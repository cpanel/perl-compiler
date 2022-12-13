package B::C::Hooks;

use B::C::Std;

use B::C::Debug ();

sub new ( $class, %opts ) {

    my $self = bless {}, $class;

    $self->_load_hooks();

    return $self;

}

sub _dd ($str) {
    return B::C::Debug::debug( 'hooks' => $str );
}

sub _load_hooks ($self) {

    # this is where you want to load your hooks
    return unless eval { require B::C::Hooks::Loader; 1 };

    foreach my $k ( sort keys %INC ) {
        next unless $k =~ qr{^B/C/Hooks/([^/]+)\.pm$};
        my $hook = $1;
        next if $hook eq 'Loader';    # loader entry point
        next if $hook eq 'Base';      # this is the base class

        my $pkg = "B::C::Hooks::$hook";

        _dd("detecting B::C hook '$hook'");

        $self->{hooks} //= [];
        push $self->{hooks}->@*, $pkg->new();
    }

    return;
}

sub _hooks ($self) {
    return ( $self->{hooks} // [] );
}

=pod

=head2 pre_write( $self, %opts )

Call the 'pre_write' hook on all loaded hooks.
This is happening before we start generating the stash.

This is a good time to alter section contents before we generate the stash.

=cut

sub pre_write ( $self, %opts ) {
    return $self->_visit( 'pre_write', %opts );
}

=pod

=head2 pre_process( $self, %opts )

Call the 'pre_process' hook on all loaded hooks.
This is happening before we render the template.

Provided option:
 - stash: access to the stash

=cut

sub pre_process ( $self, %opts ) {

    # init the hooks entry in our main stasg
    my $global_stash = $opts{stash}->{hooks} = {};

    $opts{post_visit} = sub ($hook) {

        return unless my $hook_stash = $hook->get_stash;

        foreach my $k ( keys %$hook_stash ) {
            $global_stash->{$k} //= '';
            $global_stash->{$k} .= sprintf( "\n/* %s - %s */\n", ref $hook, $k );
            $global_stash->{$k} .= $hook_stash->{$k};
        }

        return;
    };

    return $self->_visit( 'pre_process', %opts );
}

=pod

=head2 post_process( $self, %opts )

Call the 'post_process' hook on all loaded hooks.
This is happening after processing the template.

Provided option:
 - c_file_name: name of the temporary file to generate the c code.

=cut

sub post_process ( $self, %opts ) {
    return $self->_visit( 'post_process', %opts );
}

sub _visit ( $self, $method, %opts ) {

    foreach my $hook ( $self->_hooks->@* ) {
        next unless my $sub = $hook->can($method);

        my $post_visit = delete $opts{post_visit};

        $hook->debug("calling hook '$method'");
        $sub->( $hook, %opts );

        if ($post_visit) {
            $post_visit->($hook);
        }
    }

    return;
}

1;
