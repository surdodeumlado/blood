class_name BloodContext
extends RefCounted

## What happened, as described by combat. Nothing in here says anything about
## particles, colours or lifetimes - that is BloodProfile's job.
##
## EVERY direction in this class is WORLD SPACE and normalised, and every one of
## them has a single documented sign. The previous version carried one ambiguous
## `direction` that different call sites meant different things by, which is how
## the forward lobe ended up being clipped away against the entry normal.
##
##                    attack_direction_ws
##        attacker  ───────────────────►  [victim]  ───────────────────►
##                                                  penetration_direction_ws
##                        ◄─────────
##                  surface_normal_ws (points back OUT toward the attacker
##                  at the entry wound)
##
## Read that diagram before changing any sign in this file.

## Which impact family. Selects the BloodProfile.
var damage_type: BloodTypes.DamageType = BloodTypes.DamageType.BALLISTIC
## Normalised intensity. 1.0 is a standard hit; see BloodTypes.ENERGY_*.
var energy := 1.0

## The wound. A REAL sampled contact point on the victim, at the height of the
## region that was actually hit - never the victim's root or a hurtbox node
## origin, both of which sit at the feet.
var position_ws := Vector3.ZERO

## Direction the attack was TRAVELLING, pointing from attacker toward victim.
## Zero when the attack has no meaningful direction (an explosion underfoot).
var attack_direction_ws := Vector3.ZERO

## Where transferred energy CONTINUES after entry: through and out of the
## victim. Defaults to attack_direction_ws, which is what a bullet does. A
## weapon that deflects energy elsewhere may override it.
var penetration_direction_ws := Vector3.ZERO

## Outward geometric normal at the contact surface. At an entry wound this
## points back toward the attacker, which is the opposite hemisphere from
## penetration_direction_ws. Zero when unknown.
var surface_normal_ws := Vector3.ZERO

## World velocity of the weapon's contact point, when the weapon was moving.
var weapon_velocity_ws := Vector3.ZERO

## Normal of the plane a melee swing travelled in. Slashing patterns fan out
## inside this plane instead of guessing from the camera.
var swing_plane_normal_ws := Vector3.ZERO

## Explosion centre toward this victim's sample point. Per victim, never a
## single shared direction for the whole blast.
var explosion_direction_ws := Vector3.ZERO

## Filled in by the pattern once it has chosen. Diagnostics and tests read it.
var blood_primary_axis_ws := Vector3.ZERO

var body_region: BloodTypes.BodyRegion = BloodTypes.BodyRegion.TORSO
var is_headshot := false
var is_kill := false
## Damage beyond what was needed to kill, as a fraction of max health.
var overkill := 0.0

## Only true for blood that came off a hard surface rather than out of a body:
## that material may not be fired back into the surface it landed on. A wound
## has no such restriction, which is exactly why forward spatter is allowed to
## continue away from the entry normal.
var clip_to_surface := false

## Set by BloodSystem. Purely for telemetry correlation.
var event_id := 0


static func make(
	damage_type_: BloodTypes.DamageType,
	position: Vector3,
	attack_direction: Vector3,
	region: BloodTypes.BodyRegion,
	energy_ := 1.0
) -> BloodContext:
	var ctx := BloodContext.new()
	ctx.damage_type = damage_type_
	ctx.position_ws = position
	ctx.attack_direction_ws = _safe_dir(attack_direction)
	# A bullet keeps going the way it was going. Anything else overrides this.
	ctx.penetration_direction_ws = ctx.attack_direction_ws
	ctx.body_region = region
	ctx.is_headshot = region == BloodTypes.BodyRegion.HEAD
	ctx.energy = energy_
	return ctx


static func _safe_dir(v: Vector3) -> Vector3:
	return v.normalized() if v.length_squared() > 0.0001 else Vector3.ZERO


## The direction blood is mainly thrown in. Patterns start here.
func primary_axis() -> Vector3:
	if explosion_direction_ws.length_squared() > 0.0001:
		return explosion_direction_ws
	if penetration_direction_ws.length_squared() > 0.0001:
		return penetration_direction_ws
	if attack_direction_ws.length_squared() > 0.0001:
		return attack_direction_ws
	if surface_normal_ws.length_squared() > 0.0001:
		return surface_normal_ws
	return Vector3.UP


## Backspatter travels back toward whoever delivered the hit.
func victim_to_attacker_ws() -> Vector3:
	if attack_direction_ws.length_squared() > 0.0001:
		return -attack_direction_ws
	if surface_normal_ws.length_squared() > 0.0001:
		return surface_normal_ws
	return Vector3.UP


func describe() -> String:
	return (
		"#%d %s %s energy %.2f kill %s origin %.2v axis %.2v attack %.2v normal %.2v"
		% [
			event_id,
			BloodTypes.DamageType.keys()[int(damage_type)],
			BloodTypes.BodyRegion.keys()[int(body_region)],
			energy, is_kill, position_ws, blood_primary_axis_ws,
			attack_direction_ws, surface_normal_ws,
		]
	)
