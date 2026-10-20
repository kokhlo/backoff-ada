--  Backoff.Ada implementation.
--
--  Deterministic testability:
--    - Next_Interval_After accepts a Random_Seed (Float in [0.0, 1.0]) to
--      compute jittered intervals without advancing RNG state.
--    - Tests verify jitter bounds by calling with seed = 0.0 (min) and 1.0 (max).

with Ada.Exceptions; use Ada.Exceptions;

package body Backoff is

   --  Validation shared by Initialize, Reset and Next_Back_Off.
   --  Hand-mutating record fields cannot bypass this: every state
   --  transition re-checks before computing.
   procedure Validate (B : Backoff_Config) is
   begin
      if B.Initial_Interval <= 0.0 then
         Raise_Exception
           (Constraint_Error'Identity,
            "backoff: Initial_Interval must be > 0, got "
            & Duration'Image (B.Initial_Interval));
      elsif B.Multiplier < 1.0 then
         Raise_Exception
           (Constraint_Error'Identity,
            "backoff: Multiplier must be >= 1, got "
            & Duration'Image (B.Multiplier));
      elsif B.Randomization_Factor < 0.0
        or else B.Randomization_Factor > 1.0
      then
         Raise_Exception
           (Constraint_Error'Identity,
            "backoff: Randomization_Factor must be in [0, 1], got "
            & Duration'Image (B.Randomization_Factor));
      elsif B.Max_Interval <= 0.0 then
         Raise_Exception
           (Constraint_Error'Identity,
            "backoff: Max_Interval must be > 0, got "
            & Duration'Image (B.Max_Interval));
      elsif B.Max_Interval < B.Initial_Interval then
         Raise_Exception
           (Constraint_Error'Identity,
            "backoff: Max_Interval ("
            & Duration'Image (B.Max_Interval)
            & ") must be >= Initial_Interval ("
            & Duration'Image (B.Initial_Interval)
            & ")");
      elsif B.Max_Elapsed_Time < 0.0 then
         Raise_Exception
           (Constraint_Error'Identity,
            "backoff: Max_Elapsed_Time must be >= 0 (0 = no limit), got "
            & Duration'Image (B.Max_Elapsed_Time));
      end if;
   end Validate;

   --  Initialize a backoff configuration with custom settings.
   procedure Initialize
     (B : in out Backoff_Config;
      Initial_Interval      : Duration := Default_Initial_Interval;
      Randomization_Factor  : Duration := Default_Randomization_Factor;
      Multiplier            : Duration := Default_Multiplier;
      Max_Interval          : Duration := Default_Max_Interval;
      Max_Elapsed_Time      : Duration := Default_Max_Elapsed_Time)
   is
   begin
      B.Initial_Interval     := Initial_Interval;
      B.Randomization_Factor := Randomization_Factor;
      B.Multiplier           := Multiplier;
      B.Max_Interval         := Max_Interval;
      B.Max_Elapsed_Time     := Max_Elapsed_Time;

      Validate (B);

      --  Reset state (creates new RNG generator).
      B.Current_Interval := Initial_Interval;
      B.Start_Time := Clock;
      Ada.Numerics.Float_Random.Reset (B.Rand_Gen);
   end Initialize;

   --  Reset backoff state (current interval and start time).
   procedure Reset (B : in out Backoff_Config) is
   begin
      Validate (B);
      B.Current_Interval := B.Initial_Interval;
      B.Start_Time := Clock;
      Ada.Numerics.Float_Random.Reset (B.Rand_Gen);
   end Reset;

   --  True when the elapsed-time budget is exhausted.
   function Elapsed_Exceeded (B : Backoff_Config) return Boolean is
   begin
      --  Max_Elapsed_Time = 0.0 means "no limit" (cenkalti/backoff).
      if B.Max_Elapsed_Time = 0.0 then
         return False;
      end if;
      return Duration (Clock - B.Start_Time) >= B.Max_Elapsed_Time;
   end Elapsed_Exceeded;

   --  Pure function: compute next interval given a current base and random seed.
   --  Deterministic: uses Random_Seed directly, no RNG state.
   function Next_Interval_After
     (Base        : Duration;
      Jitter      : Jitter_Mode;
      Random_Factor : Duration := Default_Randomization_Factor;
      Random_Seed : Duration := 0.0) return Duration
   is
      Result : Duration;
   begin
      if Base <= 0.0 then
         Raise_Exception
           (Constraint_Error'Identity,
            "backoff: Next_Interval_After base must be > 0, got "
            & Duration'Image (Base));
      elsif Random_Factor < 0.0 or else Random_Factor > 1.0 then
         Raise_Exception
           (Constraint_Error'Identity,
            "backoff: Next_Interval_After random factor must be in [0, 1], got "
            & Duration'Image (Random_Factor));
      end if;

      if Jitter = None then
         --  Deterministic: no jitter.
         Result := Base;
      elsif Jitter = Decorrelated then
         --  Decorrelated jitter: Base * random in [1-factor, 1+factor].
         --  Random_Seed in [0.0, 1.0] maps linearly to the range.
         declare
            Lower : constant Duration := 1.0 - Random_Factor;
            Upper : constant Duration := 1.0 + Random_Factor;
            Mult  : constant Duration := Lower + Random_Seed * (Upper - Lower);
         begin
            Result := Base * Mult;
         end;
      else -- Jitter = Full
         --  Full jitter: uniform in [0, Base].
         --  Random_Seed in [0.0, 1.0] maps to [0, Base].
         Result := Random_Seed * Base;
      end if;

      return Result;
   end Next_Interval_After;

   --  Get the next backoff interval with jitter applied.
   --  Returns 0.0 when Max_Elapsed_Time is exceeded.
   function Next_Back_Off (B : in out Backoff_Config) return Duration is
      Now     : constant Time := Clock;
      Elapsed : constant Duration := Duration (Now - B.Start_Time);
      Result  : Duration;
      Random_Val : Float;
   begin
      Validate (B);

      --  Check if we've exceeded Max_Elapsed_Time.
      --  Max_Elapsed_Time = 0.0 means no limit (cenkalti/backoff).
      if B.Max_Elapsed_Time > 0.0 and then Elapsed >= B.Max_Elapsed_Time then
         return 0.0;
      end if;

      --  Get random value from RNG generator.
      Random_Val := Ada.Numerics.Float_Random.Random (B.Rand_Gen);

      --  Compute next interval with jitter using deterministic core.
      Result := Next_Interval_After
        (Base          => B.Current_Interval,
         Jitter        => B.Jitter,
         Random_Factor => B.Randomization_Factor,
         Random_Seed   => Duration (Random_Val));

      --  Advance current interval: multiply, cap at Max_Interval.
      --  Overflow-safe: compare in divisor space before multiplying, so a
      --  huge Current * Multiplier cannot become Infinity (and compare
      --  oddly) before the cap comparison runs.
      if B.Multiplier > 1.0
        and then B.Current_Interval > B.Max_Interval / B.Multiplier
      then
         --  The product would exceed Max_Interval: cap directly.
         B.Current_Interval := B.Max_Interval;
      else
         B.Current_Interval := B.Current_Interval * B.Multiplier;
         if B.Current_Interval > B.Max_Interval then
            B.Current_Interval := B.Max_Interval;
         end if;
      end if;

      return Result;
   end Next_Back_Off;

end Backoff;
