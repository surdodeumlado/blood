class_name DummyTarget
extends CharacterBody3D

## Placeholder target. There is no AI here on purpose: it stands still, takes
## damage, reacts, dies and comes back. Its whole job is to let us judge hit
## feedback and death feedback, not behaviour.

const ZONE_BODY := &"body"
const ZONE_HEAD := &"head"

@export var config: CombatConfig

## Toggled together for every dummy via the "dummies" group.
const DEBUG_GROUP := &"dummies"

@onready var _visual: Node3D = $Visual
@onready var _reservoir: BloodReservoir = $BloodReservoir
@onready var _collider: CollisionShape3D = $Collider
@onready var _body_hurtbox: Hurtbox = $Hurtboxes/BodyHurtbox
@onready var _head_hurtbox: Hurtbox = $Hurtboxes/HeadHurtbox
@onready var _body_hurtbox_shape: CollisionShape3D = $Hurtboxes/BodyHurtbox/Shape
@onready var _head_hurtbox_shape: CollisionShape3D = $Hurtboxes/HeadHurtbox/Shape
@onready var _hurtbox_debug: Node3D = $HurtboxDebug

var _health := 0.0
var _flash := 0.0
var _stagger := 0.0
var _lean := Vector3.ZERO
## PURELY PRESENTATIONAL death throw. The visual is carried along the blow for a
## moment before it is hidden, so a maul kill has something moving in the
## direction the blood went. Hurtboxes and the collider are already disabled by
## the time this runs, so it cannot affect gameplay in any way.
var _death_throw := Vector3.ZERO
var _death_spin := Vector3.ZERO
var _death_time := 0.0
var _alive := true
var _spawn_position := Vector3.ZERO
var _material: StandardMaterial3D
var _overkill := 0.0


func _ready() -> void:
	_spawn_position = global_position
	# Own a private copy of the material so flashing one dummy never flashes
	# every dummy in the arena.
	_material = _build_material()
	for child in _visual.get_children():
		if child is MeshInstance3D:
			child.material_override = _material
	_build_hurtboxes()
	add_to_group(DEBUG_GROUP)
	_health = config.dummy_max_health
	_refresh_tint()
	# The blood system ticks every registered reservoir's wounds, so a wounded
	# dummy drips without this scene needing a _process of its own.
	var blood := BloodSystem.find(get_tree())
	if blood != null:
		blood.register_reservoir(_reservoir)


## Hurtbox geometry is owned here and driven entirely by config, so aim
## forgiveness is a number you can tune rather than something buried in a scene.
func _build_hurtboxes() -> void:
	var body_shape := CapsuleShape3D.new()
	body_shape.radius = config.body_hurtbox_radius
	body_shape.height = config.body_hurtbox_height
	_body_hurtbox_shape.shape = body_shape
	_body_hurtbox_shape.position.y = config.body_hurtbox_height * 0.5
	_body_hurtbox.zone = Hurtbox.ZONE_BODY
	_body_hurtbox.collision_layer = config.hurtbox_layer

	var head_shape := BoxShape3D.new()
	head_shape.size = config.head_hurtbox_size
	_head_hurtbox_shape.shape = head_shape
	_head_hurtbox_shape.position.y = config.head_hurtbox_y
	_head_hurtbox.zone = Hurtbox.ZONE_HEAD
	_head_hurtbox.collision_layer = config.hurtbox_layer

	_build_hurtbox_debug(body_shape, head_shape)


## Optional wireframe-ish overlay so hurtbox tuning can be done by eye.
func _build_hurtbox_debug(body_shape: CapsuleShape3D, head_shape: BoxShape3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 1.0, 0.4, 0.18)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var head_mat := mat.duplicate() as StandardMaterial3D
	head_mat.albedo_color = Color(1.0, 0.85, 0.2, 0.22)

	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = body_shape.radius
	body_mesh.height = body_shape.height
	_add_debug_mesh(body_mesh, mat, _body_hurtbox_shape.position.y)

	var head_mesh := BoxMesh.new()
	head_mesh.size = head_shape.size
	_add_debug_mesh(head_mesh, head_mat, _head_hurtbox_shape.position.y)

	_hurtbox_debug.visible = false


func _add_debug_mesh(mesh: Mesh, mat: Material, y: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hurtbox_debug.add_child(mi)
	mi.position.y = y


func set_hurtbox_debug(shown: bool) -> void:
	_hurtbox_debug.visible = shown


## A dead dummy is not shootable, and it stops being shootable IMMEDIATELY.
##
## Clearing collision_layer takes effect for the very next ray query, with no
## deferred frame in between - that gap is what used to let a shot fired the
## same frame as the kill still resolve against a corpse. The shape disable is
## deferred because it is not safe to touch mid-physics, and is only a belt to
## the layer change.
func _set_hurtboxes_enabled(enabled: bool) -> void:
	var layer := config.hurtbox_layer if enabled else 0
	_body_hurtbox.collision_layer = layer
	_head_hurtbox.collision_layer = layer
	_body_hurtbox_shape.set_deferred("disabled", not enabled)
	_head_hurtbox_shape.set_deferred("disabled", not enabled)


## Hit resolution asks this before applying anything. A corpse says no, so a
## corpse produces no damage, no hitmarker and no blood.
func is_damageable() -> bool:
	return _alive


func _physics_process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta, 0.0)
		_material.emission_energy_multiplier = 6.0 * (_flash / config.dummy_flash_time)

	if _death_time > 0.0:
		_advance_death_throw(delta)
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


## Optional extra the blood system asks for by duck-typing. Reports how far past
## zero the last hit went, as a fraction of a full health bar.
## Duck-typed so a multi-hit sweep can scale secondary damage to the victim.
func max_health() -> float:
	return config.dummy_max_health


func overkill_ratio() -> float:
	return _overkill


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
	# Damage past zero, as a fraction of a full health bar. Blood reads this to
	# make a wildly overkilling hit look like one.
	_overkill = maxf(amount - maxf(_health, 0.0), 0.0) / maxf(config.dummy_max_health, 0.001)
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


func _die(push: Vector3) -> void:
	_alive = false
	_collider.set_deferred("disabled", true)
	_set_hurtboxes_enabled(false)
	velocity = Vector3.ZERO

	# The body is thrown the way it was hit, for a fraction of a second, purely
	# as presentation. Before this it was hidden on the same frame it died, so a
	# maul blow sent blood flying in one direction while the target vanished
	# where it stood - which read as an explosion rather than as an impact.
	if config.dummy_death_throw_time > 0.0 and push.length_squared() > 0.0001:
		_death_throw = push.normalized() * config.dummy_death_throw_speed
		_death_throw.y += config.dummy_death_throw_lift
		_death_spin = Vector3(
			randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)
		) * config.dummy_death_spin
		_death_time = config.dummy_death_throw_time
	else:
		_visual.visible = false
	# The body is about to be hidden. Its open wounds finish out in world space
	# instead of vanishing with it, so a kill keeps bleeding for a moment.
	var blood := BloodSystem.find(get_tree())
	if blood != null and _reservoir != null:
		for w in _reservoir.wounds:
			blood.add_remnant(w, global_position + Vector3.UP * 1.0)
		_reservoir.wounds.clear()
	Sfx.play_3d(&"death", global_position, randf_range(0.9, 1.05), -4.0)
	_respawn_after(config.dummy_respawn_delay)


## Carries the corpse visual along the blow and then retires it. Local to the
## Visual node, so nothing physical moves and nothing can be hit.
func _advance_death_throw(delta: float) -> void:
	_death_time -= delta
	if _death_time <= 0.0:
		_visual.visible = false
		_visual.position = Vector3.ZERO
		_visual.rotation = Vector3.ZERO
		_death_throw = Vector3.ZERO
		return
	_death_throw.y -= config.dummy_gravity * delta
	# global_basis.inverse() keeps the throw world-aligned even though the
	# offset is applied in the body's local space.
	_visual.position += (global_basis.inverse() * _death_throw) * delta
	_visual.rotation += _death_spin * delta
	# Sink away rather than popping out of existence.
	var t: float = clampf(_death_time / maxf(config.dummy_death_throw_time, 0.001), 0.0, 1.0)
	_visual.scale = Vector3.ONE * lerpf(0.55, 1.0, t)


## Death gore now comes from BloodSystem: the weapon reports the kill and the
## blood profile decides what it looks like. The old runtime-allocated rigid
## body fragments are gone, which also removes the only place this scene
## created nodes while playing.
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
	_visual.position = Vector3.ZERO
	_visual.scale = Vector3.ONE
	_death_time = 0.0
	_death_throw = Vector3.ZERO
	_visual.visible = true
	_collider.set_deferred("disabled", false)
	_set_hurtboxes_enabled(true)
	_alive = true
	if _reservoir != null:
		_reservoir.refill()
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


## Duck-typed: this is how a Hurtbox finds the body's material store.
func blood_reservoir() -> BloodReservoir:
	return _reservoir


## Immediate respawn, for the Blood Lab reset. Bypasses the timer so the four
## comparison kills can be repeated without waiting.
func force_respawn() -> void:
	global_position = _spawn_position
	velocity = Vector3.ZERO
	_health = config.dummy_max_health
	_lean = Vector3.ZERO
	_visual.rotation = Vector3.ZERO
	_visual.position = Vector3.ZERO
	_visual.scale = Vector3.ONE
	_death_time = 0.0
	_death_throw = Vector3.ZERO
	_visual.visible = true
	_collider.set_deferred("disabled", false)
	_set_hurtboxes_enabled(true)
	_alive = true
	if _reservoir != null:
		_reservoir.refill()
	_refresh_tint()
