--  Runnable demo for backoff: a flaky operation retried with full
--  jitter until it succeeds or the time budget runs out. The demo
--  prints each delay instead of sleeping, so it finishes instantly.
with Ada.Numerics.Float_Random;
with Ada.Text_IO;
with Backoff;      use Backoff;
with Backoff.Retry;

procedure Retry_Demo is
   use Ada.Text_IO;

   Attempts : Natural := 0;

   --  Succeeds on the 4th attempt: typical flaky dependency.
   function Flaky_Op return Boolean is
   begin
      Attempts := Attempts + 1;
      return Attempts >= 4;
   end Flaky_Op;

   --  Called after each failure with the delay before the next try.
   --  A real caller would `delay` here; the demo just prints it.
   --  (Backoff.Duration is a Float subtype, not Standard.Duration.)
   procedure On_Failure (Attempt : Positive; Delay_For : Backoff.Duration) is
   begin
      Put_Line ("attempt"
                & Positive'Image (Attempt)
                & " failed, next retry in"
                & Backoff.Duration'Image (Delay_For)
                & " s");
   end On_Failure;

   procedure Retry_With_Backoff is new Backoff.Retry.Retry_Loop
     (Op          => Flaky_Op,
      Max_Attempts => 8,
      On_Failure  => On_Failure);

   Config  : Backoff_Config (Jitter => Full);
   Success : Boolean;
begin
   --  Fast-forwarded budget: 0.5 s start, 0.05 s initial interval.
   Initialize (Config,
               Initial_Interval => 0.050,
               Multiplier       => 1.5,
               Max_Interval     => 1.000,
               Max_Elapsed_Time => 0.500);

   Retry_With_Backoff (Config, Success);

   if Success then
      Put_Line ("succeeded after" & Natural'Image (Attempts) & " attempts");
   else
      Put_Line ("gave up after" & Natural'Image (Attempts) & " attempts");
   end if;
end Retry_Demo;
