class_name FirstPersonCamera
extends Camera3D

## First person camera: pitch lives here, yaw lives on the body. Also owns the
## composed FOV and a small additive weapon recoil.
##
## Recoil is kept separate from the aim pitch so that it never steals the
## player's aim: the look angle is authoritative and recoil is a decaying offset
## on top of it. No head bob, no sway - the movement is already the camera
## motion and anything more makes this nauseating at 25 m/s.
##
## FOV is composed in ONE place from three independent parts:
##
##     fov = speed component + dash accent + hit pulse      (clamped)
##
## Each accent is written with max(), never +=, so repeated hits cannot stack,
## and the total is clamped to fov_absolute_max, so two effects firing at once
## cannot fight each other or run away into a fisheye.

var _config: MovementConfig
var _yaw_target: Node3D
var _pitch := 0.0
var _recoil := Vector2.ZERO
var _recoil_recovery := 14.0

var _speed_fov := 90.0
var _dash_accent := 0.0
var _hit_pulse := 0.0


func setup(config: MovementConfig, yaw_target: Node3D) -> void:
	_config = config
	_yaw_target = yaw_target
	_speed_fov = config.fov_base
	fov = config.fov_base


func set_recoil_recovery(recovery: float) -> void:
	_recoil_recovery = recovery


func look(relative: Vector2) -> void:
	_yaw_target.rotate_y(-relative.x * _config.mouse_sensitivity)
	var limit := deg_to_rad(_config.pitch_limit_degrees)
	_pitch = clampf(_pitch - relative.y * _config.mouse_sensitivity, -limit, limit)


## Degrees. Positive pitch kicks the view up.
func add_recoil(pitch_degrees: float, yaw_degrees: float) -> void:
	_recoil += Vector2(deg_to_rad(pitch_degrees), deg_to_rad(yaw_degrees))


## Short FOV kick on a confirmed hit. max(), so holding down hits cannot stack.
func pulse_fov(degrees: float) -> void:
	_hit_pulse = maxf(_hit_pulse, degrees)


## Held while dashing, then decays on its own.
func accent_dash_fov() -> void:
	_dash_accent = maxf(_dash_accent, _config.fov_dash_accent)


func current_fov() -> float:
	return fov


func update(horizontal_speed: float, delta: float) -> void:
	var decay := 1.0 - exp(-_recoil_recovery * delta)
	_recoil = _recoil.lerp(Vector2.ZERO, decay)
	rotation.x = _pitch + _recoil.x
	rotation.y = _recoil.y

	# Speed component: frame-rate independent easing, never snaps.
	var t := clampf(
		inverse_lerp(_config.fov_speed_start, _config.fov_speed_full, horizontal_speed), 0.0, 1.0
	)
	var speed_target := lerpf(_config.fov_base, _config.fov_max, t)
	_speed_fov = lerpf(_speed_fov, speed_target, 1.0 - exp(-_config.fov_lerp_speed * delta))

	# Accents always decay toward zero, so nothing can be left stuck on.
	_dash_accent = lerpf(_dash_accent, 0.0, 1.0 - exp(-_config.fov_dash_recovery * delta))
	_hit_pulse = lerpf(_hit_pulse, 0.0, 1.0 - exp(-_config.fov_pulse_recovery * delta))
	if _dash_accent < 0.01:
		_dash_accent = 0.0
	if _hit_pulse < 0.01:
		_hit_pulse = 0.0

	fov = minf(_speed_fov + _dash_accent + _hit_pulse, _config.fov_absolute_max)
