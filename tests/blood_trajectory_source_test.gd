extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var blood:=BloodSystem.new()
	blood.settings=load("res://data/blood/blood_settings.tres")
	root.add_child(blood);blood.set_physics_process(false);blood.set_process(false)
	var victim:=Node3D.new();root.add_child(victim)
	var reservoir:=BloodReservoir.new();victim.add_child(reservoir)
	blood.register_reservoir(reservoir)
	var ctx:=BloodContext.make(BloodTypes.DamageType.SLASHING,Vector3.UP,Vector3.RIGHT,BloodTypes.BodyRegion.TORSO)
	var wound:=reservoir.open_wound(reservoir.withdraw(ctx))
	reservoir.reparent(root) # Deliberately orphan a surviving reservoir.
	victim.queue_free()
	await process_frame
	blood._tick_wounds(0.01)
	var passed:=wound.current_source()==null and reservoir.wounds.is_empty() and not blood._reservoirs.has(reservoir)
	print("ORPHAN_SOURCE_CLEANUP ",passed)
	quit(0 if passed else 1)
