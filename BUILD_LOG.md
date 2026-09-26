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
