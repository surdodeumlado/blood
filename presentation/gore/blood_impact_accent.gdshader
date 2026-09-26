shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
// Independent transient layer. Never consumes stain custom data or wet mass.
uniform float accent_clock = 0.0;
uniform float irregularity = 0.0;
varying float age;
varying float bias;
varying float phase;
void vertex() {
	age = clamp((accent_clock - INSTANCE_CUSTOM.x) / max(INSTANCE_CUSTOM.y, 0.001), 0.0, 1.0);
	bias = INSTANCE_CUSTOM.z;
	phase = INSTANCE_CUSTOM.w;
}
void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float ink = 0.0;
	// Six tiny moving kicks, not an opaque disc or a persistent crown.
	for (int i = 0; i < 6; i++) {
		float jitter = fract(sin(float(i) * 17.13 + phase * 7.1) * 437.31);
		float angle = float(i) * 1.047198 + phase + (jitter - 0.5) * irregularity;
		vec2 axis = vec2(cos(angle), sin(angle));
		float local_age = clamp(age - jitter * 0.17 * irregularity, 0.0, 1.0);
		vec2 centre = axis * (0.12 + local_age * (0.62 - jitter * 0.2 * irregularity)) + vec2(bias * age * 0.18, 0.0);
		vec2 q = p - centre;
		float forward = dot(q, axis) / (0.11 + age * 0.06);
		float side = dot(q, vec2(-axis.y, axis.x)) / (0.055 * (1.0 + (jitter - 0.5) * irregularity));
		float edge = length(vec2(forward, side));
		float aa = max(fwidth(edge), 0.02);
		float weight = 1.0 - bias * max(-axis.x, 0.0) * 0.8;
		weight *= 1.0 - jitter * irregularity * 0.55;
		ink = max(ink, (1.0 - smoothstep(1.0 - aa, 1.0 + aa, edge)) * weight);
	}
	ALBEDO = COLOR.rgb;
	ALPHA = ink * COLOR.a * (1.0 - age) * 0.8;
}
