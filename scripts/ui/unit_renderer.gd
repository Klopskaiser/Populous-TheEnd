class_name UnitRenderer extends MultiMeshInstance3D

## Renders ALL units through one MultiMesh (one draw call) instead of one
## AnimatedSprite3D node per unit — 4000 sprites were 4000 draw calls plus
## 4000 per-frame node updates. Billboarding happens in the vertex shader;
## the animation frame is selected via per-instance custom data (atlas UV
## offset) and the tribe colour via the per-instance colour.
##
## Per frame: the camera is fetched ONCE; frame/view updates run in
## VISUAL_SLICES staggered slices; transforms are only rewritten for units
## whose position actually changed (standing units cost one comparison).

const MAX_UNITS: int = 4096
const VISUAL_SLICES: int = 3
const PIXEL_SIZE: float = 0.06
## Kinds baked into the atlas (shaman is added in phase 6).
const KINDS: Array[StringName] = [&"brave", &"warrior", &"firewarrior", &"preacher"]
## Sprite Y offset while airborne selects the arms-up jump frame.
const HOP_FRAME_THRESHOLD: float = 0.12
## Small extra depth nudge toward the camera (metres) so a sprite standing on
## a step/next to a foundation lip is not z-fought / buried by the ground.
const DEPTH_BIAS: float = 0.35
## Multiplier on each row's true world elevation when computing depth. 1.0 =
## physically correct (head sits at its real depth): a unit in front of a
## building is fully visible, a unit behind it is occluded, with no overshoot.
## Values >1 pull heads further toward the camera but make them poke through
## roofs/walls when the unit is actually behind — so keep this at 1.0.
const ELEVATION_GAIN: float = 1.0

const SHADER_CODE: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D atlas : source_color, filter_nearest;
uniform vec2 frame_uv;
uniform float depth_bias;
uniform float elevation_gain;

varying vec4 tint;
varying vec2 uv_offset;

void vertex() {
	tint = COLOR;
	uv_offset = INSTANCE_CUSTOM.xy;
	// Camera-facing (spherical) billboard: the quad axes follow the camera so
	// the sprite never foreshortens. This is used for the on-screen SHAPE.
	mat4 mv = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	vec4 vp = mv * vec4(VERTEX, 1.0);
	vec4 clip = PROJECTION_MATRIX * vp;

	// A spherical billboard puts the whole quad at ONE depth (the unit's ground
	// point), so the head is drawn too far back and nearby elevated geometry
	// (building roofs, flattened-terrain lips) wrongly occludes it. Instead
	// derive the DEPTH as if the sprite stood vertically in the world: raise
	// each row by its true world height (VERTEX.y along world up) plus a small
	// bias toward the camera. Only the depth changes; x/y keep the spherical
	// projection, so there is no shear or screen shift.
	vec3 up_view = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	vec4 vp_depth = vp;
	vp_depth.z += up_view.z * VERTEX.y * elevation_gain + depth_bias;
	vec4 clip_depth = PROJECTION_MATRIX * vp_depth;

	POSITION = clip;
	POSITION.z = clip_depth.z / clip_depth.w * clip.w;
}

void fragment() {
	vec4 tex = texture(atlas, uv_offset + UV * frame_uv);
	if (tex.a < 0.5) {
		discard;
	}
	// Corpse fade: screen-door (ordered dither) on the instance alpha keeps the
	// opaque pipeline — real alpha blending would drag every unit sprite into
	// the transparent pass and its sorting problems.
	if (tint.a < 1.0) {
		float threshold = fract(52.9829189 *
			fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (tint.a < threshold) {
			discard;
		}
	}
	ALBEDO = tex.rgb * tint.rgb;
}
"""

var _units: Array[Unit] = []
var _multimesh: MultiMesh = null
var _uvs: PackedVector2Array = PackedVector2Array()
var _table: Dictionary = {}
var _visual_phase: int = 0


func _ready() -> void:
	var atlas: Dictionary = PlaceholderSprites.build_atlas(KINDS)
	_uvs = atlas.uvs
	_table = atlas.table

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(
		float(PlaceholderSprites.W) * PIXEL_SIZE,
		float(PlaceholderSprites.H) * PIXEL_SIZE)
	# Feet at the instance origin.
	quad.center_offset = Vector3(0.0, float(PlaceholderSprites.H) * PIXEL_SIZE * 0.5, 0.0)
	var shader: Shader = Shader.new()
	shader.code = SHADER_CODE
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("atlas", atlas.texture)
	material.set_shader_parameter("frame_uv", atlas.frame_uv)
	material.set_shader_parameter("depth_bias", DEPTH_BIAS)
	material.set_shader_parameter("elevation_gain", ELEVATION_GAIN)
	quad.material = material

	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true
	_multimesh.mesh = quad
	_multimesh.instance_count = MAX_UNITS
	_multimesh.visible_instance_count = 0
	multimesh = _multimesh


# --- Registration ------------------------------------------------------------------

func register_unit(unit: Unit) -> void:
	if unit._render_index >= 0:
		return
	if _units.size() >= MAX_UNITS:
		push_warning("UnitRenderer: capacity of %d units reached" % MAX_UNITS)
		return
	unit._render_index = _units.size()
	unit._render_kind = unit.unit_kind()
	unit._render_pos = Vector3.INF
	unit._render_frame = -1
	unit._render_alpha = 1.0
	_units.append(unit)
	_multimesh.set_instance_color(unit._render_index,
		Unit.TRIBE_COLORS[unit.tribe_id % Unit.TRIBE_COLORS.size()])
	_multimesh.visible_instance_count = _units.size()


## Swap-remove: the last slot's unit moves into the freed slot; its data is
## rewritten (colour now, transform/frame invalidated for the next pass).
func unregister_unit(unit: Unit) -> void:
	var index: int = unit._render_index
	if index < 0 or index >= _units.size():
		return
	var last: int = _units.size() - 1
	var moved: Unit = _units[last]
	_units[index] = moved
	_units.remove_at(last)
	unit._render_index = -1
	if moved != unit:
		moved._render_index = index
		moved._render_pos = Vector3.INF
		moved._render_frame = -1
		# Colour is rewritten at full alpha; resetting the cache makes the next
		# frame pass re-apply a fading corpse's actual alpha.
		moved._render_alpha = 1.0
		_multimesh.set_instance_color(index,
			Unit.TRIBE_COLORS[moved.tribe_id % Unit.TRIBE_COLORS.size()])
	_multimesh.visible_instance_count = _units.size()


## Re-applies the tribe colour of a unit's instance (after a preacher
## conversion switched its tribe).
func update_unit_color(unit: Unit) -> void:
	if unit._render_index < 0:
		return
	unit._render_alpha = 1.0
	_multimesh.set_instance_color(unit._render_index,
		Unit.TRIBE_COLORS[unit.tribe_id % Unit.TRIBE_COLORS.size()])


# --- Per-frame update -------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _units.is_empty():
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var basis: Basis = camera.global_transform.basis
	var cam_forward: Vector3 = -basis.z
	var cam_right: Vector3 = basis.x
	var hop_offset: float = absf(sin(float(Time.get_ticks_msec()) * 0.012)) * 0.35
	var now_ms: int = Time.get_ticks_msec()

	# Animation frames/views, staggered over VISUAL_SLICES frames.
	for i in range(_visual_phase, _units.size(), VISUAL_SLICES):
		_update_frame(_units[i], cam_forward, cam_right, hop_offset, now_ms)
	_visual_phase = (_visual_phase + 1) % VISUAL_SLICES

	# Transforms every frame, but only for units that actually moved.
	for i in range(_units.size()):
		var unit: Unit = _units[i]
		var pos: Vector3 = unit.position
		if unit.hop_visual:
			pos.y += hop_offset
		if pos != unit._render_pos:
			unit._render_pos = pos
			_multimesh.set_instance_transform(unit._render_index,
				Transform3D(Basis.IDENTITY, pos))


func _update_frame(unit: Unit, cam_forward: Vector3, cam_right: Vector3,
		hop_offset: float, now_ms: int) -> void:
	# Corpse fade: push the decaying alpha into the instance colour (before the
	# frame-equality early-out below — the corpse frame itself never changes).
	if unit.state == Unit.State.DEAD:
		var alpha: float = unit.corpse_alpha()
		if absf(alpha - unit._render_alpha) > 0.01:
			unit._render_alpha = alpha
			var col: Color = Unit.TRIBE_COLORS[unit.tribe_id % Unit.TRIBE_COLORS.size()]
			col.a = alpha
			_multimesh.set_instance_color(unit._render_index, col)
	var view: int = Unit.view_index(unit.facing, cam_forward, cam_right)
	var per_base: Dictionary = _table.get(unit._render_kind, _table[KINDS[0]])
	var base: StringName = unit.anim_base_name
	var views: Array = per_base.get(base, per_base[&"idle"])
	var info: Array = views[view]   # [start, count, fps]
	var frame: int
	if unit.hop_visual and base == &"jump":
		# Frame-driven by the hop phase: arms up in the air, down on landing.
		frame = 1 if hop_offset > HOP_FRAME_THRESHOLD else 0
	else:
		frame = int(float(now_ms - unit.anim_start_ms) * 0.001 * float(info[2])) % int(info[1])
	var global_frame: int = int(info[0]) + frame
	if global_frame == unit._render_frame:
		return
	unit._render_frame = global_frame
	var uv: Vector2 = _uvs[global_frame]
	_multimesh.set_instance_custom_data(unit._render_index, Color(uv.x, uv.y, 0.0, 0.0))
