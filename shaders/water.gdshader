shader_type spatial;
render_mode cull_disabled;

// Opaque Populous-style sea (see Terrain._ensure_water). Deliberately tiny:
// two sin() per fragment, no texture fetch, no vertex displacement and no
// transparency — the plane covers the whole map, so anything more expensive
// here shows up directly in the frame time. Nothing below the surface is ever
// meant to be visible; that is what makes a drowned unit vanish for free.

uniform vec3 deep : source_color = vec3(0.055, 0.16, 0.40);
uniform vec3 crest : source_color = vec3(0.13, 0.30, 0.58);
uniform float wave_speed = 0.35;
uniform float wave_scale = 0.08;

varying vec3 wpos;

void vertex() {
	// World position only — the surface itself stays perfectly flat so it keeps
	// matching TerrainData.SEA_LEVEL for every gameplay check.
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float w = sin(wpos.x * wave_scale + TIME * wave_speed)
			* sin(wpos.z * wave_scale * 1.3 - TIME * wave_speed * 0.8);
	ALBEDO = mix(deep, crest, w * 0.5 + 0.5);
	ROUGHNESS = 0.25;
	METALLIC = 0.1;
}
