extends "res://tests/blood_fall_live_test.gd"
const DESTINATION := "res://docs/validation/blood_weapon_signature/"
const TRACK_CAP := 4096
var phase := "baseline"
var traces:Dictionary={}
var contexts:Dictionary={}
var impacts:Array=[]
var marks:Array=[]
var births:Array=[]
var overflow:=0

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("phase="):phase=arg.trim_prefix("phase=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DESTINATION))
	native=DisplayServer.get_name()!="headless"
	world=load("res://world/chambers/prototype/the_box.tscn").instantiate()
	get_tree().root.add_child(world);get_tree().current_scene=world
	blood=world.get_node("BloodSystem");player=world.get_node("Player")
	camera=player.get_node("Head/Camera");rack=camera.get_node("Weapons")
	for t in world.get_node("Targets").get_children():targets.append(t)
	blood.record_causality=true;blood.profile_stages=true
	blood._surface.begin_recording()
	await tick();await tick()
	for weapon in [0,1,2,3]:
		for wall_distance in [2.0,7.0,18.0]:await measure(weapon,wall_distance,1)
	for victims in [2,4]:await measure(3,18.0,victims)
	if native:
		for weapon in [0,1,2,3]:await measure(weapon,7.0,1,true)
		for victims in [1,2,4]:await measure(3,18.0,victims,false,false)
	check(overflow==0,"bounded trace capacity")
	var f:=FileAccess.open(DESTINATION+phase+("_native" if native else "_headless")+".json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"rows":rows,"failures":failures,"overflow":overflow},"\t"));f.close()
	print("SIGNATURE_SAVED phase=",phase," failures=",failures.size())
	await get_tree().create_timer(.5).timeout
	get_tree().quit(failures.size())

func drain() -> void:
	var context:BloodContext=blood.last_context
	if context!=null and not contexts.has(context.event_id):
		var axis:=context.weapon_velocity_ws.normalized() if context.weapon_velocity_ws.length()>1 else context.primary_axis()
		contexts[context.event_id]={"axis":axis,"origin":context.position_ws,"tip_speed":context.weapon_velocity_ws.length()}
	for r in blood.causal_records:
		var action:String=r.get("action","")
		if action=="release_frame":
			contexts[r.event_id]={"axis":r.axis,"origin":r.origin,"tip_speed":r.tip_speed}
		elif action=="spawn":
			if traces.size()>=TRACK_CAP:overflow+=1;continue
			var parent:Dictionary=traces.get(int(r.parent_id),{})
			var ctx:Dictionary=contexts.get(int(r.event_id),{"axis":Vector3.FORWARD,"origin":r.position,"tip_speed":0.0})
			var v:Vector3=r.velocity
			var d:Dictionary={"id":r.drop_id,"event":r.event_id,"kind":r.material_class,"mass":r.represented_mass,
				"origin":parent.get("origin",r.position),"born":parent.get("born",blood._clock),"visible":parent.get("visible",0.0),"relevant":parent.get("relevant",0.0),
				"speed":parent.get("speed",v.length()),"launch_velocity":v,"angle":rad_to_deg(v.angle_to(ctx.axis)),"tip_speed":ctx.tip_speed,
				"diameter":r.physical_diameter,"primary":int(r.parent_id)<0,"residual":(int(r.launch_flags)&1)!=0,"castoff":false,"last_position":r.position,"path":parent.get("path",0.0)}
			traces[r.drop_id]=d
			if d.primary and not d.residual:births.append(d.duplicate())
		elif action=="castoff":
			for id in traces:
				if traces[id].event==r.event_id:
					traces[id].castoff=true
					traces[id].angle=rad_to_deg(Vector3(traces[id].launch_velocity).angle_to(r.tip_velocity))
			for d in births:
				if d.event==r.event_id:d.castoff=true;d.angle=rad_to_deg(Vector3(d.launch_velocity).angle_to(r.tip_velocity))
		elif action=="collision" and traces.has(r.drop_id):
			var d:Dictionary=traces[r.drop_id].duplicate()
			if d.residual:continue
			d.range=Vector3(r.position).distance_to(d.origin);d.life=blood._clock-float(d.born)
			d.ratio=float(d.visible)/maxf(float(d.life),.00001)
			d.relevant_ratio=float(d.visible)/maxf(float(d.relevant),.00001)
			d.position=r.position;d.impact_velocity=r.velocity
			d.mass=r.mass;d.normal=r.get("normal",Vector3.ZERO)
			d.wall=absf(Vector3(r.position).x-40.0)<0.08
			impacts.append(d)
		elif action=="stain" and marks.size()<4096:
			var slot:int=r.slot
			var xf:Transform3D=blood._surface.recorded_xform[slot]
			marks.append({"drop":r.drop_id,"event":r.event_id,"position":r.position,"normal":xf.basis.z.normalized(),"mass":r.mass,"width":maxf(xf.basis.x.length(),xf.basis.y.length()),"coarse":int(r.drop_id)<0})
	blood.causal_records.clear()

func measure(weapon:int,wall_distance:float,victims:int,capture:=false,telemetry:=true) -> void:
	blood.record_causality=telemetry
	blood.clear_all();blood.seed_for_test(8319)
	traces.clear();contexts.clear();impacts.clear();marks.clear();births.clear()
	var centre:=Vector3(40-wall_distance,0,-12)
	for i in targets.size():
		targets[i]._spawn_position=centre+Vector3(0,0,float(i)*1.5) if i<victims else Vector3(-30,0,30+i*3)
		targets[i].force_respawn()
	player.global_position=centre+Vector3(-7 if weapon==0 or weapon==3 else -1.4,.05,0)
	player.velocity=Vector3.ZERO;player.rotation=Vector3(0,-PI/2,0);camera._pitch=0;camera._recoil=Vector2.ZERO
	rack.select(weapon)
	for w in rack.weapons:
		if w is MeleeWeapon:w.blood_load=0
	await get_tree().create_timer(.85).timeout
	blood.stage_us.clear();blood.query_count=0;blood.causal_records.clear()
	var before:=blood.combat_event_count();rack.try_attack()
	var previous_cpu:=0;var last:=Time.get_ticks_usec();var cpu:Array=[];var frames:Array=[]
	var peak:=0;var streak_peak:=0;var demand_peak:=0
	var since_birth:=-1
	for frame in 300:
		if telemetry:drain()
		if not births.is_empty():since_birth+=1
		if capture and since_birth in [5,15,30]:
			get_viewport().get_texture().get_image().save_png(DESTINATION+"w%d_frame%d.png"%[weapon,since_birth])
		await tick()
		var now:=Time.get_ticks_usec();frames.append(now-last);last=now
		var total:int=blood.stage_us.get("physical_simulation",0);cpu.append(total-previous_cpu);previous_cpu=total
		if telemetry:drain()
		var selected:Dictionary={}
		for j in blood._rain_streaks.count:selected[blood._rain_streaks.drop_ids[j]]=true
		var demand:=0
		for i in blood._rep_count:
			var id:int=blood._rep_id[i]
			if not traces.has(id):continue
			var d:Dictionary=traces[id]
			d.path+=Vector3(d.last_position).distance_to(blood._rep_pos[i]);d.last_position=blood._rep_pos[i]
			if camera.is_position_in_frustum(blood._rep_pos[i]):
				d.relevant+=1.0/60
				if selected.has(id):d.visible+=1.0/60
			if blood._rep_kind[i]>=2 and blood._rep_vel[i].length()>=2:demand+=1
		peak=maxi(peak,blood._rep_count);streak_peak=maxi(streak_peak,selected.size());demand_peak=maxi(demand_peak,demand)
		# Real second alternating swing, including preloaded cast-off.
		if frame==90 and weapon in [1,2]:rack.try_attack()
	check(blood.combat_event_count()>before,"actual weapon event%d wall%f"%[weapon,wall_distance])
	var row:Dictionary={"weapon":weapon,"wall":wall_distance,"victims":victims,"events":blood.combat_event_count()-before,"births":births.duplicate(true),"impacts":impacts.duplicate(true),"stains":marks.duplicate(true),"contexts":contexts.duplicate(true),"cpu":cpu,"frames":frames,"peak":peak,"streak_peak":streak_peak,"demand_peak":demand_peak,"queries":blood.query_count,"budgets":blood.peak_frame_usage.duplicate()}
	rows.append(row)
	row.capture=capture
	row.telemetry=telemetry
	row.ledger=blood.mass_ledger();row.sources=blood.active_wounds();row.source_peak=blood.source_high_water
	print("SIGNATURE_CASE w",weapon," wall=",wall_distance," births=",births.size()," impacts=",impacts.size()," stains=",marks.size())
