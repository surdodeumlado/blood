class_name BloodPattern
extends RefCounted

## How ONE impact family throws material. Not "the same emitter with different
## numbers" - these subclasses generate fundamentally different geometry.
##
## The brief is explicit about this and it is the whole reason Phase 1 failed
## its playtest: Phase 1 made every family sample a cone around an axis and then
## varied count, speed and spread. Four cones with different widths read as four
## slightly different red explosions, because a cone is a cone.
##
## So:
##     BALLISTIC  a narrow TRACK through the body        (axial, 1-D-ish)
##     SLASHING   a FAN swept through the swing plane    (planar, 1-D arc)
##     BLUNT      a broad SHELL around the momentum axis (solid angle)
##     EXPLOSIVE  MULTI-ORIGIN radial rupture            (many sources)
##
## Those are four different shapes of thing, not four settings.
##
## ZERO ALLOCATION. A catastrophic event samples this hundreds of times per
## frame, so sample() writes into fields on the pattern object instead of
## returning a Dictionary. Read out_* immediately after calling sample().

## Filled in by sample().
var out_dir := Vector3.FORWARD
## Multiplier on the layer's base speed. Patterns use this to make some material
## genuinely travel and the rest stay local.
var out_speed := 1.0
## Offset from the wound, in world space. This is how a pattern becomes a LINE
## or an ARC or a CLOUD rather than a point source.
var out_origin := Vector3.ZERO
## Multiplier on the layer's base size.
var out_size := 1.0
## How stretched the element is along its own travel. Slashing pushes this hard.
var out_stretch := 1.0

## Which material is being sampled, when the caller knows. Set immediately
## before sample() and read by patterns that make heavy material behave
## differently from mist. -1 means "plain blood".
var material_class := -1

var _frame := Basis.IDENTITY
var _release: BloodRelease
var _rng: RandomNumberGenerator


## Called once per event before any sample(). Subclasses precompute whatever the
## whole event shares - sub-origins, arc extents, contact discs.
func begin(release: BloodRelease, frame: Basis, rng: RandomNumberGenerator) -> void:
	_release = release
	_frame = frame
	_rng = rng
	_on_begin()


func _on_begin() -> void:
	pass


## Produce one representative for `layer`. `u` is that representative's index
## fraction through the burst (0..1), which lets a pattern give a burst
## structure - a leading edge, a dense core, a trailing spray - instead of
## treating every element as an independent dice roll.
func sample(_layer: BloodTypes.Layer, _u: float) -> void:
	out_dir = _frame.z
	out_speed = 1.0
	out_origin = Vector3.ZERO
	out_size = 1.0
	out_stretch = 1.0


func frame() -> Basis:
	return _frame


## Uniform point on a spherical cap around `axis`, sampling cos(theta) so the
## material fills the cone's VOLUME. `concentration` above 1 packs toward the
## axis. This is the Phase 1 sampler and it stays correct - it is just no longer
## the ONLY shape available.
func cone(axis: Vector3, frame_: Basis, half_angle_deg: float, concentration := 1.0) -> Vector3:
	var cos_max := cos(deg_to_rad(clampf(half_angle_deg, 0.0, 180.0)))
	var u := pow(_rng.randf(), 1.0 / maxf(concentration, 0.05))
	var cos_theta: float = lerpf(cos_max, 1.0, u)
	var sin_theta := sqrt(maxf(1.0 - cos_theta * cos_theta, 0.0))
	var azimuth := _rng.randf() * TAU
	return (
		axis * cos_theta
		+ frame_.x * (sin_theta * cos(azimuth))
		+ frame_.y * (sin_theta * sin(azimuth))
	).normalized()


func random_unit() -> Vector3:
	return Vector3(
		_rng.randfn(0.0, 1.0), _rng.randfn(0.0, 1.0), _rng.randfn(0.0, 1.0)
	).normalized()


## Factory. One place that knows which family gets which geometry.
static func for_family(family: BloodTypes.DamageType) -> BloodPattern:
	match family:
		BloodTypes.DamageType.SLASHING:
			return SlashingPattern.new()
		BloodTypes.DamageType.PIERCING:
			# A thrust is a ballistic track with a tighter angle; the profile
			# supplies the narrower numbers.
			return BallisticPattern.new()
		BloodTypes.DamageType.BLUNT:
			return BluntPattern.new()
		BloodTypes.DamageType.HIGH_ENERGY:
			return ExplosivePattern.new()
		_:
			return BallisticPattern.new()
