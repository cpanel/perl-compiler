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

sub savecowpv ($pv) {

    my ( $cstring, $cur, $len, $utf8 ) = cow_strlen_flags($pv);
    return @{ $cowtable{$cstring} } if defined $cowtable{$cstring};

    if ( cowpv->index <= 0 ) {

        # the 0 entry is special
        cowpv->add(qq{Static const char allCOWPVs[] = "";\n});    # ";\n -> 3
        cowpv()->{_total_len} = 0;
    }

    {                                                             # append our string to the declaration of strings
        my $declaration    = cowpv->get(0);
        my $noquotecstring = $cstring;
        $noquotecstring =~ s{^"}{};
        $noquotecstring =~ s{"$}{};

        my $end = qq{";\n};

        # we are playing here with the limits with very long strings
        #   but we can easily split them as part of a next iteration
        #   by having multiple allCOWPVs strings
        $declaration =~ s[^(.+)(\Q$end\E)$][$1${noquotecstring}$2]m;
        cowpv->update( 0, $declaration );
    }

    my $ix = cowpv->index();    # not really exact

    {
        my $comment_str = $cstring;
        $comment_str =~ s{\Q/*\E}{??}g;
        $comment_str =~ s{\Q*/\E}{??}g;
        $comment_str =~ s{\Q\000\377\E"$}{"};    # remove the cow part
        cowpv->sadd( q{#define COWPV%d (char*) allCOWPVs+%d /* %s */}, $ix, cowpv()->{_total_len}, $comment_str );
    }

    # increase the total length of our master string (only after having use it)
    cowpv()->{_total_len} += $len;

    my $pvsym = sprintf( q{COWPV%d}, $ix );

    $cowtable{$cstring} = [ $pvsym, $cur, $len, $utf8 ];

    return ( $pvsym, $cur, $len, $utf8 );    # NOTE: $cur is total size of the perl string. len would be the length of the C string.
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
