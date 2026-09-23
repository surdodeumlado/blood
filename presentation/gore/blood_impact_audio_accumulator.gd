class_name BloodImpactAudioAccumulator
extends Node3D
## Local pooled presentation component, NOT another global audio bus/autoload.
## Deterministic synthesized placeholders; replace streams for final sound design.
## Density tiers: isolated ticks, a patter, and a rain texture.
const TIERS := 4
## Impact counts at which a cluster moves up a tier.
##
## FOUR tiers, not three: with three, twenty and a hundred impacts landed in the
## same texture AND both saturated the gain cap, so a downpour sounded exactly
## like a patter. The top tier is what keeps heavy blood rain distinct once
## loudness has deliberately stopped growing.
const TIER_PATTER := 4
const TIER_RAIN := 18
const TIER_DOWNPOUR := 55
## Seconds of texture per tier. Longer means denser-sounding, not just louder.
const TIER_DURATION := [0.09, 0.24, 0.46, 0.78]

var settings: BloodStabilitySettings
var clusters: Dictionary = {}
var voices: Array[AudioStreamPlayer3D] = []
var voice_left: Array[float] = []
var voice_ready_at: Array[int] = []
var streams: Array[AudioStreamWAV] = []
var clock := 0.0
var submitted := 0
var played := 0
var peak_voices := 0
var merged_overflow := 0
var filtered := 0
var expired_clusters := 0
var last_events: Array[Dictionary] = []

func setup(config: BloodStabilitySettings) -> void:
	if not voices.is_empty(): return # Capacities/resources are fixed at construction.
	settings = config
	# 4 surfaces x 3 DENSITY TIERS, all built once here. Fixed capacity, no hot
	# path allocation, and the tiers are what make a hundred drops sound unlike
	# six - previously there were only two textures and a binary switch at six
	# impacts, so "patter" and "downpour" were literally the same sound.
	for surface in 4:
		for tier in TIERS: streams.append(_placeholder(surface, tier))
	for i in settings.audio_voices:
		var voice := AudioStreamPlayer3D.new()
		voice.max_distance = settings.audio_max_distance_m
		voice.unit_size = settings.audio_unit_size_m
		add_child(voice)
		voices.append(voice)
		voice_left.append(0.0)
		voice_ready_at.append(0)

func submit(pos: Vector3, surface: BloodSurfaceResponse, mass: float, speed: float, material: int, normal: Vector3, timestamp: float) -> void:
	if not settings.audio_enabled or mass < settings.audio_min_mass or speed < 0.2:
		filtered += 1
		return
	submitted += 1
	var cell := Vector3i((pos / settings.audio_cell_m).floor())
	var acoustic := 2 if surface.absorption_rate > 0.1 else (1 if surface.roughness > 0.4 else 0)
	if acoustic == 0 and absf(normal.y) < 0.6: acoustic = 3
	var key := "%s:%d" % [cell, acoustic]
	if not clusters.has(key):
		if clusters.size() >= settings.audio_clusters:
			# Enrich an existing nearby texture, never allocate another voice.
			var best := INF
			for candidate in clusters:
				var distance: float = clusters[candidate].pos.distance_squared_to(pos)
				if distance < best: best = distance; key = candidate
			merged_overflow += 1
		else:
			clusters[key] = {"pos": pos, "mass": 0.0, "count": 0, "speed": 0.0,
				"surface": acoustic, "age": 0.0, "timestamp": timestamp, "material": material}
	var c: Dictionary = clusters[key]
	c.pos = (c.pos * c.mass + pos * mass) / maxf(c.mass + mass, 0.000001)
	c.mass += mass
	c.count += 1
	c.speed = maxf(c.speed, speed)

func advance(delta: float, event_budget: int) -> int:
	if not settings.audio_enabled: return 0
	clock += delta
	for i in voices.size(): voice_left[i] = maxf(0.0, voice_left[i] - delta)
	var emitted := 0
	for key in clusters.keys():
		var c: Dictionary = clusters[key]
		c.age += delta
		if c.age > settings.audio_cluster_max_age_s:
			clusters.erase(key)
			expired_clusters += 1
			continue
		if c.age < settings.audio_window_s or emitted >= event_budget: continue
		var free := -1
		for i in voices.size():
			# Physics catch-up/manual fixtures can outrun the audio mixer. Do
			# not replace a playback merely because simulated time advanced.
			if voice_left[i] <= 0.0 and Time.get_ticks_usec() >= voice_ready_at[i] and not voices[i].playing:
				free = i
				break
		if free < 0: continue
		var tier := tier_for(int(c.count))
		var voice := voices[free]
		voice.stream = streams[c.surface * TIERS + tier]
		voice.global_position = c.pos
		# Denser clusters sit slightly lower and vary less: a downpour is a bed,
		# a single drop is a distinct tick.
		var spread: float = [0.12, 0.08, 0.05, 0.035][tier]
		var centre: float = [0.98, 0.92, 0.86, 0.82][tier]
		voice.pitch_scale = clampf(
			centre + sin(float(played) * 2.37) * spread + minf(c.speed, 10.0) * 0.006, 0.78, 1.15
		)
		# SATURATING gain, driven by mass AND count, so density is audible
		# without ever becoming linear in impact count or outrunning combat.
		var loudness: float = log(1.0 + c.mass * 25.0 + float(c.count) * 0.9) * 2.6
		voice.volume_db = minf(settings.audio_max_db, settings.audio_base_db + loudness)
		if c.surface == 2: voice.volume_db -= 4.0
		voice.play()
		voice_left[free] = float(TIER_DURATION[tier]) / voice.pitch_scale
		voice_ready_at[free] = Time.get_ticks_usec() + int(voice_left[free] * 1000000)
		played += 1
		emitted += 1
		last_events.append({"position": c.pos, "count": c.count, "mass": c.mass, "tier": tier,
			"dense": tier > 0, "db": voice.volume_db, "surface": c.surface,
			"duration": float(TIER_DURATION[tier])})
		if last_events.size() > 32: last_events.pop_front()
		clusters.erase(key)
	var active := 0
	for i in voice_left.size():
		if voice_left[i] > 0.0 or voices[i].playing or Time.get_ticks_usec() < voice_ready_at[i]: active += 1
	peak_voices = maxi(peak_voices, active)
	return emitted

## Which density texture a cluster of this many impacts deserves.
##
##   0  isolated  - a single quiet wet tick
##   1  patter    - several irregular details
##   2  rain      - a continuous wet bed
##   3  downpour  - a heavy continuous wash
func tier_for(count: int) -> int:
	if count >= TIER_DOWNPOUR: return 3
	if count >= TIER_RAIN: return 2
	if count >= TIER_PATTER: return 1
	return 0


func clear() -> void:
	clusters.clear()
	for i in voices.size():
		if is_instance_valid(voices[i]):
			voices[i].stop()
		voice_left[i] = 0.0
		# stop() does not synchronously retire playback in the audio mixer.
		# Preserve the real-time deadline across reset instead of stealing it.

## One placeholder texture. `tier` changes the NUMBER OF INTERNAL TRANSIENTS and
## the length, not just the amplitude: that is what makes density audible rather
## than merely loud.
func _placeholder(surface: int, tier: int) -> AudioStreamWAV:
	var rate := 22050
	var dense := tier > 0
	var duration: float = float(TIER_DURATION[tier])
	var data := PackedByteArray()
	data.resize(int(rate * duration) * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 19283 + surface * 13 + tier
	var phase := 0.0
	var filtered_sample := 0.0
	var onset := 0.0
	# Higher tiers fire their next wet transient sooner, so the same second of
	# audio contains many more of them: a texture, not one repeated splat.
	var gap_min: float = [0.023, 0.014, 0.005, 0.0025][tier]
	var gap_max: float = [0.049, 0.030, 0.012, 0.0065][tier]
	var next_onset := rng.randf_range(gap_min, gap_max)
	for i in data.size() / 2:
		var t := float(i) / rate
		if dense and t >= next_onset:
			onset = next_onset
			next_onset += rng.randf_range(gap_min, gap_max)
		var cycle := t - onset
		var freq: float = lerpf(850.0, 180.0, clampf(cycle / 0.05, 0, 1)) * [1.1, 0.8, 0.55, 0.92][surface]
		phase += TAU * freq / rate
		filtered_sample = lerpf(filtered_sample, rng.randf_range(-1, 1), 0.25 if surface == 2 else 0.65)
		var envelope := (1.0 - exp(-cycle * 1500)) * exp(-cycle * 95) * (1.0 - t / duration)
		var sample := (sin(phase) * 0.25 + filtered_sample * 0.65) * envelope
		data.encode_s16(i * 2, int(clampf(sample, -1, 1) * 32767))
	# Known source amplitude; otherwise quiet source + -30 dB + inverse distance
	# made valid impacts effectively inaudible next to combat.
	var peak := 1.0
	for i in data.size() / 2: peak = maxf(peak, absf(data.decode_s16(i * 2)))
	for i in data.size() / 2:
		data.encode_s16(i * 2, int(data.decode_s16(i * 2) * (0.7 * 32767.0 / peak)))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	return stream
