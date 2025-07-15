#!/usr/bin/perl
# Test for environment duplication fix in fork scenarios
# This reproduces the systemd notification issue where forking + $0 change
# would break process identification in compiled binaries

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}
use strict;
use warnings;

plan(4);

# Test 1: Basic environment setup
$ENV{TEST_FORK_ENVIRON} = "parent_value";
is( $ENV{TEST_FORK_ENVIRON}, "parent_value", "parent environment setup" );

# Test 2: Fork and test environment duplication behavior
my $pid = fork();
die "fork failed: $!" unless defined $pid;

if ( $pid == 0 ) {

    # Child process - test critical environment duplication after $0 change

    # Critical test - change $0 in child (triggers dup_environ)
    # This is where the bug would manifest in compiled binaries
    # Use a VERY large $0 to potentially trigger buffer overflow that corrupts %ENV
    my $large_child_name = "test_child_process_fork_" . ("Y" x 8000);  # 8KB process name
    $0 = $large_child_name;

    # Environment should still be accessible after $0 change
    # In buggy versions, environment would be corrupted here
    exit 1 unless defined $ENV{TEST_FORK_ENVIRON} && $ENV{TEST_FORK_ENVIRON} eq "parent_value";

    # Should be able to modify environment after $0 change
    $ENV{CHILD_TEST} = "child_modified";
    exit 2 unless $ENV{CHILD_TEST} eq "child_modified";

    exit 0;

}
else {
    # Parent process
    waitpid( $pid, 0 );
    my $child_exit = $? >> 8;
    is( $child_exit, 0, "child environment preserved after \$0 change" );

    # Test 3: Verify parent environment unchanged
    is( $ENV{TEST_FORK_ENVIRON}, "parent_value", "parent environment unchanged after fork" );
}

# Test 4: Multiple $0 changes work correctly
my $large_multi_name = "test_multiple_changes_" . ("Z" x 12000);  # 12KB process name
$0 = $large_multi_name;
$ENV{MULTI_TEST} = "multi_value";
is( $ENV{MULTI_TEST}, "multi_value", "environment works after large \$0 change" );

# Clean up
delete $ENV{TEST_FORK_ENVIRON};
delete $ENV{MULTI_TEST};

# This test specifically targets the scenario where:
# 1. A process forks (like a daemon)
# 2. The child changes $0 (common for daemon processes)
# 3. The environment duplication triggered by $0 change uses incompatible method
# 4. This breaks process identification needed for systemd notifications
