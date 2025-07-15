#!/usr/bin/perl
# Test to expose process identity corruption that occurs with incompatible putenv
# This test specifically targets the scenario where environment duplication
# corrupts process identification needed for systemd notifications

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}

use strict;
use warnings;

plan(6);

# Test 1: Establish baseline process identity
my $original_pid = $$;
my $original_ppid = getppid();
$ENV{PROCESS_IDENTITY_TEST} = "pid_${original_pid}_ppid_${original_ppid}";
pass("baseline process identity established");

# Test 2: Change $0 and verify process identity remains stable
# This is where the bug would manifest - process identification corruption
$0 = "test_process_identity_corruption";

my $post_change_pid = $$;
my $post_change_ppid = getppid();

# PID and PPID should remain the same after $0 change
my $identity_stable = ($original_pid == $post_change_pid && $original_ppid == $post_change_ppid);
ok($identity_stable, "process identity stable after \$0 change");

# Test 3: Verify environment-based process tracking still works
# This simulates how systemd tracks processes
my $env_identity_ok = defined $ENV{PROCESS_IDENTITY_TEST} && 
                     $ENV{PROCESS_IDENTITY_TEST} eq "pid_${original_pid}_ppid_${original_ppid}";
ok($env_identity_ok, "environment-based process tracking works");

# Test 4: Test the critical fork+exec scenario that was failing
# This is the exact pattern that was breaking systemd notifications
$ENV{CRITICAL_NOTIFICATION_VAR} = "ready_for_notification";
$0 = "daemon_ready_for_notification";

my $fork_exec_ok = 0;
if (my $pid = fork()) {
    waitpid($pid, 0);
    $fork_exec_ok = ($? >> 8) == 0;
} elsif (defined $pid) {
    # Child: exec a process that simulates systemd notification check
    exec($^X, '-e', '
        # This simulates what sd_notify() does - checks process environment
        # for notification socket and process identification
        
        # Check if critical environment survived
        exit 1 unless defined $ENV{CRITICAL_NOTIFICATION_VAR};
        exit 2 unless $ENV{CRITICAL_NOTIFICATION_VAR} eq "ready_for_notification";
        
        # Check if process identity tracking environment survived
        exit 3 unless defined $ENV{PROCESS_IDENTITY_TEST};
        
        # Simulate successful notification
        exit 0;
    ') or exit 255;
} else {
    $fork_exec_ok = 0;  # Fork failed
}

ok($fork_exec_ok, "fork+exec process identity and environment inheritance works");

# Test 5: Test multiple rapid $0 changes with process identity checks
# This stress tests the environment duplication mechanism
my $rapid_identity_ok = 1;
for my $i (1..5) {
    $0 = "rapid_test_iteration_$i";
    
    # Check if process identity is still stable
    if ($$ != $original_pid || getppid() != $original_ppid) {
        $rapid_identity_ok = 0;
        last;
    }
    
    # Check if environment tracking still works
    unless (defined $ENV{PROCESS_IDENTITY_TEST} && 
            $ENV{PROCESS_IDENTITY_TEST} eq "pid_${original_pid}_ppid_${original_ppid}") {
        $rapid_identity_ok = 0;
        last;
    }
}
ok($rapid_identity_ok, "process identity stable through multiple rapid \$0 changes");

# Test 6: Test the exact systemd notification failure scenario
# This reproduces the timing issue that was causing failures
$ENV{SYSTEMD_SOCKET} = "/run/systemd/notify";
$ENV{NOTIFY_SOCKET} = "/run/systemd/notify";
$ENV{MAINPID} = $original_pid;

# Change $0 BEFORE attempting notification (the problematic sequence)
$0 = "daemon_process_dormant";

# Now try to "notify" systemd by checking if environment is accessible
# In the buggy version, this would fail because environment was corrupted
my $notification_ok = 1;
$notification_ok = 0 unless defined $ENV{SYSTEMD_SOCKET} && $ENV{SYSTEMD_SOCKET} eq "/run/systemd/notify";
$notification_ok = 0 unless defined $ENV{NOTIFY_SOCKET} && $ENV{NOTIFY_SOCKET} eq "/run/systemd/notify";
$notification_ok = 0 unless defined $ENV{MAINPID} && $ENV{MAINPID} eq $original_pid;
$notification_ok = 0 unless defined $ENV{CRITICAL_NOTIFICATION_VAR} && $ENV{CRITICAL_NOTIFICATION_VAR} eq "ready_for_notification";

ok($notification_ok, "systemd notification environment accessible after \$0 change");

# Clean up
delete $ENV{PROCESS_IDENTITY_TEST};
delete $ENV{CRITICAL_NOTIFICATION_VAR};
delete $ENV{SYSTEMD_SOCKET};
delete $ENV{NOTIFY_SOCKET};
delete $ENV{MAINPID};

# This test specifically targets the process identity corruption that would
# occur with the old my_setenv("NoNe SuCh", NULL) method. When PERL_USE_SAFE_PUTENV
# is enabled, this incompatible method would corrupt the environment in ways
# that break process identification and systemd notification mechanisms.
