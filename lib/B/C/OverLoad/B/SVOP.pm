package B::SVOP;

use strict;

use B qw/SVf_ROK/;
use B::C::File qw/svopsect init/;
use B::C::Debug qw/debug WARN/;

sub do_save {
    my ($op) = @_;

    svopsect()->comment_common("sv");
    my ( $ix, $sym ) = svopsect()->reserve( $op, "OP*" );
    svopsect()->debug( $op->name, $op );

    my $svsym = 'Nullsv';

    # STATIC HV: This might be a bug now we have a static stash.
    # It might also be a XS op we need to be aware of and take special action beyond this.
    #
    # XXX moose1 crash with 5.8.5-nt, Cwd::_perl_abs_path also
    if ( $op->name eq 'aelemfast' and $op->flags & 128 ) {    #OPf_SPECIAL
        $svsym = '&PL_sv_undef';                              # pad does not need to be saved
        debug( sv => "SVOP->sv aelemfast pad %d\n", $op->flags );
    }
    else {
        $svsym = $op->sv->save( "svop " . $op->name );
    }

    my $is_const_addr = $svsym =~ m/Null|\&/;

    my $svop_sv = ( $is_const_addr ? $svsym : "Nullsv /* $svsym */" );
    svopsect()->supdate( $ix, "%s, (SV*) %s", $op->_save_common, $svop_sv );
    init()->add("svop_list[$ix].op_sv = (SV*) $svsym;") unless $is_const_addr;

    return $sym;
}

1;
