class_name BloodSurfaceSupport
extends RefCounted
## Conservative planar footprint support. Unsupported quads are shrunk or rejected.
## Collider identity + full transform are retained; moved/deleted owners retire marks.
# Keep the helper independent of BloodSystem's script resource to avoid a
# circular script-resource dependency; the owner clears this link on exit.
var blood: Node3D
var anchors: Dictionary = {}
var owners: Dictionary = {}
var rejected := 0
var shrunk := 0
var last_samples: Array[Vector3] = []
var last_hit: Dictionary = {}

func contact(pos: Vector3, normal: Vector3) -> Dictionary:
	var s: BloodStabilitySettings = blood.settings.stability
	if not blood.can_query(): return {}
	blood._ray.from = pos + normal * s.support_probe_m
	blood._ray.to = pos - normal * s.support_probe_m
	var hit: Dictionary = blood._query()
	if hit.is_empty() or (hit.normal as Vector3).dot(normal) < s.support_normal_dot: return {}
	return hit

func fit(xform: Transform3D, offset: float) -> Dictionary:
	var s: BloodStabilitySettings = blood.settings.stability
	var n := xform.basis.z.normalized()
	var pos := xform.origin - n * offset
	var hit := contact(pos, n)
	if hit.is_empty(): rejected += 1; return {}
	pos = hit.position
	n = hit.normal
	var collider_id: int = hit.collider_id
	# Preserve the requested tangent axes while snapping to the measured plane.
	var x := xform.basis.x.slide(n).normalized() * xform.basis.x.length()
	var y := n.cross(x.normalized()) * xform.basis.y.length()
	var factor := 1.0
	last_samples.clear()
	for attempt in s.max_support_shrinks + 1:
		var supported := true
		for uv in [Vector2(-0.5,-0.5), Vector2(0,-0.5), Vector2(0.5,-0.5), Vector2(-0.5,0), Vector2(0.5,0), Vector2(-0.5,0.5), Vector2(0,0.5), Vector2(0.5,0.5)]:
			var sample: Vector3 = pos + (x * uv.x + y * uv.y) * factor
			if blood.settings.debug_patterns: last_samples.append(sample)
			var support := contact(sample, n)
			if support.is_empty() or int(support.collider_id) != collider_id or absf((support.position as Vector3).distance_to(sample)) > s.support_plane_tolerance_m:
				supported = false
				break
		if supported:
			last_hit = hit
			if factor < 1: shrunk += 1
			return {"transform": Transform3D(Basis(x * factor, y * factor, n), pos + n * offset), "hit": hit, "scale": factor}
		factor *= 0.55
	rejected += 1
	return {}

func own(slot: int, fit_result: Dictionary) -> void:
	var hit: Dictionary = fit_result.hit
	var collider := hit.collider as Node3D
	if not is_instance_valid(collider): return
	var id: int = collider.get_instance_id()
	if anchors.has(slot) and int(anchors[slot].owner_id) != id: forget(slot)
	anchors[slot] = {"owner_id": id, "surface_hit_position_ws": hit.position, "surface_normal_ws": hit.normal,
		"tangent_frame": (fit_result.transform as Transform3D).basis, "surface_class": blood.surface_response(collider, hit.normal).label,
		"owner_transform": collider.global_transform, "transform": fit_result.transform}
	if not owners.has(id):
		owners[id] = {"ref": weakref(collider), "transform": collider.global_transform, "slots": {},
			"signature": _shape_signature(collider)}
	owners[id].slots[slot] = true

func _shape_signature(owner: Node3D) -> int:
	var state: Array = []
	for child in owner.find_children("*", "CollisionShape3D", true, false):
		var collision := child as CollisionShape3D
		var shape := collision.shape
		# Poll value data, not callbacks into a RefCounted observer during world
		# destruction. Shapes/colliders retain no strong reference from blood.
		var geometry: Variant = null
		if shape is BoxShape3D: geometry = shape.size
		elif shape is SphereShape3D: geometry = shape.radius
		elif shape is CapsuleShape3D or shape is CylinderShape3D:
			geometry = Vector2(shape.get("radius"), shape.get("height"))
		elif shape is ConvexPolygonShape3D: geometry = hash(shape.points)
		elif shape is ConcavePolygonShape3D: geometry = hash(shape.get_faces())
		elif shape is HeightMapShape3D: geometry = hash(shape.map_data)
		elif shape is WorldBoundaryShape3D: geometry = shape.plane
		state.append([collision.get_instance_id(), collision.global_transform, collision.disabled,
			shape.get_rid() if shape != null else RID(), geometry])
	return hash(state)

func _forget_owner(id: int) -> void:
	owners.erase(id)

func forget(slot: int) -> void:
	if not anchors.has(slot): return
	var id: int = anchors[slot].owner_id
	if owners.has(id):
		owners[id].slots.erase(slot)
		if owners[id].slots.is_empty(): _forget_owner(id)
	anchors.erase(slot)

func validate_owners() -> void:
	for id in owners.keys():
		var owner := (owners[id].ref as WeakRef).get_ref() as Node3D
		if is_instance_valid(owner) and owner.is_inside_tree() and owner.global_transform.is_equal_approx(owners[id].transform) and _shape_signature(owner) == int(owners[id].signature): continue
		# Fail closed on moved/removed geometry; do not leave old world-space ink.
		for slot in owners[id].slots.keys():
			blood._surface.release(slot)
			blood._stain_active[slot] = 0
			blood._forget_stain(slot)
			anchors.erase(slot)
		_forget_owner(id)

func clear() -> void:
	anchors.clear()
	for id in owners.keys(): _forget_owner(id)
