class_name DebugHud
extends CanvasLayer

## Development-only readout. Not a UI system, not styled, not shipping.
## It reads the movement controller directly because that is exactly what it is
## for: tuning that controller.

@onready var _label: Label = $Panel/Label
@onready var crosshair: Crosshair = $Crosshair

var _movement: MovementController
var _blaster: TestBlaster


func bind(movement: MovementController, blaster: TestBlaster) -> void:
	_movement = movement
	_blaster = blaster


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
		"",
		"BHOP CHAIN   %d" % _movement.bhop_chain,
		"LAST HOP     %.0f ms on ground" % (_movement.last_hop_ground_time * 1000.0),
		"AIR STRAFE   %s" % strafe,
		"SOFT CEIL    %.1f m/s   (gain x%.2f)" % [cfg.air_soft_ceiling, falloff],
		"",
		"DASH         %s" % _dash_text(),
		"WEAPON       %s" % ("READY" if _blaster.ready_to_fire() else "CYCLING"),
		"",
		"LMB fire (semi-auto)   SHIFT dash   CTRL crouch/slide   ESC mouse",
	])


func _dash_text() -> String:
	if _movement.dash_ready():
		return "READY"
	return "COOLDOWN %.2fs" % _movement.dash_cooldown_left()
