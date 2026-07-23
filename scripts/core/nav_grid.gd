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
## Flat walkability mirror of the unit grid (index = z * size + x, 1 =
## walkable): the C2 movement kernels check their steps against this without
## an AStarGrid2D object call per unit. Maintained by update_region — the
## single solidity writer (fill_solid_region funnels through it).
var walkable_map: PackedByteArray = PackedByteArray()
## Second grid for wide vehicles (siege engine, phase 7f): a cell is passable
## only when at least one fully walkable 2x2 block contains it — 1-cell gaps
## and narrow ledges stay closed to vehicles. Derived from the unit grid on
## every update.
var _vehicle_astar: AStarGrid2D = AStarGrid2D.new()
## Cells occupied by PARKED (unmanned, stationary) vehicles — refcounted so
## overlapping footprints stack. Only the vehicle grid honours these, so OTHER
## vehicles path around a parked hulk instead of shoving through it (user
## report); pedestrians and the pedestrian-only PathWorker are unaffected.
var _vehicle_obstacles: Dictionary[Vector2i, int] = {}


func _init(p_terrain: TerrainData) -> void:
	terrain = p_terrain
	walkable_map.resize(terrain.size * terrain.size)
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
## exists (e.g. target on a separate landmass) — unless `allow_partial` is set
## (attack-move waves, phase 8.2): then the path ends at the closest REACHABLE
## cell toward the target instead of failing.
func find_path(from: Vector3, to: Vector3, allow_partial: bool = false) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	var from_cell: Vector2i = nearest_walkable_cell(world_to_cell(from))
	var target_cell: Vector2i = world_to_cell(to)
	var to_cell: Vector2i = nearest_walkable_cell(target_cell)
	if from_cell.x < 0 or to_cell.x < 0:
		return result
	var id_path: Array[Vector2i] = _astar.get_id_path(from_cell, to_cell, allow_partial)
	if id_path.is_empty():
		return result
	for cell in id_path:
		result.append(cell_to_world(cell))
	# If the exact click point lies inside the reached target cell, end the
	# path there instead of at the cell centre (a partial path may end
	# elsewhere — only rewrite when the target cell was actually reached).
	if to_cell == target_cell and id_path[id_path.size() - 1] == to_cell:
		result[result.size() - 1] = Vector3(to.x, terrain.get_height(to.x, to.z), to.z)
	return result


func is_cell_walkable(cell: Vector2i) -> bool:
	return terrain.in_bounds(cell) and not _astar.is_point_solid(cell)


# --- Islands (connected components) ----------------------------------------------

## Two world positions share an island when they are mutually reachable on
## foot — an O(1) reachability prefilter for target choosers (trees, piles,
## delivery buildings), so braves stop picking beeline-near but blocked
## targets below cliffs. Labels refresh lazily after walkability changes, at
## most once per ISLAND_REFRESH_MS (briefly stale labels self-heal).
const ISLAND_REFRESH_MS: int = 1000

var _islands: PackedInt32Array = PackedInt32Array()
var _islands_dirty: bool = true
var _islands_computed_ms: int = 0

## Monotonic walkability-change counter (bumped by every update_region).
## Consumers use it to invalidate cached reachability verdicts the moment the
## grid changes (e.g. TreeManager.best_tree's negative-path cache).
var change_version: int = 0

## Telemetry for the benchmarks (pattern: Unit.dbg_plan_*) — pure counters.
static var dbg_island_fills: int = 0
static var dbg_island_us: int = 0


func same_island(a: Vector3, b: Vector3) -> bool:
	var ia: int = island_at(nearest_walkable_cell(world_to_cell(a)))
	return ia >= 0 and ia == island_at(nearest_walkable_cell(world_to_cell(b)))


func island_at(cell: Vector2i) -> int:
	if cell.x < 0 or not terrain.in_bounds(cell):
		return -1
	_ensure_islands()
	return _islands[cell.y * terrain.size + cell.x]


## Flood-fill labelling over the walkable grid (4-connected — matching
## DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES, where a diagonal never connects cells
## that are not already 4-connected).
func _ensure_islands() -> void:
	if not _islands_dirty:
		return
	var now: int = Time.get_ticks_msec()
	if not _islands.is_empty() and now - _islands_computed_ms < ISLAND_REFRESH_MS:
		return
	_islands_dirty = false
	_islands_computed_ms = now
	var t0: int = Time.get_ticks_usec()
	dbg_island_fills += 1
	var size: int = terrain.size
	_islands.resize(size * size)
	_islands.fill(-1)
	var next_id: int = 0
	var queue: PackedInt32Array = PackedInt32Array()
	for start in range(size * size):
		if _islands[start] != -1 \
				or _astar.is_point_solid(Vector2i(start % size, start / size)):
			continue
		queue.resize(0)
		queue.push_back(start)
		_islands[start] = next_id
		var head: int = 0
		while head < queue.size():
			var idx: int = queue[head]
			head += 1
			var cz: int = idx / size
			for n in [idx - 1, idx + 1, idx - size, idx + size]:
				if n < 0 or n >= size * size or _islands[n] != -1:
					continue
				# Row wrap guard for the +-1 neighbours.
				if absi(n - idx) == 1 and n / size != cz:
					continue
				if _astar.is_point_solid(Vector2i(n % size, n / size)):
					continue
				_islands[n] = next_id
				queue.push_back(n)
		next_id += 1
	dbg_island_us += Time.get_ticks_usec() - t0


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
	change_version += 1
	var r: Rect2i = rect.intersection(Rect2i(0, 0, terrain.size, terrain.size))
	var delta_cells: PackedInt32Array = PackedInt32Array()
	var delta_solids: PackedByteArray = PackedByteArray()
	for z in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			var cell: Vector2i = Vector2i(x, z)
			var solid: bool = _building_cells.has(cell) or not terrain.is_walkable(cell)
			_astar.set_point_solid(cell, solid)
			walkable_map[z * terrain.size + x] = 0 if solid else 1
			if path_worker != null:
				delta_cells.append(z * terrain.size + x)
				delta_solids.append(1 if solid else 0)
	_refresh_vehicle_region(r)
	_islands_dirty = true
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
			_vehicle_astar.set_point_solid(cell,
				not _vehicle_passable(cell) or _vehicle_obstacles.has(cell))


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


## Blocks/unblocks a parked vehicle's footprint cells on the VEHICLE grid only
## (refcounted). A stationary unmanned vehicle registers its cells so other
## vehicles route around it; it clears them when crewed/moving/destroyed. The
## unit grid and PathWorker are untouched — pedestrians ignore parked vehicles.
func set_vehicle_obstacle(cells: Array[Vector2i], solid: bool) -> void:
	for cell in cells:
		if not terrain.in_bounds(cell):
			continue
		if solid:
			_vehicle_obstacles[cell] = int(_vehicle_obstacles.get(cell, 0)) + 1
			_vehicle_astar.set_point_solid(cell, true)
		else:
			var n: int = int(_vehicle_obstacles.get(cell, 0)) - 1
			if n > 0:
				_vehicle_obstacles[cell] = n
				continue
			_vehicle_obstacles.erase(cell)
			# Restore the cell's natural vehicle passability (terrain/erosion).
			_vehicle_astar.set_point_solid(cell, not _vehicle_passable(cell))


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
