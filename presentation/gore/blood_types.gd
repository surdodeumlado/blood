class_name BloodTypes
extends RefCounted

## Shared vocabulary for the blood system. Lives in one file so that combat
## code, profiles and presentation all agree without any of them importing each
## other.

## Impact families. A weapon picks one; the matching BloodProfile decides how it
## looks. Deliberately about the KIND of wound, not about the weapon: a pistol,
## a hand cannon and a shotgun are all BALLISTIC and tell themselves apart
## through impact energy and their own profile overrides.
##
## There is no separate EXPLOSIVE entry on purpose. An explosion is HIGH_ENERGY
## with no meaningful attack direction, which the profile already expresses
## through directional_bias near zero and a wide spread. Adding EXPLOSIVE now
## would be a second name for the same parameter set. If explosives later need a
## genuinely different look (misting rather than streaks, say), adding an enum
## entry and a .tres is the cheapest change in this whole system.
enum DamageType {
	BALLISTIC,   ## bullets: fast, narrow, carries on through
	SLASHING,    ## blades: lateral arc, long streaks
	PIERCING,    ## thrusts: tight, concentrated, low volume
	BLUNT,       ## impacts: wide, non-linear, rupture
	HIGH_ENERGY, ## explosives and the supernatural: radial, extreme
}

## Coarse enough to be useful now, specific enough to drive future gore rules.
## The current dummy only reports HEAD and TORSO; LIMB exists so that limb
## hurtboxes (and severing) can be added without touching this contract.
enum BodyRegion {
	TORSO,
	HEAD,
	LIMB,
}

## Reference points for impact energy. Nothing clamps to these exact values -
## they are what the numbers are meant to mean.
const ENERGY_WEAK := 0.5
const ENERGY_NORMAL := 1.0
const ENERGY_HEAVY := 1.5
const ENERGY_EXTREME := 2.0


## How much material one release is worth, split by how it is represented.
##
## This is the Phase 2 idea that replaces "spawn N particles". Combat says how
## much biological material left the body; the rendering layer alone decides how
## many visual and physical representatives that needs. A quality tier may
## change the representative count and may NEVER change the mass.
enum Layer {
	MICRO,    ## fine mist / aerosol. Cheap, abundant, dies near the wound
	SMALL,    ## visible beads. Cheap, many
	MEDIUM,   ## thick droplets and globules. The physical representatives
	LARGE,    ## gore chunks and thick blobs. Few, heavy, persistent
	SURFACE,  ## stains: what the arena remembers
}


## Material variety, not anatomy. A blunt kill throwing pale grains among the
## red is the entire point - it stops gore reading as red sparks.
enum Tissue {
	FLESH,        ## deep red organic, the default meat
	FAT,          ## pale cream-yellow, sparse, unmistakable among the red
	DARK_TISSUE,  ## very dark red-brown, blunt and explosive signature
	THICK_BLOOD,  ## dense near-black clots, heavy trajectories
}


## How a surface receives blood. Deliberately two entries: enough to change the
## read, not enough to become a material simulation.
enum Surface {
	SMOOTH,  ## clean ellipse, few satellites
	ROUGH,   ## irregular edge, more satellites
}


## Development intensity tiers. These scale REPRESENTATION ONLY.
enum Quality {
	LOW,
	HIGH,
	INSANE,
}


## Stain shapes packed into the generated atlas, in atlas order. The surface
## layer picks one per stain and sends its index as per-instance custom data,
## so seven shapes cost one material rather than seven hundred.
enum Stain {
	TINY_DROP,
	MEDIUM_ROUND,
	LARGE_IRREGULAR,
	ELONGATED,
	STREAK,
	CLUSTER,
	POOLED,
}

const STAIN_COUNT := 7
