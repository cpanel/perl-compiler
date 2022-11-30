package B::METHOP;

use B::C::Std;

use B::C::File qw/methopsect/;

sub do_save ( $op, @ ) {

    my $name    = $op->name || '';
    my $flagspv = $op->flagspv;
    my $union   = $name eq 'method' ? "{.op_first=(OP*)%s}" : "{.op_meth_sv=(SV*)%s}";

    methopsect()->comment_for_op("first, rclass");
    my ( $ix, $sym ) = methopsect()->reserve( $op, "OP*" );
    methopsect()->debug( $name, $flagspv );

    my $rclass = $op->rclass->save("op_rclass_sv");
    my $first  = $name eq 'method' ? $op->first->save("methop first") : $op->meth_sv->save("methop meth_sv");

    methopsect()->supdate( $ix, "%s, $union, (SV*)%s", $op->save_baseop, $first, $rclass );

    return $sym;
}

1;
