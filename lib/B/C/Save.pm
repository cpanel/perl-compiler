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

use constant C_DECLARATION_FOR_COW_PV => q{Static const char allCOWPVs[]};

sub savecowpv ($pv) {

    my ( $cstring, $cur, $len, $utf8 ) = cow_strlen_flags($pv);
    return @{ $cowtable{$cstring} } if defined $cowtable{$cstring};

    if ( cowpv->index <= 0 ) {

        # the 0 entry is special
        cowpv->add( C_DECLARATION_FOR_COW_PV . qq{ = "";\n} );
    }

    my $ix = cowpv->add(qq[/* placeholder: filled later */]);

    my $pvsym = sprintf( q{COWPV%d}, $ix );
    $COW_map{$pvsym} = [ $ix, $len, $cstring, $pv ];    # consider removing the cstring

    # local cache for this function
    $cowtable{$cstring} = [ $pvsym, $cur, $len, $utf8 ];

    # NOTE: $cur is total size of the perl string. len would be the length of the C string.
    return ( $pvsym, $cur, $len, $utf8 );
}

#
# Run later when all our COWPV strings are setup
#
sub cowpv_setup() {

    my $total_len = 0;

    my @all_syms = keys %COW_map;    # shuffle the list
    if ( defined $ENV{BC_COWPV_SHUFFLE} && $ENV{BC_COWPV_SHUFFLE} eq 0 ) {
        warn "### WARNING: BC_COWPV_SHUFFLE=0\n";
        @all_syms = sort { $COW_map{$a}->[0] <=> $COW_map{$b}->[0] } @all_syms;
    }

    my @all_pvs;

    foreach my $pvsym (@all_syms) {
        my ( $ix, $len, $cstring, $pv ) = $COW_map{$pvsym}->@*;

        my $comment = _comment_str($cstring);
        my @cchars  = cchars($pv);

        # do not use the 'cstring' but split the char directly and encode it
        push @all_pvs, [
            cchars($pv), '0x00', '0xff',
            "/* $pvsym=$comment */\n"
        ];

        cowpv->supdate(
            $ix,
            q{#define %s (char*) allCOWPVs+%d /* %s */},
            $pvsym,
            $total_len,
            $comment
        );

        $total_len += $len;
    }

    # update definition...
    my $str = '';
    foreach my $pv (@all_pvs) {
        $str .= ( " " x 20 ) . join( ', ', @$pv );
    }
    my $declaration = sprintf(
        C_DECLARATION_FOR_COW_PV . qq[ = {\n%s\n};\n],
        $str
    );
    cowpv->update( 0, $declaration );

    cowpv()->{_total_len} = $total_len;

    return;
}

sub cchars ($pv) {

    # ensure to use a different PV
    $pv = $pv . "_";
    chop $pv;

    # "\x{100}" becomes "\xc4\x80"
    utf8::encode($pv) if utf8::is_utf8($pv);

    my @chars  = split( '', $pv );
    my @cchars = ( map { sprintf( q[0x%02x], ord($_) ) } @chars );

    if ( grep { hex($_) > 255 } @cchars ) {
        warn "PV: $pv";
        warn "CCHARS: @cchars";

        require Devel::Peek;
        Devel::Peek::Dump($pv);

        die qq[PV contains some unexpected characters];
    }

    return @cchars;
}

sub _comment_str ($str) {
    $str =~ s{\Q/*\E}{??}g;
    $str =~ s{\Q*/\E}{??}g;
    $str =~ s{\Q\000\377\E"$}{"};    # remove the cow part
    $str =~ s{\n}{\\n}g;

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
