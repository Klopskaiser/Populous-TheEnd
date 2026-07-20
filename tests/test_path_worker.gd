extends TestBase

## Phase 8.1 (Stufe A): functional tests for the off-main-thread PathWorker and
## its UnitManager/Unit integration, plus a regression watcher against the
## phase-8 "units ignore orders" restack bug (no unit stays in MOVE with an open
## async request and an empty path once results are drained).
##
## These tests start a REAL worker thread (headless-safe). Every world is torn
## down via _shutdown() which joins the thread — the test node lives outside the
## scene tree, so UnitManager._exit_tree never fires automatically.

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const SIEGE_SCENE: PackedScene = preload("res://scenes/units/siege_engine.tscn")


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


## Land at 5.0 split by a below-sea-level valley along x = 64 (mirrors the
## NavGrid test) → two disconnected landmasses.
func _valley_terrain() -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for vz in range(TerrainData.VERTS):
		for vx in range(TerrainData.VERTS):
			var dx: float = absf(float(vx) - 64.0)
			var h: float = 5.0 - 0.5 * maxf(0.0, 10.0 - dx)
			td.heights[vz * TerrainData.VERTS + vx] = h
	return td


func _make_world(td: TerrainData) -> Dictionary:
	var nav: NavGrid = NavGrid.new(td)
	var worker: PathWorker = PathWorker.new(
		Rect2i(0, 0, td.size, td.size),
		Vector2(TerrainData.CELL_SIZE, TerrainData.CELL_SIZE),
		AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES,
		nav.solid_snapshot(), td.size)
	nav.path_worker = worker
	var tribes: Array[Tribe] = [Tribe.new(0), Tribe.new(1)]
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, tribes)
	um.path_worker = worker
	return {"td": td, "nav": nav, "um": um, "worker": worker}


func _shutdown(w: Dictionary) -> void:
	w.worker.stop()
	w.nav.path_worker = null
	w.um.path_worker = null
	w.um.free()


## Pumps the async path pipeline: submits queued requests and drains ready
## results across several short waits so the worker thread can produce them.
## Returns once every live unit has left the "waiting for path" window or the
## budget runs out.
func _pump(w: Dictionary, budget_ms: int = 1000) -> void:
	var um: UnitManager = w.um
	var elapsed: int = 0
	while elapsed <= budget_ms:
		um._drain_path_queue()
		if not _any_pending(um):
			return
		OS.delay_msec(4)
		elapsed += 4


func _any_pending(um: UnitManager) -> bool:
	for u in um.units:
		if is_instance_valid(u) and u._pending_target != Vector3.INF:
			return true
	return false


# --- Tests --------------------------------------------------------------------

func test_async_path_is_produced_and_walked() -> void:
	var w: Dictionary = _make_world(_flat_terrain())
	var um: UnitManager = w.um
	var brave: Unit = um.spawn_unit(BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(20, 20)))
	brave.order_move(w.nav.cell_to_world(Vector2i(80, 60)))
	check(brave._pending_target != Vector3.INF, "async: order parks a pending target")
	_pump(w)
	check(brave._pending_target == Vector3.INF, "async: pending target consumed after worker reply")
	check(brave.state == Unit.State.MOVE, "async: unit is in MOVE with a path")
	var path: PackedVector3Array = brave.get_remaining_path()
	check(path.size() > 0, "async: a non-empty path was applied")
	if path.size() > 0:
		check(w.nav.world_to_cell(path[path.size() - 1]) == Vector2i(80, 60),
			"async: path ends at the target cell")
	# The unit actually advances when ticked.
	var x0: float = brave.position.x
	for i in range(20):
		brave.tick(0.1)
	check(brave.position.x > x0 + 1.0, "async: unit walks along the applied path")
	_shutdown(w)


func test_grid_delta_applies_before_later_request() -> void:
	var w: Dictionary = _make_world(_flat_terrain())
	var um: UnitManager = w.um
	# Wall along x = 64, rows 30..97 — pushed to the worker as a delta.
	var wall: Rect2i = Rect2i(64, 30, 1, 68)
	w.nav.fill_solid_region(wall, true)
	var brave: Unit = um.spawn_unit(BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(40, 64)))
	brave.order_move(w.nav.cell_to_world(Vector2i(90, 64)))
	_pump(w)
	var path: PackedVector3Array = brave.get_remaining_path()
	check(path.size() > 0, "delta: detour path exists across the wall")
	var crosses: bool = false
	for p in path:
		if wall.has_point(w.nav.world_to_cell(p)):
			crosses = true
			break
	check(not crosses, "delta: worker path respects the wall pushed before the request")
	_shutdown(w)


func test_stale_result_is_discarded() -> void:
	var w: Dictionary = _make_world(_flat_terrain())
	var um: UnitManager = w.um
	var brave: Unit = um.spawn_unit(BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(20, 20)))
	# Order A, submit it, then order B before A's reply is applied.
	brave.order_move(w.nav.cell_to_world(Vector2i(80, 20)))
	um._drain_path_queue()   # submits request #1
	brave.order_move(w.nav.cell_to_world(Vector2i(20, 80)))
	um._drain_path_queue()   # submits request #2, invalidating #1
	check(brave._path_request_id == 2, "stale: a second order bumps the request id")
	_pump(w)
	var path: PackedVector3Array = brave.get_remaining_path()
	check(path.size() > 0, "stale: the latest order produced a path")
	if path.size() > 0:
		check(w.nav.world_to_cell(path[path.size() - 1]) == Vector2i(20, 80),
			"stale: path ends at target B, not the superseded target A")
	_shutdown(w)


func test_unreachable_target_goes_idle() -> void:
	var w: Dictionary = _make_world(_valley_terrain())
	var um: UnitManager = w.um
	var brave: Unit = um.spawn_unit(BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(30, 64)))
	brave.order_move(w.nav.cell_to_world(Vector2i(100, 64)))   # across the water strip
	_pump(w)
	check(brave._pending_target == Vector3.INF, "unreachable: pending target consumed")
	check(brave.state == Unit.State.IDLE, "unreachable: unit falls back to IDLE (as synchronous)")
	_shutdown(w)


## Regression (fire-ram hill judder): a CrewedVehicle MUST plan MOVE orders on
## the VEHICLE grid, NOT via the async PathWorker. The worker is seeded with the
## PEDESTRIAN solidity snapshot and knows nothing about the eroded vehicle grid —
## deferring to it handed the vehicle a pedestrian route onto a ridge its own
## combat approach (find_vehicle_path) then refused, making the ram oscillate.
## The fix overrides CrewedVehicle._start_path_to to plan synchronously.
func test_vehicle_move_uses_vehicle_grid_not_async_worker() -> void:
	var w: Dictionary = _make_world(_flat_terrain())
	var um: UnitManager = w.um
	# Wall with a 1-cell gap: passable for pedestrians, closed to vehicles.
	var wall_x: int = 64
	for z in range(0, TerrainData.SIZE):
		if z == 60:
			continue
		w.nav.fill_solid_region(Rect2i(Vector2i(wall_x, z), Vector2i(1, 1)), true)
	var target: Vector3 = w.nav.cell_to_world(Vector2i(80, 60))
	var veh: Unit = um.spawn_unit(SIEGE_SCENE, 0, w.nav.cell_to_world(Vector2i(50, 60)))
	check(veh is CrewedVehicle, "spawned a crewed vehicle")
	veh._start_path_to(target)
	# Planned synchronously: never parked on the async (pedestrian) worker.
	check(veh._pending_target == Vector3.INF,
		"vehicle MOVE plans synchronously, does not defer to the pedestrian worker")
	# The 1-cell gap is closed to vehicles -> no route -> stop, NOT a pedestrian
	# path threaded through the gap.
	check(veh.get_remaining_path().is_empty(),
		"vehicle gets no path through the pedestrian-only 1-cell gap")
	check(veh.state == Unit.State.IDLE,
		"unreachable-by-vehicle target -> IDLE (route dropped)")
	# Widen the gap to 2 cells: the vehicle grid now has a route.
	w.nav.fill_solid_region(Rect2i(Vector2i(wall_x, 61), Vector2i(1, 1)), false)
	veh._start_path_to(target)
	check(veh._pending_target == Vector3.INF, "widened: still synchronous")
	check(not veh.get_remaining_path().is_empty(),
		"widened 2-cell corridor -> a vehicle path exists")
	check(veh.state == Unit.State.MOVE, "widened: vehicle is in MOVE with a path")
	# Contrast: a pedestrian in the SAME world still uses the async worker.
	var brave: Unit = um.spawn_unit(BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(50, 60)))
	brave._start_path_to(target)
	check(brave._pending_target != Vector3.INF,
		"pedestrian MOVE still defers to the async worker")
	_shutdown(w)


func test_shutdown_is_clean() -> void:
	var w: Dictionary = _make_world(_flat_terrain())
	var um: UnitManager = w.um
	var brave: Unit = um.spawn_unit(BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(20, 20)))
	brave.order_move(w.nav.cell_to_world(Vector2i(80, 60)))
	um._drain_path_queue()   # a request is in flight when we stop
	w.worker.stop()
	# After stop the API is inert and does not hang or crash.
	w.worker.submit_request(brave.get_instance_id(), 99, Vector2i(0, 0), Vector2i(1, 1))
	check(w.worker.drain_results() is Array, "shutdown: drain still returns after stop")
	w.worker.stop()   # idempotent
	w.nav.path_worker = null
	w.um.path_worker = null
	w.um.free()
	check(true, "shutdown: joined cleanly without hang")


## Regression watcher for the phase-8 restack bug: mass move orders plus a
## mid-run terrain delta (earthquake-like). After draining, NO living unit may
## sit in MOVE with an empty path and an open async request.
func test_regression_no_stuck_units_after_delta() -> void:
	var w: Dictionary = _make_world(_flat_terrain())
	var um: UnitManager = w.um
	var braves: Array[Unit] = []
	for i in range(200):
		var cell: Vector2i = Vector2i(20 + i % 20, 20 + i / 20)
		var b: Unit = um.spawn_unit(BRAVE_SCENE, 0, w.nav.cell_to_world(cell))
		if b != null:
			braves.append(b)
	for b in braves:
		b.order_move(w.nav.cell_to_world(Vector2i(100, 100)))
	um._drain_path_queue()   # submit the whole wave at once
	# Mid-flight terrain change: block a strip (delta) then re-order everyone.
	var wall: Rect2i = Rect2i(70, 60, 1, 40)
	w.nav.fill_solid_region(wall, true)
	for b in braves:
		b.order_move(w.nav.cell_to_world(Vector2i(110, 110)))
	_pump(w, 3000)
	var stuck: int = 0
	for b in braves:
		if not is_instance_valid(b):
			continue
		var open_request: bool = b._pending_target != Vector3.INF
		var empty_path: bool = b.get_remaining_path().is_empty()
		if b.state == Unit.State.MOVE and empty_path and open_request:
			stuck += 1
	check(stuck == 0, "regression: no unit stuck in MOVE with empty path + open request (%d stuck)" % stuck)
	# Sanity: the wave actually got paths (most units moving toward the goal).
	var moving: int = 0
	for b in braves:
		if is_instance_valid(b) and b.get_remaining_path().size() > 0:
			moving += 1
	check(moving > 150, "regression: the bulk of the wave received a path (%d/200)" % moving)
	_shutdown(w)
