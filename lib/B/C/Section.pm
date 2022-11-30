package B::C::Section;

use B::C::Std;

# use warnings
use B qw/SVf_FAKE/;

use B::C::Helpers::Symtable ();
my %sections;

sub BOOTSTRAP_marker {
    return q{BOOTSTRAP_XS_};
}

sub new ( $class, $section, $symtable, $default ) {

    my $self = bless {
        'name'     => $section,
        'symtable' => $symtable,
        'default'  => $default,
        'values'   => [],
        'c_header' => [],
    }, $class;
    $sections{$section} = $self;

    # if sv add a dummy sv_arenaroot to support global destruction
    if ( $section eq 'sv' ) {
        $self->add( "NULL, 0, SVTYPEMASK|" . SVf_FAKE . ", {0}" );
        $self->debug("PL_sv_arenaroot");
    }

    return $self;
}

sub has_values ($self) {

    return scalar @{ $self->{values} } >= 1 ? 1 : 0;
}

sub add ( $self, @list ) {

    my $add_stack = 'B::C::Save'->can('_caller_comment');
    if ( $list[-1] && ref $add_stack ) {
        my $add = $add_stack->();
        $list[-1] .= qq{\n} . $add if length $add;
    }
    push( @{ $self->{'values'} }, @list );

    # return its position in the list (first one will be 0), avoid to call index just after in most cases
    return $self->index();
}

sub reserve ( $self, $sv, $type = undef ) {

    $sv or die("Need a symbol");
    my $type_cast = $type ? "($type)" : '';

    my $caller_package = ( caller(0) )[0];
    $caller_package =~ s/^B:://;

    my $ix = $self->add("FAKE $caller_package");

    my $list_name = $self->{'name'} or die;

    # (OP*)&svop_list[5]"
    my $sym = sprintf( '%s&%s_list[%d]', $type_cast, $list_name, $ix );

    B::C::Helpers::Symtable::savesym( $sv, $sym );

    return ( $ix, $sym );
}

sub _convert_list_to_sprintf (@list) {

    my @patterns;
    my @args;

    die "saddl should be called with an even number of arguments" unless scalar @list % 2 == 0;

    while ( my ( $k, $v ) = splice( @list, 0, 2 ) ) {
        push @patterns, $k;
        if ( ref $v eq 'ARRAY' ) {
            push @args, @$v;
        }
        else {
            push @args, $v;
        }
    }
    my $pattern = join( ', ', @patterns );

    return sprintf( $pattern, @args );
}

sub sort ($self) {    # used by shared_HE

    my %line_to_int;
    foreach my $l ( @{ $self->{'values'} } ) {
        my $v = $l =~ qr{([0-9]+)} ? $1 : 0;
        $line_to_int{$l} = $v;
    }

    my @sorted = sort { $line_to_int{$a} <=> $line_to_int{$b} } @{ $self->{'values'} };

    $self->{'values'} = \@sorted;

    return;
}

# simple add using sprintf: avoid boilerplates
# ex: sadd( "%d, %s", 1234, q{abcd} )
sub sadd ( $self, $pattern, @args ) {
    return $self->add( sprintf( $pattern, @args ) );
}

# simple add using sprintf using input formatted as a list
# ex: saddl( "%d" => 1234, "%s" => q{abcd} )
sub saddl ( $self, @list ) {
    return $self->add( _convert_list_to_sprintf(@list) );
}

# simple update using sprintf: avoid boilerplates
# ex: supdate( 1, "%d, %s", 1234, q{str} )
sub supdate ( $self, $row, $pattern, @args ) {
    return $self->update( $row, sprintf( $pattern, @args ) );
}

# simple update using sprintf using input formatted as a list
# ex: supdatel( 1, "%d" => 1234, "%s" => q{str} )
sub supdatel ( $self, $row, @list ) {
    return $self->update( $row, _convert_list_to_sprintf(@list) );
}

sub update ( $self, $row, $value ) {

    die "Element does not exists" if $row > $self->index;

    $self->{'values'}->[$row] = $value;

    return;
}

sub supdate_field ( $self, $row, $field, $pattern, @args ) {
    return $self->update_field( $row, $field, sprintf( $pattern, @args ) );
}

=pod

update_field: update a single value from an existing line

=cut

sub update_field ( $self, $row, $field, $value ) {

    die "Need to call with row, field, value" unless defined $value;

    my $line   = $self->get($row);
    my @fields = _field_split($line);    # does not handle comma in comments

    die "Invalid field id $field" if $field > $#fields;
    $fields[$field] = $value;
    $line = join ',', @fields;           # update line

    return $self->update( $row, $line );
}

sub _field_split ($to_split) {

    my @list = split( ',', $to_split );
    my @ok;
    my ( $count_open, $count_close );
    my $str;
    my $reset = sub { $str = '', $count_open = $count_close = 0 };
    $reset->();
    foreach my $next (@list) {
        $str .= ',' if length $str;
        $str .= $next;
        my $snext = $next;
        $snext =~ s{"[^"]+"}{""}g;    # remove weird content inside double quotes
        $count_open  += $snext =~ tr/(//;
        $count_close += $snext =~ tr/)//;

        #warn "$count_open vs $count_close: $str";
        if ( $count_close == $count_open ) {
            push @ok, $str;
            $reset->();
        }
    }
    die "Cannot split correctly '$to_split' (some leftover='$str')" if length $str;

    return @ok;
}

sub get ( $self, $row = undef ) {

    $row = $self->index if !defined $row;    # get the last entry if not set

    return $self->{'values'}->[$row];
}

sub get_bootstrapsub_rows ($self) {

    my $bs_rows = {};

    my $ix = -1;
    foreach my $v ( @{ $self->{'values'} } ) {
        ++$ix;
        if ( $v =~ qr{BOOTSTRAP_XS_\Q[[\E(.+?)\Q]]\E_XS_BOOTSTRAP} ) {
            my $bs = $1;
            $bs_rows->{$bs} //= [];
            push @{ $bs_rows->{$bs} }, $ix;
        }
    }

    return $bs_rows;
}

sub get_field ( $self, $row, $field ) {

    die "Need to call with row, field" unless defined $field;

    my $line   = $self->get($row);
    my @fields = _field_split($line);    # does not handle comma in comments

    die "Invalid field id $field" if $field > $#fields;

    return $fields[$field];
}

sub get_fields ( $self, $row = undef ) {

    my $line = $self->get($row);
    return split( qr/\s*,\s*/, $line );
}

sub remove ($self) {    # should be rename pop or remove last
    return pop @{ $self->{'values'} };
}

sub name ($self) {
    return $self->{'name'};
}

sub symtable ($self) {
    return $self->{'symtable'};
}

sub default ($self) {
    return $self->{'default'};
}

sub index ($self) {

    return scalar( @{ $self->{'values'} } ) - 1;
}

sub typename ($self) {

    my $name     = $self->name;
    my $typename = uc($name);
    $typename = 'UNOP_AUX'           if $typename eq 'UNOPAUX';
    $typename = 'MyPADNAME'          if $typename eq 'PADNAME';
    $typename = 'SHARED_HE'          if $typename eq 'SHAREDHE';
    $typename = 'STATIC_MEMORY_AREA' if $typename eq 'MALLOC';

    return $typename;
}

sub comment_for_op ( $self, @comments ) {

    return $self->comment( B::OP::basop_comment(), ', ', @comments );
}

sub comment ( $self, @comments ) {

    @comments = grep { defined $_ } @comments;
    $self->{'comment'} = join( "", @comments ) if @comments;

    return $self->{'comment'};
}

# add debugging info - stringified flags on -DF
my $debug_flags;

sub add_extra_comments {
    return 1;    # always on for now
                 # maybe use another standard flag ? - debug('flags')
                 #return $ENV{BC_DEVELOPING};
}

sub debug ( $self, @what ) {

    # disable the sub when unused
    if ( !$self->add_extra_comments ) {

        # Scoped no warnings without loading the module.
        local $^W;
        BEGIN { ${^WARNING_BITS} = 0; }
        *debug = sub { };
        return;
    }

    # build our debug line for the current index

    my $str;
    my $dbg = scalar @what ? '' : 'undef';
    foreach my $e (@what) {
        do { $str = 'undef'; next } unless defined $e;
        $str = ref($e) || $e;
    }
    continue {
        $dbg .= ', ' if length $dbg;
        $dbg .= $str;
    }

    my $ix = $self->index;
    if ( defined $self->{'dbg'}->[$ix] ) {
        $self->{'dbg'}->[$ix] .= ', ' . $dbg;
    }
    else {
        $self->{'dbg'}->[$ix] = $dbg;
    }

    return $self->{'dbg'}->[$ix];
}

sub add_c_header ( $self, @headers ) {
    push @{ $self->{'c_header'} }, @headers;
    return;
}

sub output ( $self, $format ) {

    # weird things would occur if we call the output more than once
    die ref($self) . " output should only be called once" if $self->{_output_called};
    $self->{_output_called} = 1;

    my $sym     = $self->symtable;    # This should always be defined. see new
    my $default = $self->default;

    my $i = 0;

    if ( $self->name eq 'sv' ) {      # fixup arenaroot refcnt
        my $len = scalar @{ $self->{'values'} };
        $self->{'values'}->[0] =~ s/^NULL, 0/NULL, $len/;
    }

    my $comment = $self->comment;

    my $output = '';

    # check if the format already provide a closing comment
    my $wrap_debug_with_comment = $format =~ qr{\Q*/\E\s+$} ? 0 : 1;

    foreach my $i ( @{ $self->{'c_header'} } ) {
        $output .= "    $i\n";
    }

    foreach ( @{ $self->{'values'} } ) {
        my $val = $_;    # Copy so we don't overwrite on successive calls.
        my $dbg = "";
        my $ref = "";

        if ( $self->add_extra_comments() && defined $comment && $i % 10 == 0 ) {

            # every 10 lines add the comment header so we can easily read it
            $output .= qq{\n} if $i;
            $output .= qq{\t/* } . $comment . qq{ */\n\n};

        }

        $val =~ s{(s\\_[0-9a-f]+)}{ exists($sym->{$1}) ? $sym->{$1} : $default; }ge;
        if ( defined $self->{'dbg'}->[$i] ) {
            $dbg = $self->{'dbg'}->[$i] . " " . $ref;
            if ($wrap_debug_with_comment) {
                $dbg = " /* " . $dbg . " */";
            }
            else {
                $dbg = '- ' . $dbg;
            }

        }

        $val =~ s{BOOTSTRAP_XS_\Q[[\E.+?\Q]]\E_XS_BOOTSTRAP}{0};

        {
            # Scoped no warnings without loading the module.
            local $^W;
            BEGIN { ${^WARNING_BITS} = 0; }
            $output .= sprintf( $format, $val, $self->name, $i, $ref, $dbg );
        }

        ++$i;
    }

    return $output;
}

1;
