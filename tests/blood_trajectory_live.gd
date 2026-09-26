extends "res://tests/blood_rain_hard_live.gd"
const RECOVERY := "res://docs/validation/blood_trajectory_recovery/"
var origins: Array=[]

func save(name: String, data: Variant) -> void:
	var f:=FileAccess.open(RECOVERY+name+".json",FileAccess.WRITE)
	f.store_string(JSON.stringify(data,"\t"));f.close()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RECOVERY))
	# Inherited capture helper uses its original evidence directory.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/validation/blood_rain_hard/"))
	native=DisplayServer.get_name()!="headless"
	world=load("res://world/chambers/prototype/the_box.tscn").instantiate()
	get_tree().root.add_child(world);get_tree().current_scene=world
	blood=world.get_node("BloodSystem");player=world.get_node("Player")
	camera=player.get_node("Head/Camera");rack=camera.get_node("Weapons")
	for target in world.get_node("Targets").get_children():targets.append(target)
	blood.record_causality=true;blood.profile_stages=true
	blood._rain_streaks.layer.begin_recording()
	for child in blood.get_children():
		if child is BloodMultiMeshLayer:layers.append(child);child.profile_writes=true
	await tick();await tick()
	await origin_checks()
	await landing_checks()
	for victims in [1,2,4]: await event(3,victims,7,false)
	for weapon in [0,1,2]: await event(weapon,1,7 if weapon==0 else 1.4,false)
	if native:
		mode_label="trajectory_recovery"
		await event(3,1,7,true)
	save("native" if native else "headless",{"rows":rows,"origins":origins,"failures":failures,
		"sources":{"active":blood.active_wounds()+blood._remnants.size(),"high_water":blood.source_high_water,"cleanups":blood.source_cleanup_count,"reservoir_cap":blood.MAX_WOUND_RESERVOIRS,"remnant_cap":blood.settings.max_remnants}})
	print("TRAJECTORY_LIVE_SAVED failures=",failures.size()," native=",native)
	await get_tree().create_timer(.5).timeout
	get_tree().quit(failures.size())

func origin_checks() -> void:
	blood.clear_all()
	var target:DummyTarget=targets[0]
	target.force_respawn();target.set_physics_process(false)
	target.global_position=Vector3(0,0,-15)
	var reservoir:=target.blood_reservoir()
	var point:=target.global_position+Vector3(.12,1.6,0)
	var ctx:=BloodContext.make(BloodTypes.DamageType.BLUNT,point,Vector3.RIGHT,BloodTypes.BodyRegion.HEAD)
	var rel:=reservoir.withdraw(ctx)
	var wound:=reservoir.open_wound(rel)
	blood.release(rel)
	for i in 4:await tick()
	check(rel.position_ws()==point,"immediate hit snapshot stays at actual contact")
	var positions:=blood._rep_pos.duplicate()
	var count:=blood._rep_count
	target.global_position+=Vector3(3,0,1)
	target.blood_source().rotation.z=.3
	reservoir.tick_wounds(.01)
	var expected:Vector3=target.blood_source().global_transform*wound.local_anchor
	check(wound.last_valid_position.distance_to(expected)<.0001,"new living wound origin follows translation AND visual rotation")
	for i in count:check(blood._rep_pos[i]==positions[i],"released drop is never reattached")
	wound.since_drip=wound.drip_interval
	blood._tick_wounds(.01)
	# Residual releases are synchronous; record physical spawn around current wound.
	var found:=false
	for r in blood.causal_records:
		if r.get("action")=="spawn" and (int(r.get("launch_flags",0))&1)!=0:
			if Vector3(r.position).distance_to(expected)<.7:found=true
	check(found,"future physical release born at current moving wound")
	# Real death path, then advance the corpse Visual independently of the root.
	target.take_damage(10000,expected,Vector3.RIGHT,&"head")
	target._advance_death_throw(.05)
	blood._tick_wounds(.01)
	check(not blood._remnants.is_empty(),"visible death body retains finite source")
	for w in blood._remnants:
		check(w.world_anchor.distance_to(target.blood_source().global_transform*w.local_anchor)<.0001,"corpse source follows current thrown body")
	var after:Vector3=wound.world_anchor
	target.blood_source().hide()
	blood._tick_wounds(.01)
	check(blood._remnants.is_empty(),"hidden corpse terminates source; no ghost neck")
	target.force_respawn()
	check(wound.current_source()==null,"respawn generation cannot resurrect old source")
	var fresh:=reservoir.open_wound(rel)
	var transient:=Node3D.new();world.add_child(transient)
	fresh.bind_source(transient,reservoir,point)
	transient.queue_free();await tick()
	check(fresh.current_source()==null,"freed source ID resolves safely")
	reservoir.tick_wounds(.01)
	check(not reservoir.wounds.has(fresh),"invalid attached source removed")
	origins.append({"hit":point,"moved_wound":expected,"corpse_wound":after,"independent_drops":count,"ghost_sources_after_hide":blood._remnants.size()})
	target.set_physics_process(true)

func landing_checks() -> void:
	var profile:BloodProfile=load("res://data/blood/blood_ballistic.tres")
	for height in [.5,1.0,2.0,4.0]:
		blood.clear_all()
		var id:=blood._emit_representative(profile,Vector3(0,height,-15),Vector3.ZERO,0,.003,1,.001985,3,900)
		var start:=blood._clock
		var contact:Dictionary={}
		for frame in 100:
			await tick()
			for r in blood.causal_records:
				if r.get("action")=="collision" and r.drop_id==id:contact=r
			if not contact.is_empty():break
		check(not contact.is_empty(),"physical landing height%f"%height)
		if not contact.is_empty():check(absf(Vector3(contact.position).y)<.001,"stain fed by actual floor contact")
		origins.append({"height":height,"time_to_ground":blood._clock-start,"contact":contact})
		if height==2:check(blood._clock-start<.45,"2m fall remains fast")
