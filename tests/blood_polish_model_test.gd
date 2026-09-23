extends SceneTree
## Small CPU contract fixture: no MultiMesh, world simulation or audio playback.
var failures: Array[String] = []
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print(("PASS " if ok else "FAIL ") + label)

func _initialize() -> void:
	var config: ReservoirConfig = load("res://data/blood/reservoir_defaults.tres")
	var reservoir := BloodReservoir.new()
	reservoir.config = config
	for families in [[BloodTypes.DamageType.HIGH_ENERGY, BloodTypes.DamageType.BALLISTIC],
		[BloodTypes.DamageType.HIGH_ENERGY, BloodTypes.DamageType.SLASHING],
		[BloodTypes.DamageType.BLUNT, BloodTypes.DamageType.BALLISTIC]]:
		reservoir.refill()
		var first := BloodContext.make(families[0], Vector3.ZERO, Vector3.FORWARD, BloodTypes.BodyRegion.HEAD, 2.4)
		var original_unbounded := config.hit_blood_fraction * config.family_scale(families[0]) * config.head_multiplier * (1 + (first.energy - 1) * config.energy_influence)
		var a := reservoir.withdraw(first)
		check(a.blood_mass <= config.max_nonlethal_fraction and reservoir.remaining_blood > 0, "nonlethal family %d retains living stock (old demand %.3f)" % [families[0], original_unbounded])
		var b := reservoir.withdraw(BloodContext.make(families[1], Vector3.ZERO, Vector3.FORWARD, BloodTypes.BodyRegion.TORSO))
		check(b.family() == families[1] and b.blood_mass > 0, "subsequent family %d creates a positive release" % families[1])
		check(is_equal_approx(reservoir.remaining_blood + a.blood_mass + b.blood_mass, 1.0), "no replenishment or invented mass")
	reservoir.free()
	var fluid: BloodPhysicsSettings = load("res://data/blood/blood_physics.tres")
	var surface: BloodSurfaceResponse = load("res://data/blood/surfaces/smooth.tres")
	var previous := 0.0
	for angle in [90, 60, 45, 30, 15]:
		var r := deg_to_rad(angle)
		var response := BloodFluidModel.impact(0.003, Vector3(cos(r), -sin(r), 0) * 5, Vector3.UP, surface, fluid)
		check(response.aspect >= previous, "incidence %d preserves increasing directional aspect" % angle)
		previous = response.aspect
	print("POLISH MODEL: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
