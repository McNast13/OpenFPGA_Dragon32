# Notes

Working notes for the port. See [docs/PLAN.md](docs/PLAN.md) for the full
plan.

## Phase 0 status

- Repo scaffolded from `open-fpga/core-template`: `src/fpga/{apf,core}`,
  `ap_core.qpf`/`.qsf`, and `dist/Cores/McNast13.Dragon32`,
  `dist/Platforms/dragon32.json` are in place, all still the template's
  stock content (a gray test-pattern `core_top.v` — no Dragon RTL yet).
- CI build workflow added at `.github/workflows/build.yml`, modeled on
  `../OpenFPGA_ZX-Spectrum`'s: Quartus 18.1 via the `raetro/quartus` Docker
  image, RBF→`.rbf_r` conversion, zip packaging. **Not yet run** — this repo
  has no GitHub remote yet, so the phase 0 gate ("test pattern shows on the
  Pocket screen") isn't confirmed. Push to a remote and check the Actions
  run before trusting this builds.
- RTL inventory and licensing check below: done.

## RTL inventory (`CoCo2_MiSTer` → Dragon 32 hardware blocks)

Cloned and inspected 2026-09-26 (not vendored into this repo yet — machine
RTL work starts phase 1).

| File | Hardware block | Notes |
| --- | --- | --- |
| `rtl/mc6809i.v` | CPU (6809E) | **Active** — Greg Miller's cycle-accurate soft core (`dragoncoco.sv` instantiates `mc6809i`, not any `CPU09/*.vhd` revision) |
| `rtl/CPU09/*.vhd` | CPU (unused) | OpenCores' John Kent 6809 core, several revisions vendored upstream but not instantiated by `dragoncoco.sv` — skip, don't vendor |
| `rtl/mc6883.vhd` | Memory controller (6883 SAM) | **Active** (`dragoncoco.sv` instantiates `mc6883`, not `sam.v`) |
| `rtl/sam.v` | Memory controller (unused) | Not instantiated — skip |
| `rtl/mc6847pace.vhd` | Video (6847 VDG) | **Active** (`dragoncoco.sv` instantiates `mc6847pace`, not `mc6847.vhd`). Its `charrom_inst` loads `rtl/mc6847_ntsc.hex` (Intel-hex, 65 lines) as the VDG's built-in character-generator font — this is the chip's own internal ROM content, not user software, but it's still a ROM dump baked into the RTL rather than user-supplied. Flag if this is ever published; it's the one piece of ROM-shaped content the core would ship with |
| `rtl/mc6847.vhd` | Video (unused) | Not instantiated — skip |
| `rtl/pia6520.v` | I/O (6821-compatible PIA ×2) | Thomas Skibo's PIA core |
| `rtl/keyboard.sv` | Keyboard matrix decode | PS/2 scancode → Dragon/CoCo matrix. **We replace this, not reuse it** — it's the MiSTer-specific input path our port swaps for APF/dock-keyboard and d-pad input, and see the licensing note below |
| `rtl/dac.sv` | Sound (6-bit DAC) | Alan Steremberg |
| `rtl/cassette.v`, `rtl/Cassette_Write.sv` | Tape in/out | |
| `rtl/fdc.sv`, `rtl/wd1793.sv` | Disk controller | Not needed for v1 (Dragon 32 has no disk drive stock); deferred |
| `rtl/dpram.vhd` (top level), `rtl/dpram_1r1w.vhd` | RAM | Vendor memory primitives — check against Pocket's device family in phase 1 |
| `rtl/ram.v`, `rtl/rom.v`, `rtl/sprom.vhd`, `rtl/chrrom.v` | RAM/ROM wrappers | |
| `rtl/pll/`, `rtl/pll.v`, `rtl/pll.qip` | Clocking | MiSTer-specific PLL IP; replaced by the APF template's `mf_pllbase` |
| `rtl/OVO.vhd` | On-screen overlay (cassette counter) | MiSTer OSD-adjacent; likely dropped, re-add via APF's own OSD path if wanted |
| `rtl/ttl_74LS138.vhd`, `rtl/acia.sv`, `rtl/ps2.v`, `rtl/uart_rx.v`, `rtl/square_gen.v` | Glue logic | Check usage in `dragoncoco.sv` before deciding to port each |
| `rtl/dragoncoco.sv` | Machine top level | The actual CoCo/Dragon machine wrapper — this is what gets instantiated inside our `core_top.v` in phase 1, in place of `CoCo2.sv`'s MiSTer wrapper |
| `sys/` (53 files) | MiSTer framework (`hps_io`, scaler, PLL, OSD) | Confirmed: dropped entirely, replaced by APF |
| `roms/` | ROM helper module (`rom_chrrom.v`) + character ROM | Character ROM (`chrrom`) is font data — need to confirm it's not a copy of the real 6847 font ROM before reuse; treat as ROM-adjacent and check |
| `releases/*.rom`, `releases/*.rbf` | **Not source** | The upstream repo ships prebuilt boot ROM binaries and bitstreams here — real ROM dumps, not placeholders. **Do not vendor this folder into our repo under any circumstance** — it's exactly the ROM content our own "no ROMs" rule excludes |

## Licensing findings (2026-09-26)

No single top-level `LICENSE` file in `CoCo2_MiSTer`. Licensing is per-file,
declared in each file's header comment:

| Files | License | Implication |
| --- | --- | --- |
| `CoCo2.sv`, `wd1793.sv` | GPLv2-or-later | Combined work licensing likely needs to honor GPLv2 for anything derived from these |
| `pia6520.v`, `fdc.sv`, `Cassette_Write.sv` | BSD-style permissive (redistribution with attribution) | Fine to reuse with attribution kept |
| `dac.sv` | Copyright notice, no explicit license terms | Ambiguous — ask upstream or treat cautiously if publishing |
| `keyboard.sv` | Permissive **but explicitly non-commercial only** ("License is granted for non-commercial use only... A fee may not be charged for redistributions") | We don't need this file anyway (replaced by our own Pocket input path), so this doesn't block us — but don't reuse its matrix-mapping logic verbatim if publishing later; re-derive the key matrix from public Dragon 32 documentation instead, to keep the port's licensing clean |
| `mc6809i.v` | Copyright notice (Greg Miller, 2016), no explicit license terms found | Same ambiguity as `dac.sv` |
| `CPU09/*.vhd` | "This core adheres to the GNU public license" (OpenCores, John Kent) | GPL |
| `mc6883.vhd`, `mc6847.vhd`, `mc6847pace.vhd`, `sam.v`, `dragoncoco.sv`, `OVO.vhd`, and others | No license or copyright text at all | Presumably covered by the repo's overall intent (GPL, per `CoCo2.sv`'s header) but not explicitly marked per-file |

**Working conclusion:** treat the whole `rtl/` tree as GPLv2-or-later for our
purposes (that's the license on the actual top-level file, `CoCo2.sv`, and
the most restrictive license present among files with explicit terms other
than the two special cases below), and keep every file's original header
intact when vendoring in phase 1. Two exceptions to flag if this is ever
published: `keyboard.sv`'s non-commercial clause (moot — not reused) and the
unclear terms on `mc6809i.v`/`dac.sv` (reused as-is; worth a note in
whatever public README this core ships with, or a message to the authors).

Already-confirmed-clean sources for everything else the port pulls in:

- `open-fpga/core-template` — no explicit license; carries Analogue's own
  APF Software License Agreement in `src/fpga/apf/*` headers only. Kept
  intact, untouched, in this repo.
- `agg23/analogue-pocket-utils` — MIT (Adam Gastineau). Not yet vendored;
  pull in specific modules (data loader, PSRAM controller, I2S audio) when
  phase 1/2 needs them, keeping the MIT header.

**Never vendor:** `CoCo2_MiSTer/releases/` or `CoCo2_MiSTer/roms/` — see the
inventory table above. Only `rtl/`, `CoCo2.sv` (for reference), and
`dpram.vhd` are candidates for vendoring.

## Answers to the plan's open questions (2026-09-26)

- **Use:** personal, for now — may publish later. Keep licensing clean from
  the start so publishing later doesn't need rework.
- **Input hardware:** Pocket dock and a USB keyboard are both available.
  Confirm in phase 0 whether APF exposes dock USB keyboard input to cores;
  if it does, prioritize it over typed-command macros / on-screen keyboard
  for v1, since it's the most natural way to use Dragon BASIC.
- **Machine scope:** stays Dragon 32 only for now.

## Open items for phase 1

- Confirm whether APF exposes Pocket dock USB keyboard input to cores
  (input plan, above).
- `roms/chrrom` — check what this actually contains before deciding whether
  it's reusable font data or something closer to ROM content.
