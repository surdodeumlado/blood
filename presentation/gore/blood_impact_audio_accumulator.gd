class_name BloodImpactAudioAccumulator
extends Node3D
## Local pooled presentation component, NOT another global audio bus/autoload.
## Real recorded foley only. Missing categories are counted and remain silent.
const TIERS := 5
## Impact counts at which a cluster moves up a tier.
##
## Five tiers distinguish sparse, patter, rain and dense rain after gain saturates.
const TIER_PATTER := 4
const TIER_RAIN := 18
const TIER_DOWNPOUR := 40
const TIER_DENSE := 90
## Seconds of texture per tier. Longer means denser-sounding, not just louder.
const TIER_DURATION := [0.07, 0.24, 0.42, 0.62, 0.78]

var settings: BloodStabilitySettings
var clusters: Dictionary = {}
var voices: Array[AudioStreamPlayer3D] = []
var voice_left: Array[float] = []
var voice_ready_at: Array[int] = []
var streams: Array[AudioStreamWAV] = []
var bank := BloodFoleyBank.new()
var missing_foley_events := 0
var last_missing_impact: Dictionary = {} # one bounded diagnostic, never history
var clock := 0.0
var submitted := 0
var played := 0
var peak_voices := 0
var merged_overflow := 0
var filtered := 0
var expired_clusters := 0
var last_events: Array[Dictionary] = []
var recent_pos := PackedVector3Array()
var recent_time := PackedFloat64Array()
var recent_cursor := 0
var recent_count := 0
var peak_clusters := 0
var peak_recent := 0
var voice_tier := PackedInt32Array()

func setup(config: BloodStabilitySettings) -> void:
	if not voices.is_empty(): return # Capacities/resources are fixed at construction.
	settings = config
	if settings.rain_audio_samples.size() > TIERS: settings.rain_audio_samples.resize(TIERS)
	for i in settings.rain_audio_samples.size():
		if not BloodFoleyBank.valid(settings.rain_audio_samples[i] as AudioStreamWAV): settings.rain_audio_samples[i] = null
	if not BloodFoleyBank.valid(settings.rain_audio_wet_sample as AudioStreamWAV): settings.rain_audio_wet_sample = null
	recent_pos.resize(clampi(settings.audio_recent_capacity, 1, 256))
	recent_time.resize(recent_pos.size())
	recent_time.fill(-INF)
	voice_tier.resize(settings.audio_voices)
	bank.setup()
	for clip in bank.clips:
		if clip != null: streams.append(clip)
	if streams.is_empty():
		push_warning("Blood foley bank absent: impacts silent, no synthetic fallback. See docs/audio/BLOOD_RAIN_AUDIO_SOURCES.md")
	for i in settings.audio_voices:
		var voice := AudioStreamPlayer3D.new()
		voice.max_distance = settings.audio_max_distance_m
		voice.unit_size = settings.audio_unit_size_m
		add_child(voice)
		voices.append(voice)
		voice_left.append(0.0)
		voice_ready_at.append(0)

func submit(pos: Vector3, surface: BloodSurfaceResponse, mass: float, speed: float, material: int, normal: Vector3, timestamp: float, wet := false, drop_id := -1) -> void:
	if not settings.audio_enabled or mass < settings.audio_min_mass or speed < 0.2:
		filtered += 1
		return
	submitted += 1
	recent_pos[recent_cursor] = pos
	recent_time[recent_cursor] = clock
	recent_cursor = (recent_cursor + 1) % recent_pos.size()
	recent_count = mini(recent_count + 1, recent_pos.size())
	peak_recent = maxi(peak_recent, recent_count)
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
				"surface": acoustic, "age": 0.0, "timestamp": timestamp, "material": material, "wet": 0, "drop_id": drop_id}
	peak_clusters = maxi(peak_clusters, clusters.size())
	var c: Dictionary = clusters[key]
	c.pos = (c.pos * c.mass + pos * mass) / maxf(c.mass + mass, 0.000001)
	c.mass += mass
	c.count += 1
	c.wet += int(wet)
	c.speed = maxf(c.speed, speed)

func nearby_count(pos: Vector3) -> int:
	var total := 0
	var radius_sq := settings.audio_recent_radius_m * settings.audio_recent_radius_m
	for i in recent_count:
		if clock - recent_time[i] <= settings.audio_recent_window_s and recent_pos[i].distance_squared_to(pos) <= radius_sq:
			total += 1
	return total

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
		# Rendering density was diluted by 1.2m cells and 80ms dispatch. Remember
		# nearby recent landings after dispatch, with a fixed ring, not a growing grid.
		var density := maxi(int(c.count), nearby_count(c.pos)) if settings.rain_enabled else int(c.count)
		if settings.blood_rain_debug_extreme and density >= 5: density = mini(density * 4, 128)
		var tier := tier_for(density)
		var covered := false
		if tier >= 2:
			for i in voices.size():
				if voice_tier[i] >= 2 and voices[i].playing and voices[i].global_position.distance_squared_to(c.pos) < settings.audio_recent_radius_m * settings.audio_recent_radius_m:
					covered = true
		if covered: continue # Keep/expire the bounded cluster; don't stack rain beds.
		var voice := voices[free]
		var wet_surface := int(c.wet) * 2 > int(c.count)
		# Wet one-shots must not replace a dense patter bed with a single plop.
		var clip: AudioStream = bank.choose(tier, wet_surface, float(c.mass) > 0.025, float(c.mass) > 0.003, played)
		if tier < mini(settings.rain_audio_samples.size(), TIERS) and settings.rain_audio_samples[tier] != null:
			clip = settings.rain_audio_samples[tier]
		if tier == 0 and wet_surface and settings.rain_audio_wet_sample != null: clip = settings.rain_audio_wet_sample
		if clip == null:
			missing_foley_events += 1
			last_missing_impact={"position":c.pos,"drop_id":c.drop_id,"material":c.material,"speed":c.speed,"wet":wet_surface,"reason":"real foley category missing","tier":tier}
			clusters.erase(key)
			continue
		voice.stream = clip
		voice.global_position = c.pos
		# Denser clusters sit slightly lower and vary less: a downpour is a bed,
		# a single drop is a distinct tick.
		var spread: float = [0.045, 0.035, 0.025, 0.02, 0.015][tier]
		var centre: float = 0.98 if wet_surface else 1.0
		voice.pitch_scale = clampf(
			centre + sin(float(played) * 2.37) * spread, 0.93, 1.05
		)
		# SATURATING gain, driven by mass AND count, so density is audible
		# without ever becoming linear in impact count or outrunning combat.
		voice.volume_db = gain_for(density, float(c.mass))
		voice.volume_db -= 0.6 + 0.6 * sin(float(played) * 1.79)
		if c.surface == 2: voice.volume_db -= 4.0
		if wet_surface: voice.volume_db -= 1.5
		if settings.blood_rain_debug_extreme: voice.volume_db = minf(-6.0, voice.volume_db + 12.0)
		if settings.blood_impact_audio_debug: voice.volume_db=-6.0
		voice.play()
		voice_tier[free] = tier
		voice_left[free] = minf(clip.get_length(), BloodFoleyBank.MAX_SECONDS) / voice.pitch_scale
		voice_ready_at[free] = Time.get_ticks_usec() + int(voice_left[free] * 1000000)
		played += 1
		emitted += 1
		last_events.append({"position": c.pos, "count": c.count, "density": density, "wet": wet_surface, "mass": c.mass, "tier": tier,
			"dense": tier > 0, "db": voice.volume_db, "surface": c.surface,
			"duration": clip.get_length(), "sample": clip.resource_path, "pitch": voice.pitch_scale,
			"drop_id":c.drop_id,"playing":voice.playing,"bus":voice.bus,"attenuation":voice.attenuation_model,
			"unit_size":voice.unit_size,"max_distance":voice.max_distance})
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
##   1  sparse    - several irregular details
##   2  patter    - a continuous wet bed
##   3  rain      - a continuous wash
##   4  dense     - more internal transients, same gain ceiling
func tier_for(count: int) -> int:
	if count >= TIER_DENSE: return 4
	if count >= TIER_DOWNPOUR: return 3
	if count >= TIER_RAIN: return 2
	if count >= TIER_PATTER: return 1
	return 0

func gain_for(count: int, mass: float) -> float:
	var loudness := log(1.0 + mass * 25.0 + float(count) * 0.9) * 2.6
	var restraint := 8.0 if count < TIER_PATTER else (3.0 if count < TIER_RAIN else 0.0)
	return minf(settings.audio_max_db, settings.audio_base_db + loudness - restraint)


func clear() -> void:
	clusters.clear()
	last_missing_impact.clear()
	recent_time.fill(-INF)
	recent_pos.fill(Vector3.ZERO)
	recent_count = 0; recent_cursor = 0
	voice_tier.fill(0)
	for i in voices.size():
		if is_instance_valid(voices[i]):
			voices[i].stop()
		voice_left[i] = 0.0
		# stop() does not synchronously retire playback in the audio mixer.
		# Preserve the real-time deadline across reset instead of stealing it.
