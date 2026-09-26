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

## Surface layout is owned by BloodSurfacePresentation; liquid X is its tail.
## Only fade Z is shared here. Each full write replaces all four channels.
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
var write_count := 0
var instance_api_calls := 0
var commit_count := 0
var write_us := 0
var commit_us := 0
var profile_writes := false
var _buffer := PackedFloat32Array()
var _dirty := false
var _last_commit_frame := -1
## Highest slot ever used, so visible_instance_count can stay tight early on.
var _high_water := 0

## CPU-SIDE MIRROR OF WHAT WAS SUBMITTED, for tests only.
##
## Per-instance MultiMesh data lives in the RenderingServer, and a --headless
## run uses the DUMMY server, which stores none of it: set_instance_transform
## succeeds, and get_instance_transform then returns identity. So a headless
## test cannot read back what it wrote, however correct the write was.
##
## Recording the exact Transform3D and custom data handed to the rendering API
## is the furthest a headless test can honestly follow the value. The PIXELS are
## checked by eye in tests/blood_render_fixture.tscn, which runs windowed.
var record_writes := false
var recorded_xform: Array[Transform3D] = []
var recorded_custom: PackedColorArray = PackedColorArray()
var recorded_color: PackedColorArray = PackedColorArray()


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
	_buffer.resize(capacity * 20) # 3x4 transform + RGBA + custom RGBA.
	for i in capacity:
		# Filled back to front so the first allocations come out in index order,
		# which keeps visible_instance_count small while the pool is cold.
		_free[i] = capacity - 1 - i
		_age[i] = 0
		_active[i] = 0
		# Park every instance at zero scale: an unallocated slot must not draw.
	_free_count = capacity
	_dirty = true


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
	_dirty = true


## Hand a slot back. It goes on the free list, so the NEXT allocation reuses it
## before anything living is touched.
func release(idx: int) -> void:
	if idx < 0 or idx >= capacity or _active[idx] == 0:
		return
	_active[idx] = 0
	_live -= 1
	_age[idx] = 0
	for j in 12: _buffer[idx * 20 + j] = 0.0
	_dirty = true
	if _free_count < capacity:
		_free[_free_count] = idx
		_free_count += 1


func write(idx: int, xform: Transform3D, color: Color, custom := Color(0, 0, 1, 0)) -> void:
	write_count += 1
	var start := Time.get_ticks_usec() if profile_writes else 0
	var k := idx * 20
	var b := xform.basis
	_buffer[k] = b.x.x; _buffer[k + 1] = b.y.x; _buffer[k + 2] = b.z.x; _buffer[k + 3] = xform.origin.x
	_buffer[k + 4] = b.x.y; _buffer[k + 5] = b.y.y; _buffer[k + 6] = b.z.y; _buffer[k + 7] = xform.origin.y
	_buffer[k + 8] = b.x.z; _buffer[k + 9] = b.y.z; _buffer[k + 10] = b.z.z; _buffer[k + 11] = xform.origin.z
	_buffer[k + 12] = color.r; _buffer[k + 13] = color.g; _buffer[k + 14] = color.b; _buffer[k + 15] = color.a
	_buffer[k + 16] = custom.r; _buffer[k + 17] = custom.g; _buffer[k + 18] = custom.b; _buffer[k + 19] = custom.a
	_dirty = true
	if profile_writes: write_us += Time.get_ticks_usec() - start
	if record_writes:
		recorded_xform[idx] = xform
		recorded_custom[idx] = custom
		recorded_color[idx] = color


## Start mirroring submissions. Test-only: it costs one array write per stain.
func begin_recording() -> void:
	recorded_xform.resize(capacity)
	recorded_custom.resize(capacity)
	recorded_color.resize(capacity)
	record_writes = true


func set_color(idx: int, color: Color) -> void:
	var k := idx * 20 + 12
	_buffer[k] = color.r; _buffer[k + 1] = color.g; _buffer[k + 2] = color.b; _buffer[k + 3] = color.a
	_dirty = true

func set_fade(idx: int, alpha: float) -> void:
	if not is_active(idx): return
	_buffer[idx * 20 + 18] = clampf(alpha, 0.0, 1.0)
	if record_writes: recorded_custom[idx].b = clampf(alpha, 0.0, 1.0)
	_dirty = true

func _process(_delta: float) -> void:
	commit()

func commit() -> void:
	var frame := Engine.get_process_frames()
	if not _dirty or _last_commit_frame == frame: return
	var start := Time.get_ticks_usec() if profile_writes else 0
	multimesh.buffer = _buffer
	multimesh.visible_instance_count = _high_water
	_last_commit_frame = frame
	_dirty = false
	commit_count += 1
	if profile_writes: commit_us += Time.get_ticks_usec() - start


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
	_dirty = true


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
