package B::SPECIAL;

use B::C::Std;
use B qw( @specialsv_name);

sub save ( $sv, $fullname = undef ) {

    # Nullsv &PL_sv_undef &PL_sv_yes &PL_sv_no &PL_sv_zero (SV*)pWARN_ALL (SV*)pWARN_NONE (SV*)pWARN_STD
    my $sym = $specialsv_name[$$sv];
    if ( !defined($sym) ) {
        warn "unknown specialsv index $$sv passed to B::SPECIAL::save";
    }

    return $sym;
}

#ignore nullified cv
sub savecv { }

1;
