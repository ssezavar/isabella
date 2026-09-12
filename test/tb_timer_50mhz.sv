`timescale 1ns/1ps
// same timer, told it is on a 50 MHz clock, driven at 50 MHz.
// delays should come out the same in real time as the 100 MHz case.
module tb50;
   reg clk=0, clr=1; reg [1:0] scale; reg [7:0] duration; wire t;
   real t0;
   timer #(.CLK_HZ(50000000)) dut (.clk(clk),.clr(clr),.scale(scale),
                                   .duration(duration),.t(t));
   always #10 clk = ~clk;                     // 20 ns period = 50 MHz
   task run(input [1:0] sc, input [7:0] dur, input real want_us);
      begin
         scale=sc; duration=dur; clr=1;
         @(posedge clk); @(posedge clk); clr=0; t0=$realtime;
         wait (t===1'b1);
         $display("  50 MHz  scale=%0d duration=%3d | want %8.3f us | got %8.3f us | %+6.2f %%",
                  sc,dur,want_us,($realtime-t0)/1000.0,
                  100.0*((($realtime-t0)/1000.0)-want_us)/want_us);
      end
   endtask
   initial begin
      $display("");
      run(0,1,1.0); run(0,10,10.0); run(0,100,100.0); run(1,2,2000.0);
      $display("");
      $finish;
   end
endmodule
