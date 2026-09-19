extends Node3D

## Headless runtime check for MovementController, ImpactFx and DummyTarget.
## Not a unit-test framework, just a scripted timeline that drives the systems
## through every state and asserts the invariants that matter.
##
##   godot --headless --path . res://tests/movement_smoke_test.tscn
##
## Exits with code 1 if anything fails.

const MOVEMENT_CONFIG := "res://data/movement/default_movement.tres"
const COMBAT_CONFIG := "res://data/combat/default_combat.tres"
const DUMMY_SCENE := "res://gameplay/enemies/dummy_target.tscn"

var config: MovementConfig
var combat: CombatConfig
var body: CharacterBody3D
var movement: MovementController

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	config = load(MOVEMENT_CONFIG)
	combat = load(COMBAT_CONFIG)
	_build_world()
	_build_player()
	_run()


func _physics_process(delta: float) -> void:
	if movement == null:
		return
	movement.step(delta)
	movement.wants_jump = false
	movement.wants_dash = false


# --------------------------------------------------------------------------

func _build_world() -> void:
	_add_box(Vector3(200, 1, 200), Vector3(0, -0.5, 0))        # floor
	_add_box(Vector3(10, 0.5, 10), Vector3(60, 1.45, 0))       # ceiling, 1.2 clearance


func _add_box(size: Vector3, pos: Vector3) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sb.add_child(cs)
	add_child(sb)
	sb.global_position = pos


func _build_player() -> void:
	body = CharacterBody3D.new()
	body.floor_max_angle = 0.959931
	body.floor_snap_length = 0.3
	var collider := CollisionShape3D.new()
	var head := Node3D.new()
	var mc := MovementController.new()
	mc.config = config
	body.add_child(collider)
	body.add_child(head)
	body.add_child(mc)
	add_child(body)
	body.global_position = Vector3(0, 0.2, 0)
	mc.setup(body, collider, head)
	movement = mc


# --------------------------------------------------------------------------

func _run() -> void:
	await _basics()
	await _dash_and_slide()
	await _ceiling()
	await _air_model()
	await _bunnyhop()
	await _framerate_independence()
	await _fx_pool()
	await _dummy()
	await _shooting()
	_report()


func _basics() -> void:
	await _tick(20)
	_check(body.is_on_floor(), "settles on the floor")
	_check(movement.state == MovementController.State.GROUND, "idles in GROUND")
	_check(movement.horizontal_speed() < 0.1, "idle speed is zero")

	movement.input_dir = Vector2(0, 1)
	await _tick(30)
	_check(
		movement.horizontal_speed() > config.move_speed - 0.5,
		"reaches base speed (%.2f)" % movement.horizontal_speed()
	)


func _dash_and_slide() -> void:
	movement.wants_dash = true
	await _tick(1)
	_check(movement.state == MovementController.State.DASH, "dash starts")
	_check(
		movement.horizontal_speed() > config.dash_speed - 0.5,
		"dash reaches dash_speed (%.2f)" % movement.horizontal_speed()
	)
	await _tick(int(ceil(config.dash_duration * 60.0)) + 2)
	_check(movement.state != MovementController.State.DASH, "dash ends by itself")
	_check(
		movement.horizontal_speed() > config.move_speed,
		"momentum survives the dash (%.2f)" % movement.horizontal_speed()
	)

	movement.wants_crouch = true
	await _tick(2)
	_check(movement.state == MovementController.State.SLIDE, "fast crouch becomes a slide")
	var slide_speed := movement.horizontal_speed()

	movement.wants_jump = true
	await _tick(2)
	_check(
		movement.horizontal_speed() > slide_speed - 0.5,
		"slide jump keeps horizontal momentum (%.2f -> %.2f)" % [
			slide_speed, movement.horizontal_speed()
		]
	)
	_check(body.velocity.y > 0.0, "slide jump actually leaves the ground")

	movement.wants_crouch = false
	movement.input_dir = Vector2.ZERO
	await _tick(90)
	_check(movement.state == MovementController.State.GROUND, "returns to GROUND")

	movement.wants_crouch = true
	await _tick(10)
	_check(movement.state == MovementController.State.CROUCH, "slow crouch stays CROUCH")


func _ceiling() -> void:
	body.global_position = Vector3(60, 0.1, 0)
	body.velocity = Vector3.ZERO
	await _tick(20)
	_check(movement.state == MovementController.State.CROUCH, "crouched under the ceiling")
	movement.wants_crouch = false
	await _tick(40)
	_check(
		movement.state == MovementController.State.CROUCH,
		"stays crouched: no clearance to stand"
	)
	var head_node := body.get_child(1) as Node3D
	_check(
		head_node.position.y < 1.0,
		"head stays low under the ceiling (%.2f)" % head_node.position.y
	)

	movement.input_dir = Vector2(0, 1)
	body.global_position = Vector3(0, 0.1, 0)
	await _tick(40)
	_check(movement.state == MovementController.State.GROUND, "stands up in the open")


## The two halves of the air model, checked separately.
func _air_model() -> void:
	# Holding forward in the air must never push past move_speed.
	await _reset(Vector3(0, 0.2, 0))
	movement.input_dir = Vector2(0, 1)
	await _tick(40)
	movement.wants_jump = true
	await _tick(1)
	movement.input_dir = Vector2(0, 1)
	await _tick(30)
	_check(
		movement.horizontal_speed() <= config.move_speed + 0.05,
		"holding forward in the air cannot exceed move_speed (%.2f)" % movement.horizontal_speed()
	)

	# Holding strafe with a FIXED view is worth almost nothing.
	await _reset(Vector3(0, 0.2, 0))
	movement.input_dir = Vector2(0, 1)
	await _tick(40)
	var before := movement.horizontal_speed()
	movement.wants_jump = true
	await _tick(1)
	movement.input_dir = Vector2(-1, 0)
	await _tick(30)
	var held_gain := movement.horizontal_speed() - before
	_check(
		held_gain < 0.6,
		"holding a strafe key without turning barely gains (+%.2f m/s)" % held_gain
	)


## A perfect-strafe bot: hold A and rotate the view so the wish direction stays
## perpendicular to the velocity, jumping on the tick after every landing.
func _bhop_peak(ticks: int) -> float:
	await _reset(Vector3(0, 0.2, -80.0))
	movement.input_dir = Vector2(0, 1)
	await _tick(40)
	var peak := 0.0
	for i in ticks:
		if body.is_on_floor():
			movement.wants_jump = true
			movement.input_dir = Vector2(0, 1)
		else:
			movement.input_dir = Vector2(-1, 0)
			var d := Vector3(body.velocity.x, 0.0, body.velocity.z)
			if d.length() > 0.01:
				d = d.normalized()
				# Aim the body so that -basis.x (the A direction) is 90 degrees
				# off the current velocity.
				body.rotation.y = atan2(-d.x, -d.z)
		await _tick(1)
		peak = maxf(peak, movement.horizontal_speed())
	return peak


func _bunnyhop() -> void:
	var start := config.move_speed
	var peak: float = await _bhop_peak(1200)

	_check(
		peak > start + 4.0,
		"a correct air-strafe gains real speed (%.2f -> %.2f)" % [start, peak]
	)
	_check(
		peak > 14.0,
		"bunnyhop reaches competent territory (peak %.2f m/s)" % peak
	)
	_check(
		peak <= config.air_soft_ceiling + 0.5,
		"soft ceiling holds (peak %.2f / ceiling %.1f)" % [peak, config.air_soft_ceiling]
	)
	_check(is_finite(body.velocity.length()), "velocity stays finite")

	# Dash spam cannot beat a good strafe run, and cannot compound.
	await _reset(Vector3(0, 0.2, -80.0))
	var dash_peak := 0.0
	for i in 600:
		movement.input_dir = Vector2(0, 1)
		movement.wants_dash = true
		movement.wants_jump = body.is_on_floor()
		await _tick(1)
		dash_peak = maxf(dash_peak, movement.horizontal_speed())
	_check(
		dash_peak <= config.dash_speed + 0.1,
		"mashing dash never compounds (peak %.2f)" % dash_peak
	)
	await _reset(Vector3(0, 0.2, 0))


## Godot runs _physics_process at a fixed rate, so movement should produce the
## same result no matter what that rate is. Run the same bot at 60 and at 120.
func _framerate_independence() -> void:
	var at_60: float = await _bhop_peak(1200)
	Engine.physics_ticks_per_second = 120
	var at_120: float = await _bhop_peak(2400)
	Engine.physics_ticks_per_second = 60
	await _reset(Vector3(0, 0.2, 0))
	var drift: float = absf(at_120 - at_60) / maxf(at_60, 0.001)
	_check(
		drift < 0.08,
		"bunnyhop result is tick-rate independent (60Hz %.2f vs 120Hz %.2f, %.1f%%)" % [
			at_60, at_120, drift * 100.0
		]
	)


## Pooled effects must never grow and must switch themselves off.
func _fx_pool() -> void:
	var fx := ImpactFx.new()
	fx.config = combat
	add_child(fx)
	await _tick(1)
	var expected := combat.tracer_pool_size + combat.impact_pool_size
	_check(fx.get_child_count() == expected, "fx pool preallocates %d nodes" % expected)

	const KINDS := [ImpactFx.Kind.WORLD, ImpactFx.Kind.ENEMY, ImpactFx.Kind.HEAD]
	for i in 300:
		fx.tracer(Vector3(0, 1, 0), Vector3(0, 1, 10))
		fx.impact(Vector3(0, 1, 10), KINDS[i % KINDS.size()])
	_check(
		fx.get_child_count() == expected,
		"300 shots allocate nothing (still %d nodes)" % fx.get_child_count()
	)
	_check(fx.is_processing(), "fx processes while effects are alive")

	await _tick(40)
	_check(not fx.is_processing(), "fx stops processing once effects expire")
	var visible_count := 0
	for child in fx.get_children():
		if (child as Node3D).visible:
			visible_count += 1
	_check(visible_count == 0, "every effect hid itself (%d still visible)" % visible_count)
	fx.queue_free()


## Damage, reaction, death, fragment cleanup and respawn.
func _dummy() -> void:
	var dummy: Node3D = load(DUMMY_SCENE).instantiate()
	# Position BEFORE add_child: _ready() captures the respawn point.
	dummy.position = Vector3(20, 0.0, 0)
	add_child(dummy)
	await _tick(10)

	var before_children := get_child_count()
	var hits := 0
	var killed := false
	while hits < 20 and not killed:
		killed = dummy.take_damage(combat.damage_body, dummy.global_position, Vector3(0, 0, -1))
		hits += 1
		await _tick(2)
	_check(killed and hits == 3, "three body shots kill the dummy (took %d)" % hits)
	_check(
		get_child_count() > before_children,
		"death spawned fragments (%d)" % (get_child_count() - before_children)
	)

	await _seconds(combat.death_fragment_lifetime + 0.5)
	_check(
		get_child_count() == before_children,
		"fragments cleaned themselves up (%d extra left)" % (get_child_count() - before_children)
	)

	await _seconds(combat.dummy_respawn_delay + 0.5)
	_check(
		dummy.take_damage(1.0, dummy.global_position, Vector3(0, 0, -1)) == false,
		"dummy respawned and takes damage again"
	)
	dummy.queue_free()


## End to end: a real player scene, a real blaster, a real trace, real kills.
## Body shots and a headshot are checked separately, through the actual weapon.
func _shooting() -> void:
	const DISTANCE := 12.0
	var target: Node3D = load(DUMMY_SCENE).instantiate()
	# Position BEFORE add_child: _ready() captures the respawn point.
	target.position = Vector3(40, 0, -DISTANCE)
	add_child(target)

	var player: Node3D = load("res://gameplay/player/player.tscn").instantiate()
	player.position = Vector3(40, 0.5, 0)
	add_child(player)
	await _tick(20)

	var camera: FirstPersonCamera = player.get_node("Head/Camera")
	var blaster: TestBlaster = player.get_node("Head/Camera/Blaster")
	var target_visual: Node3D = target.get_node("Visual")
	var zones: Array[StringName] = []
	blaster.hit_confirmed.connect(func(zone: StringName) -> void: zones.append(zone))

	# --- semi-auto: holding the trigger is not a thing, and the cooldown holds.
	blaster.try_fire()
	await _tick(2)
	_check(not blaster.ready_to_fire(), "weapon is cycling right after a shot")
	var before_spam := zones.size()
	for i in 20:
		blaster.try_fire()
		await _tick(1)
	_check(
		zones.size() == before_spam,
		"calling fire during the cooldown does nothing (%d extra)" % (zones.size() - before_spam)
	)

	# --- body shots: level aim hits the capsule, three of them kill.
	var body_shots := 1
	while body_shots < 8 and target_visual.visible:
		await _wait_ready(blaster)
		blaster.try_fire()
		body_shots += 1
		await _tick(3)
	_check(
		body_shots == 3 and not target_visual.visible,
		"three body shots kill through the real weapon (took %d)" % body_shots
	)
	_check(
		not zones.has(TestBlaster.ZONE_HEAD),
		"level aim never registered as a headshot"
	)

	# --- headshot: pitch up onto the head sphere, one shot kills.
	await _seconds(combat.dummy_respawn_delay + 0.5)
	await _tick(10)
	var head_y: float = target.global_position.y + 2.15
	var eye_y: float = camera.global_position.y
	# look() takes mouse pixels, so convert the angle we want through sensitivity.
	camera.look(Vector2(0.0, -atan2(head_y - eye_y, DISTANCE) / config.mouse_sensitivity))
	await _tick(3)
	zones.clear()
	await _wait_ready(blaster)
	blaster.try_fire()
	await _tick(3)
	_check(zones.has(TestBlaster.ZONE_HEAD), "aiming at the head registers a headshot")
	_check(not target_visual.visible, "one headshot kills the dummy")

	await _seconds(combat.hitstop_headshot + 0.2)
	_check(is_equal_approx(Engine.time_scale, 1.0), "hit stop restored time_scale")

	player.queue_free()
	target.queue_free()
	await _tick(2)


func _wait_ready(blaster: TestBlaster) -> void:
	var guard := 0
	while not blaster.ready_to_fire() and guard < 300:
		guard += 1
		await _tick(1)


# --------------------------------------------------------------------------

func _reset(pos: Vector3) -> void:
	movement.input_dir = Vector2.ZERO
	movement.wants_crouch = false
	body.rotation = Vector3.ZERO
	body.global_position = pos
	body.velocity = Vector3.ZERO
	await _tick(20)


func _tick(count := 1) -> void:
	for i in count:
		await get_tree().physics_frame


func _seconds(duration: float) -> void:
	await get_tree().create_timer(duration).timeout


func _check(ok: bool, label: String) -> void:
	_checks += 1
	var line := ("  PASS  " if ok else "  FAIL  ") + label
	print(line)
	# stdout is block-buffered when it is not a console, so mirror every result
	# to stderr as well: that is what makes progress visible during a headless
	# run instead of arriving all at once at exit.
	printerr(line)
	if not ok:
		_failures.append(label)


func _report() -> void:
	print("")
	print("%d checks, %d failed" % [_checks, _failures.size()])
	for failure in _failures:
		print("  FAILED: ", failure)
	get_tree().quit(0 if _failures.is_empty() else 1)
