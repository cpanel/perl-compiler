package B::C::OverLoad;

use B::C::OverLoad::B::OBJECT      ();    # nothing to save here
use B::C::OverLoad::B::PADLIST     ();    # uses B::AV::save logic
use B::C::OverLoad::B::PADNAMELIST ();    # uses B::AV::save logic
use B::C::OverLoad::B::SPECIAL     ();    # nothing to do there: handle specialsv_name

BEGIN {
    # needs to be loaded first: provide common helper for all OPs
    # 	::save provides the cache mechanism for free, and avoid boilerplates/errors in OPs
    require B::C::OP;

    my @OPs = qw{AV BINOP COP CV GV IV HV IO LISTOP LOGOP LOOP
      METHOP NULL NV OP PADNAME PMOP PV PVIV PVLV PVMG
      PVNV PVOP REGEXP RV
      SVOP UNOP UNOP_AUX UV
      INVLIST
    };

    # do not use @ISA, just plug what we need
    foreach my $op (@OPs) {
        no strict 'refs';
        my $pkg      = qq{B::$op};
        my $overload = "B::C::OverLoad::$pkg";

        # problems. Ideally this code should be removed in favor of a better solution.
        eval qq{require $overload} or die $@;
        my $save = $pkg . q{::save};
        *$save = B::C::OP::save_constructor($pkg);

    }
}

1;
