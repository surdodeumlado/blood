class_name BloodRelease
extends RefCounted

## ONE withdrawal of biological material from ONE body, at one instant.
##
## This is the Phase 2 replacement for "spawn N particles". A weapon no longer
## says how many of anything to make; the victim's BloodReservoir decides how
## much material actually left the body, and THIS object is the snapshot of that
## decision. Every visual layer - mist, beads, droplets, tissue, chunks, stains -
## derives its own output from the same release, which is what stops four
## layers inventing four unrelated geometries for the same wound.
##
## It is a SNAPSHOT and nothing else. Persistent state (how much blood the body
## has left, which wounds are open) lives on the reservoir, never here.
##
## Mass is a stylised normalised unit, not litres. 1.0 is "an entire dummy's
## worth of blood". A hand cannon body shot is a few hundredths; a grenade kill
## is most of the body at once.

## The geometry contract from Phase 1. Position, attack direction, penetration
## direction, surface normal, swing plane, explosion direction - all world space,
## all with one documented sign each. Patterns read the frame from here.
var context: BloodContext

## How much BLOOD this release is worth, in reservoir units.
var blood_mass := 0.0
## How much solid TISSUE came with it. Zero for most non-lethal hits.
var tissue_mass := 0.0

## Normalised mixture over BloodTypes.Tissue, summing to ~1.0 when tissue_mass
## is non-zero. This is what makes a maul kill throw pale fat grains and a
## bullet wound not.
var tissue_mix: PackedFloat32Array = PackedFloat32Array([1.0, 0.0, 0.0, 0.0])

## 0 when this release opened no lasting wound. Otherwise roughly "how badly",
## which drives drip rate and how long the wound keeps leaking.
var wound_severity := 0.0

## True when this release came from a wound dripping rather than from the blow
## itself. Patterns use it to stay small and vertical instead of re-firing the
## whole signature every drip.
var is_residual := false

## Set by BloodSystem for telemetry correlation. Matches BloodContext.event_id.
var event_id := 0


static func make(ctx: BloodContext, blood: float, tissue := 0.0) -> BloodRelease:
	var r := BloodRelease.new()
	r.context = ctx
	r.blood_mass = maxf(blood, 0.0)
	r.tissue_mass = maxf(tissue, 0.0)
	return r


func family() -> BloodTypes.DamageType:
	return context.damage_type if context != null else BloodTypes.DamageType.BALLISTIC


func position_ws() -> Vector3:
	return context.position_ws if context != null else Vector3.ZERO


func is_kill() -> bool:
	return context != null and context.is_kill


func energy() -> float:
	return context.energy if context != null else 1.0


## Total material, used for the coarse "how big was this event" decisions like
## how far the pattern should reach.
func total_mass() -> float:
	return blood_mass + tissue_mass


## How much of the tissue budget belongs to one category.
func tissue_share(category: BloodTypes.Tissue) -> float:
	var i := int(category)
	if i < 0 or i >= tissue_mix.size():
		return 0.0
	return tissue_mass * tissue_mix[i]


func describe() -> String:
	return (
		"#%d %s blood %.3f tissue %.3f wound %.2f%s"
		% [
			event_id,
			BloodTypes.DamageType.keys()[int(family())],
			blood_mass,
			tissue_mass,
			wound_severity,
			" RESIDUAL" if is_residual else "",
		]
	)
