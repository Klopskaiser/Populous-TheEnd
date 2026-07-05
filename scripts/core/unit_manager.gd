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
## Minimum comfortable distance between unit centres.
const SEPARATION_RADIUS: float = 0.55
## Maximum push speed in metres per second.
const SEPARATION_SPEED: float = 1.6

var terrain_data: TerrainData = null
var nav_grid: NavGrid = null
var tribes: Array[Tribe] = []
var tree_manager: TreeManager = null
var wood_pile_manager: WoodPileManager = null

var units: Array[Unit] = []
var _hash: Dictionary[Vector2i, Array] = {}       # hash cell -> Array of Unit
var _unit_cells: Dictionary[Unit, Vector2i] = {}  # unit -> current hash cell


func setup(p_terrain_data: TerrainData, p_nav_grid: NavGrid,
		p_tribes: Array[Tribe] = [], p_tree_manager: TreeManager = null,
		p_wood_pile_manager: WoodPileManager = null) -> void:
	terrain_data = p_terrain_data
	nav_grid = p_nav_grid
	tribes = p_tribes
	tree_manager = p_tree_manager
	wood_pile_manager = p_wood_pile_manager


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	for unit in units:
		_update_hash_cell(unit)
	_apply_separation(delta)


## Pushes overlapping units apart (soft, capped speed). Skips dead and thrown
## units; the target cell must stay walkable so nobody gets shoved into water.
func _apply_separation(delta: float) -> void:
	var max_step: float = SEPARATION_SPEED * delta
	for unit in units:
		if unit.state == Unit.State.DEAD or unit.state == Unit.State.THROWN:
			continue
		var push: Vector2 = Vector2.ZERO
		for other: Unit in get_units_in_radius(unit.position, SEPARATION_RADIUS):
			if other == unit or other.state == Unit.State.DEAD \
					or other.state == Unit.State.THROWN:
				continue
			var away: Vector2 = Vector2(
				unit.position.x - other.position.x,
				unit.position.z - other.position.z)
			var dist: float = away.length()
			if dist < 0.001:
				# Full overlap: deterministic per-unit direction.
				var angle: float = float(unit.get_instance_id() % 628) * 0.01
				away = Vector2(cos(angle), sin(angle))
				dist = 0.001
			push += away / dist * (SEPARATION_RADIUS - dist)
		if push == Vector2.ZERO:
			continue
		if push.length() > max_step:
			push = push.normalized() * max_step
		var nx: float = unit.position.x + push.x
		var nz: float = unit.position.z + push.y
		if nav_grid != null and not nav_grid.is_cell_walkable(
				nav_grid.world_to_cell(Vector3(nx, 0.0, nz))):
			continue
		unit.position.x = nx
		unit.position.z = nz
		if terrain_data != null:
			unit.position.y = terrain_data.get_height(nx, nz)


# --- Registry -------------------------------------------------------------------

func register(unit: Unit) -> void:
	if unit in units:
		return
	units.append(unit)
	unit.died.connect(_on_unit_died)
	_update_hash_cell(unit)


func unregister(unit: Unit) -> void:
	units.erase(unit)
	if unit.died.is_connected(_on_unit_died):
		unit.died.disconnect(_on_unit_died)
	var cell: Vector2i = _unit_cells.get(unit, Vector2i(-1, -1))
	if _hash.has(cell):
		_hash[cell].erase(unit)
	_unit_cells.erase(unit)


func _on_unit_died(unit: Unit) -> void:
	unregister(unit)
	if unit.tribe != null:
		unit.tribe.remove_unit(unit)
	if is_inside_tree():
		var events: Node = get_node_or_null("/root/Events")
		if events != null:
			events.unit_died.emit(unit)


# --- Spawning -------------------------------------------------------------------

func spawn_unit(scene: PackedScene, tribe_id: int, pos: Vector3) -> Unit:
	var unit: Unit = scene.instantiate() as Unit
	unit.tribe_id = tribe_id
	unit.terrain_data = terrain_data
	unit.nav_grid = nav_grid
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
	var old_cell: Vector2i = _unit_cells.get(unit, Vector2i(2147483647, 2147483647))
	if new_cell == old_cell:
		return
	if _hash.has(old_cell):
		_hash[old_cell].erase(unit)
	if not _hash.has(new_cell):
		_hash[new_cell] = []
	_hash[new_cell].append(unit)
	_unit_cells[unit] = new_cell


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
