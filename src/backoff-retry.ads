--  Backoff.Retry: Generic retry procedure with exponential backoff.
--
--  Instantiate with an operation function (returns Boolean) and callbacks,
--  then call the retry loop with a Backoff_Config.

package Backoff.Retry is

   --  Generic retry procedure: loop until Op returns True or Max_Attempts exhausted.
   --  On each failure, calls On_Failure (Attempt, Delay_For) with the attempt
   --  count and the delay before the next attempt (seconds as Duration).
   --  Returns Success = True if op succeeded, False if Max_Attempts reached.
   --  Note: Does NOT actually sleep; caller must honor Delay_For in On_Failure.
   generic
      with function Op return Boolean;
      Max_Attempts : Positive := 5;
      with procedure On_Failure (Attempt : Positive; Delay_For : Duration) is <>;
   procedure Retry_Loop
     (Config   : in out Backoff_Config;
      Success  : out Boolean);

end Backoff.Retry;