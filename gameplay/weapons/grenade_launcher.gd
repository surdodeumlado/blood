class_name GrenadeLauncher
extends Weapon

## Placeholder grenade launcher. Not a grenade system: a small pool of reusable
## projectiles, fired, bounced, fused, detonated, recycled.
##
## Its job is to prove the HIGH_ENERGY BloodProfile - radial damage on several
## targets at once, radial blood, heavy environment contamination - and to feel
## clearly different from the blunt weapon, whose burst originates at a victim
## rather than at a point in the world.

@export var muzzle_speed := 22.0
@export var fuse_time := 2.4
@export var cooldown_time := 0.7
@export var blast_radius := 6.0
@export var damage_centre := 160.0
@export var damage_edge := 55.0
## Fraction of speed kept through a world bounce.
@export_range(0.0, 1.0) var bounce_restitution := 0.42
## Below this speed the grenade stops bouncing and just sits out its fuse.
@export var rest_speed := 1.6
@export var projectile_radius := 0.13
## Grenades that may be in the air at once. A third launch is refused until one
## of them goes off.
@export var max_active := 2
## How much of the player's velocity the grenade inherits. Throwing while
## bhopping at 22 m/s has to send it forward, not drop it at your feet.
@export_range(0.0, 1.5) var velocity_inheritance := 0.9

var _cooldown := 0.0

## One entry per live grenade: {node, velocity, fuse, bounces}. The projectile
## nodes are pooled at setup, so firing never allocates.
var _live: Array[Dictionary] = []
var _pool: Array[Node3D] = []

@onready var _rig: Node3D = $Rig
@onready var _projectile: Node3D = $Projectile

var _ray: PhysicsRayQueryParameters3D
var _overlap: PhysicsShapeQueryParameters3D


func _on_setup() -> void:
	_rng.seed = 0x6EADE
	_projectile.visible = false
	# The template plus enough copies to cover the cap.
	_pool.append(_projectile)
	for i in maxi(max_active - 1, 0):
		var copy := _projectile.duplicate() as Node3D
		add_child(copy)
		_pool.append(copy)
	for node in _pool:
		node.top_level = true
		node.visible = false

	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true
	_ray.collision_mask = 1
	var shape := SphereShape3D.new()
	shape.radius = projectile_radius
	_overlap = PhysicsShapeQueryParameters3D.new()
	_overlap.shape = shape
	_overlap.collide_with_areas = true
	_overlap.collide_with_bodies = false
	_overlap.collision_mask = config.hurtbox_layer


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _live.is_empty():
		return
	# Iterate backwards: a grenade can detonate and leave the list mid-loop.
	for i in range(_live.size() - 1, -1, -1):
		_step_grenade(i, delta)


func _step_grenade(index: int, delta: float) -> void:
	var g: Dictionary = _live[index]
	var node: Node3D = g["node"]

	g["fuse"] -= delta
	if g["fuse"] <= 0.0:
		_detonate(index)
		return

	var vel: Vector3 = g["velocity"]
	vel.y -= config.bomb_gravity * delta
	var from: Vector3 = node.global_position
	var to := from + vel * delta

	# A live enemy in the way detonates it on contact - no bounce, no fuse wait.
	# That direct hit is the pay-off shot.
	_overlap.transform = Transform3D(Basis(), to)
	for overlap in get_world_3d().direct_space_state.intersect_shape(_overlap, 4):
		var area = overlap.get("collider")
		if area == null or not area.has_method("take_damage"):
			continue
		if area.has_method("is_damageable") and not area.is_damageable():
			continue
		node.global_position = to
		g["velocity"] = vel
		_live[index] = g
		_detonate(index)
		return

	# Otherwise sweep against static geometry and bounce. The segment test is
	# what stops a grenade thrown at bhop speed tunnelling through a wall.
	_ray.from = from
	_ray.to = to
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if hit.is_empty():
		node.global_position = to
		node.rotate_x(6.0 * delta)
	else:
		var normal: Vector3 = hit.normal
		node.global_position = (hit.position as Vector3) + normal * (projectile_radius * 1.1)
		vel = vel.bounce(normal) * bounce_restitution
		g["bounces"] = int(g["bounces"]) + 1
		Sfx.play_3d(&"impact", node.global_position, 0.7, -16.0)
		# Stop chattering once it has spent its energy; it sits out the fuse.
		if vel.length() < rest_speed:
			vel = Vector3.ZERO

	g["velocity"] = vel
	_live[index] = g


func ready_to_attack() -> bool:
	return _cooldown <= 0.0 and _live.size() < max_active


func try_attack() -> void:
	if not ready_to_attack() or camera() == null:
		return
	_cooldown = cooldown_time
	var cam := camera()
	var node: Node3D = _pool[_live.size()]
	node.global_position = cam.global_position + (-cam.global_basis.z) * 0.7
	node.visible = true

	# Aim plus inherited player motion. Without the inheritance a grenade thrown
	# while bunnyhopping is left behind by the player who threw it.
	var launch := (-cam.global_basis.z + Vector3.UP * 0.12).normalized() * muzzle_speed
	if _shooter is CharacterBody3D:
		launch += (_shooter as CharacterBody3D).velocity * velocity_inheritance

	_live.append({"node": node, "velocity": launch, "fuse": fuse_time, "bounces": 0})
	camera().add_recoil(config.recoil_pitch * 0.8, _rng.randf_range(-0.4, 0.4))
	Sfx.play_2d(&"shot", 0.75, -6.0)


## Radial damage. Every damageable thing inside the blast gets its own hit and
## therefore its own BloodContext, ORIGINATING AT THAT VICTIM with the direction
## pointing away from the blast. That is what stops an explosion being one red
## ball in mid-air and makes it read as several bodies coming apart at once.
func _detonate(index: int) -> void:
	var g: Dictionary = _live[index]
	var node: Node3D = g["node"]
	var centre: Vector3 = node.global_position
	node.visible = false
	_live.remove_at(index)

	Sfx.play_3d(&"death", centre, 0.55, 2.0)
	camera().pulse_fov(config.fov_pulse_head)

	var shape := SphereShape3D.new()
	shape.radius = blast_radius
	var targets := unique_targets(overlap_hurtboxes(shape, Transform3D(Basis(), centre)))

	for id in targets:
		var entry: Dictionary = targets[id]
		var area = entry["area"]
		# The real region height, not the hurtbox node origin at the victim's
		# feet: a head caught by a blast must bleed at head height.
		var point: Vector3 = wound_point_of(area, centre, Vector3.ZERO)
		var offset := point - centre
		var distance := offset.length()
		var falloff: float = clampf(1.0 - distance / maxf(blast_radius, 0.001), 0.0, 1.0)
		var damage: float = lerpf(damage_edge, damage_centre, falloff)
		var dir := offset.normalized() if distance > 0.01 else Vector3.UP
		apply_hit(
			area, point, dir, dir, entry["zone"], damage, 1.0 + falloff,
			func(ctx: BloodContext) -> void: ctx.explosion_direction_ws = dir
		)

	# NO victim, NO blood. A blast in an empty room is a blast in an empty room;
	# inventing a body's worth of blood out of thin air was the single loudest
	# lie in the pipeline.


## Launched grenades are world space and keep flying and detonating even if the
## player swaps weapons, so only the held rig is hidden.
func set_active(value: bool) -> void:
	active = value
	_rig.visible = value


func active_count() -> int:
	return _live.size()


func bounces_of(index: int) -> int:
	if index < 0 or index >= _live.size():
		return 0
	return int(_live[index]["bounces"])


func velocity_of(index: int) -> Vector3:
	if index < 0 or index >= _live.size():
		return Vector3.ZERO
	return _live[index]["velocity"]


## Test hook: force the oldest grenade's fuse to expire now.
func force_fuse() -> void:
	if not _live.is_empty():
		_live[0]["fuse"] = 0.0
