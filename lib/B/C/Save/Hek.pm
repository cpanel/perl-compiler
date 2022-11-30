package B::C::Save::Hek;

use B::C::Std;

use B::C::File    qw(sharedhe sharedhestructs);
use B::C::Helpers qw/strlen_flags/;

use Exporter ();
our @ISA = qw(Exporter);

our @EXPORT_OK = qw/save_shared_he get_sHe_HEK/;

my %saved_shared_hash;

sub save_shared_he ($key) {

    return ( 'NULL', 0 ) unless defined $key;
    return @{ $saved_shared_hash{$key} } if $saved_shared_hash{$key};

    my $utf8 = 0;
    my ( $cur, $cstring ) = try_latin1($key);

    if ( !$cur ) {
        ( $cstring, $cur, $utf8 ) = strlen_flags($key);
    }

    _define_once($cur);

    my $index = sharedhe()->index() + 1;
    sharedhe()->sadd( "ALLOC_sHe(%d, %d, %s, %d); /* sHe%d */", $index, $cur, $cstring, $utf8 ? 1 : 0, $index );

    # cannot use sHe$ix directly as sharedhe_list is used in by init_pl_strtab and init_assign
    $saved_shared_hash{$key} = [ sprintf( q{sharedhe_list[%d]}, $index ), $cur ];

    return @{ $saved_shared_hash{$key} };
}

sub _define_once ($len) {

    sharedhestructs()->{_defined_once} //= {};

    return if sharedhestructs()->{_defined_once}->{$len};

    sharedhestructs->sadd( q{DEFINE_STATIC_SHARED_HE_STRUCT(%d);}, $len );
    sharedhestructs()->{_defined_once}->{$len} = 1;
}

sub try_latin1 ($pv) {

    my @chars = map { ord $_ } split( '', $pv );

    # Can't be converted to utf8 because one of the chars can't fit in a byte.
    return if ( grep { $_ > 255 } @chars );

    my $cstring = '';
    foreach my $char (@chars) {
        if ( $char >= 32 and $char < 128 and $char != 92 and $char != 34 ) {
            $cstring .= chr($char);
        }
        else {
            $cstring .= sprintf( '\\%03o', $char );
        }
    }

    return ( scalar @chars, qq{"$cstring"} );
}

sub get_sHe_HEK ($shared_he) {

    return q{NULL} if !defined $shared_he or $shared_he eq 'NULL';

    my $sharedhe_ix;
    if ( $shared_he =~ qr{^sharedhe_list\[([0-9]+)\]$} ) {
        $sharedhe_ix = $1;
    }

    die unless defined $sharedhe_ix;
    my $se = q{sHe} . $sharedhe_ix;

    return sprintf( q{get_sHe_HEK(%s)}, $se );
}

1;
