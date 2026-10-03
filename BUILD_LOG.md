# Build log

What changed, build result, resource use and timing numbers for each build.

## 2026-09-26 — CI run #1 (36238957368) — failed

First push, unmodified template `core_top.v`. Failed at the "Compile with
Quartus" step, before Quartus itself ever ran:

```
docker: failed to register layer: write /opt/intelFPGA/quartus/common/devinfo/programmer/sfl_enhanced_04_02e060dd.sof: no space left on device
```

Cause: `raetro/quartus:18.1` is a large image; GitHub's default `ubuntu-latest`
runner disk filled during the Docker layer pull, before compilation started.
Not a Quartus/timing/fit problem — infra only.

Fix: added a "Free disk space" step (`jlumbroso/free-disk-space@main`,
clearing the runner's preinstalled tool caches) before the Docker steps in
`.github/workflows/build.yml`. Also worth noting: the sibling
`../OpenFPGA_ZX-Spectrum` workflow this was modeled on turned out to have no
run history of its own on GitHub, so it wasn't actually a proven pattern —
just an untested template.

## 2026-09-26 — CI run #2 (36239286651) — succeeded

Same unmodified template `core_top.v`, after the disk-space fix. Compiled,
converted to `.rbf_r`, and packaged clean.

- **Fitter:** Cyclone V, `5CEBA4F23C8` — 414/18,480 ALMs (2%), 722 registers,
  8,192/3,153,920 block memory bits (<1%), 1/4 PLLs, 0 DSP blocks. Tiny, as
  expected for a test-pattern-only core.
- **Timing:** all corners (slow/fast, 1100mV, 0C/85C) show positive setup,
  hold and minimum-pulse-width slack on every clock (`clk_74a`,
  `bridge_spiclk`, the PLL's `divclk`) — no negative TNS anywhere. Clean
  timing closure on the template as shipped.
- **Output:** `bitstream.rbf_r`, 786,972 bytes. Zip contents verified
  against the expected `Cores/Platforms/Assets` layout — matches.

## 2026-09-26 — phase 0 gate confirmed on hardware

Copied `Cores/McNast13.Dragon32`, `Platforms/dragon32.json` (+ `_images`)
and `Assets/dragon32/McNast13.Dragon32` from CI run #2's zip onto the Pocket
SD card, alongside the existing cores already there (no conflicts). Booted
on real hardware: gray test pattern confirmed on screen.

**Phase 0 complete.** Toolchain, CI, packaging and SD card install all work
end to end. Moving to phase 1: get the actual Dragon 32 machine running.

## 2026-09-26 — CI run #4 (36243434530) — failed (Analysis & Synthesis)

First attempt at wiring the real machine into `core_top.v`. Failed with:

```
Error (12006): Node instance "coco_wd1793_0" instantiates undefined entity "wd1793".
```

(×4, one per `fdc.sv` instance). Cause: `fdc.sv` instantiates `wd1793`
internally, which the phase 1 dependency scan missed — it only checked
`dragoncoco.sv`'s own instantiations, not what `fdc.sv` itself pulls in.
Fix: vendored `wd1793.sv`, added to `ap_core.qsf`. See NOTES.md.

## 2026-09-26 — CI run #5 (36243997285) — compiled, but timing failed

Compiled clean this time (`wd1793` fix worked): `bitstream.rbf_r` produced,
zip packaged correctly.

- **Fitter:** Cyclone V `5CEBA4F23C8` — 4,047/18,480 ALMs (22%), 3,101
  registers, 802,884/3,153,920 block memory bits (25%), 100/308 RAM blocks
  (32%), 2/4 PLLs. Comfortable headroom on everything.
- **Timing: failed.** Worst case -10.121 ns setup slack (TNS -11186.465),
  Slow 1100mV 85C corner, on `ic|dp1|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk`
  — that's `dragon_pll`'s own internal counter hardware, not the machine
  logic. For comparison, the *same kind* of node on the template's existing
  `mf_pllbase` had +77.2 ns slack in phase 0's report. Diagnosis: the
  delta-sigma fractional modulator (`fractional_vco_multiplier("true")`,
  needed to hit 57.272727 MHz precisely) is tight at this output frequency.
  Fix attempted: switched to integer-N mode (`fractional_vco_multiplier("false")`) —
  phase 1 doesn't need bit-exact frequency, so trading precision for a PLL
  that actually closes timing seemed like the right call. **Did not test
  this build on hardware** — pushing a known timing failure to real
  hardware risks a wasted test cycle for no useful information.

## 2026-09-26 — CI run #6 (36244907813) — failed (Fitter)

Integer-N mode didn't just have tighter timing - it outright rejected the
request:

```
Error: PLL Output Counter parameter 'output_clock_frequency' is set to an
illegal value of '57.272727 MHz' ...
```

Cause: 57.272727 MHz reduces to a 280/363 ratio of the 74.25 MHz reference -
not representable by the small integer PLL counters integer-N mode uses.
Fix: picked a different target frequency instead, one with a genuinely
clean small-integer ratio to 74.25 MHz - 57.75 MHz = 74.25 x 7/9 exactly,
about 0.83% off the real hardware's 57.272727 MHz. Irrelevant for this
gate's purposes. Still integer-N mode.

## 2026-09-26 — CI run #7 (36245568840) — compiled, timing still failed

Same fitter numbers as run #5 (4,061 ALMs, 22%; 802,884 block memory bits,
25%). Timing: still failed, same node, virtually the same magnitude
(-10.608 ns worst case) as run #5's fractional-mode failure (-10.121 ns) -
despite integer-N mode and a completely different, "cleaner" frequency.

That similarity across three different PLL configurations (fractional
57.272727MHz, integer 57.272727MHz [rejected outright], integer 57.75MHz)
was the tell that this was never actually a PLL-hardware-feasibility
problem. Checked `core_constraints.sdc`: it declares
`set_clock_groups -asynchronous` naming each of the *existing* mf_pllbase
clock nodes explicitly by name - and dragon_pll's two output clocks were
never added to that list. Without that declaration, Quartus's STA was
analyzing dp1's clock as if it needed synchronous timing against
clk_74a/mf_pllbase's outputs, which isn't a real relationship between two
independent PLLs - a classic missing-SDC false violation, not a real one.

Fix: added dp1's two clock nodes to the existing asynchronous group in
`core_constraints.sdc`, and reverted `dragon_pll.v` back to the bit-exact
57.272727 MHz fractional-mode target (57.75 MHz was never actually needed -
the frequency was fine all along).

## 2026-09-26 — CI run #8 (36246540253) — compiled, timing partially fixed

The SDC fix worked, partially: negative slack dropped from 4 instances to
2 (4,075 ALMs, 22%; same block memory). The "Fast" corner violations are
gone entirely. But both "Slow" corner instances remain, on the same
`ic|dp1|...divclk` node, and slightly *worse* than before (-10.892 ns /
-11.013 ns vs. -10.608 ns / -10.344 ns).

So both suspects were real: the missing SDC group caused some of the
apparent violations (now fixed), but the fractional delta-sigma modulator
genuinely doesn't have enough margin at 57.272727 MHz on this part's
worst-case timing corner, independent of the SDC issue. Fix: switched back
to integer-N mode at 57.75 MHz (the clean 7/9 ratio from run #6/#7) - this
time keeping the corrected SDC as well, combining both fixes rather than
treating them as alternatives.

## 2026-09-26 — CI run #9 (36247444616) — compiled, timing still failed

Same fitter numbers as before (4,041 ALMs, 22%). Timing: still 2 negative
slack instances, same node, similar magnitude (-9.971 ns / -9.403 ns) as
run #8 - despite now being in integer-N mode (no fractional modulator) with
the corrected SDC. That ruled out both of the previous theories (missing
SDC group, fractional modulator tightness) as the *sole* cause.

Re-read what this timing check actually is: `ic|dp1|altera_pll_i|general[0]
.gpll~PLL_OUTPUT_COUNTER|divclk` is simply Quartus's internal name for
dragon_pll's outclk_0 net itself - not a PLL-internal-only diagnostic as
assumed in runs #5-#8, but the actual clock powering every register in the
Dragon 32 machine. This is real machine-logic timing: -10 ns slack against
a ~17.3 ns period implies an actual critical path around 27 ns somewhere in
the RTL (most likely `mc6809i.v`'s combinational instruction decoder) - a
genuine ~36 MHz ceiling on this part. Plausible root cause: the Pocket's
Cyclone V (`5CEBA4F23C8`, speed grade C8) is a smaller/slower-graded part
than the Cyclone V on MiSTer's DE10-Nano (speed grade C6) this RTL was
written against - timing that closes there isn't guaranteed to close here.

Fix: dropped the target frequency to 14.85 MHz (74.25 MHz x 1/5), about a
quarter of real-time speed but with generous headroom below the ~36 MHz
ceiling. Functional correctness doesn't depend on clock rate for
synchronous digital logic - only perceived speed and video refresh rate do
- so this is an acceptable trade to finally get a clean pass for phase 1's
actual gate (booting to BASIC). Revisit in phase 2, which needs correct
video/audio timing anyway and is the right place to add a real
`report_timing` detail pass and find out how close to 57.27 MHz is safe.

## 2026-09-26 — CI run #10 (36248282773) — compiled, timing clean

**Zero negative slack anywhere.** 3,884/18,480 ALMs (21%), 2,698
registers, 802,884/3,153,920 block memory bits (25%), 100/308 RAM blocks
(32%), 2/4 PLLs. Confirms the diagnosis across runs #5-#9: this was always
a real ~36MHz critical-path ceiling in the machine RTL on this specific
part, not a PLL configuration problem. 14.85 MHz clears it comfortably.

**Ready for a hardware test** - the actual phase 1 gate (BASIC banner on
screen) still needs the SD card / real Pocket, same as phase 0.

## 2026-09-26 — first hardware test — gray screen, cause unclear

Installed on the SD card along with the user's own `boot.rom`. Result:
solid gray screen, indistinguishable from phase 0's test pattern. Confirmed
on a second attempt (power-cycled) that this is the new build, not phase 0
still cached/open.

Can't tell from a solid-gray picture alone whether the machine is actually
stuck (PLL, reset, ROM load) or whether the video wiring itself just can't
show anything because `clk_dragon` isn't a trustworthy clock on real
hardware — both would look identical from the outside. Pushed a temporary
diagnostic build instead of guessing at a specific fix - see NOTES.md
"Debugging the gray screen" for what it does (four solid colors encoding
PLL lock / reset release / ROM load status, using the *other*, already-
proven clock domain so it stays observable even if dragon_pll is the
problem).

## 2026-09-26 — correction: the gray screen was a copy bug, not the RTL

Found while placing the diagnostic build on the SD card: the SD card's
`Cores/McNast13.Dragon32/` already existed (from the phase 0 install), so
every `cp -R .../Cores/McNast13.Dragon32 "/Volumes/ROMS/Cores/McNast13.Dragon32"`
since then landed the new build *inside* the existing folder
(`.../McNast13.Dragon32/McNast13.Dragon32/...`) instead of overwriting its
contents - a classic `cp -R` gotcha (it copies the source directory *into*
an existing destination directory, rather than merging into it). Confirmed
by comparing MD5s: the top-level `bitstream.rbf_r` the Pocket actually
loads was untouched since phase 0, while the real phase 1 builds were
piling up one level too deep, invisible to the Pocket.

So the entire "gray screen" investigation was chasing a phantom: **the
Pocket was still running phase 0's stock test pattern the whole time**,
which is exactly why it looked identical - it *was* identical, unchanged.
The real phase 1 RTL was never actually tested on hardware yet.

Fixed the SD card by moving the (correctly extracted) diagnostic build up
to the real path and removing the nested copy; verified by checksum. The
diagnostic build is now genuinely in place for the next test - worth
running it now anyway, since it's still useful signal about the real RTL
regardless of how we got here.

## 2026-09-26 — hardware test (diagnostic build, correctly placed) — yellow

PLL locked, reset released, but the boot ROM was never written into the
machine at all. See NOTES.md "Boot ROM never loading: the deferload field"
for the diagnosis: `data.json`'s ROM slot copied `"deferload": true` from
`../OpenFPGA_ZX-Spectrum`'s working example without also copying the
explicit `target_dataslot_read` request that core issues to actually
trigger a deferred slot's transfer. Fix: dropped `deferload` entirely,
matching `agg23/openfpga-pokemonmini`'s simpler slot (no request needed).
Rebuilding to test - keeping the diagnostic overlay in place one more
round rather than reverting to real video, so a persisting yellow (if this
guess is wrong) is still informative rather than back to a blank gray.

## 2026-09-26 — hardware test (deferload fix, diagnostic build) — green!

Dropping `deferload` fixed it. PLL locked, reset released, boot ROM
loaded — all three gates confirmed good on real hardware. Reverted
`core_top.v` to real video passthrough (removed the diagnostic overlay)
to test whether the actual BASIC banner appears now that the boot chain is
confirmed working end to end.

## 2026-09-26 — hardware test (real video) — stuck showing "@"

16 rows of giant "@" symbols (a Dragon/CoCo VDG's decode of all-zero video
RAM - real character decode confirmed working, but BASIC hasn't written
its banner). Waited 15-30s at the user's own initiative - no change, so
genuinely stuck rather than just slow at our reduced clock. Column count
(5 instead of 32) is a separate display-geometry issue, deferred - not
blocking this diagnosis since the content itself (not just its geometry)
is wrong.

Added two debug taps to dragoncoco.sv (`dbg_cpu_addr`, `dbg_reset_n` - see
NOTES.md "Debugging the stuck @ screen") and extended the diagnostic
overlay to check whether the CPU is actually executing at all. Rebuilding
to test.

## 2026-09-26 — hardware test (round 2 diagnostic) — magenta

Internal reset released, but `cpu_addr` never moved in half a second -
genuinely halted. Ruled out `mc6809i.v`'s NMI handling (edge-triggered,
wouldn't explain a persistent freeze from a stuck line) and
`dragoncoco.sv`'s own `halt` signal (hardwired to constant 0 when
`dragon=1'b1`, independent of the disk controller). Added a third debug
tap (`dbg_clk_e`, SAM's own E-clock output that paces the CPU's
sequencer per `mc6809i.v`'s own clocking comments) with a toggle
detector, to split "SAM's clock generation is stuck" from "CPU-specific
problem." See NOTES.md for the reasoning. Rebuilding to test.

## 2026-09-26 — hardware test (round 3 diagnostic) — magenta again

`clk_E` toggles fine - ruled out SAM/clocking. Genuinely CPU-specific:
valid clock, valid reset, `cpu_addr` still frozen. Round 4: replaced the
single magenta case with four colors split by the frozen address's top 2
bits across the memory map (RAM low/high, ROM, cart/IO/vectors) - see
NOTES.md. Rebuilding to test.

## 2026-09-26 — hardware test (round 4 diagnostic) — pink

Frozen in `$C000-FFFF` (cart/IO/vector space - reset vector, PIA1/PIA2,
SAM registers). Confirmed via brightness ("light/pale") rather than hue,
since the user is slightly colorblind - noted for future rounds: primary
colors only (red/blue/yellow/black/white/green), no more
magenta/cyan/purple/pink together.

Round 5: does the frozen address exactly equal $FFFE/$FFFF (the CPU never
got past its own reset vector fetch) or something else in that range
(fetched *something* and is stuck wherever that pointed)? Black vs white.
Rebuilding to test.

## 2026-09-26 — hardware test (round 5 diagnostic) — black

CPU permanently stuck re-addressing exactly $FFFE/$FFFF - its own reset
vector, the last 2 bytes of the ROM. Root cause theory: data_loader's
WRITE_MEM_CLOCK_DELAY/EN_CYCLE_LENGTH (12, 5) were copied from
PokemonMini verbatim, but that core's clk_memory runs at 40MHz - ours is
only 14.85MHz, giving only ~20% margin against APF's ~1010ns-per-word
bridge cadence (data_loader.sv's own documented figure). A transfer
falling cumulatively behind under a tight margin would most plausibly
corrupt whatever arrives last - exactly the reset vector. Dropped to (4,
1), the documented minimum, for much more margin. Kept the diagnostic
overlay in place (green would confirm this was it). Rebuilding to test.

## 2026-09-26 — hardware test (timing fix) — black again, unchanged

Identical result to before the timing fix - ruled that theory out
outright (a real margin problem would be sensitive to the margin
changing; this wasn't). Checked `~/Downloads/d32.rom` directly (local
file, no hardware needed): its real bytes at `$3FFE-3FFF` are `B3 B4`, a
normal reset vector into ROM. Content's fine - the CPU isn't jumping to a
bad vector, it's never completing the fetch at all.

Found a real gap in round 3's `clk_E` check: it only tested "did it ever
toggle once", which a single edge at reset release would already satisfy
without continued toggling. Replaced with a watchdog checking `clk_E` is
still actively toggling (no more than ~10ms gap) right before the second
snapshot.

Also added the same watchdog for `clk_Q` (never tapped before - only
`clk_E` was checked, but the CPU needs both phases) in the same build,
combining what would otherwise be two separate hardware round-trips.
New color: gray (clk_E fine, clk_Q stalled). Rebuilding to test.

## 2026-09-26 — hardware test (clk_E/clk_Q watchdog) — white

clk_E genuinely stalled (not just "toggled once" - the real finding the
round-4 check missed). Traced clk_E's generation in mc6883.vhd: a plain
free-running divide-by-4 counter, no PLL/NCO, clock-rate-independent -
rules out "broke because we slowed the clock" for that specific divider.
But that whole state machine only advances if SAM's own spd_ena pulse is
high - added a dbg_spd_ena tap (exposed via dragoncoco.sv's existing
clk_enable wire) with the same watchdog, positioned before clk_E/clk_Q in
the priority chain since it's the more fundamental candidate. Black now
means spd_ena stalled; white is redefined to mean spd_ena is fine but
clk_E stalled anyway. Rebuilding to test.

## 2026-09-26 — hardware test (spd_ena watchdog) — black

spd_ena itself stalled. Its generator (mc6883.vhd's Tm process) is a
trivial free-running counter gated only by clk/reset - nothing else can
stop it once running, and round 3 already proved clk_E genuinely toggled
at some point. Points at "worked briefly, then something re-froze it" -
most plausibly a later reset re-assertion or PLL unlock, neither of which
any check so far catches (they all test current level at one sample
point, not "did this go low again after going high").

Added sticky "ever glitched low after being high" latches for
pll_dragon_locked, reset_n_dragon, and dbg_reset_n - cheap, no new RTL
taps needed. Reused red/blue/orange (same association, extended meaning).
Rebuilding to test.

## 2026-09-26 — hardware test (glitch latches) — black again

None of the three glitch latches fired - rules out a later reset/PLL
glitch too. spd_ena stalled with clk/reset both confirmed stable the
whole time, and its generator (mc6883.vhd's Tm process) is unconditionally
free-running otherwise. No remaining RTL-reading-level theory left.

Added a direct tap on Tm's own t_clks counter (the most fundamental
signal in this chain - if this isn't incrementing, nothing downstream
could be), reusing mc6883.vhd's existing-but-unconnected dbg port pattern
for the wiring. Extended the color scheme with a brightness progression
(black=t_clks stalled, dark gray=spd_ena stalled instead, gray=clk_E,
light gray=clk_Q). Rebuilding to test.

## 2026-09-26 — hardware test (t_clks) — black again; pivoted to simulation

Still black. At this point installed GHDL and Icarus Verilog locally
(see NOTES.md "Pivoting to local simulation" for full details) instead of
spending more hardware round-trips:

- GHDL simulation of mc6883.vhd (SAM) alone: t_clks/spd_ena/clk_e/clk_q
  all cycle perfectly for 20us simulated - zero stalling. This means
  rounds 6-9's "stalled" readings were most likely false negatives from
  undersampling in my own watchdog (t_clks toggles at 14.85MHz, sampled by
  a 12.288MHz clock - too close in rate to reliably catch), not real
  hardware behavior. cpu_addr (changes far slower, ~4.3us/cycle) remains
  the one trustworthy signal from the color diagnostics.
- Icarus simulation of mc6809i.v (the CPU) alone, fed the real boot.rom
  via a simple direct memory model: correctly fetches the real $B3B4
  vector and executes 130+us of real BASIC boot code with zero freezing.

Both components individually validated correct. Bug is in the integration
- leading suspect is dragoncoco.sv's rom8_dout2 capture register (a
  precise ras_n/clk_E-gated latch) vs real BRAM read latency my
  combinational testbench model doesn't have. Next: extend the simulation
  with a registered memory model to try to reproduce the freeze locally.

## 2026-09-27 — full-machine simulation (Verilator) — no freeze reproduced

Built a full-machine testbench: the real `dragoncoco.sv` + real
`mc6809i.v`/`pia6520.v`/`dac.sv`/`acia.sv`/`fdc.sv`/`wd1793.sv`/
`Cassette_Write.sv`/`keyboard.sv`, plus `mc6883.vhd` and `ttl_74LS138.vhd`
synthesized to Verilog via `ghdl --synth --out=verilog` (GHDL can't
elaborate `dpram.vhd`/`dpram_1r1w.vhd` directly - vendor-only
`altera_mf` dependency - so those two were replaced with hand-written
Verilog stand-ins matching their confirmed real 1-cycle read latency;
`mc6847pace` (VDG) was stubbed out too, since video content is irrelevant
to this test). Compiled with Verilator (Icarus choked on legal-but-
unconventional declaration ordering across too many files to patch by
hand) using `--no-assert-case` (see below) and `-Wno-PROCASSWIRE`
(pervasive `wire`-then-procedurally-assigned style throughout this
vendored codebase - harmless, just not modern strict-IEEE style) and
`--timing`.

First run hit a genuine `unique case` violation at time 0
(`dragoncoco.sv:186`, the `cpu_din` mux): `rom8_cs` is defined as
`romA_cs | rom8k_cs`, so whenever `romA_cs` fires, `rom8_cs` fires too -
both branches write the same value (`rom8_dout2`) so it's functionally
harmless, but it does violate strict SystemVerilog `unique` semantics.
Verilator enforces that as a runtime assertion by default; recompiled
with `--no-assert-case` to match how every other synthesis tool (and the
original `case(1'b1)` priority-encoder idiom) already treats it.

With that resolved, loaded the real `boot.rom` via simulated `ioctl_wr`
pulses (bypassing `data_loader`/the bridge - that mechanism is separately
confirmed working), released `trig_reset_n` only after the load finished,
and let it run. **Result: the CPU never freezes.** It fetches its reset
vector, jumps into real boot code, and keeps executing (RAM-clear-style
address ramps around `$7F8F`-`$7F92`, code around `$0109`-`$010d`, etc.)
continuously for the full 2ms simulated window (tens of thousands of
cycles) - dbg_cpu_addr is dynamic throughout, never stuck.

This directly contradicts the "stuck at $FFFE/$FFFF" readings from
rounds 6-9. Combined with the already-identified undersampling risk in
that diagnostic's own CDC sampling (clk_core_12288 sampling
clk_dragon-rate signals - nearly the same frequency), and the fact that
`dbg_cpu_addr` itself was captured through that same flawed
`synch_3`-at-clk_core_12288 path, the most likely explanation is that
rounds 6-9 were **entirely false negatives from the diagnostic
infrastructure itself** - the real RTL, given a clean ROM load and reset
release, has no freeze.

Reverted core_top.v to real video passthrough (removed the whole
diagnostic overlay: sample-counter/watchdog/glitch-latch logic, the
`diag_color` chain, and the leftover phase-0 test-pattern generator) and
removed the TEMPORARY DEBUG TAPS from dragoncoco.sv and mc6883.vhd.
Pushing this for a real hardware test - if BASIC actually boots now, the
whole "CPU freeze" investigation resolves to "it was the diagnostic, not
the machine." If it still doesn't boot, real video passthrough will at
least show *something* different (a real, if wrong, picture) instead of
a diagnostic color, which narrows things down again from a clean slate.

## 2026-09-27 — hardware test (real video passthrough) — it boots!

**Phase 1's core gate is met.** Real Dragon BASIC `OK` prompt on screen,
green background - that's the authentic default Color BASIC alphanumeric
screen (green background, white text), not a bug. Confirms rounds 6-9's
"stuck at $FFFE/$FFFF" were exactly what the full-machine simulation
predicted: false negatives from the diagnostic's own undersampling, not a
real freeze. The machine has been fine since the ROM-load fix; only the
watchdog reading it was broken.

One real cosmetic bug found on this same test: oversized/stretched text.
Root cause: `video.json` declared a 320x240 scaler canvas, left over from
phase 0's test pattern, but `mc6847pace.vhd`'s real CVBS timing (with
`overscan` tied to 0, as core_top.v does) only marks the true 256x192
alphanumeric window as active - the border is blanked. Feeding a real
256x192 active stream into a scaler expecting 320x240 stretches
everything unevenly, which is exactly "oversized text" with no other
visible artifacts. Fixed by correcting `video.json` to declare 256x192
(handily already exactly 4:3, so aspect_w/aspect_h needed no change).
No RTL change needed - core_top.v's `video_de` already tracks the real
256x192 window correctly since it's a direct passthrough of
dragoncoco.sv's hblank/vblank. Rebuilding to test.

## 2026-09-27 — hardware test (video.json 256x192) — still oversized

video.json alone wasn't the whole story: text still ~20% of screen width
per character (roughly 4-5 real characters' worth stretched across the
full width). Found the real cause: `video_rgb_clock` was wired to
`clk_dragon` directly - the machine's full, ungated system clock, not
the VDG's actual per-pixel rate. `dragoncoco.sv` already exposes the
correct signal on its own `vclk` output port (internally wired to
`mc6847pace`'s genuine `pixel_clock` output), but core_top.v left it
unconnected. The real rate is `clk_dragon`/8 (SAM's `Tm` process divides
by 4 for `VClk`, `mc6847pace`'s own `PROC_CLOCKS` divides by 2 again for
`cvbs_clk_ena`) - so the scaler was sampling 8x faster than real pixels
change. With `video.json` now correctly declaring 256 real pixels/line,
the scaler only captures 256 raw `clk_dragon`-rate samples before
considering a line "done" - at 8x oversampling that's only ~32 real
pixels' worth (about 4 real characters), stretched to fill the full
declared width. Matches the ~20%-per-character report almost exactly
(256/32 = 8x, ~4-5 characters over the whole width).

Fixed by connecting `dragoncoco`'s `vclk` output through
(`dragon_vclk`) and driving both `video_rgb_clock` and
`video_rgb_clock_90` from it instead of `clk_dragon`/`clk_dragon_90deg` -
no true 90-degree partner exists for a derived/gated clock like this,
but at ~1.86MHz DDIO output margin isn't a real concern, so reusing the
same signal for both should be fine. Rebuilding (this one needs a real
Quartus recompile, unlike the video.json-only fix) - watching STA for
any new clock-relationship warning on `dragon_vclk`, the same class of
issue dp1's own clocks hit before they were added to
`core_constraints.sdc`'s async group.

## 2026-09-27 — hardware test (dragon_vclk fix) — "looks perfect"

**Phase 1 is done.** Real BASIC `OK` prompt, correct green background,
correctly-sized 32-column text. STA showed zero new timing warnings from
`dragon_vclk` - Quartus didn't need a clock declaration for it, since
nothing on-chip is clocked *by* it, it's just a normal registered signal
routed to an output pin.

Next: phase 3 (input + cassette loading), pulled ahead of phase 2
(audio/video XRoar parity) at the user's request.

## 2026-09-27 — USB keyboard input added, not yet hardware-tested

Ported the same architecture `OpenFPGA_ZX-Spectrum` already proved out for
this exact problem (docked USB keyboard -> a computer's real keyboard
matrix): vendored `apf2hid.sv` (MIT) to extract the raw HID report from
the Pocket's `cont3_key`/`cont3_joy`/`cont3_trig` controller slot, and
wrote a new `dragon_keyboard.sv` that re-derives the Dragon 32 matrix
fresh every `clk_dragon` cycle from that live snapshot - no PS/2
toggle/strobe convention, no per-key state, same reasoning as the ZX
Spectrum project's own README for why that shape avoids a whole class of
stuck/dropped-key bugs.

This **replaces** the vendored `dragon/keyboard.sv` module entirely
(removed from the repo) rather than extending it - that file's license
was non-commercial-only, and its ps2_key-toggle-strobe convention is
exactly the pattern being avoided. The Dragon 32 keyboard matrix table
itself (a hardware fact, not code) came from two independent public
sources: 6809.org.uk's PIA0-port-A-is-rows/port-B-is-columns description,
and XRoar's own key-value encoding scheme (`dkbd.c`/`dkbd.h`, GPLv3) -
only the factual row/column grid was taken from XRoar, not its code; the
decode logic in `dragon_keyboard.sv` is original.

v1 scope: A-Z, 0-9, Space, Enter, arrows, Backspace (maps to Left, matching
real Dragon hardware - no dedicated matrix position), Delete (maps to
Clear), Escape (maps to Break), Shift, and comma/period/minus/slash/
semicolon/colon (semicolon key remaps to Dragon's dedicated colon position
when shifted, without also asserting Dragon Shift, since Dragon has
separate physical keys for `;` and `:`). No `@` mapping yet (needs Shift+2
remapping like the semicolon does - deferred, not critical for typing
BASIC). Verified with a 12-case Icarus testbench
(`usbkbd/tb_dragon_keyboard.sv`) covering single keys, multi-key holds,
shift suppression, and column-scanning - all pass. Not yet tested on real
hardware with an actual keyboard - next step once this builds.

## 2026-09-27 — cassette (.cas) loading added, not yet hardware-tested

Added a second, independent data slot/data_loader pair for `.cas` files -
`data.json`'s new "Cassette" slot (optional, `parameters: 11` for
user-reloadable-at-any-time, its own bridge address `0x10000000` distinct
from the boot ROM's `0x00000000`), a `cas_ram` buffer (64KB, plenty for
any realistic Dragon 32 tape file given the machine only has 32KB RAM to
begin with), and a new `cas_player` module that streams the loaded bytes
out as the real bit-serial tape waveform into `dragoncoco.sv`'s `casdout`
input.

Real Color BASIC cassette encoding (source: Chris Lomont's "Color
Computer 1/2/3 Hardware Programming" v0.82, a public hardware reference -
found via web search, not from any vendored/emulator code): each bit is
one full cycle of a tone, LSB first, '1' = 2400 Hz, '0' = 1200 Hz,
detected by the real machine on a positive-to-negative zero crossing. A
`.cas` file already contains the fully-decoded byte stream (leader bytes,
magic bytes, block headers, checksums, all literally present) - the only
job here is re-encoding those bytes back into the right square-wave
cycles, which a plain digital toggle can do directly (no DAC needed,
since a comparator would square up a real analog signal the same way
anyway).

The one non-obvious design point: this machine runs `clk_dragon` at 14.85
MHz, not the ~57.272727 MHz `dragon_pll.v` documents as the "real" 16x-
NTSC-colorburst target - a deliberate trade for timing closure (see
phase 1's build history above). Every other clock in the machine (SAM's
E/Q generation, the CPU's effective instruction rate) is already a fixed
divide of `clk_dragon`, so the whole machine runs uniformly slower than
real hardware. Since Color BASIC's tape-reading routine measures bit
timing by counting its own (now-slower) CPU cycles, the tape waveform
needs the exact same treatment: expressed as a fixed clk_dragon *cycle
count* per bit derived from the original 57,272,727 Hz design frequency
divided by the tone frequency, not literal 1200/2400 Hz relative to
`clk_dragon`'s actual slower rate (which would make the tape appear to
run fast relative to what the CPU is measuring it against). Also means
none of this needs revisiting if `clk_dragon`'s rate ever changes later.

Also handles two real-hardware behaviors deliberately: pausing the
"motor" (`cas_relay`, the real PIA1 CA2 motor-control line Dragon
software already toggles around CLOAD) freezes playback position rather
than resetting it - a real tape deck doesn't rewind when you stop the
motor - and loading a *different* file (`dataslot_update` firing again
for this slot) does rewind to the start, like swapping the cassette.

Verified with an 8-case Icarus testbench (`cassette/tb_cas_player.sv`):
exact half-cycle timing for both tone frequencies (measuring real
`$realtime` deltas between `casdout` edges), motor pause holding state
steady, motor resume continuing correctly, end-of-tape silence, and
multi-byte address advancement - all pass. Not yet tested on real
hardware with an actual `.cas` file.

## 2026-09-27 — joystick support added, not yet hardware-tested

Turned out to be a small addition: `dragoncoco.sv`'s own vendored
`dac.sv` already emulates the real DAC+comparator timing protocol Dragon
software's joystick-read routine expects (a 6-bit DAC value walked up
until it exceeds the joystick's position, time-multiplexed across both
sticks' axes via SELA/SELB - see `dac.sv`'s own header table). All that
was missing was feeding it real controller data - `joy1`/`joy2`/`joya1`/
`joya2` were all tied to 0.

Wired `cont1_joy`/`cont2_joy` (the Pocket's real analog stick position)
through to `joya1`/`joya2` directly, with `cont1_key`/`cont2_key`'s d-pad
bits overriding to a hard extreme (255/0) when pressed - so either an
analog stick or the d-pad works, no menu setting needed. Confirmed the
polarity (right/down = 255, left/up = 0) against `dragoncoco.sv`'s own
`joy_use_dpad` branch, which already uses that exact convention
internally. `joy1[4]`/`joy2[4]` (the fire button, mapped to face_a) feed
straight into `dragon_keyboard.sv`'s existing `joystick_1_button`/
`joystick_2_button` ports - already wired correctly back when the
keyboard bridge was built, just never had real data behind them until
now.

One real unknown, not resolvable without a hardware test: whether the
Pocket's analog stick actually reports increasing value = rightward/
downward (the assumption both `joy1_x`/`joy1_y`'s polarity and the
d-pad-override values rely on) - a reasonable, near-universal convention,
but unconfirmed for this specific bridge. If movement comes out inverted
on either axis, it's a one-line fix once observed.

No dedicated testbench for this one - pure combinational muxing on top of
the already-proven `synch_3` synchronizer pattern, and `dac.sv`'s own
protocol emulation isn't code this change touches at all.

## 2026-09-27 — hardware test (cassette) — hung forever on CLOAD

User loaded `test.cas` via the Pocket's menu, typed `CLOAD` - screen
stuck showing a single `S` in the top-left corner, unchanged after 30
minutes. Genuinely hung, not just slow: worst case (every bit at the
slower 1200Hz rate) the whole 329-byte file should finish in ~8 seconds
at this clock rate.

Root cause, confirmed by directly asking Analogue's own host/target-
command docs the exact question: for a data slot that's optional and
user-reloadable *while the core is already running* (this slot's
situation - `data.json`'s `"parameters": 11`), the platform does **not**
push the file's bytes via plain bridge writes into the slot's declared
address the way it does for the boot ROM at cold boot. It only fires
`dataslot_update` with the new file's size - actually getting the bytes
requires the core to explicitly issue a `target_dataslot_read` request
into a bridge scratch address of the core's own choosing, then wait for
`target_dataslot_ack`/`target_dataslot_done`.

The previous implementation only watched for plain bridge writes into
the slot's own `data.json` address (`0x10000000`), which never arrived -
`cas_ram` stayed all zero, while `cas_len` still got set correctly from
`dataslot_update_size` (that part *did* fire). So `cas_player` had a
valid-looking length and dutifully "played" 329 zero bytes: every bit a
1200Hz cycle, no alternating pattern anywhere, so no valid leader tone
for Color BASIC's bit-sync search to ever lock onto. Not silence, but
functionally the same to a routine that's waiting for a specific pattern
- an infinite, patient wait, matching exactly what was observed.

Fixed with a proper request/ack/done state machine, in `core_top.v`,
running on `clk_74a` (matching where `target_dataslot_*`/`dataslot_update`
actually live - not `clk_dragon`, which was a subtlety the earlier
version got right by accident, having never actually driven any target
command). Requests the whole file in one shot into scratch address
`0x60000000` (a conventional choice - `OpenFPGA_ZX-Spectrum`'s own
on-demand loader uses the same address for the same purpose); no
documented hard per-request size limit, and real Dragon 32 tape files
are nowhere near this buffer's 64KB, so no chunking needed. The existing
`cas_data_loader` (a plain `data_loader` watching for bridge writes) is
still exactly right for actually capturing the bytes once the platform
delivers them - it just needed to watch `0x60000000` instead of the
slot's own declared address, since that's where `target_dataslot_read`
actually lands them. A toggle (not a raw pulse) carries the "data's
ready" signal across the `clk_74a`/`clk_dragon` boundary, since a
single-cycle pulse risks being missed entirely by an asynchronous
receiving clock. Rebuilding to test.

## 2026-09-27 — hardware test (target_dataslot_read fix) — still hangs

Same symptom: `S` stuck top-left after `CLOAD`. The request/ack/done fix
didn't resolve it (or something else is also wrong) - rather than guess
again, added a small temporary diagnostic: a 32x32 top-right corner patch
(real video everywhere else, so the hang itself stays visible) with
sticky "ever happened" latches checked in priority order -
`dataslot_update` for the Cassette slot ever arriving (red if not),
`target_dataslot_ack` ever coming back (orange), `target_dataslot_done`
ever firing (yellow), `cas_new_file` ever reaching `clk_dragon` (blue),
`cas_relay`/motor ever asserting (white), `casdout` ever toggling
(black) - green if all of those happened, meaning the loading pipeline
itself is fine and the remaining bug is in the file's content/format or
how CLOAD interprets it, not in delivery. Rebuilding to test.

## 2026-09-27 — hardware test (diagnostic) — red, before CLOAD even ran

Red square visible from the moment the core loads, before CLOAD is ever
typed - meaning `dataslot_update` for the Cassette slot never fires at
all in this user's actual workflow (loading `test.cas` via however the
Pocket's menu presents it). That's the live-reload path's trigger - if
it never fires, `target_dataslot_read` never gets issued, so of course
nothing downstream progresses.

This points at the file being selected as part of *launching* the core
(or remembered from a previous session) rather than reloaded from an
already-running core's interact menu - a case the very first cassette
implementation actually handled correctly in principle (plain bridge
writes into the slot's own declared address, same mechanism as the boot
ROM), before it got replaced entirely by the target_dataslot_read
mechanism on the assumption that was the only path that mattered. Worth
being honest about what's actually confirmed vs. not: the first
implementation *also* hung with the same "S stuck" symptom, and there
was no diagnostic yet to say whether that was because the boot-time path
doesn't work either, or because of some other issue entirely. Redoing
that experiment blind wouldn't add anything.

Fixed by supporting **both** delivery paths simultaneously - re-added the
boot-time `data_loader` (watching `0x10000000`, exactly the original
approach) alongside the `target_dataslot_read` live-reload path, feeding
the same `cas_ram`/`cas_len`/`cas_new_file` from whichever one actually
fires. Extended the diagnostic to add a `cas_boot_wr` sticky latch and
adjusted the color chain so it skips the ack/done checks (live-reload-
specific) when the boot path is the one that actually delivered the
file, instead of showing a misleading orange/yellow. Caught and fixed a
real bug while doing this: the new `cas_boot_wr` latch was first written
sampling a `clk_dragon`-domain signal (`data_loader`'s `write_en`,
confirmed by reading `pocket_utils/data_loader.sv` directly - it's driven
inside `always @(posedge clk_memory)`) inside a `clk_74a`-domain always
block, an actual CDC bug caught by re-reading the diff before shipping
it, not by a hardware round-trip. Moved that latch to `clk_dragon`, where
it belongs and needs no synchronizer at all. Rebuilding - this diagnostic
run should tell us definitively whether either path now actually
delivers the file.

## 2026-09-27 — hardware test (dual-path diagnostic) — light green: found root cause

Light green square: `dataslot_update` fired (RED cleared) right after
selecting `test.cas`, then WHITE (motor not asserted yet), then, after
`CLOAD`, LIGHT GREEN - confirming the *entire* loading pipeline works:
file delivery, `cas_len`, the tape motor, and `casdout` toggling.
`CLOAD` itself even reported finding "TEST" correctly. But `RUN` gave
`?SN ERROR IN 8272` - nonsense for a 2-line program.

Two independent verifications before touching any more RTL:

1. Built a bit-accurate reference decoder (`cassette/tb_cas_fullfile2.sv`)
   that measures exact clk_dragon cycle counts between every `casdout`
   edge (not `$realtime` - an earlier attempt using `$realtime` deltas
   had its own bug and produced false mismatches) and reconstructs all
   329 bytes. **All 329 bytes match exactly** - `cas_player.sv` is
   bit-accurate end to end. Also tried a real commercial cassette game
   (Jet Set Willy) - `CLOAD` found it too. Two independently-sourced
   files both successfully syncing rules out the delivery/encoding layer
   entirely (Jet Set Willy's own `?FM ERROR` on `RUN` is expected -
   commercial cassette games are almost always machine code, needing
   `CLOADM` + `EXEC`, not `CLOAD` + `RUN`).
2. Attempted a full-machine simulation (real CPU/SAM/keyboard bridge,
   "typing" CLOAD via simulated HID keypresses) to reproduce the exact
   error - inconclusive, since the simulated typing itself never
   actually triggered CLOAD (`cas_relay`/tape motor never asserted in
   550M cycles) - a testbench timing issue, not informative about the
   real bug. Abandoned rather than debug a harness-only problem.

Root cause found by going to the actual source: downloaded and
text-extracted "Color BASIC Unravelled" (a real ROM disassembly,
`techheap.packetizer.com/computers/coco/unravelled_series/`) and found
CLOAD's own dispatch code. The filename block's byte 10 - documented
elsewhere (Lomont's hardware reference, used for the original format
writeup) as a "gap flag" ($00=no gaps) - is actually tested by CLOAD as
part of a combined ASCII+MODE selector. The disassembly's own
authoritative table (`LA65C`, "ENTER HERE FOR ASCII FILES": `LDX #$FFFF`
then `STX 9,U`, setting CASBUF+9 *and* CASBUF+10 together):

| File kind | TYPE (byte 8) | ASCII (byte 9) | MODE (byte 10) |
|---|---|---|---|
| BASIC CRUNCHED | 00 | 00 | 00 |
| **BASIC ASCII** | 00 | FF | **FF** |
| DATA | 01 | FF | FF |
| MACHINE LANGUAGE | 02 | 00 | 00 |

`test.cas` had byte 9 = FF (correct) but byte 10 = 00 (following the
"gap flag" reading) - an invalid combination matching no row. Since
CLOAD's dispatch branches primarily on byte 10, treating 0 as "crunched/
tokenized", it took the raw ASCII program text and tried to load it
directly as pre-tokenized binary program data - exactly the kind of
corruption that produces a garbage line number like "8272". Regenerated
`test.cas` with byte 10 = FF (matching the BASIC ASCII row exactly),
re-verified bit-accuracy against the corrected file (still all 329 bytes
match). This is a test-file-only fix - no RTL change, no rebuild needed,
just replacing `test.cas` on the SD card.

## 2026-09-27 — hardware test (corrected test.cas) — progress, but stalls

Real progress this time: after `CLOAD`, the screen shows `F TEST`
(BASIC's own "found TEST" display - matches the ASCII+MODE byte fix
actually taking effect) and then hangs there - confirmed a genuine stall
(user waited 30+ seconds, well past what a slow load should need), not
just "still working". One more visual detail worth keeping in mind but
not chasing yet: the `F` specifically has a black background, unlike the
rest of the line - could be a normal Color BASIC "search in progress"
cursor indicator, or could be a stray write landing in video memory.

The existing diagnostic's later stages are all *sticky* ("did this ever
happen") - fine for catching a pipeline that never starts at all, but
useless for telling "still actively reading" apart from "read started,
then got stuck partway through", which is exactly this new symptom.
Added a live watchdog: resets whenever `cas_addr` (the tape player's
read position) changes, flags a stall (new cyan color) if it hasn't
moved in ~1 second despite the motor being on and the read not yet
having reached the end of the file. Green now specifically means
"still progressing right now, or successfully finished" - cyan means
"started, then got stuck at a fixed position". Rebuilding to test -
this should say definitively whether `cas_player`/`cas_ram` themselves
are stuck, or whether the real machine (CPU/SAM/PIA) is what's not
progressing despite tape data continuing to arrive correctly.

## 2026-09-27 — hardware test (stall watchdog) — green after 60s, still no visible progress

Green, not cyan - not stalled at a fixed position by the watchdog's
definition. But the screen still showed no change (still `F TEST`) after
a genuine 60-second wait. Green as previously defined couldn't
distinguish "still actively progressing" from "already fully read the
whole file" - both count as "not stalled". Given a 329-byte file
shouldn't plausibly need 60+ seconds even accounting for real CPU-side
overhead per byte, "already finished" became the more likely reading.

Read the actual CLOAD dispatch and block-read routines in "Color BASIC
Unravelled" to understand what happens after the data block: for a
BASIC ASCII file, CLOAD sets the device number to tape and jumps into
`LAC7C` - **BASIC's own normal direct-mode command loop** (the same code
that runs at the keyboard "OK" prompt). Each "input line" it reads comes
from tape instead of the keyboard (since DEVNUM is now cassette), gets
merged into the program because it starts with a line number, and this
repeats until "get a character" (`LA171`) detects no more data (a
sticky-per-line-input `CINBFL` flag) and closes the file, returning to
the keyboard and printing `OK`. The per-block fetch logic (`LA635`)
checks each block's type: a data block (positive, non-zero) gets its
length loaded into a character counter; a block with the high bit set
(matches this project's `0xFF` EOF block type exactly) returns
immediately via `LA657` (a bare `RTS`) with no new characters - the
signal the caller uses to detect end-of-input.

Added a further diagnostic distinction: whether `cas_addr` has actually
reached the last valid position (fully consumed), not just "not
currently below the stall threshold" - a new magenta color, separate
from green (still actively progressing, below the end). If it comes back
magenta, the tape side is provably done and the entire remaining bug is
in Color BASIC's own end-of-file detection/return-to-prompt sequence,
not in any of this project's own RTL. Deliberately *not* also changing
`test.cas` this round (e.g. the second leader between the filename and
data blocks, which the disassembly doesn't show BASIC explicitly
expecting a motor-cycle/gap for, contradicting the earlier "gap flag"
reading of that byte a second time - still a candidate, but changing two
things in the same test would confound which one mattered). Rebuilding
to test.

## 2026-09-27 — hardware test (end-of-file diagnostic) — magenta

Confirmed: `cas_addr` reached the last valid position. The tape side is
provably done - every byte, including the EOF block, was delivered.
Color BASIC still hung at `F TEST` past 60+ seconds. The entire
remaining bug is in Color BASIC's own end-of-file detection/return-to-
prompt logic, not in this project's RTL - `cas_player`/`cas_ram`/
delivery are now proven correct beyond reasonable doubt (bit-accurate
regression test, full hardware completion, two independent test files).

Traced `LA701`/`LA6E5` (the actual block-read/error-check routine
`LA635` calls) in "Color BASIC Unravelled" for more detail on EOF
handling - confirms the same "BLKTYP negative = last block" convention
already used, including a note that block number `$FF` specifically
causes CLOAD to "ignore errors in the blocks it's skipping while looking
for the correct file name" (a filename-search-specific behavior, not
directly relevant to the data-read hang, but confirms `0xFF` is
consistently "end of program" throughout the ROM, not just in the one
branch already found).

Given the RTL side is now fully proven, tried a cheap (test.cas-only,
no rebuild) experiment isolating the one remaining candidate flagged
but not yet tested alone: removed the second 128-byte leader between
the filename and data blocks entirely (going straight from the filename
block's own trailing magic byte into the data block's header) - the
disassembly shows no explicit gap/motor-cycle instruction between
finding the filename and fetching the next block, contradicting the
"gap flag" reading of that byte that originally motivated adding it.
Also fixed an independent, unrelated bug noticed along the way while
re-reading the token research from earlier in this session: `GOTO`
tokenizes as `GO` (a real token) followed by literal, unshortened text
"` TO`" - not a single word - so the test program's second line now
reads `20 GO TO 10` instead of `20 GOTO 10`. This wouldn't explain a
*hang* (a tokenizing mismatch would surface as an error when that line
runs, not block progress before then), but it's a correctness bug
worth fixing regardless while already touching this file. Re-verified
bit-accuracy against the new 202-byte file (down from 329 - no second
leader) - still exact. No RTL change, no rebuild - just the file on the
SD card.

## 2026-09-27 — hardware test (leader removal + GO TO fix) — same hang

After a *full core reset* (ruling out contamination from an unrelated
Jet Set Willy `?FM ERROR` attempt in the same session, which had briefly
made `test.cas` behave differently - `?IO ERROR` and an empty `LIST`,
consistent with leftover tape-device state from the earlier failed
attempt, not a real finding about `test.cas` itself), the original hang
reproduced exactly: magenta again.

More importantly: also tried Jet Set Willy again, this time with the
*correct* command for a machine-code file (`CLOADM`, not `CLOAD`) - shows
its real loading screen, then hangs there too, also magenta. **Two
completely unrelated files** (a hand-built ASCII BASIC program and a
real commercial machine-code game, each loaded with the command
appropriate to its own type) **hang identically**: full tape delivery
confirmed, then no further progress. That's strong, convergent evidence
the bug isn't in either file's specific content/format at all - it's in
something generic to how `cas_player.sv` behaves once a file finishes.

Found a real gap: `cas_player.sv`'s `ST_DONE` state held `casdout`
permanently, silently low forever once the file finished - genuine,
edge-free silence. Real cassette tape, even blank/run-out sections,
never produces that; there's always *some* signal to synchronize
against, and it's the software's job (via block-type/checksum checks -
which Color BASIC's own CLOAD routine demonstrably has) to recognize
unexpected data and stop cleanly. An idealized flat signal may be
starving the CPU's bit-timing-measurement logic of an edge it's
implicitly always waiting for, if it never expects that edge to
structurally never arrive.

Fixed: end of file now loops back to the start and keeps playing,
rather than going silent. Updated `tb_cas_player.sv`'s "end of tape"
test to match (was explicitly asserting silence - now asserts the
opposite: `cas_addr` wraps to 0 and `casdout` keeps toggling). This is a
real RTL change, not a test-file tweak - needs a rebuild and a fresh
hardware test on both files.

## 2026-09-27 — hardware test (loop fix) — real progress, new symptoms

`test.cas` + `CLOAD`: no more infinite hang - now a clean `?IO ERROR`.
Genuine progress: the CPU is no longer stuck waiting for an edge that
structurally could never arrive (confirming the loop-fix theory), but
what it finds on retry is this project's own file *looping back to its
start* - the leader and filename block again - which `CLOAD` correctly
rejects as an unexpected header block where it expected another data-or-
EOF block. Exactly the failure mode the fix's design predicted as a
possible next step, not a new mystery.

Jet Set Willy + `CLOADM`: loading screen shows, then sticks - green
square this time (previously magenta pre-fix), consistent with
`cas_player` now continuously looping/still running rather than sitting
idle - expected given the fix, but the *game itself* still hasn't
progressed. `CLOADM`'s own machine-code loading path is different from
ASCII `CLOAD`'s (likely closer to the "load a crunched program directly
into memory" routine read earlier, not the character-by-character line-
input loop `test.cas` exercises) - whether it hits the same class of
issue or something else entirely isn't yet known; not chasing this one
further until `test.cas` is fully resolved, to avoid diluting focus
across two different code paths at once.

Fixed the specific `test.cas` symptom without any RTL change: padded
the file with 10 repeated EOF blocks at the end (60 bytes) instead of
just one - `cas_player.sv` has no concept of the `.cas` format's block
structure at all (it just plays bytes as tone cycles), so teaching it
to loop *only* the last block specifically would need real new
complexity; multiplying the trailing EOF blocks gives the same effect
for free, purely as file content. Any retry-after-EOF now finds another
valid "no more data" signal instead of wrapping into the leader, unless
`CLOAD` retries more than 10 times in a row (not expected). Re-verified
bit-accuracy against the new 256-byte file (up from 202) - still exact.
No RTL change, no rebuild - just the file on the SD card.

## 2026-09-27 — hardware test (10 EOF blocks) — same ?IO ERROR

Padding to 10 EOF blocks didn't change the outcome at all - identical
`?IO ERROR`. Real negative evidence: if the bug were "retry lands on
the leader after wrapping", 10 valid EOF blocks in a row should have
absorbed any reasonable number of retries. Getting the *same* error
suggests either the error happens on the very first EOF encounter (not
a retry at all), or BASIC retries far more than 10 times.

Went looking for independent confirmation of the file format rather
than continuing to guess: found `cassette-nibbler`
(github.com/eightbitjim/cassette-nibbler), a real, working Java library
for decoding actual recorded cassette tapes (TRS-80/CoCo support).
Its `TapeBlock.java` checksum logic, block-type constants (0x00/0x01/
0xFF), and framing (128×leader + `0x55,0x3C` + type + length + data +
checksum + trailing `0x55`) match this project's implementation
exactly, byte for byte - strong independent confirmation the file
format itself is correct. Also independently recomputed both the data
block's and EOF block's checksums from scratch in Python against the
actual file bytes - both match exactly. This rules out a checksum/
format bug in `test.cas` about as thoroughly as possible without
access to real Color BASIC ROM source.

Given the "retry more than 10 times" possibility couldn't be ruled out
cheaply any other way, tried a much larger safety margin: padded to
200 repeated EOF blocks (1396 bytes total, up from 256). Fixed two
testbench-only bugs found while re-verifying (`tb_cas_fullfile.sv`'s
memory array was only 512 bytes, too small for files this size, and
the run timeout was too short to finish playing back the larger file) -
neither affects real hardware, only the simulation harness itself.
Re-verified bit-accuracy against the full 1396-byte file - all bytes
match exactly. No RTL change, no rebuild - just the file on the SD
card, under real time pressure (a 2-hour session limit on the user's
end), so shipped without waiting for the full re-verification to
finish first.

## 2026-09-27 — hardware test (200 EOF blocks) — CLOAD actually finishes

Real breakthrough: `CLOAD` with the 200-EOF-block `test.cas` **finishes**
- no hang, no `?IO ERROR`. The retry-count theory was right; 10 wasn't
enough margin, 200 was. Diagnostic shows cyan (motor on, then stalled)
rather than green - almost certainly a harmless diagnostic artifact,
not a real problem: real Dragon software turns the tape motor off once
loading completes (matching authentic hardware behavior), and the
stall-watchdog can't currently distinguish "motor off because we're
done" from "motor still on but genuinely stuck". Not investigated
further this session.

`RUN` produced no visible output. **Not yet determined** whether the
program actually landed in memory (`LIST` was the next diagnostic step,
not yet run) or loaded but has some other problem. Session paused here
at the user's request to prioritize a separate, more urgent issue - see
next entry. Resume by checking `LIST` on a fresh `CLOAD` of the current
`test.cas`.

## 2026-09-28 — undocked video: random static, no pattern (new priority)

User asked to pause cassette work (see above - resume point unchanged)
to prioritize two new items: an on-screen keyboard for undocked use,
and a report that undocked video "just displays a multicoloured
garbled mess". Asked a clarifying question about what the garbage
looks like - user answered "Random static/noise, no pattern".

That answer is consistent with the scaler's receiver never achieving
sync lock at all (as opposed to locking onto a wrong/unstable timing,
which would look more like tearing or a stable-but-wrong image).
Leading theory: this core's real frame rate is very low (~15 FPS,
derived from mc6847pace.vhd's own H_TOTAL_PER_LINE=463 x
V2_TOTAL_PER_FIELD=262 vclk-tick raster timing), and video_rgb_clock
was being driven directly from that real, slow per-pixel rate
(dragon_vclk). The Pocket's built-in LCD only supports 30-62Hz
(Analogue's published specs) - docked (HDMI) is presumably more
tolerant, matching why this worked fine docked ("looks perfect!" in
phase 1) but not undocked. A sibling project
(`OpenFPGA_ZX-Spectrum`) driving video_rgb_clock from an equally
derived/gated clock, not a raw PLL output, and presumably working
undocked too, ruled out "derived clock" per se as the problem - it's
specifically the *rate* being too low.

**Fix**: added `src/fpga/core/dragon/video_frame_buffer.sv`, a small
frame buffer (49152 x 24-bit words, one screen) that decouples the
scaler's output timing from the machine's own real pixel rate. Real
Dragon pixels are written in at their native (slow) rate on the
`clk_dragon`/`dragon_vclk` side; a separate, fixed, clean ~45.7Hz
scan-out (320x210 total, 256x192 active, derived from `clk_core_12288`
- already present in `core_top.v` for other purposes, previously
unused for video - by /4 clean-toggle dividers) continuously re-reads
the same buffer out to the scaler. The image still only *updates* ~15
times a second (unchanged - the machine itself isn't any faster), but
the scaler always sees a normal, lockable refresh rate now. Uses the
same `dpram_1r1w` true dual-clock dual-port RAM primitive already used
throughout `dragoncoco.sv` for ROMs.

The cassette diagnostic corner-patch overlay (`cas_diag_patch`/
`cas_diag_color`, still present/unresolved from the paused cassette
work) now applies on the *write* side (an `wr_overlay_en`/
`wr_overlay_color` input to `video_frame_buffer`) rather than directly
on `video_rgb`, so it's unaffected by this change and still uses its
original, already-hardware-validated `dragon_h_count`/`dragon_v_count`
coordinate math.

Verified in simulation (iverilog, `/tmp/tb_vfb.sv` - not part of the
repo, ad hoc) before shipping to hardware: all 49,152 write-side
pixels land at the correct address with correct data; the read-side
timing generator produces exactly 320*210=67,200 dot_clk cycles
between vsync pulses as designed; and a full active-line readback
through the real `rd_rgb`/`rd_de` output pipeline (not just raw RAM
contents) confirms the one-cycle RAM read latency is correctly
accounted for, with no off-by-one shift. Found and fixed one real gap
in the process: the read-side counters (`h_cnt`, `v_cnt`, `dot_div`,
`dot_div_90`, and the de/hsync/vsync pipeline registers) had no
explicit power-up value, which is harmless on real Cyclone V hardware
(Quartus honors an RTL `initial value` as the register's power-up
state) but left them permanently unknown (X) in simulation with no way
to ever recover, since there's no reset input on this module - added
explicit `= 0` initial values to all of them.

Not yet tested on real hardware - this is the next thing to check
(undocked, on the actual Pocket).

## 2026-09-29 — new SD card, video fix confirmed working undocked

User's old SD card had failed outright (undetected by both the Pocket
and a computer card reader - a genuine hardware failure, unrelated to
any core file). New card ("analogue") in use from this session on.
Installed the current `main` build (commit `7d3fa57`, the frame-buffer
video fix above) by downloading the matching GitHub Actions artifact
(`Dragon32-pocket-core`, run `36398117424`) rather than building
locally (Quartus only runs via the Docker/CI path on this machine) and
copying `Cores/McNast13.Dragon32/`, `Platforms/dragon32.json` +
`_images/dragon32.bin`, and `Assets/dragon32/McNast13.Dragon32/` onto
the card, byte-verified against the downloaded artifact (MD5 match on
`bitstream.rbf_r`).

**Undocked video fix confirmed working on real hardware.** The frame
buffer resolves the "random static/no pattern" symptom - no further
action needed here unless a regression shows up.

`test.cas` wasn't on the new card yet (cassette testing was paused
before the card failure, so it was never carried over). Added it to
`Assets/dragon32/common/test.cas` (the standard openFPGA browse path
for a core's optional/no-fixed-filename data slots - matches the
convention seen in other installed cores' `Assets/<platform>/common/`
folders), copying the current repo copy (1396 bytes, 200 trailing EOF
blocks) byte-verified by MD5. Resume point unchanged from the
2026-09-27 entry: fresh `CLOAD` of `test.cas`, then `LIST` (not `RUN`)
to check whether the program landed in memory correctly.

## 2026-09-29 — hardware test (200 EOF blocks, new card) — CLOAD/RUN both OK, LIST empty

Fresh `CLOAD` of `test.cas`: `OK`. `RUN`: `OK`, no visible output.
`LIST`: `OK`, no program listed. Real finding, not just "still
untested": `CLOAD` reports success with **no error at all**, yet the
program never lands in memory - ruling out a hang or a detected bad
checksum, and pointing at something in the ASCII-mode `CLOAD` path that
silently fails to store the tokenized program despite believing (or not
checking) that it succeeded.

Investigated a real, independent bug before chasing that further:
`cas_player.sv`'s `ST_FETCH` state samples `cas_data` one cycle too
early relative to `cas_ram.sv`'s actual registered-read latency
(`rd_data <= mem[rd_addr]` - a genuine 1-cycle synchronous read), a
mismatch neither `tb_cas_player.sv` nor `tb_cas_fullfile.sv` could catch
because both used an idealized, zero-latency combinational stand-in
(`wire cas_data = mem[cas_addr]`) instead of the real `cas_ram` module.

Traced the actual effect by hand, got it wrong once (concluded
"corrupting" on first pass), then verified properly by simulating
`test.cas` through the *real* `cas_ram.sv` (ad hoc testbench, not part
of the repo). The bug is a clean one-slot delay, not corruption: byte 0
plays twice, every real byte after that plays exactly once in the
correct order, and only the file's absolute last byte (buried in 200x
redundant EOF padding) is dropped. Since byte 0 of a `.cas` file is
always a leader byte (`0x55`, ~128 of them in a row), duplicating it is
indistinguishable from "one extra leader byte" - completely harmless.
Direct evidence: the simulated decode of the real data block, byte for
byte, produced `10 PRINT "HELLO FROM CLAUDE"` / `20 GO TO 10` exactly,
correctly ordered, checksum intact. **This bug is ruled out as the
cause of the empty `LIST`** - consistent with Jet Set Willy's `CLOADM`
separately getting as far as its own loading screen, which wouldn't
happen if this bug broadly corrupted post-leader content.

Fixed anyway since it's a real RTL/documentation mismatch worth having
correct regardless: added an `ST_FETCH2` state so `cas_player.sv` waits
the full cycle `cas_ram.sv` actually needs before capturing `cas_data`,
instead of one cycle short. Updated both `tb_cas_player.sv` and
`tb_cas_fullfile.sv` to instantiate the real `cas_ram` module rather
than their idealized lookups, so this class of bug can't hide from
either test again. Re-verified: `tb_cas_player.sv` passes (one
hardcoded startup-fill cycle-count constant needed bumping - measured
empirically off the fixed sim, not re-derived by hand, given the
hand-derivation mistake earlier in this entry); `tb_cas_fullfile.sv`
reports `ALL 1396 BYTES MATCH - cas_player is bit-accurate` against the
real RAM timing.

**Still unresolved**: why ASCII `CLOAD` reports `OK` without ever
storing the program. Since the cassette bit-delivery pipeline itself is
now confirmed correct (both by this fix and by the pre-fix content
tracing above), the next place to look is Color BASIC's ASCII-mode
line-by-line tokenizing path specifically (distinct from `CLOADM`'s raw
block loader, which JSW's testing shows gets further) - or the core's
PIA/`casdout` wiring into the CPU side (`dragoncoco.sv`) rather than the
tape-playback engine itself.

## 2026-09-29 — decisive test: hand-typed BASIC program works fine

At the user's request, typed a trivial `PRINT` program directly at the
keyboard (no cassette involved at all) and ran it - worked correctly.
This rules out "BASIC program storage/editing is broken in general" on
this core - the machine can create, keep, and run a program just fine.
Combined with the RAM-latency investigation above (tape delivery
independently proven bit-accurate) and JSW's `CLOADM` getting as far as
its own loading screen, the bug is now narrowed specifically to ASCII
`CLOAD`'s own mechanism of re-feeding tape bytes through the line-input/
tokenizer as if typed - not the file, not general storage, not raw byte
delivery.

Built `test_crunched.cas` (`generate_test_crunched_cas.py`) to test this
directly: the same trivial program, pre-tokenized ("crunched") instead
of ASCII source, so it loads via the TYPE=00/ASCII=00/MODE=00 path -
which, per the disassembly-sourced note in `generate_test_cas.py`,
shares its low-level block-fetch with `CLOADM`'s raw loader (the path
already confirmed to make real progress). If this loads correctly where
the ASCII file doesn't, that confirms the bug is confined to ASCII
CLOAD's re-tokenizing mechanism specifically.

Sourced the tokenized-program format from public references
(subethasoftware.com's Color BASIC memory-format writeup, corroborated
by MSX-wiki/GW-BASIC's tokenized-format pages describing the same
Microsoft BASIC-derived scheme) and confirmed `PRINT`=`$87`/`GO`=`$81`
against `archive.worldofdragon.org`'s token table (consistent with this
project's existing dragon32.info-sourced token facts). Verified
bit-accurate playback through the real (post-fix) `cas_ram` timing model
before shipping to hardware - `ALL 1392 BYTES MATCH`.

**Flagged, unresolved risk**: the crunched format bakes in absolute
"next line" memory addresses (crunched CLOAD copies bytes directly into
place with no relocation), which requires knowing the real runtime
BASIC program-start address (TXTTAB) in advance. Used `$1E00`, per
dragon32.info's memory map explicitly describing the *Dragon's* (not
just generic CoCo's) post-boot free memory start - but generic CoCo
references for machines with Extended BASIC instead cite `$1E01`, a
1-byte discrepancy no available documentation resolves. If
`test_crunched.cas` fails to load with a plausible-looking address
error, the fix is cheap: type `PRINT PEEK(25)*256+PEEK(26)` after a
fresh `NEW` to read the real value directly from this core's own running
ROM, then regenerate with `TXTTAB` set to match.

Added `test_crunched.cas` to the SD card at
`Assets/dragon32/common/test_crunched.cas` (MD5-verified) alongside the
existing `test.cas`. Not yet tested on hardware.

## 2026-09-29 — hardware test (test_crunched.cas, first attempt) - same symptom, plus a real keyboard gap found

`CLOADM` on `test_crunched.cas` correctly returned `?FM ERROR` - good
sign, confirms the ROM's TYPE-byte checking works on this core (it's a
TYPE=00 BASIC file, not TYPE=02 machine language, and `CLOADM` correctly
refuses it). Plain `CLOAD` then `LIST`: `OK`, then nothing listed -
*same* symptom as the ASCII file. Checked the diagnostic corner color
right after `CLOAD` returned `OK`, before doing anything else: cyan
(motor on, then stalled, not at the true end of file). Initially treated
this as new evidence for a "CLOAD retries repeatedly, each retry wipes
the program" theory - but on review this is the exact same cyan the
2026-09-27 session already saw and correctly wrote off as harmless
(motor legitimately turns off once BASIC is satisfied, long before
actually consuming all 200 redundant EOF-padding blocks - the
stall-watchdog just can't tell "motor off because done" from "motor off
because stuck"). Retracted that theory; this diagnostic doesn't actually
discriminate between it and normal success.

Separately, chasing what key produces `*` (needed to type
`PEEK(25)*256+PEEK(26)` as a diagnostic) surfaced a real, independent
bug: real Dragon/CoCo keyboards produce `*` via Shift+`:` (same
bit-paired-ASCII scheme confirmed earlier for Shift+8=`(` - `:`=0x3A,
`*`=0x2A, same 0x10 offset). But `dragon_keyboard.sv`'s handling of the
`:`/`;` key (USB HID 0x33) unconditionally suppresses Dragon's own SHIFT
line whenever it maps to the colon position ("Dragon has separate
dedicated keys, no shift needed either way" - true for plain `:`/`;`,
but incomplete: Shift+`:` is a real, distinct, currently-unreachable
combination). **No key combination on this core can currently produce
`*` at all.** Not yet fixed - noted here so it isn't lost; likely fix is
mapping the USB numpad-multiply key (HID 0x55) directly to Dragon
Shift+colon, rather than disturbing the digit row's existing (correct)
behavior.

Worked around the immediate diagnostic need by asking for `PEEK(25)` and
`PEEK(26)` separately (`30` and `1`) instead of the combined expression.
**This resolved a real, concrete bug in `test_crunched.cas` itself**:
`30*256+1 = 7681 = $1E01`, not the `$1E00` guessed - confirming the
generic-CoCo reference over the Dragon-specific one this project had
weighted more heavily. Fixed `generate_test_crunched_cas.py`'s `TXTTAB`
constant to `0x1E01`, regenerated (line 1's `next_line_addr` now
correctly `0x1E1A`, not the wrong `0x1E19`), re-verified bit-accurate
playback through the real `cas_ram` timing model (`ALL 1392 BYTES
MATCH`), and re-copied to the SD card (MD5-verified). **Not yet
re-tested on hardware** - this is the immediate next step next session.

Current understanding heading into next session: the ASCII `test.cas`
failure and the (now-corrected) `test_crunched.cas` failure may or may
not share a root cause - the crunched file's failure had an obvious,
sufficient, independent explanation (wrong hardcoded address) that had
nothing to do with `CLOAD`'s ASCII-vs-crunched code path distinction.
If the corrected crunched file now loads/lists/runs cleanly, that
restores the earlier theory (ASCII CLOAD's own line-retyping mechanism
is the one broken thing) with crunched CLOAD confirmed working. If it
*still* fails even with the correct address, that points back to
something shared by `CLOAD` generically (both sub-modes), not ASCII
specifically - worth distinguishing clearly by testing `LIST`/`RUN`
result carefully once more.

## 2026-10-02 — hardware test (corrected test_crunched.cas) - still empty; root cause found in the ROM

Re-tested the `$1E01`-corrected `test_crunched.cas`: `CLOAD` → `OK`,
`LIST` → nothing. So the wrong address wasn't the (only) problem, and
the failure is shared by both CLOAD sub-modes.

**Root cause, confirmed by disassembling the real Dragon 32 ROM**
(`d32.rom`): the ROM's tape "motor on" routine at `$BDCF` sets PIA1 CRA
bit 3 (motor relay) and then immediately spins in a delay loop (`LDX $95`
/ `LEAX -1,X` / `BNE`, 8 cycles/iteration; `$95` is initialised to
`$DA5C` from the ROM's init table at `$BBA5`) - ~447k CPU cycles, about
0.5s of tape at real speed - *before* it starts looking for a sync byte.
The block-read entry at `$BDE5` (`ORCC #$50`, `BSR` motor-on, then the
sync search) is used for every block after the filename. That delay
exists to let a real deck get up to speed, and real `CSAVE` output always
has a leader in front of the data block to soak it up.

`test.cas`/`test_crunched.cas` had *no* leader before the data block
(removed on 2026-09-27 on a wrong reading of the disassembly). And
`cas_player.sv` correctly runs whenever the motor is on - so during that
0.5s spin, the whole ~0.25s data block played out with nobody listening.
The first sync the ROM then found was in an EOF block → `CLOAD` returns
`OK` with nothing loaded. This also explains the whole earlier EOF saga:
with one EOF block it skipped past it too and wrapped into the header
(`?IO ERROR`); 10 wasn't enough; 200 left it landing on an EOF block.
None of that was "CLOAD retrying" - it was the tape running during the
motor-on delay. The ASCII-vs-crunched theory was a red herring.

Fix (test files only, no RTL change): both generators now emit a second
leader between the filename and data blocks, and both leaders are 256
bytes (~1.3s, comfortably > the 0.5s delay). `test.cas` 1396 → 1780
bytes, `test_crunched.cas` 1392 → 1776. The 200 EOF blocks are left in
for now (harmless) - can be trimmed once loading is confirmed.

Implication for real software: real `.cas` dumps of commercial tapes
include proper leaders, so this doesn't affect them - JSW's
reaching-its-loading-screen-then-sticking is a separate question.

## 2026-10-02 — hardware test (second leader) — CASSETTE LOADING WORKS

`test.cas` (ASCII): `CLOAD` → `OK`, `LIST` shows both lines exactly.
**First successful BASIC tape load on this core.** Confirms the
missing-leader diagnosis above.

`test_crunched.cas`: loads, but `LIST` shows only line 10. A bug in the test
file, not the core: the generator gave the last line a link of `0000`, but
in this BASIC a zero link *is* the end-of-program marker (the program ends
with a separate `00 00` after the last line), so line 20 was treated as
the end and never listed. Fixed the generator (line 20 now links to
`$1E26`, followed by `00 00`), regenerated (1778 bytes). Waiting for a
hardware retest.

## 2026-10-02 — Jet Set Willy loads (12 min); audio wired up

`CLOADM` of `JetSetWilly_V2.cas` (34251 bytes: header + 128×255-byte
blocks loading `$0150`-`$80CF`, all checksums good) **loads and runs**
after ~12 minutes - exactly the predicted ~3 min real-hardware load time
× the machine's ~1/4 speed. It was never stuck before, just slow.

No sound: audio had never been connected (`core_top.v` left `sound`/
`sndout` unconnected and output an all-zero I2S stream). Now mixes the
6-bit DAC (`dac.sv`'s `sound`) + 1-bit beeper (PIA1 PB1) into unsigned
15-bit mono through agg23's `sound_i2s.sv`/`sync_fifo.sv` (MIT, same
library as the vendored `data_loader.sv`). One local change:
`sync_fifo`'s dcfifo set to `use_eab = "OFF"` - M10Ks are 308/308 used
by the frame buffer. Expect everything ~2 octaves low (1/4 speed).
Not yet hardware-tested.

## 2026-10-02 — hardware test (audio build e200439) — sound works

Installed CI build of `e200439` (timing met, M10K still 308/308).
`SOUND 89,30` plays a tone on real hardware - audio path confirmed.
(Pitch expected ~2 octaves low at current 1/4 machine speed - see
`docs/SPEED_PLAN.md`.)
Jet Set Willy's in-game music also plays - very low pitched, as expected
at 1/4 machine speed. Confirms the DAC path (not just the 1-bit sound).

## 2026-10-02 — real speed: timing closes at 57.272727 MHz (branch speed/step1-timing-report)

`docs/SPEED_PLAN.md` steps 1-3. Added `tools/timing_report.tcl` + a CI step
that writes per-path reports, set `dragon_pll` back to 57.272727 MHz, then
added multicycle constraints one layer at a time, reading the report each
time:

| Build | Worst setup slack | TNS | What failed |
|---|---|---|---|
| none | -10.276 | -12592.8 | 6809 reg -> 6809 reg, full-cycle, ~27 ns logic |
| + CPU internal (setup 4) | -8.321 | -9187.4 | 6809 reg -> ram1/pia/pia1, half-cycle (negedge->posedge), ~16 ns |
| + CPU outputs (setup 2) | -1.702 | -48.7 | read-data latches (ram_dout, rom8/romC/pia/pia1 _dout2) -> 6809 |
| + read latches (setup 3) | **+1.804** | 0 | - (hold +0.205, all corners pass) |

The earlier "~36 MHz ceiling" conclusion was wrong: it was missing
constraints, not a slow part. Why each number is what it is, including
the cases that must NOT be relaxed (`e_r`/`q_r`, the SAM fast-mode
1.5-period budget for PIA read strobes), is written next to each
constraint in `core_constraints.sdc`. Correction to the plan: my "half-
cycle paths" guess was wrong for the worst layer (full-cycle), right for
the second.

Also step 2 cleanup: removed the cassette diagnostic square (overlay
ports kept, tied off, for the on-screen keyboard) and the unused 90°
Dragon clock.

Simulation can't validate this (it's clock-rate independent) - the
timing report is the check, then hardware: `PRINT TIMER` over 10 s,
`SOUND` pitch, tape load times, JSW.

## 2026-10-02 — hardware test (real-speed build 8cee4a3) — works as expected

Installed the CI build of the speed branch (timing met, +1.268 ns setup,
M10K 308/308). User confirms it works as expected on real hardware
(speed, sound, tape). Merged into `main`. Still NTSC 60 Hz timing - UK
50 Hz is `docs/SPEED_PLAN.md` step 8.

## 2026-10-02 — UK 50 Hz frame timing (SPEED_PLAN step 8) — works

`PAL` parameter (mc6847pace generic via dragoncoco, set to 1 in
core_top): +23 border lines top and bottom, 263 -> 309 lines = 49.93 Hz.
Found along the way: this VDG's lines are 464 ticks (64.81 us), not the
real chip's 456, so the NTSC timing had actually been 58.67 Hz, not 59.94
- and the real Dragon's +25/+25 would have given 49.3 Hz here, hence 23.
CI build timing met (+0.676 ns - tighter than the previous +1.268 ns,
fitter variation; untouched paths), M10K 308/308. Hardware: `PRINT
TIMER` over 10 s ≈ 500 (was ≈ 600) - confirmed 50 Hz. Merged to `main`.

## 2026-10-03 — frame buffer output locked to 50 Hz (SPEED_PLAN step 6)

`video_frame_buffer.sv` read side no longer free-runs at ~46 Hz (which
dropped ~4 of every 50 frames and tore at a drifting line). Lines are now
293 dots (95.38 us) and each frame is frame-locked to the Dragon: it runs
at least 209 lines, then ends at the first line boundary after the write
side's first active pixel of a new frame (a toggle, 2-flop synchronised
into dot_clk). Dragon frame = 209.98 of our lines, so frames come out 210
with an occasional 209 (49.92/50.16 Hz). Because our lines and pixels are
both slower than the Dragon's, the read always trails the write: every
frame is shown whole, once, with no tear.

First attempt held onto a pulse that arrived mid-frame and ended every
frame at 209 - never locked (caught in sim). Fix: only accept the pulse
from line 208 on; an ignored one stretches the frame to 230 lines, which
pulls into lock within a few frames.

Verified in simulation (iverilog, ad hoc testbench in the session
scratchpad: real 57.27 MHz / 12.288 MHz clocks, 464-tick x 309-line
Dragon model stamping each pixel with its frame number), 3 s simulated:
locked by frame 3 (230, 217, then 210...), 149 frames out for 149 in,
zero torn pixels, zero misplaced pixels, no repeated or skipped frames.

NTSC (PAL=0, 58.67 Hz) is faster than this can follow - it would wander
between 209 and 230 lines. Needs retuning if the PAL/NTSC menu option
is ever added.

CI build (run 37118983325): timing met - clk_dragon setup +1.960 ns
(up from +0.676 ns; fitter variation, the changed logic is all on the
12.288 MHz side), hold +0.204 ns, all TNS 0. M10K 308/308, ALMs 26%.
Awaiting hardware test.

### Hardware test: one-frame black dropout, docked and undocked — fixed

User saw a brief one-frame black dropout, both docked and undocked.
Cause: the occasional 209-line frame (the drift correction) - the
scaler blanks a frame whenever the frame length changes. Fix: run the
read side from clk_dragon/16 (3.5795 MHz) instead of clk_core_12288.
A PAL Dragon frame is 309 x 464 x 8 = 1,147,008 clk_dragon cycles =
16 x 348 dots x 206 lines exactly, so every frame is now exactly 206
lines and never needs correcting; the lock (end the frame at the first
line boundary after the write side's frame-start pulse, if in its last
two lines, else run to 230) only acts at power-on/reset. dot_clk_90 is a
registered divider output 4 clk_dragon cycles after dot_clk. The 12.288
MHz PLL stays in core_top (unused by video now).

Sim (same testbench, 3 s): 230, 209, then 206 lines every frame; pulse
lands at line 205 dot 52 every frame (well clear of the boundary); 149
in / 149 out, zero torn/misplaced pixels, dot_clk_90 exactly 90 degrees.

CI build (run 37120070622): timing met - clk_dragon setup +1.614 ns,
hold +0.096 ns, all TNS 0; M10K 308/308, ALMs 26%. The 12.288 MHz PLL
is now optimised away (no longer used). Installed on the SD card,
all files MD5-verified (bitstream.rbf_r f682fcf1...). Awaiting hardware
test.

### Hardware test (run 37120070622) — works

User confirms all good on real hardware: no dropouts, docked or
undocked. Merged to `main`. SPEED_PLAN complete.

## 2026-10-03 — keyboard: `*`, `+` and `=` now typeable

No key combination produced `*` or `+`: on the Dragon they're Shift+`:`
and Shift+`;`, but the `;:` key's PC-style mapping uses Shift to pick
`:`, and the `=+` key wasn't mapped. User chose the minimal fix (keep
the existing mostly-positional mapping; UK keyboard):
- `=+` key (HID 0x2E): `=` -> Dragon Shift+MINUS, Shift+`=` -> `+`
  (Dragon Shift+`;`)
- keypad `*` (0x55) -> Dragon `*`, keypad `+` (0x57) -> Dragon `+`
New `force_shift` flag in `hid_to_dragon` asserts Dragon SHIFT when the
PC key isn't shifted. tb_dragon_keyboard: 23/23 pass (10 new).

## 2026-10-03 — on-screen keyboard (built on kbd-star-plus)

Select opens a 256x62 panel with the Dragon's own key layout (5 rows,
53 keys), drawn into the frame buffer via the kept overlay ports. D-pad
moves (hold: repeat after 20 frames, then every 5), A presses the key
(held while A is held, min 3 frames so a tap registers), B latches Shift
for one key (keys then show shifted symbols; also A on either SHF), X
moves the panel top/bottom. While open, d-pad and A are masked from the
joystick (`cont1_key_game` in core_top). The key goes into
dragon_keyboard.sv as a matrix position + shift (new osd_* ports, through
dragoncoco).

No block RAM: font (63 glyphs, 5x7), key table and position map are
combinational logic generated by `tools/gen_osd_tables.py`, which also
checks every key's matrix position against dragon_keyboard.sv's grid.
Drawing uses the frame buffer's write position (new wr_next_x/y
outputs): a pixel is written every 8 clk_dragon cycles, so a 4-stage
pipeline has the colour ready in time - no multicycle constraints.
Colours primary only: black panel, blue keys, white text, yellow
highlight, green latched SHIFT.

Sim: tb_osd_keyboard (controller, 25 checks) all pass after fixing a
repeat off-by-one; tb_dragon_keyboard 26/26. Rendered frames through
the real video_frame_buffer (iverilog, Dragon video model) and checked
the images: panel bottom with '1' highlighted; Shift latched (shifted
labels, green SHF); panel at top. Found along the way: iverilog never
runs `always @(*)` blocks whose inputs don't change after time 0, so
the tables now use always_comb.

input.json: button names for Select/A/B/X (kept to 19 chars).

CI build (run 37123787609): timing met - clk_dragon setup +0.822 ns
(worst path is the existing SAM clk_e -> 6809 half-cycle path, not the
OSD: fitter placement shifted with the extra logic), hold +0.204 ns, all
TNS 0. ALMs 28% (was 26%), M10K 308/308 unchanged. No new critical
warnings (same 11 in map as before). Not installed yet - awaiting go-ahead.
Installed on the SD card, all files MD5-verified (bitstream.rbf_r b506c706...). Awaiting hardware test.
