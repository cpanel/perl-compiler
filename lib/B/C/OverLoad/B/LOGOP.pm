package B::LOGOP;

use B::C::Std;

use B::C::File qw/logopsect/;

sub do_save ( $op, $ = undef ) {

    logopsect()->comment_for_op("first, other");
    my ( $ix, $sym ) = logopsect()->reserve( $op, "OP*" );
    logopsect()->debug( $op->name, $op );

    logopsect()->supdatel(
        $ix,
        '%s' => $op->save_baseop,
        '%s' => $op->first->save,
        '%s' => $op->other->save
    );

    return $sym;
}

1;
