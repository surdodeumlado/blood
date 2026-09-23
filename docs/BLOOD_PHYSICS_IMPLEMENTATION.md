# Blood material implementation and plausibility review

21 September 2026. Research was documented before implementation. This is a research-informed real-time game approximation, **not forensic validation**.

The liquid box mesh and unbounded mass/velocity scaling are gone. SMALL and MEDIUM are rounded, colliding liquid representatives. Fine mist remains cosmetic with explicitly coarse deposition. Angular geometry now belongs to solid organic fragments. The existing Phase 2.3 stain atlas selection, occupancy compensation and radius-to-diameter correction remain in place.

## 1. Research sources

[BLOOD_PHYSICS_RESEARCH.md](BLOOD_PHYSICS_RESEARCH.md) records findings, linked primary sources, confidence, limitations, implementation choices and artistic departures for all thirteen requested research topics. Sources include NIST/OSAC methodology; NIJ-supported high-speed atomization, forward-spatter, inclined-impact and textile studies; whole-blood impact experiments; cast-off high-speed observations; and fluid-dynamics drag, breakup and contact-retention models. Abstract-only and preprint access are identified. The later NIJ inclined-impact report's incomplete validation was explicitly excluded as a calibrated law.

## 2. Major physical findings

Fast drop impact can use an effective high-shear viscosity, while slow surface flow needs different assumptions. Physical diameter strongly affects aerodynamic deceleration. Surface tension favours rounded liquid bodies; represented parcel mass is not a reason to render one huge drop. Impact incidence and substrate response matter. Air-driven breakup and liquid impact splash require different Weber numbers. Cast-off depends on motion and retained liquid. Similar stain patterns do not uniquely identify an event or weapon.

## 3. Scientific uncertainty

Fluid condition, temperature, hematocrit, substrate finish, wetting and initial geometry vary. Water/simulant breakup thresholds are not universal blood thresholds. The game does not invert stains into forensic conclusions. None of its authored impact thresholds, distributions, adhesion coefficients or pool sizes is experimentally calibrated to a specific weapon or material sample.

## 4. Game simplifications and units

SI units govern equivalent drop diameter, velocity, density, viscosity and surface tension. A representative stands for a parcel of many similar drops. Its represented reservoir mass determines the environmental deposit; its equivalent diameter determines flight and impact response. The shared density gives an equivalent single-drop mass of `rho * PI * d^3 / 6`.

The surface-retention calibration is **0.1 kg per reservoir unit**, a gameplay mapping, not a human blood-volume assertion. Existing parcel-to-stain area settings remain artistic. Low, High and Insane change sampling, not the reservoir withdrawal. Full physical pools explicitly route an unadmitted parcel through coarse deposition. Misses are recorded as escaped mass rather than called deposited blood.

## 5. Droplet physical model

Preallocated arrays store current/previous position, velocity, physical diameter, represented mass, liquid category, readable diameter, age/lifetime, pool layer/slot, breakup generation/exposure, drop ID, parent ID and event ID. Density and air properties are shared resource values rather than redundantly stored per drop. `BloodPhysicsSettings` is exposed through `BloodSettings.fluid`.

SMALL plus MEDIUM allow at most **1,720 active representatives** at the current resource capacities. There is no per-drop Node3D or RigidBody3D. Sleeping solid fragments retain their MultiMesh slot; settled fragments can be recycled without assigning two simulators to one live slot. Escaped solid flight is bounded at eight seconds.

## 6. Flight and drag

Defaults: blood density **1055 kg/m³**, effective viscosity **0.0048 Pa·s**, surface tension **0.060 N/m**, air density **1.204 kg/m³**, air viscosity **1.81e-5 Pa·s**. Gravity comes from the world's project setting, currently **9.8 m/s²**; player movement gravity is untouched.

`Re_air = rho_air * speed * diameter / mu_air`. Schiller–Naumann sphere drag uses `Cd = 24/Re * (1 + 0.15 Re^0.687)` below Re=1000 and 0.44 above. A non-reversing implicit-speed update applies drag. At the 60 Hz fixed clock, drag integration uses two 1/120 s substeps, followed by one swept ray across the fixed-step displacement. Gravity-only chord error is approximately 0.34 mm at 60 Hz; finite-radius collision and arbitrary curved-path exactness are not claimed.

In the isolated no-gravity test, drops starting at 20 m/s retained approximately **0.000009, 1.41 and 6.94 m/s** after one second for diameters **0.1, 1 and 4 mm**, respectively. This verifies the implementation's diameter ordering, not experimental calibration.

## 7. Breakup and ligaments

The aerodynamic criterion uses **air density**: `We_air = rho_air * speed² * d / sigma`. The threshold is `12 * (1 + 1.077 * Oh^1.6)`, with 25 ms of above-threshold exposure. This is a phenomenological use of an engineering drop-breakup model. At most two generations of binary splitting are allowed. Each child carries half the parcel mass and diameter `parent_d * (0.5)^(1/3)`. The equal/opposite small separation velocities preserve parcel momentum; they are an authored separation cue.

Breakup occurs after integration, so newborn children do not accidentally receive an extra time step because of their array index. A full pool retains the parent unchanged. A ligament lasts about 0.1 s, then splits or collapses into a rounded drop if capacity prevents splitting. Thin ligaments are generated in a 4.5% authored fraction of violent-family MEDIUM samples; there is no sheet solver.

## 8. Liquid rendering

Physical liquid uses a **unit-diameter SphereMesh**, 12 radial segments and six rings. MICRO mist uses a cheaper eight-segment sphere. The physical liquid shader supplies restrained curved-surface shading without depending on scene lighting; this is a readability shader, not an optical blood model. Ordinary velocity deformation is capped at 1.55× and the final longest axis is capped, too.

| Category | Physical example | Requested readable diameter | Submitted longest axis at 3 m/s |
|---|---:|---:|---:|
| Fine | 0.15 mm | 4.0 mm | 4.18 mm |
| Small | 0.6 mm | 4.8 mm | 5.02 mm |
| Medium | 1.5 mm | 12 mm | 12.54 mm |
| Large | 3 mm | 24 mm | 25.08 mm |
| Glob | 6 mm | 48 mm | 50.16 mm |
| Ligament | 4 mm equivalent | 12 mm thickness | 96 mm length |

These dimensions come from the transforms submitted to MultiMesh, whose mesh is one metre across. [The native close-up](validation/blood_physics/02_liquid_shapes.png) verifies rounded rendered silhouettes. No liquid uses a BoxMesh.

## 9. Size distributions

Physical sample bands overlap between families: fine **0.08–0.35 mm**, small **0.35–1 mm**, medium **1–2 mm**, large **2–4 mm**, rare globs **4–8 mm**. Fine/small sampling uses bounded log-uniform bands; larger bands are uniform mixtures. They are authored distributions, not a fitted experimental histogram. Existing per-family medium/large fractions remain the mixture controls. Only 15% of the configured large fraction becomes the rare glob band. Ballistic fine representatives receive a modest initial speed bias before diameter-dependent drag acts.

## 10. Impact model

Every physical swept collision deposits, including slow contact that the old minimum-speed gate discarded. Normal impact speed produces liquid-density Weber and Reynolds numbers. Bounded, phenomenological spread factors select DEPOSIT, SPREAD, SPLASH, GLANCING or HEAVY_GLOB. A representative deposit remains a stylized parcel footprint, not a measured stain from one isolated millimetre drop.

Spawn, breakup, collision and stain records can be enabled with `record_causality`. They identify drop, parent, event and monotonic stain IDs; reused render slots do not reuse stain IDs. The history is bounded to 4,096 records. Runoff and its terminal drops retain source IDs. Coarse/timeout deposition is explicitly distinguishable from a collision record.

## 11. Angle to morphology

Incoming velocity projected into the surface determines the long axis. A regularized aspect law avoids unbounded `1/sin(angle)`. The transverse and longitudinal factors are reciprocal square roots, so angle alone does not inflate area. Tested aspects for **90°, 60°, 45°, 30°, 15°** are **1.00, 1.14, 1.36, 1.81, 2.70**. Shallow impacts select a coherent directional tail. These are game morphology values, not an inverse angle-estimation formula.

## 12. Surface response

Three resources live in `data/blood/surfaces/`. Assign one as collider metadata `blood_response`; string metadata `blood_surface` also accepts smooth/metal, rough/stone and porous/wood/fabric. Untagged horizontal surfaces keep the rough fallback; untagged walls keep smooth. A coating can override the nominal material.

| Preset | Roughness | Spread | Absorption /s | Retention | Runoff mobility |
|---|---:|---:|---:|---:|---:|
| Smooth nonabsorbent | 0.05 | 1.05 | 0 | 0.35 | 1.00 |
| Rough nonabsorbent | 0.80 | 0.88 | 0 | 0.80 | 0.48 |
| Porous absorbent | 0.65 | 0.83 | 2.5 | 1.80 | 0.08 |

All coefficients in this table are game approximations. Porosity suppresses sustained runoff through absorption; it does not forbid the initial impact from splashing. Wet patches store wet and absorbed mass separately. Their bookkeeping is bounded to 1,024 patches; evicted bookkeeping becomes frozen retained stock rather than deleted material.

## 13. Satellites

The normal-impact Weber/Reynolds criterion and substrate splash multiplier determine eligibility and sample count. The current artistic threshold is We_normal=160 with Re_normal≥100. At most three satellites are sampled. Their total share is carved from the parent, and unsuccessful surface projections return that share to it. Normal impacts distribute around the point; glancing impacts bias satellites along incoming tangential motion. Coarse-cluster secondary marks also ray-check actual geometry and return misses to their anchor.

## 14. Wall and inclined runoff

Wet mass accumulates locally. Tangential gravity must overcome a footprint-width/surface-tension/retention proxy before a bounded portion enters runoff. Absorption competes with mobility. Surface tracing follows the projected gravity direction on walls and inclines.

Each segment spans from the **last deposited mark**, uses a connected rounded mask rather than the decorative broken-tail atlas, overlaps its neighbours and narrows as its mass is spent. The terminal mark is compact, avoiding the old elongated bead ladder. At an edge, the remaining mass becomes a real falling representative when capacity permits; otherwise it remains a terminal surface deposit. Branching is intentionally omitted. At most **24 rivulets** are active.

Same 0.08-unit wall deposits, native recorded transform extents:

| Time | Smooth rendered run length | Rough rendered run length | Porous |
|---|---:|---:|---|
| 0 s | 0 m | 0 m | No runoff |
| 0.5 s | 0.35 m | 0.19 m | Absorbing |
| 1 s | 0.61 m | 0.36 m | Absorbing |
| 2 s | 0.97 m | 0.61 m | Absorbing |
| 6.5 s | 2.22 m | 1.30 m | Absorbed; no run |

See [T=0](validation/blood_physics/03_runoff_000.png), [T=2](validation/blood_physics/03_runoff_020.png), [finished](validation/blood_physics/03_runoff_065.png) and [inclined surface](validation/blood_physics/04_inclined_runoff.png). Reported run length is geometry extent, including overlap; source stain occlusion means the entire length is not necessarily separately visible.

## 15. Cast-off

Actual tip displacement and axis rotation provide velocity and angular speed. A centripetal-acceleration-inspired threshold depends on load. Launch follows measured tip velocity with small transverse variation. Different reach and swing motion naturally change release without weapon-name conditions.

Blade load is carved from the body's withdrawal: at most 8% of a contact release, bounded by remaining load capacity. Full normalized load is 0.025 reservoir units. A swing snapshots its previously held load; the current hit's new load cannot immediately masquerade as later-motion cast-off. Emission only spends the admitted amount, and quality changes sample count while keeping the spent mass. Damage, attack clocks, sweep reach and recoil/FOV code were not retuned.

For equal 0.6 starting loads at a 0.6 m effective radius, 1/8/20 rad/s spent **0 / 0.222 / 0.5 normalized load**. This checks threshold behaviour, not experimentally measured detachment speeds.

The integration fixture also drives the **actual authored Daggers and Maul rigs** through two swings. First contact loads them without immediate cast-off; the later swing emitted **4 / 7 physical representatives**, respectively. Angular speed comes from complete orientation quaternions: comparing only the forward vector would miss these rigs' roll about that axis. The fixture uses the production pose and cast-off code without changing damage or timing parameters.

## 16–19. Pattern families

**16. Ballistic:** existing forward/back geometry is preserved. Fine forward samples receive a modest speed bias; small drops subsequently decelerate faster. No firearm identification or muzzle-gas simulation is claimed.

**17. Slashing:** existing contact fan follows the actual swing plane. Wound release, retained implement load and later-motion cast-off are separate material paths. There is no cutting biomechanics or blade-film solver.

**18. Blunt:** existing contact-momentum axis and broad local/travelling distribution remain. Liquid gains rare transient ligaments, while tissue remains solid. Both the sample direction tests and [positive](validation/blood_physics/06_blunt_positive.png)/[negative](validation/blood_physics/06_blunt_negative.png) first-person reference captures preserve swing reversal.

**19. Explosive:** existing per-victim outward direction and multiple local origins remain. The high tissue component stays distinct from the fine liquid cloud. Sampling origins are checked against world geometry so a contact-volume offset cannot put physical material beneath the floor. No blast injury or blast-air coupling is calculated.

## 20. Liquid versus tissue

[The solid reference plate](validation/blood_physics/02b_solid_tissue.png) shows flesh, muted beige fat, dark tissue, stringy tissue and a major fragment. Solids use an asymmetric, flat-shaded octahedral mesh with no rectangular faces. Stringy tissue has narrow solid axes and does not collapse like a liquid ligament. The legacy THICK_BLOOD mixture index maps to stringy/clotted organic material, preserving serialized mixtures without drawing liquid boxes.

Hard authored size bounds: ordinary liquid longest axis **4.5 cm**, glob **6 cm**, ligament **12 cm length / 1.2 cm thickness**; solid grains **3.8 cm**, fat **3.5 cm**, normal fragments **11 cm**, rare major chunks **18 cm**. Actual solid sizes are usually below their caps. Liquid violations produce developer warnings; fixtures observed none.

## 21. Validation and visual review

`tests/blood_material_test.tscn` produces the controlled surface/angle/size/speed matrix, liquid and tissue plates, runoff timeline, inclined runoff, cast-off and blunt reversal captures. It also tests the actual authored weapon rigs. Headless: **45 checks passed**. Native Compatibility: **60 checks passed**, including 15 PNG writes. [Headless results](validation/blood_physics/results.json) and [native results](validation/blood_physics/native_results.json) contain dimensions, stock, conditions and timings.

Regression suites: Phase 2 **68/68**, Phase 2.1 **56/56**, Phase 2.2 **39/39**, Phase 2.3 **59/59**. The complete movement/combat suite passed **154/154** using the real-time clock. An accelerated `--fixed-fps` run is unsuitable for its wall-clock cooldown assertion; that test was rerun normally. The stress fixture respected pool capacities.

The Phase 2.3 readability checks now test the larger-mark percentile instead of requiring the median of all fine impact details to read from 12 m. This deliberate test-contract update accompanies native frame review, not an increase in stain counts or a claim that percentiles prove visual quality.

Native review found and corrected two issues that numeric checks alone missed: excessive solid-fragment prominence and broken runoff texture tails. Final captures show rounded liquid, smaller angular tissue, directional deposition, continuous tapered runoff and persistent pooled contamination. The [Insane aftermath](validation/blood_physics/07_aftermath_quality_2.png) is the rendered reference, not an area-counter argument. These are deterministic developer scenes, not a claim that a human has approved a fresh interactive Maul playtest.

## 22. Performance measurements

Godot **4.7.2 Compatibility**, Windows, Ryzen 5 3600, Radeon RX 9060 XT, 1280×720. One fixed catastrophic event: 0.85 blood + 0.4 tissue units. CPU simulation timings cover 360 fixed steps (six seconds) with production causality/write recording disabled. Renderer measurements use 60 warmed native frames of the frozen initial burst; they are viewport render costs, **not total game FPS**. See [Godot's timing API](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-viewport-set-measure-render-time).

| Quality | Initial physical reps | Emit CPU | Mean simulation step | P95 step | Peak step | GPU render median |
|---|---:|---:|---:|---:|---:|---:|
| Low | 195 | 12.32 ms | 1.02 ms | 3.46 ms | 5.39 ms | 0.16 ms |
| High | 532 | 20.27 ms | 2.63 ms | 9.67 ms | 18.82 ms | 0.18 ms |
| Insane | 887 | 32.15 ms | 4.40 ms | 15.99 ms | 32.13 ms | 0.19 ms |

The fixture rendered nine scene draw calls, including five blood layers. Renderer medians are noisy and need not increase monotonically. Emission and dense collision/deposition frames remain the expensive stages; **High and Insane have measured spikes above a 16.7 ms frame budget**. No locked-60-FPS claim is made. The fixed-step ray-query consolidation reduced the comparable Insane mean from about 5.3 ms to 3.8–4.4 ms across subsequent measurements while retaining two drag substeps. The table uses the final capture run, not the fastest run. Many simultaneous events and other hardware require separate profiling.

## 23. Intentional exaggerations and plausibility classification

| Effect | Classification | Deliberate departure |
|---|---|---|
| Gravity, diameter/drag ordering, volume bookkeeping | Physically grounded model | Point representatives and isolated sphere assumptions |
| Aerodynamic breakup | Phenomenological approximation | Engineering threshold, binary representatives, fixed exposure |
| Impact spread, splash and substrate coefficients | Phenomenological approximation | Bounded authored coefficients, no crown solver |
| Stain angle response | Phenomenological approximation | Regularized aspect at shallow incidence |
| Retention, absorption, runoff and cast-off onset | Phenomenological approximation | Authored rates/thresholds; no contact-line solver |
| Liquid visual diameter | Artistic exaggeration | Nominal 8×, 4 mm minimum, hard caps; the smallest beads can exceed 8× |
| Velocity stretch, gloss cue, ligament frequency | Artistic exaggeration | Readability and family emphasis |
| Parcel stain area and pooled reinforcement | Artistic exaggeration | A parcel represents many drops; no literal single-drop footprint claim |
| Widened runoff and accelerated flow | Artistic exaggeration | Visible within seconds and from first person |
| Tissue mixture/size and event energy coupling | Artistic exaggeration | No biomechanical tissue-liberation model |

## 24. Remaining limitations

No CFD, sheet surface, coalescence, collective spray drag, non-Newtonian constitutive solver, dynamic contact angle, pore network, realistic coagulation/drying, free-surface pool depth, or obstacle-aware pool expansion. Surface parameters are authored presets. Fine drops remain visually tiny at long FPS distances by design. A very close camera can still make a bounded object appear large through perspective; render size caps are not a screen-occlusion guarantee.

MICRO mass uses coarse deposition. Physical lifetime expiry also uses explicitly logged coarse fallback, rather than claiming an unobserved flight collision. Blood leaving reachable geometry is an escaped-mass diagnostic. Surface eviction preserves a bounded visual history, not every stain forever. The old coverage grid is a coarse footprint union; it is not an alpha-, occlusion- and eviction-correct measurement of currently visible screen coverage. Its output must never replace screenshot judgment. The legacy last-event mass ledger can mix asynchronous activity from multiple events; use bounded causal IDs for individual event investigations.

## 25. Exact manual Godot checklist

1. Open the project in Godot 4.7.2 with **Compatibility**. Run `world/chambers/prototype/the_box.tscn` (F6), or the configured main scene (F5). Leave movement and camera settings unchanged.
2. Select **3: Maul**. Stand roughly 2–3 m from a fresh target; hit at body/head height. Judge the actual moving view: fine mist and small rounded liquid, sparse globs, brief thin ligaments, smaller flesh/fat/dark fragments and a few major pieces. Reject ordinary box-shaped liquid or screen-filling liquid rods.
3. Repeat with the opposite swing direction and while aiming up/down. Blood should follow the contact momentum and 3D attack frame. Check that the weapon's existing damage, timing and movement feel match the prior build.
4. Select **2: Twin Daggers**. Swing once at a clean target, then swing through empty space. The first contact should load the blade; a later sufficiently fast movement should shed tangent-directed blood. A clean empty swing should not manufacture load. Compare with the Maul's motion.
5. Select **1: Hand Cannon**. Check distinct forward/back spatter and fine droplets decelerating close to the event while larger ones travel farther. Do not infer weapon identity from stain size.
6. Select **4: Grenade Launcher**. Use multiple fresh victims. Check separate per-victim outward releases, mixed solid tissue and liquid, and bounded material sizes. Confirm existing grenade rules and timing.
7. Hit a victim near a wall. Watch at 0, 0.5, 1, 2 and 6.5 s: a sufficiently wet deposit should produce a continuous narrowing run and a compact terminal deposit. Move to shallow camera angles to check surface offsets. Fine stains should remain over pooled bases.
8. Run `tests/blood_material_test.tscn` with native rendering and `-- --capture`. Inspect `docs/validation/blood_physics/*.png`: three substrates; angles 90/60/45/30/15; size and speed rows; runoff timeline; incline; cast-off; ±X blunt references. The matrix tests equivalent-drop inputs at a fixed represented parcel mass, not a calibrated laboratory single-drop volume series.
9. For interactive substrate experiments, set the collider's `blood_response` metadata to one of `data/blood/surfaces/{smooth,rough,porous}.tres`. Repeat the same heavy deposit. Rough should run more slowly; porous should absorb with little sustained runoff.
10. Compare LOW/HIGH/INSANE by changing only `quality` in `data/blood/blood_settings.tres`, restarting between trials, then restore the current **INSANE (2)** setting. Logical reservoir release must stay equal. Profile the first hit, sustained multi-kills and several seconds of aftermath; watch for the documented Insane CPU spikes.
11. Check the Godot debugger for liquid-size warnings or script errors. Enable `record_causality` only when investigating a drop; locate its `spawn → collision → stain` IDs. Treat `timeout_coarse` as an approximation, not a real collision.

The implementation and developer fixtures are complete. Interactive visual acceptance remains a player judgment; no forensic validation is claimed.
