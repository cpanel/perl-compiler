package B::OP;

use strict;

use B qw/peekop cstring threadsv_names opnumber/;

use B::C::Config;
use B::C::File qw/init copsect opsect/;

my $OP_CUSTOM = opnumber('custom');

my @threadsv_names;

BEGIN {
    @threadsv_names = threadsv_names();
}

# special handling for nullified COP's.
my %OP_COP = ( opnumber('nextstate') => 1 );
debug( cops => %OP_COP );

sub do_save {
    my ($op) = @_;

    my $type = $op->type;
    $B::C::nullop_count++ unless $type;

    # HV_STATIC: Why are we saving a null row?
    # since 5.10 nullified cops free their additional fields
    if ( !$type and $OP_COP{ $op->targ } ) {
        die("Saving a cop in an OP???");
        copsect()->comment_common("line, stash, file, hints, seq, warnings, hints_hash");
        my ( $ix, $sym ) = copsect()->reserve( $op, "OP*" );
        copsect()->debug( $op->name, $op );

        copsect()->supdate( $ix,
            "%s, 0, %s, NULL, 0, 0, NULL, NULL",
            $op->_save_common, "Nullhv"
        );

        return $sym;
    }
    else {

        opsect()->comment( B::C::opsect_common() );
        my ( $ix, $sym ) = opsect()->reserve( $op, "OP*" );
        opsect()->debug( $op->name, $op );

        opsect()->update( $ix, $op->_save_common );
        return $sym;
    }
}

# See also init_op_ppaddr below; initializes the ppaddr to the
# OpTYPE; init_op_ppaddr iterates over the ops and sets
# op_ppaddr to PL_ppaddr[op_ppaddr]; this avoids an explicit assignment
# in perl_init ( ~10 bytes/op with GCC/i386 )
sub B::OP::fake_ppaddr {
    my $op = shift;
    return "NULL" unless $op->can('name');
    if ( $op->type == $OP_CUSTOM ) {
        return ( verbose() ? sprintf( "/*XOP %s*/NULL", $op->name ) : "NULL" );
    }
    return sprintf( "INT2PTR(void*,OP_%s)", uc( $op->name ) );
}

sub _save_common {
    my $op = shift;

    return sprintf(
        "%s, %s, %s, %u, %u, 0, 0, 0, 1, 0, 0, 0, 0x%x, 0x%x",
        $op->next->save,
        $op->sibling->save,
        $op->fake_ppaddr, $op->targ, $op->type, $op->flags, $op->private
    );
}

# XXX HACK! duct-taping around compiler problems
sub isa { UNIVERSAL::isa(@_) }    # walkoptree_slow misses that
sub can { UNIVERSAL::can(@_) }

1;
