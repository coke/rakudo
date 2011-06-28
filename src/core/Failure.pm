my class Failure {
    has $!exception;
    has $!handled;

    method new($ex) {
        my $new = self.CREATE;
        $new.BUILD($ex);
    }

    method BUILD($ex) {
        $!exception = $ex;
        self;
    }

    # TODO: should be Failure:D: multi just like method Bool,
    # but obscure problems prevent us from making Mu.defined
    # a multi. See http://irclog.perlgeek.de/perl6/2011-06-28#i_4016747
    method defined() {
        $!handled =1 if nqp::p6bool(pir::repr_defined__IP(self));
        0.Bool;
    }
    multi method Bool(Failure:D:) { $!handled = 1; 0.Bool; }

    proto method Int(|$) {*}
    multi method Int(Failure:D:) { $!handled ?? 0 !! $!exception.rethrow; }
    proto method Num(|$) {*}
    multi method Num(Failure:D:) { $!handled ?? 0e0 !! $!exception.rethrow; }
    proto method Str(|$) {*}
    multi method Str(Failure:D:) { $!handled ?? '' !! $!exception.rethrow; }
}


my &fail := -> *@msg {
    my $value = @msg.join('');
    my Mu $ex := Q:PIR {
                     # throw and immediately catch an exception, to capture
                     # the location at the point of the fail()
                     push_eh catch
                     $P0 = find_lex '$value'
                     $S0 = $P0
                     die $S0
                   catch:
                     .get_results (%r)
                     pop_eh
                 };
    my $fail = Failure.new(EXCEPTION($ex));
    my Mu $return := pir::find_caller_lex__Ps('RETURN');
    $return($fail) unless nqp::isnull($return);
    $fail
}


