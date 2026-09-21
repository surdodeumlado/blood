# GORE — the research behind the blood

`docs/BLOOD.md` describes the system as it is built. This file describes **why
it is shaped that way**: which real bloodstain-pattern principles the geometry
is derived from, and — just as important — where the game deliberately stops
being accurate.

The rule the whole pillar runs on:

> **REAL PHYSICS PRINCIPLES → STYLISED EXAGGERATION → STRONG VISUAL IDENTITY.**

Nothing here is a fluid simulation. Every principle below is used as a *reason
for a shape*, then pushed well past life for legibility at 60 Hz in a game
where the player is moving at 25 m/s.

---

## Sources

1. **Bloodstain Patterns** — Forensic Science Simplified.
   <https://www.forensicsciencesimplified.org/blood/BloodstainPatterns.pdf>
   Plain-language taxonomy: passive, spatter and altered stains; impact vs
   cast-off vs projected; the directionality of an elongated stain.

2. **Quantitative Analysis of High-Velocity Bloodstain Patterns** — NIJ.
   <https://nij.ojp.gov/library/publications/quantitative-analysis-high-velocity-bloodstain-patterns>
   Droplet size distributions in high-velocity spatter, and the relationship
   between energy and how fine the resulting mist is.

3. **Journal of Forensic Sciences, 10.1111/1556-4029.13418.**
   <https://onlinelibrary.wiley.com/doi/full/10.1111/1556-4029.13418>
   Forward vs back spatter from gunshot wounds, and the very different
   character of the two.

4. **Bullet shape and velocity determine blood spatter patterns** — AIP.
   <https://publishing.aip.org/publications/latest-content/bullet-shape-velocity-determine-blood-spatter-patterns/>
   Why the *projectile* changes the pattern rather than only the wound, and how
   atomisation scales with speed.

5. **PMC12272922.**
   <https://pmc.ncbi.nlm.nih.gov/articles/PMC12272922/>
   Droplet flight: drag against a droplet's size, and the resulting difference
   between fine mist that stops in the air and large drops that carry.

> Read as background for the *shapes*. No number in `data/blood/` is a measured
> constant from any of them; every number is a tuning value.

---

## Principles, and what each one became in the game

### A. A spatter pattern has a DIRECTION

An impact pattern radiates from the wound, and the material carries the energy
that produced it. It is not a sphere centred on a body.

**In the game:** every event is built in a frame whose Z is the attack axis
(`BloodSystem._basis_for_axis`). Nothing is constructed around world up, so a
pattern rotates *and pitches* with the attack. This is asserted by geometry
tests D (pitch survives) and E (rigid rotation).

### B. A gunshot throws material BOTH ways

Forward spatter continues out of the exit side and is the larger share. Back
spatter travels toward the shooter, is sparser, slower and coarser.

**In the game:** two explicit lobes per event, not one direction plus noise.
`back_fraction`, `back_spread_angle`, `back_speed_scale` and `back_size_scale`
in `BloodProfile` are the whole implementation; families that should not throw
anything backward set `back_fraction = 0` and the second lobe disappears with
no special case. Mist, droplets and wall splats all use the same two lobes.

> The audit found this lobe deleted at runtime: material was being clipped
> against the *entry* normal, which points back at the shooter, so 84 % forward
> became 0 % forward. A wound is not a surface. Clipping now only happens for
> blood that genuinely came off hard geometry (`BloodContext.clip_to_surface`).

### C. Energy decides how FINE the material is

Higher-energy impacts atomise blood into far more, far smaller droplets; low
energy produces fewer, larger ones.

**In the game:** `droplet_medium_fraction` / `droplet_large_fraction` per
family give each one a *distribution*, not a single size. Ballistic is mostly
fine; blunt is heavy. `impact_energy` on the weapon scales the amount through
`BloodProfile.energy_influence`.

### D. Droplet size decides how FAR it flies

Drag scales with cross-section while momentum scales with mass, so fine mist
decelerates almost immediately and big drops carry across a room.

**In the game:** `BloodSystem._step_droplets` applies drag ~ speed² divided by
droplet size (`BloodSettings.droplet_drag`). Mist is cheap, abundant and local;
droplets are few, simulated against the static world, and are what actually
stain distant geometry.

### E. The stain records the angle it arrived at

A droplet striking square leaves a circle. One arriving shallow leaves an
ellipse whose long axis runs along its direction of travel — that is what makes
a real pattern readable at all.

**In the game:** `BloodSystem._place_splat` computes incidence from
`travel · normal`, elongates the quad by `1 / incidence` clamped to
`env_streak_ratio`, and rolls the quad so its long axis follows the travel
direction projected onto the surface.

> The audit found this 90° out: the roll aligned `basis.x` with travel and then
> stretched `basis.y`. Stains pointed across the direction blood was flying.

### F. A swung weapon throws CAST-OFF along its arc

A loaded blade sheds blood tangentially as it swings, leaving a line of stains
rather than a burst.

**In the game:** `MeleeWeapon._throw_castoff` — a blood load accumulated per
hit, spent over later swings, thrown along the swing tangent with a tight
spread. It is presentation only: no damage, no gating.

### G. A swing sweeps a PLANE

Blood from a slash fans out inside the plane the blade travelled through.

**In the game:** the melee weapon puts `swing_plane_normal_ws` into the blood
context, and `BloodSystem._pattern_frame` makes that normal the frame's *thin*
axis. Every `flatten` downstream then squashes the pattern toward the swing
instead of toward a side picked off the camera. Geometry test G asserts it.

### H. An explosion acts on each BODY, not on the room

A blast is radial from its centre, but the blood comes out of whatever was
standing in it, each one thrown outward from the centre.

**In the game:** `GrenadeLauncher._detonate` resolves victims individually and
gives each one its own context, originating at *that victim* with its own
`explosion_direction_ws`. A blast that catches nobody produces **no blood at
all** — the audit was right that inventing a body's worth of blood in an empty
room was the loudest lie in the pipeline.

### I. Blunt force is broad but still directional

A hammer does not produce a neat cone, but it does not produce a sphere either.

**In the game:** `blood_blunt.tres` — wide `spread_angle`, moderate
`directional_bias`, a heavier droplet distribution, a wide slow back lobe.

### J. Satellite stains

Large drops striking a surface throw small secondary stains around the parent.

**Not implemented.** Listed here so it is not mistaken for an oversight; it
sits behind the foundation work in priority.

---

## Where the game deliberately lies

| Real | Game | Why |
| --- | --- | --- |
| Blood volume is finite | It is not | "THE ARENA SHOULD REMEMBER THE FIGHT" |
| Mist is nearly invisible | Mist is large and opaque | It has to read in 100 ms at 25 m/s |
| Stains dry and darken | Splats are placed and then free | The Compatibility renderer, and the performance philosophy |
| Patterns are subtle | Patterns are exaggerated | Identity — a family must be recognisable from across the arena |
| Droplets tumble and break up | One drag term, no breakup | Cost. The size *distribution* carries the read instead |
| Stains accumulate and pool | A fixed ring buffer recycles the oldest | Hard budgets, zero runtime allocation |

Stylised, not forensic. If a choice has to be made between accuracy and
legibility at speed, legibility wins every time — but the *shape* still comes
from a real principle rather than from a guess.
