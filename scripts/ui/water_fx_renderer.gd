class_name WaterFxRenderer extends MultiMeshInstance3D

## Splash rings on the sea surface above anything that is currently going under:
## drowned units, sinking vehicle wrecks and buildings that slid into the water.
## Without them a body simply disappears through a flat blue plane — the ring
## tells the player WHERE something drowned until it is fully submerged.
##
## One MultiMesh of flat, upward-facing quads lying on the water plane = one
## draw call for every splash in the match, following the StatusFxRenderer /
## StarsRenderer pattern. The quads are alpha-scissored, so they stay in the
## opaque pass and need no sorting.
##
## Sources decide for themselves whether they splash (Unit.water_splash_active /
## Building.water_splash_active), which keeps the rule headless-testable and out
## of the renderer.
##
## The frames are procedural (an expanding foam ring plus droplets) and can be
## replaced with assets/textures/effects/splash.png — a single image or a
## horizontal strip of square frames.

## Splashes drawn at once; beyond this the oldest sources are simply skipped.
const MAX_SPLASH: int = 128
const FRAME_TIME: float = 0.12
## Above the water plane, so the ring stays clear of the wave crests.
const SURFACE_LIFT: float = 0.12
## Procedural frame resolution and foam colour.
const TEX: int = 32
const C_FOAM: Color = Color(0.86, 0.94, 1.0, 1.0)

var _unit_manager: UnitManager = null
var _building_manager: BuildingManager = null
var _material: StandardMaterial3D = null
var _textures: Array[Texture2D] = []
var _frame_timer: float = 0.0
var _frame: int = 0


func setup(p_unit_manager: UnitManager, p_building_manager: BuildingManager = null) -> void:
	_unit_manager = p_unit_manager
	_building_manager = p_building_manager


func _ready() -> void:
	_textures = _load_textures()
	# PlaneMesh defaults to FACE_Y: a horizontal quad lying on the water.
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_material.alpha_scissor_threshold = 0.5
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_texture = _textures[0]
	plane.material = _material
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = plane
	mm.instance_count = MAX_SPLASH
	mm.visible_instance_count = 0
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	if multimesh == null:
		return
	_frame_timer += delta
	if _frame_timer >= FRAME_TIME:
		_frame_timer = 0.0
		_frame += 1
		if _textures.size() > 1:
			_material.albedo_texture = _textures[_frame % _textures.size()]
	var y: float = TerrainData.SEA_LEVEL + SURFACE_LIFT
	var count: int = 0
	if _unit_manager != null:
		for unit in _unit_manager.units:
			if count >= MAX_SPLASH:
				break
			if not unit.water_splash_active():
				continue
			_place(count, unit.position, unit.water_splash_radius(), y)
			count += 1
	if _building_manager != null:
		for b in _building_manager.buildings:
			if count >= MAX_SPLASH:
				break
			if not is_instance_valid(b) or not b.water_splash_active():
				continue
			_place(count, b.position, b.water_splash_radius(), y)
			count += 1
	multimesh.visible_instance_count = count


## One ring, sized in metres and laid flat on the water surface. The per-source
## position offset breaks up the shared frame timing so neighbouring splashes do
## not pulse in lockstep.
func _place(index: int, at: Vector3, radius: float, y: float) -> void:
	var wobble: float = 1.0 + 0.12 * sin(float(_frame) + at.x + at.z)
	var d: float = radius * 2.0 * wobble
	multimesh.set_instance_transform(index, Transform3D(
		Basis.IDENTITY.scaled(Vector3(d, 1.0, d)), Vector3(at.x, y, at.z)))


func _load_textures() -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	var img: Image = AssetLibrary.image("textures/effects/splash.png")
	if img != null:
		var fh: int = img.get_height()
		var n: int = maxi(img.get_width() / maxi(fh, 1), 1)
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		for i in range(n):
			var frame: Image = Image.create(fh, fh, false, Image.FORMAT_RGBA8)
			frame.blit_rect(img, Rect2i(i * fh, 0, fh, fh), Vector2i.ZERO)
			frames.append(ImageTexture.create_from_image(frame))
		return frames
	for i in range(4):
		frames.append(splash_frame(i))
	return frames


## Procedural splash: a foam ring that widens and thins over four phases, with
## droplets flung outwards in the middle phases. Static so tests can build the
## frames without a scene tree.
static func splash_frame(phase: int) -> ImageTexture:
	var img: Image = Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 0.0))
	var c: float = float(TEX) * 0.5
	var t: float = float(phase) / 3.0
	var r: float = lerpf(float(TEX) * 0.17, float(TEX) * 0.45, t)
	var thick: float = lerpf(3.4, 1.3, t)
	for py in range(TEX):
		for px in range(TEX):
			var d: float = Vector2(float(px) + 0.5 - c, float(py) + 0.5 - c).length()
			if absf(d - r) <= thick:
				img.set_pixel(px, py, C_FOAM)
	if phase == 1 or phase == 2:
		var dr: float = r + thick + 2.0
		for i in range(4):
			var a: float = TAU * (float(i) / 4.0 + 0.125)
			var dx: int = int(c + cos(a) * dr)
			var dy: int = int(c + sin(a) * dr)
			if dx >= 0 and dy >= 0 and dx < TEX - 1 and dy < TEX - 1:
				img.fill_rect(Rect2i(dx, dy, 2, 2), C_FOAM)
	return ImageTexture.create_from_image(img)
