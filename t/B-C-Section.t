#!perl -w

use strict;
use warnings;

use 5.14.0;    # Inline packages

use Test::More;
use Test::Trap;
use Test::Deep;

use FileHandle;
use B qw(SVf_FAKE);
use B::C::Section;

BEGIN {
	use B::C ();
	B::C::load_heavy(); # need some helpers from there & bootstrap C.xs
}

my %symtable;

my $aaasect   = B::C::Section->new( 'aaa',   \%symtable, 0 );
my $bbbsect   = B::C::Section->new( 'bbb',   \%symtable, 0 );
my $xpvcvsect = B::C::Section->new( 'xpvcv', \%symtable, 0 );
my $svsect    = B::C::Section->new( 'sv',    \%symtable, 0 );

is( $aaasect->typename,   'AAA',              "Typename for aaasect is upper cased as expected" );
is( $svsect->typename,    'SV',               "Typename for svsect is upper cased as expected" );
is( $xpvcvsect->typename, 'XPVCV', "Typename for xpvcvsect" );

my $svf_fake = B::SVf_FAKE();
my $expect = "NULL, 1, SVTYPEMASK|${svf_fake}, {0}\n";
is( $svsect->output("%s\n"), $expect, "svsect initializes with something automatically?" );
is( $svsect->index(),        0,       "Indext for svsect is right" );

{
	is eval { $svsect->output("%s\n"); 1 }, undef, "cannot call output twice";
	like $@, qr{B::C::Section output should only be called once}, 'B::C::Section output should only be called once';		
	ok $svsect->{_output_called}, "_output_called is set";
	$svsect->{_output_called} = undef; # disable the protection for the test
}

$svsect->add("yabba dabba doo");
$expect .= "yabba dabba doo\n";
is( $svsect->output("%s\n"), $expect, "svsect retains what was added. with something automatically?" );
is( $svsect->index(),        1,       "Index for svsect is right" );

$svsect->{_output_called} = undef; # disable the protection for the test

$svsect->remove;
$expect = "NULL, 1, SVTYPEMASK|${svf_fake}, {0}\n";
is( $svsect->output("%s\n"), $expect, "svsect retains what was added. with something automatically?" );
is( $svsect->index(),        0,       "Index for svsect is right after remove" );

is( $aaasect->comment,                  undef,       "comment Starts out blank" );
is( $aaasect->comment(qw/foo bar baz/), 'foobarbaz', "comment joins all passed args and stores/returns them." );
is( $aaasect->comment('flib'),          'flib',      "successive calls to comment overwrites/stores/returns the new stuff" );

is( $aaasect->comment_for_op('flib'), 'next, sibparent, ppaddr, targ, type, opt, slabbed, savefree, static, folded, moresib, spare, flags, private, flib', "comment_for_op" );

{
	note "testing debug";

$bbbsect->add('first row');
is( $bbbsect->debug('first'), 'first', 'first debug by default' );
is( $bbbsect->debug('second'), 'first, second', "second debug call" );

$bbbsect->add('second row');
is( $bbbsect->debug('newrow'), 'newrow', 'newrow create a new debug section' );
is( $bbbsect->debug(), 'newrow, undef', 'debug without args add undef' );

$bbbsect->add('third row');

is( $bbbsect->debug( 'some', undef, 'lines', undef), 'some, undef, lines, undef', 'multiple args debug call' );

}

{
	note "testing output";

	# Start over. Let's test output now.
	#B::C::Debug::enable_verbose();
	#B::C::Debug::enable_debug_level('flags');
	my $bbbsect;
    $bbbsect = B::C::Section->new( 'bbb', \%symtable, 'default_value_here' );
	$bbbsect->add("first row");
	$bbbsect->add("second row");
	$bbbsect->debug( 'my debug comment' );
	$bbbsect->add("third row");

	my $string;
	trap { $string = $bbbsect->output("%s\n") };
	is( $string, "first row\nsecond row\nthird row\n", "Simple output" );

	$bbbsect->{_output_called} = undef; # disable the protection for the test

	# testing with an unresolved symbol
	$bbbsect = B::C::Section->new( 'bbb', \%symtable, 'default_value_here' );
	$bbbsect->add("first", "s\\_134bcef33", 'third');
	trap { $string = $bbbsect->output("%s,\n") };
	is( $string, "first,\ndefault_value_here,\nthird,\n", "unresolved symbol" );

	$bbbsect->{_output_called} = undef; # disable the protection for the test

	# testing with a resolved symbol now
	$symtable{'s\_134bcef33'} = "resolved";
	trap { $string = $bbbsect->output("%s,\n") };
	is( $string, "first,\nresolved,\nthird,\n", "resolved symbol" );

	$bbbsect->{_output_called} = undef; # disable the protection for the test

	# testing get
	is $bbbsect->get( 0 ), 'first', 'get the first row';
	is $bbbsect->get( 1 ), 's\_134bcef33', 'get the second row (unresolved)';
	is $bbbsect->get( 2 ), 'third', 'get the third row';
	is $bbbsect->get( -1 ), 'third', 'get the last row';
	is $bbbsect->get( ), 'third', 'get the last row';

}

done_testing();
