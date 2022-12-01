package B::C::Hooks::Base;

use B::C::Std;
use B::C::Debug ();

sub new ( $class, %opts ) {

    return bless {}, $class;
}

sub debug ( $self, $str ) {
    return B::C::Debug::debug( 'hooks' => ref($self) . ' ' . $str );
}

sub stash ( $self, $k, $v ) {

    $self->{stash} //= {};
    $self->{stash}->{$k} = $v;

    return;
}

sub get_stash ($self) {
    return $self->{stash};
}

1;
