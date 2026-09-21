class_name BluntPattern
extends BloodPattern

## BODY MASS THROWN BY A HEAVY HIT.
##
##                     ░░░░░░░░░░░░
##      ══██►   [X]  ░░░░░░░░░░░░░░░░░░░►   momentum trail
##              ▓▓▓   ░░░░░░░░░░░░░░
##           impact site
##
## Two simultaneous zones, which is the whole identity of the family:
##
##   ZONE 1  THE IMPACT SITE. Slow, dense, local. Barely leaves the victim and
##           soaks whatever is directly underneath. This is what makes a maul
##           blow disgusting up close, and it must survive the directional work
##           below - moving all the blood downrange would just make a wide
##           gunshot.
##
##   ZONE 2  THE MOMENTUM TRAIL. A broad, heavy, ASYMMETRIC volume travelling
##           along the swing's momentum axis. Reversing the swing reverses it.
##
## Why this is not a cone (see BallisticPattern for the contrast): a cone has a
## tight axis and uniform lateral spread. This samples a broad random direction
## and then BIASES it along the momentum axis, which gives high directional
## covariance with very large lateral spread - a thrown volume, not a beam.
##
## Momentum is inherited differently per material (Part N): fine mist scatters
## widest, thick blood and tissue carry the blow, and chunks carry it hardest.

## Share of material that stays at the impact site.
const LOCAL_FRACTION := 0.40
const LOCAL_SPEED := 0.16
## Radius of the contact patch material is born across.
const CONTACT_RADIUS := 0.42

## How hard the travelling lobe is pushed along the momentum axis, versus how
## much lateral scatter it keeps. Higher = more directional, wider = broader.
const TRAVEL_FORWARD := 1.35
const TRAVEL_LATERAL := 0.80
const TRAVEL_SPEED_MIN := 0.55
const TRAVEL_SPEED_MAX := 2.3

## Per-material momentum inheritance. 1.0 follows the blow fully; lower values
## scatter more. Indexed by BloodTypes.Tissue, with -1 meaning plain blood.
const MOMENTUM_BLOOD := 1.0
const MOMENTUM := {
	BloodTypes.Tissue.FLESH: 1.15,
	BloodTypes.Tissue.FAT: 0.75,
	BloodTypes.Tissue.DARK_TISSUE: 1.1,
	BloodTypes.Tissue.THICK_BLOOD: 1.45,
}

var _contact := 0.4
var _cloud_radius := 0.5
var _axis := Vector3.FORWARD


func _on_begin() -> void:
	var mass := _release.total_mass()
	_contact = CONTACT_RADIUS * (0.6 + mass)
	_cloud_radius = 0.35 + mass * 1.1
	# The momentum axis. penetration_direction_ws is the swing's real momentum
	# for a melee hit; weapon_velocity_ws overrides it when the weapon reported
	# genuine contact motion, because that is the most direct evidence of where
	# the mass was thrown.
	_axis = _frame.z
	var wv := _release.context.weapon_velocity_ws
	if wv.length_squared() > 0.25:
		_axis = (wv.normalized() * 1.25 + _frame.z * 0.5).normalized()


## How strongly this sample follows the blow.
func _momentum_weight(layer: BloodTypes.Layer) -> float:
	var w: float = MOMENTUM.get(material_class, MOMENTUM_BLOOD)
	match layer:
		BloodTypes.Layer.MICRO:
			# Fine mist is the easiest thing to scatter: it has no momentum of
			# its own worth speaking of.
			w *= 0.55
		BloodTypes.Layer.SMALL:
			w *= 0.8
		BloodTypes.Layer.MEDIUM:
			# Fat travelling droplets are the clearest carriers of the blow.
			w *= 1.25
		BloodTypes.Layer.LARGE:
			w *= 1.35
		_:
			pass
	return w


func sample(layer: BloodTypes.Layer, u: float) -> void:
	out_size = 1.35
	out_stretch = 1.35
	var momentum := _momentum_weight(layer)

	# --- ZONE 1: the impact site. Slow, dense, local, all round the wound.
	# Deliberately NOT directional: this is the mess left where the mass was
	# struck, and it has to stay disgusting whichever way the swing went.
	if u < LOCAL_FRACTION:
		var d := random_unit()
		# Slight forward lean so even the local mess knows about the blow.
		out_dir = (d + _axis * 0.3).normalized()
		out_speed = LOCAL_SPEED * _rng.randf_range(0.4, 2.2)
		out_origin = random_unit() * (_rng.randf() * _cloud_radius)
		out_size = 1.7
		out_stretch = 1.1
		if layer == BloodTypes.Layer.MEDIUM or layer == BloodTypes.Layer.LARGE:
			# Heavy material in the impact zone drops more or less straight
			# down and soaks the floor under the victim.
			out_dir = (out_dir + Vector3.DOWN * 0.9).normalized()
			out_size = 2.0
		return

	# --- ZONE 2: the momentum trail. Broad and heavy, but unmistakably thrown.
	#
	# A wide random direction pushed hard along the momentum axis. The result
	# keeps a large lateral spread (unlike a cone) while almost all of the mass
	# ends up on the swing's side of the victim.
	var scatter := random_unit()
	var lateral := TRAVEL_LATERAL
	if layer == BloodTypes.Layer.LARGE:
		# Chunks scatter least: they carry the blow and then fall.
		lateral *= 0.6
	out_dir = (_axis * (TRAVEL_FORWARD * momentum) + scatter * lateral).normalized()

	# Speed rises with how closely this piece followed the blow: material thrown
	# straight down the momentum axis got the most energy out of the impact.
	var along: float = clampf(out_dir.dot(_axis), 0.0, 1.0)
	out_speed = lerpf(TRAVEL_SPEED_MIN, TRAVEL_SPEED_MAX, along * along)
	out_speed *= _rng.randf_range(0.8, 1.25)

	# Born across the contact patch, and pushed along the axis so the trail
	# starts on the far side of the victim rather than inside it.
	out_origin = (
		_frame.x * _rng.randf_range(-_contact, _contact)
		+ _frame.y * _rng.randf_range(-_contact, _contact)
		+ _axis * _rng.randf_range(0.0, _contact * 1.6)
	)

	match layer:
		BloodTypes.Layer.MICRO:
			out_size = 1.0
			out_speed *= 0.85
		BloodTypes.Layer.MEDIUM:
			# Fat, heavy droplets: the blunt read, and the layer that paints
			# the momentum trail onto the floor.
			out_size = 2.1
			out_stretch = 1.3
		BloodTypes.Layer.LARGE:
			out_size = 1.5
			out_speed *= 1.15
			out_stretch = 1.0
		_:
			pass
