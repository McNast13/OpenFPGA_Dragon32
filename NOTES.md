# Notes

Working notes for the port. See [docs/PLAN.md](docs/PLAN.md) for the full
plan.

## Phase 1 status (2026-09-26)

Implemented per the wiring plan below: vendored the confirmed RTL set into
`src/fpga/core/dragon/`, added `dragon_pll.v` (machine clock) and vendored
agg23's `data_loader.sv` into `src/fpga/core/pocket_utils/` (boot ROM
bridge), rewrote `core_top.v`'s video section to instantiate `dragoncoco`
directly instead of the template's test pattern, and added the boot ROM
data slot to `data.json`. Not yet confirmed by CI or hardware — that's the
immediate next step.

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
| `rtl/pia6520.v` | I/O (6821-compatible PIA ×2) | Thomas Skibo's PIA core. Instantiated twice (`pia`, `pia1`) |
| `rtl/keyboard.sv` | Keyboard matrix decode | **Correction (was wrong above): this is an internal submodule of `dragoncoco.sv` itself** (`keyboard kb(...)`, line 688), not something the MiSTer wrapper owns — `dragoncoco.sv`'s top-level `ps2_key` input flows straight into it, and it drives the key matrix that feeds the PIAs internally. We can't swap it out without also reimplementing its scancode→matrix logic, so it's vendored as-is. Its license ("non-commercial use only... a fee may not be charged for redistributions") only restricts *charging money* — a free, personal or later-published-for-free port doesn't trip that clause, so this is fine to keep long-term, not just for now. For phase 1's gate (BASIC banner, no keypress needed) we just drive its `ps2_key` input to "no key pressed" (`11'b0`) |
| `rtl/dac.sv` | Sound (6-bit DAC) | Alan Steremberg |
| `rtl/acia.sv` | Serial (ACIA) | Instantiated (`acia acia(...)`), but only reachable via `acia_cs`, which is gated `dragon64 ? ... : 1'b0` — dead code with `dragon64=0`. Vendored anyway since it's referenced unconditionally at elaboration time |
| `rtl/fdc.sv` | Disk controller | Instantiated (`fdc coco_fdc(...)`) but gated by `disk_cart_enabled` (tied `0` for v1 — no disk support yet). Still needed for the module to elaborate; not functionally exercised until disk support lands |
| `rtl/wd1793.sv` | Floppy controller | **Correction (missed in the first pass): `fdc.sv` instantiates this internally** (four `wd1793` instances) — my first dependency scan only checked `dragoncoco.sv`'s own instantiations, not what its submodules pull in themselves, so this got missed until the first real compile caught it (`Error (12006): ... instantiates undefined entity "wd1793"`). Vendored now. GPLv2 (Viacheslav Slavinsky / Sorgelig) — same bucket as the rest |
| `rtl/Cassette_Write.sv` | Tape write | Instantiated (`Cassette_Write CoCo3_Cassette_Write(...)`) |
| `rtl/dpram.vhd` | RAM (generic dual-port, Altera `altsyncram`) | Used for the 64K-addressable work RAM (`ram1`) and the cartridge ROM window (`romC`) — both fit comfortably on-chip on the Pocket's Cyclone V (see phase 1 plan below) |
| `rtl/dpram_1r1w.vhd` | ROM (generic 1-read/1-write dual-port) | Used for each boot ROM slot (`roms_coco2`, `roms_D32`, `roms_D64`, `roms_disk`) and, inside `mc6847pace.vhd`, for its line buffer |
| `rtl/sprom.vhd` | ROM (single-port, Altera `altsyncram`) | Used inside `mc6847pace.vhd` for the character-generator ROM (`charrom_inst`, loads `mc6847_ntsc.hex`) |
| `rtl/ttl_74LS138.vhd` | Glue (3-to-8 decoder) | Instantiated as `ttl_74ls138_p` |
| `rtl/CPU09/*.vhd`, `rtl/sam.v`, `rtl/mc6847.vhd`, `rtl/cassette.v`, `rtl/ram.v`, `rtl/rom.v`, `rtl/chrrom.v`, `rtl/OVO.vhd`, `rtl/ps2.v`, `rtl/uart_rx.v`, `rtl/square_gen.v`, `rtl/pll*` | Not needed | Not instantiated by `dragoncoco.sv` or any of its submodules — skip all of these |
| `rtl/dragoncoco.sv` | Machine top level | The actual CoCo/Dragon machine wrapper — instantiated as-is inside our `core_top.v` in phase 1, in place of `CoCo2.sv`'s MiSTer wrapper. Full dependency list above is now confirmed complete via a scan for every module instantiation in the file |
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
than the exceptions below), and keep every file's original header intact
when vendoring. Two things worth a note in whatever public README this core
ships with, if published: `keyboard.sv`'s non-commercial clause (satisfied —
we never charge for this) and the unclear terms on `mc6809i.v`/`dac.sv`
(reused as-is; worth a message to the authors if this goes public).

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

## Phase 1 wiring plan (2026-09-26)

`dragoncoco.sv`'s full top-level port list is now mapped against what
`core_top.v` (from the template) already provides:

- **Machine clock:** `dragoncoco.sv`'s `clk` wants ~57.272727 MHz (16× NTSC
  colorburst — a real hardware constant, not tied to any particular
  reference clock rate). The template's existing `mf_pllbase` IP only
  outputs 12.288 MHz and some 133 MHz taps, none close. Rather than
  reconfigure that IP (which is a frozen, pre-generated variation), added a
  second, new PLL instance (`dragon_pll.v`) that directly parameterizes
  Quartus's `altera_pll` primitive the same way `mf_pllbase_0002.v` already
  does — with plain frequency-string generics (`reference_clock_frequency`,
  `output_clock_frequency0`) rather than pre-baked M/N/C values. Quartus's
  own synthesis resolves the actual PLL counters from those strings at
  compile time, the same as the existing IP already does — no IP wizard or
  local Quartus needed, confirmed by reading how the template's own PLL is
  built. Feeds `clk_74a` (74.25 MHz) in, `dragoncoco.clk` out.
  - Getting this frequency bit-exact isn't necessary for phase 1's gate
    (BASIC banner, not broadcast-accurate video) — that precision matters
    for phase 2's video/audio-timing gate, not this one.
  - **Update after CI feedback:** it's currently driven at 14.85 MHz, not
    57.27 MHz. CI's fitter found real timing closure problems in the
    machine RTL itself (most likely `mc6809i.v`'s combinational decoder) —
    a worst-case ~-10 ns setup slack against a ~17.3 ns period implies an
    actual critical path around 27 ns, i.e. a genuine ~36 MHz ceiling on
    the Pocket's Cyclone V part (`5CEBA4F23C8`, speed grade C8 — smaller
    and slower-graded than the C6 part on MiSTer's DE10-Nano this RTL was
    written against). 14.85 MHz gives generous headroom below that ceiling
    at the cost of running the machine at roughly a quarter of real-time
    speed for now. Digital correctness doesn't depend on clock rate, only
    perceived speed and video refresh rate do, so this is fine for phase
    1's gate. Revisit in phase 2 (which needs correct video/audio timing
    anyway) with a real `report_timing -detail full_path` pass to find the
    actual critical path and how close to 57.27 MHz is genuinely safe —
    see BUILD_LOG.md's CI run #5–#9 entries for the full debugging trail.
- **`CLK50MHZ`:** only reaches live logic through `fdc.sv`'s disk timing,
  which is dead code while `disk_cart_enabled = 0`. Tied directly to
  `clk_74a` rather than generating a third clock domain for no functional
  reason yet.
- **Boot ROM loading:** `dragoncoco.sv` expects MiSTer's `ioctl_*` streaming
  protocol (`ioctl_data/addr/wr/download/index`), not APF's bridge/data-slot
  protocol. agg23's `data_loader.sv` (MIT, from `analogue-pocket-utils`)
  translates APF data-slot writes into exactly this ioctl shape — that's the
  whole reason the plan called for reusing it instead of writing a new
  bridge. One data slot, feeding `ioctl_index = 8'h40` (`{BOOT1, BOOT}` per
  `dragoncoco.sv`'s own constants — `BOOT1=2'd1`, `BOOT=6'd0`) to land the
  ROM in the Dragon 32 boot slot specifically (not the CoCo2/Dragon64/disk
  slots also multiplexed on that same bus).
- **Video:** `dragoncoco.sv` already outputs `red/green/blue[7:0]` and
  `hblank/vblank/hsync/vsync` directly — no need for the template's own
  test-pattern generator or its 12.288 MHz video clock. Plan is to drive
  `video_rgb`/`video_de`/`video_hs`/`video_vs` straight from the machine's
  own signals, clocked by the machine's own `clk` (`video_de = ~hblank &
  ~vblank`), rather than resample into the template's unrelated timing.
- **Controller input:** `cont1_key`'s d-pad bits map to `joy1`'s digital
  bits, `joy_use_dpad = 1`. `joya1/joya2` (analog) left at 0 for now.
- **Keyboard (`ps2_key`):** driven to `11'b0` (no key ever pressed) for
  phase 1 — the Dragon 32 boots straight to its BASIC prompt without
  needing a keypress, so real key injection is still phase 3's problem, not
  this gate's.
- **Tied off / deferred, all safe because their gating signals are 0:**
  `disk_cart_enabled=0` (disk), `casdout/cass_snd/CASS_REWIND_RECORD=0`
  (tape in), `img_mounted/img_readonly/img_size/sd_ack/sd_buff_*=0` and the
  `sd_lba/sd_rd/sd_wr/sd_buff_din` outputs left unconnected (disk SD block
  interface — `fdc.sv` still elaborates and runs, just produces nothing
  anyone reads), `roms_reset` tied to the core's reset.
- **Cartridge:** no data slot yet in phase 1 (that's phase 3's "loading and
  control" milestone) — `load_cart` will simply never fire, so `romC`
  reads back whatever the (empty, `cart_loaded=0`) cart RAM holds. Harmless
  for the boot-to-BASIC gate.

## Debugging the gray screen (2026-09-26)

Phase 1's first hardware test showed a solid gray screen — visually
indistinguishable from phase 0's test pattern (which is also a solid gray,
RGB 60/60/60). Confirmed on a second test (power-cycled, not just a stale
core still open) that this is the new build actually doing this, not phase
0 still running.

The problem with diagnosing this from the picture alone: if `clk_dragon`
(from `dragon_pll`) isn't actually a good, locked clock on real hardware,
driving `video_rgb_clock` from it directly (the original phase 1 design)
wouldn't show *anything* — and a scaler with no valid input clock showing
a neutral gray "no signal" screen would look exactly like what was
reported. So the report doesn't distinguish "the machine is stuck
somewhere" from "there's no real problem in the machine, just the video
wiring can't be trusted to show it."

Pushed a temporary diagnostic build (see `core_top.v`'s "TEMPORARY
DIAGNOSTIC BUILD" comment) that drives the scaler from `clk_core_12288`
(mf_pllbase's output — proven working since phase 0, entirely independent
of `dragon_pll`) and shows one of four solid colors instead of real video:

| Color | Means |
| --- | --- |
| Red | `dragon_pll` (`dp1`) never locked |
| Blue | `dp1` locked, but `reset_n_dragon` never released |
| Yellow | Reset released, but the boot ROM was never written at all |
| Green | All three look fine — bug is elsewhere (most likely inside `dragoncoco`'s own video timing, or the CPU not executing correctly) |

Whatever color comes back narrows this down a lot before spending another
round on a specific fix. Revert to real video passthrough (git history has
the original version) once the cause is known.

**Result: yellow** (after fixing an unrelated `cp -R` bug that meant the
real phase 1 build had never actually reached the SD card before this —
see BUILD_LOG.md). PLL locked, reset released, but the boot ROM was never
written into the machine at all.

## Boot ROM never loading: the `deferload` field (2026-09-26)

Checked Analogue's own developer docs (`analogue.co/developer/docs/openfpga/...`)
plus two real cores for how data slot loading actually works:

- **`agg23/openfpga-pokemonmini`**'s "Cartridge" slot (`required: true`,
  fixed nothing — no `filename`, no `deferload`) loads with zero explicit
  request from the core — `core_top.v` never references
  `target_dataslot_read` anywhere in that repo at all.
- **`dave18/OpenFPGA_ZX-Spectrum`**'s "ROM" slot (`required: true`,
  `filename: "boot.rom"`, **`deferload: true`**) — its core *does* pull it
  explicitly: `if (ioctl_id=='h200) target_dataslot_read<=1; ...` with a
  whole state machine around it, matching the docs' Data Slot Read target
  command (slot id, slot offset, bridge address, length).

My own `data.json` copied ZX-Spectrum's slot verbatim, `deferload: true`
included — but never implemented the matching `target_dataslot_read`
request logic ZX-Spectrum's core actually has. Best explanation:
`deferload: true` means "don't push this automatically — wait for the core
to ask," and I copied the flag without copying what it obligates the core
to do.

Fix: dropped `deferload` from `data.json` entirely, matching
PokemonMini's simpler, request-free pattern (also simplified `id` from the
ZX-Spectrum-style `"0x200"` to a plain `0`, matching PokemonMini too —
`id` is just a 16-bit identifier per the docs, nothing in this core checks
it). Much lower-risk than implementing a `target_dataslot_read` state
machine, and matches the officially-simpler intended pattern for a
`data_loader.sv`-based core.

If yellow persists after this, the next thing to try is implementing the
explicit request (ZX-Spectrum's state machine is the reference for how).

**Result: green.** Dropping `deferload` fixed the boot ROM load. PLL
locked, reset released, ROM loaded — all three gates confirmed good.
Reverted `core_top.v` back to real video passthrough (diagnostic overlay
removed) to see whether the actual BASIC banner now appears.

## Debugging the stuck @ screen (2026-09-26)

Real video passthrough showed 16 rows of "@" — the VDG's own decode of
all-zero video RAM (a well-known Dragon/CoCo "uninitialized text screen"
pattern: character code 0 decodes as "@"), not the actual BASIC banner.
Waited well past what our ~4x-slowed clock should plausibly need
(15–30s) — no change. Genuinely stuck, not just slow.

Added two more debug taps directly on `dragoncoco.sv` (temporary — see
its own "TEMPORARY DEBUG TAPS" comment, and its port list, for exactly
what was added and where to remove it later): `dbg_cpu_addr` (the CPU's
own internal `cpu_addr` bus) and `dbg_reset_n` (`dragoncoco.sv`'s *own*
internal reset counter's output — distinct from our `reset_n_dragon`,
which only gates the top-level `trig_reset_n` input; `dragoncoco.sv`
stretches that into its own ~256-cycle power-on reset internally).

Extended the diagnostic overlay (round 2) with two more gates: does
`dragoncoco`'s internal reset ever release (orange if not), and does
`cpu_addr` ever change at all in the first ~0.75s (magenta if frozen,
green if it moved) — using two timed snapshots on the same safe
`clk_core_12288` domain as before. Whatever this comes back as narrows
"is the CPU actually executing" from "is it executing wrong/writing to
the wrong place."

**Result: magenta.** Internal reset released, `cpu_addr` never moved at
all in half a second — genuinely halted, not just slow (ruled out
coincidental same-address sampling: at our clock rate, half a second is
tens of thousands of real CPU cycles even accounting for the slowdown).

Checked `mc6809i.v`'s NMI handling: it's edge-triggered
(`~NMISample & NMISample2`), not level-sensitive, so a stuck-high `nmi`
line (sourced from `fdc`'s `NMI_09` — plausible territory given
`disk_cart_enabled=0`) would only fire once, not explain a persistent
freeze on its own. Checked `dragoncoco.sv`'s own `halt` signal: it's
hardwired `dragon ? 1'b0 : fdc_halt` — with `dragon=1'b1`, `halt` is a
constant 0 regardless of the disk controller, ruling that out too.

Next suspect: `mc6883` (SAM) generates the CPU's own `clk_E`/`clk_Q`
pacing clocks from `clk` — per `mc6809i.v`'s own comments, its sequencer
only advances on `Q`/`E` edges, so if SAM's E/Q generation is stuck for
any reason, the CPU freezes regardless of its reset state. Added a third
debug tap, `dbg_clk_e` (dragoncoco's internal `clk_E`), with a sticky
toggle-detector (round 3): does `clk_E` ever toggle at all?

|Color|Means|
|-|-|
|White (new)|Internal reset released, but SAM's `clk_E` never toggled — points at SAM/clocking, not the CPU or memory|
|Magenta (redefined)|`clk_E` *is* toggling, but `cpu_addr` still never changed — genuinely CPU-specific|

**Result: magenta again.** `clk_E` toggles fine — ruled out SAM/clocking.
Genuinely CPU-specific: valid clock, valid reset, address bus still frozen.

Round 4: rather than another yes/no gate, show *where* it's frozen. Split
the frozen address's top 2 bits across the Dragon 32 memory map (RAM low
`$0000-3FFF`, RAM high `$4000-7FFF`, ROM `$8000-BFFF` — where `boot.rom`
lives — or cart/IO/vectors `$C000-FFFF`, including the reset vector at
`$FFFE`) into four distinct colors, replacing the single magenta case:

|Color|Frozen in|
|-|-|
|Magenta|RAM low (`$0000-3FFF`)|
|Cyan|RAM high (`$4000-7FFF`)|
|Purple|ROM (`$8000-BFFF`)|
|Pink|Cart/IO/vectors (`$C000-FFFF`)|

Purple would suggest a stuck loop inside otherwise-valid ROM code; pink
would point at a bad reset/interrupt vector fetch; either RAM color would
suggest something jumped into uninitialized memory (a stack problem, or a
vector pointing into RAM instead of ROM).

**Result: pink** (confirmed via brightness, not hue, since the user is
slightly colorblind — light/pale, not dark/saturated) — frozen somewhere
in `$C000-FFFF`: cart/IO/vector space, including the reset vector at
`$FFFE-FFFF`, the PIA1/PIA2 registers (`$FF00-FF3F`), and SAM's own
registers (`$FFC0-FFFF`).

Round 5 narrows this further with one more check, switching to plain
primary/neutral colors going forward (red/blue/yellow/black/white/green
only — no more magenta/cyan/purple/pink) per the user's preference: is the
frozen address *exactly* `$FFFE` or `$FFFF` (black — the CPU never even
got past fetching its own reset vector) or somewhere else in that range
(white — it fetched *something* and is stuck wherever that pointed).

**Result: black.** The CPU is permanently stuck re-addressing exactly
`$FFFE`/`$FFFF` — its own reset vector, the very last 2 bytes of the 16KB
ROM. That specific location is the clue: `data_loader`'s
`WRITE_MEM_CLOCK_DELAY`/`WRITE_MEM_EN_CYCLE_LENGTH` were copied from
PokemonMini's `(12, 5)` verbatim, but PokemonMini's `clk_memory` runs at
40MHz — ours (`clk_dragon`) is only 14.85MHz (the phase 1 timing-closure
trade), so those same 12 cycles take ~808ns against APF's own documented
~1010ns-per-word bridge cadence — only ~20% margin. A transfer that
cumulatively falls behind under a tight margin would most plausibly
corrupt whatever arrives *last* — exactly the reset vector. Dropped to
`(4, 1)`, `data_loader.sv`'s own documented minimum, for much more margin
(~269ns). Kept the diagnostic overlay in place for one more test: green
would confirm this was it; anything else means the theory's wrong.

**Result: black again** — identical to before, despite the timing fix.
That ruled out the transfer-margin theory outright (it wasn't marginal;
changing the margin changed nothing at all).

Checked the actual `~/Downloads/d32.rom` file directly (no hardware round
trip needed) — its real bytes at offset `$3FFE-3FFF` are `B3 B4`, a
perfectly normal reset vector pointing into ROM space. Not `$FFFE`/`$FFFF`
at all, and not corrupted. So the ROM content was never the problem — the
CPU isn't jumping to a bad vector value, it's never *completing* the
vector fetch at all, and stays parked exactly where that fetch started.

That reopens a real gap in round 3's `clk_E` check: it only asked "did
`clk_E` ever toggle even once" — a single edge right as reset releases
would already satisfy that without `clk_E` continuing to toggle
afterward. Replaced it with a proper watchdog: is `clk_E` still actively
toggling (no more than ~10ms since its last edge) right before the second
snapshot, not just "did it ever move." Same white/(reused-colors) scheme
otherwise.

While waiting on that build, reconsidered rather than immediately queuing
another round: `clk_E` was the only signal ever tapped from SAM's clock
generation — never `clk_Q`, the CPU's *other* required phase (per
`mc6809i.v`'s own clocking comments, both matter). Added the same
watchdog for `clk_Q` in the same build, so one hardware test now checks
both rather than needing a separate round if `clk_E` turns out fine and
`clk_Q` is the actual problem. New color: **gray** (`clk_E` fine, `clk_Q`
stalled) — distinguishable from white/black by brightness alone, not hue,
per the colorblind-friendly preference.

## Open items for phase 1

- Confirm whether APF exposes Pocket dock USB keyboard input to cores
  (input plan, above) — needed for phase 3, not this gate.
- `roms/chrrom` — check what this actually contains before deciding whether
  it's reusable font data or something closer to ROM content. Not used by
  the active `mc6847pace.vhd` path (it uses `sprom`/`mc6847_ntsc.hex`
  instead), so not blocking phase 1.
