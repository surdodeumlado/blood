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
// INSTANCE_CUSTOM carries it now:
//     .x  atlas column
//     .y  atlas row
//     .z  fade opacity
//     .w  integer mask mode + fractional directional taper (0..0.45)
//
// Everything else stays deliberately cheap: unshaded, one texture fetch, no
// depth write, no shadows. Compatibility (GLES3) safe - no compute, no storage
// buffers, no features beyond core MultiMesh instance data.

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
uniform float base_lobe_amount = 0.055;

// IMPACT BLOOM.
//
// A drop used to hit a surface and its final footprint appeared in one frame,
// which breaks the continuity between the airborne blood and the mark it makes.
// The mark now starts small at the contact point and SPREADS to its footprint.
//
// Done entirely in the shader. The quad is already at its final supported size
// and never moves; only the visible mask expands, so this costs no per-frame
// CPU writes, no extra buffer commits and no dirty flags for hundreds of
// stains - which is what the performance budget requires.
//
// Birth time rides in the fractional part of the atlas ROW channel. Rows are
// whole numbers (0 or 1), so the fraction was free. It wraps on a window far
// longer than any bloom, and the wrap is handled below.
uniform float bloom_window = 8.0;
uniform float bloom_duration = 0.11;
uniform float bloom_initial = 0.22;

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
	rivulet = floor(INSTANCE_CUSTOM.w + 0.001);
	tail = fract(INSTANCE_CUSTOM.w);
	fade_alpha = INSTANCE_CUSTOM.z;
	patch_seed = MODEL_MATRIX[3].xz * 3.7 + vec2(MODEL_MATRIX[3].y * 5.1);
	vec2 cell = vec2(INSTANCE_CUSTOM.x, floor(INSTANCE_CUSTOM.y));
	atlas_cell = cell;

	// Age since this mark was laid, from the packed birth time.
	float birth = fract(INSTANCE_CUSTOM.y) * bloom_window;
	float now = mod(TIME, bloom_window);
	float age = now - birth;
	if (age < 0.0) { age += bloom_window; }
	// Smoothstep so the spread decelerates into its final size rather than
	// stopping dead. A mark older than the window is simply fully grown.
	float t = clamp(age / max(bloom_duration, 0.001), 0.0, 1.0);
	bloom = mix(bloom_initial, 1.0, smoothstep(0.0, 1.0, t));
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
		// THE SAW BLADE LIVED HERE.
		//
		// The radius was perturbed by noise at frequencies 6 / 19 / 47 with a
		// combined amplitude of +-0.13 on a 0.375 radius - about 35% radial
		// variation, most of it from the 47-frequency term. High-frequency
		// variation in a RADIUS is, by construction, radial spikes: a star.
		//
		// Now: one low-frequency lobe carries almost all of the irregularity,
		// with a small mid term for a little unevenness and nothing above it.
		// Combined worst case is about 9% and typical is 3-6%, which is the
		// "subtle perimeter irregularity" the brief asks for.
		float low = patch_noise(p * base_lobe_frequency + patch_seed);
		float middle = patch_noise(p * base_lobe_frequency * 2.7 + patch_seed + vec2(7.2));
		float radius = 0.375
			+ (low - 0.5) * base_lobe_amount
			+ (middle - 0.5) * base_lobe_amount * 0.3;
		float edge = length(p) - radius * bloom;
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
