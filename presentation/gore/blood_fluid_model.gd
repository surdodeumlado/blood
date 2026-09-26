class_name BloodFluidModel
extends RefCounted

## Pure material calculations. No weapon rules or reservoir mutations.
enum Liquid { MICRO_MIST, FINE, SMALL, MEDIUM, LARGE, GLOB, LIGAMENT }
enum Impact { DEPOSIT, SPREAD, SPLASH, GLANCING, HEAVY_GLOB }

static func category(diameter: float) -> int:
	if diameter < 0.00008: return Liquid.MICRO_MIST
	if diameter < 0.00035: return Liquid.FINE
	if diameter < 0.001: return Liquid.SMALL
	if diameter < 0.002: return Liquid.MEDIUM
	if diameter < 0.004: return Liquid.LARGE
	return Liquid.GLOB

static func equivalent_mass(d: float, p: BloodPhysicsSettings) -> float:
	return p.density * PI * pow(d, 3.0) / 6.0

static func drag_cd(re: float) -> float:
	if re < 1000.0:
		return 24.0 / maxf(re, 0.0001) * (1.0 + 0.15 * pow(maxf(re, 0.0), 0.687))
	return 0.44

static func advance_velocity(v: Vector3, d: float, dt: float, gravity: Vector3, p: BloodPhysicsSettings) -> Vector3:
	var speed := v.length()
	if speed > 0.00001:
		var re := p.air_density * speed * d / p.air_viscosity
		var k := 3.0 * p.air_density * drag_cd(re) / (4.0 * p.density * maxf(d, 0.00002))
		v /= 1.0 + k * speed * dt
	return v + gravity * dt

static func air_weber(d: float, speed: float, p: BloodPhysicsSettings) -> float:
	return p.air_density * speed * speed * d / p.surface_tension

## Explicit arcade descent, not a fluid constant. Called AFTER drag/gravity,
## BEFORE position integration and the existing swept collision. No family gate.
## A continuous force field, not an apex-triggered mode or velocity target.
## Keep ALL aerodynamic response. The small pre-apex contribution joins with
## zero derivative; strong rising arcs receive exactly zero assistance.
static func descent_weight(vertical_speed: float) -> float:
	return 1.0 - smoothstep(-3.0, 0.5, vertical_speed)

static func assist_descent(v: Vector3, previous_y: float, kind: int, diameter: float, dt: float, s: BloodStabilitySettings) -> Vector3:
	if not s.fall_assist_enabled: return v
	if kind == Liquid.LIGAMENT: kind=category(diameter)
	var target:float
	var cap:float
	match kind:
		Liquid.SMALL: target=s.fall_assist_small_target; cap=s.fall_assist_small_cap
		Liquid.MEDIUM: target=s.fall_assist_medium_target; cap=s.fall_assist_medium_cap
		Liquid.LARGE: target=s.fall_assist_large_target; cap=s.fall_assist_large_cap
		Liquid.GLOB: target=s.fall_assist_glob_target; cap=s.fall_assist_glob_cap
		_: return v
	var down := -previous_y
	var weight := descent_weight(previous_y)
	# Targets now locate the smooth force roll-off, NOT identical terminal speeds.
	# Diameter-dependent drag remains, so parcels retain a speed distribution.
	var drive := weight * (1.0 - smoothstep(target * 0.8, cap, down))
	var brake := smoothstep(cap, cap + 2.0, down)
	v.y -= s.fall_assist_acceleration * (drive - brake) * dt
	return v

static func breakup_threshold(d: float, p: BloodPhysicsSettings) -> float:
	var oh := p.viscosity / sqrt(p.density * p.surface_tension * maxf(d, 0.00002))
	return p.breakup_weber * (1.0 + 1.077 * pow(oh, 1.6))

static func render_diameter(d: float, kind: int, p: BloodPhysicsSettings) -> float:
	var cap := p.max_glob_diameter if kind == Liquid.GLOB else p.max_drop_diameter
	if kind == Liquid.LIGAMENT: cap = p.ligament_max_width
	if kind == Liquid.MICRO_MIST: cap = p.mist_max_diameter
	var scale := 1.0
	match kind:
		Liquid.MICRO_MIST: scale = p.render_mist_scale
		Liquid.FINE: scale = p.render_fine_scale
		Liquid.SMALL: scale = p.render_small_scale
		Liquid.MEDIUM: scale = p.render_medium_scale
		Liquid.LARGE: scale = p.render_large_scale
		Liquid.GLOB: scale = p.render_glob_scale
		Liquid.LIGAMENT: scale = p.render_ligament_scale
	return minf(maxf(d * p.diameter_exaggeration, p.min_render_diameter) * scale, cap)

static func stain_render_scale(kind: int, p: BloodPhysicsSettings) -> float:
	match kind:
		Liquid.MEDIUM: return p.stain_medium_render_scale
		Liquid.LARGE, Liquid.LIGAMENT: return p.stain_large_render_scale
		Liquid.GLOB: return p.stain_glob_render_scale
	return 1.0

static func liquid_transform(pos: Vector3, velocity: Vector3, diameter: float, kind: int, age: float, p: BloodPhysicsSettings) -> Transform3D:
	var basis := Basis.IDENTITY
	var speed := velocity.length()
	if speed > 0.001:
		var axis := velocity / speed
		basis = Basis.looking_at(axis, Vector3.RIGHT if absf(axis.y) > 0.95 else Vector3.UP)
	var stretch := clampf(1.0 + speed * 0.015, 1.0, p.max_elongation)
	var width := diameter / sqrt(stretch)
	var length := diameter * stretch
	if kind == Liquid.LIGAMENT:
		width = minf(diameter, p.ligament_max_width)
		length = minf(p.ligament_max_length, width * lerpf(8.0, 3.0, clampf(age / p.ligament_lifetime, 0.0, 1.0)))
	else:
		# The maximum is the LONGEST axis, not merely the transverse diameter.
		length = minf(length, p.max_glob_diameter if kind == Liquid.GLOB else p.max_drop_diameter)
	return Transform3D(basis.scaled_local(Vector3(width, width, length)), pos)

static func impact(d: float, velocity: Vector3, normal: Vector3, surface: BloodSurfaceResponse, p: BloodPhysicsSettings) -> Dictionary:
	var speed := velocity.length()
	var vn := absf(velocity.dot(normal))
	var incidence := vn / maxf(speed, 0.0001)
	var we := p.density * vn * vn * d / p.surface_tension
	var re := p.density * vn * d / p.viscosity
	# Bounded interpolation, inspired by inertial/capillary and viscous scales.
	# NOT an experimentally fitted blood spreading law.
	var spread := clampf(minf(pow(1.0 + we, 0.20), pow(1.0 + re, 0.16)) * 0.65, 0.72, 1.65) * surface.spread
	var aspect := clampf(1.0 / sqrt(incidence * incidence + 0.075 * (1.0 - incidence * incidence)), 1.0, p.max_stain_aspect)
	var splash := we * surface.splash_multiplier >= p.splash_weber and re >= p.splash_min_reynolds
	var outcome := Impact.DEPOSIT
	if we > 10.0: outcome = Impact.SPREAD
	if d >= 0.004: outcome = Impact.HEAVY_GLOB
	if splash: outcome = Impact.SPLASH
	if incidence < p.glancing_sine and speed > 0.5: outcome = Impact.GLANCING
	return {"we": we, "re": re, "incidence": incidence, "aspect": aspect, "spread": spread,
		"splash": splash, "outcome": outcome, "surface": surface.label}

static func retention_ratio(mass: float, width: float, normal: Vector3, gravity: Vector3, surface: BloodSurfaceResponse, p: BloodPhysicsSettings) -> float:
	var drive := mass * p.kilograms_per_unit * gravity.slide(normal).length()
	var hold := p.surface_tension * maxf(width, 0.001) * surface.retention
	return drive / maxf(hold, 0.000001)

static func castoff_fraction(load: float, tip_velocity: Vector3, angular_speed: float, p: BloodPhysicsSettings) -> float:
	if load <= 0.0 or tip_velocity.length() < p.castoff_min_tip_speed: return 0.0
	# Centripetal acceleration proxy: omega * tangential speed. Adhesion falls
	# relative to inertia as the available load grows. Authored, not calibrated.
	var acceleration := absf(angular_speed) * tip_velocity.length()
	var threshold := p.castoff_min_acceleration / sqrt(maxf(load, 0.05))
	return clampf((acceleration / threshold - 1.0) * 0.3, 0.0, 1.0)
