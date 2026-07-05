class_name SelectionManager extends Control

## Screen-space unit selection and movement orders (full-rect Control on a
## CanvasLayer above the 3D view).
##
## - Left click: select the nearest own unit within a pixel radius
##   (camera.unproject_position); click on empty ground deselects.
## - Left drag: box select via rect.has_point(unproject) + is_position_behind
##   guard. The drag rect is drawn in _draw().
## - Right click: raycast -> context command via TribeCommands: tree = gather,
##   own construction site = build, own reincarnation site = pray, otherwise
##   move (scattered formation offsets so units do not stack).
##   Shift+right-click appends a waypoint. Key P toggles patrol.
## - While the BuildMenu is in placement mode, all mouse input is ignored here.

const CLICK_RADIUS_PX: float = 24.0
const DRAG_THRESHOLD_PX: float = 6.0
const RAY_LENGTH: float = 1000.0

const BUILDING_MASK: int = 2   # building click bodies
const TERRAIN_MASK: int = 1

var player_tribe_id: int = 0
var selected: Array[Unit] = []
## Selected own building (mutually exclusive with unit selection). Right-click
## then sets its rally point.
var selected_building: Building = null
## Building currently under the mouse (drives its production-bar visibility).
var _hovered_building: Building = null

var _unit_manager: UnitManager = null
var _tribe_commands: TribeCommands = null
var _build_menu: BuildMenu = null
var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_current: Vector2 = Vector2.ZERO


func setup(p_unit_manager: UnitManager, p_tribe_commands: TribeCommands = null,
		p_build_menu: BuildMenu = null) -> void:
	_unit_manager = p_unit_manager
	_tribe_commands = p_tribe_commands
	_build_menu = p_build_menu


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # only draws; input via _unhandled_input


func _unhandled_input(event: InputEvent) -> void:
	if _build_menu != null and _build_menu.is_active():
		_dragging = false
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		# Clicks that START over the sidebar are ignored; a drag that started on
		# the map is still allowed to finish over the sidebar.
		if mb.pressed and Sidebar.is_mouse_over_ui():
			return
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
			if selected_building != null and is_instance_valid(selected_building):
				_set_rally(mb.position)
			else:
				_command_move(mb.position, mb.shift_pressed)
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		_update_hover(mm.position)
		if _dragging:
			_drag_current = mm.position
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
	# A building under the cursor takes priority: select it (own only).
	var hit: Dictionary = _raycast(screen_pos, BUILDING_MASK)
	if not hit.is_empty():
		var node: Node = hit.get("collider") as Node
		if node != null and node.has_meta("building"):
			var b: Building = node.get_meta("building") as Building
			if b != null and b.tribe_id == player_tribe_id:
				_select_building(b)
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


## Public selection setter (used by the sidebar's "select idle braves" button).
func select_units(units: Array[Unit]) -> void:
	_set_selection(units)


func _set_selection(units: Array[Unit]) -> void:
	_clear_selected_building()
	# Guard every method call with is_instance_valid: a selected unit may have
	# been freed meanwhile (e.g. a brave that graduated from a training building
	# via queue_free), and calling a method on a freed instance crashes.
	for unit in selected:
		if is_instance_valid(unit):
			unit.set_selected(false)
	var kept: Array[Unit] = []
	for unit in units:
		if is_instance_valid(unit) and unit.state != Unit.State.DEAD:
			kept.append(unit)
			unit.set_selected(true)
	selected = kept


## Selects an own building (clears any unit/building selection first).
func _select_building(building: Building) -> void:
	_set_selection([])
	selected_building = building
	building.set_selected(true)


func _clear_selected_building() -> void:
	if selected_building != null and is_instance_valid(selected_building):
		selected_building.set_selected(false)
	selected_building = null


## Sets the selected building's rally point to the clicked terrain position.
func _set_rally(screen_pos: Vector2) -> void:
	var hit: Dictionary = _raycast(screen_pos, TERRAIN_MASK)
	if hit.is_empty():
		return
	selected_building.rally_point = hit.position


## Tracks the building under the cursor so it can show its production bar on
## hover (in addition to when selected).
func _update_hover(screen_pos: Vector2) -> void:
	var building: Building = null
	if not Sidebar.is_mouse_over_ui():
		var hit: Dictionary = _raycast(screen_pos, BUILDING_MASK)
		if not hit.is_empty():
			var node: Node = hit.get("collider") as Node
			if node != null and node.has_meta("building"):
				building = node.get_meta("building") as Building
	if building == _hovered_building:
		return
	if _hovered_building != null and is_instance_valid(_hovered_building):
		_hovered_building.set_hovered(false)
	_hovered_building = building
	if building != null:
		building.set_hovered(true)


func _raycast(screen_pos: Vector2, mask: int) -> Dictionary:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	var space: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, from + dir * RAY_LENGTH)
	query.collision_mask = mask
	return space.intersect_ray(query)


## Drops freed or dead units from the selection. Uses an explicit loop with an
## is_instance_valid guard before any typed use — passing a freed instance to a
## typed lambda parameter would itself raise a script error.
func _prune_selection() -> void:
	var kept: Array[Unit] = []
	for u in selected:
		if is_instance_valid(u) and u.state != Unit.State.DEAD:
			kept.append(u)
	selected = kept


# --- Context commands (right-click) ---------------------------------------------------

func _command_move(screen_pos: Vector2, queue_up: bool) -> void:
	_prune_selection()
	if selected.is_empty():
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	# Right-click on an enemy unit = attack order (units have no physics body, so
	# this is a screen-space pick like _click_select, not a raycast).
	var enemy: Unit = _enemy_under_cursor(screen_pos, camera)
	if enemy != null and _tribe_commands != null:
		_tribe_commands.order_attack(selected, enemy)
		return
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	var space: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, from + dir * RAY_LENGTH)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return

	if _tribe_commands != null and _dispatch_context_command(hit):
		return

	var target: Vector3 = hit.position
	if _tribe_commands != null:
		_tribe_commands.order_move(selected, target, queue_up)
		return
	for i in range(selected.size()):
		selected[i].order_move(target + TribeCommands.formation_offset(i), queue_up)


## Nearest enemy (non-player) unit within the click radius of the cursor, or
## null. Screen-space pick (units have no collision bodies).
func _enemy_under_cursor(screen_pos: Vector2, camera: Camera3D) -> Unit:
	if _unit_manager == null:
		return null
	var best: Unit = null
	var best_dist: float = CLICK_RADIUS_PX
	for unit in _unit_manager.units:
		if unit.tribe_id == player_tribe_id or unit.state == Unit.State.DEAD:
			continue
		var world: Vector3 = unit.global_position + Vector3(0.0, 0.7, 0.0)
		if camera.is_position_behind(world):
			continue
		var dist: float = camera.unproject_position(world).distance_to(screen_pos)
		if dist < best_dist:
			best_dist = dist
			best = unit
	return best


## Tree -> gather, own construction site -> build, own reincarnation site ->
## pray. Returns false when the click should be a plain move order.
func _dispatch_context_command(hit: Dictionary) -> bool:
	var collider: Object = hit.get("collider")
	var node: Node = collider as Node
	if node == null:
		return false
	if node.has_meta("tree_resource"):
		var tree: TreeResource = node.get_meta("tree_resource") as TreeResource
		if tree != null and not tree.felled_flag:
			_tribe_commands.order_chop(selected, tree)
			return true
		return false
	if node.has_meta("building"):
		var building: Building = node.get_meta("building") as Building
		if building == null or building.tribe_id != player_tribe_id:
			return false
		if building.under_construction:
			_tribe_commands.order_build(selected, building)
			return true
		if building is ReincarnationSite:
			_tribe_commands.order_pray(selected, building)
			return true
		if building is TrainingBuilding:
			_tribe_commands.order_train(building, selected)
			return true
	return false
