class_name UnitManager extends Node

## Registry and spatial hash for all units (child of Main).
##
## The spatial hash (cell size ~4 m) enables cheap radius queries for target
## search and separation — never per-frame O(n^2) distance loops. The hash is
## refreshed in tick() (called from _physics_process; tests call it manually).
##
## Soft separation: units closer than SEPARATION_RADIUS push each other apart
## (each unit moves away from its neighbours, so pairs separate symmetrically).
## This prevents full overlap in normal play; scripted throws (Blast/Tornado,
## phase 5) use the THROWN state which is excluded here.

const HASH_CELL_SIZE: float = 4.0
## Minimum comfortable distance between unit centres (tight packing: group
## members stand just outside this radius).
const SEPARATION_RADIUS: float = 0.44
## Maximum push speed in metres per second.
const SEPARATION_SPEED: float = 1.6
## Separation processes at most this many units per tick (round-robin over
## slices; the push delta is scaled by the slice count) — a full pass every
## frame would dominate the frame time with thousands of units.
const SEPARATION_UNITS_PER_TICK: int = 600
## Max neighbour candidates examined per separated unit. Bounds the cost when
## thousands of units share one crowded hash bucket (the benchmark showed
## ~190 ms/tick without this cap when 4000 units converge on one point).
const SEPARATION_MAX_CHECKS: int = 20
## Max A* path computations per tick (mass move orders are spread over
## frames via the path queue instead of stalling one frame).
const PATHS_PER_TICK: int = 48

var terrain_data: TerrainData = null
var nav_grid: NavGrid = null
var tribes: Array[Tribe] = []
var tree_manager: TreeManager = null
var wood_pile_manager: WoodPileManager = null
## Central MultiMesh renderer (set by Main; null in headless tests).
var unit_renderer: UnitRenderer = null

var units: Array[Unit] = []
## Live projectiles (Fireball), ticked here after the units.
var projectiles: Array = []
var _hash: Dictionary[Vector2i, Array] = {}   # hash cell -> Array of Unit
var _path_requests: Array[Unit] = []
var _path_head: int = 0
var _separation_phase: int = 0


func setup(p_terrain_data: TerrainData, p_nav_grid: NavGrid,
		p_tribes: Array[Tribe] = [], p_tree_manager: TreeManager = null,
		p_wood_pile_manager: WoodPileManager = null) -> void:
	terrain_data = p_terrain_data
	nav_grid = p_nav_grid
	tribes = p_tribes
	tree_manager = p_tree_manager
	wood_pile_manager = p_wood_pile_manager


## In-game driver: ticks all units centrally (no per-unit _physics_process —
## the Node callback overhead alone would dominate with thousands of units),
## then runs the manager systems. Tests call unit.tick()/tick() directly.
func _physics_process(delta: float) -> void:
	# Iterate a snapshot: an expiring corpse deregisters itself mid-loop via the
	# corpse_expired signal (erasing from `units`), which would otherwise skip
	# elements. Dead units still tick — their tick runs the corpse decay.
	for unit in units.duplicate():
		if is_instance_valid(unit):
			unit.tick(delta)
	tick(delta)


func tick(delta: float) -> void:
	# Hash refresh, inlined (a function call per unit per tick adds up).
	for unit in units:
		var new_cell: Vector2i = Vector2i(
			int(floor(unit.position.x / HASH_CELL_SIZE)),
			int(floor(unit.position.z / HASH_CELL_SIZE)))
		if new_cell != unit._hash_cell:
			_move_hash_cell(unit, new_cell)
	_drain_path_queue()
	_apply_separation(delta)
	_tick_projectiles(delta)


# --- Projectiles -------------------------------------------------------------------

## Registers a projectile (e.g. a Fireball); it is ticked here until `done`
## flips, then freed. Added to the tree (visible) when the manager is in-game.
func register_projectile(projectile: Node3D) -> void:
	projectiles.append(projectile)
	if is_inside_tree():
		add_child(projectile)


func _tick_projectiles(delta: float) -> void:
	if projectiles.is_empty():
		return
	var kept: Array = []
	for p in projectiles:
		if not is_instance_valid(p):
			continue
		p.tick(delta)
		if p.done:
			p.queue_free()
		else:
			kept.append(p)
	projectiles = kept


# --- Path queue -------------------------------------------------------------------

## Registers a unit whose pending move target needs a path (see
## Unit._start_path_to). Deduplicated via the unit's _path_queued flag.
func request_path(unit: Unit) -> void:
	_path_requests.append(unit)


func _drain_path_queue() -> void:
	var budget: int = PATHS_PER_TICK
	while budget > 0 and _path_head < _path_requests.size():
		var unit: Unit = _path_requests[_path_head]
		_path_head += 1
		if not is_instance_valid(unit):
			continue
		unit._resolve_pending_path()
		budget -= 1
	if _path_head >= _path_requests.size():
		_path_requests.clear()
		_path_head = 0


# --- Separation -----------------------------------------------------------------------

## Pushes overlapping units apart (soft, capped speed). Two scale guards:
## at most SEPARATION_UNITS_PER_TICK units are processed per tick (round-robin
## slices, push delta scaled by the slice count), and each unit examines at
## most SEPARATION_MAX_CHECKS neighbour candidates — so a mega-crowd on one
## spot cannot blow up the tick. Skips dead and thrown units; the target cell
## must stay walkable so nobody gets shoved into water.
func _apply_separation(delta: float) -> void:
	if units.is_empty():
		return
	var slices: int = maxi(1, int(ceil(float(units.size()) / float(SEPARATION_UNITS_PER_TICK))))
	if _separation_phase >= slices:
		_separation_phase = 0
	var max_step: float = SEPARATION_SPEED * delta * float(slices)
	for index in range(_separation_phase, units.size(), slices):
		var unit: Unit = units[index]
		if unit.state == Unit.State.DEAD or unit.state == Unit.State.THROWN:
			continue
		var push: Vector2 = Vector2.ZERO
		var pos: Vector3 = unit.position
		var checks: int = SEPARATION_MAX_CHECKS
		var min_key: Vector2i = hash_key(pos - Vector3(SEPARATION_RADIUS, 0.0, SEPARATION_RADIUS))
		var max_key: Vector2i = hash_key(pos + Vector3(SEPARATION_RADIUS, 0.0, SEPARATION_RADIUS))
		for kz in range(min_key.y, max_key.y + 1):
			for kx in range(min_key.x, max_key.x + 1):
				var bucket: Array = _hash.get(Vector2i(kx, kz), [])
				for other: Unit in bucket:
					if other == unit or other.state == Unit.State.DEAD \
							or other.state == Unit.State.THROWN:
						continue
					checks -= 1
					var away: Vector2 = Vector2(pos.x - other.position.x, pos.z - other.position.z)
					var dist: float = away.length()
					if dist < SEPARATION_RADIUS:
						if dist < 0.001:
							# Full overlap: deterministic per-unit direction.
							var angle: float = float(unit.get_instance_id() % 628) * 0.01
							away = Vector2(cos(angle), sin(angle))
							dist = 0.001
						push += away / dist * (SEPARATION_RADIUS - dist)
					if checks <= 0:
						break
				if checks <= 0:
					break
			if checks <= 0:
				break
		if push == Vector2.ZERO:
			continue
		if push.length() > max_step:
			push = push.normalized() * max_step
		var nx: float = pos.x + push.x
		var nz: float = pos.z + push.y
		if nav_grid != null and not nav_grid.is_cell_walkable(
				nav_grid.world_to_cell(Vector3(nx, 0.0, nz))):
			continue
		unit.position.x = nx
		unit.position.z = nz
		if terrain_data != null:
			unit.position.y = terrain_data.get_height(nx, nz)
	_separation_phase = (_separation_phase + 1) % slices


# --- Registry -------------------------------------------------------------------

func register(unit: Unit) -> void:
	if unit in units:
		return
	units.append(unit)
	unit.died.connect(_on_unit_died)
	unit.corpse_expired.connect(_on_corpse_expired)
	_update_hash_cell(unit)
	if unit_renderer != null:
		unit_renderer.register_unit(unit)


func unregister(unit: Unit) -> void:
	units.erase(unit)
	if unit.died.is_connected(_on_unit_died):
		unit.died.disconnect(_on_unit_died)
	if unit.corpse_expired.is_connected(_on_corpse_expired):
		unit.corpse_expired.disconnect(_on_corpse_expired)
	if _hash.has(unit._hash_cell):
		_hash[unit._hash_cell].erase(unit)
	unit._hash_cell = Vector2i(2147483647, 2147483647)
	if unit_renderer != null:
		unit_renderer.unregister_unit(unit)


## Removes a unit from the live simulation (registry, spatial hash, renderer)
## WITHOUT touching its tribe membership — used when a brave enters a training
## building: it stays alive and counted as population until it graduates into a
## combat unit. (unregister already leaves the tribe list alone.)
func remove_from_world(unit: Unit) -> void:
	unregister(unit)


func _on_unit_died(unit: Unit) -> void:
	# The unit is NOT removed here: it stays registered (and rendered) as a
	# lying corpse — combat, selection, separation and target scans all skip
	# DEAD units. Only the tribe loses it immediately (population drops).
	if unit.tribe != null:
		unit.tribe.remove_unit(unit)
	if is_inside_tree():
		var events: Node = get_node_or_null("/root/Events")
		if events != null:
			events.unit_died.emit(unit)


## Corpse finished fading: now actually remove and free the node. It is out of
## the registry, hash, renderer, tribe and (via _die) every combat slot.
func _on_corpse_expired(unit: Unit) -> void:
	unregister(unit)
	unit.queue_free()


# --- Spawning -------------------------------------------------------------------

func spawn_unit(scene: PackedScene, tribe_id: int, pos: Vector3) -> Unit:
	var unit: Unit = scene.instantiate() as Unit
	unit.tribe_id = tribe_id
	unit.terrain_data = terrain_data
	unit.nav_grid = nav_grid
	unit.path_service = self
	# Worker references — only Braves have these properties.
	unit.set("tree_manager", tree_manager)
	unit.set("wood_pile_manager", wood_pile_manager)
	unit.position = pos
	if terrain_data != null:
		unit.position.y = terrain_data.get_height(pos.x, pos.z)
	add_child(unit)
	register(unit)
	if tribe_id >= 0 and tribe_id < tribes.size():
		tribes[tribe_id].add_unit(unit)
	return unit


# --- Spatial hash ----------------------------------------------------------------

func hash_key(pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(pos.x / HASH_CELL_SIZE)),
		int(floor(pos.z / HASH_CELL_SIZE)))


func _update_hash_cell(unit: Unit) -> void:
	var new_cell: Vector2i = hash_key(unit.position)
	if new_cell != unit._hash_cell:
		_move_hash_cell(unit, new_cell)


func _move_hash_cell(unit: Unit, new_cell: Vector2i) -> void:
	if _hash.has(unit._hash_cell):
		_hash[unit._hash_cell].erase(unit)
	if not _hash.has(new_cell):
		_hash[new_cell] = []
	_hash[new_cell].append(unit)
	unit._hash_cell = new_cell


## All units within radius (XZ distance) around pos.
func get_units_in_radius(pos: Vector3, radius: float) -> Array[Unit]:
	var result: Array[Unit] = []
	var min_key: Vector2i = hash_key(pos - Vector3(radius, 0.0, radius))
	var max_key: Vector2i = hash_key(pos + Vector3(radius, 0.0, radius))
	var flat_pos: Vector2 = Vector2(pos.x, pos.z)
	for kz in range(min_key.y, max_key.y + 1):
		for kx in range(min_key.x, max_key.x + 1):
			var bucket: Array = _hash.get(Vector2i(kx, kz), [])
			for unit: Unit in bucket:
				var flat: Vector2 = Vector2(unit.position.x, unit.position.z)
				if flat.distance_to(flat_pos) <= radius:
					result.append(unit)
	return result


func get_units_of_tribe(tribe_id: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in units:
		if unit.tribe_id == tribe_id:
			result.append(unit)
	return result
