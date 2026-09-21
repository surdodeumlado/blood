# BLOOD

Prototype 0.4 — foundation only. The hand cannon is the first consumer, not the
design target.

## The one rule

> **Combat describes WHAT happened. Blood presentation decides HOW it looks.**

Combat code never spawns a particle, never picks a colour and never knows how
many of anything there are. It fills in a `BloodContext` and calls `spill()`
once. Adding a sword later means adding a `.tres`, not adding code.

There is no `if weapon == revolver` anywhere, and there must never be one.

```
weapon  ──build──▶  BloodContext  ──▶  BloodSystem  ──look up──▶  BloodProfile
                    (what happened)                                (how it looks)
```

## Files

```
presentation/gore/blood_types.gd     enums: DamageType, BodyRegion, energy constants
presentation/gore/blood_context.gd   per-hit value object (RefCounted)
presentation/gore/blood_profile.gd   Resource: how one family looks
presentation/gore/blood_settings.gd  Resource: global budgets and physics
presentation/gore/blood_system.gd    the only thing that spawns blood
data/blood/blood_settings.tres
data/blood/blood_{ballistic,slashing,piercing,blunt,high_energy}.tres
```

## BloodContext

| Field | Meaning |
|---|---|
| `damage_type` | impact family |
| `energy` | normalised intensity, 1.0 = standard |
| `position_ws` | the wound: a REAL sampled contact point at the height of the region that was hit, never a node origin |
| `attack_direction_ws` | the way the attack was TRAVELLING, attacker toward victim. ZERO when there is no meaningful direction |
| `penetration_direction_ws` | where transferred energy CONTINUES, through and out of the victim. Defaults to the attack direction |
| `surface_normal_ws` | outward normal at the contact surface. At an entry wound this points BACK at the attacker |
| `weapon_velocity_ws` | world velocity of the weapon's contact point, when it was moving |
| `swing_plane_normal_ws` | normal of the plane a melee swing travelled in |
| `explosion_direction_ws` | blast centre toward THIS victim. Per victim, never one shared direction |
| `blood_primary_axis_ws` | filled in by the system once the pattern has chosen. Telemetry and tests read it |
| `clip_to_surface` | true only for blood coming off HARD GEOMETRY, which may not be fired back into it. A wound is never clipped |
| `event_id` | telemetry correlation |
| `body_region` | TORSO / HEAD / LIMB |
| `is_headshot` | convenience, set from the region |
| `is_kill` | did this blow kill |
| `overkill` | optional: damage past zero, as a fraction of a health bar |

## Impact families

`BALLISTIC · SLASHING · PIERCING · BLUNT · HIGH_ENERGY`

**Why no EXPLOSIVE.** An explosion is `HIGH_ENERGY` with no meaningful attack
direction, which the profile already expresses through `directional_bias` near
zero and a wide spread. A separate enum entry today would be a second name for
the same parameter set. If explosives later need a genuinely different look —
misting instead of streaks, say — adding an entry and a `.tres` is the cheapest
change in this whole system.

## BloodProfile

One `.tres` per family. Grouped into burst (amount, scale, streak stretch,
speed, lifetime), distribution (`directional_bias`, `lateral_bias`,
`spread_angle`, `spread_angle_secondary`), environment splatter (chance, count,
size, distance, `env_streak_ratio`, lifetime), scaling (headshot / kill / limb
multipliers, `combined_event_falloff`, `energy_influence`,
`overkill_influence`) and colour.

The two distribution knobs do most of the differentiating work:

| Family | Shape | How |
|---|---|---|
| BALLISTIC | round cone along the shot | bias 0.88, lateral 0, 24°/20° |
| SLASHING | flat lateral fan, long streaks | lateral 0.75, 62°/10°, stretch 5.5 |
| PIERCING | tight, low volume | bias 0.95, 9°/8°, 6 particles |
| BLUNT | wide, non-linear, blots | bias 0.45, 75°/70°, stretch 1.5 |
| HIGH_ENERGY | radial, extreme | bias 0.12, 85°/85°, 26 particles |

Asymmetric spread (`spread_angle` vs `spread_angle_secondary`) is what makes a
fan a fan and a ball a ball, with no per-family code.

## Impact energy

Normalised around 1.0 — `ENERGY_WEAK` 0.5, `NORMAL` 1.0, `HEAVY` 1.5,
`EXTREME` 2.0. It is how a pistol, a hand cannon and a future shotgun all stay
BALLISTIC without looking identical. The hand cannon ships at **1.45**, plus
**+0.25** on a headshot.

The profile decides how much it cares, via `energy_influence`. Measured: the
same family and region produces 6 particles at 0.5 energy and 22 at 2.0.

## Scaling, all in one place

`BloodSystem._amount_scale()` is the only place region, kill, energy and
overkill fold together, so "a headshot bleeds more" is one rule for every
family:

```
scale  = region multiplier          (head 2.4 / torso 1.0 / limb 0.7)
       × kill bonus                  (×1.8, reduced when also a headshot)
       × energy                      (1 + (energy-1) × energy_influence)
       × overkill                    (1 + overkill × overkill_influence)
```

**Headshot kills combine rather than duplicate.** The kill bonus is scaled by
`combined_event_falloff` (0.5) when the hit is also a headshot, so a headshot
kill is bigger than either alone without being the two blindly multiplied:
measured **37 particles, where the blind product would be 47**.

## Body regions

TORSO, HEAD and LIMB. The current dummy only reports HEAD and TORSO — it has no
limb hurtboxes yet — but the weapon already maps a `&"limb"` zone through, so
adding limb hurtboxes needs no change to this contract. That mapping is also
what a future dismemberment rule will read.

## Environment splatter

Splats are pooled `MeshInstance3D` quads with a procedurally generated soft-lobe
texture (built at startup from `Image`, so the repo carries no art). Placement
casts a few rays along the spray and marks whatever they land on — which is what
puts blood on the wall *behind* a target rather than leaving it hanging in air.

- Oriented to the surface normal, with a random roll.
- Stretched along travel by `env_streak_ratio` scaled by how glancing the hit
  was: head-on leaves a blot, glancing leaves a streak.
- **Pushed `surface_offset` (12 mm) off the surface along its normal.** Without
  this the quad is coplanar with the wall and z-fights. The smoke test asserts
  floor splats sit at exactly that height (worst error 0.00000 m).
- Lands on world geometry only (`surface_mask`), never on hurtboxes or the
  player.

## Temporary vs persistent

| | Lifetime | Budget |
|---|---|---|
| **Temporary** — airborne spray | ~0.5 s, simulated in `_process` | `max_particles` 160 |
| **Persistent** — wall and floor splats | 26–34 s with a 2.5 s fade | `max_env_splats` 56 |

Both are ring buffers: the oldest is recycled when the budget is reached.
Everything is preallocated at `_ready`, so a long run cannot create a single
extra node — the smoke test fires 120 blood events and asserts the node count
never moves. `_process` switches itself off when nothing is alive.

Per-event caps (`max_particles_per_event` 40, `max_env_splats_per_event` 6) stop
one extreme hit from eating the entire pool.

## Phase 2: mass, materiality and batching

Phase 1 made the geometry correct and failed its playtest anyway: the player
said *"it looks basically the same"*. Correct vectors are not a visual identity.
Phase 2 is the answer to that.

### Represented mass replaces counts

Combat no longer says "spawn 16 droplets". The victim's **BloodReservoir** says
how much material actually left the body, as a stylised normalised unit where
1.0 is a whole body, and the rendering layer alone turns that into elements.

```
weapon ─hit─▶ BloodReservoir.withdraw(ctx) ─▶ BloodRelease ─▶ BloodSystem
              (how much material)             (a snapshot)     (how many, how)
```

`BloodRelease` carries blood mass, tissue mass, the tissue mixture, wound
severity, and the Phase 1 `BloodContext` with all its world-space vectors. Every
layer derives its output from that one object, so mist, droplets, tissue and
stains cannot invent unrelated geometry.

**A quality tier scales representation and NEVER the reservoir.** LOW, HIGH and
INSANE change how many elements a release is drawn with; the mass released, the
reservoir consumed and a wound's schedule are identical at every tier. This is
asserted, not assumed.

Because the reservoir is stateful, **the second hit on a body is genuinely
smaller than the first**, and a body that has been emptied has only its corpse
allowance left.

### Five batched layers

| Layer | What | Capacity |
|---|---|---|
| MICRO | fine mist | 3000 |
| SMALL | visible beads | 1200 |
| MEDIUM | **physical representatives** - fly, collide, stain | 520 |
| LARGE | tissue grains and gore chunks | 700 |
| SURFACE | stains: the arena's memory | 3200 |

Every layer is one `MultiMeshInstance3D`. The whole blood system is **six nodes**
where Phase 1 had 850, and a MultiMesh slot costs twelve floats rather than a
scene-tree node, which is what makes thousands of elements affordable on the
Compatibility backend with no compute and no Forward+ features.

### Allocation

`BloodMultiMeshLayer` allocates **free slot → oldest retired → eviction only
when truly full**. The Phase 1 ring advanced one index and overwrote whatever
was there, so a large event could erase blood it had just emitted while
hundreds of retired slots sat unused.

Stains go further, because the arena's memory is the point. When the surface
layer is full, the **most crowded cell** gives up its oldest stain rather than
the arena's oldest stain. A lone early mark in a quiet corner survives a whole
fight; a saturated patch recycles within itself.

### The 22-droplet convergence

Phase 1 had `max_droplets_per_event = 22` while profiles asked for 16/26/30/40.
Everything above 22 clamped, so a grenade kill and a pistol hit emitted the same
amount of material and the entire mass model was invisible.

There is now **no flat per-event cap**. Demand scales with released mass and is
admitted against what each layer has genuinely free. Measured, per kill:

```
BALLISTIC 147   SLASHING 245   EXPLOSIVE 315   BLUNT 357   physical droplets
```

### Physical representatives

MEDIUM elements are material packets: each carries a share of the event's mass,
flies under gravity and size-scaled quadratic drag, segment-tests against static
geometry and stains where it lands, with a stain size reflecting the mass it
stood for. They are simulated in `_physics_process` at a **fixed timestep**, so
how far a droplet travels no longer depends on the render frame rate.

The old direct splat-ray is still there, reduced to a **few accent rays**, so
the wall right behind a victim is marked instantly. The bulk of contamination is
now painted by real trajectories.

## Pattern geometry

Everything an event spawns — mist, physical droplets, gore chunks and the rays
that place wall splats — is built in **one frame**, and that frame is derived
from the attack, never from the world.

```
_lobe_axis(ctx, back)     which direction this lobe is thrown along
   forward -> penetration_direction_ws   (energy continuing through the victim)
   back    -> victim_to_attacker_ws()    (material thrown at the attacker)

_pattern_frame(ctx, axis) the orthonormal frame that lobe is sampled in
   no swing plane -> _basis_for_axis(axis)
   swing plane    -> y = swing_plane_normal_ws (THIN), x in the plane (WIDE)
```

Consequences, each one covered by a test in `tests/movement_smoke_test.gd`:

* **Attack pitch survives.** A shot angled steeply upward throws material
  upward. Nothing is re-flattened onto the ground plane. *(test D)*
* **The pattern rotates rigidly.** Turning the whole event by any angle gives a
  statistically identical pattern relative to the axis. *(test E)*
* **No cardinal bias.** Azimuth around the axis is uniform even when the attack
  is tilted off every world axis. *(test F)*
* **A slash fans inside its swing plane**, because the plane's normal is the
  frame's thin axis and `lateral_flatten` squashes toward the swing. *(test G)*

### Two lobes, not one direction plus noise

A wound throws material forward *and* backward. Both lobes are explicit and
both come from `BloodProfile` data:

```
back_fraction      share of material going back at the attacker
back_spread_angle  wider than the forward lobe
back_speed_scale   slower
back_size_scale    coarser
```

`back_fraction = 0` collapses an event to a single lobe with no special case,
which is what HIGH_ENERGY does — a blast is radial, it has no "back".

### A wound is not a surface

`clip_to_surface` is **false** for a wound. The entry normal points back at the
attacker, so clipping the spray against it deletes the entire forward plume —
which is exactly what a runtime audit measured: 84 % forward became 0 %
forward, and 90 % of the material ended up tangential. Only blood coming off
hard geometry sets the flag.

### Where an event is BORN

A hurtbox **node** sits at its owner's origin, which is the feet. Anything that
resolves hits by overlap rather than by a ray must call
`Hurtbox.wound_point(from_ws, direction_ws)`, which samples the collision
*shape* and pushes the point back out along the incoming direction. Head blood
at head height is a test, not a convention. *(tests I, J)*

### An explosion acts per victim

`GrenadeLauncher._detonate` builds one context per victim, at that victim, with
that victim's own `explosion_direction_ws`. **A blast that catches nobody
produces no blood at all.** *(test L)*

## Four families, four geometries

The Phase 1 emitter sampled a cone around an axis and varied count, speed and
spread per family. Four cones with different widths read as four slightly
different red explosions, because a cone is a cone. Phase 2 gives each family
its own **pattern strategy** generating a structurally different shape.

```
presentation/gore/patterns/
    blood_pattern.gd       base + factory (zero-allocation sampling)
    ballistic_pattern.gd   a TRACK
    slashing_pattern.gd    a FAN
    blunt_pattern.gd       a SHELL
    explosive_pattern.gd   a MULTI-ORIGIN RUPTURE
```

### BALLISTIC — a directional penetration event

Three structural parts, not one cone: a **core** spine (4° half-angle, 2.4x
speed) that reaches the far wall, a **plume** wrapped around it, and a sparse
wide **back lobe** toward the shooter. Origins are jittered *along* the axis, so
the source reads as a wound channel rather than a point.

*Measured: 0.93 mean axial alignment; born 0.262 along the channel vs 0.000
across it.*

### SLASHING — a fan swept through the swing plane

Essentially one-dimensional. Direction is the swing axis **rotated about the
swing-plane normal** across a 72° arc with only ~9° of out-of-plane wobble, so
it cannot come out spherical however much material passes through it. Origins
spread **along the cut line**, which is what makes the aftermath long and
lateral rather than a flat burst. Speed peaks at the leading edge of the sweep.

*Measured: 0.106 mean out-of-plane (vs blunt 0.547); origin spread 0.288 along
the cut.*

### BLUNT — a shell around the momentum axis

Two things a widened ballistic cone can never reproduce. **Speed collapses with
angle**: material near the blow axis is thrown hard, material at the rim barely
leaves the body. And a large fraction is a **near-field cloud** emitted at very
low speed from a contact disc the width of the weapon head, which is what
produces the dense local soaking that reads as something heavy hitting
something soft.

*Measured: 0.62 speed near the axis vs 0.27 at the rim; born across a 0.319
contact patch vs ballistic's 0.000.*

### EXPLOSIVE — multi-origin catastrophe

Every other family emits from one place. This one scatters **six rupture points
across the body**, each throwing material radially outward from *its own*
position, biased along that victim's blast axis. One radial burst from one point
is a red sphere; six overlapping bursts is a body coming apart. It also throws
furthest, giving it the largest environmental footprint.

*Measured: 6 distinct rupture origins; 0.67 axial vs ballistic's 0.93.*

### Stain language

Seven shapes — tiny drop, medium round, large irregular, elongated, streak,
cluster, pooled — generated into one 4x2 atlas at startup and selected
per-instance through custom data, so all seven cost **one material**. Families
weight them differently, and this is a large part of how an aftermath is
recognised: slashing is 42% streak, blunt is 28% large-irregular and 22% pooled.

## Tissue

`FLESH` deep red, `FAT` pale cream, `DARK_TISSUE` brown-red, `THICK_BLOOD` near
black. Each family requests a different mixture, which is the other half of
telling them apart: a bullet is 70% flesh and 4% fat; a maul is 40% flesh, 20%
fat and 24% dark tissue. Pale grains among the red are instantly legible and
stop gore reading as red sparks. Six irregular low-poly shapes, shared.

## Wounds

`Wound` is logical and owned by the reservoir, so quality cannot change it. It
accumulates and emits **discrete releases on a scheduler** — never per frame —
tapering over its life. It is anchored in the victim's local space, so a wounded
target that walks leaves a trail. When the victim dies or is hidden, the wound
**detaches** and finishes its life at a fixed world point, which is how a
catastrophic head kill keeps leaking after the corpse is gone.

## Phase 2.1: surface payoff

Phase 2 put a great deal of blood in the air and the playtest still said the
room looked too clean. The cause was structural, not tuning.

### Where the mass was going

`BloodSystem.mass_ledger()` reports represented mass per event, end to end, and
it is the thing to read first when an aftermath looks wrong:

```
release_blood_mass / release_tissue_mass
air_visual_mass_represented / physical_mass_represented
physical_mass_that_hit_world / _timed_out / _recycled
surface_mass_deposited, tissue_mass_deposited
stain_count, mean_stain_area, estimated_total_stain_area
surface_mass_floor / _wall / _ceiling
```

Three defects showed up immediately:

1. **The cheap cloud deposited nothing.** Thousands of micro and small elements
   carried no mass and never touched the world, so the aftermath was built
   entirely from the few hundred physical representatives.
2. **Every stain was the same size.** Mass was split evenly across
   representatives, so each carried an identical tiny share, and the old
   `_stain_size` lerp saturated at ~0.17 mass. Every landing produced the same
   small disc - the "many small isolated stains" the playtest described.
3. **Mass was being INVENTED.** Chunk impacts deposited a hardcoded `0.05` each
   and satellites a hardcoded `0.004`, neither related to what they carried. A
   maul kill deposited **16x** the mass the body released.

### The split, and both halves deposit

```
release blood mass
  ├── physical_mass_share (0.55)  -> representatives: fly, collide, stain
  └── the rest             (0.45) -> the cheap cloud
                                     -> coarse deposition probes
```

`_coarse_deposition` is the mass-conserving approximation for the unsimulated
cloud: a bounded number of probes (at most 30 raycasts for an entire
catastrophic event, sampled from the family's own pattern) each laying down a
CLUSTER carrying its share. A probe that finds nothing looks straight down
instead, because the material has to land somewhere. Nothing evaporates -
representatives that time out also do a final downward ray and deposit.

### Stain area, not stain size

```
area = mass * stain_area_per_mass        r = sqrt(area / PI)
```

Ten times the mass is about three times the width. Representatives are given
mass in **size classes** rather than an even split - a few heavy packets among
many fine ones - so an event produces a genuine distribution instead of one
repeated dot. Heavy packets land as clusters rather than discs.

### Soaked regions

Cells accumulate deposited MASS. Past `soak_mass_threshold` a cell earns a large
dark base layer, laid at `soak_base_offset` - **closer to the surface than the
detail stains**, so fine directional spatter renders on top of it and is never
erased. Bounded per cell.

### Measured, one major kill each

| Family | blood released | surface deposited | stains | area |
|---|---|---|---|---|
| BALLISTIC | 0.780 | 0.874 | 448 | 3.10 m² |
| SLASHING | 0.897 | 0.992 | 776 | 5.41 m² |
| BLUNT | 1.000 | 1.181 | 1279 | 6.47 m² |
| HIGH_ENERGY | 1.000 | 1.240 | 1191 | 7.27 m² |

Deposited equals released blood plus deposited tissue, to within a percent, for
every family. HIGH_ENERGY is the only one that meaningfully reaches walls
(0.315) and the ceiling (0.128).

## Wound lifecycle

`Wound.State` is explicit:

```
ATTACHED_LIVING -> follows the body, inherits its motion, leaves a trail
WORLD_REMNANT   -> detached, SINKS to the floor, finite clock, finite reserve
EXHAUSTED       -> retired by its owner
```

A dead target's wound becomes a remnant anchored in world space that falls to
whatever is underneath (measured: 1.80 m -> 0.05 m, coming to rest on the
floor) and bleeds out what it has left before retiring. It cannot float, cannot
emit without losing reservoir mass, and cannot outlive its reserve.

## Blunt momentum

The Phase 2 chain was broken at the source. `MeleeWeapon` wrote
`ctx.weapon_velocity_ws` and **nothing ever read it**, while BLUNT's
`penetration_direction_ws` was never set at all - so it defaulted to
`attack_direction_ws`, which is *camera forward*. Reversing a maul swing could
not change the blood, because the swing was not in the chain.

Now:

```
MeleeWeapon.tip_velocity (real rig motion, sampled per render frame)
  -> tangent + facing * momentum_forward_bias  = momentum axis
  -> ctx.penetration_direction_ws AND ctx.weapon_velocity_ws
  -> BluntPattern._axis
  -> travelling lobe, chunk and tissue velocity
  -> surface contamination
```

`BluntPattern` has two simultaneous zones: a **local impact site** (40%, slow,
all round the wound, heavy material dropping straight down) and a **momentum
trail** - a broad random direction pushed hard along the momentum axis, which
keeps a wide lateral spread while putting nearly all the mass on the swing's
side. It is not a cone; a cone would make it a wide gunshot.

Material inherits momentum by class: `THICK_BLOOD` 1.45, `FLESH` 1.15,
`DARK_TISSUE` 1.1, `FAT` 0.75, with mist scattering most and chunks least.

Mass-weighted, +X versus -X swing:

| | +X | -X |
|---|---|---|
| travelling material | +1.703 | −1.748 |
| large chunks | +0.887 | −0.877 |
| THICK_BLOOD | +0.864 | −0.882 |
| local impact zone | 383 | 403 |
| **surface centroid x** | **+7.87** | **−6.19** |

## First-event hitch

The one-time stutter was first-use initialisation: MultiMesh transform buffers
are not created or uploaded until something writes an instance, and the first
catastrophic event wrote thousands across five layers in one frame, alongside
first submission of five transparent vertex-colour materials and the stain
atlas texture.

`_prewarm()` runs at chamber load, touches a bounded number of instances in
every layer at zero scale far below the floor, and releases them again. It emits
no visible blood, produces no events, consumes no reservoir and does not touch
telemetry - all asserted. Measured afterwards: first catastrophic event
**23173 µs**, second identical event **22821 µs**.

## Death presentation

The dummy's `_die()` received a push vector, **discarded it**, and hid the body
on the same frame - so a maul blow threw blood in one direction while the target
vanished on the spot. It now carries the corpse visual along the blow for
`dummy_death_throw_time` before retiring it. Purely presentational: hurtboxes
and the collider are already disabled when it starts, and setting the time to 0
removes it entirely.

## Developer tools

Both off by default in `data/blood/blood_settings.tres`, both toggled together
at runtime with the `debug_blood` action (**F4**):

* `debug_patterns` — draws the vectors every event was built from, at the
  wound: **green** primary axis, **white** attack direction, **red** back-lobe
  axis, **blue** surface normal, **yellow** swing plane normal. A fixed pool of
  `debug_gizmo_slots` gizmos, built on first use and never again.
* `debug_telemetry` — one line per event: id, family, region, energy, kill
  flag, origin, chosen axis, and how much of each kind of material it spent.

Neither can change a single spawned particle. They only observe.

## Future gore seam

Nothing here implements dismemberment, chunks or organs. The seam that makes it
possible later is that a single call already carries

```
DamageType + energy + BodyRegion + is_kill + overkill
```

which is exactly the input a `GoreResponse` rule would need — e.g. *slashing +
limb + high energy → sever*. Adding that means reading the same context in the
same place; it does not mean revisiting weapons, hurtboxes or profiles.

## Style

See `docs/GORE.md` for the bloodstain-pattern research each of these shapes
is derived from, and for the list of places the game lies on purpose.

Stylised, not medical. Impact, clarity, controlled exaggeration, speed. No fluid
simulation, no dripping system, no realistic liquid.
