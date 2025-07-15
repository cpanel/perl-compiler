#!/usr/bin/perl
# Test edge cases with empty or minimal environments
# This targets specific edge cases in environment duplication that might
# only manifest when starting with very few environment variables

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}

use strict;
use warnings;

plan(8);

# Save original environment for restoration
my %original_env = %ENV;

# Test 1: Test with completely empty environment
%ENV = ();
# Use a VERY large $0 to potentially trigger buffer overflow that corrupts %ENV
my $large_empty_name = "empty_env_test_" . ("G" x 30000);  # 30KB process name
$0 = $large_empty_name;

# The environment should still be accessible (even if empty)
# Test that we can still access %ENV even when it's empty
my $empty_env_accessible = 1;  # We can always access %ENV
eval { my $test = scalar keys %ENV; };
$empty_env_accessible = 0 if $@;
ok($empty_env_accessible, "empty environment remains accessible after \$0 change");

# Test 2: Test with single environment variable
%ENV = ();
$ENV{SINGLE_VAR} = "single_value";
my $large_single_name = "single_var_test_" . ("H" x 25000);  # 25KB
$0 = $large_single_name;

my $single_var_ok = defined $ENV{SINGLE_VAR} && $ENV{SINGLE_VAR} eq "single_value";
ok($single_var_ok, "single environment variable survives \$0 change");

# Test 3: Test with environment variable that has empty value
%ENV = ();
$ENV{EMPTY_VALUE_VAR} = "";
$ENV{NON_EMPTY_VAR} = "non_empty";
$0 = "empty_value_test";

my $empty_value_ok = exists $ENV{EMPTY_VALUE_VAR} && $ENV{EMPTY_VALUE_VAR} eq "" &&
                     defined $ENV{NON_EMPTY_VAR} && $ENV{NON_EMPTY_VAR} eq "non_empty";
ok($empty_value_ok, "environment variables with empty values handled correctly");

# Test 4: Test with environment variables that might confuse putenv
%ENV = ();
$ENV{VAR_WITH_EQUALS} = "value=with=equals";
$ENV{VAR_WITH_NULL} = "value\0with\0null";
my $large_special_name = "special_chars_test_" . ("I" x 20000);  # 20KB
$0 = $large_special_name;

my $special_chars_ok = defined $ENV{VAR_WITH_EQUALS} && $ENV{VAR_WITH_EQUALS} eq "value=with=equals" &&
                       defined $ENV{VAR_WITH_NULL};  # Null handling might vary
ok($special_chars_ok, "environment variables with special characters handled");

# Test 5: Test the critical minimal systemd environment
%ENV = ();
# This simulates exactly what systemd might leave
$ENV{PATH} = "/usr/bin:/bin";
$ENV{NOTIFY_SOCKET} = "/run/systemd/notify";
$ENV{LISTEN_PID} = $$;

$0 = "systemd_minimal_test";

my $systemd_minimal_ok = defined $ENV{PATH} && $ENV{PATH} eq "/usr/bin:/bin" &&
                         defined $ENV{NOTIFY_SOCKET} && $ENV{NOTIFY_SOCKET} eq "/run/systemd/notify" &&
                         defined $ENV{LISTEN_PID} && $ENV{LISTEN_PID} eq $$;
ok($systemd_minimal_ok, "minimal systemd environment survives \$0 change");

# Test 6: Test environment growth from minimal state
# Start minimal and add variables one by one
for my $i (1..10) {
    $ENV{"GROWTH_VAR_$i"} = "growth_value_$i";
    $0 = "growth_test_iteration_$i";
}

my $growth_ok = 1;
for my $i (1..10) {
    unless (defined $ENV{"GROWTH_VAR_$i"} && $ENV{"GROWTH_VAR_$i"} eq "growth_value_$i") {
        $growth_ok = 0;
        last;
    }
}
# Original minimal vars should still be there
$growth_ok = 0 unless defined $ENV{NOTIFY_SOCKET} && $ENV{NOTIFY_SOCKET} eq "/run/systemd/notify";

ok($growth_ok, "environment growth from minimal state works correctly");

# Test 7: Test the specific edge case that might trigger the bug
# This tests the scenario where environment duplication happens
# when there are very few variables, which might expose buffer issues
# or incorrect size calculations in the old method

%ENV = ();
$ENV{TEST_VAR_1} = "A";  # Single character
$ENV{TEST_VAR_2} = "B";  # Single character

# Multiple rapid $0 changes with minimal environment
for my $i (1..5) {
    $0 = "edge_case_test_$i";
    
    # Add one variable per iteration
    $ENV{"EDGE_VAR_$i"} = "edge_value_$i";
}

my $edge_case_ok = 1;
$edge_case_ok = 0 unless defined $ENV{TEST_VAR_1} && $ENV{TEST_VAR_1} eq "A";
$edge_case_ok = 0 unless defined $ENV{TEST_VAR_2} && $ENV{TEST_VAR_2} eq "B";
for my $i (1..5) {
    $edge_case_ok = 0 unless defined $ENV{"EDGE_VAR_$i"} && $ENV{"EDGE_VAR_$i"} eq "edge_value_$i";
}

ok($edge_case_ok, "edge case with minimal environment and rapid changes works");

# Test 8: Test the exact scenario that would break with my_setenv("NoNe SuCh", NULL)
# The old method might fail when trying to duplicate a very small environment
# because it relies on my_setenv with a non-existent variable

%ENV = ();
# Set up the absolute minimum that systemd might provide
$ENV{PATH} = "/bin";
$ENV{PWD} = "/";

# This $0 change triggers the problematic environment duplication
$0 = "critical_duplication_test";

# Try to add a new variable after duplication
$ENV{POST_DUPLICATION_VAR} = "post_duplication_value";

# Check if everything is still working
my $critical_ok = defined $ENV{PATH} && $ENV{PATH} eq "/bin" &&
                  defined $ENV{PWD} && $ENV{PWD} eq "/" &&
                  defined $ENV{POST_DUPLICATION_VAR} && $ENV{POST_DUPLICATION_VAR} eq "post_duplication_value";

ok($critical_ok, "critical minimal environment duplication scenario works");

# Restore original environment
%ENV = %original_env;

# This test specifically targets edge cases that might only manifest when
# the environment is very small, which could expose bugs in the old
# my_setenv("NoNe SuCh", NULL) method that might not handle minimal
# environments correctly, especially in compiled binaries.
