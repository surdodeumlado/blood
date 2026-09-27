# Weapon signature handoff — 2026-09-26

CURRENT PHASE: implementation, feasible technical validation, Git review, commit and normal push complete. Full-speed player acceptance remains pending. STOP AFTER THIS PASS.
ORIGINAL RESEARCH RECOVERED: YES. BLOOD_PHYSICS_RESEARCH sections11–13 and pattern/profile history since12d862b. Baseline5a41f7f.
BALLISTIC ROOT CAUSE: no launch regression measured; original directional/back-spatter signature retained.
SLASHING ROOT CAUSE: generic blended frame instead of actual cut tangent; edge speed and total-mass multiplier exaggerated launch. Corrected tangent, statistical speed weighting, tip-based calibration.
BLUNT ROOT CAUSE: alignment already near1 made nearly all travel speeds high, then logical mass boosted again. Corrected decaying launch distribution; local40% retained.
HIGH_ENERGY ROOT CAUSE: physical SMALL in medium render layer bypassed carrier launch calibration (159.12m/s max). Initial-only smooth compression into existing spray envelope; fine-layer speed distribution/mass boost corrected. High arcs/carriers untouched.
CAST_OFF STATUS: separate loaded-blade mass, actual tip velocity once, no stacking. Live Daggers4/Maul7 cast-off reps observed.
BALLISTIC P50/P90/P99 RANGE:2.15/5.53/5.53m.
SLASHING P50/P90/P99 RANGE:2.60/4.93/6.66m.
BLUNT P50/P90/P99 RANGE:2.74/4.66/8.29m.
HIGH_ENERGY P50/P90/P99 RANGE:2.85/4.89/9.67m.
INITIAL SPEED P50/P90/P99 BY FAMILY (m/s): ballistic17.69/38.39/52.91; slash8.47/16.88/26.12; blunt4.98/14.68/20.08; explosive16/34/41.52.
CAUSAL VISIBILITY IMPLEMENTED: YES. Six fixed priority buckets, actual camera frustum, represented consequence, current speed/direction; same192 streak capacity/geometry. Statistical-only forward probe localized7m→2m; no physical range kill and no surface morphology edits.
FAR-STAIN INVISIBLE-FLIGHT RATE: final open major >=5m contacts with <10% relevant streak time:0/8 ballistic,0/9 slash,0/12 blunt,0/26 explosive. Native7m wall traces: three matched stains with90.9–100% in-frustum streak time. Not an occlusion/attention guarantee; full-speed perception pending. No7/18m physical wall hits for Cannon/Daggers in this seed; not fabricated as passes.
DENSITY PRESERVED: YES admission/count settings unchanged, open births33/104/258/222; grenade320/346 for2/4 victims. Breakup/near-wall subsequent cast-off counts vary with changed initial flight; documented in report.
GLOBAL FALL MODEL PRESERVED: YES.
STREAK SHAPE PRESERVED: YES.
PUDDLES PRESERVED: YES implementation and regressions.
FADE PRESERVED: YES.
RUNOFF PRESERVED: YES.
WOUND ORIGIN FIX PRESERVED: YES; no lifecycle edits.
VALIDATION: model clean;14-case final headless exit0; existing regression42/0; ONE Compatibility process21cases exit0, including all four actual weapons, captures and trace-disabled1/2/4-victim performance. No more graphical runs planned.
PERFORMANCE: native trace-disabled physical CPU mean/P95/peak ms:1 victim1.210/3.715/7.750;2 victims1.575/5.580/13.695;4 victims1.813/7.417/15.745. Physical peaks317/423/454; fixed192 streaks. Details/limits in BLOOD_WEAPON_SIGNATURE_REPORT.md.
MEMORY P0 STATUS: historical0xC0000005 unresolved; NONE observed this pass. No new production nodes/resources/histories, resizing or teardown changes. Fixture overflow0. RAM high-water not measured.
KNOWN LIMITATIONS: preexisting absent foley warning, audio locked. Player-moving and all head/body/angle combinations remain manual acceptance. Raw captures/traces kept local, not committed. Baseline histogram mass is explicitly a birth-mass proxy; final collision mass is accurate.
GIT COMMIT: 6ec91ea — fix(blood): rebuild weapon splatter ranges and causal flight visibility. Branch main; remote origin https://github.com/surdodeumlado/blood.git.
PUSH STATUS: SUCCESS. Normal git push origin main advanced5a41f7f→6ec91ea. This documentation follow-up records the completed implementation push.
LAST COMMAND: git push origin main (exit0, main -> main).
NEXT EXACT ACTION: player full-speed THE_BOX checklist in BLOOD_WEAPON_SIGNATURE_REPORT.md. No additional automatic tuning or native runs. Unrelated dirty tests/reports and earlier untracked evidence remain preserved.
DO NOT RESTART: no new physics/rain/audio/surface pass; no repeat native validation. Player perception remains final authority.
