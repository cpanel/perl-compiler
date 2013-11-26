#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=90
# Magic Tie::Named::Capture <=> *main::+ main::*- and Errno vs !
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 16;
my $i=0;
sub test3 {
  my $name = shift;
  my $script = shift;
  my $cmt = join('',@_);
  my $todo = "";
  $todo = 'TODO ' if $name eq 'ccode90i_c' or $] > 5.015;
  plctestok($i*3+1, $name, $script, $todo." BC ".$cmt);
  ctestok($i*3+2, "C", $name, $script, "C $cmt");
  ctestok($i*3+3, "CC", $name, $script, $todo."CC $cmt");
  $i++;
}

SKIP: {
  skip "Tie::Named::Capture requires Perl v5.10", 3 if $] < 5.010;

  test3('ccode90i_c', <<'EOF', '%+ includes Tie::Hash::NamedCapture');
my $s = 'test string';
$s =~ s/(?<first>test) (?<second>string)/\2 \1/g;
print q(o) if $s eq 'string test';
'test string' =~ /(?<first>\w+) (?<second>\w+)/;
print q(k) if $+{first} eq 'test';
EOF
}

test3('ccode90i_ca', <<'EOF', '@+');
"abc" =~ /(.)./; print "ok" if "21" eq join"",@+;
EOF

test3('ccode90i_es', <<'EOF', '%! magic');
my %errs = %!; # t/op/magic.t Errno compiled in
print q(ok) if defined ${"!"}{ENOENT};
EOF

# this fails so far, %{"!"} is not detected at compile-time. requires -uErrno
test3('ccode90i_er', <<'EOF', 'Errno loaded automagically');
my %errs = %{"!"}; # t/op/magic.t Errno to be loaded at run-time
print q(ok) if defined ${"!"}{ENOENT};
EOF

test3('ccode90i_ep', <<'EOF', '%! pure IV');
print FH "foo"; print "ok" if $! == 9;
EOF

ctestok(16, 'C', 'ccode90i_ce', <<'EOF', 'TODO C more @+');
my $content = "ok\n";
while ( $content =~ m{\w}g ) {
    $_ .= "$-[0]$+[0]";
}
print "ok" if $_ eq "0112";
EOF
