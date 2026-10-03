# Dragon 32 for Analogue Pocket

An openFPGA core porting the Dragon 32 home computer to the Analogue Pocket,
built by trimming the MiSTer CoCo2/Dragon core down to Dragon 32 only and
replacing its MiSTer-specific plumbing with Analogue Platform Framework (APF)
equivalents.

A UK Dragon 32: real speed (0.89 MHz 6809), 50 Hz PAL frame timing, sound,
cassette and cartridge loading, joystick, and keyboard input from a docked USB keyboard or
an on-screen keyboard. Tested on real hardware, docked and undocked.

## Installing

1. Download the latest release zip from
   [Releases](https://github.com/McNast13/OpenFPGA_Dragon32/releases) and
   copy its `Cores`, `Platforms` and `Assets` folders to the root of the
   Pocket's SD card.
2. Supply your own Dragon 32 BASIC ROM (16 KB), named `boot.rom`, in
   `Assets/dragon32/McNast13.Dragon32/`. It is not included.
3. Put cassette images (`.cas`) in `Assets/dragon32/common/`, load one
   through the core's menu, then type `CLOAD` (BASIC) or `CLOADM` (machine
   code) and `RUN` / `EXEC`.
4. Cartridge images (`.rom` / `.ccc`, 8K or 16K) also go in
   `Assets/dragon32/common/`. Load one from the core's Cartridge slot: the
   Dragon resets and the cartridge starts. Relaunch the core to go back to
   BASIC.

## Not yet supported

Disks (DragonDOS/VDK), tape saving, save states, Dragon 64 and
CoCo modes, NTSC 60 Hz.

## Controls

- **D-pad / stick, A:** Dragon joystick and fire button.
- **Select:** open/close the on-screen keyboard (the Dragon's own layout). While
  it's open: d-pad moves (hold to repeat), **A** presses the highlighted key
  (held while A is held), **B** latches Shift for the next key (keys show
  their shifted symbols), **X** moves the keyboard between the bottom and top
  of the screen. The joystick doesn't see the d-pad or A while it's open.
- **USB keyboard (docked):** mostly positional, like the Dragon's own keys.
  `=` and Shift+`=` give `=` and `+`; keypad `*` and `+` give `*` and `+`.

## Not included

No ROMs or software. Supply your own Dragon 32 boot ROM and games, same as
the upstream MiSTer core requires.

## Sources

- Machine RTL: [MiSTer-devel/CoCo2_MiSTer](https://github.com/MiSTer-devel/CoCo2_MiSTer)
- Pocket core template: [open-fpga/core-template](https://github.com/open-fpga/core-template)
- Reusable Pocket IP (data loader, PSRAM, I2S audio): [agg23/analogue-pocket-utils](https://github.com/agg23/analogue-pocket-utils)
- Closest precedent (MiSTer computer core on Pocket): [dave18/OpenFPGA_ZX-Spectrum](https://github.com/dave18/OpenFPGA_ZX-Spectrum) — also our sibling project in this workspace, `../OpenFPGA_ZX-Spectrum`
- Claude-assisted MiSTer-to-Pocket port precedent: [janisc/openfpga-NGPC](https://github.com/janisc/openfpga-NGPC)

## Build

There's no local Quartus or Docker in this dev environment. Builds run via
GitHub Actions using the `raetro/quartus` Docker image, packaging a release
zip as a workflow artifact — following the pattern already proven in
`../OpenFPGA_ZX-Spectrum/.github/workflows/build.yml`.

## Licensing

GPL-2.0-or-later (see [LICENSE](LICENSE)), following the upstream
CoCo2_MiSTer core's top-level `CoCo2.sv`. Upstream files keep their own
headers: some are BSD-style (`pia6520.v`, `fdc.sv`, `Cassette_Write.sv`) or
GPL (`CPU09`), and `mc6809i.v` (Greg Miller) and `dac.sv` carry a copyright
notice without explicit licence terms - used as-is from upstream.
`apf2hid.sv` and `pocket_utils/` are MIT. Analogue's APF framework files
(`src/fpga/apf/`) are under Analogue's own agreement in their headers.
See [NOTES.md](NOTES.md) for the full per-file review.

Never distribute a Dragon ROM or commercial games with this core.
