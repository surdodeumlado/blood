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
##   TRAJECTORIES PAINT THE ROOM. SMALL and MEDIUM representatives fly, collide with real
##   static geometry at a fixed timestep and stain wherever they land.
##
## Instance/simulation arrays are preallocated; diagnostic maps are bounded.
## Events never allocate one node per droplet.

const GROUP := &"blood_system"

## Stain atlas layout. Seven shapes in a 4x2 grid.
const ATLAS_COLS := 4
const ATLAS_ROWS := 2

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
var _led_runoff_mass := 0.0
## FINAL VISIBLE longest dimension of every mark this event laid, in metres, so
## readability can be judged from what is on screen rather than from a logical
## radius. Developer diagnostics only.
var _led_extents: PackedFloat32Array = PackedFloat32Array()
## Coarse occupancy grid for approximate UNIQUE coverage - summing every mark's
## area counts the same square metre once per overlapping mark, which is how a
## visibly clean room reported hundreds of square metres.
var _coverage_cells: Dictionary = {}

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

# --- Cosmetic MICRO mist: no collision; mass represented by coarse probes ---
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

# --- Physical SMALL + MEDIUM representatives: collide, stain on landing ---
var _rep_slot: PackedInt32Array = PackedInt32Array()
var _rep_pos: PackedVector3Array = PackedVector3Array()
var _rep_vel: PackedVector3Array = PackedVector3Array()
var _rep_life: PackedFloat32Array = PackedFloat32Array()
var _rep_size: PackedFloat32Array = PackedFloat32Array()
var _rep_mass: PackedFloat32Array = PackedFloat32Array()
var _rep_stretch: PackedFloat32Array = PackedFloat32Array()
var _rep_color: PackedColorArray = PackedColorArray()
var _rep_profile: Array[BloodProfile] = []
## Simulation priority, computed once per frame. See _step_representatives.
var _rep_rank: PackedByteArray = PackedByteArray()
var _rep_count := 0

# Physical equivalent size is independent of the mass of the represented parcel.
var _rep_previous := PackedVector3Array()
var _rep_diameter := PackedFloat32Array()
var _rep_kind := PackedByteArray()
var _rep_layer := PackedByteArray()
var _rep_generation := PackedByteArray()
var _rep_exposure := PackedFloat32Array()
var _rep_age := PackedFloat32Array()
var _rep_id := PackedInt64Array()
var _rep_parent := PackedInt64Array()
var _rep_event := PackedInt64Array()
var _rep_flags := PackedByteArray()
var _rep_wait := PackedFloat32Array()
var _drop_serial := 0
var _stain_serial := 0
var _causal_drop := -1
var _causal_event := -1
var _stain_ids := PackedInt64Array()
var _stain_drop_ids := PackedInt64Array()
var _stain_event_ids := PackedInt64Array()
## Bounded diagnostic history; disabled unless requested by developer fixtures.
var record_causality := false
var causal_records: Array[Dictionary] = []
var material_stats := {"collisions": 0, "breakups": 0, "ligaments": 0, "escaped_mass": 0.0, "size_warnings": 0}
var _gravity := Vector3.DOWN * 9.8
var _smooth: BloodSurfaceResponse = preload("res://data/blood/surfaces/smooth.tres")
var _rough: BloodSurfaceResponse = preload("res://data/blood/surfaces/rough.tres")
var _porous: BloodSurfaceResponse = preload("res://data/blood/surfaces/porous.tres")
var _wet_patches: Dictionary = {}
var _retained_patch_mass := 0.0
## Material that finished soaking INTO a surface and whose patch has since been
## retired. Absorption is a real, terminal destination, so it must survive the
## bookkeeping object that happened to be tracking it - otherwise retiring a
## dried-out patch silently deletes the mass it absorbed.
var _absorbed_retired := 0.0
var _impact_response: Dictionary = {}
var _deposit_surface: BloodSurfaceResponse
var _suppress_runoff := false
var _runoff_last_mark := PackedVector3Array()
var _runoff_surface: Array[BloodSurfaceResponse] = []
var _runoff_drop_id := PackedInt64Array()
var _runoff_event_id := PackedInt64Array()

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
var _sol_category: PackedByteArray = PackedByteArray()
## Represented TISSUE mass each solid stands for. A chunk that marks a surface
## deposits from this, instead of the hardcoded constant it used to invent.
var _sol_mass: PackedFloat32Array = PackedFloat32Array()
var _sol_profile: Array[BloodProfile] = []
var _sol_count := 0
var _sol_age := PackedFloat32Array()
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
var _stain_birth := PackedFloat32Array()
var _fade_slots := PackedInt32Array()
var _fade_left := PackedFloat32Array()
var _fade_duration := PackedFloat32Array()
var _fade_count := 0
var _fade_scan := 0

# --- Wall runoff: rivulets creeping down vertical surfaces ---
var _runoff_pos: PackedVector3Array = PackedVector3Array()
var _runoff_dir: PackedVector3Array = PackedVector3Array()
var _runoff_normal: PackedVector3Array = PackedVector3Array()
var _runoff_mass: PackedFloat32Array = PackedFloat32Array()
var _runoff_age: PackedFloat32Array = PackedFloat32Array()
var _runoff_since: PackedFloat32Array = PackedFloat32Array()
var _runoff_speed: PackedFloat32Array = PackedFloat32Array()
## The mass a rivulet STARTED with, so it can taper as it spends it.
var _runoff_start_mass: PackedFloat32Array = PackedFloat32Array()
var _runoff_profile: Array[BloodProfile] = []
var _runoff_count := 0

# --- Wound scheduling ---
var _reservoirs: Array[BloodReservoir] = []
## Wounds whose victim is gone, finishing out in world space.
var _remnants: Array[Wound] = []
var _remnant_family: Array[int] = []

var _stain_atlas: ImageTexture
## MEASURED visible extent of each atlas cell, as a fraction of the cell.
## Filled in when the atlas is generated by scanning the pixels it just drew -
## not guessed. A TINY_DROP occupies about a third of its cell, so a quad sized
## to the requested footprint would render a mark a third of the asked-for size.
var _atlas_occupancy: PackedVector2Array = PackedVector2Array()
## Fraction of the cell with meaningful alpha, for coverage diagnostics.
var _atlas_fill: PackedFloat32Array = PackedFloat32Array()
var _ray: PhysicsRayQueryParameters3D

# --- Debug ---
var _gizmos: Array[MeshInstance3D] = []
var _gizmo_life: Array[float] = []
var _next_gizmo := 0
var _prewarmed := false
## Opt-in stage timings. Counters remain cheap; no per-drop log output.
var profile_stages := false
var stage_us: Dictionary = {}
var query_count := 0
## Legacy single-operation fixtures may bypass scheduling, never support checks.
var synchronous_test_mode := false
var manual_budget_clock := false
var frame_usage := {"queries": 0, "drops": 0, "solids": 0, "micro": 0, "stains": 0, "runoff": 0, "wall_drops": 0, "audio": 0, "solid_queries": 0}
var peak_frame_usage: Dictionary = {}
var _budget_frame := -1
var _clock := 0.0
var _density := 1.0
var _per_job_share := 1.0
var _emitting_stage := -1
var _presentation_queue: Array[Dictionary] = []
var _contacts: Dictionary = {}
var _coarse_jobs: Array[Dictionary] = []
var _pending_remnants: Array[Wound] = []
var _draining_contacts := false
var _contact_hit: Dictionary = {}
var _contact_residual := false
var _contact_catastrophic := false
var _current_event_catastrophic := false
var _emission_flags := 0
var _eviction_cell := -1
var _eviction_frame := -1
var _support: BloodSurfaceSupport
var _audio: BloodImpactAudioAccumulator
var _pools: Dictionary = {}
var _active_wet_key := ""
## Keys drained out of _wet_patches at the end of the step. See _step_wet_patches.
var _wet_retire: Array = []
## Iteration order for the time-sliced scan, plus where the slice resumes.
var _wet_keys: Array = []
var _wet_cursor := 0
var _runoff_patch: Array[String] = []
var _last_surface_slot := -1
var queued_blood_mass := 0.0
var accepted_blood_mass := 0.0
var accepted_tissue_mass := 0.0
var coalesced_contacts := 0
var _debug_label: Label
var _debug_mesh: ImmediateMesh

func _flush_presentation() -> void:
	if _presentation_queue.is_empty(): return
	_presentation_queue.sort_custom(func(a: Dictionary, b: Dictionary): return a.priority > b.priority)
	var jobs := _presentation_queue.size()
	_per_job_share = 1.0 / maxf(jobs, 1)
	for job in _presentation_queue:
		var rel: BloodRelease = job.release
		if job.stage == 0:
			var neighbors := 0
			for other in _presentation_queue:
				if (other.release as BloodRelease).position_ws().distance_to(rel.position_ws()) <= settings.stability.event_neighborhood_m: neighbors += 1
			job.density = maxf(settings.stability.minimum_sampling, 1.0 / (1.0 + settings.stability.adaptive_pressure * (neighbors - 1)))
			if job.distance > settings.stability.importance_distance_m: job.density *= settings.stability.distant_sampling
		_density = job.density
		_emitting_stage = job.stage
		_release_now(rel)
		job.stage += 1
	for i in range(_presentation_queue.size() - 1, -1, -1):
		if _presentation_queue[i].stage >= 3:
			queued_blood_mass -= (_presentation_queue[i].release as BloodRelease).blood_mass
			_presentation_queue.remove_at(i)
	_density = 1.0
	_per_job_share = 1.0
	_emitting_stage = -1
	_current_event_catastrophic = false
	_emission_flags = 0

func _queue_coarse(profile: BloodProfile, origin: Vector3, dir: Vector3, mass: float, event_id: int, residual := false, catastrophic := false) -> void:
	if mass <= 0 or profile == null: return
	if _coarse_jobs.size() >= settings.stability.max_coarse_jobs:
		# A bounded pending stock. Coalesce only the presentation, retain all mass.
		var nearest := 0
		var distance := INF
		for i in _coarse_jobs.size():
			var d: float = _coarse_jobs[i].origin.distance_squared_to(origin)
			if d < distance: nearest = i; distance = d
		_coarse_jobs[nearest].mass += mass
		_coarse_jobs[nearest].residual = _coarse_jobs[nearest].residual and residual
		_coarse_jobs[nearest].catastrophic = _coarse_jobs[nearest].catastrophic or catastrophic
		return
	_coarse_jobs.append({"profile": profile, "origin": origin, "dir": dir.normalized(), "mass": mass, "event": event_id, "residual": residual, "catastrophic": catastrophic})

func _drain_coarse() -> void:
	var processed := 0
	while not _coarse_jobs.is_empty() and can_query(12) and processed < 12:
		var job: Dictionary = _coarse_jobs.pop_front()
		_ray.from = job.origin
		_ray.to = job.origin + job.dir * settings.cloud_probe_distance
		var hit := _query()
		if hit.is_empty():
			_ray.from = job.origin + job.dir * minf(settings.cloud_probe_distance, 2.0)
			_ray.to = _ray.from + Vector3.DOWN * 20.0
			hit = _query()
		if hit.is_empty():
			material_stats.escaped_mass += job.mass
		else:
			_queue_contact(job.profile, hit.position, hit.normal, job.dir, _stain_radius(job.profile, job.mass), job.mass,
				{}, hit, -1, job.event, job.residual, job.catastrophic)
		processed += 1

func _contact_key(pos: Vector3, normal: Vector3, owner_id: int) -> String:
	return "%d:%s:%s" % [owner_id, Vector3i((pos / settings.stability.aggregation_cell_m).floor()), Vector3i((normal * 20).round())]

func _queue_contact(profile: BloodProfile, pos: Vector3, normal: Vector3, travel: Vector3, radius: float, mass: float, response: Dictionary, hit: Dictionary, drop: int, event_id: int, residual := false, catastrophic := false) -> void:
	var owner_id := int(hit.get("collider_id", 0))
	var key := _contact_key(pos, normal, owner_id)
	if not _contacts.has(key):
		if _contacts.size() >= settings.stability.max_pending_contacts:
			_queue_coarse(profile, pos + normal * 0.03, Vector3.DOWN, mass, event_id, residual, catastrophic)
			return
		_contacts[key] = {"profile": profile, "pos": pos, "normal": normal, "travel": travel, "radius": radius,
			"mass": 0.0, "response": response.duplicate(), "hit": hit.duplicate(), "drop": drop, "event": event_id,
			"residual": residual, "catastrophic": catastrophic, "count": 0, "age": _clock, "terminal": _suppress_runoff,
			"surface": _deposit_surface if _deposit_surface != null else surface_response(hit.get("collider"), normal)}
	var c: Dictionary = _contacts[key]
	# Keep an actual hit point as anchor; never average contacts across an edge.
	if mass > c.mass:
		c.pos = pos; c.normal = normal; c.travel = travel; c.hit = hit.duplicate(); c.response = response.duplicate()
	c.mass += mass
	c.count += 1
	c.radius = maxf(c.radius, radius)
	c.catastrophic = c.catastrophic or catastrophic
	c.residual = c.residual and residual
	if c.count > 1: coalesced_contacts += 1
	_record_causal({"action": "contact_cluster", "cluster": key, "drop_id": drop, "event_id": event_id, "mass": mass})

func _drain_contacts() -> void:
	var keys := _contacts.keys()
	keys.sort_custom(func(a: String, b: String): return float(_contacts[a].mass) + (_clock - float(_contacts[a].age)) * 0.02 > float(_contacts[b].mass) + (_clock - float(_contacts[b].age)) * 0.02)
	for key in keys:
		if frame_usage.stains >= settings.stability.stain_writes_per_frame - 4 or not can_query(1 + 8 * (settings.stability.max_support_shrinks + 1)): break
		var c: Dictionary = _contacts[key]
		_draining_contacts = true
		_contact_hit = c.hit
		_contact_residual = c.residual
		_contact_catastrophic = c.catastrophic
		_suppress_runoff = c.terminal
		_impact_response = c.response
		_causal_drop = c.drop
		_causal_event = c.event
		_deposit_surface = c.surface
		var radius := maxf(c.radius, _stain_radius(c.profile, c.mass))
		_place_stain(c.profile, c.pos, c.normal, c.travel, radius, c.mass)
		_record_causal({"action": "cluster_stain", "cluster": key, "stain_id": _stain_serial, "mass": c.mass, "contacts": c.count})
		_contacts.erase(key)
		_draining_contacts = false
		_contact_hit = {}
		_contact_residual = false
		_contact_catastrophic = false
		_suppress_runoff = false
		_impact_response = {}
		_deposit_surface = null
		_causal_drop = -1
		_causal_event = -1

func _write_surface(slot: int, xform: Transform3D, color: Color, custom: Color, offset: float) -> bool:
	if not _spend("stains", settings.stability.stain_writes_per_frame):
		_surface.release(slot)
		_stain_active[slot] = 0
		_forget_stain(slot)
		_support.forget(slot)
		return false
	var fitted := _support.fit(xform, offset)
	if fitted.is_empty():
		_surface.release(slot)
		_stain_active[slot] = 0
		_forget_stain(slot)
		_support.forget(slot)
		return false
	_surface.write(slot, fitted.transform, color, custom)
	if _stain_active[slot] == 0: _stain_birth[slot] = _clock
	_support.own(slot, fitted)
	_last_surface_slot = slot
	return true

func _begin_frame() -> void:
	var frame := Engine.get_process_frames()
	if manual_budget_clock: frame = _budget_frame + 1
	if frame == _budget_frame: return
	for key in frame_usage:
		peak_frame_usage[key] = maxi(int(peak_frame_usage.get(key, 0)), int(frame_usage[key]))
		frame_usage[key] = 0
	_budget_frame = frame

func can_query(count := 1, reserve := 0) -> bool:
	return synchronous_test_mode or int(frame_usage.queries) + count <= settings.stability.queries_per_frame - reserve

func _spend(kind: String, cap: int) -> bool:
	if not synchronous_test_mode and int(frame_usage[kind]) >= cap: return false
	frame_usage[kind] += 1
	return true

func _profile_stage(label: String, start: int) -> void:
	if profile_stages: stage_us[label] = int(stage_us.get(label, 0)) + Time.get_ticks_usec() - start

func _sample(pattern: BloodPattern, layer: int, u: float) -> void:
	var start := Time.get_ticks_usec() if profile_stages else 0
	pattern.sample(layer, u)
	_profile_stage("pattern_sampling", start)

func _query() -> Dictionary:
	if not can_query(): return {}
	frame_usage.queries += 1
	query_count += 1
	var start := Time.get_ticks_usec() if profile_stages else 0
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	_profile_stage("raycasts", start)
	return hit


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
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN) * float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_build_layers()

	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true
	_ray.collision_mask = settings.surface_mask
	_support = BloodSurfaceSupport.new()
	_support.blood = self
	_audio = BloodImpactAudioAccumulator.new()
	add_child(_audio)
	_audio.setup(settings.stability)
	_runoff_patch.resize(settings.max_runoff)

	if settings.prewarm:
		_prewarm()

	set_process(false)
	set_physics_process(true)

func _exit_tree() -> void:
	# End presentation ownership while the world still has a valid lifetime.
	# No shape signal/resource callbacks or RenderingServer writes here.
	if _support != null:
		_support.clear()
		_support.blood = null
	if is_instance_valid(_audio): _audio.clear()

static func find(tree: SceneTree) -> BloodSystem:
	return tree.get_first_node_in_group(GROUP) as BloodSystem


# --------------------------------------------------------------------------
# Entry points
# --------------------------------------------------------------------------

## THE entry point. A reservoir has already decided how much material this is.
func release(rel: BloodRelease) -> void:
	if rel == null or rel.context == null or settings == null: return
	if synchronous_test_mode:
		_release_now(rel)
		return
	_event_counter += 1
	if not rel.is_residual: _combat_events += 1
	rel.event_id = _event_counter
	rel.context.event_id = rel.event_id
	last_context = rel.context if not rel.is_residual else last_context
	last_release = rel if not rel.is_residual else last_release
	accepted_blood_mass += rel.blood_mass
	accepted_tissue_mass += rel.tissue_mass
	queued_blood_mass += rel.blood_mass
	if rel.is_residual:
		# Resolve a live wound at its current validated transform. A queued
		# primary burst may span three steps; an attached emitter must not.
		_release_now(rel)
		queued_blood_mass -= rel.blood_mass
		return
	var priority := 1.0 + float(rel.is_kill()) + float(rel.context.body_region == BloodTypes.BodyRegion.HEAD) * 0.4
	if rel.family() == BloodTypes.DamageType.HIGH_ENERGY: priority += 0.3
	var camera := get_viewport().get_camera_3d()
	var distance := camera.global_position.distance_to(rel.position_ws()) if camera != null else 0.0
	priority /= 1.0 + distance / settings.stability.importance_distance_m
	if rel.is_residual: priority *= 0.2
	if _presentation_queue.size() >= settings.stability.max_pending_releases:
		# Saturation has an explicit coarse mass path, not discarded blood.
		_queue_coarse(_profiles.get(int(rel.family())), rel.position_ws(), rel.context.primary_axis(), rel.blood_mass, rel.event_id, rel.is_residual, rel.is_kill() and not rel.is_residual)
		material_stats["retained_tissue_mass"] = float(material_stats.get("retained_tissue_mass", 0.0)) + rel.tissue_mass
		queued_blood_mass -= rel.blood_mass
		return
	_presentation_queue.append({"release": rel, "priority": priority, "distance": distance, "stage": 0, "density": 1.0})
	_wake()

func _release_now(rel: BloodRelease) -> void:
	if rel == null or rel.context == null or settings == null:
		return
	var ctx := rel.context
	_emission_flags = int(rel.is_residual) | (int(rel.is_kill() and rel.blood_mass >= 0.35 and not rel.is_residual) << 1)
	# A wound dripping must NOT clobber the record of the last BLOW. These are
	# debug/telemetry fields that tests and the overlay read right after a hit,
	# and a residual drip landing in between made a hand cannon headshot report
	# the drip's energy and direction instead of its own.
	if not rel.is_residual and _emitting_stage in [-1, 0]:
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
		_led_runoff_mass = 0.0
		_led_extents.clear()
		_coverage_cells.clear()

	var profile := _profiles.get(int(ctx.damage_type)) as BloodProfile
	if profile == null:
		return

	ctx.blood_primary_axis_ws = ctx.primary_axis()
	if synchronous_test_mode:
		_event_counter += 1
		if not rel.is_residual: _combat_events += 1
		ctx.event_id = _event_counter
		rel.event_id = _event_counter
	_current_event_catastrophic = rel.is_kill() and rel.blood_mass >= 0.35 and not rel.is_residual

	# The Phase 1 frame: attack-relative, pitch-preserving, swing-plane aware.
	var frame := _pattern_frame(ctx, _lobe_axis(ctx, false))
	var pattern := _patterns.get(int(ctx.damage_type)) as BloodPattern
	if pattern == null:
		pattern = BloodPattern.for_family(ctx.damage_type)
		_patterns[int(ctx.damage_type)] = pattern
	pattern.begin(rel, frame, _rng)
	_causal_event = rel.event_id

	var stamp := Time.get_ticks_usec() if profile_stages else 0
	if _emitting_stage in [-1, 2]: _emit_micro(profile, rel, pattern)
	_profile_stage("micro", stamp)
	stamp = Time.get_ticks_usec() if profile_stages else 0
	if _emitting_stage in [-1, 1]: _emit_small(profile, rel, pattern)
	if _emitting_stage in [-1, 0]: _emit_medium(profile, rel, pattern)
	_profile_stage("physical_admission", stamp)
	stamp = Time.get_ticks_usec() if profile_stages else 0
	if _emitting_stage in [-1, 0]: _emit_solids(profile, rel, pattern)
	_profile_stage("tissue_admission", stamp)
	stamp = Time.get_ticks_usec() if profile_stages else 0
	if _emitting_stage in [-1, 0]: _coarse_deposition(profile, rel, pattern)
	_profile_stage("coarse_deposition", stamp)

	if settings.debug_telemetry:
		print("[blood] %s | %s" % [rel.describe(), _event_telemetry()])
	if settings.debug_patterns:
		_draw_event_gizmo(ctx)
	_wake()
	_emission_flags = 0
	_causal_event = -1


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
	var want := int(round(demand * settings.quality_scale() * _density))
	if want <= 0:
		return 0
	var affordable := int(layer.free_slots() * settings.event_free_share)
	# The floor guarantees a family signature survives even under pressure.
	affordable = maxi(affordable, mini(floor_count, layer.capacity))
	var count := mini(want, affordable)
	if not synchronous_test_mode:
		var s := settings.stability
		var cap := s.new_drops_per_frame
		var used: int = frame_usage.drops
		if layer == _large: cap = s.new_solids_per_frame; used = frame_usage.solids
		if layer == _micro: cap = s.new_micro_per_frame; used = frame_usage.micro
		count = mini(count, maxi(0, mini(cap - used, int(ceil(cap * _per_job_share)))))
	return count


func _emit_micro(profile: BloodProfile, rel: BloodRelease, pattern: BloodPattern) -> void:
	var demand := rel.blood_mass * settings.micro_per_mass * profile.micro_weight
	var count := _admit(_micro, demand, settings.min_micro_per_event)
	if rel.is_residual:
		count = mini(count, 6)
	var reach := 0.6 + rel.total_mass() * 1.4
	for i in count:
		var u := float(i) / maxf(float(count), 1.0)
		_sample(pattern, BloodTypes.Layer.MICRO, u)
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
	var count := mini(_admit(_small, rel.blood_mass * settings.small_per_mass * profile.small_weight, 4), _small.free_slots())
	if rel.is_residual: return
	var parcel := rel.blood_mass * settings.physical_mass_share * 0.35
	if count <= 0:
		_deposit_unadmitted(profile, rel.position_ws(), parcel)
		return
	for i in count:
		_sample(pattern, BloodTypes.Layer.SMALL, float(i) / maxf(count, 1))
		var d := exp(_rng.randf_range(log(0.00008), log(0.001)))
		var velocity := pattern.out_dir * profile.small_speed * pattern.out_speed * (0.7 + rel.total_mass() * 1.2)
		_emit_representative(profile, _safe_release_origin(rel.position_ws(), pattern.out_origin),
			velocity, 0.0, parcel / count, 1.0, d, -1, rel.event_id, 1)
	_led_physical_mass += parcel
	if not rel.is_residual: last_small_spawned = count

func _emit_medium(profile: BloodProfile, rel: BloodRelease, pattern: BloodPattern) -> void:
	var count := mini(_admit(_medium, rel.blood_mass * settings.medium_per_mass * profile.medium_weight, settings.min_medium_per_event), _medium.free_slots())
	if rel.is_residual: count = mini(count, 3)
	var parcel := rel.blood_mass if rel.is_residual else rel.blood_mass * settings.physical_mass_share * 0.65
	if count <= 0:
		_deposit_unadmitted(profile, rel.position_ws(), parcel)
		return
	var diameters := PackedFloat32Array()
	var weights := PackedFloat32Array()
	var total := 0.0
	for i in count:
		var roll := _rng.randf()
		var d: float
		if roll < profile.droplet_large_fraction * 0.15:
			d = _rng.randf_range(0.004, 0.008)
		elif roll < profile.droplet_large_fraction:
			d = _rng.randf_range(0.002, 0.004)
		elif roll < profile.droplet_large_fraction + profile.droplet_medium_fraction:
			d = _rng.randf_range(0.001, 0.002)
		else:
			d = exp(_rng.randf_range(log(0.00035), log(0.001)))
		diameters.append(d)
		# Multiplicity can vary; no cubic parcel-to-render-size mapping.
		var weight := clampf(pow(d / 0.001, 1.5), 0.3, 14.0)
		weights.append(weight)
		total += weight
	for i in count:
		_sample(pattern, BloodTypes.Layer.MEDIUM, float(i) / maxf(count, 1))
		var kind := BloodFluidModel.category(diameters[i])
		var violent := profile.damage_type == BloodTypes.DamageType.BLUNT or profile.damage_type == BloodTypes.DamageType.HIGH_ENERGY
		if violent and not rel.is_residual and _rng.randf() < settings.fluid.ligament_fraction:
			kind = BloodFluidModel.Liquid.LIGAMENT
		var velocity := pattern.out_dir * profile.medium_speed * pattern.out_speed * (0.8 + rel.total_mass() * 1.1)
		# Ballistic fine drops launch faster on average; size bands still overlap.
		if profile.damage_type == BloodTypes.DamageType.BALLISTIC:
			velocity *= clampf(pow(0.0015 / diameters[i], 0.18), 0.7, 1.35)
		_emit_representative(profile, _safe_release_origin(rel.position_ws(), pattern.out_origin), velocity,
			0.0, parcel * weights[i] / total, 1.0, diameters[i], kind, rel.event_id)
	_led_physical_mass += parcel
	if not rel.is_residual: last_droplets_spawned = count

func _safe_release_origin(origin: Vector3, offset: Vector3) -> Vector3:
	# A sampled contact volume must not begin on the far side of a floor/wall.
	_ray.from = origin
	_ray.to = origin + offset
	if offset.length_squared() < 0.000001: return origin
	if not can_query(1, settings.stability.surface_query_reserve): return origin
	var hit := _query()
	return (hit.position as Vector3) + (hit.normal as Vector3) * 0.015 if not hit.is_empty() else origin + offset

func _deposit_unadmitted(profile: BloodProfile, origin: Vector3, mass: float) -> void:
	if mass <= 0.0: return
	if not synchronous_test_mode:
		_queue_coarse(profile, origin, Vector3.DOWN, mass, _causal_event, _contact_residual or (_emission_flags & 1) != 0, _contact_catastrophic or (_emission_flags & 2) != 0)
		return
	material_stats["coarse_fallback_mass"] = float(material_stats.get("coarse_fallback_mass", 0.0)) + mass
	_ray.from = origin
	_ray.to = origin + _gravity.normalized() * 20.0
	var hit := _query()
	if not hit.is_empty():
		_deposit_cluster(profile, hit.position, hit.normal, _gravity.normalized(), mass)
	else:
		material_stats.escaped_mass += mass

func _emit_solids(profile: BloodProfile, rel: BloodRelease, pattern: BloodPattern) -> void:
	if rel.tissue_mass <= 0.0 or rel.is_residual:
		return
	var grain_demand := rel.tissue_mass * settings.grains_per_tissue * profile.grain_weight
	var chunk_demand := rel.tissue_mass * settings.large_per_tissue * profile.chunk_weight
	var reach := 0.7 + rel.total_mass()
	# Recycle settled organic debris only; a live slot must have one simulator.
	var wanted := mini(int(ceil((grain_demand + chunk_demand) * settings.quality_scale())), _large.capacity)
	while _large.free_slots() < wanted and not _sol_settled.is_empty():
		_large.release(_sol_settled[0])
		_sol_settled.remove_at(0)

	# CHUNKS FIRST. Grains and chunks share one layer, and grains are far more
	# numerous, so asking for grains first let them eat the whole allocation and
	# a maul kill came out with 195 specks and almost no real pieces. The big
	# pieces are the ones that carry the family's read, so they get served first.
	var chunks := _admit(_large, chunk_demand, 0)
	# Tissue mass is shared out over the solids that actually exist. A chunk is
	# worth several grains, so it carries several grains' worth of material.
	var grains_planned := mini(_admit(_large, grain_demand, 0), maxi(_large.free_slots() - chunks, 0))
	if not synchronous_test_mode:
		grains_planned = mini(grains_planned, maxi(0, settings.stability.new_solids_per_frame - int(frame_usage.solids) - chunks))
	var tissue_units := float(chunks) * 4.0 + float(grains_planned)
	if tissue_units <= 0.0:
		material_stats["retained_tissue_mass"] = float(material_stats.get("retained_tissue_mass", 0.0)) + rel.tissue_mass
		return
	var unit_mass := rel.tissue_mass / maxf(tissue_units, 1.0)
	for i in chunks:
		var uc := float(i) / maxf(float(chunks), 1.0)
		# Material first: a pattern may throw fat and dense tissue differently.
		var cc := TissueDebris.pick(rel.tissue_mix, _rng.randf())
		pattern.material_class = int(cc)
		_sample(pattern, BloodTypes.Layer.LARGE, uc)
		_emit_solid(
			profile,
			_safe_release_origin(rel.position_ws(), pattern.out_origin),
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
		_sample(pattern, BloodTypes.Layer.LARGE, u)
		_emit_solid(
			profile,
			_safe_release_origin(rel.position_ws(), pattern.out_origin),
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
	if not synchronous_test_mode:
		if rel.is_residual: return
		var mass := rel.blood_mass * (1.0 - settings.physical_mass_share)
		_led_air_mass += mass
		var probes := clampi(int(ceil(mass * settings.cloud_probes_per_mass * _density)), 2, settings.cloud_probes_max)
		for probe in probes:
			_sample(pattern, BloodTypes.Layer.MEDIUM, float(probe) / probes)
			_queue_coarse(profile, _safe_release_origin(rel.position_ws(), pattern.out_origin), pattern.out_dir, mass / probes, rel.event_id, false, rel.is_kill())
		return
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
		_sample(pattern, BloodTypes.Layer.SURFACE, float(i) / maxf(float(probes), 1.0))
		var dir := pattern.out_dir
		_ray.from = _safe_release_origin(origin, pattern.out_origin)
		_ray.to = _ray.from + dir * settings.cloud_probe_distance
		var hit := _query()
		if hit.is_empty():
			# Nothing in that direction within reach, so gravity takes it. But
			# NOT straight down from the event origin every time: nine of twelve
			# probes missing meant nine clusters landing on the same square
			# centimetre, which is why soak bases stacked into one blob.
			#
			# The fallback keeps the pattern's own geometry - it drops from a
			# point ALONG the trajectory the probe was already travelling, so
			# a forward plume still lands forward and a lateral fan still lands
			# laterally. It is the pattern's footprint, projected downward.
			var travelled: float = settings.cloud_probe_distance * _rng.randf_range(0.25, 1.0)
			var from := _safe_release_origin(origin, pattern.out_origin + dir * travelled)
			_ray.from = from
			_ray.to = from + Vector3.DOWN * settings.cloud_probe_distance * 2.0
			hit = _query()
			# Keep the horizontal component so the mark still points the way the
			# material was going when it fell.
			var flat := Vector3(dir.x, 0.0, dir.z)
			var has_flat := flat.length_squared() > 0.0001
			dir = (flat * 0.5 + Vector3.DOWN).normalized() if has_flat else Vector3.DOWN
			if hit.is_empty():
				material_stats.escaped_mass += per_probe
				continue
		_deposit_surface = surface_response(hit.get("collider"), hit.normal)
		_deposit_cluster(profile, hit.position, hit.normal, dir, per_probe)
		_deposit_surface = null
		landed += per_probe
	_led_surface_mass += 0.0  # counted inside _place_stain


## One probe's worth of material, laid down as a cluster rather than a single
## disc: an anchor stain carrying most of the mass plus a few smaller marks
## around it. Clusters are what stop dense areas reading as isolated stickers.
func _deposit_cluster(
	profile: BloodProfile, point: Vector3, normal: Vector3, travel: Vector3, mass: float
) -> void:
	var count := maxi(settings.cluster_size, 0)
	var spread := _stain_radius(profile, mass) * 1.9
	var tangent := travel.slide(normal)
	if tangent.length_squared() < 0.0001:
		tangent = normal.cross(Vector3.RIGHT if absf(normal.y) > 0.95 else Vector3.UP)
	tangent = tangent.normalized()
	var bitangent := normal.cross(tangent).normalized()
	var each := mass * 0.38 / maxf(count, 1)
	var remaining := mass
	var saved_surface := _deposit_surface
	for j in count:
		var at := point + tangent * _rng.randf_range(-spread, spread * 1.6)
		at += bitangent * _rng.randf_range(-spread, spread)
		_ray.from = at + normal * 0.15
		_ray.to = at - normal * 0.25
		var hit := _query()
		if hit.is_empty(): continue
		_deposit_surface = surface_response(hit.get("collider"), hit.normal)
		_place_stain(profile, hit.position, hit.normal, travel, _stain_radius(profile, each), each)
		remaining -= each
	_deposit_surface = saved_surface
	# Missed secondary projections and a zero satellite budget return to parent.
	_place_stain(profile, point, normal, travel, _stain_radius(profile, remaining), remaining)

func _blood_tint(_profile: BloodProfile) -> Color:
	# Slight variation between fresh and deep red, so a burst is not one flat
	# colour. Restrained: this is blood, not confetti.
	return settings.fresh_blood_color.lerp(settings.dark_fresh_blood_color, _rng.randf_range(0.0, 0.22))


# --------------------------------------------------------------------------
# Cheap airborne layer
# --------------------------------------------------------------------------

func _emit_air(
	layer: BloodMultiMeshLayer, pos: Vector3, vel: Vector3, size: float,
	stretch: float, color: Color, life: float
) -> void:
	if not _spend("micro", settings.stability.new_micro_per_frame): return
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
	_air_size[i] = minf(size * settings.fluid.render_mist_scale, settings.fluid.mist_max_diameter)
	_air_stretch[i] = stretch
	_air_color[i] = color
	# The first frame must obey the same mist cap as subsequent updates.
	layer.write(slot, _oriented(pos, vel, _air_size[i], stretch), color)


func _step_air(delta: float) -> void:
	var i := 0
	while i < _air_count:
		_air_life[i] -= delta
		if _air_life[i] <= 0.0:
			_retire_air(i)
			continue
		var vel := _air_vel[i]
		vel = BloodFluidModel.advance_velocity(vel, 0.00006, delta, _gravity, settings.fluid)
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
func _oriented(pos: Vector3, vel: Vector3, size: float, _stretch: float) -> Transform3D:
	# Legacy callers get bounded liquid ellipsoids, never box/rod scaling.
	return BloodFluidModel.liquid_transform(pos, vel, minf(size, settings.fluid.mist_max_diameter),
		BloodFluidModel.Liquid.MICRO_MIST, 0.0, settings.fluid)

func _emit_representative(
	profile: BloodProfile, pos: Vector3, vel: Vector3, size: float,
	mass: float, _stretch: float, physical_diameter := 0.0, kind := -1,
	event_id := -1, layer_kind := 0, generation := 0, parent_id := -1
) -> int:
	if not _spend("drops", settings.stability.new_drops_per_frame): return -1
	var layer := _small if layer_kind == 1 else _medium
	if _rep_count >= _rep_slot.size(): return -1
	var slot := layer.acquire(false)
	if slot < 0: return -1
	var i := _rep_count
	_rep_count += 1
	var d := physical_diameter if physical_diameter > 0.0 else clampf(size / settings.fluid.diameter_exaggeration, 0.00035, 0.004)
	if kind < 0: kind = BloodFluidModel.category(d)
	_rep_slot[i] = slot
	_rep_layer[i] = layer_kind
	_rep_pos[i] = pos
	_rep_previous[i] = pos
	_rep_vel[i] = vel
	_rep_life[i] = settings.droplet_max_life
	_rep_diameter[i] = d
	_rep_kind[i] = kind
	_rep_size[i] = BloodFluidModel.render_diameter(d, kind, settings.fluid)
	_rep_mass[i] = mass
	_rep_stretch[i] = 1.0
	# Deterministic tint: visual tuning must not consume the simulation RNG.
	_rep_color[i] = settings.fresh_blood_color.lerp(settings.dark_fresh_blood_color, 0.08 if kind < BloodFluidModel.Liquid.LARGE else 0.18)
	_rep_profile[i] = profile
	_rep_generation[i] = generation
	_rep_exposure[i] = 0.0
	_rep_age[i] = 0.0
	_drop_serial += 1
	_rep_id[i] = _drop_serial
	_rep_parent[i] = parent_id
	_rep_event[i] = event_id if event_id >= 0 else _event_counter
	_rep_flags[i] = _emission_flags
	_rep_wait[i] = 0.0
	_record_causal({"action": "spawn", "drop_id": _rep_id[i], "parent_id": parent_id,
		"event_id": _rep_event[i], "position": pos, "velocity": vel, "physical_diameter": d,
		"render_diameter": _rep_size[i], "material_class": kind, "represented_mass": mass})
	if kind == BloodFluidModel.Liquid.LIGAMENT: material_stats.ligaments += 1
	_write_representative(i)
	return _rep_id[i]

func _write_representative(i: int) -> void:
	var xform := BloodFluidModel.liquid_transform(_rep_pos[i], _rep_vel[i], _rep_size[i],
		_rep_kind[i], _rep_age[i], settings.fluid)
	var longest := maxf(xform.basis.x.length(), maxf(xform.basis.y.length(), xform.basis.z.length()))
	var cap := settings.fluid.max_glob_diameter if _rep_kind[i] == BloodFluidModel.Liquid.GLOB else settings.fluid.max_drop_diameter
	if _rep_kind[i] == BloodFluidModel.Liquid.LIGAMENT: cap = settings.fluid.ligament_max_length
	if longest > cap + 0.0001:
		material_stats.size_warnings += 1
		push_warning("Blood liquid render limit exceeded: drop %d, %.4f m" % [_rep_id[i], longest])
	var layer := _small if _rep_layer[i] == 1 else _medium
	var trail := 0.0
	# A fixed subset of existing medium slots owns wakes. No new mesh, buffer,
	# history array or per-drop node. The tail ends with the causal collision.
	if _rep_layer[i] != 1 and _rep_slot[i] < settings.stability.max_trails:
		trail = trail_length_for(_rep_kind[i], _rep_vel[i].length(), _rep_profile[i].damage_type)
	layer.write(_rep_slot[i], xform, _rep_color[i], Color(trail / maxf(xform.basis.z.length(), 0.001), 0, 1, 0))

func trail_length_for(kind: int, speed: float, family: int) -> float:
	if kind < BloodFluidModel.Liquid.MEDIUM or speed <= settings.stability.trail_min_speed: return 0.0
	var gain := settings.stability.slash_trail_gain if family == BloodTypes.DamageType.SLASHING else 1.0
	return minf(settings.stability.trail_max_length_m, (speed - settings.stability.trail_min_speed) * settings.stability.trail_time_s * gain)

func _split_representative(i: int) -> void:
	var layer := _small if _rep_layer[i] == 1 else _medium
	if layer.free_slots() < 1 or _rep_count >= _rep_slot.size(): return
	var mass := _rep_mass[i]
	var d := _rep_diameter[i] * pow(0.5, 1.0 / 3.0)
	var side := _rep_vel[i].cross(Vector3.UP).normalized()
	if side.length_squared() < 0.1: side = Vector3.RIGHT
	var child := _emit_representative(_rep_profile[i], _rep_pos[i], _rep_vel[i] + side * 0.25,
		0.0, mass * 0.5, 1.0, d, BloodFluidModel.category(d), _rep_event[i],
		_rep_layer[i], _rep_generation[i] + 1, _rep_id[i])
	if child < 0: return
	_rep_flags[_rep_count - 1] = _rep_flags[i]
	_rep_mass[i] = mass * 0.5
	_rep_diameter[i] = d
	_rep_kind[i] = BloodFluidModel.category(d)
	_rep_size[i] = BloodFluidModel.render_diameter(d, _rep_kind[i], settings.fluid)
	_rep_generation[i] += 1
	_rep_exposure[i] = 0.0
	_rep_vel[i] -= side * 0.25
	material_stats.breakups += 1
	_record_causal({"action": "split", "drop_id": _rep_id[i], "child_id": child,
		"event_id": _rep_event[i], "before_mass": mass, "children_mass": mass})

func _step_representatives(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	# RANK ONCE, NOT THREE TIMES.
	#
	# The three priority passes each used to walk the whole representative list
	# and recompute this rank - including a camera distance_to(), a square root -
	# for every drop, then skip the two thirds that were not its turn. That is
	# 3N rank evaluations to do N drops' worth of work, and it was the largest
	# in-combat cost in the profile at roughly 2 ms/frame for ~50 drops.
	#
	# Computing it once into a preallocated byte array leaves the ordering
	# semantics identical and removes two thirds of the distance maths.
	var camera_pos := camera.global_position if camera != null else Vector3.ZERO
	var importance := settings.stability.importance_distance_m
	var importance_sq := importance * importance
	for j in _rep_count:
		_rep_wait[j] += delta
		var rank := 2
		if _rep_kind[j] >= BloodFluidModel.Liquid.LARGE:
			rank = 0
		elif _rep_kind[j] >= BloodFluidModel.Liquid.MEDIUM:
			# Squared compare: same predicate, no square root.
			if camera == null or camera_pos.distance_squared_to(_rep_pos[j]) < importance_sq:
				rank = 1
		_rep_rank[j] = rank
	for priority in 3:
		var i := 0
		while i < _rep_count:
			if _rep_rank[i] != priority: i += 1; continue
			if not can_query(1, settings.stability.surface_query_reserve + settings.stability.solid_queries_per_frame):
				# Bounded deferred simulation. Fine/distant samples that cannot be
				# serviced become an explicit coarse parcel, preserving all mass.
				if _rep_wait[i] > (0.12 if priority == 2 else 0.25):
					_queue_coarse(_rep_profile[i], _rep_pos[i], _rep_vel[i], _rep_mass[i], _rep_event[i], (_rep_flags[i] & 1) != 0, (_rep_flags[i] & 2) != 0)
					material_stats["budget_coarse_mass"] = float(material_stats.get("budget_coarse_mass", 0.0)) + _rep_mass[i]
					_retire_representative(i)
					continue
				i += 1
				continue
			var elapsed := minf(_rep_wait[i], 1.0 / 30.0)
			_rep_wait[i] -= elapsed
			var steps := maxi(1, int(ceil(elapsed / settings.fluid.fixed_substep)))
			var dt := elapsed / steps
			var from := _rep_pos[i]
			_rep_previous[i] = from
			var velocity := _rep_vel[i]
			var to := from
			for substep in steps:
				velocity = BloodFluidModel.advance_velocity(velocity, _rep_diameter[i], dt, _gravity, settings.fluid)
				to += velocity * dt
			_ray.from = from
			_ray.to = to
			var hit := _query()
			if not hit.is_empty():
				_deposit_surface = surface_response(hit.get("collider"), hit.normal)
				_contact_hit = hit
				_land_representative(i, hit.position, hit.normal, velocity)
				_contact_hit = {}
				_deposit_surface = null
				continue
			_rep_pos[i] = to
			_rep_vel[i] = velocity
			_rep_life[i] -= elapsed
			_rep_age[i] += elapsed
			var unstable := BloodFluidModel.air_weber(_rep_diameter[i], velocity.length(), settings.fluid) > BloodFluidModel.breakup_threshold(_rep_diameter[i], settings.fluid)
			_rep_exposure[i] = _rep_exposure[i] + elapsed if unstable else 0.0
			if _rep_life[i] <= 0.0:
				_led_timed_out += _rep_mass[i]
				_causal_drop = _rep_id[i]
				_causal_event = _rep_event[i]
				_record_causal({"action": "timeout_coarse", "drop_id": _causal_drop, "event_id": _causal_event})
				_contact_residual = (_rep_flags[i] & 1) != 0
				_contact_catastrophic = (_rep_flags[i] & 2) != 0
				_deposit_unadmitted(_rep_profile[i], to, _rep_mass[i])
				_contact_residual = false
				_contact_catastrophic = false
				_causal_drop = -1
				_causal_event = -1
				_retire_representative(i)
				continue
			i += 1
	var before_breakup := _rep_count
	for j in before_breakup:
		var ligament := _rep_kind[j] == BloodFluidModel.Liquid.LIGAMENT and _rep_age[j] >= settings.fluid.ligament_lifetime
		if _rep_generation[j] < settings.fluid.breakup_max_generation and (ligament or _rep_exposure[j] >= settings.fluid.breakup_exposure): _split_representative(j)
		if ligament:
			_rep_kind[j] = BloodFluidModel.category(_rep_diameter[j])
			_rep_size[j] = BloodFluidModel.render_diameter(_rep_diameter[j], _rep_kind[j], settings.fluid)
	for j in _rep_count: _write_representative(j)

func _land_representative(i: int, point: Vector3, normal: Vector3, vel: Vector3) -> void:
	var profile := _rep_profile[i]
	var mass := _rep_mass[i]
	var surface := _deposit_surface if _deposit_surface != null else surface_response(null, normal)
	_impact_response = BloodFluidModel.impact(_rep_diameter[i], vel, normal, surface, settings.fluid)
	_impact_response["render_scale"] = BloodFluidModel.stain_render_scale(_rep_kind[i], settings.fluid)
	_causal_drop = _rep_id[i]
	_causal_event = _rep_event[i]
	material_stats.collisions += 1
	_led_hit_world += mass
	_record_causal({"action": "collision", "drop_id": _causal_drop, "event_id": _causal_event,
		"parent_id": _rep_parent[i], "position": point, "velocity": vel, "diameter": _rep_diameter[i],
		"mass": mass, "impact": _impact_response.duplicate()})
	var radius := _stain_radius(profile, mass) * float(_impact_response.spread)
	var kind := int(_rep_kind[i])
	var limit := settings.stability.immediate_fine_width_m if kind <= BloodFluidModel.Liquid.SMALL else settings.stability.immediate_medium_width_m
	if kind >= BloodFluidModel.Liquid.LARGE: limit = settings.stability.immediate_glob_width_m
	_impact_response["max_width"] = limit
	# A small bead carrying a large statistical parcel is not a giant glob.
	_impact_response["direct_large"] = kind >= BloodFluidModel.Liquid.LARGE
	_audio.submit(point, surface, mass, vel.length(), kind, normal, _clock)
	if not synchronous_test_mode:
		var satellite_mass := _impact_satellites(profile, point, normal, vel, radius, mass, surface)
		_queue_contact(profile, point, normal, vel, radius, mass - satellite_mass, _impact_response, _contact_hit,
			_causal_drop, _causal_event, (_rep_flags[i] & 1) != 0, (_rep_flags[i] & 2) != 0)
		_impact_response = {}
		_causal_drop = -1
		_causal_event = -1
		_retire_representative(i)
		return
	var satellites := _impact_satellites(profile, point, normal, vel, radius, mass, surface)
	_place_stain(profile, point, normal, vel, radius * sqrt(maxf(1.0 - satellites / maxf(mass, 0.000001), 0.0)), mass - satellites)
	_impact_response = {}
	_causal_drop = -1
	_causal_event = -1
	_retire_representative(i)

func _impact_satellites(profile: BloodProfile, point: Vector3, normal: Vector3, velocity: Vector3, radius: float, mass: float, surface: BloodSurfaceResponse) -> float:
	if not bool(_impact_response.get("splash", false)): return 0.0
	var severity := clampf(float(_impact_response.we) * surface.splash_multiplier / settings.fluid.splash_weber - 0.5, 0.0, 2.0)
	var count := clampi(int(ceil(severity * (1.0 + surface.roughness) * settings.quality_scale())), 1, settings.satellite_max)
	if not synchronous_test_mode:
		if mass < 0.004 or not can_query(2, settings.stability.surface_query_reserve + settings.stability.solid_queries_per_frame): return 0.0
		count = mini(count, 2) # Extra breakup yields to real parcel/support queries.
	var share := mass * settings.satellite_mass_share / count
	var tangent := velocity.slide(normal)
	var oblique := tangent.length_squared() > 0.01
	if not oblique: tangent = normal.cross(Vector3.RIGHT if absf(normal.y) > 0.9 else Vector3.UP)
	tangent = tangent.normalized()
	var side := normal.cross(tangent).normalized()
	var deposited := 0.0
	for j in count:
		var angle := _rng.randf_range(-1.2, 1.2) if oblique else _rng.randf() * TAU
		var at := point + (tangent * cos(angle) + side * sin(angle)) * radius * _rng.randf_range(1.3, 2.8)
		_ray.from = at + normal * 0.15
		_ray.to = at - normal * 0.2
		var hit := _query()
		if hit.is_empty(): continue
		if not synchronous_test_mode:
			_queue_contact(profile, hit.position, hit.normal, velocity, radius * 0.22, share,
				{"aspect": 1.3, "outcome": BloodFluidModel.Impact.DEPOSIT, "max_width": settings.stability.immediate_fine_width_m},
				hit, _causal_drop, _causal_event, true)
			deposited += share
			continue
		var saved := _impact_response
		_impact_response = {"aspect": 1.3, "outcome": BloodFluidModel.Impact.DEPOSIT}
		_place_stain(profile, hit.position, hit.normal, velocity, radius * 0.22, share)
		_impact_response = saved
		deposited += share
	return deposited

func surface_response(collider: Object, normal: Vector3) -> BloodSurfaceResponse:
	if is_instance_valid(collider):
		var value: Variant = collider.get_meta("blood_response") if collider.has_meta("blood_response") else null
		if value is BloodSurfaceResponse: return value
		var tag := str(collider.get_meta("blood_surface", "")).to_lower()
		if tag in ["porous", "wood", "fabric", "porous_absorbent"]: return _porous
		if tag in ["smooth", "metal", "smooth_nonabsorbent"]: return _smooth
		if tag in ["rough", "stone", "rough_nonabsorbent"]: return _rough
	return _rough if absf(normal.y) > 0.7 else _smooth

func _record_causal(record: Dictionary) -> void:
	if not record_causality: return
	if causal_records.size() >= settings.fluid.max_causal_records: causal_records.pop_front()
	causal_records.append(record)

func _retire_representative(i: int) -> void:
	var layer := _small if _rep_layer[i] == 1 else _medium
	layer.release(_rep_slot[i])
	var last := _rep_count - 1
	if i != last:
		_rep_slot[i] = _rep_slot[last]
		_rep_layer[i] = _rep_layer[last]
		_rep_pos[i] = _rep_pos[last]
		_rep_previous[i] = _rep_previous[last]
		_rep_vel[i] = _rep_vel[last]
		_rep_life[i] = _rep_life[last]
		_rep_size[i] = _rep_size[last]
		_rep_mass[i] = _rep_mass[last]
		_rep_stretch[i] = _rep_stretch[last]
		_rep_color[i] = _rep_color[last]
		_rep_profile[i] = _rep_profile[last]
		_rep_diameter[i] = _rep_diameter[last]
		_rep_kind[i] = _rep_kind[last]
		_rep_generation[i] = _rep_generation[last]
		_rep_exposure[i] = _rep_exposure[last]
		_rep_age[i] = _rep_age[last]
		_rep_id[i] = _rep_id[last]
		_rep_parent[i] = _rep_parent[last]
		_rep_event[i] = _rep_event[last]
		_rep_flags[i] = _rep_flags[last]
		_rep_wait[i] = _rep_wait[last]
		_rep_rank[i] = _rep_rank[last]
	_rep_count -= 1

func _emit_solid(
	profile: BloodProfile, pos: Vector3, vel: Vector3, size: float,
	category: BloodTypes.Tissue, big: bool, mass := 0.0
) -> void:
	if not _spend("solids", settings.stability.new_solids_per_frame):
		material_stats["retained_tissue_mass"] = float(material_stats.get("retained_tissue_mass", 0.0)) + mass
		return
	if _sol_count >= _sol_slot.size(): return
	var slot := _large.acquire(false)
	if slot < 0:
		return
	var i := _sol_count
	if i >= _sol_slot.size():
		_large.release(slot)
		return
	_sol_count += 1
	_sol_slot[i] = slot
	_sol_age[i] = 0.0
	_sol_pos[i] = pos
	_sol_vel[i] = vel / maxf(TissueDebris.drag_for(category), 0.2)
	_sol_spin[i] = _rng.randf_range(-14.0, 14.0)
	_sol_basis[i] = Basis.from_euler(
		Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)
	)
	if category == BloodTypes.Tissue.THICK_BLOOD:
		category = BloodTypes.Tissue.STRINGY_TISSUE
	elif big and category == BloodTypes.Tissue.FLESH and _rng.randf() < 0.12:
		category = BloodTypes.Tissue.GORE_CHUNK
	var cap := settings.fluid.chunk_max_size if category == BloodTypes.Tissue.GORE_CHUNK else settings.fluid.tissue_max_size
	if not big: cap = minf(cap, settings.fluid.grain_max_size)
	if category == BloodTypes.Tissue.FAT: cap = minf(cap, settings.fluid.fat_max_size)
	size = minf(size, cap / 1.3)
	# Irregular axes read as gristle rather than as dice.
	_sol_size[i] = Vector3(
		size, size * _rng.randf_range(0.45, 1.0), size * _rng.randf_range(0.6, 1.3)
	)
	if category == BloodTypes.Tissue.STRINGY_TISSUE:
		_sol_size[i] *= Vector3(0.18, 0.2, 1.0)
	_sol_color[i] = TissueDebris.color_for(category, _rng)
	# Only big pieces are allowed to leave a mark, and only one each.
	_sol_marks[i] = 0 if big else 1
	_sol_bounced[i] = 0
	_sol_category[i] = int(category)
	_sol_mass[i] = mass
	_sol_profile[i] = profile
	_write_solid(i)


func _write_solid(i: int) -> void:
	_large.write(
		_sol_slot[i],
		Transform3D(_sol_basis[i].scaled_local(_sol_size[i]), _sol_pos[i]),
		_sol_color[i],
		Color(float(_sol_category[i]), 0.0, 1.0, 0.0)
	)


## Fixed timestep, same as the representatives.
func _step_solids(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var i := 0
	while i < _sol_count:
		if not can_query(1, settings.stability.surface_query_reserve): break
		if not synchronous_test_mode and frame_usage.solid_queries >= settings.stability.solid_queries_per_frame: break
		frame_usage.solid_queries += 1
		_sol_age[i] += delta
		if _sol_age[i] >= settings.fluid.solid_max_flight_time:
			material_stats["escaped_tissue_mass"] = float(material_stats.get("escaped_tissue_mass", 0.0)) + _sol_mass[i]
			_large.release(_sol_slot[i])
			_settle_solid(i)
			_sol_settled.resize(_sol_settled.size() - 1)
			continue
		var vel := _sol_vel[i]
		vel += _gravity * delta
		var from := _sol_pos[i]
		var to := from + vel * delta

		_ray.from = from
		_ray.to = to
		var hit := _query()
		if not hit.is_empty():
			_contact_hit = hit
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
	_contact_hit = {}


## A settled solid keeps its MultiMesh slot - it stays visible, that is the
## point - but leaves the simulation list.
func _settle_solid(i: int) -> void:
	_sol_settled.append(_sol_slot[i])
	var last := _sol_count - 1
	if i != last:
		_sol_slot[i] = _sol_slot[last]
		_sol_age[i] = _sol_age[last]
		_sol_pos[i] = _sol_pos[last]
		_sol_vel[i] = _sol_vel[last]
		_sol_spin[i] = _sol_spin[last]
		_sol_basis[i] = _sol_basis[last]
		_sol_size[i] = _sol_size[last]
		_sol_color[i] = _sol_color[last]
		_sol_marks[i] = _sol_marks[last]
		_sol_bounced[i] = _sol_bounced[last]
		_sol_category[i] = _sol_category[last]
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

## Birth time for the shader's impact bloom, packed into 0..1.
##
## The shader compares this against mod(TIME, bloom_window). Using the engine
## clock directly - rather than the system's own accumulated _clock - keeps the
## two in step without sending a second time value per instance.
func _bloom_stamp() -> float:
	var window: float = maxf(settings.stability.bloom_window_s, 0.1)
	# Kept strictly below 1.0 so it can never carry into the row integer.
	return minf(fmod(float(Time.get_ticks_msec()) * 0.001, window) / window, 0.9999)



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


## Lay one mark on a surface.
##
## DIMENSION SEMANTICS, spelled out because mixing these is exactly how the
## Phase 2.3 render bug happened:
##     radius_m   HALF the mark's visible width, in metres. What _stain_radius
##                returns.
##     quad_m     the FULL width/height of the quad, in metres, after the atlas
##                occupancy has been divided out.
##     mass       represented material, NOT a dimension.
func _place_stain(
	profile: BloodProfile, pos: Vector3, normal: Vector3, travel: Vector3,
	radius_m: float, mass: float
) -> void:
	if not synchronous_test_mode and not _draining_contacts:
		_queue_contact(profile, pos, normal, travel, radius_m, mass, _impact_response, _contact_hit, _causal_drop, _causal_event, _contact_residual, _contact_catastrophic)
		return
	var start := Time.get_ticks_usec() if profile_stages else 0
	_place_stain_impl(profile, pos, normal, travel, radius_m, mass)
	_profile_stage("stain_placement", start)

func _place_stain_impl(profile: BloodProfile, pos: Vector3, normal: Vector3, travel: Vector3, radius_m: float, mass: float) -> void:
	var key := _cell_key(pos)
	var density: int = _cells.get(key, 0)

	# Dense contamination stops being fifty identical stickers and becomes one
	# big soaked reinforcement mark plus the detail on top.
	# Accumulation is handled by mass-backed growing pools, never a random
	# radius multiplier on the next residual drip in a crowded 3 m cell.

	var slot := _acquire_stain_slot(key)
	if slot < 0:
		_retained_patch_mass += mass
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
	# A WALL IS NOT A FLOOR ROTATED 90 DEGREES.
	#
	# On a floor, material arrives mostly from above and spreads - it pools. On a
	# wall it arrives across the surface and SMEARS, and how much depends on the
	# angle it came in at. A glancing hit draws a long directional streak; a
	# head-on hit stays compact. Using one elongation rule for both is what made
	# wall blood read as a decal pasted vertically.
	var on_wall := _is_wall(normal)
	var elongation: float
	if on_wall:
		if incidence < settings.wall_glancing_incidence:
			elongation = clampf(1.0 / incidence, 1.0, settings.wall_streak_ratio)
		else:
			elongation = clampf(1.0 / incidence, 1.0, profile.env_streak_ratio)
			if _impact_response.is_empty(): radius_m *= settings.wall_compact_scale
	else:
		elongation = clampf(1.0 / incidence, 1.0, profile.env_streak_ratio)
	if not _impact_response.is_empty():
		elongation = sqrt(float(_impact_response.get("aspect", 1.0)))
	if profile.damage_type == BloodTypes.DamageType.SLASHING and travel.slide(normal).length_squared() > 0.01:
		elongation = maxf(elongation, sqrt(settings.stability.slash_stain_aspect))
	var across := 1.0 / elongation if not _impact_response.is_empty() else 1.0
	var along := travel.slide(normal)
	if along.length_squared() > 0.0001:
		along = along.normalized()
		var roll := atan2(along.dot(basis.y.normalized()), along.dot(basis.x.normalized()))
		basis = basis.rotated(normal, roll)
	# basis.x was just rotated onto the travel direction, so THAT is the axis to
	# stretch. Scaling y instead put the long axis 90 degrees across the travel.
	var shape := _pick_stain_shape(profile)
	if on_wall:
		if incidence < settings.wall_glancing_incidence:
			# Glancing wall material is a smear, whatever the family favours.
			var smear := _rng.randf() < 0.6
			shape = int(BloodTypes.Stain.STREAK) if smear else int(BloodTypes.Stain.ELONGATED)
		else:
			# Straight into the wall: a rounder, irregular splat. Left to the
			# family's own weights this often came out as a streak, which reads
			# as a glancing hit and contradicts what actually happened.
			var chunky := _rng.randf() < 0.55
			if chunky:
				shape = int(BloodTypes.Stain.LARGE_IRREGULAR)
			else:
				shape = int(BloodTypes.Stain.MEDIUM_ROUND)

	if not _impact_response.is_empty():
		var outcome := int(_impact_response.get("outcome", BloodFluidModel.Impact.DEPOSIT))
		var response := _deposit_surface if _deposit_surface != null else surface_response(null, normal)
		shape = int(BloodTypes.Stain.MEDIUM_ROUND)
		if response.roughness > 0.4 or outcome == BloodFluidModel.Impact.SPLASH:
			shape = int(BloodTypes.Stain.LARGE_IRREGULAR)
		if outcome == BloodFluidModel.Impact.GLANCING: shape = int(BloodTypes.Stain.ELONGATED)
		if outcome == BloodFluidModel.Impact.HEAVY_GLOB: shape = int(BloodTypes.Stain.POOLED)
	# Preserve the physical aspect and actual incoming tangent while retaining
	# the blade-specific footprint that the generic impact override erased.
	if profile.damage_type == BloodTypes.DamageType.SLASHING and along.length_squared() > 0.01:
		shape = int(BloodTypes.Stain.STREAK)

	# radius_m is HALF the width. The quad must be a full DIAMETER across, and
	# then wider again so the ink inside the atlas cell actually spans it.
	# Apply arcade gain only to submitted geometry; collision spread, satellite
	# positions and wet/runoff accounting still use the original physical inputs.
	var visual_radius := radius_m * float(_impact_response.get("render_scale", 1.0))
	var max_width := float(_impact_response.get("max_width", settings.stability.immediate_medium_width_m))
	if _contact_catastrophic and mass >= settings.stability.catastrophic_min_mass and bool(_impact_response.get("direct_large", false)):
		max_width = settings.stability.catastrophic_width_m
	if _contact_residual: max_width = settings.stability.residual_width_m
	visual_radius = minf(visual_radius, max_width / (2.0 * maxf(elongation, across)))
	var quad_m := quad_for_visible_diameter(visual_radius * 2.0, shape)
	var procedural := maxf(quad_m.x * elongation, quad_m.y * across) > settings.stain_atlas_cell / settings.stability.minimum_surface_texels_per_m
	if procedural:
		# Procedural masks have symmetric occupancy. Reusing the elongated
		# bitmap's asymmetric padding correction made shallow impacts round.
		quad_m = Vector2.ONE * visual_radius * 2.0 / settings.stability.pool_mask_occupancy
	basis.x *= quad_m.x * elongation
	basis.y *= quad_m.y * across
	# Saturating cells darken, so a soaked patch reads wetter than a fresh one.
	var dark: float = clampf(float(density) / maxf(float(settings.soak_threshold), 1.0), 0.0, 1.0)
	dark *= settings.soak_darkening
	var c := settings.dark_fresh_blood_color.lerp(settings.fresh_blood_color, 0.35)
	if _deposit_surface != null: c = c.darkened(_deposit_surface.stain_darkening)
	var color := Color(c.r * (1.0 - dark), c.g * (1.0 - dark), c.b * (1.0 - dark), 1.0)

	# The atlas ROW carries the bloom birth time in its fraction. Rows are whole
	# numbers, so the fraction was unused; this lets the shader grow the mark
	# from its contact point to its footprint with no per-frame CPU writes.
	var custom := Color(
		float(shape % ATLAS_COLS), float(shape / ATLAS_COLS) + _bloom_stamp(), 1.0, 0.0
	)
	if procedural:
		custom.a = 2.0 # Procedural irregular mask, no magnified 64px bitmap.
	custom.a += settings.stability.directional_tail_strength * (1.0 - incidence)
	if not _write_surface(
		slot,
		Transform3D(basis, pos + normal * settings.stability.detail_surface_offset_m),
		color,
		custom, settings.stability.detail_surface_offset_m
	):
		_retained_patch_mass += mass
		material_stats["unsupported_mass"] = float(material_stats.get("unsupported_mass", 0.0)) + mass
		return
	if slot < _stain_life.size():
		_stain_life[slot] = settings.stain_lifetime if settings.stain_lifetime > 0.0 else -1.0
		_stain_active[slot] = 1
	_stamp_causality(slot, pos, mass)
	last_splats_spawned += 1

	# Ledger: where the material actually ended up.
	_led_surface_mass += mass
	_led_stains += 1
	# NOMINAL summed area: the ink ellipse this mark nominally covers. Kept as a
	# diagnostic only - it sums overlapping marks, so it is NOT coverage. See
	# unique_coverage_for_test() for the honest figure.
	var fitted_scale: float = _support.anchors[slot].tangent_frame.x.length() / maxf(basis.x.length(), 0.000001)
	_led_stain_area += PI * (visual_radius * elongation) * (visual_radius * across) * fitted_scale * fitted_scale
	_note_stain_extent(visual_radius * 2.0 * elongation * fitted_scale, visual_radius * 2.0 * across * fitted_scale, pos, normal)
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

	_accumulate_wet(profile, pos, normal, mass)

func _stamp_causality(slot: int, pos: Vector3, mass: float) -> void:
	_stain_serial += 1
	_stain_ids[slot] = _stain_serial
	_stain_drop_ids[slot] = _causal_drop
	_stain_event_ids[slot] = _causal_event if _causal_event >= 0 else _event_counter
	_record_causal({"action": "stain", "stain_id": _stain_serial, "slot": slot,
		"drop_id": _causal_drop, "event_id": _stain_event_ids[slot], "position": pos, "mass": mass})

func _accumulate_wet(profile: BloodProfile, pos: Vector3, normal: Vector3, mass: float) -> void:
	if mass <= 0 or not _support.anchors.has(_last_surface_slot): return
	var anchor: Dictionary = _support.anchors[_last_surface_slot]
	pos = anchor.surface_hit_position_ws
	normal = anchor.surface_normal_ws
	var key := "%d:%s:%s" % [anchor.owner_id, Vector3i((pos / settings.stability.wet_patch_cell_m).floor()), Vector3i((normal * 20).round())]
	var surface := _deposit_surface if _deposit_surface != null else surface_response(null, normal)
	if not _wet_patches.has(key):
		if _wet_patches.size() >= settings.fluid.max_wet_patches:
			var oldest: Variant = _wet_patches.keys()[0]
			_retained_patch_mass += float(_wet_patches[oldest].wet)
			_absorbed_retired += float(_wet_patches[oldest].absorbed)
			_wet_patches.erase(oldest)
			_pools.erase(oldest)
		_wet_patches[key] = {"wet": 0.0, "absorbed": 0.0, "surface": surface, "pos": pos, "normal": normal,
			"profile": profile, "owner": anchor.owner_id, "owner_transform": anchor.owner_transform,
			"age": 0.0, "eligible_age": 0.0, "state": "STATIC_WET", "running": false, "revision": 0, "started_revision": -1,
			"last_clock": _clock,
			"footprint": maxf(0.05, minf(anchor.tangent_frame.x.length(), anchor.tangent_frame.y.length())), "event": _causal_event}
		# Joins the round-robin scan order. Stale keys are swept by the scan.
		_wet_keys.append(key)
	var patch: Dictionary = _wet_patches[key]
	patch.wet += mass
	patch.age = 0.0
	patch.revision += 1
	if _suppress_runoff: patch.started_revision = patch.revision
	# Deposits extend a short spreading window; the area target is strictly
	# mass-backed. With no new material, no further target growth is possible.
	if normal.y > 0.55 and patch.wet + patch.absorbed >= settings.stability.pool_start_mass:
		if not _pools.has(key):
			_pools[key] = {"pos": pos, "normal": normal, "profile": profile, "slot": -1, "serial": -1,
				"target": 0.0, "rendered": 0.0, "credit": 0.0, "growth_until": 0.0, "owner": anchor.owner_id}
		var pool: Dictionary = _pools[key]
		pool.target = minf(settings.stability.pool_max_area_m2, (patch.wet + patch.absorbed) * settings.stability.pool_area_per_mass)
		pool.credit = minf(pool.target, pool.credit + minf(mass * settings.stability.pool_area_per_mass, settings.stability.pool_area_credit_per_deposit))
		pool.growth_until = _clock + settings.stability.pool_growth_window_s

## Advance every wet patch that still has something to do.
##
## THE PERFORMANCE REGRESSION LIVED HERE.
##
## A finished patch used to be marked "DRY_OR_EXHAUSTED" and left in the
## dictionary forever. The dictionary fills to max_wet_patches and then every
## physics frame re-scanned all of them - including hundreds of dead ones -
## doing an instance_from_id() lookup and a full Transform3D comparison each.
##
## Profiled: an arena with stains but NO new emission spent 476 ms over 90
## frames in here (5.3 ms/frame), about ten times the cost of a four-victim
## fight. The lag was never the droplets; it was the aftermath being rescanned.
##
## Exhausted patches are now retired out of the set. Every other site that
## looks a patch up already treats "missing" and "DRY_OR_EXHAUSTED" the same
## way, so removal matches the contract the rest of the file already assumes.
func _step_wet_patches(_delta: float) -> void:
	var start := Time.get_ticks_usec() if profile_stages else 0
	var total := _wet_keys.size()
	if total == 0:
		_profile_stage("wet_patch_updates", start)
		return
	# TIME-SLICED, not exhaustive.
	#
	# Every patch used to be visited every physics frame, and the expensive part
	# - instance_from_id() plus a full Transform3D comparison - happened BEFORE
	# any of the early-outs, so a patch sitting in STATIC_WET cost just as much
	# as one actively running. At the 1024-patch cap that is ~61k instance
	# lookups and transform compares per second, paid forever.
	#
	# Now a bounded slice is visited per frame, round-robin, and each patch
	# advances by the time since IT was last visited rather than by the frame
	# delta. Absorption, drying and runoff eligibility all operate on second
	# timescales, so a ~0.1 s revisit interval is invisible - while the cost
	# stops scaling with how much of the fight the arena is still holding.
	var budget: int = maxi(settings.stability.wet_updates_per_frame, 1)
	var visited := 0
	while visited < budget and not _wet_keys.is_empty():
		if _wet_cursor >= _wet_keys.size():
			_wet_cursor = 0
		var key: Variant = _wet_keys[_wet_cursor]
		if not _wet_patches.has(key):
			# Retired elsewhere: drop the stale key by swapping in the tail.
			_wet_keys[_wet_cursor] = _wet_keys[_wet_keys.size() - 1]
			_wet_keys.resize(_wet_keys.size() - 1)
			visited += 1
			continue
		visited += 1
		_wet_cursor += 1
		var patch: Dictionary = _wet_patches[key]
		var surface: BloodSurfaceResponse = patch.surface
		# Elapsed time for THIS patch, not for the frame.
		var delta: float = maxf(_clock - float(patch.last_clock), 0.0)
		patch.last_clock = _clock
		if delta <= 0.0:
			continue
		patch.age += delta
		var absorbed := float(patch.wet) * (1.0 - exp(-surface.absorption_rate * delta))
		patch.wet -= absorbed
		patch.absorbed += absorbed
		var owner := instance_from_id(patch.owner) as Node3D
		if not is_instance_valid(owner) or not owner.global_transform.is_equal_approx(patch.owner_transform) or patch.age >= settings.stability.wet_lifetime_s:
			_retained_patch_mass += patch.wet
			patch.wet = 0.0
			patch.state = "DRY_OR_EXHAUSTED"
			_wet_retire.append(key)
			continue
		if surface.absorption_rate > surface.runoff_mobility * 4.0:
			if patch.wet > 0.00001:
				patch.state = "ABSORBING"
			else:
				patch.state = "DRY_OR_EXHAUSTED"
				_wet_retire.append(key)
			continue
		if patch.running: patch.state = "RUNNING"; continue
		if patch.started_revision == patch.revision: patch.state = "STATIC_WET"; continue
		var ratio := BloodFluidModel.retention_ratio(patch.wet, patch.footprint, patch.normal, _gravity, surface, settings.fluid) / settings.stability.runoff_retention_scale
		if patch.wet < settings.runoff_mass_threshold or ratio <= 1.0:
			patch.state = "STATIC_WET"
			patch.eligible_age = 0.0
			continue
		patch.state = "RUNOFF_ELIGIBLE"
		patch.eligible_age += delta
		var delay := clampf(settings.stability.runoff_delay_max_s / ratio, settings.stability.runoff_delay_min_s, settings.stability.runoff_delay_max_s)
		if patch.eligible_age < delay: continue
		_active_wet_key = key
		var taken := _try_runoff(patch.profile, patch.pos, patch.normal, patch.wet, surface)
		_active_wet_key = ""
		if taken > 0:
			patch.wet -= taken
			patch.running = true
			patch.started_revision = patch.revision
			patch.state = "RUNNING"
			patch.eligible_age = 0.0
			_led_surface_mass -= taken
			if patch.normal.y > 0.6: _led_floor -= taken
			elif patch.normal.y < -0.6: _led_ceiling -= taken
			else: _led_wall -= taken
	# Retired outside the loop: erasing from a Dictionary while iterating it is
	# not safe. A patch that dries out simply stops existing, and new blood on
	# the same spot starts a fresh one - which is what _deposit_wet already did.
	if not _wet_retire.is_empty():
		for dead in _wet_retire:
			_absorbed_retired += float(_wet_patches[dead].absorbed) if _wet_patches.has(dead) else 0.0
			_wet_patches.erase(dead)
			# The pool goes with its patch, exactly as patch EVICTION already does.
			# Otherwise _pools keeps a row for every patch the arena has ever had
			# and stops being bounded by max_wet_patches. The stain itself is owned
			# by the surface layer and survives; it simply stops growing.
			_pools.erase(dead)
		_wet_retire.clear()
	_profile_stage("wet_patch_updates", start)

func _step_pools(delta: float) -> void:
	for key in _pools:
		var pool: Dictionary = _pools[key]
		if _clock > pool.growth_until or pool.rendered >= pool.target: continue
		if not _wet_patches.has(key) or _wet_patches[key].state == "DRY_OR_EXHAUSTED": continue
		if not can_query(1 + 8 * (settings.stability.max_support_shrinks + 1)) or frame_usage.stains >= settings.stability.stain_writes_per_frame: break
		var slot: int = pool.slot
		if slot >= 0 and _stain_active[slot] == 2:
			pool.growth_until = 0.0
			continue
		if slot < 0 or not _surface.is_active(slot) or _stain_ids[slot] != pool.serial:
			slot = _acquire_stain_slot(_cell_key(pool.pos))
			if slot < 0: continue
			pool.slot = slot
			pool.rendered = minf(pool.target, settings.stability.pool_initial_area_m2)
			_stain_birth[slot] = _clock
			_stain_active[slot] = 1
			_stamp_causality(slot, pool.pos, 0.0)
			pool.serial = _stain_ids[slot]
			var cell := _cell_key(pool.pos)
			_stain_cell[slot] = cell
			var owned: PackedInt32Array = _cell_slots.get(cell, PackedInt32Array())
			owned.append(slot)
			_cell_slots[cell] = owned
			_cell_bases[cell] = int(_cell_bases.get(cell, 0)) + 1
		else:
			var next_area := minf(minf(pool.target, pool.credit), pool.rendered + settings.stability.pool_growth_m2_s * delta)
			if next_area > pool.rendered: _stain_birth[slot] = _clock
			pool.rendered = next_area
		var diameter := sqrt(pool.rendered / PI) * 2.0 / settings.stability.pool_mask_occupancy
		var n: Vector3 = pool.normal
		var basis := Basis.looking_at(-n, Vector3.FORWARD if absf(n.y) > 0.95 else Vector3.UP)
		basis.x *= diameter
		basis.y *= diameter
		if not _write_surface(slot, Transform3D(basis, pool.pos + n * settings.stability.pool_surface_offset_m),
			settings.pooled_blood_color, Color(0, 0, 1, 2), settings.stability.pool_surface_offset_m):
			pool.growth_until = 0.0
			pool.slot = -1
		else:
			# Supported base + the retained directional impact marks above it are
			# separate scales of detail; the procedural rim breaks up large edges.
			var supported: Transform3D = _support.anchors[slot].transform
			pool.rendered = minf(pool.rendered, PI * supported.basis.x.length() * supported.basis.y.length() * pow(settings.stability.pool_mask_occupancy, 2) / 4.0)

func wet_mass_report() -> Dictionary:
	var wet := 0.0
	var absorbed := 0.0
	var moving := 0.0
	for patch in _wet_patches.values():
		wet += float(patch.wet)
		absorbed += float(patch.absorbed)
	for i in _runoff_count: moving += _runoff_mass[i]
	return {"wet": wet, "absorbed": absorbed + _absorbed_retired, "mobile": moving, "frozen_retained": _retained_patch_mass, "patches": _wet_patches.size()}

func _acquire_stain_slot(_key: int) -> int:
	# Never steal a visible stain. Proactive retirement below maintains headroom.
	# At hard saturation the caller retains/degrades incoming mass explicitly.
	return _surface.acquire(false)

func _begin_stain_fade(slot: int) -> bool:
	if _fade_count >= _fade_slots.size() or _stain_active[slot] != 1: return false
	if _clock - _stain_birth[slot] < settings.stability.fade_min_age_s: return false
	var width := 0.0
	if _support.anchors.has(slot):
		var frame: Basis = _support.anchors[slot].tangent_frame
		width = maxf(frame.x.length(), frame.y.length())
	var duration := settings.stability.fade_micro_s if width < 0.1 else settings.stability.fade_medium_s
	if width > 0.5: duration = settings.stability.fade_pool_s
	_fade_slots[_fade_count] = slot
	_fade_left[_fade_count] = duration
	_fade_duration[_fade_count] = duration
	_fade_count += 1
	_stain_active[slot] = 2
	return true

## Drop a stain out of its cell index, so a cell that empties stops being a
## candidate for eviction and its count stays honest.
func _forget_stain(slot: int) -> void:
	# Slot release/eviction must also retire its geometry ownership.
	# SurfaceSupport.validate_owners performs this itself while iterating.
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
		_cell_mass.erase(key)
		_cell_bases.erase(key)
	else:
		_cell_slots[key] = owned
		_cells[key] = owned.size()

## The wet base layer under a saturated patch.
##
## Deliberately NOT a replacement for the stains already there: it is laid at a
## smaller surface offset, so it sits UNDER the fine spatter and the directional
## evidence survives. Big, dark, irregular, and it only appears once a cell has
## genuinely taken that much material.
func _place_soak_base(profile: BloodProfile, pos: Vector3, normal: Vector3, mass: float) -> void:
	# Compatibility hook: a request contributes deposited mass, never an instant
	# fully-sized reinforcement quad. It must pass through a supported contact.
	_place_stain(profile, pos, normal, Vector3.DOWN, minf(_stain_radius(profile, mass), 0.1), mass)

func _note_stain_extent(width_m: float, height_m: float, at: Vector3, normal: Vector3) -> void:
	if not synchronous_test_mode and not record_causality and not settings.debug_patterns: return
	var start := Time.get_ticks_usec() if profile_stages else 0
	_led_extents.append(maxf(width_m, height_m))
	# Stamp the footprint into a coarse grid, as an ELLIPSE ON THE MARK'S OWN
	# SURFACE PLANE.
	#
	# Stamping a square of the longest side on the XZ plane inflated every
	# elongated mark by the ratio of its axes, and put wall stains in the wrong
	# plane entirely - which made "unique coverage" exceed the nominal summed
	# area and turned the honest metric into another overstatement.
	var cell := maxf(settings.coverage_cell_size, 0.01)
	# The two world axes the surface actually spans: everything except the one
	# the normal points along.
	var n := normal.abs()
	var axis_a := 0
	var axis_b := 2
	if n.y >= n.x and n.y >= n.z:
		axis_a = 0
		axis_b = 2          # floor or ceiling: spans X and Z
	elif n.x >= n.z:
		axis_a = 1
		axis_b = 2          # wall facing X: spans Y and Z
	else:
		axis_a = 0
		axis_b = 1          # wall facing Z: spans X and Y

	var sa: float = maxf(width_m * 0.5, cell * 0.5)
	var sb: float = maxf(height_m * 0.5, cell * 0.5)
	var ha: int = clampi(int(ceil(sa / cell)), 0, 24)
	var hb: int = clampi(int(ceil(sb / cell)), 0, 24)
	var base := Vector3i(
		int(floor(at.x / cell)), int(floor(at.y / cell)), int(floor(at.z / cell))
	)
	for da in range(-ha, ha + 1):
		for db in range(-hb, hb + 1):
			# Ellipse, not bounding box.
			var ua := float(da) * cell / sa
			var ub := float(db) * cell / sb
			if ua * ua + ub * ub > 1.0:
				continue
			var c := base
			c[axis_a] += da
			c[axis_b] += db
			_coverage_cells[
				(c.x + 4096) | ((c.y + 2048) << 13) | ((c.z + 4096) << 26)
			] = true
	_profile_stage("coverage_diagnostic", start)


## Approximate UNIQUE visible coverage in square metres, from the coarse grid.
## This is the honest figure; nominal summed area is not.
func unique_coverage_for_test() -> float:
	var cell := maxf(settings.coverage_cell_size, 0.01)
	return float(_coverage_cells.size()) * cell * cell


## Final visible longest dimension of every mark the last event laid, bucketed
## the way the brief asks: <5, 5-10, 10-20, 20-40, 40-80, >80 cm.
func size_distribution_for_test() -> Dictionary:
	var buckets := {"<5cm": 0, "5-10cm": 0, "10-20cm": 0, "20-40cm": 0, "40-80cm": 0, ">80cm": 0}
	for e in _led_extents:
		var cm: float = e * 100.0
		if cm < 5.0:
			buckets["<5cm"] += 1
		elif cm < 10.0:
			buckets["5-10cm"] += 1
		elif cm < 20.0:
			buckets["10-20cm"] += 1
		elif cm < 40.0:
			buckets["20-40cm"] += 1
		elif cm < 80.0:
			buckets["40-80cm"] += 1
		else:
			buckets[">80cm"] += 1
	return buckets


## Median and 90th percentile visible width, in metres.
func stain_percentiles_for_test() -> Dictionary:
	if _led_extents.is_empty():
		return {"median": 0.0, "p90": 0.0, "count": 0}
	var sorted := Array(_led_extents)
	sorted.sort()
	var n := sorted.size()
	return {
		"median": float(sorted[n / 2]),
		"p90": float(sorted[mini(int(float(n) * 0.9), n - 1)]),
		"count": n,
	}


## Represented-mass accounting for the last event. This is the Part A
## diagnostic: it makes a weak aftermath traceable to the stage that lost the
## mass rather than something to be guessed at from particle counts.
func mass_ledger() -> Dictionary:
	return {
		"release_blood_mass": _led_blood,
		"contact_retained_mass": last_release.contact_retained_mass if last_release != null else 0.0,
		"release_tissue_mass": _led_tissue,
		"air_visual_mass_represented": _led_air_mass,
		"physical_mass_represented": _led_physical_mass,
		"physical_mass_that_hit_world": _led_hit_world,
		"physical_mass_that_timed_out": _led_timed_out,
		"physical_mass_recycled": _led_recycled,
		"surface_mass_deposited": _led_surface_mass,
		"stain_count": _led_stains,
		"mean_stain_area": _led_stain_area / maxf(float(_led_stains), 1.0),
		"nominal_summed_area": _led_stain_area,
		"estimated_total_stain_area": _led_stain_area,
		"approx_unique_visible_coverage": unique_coverage_for_test(),
		"surface_mass_floor": _led_floor,
		"surface_mass_wall": _led_wall,
		"surface_mass_ceiling": _led_ceiling,
		"tissue_mass_deposited": _led_tissue_deposited,
		"runoff_mass_claimed": _led_runoff_mass,
	}



# --------------------------------------------------------------------------
# Wall runoff
# --------------------------------------------------------------------------
#
# Blood on a wall is material, not a sticker. A heavy enough deposit starts to
# RUN: a rivulet creeps down the surface under gravity, darkening the path it
# takes, and drops what is left of itself where it stops.
#
# This is emphatically NOT a fluid simulation. It is a small fixed pool of
# points that walk downward on the plane they were born on, laying one narrow
# stain every `runoff_step` metres and spending mass as they go. Cost is a
# handful of positions per frame plus one short ray each time a rivulet checks
# the wall is still under it.
#
# MASS IS CONSERVED. A rivulet's budget is carved OUT of the deposit that
# spawned it - the stain it came from is made correspondingly smaller - so
# running blood can never invent material.

## Does this surface normal belong to a wall rather than a floor or ceiling?
func _is_wall(normal: Vector3) -> bool:
	return absf(normal.dot(Vector3.UP)) < settings.wall_normal_threshold


## Consider starting a rivulet from a wall deposit.
func _try_runoff(profile: BloodProfile, pos: Vector3, normal: Vector3, mass: float, surface: BloodSurfaceResponse = null) -> float:
	if _suppress_runoff or mass < settings.runoff_mass_threshold or _runoff_count >= _runoff_pos.size(): return 0.0
	if surface == null: surface = surface_response(null, normal)
	var tangent_gravity := _gravity.slide(normal)
	if tangent_gravity.length() < 0.1: return 0.0
	var width := _stain_radius(profile, mass) * 2.0
	if _active_wet_key != "" and _wet_patches.has(_active_wet_key): width = _wet_patches[_active_wet_key].footprint
	var ratio := BloodFluidModel.retention_ratio(mass, width, normal, _gravity, surface, settings.fluid) / settings.stability.runoff_retention_scale
	if ratio <= 1.0 or surface.absorption_rate > surface.runoff_mobility * 4.0: return 0.0
	if not _spend("runoff", settings.stability.runoff_starts_per_frame): return 0.0
	var taken := mass * settings.runoff_mass_share
	var i := _runoff_count
	_runoff_count += 1
	_runoff_patch[i] = _active_wet_key
	_runoff_pos[i] = pos
	_runoff_last_mark[i] = pos
	_runoff_dir[i] = tangent_gravity.normalized()
	_runoff_normal[i] = normal
	_runoff_mass[i] = taken
	_runoff_age[i] = 0.0
	_runoff_since[i] = 0.0
	_runoff_profile[i] = profile
	_runoff_surface[i] = surface
	_runoff_drop_id[i] = _causal_drop
	_runoff_event_id[i] = _causal_event if _causal_event >= 0 else _event_counter
	_runoff_speed[i] = settings.runoff_speed * surface.runoff_mobility * tangent_gravity.length() / maxf(_gravity.length(), 0.01) * clampf(taken * 40.0, 0.6, 2.2)
	_runoff_start_mass[i] = taken
	_led_runoff_mass += taken
	return taken

func _step_runoff(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	for j in _runoff_count: _runoff_age[j] += delta
	var i := 0
	while i < _runoff_count:
		if _runoff_age[i] >= settings.runoff_lifetime:
			_finish_runoff(i, _runoff_pos[i], _runoff_dir[i])
			continue
		if not can_query(3 + 8 * (settings.stability.max_support_shrinks + 1)) or frame_usage.stains >= settings.stability.stain_writes_per_frame - 1: break
		var owner_key := _runoff_patch[i]
		if owner_key != "" and (not _wet_patches.has(owner_key) or _wet_patches[owner_key].state == "DRY_OR_EXHAUSTED"):
			_retained_patch_mass += _runoff_mass[i]
			_retire_runoff(i)
			continue
		var normal := _runoff_normal[i]
		var dir := _gravity.slide(normal).normalized()
		if dir.length_squared() < 0.01:
			_finish_runoff(i, _runoff_pos[i], dir)
			continue
		var left_share := clampf(_runoff_mass[i] / maxf(_runoff_start_mass[i], 0.000001), 0.0, 1.0)
		var step := _runoff_speed[i] * lerpf(0.35, 1.0, left_share) * delta
		var next := _runoff_pos[i] + dir * step
		_runoff_since[i] += step
		if _runoff_since[i] >= settings.runoff_step or _runoff_age[i] >= settings.runoff_lifetime:
			# Detect a real floor contact along the advancing front, before the
			# wall probe can walk through a wall/floor junction.
			_ray.from = _runoff_last_mark[i] + normal * 0.025
			_ray.to = next + normal * 0.025 + dir * 0.025
			var floor_hit := _query()
			if not floor_hit.is_empty() and (floor_hit.normal as Vector3).y > 0.5:
				_queue_contact(_runoff_profile[i], floor_hit.position, floor_hit.normal, dir,
					_stain_radius(_runoff_profile[i], _runoff_mass[i]), _runoff_mass[i], {}, floor_hit,
					_runoff_drop_id[i], _runoff_event_id[i], true)
				_retire_runoff(i)
				continue
			_ray.from = next + normal * 0.08
			_ray.to = next - normal * 0.18
			var hit := _query()
			if hit.is_empty() or (hit.normal as Vector3).dot(normal) < 0.7:
				# An actual free falling terminal parcel; no teleport to the floor.
				_finish_runoff(i, _runoff_pos[i] + normal * 0.025, Vector3.DOWN, true)
				continue
			var from := _runoff_last_mark[i]
			next = hit.position
			_runoff_normal[i] = hit.normal
			_runoff_last_mark[i] = next
			_runoff_since[i] = 0.0
			var spend := _runoff_mass[i] * 0.18
			_runoff_mass[i] -= spend
			var width := clampf(sqrt(_runoff_start_mass[i]) * settings.fluid.rivulet_width_gain,
				settings.fluid.rivulet_min_width, settings.fluid.rivulet_max_width) * lerpf(settings.runoff_taper_min, 1.0, left_share)
			_causal_drop = _runoff_drop_id[i]
			_causal_event = _runoff_event_id[i]
			_place_streak(_runoff_profile[i], (from + next) * 0.5, hit.normal, dir,
				width / (2.0 * settings.runoff_width), spend, from.distance_to(next))
			_causal_drop = -1
			_causal_event = -1
			_retained_patch_mass += spend
		_runoff_pos[i] = next
		_runoff_dir[i] = dir
		if _runoff_mass[i] <= 0.00002 or _runoff_age[i] >= settings.runoff_lifetime:
			_finish_runoff(i, next, dir)
			continue
		i += 1

func _finish_runoff(i: int, at: Vector3, dir: Vector3, falling := false) -> void:
	var profile := _runoff_profile[i]
	var mass := _runoff_mass[i]
	if profile != null and mass > 0.0:
		var admitted := -1
		if falling:
			if _spend("wall_drops", settings.stability.wall_drops_per_frame):
				admitted = _emit_representative(profile, at, Vector3.DOWN * 0.3, 0.0, mass, 1.0, 0.003,
					-1, _runoff_event_id[i], 0, 0, _runoff_drop_id[i])
			if admitted < 0:
				_queue_coarse(profile, at, Vector3.DOWN, mass, _runoff_event_id[i], true)
				_retire_runoff(i)
				return
		if admitted < 0:
			_suppress_runoff = true
			_causal_drop = _runoff_drop_id[i]
			_causal_event = _runoff_event_id[i]
			_impact_response = {"aspect": 1.0, "outcome": BloodFluidModel.Impact.DEPOSIT}
			_deposit_surface = _runoff_surface[i]
			_place_stain(profile, at, _runoff_normal[i], dir, _stain_radius(profile, mass), mass)
			_impact_response = {}
			_deposit_surface = null
			_causal_drop = -1
			_causal_event = -1
			_suppress_runoff = false
	_retire_runoff(i)

func _retire_runoff(i: int) -> void:
	var key := _runoff_patch[i]
	if _wet_patches.has(key): _wet_patches[key].running = false
	var last := _runoff_count - 1
	if i != last:
		_runoff_patch[i] = _runoff_patch[last]
		_runoff_pos[i] = _runoff_pos[last]
		_runoff_last_mark[i] = _runoff_last_mark[last]
		_runoff_surface[i] = _runoff_surface[last]
		_runoff_drop_id[i] = _runoff_drop_id[last]
		_runoff_event_id[i] = _runoff_event_id[last]
		_runoff_dir[i] = _runoff_dir[last]
		_runoff_normal[i] = _runoff_normal[last]
		_runoff_mass[i] = _runoff_mass[last]
		_runoff_age[i] = _runoff_age[last]
		_runoff_since[i] = _runoff_since[last]
		_runoff_speed[i] = _runoff_speed[last]
		_runoff_start_mass[i] = _runoff_start_mass[last]
		_runoff_profile[i] = _runoff_profile[last]
	_runoff_count -= 1


## A narrow mark along a rivulet's path: long in the direction it is running,
## thin across it. Deliberately not _place_stain, which would re-trigger runoff
## and re-run the whole incidence model on something that is already a streak.
func _place_streak(
	profile: BloodProfile, pos: Vector3, normal: Vector3, dir: Vector3,
	radius: float, mass: float, span := 0.0
) -> void:
	var key := _cell_key(pos)
	var slot := _acquire_stain_slot(key)
	if slot < 0:
		return
	_cells[key] = int(_cells.get(key, 0)) + 1
	if not _cell_slots.has(key):
		_cell_slots[key] = PackedInt32Array()
	var owned: PackedInt32Array = _cell_slots[key]
	owned.append(slot)
	_cell_slots[key] = owned
	if slot < _stain_cell.size():
		_stain_cell[slot] = key

	var reference := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var basis := Basis.looking_at(-normal, reference)
	var along := dir.slide(normal)
	if along.length_squared() > 0.0001:
		along = along.normalized()
		var roll := atan2(along.dot(basis.y.normalized()), along.dot(basis.x.normalized()))
		basis = basis.rotated(normal, roll)
	# Long down the run, narrow across it, and at LEAST long enough to bridge
	# the gap to the previous segment with a little overlap.
	var streak := int(BloodTypes.Stain.STREAK)

	var length: float = maxf(span * settings.runoff_overlap, radius * 4.0)
	basis.x *= length
	basis.y *= radius * 2.0 * settings.runoff_width

	# A run is wet and dark - darker than the spatter it came from.
	var c := settings.dark_fresh_blood_color.lerp(settings.pooled_blood_color, 0.35)
	if not _write_surface(
		slot,
		Transform3D(basis, pos + normal * settings.stability.runoff_surface_offset_m),
		c,
		Color(
			float(int(BloodTypes.Stain.STREAK) % ATLAS_COLS),
			float(int(BloodTypes.Stain.STREAK) / ATLAS_COLS), 1.0, 1.0
		), settings.stability.runoff_surface_offset_m
	): return
	if slot < _stain_life.size():
		_stain_life[slot] = -1.0
		_stain_active[slot] = 1
	_stamp_causality(slot, pos, mass)
	last_splats_spawned += 1
	_led_surface_mass += mass
	_led_stains += 1
	_led_stain_area += length * (radius * 2.0 * settings.runoff_width)
	_note_stain_extent(length, radius * 2.0 * settings.runoff_width, pos, normal)
	if normal.y > 0.6: _led_floor += mass
	elif normal.y < -0.6: _led_ceiling += mass
	else: _led_wall += mass


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
	# Fixed scan budget, even with thousands of permanent stains. Fade updates
	# touch at most max_fading_stains custom-data floats, one layer commit.
	var pressure := _surface.free_slots() < settings.stability.fade_reserve_slots
	for scan in mini(settings.stability.fade_scan_per_step, _stain_active.size()):
		var slot := _fade_scan
		_fade_scan = (_fade_scan + 1) % _stain_active.size()
		if _stain_active[slot] != 1: continue
		var expired := settings.stain_lifetime > 0 and _clock - _stain_birth[slot] >= settings.stain_lifetime
		if pressure or expired: _begin_stain_fade(slot)
	var i := _fade_count - 1
	while i >= 0:
		var slot := _fade_slots[i]
		_fade_left[i] = maxf(0.0, _fade_left[i] - delta)
		if _stain_active[slot] != 2 or not _surface.is_active(slot):
			_fade_left[i] = 0.0
		else:
			_surface.set_fade(slot, _fade_left[i] / maxf(_fade_duration[i], 0.001))
		if _fade_left[i] <= 0.0:
			if _stain_active[slot] == 2:
				_surface.release(slot)
				_support.forget(slot)
				_stain_active[slot] = 0
				_forget_stain(slot)
			_fade_count -= 1
			_fade_slots[i] = _fade_slots[_fade_count]
			_fade_left[i] = _fade_left[_fade_count]
			_fade_duration[i] = _fade_duration[_fade_count]
		i -= 1

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
func add_remnant(wound: Wound, at: Vector3, budget := -1.0) -> void:
	if wound == null or wound.state != Wound.State.ATTACHED_LIVING: return
	var transfer := minf(wound.remaining, fallback_reservoir.remnant_reserve) if budget < 0 else budget
	if transfer <= 0: wound.exhaust(); return
	while _remnants.size() >= settings.max_remnants:
		var oldest: Wound = _remnants.pop_front()
		_retained_patch_mass += oldest.remaining
		oldest.exhaust()
		_pending_remnants.erase(oldest)
		_remnant_family.pop_front()
	wound.detach(at, -INF, transfer, settings.remnant_lifetime)
	_remnants.append(wound)
	_remnant_family.append(int(wound.family))
	_pending_remnants.append(wound)

func _resolve_remnant_support() -> void:
	for w in _pending_remnants.duplicate():
		if not can_query(): break
		_ray.from = w.world_anchor
		_ray.to = w.world_anchor + Vector3.DOWN * 12.0
		var below := _query()
		if below.is_empty():
			material_stats["unsupported_remnant_mass"] = float(material_stats.get("unsupported_remnant_mass", 0.0)) + w.remaining
			_retained_patch_mass += w.remaining
			w.exhaust()
		else:
			w.rest_y = (below.position as Vector3).y + 0.015
			w.last_valid_surface = {"position": below.position, "normal": below.normal, "collider_id": below.collider_id}
		_pending_remnants.erase(w)

func _tick_wounds(delta: float) -> void:
	_resolve_remnant_support()
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
		if _pending_remnants.has(w): continue
		if not w.last_valid_surface.is_empty() and not is_instance_id_valid(w.last_valid_surface.collider_id):
			_retained_patch_mass += w.remaining
			w.exhaust()
		# The source collapses toward the floor while it bleeds out.
		w.fall(delta)
		var before := w.remaining
		var amount := w.tick(delta)
		_retained_patch_mass += maxf(0.0, before - amount - w.remaining)
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

func _update_stability_debug() -> void:
	if _debug_label == null:
		var canvas := CanvasLayer.new()
		add_child(canvas)
		_debug_label = Label.new()
		_debug_label.position = Vector2(12, 260)
		_debug_label.add_theme_font_size_override("font_size", 15)
		canvas.add_child(_debug_label)
		_debug_mesh = ImmediateMesh.new()
		var instance := MeshInstance3D.new()
		instance.mesh = _debug_mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		instance.material_override = mat
		add_child(instance)
	_debug_label.visible = true
	var text := "BLOOD DEV | queries %d/%d | queue %d | contacts %d | coarse %d\n" % [frame_usage.queries, settings.stability.queries_per_frame, _presentation_queue.size(), _contacts.size(), _coarse_jobs.size()]
	text += "stain writes %d/%d | wet %d | runoff %d | audio clusters %d / voices %d\n" % [frame_usage.stains, settings.stability.stain_writes_per_frame, _wet_patches.size(), _runoff_count, _audio.clusters.size(), _audio.peak_voices]
	text += "fade %d/%d | trail slots %d | audio submitted %d / filtered %d / played %d\n" % [_fade_count, _fade_slots.size(), settings.stability.max_trails, _audio.submitted, _audio.filtered, _audio.played]
	_debug_mesh.clear_surfaces()
	var has_lines := not _wet_patches.is_empty() or not _support.last_samples.is_empty() or not _remnants.is_empty()
	if not has_lines:
		_debug_label.text = text
		return
	_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for key in _wet_patches.keys().slice(0, 8):
		var patch: Dictionary = _wet_patches[key]
		text += "%s wet %.4f age %.1f\n" % [patch.state, patch.wet, patch.age]
		_debug_mesh.surface_set_color(Color.GREEN)
		_debug_mesh.surface_add_vertex(patch.pos)
		_debug_mesh.surface_add_vertex(patch.pos + patch.normal * 0.18)
	for pos in _support.last_samples:
		_debug_mesh.surface_set_color(Color.YELLOW)
		_debug_mesh.surface_add_vertex(pos - Vector3.RIGHT * 0.015)
		_debug_mesh.surface_add_vertex(pos + Vector3.RIGHT * 0.015)
	for w in _remnants:
		text += "remnant #%d mass %.4f life %.2f\n" % [w.death_id, w.remaining, maxf(0, w.lifetime - w.age)]
		_debug_mesh.surface_set_color(Color.CYAN)
		_debug_mesh.surface_add_vertex(w.world_anchor)
		_debug_mesh.surface_add_vertex(w.world_anchor + Vector3.UP * 0.15)
	for reservoir in _reservoirs:
		if not is_instance_valid(reservoir): continue
		for wound in reservoir.wounds:
			text += "attached mass %.4f generation %d\n" % [wound.remaining, wound.owner_generation]
	_debug_mesh.surface_end()
	_debug_label.text = text


# --------------------------------------------------------------------------
# Cast-off
# --------------------------------------------------------------------------

## Droplets flung along a weapon's swing arc by a bloodied blade. Not a hit -
## there is no victim and no damage, only material leaving the weapon along the
## direction it is actually travelling.
func cast_off(
	origin: Vector3, tip_velocity: Vector3, damage_type: BloodTypes.DamageType,
	count: int, _energy: float, load := 0.5, angular_speed := 12.0, max_spend := 0.5
) -> float:
	_begin_frame()
	var profile := _profiles.get(int(damage_type)) as BloodProfile
	if profile == null or count <= 0: return 0.0
	var fraction := BloodFluidModel.castoff_fraction(load, tip_velocity, angular_speed, settings.fluid)
	var spent := minf(load, max_spend) * fraction
	if spent <= 0.0: return 0.0
	var sampled := maxi(1, int(round(count * settings.quality_scale())))
	var n := mini(mini(sampled, 64), _medium.free_slots())
	if n <= 0: return 0.0
	_event_counter += 1
	var mass := spent * settings.fluid.castoff_load_mass
	var axis := tip_velocity.normalized()
	var frame := _basis_for_axis(axis)
	var admitted := 0
	for j in n:
		var velocity := tip_velocity + frame.x * _rng.randf_range(-0.2, 0.2) + frame.y * _rng.randf_range(-0.2, 0.2)
		var d := _rng.randf_range(0.0008, 0.003)
		var id := _emit_representative(profile, origin, velocity, 0.0, mass / n, 1.0, d, -1, _event_counter)
		if id >= 0: admitted += 1
	_record_causal({"action": "castoff", "event_id": _event_counter, "mass": mass * admitted / n,
		"tip_velocity": tip_velocity, "angular_speed": angular_speed, "load_spent": spent * admitted / n})
	_wake()
	return spent * admitted / n

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


## Lay ONE stain of an explicitly chosen variant at an explicitly chosen visible
## diameter. The render fixture uses it to put every atlas cell side by side at
## the same quad size, which is the only way to see whether per-instance atlas
## selection is actually reaching the GPU.
func place_variant_for_test(
	profile: BloodProfile, pos: Vector3, shape: int, visible_diameter_m: float
) -> int:
	var slot := _acquire_stain_slot(_cell_key(pos))
	if slot < 0:
		return -1
	var normal := Vector3.UP
	var basis := Basis.looking_at(-normal, Vector3.FORWARD)
	var quad := quad_for_visible_diameter(visible_diameter_m, shape)
	basis.x *= quad.x
	basis.y *= quad.y
	_surface.write(
		slot,
		Transform3D(basis, pos + normal * settings.surface_offset),
		profile.env_color,
		# No bloom stamp: fixture marks are meant to be measured at final size.
		Color(float(shape % ATLAS_COLS), float(shape / ATLAS_COLS), 1.0, 0.0)
	)
	if slot < _stain_life.size():
		_stain_life[slot] = -1.0
		_stain_active[slot] = 1
		_stain_cell[slot] = _cell_key(pos)
	return slot


## The final world-space basis of one stain slot, so a test can prove the
## transform that reached the MultiMesh is the one that was intended.
## Turn on the CPU-side mirror of what the surface layer submits. Headless runs
## cannot read per-instance data back out of the dummy RenderingServer, so this
## is how a test follows the value to the last step before the GPU.
func record_stain_writes_for_test() -> void:
	_surface.begin_recording()


func stain_transform_for_test(slot: int) -> Transform3D:
	if _surface.record_writes and slot >= 0 and slot < _surface.recorded_xform.size():
		return _surface.recorded_xform[slot]
	return _surface.multimesh.get_instance_transform(slot)


func stain_custom_for_test(slot: int) -> Color:
	if _surface.record_writes and slot >= 0 and slot < _surface.recorded_custom.size():
		return _surface.recorded_custom[slot]
	return _surface.multimesh.get_instance_custom_data(slot)


func is_wall_for_test(normal: Vector3) -> bool:
	return _is_wall(normal)


## The elongation a stain would get on this surface at this angle. Exposed so a
## test can prove a wall does not behave like a floor turned sideways.
func stain_elongation_for_test(
	profile: BloodProfile, normal: Vector3, travel: Vector3
) -> float:
	var incidence: float = clampf(absf(travel.normalized().dot(normal)), 0.05, 1.0)
	if _is_wall(normal):
		if incidence < settings.wall_glancing_incidence:
			return clampf(1.0 / incidence, 1.0, settings.wall_streak_ratio)
		return clampf(1.0 / incidence, 1.0, profile.env_streak_ratio)
	return clampf(1.0 / incidence, 1.0, profile.env_streak_ratio)


## Lay one deposit directly, bypassing an event. Tests use it to drive the
## surface and runoff rules without having to aim a weapon at a wall.
func place_stain_for_test(
	profile: BloodProfile, pos: Vector3, normal: Vector3, travel: Vector3, mass: float
) -> void:
	_place_stain(profile, pos, normal, travel, _stain_radius(profile, mass), mass)


func runoff_position_for_test(index: int) -> Vector3:
	if index < 0 or index >= _runoff_count:
		return Vector3.ZERO
	return _runoff_pos[index]


## SCREEN-SPACE SANITY CHECK.
##
## A mark that is geometrically correct and one pixel wide on screen is still
## invisible. This converts a world-space width into the pixels it covers at a
## given viewing distance, so readability can be argued from numbers rather than
## from hope.
##
##     px = width_m * screen_height_px / (2 * distance_m * tan(fov/2))
##
## Developer diagnostics only.
static func screen_pixels_for(
	width_m: float, distance_m: float, fov_degrees := 90.0, screen_height_px := 1080.0
) -> float:
	var half := tan(deg_to_rad(clampf(fov_degrees, 1.0, 179.0)) * 0.5)
	return width_m * screen_height_px / maxf(2.0 * distance_m * half, 0.0001)


## Everything Part 21 of the brief asks for, in one place: what the last event
## actually left on the world.
func aftermath_report_for_test() -> Dictionary:
	var led := mass_ledger()
	var pct := stain_percentiles_for_test()
	var bases := 0
	var widest_base := 0.0
	var pooled := int(BloodTypes.Stain.POOLED)
	var want_r := float(pooled % ATLAS_COLS)
	var want_g := float(pooled / ATLAS_COLS)
	if _surface.record_writes:
		for slot in _surface.capacity:
			var c: Color = _surface.recorded_custom[slot]
			if is_equal_approx(c.r, want_r) and is_equal_approx(c.g, want_g):
				bases += 1
				widest_base = maxf(widest_base, _surface.recorded_xform[slot].basis.x.length())
	return {
		"stain_count": led["stain_count"],
		"nominal_summed_area": led["nominal_summed_area"],
		"approx_unique_visible_coverage": led["approx_unique_visible_coverage"],
		"median_visible_width": pct["median"],
		"p90_visible_width": pct["p90"],
		"soak_base_count": bases,
		"soak_base_widest_quad": widest_base,
		"surface_mass_floor": led["surface_mass_floor"],
		"surface_mass_wall": led["surface_mass_wall"],
		"surface_mass_ceiling": led["surface_mass_ceiling"],
		"median_px_at_4m": screen_pixels_for(pct["median"], 4.0),
		"median_px_at_12m": screen_pixels_for(pct["median"], 12.0),
		"p90_px_at_12m": screen_pixels_for(pct["p90"], 12.0),
	}


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
		"runoff": _runoff_count,
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
	_fade_count = 0
	_fade_scan = 0
	_presentation_queue.clear()
	_contacts.clear()
	_coarse_jobs.clear()
	_pools.clear()
	_pending_remnants.clear()
	if _support != null: _support.clear()
	if _audio != null: _audio.clear()
	queued_blood_mass = 0.0
	accepted_blood_mass = 0.0
	accepted_tissue_mass = 0.0
	_emission_flags = 0
	_budget_frame = -1
	_eviction_frame = -1
	peak_frame_usage.clear()
	coalesced_contacts = 0
	for key in frame_usage: frame_usage[key] = 0
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
	_runoff_count = 0
	_wet_patches.clear()
	_wet_keys.clear()
	_wet_cursor = 0
	_wet_retire.clear()
	_retained_patch_mass = 0.0
	_absorbed_retired = 0.0
	causal_records.clear()
	material_stats = {"collisions": 0, "breakups": 0, "ligaments": 0, "escaped_mass": 0.0, "size_warnings": 0}
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
	_begin_frame()
	_clock += delta
	_step_stains(delta)
	_support.validate_owners()
	var stage := Time.get_ticks_usec() if profile_stages else 0
	_flush_presentation()
	_profile_stage("presentation_queue", stage)
	_step_wet_patches(delta)
	stage = Time.get_ticks_usec() if profile_stages else 0
	if _rep_count > 0:
		_step_representatives(delta)
	_profile_stage("physical_simulation", stage)
	stage = Time.get_ticks_usec() if profile_stages else 0
	if _sol_count > 0:
		_step_solids(delta)
	_profile_stage("tissue_simulation", stage)
	stage = Time.get_ticks_usec() if profile_stages else 0
	if _runoff_count > 0:
		_step_runoff(delta)
	_profile_stage("runoff_updates", stage)
	if not _reservoirs.is_empty() or not _remnants.is_empty():
		_tick_wounds(delta)
	stage = Time.get_ticks_usec() if profile_stages else 0
	_drain_coarse()
	_profile_stage("coarse_queries", stage)
	stage = Time.get_ticks_usec() if profile_stages else 0
	_drain_contacts()
	_profile_stage("contact_clusters", stage)
	stage = Time.get_ticks_usec() if profile_stages else 0
	_step_pools(delta)
	_profile_stage("pool_updates", stage)
	var audio_start := Time.get_ticks_usec() if profile_stages else 0
	frame_usage.audio += _audio.advance(delta, maxi(0, settings.stability.audio_events_per_frame - int(frame_usage.audio)))
	_profile_stage("audio_scheduling", audio_start)
	if settings.debug_patterns: _update_stability_debug()
	elif _debug_label != null:
		_debug_label.visible = false
		_debug_mesh.clear_surfaces()


## Cheap visual material runs on the render clock, where smoothness matters and
## exactness does not.
func _process(delta: float) -> void:
	if _air_count > 0:
		_step_air(delta)
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

	# Unit-diameter rounded liquid geometry, shared by three batched layers.
	var drop := SphereMesh.new()
	drop.radius = 0.5
	drop.height = 1.0
	drop.radial_segments = 8
	drop.rings = 4
	_micro = _make_layer(drop, _blood_material(null), settings.max_micro)
	var liquid_material := ShaderMaterial.new()
	liquid_material.shader = load("res://presentation/gore/blood_liquid.gdshader")
	liquid_material.set_shader_parameter("wet_highlight_color", settings.wet_highlight_color)
	var bead := SphereMesh.new()
	bead.radius = 0.5
	bead.height = 1.0
	bead.radial_segments = 12
	bead.rings = 6
	# SMALL and MEDIUM get DIFFERENT readability budgets, so the material is
	# duplicated once at load. MEDIUM is the primary readable airborne blood and
	# earns the larger boost; SMALL gets a smaller one; MICRO uses the flat
	# material above and gets none at all, which is the intended hierarchy.
	liquid_material.set_shader_parameter("readability_gain", settings.small_readability_gain)
	liquid_material.set_shader_parameter("readability_ref_m", settings.readability_reference_m)
	liquid_material.set_shader_parameter("readability_max", settings.readability_max_scale)
	var medium_material: ShaderMaterial = liquid_material.duplicate()
	medium_material.set_shader_parameter("readability_gain", settings.medium_readability_gain)
	_small = _make_layer(bead, liquid_material, settings.max_small)
	_medium = _make_layer(bead, medium_material, settings.max_medium)

	# LARGE: real geometry, lit, so tissue reads as solid matter rather than as
	# another flat sprite.
	var solid_mat := StandardMaterial3D.new()
	solid_mat.vertex_color_use_as_albedo = true
	solid_mat.roughness = 0.62
	_large = _make_layer(TissueDebris.fragment_mesh(), solid_mat, settings.max_large)

	# SURFACE: the arena's memory. One material, seven shapes, via the atlas.
	_surface = _make_layer(quad, _stain_material(_stain_atlas), settings.max_surface)

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
	var physical_cap := settings.max_medium + settings.max_small
	_rep_slot.resize(physical_cap)
	_rep_pos.resize(physical_cap)
	_rep_vel.resize(physical_cap)
	_rep_life.resize(physical_cap)
	_rep_size.resize(physical_cap)
	_rep_mass.resize(physical_cap)
	_rep_stretch.resize(physical_cap)
	_rep_color.resize(physical_cap)
	_rep_profile.resize(physical_cap)
	_rep_previous.resize(physical_cap)
	_rep_diameter.resize(physical_cap)
	_rep_kind.resize(physical_cap)
	_rep_layer.resize(physical_cap)
	_rep_generation.resize(physical_cap)
	_rep_exposure.resize(physical_cap)
	_rep_age.resize(physical_cap)
	_rep_id.resize(physical_cap)
	_rep_parent.resize(physical_cap)
	_rep_event.resize(physical_cap)
	_rep_flags.resize(physical_cap)
	_rep_wait.resize(physical_cap)
	_rep_rank.resize(physical_cap)

	_sol_slot.resize(settings.max_large)
	_sol_age.resize(settings.max_large)
	_sol_pos.resize(settings.max_large)
	_sol_vel.resize(settings.max_large)
	_sol_spin.resize(settings.max_large)
	_sol_basis.resize(settings.max_large)
	_sol_size.resize(settings.max_large)
	_sol_color.resize(settings.max_large)
	_sol_marks.resize(settings.max_large)
	_sol_bounced.resize(settings.max_large)
	_sol_category.resize(settings.max_large)
	_sol_mass.resize(settings.max_large)
	_sol_profile.resize(settings.max_large)

	_stain_birth.resize(settings.max_surface)
	_fade_slots.resize(settings.stability.max_fading_stains)
	_fade_left.resize(settings.stability.max_fading_stains)
	_fade_duration.resize(settings.stability.max_fading_stains)
	_stain_life.resize(settings.max_surface)
	_stain_active.resize(settings.max_surface)
	_stain_cell.resize(settings.max_surface)
	_stain_ids.resize(settings.max_surface)
	_stain_drop_ids.resize(settings.max_surface)
	_stain_event_ids.resize(settings.max_surface)

	var runoff_cap: int = maxi(settings.max_runoff, 1)
	_runoff_pos.resize(runoff_cap)
	_runoff_dir.resize(runoff_cap)
	_runoff_normal.resize(runoff_cap)
	_runoff_mass.resize(runoff_cap)
	_runoff_age.resize(runoff_cap)
	_runoff_since.resize(runoff_cap)
	_runoff_speed.resize(runoff_cap)
	_runoff_start_mass.resize(runoff_cap)
	_runoff_profile.resize(runoff_cap)
	_runoff_last_mark.resize(runoff_cap)
	_runoff_surface.resize(runoff_cap)
	_runoff_drop_id.resize(runoff_cap)
	_runoff_event_id.resize(runoff_cap)


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
	return mat


## THE stain material.
##
## A ShaderMaterial rather than a StandardMaterial3D, because only a shader can
## read INSTANCE_CUSTOM and let each instance choose its own atlas cell. The
## StandardMaterial3D version silently rendered every single stain as the first
## cell - TINY_DROP - no matter what shape had been picked, which is why the
## arena looked clean while the telemetry reported thousands of marks.
func _stain_material(atlas: Texture2D) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://presentation/gore/blood_stain.gdshader")
	mat.set_shader_parameter("atlas", atlas)
	mat.set_shader_parameter("atlas_cells", Vector2(ATLAS_COLS, ATLAS_ROWS))
	# Bloom timing must match what the CPU packs into the atlas row fraction.
	mat.set_shader_parameter("bloom_window", settings.stability.bloom_window_s)
	mat.set_shader_parameter("bloom_duration", settings.stability.bloom_duration_s)
	mat.set_shader_parameter("bloom_initial", settings.stability.bloom_initial)
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
		_paint_stain(
			img, (shape % ATLAS_COLS) * cell, (shape / ATLAS_COLS) * cell, cell, shape, rng
		)
	_measure_atlas(img, cell)
	return ImageTexture.create_from_image(img)


## Scan what was just drawn and record how much of each cell is actually ink.
##
## This is the other half of "the arena looks clean": a quad sized to the
## requested footprint renders a mark the size of the INK inside it, and the ink
## fills only part of its cell. A TINY_DROP lobe of radius 0.17 covers about a
## third of the cell width, so asking for a 20 cm mark produced a ~7 cm one.
## Measuring it here means the calibration below is derived from the real
## texture rather than from a constant somebody has to remember to update.
func _measure_atlas(img: Image, cell: int) -> void:
	_atlas_occupancy.resize(BloodTypes.STAIN_COUNT)
	_atlas_fill.resize(BloodTypes.STAIN_COUNT)
	for shape in BloodTypes.STAIN_COUNT:
		var ox := (shape % ATLAS_COLS) * cell
		var oy := (shape / ATLAS_COLS) * cell
		var min_x := cell
		var max_x := -1
		var min_y := cell
		var max_y := -1
		var lit := 0
		for y in cell:
			for x in cell:
				if img.get_pixel(ox + x, oy + y).a < 0.1:
					continue
				lit += 1
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
		if max_x < 0:
			_atlas_occupancy[shape] = Vector2.ONE
			_atlas_fill[shape] = 1.0
			continue
		_atlas_occupancy[shape] = Vector2(
			float(max_x - min_x + 1) / float(cell), float(max_y - min_y + 1) / float(cell)
		)
		_atlas_fill[shape] = float(lit) / float(cell * cell)


## How wide the QUAD must be for a stain's INK to be `diameter_m` across.
##
## THE DIMENSION CONTRACT, stated once so it cannot drift again:
##
##     _stain_radius()                 -> RADIUS in metres
##     quad_for_visible_diameter()     -> full QUAD WIDTH in metres
##     Basis.x/.y scale of a unit quad -> full WIDTH, not half-width
##
## The old code scaled a unit quad's axes by the RADIUS, so a stain rendered at
## its diameter/2, and then the atlas ink shrank it again. Both factors are
## applied here, in one place, per variant.
func quad_for_visible_diameter(diameter_m: float, shape: int) -> Vector2:
	var occ := Vector2.ONE
	if shape >= 0 and shape < _atlas_occupancy.size():
		occ = _atlas_occupancy[shape]
	return Vector2(
		diameter_m / maxf(occ.x, 0.05),
		diameter_m / maxf(occ.y, 0.05)
	)


## Visible ink extent of one atlas cell, as a fraction of the cell.
func atlas_occupancy(shape: int) -> Vector2:
	if shape < 0 or shape >= _atlas_occupancy.size():
		return Vector2.ONE
	return _atlas_occupancy[shape]


## Fraction of the cell that is ink at all, for coverage estimates.
func atlas_fill(shape: int) -> float:
	if shape < 0 or shape >= _atlas_fill.size():
		return 1.0
	return _atlas_fill[shape]


func _paint_stain(
	img: Image, ox: int, oy: int, cell: int, shape: int, rng: RandomNumberGenerator
) -> void:
	# Each shape is a handful of overlapping lobes with a narrow soft edge. Irregular enough to read
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
					# Opaque body with a narrow antialiased rim, not an airbrush disc.
					a = maxf(a, 1.0 - smoothstep(1.0 - settings.stain_edge_softness, 1.0, d / r))
			if a > 0.004:
				img.set_pixel(ox + x, oy + y, Color(1, 1, 1, a))


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
