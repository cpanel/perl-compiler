#!/usr/bin/perl
# Test to reproduce environment corruption with minimal starting environment
# This simulates the systemd scenario where most environment variables are cleared
# and Perl starts with a very small %ENV, which might expose edge cases in
# environment duplication logic

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}

use strict;
use warnings;

plan(11);

# Test 1: Simulate systemd's minimal environment
# First, save critical variables we need to keep
my $saved_path     = $ENV{PATH};
my $saved_perl5lib = $ENV{PERL5LIB} || "";

# Clear most environment variables to simulate systemd behavior
my @original_keys = keys %ENV;
for my $key (@original_keys) {

    # Keep only absolutely essential variables
    next if $key eq 'PATH';
    next if $key eq 'PERL5LIB';
    next if $key eq 'HOME';
    next if $key eq 'USER';
    next if $key eq 'LOGNAME';
    delete $ENV{$key};
}

# Set up minimal systemd-like environment
$ENV{PATH}          = $saved_path;
$ENV{PERL5LIB}      = $saved_perl5lib if $saved_perl5lib;
$ENV{NOTIFY_SOCKET} = "/run/systemd/notify";
$ENV{LISTEN_PID}    = $$;
$ENV{MAINPID}       = $$;

my $minimal_env_count = scalar keys %ENV;
pass("minimal systemd-like environment established ($minimal_env_count variables)");

# Test 2: Trigger environment duplication with minimal environment
# This is where the bug might manifest - when there are very few variables
# Use a VERY large $0 to potentially trigger buffer overflow that corrupts %ENV
my $large_minimal_name = "minimal_env_test_process_" . ( "C" x 20000 );    # 20KB process name
$0 = $large_minimal_name;

# Check if the minimal environment survived
is( $ENV{NOTIFY_SOCKET}, "/run/systemd/notify", "NOTIFY_SOCKET survives \$0 change" );
is( $ENV{LISTEN_PID},    $$,                    "LISTEN_PID survives \$0 change" );
is( $ENV{MAINPID},       $$,                    "MAINPID survives \$0 change" );

# Test 3: Test adding variables to minimal environment after duplication
# This might expose issues with environment expansion after duplication
$ENV{NEW_VAR_1} = "new_value_1";
$ENV{NEW_VAR_2} = "new_value_2";

my $large_expansion_name = "minimal_env_expansion_test_" . ( "D" x 18000 );    # 18KB
$0 = $large_expansion_name;

is( $ENV{NEW_VAR_1}, "new_value_1", "NEW_VAR_1 survives large \$0 change" );
is( $ENV{NEW_VAR_2}, "new_value_2", "NEW_VAR_2 survives large \$0 change" );

# Original minimal vars should still be there
is( $ENV{NOTIFY_SOCKET}, "/run/systemd/notify", "NOTIFY_SOCKET still accessible after expansion" );

# Test 4: Test the critical fork+exec scenario with minimal environment
# This reproduces the exact systemd notification failure scenario
my $fork_exec_minimal_ok = 0;

if ( my $pid = fork() ) {
    waitpid( $pid, 0 );
    $fork_exec_minimal_ok = ( $? >> 8 ) == 0;
}
elsif ( defined $pid ) {

    # Child: exec with minimal environment - this is where corruption would show
    exec(
        $^X, '-e', '
        # Check if minimal environment was inherited correctly
        exit 1 unless defined $ENV{NOTIFY_SOCKET};
        exit 2 unless $ENV{NOTIFY_SOCKET} eq "/run/systemd/notify";
        exit 3 unless defined $ENV{LISTEN_PID};
        exit 4 unless defined $ENV{MAINPID};
        
        # Check if added variables survived
        exit 5 unless defined $ENV{NEW_VAR_1};
        exit 6 unless $ENV{NEW_VAR_1} eq "new_value_1";
        
        exit 0;
    '
    ) or exit 255;
}
else {
    $fork_exec_minimal_ok = 0;
}

ok( $fork_exec_minimal_ok, "fork+exec works correctly with minimal environment" );

# Test 5: Test rapid environment changes with minimal base
# This stress tests the duplication mechanism when starting from minimal state
my $rapid_minimal_ok = 1;

for my $i ( 1 .. 5 ) {
    my $large_rapid_name = "rapid_minimal_test_$i" . ( "E" x ( 10000 + $i * 2000 ) );    # 12KB-20KB
    $0 = $large_rapid_name;
    $ENV{"RAPID_VAR_$i"} = "rapid_value_$i";

    # Check if all variables are still accessible
    for my $j ( 1 .. $i ) {
        unless ( defined $ENV{"RAPID_VAR_$j"} && $ENV{"RAPID_VAR_$j"} eq "rapid_value_$j" ) {
            $rapid_minimal_ok = 0;
            last;
        }
    }
    last unless $rapid_minimal_ok;

    # Check if original minimal environment is still intact
    unless ( defined $ENV{NOTIFY_SOCKET} && $ENV{NOTIFY_SOCKET} eq "/run/systemd/notify" ) {
        $rapid_minimal_ok = 0;
        last;
    }
}

ok( $rapid_minimal_ok, "rapid environment changes work with minimal base environment" );

# Test 6: Test the edge case of empty environment duplication
# Create an even more minimal environment and test duplication
my %backup_env = %ENV;
%ENV = ();    # Completely empty environment

# Add back just the absolute minimum
$ENV{PATH}         = $saved_path;
$ENV{CRITICAL_VAR} = "critical_value";

# This is the critical test - environment duplication with nearly empty environment
# Use a VERY large $0 to potentially trigger buffer overflow that corrupts %ENV
my $large_empty_name = "empty_env_duplication_test_" . ( "F" x 25000 );    # 25KB process name
$0 = $large_empty_name;

# Check if the minimal variables survived
is( $ENV{PATH},         $saved_path,      "PATH survives nearly empty environment duplication" );
is( $ENV{CRITICAL_VAR}, "critical_value", "CRITICAL_VAR survives nearly empty environment duplication" );

# Restore environment for cleanup
%ENV = %backup_env;

# Clean up
delete $ENV{NOTIFY_SOCKET};
delete $ENV{LISTEN_PID};
delete $ENV{MAINPID};
delete $ENV{NEW_VAR_1};
delete $ENV{NEW_VAR_2};
for my $i ( 1 .. 5 ) {
    delete $ENV{"RAPID_VAR_$i"};
}

# This test specifically targets the scenario where systemd clears most environment
# variables, leaving Perl with a minimal %ENV. The old my_setenv("NoNe SuCh", NULL)
# method might have edge cases when dealing with very small environments that
# could cause corruption or failures in the duplication process.
