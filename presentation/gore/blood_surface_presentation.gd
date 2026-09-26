class_name BloodSurfacePresentation
extends RefCounted
## Surface-only CUSTOM contract. Liquid/tissue layers use their own materials.
## X = shape + 8 * mode + tail (<0.5), Y = absolute system birth seconds,
## Z = retirement alpha, W = integer seed percent + fractional duration seconds.
## Duration zero means mature (pools/runoff own spatial growth on CPU).
static func encode(legacy: Color, birth: float, duration := 0.0, initial := 1.0) -> Color:
	var shape := clampi(int(legacy.r) + 4 * int(legacy.g), 0, 7)
	var mode := clampi(int(legacy.a), 0, 2)
	return Color(shape + mode * 8 + clampf(fmod(legacy.a, 1.0), 0.0, 0.45), birth,
		clampf(legacy.b, 0.0, 1.0), floor(clampf(initial, 0.01, 1.0) * 100.0) + clampf(duration, 0.0, 0.45))

static func growth(custom: Color, clock: float) -> float:
	var duration := fmod(custom.a, 1.0)
	if duration < 0.001: return 1.0
	var t := clampf((clock - custom.g) / duration, 0.0, 1.0)
	return lerpf(floor(custom.a) * 0.01, 1.0, t * t * (3.0 - 2.0 * t))
