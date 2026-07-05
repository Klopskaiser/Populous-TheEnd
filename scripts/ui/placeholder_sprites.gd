class_name PlaceholderSprites

## Procedural placeholder sprite factory (no external asset files).
##
## Builds 16x24 pixel-art frames via Image fill_rect patterns. The sprites are
## drawn in near-white so the tribe colour is applied by the unit itself via
## modulate. Only ever call this from _ready() of scenes (headless rule:
## Image/ImageTexture work with the dummy RenderingServer, but core logic
## tests must not depend on texture contents).

const W: int = 16
const H: int = 24

const C_HEAD: Color = Color(1.0, 1.0, 1.0)
const C_BODY: Color = Color(0.92, 0.92, 0.92)
const C_LIMB: Color = Color(0.78, 0.78, 0.78)

## Casters get the "cast" animation (see CLAUDE.md par. 3).
const CASTER_KINDS: Array[StringName] = [&"shaman", &"preacher"]


## Builds the SpriteFrames (idle/walk/attack, plus cast for casters) for a
## unit kind. All current kinds share the same humanoid silhouette.
static func make_frames(unit_kind: StringName) -> SpriteFrames:
	var frames: SpriteFrames = SpriteFrames.new()
	frames.remove_animation("default")
	_add_animation(frames, &"idle", [_frame_idle(0), _frame_idle(1)], 2.0)
	_add_animation(frames, &"walk",
		[_frame_walk_a(), _frame_stand(), _frame_walk_b(), _frame_stand()], 8.0)
	_add_animation(frames, &"attack", [_frame_stand(), _frame_attack()], 6.0)
	if unit_kind in CASTER_KINDS:
		_add_animation(frames, &"cast", [_frame_stand(), _frame_cast()], 4.0)
	return frames


static func _add_animation(frames: SpriteFrames, anim: StringName,
		images: Array[Image], fps: float) -> void:
	frames.add_animation(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, true)
	for img in images:
		frames.add_frame(anim, ImageTexture.create_from_image(img))


# --- Frame painters ------------------------------------------------------------

static func _new_image() -> Image:
	return Image.create_empty(W, H, false, Image.FORMAT_RGBA8)


static func _draw_head_torso(img: Image, bob: int) -> void:
	img.fill_rect(Rect2i(5, 1 + bob, 6, 6), C_HEAD)   # head
	img.fill_rect(Rect2i(4, 7 + bob, 8, 9), C_BODY)   # torso


static func _draw_arms_side(img: Image, bob: int) -> void:
	img.fill_rect(Rect2i(2, 8 + bob, 2, 6), C_LIMB)
	img.fill_rect(Rect2i(12, 8 + bob, 2, 6), C_LIMB)


static func _draw_legs_stand(img: Image) -> void:
	img.fill_rect(Rect2i(5, 16, 2, 8), C_LIMB)
	img.fill_rect(Rect2i(9, 16, 2, 8), C_LIMB)


static func _frame_stand() -> Image:
	var img: Image = _new_image()
	_draw_head_torso(img, 0)
	_draw_arms_side(img, 0)
	_draw_legs_stand(img)
	return img


static func _frame_idle(bob: int) -> Image:
	var img: Image = _new_image()
	_draw_head_torso(img, bob)
	_draw_arms_side(img, bob)
	_draw_legs_stand(img)
	return img


static func _frame_walk_a() -> Image:
	var img: Image = _new_image()
	_draw_head_torso(img, 0)
	_draw_arms_side(img, 0)
	img.fill_rect(Rect2i(3, 16, 3, 7), C_LIMB)    # left leg forward
	img.fill_rect(Rect2i(10, 17, 3, 6), C_LIMB)   # right leg back
	return img


static func _frame_walk_b() -> Image:
	var img: Image = _new_image()
	_draw_head_torso(img, 0)
	_draw_arms_side(img, 0)
	img.fill_rect(Rect2i(3, 17, 3, 6), C_LIMB)    # left leg back
	img.fill_rect(Rect2i(10, 16, 3, 7), C_LIMB)   # right leg forward
	return img


static func _frame_attack() -> Image:
	var img: Image = _new_image()
	_draw_head_torso(img, 0)
	img.fill_rect(Rect2i(2, 8, 2, 6), C_LIMB)     # left arm at side
	img.fill_rect(Rect2i(12, 6, 4, 3), C_LIMB)    # right arm thrust out
	_draw_legs_stand(img)
	return img


static func _frame_cast() -> Image:
	var img: Image = _new_image()
	_draw_head_torso(img, 0)
	img.fill_rect(Rect2i(2, 2, 2, 7), C_LIMB)     # both arms raised
	img.fill_rect(Rect2i(12, 2, 2, 7), C_LIMB)
	_draw_legs_stand(img)
	return img
