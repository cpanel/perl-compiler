package B::IO;

use B::C::Std;

use B          qw/cchar svref_2object/;
use B::C::Save qw/savecowpv/;
use B::C::File qw/init init2 svsect xpviosect/;

sub save_io_and_data ( $io, $globname, $is_utf8, $data ) {

    my $ref = svref_2object( \$data )->save;

    my $use_utf8 = $is_utf8 ? 'use utf8; ' : '';

    # force inclusion of PerlIO::scalar as it was loaded in BEGIN. ?
    init2()->add_eval( sprintf( '%sopen(%s, \'<:scalar\', \\\\$%s);', $use_utf8, $globname, $globname ) );

    #init()->pre_destruct( sprintf 'eval_pv("close %s;", 1);', $globname );    # is this really required ?

    return ( q{NULL}, $ref );
}

sub do_save ( $io, $fullname = undef ) {

    $io->FLAGS & 2048 and die sprintf( "Unexpected SVf_ROK found in %s\n", ref $io );
    my ( $ix, $sym ) = svsect()->reserve($io);
    svsect()->debug( $fullname, $io );

    my ( $default, $default_top ) = '';
    if ( $fullname =~ qr{([^:]+)$} ) {
        $default     = $1;
        $default_top = $default . '_TOP';
    }

    my ( $xio_top_name,    undef, undef ) = savecowpv( $io->TOP_NAME    || $default_top );
    my ( $xio_fmt_name,    undef, undef ) = savecowpv( $io->FMT_NAME    || $default );       # default is STDOUT
    my ( $xio_bottom_name, undef, undef ) = savecowpv( $io->BOTTOM_NAME || '' );             # is this really used ?

    my $top_gv    = $io->TOP_GV->save;
    my $fmt_gv    = $io->FMT_GV->save;
    my $bottom_gv = $io->BOTTOM_GV->save;
    foreach ( $top_gv, $fmt_gv, $bottom_gv ) {
        $_ = 'NULL' if ( $_ eq 'Nullsv' );
    }

    xpviosect()->comment('xmg_stash, xmg_u, xpv_cur, xpv_len_u, xiv_u, xio_ofp, xio_dirpu, xio_page, xio_page_len, xio_lines_left, xio_top_name, xio_top_gv, xio_fmt_name, xio_fmt_gv, xio_bottom_name, xio_bottom_gv, xio_type, xio_flags');
    my $xpvio_ix = xpviosect()->saddl(
        "%s"                => $io->save_magic_stash,         # xmg_stash
        "{%s}"              => $io->save_magic($fullname),    # xmg_u
        "%u"                => $io->CUR,                      # xpv_cur
        "{.xpvlenu_len=%u}" => $io->LEN,                      # xpv_len_u

        # end of head
        "{.xivu_uv=%d}"           => 0,                       # xiv_u
        "(PerlIO*) %d"            => 0,                       # xio_ofp
        "{.xiou_any =(void*) %s}" => q{NULL},                 # xio_dirpu
        "%d"                      => $io->PAGE,               # xio_page        /* $% */
        "%d"                      => $io->PAGE_LEN,           # xio_page_len    /* $= */
        "%d"                      => $io->LINES_LEFT,         # xio_lines_left  /* $- */
        "(char*) %s"              => $xio_top_name,           # xio_top_name    /* $^ */
        "(GV*)%s"                 => $top_gv,                 # xio_top_gv      /* $^ */
        "(char*)%s"               => $xio_fmt_name,           # xio_fmt_name    /* $~ */
        "(GV*)%s"                 => $fmt_gv,                 # xio_fmt_gv      /* $~ */
        "(char*)%s"               => $xio_bottom_name,        # xio_bottom_name /* $^B */
        "(GV*) %s"                => $bottom_gv,              # xio_bottom_gv   /* $^B */
        '%s'                      => cchar( $io->IoTYPE ),    # xio_type
        "0x%x"                    => $io->IoFLAGS,            # xio_flags
    );

    svsect->supdatel(
        $ix,
        "(XPVIO*)&xpvio_list[%u]" => $xpvio_ix,               # SvANY=XPVIO*
        "%Lu"                     => $io->REFCNT + 1,         # refcnt
        "0x%x"                    => $io->FLAGS,              # flags
        "{%d}"                    => 0,                       # sv_u ( fileno ? )
    );

    return $sym;
}

1;
