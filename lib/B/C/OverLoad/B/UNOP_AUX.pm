package B::UNOP_AUX;

use strict;

use B::C::Debug qw/debug/;
use B::C::File qw/unopauxsect init free meta_unopaux_item/;
use B::C::Helpers qw/is_constant/;

sub do_save {
    my ($op) = @_;

    my @aux_list = $op->name eq 'multideref' ? $op->aux_list_thr : $op->aux_list;    # GH#283, GH#341
    my $auxlen = scalar @aux_list;

    unopauxsect()->comment_for_op("first, aux");
    my ( $ix, $sym ) = unopauxsect()->reserve( $op, "OP*" );
    unopauxsect()->debug( $op->name, $op );

    my @to_be_filled = map { 0 } 1 .. $auxlen;                                       #

    my $list_size         = $auxlen + 1;
    my $unopaux_item_sect = meta_unopaux_item($list_size);
    $unopaux_item_sect->comment(q{length prefix, UNOP_AUX_item * $auxlen });
    my $uaux_item_ix = $unopaux_item_sect->add( join( ', ', qq[{.uv=$auxlen}], @to_be_filled ) );

    my $symname = sprintf( 'meta_unopaux_item%d_list[%d]', $list_size, $uaux_item_ix );
    unopauxsect()->supdate( $ix, "%s, %s, &%s.aaab", $op->save_baseop, $op->first->save, $symname );

    # This cannot be a section, as the number of elements is variable
    my $i            = 1;                                                            # maybe rename tp field_ix
    my $struct_field = q{aaaa};

    my $action = 0;
    for my $item (@aux_list) {
        my $field;

        $struct_field++;
        my $symat = "${symname}.$struct_field";

        unless ( ref $item ) {

            # symbolize MDEREF action
            my $cmt = $op->get_action_name($item);
            $action = $item;

            #debug( hv => $op->name . " action $action $cmt" );
            $field = sprintf( "{.uv=0x%x}", $item );    #  \t/* %s: %u */ , $cmt, $item
        }
        else {
            # const and sv already at compile-time, gv deferred to init-time.
            # testcase: $a[-1] -1 as B::IV not as -1
            # hmm, if const ensure that candidate CONSTs have been HEKified. (pp_multideref assertion)
            # || SvTYPE(keysv) >= SVt_PVMG
            # || !SvOK(keysv)
            # || SvROK(keysv)
            # || SvIsCOW_shared_hash(keysv));
            my $constkey = ( $action & 0x30 ) == 0x10 ? 1 : 0;
            my $itemsym = $item->save( "$symat" . ( $constkey ? " const" : "" ) );
            if ( is_constant($itemsym) ) {
                if ( ref $item eq 'B::IV' ) {
                    my $iv = $item->IVX;
                    $field = "{.iv=$iv}";
                }
                elsif ( ref $item eq 'B::UV' ) {    # also for PAD_OFFSET
                    my $uv = $item->UVX;
                    $field = "{.uv=$uv}";
                }
                else {                              # SV
                    $field = "{.sv=$itemsym}";
                }
            }
            else {
                if ( $itemsym =~ qr{^PL_} ) {
                    $field = "{.sv=Nullsv}";        #  \t/* $itemsym */
                    init()->add("$symat.sv = (SV*)$itemsym;");
                }
                else {
                    ## gv or other late inits
                    $field = "{.sv = (SV*) $itemsym}";
                }
            }
        }

        $unopaux_item_sect->update_field( $uaux_item_ix, $i, q[ ] . $field );
        $i++;
    }

    free()->add("    ($sym)->op_type = OP_NULL;");

    return $sym;
}

sub get_action_name {
    my ( $op, $item ) = @_;

    my $cmt = 'action';
    if ( $op->name eq 'multideref' ) {
        my $act = $item & 0xf;    # MDEREF_ACTION_MASK
        $cmt = 'AV_pop_rv2av_aelem'          if $act == 1;
        $cmt = 'AV_gvsv_vivify_rv2av_aelem'  if $act == 2;
        $cmt = 'AV_padsv_vivify_rv2av_aelem' if $act == 3;
        $cmt = 'AV_vivify_rv2av_aelem'       if $act == 4;
        $cmt = 'AV_padav_aelem'              if $act == 5;
        $cmt = 'AV_gvav_aelem'               if $act == 6;
        $cmt = 'HV_pop_rv2hv_helem'          if $act == 8;
        $cmt = 'HV_gvsv_vivify_rv2hv_helem'  if $act == 9;
        $cmt = 'HV_padsv_vivify_rv2hv_helem' if $act == 10;
        $cmt = 'HV_vivify_rv2hv_helem'       if $act == 11;
        $cmt = 'HV_padhv_helem'              if $act == 12;
        $cmt = 'HV_gvhv_helem'               if $act == 13;
        my $idx = $item & 0x30;    # MDEREF_INDEX_MASK
        $cmt .= ''             if $idx == 0x0;
        $cmt .= ' INDEX_const' if $idx == 0x10;
        $cmt .= ' INDEX_padsv' if $idx == 0x20;
        $cmt .= ' INDEX_gvsv'  if $idx == 0x30;
    }
    elsif ( $op->name eq 'signature' ) {    # cperl only for now
        my $act = $item & 0xf;              # SIGNATURE_ACTION_MASK
        $cmt = 'reload'            if $act == 0;
        $cmt = 'end'               if $act == 1;
        $cmt = 'padintro'          if $act == 2;
        $cmt = 'arg'               if $act == 3;
        $cmt = 'arg_default_none'  if $act == 4;
        $cmt = 'arg_default_undef' if $act == 5;
        $cmt = 'arg_default_0'     if $act == 6;
        $cmt = 'arg_default_1'     if $act == 7;
        $cmt = 'arg_default_iv'    if $act == 8;
        $cmt = 'arg_default_const' if $act == 9;
        $cmt = 'arg_default_padsv' if $act == 10;
        $cmt = 'arg_default_gvsv'  if $act == 11;
        $cmt = 'arg_default_op'    if $act == 12;
        $cmt = 'array'             if $act == 13;
        $cmt = 'hash'              if $act == 14;
        my $idx = $item & 0x3F;    # SIGNATURE_MASK
        $cmt .= ''           if $idx == 0x0;
        $cmt .= ' flag skip' if $idx == 0x10;
        $cmt .= ' flag ref'  if $idx == 0x20;
    }
    else {
        die "Unknown UNOP_AUX op {$op->name}";
    }

    return $cmt;

}

1;
