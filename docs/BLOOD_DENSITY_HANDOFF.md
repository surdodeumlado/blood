# Blood density handoff — 2026-09-27
CURRENT PHASE: implementation, validation, diff review, commit and normal push complete. Player playtest acceptance pending. STOP AFTER THIS PASS.
BASELINE: 9a72fee. Prior approved weapon signatures preserved.
PRODUCTION: blood_quantity_multiplier1.5 in reservoir_defaults.tres. Real stock and primary blood releases+50%; finite corpse allowance scaled. Existing family/head/kill hierarchy retained. Tissue and blade load unchanged.
EMISSION: normalized reference mass for count, launch/footprint and coarse-probe demand; actual larger mass used for accounting, physical parcels and existing surface deposits. No extra particle-count setting or physical diameter increase.
VALIDATION: ten event categories/model32samples perpattern pass. Actual THE_BOX24-case headless and24-case Compatibility A/B cover all four weapons,1/2/4victims.42existing regressions pass. Initial melee side differed across A/B cohorts; fixture corrected to reset side/RNG, then targeted4-case headless and4-case Compatibility repeated Daggers/Maul only. All exits0. No crash retry or stress/endurance loops.
RESULT: matched native Daggers area proxy+24%, reps105→105; Maul+28%,273→274. Original cohort Cannon single-hit+11%, grenade+25%. Quad area is summed footprint, not overlap/alpha-corrected unique coverage. Screenshots reviewed; full-speed player acceptance pending.
PERFORMANCE: native4-victim physical mean/P95/peak ms before→after: Cannon.559/1.233/1.901→.572/1.205/1.630; Daggers1.747/3.807/4.678→1.676/3.552/4.288; Maul3.263/9.536/16.617→3.356/9.379/13.208; grenade1.462/5.683/16.027→1.588/6.224/19.129. No zero-cost claim. Other stage counter sums overlap and are not engine frame timings.
LOCKED: global physics/trajectory/fall, streak geometry/readability, crimson, puddle/fade/runoff/drip rules, wound lifecycle, audio, movement and weapon rules unchanged. Melee edit only blood retention reference.
MEMORY P0: historical0xC0000005 unresolved; none observed. Same fixed capacities/slot resets, no new production nodes/resources/per-drop fields. One scalar added to existing release snapshot. No new teardown behavior. RAM high-water unmeasured.
LIMITATIONS: single-hit distant difference modest; real-play judgment pending. Preexisting missing-foley/certificate warnings; audio untouched. Existing unrelated dirty tests/reports preserved. Raw timings/captures remain local untracked diagnostics.
GIT COMMIT: c9ef029 — feat(blood): increase represented blood quantity within existing budgets.
PUSH STATUS: SUCCESS. origin/main at https://github.com/surdodeumlado/blood.git advanced9a72fee→c9ef029 by normal push. Documentation follow-up records this completed push.
LAST COMMAND: git push origin main (exit0).
NEXT EXACT ACTION: player THE_BOX playtest: hits versus kills, all four weapons,1/2/4victims; judge heavier floor/wall aftermath and frame stability. No automatic retuning or further native runs.
