# Trajectory recovery — 2026-09-26

CURRENT PHASE: A–M complete technically; N/O correction commit and normal push next. Player perceptual acceptance pending.

ORIGINAL RESEARCH RECOVERED: YES. BLOOD_PHYSICS_RESEARCH.md, continuity audit, rain research and fall-speed report recovered. Density1055, viscosity.0048, tension.060; Schiller–Naumann drag, diameter/equivalent mass separate from represented mass. No new research needed.

KINK ROOT CAUSE: blood_fluid_model.assist_descent activates full35m/s² below−.15m/s, cancels vertical drag then hard converges/clamps target/cap. Previous fall-speed report confirms MEDIUM collapses to exactly−9.5. This is uncommitted work after4611c0a, not an invented historical commit.

STALE ORIGIN ROOT CAUSE: DummyTarget._die hands wounds to add_remnant at old root position; Weapon.apply_hit opens another lethal remnant at hit snapshot. Wound.detach stores world_anchor; _tick_wounds calls fall with only Y. Meanwhile DummyTarget moves/rotates only Visual during death throw, then hides it. No body source is tracked by remnants. Living wounds follow root, not Visual lean.

Plan: continuous velocity-weighted bounded downward force, retain aerodynamic drag and diameter response; current visible body transform resolved only for future releases using instance IDs/generation. Invalid/hidden body terminates source. Existing airborne arrays never follow body.

SMOOTH ASSIST STATUS: implemented. Weight1−smoothstep(−3,.5,previousY); drive rolls off smoothly between.8target/cap; smooth braking above cap.35m/s² bounded contribution; aerodynamic vertical response retained, no velocity replacement/clamp.
VISIBLE KINK: no force discontinuity in numeric fixture; player perception pending. FAST DESCENT: model MEDIUM >8m/s by300ms across five launches; real2m fall<.45s.
IMMEDIATE RELEASE SEMANTICS / FUTURE RELEASE / RELEASED INDEPENDENCE: PASS deterministic THE_BOX checks (105 already released drops unchanged by moving source).
GHOST NECK: source follows thrown Visual then expires when hidden; fixture PASS. Perceptual final pending.
HAND CANNON / DAGGERS / MAUL / GRENADE: PASS technical actual THE_BOX gameplay events, headless and one native process; no claim of human visual approval.
DENSITY / TRAILS / READABILITY / PUDDLES / FADE / RUNOFF PRESERVED: configuration/renderer unchanged;42 stability checks passed including wet pools/support/runoff/accounting.
MEMORY P0 STATUS: historical0xC0000005 unresolved; all completed fixtures exit0; no crash. Exactly one graphical Compatibility process, exit0. Wrapper parse/setup errors preserved and corrected; not native crashes. Orphan-registry cleanup edge case added afterward and verified in a focused headless test; no second graphical run.
GIT COMMIT: approved preexisting runtime baseline checkpoint77f6b92. Current correction reviewed, commit pending.
GIT PUSH STATUS: pending; main / origin https://github.com/surdodeumlado/blood.git.
LAST COMMAND: focused orphan-source fixture exit0; report and compact summary generated. Six existing production files changed this pass, no new production resources.
NEXT EXACT ACTION: stage only six production edits, four trajectory fixture scripts/scene, inherited live-fixture dependencies, stability-test baseline compatibility, report/handoff/summary. Review cached diff, commit correction, inspect remote/upstream and normal push. Preserve all other local artifacts.

Measured: MEDIUM high arc peak3.820659→3.820345m; +300ms after apex9.168m/s(33km/h). THE_BOX2m contact.383s. Initial grenade counts222/320/364 preserved; peaks329/467/514; streak capacity192. Source peak4, final0. Detailed limitations and metrics in BLOOD_TRAJECTORY_RECOVERY_REPORT.md.
