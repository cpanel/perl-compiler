package # do not index it
        B::NV;

use B::C::Std;

use B q/SVf_IOK/;

use B::C::Debug   qw/debug/;
use B::C::File    qw/xpvnvsect svsect/;
use B::C::Decimal qw/get_double_value/;

# TODO NVs should/could be bodyless ? view IVs, UVs
sub do_save ( $sv, $fullname, $custom = undef ) {

    my $svflags = $sv->FLAGS;
    my $refcnt  = $sv->REFCNT;
    $sv->FLAGS & 2048 and die sprintf( "In B::NV, unexpected SVf_ROK found in %s\n", ref $sv );

    if ( ref $custom ) {    # used when downgrading a PVIV / PVNV to IV
        $svflags = $custom->{flags}  if defined $custom->{flags};
        $refcnt  = $custom->{refcnt} if defined $custom->{refcnt};
    }

    my $nv = get_double_value( $sv->NV );
    $nv .= '.00' if $nv =~ /^-?\d+$/;

    my ( $ix, $sym ) = svsect()->reserve($sv);
    svsect()->debug( $fullname, $sv );

    # Since 5.24 we can access the IV/NV/UV value from either the union from the main SV body
    # or also from the SvANY of it. View IV.pm for more information

    svsect()->supdatel(
        $ix,
        'BODYLESS_NV_PTR(%s)' => $sym,        # sv_any NOTE we're not pointing top NV_PTR
        '%lu',                => $refcnt,     # sv_refcnt
        '0x%x'                => $svflags,    # sv_flags
        '{.svu_nv=%s}'        => $nv,         # sv_u.svu_nv
    );
    return $sym;
}

1;
