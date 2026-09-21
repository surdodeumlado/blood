class_name Hurtbox
extends Area3D

## A shootable volume, separate from whatever the owner collides with.
##
## Why an Area3D instead of another shape on the body: aim forgiveness and
## physics are different jobs. The dummy should be easy to hit without becoming
## physically fatter, and the head must be able to overlap the torso without
## that overlap shoving the player around.
##
## It forwards take_damage() and hit_zone() to the first ancestor that can take
## damage, so the weapon needs no knowledge of hurtboxes at all: it still just
## duck-types the collider it hit.

const ZONE_BODY := &"body"
const ZONE_HEAD := &"head"

@export var zone: StringName = ZONE_BODY

var _target: Node
var _shape: CollisionShape3D


func _ready() -> void:
	# Never monitors anything; it only exists to be found by ray queries.
	monitoring = false
	monitorable = true
	collision_mask = 0
	_target = get_parent()
	while _target != null and not _target.has_method("take_damage"):
		_target = _target.get_parent()
	if _target == null:
		push_error("Hurtbox %s has no ancestor that can take damage." % name)
	for child in get_children():
		if child is CollisionShape3D:
			_shape = child
			break


## Where the wound actually IS, in world space.
##
## A hurtbox NODE sits at its owner's origin, which is the feet. Melee and
## explosive hits used to report that origin as the impact point, so head blood
## was born on the floor. This samples the collision SHAPE instead: its centre
## is at the real region height, and the returned point is pushed back out along
## the incoming direction so blood starts on the entry surface, not inside it.
func wound_point(from_ws: Vector3, direction_ws: Vector3) -> Vector3:
	if _shape == null or _shape.shape == null:
		return global_position
	var centre := _shape.global_position
	var dir := direction_ws
	if dir.length_squared() > 0.0001:
		dir = dir.normalized()
	elif from_ws.distance_squared_to(centre) > 0.0001:
		dir = (centre - from_ws).normalized()
	else:
		return centre
	return centre - dir * _entry_extent(dir)


## Half-extent of the shape along a world direction. Approximate on purpose:
## this picks a plausible surface point, it is not a collision solver.
func _entry_extent(dir_ws: Vector3) -> float:
	var local: Vector3 = _shape.global_basis.inverse() * dir_ws
	if local.length_squared() < 0.0001:
		return 0.0
	local = local.normalized()
	var shape: Shape3D = _shape.shape
	if shape is SphereShape3D:
		return (shape as SphereShape3D).radius
	if shape is BoxShape3D:
		var half: Vector3 = (shape as BoxShape3D).size * 0.5
		# Distance from the centre to the box surface along `local`.
		var t := INF
		for axis in 3:
			var d: float = absf(local[axis])
			if d > 0.0001:
				t = minf(t, half[axis] / d)
		return 0.0 if is_inf(t) else t
	if shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		var lateral := Vector2(local.x, local.z).length()
		return cap.radius if lateral > 0.5 else cap.height * 0.5
	if shape is CylinderShape3D:
		var cyl := shape as CylinderShape3D
		var side := Vector2(local.x, local.z).length()
		return cyl.radius if side > 0.5 else cyl.height * 0.5
	return 0.0


## The ray reports a shape index; for a hurtbox the zone is the whole point of
## the node, so the index is irrelevant.
func hit_zone(_shape_index: int) -> StringName:
	return zone


## Forwarded so the wound that computed it actually reaches the blood context.
func overkill_ratio() -> float:
	if _target != null and _target.has_method("overkill_ratio"):
		return _target.overkill_ratio()
	return 0.0


## The victim's material store, so a weapon can ask the BODY how much blood a
## hit is worth instead of inventing a number. Same duck-typed route as
## take_damage() and overkill_ratio(): the weapon never knows what a reservoir
## is, it just asks whether this thing has one.
func blood_reservoir() -> BloodReservoir:
	if _target == null:
		return null
	if _target.has_method("blood_reservoir"):
		return _target.blood_reservoir()
	for child in _target.get_children():
		if child is BloodReservoir:
			return child
	return null


## The node that actually owns the damage - used to collapse a body hit and a
## head hit from the same sweep into ONE victim.
func damage_owner() -> Node:
	return _target


## Asked before anything is applied, so a hit on something that cannot be hurt
## produces no damage, no hitmarker and no blood.
func is_damageable() -> bool:
	if _target == null:
		return false
	if _target.has_method("is_damageable"):
		return _target.is_damageable()
	return true


func take_damage(amount: float, point: Vector3, direction: Vector3, _zone := ZONE_BODY) -> bool:
	if _target == null:
		return false
	return _target.take_damage(amount, point, direction, zone)
