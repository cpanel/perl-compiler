# B::C Perl Compiler — Copilot Instructions

## What This Project Is

B::C is a Perl-to-C compiler backend. It compiles Perl programs into C source code, which is then compiled into standalone executables. The main entry point is `perlcc` (generated from `script/perlcc.PL`). Each git branch targets a specific Perl version (current branch: `bc542` for Perl 5.42).

## Build & Test

```sh
# Build and install (required before running tests)
perl Makefile.PL installdirs=vendor && make -j4 install
# Or use the shortcut:
./configure.cpanel

# Run the full compiled test suite (uses cprove wrapper around prove)
./cprove -j4 t/testsuite/C-COMPILED/*/*.t
# Or: ./cprove --all

# Run a single compiled test by short name
./cprove op/my.t
./cprove -v extra/const-array.t

# Run a single unit test directly
prove -b -v t/B-C-InitSection.t

# Run uncompiled version of a test (for comparison)
./cprove -u -v op/my.t

# Rebuild B::C and run tests in one step
./cprove -c -v extra/*.t

# Run only known-broken tests
./cprove --errors

# Rerun failures with verbose
./cprove -j4 --rerun t/testsuite/t/*/*.t
```

Test files under `t/testsuite/C-COMPILED/` are compiled Perl core tests. Known failures are tracked in `t/testsuite/C-COMPILED/known_errors.txt`. Unit tests for B::C internals live directly in `t/` (e.g., `t/B-C-Section.t`).

## Architecture

### Compilation Pipeline

1. Perl parses the input program and builds an op tree
2. `B::C` walks the op tree via `B::C::OverLoad::B::*` modules (one per SV/OP type)
3. Each node's `save` method emits C code into `B::C::Section` objects
4. `B::C::File` renders the final `.c` file using Template Toolkit (`lib/B/C/Templates/base.c.tt2`)
5. `cc_harness` compiles the generated C into an executable

### Key Module Roles

- **`lib/B/C.pm`** + **`lib/B/C_heavy.pl`** — Main compiler entry point and heavy lifting. `C.pm` is loaded by `perl -MO=C`, then loads `C_heavy.pl`.
- **`lib/B/C/OverLoad/B/*.pm`** — One module per Perl internal type (AV, HV, GV, CV, OP, COP, etc.). Each overloads `B::TYPE::save` to generate C code for that type.
- **`lib/B/C/OP.pm`** — Provides `save_constructor()` which builds the cached save dispatchers for all OP types.
- **`lib/B/C/File.pm`** — Singleton responsible for rendering the final C file. Manages all `B::C::Section` instances.
- **`lib/B/C/Section.pm`** / **`lib/B/C/InitSection.pm`** — Accumulate C code fragments (declarations, initializations) during the tree walk.
- **`lib/B/C/Save.pm`** — Handles COW (copy-on-write) PV string saving and deduplication.
- **`lib/B/C/Helpers.pm`** — Utility functions for C string encoding, GV memorization, and symbol management.
- **`lib/B/C/Helpers/Symtable.pm`** — Symbol table mapping Perl objects to their C variable names (`savesym`/`objsym`).
- **`lib/B/C/Flags.pm`** — Auto-generated at build time by `Makefile.PL`. Contains Config values and build metadata.
- **`lib/B/C/Std.pm`** — Imported by most modules; enables `feature ':5.42'`.
- **`C.xs`** — XS extensions providing fast access to Perl internals (SV types, flags, etc.).

### Test Infrastructure

- **`cprove`** — Perl wrapper around `App::Prove` that handles test compilation, known-error filtering, and blacklisting. Supports compiled (`-c`) and uncompiled (`-u`) modes.
- **`dprove`** — Runs both uncompiled and compiled versions of a test for comparison.
- **`t/testsuite/`** — Contains the Perl core test suite, with `C-COMPILED/` holding the compiled variants.

## Conventions

- Modules use `B::C::Std` instead of `use feature` directly (it handles a bootstrap edge case with `feature.pm`).
- Perl 5.42 features are available: subroutine signatures (`sub foo ($bar) { ... }`) are used throughout.
- The `save` method pattern is central: every SV/OP type in `lib/B/C/OverLoad/B/` has a `save` method that returns a C symbol name and is cached via `savesym`/`objsym`.
- The OverLoad modules do not use `@ISA` inheritance — they inject `save` methods directly into `B::*` namespaces at load time.
- `B::C::File` is a singleton (initialized with `B::C::File::new()`, accessed via exported section accessors).
- Version numbers follow the pattern `5.PERLVERSION_XXX` (e.g., `5.042004`), tied to the target Perl version.
- CI runs in a cPanel Perl container via GitHub Actions (`.github/workflows/bc-testsuite.yml`).
- Windows/threads/multiplicity are explicitly unsupported. The code requires C99 and `dlfcn`/`dlopen`.
