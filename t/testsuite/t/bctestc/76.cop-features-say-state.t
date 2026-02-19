#!./perl

# cop_features: verify multiple custom feature flags survive compilation.

use feature "say", "state";

state $msg = "ok";
say $msg;
