class_name BloodSettings
extends Resource

@export var fluid: BloodPhysicsSettings = preload("res://data/blood/blood_physics.tres")
@export var stability: BloodStabilitySettings = preload("res://data/blood/blood_stability.tres")

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
## Fine mist capacity; sparse accents rather than the main impact silhouette.
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
@export var micro_per_mass := 180.0
@export var small_per_mass := 170.0
@export var medium_per_mass := 135.0
## Solid material comes from TISSUE mass rather than blood mass.
@export var large_per_tissue := 135.0
@export var grains_per_tissue := 200.0


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
## Shared crimson palette. Shape and motion, not unrelated hues, identify families.
@export var fresh_blood_color := Color("dc143c")
@export var dark_fresh_blood_color := Color("a80d30")
@export var wet_highlight_color := Color("ff526c")
@export var pooled_blood_color := Color("690a24")
## Fraction of a stain lobe's radius used for antialiased edge falloff.
## Baked into the atlas once; occupancy is measured after baking.
@export_range(0.02, 0.5) var stain_edge_softness := 0.10
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
@export var cluster_size := 6

@export_group("Stain area")
## Square metres of stain per unit of deposited represented mass.
##
## Stain RADIUS is derived as sqrt(mass * this / PI), so ten times the mass is
## about three times the width rather than ten times. That is what gives a real
## size distribution instead of the old uniform dots: the mapping was previously
## a lerp that saturated almost immediately.
@export var stain_area_per_mass := 7.2
## Hard clamps, so a single packet can neither vanish nor swallow a room.
@export var stain_radius_min := 0.045
@export var stain_radius_max := 1.35
## A landing heavy enough to break up into a CLUSTER rather than one disc. This
## is what makes a fat, dense airborne packet leave a convincing mark instead of
## the same dot a fine droplet leaves - the playtest complaint that heavy blood
## looked good in the air and underwhelming on the ground.
@export var cluster_mass_threshold := 0.0035

@export_group("Soak")
## Represented mass a contamination cell must accumulate before it earns a
## large soaked base layer underneath the fine detail.
@export var soak_mass_threshold := 0.085
## How much bigger the soaked base layer is than a normal stain.
@export var soak_base_scale := 4.0
## Hard ceiling on a soaked base radius, in metres.
##
## Without it, raising stain_area_per_mass in Phase 2.3 pushed bases past 4 m
## ACROSS - a pool the size of the room rather than a patch under a body. The
## base is a reinforcement for one contamination cell; it has no business being
## larger than one.
@export var soak_base_max_radius := 0.8
## Soaked bases are laid CLOSER to the surface than detail stains, so fine
## directional spatter always renders on top of them and is never erased.
@export var soak_base_offset := 0.004
## Most soaked bases one cell may accumulate.
@export var soak_bases_per_cell := 5

@export_group("Prewarm")
## Force every layer's transform buffer and material through the renderer once
## at chamber load, off screen, so the first real blood event does not pay for
## it. Costs one frame of setup and nothing afterwards.
@export var prewarm := true
## Instances touched per layer during prewarm.
@export var prewarm_instances := 64


# ==========================================================================
# PHASE 2.2 - SURFACE DEPOSITION, WALL RUNOFF, REMNANT TERMINATION
# ==========================================================================

@export_group("Remnants")
## Seconds a world remnant may last. Overrides whatever the wound was carrying,
## and is backed by a hard deadline inside Wound so nothing can outlive it.
## Cell size of the coarse grid used to approximate UNIQUE visible coverage.
## Developer diagnostics only; nothing in production reads it.
@export var coverage_cell_size := 0.05

@export var remnant_lifetime := 1.9
## Most remnants that may bleed at once. A multi-kill must not become a field of
## independent bleeders.
@export var max_remnants := 4

@export_group("Wall response")
## A surface counts as a wall when its normal is this far from vertical.
@export_range(0.0, 1.0) var wall_normal_threshold := 0.55
## How much further a shallow, glancing wall impact is stretched along its
## travel than a head-on one. Walls read as smears; floors read as pools.
@export var wall_streak_ratio := 4.5
## Head-on wall impacts stay compact instead.
@export var wall_compact_scale := 0.85
## Incidence below this (|dot(travel, normal)|) counts as glancing.
@export_range(0.0, 1.0) var wall_glancing_incidence := 0.55

@export_group("Wall runoff")
## Deposited mass a wall spot needs before any of it starts running down.
@export var runoff_mass_threshold := 0.012
## Share of a qualifying wall deposit that becomes a running rivulet. Carved OUT
## of the stain, never added: runoff is not free blood.
@export_range(0.0, 1.0) var runoff_mass_share := 0.55
## Most rivulets alive at once, across the whole arena.
@export var max_runoff := 24
## Metres per second a rivulet creeps down the wall.
@export var runoff_speed := 0.55
## Metres between the marks a rivulet lays behind it.
@export var runoff_step := 0.09
## Seconds a rivulet may run before it stops regardless of budget.
@export var runoff_lifetime := 6.0
## How far a rivulet wanders sideways, in metres per second.
@export var runoff_wander := 0.12
## Width of the streak relative to the mark radius its mass would give.
@export var runoff_width := 0.55
## How far each runoff segment overreaches the gap to the previous one. Above
## 1.0 the segments overlap, which is what makes a rivulet read as a continuous
## streak instead of a dotted line.
## Share of a rivulet's remaining mass dropped where it finally stops.
@export var runoff_overlap := 1.45
## How narrow a rivulet gets once it has spent its material. 1.0 is a uniform
## ribbon; below that it tapers from a thick start to a thin tail.
@export_range(0.15, 1.0) var runoff_taper_min := 0.42
## Chance per segment that a running streak sheds a visible drop beside itself.
@export_range(0.0, 1.0) var runoff_drop_chance := 0.14
@export_range(0.0, 1.0) var runoff_terminal_share := 0.6


@export_group("Airborne readability")
## VISUAL-ONLY exaggeration of rendered droplet size. Physics is untouched:
## drag, collision, represented mass, physical diameter and stain mass all use
## the true simulated diameter. A physically correct 3 mm bead is about one
## pixel across a room, so the blood carrying the event is invisible exactly
## when the player is looking at it.
##
## MEDIUM is the primary readable airborne class and gets the larger gain.
@export_range(1.0, 4.0) var medium_readability_gain := 1.9
@export_range(1.0, 4.0) var small_readability_gain := 1.35
## Below this distance there is no distance growth at all, so nothing becomes a
## giant blob in the player's face.
@export var readability_reference_m := 5.0
## Hard clamp on distance growth. Never unbounded.
@export var readability_max_scale := 2.4
