shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

// Phase 10j: the water that reaches the disc's rim pours off into space. A static
// curtain around the submerged part of the rim (see TerrainRim), with the pattern
// scrolled downward — one draw call, no tick, no particles. The project has
// no GPUParticles3D anywhere; the house style is MultiMesh plus animated meshes.
//
// 2026-11-15 (user: "der Wasserfall ist nicht wirklich sichtbar"). Two causes:
//   * The fade read UV.y as if it ran 0..1 over the fall — it runs 0..height in
//     TILES (4,25 for a 34-m fall), so the curtain was fully transparent 8 m
//     below the lip. The fall fraction now comes from `height_tiles`.
//   * It was a LIT surface hanging in the void, where only the dim ambient light
//     reaches a vertical face: near black against the black sky. It is now
//     UNSHADED — the water carries its own light, as if lit from the depth it
//     falls into (`glow`) — so it reads from every side.
// It also leaves the lip in a short ARC (`arc_out`) before it drops straight
// down: a curtain hanging exactly under the edge is hidden by that very edge
// from the game camera, which looks down from inside the disc.
//
// The colours are the SAME uniforms as the sea (water.gdshader) so the lip cannot
// drift out of tune with the surface it flows out of.

uniform vec3 deep : source_color = vec3(0.055, 0.16, 0.40);
uniform vec3 crest : source_color = vec3(0.13, 0.30, 0.58);
// Metres of UV travel per second.
uniform float scroll_speed = 1.6;
// Vertical tiling length in metres — how tall one repeat of the streak pattern is.
uniform float tile = 8.0;
// Height of the whole fall in tiles (mesh UV.y at the bottom edge).
uniform float height_tiles = 4.25;
// Over how much of the fall the alpha fades out toward the bottom (0..1 of height).
uniform float fade_fraction = 0.45;
// How far the water shoots out past the lip (metres) and over which drop (metres)
// it reaches that distance before falling straight.
uniform float arc_out = 1.4;
uniform float arc_drop = 3.0;
// Light the water carries: tint and strength of the glow that grows with depth.
uniform vec3 glow : source_color = vec3(0.55, 0.80, 1.0);
uniform float glow_strength = 0.55;
// Brightness of the foam streaks.
uniform float foam = 0.9;

varying vec2 band_uv;

// Cheap 1D hash: the streak pattern across the fall.
float hash11(float x) {
	return fract(sin(x * 78.233) * 43758.5453);
}

// Smooth 1D noise across the fall, so neighbouring streaks blend instead of
// standing side by side as hard columns.
float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash11(i), hash11(i + 1.0), f);
}

void vertex() {
	band_uv = UV;
	// The mesh hangs vertically; the launch arc is added here (NORMAL = outward).
	float drop = UV.y * tile;
	VERTEX += NORMAL * arc_out * (1.0 - exp(-drop / max(arc_drop, 0.01)));
}

void fragment() {
	// 0 at the lip, 1 at the bottom of the fall.
	float fall = clamp(band_uv.y / max(height_tiles, 0.001), 0.0, 1.0);
	// Three scales of streaks, each falling at its own speed (the fine ones race).
	float u = band_uv.x;
	float wide = noise1(u * 5.0);
	float mid = noise1(u * 21.0 + 3.7);
	float fine = noise1(u * 83.0 + 9.1);
	// UV.y GROWS downward, so a pattern that falls needs `y - t`: with `y + t` the
	// streaks climbed the curtain (user report 2026-11-15: "laeuft rueckwaerts").
	float t = TIME * scroll_speed / tile;
	float v1 = fract(band_uv.y * 0.6 - t * 0.8 + wide * 1.1);
	float v2 = fract(band_uv.y * 1.7 - t * 1.3 + mid * 1.6);
	float v3 = fract(band_uv.y * 4.5 - t * 2.1 + fine * 2.2);
	float streak = 0.50 * (0.5 + 0.5 * sin(v1 * 6.2831853))
		+ 0.32 * (0.5 + 0.5 * sin(v2 * 6.2831853))
		+ 0.18 * (0.5 + 0.5 * sin(v3 * 6.2831853));
	// Where a wide and a medium streak coincide the water is whipped white.
	float white = smoothstep(0.55, 0.9, streak * (0.6 + 0.8 * wide * mid));

	// Foam at the lip, the sea's colours in the body, lighter with the depth.
	float lip = 1.0 - smoothstep(0.0, 0.05, fall);
	vec3 col = mix(deep * 1.6, crest * 1.5, streak);
	col = mix(col, vec3(1.0), clamp(white * foam + lip * 0.6, 0.0, 1.0));
	col += glow * glow_strength * smoothstep(0.0, 0.9, fall) * (0.4 + 0.6 * streak);

	ALBEDO = col;
	// Thins out between the streaks further down and dissolves into space.
	float body = mix(0.92, 0.45 + 0.5 * streak, smoothstep(0.1, 0.7, fall));
	ALPHA = body * (1.0 - smoothstep(1.0 - fade_fraction, 1.0, fall));
}
