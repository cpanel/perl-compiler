#!./perl

print "1..1\n";

sub check {
    my ($c) = @_;

    # the IV '8' is upgraded to PVIV, and can be incorrectly stored from B::C
    #   forcing a downgrade solves the issue
    die q[Not Reachable] if $c eq 8;
}

sub call_check {
    check(undef);
}

call_check();
BEGIN { call_check() }

print "ok\n";
