package B::PADNAME;

use B::C::Std;

use B           qw/cstring/;
use B::C::Debug qw/debug/;
use B::C::File  qw/padnamesect/;

our $MAX_PADNAME_LENGTH = 1;

sub do_save ( $pn, $fullname ) {

    return q[&PL_padname_undef] if $pn->IsUndef;

    my ( $ix, $sym ) = padnamesect()->reserve($pn);
    padnamesect()->debug( $fullname, $pn );

    my $refcnt = $pn->REFCNT;
    my $pv     = $pn->PVX;

    my $xpadn_str = cstring($pv) || '{0}';

    my $xpadn_pv = sprintf( "((char*)%s)+STRUCT_OFFSET(struct padname_with_str, xpadn_str[0])", $sym );

    # Track the largest padname length to determine the size of the struct.
    my $xpadn_len = $pn->LEN;
    $MAX_PADNAME_LENGTH = $xpadn_len if $xpadn_len > $MAX_PADNAME_LENGTH;
    if ( $xpadn_len > 60 ) {
        die "ERROR Overlong name of lexical variable $pv for $fullname. This causes all pads to have to be overly large. Please shrink the variable name's length and try again.";
    }

    # 5.22 needs the buffer to be at the end, and the pv pointing to it.
    # We allocate a static buffer, and for uniformity of the list pre-alloc.
    # We set it to the max length of the largest variable.
    padnamesect()->comment(" pv, ourstash, type_u, low, high, refcnt, gen, len, flags, str");

    # STATIC_HV: xpadn_type_u doesn't seem to be supporting the possibility of xpadn_protocv??

    # Provided in base.c.tt2 custom to deal with xpadn_str needing to be fixed in size.
    padnamesect()->supdatel(
        $ix,
        "%s"                         => $xpadn_pv,                         # char *xpadn_pv;
        "(HV*) %s"                   => $pn->OURSTASH->save($fullname),    # HV *xpadn_ourstash;
        "{.xpadn_typestash=(HV*)%s}" => $pn->TYPE->save($fullname),        # union { HV *xpadn_typestash; CV *xpadn_protocv; } xpadn_type_u;
        "%u"                         => $pn->COP_SEQ_RANGE_LOW,            # U32 xpadn_low;
        "%u"                         => $pn->COP_SEQ_RANGE_HIGH,           # U32 xpadn_high;
        "0x%x"                       => $refcnt,                           # U32 xpadn_refcnt;
        "%i"                         => $pn->GEN,                          # int xpadn_gen;
        "%u"                         => $xpadn_len,                        # U8  xpadn_len;
        "0x%x"                       => $pn->FLAGS & 0xff,                 # U8  xpadn_flags; /* U8 + FAKE if OUTER. OUTER,STATE,LVALUE,TYPED,OUR */
        "%s"                         => $xpadn_str,                        # char xpadn_str[60]; /* longer lexical upval names are forbidden for now */
    );

    padnamesect()->debug( $fullname . " " . $pv, $pn->flagspv ) if debug('flags');

    return $sym;
}

1;
