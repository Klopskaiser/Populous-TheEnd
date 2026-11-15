extends SceneTree

## UNIT SPRITES FROM A 3D MODEL — renders the sprite sheets of one unit kind from
## an animated GLB (a TOOL, not a test and not part of the suite).
##
## Needs a real renderer, so run it WITHOUT --headless (a window opens for a few
## seconds and closes itself):
##   godot --path . -s res://tests/tool_render_unit_sprites.gd -- <figur.glb> <figur_sprites.json> <kind> [key=value ...]
## Example (the shaman, made by D:\game\gymnastikschuh\figur_export.mjs):
##   godot --path . -s res://tests/tool_render_unit_sprites.gd -- D:/game/gymnastikschuh/out/einheiten/schamanin.glb D:/game/gymnastikschuh/out/einheiten/schamanin_sprites.json shaman
## Afterwards run `godot --path . --headless --import` once — the game only sees
## imported files (assets/README.md).
##
## What it writes into assets/units/<kind>/ (rules: assets/README.md, section
## "Einheiten-Spritesheets"):
##   <anim>.png        colour sheet, rows = the eight views in PlaceholderSprites
##                     .VIEWS order (or ONE row for the viewless lying poses),
##                     columns = frames, cells FRAME_W x FRAME_H (64 x 96, the cap)
##   <anim>_mask.png   L8 mask: white where the tribe colour goes (the HAIR), black
##                     elsewhere. The game MULTIPLIES colour * mix(1, tint, mask),
##                     so the hair is rendered as a light grey that keeps its
##                     strand shading — multiplied with the tribe colour it becomes
##                     hair of that colour.
##   manifest.json     frame size, plus fps for the sheets the plan gives one
## The GLB is loaded at RUNTIME (GLTFDocument) — it is never imported into the
## project. Which clip times form which sheet comes from the plan JSON.
##
## How a frame is made: the model stands at the origin, eight orthographic
## cameras (one SubViewport each) look at it from the eight view directions, so
## ONE rendered frame yields all eight rows. Rendered SCALE times larger with a
## transparent background, box-filtered down (premultiplied, so no dark fringe),
## alpha made binary (the game discards below 0.5) and given a one-pixel dark
## outline so the figure stays readable at 20-130 screen pixels.
##
## Options (key=value):
##   elevation=22   camera height above the horizon in degrees. The game looks
##                  down 55 degrees, the placeholders are flat side views; 22
##                  keeps the figure a standing person and shows a little of the
##                  top. The higher the camera, the further a foot set forward
##                  toward it drops BELOW the ground point (and out of the cell).
##                  The viewless poses are always rendered at 0.
##   px_per_m=54    scale: 54 px/m makes a 1,5-m figure about 77 of 96 px tall
##                  and leaves room for raised arms. Lower it if limbs get cut
##                  (the tool reports cut-off cells).
##   margin=7       pixels between the figure's ground point and the cell bottom
##                  (room for a foot set toward the camera, see elevation)
##   scale=8        supersampling (power of two)
##   outline=1      0 = no outline
##   preview=<dir>  also writes contact sheets there (kontakt.png, kontakt_gross.png)

const FRAME_W: int = 64
const FRAME_H: int = 96
## Camera yaw per view, in PlaceholderSprites.VIEWS order. 0 = camera in front of
## the figure. "right" = the figure faces screen-right, so the camera stands on
## the figure's own right-hand side (the model's -X; its +X is its left).
const VIEW_YAW: Array[float] = [0.0, 180.0, -90.0, 90.0, -45.0, 45.0, -135.0, 135.0]
const OUTLINE: Color = Color(0.09, 0.07, 0.11)
## Tribe colour used for the contact sheets only.
const PREVIEW_TINTS: Array[Color] = [Color(0.25, 0.45, 0.95), Color(0.9, 0.25, 0.2)]

const HAIR_SHADER: String = """
shader_type spatial;
render_mode unshaded, cull_disabled;
// Hair for the COLOUR sheet: its own texture reduced to brightness and lifted to
// a light grey — the game multiplies the tribe colour onto it through the mask.
uniform sampler2D tex : filter_linear_mipmap;
uniform float gain = 4.2;
uniform float lift = 0.22;
uniform bool use_alpha = false;
void fragment() {
	vec4 t = texture(tex, UV);
	float l = dot(t.rgb, vec3(0.299, 0.587, 0.114));
	float v = clamp(l * gain + lift, 0.0, 1.0);
	ALBEDO = vec3(pow(v, 2.2));
	if (use_alpha) {
		ALPHA = t.a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	}
}
"""

const MASK_SHADER: String = """
shader_type spatial;
render_mode unshaded, cull_disabled;
// Mask pass: every surface a flat value (1 = takes the tribe colour), cut out by
// its own texture's alpha so lashes and strands keep their shape.
uniform sampler2D tex : filter_linear_mipmap;
uniform float value = 0.0;
uniform bool use_alpha = false;
void fragment() {
	ALBEDO = vec3(value);
	if (use_alpha) {
		ALPHA = texture(tex, UV).a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	}
}
"""

var _glb: String = ""
var _plan_path: String = ""
var _kind: String = ""
var _opt: Dictionary = {"elevation": 22.0, "px_per_m": 54.0, "margin": 7.0, "scale": 8.0,
	"outline": 1.0, "preview": ""}

var _anim: AnimationPlayer = null
var _viewports: Array[SubViewport] = []
var _cameras: Array[Camera3D] = []
## One entry per mesh surface: {mesh, surface, colour, mask}.
var _surfaces: Array[Dictionary] = []
var _hair_surfaces: int = 0
var _report: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("Usage: -s res://tests/tool_render_unit_sprites.gd -- <figur.glb> <figur_sprites.json> <kind> [key=value ...]")
		quit(1)
		return
	_glb = args[0]
	_plan_path = args[1]
	_kind = args[2]
	for i in range(3, args.size()):
		var kv: PackedStringArray = args[i].split("=", true, 1)
		if kv.size() == 2 and _opt.has(kv[0]):
			_opt[kv[0]] = kv[1] if kv[0] == "preview" else float(kv[1])
	_run()


func _run() -> void:
	await process_frame
	var plan: Variant = JSON.parse_string(FileAccess.get_file_as_string(_plan_path))
	if not (plan is Dictionary) or not (plan as Dictionary).has("sprites"):
		push_error("Sprite plan unreadable: %s" % _plan_path)
		quit(1)
		return
	if not _load_model(String((plan as Dictionary).get("haar", "HAIR"))):
		quit(1)
		return
	_build_viewports()
	var out_dir: String = ProjectSettings.globalize_path("res://assets/units/%s" % _kind)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var manifest: Dictionary = {"frame_width": FRAME_W, "frame_height": FRAME_H, "anims": {}}
	var sheets: Array[Dictionary] = []
	for entry in (plan as Dictionary)["sprites"]:
		var sheet: Dictionary = await _render_sheet(entry)
		if sheet.is_empty():
			continue
		(sheet.colour as Image).save_png(out_dir.path_join("%s.png" % sheet.name))
		(sheet.mask as Image).save_png(out_dir.path_join("%s_mask.png" % sheet.name))
		if (entry as Dictionary).has("fps"):
			manifest["anims"][sheet.name] = {"fps": float(entry["fps"])}
		sheets.append(sheet)
	var file: FileAccess = FileAccess.open(out_dir.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  ") + "\n")
	file.close()
	if String(_opt["preview"]) != "":
		_write_previews(sheets, String(_opt["preview"]))
	print("Sprites: %d sheets -> %s" % [sheets.size(), out_dir])
	print("  Haarflaechen (Maske weiss): %d von %d Flaechen" % [_hair_surfaces, _surfaces.size()])
	for line in _report:
		print("  ", line)
	quit()


# --- Model ---------------------------------------------------------------------------

## Loads the GLB at runtime and prepares the two material sets (colour, mask).
func _load_model(hair_pattern: String) -> bool:
	var doc: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	var err: Error = doc.append_from_file(_glb, state)
	if err != OK:
		push_error("GLB unreadable (%d): %s" % [err, _glb])
		return false
	var scene: Node = doc.generate_scene(state)
	if scene == null:
		push_error("GLB has no scene: %s" % _glb)
		return false
	root.add_child(scene)
	_anim = scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim == null:
		push_error("GLB has no animations: %s" % _glb)
		return false
	var hair_shader: Shader = Shader.new()
	hair_shader.code = HAIR_SHADER
	var mask_shader: Shader = Shader.new()
	mask_shader.code = MASK_SHADER
	var pattern: String = hair_pattern.to_lower()
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Skinned meshes move far from their rest bounds (roll, kick): never cull.
		mi.extra_cull_margin = 4.0
		for s in range(mi.mesh.get_surface_count()):
			var src: Material = mi.mesh.surface_get_material(s)
			var base: BaseMaterial3D = src as BaseMaterial3D
			var tex: Texture2D = base.albedo_texture if base != null else null
			var cut: bool = base != null and tex != null \
				and base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
			var is_hair: bool = src != null and src.resource_name.to_lower().contains(pattern)
			var colour: Material = src
			if is_hair:
				_hair_surfaces += 1
				var hm: ShaderMaterial = ShaderMaterial.new()
				hm.shader = hair_shader
				hm.set_shader_parameter("tex", tex)
				hm.set_shader_parameter("use_alpha", cut)
				colour = hm
			elif base != null:
				# Flat colours: the figure is drawn, not lit (the textures carry it).
				var flat: BaseMaterial3D = base.duplicate() as BaseMaterial3D
				flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				colour = flat
			var mm: ShaderMaterial = ShaderMaterial.new()
			mm.shader = mask_shader
			mm.set_shader_parameter("tex", tex)
			mm.set_shader_parameter("value", 1.0 if is_hair else 0.0)
			mm.set_shader_parameter("use_alpha", cut)
			_surfaces.append({"mesh": mi, "surface": s, "colour": colour, "mask": mm})
	return true


func _use_materials(which: String) -> void:
	for e in _surfaces:
		(e.mesh as MeshInstance3D).set_surface_override_material(e.surface, e[which])


# --- Cameras -------------------------------------------------------------------------

func _build_viewports() -> void:
	var scale: int = int(_opt["scale"])
	for i in range(VIEW_YAW.size()):
		var vp: SubViewport = SubViewport.new()
		vp.size = Vector2i(FRAME_W * scale, FRAME_H * scale)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.msaa_3d = Viewport.MSAA_4X
		root.add_child(vp)
		var cam: Camera3D = Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.near = 0.05
		cam.far = 60.0
		vp.add_child(cam)
		cam.current = true
		_viewports.append(vp)
		_cameras.append(cam)


## Points camera `i` at the figure: `yaw` around it, `elevation` above the
## horizon. The figure's ground point (the origin) lands `margin` pixels above
## the bottom centre of the cell — the game anchors the sprite there.
func _place_camera(i: int, yaw: float, elevation: float) -> void:
	var e: float = deg_to_rad(elevation)
	var y: float = deg_to_rad(yaw)
	var back: Vector3 = Vector3(sin(y) * cos(e), sin(e), cos(y) * cos(e))
	var up_cam: Vector3 = (Vector3.UP + back * Vector3.UP.dot(-back)).normalized()
	var size: float = float(FRAME_H) / float(_opt["px_per_m"])
	var centre: Vector3 = up_cam * (size * 0.5 - float(_opt["margin"]) / float(_opt["px_per_m"]))
	_cameras[i].size = size
	_cameras[i].look_at_from_position(centre + back * 12.0, centre, Vector3.UP)


# --- Rendering -----------------------------------------------------------------------

## Renders one sheet of the plan. Returns {name, colour, mask, frames, rows}.
func _render_sheet(entry: Dictionary) -> Dictionary:
	var sheet_name: String = String(entry["name"])
	var clip: String = String(entry["clip"])
	if not _anim.has_animation(clip):
		_report.append("%s: Clip '%s' fehlt in der GLB — ausgelassen" % [sheet_name, clip])
		return {}
	var times: Array = entry["zeiten"]
	var sight: String = String(entry.get("sicht", ""))
	var views: Array[int] = []
	if sight == "":
		for i in range(VIEW_YAW.size()):
			views.append(i)
			_place_camera(i, VIEW_YAW[i], float(_opt["elevation"]))
	else:
		# Viewless pose: one row, seen level from the front or from the back.
		views.append(0)
		_place_camera(0, 180.0 if sight == "back" else 0.0, 0.0)
	var cols: int = times.size()
	var rows: int = views.size()
	var colour: PackedByteArray = PackedByteArray()
	colour.resize(cols * FRAME_W * rows * FRAME_H * 4)
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(cols * FRAME_W * rows * FRAME_H)
	var cut_cells: int = 0
	for f in range(cols):
		_anim.play(clip)
		_anim.seek(float(times[f]), true)
		_anim.pause()
		_use_materials("colour")
		await process_frame
		await RenderingServer.frame_post_draw
		var colour_cells: Array[PackedByteArray] = []
		for r in range(rows):
			colour_cells.append(_shrunk(_viewports[views[r]]))
		_use_materials("mask")
		await process_frame
		await RenderingServer.frame_post_draw
		for r in range(rows):
			var cell: Dictionary = _finish_cell(colour_cells[r], _shrunk(_viewports[views[r]]))
			if cell.cut:
				cut_cells += 1
			_blit(colour, cell.colour, cols * FRAME_W, f * FRAME_W, r * FRAME_H, 4)
			_blit(mask, cell.mask, cols * FRAME_W, f * FRAME_W, r * FRAME_H, 1)
	if cut_cells > 0:
		_report.append("%s: %d Zelle(n) beruehren den Zellrand (Figur angeschnitten?)" % [sheet_name, cut_cells])
	return {"name": sheet_name, "frames": cols, "rows": rows,
		"colour": Image.create_from_data(cols * FRAME_W, rows * FRAME_H, false, Image.FORMAT_RGBA8, colour),
		"mask": Image.create_from_data(cols * FRAME_W, rows * FRAME_H, false, Image.FORMAT_L8, mask)}


## The viewport's picture, box-filtered down to one cell. PREMULTIPLIED RGBA8
## bytes: averaging straight alpha would drag the transparent black into the
## figure's edge.
func _shrunk(vp: SubViewport) -> PackedByteArray:
	var img: Image = vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.premultiply_alpha()
	while img.get_width() > FRAME_W:
		img.shrink_x2()
	return img.get_data()


## Turns the two shrunk pictures into the final cell: binary alpha, straight
## colour, the mask only where the figure is, and the outline around it.
func _finish_cell(colour_pm: PackedByteArray, mask_pm: PackedByteArray) -> Dictionary:
	var n: int = FRAME_W * FRAME_H
	var colour: PackedByteArray = PackedByteArray()
	colour.resize(n * 4)
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(n)
	var solid: PackedByteArray = PackedByteArray()
	solid.resize(n)
	for p in range(n):
		var a: int = colour_pm[p * 4 + 3]
		if a < 128:
			continue
		solid[p] = 1
		colour[p * 4] = mini(255, colour_pm[p * 4] * 255 / a)
		colour[p * 4 + 1] = mini(255, colour_pm[p * 4 + 1] * 255 / a)
		colour[p * 4 + 2] = mini(255, colour_pm[p * 4 + 2] * 255 / a)
		colour[p * 4 + 3] = 255
		var ma: int = mask_pm[p * 4 + 3]
		mask[p] = mini(255, mask_pm[p * 4] * 255 / ma) if ma >= 128 else 0
	var cut: bool = false
	for x in range(FRAME_W):
		if solid[x] == 1:
			cut = true
	for y in range(FRAME_H):
		if solid[y * FRAME_W] == 1 or solid[y * FRAME_W + FRAME_W - 1] == 1:
			cut = true
	if float(_opt["outline"]) > 0.5:
		var r: int = int(OUTLINE.r * 255.0)
		var g: int = int(OUTLINE.g * 255.0)
		var b: int = int(OUTLINE.b * 255.0)
		for y in range(FRAME_H):
			for x in range(FRAME_W):
				var p: int = y * FRAME_W + x
				if solid[p] == 1:
					continue
				if (x > 0 and solid[p - 1] == 1) or (x < FRAME_W - 1 and solid[p + 1] == 1) \
						or (y > 0 and solid[p - FRAME_W] == 1) \
						or (y < FRAME_H - 1 and solid[p + FRAME_W] == 1):
					colour[p * 4] = r
					colour[p * 4 + 1] = g
					colour[p * 4 + 2] = b
					colour[p * 4 + 3] = 255
	return {"colour": colour, "mask": mask, "cut": cut}


func _blit(sheet: PackedByteArray, cell: PackedByteArray, sheet_w: int, x0: int, y0: int,
		channels: int) -> void:
	for y in range(FRAME_H):
		var src: int = y * FRAME_W * channels
		var dst: int = ((y0 + y) * sheet_w + x0) * channels
		for k in range(FRAME_W * channels):
			sheet[dst + k] = cell[src + k]


# --- Contact sheets ------------------------------------------------------------------

## All sheets side by side, tinted through their masks the way the game does it
## (two tribe colours alternating per sheet), on a neutral ground.
func _write_previews(sheets: Array[Dictionary], dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var total_w: int = 0
	for s in sheets:
		total_w += int(s.frames) * FRAME_W + 4
	var h: int = VIEW_YAW.size() * FRAME_H
	var strip: Image = Image.create(maxi(total_w, 1), h, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.42, 0.5, 0.38))
	var x: int = 0
	var big_w: int = 0
	for i in range(sheets.size()):
		var s: Dictionary = sheets[i]
		var tinted: Image = _tinted(s.colour, s.mask, PREVIEW_TINTS[i % PREVIEW_TINTS.size()])
		strip.blend_rect(tinted, Rect2i(Vector2i.ZERO, tinted.get_size()), Vector2i(x, 0))
		x += int(s.frames) * FRAME_W + 4
		if i < 4:
			big_w = x
	strip.save_png(dir.path_join("kontakt.png"))
	var big: Image = strip.get_region(Rect2i(0, 0, mini(big_w, strip.get_width()), h))
	big.resize(big.get_width() * 2, big.get_height() * 2, Image.INTERPOLATE_NEAREST)
	big.save_png(dir.path_join("kontakt_gross.png"))


func _tinted(colour: Image, mask: Image, tint: Color) -> Image:
	var out: Image = colour.duplicate() as Image
	var c: PackedByteArray = out.get_data()
	var m: PackedByteArray = mask.get_data()
	for p in range(m.size()):
		var k: float = float(m[p]) / 255.0
		c[p * 4] = int(float(c[p * 4]) * lerpf(1.0, tint.r, k))
		c[p * 4 + 1] = int(float(c[p * 4 + 1]) * lerpf(1.0, tint.g, k))
		c[p * 4 + 2] = int(float(c[p * 4 + 2]) * lerpf(1.0, tint.b, k))
	return Image.create_from_data(out.get_width(), out.get_height(), false, Image.FORMAT_RGBA8, c)
