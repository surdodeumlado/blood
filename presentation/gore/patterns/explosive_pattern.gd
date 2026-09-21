class_name ExplosivePattern
extends BloodPattern

## MULTI-ORIGIN OUTWARD CATASTROPHE.
##
##            ○   ○         each ○ is a separate rupture point on the body;
##         ○   ╲ ╱   ○      material radiates outward from ITS OWN origin,
##            ─ X ─         not from one shared centre
##         ○   ╱ ╲   ○
##            ○   ○
##
## Every other family emits from one place. This one does not, and that is the
## structural difference: the body comes apart at several points at once, and
## each rupture throws material radially outward from where IT is. A single
## radial burst from one point is a red sphere; five overlapping radial bursts
## from points spread across a body is a body being torn apart.
##
## The blast direction still matters - Phase 1 established that each victim gets
## its own outward axis from the explosion centre - so every sub-origin is
## displaced outward along that axis and its material is biased outward too. The
## pattern is chaotic but never symmetric about nothing.
##
## Range is the other signature: this family throws material further than any
## other, which is what gives it the largest environmental footprint.

const SUB_ORIGINS := 6
## How far the rupture points spread across the body.
const BODY_RADIUS := 0.55
## How strongly material follows the blast axis rather than its own radial.
const BLAST_BIAS := 0.55
const SPEED_MIN := 0.9
const SPEED_MAX := 2.6

var _origins: PackedVector3Array = PackedVector3Array()
var _blast := Vector3.UP


func _on_begin() -> void:
	var ctx := _release.context
	_blast = ctx.explosion_direction_ws
	if _blast.length_squared() < 0.0001:
		_blast = ctx.primary_axis()
	if _blast.length_squared() < 0.0001:
		_blast = Vector3.UP
	_blast = _blast.normalized()

	var spread := BODY_RADIUS * (0.6 + _release.total_mass())
	_origins.resize(SUB_ORIGINS)
	for i in SUB_ORIGINS:
		# Scattered across the body, then pushed along the blast axis so the
		# ruptures sit on the side the energy arrived from.
		var p := random_unit() * (spread * _rng.randf_range(0.35, 1.0))
		p += _blast * spread * 0.45
		_origins[i] = p


func sample(layer: BloodTypes.Layer, u: float) -> void:
	# Pick which rupture this element belongs to. Spread across the burst rather
	# than randomly, so every origin gets material even in a small event.
	var which := int(u * SUB_ORIGINS) % SUB_ORIGINS
	var origin: Vector3 = _origins[which]
	out_origin = origin

	# Radial from THIS rupture point, blended toward the blast axis.
	var radial := origin
	if radial.length_squared() < 0.0001:
		radial = random_unit()
	else:
		radial = radial.normalized()
	# Genuine scatter: this is the one family allowed to approach full sphere.
	var scattered := (radial + random_unit() * 0.85).normalized()
	out_dir = (scattered + _blast * BLAST_BIAS).normalized()

	out_speed = _rng.randf_range(SPEED_MIN, SPEED_MAX)
	out_size = 1.2
	out_stretch = 2.2

	match layer:
		BloodTypes.Layer.MICRO:
			out_size = 0.9
			out_speed *= 1.15
			out_stretch = 3.0
		BloodTypes.Layer.MEDIUM:
			# The long-range material that paints distant walls.
			out_size = 1.35
			out_speed *= 1.35
		BloodTypes.Layer.LARGE:
			out_size = 1.3
			out_speed *= 0.95
			out_stretch = 1.0
		_:
			pass
