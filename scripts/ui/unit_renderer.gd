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
## Kinds baked into the atlas (later phases append warrior/firewarrior/...).
const KINDS: Array[StringName] = [&"brave"]
## Sprite Y offset while airborne selects the arms-up jump frame.
const HOP_FRAME_THRESHOLD: float = 0.12

const SHADER_CODE: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D atlas : source_color, filter_nearest;
uniform vec2 frame_uv;

varying vec4 tint;
varying vec2 uv_offset;

void vertex() {
	tint = COLOR;
	uv_offset = INSTANCE_CUSTOM.xy;
	// Billboard: camera basis, instance origin.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 tex = texture(atlas, uv_offset + UV * frame_uv);
	if (tex.a < 0.5) {
		discard;
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
		_multimesh.set_instance_color(index,
			Unit.TRIBE_COLORS[moved.tribe_id % Unit.TRIBE_COLORS.size()])
	_multimesh.visible_instance_count = _units.size()


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
