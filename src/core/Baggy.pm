my role Baggy does QuantHash {
    has %!elems; # key.WHICH => (key,value)

    submethod BUILD (:%!elems) { }
    method default(--> Int) { 0 }

    multi method keys(Baggy:D:)     { %!elems.values.map( {.key} ) }
    multi method kv(Baggy:D:)       { %!elems.values.map( {.key, .value} ) }
    multi method values(Baggy:D:)   { %!elems.values.map( {.value} ) }
    multi method pairs(Baggy:D:)    { %!elems.values.map: { (.key => .value) } }
    multi method antipairs(Baggy:D:) { %!elems.values.map: { (.value => .key) } }
    multi method invert(Baggy:D:)   { %!elems.values.map: { (.value => .key) } } # NB value can't be listy

    method kxxv(Baggy:D:) { %!elems.values.map( {.key xx .value} ) }
    method elems(Baggy:D: --> Int) { %!elems.elems }
    method total(--> Int) { [+] self.values }
    method Bool(Baggy:D:) { %!elems.Bool }

    method hash(Baggy:D: --> Hash) { %!elems.values.hash }

    multi method new(Baggy: \value) {
      nqp::iscont(value) || nqp::not_i(nqp::istype(value, Iterable))
        ?? self!new([value]) 
        !! self!new([|value])
    }
    multi method new(Baggy: **@args) { self!new(@args) }
    method !new(@args) {
        my %e;
        # need explicit signature because of #119609
        -> $_ { (%e{$_.WHICH} //= ($_ => 0)).value++ } for @args;
        self.bless(:elems(%e));
    }
    method new-from-pairs(*@pairs) {
        my %e;
        for @pairs {
            when Pair {
                (%e.AT-KEY($_.key.WHICH) //= ($_.key => 0)).value += $_.value.Int;
            }
            default {
                (%e.AT-KEY($_.WHICH) //= ($_ => 0)).value++;
            }
        }
        my @toolow;
        for %e -> $p {
            my $pair := $p.value;
            @toolow.push( $pair.key ) if $pair.value <  0;
            %e.DELETE-KEY($p.key)     if $pair.value <= 0;
        }
        fail "Found negative values for {@toolow} in {self.^name}" if @toolow;
        self.bless(:elems(%e));
    }

    method ACCEPTS($other) {
        self.defined
          ?? $other (<+) self && self (<+) $other
          !! $other.^does(self);
    }

    multi method Str(Baggy:D $ : --> Str) {
        ~ %!elems.values.map( {
              .value == 1 ?? .key.gist !! "{.key.gist}({.value})"
          } );
    }
    multi method gist(Baggy:D $ : --> Str) {
        my $name := self.^name;
        ( $name eq 'Bag' ?? 'bag' !! "$name.new" )
        ~ '('
        ~ %!elems.values.map( {
              .value == 1 ?? .key.gist !! "{.key.gist}({.value})"
          } ).join(', ')
        ~ ')';
    }
    multi method perl(Baggy:D $ : --> Str) {
        '('
        ~ %!elems.values.map( {"{.key.perl}=>{.value}"} ).join(',')
        ~ ").{self.^name}"
    }

    multi method list(Baggy:D:) { self.pairs }

    proto method grabpairs (|) { * }
    multi method grabpairs(Baggy:D:) {
        %!elems.DELETE-KEY(%!elems.keys.pick);
    }
    multi method grabpairs(Baggy:D: $count) {
        if nqp::istype($count,Whatever) || $count == Inf {
            my @grabbed = %!elems{%!elems.keys.pick(%!elems.elems)};
            %!elems = ();
            @grabbed;
        }
        else {
            %!elems{ %!elems.keys.pick($count) }:delete;
        }
    }

    proto method pickpairs(|) { * }
    multi method pickpairs(Baggy:D:) {
        %!elems.AT-KEY(%!elems.keys.pick);
    }
    multi method pickpairs(Baggy:D: $count) {
        %!elems{ %!elems.keys.pick(
          nqp::istype($count,Whatever) || $count == Inf
            ?? %!elems.elems
            !! $count
        ) };
    }

    proto method grab(|) { * }
    multi method grab(Baggy:D:) {
        my \grabbed := ROLLPICKGRAB1(self,%!elems.values);
        %!elems.DELETE-KEY(grabbed.WHICH)
          if %!elems.AT-KEY(grabbed.WHICH).value-- == 1;
        grabbed;
    }
    multi method grab(Baggy:D: $count) {
        if nqp::istype($count,Whatever) || $count == Inf {
            my @grabbed = ROLLPICKGRABN(self,self.total,%!elems.values);
            %!elems = ();
            @grabbed;
        }
        else {
            my @grabbed = ROLLPICKGRABN(self,$count,%!elems.values);
            for @grabbed {
                if %!elems.AT-KEY(.WHICH) -> $pair {
                    %!elems.DELETE-KEY(.WHICH) unless $pair.value;
                }
            }
            @grabbed;
        }
    }

    proto method pick(|) { * }
    multi method pick(Baggy:D:) {
        ROLLPICKGRAB1(self,%!elems.values);
    }
    multi method pick(Baggy:D: $count) {
        ROLLPICKGRABN(self,
          nqp::istype($count,Whatever) || $count == Inf ?? self.total !! $count,
          %!elems.values.map: { (.key => .value) }
        );
    }

    proto method roll(|) { * }
    multi method roll(Baggy:D:) {
        ROLLPICKGRAB1(self,%!elems.values);
    }
    multi method roll(Baggy:D: $count) {
        nqp::istype($count,Whatever) || $count == Inf
          ?? ROLLPICKGRABW(self,%!elems.values)
          !! ROLLPICKGRABN(self,$count, %!elems.values, :keep);
    }

    sub ROLLPICKGRAB1($self,@pairs) { # one time
        my Int $rand = $self.total.rand.Int;
        my Int $seen = 0;
        for @pairs -> $pair {
            return $pair.key if ( $seen += $pair.value ) > $rand;
        }
        Nil;
    }

    sub ROLLPICKGRABN(                                        # N times
      $self, $count, @pairs is rw, :$keep
    ) {
        my Int $total = $self.total;
        my Int $rand;
        my Int $seen;
        my int $todo = ($keep ?? $count !! ($total min $count)) + 1;

#?if jvm
        map {
            my $selected is default(Nil);
#?endif
#?if !jvm
        gather while $todo = $todo - 1 {
#?endif
            $rand = $total.rand.Int;
            $seen = 0;
            for @pairs -> $pair {
                next if ( $seen += $pair.value ) <= $rand;

#?if jvm
                $selected = $pair.key;
#?endif
#?if !jvm
                take $pair.key;
#?endif
                last if $keep;

                $pair.value--;
                $total = $total - 1;
                last;
            }
#?if jvm
            $selected;
        }, 2..$todo;
#?endif
#?if !jvm
        }
#?endif
    }

    sub ROLLPICKGRABW($self,@pairs) { # keep going
        my Int $total = $self.total;
        my Int $rand;
        my Int $seen;

#?if jvm
        map {
            my $selected is default(Nil);
#?endif
#?if !jvm
        gather loop {
#?endif
            $rand = $total.rand.Int;
            $seen = 0;
            for @pairs -> $pair {
                next if ( $seen += $pair.value ) <= $rand;
#?if jvm
                $selected = $pair.key;
#?endif
#?if !jvm
                take $pair.key;
#?endif
                last;
            }
#?if jvm
            $selected;
        }, *;
#?endif
#?if !jvm
        }
#?endif
    }

    proto method classify-list(|) { * }
    multi method classify-list( &test, *@list ) {
        fail X::Cannot::Lazy.new(:action<classify>) if @list.is-lazy;
        if @list {

            # multi-level classify
            if nqp::istype(test(@list[0]),Iterable) {
                for @list -> $l {
                    my @keys  = test($l);
                    my $last := @keys.pop;
                    my $bag   = self;
                    $bag = $bag{$_} //= self.new for @keys;
                    $bag{$last}++;
                }
            }

            # just a simple classify
            else {
                self{test $_}++ for @list;
            }
        }
        self;
    }
    multi method classify-list( %test, *@list ) {
        self.classify-list( { %test{$^a} }, @list );
    }
    multi method classify-list( @test, *@list ) {
        self.classify-list( { @test[$^a] }, @list );
    }

    proto method categorize-list(|) { * }
    multi method categorize-list( &test, *@list ) {
        fail X::Cannot::Lazy.new(:action<categorize>) if @list.is-lazy;
        if @list {

            # multi-level categorize
            if nqp::istype(test(@list[0])[0],List) {
                for @list -> $l {
                    for test($l) -> $k {
                        my @keys  = @($k);
                        my $last := @keys.pop;
                        my $bag   = self;
                        $bag = $bag{$_} //= self.new for @keys;
                        $bag{$last}++;
                    }
                }
            }

            # just a simple categorize
            else {
                for @list -> $l {
                    self{$_}++ for test($l);
                }
            }
        }
        self;
    }
    multi method categorize-list( %test, *@list ) {
        self.categorize-list( { %test{$^a} }, @list );
    }
    multi method categorize-list( @test, *@list ) {
        self.categorize-list( { @test[$^a] }, @list );
    }

    method Set()     {     Set.new(self.keys) }
    method SetHash() { SetHash.new(self.keys) }

    # all read/write candidates, to be shared with Mixes
    multi method DELETE-KEY(Baggy:D: \k) {
        my \v := %!elems.DELETE-KEY(k.WHICH);
        nqp::istype(v,Pair) ?? v.value !! 0;
    }
    multi method EXISTS-KEY(Baggy:D: \k)    { %!elems.EXISTS-KEY(k.WHICH) }
}

# vim: ft=perl6 expandtab sw=4
