class_name BloodMultiMeshLayer
extends MultiMeshInstance3D

## One batched layer of blood. Thousands of elements, ONE node, ONE draw call.
##
## This is what makes Phase 2 possible at all. The previous system gave every
## single particle its own MeshInstance3D and its own StandardMaterial3D, which
## is why the whole budget was 850 elements: 850 nodes the engine has to cull,
## transform and submit individually. A MultiMesh keeps one transform buffer on
## the CPU and uploads it as one array, so the cost of the 900th droplet is 12
## floats rather than a scene-tree node.
##
## MultiMesh with per-instance colour and custom data is core Godot rendering
## and works on the Compatibility (GLES3) backend. Nothing here needs Forward+,
## compute shaders or storage buffers.
##
## ALLOCATION POLICY, which is the other half of the Phase 2 brief:
##
##     1. a genuinely free slot
##     2. the oldest RETIRED slot
##     3. eviction of the oldest ACTIVE slot, only when truly full
##
## The old ring allocator did none of this. It advanced one index and wrote over
## whatever was there, so a large event erased blood that had just been emitted
## while hundreds of retired slots sat unused a few indices away. That is why a
## grenade kill could delete its own spray.

## Per-instance CUSTOM_DATA layout, since it is easy to lose track of:
##     x = atlas column      (stain shape / sprite variation)
##     y = atlas row
##     z = fade alpha driver (1.0 fresh, 0.0 gone)
##     w = free
const CUSTOM_SHAPE_X := 0
const CUSTOM_SHAPE_Y := 1
const CUSTOM_FADE := 2

var capacity := 0

## Telemetry. The brief asks for these by name.
var requested := 0
var admitted := 0
var rejected := 0
var recycled := 0
var evicted := 0

var _free: PackedInt32Array = PackedInt32Array()
var _free_count := 0
## Emission order, so "oldest" means oldest rather than "next index along".
var _age: PackedInt64Array = PackedInt64Array()
var _active: PackedByteArray = PackedByteArray()
var _live := 0
var _stamp := 0
## Highest slot ever used, so visible_instance_count can stay tight early on.
var _high_water := 0


func setup(mesh: Mesh, material: Material, slots: int, cast_shadows := false) -> void:
	capacity = maxi(slots, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	multimesh = mm
	material_override = material
	cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	# The layer draws in world space: blood belongs to the arena, never to
	# whatever node happened to emit it.
	top_level = true
	# Nothing is at the origin at rest, and an empty MultiMesh has a degenerate
	# AABB, so give it a generous one rather than let culling blink it out.
	custom_aabb = AABB(Vector3(-250, -50, -250), Vector3(500, 200, 500))

	_free.resize(capacity)
	_age.resize(capacity)
	_active.resize(capacity)
	for i in capacity:
		# Filled back to front so the first allocations come out in index order,
		# which keeps visible_instance_count small while the pool is cold.
		_free[i] = capacity - 1 - i
		_age[i] = 0
		_active[i] = 0
		# Park every instance at zero scale: an unallocated slot must not draw.
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	_free_count = capacity


## Returns a slot index, or -1 when the layer refused the request.
##
## `may_evict` is what separates "this event wants more material" from "this
## event may destroy older material to get it". Persistent layers pass true
## because the arena has to keep accepting blood forever; short-lived airborne
## layers pass false and simply go without, because a mist particle that cannot
## be afforded is not worth deleting a live one for.
func acquire(may_evict := true) -> int:
	requested += 1
	if _free_count > 0:
		_free_count -= 1
		var idx := _free[_free_count]
		_occupy(idx)
		admitted += 1
		return idx
	if not may_evict:
		rejected += 1
		return -1
	# Truly full. Evict the oldest ACTIVE slot - never an arbitrary one.
	var oldest := -1
	var oldest_stamp := 0x7FFFFFFFFFFFFFF
	for i in capacity:
		if _age[i] < oldest_stamp:
			oldest_stamp = _age[i]
			oldest = i
	if oldest < 0:
		rejected += 1
		return -1
	evicted += 1
	admitted += 1
	_occupy(oldest)
	return oldest


func _occupy(idx: int) -> void:
	if _active[idx] == 0:
		_active[idx] = 1
		_live += 1
	else:
		recycled += 1
	_stamp += 1
	_age[idx] = _stamp
	_high_water = maxi(_high_water, idx + 1)
	multimesh.visible_instance_count = _high_water


## Hand a slot back. It goes on the free list, so the NEXT allocation reuses it
## before anything living is touched.
func release(idx: int) -> void:
	if idx < 0 or idx >= capacity or _active[idx] == 0:
		return
	_active[idx] = 0
	_live -= 1
	_age[idx] = 0
	multimesh.set_instance_transform(
		idx, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	)
	if _free_count < capacity:
		_free[_free_count] = idx
		_free_count += 1


func write(idx: int, xform: Transform3D, color: Color, custom := Color(0, 0, 1, 0)) -> void:
	multimesh.set_instance_transform(idx, xform)
	multimesh.set_instance_color(idx, color)
	multimesh.set_instance_custom_data(idx, custom)


func set_color(idx: int, color: Color) -> void:
	multimesh.set_instance_color(idx, color)


func is_active(idx: int) -> bool:
	return idx >= 0 and idx < capacity and _active[idx] == 1


func live() -> int:
	return _live


func free_slots() -> int:
	return _free_count


func clear_all() -> void:
	for i in capacity:
		if _active[i] == 1:
			release(i)
	_high_water = 0
	multimesh.visible_instance_count = 0


func reset_telemetry() -> void:
	requested = 0
	admitted = 0
	rejected = 0
	recycled = 0
	evicted = 0


func telemetry() -> Dictionary:
	return {
		"capacity": capacity,
		"live": _live,
		"free": _free_count,
		"requested": requested,
		"admitted": admitted,
		"rejected": rejected,
		"recycled": recycled,
		"evicted": evicted,
	}
