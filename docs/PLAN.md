# Dragon 32 for Analogue Pocket: port plan

Checked 2026-09-25. Mirrored here from the planning doc so it's available
offline; see that doc for live edits.

## Goal and scope

Build a Dragon 32-only openFPGA core for the Analogue Pocket by trimming the
existing CoCo2/Dragon MiSTer core and replacing its MiSTer-specific plumbing
with Analogue Platform Framework (APF) equivalents. Claude Code does the
coding and Quartus builds; you test on the Pocket and report back.

**Version 1 (first working core):**

- Boots to Dragon BASIC with correct video, sound and keyboard input.
- Loads the Dragon 32 boot ROM from the SD card at startup.
- Loads tape images (.CAS) and cartridge images (.ROM) through Pocket data
  slots.
- Maps the Pocket d-pad and buttons to a joystick, plus a working way to
  type.

**Later versions:** disk support (DragonDOS, VDK images), saving to tape,
save states, Dragon 64 and CoCo modes, Analogizer video.

**Not included:** any ROMs or software. You supply your own Dragon 32 ROM
and games, as the MiSTer core also requires.

## Starting point

The source is the [MiSTer-devel CoCo2_MiSTer](https://github.com/MiSTer-devel/CoCo2_MiSTer)
repo (69 commits when checked). It covers the Tandy CoCo 2 plus the Dragon 32
and 64, with 64K memory, two analog joysticks, cassette loading and saving,
sound, cartridges and disks. It began as pcornier's coco2 core and was
completed by dshadoff, alanswx, pcornier, shodge12 and theflynn49.

No Dragon or CoCo core was found in the part of the
[openFPGA Library](https://openfpga-library.github.io/analogue-pocket/)
listing that could be read (the page was cut off partway) — check the full
list before starting.

Repo layout, from the file listing:

| Path | What it is |
| --- | --- |
| `CoCo2.sv` | Top-level emu module: the MiSTer wrapper to replace |
| `rtl/` | Machine RTL. Contents not inspected (GitHub blocked the listing), so the first task is to inventory it |
| `sys/` | MiSTer framework (hps_io, scaler, PLL and so on): dropped in a Pocket port |
| `roms/` | ROM folder (contents not inspected) |
| `CoCo2.qpf`, `CoCo2.qsf`, `files.qip` | Quartus project files |
| `dpram.vhd` | Dual-port RAM wrapper |

Precedent ports show the route is well travelled:

| Project | Why it matters here |
| --- | --- |
| [dave18 OpenFPGA_ZX-Spectrum](https://github.com/dave18/OpenFPGA_ZX-Spectrum) | A MiSTer home computer core ported to the Pocket: closest match in kind |
| [opengateware computer-msx](https://github.com/opengateware/computer-msx) | 8-bit computer core with keyboard handling on Pocket |
| [desaster openfpga-PCXT](https://github.com/desaster/openfpga-PCXT) and [vector06c](https://github.com/desaster/openfpga-vector06c) | More computer ports, useful for input and tape or disk loading patterns |
| [agg23 analogue-pocket-utils](https://github.com/agg23/analogue-pocket-utils) | Reusable IP: PSRAM controller, data loader and unloader, hex loader, I2S audio |
| [janisc openfpga-NGPC](https://github.com/janisc/openfpga-NGPC) | A Claude-assisted MiSTer-to-Pocket port, showing the workflow works |
| [plasticbugs pocket-core-template](https://github.com/plasticbugs/pocket-core-template) | Working skeleton with PLL, memory, ROM download, video, audio and CI (arcade-oriented) |

## Dragon 32 hardware and what the core must model

The Dragon 32 is a small machine, and it shares its chip family with the
CoCo 2, which is why one MiSTer core covers both. The table below is from
general knowledge of the hardware, not from the repo, so treat it as the
checklist to confirm against the code.

| Block | Part | Job | Port note |
| --- | --- | --- | --- |
| CPU | Motorola 6809E | Runs at roughly 0.89 MHz | Small; keep the existing soft core |
| Memory controller | 6883 SAM | Address decode, memory map, clocks, video addressing | Keep as is; timing-critical |
| Video | 6847 VDG | Text, semigraphics and graphics modes, 256x192 active area | Needs timing and scaling work for the Pocket screen |
| I/O | Two 6821 PIAs | Keyboard matrix, joysticks, tape, sound, VDG mode pins | Keep; input source changes |
| RAM | 32K usable | Program and video memory | Fits on-chip or in Pocket SRAM; decide in phase 1 |
| ROM | 16K Microsoft BASIC | Boot ROM (`d32.rom` per the MiSTer readme) | Load from SD through a data slot |
| Cartridge port | ROM cartridge | Games and utilities | Load an image into cart space via a data slot |
| Tape | Audio in and out via PIA | Cassette loading | Feed .CAS data through a data slot |
| Sound | 6-bit DAC on a PIA | Beeper and game audio | Route to the Pocket I2S audio output |

**What to remove for Dragon 32 only:** the CoCo 2 and Dragon 64 machine
options, the 64K memory mapping, the extra ROM banks (`boot0`, `boot2`), and
the machine selector in the OSD. This shrinks the design and may sidestep
the green screen some MiSTer forum users reported when switching to Dragon
mode; the cause is not confirmed.

**Display note:** the Dragon is a PAL machine at 50 Hz, unlike the NTSC
CoCo. Whether the Pocket scaler accepts that timing cleanly is an open
question (see risks).

## MiSTer to Pocket: what has to change

The machine RTL should move over largely unchanged. Nearly all the work is
in the wrapper around it. Names on the Pocket side follow the standard
openFPGA template layout and Analogue's developer docs; confirm each against
the template in phase 0.

| MiSTer piece | Pocket replacement | Notes |
| --- | --- | --- |
| `CoCo2.sv` top module | APF top level (`core_top`) instantiating a new Dragon 32 machine wrapper | Biggest rewrite |
| `sys/` framework, `hps_io` | APF bridge plus Analogue-supplied framework files | Drop `sys/` entirely |
| File loading (`ioctl_download`) | Data slots defined in `data.json`, fed by agg23's `data_loader` | One slot each for boot ROM, cartridge and tape |
| OSD menu and status bits | `interact.json` core settings and the Analogue OS menu | Replaces machine, joystick swap and similar options |
| PLL and clock setup | Pocket PLL IP fed by the APF 74.25 MHz clocks | Derive the Dragon clocks; keep video and system clocks in step |
| SDRAM / external memory | On-chip RAM first; agg23's PSRAM controller if needed | 32K RAM plus 16K ROM is small; avoid external memory in v1 |
| Video output and scaler | APF video interface plus `video.json` scaler settings | 256x192 active area; border and aspect choices to test |
| Audio out | I2S output (agg23 IP) | Convert the 6-bit DAC output to 16-bit samples |
| Joystick and PS/2 keyboard inputs | APF controller signals | See the input plan |
| Tape save (`ioctl_upload`) | Data unloader and save slot | Deferred past v1 |
| Quartus project (`CoCo2.qpf`, `.qsf`) | Template Quartus project for the Pocket FPGA | Pin and IP assignments come from the template, not the MiSTer project |

The machine RTL itself needs three checks. Vendor-specific memory primitives
may need swapping for the Pocket's device family. Any MiSTer clock-enable
assumptions must be kept intact. And timing must be re-closed, since the
Pocket FPGA is a different part from the MiSTer's.

## Input plan

The Dragon needs a full keyboard and the Pocket has none, so input is the
main design decision. Recommendation: a joystick mapping plus auto-typed
commands in v1, then an on-screen keyboard.

| Option | Works undocked | Effort | Verdict |
| --- | --- | --- | --- |
| D-pad and buttons as the Dragon joystick | Yes | Low | Do in v1. The d-pad is digital, so it maps to the joystick's extremes and centre |
| Menu-triggered typed commands (`CLOAD`, `CLOADM`, `EXEC`, `RUN`) | Yes | Low to medium | Do in v1. Core injects key presses from a settings action |
| On-screen keyboard overlay driven by the d-pad | Yes | Medium | v1.5. Best general answer for a handheld |
| USB keyboard on the dock | No | Unknown | Check whether APF exposes a dock keyboard to cores; if it does, add it |
| Physical key mapping on Pocket buttons | Yes | Low | Fallback for a handful of game keys such as space and enter |

The Dragon keyboard is read as a matrix through the PIAs. All the options
above end in the same place: setting bits in that matrix, so build one
internal key-injection path first and let each input option feed it.

## Toolchain and build setup

Quartus availability was assumed but not confirmed for this dev environment
when the plan was written — **checked now: no local Quartus or Docker in
this sandbox.** Follow the sibling `../OpenFPGA_ZX-Spectrum` repo's proven
pattern instead: build via GitHub Actions using a Quartus Docker image, and
download the packaged zip artifact from the workflow run to test.

- **Quartus versions seen in Pocket projects:** Quartus Prime 18.1 Lite in
  the `raetro/quartus:pocket` (or `raetro/quartus:18.1`) Docker image (used
  by the plasticbugs template and by `../OpenFPGA_ZX-Spectrum`), and 22.1 in
  `didiermalenfant/quartus:22.1-apple-silicon` (used by the Varvara core).
  Default to 18.1 to match the sibling project's precedent unless a reason
  turns up to differ.
- **Build command** from those projects: `quartus_sh --flow compile ap_core`
  (or `.qpf` name as applicable). The fitter is memory-hungry; the template
  docs suggest about 8 GB for Docker under emulation.
- **Bitstream format:** the Pocket loads a bit-reversed `.rbf` (`.rbf_r`).
  The template's build scripts normally produce it; confirm in phase 0.
- **Reference emulator:** XRoar, a Dragon and CoCo emulator that MiSTer
  forum users mention. Use it to compare expected behaviour for boot, video
  and tape loading.
- **Simulation:** Verilator test benches for the CPU, SAM and PIA
  interactions where a behaviour is unclear. The plasticbugs template shows
  a bench-driven method built around a reference emulator.
- **Reusable Pocket IP:** agg23's
  [analogue-pocket-utils](https://github.com/agg23/analogue-pocket-utils)
  supplies the data loader, PSRAM controller and I2S audio. Prefer it to
  writing these again.
- **Test loop:** Claude Code builds and packages the core as a zip (via CI,
  given no local Quartus). You copy it to the Pocket's SD card (Cores,
  Platforms and Assets folders), load a game, and report what you see. A
  USB SD-access option under the Pocket's developer settings saves swapping
  cards.

## Phased milestones

Work in five phases, and do not start the next until you have tested the
gate on real hardware. Phase 3, the first playable core, is the milestone
that matters most.

| Phase | Work | Gate |
| --- | --- | --- |
| 0 · Bring-up | Template core builds in Quartus (via CI) and runs on the Pocket | Test pattern shows on the Pocket screen |
| 1 · Machine | Dragon 32 RTL inside the APF wrapper, boot ROM loaded from SD | Dragon BASIC banner and prompt appear |
| 2 · Video and audio | Correct picture through the Pocket scaler, sound through I2S | Text, graphics modes and beeps match XRoar |
| 3 · Loading and control | Cartridge and tape data slots, d-pad joystick, typed commands | A game loads from tape or cartridge and is playable |
| 4 · Packaging | Settings menu, platform image, release zip, install notes | Clean install from the zip works on a fresh SD card |

At each gate, a build is produced (via CI, see above); you copy it to the SD
card, run the check and report what you saw. Later work (disk support, tape
saving, save states, on-screen keyboard) comes after the phase 4 gate.

## Risks, open questions and licensing

The main risk is the hardware loop: builds can be written and compiled, but
only you can see them run on a Pocket.

| Risk | Why it matters | Fallback |
| --- | --- | --- |
| Video timing | The Dragon is a 50 Hz PAL machine; whether the Pocket scaler accepts it cleanly is unconfirmed | Test early in phase 2; try alternative timing or frame handling if the picture judders |
| No keyboard | BASIC needs typing; the dock's USB support for keyboards is unconfirmed | Typed-command macros, then the on-screen keyboard |
| Upstream quality | MiSTer forum posts from 2020 and 2021 report a green screen in Dragon mode and tapes that would not load. The current readme lists disk support, so those reports may be out of date | Compare behaviour against XRoar and fix in the port |
| Timing closure and fit | The Pocket FPGA is a different part from the MiSTer's; the design is small, so risk is low but unmeasured | Report the numbers from Quartus; adjust clocks or memory placement |
| Unverified assumptions | The contents of `rtl/`, the exact Quartus version and the APF signal names were not checked | Phase 0 inventory and template build settle all three |
| Tape and cartridge formats | The MiSTer core takes .CAS tapes; VDK is a disk format and needs separate work | Support .CAS and .ROM in v1; add VDK with disk support later |

**Open questions:**

- Is this for personal use only, or for publishing? Publishing raises the
  licensing and packaging bar.
- Is there a Pocket dock and USB keyboard to test with, or is undocked play
  the priority?
- Is CoCo 2 or Dragon 64 support wanted later, or should the core stay
  Dragon 32 only?

**Licensing:** the upstream licence was not visible on the repo page —
check the LICENSE file first. The NGPC port credits agg23's PSRAM and data
loader modules as MIT, and states that Analogue's APF files carry
Analogue's own software agreement in their headers. Keep every header
intact. Do not distribute a Dragon ROM or commercial games with the core.

## Sources

All checked on 25 September 2026. The hardware table above comes from
general knowledge, not from these pages.

- [MiSTer-devel/CoCo2_MiSTer](https://github.com/MiSTer-devel/CoCo2_MiSTer) — repo layout, features, ROM setup and credits
- [MiSTer FPGA Forum: CoCo 2 + Dragon 32/64 thread](https://misterfpga.org/viewtopic.php?t=1418&start=75) — user reports on Dragon mode, tapes and XRoar
- [MiSTer FPGA Forum: Dragon32 core file formats](https://misterfpga.org/viewtopic.php?t=3051) — .CAS and VDK handling
- [openFPGA Library, Analogue Pocket](https://openfpga-library.github.io/analogue-pocket/) — existing cores and computer-core precedents (listing was cut off partway)
- [open-fpga/core-template](https://github.com/open-fpga/core-template) — openFPGA core starter
- [agg23/analogue-pocket-utils](https://github.com/agg23/analogue-pocket-utils) — data loader, PSRAM controller, I2S audio
- [plasticbugs/pocket-core-template](https://github.com/plasticbugs/pocket-core-template) — Quartus 18.1 Lite Docker image, bench method, CI
- [tsalvo/openfpga-varvara](https://github.com/tsalvo/openfpga-varvara) — Quartus 22.1 Docker build command
- [janisc/openfpga-NGPC](https://github.com/janisc/openfpga-NGPC) — Claude-assisted port and licence notes
- [Analogue developer docs](https://www.analogue.co/developer/docs/overview) — core structure and Pocket FPGAs
- [Time Extension: Pocket openFPGA cores](https://www.timeextension.com/guides/all-analogue-pocket-openfpga-cores-and-where-to-download-them) — USB SD access setting
