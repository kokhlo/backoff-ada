--  Backoff.Ada implementation.
--
--  Deterministic testability:
--    - Next_Interval_After accepts a Random_Seed (Float in [0.0, 1.0]) to
--      compute jittered intervals without advancing RNG state.
--    - Tests verify jitter bounds by calling with seed = 0.0 (min) and 1.0 (max).

package body Backoff is
   --  Initialize a backoff configuration with custom settings.
   procedure Initialize
     (B : in out Backoff_Config;
      Initial_Interval    : Duration := Default_Initial_Interval;
      Randomization_Factor  : Duration := Default_Randomization_Factor;
      Multiplier          : Duration := Default_Multiplier;
      Max_Interval        : Duration := Default_Max_Interval;
      Max_Elapsed_Time    : Duration := Default_Max_Elapsed_Time;
      Jitter              : Jitter_Mode := Decorrelated)
   is
      pragma Unreferenced (Jitter);
   begin
      B.Initial_Interval := Initial_Interval;
      B.Randomization_Factor := Randomization_Factor;
      B.Multiplier := Multiplier;
      B.Max_Interval := Max_Interval;
      B.Max_Elapsed_Time := Max_Elapsed_Time;

      --  Reset state (creates new RNG generator).
      B.Current_Interval := Initial_Interval;
      B.Start_Time := Clock;
      Ada.Numerics.Float_Random.Reset (B.Rand_Gen);
   end Initialize;

   --  Reset backoff state (current interval and start time).
   procedure Reset (B : in out Backoff_Config) is
   begin
      B.Current_Interval := B.Initial_Interval;
      B.Start_Time := Clock;
      Ada.Numerics.Float_Random.Reset (B.Rand_Gen);
   end Reset;

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
      Now : constant Time := Clock;
      Elapsed : constant Duration := Duration (Now - B.Start_Time);
      Result : Duration;
      Random_Val : Float;
   begin
      --  Check if we've exceeded Max_Elapsed_Time.
      if Elapsed >= B.Max_Elapsed_Time then
         return 0.0;
      end if;

      --  Get random value from RNG generator.
      Random_Val := Ada.Numerics.Float_Random.Random (B.Rand_Gen);

      --  Compute next interval with jitter using deterministic core.
      Result := Next_Interval_After
        (Base        => B.Current_Interval,
         Jitter      => B.Jitter,
         Random_Factor => B.Randomization_Factor,
         Random_Seed => Duration (Random_Val));

      --  Advance current interval: multiply, cap at Max_Interval.
      B.Current_Interval := B.Current_Interval * B.Multiplier;
      if B.Current_Interval > B.Max_Interval then
         B.Current_Interval := B.Max_Interval;
      end if;

      return Result;
   end Next_Back_Off;

end Backoff;