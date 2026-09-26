class_name BloodFlightPresentation
extends RefCounted
## Pure visual scale. Never fed back into diameter, drag, collision or parcel mass.
static func diameter(base: float, kind: int, distance: float, pixels_per_radian: float, s: BloodStabilitySettings) -> float:
	if kind < BloodFluidModel.Liquid.SMALL or kind == BloodFluidModel.Liquid.LIGAMENT: return base
	if s.blood_rain_debug_extreme and kind >= BloodFluidModel.Liquid.MEDIUM:
		return minf(0.32, maxf(base, 20.0 * maxf(distance, 2.0) / maxf(pixels_per_radian, 1.0)))
	var pixels := s.small_min_pixels
	var cap := s.small_render_cap_m
	if kind == BloodFluidModel.Liquid.MEDIUM:
		pixels = s.rain_medium_min_pixels if s.rain_enabled else s.medium_min_pixels; cap = s.medium_render_cap_m
	elif kind >= BloodFluidModel.Liquid.LARGE:
		pixels = s.rain_large_min_pixels if s.rain_enabled else s.large_min_pixels
		cap = s.glob_render_cap_m if kind == BloodFluidModel.Liquid.GLOB else s.large_render_cap_m
	var requested := pixels * distance / maxf(pixels_per_radian, 1.0)
	var assisted := minf(maxf(base, requested), cap)
	return lerpf(base, assisted, clampf(distance / s.near_readability_ramp_m, 0.0, 1.0))

static func explosive_velocity(velocity: Vector3, kind: int, s: BloodStabilitySettings, high_arc := false) -> Vector3:
	# One-time launch distribution: horizontal explosion expansion remains,
	# visible rain carriers have downward momentum before gravity integration.
	# No per-frame fall mode, gravity override or change to drag.
	if not s.rain_enabled: return velocity
	if high_arc and not s.rain_rejected_baseline_debug:
		# Keep the actual sampled upward/outward direction; bounded launch only.
		return velocity.limit_length(s.rain_high_arc_medium_speed_cap if kind==BloodFluidModel.Liquid.MEDIUM else s.rain_high_arc_speed_cap)
	var direction_y := velocity.normalized().y
	if kind >= BloodFluidModel.Liquid.MEDIUM: velocity *= s.rain_launch_speed_scale
	if kind >= BloodFluidModel.Liquid.MEDIUM and kind <= BloodFluidModel.Liquid.GLOB:
		if not s.rain_rejected_baseline_debug:
			# Excess transverse launch speed caused immediate breakup and drained
			# vertical momentum through vector drag. Bound only initial impulse.
			var horizontal:=Vector2(velocity.x,velocity.z).limit_length(s.rain_carrier_horizontal_cap_m_s)
			velocity.x=horizontal.x; velocity.z=horizontal.y
		var down := s.rain_medium_downward_m_s
		if kind == BloodFluidModel.Liquid.LARGE: down = s.rain_large_downward_m_s
		if kind == BloodFluidModel.Liquid.GLOB: down = s.rain_glob_downward_m_s
		velocity.y = -down + direction_y * s.rain_launch_vertical_spread_m_s
		return velocity
	if velocity.y <= 0.0: return velocity
	if s.blood_rain_debug_extreme and kind >= BloodFluidModel.Liquid.MEDIUM:
		velocity.y *= 0.05
		return velocity
	if kind == BloodFluidModel.Liquid.GLOB: velocity.y *= s.glob_upward_scale
	elif kind == BloodFluidModel.Liquid.LARGE: velocity.y *= s.heavy_upward_scale
	elif kind == BloodFluidModel.Liquid.MEDIUM: velocity.y *= s.rain_medium_upward_scale
	return velocity

static func streak_dimensions(kind: int, speed: float, distance: float, focal: float, falling: bool, s: BloodStabilitySettings) -> Vector2:
	if kind < BloodFluidModel.Liquid.SMALL or speed < s.rain_streak_min_speed: return Vector2.ZERO
	var cap := s.rain_streak_medium_cap_m
	if kind == BloodFluidModel.Liquid.LARGE: cap = s.rain_streak_large_cap_m
	elif kind == BloodFluidModel.Liquid.GLOB: cap = 0.65
	elif kind == BloodFluidModel.Liquid.SMALL or kind == BloodFluidModel.Liquid.LIGAMENT: cap = 0.65
	var length := minf(speed * s.rain_streak_exposure_s, cap)
	if falling:
		length = minf(cap, maxf(length, s.rain_streak_min_pixels * distance / maxf(focal,1.0)))
	var width := clampf(s.rain_streak_width_pixels * distance / maxf(focal,1.0), s.rain_streak_width_min_m, s.rain_streak_width_max_m)
	if kind == BloodFluidModel.Liquid.GLOB: width *= 1.3
	width = minf(width, length / 15.0)
	return Vector2(width,length)

static func rain_tail(kind: int, speed: float, s: BloodStabilitySettings, distance := 0.0, focal := 360.0, falling := false) -> float:
	if kind < BloodFluidModel.Liquid.SMALL or speed <= 1.4: return 0.0
	if s.blood_rain_debug_extreme and kind >= BloodFluidModel.Liquid.MEDIUM:
		return minf(1.2, (speed - 1.4) * 0.16)
	var weight := 0.65 if kind == BloodFluidModel.Liquid.SMALL else 1.0
	if kind == BloodFluidModel.Liquid.GLOB: weight = 0.62
	if kind == BloodFluidModel.Liquid.LIGAMENT: weight = 0.45
	var length := speed * s.rain_exposure_s * weight
	if falling and kind >= BloodFluidModel.Liquid.MEDIUM and kind <= BloodFluidModel.Liquid.GLOB:
		length = maxf(length, s.falling_trail_min_pixels * distance / maxf(focal, 1.0))
	return minf(s.rain_tail_cap_m * weight, length)

static func trail_priority(kind: int, velocity: Vector3, distance_squared: float, in_front: bool, s: BloodStabilitySettings) -> int:
	var relevant := in_front and distance_squared < s.importance_distance_m * s.importance_distance_m
	if not relevant: return 4
	if kind >= BloodFluidModel.Liquid.MEDIUM and kind <= BloodFluidModel.Liquid.GLOB and velocity.y < -1.0: return 0
	if kind == BloodFluidModel.Liquid.LARGE or kind == BloodFluidModel.Liquid.GLOB: return 1
	if kind >= BloodFluidModel.Liquid.MEDIUM: return 2
	return 3
