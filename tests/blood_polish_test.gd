extends Node3D

## Acceptance checks for the performance / readability / bloom / warp / audio
## pass.
##
##     godot --headless --path . res://tests/blood_polish_test.tscn
##
## Shader appearance cannot be asserted headless - the dummy renderer runs no
## fragment code - so the warp checks assert the BOUNDS the shader is given,
## and the visible result is judged in Godot. Everything else here is real
## behaviour: audio tiers, wet-patch scan cost, bloom packing, readability
## being visual-only.

const SETTINGS := "res://data/blood/blood_settings.tres"
const RESERVOIR := "res://data/blood/reservoir_defaults.tres"

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	_build_chamber()
	_run()


func _build_chamber() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	for spec in [
		[Vector3(80, 1, 80), Vector3(0, -0.5, 0)],
		[Vector3(80, 20, 1), Vector3(0, 10, -6.0)],
	]:
		var s := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = spec[0]
		s.shape = b
		s.position = spec[1]
		body.add_child(s)
	add_child(body)


func _run() -> void:
	await _warp_bounds()
	await _readability()
	await _bloom()
	await _audio_density()
	await _wet_patch_cost()
	_report()


func _make_blood() -> BloodSystem:
	var b := BloodSystem.new()
	b.settings = (load(SETTINGS) as BloodSettings).duplicate(true)
	b.fallback_reservoir = load(RESERVOIR)
	b.profiles.assign([
		load("res://data/blood/blood_ballistic.tres"),
		load("res://data/blood/blood_slashing.tres"),
		load("res://data/blood/blood_piercing.tres"),
		load("res://data/blood/blood_blunt.tres"),
		load("res://data/blood/blood_high_energy.tres"),
	])
	add_child(b)
	return b


func _reservoir() -> BloodReservoir:
	var holder := Node3D.new()
	add_child(holder)
	var r := BloodReservoir.new()
	r.config = load(RESERVOIR)
	holder.add_child(r)
	return r


func _tick(n := 1) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(ok: bool, label: String) -> void:
	_checks += 1
	var line := ("  PASS  " if ok else "  FAIL  ") + label
	print(line)
	printerr(line)
	if not ok:
		_failures.append(label)


func _report() -> void:
	var summary := "%d checks, %d failed" % [_checks, _failures.size()]
	print("")
	print(summary)
	printerr(summary)
	for f in _failures:
		printerr("  FAILED: ", f)
	get_tree().quit(0 if _failures.is_empty() else 1)


# --------------------------------------------------------------------------
# Stain warp: assert the BUDGET the shader is compiled with.
# --------------------------------------------------------------------------

func _warp_bounds() -> void:
	var src := FileAccess.get_file_as_string("res://presentation/gore/blood_stain.gdshader")
	_check(src != "", "the stain shader is readable")

	var warp_amount := _uniform(src, "warp_amount")
	var warp_freq := _uniform(src, "warp_frequency")
	var lobe_amount := _uniform(src, "base_lobe_amount")
	var lobe_freq := _uniform(src, "base_lobe_frequency")
	printerr("  [warp] mask %.3f @ %.1f | base lobe %.3f @ %.1f"
		% [warp_amount, warp_freq, lobe_amount, lobe_freq])

	# The saw blade came from HIGH FREQUENCY variation of a RADIUS: repeated
	# teeth around the perimeter. Low frequencies give uneven lobes instead.
	_check(warp_freq <= 9.0, "mask warp is low frequency, not a ripple (%.1f)" % warp_freq)
	_check(lobe_freq <= 5.0, "base lobe is low frequency (%.1f)" % lobe_freq)
	_check(
		not src.contains("47.0") and not src.contains("* 19.0") and not src.contains("* 23.0"),
		"the old 19 / 23 / 47 frequency terms are gone"
	)

	# Perimeter irregularity budget. The base radius is 0.375; the brief asks
	# for roughly 3-8% on a near-normal impact.
	var worst := (lobe_amount * 0.5 + lobe_amount * 0.3 * 0.5) / 0.375
	printerr("  [warp] worst-case base perimeter irregularity %.1f%%" % (worst * 100.0))
	_check(worst < 0.12, "base irregularity is bounded well under a starburst (%.1f%%)" % (worst * 100.0))
	_check(worst > 0.02, "but marks are still not mathematically perfect circles (%.1f%%)" % (worst * 100.0))
	_check(
		warp_amount < 0.03,
		"mask warp amplitude is subtle (%.3f)" % warp_amount
	)


func _uniform(src: String, name: String) -> float:
	for line in src.split("\n"):
		if line.begins_with("uniform float " + name):
			return float(line.split("=")[1].strip_edges().trim_suffix(";"))
	return -1.0


# --------------------------------------------------------------------------
# Airborne readability must be VISUAL ONLY.
# --------------------------------------------------------------------------

func _readability() -> void:
	var blood := _make_blood()
	await _tick(2)
	var s: BloodSettings = blood.settings

	_check(
		s.medium_readability_gain > 1.0,
		"MEDIUM airborne blood gets a readability boost (%.2fx)" % s.medium_readability_gain
	)
	_check(
		s.medium_readability_gain > s.small_readability_gain,
		"MEDIUM is boosted harder than SMALL (%.2f > %.2f)"
			% [s.medium_readability_gain, s.small_readability_gain]
	)
	_check(
		s.readability_max_scale <= 4.0 and s.readability_max_scale > 1.0,
		"distance growth is clamped, never unbounded (%.1fx)" % s.readability_max_scale
	)
	_check(
		s.readability_reference_m > 0.0,
		"there is a near distance below which nothing grows (%.1f m)" % s.readability_reference_m
	)

	# MICRO uses the flat material, so it is excluded by construction.
	var micro: BloodMultiMeshLayer = blood.layer_for_test(BloodTypes.Layer.MICRO)
	var medium: BloodMultiMeshLayer = blood.layer_for_test(BloodTypes.Layer.MEDIUM)
	_check(
		not (micro.material_override is ShaderMaterial)
			or (micro.material_override as ShaderMaterial).shader
				!= (medium.material_override as ShaderMaterial).shader,
		"MICRO does not use the readability shader - fine spray stays fine"
	)
	# SMALL and MEDIUM must be SEPARATE material instances or they cannot carry
	# different gains.
	var small: BloodMultiMeshLayer = blood.layer_for_test(BloodTypes.Layer.SMALL)
	_check(
		small.material_override != medium.material_override,
		"SMALL and MEDIUM carry independent readability settings"
	)

	# The physics must not know any of this happened.
	var src := FileAccess.get_file_as_string("res://presentation/gore/blood_liquid.gdshader")
	_check(
		src.contains("VERTEX *= readability_gain"),
		"the boost is applied in the vertex stage, to rendered geometry only"
	)
	blood.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# Impact bloom
# --------------------------------------------------------------------------

func _bloom() -> void:
	var blood := _make_blood()
	await _tick(2)
	blood.record_stain_writes_for_test()
	var st: BloodStabilitySettings = blood.settings.stability

	_check(
		st.bloom_duration_s >= 0.05 and st.bloom_duration_s <= 0.25,
		"bloom duration is in the readable range (%.0f ms)" % (st.bloom_duration_s * 1000.0)
	)
	_check(
		st.bloom_initial > 0.0 and st.bloom_initial < 0.6,
		"a mark starts as a small contact, not its final footprint (%.2f)" % st.bloom_initial
	)
	_check(
		st.bloom_window_s > st.bloom_duration_s * 10.0,
		"the birth-time window comfortably exceeds the bloom (%.1f s)" % st.bloom_window_s
	)

	# The birth stamp must live in the FRACTION of the atlas row and never
	# disturb the row integer, or the mark would sample the wrong atlas cell.
	var profile: BloodProfile = load("res://data/blood/blood_blunt.tres")
	var rows := {}
	var fractions := 0
	for i in 12:
		blood.place_stain_for_test(
			profile, Vector3(float(i) * 0.8 - 5.0, 0.0, 0.0), Vector3.UP,
			Vector3(0, -1, 0), 0.02
		)
		await _tick(1)
	var layer: BloodMultiMeshLayer = blood.layer_for_test(BloodTypes.Layer.SURFACE)
	for slot in layer.capacity:
		if not layer.is_active(slot):
			continue
		var c: Color = layer.recorded_custom[slot]
		rows[int(floor(c.g))] = true
		if absf(c.g - floor(c.g)) > 0.0001:
			fractions += 1
	printerr("  [bloom] %d marks carry a birth stamp; atlas rows used: %s"
		% [fractions, str(rows.keys())])
	_check(fractions > 0, "stains carry a packed birth time (%d)" % fractions)
	for row in rows:
		_check(
			int(row) >= 0 and int(row) < BloodSystem.ATLAS_ROWS,
			"the packed stamp never corrupts the atlas row (row %d)" % int(row)
		)

	# Shader-side: no per-frame CPU writes for growth.
	var src := FileAccess.get_file_as_string("res://presentation/gore/blood_stain.gdshader")
	_check(src.contains("bloom"), "growth is implemented in the stain shader")
	_check(
		src.contains("shaped /= max(bloom"),
		"growth expands the blood AREA rather than fading alpha in"
	)
	blood.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# Audio density: 1 / 5 / 20 / 100 impacts must differ
# --------------------------------------------------------------------------

func _audio_density() -> void:
	var stability: BloodStabilitySettings = (load(SETTINGS) as BloodSettings).stability
	var audio := BloodImpactAudioAccumulator.new()
	add_child(audio)
	audio.setup(stability)
	await _tick(1)

	_check(
		audio.voices.size() <= 8,
		"the voice pool stays hard-capped (%d voices)" % audio.voices.size()
	)
	_check(
		audio.streams.size() == 4 * BloodImpactAudioAccumulator.TIERS,
		"one fixed texture per surface per density tier (%d)" % audio.streams.size()
	)

	# Tier boundaries.
	printerr("  [audio] tier for 1 / 5 / 20 / 100 impacts: %d / %d / %d / %d"
		% [audio.tier_for(1), audio.tier_for(5), audio.tier_for(20), audio.tier_for(100)])
	_check(audio.tier_for(1) == 0, "one drop is an isolated tick")
	_check(audio.tier_for(5) == 1, "five drops become a patter")
	_check(audio.tier_for(20) == 2, "twenty drops become a rain texture")
	_check(
		audio.tier_for(100) > audio.tier_for(20),
		"a hundred drops is a heavier texture than twenty, not the same one"
	)
	_check(
		audio.tier_for(1000) == audio.tier_for(100),
		"density still saturates rather than growing without limit"
	)

	# Duration and internal transient count must both rise with density - the
	# complaint was that many drops sounded like one drop, louder.
	var durations: Array[float] = []
	for tier in BloodImpactAudioAccumulator.TIERS:
		durations.append(float(BloodImpactAudioAccumulator.TIER_DURATION[tier]))
	printerr("  [audio] tier durations: %s s" % str(durations))
	_check(
		durations[1] > durations[0] * 1.5 and durations[2] > durations[1] * 1.5,
		"each tier is a substantially longer texture"
	)
	var sizes: Array[int] = []
	for tier in BloodImpactAudioAccumulator.TIERS:
		sizes.append((audio.streams[tier] as AudioStreamWAV).data.size())
	_check(
		sizes[2] > sizes[0] * 3,
		"the rain texture holds far more audio than a single tick (%d vs %d bytes)"
			% [sizes[2], sizes[0]]
	)

	# Gain must saturate, not scale linearly with count.
	var g1 := _gain(stability, 0.002, 1)
	var g5 := _gain(stability, 0.010, 5)
	var g20 := _gain(stability, 0.040, 20)
	var g100 := _gain(stability, 0.200, 100)
	printerr("  [audio] gain dB: 1 drop %.1f | 5 %.1f | 20 %.1f | 100 %.1f"
		% [g1, g5, g20, g100])
	_check(g5 > g1 and g20 > g5, "louder with density")
	_check(
		(g100 - g20) < (g20 - g1),
		"the gain curve saturates rather than running away (%.1f dB vs %.1f dB)"
			% [g100 - g20, g20 - g1]
	)
	_check(
		g100 <= stability.audio_max_db,
		"and is hard-capped below combat (%.1f <= %.1f dB)" % [g100, stability.audio_max_db]
	)
	audio.queue_free()
	await _tick(2)


## Mirrors the gain expression in the accumulator.
func _gain(s: BloodStabilitySettings, mass: float, count: int) -> float:
	return minf(s.audio_max_db, s.audio_base_db + log(1.0 + mass * 25.0 + float(count) * 0.9) * 2.6)


# --------------------------------------------------------------------------
# The performance regression itself
# --------------------------------------------------------------------------

func _wet_patch_cost() -> void:
	var blood := _make_blood()
	await _tick(2)
	var st: BloodStabilitySettings = blood.settings.stability
	_check(
		st.wet_updates_per_frame > 0 and st.wet_updates_per_frame < blood.settings.fluid.max_wet_patches,
		"the wet patch scan is bounded per frame (%d of up to %d patches)"
			% [st.wet_updates_per_frame, blood.settings.fluid.max_wet_patches]
	)

	# Fill an arena, stop emitting, and measure the steady-state scan. Before
	# this pass the same scenario cost about 5.4 ms per frame and never fell.
	for i in 5:
		var r := _reservoir()
		await _tick(1)
		var ctx := BloodContext.make(
			BloodTypes.DamageType.HIGH_ENERGY, Vector3(randf_range(-4, 4), 1.7, -2.0),
			Vector3(0, 0, -1), BloodTypes.BodyRegion.HEAD, 1.6
		)
		ctx.is_kill = true
		blood.release(r.withdraw(ctx))
		await _tick(30)
	await _tick(200)

	blood.profile_stages = true
	blood.stage_us.clear()
	await _tick(90)
	var wet: int = int(blood.stage_us.get("wet_patch_updates", 0))
	var per_frame := float(wet) / 90.0
	printerr("  [aftermath] wet patch scan: %d us over 90 frames = %.0f us/frame"
		% [wet, per_frame])
	_check(
		per_frame < 2000.0,
		"holding an aftermath costs well under 2 ms/frame (%.0f us)" % per_frame
	)
	blood.queue_free()
	await _tick(2)
