# Notes

Working notes for the port. See [docs/PLAN.md](docs/PLAN.md) for the full
plan.

## Phase 0 task: inventory `rtl/`

Not started. Map each module in the
[CoCo2_MiSTer](https://github.com/MiSTer-devel/CoCo2_MiSTer) `rtl/` folder to
a Dragon 32 hardware block, and list everything MiSTer-specific that needs
replacing.

Hardware blocks to account for:

- CPU: Motorola 6809E
- Memory controller: 6883 SAM (address decode, memory map, clocks, video
  addressing)
- Video: 6847 VDG (text, semigraphics and graphics modes, 256x192 active
  area)
- I/O: two 6821 PIAs (keyboard matrix, joysticks, tape, sound, VDG mode
  pins)
- RAM: 32K usable
- ROM: 16K Microsoft BASIC boot ROM (`d32.rom`)
- Cartridge port
- Tape: audio in/out via PIA
- Sound: 6-bit DAC on a PIA

MiSTer-specific pieces expected to be dropped or replaced (confirm against
the actual repo): `sys/` framework, `hps_io`, OSD/status-bit handling,
`CoCo2.sv` top module, `ioctl_download`/`ioctl_upload`.

## Licensing check

Not done. Read the `CoCo2_MiSTer` LICENSE file before vendoring any of its
source — see the Licensing section in docs/PLAN.md.
