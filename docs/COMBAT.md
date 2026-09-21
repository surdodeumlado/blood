# COMBAT

Prototype 0.3. Placeholder hand cannon and one dummy target. No weapon system,
no combat framework, no reload, no ammo economy.

All numbers: `data/combat/default_combat.tres` (schema
`gameplay/combat/combat_config.gd`).

## Weapon

Semi-auto, hitscan, infinite ammo. `fire_interval` 0.62 s, zero spread —
accuracy is the thing being rewarded, so the gun goes exactly where it points.

Three body shots (34 damage each, 100 HP) or one headshot (120) kill the dummy.

## Aim, ray and crosshair are the same vector

The trace starts at `camera.global_position` and runs down `-camera.global_basis.z`.
The crosshair is drawn at the exact centre of the screen. These are by
construction the same ray, and the smoke test proves it every run:

```
crosshair centre and weapon ray are the same vector (dot 1.000000)
weapon ray starts at the eye the crosshair projects from (0.0000 m apart)
tracer ends exactly where the hitscan landed (0.0000 m apart)
```

There is no divergence to fix. Missed shots near the silhouette were a hurtbox
sizing problem, not an aiming one.

The tracer *starts* at the muzzle rather than the eye, which is cosmetic and
deliberate — it reads as coming out of the gun. Its endpoint is the real hit
point, so at any distance worth shooting at, the line still points at the hit.

## Hurtboxes

Hurtboxes are `Area3D` volumes on their own physics layer, completely separate
from the physics collider. Aim forgiveness therefore never makes the dummy
physically fatter, and the head volume can overlap the torso without shoving the
player around.

| | Visual | Hurtbox | Forgiveness |
|---|---|---|---|
| Body / legs | capsule r 0.45, h 1.9 | capsule r **0.54**, h 1.9 | **+20 %** |
| Head | box 0.5³ at y 2.15 (half-extent 0.25) | sphere r **0.34** at y 2.15 | **+36 %** |

Because the body hurtbox is the same *shape* as the visual, the +20 % is uniform
from ankles to shoulders: no thin spots, no exaggerated ankles.

**No gaps, and head priority is safe.** The head sphere spans y 1.81–2.49 and
the body capsule spans 0–1.9, so they overlap by 9 cm and there is no seam to
shoot through. The head never reaches far enough down the chest to steal torso
hits, and the body never reaches above the head, so the body collider can never
intercept a shot that was aimed at the head.

`Hurtbox` forwards `take_damage()` and `hit_zone()` to the first ancestor that
can take damage, so the weapon needs no knowledge of hurtboxes: it still just
duck-types whatever collider the ray reported.

**Debug:** press **F1** to draw every hurtbox (green body, yellow head).

## Impact feedback: local, never global

**There is no hit stop and nothing touches `Engine.time_scale`.** In a movement
game, impact must never take control away from the player: not movement, not
physics, not the camera, not the fire cooldown. The smoke test asserts
`time_scale == 1.0` after a kill.

What a hit does instead, all of it local:

| | Body | Head |
|---|---|---|
| Hitmarker | red X | gold X + expanding ring, held longer |
| Sound | `hit`, positional | `headshot`, bright crack |
| Impact puff | red | near-white, 1.45× bigger |
| FOV pulse | **+1.0°** | **+2.5°** |
| Weapon | 5 cm shove + 30 ms spin hold | 5 cm shove + 50 ms spin hold |
| Enemy | knockback + lean | 2× knockback and lean |

FOV accents are written with `max()`, never `+=`, and the composed FOV is
clamped to `fov_absolute_max` (114°), so no amount of hits can stack them.

## Gameplay cooldown vs weapon presentation

These are separate variables and one of them does not affect the other.

- **`_cooldown`** — gameplay. Decrements every frame, unconditionally. It is the
  only thing `ready_to_fire()` reads. Nothing may ever extend it.
- **`_spin_phase`** — presentation. Normally tracks the gameplay phase. On a hit
  it freezes for `impact_hold_body` / `impact_hold_head` (30 / 50 ms) so the
  impact registers on the weapon, then catches up at
  `spin_catchup_multiplier` × real time until it is back in sync.

Because the gameplay clock never stopped, the next shot becomes available
exactly on schedule whether or not the visual is still catching up. Measured in
the smoke test: the interval between a *connecting* shot and the weapon being
ready again is 0.639 s against a configured 0.62 s.

The spin is a readout of the cooldown, never its source.

## Enemy dummy

No AI on purpose. Stands still, takes damage, reacts, dies, respawns after 3 s.
Death is placeholder break-apart (7 short-lived rigid bodies on their own
collision layer, self-freeing) — **not** the gore system.
