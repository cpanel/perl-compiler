package B::REGEXP;

use B::C::Std;

use B           qw/RXf_EVAL_SEEN/;
use B::C::Debug qw/debug/;
use B::C::File  qw/init1 init2 svsect xpvsect/;
use B::C::Save  qw/savecowpv/;

# post 5.11: When called from B::RV::save not from PMOP::save precomp
sub do_save ( $sv, $fullname = undef ) {

    $sv->FLAGS & 2048 and die sprintf( "Unexpected SVf_ROK found in %s\n", ref $sv );

    my ( $ix, $sym ) = svsect()->reserve($sv);
    svsect()->debug( $sv->name, $sv );

    my $pv  = $sv->PV;
    my $cur = $sv->CUR;

    # construct original PV
    $pv =~ s/^(\(\?\^[adluimsx-]*\:)(.*)\)$/$2/;
    $cur -= length( $sv->PV ) - length($pv);
    my ( $cstr, undef, undef ) = savecowpv($pv);

    my $magic_stash = $sv->save_magic_stash;
    my $magic       = $sv->save_magic($fullname);

    # Unfortunately this XPV is needed temp. Later replaced by struct regexp.
    my $xpv_ix = xpvsect()->saddl(
        "%s"   => $magic_stash,    # xmg_stash
        "{%s}" => $magic,          # xmg_u
        "%u"   => $cur,            # xpv_cur
        "{%u}" => 0                # xpv_len_u STATIC_HV: length is 0 ???
    );
    my $xpv_sym = sprintf( "&xpv_list[%d]", $xpv_ix );

    my $initpm = init1();

    if ( $pv =~ m/\\[pN]\{/ or $pv =~ m/\\U/ ) {
        $initpm = init2();
    }

    svsect()->supdate( $ix, "%s, %Lu, 0x%x, {NULL}", $xpv_sym, $sv->REFCNT, $sv->FLAGS );
    debug( rx => "Saving RX $cstr to sv_list[$ix]" );

    # replace sv_any->XPV with struct regexp. need pv and extflags
    $initpm->open_block();

    # Re-compile into an SV.
    $initpm->add("PL_hints |= HINT_RE_EVAL;") if ( $sv->EXTFLAGS & RXf_EVAL_SEEN );
    $initpm->sadd( 'REGEXP* regex_sv = CALLREGCOMP(newSVpvn( %s, %d), 0x%x);', $cstr, $cur, $sv->EXTFLAGS );
    $initpm->add("PL_hints &= ~HINT_RE_EVAL;") if ( $sv->EXTFLAGS & RXf_EVAL_SEEN );

    $initpm->sadd( 'SvANY(%s) = SvANY(regex_sv);',                                  $sym );    # copy the SvAny
    $initpm->sadd( "((SV*) %s)->sv_u.svu_pv = (char *) SvPV_nolen((SV*)regex_sv);", $sym );    # copy the pv

    my $without_amp = $sym;
    $without_amp =~ s/^&//;

    # not set
    #$initpm->sadd( "((XPV*)SvANY(%s))->xpv_len_u.xpvlenu_rx = (struct regexp*)SvANY(regex_sv);", $sym );

    $initpm->sadd( "ReANY(%s)->xmg_stash =  %s;",       $sym, $magic_stash );
    $initpm->sadd( "ReANY(%s)->xmg_u.xmg_magic =  %s;", $sym, $magic );

    $initpm->close_block();

    return $sym;
}

1;
