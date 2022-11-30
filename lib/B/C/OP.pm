package B::C::OP;

use B::C::Std;

use B                       qw/SVf_ROK/;
use B::C::Helpers::Symtable qw/savesym objsym/;

my $last;
my $count;
my $_stack;

# We need to be sure that the SV that is saved is never re-used so we're going to increase
# its refcount by pointing to it here. This assures the SV is never freed when it goes out of scope.
# We need this when we use temp vars to save an SV with something other than its original content.

our @SAVED_OPS;

sub save_constructor ($for) {

    # we cannot trust the OP passed to know which call we should call
    #   we are hardcoding it using a constructor for save
    die unless $for;

    return sub ( $op, @args ) {

        # cache lookup
        {
            my $sym = objsym($op);
            return $sym if defined $sym;
        }

        # call the real save function and cache the return value{
        my $sym;

        local $^W = undef;    # avoid for warning 'Deep recursion on subroutine'

        if (0) {              # Debug for tracking save paths.
            my @save_info = @args;
            if ( !@save_info ) {
                foreach my $try (qw/ppname FULLNAME SAFENAME NAME_HEK name NAME/) {
                    my $got;
                    if ( $for->can($try) && ( $got = $for->can($try)->($op) ) ) {
                        push @save_info, $got;
                    }
                    last if @save_info >= 2;
                }
                push @save_info, '' while scalar @save_info < 2;
            }
            print STDERR sprintf( "%s save for %s, %s\n", $for || '?', $save_info[0] || '?', $save_info[1] || '?' );
        }
        eval { $sym = $for->can('do_save')->( $op, @args ); 1 }
          or die "$@\n:" . 'B::C::Save'->can('stack_flat')->();
        savesym( $op, $sym ) if defined $sym;

        if ( $sym && $sym =~ /sv_list/ && $op->isa('B::SV') ) {
            push @SAVED_OPS, $op->object_2svref();
        }

        return $sym;
    };

}

1;
