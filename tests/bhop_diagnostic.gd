extends Node3D

## Isolated bunnyhop measurement rig. Not part of the smoke test: this exists to
## compare bhop behaviour against the approved build while tuning, and it runs
## in a few seconds instead of minutes.
##
##   godot --headless --path . res://tests/bhop_diagnostic.tscn

const MOVEMENT_CONFIG := "res://data/movement/default_movement.tres"

var config: MovementConfig
var body: CharacterBody3D
var movement: MovementController


func _ready() -> void:
	config = load(MOVEMENT_CONFIG)
	_add_floor()
	_build_player()
	_run()


func _physics_process(delta: float) -> void:
	if movement == null:
		return
	movement.step(delta)
	movement.wants_jump = false
	movement.wants_dash = false


func _add_floor() -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(400, 1, 400)
	cs.shape = shape
	sb.add_child(cs)
	add_child(sb)
	sb.global_position = Vector3(0, -0.5, 0)


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


## A human does not snap the view to a perfect perpendicular every tick. They
## sweep the mouse at some rate, hold keys through the landing, and look roughly
## where they are going. This bot models that, and it is the one whose numbers
## can be trusted for "does bhop feel right".
func _human(ticks: int, late: int, turn_deg: float, hold_w: bool, flip_every: int) -> float:
	await _reset()
	var peak := 0.0
	var grounded_for := 0
	var side := -1.0
	var hop := 0
	var yaw := 0.0
	for i in ticks:
		var grounded := body.is_on_floor()
		if grounded:
			grounded_for += 1
			if grounded_for > late:
				movement.wants_jump = true
				grounded_for = 0
				hop += 1
				if flip_every > 0 and hop % flip_every == 0:
					side = -side
		else:
			grounded_for = 0
		# The mouse sweeps continuously, on the ground and in the air alike.
		# A (side -1) is a LEFT turn, which is a RISING yaw: hence -side.
		yaw += deg_to_rad(turn_deg) * -side * (1.0 / 60.0)
		body.rotation.y = yaw
		movement.input_dir = Vector2(side, 1.0 if hold_w else 0.0).normalized()
		await _tick()
		peak = maxf(peak, movement.horizontal_speed())
	return peak


## The actual playtest scenario: from a standstill, no dash, each hop turns a
## FINITE amount toward where you want to go and then holds - alternating sides,
## like bunnyhopping down a corridor. Returns speed after `hops` hops, because
## "it barely moves" is about how fast it builds, not about an eventual peak.
func _finite_turn(hops: int, turn_per_hop: float, hold_w: bool, alternate: bool) -> float:
	await _reset()
	# Walk up to normal speed first, exactly like a player would.
	movement.input_dir = Vector2(0, 1)
	await _tick(40)

	const TURN_RATE := 120.0
	var side := -1.0
	var yaw := 0.0
	var turned := 0.0
	var hop := 0
	var was_grounded := true
	var guard := 0
	while hop < hops and guard < 4000:
		guard += 1
		var grounded := body.is_on_floor()
		if grounded:
			movement.wants_jump = true
		# A fresh hop: reset the turn allowance and, if alternating, swap sides.
		if grounded and not was_grounded:
			hop += 1
			turned = 0.0
			if alternate:
				side = -side
		# Turn only until this hop's allowance is spent, then hold the view still.
		if turned < turn_per_hop:
			var step := TURN_RATE / 60.0
			# A (side -1) is a LEFT turn, which is a RISING yaw: hence -side.
			yaw += deg_to_rad(step) * -side
			turned += step
			body.rotation.y = yaw
		movement.input_dir = Vector2(side, 1.0 if hold_w else 0.0).normalized()
		was_grounded = grounded
		await _tick()
	return movement.horizontal_speed()


func _sweep(label: String) -> void:
	print("  %s" % label)
	for turn in [120.0, 200.0, 280.0, 360.0]:
		var a: float = await _human(900, 1, turn, true, 0)
		var b: float = await _human(900, 1, turn, false, 0)
		var c: float = await _human(900, 1, turn, true, 6)
		print("    turn %3.0f deg/s   W+A %5.2f   A only %5.2f   W+A alternating %5.2f"
			% [turn, a, b, c])


func _run() -> void:
	# The permanent baseline. Every line here is a target from the design brief,
	# so a future change that breaks one of them shows up immediately.
	print("")
	print("=== BHOP BASELINE  (strafe accel %.1f, sync rate %.0f deg/s, lateral eff %.2f,"
		% [config.air_strafe_acceleration, config.air_strafe_sync_yaw_rate,
			config.air_strafe_lateral_efficiency])
	print("     air control %.0f deg/s, lateral bonus %.2f) ==="
		% [config.air_control_turn_rate, config.air_control_lateral_bonus])
	print("  start speed                                 : %5.2f m/s" % config.move_speed)
	for turn in [45.0, 70.0, 110.0]:
		var same: float = await _finite_turn(6, turn, true, false)
		var alt: float = await _finite_turn(6, turn, true, true)
		var alt_a: float = await _finite_turn(6, turn, false, true)
		print("  %3.0f deg/hop x6 | W+A same %5.2f | W+A alt %5.2f | A-only alt %5.2f"
			% [turn, same, alt, alt_a])
	var long_chain: float = await _finite_turn(20, 70.0, true, true)
	print("  long chain, 20 hops alternating             : %5.2f m/s" % long_chain)
	var ceiling: float = await _human(1400, 1, 150.0, true, 0)
	print("  sustained perfect strafe (soft cap probe)   : %5.2f m/s" % ceiling)
	var cheat: float = await _no_turn_hold(300)
	print("  HOLD A, NO CAMERA TURN (must be ~0)         : %+5.2f m/s gained" % cheat)
	var turn_only: float = await _turn_no_key(300)
	print("  TURN CAMERA, NO LATERAL KEY (must be ~0)    : %+5.2f m/s gained" % turn_only)
	var wrong: float = await _wrong_way(300)
	print("  A + turning RIGHT (wrong way, must be ~0)   : %+5.2f m/s gained" % wrong)
	var carve: float = await _ground_carve(400)
	print("  GROUND CARVING, never jumps (must be ~0)    : %+5.2f m/s gained" % carve)


## Walking on flat ground, never jumping, holding a strafe key and sweeping the
## view. Bunnyhop gain is AIR tech: this must pay nothing at all.
func _ground_carve(ticks: int) -> float:
	await _reset()
	movement.input_dir = Vector2(0, 1)
	await _tick(40)
	var before := movement.horizontal_speed()
	var peak := before
	var yaw := 0.0
	var airborne_ticks := 0
	for i in ticks:
		if not body.is_on_floor():
			airborne_ticks += 1
		yaw += deg_to_rad(150.0) / 60.0
		body.rotation.y = yaw
		movement.input_dir = Vector2(-1, 1).normalized()
		await _tick()
		peak = maxf(peak, movement.horizontal_speed())
	if airborne_ticks > 0:
		print("    (left the ground for %d of %d ticks)" % [airborne_ticks, ticks])
	return peak - before
	print("")
	get_tree().quit()


## Camera sweeping but no strafe key: must not pay.
func _turn_no_key(ticks: int) -> float:
	return await _cheat_probe(ticks, Vector2(0, 1), 150.0)


## Holding A while turning the wrong way: must not pay.
func _wrong_way(ticks: int) -> float:
	return await _cheat_probe(ticks, Vector2(-1, 1).normalized(), -150.0)


func _cheat_probe(ticks: int, input: Vector2, turn_deg: float) -> float:
	await _reset()
	movement.input_dir = Vector2(0, 1)
	await _tick(40)
	var before := movement.horizontal_speed()
	var peak := before
	var yaw := 0.0
	for i in ticks:
		if body.is_on_floor():
			movement.wants_jump = true
		yaw += deg_to_rad(turn_deg) / 60.0
		body.rotation.y = yaw
		movement.input_dir = input
		await _tick()
		peak = maxf(peak, movement.horizontal_speed())
	return peak - before


## The approved invariant that must NOT break: holding a strafe key with the
## view locked is worth almost nothing. Returns the speed gained.
func _no_turn_hold(ticks: int) -> float:
	await _reset()
	movement.input_dir = Vector2(0, 1)
	await _tick(40)
	var before := movement.horizontal_speed()
	var peak := before
	for i in ticks:
		if body.is_on_floor():
			movement.wants_jump = true
		movement.input_dir = Vector2(-1, 0)
		await _tick()
		peak = maxf(peak, movement.horizontal_speed())
	return peak - before


## Start from a standstill, walk, then hop. `late` ticks are spent standing on
## the ground before each jump, which is what a human actually does.
## `alternate` flips the strafe side every few hops.
func _from_rest(ticks: int, late: int, alternate: bool) -> float:
	await _reset()
	var peak := 0.0
	var grounded_for := 0
	var side := -1.0
	var hop := 0
	for i in ticks:
		if body.is_on_floor():
			grounded_for += 1
			movement.input_dir = Vector2(0, 1)
			if grounded_for > late:
				movement.wants_jump = true
				grounded_for = 0
				hop += 1
				if alternate and hop % 4 == 0:
					side = -side
		else:
			grounded_for = 0
			var strafe := Vector2(side, 0)
			movement.input_dir = strafe
			_aim_wish_across_velocity(strafe, side)
		await _tick()
		peak = maxf(peak, movement.horizontal_speed())
	return peak


## W held the whole time plus a strafe key, turning with it - the case the
## playtest says stopped producing gain.
func _w_plus_strafe(ticks: int) -> float:
	await _reset()
	var peak := 0.0
	var side := -1.0
	var hop := 0
	for i in ticks:
		if body.is_on_floor():
			movement.wants_jump = true
			hop += 1
			if hop % 5 == 0:
				side = -side
		var wasd := Vector2(side, 1).normalized()
		movement.input_dir = wasd
		if not body.is_on_floor():
			_aim_wish_across_velocity(wasd, side)
		await _tick()
		peak = maxf(peak, movement.horizontal_speed())
	return peak


## Turn the body so that whatever the player is actually holding ends up
## pointing across the current velocity - which is what the mouse is for.
##
## For a body yaw of psi and an input angle alpha, the world wish direction is
## (cos(alpha+psi), 0, -sin(alpha+psi)). Solving that for the yaw which puts the
## wish direction on a chosen target lets this work for pure A/D AND for W+A/D,
## instead of only aiming correctly for a pure strafe.
func _aim_wish_across_velocity(input: Vector2, side: float) -> void:
	var d := Vector3(body.velocity.x, 0.0, body.velocity.z)
	if d.length() < 0.01 or input == Vector2.ZERO:
		return
	d = d.normalized()
	# Velocity rotated 90 degrees: left for A, right for D.
	var target := Vector3(d.z, 0.0, -d.x) if side < 0.0 else Vector3(-d.z, 0.0, d.x)
	body.rotation.y = atan2(-target.z, target.x) - atan2(input.y, input.x)


func _reset() -> void:
	movement.input_dir = Vector2.ZERO
	movement.wants_crouch = false
	movement.dash_charges = config.dash_max_charges
	body.rotation = Vector3.ZERO
	body.global_position = Vector3(0, 0.3, 0)
	body.velocity = Vector3.ZERO
	await _tick(25)


func _tick(count := 1) -> void:
	for i in count:
		await get_tree().physics_frame
