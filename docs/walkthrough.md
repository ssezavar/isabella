# A worked example, YAML to waveform

This follows `examples/seven_segment.yaml` all the way through: one YAML file,
one command, a generated project, and a simulation that proves it runs. Every
command and every block of output below was run before it was written down.

You need Julia and, for the last section, Icarus Verilog. `docs/basys3.md`
covers going on from here to real hardware.

## 1. The input

The whole controller is one file. The interesting part is the program:

```yaml
program: |
  refresh: SEG_PATTERN
           0x79           # 1
           SEG_DIGIT
           0x00           # rightmost digit
           SLEEP_MS
           0x04
  ...
           JUMP
           refresh
```

Two things to notice. `refresh:` is a named label, so the jump at the end says
`refresh` rather than an address you counted by hand. And `SEG_PATTERN` comes
before `SEG_DIGIT` deliberately; selecting the digit first would light it with
the previous digit's pattern for about 50 ns. That is real ghosting, invisible
on a board but wrong, and the fix costs nothing.

## 2. Generate

```
julia --project=. scripts/isabella.jl seven_segment.yaml
```

```
  seven_segment\doc/seven_segment_commands.md
  seven_segment\programs/seven_segment_program.mem
  seven_segment\programs/seven_segment_program.lst
  seven_segment\src/timer.sv
  seven_segment\src/seven_segment.sv
  seven_segment\inc/seven_segment_command_codes.sv
  seven_segment\inc/seven_segment_commands.sv
  seven_segment\inc/flow_commands.sv
  seven_segment\inc/flow_command_codes.sv
  seven_segment\inc/register_commands.sv
  seven_segment\inc/register_command_codes.sv
  seven_segment\top/seven_segment_top.sv
  seven_segment\sim/tb_seven_segment.sv

13 files written to seven_segment/
```

If the YAML is wrong you get one message naming the field, not a stack trace.
`docs/troubleshooting.md` lists every message the tool can produce.

## 3. Read what it assembled

`programs/*.mem` is what the hardware loads, 256 lines of hex and nothing else.
The listing beside it is the one to read:

```
# listing for seven_segment, 26 bytes
# addr  byte  source
  00    81  refresh: SEG_PATTERN
  01    79  0x79           # 1
  02    80  SEG_DIGIT
  03    00  0x00           # rightmost digit
```

and at the bottom, where each label landed:

```
# labels
  00    refresh
```

The listing and the .mem come out of the same pass over the program, so they
cannot disagree about what a byte is.

## 4. Simulate

```
cd seven_segment
iverilog -I. -o sim.vvp sim/tb_seven_segment.sv src/seven_segment.sv src/timer.sv
vvp sim.vvp
```

```
=== seven_segment ===

       0.095 us   seg = 79

finished, ready = 1
```

No `-g` flag. The generated source is Verilog 2001, so Icarus reads it at its
default setting and so will anything else.

`$readmemh` resolves `programs/..._program.mem` relative to the working
directory, which is why the commands above `cd` into the project first. Running
`vvp` from anywhere else gives an "Unable to open" warning and a ROM full of x.

The generated testbench is a smoke test: it releases reset, pulses `intr`, and
prints every change to the output register. It is there to prove the project
elaborates and starts, not to check the pattern is correct. For that, see
`test/tb_seven_segment.sv` in this repo, which watches all four digits through
a full refresh cycle and comes back round.

## 5. What to do next

`docs/basys3.md` for getting this onto a board, `docs/yaml_schema.md` for every
field you can set, `docs/instruction_set.md` for the built in commands.
