extends Node3D

## Phase 2.3: rendered stain correctness.
##
##     godot --headless --path . res://tests/blood_phase23_test.tscn
##
## The audit found the logical system producing far more contamination than the
## frame ever showed. These checks follow the value all the way to the transform
## and custom data that reach the MultiMesh - not to the enum that was chosen.
##
## Pixels themselves are checked by eye in tests/blood_render_fixture.tscn,
## which is windowed on purpose. Nothing here claims the result looks right.

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
		[Vector3(80, 20, 1), Vector3(0, 10, -4.0)],
		[Vector3(1, 20, 80), Vector3(-16, 10, 0)],
		[Vector3(80, 1, 80), Vector3(0, 11.0, 0)],
	]:
		var s := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = spec[0]
		s.shape = b
		s.position = spec[1]
		body.add_child(s)
	add_child(body)


func _run() -> void:
	await _atlas_selection()
	await _dimension_contract()
	await _footprint_calibration()
	await _size_distribution()
	await _coverage_telemetry()
	await _fallback_distribution()
	await _runoff_continuity()
	await _soak_base()
	await _aftermath_and_readability()
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
	# add_child() runs _ready synchronously, so the layers exist by now. Arming
	# this via the ready signal would be too late - the signal has already fired.
	b.record_stain_writes_for_test()
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
# 1. Atlas selection actually reaches the GPU
# --------------------------------------------------------------------------

func _atlas_selection() -> void:
	var blood := _make_blood()
	await _tick(2)
	var profile: BloodProfile = load("res://data/blood/blood_ballistic.tres")

	# The material must be one that CAN read per-instance data at all. A
	# StandardMaterial3D cannot, which is the entire bug: every stain sampled
	# atlas cell (0,0) = TINY_DROP no matter what shape was chosen.
	var layer: BloodMultiMeshLayer = blood.layer_for_test(BloodTypes.Layer.SURFACE)
	var mat := layer.material_override
	_check(
		mat is ShaderMaterial,
		"the stain layer uses a ShaderMaterial, which can read INSTANCE_CUSTOM"
	)
	if mat is ShaderMaterial:
		_check(
			(mat as ShaderMaterial).shader != null,
			"the stain shader is loaded"
		)
		_check(
			(mat as ShaderMaterial).get_shader_parameter("atlas") != null,
			"the atlas texture is bound to the shader"
		)

	# Every variant must reach its own distinct cell.
	var seen := {}
	var slots: Array[int] = []
	for shape in BloodTypes.STAIN_COUNT:
		# Use the slot the allocator ACTUALLY handed out. Assuming 0..6 is wrong:
		# prewarm has already cycled the free list, so the written slots are not
		# the first indices.
		slots.append(
			blood.place_variant_for_test(profile, Vector3(shape * 2.0, 0.0, 0.0), shape, 0.3)
		)
	await _tick(1)
	for slot in slots:
		var custom: Color = blood.stain_custom_for_test(slot)
		seen["%d,%d" % [int(custom.r), int(custom.g)]] = true
	_check(
		seen.size() == BloodTypes.STAIN_COUNT,
		"all %d variants reach DISTINCT atlas cells (%d distinct)"
			% [BloodTypes.STAIN_COUNT, seen.size()]
	)

	# And the cells must be spread over the grid, not all column 0 row 0.
	var first: Color = blood.stain_custom_for_test(slots[0])
	var last: Color = blood.stain_custom_for_test(slots[slots.size() - 1])
	printerr(
		"  [atlas cells] first (%d,%d) last (%d,%d)"
		% [int(first.r), int(first.g), int(last.r), int(last.g)]
	)
	# floorf() on the row: its fraction carries the impact-bloom birth stamp, so
	# comparing the raw float would compare birth times, not atlas cells.
	_check(
		not (is_equal_approx(first.r, last.r)
			and is_equal_approx(floorf(first.g), floorf(last.g))),
		"the first and last variants do NOT share a cell"
	)
	blood.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# 2. Radius / diameter contract
# --------------------------------------------------------------------------

func _dimension_contract() -> void:
	var blood := _make_blood()
	await _tick(2)
	var profile: BloodProfile = load("res://data/blood/blood_ballistic.tres")

	# Part 17: the MultiMesh must not lose scale. Ask for a known visible
	# diameter and read the transform that actually landed in the buffer.
	var pooled := int(BloodTypes.Stain.POOLED)
	var want := 0.40
	var slot := blood.place_variant_for_test(profile, Vector3(0, 0, 0), pooled, want)
	await _tick(1)
	var xf: Transform3D = blood.stain_transform_for_test(slot)
	var occ: Vector2 = blood.atlas_occupancy(pooled)
	var quad_width := xf.basis.x.length()
	var visible := quad_width * occ.x
	printerr(
		"  [dimension] asked %.3f m ink | quad %.3f m | occupancy %.2f | ink %.3f m"
		% [want, quad_width, occ.x, visible]
	)
	_check(
		absf(visible - want) < want * 0.12,
		"the transform that reached the MultiMesh renders the asked-for ink (%.3f vs %.3f)"
			% [visible, want]
	)
	# The quad must be WIDER than the requested ink, never narrower: the old code
	# scaled a unit quad by the RADIUS, giving a quad of half the diameter, and
	# then the ink shrank it again.
	_check(
		quad_width > want,
		"the quad is wider than the ink it must show (%.3f > %.3f)" % [quad_width, want]
	)

	# The contract, stated directly: a unit quad scaled by N is N wide.
	var slot2 := blood.place_variant_for_test(profile, Vector3(4, 0, 0), pooled, 0.80)
	await _tick(1)
	var big: Transform3D = blood.stain_transform_for_test(slot2)
	_check(
		big.basis.x.length() > quad_width * 1.8,
		"doubling the requested ink roughly doubles the quad (%.3f vs %.3f)"
			% [big.basis.x.length(), quad_width]
	)
	blood.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# 3. Occupancy measurement and calibration
# --------------------------------------------------------------------------

func _footprint_calibration() -> void:
	var blood := _make_blood()
	await _tick(2)

	var worst := 1.0
	for shape in BloodTypes.STAIN_COUNT:
		var occ: Vector2 = blood.atlas_occupancy(shape)
		var fill := blood.atlas_fill(shape)
		_check(
			occ.x > 0.05 and occ.y > 0.05 and occ.x <= 1.0 and occ.y <= 1.0,
			"variant %d has a measured ink extent (%.2f x %.2f, fill %.3f)"
				% [shape, occ.x, occ.y, fill]
		)
		worst = minf(worst, occ.x)
		# The calibration must invert the occupancy.
		var quad: Vector2 = blood.quad_for_visible_diameter(0.25, shape)
		_check(
			absf(quad.x * occ.x - 0.25) < 0.001,
			"variant %d: quad x occupancy returns the requested ink (%.3f)"
				% [shape, quad.x * occ.x]
		)

	# The audit measured TINY_DROP at ~8.5% of its cell. If that is still true,
	# the measurement is reading the real texture rather than a constant.
	var tiny := blood.atlas_fill(int(BloodTypes.Stain.TINY_DROP))
	printerr("  [occupancy] TINY_DROP fill %.3f, narrowest ink extent %.2f" % [tiny, worst])
	_check(
		tiny < 0.2,
		"TINY_DROP is measured as a small fraction of its cell (%.3f)" % tiny
	)
	_check(
		blood.atlas_fill(int(BloodTypes.Stain.POOLED)) > tiny * 3.0,
		"POOLED is measured as far denser than TINY_DROP"
	)
	blood.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# 4. Size distribution, by FINAL VISIBLE width
# --------------------------------------------------------------------------

func _size_distribution() -> void:
	for family in [
		BloodTypes.DamageType.BALLISTIC, BloodTypes.DamageType.BLUNT,
		BloodTypes.DamageType.HIGH_ENERGY,
	]:
		var blood := _make_blood()
		await _tick(2)
		var r := _reservoir()
		await _tick(1)
		var ctx := BloodContext.make(
			family, Vector3(0, 1.7, 0), Vector3(0, 0, -1), BloodTypes.BodyRegion.TORSO, 1.0
		)
		ctx.is_kill = true
		if family == BloodTypes.DamageType.BLUNT:
			ctx.weapon_velocity_ws = Vector3(1, 0, 0) * 9.0
		if family == BloodTypes.DamageType.HIGH_ENERGY:
			ctx.explosion_direction_ws = Vector3(0, 0.2, -1).normalized()
		blood.release(r.withdraw(ctx))
		await _tick(360)

		var dist: Dictionary = blood.size_distribution_for_test()
		var pct: Dictionary = blood.stain_percentiles_for_test()
		var name: String = BloodTypes.DamageType.keys()[int(family)]
		var total: int = pct["count"]
		var tiny: int = dist["<5cm"]
		var tiny_share := 100.0 * float(tiny) / maxf(float(total), 1.0)
		printerr(
			"  [%s] %d marks | median %.3f m | p90 %.3f m | <5cm %.0f%% | %s"
			% [name, total, pct["median"], pct["p90"], tiny_share, str(dist)]
		)
		# The audit found 90-93%% of rendered stains under 5 cm wide. This is not
		# a hardcoded target - it asserts the sub-5cm share is no longer almost
		# everything, which is what "the arena looks clean" measured as.
		_check(
			tiny_share < 75.0,
			"%s: the aftermath is no longer almost entirely sub-5cm marks (%.0f%%)"
				% [name, tiny_share]
		)
		_check(
			pct["median"] > 0.04,
			"%s: the median mark is readable at FPS distance (%.3f m)"
				% [name, pct["median"]]
		)
		_check(
			pct["p90"] > 0.12,
			"%s: the largest marks are substantial (p90 %.3f m)" % [name, pct["p90"]]
		)
		blood.queue_free()
		await _tick(2)


# --------------------------------------------------------------------------
# 5. Coverage telemetry must be a union, not a sum
# --------------------------------------------------------------------------

func _coverage_telemetry() -> void:
	var blood := _make_blood()
	await _tick(2)
	var profile: BloodProfile = load("res://data/blood/blood_blunt.tres")

	# Stack many marks on ONE spot. Nominal summed area grows without limit;
	# unique coverage must not, because it is the same square metre every time.
	for i in 60:
		blood.place_stain_for_test(
			profile, Vector3(0, 0.0, 0), Vector3.UP, Vector3(0, -1, 0), 0.03
		)
	var stacked_unique := blood.unique_coverage_for_test()
	var stacked_nominal: float = (blood.mass_ledger())["nominal_summed_area"]
	printerr(
		"  [coverage] 60 marks stacked on one point: nominal %.2f m2, unique %.2f m2"
		% [stacked_nominal, stacked_unique]
	)
	_check(
		stacked_unique < stacked_nominal,
		"unique coverage is smaller than the nominal sum when marks overlap (%.2f < %.2f)"
			% [stacked_unique, stacked_nominal]
	)
	# All 60 land on one point, so the union should be about ONE soaked base
	# footprint, not sixty of them. Bounded by soak_base_max_radius.
	_check(
		stacked_unique < 4.0,
		"60 marks on one spot cover about one patch, not the room (%.2f m2)"
			% stacked_unique
	)

	# Spread the same marks out and unique coverage must rise.
	var spread := _make_blood()
	await _tick(2)
	for i in 60:
		spread.place_stain_for_test(
			profile, Vector3(float(i) * 0.9 - 27.0, 0.0, 6.0), Vector3.UP,
			Vector3(0, -1, 0), 0.03
		)
	var spread_unique := spread.unique_coverage_for_test()
	printerr("  [coverage] the same 60 marks spread out: unique %.2f m2" % spread_unique)
	_check(
		spread_unique > stacked_unique * 3.0,
		"spreading the same marks raises unique coverage (%.2f vs %.2f)"
			% [spread_unique, stacked_unique]
	)
	_check(
		(blood.mass_ledger()).has("approx_unique_visible_coverage"),
		"the ledger reports approximate unique visible coverage"
	)
	blood.queue_free()
	spread.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# 6. Coarse fallback must not stack on one point
# --------------------------------------------------------------------------

func _fallback_distribution() -> void:
	# A kill in open space, far from any wall, so most directional probes miss
	# and the fallback path is what places the material. That is precisely the
	# case the audit caught stacking nine deposits on one spot.
	var blood := _make_blood()
	await _tick(2)
	var r := _reservoir()
	await _tick(1)
	var ctx := BloodContext.make(
		BloodTypes.DamageType.HIGH_ENERGY, Vector3(0, 6.0, 20.0), Vector3(0, 1, 0),
		BloodTypes.BodyRegion.TORSO, 1.0
	)
	ctx.is_kill = true
	ctx.explosion_direction_ws = Vector3(0, 1, 0)
	blood.release(r.withdraw(ctx))
	await _tick(4)

	var coverage := blood.unique_coverage_for_test()
	printerr("  [fallback] open-air kill spread over %.2f m2 of unique floor" % coverage)
	# If every fallback dropped from the same origin, the whole event would sit
	# inside roughly one cluster's footprint.
	_check(
		coverage > 1.0,
		"coarse fallback spreads over an area, not one point (%.2f m2)" % coverage
	)
	blood.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# 7. Runoff continuity
# --------------------------------------------------------------------------

func _runoff_continuity() -> void:
	var blood := _make_blood()
	await _tick(2)
	var profile: BloodProfile = load("res://data/blood/blood_high_energy.tres")
	var s: BloodSettings = blood.settings

	# The segment a rivulet lays must be long enough to bridge the distance it
	# travelled since the last one. Below 1.0 it is a dotted line, which is what
	# the audit measured: 3.5 cm marks with 9.7 cm gaps.
	_check(
		s.runoff_overlap > 1.0,
		"runoff segments overreach the gap between them (%.2f)" % s.runoff_overlap
	)

	blood.place_stain_for_test(
		profile, Vector3(0, 6.0, -3.49), Vector3(0, 0, 1), Vector3(0, 0, -1), 0.06
	)
	await _tick(24) # Allow the mass/retention start delay.
	_check(int((blood.live_counts())["runoff"]) > 0, "a heavy wall deposit starts running")

	var before: int = (blood.live_counts())["surface"]
	await _tick(120)
	var after: int = (blood.live_counts())["surface"]
	var laid := after - before
	# Widths of the marks it laid, from the size telemetry.
	var pct: Dictionary = blood.stain_percentiles_for_test()
	printerr(
		"  [runoff] %d segments laid, median visible length %.3f m, step %.3f m"
		% [laid, pct["median"], s.runoff_step]
	)
	_check(laid > 3, "the rivulet lays a run of segments (%d)" % laid)
	_check(
		pct["median"] >= s.runoff_step,
		"each segment is at least as long as the gap it must cover (%.3f >= %.3f)"
			% [pct["median"], s.runoff_step]
	)
	await _tick(800)
	_check(
		int((blood.live_counts())["runoff"]) == 0,
		"and it still terminates"
	)
	blood.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# 8. Soak bases are POOLED, not giant dots
# --------------------------------------------------------------------------

func _soak_base() -> void:
	var blood := _make_blood()
	await _tick(2)
	var profile: BloodProfile = load("res://data/blood/blood_blunt.tres")
	var before := blood.soak_bases_for_test()

	for i in 40:
		blood.place_stain_for_test(
			profile, Vector3(3.0 + randf_range(-0.3, 0.3), 0.0, 3.0 + randf_range(-0.3, 0.3)),
			Vector3.UP, Vector3(0.2, -1, 0.1).normalized(), 0.02
		)
		await _tick(1)
	var bases := blood.soak_bases_for_test()
	_check(bases > before, "a hammered patch earns soaked bases (%d)" % bases)

	# Find a slot carrying the POOLED cell and confirm it is genuinely large.
	var pooled := int(BloodTypes.Stain.POOLED)
	var want_r := float(pooled % BloodSystem.ATLAS_COLS)
	var want_g := float(pooled / BloodSystem.ATLAS_COLS)
	var found := -1
	var widest := 0.0
	for slot in 400:
		var c: Color = blood.stain_custom_for_test(slot)
		# floorf: the row fraction is the bloom birth stamp, not part of the cell.
		if is_equal_approx(c.r, want_r) and is_equal_approx(floorf(c.g), want_g):
			var w: float = blood.stain_transform_for_test(slot).basis.x.length()
			if w > widest:
				widest = w
				found = slot
	printerr("  [soak] widest POOLED base quad %.3f m (slot %d)" % [widest, found])
	_check(found >= 0, "soaked bases are written with the POOLED atlas cell")
	_check(
		widest > 0.25,
		"a soaked base is a broad region, not a dot (%.3f m quad)" % widest
	)
	blood.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# 9. Full aftermath report and screen-space readability (Parts 21, 22)
# --------------------------------------------------------------------------

func _aftermath_and_readability() -> void:
	# Part 22: a geometrically correct mark that is one pixel wide on screen is
	# still invisible. Check the arithmetic itself first.
	var px := BloodSystem.screen_pixels_for(0.20, 10.0, 90.0, 1080.0)
	_check(
		absf(px - 10.8) < 0.5,
		"the screen-space estimate is arithmetically right (20 cm at 10 m = %.1f px)" % px
	)

	for family in [
		BloodTypes.DamageType.BALLISTIC, BloodTypes.DamageType.BLUNT,
		BloodTypes.DamageType.HIGH_ENERGY,
	]:
		var blood := _make_blood()
		await _tick(2)
		var r := _reservoir()
		await _tick(1)
		var ctx := BloodContext.make(
			family, Vector3(0, 1.7, -2.0), Vector3(0, 0, -1),
			BloodTypes.BodyRegion.TORSO, 1.0
		)
		ctx.is_kill = true
		if family == BloodTypes.DamageType.BLUNT:
			ctx.weapon_velocity_ws = Vector3(1, 0, 0) * 9.0
		if family == BloodTypes.DamageType.HIGH_ENERGY:
			ctx.explosion_direction_ws = Vector3(0, 0.2, -1).normalized()
		blood.release(r.withdraw(ctx))
		await _tick(360)

		var a: Dictionary = blood.aftermath_report_for_test()
		var name: String = BloodTypes.DamageType.keys()[int(family)]
		printerr("  [%s AFTERMATH]" % name)
		printerr("      stains %d | nominal %.1f m2 | UNIQUE %.1f m2"
			% [a["stain_count"], a["nominal_summed_area"],
				a["approx_unique_visible_coverage"]])
		printerr("      visible width: median %.3f m | p90 %.3f m"
			% [a["median_visible_width"], a["p90_visible_width"]])
		printerr("      soak bases %d | widest base quad %.2f m"
			% [a["soak_base_count"], a["soak_base_widest_quad"]])
		printerr("      mass floor %.3f | wall %.3f | ceiling %.3f"
			% [a["surface_mass_floor"], a["surface_mass_wall"],
				a["surface_mass_ceiling"]])
		printerr("      readability: median %.0f px at 4 m, %.0f px at 12 m; p90 %.0f px at 12 m"
			% [a["median_px_at_4m"], a["median_px_at_12m"], a["p90_px_at_12m"]])

		# Physical fine droplets now have causal small stains. Their numerous
		# detail marks can legitimately lower the median. Check the larger marks
		# that communicate contamination at range; the material fixture captures
		# the whole frame so this percentile is not mistaken for visual proof.
		_check(
			a["p90_px_at_12m"] > 3.0,
			"%s: larger contamination marks remain readable at 12 m (%.0f px)"
				% [name, a["p90_px_at_12m"]]
		)
		var close_p90 := BloodSystem.screen_pixels_for(a["p90_visible_width"], 4.0)
		_check(
			close_p90 > 12.0,
			"%s: larger marks are clearly readable at 4 m (%.0f px)"
				% [name, close_p90]
		)
		# Unique coverage must be a real patch of room, and must not exceed the
		# nominal sum - it is a union of the same marks.
		_check(
			a["approx_unique_visible_coverage"] > 2.0,
			"%s: the event covers a real area of the chamber (%.1f m2)"
				% [name, a["approx_unique_visible_coverage"]]
		)
		_check(
			a["approx_unique_visible_coverage"] <= a["nominal_summed_area"],
			"%s: unique coverage never exceeds the nominal sum" % name
		)
		blood.queue_free()
		await _tick(2)
