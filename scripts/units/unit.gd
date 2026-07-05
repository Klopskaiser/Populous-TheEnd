class_name Unit extends Node3D

## Base class for all units (Brave, Warrior, Firewarrior, Preacher, Shaman).
##
## No physics body: movement walks the NavGrid path via move_toward on the XZ
## plane, Y is snapped from TerrainData every tick. Core logic lives in
## tick(delta) (driven by the UnitManager) so tests can drive it manually
## with artificial deltas, outside the scene tree. Uses local `position`
## (units are direct children of UnitManager at the origin, so local == global
## and it also works outside the tree).
##
## Units have NO visual children: all units are drawn by the central
## UnitRenderer (one MultiMesh draw call). The unit only keeps its animation
## state (anim_base_name + anim_start_ms) and render cache fields.

## Later phases fill in the behaviour for GATHER/PRAY/BUILD/ATTACK/TRAIN/
## PANIC/CAST/THROWN.
enum State {IDLE, MOVE, GATHER, PRAY, BUILD, ATTACK, TRAIN, PANIC, CAST, THROWN, DEAD}

signal died(unit: Unit)
signal state_changed(unit: Unit, new_state: State)

const TRIBE_COLORS: Array[Color] = [
	Color(0.35, 0.55, 1.0),   # 0 = player (blue)
	Color(1.0, 0.3, 0.25),    # 1 = AI (red)
	Color(1.0, 0.9, 0.35),
	Color(0.4, 0.9, 0.45),
]

const ARRIVE_EPS: float = 0.05       # metres: waypoint counts as reached

var tribe_id: int = 0
## Owning tribe, injected by UnitManager.spawn_unit()/Tribe.add_unit().
var tribe: Tribe = null
var max_health: int = 100
var health: int = 100
var speed: float = 4.0
var state: State = State.IDLE
var waypoint_queue: Array[Vector3] = []
var patrol: bool = false
## Visual-only: the sprite bounces (used by braves flattening terrain).
var hop_visual: bool = false

## Movement direction on the XZ plane (kept when the unit stops); drives the
## choice of the four sprite views. Default: facing the camera side (south).
var facing: Vector3 = Vector3(0, 0, 1)

## Injected by UnitManager.spawn_unit() (or directly by tests).
var terrain_data: TerrainData = null
var nav_grid: NavGrid = null
## When set (in-game), order_move paths are computed via the manager's path
## queue (spread over frames) instead of synchronously — 500 simultaneous
## move orders would otherwise stall a frame with 500 A* runs. Tests leave
## this null and get the old synchronous behaviour.
var path_service: UnitManager = null

var selected: bool = false

## Animation state, consumed by the UnitRenderer: base name (idle/walk/...)
## and the start time for frame timing.
var anim_base_name: StringName = &"idle"
var anim_start_ms: int = 0

## Current spatial-hash cell, managed by the UnitManager (stored on the unit
## because a Dictionary lookup per unit per tick is measurably slower).
var _hash_cell: Vector2i = Vector2i(2147483647, 2147483647)

## Render slot bookkeeping, managed by the UnitRenderer.
var _render_index: int = -1
var _render_kind: StringName = &"unit"
var _render_pos: Vector3 = Vector3.INF
var _render_frame: int = -1

var _path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0
## Queued move target awaiting path computation (INF = none).
var _pending_target: Vector3 = Vector3.INF
var _path_queued: bool = false


## Silhouette key for PlaceholderSprites; overridden by subclasses.
func unit_kind() -> StringName:
	return &"unit"


# --- Core logic (testable without scene tree) ---------------------------------

func tick(delta: float) -> void:
	match state:
		State.MOVE:
			_tick_move(delta)
		_:
			pass


func _tick_move(delta: float) -> void:
	if _pending_target != Vector3.INF:
		return  # waiting for the path queue
	if _advance_path(delta):
		_on_path_finished()


## Walks one step along the current path (also used by Brave sub-states that
## are not State.MOVE). Returns true when the path is exhausted.
func _advance_path(delta: float) -> bool:
	if _path_index >= _path.size():
		return true
	var target: Vector3 = _path[_path_index]
	var flat_pos: Vector2 = Vector2(position.x, position.z)
	var flat_target: Vector2 = Vector2(target.x, target.z)
	var to_target: Vector2 = flat_target - flat_pos
	if to_target.length_squared() > 0.000001:
		facing = Vector3(to_target.x, 0.0, to_target.y).normalized()
	var next: Vector2 = flat_pos.move_toward(flat_target, speed * delta)
	position.x = next.x
	position.z = next.y
	_snap_to_ground()
	if next.distance_to(flat_target) <= ARRIVE_EPS:
		_path_index += 1
	return _path_index >= _path.size()


func _has_path() -> bool:
	return _path_index < _path.size()


func _clear_path() -> void:
	_path = PackedVector3Array()
	_path_index = 0


func _snap_to_ground() -> void:
	if terrain_data != null:
		position.y = terrain_data.get_height(position.x, position.z)


func _on_path_finished() -> void:
	if waypoint_queue.is_empty():
		_set_state(State.IDLE)
		return
	if patrol:
		# Rotate the queue: the reached waypoint goes to the back.
		waypoint_queue.append(waypoint_queue.pop_front())
		_start_path_to(waypoint_queue[0])
	else:
		waypoint_queue.pop_front()
		if waypoint_queue.is_empty():
			_set_state(State.IDLE)
		else:
			_start_path_to(waypoint_queue[0])


# --- Orders --------------------------------------------------------------------

## Move order. queue_up appends the target as an additional waypoint
## (Shift+right-click), otherwise the current route is replaced.
func order_move(target: Vector3, queue_up: bool = false) -> void:
	if not queue_up:
		waypoint_queue.clear()
		waypoint_queue.append(target)
		_start_path_to(target)
		return
	waypoint_queue.append(target)
	if state != State.MOVE:
		_start_path_to(waypoint_queue[0])


func _start_path_to(target: Vector3) -> void:
	if path_service != null:
		# Defer to the manager's path queue (spread over frames).
		_pending_target = target
		_clear_path()
		if not _path_queued:
			_path_queued = true
			path_service.request_path(self)
		_set_state(State.MOVE)
		return
	if not _plan_path_to(target):
		# Unreachable: drop the waypoint and stop.
		if not waypoint_queue.is_empty():
			waypoint_queue.pop_front()
		_set_state(State.IDLE)
		return
	_set_state(State.MOVE)


## Called by the UnitManager when this unit's queued path request is due.
func _resolve_pending_path() -> void:
	_path_queued = false
	if _pending_target == Vector3.INF:
		return
	var target: Vector3 = _pending_target
	_pending_target = Vector3.INF
	if state != State.MOVE:
		return  # order was superseded while waiting
	if not _plan_path_to(target):
		if not waypoint_queue.is_empty():
			waypoint_queue.pop_front()
		_set_state(State.IDLE)


## Computes and stores a path without touching the state (Brave sub-states
## use this too). Returns false if the target is unreachable.
func _plan_path_to(target: Vector3) -> bool:
	var path: PackedVector3Array
	if nav_grid != null:
		path = nav_grid.find_path(position, target)
	else:
		path = PackedVector3Array([target])
	if path.is_empty():
		return false
	_path = path
	_path_index = 0
	return true


## Directly injects a path (used by tests and by order handling).
func set_path(path: PackedVector3Array) -> void:
	_pending_target = Vector3.INF  # cancel any queued request
	_path = path
	_path_index = 0
	if _path.is_empty():
		_set_state(State.IDLE)
	else:
		_set_state(State.MOVE)


## Not-yet-walked part of the current path (for route visualisation).
func get_remaining_path() -> PackedVector3Array:
	var points: PackedVector3Array = PackedVector3Array()
	if state != State.MOVE:
		return points
	for i in range(_path_index, _path.size()):
		points.append(_path[i])
	return points


## True while this unit generates the prayer mana bonus (Brave overrides).
func is_praying() -> bool:
	return false


# --- Damage (scaffold; combat comes in phase 4) --------------------------------

func take_damage(amount: int) -> void:
	if state == State.DEAD:
		return
	health -= amount
	if health <= 0:
		health = 0
		_set_state(State.DEAD)
		died.emit(self)


# --- State & visuals -------------------------------------------------------------

func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	state_changed.emit(self, new_state)
	_update_animation()


func _update_animation() -> void:
	_apply_animation(true)


## Which of the four sprite views matches a facing direction, given the
## camera's forward and right vectors. Returns an index into
## PlaceholderSprites.VIEWS (0 = front, 1 = back, 2 = right, 3 = left).
## Static + camera-free so it is headless-testable. Boundary (45 deg)
## prefers front/back.
static func view_index(p_facing: Vector3, cam_forward: Vector3, cam_right: Vector3) -> int:
	var flat_facing: Vector2 = Vector2(p_facing.x, p_facing.z)
	var flat_forward: Vector2 = Vector2(cam_forward.x, cam_forward.z)
	if flat_facing.length_squared() < 0.000001 or flat_forward.length_squared() < 0.000001:
		return 0
	flat_facing = flat_facing.normalized()
	flat_forward = flat_forward.normalized()
	var dot: float = flat_facing.dot(flat_forward)
	if dot >= 0.7071:
		return 1    # walking away from the camera -> back
	if dot <= -0.7071:
		return 0    # walking toward the camera -> front
	var flat_right: Vector2 = Vector2(cam_right.x, cam_right.z)
	return 2 if flat_facing.dot(flat_right) > 0.0 else 3


## StringName variant of view_index (kept for tests/readability).
static func view_suffix(p_facing: Vector3, cam_forward: Vector3, cam_right: Vector3) -> StringName:
	return PlaceholderSprites.VIEWS[view_index(p_facing, cam_forward, cam_right)]


## Animation base name for the current state; subclasses refine this for
## their sub-states (e.g. Brave chopping vs. walking while in GATHER).
func _anim_base() -> StringName:
	match state:
		State.MOVE, State.PANIC:
			return &"walk"
		State.ATTACK:
			return &"attack"
		State.CAST:
			return &"cast"
		_:
			return &"idle"


## Refreshes the animation state consumed by the UnitRenderer: the base name
## follows the state (_anim_base hook); the timer restarts on a base change
## or an explicit restart, so frame timing starts at frame 0.
func _apply_animation(restart: bool) -> void:
	var base: StringName = _anim_base()
	if base != anim_base_name:
		anim_base_name = base
		anim_start_ms = Time.get_ticks_msec()
	elif restart:
		anim_start_ms = Time.get_ticks_msec()


## Marks the unit as selected. The rings are rendered centrally by the
## SelectionRingRenderer (one MultiMesh) — per-unit ring nodes caused a
## visible hitch when box-selecting hundreds of units.
func set_selected(p_selected: bool) -> void:
	selected = p_selected
