extends Node3D

## Native captures: godot --path . res://tests/blood_material_test.tscn -- --capture
## Numeric fixtures: godot --headless --path . res://tests/blood_material_test.tscn
## Both exercise production methods; captures use the Compatibility renderer.
var output_dir := "res://docs/validation/blood_physics"
var blood: BloodSystem
var camera: Camera3D
var title: Label
var checks := 0
var failures: Array[String] = []
var report: Dictionary = {}
var captures := false
var labels: Array[Node] = []
var smooth: BloodSurfaceResponse = preload("res://data/blood/surfaces/smooth.tres")
var rough: BloodSurfaceResponse = preload("res://data/blood/surfaces/rough.tres")
var porous: BloodSurfaceResponse = preload("res://data/blood/surfaces/porous.tres")
var profile: BloodProfile = preload("res://data/blood/blood_ballistic.tres")

func _ready() -> void:
	captures = "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output_dir = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	_build_room()
	blood = BloodSystem.new()
	blood.synchronous_test_mode = true
	blood.manual_budget_clock = true
	blood.settings = (load("res://data/blood/blood_settings.tres") as BloodSettings).duplicate()
	blood.settings.fluid = blood.settings.fluid.duplicate()
	blood.settings.prewarm = false
	blood.profiles.assign([
		load("res://data/blood/blood_ballistic.tres"), load("res://data/blood/blood_slashing.tres"),
		load("res://data/blood/blood_piercing.tres"), load("res://data/blood/blood_blunt.tres"),
		load("res://data/blood/blood_high_energy.tres")])
	add_child(blood)
	blood.set_physics_process(false)
	blood.set_process(false)
	blood.record_causality = true
	blood._surface.begin_recording()
	blood._medium.begin_recording()
	blood._small.begin_recording()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_model_checks()
	_arcade_isolation()
	await _morphology()
	await _flight_and_breakup()
	await _runoff()
	await _castoff()
	_castoff_authored_rigs()
	_admission_pressure()
	await _family_readability()
	await _events_and_benchmark()
	report["checks"] = checks
	report["failures"] = failures
	report["renderer"] = RenderingServer.get_video_adapter_name() if captures else "headless dummy (no pixel claims)"
	report["engine"] = Engine.get_version_info().string
	report["cpu"] = OS.get_processor_name()
	var file := FileAccess.open(output_dir + ("/native_results.json" if captures else "/results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("BLOOD MATERIAL: %d checks, %d failures; captures=%s" % [checks, failures.size(), captures])
	for failure in failures: printerr(failure)
	blood.clear_all()
	print("MATERIAL: presentation stopped")
	await get_tree().physics_frame
	await get_tree().create_timer(0.5).timeout
	blood.queue_free()
	blood = null
	await get_tree().physics_frame
	await get_tree().process_frame
	print("MATERIAL: mixer drained; quitting")
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text)
	print(("PASS " if ok else "FAIL ") + text)

func _box(size: Vector3, at: Vector3, color: Color, response: BloodSurfaceResponse, rotation := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.rotation = rotation
	body.set_meta("blood_response", response)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)
	return body

func _build_room() -> void:
	_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0), Color(0.55, 0.57, 0.59), rough)
	_box(Vector3(22, 8, 0.4), Vector3(0, 4, -5.2), Color(0.68, 0.69, 0.71), smooth)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.06, 0.075, 0.09)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.65
	add_child(env)
	camera = Camera3D.new()
	add_child(camera)
	camera.current = true
	if captures: RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	title = Label.new()
	title.position = Vector2(22, 16)
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_shadow_color", Color.BLACK)
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(title)

func _label(text: String, at: Vector3, on_floor := true) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 48
	label.pixel_size = 0.004
	label.position = at
	label.no_depth_test = true
	if on_floor: label.rotation_degrees.x = -90
	add_child(label)
	labels.append(label)

func _clear() -> void:
	blood.clear_all()
	blood.set_process(false)
	for label in labels: label.queue_free()
	labels.clear()
	blood.seed_for_test(83191)

func _step(seconds: float) -> void:
	for step in int(round(seconds * 60.0)):
		blood._physics_process(1.0 / 60.0)
		blood._step_air(1.0 / 60.0)

func _capture(name: String, caption: String) -> void:
	title.text = caption
	if not captures: return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(output_dir + "/" + name + ".png")
	_check(error == OK, "native capture " + name)

func _top_view(center: Vector3, width: float) -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = width
	camera.position = center + Vector3(0, 12, 0.01)
	camera.look_at(center, Vector3.FORWARD)

func _model_checks() -> void:
	var p := blood.settings.fluid
	var velocities: Array[float] = []
	for d in [0.0001, 0.001, 0.004]:
		var velocity := Vector3(20, 0, 0)
		for i in 120: velocity = BloodFluidModel.advance_velocity(velocity, d, 1.0 / 120.0, Vector3.ZERO, p)
		velocities.append(velocity.length())
	report["speed_after_1s_from_20ms_no_gravity"] = velocities
	_check(velocities[0] < velocities[1] and velocities[1] < velocities[2], "smaller drops lose launch momentum faster")
	_check(velocities[0] >= 0.0, "drag never reverses velocity")
	_check(blood._medium.multimesh.mesh is SphereMesh and blood._small.multimesh.mesh is SphereMesh, "both physical liquid layers use spheres")
	var max_dimension := 0.0
	for d in [0.00008, 0.0005, 0.0015, 0.003, 0.008]:
		var kind := BloodFluidModel.category(d)
		var render_d := BloodFluidModel.render_diameter(d, kind, p)
		var t := BloodFluidModel.liquid_transform(Vector3.ZERO, Vector3(200, 0, 0), render_d, kind, 0, p)
		var extent := maxf(t.basis.x.length(), maxf(t.basis.y.length(), t.basis.z.length()))
		max_dimension = maxf(max_dimension, extent)
		var cap := p.max_glob_diameter if kind == BloodFluidModel.Liquid.GLOB else p.max_drop_diameter
		_check(extent <= cap + 0.00001, "liquid longest axis obeys cap at d=%.2f mm" % (d * 1000))
	report["max_liquid_axis_m"] = max_dimension
	_check(is_equal_approx(blood._gravity.length(), 9.8), "blood uses configured world gravity; player settings untouched")

func _arcade_isolation() -> void:
	# Same actual drop with different presentation controls: verify simulation,
	# actual collision and wet stock, not just the pure render-size function.
	var original := blood.settings.fluid
	var neutral := original.duplicate() as BloodPhysicsSettings
	neutral.render_medium_scale = 1.0
	neutral.stain_medium_render_scale = 1.0
	var samples: Array = []
	for params in [neutral, original]:
		_clear()
		blood.settings.fluid = params
		# clear_all resets pools/wet stock; the legacy ledger resets on release.
		var prior_mass := blood._led_surface_mass
		var prior_area := blood._led_stain_area
		blood._emit_representative(profile, Vector3(0, 0.9, 0), Vector3(2, -3, 0), 0, 0.002, 1, 0.0015, -1, 700)
		_step(0.05)
		var state := {"position": blood._rep_pos[0], "velocity": blood._rep_vel[0],
			"diameter": blood._rep_diameter[0], "mass": blood._rep_mass[0], "render_size": blood._rep_size[0]}
		_step(0.5)
		for record in blood.causal_records:
			if record.action == "collision":
				state["hit"] = record.position
				state["impact_we"] = record.impact.we
				state["impact_aspect"] = record.impact.aspect
		state["wet"] = blood.wet_mass_report()
		state["surface_mass"] = blood._led_surface_mass - prior_mass
		state["area"] = blood._led_stain_area - prior_area
		samples.append(state)
	var a: Dictionary = samples[0]
	var b: Dictionary = samples[1]
	_check(a.position == b.position and a.velocity == b.velocity and a.diameter == b.diameter and a.mass == b.mass,
		"render exaggeration leaves real flight, physical diameter and parcel mass unchanged")
	_check(a.has("hit") and b.has("hit") and a.get("hit") == b.get("hit") and a.get("impact_we") == b.get("impact_we") and a.get("impact_aspect") == b.get("impact_aspect"),
		"render exaggeration leaves swept collision and impact response unchanged")
	_check(a.wet == b.wet and is_equal_approx(a.surface_mass, b.surface_mass), "stain visual gain leaves deposited and wet mass unchanged")
	_check(b.render_size > a.render_size and b.area > a.area, "arcade settings enlarge liquid and final stain geometry")
	report["render_isolation"] = samples
	blood.settings.fluid = original
	_clear()

func _contact(at: Vector3, normal: Vector3, velocity: Vector3, diameter: float, mass: float, response: BloodSurfaceResponse) -> Dictionary:
	var before := blood._stain_serial
	var id := blood._emit_representative(profile, at + normal * 0.02, velocity, 0.0, mass, 1.0, diameter, -1, 700)
	blood._deposit_surface = response
	blood._land_representative(blood._rep_count - 1, at, normal, velocity)
	blood._deposit_surface = null
	var result := BloodFluidModel.impact(diameter, velocity, normal, response, blood.settings.fluid)
	result["drop_id"] = id
	result["stains"] = blood._stain_serial - before
	return result

func _morphology() -> void:
	_clear()
	_top_view(Vector3(0, 0, 0.5), 12.5)
	var rows: Array[Dictionary] = []
	for i in 3:
		var surface: BloodSurfaceResponse = [smooth, rough, porous][i]
		var at := Vector3(-3.5 + i * 3.5, 0.02, -2)
		rows.append(_contact(at, Vector3.UP, Vector3.DOWN * 4, 0.002, 0.007, surface))
		_label(surface.label.replace("_", " "), at + Vector3(0, 0.02, -0.7))
	var aspects: Array[float] = []
	for i in 5:
		var angle: float = [90, 60, 45, 30, 15][i]
		var radians := deg_to_rad(angle)
		var at := Vector3(-4.4 + i * 2.2, 0.02, 0.2)
		var result := _contact(at, Vector3.UP, Vector3(cos(radians), -sin(radians), 0) * 4, 0.002, 0.007, smooth)
		aspects.append(result.aspect)
		_label("%d deg" % angle, at + Vector3(0, 0.02, -0.6))
	for i in 3:
		var at := Vector3(-3.5 + i * 3.5, 0.02, 2.0)
		_contact(at, Vector3.UP, Vector3.DOWN * 3, [0.0005, 0.002, 0.005][i], 0.007, smooth)
		_label("%.1f mm" % ([0.0005, 0.002, 0.005][i] * 1000), at + Vector3(0, 0.02, -0.6))
	for i in 3:
		var at := Vector3(-3.5 + i * 3.5, 0.02, 3.8)
		_contact(at, Vector3.UP, Vector3.DOWN * [0.5, 3.0, 9.0][i], 0.002, 0.007, smooth)
		_label("%.1f m/s" % [0.5, 3.0, 9.0][i], at + Vector3(0, 0.02, -0.6))
	_check(aspects[0] < aspects[1] and aspects[1] < aspects[2] and aspects[2] < aspects[3] and aspects[3] < aspects[4], "grazing incidence progressively elongates stains")
	_check(aspects[4] < 3.7, "15 degree impact remains bounded")
	_check(rows[0].spread != rows[1].spread and rows[1].spread != rows[2].spread, "three material responses affect spread")
	var deposited := 0.0
	for record in blood.causal_records:
		if record.action == "stain": deposited += float(record.mass)
	_check(absf(deposited - 14 * 0.007) < 0.00001, "impact satellites conserve parent mass")
	report["normal_surfaces"] = rows
	report["angle_aspects_90_60_45_30_15"] = aspects
	await _capture("01_impact_matrix", "CONTROLLED IMPACTS | same parcel mass; surface / angle / diameter / speed")
	_step(2)
	var wet := blood.wet_mass_report()
	_check(float(wet.absorbed) > 0.006, "porous surface transfers wet material to absorbed stock")
	report["absorption_after_2s"] = wet

func _flight_and_breakup() -> void:
	_clear()
	blood._emit_representative(profile, Vector3(0, 0.02, 0), Vector3.DOWN * 0.03, 0.0, 0.01, 1.0, 0.002, -1, 183)
	_step(0.2)
	var collision := false
	var stained := false
	for record in blood.causal_records:
		if record.action == "collision": collision = true
		if record.action == "stain" and int(record.event_id) == 183: stained = true
	_check(collision and stained, "slow swept collision has a causal drop-to-stain record")
	_clear()
	blood._emit_representative(profile, Vector3(0, 4, 0), Vector3(65, 0, 0), 0.0, 0.04, 1.0, 0.008, -1, 800)
	_step(0.05)
	var mass := 0.0
	var eq_volume := 0.0
	for i in blood._rep_count:
		mass += blood._rep_mass[i]
		eq_volume += pow(blood._rep_diameter[i], 3)
	_check(blood._rep_count > 1 and blood._rep_count <= 4, "aerodynamic breakup occurs and respects generation bound")
	_check(absf(mass - 0.04) < 0.000001, "breakup conserves represented parcel mass")
	_check(absf(eq_volume - pow(0.008, 3)) < 0.000000001, "breakup conserves equivalent droplet volume")
	report["breakup"] = {"children": blood._rep_count, "mass": mass, "equivalent_volume_proxy": eq_volume}
	_clear()
	var sizes: Array[Dictionary] = []
	for i in 6:
		var d: float = [0.00015, 0.0006, 0.0015, 0.003, 0.006, 0.004][i]
		var kind := BloodFluidModel.Liquid.LIGAMENT if i == 5 else BloodFluidModel.category(d)
		blood._emit_representative(profile, Vector3(-0.28 + i * 0.11, 1.2, 0), Vector3(3, 0, 0), 0.0, 0.004, 1, d, kind)
		var transform: Transform3D = blood._medium.recorded_xform[blood._rep_slot[blood._rep_count - 1]]
		sizes.append({"physical_diameter_m": d, "requested_render_diameter_m": blood._rep_size[blood._rep_count - 1],
			"actual_basis_lengths_m": [transform.basis.x.length(), transform.basis.y.length(), transform.basis.z.length()], "class": kind})
		_label(["fine", "small", "medium", "large", "glob", "ligament"][i], Vector3(-0.28 + i * 0.11, 1.13, 0), false)
	for label in labels:
		(label as Label3D).pixel_size = 0.00055
		(label as Label3D).font_size = 28
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.9
	camera.position = Vector3(0, 1.3, 1.5)
	camera.look_at(Vector3(0, 1.2, 0))
	await _capture("02_liquid_shapes", "LIQUID SHAPES | magnified reference; longest normal axis <= %.1f cm" % (blood.settings.fluid.max_drop_diameter * 100))
	report["liquid_sizes"] = sizes
	_step(0.2)
	var ligaments := 0
	for i in blood._rep_count:
		if blood._rep_kind[i] == BloodFluidModel.Liquid.LIGAMENT: ligaments += 1
	_check(ligaments == 0, "short-lived ligaments fragment or collapse")
	_clear()
	for i in 5:
		var category: BloodTypes.Tissue = [BloodTypes.Tissue.FLESH, BloodTypes.Tissue.FAT,
			BloodTypes.Tissue.DARK_TISSUE, BloodTypes.Tissue.STRINGY_TISSUE, BloodTypes.Tissue.GORE_CHUNK][i]
		blood._emit_solid(profile, Vector3(-0.3 + i * 0.15, 1.2, 0), Vector3.ZERO, 0.15, category, i == 4, 0.004)
		_label(["flesh", "fat", "dark tissue", "stringy", "major chunk"][i], Vector3(-0.3 + i * 0.15, 1.09, 0), false)
	for label in labels:
		(label as Label3D).pixel_size = 0.00055
		(label as Label3D).font_size = 28
	camera.size = 1.0
	await _capture("02b_solid_tissue", "SOLID ORGANIC MATERIAL | angular fragments; muted fat; rare major chunks")

func _runoff() -> void:
	_clear()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 13.0
	camera.position = Vector3(0, 3.3, 6)
	camera.look_at(Vector3(0, 3.3, -5))
	for i in 3:
		var response: BloodSurfaceResponse = [smooth, rough, porous][i]
		_contact(Vector3(-4 + i * 4, 5, -4.99), Vector3.BACK, Vector3.FORWARD * 2, 0.005, 0.08, response)
		_label(response.label.replace("_", " "), Vector3(-4 + i * 4, 5.9, -4.96), false)
	var samples: Array[Dictionary] = []
	for time in [0.0, 0.5, 1.0, 2.0, 6.5]:
		var previous := float(samples.back().time) if not samples.is_empty() else 0.0
		_step(time - previous)
		if time == 0.5:
			_check(blood._runoff_count == 2, "same heavy load runs after bounded delay on smooth and rough walls; porous absorbs")
		var positions: Array = []
		for i in blood._runoff_count: positions.append(str(blood._runoff_pos[i]))
		var streams: Array[Dictionary] = []
		for source_x in [-4.0, 0.0]:
			var lower := 5.0
			var widths: Array[float] = []
			for slot in blood._surface.capacity:
				if not blood._surface.is_active(slot) or blood._surface.recorded_custom[slot].a < 0.5: continue
				var transform: Transform3D = blood._surface.recorded_xform[slot]
				if absf(transform.origin.x - source_x) > 0.2: continue
				lower = minf(lower, transform.origin.y - transform.basis.x.length() * 0.5)
				widths.append(transform.basis.y.length())
			streams.append({"source_x": source_x, "rendered_length_m": 5.0 - lower, "segment_widths_m": widths})
		samples.append({"time": time, "positions": positions, "active": blood._runoff_count, "stock": blood.wet_mass_report(), "rendered_streams": streams})
		await _capture("03_runoff_%03d" % int(time * 10), "RUNOFF | equal mass / different substrates | T = %.1f s" % time)
	_check(blood._runoff_count == 0, "runoff terminates within its bound")
	report["runoff"] = samples
	_clear()
	var normal := Vector3(0, 0.70710678, 0.70710678)
	var slope := _box(Vector3(3, 0.25, 4), Vector3(0, 2, 0), Color(0.65, 0.67, 0.7), smooth, Vector3(PI / 4, 0, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var point := Vector3(0, 2, 0) + normal * 0.125
	_contact(point, normal, -normal * 2, 0.005, 0.08, smooth)
	_step(0.4)
	_check(blood._runoff_count > 0 and blood._runoff_dir[0].dot(Vector3.DOWN.slide(normal).normalized()) > 0.99, "inclined runoff follows tangential gravity")
	_step(1)
	camera.position = Vector3(4, 5, 7)
	camera.look_at(Vector3(0, 2, 0))
	camera.size = 6
	await _capture("04_inclined_runoff", "INCLINED SURFACE | gravity projected onto the surface")
	slope.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame

func _castoff() -> void:
	_clear()
	var implement := MeleeWeapon.new()
	implement._blood = blood
	var release := BloodRelease.make(BloodContext.make(BloodTypes.DamageType.SLASHING,
		Vector3.ZERO, Vector3.RIGHT, BloodTypes.BodyRegion.TORSO), 0.01)
	implement._retain_contact_blood(release)
	_check(absf(release.blood_mass + implement.blood_load * blood.settings.fluid.castoff_load_mass - 0.01) < 0.000001,
		"blade load is carved from the contact withdrawal, never added blood")
	implement.free()
	var results: Array = []
	for omega in [1.0, 8.0, 20.0]:
		var velocity: Vector3 = Vector3.RIGHT * omega * 0.6
		var spent := blood.cast_off(Vector3(-4, 2.2, 0), velocity, BloodTypes.DamageType.SLASHING, 7, 1, 0.6, omega, 0.5)
		results.append({"omega": omega, "tip_speed": velocity.length(), "load_spent": spent})
	_check(float(results[0].load_spent) == 0.0 and float(results[2].load_spent) > float(results[1].load_spent), "equal cast-off load responds to angular motion and release threshold")
	report["castoff"] = results
	_step(1.5)
	_top_view(Vector3(0, 0, 0), 12)
	await _capture("05_castoff", "CAST-OFF | release follows measured tip velocity; equal starting loads")

func _event(family: BloodTypes.DamageType, axis: Vector3) -> BloodRelease:
	var ctx := BloodContext.make(family, Vector3(0, 1.6, 0), axis, BloodTypes.BodyRegion.HEAD, 2.0)
	ctx.is_kill = true
	ctx.weapon_velocity_ws = axis * 12
	ctx.swing_plane_normal_ws = Vector3.UP
	if family == BloodTypes.DamageType.HIGH_ENERGY: ctx.explosion_direction_ws = axis
	var release := BloodRelease.make(ctx, 0.85, 0.4)
	release.tissue_mix = PackedFloat32Array([0.4, 0.18, 0.25, 0.17])
	return release

func _castoff_authored_rigs() -> void:
	var records: Array[Dictionary] = []
	for node_name in ["TwinDaggers", "HeavyBlunt"]:
		_clear()
		# Use the actual authored rigs and swing parameters, without invoking
		# player input/camera capture or altering gameplay attack clocks.
		var shell := (load("res://gameplay/player/player.tscn") as PackedScene).instantiate()
		var weapon: MeleeWeapon = shell.get_node("Head/Camera/Weapons/" + node_name)
		weapon.get_parent().remove_child(weapon)
		shell.free()
		add_child(weapon)
		weapon.position = Vector3(0, 2, 0)
		weapon._blood = blood
		weapon._on_setup()
		weapon.set_process(false)
		weapon.set_physics_process(false)
		var load_after_contact := 0.0
		var peak_omega := 0.0
		var peak_speed := 0.0
		for swing in 2:
			weapon._castoff_available = weapon.blood_load
			weapon._castoff_done = false
			weapon._have_tip = false
			weapon._posed_rest = false
			weapon._side *= -1
			var loaded := false
			for frame in int(ceil(weapon.swing_time * 60)) + 1:
				weapon._swing = maxf(weapon.swing_time - frame / 60.0, 0.0)
				if swing == 0 and not loaded and weapon._phase() >= weapon.contact_at:
					var release := _event(weapon.damage_type, Vector3.RIGHT)
					weapon._retain_contact_blood(release)
					loaded = true
				weapon._process(1.0 / 60)
				if weapon._phase() > 0.22 and weapon._phase() < 0.58:
					peak_omega = maxf(peak_omega, weapon.tip_angular_speed)
					peak_speed = maxf(peak_speed, weapon.tip_velocity.length())
			if swing == 0:
				load_after_contact = weapon.blood_load
				_check(load_after_contact > 0.0 and blood._rep_count == 0, node_name + ": fresh contact loads weapon without immediate cast-off")
		_check(weapon.blood_load < load_after_contact and blood._rep_count > 0, node_name + ": actual later swing emits causal physical cast-off")
		_check(peak_omega > 1.0, node_name + ": full orientation detects roll about the forward axis")
		records.append({"weapon": node_name, "contact_load": load_after_contact, "remaining_load": weapon.blood_load,
			"peak_angular_speed": peak_omega, "peak_tip_speed": peak_speed, "castoff_drops": blood._rep_count})
		weapon.free()
	report["authored_weapon_castoff"] = records

func _admission_pressure() -> void:
	_clear()
	for i in blood.settings.max_medium:
		blood._emit_representative(profile, Vector3(0, 4, 0), Vector3.RIGHT * 65, 0, 0.001, 1, 0.008)
	var mass_before := 0.0
	for i in blood._rep_count: mass_before += blood._rep_mass[i]
	blood._split_representative(0)
	var mass_after := 0.0
	for i in blood._rep_count: mass_after += blood._rep_mass[i]
	_check(blood._rep_count == blood.settings.max_medium and is_equal_approx(mass_before, mass_after), "full pool refuses breakup without losing mass or overwriting a live drop")
	for i in blood.settings.max_small:
		blood._emit_representative(profile, Vector3(0, 4, 0), Vector3.ZERO, 0, 0.001, 1, 0.0005, -1, 900, 1)
	blood.release(BloodRelease.make(BloodContext.make(BloodTypes.DamageType.BALLISTIC,
		Vector3(0, 2, 0), Vector3.DOWN, BloodTypes.BodyRegion.TORSO), 0.2))
	blood.set_process(false)
	var stock := blood.wet_mass_report()
	_check(absf(blood._led_surface_mass + float(stock.mobile) + float(blood.material_stats.escaped_mass) - 0.2) < 0.00001, "full physical pools conserve a new event through explicit coarse fallback")

func _family_readability() -> void:
	var rows: Array = []
	for family in [BloodTypes.DamageType.BALLISTIC, BloodTypes.DamageType.SLASHING, BloodTypes.DamageType.BLUNT, BloodTypes.DamageType.HIGH_ENERGY]:
		_clear()
		blood.settings.quality = BloodTypes.Quality.INSANE
		var name := str(BloodTypes.DamageType.keys()[family]).to_lower()
		blood.release(_event(family, Vector3(0.7, 0.15, -1).normalized()))
		blood.set_process(false)
		var widths: Array[float] = []
		for i in blood._rep_count:
			var xform := BloodFluidModel.liquid_transform(blood._rep_pos[i], blood._rep_vel[i], blood._rep_size[i], blood._rep_kind[i], 0.0, blood.settings.fluid)
			widths.append(maxf(xform.basis.x.length(), maxf(xform.basis.y.length(), xform.basis.z.length())))
		widths.sort()
		var row := {"family": name, "initial": blood.live_counts(),
			"median_liquid_axis_m": widths[widths.size() / 2], "p90_liquid_axis_m": widths[int(widths.size() * 0.9)]}
		_step(0.10)
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.position = Vector3(0, 1.65, 2.5)
		camera.look_at(Vector3(0, 1.6, 0))
		await _capture("08_" + name + "_air", name.to_upper() + " | fixed FPS camera | T = 0.10 s")
		_step(5.9)
		camera.position = Vector3(0, 4.5, 6)
		camera.look_at(Vector3(0, 0.4, -1))
		row["aftermath"] = blood.live_counts()
		row["ledger"] = blood.mass_ledger()
		await _capture("08_" + name + "_aftermath", name.to_upper() + " | same released mass | T = 6 s")
		rows.append(row)
	report["family_readability"] = rows

func _events_and_benchmark() -> void:
	var means: Array[float] = []
	for sign_value in [1.0, -1.0]:
		_clear()
		blood.release(_event(BloodTypes.DamageType.BLUNT, Vector3.RIGHT * sign_value))
		blood.set_process(false)
		var mean := 0.0
		for i in blood._rep_count: mean += blood._rep_vel[i].x
		means.append(mean / maxf(blood._rep_count, 1))
		_step(0.15)
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.position = Vector3(0, 1.65, 2.5)
		camera.look_at(Vector3(0, 1.6, 0))
		await _capture("06_blunt_%s" % ("positive" if sign_value > 0 else "negative"), "BLUNT FIRST-PERSON REFERENCE | %.0fX swing | T = 0.15 s" % sign_value)
	_check(means[0] > 0.0 and means[1] < 0.0, "blunt +X / -X momentum reversal survives material changes")
	report["blunt_mean_launch_x"] = means
	var benchmarks: Array = []
	for quality in [BloodTypes.Quality.LOW, BloodTypes.Quality.HIGH, BloodTypes.Quality.INSANE]:
		_clear()
		blood.settings.quality = quality
		blood.record_causality = false
		blood._surface.record_writes = false
		blood._medium.record_writes = false
		blood._small.record_writes = false
		var start := Time.get_ticks_usec()
		blood.release(_event(BloodTypes.DamageType.HIGH_ENERGY, Vector3(0.5, 0.2, -1).normalized()))
		var emit_us := Time.get_ticks_usec() - start
		blood.set_process(false)
		var initial := blood._rep_count
		var initial_layers := blood.live_counts()
		var draw_times: Array[float] = []
		var gpu_times: Array[float] = []
		var cpu_times: Array[float] = []
		if captures:
			for render_frame in 70:
				var begin := Time.get_ticks_usec()
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				if render_frame >= 10:
					draw_times.append(float(Time.get_ticks_usec() - begin) / 1000.0)
					gpu_times.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
					cpu_times.append(RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()))
			draw_times.sort()
			gpu_times.sort()
			cpu_times.sort()
		var frames: Array[float] = []
		for frame in 360:
			start = Time.get_ticks_usec()
			blood._physics_process(1.0 / 60)
			blood._step_air(1.0 / 60)
			frames.append(float(Time.get_ticks_usec() - start) / 1000)
		frames.sort()
		var sum := 0.0
		for duration in frames: sum += duration
		benchmarks.append({"quality": quality, "logical_blood": 0.85, "initial_physical": initial, "initial_layers": initial_layers,
			"emit_ms": emit_us / 1000.0, "step_mean_ms": sum / frames.size(), "step_p95_ms": frames[int(frames.size() * 0.95)],
			"step_max_ms": frames.back(), "live": blood.live_counts(), "ledger": blood.mass_ledger(), "material": blood.material_stats.duplicate()})
		if not draw_times.is_empty():
			benchmarks.back()["native_frame_median_ms"] = draw_times[draw_times.size() / 2]
			benchmarks.back()["native_frame_p95_ms"] = draw_times[int(draw_times.size() * 0.95)]
			benchmarks.back()["gpu_render_median_ms"] = gpu_times[gpu_times.size() / 2]
			benchmarks.back()["cpu_render_median_ms"] = cpu_times[cpu_times.size() / 2]
			benchmarks.back()["render_draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_check(initial <= blood.settings.max_medium + blood.settings.max_small, "quality %d physical cap respected" % quality)
		_check(absf(blood._led_air_mass + blood._led_physical_mass - 0.85) < 0.00001, "quality %d represents same logical released blood" % quality)
		var initial_event_alive := 0
		for i in blood._rep_count:
			if blood._rep_age[i] >= blood.settings.droplet_max_life: initial_event_alive += 1
		_check(initial_event_alive == 0, "quality %d no physical parcel outlives its limit" % quality)
		await _capture("07_aftermath_quality_%d" % quality, "AFTERMATH | quality %d | same 0.85 logical blood units | T = 6 s" % quality)
		_step(8.0)
		_check(blood._rep_count == 0 and blood._runoff_count == 0, "quality %d terminal drops and runoff finish" % quality)
	report["benchmarks"] = benchmarks
	blood.record_causality = true
