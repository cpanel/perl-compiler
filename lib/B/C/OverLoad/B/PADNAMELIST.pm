package B::PADNAMELIST;

use B::C::Std;

our @ISA = qw(B::AV);

use B::C::File qw/padnamelistsect/;

sub section_sv {
    return padnamelistsect();
}

sub update_sv ( $av, $ix, $fullname, @ ) {

    my $section = $av->section_sv();
    $section->comment("xpadnl_fill, xpadnl_alloc, xpadnl_max, xpadnl_max_named, xpadnl_refcnt");

    # TODO: max_named walk all names and look for non-empty names
    my $refcnt   = $av->REFCNT;
    my $fill     = $av->MAX;
    my $maxnamed = $av->MAXNAMED;

    $section->update( $ix, "$fill, NULL, $fill, $maxnamed, $refcnt" );

    return;
}

sub add_malloc_line_for_array_init ( $av, $deferred_init, $sym, @ ) {

    my $fill = $av->MAX + 1;
    $deferred_init->sadd( "PADNAME **svp = %s;", B::C::Memory::INITPADNAME( $deferred_init, $sym, $fill ) );

    return;
}

sub cast_sv {
    return "(PADNAME*)";
}

sub cast_section {    ### Stupid move it to section !!! a section know its type
    return "PADNAMELIST*";
}

sub fill ($av) { return $av->MAX }

1;
