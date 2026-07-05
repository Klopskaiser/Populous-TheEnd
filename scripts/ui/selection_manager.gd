class_name SelectionManager extends Control

## Screen-space unit selection and movement orders (full-rect Control on a
## CanvasLayer above the 3D view).
##
## - Left click: select the nearest own unit within a pixel radius
##   (camera.unproject_position); click on empty ground deselects.
## - Left drag: box select via rect.has_point(unproject) + is_position_behind
##   guard. The drag rect is drawn in _draw().
## - Right click: terrain raycast -> order_move for the selection (scattered
##   formation offsets so units do not stack). Shift+right-click appends a
##   waypoint. Key P toggles patrol for the selection.
##
## From phase 3 on, orders go through TribeCommands instead of calling the
## units directly.

const CLICK_RADIUS_PX: float = 24.0
const DRAG_THRESHOLD_PX: float = 6.0
const FORMATION_SPACING: float = 1.3
const RAY_LENGTH: float = 1000.0

var player_tribe_id: int = 0
var selected: Array[Unit] = []

var _unit_manager: UnitManager = null
var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_current: Vector2 = Vector2.ZERO


func setup(p_unit_manager: UnitManager) -> void:
	_unit_manager = p_unit_manager


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # only draws; input via _unhandled_input


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_start = mb.position
				_drag_current = mb.position
			elif _dragging:
				_dragging = false
				if _drag_start.distance_to(mb.position) < DRAG_THRESHOLD_PX:
					_click_select(mb.position)
				else:
					_box_select(_drag_rect(mb.position))
			queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_command_move(mb.position, mb.shift_pressed)
	elif event is InputEventMouseMotion and _dragging:
		_drag_current = (event as InputEventMouseMotion).position
		queue_redraw()
	elif event.is_action_pressed("toggle_patrol"):
		_prune_selection()
		for unit in selected:
			unit.patrol = not unit.patrol


func _draw() -> void:
	if not _dragging:
		return
	if _drag_start.distance_to(_drag_current) < DRAG_THRESHOLD_PX:
		return
	var rect: Rect2 = _drag_rect(_drag_current)
	draw_rect(rect, Color(0.4, 0.8, 1.0, 0.15), true)
	draw_rect(rect, Color(0.4, 0.8, 1.0, 0.9), false, 1.5)


func _drag_rect(end_pos: Vector2) -> Rect2:
	return Rect2(_drag_start, end_pos - _drag_start).abs()


# --- Selection --------------------------------------------------------------------

func _click_select(screen_pos: Vector2) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or _unit_manager == null:
		return
	var best: Unit = null
	var best_dist: float = CLICK_RADIUS_PX
	for unit in _unit_manager.get_units_of_tribe(player_tribe_id):
		if unit.state == Unit.State.DEAD:
			continue
		var world: Vector3 = unit.global_position + Vector3(0.0, 0.7, 0.0)
		if camera.is_position_behind(world):
			continue
		var dist: float = camera.unproject_position(world).distance_to(screen_pos)
		if dist < best_dist:
			best_dist = dist
			best = unit
	if best != null:
		_set_selection([best])
	else:
		_set_selection([])


func _box_select(rect: Rect2) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or _unit_manager == null:
		return
	var picked: Array[Unit] = []
	for unit in _unit_manager.get_units_of_tribe(player_tribe_id):
		if unit.state == Unit.State.DEAD:
			continue
		var world: Vector3 = unit.global_position + Vector3(0.0, 0.7, 0.0)
		if camera.is_position_behind(world):
			continue
		if rect.has_point(camera.unproject_position(world)):
			picked.append(unit)
	_set_selection(picked)


func _set_selection(units: Array[Unit]) -> void:
	_prune_selection()
	for unit in selected:
		unit.set_selected(false)
	selected = units
	for unit in selected:
		unit.set_selected(true)


func _prune_selection() -> void:
	selected = selected.filter(func(u: Unit) -> bool:
		return is_instance_valid(u) and u.state != Unit.State.DEAD)


# --- Movement orders ----------------------------------------------------------------

func _command_move(screen_pos: Vector2, queue_up: bool) -> void:
	_prune_selection()
	if selected.is_empty():
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	var space: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, from + dir * RAY_LENGTH)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return
	var target: Vector3 = hit.position
	for i in range(selected.size()):
		selected[i].order_move(target + _formation_offset(i), queue_up)


## Deterministic scatter around the click target (centre, then rings of 6,
## 12, 18, ... units) so units do not stack on one spot.
static func _formation_offset(index: int) -> Vector3:
	if index == 0:
		return Vector3.ZERO
	var ring: int = 1
	var ring_count: int = 6
	var i: int = index - 1
	while i >= ring_count:
		i -= ring_count
		ring += 1
		ring_count += 6
	var angle: float = TAU * float(i) / float(ring_count)
	var radius: float = FORMATION_SPACING * float(ring)
	return Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
