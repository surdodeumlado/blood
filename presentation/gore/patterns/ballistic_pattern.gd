class_name BallisticPattern
extends BloodPattern

## A DIRECTIONAL PENETRATION EVENT.
##
##     attacker  ────►  [victim]  ══════════════►  forward plume
##                         ╲
##                          ╲ small back spatter
##
## The defining structure is a TRACK, not a ball: material is born along the
## line the projectile took through the body and leaves almost entirely along
## that same line. Three structural parts, deliberately not one cone:
##
##   CORE     a very tight, very fast spine straight down the penetration axis.
##            This is the part that reaches the far wall and makes the pattern
##            recognisable as a gunshot from across the room.
##   PLUME    a dense forward cone wrapped around the core, wider and slower.
##   BACK     a sparse, wide, slow lobe toward the shooter.
##
## Origins are jittered ALONG the axis rather than in a ball, so the source
## reads as a wound channel.

## Fraction of forward material that belongs to the tight fast core.
const CORE_FRACTION := 0.3
const CORE_HALF_ANGLE := 4.0
const CORE_SPEED := 2.4
const PLUME_HALF_ANGLE := 26.0
const PLUME_CONCENTRATION := 1.9
const BACK_HALF_ANGLE := 62.0
const BACK_SPEED := 0.4

var _back_axis := Vector3.BACK
var _back_frame := Basis.IDENTITY
var _back_fraction := 0.18
## Half-length of the wound channel the material is born along.
var _channel := 0.18


func _on_begin() -> void:
	var ctx := _release.context
	_back_axis = ctx.victim_to_attacker_ws()
	_back_frame = _basis_around(_back_axis)
	# A headshot blows a bigger channel than a torso hit.
	_channel = 0.14 + 0.5 * _release.total_mass()
	_back_fraction = 0.18


func _basis_around(axis: Vector3) -> Basis:
	var f := axis.normalized() if axis.length_squared() > 0.0001 else Vector3.FORWARD
	var reference := Vector3.UP if absf(f.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var right := f.cross(reference).normalized()
	return Basis(right, right.cross(f).normalized(), f)


func sample(layer: BloodTypes.Layer, u: float) -> void:
	out_stretch = 2.4
	out_size = 1.0

	# --- Back spatter. Sparse, wide, slow, toward the shooter.
	if _rng.randf() < _back_fraction:
		out_dir = cone(_back_axis, _back_frame, BACK_HALF_ANGLE, 1.0)
		out_speed = BACK_SPEED * _rng.randf_range(0.6, 1.2)
		out_origin = _frame.z * _rng.randf_range(-_channel, 0.0)
		out_size = 1.25
		out_stretch = 1.6
		return

	var axis := _frame.z

	# --- Core spine. Tight and fast: this is the part that travels.
	# Weighted toward the START of the burst so the fastest material leads.
	var core := u < CORE_FRACTION
	if core:
		out_dir = cone(axis, _frame, CORE_HALF_ANGLE, 3.0)
		out_speed = CORE_SPEED * _rng.randf_range(0.85, 1.3)
		out_size = 0.85 if layer == BloodTypes.Layer.MICRO else 1.1
		out_stretch = 4.0
		# Born anywhere along the exit half of the channel.
		out_origin = axis * _rng.randf_range(0.0, _channel)
		return

	# --- Forward plume. Dense, still clearly forward.
	out_dir = cone(axis, _frame, PLUME_HALF_ANGLE, PLUME_CONCENTRATION)
	out_speed = _rng.randf_range(0.75, 1.45)
	# Along the channel, biased forward: more material leaves the exit side.
	out_origin = axis * _rng.randf_range(-_channel * 0.35, _channel)
	# Fine mist sits closest to the wound; heavier material carries.
	if layer == BloodTypes.Layer.MICRO:
		out_speed *= 0.8
		out_size = 0.8
	elif layer == BloodTypes.Layer.MEDIUM:
		out_speed *= 1.25
		out_size = 1.15
