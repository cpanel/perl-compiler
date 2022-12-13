package B::C::File;

=head1 NAME

B::C::File - Responsible for rendering the C file from a provided stash and locally tracked sections for use with perlcc

=head1 SYNOPSIS

    # In B::C
    use B::C::File ();
    B::C::File::new(); # Singleton.
    ...
    B::C::File::write( 'file.c' ) # C File to generate.

=head1 DESCRIPTION

B<B::C::File> B::C::File is B::C's view. It uses Template Toolkit to render the C file using a passed in stash,
combined with B::C::Section objects which it initializes and tree walkers update as they go.

=cut

use B::C::Std;
use warnings;

use Exporter ();

use B::C::Debug             qw/debug WARN INFO verbose/;
use B::C::Helpers::Symtable qw(get_symtable_ref);
use B::C::Helpers           qw/gv_fetchpv_to_fetchpvn_flags/;
use B::C::Section           ();
use B::C::Section::Meta     ();
use B::C::InitSection       ();
use B::C::Section::Assign   ();
use B::C::Hooks             ();

use B qw(cstring comppadlist);

our @ISA = qw(Exporter);

# singleton
my $self;

sub singleton ($self) {
    $self or die "Singleton not initialized";
    return $self;
}

sub re_initialize {    # only for unit tests purpose
    my $outfile = $self->{'c_file_name'};
    $self = undef;
    return new($outfile);
}

# The objects in quotes do not have any special logic.
sub code_section_names {
    return qw{cowpv const typedef decl init0 free sym hek lazyregex sharedhe sharedhestructs invlistarray},
      struct_names(), op_sections();
}

# These objects will end up in an array of structs in the template and be auto-declared.
sub struct_names {
    return qw( malloc xpv xpvav xpvhv xpvcv padlist padname padnamelist magic
      xpviv xpvuv xpvnv xpvmg xpvlv xrv xpvbm xpvio xpvhv_with_aux
      sv gv gp xpvgv lexwarn refcounted_he
      xinvlist
      xsaccessor
      ),
      assign_sections();
}

sub assign_sections {
    return qw{assign_bodyless_iv};
}

# Each of these sections can generate multiple regular section
sub meta_sections {
    return qw{meta_unopaux_item};
}

# These populate the init sections and have a special header.
sub init_section_names {
    return qw{ init0 init init_regexp init_xops init1 init2 init_stash
      init_vtables init_static_assignments init_bootstraplink init_COREbootstraplink init_xsaccessor };
}

sub op_sections {
    return qw{ binop condop cop padop loop listop logop op pmop pmopaux pvop svop unop unopaux methop};
}

BEGIN {
    our @EXPORT_OK = map { ( $_, "${_}sect" ) } code_section_names();
    push @EXPORT_OK, init_section_names();
    push @EXPORT_OK, meta_sections();

}

sub new ( $class, $outfile = undef ) {

    $self and die "Singleton: should only be called once !";

    debug( 'file' => "Write to c file: '" . ( $outfile // 'undef' ) . "'" );
    $self = bless { 'c_file_name' => $outfile };

    foreach my $section_name ( code_section_names() ) {
        $self->{$section_name} = B::C::Section->new( $section_name, get_symtable_ref(), 0 );
    }

    foreach my $section_name ( assign_sections() ) {    # overwrite the previous section
        $self->{$section_name} = B::C::Section::Assign->new( $section_name, get_symtable_ref(), 0 );
    }

    foreach my $section_name ( init_section_names() ) {
        $self->{$section_name} = B::C::InitSection->CREATE( $section_name, get_symtable_ref(), 0 );
    }

    # our meta sections
    foreach my $section_name ( meta_sections() ) {
        $self->{$section_name} = B::C::Section::Meta->new( $section_name, get_symtable_ref(), 0 );
    }

    return $self;
}

sub get_sect ($section) {
    return $self->{$section};
}

# Devel::NYTProf gives bad data when AUTOLOAD is in place. Just the same, we have no evidence that run times change when you replace it.
# But in the interests of accurate data, you can replace the output of the below one liner and remove AUTOLOAD so you can get a useful
# NYTProf report back.
# perl -MB::C::File -E'foreach my $s ("", "sect") { foreach my $sect (B::C::File::code_section_names(), B::C::File::init_section_names()) {print "sub $sect$s { return \$self->{'\''$sect'\''} }\n"}; print "\n"}'

sub DESTROY { }    # Because we're doing autoload.

our $AUTOLOAD;     # Avoids warnings.

sub AUTOLOAD {
    my $sect = $AUTOLOAD;
    $sect =~ s/.*:://;

    $sect =~ s/sect$//;    # Strip sect off the call so we can just access the key.

    exists $self->{$sect} or die("Tried to call undefined subroutine '$sect'");

    # do something there with the meta sections
    if ( ref $self->{$sect} eq 'B::C::Section::Meta' ) {
        return $self->{$sect}->get_section(@_);
    }

    return $self->{$sect};
}

my $cfh;
my %static_ext;

sub replace_xs_bootstrap_to_init {

    # play with global sections to alter them before rendering

    my @structs = struct_names();
    foreach my $section ( sort @structs ) {
        next if $section eq 'gp';    # or $section eq 'gv';    # gv are replaced when loading bootstrap (we do not want to replace them)
                                     #next unless $section eq 'magic';

        my $field = $section eq 'magic' ? q{mg_obj} : q{sv_u.svu_rv};    # move to section ?

        my $bs_rows = $self->{$section}->get_bootstrapsub_rows();        # [ 42 => q{json::xs::encode},  ]
        foreach my $subname ( sort keys %$bs_rows ) {
            foreach my $ix ( @{ $bs_rows->{$subname} } ) {

                my $init = B::C::get_bootstrap_section($subname);

                # replace the cv to the one freshly loaded by XS
                $init->sadd(
                    '%s_list[%d].%s = (SV*) GvCV( %s );',
                    $section, $ix, $field,

                    # uses gv_fetchpvn_flags instead of gv_fetchpv to save one strlen
                    gv_fetchpv_to_fetchpvn_flags( $subname, 0, 'SVt_PVCV' ),
                );

            }
        }
    }

    #foreach my $section ( sort ) {
    #$self->{init}->fixup_assignments;
    #}

    return;
}

sub hooks ($self) {
    return $self->{hooks} //= B::C::Hooks->new();
}

sub write ( $c_file_stash, $template_name_short = undef ) {
    die unless $c_file_stash;
    $template_name_short ||= 'base.c.tt2';

    $self->hooks->pre_write();    # can alter sections before setting c_file_stash

    # TODO: refactor move section group logic outside of the 'write' which is the main purpose of File
    # Controls the rendering order of the sections.
    $c_file_stash->{init_section_list} = [ init_section_names() ];

    $c_file_stash->{section_list} = [
        struct_names(),
        op_sections(),
    ];

    # perl -e 'use Cpanel::Internals; BEGIN { B::C::setup_all_ops() }'
    # perl -e 'BEGIN { *B::C::SETUP_ALL_OPS = sub { 1 } }'
    $c_file_stash->{SETUP_ALL_OPS} = 0;
    if ( my $f = B::C->can('SETUP_ALL_OPS') ) {    # define in Cpanel/Internals.pm
        $c_file_stash->{SETUP_ALL_OPS} = $f->() // 0;
    }

    # Prep COWPV strings
    B::C::Save::cowpv_setup();

    #$c_file_stash->{SETUP_ALL_OPS} = 1; # testing...

    $c_file_stash->{op_section_list} = [ op_sections() ];

    $c_file_stash->{meta_section_list} = [ meta_sections() ];

    $self->{'sharedhestructs'}->sort();    # sort them for human readability

    foreach my $section ( code_section_names(), init_section_names() ) {
        $c_file_stash->{'section'}->{$section} = $self->{$section};
    }

    # add the Meta sections to the section_list */
    my @meta_sections;
    foreach my $section_name ( meta_sections() ) {
        my @list = $self->{$section_name}->get_all_sections();
        next unless scalar @list;
        push @meta_sections, @list;
    }
    foreach my $section (@meta_sections) {
        push @{ $c_file_stash->{section_list} }, $section->name;
        $c_file_stash->{'section'}->{ $section->name } = $section;
    }

    replace_xs_bootstrap_to_init();

    $self->{'verbose'} = $c_file_stash->{'verbose'};    # So verbose() will work. TODO: Remove me when all verbose() are gone.

    my $template_dir = $B::C::settings->{'template_dir'};

    my $template_file = "$template_dir/$template_name_short";
    -e $template_file or die("Can't find or read $template_file for generating B::C C code.");

    # problems. Ideally this code should be removed in favor of a better solution.
    # op/magic-27839.t sets SIG{WARN} in a begin block and then never releases it.
    eval q{local $SIG{__WARN__} = 'IGNORE'; require Config; require Exporter::Heavy; require Template};
    $INC{'Template.pm'} or die("Can't load Template Toolkit at run time to render the C file.");
    {
        no warnings;
        *Template::DESTROY = sub { };    # disabled
    }

    # some useful options (see below for full list)
    my $config = {
        INCLUDE_PATH => $template_dir,
        INTERPOLATE  => 0,               # expand "$var" in plain text
        POST_CHOMP   => 0,               # Don't cleanup whitespace
        EVAL_PERL    => 1,               # evaluate Perl code blocks
    };

    if ( verbose() ) {
        INFO $c_file_stash->{'compile_stats'};
        INFO "NULLOP count: $c_file_stash->{nullop_count}";
    }

    # Used to be buried in output_main_rest();
    if ( verbose() ) {
        foreach my $stashname ( sort keys %static_ext ) {
            verbose("bootstrapping static $stashname added to xs_init");
        }
    }

    # create Template object
    my $template = Template->new($config);

    open( my $fh, '>:utf8', $self->{'c_file_name'} ) or die;

    $self->hooks->pre_process( stash => $c_file_stash );

    # process input template, substituting variables
    $template->process( $template_name_short, $c_file_stash, $fh ) or die $template->error();

    {    # clear Template::Provider, Template::Context, ...
        local $@;

        my $context = $template->context;
        if ( ref $context && ref $context->{LOAD_TEMPLATES} ) {
            foreach my $provider ( @{ $context->{LOAD_TEMPLATES} } ) {
                next unless ref $provider;
                $provider->DESTROY;
            }
        }
        $context->DESTROY if ref $context;
        $template->DESTROY;
    }
    close $fh;

    $self->hooks->post_process( c_file_name => $self->{'c_file_name'} );

    return;
}

1;
