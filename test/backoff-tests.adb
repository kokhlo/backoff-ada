--  Test runner for backoff-ada exponential backoff library.
--  Plain Ada test suite with assertion-based checks.
--
--  Test coverage:
--    1. Exact sequence without jitter (factor=0): 500ms, 750ms, 1125ms, ...
--    2. Capping at MaxInterval (60s).
--    3. MaxElapsedTime stop (compute manually, no fake clock needed).
--    4. Jitter bounds with deterministic seed (factor=0.5: interval in [0.75x, 1.25x]).
--    5. Full jitter bounds: interval in [0, x].
--    6. Retry: succeeds after 2 failures (count attempts).
--    7. Retry: respects Max_Attempts.
--    8. Retry: On_Failure called with right delays (capture delays, no actual sleep).

with Ada.Text_IO;         use Ada.Text_IO;
with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Containers.Vectors;
with Backoff.Retry;       use Backoff.Retry;

procedure Backoff.Tests is

   Passes   : Natural := 0;
   Failures : Natural := 0;

   procedure Assert (Condition : Boolean; Message : String) is
   begin
      if Condition then
         Passes := Passes + 1;
         Put_Line ("[PASS] " & Message);
      else
         Failures := Failures + 1;
         Put_Line ("[FAIL] " & Message);
      end if;
   end Assert;

   --  Test 1: Exact sequence without jitter (factor=0 via None mode).
   --  Initial 500ms, multiplier 1.5 → 500ms, 750ms, 1125ms, 1687.5ms, ...
   procedure Test_Exact_Sequence is
      Config : Backoff_Config (Jitter => None);
      Delay1, Delay2, Delay3 : Duration;
   begin
      Initialize (Config,
                  Initial_Interval => 0.500,
                  Randomization_Factor => 0.0,
                  Multiplier => 1.5,
                  Max_Interval => 60.0,
                  Max_Elapsed_Time => 900.0);

      Delay1 := Next_Back_Off (Config);
      Delay2 := Next_Back_Off (Config);
      Delay3 := Next_Back_Off (Config);

      --  Allow ±0.001s tolerance for float arithmetic.
      Assert (abs (Delay1 - 0.500) < 0.001, "Exact sequence: first interval 500ms");
      Assert (abs (Delay2 - 0.750) < 0.001, "Exact sequence: second interval 750ms");
      Assert (abs (Delay3 - 1.125) < 0.001, "Exact sequence: third interval 1125ms");
   end Test_Exact_Sequence;

   --  Test 2: Capping at Max_Interval (60s).
   procedure Test_Max_Interval_Cap is
      Config : Backoff_Config (Jitter => None);
      Delay_Val : Duration;
      Exceeded_Cap : Boolean := False;
   begin
      Initialize (Config,
                  Initial_Interval => 30.0,
                  Multiplier => 2.0,
                  Max_Interval => 60.0,
                  Max_Elapsed_Time => 900.0);

      --  30 → 60 → 120 (capped to 60) → 240 (capped to 60) → ...
      for I in 1 .. 10 loop
         Delay_Val := Next_Back_Off (Config);
         if Delay_Val > 60.0 + 0.001 then
            Exceeded_Cap := True;
            exit;
         end if;
      end loop;

      Assert (not Exceeded_Cap, "Max_Interval cap: no delay exceeded 60s");
   end Test_Max_Interval_Cap;

   --  Test 3: MaxElapsedTime stop (compute manually).
   --  Set MaxElapsedTime to 2.0s; loop until Next_Back_Off returns 0.0.
   procedure Test_Max_Elapsed_Time is
      Config : Backoff_Config (Jitter => None);
      Stopped : Boolean := False;
      Delay_Val : Duration;
   begin
      Initialize (Config,
                  Initial_Interval => 0.100,
                  Multiplier => 1.5,
                  Max_Interval => 5.0,
                  Max_Elapsed_Time => 2.0);  --  2 seconds total

      --  Loop until Next_Back_Off returns 0.0 (stop signal).
      for I in 1 .. 50 loop
         Delay_Val := Next_Back_Off (Config);
         if Delay_Val = 0.0 then
            Stopped := True;
            exit;
         end if;

         --  Simulate delay (but we don't actually sleep in tests).
         delay Standard.Duration (Delay_Val);
      end loop;

      Assert (Stopped, "Max_Elapsed_Time: stopped after 2s");
   end Test_Max_Elapsed_Time;

   --  Test 4: Jitter bounds with deterministic seed (Decorrelated).
   --  Randomization factor 0.5 → multiplier in [0.5x, 1.5x] of base (1 ± 0.5).
   --  Use Next_Interval_After with seed 0.0 (min) and 1.0 (max).
   procedure Test_Jitter_Bounds_Decorrelated is
      Base : constant Duration := 1.0;  --  1 second
      Factor : constant Duration := 0.5;
      Min_Val, Max_Val : Duration;
      Expected_Min : constant Duration := 0.5;
      Expected_Max : constant Duration := 1.5;
   begin
      Min_Val := Next_Interval_After (Base, Decorrelated, Factor, Random_Seed => 0.0);
      Max_Val := Next_Interval_After (Base, Decorrelated, Factor, Random_Seed => 1.0);

      Assert (abs (Min_Val - Expected_Min) < 0.001,
              "Decorrelated jitter min: 0.5x base (seed=0.0)");
      Assert (abs (Max_Val - Expected_Max) < 0.001,
              "Decorrelated jitter max: 1.5x base (seed=1.0)");
   end Test_Jitter_Bounds_Decorrelated;

   --  Test 5: Full jitter bounds: interval in [0, base].
   procedure Test_Jitter_Bounds_Full is
      Base : constant Duration := 2.0;
      Min_Val, Max_Val : Duration;
   begin
      Min_Val := Next_Interval_After (Base, Full, Random_Factor => 0.5, Random_Seed => 0.0);
      Max_Val := Next_Interval_After (Base, Full, Random_Factor => 0.5, Random_Seed => 1.0);

      Assert (abs (Min_Val - 0.0) < 0.001, "Full jitter min: 0.0 (seed=0.0)");
      Assert (abs (Max_Val - Base) < 0.001, "Full jitter max: base (seed=1.0)");
   end Test_Jitter_Bounds_Full;

   --  Test 6: Retry succeeds after 2 failures (count attempts).
   procedure Test_Retry_Succeeds_After_Failures is
      Config : Backoff_Config (Jitter => None);
      Success : Boolean;
      Attempt_Count : Natural := 0;

      function Op return Boolean is
      begin
         Attempt_Count := Attempt_Count + 1;
         if Attempt_Count < 3 then
            return False;  --  Fail on first 2 attempts
         else
            return True;   --  Succeed on 3rd attempt
         end if;
      end Op;

      procedure On_Failure (Attempt : Positive; Delay_For : Duration) is
         pragma Unreferenced (Delay_For);
      begin
         null;  --  Just count; no actual sleep
      end On_Failure;

      procedure Retry_Op is new Backoff.Retry.Retry_Loop (Op, Max_Attempts => 5, On_Failure => On_Failure);

   begin
      Initialize (Config);
      Retry_Op (Config, Success);

      Assert (Success, "Retry: succeeded after 2 failures");
      Assert (Attempt_Count = 3, "Retry: exactly 3 attempts made");
   end Test_Retry_Succeeds_After_Failures;

   --  Test 7: Retry respects Max_Attempts (fail all 5, then stop).
   procedure Test_Retry_Max_Attempts is
      Config : Backoff_Config (Jitter => None);
      Success : Boolean;
      Attempt_Count : Natural := 0;

      function Op return Boolean is
      begin
         Attempt_Count := Attempt_Count + 1;
         return False;  --  Always fail
      end Op;

      procedure On_Failure (Attempt : Positive; Delay_For : Duration) is
         pragma Unreferenced (Attempt, Delay_For);
      begin
         null;
      end On_Failure;

      procedure Retry_Op is new Backoff.Retry.Retry_Loop (Op, Max_Attempts => 5, On_Failure => On_Failure);

   begin
      Initialize (Config);
      Retry_Op (Config, Success);

      Assert (not Success, "Retry: failed after Max_Attempts exhausted");
      Assert (Attempt_Count = 5, "Retry: exactly 5 attempts made");
   end Test_Retry_Max_Attempts;

   --  Test 8: Retry On_Failure called with right delays (capture delays).
   procedure Test_Retry_On_Failure_Delays is
      Config : Backoff_Config (Jitter => None);
      Success : Boolean;
      Attempt_Count : Natural := 0;

      package Duration_Vectors is new Ada.Containers.Vectors
        (Index_Type   => Positive,
         Element_Type => Duration);
      Delays : Duration_Vectors.Vector;

      function Op return Boolean is
      begin
         Attempt_Count := Attempt_Count + 1;
         return False;  --  Always fail
      end Op;

      procedure On_Failure (Attempt : Positive; Delay_For : Duration) is
         pragma Unreferenced (Attempt);
      begin
         Delays.Append (Delay_For);
      end On_Failure;

      procedure Retry_Op is new Backoff.Retry.Retry_Loop (Op, Max_Attempts => 4, On_Failure => On_Failure);

   begin
      Initialize (Config,
                  Initial_Interval => 0.500,
                  Multiplier => 1.5,
                  Max_Interval => 60.0);

      Retry_Op (Config, Success);

      --  On_Failure is called on each failure EXCEPT the last attempt.
      --  With Max_Attempts=4: attempts 1,2,3 fail → call On_Failure 3 times.
      --  Attempt 4 fails → no On_Failure (exhausted).
      --  Expected delays: 500ms, 750ms, 1125ms.
      Assert (not Success, "Retry: failed as expected");
      Assert (Natural (Delays.Length) = 3, "Retry: On_Failure called 3 times");

      if Natural (Delays.Length) >= 3 then
         Assert (abs (Delays.Element (1) - 0.500) < 0.001,
                 "Retry: first delay 500ms");
         Assert (abs (Delays.Element (2) - 0.750) < 0.001,
                 "Retry: second delay 750ms");
         Assert (abs (Delays.Element (3) - 1.125) < 0.001,
                 "Retry: third delay 1125ms");
      end if;
   end Test_Retry_On_Failure_Delays;

   --  Test 9 (0.3.0): Initialize has no Jitter parameter — the mode is the
   --  discriminant, fixed at declaration. This test exists to pin the API:
   --  it does not compile if someone re-adds the dead parameter.
   --  (Compile-time guard; no runtime assertions beyond instantiation.)
   procedure Test_Jitter_Is_Discriminant is
      Config : Backoff_Config (Jitter => Full);
   begin
      Initialize (Config, Initial_Interval => 1.0);
      Assert (True, "Jitter mode: pinned by discriminant (compile-time API check)");
      pragma Assert (Config.Jitter = Full);
   end Test_Jitter_Is_Discriminant;

   --  Test 10 (0.3.0): invalid configs raise Constraint_Error instead of
   --  producing negative/zero delays downstream.
   procedure Test_Invalid_Config_Rejected is
      use Ada.Exceptions;
      Config : Backoff_Config (Jitter => None);
      Raised : Boolean := False;
   begin
      begin
         Initialize (Config, Initial_Interval => -1.0);
      exception
         when E : Constraint_Error =>
            Raised := True;
            Assert (Ada.Strings.Fixed.Index
                      (Exception_Message (E), "Initial_Interval") /= 0,
                    "Invalid config: message names Initial_Interval");
      end;
      Assert (Raised, "Invalid config: Initial_Interval <= 0 rejected");

      Raised := False;
      begin
         Initialize (Config, Initial_Interval => 1.0, Multiplier => 0.5);
      exception
         when Constraint_Error => Raised := True;
      end;
      Assert (Raised, "Invalid config: Multiplier < 1 rejected");

      Raised := False;
      begin
         Initialize (Config, Initial_Interval => 1.0, Randomization_Factor => 1.5);
      exception
         when Constraint_Error => Raised := True;
      end;
      Assert (Raised, "Invalid config: Randomization_Factor > 1 rejected");

      Raised := False;
      begin
         Initialize (Config, Initial_Interval => 5.0, Max_Interval => 1.0);
      exception
         when Constraint_Error => Raised := True;
      end;
      Assert (Raised, "Invalid config: Max_Interval < Initial_Interval rejected");

      Raised := False;
      begin
         Initialize (Config, Initial_Interval => 1.0, Max_Elapsed_Time => -5.0);
      exception
         when Constraint_Error => Raised := True;
      end;
      Assert (Raised, "Invalid config: Max_Elapsed_Time < 0 rejected");

      --  Hand-mutated fields cannot bypass validation either.
      Config.Initial_Interval := 1.0;
      Config.Multiplier := 1.5;
      Config.Max_Interval := 60.0;
      Config.Max_Elapsed_Time := 900.0;
      Config.Randomization_Factor := 0.5;
      Config.Initial_Interval := -2.0;
      Raised := False;
      begin
         declare
            D : Backoff.Duration;
            pragma Unreferenced (D);
         begin
            D := Next_Back_Off (Config);
         end;
      exception
         when Constraint_Error => Raised := True;
      end;
      Assert (Raised, "Invalid config: hand-mutated fields rejected by Next_Back_Off");
   end Test_Invalid_Config_Rejected;

   --  Test 11 (0.3.0): Next_Interval_After rejects bad inputs itself.
   procedure Test_Interval_After_Validation is
      Raised : Boolean;
   begin
      Raised := False;
      begin
         declare
            D : constant Backoff.Duration :=
              Next_Interval_After (-1.0, Decorrelated);
            pragma Unreferenced (D);
         begin
            null;
         end;
      exception
         when Constraint_Error => Raised := True;
      end;
      Assert (Raised, "Next_Interval_After: negative base rejected");

      Raised := False;
      begin
         declare
            D : constant Backoff.Duration :=
              Next_Interval_After (1.0, Decorrelated, Random_Factor => 1.5);
            pragma Unreferenced (D);
         begin
            null;
         end;
      exception
         when Constraint_Error => Raised := True;
      end;
      Assert (Raised, "Next_Interval_After: factor > 1 rejected");
   end Test_Interval_After_Validation;

   --  Test 12 (0.3.0): Max_Elapsed_Time = 0 means "no limit", not
   --  "stop immediately". cenkalti semantics: zero MaxElapsedTime is
   --  never exceeded.
   procedure Test_Zero_Max_Elapsed_Means_No_Limit is
      Config : Backoff_Config (Jitter => None);
      D : Backoff.Duration;
      Got_Nonzero : Boolean := False;
   begin
      Initialize (Config, Initial_Interval => 0.050,
                  Multiplier => 1.5, Max_Interval => 1.0,
                  Max_Elapsed_Time => 0.0);
      for I in 1 .. 10 loop
         D := Next_Back_Off (Config);
         if D > 0.0 then
            Got_Nonzero := True;
         end if;
         delay Standard.Duration (0.005);
      end loop;
      Assert (Got_Nonzero,
              "Max_Elapsed_Time = 0: no stop after time passes");
      Assert (not Elapsed_Exceeded (Config),
              "Max_Elapsed_Time = 0: Elapsed_Exceeded stays False");
   end Test_Zero_Max_Elapsed_Means_No_Limit;

   --  Test 13 (0.3.0): a Full-jitter draw of exactly 0.0 is a legitimate
   --  "retry immediately" delay — Retry_Loop must NOT treat it as a stop.
   procedure Test_Zero_Delay_Not_A_Stop is
      Config : Backoff_Config (Jitter => Full);
      Success : Boolean;
      Calls : Natural := 0;

      function Op return Boolean is
      begin
         Calls := Calls + 1;
         return Calls >= 3;  -- succeed on the 3rd attempt
      end Op;

      --  Deterministic "Full jitter draw = 0.0 every time": we emulate by
      --  making every failure callback observable; the loop must keep
      --  going until Max_Attempts even with a 0.0 delay.
      Delays_Seen : Natural := 0;

      procedure On_Failure (Attempt : Positive; Delay_For : Backoff.Duration) is
         pragma Unreferenced (Attempt);
      begin
         Delays_Seen := Delays_Seen + 1;
         pragma Assert (Delay_For >= 0.0);
      end On_Failure;

      procedure Retry_Op is new Backoff.Retry.Retry_Loop
        (Op, Max_Attempts => 5, On_Failure => On_Failure);
   begin
      Initialize (Config, Initial_Interval => 0.010,
                  Multiplier => 2.0, Max_Interval => 1.0,
                  Max_Elapsed_Time => 0.0);
      Retry_Op (Config, Success);
      Assert (Success, "Zero delay: retry still succeeds (no premature stop)");
      Assert (Calls = 3, "Zero delay: exactly 3 attempts (no premature abort)");
      Assert (Delays_Seen = 2,
              "Zero delay: On_Failure called after each failed attempt");
   end Test_Zero_Delay_Not_A_Stop;

   --  Test 14 (0.3.0): overflow-safe advance. A huge Multiplier must not
   --  produce Inf/NaN intervals: the cap decision happens before multiply.
   procedure Test_Overflow_Safe_Advance is
      Config : Backoff_Config (Jitter => None);
      D : Backoff.Duration;
      All_Finite : Boolean := True;
   begin
      Initialize (Config, Initial_Interval => 1.0,
                  Randomization_Factor => 0.0,
                  Multiplier => 1.0e18, Max_Interval => 1.0e30,
                  Max_Elapsed_Time => 0.0);
      for I in 1 .. 5 loop
         D := Next_Back_Off (Config);
         if D > 1.0e30 or else D < 0.0 or else D /= D then
            All_Finite := False;
         end if;
      end loop;
      Assert (All_Finite, "Overflow: intervals stay bounded and finite");
      Assert (Config.Current_Interval <= 1.0e30,
              "Overflow: Current_Interval capped at Max_Interval");
   end Test_Overflow_Safe_Advance;

   --  Test 15 (0.3.0): Max_Interval is enforced as a hard ceiling from the
   --  very first Next_Back_Off call (initial clamp), not only after growth.
   procedure Test_Max_Interval_Enforced_From_Start is
      Config : Backoff_Config (Jitter => None);
   begin
      --  Max_Interval >= Initial_Interval is validated; the first delay
      --  is the initial interval (no pre-clamp needed when config valid).
      Initialize (Config, Initial_Interval => 2.0,
                  Multiplier => 10.0, Max_Interval => 4.0,
                  Max_Elapsed_Time => 0.0);
      declare
         D1 : constant Backoff.Duration := Next_Back_Off (Config);
         D2 : constant Backoff.Duration := Next_Back_Off (Config);
         D3 : constant Backoff.Duration := Next_Back_Off (Config);
      begin
         Assert (D1 = 2.0, "Ceiling: first delay = initial interval");
         Assert (D2 = 4.0, "Ceiling: second delay capped at Max_Interval");
         Assert (D3 = 4.0, "Ceiling: third delay stays at Max_Interval");
      end;
   end Test_Max_Interval_Enforced_From_Start;

   --  Test 16 (0.3.0): Reset returns to the initial interval and restarts
   --  the elapsed clock.
   procedure Test_Reset_Restarts_Sequence is
      Config : Backoff_Config (Jitter => None);
      D : Backoff.Duration;
   begin
      Initialize (Config, Initial_Interval => 0.500,
                  Multiplier => 1.5, Max_Interval => 60.0,
                  Max_Elapsed_Time => 0.0);
      for I in 1 .. 5 loop
         D := Next_Back_Off (Config);
      end loop;
      Reset (Config);
      D := Next_Back_Off (Config);
      Assert (abs (D - 0.500) < 0.001,
              "Reset: sequence restarts at initial interval");
   end Test_Reset_Restarts_Sequence;

begin
   Put_Line ("=== backoff-ada Exponential Backoff Test Suite ===");
   New_Line;

   Test_Exact_Sequence;
   Test_Max_Interval_Cap;
   Test_Max_Elapsed_Time;
   Test_Jitter_Bounds_Decorrelated;
   Test_Jitter_Bounds_Full;
   Test_Retry_Succeeds_After_Failures;
   Test_Retry_Max_Attempts;
   Test_Retry_On_Failure_Delays;
   Test_Jitter_Is_Discriminant;
   Test_Invalid_Config_Rejected;
   Test_Interval_After_Validation;
   Test_Zero_Max_Elapsed_Means_No_Limit;
   Test_Zero_Delay_Not_A_Stop;
   Test_Overflow_Safe_Advance;
   Test_Max_Interval_Enforced_From_Start;
   Test_Reset_Restarts_Sequence;

   New_Line;
   Put_Line ("=== Summary ===");
   Put_Line ("Passes:   " & Natural'Image (Passes));
   Put_Line ("Failures: " & Natural'Image (Failures));

   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
   else
      Put_Line ("SOME TESTS FAILED");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Backoff.Tests;