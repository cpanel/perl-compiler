package B::C::InitSection::Vtables;

use B::C::Std;
use warnings;

use base 'B::C::InitSection';

=pod

add_pvmg:

Provide an abstraction to setup the mg_virtual attribute
from a magic_list entry.

The idea is to use a for loop for the following pattern

    '%s.mg_virtual = (MGVTBL*) &PL_vtbl_%s;', $last_magic, $vtable

=cut

sub add_pvmg ( $self, $ix, $vtable ) {

    return unless $vtable;

    if ( !defined $self->{group} ) {
        $self->{group} = {};

        # only declar the variable once per function
        $self->add_c_header('register int i;');
    }

    $self->{group} //= {};
    my $group = $self->{group};    # alias for current group

    # if this is the first time
    #   or we have a different vtable name
    #   or we have a gap
    if (   defined $group->{vtable}
        && $group->{vtable} eq $vtable
        && ( $group->{to} + 1 ) == $ix ) {

        # we can reuse the group... same vtable
        $group->{to}++;
    }
    else {
        # purge the previous group
        $self->_add_pvmg_group();

        $group->{vtable} = $vtable;
        $group->{from}   = $ix;
        $group->{to}     = $ix;
    }

    return;
}

=pod

_add_pvmg_group:

used by flush to render the C lines and for loop
from all previous calls to 'add_pvmg'

=cut

sub _add_pvmg_group ($self) {

    my $group = $self->{group};
    return unless ref $group && defined $group->{vtable};

    #print STDERR "_add_pvmg_group... $group->{vtable} || $group->{from} -> $group->{to} \n";

    if ( $group->{from} == $group->{to} ) {

        $self->sadd( 'magic_list[%d].mg_virtual = (MGVTBL*) &PL_vtbl_%s;', $group->{from}, $group->{vtable} );
    }
    else {
        $self->sadd( <<'EOS', $group->{from}, $group->{to}, $group->{vtable} );

	for (i=%d; i<=%d; ++i) {
		magic_list[i].mg_virtual = (MGVTBL*) &PL_vtbl_%s;
	}
EOS
    }

    return;
}

# flush the last group
sub flush ($self) {

    # only flush once
    return $self if $self->{_flushed};
    $self->{_flushed} = 1;

    $self->_add_pvmg_group();

    return $self;    # can chain like flush.output
}

1;
