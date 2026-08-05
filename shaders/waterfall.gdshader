shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque;

// Phase 10j: the water that reaches the disc's rim pours off into space. A single
// static vertical band around the submerged part of the rim (see TerrainRim), with
// the UV scrolled downward — one draw call, no tick, no particles. The project has
// no GPUParticles3D anywhere; the house style is MultiMesh plus animated meshes.
//
// The colours are the SAME uniforms as the sea (water.gdshader) so the lip cannot
// drift out of tune with the surface it flows out of.

uniform vec3 deep : source_color = vec3(0.055, 0.16, 0.40);
uniform vec3 crest : source_color = vec3(0.13, 0.30, 0.58);
// Metres of UV travel per second.
uniform float scroll_speed = 1.6;
// Vertical tiling length in metres — how tall one repeat of the streak pattern is.
uniform float tile = 8.0;
// Over how much of the band the alpha fades out toward the bottom (0..1 of height).
uniform float fade_fraction = 0.45;

varying vec2 band_uv;

// Cheap 1D hash: the streak pattern across the fall.
float hash11(float x) {
	return fract(sin(x * 78.233) * 43758.5453);
}

void vertex() {
	band_uv = UV;
}

void fragment() {
	// UV.y runs 0 at the lip to 1 at the bottom; scrolling it downward makes the
	// water appear to pour. The fract keeps the pattern tiling seamlessly.
	float v = fract(band_uv.y + TIME * scroll_speed / tile);

	// Vertical streaks: a coarse and a fine band of columns, offset per column so
	// neighbouring streaks do not pulse in lockstep.
	float col = floor(band_uv.x * 220.0);
	float phase = hash11(col);
	float streak = 0.55 + 0.45 * sin((v + phase) * 6.2831853 * 3.0);
	float fine = 0.75 + 0.25 * sin((v + phase * 2.7) * 6.2831853 * 9.0);

	// Foam at the lip, deeper colour further down.
	float lip = 1.0 - smoothstep(0.0, 0.18, band_uv.y);
	vec3 col_rgb = mix(deep, crest, clamp(streak * fine, 0.0, 1.0));
	col_rgb = mix(col_rgb, vec3(1.0), lip * 0.35);

	ALBEDO = col_rgb;
	ROUGHNESS = 0.2;
	METALLIC = 0.1;
	// Fades into nothing on the way down: the fall does not end anywhere, it just
	// dissolves into space.
	ALPHA = 1.0 - smoothstep(1.0 - fade_fraction, 1.0, band_uv.y);
}
