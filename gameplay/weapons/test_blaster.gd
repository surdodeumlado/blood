class_name TestBlaster
extends Weapon

## Placeholder hand cannon. Semi-auto, hitscan, infinite ammo, no reload.
## Not a weapon system and not a combat framework: one script whose job is
##
##     INPUT -> IMMEDIATE FEEDBACK -> TRACER -> IMPACT -> REACTION
##
## readable enough that shooting while moving can be judged.
##
## THREE things are kept strictly apart in here:
##
##   1. Gameplay cooldown (_cooldown). Decrements every frame, unconditionally.
##      It is the ONLY thing ready_to_fire() looks at. Nothing - not a hit, not
##      an animation, not a hold - may ever extend it.
##   2. Hit detection (_trace). Resolves the shot and applies damage. Deleting
##      every effect below would not change who takes damage or how much.
##   3. Presentation (_spin_phase, flash, tracer, kick). May lag behind the
##      cooldown for impact feel, and catches up on its own.
##
## There is deliberately NO hit stop and no use of Engine.time_scale: in a
## movement game, impact must never take control away from the player.

@onready var _rig: Node3D = $Rig
@onready var _muzzle: Node3D = $Rig/Muzzle
@onready var _flash: MeshInstance3D = $Rig/Muzzle/Flash
@onready var _light: OmniLight3D = $Rig/Muzzle/Light
@onready var _fx: ImpactFx = $ImpactFx


# --- Gameplay ---
var _cooldown := 0.0

# --- Presentation ---
var _spin_phase := 1.0
var _spin_hold := 0.0
var _impact_kick := 0.0
var _flash_time := 0.0
var _rig_rest := Vector3.ZERO

var _ray: PhysicsRayQueryParameters3D


func _on_setup() -> void:
	_rig_rest = _rig.position
	_light.light_energy = config.muzzle_light_energy
	_light.omni_range = config.muzzle_light_range
	_light.shadow_enabled = false
	_flash.scale = Vector3.ONE * config.muzzle_flash_scale
	_ray = PhysicsRayQueryParameters3D.new()
	# Hurtboxes are areas, so the trace has to look for them explicitly.
	_ray.collide_with_areas = true
	_ray.collide_with_bodies = true
	_ray.exclude = [_shooter.get_rid()]
	# World geometry plus hurtboxes. Characters live on their own layer and are
	# never shot directly - you shoot their hurtboxes.
	_ray.collision_mask = 1 | config.hurtbox_layer
	_set_flash(false)


func _process(delta: float) -> void:
	# Gameplay clock. Nothing below is allowed to touch this.
	_cooldown = maxf(_cooldown - delta, 0.0)

	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_time <= 0.0:
			_set_flash(false)
	_update_spin(delta)


## The single source of truth for whether the weapon can fire.
func ready_to_attack() -> bool:
	return ready_to_fire()


func try_attack() -> void:
	try_fire()


## The single source of truth for whether the weapon can fire.
func ready_to_fire() -> bool:
	return _cooldown <= 0.0


func cooldown_left() -> float:
	return _cooldown


## Semi-auto: the player calls this once per press, never while held.
func try_fire() -> void:
	if not ready_to_fire() or _camera == null:
		return
	_cooldown = config.fire_interval
	_spin_phase = 0.0
	_spin_hold = 0.0
	var muzzle_pos := _muzzle.global_position
	_present_shot()
	_trace(muzzle_pos)


# --------------------------------------------------------------------------
# Gameplay. This half decides what got hit and for how much.
# --------------------------------------------------------------------------

func _trace(muzzle_pos: Vector3) -> void:
	var basis := _camera.global_basis
	var dir := -basis.z
	if config.spread_degrees > 0.0:
		var spread := deg_to_rad(config.spread_degrees)
		dir = dir \
			.rotated(basis.x, _rng.randf_range(-spread, spread)) \
			.rotated(basis.y, _rng.randf_range(-spread, spread))
	dir = dir.normalized()

	# The trace starts at the eye and runs straight down the camera's forward
	# axis, which is exactly what the centred crosshair draws. Aim, ray and
	# crosshair cannot diverge because they are the same vector.
	var origin := _camera.global_position
	_ray.from = origin
	_ray.to = origin + dir * config.range_metres

	var hit := _camera.get_world_3d().direct_space_state.intersect_ray(_ray)
	if hit.is_empty():
		_fx.tracer(muzzle_pos, _ray.to)
		return

	var point: Vector3 = hit.position
	var collider = hit.collider
	if collider == null or not collider.has_method("take_damage"):
		_present_world_impact(muzzle_pos, point)
		return

	# Having a take_damage() is not the same as being a valid target. A corpse
	# still has one, and treating that as a live hit is what used to produce a
	# hitmarker and a fresh blood burst on something already dead. Anything that
	# cannot be hurt is resolved as world geometry instead.
	if collider.has_method("is_damageable") and not collider.is_damageable():
		_present_world_impact(muzzle_pos, point)
		return

	# The target owns its own hurtbox layout; the weapon owns the damage numbers.
	var zone := ZONE_BODY
	if collider.has_method("hit_zone"):
		zone = collider.hit_zone(hit.shape)
	var is_head := zone == ZONE_HEAD
	_present_enemy_impact(muzzle_pos, point, is_head)
	# Damage and the blood context both go through the shared path, so this
	# weapon still never decides anything about how the wound looks.
	var energy_scale := 1.0
	if is_head:
		energy_scale += config.blood_headshot_energy_bonus / maxf(impact_energy, 0.001)
	apply_hit(
		collider, point, dir, hit.get("normal", Vector3.ZERO), zone,
		config.damage_head if is_head else config.damage_body, energy_scale
	)


# --------------------------------------------------------------------------
# Presentation. None of this is load-bearing.
# --------------------------------------------------------------------------

## Fires before the trace resolves: the player never waits on hit detection.
func _present_shot() -> void:
	_set_flash(true)
	_flash_time = config.muzzle_flash_time
	_camera.add_recoil(config.recoil_pitch, _rng.randf_range(-1.0, 1.0) * config.recoil_yaw)
	Sfx.play_2d(&"shot", _rng.randf_range(0.97, 1.03), -3.0)


func _present_world_impact(muzzle_pos: Vector3, point: Vector3) -> void:
	_fx.tracer(muzzle_pos, point)
	_fx.impact(point, ImpactFx.Kind.WORLD)
	Sfx.play_3d(&"impact", point, _rng.randf_range(0.9, 1.1), -12.0)


## Local impact accent. A short FOV pulse, a shove on the weapon and a freeze of
## the SPIN ONLY - the player keeps full control of movement and of the clock.
func _present_enemy_impact(muzzle_pos: Vector3, point: Vector3, is_head: bool) -> void:
	_fx.tracer(muzzle_pos, point)
	_fx.impact(point, ImpactFx.Kind.HEAD if is_head else ImpactFx.Kind.ENEMY)
	_camera.pulse_fov(config.fov_pulse_head if is_head else config.fov_pulse_body)
	_spin_hold = maxf(_spin_hold, config.impact_hold_head if is_head else config.impact_hold_body)
	_impact_kick = config.impact_kick
	if is_head:
		Sfx.play_3d(&"headshot", point, _rng.randf_range(0.98, 1.04), -4.0)


## The spin is a READOUT of the cooldown, not its source.
##
## Normally _spin_phase simply tracks the gameplay phase. On a hit it is frozen
## for a few tens of milliseconds so the impact registers on the weapon, then it
## catches up faster than real time until it is back in sync. Because the
## gameplay clock never stopped, the shot becomes available exactly on schedule
## whether or not the visual is still catching up.
func _update_spin(delta: float) -> void:
	var gameplay_phase := 1.0
	if config.fire_interval > 0.0:
		gameplay_phase = clampf(1.0 - _cooldown / config.fire_interval, 0.0, 1.0)

	if _spin_hold > 0.0:
		_spin_hold -= delta
	else:
		var catchup := config.spin_catchup_multiplier / maxf(config.fire_interval, 0.001)
		_spin_phase = move_toward(_spin_phase, gameplay_phase, catchup * delta)

	_impact_kick = maxf(_impact_kick - delta * 6.0, 0.0)

	var eased := 1.0 - pow(1.0 - _spin_phase, config.spin_ease_exponent)
	var settle := 1.0 - eased
	_rig.rotation.x = -TAU * config.spin_turns * eased
	_rig.position = _rig_rest \
		+ Vector3(0.0, config.kick_up, config.kick_back) * settle \
		+ Vector3(0.0, 0.0, _impact_kick)


func _set_flash(on: bool) -> void:
	_flash.visible = on
	_light.visible = on
