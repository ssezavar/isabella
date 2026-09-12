# When it goes wrong

## Generation

**`error: <file> has no `rst:` field`**
The YAML is missing a required field. All eight are listed in
[yaml_schema.md](yaml_schema.md).

**`error: program line "5:	LED_CLEAR": label says 5 but byte offset is 1`**
Your address labels do not match where the bytes actually land. Remember a
command with a data byte takes two addresses. Renumber from the line named.

**`error: program line "...": "FOO" is not a known command or a valid byte`**
Either a mnemonic that is not in your `commands:` list, usually a typo or a case
difference, or a data byte in a form the assembler does not accept. See the
radix table in [yaml_schema.md](yaml_schema.md).

**`Warning: byte "20" has no radix, reading it as hex (32 decimal)`**
Not fatal, but it is telling you something real. A bare `20` in the program is
hex, so it means 32. Write `0x20` if you meant 32, or `#20` if you meant 20.

**`error: too many commands (17). only 16 fit under hex_prefix 8`**
One `hex_prefix` gives you 16 command codes. Split the design, or use a
different prefix for a second controller.

**`error: program is 260 bytes, 255 is the limit`**
The ROM is 256 bytes and the last one is reserved. Shorten the program, or move
work into the command bodies.

## Synthesis and simulation

**`Unknown module type: timer`**
`src/timer.sv` was not added to the project. Both files in `src/` are needed.

**`Cannot find include file inc/flow_command_codes.sv`**
The include path is wrong. It must point at the directory *containing* `inc/`,
not at `inc/` itself.

**`syntax error` on `padr++` or `uscount++`**
The generated source is SystemVerilog. Icarus needs `-g2012`. Vivado is fine
provided the files are `.sv` and not `.v`.

**`WARNING: $readmemh: Unable to open programs/..._program.mem`**
The path is resolved at runtime relative to the working directory, not relative
to the source file. Run the simulator from the directory that contains
`programs/`.

## On the board

**Nothing happens at all.**
Check `ready` first. If it never goes low, `intr` is not reaching the
controller. If it goes low and stays low, the program is running but stuck,
most likely a `JUMP` to the wrong address.

**Everything happens far too fast, or at once.**
The most likely cause is a bare data byte read as hex. `SLEEP_MS 50` written as
`50` is `0x50`, which is 80 ms. Also check that `intr` is not held high, which
restarts the routine on every clock.

**The pattern is right but the timing is off.**
Two known causes. Sleeps carry a few clocks of instruction overhead on top of
the requested time, about 90 ns per loop iteration at 100 MHz. And the timer
needs to know your clock: it defaults to 100 MHz, so on any other board set
`clk_hz:` in the YAML or every delay scales by the ratio.

**It jumps to the wrong place.**
Jump targets are absolute byte addresses, not line numbers. If the target
instruction takes a data byte, make sure you are pointing at the command and not
at its data.

## Still stuck

`doc/<module>_commands.md` in the generated output lists your command codes.
Compare them against `programs/<module>_program.mem`, which is plain hex, one
byte per line, and read the program by hand. Nine times out of ten the ROM shows
the problem directly.
