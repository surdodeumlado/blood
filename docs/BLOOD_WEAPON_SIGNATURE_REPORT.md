# Weapon signatures, range and causal flight — 2026-09-26

The Hand Cannon benefited from the earlier shared-trajectory correction, but the other emission patterns had remained unchanged since commit12d862b. This pass changes emission and presentation priority, not global falling physics.

The principal findings are:

- Daggers used a blended generic forward frame for the fan and multiplied launch speed by total released material. The corrected fan follows the actual blade tangent; tip speed calibrates launch independently of logical mass.
- Maul travelling directions were already strongly aligned with the swing. Using that same alignment to assign speed put most travelling droplets near the upper end, then total mass boosted them again. The corrected lobe has a decaying speed distribution, with the original40% local component and broad directional volume retained.
- Grenade physical SMALL droplets in the medium render layer escaped the rain-carrier launch calibration. Some left at159.12m/s. Only that uncalibrated population and the fine/small-layer launch distribution were corrected; high-arc/carrier launch rules remain.
- Distant deposits had two different causes: important physical parcels could lose streak priority, and statistical cloud probes could deposit at7m without individual physical flight. The former now use consequence-aware priority; the latter stay within the existing2m local fallback footprint. Surface morphology and physical collision deposition are unchanged.

These are game approximations informed by the recovered research, not forensic constants. Player acceptance at full speed in THE_BOX remains pending.

## Recovered model and exact changes

`docs/BLOOD_PHYSICS_RESEARCH.md`, especially sections11–13, defines ballistic core/plume/back-spatter, a planar slash fan and separate loaded-blade cast-off, a local/broad blunt event, and multi-origin per-victim explosive release. Git comparison showed no rain-era recalibration in the slash/blunt pattern files or their profiles. Density1055kg/m³, viscosity0.0048Pa·s, surface tension0.060N/m, physical diameter/mass, aerodynamic model and smooth descent assistance are untouched.

Production files:

- `presentation/gore/patterns/slashing_pattern.gd`: mean launch axis90% actual blade direction plus10% existing frame; cut origin follows blade tangent; edge speed weighting squared instead of linear. Existing fan angle, thickness and counts retained.
- `presentation/gore/patterns/blunt_pattern.gd`: travelling speed samples `lerp(.55,2.3,u²)` with bounded directional weighting, instead of assigning almost everyone upper speed from alignment. Same local fraction, direction sampling and RNG call count.
- `presentation/gore/patterns/explosive_pattern.gd`: only SMALL render-layer speed percentile is squared, retaining a rare energetic fringe.
- `presentation/gore/blood_system.gd`: melee physical launch uses `clamp(tip_speed/10,.75,1.3)` instead of a total-mass multiplier. Explosive small-layer mass multiplier bounded at1.5. Non-high-arc physical SMALL in medium layer uses initial `v/sqrt(1+|v|²/envelope²)`, envelope=existing34m/s energetic-spray setting. This preserves direction and a distribution; it is not an in-flight speed or distance clamp. Residual-wound release semantics unchanged.
- `presentation/gore/blood_flight_presentation.gd`: six fixed priority buckets; in-frustum major directional/distant transport, descending rain, other major parcels, nearby carriers, secondary detail, off-screen detail. Major threshold0.0005 logical mass; fine parcels require0.001. Important fine parcels can use existing SMALL streak geometry. No new geometry, shader, capacity, prediction or history.

BALLISTIC launch is deliberately unchanged. CAST-OFF remains separate stored blade load released with actual tip velocity once; no cut/impact impulse stacking was found. Final live samples: Daggers4 cast-off reps, speed median13.994m/s and deviation median0.50°; Maul7 reps,7.978m/s and1.34°. These are actual sampled blade motions, not family fall speeds.

## Measurement method and limits

`tests/blood_signature_live.gd` instantiates real `world/chambers/prototype/the_box.tscn` and fires through `WeaponRack.try_attack`. Each family is tested with wall distances2/7/18m; melee gets a second alternating attack/cast-off. Grenade also uses2/4 victims. Fixed seed8319, five-second observation per case. No lab-only substitute.

Range is straight-line release-origin to first physical contact, including vertical displacement, not horizontal range or integrated path length. Breakup descendants inherit the original release origin and flight history. Range distributions count descendant contacts; launch distributions count primary non-residual births, including cast-off. Ongoing wound drips are excluded. Non-contacting/expired parcels are not silently counted as zero-range impacts.

Actual attack scheduling, contacts and budget order introduce small variation between runs. These are controlled single-seed measurements, not statistically exhaustive weapon distributions. Baseline collision mass was recorded as birth mass before breakup; its histogram mass is explicitly marked a proxy. Final histogram mass uses actual collision mass. Do not compare the baseline proxy as exact deposited mass.

## Initial speeds (m/s)

Open18m-wall case, one victim. Each entry is P50 / P90 / P99 / maximum.

| Family | Before | Final |
|---|---|---|
| Hand Cannon |17.69 /38.39 /52.91 /52.91|17.69 /38.39 /52.91 /52.91|
| Daggers |16.67 /28.95 /39.00 /40.78|8.47 /16.88 /26.12 /28.43|
| Maul |28.85 /54.97 /62.22 /64.79|4.98 /14.68 /20.08 /20.40|
| Grenade |28.97 /84.26 /138.69 /159.12|16.00 /34.00 /41.52 /43.65|

These are launch speeds, not descent speeds. The global fast/smooth descent model has not changed.

## Range distributions (metres)

| Family | Before P50/P90/P99/max | Final P50/P90/P99/max |
|---|---|---|
| Hand Cannon |2.35 /5.53 /5.53 /5.53|2.15 /5.53 /5.53 /5.53|
| Daggers |3.35 /6.62 /8.77 /8.77|2.60 /4.93 /6.66 /6.66|
| Maul |5.52 /9.58 /14.83 /16.46|2.74 /4.66 /8.29 /8.46|
| Grenade |2.94 /5.62 /9.67 /9.67|2.85 /4.89 /9.67 /9.67|

Final physical-contact histogram: count (percentage; normalized logical mass).

| Family |0–2m|2–5m|5–10m|10–15m|15+m|
|---|---|---|---|---|---|
| Hand Cannon |14 (38.9%;.03207)|14 (38.9%;.04117)|8 (22.2%;.01952)|0|0|
| Daggers |0|86 (90.5%;.18738)|9 (9.5%;.02638)|0|0|
| Maul |56 (21.1%;.10104)|191 (72.1%;.37034)|18 (6.8%;.03641)|0|0|
| Grenade |20 (6.9%;.03377)|244 (84.1%;.41828)|26 (9.0%;.04584)|0|0|

Local statistical contamination is additional and not a physical flight in this histogram. No rule kills a physical representative at a range boundary. The preserved energetic arcs still produce grenade outliers near9.67m; the excessive Maul tail is substantially reduced.

Final angular P50/P90/P99 relative to actual event vector: ballistic15.5/129.9/164.5°, slash32.2/63.7/71.1°, blunt32.5/103.9/165.4°, explosive62.8/115.3/170.0°. Ballistic includes the intentional back-spatter lobe; blunt includes its local omnidirectional40%, so these whole-event percentiles are not main-cone half angles. Slash old P90/P99 was81.7/94.7°. A128-sample rotation-covariance fixture verifies opposite blade fans/origins rotate correctly while keeping speed identical.

Final airborne lifetime P50/P90/P99/max seconds: ballistic.48/2.12/2.82/2.82; slash.58/2.72/3.92/3.92; blunt.48/1.22/3.92/4.02; explosive.22/1.63/3.82/3.95. Fine detail can remain airborne longer; no global lifetime retune was made.

## Causal visibility and actual wall attribution

Major, camera-relevant physical contacts travelling>=5m with <10% streak-visible time: baseline open cases0/8 ballistic,0/27 slash,1/111 blunt,0/33 explosive; final0/8,0/9,0/12,0/26. The baseline already rendered many important physical flights: this evidence does not support claiming that all distant stains were caused by missing streaks.

The native7m-wall grenade case traces event136:

| Rep | Class | Launch m/s | Range m | Flight s | Streak time s | Visible/relevant | Matched stain width m |
|---|---|---|---|---|---|---|---|
|2075|LARGE|28.97|6.532|.367|.333|95.2%|.345|
|1924|LIGAMENT|28.97|6.501|.367|.350|100%|.344|
|2132|LARGE|28.97|6.564|.383|.333|90.9%|.347|

Each carried.001279 logical mass. Another contact shares/merges presentation and has no unique matching stain; the report does not invent one. No physical7/18m far-wall impacts occurred for Cannon/Daggers in this seed; they hit nearer surfaces instead. Near-wall tests still exercise their real physical contacts. Additional player angles and moving-player cases remain manual acceptance items.

Visibility means a selected rep was actually written to the streak batch while inside the camera frustum, sampled at approximately60Hz. It does not prove attention, contrast or occlusion-free visibility. Body visibility is not counted. Negative-ID stains may include statistical deposits, aggregation and satellites; they are not all classified as invisible physical flight. The statistical forward probe is now local2m, so that path no longer paints a7m wall directly.

## Density, arcs and locked systems

Open-case primary births remain33/104/258/222, and grenade320/346 for2/4 victims. No admission, sampling fraction, profile count, physical diameter distribution or cap was edited. The near-wall dagger second attack/cast-off produces189 rather than191 births in these runs; actual hit/load evolution differs, not configured density. Breakup naturally changes with launch energy: open physical peaks40/120/439/331 before,40/106/273/317 final. This is not a return to the rejected low-admission baseline.

High-arc and visible-rain-carrier launch rules unchanged. Comparing the candidate before the final SMALL correction against final gives22 rising MEDIUM launches with maximum vector difference.00923m/s from live contact scheduling; not bit-identical events. Shared gravity/drag/descent code is byte-unchanged.

Streak dimensions/shader, crimson, airborne readability assistance, collision contact semantics, stain renderer, wet bloom, puddle formation/accumulation/fade and wall runoff are unchanged. Statistical transport placement deliberately becomes local; physical landing locations naturally change with launch. Wound lifecycle, audio, player movement/BHOP/dash/slide/FOV and weapon gameplay are unchanged. Hash audit changed only the five production files listed above.

## Performance and resource safety

Headless comparable physical-simulation CPU, milliseconds, mean/P95/peak; detailed trace enabled in both:

| Grenade victims | Before | Final | Physical peak before/final | Queries before/final |
|---|---|---|---|---|
|1|1.353/3.883/8.925|1.298/3.866/8.000|331/317|32254/31347|
|2|1.944/6.726/12.413|1.766/6.214/11.698|459/424|38537/38526|
|4|1.938/6.673/11.391|1.993/6.402/10.913|493/450|49037/50919|

The4-victim mean increased about2.9%, while its P95 decreased about4.1%; no universal speedup is claimed.

One Compatibility process included separate uncaptured cases with detailed tracing OFF:

| Victims | CPU mean/P95/peak ms | Physical peak | Streak peak | Queries | Peak stain writes/frame |
|---|---|---|---|---|---|
|1|1.210/3.715/7.750|317|192|31682|39|
|2|1.575/5.580/13.695|423|192|36970|39|
|4|1.813/7.417/15.745|454|192|49288|48|

Native traced demand peaked261/344/377, admitted192. Trace-enabled native means1.247/1.651/1.799ms; order/scheduling noise prevents interpreting their difference as an exact tracing overhead. These are physical-stage timings, not whole-engine frame time or renderer timing. No before-native run was added just to manufacture a comparison.

No new production Nodes, Resources, MultiMeshes, streams, per-drop storage or source registry. Existing192 streak capacity and physical capacities retained. Six linear bucket scans replace five: bounded O(N), no sort/all-pairs/prediction. Debug trace remains opt-in and bounded; fixture storage cap4096 per case, overflow0. No production noisy logging. Sources high-water4; final4-victim case has1 valid ongoing wound, not an orphan. No teardown changes or buffer resizing. RAM high-water was not measured.

## Validation and remaining acceptance

- Model rotation/priority checks: clean.
- Actual THE_BOX headless baseline, candidate and final: exit0,14cases each; no repeated native stress loop.
- Existing surface/mass/budget/source regression:42checks,0failures, including1/2/4/8-victim conservation and query/write limits.
- ONE graphical Compatibility process: exit0,21cases including4 capture cases and3 trace-disabled performance cases. No0xC0000005 observed. Historical native crash remains unresolved; this run does not prove it fixed.
- Four weapon captures reviewed: dagger fan and broad Maul spray remain dense; grenade shows upward spread/streaks and local aftermath; Cannon remains directional. These still images are diagnostic evidence, not full-speed perceptual approval.
- Known preexisting warnings: Windows certificate-store access and absent real foley bank. No audio changes were made; this workspace cannot validate sound acceptance.

Player checklist: Cannon head/body hits near/open walls; left/right Daggers stationary and moving, including cast-off; Maul left/right, knockback and multiple victims; grenade1/2/4 victims near-wall/center. Follow important flight to the stain, verify local-heavy/far-rare distribution, preserved high arcs/smooth fast fall, density/streaks and approved puddles/runoff. Moving-player and every head/body/angle combination were not automated here. Stop this pass after review/commit/push; do not start another fall/audio/surface pass.

Compact before/final/native distributions, per-class speeds/diameters, histograms and wall traces are in `docs/validation/blood_weapon_signature/*_summary.json`. Raw traces and12PNG captures remain local untracked diagnostics to avoid committing large debug assets. Exact commands/exits/stdout/stderr are preserved. The fixture and summarizer reproduce the evidence.
