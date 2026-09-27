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
