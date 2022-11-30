package B::INVLIST;

use B::C::Std;

use B           qw/SVf_IsCOW SVf_ROK SVf_POK SVp_POK SVs_GMG SVt_PVGV SVf_READONLY SVf_FAKE/;
use B::C::Debug qw/debug/;
use B::C::File  qw/svsect xinvlistsect invlistarray/;

sub do_save ( $sv, $fullname = undef, $custom = undef ) {

    my ( $ix, $sym ) = svsect()->reserve($sv);
    svsect()->debug( $fullname, $sv );

    my $flags      = $sv->FLAGS;
    my $offset     = $sv->is_offset;
    my $prev_index = $sv->prev_index;

    my @array = $sv->get_invlist_array();

    # use Data::Dumper qw/Dumper/;
    # print STDERR Dumper( \@array );
    #print STDERR "-- use invlist... $offset ". join( ', ', @array ) . " # ". $sv->CUR / 4 .  "\n";

    if ( $sv->CUR <= 0 ) {

        # this should not happen, this is a protection to investigate if this occurs
        die q[Do not know how to handle empty invlist.];
    }

    if ($offset) {

        # need to confirm we are storing the full invlist when using an offset
        die q[Offset used in invlist: need to check...];
    }

    # can optimize to duplicate the arrays and return the value to the other one
    my $invlistarray_ix = $sv->_get_invlist_array_index($sym);

    xinvlistsect()->comment("xmg_stash, xmg_u, xpv_cur, xpv_len_u, prev_index, iterator, is_offset");
    xinvlistsect()->saddl(

        # _XPV_HEAD
        '%s'   => 'Nullhv',                      # HV* xmg_stash
        '{%s}' => '0',                           # union _xmgu xmg_u;
        '%d'   => $sv->CUR,                      # STRLEN      xpv_cur;
        '%d'   => $sv->LEN,                      # union      xpv_len_u;
                                                 # xpvinvlist
        '%d'   => 0,                             # nnnIV          prev_index;     /* caches result of previous invlist_search() */
                                                 # UV_MAX value is set by invlist_iterfinish
        '%s'   => 'UV_MAX',                      # UV_MAX STRLEN      iterator;       /* Stores where we are in iterating */
        '%s'   => $offset ? 'TRUE' : 'FALSE',    # bool        is_offset;
    );

    # invlist_array is a metalist containing all invlist values...
    #   we just want a pointer to the first invlist element
    svsect()->update(
        $ix,
        sprintf(
            "&xinvlist_list[%d], %Lu, 0x%x, {.svu_pv= (char*) ( invlist_array + %d ) }",
            xinvlistsect()->index, $sv->REFCNT, $flags, $invlistarray_ix,
        )
    );

    return $sym;
}

=pod

_get_invlist_array_index:

add the UV array to the global array
returns the index in the array

Detect duplicate lists and return the index to the previously cached one

=cut

our %CACHE;

sub _get_invlist_array_index ( $sv, $sym ) {

    $sym =~ s{^&}{};    # strip the pointer to the symbol (only used by comments)

    my @array = $sv->get_invlist_array();

    my $key = join( ':', @array );

    my $ix = $CACHE{$key};
    if ( defined $ix ) {

        # augment the comment before the first value
        my $value = invlistarray()->{values}->[$ix];
        $value =~ s{used by: (.*) \*/}{used by: $1, $sym */};
        invlistarray()->{values}->[$ix] = $value;

        return $CACHE{$key};
    }

    # can optimize to duplicate the arrays and return the value to the other one
    $ix = invlistarray->index + 1;
    if ( my $len = scalar @array ) {

        #invlistarray->comment( "invlist used by: $sym" );
        my $first = 1;
        foreach my $uv (@array) {
            my $comment = '';

            if ($first) {
                $first   = 0;
                $comment = "/* invlist at invlist_array[$ix] LEN=$len used by: $sym */\n\t";
            }

            invlistarray->saddl( "%s0x%X", [ $comment, $uv ] );
        }
    }

    return $CACHE{$key} = $ix;
}

1;

__END__

struct xpvinvlist {
    _XPV_HEAD;
    IV          prev_index;     /* caches result of previous invlist_search() */
    STRLEN  iterator;       /* Stores where we are in iterating */
    bool    is_offset;  /* The data structure for all inversion lists
                                   begins with an element for code point U+0000.
                                   If this bool is set, the actual list contains
                                   that 0; otherwise, the list actually begins
                                   with the following element.  Thus to invert
                                   the list, merely toggle this flag  */
};


* What s the difference between `PL_XPosix_ptrs[_CC_WORDCHAR]` and `PL_Posix_ptrs[_CC_WORDCHAR]`?
> the X stands for extended, and hence includes all of Unicode.  plain PL_Posix refers to ASCII restricted

Perl_invlist_clone in regcomp.c show how to create one invlist
