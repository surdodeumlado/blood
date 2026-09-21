extends CharacterBody3D

## Thin shell: reads input actions, hands them to the movement controller, and
## wires movement events to camera, audio and HUD. All movement logic lives in
## MovementController; all weapon logic lives in TestBlaster.

const FALLBACK_MOVEMENT_CONFIG := "res://data/movement/default_movement.tres"
## Falling out of the world resets the player instead of dropping forever.
const RESPAWN_BELOW_Y := -30.0
## Landings softer than this are silent, so walking off a kerb does not thud.
const LANDING_SOUND_MIN_SPEED := 3.0

@onready var _collider: CollisionShape3D = $Collider
@onready var _head: Node3D = $Head
@onready var _camera: FirstPersonCamera = $Head/Camera
@onready var _weapons: WeaponRack = $Head/Camera/Weapons
@onready var _movement: MovementController = $Movement
@onready var _hud: DebugHud = $DebugHud
@onready var _slide_audio: AudioStreamPlayer = $SlideAudio

var _spawn_transform: Transform3D
var _hurtbox_debug := false


func _ready() -> void:
	_spawn_transform = global_transform
	if _movement.config == null:
		_movement.config = load(FALLBACK_MOVEMENT_CONFIG)
	_movement.setup(self, _collider, _head)

	_camera.setup(_movement.config, self)
	_camera.set_recoil_recovery(_weapons.config.recoil_recovery)
	_weapons.setup(_camera, self)
	_weapons.hit_confirmed.connect(_on_hit_confirmed)
	_weapons.enemy_killed.connect(_on_enemy_killed)
	_weapons.weapon_changed.connect(_on_weapon_changed)

	_hud.bind(_movement, _weapons, _camera)
	_movement.jumped.connect(_on_jumped)
	_movement.landed.connect(_on_landed)
	_movement.dashed.connect(_on_dashed)
	_movement.slide_started.connect(_on_slide_started)
	_movement.slide_ended.connect(_on_slide_ended)

	_slide_audio.stream = Sfx.stream(&"slide")
	_capture_mouse(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured():
		_camera.look(event.relative)
	elif event.is_action_pressed("pause"):
		_capture_mouse(not _mouse_captured())
	elif _mouse_captured() and _weapons.handle_input(event):
		pass
	elif event.is_action_pressed("debug_blood"):
		var blood := BloodSystem.find(get_tree())
		if blood != null:
			print("[blood] pattern debug %s" % ("ON" if blood.toggle_debug_patterns() else "OFF"))
	elif event.is_action_pressed("debug_hurtboxes"):
		_hurtbox_debug = not _hurtbox_debug
		get_tree().call_group(
			DummyTarget.DEBUG_GROUP, "set_hurtbox_debug", _hurtbox_debug
		)
	elif event is InputEventMouseButton and event.pressed and not _mouse_captured():
		_capture_mouse(true)


func _process(delta: float) -> void:
	# Camera runs at render rate so look, recoil and FOV stay smooth above 60 Hz.
	_camera.update(_movement.horizontal_speed(), delta)
	# Semi-auto: one press, one shot. Holding the button does nothing.
	if _mouse_captured() and Input.is_action_just_pressed("primary_action"):
		_weapons.try_attack()
	if _slide_audio.playing:
		_slide_audio.pitch_scale = clampf(_movement.horizontal_speed() / 12.0, 0.75, 1.7)


func _physics_process(delta: float) -> void:
	if _mouse_captured():
		_movement.input_dir = Input.get_vector(
			"move_left", "move_right", "move_backward", "move_forward"
		)
		# just_pressed, never pressed: holding jump can never auto-bunnyhop.
		_movement.wants_jump = Input.is_action_just_pressed("jump")
		_movement.wants_dash = Input.is_action_just_pressed("dash")
		_movement.wants_crouch = Input.is_action_pressed("crouch")
	else:
		_movement.input_dir = Vector2.ZERO
		_movement.wants_jump = false
		_movement.wants_dash = false
		_movement.wants_crouch = false

	_movement.step(delta)

	if global_position.y < RESPAWN_BELOW_Y:
		global_transform = _spawn_transform
		velocity = Vector3.ZERO


# --------------------------------------------------------------------------
# Feedback
# --------------------------------------------------------------------------

## Pitch rises with the hop chain: the ear is the fastest way to tell whether
## the last landing was clean.
func _on_jumped(hop_chain: int) -> void:
	Sfx.play_2d(&"jump", 1.0 + minf(hop_chain, 8) * 0.035, -12.0)


func _on_landed(impact_speed: float) -> void:
	if impact_speed < LANDING_SOUND_MIN_SPEED:
		return
	Sfx.play_2d(&"land", clampf(1.25 - impact_speed * 0.015, 0.75, 1.25), -11.0)


func _on_dashed() -> void:
	Sfx.play_2d(&"dash", randf_range(0.96, 1.04), -9.0)
	_camera.accent_dash_fov()


func _on_slide_started() -> void:
	_slide_audio.play()


func _on_slide_ended() -> void:
	_slide_audio.stop()


## The selector pops up on every switch and fades out on its own.
func _on_weapon_changed(_weapon: Weapon) -> void:
	var names := PackedStringArray()
	for w in _weapons.weapons:
		names.append(w.display_name)
	_hud.weapon_selector.show_weapons(names, _weapons.current_index)


func _on_hit_confirmed(zone: StringName) -> void:
	_hud.crosshair.flash(zone == Weapon.ZONE_HEAD)


## Precision and aggression buy mobility. Gated on the KILL, never on the hit,
## so a future enemy that survives headshots cannot be farmed for dashes.
func _on_enemy_killed(zone: StringName) -> void:
	if zone == Weapon.ZONE_HEAD:
		_movement.reward_headshot_kill()
	else:
		_movement.reward_kill()


# --------------------------------------------------------------------------

func _mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _capture_mouse(capture: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE
