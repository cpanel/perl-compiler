#!/usr/bin/perl
# Test to detect environment corruption that would occur with old dup_environ method
# This test is designed to FAIL with the old my_setenv("NoNe SuCh", NULL) approach
# and PASS with the new dup_environ() approach

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}

use strict;
use warnings;

plan(12);

# Test 1: Establish comprehensive environment baseline
my @test_vars   = qw(TEST_VAR_1 TEST_VAR_2 TEST_VAR_3 TEST_VAR_4 TEST_VAR_5);
my @test_values = qw(value1 value2 value3 value4 value5);

for my $i ( 0 .. $#test_vars ) {
    $ENV{ $test_vars[$i] } = $test_values[$i];
}

my $baseline_count = scalar keys %ENV;
pass("comprehensive environment baseline established ($baseline_count vars)");

# Test 2: Verify all test variables are set correctly
my $all_set = 1;
for my $i ( 0 .. $#test_vars ) {
    unless ( defined $ENV{ $test_vars[$i] } && $ENV{ $test_vars[$i] } eq $test_values[$i] ) {
        $all_set = 0;
        last;
    }
}
ok( $all_set, "all test environment variables set correctly" );

# Test 3: Store critical system variables for comparison
my $original_path = $ENV{PATH} || "";
my $original_home = $ENV{HOME} || $ENV{USERPROFILE} || "";
my $original_user = $ENV{USER} || $ENV{USERNAME}    || "";
ok( length($original_path) > 0, "critical system variables captured" );

# Test 4: First $0 change - this triggers environment duplication
# In buggy versions using my_setenv("NoNe SuCh", NULL), this would corrupt environ
$0 = "test_environ_corruption_detector";
is( $0, "test_environ_corruption_detector", "first process name change successful" );

# Test 5: Check if environment count changed unexpectedly
my $post_change_count = scalar keys %ENV;
ok( $post_change_count >= $baseline_count, "environment count stable after \$0 change" );

# Test 6: Verify all test variables still exist and have correct values
my $all_preserved = 1;
for my $i ( 0 .. $#test_vars ) {
    unless ( defined $ENV{ $test_vars[$i] } && $ENV{ $test_vars[$i] } eq $test_values[$i] ) {
        $all_preserved = 0;
        last;
    }
}

ok( $all_preserved, "all test variables preserved after \$0 change" );

# Test 7: Verify critical system variables preserved
my $system_preserved = 1;
$system_preserved = 0 if defined $original_path && ( !defined $ENV{PATH} || $ENV{PATH} ne $original_path );
$system_preserved = 0
  if defined $original_home
  && length($original_home) > 0
  && ( !defined $ENV{HOME} && !defined $ENV{USERPROFILE} );
ok( $system_preserved, "critical system variables preserved" );

# Test 8: Test environment modification after $0 change
$ENV{POST_CHANGE_TEST} = "modification_test";
is( $ENV{POST_CHANGE_TEST}, "modification_test", "can modify environment after \$0 change" );

# Test 9: Multiple rapid $0 changes (stress test for environment duplication)
for my $i ( 1 .. 5 ) {
    $0 = "stress_test_process_$i";
    $ENV{"STRESS_VAR_$i"} = "stress_value_$i";
}

my $stress_success = 1;
for my $i ( 1 .. 5 ) {
    unless ( defined $ENV{"STRESS_VAR_$i"} && $ENV{"STRESS_VAR_$i"} eq "stress_value_$i" ) {
        $stress_success = 0;
        last;
    }
}
ok( $stress_success, "multiple rapid \$0 changes handled correctly" );

# Test 10: Environment deletion works
delete $ENV{POST_CHANGE_TEST};
ok( !defined $ENV{POST_CHANGE_TEST}, "environment variable deletion works" );

# Test 11: Large environment variable handling
my $large_value = "x" x 1000;    # 1KB value
$ENV{LARGE_TEST_VAR} = $large_value;
is( $ENV{LARGE_TEST_VAR}, $large_value, "large environment variables handled correctly" );

# Test 12: Final integrity check
my $final_count         = scalar keys %ENV;
my $final_all_preserved = 1;
for my $i ( 0 .. $#test_vars ) {
    unless ( defined $ENV{ $test_vars[$i] } && $ENV{ $test_vars[$i] } eq $test_values[$i] ) {
        $final_all_preserved = 0;
        last;
    }
}
ok( $final_all_preserved && $final_count >= $baseline_count, "final environment integrity check passed" );

# Clean up
for my $i ( 0 .. $#test_vars ) {
    delete $ENV{ $test_vars[$i] };
}
for my $i ( 1 .. 5 ) {
    delete $ENV{"STRESS_VAR_$i"};
}
delete $ENV{LARGE_TEST_VAR};

# This test is specifically designed to detect the environment corruption
# that would occur with the old my_setenv("NoNe SuCh", NULL) method
# when compiled with perlcc and PERL_USE_SAFE_PUTENV enabled
