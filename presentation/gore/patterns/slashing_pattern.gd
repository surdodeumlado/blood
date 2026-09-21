class_name SlashingPattern
extends BloodPattern

## A FAN SWEPT THROUGH THE SWING PLANE.
##
##                    ╱╱╱╱╱╱
##        blade  ────────────────►     material fans out along the cut,
##                    ╲╲╲╲╲╲           not outward from a point
##
## The structural difference from every other family: this pattern is
## essentially ONE-DIMENSIONAL. Direction is a rotation of the swing axis about
## the swing-plane NORMAL by an angle swept across the arc, with only a few
## degrees of out-of-plane jitter. It never samples a cone, so it can never come
## out spherical no matter how much material is pushed through it.
##
## The second structural difference is the ORIGIN. Material is born spread ALONG
## the cut line rather than at a point, which is what makes a dagger aftermath
## read as LONG and LATERAL instead of as a burst that happens to be flat.
##
## Blood leaves a blade tangentially, fastest at the leading edge of the arc, so
## `u` maps to position along the sweep and drives speed as well as direction.

## Half-angle of the fan, measured in the swing plane. Deliberately wide.
const ARC_HALF_ANGLE := 72.0
## How far out of the swing plane material is allowed to stray, in degrees.
## Small on purpose - this is what keeps the fan a fan.
const OUT_OF_PLANE := 9.0
## Length of the cut the material is born along, scaled by release mass.
const CUT_LENGTH := 0.85
## Extra speed at the leading edge of the sweep.
const LEADING_EDGE_SPEED := 1.9

var _cut_axis := Vector3.RIGHT
var _cut_length := 0.6
var _plane_normal := Vector3.UP


func _on_begin() -> void:
	# frame.x is the in-plane wide axis and frame.y is the swing-plane normal:
	# BloodSystem._pattern_frame guarantees this whenever the weapon reported a
	# swing plane, which the melee weapon does.
	_plane_normal = _frame.y
	_cut_axis = _frame.x
	_cut_length = CUT_LENGTH * (0.45 + _release.total_mass())


func sample(layer: BloodTypes.Layer, u: float) -> void:
	# --- WHERE along the cut. This is the fan's spine.
	# Spread across [-1, 1] with a little jitter so successive elements do not
	# form a visible comb.
	var t := (u * 2.0 - 1.0) + _rng.randf_range(-0.08, 0.08)
	t = clampf(t, -1.0, 1.0)

	# --- DIRECTION: rotate the swing axis about the plane normal. Pure planar.
	var angle := deg_to_rad(ARC_HALF_ANGLE) * t
	var dir := _frame.z.rotated(_plane_normal, angle)
	# Only a few degrees of thickness, so the sheet stays a sheet.
	var wobble := deg_to_rad(_rng.randf_range(-OUT_OF_PLANE, OUT_OF_PLANE))
	# Heavy material sags out of the plane a little more than mist does.
	if layer == BloodTypes.Layer.LARGE or layer == BloodTypes.Layer.MEDIUM:
		wobble *= 1.8
	out_dir = dir.rotated(_cut_axis, wobble).normalized()

	# --- SPEED: fastest at the leading edge of the sweep, trailing off behind.
	# `t` runs from the start of the arc to its end, so the far end is the tip.
	var edge: float = clampf((t + 1.0) * 0.5, 0.0, 1.0)
	out_speed = lerpf(0.55, LEADING_EDGE_SPEED, edge) * _rng.randf_range(0.8, 1.25)

	# --- ORIGIN: spread ALONG the cut, not around a point.
	out_origin = _cut_axis * (t * _cut_length * 0.5)
	# Plus a thin sliver of depth so the cut has a mouth rather than being a
	# mathematical line.
	out_origin += _frame.z * _rng.randf_range(-0.04, 0.10)
	out_origin += _plane_normal * _rng.randf_range(-0.05, 0.05)

	# --- LOOK: long streaks. A slash stains in lines.
	out_stretch = 5.5
	out_size = 1.0
	if layer == BloodTypes.Layer.MICRO:
		out_size = 0.75
		out_stretch = 6.5
	elif layer == BloodTypes.Layer.MEDIUM:
		out_size = 1.2
		out_speed *= 1.15
	elif layer == BloodTypes.Layer.LARGE:
		out_size = 1.0
		out_speed *= 0.8
		out_stretch = 2.0
