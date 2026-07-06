class_name StarsRenderer extends MultiMeshInstance3D

## Circling-stars overlay above units that just took heavy damage
## (Unit.has_stars()) — the ONLY damage feedback, HP is never shown.
##
## One MultiMesh of billboard quads; the star texture is procedural (FRAME_COUNT
## frames with the three stars at rotated positions) and all active overlays
## share the current frame (swapped on the material — cheap and sufficient).

const MAX_STARS: int = 256
const FRAME_COUNT: int = 4
const FRAME_TIME: float = 0.12
## Height above the unit's feet, measured along the CAMERA's up axis — the
## unit sprites are camera-facing billboards, so their heads extend along
## screen-up, not world-up. Anchoring the stars along world-up made them
## appear offset from the head at pitched camera angles.
const HEIGHT: float = 1.6

const C_STAR: Color = Color(1.0, 0.92, 0.3)

var _unit_manager: UnitManager = null
var _multimesh: MultiMesh = null
var _material: StandardMaterial3D = null
var _textures: Array[ImageTexture] = []
var _frame_timer: float = 0.0
var _frame: int = 0


func setup(p_unit_manager: UnitManager) -> void:
	_unit_manager = p_unit_manager


func _ready() -> void:
	for f in range(FRAME_COUNT):
		_textures.append(_make_frame_texture(f))
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(1.1, 0.55)
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# Alpha scissor keeps the quads in the opaque pass (no sorting issues).
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_material.alpha_scissor_threshold = 0.5
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_material.albedo_texture = _textures[0]
	quad.material = _material
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.mesh = quad
	_multimesh.instance_count = MAX_STARS
	_multimesh.visible_instance_count = 0
	multimesh = _multimesh


func _process(delta: float) -> void:
	if _unit_manager == null or _multimesh == null:
		return
	_frame_timer += delta
	if _frame_timer >= FRAME_TIME:
		_frame_timer = 0.0
		_frame = (_frame + 1) % FRAME_COUNT
		_material.albedo_texture = _textures[_frame]
	var camera: Camera3D = get_viewport().get_camera_3d()
	# Along the camera's up axis the stars sit exactly above the billboard
	# sprite's head at every pitch/zoom (see HEIGHT).
	var up: Vector3 = camera.global_transform.basis.y if camera != null \
		else Vector3.UP
	var count: int = 0
	for unit in _unit_manager.units:
		if count >= MAX_STARS:
			break
		if unit.has_stars():
			_multimesh.set_instance_transform(count, Transform3D(
				Basis.IDENTITY, unit.position + up * HEIGHT))
			count += 1
	_multimesh.visible_instance_count = count


## One frame of the overlay: three small stars orbiting a flat ellipse; the
## phase rotates them so consecutive frames read as "circling".
static func _make_frame_texture(phase: int) -> ImageTexture:
	var w: int = 32
	var h: int = 16
	var img: Image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for s in range(3):
		var angle: float = TAU * (float(s) / 3.0 + float(phase) / float(FRAME_COUNT * 3))
		var cx: int = int(16.0 + cos(angle) * 12.0)
		var cy: int = int(8.0 + sin(angle) * 4.0)
		_draw_star(img, cx, cy)
	return ImageTexture.create_from_image(img)


## Small plus-shaped star with a bright core.
static func _draw_star(img: Image, cx: int, cy: int) -> void:
	img.fill_rect(Rect2i(cx - 2, cy, 5, 1), C_STAR)
	img.fill_rect(Rect2i(cx, cy - 2, 1, 5), C_STAR)
	img.fill_rect(Rect2i(cx, cy, 1, 1), Color.WHITE)
