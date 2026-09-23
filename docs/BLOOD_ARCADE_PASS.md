# Blood arcade readability pass — 2026-09-22

This is a presentation and representative-density pass over Phase 3. No new fluid model, research pass, weapon rules, movement changes or additional particle layer. Phase 3's implementation report remains the historical baseline; the sizes, palette and sampling below supersede its presentation settings.

## What changed

- Sparse mist and fewer fine representatives reduce visual noise and simulation work. Medium/large representatives retain a larger share of the sampling budget.
- Physical drops still use the existing rounded unit SphereMesh and bounded velocity-aligned ellipsoid. No liquid boxes, added blur, screen overlay or motion-trail layer.
- A shared crimson palette replaces the old dark red airborne tint. Curved shading is brighter, with a small saturated wet highlight. Tissue keeps its separate angular geometry and material palette.
- Important physical collisions produce slightly wider rendered stains, preserving the original aspect, orientation, surface normal and atlas correction. Soaked-base dimensions and their caps remain unchanged.
- Mist now respects its existing size cap on its **first submitted frame**, as it already did on subsequent updates.
- Stain masks now have an opaque body and narrow antialiased rim. This removes the old airbrushed appearance in the captures; the atlas is baked once and its occupancy is measured afterward, preserving requested stain dimensions without extra shader work.

## Physical/render separation

`render_diameter` starts from `max(physical_diameter * diameter_exaggeration, min_render_diameter)`, multiplies by the selected class's render scale and applies its visual cap. The physical diameter is not modified. Velocity deformation is bounded to 1.4; the final ordinary/glob longest axes are capped at 6.5/8.5 cm. Ligaments retain the existing 12 cm length / 1.2 cm width caps.

The new stain gain applies only when constructing the final stain quad, after physical spread and satellite placement have been calculated. Nominal area/footprint diagnostics follow that final geometry; they still do not measure visible pixels. Wet stock, absorption, runoff thresholds and flow receive the same physical inputs.

Count reductions redistribute the same represented mass among fewer samples through the existing admission logic. They change stochastic sampling and individual parcel mass, not the physical equivalent-diameter distributions, drag equations, breakup criteria, gravity or family generators. Fewer samples do not promise bit-identical per-event footprints. Coarse deposition remains active, including capacity fallback; no released blood is discarded just because mist is reduced.

## New parameters

In `BloodPhysicsSettings`, exposed by `data/blood/blood_physics.tres`:

| Parameter | Default | Effect |
|---|---:|---|
| `render_mist_scale` | 0.65 | Mist visual size; fewer mist samples are configured separately |
| `render_fine_scale` | 1.3 | Fine drop readable diameter |
| `render_small_scale` | 3.0 | Small drop readable diameter |
| `render_medium_scale` | 2.5 | Medium drop readable diameter |
| `render_large_scale` | 1.8 | Large drop readable diameter |
| `render_glob_scale` | 1.3 | Glob readable diameter |
| `render_ligament_scale` | 1.0 | Ligament width, within existing caps |
| `stain_medium_render_scale` | 1.12 | Medium collision's final stain dimensions |
| `stain_large_render_scale` | 1.18 | Large/ligament collision's final stain dimensions |
| `stain_glob_render_scale` | 1.22 | Glob collision's final stain dimensions |

These are dimension multipliers, not area multipliers. Satellite geometry does not inherit the main stain's extra gain. A fine/small drop's stain gain remains 1.0; fewer representatives already mean a larger mass share per remaining parcel.

Four new colors in `BloodSettings`, explicitly configured in `data/blood/blood_settings.tres`:

| Parameter | sRGB color | Use |
|---|---|---|
| `fresh_blood_color` | **#DC143C** | Main airborne crimson |
| `dark_fresh_blood_color` | **#A80D30** | Restrained airborne variation, fresh stain base, runoff |
| `wet_highlight_color` | **#FF526C** | Small curved highlight; also a liquid shader uniform |
| `pooled_blood_color` | **#690A24** | Dense soaked bases; darker runoff blend |

Fresh stain color blends dark fresh toward fresh by 35%, with existing saturation/absorption darkening. Runoff blends dark fresh toward pooled by 35%. Existing per-profile color fields remain serialized for compatibility, but production liquid/stain colors now use this shared palette. Tissue colors are unchanged. These are base colors, not a promise that every shaded output pixel equals the hex code.

One additional `BloodSettings` control, `stain_edge_softness = 0.10`, sets the fraction of each stain lobe's radius occupied by the soft edge. It is baked into the atlas at construction, so changes require recreating the blood system/restarting the scene. All palette/render controls should likewise be tested after restarting the scene.

## Quantity versus size

Existing density settings were adjusted; hard pool capacities and quality multipliers were not increased.

| Existing parameter | Before | After | Reduction |
|---|---:|---:|---:|
| `micro_per_mass` | 1400 | 180 | 87.1% |
| `small_per_mass` | 520 | 170 | 67.3% |
| `medium_per_mass` | 210 | 135 | 35.7% |
| `grains_per_tissue` | 460 | 200 | 56.5% |
| `large_per_tissue` | 190 | 135 | 28.9% |

Existing `max_drop_diameter` changes from 0.045 to 0.065 m, `max_glob_diameter` from 0.060 to 0.085 m, and `max_elongation` from 1.55 to 1.4. No tissue size cap increases. Cast-off sample counts remain as before; the few existing cast-off drops benefit from the same liquid size and color controls.

Family generators are unchanged: BALLISTIC retains forward/back lobes, SLASHING its directional fan and later-motion cast-off, BLUNT its momentum-aligned broad volume, HIGH_ENERGY its per-victim outward release. No new camera impulse, damage, timing, FOV or gameplay effect was added.

## Evidence and performance

The same deterministic fixture, seed, released mass, cameras and Compatibility renderer capture both versions. Each version has 23 PNGs: material shapes, three substrates and impact angles, runoff timeline and incline, cast-off, blunt reversal, aftermath at three qualities, and airborne/aftermath views for all four families.

- [Before raw results](validation/blood_arcade/before/native_results.json)
- [After raw results](validation/blood_arcade/after/native_results.json)
- [Maul before](validation/blood_arcade/before/08_blunt_air.png) / [after](validation/blood_arcade/after/08_blunt_air.png)
- [High energy before](validation/blood_arcade/before/08_high_energy_air.png) / [after](validation/blood_arcade/after/08_high_energy_air.png)
- [Persistent aftermath before](validation/blood_arcade/before/08_high_energy_aftermath.png) / [after](validation/blood_arcade/after/08_high_energy_aftermath.png)

Godot 4.7.2 Compatibility, Ryzen 5 3600, Radeon RX 9060 XT, 1280x720, VSync disabled. One HIGH_ENERGY event releases the same 0.85 blood + 0.4 tissue units. CPU simulation covers 360 fixed steps (six seconds); emission is timed separately. GPU values are viewport render medians over 60 warmed frozen-burst frames, not whole-game FPS. Final native measurements, not the fastest intermediate run:

| Quality | Initial physical drops before → after | All initial airborne elements before → after | Emit CPU ms before → after | Mean step ms before → after | P95 step ms before → after | Peak step ms before → after |
|---|---:|---:|---:|---:|---:|---:|
| LOW | 195 → 83 | 682 → 181 | 9.28 → 5.47 | 0.95 → 0.46 | 3.28 → 1.17 | 5.01 → 2.54 |
| HIGH | 532 → 224 | 1859 → 493 | 19.44 → 7.86 | 2.60 → 1.11 | 8.93 → 3.05 | 15.62 → 8.19 |
| INSANE | 887 → 374 | 3099 → 821 | 29.82 → 11.87 | 4.17 → 1.83 | 16.06 → 5.76 | 31.50 → 8.19 |

All airborne elements includes cosmetic mist, physical liquid and flying solids, not surface stains. INSANE has **73.5% fewer initial airborne elements**, **57.8% fewer physical drops**, **56.2% lower mean simulation cost** and **60.2% lower emission cost** in this fixture. GPU render medians LOW/HIGH/INSANE were 0.178/0.189/0.196 ms before and 0.153/0.220/0.150 ms after: no uniform GPU speedup is claimed. Both runs use nine scene draw calls, including five blood layers. Full-pool worst-case capacities remain unchanged, so extreme sustained saturation can still cost substantially more than this single event.

Actual submitted liquid longest-axis distributions at event creation (INSANE, equal family test mass):

| Family | Median cm before → after | P90 cm before → after | Physical drops before → after |
|---|---:|---:|---:|
| BALLISTIC | 0.62 → 1.73 | 1.11 → 3.55 | 603 → 248 |
| SLASHING | 0.62 → 1.93 | 1.62 → 4.79 | 762 → 322 |
| BLUNT | 0.59 → 2.20 | 2.36 → 5.29 | 701 → 325 |
| HIGH_ENERGY | 0.62 → 1.81 | 2.16 → 5.05 | 887 → 374 |

These statistics accompany native screenshots; they do not prove visual acceptance. The plate at 3 m/s shows fine/small/medium/large/glob longest axes of approximately 0.54/1.50/3.13/4.51/6.52 cm. At 6 s the four family fixtures retain 1184/1647/1581/1756 surface marks respectively; reduced mark counts do not erase the pooled and directional aftermath seen in the captures. Approximate area counters are not treated as pixel coverage.

Final validation:

- Material suite: **49/49 headless**, **72/72 native** (including 23 PNG writes). Four new checks compare the same actual drop under neutral and enlarged render controls: identical physical trajectory/diameter/mass, swept contact, impact response and wet mass, with larger submitted visuals.
- Existing regressions, unchanged assertions: Phase 2 **68/68**, Phase 2.1 **56/56**, Phase 2.2 **39/39**, Phase 2.3 **59/59**. Phase 2.3 and material/native suites were rerun after the final atlas edge change.
- Movement/combat: **154/154**, real-time clock. Existing authored-weapon cast-off fixture still emits 4 dagger / 7 Maul representatives on the later swing. Surface/angle, breakup conservation, full-pool fallback, runoff termination and ±X momentum checks pass.
- Stress: 56 blood events, all pool capacities respected; no added runtime nodes/layers. This stress run is headless, so its wall time is not a gameplay FPS result.
- `git diff --check` passes. SHA-256 comparison against this pass's starting workspace confirms only the eight existing files listed below changed; no gameplay/weapon/movement/profile generator file was altered.

The Windows runs log certificate-store and shader-cache write diagnostics, also present in the native baseline. The movement fixture additionally reports two ObjectDB instances at shutdown despite all 154 assertions passing; that warning is not resolved by this presentation pass. Final blood fixture logs contain no script exceptions or liquid-size warnings. Interactive first-person acceptance and sustained full-game performance remain the manual checks below.

## Files changed by this pass

Existing files, relative to the start of this pass (not relative to the repository's older dirty HEAD):

1. `data/blood/blood_settings.tres` — representative densities, palette and stain edge.
2. `data/blood/blood_physics.tres` — explicit render controls and visual bounds.
3. `presentation/gore/blood_settings.gd` — matching density defaults, four palette fields and stain edge control.
4. `presentation/gore/blood_physics_settings.gd` — class render scales, stain scales and bounds.
5. `presentation/gore/blood_fluid_model.gd` — render-only class lookup and diameter calculation.
6. `presentation/gore/blood_liquid.gdshader` — brighter crimson curvature and wet highlight.
7. `presentation/gore/blood_system.gd` — palette wiring, final stain gain, first-frame mist cap and baked stain edges.
8. `tests/blood_material_test.gd` — output-directory argument, four-family captures, render/physics isolation regression, initial-layer measurements and current cap captions.

New report: `docs/BLOOD_ARCADE_PASS.md`. New generated evidence: `docs/validation/blood_arcade/before/` and `after/` (46 PNGs, their Godot import sidecars, and raw JSON), plus `comparison.json` and `validation_summary.json`. The [exact artifact manifest](validation/blood_arcade/manifest.txt) enumerates every generated file. Phase 3's original captures are preserved. Pre-existing user changes are preserved. No commit was requested or made.

## Short Godot playtest

1. Godot 4.7.2 / Compatibility, F5 main scene or F6 `world/chambers/prototype/the_box.tscn`. Start with INSANE, unchanged camera/movement settings.
2. **3 / Maul:** hit fresh targets at 2–3 m, reverse the swing and aim up/down. Expect fewer tiny specks, visible crimson rounded drops, rare larger globs and distinct tissue. Reject giant liquid cubes, long rods or a cloud that hides the impact direction.
3. **1 / Hand Cannon:** inspect forward consequence and smaller but visible backspatter. **2 / Daggers:** inspect the cut fan, then swing through empty space after contact to see cast-off.
4. **4 / Grenade Launcher:** hit multiple victims. Check distinct outward releases, a wider dirty aftermath and less fine noise. Watch the profiler during the initial burst and repeated kills.
5. Hit near walls and aim toward the ceiling. Follow real airborne contacts into stains; observe runoff for 0.5–6.5 s and persistent floor pools from shallow angles. Compare all three quality levels, restarting between them; restore INSANE (2).

Repeat the controlled captures from the project root with:

```powershell
godot --path . res://tests/blood_material_test.tscn -- --capture --output=res://docs/validation/blood_arcade/after
```

Developer captures support presentation review; the player's moving first-person visual acceptance remains manual. This pass makes no forensic-validation claim and no guaranteed whole-game FPS claim.
