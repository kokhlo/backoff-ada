--  Backoff.Ada: Exponential backoff with jitter and retry for Ada.
--  Inspired by cenkalti/backoff (Go) with deterministic testability.
--
--  Design choices:
--    - Backoff is a limited record (single-task use; caller owns concurrency).
--    - Jitter modes: None (deterministic), Decorrelated (AWS-style: ±factor),
--                    Full (uniform in [0, current]).
--    - Next_Interval_After is a pure function for testing jitter bounds without
--      advancing state; inject Random_Seed for deterministic results.
--    - Next_Back_Off advances state and returns 0.0 when MaxElapsedTime exceeded.
--    - Retry loops with callback; no exceptions for control flow.

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
   Default_Multiplier         : constant Duration := 1.500;   -- 1.5x
   Default_Max_Interval       : constant Duration := 60.000; -- 60 seconds
   Default_Max_Elapsed_Time   : constant Duration := 900.000; -- 15 minutes

   --  Backoff state (limited record: single-task use, caller manages concurrency).
   type Backoff_Config (Jitter : Jitter_Mode := Decorrelated) is limited record
      Initial_Interval   : Duration := Default_Initial_Interval;
      Randomization_Factor : Duration := Default_Randomization_Factor;
      Multiplier         : Duration := Default_Multiplier;
      Max_Interval       : Duration := Default_Max_Interval;
      Max_Elapsed_Time   : Duration := Default_Max_Elapsed_Time;

      --  Internal state (advanced by Next_Back_Off).
      Current_Interval   : Duration := Default_Initial_Interval;
      Start_Time         : Time := Clock;
      Rand_Gen           : Ada.Numerics.Float_Random.Generator;
   end record;

   --  Initialize a backoff configuration with custom settings.
   procedure Initialize
     (B : in out Backoff_Config;
      Initial_Interval    : Duration := Default_Initial_Interval;
      Randomization_Factor  : Duration := Default_Randomization_Factor;
      Multiplier          : Duration := Default_Multiplier;
      Max_Interval        : Duration := Default_Max_Interval;
      Max_Elapsed_Time    : Duration := Default_Max_Elapsed_Time;
      Jitter              : Jitter_Mode := Decorrelated);

   --  Reset backoff state (current interval and start time).
   procedure Reset (B : in out Backoff_Config);

   --  Get the next backoff interval with jitter applied.
   --  Returns 0.0 when Max_Elapsed_Time is exceeded (stop retrying).
   function Next_Back_Off (B : in out Backoff_Config) return Duration;

   --  Pure function: compute next interval given a current base and random seed.
   --  Does NOT advance state; used for deterministic jitter bounds testing.
   --  When Jitter = None, returns Base directly.
   --  When Jitter = Decorrelated: returns Base * Random in [1-factor, 1+factor].
   --  When Jitter = Full: returns uniform random in [0, Base].
   --  Random_Seed: any Float in [0.0, 1.0] acts as the random value.
   function Next_Interval_After
     (Base        : Duration;
      Jitter      : Jitter_Mode;
      Random_Factor : Duration := Default_Randomization_Factor;
      Random_Seed : Duration := 0.0) return Duration;

end Backoff;