class_name CombatConfig
extends Resource

## Tuning for the placeholder hand cannon and all of its feedback. Same rule as
## MovementConfig: no combat magic numbers anywhere else.
##
## Design: few shots, every shot matters, high mobility between shots, accuracy
## rewarded. Semi-auto only - no automatic fire, no burst, no reload, ammo is
## infinite for THE BOX.

@export_group("Weapon")
## Seconds between shots. The spin animation is timed to exactly this, so the
## weapon itself tells the player when the next shot is available.
@export var fire_interval := 0.62
@export var range_metres := 120.0
## Three of these kill the basic dummy.
@export var damage_body := 34.0
## One of these kills it outright.
@export var damage_head := 120.0
## Cone half-angle in degrees. Zero: a hand cannon is pinpoint, and accuracy is
## supposed to be the thing being rewarded.
@export var spread_degrees := 0.0

@export_group("Recoil")
## Degrees of camera pitch kick per shot. One firm kick, not a rattle.
@export var recoil_pitch := 2.2
## Degrees of random camera yaw kick per shot.
@export var recoil_yaw := 0.45
## Higher = the camera returns to the aim point faster.
@export var recoil_recovery := 11.0

@export_group("Weapon spin (cooldown tell)")
## Full rotations the weapon performs between shots. The spin IS the cooldown
## readout: when the gun is level again, you can fire again.
@export var spin_turns := 1.0
## Higher = the spin snaps away fast and settles slowly into the ready pose.
@export var spin_ease_exponent := 3.0
## Metres the weapon is thrown back toward the camera on firing.
@export var kick_back := 0.12
## Metres the weapon is thrown up on firing.
@export var kick_up := 0.05

@export_group("Muzzle")
@export var muzzle_flash_time := 0.06
@export var muzzle_light_energy := 7.0
@export var muzzle_light_range := 7.0
@export var muzzle_flash_scale := 1.9

@export_group("Tracer")
## Presentation only. Hit detection is instantaneous hitscan and does not wait
## for, or care about, any of this.
@export var tracer_lifetime := 0.045
@export var tracer_thickness := 0.075
@export var tracer_color := Color(1.0, 0.82, 0.38, 1.0)
## Hard ceiling on simultaneous tracers. Pooled, never allocated at runtime.
@export var tracer_pool_size := 12

@export_group("Impact")
@export var impact_lifetime := 0.18
@export var impact_start_radius := 0.08
@export var impact_end_radius := 0.5
@export var impact_world_color := Color(1.0, 0.92, 0.62, 1.0)
@export var impact_enemy_color := Color(1.0, 0.16, 0.14, 1.0)
@export var impact_head_color := Color(1.0, 0.95, 0.75, 1.0)
@export var impact_pool_size := 12

@export_group("Hit stop")
## Real seconds the game freezes on a hit. Keep tiny or combat turns to mud.
@export var hitstop_hit := 0.03
@export var hitstop_kill := 0.07
@export var hitstop_headshot := 0.1
## Engine.time_scale used during hit stop.
@export var hitstop_scale := 0.05

@export_group("Enemy dummy")
## 100 / damage_body = three body shots. One headshot overkills it.
@export var dummy_max_health := 100.0
@export var dummy_knockback := 6.0
@export var dummy_knockback_lift := 1.8
## Headshots hit visibly harder.
@export var dummy_headshot_force := 2.0
@export var dummy_flash_time := 0.14
## Seconds the dummy is stunned in place after a hit (visual recoil window).
@export var dummy_stagger_time := 0.09
@export var dummy_respawn_delay := 3.0
@export var dummy_gravity := 24.0
@export var dummy_friction := 12.0
## Radius of the head hitbox. Deliberately generous: this prototype is about
## feel, not about competitive pixel-perfect aim.
@export var dummy_head_radius := 0.48

@export_group("Death")
@export var death_fragments := 7
@export var death_fragment_impulse := 6.0
@export var death_fragment_lifetime := 2.5
