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
