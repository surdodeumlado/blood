# Native crash during validation — 2026-09-23

## What crashed

```
godot --headless --path . res://tests/blood_stability_test.tscn
```

Exit code **139 (SIGSEGV)**. Godot 4.7.2.stable.steam.ed1daf0bf, Windows 11,
`--headless` (dummy RenderingServer).

Full output preserved verbatim in
[`blood_stability_test_segfault.log`](blood_stability_test_segfault.log).

## Where in the run

**After the test finished.** The log ends:

```
STABILITY: 46 checks, 0 failed
STABILITY: presentation stopped
STABILITY: mixer drained; quitting
```

All 46 assertions ran and passed — mass conservation for 1/2/4/8 victims, every
budget bound, the audio clustering checks (100 simultaneous impacts → one
cluster, six pooled voices), the MultiMesh single-commit rule. The test then
performed its own orderly teardown (`presentation stopped`, `mixer drained`) and
called `quit()`. The segfault happened during **engine shutdown**, after that.

No Godot crash handler output, no backtrace, no `ERROR:` line anywhere in the
log. The dying process produced nothing.

## What was NOT done, deliberately

The pass brief is explicit: *"If ANY native crash occurs: STOP native
validation. Preserve the log. Do NOT keep retrying."*

So, after this crash:

- the stability test was **not** re-run,
- `tests/blood_shutdown_probe.gd` was **not** run (its own header warns against
  looping it until an intermittent crash passes),
- **no windowed Compatibility (GLES3) validation was run at all.**

That last one matters and is not a formality. This pass changed three shaders
(`blood_stain.gdshader`, `blood_liquid.gdshader`) and the material wiring that
feeds them. A shader that fails to compile is invisible to a `--headless` run,
because the dummy renderer never compiles one. **The airborne readability boost,
the impact bloom and the new stain warp have therefore not been seen on a GPU
and are not claimed to work.**

## Prior art

`tests/blood_shutdown_probe.gd` already exists to isolate a shutdown crash in
this area, with three explicit modes (`--world`, `--resources`, default audio).
Its header says: *"Do not loop this probe to turn an intermittent crash into a
passing result."* So a shutdown-time crash here is a known, previously
investigated hazard rather than something this pass introduced evidence about
either way.

## What is and is not implicated

Not evidence of a cause, only of what was in the process at the time:

- the run had just exercised the **audio accumulator** hardest of any test in
  the suite (100 simultaneous impacts, six pooled `AudioStreamPlayer`s), and
  this pass changed that file (a fourth density tier: 4 surfaces x 4 tiers = 16
  synthesised `AudioStreamWAV`s instead of 8),
- the same orderly-teardown sequence in `tests/blood_material_test.tscn` exited
  **0** in this same session,
- every other suite exited 0.

The honest statement is that this is unexplained. It is not reproduced, not
bisected, and not attributed.
