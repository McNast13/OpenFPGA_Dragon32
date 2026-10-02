# Plan: run the Dragon at its real speed

Status: **plan, not started** (2026-10-02).

## Where we are

`clk_dragon` runs at 14.85 MHz instead of the 57.272727 MHz the RTL was
written for (`dragon_pll.v`). Every Dragon clock is a fixed division of
`clk_dragon`, so the machine is uniformly ~26% speed: CPU 0.232 MHz
instead of 0.895 MHz, ~15 fps, tape loads ~4x long (JSW: 12 min instead
of ~3), sound ~2 octaves low.

That trade was made because early CI builds at ~57.27 MHz failed timing:
worst setup slack ~-10 ns and **TNS ~-11,000 ns** (thousands of failing
paths, not one bad one). We only ever saw summary numbers, never the
actual failing paths.

## What the ZX Spectrum core does (the model to copy)

`OpenFPGA_ZX-Spectrum/src/fpga/core/core_top.sv` + `core_constraints.sdc`:

1. **One fast system clock** from the PLL; nothing in the machine gets a
   slow clock of its own.
2. **Clock enables** (`ce_cpu_p/n`, `ce_7mp`, `ce_tape`, `ce_wd1793`...)
   from a counter decide when each part actually advances.
3. **Multicycle timing exceptions** for everything that only advances on
   an enable - e.g. `set_multicycle_path -from {ic|cpu|*} -setup 2 /
   -hold 1` - so Quartus checks those paths against the real time they
   have (several clock periods), not one.
4. `derive_pll_clocks` / `derive_clock_uncertainty` at the top of the SDC.

## Why this fits the Dragon

The Dragon RTL is *already* built like step 1 and 2 - it just never got
step 3:

- **SAM** (`mc6883.vhd`) runs on `clk` and makes enables: `Tm` divides by
  4 (`clk_14M318_ena`), `PROC_MAIN` then walks 16 states per CPU cycle and
  drives `clk_e`/`clk_q` as plain signals. One CPU cycle = **64 `clk`
  cycles**.
- **CPU** (`mc6809i.v`) registers `a/b/x/y/s/u/pc/cc/CpuState...` update
  only in `always @(negedge clk)` *when E has just fallen* - once per 64
  clocks. Its big combinational `*_nxt` decoder has 64 clocks to settle,
  but Quartus currently checks it as if it had **half** a clock (8.7 ns at
  57 MHz - `negedge` registers fed from `posedge` ones). That almost
  certainly explains both the -10 ns slack and the huge TNS.
- PIAs advance on `clk_ena` (SAM's `spd_ena`), the VDG on `VClk` - again
  once every 4+ clocks.

So the problem is most likely missing timing constraints, not a design
too slow for the chip.

## Steps

### 1. Measure first (one CI build, no hardware test)
- Add a `quartus_sta` step to `.github/workflows/build.yml` that writes
  `report_timing -npaths 200 -detail summary` (setup + hold) for the
  `clk_dragon` domain into the `quartus-reports` artifact.
- Temporarily set `dragon_pll.v` to 57.272727 MHz (`fractional_vco_
  multiplier("true")`) and build, expecting timing to fail - the point
  is the report. Confirm which modules the failing paths are in (expect
  `cpu|*` and paths into it from RAM/ROM/PIA/SAM).

### 2. Add ZX-style constraints
- `derive_pll_clocks` + `derive_clock_uncertainty` at the top of
  `core_constraints.sdc`.
- Multicycle on the CPU, `-from` and `-to` `{ic|dragon|cpu|*}` (exact
  hierarchy from step 1's report). Start conservative: **setup 4 / hold
  3** - SAM's finest step is every 4 clocks, so 4 is safe for anything
  SAM-paced, and the CPU's real budget (64) is far above it. Raise it
  only if 4 doesn't close.
- Same treatment, if the report shows them failing, for the PIAs and VDG
  (enabled every 4 clocks) and the SAM's own enabled processes.
- **Do not** relax `video_frame_buffer`'s read side, the cassette loader
  or the bridge/`data_loader` paths - they're real full-rate logic.
- Remove the cassette diagnostic square (the coloured 32x32 patch in the
  top-right of the picture). Its job - debugging tape loading - is done,
  and it's now just clutter on screen. It's in `core_top.v` from the
  `TEMPORARY DIAGNOSTIC` comment (~line 829): `cas_stall_watchdog`, the
  `dbg_*` signals, `cas_diag_color` and `cas_diag_patch`. Tie
  `video_frame_buffer`'s `wr_overlay_en` to 0, or remove the overlay ports
  from `video_frame_buffer.sv` altogether (keep them if the on-screen
  keyboard will draw through them - decide then). Doing it in this step
  also matters for the speed change itself: the watchdog's "~1 s" is a
  hard-coded `14_850_000` clock count that would be wrong at 57 MHz.
- Remove the now-unused `clk_dragon_90deg` output if nothing uses it any
  more (the scaler moved to `clk_core_12288` with the frame buffer).

### 3. Switch to 57.272727 MHz and build
- Pass = timing met at the slow corner. If close but not quite, try
  Quartus seed/effort options next (the ZX core is fitted with similar
  settings).

### 3b. Fallback if step 3 can't close: 28.636 MHz
- Half of 57.27, so period 34.9 ns. Change SAM's `Tm` so its normal-speed
  enable fires every 2 clocks instead of 4 (same 0.895 MHz CPU), keep the
  multicycle constraints (halved). Side effect: the Dragon's "fast" POKE
  (1.79 MHz) would need an enable every clock - still possible at this
  rate. More RTL change in vendored code, so only if step 3 fails.

### 4. Tape (`cas_player.sv`)
- Bit timings are fixed counts of `clk_dragon` cycles worked out from the
  57.27 MHz reference (`HALF_PERIOD_BIT1/0`). **At 57.27 MHz they become
  exactly right with no change** - the comment block explaining the scaling
  needs updating, that's all.
- For the 3b fallback they'd be 2x too long - change them to a
  `CLK_HZ` parameter so they're computed from whatever the clock is.
- Re-run `tb_cas_fullfile.sv` after either change.
- Result: JSW loads in ~3 min instead of 12. A "fast load" (making tape
  loading run faster than real time, like the ZX core's turbo-while-
  loading) is a separate, later feature - not part of this plan.

### 5. Sound
- Pitch corrects itself: tones come from CPU timing loops, and
  `sound_i2s` handles the cross-clock transfer at any core clock. No
  change needed for correctness.
- Optional, separate: tape audio through the speaker (`cass_snd` is tied
  to 0; real hardware can route the tape to the speaker through the
  analogue mux), and a simple filter if the 6-bit DAC sounds harsh.

### 6. Video
- The write side follows the machine (~60 fps after this). The read side
  is a fixed timing from `clk_core_12288` (~46 Hz) - it still works, but
  60 fps in, 46 fps out will drop frames and may judder on scrolling.
  Follow-up: retune the frame buffer's output timing to ~60 Hz.
- Retune it to match whatever the machine produces (60 Hz NTSC, or 50 Hz
  if step 8 is done).

### 8. UK 50 Hz (PAL) timing - after steps 1-4 work
A real UK Dragon 32 uses the same NTSC-only 6847 video chip as the US CoCo.
It gets to 50 Hz by adding extra blank border lines: 262 lines per frame
becomes 312 (262 x 60 ≈ 312 x 50). The CPU speed is essentially the same
(the UK crystal is within ~1% of the CoCo's).

The vendored VDG (`mc6847pace.vhd`) already has the hook: the top and
bottom border constants carry a commented-out `-- + 25 for PAL`. Today's
frame = 2+2+12+27+192+27 = 262 lines. Adding 25 to each border = 312.
- Make it a generic (`PAL : boolean`), passed down from `dragoncoco.sv` and
  tied to a constant in `core_top.v` (or, later, a menu option in
  `interact.json`).
- FS (`fs_n`) comes from that same line counter and drives the PIA's 50/60
  Hz interrupt, so BASIC's `TIMER`, `PLAY` tempo and every game that counts
  frames would follow automatically - the main point of doing this.
- Check: the SAM's video address counter must not count the extra border
  lines (it should reset each frame, as the real chip does) - verify in the
  Verilator full-machine sim before building.
- `video_frame_buffer.sv` only captures the 256x192 active area, so the
  extra border lines shouldn't need changes there. Retune its output to
  50 Hz to match (step 6).
- NTSC artefact colours stay off (`artifact_enable` is already 0) - correct
  for a UK machine, where PMODE 4 is black and white.
- Hardware check: `PRINT TIMER`, 10 s on a stopwatch → ~500 (50/s).

### 7. Untouched
Keyboard (`dragon_keyboard.sv`), joystick and ROM/tape loading all cross
into `clk_dragon` through existing synchronisers/loaders and don't depend
on its rate. No new block RAM needed (M10K is 308/308 used - this plan
needs none).

## Hardware checks once it builds
1. Boots to `OK` as before.
2. **Speed:** `PRINT TIMER`, wait 10 s on a stopwatch, `PRINT TIMER`
   again - should go up by ~600 (60 per second). Today it'd be ~150.
3. **Sound pitch:** `SOUND 89,30` should be close to concert A (440 Hz) -
   compare against a tuner app.
4. **Tape:** `test.cas` loads/lists; JSW loads in ~3 min.
5. JSW plays at a sensible speed with correct-sounding music.
