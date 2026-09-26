extends "res://tests/blood_fall_live_test.gd"
## Bounded real-weapon THE_BOX matrix. No gameplay scripts are changed.
const DEST := "res://docs/validation/blood_rain_hard/"
var mode_label := "production"
var layers: Array = []

func save(name: String, data: Variant) -> void:
	var file := FileAccess.open(DEST+name+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(data,"\t")); file.close()

func run() -> void:
	native=DisplayServer.get_name()!="headless"
	world=load("res://world/chambers/prototype/the_box.tscn").instantiate()
	get_tree().root.add_child(world); get_tree().current_scene=world
	blood=world.get_node("BloodSystem"); player=world.get_node("Player")
	camera=player.get_node("Head/Camera"); rack=camera.get_node("Weapons")
	for target in world.get_node("Targets").get_children(): targets.append(target)
	blood.record_causality=true; blood.profile_stages=true
	blood._rain_streaks.layer.begin_recording()
	for child in blood.get_children():
		if child is BloodMultiMeshLayer: layers.append(child); child.profile_writes=true
	await tick(); await tick()
	if native:
		for variant in ["rejected","density","production","streak_only"]:
			configure(variant)
			await event(3,1,7,true)
		print("HARD_GEOMETRY_READY: inspect captures; write continue_native.txt to continue this SAME process")
		for frame in 14400: # <=240 seconds; no unbounded deferred chain.
			if FileAccess.file_exists(DEST+"continue_native.txt"): break
			await tick()
		if not FileAccess.file_exists(DEST+"continue_native.txt"):
			save("native_checkpoint",{"status":"geometry review timed out","rows":rows})
			get_tree().quit(2); return
	configure("production")
	for victims in [1,2,4]: await event(3,victims,7,false)
	for weapon in [0,1,2]: await event(weapon,1,7 if weapon==0 else 1.4,native)
	if native:
		# Second real dagger swing uses blood legitimately retained by the first.
		mode_label="production_castoff"
		await event(1,1,1.4,true)
		mode_label="production"
		await event(3,1,4,true)
		await event(3,1,10,true)
	save("hard_native" if native else "hard_headless",{"rows":rows,"failures":failures,
		"foley_loaded":blood._audio.bank.loaded_count,"last_missing_impact":blood._audio.last_missing_impact,
		"audio_played":blood._audio.last_events,"capacities":{"physical":blood._rep_slot.size(),
		"streaks":blood._rain_streaks.slots.size(),"selected":blood.settings.stability.rain_streak_budget,"voices":6}})
	print("HARD_SAVED failures=",failures.size())
	await get_tree().create_timer(1.5).timeout
	get_tree().quit(failures.size())

func configure(variant: String) -> void:
	mode_label=variant
	var s:=blood.settings.stability
	var old:=variant=="rejected"
	s.rain_rejected_baseline_debug=old
	s.rain_streak_mode=2 if variant=="streak_only" else (0 if variant=="density" or old else 1)
	s.explosion_small_sampling=.12 if old else .65
	s.explosion_medium_sampling=.35 if old else .9
	s.explosion_medium_fraction=.72 if old else .52
	s.explosion_large_fraction=.24 if old else .25
	s.rain_medium_min_physical_m=.00185 if old else .00198
	s.rain_launch_speed_scale=.14 if old else .18
	s.rain_medium_downward_m_s=5.6 if old else 9.2
	s.rain_large_downward_m_s=7.2 if old else 11.2
	s.rain_glob_downward_m_s=8 if old else 12.5
	s.rain_high_arc_fraction=0 if old else .35

func counters() -> Dictionary:
	var d:Dictionary={"writes":0,"commits":0,"surface_writes":blood._surface.write_count,"streak_writes":blood._rain_streaks.layer.write_count}
	for layer in layers: d.writes+=layer.write_count; d.commits+=layer.commit_count
	return d

func sample() -> Dictionary:
	var lookup:Dictionary={}
	for k in blood._rain_streaks.count:
		lookup[blood._rain_streaks.drop_ids[k]]=blood._rain_streaks.layer.recorded_xform[blood._rain_streaks.slots[k]]
	var result:Dictionary={"classes":[],"high_arc_alive":0,"eligible":0,"selected":0,"written":lookup.size()}
	for kind in [2,3,4,5,6]:
		var d:Dictionary={"kind":kind,"count":0,"falling":0,"eligible":0,"selected":0,"written":0,
			"y":[],"speed":[],"diameter":[],"length":[],"width":[],"main_rain_y":[]}
		for i in blood._rep_count:
			if blood._rep_kind[i]!=kind or (blood._rep_flags[i]&1)!=0: continue
			d.count+=1
			if (blood._rep_flags[i]&8)!=0: result.high_arc_alive+=1
			if blood._rep_vel[i].y>=-1: continue
			d.falling+=1; d.y.append(blood._rep_vel[i].y); d.speed.append(blood._rep_vel[i].length())
			d.diameter.append(blood._rep_diameter[i])
			if (blood._rep_flags[i]&4)!=0: d.main_rain_y.append(blood._rep_vel[i].y)
			d.eligible+=int(blood._rep_vel[i].length()>=blood.settings.stability.rain_streak_min_speed)
			d.selected+=int(blood._rep_trail[i]!=0)
			if lookup.has(blood._rep_id[i]):
				var t:Transform3D=lookup[blood._rep_id[i]]
				d.written+=1; d.length.append(t.basis.y.length()); d.width.append(t.basis.x.length())
		result.eligible+=d.eligible; result.selected+=d.selected; result.classes.append(d)
	return result

func event(weapon: int, victims: int, distance: float, captures: bool) -> void:
	blood.clear_all(); blood.seed_for_test(8319)
	var centre:=Vector3(0,0,-20)
	for i in targets.size():
		targets[i]._spawn_position=centre+Vector3(float(i%2)*1.8,0,-float(i/2)*1.8) if i<victims else Vector3(30,0,30+i*3)
		targets[i].force_respawn()
	player.global_position=centre+Vector3(0,.05,distance); player.velocity=Vector3.ZERO; player.rotation=Vector3.ZERO
	camera._pitch=0; camera._recoil=Vector2.ZERO; rack.select(weapon)
	await get_tree().create_timer(.85).timeout
	blood.stage_us.clear(); blood.query_count=0; blood.causal_records.clear()
	var before:=blood.combat_event_count()
	var count_start:=counters()
	var start:=Time.get_ticks_usec(); rack.try_attack(); var request_us:=Time.get_ticks_usec()-start
	var waited:=0
	while blood.combat_event_count()==before and waited<210: await tick(); waited+=1
	check(blood.combat_event_count()>before,"actual weapon blood %d"%weapon)
	var label:="%s_w%d_v%d_%dm%s"%[mode_label,weapon,victims,int(distance),"_capture" if captures else ""]
	var row:Dictionary={"label":label,"request_us":request_us,"cpu_physical_us":[],"frame_us":[],"snapshots":[],
		"initial":[],"castoff_records":[],"peak_reps":0,"streak_peak":0,"all_motion_written":0,"fall_written":0,"streak_demand_peak":0}
	var birth:=blood._clock; var previous_cpu:=0; var previous_frame:=Time.get_ticks_usec()
	var seen:Dictionary={}
	var next_capture:=0; var times:=[.025,.08,.15,.25,.5,.75,1.0,2.0,3.0]
	for frame in 190:
		# Capture births before the bounded causal log rolls over in multi-hit.
		if frame<30:
			for record in blood.causal_records:
				if record.get("action")=="castoff" and not row.castoff_records.has(record) and row.castoff_records.size()<32: row.castoff_records.append(record)
				if record.get("action")!="spawn" or int(record.get("parent_id",-1))>=0: continue
				var id:int=record.drop_id
				if seen.has(id) or seen.size()>=2048: continue
				seen[id]=true; row.initial.append(record)
		await tick()
		var now:=Time.get_ticks_usec(); row.frame_us.append(now-previous_frame); previous_frame=now
		var cpu:int=blood.stage_us.get("physical_simulation",0)
		row.cpu_physical_us.append(maxi(0,cpu-previous_cpu)); previous_cpu=cpu
		row.peak_reps=maxi(row.peak_reps,blood._rep_count); row.streak_peak=maxi(row.streak_peak,blood._rain_streaks.count)
		row.all_motion_written+=blood._rain_streaks.count
		var demand:=0
		for i in blood._rep_count:
			if blood._rep_kind[i]>=2 and blood._rep_vel[i].length()>=2: demand+=1
		row.streak_demand_peak=maxi(row.streak_demand_peak,demand)
		var elapsed:=blood._clock-birth
		if next_capture<times.size() and elapsed>=times[next_capture]:
			var snap:=sample(); snap.time=elapsed; snap.reps=blood._rep_count; row.snapshots.append(snap)
			for cl in snap.classes: row.fall_written+=cl.written
			if captures:
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(DEST+label+"_%04d.png"%int(times[next_capture]*1000))
			next_capture+=1
	row.events=blood.combat_event_count()-before
	row.queries=blood.query_count; row.stages=blood.stage_us.duplicate(); row.budgets=blood.peak_frame_usage.duplicate()
	row.counter_delta=counters()
	for key in count_start: row.counter_delta[key]-=count_start[key]
	row.audio=blood._audio.last_events.duplicate(true); row.audio_missing=blood._audio.last_missing_impact.duplicate()
	row.mass=blood.accepted_blood_mass
	check(row.streak_peak<=blood.settings.stability.rain_streak_budget,label+" fixed streak budget")
	check(int(row.budgets.get("queries",0))<=640,label+" query budget")
	if weapon==3: check(row.events==victims,label+" real victim count")
	if mode_label=="production": check(row.all_motion_written>0,label+" shared streak write")
	rows.append(row); save(label+("_native" if native else "_headless"),row)
	print("HARD_CASE ",label," reps=",row.peak_reps," streaks=",row.streak_peak," demand=",row.streak_demand_peak)
	await get_tree().create_timer(.5).timeout
