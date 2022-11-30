package B::PV;

use B::C::Std;

use B               qw/SVf_IsCOW SVf_ROK SVf_POK SVp_POK SVs_GMG SVt_PVGV SVf_READONLY SVf_FAKE/;
use B::C::Debug     qw/debug/;
use B::C::Save      qw/savecowpv/;
use B::C::Save::Hek qw/save_shared_he get_sHe_HEK/;
use B::C::File      qw/xpvsect svsect free/;
use B::C::Helpers   qw/is_shared_hek/;

sub SVpbm_VALID { 0x40000000 }
sub SVp_SCREAM  { 0x00008000 }    # method name is DOES

sub do_save ( $sv, $fullname = undef, $custom = undef ) {

    #if ( !length $fullname ) {
    #    print STDERR B::C::Save::stack_flat();
    #    die("B::PV requires a \$fullname be passed to save please!");
    #}

    my ( $ix, $sym ) = svsect()->reserve($sv);
    svsect()->debug( $fullname, $sv );

    my $shared_hek = is_shared_hek($sv);

    my ( $savesym, $cur, $len, $pv, $flags ) = $sv->save_svu( $sym, $fullname );

    # sv_free2 problem with !SvIMMORTAL and del_SV
    my $refcnt = $sv->REFCNT;
    if ( $fullname && $fullname eq 'svop const' ) {
        $refcnt = 0x7fffffff;
    }

    if ( ref $custom ) {    # used when downgrading a PVIV / PVNV to IV
        $flags  = $custom->{flags}  if defined $custom->{flags};
        $refcnt = $custom->{refcnt} if defined $custom->{refcnt};
        $flags &= $custom->{update_flags} if defined $custom->{update_flags};
    }

    # static pv, do not destruct. test 13 with pv0 "3".
    if ( !$shared_hek and $flags & SVf_READONLY and !$len ) {
        $flags ^= SVf_FAKE;    # turn off SVf_FAKE
        debug( pv => "turn off SVf_FAKE %s %s\n", $pv, $fullname );
    }

    my $xpv_sym = 'NULL';
    if ( $sv->HAS_ANY ) {
        xpvsect()->comment("stash, magic, cur, len");
        my $xpv_ix = xpvsect()->sadd( "Nullhv, {0}, %u, {%u}", $cur, $len );

        $xpv_sym = sprintf( '&xpv_list[%d]', $xpv_ix );
    }

    svsect()->comment("any, refcnt, flags, sv_u");
    my $sv_ix = svsect()->supdatel(
        $ix,
        '%s'   => $xpv_sym,
        '%Lu'  => $refcnt,
        '0x%x' => $flags,
        '{%s}' => $savesym
    );

    return $sym;
}

sub save_svu ( $sv, $sym, $fullname, @ ) {

    my $flags = $sv->FLAGS;

    # This is an RV so the svu points to another SV.
    if ( $flags & SVf_ROK ) {
        my $savesym = B::RV::save_rv( $sv, $sym, $fullname );

        my $flags = $sv->FLAGS;

        # GV should never have an ROK flag. that's just wierd.
        die( sprintf( "Unexpected Flags (0x%x) for %s in save_svu for ROK\n", $flags, ref $sv ) ) if ( $flags & SVt_PVGV ) == SVt_PVGV;

        my $pv = "RV DEBUG ONLY STRING";
        $savesym = ".svu_rv=$savesym";
        return ( $savesym, $sv->CUR, $sv->LEN, $pv, $flags );
    }

    if ( $sv->IsBool ) {

        # bool values are only sharing the PVX at this point
        my $pv = $sv->IsBoolYes ? 'PL_Yes' : 'PL_No';
        return ( ".svu_pv=(char*) $pv", $sv->CUR, $sv->LEN, $pv, $sv->FLAGS );
    }

    my $pok = $flags & ( SVf_POK | SVp_POK );
    my $gmg = $flags & SVs_GMG;

    my $shared_hek = is_shared_hek($sv);

    # Our svu points to a shared_hek.
    if ($shared_hek) {
        my $pv = $sv->PV;
        my ( $shared_he, $cur ) = save_shared_he($pv);    # we know that a shared_hek as POK
        my $len = 0;

        return ( ".svu_pv=(char*)(" . get_sHe_HEK($shared_he) . q{)->hek_key}, $cur, $len, $pv, $flags );
    }

    my $pv = "";
    my ( $savesym, $cur, $len ) = savecowpv($pv);

    # overloaded VERSION symbols fail to xs boot: ExtUtils::CBuilder with Fcntl::VERSION (i91)
    # 5.6: Can't locate object method "RV" via package "B::PV" Carp::Clan
    if ($pok) {
        $pv  = pack "a*", $sv->PV;    # XXX!
        $cur = ( $sv and $sv->can('CUR') and ref($sv) ne 'B::GV' ) ? $sv->CUR : length($pv);
    }
    else {
        if ( $gmg && $fullname ) {
            no strict 'refs';
            $pv  = ( $fullname and ref($fullname) ) ? "${$fullname}" : '';
            $cur = length( pack "a*", $pv );
            $pok = 1;
        }
    }

    if ($pok) {
        ( $savesym, $cur, $len ) = savecowpv($pv);    # only flags as COW if it's not a reference and not an empty string
        $flags |= SVf_IsCOW;
    }
    else {
        $flags ^= SVf_IsCOW;
    }

    $fullname = '' if !defined $fullname;

    if ( $fullname =~ m{^(.+)::AUTOLOAD$} ) {
        my $pkg = $1;
        if ( $pkg->can('AUTOLOAD') ) {

            # clear AUTOLOAD PV when used at compile time
            #print STDERR "## $fullname has AUTOLOAD sub\n";
            $savesym = 'NULL';
            $cur     = 0;
            $len     = 0;
            $pv      = '';
            $flags   = 0;
        }
    }

    debug( pv => "Saving pv %s %s cur=%d, len=%d, %s", $savesym, $pv, $cur, $len, $shared_hek ? "shared, $fullname" : $fullname );

    $savesym = ".svu_pv=(char*) $savesym";
    return ( $savesym, $cur, $len, $pv, $flags );
}

1;
