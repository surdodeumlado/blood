class_name MovementController
extends Node

## All of the prototype movement lives here. It is driven by the player script:
## the player fills the input fields once per physics tick and calls step().
## Everything is frame-rate independent and runs in _physics_process.
##
## Air model, in two deliberately separate terms (see docs/MOVEMENT.md):
##   1. air_acceleration  - baseline control, can never exceed move_speed.
##   2. air_strafe_*      - the skill term, gated by air_speed_cap.
## Term 1 is why walking is enough. Term 2 is why mastery dominates.

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
var strafe_gain := 0.0         ## m/s the strafe term added last tick

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


func step(delta: float) -> void:
	var grounded := _body.is_on_floor()
	_tick_timers(delta, grounded)

	if wants_dash and _can_dash(grounded):
		_start_dash(grounded)

	strafe_gain = 0.0
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
	_detect_landing(fall_speed)


func horizontal_speed() -> float:
	return _horizontal(_body.velocity).length()


func state_name() -> String:
	return STATE_NAMES[state]


func dash_ready() -> bool:
	return _dash_cooldown <= 0.0


func dash_cooldown_left() -> float:
	return _dash_cooldown


## 1.0 = strafing gains full strength, 0.0 = at or past the soft ceiling.
func soft_ceiling_falloff(speed: float) -> float:
	if speed <= config.air_falloff_start:
		return 1.0
	if speed >= config.air_soft_ceiling:
		return 0.0
	var t := inverse_lerp(config.air_falloff_start, config.air_soft_ceiling, speed)
	return pow(1.0 - t, config.air_falloff_exponent)


# --------------------------------------------------------------------------
# Timers
# --------------------------------------------------------------------------

func _tick_timers(delta: float, grounded: bool) -> void:
	_dash_cooldown = maxf(_dash_cooldown - delta, 0.0)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)

	if grounded:
		_coyote = config.coyote_time
		_air_dashes = 0
		_ground_time += delta
	else:
		_coyote = maxf(_coyote - delta, 0.0)
		_ground_time = 0.0
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
	if not hopping:
		_apply_friction(delta, wish_dir, wish_speed)
	_accelerate(delta, wish_dir, wish_speed, config.ground_acceleration)


func _air_physics(delta: float) -> void:
	var wish_dir := _wish_dir()
	if wish_dir == Vector3.ZERO:
		return
	# Term 1: baseline control. Below move_speed it accelerates normally, so the
	# air feels ordinary at ordinary speeds. Above move_speed it degrades into
	# pure redirection, which is why holding a strafe key cannot manufacture
	# speed the way it would in a naive Quake port.
	if horizontal_speed() <= config.move_speed:
		_accelerate(delta, wish_dir, config.move_speed, config.air_acceleration)
	else:
		_air_redirect(delta, wish_dir)
	# Term 2: the technique.
	_air_strafe(delta, wish_dir)


func _apply_friction(delta: float, wish_dir: Vector3, wish_speed: float) -> void:
	var vel := _horizontal(_body.velocity)
	var speed := vel.length()
	if speed < 0.01:
		_set_horizontal(Vector3.ZERO)
		return

	var drop := 0.0
	if wish_dir == Vector3.ZERO:
		drop = config.ground_deceleration * delta
	elif speed > wish_speed:
		# Holding input while over the base speed: bleed the surplus gently so
		# dash / slide / bhop momentum survives a while instead of snapping away.
		drop = config.momentum_friction * delta
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


## Speed-preserving turn toward the input direction, limited to air_turn_rate.
## Rotates the velocity; never lengthens it. This is control, not gain.
func _air_redirect(delta: float, wish_dir: Vector3) -> void:
	var vel := _horizontal(_body.velocity)
	if vel.length_squared() < 0.0001:
		return
	var current := Vector2(vel.x, vel.z)
	var target := Vector2(wish_dir.x, wish_dir.z)
	var max_turn := deg_to_rad(config.air_turn_rate) * delta
	var turned := current.rotated(clampf(current.angle_to(target), -max_turn, max_turn))
	_set_horizontal(Vector3(turned.x, 0.0, turned.y))


## The air-strafe term. Identical in shape to _accelerate, but the wish speed is
## air_speed_cap (about 1 m/s) instead of move_speed. Consequences:
##
##   - Holding W at speed: velocity is already aligned, dot >> cap, zero gain.
##   - Holding A without turning: the velocity rotates toward A, dot crosses the
##     cap after two or three ticks, gain stops. Holding a key is worth nothing.
##   - Holding A while turning the view at the matching rate: the wish direction
##     stays just ahead of the velocity, dot stays under the cap, and speed is
##     added every tick. That is the technique.
##
## Gain is scaled by the soft-ceiling falloff, so it fades out smoothly instead
## of being clamped.
func _air_strafe(delta: float, wish_dir: Vector3) -> void:
	var vel := _horizontal(_body.velocity)
	var add_speed := config.air_speed_cap - vel.dot(wish_dir)
	if add_speed <= 0.0:
		return
	var gain := minf(config.air_strafe_acceleration * delta, add_speed)
	gain *= soft_ceiling_falloff(vel.length())
	if gain <= 0.0:
		return
	var before := vel.length()
	_set_horizontal(vel + wish_dir * gain)
	strafe_gain = horizontal_speed() - before


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

func _can_dash(grounded: bool) -> bool:
	if state == State.DASH or _dash_cooldown > 0.0:
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

	var speed := maxf(vel.length() - config.slide_friction * delta, 0.0)
	if speed <= 0.01:
		_set_horizontal(Vector3.ZERO)
		return

	var dir := vel.normalized()
	var wish_dir := _wish_dir()
	if wish_dir != Vector3.ZERO:
		# Steering blends direction only; speed is carried over untouched.
		dir = (dir + wish_dir * config.slide_steer_acceleration * delta).normalized()
	_set_horizontal(dir * speed)


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func _apply_limits(delta: float) -> void:
	var vel := _horizontal(_body.velocity)
	var speed := vel.length()

	# Above the soft ceiling in the air (a dash got you there, or a slope), bleed
	# back down to it gently rather than clamping.
	if speed > config.air_soft_ceiling and state != State.DASH and not _body.is_on_floor():
		speed = maxf(speed - config.overspeed_drag * delta, config.air_soft_ceiling)
		vel = vel.normalized() * speed
		_set_horizontal(vel)

	# Safety net only. Sits far above the soft ceiling; hitting it means a bug.
	if speed > config.safety_speed_limit:
		_set_horizontal(vel * (config.safety_speed_limit / speed))

	_body.velocity.y = maxf(_body.velocity.y, -config.max_fall_speed)


func _wish_dir() -> Vector3:
	if input_dir == Vector2.ZERO:
		return Vector3.ZERO
	var basis := _body.global_transform.basis
	var dir := basis.x * input_dir.x - basis.z * input_dir.y
	dir.y = 0.0
	return dir.normalized() if dir.length_squared() > 0.0001 else Vector3.ZERO


func _forward() -> Vector3:
	var dir := -_body.global_transform.basis.z
	dir.y = 0.0
	return dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD


func _horizontal(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _set_horizontal(v: Vector3) -> void:
	_body.velocity.x = v.x
	_body.velocity.z = v.z
