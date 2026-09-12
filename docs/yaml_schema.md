# The YAML file, field by field

One YAML file describes the whole controller. Every field below is required;
if one is missing the generator says which one.

```yaml
---
module: led_controller_with_shift
inputs: |
  // no special inputs for this controller
outputs: |
  output reg [15:0] led
initial: |
  led = 0;
rst: |
  led <= 0;
hex_prefix: 8
commands:
- name: LED_CLEAR
  databytes: 0
  verilog: led <= 0;
program: |
  0:	LED_CLEAR
...
```

## module

The module name. Becomes `src/<module>.sv`, the program ROM filename, and the
default output directory. Must be usable as a filename: letters, digits, `.`,
`_` and `-` only.

## inputs / outputs

Pasted verbatim into the generated module's port list, after the five ports
Isabella always declares (`clk`, `rst`, `intr`, `iadr`, `ready`). Write them as
Verilog port declarations, no trailing comma on the last one.

```yaml
outputs: |
  output reg [15:0] led,
  output reg        busy
```

Anything you declare here is visible to every command body.

## initial / rst

Verilog pasted into the generated `initial` block and into the `if (rst)` branch
respectively. Use `initial` for simulation and FPGA power-on state, `rst` for
what should happen on a reset. Use `=` in `initial` and `<=` in `rst`, matching
the blocking / non-blocking convention of the surrounding code.

## hex_prefix

The high nibble of your command codes, as a number. With `hex_prefix: 8` your
commands are numbered `0x80`, `0x81`, `0x82` and so on.

Pick something at or above 1. Codes `0x00` to `0x04` are reserved for the
built-in flow control commands.

**You get 16 commands per prefix.** The 17th is an error, because there is no
room left in the nibble.

## clk_hz (optional)

The frequency of `clk`, in hertz. Defaults to `100000000`, the Basys3 clock, so
existing files need no change.

```yaml
clk_hz: 50000000
```

This reaches the timer as a Verilog parameter, so `SLEEP_US 10` means ten real
microseconds on whatever board you are on.

The timer divides by 1,000,000 in integer arithmetic, so a clock that is not a
whole number of MHz rounds down and every delay runs slightly short. 12.288 MHz
is treated as 12 MHz, about 2% fast.

## commands

A list. Each entry has three fields.

| field | meaning |
|---|---|
| `name` | the mnemonic you write in `program:`. Uppercase, digits and underscores. |
| `databytes` | how many bytes follow this command in the program. Usually 0 or 1. |
| `verilog` | the body, pasted into a `case` arm and run when the command executes. |

Inside `verilog` you can use anything declared in `outputs`, plus `data`, which
holds the last data byte read.

```yaml
- name: LED_SET_LOW_BYTE
  databytes: 1
  verilog: led[7:0] <= data;
```

A command with `databytes: 2` sees only the **most recent** byte in `data`. If
you need both, latch the first one yourself into a register you declared in
`outputs`.

> Commands taking more than one data byte have never been simulated. The
> mechanism is there and looks right, but treat `databytes: 2` and above as
> untested.

## program

The program itself, one byte per line:

```
<address>:	<MNEMONIC or data byte>	# optional comment
```

The label is optional, and it can be a **name** instead of a number:

```
program: |
  start:  LED_SET_LOW_BYTE
          0x01
  loop:   LED_LEFT_SHIFT
          SLEEP_MS
          0x20
          JUMP
          loop           # no address to work out
```

That is the recommended style. Names may be used before they are defined, so
jumping forward is fine, and nothing has to be renumbered when you insert a
line.

Numeric labels still work and are still checked: if the number does not match
the byte offset the line actually lands at, generation stops and tells you.
Count carefully, a command taking a data byte occupies two addresses.

```
program: |
  0:	LED_SET_LOW_BYTE   # command at address 0
  1:	0x01               # its data byte, address 1
  2:	LED_LEFT_SHIFT     # address 2
  3:	JUMP
  4:	0x02               # jump back to address 2
```

Comments are optional, and so is the label. A bare token on its own line is
fine.

The generator also checks that every command gets the data bytes it declared. If
a command is followed by another mnemonic when it was still owed a byte, or the
program runs out mid command, generation stops rather than emitting a ROM that
is shifted by one. A `JUMP` past the end of the program warns, since it will
land in the zero padding and stop.

Maximum program length is 255 bytes. The rest of the 256-byte ROM is padded
with `0x00`, which is `NULL_CMD`, so a program that runs off the end stops
cleanly.

### Data byte radix

**The `.mem` file is hexadecimal, so a bare number is read as hex.** `20` means
32 decimal, not 20. Write the radix and avoid the whole question:

| you write | value |
|---|---|
| `0x14` | 20 |
| `8'h14` | 20 |
| `8'd20` | 20 |
| `#20` | 20 |
| `14` | 20, and prints a warning |

Bare digits still work so existing programs keep running, but they warn every
time, naming both readings.

## See also

- [instruction_set.md](instruction_set.md) for the built-in commands and the
  `intr` / `iadr` / `ready` handshake
- [basys3.md](basys3.md) for wiring the controller into a real design
