# Contributing to backoff-ada

Thanks for considering a contribution.

## Getting started

You need an Ada toolchain. The easiest path is [Alire](https://alire.ada.dev):

```bash
alr toolchain --select --disable-assistant gnat_native=14.2.1 gprbuild=25.0.1
```

Build and test:

```bash
alr build                    # library
gprbuild -p -P backoff_tests.gpr
./bin/backoff-tests          # full suite, exit 0 = all passed
```

No server or network is needed; the suite is fully deterministic
(jitter bounds are verified through `Next_Interval_After` with explicit
seeds, not by sampling).

## What CI runs

Every push and PR builds the library and tests on Linux and macOS across
GNAT 14.2 and 16.1, warning-free (`-gnatwa` is in both project files).
The `alire-check` job builds a dependent crate pinned to your checkout —
keep `alire.toml` and `backoff.gpr` consumable. A PR is not done until
CI is green.

## Ground rules

- **Build must be warning-free.** Both the library and the test project
  compile with `-gnatwa`. Do not silence new warnings with pragmas — fix
  the cause.
- **Tests are required for behavior changes.** The suite is a plain Ada
  program (`test/backoff-tests.adb`) with its own `Assert`. Add a focused
  test next to the behavior you change; keep it deterministic (inject
  seeds / pass explicit values, never sample-and-hope).
- **Validation belongs in `Initialize`/`Reset`/`Next_Back_Off`.** Every
  state transition re-checks the configuration so hand-mutated fields
  cannot bypass it. If you add a config field, add it to `Validate` and
  to the invalid-config test.
- **`0.0` from `Next_Back_Off` is ambiguous by design** — it is the
  stop signal *and* a legitimate Full-jitter draw. Use `Elapsed_Exceeded`
  to disambiguate; do not compare delays against `0.0` for control flow.
- **Conventional commits** (`fix:`, `feat:`, `docs:`, `chore:`), one
  logical change per commit. Version lives in `alire.toml` and the README
  badge — the release workflow enforces they match the tag.

## Releasing (maintainers)

1. Bump `version` in `alire.toml` and the alire badge in `README.md`.
2. Add a `CHANGELOG.md` entry.
3. Commit, tag `vX.Y.Z`, push the tag. The `release` workflow verifies
   the tag against `alire.toml` and the README badge, rebuilds, runs the
   suite, and publishes a source archive + sha512 to GitHub Releases.
4. Submit the matching crate to alire-index (`index/ba/backoff/`).
