# backoff-ada

[![CI](https://github.com/kokhlo/backoff-ada/actions/workflows/build-test.yml/badge.svg)](https://github.com/kokhlo/backoff-ada/actions/workflows/build-test.yml)
[![Alire](https://img.shields.io/badge/alire-0.3.0-blue.svg)](https://alire.ada.dev)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Exponential backoff with jitter and retry for Ada. Inspired by [cenkalti/backoff](https://github.com/cenkalti/backoff) (Go, 3k⭐).

## What / Why

Resilient network clients and distributed systems need exponential backoff to handle transient failures gracefully. This library provides:

- **Exponential backoff** with configurable initial interval, multiplier, and max interval
- **Jitter modes**: None (deterministic), Decorrelated (AWS-style ±factor), Full (uniform [0, x])
- **Max elapsed time** to bound total retry duration (0.0 = no limit)
- **Validated configuration**: invalid values raise `Constraint_Error` with a descriptive message
- **Generic retry loop** with callback-based progress tracking
- **Deterministic testability**: inject random seeds for reproducible jitter tests

## Installation

With [Alire](https://alire.ada.dev):

```bash
alr with backoff
```

Available in the community index since 0.2.0 (`index/ba/backoff/`). To pin a local checkout instead: `alr with backoff --use /path/to/backoff-ada`.

## Usage

### Basic backoff sequence

```ada
with Backoff; use Backoff;

procedure Example is
   Config : Backoff_Config (Jitter => Decorrelated);
   Delay_Val : Duration;
begin
   Initialize (Config,
               Initial_Interval => 0.500,    -- 500ms
               Multiplier => 1.5,
               Max_Interval => 60.0,         -- 60 seconds
               Max_Elapsed_Time => 900.0);   -- 15 minutes; 0.0 = no limit

   loop
      exit when Elapsed_Exceeded (Config);
      Delay_Val := Next_Back_Off (Config);

      delay Standard.Duration (Delay_Val);
      --  Retry your operation here
   end loop;
end Example;
```

> Note: the jitter mode is the **discriminant** of `Backoff_Config`, fixed at
> declaration — `Initialize` has no `Jitter` parameter (0.3.0 removed the
> dead parameter that silently did nothing).

### Retry helper

```ada
with Ada.Text_IO; use Ada.Text_IO;
with Backoff; use Backoff;
with Backoff.Retry;

procedure Retry_Example is
   Config : Backoff_Config (Jitter => Full);
   Success : Boolean;

   function Attempt_Operation return Boolean is
   begin
      --  Your operation here (returns True on success)
      return False;
   end Attempt_Operation;

   procedure On_Failure (Attempt : Positive; Delay_For : Duration) is
   begin
      Put_Line ("Attempt" & Positive'Image(Attempt) &
                " failed, waiting" & Duration'Image(Delay_For) & "s");
      delay Standard.Duration (Delay_For);
   end On_Failure;

   procedure Retry_Op is new Backoff.Retry.Retry_Loop
     (Op => Attempt_Operation,
      Max_Attempts => 5,
      On_Failure => On_Failure);

begin
   Initialize (Config);
   Retry_Op (Config, Success);

   if Success then
      Put_Line ("Operation succeeded");
   else
      Put_Line ("All attempts exhausted");
   end if;
end Retry_Example;
```

A `Delay_For` of `0.0` from `On_Failure` is a legitimate "retry immediately"
draw (Full jitter), not a stop; the loop stops only when the elapsed-time
budget runs out or attempts are exhausted.

## Design Choices

### Limited record for state

`Backoff_Config` is a `limited record` (single-task use). Caller owns concurrency — spawn multiple tasks with separate configs if needed. This keeps the API simple and avoids protected-object overhead for single-threaded clients.

### Validated configuration

`Initialize`, `Reset` and `Next_Back_Off` validate the configuration and raise `Constraint_Error` (with a message naming the field) for `Initial_Interval <= 0`, `Multiplier < 1`, `Randomization_Factor` outside `[0, 1]`, `Max_Interval <= 0`, `Max_Interval < Initial_Interval`, or `Max_Elapsed_Time < 0`. Before 0.3.0 such configs silently produced negative delays that callers fed to `delay`.

### Deterministic jitter testing

`Next_Interval_After` is a pure function that accepts an explicit `Random_Seed` parameter (Float in [0.0, 1.0]). Tests verify jitter bounds by calling with seed=0.0 (min) and seed=1.0 (max), without advancing RNG state. This decouples the jitter computation from side effects.

### Retry callback pattern

`Retry_Loop` is a generic procedure that takes an operation function and a failure callback. The callback receives the attempt count and the delay duration, letting the caller decide how to wait (actual `delay`, logging, or inject fake time in tests). No exceptions for control flow — the `Success` out parameter indicates whether the operation succeeded.

## Defaults

Matches cenkalti/backoff Go defaults:

- Initial interval: 500ms
- Randomization factor: 0.5 (decorrelated jitter: multiplier in [0.5x, 1.5x])
- Multiplier: 1.5
- Max interval: 60 seconds
- Max elapsed time: 15 minutes (0.0 = no limit)

## Niche Status

`backoff` was the first backoff/retry library published for Ada (since 0.2.0 in the community index).

## Roadmap

- [x] Core backoff state machine
- [x] Jitter modes (None, Decorrelated, Full)
- [x] Generic retry loop
- [x] Tests: exact sequence, capping, elapsed time, jitter bounds, retry scenarios
- [x] Publish to alire-index at github.com/kokhlo/backoff-ada
- [ ] Integration example: redis-ada reconnect with exponential backoff
- [ ] Adaptive jitter (measure actual server load)

See [CHANGELOG.md](CHANGELOG.md) for release history.

## License

MIT License — see [LICENSE](LICENSE)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
