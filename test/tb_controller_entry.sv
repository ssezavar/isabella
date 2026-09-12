`timescale 1ns/1ps
//
// Second controller test: the integration interface a student design has to
// drive. Two routines in one ROM, entered by address.
//
//   0: LED_SET_LOW_BYTE / 0x0F / LED_SET_HIGH_BYTE / 0xF0 / NULL_CMD  -> F00F
//   5: LED_FLOOD / NULL_CMD                                          -> FFFF
//
// checks: does NULL_CMD end a routine and return to WAIT with ready high,
// and does intr at a non-zero iadr enter the right routine.
//
module tb_ctrl2;

   reg         clk = 0;
   reg         rst = 1;
   reg         intr = 0;
   reg [7:0]   iadr = 0;
   wire        ready;
   wire [15:0] led;
   integer     fails = 0;

   ctrl_test2 dut (.clk(clk), .rst(rst), .intr(intr), .iadr(iadr),
                   .ready(ready), .led(led));

   always #5 clk = ~clk;

   task fire(input [7:0] addr);
      begin
         @(negedge clk); iadr = addr; intr = 1;
         @(negedge clk); intr = 0;
      end
   endtask

   task check(input [8*24:1] what, input [15:0] got, input [15:0] want);
      begin
         if (got === want)
           $display("  PASS  %-24s = %04h", what, got);
         else begin
            $display("  FAIL  %-24s = %04h, expected %04h", what, got, want);
            fails = fails + 1;
         end
      end
   endtask

   initial begin
      $display("");
      $display("=== controller integration interface ===");
      $display("");

      repeat (4) @(posedge clk);
      rst = 0;
      repeat (2) @(posedge clk);

      $display("routine A, intr with iadr=0");
      fire(0);
      #2000;
      check("led after routine A", led, 16'hF00F);
      if (ready !== 1'b1) begin
         $display("  FAIL  ready is %b after NULL_CMD, expected 1", ready);
         fails = fails + 1;
      end
      else
        $display("  PASS  ready high again after NULL_CMD");
      $display("        padr stopped at %0d, state=%0d", dut.padr, dut.state);

      $display("");
      $display("routine B, intr with iadr=5");
      fire(5);
      #2000;
      check("led after routine B", led, 16'hFFFF);
      if (ready !== 1'b1) begin
         $display("  FAIL  ready is %b after routine B", ready);
         fails = fails + 1;
      end
      else
        $display("  PASS  ready high again after routine B");

      $display("");
      $display("re-running routine A to confirm it is re-entrant");
      fire(0);
      #2000;
      check("led back to F00F", led, 16'hF00F);

      $display("");
      if (fails == 0)
        $display("ALL CHECKS PASSED");
      else
        $display("%0d CHECK(S) FAILED", fails);
      $display("");
      $finish;
   end

   initial begin
      #200000;
      $display("");
      $display("!! TIMEOUT");
      $finish;
   end

endmodule
