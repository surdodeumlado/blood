extends Node3D

## Phase 2.1: air-to-surface payoff, wound lifecycle, blunt momentum, prewarm.
##
##     godot --headless --path . res://tests/blood_phase21_test.tscn
##
## These check the four things the playtest complained about. As always, passing
## proves the MECHANISM works; whether the result looks right is decided in
## Godot by the player, and nothing here is allowed to claim it.

const SETTINGS := "res://data/blood/blood_settings.tres"
const RESERVOIR := "res://data/blood/reservoir_defaults.tres"

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	_build_chamber()
	_run()


## Floor, back wall, side wall and an overhead surface, as Part U requires.
func _build_chamber() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	for spec in [
		[Vector3(80, 1, 80), Vector3(0, -0.5, 0)],      # floor
		[Vector3(80, 16, 1), Vector3(0, 8, -14)],       # back wall
		[Vector3(1, 16, 80), Vector3(-14, 8, 0)],       # side wall
		[Vector3(80, 1, 80), Vector3(0, 9.0, 0)],       # ceiling
	]:
		var s := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = spec[0]
		s.shape = b
		s.position = spec[1]
		body.add_child(s)
	add_child(body)


func _run() -> void:
	await _prewarm_tests()
	await _air_to_surface()
	await _stain_scaling()
	await _soak()
	await _wound_lifecycle()
	await _blunt_momentum()
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


## A maul blow with a REAL swing momentum, the way MeleeWeapon now reports one.
func _maul_ctx(swing: Vector3, at := Vector3(0, 1.7, 0)) -> BloodContext:
	var facing := Vector3(0, 0, -1)
	var c := BloodContext.make(
		BloodTypes.DamageType.BLUNT, at, facing, BloodTypes.BodyRegion.TORSO, 1.4
	)
	c.is_kill = true
	c.swing_plane_normal_ws = swing.cross(facing).normalized()
	c.weapon_velocity_ws = swing * 9.0
	c.penetration_direction_ws = (swing + facing * 0.45).normalized()
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
# 1. Prewarm (Parts R, S, T)
# --------------------------------------------------------------------------

func _prewarm_tests() -> void:
	var blood := _make_blood()
	await _tick(2)
	_check(blood.prewarmed(), "the system prewarms at chamber load")

	# Prewarm must leave NO trace: no visible material, no events, no telemetry.
	var live: Dictionary = blood.live_counts()
	_check(
		live["micro"] == 0 and live["surface"] == 0 and live["large"] == 0,
		"prewarm emits no visible blood (%s)" % str(live)
	)
	_check(blood.event_count() == 0, "prewarm produces no blood events")
	var tel: Dictionary = blood.telemetry()
	_check(
		(tel["micro"] as Dictionary)["requested"] == 0,
		"prewarm does not pollute layer telemetry"
	)
	var r := _reservoir()
	await _tick(1)
	_check(
		is_equal_approx(r.remaining_blood, 1.0),
		"prewarm consumes no reservoir (%.3f)" % r.remaining_blood
	)

	# The measurable CPU claim: after prewarm, the first catastrophic event must
	# not do structurally more work than the second identical one. Wall time in
	# a headless run is noisy, so what is asserted is the thing that actually
	# causes the spike - allocation and pool growth.
	var children := blood.get_child_count()
	var r1 := _reservoir()
	await _tick(1)
	var t0 := Time.get_ticks_usec()
	blood.release(r1.withdraw(_ctx(BloodTypes.DamageType.HIGH_ENERGY, true)))
	var first_us := Time.get_ticks_usec() - t0
	await _tick(1)
	blood.clear_all()
	await _tick(2)
	var r2 := _reservoir()
	await _tick(1)
	var t1 := Time.get_ticks_usec()
	blood.release(r2.withdraw(_ctx(BloodTypes.DamageType.HIGH_ENERGY, true)))
	var second_us := Time.get_ticks_usec() - t1
	_check(
		blood.get_child_count() == children,
		"the first catastrophic event allocates no nodes (%d)" % blood.get_child_count()
	)
	printerr("  [first event %d us, second identical event %d us]" % [first_us, second_us])
	# Deliberately generous: this asserts there is no ORDER-OF-MAGNITUDE first
	# event penalty left on the CPU side, not a precise timing.
	_check(
		first_us < maxi(second_us, 1) * 8,
		"no order-of-magnitude first-event CPU penalty (%d us vs %d us)"
			% [first_us, second_us]
	)
	blood.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# 2. Air to surface (Parts A, C, D, G, U)
# --------------------------------------------------------------------------

func _air_to_surface() -> void:
	var results := {}
	for family in [
		BloodTypes.DamageType.BALLISTIC, BloodTypes.DamageType.SLASHING,
		BloodTypes.DamageType.BLUNT, BloodTypes.DamageType.HIGH_ENERGY,
	]:
		var blood := _make_blood()
		await _tick(2)
		var r := _reservoir()
		await _tick(1)
		var ctx := _ctx(family, true)
		if family == BloodTypes.DamageType.SLASHING:
			ctx.swing_plane_normal_ws = Vector3.UP
			ctx.penetration_direction_ws = Vector3(1, 0, 0)
		if family == BloodTypes.DamageType.BLUNT:
			ctx.weapon_velocity_ws = Vector3(1, 0, 0) * 9.0
		if family == BloodTypes.DamageType.HIGH_ENERGY:
			ctx.explosion_direction_ws = Vector3(0, 0.2, -1).normalized()
		var rel := r.withdraw(ctx)
		blood.release(rel)
		# Let everything land.
		await _tick(300)
		var led: Dictionary = blood.mass_ledger()
		var live: Dictionary = blood.live_counts()
		led["live_surface"] = live["surface"]
		results[family] = led
		blood.queue_free()
		await _tick(2)

	for family in results:
		var l: Dictionary = results[family]
		var name: String = BloodTypes.DamageType.keys()[int(family)]
		printerr("  [%s] blood %.3f -> surface %.3f over %d stains, area %.2f m2 (floor %.3f wall %.3f ceil %.3f)"
			% [name, l["release_blood_mass"], l["surface_mass_deposited"], l["stain_count"],
				l["estimated_total_stain_area"], l["surface_mass_floor"],
				l["surface_mass_wall"], l["surface_mass_ceiling"]])

		# THE core Phase 2.1 claim, and it is TWO-SIDED on purpose.
		#
		# Too little deposited means the aftermath is weaker than the airborne
		# event implied, which is the bug this phase exists to fix. Too much
		# means the system is inventing material - which it WAS: chunk impacts
		# and satellites each carried a hardcoded mass, so a maul kill deposited
		# sixteen bodies' worth of blood and a one-sided check sailed past it.
		var deposited: float = l["surface_mass_deposited"]
		var expected: float = l["release_blood_mass"] + l["tissue_mass_deposited"]
		_check(
			deposited > expected * 0.9 and deposited < expected * 1.1,
			"%s: surface mass matches what was released, no more (%.3f vs %.3f)"
				% [name, deposited, expected]
		)
		_check(
			l["estimated_total_stain_area"] > 1.0,
			"%s: leaves a substantial stained area (%.2f m2)"
				% [name, l["estimated_total_stain_area"]]
		)
		_check(
			int(l["stain_count"]) > 40,
			"%s: leaves a substantial number of marks (%d)" % [name, l["stain_count"]]
		)
		# The cloud must genuinely contribute, not just the physical droplets.
		# This is the half of the material that was depositing NOTHING before.
		_check(
			l["air_visual_mass_represented"] > l["release_blood_mass"] * 0.3,
			"%s: the cheap airborne cloud carries a real share of the mass (%.3f)"
				% [name, l["air_visual_mass_represented"]]
		)
		# And the physical half must actually arrive rather than expiring.
		_check(
			l["physical_mass_that_hit_world"] > l["physical_mass_represented"] * 0.85,
			"%s: physical representatives reach the world (%.3f of %.3f)"
				% [name, l["physical_mass_that_hit_world"], l["physical_mass_represented"]]
		)

	# Part G: an explosion must leave the largest footprint of the four.
	var boom: float = (results[BloodTypes.DamageType.HIGH_ENERGY] as Dictionary)[
		"estimated_total_stain_area"
	]
	var bullet: float = (results[BloodTypes.DamageType.BALLISTIC] as Dictionary)[
		"estimated_total_stain_area"
	]
	_check(
		boom > bullet,
		"EXPLOSIVE leaves a larger footprint than BALLISTIC (%.2f > %.2f)" % [boom, bullet]
	)


# --------------------------------------------------------------------------
# 3. Stain scaling (Parts B, E)
# --------------------------------------------------------------------------

func _stain_scaling() -> void:
	var blood := _make_blood()
	await _tick(2)
	var profile: BloodProfile = load("res://data/blood/blood_blunt.tres")

	# Heavier deposits must make bigger marks, by AREA rather than by a lerp
	# that saturates - which is what made every old stain identical.
	var tiny := blood.stain_radius_for_test(profile, 0.0005)
	var small := blood.stain_radius_for_test(profile, 0.005)
	var medium := blood.stain_radius_for_test(profile, 0.05)
	var heavy := blood.stain_radius_for_test(profile, 0.2)
	printerr("  [stain radii] tiny %.3f small %.3f medium %.3f heavy %.3f" % [tiny, small, medium, heavy])
	_check(
		tiny < small and small < medium and medium < heavy,
		"stain radius rises monotonically with deposited mass"
	)
	_check(
		heavy > small * 3.0,
		"a heavy deposit is dramatically larger than a small one (%.3f vs %.3f)"
			% [heavy, small]
	)
	# Area-proportional: 100x the mass is ~10x the radius, not 100x.
	var ratio := medium / maxf(small, 0.0001)
	_check(
		ratio > 2.0 and ratio < 5.0,
		"stain growth is area-proportional, not linear (10x mass -> %.2fx radius)" % ratio
	)

	# And a real event must produce VARIETY, not one repeated size.
	var r := _reservoir()
	await _tick(1)
	var ctx := _ctx(BloodTypes.DamageType.BLUNT, true)
	ctx.weapon_velocity_ws = Vector3(1, 0, 0) * 9.0
	blood.release(r.withdraw(ctx))
	await _tick(300)
	var led: Dictionary = blood.mass_ledger()
	var mean_area: float = led["mean_stain_area"]
	_check(
		mean_area > 0.002,
		"the average mark is a real mark, not a speck (%.4f m2 mean)" % mean_area
	)
	blood.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# 4. Soaked regions (Part F)
# --------------------------------------------------------------------------

func _soak() -> void:
	var blood := _make_blood()
	await _tick(2)
	# Hammer one small area repeatedly.
	for i in 6:
		var r := _reservoir()
		await _tick(1)
		var ctx := _ctx(BloodTypes.DamageType.BLUNT, true, Vector3(0, 1.4, 0))
		ctx.weapon_velocity_ws = Vector3(1, 0, 0) * 9.0
		blood.release(r.withdraw(ctx))
		await _tick(60)
	await _tick(200)

	var live: Dictionary = blood.live_counts()
	_check(
		int(blood.soak_bases_for_test()) > 0,
		"a repeatedly hit region earns soaked base layers (%d)"
			% blood.soak_bases_for_test()
	)
	# The base layer must not have erased the detail on top of it.
	_check(
		int(live["surface"]) > blood.soak_bases_for_test() * 4,
		"fine directional spatter survives alongside the soaked base (%d stains, %d bases)"
			% [live["surface"], blood.soak_bases_for_test()]
	)
	_check(
		blood.settings.soak_base_offset < blood.settings.surface_offset,
		"the soaked base is laid UNDER the detail stains, never over them"
	)
	blood.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# 5. Wound lifecycle (Parts H, I, J, K, V)
# --------------------------------------------------------------------------

func _wound_lifecycle() -> void:
	var blood := _make_blood()
	await _tick(2)
	var r := _reservoir()
	await _tick(1)
	blood.register_reservoir(r)
	var victim := r.victim()
	victim.global_position = Vector3(0, 0, 0)

	var rel := r.withdraw(_ctx(BloodTypes.DamageType.SLASHING, false, Vector3(0, 1.5, 0)))
	var w := r.open_wound(rel)
	_check(w != null, "a slashing hit opens a wound")
	if w == null:
		blood.queue_free()
		return
	_check(
		w.state == Wound.State.ATTACHED_LIVING,
		"a fresh wound is ATTACHED_LIVING"
	)

	# --- J: a stationary wounded target drips onto the floor below it.
	var before: int = (blood.live_counts())["surface"]
	await _tick(160)
	var after: int = (blood.live_counts())["surface"]
	_check(
		after > before,
		"a stationary wounded target stains the floor below it (%d -> %d)"
			% [before, after]
	)

	# --- J: a moving wounded target leaves a TRAIL, not a puddle.
	blood.clear_all()
	var r2 := _reservoir()
	await _tick(1)
	blood.register_reservoir(r2)
	var walker := r2.victim()
	walker.global_position = Vector3(-6, 0, 3)
	var rel2 := r2.withdraw(_ctx(BloodTypes.DamageType.SLASHING, false, Vector3(-6, 1.5, 3)))
	var w2 := r2.open_wound(rel2)
	var positions: Array[Vector3] = []
	if w2 != null:
		for step in 150:
			walker.global_position += Vector3(0.08, 0, 0)
			positions.append(w2.position_ws(walker.global_transform))
			await _tick(1)
	var spread := 0.0
	if positions.size() > 2:
		spread = positions[0].distance_to(positions[positions.size() - 1])
	_check(
		spread > 6.0,
		"a moving wound travels with its victim, laying a trail (%.1f m)" % spread
	)

	# --- H/I/K: on death the wound must NOT stay floating at torso height.
	var r3 := _reservoir()
	await _tick(1)
	var dying := r3.victim()
	dying.global_position = Vector3(5, 0, 0)
	var rel3 := r3.withdraw(
		_ctx(BloodTypes.DamageType.BALLISTIC, true, Vector3(5, 1.8, 0))
	)
	var w3 := r3.open_wound(rel3)
	_check(w3 != null, "a lethal blow opens a wound to convert into a remnant")
	if w3 != null:
		blood.add_remnant(w3, Vector3(5, 1.8, 0))
		_check(
			w3.state == Wound.State.WORLD_REMNANT,
			"a dead target's wound becomes a WORLD_REMNANT"
		)
		var start_y := w3.position_ws(Transform3D.IDENTITY).y
		var before3: int = (blood.live_counts())["surface"]
		await _tick(120)
		var end_y := w3.position_ws(Transform3D.IDENTITY).y
		_check(
			end_y < start_y - 0.5,
			"the remnant SINKS toward the floor rather than floating (%.2f -> %.2f)"
				% [start_y, end_y]
		)
		_check(
			end_y > -1.0,
			"the remnant comes to rest on the floor instead of falling forever (%.2f)" % end_y
		)
		var after3: int = (blood.live_counts())["surface"]
		_check(
			after3 > before3,
			"the remnant actually deposits blood on the world (%d -> %d)"
				% [before3, after3]
		)
		# --- V: it must END. No infinite emitters.
		await _tick(500)
		_check(
			not w3.alive(),
			"the remnant exhausts itself on a finite clock"
		)
		var live_now: Dictionary = blood.live_counts()
		_check(
			int(live_now["remnants"]) == 0,
			"the exhausted remnant retires (%d left)" % live_now["remnants"]
		)
		_check(
			w3.remaining <= 0.0001 or w3.state == Wound.State.EXHAUSTED,
			"an exhausted wound has nothing left to give"
		)
	blood.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# 6. BLUNT momentum (Parts L, M, N, O, P, W)
# --------------------------------------------------------------------------

func _blunt_momentum() -> void:
	var blood := _make_blood()
	await _tick(2)
	blood.seed_for_test(2024)
	const N := 1200

	# --- L: the vector chain. A maul context must carry real swing momentum,
	# and the pattern must build its axis from that rather than camera forward.
	var plus := _maul_ctx(Vector3(1, 0, 0))
	var minus := _maul_ctx(Vector3(-1, 0, 0))
	_check(
		plus.weapon_velocity_ws.length() > 0.5,
		"a maul hit carries a real weapon velocity into the context"
	)
	_check(
		plus.penetration_direction_ws.dot(Vector3(1, 0, 0)) > 0.5
			and minus.penetration_direction_ws.dot(Vector3(1, 0, 0)) < -0.5,
		"BLUNT penetration direction follows the swing, not camera forward"
	)

	# --- W: mass-weighted distribution must REVERSE with the swing.
	var stats := {}
	for entry in [["+X", plus], ["-X", minus]]:
		var label: String = entry[0]
		var ctx: BloodContext = entry[1]
		var rel := BloodRelease.make(ctx, 0.9, 0.5)
		rel.tissue_mix = (load(RESERVOIR) as ReservoirConfig).tissue_mix_for(
			BloodTypes.DamageType.BLUNT
		)
		var pattern := blood.pattern_for_test(rel)

		var travel_x := 0.0
		var travel_n := 0
		var local_n := 0
		var chunk_x := 0.0
		var chunk_n := 0
		var thick_x := 0.0
		var thick_n := 0
		var lateral := 0.0
		for i in N:
			var u := float(i) / float(N)
			var s := blood.sample_pattern_for_test(rel, BloodTypes.Layer.MEDIUM, u, pattern)
			var d: Vector3 = s["dir"]
			var sp: float = s["speed"]
			if sp < 0.3:
				local_n += 1
			else:
				# Mass-weighted by speed: faster material carries further and
				# dominates the visible trail.
				travel_x += d.x * sp
				travel_n += 1
				lateral += absf(d.z)
		for i in N:
			var u := float(i) / float(N)
			pattern.material_class = int(BloodTypes.Tissue.FLESH)
			var s := blood.sample_pattern_for_test(rel, BloodTypes.Layer.LARGE, u, pattern)
			if s["speed"] > 0.3:
				chunk_x += (s["dir"] as Vector3).x
				chunk_n += 1
			pattern.material_class = int(BloodTypes.Tissue.THICK_BLOOD)
			var t := blood.sample_pattern_for_test(rel, BloodTypes.Layer.MEDIUM, u, pattern)
			if t["speed"] > 0.3:
				thick_x += (t["dir"] as Vector3).x
				thick_n += 1
		pattern.material_class = -1
		stats[label] = {
			"travel_x": travel_x / maxf(float(travel_n), 1.0),
			"local": local_n,
			"chunk_x": chunk_x / maxf(float(chunk_n), 1.0),
			"thick_x": thick_x / maxf(float(thick_n), 1.0),
			"lateral": lateral / maxf(float(travel_n), 1.0),
		}

	var p: Dictionary = stats["+X"]
	var m: Dictionary = stats["-X"]
	printerr("  [blunt +X] travel %.3f chunks %.3f thick %.3f lateral %.3f local %d"
		% [p["travel_x"], p["chunk_x"], p["thick_x"], p["lateral"], p["local"]])
	printerr("  [blunt -X] travel %.3f chunks %.3f thick %.3f lateral %.3f local %d"
		% [m["travel_x"], m["chunk_x"], m["thick_x"], m["lateral"], m["local"]])

	_check(
		p["travel_x"] > 0.35 and m["travel_x"] < -0.35,
		"BLUNT travelling material reverses with the swing (%.3f vs %.3f)"
			% [p["travel_x"], m["travel_x"]]
	)
	_check(
		p["chunk_x"] > 0.3 and m["chunk_x"] < -0.3,
		"large chunks reverse with the swing (%.3f vs %.3f)" % [p["chunk_x"], m["chunk_x"]]
	)
	_check(
		p["thick_x"] > 0.35 and m["thick_x"] < -0.35,
		"THICK_BLOOD reverses with the swing (%.3f vs %.3f)"
			% [p["thick_x"], m["thick_x"]]
	)
	# --- O: the impact site must survive the directional work.
	_check(
		int(p["local"]) > N / 8,
		"a substantial local impact zone remains in both directions (%d)" % p["local"]
	)
	# --- P: broad, not a ballistic beam.
	_check(
		p["lateral"] > 0.2,
		"BLUNT keeps a wide lateral spread - a thrown volume, not a beam (%.3f)"
			% p["lateral"]
	)

	# --- Fat should scatter more than thick blood: material classes differ.
	var rel2 := BloodRelease.make(plus, 0.9, 0.5)
	var pat2 := blood.pattern_for_test(rel2)
	var fat_x := 0.0
	var thick2_x := 0.0
	for i in N:
		var u := float(i) / float(N)
		pat2.material_class = int(BloodTypes.Tissue.FAT)
		fat_x += (blood.sample_pattern_for_test(rel2, BloodTypes.Layer.LARGE, u, pat2)["dir"] as Vector3).x
		pat2.material_class = int(BloodTypes.Tissue.THICK_BLOOD)
		thick2_x += (blood.sample_pattern_for_test(rel2, BloodTypes.Layer.LARGE, u, pat2)["dir"] as Vector3).x
	pat2.material_class = -1
	_check(
		thick2_x > fat_x,
		"THICK_BLOOD follows the blow harder than FAT does (%.1f vs %.1f)"
			% [thick2_x / N, fat_x / N]
	)

	# --- Surface consequence: the contamination centroid must shift too.
	var centroids := {}
	for entry in [["+X", Vector3(1, 0, 0)], ["-X", Vector3(-1, 0, 0)]]:
		var b2 := _make_blood()
		await _tick(2)
		var r := _reservoir()
		await _tick(1)
		var ctx := _ctx(BloodTypes.DamageType.BLUNT, true, Vector3(0, 1.7, 0))
		ctx.weapon_velocity_ws = (entry[1] as Vector3) * 9.0
		ctx.penetration_direction_ws = ((entry[1] as Vector3) + Vector3(0, 0, -0.45)).normalized()
		ctx.swing_plane_normal_ws = (entry[1] as Vector3).cross(Vector3(0, 0, -1)).normalized()
		b2.release(r.withdraw(ctx))
		await _tick(300)
		centroids[entry[0]] = b2.surface_centroid_for_test()
		b2.queue_free()
		await _tick(2)

	var cp: Vector3 = centroids["+X"]
	var cm: Vector3 = centroids["-X"]
	printerr("  [blunt surface centroid] +X %.2v   -X %.2v" % [cp, cm])
	_check(
		cp.x > cm.x + 0.3,
		"the surface contamination centroid shifts with the swing (%.2f vs %.2f)"
			% [cp.x, cm.x]
	)
	blood.queue_free()
	await _tick(2)
