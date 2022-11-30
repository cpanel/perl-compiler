package B::C::Memory;

use strict;

use B::C::File qw{malloc};

# track memory malloced in accurate sequence,
#	so we can predict the size of each element/pointer at compile time
our %MEMORY_USED_BY_SECTION;

my @SECTION_ORDER = qw{
  init_stash
  init_static_assignments
  init_bootstraplink
};

my %SIZEOF = (
    'PERL_HV_ARRAY_ALLOC_BYTES' => 8,     # 'sizeof(HE*) * size' by default
    'struct xpvhv_aux'          => 56,
    'void *'                    => 8,
    'HE'                        => 24,    # need a check
);

# simple sizeof using one hardcoded value for now
sub sizeof {
    my $struct = shift;

    die q{sizeof requires one arg} unless $struct;
    return $SIZEOF{$struct}  if defined $SIZEOF{$struct};
    return $SIZEOF{'void *'} if $struct =~ q{\*$};
    die qq{sizeof: Unkown struct '$struct'};
}

sub check_all_sizes {
    my $check = sub {
        my ( $struct, $size ) = @_;
        my $set = $SIZEOF{$struct} // 0;

        #warn "# sizeof($struct) is incorrect: set to '$set' should be '$size'\n";
        return if $set == $size;
        die "sizeof($struct) is incorrect: set to '$set' should be '$size'\n";
    };

    # do the check using the XS caller
    $check->( 'void *',                    B::C::sizeof_pointer() );
    $check->( 'struct xpvhv_aux',          B::C::sizeof_xpvhv_aux() );
    $check->( 'PERL_HV_ARRAY_ALLOC_BYTES', B::C::sizeof_HV_ARRAY() );

    return;
}

check_all_sizes();    # autocheck at startup

# mark the memory consume for this structure
sub consume_malloc {
    my ( $init, $size ) = @_;
    ### Note we should also consider using the section index,
    #	but so far all calls to B::C::Memory
    #	are directly performed inside one add so they are sequential inside the same section

    die 'init should be a section' unless $init->isa('B::C::InitSection');

    my $section_name = $init->name;

    $MEMORY_USED_BY_SECTION{$section_name} //= [];

    if ( !defined $MEMORY_USED_BY_SECTION{$section_name}->[-1] ) {

        # first entry for this section
        push @{ $MEMORY_USED_BY_SECTION{$section_name} }, { counter => 1, size => $size };
    }
    else {
        my $last = $MEMORY_USED_BY_SECTION{$section_name}->[-1];
        if ( $last->{size} == $size ) {
            $last->{counter}++;
        }
        else {
            push @{ $MEMORY_USED_BY_SECTION{$section_name} }, { counter => 1, size => $size };
        }
    }

}

sub get_malloc_size {    # in char unit
    populate_malloc_section();

    my @last_entry = malloc()->get_fields();    # get the last entry

    my $to   = $last_entry[1];
    my $size = 0;
    $size = $1 if $to =~ qr{([0-9]+)};

    return $size;
}

# build an array used to know what is the size of ptr inside our main memory
#	this is used by realloc
sub populate_malloc_section {
    return if malloc()->index >= 0;    # only run it once

    my $position        = 1;
    my $ordered_section = { map { $_ => $position++ } @SECTION_ORDER };

    # check that all section are known
    foreach my $name ( sort keys %MEMORY_USED_BY_SECTION ) {
        die qq{Unkown section name '$name' order.} unless defined $ordered_section->{$name};
    }

    my $from = 0;
    my $to   = 0;

    foreach my $section_name (@SECTION_ORDER) {
        next unless defined $MEMORY_USED_BY_SECTION{$section_name};

        my $section = $MEMORY_USED_BY_SECTION{$section_name};
        foreach my $entry (@$section) {

            $to += $entry->{counter} * $entry->{size};    # where this ends

            malloc()->comment('Malloc_t from (delta from start), Malloc_t to (delta from start), MEM_SIZE size, void *next (unusued pointer)');

            # for now use STATIC_MEMORY_AREA struct
            # { Malloc_t from; Malloc_t to; MEM_SIZE size; struct static_memory_t *next; }
            malloc()->saddl(
                '(Malloc_t) %d' => $from,             # Malloc_t from
                '(Malloc_t) %d' => $to,               # Malloc_t to
                '(MEM_SIZE) %d' => $entry->{size},    # MEM_SIZE size
                '%s'            => 'NULL',            # struct static_memory_t *next - unused *next pointer
            );
            malloc()->debug( $entry->{size} . ' x' . $entry->{counter} );

            $from = $to;                              # where the next one starts;
        }
    }

    return 1;
}

### helpers ( maybe move them to a better place ? )

# this is a perl wrapper around the C call to HvSETUP
sub HvSETUP {

    # this is matching the C prototype for HvSETUP
    my ( $init, $hv, $size, $has_ook, $backrefs_sym ) = @_;

    my $memory_required = $size * sizeof('PERL_HV_ARRAY_ALLOC_BYTES');

    # be careful there has_ook is true or false string...
    $memory_required += sizeof('struct xpvhv_aux') if $has_ook && lc($has_ook) eq 'true';

    consume_malloc( $init, $memory_required );

    return sprintf( q{HvSETUP(%s, %d, %s, (SV*) %s);}, $hv, $size, $has_ook, $backrefs_sym );
}

# this is a perl wrapper around the C call to INITPADNAME
sub INITPADNAME {
    my ( $init, $padname, $number_of_items ) = @_;

    consume_malloc( $init, sizeof('PADNAME *') * $number_of_items );

    return sprintf( q{INITPADNAME(%s, %d)}, $padname, $number_of_items );
}

# this is a perl wrapper around the C call to INITPADLIST
sub INITPADLIST {
    my ( $init, $pad, $number_of_items ) = @_;

    consume_malloc( $init, sizeof('PAD *') * $number_of_items );

    return sprintf( q{INITPADLIST(%s, %d)}, $pad, $number_of_items );
}

sub HvAddEntry {
    my ( $init, $sym, $value, $shared_he, $max ) = @_;
    consume_malloc( $init, sizeof('HE') );

    return sprintf( q{HvAddEntry(%s, (SV*) %s, %s, %d)}, $sym, $value, $shared_he, $max );
}

sub INITAv {
    my ( $init, $sym, $number_of_items ) = @_;

    consume_malloc( $init, sizeof('SV *') * $number_of_items );

    return sprintf( q{INITAv(%s, %d)}, $sym, $number_of_items );
}

1;
