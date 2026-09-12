`timescale 1ns/1ps
//
// Testbench for the generated timer.sv (Dr. Winstead's timer_source, commit 1458a1a).
// Drives a 100 MHz clock and measures how long `t` actually takes to assert.
//
module tb_timer;

   reg         clk = 0;
   reg         clr = 1;
   reg [1:0]   scale;
   reg [7:0]   duration;
   wire        t;

   real        t0, elapsed_us, err;

   timer dut (.clk(clk), .clr(clr), .scale(scale), .duration(duration), .t(t));

   always #5 clk = ~clk;          // 10 ns period = 100 MHz, the Basys3 clock

   task run;
      input [1:0]  sc;
      input [7:0]  dur;
      input real   want_us;
      begin
         scale    = sc;
         duration = dur;
         clr      = 1;
         @(posedge clk); @(posedge clk);
         clr = 0;
         t0  = $realtime;
         wait (t === 1'b1);
         elapsed_us = ($realtime - t0) / 1000.0;
         err = 100.0 * (elapsed_us - want_us) / want_us;
         $display("  scale=%0d duration=%3d | want %9.3f us | got %9.3f us | %+7.2f %%",
                  sc, dur, want_us, elapsed_us, err);
      end
   endtask

   initial begin
      $display("");
      $display("timer.sv, 100 MHz clock");
      $display("  ------------------------------------------------------------------");
      $display("MICROSECOND scale (scale=0)");
      run(0,   1,    1.0);
      run(0,  10,   10.0);
      run(0,  50,   50.0);
      run(0, 100,  100.0);
      $display("");
      $display("MILLISECOND scale (scale=1)");
      run(1,   1,  1000.0);
      run(1,   2,  2000.0);
      run(1,  32, 32000.0);        // the 0x20 from the shipped LED example
      $display("");
      $display("  note: 'want' is the nominal value the program asks for.");
      $display("");
      $finish;
   end

endmodule
