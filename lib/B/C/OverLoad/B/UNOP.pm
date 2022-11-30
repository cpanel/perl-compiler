package B::UNOP;

use B::C::Std;

use B::C::File qw/unopsect/;

our @DO_UPDATE_ARGS;    # avoid a local on @_ which bloat the binary

sub do_save {    # cannot use function signature here - goto
    my ($op) = @_;

    unopsect()->comment_for_op("first");
    my ( $ix, $sym ) = unopsect()->reserve( $op, "OP*" );
    unopsect()->debug( $op->name, $op );

    # view Sub::Call::Tail perldoc for more details ( could use it )
    @DO_UPDATE_ARGS = ( $ix, $sym, $op );
    goto &do_update;    # avoid deep recursion calls by forcing a tail call with goto
}

sub do_update {
    my ( $ix, $sym, $op ) = @DO_UPDATE_ARGS;
    unopsect()->supdate( $ix, "%s, %s", $op->save_baseop, $op->first->save || 'NULL' );

    return $sym;
}

1;
