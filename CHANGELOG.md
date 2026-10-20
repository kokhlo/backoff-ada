# Changelog

## 0.3.0 (2026-10-20)

Breaking / behavior changes:

- **`Initialize` no longer takes a `Jitter` parameter.** It never had an
  effect: the jitter mode is the discriminant of `Backoff_Config` and a
  limited record's discriminant is fixed at declaration. Code that passed
  `Jitter => ...` explicitly will not compile until the actual is removed
  (the mode already came from the discriminant, so runtime behavior is
  unchanged for such callers).

Fixes:

- **Static linking by default.** The library was built as a dynamic
  library whose macOS consumers crashed at load time with duplicate
  `LC_RPATH` entries (a known GNAT ≤ 14.2 toolchain issue). The project
  now builds static, so `alr with backoff` consumers link the objects
  in directly and run without rpath setup.
- **Invalid configuration is now rejected** with `Constraint_Error`
  (descriptive message) instead of silently producing negative or zero
  delays: `Initial_Interval <= 0`, `Multiplier < 1`,
  `Randomization_Factor` outside `[0, 1]`, `Max_Interval <= 0`,
  `Max_Interval < Initial_Interval`, `Max_Elapsed_Time < 0`.
  Checked in `Initialize`/`Reset` and re-checked in `Next_Back_Off`
  (hand-mutated fields cannot bypass validation). Previously a negative
  initial interval or a factor > 1 yielded **negative** delays that
  callers would feed to `delay`.
- **`Max_Elapsed_Time = 0.0` now means "no time limit"** (matching
  cenkalti/backoff) instead of stopping on the first call.
- **A delay of `0.0` is no longer treated as a stop signal by
  `Retry_Loop`.** Full jitter legitimately draws `0.0` ("retry
  immediately"); the loop now stops only on elapsed-time exhaustion.
  New function `Elapsed_Exceeded (B)` disambiguates the stop condition.
- **Overflow-safe interval advance** (defensive hardening): the cap is
  decided in divisor space before multiplying, so `Current * Multiplier`
  cannot overflow to `Infinity` on the way to the cap. Behavior is
  identical under IEEE floats; the guard matters for `-gnato` builds and
  non-IEEE targets.

Additions:

- `Elapsed_Exceeded` function (see above).

Infrastructure:

- Library now compiles warning-free with `-gnatwa` (project names in
  `backoff.gpr`/`backoff_tests.gpr` aligned with file names).
- CI: build+test matrix (Linux/macOS × GNAT 14.2.1/16.1.0) plus an
  `alr with --use` consumer check; release workflow with tag/version
  consistency enforcement and source archive.
- `CONTRIBUTING.md` added.
- Test suite grew from 18 to 39 assertions, covering validation,
  zero-limit semantics, stop-vs-zero-delay, overflow and reset.

## 0.2.0 (2026-10-12)

- Renamed project files to `backoff.gpr`/`backoff_tests.gpr` as expected
  by the alire-index entry (crate `backoff`).

## 0.1.0 (2026-08-29)

- Initial release: exponential backoff with None/Decorrelated/Full
  jitter, callback-based generic retry loop, deterministic jitter
  testing via `Next_Interval_After`.
