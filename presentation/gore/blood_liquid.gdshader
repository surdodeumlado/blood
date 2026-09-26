shader_type spatial;
render_mode unshaded;

// Rounded mesh normals provide a restrained curved-body cue even in dark rooms.
// Readability shading, not a physically based optical model of blood.
uniform vec4 wet_highlight_color : source_color = vec4(1.0, 0.322, 0.424, 1.0);
varying float wake_fade;

// Final bounded screen-readability scale is submitted in the instance basis.
// Only X is used here: rear-tail length in local coordinates. No simulation state.
void vertex() {
	// +Z is behind velocity in the submitted basis. Extend only rear vertices
	// into a short tapered wake; the front remains the physical readable bead.
	float rear = max(VERTEX.z * 2.0, 0.0);
	wake_fade = rear * clamp(INSTANCE_CUSTOM.x, 0.0, 1.0);
	VERTEX.xy *= 1.0 - 0.5 * rear * clamp(INSTANCE_CUSTOM.x, 0.0, 1.0);
	VERTEX.z += INSTANCE_CUSTOM.x * rear * rear;
}
void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float glaze = pow(max(dot(normalize(NORMAL), normalize(vec3(-0.35, 0.55, 0.8))), 0.0), 28.0);
	ALBEDO = mix(COLOR.rgb * (0.78 + 0.22 * facing), wet_highlight_color.rgb, 0.18 * glaze);
	// Rounded opaque head; tapered wake loses opacity towards its rear.
	ALPHA = COLOR.a * (1.0 - 0.7 * wake_fade * wake_fade);
}
