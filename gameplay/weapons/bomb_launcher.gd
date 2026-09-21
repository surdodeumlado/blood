class_name BombLauncher
extends Weapon

## Placeholder explosive test instrument. Not a grenade system: one reusable
## bomb object, thrown, fused, detonated, recycled.
##
## Its job is to prove the HIGH_ENERGY BloodProfile - radial damage on several
## targets at once, radial blood, heavy environment contamination.

@export var throw_speed := 14.0
@export var fuse_time := 1.1
@export var blast_radius := 5.5
@export var damage_centre := 130.0
@export var damage_edge := 45.0
@export var cooldown_time := 0.9

var _cooldown := 0.0
var _fuse := 0.0
var _flying := false
var _velocity := Vector3.ZERO

@onready var _rig: Node3D = $Rig
@onready var _projectile: Node3D = $Projectile


func _on_setup() -> void:
	_rng.seed = 0xB0B
	_projectile.top_level = true
	_projectile.visible = false


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not _flying:
		return

	# Cheap ballistic arc. One bomb in the air at a time, so this costs nothing.
	_velocity.y -= config.bomb_gravity * delta
	_projectile.global_position += _velocity * delta
	_projectile.rotate_x(4.0 * delta)

	_fuse -= delta
	var floor_y := _floor_below(_projectile.global_position)
	if _projectile.global_position.y <= floor_y + 0.12:
		_projectile.global_position.y = floor_y + 0.12
		_velocity = Vector3.ZERO
	if _fuse <= 0.0:
		_detonate()


func ready_to_attack() -> bool:
	return _cooldown <= 0.0 and not _flying


func try_attack() -> void:
	if not ready_to_attack() or camera() == null:
		return
	_cooldown = cooldown_time
	var cam := camera()
	_projectile.global_position = cam.global_position + (-cam.global_basis.z) * 0.6
	_velocity = (-cam.global_basis.z + Vector3.UP * 0.25).normalized() * throw_speed
	_projectile.visible = true
	_flying = true
	_fuse = fuse_time
	Sfx.play_2d(&"dash", 0.7, -10.0)


## Radial damage. Every damageable thing inside the blast gets its own hit and
## therefore its own BloodContext, which is what makes a multi-kill explosion
## contaminate the whole area.
func _detonate() -> void:
	_flying = false
	_projectile.visible = false
	var centre := _projectile.global_position

	Sfx.play_3d(&"death", centre, 0.6, 0.0)
	camera().pulse_fov(config.fov_pulse_head)

	var shape := SphereShape3D.new()
	shape.radius = blast_radius
	var targets := unique_targets(overlap_hurtboxes(shape, Transform3D(Basis(), centre)))

	for id in targets:
		var entry: Dictionary = targets[id]
		var area = entry["area"]
		var point: Vector3 = (area as Node3D).global_position
		var offset := point - centre
		var distance := offset.length()
		var falloff: float = clampf(1.0 - distance / maxf(blast_radius, 0.001), 0.0, 1.0)
		var damage: float = lerpf(damage_edge, damage_centre, falloff)
		# Direction is radially outward from the blast, so the blood follows the
		# explosion rather than a shot line.
		var dir := offset.normalized() if distance > 0.01 else Vector3.UP
		apply_hit(area, point, dir, dir, entry["zone"], damage, 1.0 + falloff)

	# Mark the world even when nothing was standing there.
	var blood := _blood_system()
	if blood != null and targets.is_empty():
		var ctx := BloodContext.make(
			damage_type, centre + Vector3.UP * 0.3, Vector3.ZERO,
			BloodTypes.BodyRegion.TORSO, impact_energy
		)
		blood.spill(ctx)


func _floor_below(from: Vector3) -> float:
	var params := PhysicsRayQueryParameters3D.new()
	params.from = from + Vector3.UP * 0.2
	params.to = from + Vector3.DOWN * 40.0
	params.collide_with_areas = false
	params.collision_mask = 1
	var hit := camera().get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return from.y - 40.0
	return (hit.position as Vector3).y


## The thrown bomb is world space and must keep flying and detonating even if
## the player swaps weapons mid-air, so only the held rig is hidden - hiding the
## whole node would take the live projectile with it.
func set_active(value: bool) -> void:
	active = value
	_rig.visible = value
