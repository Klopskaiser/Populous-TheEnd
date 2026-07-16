class_name UnitSpriteLibrary

## Builds the shared unit sprite atlas for the MultiMesh UnitRenderer, mixing
## user-provided sprite sheets (assets/units/<kind>/<anim>.png, sliced per the
## kind's manifest.json) with the procedural PlaceholderSprites frames for
## every (kind, anim) that has no sheet. The returned dictionary keeps the
## exact PlaceholderSprites.build_atlas contract (texture / uvs / frame_uv /
## table) plus "mask_texture": an L8 atlas gating the tribe-colour multiply
## per pixel (white = full tint; placeholder frames and sheets without a
## <anim>_mask.png get a white mask, which reproduces the old full multiply).
##
## Sheet layout (see assets/README.md): rows = directional views (8 rows in
## PlaceholderSprites.VIEWS order, or 5 rows front/back/right/front_right/
## back_right with the left views mirrored), columns = frames. All frames are
## blitted into ONE uniform atlas cell (the max frame size over all kinds);
## smaller frames are upscaled nearest-neighbour, so the renderer's single
## frame_uv uniform keeps working unchanged.

const MAX_ATLAS_WIDTH: int = 4096

## Row order of 5-row sheets; the three left views mirror their right twin.
const SHEET_ROWS_5: Array[StringName] = [
	&"front", &"back", &"right", &"front_right", &"back_right"]
const MIRROR_SOURCE: Dictionary = {
	&"left": &"right", &"front_left": &"front_right", &"back_left": &"back_right"}


## Drop-in replacement for PlaceholderSprites.build_atlas (plus mask_texture).
static func build_atlas(kinds: Array[StringName]) -> Dictionary:
	# 1) Load + slice all available sheets and find the atlas cell size.
	var sheets: Dictionary = {}   # kind -> anim -> {"views": {view -> [Image]}, "masks": {view -> [Image]}, "fps": float}
	var cell_w: int = PlaceholderSprites.W
	var cell_h: int = PlaceholderSprites.H
	for kind in kinds:
		var manifest: Dictionary = AssetLibrary.json("units/%s/manifest.json" % kind)
		var per_anim: Dictionary = {}
		for anim in PlaceholderSprites._anims_for(kind):
			var sliced: Dictionary = _slice_sheet(kind, anim, manifest)
			if sliced.is_empty():
				continue
			per_anim[anim] = sliced
			cell_w = maxi(cell_w, int(manifest.get("frame_width", 0)))
			cell_h = maxi(cell_h, int(manifest.get("frame_height", 0)))
		if not per_anim.is_empty():
			sheets[kind] = per_anim

	# 2) Collect every frame (+ its mask) in PlaceholderSprites atlas order.
	var images: Array[Image] = []
	var masks: Array = []   # Image or null (null = white cell)
	var table: Dictionary = {}
	for kind in kinds:
		var kind_sheets: Dictionary = sheets.get(kind, {})
		var per_base: Dictionary = {}
		for anim in PlaceholderSprites._anims_for(kind):
			var sheet: Dictionary = kind_sheets.get(anim, {})
			var per_view: Array = []
			for view in PlaceholderSprites.VIEWS:
				var frame_images: Array[Image] = []
				var mask_images: Array = []
				var fps: float = PlaceholderSprites._anim_fps(anim)
				if not sheet.is_empty():
					frame_images.assign(sheet.views[view])
					mask_images = sheet.masks.get(view, [])
					fps = sheet.fps
				else:
					frame_images = PlaceholderSprites._build_frames(kind, anim, view)
				per_view.append([images.size(), frame_images.size(), fps])
				for i in range(frame_images.size()):
					images.append(frame_images[i])
					masks.append(mask_images[i] if i < mask_images.size() else null)
			per_base[anim] = per_view
		table[kind] = per_base

	# 3) Blit colour + mask atlases with one uniform cell size.
	var cols: int = clampi(MAX_ATLAS_WIDTH / cell_w, 1, maxi(images.size(), 1))
	var rows: int = int(ceil(float(images.size()) / float(cols)))
	var atlas: Image = Image.create(cols * cell_w, rows * cell_h, false, Image.FORMAT_RGBA8)
	var mask_atlas: Image = Image.create(cols * cell_w, rows * cell_h, false, Image.FORMAT_L8)
	var white_cell: Image = Image.create(cell_w, cell_h, false, Image.FORMAT_L8)
	white_cell.fill(Color.WHITE)
	var uvs: PackedVector2Array = PackedVector2Array()
	var atlas_size: Vector2 = Vector2(float(cols * cell_w), float(rows * cell_h))
	var cell_rect: Rect2i = Rect2i(0, 0, cell_w, cell_h)
	for i in range(images.size()):
		var pos: Vector2i = Vector2i((i % cols) * cell_w, (i / cols) * cell_h)
		atlas.blit_rect(_fit_cell(images[i], cell_w, cell_h, Image.FORMAT_RGBA8), cell_rect, pos)
		var mask: Image = masks[i]
		if mask == null:
			mask_atlas.blit_rect(white_cell, cell_rect, pos)
		else:
			mask_atlas.blit_rect(_fit_cell(mask, cell_w, cell_h, Image.FORMAT_L8), cell_rect, pos)
		uvs.append(Vector2(pos) / atlas_size)
	return {
		"texture": ImageTexture.create_from_image(atlas),
		"mask_texture": ImageTexture.create_from_image(mask_atlas),
		"uvs": uvs,
		"frame_uv": Vector2(float(cell_w), float(cell_h)) / atlas_size,
		"table": table,
	}


## Slices assets/units/<kind>/<anim>.png (+ optional <anim>_mask.png) into
## per-view frame lists. Returns {} when the sheet is missing or malformed
## (then the caller uses the procedural frames for this anim).
static func _slice_sheet(kind: StringName, anim: StringName, manifest: Dictionary) -> Dictionary:
	var rel: String = "units/%s/%s.png" % [kind, anim]
	var img: Image = AssetLibrary.image(rel)
	if img == null:
		return {}
	# blit_rect needs matching formats; PNGs import as RGB8 without alpha.
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var fw: int = int(manifest.get("frame_width", 0))
	var fh: int = int(manifest.get("frame_height", 0))
	if fw <= 0 or fh <= 0:
		push_warning("UnitSpriteLibrary: '%s' vorhanden, aber units/%s/manifest.json fehlt oder hat kein frame_width/frame_height — Platzhalter bleibt aktiv." % [rel, kind])
		return {}
	if img.get_width() % fw != 0 or img.get_height() % fh != 0:
		push_warning("UnitSpriteLibrary: '%s' (%dx%d) ist kein Vielfaches der Framegroesse %dx%d — Platzhalter bleibt aktiv." % [rel, img.get_width(), img.get_height(), fw, fh])
		return {}
	var frame_count: int = img.get_width() / fw
	var row_count: int = img.get_height() / fh
	if row_count != 5 and row_count != 8:
		push_warning("UnitSpriteLibrary: '%s' hat %d Zeilen — erlaubt sind 5 oder 8 Blickrichtungen. Platzhalter bleibt aktiv." % [rel, row_count])
		return {}
	var mask_img: Image = AssetLibrary.image("units/%s/%s_mask.png" % [kind, anim])
	if mask_img != null and (mask_img.get_width() != img.get_width()
			or mask_img.get_height() != img.get_height()):
		push_warning("UnitSpriteLibrary: '%s_mask.png' passt nicht zur Sheet-Groesse — Maske wird ignoriert." % anim)
		mask_img = null
	if mask_img != null and mask_img.get_format() != Image.FORMAT_RGBA8:
		mask_img.convert(Image.FORMAT_RGBA8)

	var row_views: Array[StringName] = SHEET_ROWS_5 if row_count == 5 \
			else PlaceholderSprites.VIEWS
	var views: Dictionary = {}
	var view_masks: Dictionary = {}
	for row in range(row_count):
		views[row_views[row]] = _cut_row(img, row, fw, fh, frame_count)
		if mask_img != null:
			view_masks[row_views[row]] = _cut_row(mask_img, row, fw, fh, frame_count)
	if row_count == 5:
		for view in MIRROR_SOURCE:
			var src: StringName = MIRROR_SOURCE[view]
			views[view] = _mirror_frames(views[src])
			if view_masks.has(src):
				view_masks[view] = _mirror_frames(view_masks[src])

	var fps: float = PlaceholderSprites._anim_fps(anim)
	var anims_meta: Dictionary = manifest.get("anims", {})
	if anims_meta.has(String(anim)):
		fps = float((anims_meta[String(anim)] as Dictionary).get("fps", fps))
	return {"views": views, "masks": view_masks, "fps": fps}


static func _cut_row(sheet: Image, row: int, fw: int, fh: int, count: int) -> Array[Image]:
	var frames: Array[Image] = []
	for i in range(count):
		var frame: Image = Image.create(fw, fh, false, Image.FORMAT_RGBA8)
		frame.blit_rect(sheet, Rect2i(i * fw, row * fh, fw, fh), Vector2i.ZERO)
		frames.append(frame)
	return frames


static func _mirror_frames(frames: Array[Image]) -> Array[Image]:
	var mirrored: Array[Image] = []
	for frame in frames:
		var copy: Image = frame.duplicate()
		copy.flip_x()
		mirrored.append(copy)
	return mirrored


## Converts + nearest-upscales a frame into the shared atlas cell size.
static func _fit_cell(img: Image, cw: int, ch: int, format: Image.Format) -> Image:
	var result: Image = img
	if result.get_format() != format:
		result = result.duplicate()
		result.convert(format)
	if result.get_width() != cw or result.get_height() != ch:
		if result == img:
			result = result.duplicate()
		result.resize(cw, ch, Image.INTERPOLATE_NEAREST)
	return result
