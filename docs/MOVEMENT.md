# MOVEMENT

Prototype 0.3 — COMBAT/MOVEMENT FEEL TUNING.

> **THE AIR MODEL WAS DELIBERATELY UNFROZEN AND REPLACED.**
>
> The previous air model was approved and frozen, then failed in play: tight
> curves felt awkward and the player reported losing speed while trying to
> curve. It has been replaced with mathematics derived from Source SDK 2013's
> `CGameMovement`. **Ground movement, slide and dash were NOT part of that
> change and remain as approved.**
>
> The air model is now pending a manual playtest and is not approved. Numbers
> are pinned by `tests/movement_source_lab.tscn`.

## Philosophy

The player is already fast. **There is no sprint.** Shift is **dash**. Nothing
about the movement set rewards holding a key down for a baseline the game should
have given you for free.

Movement favours: speed, future aggression, mechanical mastery, momentum
conservation, fast direction changes, responsive air movement.

**Game feel beats realism.** Where physical plausibility and control fight each
other, control wins.

### Bunnyhop philosophy

> **WALKING IS ENOUGH TO WIN. MOVEMENT MASTERY IS ENOUGH TO DOMINATE.**

Bunnyhop is never required. A player who only walks, jumps, dashes and slides
moves at ~9 m/s and has full control of the game. A player who learns to
air-strafe moves at 20–24 m/s, and the difference is entirely theirs.

The skill lives in: jump/landing timing, synchronising A/D with mouse movement,
the trajectory you choose, whether you keep momentum through the landing, map
knowledge, and combining the systems. It is not a one-frame window and it is not
automated either.

**There is no auto-bhop.** Jump reads `is_action_just_pressed`, so holding Space
produces exactly one jump, ever. You have to press it again, and you have to
press it at the right moment.

## Where the numbers live

All of them: `data/movement/default_movement.tres`
Schema and documentation: `gameplay/movement/movement_config.gd`
Combat / feedback numbers: `data/combat/default_combat.tres`

Nothing hardcodes a tuning value. Edit the `.tres` and press Play. To add a knob,
add an `@export` to `MovementConfig` and use it.

## The air model — Source `AirMove` / `AirAccelerate`

**One term. No steering term, no gain term, no rule about the mouse.**

Reference: Source SDK 2013 `gamemovement.cpp`, `CGameMovement::AirMove()` and
`AirAccelerate()`. The relationships are Valve's; every number is ours. This is
**not** a claim of parity with Source 2, whose movement code is not public in
the same way.

`AirMove` builds a wish velocity from the flattened view basis and the movement
keys, and clamps its length to `move_speed`. `AirAccelerate` then does all of it:

```
wishspd     = min(wish_speed, air_wish_speed_cap)   # 1.1 m/s
current     = dot(velocity, wish_dir)               # a PROJECTION, not a speed
add_speed   = wishspd - current
if add_speed <= 0: nothing happens
accel_speed = min(air_accelerate * wish_speed * dt, add_speed)
velocity   += wish_dir * accel_speed
```

**The asymmetry on the last line is load-bearing.** The acceleration term uses
the *uncapped* `wish_speed`; the budget it is clamped against uses the *capped*
one. Replacing one with the other is the classic mis-port and it turns air
strafing into a mushy drift.

Why this both turns and gains: `current` is a projection. Moving fast forwards
while wishing sideways makes it near zero, so the full `add_speed` is available
— and a vector added at ninety degrees to a velocity both bends it *and*
lengthens it. Nothing multiplies anything.

| What you do | What happens |
|---|---|
| Hold W at any speed | projection is already past the cap, `add_speed < 0`, **nothing added, nothing taken** |
| Hold A/D, view fixed | one capped tick of orthogonal acceleration, then the projection catches up. **+0.04 m/s and a 4° nudge.** Small, allowed, not a technique |
| Hold A/D **and turn the view with it** | the wish direction keeps outrunning the projection, so acceleration is added every tick: **a tight arc that gains speed** |
| Hold S | the projection is negative, so `add_speed` is large and the cap stops binding — speed scrubs off fast. Correct Source behaviour |

There is **no camera-turn bonus**, no lateral-input rejection, no
velocity carving and no turn damping. The mouse reaches movement only by moving
the camera, which moves the wish direction.

### What this fixed

The previous model capped air steering at a flat **120 °/s** rotation of the
velocity vector. Measured in the lab, it turned **exactly 86° per jump at 12,
16, 20 and 24 m/s** — identical at every speed, and identical whether the camera
swept or stood still, because the camera only gated the *gain* term and had no
steering authority at all. That is what "tight curves feel horrible" was.

| Speed | Heading per jump, old | new | Speed change, old | new |
|---|---|---|---|---|
| 12 m/s | 86° | **208°** | +1.01 | **+2.00** |
| 16 m/s | 86° | **162°** | +0.79 | **+1.55** |
| 20 m/s | 86° | **131°** | +0.44 | **+1.20** |
| 24 m/s | 86° | **113°** | +0.09 | **+0.13** |

Turning is now **1.3–2.4× tighter**, it **tightens further as you slow down**
(which is what makes a curve feel like a curve), and a tight turn *gains* speed
instead of costing it.

## Bunnyhop: what jumping actually does

The reward for a clean hop is **friction you never pay**.

`MovementController.step()` knows, before running ground physics, whether a jump
will fire this tick. If it will, ground friction is skipped entirely. So:

- **Land and jump on the same tick** → you keep 100% of your speed.
- **Land and jump three ticks late** → you paid `momentum_friction` (14 m/s²)
  for three ticks, about 0.7 m/s.
- **Land and just run** → you bleed back toward 9 m/s in roughly a second.

No magic window, no bonus, no combo counter that does anything. Just timing.

### Jump buffer and coyote time

| Knob | Value | Purpose |
|---|---|---|
| `jump_buffer_time` | **0.10 s** | a jump pressed up to 100 ms before landing still fires on the landing tick |
| `coyote_time` | **0.10 s** | jump still works for 100 ms after walking off an edge |
| `bhop_grace_time` | 0.12 s | **display only** — classifies a hop as "clean" for the HUD chain counter. Grants nothing. |

0.10 s is 6 physics ticks at 60 Hz. It exists so that input timing is fair across
framerates and so that landing does not eat a press, not to automate the
technique: you still have to press per hop, and pressing early enough to be
buffered is itself the timing.

**Tune `jump_buffer_time` first if bhop feels too hard or too free.**

## Ground traction

The 0.2 ground movement felt like walking on soap. The cause was that friction
only ran when there was **no** input: hold W at 9 m/s, press A, and the forward
component had nothing scrubbing it, so the velocity swung round in a long lazy
arc instead of turning.

0.3 moves to the Quake order — **friction first, then acceleration, every
grounded tick, input or not** — split into two regimes:

| Speed | Friction | Why |
|---|---|---|
| at or below `move_speed` | `ground_deceleration` = **95 m/s²** | normal walking, planted and crisp |
| above `move_speed` | `momentum_friction` = **14 m/s²** | movement tech, momentum survives |
| a jump fires this tick | **none at all** | the bhop landing pays nothing |

Holding a direction, friction scrubs the whole velocity and acceleration
immediately rebuilds it along the wish direction, so whatever pointed the old
way dies fast. Measured: a full stop takes **100 ms** and a 180° reversal takes
**50 ms** (they were roughly 3× and 6× that before).

`ground_acceleration` had to rise to **150 m/s²** to stay ahead of the new
friction — with friction running every tick, acceleration that cannot out-pace
it means the player never reaches `move_speed` at all. The two numbers are
coupled; if you raise the deceleration, raise the acceleration too.

**None of this touches the tech.** The high-speed path is `momentum_friction`,
unchanged from 0.2; slide runs its own `slide_friction` and never goes through
this code at all; and `_ground_physics()` receives a `hopping` flag computed
*before* it runs, so a buffered jump on the landing tick skips friction
entirely. The HUD prints which regime ran (`TRACTION` / `MOMENTUM` /
`HOP (no friction)`) so this is visible while tuning.

## Soft cap

**It bends new gain. It never touches momentum you already have.**

`soft_cap_gain_scale()` scales the *speed increase* an acceleration would have
produced, then re-lengths the accelerated vector to that:

```
speed <= bhop_soft_cap_start (20)  -> x1.00   full gain
speed >= bhop_soft_cap_end   (25)  -> x0.03   asymptote, deliberately not zero
between                            -> smoothstep, so there is no edge to feel
```

Three properties fall out of scaling the *surplus length* rather than the
vector, and all three are requirements rather than side effects:

- **Steering is untouched.** The heading of the accelerated vector is preserved
  exactly, so a tight turn at 25 m/s is as tight as one at 16 m/s. It just
  stops paying.
- **Deceleration is untouched.** Wishing backwards produces no surplus, so
  there is nothing to scale.
- **Existing velocity is never reduced**, because the result is never shorter
  than what you came in with.

There is **no `overspeed_drag` any more.** It used to bleed anything above the
ceiling back down at 6 m/s², and the lab measured it taking **30 → 25.7 m/s over
a single jump with no input at all**. That is "steering mysteriously deleted my
speed" wearing a different hat. Speed you have earned is now taken only by
collision, by ground friction, by braking, or by explicitly wishing backwards.

`safety_speed_limit` (40 m/s) is a **safety net against physics blowups, not a
gameplay cap**. It sits far above the soft cap and reaching it means a bug.

### Speed bands (targets, measured at 60 Hz)

| Band | Speed |
|---|---|
| Normal movement | 9 m/s |
| Competent bhop | 12–16 m/s |
| Good bhop | 16–20 m/s |
| Excellent bhop | 20–24 m/s |
| Soft cap region | 20 → 25 m/s |

Measured: a machine-perfect strafe chain runs **9.00 → 25.28 m/s over 41 hops in
30 s**. It takes about 2.5 s of air time to reach 16 and roughly 8 s to approach
the cap, so speed is built progressively rather than jumped into.

## Current values

| Knob | Value | Note |
|---|---|---|
| move_speed | 9.0 | base ground speed |
| ground_acceleration | 150.0 | must stay above ground_deceleration |
| ground_deceleration | 95.0 | traction, at or below move_speed, every tick |
| momentum_friction | 14.0 | above move_speed; the bhop timing pressure |
| crouch_speed_multiplier | 0.45 | |
| air_accelerate | 12.0 | Source `sv_airaccelerate`. Units of 1/s, so it needed no scale conversion |
| air_wish_speed_cap | 1.1 | Source `GetAirSpeedCap`, 30/250 of a run, scaled to our 9 m/s. Drives turn rate **and** gain |
| bhop_soft_cap_start | 20.0 | full gain below here |
| bhop_soft_cap_end | 25.0 | near-zero gain above here |
| bhop_soft_cap_min_gain | 0.03 | asymptote, not a wall |
| safety_speed_limit | 40.0 | safety net, not a cap |
| jump_velocity / gravity | 8.5 / 24.0 | ~0.71 s airtime |
| coyote_time / jump_buffer_time | 0.10 / 0.10 | |
| dash_speed / duration | 20.0 / 0.14 s | |
| dash_max_charges / dash_charge_time | 2 / 1.35 s | sequential refill |
| dash_cooldown | 0.15 s | minimum gap between dashes |
| dash_kill_recharge_bonus | 0.7 s | normal kill; headshot kill grants a full charge |
| dash_exit_speed_multiplier | 0.85 | dashing while fast is a net loss |
| air_dash_limit | 2 | refilled on landing; the charge pool is the real limit |
| slide_min_speed / slide_end_speed | 7.0 / 4.0 | |
| slide_entry_speed_multiplier | 1.25 | entry = max(current, 11.25) |
| slide_friction | 3.0 | vs 45 standing |
| slide_steer_acceleration | 9.0 | direction only |
| slide_slope_acceleration | 18.0 | downhill gain |
| stand / crouch height | 1.8 / 0.9 | capsule radius 0.4 |
| fov_base → fov_max | 90 → 104 | speed component, mapped over 9 → 25 m/s |
| fov_dash_accent | +5.0 | decaying accent while dashing |
| fov_pulse_body / head | +1.0 / +2.5 | hit accent (CombatConfig) |
| fov_absolute_max | 114.0 | hard ceiling on the composed FOV |
| mouse_sensitivity | 0.0022 | radians per pixel |

## Dash as a resource

Dash is a **two-charge pool**, not a cooldown. One dash costs one charge; at
zero charges there is no dash.

| Knob | Value |
|---|---|
| `dash_max_charges` | 2 |
| `dash_charge_time` | 1.35 s per charge |
| `dash_cooldown` | 0.15 s minimum gap between two dashes |
| `dash_kill_recharge_bonus` | 0.7 s |

Refill is **strictly sequential**: one accumulator fills, completes a charge,
resets and starts on the next. Two charges can never fill in parallel. It is
delta-driven, so the refill rate does not care about the tick rate.

### Combat pays for mobility

| Event | Reward |
|---|---|
| normal **kill** | the in-progress charge jumps 0.7 s closer to done |
| **headshot kill** | a whole charge back, immediately |

Both are clamped at `dash_max_charges`, and the normal-kill bonus is capped at
one charge time so it can finish the current charge but never spill into the
next.

Both are gated on the **kill**, never on the hit. A future enemy tough enough to
survive headshots must not become an infinite dash farm.

## Dash / slide / bhop interaction

The goal is that dash and slide **complement** bunnyhop rather than replace it.
Nothing below is scripted as a combo; it all falls out of the rules.

**Dash is a correction tool, not a speed source.** It sets speed to
`max(dash_speed, current_speed)` — never additive — and multiplies by 0.85 on
exit. So mashing it on cooldown while already at 22 m/s makes you *slower*, and
the headless test confirms dash spam peaks at exactly `dash_speed`. It also zeros
vertical velocity for its duration, so a mistimed air dash kills the hop you were
in the middle of. Used well it is a dodge, a mid-air trajectory correction, or a
way to convert a bad landing into a slide.

**Slide is a momentum bank.** Friction is 3 m/s² instead of 14, entry is a
`max()` and steering only rotates, so a slide preserves a fast landing for over a
second without ever generating speed. Slide-jump carries 100% of horizontal
velocity.

Emergent combinations that work because of the above, not because anything
codes for them:

- **bhop → slide → jump** — bank a fast landing, ride it, launch back into hops.
- **dash → jump → air-strafe** — dash hands you 20 m/s to start arcing from, at
  the cost of the dash cooldown. Air acceleration steers that momentum like any
  other; it never resets it.
- **high-speed landing → slide** — the cheapest way to not lose a bad hop.
- **ramp slide → jump** — slope acceleration can put you over the soft cap, and
  nothing takes it back any more. You keep it until geometry or the ground says
  otherwise, so the ramp is genuinely worth knowing.

If something emergent turns out to be fun, has skill expression and does not
break combat, it stays.

## Momentum decisions

**Jump never resets horizontal velocity.** Neither does landing. Speed is only
removed by ground friction, by the slide ending, by wishing backwards in the
air, or by hitting geometry. **Air steering never removes it.**

**Nothing additive.** Every speed-granting move uses `max()` or a bounded gain:
dash `max()`, slide entry `max()`, slide steering rotates without lengthening,
and air acceleration is bounded per tick by `air_wish_speed_cap` and then by the
soft cap. Gain per tick shrinks as speed rises with no extra rule for it,
because adding a fixed length across a longer vector lengthens it less.

## Crouch / slide safety

The capsule is resized from `MovementConfig`, and the controller **never grows
the capsule into geometry**. Before standing, a `PhysicsShapeQueryParameters3D`
shape query tests a standing capsule at the player position; if anything is hit,
the player stays crouched. The check capsule is 2 cm thinner than the real one so
hugging a wall does not falsely block standing. The same guard runs in
`_update_height()`, so a slide-jump under a low ceiling cannot pop you into it.

## Frame-rate independence

All movement runs in `_physics_process`, which Godot ticks at a fixed rate
(`physics/common/physics_ticks_per_second = 60`, set explicitly). **Render FPS
cannot affect movement at all**, and the lab asserts that structurally rather
than statistically: the controller reads no render-rate quantity, and `step()`
is called from `_physics_process` only.

The **physics tick rate** is a different matter, and it is worth being honest
about. Over the same wall-clock second, 120 Hz gains **3.1% more speed** but
**61% more turn authority** than 60 Hz. This is not a delta-time bug — it is
inherited from Source, where `add_speed` is a *per-tick* budget, and it is the
same reason 64-tick and 128-tick Counter-Strike feel different to strafe on. At
60 Hz the accel term offers 1.8 m/s per tick and the 1.1 m/s cap binds; at
120 Hz it offers 0.9 and the accel term binds instead.

**Consequence: `physics_ticks_per_second` is now an air-feel setting.** Changing
it retunes movement. The lab prints the figure every run.

The camera — look, recoil recovery and FOV easing — runs in `_process` at render
rate, using `1 - exp(-k * dt)` easing so it is also rate independent.

## Architecture

```
gameplay/player/player.gd                   reads input actions, wires feedback
gameplay/movement/movement_controller.gd    all movement, _physics_process
gameplay/movement/movement_config.gd        the tuning schema (Resource)
presentation/camera/first_person_camera.gd  pitch, recoil, dynamic FOV
presentation/ui/debug_hud.gd                tuning readout
presentation/ui/crosshair.gd                crosshair + hitmarker
```

`player.gd` fills `MovementController.input_dir / wants_jump / wants_dash /
wants_crouch` once per physics tick and calls `step(delta)`. The controller emits
`jumped / landed / dashed / slide_started / slide_ended`, which the player turns
into audio. Yaw is applied to the `CharacterBody3D`; pitch to the `Camera3D`.

Input goes through the project's input actions only — no keycodes in gameplay
code.

## Not yet

No head bob. No weapon sway. No wall running, no grappling, no ledge grab, no
stamina. Deliberately: the movement already provides plenty of camera motion at
23 m/s and anything more makes this nauseating.
