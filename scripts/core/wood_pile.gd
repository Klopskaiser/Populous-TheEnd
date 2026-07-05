class_name WoodPile extends Node3D

## Wood pile lying on the ground (there is no wood storage building): braves
## drop chopped wood here, construction sites absorb nearby piles. Holds up to
## MAX_AMOUNT wood; empty piles are removed by the WoodPileManager.
##
## Visual: a billboarded pixel-art sprite (like the units) showing one log per
## wood unit, regenerated procedurally on amount changes — no asset files.

const MAX_AMOUNT: int = 5

const SPRITE_W: int = 16
const SPRITE_H: int = 16
const SPRITE_PIXEL_SIZE: float = 0.06

## Top-left pixel of each 5x3 log, bottom row of 3 + top row of 2.
const LOG_PIXELS: Array[Vector2i] = [
	Vector2i(0, 12), Vector2i(5, 12), Vector2i(10, 12),
	Vector2i(2, 9), Vector2i(7, 9),
]

const C_LOG: Color = Color(0.55, 0.36, 0.2)
const C_LOG_END: Color = Color(0.35, 0.22, 0.1)

var amount: int = 0

var _sprite: Sprite3D = null


func space_left() -> int:
	return MAX_AMOUNT - amount


func set_amount(value: int) -> void:
	amount = clampi(value, 0, MAX_AMOUNT)
	_update_visual()


func _ready() -> void:
	_update_visual()


func _update_visual() -> void:
	if not is_inside_tree():
		return
	if _sprite == null:
		_sprite = Sprite3D.new()
		_sprite.name = "Sprite"
		_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_sprite.shaded = false
		_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_sprite.pixel_size = SPRITE_PIXEL_SIZE
		_sprite.position.y = float(SPRITE_H) * SPRITE_PIXEL_SIZE * 0.5
		add_child(_sprite)
	_sprite.texture = _make_texture(amount)


## Pixel-art stack: one log (with darker cut ends) per wood unit.
static func _make_texture(p_amount: int) -> ImageTexture:
	var img: Image = Image.create(SPRITE_W, SPRITE_H, false, Image.FORMAT_RGBA8)
	for i in range(mini(p_amount, LOG_PIXELS.size())):
		var p: Vector2i = LOG_PIXELS[i]
		img.fill_rect(Rect2i(p.x, p.y, 5, 3), C_LOG)
		img.fill_rect(Rect2i(p.x, p.y, 1, 3), C_LOG_END)
		img.fill_rect(Rect2i(p.x + 4, p.y, 1, 3), C_LOG_END)
	return ImageTexture.create_from_image(img)
