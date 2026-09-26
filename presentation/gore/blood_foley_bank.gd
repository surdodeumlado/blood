class_name BloodFoleyBank
extends RefCounted
## Authored, short mono PCM only. Missing originals NEVER become synthetic rain.
## See docs/audio/BLOOD_RAIN_AUDIO_SOURCES.md. Load once, not during impacts.
const ROOT := "res://assets/audio/blood/processed/"
const FILES := [
	"blood_drop_small_01.wav", "blood_drop_small_02.wav", "blood_drop_small_03.wav",
	"blood_splash_medium_01.wav", "blood_splash_medium_02.wav",
	"blood_splat_heavy_01.wav", "blood_splat_heavy_02.wav",
	"blood_pool_impact_01.wav", "blood_pool_impact_02.wav",
	"blood_rain_sparse_01.wav", "blood_rain_sparse_02.wav",
	"blood_rain_patter_01.wav", "blood_rain_patter_02.wav",
	"blood_rain_dense_01.wav", "blood_rain_dense_02.wav",
	"blood_rain_heavy_01.wav", "blood_rain_heavy_02.wav"]
const MAX_SECONDS := 1.2
var clips: Array[AudioStreamWAV] = []
var loaded_count := 0
var rejected_count := 0

func setup() -> void:
	if not clips.is_empty(): return
	clips.resize(FILES.size())
	for i in FILES.size():
		var path: String = ROOT + FILES[i]
		if not ResourceLoader.exists(path): continue
		var clip := load(path) as AudioStreamWAV
		if not valid(clip):
			rejected_count += 1
			push_warning("Blood foley rejected (48kHz mono PCM16, no loop, <=1.2s required): " + path)
			continue
		clips[i] = clip
		loaded_count += 1

static func valid(clip: AudioStreamWAV) -> bool:
	return clip != null and clip.format == AudioStreamWAV.FORMAT_16_BITS and not clip.stereo and clip.mix_rate == 48000 and clip.loop_mode == AudioStreamWAV.LOOP_DISABLED and clip.get_length() > 0.005 and clip.get_length() <= MAX_SECONDS

func choose(tier: int, wet: bool, heavy: bool, medium: bool, serial: int) -> AudioStreamWAV:
	var start := 0
	var count := 3
	if tier > 0:
		start = 9 + (clampi(tier, 1, 4) - 1) * 2; count = 2
	elif wet:
		start = 7; count = 2
	elif heavy:
		start = 5; count = 2
	elif medium:
		start = 3; count = 2
	for offset in count:
		var i := start + (serial + offset) % count
		if i < clips.size() and clips[i] != null: return clips[i]
	return null
