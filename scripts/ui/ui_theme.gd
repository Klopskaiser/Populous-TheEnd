class_name UiTheme

## Procedural gold/brown look for the Populous-style sidebar: StyleBoxFlat
## builders (panel, buttons normal/hover/pressed/disabled) and generated
## pixel-art icons (ImageTexture, cached per key). No external asset files —
## real art can later replace the same icon keys. Only call the icon builders
## from _ready() contexts (headless rule: Image/ImageTexture work with the
## dummy RenderingServer, but core-logic tests must not depend on pixels).

# --- Palette ----------------------------------------------------------------

const GOLD: Color = Color(0.85, 0.68, 0.30)
const GOLD_BRIGHT: Color = Color(0.98, 0.85, 0.45)
const GOLD_DARK: Color = Color(0.52, 0.40, 0.16)
const BROWN_DARK: Color = Color(0.16, 0.11, 0.06)
const BROWN_MID: Color = Color(0.30, 0.21, 0.11)
const BROWN_LIGHT: Color = Color(0.44, 0.31, 0.16)
const TEXT: Color = Color(0.95, 0.88, 0.68)
const TEXT_DIM: Color = Color(0.55, 0.48, 0.34)

const ICON_SIZE: int = 24


# --- StyleBoxes -------------------------------------------------------------

static func panel_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = BROWN_DARK
	s.set_border_width_all(3)
	s.border_color = GOLD_DARK
	s.set_corner_radius_all(4)
	s.content_margin_left = 6.0
	s.content_margin_right = 6.0
	s.content_margin_top = 6.0
	s.content_margin_bottom = 6.0
	return s


static func inset_style() -> StyleBoxFlat:
	## Recessed dark slot (mana bar background, pip background, counters).
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = Color(0.09, 0.06, 0.03)
	s.set_border_width_all(1)
	s.border_color = GOLD_DARK
	s.set_corner_radius_all(2)
	return s


static func _button_box(bg: Color, border: Color, width: int = 2) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(width)
	s.border_color = border
	s.set_corner_radius_all(3)
	s.content_margin_left = 6.0
	s.content_margin_right = 6.0
	s.content_margin_top = 4.0
	s.content_margin_bottom = 4.0
	return s


## Applies the gold/brown button skin to any Button-derived control.
static func style_button(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal", _button_box(BROWN_MID, GOLD_DARK))
	btn.add_theme_stylebox_override("hover", _button_box(BROWN_LIGHT, GOLD))
	btn.add_theme_stylebox_override("pressed", _button_box(GOLD_DARK, GOLD_BRIGHT))
	btn.add_theme_stylebox_override("focus", _button_box(BROWN_MID, GOLD))
	btn.add_theme_stylebox_override("disabled", _button_box(Color(0.18, 0.14, 0.09), GOLD_DARK, 1))
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", GOLD_BRIGHT)
	btn.add_theme_color_override("font_pressed_color", BROWN_DARK)
	btn.add_theme_color_override("font_disabled_color", TEXT_DIM)


# --- Icons ------------------------------------------------------------------

static var _icon_cache: Dictionary[StringName, ImageTexture] = {}


## Cached pixel-art icon (ICON_SIZE x ICON_SIZE) for the given key. Unknown
## keys get a neutral placeholder square so the UI never breaks.
static func icon(key: StringName) -> ImageTexture:
	if _icon_cache.has(key):
		return _icon_cache[key]
	var img: Image = Image.create_empty(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	match key:
		&"house", &"hut":
			_draw_house(img)
		&"star":
			_draw_star(img)
		&"people":
			_draw_people(img)
		&"brave":
			_draw_person(img)
		&"preacher":
			_draw_preacher(img)
		&"crew":
			_draw_crew(img)
		&"warrior_camp", &"warrior":
			_draw_sword(img)
		&"firewarrior_camp", &"fireball", &"firewarrior":
			_draw_flame(img)
		&"temple":
			_draw_temple(img)
		&"forester":
			_draw_seedling(img)
		&"workshop", &"siege":
			_draw_catapult(img)
		&"watchtower":
			_draw_watchtower(img)
		&"lightning":
			_draw_lightning(img)
		&"swarm":
			_draw_swarm(img)
		&"landbridge":
			_draw_landbridge(img)
		&"tornado":
			_draw_tornado(img)
		&"earthquake":
			_draw_earthquake(img)
		&"volcano":
			_draw_volcano(img)
		&"firestorm":
			_draw_firestorm(img)
		&"flatten":
			_draw_flatten(img)
		&"sink":
			_draw_sink(img)
		&"shaman":
			_draw_shaman(img)
		&"pause":
			_draw_pause(img)
		&"menu":
			_draw_menu(img)
		_:
			img.fill_rect(Rect2i(4, 4, ICON_SIZE - 8, ICON_SIZE - 8), GOLD_DARK)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_icon_cache[key] = tex
	return tex


# --- Icon painters ----------------------------------------------------------

const I_LIGHT: Color = Color(0.95, 0.88, 0.68)
const I_GOLD: Color = Color(0.90, 0.72, 0.30)
const I_DARK: Color = Color(0.30, 0.22, 0.12)


static func _disc(img: Image, cx: int, cy: int, r: int, col: Color) -> void:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if x < 0 or y < 0 or x >= ICON_SIZE or y >= ICON_SIZE:
				continue
			var dx: int = x - cx
			var dy: int = y - cy
			if dx * dx + dy * dy <= r * r:
				img.set_pixel(x, y, col)


static func _rect(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
	img.fill_rect(Rect2i(x, y, w, h), col)


static func _draw_house(img: Image) -> void:
	# Roof (triangle-ish) + body + door.
	for i in range(7):
		var w: int = 4 + i * 2
		_rect(img, 12 - w / 2, 4 + i, w, 1, I_GOLD)
	_rect(img, 5, 11, 14, 9, I_DARK)
	_rect(img, 6, 12, 12, 7, I_LIGHT)
	_rect(img, 10, 14, 4, 5, I_DARK)  # door


static func _draw_star(img: Image) -> void:
	_disc(img, 12, 12, 3, I_GOLD)
	# Four spokes.
	_rect(img, 11, 3, 2, 18, I_GOLD)
	_rect(img, 3, 11, 18, 2, I_GOLD)
	# Diagonal accents.
	for i in range(5):
		img.set_pixel(6 + i, 6 + i, I_LIGHT)
		img.set_pixel(18 - i, 6 + i, I_LIGHT)


static func _draw_people(img: Image) -> void:
	# Two little figures.
	_disc(img, 8, 8, 3, I_LIGHT)
	_rect(img, 5, 12, 6, 8, I_GOLD)
	_disc(img, 16, 9, 3, I_LIGHT)
	_rect(img, 13, 13, 6, 7, I_GOLD)


static func _draw_person(img: Image) -> void:
	# A single figure (brave): head + body.
	_disc(img, 12, 7, 4, I_LIGHT)
	_rect(img, 8, 12, 8, 9, I_GOLD)
	_rect(img, 10, 21, 1, 2, I_DARK)
	_rect(img, 13, 21, 1, 2, I_DARK)


static func _draw_preacher(img: Image) -> void:
	# Robed figure with a raised staff (converter).
	_disc(img, 10, 7, 3, I_LIGHT)
	for i in range(9):                        # widening robe
		_rect(img, 10 - i / 2, 11 + i, 4 + i, 1, I_GOLD)
	_rect(img, 17, 3, 2, 17, I_DARK)          # staff
	_disc(img, 18, 3, 2, I_LIGHT)             # staff head


static func _draw_crew(img: Image) -> void:
	# Figure in a doorway (crew/occupancy tab).
	_rect(img, 4, 3, 16, 18, I_DARK)          # door frame
	_rect(img, 6, 5, 12, 16, Color(0.09, 0.06, 0.03))   # opening
	_disc(img, 12, 10, 3, I_LIGHT)            # head
	_rect(img, 9, 14, 7, 7, I_GOLD)           # body


static func _draw_sword(img: Image) -> void:
	_rect(img, 11, 3, 2, 14, I_LIGHT)   # blade
	_rect(img, 8, 16, 8, 2, I_GOLD)     # guard
	_rect(img, 11, 18, 2, 4, I_DARK)    # grip
	img.set_pixel(11, 3, I_LIGHT)
	img.set_pixel(12, 3, I_LIGHT)


static func _draw_flame(img: Image) -> void:
	_disc(img, 12, 15, 5, Color(0.9, 0.35, 0.1))
	_disc(img, 12, 13, 4, I_GOLD)
	_disc(img, 12, 12, 2, I_LIGHT)
	# Tip.
	_rect(img, 11, 5, 2, 6, Color(0.9, 0.35, 0.1))


static func _draw_temple(img: Image) -> void:
	# Pediment + columns + base.
	for i in range(5):
		var w: int = 6 + i * 3
		_rect(img, 12 - w / 2, 4 + i, w, 1, I_GOLD)
	_rect(img, 5, 9, 14, 2, I_LIGHT)
	_rect(img, 6, 11, 2, 8, I_LIGHT)
	_rect(img, 11, 11, 2, 8, I_LIGHT)
	_rect(img, 16, 11, 2, 8, I_LIGHT)
	_rect(img, 4, 19, 16, 2, I_GOLD)


static func _draw_watchtower(img: Image) -> void:
	# Tall slim shaft, a wider crenellated top and a dark doorway at the base.
	_rect(img, 9, 6, 6, 14, I_LIGHT)      # shaft
	_rect(img, 7, 4, 10, 3, I_GOLD)       # platform
	_rect(img, 7, 3, 2, 2, I_GOLD)        # merlons
	_rect(img, 11, 3, 2, 2, I_GOLD)
	_rect(img, 15, 3, 2, 2, I_GOLD)
	_rect(img, 10, 14, 4, 6, I_DARK)      # doorway


static func _draw_seedling(img: Image) -> void:
	# A little sapling: mound of earth, a stem and two leaves (forester).
	const C_LEAF: Color = Color(0.3, 0.65, 0.28)
	const C_STEM: Color = Color(0.5, 0.36, 0.2)
	_rect(img, 4, 18, 16, 3, I_DARK)          # earth
	_rect(img, 11, 8, 2, 10, C_STEM)          # stem
	_disc(img, 8, 10, 3, C_LEAF)              # left leaf
	_disc(img, 16, 9, 3, C_LEAF)              # right leaf
	_disc(img, 12, 6, 2, C_LEAF)              # tip


static func _draw_catapult(img: Image) -> void:
	# Siege workshop: a little catapult — base, two wheels, slanted throwing
	# arm with a basket and a stone leaving it.
	_rect(img, 5, 15, 14, 3, I_DARK)          # base frame
	_disc(img, 7, 19, 2, I_GOLD)              # wheels
	_disc(img, 17, 19, 2, I_GOLD)
	for i in range(9):                        # slanted arm
		img.set_pixel(8 + i, 14 - i, I_LIGHT)
		img.set_pixel(9 + i, 14 - i, I_LIGHT)
	_disc(img, 17, 5, 2, I_GOLD)              # basket
	_disc(img, 20, 3, 1, Color(0.9, 0.35, 0.1))   # stone flying off


static func _draw_lightning(img: Image) -> void:
	var pts: Array[Vector2i] = [
		Vector2i(14, 3), Vector2i(13, 6), Vector2i(12, 9), Vector2i(11, 11),
		Vector2i(14, 11), Vector2i(11, 15), Vector2i(9, 18), Vector2i(10, 14),
		Vector2i(7, 14), Vector2i(11, 8), Vector2i(12, 6)]
	for p in pts:
		_disc(img, p.x, p.y, 1, I_GOLD)
	img.set_pixel(13, 4, I_LIGHT)
	img.set_pixel(9, 17, I_LIGHT)


static func _draw_swarm(img: Image) -> void:
	var pts: Array[Vector2i] = [
		Vector2i(6, 6), Vector2i(11, 5), Vector2i(16, 8), Vector2i(8, 11),
		Vector2i(13, 12), Vector2i(18, 13), Vector2i(6, 16), Vector2i(11, 17),
		Vector2i(16, 18)]
	for p in pts:
		_disc(img, p.x, p.y, 1, I_GOLD)


static func _draw_landbridge(img: Image) -> void:
	# Water below, an arch of land rising across it.
	_rect(img, 2, 16, 20, 5, Color(0.15, 0.35, 0.6))
	for x in range(4, 20):
		var t: float = float(x - 12) / 8.0
		var h: int = 16 - int(round(6.0 * (1.0 - t * t)))
		_rect(img, x, h, 1, 17 - h, Color(0.35, 0.55, 0.24))
		img.set_pixel(x, h, I_GOLD)


static func _draw_tornado(img: Image) -> void:
	for i in range(9):
		var y: int = 4 + i * 2
		var w: int = maxi(2, 12 - i)
		_rect(img, 12 - w / 2, y, w, 1, I_LIGHT if i % 2 == 0 else I_GOLD)


static func _draw_earthquake(img: Image) -> void:
	# Ground slab split by a jagged crack.
	_rect(img, 3, 12, 18, 8, I_DARK)
	_rect(img, 3, 12, 18, 2, I_GOLD)
	var crack: Array[Vector2i] = [
		Vector2i(12, 12), Vector2i(11, 14), Vector2i(13, 15), Vector2i(11, 17),
		Vector2i(12, 19)]
	for p in crack:
		_rect(img, p.x - 1, p.y, 3, 2, I_LIGHT)
	# Debris flying above.
	_disc(img, 7, 8, 1, I_GOLD)
	_disc(img, 12, 6, 1, I_GOLD)
	_disc(img, 17, 8, 1, I_GOLD)


static func _draw_volcano(img: Image) -> void:
	# Mountain triangle with a glowing crater.
	for i in range(12):
		var w: int = 2 + i * 2
		_rect(img, 12 - w / 2, 8 + i, w, 1, I_DARK)
	_rect(img, 10, 7, 4, 2, Color(0.9, 0.35, 0.1))
	_rect(img, 11, 3, 2, 4, Color(0.9, 0.35, 0.1))
	img.set_pixel(9, 4, I_GOLD)
	img.set_pixel(14, 5, I_GOLD)


static func _draw_firestorm(img: Image) -> void:
	# Three small falling flames.
	for base in [Vector2i(6, 9), Vector2i(13, 5), Vector2i(17, 12)]:
		_disc(img, base.x, base.y + 4, 2, Color(0.9, 0.35, 0.1))
		_disc(img, base.x, base.y + 3, 1, I_GOLD)
		_rect(img, base.x, base.y - 1, 1, 3, I_LIGHT)   # falling trail
	_rect(img, 4, 19, 16, 2, I_DARK)


static func _draw_flatten(img: Image) -> void:
	# A level plateau with hard cliff edges over rough ground.
	_rect(img, 3, 16, 18, 4, I_DARK)
	_rect(img, 6, 10, 12, 6, I_GOLD)      # raised flat slab
	_rect(img, 6, 10, 12, 2, I_LIGHT)     # flat top highlight
	_rect(img, 6, 10, 1, 6, I_LIGHT)      # hard left edge
	_rect(img, 17, 10, 1, 6, I_LIGHT)     # hard right edge


static func _draw_sink(img: Image) -> void:
	# Land dipping into water with a down arrow.
	_rect(img, 3, 15, 18, 5, Color(0.15, 0.35, 0.6))
	_rect(img, 3, 12, 5, 3, Color(0.35, 0.55, 0.24))
	_rect(img, 16, 12, 5, 3, Color(0.35, 0.55, 0.24))
	_rect(img, 11, 4, 2, 8, I_GOLD)
	for i in range(4):
		_rect(img, 8 + i, 11 + i, 8 - i * 2, 1, I_GOLD)


static func _draw_shaman(img: Image) -> void:
	# Hooded portrait.
	_disc(img, 12, 13, 7, I_DARK)
	_disc(img, 12, 13, 5, I_LIGHT)
	# Hood peak.
	for i in range(5):
		_rect(img, 12 - i, 3 + i, 1 + i * 2, 1, I_GOLD)
	img.set_pixel(10, 13, I_DARK)
	img.set_pixel(14, 13, I_DARK)


static func _draw_pause(img: Image) -> void:
	_rect(img, 7, 5, 4, 14, I_LIGHT)
	_rect(img, 13, 5, 4, 14, I_LIGHT)


static func _draw_menu(img: Image) -> void:
	_rect(img, 5, 6, 14, 2, I_LIGHT)
	_rect(img, 5, 11, 14, 2, I_LIGHT)
	_rect(img, 5, 16, 14, 2, I_LIGHT)
