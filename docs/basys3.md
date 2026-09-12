# Using a generated controller in a design

> **Untested on hardware.** Everything here follows from the generated source
> and from simulation. Nothing in this file has been through Vivado or onto a
> real Basys3 yet. Treat it as a starting point, not a recipe that is known to
> work. If you get it onto a board, please correct this file.

## What the generator gives you

```
<outdir>/
  doc/<module>_commands.md          your command codes, for reference
  inc/<module>_command_codes.sv     localparams, included by the controller
  inc/<module>_commands.sv          the case arms, included by the controller
  inc/flow_command_codes.sv         built-in command codes
  inc/flow_commands.sv              built-in command bodies
  programs/<module>_program.mem     the assembled program, 256 bytes of hex
  src/<module>.sv                   the controller
  src/timer.sv                      the timer it depends on
  top/<module>_top.sv               a top module skeleton, wired up
  sim/tb_<module>.sv                a testbench that runs the program
```

## Adding it to a Vivado project

1. Add both files in `src/` as design sources.
2. Add `inc/` as an **include directory**. The controller uses
   `` `include "inc/..." ``, so the path it resolves against must contain
   `inc/`. Point the include path at the directory *above* `inc`.
3. Add `programs/<module>_program.mem` to the project.

**The `.mem` path is relative at runtime.** The controller does

```verilog
$readmemh("programs/<module>_program.mem", pmem, 0, 255);
```

so `programs/` has to be reachable from wherever the tool runs: the simulation
working directory for simulation, and the synthesis run directory for
synthesis. If the LEDs do nothing and the file was not found, this is why.

## A top module

Isabella generates `top/<module>_top.sv` for you now, with every output port
already connected. It looks like this:

```verilog
module top (
   input        clk,
   input        btnC,        // reset
   input        btnU,        // start the routine
   output [15:0] led
   );

   wire ready;

   led_controller_with_shift ctrl (
      .clk   (clk),
      .rst   (btnC),
      .intr  (btnU),         // debounce this in a real design
      .iadr  (8'd0),         // start at address 0
      .ready (ready),
      .led   (led)
      );

endmodule
```

`btnU` straight into `intr` will fire repeatedly while held, since the button is
not debounced and the controller re-enters on every clock `intr` is high. Fine
for a first test, not fine in general.

To run the routine once at power-on instead, hold `intr` high for one clock from
a small startup counter, or tie it high and let the program end in `NULL_CMD`.

## Constraints

The Basys3 master XDC from Digilent has everything, commented out. Uncomment
`clk`, the LEDs, and the buttons you use. The clock is 100 MHz on `W5`, which is
the default `timer.sv` is built for.

On a different board, set `clk_hz:` in the YAML. It is passed to the timer as a
parameter, so sleeps stay correct in real time.

## Simulating first

Icarus is quicker than Vivado for checking a program:

```
cd <outdir>
iverilog -g2012 -I. -o sim.vvp sim/tb_<module>.sv src/timer.sv src/<module>.sv
vvp sim.vvp
```

That testbench is generated with the project, so it already names your module
and its ports. Edit `RUN_US` at the top of it to change how long the program is
allowed to run.

Do not glob `src/*.sv` alongside `src/timer.sv`; the timer gets declared twice
and Icarus stops.

`-g2012` is required, since the generated source uses SystemVerilog `++`.

Run `vvp` from the directory containing `programs/`, or `$readmemh` will not
find the ROM.

`test/tb_controller.sv` prints every `led` change with a timestamp, and the
first 40 clocks of FSM state. Adapting it to your own module means changing the
instantiated module name and the port list.
