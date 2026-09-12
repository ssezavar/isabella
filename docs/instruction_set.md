# Instruction set and the controller interface

## Built-in commands

Codes `0x00` through `0x04` are reserved. They exist in every controller and you
do not declare them.

| code | name | data bytes | what it does |
|---|---|---|---|
| `0x00` | `NULL_CMD` | 0 | Stop. Return to `WAIT` and raise `ready`. |
| `0x01` | `SLEEP_US` | 1 | Wait N microseconds. |
| `0x02` | `SLEEP_MS` | 1 | Wait N milliseconds. |
| `0x03` | `SLEEP_S` | 1 | Wait N seconds. |
| `0x04` | `JUMP` | 1 | Continue at the given address. |

Sleep durations are one byte, so 1 to 255 units.

Unused program memory is `0x00`, so a routine that simply runs to the end of
what you wrote stops on its own. Ending a routine with an explicit `NULL_CMD`
is clearer.

Your own commands start at `hex_prefix << 4`. With `hex_prefix: 8` they are
`0x80` upward, up to 16 of them.

## Driving the controller

This is the interface your design has to drive. Five ports:

```verilog
input        clk,     // 100 MHz on the Basys3
input        rst,
input        intr,    // pulse high to start a routine
input  [7:0] iadr,    // the address to start it at
output       ready    // high when idle and able to accept a new routine
```

To run a routine: put its start address on `iadr` and raise `intr` for at least
one clock. The controller latches the address, drops `ready`, and executes until
it hits `NULL_CMD`.

```verilog
// run the routine at address 5
iadr <= 8'd5;
intr <= 1'b1;
@(posedge clk);
intr <= 1'b0;
```

`ready` returns high when the routine finishes. It is also high during a
`SLEEP`, because the controller can accept a new routine mid-sleep: raising
`intr` during a sleep abandons it and jumps to the new address. That is
deliberate, and it is how you interrupt a long animation.

If you only need `ready` to mean "the routine finished", check that it is high
**and** that you are not in the middle of one you started.

Multiple routines live in one ROM. Give each a start address and end it with
`NULL_CMD`:

```
  0:	LED_SET_LOW_BYTE   # routine A
  1:	0x0F
  2:	NULL_CMD
  3:	LED_FLOOD          # routine B, start it with iadr = 3
  4:	NULL_CMD
```

Routines are re-entrant. Firing the same address twice runs it twice.

## Timing, and what it actually costs

**Sleeps are a floor, not an exact figure.** Every instruction costs a few
clocks to fetch and decode on top of any sleep it contains.

Measured at 100 MHz: a loop of `LED_LEFT_SHIFT`, `SLEEP_US 5`, `JUMP` repeats
every **5.09 µs**, not 5.00. That is about 90 ns of overhead per iteration,
spread across the instructions in the loop.

For blinking lights this does not matter. For a peripheral with tight
inter-command timing, an OLED init sequence for instance, budget for it, or
measure the loop you actually wrote.

The timer itself is accurate once the sleep starts:

| scale | asked | measured |
|---|---|---|
| µs | 1 | 1.000 µs |
| µs | 100 | 100.000 µs |
| ms | 1 | 1.001 ms |
| ms | 32 | 32.001 ms |

The constant +1 µs on the millisecond scale is one tick of detection latency in
the timer's rollover counters.

The timer takes the clock rate as a parameter, defaulting to 100 MHz. On
another board set `clk_hz:` in the YAML and the delays stay correct in real
time. Verified in simulation at 50 MHz, where 1, 10 and 100 µs all came out
exact.

## States

The controller is a five-state machine. You do not need this to use it, but it
helps when reading a waveform.

| state | |
|---|---|
| `WAIT` | idle, `ready` high, watching `intr` |
| `CMD_START` | decode the command in `cmd` and run its body if it has all its data |
| `DATA_BYTE` | fetch one data byte into `data`, bump the counter |
| `SLEEP` | timer running; watching for `intr` to cut it short |
| `CMD_DONE` | advance to the next instruction |

A command with data bytes bounces between `CMD_START` and `DATA_BYTE` until
`data_bytes` matches its declared count, then runs its body.

## What has and has not been verified

Simulated and passing, see `test/`:

- the FSM executing a real program, including `JUMP` looping
- `intr` / `iadr` entry at a non-zero address, `NULL_CMD` termination, `ready`,
  and re-entrancy
- `SLEEP_US` through the controller
- the timer standalone on the µs and ms scales, at both 100 and 50 MHz

Not yet simulated:

- `SLEEP_MS` and `SLEEP_S` *through the controller* (the timer itself is tested
  on the ms scale, so the risk is in the controller's `timerUnits` handling)
- commands with more than one data byte
- `intr` arriving during a `SLEEP`
- `rst` asserted mid-program

Nothing has been run in Vivado or on real hardware yet.
