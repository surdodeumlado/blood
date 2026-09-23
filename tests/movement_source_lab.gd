extends Node3D

## SOURCE-STYLE AIR MOVEMENT DIAGNOSTIC LAB.
##
##     godot --headless --path . res://tests/movement_source_lab.tscn
##
## Two jobs in one run, because either one alone would mislead:
##
##   1. MEASUREMENT (cases A-K, plus the turn-radius table). Deterministic, no
##      subjective input. This is what answers "do tight curves still eat
##      speed" with numbers instead of an opinion.
##
##   2. PROPERTY ASSERTIONS. The twelve Source-LIKE properties. Deliberately
##      not assertions about Source CONSTANTS: the numbers here are ours, only
##      the relationships are Valve's.
##
## It is written to run against EITHER controller, so the old air model could be
## measured before it was replaced and the two reports compared directly.
## Telemetry a controller does not expose prints as "-".
##
## Everything airborne happens high above the floor, so the air model is never
## contaminated by a landing. The two landing cases are the explicit exception.

const MOVEMENT_CONFIG := "res://data/movement/default_movement.tres"

## Air time of one real jump: 2 * jump_velocity / gravity, in physics ticks.
var jump_ticks := 43

var config: MovementConfig
var body: CharacterBody3D
var movement: MovementController

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	config = load(MOVEMENT_CONFIG)
	jump_ticks = int(round((2.0 * config.jump_velocity / config.gravity) * 60.0))
	_build_world()
	_build_player()
	_run()


func _physics_process(delta: float) -> void:
	if movement == null:
		return
	movement.step(delta)
	movement.wants_jump = false
	movement.wants_dash = false


func _build_world() -> void:
	# 2 km of floor. A 30 s chain at 25 m/s covers 750 m, and a smaller arena
	# silently truncates the bhop cases by dropping the bot off the edge - which
	# reads as "the chain ended" rather than "the floor ended".
	_add_box(Vector3(2000, 1, 2000), Vector3(0, -0.5, 0))
	# A wall, used only by the collision-vs-steering separation case.
	_add_box(Vector3(1, 8, 60), Vector3(24, 4, 0))


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
# Harness
# --------------------------------------------------------------------------

func _tick(n := 1) -> void:
	for i in n:
		await get_tree().physics_frame


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _speed() -> float:
	return _flat(body.velocity).length()


## Heading in degrees. 0 is -Z (what yaw 0 faces); positive is to the right.
func _heading(v: Vector3) -> float:
	var f := _flat(v)
	if f.length_squared() < 0.000001:
		return 0.0
	return rad_to_deg(atan2(f.x, -f.z))


func _signed_delta(from: float, to: float) -> float:
	return rad_to_deg(wrapf(deg_to_rad(to - from), -PI, PI))


## Face the body so `dir` becomes its RIGHT vector (+basis.x).
func _aim_right_along(dir: Vector3) -> void:
	body.rotation.y = atan2(-dir.z, dir.x)


## Rotate a horizontal vector about +Y. -90 degrees is a turn to the right.
func _rot_y(v: Vector3, degrees: float) -> Vector3:
	var a := deg_to_rad(degrees)
	return Vector3(v.x * cos(a) + v.z * sin(a), 0.0, -v.x * sin(a) + v.z * cos(a))


## Park the player airborne, high up, moving at `speed` along -Z, facing -Z.
func _airborne(speed: float) -> void:
	movement.input_dir = Vector2.ZERO
	movement.wants_crouch = false
	body.rotation = Vector3.ZERO
	body.global_position = Vector3(0, 60.0, 40.0)
	body.velocity = Vector3(0, 0, -speed)
	# Two settling ticks: the first re-resolves the stance to AIR, and both let
	# the sampled yaw rate forget the rotation jump this function just made.
	await _tick(2)
	body.velocity = Vector3(0, 0, -speed)


func _ground(pos := Vector3(0, 0.2, 0)) -> void:
	movement.input_dir = Vector2.ZERO
	movement.wants_crouch = false
	movement.dash_charges = config.dash_max_charges
	body.rotation = Vector3.ZERO
	body.global_position = pos
	body.velocity = Vector3.ZERO
	await _tick(20)


## Whatever of the section 24 telemetry this controller exposes.
func _telemetry() -> String:
	if not (&"air_add_speed" in movement):
		return "      telemetry: - (this controller exposes no AirAccelerate readout)"
	return ("      wish %.2f | capped %.2f | proj %.2f | add %.2f | accel %.3f | softcap x%.2f"
		% [movement.air_wish_speed, movement.air_wish_speed_capped,
			movement.air_current_speed, movement.air_add_speed,
			movement.air_accel_applied, movement.soft_cap_gain])


func _collided() -> bool:
	return body.get_slide_collision_count() > 0


func _row(name: String, v0: float, v1: float, heading: float, yaw: float) -> void:
	print("  %-32s %6.2f -> %6.2f (%+5.2f)  heading %+7.1f deg  cam %+7.1f deg/s"
		% [name, v0, v1, v1 - v0, heading, yaw])


func _check(ok: bool, label: String) -> void:
	_checks += 1
	var line := ("  PASS  " if ok else "  FAIL  ") + label
	print(line)
	printerr(line)
	if not ok:
		_failures.append(label)


func _section(title: String) -> void:
	print("")
	print("=== " + title + " ===")


# --------------------------------------------------------------------------
# Flight helper
# --------------------------------------------------------------------------

## Hold `input` for `ticks` while `driver` optionally rotates the body each tick.
func _fly(speed: float, input: Vector2, ticks: int, driver := Callable()) -> Dictionary:
	await _airborne(speed)
	var yaw0 := body.rotation.y
	var v0 := _speed()
	var lowest := v0
	var collided := false
	# ACCUMULATED heading, not endpoint-minus-start. The new model can turn more
	# than 180 degrees in a single jump at low speed, and a wrapped endpoint
	# difference reports that as a small turn the other way - which understates
	# exactly the thing this pass set out to fix.
	var turned := 0.0
	var last := _heading(body.velocity)
	for i in ticks:
		if driver.is_valid():
			driver.call(i)
		movement.input_dir = input
		await _tick(1)
		var now := _heading(body.velocity)
		turned += _signed_delta(last, now)
		last = now
		lowest = minf(lowest, _speed())
		collided = collided or _collided()
	return {
		"v0": v0, "v1": _speed(), "low": lowest,
		"heading": turned,
		"yaw_rate": rad_to_deg(wrapf(body.rotation.y - yaw0, -PI, PI)) / (float(ticks) / 60.0),
		"collided": collided,
		"telemetry": _telemetry(),
	}


## THE IDEALISED SKILLED STRAFE.
##
## Keep the lateral key pointing exactly perpendicular to the CURRENT velocity,
## which is the angle that maximises Source air gain (the speed added per tick
## peaks when the projection of velocity onto the wish direction is zero) and is
## what a good player converges on by feel.
##
## The body aim is the SAME for both sides, which is not a bug: basis.x is put
## along "right of the velocity", so D (+basis.x) curves right and A (-basis.x)
## curves left off one identical rule. That is what makes the symmetry check
## meaningful rather than two hand-tuned mirror cases.
func _perpendicular_driver(_side: float) -> Callable:
	return func(_i: int) -> void:
		var v := _flat(body.velocity)
		if v.length_squared() < 0.0001:
			return
		_aim_right_along(_rot_y(v.normalized(), -90.0))


# --------------------------------------------------------------------------
# Cases A-K
# --------------------------------------------------------------------------

func _cases() -> void:
	_section("CASES A-K  (airborne cases run one jump of air time: %d ticks)" % jump_ticks)

	var a := await _fly(9.0, Vector2(0, 1), jump_ticks)
	_row("A  9 m/s, W, camera fixed", a.v0, a.v1, a.heading, a.yaw_rate)
	print(a.telemetry)

	var b := await _fly(15.0, Vector2(0, 1), jump_ticks)
	_row("B  15 m/s, W, camera fixed", b.v0, b.v1, b.heading, b.yaw_rate)
	print(b.telemetry)

	var c := await _fly(15.0, Vector2(1, 0), jump_ticks)
	_row("C  15 m/s, D, camera fixed", c.v0, c.v1, c.heading, c.yaw_rate)
	print(c.telemetry)

	# D / E use a steady, humanly plausible camera sweep rather than the ideal.
	var sweep := func(rate: float) -> Callable:
		return func(_i: int) -> void:
			body.rotation.y -= deg_to_rad(rate) / 60.0

	var d := await _fly(15.0, Vector2(1, 0), jump_ticks, sweep.call(160.0))
	_row("D  15, D + camera right 160/s", d.v0, d.v1, d.heading, d.yaw_rate)
	print(d.telemetry)

	var e := await _fly(15.0, Vector2(1, 1), jump_ticks, sweep.call(160.0))
	_row("E  15, W+D + camera right 160/s", e.v0, e.v1, e.heading, e.yaw_rate)
	print(e.telemetry)

	var f := await _fly(20.0, Vector2(1, 0), jump_ticks, _perpendicular_driver(1.0))
	_row("F  20, tight D + right arc", f.v0, f.v1, f.heading, f.yaw_rate)
	print(f.telemetry)

	var g := await _fly(20.0, Vector2(-1, 0), jump_ticks, _perpendicular_driver(-1.0))
	_row("G  20, tight A + left arc", g.v0, g.v1, g.heading, g.yaw_rate)
	print(g.telemetry)
	_check(
		absf(absf(f.heading) - absf(g.heading)) < 4.0
			and absf((f.v1 - f.v0) - (g.v1 - g.v0)) < 0.25,
		"12. left and right are symmetric (%.1f vs %.1f deg, %+.2f vs %+.2f m/s)"
			% [f.heading, g.heading, f.v1 - f.v0, g.v1 - g.v0]
	)

	# H: a real bhop chain on the floor, strafing perpendicular in the air.
	await _ground(Vector3(0, 0.2, 120.0))
	movement.input_dir = Vector2(0, 1)
	await _tick(40)
	var chain_start := _speed()
	var peak := chain_start
	var hops := 0
	for i in 1800:
		if body.is_on_floor():
			movement.wants_jump = true
			movement.input_dir = Vector2(0, 1)
			hops += 1
		else:
			movement.input_dir = Vector2(1, 0)
			var v := _flat(body.velocity)
			if v.length() > 0.01:
				_aim_right_along(_rot_y(v.normalized(), -90.0))
		await _tick(1)
		peak = maxf(peak, _speed())
	print("  %-32s %6.2f -> %6.2f peak over %d hops in 30 s"
		% ["H  bhop chain, perfect strafe", chain_start, peak, hops])

	# H2: THE CORRIDOR ZIGZAG, which is what bhop actually looks like in play.
	#
	# H holds one endless curve, which is the theoretical maximum but is not a
	# thing anyone does in a room. This alternates sides every hop and keeps the
	# mouse moving with the key, so the heading oscillates instead of winding up.
	# It is the honest answer to "will alternating A and D down a corridor still
	# build speed" - a question the previous model answered differently, because
	# its gain came from mouse/key synchronisation rather than from geometry.
	await _ground(Vector3(0, 0.2, 120.0))
	movement.input_dir = Vector2(0, 1)
	await _tick(40)
	var zig_start := _speed()
	var zig_peak := zig_start
	var side := 1.0
	var was_airborne := false
	# AIRBORNE turn per hop only. The grounded ticks are excluded deliberately:
	# ground acceleration re-points the velocity toward where the camera is
	# looking, and the camera is parked perpendicular to the velocity by the
	# strafe driver, so including them measures the landing rather than the arc.
	var hop_turn := 0.0
	var turns: Array[float] = []
	var prev := _heading(body.velocity)
	for i in 1800:
		if body.is_on_floor():
			movement.wants_jump = true
			movement.input_dir = Vector2(0, 1)
			# Edge-triggered. Flipping on every grounded TICK silently flips
			# twice on any landing that lasts two, which turns the zigzag back
			# into one long curve and makes this case prove nothing.
			if was_airborne:
				side = -side
				turns.append(hop_turn)
				hop_turn = 0.0
			was_airborne = false
		else:
			if not was_airborne:
				prev = _heading(body.velocity)
			was_airborne = true
			movement.input_dir = Vector2(side, 0)
			var v := _flat(body.velocity)
			if v.length() > 0.01:
				_aim_right_along(_rot_y(v.normalized(), -90.0))
		await _tick(1)
		if was_airborne:
			var now := _heading(body.velocity)
			hop_turn += _signed_delta(prev, now)
			prev = now
		zig_peak = maxf(zig_peak, _speed())
	var reversals := 0
	for i in range(1, turns.size()):
		if signf(turns[i]) != signf(turns[i - 1]):
			reversals += 1
	print("  %-32s %6.2f -> %6.2f peak, %d of %d hops reversed their turn"
		% ["H2 corridor zigzag, alternating", zig_start, zig_peak,
			reversals, maxi(turns.size() - 1, 0)])
	_check(
		zig_peak > 16.0,
		"alternating A/D down a corridor still builds real speed (%.2f m/s)" % zig_peak
	)

	# I / J: the landing pair. Same approach, one re-jumps, one does not.
	var kept_jump := await _landing(true)
	var kept_stand := await _landing(false)
	print("  %-32s %6.2f -> %6.2f (%+5.2f)  traction %s"
		% ["I  land + immediate re-jump", kept_jump.v0, kept_jump.v1,
			kept_jump.v1 - kept_jump.v0, kept_jump.traction])
	print("  %-32s %6.2f -> %6.2f (%+5.2f)  traction %s"
		% ["J  land, no jump", kept_stand.v0, kept_stand.v1,
			kept_stand.v1 - kept_stand.v0, kept_stand.traction])
	_check(
		kept_jump.v1 > kept_stand.v1 + 1.0,
		"9. an immediate landing jump keeps far more than standing (%.2f vs %.2f m/s)"
			% [kept_jump.v1, kept_stand.v1]
	)
	_check(
		kept_stand.v1 < kept_stand.v0 - 0.5,
		"10. standing on the ground still receives normal friction (%.2f -> %.2f)"
			% [kept_stand.v0, kept_stand.v1]
	)

	# K: dash, then steer the dash momentum with the air model.
	#
	# Run high above the floor. Dashing off the ground and then strafing lands
	# the player mid-measurement, and ground friction then shows up as if the
	# air model had eaten the dash - which is exactly the confusion section 16
	# says must not happen.
	await _airborne(9.0)
	movement.dash_charges = config.dash_max_charges
	movement.wants_dash = true
	movement.input_dir = Vector2(0, 1)
	await _tick(1)
	var dash_peak := _speed()
	var guard := 0
	while movement.state == MovementController.State.DASH and guard < 120:
		await _tick(1)
		dash_peak = maxf(dash_peak, _speed())
		guard += 1
	var after_dash := _speed()
	var dash_h0 := _heading(body.velocity)
	for i in 20:
		movement.input_dir = Vector2(1, 0)
		var v := _flat(body.velocity)
		if v.length() > 0.01:
			_aim_right_along(_rot_y(v.normalized(), -90.0))
		await _tick(1)
	print("  %-32s peak %.2f -> exit %.2f -> +20 strafe ticks %.2f (heading %+.1f)"
		% ["K  dash into air strafe", dash_peak, after_dash, _speed(),
			_signed_delta(dash_h0, _heading(body.velocity))])
	_check(
		_speed() > after_dash - 0.3,
		"11. dash momentum survives into air control (%.2f -> %.2f)" % [after_dash, _speed()]
	)


## Carry real momentum into a landing, then either jump on the touchdown tick or
## stand. The while loop exits on the tick the body BECAME grounded, so the next
## tick is the first grounded one - exactly when a bhop has to fire.
func _landing(rejump: bool) -> Dictionary:
	await _ground(Vector3(0, 0.2, 120.0))
	movement.input_dir = Vector2(0, 1)
	await _tick(30)
	body.velocity = Vector3(0, 0, -16.0)
	movement.wants_jump = true
	await _tick(1)
	var v0 := _speed()
	var guard := 0
	while not body.is_on_floor() and guard < 300:
		movement.input_dir = Vector2(0, 1)
		await _tick(1)
		guard += 1
	movement.wants_jump = rejump
	movement.input_dir = Vector2(0, 1)
	await _tick(1)
	var traction: String = str(movement.traction_state)
	for i in 10:
		movement.input_dir = Vector2(0, 1)
		await _tick(1)
	return {"v0": v0, "v1": _speed(), "traction": traction}


# --------------------------------------------------------------------------
# Turn-radius analysis
# --------------------------------------------------------------------------

func _turn_table() -> void:
	_section("TURN RADIUS  (one jump of air time, ideal skilled strafe, per side)")
	print("  %8s %10s %12s %14s %10s" % ["speed", "side", "heading", "final speed", "delta"])
	for speed in [12.0, 16.0, 20.0, 24.0]:
		for side in [1.0, -1.0]:
			var r := await _fly(
				speed, Vector2(side, 0), jump_ticks, _perpendicular_driver(side)
			)
			print("  %8.0f %10s %8.1f deg %10.2f m/s %9.2f"
				% [speed, "D right" if side > 0.0 else "A left",
					r.heading, r.v1, r.v1 - r.v0])
			_check(
				r.v1 >= r.v0 - 0.2,
				"7. a %.0f m/s %s arc does not scale total velocity down (%.2f -> %.2f)"
					% [speed, "right" if side > 0.0 else "left", r.v0, r.v1]
			)


# --------------------------------------------------------------------------
# Source-LIKE property assertions
# --------------------------------------------------------------------------

func _properties() -> void:
	_section("SOURCE-LIKE PROPERTIES")

	# 1. No arbitrary horizontal air damping: coast with no input at all.
	var coast := await _fly(18.0, Vector2.ZERO, jump_ticks)
	_check(
		absf(coast.v1 - coast.v0) < 0.05 and not coast.collided,
		"1. no horizontal air damping with no input (%.3f -> %.3f)" % [coast.v0, coast.v1]
	)

	# 2 + 3. AirAccelerate projects with a dot product and is limited by the
	# directional add_speed. Facing along the velocity means the projection is
	# already past the cap, so nothing may be added.
	var aligned := await _fly(18.0, Vector2(0, 1), 1)
	_check(
		absf(aligned.v1 - aligned.v0) < 0.001,
		"2/3. input along the velocity adds nothing, the projection is past the cap (%+.4f)"
			% (aligned.v1 - aligned.v0)
	)

	# 5. Perpendicular means the projection is zero, so something must be added.
	await _airborne(18.0)
	_aim_right_along(_rot_y(Vector3(0, 0, -1), -90.0))
	var before := _speed()
	movement.input_dir = Vector2(1, 0)
	await _tick(1)
	var perp_gain := _speed() - before
	_check(
		perp_gain > 0.0,
		"5. a lateral key perpendicular to the velocity adds orthogonal speed (+%.4f m/s)"
			% perp_gain
	)

	# 4. Momentum is not hard-clamped to walk speed.
	var fast := await _fly(22.0, Vector2(0, 1), jump_ticks * 3)
	_check(
		fast.v1 > config.move_speed * 2.0,
		"4. holding W at speed is not clamped toward walk speed (%.2f -> %.2f, walk %.1f)"
			% [fast.v0, fast.v1, config.move_speed]
	)
	_check(
		fast.low > fast.v0 - 0.2,
		"   and it never dips below where it started (low %.2f)" % fast.low
	)

	# 6. Rotating the view changes wish_dir naturally: identical key, different
	# view, very different outcome.
	var still := await _fly(15.0, Vector2(1, 0), jump_ticks)
	var turned := await _fly(15.0, Vector2(1, 0), jump_ticks, _perpendicular_driver(1.0))
	_check(
		absf(turned.heading) > absf(still.heading) + 20.0,
		"6. coordinated view rotation bends the path much harder (%.1f vs %.1f deg)"
			% [turned.heading, still.heading]
	)
	_check(
		turned.v1 > still.v1,
		"   and the coordinated turn is the stronger technique (%.2f vs %.2f m/s)"
			% [turned.v1, still.v1]
	)

	# 8. The soft cap bends the GAIN. It must never bleed existing momentum.
	var above := await _fly(30.0, Vector2.ZERO, jump_ticks)
	_check(
		above.v1 > 29.5,
		"8. above the soft cap, existing momentum is preserved, not bled (%.2f -> %.2f)"
			% [above.v0, above.v1]
	)

	# Collision-caused loss has to be distinguishable from steering-caused loss.
	await _airborne(20.0)
	body.global_position = Vector3(18.0, 4.0, 0)
	body.velocity = Vector3(20.0, 0, 0)
	var hit := false
	var pre := _speed()
	for i in 30:
		movement.input_dir = Vector2.ZERO
		await _tick(1)
		hit = hit or _collided()
	_check(
		hit and _speed() < pre - 1.0,
		"collision removes speed, reported separately from steering (%.2f -> %.2f, hit %s)"
			% [pre, _speed(), hit]
	)


# --------------------------------------------------------------------------

func _framerate() -> void:
	_section("RENDER-RATE AND PHYSICS-TICK BEHAVIOUR")

	# Section 27's actual requirement: movement gain must not be tied to RENDER
	# frames. That is structural, not statistical - so check it structurally.
	# If step() is ever called from _process, no amount of sampling would be a
	# substitute for noticing.
	var src := FileAccess.get_file_as_string(
		"res://gameplay/movement/movement_controller.gd"
	)
	var player := FileAccess.get_file_as_string("res://gameplay/player/player.gd")
	_check(
		player.contains("_physics_process") and not player.contains("_process(delta)\n\t_movement.step"),
		"movement is stepped from _physics_process, never from a render frame"
	)
	_check(
		not src.contains("get_process_delta_time")
			and not src.contains("Engine.get_frames_per_second"),
		"the controller reads no render-rate quantity at all"
	)
	var at_60 := await _fly(15.0, Vector2(1, 0), jump_ticks, _perpendicular_driver(1.0))
	Engine.physics_ticks_per_second = 120
	var at_120 := await _fly(15.0, Vector2(1, 0), jump_ticks * 2, _perpendicular_driver(1.0))
	Engine.physics_ticks_per_second = 60
	var drift: float = absf(at_120.v1 - at_60.v1) / maxf(at_60.v1, 0.001)
	var turn_drift: float = absf(at_120.heading - at_60.heading) / maxf(absf(at_60.heading), 0.001)
	print("  60 Hz -> %.3f m/s %+.1f deg   |   120 Hz -> %.3f m/s %+.1f deg   drift %.2f%%"
		% [at_60.v1, at_60.heading, at_120.v1, at_120.heading, drift * 100.0])
	print("  accumulated turn over the same wall-clock time differs by %.0f%%"
		% (turn_drift * 100.0))
	_check(
		drift < 0.08,
		"speed gained over the same wall-clock time barely moves with tick rate (%.2f%%)"
			% (drift * 100.0)
	)
	# TURN AUTHORITY IS NOT ASSERTED INVARIANT, AND THAT IS NOT AN OVERSIGHT.
	#
	# Source's AirAccelerate clamps to a PER-TICK budget (add_speed), so a higher
	# tick rate buys more turning per second. It is the same reason 64-tick and
	# 128-tick CS feel different to strafe on, and reproducing it is fidelity
	# rather than a bug. Godot's physics rate is a fixed project setting, so this
	# cannot vary at runtime - but changing that setting WOULD change air feel,
	# which is worth failing loudly over rather than silently absorbing.
	_check(
		turn_drift < 1.0,
		"turn authority scales with tick rate but does not explode (%.0f%% at 2x)"
			% (turn_drift * 100.0)
	)


func _run() -> void:
	print("")
	print("MOVEMENT SOURCE LAB   walk %.1f  jump %.1f  gravity %.1f  air time %d ticks"
		% [config.move_speed, config.jump_velocity, config.gravity, jump_ticks])
	await _cases()
	await _turn_table()
	await _properties()
	await _framerate()
	_report()


func _report() -> void:
	var summary := "%d checks, %d failed" % [_checks, _failures.size()]
	print("")
	print(summary)
	printerr(summary)
	for f in _failures:
		printerr("  FAILED: ", f)
	get_tree().quit(0 if _failures.is_empty() else 1)
