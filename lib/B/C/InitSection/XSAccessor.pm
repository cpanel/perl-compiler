package B::C::InitSection::XSAccessor;

use B::C::Std;
use warnings;

use B          qw/cstring/;
use B::C::Save qw/savecowpv/;

# avoid use vars
use base 'B::C::InitSection';

sub has_values ($self) {

    return 1 if defined $self->{methods} && scalar keys %{ $self->{methods} };

    return $self->SUPER::has_values();
}

sub setup_method_for ( $self, %opts ) {

    $self->{methods} //= {};

    my $method = $opts{xs_sub};
    die "xs_sub must be defined" unless $method;

    # multiple functions are sharing the same xs_sub
    # note that Class::XSAccessor::constructor is special and is the 'contructor' a.k.a. new
    $self->{methods}->{$method} //= [];

    # force the cowpv to be stored - need to occurs before flush
    my ( $method_cowpv, undef, undef ) = savecowpv($method);

    push @{ $self->{methods}->{$method} }, {%opts};

    return;
}

# flush the last group
sub flush ($self) {

    # only flush once
    return $self if $self->{_flushed};
    $self->{_flushed} = 1;

    return unless defined $self->{methods};

    $self->add_c_header('void (*xcv_xsub) (pTHX_ CV*);');

    foreach my $method ( sort keys %{ $self->{methods} } ) {
        my $xa = $self->{methods}->{$method};

        #my $comment = sprintf( 'XSAccessor for %s', $method );
        $self->open_block($method);    # do not split in the middle of one function

        my ( $method_cowpv, undef, undef ) = savecowpv($method);

        # fetch the xsub once
        $self->sadd( '/* %s */', "fetch method $method" );

        $self->sadd(                   # .
            'xcv_xsub = CvXSUB(GvCV(gv_fetchpv( %s, GV_NOADD_NOINIT, SVt_PVGV)));',    # .
            $method_cowpv
        );

        # maybe add one if check on xcv_xsub

        # assignment
        foreach my $xa ( sort { $a->{fullname} cmp $b->{fullname} } @{ $self->{methods}->{$method} } ) {
            my @path      = split qr/::/, $xa->{fullname};
            my $shortname = $path[-1];

            # now plug the xsub to our XPVCV
            $self->sadd( 'xpvcv_list[%u].xcv_root_u.xcv_xsub = xcv_xsub; /* %s */', $xa->{xpvcv_ix}, $xa->{fullname} );

            # the constructor does not use one xsaccessor_list entry
            next if $method eq 'Class::XSAccessor::constructor';

            $self->sadd(
                q[PERL_HASH( (%s)->hash, %s, %d); /* %s */],
                $xa->{xsaccessor_entry},
                $xa->{xsaccessor_key},
                $xa->{xsaccessor_key_len},
                $xa->{fullname}
            );
        }

        $self->close_block();
    }

    return $self;    # can chain like flush.output
}

1;
