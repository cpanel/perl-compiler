package B::LISTOP;

use B::C::Std;

use B::C::File qw/listopsect/;

our @DO_UPDATE_ARGS;    # avoid a local on @_ which bloat the binary

sub do_save {
    my ($op) = @_;

    listopsect()->comment_for_op("first, last");
    my ( $ix, $sym ) = listopsect()->reserve( $op, "OP*" );
    listopsect()->debug( $op->name, $op );

    # view Sub::Call::Tail perldoc for more details ( could use it )
    @DO_UPDATE_ARGS = ( $ix, $sym, $op );
    goto &do_update;    # avoid deep recursion calls by forcing a tail call with goto
}

sub do_update {
    my ( $ix, $sym, $op ) = @DO_UPDATE_ARGS;

    listopsect()->supdate( $ix, "%s, %s, %s", $op->save_baseop, $op->first->save, $op->last->save );

    return $sym;
}

1;
