extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var fixture:Node=load("res://tests/blood_stability_test.gd").new()
	fixture.output="res://docs/validation/blood_trajectory_recovery"
	root.add_child(fixture)
