package B::C::Save;

use B::C::Std;

use B::C::Debug   qw/debug/;
use B::C::File    qw( xpvmgsect decl init const cowpv );
use B::C::Helpers qw/strlen_flags cstring_cow cow_strlen_flags/;

use Exporter ();
our @ISA = qw(Exporter);

our @EXPORT_OK = qw/savecowpv/;

my %strtable;
my %cowtable;

my %COW_map;

sub savecowpv ($pv) {

    my ( $cstring, $cur, $len, $utf8 ) = cow_strlen_flags($pv);
    return @{ $cowtable{$cstring} } if defined $cowtable{$cstring};

    if ( cowpv->index <= 0 ) {

        # the 0 entry is special
        cowpv->add(qq{Static const char allCOWPVs[] = "";\n});    # ";\n -> 3
    }

    my $ix = cowpv->add(qq[/* fill later */]);

    my $pvsym = sprintf( q{COWPV%d}, $ix );
    $COW_map{$pvsym} = [ $ix, $len, $cstring ];

    # local cache for this function
    $cowtable{$cstring} = [ $pvsym, $cur, $len, $utf8 ];

    return ( $pvsym, $cur, $len, $utf8 );    # NOTE: $cur is total size of the perl string. len would be the length of the C string.
}

#
# Run later when all our COWPV strings are setup
#
sub cowpv_setup() {

    my $total_len = 0;

    foreach my $pvsym (
        sort { $COW_map{$a}->[0] <=> $COW_map{$b}->[0] }    # FIXME to remove
        keys %COW_map
      ) {                                                   # shuffle the list
        my ( $ix, $len, $cstring ) = $COW_map{$pvsym}->@*;

        _append_str_to_allCOWPV($cstring);

        cowpv->supdate(
            $ix,
            q{#define %s (char*) allCOWPVs+%d /* %s */},
            $pvsym,
            $total_len,
            _comment_str($cstring)
        );

        $total_len += $len;
    }

    cowpv()->{_total_len} = $total_len;

    return;
}

sub _append_str_to_allCOWPV ($str) {

    # append our string to the declaration of strings

    my $declaration = cowpv->get(0);

    $str =~ s{^"}{};
    $str =~ s{"$}{};

    my $end = qq{";\n};

    # we are playing here with the limits with very long strings
    #   but we can easily split them as part of a next iteration
    #   by having multiple allCOWPVs strings
    $declaration =~ s[^(.+)(\Q$end\E)$][$1${str}$2]m;
    cowpv->update( 0, $declaration );

    return;
}

sub _comment_str ($str) {
    $str =~ s{\Q/*\E}{??}g;
    $str =~ s{\Q*/\E}{??}g;
    $str =~ s{\Q\000\377\E"$}{"};    # remove the cow part

    return $str;
}

sub _caller_comment {
    return '' unless debug('stack');
    my $s = stack_flat(+1);
    return qq{/* $s */};
}

sub stack {
    my @stack;
    foreach my $level ( 0 .. 100 ) {
        my @caller = grep { defined } caller($level);
        @caller = map { $_ =~ s{/usr/local/cpanel/3rdparty/perl/5[0-9]+/lib64/perl5/cpanel_lib/x86_64-linux-64int/}{lib/}; $_ } @caller;

        last if !scalar @caller or !defined $caller[0];
        push @stack, join( ' ', @caller );
    }

    return \@stack;
}

sub stack_flat ( $remove = 0 ) {
    $remove += 2;
    my @stack = @{ stack() };
    splice( @stack, 0, $remove );    # shift the first X elements
    return join "\n", @stack;
}

1;
