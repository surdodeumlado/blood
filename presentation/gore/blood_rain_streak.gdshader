shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
// Rectangular core, tiny edge fade. No round head, capsule, saw teeth or TIME.
void fragment() {
	float side = abs(UV.x - 0.5) * 2.0;
	float width = 0.93 + 0.05 * UV.y;
	float aa = max(fwidth(side),0.015);
	float across = 1.0 - smoothstep(width-aa,width,side);
	float ends = smoothstep(0.0,0.045,UV.y) * (1.0-smoothstep(0.91,1.0,UV.y));
	ALBEDO=COLOR.rgb;
	ALPHA=COLOR.a * across * ends * 0.86;
}
