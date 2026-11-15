shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// The wall of a twister: streaks of noise that run around the axis, lean with the
// height and climb. One surface of revolution per layer (see TornadoVisual) — no
// tick, no particles, no texture, no screen or depth read. House style like the
// waterfall: a static mesh whose pattern is scrolled here.
//
// Mesh convention: UV.x = angle around the axis (0..1, seam at 0/1), UV.y = height
// (0 = ground end, 1 = far end). NORMAL points radially outward.
//
// Whirled-up units have to stay readable (user spec): the layers are kept thin by
// `max_alpha` and `coverage` — the dense core stays INSIDE the circle the riders
// fly on, and only the faint veil ever lies in front of them.

// Colour of the wall, and what it turns into near the ground (kicked-up dust).
uniform vec3 tint : source_color = vec3(0.80, 0.81, 0.85);
uniform vec3 tint_low : source_color = vec3(0.62, 0.56, 0.47);
// Up to this share of the height the dust colour bleeds into the wall.
uniform float low_reach = 0.3;
// Opacity of the densest streak, and the share of the wall that carries streaks.
uniform float max_alpha = 0.7;
uniform float coverage = 0.5;
// Share of that opacity the NEAR wall keeps (the half of the surface between
// the camera and the axis). Below 1 the far wall carries the shape while the
// near one stays thin — whatever flies inside the layer shows through it.
uniform float near_alpha = 1.0;
// Opacity of the wall BETWEEN the streaks, as a share of max_alpha: the body of
// the funnel. 0 = only streaks hang in the air.
uniform float fill = 0.25;
// Half-width of the streak edge in noise units: small = hard-edged bands.
uniform float edge = 0.09;
// Strength of the thin wind lines drawn on top of the broad streaks (0 = none).
uniform float wisps = 0.8;
// Pattern repeats around the axis. MUST be a whole number (the seam).
uniform float streaks = 3.0;
// Pattern repeats over the height.
uniform float tile_v = 2.0;
// Lean of the streaks: pattern tiles the wall is wound by over its height.
uniform float twist = 1.0;
// Pattern tiles per second around the axis / up the wall.
uniform float spin = 2.4;
uniform float rise = 0.6;
// Sideways wobble of the axis at the far end, in mesh units (0 = rigid).
uniform float sway = 0.1;
// Over how much of the height the wall fades in at the ground / out at the far end.
uniform float fade_bottom = 0.06;
uniform float fade_top = 0.25;
// 0..1 build-up (the funnel rises out of the ground) and overall opacity.
uniform float grow = 1.0;
uniform float opacity = 1.0;
// Per-twister offset so three funnels do not move in step.
uniform float phase = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Value noise that repeats every `period` cells in x (the seam around the axis).
// y is wrapped at 64 cells only to keep the hash input small as TIME grows.
float wall_noise(vec2 p, float period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float x0 = mod(i.x, period);
	float x1 = mod(i.x + 1.0, period);
	float y0 = mod(i.y, 64.0);
	float y1 = mod(i.y + 1.0, 64.0);
	float a = hash21(vec2(x0, y0));
	float b = hash21(vec2(x1, y0));
	float c = hash21(vec2(x0, y1));
	float d = hash21(vec2(x1, y1));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	float t = UV.y;
	// The axis snakes: more with the height, never at the ground.
	float w = TIME * 1.7 + phase + t * 2.6;
	VERTEX.x += sin(w) * sway * t * t;
	VERTEX.z += cos(w * 0.81 + 1.3) * sway * t * t;
	// Build-up: the funnel rises out of the ground and widens as it does.
	VERTEX.y *= grow;
	VERTEX.xz *= mix(0.4, 1.0, grow);
}

void fragment() {
	float t = UV.y;
	vec2 p = vec2(UV.x * streaks + t * twist - TIME * spin, t * tile_v - TIME * rise + phase);
	float n = wall_noise(p, streaks) * 0.62
		+ wall_noise(p * vec2(2.0, 1.7) + vec2(0.0, 3.1), streaks * 2.0) * 0.38;
	float streak = smoothstep(1.0 - coverage - edge, 1.0 - coverage + edge, n);
	// Thin wind lines: the ridge of a second, flatter noise field.
	float ridge = 1.0 - abs(2.0 * wall_noise(p * vec2(1.0, 2.3) + vec2(1.7, 0.0), streaks) - 1.0);
	streak = max(streak, smoothstep(0.86, 0.97, ridge) * wisps);
	float a = mix(fill, 1.0, streak);
	a *= smoothstep(0.0, fade_bottom, t) * (1.0 - smoothstep(1.0 - fade_top, 1.0, t));
	// Soften the silhouette: where the wall turns edge-on it would draw a hard line.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	a *= mix(0.6, 1.0, smoothstep(0.0, 0.45, facing));
	// Streaks are the lit crests, the wall between them is the darker body.
	ALBEDO = mix(tint_low, tint, smoothstep(0.0, low_reach, t)) * mix(0.72, 1.1, streak);
	// The mesh is wound so that its INNER side is the front face: front-facing
	// fragments are the far wall, the rest is the wall toward the camera.
	ALPHA = a * max_alpha * opacity * (FRONT_FACING ? 1.0 : near_alpha);
}
