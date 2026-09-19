class_name FirstPersonCamera
extends Camera3D

## First person camera: pitch lives here, yaw lives on the body. Also owns the
## speed-driven FOV and a small additive weapon recoil.
##
## Recoil is kept separate from the aim pitch so that it never steals the
## player's aim: the look angle is authoritative and recoil is a decaying offset
## on top of it. No head bob, no sway - the movement is already the camera
## motion and anything more makes this nauseating at 25 m/s.

var _config: MovementConfig
var _yaw_target: Node3D
var _pitch := 0.0
var _recoil := Vector2.ZERO
var _recoil_recovery := 14.0


func setup(config: MovementConfig, yaw_target: Node3D) -> void:
	_config = config
	_yaw_target = yaw_target
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


func update(horizontal_speed: float, delta: float) -> void:
	var decay := 1.0 - exp(-_recoil_recovery * delta)
	_recoil = _recoil.lerp(Vector2.ZERO, decay)
	rotation.x = _pitch + _recoil.x
	rotation.y = _recoil.y

	# Frame-rate independent easing toward the speed-mapped FOV: never snaps.
	var t := clampf(
		inverse_lerp(_config.fov_speed_start, _config.fov_speed_full, horizontal_speed), 0.0, 1.0
	)
	var target := lerpf(_config.fov_base, _config.fov_max, t)
	fov = lerpf(fov, target, 1.0 - exp(-_config.fov_lerp_speed * delta))
