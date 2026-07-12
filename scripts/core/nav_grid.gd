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

## Phase 8.1 (Stufe A): when set, every unit-grid solidity change is mirrored to
## the off-main-thread PathWorker as a compact delta. NavGrid stays the single
## source of truth; the worker only holds a private clone. Null → fully
## synchronous (tests, headless, A/B fallback).
var path_worker: PathWorker = null

var _astar: AStarGrid2D = AStarGrid2D.new()
var _building_cells: Dictionary[Vector2i, bool] = {}  # cells blocked by buildings
## Second grid for wide vehicles (siege engine, phase 7f): a cell is passable
## only when at least one fully walkable 2x2 block contains it — 1-cell gaps
## and narrow ledges stay closed to vehicles. Derived from the unit grid on
## every update.
var _vehicle_astar: AStarGrid2D = AStarGrid2D.new()


func _init(p_terrain: TerrainData) -> void:
	terrain = p_terrain
	_astar.region = Rect2i(0, 0, terrain.size, terrain.size)
	_astar.cell_size = Vector2(TerrainData.CELL_SIZE, TerrainData.CELL_SIZE)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	_vehicle_astar.region = _astar.region
	_vehicle_astar.cell_size = _astar.cell_size
	_vehicle_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_vehicle_astar.update()
	update_region(Rect2i(0, 0, terrain.size, terrain.size))


# --- Cell <-> world conversion ------------------------------------------------

func world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(
		clampi(int(floor(pos.x / TerrainData.CELL_SIZE)), 0, terrain.size - 1),
		clampi(int(floor(pos.z / TerrainData.CELL_SIZE)), 0, terrain.size - 1))


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


## True when the cell is reserved by a building footprint (steep-but-empty
## cells are not "blocked" in this sense — they can be flattened).
func is_cell_blocked_by_building(cell: Vector2i) -> bool:
	return _building_cells.has(cell)


## Nearest walkable cell via outward ring search; (-1, -1) if none in range.
func nearest_walkable_cell(cell: Vector2i) -> Vector2i:
	cell = Vector2i(
		clampi(cell.x, 0, terrain.size - 1),
		clampi(cell.y, 0, terrain.size - 1))
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
	var r: Rect2i = rect.intersection(Rect2i(0, 0, terrain.size, terrain.size))
	var delta_cells: PackedInt32Array = PackedInt32Array()
	var delta_solids: PackedByteArray = PackedByteArray()
	for z in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			var cell: Vector2i = Vector2i(x, z)
			var solid: bool = _building_cells.has(cell) or not terrain.is_walkable(cell)
			_astar.set_point_solid(cell, solid)
			if path_worker != null:
				delta_cells.append(z * terrain.size + x)
				delta_solids.append(1 if solid else 0)
	_refresh_vehicle_region(r)
	# Mirror the unit-grid change to the worker AFTER the local grid is updated,
	# so the worker's clone converges to the same state (FIFO-ordered vs. later
	# path requests). The vehicle grid stays main-thread only (siege pathing is
	# synchronous and rare — not routed through the worker in Stufe A).
	if path_worker != null and delta_cells.size() > 0:
		path_worker.push_delta(delta_cells, delta_solids)


## Full unit-grid solidity snapshot (index = z * size + x, 1 = solid) used to
## seed a fresh PathWorker clone so it starts perfectly in sync.
func solid_snapshot() -> PackedByteArray:
	var snap: PackedByteArray = PackedByteArray()
	snap.resize(terrain.size * terrain.size)
	for z in range(terrain.size):
		for x in range(terrain.size):
			snap[z * terrain.size + x] = 1 if _astar.is_point_solid(Vector2i(x, z)) else 0
	return snap


# --- Vehicle navigation (siege engine, phase 7f) ----------------------------------

## A vehicle-sized unit (~1x2 m, rotating) fits on a cell when at least one
## 2x2 block of walkable cells contains it.
func is_cell_vehicle_walkable(cell: Vector2i) -> bool:
	return terrain.in_bounds(cell) and not _vehicle_astar.is_point_solid(cell)


## Recomputes vehicle passability from the unit grid. Grown by 1 because a
## cell's vehicle flag depends on its neighbours.
func _refresh_vehicle_region(rect: Rect2i) -> void:
	var r: Rect2i = rect.grow(1).intersection(Rect2i(0, 0, terrain.size, terrain.size))
	for z in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			var cell: Vector2i = Vector2i(x, z)
			_vehicle_astar.set_point_solid(cell, not _vehicle_passable(cell))


func _vehicle_passable(cell: Vector2i) -> bool:
	if not terrain.in_bounds(cell) or _astar.is_point_solid(cell):
		return false
	# Any of the four 2x2 blocks containing the cell fully walkable?
	for oz in range(-1, 1):
		for ox in range(-1, 1):
			if _block_walkable(cell + Vector2i(ox, oz)):
				return true
	return false


## Whether the 2x2 block with top-left `origin` is fully walkable.
func _block_walkable(origin: Vector2i) -> bool:
	for dz in range(2):
		for dx in range(2):
			var c: Vector2i = origin + Vector2i(dx, dz)
			if not terrain.in_bounds(c) or _astar.is_point_solid(c):
				return false
	return true


## find_path for vehicles: same contract, on the eroded vehicle grid. Start/
## target snap to the nearest VEHICLE-passable cell; empty when no wide-enough
## route exists (the engine then stays put).
func find_vehicle_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	var from_cell: Vector2i = _nearest_vehicle_cell(world_to_cell(from))
	var target_cell: Vector2i = world_to_cell(to)
	var to_cell: Vector2i = _nearest_vehicle_cell(target_cell)
	if from_cell.x < 0 or to_cell.x < 0:
		return result
	var id_path: Array[Vector2i] = _vehicle_astar.get_id_path(from_cell, to_cell)
	if id_path.is_empty():
		return result
	for cell in id_path:
		result.append(cell_to_world(cell))
	if to_cell == target_cell:
		result[result.size() - 1] = Vector3(to.x, terrain.get_height(to.x, to.z), to.z)
	return result


## Nearest vehicle-passable cell via outward ring search; (-1, -1) if none.
func _nearest_vehicle_cell(cell: Vector2i) -> Vector2i:
	cell = Vector2i(
		clampi(cell.x, 0, terrain.size - 1),
		clampi(cell.y, 0, terrain.size - 1))
	if not _vehicle_astar.is_point_solid(cell):
		return cell
	for radius in range(1, MAX_SNAP_RADIUS + 1):
		var best: Vector2i = Vector2i(-1, -1)
		var best_dist: float = INF
		for candidate in _ring_cells(cell, radius):
			if not terrain.in_bounds(candidate):
				continue
			if _vehicle_astar.is_point_solid(candidate):
				continue
			var d: float = Vector2(candidate - cell).length_squared()
			if d < best_dist:
				best_dist = d
				best = candidate
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


## Blocks/unblocks cells for a building footprint (persists across
## terrain-driven update_region calls).
func fill_solid_region(rect: Rect2i, solid: bool) -> void:
	var r: Rect2i = rect.intersection(Rect2i(0, 0, terrain.size, terrain.size))
	for z in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			var cell: Vector2i = Vector2i(x, z)
			if solid:
				_building_cells[cell] = true
			else:
				_building_cells.erase(cell)
	update_region(r)
