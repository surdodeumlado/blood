class_name Crosshair
extends Control

## Placeholder crosshair plus hitmarker. Drawn, not textured, so there is no
## art dependency. The hitmarker is the "I hit it" confirmation that has to
## work without any numbers on screen.

@export var arm_length := 6.0
@export var gap := 4.0
@export var thickness := 2.0
@export var hitmarker_time := 0.18
@export var hitmarker_size := 9.0
@export var color := Color(0.85, 0.92, 1.0, 0.7)
@export var hitmarker_color := Color(1.0, 0.25, 0.2, 1.0)
## Headshots get their own marker: bigger, brighter, drawn with a ring so it is
## unmistakable without any numbers on screen.
@export var headshot_time := 0.3
@export var headshot_size := 17.0
@export var headshot_color := Color(1.0, 0.93, 0.55, 1.0)

var _flash := 0.0
var _flash_duration := 0.18
var _critical := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	queue_redraw()
	if _flash <= 0.0:
		set_process(false)


func flash(critical := false) -> void:
	_critical = critical
	_flash_duration = headshot_time if critical else hitmarker_time
	_flash = _flash_duration
	set_process(true)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	draw_line(c + Vector2(-gap - arm_length, 0), c + Vector2(-gap, 0), color, thickness)
	draw_line(c + Vector2(gap, 0), c + Vector2(gap + arm_length, 0), color, thickness)
	draw_line(c + Vector2(0, -gap - arm_length), c + Vector2(0, -gap), color, thickness)
	draw_line(c + Vector2(0, gap), c + Vector2(0, gap + arm_length), color, thickness)

	if _flash <= 0.0:
		return
	var life := _flash / _flash_duration
	var col := headshot_color if _critical else hitmarker_color
	col.a *= life
	var size_ := headshot_size if _critical else hitmarker_size
	var width := thickness * 1.6 if _critical else thickness
	for d in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		draw_line(c + d * (size_ * 0.45), c + d * size_, col, width)
	if _critical:
		# Expanding ring, only ever drawn for a headshot.
		draw_arc(c, size_ * (1.6 - life * 0.5), 0.0, TAU, 24, col, width, true)
