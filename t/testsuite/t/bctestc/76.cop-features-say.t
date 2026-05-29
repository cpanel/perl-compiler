#!./perl

# cop_features: verify that 'use feature "say"' is preserved in compiled output.
# Without proper cop_features serialization, 'say' silently loses its feature
# flag when the bundle is FEATURE_BUNDLE_CUSTOM.

use feature "say";

say "ok";
