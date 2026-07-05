extends TestBase

## Headless tests for Unit movement logic (tick-driven, outside the scene
## tree) and the UnitManager spatial hash. Nodes are freed manually to avoid
## leaked instances.

const TICK: float = 0.05
const MAX_TICKS: int = 20000


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


func _make_unit(td: TerrainData) -> Unit:
	var unit: Unit = Unit.new()
	unit.terrain_data = td
	return unit


## Ticks until the unit is IDLE (or the tick budget runs out).
func _tick_until_idle(unit: Unit) -> int:
	var ticks: int = 0
	while unit.state != Unit.State.IDLE and ticks < MAX_TICKS:
		unit.tick(TICK)
		ticks += 1
	return ticks


func test_unit_follows_path_to_target() -> void:
	var td: TerrainData = _flat_terrain()
	var unit: Unit = _make_unit(td)
	unit.position = Vector3(10.0, 0.0, 10.0)
	unit.set_path(PackedVector3Array([Vector3(15.0, 0.0, 10.0), Vector3(15.0, 0.0, 18.0)]))
	check(unit.state == Unit.State.MOVE, "unit is MOVE after set_path")
	_tick_until_idle(unit)
	check(unit.state == Unit.State.IDLE, "unit is IDLE after finishing the path")
	var flat: Vector2 = Vector2(unit.position.x, unit.position.z)
	check(flat.distance_to(Vector2(15.0, 18.0)) <= 0.1,
		"unit reached the path end (at %s)" % str(flat))
	unit.free()


func test_y_snapping_follows_terrain() -> void:
	var td: TerrainData = _flat_terrain()
	# Give the terrain a distinct bump so Y actually changes along the way.
	td.raise_area(Vector2(20.0, 20.0), 8.0, 4.0)
	var unit: Unit = _make_unit(td)
	unit.position = Vector3(12.0, 0.0, 20.0)
	unit.set_path(PackedVector3Array([Vector3(20.0, 0.0, 20.0)]))
	var snapped_ok: bool = true
	for i in range(200):
		unit.tick(TICK)
		var expected: float = td.get_height(unit.position.x, unit.position.z)
		if absf(unit.position.y - expected) > 0.0001:
			snapped_ok = false
			break
		if unit.state == Unit.State.IDLE:
			break
	check(snapped_ok, "position.y always matches TerrainData.get_height()")
	check_near(unit.position.y, td.get_height(unit.position.x, unit.position.z),
		"final Y matches terrain height")
	unit.free()


func test_waypoint_queue_in_order() -> void:
	var td: TerrainData = _flat_terrain()
	var unit: Unit = _make_unit(td)
	unit.position = Vector3(10.0, 0.0, 10.0)
	var wp1: Vector3 = Vector3(14.0, 0.0, 10.0)
	var wp2: Vector3 = Vector3(14.0, 0.0, 14.0)
	var wp3: Vector3 = Vector3(10.0, 0.0, 14.0)
	unit.order_move(wp1)
	unit.order_move(wp2, true)
	unit.order_move(wp3, true)
	check(unit.waypoint_queue.size() == 3, "queue holds 3 waypoints")

	var reach_order: Array[int] = []
	var waypoints: Array[Vector3] = [wp1, wp2, wp3]
	var ticks: int = 0
	while unit.state != Unit.State.IDLE and ticks < MAX_TICKS:
		unit.tick(TICK)
		ticks += 1
		for i in range(waypoints.size()):
			if i in reach_order:
				continue
			var flat: Vector2 = Vector2(unit.position.x, unit.position.z)
			if flat.distance_to(Vector2(waypoints[i].x, waypoints[i].z)) <= 0.1:
				reach_order.append(i)
	check(unit.state == Unit.State.IDLE, "unit is IDLE after the route")
	check(reach_order == ([0, 1, 2] as Array[int]),
		"waypoints reached in order (got %s)" % str(reach_order))
	check(unit.waypoint_queue.is_empty(), "queue is empty after a one-shot route")
	unit.free()


func test_patrol_repeats_route() -> void:
	var td: TerrainData = _flat_terrain()
	var unit: Unit = _make_unit(td)
	unit.position = Vector3(10.0, 0.0, 10.0)
	var wp1: Vector3 = Vector3(13.0, 0.0, 10.0)
	var wp2: Vector3 = Vector3(13.0, 0.0, 13.0)
	var wp3: Vector3 = Vector3(10.0, 0.0, 13.0)
	unit.patrol = true
	unit.order_move(wp1)
	unit.order_move(wp2, true)
	unit.order_move(wp3, true)

	# Enough ticks for several laps around the triangle.
	var visits_wp1: int = 0
	var near_wp1: bool = false
	for i in range(4000):
		unit.tick(TICK)
		var flat: Vector2 = Vector2(unit.position.x, unit.position.z)
		var is_near: bool = flat.distance_to(Vector2(wp1.x, wp1.z)) <= 0.1
		if is_near and not near_wp1:
			visits_wp1 += 1
		near_wp1 = is_near
	check(unit.state == Unit.State.MOVE, "patrol: unit keeps moving")
	check(unit.waypoint_queue.size() == 3, "patrol: queue length stays constant")
	check(visits_wp1 >= 2, "patrol: first waypoint visited again (%d visits)" % visits_wp1)
	unit.free()


func test_view_suffix_directions() -> void:
	# Camera looks north (-Z), its right vector points east (+X).
	var fwd: Vector3 = Vector3(0, 0, -1)
	var right: Vector3 = Vector3(1, 0, 0)
	check(Unit.view_suffix(Vector3(0, 0, -1), fwd, right) == &"back",
		"walking away from camera -> back view")
	check(Unit.view_suffix(Vector3(0, 0, 1), fwd, right) == &"front",
		"walking toward camera -> front view")
	check(Unit.view_suffix(Vector3(1, 0, 0), fwd, right) == &"right",
		"walking screen-right -> right view")
	check(Unit.view_suffix(Vector3(-1, 0, 0), fwd, right) == &"left",
		"walking screen-left -> left view")
	check(Unit.view_suffix(Vector3.ZERO, fwd, right) == &"front",
		"zero facing falls back to front view")
	# Rotated camera: looking east -> a unit walking east is seen from behind.
	check(Unit.view_suffix(Vector3(1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)) == &"back",
		"rotated camera: same heading -> back view")


func test_facing_follows_movement() -> void:
	var td: TerrainData = _flat_terrain()
	var unit: Unit = _make_unit(td)
	unit.position = Vector3(10.0, 0.0, 10.0)
	unit.set_path(PackedVector3Array([Vector3(14.0, 0.0, 10.0)]))
	unit.tick(TICK)
	check(unit.facing.distance_to(Vector3(1, 0, 0)) < 0.001,
		"facing points along the movement direction (+X)")
	_tick_until_idle(unit)
	check(unit.facing.distance_to(Vector3(1, 0, 0)) < 0.001,
		"facing is kept after the unit stops")
	unit.free()


func test_remaining_path_shrinks() -> void:
	var td: TerrainData = _flat_terrain()
	var unit: Unit = _make_unit(td)
	unit.position = Vector3(10.0, 0.0, 10.0)
	unit.set_path(PackedVector3Array([Vector3(12.0, 0.0, 10.0), Vector3(14.0, 0.0, 10.0)]))
	check(unit.get_remaining_path().size() == 2, "remaining path starts with 2 points")
	for i in range(100):
		unit.tick(TICK)
		if unit.get_remaining_path().size() < 2:
			break
	check(unit.get_remaining_path().size() == 1,
		"first path point is dropped after passing it")
	_tick_until_idle(unit)
	check(unit.get_remaining_path().is_empty(), "remaining path is empty when IDLE")
	unit.free()


func test_spatial_hash_radius_query() -> void:
	var td: TerrainData = _flat_terrain()
	var manager: UnitManager = UnitManager.new()
	manager.setup(td, null)

	var inside_a: Unit = _make_unit(td)
	inside_a.position = Vector3(50.0, 5.0, 50.0)
	var inside_b: Unit = _make_unit(td)
	inside_b.position = Vector3(53.0, 5.0, 52.0)
	var outside_near: Unit = _make_unit(td)
	outside_near.position = Vector3(56.0, 5.0, 50.0)   # 6 m away
	var outside_far: Unit = _make_unit(td)
	outside_far.position = Vector3(90.0, 5.0, 90.0)
	for unit: Unit in [inside_a, inside_b, outside_near, outside_far]:
		manager.register(unit)
	manager.tick(TICK)

	var found: Array[Unit] = manager.get_units_in_radius(Vector3(50.0, 5.0, 50.0), 5.0)
	check(inside_a in found, "radius query finds unit at the centre")
	check(inside_b in found, "radius query finds unit inside the radius")
	check(not (outside_near in found), "radius query excludes unit just outside")
	check(not (outside_far in found), "radius query excludes far-away unit")
	check(found.size() == 2, "radius query returns exactly 2 units")

	# Moving a unit updates its hash cell on the next tick.
	inside_b.position = Vector3(90.0, 5.0, 90.0)
	manager.tick(TICK)
	found = manager.get_units_in_radius(Vector3(50.0, 5.0, 50.0), 5.0)
	check(found.size() == 1, "moved unit left the radius after hash update")

	check(manager.get_units_of_tribe(0).size() == 4, "tribe query returns all units")

	for unit: Unit in [inside_a, inside_b, outside_near, outside_far]:
		unit.free()
	manager.free()


func test_path_queue_spreads_path_requests() -> void:
	var td: TerrainData = _flat_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var manager: UnitManager = UnitManager.new()
	manager.setup(td, nav)
	var count: int = UnitManager.PATHS_PER_TICK + 12
	var units: Array[Unit] = []
	for i in range(count):
		var unit: Unit = _make_unit(td)
		unit.nav_grid = nav
		unit.path_service = manager
		unit.position = Vector3(30.0 + float(i % 10) * 1.5, 5.0, 30.0 + float(i / 10) * 1.5)
		manager.register(unit)
		units.append(unit)

	for unit in units:
		unit.order_move(Vector3(90.0, 5.0, 90.0))
	var pending: int = 0
	for unit in units:
		if unit.state == Unit.State.MOVE and unit.get_remaining_path().is_empty():
			pending += 1
	check(pending == count, "all move orders wait for the path queue first")

	manager.tick(TICK)
	var resolved: int = 0
	for unit in units:
		if not unit.get_remaining_path().is_empty():
			resolved += 1
	check(resolved == UnitManager.PATHS_PER_TICK,
		"one tick resolves at most PATHS_PER_TICK paths (got %d)" % resolved)

	manager.tick(TICK)
	resolved = 0
	for unit in units:
		if not unit.get_remaining_path().is_empty():
			resolved += 1
	check(resolved == count, "the second tick resolves the rest")

	var before: Vector3 = units[0].position
	units[0].tick(TICK)
	check(units[0].position != before, "resolved units actually walk")

	for unit in units:
		unit.free()
	manager.free()


func test_separation_pushes_overlapping_units_apart() -> void:
	var td: TerrainData = _flat_terrain()
	var manager: UnitManager = UnitManager.new()
	manager.setup(td, null)
	var a: Unit = _make_unit(td)
	var b: Unit = _make_unit(td)
	a.position = Vector3(50.0, 5.0, 50.0)
	b.position = Vector3(50.0, 5.0, 50.0)   # full overlap
	manager.register(a)
	manager.register(b)

	for i in range(100):
		manager.tick(TICK)
	var dist: float = Vector2(a.position.x, a.position.z).distance_to(
		Vector2(b.position.x, b.position.z))
	check(dist >= 0.4, "overlapping units are pushed apart (dist %f)" % dist)
	check(dist <= 2.0, "separation does not fling units away")
	check_near(a.position.y, td.get_height(a.position.x, a.position.z),
		"pushed unit stays snapped to the terrain")

	a.free()
	b.free()
	manager.free()
