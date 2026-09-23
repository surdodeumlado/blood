extends Node3D

## PERFORMANCE PROFILER for the blood system.
##
##     godot --headless --path . res://tests/blood_perf_profile.tscn
##
## The brief's rule for this pass is "profile before tuning", so this measures
## the scenarios in the test matrix and reports where the time actually goes -
## per stage, per layer - instead of guessing which part of the droplet path got
## slower.
##
## It deliberately uses the instrumentation the system already carries
## (profile_stages / stage_us / query_count / layer write counters) rather than
## adding a second, competing one.
##
## Scenarios: no blood, 1 victim, 2 simultaneous, 4 simultaneous, and an
## aftermath with many stains but NO new emission - the last one separates
## "emitting blood is slow" from "having blood is slow".

const SETTINGS := "res://data/blood/blood_settings.tres"
const RESERVOIR := "res://data/blood/reservoir_defaults.tres"

## Frames measured per scenario after the event fires.
const MEASURE_FRAMES := 90

var _rows: Array[Dictionary] = []


func _ready() -> void:
	_build_chamber()
	_run()


func _build_chamber() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	for spec in [
		[Vector3(90, 1, 90), Vector3(0, -0.5, 0)],
		[Vector3(90, 20, 1), Vector3(0, 10, -8.0)],
		[Vector3(1, 20, 90), Vector3(-14, 10, 0)],
		[Vector3(90, 1, 90), Vector3(0, 12.0, 0)],
	]:
		var s := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = spec[0]
		s.shape = b
		s.position = spec[1]
		body.add_child(s)
	add_child(body)


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
	b.profile_stages = true
	for layer in [
		BloodTypes.Layer.MICRO, BloodTypes.Layer.SMALL, BloodTypes.Layer.MEDIUM,
		BloodTypes.Layer.LARGE, BloodTypes.Layer.SURFACE,
	]:
		var l: BloodMultiMeshLayer = b.layer_for_test(layer)
		if l != null:
			l.profile_writes = true
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


## One catastrophic kill at `at`.
func _kill(blood: BloodSystem, at: Vector3, family: BloodTypes.DamageType) -> void:
	var r := _reservoir()
	var ctx := BloodContext.make(
		family, at, Vector3(0, 0, -1), BloodTypes.BodyRegion.HEAD, 1.6
	)
	ctx.is_kill = true
	if family == BloodTypes.DamageType.BLUNT:
		ctx.weapon_velocity_ws = Vector3(1, 0, 0) * 9.0
	if family == BloodTypes.DamageType.HIGH_ENERGY:
		ctx.explosion_direction_ws = Vector3(0, 0.3, -1).normalized()
	blood.release(r.withdraw(ctx))


func _layer_stats(blood: BloodSystem) -> Dictionary:
	var writes := 0
	var commits := 0
	var write_us := 0
	var commit_us := 0
	for layer in [
		BloodTypes.Layer.MICRO, BloodTypes.Layer.SMALL, BloodTypes.Layer.MEDIUM,
		BloodTypes.Layer.LARGE, BloodTypes.Layer.SURFACE,
	]:
		var l: BloodMultiMeshLayer = blood.layer_for_test(layer)
		if l == null:
			continue
		writes += l.write_count
		commits += l.commit_count
		write_us += l.write_us
		commit_us += l.commit_us
	return {"writes": writes, "commits": commits, "write_us": write_us, "commit_us": commit_us}


## Run one scenario and record per-frame timings.
func _scenario(name: String, victims: int, aftermath := false) -> void:
	var blood := _make_blood()
	await _tick(3)

	# Pre-load an aftermath WITHOUT new emission, to separate the cost of
	# holding blood from the cost of making it.
	if aftermath:
		for i in 6:
			_kill(blood, Vector3(randf_range(-6, 6), 1.7, randf_range(-5, 2)),
				BloodTypes.DamageType.HIGH_ENERGY)
			await _tick(30)
		await _tick(240)

	blood.stage_us.clear()
	blood.query_count = 0
	for layer in [
		BloodTypes.Layer.MICRO, BloodTypes.Layer.SMALL, BloodTypes.Layer.MEDIUM,
		BloodTypes.Layer.LARGE, BloodTypes.Layer.SURFACE,
	]:
		var l: BloodMultiMeshLayer = blood.layer_for_test(layer)
		if l != null:
			l.write_count = 0
			l.commit_count = 0
			l.write_us = 0
			l.commit_us = 0

	# The release itself, timed separately from the steady-state steps.
	var release_us := 0
	if victims > 0:
		var t0 := Time.get_ticks_usec()
		for v in victims:
			var a := TAU * float(v) / maxf(float(victims), 1.0)
			_kill(
				blood, Vector3(cos(a) * 2.5, 1.7, sin(a) * 2.5 - 2.0),
				[BloodTypes.DamageType.BALLISTIC, BloodTypes.DamageType.BLUNT,
					BloodTypes.DamageType.HIGH_ENERGY, BloodTypes.DamageType.SLASHING][v % 4]
			)
		release_us = Time.get_ticks_usec() - t0

	# Steady state: measure each physics step individually so a spike shows up
	# as P95/peak rather than being hidden in a mean.
	var samples: Array[int] = []
	for i in MEASURE_FRAMES:
		var t := Time.get_ticks_usec()
		await get_tree().physics_frame
		samples.append(Time.get_ticks_usec() - t)
	samples.sort()
	var total := 0
	for s in samples:
		total += s
	var mean := float(total) / maxf(float(samples.size()), 1.0)
	var p95: int = samples[mini(int(float(samples.size()) * 0.95), samples.size() - 1)]
	var peak: int = samples[samples.size() - 1]

	var ls := _layer_stats(blood)
	var live: Dictionary = blood.live_counts()
	_rows.append({
		"name": name,
		"release_us": release_us,
		"mean": mean,
		"p95": p95,
		"peak": peak,
		"queries": blood.query_count,
		"writes": ls["writes"],
		"commits": ls["commits"],
		"write_us": ls["write_us"],
		"commit_us": ls["commit_us"],
		"stages": blood.stage_us.duplicate(),
		"reps": int(live.get("representatives", 0)),
		"surface": int(live.get("surface", 0)),
	})
	blood.queue_free()
	await _tick(3)


func _run() -> void:
	await _scenario("A no blood", 0)
	await _scenario("B 1 victim", 1)
	await _scenario("C 2 victims", 2)
	await _scenario("D 4 victims", 4)
	await _scenario("E aftermath only", 0, true)
	_report()


func _report() -> void:
	printerr("")
	printerr("=== BLOOD PERFORMANCE PROFILE (headless, %d frames per scenario) ===" % MEASURE_FRAMES)
	printerr("")
	printerr("%-18s %10s %9s %9s %9s %8s %9s %8s" % [
		"scenario", "release us", "mean us", "P95 us", "peak us", "queries", "mm writes", "commits"
	])
	for r in _rows:
		printerr("%-18s %10d %9.1f %9d %9d %8d %9d %8d" % [
			r["name"], r["release_us"], r["mean"], r["p95"], r["peak"],
			r["queries"], r["writes"], r["commits"]
		])

	printerr("")
	printerr("PER-STAGE TOTALS (microseconds over the measured window)")
	var labels := {}
	for r in _rows:
		for k in (r["stages"] as Dictionary):
			labels[k] = true
	var header := "%-22s" % "stage"
	for r in _rows:
		header += "%12s" % (r["name"] as String).substr(0, 11)
	printerr(header)
	for label in labels:
		var line := "%-22s" % label
		for r in _rows:
			line += "%12d" % int((r["stages"] as Dictionary).get(label, 0))
		printerr(line)

	printerr("")
	printerr("MULTIMESH BUFFER COST")
	for r in _rows:
		printerr("  %-18s write %6d us | commit %6d us | %d commits | reps %d | stains %d" % [
			r["name"], r["write_us"], r["commit_us"], r["commits"], r["reps"], r["surface"]
		])

	# The superlinearity question the brief asks directly.
	printerr("")
	printerr("SCALING (is cost O(victims) or worse?)")
	var one := _rows[1] as Dictionary
	var two := _rows[2] as Dictionary
	var four := _rows[3] as Dictionary
	var base := (_rows[0] as Dictionary)["mean"] as float
	var n1: float = maxf((one["mean"] as float) - base, 0.001)
	var n2: float = maxf((two["mean"] as float) - base, 0.001)
	var n4: float = maxf((four["mean"] as float) - base, 0.001)
	printerr("  cost above idle:  1v %.1f us | 2v %.1f us (%.2fx) | 4v %.1f us (%.2fx)"
		% [n1, n2, n2 / n1, n4, n4 / n1])
	printerr("  linear would be:  2.00x and 4.00x")
	printerr("  release CPU:      1v %d us | 2v %d us | 4v %d us"
		% [one["release_us"], two["release_us"], four["release_us"]])
	printerr("")
	printerr("NOTE: headless has no renderer, so commit cost here is the CPU-side")
	printerr("buffer copy only. GPU upload is not measured and is not claimed.")
	get_tree().quit(0)
