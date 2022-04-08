#!./perl

print "1..10\n";

eval q{use Devel::Peek};

{
    note("testing true");
    my $true;
    BEGIN { $true = ( 1 == 1 ) }

    my $dump = mydump($true);
    like( $dump, qr{\Q[BOOL PL_Yes]\E}, "BOOL PL_Yes" );

    ok( $true == 1, "true == 1" );
    ok( $true eq '1', "true eq '1'" );

}

{
    note("testing false");
    my $false;
    BEGIN { $false = ( 1 == 0 ) }

    my $dump = mydump($false);

    like( $dump, qr{\Q[BOOL PL_No]\E}, "BOOL PL_No" );

    ok( $false == 0, "false == 0" );
    ok( $false eq '', "false eq '' $false" );

}

{
    # Check that boolean COW string buffer is safe to copy into new SVs and
    # doesn't get corrupted by inplace mutations
    note( "Checking COW string buffer" );
    my $truevar;
    BEGIN { $truevar = ( 1 == 1 ) }

    my $x = $truevar;
    $x =~ s/1/t/;

    ok($x eq 't', "x eq 't'");
    ok($truevar eq "1", "truevar eq '1");

    my $y = $truevar;
    substr($y, 0, 1, "T");

    ok( $y eq "T", "y eq T");
    ok( $truevar eq "1", "truevar eq '1'");
}

exit;

# ... helpers ....

sub is_compiled {
    return $0 =~ qr{\.bin$} ? 1 : 0;
}

my $closed;

my $out;

sub mydump {
    $out = '';

    close STDERR;
    {
        local *STDERR;
        open STDERR, ">", \$out;

        Dump( $_[0] );
        note("[ $out ]");
    }

    return $out;
}

{
    my $_counter = 0;

    sub ok {
        my ( $t, $msg ) = @_;

        $msg ||= '';
        ++$_counter;

        if ($t) {
            print "ok $_counter - $msg\n";
            return 1;
        }
        else {
            print "not ok $_counter - $msg\n";
            return 0;
        }
    }
}

sub like {
    my ( $s, $re, $msg ) = @_;

    if ( defined $re ) {
        my $ok = $s =~ $re ? 1 : 0;
        return ok( $ok, $msg );
    }

    die;
}

sub note {
    my $s = shift;
    return unless defined $s;
    map { print "# $_\n" } split( qr{\n}, $s );    # map in void context, yea

    return;
}
