# Dragon 32 for Analogue Pocket

An openFPGA core porting the Dragon 32 home computer to the Analogue Pocket,
built by trimming the MiSTer CoCo2/Dragon core down to Dragon 32 only and
replacing its MiSTer-specific plumbing with Analogue Platform Framework (APF)
equivalents.

Status: not started. See [docs/PLAN.md](docs/PLAN.md) for the full plan,
[NOTES.md](NOTES.md) for the hardware/RTL inventory (phase 0), and
[BUILD_LOG.md](BUILD_LOG.md) for build results once they start.

## Goal (v1)

- Boots to Dragon BASIC with correct video, sound and keyboard input
- Loads the Dragon 32 boot ROM from the SD card at startup
- Loads tape images (`.CAS`) and cartridge images (`.ROM`) through Pocket
  data slots
- Maps the Pocket d-pad and buttons to a joystick, plus a working way to type

## Controls

- **D-pad / stick, A:** Dragon joystick and fire button.
- **Select:** open/close the on-screen keyboard (the Dragon's own layout). While
  it's open: d-pad moves (hold to repeat), **A** presses the highlighted key
  (held while A is held), **B** latches Shift for the next key (keys show
  their shifted symbols), **X** moves the keyboard between the bottom and top
  of the screen. The joystick doesn't see the d-pad or A while it's open.
- **USB keyboard (docked):** mostly positional, like the Dragon's own keys.
  `=` and Shift+`=` give `=` and `+`; keypad `*` and `+` give `*` and `+`.

Later: disk support (DragonDOS, VDK), tape saving, save states, Dragon 64 and
CoCo modes, Analogizer video.

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

Not yet confirmed — check the upstream `CoCo2_MiSTer` LICENSE before vendoring
any of its source. agg23's IP is MIT. Analogue's own APF files carry their
own agreement in their headers; keep every header intact. Never distribute a
Dragon ROM or commercial games with this core.
