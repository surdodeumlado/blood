class_name ReservoirConfig
extends Resource

## How much material a body gives up, per event. The whole mass model lives in
## one .tres so that "a maul kill is catastrophic and a pistol graze is not" is
## a number you can tune, not a constant buried in a weapon.
##
## Units are stylised and normalised: a full body is blood 1.0 / tissue 1.0.
## Nothing here is physiological and nothing should try to be.

@export_group("Capacity")
## A full body. Every draw below is a fraction of this.
@export var max_blood := 1.0
@export var max_tissue := 1.0
## A dead body may keep giving material up to this fraction of its capacity,
## which is what pays for post-mortem hits and residual leakage.
@export_range(0.0, 1.0) var death_release_allowance := 0.35

@export_group("Non-lethal draw")
## Fraction of REMAINING blood a normal wounding hit takes.
@export_range(0.0, 1.0) var hit_blood_fraction := 0.13
## Multiplier when the wound is in the head.
@export var head_multiplier := 2.4
## Multiplier for limbs. Below 1: less meat.
@export var limb_multiplier := 0.65
## Tissue released by a non-lethal hit, as a fraction of the blood drawn.
@export_range(0.0, 2.0) var hit_tissue_ratio := 0.12

@export_group("Killing blow")
## Fraction of REMAINING blood a kill releases at once. High on purpose: a kill
## is the moment the body stops holding anything back.
@export_range(0.0, 1.0) var kill_blood_fraction := 0.78
## Tissue released by a kill, as a fraction of the blood released.
@export_range(0.0, 3.0) var kill_tissue_ratio := 0.55
## A headshot kill is the catastrophic case.
@export var kill_head_multiplier := 1.55
## How hard overkill damage pushes the release up.
@export_range(0.0, 3.0) var overkill_influence := 0.9
## How hard impact energy pushes the release up.
@export_range(0.0, 3.0) var energy_influence := 0.8

@export_group("Family draw multipliers")
## Per-family scaling on top of everything above, indexed by DamageType. This is
## where "the maul is a flagship event and the dagger is a cut" is expressed.
@export var ballistic_scale := 1.0
@export var slashing_scale := 1.15
@export var piercing_scale := 0.6
@export var blunt_scale := 1.85
@export var high_energy_scale := 2.6

@export_group("Wounds")
## Severity a non-lethal hit opens, per family. 0 opens no wound at all.
@export_range(0.0, 1.0) var wound_severity_ballistic := 0.35
@export_range(0.0, 1.0) var wound_severity_slashing := 0.85
@export_range(0.0, 1.0) var wound_severity_piercing := 0.5
@export_range(0.0, 1.0) var wound_severity_blunt := 0.4
@export_range(0.0, 1.0) var wound_severity_high_energy := 0.6
## Blood a wound of severity 1.0 will leak over its whole life.
@export var wound_reserve := 0.22
## Seconds a wound of severity 1.0 stays open.
@export var wound_lifetime := 9.0
## Seconds between discrete drip releases. Wounds must never emit per frame.
@export var wound_drip_interval := 0.22
## Most wounds one body may carry. Older ones are replaced.
@export var max_wounds := 4

@export_group("Death remnant")
## A lethal blow leaves a world-space remnant that keeps leaking briefly, so a
## catastrophic kill does not stop dead the instant the corpse is hidden.
@export var remnant_severity := 0.9
@export var remnant_lifetime := 3.5
@export var remnant_reserve := 0.16


## Per-family multiplier, kept as a function so the .tres stays flat and
## readable rather than becoming an array nobody can edit by hand.
func family_scale(family: BloodTypes.DamageType) -> float:
	match family:
		BloodTypes.DamageType.SLASHING:
			return slashing_scale
		BloodTypes.DamageType.PIERCING:
			return piercing_scale
		BloodTypes.DamageType.BLUNT:
			return blunt_scale
		BloodTypes.DamageType.HIGH_ENERGY:
			return high_energy_scale
		_:
			return ballistic_scale


func wound_severity_for(family: BloodTypes.DamageType) -> float:
	match family:
		BloodTypes.DamageType.SLASHING:
			return wound_severity_slashing
		BloodTypes.DamageType.PIERCING:
			return wound_severity_piercing
		BloodTypes.DamageType.BLUNT:
			return wound_severity_blunt
		BloodTypes.DamageType.HIGH_ENERGY:
			return wound_severity_high_energy
		_:
			return wound_severity_ballistic


## What mixture of solid material a family throws. Returns weights over
## BloodTypes.Tissue: FLESH, FAT, DARK_TISSUE, THICK_BLOOD.
##
## This is the table that stops every family looking like the same red burst:
## a bullet is nearly pure blood, a maul throws pale fat among dark tissue.
func tissue_mix_for(family: BloodTypes.DamageType) -> PackedFloat32Array:
	match family:
		BloodTypes.DamageType.SLASHING:
			return PackedFloat32Array([0.62, 0.10, 0.06, 0.22])
		BloodTypes.DamageType.PIERCING:
			return PackedFloat32Array([0.55, 0.05, 0.10, 0.30])
		BloodTypes.DamageType.BLUNT:
			return PackedFloat32Array([0.40, 0.20, 0.24, 0.16])
		BloodTypes.DamageType.HIGH_ENERGY:
			return PackedFloat32Array([0.38, 0.16, 0.30, 0.16])
		_:
			return PackedFloat32Array([0.70, 0.04, 0.06, 0.20])
