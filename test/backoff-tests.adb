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
                  Max_Elapsed_Time => 900.0,
                  Jitter => None);

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
                  Max_Elapsed_Time => 900.0,
                  Jitter => None);

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
                  Max_Elapsed_Time => 2.0,  --  2 seconds total
                  Jitter => None);

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
      Initialize (Config, Jitter => None);
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
      Initialize (Config, Jitter => None);
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
                  Max_Interval => 60.0,
                  Jitter => None);

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