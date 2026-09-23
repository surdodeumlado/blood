extends Node3D

## Phase 2 validation: mass, admission, allocator, patterns, wounds, tissue.
##
##     godot --headless --path . res://tests/blood_phase2_test.tscn
##
## Lives in its own scene rather than growing the movement smoke test, which is
## already long and spends most of its runtime on real-time awaits.
##
## IMPORTANT: passing these does NOT mean the blood looks right. Every check
## here is structural - that the geometry of four families genuinely differs,
## that mass is accounted for, that budgets hold. Whether the result READS as
## four different physical events is a playtest question and nothing in this
## file is allowed to claim it.

const SETTINGS := "res://data/blood/blood_settings.tres"
const RESERVOIR := "res://data/blood/reservoir_defaults.tres"

var _failures: Array[String] = []
var _checks := 0
var _blood: BloodSystem


func _ready() -> void:
	_build_world()
	_run()


func _build_world() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	body.add_child(shape)
	# Walls, so droplets have something vertical to stain.
	for spec in [
		[Vector3(200, 12, 1), Vector3(0, 6, -30)],
		[Vector3(200, 12, 1), Vector3(0, 6, 30)],
	]:
		var w := CollisionShape3D.new()
		var wb := BoxShape3D.new()
		wb.size = spec[0]
		w.shape = wb
		w.position = spec[1]
		body.add_child(w)
	add_child(body)


func _run() -> void:
	await _reservoir_tests()
	await _mass_and_quality()
	await _no_convergence()
	await _allocator()
	await _pattern_geometry()
	await _tissue()
	await _wounds()
	await _contamination()
	await _budgets()
	await _phase1_regression()
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


func _ctx(
	family: BloodTypes.DamageType, kill: bool,
	region := BloodTypes.BodyRegion.TORSO, energy := 1.0
) -> BloodContext:
	var c := BloodContext.make(
		family, Vector3(0, 1.6, 0), Vector3(0, 0, -1), region, energy
	)
	c.is_kill = kill
	return c


func _new_reservoir() -> BloodReservoir:
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
# 1. Reservoir
# --------------------------------------------------------------------------

func _reservoir_tests() -> void:
	var r := _new_reservoir()
	await _tick(2)
	_check(
		is_equal_approx(r.remaining_blood, 1.0),
		"reservoir starts full (%.2f)" % r.remaining_blood
	)

	# Successive hits on the same body draw from a shrinking pool: the second
	# hit MUST be smaller than the first. That is the whole point of a reservoir.
	var first := r.withdraw(_ctx(BloodTypes.DamageType.BALLISTIC, false))
	var second := r.withdraw(_ctx(BloodTypes.DamageType.BALLISTIC, false))
	_check(
		second.blood_mass < first.blood_mass,
		"a second hit draws less than the first (%.4f < %.4f)"
			% [second.blood_mass, first.blood_mass]
	)
	_check(
		r.remaining_blood < 1.0 and r.remaining_blood > 0.0,
		"the reservoir is depleted by hits but not emptied (%.3f)" % r.remaining_blood
	)

	# A kill is categorically larger than a wounding hit.
	var r2 := _new_reservoir()
	await _tick(1)
	var hit := r2.withdraw(_ctx(BloodTypes.DamageType.BALLISTIC, false))
	var r3 := _new_reservoir()
	await _tick(1)
	var kill := r3.withdraw(_ctx(BloodTypes.DamageType.BALLISTIC, true))
	_check(
		kill.blood_mass > hit.blood_mass * 4.0,
		"a kill releases far more than a hit (%.3f vs %.3f)"
			% [kill.blood_mass, hit.blood_mass]
	)

	# Family scaling must survive into the released mass.
	var masses := {}
	for family in [
		BloodTypes.DamageType.BALLISTIC, BloodTypes.DamageType.SLASHING,
		BloodTypes.DamageType.BLUNT, BloodTypes.DamageType.HIGH_ENERGY,
	]:
		var rr := _new_reservoir()
		await _tick(1)
		masses[family] = rr.withdraw(_ctx(family, true)).blood_mass
	_check(
		masses[BloodTypes.DamageType.BLUNT] > masses[BloodTypes.DamageType.BALLISTIC],
		"a maul kill releases more mass than a bullet kill (%.3f > %.3f)"
			% [masses[BloodTypes.DamageType.BLUNT], masses[BloodTypes.DamageType.BALLISTIC]]
	)
	_check(
		masses[BloodTypes.DamageType.HIGH_ENERGY] >= masses[BloodTypes.DamageType.BLUNT],
		"an explosive kill is the largest release (%.3f)"
			% masses[BloodTypes.DamageType.HIGH_ENERGY]
	)

	# A corpse still has something to give, but not unlimited.
	var r4 := _new_reservoir()
	await _tick(1)
	r4.withdraw(_ctx(BloodTypes.DamageType.HIGH_ENERGY, true))
	var post := r4.withdraw(_ctx(BloodTypes.DamageType.BALLISTIC, false))
	_check(
		post.blood_mass >= 0.0 and r4.has_material(),
		"a corpse keeps a bounded post-mortem allowance"
	)


# --------------------------------------------------------------------------
# 2. Mass model, and quality independence
# --------------------------------------------------------------------------

func _mass_and_quality() -> void:
	var blood := _make_blood()
	await _tick(2)

	# THE quality rule: a tier changes representation and NEVER the reservoir.
	var results := {}
	for tier in [
		BloodTypes.Quality.LOW, BloodTypes.Quality.HIGH, BloodTypes.Quality.INSANE
	]:
		var r := _new_reservoir()
		await _tick(1)
		blood.settings.quality = tier
		var rel := r.withdraw(_ctx(BloodTypes.DamageType.BALLISTIC, true))
		blood.release(rel)
		await _tick(1)
		results[tier] = {
			"mass": rel.blood_mass,
			"remaining": r.remaining_blood,
			"micro": blood.last_particles_spawned,
		}
	_check(
		is_equal_approx(
			results[BloodTypes.Quality.LOW]["mass"], results[BloodTypes.Quality.INSANE]["mass"]
		),
		"quality does not change released MASS (%.4f vs %.4f)"
			% [results[BloodTypes.Quality.LOW]["mass"],
				results[BloodTypes.Quality.INSANE]["mass"]]
	)
	_check(
		is_equal_approx(
			results[BloodTypes.Quality.LOW]["remaining"],
			results[BloodTypes.Quality.INSANE]["remaining"]
		),
		"quality does not change reservoir consumption"
	)
	_check(
		results[BloodTypes.Quality.INSANE]["micro"] > results[BloodTypes.Quality.LOW]["micro"] * 3,
		"INSANE draws far more representatives than LOW (%d vs %d)"
			% [results[BloodTypes.Quality.INSANE]["micro"],
				results[BloodTypes.Quality.LOW]["micro"]]
	)
	blood.settings.quality = BloodTypes.Quality.INSANE
	blood.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# 3. The 22-droplet convergence must be gone
# --------------------------------------------------------------------------

func _no_convergence() -> void:
	var blood := _make_blood()
	await _tick(2)
	var counts := {}
	var micro := {}
	for family in [
		BloodTypes.DamageType.BALLISTIC, BloodTypes.DamageType.SLASHING,
		BloodTypes.DamageType.BLUNT, BloodTypes.DamageType.HIGH_ENERGY,
	]:
		blood.clear_all()
		await _tick(2)
		var r := _new_reservoir()
		await _tick(1)
		blood.release(r.withdraw(_ctx(family, true)))
		counts[family] = blood.last_droplets_spawned
		micro[family] = blood.last_particles_spawned
		await _tick(1)

	var values: Array = counts.values()
	var lo: int = values.min()
	var hi: int = values.max()
	_check(
		hi > lo,
		"families no longer converge on one droplet count (%s)" % str(counts)
	)
	_check(
		hi >= lo * 2,
		"the spread between families is substantial (%d..%d)" % [lo, hi]
	)
	_check(
		counts[BloodTypes.DamageType.HIGH_ENERGY] > 22,
		"a grenade kill is no longer capped at 22 physical droplets (%d)"
			% counts[BloodTypes.DamageType.HIGH_ENERGY]
	)

	# A body hit and a catastrophic kill must not saturate to similar output.
	blood.clear_all()
	await _tick(2)
	var r1 := _new_reservoir()
	await _tick(1)
	blood.release(r1.withdraw(_ctx(BloodTypes.DamageType.BALLISTIC, false)))
	var body_micro := blood.last_particles_spawned
	await _tick(1)
	blood.clear_all()
	await _tick(2)
	var r2 := _new_reservoir()
	await _tick(1)
	blood.release(r2.withdraw(_ctx(BloodTypes.DamageType.BALLISTIC, true, BloodTypes.BodyRegion.HEAD)))
	var head_micro := blood.last_particles_spawned
	_check(
		head_micro > body_micro * 4,
		"a headshot kill is dramatically bigger than a body shot (%d vs %d)"
			% [head_micro, body_micro]
	)
	blood.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# 4. Allocator: free slots first, never overwrite live material needlessly
# --------------------------------------------------------------------------

func _allocator() -> void:
	var layer := BloodMultiMeshLayer.new()
	add_child(layer)
	var mesh := QuadMesh.new()
	layer.setup(mesh, StandardMaterial3D.new(), 8)

	var slots: Array[int] = []
	for i in 8:
		slots.append(layer.acquire(true))
	_check(layer.live() == 8, "layer fills to capacity (%d)" % layer.live())
	_check(layer.evicted == 0, "filling a cold pool evicts nothing")

	# Free three in the MIDDLE, then allocate three: they must come from the
	# free list, not from overwriting live slots at some rolling index.
	layer.release(slots[2])
	layer.release(slots[5])
	layer.release(slots[6])
	var before_evicted := layer.evicted
	var reused: Array[int] = []
	for i in 3:
		reused.append(layer.acquire(true))
	_check(
		layer.evicted == before_evicted,
		"free slots are reused before anything live is evicted (%d evictions)"
			% (layer.evicted - before_evicted)
	)
	reused.sort()
	var expected: Array[int] = [2, 5, 6]
	_check(
		reused == expected,
		"the exact freed slots came back (%s)" % str(reused)
	)

	# Genuinely full: eviction is now allowed, and must take the OLDEST.
	var evicted_slot := layer.acquire(true)
	_check(layer.evicted == before_evicted + 1, "a truly full layer evicts exactly once")
	_check(evicted_slot >= 0, "a full layer still serves a request when allowed to evict")

	# A layer that may not evict refuses instead of destroying live material.
	var refused := layer.acquire(false)
	_check(refused == -1, "a non-evicting request is refused when full")
	_check(layer.rejected > 0, "rejections are counted (%d)" % layer.rejected)
	layer.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# 5. THE ACCEPTANCE CORE: four families, four different geometries
# --------------------------------------------------------------------------

func _pattern_geometry() -> void:
	var blood := _make_blood()
	await _tick(2)
	blood.seed_for_test(4242)
	const N := 900

	var stats := {}
	for family in [
		BloodTypes.DamageType.BALLISTIC, BloodTypes.DamageType.SLASHING,
		BloodTypes.DamageType.BLUNT, BloodTypes.DamageType.HIGH_ENERGY,
	]:
		var ctx := _ctx(family, true)
		var axis := Vector3(0, 0, -1)
		if family == BloodTypes.DamageType.SLASHING:
			# A horizontal swing: plane normal is up, blade travels along +X.
			ctx.swing_plane_normal_ws = Vector3.UP
			ctx.penetration_direction_ws = Vector3(1, 0, 0)
			axis = Vector3(1, 0, 0)
		if family == BloodTypes.DamageType.HIGH_ENERGY:
			ctx.explosion_direction_ws = Vector3(0, 0, -1)
		var rel := BloodRelease.make(ctx, 0.6, 0.3)
		var pattern := blood.pattern_for_test(rel)

		var axial := 0.0
		var out_of_plane := 0.0
		var origin_spread := Vector3.ZERO
		var origins: Array[Vector3] = []
		var speed_near := 0.0
		var speed_near_n := 0
		var speed_far := 0.0
		var speed_far_n := 0
		for i in N:
			var u := float(i) / float(N)
			var s := blood.sample_pattern_for_test(rel, BloodTypes.Layer.MEDIUM, u, pattern)
			var dir: Vector3 = s["dir"]
			axial += absf(dir.dot(axis))
			out_of_plane += absf(dir.dot(Vector3.UP))
			var o: Vector3 = s["origin"]
			origin_spread += Vector3(absf(o.x), absf(o.y), absf(o.z))
			if i % 30 == 0:
				origins.append(o)
			# Speed against angle from the axis, for the blunt shell test.
			var ang := absf(dir.dot(axis))
			if ang > 0.75:
				speed_near += s["speed"]
				speed_near_n += 1
			elif ang < 0.3:
				speed_far += s["speed"]
				speed_far_n += 1
		stats[family] = {
			"axial": axial / N,
			"out_of_plane": out_of_plane / N,
			"origin": origin_spread / N,
			"origins": origins,
			"speed_near": speed_near / maxf(float(speed_near_n), 1.0),
			"speed_far": speed_far / maxf(float(speed_far_n), 1.0),
		}

	var bal: Dictionary = stats[BloodTypes.DamageType.BALLISTIC]
	var slash: Dictionary = stats[BloodTypes.DamageType.SLASHING]
	var blunt: Dictionary = stats[BloodTypes.DamageType.BLUNT]
	var boom: Dictionary = stats[BloodTypes.DamageType.HIGH_ENERGY]

	# --- BALLISTIC: a TRACK. Strongly axial, and much more axial than blunt.
	_check(
		bal["axial"] > 0.75,
		"BALLISTIC is strongly axial - a track, not a ball (%.2f)" % bal["axial"]
	)
	_check(
		bal["axial"] > blunt["axial"] + 0.15,
		"BALLISTIC is far more directional than BLUNT (%.2f vs %.2f)"
			% [bal["axial"], blunt["axial"]]
	)
	# Born along the channel: spread along the axis, not across it.
	var bo: Vector3 = bal["origin"]
	_check(
		bo.z > bo.x * 1.5,
		"BALLISTIC material is born along the wound channel (%.3f along vs %.3f across)"
			% [bo.z, bo.x]
	)

	# --- SLASHING: a FAN. Nearly nothing leaves the swing plane, and the source
	# is spread along the cut rather than sitting at a point.
	_check(
		slash["out_of_plane"] < 0.25,
		"SLASHING stays in the swing plane (mean |dot(up)| %.3f)" % slash["out_of_plane"]
	)
	_check(
		slash["out_of_plane"] < blunt["out_of_plane"] * 0.6,
		"SLASHING is far flatter than BLUNT (%.3f vs %.3f)"
			% [slash["out_of_plane"], blunt["out_of_plane"]]
	)
	var so: Vector3 = slash["origin"]
	_check(
		so.z > 0.05,
		"SLASHING is born spread ALONG the cut, not at a point (%.3f)" % so.z
	)

	# --- BLUNT: a SHELL. Broad, and momentum is spent near the axis - the
	# characteristic a wide ballistic cone can never reproduce.
	_check(
		blunt["speed_near"] > blunt["speed_far"] * 1.8,
		"BLUNT speed collapses toward the rim (%.2f near axis vs %.2f at rim)"
			% [blunt["speed_near"], blunt["speed_far"]]
	)
	_check(
		blunt["axial"] < bal["axial"],
		"BLUNT is broader than BALLISTIC (%.2f < %.2f)" % [blunt["axial"], bal["axial"]]
	)
	var blo: Vector3 = blunt["origin"]
	_check(
		blo.x > bo.x * 2.0,
		"BLUNT is born across a contact patch, not a point (%.3f vs ballistic %.3f)"
			% [blo.x, bo.x]
	)

	# --- EXPLOSIVE: MULTI-ORIGIN. Several distinct rupture points, and the most
	# scattered directions of the four.
	var distinct := 0
	var seen: Array[Vector3] = []
	for o in boom["origins"]:
		var dup := false
		for s2 in seen:
			if s2.distance_to(o) < 0.05:
				dup = true
				break
		if not dup:
			seen.append(o)
			distinct += 1
	_check(
		distinct >= 4,
		"EXPLOSIVE emits from several distinct rupture points (%d)" % distinct
	)
	_check(
		boom["axial"] < bal["axial"],
		"EXPLOSIVE is less axial than BALLISTIC (%.2f < %.2f)"
			% [boom["axial"], bal["axial"]]
	)

	# --- And the summary claim: no two families share a geometric signature.
	var signatures := []
	for f in stats:
		var st: Dictionary = stats[f]
		signatures.append(Vector3(st["axial"], st["out_of_plane"], (st["origin"] as Vector3).x))
	var min_gap := 99.0
	for i in signatures.size():
		for j in range(i + 1, signatures.size()):
			min_gap = minf(min_gap, (signatures[i] as Vector3).distance_to(signatures[j]))
	_check(
		min_gap > 0.08,
		"every pair of families is geometrically distinguishable (closest pair %.3f)"
			% min_gap
	)

	blood.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# 6. Tissue
# --------------------------------------------------------------------------

func _tissue() -> void:
	var cfg: ReservoirConfig = load(RESERVOIR)
	# Every category must be reachable, or the material variety is a lie.
	var seen := {}
	for family in [
		BloodTypes.DamageType.BALLISTIC, BloodTypes.DamageType.SLASHING,
		BloodTypes.DamageType.BLUNT, BloodTypes.DamageType.HIGH_ENERGY,
	]:
		var mix := cfg.tissue_mix_for(family)
		for i in 400:
			seen[TissueDebris.pick(mix, float(i) / 400.0)] = true
	_check(
		seen.size() == 4,
		"all four tissue categories are reachable (%d)" % seen.size()
	)

	# A bullet is nearly pure blood; a maul throws fat and dark tissue.
	var bullet := cfg.tissue_mix_for(BloodTypes.DamageType.BALLISTIC)
	var maul := cfg.tissue_mix_for(BloodTypes.DamageType.BLUNT)
	_check(
		maul[int(BloodTypes.Tissue.FAT)] > bullet[int(BloodTypes.Tissue.FAT)] * 3.0,
		"BLUNT throws far more FAT than BALLISTIC (%.2f vs %.2f)"
			% [maul[int(BloodTypes.Tissue.FAT)], bullet[int(BloodTypes.Tissue.FAT)]]
	)
	_check(
		maul[int(BloodTypes.Tissue.DARK_TISSUE)] > bullet[int(BloodTypes.Tissue.DARK_TISSUE)] * 2.0,
		"BLUNT throws far more DARK_TISSUE than BALLISTIC"
	)

	# The categories must be visually separable, not four shades of the same red.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var flesh := TissueDebris.color_for(BloodTypes.Tissue.FLESH, rng)
	var fat := TissueDebris.color_for(BloodTypes.Tissue.FAT, rng)
	var dark := TissueDebris.color_for(BloodTypes.Tissue.DARK_TISSUE, rng)
	_check(
		fat.g > flesh.g + 0.3 and fat.b > flesh.b + 0.3,
		"FAT is visibly pale against FLESH (fat %.2f/%.2f vs flesh %.2f/%.2f)"
			% [fat.g, fat.b, flesh.g, flesh.b]
	)
	_check(
		dark.r < flesh.r - 0.1,
		"DARK_TISSUE is visibly darker than FLESH (%.2f < %.2f)" % [dark.r, flesh.r]
	)
	_check(
		TissueDebris.build_meshes().size() >= 5,
		"the tissue mesh library has real shape variety (%d)"
			% TissueDebris.build_meshes().size()
	)

	# And tissue must actually reach the world.
	var blood := _make_blood()
	await _tick(2)
	var r := _new_reservoir()
	await _tick(1)
	blood.release(r.withdraw(_ctx(BloodTypes.DamageType.BLUNT, true)))
	await _tick(2)
	_check(
		blood.last_grains_spawned > 0,
		"a maul kill spawns tissue grains (%d)" % blood.last_grains_spawned
	)
	_check(
		blood.last_chunks_spawned > 0,
		"a maul kill spawns large chunks (%d)" % blood.last_chunks_spawned
	)

	# Chunk impacts are bounded: no recursive gore.
	await _tick(140)
	var live: Dictionary = blood.live_counts()
	_check(
		live["large"] <= blood.settings.max_large,
		"solid material stays within its budget (%d/%d)"
			% [live["large"], blood.settings.max_large]
	)
	_check(
		live["solids_settled"] > 0,
		"solids settle and stay on the floor (%d)" % live["solids_settled"]
	)
	blood.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# 7. Wounds
# --------------------------------------------------------------------------

func _wounds() -> void:
	var blood := _make_blood()
	await _tick(2)
	var r := _new_reservoir()
	await _tick(1)
	blood.register_reservoir(r)

	var rel := r.withdraw(_ctx(BloodTypes.DamageType.SLASHING, false))
	var w := r.open_wound(rel)
	_check(w != null, "a slashing hit opens a wound")
	_check(r.wounds.size() == 1, "the wound is held by the victim, not by the blood system")

	if w != null:
		# It must NOT emit every frame - it accumulates and releases discretely.
		var emissions := 0
		var frames := 0
		var before := blood.event_count()
		while frames < 120 and w.alive():
			await _tick(1)
			frames += 1
		emissions = blood.event_count() - before
		_check(
			emissions > 0,
			"the wound releases blood over time (%d discrete events in %d frames)"
				% [emissions, frames]
		)
		_check(
			emissions < frames,
			"the wound does NOT emit every frame (%d events / %d frames)"
				% [emissions, frames]
		)

	# Severity differs by family: a blade opens a worse wound than a bullet.
	var cfg: ReservoirConfig = load(RESERVOIR)
	_check(
		cfg.wound_severity_for(BloodTypes.DamageType.SLASHING)
			> cfg.wound_severity_for(BloodTypes.DamageType.BALLISTIC),
		"a blade opens a worse wound than a bullet (%.2f > %.2f)"
			% [cfg.wound_severity_for(BloodTypes.DamageType.SLASHING),
				cfg.wound_severity_for(BloodTypes.DamageType.BALLISTIC)]
	)

	# A wound follows its victim: moving the body moves where it drips.
	var r2 := _new_reservoir()
	await _tick(1)
	var victim := r2.victim()
	var rel2 := r2.withdraw(_ctx(BloodTypes.DamageType.SLASHING, false))
	var w2 := r2.open_wound(rel2)
	if w2 != null:
		var at_first := w2.position_ws(victim.global_transform)
		victim.global_position += Vector3(5, 0, 0)
		var at_second := w2.position_ws(victim.global_transform)
		_check(
			at_first.distance_to(at_second) > 4.0,
			"a wound is anchored to the VICTIM, so a moving target trails blood"
		)
		# Detached, it finishes where it was told to.
		w2.detach(Vector3(1, 2, 3))
		_check(
			w2.position_ws(victim.global_transform).is_equal_approx(Vector3(1, 2, 3)),
			"a detached wound finishes its life in world space"
		)

	# Remnants keep bleeding with no victim node at all.
	var r3 := _new_reservoir()
	await _tick(1)
	var kill_rel := r3.withdraw(_ctx(BloodTypes.DamageType.BALLISTIC, true, BloodTypes.BodyRegion.HEAD))
	var w3 := r3.open_wound(kill_rel)
	if w3 != null:
		blood.add_remnant(w3, Vector3(0, 1.8, -5))
		var before3 := blood.event_count()
		await _tick(60)
		_check(
			blood.event_count() > before3,
			"a death remnant keeps leaking after the corpse is gone (%d events)"
				% (blood.event_count() - before3)
		)
	blood.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# 8. Contamination
# --------------------------------------------------------------------------

func _contamination() -> void:
	var blood := _make_blood()
	await _tick(2)

	# Physical droplets must actually fly and stain the world, and the arena
	# must remember it.
	for i in 6:
		var r := _new_reservoir()
		await _tick(1)
		var ctx := _ctx(BloodTypes.DamageType.HIGH_ENERGY, true)
		ctx.position_ws = Vector3(i * 2.0 - 5.0, 1.6, 0)
		ctx.explosion_direction_ws = Vector3(0, 0.3, -1).normalized()
		var rel := r.withdraw(ctx)
		blood.release(rel)
		await _tick(2)
	await _tick(180)

	var live: Dictionary = blood.live_counts()
	_check(
		live["surface"] > 100,
		"trajectories paint substantial contamination (%d stains)" % live["surface"]
	)
	_check(
		live["cells"] > 1,
		"contamination is spread over several regions, not one heap (%d cells)"
			% live["cells"]
	)
	_check(
		live["surface"] <= blood.settings.max_surface,
		"stains respect their budget (%d/%d)" % [live["surface"], blood.settings.max_surface]
	)

	# The chamber remembers: many more events must not erase the early ones.
	#
	# NOT asserted as a monotonic count. The stain layer deliberately keeps a
	# free reserve (fade_reserve_slots) so a new event never has to steal a
	# visible stain, so once the arena saturates the live count OSCILLATES: a
	# pressure-fade cohort releases ~100 slots at once, new deposits refill
	# them, and the sample lands wherever it lands between 3000 and 3200. What
	# must hold is that nothing was DESTROYED to make room, and the arena is
	# still essentially full.
	var before: int = live["surface"]
	var before_admitted: int = int((blood.telemetry()["surface"] as Dictionary)["admitted"])
	for i in 10:
		var r := _new_reservoir()
		await _tick(1)
		var ctx := _ctx(BloodTypes.DamageType.BALLISTIC, true)
		ctx.position_ws = Vector3(20.0 + i, 1.6, 10)
		blood.release(r.withdraw(ctx))
		await _tick(2)
	await _tick(120)
	var after: Dictionary = blood.live_counts()
	var tel: Dictionary = blood.telemetry()["surface"]
	_check(
		int(tel["evicted"]) == 0,
		"later kills NEVER destroy an earlier stain to make room (%d evictions)"
			% int(tel["evicted"])
	)
	_check(
		int(tel["admitted"]) > before_admitted,
		"and the later kills really did lay new marks (+%d admitted)"
			% (int(tel["admitted"]) - before_admitted)
	)
	var floor_live: int = (
		blood.settings.max_surface
		- blood.settings.stability.fade_reserve_slots
		- blood.settings.stability.max_fading_stains
	)
	_check(
		int(after["surface"]) >= floor_live,
		"the chamber is still essentially full afterwards (%d of %d, floor %d)"
			% [int(after["surface"]), blood.settings.max_surface, floor_live]
	)

	# And the reset actually resets.
	blood.clear_all()
	await _tick(2)
	var cleared: Dictionary = blood.live_counts()
	_check(
		cleared["surface"] == 0 and cleared["large"] == 0,
		"clear_all wipes the arena (%s)" % str(cleared)
	)
	blood.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# 9. Budgets under load
# --------------------------------------------------------------------------

func _budgets() -> void:
	var blood := _make_blood()
	await _tick(2)
	var children := blood.get_child_count()

	for i in 60:
		var r := _new_reservoir()
		await _tick(1)
		var ctx := _ctx(BloodTypes.DamageType.HIGH_ENERGY, true, BloodTypes.BodyRegion.HEAD, 2.0)
		ctx.position_ws = Vector3(randf_range(-20, 20), 1.6, randf_range(-20, 20))
		blood.release(r.withdraw(ctx))
		await _tick(1)

	_check(
		blood.get_child_count() == children,
		"60 catastrophic events allocate no nodes (%d children)" % blood.get_child_count()
	)
	_check(
		children <= 8,
		"the whole blood system is a handful of batched nodes, not hundreds (%d)" % children
	)
	var live: Dictionary = blood.live_counts()
	for key in ["micro", "small", "medium", "large", "surface"]:
		var layer: BloodMultiMeshLayer = blood.layer_for_test(
			{
				"micro": BloodTypes.Layer.MICRO, "small": BloodTypes.Layer.SMALL,
				"medium": BloodTypes.Layer.MEDIUM, "large": BloodTypes.Layer.LARGE,
				"surface": BloodTypes.Layer.SURFACE,
			}[key]
		)
		_check(
			live[key] <= layer.capacity,
			"%s layer stays within capacity (%d/%d)" % [key, live[key], layer.capacity]
		)
	blood.queue_free()
	await _tick(2)


# --------------------------------------------------------------------------
# 10. Phase 1 must still hold
# --------------------------------------------------------------------------

func _phase1_regression() -> void:
	var blood := _make_blood()
	await _tick(2)
	blood.seed_for_test(90210)
	var ballistic: BloodProfile = load("res://data/blood/blood_ballistic.tres")
	const N := 2000

	var shot := Vector3(0, 0, -1)
	var wound := BloodContext.make(
		BloodTypes.DamageType.BALLISTIC, Vector3(0, 1.6, 0), shot,
		BloodTypes.BodyRegion.TORSO, 1.0
	)
	wound.surface_normal_ws = -shot
	var forward := 0
	for i in N:
		if blood.sample_lobe_for_test(ballistic, wound, false).dot(shot) > 0.3:
			forward += 1
	_check(
		100.0 * forward / N > 55.0,
		"Phase 1: the forward lobe still survives the entry normal (%.1f%%)"
			% (100.0 * forward / N)
	)

	var steep := Vector3(0, 0.85, -0.53).normalized()
	var up_ctx := BloodContext.make(
		BloodTypes.DamageType.BALLISTIC, Vector3(0, 1.6, 0), steep,
		BloodTypes.BodyRegion.TORSO, 1.0
	)
	var mean_up := 0.0
	for i in N:
		mean_up += blood.sample_lobe_for_test(ballistic, up_ctx, false).y
	_check(
		mean_up / N > 0.3,
		"Phase 1: attack pitch is still preserved (mean y %.2f)" % (mean_up / N)
	)

	var slash := BloodContext.make(
		BloodTypes.DamageType.SLASHING, Vector3(0, 1.6, 0), Vector3(0, 0, -1),
		BloodTypes.BodyRegion.TORSO, 1.0
	)
	slash.swing_plane_normal_ws = Vector3.UP
	var sframe: Basis = blood.pattern_frame_for_test(slash, false)
	_check(
		absf(sframe.y.dot(Vector3.UP)) > 0.99,
		"Phase 1: the swing plane normal is still the frame's thin axis (%.3f)"
			% absf(sframe.y.dot(Vector3.UP))
	)

	var transient_families: Array[String] = []
	for name in ["ballistic", "slashing", "piercing", "blunt", "high_energy"]:
		var p: BloodProfile = load("res://data/blood/blood_%s.tres" % name)
		if p.env_splat_lifetime > 0.0:
			transient_families.append(name)
	_check(
		transient_families.is_empty() and blood.settings.stain_lifetime <= 0.0,
		"Phase 1: world stains are still persistent for every family"
	)
	blood.queue_free()
	await _tick(2)
