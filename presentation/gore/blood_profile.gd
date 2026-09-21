class_name BloodProfile
extends Resource

## How one impact family looks. One .tres per DamageType in data/blood/.
##
## This is the reason there is no `if weapon == revolver` anywhere: a weapon
## names a family and an energy, and everything about the resulting spray comes
## from the matching profile. New weapons need no code, only numbers.

## Which family this profile answers for. BloodSystem indexes profiles by this.
@export var damage_type: BloodTypes.DamageType = BloodTypes.DamageType.BALLISTIC

@export_group("Burst")
## Particles for a plain torso hit at energy 1.0, before any multiplier.
@export var burst_amount := 10
## Base size of a spray particle, in metres.
@export var burst_scale := 0.055
## How far the spray is stretched along its own velocity. High values read as
## streaks rather than droplets - what SLASHING wants.
@export var streak_stretch := 2.6
@export var particle_speed_min := 4.0
@export var particle_speed_max := 11.0
@export var particle_lifetime := 0.55

@export_group("Distribution")
## 1.0 = the spray follows the attack direction. 0.0 = an even sphere, which is
## what an explosion or a point-blank rupture wants.
@export_range(0.0, 1.0) var directional_bias := 0.85
## Fraction of the material that ignores the cone and scatters in full 3D.
## Around 0.2-0.3 keeps most of the spray tied to the shot while stopping it
## reading as a straight line. Explosives push this much higher.
@export_range(0.0, 1.0) var radial_scatter_fraction := 0.25
## Random multiplier range applied to every launch speed, so nothing comes out
## in a uniform sheet.
@export var velocity_variance := 0.45
## 1.0 = the spray fires out sideways across the attack instead of along it.
## This is the knob that turns a gunshot cone into a slash arc.
@export_range(0.0, 1.0) var lateral_bias := 0.0
## Half-angle of the spray cone, in degrees. 180 is a full sphere.
@export var spread_angle := 40.0
## How densely the cone packs toward its axis. 1.0 samples the spherical cap
## uniformly (material genuinely fills the cone); above 1.0 biases toward the
## centre. Keep it near 1 - high values are what made every shot read as a
## single line down the aim vector.
@export_range(0.2, 6.0) var spread_concentration := 1.3
## Flattens the cone toward the frame's horizontal axis. 1.0 is a round cone,
## higher squashes it into a fan - which is what a slash wants.
@export_range(1.0, 6.0) var lateral_flatten := 1.0

@export_group("Environment splatter")
## Chance that an event tries to mark nearby geometry at all.
@export_range(0.0, 1.0) var env_splat_chance := 0.9
## Ray casts attempted when it does. Each hit becomes one splat.
@export var env_splat_count := 4
@export var env_splat_size_min := 0.22
@export var env_splat_size_max := 0.6
## How far blood will travel looking for a surface to land on.
@export var env_splat_distance := 4.5
## 1.0 keeps splats round; higher stretches them along the spray direction into
## streaks. Slashing and ballistic want streaks; blunt wants blots.
@export var env_streak_ratio := 1.7
@export var env_splat_lifetime := 26.0

@export_group("Scaling")
## Applied when the wound is in the HEAD region.
@export var headshot_multiplier := 2.3
## Applied on a killing blow.
@export var kill_multiplier := 1.8
## Applied to LIMB wounds. Below 1.0: less meat.
@export var limb_multiplier := 0.7
## When a hit is BOTH a headshot and a kill, the kill bonus is scaled by this
## before being applied, so the two events combine instead of blindly
## multiplying into a fountain.
@export_range(0.0, 1.0) var combined_event_falloff := 0.5
## How strongly impact energy moves the result. 0.0 ignores energy entirely,
## 1.0 scales straight with it.
@export_range(0.0, 2.0) var energy_influence := 1.0
## How strongly overkill damage adds on top.
@export_range(0.0, 2.0) var overkill_influence := 0.6

@export_group("Organic chunks")
## Small solid gore bits that fly, fall and stay on the floor. They are the
## signature of a kill rather than of a hit, so by default they only spawn when
## one lands.
@export var chunk_on_kill_only := true
## Chunks for a plain kill at energy 1.0, before multipliers.
@export var chunk_count := 7
@export var chunk_size_min := 0.055
@export var chunk_size_max := 0.13
@export var chunk_speed_min := 2.5
@export var chunk_speed_max := 7.5
## Fraction of speed kept on the single bounce a chunk is allowed.
@export_range(0.0, 1.0) var chunk_bounce := 0.28
## Metres the chunk spawn points are jittered around the wound, so a kill throws
## debris out of a volume rather than out of one socket.
@export var chunk_origin_spread := 0.35
## Chunks get their OWN azimuth spread, in degrees either side of the impact
## direction. 180 is the full circle. Reusing the narrow bullet cone here is what
## made gore land in a straight line on the floor.
@export_range(0.0, 180.0) var chunk_spread_angle := 120.0
## Launch elevation band, in degrees. Negative is downward. A real band is what
## stops everything living in one flat plane.
@export var chunk_elevation_min := 8.0
@export var chunk_elevation_max := 70.0

@export_group("Physical droplets")
## Droplets are simulated against the static world and leave a splat where they
## land, so environment blood emerges from real trajectories instead of being
## placed by a raycast at the moment of impact.
@export var droplet_count := 14
@export var droplet_speed_min := 5.0
@export var droplet_speed_max := 14.0
@export var droplet_size := 0.045
## Size mix. The rest of the droplets are small. Ballistic wants many fine ones,
## blunt wants a heavier average - the difference between the families is the
## DISTRIBUTION, not a single threshold.
@export_range(0.0, 1.0) var droplet_medium_fraction := 0.3
@export_range(0.0, 1.0) var droplet_large_fraction := 0.08
## Azimuth spread either side of the impact direction, in degrees.
@export_range(0.0, 180.0) var droplet_spread_angle := 85.0
@export var droplet_elevation_min := -10.0
@export var droplet_elevation_max := 55.0
## Splat size for a droplet landing at droplet_speed_max. Scaled down by speed.
@export var droplet_splat_size := 0.55

@export_group("Look")
@export var color := Color(0.42, 0.015, 0.03, 1.0)
## Splats land darker than airborne spray.
@export var env_color := Color(0.26, 0.01, 0.02, 1.0)

@export_group("Forward / back spatter")
## Gunshot wounds throw material BOTH ways: a dense forward plume continuing the
## bullet's travel, and a sparser back spatter toward the shooter. Splitting the
## droplets into two lobes is most of what makes a bullet wound read as a bullet
## wound rather than as a generic burst.
##
## Set back_fraction to 0 for families where it makes no sense.
@export_range(0.0, 1.0) var back_fraction := 0.0
## Half-angle of the backward lobe. Usually wider and looser than the forward one.
@export var back_spread_angle := 70.0
## Back spatter carries less energy than the forward plume.
@export_range(0.0, 2.0) var back_speed_scale := 0.6
## ...but tends to be a bit chunkier per droplet.
@export var back_size_scale := 1.35

# ==========================================================================
# PHASE 2 - REPRESENTED MASS
# ==========================================================================
#
# Everything above describes the Phase 1 geometry contract and is still the
# shared frame machinery. What follows replaces "spawn N of each thing" with
# "this much mass, weighted this way".
#
# A profile no longer says how many droplets to make. It says how a family
# DIVIDES a given quantity of material between the representation layers, and
# how that material looks and moves. The count falls out of the mass.

@export_group("Mass weighting")
## How this family splits released BLOOD between the cheap layers and the
## physical ones. Not normalised on purpose: a family that atomises (ballistic)
## legitimately produces more total representatives per unit mass than one that
## throws it in lumps (blunt).
@export var micro_weight := 1.0
@export var small_weight := 1.0
@export var medium_weight := 1.0
## How this family splits released TISSUE between small grains and big chunks.
@export var grain_weight := 1.0
@export var chunk_weight := 1.0

@export_group("Layer speeds")
## Base launch speed per layer, before the pattern's own speed multiplier.
@export var micro_speed := 7.0
@export var small_speed := 8.5
@export var medium_speed := 11.0
@export var large_speed := 6.0

@export_group("Layer sizes")
## Base world size per layer. Stylised: these are readable sizes, not physical
## droplet diameters.
@export var micro_size := 0.030
@export var small_size := 0.055
@export var medium_size := 0.075
@export var grain_size := 0.055
@export var chunk_size := 0.13

@export_group("Stains")
## Relative weight of each stain shape in the atlas, in BloodTypes.Stain order:
## TINY_DROP, MEDIUM_ROUND, LARGE_IRREGULAR, ELONGATED, STREAK, CLUSTER, POOLED.
## This is a large part of how a family's aftermath is recognised: slashing is
## nearly all STREAK, blunt is POOLED and LARGE_IRREGULAR.
@export var stain_shape_weights: PackedFloat32Array = PackedFloat32Array(
	[0.22, 0.30, 0.18, 0.14, 0.06, 0.08, 0.02]
)
## Overall size multiplier for this family's stains.
@export var stain_scale := 1.0
## A few direct rays are still cast at emission time as an ACCENT, so a wall
## right behind a victim is marked instantly rather than waiting for flight
## time. The bulk of contamination now comes from real trajectories.
@export var direct_accent_rays := 3
@export var direct_accent_distance := 5.0


## Weight of one stain shape, safe against a short or empty array.
func stain_weight(shape: BloodTypes.Stain) -> float:
	var i := int(shape)
	if i < 0 or i >= stain_shape_weights.size():
		return 0.0
	return stain_shape_weights[i]
