package B::UV;

use B::C::Std;

use B             qw/SVf_READONLY/;
use B::C::Flags   ();
use B::C::File    qw/svsect/;
use B::C::Decimal qw/u32fmt/;

sub do_save ( $sv, $fullname = undef ) {

    $sv->FLAGS & 2048 and die sprintf( "Unexpected SVf_ROK found in %s\n", ref $sv );

    my ( $ix, $sym ) = svsect()->reserve($sv);
    svsect()->debug( $fullname, $sv );

    my $uvuformat = $B::C::Flags::Config{uvuformat};
    $uvuformat =~ s/"//g;    #" poor editor

    my $uvx  = $sv->UVX;
    my $suff = $uvx > 2147483647 ? 'UL' : 'U';

    # Since 5.24 we can access the IV/NV/UV value from either the union from the main SV body
    # or also from the SvANY of it. View IV.pm for more information

    my $flags = $sv->FLAGS;

    # special case to be able to bootstrap EV need to remove the READONLY flag
    $flags &= ~SVf_READONLY if $fullname && $fullname eq 'EV::API';

    svsect()->supdatel(
        $ix,
        "BODYLESS_UV_PTR(%s)" => $sym,           # sv_any
        u32fmt()              => $sv->REFCNT,    # sv_refcnt
        '0x%x'                => $flags,         # sv_flags
        '{.svu_uv=%s}'        => "$uvx$suff",    # sv_u.svu_uv
    );

    return $sym;
}

1;
