shader_type spatial;

// Textured terrain material (used when assets/textures/terrain/{sand,grass,
// rock}.png exist — see Terrain._create_material). World-space projection:
// sand/grass are sampled top-down only (they only show on near-flat ground on
// a heightmap), rock is fully triplanar so cliffs do not smear. No UVs are
// needed, which keeps the runtime deformation path (rebuild_chunks) untouched.
//
// ANTI-TILING. At uv_scale 0.25 one tile is 4 m, and the camera sees 60-100 m
// of ground at once: 15-25 copies of the same image in one screenful. Two
// separate symptoms come out of that and they need two separate cures:
//   (a) the REPETITION itself is legible as a grid, even with a perfectly
//       seamless image — the eye locks onto any recognisable blob recurring on
//       a lattice. Cure: break the lattice (anti_tile_mode 1 and 2).
//   (b) a NON-SEAMLESS source adds a hard discontinuity on every tile border,
//       which draws that lattice for you. Cure: never show a tile border at
//       full weight (seam_blend; mode 2 helps, but only partially).
// All of it is shader-only on the same three images: no splatmap, no noise
// texture on disk, no PBR maps. The real fix for (b) is still a seamless
// source image — this only hides it.

// filter_linear_mipmap_anisotropic (was: filter_linear_mipmap). At this
// camera's grazing angles isotropic mip selection picks a far too high level
// along the view direction and the distance turns to mush. That HIDES the
// tiling by destroying the texture — anisotropy keeps the detail and lets the
// code below do the actual work. Capped by ProjectSettings
// rendering/textures/default_filters/anisotropic_filtering_level.
uniform sampler2D sand_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

// Height thresholds, set from Terrain.SAND_TOP / ROCK_BOTTOM. The defaults now
// MATCH those (TerrainData.GRASS_MIN / GRASS_MAX = 3.5 / 10.0) — the old
// 6.5 / 13.0 made every inspector preview of this material a lie.
uniform float sand_top = 3.5;
uniform float rock_bottom = 10.0;
uniform float uv_scale = 0.25;
// Steepness range over which any surface fades to rock (on NORMAL.y).
uniform float slope_rock_start = 0.55;
uniform float slope_rock_end = 0.75;
// How strongly the per-vertex height tint (incl. hand-tuned colouring)
// modulates the textures. 0 = pure texture, 1 = full vertex colour.
uniform float vertex_color_mix = 0.35;

// --- anti-tiling -----------------------------------------------------------
// Set from Terrain.TERRAIN_ANTI_TILE_MODE. A UNIFORM branch: every fragment of
// every chunk takes the same path, so there is no wave divergence — only the
// fetch count changes.
uniform int anti_tile_mode : hint_enum("Aus", "Guenstig", "Stark") = 1;

// mode 1: frequency of the macro layer as a fraction of the detail layer.
// 0.1873 is deliberately NOT 1/5 or 1/4: with an integer ratio the two
// lattices line up again every few tiles and you have merely built a bigger
// grid. At 0.1873 the beat period is longer than the disc.
uniform float macro_ratio : hint_range(0.05, 0.5) = 0.1873;
uniform float macro_strength : hint_range(0.0, 1.0) = 0.55;
// Wavelength (metres) of the dominant octave of the procedural value noise.
// ~42 m is about half a screen at the usual camera height: large enough to
// read as "this patch of meadow is lighter", small enough to recur per view.
uniform float macro_noise_wavelength : hint_range(8.0, 120.0) = 42.0;
uniform float macro_noise_strength : hint_range(0.0, 1.0) = 0.35;

// mode 2: 1.0 = the reference scale, ~3.46 hex cells per tile edge (~1.15 m
// cells at uv_scale 0.25). Lower = coarser cells.
uniform float hex_scale : hint_range(0.25, 4.0) = 1.0;
// Variance restoration of the 3-tap blend, see sample_stochastic(). 0 = plain
// linear blend (visibly washed out), 1 = full restoration.
uniform float hex_contrast : hint_range(0.0, 1.0) = 1.0;

// Seam cross-fade, INDEPENDENT of anti_tile_mode — it treats symptom (b) and
// combines with either mode. Width of the fade band as a fraction of the half
// tile; 0 disables it and costs nothing, above 0 it doubles the tap count.
uniform float seam_blend : hint_range(0.0, 0.45) = 0.12;

// Any LOD above the real mip count clamps to the last (1x1) level, i.e. the
// average colour of the whole image — a free "mean" without an extra asset.
const float LOD_MEAN = 16.0;
// Layer weights below this contribute less than a quantisation step; skipping
// them saves the whole sample. Algebraically identical to the old nested mix.
const float WEIGHT_EPS = 0.002;

varying vec3 wpos;
varying vec3 wnormal;
varying vec3 vcol;

// --- helpers ---------------------------------------------------------------

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// Hoskins-style hashes: NO sin(). The classic fract(sin(x) * 43758.5) hash
// gives different results on different drivers because sin() of a huge
// argument is implementation-defined.
float hash12(vec2 p) {
	vec3 p3 = fract(p.xyx * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(p.xyx * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Smoothed value noise in [0, 1]. Two of these make the macro mask.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// ONE texture fetch, plus the optional half-tile cross-fade.
//
// Every sample goes through here and every one uses textureGrad with
// explicitly passed gradients. Two reasons, both hard:
//   * mode 2 offsets the UV per hex cell, so implicit derivatives jump at
//     every cell border. The hardware would read that as "minified by a whole
//     texture" and snap to the 1x1 mip: a bright net over the terrain. The
//     gradients of the BASE uv are the correct footprint — a random offset is
//     a translation, and translations do not change derivatives.
//   * the layer/plane weight tests in fragment() are NON-uniform branches
//     around texture reads, where implicit derivatives are undefined by spec.
// Explicit gradients still drive anisotropic filtering on Vulkan.
//
// The cross-fade: tile B is the same image shifted by half a tile, so B's
// borders sit exactly on A's centres and vice versa. The mask is 0 at A's
// centre and reaches 1 exactly ON A's border, so the border is never shown —
// the discontinuity is genuinely gone, not just attenuated (a mask that only
// reached 0.5 would leave half the step).
vec3 tap(sampler2D tex, vec2 uv, vec2 ddx, vec2 ddy) {
	vec3 a = textureGrad(tex, uv, ddx, ddy).rgb;
	if (seam_blend <= 0.0) {
		return a;
	}
	vec2 e = abs(fract(uv) - 0.5) * 2.0;   // 0 at the tile centre, 1 at its border
	float m = smoothstep(1.0 - seam_blend * 2.0, 1.0, max(e.x, e.y));
	vec3 b = textureGrad(tex, uv + vec2(0.5), ddx, ddy).rgb;
	return mix(a, b, m);
}

// --- mode 1: two scales + macro mask ---------------------------------------
//
// The detail layer keeps the close-up look. The macro layer is the SAME image
// at ~1/5 the frequency; only its luminance DEVIATION FROM THE TEXTURE MEAN is
// used, applied as a classic overlay on the detail luminance. Consequences:
//   * neutral where the macro layer sits at its own mean, so nothing is
//     globally darkened or brightened;
//   * it modulates brightness, not hue, so a grass image stays green;
//   * its own repetition period is ~21 m instead of 4 m, and it beats against
//     the detail lattice rather than sitting on it.
// The procedural value noise on top adds a lattice-free component that no
// amount of staring resolves into a grid.
vec3 sample_cheap(sampler2D tex, vec3 mean, vec2 uv, vec2 ddx, vec2 ddy, vec2 world_xz) {
	vec3 base = tap(tex, uv, ddx, ddy);
	vec3 macro = tap(tex, uv * macro_ratio, ddx * macro_ratio, ddy * macro_ratio);

	float bl = max(luma(base), 1e-4);
	// 0.5 = "macro layer is exactly at the image mean" = overlay identity.
	float s = clamp(luma(macro) * 0.5 / max(luma(mean), 1e-4), 0.0, 1.0);
	float ov = bl < 0.5 ? (2.0 * bl * s) : (1.0 - 2.0 * (1.0 - bl) * (1.0 - s));
	float f = mix(1.0, ov / bl, macro_strength);

	// Two octaves, ~42 m and ~16 m. The mean of vnoise is ~0.5, so 0.6 + 0.8 * n
	// averages 1.0: brightness varies by +/-40 % with no net shift.
	float n = 0.62 * vnoise(world_xz / macro_noise_wavelength)
			+ 0.38 * vnoise(world_xz / (macro_noise_wavelength * 0.37) + vec2(31.7, 11.3));
	f *= mix(1.0, 0.6 + 0.8 * n, macro_noise_strength);

	return clamp(base * f, vec3(0.0), vec3(1.0));
}

// --- mode 2: stochastic hex sampling ---------------------------------------
//
// Heitz & Neyret's triangle (hex) grid: skew the plane into a simplex lattice,
// take the enclosing triangle's three vertices and their barycentric weights.
// No texture reads and no derivatives in here, so the branch is harmless.
void tri_grid(vec2 uv, out vec3 w, out vec2 v1, out vec2 v2, out vec2 v3) {
	uv *= 3.4641016;   // 2 * sqrt(3)
	mat2 to_skewed = mat2(vec2(1.0, 0.0), vec2(-0.57735027, 1.15470054));
	vec2 s = to_skewed * uv;
	vec2 base = floor(s);
	vec3 t = vec3(fract(s), 0.0);
	t.z = 1.0 - t.x - t.y;
	if (t.z > 0.0) {
		w = vec3(t.z, t.y, t.x);
		v1 = base;
		v2 = base + vec2(0.0, 1.0);
		v3 = base + vec2(1.0, 0.0);
	} else {
		w = vec3(-t.z, 1.0 - t.y, 1.0 - t.x);
		v1 = base + vec2(1.0, 1.0);
		v2 = base + vec2(1.0, 0.0);
		v3 = base + vec2(0.0, 1.0);
	}
}

// Three taps of the same image at three INDEPENDENT random UV offsets, one per
// hex vertex, blended by the barycentric weights.
//
// Why this kills the grid (a): the offset is constant inside a hex cell and
// uncorrelated between cells, so the image's own 4 m lattice is re-anchored
// every ~1.15 m at a random phase. There is no periodic function left to lock
// onto — the result is stationary but aperiodic.
//
// Why it also softens the seams (b): a tap's tile border only shows through
// with that tap's weight w_i, which is 1 only exactly at the hex vertex and
// 1/3 on average; the other two taps are continuous across that curve and
// dilute it. One full-contrast straight line every 4 m becomes three short,
// faint, differently placed fragments per hex cell. Attenuated and scattered
// is NOT removed — for that, use seam_blend.
//
// Variance restoration: a weighted mean of independent samples keeps only
// sqrt(dot(w, w)) of the original spread, which is why a naive stochastic
// blend looks milky in the middle of every hex triangle (w = 1/3 there, factor
// 0.577) — and that milkiness makes the hex grid itself visible. Heitz/Neyret
// fix it with a histogram-preserving operator needing a precomputed LUT, i.e.
// a fourth asset. The variance-preserving affine form below gets most of the
// way for free: it needs only the image mean, and the mean is the 1x1 mip.
vec3 sample_stochastic(sampler2D tex, vec3 mean, vec2 uv, vec2 ddx, vec2 ddy) {
	vec3 w;
	vec2 v1;
	vec2 v2;
	vec2 v3;
	tri_grid(uv * hex_scale, w, v1, v2, v3);

	vec3 c1 = tap(tex, uv + hash22(v1), ddx, ddy);
	vec3 c2 = tap(tex, uv + hash22(v2), ddx, ddy);
	vec3 c3 = tap(tex, uv + hash22(v3), ddx, ddy);

	vec3 col = w.x * c1 + w.y * c2 + w.z * c3;
	float norm = inversesqrt(max(dot(w, w), 1e-4));
	col = mean + (col - mean) * mix(1.0, norm, hex_contrast);
	return clamp(col, vec3(0.0), vec3(1.0));
}

// --- dispatcher ------------------------------------------------------------
// The mean is fetched HERE, not once up front, so a layer that is not blended
// at this pixel costs nothing at all. It is a 1x1 mip read from a constant
// address: permanently resident, effectively free.
vec3 ground(sampler2D tex, vec2 uv, vec2 ddx, vec2 ddy, vec2 world_xz) {
	if (anti_tile_mode <= 0) {
		return tap(tex, uv, ddx, ddy);
	}
	vec3 mean = textureLod(tex, vec2(0.5), LOD_MEAN).rgb;
	if (anti_tile_mode == 1) {
		return sample_cheap(tex, mean, uv, ddx, ddy, world_xz);
	}
	return sample_stochastic(tex, mean, uv, ddx, ddy);
}

// ---------------------------------------------------------------------------

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR.rgb;
}

void fragment() {
	vec2 top_uv = wpos.xz * uv_scale;
	// Gradients of the BASE uv, taken once in uniform control flow — every tap
	// below reuses them (see tap()). The two side planes get theirs here too,
	// so no derivative is ever taken inside a non-uniform branch.
	vec2 top_dx = dFdx(top_uv);
	vec2 top_dy = dFdy(top_uv);
	vec2 uv_x = wpos.zy * uv_scale;
	vec2 x_dx = dFdx(uv_x);
	vec2 x_dy = dFdy(uv_x);
	vec2 uv_z = wpos.xy * uv_scale;
	vec2 z_dx = dFdx(uv_z);
	vec2 z_dy = dFdy(uv_z);

	// Height blend, mirroring Terrain._color_for_height: sand below sand_top,
	// sand->grass over the first half of the band, grass->rock above
	// rock_bottom (over ~6 m).
	float sand_grass = clamp((wpos.y - sand_top) / max(rock_bottom - sand_top, 0.001) * 2.0, 0.0, 1.0);
	float grass_rock = clamp((wpos.y - rock_bottom) / 6.0, 0.0, 1.0);
	// Steep faces are rock at any height.
	grass_rock = max(grass_rock, 1.0 - smoothstep(slope_rock_start, slope_rock_end, wnormal.y));

	// mix(mix(sand, grass, a), rock, b) expanded into explicit weights. Same
	// value to the last bit, but now a layer with zero weight can be SKIPPED —
	// and a skipped layer is 1 to 3 taps not taken. On a Populous map most
	// pixels are a single layer, which is what pays for mode 1 / mode 2.
	float w_rock = grass_rock;
	float w_grass = (1.0 - grass_rock) * sand_grass;
	float w_sand = (1.0 - grass_rock) * (1.0 - sand_grass);

	vec3 col = vec3(0.0);
	if (w_sand > WEIGHT_EPS) {
		col += ground(sand_tex, top_uv, top_dx, top_dy, wpos.xz) * w_sand;
	}
	if (w_grass > WEIGHT_EPS) {
		col += ground(grass_tex, top_uv, top_dx, top_dy, wpos.xz) * w_grass;
	}
	if (w_rock > WEIGHT_EPS) {
		// Triplanar blend for rock only. The two side planes are skipped where
		// their weight vanishes — everywhere except actual cliffs. Without that,
		// mode 2 would cost 9 taps on every flat rock plateau.
		vec3 tw = pow(abs(wnormal), vec3(4.0));
		tw /= (tw.x + tw.y + tw.z);
		vec3 rock = vec3(0.0);
		if (tw.y > WEIGHT_EPS) {
			rock += ground(rock_tex, top_uv, top_dx, top_dy, wpos.xz) * tw.y;
		}
		if (tw.x > WEIGHT_EPS) {
			rock += ground(rock_tex, uv_x, x_dx, x_dy, wpos.zy) * tw.x;
		}
		if (tw.z > WEIGHT_EPS) {
			rock += ground(rock_tex, uv_z, z_dx, z_dy, wpos.xy) * tw.z;
		}
		col += rock * w_rock;
	}

	ALBEDO = col * mix(vec3(1.0), vcol, vertex_color_mix);
	ROUGHNESS = 1.0;
}
