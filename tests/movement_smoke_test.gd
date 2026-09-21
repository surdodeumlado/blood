extends Node3D

## Headless runtime check for MovementController, ImpactFx and DummyTarget.
## Not a unit-test framework, just a scripted timeline that drives the systems
## through every state and asserts the invariants that matter.
##
##   godot --headless --path . res://tests/movement_smoke_test.tscn
##
## Exits with code 1 if anything fails.

const MOVEMENT_CONFIG := "res://data/movement/default_movement.tres"
const COMBAT_CONFIG := "res://data/combat/default_combat.tres"
const DUMMY_SCENE := "res://gameplay/enemies/dummy_target.tscn"

var config: MovementConfig
var combat: CombatConfig
var body: CharacterBody3D
var movement: MovementController

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	config = load(MOVEMENT_CONFIG)
	combat = load(COMBAT_CONFIG)
	_build_world()
	_build_player()
	_run()


func _physics_process(delta: float) -> void:
	if movement == null:
		return
	movement.step(delta)
	movement.wants_jump = false
	movement.wants_dash = false


# --------------------------------------------------------------------------

func _build_world() -> void:
	_add_box(Vector3(200, 1, 200), Vector3(0, -0.5, 0))        # floor
	_add_box(Vector3(10, 0.5, 10), Vector3(60, 1.45, 0))       # ceiling, 1.2 clearance


func _add_box(size: Vector3, pos: Vector3) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sb.add_child(cs)
	add_child(sb)
	sb.global_position = pos


func _build_player() -> void:
	body = CharacterBody3D.new()
	body.floor_max_angle = 0.959931
	body.floor_snap_length = 0.3
	var collider := CollisionShape3D.new()
	var head := Node3D.new()
	var mc := MovementController.new()
	mc.config = config
	body.add_child(collider)
	body.add_child(head)
	body.add_child(mc)
	add_child(body)
	body.global_position = Vector3(0, 0.2, 0)
	mc.setup(body, collider, head)
	movement = mc


# --------------------------------------------------------------------------

func _run() -> void:
	await _basics()
	await _dash_and_slide()
	await _ceiling()
	await _air_model()
	await _bunnyhop()
	await _framerate_independence()
	await _dash_charges()
	await _slide_steering()
	await _ground_traction()
	await _fx_pool()
	await _dummy()
	await _blood()
	await _shooting()
	await _weapon_slots()
	await _blood_distribution()
	await _weapon_feel()
	await _blood_geometry()
	await _blood_origin()
	_report()


## Provisional weapon slots: four instruments, four damage families, one active.
func _weapon_slots() -> void:
	var blood := _make_blood_system()
	var player: Node3D = load("res://gameplay/player/player.tscn").instantiate()
	player.position = Vector3(80, 0.5, 0)
	add_child(player)
	await _tick(20)

	var rack: WeaponRack = player.get_node("Head/Camera/Weapons")
	var expected := [
		BloodTypes.DamageType.BALLISTIC,
		BloodTypes.DamageType.SLASHING,
		BloodTypes.DamageType.BLUNT,
		BloodTypes.DamageType.HIGH_ENERGY,
	]
	_check(rack.weapons.size() == 4, "four slots exist (%d)" % rack.weapons.size())

	var velocity_before: Vector3 = (player as CharacterBody3D).velocity
	for slot in 4:
		rack.select(slot)
		await _tick(1)
		var weapon := rack.current()
		_check(
			rack.current_index == slot and weapon.active,
			"key %d selects slot %d (%s)" % [slot + 1, slot + 1, weapon.display_name]
		)
		_check(
			weapon.damage_type == expected[slot],
			"%s declares %s" % [
				weapon.display_name, BloodTypes.DamageType.keys()[int(expected[slot])]
			]
		)
		var active_count := 0
		for w in rack.weapons:
			if w.active:
				active_count += 1
		_check(active_count == 1, "exactly one weapon active on slot %d (%d)" % [slot + 1, active_count])

	_check(
		(player as CharacterBody3D).velocity == velocity_before,
		"switching weapons never touches player velocity"
	)

	# Each instrument must resolve to its OWN BloodProfile, by data alone.
	# A fresh target per weapon: the cleaver reaches the head hurtbox and kills
	# outright, and a corpse is correctly not a valid target for the next one.
	for slot in [1, 2]:
		var target: Node3D = _spawn_dummy(Vector3(80, 0, -1.4))
		await _tick(10)
		rack.select(slot)
		await _tick(2)
		blood.last_context = null
		rack.try_attack()
		# Melee resolves mid-swing, so wait out the whole motion.
		await _seconds((rack.current() as MeleeWeapon).swing_time + 0.15)
		var ctx: BloodContext = blood.last_context
		_check(
			ctx != null and ctx.damage_type == expected[slot],
			"%s produces a %s blood context" % [
				rack.current().display_name,
				BloodTypes.DamageType.keys()[int(expected[slot])]
			]
		)
		target.queue_free()
		await _tick(2)
	player.queue_free()
	blood.queue_free()
	await _tick(2)


## Slide is inertia plus LIMITED steering: the entry direction must keep
## dominating, and no input may convert the momentum sideways or backwards.
func _slide_steering() -> void:
	# --- A curves left gradually, nowhere near an instant 90 degrees.
	var turn_a := await _slide_turn(Vector2(-1, 0), 0.5)
	var allowed: float = config.slide_turn_rate * 0.5 + config.slide_camera_turn_rate * 0.5 + 5.0
	_check(
		turn_a > 5.0,
		"holding A actually curves the slide (%.1f deg in 0.5 s)" % turn_a
	)
	_check(
		turn_a <= allowed,
		"A cannot snap the slide round (%.1f deg <= %.1f deg budget)" % [turn_a, allowed]
	)

	# --- D is the same rule mirrored.
	var turn_d := await _slide_turn(Vector2(1, 0), 0.5)
	_check(
		turn_d > 5.0 and turn_d <= allowed,
		"holding D curves the same amount the other way (%.1f deg)" % turn_d
	)

	# --- S brakes. It must not steer, and must never carry momentum backwards.
	await _reset(Vector3(0, 0.2, 0))
	movement.input_dir = Vector2(0, 1)
	await _tick(40)
	var entry_dir := _flat(body.velocity).normalized()
	var entry_speed := movement.horizontal_speed()
	movement.wants_crouch = true
	await _tick(2)
	movement.input_dir = Vector2(0, -1)
	# Sample only while the slide is actually running. Once it ends the player is
	# crouch-walking, and walking backwards with S held is correct behaviour.
	var worst_dot := 1.0
	var brake_speed := entry_speed
	for i in 30:
		if movement.state == MovementController.State.SLIDE:
			brake_speed = movement.horizontal_speed()
			var d := _flat(body.velocity)
			if d.length() > 0.01:
				worst_dot = minf(worst_dot, d.normalized().dot(entry_dir))
		await _tick(1)
	_check(
		brake_speed < entry_speed,
		"S brakes the slide (%.2f -> %.2f m/s)" % [entry_speed, brake_speed]
	)
	_check(
		worst_dot > 0.9,
		"S never turns the slide around while sliding (worst heading dot %.3f)" % worst_dot
	)
	movement.wants_crouch = false
	movement.input_dir = Vector2.ZERO
	await _reset(Vector3(0, 0.2, 0))


## Degrees the slide heading rotates over `seconds` while holding `input`.
func _slide_turn(input: Vector2, seconds: float) -> float:
	await _reset(Vector3(0, 0.2, 0))
	movement.input_dir = Vector2(0, 1)
	await _tick(40)
	movement.wants_crouch = true
	await _tick(2)
	var before := _flat(body.velocity).normalized()
	movement.input_dir = input
	await _tick(int(seconds * 60.0))
	var after := _flat(body.velocity).normalized()
	movement.wants_crouch = false
	movement.input_dir = Vector2.ZERO
	return rad_to_deg(absf(Vector2(before.x, before.z).angle_to(Vector2(after.x, after.z))))


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## Blood foundation: budgets, cleanup, surface offset and the weapon-agnostic
## contract. Every damage family is exercised, not just the one the gun uses.
func _blood() -> void:
	var blood := _make_blood_system()
	await _tick(2)
	var cfg: BloodSettings = blood.settings

	# Phase 2: the pools are BATCHED. The whole system is a handful of
	# MultiMesh layers rather than one node per particle, so the thing to assert
	# is that the node count is tiny and never moves - not that it equals the
	# sum of the budgets.
	var pooled := blood.get_child_count()
	_check(
		pooled <= 8,
		"blood is a handful of batched layers, not one node per particle (%d)" % pooled
	)
	_check(BloodSystem.find(get_tree()) == blood, "blood system is discoverable by group")
	for layer in [
		BloodTypes.Layer.MICRO, BloodTypes.Layer.SMALL, BloodTypes.Layer.MEDIUM,
		BloodTypes.Layer.LARGE, BloodTypes.Layer.SURFACE,
	]:
		var l: BloodMultiMeshLayer = blood.layer_for_test(layer)
		_check(
			l != null and l.capacity > 0 and l.free_slots() == l.capacity,
			"layer %d preallocates its whole capacity (%d)" % [layer, l.capacity]
		)

	# Every family must be handled by data alone - no code path per weapon.
	var families := [
		BloodTypes.DamageType.BALLISTIC,
		BloodTypes.DamageType.SLASHING,
		BloodTypes.DamageType.PIERCING,
		BloodTypes.DamageType.BLUNT,
		BloodTypes.DamageType.HIGH_ENERGY,
	]
	var handled := 0
	for family in families:
		var ctx := BloodContext.make(
			family, Vector3(0, 1.2, 0), Vector3(0, 0, -1), BloodTypes.BodyRegion.TORSO, 1.0
		)
		blood.spill(ctx)
		if blood.last_particles_spawned > 0:
			handled += 1
		await _tick(1)
	_check(handled == families.size(), "every damage family has a profile (%d/5)" % handled)

	# Region and event scaling now runs through released MASS rather than through
	# a particle multiplier, but the ordering must be the same.
	var torso := _blood_amount(blood, BloodTypes.BodyRegion.TORSO, false)
	var head := _blood_amount(blood, BloodTypes.BodyRegion.HEAD, false)
	var torso_kill := _blood_amount(blood, BloodTypes.BodyRegion.TORSO, true)
	var limb := _blood_amount(blood, BloodTypes.BodyRegion.LIMB, false)
	_check(head > torso, "a headshot bleeds more than a torso hit (%.2f > %.2f)" % [head, torso])
	_check(limb < torso, "a limb hit bleeds less than a torso hit (%.2f < %.2f)" % [limb, torso])
	_check(torso_kill > torso, "a kill bleeds more than a wound (%.2f > %.2f)" % [torso_kill, torso])

	# Chunks are the signature of a kill, not of a hit.
	blood.clear_all()
	await _tick(2)
	blood.spill(_blood_ctx(BloodTypes.BodyRegion.TORSO, false))
	await _tick(1)
	var chunks_on_hit := blood.last_chunks_spawned
	blood.spill(_blood_ctx(BloodTypes.BodyRegion.HEAD, true, 1.5, Vector3(0, 1.2, 0)))
	await _tick(2)
	var chunks_on_kill := blood.last_chunks_spawned
	_check(
		chunks_on_kill > chunks_on_hit,
		"a kill throws far more gore than a hit (%d vs %d)" % [chunks_on_kill, chunks_on_hit]
	)

	# Solid material must land and then persist without costing anything.
	await _seconds(3.0)
	var live: Dictionary = blood.live_counts()
	_check(
		live["solids_settled"] > 0,
		"gore is still on the floor after 3 s (%d settled)" % live["solids_settled"]
	)

	# Impact energy separates weapons that share a family.
	var weak := _blood_amount(blood, BloodTypes.BodyRegion.TORSO, false, BloodTypes.ENERGY_WEAK)
	var heavy := _blood_amount(blood, BloodTypes.BodyRegion.TORSO, false, BloodTypes.ENERGY_EXTREME)
	_check(
		heavy > weak * 1.5,
		"impact energy scales the same family (%.2f weak vs %.2f extreme)" % [weak, heavy]
	)

	# Budgets are hard: no run may exceed them, and nothing may allocate.
	for i in 120:
		blood.spill(_blood_ctx(BloodTypes.BodyRegion.HEAD, true, 3.0, Vector3(0, 0.35, 0)))
		await _tick(1)
	_check(
		blood.get_child_count() == pooled,
		"120 blood events allocate nothing (%d nodes)" % blood.get_child_count()
	)
	var after: Dictionary = blood.live_counts()
	var within := true
	for key in ["micro", "small", "medium", "large", "surface"]:
		var l: BloodMultiMeshLayer = blood.layer_for_test(
			{
				"micro": BloodTypes.Layer.MICRO, "small": BloodTypes.Layer.SMALL,
				"medium": BloodTypes.Layer.MEDIUM, "large": BloodTypes.Layer.LARGE,
				"surface": BloodTypes.Layer.SURFACE,
			}[key]
		)
		if after[key] > l.capacity:
			within = false
	_check(within, "every layer stays within budget under sustained load (%s)" % str(after))

	# Stains land on geometry, offset off the surface so nothing z-fights, and
	# the arena keeps them.
	_check(
		after["surface"] > 0,
		"environment stains actually landed on geometry (%d)" % after["surface"]
	)
	await _seconds(2.0)
	var settled: Dictionary = blood.live_counts()
	_check(
		settled["airborne"] == 0,
		"temporary spray cleaned itself up (%d airborne)" % settled["airborne"]
	)
	_check(
		settled["surface"] > 0,
		"environment stains are still there (persistent, not temporary)"
	)

	blood.queue_free()
	await _tick(2)


func _make_blood_system() -> BloodSystem:
	var blood := BloodSystem.new()
	blood.settings = load("res://data/blood/blood_settings.tres")
	blood.fallback_reservoir = load("res://data/blood/reservoir_defaults.tres")
	blood.profiles.assign([
		load("res://data/blood/blood_ballistic.tres"),
		load("res://data/blood/blood_slashing.tres"),
		load("res://data/blood/blood_piercing.tres"),
		load("res://data/blood/blood_blunt.tres"),
		load("res://data/blood/blood_high_energy.tres"),
	])
	add_child(blood)
	return blood


func _blood_ctx(
	region: BloodTypes.BodyRegion, kill: bool, energy := 1.0, pos := Vector3(0, 1.2, 0)
) -> BloodContext:
	var ctx := BloodContext.make(
		BloodTypes.DamageType.BALLISTIC, pos, Vector3(0, -0.4, -1).normalized(), region, energy
	)
	ctx.is_kill = kill
	return ctx


## Particles a single event is worth, as the system itself decides it.
func _blood_amount(
	blood: BloodSystem, region: BloodTypes.BodyRegion, kill: bool, energy := 1.0
) -> float:
	blood.spill(_blood_ctx(region, kill, energy))
	return float(blood.last_particles_spawned)


func _count_visible(node: Node, from_index: int, to_index: int) -> int:
	var count := 0
	for i in range(from_index, mini(to_index, node.get_child_count())):
		if (node.get_child(i) as Node3D).visible:
			count += 1
	return count


## Dash is a two-charge resource with a strictly sequential refill.
func _dash_charges() -> void:
	await _reset(Vector3(0, 0.2, 0))
	_check(
		movement.dash_charges == config.dash_max_charges,
		"starts with a full pool (%d)" % movement.dash_charges
	)

	# Spend both, then confirm a third dash is simply refused.
	movement.input_dir = Vector2(0, 1)
	await _tick(30)
	movement.wants_dash = true
	await _tick(1)
	_check(movement.dash_charges == 1, "a dash costs one charge (%d left)" % movement.dash_charges)
	await _tick(int(ceil((config.dash_duration + config.dash_cooldown) * 60.0)) + 3)
	movement.wants_dash = true
	await _tick(1)
	_check(movement.dash_charges == 0, "second dash empties the pool")
	await _tick(int(ceil((config.dash_duration + config.dash_cooldown) * 60.0)) + 3)

	var state_before := movement.state
	movement.wants_dash = true
	await _tick(1)
	_check(
		movement.dash_charges == 0 and movement.state != MovementController.State.DASH,
		"no charges means no dash"
	)
	_check(state_before != MovementController.State.DASH, "pool was genuinely empty first")

	# Sequential refill: after one charge time we have exactly one back, not two.
	await _seconds(config.dash_charge_time + 0.15)
	_check(
		movement.dash_charges == 1,
		"charges refill one at a time (%d after one charge time)" % movement.dash_charges
	)
	await _seconds(config.dash_charge_time + 0.2)
	_check(movement.dash_charges == 2, "the pool refills to full")

	# Rewards can never overshoot the cap.
	movement.reward_headshot_kill()
	movement.reward_headshot_kill()
	movement.reward_kill()
	await _tick(2)
	_check(
		movement.dash_charges == config.dash_max_charges,
		"rewards never exceed max charges (%d)" % movement.dash_charges
	)

	# A headshot kill hands a charge straight back.
	movement.wants_dash = true
	await _tick(1)
	_check(movement.dash_charges == 1, "spent one for the reward test")
	movement.reward_headshot_kill()
	_check(movement.dash_charges == 2, "headshot kill restores a charge immediately")

	# A normal kill shortens the wait instead of granting outright.
	await _tick(int(ceil((config.dash_duration + config.dash_cooldown) * 60.0)) + 3)
	movement.wants_dash = true
	await _tick(1)
	var progress_before := movement.dash_recharge_progress()
	movement.reward_kill()
	var progress_after := movement.dash_recharge_progress()
	_check(
		progress_after > progress_before and movement.dash_charges == 1,
		"a normal kill advances the timer without granting a charge (%.2f -> %.2f)"
			% [progress_before, progress_after]
	)
	await _reset(Vector3(0, 0.2, 0))


## Ground traction must be crisp at walking speed and absent on a bhop landing.
func _ground_traction() -> void:
	# Stopping from a walk should be quick now.
	await _reset(Vector3(0, 0.2, 0))
	movement.input_dir = Vector2(0, 1)
	await _tick(40)
	movement.input_dir = Vector2.ZERO
	var stop_ticks := 0
	while movement.horizontal_speed() > 0.5 and stop_ticks < 120:
		stop_ticks += 1
		await _tick(1)
	_check(
		stop_ticks <= 12,
		"walking stops crisply (%d ticks, %.0f ms)" % [stop_ticks, stop_ticks * 1000.0 / 60.0]
	)

	# Reversing direction should not take a slow slide through zero.
	await _reset(Vector3(0, 0.2, 0))
	movement.input_dir = Vector2(0, 1)
	await _tick(40)
	movement.input_dir = Vector2(0, -1)
	var turn_ticks := 0
	while body.velocity.z < 0.0 and turn_ticks < 120:
		turn_ticks += 1
		await _tick(1)
	_check(
		turn_ticks <= 12,
		"direction reversal is planted (%d ticks, %.0f ms)" % [turn_ticks, turn_ticks * 1000.0 / 60.0]
	)

	# And none of that may touch a bhop landing.
	await _reset(Vector3(0, 0.2, -80.0))
	var peak: float = await _bhop_peak(900)
	_check(
		peak > 14.0,
		"traction did not break bunnyhop (peak still %.2f m/s)" % peak
	)
	await _reset(Vector3(0, 0.2, 0))


func _basics() -> void:
	await _tick(20)
	_check(body.is_on_floor(), "settles on the floor")
	_check(movement.state == MovementController.State.GROUND, "idles in GROUND")
	_check(movement.horizontal_speed() < 0.1, "idle speed is zero")

	movement.input_dir = Vector2(0, 1)
	await _tick(30)
	_check(
		movement.horizontal_speed() > config.move_speed - 0.5,
		"reaches base speed (%.2f)" % movement.horizontal_speed()
	)


func _dash_and_slide() -> void:
	movement.wants_dash = true
	await _tick(1)
	_check(movement.state == MovementController.State.DASH, "dash starts")
	_check(
		movement.horizontal_speed() > config.dash_speed - 0.5,
		"dash reaches dash_speed (%.2f)" % movement.horizontal_speed()
	)
	await _tick(int(ceil(config.dash_duration * 60.0)) + 2)
	_check(movement.state != MovementController.State.DASH, "dash ends by itself")
	_check(
		movement.horizontal_speed() > config.move_speed,
		"momentum survives the dash (%.2f)" % movement.horizontal_speed()
	)

	movement.wants_crouch = true
	await _tick(2)
	_check(movement.state == MovementController.State.SLIDE, "fast crouch becomes a slide")
	var slide_speed := movement.horizontal_speed()

	movement.wants_jump = true
	await _tick(2)
	_check(
		movement.horizontal_speed() > slide_speed - 0.5,
		"slide jump keeps horizontal momentum (%.2f -> %.2f)" % [
			slide_speed, movement.horizontal_speed()
		]
	)
	_check(body.velocity.y > 0.0, "slide jump actually leaves the ground")

	movement.wants_crouch = false
	movement.input_dir = Vector2.ZERO
	await _tick(90)
	_check(movement.state == MovementController.State.GROUND, "returns to GROUND")

	movement.wants_crouch = true
	await _tick(10)
	_check(movement.state == MovementController.State.CROUCH, "slow crouch stays CROUCH")


func _ceiling() -> void:
	body.global_position = Vector3(60, 0.1, 0)
	body.velocity = Vector3.ZERO
	await _tick(20)
	_check(movement.state == MovementController.State.CROUCH, "crouched under the ceiling")
	movement.wants_crouch = false
	await _tick(40)
	_check(
		movement.state == MovementController.State.CROUCH,
		"stays crouched: no clearance to stand"
	)
	var head_node := body.get_child(1) as Node3D
	_check(
		head_node.position.y < 1.0,
		"head stays low under the ceiling (%.2f)" % head_node.position.y
	)

	movement.input_dir = Vector2(0, 1)
	body.global_position = Vector3(0, 0.1, 0)
	await _tick(40)
	_check(movement.state == MovementController.State.GROUND, "stands up in the open")


## The two halves of the air model, checked separately.
func _air_model() -> void:
	# Holding forward in the air must never push past move_speed.
	await _reset(Vector3(0, 0.2, 0))
	movement.input_dir = Vector2(0, 1)
	await _tick(40)
	movement.wants_jump = true
	await _tick(1)
	movement.input_dir = Vector2(0, 1)
	await _tick(30)
	_check(
		movement.horizontal_speed() <= config.move_speed + 0.05,
		"holding forward in the air cannot exceed move_speed (%.2f)" % movement.horizontal_speed()
	)

	# Holding strafe with a FIXED view is worth almost nothing.
	await _reset(Vector3(0, 0.2, 0))
	movement.input_dir = Vector2(0, 1)
	await _tick(40)
	var before := movement.horizontal_speed()
	movement.wants_jump = true
	await _tick(1)
	movement.input_dir = Vector2(-1, 0)
	await _tick(30)
	var held_gain := movement.horizontal_speed() - before
	_check(
		held_gain < 0.6,
		"holding a strafe key without turning barely gains (+%.2f m/s)" % held_gain
	)


## A perfect-strafe bot: hold A and rotate the view so the wish direction stays
## perpendicular to the velocity, jumping on the tick after every landing.
func _bhop_peak(ticks: int) -> float:
	await _reset(Vector3(0, 0.2, -80.0))
	movement.input_dir = Vector2(0, 1)
	await _tick(40)
	var peak := 0.0
	for i in ticks:
		if body.is_on_floor():
			movement.wants_jump = true
			movement.input_dir = Vector2(0, 1)
		else:
			movement.input_dir = Vector2(-1, 0)
			var d := Vector3(body.velocity.x, 0.0, body.velocity.z)
			if d.length() > 0.01:
				d = d.normalized()
				# Aim the body so that -basis.x (the A direction) is 90 degrees
				# off the current velocity.
				body.rotation.y = atan2(-d.x, -d.z)
		await _tick(1)
		peak = maxf(peak, movement.horizontal_speed())
	return peak


func _bunnyhop() -> void:
	var start := config.move_speed
	var peak: float = await _bhop_peak(1200)

	_check(
		peak > start + 4.0,
		"a correct air-strafe gains real speed (%.2f -> %.2f)" % [start, peak]
	)
	_check(
		peak > 14.0,
		"bunnyhop reaches competent territory (peak %.2f m/s)" % peak
	)
	_check(
		peak <= config.air_soft_ceiling + 0.5,
		"soft ceiling holds (peak %.2f / ceiling %.1f)" % [peak, config.air_soft_ceiling]
	)
	_check(is_finite(body.velocity.length()), "velocity stays finite")

	# Dash spam cannot beat a good strafe run, and cannot compound. With the
	# charge pool it is also rate-limited, but the speed rule must hold anyway.
	await _reset(Vector3(0, 0.2, -80.0))
	var dash_peak := 0.0
	for i in 600:
		movement.input_dir = Vector2(0, 1)
		movement.wants_dash = true
		movement.wants_jump = body.is_on_floor()
		await _tick(1)
		dash_peak = maxf(dash_peak, movement.horizontal_speed())
	_check(
		dash_peak <= config.dash_speed + 0.1,
		"mashing dash never compounds (peak %.2f)" % dash_peak
	)
	await _reset(Vector3(0, 0.2, 0))


## Godot runs _physics_process at a fixed rate, so movement should produce the
## same result no matter what that rate is. Run the same bot at 60 and at 120.
func _framerate_independence() -> void:
	var at_60: float = await _bhop_peak(1200)
	Engine.physics_ticks_per_second = 120
	var at_120: float = await _bhop_peak(2400)
	Engine.physics_ticks_per_second = 60
	await _reset(Vector3(0, 0.2, 0))
	var drift: float = absf(at_120 - at_60) / maxf(at_60, 0.001)
	_check(
		drift < 0.08,
		"bunnyhop result is tick-rate independent (60Hz %.2f vs 120Hz %.2f, %.1f%%)" % [
			at_60, at_120, drift * 100.0
		]
	)


## Pooled effects must never grow and must switch themselves off.
func _fx_pool() -> void:
	var fx := ImpactFx.new()
	fx.config = combat
	add_child(fx)
	await _tick(1)
	var expected := combat.tracer_pool_size + combat.impact_pool_size
	_check(fx.get_child_count() == expected, "fx pool preallocates %d nodes" % expected)

	const KINDS := [ImpactFx.Kind.WORLD, ImpactFx.Kind.ENEMY, ImpactFx.Kind.HEAD]
	for i in 300:
		fx.tracer(Vector3(0, 1, 0), Vector3(0, 1, 10))
		fx.impact(Vector3(0, 1, 10), KINDS[i % KINDS.size()])
	_check(
		fx.get_child_count() == expected,
		"300 shots allocate nothing (still %d nodes)" % fx.get_child_count()
	)
	_check(fx.is_processing(), "fx processes while effects are alive")

	await _tick(40)
	_check(not fx.is_processing(), "fx stops processing once effects expire")
	var visible_count := 0
	for child in fx.get_children():
		if (child as Node3D).visible:
			visible_count += 1
	_check(visible_count == 0, "every effect hid itself (%d still visible)" % visible_count)
	fx.queue_free()


## Is this target actually dead?
##
## NOT "is its visual hidden". The corpse visual is now carried along the blow
## for a moment after death as presentation, so visibility lags the kill by a
## fraction of a second. These checks are about damage rules, so they ask the
## thing that owns the damage rules.
func _is_dead(target: Node) -> bool:
	return target.has_method("is_damageable") and not target.is_damageable()


## Damage, reaction, death, fragment cleanup and respawn.
func _dummy() -> void:
	var dummy: Node3D = load(DUMMY_SCENE).instantiate()
	# Position BEFORE add_child: _ready() captures the respawn point.
	dummy.position = Vector3(20, 0.0, 0)
	add_child(dummy)
	await _tick(10)

	var before_children := get_child_count()
	var hits := 0
	var killed := false
	while hits < 20 and not killed:
		killed = dummy.take_damage(combat.damage_body, dummy.global_position, Vector3(0, 0, -1))
		hits += 1
		await _tick(2)
	_check(killed and hits == 3, "three body shots kill the dummy (took %d)" % hits)
	_check(
		get_child_count() == before_children,
		"death allocates no nodes at all (gore is pooled in BloodSystem)"
	)

	await _seconds(combat.dummy_respawn_delay + 0.5)
	_check(
		dummy.take_damage(1.0, dummy.global_position, Vector3(0, 0, -1)) == false,
		"dummy respawned and takes damage again"
	)
	dummy.queue_free()


## Proves there is no divergence between what the crosshair promises, where the
## gameplay ray actually goes, and where the visual tracer is drawn to. This is
## the check that has to pass BEFORE blaming hurtbox sizes for missed shots.
func _aim_alignment(
	player: Node3D, camera: FirstPersonCamera, blaster: TestBlaster, distance: float
) -> void:
	var target := _spawn_dummy(Vector3(40, 0, -distance))
	await _tick(10)
	var viewport := player.get_viewport()
	var centre := viewport.get_visible_rect().size * 0.5

	# 1. The crosshair sits at the exact centre of the screen, so the ray the
	#    centre pixel casts is what the player believes they are aiming down.
	var screen_dir := camera.project_ray_normal(centre)
	var weapon_dir := -camera.global_basis.z.normalized()
	_check(
		screen_dir.dot(weapon_dir) > 0.99999,
		"crosshair centre and weapon ray are the same vector (dot %.6f)" % screen_dir.dot(weapon_dir)
	)
	var screen_origin := camera.project_ray_origin(centre)
	_check(
		screen_origin.distance_to(camera.global_position) < 0.001,
		"weapon ray starts at the eye the crosshair projects from (%.4f m apart)"
			% screen_origin.distance_to(camera.global_position)
	)

	# 2. An independent raycast down that same screen ray must land where the
	#    weapon's tracer is drawn to.
	var query := PhysicsRayQueryParameters3D.create(
		screen_origin, screen_origin + screen_dir * 120.0
	)
	query.collide_with_areas = true
	query.exclude = [(player as CollisionObject3D).get_rid()]
	query.collision_mask = 1 | combat.hurtbox_layer
	var expected := camera.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not expected.is_empty(), "reference ray down the crosshair hits the target")

	var fx: ImpactFx = blaster.get_node("ImpactFx")
	blaster.try_fire()
	await _tick(2)
	_check(
		fx.last_tracer_to.distance_to(expected.position) < 0.01,
		"tracer ends exactly where the hitscan landed (%.4f m apart)"
			% fx.last_tracer_to.distance_to(expected.position)
	)
	_check(
		expected.collider != null and expected.collider is Hurtbox,
		"the crosshair ray resolves to a hurtbox, not the physics body"
	)

	target.queue_free()
	await _tick(2)


func _spawn_dummy(pos: Vector3) -> Node3D:
	var dummy: Node3D = load(DUMMY_SCENE).instantiate()
	# Position BEFORE add_child: _ready() captures the respawn point.
	dummy.position = pos
	add_child(dummy)
	return dummy


## End to end: a real player scene, a real blaster, a real trace, real kills.
## Body shots and a headshot are checked separately, through the actual weapon.
func _shooting() -> void:
	const DISTANCE := 12.0
	var player: Node3D = load("res://gameplay/player/player.tscn").instantiate()
	player.position = Vector3(40, 0.5, 0)
	add_child(player)
	await _tick(20)

	var camera: FirstPersonCamera = player.get_node("Head/Camera")
	var blaster: TestBlaster = player.get_node("Head/Camera/Weapons/HandCannon")

	# Alignment gets its own throwaway target so it cannot pre-damage the one
	# the damage tests below count shots against.
	await _aim_alignment(player, camera, blaster, DISTANCE)
	await _wait_ready(blaster)

	var target: Node3D = _spawn_dummy(Vector3(40, 0, -DISTANCE))
	await _tick(10)
	var zones: Array[StringName] = []
	var kills: Array[StringName] = []
	blaster.hit_confirmed.connect(func(zone: StringName) -> void: zones.append(zone))
	blaster.enemy_killed.connect(func(zone: StringName) -> void: kills.append(zone))

	# --- semi-auto: holding the trigger is not a thing, and the cooldown holds.
	blaster.try_fire()
	await _tick(2)
	_check(not blaster.ready_to_fire(), "weapon is cycling right after a shot")
	var before_spam := zones.size()
	for i in 20:
		blaster.try_fire()
		await _tick(1)
	_check(
		zones.size() == before_spam,
		"calling fire during the cooldown does nothing (%d extra)" % (zones.size() - before_spam)
	)

	# --- body shots: level aim hits the capsule, three of them kill.
	var body_shots := 1
	while body_shots < 8 and not _is_dead(target):
		await _wait_ready(blaster)
		blaster.try_fire()
		body_shots += 1
		await _tick(3)
	_check(
		body_shots == 3 and _is_dead(target),
		"three body shots kill through the real weapon (took %d)" % body_shots
	)
	_check(
		not zones.has(Weapon.ZONE_HEAD),
		"level aim never registered as a headshot"
	)

	# --- headshot: pitch up onto the head sphere, one shot kills.
	await _seconds(combat.dummy_respawn_delay + 0.5)
	await _tick(10)
	var head_y: float = target.global_position.y + 2.15
	var eye_y: float = camera.global_position.y
	# look() takes mouse pixels, so convert the angle we want through sensitivity.
	# Kept so the aim can be levelled again afterwards: look() accumulates.
	var aim_px: float = atan2(head_y - eye_y, DISTANCE) / config.mouse_sensitivity
	camera.look(Vector2(0.0, -aim_px))
	await _tick(3)
	zones.clear()
	await _wait_ready(blaster)
	blaster.try_fire()
	await _tick(3)
	_check(zones.has(Weapon.ZONE_HEAD), "aiming at the head registers a headshot")
	_check(_is_dead(target), "one headshot kills the dummy")
	_check(
		kills.has(Weapon.ZONE_HEAD),
		"a headshot KILL is reported, which is what pays the dash reward"
	)

	# --- the hand cannon feeds the blood foundation a correct BALLISTIC context.
	var blood := _make_blood_system()
	await _tick(2)
	var fresh: Node3D = _spawn_dummy(Vector3(40, 0, -DISTANCE))
	await _tick(10)

	camera.look(Vector2(0.0, aim_px))  # back to level
	await _tick(3)
	await _wait_ready(blaster)
	blaster.try_fire()
	await _tick(3)
	var body_ctx: BloodContext = blood.last_context
	_check(body_ctx != null, "the weapon produced a blood context")
	if body_ctx != null:
		_check(
			body_ctx.damage_type == BloodTypes.DamageType.BALLISTIC,
			"hand cannon emits BALLISTIC"
		)
		_check(
			body_ctx.body_region == BloodTypes.BodyRegion.TORSO and not body_ctx.is_headshot,
			"a torso hit reports the TORSO region"
		)
		_check(not body_ctx.is_kill, "a non-lethal hit is not reported as a kill")
		_check(
			is_equal_approx(body_ctx.energy, combat.blood_energy),
			"impact energy comes from the weapon (%.2f)" % body_ctx.energy
		)
		_check(
			body_ctx.attack_direction_ws.dot(-camera.global_basis.z) > 0.999,
			"blood direction follows the shot, not a random sphere"
		)
		_check(
			body_ctx.surface_normal_ws.length() > 0.5,
			"the surface normal at the wound was carried through"
		)

	# Headshot kill: region, kill flag and a bigger burst than the body hit.
	var body_particles := blood.last_particles_spawned
	var fresh_head_y: float = fresh.global_position.y + 2.15
	camera.look(Vector2(0.0, -atan2(
		fresh_head_y - camera.global_position.y, DISTANCE
	) / config.mouse_sensitivity))
	await _tick(3)
	await _wait_ready(blaster)
	blaster.try_fire()
	await _tick(3)
	var head_ctx: BloodContext = blood.last_context
	_check(
		head_ctx != null and head_ctx.body_region == BloodTypes.BodyRegion.HEAD
			and head_ctx.is_headshot and head_ctx.is_kill,
		"a headshot kill reports HEAD + is_kill"
	)
	_check(
		head_ctx != null and head_ctx.energy > combat.blood_energy,
		"headshots carry the weapon's extra energy (%.2f)" % (head_ctx.energy if head_ctx else 0.0)
	)
	_check(
		blood.last_particles_spawned > body_particles,
		"headshot kill bleeds more than a body hit (%d > %d)"
			% [blood.last_particles_spawned, body_particles]
	)
	# --- the corpse bug: a dead dummy must stop being a target immediately.
	var splats_before: int = (blood.live_counts())["surface"]
	zones.clear()
	kills.clear()
	var corpse_particles := blood.last_particles_spawned
	# Two shots only: the dummy respawns after dummy_respawn_delay, and a hit on
	# a RESPAWNED dummy would be perfectly correct.
	for i in 2:
		await _wait_ready(blaster)
		blaster.try_fire()
		await _tick(3)
	_check(zones.is_empty(), "shooting a corpse produces no hitmarker (%d)" % zones.size())
	_check(
		blood.last_particles_spawned == corpse_particles,
		"shooting a corpse produces no enemy blood"
	)
	_check(
		not fresh.is_damageable(),
		"the dead dummy reports itself as not damageable"
	)
	var head_area: Area3D = fresh.get_node("Hurtboxes/HeadHurtbox")
	var body_area: Area3D = fresh.get_node("Hurtboxes/BodyHurtbox")
	_check(
		head_area.collision_layer == 0 and body_area.collision_layer == 0,
		"dead hurtboxes left the hurtbox layer immediately"
	)
	# World blood must not care that the enemy is gone.
	fresh.queue_free()
	await _tick(3)
	_check(
		(blood.live_counts())["surface"]
			>= splats_before,
		"environment blood survives the enemy being freed"
	)

	blood.queue_free()
	await _tick(2)


	_check(
		is_equal_approx(Engine.time_scale, 1.0),
		"time_scale is never touched (no global hit stop)"
	)

	# --- FOV composition: accents must not stack and must not stick.
	for i in 60:
		camera.pulse_fov(combat.fov_pulse_head)
		camera.accent_dash_fov()
	await _tick(2)
	_check(
		camera.current_fov() <= config.fov_absolute_max + 0.001,
		"stacked FOV accents stay under the hard ceiling (%.2f / %.1f)"
			% [camera.current_fov(), config.fov_absolute_max]
	)
	await _seconds(2.5)
	_check(
		camera.current_fov() < config.fov_base + 0.6,
		"FOV accents decay back to base (%.2f)" % camera.current_fov()
	)

	# --- the gameplay cooldown is never extended by hit presentation.
	await _wait_ready(blaster)
	var t0 := Time.get_ticks_usec()
	blaster.try_fire()
	await _wait_ready(blaster)
	var measured := (Time.get_ticks_usec() - t0) / 1_000_000.0
	_check(
		absf(measured - combat.fire_interval) < 0.12,
		"cooldown after a connecting shot is still fire_interval (%.3fs vs %.3fs)"
			% [measured, combat.fire_interval]
	)

	player.queue_free()
	target.queue_free()
	await _tick(2)


func _wait_ready(blaster: TestBlaster) -> void:
	var guard := 0
	while not blaster.ready_to_fire() and guard < 300:
		guard += 1
		await _tick(1)


# --------------------------------------------------------------------------

func _reset(pos: Vector3) -> void:
	movement.input_dir = Vector2.ZERO
	movement.wants_crouch = false
	movement.dash_charges = config.dash_max_charges
	body.rotation = Vector3.ZERO
	body.global_position = pos
	body.velocity = Vector3.ZERO
	await _tick(20)


func _tick(count := 1) -> void:
	for i in count:
		await get_tree().physics_frame


func _seconds(duration: float) -> void:
	await get_tree().create_timer(duration).timeout


func _check(ok: bool, label: String) -> void:
	_checks += 1
	var line := ("  PASS  " if ok else "  FAIL  ") + label
	print(line)
	# stdout is block-buffered when it is not a console, so mirror every result
	# to stderr as well: that is what makes progress visible during a headless
	# run instead of arriving all at once at exit.
	printerr(line)
	if not ok:
		_failures.append(label)


func _report() -> void:
	var summary := "%d checks, %d failed" % [_checks, _failures.size()]
	print("")
	print(summary)
	printerr(summary)
	for failure in _failures:
		print("  FAILED: ", failure)
		printerr("  FAILED: ", failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


## Blood direction must fill a continuous 3D volume, not cling to a few axes.
## This is the check the playtest kept failing: bin the azimuth AROUND the
## impact axis into 16 sectors and prove every one of them gets material.
func _blood_distribution() -> void:
	var blood := _make_blood_system()
	await _tick(2)

	const SECTORS := 16
	const SAMPLES := 4000
	var profile: BloodProfile = load("res://data/blood/blood_ballistic.tres")
	var axis := Vector3(0, 0, -1)
	var frame := Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), axis)

	var bins := PackedInt32Array()
	bins.resize(SECTORS)
	var elevations: Array[float] = []
	for i in SAMPLES:
		var dir: Vector3 = blood.sample_cone_for_test(
			axis, frame, profile.spread_angle, profile.spread_concentration
		)
		# Azimuth measured in the plane perpendicular to the impact axis.
		var angle := atan2(dir.dot(frame.y), dir.dot(frame.x))
		var sector := int(wrapf(angle, 0.0, TAU) / TAU * SECTORS) % SECTORS
		bins[sector] += 1
		elevations.append(dir.y)

	var lowest := SAMPLES
	var highest := 0
	for count in bins:
		lowest = mini(lowest, count)
		highest = maxi(highest, count)
	_check(lowest > 0, "every one of %d azimuth sectors gets blood (min %d)" % [SECTORS, lowest])
	_check(
		float(highest) / maxf(float(lowest), 1.0) < 2.0,
		"azimuth is not concentrated on a few sectors (max/min %.2f)"
			% (float(highest) / maxf(float(lowest), 1.0))
	)

	# Chunks must arc: a real spread of launch elevations, not one flat plane.
	var chunk_low := 999.0
	var chunk_high := -999.0
	for i in 800:
		var dir: Vector3 = blood.sample_arc_for_test(
			axis, profile.chunk_spread_angle,
			profile.chunk_elevation_min, profile.chunk_elevation_max
		)
		chunk_low = minf(chunk_low, dir.y)
		chunk_high = maxf(chunk_high, dir.y)
	_check(
		chunk_high - chunk_low > 0.45,
		"chunks launch across a real elevation band (%.2f .. %.2f)" % [chunk_low, chunk_high]
	)

	# Physical droplets must actually land and leave a mark on the world.
	var before: int = (blood.live_counts())["surface"]
	for i in 6:
		blood.spill(_blood_ctx(BloodTypes.BodyRegion.TORSO, true, 2.0, Vector3(0, 1.4, 0)))
		await _tick(2)
	_check(blood.last_droplets_spawned > 0, "an event spawns physical droplets (%d)" % blood.last_droplets_spawned)
	await _seconds(2.5)
	var after: int = (blood.live_counts())["surface"]
	_check(after > before, "droplets landed and left world splats (%d -> %d)" % [before, after])
	_check(
		after <= blood.settings.max_surface,
		"splat budget still respected (%d)" % after
	)
	blood.queue_free()
	await _tick(2)


## Weapon feel rules from the 0.8 playtest: one motion per swing, multi-hit with
## a first/secondary split, dagger alternation, grenade capacity and inheritance.
func _weapon_feel() -> void:
	var blood := _make_blood_system()
	var player: Node3D = load("res://gameplay/player/player.tscn").instantiate()
	player.position = Vector3(-60, 0.5, 0)
	add_child(player)
	await _tick(20)
	var rack: WeaponRack = player.get_node("Head/Camera/Weapons")
	var daggers: MeleeWeapon = player.get_node("Head/Camera/Weapons/TwinDaggers")
	var maul: MeleeWeapon = player.get_node("Head/Camera/Weapons/HeavyBlunt")
	var launcher: GrenadeLauncher = player.get_node("Head/Camera/Weapons/GrenadeLauncher")

	# --- Daggers: two hits kill, and one swing damages a victim only once.
	rack.select(1)
	var d1: Node3D = _spawn_dummy(Vector3(-60, 0, -1.5))
	await _tick(10)
	var left_first := daggers._side
	daggers.try_attack()
	await _seconds(daggers.swing_time + 0.1)
	_check(
		daggers.contact_count > 0,
		"dagger swing reached contact (count %d, overlaps %d, targets %d)"
			% [daggers.contact_count, daggers.last_sweep_overlaps, daggers.last_sweep_targets]
	)
	_check(not _is_dead(d1), "one dagger hit does not kill")
	_check(daggers._side != left_first, "daggers alternate hands between attacks")
	# The first hit knocks the dummy out of reach; put it back so the test is
	# about damage, not about chasing it.
	d1.global_position = Vector3(-60, 0, -1.5)
	(d1 as CharacterBody3D).velocity = Vector3.ZERO
	await _tick(2)
	daggers.try_attack()
	await _seconds(daggers.swing_time + 0.1)
	_check(_is_dead(d1), "two dagger hits kill")
	d1.queue_free()
	await _tick(2)

	# --- Maul: first victim dies, every other victim in the SAME swing takes
	# half their max health, and nobody is hit twice.
	rack.select(2)
	var a: Node3D = _spawn_dummy(Vector3(-60.6, 0, -1.6))
	var b: Node3D = _spawn_dummy(Vector3(-59.4, 0, -1.6))
	await _tick(10)
	maul.try_attack()
	await _seconds(maul.swing_time + 0.15)
	var dead := int(_is_dead(a)) + int(_is_dead(b))
	_check(dead == 1, "one maul swing kills exactly one of two targets (%d died)" % dead)
	var survivor: Node3D = b if _is_dead(a) else a
	_check(
		survivor.max_health() > 0.0 and not survivor.is_damageable() == false,
		"the second target survived the same swing"
	)
	a.queue_free()
	b.queue_free()
	await _tick(2)

	# --- Grenades: two may be live, a third is refused.
	rack.select(3)
	await _seconds(0.2)
	launcher.try_attack()
	await _seconds(launcher.cooldown_time + 0.1)
	launcher.try_attack()
	await _tick(3)
	_check(launcher.active_count() == 2, "two grenades can be live (%d)" % launcher.active_count())
	_check(not launcher.ready_to_attack(), "a third launch is refused while two are live")
	launcher.try_attack()
	await _tick(2)
	_check(launcher.active_count() == 2, "the refused launch spawned nothing")

	# --- Inheritance: a grenade thrown while moving carries the player with it.
	launcher.force_fuse()
	await _tick(4)
	launcher.force_fuse()
	await _tick(4)
	var still := launcher.velocity_of(0)
	(player as CharacterBody3D).velocity = Vector3(0, 0, -18.0)
	await _seconds(launcher.cooldown_time + 0.1)
	launcher.try_attack()
	await _tick(2)
	var moving := launcher.velocity_of(0)
	_check(
		moving.length() > still.length() + 5.0,
		"grenades inherit player velocity (%.1f vs %.1f m/s)" % [moving.length(), still.length()]
	)
	launcher.force_fuse()
	await _tick(4)

	player.queue_free()
	blood.queue_free()
	await _tick(2)


## Signature Pass Phase 1: the geometry of an event, asserted statistically.
##
## Every check here is on a DISTRIBUTION with a seeded RNG, never on an exact
## random value: the pattern is allowed to change its dice, not its shape. A
## failure means blood is going somewhere it was never told to go.
func _blood_geometry() -> void:
	var blood := _make_blood_system()
	await _tick(2)
	blood.seed_for_test(90210)
	var ballistic: BloodProfile = load("res://data/blood/blood_ballistic.tres")
	var slashing: BloodProfile = load("res://data/blood/blood_slashing.tres")
	const N := 3000

	# --- A. The forward lobe survives. The entry normal points BACK at the
	# shooter, and clipping against it used to delete the forward plume
	# entirely: 84% forward became 0% forward and 90% tangential.
	var shot := Vector3(0, 0, -1)
	var wound := BloodContext.make(
		BloodTypes.DamageType.BALLISTIC, Vector3(0, 1.6, 0), shot,
		BloodTypes.BodyRegion.TORSO, 1.0
	)
	wound.surface_normal_ws = -shot  # entry face, pointing back at the shooter
	var forward := 0
	var tangential := 0
	for i in N:
		var d: Vector3 = blood.sample_lobe_for_test(ballistic, wound, false)
		var along := d.dot(shot)
		if along > 0.3:
			forward += 1
		elif absf(along) <= 0.3:
			tangential += 1
	var forward_pct := 100.0 * forward / N
	_check(
		forward_pct > 55.0,
		"A: the forward lobe survives the entry normal (%.1f%% forward)" % forward_pct
	)
	_check(
		tangential < forward,
		"A: material is not dumped sideways (%d tangential vs %d forward)"
			% [tangential, forward]
	)

	# --- B. A wound does NOT clip against its own surface; a hard surface does.
	var surface := BloodContext.make(
		BloodTypes.DamageType.BALLISTIC, Vector3(0, 1.6, 0), shot,
		BloodTypes.BodyRegion.TORSO, 1.0
	)
	surface.surface_normal_ws = -shot
	surface.clip_to_surface = true
	var into := 0
	for i in N:
		if blood.sample_lobe_for_test(ballistic, surface, false).dot(-shot) < -0.25:
			into += 1
	_check(into == 0, "B: surface blood is never fired into the surface (%d)" % into)

	# --- C. The back lobe points at the attacker, not into a random hemisphere.
	var back_hits := 0
	for i in N:
		if blood.sample_lobe_for_test(ballistic, wound, true).dot(-shot) > 0.0:
			back_hits += 1
	_check(
		float(back_hits) / N > 0.7,
		"C: the back lobe travels toward the attacker (%.1f%%)" % (100.0 * back_hits / N)
	)

	# --- D. Attack PITCH survives. A steeply upward shot must throw material
	# upward. The old sampler flattened the axis onto XZ, and up and down came
	# out identical.
	var steep := Vector3(0, 0.85, -0.53).normalized()
	var up_ctx := BloodContext.make(
		BloodTypes.DamageType.BALLISTIC, Vector3(0, 1.6, 0), steep,
		BloodTypes.BodyRegion.TORSO, 1.0
	)
	var down_ctx := BloodContext.make(
		BloodTypes.DamageType.BALLISTIC, Vector3(0, 1.6, 0),
		Vector3(steep.x, -steep.y, steep.z), BloodTypes.BodyRegion.TORSO, 1.0
	)
	var mean_up := 0.0
	var mean_down := 0.0
	for i in N:
		mean_up += blood.sample_lobe_for_test(ballistic, up_ctx, false).y
		mean_down += blood.sample_lobe_for_test(ballistic, down_ctx, false).y
	mean_up /= N
	mean_down /= N
	_check(
		mean_up > 0.3 and mean_down < -0.3,
		"D: attack pitch is preserved (mean y up %.2f, down %.2f)" % [mean_up, mean_down]
	)

	# --- E. The pattern is ATTACK-RELATIVE, not world-relative. Rotating the
	# whole event must rotate the pattern rigidly: the distribution of angle to
	# the axis is the same whichever way the attack points.
	var spreads: Array[float] = []
	for yaw in [0.0, 1.1, 2.4, -2.0]:
		var dir := Vector3(0, 0, -1).rotated(Vector3.UP, yaw).rotated(Vector3.RIGHT, 0.4)
		var c := BloodContext.make(
			BloodTypes.DamageType.BALLISTIC, Vector3(0, 1.6, 0), dir,
			BloodTypes.BodyRegion.TORSO, 1.0
		)
		var mean := 0.0
		for i in N:
			mean += blood.sample_lobe_for_test(ballistic, c, false).dot(dir)
		spreads.append(mean / N)
	var lo: float = spreads.min()
	var hi: float = spreads.max()
	_check(
		hi - lo < 0.06,
		"E: the pattern rotates rigidly with the attack (%.3f .. %.3f)" % [lo, hi]
	)

	# --- F. No cardinal bias. Azimuth around the attack axis must be uniform:
	# the old construction packed material onto the world axes.
	const SECTORS := 12
	var bins := PackedInt32Array()
	bins.resize(SECTORS)
	var tilted := Vector3(0.3, 0.45, -0.84).normalized()
	var tilt_ctx := BloodContext.make(
		BloodTypes.DamageType.BALLISTIC, Vector3(0, 1.6, 0), tilted,
		BloodTypes.BodyRegion.TORSO, 1.0
	)
	var tframe: Basis = blood.pattern_frame_for_test(tilt_ctx, false)
	for i in N * 2:
		var d: Vector3 = blood.sample_lobe_for_test(ballistic, tilt_ctx, false)
		var angle := atan2(d.dot(tframe.y), d.dot(tframe.x))
		bins[int(wrapf(angle, 0.0, TAU) / TAU * SECTORS) % SECTORS] += 1
	var bmin := N * 2
	var bmax := 0
	for b in bins:
		bmin = mini(bmin, b)
		bmax = maxi(bmax, b)
	_check(
		float(bmax) / maxf(float(bmin), 1.0) < 1.6,
		"F: azimuth around a tilted attack is uniform (max/min %.2f)"
			% (float(bmax) / maxf(float(bmin), 1.0))
	)

	# --- G. A slash fans INSIDE its swing plane, derived from the swing itself
	# and never from "camera side plus random".
	var slash := BloodContext.make(
		BloodTypes.DamageType.SLASHING, Vector3(0, 1.6, 0), Vector3(0, 0, -1),
		BloodTypes.BodyRegion.TORSO, 1.0
	)
	slash.penetration_direction_ws = Vector3(1, 0, 0)
	# A horizontal swing sweeps a horizontal plane, so its normal is world up.
	slash.swing_plane_normal_ws = Vector3.UP
	var in_plane := 0.0
	var out_of_plane := 0.0
	for i in N:
		var d: Vector3 = blood.sample_lobe_for_test(slashing, slash, false)
		in_plane += absf(d.dot(Vector3(0, 0, -1)))
		out_of_plane += absf(d.dot(Vector3.UP))
	_check(
		in_plane > out_of_plane * 1.3,
		"G: a slash fans inside the swing plane (in %.0f vs out %.0f)"
			% [in_plane, out_of_plane]
	)
	var sframe: Basis = blood.pattern_frame_for_test(slash, false)
	_check(
		absf(sframe.y.dot(Vector3.UP)) > 0.99,
		"G: the swing plane normal IS the frame's thin axis (%.3f)"
			% absf(sframe.y.dot(Vector3.UP))
	)

	# --- H. Persistence is consistent: no family quietly self-cleans while the
	# others stay. The arena remembers the whole fight, or none of it.
	var families := {
		"ballistic": ballistic,
		"slashing": slashing,
		"piercing": load("res://data/blood/blood_piercing.tres") as BloodProfile,
		"blunt": load("res://data/blood/blood_blunt.tres") as BloodProfile,
		"high_energy": load("res://data/blood/blood_high_energy.tres") as BloodProfile,
	}
	var transient_families: Array[String] = []
	for key in families:
		if (families[key] as BloodProfile).env_splat_lifetime > 0.0:
			transient_families.append(key)
	_check(
		transient_families.is_empty(),
		"H: every family's world splats are persistent (transient: %s)"
			% str(transient_families)
	)

	blood.queue_free()
	await _tick(2)


## Where a blood event is BORN. A hurtbox NODE sits at the victim's feet, so
## anything that resolves hits by overlap has to sample the real shape or head
## blood appears on the floor.
func _blood_origin() -> void:
	var blood := _make_blood_system()
	var player: Node3D = load("res://gameplay/player/player.tscn").instantiate()
	player.position = Vector3(-60, 0.5, 0)
	add_child(player)
	await _tick(20)
	var rack: WeaponRack = player.get_node("Head/Camera/Weapons")
	var camera: FirstPersonCamera = player.get_node("Head/Camera")

	var dummy := _spawn_dummy(Vector3(-60, 0, -2.0))
	await _tick(6)

	# --- I. The hurtbox itself reports a wound point at the REGION's height.
	var head_box: Hurtbox = dummy.get_node("Hurtboxes/HeadHurtbox")
	_check(head_box != null, "I: the dummy has a head hurtbox")
	if head_box != null:
		var wp: Vector3 = head_box.wound_point(camera.global_position, Vector3(0, 0, -1))
		_check(
			wp.y > dummy.global_position.y + 1.5,
			"I: a head wound point is at head height, not at the feet (y %.2f)" % wp.y
		)
		_check(
			absf(wp.y - head_box.global_position.y) > 1.0,
			"I: the wound point is NOT the hurtbox node origin"
		)

	# --- J. A melee head hit therefore bleeds at head height.
	rack.select(1)  # Twin Daggers
	await _tick(2)
	var melee: MeleeWeapon = player.get_node("Head/Camera/Weapons/TwinDaggers")
	camera.look(Vector2(0.0, -atan2(
		dummy.global_position.y + 2.15 - camera.global_position.y, 2.0
	) / config.mouse_sensitivity))
	await _tick(4)
	melee.try_attack()
	await _tick(40)
	var ctx: BloodContext = blood.last_context
	_check(ctx != null, "J: a melee hit produced a blood context")
	if ctx != null:
		_check(
			ctx.position_ws.y > dummy.global_position.y + 1.2,
			"J: melee blood is born on the body, not at the feet (y %.2f)" % ctx.position_ws.y
		)
		# --- K. The swing plane reached the context.
		_check(
			ctx.swing_plane_normal_ws.length() > 0.5,
			"K: a melee hit carries its swing plane into the blood context"
		)
		_check(
			absf(ctx.swing_plane_normal_ws.dot(-camera.global_basis.z)) < 0.2,
			"K: the swing plane is perpendicular to the way the player faces"
		)

	# --- L. An explosion with NO biological victim creates NO blood. The dummy
	# goes first: the blast radius is 6 m and this check is about an EMPTY room.
	dummy.queue_free()
	await _tick(4)
	rack.select(3)  # Grenade Launcher
	await _tick(2)
	var launcher: GrenadeLauncher = player.get_node("Head/Camera/Weapons/GrenadeLauncher")
	camera.look(Vector2(0.0, 900.0))  # aim at the floor
	await _tick(4)
	var before: int = blood.combat_event_count()
	launcher.try_attack()
	await _seconds(3.5)
	_check(
		blood.combat_event_count() == before,
		"L: a blast with no victim spawns no blood (%d new events)"
			% (blood.combat_event_count() - before)
	)

	# --- M. Overkill survives the hurtbox. It is computed on the VICTIM, and
	# Weapon.apply_hit only duck-types for it - so a hurtbox that does not
	# forward it silently reports zero on every single kill.
	var victim := _spawn_dummy(Vector3(-60, 0, -3.0))
	await _tick(6)
	var body_box: Hurtbox = victim.get_node("Hurtboxes/BodyHurtbox")
	_check(
		body_box.has_method("overkill_ratio"),
		"M: a hurtbox answers overkill_ratio, which is what apply_hit looks for"
	)
	body_box.take_damage(
		combat.dummy_max_health * 3.0, victim.global_position, Vector3(0, 0, -1),
		Hurtbox.ZONE_BODY
	)
	await _tick(2)
	_check(
		body_box.overkill_ratio() > 1.0,
		"M: overkill reaches the blood context through the hurtbox (%.2f)"
			% body_box.overkill_ratio()
	)

	victim.queue_free()
	player.queue_free()
	blood.queue_free()
	await _tick(2)
