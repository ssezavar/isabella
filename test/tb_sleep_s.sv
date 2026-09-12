`timescale 1ns/1ps
// SLEEP_S through the controller, at 1 MHz so a second is only 1M clocks.
// Sara (9/8):
module tb_sleep_s;
   reg clk=0, rst=1, intr=0; reg [7:0] iadr=0;
   wire ready; wire [15:0] led;
   real t0;
   ctrl_sleep_s dut (.clk(clk),.rst(rst),.intr(intr),.iadr(iadr),
                     .ready(ready),.led(led));
   always #500 clk = ~clk;                 // 1000 ns period = 1 MHz
   initial begin
      $display("");
      repeat (4) @(posedge clk); rst = 0; repeat (2) @(posedge clk);
      @(negedge clk); iadr = 0; intr = 1; @(negedge clk); intr = 0;
      t0 = $realtime;
      wait (led === 16'hFFFF);
      $display("  SLEEP_S 1 at 1 MHz -> %0.4f s", ($realtime-t0)/1.0e9);
      if ((($realtime-t0) > 0.9e9) && (($realtime-t0) < 1.15e9))
        $display("  PASS  within tolerance of one second");
      else
        $display("  FAIL  out of tolerance");
      $display("");
      $finish;
   end
   initial begin #3000000000; $display("  !! TIMEOUT"); $finish; end
endmodule
