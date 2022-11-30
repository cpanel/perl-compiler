package B::PVMG;

use B::C::Std;

use B::C::Debug   qw/debug verbose WARN/;
use B             qw/SVf_IsCOW SVf_READONLY cchar SVp_POK svref_2object/;
use B::C::Save    qw/savecowpv/;
use B::C::Decimal qw/get_integer_value get_double_value/;
use B::C::File    qw/init init_static_assignments svsect xpvmgsect magicsect init_vtables/;

# usually 0x400000, but can be as low as 0x10000
# http://docs.embarcadero.com/products/rad_studio/delphiAndcpp2009/HelpUpdate2/EN/html/devcommon/compdirsimagebaseaddress_xml.html
# called mapped_base on linux (usually 0xa38000)
sub LOWEST_IMAGEBASE() { 0x10000 }

sub do_save ( $sv, $fullname = undef ) {

    my ( $ix, $sym ) = svsect()->reserve($sv);
    svsect()->debug( $fullname, $sv );

    my ( $sv_u, $cur, $len, $pv, $flags );
    if ( $fullname =~ m{^main::[1-9][0-9]*$} ) {    # Only modify $1,$2, ... etc.  $0 is magic
        $flags = $sv->FLAGS;
        $flags |= SVf_IsCOW;                        # flag it as COW as we are using the generic empty string
        $pv = "";
        ( $sv_u, $cur, $len ) = savecowpv($pv);
        $sv_u = ".svu_pv=(char*) $sv_u";
    }
    else {
        ( $sv_u, $cur, $len, $pv, $flags ) = $sv->save_svu( $sym, $sym, $fullname );
    }

    my $ivx = get_integer_value( $sv->IVX );    # XXX How to detect HEK* namehek?
    my $nvx = get_double_value( $sv->NVX );     # it cannot be xnv_u.xgv_stash ptr (BTW set by GvSTASH later)

    # See #305 Encode::XS: XS objects are often stored as SvIV(SvRV(obj)). The real
    # address needs to be patched after the XS object is initialized.
    # But how detect them properly?
    # Detect ptr to extern symbol in shared library and remap it in init2
    # Safe and mandatory currently only Net-DNS-0.67 - 0.74.
    # svop const or pad OBJECT,IOK
    if (
        # fixme simply the or logic
        ( ( $fullname and $fullname =~ /^svop const|^padop|^Encode::Encoding| :pad\[1\]/ ) )
        and $ivx > LOWEST_IMAGEBASE    # some crazy heuristic for a sharedlibrary ptr in .data (> image_base)
        and ref( $sv->SvSTASH ) ne 'B::SPECIAL'
    ) {
        # restore the old _patch_dlsym which is updating pointer to C functions
        $ivx = _patch_dlsym( $sv, $fullname, $ivx );
    }

    xpvmgsect()->comment("STASH, MAGIC, cur, len, xiv_u, xnv_u");
    my $xpvmg_ix = xpvmgsect()->sadd(
        "(HV*) %s, {%s}, %u, {%u}, {%s}, {%s}",
        $sv->save_magic_stash, $sv->save_magic($fullname), $cur, $len, $ivx, $nvx
    );

    my $sv_ix = svsect()->supdate(
        $ix,
        "&xpvmg_list[%d], %Lu, 0x%x, {%s}",
        $xpvmg_ix, $sv->REFCNT, $flags, $sv_u
    );

    return $sym;
}

# https://metacpan.org/pod/distribution/perl/pod/perlguts.pod
my $perl_magic_vtable_map = {

    # There is no corresponding PL_vtbl_ for these entries.
    '%' => undef,    # Extra data for restricted hashes - PERL_MAGIC_rhash
    ':' => undef,    # Extra data for symbol tables - toke.c - PERL_MAGIC_symtab
    'L' => undef,    # Debugger %_<filename - PERL_MAGIC_dbfile
    'S' => undef,    # %SIG hash - PERL_MAGIC_sig
    'V' => undef,    # SV was vstring literal - PERL_MAGIC_vstring

    # Die if we get these? Strip the magic and hope bootstrap puts them back??
    'u' => 0,        # Reserved for use by extensions - PERL_MAGIC_uvar_elem
    '~' => 0,        # Available for use by extensions - PERL_MAGIC_ext

    # All of these are PL_vtbl_$value so easily assigned on startup.
    chr(0) => 'sv',               # Special scalar variable ( \0 )
    '#'    => 'arylen',           # Array length ($#ary)
    '*'    => 'debugvar',         # $DB::single, signal, trace vars
    '.'    => 'pos',              # pos() lvalue
    '<'    => 'backref',          # For weak ref data
    '@'    => 'arylen_p',         # To move arylen out of XPVAV
    'B'    => 'bm',               # Boyer-Moore (fast string search)
    'c'    => 'ovrld',            # Holds overload table (AMT) on stash - PERL_MAGIC_overload_table
    'D'    => 'regdata',          # Regex match position data (@+ and @- vars)
    'd'    => 'regdatum',         # Regex match position data element
    'E'    => 'env',              # %ENV hash
    'e'    => 'envelem',          # %ENV hash element
    'f'    => 'fm',               # Formline ('compiled' format)
    'g'    => 'mglob',            # m//g target - PERL_MAGIC_regex_global
    'H'    => 'hints',            # %^H hash
    'h'    => 'hintselem',        # %^H hash element
    'I'    => 'isa',              # @ISA array
    'i'    => 'isaelem',          # @ISA array element
    'k'    => 'nkeys',            # scalar(keys()) lvalue
    'l'    => 'dbline',           # Debugger %_<filename element
    'N'    => 'shared',           # Shared between threads
    'n'    => 'shared_scalar',    # Shared between threads
    'o'    => 'collxfrm',         # Locale transformation
    'P'    => 'pack',             # Tied array or hash - PERL_MAGIC_tied
    'p'    => 'packelem',         # Tied array or hash element - PERL_MAGIC_tiedelem
    'q'    => 'packelem',         # Tied scalar or handle - PERL_MAGIC_tiedscalar
    'r'    => 'regexp',           # Precompiled qr// regex - PERL_MAGIC_qr
    's'    => 'sigelem',          # %SIG hash element
    't'    => 'taint',            # Taintedness
    'U'    => 'uvar',             # Available for use by extensions
    'v'    => 'vec',              # vec() lvalue
    'w'    => 'utf8',             # Cached UTF-8 information
    'x'    => 'substr',           # substr() lvalue
    'y'    => 'defelem',          # Shadow "foreach" iterator variable smart parameter vivification
    'Y'    => 'nonelem',          # Array element that does not exist - introduced in 5.28
    '\\'   => 'lvref',            # Lvalue reference constructor
    ']'    => 'checkcall',        # Inlining/mutation of call to this CV
};

sub save_magic ( $sv, $fullname ) {

    my $sv_flags = $sv->FLAGS;
    my $pkg;

    # Protect our SVs against non-magic or SvPAD_OUR. Fixes tests 16 and 14 + 23
    return '0' if ( !$sv->MAGICAL );

    my @mgchain    = $sv->MAGIC;
    my $last_magic = '0';
    foreach my $mg ( reverse @mgchain ) {    # reverse because we're assigning down the chain, not up.
        my $type = $mg->TYPE;
        my $ptr  = $mg->BCPTR;
        my $len  = $mg->LENGTH;

        exists $perl_magic_vtable_map->{$type} or die sprintf( "Unknown magic type '0x%s' / '%s' [check your mapping table dude]", unpack( 'H*', $type ), $type );
        my $vtable = $perl_magic_vtable_map->{$type};

        if ( defined $vtable and $vtable eq '0' ) {
            next;

            # Remove the next above and Moose (xtestc/0350.t and xtestc/0371.t will exit B::C over this.)
            warn("We don't know how to handle or what uses u or ~ magic ???\n");
            warn("Got ptr == $ptr\n");
            warn("Got len == $len\n");
            warn("Got type == $type\n");
            exit 6;
        }

        ### view Perl_magic_freeovrld: contains a list of memory addresses to CVs...
        ###     the first call to Gv_AMG should recompute the cache
        ###     we are saving (( and other '(*' overload methods, like for example ("" for the str overload
        ### maybe we simply want to run Gv_AMG on the stash at init time
        next if $type eq 'c';

        # Save the object if there is one.
        my $obj = '0';
        if ( $type !~ /^[rnD]$/ ) {
            my $o = $mg->OBJ;
            $obj = $o->save($fullname) if ( ref $o ne 'SCALAR' );
        }
        elsif ( $type eq 'D' ) {

            # For D Magic, this number is not a pointer. It corresponds to the char value of the variable
            # i.e. char 43 == '+' for @+
            $obj = $mg->OBJ_PTR();
        }

        my $ptrsv = '0';
        my $init_ptrsv;
        {    # was if $len == HEf_SVKEY

            # The pointer is an SV* ('s' sigelem e.g.)
            # XXX On 5.6 ptr might be a SCALAR ref to the PV, which was fixed later
            if ( !defined $ptr ) {
                $ptrsv = '0';
            }
            elsif ( ref($ptr) eq 'SCALAR' ) {
                warn("We don't think anything happens here. Contact us if your program doesn't compile because of this.;\n");
                exit 7;

                $init_ptrsv = "SvPVX(" . svref_2object($ptr)->save($fullname) . ")";
            }
            elsif ( ref $ptr ) {

                # Certain magic type actually point to a PMOP or a SVPV. We save them here.
                # NOTE: This is thanks to BCPTR which needs to backport to B.xs
                $ptrsv = ref $ptr =~ m/OP/ ? $ptr->save() : $ptr->save($fullname);
            }
            else {
                ( $ptrsv, undef, undef ) = savecowpv($ptr) if defined $ptr;
            }
        }

        magicsect->comment('mg_moremagic, mg_virtual, mg_private, mg_type, mg_flags, mg_len, mg_obj, mg_ptr');

        my $last_magic_ix = magicsect->saddl(
            '(MAGIC*) %s'  => $last_magic,     # mg_moremagic
            '(MGVTBL*) %s' => '0',             # mg_virtual
            '%s'           => $mg->PRIVATE,    # mg_private
            '%s'           => cchar($type),    # mg_type
            '0x%x'         => $mg->FLAGS,      # mg_flags
            '%s'           => $len,            # mg_len
            '(SV*) %s'     => $obj,            # mg_obj
            '(char*) %s'   => $ptrsv,          # mg_ptr
        );
        $last_magic = sprintf( 'magic_list[%d]', $last_magic_ix );

        if ($init_ptrsv) {
            init_static_assignments()->sadd( q{%s.mg_ptr = (char*) %s;}, $last_magic, $init_ptrsv );
        }

        if ($vtable) {

            # simplified version
            #init_vtables()->sadd( 'magic_list[%d].mg_virtual = (MGVTBL*) &PL_vtbl_%s;', $last_magic_ix, $vtable );
            # taking care of the group
            init_vtables()->add_pvmg( $last_magic_ix, $vtable );
        }
        $last_magic = "&" . $last_magic;
    }

    return $last_magic;
}

sub save_magic_stash {
    my $sv = shift or die("save_magic_stash is a method call!");

    my $symbol = $sv->SvSTASH->save || return q{0};

    return q{0} if $symbol eq 'Nullsv';
    return q{0} if $symbol eq 'Nullhv';
    return "(HV*) $symbol";
}

###

# TODO: This was added to PVMG because we thought it was only used in this op but
# as of 5.18, it's used in B::CV::save
sub _patch_dlsym ( $sv, $fullname, $ivx ) {

    my $pkg = '';
    if ( ref($sv) eq 'B::PVMG' ) {
        my $stash = $sv->SvSTASH;
        $pkg = $stash->can('NAME') ? $stash->NAME : '';
    }
    my $name   = $sv->FLAGS & SVp_POK() ? $sv->PVX : "";
    my $ivxhex = sprintf( "0x%x", $ivx );

    # lazy load encode after walking the optree
    if ( $pkg eq 'Encode::XS' ) {
        $pkg = 'Encode';
        if ( $fullname eq 'Encode::Encoding{iso-8859-1}' ) {
            $name = "iso8859_1_encoding";
        }
        elsif ( $fullname eq 'Encode::Encoding{null}' ) {
            $name = "null_encoding";
        }
        elsif ( $fullname eq 'Encode::Encoding{ascii-ctrl}' ) {
            $name = "ascii_ctrl_encoding";
        }
        elsif ( $fullname eq 'Encode::Encoding{ascii}' ) {
            $name = "ascii_encoding";
        }

        if ( $name and $name =~ /^(ascii|ascii_ctrl|iso8859_1|null)/ ) {
            my $enc = 'Encode'->can('find_encoding')->($name);
            $name .= "_encoding" unless $name =~ /_encoding$/;
            $name =~ s/-/_/g;
            verbose("$pkg $Encode::VERSION with remap support for $name (find 1)");
        }
        else {
            for my $n ( Encode::encodings() ) {    # >=5.16 constsub without name
                my $enc = Encode::find_encoding($n);
                if ( $enc and ref($enc) ne 'Encode::XS' ) {    # resolve alias such as Encode::JP::JIS7=HASH(0x292a9d0)
                    $pkg = ref($enc);
                    $pkg =~ s/^(Encode::\w+)(::.*)/$1/;        # collapse to the @dl_module name
                    $enc = Encode->find_alias($n);
                }
                if ( $enc and ref($enc) eq 'Encode::XS' and $sv->IVX == $$enc ) {
                    $name = $n;
                    $name =~ s/-/_/g;
                    $name .= "_encoding" if $name !~ /_encoding$/;
                    if ( $pkg ne 'Encode' ) {
                        verbose( "saving $pkg" . "::bootstrap" );
                        svref_2object( \&{"$pkg\::bootstrap"} )->save;
                    }
                    last;
                }
            }
            if ($name) {
                verbose("$pkg $Encode::VERSION remap found for constant $name");
            }
            else {
                WARN("Warning: Possible missing remap for compile-time XS symbol in $pkg $fullname $ivxhex [#305]");
            }
        }
    }
    elsif ( $pkg eq 'Net::LibIDN' ) {
        $name = "idn_to_ascii";
    }

    # new API (only Encode so far)
    if ( $pkg and $name and $name =~ /^[a-zA-Z_0-9-]+$/ ) {    # valid symbol name
                                                               # unfortunately cannot use our BOOTSTRAP_XS logic there as
                                                               #   Perl_gv_fetchpv("Encode::ascii_encoding", 0, SVt_PVCV)
                                                               # is going to return an 0
                                                               # need to use the dlopen + dlsym method

        my $id = xpvmgsect()->index + 1;

        verbose("add remap for ${pkg}: $name $ivxhex in xpvmg_list[$id]");

        $B::C::remap_xs_symbols{$pkg}{MG} //= [];
        push @{ $B::C::remap_xs_symbols{$pkg}{MG} }, { NAME => $name, ID => $id };

        $ivx = "0UL /* remap $ivxhex => $name */";
    }
    else {
        WARN("Warning: Possible missing remap for compile-time XS symbol in $pkg $fullname $ivx [#305]");
    }

    return $ivx;
}

1;
