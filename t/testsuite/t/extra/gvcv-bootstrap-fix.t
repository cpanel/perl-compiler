#!/usr/bin/perl
# Test for GvCV bootstrap fix - ensures that memorized GV symbols are properly dereferenced
# when used with GvCV() in bootstrap linking code.

package main;

print "1..3\n";

# Test that UNIVERSAL::can works (this was the specific case mentioned in the bug report)
my $can_method = UNIVERSAL->can('can');
print "ok 1 - UNIVERSAL::can method found\n" if defined $can_method;

# Test that we can call it
my $result = UNIVERSAL::can('UNIVERSAL', 'can');
print "ok 2 - UNIVERSAL::can('UNIVERSAL', 'can') works\n" if defined $result;

# Test that it returns the same thing
print "ok 3 - UNIVERSAL::can returns consistent results\n" if $can_method == $result;

# This test specifically exercises the code path that was failing:
# When UNIVERSAL::can is compiled, it creates a bootstrap link that uses GvCV()
# The fix ensures that if the GV symbol is memorized (like &gv_list[415]),
# it gets properly dereferenced to *(&gv_list[415]) before being passed to GvCV()
