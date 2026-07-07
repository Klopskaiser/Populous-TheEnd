class_name Minimap extends Control

## Round, north-fixed minimap. The terrain is rendered once from TerrainData
## into an ImageTexture (height colour steps matching the terrain vertex
## colours, water dark) and refreshed partially on Events.terrain_deformed.
## An overlay in _draw() adds unit dots (tribe colour), building squares,
## tree dots and the camera marker; the overlay redraw is throttled (~0.2 s)
## and iterates the existing manager lists (never one object per unit per
## frame). Left click / drag moves the camera to the clicked spot.
##
## Coordinate mapping is exposed as static, headless-testable functions
## (world_to_map / map_to_world); pixels/points outside the inscribed circle
## are clipped so the map reads as round without a shader.

## Redraw interval for the moving overlay (dots + camera marker).
const OVERLAY_INTERVAL: float = 0.2

# Height colour steps — kept consistent with Terrain._color_for_height so the
# minimap matches the 3D terrain.
const SAND_TOP: float = TerrainData.SEA_LEVEL + 1.5
const ROCK_BOTTOM: float = TerrainData.SEA_LEVEL + 8.0
const COLOR_SAND: Color = Color(0.83, 0.74, 0.50)
const COLOR_GRASS: Color = Color(0.29, 0.55, 0.24)
const COLOR_ROCK: Color = Color(0.45, 0.44, 0.42)
const COLOR_WATER: Color = Color(0.12, 0.24, 0.42)
const COLOR_WATER_DEEP: Color = Color(0.07, 0.15, 0.30)

## Round island mask (default). Square maps (phase 7i) set this false so the
## corners — where players can start — are not clipped away.
var round_mask: bool = true

var _terrain_data: TerrainData = null
var _unit_manager: UnitManager = null
var _building_manager: BuildingManager = null
var _tree_manager: TreeManager = null
var _camera_rig: Node3D = null

var _texture: ImageTexture = null
var _image: Image = null
var _overlay_timer: float = 0.0
var _dragging: bool = false


func setup(p_terrain_data: TerrainData, p_unit_manager: UnitManager,
		p_building_manager: BuildingManager, p_tree_manager: TreeManager,
		p_camera_rig: Node3D, p_round_mask: bool = true) -> void:
	_terrain_data = p_terrain_data
	round_mask = p_round_mask
	_unit_manager = p_unit_manager
	_building_manager = p_building_manager
	_tree_manager = p_tree_manager
	_camera_rig = p_camera_rig
	_build_terrain_image()
	var events: Node = get_node_or_null("/root/Events")
	if events != null and not events.terrain_deformed.is_connected(_on_terrain_deformed):
		events.terrain_deformed.connect(_on_terrain_deformed)
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(delta: float) -> void:
	_overlay_timer -= delta
	if _overlay_timer <= 0.0:
		_overlay_timer = OVERLAY_INTERVAL
		queue_redraw()


# --- Static mapping / colour (headless-testable) ----------------------------

## World XZ (metres, 0..world_size) -> map pixel (0..map_size), clamped.
static func world_to_map(world_xz: Vector2, map_size: float, world_size: float) -> Vector2:
	if world_size <= 0.0:
		return Vector2.ZERO
	return Vector2(
		clampf(world_xz.x / world_size, 0.0, 1.0) * map_size,
		clampf(world_xz.y / world_size, 0.0, 1.0) * map_size)


## Map pixel (0..map_size) -> world XZ (metres, 0..world_size).
static func map_to_world(map_xz: Vector2, map_size: float, world_size: float) -> Vector2:
	if map_size <= 0.0:
		return Vector2.ZERO
	return Vector2(
		clampf(map_xz.x / map_size, 0.0, 1.0) * world_size,
		clampf(map_xz.y / map_size, 0.0, 1.0) * world_size)


## Height -> minimap colour. Below the sea line is dark water; above it follows
## the same sand/grass/rock ramp as the terrain vertex colours.
static func height_to_color(h: float) -> Color:
	if h <= TerrainData.SEA_LEVEL:
		var d: float = clampf((TerrainData.SEA_LEVEL - h) / TerrainData.SEA_LEVEL, 0.0, 1.0)
		return COLOR_WATER.lerp(COLOR_WATER_DEEP, d)
	if h < SAND_TOP:
		return COLOR_SAND
	if h < ROCK_BOTTOM:
		var t: float = (h - SAND_TOP) / (ROCK_BOTTOM - SAND_TOP)
		return COLOR_SAND.lerp(COLOR_GRASS, clampf(t * 2.0, 0.0, 1.0))
	return COLOR_GRASS.lerp(COLOR_ROCK, clampf((h - ROCK_BOTTOM) / 6.0, 0.0, 1.0))


# --- Terrain image ----------------------------------------------------------

func _build_terrain_image() -> void:
	if _terrain_data == null:
		return
	var n: int = _terrain_data.size
	_image = Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for z in range(n):
		for x in range(n):
			_image.set_pixel(x, z, _cell_color(x, z))
	_texture = ImageTexture.create_from_image(_image)


## Colour for a cell, transparent outside the inscribed circle (round mask).
func _cell_color(x: int, z: int) -> Color:
	if round_mask:
		var n: float = float(_terrain_data.size)
		var half: float = n * 0.5
		var dx: float = float(x) + 0.5 - half
		var dz: float = float(z) + 0.5 - half
		if dx * dx + dz * dz > half * half:
			return Color(0, 0, 0, 0)
	return height_to_color(_terrain_data.cell_height(Vector2i(x, z)))


func _on_terrain_deformed(rect: Rect2i) -> void:
	if _image == null or _terrain_data == null:
		return
	var x0: int = clampi(rect.position.x, 0, _terrain_data.size - 1)
	var z0: int = clampi(rect.position.y, 0, _terrain_data.size - 1)
	var x1: int = clampi(rect.position.x + rect.size.x, 0, _terrain_data.size)
	var z1: int = clampi(rect.position.y + rect.size.y, 0, _terrain_data.size)
	for z in range(z0, z1):
		for x in range(x0, x1):
			_image.set_pixel(x, z, _cell_color(x, z))
	_texture.update(_image)
	queue_redraw()


# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	var s: float = minf(size.x, size.y)
	if _texture != null:
		draw_texture_rect(_texture, Rect2(Vector2.ZERO, Vector2(s, s)), false)
	# Gold rim — circle for round maps, square frame for the square maps.
	if round_mask:
		draw_arc(Vector2(s * 0.5, s * 0.5), s * 0.5 - 1.0, 0.0, TAU, 48,
			UiTheme.GOLD, 2.0, true)
	else:
		draw_rect(Rect2(Vector2.ONE, Vector2(s - 2.0, s - 2.0)), UiTheme.GOLD, false, 2.0)
	var world: float = float(_terrain_data.size)
	var center: Vector2 = Vector2(s * 0.5, s * 0.5)
	var radius: float = s * 0.5

	# Trees (dark green), then buildings (squares), then units (dots on top).
	if _tree_manager != null:
		for tree: TreeResource in _tree_manager.trees:
			_draw_point(_to_map(tree.position, s, world), center, radius,
				Color(0.15, 0.3, 0.12), 1.0)
	if _building_manager != null:
		for b: Building in _building_manager.buildings:
			var col: Color = _tribe_color(b.tribe_id)
			_draw_square(_to_map(b.center_world(), s, world), center, radius, col)
	if _unit_manager != null:
		for u: Unit in _unit_manager.units:
			if u.state == Unit.State.DEAD:
				continue
			_draw_point(_to_map(u.position, s, world), center, radius,
				_tribe_color(u.tribe_id), 2.0)

	# Camera view marker.
	if _camera_rig != null:
		var m: Vector2 = _to_map(_camera_rig.global_position, s, world)
		if _inside(m, center, radius):
			draw_circle(m, 4.0, Color(1, 1, 1, 0.9), false, 1.5)


func _to_map(world_pos: Vector3, s: float, world: float) -> Vector2:
	return world_to_map(Vector2(world_pos.x, world_pos.z), s, world)


func _inside(p: Vector2, center: Vector2, radius: float) -> bool:
	if not round_mask:
		return true   # square map: the whole s×s frame is valid
	return p.distance_to(center) <= radius


func _draw_point(p: Vector2, center: Vector2, radius: float, col: Color, sz: float) -> void:
	if not _inside(p, center, radius):
		return
	draw_rect(Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), col, true)


func _draw_square(p: Vector2, center: Vector2, radius: float, col: Color) -> void:
	if not _inside(p, center, radius):
		return
	draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), col, true)
	draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), Color(0, 0, 0, 0.6), false, 1.0)


func _tribe_color(tribe_id: int) -> Color:
	if tribe_id >= 0 and tribe_id < Unit.TRIBE_COLORS.size():
		return Unit.TRIBE_COLORS[tribe_id]
	return Color.WHITE


# --- Input (click / drag to move the camera) --------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.pressed:
				_move_camera_to(mb.position)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_move_camera_to((event as InputEventMouseMotion).position)
		accept_event()


func _move_camera_to(local_pos: Vector2) -> void:
	if _camera_rig == null:
		return
	var s: float = minf(size.x, size.y)
	var world: Vector2 = map_to_world(local_pos, s, float(_terrain_data.size))
	_camera_rig.global_position.x = world.x
	_camera_rig.global_position.z = world.y
	queue_redraw()
