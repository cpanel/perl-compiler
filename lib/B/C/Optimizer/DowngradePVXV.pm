package B::C::Optimizer::DowngradePVXV;

use B::C::Std;

use B::C::Decimal qw/get_integer_value intmax/;
use B             qw{SVf_NOK SVp_NOK SVs_OBJECT SVf_IOK SVf_ROK SVf_POK SVp_POK SVp_IOK SVf_IsCOW SVf_READONLY SVs_PADSTALE SVs_PADTMP SVf_PROTECT};

use Exporter ();
our @ISA = qw(Exporter);

our @EXPORT_OK = qw/downgrade_pviv downgrade_pvnv/;

# we need to keep them in memory to do not reuse the same memory location
my @EXTRA;

sub SVt_IV   { 1 }
sub SVt_NV   { 2 }
sub SVt_PV   { 3 }
sub SVt_PVIV { 5 }
sub SVt_PVNV { 6 }
sub SVt_MASK { 0xf }    # smallest bitmask that covers all types

my $DEBUG = 0;

my $REGEXP_INTEGER = qr{^(?:[1-9][0-9]*|0)\z};

sub ddebug (@what) {
    return unless $DEBUG;

    local %ENV;    # avoid error with taint from op/taint.t
    my $msg = join ' ', map { defined $_ ? $_ : 'undef' } @what;

    qx{/usr/bin/echo '$msg' >> /tmp/downgrade};
    return 1;
}

sub is_simple_pviv ($sv) {

    my $flags = $sv->FLAGS;

    return if ( $flags & SVf_ROK ) == SVf_ROK;
    return if ( $flags & SVt_MASK ) != SVt_PVIV();

    # downgrade to IV if private_POK is set without having the public POK set
    return 1 if ( $flags & SVp_POK && !( $flags & SVf_POK ) );

    # remove insignificant flags for us as a PVIV
    $flags &= ~SVf_IsCOW if $flags & SVp_POK;
    $flags &= ~SVf_IOK;
    $flags &= ~SVf_POK;
    $flags &= ~SVp_IOK;
    $flags &= ~SVp_POK;
    $flags &= ~SVf_READONLY;
    $flags &= ~SVf_PROTECT;

    # remove the type
    $flags &= ~SVt_MASK();

    ddebug( "PVIV with flags", $flags ) if $flags;

    return $flags == 0;
}

sub is_simple_pvnv ($sv) {    # should factorize this with the other is_simple funcion, once ready

    my $flags = $sv->FLAGS;

    return if ( $flags & SVf_ROK ) == SVf_ROK;
    return if ( $flags & SVt_MASK ) != SVt_PVNV();

    return if $sv->IsBool;

    # remove insignificant flags for us as a PVIV
    $flags &= ~SVf_IsCOW if $flags & SVp_POK;
    $flags &= ~SVf_IOK;
    $flags &= ~SVf_POK;
    $flags &= ~SVf_NOK;
    $flags &= ~SVp_IOK;
    $flags &= ~SVp_POK;
    $flags &= ~SVp_NOK;

    # bonus ?
    $flags &= ~SVf_READONLY;
    $flags &= ~SVs_PADSTALE;
    $flags &= ~SVs_PADTMP;
    $flags &= ~SVf_PROTECT;

    # remove the type
    $flags &= ~SVt_MASK();

    ddebug( "PVNV with flags", $flags ) if $flags;

    return $flags == 0;
}

sub custom_flags ( $sv, $type = 0 ) {

    $type ||= 0;

    # remove the current type
    my $flags = $sv->FLAGS & ~SVt_MASK();

    # use the new type
    $flags |= $type;

    if ( $type == SVt_IV() ) {
        $flags |= ( SVf_IOK | SVp_IOK );

        $flags &= ~SVf_NOK;
        $flags &= ~SVp_NOK;
        $flags &= ~SVf_POK;
        $flags &= ~SVp_POK;

    }
    elsif ( $type == SVt_NV() ) {
        $flags |= ( SVf_NOK | SVp_NOK );

        $flags &= ~SVf_IOK;
        $flags &= ~SVp_IOK;
        $flags &= ~SVf_POK;
        $flags &= ~SVp_POK;

    }
    elsif ( $type == SVt_PV() ) {
        $flags |= ( SVf_POK | SVp_POK | SVf_IsCOW );

        $flags &= ~SVf_IOK;
        $flags &= ~SVp_IOK;
        $flags &= ~SVf_NOK;
        $flags &= ~SVp_NOK;
    }

    return $flags;
}

sub downgrade_pviv ( $sv, $fullname ) {

    return unless is_simple_pviv($sv);

    my $iok  = $sv->FLAGS & SVf_IOK;
    my $pok  = $sv->FLAGS & SVf_POK;
    my $ppok = $sv->FLAGS & SVp_POK;

    return if $iok && $pok && $sv->PV ne $sv->IVX;

    if ( $ppok && !$pok ) {
        my $can_downgrade_to_iv = $sv->can_downgrade_to_iv;
        ddebug( "- PVIV downgrade skipped - can downgrade %d", _sv_to_str($sv), $can_downgrade_to_iv );
        return unless $can_downgrade_to_iv;
    }

    #tidyoff
    if (  !$pok && $iok
        or $iok && $sv->PV =~ $REGEXP_INTEGER ) {    # PVIV used as IV let's downgrade it as an IV
        ddebug("downgrade PVIV to IV - case a");

        push @EXTRA, int get_integer_value( $sv->IVX );
        my $sviv = B::svref_2object( \$EXTRA[-1] );
        return B::IV::save( $sviv, $fullname, { flags => custom_flags( $sv, SVt_IV() ), refcnt => $sv->REFCNT } );

        #return B::IV::save( $sviv, $fullname );
    }
    elsif ( $pok && $sv->PV =~ $REGEXP_INTEGER && length( $sv->PV ) <= 18 ) {    # use Config{...}
        ddebug("downgrade PVIV to IV - case b");

        # downgrade a PV that looks like an IV (and not too long) to a simple IV
        push @EXTRA, int( "" . $sv->PV );
        my $sviv = B::svref_2object( \$EXTRA[-1] );
        return B::IV::save( $sviv, $fullname, { flags => custom_flags( $sv, SVt_IV() ), refcnt => $sv->REFCNT } );
    }
    elsif ($pok) {                                                               # maybe do not downgrade it to PV if the string is only 0-9 ??
        ddebug("downgrade the PVIV as a regular PV");
        push @EXTRA, "" . $sv->PV;
        my $svpv = B::svref_2object( \$EXTRA[-1] );
        return B::PV::save( $svpv, $fullname, { flags => custom_flags( $sv, SVt_PV() ), refcnt => $sv->REFCNT } );
    }
    else {
        ddebug( sprintf( "downgrade PVIV skipped ? %s", _sv_to_str($sv) ) );
    }

    #tidyon

    return;
}

sub downgrade_pvnv ( $sv, $fullname ) {

    return unless is_simple_pvnv($sv);

    my $iok = $sv->FLAGS & SVf_IOK;
    my $nok = $sv->FLAGS & SVf_NOK;
    my $pok = $sv->FLAGS & SVf_POK;

    my $ppok = $sv->FLAGS & SVp_POK;

    return if $iok && $pok && $sv->PV ne $sv->IVX;
    return if $nok && $pok && $sv->PV ne $sv->NV;

    # do not mess with large numbers
    if ( $ppok && $nok && ( $sv->NV > intmax() or $sv->NV < -intmax() ) ) {

        #ddebug("- XXX PVNV downgrade skipped ", _sv_to_str($sv), intmax() );
        return;
    }

    # if the PV is private abort.. in some cases
    if ( $ppok && !$pok or $ppok && ( $sv->FLAGS & SVf_IsCOW ) ) {

        #ddebug("- PVNV downgrade skipped ", _sv_to_str($sv));
        return;
    }

    return unless $iok or $nok or $pok;    # SVs_PADSTALE ?

    #tidyoff
    if (
        $nok && $sv->NV =~ $REGEXP_INTEGER && length( $sv->NV ) <= 18    # !$pok && !$iok &&
      ) {                                                                # PVNV used as IV let's downgrade it as an IV
                                                                         #return;
        ddebug( "downgrade PVNV to IV from NV - case a", _sv_to_str($sv) );

        #eval q{use Devel::Peek}; Dump($sv);
        return if $sv->NV == 0;
        push @EXTRA, int $sv->NV;
        my $sviv = B::svref_2object( \$EXTRA[-1] );
        do { ddebug("WARN: invalid B::IV when downgrading PVNV"); return } unless ref $sviv eq 'B::IV';
        return B::IV::save( $sviv, $fullname, { flags => custom_flags( $sv, SVt_IV() ), refcnt => $sv->REFCNT } );
    }
    elsif ( $pok && $sv->PV =~ $REGEXP_INTEGER && length( $sv->PV ) <= 18 ) {
        ddebug("downgrade PVNV to IV - case b");
        push @EXTRA, int( "" . $sv->PV );
        my $sviv = B::svref_2object( \$EXTRA[-1] );
        do { ddebug("WARN: invalid B::IV when downgrading PVNV"); return } unless ref $sviv eq 'B::IV';
        return B::IV::save( $sviv, $fullname, { flags => custom_flags( $sv, SVt_IV() ), refcnt => $sv->REFCNT } );
    }
    elsif ($iok) {    # && $sv->IVX =~ $REGEXP_INTEGER
        ddebug("downgrade PVNV to IV - case d");
        push @EXTRA, int( "" . $sv->IV );
        my $sviv = B::svref_2object( \$EXTRA[-1] );
        return B::IV::save( $sviv, $fullname, { flags => custom_flags( $sv, SVt_IV() ), refcnt => $sv->REFCNT } );
    }
    elsif ($nok) {

        # need to be sure that the PV is set: checking its length
        if ( length( $sv->PV ) && ( $sv->NV // '' ) ne ( $sv->PV // '' ) ) {

            # for example, we do not want to convert to NV $] = PV 5.025010 , NV 5.02501 or we would lost the 0 padding
            #   ( also true for any other similar variable 'our $X; BEGIN { $X = $] };' )
            ddebug( "Cannot downgrade PVNV to NV - case e: NV and PV differ", 'NV:', $sv->NV, 'PV: ', $sv->PV );
            return;
        }

        ddebug( "downgrade PVNV to NV - case e", _sv_to_str($sv) );

        push @EXTRA, $sv->NV;
        my $svnv = B::svref_2object( \$EXTRA[-1] );

        #debug( "Value ?? %s", )
        do { ddebug("WARN: invalid B::NV when downgrading PVNV"); return } unless ref $svnv eq 'B::NV';
        return B::NV::save( $svnv, $fullname, { flags => custom_flags( $sv, SVt_NV() ), refcnt => $sv->REFCNT } );
    }
    else {
        ddebug( sprintf( "downgrade PVNV skipped ? %s", _sv_to_str($sv) ) );
    }

    # elsif ($pok) {                                                            # maybe do not downgrade it to PV if the string is only 0-9 ??
    #                                                                           # downgrade the PVIV as a regular PV
    #     ddebug("downgrade PVNV to IV - case c");
    #     push @EXTRA, "" . $sv->PV;
    #     my $svpv = B::svref_2object( \$EXTRA[-1] );
    #     return B::PV::save( $svpv, $fullname );
    # }

    #tidyon

    return;
}

# debug helper
sub _sv_to_str ($sv) {

    my ( $flags, $values ) = ( '', '' );

    my $iok  = $sv->FLAGS & SVf_IOK;
    my $nok  = $sv->FLAGS & SVf_NOK;
    my $pok  = $sv->FLAGS & SVf_POK;
    my $ppok = $sv->FLAGS & SVp_POK;

    if ($iok) {
        $flags  .= 'IOK ';
        $values .= 'IV: ' . $sv->IVX . ' ';
    }
    if ($nok) {
        $flags  .= 'NOK ';
        $values .= 'NV: ' . $sv->NV . ' ';
    }
    if ($pok) {
        $flags  .= 'POK ';
        $values .= 'PV: ' . $sv->PV . ' ';
    }
    $flags .= 'pPOK ' if $ppok;

    return sprintf( "SV is %s ; %s ; Flags 0x%x ; SvCUR %d", $flags, $values, $sv->FLAGS, $sv->CUR );
}

1;
