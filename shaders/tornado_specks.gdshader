shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// Small bits of dirt and leaves that the twister carries: one MultiMesh of quads
// whose orbit is computed HERE from TIME (see TornadoVisual) — one draw call, no
// tick. Each speck spirals from the ground up the funnel wall and starts over.
//
// They are deliberately tiny against a unit (a brave is 1.44 m tall): the specks
// are dressing, the whirled-up units must stay the thing the eye follows.
//
// INSTANCE_CUSTOM: x = angle offset (0..1), y = height offset (0..1),
//                  z = speed factor (0..1), w = size / shade seed (0..1).
// Mesh: a unit quad in the XY plane (-0.5..0.5); the node is scaled so that mesh
// x/z = funnel radius and mesh y = funnel height.

// Orbit radius at the ground and at the mouth, in mesh units.
uniform float r_low = 0.35;
uniform float r_high = 1.5;
// Edge length of a speck in metres (varied per instance).
uniform float size = 0.16;
uniform vec3 color_a : source_color = vec3(0.34, 0.27, 0.19);
uniform vec3 color_b : source_color = vec3(0.50, 0.47, 0.36);
// Same meaning as in tornado_funnel.gdshader.
uniform float grow = 1.0;
uniform float opacity = 1.0;
uniform float phase = 0.0;

varying float v_fade;
varying float v_shade;

void vertex() {
	float speed = INSTANCE_CUSTOM.z;
	float seed = INSTANCE_CUSTOM.w;
	float climb = fract(INSTANCE_CUSTOM.y + TIME * (0.16 + 0.2 * speed));
	float ang = (INSTANCE_CUSTOM.x + TIME * (0.7 + 0.6 * speed)) * TAU + phase;
	float r = mix(r_low, r_high, climb) * (0.82 + 0.3 * seed);
	vec3 centre = vec3(cos(ang) * r, climb * grow, sin(ang) * r);
	vec4 view_centre = MODELVIEW_MATRIX * vec4(centre, 1.0);
	// Billboard in view space, so the node's non-uniform scale never stretches a
	// speck; it tumbles around the view axis.
	float rot = TIME * (3.0 + 5.0 * speed) + INSTANCE_CUSTOM.x * 40.0;
	vec2 q = vec2(VERTEX.x * cos(rot) - VERTEX.y * sin(rot),
		VERTEX.x * sin(rot) + VERTEX.y * cos(rot));
	view_centre.xy += q * size * (0.6 + 0.8 * seed);
	POSITION = PROJECTION_MATRIX * view_centre;
	// Fades in at the ground and out before it wraps back down.
	v_fade = smoothstep(0.0, 0.08, climb) * (1.0 - smoothstep(0.78, 1.0, climb));
	v_shade = seed;
}

void fragment() {
	// A flat shard rather than a dot: twice as long as it is high.
	vec2 d = abs(UV - vec2(0.5));
	float a = 1.0 - smoothstep(0.3, 0.5, max(d.x, d.y * 2.0));
	ALBEDO = mix(color_a, color_b, v_shade);
	ALPHA = a * v_fade * opacity;
}
