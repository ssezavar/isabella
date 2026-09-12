`timescale 1ns/1ps
//
// T6: the controller paths tb_controller.sv and tb_controller_entry.sv left
// alone. Drives test/ctrl_t6.yaml.
//
//   1  a command that takes two data bytes
//   2  SLEEP_MS through the FSM, not just the timer on its own
//   3  intr arriving during a SLEEP, which should abandon it
//   4  rst asserted mid program
//
// Sara, 09/08/26
//
module tb_controller_t6;

   reg         clk = 0;
   reg         rst = 1;
   reg         intr = 0;
   reg [7:0]   iadr = 0;
   wire        ready;
   wire [15:0] led;
   integer     fails = 0;
   real        t0;

   ctrl_t6 dut (.clk(clk), .rst(rst), .intr(intr), .iadr(iadr),
                .ready(ready), .led(led));

   always #5 clk = ~clk;                        // 100 MHz

   task fire(input [7:0] addr);
      begin
         @(negedge clk); iadr = addr; intr = 1;
         @(negedge clk); intr = 0;
      end
   endtask

   task check(input [8*28:1] what, input [15:0] got, input [15:0] want);
      begin
         if (got === want)
           $display("  PASS  %-28s = %04h", what, got);
         else begin
            $display("  FAIL  %-28s = %04h, expected %04h", what, got, want);
            fails = fails + 1;
         end
      end
   endtask

   task note(input [8*40:1] msg, input ok);
      begin
         if (ok) $display("  PASS  %0s", msg);
         else begin
            $display("  FAIL  %0s", msg);
            fails = fails + 1;
         end
      end
   endtask

   initial begin
      $display("");
      $display("=== T6, the paths nothing else covered ===");
      $display("");

      repeat (4) @(posedge clk);
      rst = 0;
      repeat (2) @(posedge clk);

      // ---------------------------------------------------------------
      $display("1. command taking two data bytes");
      fire(0);
      #4000;
      // LED_TWO writes led[7:0] from the LAST byte, then LED_SET_HIGH_BYTE
      // only reaches the program counter if BOTH bytes were consumed.
      check("led after routine A", led, 16'hCCBB);
      note("both data bytes consumed, next cmd ran", led[15:8] === 8'hCC);

      // ---------------------------------------------------------------
      $display("");
      $display("2. SLEEP_MS through the FSM");
      fire(6);
      @(negedge clk);
      t0 = $realtime;
      wait (led === 16'hFFFF);
      $display("        LED_FLOOD reached after %0.3f ms", ($realtime-t0)/1000000.0);
      note("SLEEP_MS 1 took between 0.9 and 1.2 ms",
           (($realtime-t0) > 900000) && (($realtime-t0) < 1200000));
      #2000;

      // ---------------------------------------------------------------
      $display("");
      $display("3. intr arriving during a SLEEP");
      fire(14);                                 // clears led, sleeps 100 ms
      #50000;                                   // 50 us in, well inside the sleep
      note("still sleeping, led not flooded yet", led === 16'h0000);
      fire(11);                                 // jump to the short routine
      #4000;
      check("led after interrupting routine D", led, 16'h0077);
      note("LED_FLOOD at addr 17 never ran", led !== 16'hFFFF);
      #2000;

      // ---------------------------------------------------------------
      $display("");
      $display("4. rst asserted mid program");
      fire(14);                                 // start the long sleep again
      #30000;
      rst = 1;
      repeat (4) @(posedge clk);
      rst = 0;
      repeat (4) @(posedge clk);
      check("led cleared by rst", led, 16'h0000);
      note("controller idle after rst", ready === 1'b1);
      #200000;                                  // nothing should resume
      check("still idle 200 us later", led, 16'h0000);

      $display("");
      if (fails == 0) $display("ALL T6 CHECKS PASSED");
      else            $display("%0d T6 CHECK(S) FAILED", fails);
      $display("");
      $finish;
   end

   initial begin
      #500000000;
      $display("");
      $display("!! TIMEOUT");
      $finish;
   end

endmodule
