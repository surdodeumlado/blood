extends Node3D
## Native CPU/frame benchmark. Actual Weapon.apply_hit + real dummy reservoirs;
## direct resolved contacts deliberately exclude melee overlap/grenade broadphase.
var blood: BloodSystem
var camera: Camera3D
var output := "res://docs/validation/blood_stability/before"
var native := false
var warmup_ms := 0.0

func box(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	mesh.mesh = cube
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.28, 0.3, 0.32)
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	native = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	box(Vector3(40, 1, 40), Vector3(0, -0.5, 0))
	box(Vector3(24, 8, 0.3), Vector3(0, 4, -4.15))
	camera = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 2.1, 6)
	camera.look_at(Vector3(0, 1, -1))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -20, 0)
	add_child(light)
	blood = BloodSystem.new()
	blood.settings = (load("res://data/blood/blood_settings.tres") as BloodSettings).duplicate()
	blood.profiles.assign([load("res://data/blood/blood_ballistic.tres"), load("res://data/blood/blood_slashing.tres"), load("res://data/blood/blood_blunt.tres"), load("res://data/blood/blood_high_energy.tres")])
	add_child(blood)
	blood.set_physics_process(false)
	blood.set_process(false)
	blood.manual_budget_clock = not native
	blood.profile_stages = true
	for layer in [blood._micro, blood._small, blood._medium, blood._large, blood._surface]: layer.profile_writes = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	if native and "--warmup" in OS.get_cmdline_user_args():
		# Optional first-use control: let prewarmed buffers actually draw before
		# run_case clears them. The baseline-compatible default is unchanged.
		var warm_start := Time.get_ticks_usec()
		for frame in 3:
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
		warmup_ms = (Time.get_ticks_usec() - warm_start) / 1000.0
	var rows: Array = []
	for family in [BloodTypes.DamageType.BLUNT, BloodTypes.DamageType.HIGH_ENERGY]:
		for count in [1, 2, 4, 8]:
			if "--first-case" in OS.get_cmdline_user_args() and (family != BloodTypes.DamageType.BLUNT or count != 1): continue
			rows.append(await run_case(family, count))
	var report := {"engine": Engine.get_version_info().string, "cpu": OS.get_processor_name(),
		"renderer": RenderingServer.get_video_adapter_name() if native else "headless", "native": native, "rows": rows, "explicit_prewarm_draw_ms": warmup_ms,
		"scope": "actual resolved Weapon.apply_hit contacts; no melee/grenade broadphase; 360 fixed steps; real native frame intervals; no GPU claim"}
	var f := FileAccess.open(output + "/multi_hit.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	print("MULTI HIT benchmark complete: " + output)
	get_tree().quit()

func run_case(family: int, count: int) -> Dictionary:
	blood.clear_all()
	blood._reservoirs.clear()
	blood.seed_for_test(54122)
	var victims: Array[DummyTarget] = []
	for i in count:
		var target := preload("res://gameplay/enemies/dummy_target.tscn").instantiate() as DummyTarget
		target.position = Vector3((i % 4 - (mini(count, 4) - 1) * 0.5) * 1.15, 0, -float(i / 4) * 1.3)
		add_child(target)
		target.set_physics_process(false)
		victims.append(target)
	var weapon := Weapon.new()
	weapon.damage_type = family
	weapon.impact_energy = 2.0
	weapon.config = load("res://data/combat/default_combat.tres")
	add_child(weapon)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if native: await RenderingServer.frame_post_draw
	blood.stage_us.clear()
	blood.query_count = 0
	var start_writes := blood._surface.write_count
	var start_api := api_calls()
	var start_commits := commits()
	var start_write_us := 0
	var start_commit_us := 0
	for layer in [blood._micro, blood._small, blood._medium, blood._large, blood._surface]:
		start_write_us += layer.write_us
		start_commit_us += layer.commit_us
	var start := Time.get_ticks_usec()
	for target in victims:
		var at := target.position + Vector3.UP * 1.4
		var axis := Vector3(0.65, 0.18, -1).normalized()
		if family == BloodTypes.DamageType.HIGH_ENERGY: axis = (at - Vector3(0, 0.5, 2)).normalized()
		weapon.apply_hit(target.get_node("Hurtboxes/HeadHurtbox"), at, axis, -axis, &"head", 200,
			1.0, func(ctx: BloodContext):
				ctx.weapon_velocity_ws = axis * 12
				ctx.swing_plane_normal_ws = Vector3.UP
				if family == BloodTypes.DamageType.HIGH_ENERGY: ctx.explosion_direction_ws = axis)
	var emit_ms := (Time.get_ticks_usec() - start) / 1000.0
	var immediate := blood.live_counts()
	var emit_stages := blood.stage_us.duplicate()
	blood.set_process(false)
	var steps: Array[float] = []
	var frame_intervals: Array[float] = []
	var peak_queries := 0
	var peak_writes := 0
	var peak_commits := 0
	var peak_parcels := blood._rep_count
	for step in 360:
		var previous_q := blood.query_count
		var previous_w := blood._surface.write_count
		var previous_c := commits()
		var begin := Time.get_ticks_usec()
		blood._physics_process(1.0 / 60.0)
		blood.set_process(false)
		blood._step_air(1.0 / 60.0)
		steps.append((Time.get_ticks_usec() - begin) / 1000.0)
		peak_queries = maxi(peak_queries, blood.query_count - previous_q)
		peak_writes = maxi(peak_writes, blood._surface.write_count - previous_w)
		peak_parcels = maxi(peak_parcels, blood._rep_count)
		if native:
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			frame_intervals.append((Time.get_ticks_usec() - begin) / 1000.0 + (emit_ms if step == 0 else 0.0))
		peak_commits = maxi(peak_commits, commits() - previous_c)
		if native and step in [2, 359]:
			get_viewport().get_texture().get_image().save_png(output + "/%s_%d_%d.png" % [BloodTypes.DamageType.keys()[family], count, step])
	steps.sort()
	frame_intervals.sort()
	var sum := 0.0
	for s in steps: sum += s
	var write_us := -start_write_us
	var commit_us := -start_commit_us
	for layer in [blood._micro, blood._small, blood._medium, blood._large, blood._surface]:
		write_us += layer.write_us
		commit_us += layer.commit_us
	var row := {"family": BloodTypes.DamageType.keys()[family], "victims": count, "emit_cpu_ms": emit_ms,
		"step_mean_ms": sum / steps.size(), "step_p95_ms": steps[int(steps.size() * 0.95)], "step_peak_ms": steps.back(),
		"native_frame_peak_ms": frame_intervals.back() if native else null, "immediate": immediate, "peak_physical": peak_parcels,
		"ray_queries": blood.query_count, "peak_queries_step": peak_queries, "stain_writes": blood._surface.write_count - start_writes,
		"peak_stain_writes_step": peak_writes, "instance_api_calls": api_calls() - start_api, "buffer_commits": commits() - start_commits,
		"peak_commits_step": peak_commits, "emit_stages_us": emit_stages, "all_stages_us": blood.stage_us.duplicate(), "final": blood.live_counts(),
		"instance_write_cpu_us": write_us, "buffer_submit_cpu_us": commit_us, "logical_blood_including_remnants": blood.accepted_blood_mass,
		"pending_blood": blood.queued_blood_mass, "frame_budget_peaks": blood.peak_frame_usage.duplicate(), "audio_peak_voices": blood._audio.peak_voices}
	print(JSON.stringify(row))
	for target in victims: target.free()
	weapon.free()
	return row

func commits() -> int:
	return blood._micro.commit_count + blood._small.commit_count + blood._medium.commit_count + blood._large.commit_count + blood._surface.commit_count

func api_calls() -> int:
	return blood._micro.instance_api_calls + blood._small.instance_api_calls + blood._medium.instance_api_calls + blood._large.instance_api_calls + blood._surface.instance_api_calls
