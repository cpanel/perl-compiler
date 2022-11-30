package B::PADLIST;

use B::C::Std;

our @ISA = qw(B::AV);

use B::C::File qw/padlistsect/;

sub section_sv {
    return padlistsect();
}

sub update_sv ( $av, $ix, $fullname, @ ) {    # id+outid as U32 (PL_padlist_generation++)

    my $section = $av->section_sv();
    $section->comment("xpadl_max, xpadl_alloc, xpadl_id, xpadl_outid");
    $section->supdatel(
        $ix,
        '%s' => $av->MAX,      # xpadl_max
        '%s' => '{NULL}',      # xpadl_alloc
        '%s' => $av->id,       # xpadl_id
        '%s' => $av->outid,    # xpadl_outid
    );

    return;
}

sub add_malloc_line_for_array_init ( $av, $deferred_init, $sym, @ ) {

    my $fill = $av->MAX + 1;
    $deferred_init->sadd( "PAD **svp = %s;", B::C::Memory::INITPADLIST( $deferred_init, $sym, $fill ) );
}

sub cast_sv {
    return "(PAD*)";
}

sub cast_section {    ### Stupid move it to section !!! a section know its type
    return "PADLIST*";
}

sub fill ($av) { return $av->MAX }

1;
