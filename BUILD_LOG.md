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
  Fix: switched to integer-N mode (`fractional_vco_multiplier("false")`) —
  phase 1 doesn't need bit-exact frequency, so trading precision for a PLL
  that actually closes timing is the right call. **Did not test this build
  on hardware** — pushing a known timing failure to real hardware risks a
  wasted test cycle for no useful information.
