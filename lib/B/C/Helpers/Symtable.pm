package B::C::Helpers::Symtable;

use B::C::Std;

use Exporter ();

our @ISA = qw(Exporter);

our @EXPORT_OK = qw(get_symtable_ref savesym objsym getsym dump_symtable delsym);

my %SYMTABLE;

sub get_symtable_ref {
    return \%SYMTABLE;
}

# todo move all the sym to helper
sub savesym ( $obj, $value ) {
    no strict 'refs';
    my $sym = sprintf( "s\\_%x", $$obj );
    $SYMTABLE{$sym} = $value;
    return $value;
}

sub objsym ($obj) {
    no strict 'refs';
    return $SYMTABLE{ sprintf( "s\\_%x", $$obj ) };
}

sub getsym ($sym) {

    my $value;

    return 0 if $sym eq "sym_0";    # special case
    $value = $SYMTABLE{$sym};
    return $value if defined($value);

    warn "warning: undefined symbol $sym\n" if $B::C::settings->{'warn_undefined_syms'};
    return "UNUSED";
}

sub delsym ($obj) {
    my $sym = sprintf( "s\\_%x", $$obj );

    # fixme move the variable here with accessor
    delete $SYMTABLE{$sym};

    return;
}

sub clearsym() {    #unit test helper

    %SYMTABLE = ();

    return;
}

sub dump_symtable() {

    # For debugging
    my ( $sym, $val );
    warn "----Symbol table:\n";

    for $sym ( sort keys %SYMTABLE ) {
        $val = $SYMTABLE{$sym};
        warn "$sym => $val\n";
    }
    warn "---End of symbol table\n";
}

1;
