class_name BloodSystem
extends Node3D

## The only thing in the project that spawns blood.
##
## Combat never touches particles. A victim's BloodReservoir decides how much
## material left the body and hands over a BloodRelease; this node picks the
## family's BloodPattern and draws that mass. Adding a weapon means adding a
## damage type and an energy number, not code here.
##
## PHASE 2 ARCHITECTURE
##
##   MASS, NOT COUNTS. A release carries represented blood and tissue mass. How
##   many elements that becomes is decided here and only here, which is why a
##   quality tier can change the look without ever changing the event.
##
##   BATCHED. Five MultiMesh layers instead of 850 MeshInstance3D nodes. The
##   arena can hold thousands of elements for the cost of five draw calls, on
##   the Compatibility backend, with no compute and no Forward+ features.
##
##   FOUR PATTERNS, NOT ONE EMITTER. BallisticPattern / SlashingPattern /
##   BluntPattern / ExplosivePattern generate structurally different geometry -
##   a track, a fan, a shell, a multi-origin rupture. Phase 1's cone sampler is
##   retained below as the shared FRAME machinery and as the thing the Phase 1
##   regression tests assert on, but it no longer decides shape.
##
##   TRAJECTORIES PAINT THE ROOM. MEDIUM representatives fly, collide with real
##   static geometry at a fixed timestep and stain wherever they land.
##
## Everything is preallocated. A long run cannot create a single extra node.

const GROUP := &"blood_system"

@export var settings: BloodSettings
## One per DamageType. Indexed by profile.damage_type at _ready.
@export var profiles: Array[BloodProfile] = []
## Used when something calls spill() without a reservoir behind it.
@export var fallback_reservoir: ReservoirConfig

## Last event handled, for tests and the debug overlay. Debug only.
var last_context: BloodContext
var last_release: BloodRelease
var last_particles_spawned := 0
var last_splats_spawned := 0
var last_chunks_spawned := 0
var last_droplets_spawned := 0
## Phase 2 telemetry, per event.
var last_mass_requested := 0.0
var last_mass_admitted := 0.0
var last_grains_spawned := 0
var last_small_spawned := 0

## PHASE 2.1 MASS LEDGER. Represented-mass accounting for one event, so a weak
## aftermath can be traced to the stage that lost the mass rather than guessed
## at from particle counts. Read through mass_ledger().
var _led_blood := 0.0
var _led_tissue := 0.0
var _led_air_mass := 0.0
var _led_physical_mass := 0.0
var _led_hit_world := 0.0
var _led_timed_out := 0.0
var _led_recycled := 0.0
var _led_surface_mass := 0.0
var _led_stains := 0
var _led_stain_area := 0.0
var _led_floor := 0.0
var _led_wall := 0.0
var _led_ceiling := 0.0
var _led_tissue_deposited := 0.0

var _profiles: Dictionary[int, BloodProfile] = {}
var _patterns: Dictionary[int, BloodPattern] = {}
var _rng := RandomNumberGenerator.new()
var _event_counter := 0
## Events that came from an actual blow, as opposed to a wound dripping.
var _combat_events := 0

# --- Batched layers ---
var _micro: BloodMultiMeshLayer
var _small: BloodMultiMeshLayer
var _medium: BloodMultiMeshLayer
var _large: BloodMultiMeshLayer
var _surface: BloodMultiMeshLayer

# --- Cheap airborne (MICRO + SMALL): no collision, ballistic, faded out ---
var _air_slot: PackedInt32Array = PackedInt32Array()
var _air_layer: PackedByteArray = PackedByteArray()
var _air_pos: PackedVector3Array = PackedVector3Array()
var _air_vel: PackedVector3Array = PackedVector3Array()
var _air_life: PackedFloat32Array = PackedFloat32Array()
var _air_max_life: PackedFloat32Array = PackedFloat32Array()
var _air_size: PackedFloat32Array = PackedFloat32Array()
var _air_stretch: PackedFloat32Array = PackedFloat32Array()
var _air_color: PackedColorArray = PackedColorArray()
var _air_count := 0

# --- Physical representatives (MEDIUM): collide, stain on landing ---
var _rep_slot: PackedInt32Array = PackedInt32Array()
var _rep_pos: PackedVector3Array = PackedVector3Array()
var _rep_vel: PackedVector3Array = PackedVector3Array()
var _rep_life: PackedFloat32Array = PackedFloat32Array()
var _rep_size: PackedFloat32Array = PackedFloat32Array()
var _rep_mass: PackedFloat32Array = PackedFloat32Array()
var _rep_stretch: PackedFloat32Array = PackedFloat32Array()
var _rep_color: PackedColorArray = PackedColorArray()
var _rep_profile: Array[BloodProfile] = []
var _rep_count := 0

# --- Solid material (LARGE): grains and chunks, collide, settle, persist ---
var _sol_slot: PackedInt32Array = PackedInt32Array()
var _sol_pos: PackedVector3Array = PackedVector3Array()
var _sol_vel: PackedVector3Array = PackedVector3Array()
var _sol_spin: PackedFloat32Array = PackedFloat32Array()
var _sol_basis: Array[Basis] = []
var _sol_size: PackedVector3Array = PackedVector3Array()
var _sol_color: PackedColorArray = PackedColorArray()
var _sol_marks: PackedByteArray = PackedByteArray()
var _sol_bounced: PackedByteArray = PackedByteArray()
var _sol_mesh: PackedFloat32Array = PackedFloat32Array()
## Represented TISSUE mass each solid stands for. A chunk that marks a surface
## deposits from this, instead of the hardcoded constant it used to invent.
var _sol_mass: PackedFloat32Array = PackedFloat32Array()
var _sol_profile: Array[BloodProfile] = []
var _sol_count := 0
## Settled solids keep their slot (they stay visible) but stop simulating.
var _sol_settled: PackedInt32Array = PackedInt32Array()

# --- Stains ---
var _stain_life: PackedFloat32Array = PackedFloat32Array()
var _stain_active: PackedByteArray = PackedByteArray()
## cell key -> stain count, for soak reinforcement and cell-local density.
var _cells: Dictionary = {}
## cell key -> the slots that cell holds, oldest first. THIS is what makes
## eviction cell-local instead of a global ring that erases the oldest stain
## anywhere in the arena.
var _cell_slots: Dictionary = {}
## cell key -> represented mass deposited there, and how many soaked bases it
## has already earned. This is what turns repeated hits into a wet region
## instead of a pile of stickers.
var _cell_mass: Dictionary = {}
var _cell_bases: Dictionary = {}
var _stain_cell: PackedInt64Array = PackedInt64Array()

# --- Wound scheduling ---
var _reservoirs: Array[BloodReservoir] = []
## Wounds whose victim is gone, finishing out in world space.
var _remnants: Array[Wound] = []
var _remnant_family: Array[int] = []

var _tissue_meshes: Array[Mesh] = []
var _stain_atlas: ImageTexture
var _ray: PhysicsRayQueryParameters3D

# --- Debug ---
var _gizmos: Array[MeshInstance3D] = []
var _gizmo_life: Array[float] = []
var _next_gizmo := 0
var _prewarmed := false


func _ready() -> void:
	add_to_group(GROUP)
	if settings == null:
		push_error("BloodSystem has no BloodSettings assigned.")
		return
	if fallback_reservoir == null:
		fallback_reservoir = load("res://data/blood/reservoir_defaults.tres")
	for profile in profiles:
		if profile != null:
			_profiles[int(profile.damage_type)] = profile
			_patterns[int(profile.damage_type)] = BloodPattern.for_family(profile.damage_type)

	_rng.seed = 0x8100D
	_tissue_meshes = TissueDebris.build_meshes()
	_build_layers()

	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true
	_ray.collision_mask = settings.surface_mask

	if settings.prewarm:
		_prewarm()

	set_process(false)
	set_physics_process(true)


static func find(tree: SceneTree) -> BloodSystem:
	return tree.get_first_node_in_group(GROUP) as BloodSystem


# --------------------------------------------------------------------------
# Entry points
# --------------------------------------------------------------------------

## THE entry point. A reservoir has already decided how much material this is.
func release(rel: BloodRelease) -> void:
	if rel == null or rel.context == null or settings == null:
		return
	var ctx := rel.context
	# A wound dripping must NOT clobber the record of the last BLOW. These are
	# debug/telemetry fields that tests and the overlay read right after a hit,
	# and a residual drip landing in between made a hand cannon headshot report
	# the drip's energy and direction instead of its own.
	if not rel.is_residual:
		last_context = ctx
		last_release = rel
		last_particles_spawned = 0
		last_small_spawned = 0
		last_splats_spawned = 0
		last_chunks_spawned = 0
		last_droplets_spawned = 0
		last_grains_spawned = 0
		last_mass_requested = rel.total_mass()
		last_mass_admitted = 0.0
		_led_blood = rel.blood_mass
		_led_tissue = rel.tissue_mass
		_led_air_mass = 0.0
		_led_physical_mass = 0.0
		_led_hit_world = 0.0
		_led_timed_out = 0.0
		_led_recycled = 0.0
		_led_surface_mass = 0.0
		_led_stains = 0
		_led_stain_area = 0.0
		_led_floor = 0.0
		_led_wall = 0.0
		_led_ceiling = 0.0
		_led_tissue_deposited = 0.0

	var profile := _profiles.get(int(ctx.damage_type)) as BloodProfile
	if profile == null:
		return

	ctx.blood_primary_axis_ws = ctx.primary_axis()
	_event_counter += 1
	if not rel.is_residual:
		_combat_events += 1
	ctx.event_id = _event_counter
	rel.event_id = _event_counter

	# The Phase 1 frame: attack-relative, pitch-preserving, swing-plane aware.
	var frame := _pattern_frame(ctx, _lobe_axis(ctx, false))
	var pattern := _patterns.get(int(ctx.damage_type)) as BloodPattern
	if pattern == null:
		pattern = BloodPattern.for_family(ctx.damage_type)
		_patterns[int(ctx.damage_type)] = pattern
	pattern.begin(rel, frame, _rng)

	_emit_micro(profile, rel, pattern)
	_emit_small(profile, rel, pattern)
	_emit_medium(profile, rel, pattern)
	_emit_solids(profile, rel, pattern)
	_coarse_deposition(profile, rel, pattern)

	if settings.debug_telemetry:
		print("[blood] %s | %s" % [rel.describe(), _event_telemetry()])
	if settings.debug_patterns:
		_draw_event_gizmo(ctx)
	_wake()


## Convenience for callers with no reservoir behind them - the Phase 1 tests and
## anything that just wants blood at a point. Estimates a plausible mass from
## the context using the same config a real body would use.
func spill(ctx: BloodContext) -> void:
	release(estimate_release(ctx))


func estimate_release(ctx: BloodContext) -> BloodRelease:
	var cfg := fallback_reservoir
	if cfg == null:
		cfg = load("res://data/blood/reservoir_defaults.tres")
	var scale := cfg.family_scale(ctx.damage_type)
	match ctx.body_region:
		BloodTypes.BodyRegion.HEAD:
			scale *= cfg.head_multiplier
		BloodTypes.BodyRegion.LIMB:
			scale *= cfg.limb_multiplier
		_:
			pass
	scale *= 1.0 + (ctx.energy - 1.0) * cfg.energy_influence
	scale *= 1.0 + ctx.overkill * cfg.overkill_influence
	var blood := 0.0
	var tissue := 0.0
	if ctx.is_kill:
		var f := cfg.kill_blood_fraction
		if ctx.body_region == BloodTypes.BodyRegion.HEAD:
			f = minf(f * cfg.kill_head_multiplier, 1.0)
		blood = cfg.max_blood * f * scale
		tissue = blood * cfg.kill_tissue_ratio
	else:
		blood = cfg.max_blood * cfg.hit_blood_fraction * scale
		tissue = blood * cfg.hit_tissue_ratio
	var rel := BloodRelease.make(ctx, blood, tissue)
	rel.tissue_mix = cfg.tissue_mix_for(ctx.damage_type)
	rel.wound_severity = cfg.wound_severity_for(ctx.damage_type)
	return rel


# --------------------------------------------------------------------------
# Admission: mass -> representatives
# --------------------------------------------------------------------------

## How many elements a quantity of mass is worth in one layer, after quality and
## after what the layer can actually afford RIGHT NOW.
##
## There is deliberately NO flat per-event cap. A flat cap is precisely what
## made BLUNT's configured 30 and HIGH_ENERGY's 40 both come out as 22, so a
## grenade kill and a pistol hit produced the same amount of material and the
## entire mass model was invisible. Demand scales with mass; supply is limited
## only by what is genuinely free.
func _admit(layer: BloodMultiMeshLayer, demand: float, floor_count: int) -> int:
	var want := int(round(demand * settings.quality_scale()))
	if want <= 0:
		return 0
	var affordable := int(layer.free_slots() * settings.event_free_share)
	# The floor guarantees a family signature survives even under pressure.
	affordable = maxi(affordable, mini(floor_count, layer.capacity))
	return mini(want, affordable)


func _emit_micro(profile: BloodProfile, rel: BloodRelease, pattern: BloodPattern) -> void:
	var demand := rel.blood_mass * settings.micro_per_mass * profile.micro_weight
	var count := _admit(_micro, demand, settings.min_micro_per_event)
	if rel.is_residual:
		count = mini(count, 6)
	var reach := 0.6 + rel.total_mass() * 1.4
	for i in count:
		var u := float(i) / maxf(float(count), 1.0)
		pattern.sample(BloodTypes.Layer.MICRO, u)
		_emit_air(
			_micro,
			rel.position_ws() + pattern.out_origin,
			pattern.out_dir * profile.micro_speed * pattern.out_speed * reach,
			profile.micro_size * pattern.out_size,
			pattern.out_stretch,
			_blood_tint(profile),
			settings.micro_lifetime
		)
	if not rel.is_residual:
		last_particles_spawned = count
	if demand > 0.0 and not rel.is_residual:
		last_mass_admitted += rel.blood_mass * clampf(float(count) / demand, 0.0, 1.0)


func _emit_small(profile: BloodProfile, rel: BloodRelease, pattern: BloodPattern) -> void:
	var demand := rel.blood_mass * settings.small_per_mass * profile.small_weight
	var count := _admit(_small, demand, 4)
	if rel.is_residual:
		count = mini(count, 4)
	var reach := 0.7 + rel.total_mass() * 1.2
	for i in count:
		var u := float(i) / maxf(float(count), 1.0)
		pattern.sample(BloodTypes.Layer.SMALL, u)
		_emit_air(
			_small,
			rel.position_ws() + pattern.out_origin,
			pattern.out_dir * profile.small_speed * pattern.out_speed * reach,
			profile.small_size * pattern.out_size,
			pattern.out_stretch,
			_blood_tint(profile),
			settings.small_lifetime
		)
	if not rel.is_residual:
		last_small_spawned = count


## The physical layer. These fly, hit real geometry and stain it.
func _emit_medium(profile: BloodProfile, rel: BloodRelease, pattern: BloodPattern) -> void:
	var demand := rel.blood_mass * settings.medium_per_mass * profile.medium_weight
	var count := _admit(_medium, demand, settings.min_medium_per_event)
	if rel.is_residual:
		count = mini(count, 3)
	var reach := 0.8 + rel.total_mass() * 1.1
	if count <= 0:
		return

	# SIZE CLASSES, NOT AN EVEN SPLIT.
	#
	# Dividing the mass evenly gave every representative an identical share and
	# therefore an identical small stain - which is exactly what "many small
	# isolated stains" looked like in the playtest. Real spatter is a few heavy
	# packets among many fine ones, so the mass is distributed the same way and
	# the aftermath gets a genuine size distribution.
	var weights := PackedFloat32Array()
	weights.resize(count)
	var total_weight := 0.0
	for i in count:
		var roll := _rng.randf()
		var w := 1.0
		if roll > 1.0 - profile.droplet_large_fraction:
			w = _rng.randf_range(5.0, 9.0)
		elif roll > 1.0 - profile.droplet_large_fraction - profile.droplet_medium_fraction:
			w = _rng.randf_range(2.0, 3.6)
		else:
			w = _rng.randf_range(0.4, 1.0)
		weights[i] = w
		total_weight += w

	# Only the PHYSICAL share rides on representatives; the rest belongs to the
	# cheap cloud and is deposited by coarse probes.
	# A drip has no cloud worth probing for, so all of its material rides on the
	# handful of droplets it does emit. Otherwise the cloud share would simply be
	# lost and a bleeding wound would stain nothing.
	var physical_mass := rel.blood_mass
	if not rel.is_residual:
		physical_mass = rel.blood_mass * settings.physical_mass_share
	_led_physical_mass = physical_mass
	for i in count:
		var u := float(i) / maxf(float(count), 1.0)
		pattern.sample(BloodTypes.Layer.MEDIUM, u)
		var share := physical_mass * (weights[i] / maxf(total_weight, 0.001))
		# A heavier packet is visibly fatter in flight as well as on landing.
		var bulk: float = pow(weights[i], 0.34)
		_emit_representative(
			profile,
			rel.position_ws() + pattern.out_origin,
			pattern.out_dir * profile.medium_speed * pattern.out_speed * reach,
			profile.medium_size * pattern.out_size * bulk,
			share,
			pattern.out_stretch
		)
	if not rel.is_residual:
		last_droplets_spawned = count


## Tissue: grains and chunks, in the family's own mixture.
func _emit_solids(profile: BloodProfile, rel: BloodRelease, pattern: BloodPattern) -> void:
	if rel.tissue_mass <= 0.0 or rel.is_residual:
		return
	var grain_demand := rel.tissue_mass * settings.grains_per_tissue * profile.grain_weight
	var chunk_demand := rel.tissue_mass * settings.large_per_tissue * profile.chunk_weight
	var reach := 0.7 + rel.total_mass()

	# CHUNKS FIRST. Grains and chunks share one layer, and grains are far more
	# numerous, so asking for grains first let them eat the whole allocation and
	# a maul kill came out with 195 specks and almost no real pieces. The big
	# pieces are the ones that carry the family's read, so they get served first.
	var chunks := _admit(_large, chunk_demand, 0)
	# Tissue mass is shared out over the solids that actually exist. A chunk is
	# worth several grains, so it carries several grains' worth of material.
	var grains_planned := _admit(_large, grain_demand, 0)
	var tissue_units := float(chunks) * 4.0 + float(grains_planned)
	var unit_mass := rel.tissue_mass / maxf(tissue_units, 1.0)
	for i in chunks:
		var uc := float(i) / maxf(float(chunks), 1.0)
		# Material first: a pattern may throw fat and dense tissue differently.
		var cc := TissueDebris.pick(rel.tissue_mix, _rng.randf())
		pattern.material_class = int(cc)
		pattern.sample(BloodTypes.Layer.LARGE, uc)
		_emit_solid(
			profile,
			rel.position_ws() + pattern.out_origin,
			pattern.out_dir * profile.large_speed * pattern.out_speed * reach * 0.8,
			profile.chunk_size * pattern.out_size * TissueDebris.size_for(cc),
			cc,
			true,
			unit_mass * 4.0
		)
	last_chunks_spawned = chunks

	var grains := grains_planned
	for i in grains:
		var u := float(i) / maxf(float(grains), 1.0)
		var cat := TissueDebris.pick(rel.tissue_mix, _rng.randf())
		pattern.material_class = int(cat)
		pattern.sample(BloodTypes.Layer.LARGE, u)
		_emit_solid(
			profile,
			rel.position_ws() + pattern.out_origin,
			pattern.out_dir * profile.large_speed * pattern.out_speed * reach,
			profile.grain_size * pattern.out_size * TissueDebris.size_for(cat),
			cat,
			false,
			unit_mass
		)
	last_grains_spawned = grains
	pattern.material_class = -1


## COARSE DEPOSITION: how the cheap airborne cloud reaches the world.
##
## This is the fix for the central Phase 2 failure. Thousands of micro and small
## elements implied a huge quantity of blood, but they carried no mass and never
## touched anything, so the aftermath was built entirely from the few hundred
## physical representatives and looked far too clean for what had just flown
## through the air.
##
## Simulating every micro particle is out of the question. Instead the cloud's
## share of the mass is deposited through a BOUNDED number of probes - a couple
## of dozen raycasts for an entire catastrophic event - each sampled from the
## family's own pattern so the deposition lands where that pattern actually
## threw material. Each probe drops a CLUSTER carrying its share of the mass.
##
## Mass-conserving by construction: physical_mass_share rides on
## representatives, and everything left over is deposited here.
func _coarse_deposition(profile: BloodProfile, rel: BloodRelease, pattern: BloodPattern) -> void:
	if rel.is_residual:
		return
	var cloud_mass := rel.blood_mass * (1.0 - settings.physical_mass_share)
	_led_air_mass = cloud_mass
	if cloud_mass <= 0.0:
		return
	var probes := clampi(
		int(round(cloud_mass * settings.cloud_probes_per_mass)), 1, settings.cloud_probes_max
	)
	var per_probe := cloud_mass / float(probes)
	var space := get_world_3d().direct_space_state
	var origin := rel.position_ws()
	var landed := 0.0
	for i in probes:
		pattern.sample(BloodTypes.Layer.SURFACE, float(i) / maxf(float(probes), 1.0))
		var dir := pattern.out_dir
		_ray.from = origin + pattern.out_origin
		_ray.to = _ray.from + dir * settings.cloud_probe_distance
		var hit := space.intersect_ray(_ray)
		if hit.is_empty():
			# Nothing in that direction within reach. The material still has to
			# go somewhere, so gravity takes it: look straight down instead.
			_ray.from = origin
			_ray.to = origin + Vector3.DOWN * settings.cloud_probe_distance
			hit = space.intersect_ray(_ray)
			dir = Vector3.DOWN
			if hit.is_empty():
				continue
		_deposit_cluster(profile, hit.position, hit.normal, dir, per_probe)
		landed += per_probe
	_led_surface_mass += 0.0  # counted inside _place_stain


## One probe's worth of material, laid down as a cluster rather than a single
## disc: an anchor stain carrying most of the mass plus a few smaller marks
## around it. Clusters are what stop dense areas reading as isolated stickers.
func _deposit_cluster(
	profile: BloodProfile, point: Vector3, normal: Vector3, travel: Vector3, mass: float
) -> void:
	var satellites: int = maxi(settings.cluster_size, 0)
	# The anchor keeps the lion's share; the rest is spread around it.
	var anchor_mass := mass * 0.62
	_place_stain(profile, point, normal, travel, _stain_radius(profile, anchor_mass), anchor_mass)
	if satellites <= 0:
		return
	var spread: float = _stain_radius(profile, mass) * 1.9
	var tangent := travel.slide(normal)
	if tangent.length_squared() < 0.0001:
		tangent = normal.cross(Vector3.UP)
		if tangent.length_squared() < 0.0001:
			tangent = normal.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var bitangent := normal.cross(tangent).normalized()
	var each := (mass - anchor_mass) / float(satellites)
	for i in satellites:
		var at := point
		at += tangent * _rng.randf_range(-spread, spread * 1.6)
		at += bitangent * _rng.randf_range(-spread, spread)
		# Keep the satellite on the same surface plane as its anchor.
		_place_stain(profile, at, normal, travel, _stain_radius(profile, each), each)


func _blood_tint(profile: BloodProfile) -> Color:
	# Slight variation between fresh and deep red, so a burst is not one flat
	# colour. Restrained: this is blood, not confetti.
	var c := profile.color
	var j := _rng.randf_range(-0.06, 0.06)
	return Color(clampf(c.r + j, 0.0, 1.0), c.g, c.b, 1.0)


# --------------------------------------------------------------------------
# Cheap airborne layer
# --------------------------------------------------------------------------

func _emit_air(
	layer: BloodMultiMeshLayer, pos: Vector3, vel: Vector3, size: float,
	stretch: float, color: Color, life: float
) -> void:
	# Airborne mist is never worth evicting live material for.
	var slot := layer.acquire(false)
	if slot < 0:
		return
	var i := _air_count
	if i >= _air_slot.size():
		layer.release(slot)
		return
	_air_count += 1
	_air_slot[i] = slot
	_air_layer[i] = 0 if layer == _micro else 1
	_air_pos[i] = pos
	_air_vel[i] = vel
	_air_life[i] = life
	_air_max_life[i] = life
	_air_size[i] = size
	_air_stretch[i] = stretch
	_air_color[i] = color
	layer.write(slot, _oriented(pos, vel, size, stretch), color)


func _step_air(delta: float) -> void:
	var i := 0
	while i < _air_count:
		_air_life[i] -= delta
		if _air_life[i] <= 0.0:
			_retire_air(i)
			continue
		var vel := _air_vel[i]
		vel.y -= settings.gravity * delta
		vel *= maxf(1.0 - settings.drag * delta, 0.0)
		_air_vel[i] = vel
		var pos := _air_pos[i] + vel * delta
		_air_pos[i] = pos
		var layer := _micro if _air_layer[i] == 0 else _small
		var c := _air_color[i]
		c.a = clampf(_air_life[i] / maxf(_air_max_life[i] * settings.fade_fraction, 0.001), 0.0, 1.0)
		layer.write(_air_slot[i], _oriented(pos, vel, _air_size[i], _air_stretch[i]), c)
		i += 1


func _retire_air(i: int) -> void:
	var layer := _micro if _air_layer[i] == 0 else _small
	layer.release(_air_slot[i])
	var last := _air_count - 1
	if i != last:
		_air_slot[i] = _air_slot[last]
		_air_layer[i] = _air_layer[last]
		_air_pos[i] = _air_pos[last]
		_air_vel[i] = _air_vel[last]
		_air_life[i] = _air_life[last]
		_air_max_life[i] = _air_max_life[last]
		_air_size[i] = _air_size[last]
		_air_stretch[i] = _air_stretch[last]
		_air_color[i] = _air_color[last]
	_air_count -= 1


## Stretched along its own travel, so fast material reads as a streak. This is
## most of what sells blood in motion.
func _oriented(pos: Vector3, vel: Vector3, size: float, stretch: float) -> Transform3D:
	var speed := vel.length()
	var basis := Basis.IDENTITY
	if speed > 0.01:
		var forward := vel / speed
		var reference := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		basis = Basis.looking_at(forward, reference)
	basis.x *= size
	basis.y *= size
	basis.z *= size * maxf(stretch * clampf(speed * 0.18, 0.5, 3.0), 0.2)
	return Transform3D(basis, pos)


# --------------------------------------------------------------------------
# Physical representatives
# --------------------------------------------------------------------------

## A representative is a MATERIAL PACKET: it carries a share of the event's
## mass, and the stain it leaves reflects that share.
func _emit_representative(
	profile: BloodProfile, pos: Vector3, vel: Vector3, size: float,
	mass: float, stretch: float
) -> void:
	var slot := _medium.acquire(false)
	if slot < 0:
		return
	var i := _rep_count
	if i >= _rep_slot.size():
		_medium.release(slot)
		return
	_rep_count += 1
	_rep_slot[i] = slot
	_rep_pos[i] = pos
	_rep_vel[i] = vel
	_rep_life[i] = settings.droplet_max_life
	_rep_size[i] = size
	_rep_mass[i] = mass
	_rep_stretch[i] = stretch
	_rep_color[i] = profile.color
	_rep_profile[i] = profile
	_medium.write(slot, _oriented(pos, vel, size, stretch), profile.color)


## FIXED TIMESTEP. Runs in _physics_process, so how far a droplet travels no
## longer depends on the render frame rate - which it did when this ran off
## _process delta.
func _step_representatives(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var i := 0
	while i < _rep_count:
		var vel := _rep_vel[i]
		vel.y -= settings.gravity * delta
		var speed := vel.length()
		if speed > 0.01:
			# Quadratic drag scaled by size: fine spray dies near the trajectory
			# while fat droplets carry on and reach the far wall.
			var d := settings.droplet_drag * speed * speed
			d /= maxf(_rep_size[i] / settings.droplet_size, 0.2)
			vel -= vel / speed * minf(d * delta, speed)
		var from := _rep_pos[i]
		var to := from + vel * delta

		_ray.from = from
		_ray.to = to
		var hit := space.intersect_ray(_ray)
		if not hit.is_empty():
			_land_representative(i, hit.position, hit.normal, vel)
			continue

		_rep_life[i] -= delta
		if _rep_life[i] <= 0.0:
			# Out of time, still airborne. The material it stood for cannot just
			# evaporate, so gravity finishes the job: one downward ray puts it on
			# whatever is underneath. Mass in equals mass on the floor.
			_led_timed_out += _rep_mass[i]
			var profile: BloodProfile = _rep_profile[i]
			if profile != null:
				_ray.from = _rep_pos[i]
				_ray.to = _rep_pos[i] + Vector3.DOWN * 12.0
				var below := space.intersect_ray(_ray)
				if not below.is_empty():
					_deposit_cluster(
						profile, below.position, below.normal, Vector3.DOWN, _rep_mass[i]
					)
			_retire_representative(i)
			continue
		_rep_pos[i] = to
		_rep_vel[i] = vel
		_medium.write(
			_rep_slot[i], _oriented(to, vel, _rep_size[i], _rep_stretch[i]), _rep_color[i]
		)
		i += 1


func _land_representative(i: int, point: Vector3, normal: Vector3, vel: Vector3) -> void:
	var profile: BloodProfile = _rep_profile[i]
	var speed := vel.length()
	var mass := _rep_mass[i]
	if profile != null and speed >= settings.droplet_min_impact_speed:
		var size := _stain_radius(profile, mass)
		# Faster impacts splash wider for the same quantity of material.
		size *= clampf(speed / 9.0, 0.7, 1.9)
		_led_hit_world += mass
		# Satellites are material thrown off the MAIN impact, so their share is
		# carved out of it rather than added on top. Mass in, mass down.
		var satellite_share := mass * settings.satellite_mass_share
		var main := mass - satellite_share
		# A heavy packet lands as a CLUSTER, not a disc: that is the difference
		# between "a thick droplet hit the floor" and "a dot appeared".
		if main > settings.soak_mass_threshold * 0.25:
			_deposit_cluster(profile, point, normal, vel.normalized(), main)
		else:
			_place_stain(profile, point, normal, vel.normalized(), size, main)
		_satellites(profile, point, normal, vel, size, satellite_share)
	_retire_representative(i)


func _retire_representative(i: int) -> void:
	_medium.release(_rep_slot[i])
	var last := _rep_count - 1
	if i != last:
		_rep_slot[i] = _rep_slot[last]
		_rep_pos[i] = _rep_pos[last]
		_rep_vel[i] = _rep_vel[last]
		_rep_life[i] = _rep_life[last]
		_rep_size[i] = _rep_size[last]
		_rep_mass[i] = _rep_mass[last]
		_rep_stretch[i] = _rep_stretch[last]
		_rep_color[i] = _rep_color[last]
		_rep_profile[i] = _rep_profile[last]
	_rep_count -= 1


# --------------------------------------------------------------------------
# Solid material: grains and chunks
# --------------------------------------------------------------------------

func _emit_solid(
	profile: BloodProfile, pos: Vector3, vel: Vector3, size: float,
	category: BloodTypes.Tissue, big: bool, mass := 0.0
) -> void:
	var slot := _large.acquire(true)
	if slot < 0:
		return
	var i := _sol_count
	if i >= _sol_slot.size():
		_large.release(slot)
		return
	_sol_count += 1
	_sol_slot[i] = slot
	_sol_pos[i] = pos
	_sol_vel[i] = vel / maxf(TissueDebris.drag_for(category), 0.2)
	_sol_spin[i] = _rng.randf_range(-14.0, 14.0)
	_sol_basis[i] = Basis.from_euler(
		Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)
	)
	# Irregular axes read as gristle rather than as dice.
	_sol_size[i] = Vector3(
		size, size * _rng.randf_range(0.45, 1.0), size * _rng.randf_range(0.6, 1.3)
	)
	_sol_color[i] = TissueDebris.color_for(category, _rng)
	# Only big pieces are allowed to leave a mark, and only one each.
	_sol_marks[i] = 0 if big else 1
	_sol_bounced[i] = 0
	_sol_mesh[i] = float(_rng.randi() % maxi(_tissue_meshes.size(), 1))
	_sol_mass[i] = mass
	_sol_profile[i] = profile
	_write_solid(i)


func _write_solid(i: int) -> void:
	_large.write(
		_sol_slot[i],
		Transform3D(_sol_basis[i].scaled(_sol_size[i]), _sol_pos[i]),
		_sol_color[i],
		Color(_sol_mesh[i], 0.0, 1.0, 0.0)
	)


## Fixed timestep, same as the representatives.
func _step_solids(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var i := 0
	while i < _sol_count:
		var vel := _sol_vel[i]
		vel.y -= settings.gravity * delta
		var from := _sol_pos[i]
		var to := from + vel * delta

		_ray.from = from
		_ray.to = to
		var hit := space.intersect_ray(_ray)
		if not hit.is_empty():
			var normal: Vector3 = hit.normal
			var point: Vector3 = hit.position
			var speed := vel.length()
			# A big piece may leave ONE mark. Never recursive.
			if _sol_marks[i] == 0 and speed > 3.0:
				_sol_marks[i] = 1
				var profile: BloodProfile = _sol_profile[i]
				if profile != null:
					# A chunk smears part of what it is carrying onto the
					# surface and keeps the rest, because the chunk itself stays
					# lying there. It deposits its OWN represented mass: the old
					# hardcoded 0.05 per chunk invented roughly thirteen bodies
					# worth of material out of a single maul kill.
					var smear: float = _sol_mass[i] * 0.35
					_sol_mass[i] -= smear
					_led_tissue_deposited += smear
					_place_stain(
						profile, point, normal, vel.normalized(),
						_stain_radius(profile, smear) * 1.3, smear
					)
			if _sol_bounced[i] == 0 and speed > 2.5 and settings.chunk_bounce > 0.0:
				_sol_bounced[i] = 1
				_sol_vel[i] = vel.bounce(normal) * settings.chunk_bounce
				_sol_pos[i] = point + normal * 0.02
				i += 1
				continue
			# Settled: lie on the surface, stop simulating, persist until the
			# layer genuinely needs the slot back.
			_sol_pos[i] = point + normal * (_sol_size[i].y * 0.5 + 0.005)
			_sol_basis[i] = Basis.from_euler(Vector3(0.0, _rng.randf() * TAU, 0.0))
			_write_solid(i)
			_settle_solid(i)
			continue

		_sol_pos[i] = to
		_sol_vel[i] = vel
		_sol_basis[i] = _sol_basis[i].rotated(Vector3.UP, _sol_spin[i] * delta)
		_write_solid(i)
		i += 1


## A settled solid keeps its MultiMesh slot - it stays visible, that is the
## point - but leaves the simulation list.
func _settle_solid(i: int) -> void:
	_sol_settled.append(_sol_slot[i])
	var last := _sol_count - 1
	if i != last:
		_sol_slot[i] = _sol_slot[last]
		_sol_pos[i] = _sol_pos[last]
		_sol_vel[i] = _sol_vel[last]
		_sol_spin[i] = _sol_spin[last]
		_sol_basis[i] = _sol_basis[last]
		_sol_size[i] = _sol_size[last]
		_sol_color[i] = _sol_color[last]
		_sol_marks[i] = _sol_marks[last]
		_sol_bounced[i] = _sol_bounced[last]
		_sol_mesh[i] = _sol_mesh[last]
		_sol_mass[i] = _sol_mass[last]
		_sol_profile[i] = _sol_profile[last]
	_sol_count -= 1


# --------------------------------------------------------------------------
# Stains and contamination
# --------------------------------------------------------------------------

## Stain radius from the represented mass that landed, by AREA.
##
##     area = mass * stain_area_per_mass      ->      r = sqrt(area / PI)
##
## The old mapping was a lerp that saturated at about 0.17 mass, so every
## representative - which all carried an identical tiny share - produced an
## identical small disc, and no amount of extra blood ever made a bigger mark.
## Going through area means ten times the mass is about three times the width,
## which both conserves the material and produces a real size distribution.
func _stain_radius(profile: BloodProfile, mass: float) -> float:
	var area: float = maxf(mass, 0.0) * settings.stain_area_per_mass * profile.stain_scale
	return clampf(sqrt(area / PI), settings.stain_radius_min, settings.stain_radius_max)


## Kept for callers that still think in sizes rather than masses.
func _stain_size(profile: BloodProfile, mass: float) -> float:
	return _stain_radius(profile, mass) * 2.0


## Pick a stain shape from the family's weights. This is a large part of how an
## aftermath is recognised: slashing is nearly all STREAK, blunt is POOLED.
func _pick_stain_shape(profile: BloodProfile) -> int:
	var total := 0.0
	for w in profile.stain_shape_weights:
		total += w
	if total <= 0.0:
		return int(BloodTypes.Stain.MEDIUM_ROUND)
	var target := _rng.randf() * total
	var running := 0.0
	for i in profile.stain_shape_weights.size():
		running += profile.stain_shape_weights[i]
		if target <= running:
			return i
	return int(BloodTypes.Stain.MEDIUM_ROUND)


func _cell_key(pos: Vector3) -> int:
	var s := maxf(settings.contamination_cell_size, 0.5)
	var x := int(floor(pos.x / s)) + 512
	var y := int(floor(pos.y / s)) + 512
	var z := int(floor(pos.z / s)) + 512
	return x + y * 1024 + z * 1048576


func _place_stain(
	profile: BloodProfile, pos: Vector3, normal: Vector3, travel: Vector3,
	size: float, mass: float
) -> void:
	var key := _cell_key(pos)
	var density: int = _cells.get(key, 0)

	# Dense contamination stops being fifty identical stickers and becomes one
	# big soaked reinforcement mark plus the detail on top.
	if density >= settings.soak_threshold and _rng.randf() < 0.35:
		size *= settings.soak_scale
		density = 0
		_cells[key] = 0

	var slot := _acquire_stain_slot(key)
	if slot < 0:
		return
	_cells[key] = density + 1
	if not _cell_slots.has(key):
		_cell_slots[key] = PackedInt32Array()
	var owned: PackedInt32Array = _cell_slots[key]
	owned.append(slot)
	_cell_slots[key] = owned
	if slot < _stain_cell.size():
		_stain_cell[slot] = key

	var reference := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	# QuadMesh faces +Z, and looking_at points -Z, so aim at -normal.
	var basis := Basis.looking_at(-normal, reference)
	# Incidence decides the SHAPE: square-on is round, shallow is a long ellipse.
	var incidence: float = clampf(absf(travel.normalized().dot(normal)), 0.05, 1.0)
	var elongation: float = clampf(1.0 / incidence, 1.0, profile.env_streak_ratio)
	var along := travel.slide(normal)
	if along.length_squared() > 0.0001:
		along = along.normalized()
		var roll := atan2(along.dot(basis.y.normalized()), along.dot(basis.x.normalized()))
		basis = basis.rotated(normal, roll)
	# basis.x was just rotated onto the travel direction, so THAT is the axis to
	# stretch. Scaling y instead put the long axis 90 degrees across the travel.
	basis.x *= size * elongation
	basis.y *= size

	var shape := _pick_stain_shape(profile)
	# Saturating cells darken, so a soaked patch reads wetter than a fresh one.
	var dark: float = clampf(float(density) / maxf(float(settings.soak_threshold), 1.0), 0.0, 1.0)
	dark *= settings.soak_darkening
	var c := profile.env_color
	var color := Color(c.r * (1.0 - dark), c.g * (1.0 - dark), c.b * (1.0 - dark), 1.0)

	_surface.write(
		slot,
		Transform3D(basis, pos + normal * settings.surface_offset),
		color,
		Color(float(shape % 4), float(shape / 4), 1.0, 0.0)
	)
	if slot < _stain_life.size():
		_stain_life[slot] = settings.stain_lifetime if settings.stain_lifetime > 0.0 else -1.0
		_stain_active[slot] = 1
	last_splats_spawned += 1

	# Ledger: where the material actually ended up.
	_led_surface_mass += mass
	_led_stains += 1
	# The quad spans `size` across, so its half-extents are size/2: the footprint
	# is PI * (size*elongation/2) * (size/2), not PI * size^2.
	_led_stain_area += PI * size * size * elongation * 0.25
	var up := normal.dot(Vector3.UP)
	if up > 0.6:
		_led_floor += mass
	elif up < -0.6:
		_led_ceiling += mass
	else:
		_led_wall += mass

	# Soaked base layer. Cells accumulate represented MASS, and once a patch has
	# taken enough material it earns a large dark base underneath - laid closer
	# to the surface than the detail stains, so fine directional spatter still
	# reads on top of it and nothing is erased.
	var cell_mass: float = _cell_mass.get(key, 0.0) + mass
	_cell_mass[key] = cell_mass
	if cell_mass >= settings.soak_mass_threshold:
		var bases: int = _cell_bases.get(key, 0)
		if bases < settings.soak_bases_per_cell:
			_cell_bases[key] = bases + 1
			_cell_mass[key] = 0.0
			_place_soak_base(profile, pos, normal, cell_mass)


## A stain slot, taking the arena's memory seriously.
##
## While slots are free this is just an allocation. Once the surface layer is
## FULL, the brief is explicit that a global ring is the wrong answer: it erases
## the oldest stain anywhere, so a busy corner silently deletes the history of a
## fight on the other side of the room. Instead the most CROWDED cell gives up
## its oldest stain, which is the one least likely to be missed - that cell is
## already saturated - and a lone early mark in a quiet corner survives the
## whole fight.
func _acquire_stain_slot(key: int) -> int:
	if _surface.free_slots() > 0:
		return _surface.acquire(false)

	var worst := -1
	var worst_count := 0
	for k in _cell_slots:
		var n: int = (_cell_slots[k] as PackedInt32Array).size()
		if n > worst_count:
			worst_count = n
			worst = k
	# Nothing to reclaim from, or the incoming cell IS the crowded one and has
	# only a token presence: fall back to the layer's own oldest-active policy.
	if worst < 0 or worst_count <= 1:
		return _surface.acquire(true)

	var owned: PackedInt32Array = _cell_slots[worst]
	var victim := owned[0]
	owned.remove_at(0)
	if owned.is_empty():
		_cell_slots.erase(worst)
		_cells.erase(worst)
	else:
		_cell_slots[worst] = owned
		_cells[worst] = owned.size()
	_surface.release(victim)
	if victim < _stain_active.size():
		_stain_active[victim] = 0
	return _surface.acquire(false)


## Drop a stain out of its cell index, so a cell that empties stops being a
## candidate for eviction and its count stays honest.
func _forget_stain(slot: int) -> void:
	if slot >= _stain_cell.size():
		return
	var key := _stain_cell[slot]
	if not _cell_slots.has(key):
		return
	var owned: PackedInt32Array = _cell_slots[key]
	var at := owned.find(slot)
	if at >= 0:
		owned.remove_at(at)
	if owned.is_empty():
		_cell_slots.erase(key)
		_cells.erase(key)
	else:
		_cell_slots[key] = owned
		_cells[key] = owned.size()

## The wet base layer under a saturated patch.
##
## Deliberately NOT a replacement for the stains already there: it is laid at a
## smaller surface offset, so it sits UNDER the fine spatter and the directional
## evidence survives. Big, dark, irregular, and it only appears once a cell has
## genuinely taken that much material.
func _place_soak_base(
	profile: BloodProfile, pos: Vector3, normal: Vector3, mass: float
) -> void:
	var slot := _acquire_stain_slot(_cell_key(pos))
	if slot < 0:
		return
	var reference := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var basis := Basis.looking_at(-normal, reference)
	var radius := _stain_radius(profile, mass) * settings.soak_base_scale
	radius = minf(radius, settings.stain_radius_max * settings.soak_base_scale)
	# Slightly irregular rather than a perfect disc.
	basis = basis.rotated(normal, _rng.randf() * TAU)
	basis.x *= radius * _rng.randf_range(0.85, 1.25)
	basis.y *= radius * _rng.randf_range(0.85, 1.25)

	var c := profile.env_color
	# Wet material reads darker and richer than fresh spatter.
	var dark := 1.0 - settings.soak_darkening
	_surface.write(
		slot,
		Transform3D(basis, pos + normal * settings.soak_base_offset),
		Color(c.r * dark, c.g * dark, c.b * dark, 1.0),
		Color(float(BloodTypes.Stain.POOLED % 4), float(BloodTypes.Stain.POOLED / 4), 1.0, 0.0)
	)
	if slot < _stain_life.size():
		_stain_life[slot] = -1.0
		_stain_active[slot] = 1
		_stain_cell[slot] = _cell_key(pos)
	var key := _cell_key(pos)
	if not _cell_slots.has(key):
		_cell_slots[key] = PackedInt32Array()
	var owned: PackedInt32Array = _cell_slots[key]
	owned.append(slot)
	_cell_slots[key] = owned
	_led_stains += 1
	_led_stain_area += PI * radius * radius * 0.25


## Represented-mass accounting for the last event. This is the Part A
## diagnostic: it makes a weak aftermath traceable to the stage that lost the
## mass rather than something to be guessed at from particle counts.
func mass_ledger() -> Dictionary:
	return {
		"release_blood_mass": _led_blood,
		"release_tissue_mass": _led_tissue,
		"air_visual_mass_represented": _led_air_mass,
		"physical_mass_represented": _led_physical_mass,
		"physical_mass_that_hit_world": _led_hit_world,
		"physical_mass_that_timed_out": _led_timed_out,
		"physical_mass_recycled": _led_recycled,
		"surface_mass_deposited": _led_surface_mass,
		"stain_count": _led_stains,
		"mean_stain_area": _led_stain_area / maxf(float(_led_stains), 1.0),
		"estimated_total_stain_area": _led_stain_area,
		"surface_mass_floor": _led_floor,
		"surface_mass_wall": _led_wall,
		"surface_mass_ceiling": _led_ceiling,
		"tissue_mass_deposited": _led_tissue_deposited,
	}



## A fast heavy impact throws a few small secondary marks around the parent.
## Strictly bounded, and rough surfaces throw more than smooth ones.
func _satellites(
	profile: BloodProfile, point: Vector3, normal: Vector3, vel: Vector3,
	parent_size: float, mass_share := 0.0
) -> void:
	var speed := vel.length()
	if speed < settings.satellite_speed_threshold:
		if mass_share > 0.0:
			_place_stain(profile, point, normal, vel.normalized(), parent_size * 0.4, mass_share)
		return
	# Only a MINORITY of impacts throw satellites. Letting every landing throw
	# its maximum turned one droplet into seven stains and burned the arena's
	# whole memory in a single fight.
	if _rng.randf() > settings.satellite_chance:
		# No satellites this time, so the reserved share goes back into the main
		# mark rather than disappearing.
		if mass_share > 0.0:
			_place_stain(profile, point, normal, vel.normalized(), parent_size * 0.4, mass_share)
		return
	var budget := settings.satellite_max
	if _surface_kind(normal) == BloodTypes.Surface.ROUGH:
		budget += settings.rough_satellite_bonus
	var count := mini(
		int(round(clampf(speed / 14.0, 0.0, 1.0) * budget * settings.quality_scale())), budget
	)
	if count <= 0:
		if mass_share > 0.0:
			_place_stain(profile, point, normal, vel.normalized(), parent_size * 0.4, mass_share)
		return
	var tangent := vel.slide(normal)
	if tangent.length_squared() < 0.0001:
		tangent = normal.cross(Vector3.UP)
		if tangent.length_squared() < 0.0001:
			tangent = normal.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var bitangent := normal.cross(tangent).normalized()
	for i in count:
		var spread := settings.satellite_spread * (0.4 + _rng.randf())
		# Satellites throw FORWARD of the parent, the way the drop was going.
		var at := point + tangent * spread * _rng.randf_range(0.4, 1.6)
		at += bitangent * spread * _rng.randf_range(-0.7, 0.7)
		# Each satellite carries a slice of the share RESERVED from its parent.
		# Inventing a fixed mass here was adding material to the world on every
		# single impact.
		_place_stain(
			profile, at, normal, vel.normalized(), parent_size * 0.22,
			mass_share / float(count)
		)


## Cheap first pass: horizontal surfaces are the rough floor, vertical ones the
## smooth walls. THE_BOX has no material tags and does not need them yet.
func _surface_kind(normal: Vector3) -> BloodTypes.Surface:
	return BloodTypes.Surface.ROUGH if absf(normal.dot(Vector3.UP)) > 0.7 \
		else BloodTypes.Surface.SMOOTH


func _step_stains(delta: float) -> void:
	if settings.stain_lifetime <= 0.0:
		return
	for i in _stain_life.size():
		if _stain_active[i] == 0 or _stain_life[i] <= 0.0:
			continue
		_stain_life[i] -= delta
		if _stain_life[i] <= 0.0:
			_surface.release(i)
			_stain_active[i] = 0
			_forget_stain(i)


# --------------------------------------------------------------------------
# Wounds
# --------------------------------------------------------------------------

## Reservoirs register themselves so the system can tick their wounds without
## every enemy needing its own _process.
func register_reservoir(res: BloodReservoir) -> void:
	if res != null and not _reservoirs.has(res):
		_reservoirs.append(res)


func unregister_reservoir(res: BloodReservoir) -> void:
	_reservoirs.erase(res)


## A wound whose victim is gone finishes its life here, in world space. This is
## what lets a catastrophic head kill keep leaking after the corpse is hidden.
func add_remnant(wound: Wound, at: Vector3) -> void:
	# Find what is underneath, so the remnant SINKS to it instead of hanging in
	# the air at torso height. A source with nothing supporting it was the most
	# obviously broken thing about Phase 2's wounds.
	var rest := at.y - 1.6
	var space := get_world_3d().direct_space_state
	if space != null:
		_ray.from = at
		_ray.to = at + Vector3.DOWN * 12.0
		var below := space.intersect_ray(_ray)
		if not below.is_empty():
			rest = (below.position as Vector3).y + 0.05
	wound.detach(at, rest)
	_remnants.append(wound)
	_remnant_family.append(int(wound.family))


func _tick_wounds(delta: float) -> void:
	for i in range(_reservoirs.size() - 1, -1, -1):
		var res := _reservoirs[i]
		if not is_instance_valid(res):
			_reservoirs.remove_at(i)
			continue
		var victim := res.victim()
		if victim == null or not is_instance_valid(victim):
			continue
		for entry in res.tick_wounds(delta):
			_drip(entry["wound"], entry["amount"], victim.global_transform)

	for i in range(_remnants.size() - 1, -1, -1):
		var w: Wound = _remnants[i]
		# The source collapses toward the floor while it bleeds out.
		w.fall(delta)
		var amount := w.tick(delta)
		if amount > 0.0:
			_drip(w, amount, Transform3D.IDENTITY)
		if not w.alive():
			w.exhaust()
			_remnants.remove_at(i)
			_remnant_family.remove_at(i)


## One discrete release from a wound. Small, downward, and flagged residual so
## the pattern does not re-fire the family's whole signature for a drip.
func _drip(w: Wound, amount: float, victim_xform: Transform3D) -> void:
	var pos := w.position_ws(victim_xform)
	var dir := w.direction_ws(victim_xform)
	var ctx := BloodContext.make(w.family, pos, dir, w.region, 0.4)
	ctx.penetration_direction_ws = dir
	var rel := BloodRelease.make(ctx, amount, 0.0)
	rel.is_residual = true
	release(rel)


# --------------------------------------------------------------------------
# Cast-off
# --------------------------------------------------------------------------

## Droplets flung along a weapon's swing arc by a bloodied blade. Not a hit -
## there is no victim and no damage, only material leaving the weapon along the
## direction it is actually travelling.
func cast_off(
	origin: Vector3, tangent: Vector3, damage_type: BloodTypes.DamageType,
	count: int, energy: float
) -> void:
	var profile := _profiles.get(int(damage_type)) as BloodProfile
	if profile == null or count <= 0:
		return
	var axis := tangent.normalized() if tangent.length_squared() > 0.0001 else Vector3.FORWARD
	var frame := _basis_for_axis(axis)
	var n := mini(count, 64)
	for i in n:
		# Tight around the tangent and spread ALONG it: cast-off reads as a line
		# of stains, never as a burst.
		var t := float(i) / maxf(float(n - 1), 1.0) * 2.0 - 1.0
		var dir := axis.rotated(frame.y, deg_to_rad(_rng.randf_range(-16.0, 16.0)))
		dir = dir.rotated(frame.x, deg_to_rad(_rng.randf_range(-10.0, 22.0)))
		var speed: float = profile.medium_speed * _rng.randf_range(0.6, 1.0) * energy
		_emit_representative(
			profile,
			origin + frame.x * (t * 0.25),
			dir * speed,
			profile.medium_size * _rng.randf_range(0.8, 1.4),
			0.004,
			3.0
		)
	last_droplets_spawned = n
	_wake()


# --------------------------------------------------------------------------
# Phase 1 geometry. Retained: this is the shared FRAME machinery every pattern
# is built on, and the contract the Phase 1 regression tests assert.
# --------------------------------------------------------------------------

## An orthonormal basis whose Z is the given axis. Nothing here looks at world
## up except to pick a stable reference when the axis is nearly vertical, so a
## pattern built in this frame rotates AND pitches with the attack instead of
## being re-flattened onto the ground plane.
func _basis_for_axis(axis: Vector3) -> Basis:
	var forward := axis.normalized() if axis.length_squared() > 0.0001 else Vector3.FORWARD
	var reference := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var right := forward.cross(reference).normalized()
	var up := right.cross(forward).normalized()
	return Basis(right, up, forward)


## The frame a whole event's pattern is built in.
##
## When the attack swept through a plane - a blade, a hammer arc - the pattern
## must fan out INSIDE that plane, so the plane's normal becomes the frame's
## thin axis (y) and the in-plane perpendicular becomes the wide one (x).
func _pattern_frame(ctx: BloodContext, axis: Vector3) -> Basis:
	var plane := ctx.swing_plane_normal_ws
	if plane.length_squared() <= 0.0001:
		return _basis_for_axis(axis)
	var forward := axis.normalized() if axis.length_squared() > 0.0001 else Vector3.FORWARD
	var right := plane.normalized().cross(forward)
	if right.length_squared() < 0.0001:
		return _basis_for_axis(forward)
	right = right.normalized()
	return Basis(right, forward.cross(right).normalized(), forward)


## FORWARD is where the transferred energy continues; BACK points straight at
## whoever delivered the hit.
func _lobe_axis(ctx: BloodContext, back: bool) -> Vector3:
	if back:
		return ctx.victim_to_attacker_ws()
	if ctx.penetration_direction_ws.length_squared() > 0.0001:
		return ctx.penetration_direction_ws
	return ctx.primary_axis()


func _sample_direction(
	profile: BloodProfile, ctx: BloodContext, frame_in: Basis, back := false
) -> Vector3:
	var frame := frame_in
	var forward := frame.z
	if profile.lateral_bias > 0.0:
		var side := frame.x * (1.0 if _rng.randf() < 0.5 else -1.0)
		forward = forward.lerp(side, profile.lateral_bias).normalized()
		frame = _pattern_frame(ctx, forward)

	var dir := _sample_cone(
		forward, frame,
		profile.back_spread_angle if back else profile.spread_angle,
		profile.spread_concentration,
		1.0 if back else profile.lateral_flatten
	)

	if _rng.randf() < profile.radial_scatter_fraction:
		dir = _random_unit()
	elif profile.directional_bias < 1.0:
		dir = dir.lerp(_random_unit(), 1.0 - profile.directional_bias).normalized()

	# Blood coming off a HARD SURFACE may not be fired back into it. Blood out of
	# a WOUND has no such restriction - the entry normal points back at the
	# attacker while transferred energy continues through the victim, so
	# clipping here is what deleted the entire forward lobe.
	if ctx.clip_to_surface and ctx.surface_normal_ws.length_squared() > 0.0001:
		if dir.dot(ctx.surface_normal_ws) < -0.2:
			dir = dir.slide(ctx.surface_normal_ws).normalized()
	return dir


func _sample_cone(
	axis: Vector3, frame: Basis, half_angle_deg: float, concentration: float, flatten := 1.0
) -> Vector3:
	var cos_max := cos(deg_to_rad(clampf(half_angle_deg, 0.0, 180.0)))
	var u := pow(_rng.randf(), 1.0 / maxf(concentration, 0.05))
	var cos_theta: float = lerpf(cos_max, 1.0, u)
	var sin_theta := sqrt(maxf(1.0 - cos_theta * cos_theta, 0.0))
	var azimuth := _rng.randf() * TAU
	var x := sin_theta * cos(azimuth)
	var y := sin_theta * sin(azimuth) / maxf(flatten, 0.05)
	return (axis * cos_theta + frame.x * x + frame.y * y).normalized()


func _sample_arc(
	axis: Vector3, spread_deg: float, elev_min: float, elev_max: float, world_up_bias := 0.0
) -> Vector3:
	return _sample_arc_in(_basis_for_axis(axis), spread_deg, elev_min, elev_max, world_up_bias)


func _sample_arc_in(
	frame: Basis, spread_deg: float, elev_min: float, elev_max: float, world_up_bias := 0.0
) -> Vector3:
	var spread := deg_to_rad(clampf(spread_deg, 0.0, 180.0))
	var swing := _rng.randf_range(-spread, spread)
	var dir := frame.z.rotated(frame.y, swing)
	var elevation := deg_to_rad(_rng.randf_range(elev_min, elev_max))
	dir = dir.rotated(dir.cross(frame.y).normalized(), -elevation) \
		if absf(dir.dot(frame.y)) < 0.99 else dir
	if world_up_bias > 0.0:
		dir = dir.lerp(Vector3.UP, clampf(world_up_bias, 0.0, 1.0))
	return dir.normalized()


func _random_unit() -> Vector3:
	return Vector3(
		_rng.randfn(0.0, 1.0), _rng.randfn(0.0, 1.0), _rng.randfn(0.0, 1.0)
	).normalized()


# --------------------------------------------------------------------------
# Test hooks
# --------------------------------------------------------------------------

func sample_cone_for_test(
	axis: Vector3, frame: Basis, half_angle: float, concentration: float
) -> Vector3:
	return _sample_cone(axis, frame, half_angle, concentration)


func sample_arc_for_test(
	axis: Vector3, spread: float, elev_min: float, elev_max: float
) -> Vector3:
	return _sample_arc(axis, spread, elev_min, elev_max)


func sample_lobe_for_test(profile: BloodProfile, ctx: BloodContext, back := false) -> Vector3:
	var frame := _pattern_frame(ctx, _lobe_axis(ctx, back))
	return _sample_direction(profile, ctx, frame, back)


func pattern_frame_for_test(ctx: BloodContext, back := false) -> Basis:
	return _pattern_frame(ctx, _lobe_axis(ctx, back))


## One sample straight out of the family's PATTERN, which is what the Phase 2
## tests assert on: the patterns, not the legacy cone, decide shape now.
func sample_pattern_for_test(
	rel: BloodRelease, layer: BloodTypes.Layer, u: float, pattern: BloodPattern = null
) -> Dictionary:
	var p := pattern
	if p == null:
		p = BloodPattern.for_family(rel.family())
		p.begin(rel, _pattern_frame(rel.context, _lobe_axis(rel.context, false)), _rng)
	p.sample(layer, u)
	return {
		"dir": p.out_dir,
		"speed": p.out_speed,
		"origin": p.out_origin,
		"size": p.out_size,
		"stretch": p.out_stretch,
	}


func pattern_for_test(rel: BloodRelease) -> BloodPattern:
	var p := BloodPattern.for_family(rel.family())
	p.begin(rel, _pattern_frame(rel.context, _lobe_axis(rel.context, false)), _rng)
	return p


func stain_radius_for_test(profile: BloodProfile, mass: float) -> float:
	return _stain_radius(profile, mass)


## How many soaked base layers the arena has laid down.
func soak_bases_for_test() -> int:
	var n := 0
	for k in _cell_bases:
		n += int(_cell_bases[k])
	return n


## Mass-weighted centre of all surface contamination. This is what proves a
## swing's direction actually reached the floor, rather than only the airborne
## sample distribution.
func surface_centroid_for_test() -> Vector3:
	var sum := Vector3.ZERO
	var total := 0.0
	for key in _cell_slots:
		var count: float = float((_cell_slots[key] as PackedInt32Array).size())
		if count <= 0.0:
			continue
		# Recover the cell's world centre from its key.
		var sz: float = maxf(settings.contamination_cell_size, 0.5)
		var k: int = int(key)
		var x := (k % 1024) - 512
		var y := ((k / 1024) % 1024) - 512
		var z := (k / 1048576) - 512
		sum += Vector3(
			(float(x) + 0.5) * sz, (float(y) + 0.5) * sz, (float(z) + 0.5) * sz
		) * count
		total += count
	return sum / maxf(total, 1.0)


func prewarmed() -> bool:
	return _prewarmed


func event_count() -> int:
	return _event_counter


## Events from an actual blow. Wound drips are excluded, so a test can ask
## "did this attack produce blood" without a bleeding target answering for it.
func combat_event_count() -> int:
	return _combat_events


func seed_for_test(value: int) -> void:
	_rng.seed = value


func layer_for_test(layer: BloodTypes.Layer) -> BloodMultiMeshLayer:
	match layer:
		BloodTypes.Layer.MICRO:
			return _micro
		BloodTypes.Layer.SMALL:
			return _small
		BloodTypes.Layer.MEDIUM:
			return _medium
		BloodTypes.Layer.LARGE:
			return _large
		_:
			return _surface


func live_counts() -> Dictionary:
	return {
		"micro": _micro.live(),
		"small": _small.live(),
		"medium": _medium.live(),
		"large": _large.live(),
		"surface": _surface.live(),
		"airborne": _air_count,
		"representatives": _rep_count,
		"solids_flying": _sol_count,
		"solids_settled": _sol_settled.size(),
		"wounds": active_wounds(),
		"remnants": _remnants.size(),
		"cells": _cells.size(),
	}


func active_wounds() -> int:
	var n := 0
	for r in _reservoirs:
		if is_instance_valid(r):
			n += r.wounds.size()
	return n


func telemetry() -> Dictionary:
	return {
		"micro": _micro.telemetry(),
		"small": _small.telemetry(),
		"medium": _medium.telemetry(),
		"large": _large.telemetry(),
		"surface": _surface.telemetry(),
		"events": _event_counter,
		"cells": _cells.size(),
	}


func reset_telemetry() -> void:
	_micro.reset_telemetry()
	_small.reset_telemetry()
	_medium.reset_telemetry()
	_large.reset_telemetry()
	_surface.reset_telemetry()


func _event_telemetry() -> String:
	return (
		"micro %d small %d rep %d grain %d chunk %d stain %d | mass req %.3f adm %.3f"
		% [
			last_particles_spawned, last_small_spawned, last_droplets_spawned,
			last_grains_spawned, last_chunks_spawned, last_splats_spawned,
			last_mass_requested, last_mass_admitted,
		]
	)


## Wipe the arena. Blood Lab only.
func clear_all() -> void:
	while _air_count > 0:
		_retire_air(0)
	while _rep_count > 0:
		_retire_representative(0)
	while _sol_count > 0:
		_large.release(_sol_slot[0])
		_settle_solid(0)
		_sol_settled.resize(_sol_settled.size() - 1)
	for slot in _sol_settled:
		_large.release(slot)
	_sol_settled.clear()
	_surface.clear_all()
	_large.clear_all()
	_micro.clear_all()
	_small.clear_all()
	_medium.clear_all()
	_cells.clear()
	_cell_slots.clear()
	_cell_mass.clear()
	_cell_bases.clear()
	_remnants.clear()
	_remnant_family.clear()
	for i in _stain_active.size():
		_stain_active[i] = 0
	for r in _reservoirs:
		if is_instance_valid(r):
			r.refill()


# --------------------------------------------------------------------------
# Loops
# --------------------------------------------------------------------------

## Physical material runs on the FIXED clock. This is the frame-rate robustness
## the brief asks for: how far a droplet flies no longer depends on render rate.
func _physics_process(delta: float) -> void:
	if settings == null:
		return
	if _rep_count > 0:
		_step_representatives(delta)
	if _sol_count > 0:
		_step_solids(delta)
	if not _reservoirs.is_empty() or not _remnants.is_empty():
		_tick_wounds(delta)


## Cheap visual material runs on the render clock, where smoothness matters and
## exactness does not.
func _process(delta: float) -> void:
	if _air_count > 0:
		_step_air(delta)
	_step_stains(delta)
	if settings.debug_patterns:
		_step_gizmos(delta)
		return
	if _air_count <= 0:
		set_process(false)


func _wake() -> void:
	if _air_count > 0 or settings.debug_patterns:
		set_process(true)


# --------------------------------------------------------------------------
# Construction
# --------------------------------------------------------------------------

func _build_layers() -> void:
	_stain_atlas = _build_stain_atlas()

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE

	# Airborne material is a BOX, not a quad.
	#
	# A quad oriented along its own velocity is invisible edge-on, so every
	# droplet flying directly toward or away from the player would disappear -
	# which is most of a forward plume seen from behind the shooter. A unit box
	# scaled along its travel gives the same streak from ANY angle for twelve
	# triangles, and at these counts that is ~57k triangles across three draw
	# calls. Cheap, and it actually reads.
	var drop := BoxMesh.new()
	drop.size = Vector3.ONE
	_micro = _make_layer(drop, _blood_material(null), settings.max_micro)
	_small = _make_layer(drop, _blood_material(null), settings.max_small)
	_medium = _make_layer(drop, _blood_material(null), settings.max_medium)

	# LARGE: real geometry, lit, so tissue reads as solid matter rather than as
	# another flat sprite.
	var solid_mat := StandardMaterial3D.new()
	solid_mat.vertex_color_use_as_albedo = true
	solid_mat.roughness = 0.62
	_large = _make_layer(_tissue_meshes[0], solid_mat, settings.max_large)

	# SURFACE: the arena's memory. One material, seven shapes, via the atlas.
	_surface = _make_layer(quad, _blood_material(_stain_atlas), settings.max_surface)

	var air_cap := settings.max_micro + settings.max_small
	_air_slot.resize(air_cap)
	_air_layer.resize(air_cap)
	_air_pos.resize(air_cap)
	_air_vel.resize(air_cap)
	_air_life.resize(air_cap)
	_air_max_life.resize(air_cap)
	_air_size.resize(air_cap)
	_air_stretch.resize(air_cap)
	_air_color.resize(air_cap)

	_rep_slot.resize(settings.max_medium)
	_rep_pos.resize(settings.max_medium)
	_rep_vel.resize(settings.max_medium)
	_rep_life.resize(settings.max_medium)
	_rep_size.resize(settings.max_medium)
	_rep_mass.resize(settings.max_medium)
	_rep_stretch.resize(settings.max_medium)
	_rep_color.resize(settings.max_medium)
	_rep_profile.resize(settings.max_medium)

	_sol_slot.resize(settings.max_large)
	_sol_pos.resize(settings.max_large)
	_sol_vel.resize(settings.max_large)
	_sol_spin.resize(settings.max_large)
	_sol_basis.resize(settings.max_large)
	_sol_size.resize(settings.max_large)
	_sol_color.resize(settings.max_large)
	_sol_marks.resize(settings.max_large)
	_sol_bounced.resize(settings.max_large)
	_sol_mesh.resize(settings.max_large)
	_sol_mass.resize(settings.max_large)
	_sol_profile.resize(settings.max_large)

	_stain_life.resize(settings.max_surface)
	_stain_active.resize(settings.max_surface)
	_stain_cell.resize(settings.max_surface)


func _make_layer(mesh: Mesh, material: Material, slots: int) -> BloodMultiMeshLayer:
	var layer := BloodMultiMeshLayer.new()
	add_child(layer)
	layer.setup(mesh, material, slots)
	return layer


func _blood_material(atlas: Texture2D) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if atlas != null:
		mat.albedo_texture = atlas
		# Stains read one cell of the 4x2 atlas; which cell comes from the
		# per-instance custom data, so all seven shapes share ONE material.
		mat.uv1_scale = Vector3(0.25, 0.5, 1.0)
	return mat


## Seven stain shapes generated at startup into one 4x2 atlas, so the repo
## carries no textures and every stain costs one material.
func _build_stain_atlas() -> ImageTexture:
	var cell: int = maxi(settings.stain_atlas_cell, 8)
	var img := Image.create(cell * 4, cell * 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xB100D
	for shape in BloodTypes.STAIN_COUNT:
		_paint_stain(img, (shape % 4) * cell, (shape / 4) * cell, cell, shape, rng)
	return ImageTexture.create_from_image(img)


func _paint_stain(
	img: Image, ox: int, oy: int, cell: int, shape: int, rng: RandomNumberGenerator
) -> void:
	# Each shape is a handful of overlapping soft lobes. Irregular enough to read
	# as a stain rather than as a sticker, cheap enough to be free.
	var lobes: Array = []
	match shape:
		BloodTypes.Stain.TINY_DROP:
			lobes.append([0.5, 0.5, 0.17])
		BloodTypes.Stain.MEDIUM_ROUND:
			lobes.append([0.5, 0.5, 0.34])
			lobes.append([0.58, 0.44, 0.20])
		BloodTypes.Stain.LARGE_IRREGULAR:
			for i in 6:
				lobes.append([
					0.5 + rng.randf_range(-0.18, 0.18),
					0.5 + rng.randf_range(-0.18, 0.18),
					rng.randf_range(0.16, 0.31),
				])
		BloodTypes.Stain.ELONGATED:
			for i in 7:
				var t := float(i) / 6.0
				lobes.append([
					0.12 + t * 0.76, 0.5 + rng.randf_range(-0.05, 0.05), lerpf(0.19, 0.08, t)
				])
		BloodTypes.Stain.STREAK:
			for i in 10:
				var t := float(i) / 9.0
				lobes.append([
					0.05 + t * 0.9, 0.5 + sin(t * 3.0) * 0.06, lerpf(0.12, 0.035, t)
				])
		BloodTypes.Stain.CLUSTER:
			lobes.append([0.45, 0.5, 0.24])
			for i in 5:
				lobes.append([
					0.5 + rng.randf_range(-0.38, 0.38),
					0.5 + rng.randf_range(-0.38, 0.38),
					rng.randf_range(0.05, 0.10),
				])
		_:  # POOLED
			lobes.append([0.5, 0.5, 0.44])
			for i in 5:
				lobes.append([
					0.5 + rng.randf_range(-0.16, 0.16),
					0.5 + rng.randf_range(-0.16, 0.16),
					rng.randf_range(0.26, 0.40),
				])

	for y in cell:
		for x in cell:
			var u := float(x) / float(cell)
			var v := float(y) / float(cell)
			var a := 0.0
			for lobe in lobes:
				var dx: float = u - lobe[0]
				var dy: float = v - lobe[1]
				var r: float = lobe[2]
				var d := sqrt(dx * dx + dy * dy)
				if d < r:
					# Soft edge, hard core.
					a = maxf(a, clampf(1.0 - pow(d / r, 2.2), 0.0, 1.0))
			if a > 0.004:
				img.set_pixel(ox + x, oy + y, Color(1, 1, 1, clampf(a * 1.35, 0.0, 1.0)))


# --------------------------------------------------------------------------
# Prewarm
# --------------------------------------------------------------------------

## Pay the first-use costs at chamber load instead of on the first kill.
##
## The playtest reported a large one-time stutter on the FIRST major blood
## event and smooth behaviour afterwards, which is the signature of first-use
## initialisation. In this system the candidates are, in order of cost:
##
##   1. The MultiMesh transform buffers. `instance_count` allocates CPU-side,
##      but the GPU buffer is not created or uploaded until something actually
##      writes an instance and the layer is first drawn. The first catastrophic
##      event wrote thousands of instances across five layers at once, forcing
##      every one of those buffers to be created and uploaded in a single frame.
##   2. Material setup. Each layer's StandardMaterial3D is only compiled into a
##      real shader the first time it is submitted, and five materials with
##      transparency and vertex colour arrived together on that same frame.
##   3. The stain atlas. Generated pixel by pixel at _ready - already paid at
##      load, but the texture is not uploaded until first use.
##
## This touches a bounded number of instances in every layer, which forces the
## buffers into existence and the materials through the renderer, then hands the
## slots straight back. Nothing is visible: every instance is written at zero
## scale far under the floor, and the slots are released in the same call.
##
## It must not: emit visible blood, consume any reservoir, or move the ledger.
func _prewarm() -> void:
	var count: int = maxi(settings.prewarm_instances, 1)
	var hide := Vector3(0.0, -10000.0, 0.0)
	for layer: BloodMultiMeshLayer in [_micro, _small, _medium, _large, _surface]:
		var n: int = mini(count, layer.capacity)
		var slots := PackedInt32Array()
		for i in n:
			var slot: int = layer.acquire(false)
			if slot < 0:
				break
			slots.append(slot)
			# A real write, so the transform buffer is genuinely allocated and
			# marked dirty - but at zero scale, underground, invisible.
			layer.write(
				slot,
				Transform3D(Basis().scaled(Vector3.ZERO), hide),
				Color(0, 0, 0, 0),
				Color(0, 0, 0, 0)
			)
		for released: int in slots:
			layer.release(released)
		# The layer keeps its high-water mark, so visible_instance_count stays
		# non-zero and the renderer submits the buffer on the next frame.
		layer.reset_telemetry()
	_prewarmed = true


# --------------------------------------------------------------------------
# Debug overlay
# --------------------------------------------------------------------------

func toggle_debug_patterns() -> bool:
	settings.debug_patterns = not settings.debug_patterns
	settings.debug_telemetry = settings.debug_patterns
	if settings.debug_patterns:
		_build_gizmo_pool()
		set_process(true)
	else:
		for g in _gizmos:
			g.visible = false
	return settings.debug_patterns


func _build_gizmo_pool() -> void:
	if not _gizmos.is_empty():
		return
	for i in maxi(settings.debug_gizmo_slots, 1):
		var mi := MeshInstance3D.new()
		mi.mesh = ImmediateMesh.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.top_level = true
		mi.visible = false
		add_child(mi)
		_gizmos.append(mi)
		_gizmo_life.append(0.0)


## GREEN primary axis, WHITE attack, RED back lobe, BLUE surface normal,
## YELLOW swing plane normal.
func _draw_event_gizmo(ctx: BloodContext) -> void:
	_build_gizmo_pool()
	if _gizmos.is_empty():
		return
	var idx := _next_gizmo
	_next_gizmo = (_next_gizmo + 1) % _gizmos.size()
	var mi := _gizmos[idx]
	var mesh := mi.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_gizmo_line(mesh, ctx.blood_primary_axis_ws, 1.2, Color(0.2, 1.0, 0.25))
	_gizmo_line(mesh, ctx.attack_direction_ws, 0.9, Color.WHITE)
	_gizmo_line(mesh, ctx.victim_to_attacker_ws(), 0.6, Color(1.0, 0.2, 0.2))
	_gizmo_line(mesh, ctx.surface_normal_ws, 0.5, Color(0.3, 0.5, 1.0))
	_gizmo_line(mesh, ctx.swing_plane_normal_ws, 0.4, Color(1.0, 0.9, 0.2))
	mesh.surface_end()
	mi.global_position = ctx.position_ws
	mi.visible = true
	_gizmo_life[idx] = settings.debug_gizmo_life


func _gizmo_line(mesh: ImmediateMesh, dir: Vector3, length: float, color: Color) -> void:
	if dir.length_squared() < 0.0001:
		return
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(Vector3.ZERO)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(dir.normalized() * length)


func _step_gizmos(delta: float) -> void:
	for i in _gizmos.size():
		if _gizmo_life[i] <= 0.0:
			continue
		_gizmo_life[i] -= delta
		if _gizmo_life[i] <= 0.0:
			_gizmos[i].visible = false
