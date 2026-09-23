class_name DebugHud
extends CanvasLayer

## Development-only readout. Not a UI system, not styled, not shipping.
## It reads the movement controller directly because that is exactly what it is
## for: tuning that controller.

@onready var _label: Label = $Panel/Label
@onready var crosshair: Crosshair = $Crosshair
@onready var weapon_selector: WeaponSelector = $WeaponSelector

var _movement: MovementController
var _weapons: WeaponRack
var _camera: FirstPersonCamera


func bind(movement: MovementController, weapons: WeaponRack, camera: FirstPersonCamera) -> void:
	_movement = movement
	_weapons = weapons
	_camera = camera


func _process(_delta: float) -> void:
	if _movement == null:
		return
	var speed := _movement.horizontal_speed()
	var cfg := _movement.config
	var grounded := _movement.state == MovementController.State.GROUND \
		or _movement.state == MovementController.State.SLIDE \
		or _movement.state == MovementController.State.CROUCH

	# The terms of AirAccelerate, laid out in the order the equation uses them.
	# Tuning air feel means watching add_speed and accel, not the speed number.
	var air := "-"
	if _movement.state == MovementController.State.AIR:
		if _movement.air_add_speed <= 0.0:
			air = "no room  (proj %.2f >= cap %.2f)" % [
				_movement.air_current_speed, _movement.air_wish_speed_capped
			]
		else:
			air = "+%.3f m/s  (add %.2f)" % [
				_movement.air_accel_applied, _movement.air_add_speed
			]

	_label.text = "\n".join([
		"FPS          %d" % Engine.get_frames_per_second(),
		"SPEED        %6.2f m/s%s" % [speed, "   <COLLISION>" if _movement.collided_last_tick else ""],
		"GROUNDED     %s" % ("YES" if grounded else "NO (AIRBORNE)"),
		"STATE        %s" % _movement.state_name(),
		"TRACTION     %s" % _movement.traction_state,
		"",
		"BHOP CHAIN   %d" % _movement.bhop_chain,
		"LAST HOP     %.0f ms on ground" % (_movement.last_hop_ground_time * 1000.0),
		"AIR ACCEL    %s" % air,
		"WISH         %.2f m/s  capped %.2f  proj %.2f" % [
			_movement.air_wish_speed, _movement.air_wish_speed_capped,
			_movement.air_current_speed,
		],
		"ANGLE v^wish %+6.1f deg   cam %+6.0f deg/s" % [
			_movement.air_wish_angle_deg, rad_to_deg(_movement.yaw_rate()),
		],
		"SOFT CAP     %.0f-%.0f m/s   (gain x%.2f)" % [
			cfg.bhop_soft_cap_start, cfg.bhop_soft_cap_end, _movement.soft_cap_gain,
		],
		"",
		"DASH         %s" % _dash_meter(),
		"RECHARGE     %s" % _recharge_text(),
		"WEAPON       %s" % _weapon_text(),
		"FOV          %.1f" % _camera.current_fov(),
		"",
		"LMB attack   1-4 weapon   SHIFT dash   CTRL crouch/slide   F1 hurtboxes",
	])


## Which BloodProfile is being tested, at a glance.
func _weapon_text() -> String:
	var weapon := _weapons.current()
	if weapon == null:
		return "-"
	return "[%d] %s  (%s)  %s" % [
		_weapons.current_index + 1,
		weapon.display_name,
		BloodTypes.DamageType.keys()[int(weapon.damage_type)],
		"READY" if weapon.ready_to_attack() else "CYCLING",
	]


## DASH [#][ ] - one block per charge, filled if available.
func _dash_meter() -> String:
	var out := ""
	for i in _movement.config.dash_max_charges:
		out += "[#]" if i < _movement.dash_charges else "[ ]"
	return out


func _recharge_text() -> String:
	if _movement.dash_charges >= _movement.config.dash_max_charges:
		return "full"
	return "%3d%% -> next charge" % int(_movement.dash_recharge_progress() * 100.0)
