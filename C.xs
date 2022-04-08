#define PERL_NO_GET_CONTEXT
#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>

/* hack for 5.6.2: just want to know if PMf_ONCE or 0 */
#ifndef PmopSTASHPV
# define PmopSTASHPV(o) ((o)->op_pmflags & PMf_ONCE)
#endif
#ifndef RX_EXTFLAGS
# define RX_EXTFLAGS(prog) ((prog)->extflags)
#endif

typedef INVLIST       *B__INVLIST;
typedef MAGIC         *B__MAGIC;
typedef PADNAME       *B__PADNAME;
typedef PADLIST       *B__PADLIST;
typedef PADNAMELIST   *B__PADNAMELIST;
typedef struct p5rx  *B__REGEXP;
typedef COP  *B__COP;
typedef CV   *B__CV;
typedef OP   *B__OP;
typedef HV   *B__HV;
typedef SV   *B__SV;

STATIC U32 a_hash = 0;

typedef struct {
  U32 hash;
  char* key; /* This is the only thing we really care about. */
  I32 len;
} xsaccessor_any;

typedef struct {
  U32 bits;
  IV  require_tag;
} a_hint_t;

static const char* const svclassnames[] = {
    "B::NULL",
    "B::IV",
    "B::NV",
    "B::PV",
    "B::INVLIST",
    "B::PVIV",
    "B::PVNV",
    "B::PVMG",
    "B::REGEXP",
    "B::GV",
    "B::PVLV",
    "B::AV",
    "B::HV",
    "B::CV",
    "B::FM",
    "B::IO",
};

typedef enum {
    OPc_NULL,	/* 0 */
    OPc_BASEOP,	/* 1 */
    OPc_UNOP,	/* 2 */
    OPc_BINOP,	/* 3 */
    OPc_LOGOP,	/* 4 */
    OPc_LISTOP,	/* 5 */
    OPc_PMOP,	/* 6 */
    OPc_SVOP,	/* 7 */
    OPc_PADOP,	/* 8 */
    OPc_PVOP,	/* 9 */
    OPc_LOOP,	/* 10 */
    OPc_COP,	/* 11 */
    OPc_METHOP,	/* 12 */
    OPc_UNOP_AUX /* 13 */
} opclass;

static const char* const opclassnames[] = {
    "B::NULL",
    "B::OP",
    "B::UNOP",
    "B::BINOP",
    "B::LOGOP",
    "B::LISTOP",
    "B::PMOP",
    "B::SVOP",
    "B::PADOP",
    "B::PVOP",
    "B::LOOP",
    "B::COP",
    "B::METHOP",
    "B::UNOP_AUX"
};

#define MY_CXT_KEY "B::C::_guts" XS_VERSION

typedef struct {
    int		x_walkoptree_debug;	/* Flag for walkoptree debug hook */
    SV *	x_specialsv_list[9];
} my_cxt_t;

START_MY_CXT

#define walkoptree_debug	(MY_CXT.x_walkoptree_debug)
#define specialsv_list		(MY_CXT.x_specialsv_list)

static opclass
cc_opclass(pTHX_ const OP *o)
{
    bool custom = 0;

    if (!o)
	return OPc_NULL;

    if (o->op_type == 0) {
	if (o->op_targ == OP_NEXTSTATE || o->op_targ == OP_DBSTATE)
	    return OPc_COP;
	return (o->op_flags & OPf_KIDS) ? OPc_UNOP : OPc_BASEOP;
    }

    if (o->op_type == OP_SASSIGN)
	return ((o->op_private & OPpASSIGN_BACKWARDS) ? OPc_UNOP : OPc_BINOP);

    if (o->op_type == OP_AELEMFAST) {
	    return OPc_SVOP;
    }

    if (o->op_type == OP_CUSTOM)
        custom = 1;

    switch (OP_CLASS(o)) {
    case OA_BASEOP:
	   return OPc_BASEOP;

    case OA_UNOP:
	   return OPc_UNOP;

    case OA_BINOP:
	   return OPc_BINOP;

    case OA_LOGOP:
	   return OPc_LOGOP;

    case OA_LISTOP:
	   return OPc_LISTOP;

    case OA_PMOP:
	   return OPc_PMOP;

    case OA_SVOP:
	   return OPc_SVOP;

    case OA_PADOP:
	   return OPc_PADOP;

    case OA_PVOP_OR_SVOP:
        /*
         * Character translations (tr///) are usually a PVOP, keeping a
         * pointer to a table of shorts used to look up translations.
         * Under utf8, however, a simple table isn't practical; instead,
         * the OP is an SVOP (or, under threads, a PADOP),
         * and the SV is a reference to a swash
         * (i.e., an RV pointing to an HV).
         */
    	return (!custom &&
    		   (o->op_private & (OPpTRANS_TO_UTF|OPpTRANS_FROM_UTF))
    	       )
    		? OPc_SVOP : OPc_PVOP;

    case OA_LOOP:
	return OPc_LOOP;

    case OA_COP:
	return OPc_COP;

    case OA_BASEOP_OR_UNOP:
	/*
	 * UNI(OP_foo) in toke.c returns token UNI or FUNC1 depending on
	 * whether parens were seen. perly.y uses OPf_SPECIAL to
	 * signal whether a BASEOP had empty parens or none.
	 * Some other UNOPs are created later, though, so the best
	 * test is OPf_KIDS, which is set in newUNOP.
	 */
	   return (o->op_flags & OPf_KIDS) ? OPc_UNOP : OPc_BASEOP;

    case OA_FILESTATOP:
	/*
	 * The file stat OPs are created via UNI(OP_foo) in toke.c but use
	 * the OPf_REF flag to distinguish between OP types instead of the
	 * usual OPf_SPECIAL flag. As usual, if OPf_KIDS is set, then we
	 * return OPc_UNOP so that walkoptree can find our children. If
	 * OPf_KIDS is not set then we check OPf_REF. Without OPf_REF set
	 * (no argument to the operator) it's an OP; with OPf_REF set it's
	 * an SVOP (and op_sv is the GV for the filehandle argument).
	 */
    	return ((o->op_flags & OPf_KIDS) ? OPc_UNOP :
    		(o->op_flags & OPf_REF) ? OPc_SVOP : OPc_BASEOP);
    case OA_LOOPEXOP:
	/*
	 * next, last, redo, dump and goto use OPf_SPECIAL to indicate that a
	 * label was omitted (in which case it's a BASEOP) or else a term was
	 * seen. In this last case, all except goto are definitely PVOP but
	 * goto is either a PVOP (with an ordinary constant label), an UNOP
	 * with OPf_STACKED (with a non-constant non-sub) or an UNOP for
	 * OP_REFGEN (with goto &sub) in which case OPf_STACKED also seems to
	 * get set.
	 */
    	if (o->op_flags & OPf_STACKED)
    	    return OPc_UNOP;
    	else if (o->op_flags & OPf_SPECIAL)
    	    return OPc_BASEOP;
    	else
    	    return OPc_PVOP;
    case OA_METHOP:
	   return OPc_METHOP;
    case OA_UNOP_AUX:
	   return OPc_UNOP_AUX;
    }
    warn("can't determine class of operator %s, assuming BASEOP\n",
	 OP_NAME(o));
    return OPc_BASEOP;
}

static SV *
make_sv_object(pTHX_ SV *sv)
{
    SV *const arg = sv_newmortal();
    const char *type = 0;
    IV iv;
    dMY_CXT;

    for (iv = 0; iv < (IV)(sizeof(specialsv_list)/sizeof(SV*)); iv++) {
        if (sv == specialsv_list[iv]) {
            type = "B::SPECIAL";
            break;
        }
    }
    if (!type) {
	   type = svclassnames[SvTYPE(sv)];
	   iv = PTR2IV(sv);
    }
    sv_setiv(newSVrv(arg, type), iv);
    return arg;
}

static SV *
make_op_object(pTHX_ const OP *o)
{
    SV *opsv = sv_newmortal();
    sv_setiv(newSVrv(opsv, opclassnames[cc_opclass(aTHX_ o)]), PTR2IV(o));
    return opsv;
}


static int
my_runops(pTHX)
{
    HV* regexp_hv = get_hv( "B::C::Regexp", GV_ADD );
    SV* key = newSViv( 0 );
    int type;

    DEBUG_l(Perl_deb(aTHX_ "Entering new RUNOPS level (B::C)\n"));
    do {

	if (PL_debug) {
	    if (PL_watchaddr && (*PL_watchaddr != PL_watchok))
		PerlIO_printf(Perl_debug_log,
			      "WARNING: %"UVxf" changed from %"UVxf" to %"UVxf"\n",
			      PTR2UV(PL_watchaddr), PTR2UV(PL_watchok),
			      PTR2UV(*PL_watchaddr));
#if defined(DEBUGGING) \
   && !(defined(_WIN32) || (defined(__CYGWIN__) && (__GNUC__ > 3)) || defined(AIX))
	    if (DEBUG_s_TEST_) debstack();
	    if (DEBUG_t_TEST_) debop(PL_op);
#endif
	}

        /* Need to store the rx all for QR PMOPs in a global %Regexp hash. MATCH once also */
        type = PL_op->op_type;
        if (type == OP_QR
        || (type == OP_MATCH
            && PmopSTASH((PMOP*)PL_op)
            ))
        {
            PMOP* op;
            REGEXP* rx = PM_GETRE( (PMOP*)PL_op );
            SV* rv = newSViv( 0 );

            New(0, op, 1, PMOP );
            Copy( PL_op, op, 1, PMOP );
            /* we need just the flags */
            op->op_next = NULL;
            op->op_first = NULL;
            op->op_last = NULL;
            op->op_pmregexp = 0;
            op->op_sibparent = 0;

            sv_setiv( key, PTR2IV( rx ) );
            sv_setref_iv( rv, "B::PMOP", PTR2IV( op ) );
#if defined(DEBUGGING)
	    if (DEBUG_D_TEST_) fprintf(stderr, "pmop %p => rx %s %p 0x%x %s\n",
                                       op, PL_op_name[type], rx, (unsigned)op->op_pmflags,
                                       RX_WRAPPED(rx));
#endif
            hv_store_ent( regexp_hv, key, rv, 0 );
        }
    } while ((PL_op = CALL_FPTR(PL_op->op_ppaddr)(aTHX)));

    SvREFCNT_dec( key );

    TAINT_NOT;
    return 0;
}

#/* ************************************************************ */
MODULE = B__MAGIC	PACKAGE = B::MAGIC
#/* ************************************************************ */

# This is a modified version of B::MAGIC::PTR. The B version isn't aware of when mg_ptr is
# actually pointing to a perl structure so it can't provide the right B object back to the caller.

void
BCPTR(mg)
	B::MAGIC	mg
PPCODE:
    if (mg->mg_ptr) {
        if (mg->mg_type == ':') {
            PUSHs(make_op_object(aTHX_ *((OP**)mg->mg_ptr)));
        }
        else if (mg->mg_len >= 0) {
            PUSHs(newSVpvn_flags(mg->mg_ptr, mg->mg_len, SVs_TEMP));
        }
        else if (mg->mg_len == HEf_SVKEY) {
            PUSHs(make_sv_object(aTHX_ (SV*)mg->mg_ptr));
        }
        else
            PUSHs(sv_newmortal());
    }
    else
        PUSHs(sv_newmortal());

#/* ************************************************************ */
MODULE = B      PACKAGE = B::HV
#/* ************************************************************ */

# returns a single or multiple ENAME(s), since 5.14
void
ENAMES(hv)
    B::HV hv
PPCODE:
    if (SvOOK(hv)) {
      if (HvENAME_HEK(hv)) {
        I32 i = 0;
        const I32 count = HvAUX(hv)->xhv_name_count;
        if (count) {
          HEK** names = HvAUX(hv)->xhv_name_u.xhvnameu_names;
          HEK *const *hekp = names + (count < 0 ? 1 : 0);
          HEK *const *const endp = names + (count < 0 ? -count : count);
          while (hekp < endp) {
            assert(*hekp);
            PUSHs(newSVpvn_flags(HEK_KEY(*hekp), HEK_LEN(*hekp),
                                 HEK_UTF8(*hekp) ? SVf_UTF8|SVs_TEMP : SVs_TEMP));
            ++hekp;
            i++;
          }
          XSRETURN(i);
        }
        else {
          HEK *const hek = HvENAME_HEK_NN(hv);
          ST(0) = newSVpvn_flags(HEK_KEY(hek), HEK_LEN(hek),
                                 HEK_UTF8(hek) ? SVf_UTF8|SVs_TEMP : SVs_TEMP);
          XSRETURN(1);
        }
      }
    }
    XSRETURN_UNDEF;

I32
name_count(hv)
    B::HV hv
PPCODE:
    PERL_UNUSED_VAR(RETVAL);
    if (SvOOK(hv))
      PUSHi(HvAUX(hv)->xhv_name_count);
    else
      PUSHi(0);

IV
Gv_AMG(stash)
    B::HV stash
CODE:
    XSRETURN_IV((!SvREADONLY(stash) && Gv_AMG(stash)) ? 1 : 0);

#/* ************************************************************ */
MODULE = B	PACKAGE = B::UNOP_AUX
#/* ************************************************************ */

SV*
aux(o)
          B::OP o
CODE:
  {
    UNOP_AUX_item *items = cUNOP_AUXo->op_aux;
    UV len = items[-1].uv;
    RETVAL = newSVpvn_flags((char*)&items[-1], (1+len) * sizeof(UNOP_AUX_item), 0);
  }
OUTPUT:
    RETVAL

SV*
aux_ptr2iv(o)
          B::OP o
CODE:
  {
    UNOP_AUX_item *aux = cUNOP_AUXo->op_aux;
    RETVAL = newSViv(PTR2IV(aux));
  }
OUTPUT:
    RETVAL


# Return the contents of the op_aux array as a list of IV/SV/GV/PADOFFSET objects.
# This version here returns the padoffset of SV/GV under ithreads, and not the
# SV/GV itself. It also uses simplified mPUSH macros.
# The design of the upstream aux_list method deviates significantly from proper B design.

void
aux_list_thr(o)
	B::OP  o
    PPCODE:
        PERL_UNUSED_VAR(cv); /* not needed on unthreaded builds */
        switch (o->op_type) {
        default:
            XSRETURN(0); /* by default, an empty list */

        case OP_ARGCHECK:
        {
            UNOP_AUX_item *aux = cUNOP_AUXo->op_aux;

            EXTEND(SP, 3);
            PUSHs(sv_2mortal(newSViv(aux[0].iv)));
            PUSHs(sv_2mortal(newSViv(aux[1].iv)));
            PUSHs(sv_2mortal(newSViv(aux[2].iv))); /* return the integer value and not a char */
            /*PUSHs(sv_2mortal(aux[2].iv ? Perl_newSVpvf(aTHX_ "%c", (char)aux[2].iv) : &PL_sv_no));*/
            break;
        }

        case OP_MULTICONCAT:
        {
                /* stolen from B.xs
                    - always return the plain & the utf8 strings
                        (do not try to be smart to return one or the other)
                    - always return all segments as they are
                    (view op/evalbytes.t unit test)
                */

                UNOP_AUX_item *aux = cUNOP_AUXo->op_aux;

                SSize_t nargs;
                char *p;
                STRLEN len;
                U32 utf8 = 0;
                SV *sv;
                UNOP_AUX_item *lens;

                /* return (nargs, const string, segment len 0, 1, 2, ...) */

                /* if this changes, this block of code probably needs fixing */
                assert(PERL_MULTICONCAT_HEADER_SIZE == 5);
                nargs = aux[PERL_MULTICONCAT_IX_NARGS].ssize;
                EXTEND(SP, ((SSize_t)(2 + (nargs+1))));
                PUSHs(sv_2mortal(newSViv((IV)nargs)));

                {   /* the plain string slots */
                    p   = aux[PERL_MULTICONCAT_IX_PLAIN_PV].pv;
                    len = aux[PERL_MULTICONCAT_IX_PLAIN_LEN].ssize;
                    if ( p ) {
                        PUSHs(sv_2mortal(newSVpvn(p, len)));
                    } else {
                        PUSHs(&PL_sv_undef);
                    }
                }

                {   /* the utf8 slots */
                    p   = aux[PERL_MULTICONCAT_IX_UTF8_PV].pv;
                    len = aux[PERL_MULTICONCAT_IX_UTF8_LEN].ssize;
                    if ( p ) {
                        sv = newSVpvn(p, len);
                        SvFLAGS(sv) |= utf8;
                        PUSHs(sv_2mortal(sv));
                    } else {
                        PUSHs(&PL_sv_undef);
                    }

     /* * If the string has different plain and utf8 representations
     *   (e.g. "\x80"), then then aux[PERL_MULTICONCAT_IX_PLAIN_PV/LEN]]
     *   holds the plain rep, while aux[PERL_MULTICONCAT_IX_UTF8_PV/LEN]
     *   holds the utf8 rep, and there are 2 sets of segment lengths,
     *   with the utf8 set following after the plain set.
     */
                    if (
                        aux[PERL_MULTICONCAT_IX_PLAIN_PV].pv
                        && aux[PERL_MULTICONCAT_IX_UTF8_PV].pv
                        && aux[PERL_MULTICONCAT_IX_UTF8_PV].pv != aux[PERL_MULTICONCAT_IX_PLAIN_PV].pv ) {
                            nargs += 2;
                    }
                }

                lens = aux + PERL_MULTICONCAT_IX_LENGTHS;
                nargs++; /* loop (nargs+1) times */

                while (nargs--) {
                    PUSHs(sv_2mortal(newSViv(lens->ssize)));
                    lens++;
                }

            break;
        }
        case OP_MULTIDEREF:
#  define PUSH_SV(item) PUSHs(make_sv_object(aTHX_ (item)->sv))
            {
                UNOP_AUX_item *items = cUNOP_AUXo->op_aux;
                UV actions = items->uv;
                UV len = items[-1].uv;
                bool last = 0;
                bool is_hash = FALSE;

                assert(len <= SSize_t_MAX);
                EXTEND(SP, (SSize_t)len);
                mPUSHu(actions);

                while (!last) {
                    switch (actions & MDEREF_ACTION_MASK) {

                    case MDEREF_reload:
                        actions = (++items)->uv;
                        mPUSHu(actions);
                        continue;
                        NOT_REACHED; /* NOTREACHED */

                    case MDEREF_HV_padhv_helem:
                        is_hash = TRUE;
                        /* FALLTHROUGH */
                    case MDEREF_AV_padav_aelem:
                        mPUSHu((++items)->pad_offset);
                        goto do_elem;
                        NOT_REACHED; /* NOTREACHED */

                    case MDEREF_HV_gvhv_helem:
                        is_hash = TRUE;
                        /* FALLTHROUGH */
                    case MDEREF_AV_gvav_aelem:
                        PUSH_SV(++items);
                        goto do_elem;
                        NOT_REACHED; /* NOTREACHED */

                    case MDEREF_HV_gvsv_vivify_rv2hv_helem:
                        is_hash = TRUE;
                        /* FALLTHROUGH */
                    case MDEREF_AV_gvsv_vivify_rv2av_aelem:
                        PUSH_SV(++items);
                        goto do_vivify_rv2xv_elem;
                        NOT_REACHED; /* NOTREACHED */

                    case MDEREF_HV_padsv_vivify_rv2hv_helem:
                        is_hash = TRUE;
                        /* FALLTHROUGH */
                    case MDEREF_AV_padsv_vivify_rv2av_aelem:
                        mPUSHu((++items)->pad_offset);
                        goto do_vivify_rv2xv_elem;
                        NOT_REACHED; /* NOTREACHED */

                    case MDEREF_HV_pop_rv2hv_helem:
                    case MDEREF_HV_vivify_rv2hv_helem:
                        is_hash = TRUE;
                        /* FALLTHROUGH */
                    do_vivify_rv2xv_elem:
                    case MDEREF_AV_pop_rv2av_aelem:
                    case MDEREF_AV_vivify_rv2av_aelem:
                    do_elem:
                        switch (actions & MDEREF_INDEX_MASK) {
                        case MDEREF_INDEX_none:
                            last = 1;
                            break;
                        case MDEREF_INDEX_const:
                            if (is_hash)
                              PUSH_SV(++items);
                            else
                              mPUSHi((++items)->iv);
                            break;
                        case MDEREF_INDEX_padsv:
                            mPUSHu((++items)->pad_offset);
                            break;
                        case MDEREF_INDEX_gvsv:
                            PUSH_SV(++items);
                            break;
                        }
                        if (actions & MDEREF_FLAG_last)
                            last = 1;
                        is_hash = FALSE;

                        break;
                    } /* switch */

                    actions >>= MDEREF_SHIFT;
                } /* while */
                XSRETURN(len);

            } /* OP_MULTIDEREF */
#if PERL_VERSION > 23 && defined(OP_SIGNATURE) /* cperl */
        case OP_SIGNATURE:
            {
                UNOP_AUX_item *items = cUNOP_AUXo->op_aux;
                UV len = items[-1].uv;
                UV actions = items[1].uv;

                assert(len <= SSize_t_MAX);
                EXTEND(SP, (SSize_t)len);
                mPUSHu(items[0].uv);
                mPUSHu(actions);
                items++;

                while (1) {
                    switch (actions & SIGNATURE_ACTION_MASK) {

                    case SIGNATURE_reload:
                        actions = (++items)->uv;
                        mPUSHu(actions);
                        continue;

                    case SIGNATURE_end:
                        goto finish;

                    case SIGNATURE_padintro:
                        mPUSHu((++items)->uv);
                        break;

                    case SIGNATURE_arg:
                    case SIGNATURE_arg_default_none:
                    case SIGNATURE_arg_default_undef:
                    case SIGNATURE_arg_default_0:
                    case SIGNATURE_arg_default_1:
                    case SIGNATURE_arg_default_op:
                    case SIGNATURE_array:
                    case SIGNATURE_hash:
                        break;

                    case SIGNATURE_arg_default_iv:
                        mPUSHu((++items)->iv);
                        break;

                    case SIGNATURE_arg_default_const:
                        PUSH_SV(++items);
                        break;

                    case SIGNATURE_arg_default_padsv:
                        mPUSHu((++items)->pad_offset);
                        break;

                    case SIGNATURE_arg_default_gvsv:
                        PUSH_SV(++items);
                        break;

                    } /* switch */

                    actions >>= SIGNATURE_SHIFT;
                } /* while */
              finish:
                XSRETURN(len);

            } /* OP_SIGNATURE */
#endif
        } /* switch */

#/* ************************************************************ */
MODULE = B	PACKAGE = B::PADNAME	PREFIX = Padname
#/* ************************************************************ */

#/*
#* PadnameGEN submitted to 5.36
#* - view https://github.com/Perl/perl5/pull/19599
#*/

int
PadnameGEN(padn)
       B::PADNAME      padn
    CODE:
        RETVAL = padn->xpadn_gen;
    OUTPUT:
       RETVAL

#/*
#* PadnameIsUndef submitted to 5.36
#* - view https://github.com/Perl/perl5/pull/19599
#*/

bool
PadnameIsUndef(padn)
       B::PADNAME      padn
    CODE:
        RETVAL = padn == &PL_padname_undef ? TRUE : FALSE;
    OUTPUT:
       RETVAL

#/* ************************************************************ */
MODULE = B     PACKAGE = B::PADNAMELIST        PREFIX = Padnamelist
#/* ************************************************************ */

size_t
PadnamelistMAXNAMED(padnl)
       B::PADNAMELIST  padnl

#/* ************************************************************ */
MODULE = B	PACKAGE = B::REGEXP	PREFIX = RX_
#/* ************************************************************ */

U32
RX_EXTFLAGS(rx)
	  B::REGEXP rx

U32 RX_NPARENS(rx)
      B::REGEXP rx
    CODE:
        RETVAL = rx && ReANY(rx) ? ReANY(rx)->nparens : 0;
    OUTPUT:
       RETVAL

#/* ************************************************************ */
MODULE = B  PACKAGE = B::MAGIC PREFIX = MG_
#/* ************************************************************ */

void
MG_OBJ_PTR(mg)
    B::MAGIC    mg
    PPCODE:
        PUSHs(sv_2mortal(newSVuv( mg ? PTR2UV(mg->mg_obj) : 0 )));

#/* ************************************************************ */
MODULE = B     PACKAGE = B::SV        PREFIX = Sv
#/* ************************************************************ */

bool
SvHAS_ANY(sv)
    B::SV   sv
    CODE:
	RETVAL = SvANY(sv) ? TRUE : FALSE;
    OUTPUT:
        RETVAL

#/*
#* SvIsBool, SvIsBoolYes, SvIsBoolNo submitted to 5.36
#* - view https://github.com/Perl/perl5/pull/19600
#*/

bool
SvIsBool(sv)
    B::SV   sv
    CODE:
	RETVAL = SvIsBOOL(sv) ? TRUE : FALSE;
    OUTPUT:
        RETVAL

bool
SvIsBoolYes(sv)
    B::SV   sv
    CODE:
	RETVAL = SvIsBOOL(sv) && SvPVX_const(sv) == PL_Yes ? TRUE : FALSE;
    OUTPUT:
        RETVAL

bool
SvIsBoolNo(sv)
    B::SV   sv
    CODE:
	RETVAL = SvIsBOOL(sv) && SvPVX_const(sv) == PL_No ? TRUE : FALSE;
    OUTPUT:
        RETVAL

#/*
#* Perl_sv_get_backrefs returns the point to the backrefs AV*
#* - for HV (with OOK) it's stored in the AUX.xhv_backreferences
#* - for any other SVs it's stored in the PERL_MAGIC_backref magic
#*
#*/

void
SvBACKREFS(sv)
    B::SV sv
PREINIT:
    SV *av_backrefs;
PPCODE:
    av_backrefs = (SV*) Perl_sv_get_backrefs(sv);
    if (av_backrefs) {
        XPUSHs(make_sv_object(aTHX_ av_backrefs));
    } else {
        XSRETURN_UNDEF;
    }

#/* ************************************************************ */
MODULE = B__CC	PACKAGE = B::CC
#/* ************************************************************ */

PROTOTYPES: DISABLE

# Perl_ck_null is not exported on Windows, so disable autovivification optimizations there

U32
_autovivification(cop)
	B::COP	cop
CODE:
    {
      SV *hint;
      IV h;

      RETVAL = 1;
      if (PL_check[OP_PADSV] != PL_check[0]) {
	/*char *package = CopSTASHPV(cop);*/
#ifdef cop_hints_fetch_pvn
	hint = cop_hints_fetch_pvn(cop, "autovivification", strlen("autovivification"), a_hash, 0);
#else
	hint = Perl_refcounted_he_fetch(aTHX_ cop->cop_hints_hash,
					NULL, "autovivification", strlen("autovivification"), 0, a_hash);
#endif
	if (!(hint && SvIOK(hint)))
	  return;
	h = SvIVX(hint);
	if (h & 4)  /* A_HINT_FETCH  4 */
	  RETVAL = 0;
      }
    }
OUTPUT:
  RETVAL

#/* ************************************************************ */
MODULE = B__OP	PACKAGE = B::OP		PREFIX = op_
#/* ************************************************************ */

#ifdef need_op_slabbed

I32
op_slabbed(op)
        B::OP        op
    PPCODE:
	PUSHi(op->op_slabbed);

I32
op_savefree(op)
        B::OP        op
    PPCODE:
	PUSHi(op->op_savefree);

I32
op_static(op)
        B::OP        op
    PPCODE:
	PUSHi(op->op_static);

#endif

#ifdef need_op_folded

I32
op_folded(op)
        B::OP        op
    PPCODE:
	PUSHi(op->op_folded);

#endif

I32
op_max()
    PPCODE:
    PUSHi(OP_max);


#/*
#*   op_sibling and op_parent from B.xs are tight but do not return what is in the slot
#*       op_sibling returns op_sibparent only if op_moresib is set...
#*       whereas op_parent returns the great,great... parent...
#*   so a combination of the two could provide the same as this op_sibparent
#*        i.e.:   op_sibling || op_oarent
#*/

void
op_sibparent(op)
        B::OP        op
PPCODE:
     PUSHs(make_op_object(aTHX_ op->op_sibparent ));

#/* unused for now */
void
op_bc_next(op)
        B::OP        op
PPCODE:
     PUSHs(make_op_object(aTHX_ op->op_next ));

#/* ************************************************************ */
MODULE = B__C          PACKAGE = B::C
#/* ************************************************************ */

SV*
get_linear_isa(classname)
    SV* classname;
CODE:
  {
    HV *class_stash = gv_stashsv(classname, 0);

    if (!class_stash) {
        /* No stash exists yet, give them just the classname */
        AV* isalin = newAV();
        av_push(isalin, newSVsv(classname));
        RETVAL = newRV(MUTABLE_SV(isalin));
    }
    else { /* just dfs */
      RETVAL = newRV(MUTABLE_SV(Perl_mro_get_linear_isa(aTHX_ class_stash)));
    }
  }
OUTPUT:
    RETVAL

SV*
sizeof_pointer()
    ALIAS:
    B::C::sizeof_xpvhv_aux                 = 1
    B::C::sizeof_HV_ARRAY                  = 2
PREINIT:
    SV *ret;
CODE:
 {
    MEM_SIZE size;
    switch (ix) {
        case 1:
            size = sizeof( struct xpvhv_aux );
        break;
        case 2:
            size = PERL_HV_ARRAY_ALLOC_BYTES(1);
        break;
        default:
            size = sizeof( void * );

    }
    RETVAL = newSVuv( size );
 }
OUTPUT:
    RETVAL

SV*
strtab()
    CODE:
        RETVAL = newRV_inc((SV*)PL_strtab);
    OUTPUT:
        RETVAL

SV*
custom_ops()
    CODE:
//    { PTR2IV(ppaddr) => PTR2IV(xop) }
        if (PL_custom_ops)
            RETVAL = newRV_inc((SV*)PL_custom_ops);
        else
            RETVAL = &PL_sv_undef;
    OUTPUT:
        RETVAL


SV*
custom_op_names()
    CODE:
        if (PL_custom_op_names)
            RETVAL = newRV_inc((SV*)PL_custom_op_names);
        else
            RETVAL = &PL_sv_undef;
    OUTPUT:
        RETVAL

SV*
custom_op_descs()
    CODE:
        if (PL_custom_op_descs)
            RETVAL = newRV_inc((SV*)PL_custom_op_descs);
        else
            RETVAL = &PL_sv_undef;
    OUTPUT:
        RETVAL

#/* ************************************************************ */
MODULE = B__CV	PACKAGE = B::CV		PREFIX = cv_
#/* ************************************************************ */

SV*
cv_get_xs_accessor_key(cv)
      B::CV cv;
  CODE:
        SV *sv;
        xsaccessor_any *xsa;

        xsa = XSANY.any_ptr;
        if (xsa) {
            RETVAL = newSVpvn(xsa->key, xsa->len);
        } else {
            RETVAL = &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

#/* ************************************************************ */
MODULE = B__SV	PACKAGE = B::SV		PREFIX = sv_
#/* ************************************************************ */

bool
sv_can_downgrade_to_iv(sv)
      B::SV sv;
  CODE:
        RETVAL = FALSE;
        if ( SvIOK(sv) && SvPOKp(sv) && SvCUR(sv) && SvCUR(sv) < 10 ) {
            char *str = SvPVX(sv);
            RETVAL = TRUE;
            for (int i = 0; i < SvCUR(sv); ++i ) {
                if ( *str < '0' || *str > '9' ) {
                    RETVAL = FALSE;
                    break;
                }
                ++str;
            }
        }
    OUTPUT:
        RETVAL

#/* ************************************************************ */
MODULE = B__C          PACKAGE = B::C
#/* ************************************************************ */

BOOT:
{
    MY_CXT_INIT;
    PL_runops = my_runops;
    {
      dMY_CXT;
      specialsv_list[0] = Nullsv;
      specialsv_list[1] = &PL_sv_undef;
      specialsv_list[2] = &PL_sv_yes;
      specialsv_list[3] = &PL_sv_no;
      specialsv_list[4] = &PL_sv_zero;
      specialsv_list[5] = (SV *) pWARN_ALL;
      specialsv_list[6] = (SV *) pWARN_NONE;
      specialsv_list[7] = (SV *) pWARN_STD;
      specialsv_list[8] = &PL_padname_undef;
    }
}
