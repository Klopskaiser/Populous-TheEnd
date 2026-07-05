class_name UnitManager extends Node

## Registry and spatial hash for all units (child of Main).
##
## The spatial hash (cell size ~4 m) enables cheap radius queries for target
## search and separation — never per-frame O(n^2) distance loops. The hash is
## refreshed in tick() (called from _physics_process; tests call it manually).

const HASH_CELL_SIZE: float = 4.0

var terrain_data: TerrainData = null
var nav_grid: NavGrid = null
var tribes: Array[Tribe] = []
var tree_manager: TreeManager = null

var units: Array[Unit] = []
var _hash: Dictionary[Vector2i, Array] = {}       # hash cell -> Array of Unit
var _unit_cells: Dictionary[Unit, Vector2i] = {}  # unit -> current hash cell


func setup(p_terrain_data: TerrainData, p_nav_grid: NavGrid,
		p_tribes: Array[Tribe] = [], p_tree_manager: TreeManager = null) -> void:
	terrain_data = p_terrain_data
	nav_grid = p_nav_grid
	tribes = p_tribes
	tree_manager = p_tree_manager


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(_delta: float) -> void:
	for unit in units:
		_update_hash_cell(unit)


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
	unit.set("tree_manager", tree_manager)  # only Braves have this property
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
