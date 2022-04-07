package B::C::Std;

use strict;

sub import {

    strict->import();

    # comp/use.t is blocking feature.pm... we can safely load it from this point
    delete $INC{'feature.pm'} if defined $INC{'feature.pm'} && $INC{'feature.pm'} !~ m{/} && !-e $INC{'feature.pm'};
    require feature;
    feature->import( ':5.36', 'signatures' );
    warnings->unimport('experimental::signatures');

    return;
}

1;
