package B::C::Hooks::Loader;

=pod

This package a place hodler.

This is used to declare your custom hooks.
B::C loads 'B::C::Hooks::Loader' and then
register all Hooks loaded.

Overwrite it and load your custom hooks.

	use B::C::Hooks::MyFirstHook  ();
	use B::C::Hooks::MySecondHook ();

=cut

1;
