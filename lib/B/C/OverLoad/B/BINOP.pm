package B::BINOP;

use strict;

use B           qw/opnumber/;
use B::C::File  qw/binopsect init/;
use B::C::Debug qw/verbose/;

my $OP_CUSTOM;
BEGIN { $OP_CUSTOM = B::opnumber('custom') }

our @DO_UPDATE_ARGS;    # avoid a local on @_ which bloat the binary

sub do_save {
    my ($op) = @_;

    binopsect->comment_for_op("first, last");
    my ( $ix, $sym ) = binopsect()->reserve( $op, "OP*" );
    binopsect->debug( $op->name, $op->flagspv );

    # view Sub::Call::Tail perldoc for more details ( could use it )
    @DO_UPDATE_ARGS = ( $ix, $sym, $op );
    goto &do_update;    # avoid deep recursion calls by forcing a tail call with goto
}

sub do_update {
    my ( $ix, $sym, $op ) = @DO_UPDATE_ARGS;

    binopsect->supdate( $ix, "%s, %s, %s", $op->save_baseop, $op->first->save, $op->last->save );

    my $ppaddr = $op->ppaddr;
    if ( $op->type == $OP_CUSTOM ) {
        my $ptr = $$op;
        if ( $op->name eq 'Devel_Peek_Dump' or $op->name eq 'Dump' ) {
            verbose('custom op Devel_Peek_Dump');
            $B::C::devel_peek_needed++;
            init()->sadd( "binop_list[%d].op_ppaddr = S_pp_dump;", $ix );
        }
        else {
            vebose( "Warning: Unknown custom op " . $op->name );
            init()->sadd( "binop_list[%d].op_ppaddr = Perl_custom_op_xop(aTHX_ INT2PTR(OP*, 0x%x));", $ix, $ppaddr, $$op );
        }
    }

    return $sym;
}

1;
