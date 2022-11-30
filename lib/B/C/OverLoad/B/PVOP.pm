package B::PVOP;

use B::C::Std;

use B::C::File qw/pvopsect/;
use B::C::Save qw/savecowpv/;

sub do_save ( $op, @ ) {

    my ( $cow_sym, $cur, $len ) = savecowpv( $op->pv );

    pvopsect()->comment_for_op("pv");
    my ( $ix, $sym ) = pvopsect()->reserve( $op, "OP*" );
    pvopsect()->debug( $op->name, $op );

    pvopsect()->supdate( $ix, "%s, (char*)%s", $op->save_baseop, $cow_sym );

    return $sym;
}

1;
