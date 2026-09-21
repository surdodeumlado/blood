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

@export_group("Weapon spin (presentation only)")
## Full rotations the weapon performs between shots. The spin is a READOUT of
## the gameplay cooldown, never its source: see TestBlaster for the split.
@export var spin_turns := 1.0
## Higher = the spin snaps away fast and settles slowly into the ready pose.
@export var spin_ease_exponent := 3.0
## Metres the weapon is thrown back toward the camera on firing.
@export var kick_back := 0.12
## Metres the weapon is thrown up on firing.
@export var kick_up := 0.05
## Seconds the SPIN (and only the spin) freezes when a shot connects, so the
## impact reads on the weapon. The gameplay cooldown keeps running underneath.
@export var impact_hold_body := 0.03
@export var impact_hold_head := 0.05
## How much faster than real time the spin catches back up to the gameplay
## phase after a hold. Multiplier on the normal spin rate; must be > 1.0 or the
## visual would never resynchronise.
@export var spin_catchup_multiplier := 2.5
## Extra metres the weapon is shoved back on a connecting hit.
@export var impact_kick := 0.05

@export_group("Blood")
## Which impact family this weapon produces. The blood profile for it lives in
## data/blood/ - nothing about the look is decided here.
@export var blood_damage_type: BloodTypes.DamageType = BloodTypes.DamageType.BALLISTIC
## Impact energy, normalised around 1.0 (see BloodTypes.ENERGY_*). This is how
## a pistol, this hand cannon and a future shotgun all stay BALLISTIC without
## looking identical.
@export var blood_energy := 1.45
## Extra energy on a headshot, before the profile's own head multiplier.
@export var blood_headshot_energy_bonus := 0.25

@export_group("Weapon lab (THE_BOX test instruments)")
## Camera kick for the melee test instruments.
@export var melee_recoil_pitch := 1.4
## Gravity applied to the thrown test bomb.
@export var bomb_gravity := 18.0

@export_group("Hit accent (no time scale, ever)")
## Degrees of FOV pulse on a body hit. Local feedback only: nothing about impact
## is allowed to pause the player, the physics, the camera or the cooldown.
@export var fov_pulse_body := 1.0
@export var fov_pulse_head := 2.5

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

@export_group("Hurtboxes")
## Hurtboxes are Area3D volumes, completely separate from the physics collider,
## so aim forgiveness never makes the dummy physically fatter.
##
## Visual reference on the dummy: body capsule radius 0.45 / height 1.9, head
## box 0.5 cubed centred at y = 2.15 (half-extent 0.25).
##
## Body: same capsule shape as the visual, +20% radius. Because the shape
## matches, the forgiveness is a uniform +20% from ankles to shoulders, with no
## thin spots and no gap against the head.
@export var body_hurtbox_radius := 0.54
@export var body_hurtbox_height := 1.9
## Head: a BOX, not a sphere, so the margin is uniform on every axis and the
## whole visual head is genuinely inside it. The visual head is a 0.5 x 0.45 x
## 0.5 box, so this is +35% per axis. A sphere large enough to enclose that box
## would have to reach 0.42 just to touch its corners, and anything bigger
## started eating chest shots.
@export var head_hurtbox_size := Vector3(0.675, 0.608, 0.675)
@export var head_hurtbox_y := 2.15
## Physics layer the hurtbox areas live on. The weapon ray looks for world
## geometry AND this layer; the dummy's own body layer is irrelevant to aiming.
@export var hurtbox_layer := 2

@export_group("Death")
@export var death_fragments := 7
@export var death_fragment_impulse := 6.0
@export var death_fragment_lifetime := 2.5

@export_group("Death presentation")
## Seconds the corpse visual is carried along the blow before it is retired.
## PURELY PRESENTATIONAL: hurtboxes and the collider are already disabled when
## this starts, so it cannot change who can be hit or what takes damage. It
## exists because a target that vanished on the spot fought the impression that
## a heavy blow had thrown it somewhere. Set to 0 to disable.
@export var dummy_death_throw_time := 0.42
@export var dummy_death_throw_speed := 7.5
@export var dummy_death_throw_lift := 2.6
@export var dummy_death_spin := 5.0
