package B::PVLV;

use B::C::Std;

use B q/cchar/;

use B::C::File    qw/xpvlvsect svsect init/;
use B::C::Decimal qw/get_double_value/;

# Warning not covered by the (cpanel)core test suite...
# FIXME... add some test coverage for PVLV

sub do_save ( $sv, $fullname = undef ) {

    die("We know of no code that produces a PVLV. Please contact the busy camels immediately.");

}

1;

__END__

{
    my ( $ix, $sym ) = svsect()->reserve($sv);
    svsect()->debug( $fullname, $sv );

    my ( $pvsym, $cur, $len, $pv, $flags ) = $sv->save_svu( $sym, $fullname );

    xpvlvsect()->comment('xmg_stash, xmg_u, xpv_cur, xpv_len_u, xiv_u, xnv_u, xlv_targoff_u, xlv_targlen, xlv_targ, xlv_type, xlv_flags');
    my $xpv_ix = xpvlvsect()->saddl(
        "%s"   => $sv->save_magic_stash,           # xmg_stash
        "{%s}" => $sv->save_magic($fullname),      # xmg_u
        "%u"   => $cur,                            # xpv_cur
        "{%u}" => $len,                            # xpv_len_u
        "%s"   => 0,                               # xiv_u - Was 0 and labeled as 0/*GvNAME later*/
        "%s"   => get_double_value( $sv->NVX ),    # xnv_u
        "%s"   => $sv->TARGOFF,                    # xlv_targoff_u
        "%s"   => $sv->TARGLEN,                    # xlv_targlen
        "%s"   => $sv->TARG,                       # xlv_targ
        "%s"   => cchar( $sv->TYPE ),              # xlv_type
        "%d"   => $sv->LvFLAGS,                    # xlv_flags # STATIC_HV: LvFLAGS is unimplemented in B
    );

    svsect()->supdate( $ix, "&xpvlv_list[%d], %Lu, 0x%x, {%s}", xpvlvsect()->index, $sv->REFCNT, $flags, $pvsym );

    return $sym;
}

1;
