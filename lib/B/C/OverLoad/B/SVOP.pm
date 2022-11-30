package B::SVOP;

use B::C::Std;

use B           qw/SVf_ROK/;
use B::C::File  qw/svopsect init/;
use B::C::Debug qw/debug WARN/;

sub do_save ( $op, @ ) {

    svopsect()->comment_for_op("sv");
    my ( $ix, $sym ) = svopsect()->reserve( $op, "OP*" );
    svopsect()->debug( $op->name, $op );

    my $svsym = 'Nullsv';

    if ( $op->name eq 'aelemfast' and $op->flags & 128 ) {    #OPf_SPECIAL
        $svsym = '&PL_sv_undef';                              # pad does not need to be saved
        debug( sv => "SVOP->sv aelemfast pad %d\n", $op->flags );
    }
    else {
        $svsym = $op->sv->save( "svop " . $op->name );
    }

    # PL_envgv and PL_argvgv STATIC_HV: We're probably saving those wrong.
    unless ( $svsym =~ m/[sg]v_list|Nullsv/ ) {    # PL_sv_yes, PL_sv_no, PL_sv_zero...
        init()->add("svop_list[$ix].op_sv = (SV*) $svsym;");
        $svsym = 'NULL';
    }

    svopsect()->supdate( $ix, "%s, (SV*) %s", $op->save_baseop, $svsym );

    return $sym;
}

1;
