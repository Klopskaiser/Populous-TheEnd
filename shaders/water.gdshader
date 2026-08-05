shader_type spatial;
render_mode cull_disabled;

// Opaque Populous-style sea (see Terrain._ensure_water). Nothing below the
// surface is ever meant to be visible; that is what makes a drowned unit vanish
// for free.
//
// The surface rolls with a small three-wave sum: the vertices are displaced
// vertically (needs the plane subdivision set in Terrain._ensure_water), the
// normal is rebuilt from the same function so the light actually travels over
// the swell, and the crest tint reuses the height that was already computed.
// The amplitude is deliberately tiny (a few centimetres) so the visible
// waterline still matches the gameplay threshold SEA_LEVEL + Unit.WATER_EPS.

uniform vec3 deep : source_color = vec3(0.055, 0.16, 0.40);
uniform vec3 crest : source_color = vec3(0.13, 0.30, 0.58);
// Wave height in metres (peak of the summed waves).
uniform float wave_height = 0.07;
// Radians per metre — 0.35 gives a ~18 m swell, far longer than one subdivision
// cell, so the surface never looks faceted.
uniform float wave_scale = 0.35;
uniform float wave_speed = 0.9;
// Phase 10j: the sea is cut to the DISC. The plane stays a square PlaneMesh so its
// subdivision (and with it the wave displacement) is untouched — the fragments
// outside the disc are simply discarded. That is also why there is only ONE material
// path now: a StandardMaterial3D cannot discard, so the optional water texture is
// fed in here instead of replacing the whole material.
//
// The cut uses the CELL MASK, not a circle. Terrain._build_chunk_mesh culls whole
// cells, so the land's edge is a staircase; a circular cut let the sea overhang the
// rock wall by up to half a metre, which showed up as a strip of water below the land
// at the rim (user report: "sieht am Rand wie eine Torte aus") and hid the waterfall
// behind that overhang. Sampling the same mask the walkability uses makes sea edge and
// mesh edge the same line by construction.
uniform sampler2D disc_mask : filter_nearest, repeat_disable, hint_default_white;
uniform float map_size = 128.0;
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform bool use_tex = false;
uniform float uv_scale = 1.0;
// Finite-difference step for the normal, in metres.
const float NORMAL_EPS = 0.75;

varying float wave;
varying vec2 world_xz;

// Normalised swell in roughly [-1, 1].
float wave_at(vec2 p, float t) {
	return 0.4 * sin(p.x * wave_scale + t * wave_speed)
		+ 0.4 * sin(p.y * wave_scale * 0.8 - t * wave_speed * 0.7)
		+ 0.2 * sin((p.x + p.y) * wave_scale * 1.7 + t * wave_speed * 1.3);
}

void vertex() {
	vec2 wxz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	world_xz = wxz;
	wave = wave_at(wxz, TIME);
	VERTEX.y += wave * wave_height;
	// Rebuild the normal from the same function (central differences). The plane
	// is axis-aligned and unrotated, so model space and world space agree here.
	float hx = wave_at(wxz + vec2(NORMAL_EPS, 0.0), TIME)
		- wave_at(wxz - vec2(NORMAL_EPS, 0.0), TIME);
	float hz = wave_at(wxz + vec2(0.0, NORMAL_EPS), TIME)
		- wave_at(wxz - vec2(0.0, NORMAL_EPS), TIME);
	NORMAL = normalize(vec3(
		-hx * wave_height, 2.0 * NORMAL_EPS, -hz * wave_height));
}

void fragment() {
	// Outside the disc there is no world, so there is no sea either.
	if (texture(disc_mask, world_xz / map_size).r < 0.5) {
		discard;
	}
	// No trig in the fragment stage at all — the crest tint rides the varying.
	vec3 col = mix(deep, crest, clamp(wave * 0.5 + 0.5, 0.0, 1.0));
	if (use_tex) {
		// Same look as the old StandardMaterial3D path: tinted texture, still opaque.
		col = texture(albedo_tex, world_xz * uv_scale * 0.02).rgb * col * 1.6;
	}
	ALBEDO = col;
	ROUGHNESS = 0.25;
	METALLIC = 0.1;
}
