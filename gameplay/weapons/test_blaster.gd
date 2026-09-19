class_name TestBlaster
extends Node3D

## Placeholder hand cannon. Semi-auto, hitscan, infinite ammo, no reload.
## Not a weapon system and not a combat framework: one script whose job is
##
##     INPUT -> IMMEDIATE FEEDBACK -> TRACER -> IMPACT -> REACTION
##
## readable enough that shooting while moving can be judged.
##
## Hit detection and presentation are separate on purpose. _trace() resolves the
## shot and applies damage; everything else in here is cosmetic and could be
## deleted wholesale without changing who takes damage or how much.
##
## The cooldown lives here, never in the movement controller: the player can
## jump, dash, slide, bunnyhop and air-strafe freely through the whole spin.

signal hit_confirmed(zone: StringName)

const ZONE_BODY := &"body"
const ZONE_HEAD := &"head"

@export var config: CombatConfig

@onready var _rig: Node3D = $Rig
@onready var _muzzle: Node3D = $Rig/Muzzle
@onready var _flash: MeshInstance3D = $Rig/Muzzle/Flash
@onready var _light: OmniLight3D = $Rig/Muzzle/Light
@onready var _fx: ImpactFx = $ImpactFx

var _camera: FirstPersonCamera
var _shooter: CollisionObject3D
var _cooldown := 0.0
var _flash_time := 0.0
var _spinning := false
var _rig_rest := Vector3.ZERO
var _hitstop_token := 0
var _ray: PhysicsRayQueryParameters3D
var _rng := RandomNumberGenerator.new()


func setup(camera: FirstPersonCamera, shooter: CollisionObject3D) -> void:
	_camera = camera
	_shooter = shooter
	_rig_rest = _rig.position
	_light.light_energy = config.muzzle_light_energy
	_light.omni_range = config.muzzle_light_range
	_light.shadow_enabled = false
	_flash.scale = Vector3.ONE * config.muzzle_flash_scale
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true
	_ray.exclude = [_shooter.get_rid()]
	_ray.collision_mask = _shooter.collision_mask
	_set_flash(false)


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_time <= 0.0:
			_set_flash(false)
	if _spinning:
		_update_spin()


func ready_to_fire() -> bool:
	return _cooldown <= 0.0


## Semi-auto: the player calls this once per press, never while held.
func try_fire() -> void:
	if _cooldown > 0.0 or _camera == null:
		return
	_cooldown = config.fire_interval
	_spinning = true
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

	# The trace starts at the eye so the crosshair is honest.
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

	# The target owns its own hitbox layout; the weapon owns the damage numbers.
	var zone := ZONE_BODY
	if collider.has_method("hit_zone"):
		zone = collider.hit_zone(hit.shape)
	var is_head := zone == ZONE_HEAD
	var killed: bool = collider.take_damage(
		config.damage_head if is_head else config.damage_body, point, dir, zone
	)

	_present_enemy_impact(muzzle_pos, point, is_head)
	hit_confirmed.emit(zone)
	if is_head:
		_hitstop(config.hitstop_headshot)
	else:
		_hitstop(config.hitstop_kill if killed else config.hitstop_hit)


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


func _present_enemy_impact(muzzle_pos: Vector3, point: Vector3, is_head: bool) -> void:
	_fx.tracer(muzzle_pos, point)
	_fx.impact(point, ImpactFx.Kind.HEAD if is_head else ImpactFx.Kind.ENEMY)
	if is_head:
		Sfx.play_3d(&"headshot", point, _rng.randf_range(0.98, 1.04), -4.0)


## The spin is the cooldown readout: the weapon is thrown back and flipped on
## firing, and is level and still again exactly when the next shot is available.
func _update_spin() -> void:
	if _cooldown <= 0.0:
		_rig.rotation.x = 0.0
		_rig.position = _rig_rest
		_spinning = false
		return
	var t := clampf(1.0 - _cooldown / config.fire_interval, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - t, config.spin_ease_exponent)
	var settle := 1.0 - eased
	_rig.rotation.x = -TAU * config.spin_turns * eased
	_rig.position = _rig_rest + Vector3(0.0, config.kick_up, config.kick_back) * settle


func _set_flash(on: bool) -> void:
	_flash.visible = on
	_light.visible = on


## Very short real-time freeze. Token guards against overlapping calls restoring
## time_scale early.
func _hitstop(duration: float) -> void:
	if duration <= 0.0:
		return
	_hitstop_token += 1
	var token := _hitstop_token
	Engine.time_scale = config.hitstop_scale
	await get_tree().create_timer(duration, true, false, true).timeout
	if token == _hitstop_token:
		Engine.time_scale = 1.0
