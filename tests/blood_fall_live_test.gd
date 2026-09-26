extends Node
## Actual THE_BOX weapons. One persistent scene, <=8 cases, bounded observations.
const OUTPUT := "res://docs/validation/blood_fall_final/"
const SAMPLE_CAP := 2048 # per class, per case; seven classes, five numeric arrays
var world: Node3D
var blood: BloodSystem
var player: CharacterBody3D
var camera: FirstPersonCamera
var rack: WeaponRack
var targets: Array[DummyTarget] = []
var original_positions: Array[Vector3] = []
var rows: Array = []
var failures: Array[String] = []
var native := false

func tick() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error(label)
func save(name: String, data: Variant) -> void:
	var file := FileAccess.open(OUTPUT+name+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(data,"\t")); file.close()
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	native = DisplayServer.get_name() != "headless"
	world = load("res://world/chambers/prototype/the_box.tscn").instantiate()
	get_tree().root.add_child(world); get_tree().current_scene=world
	blood = world.get_node("BloodSystem"); player=world.get_node("Player")
	camera=player.get_node("Head/Camera"); rack=camera.get_node("Weapons")
	for target in world.get_node("Targets").get_children():
		targets.append(target); original_positions.append(target.global_position)
	blood.record_causality=true; blood.profile_stages=true
	blood._small.begin_recording(); blood._medium.begin_recording()
	for layer in [blood._small,blood._medium,blood._surface,blood._impact_accent.layer]: layer.profile_writes=true
	await tick(); await tick()
	# No PNG readback during perf cases. Captures use separate single-victim cases.
	for victims in [1,2,4]: await event(3,victims,7,false)
	for weapon in [0,1,2]: await event(weapon,1,7 if weapon==0 else 1.4,false)
	if native:
		await event(3,1,4,true)
		await event(3,1,10,true)
	await audio_missing_check()
	save("native" if native else "headless",{"rows":rows,"failures":failures,"foley_loaded":blood._audio.bank.loaded_count,
		"foley_missing":blood._audio.missing_foley_events,"real_samples_played":blood._audio.last_events,
		"caps":{"physical":blood._rep_slot.size(),"trails":96,"voices":6,"foley":17,"samples_per_class":SAMPLE_CAP}})
	print("FALL_FINAL_SAVED failures=",failures.size()," native=",native)
	await get_tree().create_timer(1.5).timeout
	get_tree().quit(failures.size())

func event(weapon: int, victims: int, distance: float, captures: bool) -> void:
	blood.clear_all(); blood.seed_for_test(8319)
	var centre := Vector3(0,0,-20)
	for i in targets.size():
		# Fixture arrangement only: no new victim nodes or damage-rule changes.
		targets[i]._spawn_position = centre+Vector3(float(i%2)*1.8,0,-float(i/2)*1.8) if i<victims else Vector3(30,0,30+float(i)*3)
		targets[i].force_respawn()
	player.global_position=centre+Vector3(0,0.05,distance)
	player.velocity=Vector3.ZERO; player.rotation=Vector3.ZERO
	camera._pitch=0; camera._recoil=Vector2.ZERO
	rack.select(weapon)
	await get_tree().create_timer(0.85).timeout
	blood.stage_us.clear(); blood.query_count=0; blood.causal_records.clear()
	var before := blood.combat_event_count()
	var start := Time.get_ticks_usec()
	rack.try_attack()
	var request_us := Time.get_ticks_usec()-start
	var waited := 0
	while blood.combat_event_count()==before and waited<210:
		await tick(); waited+=1
	check(blood.combat_event_count()>before,"real weapon produced blood index%d"%weapon)
	var label := "w%d_v%d_%dm%s"%[weapon,victims,int(distance),"_capture" if captures else ""]
	var row := {"label":label,"weapon":weapon,"victims_requested":victims,"events":0,"distance":distance,"captures":captures,
		"request_us":request_us,"cpu_us":[],"frame_us":[],"samples":[],"snapshots":[],"initial":[],"peak_reps":0,"trail_peak":0}
	for kind in 7:
		row.samples.append({"kind":kind,"falling":0,"eligible":0,"selected":0,"written":0,"diameter":[],"down":[],"head":[],"tail":[]})
	var birth := blood._clock
	var previous_us := 0
	var previous_frame := Time.get_ticks_usec()
	var next_capture := 0
	var times := [0.05,0.12,0.2,0.35,0.6]
	for frame in 90:
		await tick()
		var now := Time.get_ticks_usec(); row.frame_us.append(now-previous_frame); previous_frame=now
		var sum := 0
		for key in blood.stage_us: sum+=int(blood.stage_us[key])
		row.cpu_us.append(maxi(0,sum-previous_us)); previous_us=sum
		row.peak_reps=maxi(row.peak_reps,blood._rep_count)
		var trail_count := 0
		for i in blood._rep_count:
			trail_count+=int(blood._rep_trail[i]!=0)
			if (blood._rep_flags[i] & 1)!=0: continue # Primary flight, not late wound drips.
			if blood._rep_vel[i].y>=-1 or blood._rep_age[i]<0.03: continue
			var kind:int=blood._rep_kind[i]
			var s:Dictionary=row.samples[kind]
			var layer:=blood._small if blood._rep_layer[i]==1 else blood._medium
			var slot:int=blood._rep_slot[i]
			var transform:Transform3D=layer.recorded_xform[slot]
			var tail:float=layer.recorded_custom[slot].r*transform.basis.z.length()
			s.falling+=1
			s.eligible+=int(blood.trail_length_for(kind,blood._rep_vel[i].length(),blood._rep_profile[i].damage_type)>0)
			s.selected+=int(blood._rep_trail[i]!=0); s.written+=int(tail>0.001)
			if frame%3==0 and s.diameter.size()<SAMPLE_CAP:
				s.diameter.append(blood._rep_diameter[i]); s.down.append(-blood._rep_vel[i].y)
				s.head.append(transform.basis.x.length()); s.tail.append(tail)
		row.trail_peak=maxi(row.trail_peak,trail_count)
		var elapsed:=blood._clock-birth
		if next_capture<times.size() and elapsed>=times[next_capture]:
			row.snapshots.append({"time":elapsed,"reps":blood._rep_count,"accents":blood._impact_accent.count})
			if captures:
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(OUTPUT+label+"_%03d.png"%int(times[next_capture]*1000))
			next_capture+=1
		if frame>=5 and frame<16: camera.look(Vector2(0.6,0))
	row.events=blood.combat_event_count()-before
	for record in blood.causal_records:
		if record.get("action")=="spawn" and int(record.get("parent_id",-1))<0 and row.initial.size()<512: row.initial.append(record)
	row.queries=blood.query_count; row.stages=blood.stage_us.duplicate()
	row.material=blood.material_stats.duplicate(); row.budgets=blood.peak_frame_usage.duplicate()
	row.audio=blood._audio.last_events.duplicate(true); row.foley_missing=blood._audio.missing_foley_events
	row.accepted_mass=blood.accepted_blood_mass
	check(row.trail_peak<=96,label+" trail budget")
	check(int(row.budgets.get("queries",0))<=640,label+" query budget")
	check(blood._audio.peak_voices<=6,label+" voice budget")
	if weapon==3: check(row.events==victims,label+" actual multi-victim count")
	if weapon!=3:
		var written:=0
		for s in row.samples: written+=int(s.written)
		check(written>0,label+" global falling trail written")
	rows.append(row)
	save(label+("_native" if native else "_headless"),row)
	print("FALL_CASE ",label," events=",row.events," reps_peak=",row.peak_reps)
	await get_tree().create_timer(2.0).timeout

func audio_missing_check() -> void:
	if blood._audio.bank.loaded_count>0: return
	blood._audio.clear()
	var missing:=blood._audio.missing_foley_events
	var before:=blood._audio.played
	var surface:BloodSurfaceResponse=load("res://data/blood/surfaces/smooth.tres")
	for count in [1,5,20,50,100]:
		for i in count: blood._audio.submit(player.global_position,surface,0.002,5,3,Vector3.UP,blood._clock)
		await get_tree().create_timer(0.15).timeout
	check(blood._audio.played==before and blood._audio.missing_foley_events>missing,"missing bank silent, no synthesized substitute")
