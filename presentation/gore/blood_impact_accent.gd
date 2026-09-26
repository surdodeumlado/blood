class_name BloodImpactAccent
extends RefCounted
## Presentation only: no parcel mass, no collisions, no stain mutation.
## One fixed MultiMesh allocated at initialization, never one node per impact.
var layer: BloodMultiMeshLayer
var settings: BloodStabilitySettings
var material: ShaderMaterial
var slots := PackedInt32Array()
var expires := PackedFloat64Array()
var events := PackedInt64Array()
var count := 0
var peak := 0
var admitted := 0
var rejected := 0
var clock := 0.0
var frame := -1
var used := 0
var last_irregularity := -1.0

func setup(parent: Node3D, config: BloodStabilitySettings) -> void:
	if layer != null: return
	settings = config
	var capacity := clampi(config.splash_capacity, 1, 128)
	slots.resize(capacity); expires.resize(capacity); events.resize(capacity)
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	material = ShaderMaterial.new()
	material.shader = preload("res://presentation/gore/blood_impact_accent.gdshader")
	layer = BloodMultiMeshLayer.new()
	parent.add_child(layer)
	layer.setup(mesh, material, capacity)

func advance(delta: float) -> void:
	clock += delta
	if count > 0: material.set_shader_parameter("accent_clock", clock)
	var i := count - 1
	while i >= 0:
		if clock >= expires[i]:
			layer.release(slots[i])
			count -= 1
			slots[i] = slots[count]; expires[i] = expires[count]; events[i] = events[count]
			slots[count] = -1; expires[count] = 0.0; events[count] = -1
		i -= 1

static func eligible(kind: int, velocity: Vector3, normal: Vector3, weber: float) -> bool:
	if absf(velocity.dot(normal)) < 0.7: return false
	return kind >= BloodFluidModel.Liquid.MEDIUM or (kind == BloodFluidModel.Liquid.SMALL and weber >= 180)

func submit(pos: Vector3, normal: Vector3, velocity: Vector3, kind: int, diameter: float, weber: float, color: Color, event_id: int) -> void:
	if not settings.rain_enabled or not eligible(kind, velocity, normal, weber): return
	var current := Engine.get_process_frames()
	if current != frame: frame = current; used = 0
	if used >= settings.splashes_per_frame or count >= slots.size(): rejected += 1; return
	var slot := layer.acquire(false)
	if slot < 0: rejected += 1; return
	var tangent := velocity.slide(normal)
	var incidence := absf(velocity.normalized().dot(normal))
	if tangent.length_squared() < 0.0001: tangent = normal.cross(Vector3.RIGHT if absf(normal.y) > 0.9 else Vector3.UP)
	tangent = tangent.normalized()
	var width := clampf(diameter * 20.0 + sqrt(maxf(weber, 0.0)) * 0.001, 0.035, settings.splash_max_width_m)
	var basis := Basis(tangent * width, normal.cross(tangent) * width * lerpf(0.5, 1.0, incidence), normal)
	var duration := 0.095 if kind >= BloodFluidModel.Liquid.LARGE else 0.065
	basis.x *= settings.rain_splash_scale; basis.y *= settings.rain_splash_scale
	duration *= settings.rain_splash_duration_scale
	if last_irregularity != settings.rain_splash_irregularity:
		last_irregularity = settings.rain_splash_irregularity
		material.set_shader_parameter("irregularity", last_irregularity)
	if settings.blood_rain_debug_extreme:
		basis.x *= 4.0; basis.y *= 4.0
		duration = 0.2
	# Every slot state/custom channel is replaced before making it visible.
	layer.write(slot, Transform3D(basis, pos + normal * 0.003), color,
		Color(clock, duration, 1.0 - incidence, float(event_id % 11) * 0.37))
	material.set_shader_parameter("accent_clock", clock)
	slots[count] = slot; expires[count] = clock + duration; events[count] = event_id
	count += 1; used += 1; admitted += 1; peak = maxi(peak, count)

func clear() -> void:
	while count > 0:
		count -= 1
		layer.release(slots[count])
	frame = -1; used = 0
	expires.fill(0.0); events.fill(-1); slots.fill(-1)
