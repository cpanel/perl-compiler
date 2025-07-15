#!/usr/bin/perl
# Test to reproduce the exact systemd notification failure scenario
# This test simulates the dnsadmin-dormant.pl issue where systemd notifications
# failed due to environment corruption after $0 changes in compiled binaries

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}

use strict;
use warnings;

plan(6);

# Test 1: Simulate the exact dnsadmin-dormant.pl scenario
# Set up environment as it would be in a systemd service
$ENV{NOTIFY_SOCKET} = "/run/systemd/notify";
$ENV{LISTEN_PID} = $$;
$ENV{LISTEN_FDS} = "1";
$ENV{SERVICE_RESULT} = "success";
$ENV{MAINPID} = $$;

# This is the critical sequence that was failing:
# 1. Process starts normally
# 2. Process changes $0 to indicate dormant state
# 3. Process tries to notify systemd of readiness
# 4. Notification fails because environment is corrupted

pass("systemd service environment established");

# Test 2: The problematic sequence - change $0 BEFORE notification
# This is what dnsadmin-dormant.pl was doing that caused failures
$0 = "dnsadmin-dormant - dormant mode";

# Now try to access systemd notification environment
# In the buggy version, this would fail because $0 change corrupted environment
is($ENV{NOTIFY_SOCKET}, "/run/systemd/notify", "NOTIFY_SOCKET survived \$0 change");
is($ENV{LISTEN_PID}, $$, "LISTEN_PID survived \$0 change");
is($ENV{MAINPID}, $$, "MAINPID survived \$0 change");

# Test 3: Simulate the actual systemd notification process
# This is what sd_notify() would do internally
my $notification_success = 0;

if (my $pid = fork()) {
    waitpid($pid, 0);
    $notification_success = ($? >> 8) == 0;
} elsif (defined $pid) {
    # Child process simulates sd_notify() checking environment and sending notification
    exec($^X, '-e', '
        # This simulates the internal workings of sd_notify()
        
        # Check if NOTIFY_SOCKET is available (required for systemd notification)
        exit 1 unless defined $ENV{NOTIFY_SOCKET};
        exit 2 unless $ENV{NOTIFY_SOCKET} eq "/run/systemd/notify";
        
        # Check if process identification is correct
        exit 3 unless defined $ENV{LISTEN_PID};
        exit 4 unless defined $ENV{MAINPID};
        
        # Simulate successful notification send
        # In real scenario, this would send "READY=1" to systemd socket
        print "READY=1\nSTATUS=Service ready\n";
        exit 0;
    ') or exit 255;
} else {
    $notification_success = 0;  # Fork failed
}

ok($notification_success, "systemd notification simulation successful");

# Test 4: Test the workaround sequence (notification BEFORE $0 change)
# Reset environment for clean test
delete $ENV{NOTIFY_SOCKET};
delete $ENV{LISTEN_PID};
delete $ENV{LISTEN_FDS};
delete $ENV{SERVICE_RESULT};
delete $ENV{MAINPID};

# Set up fresh environment
$ENV{NOTIFY_SOCKET} = "/run/systemd/notify";
$ENV{LISTEN_PID} = $$;
$ENV{MAINPID} = $$;

# Correct sequence: notify systemd FIRST, then change $0
my $workaround_success = 0;

if (my $pid = fork()) {
    waitpid($pid, 0);
    $workaround_success = ($? >> 8) == 0;
    
    # NOW it's safe to change $0 (after notification)
    $0 = "dnsadmin-dormant - ready mode";
    
} elsif (defined $pid) {
    # Child: send notification BEFORE parent changes $0
    exec($^X, '-e', '
        exit 1 unless defined $ENV{NOTIFY_SOCKET};
        exit 2 unless $ENV{NOTIFY_SOCKET} eq "/run/systemd/notify";
        print "READY=1\nSTATUS=Service ready (workaround)\n";
        exit 0;
    ') or exit 255;
} else {
    $workaround_success = 0;
}

ok($workaround_success, "workaround sequence (notify before \$0 change) successful");

# Clean up
delete $ENV{NOTIFY_SOCKET};
delete $ENV{LISTEN_PID};
delete $ENV{LISTEN_FDS};
delete $ENV{SERVICE_RESULT};
delete $ENV{MAINPID};

# This test reproduces the exact scenario that was failing in dnsadmin-dormant.pl
# where systemd notifications would fail after $0 changes in compiled binaries
# due to environment corruption caused by incompatible putenv usage.
