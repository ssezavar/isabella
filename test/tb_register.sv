`timescale 1ns/1ps
//
// The register commands, LOAD_A through JGZ, on the FSM. ctrl_register.yaml
// holds six routines; each is entered with intr/iadr and every change of
// led is recorded, then the record is compared against what the routine
// should have produced.
//
// The point of the count routine: under the code as pushed in 83b8440 a
// conditional jump that was not taken never finished. It fetched a second
// data byte, data_bytes went to 2, the "data_bytes == 1" test never held
// again and padr walked the whole ROM. This fixture cannot run under that
// generator, its assembler reads neither labels nor 'd literals, but a seven
// byte LOAD_B / DECR_B / JGZ loop did: led reached 3 and the FSM was still in
// DATA_BYTE after 3000 clocks with data_bytes at 208.
//
//   00  arith   10  count   1A  jz   2D  jlz   40  jgz   4A  show
//
// Sara, 9/21/26
//
module tb_register;

   reg         clk = 0;
   reg         rst = 1;
   reg         intr = 0;
   reg [7:0]   iadr = 0;
   wire        ready;
   wire [15:0] led;

   ctrl_register dut (.clk(clk), .rst(rst), .intr(intr), .iadr(iadr),
                      .ready(ready), .led(led));

   always #5 clk = ~clk;

   // every change of led, in order
   reg [15:0] trace [0:15];
   real       ttime [0:15];
   integer    tn = 0;
   always @(led) begin
      if (tn < 16) begin trace[tn] = led; ttime[tn] = $realtime; end
      tn = tn + 1;
   end

   integer fails = 0;
   integer n;

   // enter the routine at addr and wait for it to reach NULL_CMD
   task run;
      input [7:0] addr;
      input [8*8-1:0] name;
      begin
         tn = 0;
         @(posedge clk); iadr <= addr; intr <= 1;
         @(posedge clk); intr <= 0;
         // ready drops the clock after intr, so let it drop before waiting on it
         n = 0;
         while (ready && n < 10) begin @(posedge clk); n = n + 1; end
         n = 0;
         while (!ready && n < 2000) begin @(posedge clk); n = n + 1; end
         if (!ready) begin
            $display("FAIL %0s: never ready, cmd=%02h data_bytes=%0d padr=%02h",
                     name, dut.cmd, dut.data_bytes, dut.padr);
            fails = fails + 1;
         end
         @(posedge clk);
      end
   endtask

   task expect_trace;
      input [8*8-1:0] name;
      input integer   count;
      input [15:0]    v0, v1, v2, v3, v4;
      reg   [15:0]    exp [0:4];
      integer i; reg ok;
      begin
         exp[0] = v0; exp[1] = v1; exp[2] = v2; exp[3] = v3; exp[4] = v4;
         ok = (tn == count);
         for (i = 0; i < count && i < 5; i = i + 1)
           if (trace[i] !== exp[i]) ok = 0;
         if (ok)
           $display("ok   %0s", name);
         else begin
            $display("FAIL %0s: %0d led writes, expected %0d", name, tn, count);
            for (i = 0; i < tn && i < 16; i = i + 1)
              $display("       [%0d] %04h", i, trace[i]);
            fails = fails + 1;
         end
      end
   endtask

   initial begin
      #25 rst = 0;
      @(posedge clk);

      run(8'h00, "arith");
      // B after ADD, after SUB, then A and B after SWAP, then B after INCR DECR DECR
      expect_trace("arith", 5, 16'h0800, 16'hFD00, 16'hFDFD, 16'h05FD, 16'h04FD);

      run(8'h10, "count");
      // cleared, three bumps, then the LED_SET after the loop fell through
      expect_trace("count", 5, 16'h0000, 16'h0001, 16'h0002, 16'h0003, 16'h00AA);
      // what a loop iteration costs: LED_BUMP, DECR_B and a taken JGZ, then
      // the last one where JGZ falls through into LED_SET and its byte
      $display("     bump to bump, JGZ taken:     %0.0f ns", ttime[2] - ttime[1]);
      $display("     bump to LED_SET, JGZ not:   %0.0f ns", ttime[4] - ttime[3]);

      run(8'h1A, "jz");
      expect_trace("jz",    2, 16'h0011, 16'h0022, 0, 0, 0);

      run(8'h2D, "jlz");
      expect_trace("jlz",   2, 16'h0033, 16'h0044, 0, 0, 0);

      run(8'h40, "jgz");
      expect_trace("jgz",   1, 16'h0055, 0, 0, 0, 0);

      // a reset must clear A and B, not just the state
      @(posedge clk); rst <= 1; @(posedge clk); rst <= 0; @(posedge clk);
      run(8'h4A, "show");
      if (led !== 16'h0000) begin
         $display("FAIL show: A/B after reset read %04h", led);
         fails = fails + 1;
      end else
         $display("ok   show");

      if (fails == 0) $display("ALL REGISTER CHECKS PASSED");
      else            $display("%0d REGISTER CHECKS FAILED", fails);
      $finish;
   end

endmodule
