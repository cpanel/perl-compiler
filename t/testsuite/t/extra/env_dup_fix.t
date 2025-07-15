#!/usr/bin/perl
# Test for environment duplication fix that prevents systemd notification failures
# This test reproduces the issue where setting $0 in compiled binaries would
# break process identification due to incompatible environment duplication

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}

use strict;
use warnings;

# Ensure we have the minimum required environment
$ENV{PATH} ||= '/bin:/usr/bin';

plan(6);

# Test 1: Basic environment access before any $0 changes
my $initial_env_count = scalar keys %ENV;
ok( $initial_env_count > 0, "initial environment accessible" );

# Test 2: Set a test environment variable BEFORE changing $0
$ENV{TEST_ENVIRON_DUP} = "test_value_12345";
is( $ENV{TEST_ENVIRON_DUP}, "test_value_12345", "can set environment variables" );

# Test 3: Change $0 to VERY large value (this triggers environment duplication)
# This is the critical test - changing $0 triggers environment duplication
# In the buggy version, this would use my_setenv("NoNe SuCh", NULL) which
# is incompatible with PERL_USE_SAFE_PUTENV in Perl 5.42
# Use a VERY large $0 to potentially trigger buffer overflow that corrupts %ENV
my $large_process_name = "test_process_environ_dup_" . ("X" x 10000);  # 10KB process name
$0 = $large_process_name;
is( $0, $large_process_name, "large process name change successful" );

# Test 4: NOW check if environment is still accessible after large $0 change
# This is where the bug would manifest - environment access would fail
# or be corrupted after $0 change in compiled binaries
my $post_change_env_count = scalar keys %ENV;
ok( $post_change_env_count >= $initial_env_count, "environment accessible after large \$0 change" );

# Test 5: CRITICAL TEST - Verify our test variable is still accessible after large $0
# This tests that the environment duplication preserved all variables correctly
# In buggy version, this would fail because %ENV got corrupted
is( $ENV{TEST_ENVIRON_DUP}, "test_value_12345", "test environment variable preserved after large \$0" );

# Test 6: Verify we can still modify environment after $0 change
$ENV{TEST_ENVIRON_POST} = "post_change_value";
is( $ENV{TEST_ENVIRON_POST}, "post_change_value", "can modify environment after \$0 change" );

# Clean up
delete $ENV{TEST_ENVIRON_DUP};
delete $ENV{TEST_ENVIRON_POST};

# Note: This test specifically targets the bug where compiled binaries
# using the old my_setenv("NoNe SuCh", NULL) method would corrupt
# environment access when $0 was changed, breaking systemd notifications
# because sd_notify() relies on stable process identification.
