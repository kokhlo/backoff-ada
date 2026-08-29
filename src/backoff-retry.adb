--  Backoff.Retry implementation.

package body Backoff.Retry is

   --  Generic retry loop: execute Op until success or Max_Attempts exhausted.
   procedure Retry_Loop
     (Config   : in out Backoff_Config;
      Success  : out Boolean)
   is
      Attempt : Positive;
      Delay_Val : Duration;
   begin
      Success := False;
      for Attempt in 1 .. Max_Attempts loop
         if Op then
            Success := True;
            return;
         end if;

         --  On failure, get next delay and notify callback.
         --  Note: On_Failure receives the delay to apply before the next attempt.
         --  We get the delay FIRST, then notify; this matches cenkalti/backoff pattern.
         if Attempt = Max_Attempts then
            --  Last attempt exhausted; no further delay.
            exit;
         end if;

         Delay_Val := Next_Back_Off (Config);
         if Delay_Val = 0.0 then
            --  Max_Elapsed_Time exceeded; stop retrying.
            exit;
         end if;

         On_Failure (Attempt, Delay_Val);
      end loop;
   end Retry_Loop;

end Backoff.Retry;