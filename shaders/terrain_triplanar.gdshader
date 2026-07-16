shader_type spatial;

// Textured terrain material (used when assets/textures/terrain/{sand,grass,
// rock}.png exist — see Terrain._create_material). World-space projection:
// sand/grass are sampled top-down only (they only show on near-flat ground on
// a heightmap), rock is fully triplanar so cliffs do not smear. No UVs are
// needed, which keeps the runtime deformation path (rebuild_chunks) untouched.

uniform sampler2D sand_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
// Height thresholds, set from Terrain.SAND_TOP / ROCK_BOTTOM.
uniform float sand_top = 6.5;
uniform float rock_bottom = 13.0;
uniform float uv_scale = 0.25;
// Steepness range over which any surface fades to rock (on NORMAL.y).
uniform float slope_rock_start = 0.55;
uniform float slope_rock_end = 0.75;
// How strongly the per-vertex height tint (incl. hand-tuned colouring)
// modulates the textures. 0 = pure texture, 1 = full vertex colour.
uniform float vertex_color_mix = 0.35;

varying vec3 wpos;
varying vec3 wnormal;
varying vec3 vcol;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR.rgb;
}

void fragment() {
	vec2 top_uv = wpos.xz * uv_scale;
	vec3 sand = texture(sand_tex, top_uv).rgb;
	vec3 grass = texture(grass_tex, top_uv).rgb;

	// Triplanar blend for rock only (5 fetches total instead of 9).
	vec3 tw = pow(abs(wnormal), vec3(4.0));
	tw /= (tw.x + tw.y + tw.z);
	vec3 rock = texture(rock_tex, wpos.zy * uv_scale).rgb * tw.x
			+ texture(rock_tex, top_uv).rgb * tw.y
			+ texture(rock_tex, wpos.xy * uv_scale).rgb * tw.z;

	// Height blend, mirroring Terrain._color_for_height: sand below sand_top,
	// sand->grass over the first half of the band, grass->rock above
	// rock_bottom (over ~6 m).
	float sand_grass = clamp((wpos.y - sand_top) / max(rock_bottom - sand_top, 0.001) * 2.0, 0.0, 1.0);
	float grass_rock = clamp((wpos.y - rock_bottom) / 6.0, 0.0, 1.0);
	// Steep faces are rock at any height.
	grass_rock = max(grass_rock, 1.0 - smoothstep(slope_rock_start, slope_rock_end, wnormal.y));

	vec3 col = mix(mix(sand, grass, sand_grass), rock, grass_rock);
	ALBEDO = col * mix(vec3(1.0), vcol, vertex_color_mix);
	ROUGHNESS = 1.0;
}
