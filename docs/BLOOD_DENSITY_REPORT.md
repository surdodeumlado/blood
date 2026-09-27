# Controlled blood quantity pass — 2026-09-27

The player wanted more blood, while keeping the current behavior. This pass increases actual represented liquid by50% per primary release and gives the existing surface system more mass to work with. It does not increase physical diameters, launch impulse, representative demand, or coarse-probe demand.

## Quantity and accounting

Production `data/blood/reservoir_defaults.tres` now sets `blood_quantity_multiplier = 1.5`. The class default remains1.0 for compatibility. The real reservoir holds1.5 rather than1.0 normalized blood units; its finite corpse allowance scales from.35 to.525. Family/region/energy/kill withdrawal fractions are unchanged. Tissue quantity, blade-retained load, wound schedules and fixed residual reserves remain unchanged.

Pure fresh-reservoir examples at energy1, no overkill:

| Event | Before blood | After blood |
|---|---:|---:|
| Ballistic body hit |.130|.195|
| Ballistic head hit |.312|.468|
| Ballistic body kill |.780|1.170|
| Ballistic head kill |1.000|1.500|
| Slash hit |.1495|.22425|
| Slash kill |.897|1.3455|
| Blunt hit |.2405|.36075|
| Blunt kill |1.000|1.500|
| Explosive hit |.338|.507|
| Explosive kill |1.000|1.500|

These are stylized logical units, not litres or physiological estimates. Repeated hits still consume the finite reservoir. Hits stay smaller than kills, and catastrophic families retain their existing hierarchy/caps. Increasing a kill that already emptied the old reservoir required increasing real available stock, not merely requesting an impossible larger withdrawal.

Previously `blood_mass`/`total_mass()` also drove count, origin footprint and some launch speeds. Raising stock alone would have changed the approved flight. `BloodRelease` now snapshots the quantity multiplier and exposes a separate emission reference. Actual `blood_mass` and `total_mass()` retain their accounting meanings; only launch/pattern/count/probe calculations use the normalized reference. Tissue is calculated from unscaled blood. The blade retention formula uses the same reference, so cast-off load is not accidentally multiplied or duplicated.

Physical parcels still carry55% of actual released liquid; the existing local statistical path carries45%. Both receive more mass without more requested samples/rays. Physical diameter, aerodynamic mass, collision geometry, gravity and smooth fall assistance are unchanged. The existing stain radius/wet contribution rules receive larger parcels; no stain, bloom, puddle, fade, runoff or dripping parameters were retuned. No airborne head enlargement or class redistribution was necessary.

## Validation method

`tests/blood_density_model.gd` verifies the ten event cases, actual reservoir conservation, unchanged tissue/emission reference, and32 sampled launches per family/event before/after. It also checks blade-retention accounting. All checks passed.

`tests/blood_density_live.gd` loads actual THE_BOX, uses its four weapons through `WeaponRack.try_attack`, and compares multiplier1.0 against1.5 for1/2/4 victims. Cannon/melee attack successive targets every54frames; grenade attacks the cluster once. Weapon damage/timing is never changed. Each case observes360physics frames. Same initial seed and target arrangement. The model covers the full hit/kill/head matrix; live cases are the real outcomes of those attacks, not every possible headshot/angle combination.

Accepted-mass totals include unscaled later wound releases, so live totals rise by less than50% for nonlethal cases. Surface area is the sum of active recorded quad footprints at the end of the observation, NOT unique covered area: overlaps, alpha/masks and support clipping matter. Surface-peak counts and screenshots provide complementary evidence. Aftermath telemetry from the legacy per-event ledger is not mislabeled as a whole-room cumulative mass total.

## Headless before/after

| Weapon | Victims | Accepted mass ratio | Active quad area ratio | Physical peak before→after |
|---|---:|---:|---:|---:|
| Cannon |1|1.31|1.11|40→39|
| Cannon |2|1.32|1.20|49→54|
| Cannon |4|1.32|1.13|66→63|
| Daggers |1|1.38|1.07|105→105|
| Daggers |2|1.39|1.34|140→142|
| Daggers |4|1.39|1.31|180→176|
| Maul |1|1.48|1.32|274→276|
| Maul |2|1.49|1.30|337→324|
| Maul |4|1.49|1.28|390→400|
| Grenade |1|1.50|1.25|308→311|
| Grenade |2|1.47|1.37|432→431|
| Grenade |4|1.45|1.27|465→457|

Headless4-victim physical-stage mean/P95 milliseconds:

- Cannon: .593/1.268 → .658/1.416.
- Daggers: 1.657/3.399 → 1.832/3.730.
- Maul: 3.289/6.924 → 3.572/7.939.
- Grenade: 1.479/5.078 → 1.526/5.257.

Surface-peak counts with4 victims:321→441 Cannon;808→907 Daggers;1723→1913 Maul;1182→1226 grenade. Streak peak:37→34,110→110,192→192,192→192. These are bounded runtime results, not forced identical counts: breakup, secondary deposits, contact timing, source evolution and query pressure can vary. Admission formulas use the original reference quantity, so there is no configured blanket particle increase.

The existing42-check surface/source/budget regression passed, including conserved physical/pending/retained/runoff/escaped mass and write/query limits. No new production Node, Resource, mesh, material, MultiMesh, audio stream, history or per-representative field was introduced. The only additional release state is one scalar on an existing release snapshot. Capacities and recycled-slot behavior unchanged.

## Files

- `gameplay/combat/reservoir_config.gd`, `data/blood/reservoir_defaults.tres`: quantity control.
- `gameplay/combat/blood_reservoir.gd`: actual stock/withdrawal accounting; tissue normalization.
- `presentation/gore/blood_release.gd`: actual quantity versus emission reference.
- `presentation/gore/blood_system.gd`: normalized launch/count/probe inputs; actual parcel mass unchanged in semantics.
- Four existing pattern files: use emission reference for their existing footprint formulas only.
- `gameplay/weapons/melee_weapon.gd`: blood retention input only; no attack/damage changes.
- Density model/live/regression fixtures, summarizer and compact evidence under `docs/validation/blood_density`.

Global trajectories/fall speed, streak geometry/readability, crimson, surface morphology, puddle behavior/fade, runoff/dripping, wound-origin lifecycle, audio settings, movement/BHOP/dash/slide/FOV and weapon rules are locked and unedited. Surface processing naturally has somewhat more work because more real mass reaches it; zero performance cost is not claimed.

Historical0xC0000005 remains unresolved. No crash observed in any run. Both graphical processes exited0; the second was a targeted correction of the melee A/B fixture, not a crash retry or endurance loop. Preexisting missing-foley and certificate-store warnings remain; audio was not part of this pass. Player full-speed judgment remains final authority.


## Graphical result and A/B correction

The first Compatibility run completed24cases across all four weapons and1/2/4victims. Inspection exposed an A/B setup issue: alternating melee attacks started from different sides between cohorts. Those first melee captures are not pixel-matched evidence of quantity alone. The fixture now resets attack side and weapon RNG between cases. A short4-case headless comparison and4-case Compatibility comparison repeated only Daggers/Maul with one victim. No production tuning changed during this correction; all runs exited0.

Matched native comparison: Daggers accepted mass1.38x, active quad area1.24x, peak105→105; Maul mass1.51x, area1.28x, peak273→274. Images show thicker local contamination and connected patches while preserving the directional footprint. Cannon is deliberately more subtle at distance; its single-hit area increase is about11%. Grenade single-event area increases about25%. These are aftermath captures, not player approval of full-speed combat readability.

Native4-victim physical-stage mean/P95/peak milliseconds (before → after):

| Weapon | Before | After |
|---|---|---|
| Cannon |.559 /1.233 /1.901|.572 /1.205 /1.630|
| Daggers |1.747 /3.807 /4.678|1.676 /3.552 /4.288|
| Maul |3.263 /9.536 /16.617|3.356 /9.379 /13.208|
| Grenade |1.462 /5.683 /16.027|1.588 /6.224 /19.129|

This is acceptable for the next playtest without a count explosion, not a promise of zero cost or hitch-free frames. Grenade physical mean rises about8.7%; its tail still warrants player observation. The first melee multi-victim cohort includes alternating-side variation, so decreases are not claimed as optimizations. The optional stages_cpu_ms summary is a sum of inclusive instrumentation counters (some nested) and must NOT be read as total frame/engine CPU. Physical-stage measurements above are the primary CPU comparison. Query/stain-write budgets remained enforced; no RAM high-water was measured.

Compact model, regression and1/2/4-victim summaries are tracked. Raw per-frame timing arrays and PNG captures remain local diagnostics. No further automatic retuning is planned. Git commit/push status is recorded in BLOOD_DENSITY_HANDOFF.md.
