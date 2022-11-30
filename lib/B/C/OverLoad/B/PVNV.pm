package B::PVNV;

use B::C::Std;

use B                              qw{SVf_NOK SVp_NOK};
use B::C::Decimal                  qw/get_integer_value get_double_value/;
use B::C::File                     qw/xpvnvsect svsect/;
use B::C::Optimizer::DowngradePVXV qw/downgrade_pvnv/;

sub do_save ( $sv, $fullname = undef ) {

    my $downgraded = downgrade_pvnv( $sv, $fullname );
    return $downgraded if defined $downgraded;

    my ( $ix, $sym ) = svsect()->reserve($sv);
    svsect()->debug( $fullname, $sv );

    my ( $savesym, $cur, $len, $pv, $flags ) = $sv->save_svu( $sym, $fullname );
    my $nvx = '0.0';
    my $ivx = get_integer_value( $sv->IVX );    # here must be IVX!
    if ( $flags & ( SVf_NOK | SVp_NOK ) ) {

        # it could be a double, or it could be 2 ints - union xpad_cop_seq
        $nvx = get_double_value( $sv->NV );
    }

    my $xpv_sym = 'NULL';
    if ( $sv->HAS_ANY ) {

        # For some time the stringification works of NVX double to two ints worked ok.
        xpvnvsect()->comment('STASH, MAGIC, cur, len, IVX, NVX');
        my $xpv_ix = xpvnvsect()->sadd( "Nullhv, {0}, %u, {%u}, {%s}, {%s}", $cur, $len, $ivx, $nvx );

        $xpv_sym = sprintf( "&xpvnv_list[%d]", $xpv_ix );
    }

    svsect()->supdate( $ix, "%s, %Lu, 0x%x, {%s}", $xpv_sym, $sv->REFCNT, $flags, $savesym );
    return $sym;
}

1;
