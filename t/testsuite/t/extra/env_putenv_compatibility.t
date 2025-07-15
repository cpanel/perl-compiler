#!/usr/bin/perl
# Test to expose putenv compatibility issues with PERL_USE_SAFE_PUTENV
# This test specifically targets the bug where my_setenv("NoNe SuCh", NULL)
# is incompatible with PERL_USE_SAFE_PUTENV in Perl 5.42

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}

use strict;
use warnings;

plan(8);

# Test 1: Set up a complex environment that would stress putenv
my @env_vars = ();
for my $i (1..50) {
    my $var = "STRESS_ENV_VAR_$i";
    my $val = "value_$i" . ("x" x 100);  # Long values
    $ENV{$var} = $val;
    push @env_vars, $var;
}
pass("complex environment setup complete");

# Test 2: Trigger multiple $0 changes rapidly to stress environment duplication
my $rapid_changes_ok = 1;
for my $i (1..10) {
    $0 = "stress_test_process_iteration_$i";
    
    # Check if environment is still intact after each change
    for my $j (1..10) {  # Check first 10 vars
        my $var = "STRESS_ENV_VAR_$j";
        my $expected = "value_$j" . ("x" x 100);
        unless (defined $ENV{$var} && $ENV{$var} eq $expected) {
            $rapid_changes_ok = 0;
            last;
        }
    }
    last unless $rapid_changes_ok;
}
ok($rapid_changes_ok, "environment survives rapid \$0 changes");

# Test 3: Test with environment variables that have special characters
# These might expose putenv issues
$ENV{'SPECIAL_VAR_=_EQUALS'} = "value_with_equals=sign";
$ENV{'SPECIAL_VAR_NULL'} = "value\0with\0nulls";
$ENV{'SPECIAL_VAR_NEWLINE'} = "value\nwith\nnewlines";

$0 = "test_special_chars_process";

# Check if special vars survived
my $special_ok = 1;
$special_ok = 0 unless defined $ENV{'SPECIAL_VAR_=_EQUALS'} && $ENV{'SPECIAL_VAR_=_EQUALS'} eq "value_with_equals=sign";
# Note: NULL and newline chars might be handled differently, so we're more lenient
$special_ok = 0 unless defined $ENV{'SPECIAL_VAR_NULL'};
$special_ok = 0 unless defined $ENV{'SPECIAL_VAR_NEWLINE'};

ok($special_ok, "special character environment variables survive \$0 change");

# Test 4: Test environment variable deletion and recreation
# This might expose issues with putenv memory management
for my $i (1..10) {
    $ENV{"TEMP_VAR_$i"} = "temp_value_$i";
}

$0 = "test_deletion_process";

for my $i (1..10) {
    delete $ENV{"TEMP_VAR_$i"};
}

# Recreate them
for my $i (1..10) {
    $ENV{"TEMP_VAR_$i"} = "new_temp_value_$i";
}

my $deletion_ok = 1;
for my $i (1..10) {
    unless (defined $ENV{"TEMP_VAR_$i"} && $ENV{"TEMP_VAR_$i"} eq "new_temp_value_$i") {
        $deletion_ok = 0;
        last;
    }
}
ok($deletion_ok, "environment variable deletion and recreation works");

# Test 5: Test with very large environment
# This might expose memory management issues in putenv
my $large_value = "X" x 10000;  # 10KB value
$ENV{VERY_LARGE_VAR} = $large_value;

$0 = "test_large_env_process";

is($ENV{VERY_LARGE_VAR}, $large_value, "very large environment variable survives \$0 change");

# Test 6: Test environment inheritance in subprocess after $0 change
# This is closer to the actual systemd notification scenario
$ENV{SUBPROCESS_TEST} = "subprocess_value";
$0 = "test_subprocess_inheritance";

my $subprocess_ok = 0;
if (my $pid = fork()) {
    waitpid($pid, 0);
    $subprocess_ok = ($? >> 8) == 0;
} elsif (defined $pid) {
    # Child process - check if environment was inherited correctly
    exit 1 unless defined $ENV{SUBPROCESS_TEST};
    exit 2 unless $ENV{SUBPROCESS_TEST} eq "subprocess_value";
    exit 0;
} else {
    # Fork failed
    $subprocess_ok = 0;
}

ok($subprocess_ok, "environment inheritance to subprocess works after \$0 change");

# Test 7: Test with environment variables that might conflict with system vars
# Save originals
my $orig_path = $ENV{PATH};
my $orig_home = $ENV{HOME} || $ENV{USERPROFILE} || "";

# Modify critical system vars
$ENV{PATH} = "/test/path:/another/test/path";
$ENV{HOME} = "/test/home" if exists $ENV{HOME};
$ENV{USERPROFILE} = "/test/userprofile" if exists $ENV{USERPROFILE};

$0 = "test_system_vars_process";

# Check if modifications survived
my $system_vars_ok = 1;
$system_vars_ok = 0 unless $ENV{PATH} eq "/test/path:/another/test/path";

# Restore originals
$ENV{PATH} = $orig_path;
$ENV{HOME} = $orig_home if $orig_home && exists $ENV{HOME};
$ENV{USERPROFILE} = $orig_home if $orig_home && exists $ENV{USERPROFILE};

ok($system_vars_ok, "system environment variable modifications survive \$0 change");

# Test 8: Final integrity check - make sure our stress test vars are still there
my $final_integrity = 1;
for my $i (1..50) {
    my $var = "STRESS_ENV_VAR_$i";
    my $expected = "value_$i" . ("x" x 100);
    unless (defined $ENV{$var} && $ENV{$var} eq $expected) {
        $final_integrity = 0;
        last;
    }
}
ok($final_integrity, "all stress test environment variables survived");

# Clean up
for my $var (@env_vars) {
    delete $ENV{$var};
}
for my $i (1..10) {
    delete $ENV{"TEMP_VAR_$i"};
}
delete $ENV{VERY_LARGE_VAR};
delete $ENV{SUBPROCESS_TEST};
delete $ENV{'SPECIAL_VAR_=_EQUALS'};
delete $ENV{'SPECIAL_VAR_NULL'};
delete $ENV{'SPECIAL_VAR_NEWLINE'};

# This test is designed to expose putenv compatibility issues that would
# occur with the old my_setenv("NoNe SuCh", NULL) method when PERL_USE_SAFE_PUTENV
# is enabled in Perl 5.42. The stress conditions should reveal memory management
# or environment corruption issues that the simple tests might miss.
