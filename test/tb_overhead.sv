`timescale 1ns/1ps
//
// Instruction overhead measurement. Answers one question: how many clocks does
// the FSM spend on an instruction beyond the work the instruction does.
//
// ctrl_overhead.yaml holds three routines. Each one writes led on every
// instruction, so the gap between two led writes is the cost of one
// instruction, measured rather than counted off the state diagram.
//
//   00  zero_run   ten commands taking no data byte
//   0C  one_run    ten commands taking one data byte
//   22  sleep_run  SLEEP_US 5 in a loop
//
// sara 9/15/26
//
module tb_overhead;

   reg         clk = 0;
   reg         rst = 1;
   reg         intr = 0;
   reg [7:0]   iadr = 0;
   wire        ready;
   wire [15:0] led;

   ctrl_overhead dut (.clk(clk), .rst(rst), .intr(intr), .iadr(iadr),
                      .ready(ready), .led(led));

   always #5 clk = ~clk;                       // 100 MHz, 10 ns a clock

   real tprev, gap, total;
   integer n, fails;
   reg [15:0] ledprev;

   // wait for the next led write and return the gap since the previous one
   task next_gap;
      begin
         ledprev = led;
         while (led === ledprev) @(posedge clk);
         gap   = $realtime - tprev;
         tprev = $realtime;
      end
   endtask

   // intr is only looked at in WAIT and SLEEP, so the routine in flight has
   // to be allowed to finish or the pulse is simply lost.
   task idle;
      begin
         while (dut.state !== 3'd0) @(posedge clk);
         repeat (2) @(posedge clk);
      end
   endtask

   task enter;
      input [7:0] a;
      begin
         idle;
         @(posedge clk); iadr = a; intr = 1;
         @(posedge clk); intr = 0;
         tprev = $realtime;
      end
   endtask

   task measure;
      input [8*14:1] label;
      input [7:0]    addr;
      input integer  iterations;
      input real     lo;
      input real     hi;
      begin
         total = 0;
         enter(addr);
         next_gap;                       // first one includes entry, discard
         for (n = 0; n < iterations; n = n + 1) begin
            next_gap;
            total = total + gap;
         end
         total = total / iterations;
         $display("  %0s  %0.1f ns per instruction, %0.1f clocks",
                  label, total, total / 10.0);
         if (total < lo || total > hi) begin
            $display("  FAIL  expected between %0.1f and %0.1f ns", lo, hi);
            fails = fails + 1;
         end
         else
           $display("  PASS");
      end
   endtask

   initial begin
      fails = 0;
      $display("");
      $display("=== instruction overhead at 100 MHz ===");
      $display("");
      repeat (4) @(posedge clk);
      rst = 0;
      repeat (2) @(posedge clk);

      measure("no data byte ", 8'h00, 8, 10.0,  60.0);
      measure("one data byte", 8'h0C, 8, 20.0, 100.0);
      measure("SLEEP_US 5   ", 8'h22, 8, 5000.0, 5200.0);

      $display("");
      if (fails == 0)
        $display("ALL OVERHEAD CHECKS PASSED");
      else
        $display("%0d OVERHEAD CHECKS FAILED", fails);
      $display("");
      $finish;
   end

endmodule
