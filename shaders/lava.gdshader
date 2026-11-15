shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// The surface of every lava body (LavaSurge sheet, LavaFlow ribbon): a slowly
// churning melt with dark crust plates and glowing veins instead of the flat
// vertex colour it replaced. House style like the waterfall and the twister —
// one draw call per body, no tick, no particles, no texture, no screen read.
//
// Per-vertex inputs (set by the mesh builders):
//   COLOR.rgb  the age ramp from LavaCommon.color_for (glowing front -> viscous
//              dark red -> cooled scorch); it stays the BASE colour, so the
//              gameplay reading "bright = fresh and deadly" is unchanged
//   COLOR.a    fade-out of a crust that leaves no scorch
//   UV.x       heat: 1 = just poured, 0 = cooled
//   UV.y       coverage: 1 inside the body, falling to 0 at its edge
// The pattern is anchored in WORLD space, so a sheet that is rebuilt five times
// a second (and a ribbon that grows) never drags its texture along.

// Glow of the veins and of the advancing rim.
uniform vec3 vein : source_color = vec3(1.0, 0.62, 0.14);
// Crust plates that form as the melt cools.
uniform vec3 crust : source_color = vec3(0.10, 0.035, 0.025);
// Size of the crust plates (metres per noise cell) and how fast the melt creeps.
uniform float plate_size = 1.1;
uniform float creep = 0.09;

varying vec3 world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float heat = clamp(UV.x, 0.0, 1.0);
	float cover = UV.y;
	float t = TIME * creep;
	vec2 p = world_pos.xz / plate_size;
	// The melt churns: the pattern is warped by a second, slower field.
	vec2 q = p + vec2(noise(p * 0.5 + vec2(t, -t * 0.7)),
		noise(p * 0.5 + vec2(7.3 - t * 0.8, t))) * 0.9;
	float n1 = noise(q + vec2(t * 1.1, -t * 0.6));
	float n2 = noise(q * 2.3 - vec2(t * 1.4, t * 0.5));
	// Veins: the ridge of the plate field — thin lines between the plates.
	float ridge = 1.0 - abs(2.0 * n1 - 1.0);
	float veins = smoothstep(0.70, 0.96, ridge);
	// Plates grow with the cooling: none on a fresh pour, most of the surface late.
	float plates = smoothstep(0.30, 0.72, n2 * 0.55 + n1 * 0.45) * (1.0 - heat) * 0.9;

	vec3 body = COLOR.rgb * (0.82 + 0.55 * n2);
	body = mix(body, crust, plates);
	// The veins glow as long as there is heat; a cooled scorch keeps a faint ember.
	body += vein * veins * (0.06 + 0.94 * heat) * (0.75 + 0.25 * sin(TIME * 2.1 + n1 * 9.0));
	// A slow pulse through the molten part.
	body *= 1.0 + 0.10 * heat * sin(TIME * 1.6 + n2 * 6.0);

	// Ragged edge, and a bright rim where hot lava meets the ground.
	float ragged = cover + (n2 - 0.5) * 0.45 + (n1 - 0.5) * 0.25;
	float rim = (1.0 - smoothstep(0.12, 0.5, ragged)) * heat;
	body = mix(body, vein * 1.15, rim * 0.75);

	ALBEDO = body;
	ALPHA = smoothstep(0.0, 0.16, ragged) * COLOR.a;
}
