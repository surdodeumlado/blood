extends Node3D
var blood: BloodSystem
var camera: Camera3D
var checks := 0
var failures: Array[String] = []
var native := false
var output := "res://docs/validation/blood_stability/fixtures"
var profile: BloodProfile = preload("res://data/blood/blood_blunt.tres")
var smooth: BloodSurfaceResponse = preload("res://data/blood/surfaces/smooth.tres")
var rough: BloodSurfaceResponse = preload("res://data/blood/surfaces/rough.tres")
var porous: BloodSurfaceResponse = preload("res://data/blood/surfaces/porous.tres")
var captures: Array[String] = []
var pool_areas: Array[float] = []
var budget_peaks: Dictionary = {}
var sampling_counts: Array[int] = []

func _ready() -> void:
	native = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	box(Vector3(30, 1, 30), Vector3(0, -0.5, 0), rough)
	box(Vector3(12, 6, 0.2), Vector3(0, 3, -3.1), smooth)
	camera = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 3, 7)
	camera.look_at(Vector3(0, 1, -2))
	blood = BloodSystem.new()
	blood.settings = (load("res://data/blood/blood_settings.tres") as BloodSettings).duplicate()
	blood.settings.stability = blood.settings.stability.duplicate()
	blood.settings.prewarm = false
	blood.profiles.assign([profile, load("res://data/blood/blood_high_energy.tres"), load("res://data/blood/blood_ballistic.tres"), load("res://data/blood/blood_slashing.tres")])
	add_child(blood)
	blood.set_physics_process(false)
	blood.set_process(false)
	blood.manual_budget_clock = true
	blood.record_causality = true
	blood._surface.begin_recording()
	await get_tree().physics_frame
	await get_tree().physics_frame
	await support_checks()
	await wet_checks()
	await wound_checks()
	await budget_checks()
	await audio_checks()
	var f := FileAccess.open(output + ("/native_results.json" if native else "/results.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks": checks, "failures": failures, "captures": captures,
		"frame_peak_usage": budget_peaks, "audio_peak_voices": blood._audio.peak_voices, "pool_area_samples_m2": pool_areas,
		"physical_counts_after_three_steps_1_2_4_8_victims": sampling_counts}, "\t"))
	print("STABILITY: %d checks, %d failed" % [checks, failures.size()])
	for failure in failures: printerr(failure)
	# Manual virtual-time simulation is much faster than the audio mixer.
	# Stop pending 3D playback and let a real mixer/physics interval retire it.
	blood.clear_all()
	print("STABILITY: presentation stopped")
	await get_tree().physics_frame
	await get_tree().create_timer(0.5).timeout
	blood.queue_free()
	blood = null
	await get_tree().physics_frame
	await get_tree().process_frame
	print("STABILITY: mixer drained; quitting")
	get_tree().quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print(("PASS " if ok else "FAIL ") + label)

func box(size: Vector3, at: Vector3, response: BloodSurfaceResponse) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.set_meta("blood_response", response)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	mesh.mesh = cube
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.3, 0.32, 0.34)
	mesh.material_override = material
	body.add_child(mesh)
	add_child(body)
	return body

func reset() -> void:
	blood.clear_all()
	blood._reservoirs.clear()
	blood.seed_for_test(5819)
	blood.synchronous_test_mode = false
	blood.set_process(false)

func steps(count: int) -> void:
	for i in count:
		blood._physics_process(1.0 / 60.0)
		blood.set_process(false)
		blood._step_air(1.0 / 60.0)

func deposit(at: Vector3, normal: Vector3, mass: float, response: BloodSurfaceResponse, diameter := 0.005, residual := false) -> void:
	blood._begin_frame()
	var hit := blood._support.contact(at, normal)
	blood._contact_hit = hit
	blood._deposit_surface = response
	blood._emit_representative(profile, at + normal * 0.02, -normal * 3, 0, mass, 1, diameter, -1, 551)
	var index := blood._rep_count - 1
	blood._rep_flags[index] = 1 if residual else 2
	blood._land_representative(index, at, normal, -normal * 3)
	blood._deposit_surface = null
	blood._contact_hit = {}

func capture(name: String) -> void:
	if not native: return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(output + "/" + name + ".png")
	check(error == OK, "capture " + name)
	captures.append(name)

func support_checks() -> void:
	reset()
	var narrow := box(Vector3(0.65, 1.8, 0.2), Vector3(6, 1.5, 0), smooth)
	((narrow.get_child(1) as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = Color(0.6, 0.64, 0.67)
	await get_tree().physics_frame
	await get_tree().physics_frame
	deposit(Vector3(6.22, 1.5, 0.1), Vector3.BACK, 0.1, smooth)
	steps(1)
	check(not blood._support.anchors.is_empty(), "edge deposit receives a real owned support anchor")
	var plane_safe := true
	var footprint_safe := true
	for anchor in blood._support.anchors.values():
		var t: Transform3D = anchor.transform
		var distance: float = (t.origin - anchor.surface_hit_position_ws).dot(anchor.surface_normal_ws)
		plane_safe = plane_safe and distance > 0 and distance <= 0.003
		for u in [-0.5, 0.5]:
			for v in [-0.5, 0.5]:
				var corner: Vector3 = t.origin + t.basis.x * u + t.basis.y * v
				footprint_safe = footprint_safe and corner.x >= 5.675 and corner.x <= 6.325 and corner.y >= 0.6 and corner.y <= 2.4
	check(plane_safe, "stain point stays outside the correct surface plane at millimetre offset")
	check(footprint_safe, "large edge stain is reduced until its whole sampled footprint is supported")
	camera.position = Vector3(7.5, 2.5, 3)
	camera.look_at(Vector3(6, 1.5, 0))
	await capture("01_supported_edge")
	if native:
		var transforms_match := true
		for slot in blood._support.anchors:
			transforms_match = transforms_match and blood._surface.multimesh.get_instance_transform(slot).is_equal_approx(blood._surface.recorded_xform[slot])
		check(transforms_match, "native MultiMesh readback preserves submitted scale and orientation")
	var edge_shape := (narrow.get_child(0) as CollisionShape3D).shape as BoxShape3D
	edge_shape.size = Vector3(0.1, 0.1, 0.1)
	blood._support.validate_owners()
	check(blood._support.anchors.is_empty(), "edited collision shape invalidates old footprint support")
	edge_shape.size = Vector3(0.65, 1.8, 0.2)
	await get_tree().physics_frame
	await get_tree().physics_frame
	deposit(Vector3(6, 1.5, 0.1), Vector3.BACK, 0.02, smooth)
	steps(1)
	narrow.position.x += 1
	blood._support.validate_owners()
	check(blood._support.anchors.is_empty(), "moved collider retires its old world-space marks")
	narrow.queue_free()
	await get_tree().physics_frame
	reset()
	blood._place_stain(profile, Vector3(0, 10, 0), Vector3.BACK, Vector3.DOWN, 1, 0.01)
	steps(2)
	check(blood._surface.live() == 0 and float(blood.material_stats.get("unsupported_mass", 0)) > 0, "unsupported floating stain is rejected with explicit retained mass")
	blood.settings.debug_patterns = true
	steps(1)
	check(blood._debug_label != null, "empty developer overlay is valid before the first impact")
	blood.settings.debug_patterns = false

func wet_checks() -> void:
	reset()
	deposit(Vector3(-3, 4, -3), Vector3.BACK, 0.08, smooth)
	deposit(Vector3(0, 4, -3), Vector3.BACK, 0.08, rough)
	deposit(Vector3(3, 4, -3), Vector3.BACK, 0.08, porous)
	deposit(Vector3(-4, 2, -3), Vector3.BACK, 0.0002, smooth, 0.0003)
	steps(30)
	var running := 0
	var absorbing := false
	var tiny_static := false
	for patch in blood._wet_patches.values():
		if patch.running: running += 1
		if patch.surface == porous: absorbing = patch.state == "ABSORBING" and not patch.running
		if patch.wet < 0.001 and patch.surface == smooth: tiny_static = not patch.running
	check(running == 2, "smooth and rough heavy wall deposits deterministically run after bounded delay")
	check(tiny_static, "tiny wall drop remains static")
	check(absorbing, "porous wall absorbs without sustained runoff")
	camera.position = Vector3(0, 3, 7)
	camera.look_at(Vector3(0, 2.5, -3))
	await capture("02_wall_half_second")
	steps(360)
	check(blood._runoff_count == 0, "streams exhaust within bounded lifetime without repeatedly restarting the same deposit")
	await capture("03_wall_finished")
	reset()
	camera.position = Vector3(1.3, 1.8, 2.6)
	camera.look_at(Vector3(0, 0, 0))
	var areas: Array[float] = []
	for i in 5:
		# Repeated residual packets: accumulated pooling, not direct heavy globs.
		deposit(Vector3(0, 0, 0), Vector3.UP, 0.012, smooth, 0.001, true)
		steps(8)
		var area := 0.0
		for pool in blood._pools.values(): area += pool.rendered
		areas.append(area)
		await capture("04_pool_%d" % i)
	pool_areas = areas.duplicate()
	check(areas.back() > areas[1] and areas[1] > 0, "pool grows with repeated incoming deposits rather than appearing at final size")
	steps(30)
	var settled := JSON.stringify(blood._pools)
	steps(60)
	check(settled == JSON.stringify(blood._pools), "pool target and rendered area stop growing without additional deposited mass")
	reset()
	deposit(Vector3(0, 0, 0), Vector3.UP, 0.002, smooth, 0.001, true)
	steps(3)
	var max_axis := 0.0
	for anchor in blood._support.anchors.values():
		var t: Transform3D = anchor.transform
		max_axis = maxf(max_axis, maxf(t.basis.x.length(), t.basis.y.length()))
	check(blood._pools.is_empty() and max_axis < 0.35, "residual drip cannot create an immediate catastrophic pool")
	reset()
	deposit(Vector3(0, 0.25, -3), Vector3.BACK, 0.2, smooth)
	steps(100)
	var floor_mass := 0.0
	for patch in blood._wet_patches.values():
		if patch.normal.y > 0.5: floor_mass += patch.wet + patch.absorbed
	check(floor_mass > 0 and not blood._pools.is_empty(), "wall runoff transfers mass to a real floor contact and feeds a growing floor pool")

func wound_checks() -> void:
	reset()
	var target := preload("res://gameplay/enemies/dummy_target.tscn").instantiate() as DummyTarget
	add_child(target)
	target.set_physics_process(false)
	var reservoir := target.get_node("BloodReservoir") as BloodReservoir
	var ctx := BloodContext.make(BloodTypes.DamageType.SLASHING, Vector3(0, 1, 0), Vector3.RIGHT, BloodTypes.BodyRegion.TORSO)
	var release := reservoir.withdraw(ctx)
	var wound := reservoir.open_wound(release)
	target.position = Vector3(3, 0, 0)
	reservoir.tick_wounds(0.01)
	check(wound.last_valid_position.x > 2.9, "living wound anchor follows the moving biological owner")
	target._alive = false
	var due := reservoir.tick_wounds(1)
	check(due.is_empty() and reservoir.wounds.is_empty(), "dead owner cannot keep attached wound emissions")
	reservoir.refill()
	target._alive = true
	check(wound.state == Wound.State.EXHAUSTED and reservoir.wounds.is_empty(), "respawn generation cannot inherit an old wound")
	var w := reservoir.open_wound(release)
	reservoir.release_wound(w)
	var available := reservoir.remaining_blood + reservoir.death_release_allowance
	var transfer := reservoir.transfer_remnant_budget(w)
	check(is_equal_approx(available - reservoir.remaining_blood - reservoir.death_release_allowance, transfer), "remnant handoff debits exactly its legitimate transferred mass")
	blood.add_remnant(w, Vector3(0, 1, 0), transfer)
	steps(180)
	check(blood._remnants.is_empty() and w.state == Wound.State.EXHAUSTED, "world remnant exhausts and retires without owner references")
	reservoir.refill()
	check(reservoir.remnant_transferred == 0 and reservoir.wounds.is_empty(), "respawn resets remnant accounting without resurrecting detached wounds")
	target.queue_free()
	await get_tree().physics_frame

func event() -> BloodRelease:
	var ctx := BloodContext.make(BloodTypes.DamageType.HIGH_ENERGY, Vector3(0, 1.6, 0), Vector3(0.3, 0.2, -1).normalized(), BloodTypes.BodyRegion.HEAD, 2)
	ctx.is_kill = true
	ctx.explosion_direction_ws = ctx.primary_axis()
	return BloodRelease.make(ctx, 0.3, 0)

func mass_in_presentation() -> float:
	var mass := 0.0
	for i in blood._rep_count: mass += blood._rep_mass[i]
	for c in blood._contacts.values(): mass += c.mass
	for c in blood._coarse_jobs: mass += c.mass
	var stock := blood.wet_mass_report()
	return mass + stock.wet + stock.absorbed + stock.mobile + stock.frozen_retained + float(blood.material_stats.escaped_mass)

func budget_checks() -> void:
	var representatives: Array[int] = []
	for count in [1, 2, 4, 8]:
		reset()
		for i in count: blood.release(event())
		check(blood._rep_count == 0 and is_equal_approx(blood.accepted_blood_mass, count * 0.3), "%d victims queue presentation without delaying or changing the logical withdrawal" % count)
		steps(3)
		representatives.append(blood._rep_count)
		check(absf(blood.queued_blood_mass) < 0.000001, "%d victims finish primary emission within three fixed steps" % count)
		steps(80)
		check(absf(mass_in_presentation() - count * 0.3) < 0.0001, "%d victims conserve physical, pending, retained, runoff and escaped blood mass" % count)
	check(representatives[1] < representatives[0] * 2 and representatives[2] < representatives[0] * 4, "multi-victim sampling degrades gracefully per victim")
	check(blood.peak_frame_usage.queries <= blood.settings.stability.queries_per_frame, "strict collision/support ray budget is never exceeded")
	check(blood.peak_frame_usage.stains <= blood.settings.stability.stain_writes_per_frame, "stain write budget is never exceeded")
	check(blood.peak_frame_usage.drops <= blood.settings.stability.new_drops_per_frame, "physical admission budget is never exceeded")
	check(blood.peak_frame_usage.runoff <= blood.settings.stability.runoff_starts_per_frame, "runoff event budget is never exceeded")
	check(blood.coalesced_contacts > 0, "nearby physical impacts share surface presentation")
	budget_peaks = blood.peak_frame_usage.duplicate()
	sampling_counts = representatives.duplicate()
	var layer := blood._surface
	var before := layer.commit_count
	for i in 100: layer.set_color(0, Color("dc143c"))
	layer.commit()
	layer.commit()
	check(layer.commit_count - before <= 1, "100 writes commit a MultiMesh layer at most once in a rendered frame")
	reset()
	blood.manual_budget_clock = false
	for i in 8: blood.release(event())
	steps(6)
	check(blood.frame_usage.queries <= blood.settings.stability.queries_per_frame and blood.frame_usage.drops <= blood.settings.stability.new_drops_per_frame,
		"six catch-up steps share one rendered-frame admission and query budget")
	check(absf(mass_in_presentation() - 2.4) < 0.0001, "same-frame budget overflow retains all logical blood")
	blood.manual_budget_clock = true
	await get_tree().process_frame

func audio_checks() -> void:
	if blood._audio.streams.is_empty():
		print("PENDING: playback checks require real foley originals; no synthetic fallback")
		return
	blood._audio.clear()
	var before := blood._audio.played
	for i in 100: blood._audio.submit(Vector3(0, 0, 0), smooth, 0.002, 3, 3, Vector3.UP, 0)
	check(blood._audio.clusters.size() == 1, "100 simultaneous local impacts form one audio cluster")
	blood._audio.advance(0.09, blood.settings.stability.audio_events_per_frame)
	check(blood._audio.played - before == 1 and blood._audio.last_events.back().dense, "100 impacts produce one quiet rain texture, not 100 voices")
	for j in 10:
		for i in 20: blood._audio.submit(Vector3(i * 2, 0, j * 2), rough, 0.001, 4, 3, Vector3.UP, j * 0.01)
		blood._audio.advance(0.01, 2)
	check(blood._audio.peak_voices <= blood.settings.stability.audio_voices, "blood audio never exceeds its six pooled voices")
	check(blood._audio.clusters.size() <= blood.settings.stability.audio_clusters, "audio overflow enriches bounded clusters")
