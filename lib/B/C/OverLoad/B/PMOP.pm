package B::PMOP;

use B::C::Std;

use B             qw/RXf_EVAL_SEEN PMf_EVAL PMf_KEEP SVf_UTF8 svref_2object/;
use B::C::Debug   qw/debug/;
use B::C::File    qw/pmopsect pmopauxsect init init1 init2 lazyregex/;
use B::C::Helpers qw/strlen_flags/;
use B::C::Save    qw/savecowpv/;

# Global to this space?
my ($swash_init);

my %CACHE_SAVED_RX;    # all previously saved RegExp

use constant IX_PPADDR => 2;    # where is stored ppaddr in the PMOP struct

sub do_save ( $op, @ ) {

    pmopsect()->comment_for_op("first, last, pmregexp, pmflags, pmreplroot, pmreplstart");

    my ( $ix, $sym ) = pmopsect()->reserve( $op, 'OP*' );
    my $aux_ix = pmopauxsect()->add('0');

    if ( $ix != $aux_ix ) {
        die "pmopsect_aux should always stay in sync with pmop";
    }

    $sym =~ s/^\(OP\*\)//;    # Strip off the typecasting for local use but other callers will get our casting.
    pmopsect()->debug( $op->name, $op );

    my $replroot  = $op->pmreplroot;
    my $replstart = $op->pmreplstart;
    my $ppaddr    = $op->ppaddr;

    my $replrootfield      = 'NULL';
    my $replrootfield_cast = '';
    if ( defined $replroot && ref $replroot ) {
        $replrootfield      = $replroot->save || 'NULL';
        $replrootfield_cast = '.op_pmtargetgv=' if $replrootfield =~ qr{gv_list};
    }
    elsif ( $replroot =~ qr{^[0-9]+$} ) {
        $replrootfield      = $replroot;
        $replrootfield_cast = '.op_pmtargetoff=';
    }

    my $replstartfield = ( defined $replstart && ref $replstart ) ? $replstart->save || 'NULL' : $replstart || 'NULL';

    # pmnext handling is broken in perl itself, we think. Bad op_pmnext
    # fields aren't noticed in perl's runtime (unless you try reset) but we
    # segfault when trying to dereference it to find op->op_pmnext->op_type
    pmopsect()->supdatel(
        $ix,
        '%s'                        => $op->save_baseop,                        # BASEOP
        '%s /* first */'            => $op->first->save,                        # OP *    op_first
        '%s /* last */'             => $op->last->save,                         # OP *    op_last
        '%u'                        => 0,                                       # REGEXP *    op_pmregexp
        '0x%x'                      => $op->pmflags,                            #  U32         op_pmflags
        '{%s} /* op_pmreplrootu */' => $replrootfield_cast . $replrootfield,    # union op_pmreplrootu
                                                                                # union {
                                                                                # OP *    op_pmreplroot;      /* For OP_SUBST */
                                                                                # PADOFFSET op_pmtargetoff;   /* For OP_SPLIT lex ary or thr GV */
                                                                                # GV *    op_pmtargetgv;          /* For OP_SPLIT non-threaded GV */
                                                                                # }   op_pmreplrootu;
        '{%s}'                      => $replstartfield,                         # union op_pmstashstartu
                                                                                # union {
                                                                                # OP *    op_pmreplstart; /* Only used in OP_SUBST */
                                                                                # HV *    op_pmstash;
                                                                                # }       op_pmstashstartu;
    );

    my $code_list = $op->code_list;
    if ( $code_list and $$code_list ) {
        debug( gv => "saving pmop_list[%d] code_list $code_list (?{})", $ix );
        my $code_op = $code_list->save;
        if ($code_op) {

            # (?{}) code blocks
            init()->sadd( 'pmop_list[%d].op_code_list = %s;', $ix, $code_op );
        }
        debug( gv => "done saving pmop_list[%d] code_list $code_list (?{})", $ix );
    }

    my $re = $op->precomp;

    if ( defined($re) ) {

        # TODO minor optim: fix savere( $re ) to avoid newSVpvn;
        my ( $qre, $relen, $utf8 ) = strlen_flags($re);

        my $pmflags = $op->pmflags;
        debug( gv => "pregcomp $sym $qre:$relen" . ( $utf8 ? " SVf_UTF8" : "" ) . sprintf( " 0x%x\n", $pmflags ) );

        # some pm need early init (242), SWASHNEW needs some late GVs (GH#273)
        # esp with 5.22 multideref init. i.e. all \p{} \N{}, \U, /i, ...
        # But XSLoader and utf8::SWASHNEW itself needs to be early.
        my $initpm    = init1();
        my $can_defer = 1;

        if (   $qre =~ m/\\[Nx]\{/
            || $qre =~ m/\\U/
            || ( $op->reflags & SVf_UTF8 || $utf8 ) ) {
            $initpm = init2();

            # If these are deferred the error message will change
            # because the sequence will not be inited soon enough
            $can_defer = 0;
        }

        my $eval_seen = $op->reflags & RXf_EVAL_SEEN;
        $can_defer = 0 if $eval_seen;

        if ( !$can_defer ) {
            $initpm->open_block();    # make sure everything is in a single block - not cut over two functions
            if ($eval_seen) {         # we cannot compile RegExp with eval at runtime
                                      # set HINT_RE_EVAL on
                $pmflags |= PMf_EVAL;
                $initpm->add('U32 hints_sav = PL_hints;');
                $initpm->add('PL_hints |= HINT_RE_EVAL;');
            }
            $initpm->sadd( "PM_SETRE(%s, CALLREGCOMP(newSVpvn_flags(%s, %s, SVs_TEMP|%s), 0x%x));", $sym, $qre, $relen, $utf8 ? 'SVf_UTF8' : '0', $pmflags );
            $initpm->sadd( "RX_EXTFLAGS(PM_GETRE(%s)) = 0x%x;", $sym, $op->reflags );
            if ($eval_seen) {
                $initpm->add('PL_hints = hints_sav;');    # set HINT_RE_EVAL off
            }
            $initpm->close_block();
        }

        # not a /o regexp and regexp was already seen at compile time [bind_match]
        elsif ( !( $pmflags & PMf_KEEP ) && ref $op->last eq 'B::LOGOP' ) {
            1;    # ignored
        }
        else {
            my $key      = sprintf( "((%s, %s, SVs_TEMP|%s), 0x%x, 0x%x)", $qre, $relen, $utf8 ? 'SVf_UTF8' : '0', $pmflags, $op->reflags );
            my $saved_rx = $CACHE_SAVED_RX{$key};

            my $ix_bcrx;    # point to one index in rx_list

            my $comment = $qre;
            $comment =~ s{\Q/*\E}{??}g;
            $comment =~ s{\Q*/\E}{??}g;

            if (
                $saved_rx                      # If we have already seen this regex
                && !_regex_has_capture($re)    # and it does not have a capture
              ) {                              # we can just use the reference.
                $ix_bcrx = $saved_rx->{ix};
                ++$saved_rx->{refcnt};         # increase the refcnt

                my $IX_REFCNT = 6;             # where is stored our RefCNT in the struct
                lazyregex()->supdate_field( $ix_bcrx, $IX_REFCNT, ' %u', $saved_rx->{refcnt} );
            }
            else {
                # ix where we store all informations in the rx_list
                $ix_bcrx = lazyregex()->sadd(    #
                    "%s, %s, %s, SVs_TEMP|%s, 0x%x, 0x%x, %d /* RefCNT */",    #
                    'NULL', $qre, $relen, $utf8 ? 'SVf_UTF8' : '0', $pmflags, $op->reflags
                );

                # start refcnt at 0 as we want to add +1 for each additional PMOP
                $CACHE_SAVED_RX{$key} = {
                    ix     => $ix_bcrx,
                    refcnt => 0,
                };
            }

            # update the op to use our custom lazy RegExp OP
            pmopsect()->supdate_field( $ix, IX_PPADDR, ' %s', '&Perl_pp_bc_init_pmop' );

            # store the position of the bcregex in a struct side/side so we do not have to update/corrupt the PMOP itself
            pmopauxsect()->supdate( $ix, '%d /* rx_list[%d] - %s */', $ix_bcrx, $ix_bcrx, $comment );
        }
    }

    if ( $replrootfield && $replrootfield ne 'NULL' && $replrootfield ne '(void*)Nullsv' ) {
        my $pmsym = $sym;
        $pmsym =~ s/^\&//;    # Strip '&' off the front.

        # XXX need that for subst
        init()->sadd( "%s.op_pmreplrootu.op_pmreplroot = (OP*)%s;", $pmsym, $replrootfield );
    }

    return "(OP*)" . $sym;
}

sub _regex_has_capture ($re) {

    # No ()s .. has no capture - pre optimization
    return 0 if $re !~ tr{()}{};

    # could also use Regexp::Parser with a scalar on $parser->captures
    my $qr      = qr{$re};
    my $re_obj  = svref_2object($qr);
    my $nparens = $re_obj->NPARENS;     # number of captures

    return $nparens ? 1 : 0;
}

1;
