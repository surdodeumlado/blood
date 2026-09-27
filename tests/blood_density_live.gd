extends "res://tests/blood_fall_live_test.gd"
const DEST := "res://docs/validation/blood_density/"
var melee_pair:=false
func run()->void:
	melee_pair="melee_pair" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DEST))
	native=DisplayServer.get_name()!="headless"
	world=load("res://world/chambers/prototype/the_box.tscn").instantiate()
	get_tree().root.add_child(world);get_tree().current_scene=world
	blood=world.get_node("BloodSystem");player=world.get_node("Player")
	camera=player.get_node("Head/Camera");rack=camera.get_node("Weapons")
	for target in world.get_node("Targets").get_children():targets.append(target)
	blood.profile_stages=true
	blood._surface.begin_recording()
	await tick();await tick()
	for gain in [1.0,1.5]:
		for weapon in [1,2] if melee_pair else [0,1,2,3]:
			for victims in [1] if melee_pair else [1,2,4]:await measure(gain,weapon,victims)
	var f:=FileAccess.open(DEST+("native" if native else "headless")+("_melee_pair" if melee_pair else "")+".json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"rows":rows,"failures":failures},"\t"));f.close()
	print("DENSITY_LIVE failures=",failures.size())
	await get_tree().create_timer(.5).timeout
	get_tree().quit(failures.size())
func aim(weapon:int,target:DummyTarget)->void:
	player.global_position=target.global_position+Vector3(0,.05,7 if weapon in [0,3] else 1.4)
	player.velocity=Vector3.ZERO;player.rotation=Vector3.ZERO
	camera._pitch=0;camera._recoil=Vector2.ZERO
func measure(gain:float,weapon:int,victims:int)->void:
	blood.clear_all();blood.seed_for_test(8319)
	for i in targets.size():
		var target:DummyTarget=targets[i]
		var reservoir:BloodReservoir=target.get_node("BloodReservoir")
		reservoir.config.blood_quantity_multiplier=gain
		target._spawn_position=Vector3(float(i)*1.5,0,-37) if i<victims else Vector3(30,0,30+i*3)
		target.force_respawn()
	rack.select(weapon)
	for w in rack.weapons:
		if w is MeleeWeapon:
			w.blood_load=0;w._side=1.0;w._rng.seed=hash(w.display_name)
	aim(weapon,targets[0]);await get_tree().create_timer(.85).timeout
	blood.stage_us.clear();blood.query_count=0
	var initial_events:=blood.combat_event_count()
	var accepted:=blood.accepted_blood_mass
	var peak:=0;var streak_peak:=0;var demand_peak:=0;var stain_peak:=0
	var cpu:Array=[];var previous_cpu:=0
	var stage_cpu:Array=[];var previous_stage:=0
	for frame in 360:
		if frame%54==0 and frame/54<victims and (weapon!=3 or frame==0):
			aim(weapon,targets[frame/54]);rack.try_attack()
		await tick()
		var total:int=blood.stage_us.get("physical_simulation",0);cpu.append(total-previous_cpu);previous_cpu=total
		var stage_total:=0
		for value in blood.stage_us.values():stage_total+=int(value)
		stage_cpu.append(stage_total-previous_stage);previous_stage=stage_total
		peak=maxi(peak,blood._rep_count);streak_peak=maxi(streak_peak,blood._rain_streaks.count)
		var demand:=0
		for i in blood._rep_count:
			if blood._rep_kind[i]>=2 and blood._rep_vel[i].length()>2:demand+=1
		demand_peak=maxi(demand_peak,demand);stain_peak=maxi(stain_peak,blood._surface.live())
	var report:=blood.aftermath_report_for_test()
	var visible_area:=0.0
	for slot in blood._surface.capacity:
		if blood._surface.is_active(slot):
			var xf:Transform3D=blood._surface.recorded_xform[slot]
			visible_area+=xf.basis.x.length()*xf.basis.y.length()
	report.all_active_quad_area=visible_area
	rows.append({"gain":gain,"weapon":weapon,"victims":victims,"events":blood.combat_event_count()-initial_events,"accepted_mass":blood.accepted_blood_mass-accepted,"peak":peak,"trails":streak_peak,"demand":demand_peak,"surface_peak":stain_peak,"queries":blood.query_count,"budgets":blood.peak_frame_usage.duplicate(),"cpu":cpu,"aftermath":report})
	rows[-1].stage_cpu=stage_cpu
	check(blood.combat_event_count()>initial_events,"actual weapon blood event")
	if native and victims==1:
		camera._pitch=-.35
		await tick();await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(DEST+("matched_" if melee_pair else "")+"aftermath_w%d_gain%.1f.png"%[weapon,gain])
	print("DENSITY_CASE ",gain," w",weapon," victims",victims," peak",peak," mass",blood.accepted_blood_mass-accepted)
