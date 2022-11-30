package B::HV;

use B::C::Std;

use B               qw/svref_2object SVf_READONLY SVf_PROTECT SVf_OOK SVf_AMAGIC/;
use B::C::Debug     qw/debug WARN/;
use B::C::File      qw/init xpvhvsect xpvhv_with_auxsect svsect decl init init2 init_stash init_static_assignments/;
use B::C::Save::Hek qw/save_shared_he get_sHe_HEK/;

=pod

v5.35.5 introduces XPVHV_WITH_AUX by 94ee6ed79dbca73d0345b745534477e4017fb990

    struct xpvhv_with_aux {
        HV         *xmg_stash;      /* class package */
        union _xmgu xmg_u;
        STRLEN      xhv_keys;       /* total keys, including placeholders */
        STRLEN      xhv_max;        /* subscript of last element of xhv_array */
        struct xpvhv_aux xhv_aux;
    };

    typedef struct xpvhv_with_aux XPVHV_WITH_AUX;

-#define HvAUX(hv)       ((struct xpvhv_aux*)&(HvARRAY(hv)[HvMAX(hv)+1]))
+#define HvAUX(hv)       (&(((struct xpvhv_with_aux*)  SvANY(hv))->xhv_aux))

=cut

sub can_save_stash ($stash_name) {

    #return get_current_stash_position_in_starting_stash ( $stash_name ) ? 1 : 0;

    return 1 if $stash_name eq 'main';

    $stash_name =~ s{::$}{};
    $stash_name =~ s{^main::}{};

    # ... do something with names containing a pad FIXME ( new behavior good to have )

    my $starting_flat_stashes = $B::C::settings->{'starting_flat_stashes'} or die;
    return $starting_flat_stashes->{$stash_name} ? 1 : 0;    # need to skip properly ( maybe just a protection there
}

sub key_was_missing_from_stash_at_compile ( $stash_name, $key, $curstash ) {

    ### STATIC_HV need improvement there - using a more generic method for whitelisting
    if ( !$stash_name && $key && $key =~ qr{^B::C::} ) {
        return 1;
    }

    # when it s not a stash (noname) we always want to save all the keys from the hash
    return 0 unless $stash_name;

    # if do not have a pointer to a stash in starting_stash, we should not save the key
    return 1 if ref $curstash ne 'HASH';

    # no need to check if the stash name is in starting_stashes ( we know this for sure )

    # was the key defined at startup by starting_stash() ?
    return !$curstash->{$key};
}

# our only goal here is to get the curstash position in starting_stash if it exists
sub get_current_stash_position_in_starting_stash ($stash_name) {

    return unless $stash_name;    # <---- we want to save all *keys*

    $stash_name =~ s{::$}{};
    $stash_name =~ s{^main::}{};

    my $curstash = $B::C::settings->{'starting_stash'};

    if ( $stash_name ne 'main' ) {
        foreach my $sect ( split( '::', $stash_name ) ) {
            $curstash = $curstash->{ $sect . '::' } or return;    # Should never happen.
            ref $curstash eq 'HASH'                 or return;
        }
    }

    return $curstash;
}

sub do_save ( $hv, $fullname = undef ) {

    $fullname ||= '';
    my $stash_name = $hv->NAME;
    $hv->FLAGS & 2048 and die sprintf( "Unexpected SVf_ROK found in %s\n", ref $hv );

    #debug( hv => "XXXX HV fullname %s // name %s", $fullname, $stash_name );
    if ($stash_name) {

        $stash_name =~ s/^main::(.+)$/$1/;    # Strip off main:: on everything but main::

        if ( !can_save_stash($stash_name) ) {
            debug( hv => 'skipping stash ' . $stash_name );
            return q{NULL};
        }
        debug( hv => 'Saving stash ' . $stash_name );
    }

    my ( $ix, $sym ) = svsect()->reserve( $hv, 'HV*' );
    svsect()->debug( $fullname, $hv );

    my $cache_stash_entry;

    my $current_stash_position_in_starting_stash = get_current_stash_position_in_starting_stash($stash_name);

    # reduce the content
    # remove values from contents we are not going to save
    my @hash_content_to_save;
    my @contents = $hv->ARRAY;

    if (@contents) {
        my ( $i, $length );
        $length = scalar(@contents);

        # Walk the values and save them into symbols
        for ( $i = 1; $i < @contents; $i += 2 ) {
            my $key = $contents[ $i - 1 ];    # string only
            my $sv  = $contents[$i];
            my $value;

            if ( key_was_missing_from_stash_at_compile( $stash_name, $key, $current_stash_position_in_starting_stash ) ) {
                debug( hv => '...... Skipping key "%s" from stash "%s" (missing) ', $key, $stash_name );
                next;
            }

            debug( hv => "saving HV [ $i / len=$length ]\$" . $fullname . '{' . $key . "} 0x%0x", $sv );
            $value = $sv->save( $fullname . '{' . $key . '}' );    # Turn the hash value into a symbol

            if ( $fullname && $fullname eq 'main::SIG' ) {
                $B::C::mainSIGs{$key} = $value;
            }

            next if $value eq q{NULL};                             # this can comes from ourself ( view above )

            push @hash_content_to_save, [ $key, $value ] if defined $value;
        }
    }

    # Ordinary HV or Stash
    # KEYS = 0, inc. dynamically below with hv_store

    my $hv_total_keys = scalar(@hash_content_to_save);
    my $max           = get_max_hash_from_keys($hv_total_keys);

    my $flags   = $hv->FLAGS & ~SVf_READONLY & ~SVf_PROTECT;
    my $has_ook = $flags & SVf_OOK ? q{TRUE} : q{FALSE};       # only need one AUX when OOK is set

    my $xpvh_sym;

    if ( $has_ook eq q{TRUE} ) {
        xpvhv_with_auxsect()->comment("xmg_stash, xmg_u, xhv_keys, xhv_max, struct xpvhv_aux");
        xpvhv_with_auxsect()->saddl(
            '%s'   => $hv->save_magic_stash,                                                           # xmg_stash
            '{%s}' => $hv->save_magic( length $stash_name ? '%' . $stash_name . '::' : $fullname ),    # mgu
            '%d'   => $hv_total_keys,                                                                  # xhv_keys
            '%d'   => $max,                                                                            # xhv_max
            '%s'   => '{0}',                                                                           # struct xpvhv_aux
        );

        $xpvh_sym = sprintf( "xpvhv_with_aux_list[%d]", xpvhv_with_auxsect()->index );
    }
    else {
        xpvhvsect()->comment("xmg_stash, xmg_u, xhv_keys, xhv_max");
        xpvhvsect()->saddl(
            '%s'   => $hv->save_magic_stash,                                                           # xmg_stash
            '{%s}' => $hv->save_magic( length $stash_name ? '%' . $stash_name . '::' : $fullname ),    # mgu
            '%d'   => $hv_total_keys,                                                                  # xhv_keys
            '%d'   => $max                                                                             # xhv_max
        );

        $xpvh_sym = sprintf( "xpvhv_list[%d]", xpvhvsect()->index );
    }

    # replace the previously saved svsect with some accurate content
    svsect()->update(
        $ix,
        sprintf(
            "&%s, %Lu, 0x%x, {0}",
            $xpvh_sym, $hv->REFCNT, $flags
        )
    );

    my $init = $stash_name ? init_stash() : init_static_assignments();

    my $backrefs_sym = 0;
    if ( my $backrefs = $hv->BACKREFS ) {

        # backref is by default a list AV, but when only one single GV is in this list, then the AV is saved
        if ( ref $backrefs eq 'B::AV' ) {
            $backrefs_sym = $backrefs->save( undef, undef, 'backref_save' );
        }
        else {
            # backrefs is not an array - single element list - backrefs=GV
            if ( !B::AV::skip_backref_sv($backrefs) ) {
                $backrefs_sym = $backrefs->save();
            }
        }
    }

    $init->open_block( $stash_name ? "STASH declaration for ${stash_name}::" : '' );

    {    # add hash content even if the hash is empty [ maybe only for %INC ??? ]
        $init->add( B::C::Memory::HvSETUP( $init, $sym, $max + 1, $has_ook, $backrefs_sym ) );

        my @hash_elements;
        {
            my $i       = 0;
            my %hash_kv = ( map { $i++, $_ } @hash_content_to_save );
            @hash_elements = values %hash_kv;    # randomize the hash eleement order to the buckets [ when coliding ]
        }

        # uncomment for saving hashes in a consistent order while debugging
        #@hash_elements = @hash_content_to_save;

        foreach my $elt (@hash_elements) {
            my ( $key, $value ) = @$elt;

            # Insert each key into the hash.
            my ($shared_he) = save_shared_he($key);
            $init->sadd(
                "%s; /* %s */",
                B::C::Memory::HvAddEntry( $init, $sym, $value, $shared_he, $max ), $key
            );
        }
    }

    $init->add("SvREADONLY_on($sym);") if $hv->FLAGS & SVf_READONLY;

    # Setup xhv_name_u and xhv_name_count in the AUX section of the hash via hv_name_set.
    my @enames     = $hv->ENAMES;
    my $name_count = $hv->name_count;

    #warn("Found an example of a non-zero HvAUX name_count!") if $name_count;
    if ( scalar @enames and !length $enames[0] and $stash_name ) {
        warn("Found empty ENAMES[0] for $stash_name");
    }

    foreach my $hash_name (@enames) {
        next unless length $hash_name;
        my ($shared_he) = save_shared_he($hash_name);
        $init->sadd( q{HvAUX(%s)->xhv_name_u.xhvnameu_name = %s; /* %s */}, $sym, get_sHe_HEK($shared_he), $hash_name );
    }

    # Special stuff we want to do for stashes.
    if ( length $stash_name ) {

        # SVf_AMAGIC is set on almost every stash until it is
        # used.  This forces a transversal of the stash to remove
        # the flag if its not actually needed.
        # fix overload stringify
        # Gv_AMG: potentially removes the AMG flag
        if ( $hv->FLAGS & SVf_AMAGIC ) {    #and $hv->Gv_AMG
            my $do_mro_isa_changed = eval { $hv->Gv_AMG };
            $do_mro_isa_changed = 1 if $@;    # fallback - view xtestc/0184.t
            init2()->sadd( "mro_isa_changed_in(%s);  /* %s */", $sym, $stash_name ) if $do_mro_isa_changed;
        }
        my $get_mro = ( scalar %main::mro:: ) ? mro->can('get_mro') : 0;
        if ( $stash_name ne 'mro' and $get_mro and $get_mro->($stash_name) eq 'c3' ) {
            init2()->sadd( 'Perl_mro_set_mro(aTHX_ HvMROMETA(%s), newSVpvs("c3")); /* %s */', savestashpv($stash_name), $stash_name );
        }
    }

    # close our HvSETUP block
    $init->close_block;

    return $sym;
}

sub nextPowerOf2 ($n) {

    my $count = 0;

    while ( $n != 0 ) {
        $n >>= 1;
        ++$count;
    }

    return 1 << $count;
}

sub get_max_hash_from_keys ( $keys, $minimum = 7 ) {

    my $keys_max = nextPowerOf2( $keys + $keys >> 1 ) - 1;    # 15

    return $keys_max < $minimum ? $minimum : $keys_max;
}

sub savestashpv ($name) {    # save a stash from a string (pv)

    no strict 'refs';
    return svref_2object( \%{ $name . '::' } )->save;
}

1;
