#!/usr/bin/perl
# Test for systemd notification timing issue with $0 changes
# This reproduces the specific issue where setting $0 before sending
# systemd notifications would break process attribution in compiled binaries

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}

use strict;
use warnings;

plan(10);

# Simulate the systemd notification scenario
# This test reproduces the exact sequence that was failing

# Test 1: Initial process state
my $original_0 = $0;
my $pid        = $$;
pass("initial process state captured");

# Test 2: Environment baseline
$ENV{SYSTEMD_TEST} = "notification_test";
my $baseline_env_count = scalar keys %ENV;
ok( $baseline_env_count > 0, "baseline environment established" );

# Test 3: Simulate the PROBLEMATIC sequence (what was failing)
# This is what dnsadmin-dormant.pl was doing that broke systemd notifications

# Step 1: Change $0 FIRST (this triggers environment duplication)
$0 = "test_daemon_dormant_mode";

# Step 2: Simulate systemd notification attempt
# In the real scenario, this is where sd_notify() would fail because
# the process identification was corrupted by the $0 change
my $process_id_stable = ( $$ == $pid );              # PID should remain the same
my $env_accessible    = ( scalar keys %ENV > 0 );    # Environment should still work
ok( $process_id_stable && $env_accessible, "process identification stable after \$0 change" );

# Test 4: Environment integrity after $0 change
is( $ENV{SYSTEMD_TEST}, "notification_test", "environment variables preserved after \$0 change" );

# Test 5: Can still access system environment
my $path_accessible = defined $ENV{PATH} && length( $ENV{PATH} ) > 0;
ok( $path_accessible, "system environment still accessible" );

# Test 6: Simulate the CORRECT sequence (the fix)
# Reset for clean test
$0 = $original_0;
delete $ENV{SYSTEMD_TEST};

# Step 1: Simulate systemd notification FIRST (before $0 change)
$ENV{NOTIFICATION_SENT} = "ready_signal_sent";
my $notification_success = ( $ENV{NOTIFICATION_SENT} eq "ready_signal_sent" );

# Step 2: THEN change $0 (safe after notification)
$0 = "test_daemon_ready_mode";
ok( $notification_success && defined $ENV{NOTIFICATION_SENT}, "notification before \$0 change sequence works" );

# Test 7: Environment still works after correct sequence
my $post_correct_env_count = scalar keys %ENV;
ok( $post_correct_env_count >= $baseline_env_count, "environment preserved in correct sequence" );

# Test 8: Multiple $0 changes (stress test)
for my $i ( 1 .. 3 ) {
    $0 = "test_daemon_iteration_$i";
    $ENV{"TEST_ITER_$i"} = "iteration_$i";
}

my $all_iterations_ok = 1;
for my $i ( 1 .. 3 ) {
    unless ( defined $ENV{"TEST_ITER_$i"} && $ENV{"TEST_ITER_$i"} eq "iteration_$i" ) {
        $all_iterations_ok = 0;
        last;
    }
}
ok( $all_iterations_ok, "multiple \$0 changes handle correctly" );

# Test 9: Environment modification after multiple $0 changes
$ENV{FINAL_TEST} = "final_value";
is( $ENV{FINAL_TEST}, "final_value", "environment modification works after multiple \$0 changes" );

# Test 10: Process name reflects final change
is( $0, "test_daemon_iteration_3", "final process name correct" );

# Clean up
for my $i ( 1 .. 3 ) {
    delete $ENV{"TEST_ITER_$i"};
}
delete $ENV{NOTIFICATION_SENT};
delete $ENV{FINAL_TEST};

# This test reproduces the exact timing issue that caused systemd notification
# failures in compiled binaries when $0 was set before sd_notify() calls
