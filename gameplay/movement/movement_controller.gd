class_name MovementController
extends Node

## All of the prototype movement lives here. It is driven by the player script:
## the player fills the input fields once per physics tick and calls step().
## Everything is frame-rate independent and runs in _physics_process.
##
## AIR MODEL: Source CGameMovement, not a heuristic (see docs/MOVEMENT.md).
##
## ONE term, _air_accelerate, derived from Source SDK 2013's AirAccelerate. It
## adds acceleration along the wish direction and nothing else: it never rotates
## the velocity, never damps it, never reads the mouse and has no idea whether
## the key held is W or D. Turning and gaining speed are the same act, which is
## why there is no longer a steering term and a gain term to keep in balance.
##
## This replaced a model with a 120 deg/s turn-rate cap and a separate
## camera-sync gain rule. The lab measured that model turning exactly 86 degrees
## per jump at 12, 16, 20 AND 24 m/s, with the camera making no difference -
## which is what "tight curves feel horrible" was.

signal jumped(hop_chain: int)
signal landed(impact_speed: float)
signal dashed()
signal slide_started()
signal slide_ended()

enum State { GROUND, AIR, DASH, SLIDE, CROUCH }

const STATE_NAMES := {
	State.GROUND: "GROUND",
	State.AIR: "AIR",
	State.DASH: "DASH",
	State.SLIDE: "SLIDE",
	State.CROUCH: "CROUCH",
}

@export var config: MovementConfig

# --- Input, written by the player script every physics tick. ---
var input_dir := Vector2.ZERO  ## x = strafe, y = forward
var wants_jump := false        ## just_pressed
var wants_dash := false        ## just_pressed
var wants_crouch := false      ## held

var state: State = State.GROUND

# --- Readouts for the debug HUD. ---
var bhop_chain := 0            ## consecutive clean hops
var last_hop_ground_time := 0.0  ## seconds spent grounded before the last jump
var traction_state: StringName = &"AIR"  ## which friction regime ran last tick
var dash_charges := 0

## AIRACCELERATE READOUT, one tick behind nothing: these are written by
## _air_accelerate every airborne tick and read by the debug HUD and the
## movement lab. They exist so air feel can be tuned by looking at the actual
## terms of the equation instead of guessing from the speed number.
var air_wish_speed := 0.0          ## |wish velocity|, after the move_speed clamp
var air_wish_speed_capped := 0.0   ## min(above, air_wish_speed_cap) - Source's wishspd
var air_current_speed := 0.0       ## velocity . wish_dir, the PROJECTION
var air_add_speed := 0.0           ## how much room is left along wish_dir
var air_accel_applied := 0.0       ## m/s actually added this tick
var air_wish_angle_deg := 0.0      ## angle between velocity and wish_dir
var soft_cap_gain := 1.0           ## fraction of a speed increase let through
var collided_last_tick := false    ## so collision loss is never read as air loss

var _body: CharacterBody3D
var _collider: CollisionShape3D
var _capsule: CapsuleShape3D
var _head: Node3D

var _height := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _ground_time := 0.0
var _airborne_since_jump := false
var _prev_grounded := true
var _dash_time := 0.0
var _dash_cooldown := 0.0
var _dash_dir := Vector3.FORWARD
var _dash_speed := 0.0
var _air_dashes := 0
var _dash_recharge := 0.0
var _landing_grace := 0.0
## Signed yaw rate in rad/s, sampled from the body each tick. TELEMETRY ONLY.
##
## It used to be half of the strafe rule: gain was paid out for turning the
## mouse in the same direction as the held key. Nothing reads it for physics any
## more, and nothing should - section 28 is explicit that the mouse must reach
## movement only by moving the camera, which moves the wish direction. It stays
## because it is genuinely useful on the debug HUD while tuning.
var _yaw_rate := 0.0
var _prev_yaw := 0.0

# Reused every frame so the stand-up clearance test allocates nothing.
var _stand_query: PhysicsShapeQueryParameters3D


func setup(body: CharacterBody3D, collider: CollisionShape3D, head: Node3D) -> void:
	_body = body
	_collider = collider
	_head = head

	# Own the capsule outright so config is the only source of truth for size.
	_capsule = CapsuleShape3D.new()
	_capsule.radius = config.capsule_radius
	_capsule.height = config.stand_height
	_collider.shape = _capsule
	_height = config.stand_height
	_apply_height()

	var stand_shape := CapsuleShape3D.new()
	# Slightly thinner than the real capsule so hugging a wall never blocks standing.
	stand_shape.radius = maxf(config.capsule_radius - 0.02, 0.05)
	stand_shape.height = config.stand_height
	_stand_query = PhysicsShapeQueryParameters3D.new()
	_stand_query.shape = stand_shape
	_stand_query.collide_with_areas = false
	_stand_query.collide_with_bodies = true
	_stand_query.exclude = [_body.get_rid()]
	_stand_query.collision_mask = _body.collision_mask

	dash_charges = config.dash_max_charges
	_prev_yaw = _body.rotation.y


func step(delta: float) -> void:
	var grounded := _body.is_on_floor()
	_sample_yaw_rate(delta)
	_tick_timers(delta, grounded)

	if wants_dash and _can_dash(grounded):
		_start_dash(grounded)

	if state == State.DASH:
		_dash_physics()
	else:
		_apply_gravity(delta)
		_update_stance(grounded)
		# Knowing a jump fires THIS tick lets ground friction be skipped, which
		# is the whole of bunnyhop: land and jump on the same tick and you keep
		# everything; be late and every extra tick costs momentum_friction.
		var hopping := _jump_ready()
		if state == State.SLIDE:
			_slide_physics(delta)
		elif grounded:
			_ground_physics(delta, hopping)
		else:
			_air_physics(delta)

	_try_jump()
	_apply_limits(delta)
	_update_height(delta)

	var fall_speed := -_body.velocity.y
	_body.move_and_slide()
	# Section 16: geometry is allowed to remove speed, steering is not. Recording
	# it here is what lets the HUD and the lab tell the two apart instead of
	# blaming the air model for a wall.
	collided_last_tick = _body.get_slide_collision_count() > 0
	_detect_landing(fall_speed)


## Yaw is wrapped so a wrap-around never reads as an enormous turn.
func _sample_yaw_rate(delta: float) -> void:
	var yaw := _body.rotation.y
	_yaw_rate = wrapf(yaw - _prev_yaw, -PI, PI) / maxf(delta, 0.0001)
	_prev_yaw = yaw


## Signed, rad/s. Positive is a left turn.
func yaw_rate() -> float:
	return _yaw_rate


func horizontal_speed() -> float:
	return _horizontal(_body.velocity).length()


func state_name() -> String:
	return STATE_NAMES[state]


func dash_ready() -> bool:
	return dash_charges > 0 and _dash_cooldown <= 0.0


## How much of a would-be SPEED INCREASE the soft cap lets through at `speed`.
## 1.0 below the cap region, bhop_soft_cap_min_gain at and above the top of it.
## Smoothstep so there is no edge the player can feel.
func soft_cap_gain_scale(speed: float) -> float:
	if speed <= config.bhop_soft_cap_start:
		return 1.0
	if speed >= config.bhop_soft_cap_end:
		return config.bhop_soft_cap_min_gain
	var t := smoothstep(config.bhop_soft_cap_start, config.bhop_soft_cap_end, speed)
	return lerpf(1.0, config.bhop_soft_cap_min_gain, t)


# --------------------------------------------------------------------------
# Timers
# --------------------------------------------------------------------------

func _tick_timers(delta: float, grounded: bool) -> void:
	_dash_cooldown = maxf(_dash_cooldown - delta, 0.0)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	_landing_grace = maxf(_landing_grace - delta, 0.0)
	_tick_dash_charges(delta)

	if not grounded:
		traction_state = &"AIR"

	if grounded:
		_coyote = config.coyote_time
		_air_dashes = 0
		_ground_time += delta
	else:
		_coyote = maxf(_coyote - delta, 0.0)
		_ground_time = 0.0
		_landing_grace = 0.0
		_airborne_since_jump = true

	if wants_jump:
		_jump_buffer = config.jump_buffer_time

	if state == State.DASH:
		_dash_time -= delta
		if _dash_time <= 0.0:
			_end_dash()


func _detect_landing(fall_speed: float) -> void:
	var grounded := _body.is_on_floor()
	if grounded and not _prev_grounded:
		_ground_time = 0.0
		_landing_grace = config.landing_traction_grace
		landed.emit(maxf(fall_speed, 0.0))
	_prev_grounded = grounded


# --------------------------------------------------------------------------
# Stance: ground / air / crouch / slide
# --------------------------------------------------------------------------

func _update_stance(grounded: bool) -> void:
	var speed := horizontal_speed()
	var was_sliding := state == State.SLIDE

	if was_sliding:
		if grounded and wants_crouch and speed >= config.slide_end_speed:
			return
		state = State.CROUCH if wants_crouch else State.GROUND

	if wants_crouch:
		# A slide can only start out of a non-slide state, so it can never be
		# re-triggered mid-slide for a free entry boost.
		if grounded and speed >= config.slide_min_speed and state != State.SLIDE:
			_start_slide(speed)
		else:
			state = State.CROUCH
	elif _can_stand():
		state = State.GROUND if grounded else State.AIR
	else:
		# Ceiling above us: stay crouched instead of expanding into geometry.
		state = State.CROUCH

	if was_sliding and state != State.SLIDE:
		slide_ended.emit()


func _can_stand() -> bool:
	if _height >= config.stand_height - 0.001:
		return true
	_stand_query.transform = Transform3D(
		Basis(), _body.global_position + Vector3.UP * (config.stand_height * 0.5)
	)
	var space := _body.get_world_3d().direct_space_state
	return space.intersect_shape(_stand_query, 1).is_empty()


func _update_height(delta: float) -> void:
	var target := config.stand_height
	if state == State.CROUCH or state == State.SLIDE:
		target = config.crouch_height
	# The capsule is never allowed to grow into geometry.
	if target > _height and not _can_stand():
		target = _height
	if is_equal_approx(_height, target):
		return
	_height = move_toward(_height, target, config.height_change_speed * delta)
	_apply_height()


func _apply_height() -> void:
	_capsule.height = _height
	_collider.position.y = _height * 0.5
	_head.position.y = maxf(_height - config.eye_offset, 0.1)


# --------------------------------------------------------------------------
# Ground / air
# --------------------------------------------------------------------------

func _apply_gravity(delta: float) -> void:
	if not _body.is_on_floor():
		_body.velocity.y -= config.gravity * delta


func _ground_physics(delta: float, hopping: bool) -> void:
	var wish_dir := _wish_dir()
	var wish_speed := config.move_speed
	if state == State.CROUCH:
		wish_speed *= config.crouch_speed_multiplier
	if hopping:
		# A jump fires this tick, so the landing is a bounce: it neither loses
		# momentum to friction nor gains any from ground acceleration.
		#
		# Skipping acceleration too matters. Friction is already skipped here, so
		# leaving acceleration on would let a player pump speed for free simply
		# by sweeping the view while grounded - the wish direction rotates, and
		# with nothing scrubbing the old heading each tick adds to a circle. Air
		# speed must be bought in the air, by the strafe rule.
		traction_state = &"HOP (bounce)"
		return
	_apply_friction(delta, wish_dir, wish_speed)

	# Ground acceleration may redirect, but it may NEVER raise total speed above
	# walking pace.
	#
	# _accelerate only caps the projection onto the wish direction, and the wish
	# direction is whatever the player is currently facing. Sweeping the view
	# while holding a strafe key therefore kept the dot under the cap forever
	# and let ground acceleration pump speed in a circle - grounded carving was
	# reaching +31 m/s with no jump involved. Bunnyhop gain is air tech; the
	# ground does not sell it.
	#
	# Incoming momentum is untouched: the ceiling is max(current, wish_speed), so
	# arriving from a hop, a slide or a dash keeps every bit of its speed and is
	# only ever bled by momentum_friction above.
	var before := _horizontal(_body.velocity).length()
	_accelerate(delta, wish_dir, wish_speed, config.ground_acceleration)
	var after := _horizontal(_body.velocity)
	var speed := after.length()
	var ceiling := maxf(before, wish_speed)
	if speed > ceiling and speed > 0.001:
		_set_horizontal(after * (ceiling / speed))


## SOURCE CGameMovement::AirMove.
##
## Build a wish VELOCITY from the view basis and the movement keys, flatten it,
## split it into a direction and a speed, clamp the speed to the player's normal
## maximum, and hand both to AirAccelerate. That is the whole of it.
##
## What is deliberately absent: any rotation of the existing velocity, any
## damping, any reading of the mouse, any distinction between W and A/D, and any
## rule about whether the camera is turning. The velocity changes heading ONLY
## because acceleration is added in the wish direction and the vectors sum.
func _air_physics(delta: float) -> void:
	var wish := _wish_velocity()
	var wish_speed := wish.length()
	if wish_speed < 0.0001:
		air_wish_speed = 0.0
		air_add_speed = 0.0
		air_accel_applied = 0.0
		return
	var wish_dir := wish / wish_speed
	# Source clamps the wish speed to the player's maximum before accelerating.
	# Godot's get_vector() already normalises the stick, so a diagonal asks for
	# exactly the same speed as a single key - which is what the clamp is for.
	wish_speed = minf(wish_speed, config.move_speed)
	_air_accelerate(delta, wish_dir, wish_speed)


## SOURCE CGameMovement::AirAccelerate.
##
##     wishspd      = min(wish_speed, air_wish_speed_cap)
##     current      = velocity . wish_dir              <- a PROJECTION
##     add_speed    = wishspd - current
##     accel_speed  = min(air_accelerate * wish_speed * dt, add_speed)
##     velocity    += wish_dir * accel_speed
##
## The asymmetry on the third line is the load-bearing part and is easy to
## "clean up" by mistake: the acceleration term uses the UNCAPPED wish speed,
## while the budget it is clamped against uses the CAPPED one. Replacing
## wish_speed with wishspd there is the classic mis-port, and it is what turns
## air strafing into a slow, mushy drift.
##
## Why this gives speed: `current` is a projection, not a magnitude. Moving fast
## forwards while wishing sideways makes it near zero, so the full add_speed is
## still available - and a vector added at ninety degrees to a velocity
## lengthens it. Nothing here multiplies anything.
func _air_accelerate(delta: float, wish_dir: Vector3, wish_speed: float) -> void:
	var vel := _horizontal(_body.velocity)
	var wishspd := minf(wish_speed, config.air_wish_speed_cap)
	var current := vel.dot(wish_dir)
	var add_speed := wishspd - current

	air_wish_speed = wish_speed
	air_wish_speed_capped = wishspd
	air_current_speed = current
	air_add_speed = add_speed
	air_accel_applied = 0.0
	air_wish_angle_deg = rad_to_deg(
		Vector2(vel.x, vel.z).angle_to(Vector2(wish_dir.x, wish_dir.z))
	) if vel.length_squared() > 0.0001 else 0.0

	if add_speed <= 0.0:
		return
	var accel_speed := minf(config.air_accelerate * wish_speed * delta, add_speed)
	air_accel_applied = accel_speed

	var accelerated := vel + wish_dir * accel_speed
	_set_horizontal(_apply_soft_cap(vel, accelerated))


## THE SOFT CAP, and the reason it is written this awkwardly.
##
## It scales the SPEED INCREASE, not the velocity. The accelerated vector keeps
## its heading exactly, and its length is walked back toward the length it had
## before - never past it.
##
## Consequences, all of which the brief asks for by name:
##   - steering authority at 26 m/s is identical to steering at 16 m/s, because
##     only the surplus length is touched and never the direction;
##   - an acceleration that SLOWS the player (wishing backwards) is left alone,
##     because there is no surplus to scale;
##   - momentum already earned is never reduced, so there is nothing here that
##     can make a tight turn cost speed.
func _apply_soft_cap(before: Vector3, after: Vector3) -> Vector3:
	var was := before.length()
	var now := after.length()
	soft_cap_gain = soft_cap_gain_scale(was)
	if now <= was or now < 0.0001:
		return after
	var allowed := was + (now - was) * soft_cap_gain
	return after * (allowed / now)


## Quake-order friction: it runs BEFORE acceleration and, at walking speed, it
## runs every grounded tick whether or not there is input. That is the traction.
## Holding a direction, friction scrubs the whole velocity and acceleration
## immediately puts it back along the wish direction, so whatever was pointing
## the old way dies fast and turning feels planted instead of slippery.
##
## Two regimes, and the split is the whole point:
##   at or below move_speed -> ground_deceleration, hard. Normal walking.
##   above move_speed       -> momentum_friction, gentle. Movement tech.
##
## The caller skips this entirely on the tick a jump fires, so a clean bhop
## landing never pays either of them.
func _apply_friction(delta: float, wish_dir: Vector3, wish_speed: float) -> void:
	var vel := _horizontal(_body.velocity)
	var speed := vel.length()
	if speed < 0.01:
		_set_horizontal(Vector3.ZERO)
		return

	var drop: float
	if speed > wish_speed:
		# Bhop / slide / dash momentum: bleed the surplus slowly so it survives
		# long enough to be chained.
		drop = config.momentum_friction * delta
		traction_state = &"MOMENTUM"
	elif wish_dir != Vector3.ZERO and _landing_grace > 0.0:
		# Mid-hop: just landed and still steering. Measured to be inert for
		# promptly-timed hops (the jump-tick skip already covers those), so this
		# only matters for a landing the player is a few ticks late on. Kept
		# because it costs nothing and makes the stated invariant explicit:
		# a landing that is part of a hop never pays walking traction.
		drop = 0.0
		traction_state = &"HOP GRACE"
	else:
		drop = config.ground_deceleration * delta
		traction_state = &"TRACTION"

	if drop <= 0.0:
		return
	var new_speed := maxf(speed - drop, 0.0)
	_set_horizontal(vel * (new_speed / speed))


## Quake-style acceleration: only ever adds speed along wish_dir, and only up to
## wish_speed measured ALONG that direction. Already moving faster than
## wish_speed forwards? Then holding forward adds nothing and takes nothing.
func _accelerate(delta: float, wish_dir: Vector3, wish_speed: float, accel: float) -> void:
	if wish_dir == Vector3.ZERO:
		return
	var vel := _horizontal(_body.velocity)
	var add_speed := wish_speed - vel.dot(wish_dir)
	if add_speed <= 0.0:
		return
	_set_horizontal(vel + wish_dir * minf(accel * delta, add_speed))


# --------------------------------------------------------------------------
# Jump
# --------------------------------------------------------------------------

func _jump_ready() -> bool:
	return _jump_buffer > 0.0 and _coyote > 0.0


func _try_jump() -> void:
	if not _jump_ready():
		return
	last_hop_ground_time = _ground_time
	# A clean hop is one taken almost immediately after landing. Chains only
	# count for display; the actual reward is the friction that was skipped.
	if _airborne_since_jump and _ground_time <= config.bhop_grace_time:
		bhop_chain += 1
	else:
		bhop_chain = 0

	_jump_buffer = 0.0
	_coyote = 0.0
	_ground_time = 0.0
	_airborne_since_jump = false
	if state == State.DASH:
		_end_dash()
	# Horizontal velocity is deliberately untouched: momentum carries through
	# every jump, including out of a slide or a dash.
	_body.velocity.y = config.jump_velocity
	if state == State.SLIDE:
		slide_ended.emit()
	state = State.AIR
	jumped.emit(bhop_chain)


# --------------------------------------------------------------------------
# Dash
# --------------------------------------------------------------------------

## One timer, one charge. Because a single accumulator is refilled and reset,
## charges can only ever complete one after another - never in parallel.
## Delta-driven, so the refill rate does not care about the tick rate.
func _tick_dash_charges(delta: float) -> void:
	if dash_charges >= config.dash_max_charges:
		_dash_recharge = 0.0
		return
	_dash_recharge += delta
	while _dash_recharge >= config.dash_charge_time and dash_charges < config.dash_max_charges:
		_dash_recharge -= config.dash_charge_time
		dash_charges += 1
	if dash_charges >= config.dash_max_charges:
		_dash_recharge = 0.0


## A kill shortens the wait for the charge already in progress. It is capped at
## the charge time, so it can finish the current charge but never spill over
## into the next one and never overshoot dash_max_charges.
func reward_kill() -> void:
	if dash_charges >= config.dash_max_charges:
		return
	_dash_recharge = minf(
		_dash_recharge + config.dash_kill_recharge_bonus, config.dash_charge_time
	)


## A headshot KILL hands back a whole charge immediately. Deliberately gated on
## the kill, not the hit: a tough enemy surviving headshots must not become an
## infinite dash farm.
func reward_headshot_kill() -> void:
	if dash_charges >= config.dash_max_charges:
		return
	dash_charges += 1
	if dash_charges >= config.dash_max_charges:
		_dash_recharge = 0.0


## 0..1 progress toward the next charge. 1.0 when the pool is already full.
func dash_recharge_progress() -> float:
	if dash_charges >= config.dash_max_charges:
		return 1.0
	return clampf(_dash_recharge / config.dash_charge_time, 0.0, 1.0)


func _can_dash(grounded: bool) -> bool:
	if state == State.DASH or _dash_cooldown > 0.0:
		return false
	if dash_charges <= 0:
		return false
	if not grounded and _air_dashes >= config.air_dash_limit:
		return false
	return true


func _start_dash(grounded: bool) -> void:
	var dir := _wish_dir()
	if dir == Vector3.ZERO:
		dir = _forward()
	_dash_dir = dir
	# max(), not +=. Dashing never stacks on top of itself, but it also never
	# punishes a player who was already faster than the dash.
	_dash_speed = minf(maxf(config.dash_speed, horizontal_speed()), config.safety_speed_limit)
	_dash_time = config.dash_duration
	dash_charges -= 1
	if state == State.SLIDE:
		slide_ended.emit()
	state = State.DASH
	if not grounded:
		_air_dashes += 1
	_dash_physics()
	dashed.emit()


func _dash_physics() -> void:
	_set_horizontal(_dash_dir * _dash_speed)
	# Zeroing vertical velocity is what makes a mistimed air dash cost a hop.
	_body.velocity.y = 0.0


func _end_dash() -> void:
	_set_horizontal(_horizontal(_body.velocity) * config.dash_exit_speed_multiplier)
	_dash_cooldown = config.dash_cooldown
	state = State.AIR  # Re-resolved by _update_stance on the next tick.


# --------------------------------------------------------------------------
# Slide
# --------------------------------------------------------------------------

func _start_slide(speed: float) -> void:
	state = State.SLIDE
	# max(), never an add: repeatedly entering slides cannot stack speed.
	var entry := maxf(speed, config.move_speed * config.slide_entry_speed_multiplier)
	var vel := _horizontal(_body.velocity)
	if vel.length() > 0.01:
		_set_horizontal(vel.normalized() * entry)
	slide_started.emit()


func _slide_physics(delta: float) -> void:
	var vel := _horizontal(_body.velocity)

	# Slopes accelerate the slide. The horizontal part of a floor normal points
	# straight downhill.
	var normal := _body.get_floor_normal()
	var downhill := Vector3(normal.x, 0.0, normal.z)
	if downhill.length_squared() > 0.0001:
		vel += downhill * config.slide_slope_acceleration * delta

	# S is a brake. It only ever removes speed - it is never allowed to steer,
	# which is what used to let a slide turn around and keep its momentum.
	var drop := config.slide_friction
	if input_dir.y < -0.1:
		drop += config.slide_brake_strength * absf(input_dir.y)

	var speed := maxf(vel.length() - drop * delta, 0.0)
	if speed <= 0.01:
		_set_horizontal(Vector3.ZERO)
		return

	# Inertia plus limited steering, NOT ground movement with low friction.
	# The heading may only rotate by a bounded number of degrees per second, so
	# the direction the slide was entered with keeps dominating the trajectory
	# and no input can convert the momentum sideways in one go.
	var dir := vel.normalized()

	# A / D: the player's steering authority, and the only thing that steers.
	# W contributes nothing, which is exactly how holding it "holds the line".
	if absf(input_dir.x) > 0.1:
		var lateral := _body.global_transform.basis.x * signf(input_dir.x)
		lateral.y = 0.0
		if lateral.length_squared() > 0.0001:
			dir = _rotate_limited(
				dir,
				lateral.normalized(),
				deg_to_rad(config.slide_turn_rate) * absf(input_dir.x) * delta
			)

	# The camera curves the slide gently. Deliberately a much smaller rate: it
	# bends the line, it never snaps the velocity to where you are looking.
	if config.slide_camera_turn_rate > 0.0:
		dir = _rotate_limited(dir, _forward(), deg_to_rad(config.slide_camera_turn_rate) * delta)

	_set_horizontal(dir * speed)


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

## No horizontal air damping lives here any more.
##
## There used to be an overspeed_drag that bled anything above the soft ceiling
## back down at 6 m/s^2. It was measurably taking 30 m/s to 25.7 over a single
## jump with no input at all, which is exactly the "steering mysteriously
## deleted my speed" complaint wearing a different hat. The soft cap now bends
## the GAIN instead, so speed the player has earned is theirs until geometry or
## the ground takes it.
func _apply_limits(_delta: float) -> void:
	var vel := _horizontal(_body.velocity)
	var speed := vel.length()

	# Safety net only. Sits far above the soft cap; hitting it means a bug.
	if speed > config.safety_speed_limit:
		_set_horizontal(vel * (config.safety_speed_limit / speed))

	_body.velocity.y = maxf(_body.velocity.y, -config.max_fall_speed)


## Source's wish VELOCITY: the view basis flattened, scaled by the keys, at walk
## speed. AirMove wants the length as well as the direction, so this is the
## primary form and _wish_dir() is the normalised view of it.
##
## The vertical component is dropped BEFORE normalising, which is why looking at
## the sky does not shorten the wish vector or bend it upwards. Pitch has no
## effect on movement at all, in the air or on the ground.
func _wish_velocity() -> Vector3:
	if input_dir == Vector2.ZERO:
		return Vector3.ZERO
	var basis := _body.global_transform.basis
	var forward := -basis.z
	var right := basis.x
	forward.y = 0.0
	right.y = 0.0
	if forward.length_squared() < 0.0001 or right.length_squared() < 0.0001:
		return Vector3.ZERO
	var wish := right.normalized() * input_dir.x + forward.normalized() * input_dir.y
	return wish * config.move_speed


func _wish_dir() -> Vector3:
	var wish := _wish_velocity()
	return wish.normalized() if wish.length_squared() > 0.0001 else Vector3.ZERO


func _forward() -> Vector3:
	var dir := -_body.global_transform.basis.z
	dir.y = 0.0
	return dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD


## Rotates `from` toward `to` by at most `max_angle` radians, on the XZ plane,
## preserving magnitude. The hard per-tick angle cap is what turns steering into
## a rate rather than an instant redirect.
func _rotate_limited(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	if a.length_squared() < 0.0001 or b.length_squared() < 0.0001:
		return from
	var rotated := a.rotated(clampf(a.angle_to(b), -max_angle, max_angle))
	return Vector3(rotated.x, 0.0, rotated.y)


func _horizontal(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _set_horizontal(v: Vector3) -> void:
	_body.velocity.x = v.x
	_body.velocity.z = v.z
