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

## How long a pile burns before it is consumed (fire spells / lava).
const BURN_TIME: float = 1.5

var amount: int = 0
## Depot stock piles are not right-click targets (the depot's own click body
## must win); they become clickable again once the depot is destroyed.
var clickable: bool = true
## Burn countdown (> 0 while alight); the WoodPileManager removes it at the end.
var _burn_time: float = 0.0

var _sprite: Sprite3D = null
var _click_body: StaticBody3D = null


func space_left() -> int:
	return MAX_AMOUNT - amount


# --- Burning (fire spells / lava) ---------------------------------------------

func is_burning() -> bool:
	return _burn_time > 0.0


## Sets the pile alight; it burns down and is then removed by the manager
## (the wood is lost). Re-igniting refreshes nothing.
func ignite() -> void:
	if is_burning():
		return
	_burn_time = BURN_TIME


## Advances the burn; returns true once the pile is spent. Driven by the
## WoodPileManager tick.
func burn_tick(delta: float) -> bool:
	if _burn_time <= 0.0:
		return false
	_burn_time -= delta
	if _sprite != null:
		# Flicker fiery while burning down, shrinking away.
		var flick: float = 0.6 + randf() * 0.4
		_sprite.modulate = Color(1.0, 0.5 * flick, 0.1 * flick)
		var t: float = clampf(_burn_time / BURN_TIME, 0.05, 1.0)
		_sprite.scale = Vector3.ONE * t
	return _burn_time <= 0.0


func set_amount(value: int) -> void:
	amount = clampi(value, 0, MAX_AMOUNT)
	_update_visual()


func _ready() -> void:
	_update_visual()
	if clickable:
		_create_click_body()


## Makes a (depot stock) pile right-click targetable again — used when the
## owning depot is destroyed and the wood keeps lying around as normal piles.
func make_clickable() -> void:
	clickable = true
	if _click_body == null and is_inside_tree():
		_create_click_body()


## StaticBody3D on layer 3 (value 4, like trees) so right-clicks can target
## the pile (order_pickup); no physics interaction (mask 0).
func _create_click_body() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "ClickBody"
	body.collision_layer = 4
	body.collision_mask = 0
	body.set_meta("wood_pile", self)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	shape.shape = box
	shape.position.y = 0.5
	body.add_child(shape)
	add_child(body)
	_click_body = body


func _update_visual() -> void:
	# The whole pile grows with its wood count. The sprite's feet sit at the
	# pile origin (offset == half height), so uniform scaling keeps the base on
	# the ground while the pile gets visibly bigger.
	var t: float = clampf(float(amount - 1) / float(MAX_AMOUNT - 1), 0.0, 1.0)
	scale = Vector3.ONE * lerpf(0.8, 1.45, t)
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
