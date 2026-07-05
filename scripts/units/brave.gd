class_name Brave extends Unit

## Basic follower unit. Behaviour states on top of Unit:
## - GATHER: walk to a tree, chop on a timer, credit the wood to the tribe,
##   then continue with the nearest remaining tree.
## - PRAY:   walk to the reincarnation site; while nearby, is_praying() is true
##   and the tribe's mana tick gets the prayer bonus.
## - BUILD:  walk to a construction site and drive its build_progress.
## All logic runs in tick(delta) and works without the scene tree.

const GATHER_RANGE: float = 1.5     # metres to the tree
const CHOP_INTERVAL: float = 1.0    # seconds per chop
const CHOP_WOOD: int = 2            # wood per chop
const BUILD_RATE: float = 0.2       # build_progress per second per brave

## Injected by UnitManager.spawn_unit() (or directly by tests).
var tree_manager: TreeManager = null

var target_tree: TreeResource = null
var target_building: Building = null

var _chop_timer: float = CHOP_INTERVAL
## True while working in place (chopping/building/praying) — drives both
## is_praying() and the animation sub-state.
var _working: bool = false
## Last target the current path was planned for (replan when it changes).
var _seek_goal: Vector3 = Vector3.INF


func _init() -> void:
	max_health = 60
	health = 60
	speed = 4.0


func unit_kind() -> StringName:
	return &"brave"


func is_praying() -> bool:
	return state == State.PRAY and _working


# --- Orders --------------------------------------------------------------------

func order_gather(tree: TreeResource) -> void:
	target_tree = tree
	_begin_task(State.GATHER)


func order_build(building: Building) -> void:
	target_building = building
	_begin_task(State.BUILD)


func order_pray(site: Building) -> void:
	target_building = site
	_begin_task(State.PRAY)


func _begin_task(new_state: State) -> void:
	waypoint_queue.clear()
	patrol = false
	_clear_path()
	_seek_goal = Vector3.INF
	_chop_timer = CHOP_INTERVAL
	_set_working(false)
	_set_state(new_state)


# --- Tick ----------------------------------------------------------------------

func tick(delta: float) -> void:
	match state:
		State.GATHER:
			_tick_gather(delta)
		State.BUILD:
			_tick_build(delta)
		State.PRAY:
			_tick_pray(delta)
		_:
			super.tick(delta)


func _tick_gather(delta: float) -> void:
	if not _tree_valid(target_tree):
		target_tree = tree_manager.nearest_tree(position) if tree_manager != null else null
		_seek_goal = Vector3.INF
		if target_tree == null:
			_stop_task()
			return
	if not _seek(target_tree.position, GATHER_RANGE, delta):
		return
	_face_toward(target_tree.position)
	_chop_timer -= delta
	if _chop_timer <= 0.0:
		_chop_timer += CHOP_INTERVAL
		var got: int = target_tree.harvest(CHOP_WOOD)
		if got > 0 and tribe != null:
			tribe.add_wood(got)
		# A depleting harvest may free the tree — do not touch it afterwards;
		# the next tick re-targets via _tree_valid().


func _tick_build(delta: float) -> void:
	if not is_instance_valid(target_building) or not target_building.under_construction:
		_stop_task()
		return
	if not _seek(target_building.center_world(), target_building.interact_range(), delta):
		return
	_face_toward(target_building.center_world())
	target_building.add_build_progress(BUILD_RATE * delta)
	if not target_building.under_construction:
		_stop_task()


func _tick_pray(delta: float) -> void:
	if not is_instance_valid(target_building):
		_stop_task()
		return
	if not _seek(target_building.center_world(), ReincarnationSite.PRAY_RADIUS, delta):
		return
	_face_toward(target_building.center_world())
	# Praying itself is passive: Tribe.tick() counts is_praying() braves.


func _stop_task() -> void:
	target_tree = null
	target_building = null
	_set_working(false)
	_clear_path()
	_set_state(State.IDLE)


# --- Helpers ---------------------------------------------------------------------

func _tree_valid(tree: TreeResource) -> bool:
	return tree != null and is_instance_valid(tree) and tree.wood_remaining > 0


## Walks toward target_pos until within arrive_range (XZ). Returns true once
## in range (and switches to working); gives up via IDLE when unreachable.
func _seek(target_pos: Vector3, arrive_range: float, delta: float) -> bool:
	var flat: Vector2 = Vector2(position.x, position.z)
	var flat_target: Vector2 = Vector2(target_pos.x, target_pos.z)
	if flat.distance_to(flat_target) <= arrive_range:
		if not _working:
			_clear_path()
			_set_working(true)
		return true
	if _working:
		_set_working(false)
	if not _has_path() or _seek_goal.distance_to(target_pos) > 0.5:
		_seek_goal = target_pos
		if not _plan_path_to(target_pos):
			_stop_task()
			return false
	if _advance_path(delta):
		# Path exhausted but still out of range: target unreachable, give up.
		if Vector2(position.x, position.z).distance_to(flat_target) > arrive_range:
			_stop_task()
	return false


func _set_working(working: bool) -> void:
	if _working == working:
		return
	_working = working
	_update_animation()


func _face_toward(target_pos: Vector3) -> void:
	var dir: Vector3 = Vector3(target_pos.x - position.x, 0.0, target_pos.z - position.z)
	if dir.length_squared() > 0.000001:
		facing = dir.normalized()


## Sub-state animations: chopping/building use the attack frames, praying
## stands (idle), walking phases use walk.
func _anim_base() -> StringName:
	match state:
		State.GATHER, State.BUILD:
			return &"attack" if _working else &"walk"
		State.PRAY:
			return &"idle" if _working else &"walk"
		_:
			return super._anim_base()
