package B::RV;

use B::C::Std;

use B::C::Debug   qw/debug/;
use B             qw/SVf_ROK SVt_PVGV SVf_READONLY/;
use B::C::File    qw/svsect init init2/;
use B::C::Helpers qw/is_constant/;

# Since 5.11 also called by IV::save (SV -> IV)
sub do_save ( $sv, $fullname = undef ) {

    $fullname ||= "(Unknown RV)";

    # constants from B [ coming from XS ]
    # STATIC_HV need a more generic way to do not save these constants and bootstrap them correctly
    if ( !B::C::skip_B() ) {
        return 'NULL' if $fullname =~ qr{^(main::)?B::} and $sv->RV and $sv->RV->FLAGS & SVf_READONLY;
    }

    debug( sv => "Saving RV %s (0x%x) - called from %s:%s\n", ref($sv), $$sv, @{ [ ( caller(1) )[3] ] }, @{ [ ( caller(1) )[2] ] } );

    my ( $ix, $sym ) = svsect()->reserve($sv);
    svsect()->debug( $fullname, $sv );

    # 5.22 has a wrong RV->FLAGS (https://github.com/perl11/cperl/issues/63)
    my $flags = $sv->FLAGS;

    # GV should never have an ROK flag. that's just wierd.
    die( sprintf( "Unexpected Flags (0x%x) for %s in save_svu for ROK\n", $flags, ref $sv ) ) if ( $flags & SVt_PVGV ) == SVt_PVGV;

    svsect()->supdatel(
        $ix,
        '(void*)%s - sizeof(void*)' => $sym,                              # the SvANY is set just below at init time
        '%Lu'                       => $sv->REFCNT,
        '0x%x'                      => $flags,
        '{.svu_rv=%s}'              => save_rv( $sv, $sym, $fullname ),
    );

    return $sym;
}

sub try_save ( $sv, $fullname ) {

    return unless $sv->FLAGS & SVf_ROK;

    return do_save( $sv, $fullname );
}

sub save_rv ( $sv, $sym, $fullname ) {

    $fullname ||= "(Unknown RV)";

    my $rv = $sv->RV->save($fullname);

    if ( !B::C::skip_B() ) {
        return 'NULL' if is_constant($rv) && $fullname =~ qr{^B::};
    }
    return "(SV*)$rv" if is_constant($rv);

    $sym =~ s/^&//;

    my $init = ( $rv =~ /get_cv/ ) ? init2() : init();

    # check if the CV is bootsrrapped then use the correct section for it
    if ( my $sub = B::C::is_bootstrapped_cv($rv) ) {
        $init = B::C::get_bootstrap_section($sub);
    }

    $init->sadd( "%s.sv_u.svu_rv = (SV*)%s;", $sym, $rv );
    return sprintf( q{0 /* RV %s */}, $rv );
}

1;
