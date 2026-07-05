class_name PlaceholderSprites

## Procedural placeholder sprite factory (no external asset files).
##
## Builds 16x24 pixel-art frames via Image fill_rect patterns. The sprites are
## drawn in near-white so the tribe colour is applied by the unit itself via
## modulate. Only ever call this from _ready() of scenes (headless rule:
## Image/ImageTexture work with the dummy RenderingServer, but core logic
## tests must not depend on texture contents).
##
## Directional views: every animation exists in four variants named
## "<anim>_<view>" with view in front/back/left/right (e.g. "walk_back").
## The Unit picks the view from its facing relative to the camera. To replace
## the placeholders with real art later, provide a SpriteFrames resource with
## the same animation names — nothing else has to change.
## Placeholder telltales: front = two eyes, back = hair patch, side = one eye
## (left is the mirrored right view).

const W: int = 16
const H: int = 24

const C_HEAD: Color = Color(1.0, 1.0, 1.0)
const C_BODY: Color = Color(0.92, 0.92, 0.92)
const C_LIMB: Color = Color(0.78, 0.78, 0.78)
const C_EYE: Color = Color(0.12, 0.12, 0.12)
const C_HAIR: Color = Color(0.5, 0.5, 0.5)
## Carried log (matches the wood-pile colours).
const C_WOOD: Color = Color(0.55, 0.36, 0.2)
const C_WOOD_END: Color = Color(0.35, 0.22, 0.1)

## Casters get the "cast" animation (see CLAUDE.md par. 3).
const CASTER_KINDS: Array[StringName] = [&"shaman", &"preacher"]

const VIEWS: Array[StringName] = [&"front", &"back", &"right", &"left"]


## One shared SpriteFrames per kind — building the frames is expensive and
## AnimatedSprite3D instances can share the resource (each keeps its own
## frame index). Without the cache, spawning hundreds of units rebuilt all
## images per unit and caused visible hitches.
static var _cache: Dictionary[StringName, SpriteFrames] = {}


## Builds the SpriteFrames (idle/walk/attack, plus cast for casters), each in
## all four directional views. All current kinds share the same silhouette.
static func make_frames(unit_kind: StringName) -> SpriteFrames:
	if _cache.has(unit_kind):
		return _cache[unit_kind]
	var frames: SpriteFrames = SpriteFrames.new()
	frames.remove_animation("default")
	# "jump" is frame-driven by the hop visual (frame 0 = arms down on the
	# ground, frame 1 = arms up in the air), not by the animation timer.
	var anims: Array[StringName] = [
		&"idle", &"walk", &"attack", &"jump", &"carry", &"carry_walk"]
	if unit_kind in CASTER_KINDS:
		anims.append(&"cast")
	for anim in anims:
		for view in VIEWS:
			var full_name: StringName = StringName("%s_%s" % [anim, view])
			_add_animation(frames, full_name, _build_frames(anim, view), _anim_fps(anim))
	_cache[unit_kind] = frames
	return frames


## Builds one texture atlas with ALL frames of the given kinds, for the
## MultiMesh-based UnitRenderer (one draw call for all units instead of one
## AnimatedSprite3D per unit). Returns:
##   texture:  ImageTexture with all frames in a grid
##   uvs:      PackedVector2Array — UV offset per global frame index
##   frame_uv: Vector2 — UV size of one frame
##   table:    kind -> anim base -> Array[4 views] of [start, count, fps]
##             (view order matches VIEWS: front, back, right, left)
static func build_atlas(kinds: Array[StringName]) -> Dictionary:
	var images: Array[Image] = []
	var table: Dictionary = {}
	for kind in kinds:
		var anims: Array[StringName] = [
			&"idle", &"walk", &"attack", &"jump", &"carry", &"carry_walk"]
		if kind in CASTER_KINDS:
			anims.append(&"cast")
		var per_base: Dictionary = {}
		for anim in anims:
			var per_view: Array = []
			for view in VIEWS:
				var frame_images: Array[Image] = _build_frames(anim, view)
				per_view.append([images.size(), frame_images.size(), _anim_fps(anim)])
				images.append_array(frame_images)
			per_base[anim] = per_view
		table[kind] = per_base

	var cols: int = 16
	var rows: int = int(ceil(float(images.size()) / float(cols)))
	var atlas: Image = Image.create(cols * W, rows * H, false, Image.FORMAT_RGBA8)
	var uvs: PackedVector2Array = PackedVector2Array()
	var atlas_size: Vector2 = Vector2(float(cols * W), float(rows * H))
	for i in range(images.size()):
		var px: int = (i % cols) * W
		var py: int = (i / cols) * H
		atlas.blit_rect(images[i], Rect2i(0, 0, W, H), Vector2i(px, py))
		uvs.append(Vector2(float(px), float(py)) / atlas_size)
	return {
		"texture": ImageTexture.create_from_image(atlas),
		"uvs": uvs,
		"frame_uv": Vector2(float(W), float(H)) / atlas_size,
		"table": table,
	}


static func _anim_fps(anim: StringName) -> float:
	match anim:
		&"walk", &"carry_walk":
			return 8.0
		&"attack":
			return 6.0
		&"cast":
			return 4.0
		_:
			return 2.0


## Frames for one animation in one view. The left view is the mirrored right
## view (real art can replace it with distinct frames later).
static func _build_frames(anim: StringName, view: StringName) -> Array[Image]:
	var paint_view: StringName = &"right" if view == &"left" else view
	var images: Array[Image] = []
	match anim:
		&"walk":
			images = [
				_frame_walk(paint_view, 0), _frame_stand(paint_view, 0),
				_frame_walk(paint_view, 1), _frame_stand(paint_view, 0),
			]
		&"attack":
			images = [_frame_stand(paint_view, 0), _frame_attack(paint_view)]
		&"jump":
			images = [_frame_stand(paint_view, 0), _frame_jump(paint_view)]
		&"carry":
			images = [_frame_carry(paint_view, 0), _frame_carry(paint_view, 1)]
		&"carry_walk":
			images = [
				_frame_carry_walk(paint_view, 0), _frame_carry(paint_view, 0),
				_frame_carry_walk(paint_view, 1), _frame_carry(paint_view, 0),
			]
		&"cast":
			images = [_frame_stand(paint_view, 0), _frame_cast(paint_view)]
		_:
			images = [_frame_stand(paint_view, 0), _frame_stand(paint_view, 1)]
	if view == &"left":
		for img in images:
			img.flip_x()
	return images


static func _add_animation(frames: SpriteFrames, anim: StringName,
		images: Array[Image], fps: float) -> void:
	frames.add_animation(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, true)
	for img in images:
		frames.add_frame(anim, ImageTexture.create_from_image(img))


# --- Body part painters ----------------------------------------------------------

static func _new_image() -> Image:
	return Image.create_empty(W, H, false, Image.FORMAT_RGBA8)


static func _draw_head(img: Image, view: StringName, bob: int) -> void:
	img.fill_rect(Rect2i(5, 1 + bob, 6, 6), C_HEAD)
	match view:
		&"front":
			img.fill_rect(Rect2i(6, 3 + bob, 1, 1), C_EYE)
			img.fill_rect(Rect2i(9, 3 + bob, 1, 1), C_EYE)
		&"back":
			img.fill_rect(Rect2i(5, 1 + bob, 6, 2), C_HAIR)
		&"right":
			img.fill_rect(Rect2i(9, 3 + bob, 1, 1), C_EYE)


static func _draw_torso(img: Image, view: StringName, bob: int) -> void:
	if view == &"right":
		img.fill_rect(Rect2i(5, 7 + bob, 6, 9), C_BODY)  # narrower in profile
	else:
		img.fill_rect(Rect2i(4, 7 + bob, 8, 9), C_BODY)


static func _draw_arms_side(img: Image, view: StringName, bob: int) -> void:
	if view == &"right":
		img.fill_rect(Rect2i(7, 8 + bob, 2, 6), C_LIMB)  # only the near arm visible
	else:
		img.fill_rect(Rect2i(2, 8 + bob, 2, 6), C_LIMB)
		img.fill_rect(Rect2i(12, 8 + bob, 2, 6), C_LIMB)


static func _draw_legs_stand(img: Image) -> void:
	img.fill_rect(Rect2i(5, 16, 2, 8), C_LIMB)
	img.fill_rect(Rect2i(9, 16, 2, 8), C_LIMB)


## Draws one 2px-wide leg from a fixed hip (top) to a foot (bottom). When
## hip_x == foot_x it is a straight leg; otherwise the leg pivots at the hip and
## the foot swings — so walking swings the FEET, not the thighs.
static func _draw_leg(img: Image, hip_x: int, foot_x: int, col: Color) -> void:
	var y0: int = 16
	var y1: int = 24
	for y in range(y0, y1):
		var t: float = float(y - y0) / float(y1 - 1 - y0)
		var x: int = int(round(lerpf(float(hip_x), float(foot_x), t)))
		img.fill_rect(Rect2i(x, y, 2, 1), col)


# --- Frame builders ---------------------------------------------------------------

static func _frame_stand(view: StringName, bob: int) -> Image:
	var img: Image = _new_image()
	_draw_torso(img, view, bob)
	_draw_head(img, view, bob)
	_draw_arms_side(img, view, bob)
	_draw_legs_stand(img)
	return img


static func _frame_walk(view: StringName, phase: int) -> Image:
	var img: Image = _new_image()
	_draw_torso(img, view, 0)
	_draw_head(img, view, 0)
	_draw_arms_side(img, view, 0)
	# Hips fixed at x=5/9; the feet swing (alternating) — pivot at the hip.
	if phase == 0:
		_draw_leg(img, 5, 3, C_LIMB)    # left foot swings out
		_draw_leg(img, 9, 9, C_LIMB)    # right planted
	else:
		_draw_leg(img, 5, 5, C_LIMB)    # left planted
		_draw_leg(img, 9, 11, C_LIMB)   # right foot swings out
	return img


static func _frame_attack(view: StringName) -> Image:
	var img: Image = _new_image()
	_draw_torso(img, view, 0)
	_draw_head(img, view, 0)
	if view == &"right":
		img.fill_rect(Rect2i(11, 7, 5, 2), C_LIMB)    # arm thrust in facing direction
	else:
		img.fill_rect(Rect2i(2, 8, 2, 6), C_LIMB)
		img.fill_rect(Rect2i(12, 6, 4, 3), C_LIMB)    # arm thrust out
	_draw_legs_stand(img)
	return img


## Airborne frame of the flatten hop: both arms thrown up, legs tucked.
static func _frame_jump(view: StringName) -> Image:
	var img: Image = _new_image()
	_draw_torso(img, view, 0)
	_draw_head(img, view, 0)
	if view == &"right":
		img.fill_rect(Rect2i(9, 1, 2, 7), C_LIMB)     # near arm thrown up
	else:
		img.fill_rect(Rect2i(2, 1, 2, 7), C_LIMB)     # both arms thrown up
		img.fill_rect(Rect2i(12, 1, 2, 7), C_LIMB)
	img.fill_rect(Rect2i(5, 16, 2, 5), C_LIMB)        # legs tucked mid-air
	img.fill_rect(Rect2i(9, 16, 2, 5), C_LIMB)
	return img


## Standing while carrying a log (arms forward, a log held in front).
static func _frame_carry(view: StringName, bob: int) -> Image:
	var img: Image = _new_image()
	_draw_torso(img, view, bob)
	_draw_head(img, view, bob)
	_draw_legs_stand(img)
	_draw_carry_arms_and_log(img, view, bob)
	return img


## Walking while carrying a log.
static func _frame_carry_walk(view: StringName, phase: int) -> Image:
	var img: Image = _new_image()
	_draw_torso(img, view, 0)
	_draw_head(img, view, 0)
	if phase == 0:
		_draw_leg(img, 5, 3, C_LIMB)    # left foot swings out
		_draw_leg(img, 9, 9, C_LIMB)    # right planted
	else:
		_draw_leg(img, 5, 5, C_LIMB)    # left planted
		_draw_leg(img, 9, 11, C_LIMB)   # right foot swings out
	_draw_carry_arms_and_log(img, view, 0)
	return img


static func _draw_carry_arms_and_log(img: Image, view: StringName, bob: int) -> void:
	if view == &"right":
		img.fill_rect(Rect2i(9, 10 + bob, 3, 2), C_LIMB)         # near arm forward
		img.fill_rect(Rect2i(11, 9 + bob, 5, 4), C_WOOD)         # log jutting forward
		img.fill_rect(Rect2i(11, 9 + bob, 1, 4), C_WOOD_END)
		img.fill_rect(Rect2i(15, 9 + bob, 1, 4), C_WOOD_END)
	elif view == &"back":
		# Seen from behind, the wood is held in front and out of sight — just
		# slightly shorter side arms (he is holding something).
		img.fill_rect(Rect2i(2, 8 + bob, 2, 5), C_LIMB)
		img.fill_rect(Rect2i(12, 8 + bob, 2, 5), C_LIMB)
	else:
		img.fill_rect(Rect2i(2, 10 + bob, 2, 3), C_LIMB)         # both arms forward
		img.fill_rect(Rect2i(12, 10 + bob, 2, 3), C_LIMB)
		img.fill_rect(Rect2i(3, 10 + bob, 10, 4), C_WOOD)        # log held across
		img.fill_rect(Rect2i(3, 10 + bob, 1, 4), C_WOOD_END)
		img.fill_rect(Rect2i(12, 10 + bob, 1, 4), C_WOOD_END)


static func _frame_cast(view: StringName) -> Image:
	var img: Image = _new_image()
	_draw_torso(img, view, 0)
	_draw_head(img, view, 0)
	if view == &"right":
		img.fill_rect(Rect2i(9, 1, 2, 7), C_LIMB)     # near arm raised
	else:
		img.fill_rect(Rect2i(2, 2, 2, 7), C_LIMB)     # both arms raised
		img.fill_rect(Rect2i(12, 2, 2, 7), C_LIMB)
	_draw_legs_stand(img)
	return img
