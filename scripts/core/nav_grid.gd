class_name NavGrid extends RefCounted

## Grid-based pathfinding on top of TerrainData, wrapping AStarGrid2D.
##
## No NavMesh: after a terrain deformation only the affected cells are
## re-evaluated (update_region), which makes the Landbridge spell trivial and
## keeps everything headless-testable. Building footprints are blocked via
## fill_solid_region() and survive terrain-driven region updates.

## Max ring distance when snapping an unwalkable target to the nearest
## walkable cell (covers e.g. a click into the middle of a lake).
const MAX_SNAP_RADIUS: int = 32

var terrain: TerrainData = null

var _astar: AStarGrid2D = AStarGrid2D.new()
var _building_cells: Dictionary[Vector2i, bool] = {}  # cells blocked by buildings


func _init(p_terrain: TerrainData) -> void:
	terrain = p_terrain
	_astar.region = Rect2i(0, 0, TerrainData.SIZE, TerrainData.SIZE)
	_astar.cell_size = Vector2(TerrainData.CELL_SIZE, TerrainData.CELL_SIZE)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	update_region(Rect2i(0, 0, TerrainData.SIZE, TerrainData.SIZE))


# --- Cell <-> world conversion ------------------------------------------------

func world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(
		clampi(int(floor(pos.x / TerrainData.CELL_SIZE)), 0, TerrainData.SIZE - 1),
		clampi(int(floor(pos.z / TerrainData.CELL_SIZE)), 0, TerrainData.SIZE - 1))


## World position of a cell centre, with Y from the terrain heightmap.
func cell_to_world(cell: Vector2i) -> Vector3:
	var wx: float = (float(cell.x) + 0.5) * TerrainData.CELL_SIZE
	var wz: float = (float(cell.y) + 0.5) * TerrainData.CELL_SIZE
	return Vector3(wx, terrain.get_height(wx, wz), wz)


# --- Pathfinding ---------------------------------------------------------------

## Finds a path between two world positions. Unwalkable start/target cells are
## snapped to the nearest walkable cell. Returns an empty array if no path
## exists (e.g. target on a separate landmass).
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	var from_cell: Vector2i = nearest_walkable_cell(world_to_cell(from))
	var target_cell: Vector2i = world_to_cell(to)
	var to_cell: Vector2i = nearest_walkable_cell(target_cell)
	if from_cell.x < 0 or to_cell.x < 0:
		return result
	var id_path: Array[Vector2i] = _astar.get_id_path(from_cell, to_cell)
	if id_path.is_empty():
		return result
	for cell in id_path:
		result.append(cell_to_world(cell))
	# If the exact click point lies inside the reached target cell, end the
	# path there instead of at the cell centre.
	if to_cell == target_cell:
		result[result.size() - 1] = Vector3(to.x, terrain.get_height(to.x, to.z), to.z)
	return result


func is_cell_walkable(cell: Vector2i) -> bool:
	return terrain.in_bounds(cell) and not _astar.is_point_solid(cell)


## Nearest walkable cell via outward ring search; (-1, -1) if none in range.
func nearest_walkable_cell(cell: Vector2i) -> Vector2i:
	cell = Vector2i(
		clampi(cell.x, 0, TerrainData.SIZE - 1),
		clampi(cell.y, 0, TerrainData.SIZE - 1))
	if not _astar.is_point_solid(cell):
		return cell
	for radius in range(1, MAX_SNAP_RADIUS + 1):
		var best: Vector2i = Vector2i(-1, -1)
		var best_dist: float = INF
		for candidate in _ring_cells(cell, radius):
			if not terrain.in_bounds(candidate):
				continue
			if _astar.is_point_solid(candidate):
				continue
			var d: float = Vector2(candidate - cell).length_squared()
			if d < best_dist:
				best_dist = d
				best = candidate
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


func _ring_cells(center: Vector2i, radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dx in range(-radius, radius + 1):
		cells.append(center + Vector2i(dx, -radius))
		cells.append(center + Vector2i(dx, radius))
	for dz in range(-radius + 1, radius):
		cells.append(center + Vector2i(-radius, dz))
		cells.append(center + Vector2i(radius, dz))
	return cells


# --- Walkability updates --------------------------------------------------------

## Re-reads walkability of all cells in the rect from TerrainData (call with the
## Rect2i returned by TerrainData.raise_area after a deformation).
func update_region(rect: Rect2i) -> void:
	var r: Rect2i = rect.intersection(Rect2i(0, 0, TerrainData.SIZE, TerrainData.SIZE))
	for z in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			var cell: Vector2i = Vector2i(x, z)
			var solid: bool = _building_cells.has(cell) or not terrain.is_walkable(cell)
			_astar.set_point_solid(cell, solid)


## Blocks/unblocks cells for a building footprint (persists across
## terrain-driven update_region calls).
func fill_solid_region(rect: Rect2i, solid: bool) -> void:
	var r: Rect2i = rect.intersection(Rect2i(0, 0, TerrainData.SIZE, TerrainData.SIZE))
	for z in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			var cell: Vector2i = Vector2i(x, z)
			if solid:
				_building_cells[cell] = true
			else:
				_building_cells.erase(cell)
	update_region(r)
