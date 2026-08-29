# backoff-ada

[![Alire](https://img.shields.io/badge/alire-0.1.0--dev-blue.svg)](https://alire.ada.dev)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Exponential backoff with jitter and retry for Ada. Inspired by [cenkalti/backoff](https://github.com/cenkalti/backoff) (Go, 3k⭐).

## What / Why

Resilient network clients and distributed systems need exponential backoff to handle transient failures gracefully. This library provides:

- **Exponential backoff** with configurable initial interval, multiplier, and max interval
- **Jitter modes**: None (deterministic), Decorrelated (AWS-style ±factor), Full (uniform [0, x])
- **Max elapsed time** to bound total retry duration
- **Generic retry loop** with callback-based progress tracking
- **Deterministic testability**: inject random seeds for reproducible jitter tests

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
               Max_Elapsed_Time => 900.0);   -- 15 minutes

   loop
      Delay_Val := Next_Back_Off (Config);
      exit when Delay_Val = 0.0;  -- Max elapsed time reached
      
      delay Standard.Duration (Delay_Val);
      --  Retry your operation here
   end loop;
end Example;
```

### Retry helper

```ada
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
   Initialize (Config, Jitter => Full);
   Retry_Op (Config, Success);
   
   if Success then
      Put_Line ("Operation succeeded");
   else
      Put_Line ("All attempts exhausted");
   end if;
end Retry_Example;
```

## Design Choices

### Limited record for state

`Backoff_Config` is a `limited record` (single-task use). Caller owns concurrency — spawn multiple tasks with separate configs if needed. This keeps the API simple and avoids protected-object overhead for single-threaded clients.

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
- Max elapsed time: 15 minutes

## Niche Status

As of 2026-08-29, `alr search backoff` and `alr search retry` return zero hits. This is the first backoff/retry library published for Ada.

## Roadmap

- [x] Core backoff state machine
- [x] Jitter modes (None, Decorrelated, Full)
- [x] Generic retry loop
- [x] Tests: exact sequence, capping, elapsed time, jitter bounds, retry scenarios
- [ ] Publish to alire-index at github.com/kokhlo/backoff-ada
- [ ] Integration example: redis-ada reconnect with exponential backoff
- [ ] Adaptive jitter (measure actual server load)

## License

MIT License — see [LICENSE](LICENSE)

## Contributing

PRs welcome. For major changes, open an issue first to discuss the design. Follow Ada Quality and Style Guide conventions.