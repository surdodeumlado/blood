extends SceneTree
## Isolation only, not a stress test. Explicit mode chooses ONE minimal path.
## Do not loop this probe to turn an intermittent crash into a passing result.
var holder: Node3D

func _initialize() -> void:
	call_deferred("probe")

func probe() -> void:
	if "--world" in OS.get_cmdline_user_args():
		var script := load("res://presentation/gore/blood_system.gd") as Script
		var node := script.new() as Node3D
		node.settings = (load("res://data/blood/blood_settings.tres") as BloodSettings).duplicate()
		node.settings.prewarm = false
		root.add_child(node)
		node.set_physics_process(false)
		await physics_frame
		await process_frame
		print("PROBE world: constructed empty fixed layers, no combat or audio playback")
		node.queue_free()
		await physics_frame
		await process_frame
		print("PROBE world: scene freed while servers remain alive")
	elif "--resources" in OS.get_cmdline_user_args():
		var script := load("res://presentation/gore/blood_system.gd") as Script
		var node := script.new() as Node3D
		node.free() # Not added to a world: no renderer/audio resources constructed.
		print("PROBE resources: BloodSystem script loaded/constructed/freed without _ready")
	else:
		holder = Node3D.new()
		root.add_child(holder)
		var component := BloodImpactAudioAccumulator.new()
		holder.add_child(component)
		component.setup(BloodStabilitySettings.new())
		var surface: BloodSurfaceResponse = load("res://data/blood/surfaces/smooth.tres")
		for i in 100: component.submit(Vector3.ZERO, surface, 0.002, 5, 3, Vector3.UP, 0)
		component.advance(0.09, 2)
		await create_timer(0.5).timeout
		component.clear()
		await physics_frame
		await create_timer(0.2).timeout
		print("PROBE audio: six pooled players, one clustered playback, stopped")
	quit()
