class_name PlaceholderSprites

## Procedural placeholder sprite factory (no external asset files).
##
## Builds 16x24 pixel-art frames via Image fill_rect patterns. The sprites are
## drawn in near-white so the tribe colour is applied by the unit itself via
## modulate. Only ever call this from _ready() of scenes (headless rule:
## Image/ImageTexture work with the dummy RenderingServer, but core logic
## tests must not depend on texture contents).
##
## Directional views: every animation exists in eight variants named
## "<anim>_<view>" with view in front/back/right/left plus the four diagonals
## front_right/front_left/back_right/back_left (e.g. "walk_back_right").
## The Unit picks the view from its facing relative to the camera. To replace
## the placeholders with real art later, provide a SpriteFrames resource with
## the same animation names — nothing else has to change.
## Placeholder telltales: front = two eyes, back = hair patch, side = one eye
## (left is the mirrored right view); the diagonals are 3/4 profiles — the two
## front diagonals show both eyes plus a back-of-head hair sliver, the two back
## diagonals show the hair patch plus one near-cheek eye peeking under it.

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

## Kind-specific silhouette accents (drawn over the shared body). Everything is
## multiplied by the tribe colour in the renderer, so these rely on SHAPE and
## brightness contrast, not hue, to stay readable across tribes.
const C_SHIELD: Color = Color(0.6, 0.6, 0.64)    # warrior shield block
const C_BLADE: Color = Color(1.0, 1.0, 1.0)      # bright sword blade
const C_HELMET: Color = Color(0.4, 0.4, 0.46)    # dark cap (firewarrior)
const C_FIRE: Color = Color(1.0, 0.78, 0.3)      # fireball in the hand
const C_HOOD: Color = Color(0.7, 0.7, 0.72)      # preacher hood
const C_GOWN: Color = Color(0.86, 0.86, 0.88)    # preacher gown
const C_DRESS: Color = Color(0.99, 0.99, 1.0)    # shaman dress (brightest)
const C_MANE: Color = Color(0.3, 0.28, 0.33)     # shaman's long dark hair
const C_BELT: Color = Color(0.5, 0.44, 0.55)     # shaman belt/trim

## Casters get the "cast" animation (see CLAUDE.md par. 3).
const CASTER_KINDS: Array[StringName] = [&"shaman", &"preacher"]

## Order MUST match Unit.view_index return values (0 front .. 7 back_left).
const VIEWS: Array[StringName] = [
	&"front", &"back", &"right", &"left",
	&"front_right", &"front_left", &"back_right", &"back_left"]

## The three views drawn as the mirror of their right-side counterpart.
const MIRRORED_VIEWS: Array[StringName] = [&"left", &"front_left", &"back_left"]

## The two right-side diagonal paint views (left diagonals mirror these). Their
## accents are painted BEFORE the mirror so body and accents flip together.
const DIAGONAL_PAINT_VIEWS: Array[StringName] = [&"front_right", &"back_right"]


## One shared SpriteFrames per kind — building the frames is expensive and
## AnimatedSprite3D instances can share the resource (each keeps its own
## frame index). Without the cache, spawning hundreds of units rebuilt all
## images per unit and caused visible hitches.
static var _cache: Dictionary[StringName, SpriteFrames] = {}


## All animation bases a kind carries. "jump" is frame-driven by the hop
## visual; punch/kick/shove are the three melee strike animations (their cycle
## length matches Unit.ATTACK_COOLDOWN so fighting looks continuous); "throw"
## (firewarrior only) is the ranged fireball throw.
static func _anims_for(kind: StringName) -> Array[StringName]:
	var anims: Array[StringName] = [
		&"idle", &"walk", &"attack", &"jump", &"carry", &"carry_walk",
		&"punch", &"kick", &"shove", &"dead", &"sit", &"roll"]
	if kind in CASTER_KINDS:
		anims.append(&"cast")
	if kind == &"firewarrior":
		anims.append(&"throw")
	return anims


## Builds the SpriteFrames (idle/walk/attack/strikes, plus cast for casters),
## each in all eight directional views.
static func make_frames(unit_kind: StringName) -> SpriteFrames:
	if _cache.has(unit_kind):
		return _cache[unit_kind]
	var frames: SpriteFrames = SpriteFrames.new()
	frames.remove_animation("default")
	for anim in _anims_for(unit_kind):
		for view in VIEWS:
			var full_name: StringName = StringName("%s_%s" % [anim, view])
			_add_animation(frames, full_name, _build_frames(unit_kind, anim, view), _anim_fps(anim))
	_cache[unit_kind] = frames
	return frames


## Builds one texture atlas with ALL frames of the given kinds, for the
## MultiMesh-based UnitRenderer (one draw call for all units instead of one
## AnimatedSprite3D per unit). Returns:
##   texture:  ImageTexture with all frames in a grid
##   uvs:      PackedVector2Array — UV offset per global frame index
##   frame_uv: Vector2 — UV size of one frame
##   table:    kind -> anim base -> Array[8 views] of [start, count, fps]
##             (view order matches VIEWS: front, back, right, left, then the
##             four diagonals front_right/front_left/back_right/back_left)
static func build_atlas(kinds: Array[StringName]) -> Dictionary:
	var images: Array[Image] = []
	var table: Dictionary = {}
	for kind in kinds:
		var per_base: Dictionary = {}
		for anim in _anims_for(kind):
			var per_view: Array = []
			for view in VIEWS:
				var frame_images: Array[Image] = _build_frames(kind, anim, view)
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
		# Strike cycles are tuned to Unit.ATTACK_COOLDOWN (0.8 s): punch has 4
		# frames, kick/shove have 2 — all loop in exactly one cooldown, and each
		# strike restarts the timer, so the swing lands with the hit.
		&"punch":
			return 5.0
		&"kick", &"shove":
			return 2.5
		# Throw: 2 frames over Firewarrior.FIRE_COOLDOWN (1.5 s).
		&"throw":
			return 4.0 / 3.0
		&"roll":
			return 10.0
		&"cast":
			return 4.0
		_:
			return 2.0


## Frames for one animation in one view. The left view is the mirrored right
## view (real art can replace it with distinct frames later). Kind-specific
## silhouette accents (shield/sword, helmet/fireballs, hood/gown) are drawn on
## top of the shared body so each unit type is recognisable.
static func _build_frames(kind: StringName, anim: StringName, view: StringName) -> Array[Image]:
	# Left-side views are painted as their right-side twin, then mirrored below.
	var paint_view: StringName = view
	match view:
		&"left":
			paint_view = &"right"
		&"front_left":
			paint_view = &"front_right"
		&"back_left":
			paint_view = &"back_right"
	var images: Array[Image] = []
	## Upper-body vertical bob per frame (head/arms move; legs are fixed). The
	## kind accents (helmet/hood/fireballs) follow this so they move WITH the
	## body, e.g. during idle.
	var bobs: Array[int] = []
	match anim:
		&"walk":
			images = [
				_frame_walk(paint_view, 0), _frame_stand(paint_view, 0),
				_frame_walk(paint_view, 1), _frame_stand(paint_view, 0),
			]
			bobs = [0, 0, 0, 0]
		&"attack":
			images = [_frame_stand(paint_view, 0), _frame_attack(paint_view)]
			bobs = [0, 0]
		&"jump":
			images = [_frame_stand(paint_view, 0), _frame_jump(paint_view)]
			bobs = [0, 0]
		&"carry":
			images = [_frame_carry(paint_view, 0), _frame_carry(paint_view, 1)]
			bobs = [0, 1]
		&"carry_walk":
			images = [
				_frame_carry_walk(paint_view, 0), _frame_carry(paint_view, 0),
				_frame_carry_walk(paint_view, 1), _frame_carry(paint_view, 0),
			]
			bobs = [0, 0, 0, 0]
		&"punch":
			# Both fists strike one after the other (stand between jabs).
			images = [
				_frame_stand(paint_view, 0), _frame_punch(paint_view, 0),
				_frame_stand(paint_view, 0), _frame_punch(paint_view, 1),
			]
			bobs = [0, 0, 0, 0]
		&"kick":
			images = [_frame_stand(paint_view, 0), _frame_kick(paint_view)]
			bobs = [0, 0]
		&"shove":
			images = [_frame_shove(paint_view, 0), _frame_shove(paint_view, 1)]
			bobs = [0, 0]
		&"throw":
			# Frame 0 = just fired (arm forward, that hand EMPTY), frame 1 =
			# reloaded (fireball back above the raised hand). The anim restarts
			# on each shot, so the hand-fireball vanishes exactly at launch and
			# reappears mid-cooldown ("reloading", phase 5c).
			images = [_frame_throw(paint_view, 1), _frame_throw(paint_view, 0)]
			bobs = [0, 0]
		&"dead":
			images = [_frame_dead(paint_view)]
			bobs = [0]
		&"sit":
			images = [_frame_sit(paint_view, 0), _frame_sit(paint_view, 1)]
			bobs = [0, 1]
		&"roll":
			images = [
				_frame_roll(paint_view, 0), _frame_roll(paint_view, 1),
				_frame_roll(paint_view, 2), _frame_roll(paint_view, 3),
			]
			bobs = [0, 0, 0, 0]
		&"cast":
			images = [_frame_stand(paint_view, 0), _frame_cast(paint_view)]
			bobs = [0, 0]
		_:
			images = [_frame_stand(paint_view, 0), _frame_stand(paint_view, 1)]
			bobs = [0, 1]
	# No accents on the corpse, the sitting pose or the tumbling ball: the
	# shield/helmet/hood positions assume a standing body.
	var decorate: bool = not (anim in [&"dead", &"sit", &"roll"])
	if paint_view in DIAGONAL_PAINT_VIEWS:
		# Diagonals show BOTH accessories at both (asymmetric) hands, so mirroring
		# body and accents together is correct — decorate first, then flip.
		if decorate:
			for i in range(images.size()):
				_decorate(images[i], kind, paint_view, bobs[i])
		if view in MIRRORED_VIEWS:
			for img in images:
				img.flip_x()
	else:
		# Cardinal side views are NOT mirror images (a warrior shows the shield on
		# one side, the sword on the other), so mirror the plain body first, then
		# paint the accents in the REAL view.
		if view in MIRRORED_VIEWS:
			for img in images:
				img.flip_x()
		if decorate:
			for i in range(images.size()):
				_decorate(images[i], kind, view, bobs[i])
	return images


## Draws the kind-specific silhouette accents over the shared body, in the real
## view (after the mirror) and shifted by the frame's upper-body bob so they
## animate with the unit. Only the brave stays plain.
static func _decorate(img: Image, kind: StringName, view: StringName, bob: int) -> void:
	# view is a cardinal (front/back/right/left) or a right-side diagonal
	# (front_right/back_right); left diagonals are decorated in their right form
	# and mirrored afterwards by the caller.
	match kind:
		&"warrior":
			_decorate_warrior(img, view, bob)
		&"firewarrior":
			_decorate_firewarrior(img, view, bob)
		&"preacher":
			_decorate_preacher(img, view, bob)
		&"shaman":
			_decorate_shaman(img, view, bob)
		_:
			pass


## Front/back show both shield (left) and raised sword (right). The two side
## views differ: facing right shows the SWORD, facing left shows the SHIELD
## (the far-hand item is hidden behind the body).
static func _decorate_warrior(img: Image, view: StringName, bob: int) -> void:
	match view:
		&"right":
			# Sword held IN the near hand (x7-8), blade raised upward.
			img.fill_rect(Rect2i(7, 2 + bob, 2, 9), C_BLADE)     # blade up from the hand
			img.fill_rect(Rect2i(6, 10 + bob, 3, 1), C_HELMET)   # crossguard at the grip
		&"left":
			img.fill_rect(Rect2i(4, 9 + bob, 5, 6), C_SHIELD)    # shield in front
		&"front_right", &"back_right":
			# 3/4 view: sword in the near (right) hand at x11-12, shield at the
			# far (left) hand at x4 — both raised at the hands, not the profile.
			img.fill_rect(Rect2i(12, 1 + bob, 2, 13), C_BLADE)   # sword up from the near hand
			img.fill_rect(Rect2i(11, 8 + bob, 4, 1), C_HELMET)   # crossguard at the near grip
			img.fill_rect(Rect2i(3, 9 + bob, 4, 6), C_SHIELD)    # shield at the far hand
		_:
			img.fill_rect(Rect2i(2, 9 + bob, 4, 6), C_SHIELD)    # shield, left arm
			img.fill_rect(Rect2i(12, 1 + bob, 2, 13), C_BLADE)   # sword, right hand
			img.fill_rect(Rect2i(11, 8 + bob, 4, 1), C_HELMET)   # crossguard


## Dark helmet cap over the head + glowing fireballs held AT the hands (both bob).
static func _decorate_firewarrior(img: Image, view: StringName, bob: int) -> void:
	img.fill_rect(Rect2i(5, 1 + bob, 6, 2), C_HELMET)        # helmet cap on the head
	img.fill_rect(Rect2i(7, 0 + bob, 2, 1), C_HELMET)        # small crest
	match view:
		&"right":
			img.fill_rect(Rect2i(7, 11 + bob, 3, 3), C_FIRE)    # fireball in the near hand
		&"left":
			img.fill_rect(Rect2i(6, 11 + bob, 3, 3), C_FIRE)    # fireball in the near hand
		&"front_right", &"back_right":
			# 3/4 view shows BOTH hands: a fireball at each (far x4, near x11-12).
			img.fill_rect(Rect2i(2, 11 + bob, 3, 3), C_FIRE)    # far (left) hand
			img.fill_rect(Rect2i(11, 11 + bob, 3, 3), C_FIRE)   # near (right) hand
		_:
			img.fill_rect(Rect2i(1, 11 + bob, 3, 3), C_FIRE)    # fireball, left hand
			img.fill_rect(Rect2i(12, 11 + bob, 3, 3), C_FIRE)   # fireball, right hand


## Pointed wizard-style hood framing the head (bobs) + a long static gown over
## the legs. The brim sits ABOVE the eyes (y3) and the sides clear them, so the
## face stays visible. Symmetric, so the side views need no special handling.
static func _decorate_preacher(img: Image, _view: StringName, bob: int) -> void:
	img.fill_rect(Rect2i(7, 0 + bob, 2, 1), C_HOOD)      # hat tip
	img.fill_rect(Rect2i(6, 1 + bob, 4, 1), C_HOOD)      # cone
	img.fill_rect(Rect2i(5, 2 + bob, 6, 1), C_HOOD)      # brim, just above the eyes
	img.fill_rect(Rect2i(4, 3 + bob, 2, 3), C_HOOD)      # hood sides (cheeks), clear of eyes
	img.fill_rect(Rect2i(10, 3 + bob, 2, 3), C_HOOD)
	img.fill_rect(Rect2i(4, 14, 8, 10), C_GOWN)          # gown skirt over the legs


## The shaman is unmistakably female and distinct from every other unit: an
## hourglass figure (the shared torso is pinched at the waist), a long DARK
## mane (crown + strands past the shoulders, full mane from behind) framing
## the face, and the game's BRIGHTEST ankle-length dress flaring out from a
## dark belt into a wide triangle over the legs. Reads at any zoom via
## silhouette plus the strongest dark/bright contrast.
static func _decorate_shaman(img: Image, view: StringName, bob: int) -> void:
	# Waist pinch first (transparent erase of the torso sides), hair after so
	# the strands stay intact.
	var clear: Color = Color(0, 0, 0, 0)
	if view == &"right" or view == &"left":
		img.fill_rect(Rect2i(5, 10 + bob, 1, 3), clear)
		img.fill_rect(Rect2i(10, 10 + bob, 1, 3), clear)
	else:
		img.fill_rect(Rect2i(4, 10 + bob, 2, 3), clear)
		img.fill_rect(Rect2i(10, 10 + bob, 2, 3), clear)
	match view:
		&"back":
			img.fill_rect(Rect2i(4, 0 + bob, 8, 2), C_MANE)     # crown
			img.fill_rect(Rect2i(4, 2 + bob, 8, 10), C_MANE)    # full mane down the back
		&"right":
			img.fill_rect(Rect2i(4, 0 + bob, 8, 2), C_MANE)     # crown
			img.fill_rect(Rect2i(4, 2 + bob, 2, 10), C_MANE)    # mane behind (facing right)
		&"left":
			img.fill_rect(Rect2i(4, 0 + bob, 8, 2), C_MANE)
			img.fill_rect(Rect2i(10, 2 + bob, 2, 10), C_MANE)   # mane behind (facing left)
		_:
			img.fill_rect(Rect2i(4, 0 + bob, 8, 2), C_MANE)     # crown above the eyes
			img.fill_rect(Rect2i(3, 2 + bob, 2, 10), C_MANE)    # strands past the cheeks
			img.fill_rect(Rect2i(11, 2 + bob, 2, 10), C_MANE)
	# Dress: dark belt at the waist, bright skirt widening to the ankles.
	img.fill_rect(Rect2i(5, 13, 6, 1), C_BELT)
	for y in range(14, 24):
		var half: int = mini(3 + (y - 14) / 2, 7)
		img.fill_rect(Rect2i(8 - half, y, half * 2, 1), C_DRESS)


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
	_paint_face(img, view, 1 + bob)


## Draws the eyes / hair patch that tell a head's facing, relative to the head's
## top row (so the sitting pose can reuse it at a lower position). Left-side
## views never reach here — they are painted as their right-side twin and then
## mirrored. Diagonals: front_* = both eyes shifted toward the near side + a
## hair sliver on the far (back) side; back_* = hair patch + one near-cheek eye.
static func _paint_face(img: Image, view: StringName, top: int) -> void:
	match view:
		&"front":
			img.fill_rect(Rect2i(6, top + 2, 1, 1), C_EYE)
			img.fill_rect(Rect2i(9, top + 2, 1, 1), C_EYE)
		&"back":
			img.fill_rect(Rect2i(5, top, 6, 2), C_HAIR)
		&"right":
			img.fill_rect(Rect2i(9, top + 2, 1, 1), C_EYE)
		&"front_right":
			img.fill_rect(Rect2i(5, top, 2, 3), C_HAIR)      # back-left of the head
			img.fill_rect(Rect2i(7, top + 2, 1, 1), C_EYE)
			img.fill_rect(Rect2i(10, top + 2, 1, 1), C_EYE)  # near eye at the front edge
		&"back_right":
			img.fill_rect(Rect2i(5, top, 6, 2), C_HAIR)      # hair over the head
			img.fill_rect(Rect2i(10, top + 2, 1, 1), C_EYE)  # near cheek peeking


static func _draw_torso(img: Image, view: StringName, bob: int) -> void:
	if view == &"right":
		img.fill_rect(Rect2i(5, 7 + bob, 6, 9), C_BODY)  # narrower in profile
	elif view == &"front_right" or view == &"back_right":
		img.fill_rect(Rect2i(5, 7 + bob, 7, 9), C_BODY)  # 3/4 turn, between profile and frontal
	else:
		img.fill_rect(Rect2i(4, 7 + bob, 8, 9), C_BODY)


static func _draw_arms_side(img: Image, view: StringName, bob: int) -> void:
	if view == &"right":
		img.fill_rect(Rect2i(7, 8 + bob, 2, 6), C_LIMB)  # only the near arm visible
	elif view == &"front_right" or view == &"back_right":
		img.fill_rect(Rect2i(4, 8 + bob, 1, 6), C_LIMB)   # far arm, mostly hidden
		img.fill_rect(Rect2i(11, 8 + bob, 2, 6), C_LIMB)  # near arm forward of the body
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
	elif view == &"back" or view == &"back_right":
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


## One jab of the punch: phase 0 = left fist extended, phase 1 = right fist.
## A bright 2x2 fist block at the arm's end makes the strike readable.
static func _frame_punch(view: StringName, phase: int) -> Image:
	var img: Image = _new_image()
	_draw_torso(img, view, 0)
	_draw_head(img, view, 0)
	if view == &"right":
		if phase == 0:
			img.fill_rect(Rect2i(10, 8, 5, 2), C_LIMB)     # near arm jabs forward
			img.fill_rect(Rect2i(14, 7, 2, 3), C_HEAD)     # fist
		else:
			img.fill_rect(Rect2i(6, 9, 3, 2), C_LIMB)      # arm chambered back
			img.fill_rect(Rect2i(5, 8, 2, 3), C_HEAD)      # fist at the hip
	else:
		if phase == 0:
			img.fill_rect(Rect2i(1, 8, 4, 2), C_LIMB)      # left arm extended
			img.fill_rect(Rect2i(0, 7, 2, 3), C_HEAD)      # fist
			img.fill_rect(Rect2i(12, 8, 2, 6), C_LIMB)     # right arm at the side
		else:
			img.fill_rect(Rect2i(2, 8, 2, 6), C_LIMB)      # left arm at the side
			img.fill_rect(Rect2i(11, 8, 4, 2), C_LIMB)     # right arm extended
			img.fill_rect(Rect2i(14, 7, 2, 3), C_HEAD)     # fist
	_draw_legs_stand(img)
	return img


## Kick frame: one leg swings out horizontally, bright foot block at the end.
static func _frame_kick(view: StringName) -> Image:
	var img: Image = _new_image()
	_draw_torso(img, view, 0)
	_draw_head(img, view, 0)
	_draw_arms_side(img, view, 0)
	img.fill_rect(Rect2i(5, 16, 2, 8), C_LIMB)             # planted leg
	if view == &"right":
		img.fill_rect(Rect2i(9, 16, 6, 2), C_LIMB)         # kicking leg forward
		img.fill_rect(Rect2i(14, 15, 2, 3), C_HEAD)        # foot
	else:
		img.fill_rect(Rect2i(9, 16, 2, 4), C_LIMB)         # thigh down
		img.fill_rect(Rect2i(10, 18, 5, 2), C_LIMB)        # lower leg swings out
		img.fill_rect(Rect2i(14, 17, 2, 3), C_HEAD)        # foot
	return img


## Shove: both palms thrust forward together; phase 1 = fully extended.
static func _frame_shove(view: StringName, phase: int) -> Image:
	var img: Image = _new_image()
	_draw_torso(img, view, 0)
	_draw_head(img, view, 0)
	if view == &"right":
		var reach: int = 3 + phase * 3
		img.fill_rect(Rect2i(9, 9, reach, 2), C_LIMB)      # stacked arms forward
		img.fill_rect(Rect2i(8 + reach, 8, 2, 4), C_HEAD)  # palms
	else:
		# Facing the viewer: palms as bright blocks pushing out from the chest.
		img.fill_rect(Rect2i(2, 9, 2, 4 - phase), C_LIMB)  # arms shorten as they extend
		img.fill_rect(Rect2i(12, 9, 2, 4 - phase), C_LIMB)
		var size: int = 2 + phase
		img.fill_rect(Rect2i(4 - phase, 9, size, size), C_HEAD)   # left palm
		img.fill_rect(Rect2i(10, 9, size, size), C_HEAD)          # right palm
	_draw_legs_stand(img)
	return img


## Fireball throw (firewarrior): phase 0 = wind-up (fireball raised), phase 1 =
## release (arm thrust forward, that hand empty).
static func _frame_throw(view: StringName, phase: int) -> Image:
	var img: Image = _new_image()
	_draw_torso(img, view, 0)
	_draw_head(img, view, 0)
	if view == &"right":
		if phase == 0:
			img.fill_rect(Rect2i(9, 2, 2, 6), C_LIMB)      # arm wound up high
			img.fill_rect(Rect2i(8, 0, 3, 3), C_FIRE)      # fireball above the hand
		else:
			img.fill_rect(Rect2i(10, 7, 5, 2), C_LIMB)     # arm released forward
	else:
		img.fill_rect(Rect2i(2, 8, 2, 6), C_LIMB)          # off arm at the side
		if phase == 0:
			img.fill_rect(Rect2i(12, 2, 2, 7), C_LIMB)     # throwing arm up
			img.fill_rect(Rect2i(11, 0, 3, 3), C_FIRE)     # fireball above
		else:
			img.fill_rect(Rect2i(12, 6, 4, 2), C_LIMB)     # arm thrust forward
	_draw_legs_stand(img)
	return img


## Defeated unit lying on the ground — deliberately crumpled, not laid out
## straight: torso and hip are offset, the head is flopped to the side, one
## arm and one bent leg poke up, one leg is stretched out. Drawn in the bottom
## rows (the quad's origin is at the feet, so the corpse hugs the ground).
static func _frame_dead(_view: StringName) -> Image:
	var img: Image = _new_image()
	img.fill_rect(Rect2i(1, 20, 5, 3), C_BODY)       # torso
	img.fill_rect(Rect2i(6, 21, 4, 2), C_BODY)       # hip, offset (bent body)
	img.fill_rect(Rect2i(11, 19, 4, 4), C_HEAD)      # head flopped to the side
	img.fill_rect(Rect2i(12, 21, 1, 1), C_EYE)       # closed eye
	img.fill_rect(Rect2i(0, 18, 2, 3), C_LIMB)       # arm sticking out
	img.fill_rect(Rect2i(7, 18, 2, 3), C_LIMB)       # bent leg poking up
	img.fill_rect(Rect2i(9, 23, 5, 1), C_LIMB)       # outstretched leg
	return img


## Pacified unit sitting on the ground: lowered head and torso, legs folded in
## front — clearly distinct from standing at any zoom. Two frames breathe via
## the bob offset.
static func _frame_sit(view: StringName, bob: int) -> Image:
	var img: Image = _new_image()
	if view == &"right":
		img.fill_rect(Rect2i(5, 13 + bob, 6, 7), C_BODY)   # lowered torso
	elif view == &"front_right" or view == &"back_right":
		img.fill_rect(Rect2i(5, 13 + bob, 7, 7), C_BODY)   # 3/4 turn
	else:
		img.fill_rect(Rect2i(4, 13 + bob, 8, 7), C_BODY)
	img.fill_rect(Rect2i(5, 7 + bob, 6, 6), C_HEAD)        # head sits lower
	_paint_face(img, view, 7 + bob)
	img.fill_rect(Rect2i(3, 20, 10, 3), C_LIMB)            # folded legs
	return img


## Tumbling unit: a curled-up ball low to the ground; a bright head block and
## a dark limb block circle around the centre (4 phases) to sell the rotation.
static func _frame_roll(_view: StringName, phase: int) -> Image:
	var img: Image = _new_image()
	var cx: int = 8
	var cy: int = 18
	img.fill_rect(Rect2i(4, 14, 8, 8), C_BODY)   # curled body ball
	var offs: Array[Vector2i] = [
		Vector2i(0, -4), Vector2i(4, 0), Vector2i(0, 4), Vector2i(-4, 0)]
	var head_off: Vector2i = offs[phase % 4]
	var limb_off: Vector2i = offs[(phase + 2) % 4]
	img.fill_rect(Rect2i(cx - 2 + head_off.x, cy - 2 + head_off.y, 4, 4), C_HEAD)
	img.fill_rect(Rect2i(cx - 1 + limb_off.x, cy - 1 + limb_off.y, 3, 3), C_LIMB)
	return img


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
