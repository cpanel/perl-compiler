#!/usr/bin/perl
# Test to expose memory corruption in environment handling
# This test specifically targets memory management issues that occur
# when my_setenv("NoNe SuCh", NULL) is used with PERL_USE_SAFE_PUTENV

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}

use strict;
use warnings;

plan(5);

# Test 1: Create a pattern that would expose memory corruption
# Set up environment variables in a specific pattern that might reveal corruption
my @test_pattern = ();
for my $i (0..9) {
    my $var = sprintf("PATTERN_VAR_%02d", $i);
    my $val = "pattern_value_$i" . ("_GUARD_" x 10);  # Guard pattern to detect corruption
    $ENV{$var} = $val;
    push @test_pattern, [$var, $val];
}
pass("memory corruption test pattern established");

# Test 2: Trigger environment duplication and check for corruption
$0 = "memory_corruption_test_process";

# Check if the pattern is still intact (no memory corruption)
my $pattern_intact = 1;
for my $entry (@test_pattern) {
    my ($var, $expected_val) = @$entry;
    unless (defined $ENV{$var} && $ENV{$var} eq $expected_val) {
        $pattern_intact = 0;
        last;
    }
}
ok($pattern_intact, "environment pattern intact after \$0 change (no memory corruption)");

# Test 3: Test with overlapping environment variable names
# This might expose issues with environment variable management
$ENV{OVERLAP_TEST_A} = "value_a";
$ENV{OVERLAP_TEST_AA} = "value_aa";  # Similar name
$ENV{OVERLAP_TEST_AAA} = "value_aaa";  # Even more similar

$0 = "overlap_test_process";

my $overlap_ok = 1;
$overlap_ok = 0 unless defined $ENV{OVERLAP_TEST_A} && $ENV{OVERLAP_TEST_A} eq "value_a";
$overlap_ok = 0 unless defined $ENV{OVERLAP_TEST_AA} && $ENV{OVERLAP_TEST_AA} eq "value_aa";
$overlap_ok = 0 unless defined $ENV{OVERLAP_TEST_AAA} && $ENV{OVERLAP_TEST_AAA} eq "value_aaa";

ok($overlap_ok, "overlapping environment variable names handled correctly");

# Test 4: Test environment variable boundary conditions
# This tests edge cases that might expose memory management issues
$ENV{EMPTY_VAR} = "";
$ENV{SINGLE_CHAR} = "X";
$ENV{VERY_LONG_NAME_THAT_MIGHT_CAUSE_BUFFER_ISSUES_IN_PUTENV_IMPLEMENTATION} = "long_name_value";

$0 = "boundary_test_process";

my $boundary_ok = 1;
$boundary_ok = 0 unless exists $ENV{EMPTY_VAR} && $ENV{EMPTY_VAR} eq "";
$boundary_ok = 0 unless defined $ENV{SINGLE_CHAR} && $ENV{SINGLE_CHAR} eq "X";
$boundary_ok = 0 unless defined $ENV{VERY_LONG_NAME_THAT_MIGHT_CAUSE_BUFFER_ISSUES_IN_PUTENV_IMPLEMENTATION} && 
                       $ENV{VERY_LONG_NAME_THAT_MIGHT_CAUSE_BUFFER_ISSUES_IN_PUTENV_IMPLEMENTATION} eq "long_name_value";

ok($boundary_ok, "environment variable boundary conditions handled correctly");

# Test 5: Test the specific scenario that would fail with my_setenv("NoNe SuCh", NULL)
# Create an environment state that would be corrupted by the old method
$ENV{CRITICAL_SYSTEM_VAR} = "critical_value";
$ENV{BACKUP_SYSTEM_VAR} = "backup_value";

# Multiple rapid $0 changes to stress the environment duplication
for my $i (1..3) {
    $0 = "stress_test_iteration_$i";
    
    # Each change triggers environment duplication
    # With the old method, this would eventually corrupt the environment
    $ENV{"STRESS_VAR_$i"} = "stress_value_$i";
}

# Final check - if environment duplication is working correctly,
# all variables should still be accessible
my $final_ok = 1;
$final_ok = 0 unless defined $ENV{CRITICAL_SYSTEM_VAR} && $ENV{CRITICAL_SYSTEM_VAR} eq "critical_value";
$final_ok = 0 unless defined $ENV{BACKUP_SYSTEM_VAR} && $ENV{BACKUP_SYSTEM_VAR} eq "backup_value";

for my $i (1..3) {
    $final_ok = 0 unless defined $ENV{"STRESS_VAR_$i"} && $ENV{"STRESS_VAR_$i"} eq "stress_value_$i";
}

# Check that our original pattern is still intact
for my $entry (@test_pattern) {
    my ($var, $expected_val) = @$entry;
    unless (defined $ENV{$var} && $ENV{$var} eq $expected_val) {
        $final_ok = 0;
        last;
    }
}

ok($final_ok, "environment remains uncorrupted after stress testing");

# Clean up
for my $entry (@test_pattern) {
    delete $ENV{$entry->[0]};
}
delete $ENV{OVERLAP_TEST_A};
delete $ENV{OVERLAP_TEST_AA};
delete $ENV{OVERLAP_TEST_AAA};
delete $ENV{EMPTY_VAR};
delete $ENV{SINGLE_CHAR};
delete $ENV{VERY_LONG_NAME_THAT_MIGHT_CAUSE_BUFFER_ISSUES_IN_PUTENV_IMPLEMENTATION};
delete $ENV{CRITICAL_SYSTEM_VAR};
delete $ENV{BACKUP_SYSTEM_VAR};
for my $i (1..3) {
    delete $ENV{"STRESS_VAR_$i"};
}

# This test is designed to expose memory corruption that would occur
# with the old my_setenv("NoNe SuCh", NULL) method when used with
# PERL_USE_SAFE_PUTENV. The corruption might not be immediately visible
# but would manifest as environment variable corruption or access failures.
