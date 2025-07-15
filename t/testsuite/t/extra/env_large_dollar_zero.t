#!/usr/bin/perl
# Test for environment corruption when setting very large $0
# This reproduces the exact scenario where large $0 values corrupt %ENV
# due to buffer overflow in the old environment duplication method

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}

use strict;
use warnings;

my $pid = $$;
if ( ( $ARGV[0] // '' ) ne 'second_instance' ) {

    # This is the first instance - set up environment and exec into second instance
    # Start with small but not empty environment (simulate systemd)
    %ENV = ();

    # Set up minimal systemd-like environment
    $ENV{PATH}          = "/usr/bin:/bin";
    $ENV{NOTIFY_SOCKET} = "/run/systemd/notify";
    $ENV{LISTEN_PID}    = $pid;
    $ENV{TEST_VAR_1}    = "test_value_1";
    $ENV{TEST_VAR_2}    = "test_value_2";
    my @cmd = ( $0, 'second_instance' );
    unshift @cmd, $^X unless $0 =~ m/\.bin$/;

    exec @cmd or die "exec failed: $!";
}

plan(8);

# This is the second instance - immediately set large $0 and test environment
# CRITICAL: Set very large $0 FIRST, before testing environment
# This triggers environment duplication and potential corruption
$0 = "kkd flwkjg lrwkjg lkjg lkghj lgkjglkgj gkljg";

is( $ARGV[0], 'second_instance', "ARGV is not corrupted" );

is( scalar %ENV, 5, "5 ENV Var sent to child process" );

# Test 1: Check if our test variables survived the large $0 change
is( $ENV{TEST_VAR_1},    "test_value_1",        "TEST_VAR_1 survived large \$0 change" );
is( $ENV{TEST_VAR_2},    "test_value_2",        "TEST_VAR_2 survived large \$0 change" );
is( $ENV{PATH},          "/usr/bin:/bin",       "PATH still accessible after large \$0 change" );
is( $ENV{NOTIFY_SOCKET}, "/run/systemd/notify", "NOTIFY_SOCKET survived large \$0 change" );
is( $ENV{LISTEN_PID},    $pid,                  "LISTEN_PID survived large \$0 change" );

# Test 4: Check if we can modify environment after large $0
$ENV{POST_LARGE_DOLLAR_ZERO} = "post_change_value";
is( $ENV{POST_LARGE_DOLLAR_ZERO}, "post_change_value", "can modify environment after large \$0 change" );
