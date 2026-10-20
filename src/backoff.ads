--  Backoff.Ada: Exponential backoff with jitter and retry for Ada.
--  Inspired by cenkalti/backoff (Go) with deterministic testability.
--
--  Design choices:
--    - Backoff is a limited record (single-task use; caller owns concurrency).
--    - Jitter mode is a discriminant fixed at declaration; it selects the
--      interval math and cannot be changed later (a limited record's
--      discriminant is immutable after the object is declared).
--    - Jitter modes: None (deterministic), Decorrelated (AWS-style: ±factor),
--                    Full (uniform in [0, current]).
--    - Next_Interval_After is a pure function for testing jitter bounds without
--      advancing state; inject Random_Seed for deterministic results.
--    - Next_Back_Off advances state and returns 0.0 when Max_Elapsed_Time
--      is exceeded (Max_Elapsed_Time = 0.0 means no time limit).
--    - Retry loops with callback; no exceptions for control flow.
--
--  Contracts (since 0.3.0):
--    - Invalid configuration raises Constraint_Error with a descriptive
--      message: Initial_Interval <= 0, Multiplier < 1, Randomization_Factor
--      outside [0, 1], Max_Interval <= 0, Max_Interval < Initial_Interval,
--      or Max_Elapsed_Time < 0. Checked by Initialize/Reset and defensively
--      re-checked by Next_Back_Off (hand-mutated fields do not bypass
--      validation).
--    - A delay of 0.0 returned by Full jitter is a legitimate
--      "retry immediately" hint, not a stop signal. Stop is signalled only
--      by Max_Elapsed_Time exhaustion; query it with Elapsed_Exceeded.

pragma Warnings (Off, "*header present*");
with Ada.Calendar;    use Ada.Calendar;
with Ada.Numerics.Float_Random;

package Backoff is

   --  Duration type (seconds as Float for sub-millisecond granularity).
   subtype Duration is Float;

   --  Jitter modes for randomized backoff intervals.
   type Jitter_Mode is (None, Decorrelated, Full);
   --  None: deterministic, no randomness.
   --  Decorrelated: current * random in [1-factor, 1+factor] (AWS/jittered).
   --  Full: uniform in [0, current] (expovar with φ=0).

   --  Default constants (match cenkalti/backoff Go defaults).
   Default_Initial_Interval   : constant Duration := 0.500;   -- 500 ms
   Default_Randomization_Factor : constant Duration := 0.500; -- ±50%
   Default_Multiplier         : Duration := 1.500;       -- 1.5x
   Default_Max_Interval       : constant Duration := 60.000;  -- 60 seconds
   Default_Max_Elapsed_Time   : constant Duration := 900.000; -- 15 minutes

   --  Backoff state (limited record: single-task use, caller manages
   --  concurrency). The Jitter discriminant selects the jitter mode and
   --  is fixed for the lifetime of the object.
   type Backoff_Config (Jitter : Jitter_Mode := Decorrelated) is limited record
      Initial_Interval     : Duration := Default_Initial_Interval;
      Randomization_Factor : Duration := Default_Randomization_Factor;
      Multiplier           : Duration := Default_Multiplier;
      Max_Interval         : Duration := Default_Max_Interval;
      Max_Elapsed_Time     : Duration := Default_Max_Elapsed_Time;

      --  Internal state (advanced by Next_Back_Off).
      Current_Interval   : Duration := Default_Initial_Interval;
      Start_Time         : Time := Clock;
      Rand_Gen           : Ada.Numerics.Float_Random.Generator;
   end record;

   --  Initialize a backoff configuration with custom settings.
   --  The jitter mode is NOT a parameter: it is fixed by the discriminant
   --  of the declaration. Passing Jitter => ... to Initialize has never had
   --  an effect (and the parameter is gone since 0.3.0).
   --  Raises Constraint_Error for invalid values (see package contracts).
   procedure Initialize
     (B : in out Backoff_Config;
      Initial_Interval      : Duration := Default_Initial_Interval;
      Randomization_Factor  : Duration := Default_Randomization_Factor;
      Multiplier            : Duration := Default_Multiplier;
      Max_Interval          : Duration := Default_Max_Interval;
      Max_Elapsed_Time      : Duration := Default_Max_Elapsed_Time);

   --  Reset backoff state (current interval and start time).
   --  Raises Constraint_Error if the stored configuration is invalid.
   procedure Reset (B : in out Backoff_Config);

   --  True when Max_Elapsed_Time has been exceeded since the last
   --  Initialize/Reset. Max_Elapsed_Time = 0.0 means "never" (no limit),
   --  matching cenkalti/backoff. This is the only stop signal; a 0.0
   --  delay from Full jitter is NOT a stop.
   function Elapsed_Exceeded (B : Backoff_Config) return Boolean;

   --  Get the next backoff interval with jitter applied.
   --  Returns 0.0 when Max_Elapsed_Time is exceeded (stop retrying);
   --  distinguish exhaustion from a legitimate zero delay with
   --  Elapsed_Exceeded. Raises Constraint_Error on invalid configuration.
   function Next_Back_Off (B : in out Backoff_Config) return Duration;

   --  Pure function: compute next interval given a current base and random seed.
   --  Does NOT advance state; used for deterministic jitter bounds testing.
   --  When Jitter = None, returns Base directly.
   --  When Jitter = Decorrelated: returns Base * Random in [1-factor, 1+factor].
   --  When Jitter = Full: returns uniform random in [0, Base].
   --  Random_Seed: any Float in [0.0, 1.0] acts as the random value.
   --  Raises Constraint_Error if Base <= 0 or Random_Factor outside [0, 1].
   function Next_Interval_After
     (Base        : Duration;
      Jitter      : Jitter_Mode;
      Random_Factor : Duration := Default_Randomization_Factor;
      Random_Seed : Duration := 0.0) return Duration;

end Backoff;
