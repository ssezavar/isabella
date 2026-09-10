# Isabella

A julia-based utility to generate special-purpose programmable controllers in Verilog.
Developed for Digital Design instruction at Utah State University.

Isabella generates controllers can be used to program peripheral interfaces and behaviors 
in FPGA designs, without requiring an embedded microprocessor. The designer specifies a 
list of 8-bit command codes and the registers they control. Programs of up to 255 bytes 
are supported. Very basic looping and branching instructions are provided as part of the
base instruction set. 

The Isabella tool is named after the Bear Lake Monster which haunts the mountain 
waters of northern Utah and southern Idaho.


## Quick start

Install [Julia](https://julialang.org/downloads/), then from this directory:

```
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. scripts/isabella.jl examples/controller_with_shift.yaml
```

That writes a project tree into `led_controller_with_shift/`:

```
doc/       your command codes, for reference
inc/       generated Verilog includes
programs/  the assembled program ROM
src/       the controller and its timer
top/       a top module skeleton, ports already wired
sim/       a testbench that runs your program
```

There is a second example too, `examples/seven_segment.yaml`, which drives the
Basys3 four digit display. Its refresh loop is the program itself rather than a
counter in Verilog, and it uses symbolic labels instead of hand counted
addresses.

Options:

```
-o DIR    output directory (default: the module name in the YAML)
-f        overwrite without asking
-q        only report problems
--help
```

To check the toolchain works end to end, generate the test fixture and
simulate it. This one has a matching testbench:

```
julia --project=. scripts/isabella.jl test/ctrl_test.yaml -o build/ctrl_test
cd build/ctrl_test
iverilog -g2012 -I. -o sim.vvp ../../test/tb_controller.sv src/timer.sv src/ctrl_test.sv
vvp sim.vvp
```

You should see the LED value rotate `0001 0002 0004 0008 ...` about every
5 us. The testbenches instantiate a specific module by name, so simulating
your own controller means editing one to match. Run `vvp` from the directory
holding `programs/`, since the ROM path is resolved at runtime.

## Documentation

- [docs/yaml_schema.md](docs/yaml_schema.md) - every field of the input file
- [docs/instruction_set.md](docs/instruction_set.md) - built-in commands, the
  `intr` / `iadr` / `ready` handshake, and what the timing really costs
- [docs/basys3.md](docs/basys3.md) - putting a controller into a design
- [docs/troubleshooting.md](docs/troubleshooting.md) - error messages, and what
  to check when the board does nothing

## Tests

```
julia --project=. test/runtests.jl
```

Verilog testbenches for the timer and the controller are in `test/` as well;
see the header of each for how to run it.

## Status

The generator, the assembler, the timer and the controller FSM are all
simulated and passing. Nothing has been through Vivado or onto real hardware
yet. `scripts/controller_project`, the older bash entry point, still works if
you feed it the intermediate YAML, but `scripts/isabella.jl` replaces it and
does not need bash, yq or realpath.
