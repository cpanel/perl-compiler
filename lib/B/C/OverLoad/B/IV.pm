package B::IV;

use B::C::Std;

use B             qw/SVf_IVisUV/;
use B::C::File    qw/svsect/;
use B::C::Decimal qw/get_integer_value/;

sub do_save ( $sv, $fullname = undef, $custom = undef ) {

    my $rv_sym = B::RV::try_save( $sv, $fullname );
    return $rv_sym if $rv_sym;

    # Since 5.11 the RV is no special SV object anymore, just a IV (test 16)
    my $svflags = $sv->FLAGS;
    my $refcnt  = $sv->REFCNT;

    if ( ref $custom ) {    # used when downgrading a PVIV / PVNV to IV
        $svflags = $custom->{flags}  if defined $custom->{flags};
        $refcnt  = $custom->{refcnt} if defined $custom->{refcnt};
    }

    if ( $svflags & SVf_IVisUV == SVf_IVisUV ) {
        return $sv->B::UV::save($fullname);
    }
    my $ivx = get_integer_value( $sv->IVX );

    my ( $ix, $sym ) = svsect()->reserve($sv);
    svsect()->debug( $fullname, $sv );

    # Since 5.24 we can access the IV/NV/UV value from either the union from the main SV body
    # or also from the SvANY of it. View IV.pm for more information

    svsect()->supdatel(
        $ix,
        'BODYLESS_IV_PTR(%s)' => $sym,        # sv_any
        '%lu',                => $refcnt,     # sv_refcnt
        '0x%x'                => $svflags,    # sv_flags
        '{.svu_iv=%s}'        => $ivx,        # sv_u.svu_uv
    );

=pod
    Since 5.24 we can access the IV/NV/UV value from either the union from the main SV body
    or also from the SvANY of it...

    As IV family do not need/have one SvANY we are going to cheat....
    by setting a 'virtual' pointer to the SvANY to an unsignificant memory address
    but once we try to access to the IV value of it... this will point to the
    single location where it's store in the body of the main SV....

    So two differents way to access to the same memory location.

=cut

    return $sym;
}

1;
__END__
 from sv.h

 /*
 * Bodyless IVs and NVs!
 *
 * Since 5.9.2, we can avoid allocating a body for SVt_IV-type SVs.
 * Since the larger IV-holding variants of SVs store their integer
 * values in their respective bodies, the family of SvIV() accessor
 * macros would  naively have to branch on the SV type to find the
 * integer value either in the HEAD or BODY. In order to avoid this
 * expensive branch, a clever soul has deployed a great hack:
 * We set up the SvANY pointer such that instead of pointing to a
 * real body, it points into the memory before the location of the
 * head. We compute this pointer such that the location of
 * the integer member of the hypothetical body struct happens to
 * be the same as the location of the integer member of the bodyless
 * SV head. This now means that the SvIV() family of accessors can
 * always read from the (hypothetical or real) body via SvANY.
 *
 * Since the 5.21 dev series, we employ the same trick for NVs
 * if the architecture can support it (NVSIZE <= IVSIZE).
 */

/* The following two macros compute the necessary offsets for the above
 * trick and store them in SvANY for SvIV() (and friends) to use. */

#ifdef PERL_CORE
#  define SET_SVANY_FOR_BODYLESS_IV(sv) \
       SvANY(sv) =   (XPVIV*)((char*)&(sv->sv_u.svu_iv) \
                    - STRUCT_OFFSET(XPVIV, xiv_iv))

#  define SET_SVANY_FOR_BODYLESS_NV(sv) \
       SvANY(sv) =   (XPVNV*)((char*)&(sv->sv_u.svu_nv) \
                    - STRUCT_OFFSET(XPVNV, xnv_u.xnv_nv))
#endif
