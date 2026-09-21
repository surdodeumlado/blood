class_name WeaponSelector
extends Control

## Temporary weapon list that appears on a switch and fades out again.
##
## Original and deliberately plain: a column of slots with the active one
## marked. Not a HUD, not a weapon wheel, no art - it exists so that while
## cycling with the wheel you can see what you are about to land on.

@export var hold_time := 1.2
@export var fade_time := 0.35
@export var row_height := 22.0
@export var width := 210.0
@export var margin := 18.0
@export var font_size := 14

@export var text_colour := Color(0.72, 0.74, 0.8, 1.0)
@export var active_colour := Color(1.0, 0.86, 0.45, 1.0)
@export var panel_colour := Color(0.05, 0.05, 0.06, 0.78)
@export var active_panel_colour := Color(0.3, 0.09, 0.09, 0.9)

var _entries: PackedStringArray = []
var _active := 0
var _timer := 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	set_process(false)
	modulate.a = 0.0


## Called whenever the rack changes weapon.
func show_weapons(names: PackedStringArray, active_index: int) -> void:
	_entries = names
	_active = active_index
	_timer = hold_time + fade_time
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_timer = maxf(_timer - delta, 0.0)
	modulate.a = clampf(_timer / maxf(fade_time, 0.001), 0.0, 1.0)
	if _timer <= 0.0:
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if _entries.is_empty() or _font == null:
		return
	var total := _entries.size() * row_height
	var origin := Vector2(size.x - width - margin, (size.y - total) * 0.5)

	for i in _entries.size():
		var top := origin + Vector2(0.0, i * row_height)
		var rect := Rect2(top, Vector2(width, row_height - 3.0))
		var is_active := i == _active
		draw_rect(rect, active_panel_colour if is_active else panel_colour, true)
		if is_active:
			# A bright edge on the left: reads instantly in peripheral vision.
			draw_rect(Rect2(top, Vector2(3.0, row_height - 3.0)), active_colour, true)
		draw_string(
			_font,
			top + Vector2(12.0, row_height * 0.72),
			"[%d]  %s" % [i + 1, _entries[i]],
			HORIZONTAL_ALIGNMENT_LEFT,
			width - 24.0,
			font_size,
			active_colour if is_active else text_colour
		)
