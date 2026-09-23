extends Node3D

## Phase 2.2: surface payoff, wall response, runoff, remnant termination.
##
##     godot --headless --path . res://tests/blood_phase22_test.tscn
##
## These cover the three complaints from the live playtest. Passing proves the
## MECHANISM works and the accounting is honest; whether the room finally looks
## dirty enough is decided in Godot by the player, and nothing here claims it.

const SETTINGS := "res://data/blood/blood_settings.tres"
const RESERVOIR := "res://data/blood/reservoir_defaults.tres"

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	_build_chamber()
	_run()


## Floor, a tall wall close enough to catch spatter, and a ceiling.
func _build_chamber() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	for spec in [
		[Vector3(80, 1, 80), Vector3(0, -0.5, 0)],     # floor
		[Vector3(80, 20, 1), Vector3(0, 10, -4.0)],    # wall, close behind
		[Vector3(1, 20, 80), Vector3(-16, 10, 0)],     # side wall
		[Vector3(80, 1, 80), Vector3(0, 11.0, 0)],     # ceiling
	]:
		var s := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = spec[0]
		s.shape = b
		s.position = spec[1]
		body.add_child(s)
	add_child(body)


func _run() -> void:
	await _deposition_payoff()
	await _heavy_packets()
	await _wall_response()
	await _runoff()
	await _remnant_termination()
	await _accumulation()
	_report()


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func _make_blood() -> BloodSystem:
	var b := BloodSystem.new()
	b.synchronous_test_mode = true
	b.manual_budget_clock = true
	b.settings = (load(SETTINGS) as BloodSettings).duplicate()
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


func _ctx(
	family: BloodTypes.DamageType, kill: bool, at := Vector3(0, 1.7, 0),
	dir := Vector3(0, 0, -1)
) -> BloodContext:
	var c := BloodContext.make(family, at, dir, BloodTypes.BodyRegion.TORSO, 1.0)
	c.is_kill = kill
	return c


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
# 1. Deposition payoff (Parts A, B)
# --------------------------------------------------------------------------

func _deposition_payoff() -> void:
	var results := {}
	for family in [
		BloodTypes.DamageType.BALLISTIC, BloodTypes.DamageType.BLUNT,
		BloodTypes.DamageType.HIGH_ENERGY,
	]:
		var blood := _make_blood()
		await _tick(2)
		var r := _reservoir()
		await _tick(1)
		var ctx := _ctx(family, true)
		if family == BloodTypes.DamageType.BLUNT:
			ctx.weapon_velocity_ws = Vector3(1, 0, 0) * 9.0
		if family == BloodTypes.DamageType.HIGH_ENERGY:
			ctx.explosion_direction_ws = Vector3(0, 0.2, -1).normalized()
		blood.release(r.withdraw(ctx))
		await _tick(360)
		results[family] = blood.mass_ledger()
		blood.queue_free()
		await _tick(2)

	for family in results:
		var l: Dictionary = results[family]
		var name: String = BloodTypes.DamageType.keys()[int(family)]
		printerr(
			"  [%s] blood %.3f -> surface %.3f (+runoff %.3f) | %d stains | area %.1f m2"
			% [name, l["release_blood_mass"], l["surface_mass_deposited"],
				l["runoff_mass_claimed"], l["stain_count"],
				l["estimated_total_stain_area"]]
		)
		# Phase 2.1 measured 3.1 m2 for a ballistic kill and 6.5 for blunt. The
		# playtest said that was still too weak, so the bar is raised here.
		_check(
			l["estimated_total_stain_area"] > 9.0,
			"%s: a major kill leaves a large aftermath (%.1f m2)"
				% [name, l["estimated_total_stain_area"]]
		)
		# Accounting stays honest.
		#
		# runoff_mass_claimed is FLOW-THROUGH, not a second sink: a rivulet's
		# budget is subtracted from the stain that spawned it and booked back as
		# it lays its streaks and drops its remainder. So the surface total alone
		# is the whole story once everything has settled, and adding the claimed
		# figure on top would double-count it.
		var deposited: float = l["surface_mass_deposited"]
		var expected: float = l["release_blood_mass"] + l["tissue_mass_deposited"]
		_check(
			deposited > expected * 0.9 and deposited < expected * 1.1,
			"%s: surface mass still matches what was released, runoff included (%.3f vs %.3f)"
				% [name, deposited, expected]
		)


# --------------------------------------------------------------------------
# 2. Heavy packets make heavy marks (Part L)
# --------------------------------------------------------------------------

func _heavy_packets() -> void:
	var blood := _make_blood()
	await _tick(2)
	var profile: BloodProfile = load("res://data/blood/blood_blunt.tres")

	var fine := blood.stain_radius_for_test(profile, 0.0004)
	var heavy := blood.stain_radius_for_test(profile, 0.012)
	printerr("  [packet radii] fine %.3f m, heavy %.3f m" % [fine, heavy])
	_check(
		heavy > fine * 4.0,
		"a heavy packet marks far bigger than a fine one (%.3f vs %.3f)" % [heavy, fine]
	)
	# The specific complaint: heavy airborne material looked good in flight and
	# underwhelming on the ground. A heavy packet must clear the cluster bar, so
	# it breaks up into a group of marks rather than landing as one dot.
	_check(
		0.012 > blood.settings.cluster_mass_threshold,
		"a heavy packet lands as a CLUSTER, not a single disc (%.4f > %.4f)"
			% [0.012, blood.settings.cluster_mass_threshold]
	)
	_check(
		0.0004 < blood.settings.cluster_mass_threshold,
		"a fine droplet still lands as a single small mark"
	)
	blood.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# 3. Wall response (Parts C, F)
# --------------------------------------------------------------------------

func _wall_response() -> void:
	var blood := _make_blood()
	await _tick(2)
	var s: BloodSettings = blood.settings

	var wall_normal := Vector3(0, 0, 1)
	var floor_normal := Vector3.UP
	_check(blood.is_wall_for_test(wall_normal), "a vertical surface is classed as a wall")
	_check(not blood.is_wall_for_test(floor_normal), "a floor is not classed as a wall")
	_check(
		not blood.is_wall_for_test(Vector3.DOWN),
		"a ceiling is not classed as a wall either"
	)

	# A glancing hit on a wall must draw a far longer mark than a head-on one.
	# On a floor the same two angles must NOT diverge as hard - that difference
	# is what stops wall blood reading as a floor decal turned sideways.
	var glancing := Vector3(0.96, 0.0, -0.28).normalized()
	var head_on := Vector3(0, 0, -1)
	var wall_glance := blood.stain_elongation_for_test(
		load("res://data/blood/blood_ballistic.tres"), wall_normal, glancing
	)
	var wall_direct := blood.stain_elongation_for_test(
		load("res://data/blood/blood_ballistic.tres"), wall_normal, head_on
	)
	var floor_glance := blood.stain_elongation_for_test(
		load("res://data/blood/blood_ballistic.tres"), floor_normal,
		Vector3(0.96, -0.28, 0.0).normalized()
	)
	printerr(
		"  [elongation] wall glancing %.2f, wall head-on %.2f, floor glancing %.2f"
		% [wall_glance, wall_direct, floor_glance]
	)
	_check(
		wall_glance > wall_direct * 2.0,
		"a glancing wall impact smears far longer than a head-on one (%.2f vs %.2f)"
			% [wall_glance, wall_direct]
	)
	_check(
		wall_glance > floor_glance,
		"the same glancing angle stretches further on a wall than on a floor (%.2f vs %.2f)"
			% [wall_glance, floor_glance]
	)
	_check(
		s.wall_streak_ratio > 1.0,
		"walls have their own streak ratio (%.1f)" % s.wall_streak_ratio
	)
	blood.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# 4. Runoff (Parts D, E, J, K)
# --------------------------------------------------------------------------

func _runoff() -> void:
	var blood := _make_blood()
	await _tick(2)
	var profile: BloodProfile = load("res://data/blood/blood_high_energy.tres")
	var wall_normal := Vector3(0, 0, 1)
	var spot := Vector3(0, 6.0, -3.49)

	# --- A tiny deposit must NOT run.
	blood.place_stain_for_test(profile, spot, wall_normal, Vector3(0, 0, -1), 0.0005)
	await _tick(2)
	_check(
		int((blood.live_counts())["runoff"]) == 0,
		"a tiny wall droplet does not start running"
	)

	# --- A heavy one must.
	blood.place_stain_for_test(profile, spot, wall_normal, Vector3(0, 0, -1), 0.06)
	await _tick(24) # Wet retention now has a deterministic bounded start delay.
	var running: int = (blood.live_counts())["runoff"]
	_check(running > 0, "a heavy wall deposit starts a rivulet (%d)" % running)

	# --- It travels DOWN and leaves streaks behind it.
	var before: int = (blood.live_counts())["surface"]
	var start_y := blood.runoff_position_for_test(0).y
	await _tick(90)
	var mid_y := blood.runoff_position_for_test(0).y
	var after: int = (blood.live_counts())["surface"]
	printerr("  [runoff] y %.2f -> %.2f, stains %d -> %d" % [start_y, mid_y, before, after])
	_check(
		mid_y < start_y - 0.15 or int((blood.live_counts())["runoff"]) == 0,
		"the rivulet runs downward (%.2f -> %.2f)" % [start_y, mid_y]
	)
	_check(after > before, "the rivulet leaves a visible streak behind it (%d -> %d)" % [before, after])

	# --- And it STOPS, within its lifetime, leaving nothing running.
	await _tick(700)
	var live: Dictionary = blood.live_counts()
	_check(
		int(live["runoff"]) == 0,
		"every rivulet terminates within its bounded lifetime (%d left)" % live["runoff"]
	)

	# --- Bounded: a wall hammered with deposits cannot exceed the cap.
	for i in 80:
		blood.place_stain_for_test(
			profile, Vector3(randf_range(-6, 6), randf_range(3, 8), -3.49),
			wall_normal, Vector3(0, 0, -1), 0.05
		)
	await _tick(3)
	var peak: int = (blood.live_counts())["runoff"]
	_check(
		peak <= blood.settings.max_runoff,
		"active rivulets stay within the cap (%d / %d)" % [peak, blood.settings.max_runoff]
	)
	await _tick(900)
	_check(
		int((blood.live_counts())["runoff"]) == 0,
		"the whole wall drains and stops"
	)

	# --- NO FREE MASS. Put a known quantity on a clean wall, let it run itself
	# out completely, and the world must hold exactly that - not more.
	var fresh := _make_blood()
	await _tick(2)
	var known := 0.0
	for i in 12:
		fresh.place_stain_for_test(
			profile, Vector3(float(i) * 0.4 - 2.0, 7.0, -3.49),
			wall_normal, Vector3(0, 0, -1), 0.05
		)
		known += 0.05
	await _tick(900)
	var led: Dictionary = fresh.mass_ledger()
	printerr(
		"  [runoff accounting] put %.3f on the wall, world holds %.3f (%.3f ran)"
		% [known, led["surface_mass_deposited"], led["runoff_mass_claimed"]]
	)
	_check(
		led["runoff_mass_claimed"] > 0.0,
		"runoff genuinely engaged on that wall (%.3f)" % led["runoff_mass_claimed"]
	)
	_check(
		led["surface_mass_deposited"] <= known * 1.02,
		"running blood creates NO extra mass (%.3f <= %.3f)"
			% [led["surface_mass_deposited"], known * 1.02]
	)
	_check(
		led["surface_mass_deposited"] >= known * 0.9,
		"and loses none of it either (%.3f >= %.3f)"
			% [led["surface_mass_deposited"], known * 0.9]
	)
	fresh.queue_free()
	await _tick(2)
	blood.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# 5. Remnant termination (Parts G, H, I)
# --------------------------------------------------------------------------

func _remnant_termination() -> void:
	var cfg: ReservoirConfig = load(RESERVOIR)
	var blood := _make_blood()
	await _tick(2)

	var r := _reservoir()
	await _tick(1)
	var victim := r.victim()
	victim.global_position = Vector3(8, 0, 0)
	var rel := r.withdraw(
		_ctx(BloodTypes.DamageType.SLASHING, false, Vector3(8, 1.6, 0))
	)
	var w := r.open_wound(rel)
	_check(w != null, "a slashing hit opens a wound")
	if w == null:
		blood.queue_free()
		return

	# THE BUG: detach used to shorten only the CLOCK, leaving the full reserve to
	# be forced out through a faster drip - the remnant bled harder than the
	# living wound. The mass must be capped too.
	var before_detach := w.remaining
	var budget := r.remnant_budget()
	blood.add_remnant(w, Vector3(8, 1.6, 0), budget)
	printerr(
		"  [remnant] carried %.4f, budget %.4f, kept %.4f, life %.2fs"
		% [before_detach, budget, w.remaining, w.lifetime]
	)
	_check(
		w.remaining <= budget + 0.0001,
		"a remnant is capped to its budget, not the whole wound (%.4f <= %.4f)"
			% [w.remaining, budget]
	)
	_check(
		w.lifetime <= blood.settings.remnant_lifetime + 0.001,
		"a remnant's clock comes from settings (%.2f <= %.2f)"
			% [w.lifetime, blood.settings.remnant_lifetime]
	)
	_check(
		w.hard_deadline > 0.0,
		"a remnant carries a hard deadline it cannot outlive (%.2f)" % w.hard_deadline
	)

	# It must be finished well inside a couple of seconds.
	var spent := 0.0
	var frames := 0
	while frames < 300 and w.alive():
		await _tick(1)
		frames += 1
	var seconds := float(frames) / 60.0
	printerr("  [remnant] stopped after %.2f s" % seconds)
	_check(
		not w.alive(),
		"the remnant stops bleeding (after %.2f s)" % seconds
	)
	_check(
		seconds <= blood.settings.remnant_lifetime + 0.4,
		"it stops within its stated lifetime, not long after (%.2f s)" % seconds
	)
	await _tick(20)
	_check(
		int((blood.live_counts())["remnants"]) == 0,
		"the exhausted remnant is retired from the system"
	)

	# --- No free mass: a remnant may never release more than its budget.
	var r2 := _reservoir()
	await _tick(1)
	var rel2 := r2.withdraw(
		_ctx(BloodTypes.DamageType.SLASHING, false, Vector3(-8, 1.6, 0))
	)
	var w2 := r2.open_wound(rel2)
	if w2 != null:
		var budget2 := r2.remnant_budget()
		blood.add_remnant(w2, Vector3(-8, 1.6, 0), budget2)
		var released := 0.0
		for i in 400:
			released += w2.tick(1.0 / 60.0)
			if not w2.alive():
				break
		_check(
			released <= budget2 + 0.0001,
			"a remnant never releases more than its budget (%.4f <= %.4f)"
				% [released, budget2]
		)

	# --- Concurrent remnants are capped.
	for i in 20:
		var rr := _reservoir()
		await _tick(1)
		var rl := rr.withdraw(
			_ctx(BloodTypes.DamageType.SLASHING, false, Vector3(i - 10, 1.6, 2))
		)
		var ww := rr.open_wound(rl)
		if ww != null:
			blood.add_remnant(ww, Vector3(i - 10, 1.6, 2), rr.remnant_budget())
	var remnants: int = (blood.live_counts())["remnants"]
	_check(
		remnants <= blood.settings.max_remnants,
		"concurrent remnants stay within the cap (%d / %d)"
			% [remnants, blood.settings.max_remnants]
	)

	# --- A kill must not leave its wound owned by BOTH the reservoir and the
	# remnant list, which double-dripped it.
	var r3 := _reservoir()
	await _tick(1)
	var kill_rel := r3.withdraw(_ctx(BloodTypes.DamageType.BLUNT, true, Vector3(0, 1.6, 6)))
	var w3 := r3.open_wound(kill_rel)
	if w3 != null:
		r3.release_wound(w3)
		blood.add_remnant(w3, Vector3(0, 1.6, 6), r3.remnant_budget())
		_check(
			not r3.wounds.has(w3),
			"a wound handed over as a remnant is no longer owned by the reservoir"
		)
	_check(
		cfg.remnant_reserve > 0.0,
		"the remnant reserve is a real configured number (%.3f)" % cfg.remnant_reserve
	)
	blood.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# 6. Accumulation (Part B / floor payoff)
# --------------------------------------------------------------------------

func _accumulation() -> void:
	var blood := _make_blood()
	await _tick(2)
	var profile: BloodProfile = load("res://data/blood/blood_blunt.tres")
	var spot := Vector3(3, 0.0, 3)

	# Repeated hits on one patch must build a soaked base, not just more dots.
	for i in 40:
		blood.place_stain_for_test(
			profile, spot + Vector3(randf_range(-0.4, 0.4), 0.02, randf_range(-0.4, 0.4)),
			Vector3.UP, Vector3(0.3, -1, 0.1).normalized(), 0.02
		)
		await _tick(1)
	var bases := blood.soak_bases_for_test()
	printerr("  [accumulation] %d soaked bases, %d stains"
		% [bases, (blood.live_counts())["surface"]])
	_check(bases > 0, "a repeatedly hit patch becomes soaked (%d bases)" % bases)
	_check(
		int((blood.live_counts())["surface"]) > bases * 3,
		"fine spatter still reads on top of the soaked base"
	)
	_check(
		blood.settings.soak_base_offset < blood.settings.surface_offset,
		"the soaked base stays UNDER the detail, never erasing it"
	)
	blood.queue_free()
	await _tick(2)
