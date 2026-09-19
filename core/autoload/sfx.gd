extends Node

## Placeholder audio. Every sound is SYNTHESISED AT STARTUP in a few hundred
## milliseconds of maths - there are no audio files in the repo and none of this
## is sound direction. It exists so that every input and every event has an
## audible confirmation while we tune feel.
##
## This is the project's only autoload. It is here because the player, the
## weapon, the impact effects and every enemy all need to make noise from
## unrelated parts of the tree, and the alternative (an audio node per event)
## is exactly the leak this file avoids: a fixed pool, nothing allocated at
## runtime, nothing to clean up.

const MIX_RATE := 22050
const POOL_3D := 12
const POOL_2D := 4

var _streams: Dictionary[StringName, AudioStreamWAV] = {}
var _players_3d: Array[AudioStreamPlayer3D] = []
var _players_2d: Array[AudioStreamPlayer] = []
var _next_3d := 0
var _next_2d := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_streams()
	_build_pools()


func stream(key: StringName) -> AudioStreamWAV:
	return _streams.get(key) as AudioStreamWAV


## Positional one-shot. Silently does nothing for an unknown key.
func play_3d(key: StringName, pos: Vector3, pitch := 1.0, volume_db := -6.0) -> void:
	var s := _streams.get(key) as AudioStreamWAV
	if s == null:
		return
	var player := _take_3d()
	player.stream = s
	player.global_position = pos
	player.pitch_scale = pitch
	player.volume_db = volume_db
	player.play()


## Non-positional one-shot, for things that happen at the camera.
func play_2d(key: StringName, pitch := 1.0, volume_db := -8.0) -> void:
	var s := _streams.get(key) as AudioStreamWAV
	if s == null:
		return
	var player := _take_2d()
	player.stream = s
	player.pitch_scale = pitch
	player.volume_db = volume_db
	player.play()


# --------------------------------------------------------------------------
# Pools: fixed size, round-robin, reused forever.
# --------------------------------------------------------------------------

func _build_pools() -> void:
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 90.0
		p.unit_size = 14.0
		add_child(p)
		_players_3d.append(p)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players_2d.append(p)


func _take_3d() -> AudioStreamPlayer3D:
	for i in _players_3d.size():
		var idx := (_next_3d + i) % _players_3d.size()
		if not _players_3d[idx].playing:
			_next_3d = (idx + 1) % _players_3d.size()
			return _players_3d[idx]
	# All busy: steal the oldest slot rather than allocating a new node.
	var stolen := _players_3d[_next_3d]
	_next_3d = (_next_3d + 1) % _players_3d.size()
	return stolen


func _take_2d() -> AudioStreamPlayer:
	for i in _players_2d.size():
		var idx := (_next_2d + i) % _players_2d.size()
		if not _players_2d[idx].playing:
			_next_2d = (idx + 1) % _players_2d.size()
			return _players_2d[idx]
	var stolen := _players_2d[_next_2d]
	_next_2d = (_next_2d + 1) % _players_2d.size()
	return stolen


# --------------------------------------------------------------------------
# Synthesis
# --------------------------------------------------------------------------

func _build_streams() -> void:
	_streams[&"jump"] = _tone(0.09, 320.0, 640.0, 0.0, 26.0, false, 0.55)
	_streams[&"land"] = _tone(0.14, 150.0, 70.0, 0.45, 30.0, false, 0.7)
	_streams[&"dash"] = _tone(0.17, 880.0, 210.0, 0.35, 16.0, false, 0.6)
	# Hand cannon: a big, low, slow-decaying boom, not a pistol tick.
	_streams[&"shot"] = _tone(0.30, 340.0, 52.0, 0.55, 11.0, true, 0.98)
	_streams[&"impact"] = _tone(0.06, 1400.0, 500.0, 0.85, 70.0, false, 0.45)
	_streams[&"hit"] = _tone(0.07, 980.0, 680.0, 0.4, 48.0, true, 0.6)
	# Headshot: a bright ringing crack, deliberately nothing like the body hit.
	_streams[&"headshot"] = _tone(0.26, 2100.0, 1150.0, 0.2, 10.0, false, 0.85)
	_streams[&"death"] = _tone(0.38, 520.0, 70.0, 0.55, 8.0, true, 0.75)
	_streams[&"slide"] = _slide_loop(0.45)


## One-shot recipe: a pitch sweep blended with noise under an exponential decay.
## square=true gives it a harsher, more "placeholder weapon" edge.
func _tone(
	duration: float,
	freq_start: float,
	freq_end: float,
	noise_mix: float,
	decay: float,
	square: bool,
	amp: float
) -> AudioStreamWAV:
	var count := int(duration * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(duration + freq_start * 7.0 + freq_end)
	var phase := 0.0
	for i in count:
		var t := float(i) / count
		var freq: float = lerpf(freq_start, freq_end, t)
		phase += TAU * freq / MIX_RATE
		var wave := sin(phase)
		if square:
			wave = signf(wave) * 0.7
		var sample: float = lerpf(wave, rng.randf_range(-1.0, 1.0), noise_mix)
		# Short attack ramp so nothing starts on a click.
		var attack := minf(float(i) / 48.0, 1.0)
		data.encode_s16(i * 2, int(clampf(
			sample * amp * attack * exp(-decay * t), -1.0, 1.0
		) * 32767.0))
	return _wav(data, false)


## Looping filtered noise for the slide. One-pole lowpass, seam-matched ends.
func _slide_loop(duration: float) -> AudioStreamWAV:
	var count := int(duration * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9137
	var filtered := 0.0
	for i in count:
		filtered = lerpf(filtered, rng.randf_range(-1.0, 1.0), 0.09)
		# Crossfade the tail into the head so the loop point is inaudible.
		var fade := 1.0
		var tail := 900
		if i > count - tail:
			fade = float(count - i) / tail
		data.encode_s16(i * 2, int(clampf(filtered * 2.4 * fade, -1.0, 1.0) * 32767.0))
	return _wav(data, true)


func _wav(data: PackedByteArray, looping: bool) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	if looping:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = data.size() / 2
	return wav
