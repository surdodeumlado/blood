shader_type spatial;
render_mode unshaded;

// Rounded mesh normals provide a restrained curved-body cue even in dark rooms.
// Readability shading, not a physically based optical model of blood.
uniform vec4 wet_highlight_color : source_color = vec4(1.0, 0.322, 0.424, 1.0);

// AIRBORNE READABILITY. Visual only.
//
// SIMULATION SIZE and RENDER SIZE are different things. A droplet that is
// physically correct at 3 mm is about one pixel across the room, so the blood
// that carries the event is invisible exactly when the player is watching it.
//
// This scales the rendered mesh ONLY. It runs in the vertex stage and touches
// nothing the simulation reads: drag, collision, represented mass, physical
// diameter, impact energy and stain mass all still use the true diameter.
//
//   near  (under readability_ref_m)  gain 1.0 - no giant blobs in your face
//   mid                              grows toward the clamp - the useful range
//   far   (at readability_max)       stops - bounded, never unbounded scaling
uniform float readability_gain = 1.0;
uniform float readability_ref_m = 5.0;
uniform float readability_max = 2.4;

void vertex() {
	// +Z is behind velocity in the submitted basis. Extend only rear vertices
	// into a short tapered wake; the front remains the physical readable bead.
	float rear = max(VERTEX.z * 2.0, 0.0);
	VERTEX.xy *= 1.0 - 0.5 * rear * clamp(INSTANCE_CUSTOM.x, 0.0, 1.0);
	VERTEX.z += INSTANCE_CUSTOM.x * rear * rear;

	// Applied last, so the wake grows with the bead rather than detaching.
	float dist = length(MODEL_MATRIX[3].xyz - CAMERA_POSITION_WORLD);
	float grow = clamp(dist / max(readability_ref_m, 0.01), 1.0, readability_max);
	VERTEX *= readability_gain * grow;
}
void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float glaze = pow(max(dot(normalize(NORMAL), normalize(vec3(-0.35, 0.55, 0.8))), 0.0), 28.0);
	ALBEDO = mix(COLOR.rgb * (0.78 + 0.22 * facing), wet_highlight_color.rgb, 0.18 * glaze);
}
