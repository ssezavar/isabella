`timescale 1ns/1ps
//
// Controller FSM testbench. Drives the generated ctrl_test controller and logs
// what actually happens: state changes, led writes, and the timing between
// them. Observational, so the real behaviour is visible before anything is
// asserted about it.
//
// program in ROM:
//   0: LED_SET_LOW_BYTE   81
//   1: 0x01               01
//   2: SLEEP_US           01
//   3: 0x05               05
//   4: LED_LEFT_SHIFT     84
//   5: SLEEP_US           01
//   6: 0x05               05
//   7: JUMP               04
//   8: 0x04               04
//
module tb_ctrl;

   reg         clk = 0;
   reg         rst = 1;
   reg         intr = 0;
   reg [7:0]   iadr = 0;
   wire        ready;
   wire [15:0] led;

   integer     nled = 0;
   real        tprev;

   ctrl_test dut (.clk(clk), .rst(rst), .intr(intr), .iadr(iadr),
                  .ready(ready), .led(led));

   always #5 clk = ~clk;                       // 100 MHz

   // name the states the same way the generated source does
   function [8*10:1] sname(input [2:0] s);
      case (s)
        0: sname = "WAIT";
        1: sname = "CMD_START";
        2: sname = "CMD_DONE";
        3: sname = "DATA_BYTE";
        4: sname = "SLEEP";
        default: sname = "???";
      endcase
   endfunction

   // log every led change with the gap since the previous one
   always @(led) begin
      if ($realtime > 0) begin
         $display("  %10.3f us   led = %04h   (+%0.3f us)",
                  $realtime/1000.0, led, ($realtime - tprev)/1000.0);
         tprev = $realtime;
         nled  = nled + 1;
      end
   end

   // trace the first slice of FSM activity so the handshake is visible
   integer traced = 0;
   always @(posedge clk) begin
      if (!rst && traced < 40) begin
         $display("    t=%8.3f us  state=%-10s padr=%3d cmd=%02h data=%02h dbytes=%0d ready=%b",
                  $realtime/1000.0, sname(dut.state), dut.padr, dut.cmd,
                  dut.data, dut.data_bytes, ready);
         traced = traced + 1;
      end
   end

   initial begin
      $display("");
      $display("=== controller FSM, 100 MHz ===");
      $display("");
      $display("--- first 40 clocks after reset ---");

      repeat (4) @(posedge clk);
      rst = 0;
      tprev = $realtime;

      repeat (2) @(posedge clk);

      // kick it off at address 0
      @(negedge clk); iadr = 0; intr = 1;
      @(negedge clk); intr = 0;

      #200;
      $display("");
      $display("--- led activity ---");

      #40000;                                   // 40 us, expect several shifts

      $display("");
      $display("led changes seen: %0d", nled);
      $display("final led = %04h, ready = %b", led, ready);
      $display("");
      $finish;
   end

   // watchdog
   initial begin
      #500000;
      $display("");
      $display("!! TIMEOUT, controller never finished");
      $finish;
   end

endmodule
