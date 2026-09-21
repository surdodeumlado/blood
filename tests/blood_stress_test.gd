extends Node3D

## Development stress test: what a real fight costs.
##
##     godot --headless --path . res://tests/blood_stress_test.tscn
##
## Runs 30 normal kills, 10 major kills and several grenade multi-kills through
## ONE chamber and reports what the system was holding at peak.
##
## It does NOT report FPS. This runs headless with no renderer, so any frame
## number it printed would be fiction. What it can honestly measure is the thing
## that actually drives cost: how much material was live, how many physics
## queries the blood system issued per second, and whether any budget was
## breached. Frame cost belongs to the playtest.

const SETTINGS := "res://data/blood/blood_settings.tres"
const RESERVOIR := "res://data/blood/reservoir_defaults.tres"

const NORMAL_KILLS := 30
const MAJOR_KILLS := 10
const GRENADE_VICTIMS := 4
const GRENADE_EVENTS := 4

var _blood: BloodSystem
var _peak := {}
var _query_samples: Array[int] = []


func _ready() -> void:
	_build_world()
	_blood = BloodSystem.new()
	_blood.settings = (load(SETTINGS) as BloodSettings).duplicate()
	_blood.fallback_reservoir = load(RESERVOIR)
	_blood.profiles.assign([
		load("res://data/blood/blood_ballistic.tres"),
		load("res://data/blood/blood_slashing.tres"),
		load("res://data/blood/blood_piercing.tres"),
		load("res://data/blood/blood_blunt.tres"),
		load("res://data/blood/blood_high_energy.tres"),
	])
	_blood.settings.quality = BloodTypes.Quality.INSANE
	add_child(_blood)
	_run()


func _build_world() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	for spec in [
		[Vector3(120, 1, 120), Vector3(0, -0.5, 0)],
		[Vector3(120, 14, 1), Vector3(0, 7, -40)],
		[Vector3(120, 14, 1), Vector3(0, 7, 40)],
		[Vector3(1, 14, 120), Vector3(-40, 7, 0)],
		[Vector3(1, 14, 120), Vector3(40, 7, 0)],
	]:
		var s := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = spec[0]
		s.shape = b
		s.position = spec[1]
		body.add_child(s)
	add_child(body)


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
		_sample()


func _sample() -> void:
	var live: Dictionary = _blood.live_counts()
	for key in live:
		_peak[key] = maxi(_peak.get(key, 0), int(live[key]))
	# Physics queries this frame: one per airborne representative plus one per
	# flying solid. This is the number that actually scales with blood volume.
	_query_samples.append(int(live["representatives"]) + int(live["solids_flying"]))


func _kill(family: BloodTypes.DamageType, at: Vector3, region: BloodTypes.BodyRegion, energy: float) -> void:
	var r := _reservoir()
	var ctx := BloodContext.make(family, at, Vector3(0, 0, -1), region, energy)
	ctx.is_kill = true
	if family == BloodTypes.DamageType.SLASHING:
		ctx.swing_plane_normal_ws = Vector3.UP
		ctx.penetration_direction_ws = Vector3(1, 0, 0)
	_blood.release(r.withdraw(ctx))


func _run() -> void:
	var t0 := Time.get_ticks_msec()

	# --- 30 normal kills, spread across the chamber.
	for i in NORMAL_KILLS:
		var a := float(i) / NORMAL_KILLS * TAU
		_kill(
			[BloodTypes.DamageType.BALLISTIC, BloodTypes.DamageType.SLASHING][i % 2],
			Vector3(cos(a) * 18.0, 1.6, sin(a) * 18.0),
			BloodTypes.BodyRegion.TORSO,
			1.0
		)
		await _tick(4)

	# --- 10 major kills: headshots and maul blows.
	for i in MAJOR_KILLS:
		var a := float(i) / MAJOR_KILLS * TAU
		_kill(
			[BloodTypes.DamageType.BALLISTIC, BloodTypes.DamageType.BLUNT][i % 2],
			Vector3(cos(a) * 9.0, 2.0, sin(a) * 9.0),
			BloodTypes.BodyRegion.HEAD,
			1.6
		)
		await _tick(6)

	# --- Grenade multi-kills: several victims per blast, each with its own
	# outward axis, which is the worst case the system has.
	for e in GRENADE_EVENTS:
		var centre := Vector3(randf_range(-14, 14), 1.0, randf_range(-14, 14))
		for v in GRENADE_VICTIMS:
			var offset := Vector3(cos(v * 1.57) * 2.0, 0.6, sin(v * 1.57) * 2.0)
			var r := _reservoir()
			var ctx := BloodContext.make(
				BloodTypes.DamageType.HIGH_ENERGY, centre + offset,
				offset.normalized(), BloodTypes.BodyRegion.TORSO, 2.0
			)
			ctx.is_kill = true
			ctx.explosion_direction_ws = offset.normalized()
			_blood.release(r.withdraw(ctx))
		await _tick(8)

	# Let everything in flight land.
	await _tick(240)
	var elapsed := Time.get_ticks_msec() - t0
	_report(elapsed)


func _report(elapsed_ms: int) -> void:
	var live: Dictionary = _blood.live_counts()
	var tel: Dictionary = _blood.telemetry()
	var s: BloodSettings = _blood.settings

	var peak_queries := 0
	var total_queries := 0
	for q in _query_samples:
		peak_queries = maxi(peak_queries, q)
		total_queries += q

	print("")
	print("=== BLOOD STRESS TEST (INSANE) ===")
	print("%d normal kills + %d major kills + %d grenade events x %d victims"
		% [NORMAL_KILLS, MAJOR_KILLS, GRENADE_EVENTS, GRENADE_VICTIMS])
	print("blood events: %d   wall time: %d ms   simulated frames: %d"
		% [tel["events"], elapsed_ms, _query_samples.size()])
	print("")
	print("PEAK LIVE")
	print("  visual micro      %5d / %d" % [_peak.get("micro", 0), s.max_micro])
	print("  visual small      %5d / %d" % [_peak.get("small", 0), s.max_small])
	print("  physical droplets %5d / %d" % [_peak.get("medium", 0), s.max_medium])
	print("  tissue + chunks   %5d / %d" % [_peak.get("large", 0), s.max_large])
	print("  stains            %5d / %d" % [_peak.get("surface", 0), s.max_surface])
	print("  wound emitters    %5d" % _peak.get("wounds", 0))
	print("  remnants          %5d" % _peak.get("remnants", 0))
	print("  contaminated cells%5d" % _peak.get("cells", 0))
	print("")
	print("FINAL (after everything landed)")
	print("  stains still on the arena   %d" % live["surface"])
	print("  solids settled on the floor %d" % live["solids_settled"])
	print("")
	print("PHYSICS QUERY LOAD (raycasts per frame from blood)")
	print("  peak %d   mean %.1f" % [
		peak_queries, float(total_queries) / maxf(float(_query_samples.size()), 1.0)
	])
	print("")
	print("RECYCLING PER LAYER  (requested / admitted / rejected / recycled / evicted)")
	for key in ["micro", "small", "medium", "large", "surface"]:
		var t: Dictionary = tel[key]
		print("  %-9s %6d / %6d / %6d / %6d / %6d" % [
			key, t["requested"], t["admitted"], t["rejected"], t["recycled"], t["evicted"]
		])
	print("")
	print("NOTE: no FPS figure is reported. This run is headless with no")
	print("renderer, so any frame number here would be fabricated. Frame cost")
	print("is a playtest measurement.")

	var breached := false
	for key in ["micro", "small", "medium", "large", "surface"]:
		var cap: int = (tel[key] as Dictionary)["capacity"]
		if _peak.get(key, 0) > cap:
			breached = true
			printerr("BUDGET BREACH: %s peaked at %d over capacity %d" % [key, _peak[key], cap])
	print("budgets respected: %s" % ("NO" if breached else "yes"))
	get_tree().quit(1 if breached else 0)
