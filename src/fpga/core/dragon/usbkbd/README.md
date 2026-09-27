# USB Keyboard Bridge

Converts the Analogue Pocket openFPGA "docked keyboard" controller-bus report
(`cont3_key` / `cont3_joy` / `cont3_trig`) directly into the Dragon 32
keyboard matrix, so a real USB keyboard connected via the Analogue Dock can
drive the machine.

This is a port of the same architecture built for
[`OpenFPGA_ZX-Spectrum`](../../../../../../OpenFPGA_ZX-Spectrum)'s
`src/fpga/core/usbkbd/` - see that project's own README for the detailed
history of why this shape was chosen. Short version below.

## Architecture: no PS/2 intermediate step

The machine's own vendored `dragoncoco.sv` still has a `ps2_key[10:0]`
input port (MiSTer's classic toggle+strobe convention: a scancode, a
press/break bit, and a bit that toggles on every event) feeding a vendored
`keyboard.sv` module - but that module has since been **removed entirely**
from this project (see `NOTES.md`'s licensing findings: it was
non-commercial-only licensed, and unneeded once this bridge existed).
`ps2_key` stays tied to `11'b0` at the top level; nothing drives it.

Tracking discrete press/release *events* one at a time, per HID report
slot, is also just the wrong shape for a 6-scancode-slot USB HID report -
see the ZX Spectrum project's README for the specific bug classes that
caused (slot reordering producing stale breaks, races getting a toggle bit
across a clock boundary safely). `apf2hid.sv` (vendored, MIT, unchanged)
extracts the raw modifier byte and 6 scancode bytes from the APF report and
synchronizes them onto `clk_dragon`. `dragon_keyboard.sv` decodes that
snapshot directly into the Dragon matrix, from scratch, every `clk_dragon`
cycle - see its own header comment for the matrix table and sources. There
is no PS/2 code, toggle bit, strobe pulse, per-slot state, or clock-domain
crossing anywhere in this path beyond the one synchronizer stage in
`core_top.v` ahead of `apf2hid.sv`.

`apf2hid.sv`'s license header:

https://github.com/opengateware/computer-msx

Copyright (c) 2023, Marcus Andrade <marcus@opengateware.org>

`SPDX-License-Identifier: MIT` (see the file itself for the full text).

## Scope: this only drives the Dragon keyboard matrix

The docked USB keyboard only ever reaches `dragon_keyboard.sv` via this
bridge, and that module only ever drives `kb_rows` (PIA0 port A, the
keyboard/joystick-button read port) given `kb_cols` (PIA0 port B, the
column select the CPU writes). It has no path to, and cannot be extended
to reach, the Analogue Pocket's own system menu (the controller's Home
button) - Analogue's platform firmware intercepts that before it ever
reaches the FPGA.

## Testing

`dragon_keyboard.sv` has no bridge-specific dependency - its testbench
drives `hid_mod`/`hid_sc1..6` directly, no `apf2hid.sv` or second clock
needed:

```
iverilog -g2012 -o tb.vvp tb_dragon_keyboard.sv dragon_keyboard.sv
vvp tb.vvp
```
