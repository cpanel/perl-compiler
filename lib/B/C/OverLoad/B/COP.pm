package B::COP;

use B::C::Std;

use B               qw/cstring svref_2object/;
use B::C::Debug     qw/debug/;
use B::C::File      qw/init copsect decl lexwarnsect refcounted_hesect/;
use B::C::Decimal   qw/get_integer_value/;
use B::C::Helpers   qw/strlen_flags/;
use B::C::Save::Hek qw/save_shared_he get_sHe_HEK/;

my %COPHHTABLE;
my %copgvtable;

sub do_save ( $op, @ ) {

    # TODO: if it is a nullified COP we must save it with all cop fields!
    debug( cops => "COP: line %d file %s\n", $op->line, $op->file );

    my ( $ix, $sym ) = copsect()->reserve( $op, "OP*" );
    copsect()->debug( $op->name, $op );

    # Trim the .pl extension, to print the executable name only.
    my $file = $op->file;

    if ( $op->label ) {

        # test 29 and 15,16,21. 44,45
        my $label = $op->label;
        my ( $cstring, $cur, $utf8 ) = strlen_flags($label);
        $utf8 = 'SVf_UTF8' if $cstring =~ qr{\\[0-9]};    # help a little utf8, maybe move it to strlen_flags
        init()->sadd(
            "Perl_cop_store_label(aTHX_ &cop_list[%d], %s, %u, %s);",
            $ix, $cstring, $cur, $utf8
        );
    }

    # we should have already saved the GV for the file (exception for B and O)
    my $filegv = exists $main::{qq[_<$file]} ? svref_2object( \$main::{qq[_<$file]} )->save : 'Nullgv';
    $filegv = 'Nullgv' if $filegv eq 'NULL';

    # COP has a stash method
    my $stash = $op->stash ? $op->stash->save : q{Nullhv};

    # a COP needs to have a stash, fallback to PL_defstash when none found
    if ( !$stash or $stash eq 'NULL' or $stash eq 'Nullhv' ) {

        # view op/bless.t
        $stash = B::C::save_defstash();
    }

    # add the cop at the end
    copsect()->comment_for_op("line_t line, HV* stash, GV* filegv, U32 hints, U32 seq, STRLEN* warn_sv, COPHH* hints_hash");
    copsect()->supdatel(
        $ix,
        '%s'       => $op->save_baseop,                     # BASEOP list
        '%u'       => $op->line,                            # /* line # of this command */
        '(HV*) %s' => $stash,                               # HV *    cop_stash;  /* package line was compiled in */
        '(GV*) %s' => $filegv,                              # GV *    cop_filegv; /* file the following line # is from */
        '%u'       => $op->hints,                           # U32     cop_hints;  /* hints bits from pragmata */
        '%s'       => get_integer_value( $op->cop_seq ),    # U32     cop_seq;    /* parse sequence number */
        '%s'       => $op->save_warnings,                   # STRLEN *    cop_warnings;   /* lexical warnings bitmask */
        '%s'       => $op->save_hints,                      # COPHH * cop_hints_hash; /* compile time state of %^H. */
    );

    return $sym;
}

sub save_hints ( $op, $sym = '' ) {

    $sym =~ s/^\(OP\*\)//;

    my $hints = $op->hints_hash;
    return 'NULL' unless $hints and ref($hints) || '' eq 'B::RHE';

    my $hash = $hints->HASH;
    return 'NULL' unless $hash and ref($hash) || '' eq 'HASH' and keys %$hash;

    # $op->label sets the : hint. It's not clear why we can't do it here but doing so breaks things
    # TODO: We need to determine why this is the case - https://github.com/CpanelInc/perl-compiler/issues/68
    # io/layers.t, op/goto.t break for sure if these lines are removed.
    return 'NULL' if keys %$hash == 1 and exists $hash->{':'};
    delete $hash->{':'};

    my $shared_he_next = "NULL";
    foreach my $key ( keys %$hash ) {
        my ($shared_he) = save_shared_he($key);
        my $namehek = get_sHe_HEK($shared_he);

        my $value = $hash->{$key};
        my $len   = length($value);

        B::C::longest_refcounted_he_value($len);

        my $ix = refcounted_hesect()->saddl(
            '(COPHH*) %s'               => $shared_he_next,         # struct refcounted_he *refcounted_he_next
            '%s'                        => $namehek,                # HEK *refcounted_he_hek
            '{.refcounted_he_u_len=%s}' => $len,                    # union refcounted_he_val
            '%s'                        => 'IMMORTAL_PL_strtab',    # U32 refcounted_he_refcnt
            '%s'                        => 'HVrhek_PV',
            '%s'                        => cstring($value),         # Put a 0 on the end in the event it needs to check for UTF8 info.
        );

        # print STDERR sprintf("%s == %s\n", $key, $hash->{$key});
        $shared_he_next = sprintf( '&refcounted_he_list[%d]', $ix );
    }

    return "(COPHH*)" . $shared_he_next;
}

# We use the same symbol for ALL warnings with the same value.
my %lexwarnsym_cache;

sub save_warnings ($op) {
    die unless $op;

    my $warnings = $op->warnings;
    if ( ref($warnings) eq 'B::SPECIAL' ) {
        return 'pWARN_ALL'  if $$warnings == 4;    #define pWARN_ALL  0x2 /* use warnings 'all' */
        return 'pWARN_NONE' if $$warnings == 5;    #define pWARN_NONE 0x1 /* no warnings */
        return 'pWARN_STD'  if $$warnings == 6;    #define pWARN_STD  0x0 /* ? */

        die("Unknown special warnings $warnings $$warnings\n");
    }
    ref $warnings eq 'B::PV' or die("Warnings isn't a PV like we thought it was?? $warnings");

    my $pv = $warnings->PV;
    return $lexwarnsym_cache{$pv} if $lexwarnsym_cache{$pv};

    #print STDERR sprintf("XXXX WARN length=%s len=%s cur=%s\n", length($pv), $warnings->LEN, $warnings->CUR);

    my $len = $warnings->CUR;
    B::C::longest_warnings_string($len);
    my $ix = lexwarnsect()->saddl(
        '%ld' => $len,
        '%s'  => cstring($pv),
    );

    # set cache
    return $lexwarnsym_cache{$pv} = sprintf( "(STRLEN*) &lexwarn_list[%d]", $ix );
}

1;

__END__

/* Gosh. This really isn't a good name any longer.  */
struct refcounted_he {
    struct refcounted_he *refcounted_he_next;   /* next entry in chain */
    HEK                  *refcounted_he_hek;    /* hint key */
    union {
        IV                refcounted_he_u_iv;
        UV                refcounted_he_u_uv;
        STRLEN            refcounted_he_u_len;
        void             *refcounted_he_u_ptr;  /* Might be useful in future */
    } refcounted_he_val;
    U32                   refcounted_he_refcnt; /* reference count */
    /* First byte is flags. Then NUL-terminated value. Then for ithreads,
       non-NUL terminated key.  */
    char                  refcounted_he_data[1];
};
