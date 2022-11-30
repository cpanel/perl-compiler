package B::C::XS;

use strict;
use warnings;

use B qw(svref_2object);

use B::C::Flags ();

use B::C::Debug qw/verbose debug/;

sub new {
    my $class = shift or die;
    my $ARGS  = shift or die;
    ref $ARGS eq 'HASH' or die;

    my $self = bless $ARGS, $class;

    $self->{'output_file'} or die;

    # expected input which should come from caller
    ref $self->{'dl_so_files'} eq 'ARRAY' or die 'Missing dl_so_files';
    ref $self->{'dl_modules'} eq 'ARRAY'  or die 'Missing dl_modules';

    $self->{'core_modules'} = { map { s/::[^:]+$//; ( $_ => 1 ) } sort keys %{ $self->{'core_subs'} } };

    $self->{'modules_found'} = {};

    return $self;
}

sub found_xs_sub {
    my ( $self, $sub ) = @_;

    # deals with XS exceptions there...

    if ( $sub =~ qr{^IO::(?:Dir|File|Handle|Pipe|Poll|Seekable|Select|Socket)::} ) {

        # Dir.pm  File.pm  Handle.pm  Pipe.pm  Poll.pm  Seekable.pm  Select.pm  Socket  Socket.pm
        $self->add_to_bootstrap('IO');
    }

    if ( $sub =~ qr{^mro::(?:_nextcan)} ) {
        $self->add_to_bootstrap('mro');
    }

    if ( $sub =~ qr{^re::(?:install)} ) {
        $self->add_to_bootstrap('re');
    }

    if ( !B::C::skip_B() ) {
        if ( $sub =~ qr{^B::} && $sub !~ qr{^B::C} ) {
            $self->add_to_bootstrap('B');
        }
    }

    return;

    # return unless defined $sub;
    # $sub =~ s{^main::}{};
    # return if $sub eq 'attributes::{bootstrap}';    # "main::attributes::{bootstrap}"
    # return unless $sub =~ qr{::};                   # the sub should not be in main
    # return if $sub =~ qr{:pad};

    # my $stashname = $sub;
    # $stashname =~ s{::[^:]+$}{};

    # # Skip any XS that wasn't present in starting %INC
    # my $inc_key = inc_key($stashname);
    # unless ( $self->{'starting_INC'}->{$inc_key} ) {
    #     return;
    # }

    # return if $stashname eq 'strict';
    # return if $stashname eq 'warnings';
    # return if $self->{'core_modules'}->{$stashname};
    # $stashname = "List::Util" if $stashname eq 'Scalar::Util';

    # # NOT XS???
    # return if $stashname eq 'base';

    # $self->{'modules_found'}->{$stashname}++;
}

sub add_to_bootstrap {
    my ( $self, $module ) = @_;

    # protection again multiple inclusion
    return if grep { $module eq $_ } @{ $self->{'dl_modules'} };

    push @{ $self->{'dl_modules'} },  $module;
    push @{ $self->{'dl_so_files'} }, perl_module_to_sofile($module);

    #warn "# Adding $module: " . $self->{'dl_modules'}->[-1] . " /  " . $self->{'dl_so_files'}->[-1] . "\n";

    return;
}

# Some modules like Encode, need an extra call to some CV after bootstrap
#   rather than patching the module itself, just call the extra boot functions
#
sub get_extra_CVs_boot_list {
    my ($self) = @_;

    return $self->{_extra_cvs_boot_list} if $self->{_extra_cvs_boot_list};

    my $modules = $self->{'dl_modules'} // [];

    # list of extra CVs to call for every XS module (so far only one...)
    my $exception_rules = {

        # use a prefix for the function to call, gives flexibility
        'Encode' => [qw{Encode::onBOOT}],
    };

    my @extra_cvs;

    foreach my $m (@$modules) {
        if ( my $cvs = $exception_rules->{$m} ) {
            push @extra_cvs, @$cvs;
        }
    }

    $self->{_extra_cvs_boot_list} = \@extra_cvs;

    return $self->{_extra_cvs_boot_list};
}

sub need_extra_xs_call {
    my ($self) = @_;

    return $self->has_xs && scalar @{ $self->get_extra_CVs_boot_list };
}

sub write_lst {
    my ($self) = @_;

    my $file = $self->{'output_file'} . '.lst';
    open( my $fh, ">", $file ) or die("Can't open $file: $!");
    print {$fh} '';

    foreach my $num ( 0 .. $#{ $self->{'dl_modules'} } ) {

        #        my $so_file = perl_module_to_sofile($xs_module);
        my $xs_module = $self->{'dl_modules'}->[$num];
        my $so_file   = $self->{'dl_so_files'}->[$num];
        print {$fh} "$xs_module\t$so_file\n";
    }
    close $fh;
}

sub inc_key {
    my $module = shift or die "missing module name";

    $module =~ s{::}{/}g;
    $module .= ".pm";

    return $module;
}

sub perl_module_to_sofile {
    my $module = shift or die "missing module name";
    die q{This is a function not a method call} if ref $module;

    my $inc_key = $module;
    $inc_key =~ s{::}{/}g;

    my $inc_path = $INC{"$inc_key.pm"};

    if ( !defined $inc_path ) {

        # guess it from
        $inc_path = qx{$^X -E 'use $module; say \$INC{"$inc_key.pm"}'};
        chomp($inc_path) if $inc_path;
        die qq{Cannot guess path for $module} unless $inc_path;
    }

    $inc_path =~ s/\Q$inc_key.pm\E$//;

    my @module_parts = split( '/', $inc_key );

    %B::C::Flags::Config or die;    # Fix for no warnings 'once'
    my $sofile = $inc_path . 'auto/' . $inc_key . '/' . $module_parts[-1] . '.' . $B::C::Flags::Config{'dlext'};
    -e $sofile or die("Could not find so file for $module at $sofile");

    return $sofile;
}

sub important_modules_first {

    # JSON::XS uses attributes during bootstrap.
    # DBI is used by DBD stuff and more
    foreach my $first (qw{attributes DBI}) {
        $a eq $first and return -1;
        $b eq $first and return 1;
    }

    return $a cmp $b;
}

sub modules {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die;

    my @modules = sort important_modules_first @{ $self->{'dl_modules'} };

    return \@modules;
}

sub has_xs {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die;

    return scalar @{ $self->{'dl_modules'} } ? 1 : 0;
}

1;
