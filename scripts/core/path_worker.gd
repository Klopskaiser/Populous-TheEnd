class_name PathWorker extends RefCounted

## Off-main-thread A* pathfinding (phase 8.1, Stufe A).
##
## Owns a private AStarGrid2D clone of the NavGrid's UNIT grid. The main thread
## keeps NavGrid as the single source of truth and mirrors every solidity change
## here as a compact delta; path requests and grid deltas share ONE FIFO queue,
## so a terrain change always applies BEFORE any request queued after it (no
## path solved on a stale grid state). Only POD data crosses the thread
## boundary — cell indices, ints and cell paths. Terrain heights never leave the
## main thread; the caller converts the returned cell path to world space
## (Y-snap + exact-target rule) in Unit._apply_worker_path.
##
## Godot 4.7 threading rules honoured (see plans/08b_parallelization.md):
## AStarGrid2D is not thread-safe across shared state, so the clone is built on
## the main thread in _init() and afterwards touched ONLY by the worker thread
## (deltas + get_id_path); no Node/scene access, no RefCounted sharing across
## threads, no randf() in worker code.

## Mirrors NavGrid.MAX_SNAP_RADIUS — snapping runs in the worker on its clone.
const MAX_SNAP_RADIUS: int = 32

const KIND_DELTA: int = 0
const KIND_REQUEST: int = 1

var _thread: Thread = Thread.new()
var _mutex: Mutex = Mutex.new()
var _sem: Semaphore = Semaphore.new()
var _results_mutex: Mutex = Mutex.new()
var _running: bool = false

var _grid: AStarGrid2D = AStarGrid2D.new()
var _size: int = 0

## Inbound mixed FIFO. Each entry is an untyped Array:
##   [KIND_DELTA, cells: PackedInt32Array, solids: PackedByteArray]
##   [KIND_REQUEST, instance_id: int, request_id: int,
##    from_cell: Vector2i, target_cell: Vector2i]
var _queue: Array = []
## Outbound results: [instance_id: int, request_id: int, cells: PackedVector2Array].
var _results: Array = []


## Builds the clone from a full solidity snapshot (index = z * size + x, 1 =
## solid) and starts the worker thread. The snapshot and region come from the
## NavGrid so the clone starts perfectly in sync.
func _init(region: Rect2i, cell_size: Vector2, diagonal_mode: int,
		solid_snapshot: PackedByteArray, grid_size: int) -> void:
	_size = grid_size
	_grid.region = region
	_grid.cell_size = cell_size
	_grid.diagonal_mode = diagonal_mode
	_grid.update()
	for i in range(solid_snapshot.size()):
		if solid_snapshot[i] != 0:
			@warning_ignore("integer_division")
			_grid.set_point_solid(Vector2i(i % _size, i / _size), true)
	_running = true
	_thread.start(_run)


# --- Main-thread API ----------------------------------------------------------

## Enqueues a solidity delta (cell indices + solid flags). FIFO-ordered with
## requests: applies before any request submitted afterwards.
func push_delta(cells: PackedInt32Array, solids: PackedByteArray) -> void:
	if not _running:
		return
	_mutex.lock()
	_queue.append([KIND_DELTA, cells, solids])
	_mutex.unlock()
	_sem.post()


## Enqueues a path request. from_cell/target_cell are grid cells (pure int math
## from world_to_cell — no terrain heights needed); the worker snaps both to the
## nearest walkable cell on its clone.
func submit_request(instance_id: int, request_id: int, from_cell: Vector2i,
		target_cell: Vector2i) -> void:
	if not _running:
		return
	_mutex.lock()
	_queue.append([KIND_REQUEST, instance_id, request_id, from_cell, target_cell])
	_mutex.unlock()
	_sem.post()


## Returns and clears all completed results (called once per tick by the
## UnitManager). Each entry: [instance_id, request_id, cells].
func drain_results() -> Array:
	_results_mutex.lock()
	var out: Array = _results
	_results = []
	_results_mutex.unlock()
	return out


## Stops the worker thread and joins it. Idempotent; after this, push_delta /
## submit_request are no-ops. Call from the owner's _exit_tree.
func stop() -> void:
	if not _running:
		return
	_running = false
	_sem.post()
	_thread.wait_to_finish()


# --- Worker thread ------------------------------------------------------------

func _run() -> void:
	while true:
		_sem.wait()
		if not _running:
			break
		_mutex.lock()
		var batch: Array = _queue
		_queue = []
		_mutex.unlock()
		for msg in batch:
			if msg[0] == KIND_DELTA:
				_apply_delta(msg[1], msg[2])
			else:
				_solve_request(msg[1], msg[2], msg[3], msg[4])


func _apply_delta(cells: PackedInt32Array, solids: PackedByteArray) -> void:
	for i in range(cells.size()):
		var idx: int = cells[i]
		@warning_ignore("integer_division")
		_grid.set_point_solid(Vector2i(idx % _size, idx / _size), solids[i] != 0)


func _solve_request(instance_id: int, request_id: int, from_cell: Vector2i,
		target_cell: Vector2i) -> void:
	var cells: PackedVector2Array = PackedVector2Array()
	var from: Vector2i = _snap(from_cell)
	var to: Vector2i = _snap(target_cell)
	if from.x >= 0 and to.x >= 0:
		var id_path: Array[Vector2i] = _grid.get_id_path(from, to)
		for c in id_path:
			cells.append(Vector2(c))
	_results_mutex.lock()
	_results.append([instance_id, request_id, cells])
	_results_mutex.unlock()


## Nearest walkable cell via outward ring search (mirrors
## NavGrid.nearest_walkable_cell on the worker clone). (-1, -1) if none in range.
func _snap(cell: Vector2i) -> Vector2i:
	cell = Vector2i(clampi(cell.x, 0, _size - 1), clampi(cell.y, 0, _size - 1))
	if not _grid.is_point_solid(cell):
		return cell
	for radius in range(1, MAX_SNAP_RADIUS + 1):
		var best: Vector2i = Vector2i(-1, -1)
		var best_dist: float = INF
		for candidate in _ring_cells(cell, radius):
			if candidate.x < 0 or candidate.y < 0 \
					or candidate.x >= _size or candidate.y >= _size:
				continue
			if _grid.is_point_solid(candidate):
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
