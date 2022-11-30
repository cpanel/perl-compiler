package B::CV;

use B::C::Std;

use B                       qw/CVf_CONST main_cv SVf_IsCOW CVf_NAMED/;
use B::C::Debug             qw/verbose/;
use B::C::Decimal           qw/get_integer_value/;
use B::C::Save              qw/savecowpv/;
use B::C::Save::Hek         qw/save_shared_he get_sHe_HEK/;
use B::C::File              qw/svsect xpvcvsect xsaccessorsect init_xsaccessor init/;
use B::C::Helpers::Symtable qw/objsym/;

my $initsub_index = 0;
my $anonsub_index = 0;

sub SVt_PVFM { 14 }            # not exported by B
sub SVs_RMG  { 0x00800000 }    # has random magical methods

my %xs_accessor_methods = map { $_ => undef } qw/getter lvalue_accessor setter chained_setter accessor chained_accessor defined_predicate exists_predicate constant_true constant_false test/;
my $xs_accessor_constructor;

# from B.xs maybe we need to save more than just the RMG ones
#define MAGICAL_FLAG_BITS (SVs_GMG|SVs_SMG|SVs_RMG)

sub do_save ( $cv, $origname = undef ) {

    my $fullname = $cv->FULLNAME();

    # do not save BEGIN and CHECK functions
    return 'NULL' if $fullname =~ qr{::(?:BEGIN|CHECK|UNITCHECK)$};

    $cv->FLAGS & 2048 and die sprintf( "Unexpected SVf_ROK found in %s\n", ref $cv );

    my $is_xs_accessor_constructor = $cv->is_xs_accessor_constructor;
    my ( $xsaccessor_list, $xsaccessor_function, $xsaccessor_key, $xsaccessor_key_len ) = $cv->save_xs_accessor($is_xs_accessor_constructor);

    if ( !$is_xs_accessor_constructor && !$xsaccessor_list && !$cv->CONST && $cv->XSUB ) {    # xs function
        $fullname =~ s{^main::}{};

        B::C::found_xs_sub($fullname);
        return "BOOTSTRAP_XS_[[${fullname}]]_XS_BOOTSTRAP";
    }

    my ( $ix, $sym ) = svsect()->reserve($cv);
    svsect()->debug( $fullname, $cv );

    my $presumed_package = $origname;
    $presumed_package =~ s/::[^:]+$// if $presumed_package;

    # We only have a stash if NAME_HEK isn't in place. this happens when we're off an RV instead of a GV.
    my $flags = $cv->FLAGS;

    # need to survive cv_undef as there is no protection against static CVs
    my $refcnt = $cv->REFCNT;

    my $root = $cv->get_ROOT;

    # Setup the PV for the SV here cause we need to set cur and len.
    my $pv  = 'NULL';
    my $cur = $cv->CUR;
    my $len = $cv->LEN;

    if ( defined $cv->PV ) {
        ( $pv, $cur, $len ) = savecowpv( $cv->PV );
        $pv    = "(char *) $pv";
        $flags = $flags | SVf_IsCOW;
    }

    my $xcv_outside = $cv->get_cv_outside();

    my ( $xcv_file, undef, undef ) = savecowpv( $cv->FILE || '' );

    my ( $xcv_root, $startfield );
    if ($is_xs_accessor_constructor) {
        $xcv_root   = 'NULL';
        $startfield = "0";
    }
    elsif ($xsaccessor_list) {
        $xcv_root   = 'NULL';
        $startfield = sprintf( '.xcv_xsubany= {(void*) %s /* xsubany */}', $xsaccessor_list );    # xcv_xsubany
    }
    elsif ( my $c_function = $cv->can_do_const_sv() ) {
        $xcv_root   = sprintf( '.xcv_xsub=&%s',                            $c_function );
        $startfield = sprintf( '.xcv_xsubany= {(void*) %s /* xsubany */}', $cv->XSUBANY->save() );    # xcv_xsubany
    }
    else {                                                                                            # default values for xcv_root and startfield
        $xcv_root   = sprintf( "%s", $root ? $root->save : 0 );
        $startfield = $cv->save_optree();
    }

    xpvcvsect->comment("xmg_stash, xmg_u, xpv_cur, xpv_len_u, xcv_stash, xcv_start_u, xcv_root_u, xcv_gv_u, xcv_file, xcv_padlist_u, xcv_outside, xcv_outside_seq, xcv_flags, xcv_depth");
    my $xpvcv_ix = xpvcvsect->saddl(
        '%s'          => $cv->save_magic_stash,                    # xmg_stash
        '{%s}'        => $cv->save_magic($origname),               # xmg_u
        '%u'          => $cur,                                     # xpv_cur -- warning this is not CUR and LEN for the pv
        '{%u}'        => $len,                                     # xpv_len_u -- warning this is not CUR and LEN for the pv
        '%s'          => $cv->save_stash,                          # xcv_stash
        '{%s}'        => $startfield,                              # xcv_start_u --- OP *    xcv_start; or ANY xcv_xsubany;
        '{%s}'        => $xcv_root,                                # xcv_root_u  --- OP *    xcv_root; or void    (*xcv_xsub) (pTHX_ CV*);
        q{%s}         => $cv->get_xcv_gv_u,                        # $xcv_gv_u, # xcv_gv_u
        q{(char*) %s} => $xcv_file,                                # xcv_file
        '{%s}'        => $cv->cv_save_padlist($origname),          # xcv_padlist_u
        '(CV*)%s'     => $xcv_outside,                             # xcv_outside
        '%d'          => get_integer_value( $cv->OUTSIDE_SEQ ),    # xcv_outside_seq
        '0x%x'        => $cv->CvFLAGS,                             # xcv_flags
        '%d'          => $cv->DEPTH                                # xcv_depth
    );

    # svsect()->comment("any=xpvcv, refcnt, flags, sv_u");
    svsect->supdate( $ix, "(XPVCV*)&xpvcv_list[%u], %Lu, 0x%x, {%s}", $xpvcv_ix, $cv->REFCNT, $flags, $pv );

    if ($is_xs_accessor_constructor) {
        init_xsaccessor->setup_method_for(
            xpvcv_ix => $xpvcv_ix,                           #.
            xs_sub   => "Class::XSAccessor::constructor",    #.
            fullname => $fullname                            #.
        );
    }
    elsif ($xsaccessor_list) {

        init_xsaccessor->setup_method_for(
            xpvcv_ix => $xpvcv_ix,
            xs_sub   => $xsaccessor_function,
            fullname => $fullname,

            xsaccessor_entry   => $xsaccessor_list,          # bad name
            xsaccessor_key     => $xsaccessor_key,
            xsaccessor_key_len => $xsaccessor_key_len,
        );
    }

    return $sym;
}

{
    my %_const_sv_function = map { $_ => 'bc_const_sv_xsub' } qw{B::IV B::UV B::PV B::PVIV B::PVUV};

    sub can_do_const_sv ($cv) {

        die    unless $cv;
        return unless $cv->CONST && $cv->XSUB;
        my $xsubany = $cv->XSUBANY;
        my $ref     = ref $cv->XSUBANY;
        return if !$ref || $ref eq 'B::SPECIAL';

        return unless exists $_const_sv_function{$ref};

        #die "CV CONST XSUB is not implemented for $ref" unless exists $_const_sv_function{$ref};
        return $_const_sv_function{$ref};
    }
}

sub is_xs_accessor_constructor ($cv) {

    return unless $INC{'Class/XSAccessor.pm'};
    my $name = $cv->FULLNAME;
    return if $name && index( $name, 'Class::XSAccessor::' ) == 0;
    my $xsub = $cv->XSUB or return;

    $xs_accessor_constructor //= B::svref_2object( \&Class::XSAccessor::constructor )->XSUB;
    return unless "$xsub" eq "$xs_accessor_constructor";

    return 1;
}

sub save_xs_accessor ( $cv, $ = undef ) {

    return unless $INC{'Class/XSAccessor.pm'};
    my $name = $cv->FULLNAME;
    return if $name && index( $name, 'Class::XSAccessor::' ) == 0;
    my $xsub = $cv->XSUB or return;
    my $method_found;

    no strict 'refs';
    foreach my $method ( sort keys %xs_accessor_methods ) {
        $xs_accessor_methods{$method} //= B::svref_2object( \*{"Class::XSAccessor::$method"} )->CV->XSUB;
        next unless "$xsub" eq "$xs_accessor_methods{$method}";
        $method_found = $method;
        last;
    }
    return unless $method_found;

    my ( $key, $key_cur, undef ) = savecowpv( $cv->get_xs_accessor_key );

    xsaccessorsect->comment( "HKEY", "key", "key len" );
    my $xsa_ix = xsaccessorsect->saddl(
        "%d", 0,
        "%s", $key,
        "%d", $key_cur,
    );

    return ( "&xsaccessor_list[$xsa_ix]", "Class::XSAccessor::$method_found", $key, $key_cur );
}

sub save_stash ($cv) {

    $cv->STASH or return 'Nullhv';

    my $symbol = $cv->STASH->save;
    $symbol = q{Nullhv}       if $symbol eq 'Nullsv';
    $symbol = "(HV*) $symbol" if $symbol ne 'Nullhv';

    return $symbol;
}

sub get_cv_outside ($cv) {

    my $ref = ref( $cv->OUTSIDE );

    return 0 unless $ref;

    if ( $ref eq 'B::CV' ) {
        $cv->FULLNAME or return 0;

        return $cv->OUTSIDE->save if $cv->CvFLAGS & 0x100;

        return 0 if ${ $cv->OUTSIDE } ne ${ main_cv() } && !$cv->is_format;
    }

    return $cv->OUTSIDE->save;
}

sub is_format ($cv) {

    my $format_mask = SVt_PVFM() | SVs_RMG();
    return ( $cv->FLAGS & $format_mask ) == $format_mask ? 1 : 0;
}

sub cv_save_padlist ( $cv, $origname ) {

    my $padlist = $cv->PADLIST;

    $$padlist or return 'NULL';
    my $fullname = $cv->get_full_name($origname);

    return $padlist->save( $fullname . ' :pad', $cv );
}

sub get_full_name ( $cv, $origname ) {

    my $fullname = $cv->NAME_HEK || '';
    return $fullname if $fullname;

    my $gv     = $cv->GV;
    my $cvname = '';
    if ( $gv and $$gv ) {
        $cvname = $gv->NAME;
        my $cvstashname = $gv->STASH->NAME;
        $fullname = $cvstashname . '::' . $cvname;

        # XXX gv->EGV does not really help here
        if ( $cvname eq '__ANON__' ) {
            if ($origname) {
                $cvname = $fullname = $origname;
                $cvname =~ s/^\Q$cvstashname\E::(.*)( :pad\[.*)?$/$1/ if $cvstashname;
                $cvname =~ s/^.*:://;
                if ( $cvname =~ m/ :pad\[.*$/ ) {
                    $cvname =~ s/ :pad\[.*$//;
                    $cvname   = '__ANON__' if is_phase_name($cvname);
                    $fullname = $cvstashname . '::' . $cvname;
                }
            }
            else {
                $cvname   = $gv->EGV->NAME;
                $fullname = $cvstashname . '::' . $cvname;
            }
        }

    }
    elsif ( $cv->is_lexsub($gv) ) {
        $fullname = $cv->NAME_HEK;
        $fullname = '' unless defined $fullname;
    }

    my $isconst = $cv->CvFLAGS & CVf_CONST;
    if ( !$isconst && $cv->XSUB && ( $cvname ne "INIT" ) ) {
        my $egv       = $gv->EGV;
        my $stashname = $egv->STASH->NAME;
        $fullname = $stashname . '::' . $cvname;
    }

    return $fullname;

}

sub get_xcv_gv_u ($cv) {

    # $cv->CvFLAGS & CVf_NAMED
    if ( my $pv = $cv->NAME_HEK ) {
        my ($share_he) = save_shared_he($pv);
        my $xcv_gv_u = sprintf( "{.xcv_hek=%s}", get_sHe_HEK($share_he) );      # xcv_gv_u
        return $xcv_gv_u;
    }

    #GV (.xcv_gv)
    my $xcv_gv_u = $cv->GV ? $cv->GV->save : 'Nullsv';

    $xcv_gv_u = 0 if $xcv_gv_u eq 'Nullsv';

    return sprintf( "{.xcv_gv=%s}", $xcv_gv_u );
}

sub get_ROOT ($cv) {

    my $root = $cv->ROOT;
    return ref $root eq 'B::NULL' ? undef : $root;
}

sub save_optree ($cv) {

    my $root = $cv->get_ROOT;

    return 0 unless ( $root && $$root );

    verbose() ? B::walkoptree_slow( $root, "save" ) : B::walkoptree( $root, "save" );
    my $startfield = objsym( $cv->START );

    $startfield = objsym( $root->next ) unless $startfield;    # 5.8 autoload has only root
    $startfield = "0"                   unless $startfield;    # XXX either CONST ANON or empty body

    return $startfield;
}

sub is_lexsub ( $cv, $gv ) {

    # logical shortcut perl5 bug since ~ 5.19: testcc.sh 42
    return ( ( !$gv or ref($gv) eq 'B::SPECIAL' ) and $cv->can('NAME_HEK') ) ? 1 : 0;
}

sub is_phase_name ($phase) {
    return $phase =~ /^(BEGIN|INIT|UNITCHECK|CHECK|END)$/ ? 1 : 0;
}

sub FULLNAME ($cv) {

    #return q{PL_main_cv} if $cv eq ${ main_cv() };
    # Do not coerce a RV into a GV during compile by calling $cv->GV on something with a NAME_HEK (RV)
    my $name = $cv->NAME_HEK;
    return $name if ($name);

    my $gv = $cv->GV;
    return q{SPECIAL} if ref $gv eq 'B::SPECIAL';

    return $gv->FULLNAME;
}

1;
