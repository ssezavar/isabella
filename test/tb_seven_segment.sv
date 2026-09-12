`timescale 1ns/1ps
// seven_segment.yaml: check the multiplex loop actually walks all four digits
// and comes back round. sara 9/8/26
module tb_seven_segment;
   reg clk=0, rst=1, intr=0; reg [7:0] iadr=0;
   wire ready; wire [6:0] seg; wire [3:0] an;
   integer seen = 0, fails = 0;
   reg [3:0] order [0:4];
   seven_segment dut (.clk(clk),.rst(rst),.intr(intr),.iadr(iadr),
                      .ready(ready),.seg(seg),.an(an));
   always #5 clk = ~clk;                     // 100 MHz

   // record each new anode pattern
   always @(an) if ($realtime > 0 && seen < 5) begin
      order[seen] = an;
      $display("  %7.2f ms   an=%b seg=%b", $realtime/1000000.0, an, seg);
      seen = seen + 1;
   end

   initial begin
      $display("");
      $display("=== seven segment multiplex ===");
      $display("");
      repeat (4) @(posedge clk); rst = 0; repeat (2) @(posedge clk);
      @(negedge clk); iadr = 0; intr = 1; @(negedge clk); intr = 0;
      #20000000;                             // 20 ms, five digit slots
      $display("");
      if (order[0] !== 4'b1110) begin $display("  FAIL digit 0"); fails=fails+1; end
      if (order[1] !== 4'b1101) begin $display("  FAIL digit 1"); fails=fails+1; end
      if (order[2] !== 4'b1011) begin $display("  FAIL digit 2"); fails=fails+1; end
      if (order[3] !== 4'b0111) begin $display("  FAIL digit 3"); fails=fails+1; end
      if (order[4] !== 4'b1110) begin $display("  FAIL loop did not restart"); fails=fails+1; end
      if (fails == 0) $display("  PASS  all four digits in order, then loops");
      else            $display("  %0d FAILURE(S)", fails);
      $display("");
      $finish;
   end
   initial begin #100000000; $display("  !! TIMEOUT"); $finish; end
endmodule
