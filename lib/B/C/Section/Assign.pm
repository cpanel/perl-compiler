package B::C::Section::Assign;

use B::C::Std;
use warnings;

# avoid use vars
our @ISA = qw/B::C::Section/;

sub new ( $class, @args ) {
    my $self = $class->SUPER::new(@args);
    return $self;
}

sub add ( $self, @args ) {    # for now simply perform a single add
    my $line = join ', ', @args;
    return $self->SUPER::add($line);
}

1;
