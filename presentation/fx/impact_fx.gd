class_name ImpactFx
extends Node3D

## Pooled, short-lived shot feedback: tracer beams and impact puffs.
##
## Everything is allocated once at _ready and reused forever. Nothing is
## instanced, added or freed while shooting, and the pools are hard-capped, so
## holding fire cannot accumulate objects. Children run top_level so they live
## in world space regardless of where this node is parented.

enum Kind { WORLD, ENEMY, HEAD }

## Headshot puffs read bigger so the kind of hit is obvious at a glance.
const HEAD_SCALE := 1.45

@export var config: CombatConfig

## Last beam drawn, kept so the smoke test can prove the visual tracer ends
## exactly where the gameplay raycast landed. Debug only; nothing reads these.
var last_tracer_from := Vector3.ZERO
var last_tracer_to := Vector3.ZERO

var _tracers: Array[MeshInstance3D] = []
var _tracer_mats: Array[StandardMaterial3D] = []
var _tracer_life: Array[float] = []
var _next_tracer := 0

var _impacts: Array[MeshInstance3D] = []
var _impact_mats: Array[StandardMaterial3D] = []
var _impact_life: Array[float] = []
var _impact_end: Array[float] = []
var _next_impact := 0

var _active := 0


func _ready() -> void:
	if config == null:
		push_error("ImpactFx has no CombatConfig assigned in the scene.")
		return
	for i in config.tracer_pool_size:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(config.tracer_thickness, config.tracer_thickness, 1.0)
		var mat := _fx_material()
		var mi := _fx_instance(mesh, mat)
		_tracers.append(mi)
		_tracer_mats.append(mat)
		_tracer_life.append(0.0)

	for i in config.impact_pool_size:
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 2.0
		mesh.radial_segments = 8
		mesh.rings = 4
		var mat := _fx_material()
		var mi := _fx_instance(mesh, mat)
		_impacts.append(mi)
		_impact_mats.append(mat)
		_impact_life.append(0.0)
		_impact_end.append(config.impact_end_radius)

	set_process(false)


func _process(delta: float) -> void:
	for i in _tracers.size():
		if _tracer_life[i] <= 0.0:
			continue
		_tracer_life[i] -= delta
		if _tracer_life[i] <= 0.0:
			_retire(_tracers[i])
			continue
		var t := _tracer_life[i] / config.tracer_lifetime
		_tracer_mats[i].albedo_color.a = t

	for i in _impacts.size():
		if _impact_life[i] <= 0.0:
			continue
		_impact_life[i] -= delta
		if _impact_life[i] <= 0.0:
			_retire(_impacts[i])
			continue
		var t := _impact_life[i] / config.impact_lifetime
		_impact_mats[i].albedo_color.a = t
		var r: float = lerpf(_impact_end[i], config.impact_start_radius, t)
		_impacts[i].scale = Vector3(r, r, r)

	if _active <= 0:
		set_process(false)


## Draws a beam from the muzzle to the impact point for tracer_lifetime seconds.
func tracer(from: Vector3, to: Vector3) -> void:
	last_tracer_from = from
	last_tracer_to = to
	var dir := to - from
	var length := dir.length()
	if length < 0.05:
		return
	dir /= length
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var idx := _next_tracer
	_next_tracer = (_next_tracer + 1) % _tracers.size()

	var mi := _tracers[idx]
	mi.global_transform = Transform3D(
		Basis.looking_at(dir, up).scaled(Vector3(1.0, 1.0, length)),
		from + dir * (length * 0.5)
	)
	_tracer_mats[idx].albedo_color = config.tracer_color
	if _tracer_life[idx] <= 0.0:
		_active += 1
	_tracer_life[idx] = config.tracer_lifetime
	mi.visible = true
	set_process(true)


## Expanding flash at a hit point. Colour and size tell the player what they hit:
## pale gold on the world, red on a body, big and near-white on a head.
func impact(pos: Vector3, kind: Kind) -> void:
	var idx := _next_impact
	_next_impact = (_next_impact + 1) % _impacts.size()

	var mi := _impacts[idx]
	mi.global_position = pos
	mi.scale = Vector3.ONE * config.impact_start_radius
	_impact_end[idx] = config.impact_end_radius
	match kind:
		Kind.HEAD:
			_impact_mats[idx].albedo_color = config.impact_head_color
			_impact_end[idx] *= HEAD_SCALE
		Kind.ENEMY:
			_impact_mats[idx].albedo_color = config.impact_enemy_color
		_:
			_impact_mats[idx].albedo_color = config.impact_world_color
	if _impact_life[idx] <= 0.0:
		_active += 1
	_impact_life[idx] = config.impact_lifetime
	mi.visible = true
	set_process(true)


# --------------------------------------------------------------------------

func _fx_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	return mat


func _fx_instance(mesh: Mesh, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.visible = false
	add_child(mi)
	return mi


func _retire(mi: MeshInstance3D) -> void:
	mi.visible = false
	_active -= 1
