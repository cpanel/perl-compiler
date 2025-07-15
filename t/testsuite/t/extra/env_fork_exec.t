#!/usr/bin/perl
# Test for environment duplication fix in fork+exec scenarios
# This reproduces the systemd notification issue where fork+exec with $0 change
# would break environment handling in compiled binaries

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}

use strict;
use warnings;

plan(6);

# Test 1: Setup environment for fork+exec test
$ENV{FORK_EXEC_TEST} = "parent_environment";
$ENV{CRITICAL_VAR}   = "must_survive_exec";
$ENV{PATH}           = $ENV{PATH} || "/bin:/usr/bin";
is( $ENV{FORK_EXEC_TEST}, "parent_environment", "parent environment setup for fork+exec" );

# Test 2: Change $0 before fork+exec (this triggers environment duplication)
# This is the critical step that would break with old my_setenv("NoNe SuCh", NULL)
# Use a VERY large $0 to potentially trigger buffer overflow that corrupts %ENV
my $large_daemon_name = "test_daemon_before_exec_" . ("A" x 15000);  # 15KB process name
$0 = $large_daemon_name;
is( $0, $large_daemon_name, "large process name changed before fork+exec" );

# Test 3: Verify environment still accessible after $0 change
is( $ENV{FORK_EXEC_TEST}, "parent_environment", "environment accessible after \$0 change" );

# Test 4: Fork and exec a simple command that checks environment
my $pid = fork();

die "fork failed: $!" unless defined $pid;

if ( $pid == 0 ) {

    # Child process - exec a command that will test environment
    # Use perl itself to check if environment variables survived
    exec(
        $^X, '-e', '
        exit 1 unless defined $ENV{FORK_EXEC_TEST};
        exit 2 unless $ENV{FORK_EXEC_TEST} eq "parent_environment";
        exit 3 unless defined $ENV{CRITICAL_VAR};
        exit 4 unless $ENV{CRITICAL_VAR} eq "must_survive_exec";
        exit 0;
    '
    ) or exit 255;
}
else {
    # Parent process
    waitpid( $pid, 0 );
    my $child_exit = $? >> 8;
    is( $child_exit, 0, "fork+exec environment inheritance successful" );
}

# Test 5: Multiple $0 changes with environment modification
my $multi_success = 1;
for my $i ( 1 .. 3 ) {
    my $large_cycle_name = "test_daemon_cycle_$i" . ("B" x (5000 + $i * 1000));  # 6KB, 7KB, 8KB
    $0 = $large_cycle_name;
    $ENV{"CYCLE_VAR_$i"} = "cycle_value_$i";
    unless ( defined $ENV{"CYCLE_VAR_$i"} && $ENV{"CYCLE_VAR_$i"} eq "cycle_value_$i" ) {
        $multi_success = 0;
        last;
    }
}
ok( $multi_success, "multiple large \$0 changes with environment modification successful" );

# Test 6: Final environment integrity check
is( $ENV{FORK_EXEC_TEST}, "parent_environment", "parent environment preserved" );

# Clean up
delete $ENV{FORK_EXEC_TEST};
delete $ENV{CRITICAL_VAR};
for my $i ( 1 .. 3 ) {
    delete $ENV{"CYCLE_VAR_$i"};
}
