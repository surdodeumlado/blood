shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// PER-INSTANCE ATLAS SELECTION.
//
// This shader exists because StandardMaterial3D cannot do the one thing the
// stain layer needs: let every MultiMesh instance pick its OWN cell of a shared
// atlas. The previous material set uv1_scale to one cell and wrote the wanted
// cell into per-instance custom data - but nothing consumed that data, so all
// 3200 stains sampled cell (0,0) and the entire arena was painted in TINY_DROP
// regardless of what shape the system had chosen.
//
// Surface CUSTOM: X=shape+8*mode+tail, Y=absolute birth, Z=fade,
// W=integer seed percent + duration (<1 second). See BloodSurfacePresentation.

uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
// Atlas layout. Seven shapes live in a 4x2 grid.
uniform vec2 atlas_cells = vec2(4.0, 2.0);
// Half-texel inset, so linear filtering at a cell edge cannot bleed the
// neighbouring shape into this one.
uniform float cell_inset = 0.002;

// EDGE IRREGULARITY BUDGET.
//
// Kept as uniforms because "how jagged is a bloodstain" is a look decision that
// wants tuning, not a constant buried in the fragment maths. Low frequencies
// give uneven lobes; high frequencies give teeth, which is what these replaced.
uniform float warp_frequency = 5.5;
uniform float warp_amount = 0.016;
uniform float base_lobe_frequency = 2.6;
uniform float base_lobe_amount = 0.10;

// One shared monotonic simulation clock, never global TIME/modulo.
uniform float blood_clock = 0.0;

varying float rivulet;
varying vec2 patch_seed;
varying vec2 atlas_cell;
varying float fade_alpha;
varying float tail;
varying float bloom;

float hash_cell(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float patch_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash_cell(i), hash_cell(i + vec2(1.0, 0.0)), f.x),
		mix(hash_cell(i + vec2(0.0, 1.0)), hash_cell(i + vec2(1.0)), f.x), f.y);
}

void vertex() {
	float encoded_id = floor(INSTANCE_CUSTOM.x);
	rivulet = floor(encoded_id / 8.0);
	float shape = mod(encoded_id, 8.0);
	tail = fract(INSTANCE_CUSTOM.x);
	fade_alpha = clamp(INSTANCE_CUSTOM.z, 0.0, 1.0);
	patch_seed = MODEL_MATRIX[3].xz * 3.7 + vec2(MODEL_MATRIX[3].y * 5.1);
	atlas_cell = vec2(mod(shape, 4.0), floor(shape / 4.0));
	float duration = fract(INSTANCE_CUSTOM.w);
	float age = max(blood_clock - INSTANCE_CUSTOM.y, 0.0);
	float t = duration > 0.001 ? clamp(age / duration, 0.0, 1.0) : 1.0;
	bloom = mix(floor(INSTANCE_CUSTOM.w) * 0.01, 1.0, smoothstep(0.0, 1.0, t));
}
void fragment() {
	vec2 p = UV - vec2(0.5);
	// ORGANIC IRREGULARITY, NOT A PROCEDURAL STARBURST.
	//
	// This used to be sin(p * 19) and sin(p * 23) at 0.035 amplitude: roughly
	// three full periods across the quad on each axis, which is a repeating
	// ripple. Combined with the radial mask below it read as serrated teeth.
	//
	// Now it is ONE low-frequency lobe per axis - an uneven bulge, not a wave -
	// at a much smaller amplitude, so a mark is asymmetric rather than toothed.
	vec2 warp = vec2(
		sin(p.y * warp_frequency + patch_seed.x),
		sin(p.x * warp_frequency * 1.17 + patch_seed.y)
	);
	vec2 shaped = p + warp * warp_amount * (1.0 - smoothstep(0.3, 0.5, length(p)));
	shaped.y *= 1.0 + tail * max(p.x, 0.0) * 5.0;
	// SPATIAL growth, not an alpha fade: dividing the sample coordinate by the
	// bloom makes the UV reach the transparent rim sooner, so the visible blood
	// AREA is what expands. Because it scales `shaped` - which already carries
	// the directional taper and warp - an oblique mark blooms along its own
	// final elongated geometry instead of growing round and then stretching.
	shaped /= max(bloom, 0.001);
	vec2 local_uv = clamp(shaped + vec2(0.5), vec2(cell_inset), vec2(1.0 - cell_inset));
	vec4 texel = texture(atlas, (local_uv + atlas_cell) / atlas_cells);
	ALBEDO = COLOR.rgb;
	ALPHA = texel.a * COLOR.a;
	if (rivulet > 1.5) {
		// Large bases use a procedural antialiased edge, independent of atlas
		// texel density. Existing smaller impact marks remain a separate overlay.
		p = shaped;
		// Broad asymmetry, no high-frequency radial teeth.
		float low = patch_noise(p * base_lobe_frequency + patch_seed);
		float middle = patch_noise(p * base_lobe_frequency * 2.7 + patch_seed + vec2(7.2));
		float radius = 0.365
			+ (low - 0.5) * base_lobe_amount
			+ (middle - 0.5) * base_lobe_amount * 0.3;
		// An offset low-frequency lobe, not a repeated star-shaped radial wave.
		p.x += 0.025 * sin(p.y * 4.0 + patch_seed.y);
		float edge = length(p) - radius;
		float aa = max(fwidth(edge), 0.002);
		ALPHA = (1.0 - smoothstep(-aa, aa, edge)) * COLOR.a;
		ALBEDO *= 0.97 + 0.03 * middle;
	} else if (rivulet > 0.5) {
		// Dedicated connected mask: the decorative STREAK atlas has separated
		// tail lobes and cannot guarantee a continuous rivulet between samples.
		vec2 q = abs(UV - vec2(0.5)) - vec2(0.35);
		float edge = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - 0.15;
		ALPHA = (1.0 - smoothstep(-0.035, 0.0, edge)) * COLOR.a;
	}
	ALPHA *= fade_alpha;
}
