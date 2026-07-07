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

const DRAG_THRESHOLD_PX: float = 6.0
const RAY_LENGTH: float = 1000.0

## Approximate world size of the unit sprites (UnitRenderer quad: 16x24 px at
## 0.06 m/px). Picking tests the sprite's projected SCREEN RECT, so it stays
## reliable at every zoom level (a fixed pixel radius around one anchor point
## missed clicks on the head/feet when zoomed in).
const SPRITE_HEIGHT_M: float = 1.44
const SPRITE_ASPECT: float = 16.0 / 24.0
## Extra pixels around the sprite rect that still count as a hit.
const PICK_MARGIN_PX: float = 4.0
## Minimum on-screen pick size (px) so tiny far-away sprites stay clickable.
const MIN_PICK_SIZE_PX: float = 14.0

const BUILDING_MASK: int = 2   # building click bodies
const TERRAIN_MASK: int = 1

## True while the user is holding a (potential) box-select drag. The CameraRig
## suspends edge scrolling then: the camera panning mid-drag shifted the
## screen-space box off the units and produced empty/blinking selections.
static var drag_active: bool = false

## Empty-ground click deselects are suppressed this long after a box select:
## bounced/duplicated clicks right after a fast drag cleared fresh selections
## ("rings flash briefly, then everything is deselected").
const DESELECT_GRACE_S: float = 0.3

var player_tribe_id: int = 0
var selected: Array[Unit] = []
## Selected own building (mutually exclusive with unit selection). Right-click
## then sets its rally point.
var selected_building: Building = null
## Building currently under the mouse (drives its production-bar visibility).
var _hovered_building: Building = null

## Attack-move armed (key F): the NEXT right-click issues an aggressive move
## (combatants engage enemies on the way). Esc or any right-click clears it.
## Static (like drag_active) so the sidebar's Esc guard can check it.
static var attack_arm_active: bool = false

var _unit_manager: UnitManager = null
var _tribe_commands: TribeCommands = null
var _build_menu: BuildMenu = null
var _spell_targeting: SpellTargeting = null
var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_current: Vector2 = Vector2.ZERO
## Farthest the cursor got from the press point during this drag. A fast
## out-and-back drag can RELEASE near the start again — without this it would
## degrade into a click on empty ground and wipe the selection.
var _drag_max_dist: float = 0.0
var _last_box_select_ms: int = -100000


func setup(p_unit_manager: UnitManager, p_tribe_commands: TribeCommands = null,
		p_build_menu: BuildMenu = null, p_spell_targeting: SpellTargeting = null) -> void:
	_unit_manager = p_unit_manager
	_tribe_commands = p_tribe_commands
	_build_menu = p_build_menu
	_spell_targeting = p_spell_targeting


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # only draws; input via _unhandled_input


func _process(_delta: float) -> void:
	# Safety net: if the release event was swallowed elsewhere (e.g. dropped
	# over the sidebar panel), FINALIZE the drag from the last known cursor
	# position instead of dropping it — a completed box must still select.
	if _dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_dragging = false
		drag_active = false
		if _drag_max_dist >= DRAG_THRESHOLD_PX:
			_box_select(_drag_rect(_drag_current))
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _build_menu != null and _build_menu.is_active():
		_dragging = false
		drag_active = false
		return
	if _spell_targeting != null and _spell_targeting.is_active():
		_dragging = false
		drag_active = false
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		# Clicks that START over the sidebar are ignored; a drag that started on
		# the map is still allowed to finish over the sidebar.
		if mb.pressed and Sidebar.is_mouse_over_ui():
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# Double click on an own unit: select every unit of that kind
				# currently on screen (phase 7b).
				if mb.double_click:
					_dragging = false
					drag_active = false
					_double_click_select(mb.position)
					queue_redraw()
					return
				_dragging = true
				drag_active = true
				_drag_start = mb.position
				_drag_current = mb.position
				_drag_max_dist = 0.0
			elif _dragging:
				_dragging = false
				drag_active = false
				_drag_max_dist = maxf(_drag_max_dist, _drag_start.distance_to(mb.position))
				# Once a real box was drawn (max extent counts, not just the
				# release point), it stays a box — a fast out-and-back drag must
				# never degrade into a deselecting ground click.
				if _drag_max_dist < DRAG_THRESHOLD_PX:
					_click_select(mb.position)
				else:
					_box_select(_drag_rect(mb.position))
			queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if selected_building != null and is_instance_valid(selected_building):
				_set_rally(mb.position)
			else:
				var aggressive: bool = attack_arm_active
				attack_arm_active = false
				queue_redraw()
				_command_move(mb.position, mb.shift_pressed, aggressive)
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		_update_hover(mm.position)
		if attack_arm_active:
			queue_redraw()   # the armed cursor marker follows the mouse
		if _dragging:
			_drag_current = mm.position
			_drag_max_dist = maxf(_drag_max_dist, _drag_start.distance_to(mm.position))
			queue_redraw()
	elif event.is_action_pressed("toggle_patrol"):
		_prune_selection()
		for unit in selected:
			unit.patrol = not unit.patrol
	elif event.is_action_pressed("attack_move_arm"):
		# Key F arms the attack-move; the next right-click fires it.
		_prune_selection()
		if not selected.is_empty():
			attack_arm_active = true
			queue_redraw()
	elif event.is_action_pressed("ui_cancel") and attack_arm_active:
		attack_arm_active = false
		queue_redraw()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	# Armed attack-move: red crosshair marker + label at the cursor.
	if attack_arm_active:
		var mouse: Vector2 = get_global_mouse_position()
		var red: Color = Color(0.95, 0.25, 0.15, 0.9)
		draw_arc(mouse + Vector2(14, -14), 8.0, 0.0, TAU, 20, red, 2.0)
		draw_line(mouse + Vector2(14, -22), mouse + Vector2(14, -6), red, 2.0)
		draw_line(mouse + Vector2(6, -14), mouse + Vector2(22, -14), red, 2.0)
		draw_string(get_theme_default_font(), mouse + Vector2(26, -10),
			"Angriff", HORIZONTAL_ALIGNMENT_LEFT, -1,
			get_theme_default_font_size(), red)
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
	var best: Unit = _pick_unit_at(screen_pos, camera, player_tribe_id)
	if best != null:
		_set_selection([best])
		return
	# Ground click deselects — but not right after a box select: bounced or
	# duplicated clicks in that window wiped fresh selections.
	if Time.get_ticks_msec() - _last_box_select_ms > int(DESELECT_GRACE_S * 1000.0):
		_set_selection([])


func _box_select(rect: Rect2) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or _unit_manager == null:
		return
	var picked: Array[Unit] = []
	for unit in _unit_manager.get_units_of_tribe(player_tribe_id):
		if unit.state == Unit.State.DEAD:
			continue
		var sprite: Rect2 = _unit_screen_rect(unit, camera)
		if sprite.size.y > 0.0 and rect.intersects(sprite):
			# Crew in the box selects its catapult (deduplicated below).
			var target: Unit = _crew_to_engine(unit)
			if not (target in picked):
				picked.append(target)
	# An empty box is almost always a slipped drag (or the camera moved) —
	# keep the current selection; deselecting stays on click-on-ground.
	if picked.is_empty():
		return
	_set_selection(picked)
	_last_box_select_ms = Time.get_ticks_msec()


## Screen rect the unit's billboard sprite covers (feet->head projected,
## sprite aspect for the width, clamped to a minimum clickable size).
## Zero-height rect when the unit is behind the camera.
func _unit_screen_rect(unit: Unit, camera: Camera3D) -> Rect2:
	var feet: Vector3 = unit.global_position
	var head: Vector3 = feet + Vector3(0.0, SPRITE_HEIGHT_M, 0.0)
	if camera.is_position_behind(feet) or camera.is_position_behind(head):
		return Rect2()
	var p_feet: Vector2 = camera.unproject_position(feet)
	var p_head: Vector2 = camera.unproject_position(head)
	var height: float = maxf(absf(p_feet.y - p_head.y), MIN_PICK_SIZE_PX)
	var half_w: float = maxf(height * SPRITE_ASPECT, MIN_PICK_SIZE_PX) * 0.5
	var cx: float = (p_feet.x + p_head.x) * 0.5
	var top: float = minf(p_feet.y, p_head.y)
	return Rect2(cx - half_w, top, half_w * 2.0, height)


## Nearest unit of `tribe_id` (or any ENEMY when negative) whose sprite rect
## contains the point; ties resolved by distance to the rect centre.
## Siege crew is not individually selectable (7f): picking an OWN crew member
## yields its CATAPULT instead (enemy picks keep the crew — attacking it is
## the only way to fight the vehicle).
func _pick_unit_at(screen_pos: Vector2, camera: Camera3D, tribe_id: int) -> Unit:
	if _unit_manager == null:
		return null
	var best: Unit = null
	var best_dist: float = INF
	for unit in _unit_manager.units:
		if unit.state == Unit.State.DEAD:
			continue
		if tribe_id >= 0:
			if unit.tribe_id != tribe_id:
				continue
		elif unit.tribe_id == player_tribe_id or not unit.is_targetable():
			continue   # enemy pick: siege engines cannot be attacked directly
		var sprite: Rect2 = _unit_screen_rect(unit, camera)
		if sprite.size.y <= 0.0:
			continue
		if not sprite.grow(PICK_MARGIN_PX).has_point(screen_pos):
			continue
		var dist: float = sprite.get_center().distance_to(screen_pos)
		if dist < best_dist:
			best_dist = dist
			best = unit
	if best != null and tribe_id >= 0:
		best = _crew_to_engine(best)
	return best


## Own crew members map to their catapult (selection-wise the crew IS the
## vehicle); everything else passes through.
static func _crew_to_engine(unit: Unit) -> Unit:
	if unit.siege_engine != null and is_instance_valid(unit.siege_engine) \
			and unit.siege_engine.state != Unit.State.DEAD:
		return unit.siege_engine
	return unit


## Double click on an own unit: select all own units of the same kind whose
## sprite is currently on screen (phase 7b).
func _double_click_select(screen_pos: Vector2) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or _unit_manager == null:
		return
	var clicked: Unit = _pick_unit_at(screen_pos, camera, player_tribe_id)
	if clicked == null:
		return
	var candidates: Array[Unit] = filter_units_of_kind(
		_unit_manager.get_units_of_tribe(player_tribe_id), clicked.unit_kind())
	var viewport_rect: Rect2 = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var picked: Array[Unit] = []
	for unit in candidates:
		if unit.siege_engine != null:
			continue   # crew belongs to its catapult, not to the kind selection
		var sprite: Rect2 = _unit_screen_rect(unit, camera)
		if sprite.size.y > 0.0 and viewport_rect.intersects(sprite):
			picked.append(unit)
	if not picked.is_empty():
		_set_selection(picked)
		_last_box_select_ms = Time.get_ticks_msec()


## Pure kind filter for the double-click selection (headless-testable; the
## on-screen check happens in _double_click_select).
static func filter_units_of_kind(units: Array[Unit], kind: StringName) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in units:
		if is_instance_valid(unit) and unit.state != Unit.State.DEAD \
				and unit.unit_kind() == kind:
			result.append(unit)
	return result


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


## Drops freed, dead or no-longer-own units (e.g. converted away by an enemy
## preacher) from the selection. Uses an explicit loop with an is_instance_valid
## guard before any typed use — passing a freed instance to a typed lambda
## parameter would itself raise a script error.
func _prune_selection() -> void:
	var kept: Array[Unit] = []
	for u in selected:
		if is_instance_valid(u) and u.state != Unit.State.DEAD \
				and u.tribe_id == player_tribe_id:
			kept.append(u)
	selected = kept


# --- Context commands (right-click) ---------------------------------------------------

func _command_move(screen_pos: Vector2, queue_up: bool, aggressive: bool = false) -> void:
	_prune_selection()
	if selected.is_empty():
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	# Right-click on a crewable siege engine (own, or unmanned of any tribe):
	# assign the selected units as its crew (7f).
	if _tribe_commands != null and _try_crew_assignment(screen_pos, camera):
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

	# Right-click on an ENEMY building with siege engines selected: bombard it
	# (7f); everyone else escorts with an attack-move onto the plot.
	if _tribe_commands != null and _dispatch_enemy_building(hit):
		return

	# An armed attack-move is always a march order — context commands
	# (chop/build/pray/train) would be surprising with the attack cursor up.
	if not aggressive and _tribe_commands != null and _dispatch_context_command(hit):
		return

	var target: Vector3 = hit.position
	if _tribe_commands != null:
		_tribe_commands.order_move(selected, target, queue_up, aggressive)
		return
	for i in range(selected.size()):
		selected[i].order_move(target + TribeCommands.formation_offset(i), queue_up, aggressive)


## Enemy (non-player) unit under the cursor, or null. Same sprite-rect pick as
## the selection (units have no collision bodies).
func _enemy_under_cursor(screen_pos: Vector2, camera: Camera3D) -> Unit:
	return _pick_unit_at(screen_pos, camera, -1)


## Crew assignment (7f): a siege engine under the cursor that the player may
## man — his own, or an UNMANNED one of any tribe (battlefield takeover).
## Returns true when the order was issued (only crew-capable units join).
func _try_crew_assignment(screen_pos: Vector2, camera: Camera3D) -> bool:
	var crewable: Array[Unit] = []
	for u in selected:
		if u.can_crew_siege():
			crewable.append(u)
	if crewable.is_empty():
		return false
	var engine: Unit = null
	var best_dist: float = INF
	for unit in _unit_manager.units:
		if unit.state == Unit.State.DEAD or not (unit is SiegeEngine):
			continue
		if unit.tribe_id != player_tribe_id \
				and (unit as SiegeEngine).boarded_count() > 0:
			continue   # a manned enemy engine cannot be taken
		var sprite: Rect2 = _unit_screen_rect(unit, camera)
		if sprite.size.y <= 0.0 or not sprite.grow(PICK_MARGIN_PX).has_point(screen_pos):
			continue
		var dist: float = sprite.get_center().distance_to(screen_pos)
		if dist < best_dist:
			best_dist = dist
			engine = unit
	if engine == null:
		return false
	_tribe_commands.order_crew(crewable, engine)
	return true


## Enemy building under the cursor: the whole selection assaults it (phase 7g)
## — melee units storm the entrance, firewarriors bombard, siege engines lob
## shots, braves storm on this explicit order. Returns false when it is not an
## enemy building (the click stays a plain move / attack-move).
func _dispatch_enemy_building(hit: Dictionary) -> bool:
	var node: Node = hit.get("collider") as Node
	if node == null or not node.has_meta("building"):
		return false
	var building: Building = node.get_meta("building") as Building
	if building == null or building.tribe_id == player_tribe_id or building.health <= 0:
		return false
	_tribe_commands.order_attack_building(selected, building)
	return true


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
		if building.is_usable():
			if building is ReincarnationSite:
				_tribe_commands.order_pray(selected, building)
				return true
			if building is Forester:
				_tribe_commands.order_forester(selected, building)
				return true
			if building is Workshop:
				_tribe_commands.order_workshop(selected, building)
				return true
			if building is TrainingBuilding:
				_tribe_commands.order_train(building, selected)
				return true
		if building.health < building.max_health and building.health > 0:
			# Damaged building (huts at any damage, others once unusable):
			# workers repair it.
			_tribe_commands.order_repair(selected, building)
			return true
	return false
