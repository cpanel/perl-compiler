package B::C::InitSection::XOPs;

use B::C::Std;
use warnings;

use B qw/cstring/;

# avoid use vars
use base 'B::C::InitSection';

sub has_values {
    my ($self) = @_;

    return 1 if defined $self->{xops} && scalar keys %{ $self->{xops} };

    return $self->SUPER::has_values();
}

=pod

xop_used_by(xop_name, opsym)

Declare that one XOP is used by one OP.

At init time we will look for the XOP defined with this name
and plug it to the ppaddr for the opsym.

example:
    $xops->xop_used_by( 'is_yourmum',  '(OP*)&unop_list[11]' );

=cut

sub xop_used_by ( $self, $xop_name, $opsym ) {

    $self->{xops} //= {};
    my $xops = $self->{xops};

    my ( $optype, $id );
    if ( $opsym =~ m{&(\w+_list)\[(\d+)\]}a ) {
        $optype = $1;
        $id     = $2;
    }
    else {
        die "xop_used_by: Fail to parse opsym: $opsym";
    }

    $xops->{$xop_name} //= {
        optype => $optype,
        ids    => [],
    };

    if ( $xops->{$xop_name}->{optype} ne $optype ) {
        die "XOP $xop_name: was expecting optype " . "'" . $xops->{$xop_name}->{optype} . "' " . "got '$optype'";
    }

    push @{ $xops->{$xop_name}->{ids} }, $id;

    return;
}

# flush the last group
sub flush ($self) {

    # only flush once
    return $self if $self->{_flushed};
    $self->{_flushed} = 1;

    return unless defined $self->{xops};

    $self->add_c_header('register int i;');

    foreach my $name ( sort keys %{ $self->{xops} } ) {
        my $xop    = $self->{xops}->{$name};
        my @ids    = sort { $a <=> $b } @{ $xop->{ids} };
        my $optype = $xop->{optype};

        my $cids = join( ', ', @ids );
        my $size = scalar @ids;

        my $cname = cstring($name);    # name should already be c-friendly

        # note we could also optimize list we single elements
        #   but have probably more to win with ranges if OPs are consecutive
        #   - probability of having consecutive OPs id is low...
        $self->add( <<"EOS" );
        {
            void *ppaddr   = bc_xop_ppaddr_from_name($cname);
            int idx[$size] = { $cids };

            for ( i = 0; i < $size; ++i ) {
                ( (OP*) &${optype}[ idx[i] ] )->op_ppaddr = (OP* (*)()) ppaddr;
            }
        }
EOS

    }

    return $self;    # can chain like flush.output
}

1;
