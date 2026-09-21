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
	var falloff := _movement.soft_ceiling_falloff(speed)
	var grounded := _movement.state == MovementController.State.GROUND \
		or _movement.state == MovementController.State.SLIDE \
		or _movement.state == MovementController.State.CROUCH

	var strafe := "-"
	if _movement.strafe_gain > 0.0005:
		strafe = "GAINING  +%.3f m/s" % _movement.strafe_gain
	elif _movement.state == MovementController.State.AIR:
		strafe = "no gain (aligned or capped)"

	_label.text = "\n".join([
		"FPS          %d" % Engine.get_frames_per_second(),
		"SPEED        %6.2f m/s" % speed,
		"GROUNDED     %s" % ("YES" if grounded else "NO (AIRBORNE)"),
		"STATE        %s" % _movement.state_name(),
		"TRACTION     %s" % _movement.traction_state,
		"",
		"BHOP CHAIN   %d" % _movement.bhop_chain,
		"LAST HOP     %.0f ms on ground" % (_movement.last_hop_ground_time * 1000.0),
		"AIR STRAFE   %s" % strafe,
		"SOFT CEIL    %.1f m/s   (gain x%.2f)" % [cfg.air_soft_ceiling, falloff],
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
