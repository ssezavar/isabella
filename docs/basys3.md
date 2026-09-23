# Using a generated controller in a design

> **Mostly untested on hardware.** In September 2026 Dr. Winstead built
> `controller_with_shift` with Vivado and ran it on a Basys3, using the
> upstream FSM and timer and a six line `top.sv` of his own. That settles the
> build flow and the pin choices below, and they are marked as such. What it
> does not cover: the generated `top/` skeleton, the parameterized timer, the
> one clock command fetch and the register commands, all of which exist only in
> this copy and have only been simulated. Treat those parts as a starting point.

## What his Basys3 build settles

The project he built has this shape, and it works on the board:

```
Makefile                        exports PROJECT and TOP, includes resources/verilog.mk
resources/build.tcl             read_verilog [glob src/*.v src/*.sv], read_xdc, synth, place, route, bitstream
led_controller_with_shift.xdc   the Digilent master XDC with clk, led[15:0], rst and intr uncommented
src/top.sv                      the controller instantiated with iadr tied to 0
src/led_controller_with_shift.sv, src/timer.sv, inc/*, programs/*   straight from the generator
```

Three things worth knowing from it:

- **Relative paths work from the project directory.** He ran Vivado in batch
  mode from the directory holding `inc/` and `programs/`, and both the
  `` `include "inc/..." `` lines and the `$readmemh("programs/...")` resolved
  without an include path being set. The advice below about include
  directories is for the GUI project flow, where the working directory is
  somewhere else.
- **Pins.** `rst` on `U18` (btnC) and `intr` on `T18` (btnU). That is what the
  generated `top/` skeleton assumes too.
- **Behaviour on the board.** After programming the controller sits in `WAIT`.
  A press of btnU starts the routine, one LED scanning in a circular shift.
  The 20 ms in the example was a bare `20` in his copy, so 32 ms, and his
  timer makes that 32.35 ms (see the timer notes in
  [instruction_set.md](instruction_set.md)). Neither is visible to the eye,
  which is why a scanning LED is a poor test of timing.

## What the generator gives you

```
<outdir>/
  doc/<module>_commands.md          your command codes, for reference
  inc/<module>_command_codes.sv     localparams, included by the controller
  inc/<module>_commands.sv          the case arms, included by the controller
  inc/flow_command_codes.sv         built-in command codes
  inc/flow_commands.sv              built-in command bodies
  inc/register_command_codes.sv     the A/B register command codes
  inc/register_commands.sv          and their bodies
  programs/<module>_program.mem     the assembled program, 256 bytes of hex
  programs/<module>_program.lst     the same program as a readable listing
  src/<module>.sv                   the controller
  src/timer.sv                      the timer it depends on
  top/<module>_top.sv               a top module skeleton, wired up
  sim/tb_<module>.sv                a testbench that runs the program
```

## Simulating under Vivado

`scripts/vivado_sim.tcl` runs a generated project under xsim in batch:

```
vivado -mode batch -source scripts/vivado_sim.tcl -tclargs seven_segment seven_segment
```

Everything verified so far has been verified with Icarus. Running the same
project under a second simulator is worth doing before trusting it on a board,
because the two disagree about plenty.

**That script has never been run.** Vivado is not installed here. It is written
from the documented behaviour of those commands, not from a passing run. When
you run it, fix it in place.

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
iverilog -I. -o sim.vvp sim/tb_<module>.sv src/timer.sv src/<module>.sv
vvp sim.vvp
```

That testbench is generated with the project, so it already names your module
and its ports. Edit `RUN_US` at the top of it to change how long the program is
allowed to run.

Do not glob `src/*.sv` alongside `src/timer.sv`; the timer gets declared twice
and Icarus stops.

No `-g` flag is needed. The generated source is Verilog 2001.

Run `vvp` from the directory containing `programs/`, or `$readmemh` will not
find the ROM.

`test/tb_controller.sv` prints every `led` change with a timestamp, and the
first 40 clocks of FSM state. Adapting it to your own module means changing the
instantiated module name and the port list.
