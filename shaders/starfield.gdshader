shader_type sky;

// Phase 10j: the map is a disc floating in space, so the flat light-blue
// background colour becomes a starry sky.
//
// IMPORTANT, and not a detail: the WorldEnvironment must keep
// `ambient_light_source = 3` (AMBIENT_SOURCE_COLOR). Switching the ambient over to
// this sky would light the whole map with near-black and make it unreadable. The sky
// is background only; the DirectionalLight3D "Sun" stays as the distant central star.
//
// Everything here is procedural hash noise on the view direction — no textures, in
// keeping with the project's "assets/ stays empty" rule. There is no TIME
// dependency either, so the Sky resource can bake its radiance once
// (process_mode = PROCESS_MODE_QUALITY) and cost nothing per frame.

uniform vec3 sky_top : source_color = vec3(0.008, 0.010, 0.030);
uniform vec3 sky_bottom : source_color = vec3(0.030, 0.028, 0.055);
// Nebula tint and how strongly it shows.
uniform vec3 nebula : source_color = vec3(0.10, 0.06, 0.20);
uniform float nebula_strength = 0.55;
// Fraction of cells that hold a star (per layer) and overall brightness.
uniform float star_density = 0.06;
uniform float star_brightness = 1.0;

// --- hash helpers -----------------------------------------------------------------

float hash1(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

vec3 hash3(vec3 p) {
	return vec3(
		hash1(p + vec3(0.0, 0.0, 0.0)),
		hash1(p + vec3(11.3, 4.7, 19.1)),
		hash1(p + vec3(23.7, 31.2, 5.9)));
}

// Value noise on the direction sphere, used for the nebula clouds.
float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash1(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash1(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash1(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash1(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash1(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash1(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash1(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash1(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

// One layer of stars: the direction is bucketed onto a grid, each cell may hold a
// star at a random offset inside it. Cell size sets the layer's density, `mag` its
// brightness, so three layers give a believable magnitude spread.
float star_layer(vec3 dir, float cells, float mag) {
	vec3 p = dir * cells;
	vec3 cell = floor(p);
	if (hash1(cell) > star_density) {
		return 0.0;
	}
	vec3 offset = hash3(cell + vec3(0.5)) * 0.7 + vec3(0.15);
	float d = length(fract(p) - offset);
	// Tight core with a short falloff — a star is a point, not a blob.
	float core = 1.0 - smoothstep(0.0, 0.10, d);
	return pow(core, 3.0) * mag;
}

void sky() {
	vec3 dir = normalize(EYEDIR);

	// Base gradient: darkest overhead, a touch lighter toward the horizon so the
	// disc's rim reads against something rather than pure black.
	float up = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(sky_bottom, sky_top, up);

	// Faint nebula clouds (two octaves), plus a brighter band across the sky that
	// reads as a milky way.
	float clouds = value_noise(dir * 3.0) * 0.65 + value_noise(dir * 7.0) * 0.35;
	float band = 1.0 - smoothstep(0.0, 0.55, abs(dot(dir, normalize(vec3(0.4, 0.5, -0.6)))));
	col += nebula * nebula_strength * clouds * (0.35 + 0.65 * band);

	// Three star layers: many faint, fewer medium, a handful of bright ones.
	float s = star_layer(dir, 180.0, 0.45)
		+ star_layer(dir, 90.0, 0.8)
		+ star_layer(dir, 42.0, 1.4);
	// Slight blue-white tint variation so the field is not uniformly grey.
	vec3 star_tint = mix(vec3(0.85, 0.90, 1.0), vec3(1.0, 0.95, 0.85),
		hash1(floor(dir * 90.0)));
	col += star_tint * s * star_brightness;

	COLOR = col;
}
