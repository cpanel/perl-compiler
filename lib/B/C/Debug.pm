package B::C::Debug;

use strict;

use Exporter ();
our @ISA = qw(Exporter);

our @EXPORT_OK = qw/debug verbose WARN INFO FATAL/;

my %debug_map = (
    'A'     => 'av',
    'c'     => 'cops',
    'C'     => 'cv',
    'f'     => 'file',
    'G'     => 'gv',
    'g'     => 'signals',
    'H'     => 'hv',
    'M'     => 'mg',
    'O'     => 'op',
    'p'     => 'pkg',
    'P'     => 'pv',
    'R'     => 'rx',
    's'     => 'sub',
    'S'     => 'sv',
    'u'     => 'unused',
    'd'     => 'debug',       # special case for debug without any level
    'v'     => 'verbose',     # special case to consider verbose as a debug level
    'W'     => 'walk',
    'bench' => 'benchmark',
    'stack' => 'stack',
    'h'     => 'hooks',
    'hook'  => 'hooks',
);

my %reverse_map = reverse %debug_map;

# list all possible level of debugging
my %debug;

sub init {
    %debug = map { $_ => 0 } sort values %debug_map, sort keys %debug_map;
    %debug = (
        %debug,
        flags   => 0,
        runtime => 0,
    );

    binmode( STDERR, ":utf8" );    # Binmode of STDOUT and STDERR are not preserved for the perl compiler

    return;
}
init();                            # initialize

my %saved;

sub save {
    my %copy = %debug;
    return \%copy;
}

sub restore {
    my $cfg = shift;
    die unless ref $cfg;
    %debug = %$cfg;
    return;
}

# you can then enable them
# $debug{sv} = 1;

sub enable_debug_level {
    my $l = shift or die;

    if ( defined $debug_map{$l} ) {
        INFO("Enabling debug level: '$debug_map{$l}'");
        _enable_debug_level( $debug_map{$l} );
        _enable_debug_level($l);
        return 1;
    }
    if ( defined $reverse_map{$l} ) {
        INFO("Enabling debug level: '$l'");
        _enable_debug_level($l);
        _enable_debug_level( $reverse_map{$l} );
        return 1;
    }

    # allow custom debug levels
    _enable_debug_level($l);

    # tricky, but do not enable aliases if the level we are using use an unknown character
    #   allow to use custom debug levels without enabling all others
    my @letters = split( //, $l );
    return 1 if grep { !exists $debug_map{$_} } @letters;

    return;
}

sub _enable_debug_level {
    my $level = shift or die;
    $debug{$level}++;
    return;
}

sub enable_all {
    enable_verbose() unless verbose();
    foreach my $level ( sort keys %debug ) {
        next if $debug{$level};
        next if $level =~ qr{^bench};
        enable_debug_level($level);
    }
    return;
}

sub enable_verbose {
    enable_debug_level('verbose');
}

sub enable_global_debug {
    enable_debug_level('debug');
}

sub verbose {
    return $debug{'v'} unless $debug{'v'};
    return $debug{'v'} unless scalar @_;
    display_message( '[verbose]', @_ );
    return $debug{'v'};
}

# can be improved
sub WARN  { return verbose() && display_message( "[WARNING]", @_ ) }
sub INFO  { return verbose() && display_message( "[INFO]",    @_ ) }
sub FATAL { die display_message( "[FATAL]", @_ ) }

my $logfh;

sub display_message {
    my (@msg) = @_;
    return unless scalar @msg;
    my $txt = join( " ", map { defined $_ ? $_ : 'undef' } @msg );

    # just safety to avoid double \n and trailing spaces
    $txt =~ s{\s+$}{}s;
    $txt .= "\n";

    print STDERR $txt;

    if ( $ENV{BC_DEVELOPING} ) {
        $logfh or open( $logfh, '>', 'fullog.txt' );
        print {$logfh} $txt;
    }

    return;
}

=pod
=item debug( $level, @msg )
 always return the current status for the level
 when call with one single arg print the string
 more than one, use sprintf
=cut

sub debug {
    my ( $level, @msg ) = @_;

    my @levels = ref $level eq 'ARRAY' ? @$level : $level;

    if ( !scalar @levels || grep { !defined $debug{$_} } @levels ) {

        # this is a call to debug without a level, display it when -d is enabled
        unshift @msg, $level;
        @levels = 'debug';    # regular debug
    }

    my $debug_on = grep { $debug{$_} } @levels;

    if ( $debug_on && scalar @msg ) {
        @msg = map { defined $_ ? $_ : 'undef' } @msg;
        my $header = '[level=' . join( ',', sort @levels ) . '] ';
        my $cnt    = @msg;
        my $warn;
        if ( $cnt == 1 ) {
            $warn = $msg[0];
        }
        else {
            my $str = shift @msg;
            eval {
                if ( $str =~ qr{%} ) {    # use sprintf style when % is used
                    $warn = sprintf( $str, @msg );
                }
                else {                    # use a regular join when % is not used
                    $warn = join( ' ', map { $_ // '' } $str, @msg );
                }

                1;
            } or do {
                my $error = $@;

                # track the error source when possible
                eval q/require Carp; 1/ or die $error;
                Carp::croak( "Error: $error", $header, "STR:'$str' ; ", join( ', ', @msg ) );
            };

        }
        $warn = '' unless defined $warn;
        display_message("$header$warn");
    }

    return $debug_on;
}

# maint entry points
sub setup_debug {
    my ( $levels_str, $verbose, $debug ) = @_;

    enable_verbose()      if $verbose || $debug;
    enable_global_debug() if $debug;
    return unless defined $levels_str && length $levels_str;

    my @levels = split( /\./, $levels_str );
    my $use_a_valid_level;
    foreach my $level (@levels) {
        if ( enable_debug_level($level) ) {
            WARN("Enable debug mode: $level");
            $use_a_valid_level = 1;
            next;
        }
        foreach my $level ( split( //, $level ) ) {
            next if enable_debug_level($level);
            if ( $level eq "o" ) {
                enabe_verbose();
                B->debug(1);
            }
            elsif ( $level eq "F" ) {
                enable_debug_level('flags');
                $B::C::all_bc_deps{'B::Flags'}++;
            }
            elsif ( $level eq "r" ) {
                enable_debug_level('runtime');
                $SIG{__WARN__} = sub {
                    WARN(@_);
                    my $s = join( " ", @_ );
                    chomp $s;
                    B::C::File::init()->add( "/* " . $s . " */" ) if init();
                };
            }
            else {
                WARN("ignoring unknown debug option: $level");
            }
        }
    }

    return $use_a_valid_level;
}

1;
