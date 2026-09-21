extends Node3D

## BLOOD LAB - a development instrument, not content.
##
## Four identical targets in four identical bays, one per impact family, so the
## aftermath of a ballistic kill, a slash, a maul blow and a grenade can be
## walked between and compared side by side. If you cannot tell which bay is
## which from the blood alone, the visual work is not finished.
##
## Controls:
##     1 / 2 / 3 / 4   weapon (Hand Cannon, Twin Daggers, Maul, Grenade)
##     F4              blood pattern debug overlay + telemetry
##     R (interact)    RESET: wipe all blood, tissue, stains and wounds,
##                     refill every reservoir and respawn every target
##     F3              hurtbox overlay
##
## Everything here is built in code on purpose: a dev rig should be one file you
## can read, not a scene you have to open an editor to understand.

const DUMMY := "res://gameplay/enemies/dummy_target.tscn"
const PLAYER := "res://gameplay/player/player.tscn"

## Bay spacing. Wide enough that one family's spatter cannot be mistaken for
## its neighbour's.
const BAY_SPACING := 16.0
const BAY_COUNT := 4
const FLOOR_HALF := 34.0
const WALL_HEIGHT := 7.0
## Targets stand this far in front of their back wall, so forward spatter has a
## surface to land on and the pattern is readable on a vertical plane.
const TARGET_TO_WALL := 3.2

const BAY_NAMES := ["1 BALLISTIC", "2 SLASHING", "3 BLUNT", "4 EXPLOSIVE"]

var _targets: Array[Node3D] = []
var _blood: BloodSystem
var _player: Node3D
var _report_timer := 0.0


func _ready() -> void:
	_build_lighting()
	_build_room()
	_blood = $BloodSystem
	# The lab is where the upper visual target is established, so it runs at
	# INSANE regardless of what the settings resource was last saved with.
	_blood.settings.quality = BloodTypes.Quality.INSANE
	_build_bays()
	_spawn_player()
	print("=== BLOOD LAB ===  1-4 weapons | F4 pattern debug | interact key = RESET")


func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 0.85
	sun.shadow_enabled = false
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.05, 0.06)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.44, 0.5)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)


func _build_room() -> void:
	# Pale floor and walls on purpose: blood has to be legible against them, and
	# this rig exists to judge legibility.
	_slab(
		Vector3(FLOOR_HALF * 2.0, 1.0, FLOOR_HALF * 2.0),
		Vector3(0.0, -0.5, 0.0),
		Color(0.62, 0.60, 0.58)
	)
	# Back wall the targets spatter onto, plus a far wall for long-range material.
	_slab(
		Vector3(FLOOR_HALF * 2.0, WALL_HEIGHT, 1.0),
		Vector3(0.0, WALL_HEIGHT * 0.5, -FLOOR_HALF),
		Color(0.55, 0.54, 0.53)
	)
	_slab(
		Vector3(FLOOR_HALF * 2.0, WALL_HEIGHT, 1.0),
		Vector3(0.0, WALL_HEIGHT * 0.5, FLOOR_HALF),
		Color(0.55, 0.54, 0.53)
	)
	_slab(
		Vector3(1.0, WALL_HEIGHT, FLOOR_HALF * 2.0),
		Vector3(-FLOOR_HALF, WALL_HEIGHT * 0.5, 0.0),
		Color(0.55, 0.54, 0.53)
	)
	_slab(
		Vector3(1.0, WALL_HEIGHT, FLOOR_HALF * 2.0),
		Vector3(FLOOR_HALF, WALL_HEIGHT * 0.5, 0.0),
		Color(0.55, 0.54, 0.53)
	)


## One target per family, each with its own back panel so the forward pattern
## lands on a clean vertical surface and can be read at a glance.
func _build_bays() -> void:
	var first := -(BAY_COUNT - 1) * 0.5 * BAY_SPACING
	for i in BAY_COUNT:
		var x := first + i * BAY_SPACING
		# Back panel, and a low side baffle so neighbouring bays do not bleed
		# into each other's evidence.
		_slab(
			Vector3(BAY_SPACING - 1.5, WALL_HEIGHT, 0.6),
			Vector3(x, WALL_HEIGHT * 0.5, -12.0),
			Color(0.66, 0.65, 0.64)
		)
		_slab(
			Vector3(0.5, 2.6, 9.0),
			Vector3(x + BAY_SPACING * 0.5, 1.3, -8.0),
			Color(0.48, 0.47, 0.47)
		)
		var target: Node3D = load(DUMMY).instantiate()
		target.position = Vector3(x, 0.0, -12.0 + TARGET_TO_WALL)
		add_child(target)
		_targets.append(target)
		_label(BAY_NAMES[i], Vector3(x, 4.2, -11.5))


func _slab(size: Vector3, pos: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	mesh.material_override = mat
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	shape.shape = s
	body.add_child(shape)
	add_child(body)


func _label(text: String, pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = 0.004
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = Color(0.95, 0.95, 1.0)
	l.no_depth_test = false
	add_child(l)


func _spawn_player() -> void:
	_player = load(PLAYER).instantiate()
	_player.position = Vector3(0.0, 0.6, 4.0)
	add_child(_player)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		reset()


## Wipe everything so the same four kills can be performed again from clean.
func reset() -> void:
	_blood.clear_all()
	for t in _targets:
		if is_instance_valid(t) and t.has_method("force_respawn"):
			t.force_respawn()
	print("[lab] reset - arena clean, %d targets restored" % _targets.size())


func _process(delta: float) -> void:
	# A quiet heartbeat so the live budget is visible while tuning, without
	# needing the debug overlay on.
	if not _blood.settings.debug_telemetry:
		return
	_report_timer -= delta
	if _report_timer > 0.0:
		return
	_report_timer = 2.0
	print("[lab] live %s" % _blood.live_counts())
