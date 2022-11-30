#      C.pm
#
#      Copyright (c) 1996, 1997, 1998 Malcolm Beattie
#      Copyright (c) 2008, 2009, 2010, 2011 Reini Urban
#      Copyright (c) 2010 Nick Koston
#      Copyright (c) 2011, 2012, 2013, 2014, 2015 cPanel Inc
#
#      You may distribute under the terms of either the GNU General Public
#      License or the Artistic License, as specified in the README file.
#

package B::C;
use strict;

# From C.pm
our %Config;
our %mainSIGs;
our ( $VERSION, $caller, $nullop_count, $unresolved_count, $gv_index, $settings );
our ( @ISA, @EXPORT_OK );

BEGIN {
    use B::C::Flags ();
    *Config = \%B::C::Flags::Config;
}

use B::Flags;
use B::C::Debug qw(debug verbose WARN INFO);    # used for setting debug levels from cmdline

use B::C::File qw( init2 init1 init0 init decl free
  heksect binopsect condopsect copsect padopsect listopsect logopsect magicsect
  opsect pmopsect pmopauxsect pvopsect svopsect unopsect svsect xpvsect xpvavsect xpvhvsect xpvcvsect xpvivsect xpvuvsect
  xpvnvsect xpvmgsect xpvlvsect xrvsect xpvbmsect xpviosect xsaccessorsect lexwarnsect refcounted_he padlistsect loopsect
  lazyregex sharedhe init_stash init_COREbootstraplink init_bootstraplink init_xsaccessor
);
use B::C::Helpers::Symtable qw(objsym savesym);
use Exporter                ();
use Errno                   ();                   #needed since 5.14

BEGIN {
    # always boot XS now that we have the heavy version
    require XSLoader;
    no warnings;
    XSLoader::load('B::C');
}

use B::C::Memory ();                              # after loading C.xs

# for 5.6.[01] better use the native B::C
# but 5.6.2 works fine
use B qw(minus_c sv_undef walkoptree walkoptree_slow main_root main_start peekop
  class cchar svref_2object compile_stats comppadlist hash
  init_av end_av opnumber cstring main_cv
  SVf_POK SVf_ROK SVf_IOK SVf_NOK SVf_IVisUV SVf_READONLY SVf_PROTECT);

BEGIN {
    @B::NV::ISA = 'B::IV';    # add IVX to nv. This fixes test 23 for Perl 5.8
    B->import(qw(regex_padav SVp_NOK SVp_IOK CVf_CONST CVf_ANON SVt_PVGV));
}

use B::C::XS       ();
use B::C::OverLoad ();

# FIXME: this part can now be dynamic
# exclude all not B::C:: prefixed subs
# used in CV
our %all_bc_deps;

BEGIN {
    # track all internally used packages. all other may not be deleted automatically
    # - hidden methods
    # uses now @B::C::Flags::deps
    %all_bc_deps = map { $_ => 1 } @B::C::Flags::deps;
}

our ( %xsub, %remap_xs_symbols );
our ( %dumped_package, %skip_package, %isa_cache );

# STATIC HV: do we want to preserve the ability to compile in Devel::Peek ? lazy loading it is fine and acceptable
our ($devel_peek_needed);

our @xpvav_sizes;

sub start_heavy {
    my $settings = $B::C::settings;

    B::C::Debug::setup_debug( $settings->{'debug_options'}, $settings->{'enable_verbose'}, $settings->{'enable_debug'} );

    my $output_file = $settings->{'output_file'} or die("Please supply a -o option to B::C");
    B::C::File->new($output_file);    # Singleton.

    $settings->{'XS'} = B::C::XS->new(
        {
            'output_file'  => $output_file,
            'core_subs'    => $settings->{'CORE_subs'},
            'starting_INC' => $settings->{'starting_INC'},
            'dl_so_files'  => $settings->{'dl_so_files'},
            'dl_modules'   => $settings->{'dl_modules'},
        }
    );

    {
        no warnings 'redefine';

        # do not store the patches
        my ( $bincompat, $non_bincompat, $date, @patches ) = Internals::V();

        # Config_heavy and other could require these internal informations
        #   use an eval to clear the references and convert the PVs to constant
        # examples:
        # bincompat:      HAS_TIMES PERLIO_LAYERS USE_64_BIT_INT USE_LARGE_FILES USE_LOCALE_COLLATE USE_LOCALE_NUMERIC USE_LOCALE_TIME USE_PERLIO
        # non_bincompat:  PERL_COPY_ON_WRITE PERL_DISABLE_PMC PERL_DONT_CREATE_GVSV PERL_MALLOC_WRAP PERL_OP_PARENT PERL_PRESERVE_IVUV PERL_USE_DEVEL USE_LOCALE USE_LOCALE_CTYPE USE_PERL_ATOF
        # date:           Compiled at Feb 15 2019 18:58:02
        *Internals::V = eval qq[sub { return ( "$bincompat", "$non_bincompat", "$date", "patches list removed" ) }];
    }

    die q[Class::XSAccessor::Array is not supported] if $INC{'Class/XSAccessor/Array.pm'};

    # Save some stuff we need to save early.
    save_pre_defstash();

    # save all our stashes at startup only
    save_defstash();

    # first iteration over the main tree
    save_optree();

    # fixups: wtf we could have miss during our initial walk...
    save_main_rest();

    return;
}

# used by B::OBJECT
sub add_to_isa_cache {
    my ( $k, $v ) = @_;
    die unless defined $k;

    $isa_cache{$k} = $v;
    return;
}

# This the Carp free workaround for DynaLoader::bootstrap
BEGIN {
    # Scoped no warnings without loading the module.
    local $^W;
    BEGIN { ${^WARNING_BITS} = 0; }
    *DynaLoader::croak = sub { die @_ }
}

sub get_isa ($) {
    no strict 'refs';

    my $name = shift;
    return @{ B::C::get_linear_isa($name) };
}

# try_isa($pkg,$name) returns the found $pkg for the method $pkg::$name
# If a method can be called (via UNIVERSAL::can) search the ISA's. No AUTOLOAD needed.
# https://code.google.com/archive/p/perl-compiler/issues/64, empty @ISA if a package has no subs. in Bytecode ok
sub try_isa {
    my ( $cvstashname, $cvname ) = @_;
    return 0 unless defined $cvstashname;
    if ( my $found = $isa_cache{"$cvstashname\::$cvname"} ) {
        return $found;
    }
    no strict 'refs';

    # XXX theoretically a valid shortcut. In reality it fails when $cvstashname is not loaded.
    # return 0 unless $cvstashname->can($cvname);
    my @isa = get_isa($cvstashname);
    debug(
        cv => "No definition for sub %s::%s. Try \@%s::ISA=(%s)",
        $cvstashname, $cvname, $cvstashname, join( ",", @isa )
    );
    for (@isa) {    # global @ISA or in pad
        next if $_ eq $cvstashname;
        debug( cv => "Try &%s::%s", $_, $cvname );
        if ( defined( &{ $_ . '::' . $cvname } ) ) {
            if ( exists( ${ $cvstashname . '::' }{ISA} ) ) {
                svref_2object( \@{ $cvstashname . '::ISA' } )->save("$cvstashname\::ISA");
            }
            $isa_cache{"$cvstashname\::$cvname"} = $_;
            return $_;
        }
        else {
            $isa_cache{"$_\::$cvname"} = 0;
            if ( get_isa($_) ) {
                my $parent = try_isa( $_, $cvname );
                if ($parent) {
                    $isa_cache{"$_\::$cvname"}           = $parent;
                    $isa_cache{"$cvstashname\::$cvname"} = $parent;
                    debug( gv => "Found &%s::%s", $parent, $cvname );
                    if ( exists( ${ $parent . '::' }{ISA} ) ) {
                        debug( pkg => "save \@$parent\::ISA" );
                        svref_2object( \@{ $parent . '::ISA' } )->save("$parent\::ISA");
                    }
                    if ( exists( ${ $_ . '::' }{ISA} ) ) {
                        debug( pkg => "save \@$_\::ISA\n" );
                        svref_2object( \@{ $_ . '::ISA' } )->save("$_\::ISA");
                    }
                    return $parent;
                }
            }
        }
    }
    return 0;    # not found
}

my $longest_warnings;

sub longest_warnings_string {
    my $len = shift or return $longest_warnings;

    $longest_warnings //= $len;
    $longest_warnings = $len if $longest_warnings < $len;

    return $longest_warnings;
}

my $longest_refcounted_he_value;

sub longest_refcounted_he_value {
    my $len = shift or return $longest_refcounted_he_value || 1;

    $longest_refcounted_he_value //= $len;
    $longest_refcounted_he_value = $len if $longest_refcounted_he_value < $len;

    return $longest_refcounted_he_value;
}

sub make_nonxs_Internals_V {
    my $to_eval = 'no warnings "redefine"; sub Internals::V { return (';
    foreach my $line ( Internals::V() ) {
        $line =~ s/'/\\'/g;
        $to_eval .= "'$line', ";
    }
    chop $to_eval;
    chop $to_eval;
    $to_eval .= ')};';
    eval $to_eval;
}

sub save_pre_defstash {

    make_nonxs_Internals_V();

    # We need to save the INC GV before ANYTHING else is allowed to happen or we'll corrupt it.
    my %INC_BACKUP = %INC;
    %INC = %{ $settings->{'starting_INC'} };
    svref_2object( \%main::INC )->save("main::INC");
    %INC = %INC_BACKUP;

    # We need mro to save stashes but loading it alters the mro (and next) stash.
    # The real fix is that we need C.xs to provide mro::get_mro so we don't need to require mro at all.
    if (%mro::) {
        svref_2object( \%mro:: )->save("mro::");
    }

    if (%next::) {
        svref_2object( \%next:: )->save("next::");
    }

    if ( %maybe:: && %maybe::next:: ) {
        svref_2object( \%maybe::next:: )->save("maybe::next::");
    }

    # avoid B::C and B symbols being stored - note B/C is not loading Exporter anymore
    if ( $B::C::settings->{'starting_flat_stashes'}->{'Exporter'} ) {
        my %backup_Exporter_Cache = (%Exporter::Cache);
        %Exporter::Cache = ();
        svref_2object( \%Exporter:: )->save("Exporter::");
        %Exporter::Cache = (%backup_Exporter_Cache);    # restore it
    }

    # do we have something else than PerlIO/scalar/scalar.so ?
    # there is something with PerlIO and PerlIO::scalar ( view in_static_core )
    if ( scalar @{ $settings->{'dl_modules'} } && scalar @{ $settings->{'dl_so_files'} } ) {    # Backup what we had in the DynaLoader arrays prior to C_Heavy
        my @modules = @DynaLoader::dl_modules;
        my @so      = @DynaLoader::dl_shared_objects;

        @DynaLoader::dl_modules        = @{ $settings->{'dl_modules'} };
        @DynaLoader::dl_shared_objects = @{ $settings->{'dl_so_files'} };

        svref_2object( \*DynaLoader::dl_modules )->save('@DynaLoader::dl_modules');
        svref_2object( \*DynaLoader::dl_shared_objects )->save('@DynaLoader::dl_shared_objects');

        @DynaLoader::dl_modules        = @modules;
        @DynaLoader::dl_shared_objects = @so;
    }

    # foreach my $stash ( qw{XSLoader DynaLoader} ) {
    #     no strict 'refs';
    #     #svref_2object( \%{ $stash . '::' } )->save( $stash .q{::} ) if B::HV::can_save_stash( $stash );
    # }
}

# Returns the symbol that will become &PL_defstash
sub save_defstash {

    my $PL_defstash = svref_2object( \%main:: )->save('main');

    $PL_defstash .= ' /* PL_defstash */';    # add a comment so we can easily detect it in our source code

    return $PL_defstash;
}

sub save_optree {
    debug("Starting compile");
    debug("Walking optree");
    _delete_macros_vendor_undefined();

    if ( debug('walk') ) {
        debug("Enabling B::debug");
        B->debug(1);

        # this is enabling
        # which is useful when using walkoptree (not the slow version)
    }

    verbose()
      ? walkoptree_slow( main_root, "save" )
      : walkoptree( main_root, "save" );

    return;
}

sub _delete_macros_vendor_undefined {
    foreach my $class (qw(POSIX IO Fcntl Socket Exporter Errno)) {
        no strict 'refs';
        no strict 'subs';
        no warnings 'uninitialized';
        my $symtab = $class . '::';
        for my $symbol ( sort keys %$symtab ) {
            next if $symbol !~ m{^[0-9A-Z_]+$} || $symbol =~ m{(?:^ISA$|^EXPORT|^DESTROY|^TIE|^VERSION|^AUTOLOAD|^BEGIN|^INIT|^__|^DELETE|^CLEAR|^STORE|^NEXTKEY|^FIRSTKEY|^FETCH|^EXISTS)};
            next if ref $symtab->{$symbol};
            local $@;
            my $code = "$class\:\:$symbol();";
            eval $code;
            if ( $@ =~ m{vendor has not defined} ) {
                delete $symtab->{$symbol};
                next;
            }
        }
    }
    return 1;
}

sub save_main_rest {
    debug("done main optree, walking symtable for extras");

    return if $settings->{'check'};

    # These have to be saved before fixup_ppaddr or xtestc/0131.t will fail.
    # Probably all saves have to happen prior to fixup?
    # ( comppadlist->ARRAY )[0]->save('curpad_name');
    # ( comppadlist->ARRAY )[1]->save('curpad_syms');

    $settings->{'XS'}->write_lst();
    my $c_file_stash = build_template_stash();

    do_remap_xs_symbols();

    debug("Writing output");
    B::C::File::write($c_file_stash);

    # Can use NyTProf with B::C
    if ( $INC{'Devel/NYTProf.pm'} ) {
        eval q/DB::finish_profile()/;
    }

    return;
}

### TODO:
##### remove stuff from boot  add use the template for EXTERN_C declaration
#####
sub build_template_stash {
    no strict 'refs';

    my $c_file_stash = {
        'verbose'                     => verbose(),
        'debug'                       => B::C::Debug::save(),
        'creator'                     => "created at " . scalar localtime() . " with B::C $VERSION for $^X",
        'init_name'                   => $settings->{'init_name'} || "perl_init",
        'gv_index'                    => $gv_index,
        'remap_xs_symbols'            => \%remap_xs_symbols,
        'compile_stats'               => compile_stats(),
        'nullop_count'                => $nullop_count,
        'all_eval_pvs'                => \@B::C::InitSection::all_eval_pvs,
        'TAINT'                       => ( ${^TAINT} ? 1 : 0 ),
        'devel_peek_needed'           => $devel_peek_needed,
        'MAX_PADNAME_LENGTH'          => $B::PADNAME::MAX_PADNAME_LENGTH + 1,                                  # Null byte at the end?
        'longest_warnings_string'     => longest_warnings_string() || 17,
        'longest_refcounted_he_value' => longest_refcounted_he_value(),
        'PL'                          => {
            'defstash'    => save_defstash(),                                                                                   # Re-uses the cache.
                                                                                                                                # we do not want the SVf_READONLY and SVf_PROTECT flags to be set to PL_curstname : newSVpvs_share("main")
            'curstname'   => svref_2object( \'main' )->save( 'curstname', { update_flags => ~SVf_READONLY & ~SVf_PROTECT } ),
            'incgv'       => svref_2object( \*::INC )->save("main::INC"),
            'hintgv'      => svref_2object( \*^H )->save("^H"),                                                                 # This shouldn't even exist at run time!!!
            'defgv'       => svref_2object( \*{'::_'} )->save("_"),
            'errgv'       => svref_2object( \*{'::@'} )->save("@"),
            'replgv'      => svref_2object( \*^R )->save("^R"),
            'debstash'    => svref_2object( \%::DB:: )->save("DB::"),
            'globalstash' => svref_2object( \%CORE::GLOBAL:: )->save("CORE::GLOBAL::"),
            'main_cv'     => main_cv()->save("PL_main_cv"),
            'endav'       => end_av()->save('END'),
            'initav'      => init_av()->save('INIT'),
            'main_root'   => main_root()->save,
            'main_start'  => main_start()->save,
            'dowarn'      => $^W                    ? 'G_WARN_ON' : 'G_WARN_OFF',
            'tainting'    => $^{TAINT}              ? 'TRUE'      : 'FALSE',
            'taint_warn'  => ( $^{TAINT} // 0 ) < 1 ? 'FALSE'     : 'TRUE',
            'compad'      => ( comppadlist->ARRAY )[1]->save('curpad_syms') || 'NULL',
            'warnhook'    => save_sig('__WARN__'),
            'diehook'     => save_sig('__DIE__'),
        },
        'IO' => {
            'STDIN'  => svref_2object( \*::STDIN )->save("STDIN"),
            'STDOUT' => svref_2object( \*::STDOUT )->save("STDOUT"),
            'STDERR' => svref_2object( \*::STDERR )->save("STDERR"),

            'stdin'  => svref_2object( \*::stdin )->save("stdin"),
            'stdout' => svref_2object( \*::stdout )->save("stdout"),
            'stderr' => svref_2object( \*::stderr )->save("stderr"),
        },
        'XS'          => $settings->{'XS'},
        'global_vars' => {
            'dollar_caret_H'       => $^H,
            'dollar_caret_X'       => cstring($^X),
            'dollar_caret_UNICODE' => ${^UNICODE},
            'dollar_zero'          => svref_2object( \*{'::0'} )->save("0"),
            'dollar_comma'         => svref_2object( \*{'::,'} )->save(","),
        },
        'Config' => {%B::C::Flags::Config},    # do a copy or op/sigdispatch.t will fail
        'Memory' => {
            'preallocated_sized' => B::C::Memory::get_malloc_size(),
        },
        'Signals' => {
            'PL_psig_ptr' => {},
            'ignore'      => [],
            'need_init'   => 0,
        }

    };
    chomp $c_file_stash->{'compile_stats'};    # Injects a new line when you call compile_stats()

    # define the PL_psig_ptr entries
    foreach my $signame ( sort keys %{ $Config{SIGNAL_NAMES} } ) {
        next unless defined $SIG{$signame};
        my $signum = $Config{SIGNAL_NAMES}->{$signame};
        next unless defined $B::C::mainSIGs{$signame};
        if ( ref $SIG{$signame} ) {
            $c_file_stash->{'Signals'}->{'PL_psig_ptr'}->{$signum} = $B::C::mainSIGs{$signame};
        }
        elsif ( $SIG{$signame} eq 'IGNORE' ) {
            push @{ $c_file_stash->{'Signals'}->{'ignore'} }, $signum;
        }
        else {
            WARN "Value for signal '$signame' not saved.";
        }

        $c_file_stash->{'Signals'}->{need_init} = 1;
    }

    # main() .c generation needs a buncha globals to be determined so the stash can access them.
    # Some of the vars are only put in the stash if they meet certain coditions.

    # PL_strtab's hash size
    # perl 528: 2048 = 1 << 11
    # perl 526: 512  = 1 << 9
    #   B::C knows the size of strtab when compiling it
    #   small programs would benefit from a smaller size
    $c_file_stash->{'PL_strtab_max'} = B::HV::get_max_hash_from_keys( sharedhe()->index() + 1, ( 1 << 8 ) - 1 ) + 1;    # 1 << 11 - 1
                                                                                                                        # display PL_strtab sze and max when verbose is enabled
    INFO( "PL_strtab: size=" . ( sharedhe()->index() + 1 ) . " ; HvMAX=" . $c_file_stash->{'PL_strtab_max'} );

    return $c_file_stash;
}

sub save_sig {
    my $sig_name = shift or die;
    my $sig      = $SIG{$sig_name};
    return undef if !defined $sig;

    my $sv = svref_2object( \$sig );
    $sv = $sv->RV if ( $sv->FLAGS & SVf_ROK ) == SVf_ROK;
    return $sv->save("\$SIG{$sig_name}");
}

sub do_remap_xs_symbols {
    my %xs_pkgs;

    my @xs_modules = @{ $settings->{'XS'}->modules() };
    for my $pkg ( sort keys %remap_xs_symbols ) {
        next unless grep { $pkg eq $_ } @xs_modules;
        $xs_pkgs{$pkg} = 1;    # maybe store the so file thre ?
    }

    return unless scalar keys %xs_pkgs;

    my $init = init_bootstraplink();    # was using init2 previously

    # unfortunately cannot use our BOOTSTRAP_XS logic there as
    #   Perl_gv_fetchpv("Encode::ascii_encoding", 0, SVt_PVCV)
    # is going to return an 0

    $init->open_block;

    $init->add( "#include <dlfcn.h>", "void *handle;" );

    for my $pkg ( sort keys %xs_pkgs ) {
        my $so_file = B::C::XS::perl_module_to_sofile($pkg);
        die qq{Cannot get .so file for module '$pkg'} unless $so_file;

        $init->sadd( "handle = dlopen(%s, %s);", cstring($so_file), 'RTLD_NOW|RTLD_NOLOAD' );
        foreach my $mg ( @{ $remap_xs_symbols{$pkg}{MG} } ) {
            verbose("init2 remap xpvmg_list[$mg->{ID}].xiv_iv to dlsym of $pkg\: $mg->{NAME}");
            $init->sadd(
                "xpvmg_list[%d].xiv_iv = PTR2IV( dlsym(handle, %s) );",
                $mg->{ID}, cstring( $mg->{NAME} )
            );
        }
    }

    $init->close_block;

    return;
}

sub found_xs_sub {
    my $sub = shift;

    $settings->{'XS'}->found_xs_sub($sub);

    return;
}

sub get_bootstrap_section {
    my $subname = shift;

    return init_COREbootstraplink() if $settings->{CORE_subs}->{$subname};

    # TODO
    return init_bootstraplink();
}

sub is_bootstrapped_cv {
    my $str = shift;

    return $1 if $str =~ m{BOOTSTRAP_XS_\Q[[\E(.+?)\Q]]\E_XS_BOOTSTRAP};
    return;
}

# 5.15.3 workaround [perl #101336], without .bs support
# XSLoader::load_file($module, $modlibname, ...)
my $dlext;

BEGIN {
    $dlext = $Config{dlext};
    eval q|
sub XSLoader::load_file {
  #package DynaLoader;
  my $module = shift or die "missing module name";
  my $modlibname = shift or die "missing module filepath";
  print STDOUT "XSLoader::load_file(\"$module\", \"$modlibname\" @_)\n"
      if ${DynaLoader::dl_debug};

  push @_, $module;
  # works with static linking too
  my $boots = "$module\::bootstrap";
  goto &$boots if defined &$boots;

  my @modparts = split(/::/,$module); # crashes threaded, issue 100
  my $modfname = $modparts[-1];
  my $modpname = join('/',@modparts);
  my $c = @modparts;
  $modlibname =~ s,[\\/][^\\/]+$,, while $c--;    # Q&D basename
  die "missing module filepath" unless $modlibname;
  my $file = "$modlibname/auto/$modpname/$modfname."| . qq(."$dlext") . q|;

  # skip the .bs "bullshit" part, needed for some old solaris ages ago

  print STDOUT "goto DynaLoader::bootstrap_inherit\n"
      if ${DynaLoader::dl_debug} and not -f $file;
  goto \&DynaLoader::bootstrap_inherit if not -f $file;
  my $modxsname = $module;
  $modxsname =~ s/\W/_/g;
  my $bootname = "boot_".$modxsname;
  @DynaLoader::dl_require_symbols = ($bootname);

  my $boot_symbol_ref;
  if ($boot_symbol_ref = DynaLoader::dl_find_symbol(0, $bootname)) {
    print STDOUT "dl_find_symbol($bootname) ok => goto boot\n"
      if ${DynaLoader::dl_debug};
    goto boot; #extension library has already been loaded, e.g. darwin
  }
  # Many dynamic extension loading problems will appear to come from
  # this section of code: XYZ failed at line 123 of DynaLoader.pm.
  # Often these errors are actually occurring in the initialisation
  # C code of the extension XS file. Perl reports the error as being
  # in this perl code simply because this was the last perl code
  # it executed.

  my $libref = DynaLoader::dl_load_file($file, 0) or do {
    die("Can't load '$file' for module $module: " . DynaLoader::dl_error());
  };
  push(@DynaLoader::dl_librefs,$libref);  # record loaded object

  my @unresolved = DynaLoader::dl_undef_symbols();
  if (@unresolved) {
    die("Undefined symbols present after loading $file: @unresolved\n");
  }

  $boot_symbol_ref = DynaLoader::dl_find_symbol($libref, $bootname) or do {
    die("Can't find '$bootname' symbol in $file\n");
  };
  print STDOUT "dl_find_symbol($libref, $bootname) ok => goto boot\n"
    if ${DynaLoader::dl_debug};
  push(@DynaLoader::dl_modules, $module); # record loaded module

 boot:
  my $xs = DynaLoader::dl_install_xsub($boots, $boot_symbol_ref, $file);
  print STDOUT "dl_install_xsub($boots, $boot_symbol_ref, $file)\n"
    if ${DynaLoader::dl_debug};
  # See comment block above
  push(@DynaLoader::dl_shared_objects, $file); # record files loaded
  return &$xs(@_);
}
|;
}

1;
