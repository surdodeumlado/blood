class_name DummyTarget
extends CharacterBody3D

## Placeholder target. There is no AI here on purpose: it stands still, takes
## damage, reacts, dies and comes back. Its whole job is to let us judge hit
## feedback and death feedback, not behaviour.

const ZONE_BODY := &"body"
const ZONE_HEAD := &"head"

@export var config: CombatConfig

@onready var _visual: Node3D = $Visual
@onready var _collider: CollisionShape3D = $Collider
@onready var _head_collider: CollisionShape3D = $HeadCollider

var _health := 0.0
var _flash := 0.0
var _stagger := 0.0
var _lean := Vector3.ZERO
var _alive := true
var _spawn_position := Vector3.ZERO
var _material: StandardMaterial3D
var _head_shape_index := -1


func _ready() -> void:
	_spawn_position = global_position
	# Own a private copy of the material so flashing one dummy never flashes
	# every dummy in the arena.
	_material = _build_material()
	for child in _visual.get_children():
		if child is MeshInstance3D:
			child.material_override = _material
	# Own the head sphere too, so its generosity is a config number and not
	# something buried in a scene file.
	var head_shape := SphereShape3D.new()
	head_shape.radius = config.dummy_head_radius
	_head_collider.shape = head_shape
	_head_shape_index = _shape_index_of(_head_collider)

	_health = config.dummy_max_health
	_refresh_tint()


func _physics_process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta, 0.0)
		_material.emission_energy_multiplier = 6.0 * (_flash / config.dummy_flash_time)

	if _lean.length_squared() > 0.000001:
		_lean = _lean.lerp(Vector3.ZERO, 1.0 - exp(-10.0 * delta))
		_visual.rotation = _lean

	if not _alive:
		return

	_stagger = maxf(_stagger - delta, 0.0)
	if not is_on_floor():
		velocity.y -= config.dummy_gravity * delta
	else:
		velocity.y = minf(velocity.y, 0.0)

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horizontal.length()
	if speed > 0.01:
		var drop := config.dummy_friction * delta
		horizontal *= maxf(speed - drop, 0.0) / speed
		velocity.x = horizontal.x
		velocity.z = horizontal.z
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()


## The dummy owns its own hitbox layout: the weapon hands back the shape index
## the trace reported and gets told which zone that was. The head sphere is
## deliberately generous - this prototype is about feel, not competitive aim.
func hit_zone(shape_index: int) -> StringName:
	return ZONE_HEAD if shape_index == _head_shape_index else ZONE_BODY


## Duck-typed damage entry point. The weapon only checks has_method(), so there
## is no interface, base class or combat framework involved. The caller decides
## how much damage a zone is worth; the dummy only decides how it reacts.
## Returns true if this hit killed the dummy.
func take_damage(
	amount: float, point: Vector3, direction: Vector3, zone := ZONE_BODY
) -> bool:
	if not _alive:
		return false

	var force := config.dummy_headshot_force if zone == ZONE_HEAD else 1.0
	_health -= amount
	_flash = config.dummy_flash_time
	_stagger = config.dummy_stagger_time
	_material.emission_energy_multiplier = 6.0

	# Physical reaction: shove along the shot, plus a visible lean away from it.
	var push := Vector3(direction.x, 0.0, direction.z).normalized()
	velocity += push * config.dummy_knockback * force
	velocity.y = maxf(velocity.y, 0.0) + config.dummy_knockback_lift * force
	_lean = Vector3(push.z, 0.0, -push.x) * 0.28 * force

	if _health > 0.0:
		_refresh_tint()
		Sfx.play_3d(&"hit", point, randf_range(0.95, 1.12), -10.0)
		return false

	_die(push * force)
	return true


## A raycast reports the shape INDEX it hit, which is not the same thing as
## child order, so resolve it through the shape owners instead of guessing.
func _shape_index_of(node: CollisionShape3D) -> int:
	for owner_id in get_shape_owners():
		if shape_owner_get_owner(owner_id) == node:
			return shape_owner_get_shape_index(owner_id, 0)
	return -1


func _die(push: Vector3) -> void:
	_alive = false
	_visual.visible = false
	_collider.set_deferred("disabled", true)
	_head_collider.set_deferred("disabled", true)
	velocity = Vector3.ZERO
	Sfx.play_3d(&"death", global_position, randf_range(0.9, 1.05), -4.0)
	_spawn_fragments(push)
	_respawn_after(config.dummy_respawn_delay)


## Placeholder break-apart, NOT the gore system. A fixed, small number of short
## lived rigid bodies that free themselves; nothing accumulates.
func _spawn_fragments(push: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.22, 0.22, 0.22)
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	var mat := _build_material()
	var parent := get_parent()

	for i in config.death_fragments:
		var frag := RigidBody3D.new()
		# Own layer, and a mask that only sees the world: fragments never shove
		# the player or block a shot.
		frag.collision_layer = 4
		frag.collision_mask = 1
		var cs := CollisionShape3D.new()
		cs.shape = shape
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		frag.add_child(cs)
		frag.add_child(mi)
		parent.add_child(frag)
		frag.global_position = global_position + Vector3(
			randf_range(-0.3, 0.3), randf_range(0.4, 1.5), randf_range(-0.3, 0.3)
		)
		frag.linear_velocity = (
			push * config.death_fragment_impulse * 0.5
			+ Vector3(
				randf_range(-1.0, 1.0), randf_range(0.6, 1.6), randf_range(-1.0, 1.0)
			) * config.death_fragment_impulse
		)
		frag.angular_velocity = Vector3(
			randf_range(-12.0, 12.0), randf_range(-12.0, 12.0), randf_range(-12.0, 12.0)
		)
		_free_after(frag, config.death_fragment_lifetime)


func _free_after(node: Node, seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	if is_instance_valid(node):
		node.queue_free()


func _respawn_after(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	if not is_inside_tree():
		return
	global_position = _spawn_position
	velocity = Vector3.ZERO
	_health = config.dummy_max_health
	_lean = Vector3.ZERO
	_visual.rotation = Vector3.ZERO
	_visual.visible = true
	_collider.set_deferred("disabled", false)
	_head_collider.set_deferred("disabled", false)
	_alive = true
	_refresh_tint()


## No damage numbers: the dummy simply reads as more beaten up as it loses HP.
func _refresh_tint() -> void:
	var t: float = clampf(_health / config.dummy_max_health, 0.0, 1.0)
	# Emission energy is left alone here: the hit flash owns it.
	_material.albedo_color = Color(0.95, 0.35, 0.3).lerp(Color(0.28, 0.1, 0.12), 1.0 - t)


func _build_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.35, 0.3)
	mat.roughness = 0.6
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.25)
	mat.emission_energy_multiplier = 0.0
	return mat
