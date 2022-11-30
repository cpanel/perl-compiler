package B::NV;

use B::C::Std;

use B q/SVf_IOK/;

use B::C::Debug   qw/debug/;
use B::C::File    qw/xpvnvsect svsect/;
use B::C::Decimal qw/get_double_value/;

# TODO NVs should/could be bodyless ? view IVs, UVs
sub do_save ( $sv, $fullname, $custom = undef ) {

    my $svflags = $sv->FLAGS;
    my $refcnt  = $sv->REFCNT;
    $sv->FLAGS & 2048 and die sprintf( "Unexpected SVf_ROK found in %s\n", ref $sv );

    if ( ref $custom ) {    # used when downgrading a PVIV / PVNV to IV
        $svflags = $custom->{flags}  if defined $custom->{flags};
        $refcnt  = $custom->{refcnt} if defined $custom->{refcnt};
    }

    my $nv = get_double_value( $sv->NV );
    $nv .= '.00' if $nv =~ /^-?\d+$/;

    # IVX is invalid in B.xs and unused
    my $iv = $svflags & SVf_IOK ? $sv->IVX : 0;

    my $xpv_sym = 'NULL';
    if ( $sv->HAS_ANY ) {
        xpvnvsect()->comment('STASH, MAGIC, cur, len, IVX, NVX');
        my $xpv_ix = xpvnvsect()->sadd( 'Nullhv, {0}, 0, {0}, {%ld}, {%s}', $iv, $nv );

        $xpv_sym = sprintf( "&xpvnv_list[%d]", $xpv_ix );
    }
    my $sv_ix = svsect()->sadd( '%s, %Lu, 0x%x , {0}', $xpv_sym, $refcnt, $svflags );

    svsect()->debug( $fullname, $sv );
    debug(
        sv => "Saving NV %s to xpvnv_list[%d], sv_list[%d]\n",
        $nv, xpvnvsect()->index, $sv_ix
    );
    return sprintf( "&sv_list[%d]", $sv_ix );
}

1;
