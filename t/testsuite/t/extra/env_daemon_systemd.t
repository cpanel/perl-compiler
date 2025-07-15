#!/usr/bin/perl
# Test for daemon fork+exec scenario that reproduces systemd notification issue
# This simulates the exact pattern used by daemons that fork+exec and change $0
# which was breaking systemd notifications in compiled binaries

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}

use strict;
use warnings;

plan(6);

# Test 1: Simulate daemon startup environment
$ENV{DAEMON_TEST}           = "systemd_daemon_test";
$ENV{SYSTEMD_NOTIFY_SOCKET} = "/run/systemd/notify";    # Simulate systemd socket
$ENV{SERVICE_NAME}          = "test-daemon";
is( $ENV{DAEMON_TEST}, "systemd_daemon_test", "daemon startup environment established" );

# Test 2: Simulate the problematic sequence that was failing
# Step 1: Change $0 (this triggers environment duplication)
# In the buggy version, this would corrupt the environment for fork+exec
$0 = "test-daemon - dormant mode";
is( $0, "test-daemon - dormant mode", "daemon process name set" );

# Test 3: Verify environment still accessible after $0 change
# This is where the bug would manifest - environment corruption
is( $ENV{SYSTEMD_NOTIFY_SOCKET}, "/run/systemd/notify", "systemd environment preserved after \$0 change" );

# Test 4: Fork and exec a "systemd notification" simulation
# This simulates what happens when a daemon forks and execs a helper process
# that needs to communicate with systemd
my $notify_pid = fork();
die "fork for systemd notification failed: $!" unless defined $notify_pid;

if ( $notify_pid == 0 ) {

    # Child: simulate systemd notification helper
    exec(
        $^X, '-e', '
        # Simulate sd_notify() checking environment
        exit 1 unless defined $ENV{SYSTEMD_NOTIFY_SOCKET};
        exit 2 unless $ENV{SYSTEMD_NOTIFY_SOCKET} eq "/run/systemd/notify";
        exit 3 unless defined $ENV{SERVICE_NAME};
        exit 4 unless $ENV{SERVICE_NAME} eq "test-daemon";

        # Simulate successful notification
        print "READY=1\nSTATUS=Ready\n";
        exit 0;
    '
    ) or exit 255;
}
else {
    waitpid( $notify_pid, 0 );
    my $notify_exit = $? >> 8;
    is( $notify_exit, 0, "systemd notification simulation successful" );
}

# Test 5: Simulate daemon state change
$0 = "test-daemon - active mode";
$ENV{DAEMON_STATE} = "active";
is( $ENV{DAEMON_STATE}, "active", "daemon state change successful" );

# Test 6: Final daemon environment integrity
my $final_integrity = 1;
$final_integrity = 0 unless defined $ENV{DAEMON_TEST}           && $ENV{DAEMON_TEST} eq "systemd_daemon_test";
$final_integrity = 0 unless defined $ENV{SYSTEMD_NOTIFY_SOCKET} && $ENV{SYSTEMD_NOTIFY_SOCKET} eq "/run/systemd/notify";
$final_integrity = 0 unless defined $ENV{SERVICE_NAME}          && $ENV{SERVICE_NAME} eq "test-daemon";
$final_integrity = 0 unless defined $ENV{DAEMON_STATE}          && $ENV{DAEMON_STATE} eq "active";
ok( $final_integrity, "final daemon environment integrity check passed" );

# Clean up
delete $ENV{DAEMON_TEST};
delete $ENV{SYSTEMD_NOTIFY_SOCKET};
delete $ENV{SERVICE_NAME};
delete $ENV{DAEMON_STATE};

# This test reproduces the exact daemon fork+exec pattern that was failing
# with systemd notifications when using the old environment duplication method
# in compiled binaries with PERL_USE_SAFE_PUTENV enabled
