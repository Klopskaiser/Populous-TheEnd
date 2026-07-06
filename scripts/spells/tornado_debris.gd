class_name TornadoDebris extends Node3D

## A chunk of wood whirled up by the tornado: a wood pile (or a tree the twister
## uprooted — its model becomes a pile while it is lifted) spirals up the funnel
## like a unit, is flung out in an arc and, on landing, SLIDES to a stop (wood
## does not roll like a body). It then settles back into a real WoodPile with the
## same amount of wood. A too-small tree (a sapling, no wood) is whirled the same
## way but simply VANISHES on impact. Ticked via the UnitManager projectile list;
## the visual only exists in-tree (headless tests tick it without meshes).

const LIFT_TIME: float = 0.9        # seconds to spiral up to the tip
const CARRY_TIME: float = 0.5       # dragged along the tip before release
const TOP_HEIGHT: float = 6.0
const SPIN_SPEED: float = 7.0       # angular speed while carried (rad/s)
const SPIRAL_R0: float = 2.0        # starting spiral radius, narrows to the tip
const FLING_SPEED: float = 11.0     # horizontal release speed
const FLING_UP: float = 3.5
const GRAVITY: float = 18.0
## Ground friction that bleeds off the sliding speed after landing.
const SLIDE_FRICTION: float = 7.0
## Below this horizontal speed a slide comes to rest.
const SLIDE_STOP_SPEED: float = 0.8

enum Phase {LIFT, CARRY, FLING, SLIDE}

var done: bool = false
## Wood carried; > 0 settles into a pile on landing, 0 = a sapling that vanishes.
var wood: int = 0
var vanish: bool = false
var terrain_data: TerrainData = null
var wood_pile_manager: WoodPileManager = null
## The vortex it rides while airborne (may be freed — then it flings from here).
var vortex: Node3D = null

var _phase: Phase = Phase.LIFT
var _t: float = 0.0
var _angle: float = 0.0
var _vel: Vector3 = Vector3.ZERO
## Last known funnel centre (follows the vortex while it lives).
var _center_xz: Vector3 = Vector3.ZERO


func setup(at: Vector3, p_wood: int, p_terrain_data: TerrainData,
		p_wood_pile_manager: WoodPileManager, p_vortex: Node3D, p_angle: float) -> void:
	position = at
	wood = p_wood
	vanish = p_wood <= 0
	terrain_data = p_terrain_data
	wood_pile_manager = p_wood_pile_manager
	vortex = p_vortex
	_angle = p_angle
	_center_xz = Vector3(at.x, 0.0, at.z)


func tick(delta: float) -> void:
	if done:
		return
	_t += delta
	match _phase:
		Phase.LIFT:
			_ride(delta, clampf(_t / LIFT_TIME, 0.0, 1.0))
			if _t >= LIFT_TIME:
				_phase = Phase.CARRY
				_t = 0.0
		Phase.CARRY:
			_ride(delta, 1.0)
			if _t >= CARRY_TIME:
				_start_fling()
		Phase.FLING:
			_vel.y -= GRAVITY * delta
			position += _vel * delta
			var ground: float = _ground(position)
			if position.y <= ground and _vel.y <= 0.0:
				position.y = ground
				_land()
		Phase.SLIDE:
			_tick_slide(delta)


## Spirals around the (moving) funnel centre, rising with `lift` (0..1).
func _ride(delta: float, lift: float) -> void:
	if vortex != null and is_instance_valid(vortex):
		_center_xz = Vector3(vortex.position.x, 0.0, vortex.position.z)
	_angle += SPIN_SPEED * delta
	var r: float = lerpf(SPIRAL_R0, 0.5, lift)
	var base_y: float = _ground(_center_xz)
	position = Vector3(
		_center_xz.x + cos(_angle) * r,
		base_y + lift * TOP_HEIGHT,
		_center_xz.z + sin(_angle) * r)


func _start_fling() -> void:
	var out: Vector3 = Vector3(position.x - _center_xz.x, 0.0, position.z - _center_xz.z)
	if out.length_squared() < 0.000001:
		out = Vector3(cos(_angle), 0.0, sin(_angle))
	out = out.normalized()
	_vel = out * FLING_SPEED + Vector3.UP * FLING_UP
	_phase = Phase.FLING
	_t = 0.0


## Touchdown after the arc: a sapling (or anything that lands in water) is gone;
## otherwise it keeps its horizontal momentum and slides to a stop.
func _land() -> void:
	if vanish or _in_water(position):
		done = true
		return
	_vel.y = 0.0
	if Vector2(_vel.x, _vel.z).length() <= SLIDE_STOP_SPEED:
		_settle()
		return
	_phase = Phase.SLIDE


func _tick_slide(delta: float) -> void:
	var horiz: Vector2 = Vector2(_vel.x, _vel.z)
	var speed: float = maxf(horiz.length() - SLIDE_FRICTION * delta, 0.0)
	var dir: Vector2 = horiz.normalized() if horiz.length() > 0.0001 else Vector2.ZERO
	_vel = Vector3(dir.x * speed, 0.0, dir.y * speed)
	position += _vel * delta
	_clamp_to_map()
	position.y = _ground(position)
	if _in_water(position):
		done = true   # slid into the sea: the wood is lost
		return
	if speed <= SLIDE_STOP_SPEED:
		_settle()


## Comes to rest: drop the carried wood as a pile at the resting spot.
func _settle() -> void:
	done = true
	if not vanish and wood > 0 and wood_pile_manager != null and not _in_water(position):
		wood_pile_manager.deposit(position, wood)


func _ground(pos: Vector3) -> float:
	return terrain_data.get_height(pos.x, pos.z) if terrain_data != null else 0.0


func _in_water(pos: Vector3) -> bool:
	return terrain_data != null and _ground(pos) <= TerrainData.SEA_LEVEL + 0.05


func _clamp_to_map() -> void:
	var limit: float = float(TerrainData.SIZE) * TerrainData.CELL_SIZE - 1.0
	position.x = clampf(position.x, 1.0, limit)
	position.z = clampf(position.z, 1.0, limit)


## Billboarded pile sprite (in-tree only). A sapling shows a single small log.
func _ready() -> void:
	var sprite: Sprite3D = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.pixel_size = WoodPile.SPRITE_PIXEL_SIZE
	sprite.texture = WoodPile._make_texture(maxi(wood, 1))
	sprite.position.y = float(WoodPile.SPRITE_H) * WoodPile.SPRITE_PIXEL_SIZE * 0.5
	add_child(sprite)
