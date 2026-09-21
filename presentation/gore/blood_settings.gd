class_name BloodSettings
extends Resource

## Global blood budgets and physics. Profiles say how one event looks; this says
## what the whole system is allowed to cost, and it is a hard ceiling that no
## profile can talk its way past.
##
## Phase 2 note: budgets are now CAPACITIES OF BATCHED LAYERS, not counts of
## scene nodes. A MultiMesh slot costs twelve floats, so the numbers here are an
## order of magnitude larger than the old per-node pools while costing less.

@export_group("Quality")
## Development intensity. THE_BOX and the Blood Lab default to INSANE while the
## visual target is being established.
##
## This scales REPRESENTATION ONLY. It multiplies how many visual and physical
## representatives a release is drawn with, and it may never touch the logical
## reservoir, the released mass or a wound's schedule.
@export var quality: BloodTypes.Quality = BloodTypes.Quality.INSANE

## Representative multipliers per tier.
@export var low_scale := 0.22
@export var high_scale := 0.6
@export var insane_scale := 1.0


@export_group("Layer capacities")
## Fine mist. Cheap and abundant - this is the layer that makes a catastrophic
## event look catastrophic.
@export var max_micro := 3000
## Visible beads.
@export var max_small := 1200
## Thick droplets and globules - the PHYSICAL representatives, each simulated
## against the static world and each able to leave a stain.
@export var max_medium := 520
## Gore chunks and tissue grains.
@export var max_large := 700
## The arena's memory. Every stain the chamber is holding.
@export var max_surface := 3200


@export_group("Per-event admission")
## Per-event demand is derived from released MASS, then admitted against the
## FREE capacity of each layer. There is deliberately no flat per-event cap:
## a flat cap is exactly what made a grenade kill and a pistol hit both emit 22
## droplets and look identical.
##
## Fraction of a layer's FREE slots one event may take at most. Below 1.0 so a
## single catastrophic event cannot strip the pool bare for the next one.
@export_range(0.05, 1.0) var event_free_share := 0.75
## Floor so that even a starved event keeps its family signature legible.
@export var min_micro_per_event := 8
@export var min_medium_per_event := 3


@export_group("Mass to representatives")
## How many representatives one unit of blood mass is worth, per layer, at
## INSANE. A full-body release (mass ~0.8) therefore asks for roughly
## 0.8 * micro_per_mass micro elements.
@export var micro_per_mass := 1400.0
@export var small_per_mass := 520.0
@export var medium_per_mass := 210.0
## Solid material comes from TISSUE mass rather than blood mass.
@export var large_per_tissue := 190.0
@export var grains_per_tissue := 460.0


@export_group("Airborne physics")
@export var gravity := 26.0
## Air drag, per second, for the cheap non-colliding layers.
@export var drag := 2.2
## Fraction of lifetime spent fading out.
@export_range(0.05, 1.0) var fade_fraction := 0.45
@export var micro_lifetime := 0.5
@export var small_lifetime := 0.85


@export_group("Physical representatives")
## Representatives are simulated at a FIXED timestep, in _physics_process, so
## the distance a droplet travels stops depending on the render frame rate.
@export var droplet_max_life := 4.0
## Air drag coefficient, applied as drag ~ speed^2 and divided by size, so fine
## spray decelerates fast and fat droplets carry. Tuning number, not a constant.
@export var droplet_drag := 0.22
@export var droplet_color := Color(0.55, 0.03, 0.04, 1.0)
## Base world size of a MEDIUM representative. Stylised: physical quantity and
## readable visual size are different things, and blood has to read at FPS
## distance.
@export var droplet_size := 0.075
## Representatives moving slower than this when they land are absorbed silently.
@export var droplet_min_impact_speed := 0.4


@export_group("Environment stains")
## Metres a stain is pushed off the surface along its normal. Without this the
## quad is coplanar with the wall and z-fights.
@export var surface_offset := 0.012
## Seconds a stain spends fading at the end of its life, when it has one.
@export var fade_time := 2.5
## Physics layers blood may land on. World geometry only: blood does not stick
## to hurtboxes or to the player.
@export var surface_mask := 1
## Stains are persistent by default and only recycled under pressure.
@export var stain_lifetime := 0.0
@export var stain_size_min := 0.10
@export var stain_size_max := 0.85

@export_group("Contamination")
## The arena is divided into cells this many metres across. Eviction happens
## WITHIN the most crowded cell rather than globally, so a busy corner cannot
## erase the history of a fight on the other side of the room.
@export var contamination_cell_size := 3.0
## Stains landing in a cell that already holds this many trigger one large
## reinforcement stain instead of another identical sticker, which is what makes
## a heavily hit patch start reading as soaked rather than as 50 decals.
@export var soak_threshold := 10
## Size multiplier of a reinforcement stain.
@export var soak_scale := 2.6
## Darkening applied as a cell saturates.
@export_range(0.0, 1.0) var soak_darkening := 0.45

@export_group("Satellites")
## Fast heavy impacts throw a few small secondary marks. Strictly bounded.
@export var satellite_max := 3
## Fraction of qualifying impacts that throw satellites at all.
@export_range(0.0, 1.0) var satellite_chance := 0.28
@export var satellite_speed_threshold := 6.0
@export var satellite_spread := 0.35
## Fraction of an impact.s material that is thrown off as satellites, CARVED
## OUT of the main mark rather than added to it.
## Rough surfaces throw more satellites than smooth ones.
@export_range(0.0, 0.5) var satellite_mass_share := 0.18
@export var rough_satellite_bonus := 1

@export_group("Chunk impacts")
## A large chunk may leave at most this many marks over its whole life. No
## recursive gore.
@export var chunk_max_marks := 1
@export_range(0.0, 1.0) var chunk_bounce := 0.28

@export_group("Look")
@export var chunk_color := Color(0.3, 0.02, 0.03, 1.0)
## Stain atlas resolution per cell. Seven shapes in one texture.
@export var stain_atlas_cell := 64

@export_group("Debug")
## Draws the vectors every blood event was built from.
@export var debug_patterns := false
## Prints one line per blood event, now including represented MASS rather than
## particle counts alone.
@export var debug_telemetry := false
@export var debug_gizmo_life := 5.0
@export var debug_gizmo_slots := 12


## Representation multiplier for the active tier. The ONLY thing quality does.
func quality_scale() -> float:
	match quality:
		BloodTypes.Quality.LOW:
			return low_scale
		BloodTypes.Quality.HIGH:
			return high_scale
		_:
			return insane_scale


# ==========================================================================
# PHASE 2.1 - SURFACE PAYOFF
# ==========================================================================
#
# The playtest verdict was that a massive airborne release left a weak
# aftermath. The cause was structural: ALL blood mass was divided evenly across
# the physical representatives, so every landing produced an identical small
# stain, and the thousands of cheap airborne elements carried no mass and
# deposited nothing at all. These numbers close that gap.

@export_group("Air to surface")
## Share of a release's blood mass carried by PHYSICAL representatives, which
## fly and collide. The remainder is carried by the cheap airborne cloud and
## reaches the world through bounded coarse deposition probes instead.
##
## Both halves deposit. Nothing is allowed to simply evaporate.
@export_range(0.1, 1.0) var physical_mass_share := 0.55
## Coarse deposition probes per unit of cloud mass. Each probe is ONE raycast
## that deposits a cluster, so this is the whole cost of representing thousands
## of micro particles hitting the world.
@export var cloud_probes_per_mass := 26.0
@export var cloud_probes_max := 30
## How far a coarse probe looks for a surface.
@export var cloud_probe_distance := 7.0
## Stains per cluster. One anchor plus this many satellites around it.
@export var cluster_size := 4

@export_group("Stain area")
## Square metres of stain per unit of deposited represented mass.
##
## Stain RADIUS is derived as sqrt(mass * this / PI), so ten times the mass is
## about three times the width rather than ten times. That is what gives a real
## size distribution instead of the old uniform dots: the mapping was previously
## a lerp that saturated almost immediately.
@export var stain_area_per_mass := 2.6
## Hard clamps, so a single packet can neither vanish nor swallow a room.
@export var stain_radius_min := 0.045
@export var stain_radius_max := 1.35

@export_group("Soak")
## Represented mass a contamination cell must accumulate before it earns a
## large soaked base layer underneath the fine detail.
@export var soak_mass_threshold := 0.16
## How much bigger the soaked base layer is than a normal stain.
@export var soak_base_scale := 3.4
## Soaked bases are laid CLOSER to the surface than detail stains, so fine
## directional spatter always renders on top of them and is never erased.
@export var soak_base_offset := 0.004
## Most soaked bases one cell may accumulate.
@export var soak_bases_per_cell := 3

@export_group("Prewarm")
## Force every layer's transform buffer and material through the renderer once
## at chamber load, off screen, so the first real blood event does not pay for
## it. Costs one frame of setup and nothing afterwards.
@export var prewarm := true
## Instances touched per layer during prewarm.
@export var prewarm_instances := 64
