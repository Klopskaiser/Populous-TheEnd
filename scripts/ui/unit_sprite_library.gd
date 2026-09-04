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
## PlaceholderSprites.VIEWS order, 5 rows front/back/right/front_right/
## back_right with the left views mirrored, or a SINGLE row that serves every
## view — see sheet_cut_plan), columns = frames. All frames are
## blitted into ONE uniform atlas cell (the max frame size over all kinds);
## smaller frames are upscaled nearest-neighbour, so the renderer's single
## frame_uv uniform keeps working unchanged.
##
## The SAME sheet-or-placeholder decision also feeds the sidebar's shaman
## portrait via make_portrait_frames() — that is the whole point of this class
## living between the renderer and PlaceholderSprites: there must be exactly ONE
## place that asks AssetLibrary whether real art exists.

const MAX_ATLAS_WIDTH: int = 4096

## Row order of 5-row sheets; the three left views mirror their right twin.
const SHEET_ROWS_5: Array[StringName] = [
	&"front", &"back", &"right", &"front_right", &"back_right"]
const MIRROR_SOURCE: Dictionary = {
	&"left": &"right", &"front_left": &"front_right", &"back_left": &"back_right"}


## Drop-in replacement for PlaceholderSprites.build_atlas (plus mask_texture).
static func build_atlas(kinds: Array[StringName]) -> Dictionary:
	# 1) Load + slice all available sheets and find the atlas cell size.
	var sheets: Dictionary = {}   # kind -> anim -> {"slots": {int -> [Image]}, "masks": {int -> [Image]}, "fps": float}
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
			var slots: int = PlaceholderSprites.slot_count(anim)
			for slot in range(PlaceholderSprites.VIEWS.size()):
				# The table always holds eight entries. A viewless pose fills only
				# its variants (the two corpse landings) and lets the rest point
				# at variant 0 instead of storing identical copies.
				if slot >= slots:
					per_view.append((per_view[0] as Array).duplicate())
					continue
				var frame_images: Array[Image] = []
				var mask_images: Array = []
				var fps: float = PlaceholderSprites._anim_fps(anim)
				if not sheet.is_empty():
					frame_images.assign(sheet.slots[slot])
					mask_images = sheet.masks.get(slot, [])
					fps = sheet.fps
				else:
					frame_images = PlaceholderSprites.build_slot(kind, anim, slot)
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


## One shared 1x1 white mask for every frame that has no <anim>_mask.png. The
## portrait shader multiplies by mix(1, tint, mask.r), so white means "tint the
## whole pixel" — exactly what the renderer's white atlas cells do.
static var _white_mask: ImageTexture = null


static func white_mask_texture() -> ImageTexture:
	if _white_mask == null:
		var img: Image = Image.create(1, 1, false, Image.FORMAT_L8)
		img.fill(Color.WHITE)
		_white_mask = ImageTexture.create_from_image(img)
	return _white_mask


## SpriteFrames for the sidebar's shaman portrait: the FRONT drawing of every
## animation the kind has, taken from the user's sheets where they exist and
## from PlaceholderSprites everywhere else — the same decision build_atlas makes
## for the game world. Returns:
##   frames: SpriteFrames with one animation per base, named "<anim>_front"
##   masks:  SpriteFrames frame-for-frame PARALLEL to it (the white 1x1 texture
##           wherever a frame brought no mask), so the portrait can feed its
##           tint shader straight from the current animation + frame index
##   cell:   the uniform frame size, which the caller scales into its stage
##
## Only the front view is built. The portrait never asks for another one
## (Sidebar._refresh_portrait plays "<anim>_front"), and slot 0 is the right
## drawing for EVERY pose: the front row of a normal one (sheet_cut_plan maps
## front to row 1, unmirrored, for 1/5/8-row sheets) and variant 0 of a viewless
## one — the corpse lying on its BACK, i.e. dead_back.png, which is precisely the
## face-up drawing the animation named "dead_front" wants.
static func make_portrait_frames(kind: StringName) -> Dictionary:
	var manifest: Dictionary = AssetLibrary.json("units/%s/manifest.json" % kind)
	var anims: Array[StringName] = PlaceholderSprites._anims_for(kind)
	# 1) Slice first: the cell size is only known once every sheet of this kind
	#    has been seen (same two-pass shape as build_atlas).
	var sliced: Dictionary = {}
	var cell_w: int = PlaceholderSprites.W
	var cell_h: int = PlaceholderSprites.H
	for anim in anims:
		var sheet: Dictionary = _slice_sheet(kind, anim, manifest)
		if sheet.is_empty():
			continue
		sliced[anim] = sheet
		cell_w = maxi(cell_w, int(manifest.get("frame_width", 0)))
		cell_h = maxi(cell_h, int(manifest.get("frame_height", 0)))

	# 2) Fill the two parallel resources, everything fitted into the same cell so
	#    the portrait does not change size when the animation changes.
	var frames: SpriteFrames = SpriteFrames.new()
	frames.remove_animation("default")
	var masks: SpriteFrames = SpriteFrames.new()
	masks.remove_animation("default")
	var white: ImageTexture = white_mask_texture()
	for anim in anims:
		var sheet: Dictionary = sliced.get(anim, {})
		var images: Array[Image] = _portrait_slot(sheet, kind, anim)
		if images.is_empty():
			continue   # play() on a 0-frame animation would fail silently
		var mask_images: Array = sheet.masks.get(0, []) if not sheet.is_empty() else []
		var fps: float = float(sheet.fps) if not sheet.is_empty() \
				else PlaceholderSprites._anim_fps(anim)
		var name: StringName = StringName("%s_front" % anim)
		for target: SpriteFrames in [frames, masks]:
			target.add_animation(name)
			target.set_animation_speed(name, fps)
			target.set_animation_loop(name, true)
		for i in range(images.size()):
			frames.add_frame(name, ImageTexture.create_from_image(
				_fit_cell(images[i], cell_w, cell_h, Image.FORMAT_RGBA8)))
			var mask_tex: Texture2D = white
			if i < mask_images.size():
				mask_tex = ImageTexture.create_from_image(
					_fit_cell(mask_images[i], cell_w, cell_h, Image.FORMAT_L8))
			masks.add_frame(name, mask_tex)
	return {"frames": frames, "masks": masks, "cell": Vector2i(cell_w, cell_h)}


## The front-view images of ONE animation: the sheet's slot 0 where the kind has
## usable art, the procedural placeholder otherwise. Stays on the Image level (no
## ImageTexture, no RenderingServer), so the sheet-or-placeholder decision behind
## the portrait is assertable headless.
static func portrait_slot_images(kind: StringName, anim: StringName,
		manifest: Dictionary) -> Array[Image]:
	return _portrait_slot(_slice_sheet(kind, anim, manifest), kind, anim)


## Shared by both entry points above so the decision exists exactly once.
static func _portrait_slot(sheet: Dictionary, kind: StringName,
		anim: StringName) -> Array[Image]:
	if sheet.is_empty():
		return PlaceholderSprites.build_slot(kind, anim, 0)
	var images: Array[Image] = []
	images.assign(sheet.slots[0])
	return images


## Slices one animation's user art into SLOT-keyed frame lists, matching the
## atlas table: a normal pose's slots are its eight views, a viewless pose's are
## its variants (PlaceholderSprites.VIEWLESS_POSES). Returns {} when the art is
## missing or malformed — the caller then uses the procedural frames.
static func _slice_sheet(kind: StringName, anim: StringName, manifest: Dictionary) -> Dictionary:
	var fps: float = PlaceholderSprites._anim_fps(anim)
	var anims_meta: Dictionary = manifest.get("anims", {})
	if anims_meta.has(String(anim)):
		fps = float((anims_meta[String(anim)] as Dictionary).get("fps", fps))
	var slots: Dictionary = {}
	var slot_masks: Dictionary = {}
	if PlaceholderSprites.anim_is_viewless(anim):
		# One FILE per variant, each a single row: "dead_back.png" (on the back)
		# and "dead_front.png" (on the belly). All or nothing — a half-delivered
		# corpse would mix hand-drawn and procedural landings.
		var count: int = PlaceholderSprites.slot_count(anim)
		for slot in range(count):
			var suffix: StringName = PlaceholderSprites.variant_suffix(anim, slot)
			var name: String = String(anim) if suffix == &"" \
					else "%s_%s" % [anim, suffix]
			var cut: Dictionary = _cut_sheet(kind, name, manifest, 0)
			if cut.is_empty():
				if not slots.is_empty():
					push_warning("UnitSpriteLibrary: units/%s/%s.png fehlt oder ist unbrauchbar, obwohl die anderen Varianten von '%s' da sind — Platzhalter bleibt fuer ALLE Varianten aktiv." % [kind, name, anim])
				return {}
			slots[slot] = cut.frames
			if not (cut.masks as Array).is_empty():
				slot_masks[slot] = cut.masks
		return {"slots": slots, "masks": slot_masks, "fps": fps}

	var cut: Dictionary = _cut_sheet(kind, String(anim), manifest, -1)
	if cut.is_empty():
		return {}
	for slot in range(PlaceholderSprites.VIEWS.size()):
		slots[slot] = (cut.views as Dictionary)[PlaceholderSprites.VIEWS[slot]]
		var m: Dictionary = cut.view_masks
		if m.has(PlaceholderSprites.VIEWS[slot]):
			slot_masks[slot] = m[PlaceholderSprites.VIEWS[slot]]
	return {"slots": slots, "masks": slot_masks, "fps": fps}


## Loads + validates assets/units/<kind>/<name>.png (plus its optional
## <name>_mask.png) and cuts it. With row >= 0 only that row is cut and returned
## as "frames"/"masks"; with row < 0 the full sheet_cut_plan is applied and
## returned as "views"/"view_masks". Returns {} on anything unusable, after a
## warning that names the file and the reason.
static func _cut_sheet(kind: StringName, name: String, manifest: Dictionary,
		row: int) -> Dictionary:
	var rel: String = "units/%s/%s.png" % [kind, name]
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
	var plan: Dictionary = {}
	if row >= 0:
		if row_count <= row:
			push_warning("UnitSpriteLibrary: '%s' hat nur %d Zeile(n) — Zeile %d wird gebraucht. Platzhalter bleibt aktiv." % [rel, row_count, row + 1])
			return {}
	else:
		plan = sheet_cut_plan(row_count)
		if plan.is_empty():
			push_warning("UnitSpriteLibrary: '%s' hat %d Zeilen — erlaubt sind 1, 5 oder 8 Blickrichtungen. Platzhalter bleibt aktiv." % [rel, row_count])
			return {}
	var mask_img: Image = AssetLibrary.image("units/%s/%s_mask.png" % [kind, name])
	if mask_img != null and (mask_img.get_width() != img.get_width()
			or mask_img.get_height() != img.get_height()):
		push_warning("UnitSpriteLibrary: '%s_mask.png' passt nicht zur Sheet-Groesse — Maske wird ignoriert." % name)
		mask_img = null
	if mask_img != null and mask_img.get_format() != Image.FORMAT_RGBA8:
		mask_img.convert(Image.FORMAT_RGBA8)

	if row >= 0:
		return {
			"frames": _cut_row(img, row, fw, fh, frame_count),
			"masks": _cut_row(mask_img, row, fw, fh, frame_count) if mask_img != null \
					else ([] as Array[Image]),
		}

	var views: Dictionary = {}
	var view_masks: Dictionary = {}
	# Every row is cut ONCE and shared by the views that read it (a 1-row sheet
	# is cut a single time for all eight).
	var row_cache: Dictionary = {}
	var mask_cache: Dictionary = {}
	for view in PlaceholderSprites.VIEWS:
		var entry: Array = plan[view]
		var r: int = int(entry[0])
		if not row_cache.has(r):
			row_cache[r] = _cut_row(img, r, fw, fh, frame_count)
			if mask_img != null:
				mask_cache[r] = _cut_row(mask_img, r, fw, fh, frame_count)
		var frames: Array[Image] = row_cache[r]
		var mask_frames: Array[Image] = mask_cache.get(r, [] as Array[Image])
		if bool(entry[1]):
			frames = _mirror_frames(frames)
			if not mask_frames.is_empty():
				mask_frames = _mirror_frames(mask_frames)
		views[view] = frames
		if not mask_frames.is_empty():
			view_masks[view] = mask_frames
	return {"views": views, "view_masks": view_masks}


## How a sheet with `row_count` rows is cut: view -> [row index, mirror].
##   1 row  = ONE drawing for EVERY view, never mirrored. Only reached by the
##            poses that DO have views — the viewless ones are cut per variant
##            file and always read row 1 (see _slice_sheet).
##   5 rows = front/back/right/front_right/back_right drawn, the three left views
##            mirrored from their right twin.
##   8 rows = every view drawn individually (left may differ from right).
## An empty dictionary means the row count is unsupported. Pure function so the
## rule is assertable headless.
static func sheet_cut_plan(row_count: int) -> Dictionary:
	var plan: Dictionary = {}
	match row_count:
		1:
			for view in PlaceholderSprites.VIEWS:
				plan[view] = [0, false]
		5:
			for i in range(SHEET_ROWS_5.size()):
				plan[SHEET_ROWS_5[i]] = [i, false]
			for view in MIRROR_SOURCE:
				plan[view] = [SHEET_ROWS_5.find(MIRROR_SOURCE[view]), true]
		8:
			for i in range(PlaceholderSprites.VIEWS.size()):
				plan[PlaceholderSprites.VIEWS[i]] = [i, false]
	return plan


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
