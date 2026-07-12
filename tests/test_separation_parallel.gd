extends TestBase

## Phase 8.1 (Stufe B): the two-phase parallel separation must behave like the
## serial pass — same push rules, same guards (nobody shoved onto unwalkable
## cells), same anti-stacking bookkeeping. Runs real WorkerThreadPool group
## tasks (headless-safe; the group is always waited for inside the call).

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


func _make_world(parallel: bool) -> Dictionary:
	var td: TerrainData = _flat_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var tribes: Array[Tribe] = [Tribe.new(0), Tribe.new(1)]
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, tribes)
	um.separation_parallel = parallel
	return {"td": td, "nav": nav, "um": um}


func test_parallel_pushes_overlapping_units_apart() -> void:
	var w: Dictionary = _make_world(true)
	var um: UnitManager = w.um
	var a: Unit = um.spawn_unit(BRAVE_SCENE, 0, Vector3(50.0, 5.0, 50.0))
	var b: Unit = um.spawn_unit(BRAVE_SCENE, 0, Vector3(50.0, 5.0, 50.0))
	for i in range(100):
		um.tick(1.0 / 30.0)
	var dist: float = Vector2(a.position.x, a.position.z).distance_to(
		Vector2(b.position.x, b.position.z))
	check(dist >= 0.3, "parallel: overlapping units are pushed apart (dist %f)" % dist)
	check(dist <= 2.0, "parallel: separation does not fling units away")
	check_near(a.position.y, w.td.get_height(a.position.x, a.position.z),
		"parallel: pushed unit stays snapped to the terrain")
	um.free()


func test_parallel_matches_serial_endstate() -> void:
	# Same stacked cluster, once serial, once parallel: both must resolve into
	# a spread-out, non-overlapping formation with everyone on walkable cells.
	var results: Array[Dictionary] = []
	for parallel in [false, true]:
		var w: Dictionary = _make_world(parallel)
		var um: UnitManager = w.um
		var spawn: Vector3 = w.nav.cell_to_world(Vector2i(60, 60))
		var cluster: Array[Unit] = []
		for i in range(30):
			cluster.append(um.spawn_unit(BRAVE_SCENE, 0, spawn))
		for i in range(300):
			# Units tick too, so anti-stacking escape orders actually complete
			# (otherwise escapees stand overlapped in MOVE forever).
			for u in cluster:
				u.tick(1.0 / 30.0)
			um.tick(1.0 / 30.0)
		var min_dist: float = INF
		var max_spread: float = 0.0
		var off_grid: int = 0
		for i in range(cluster.size()):
			var p: Vector3 = cluster[i].position
			if not w.nav.is_cell_walkable(w.nav.world_to_cell(p)):
				off_grid += 1
			max_spread = maxf(max_spread, Vector2(p.x - spawn.x, p.z - spawn.z).length())
			for j in range(i + 1, cluster.size()):
				var q: Vector3 = cluster[j].position
				min_dist = minf(min_dist, Vector2(p.x - q.x, p.z - q.z).length())
		results.append({"min": min_dist, "spread": max_spread, "off": off_grid})
		um.free()
	for r in results:
		check(r.off == 0, "endstate: nobody pushed onto an unwalkable cell")
		check(r.spread < 10.0, "endstate: cluster stays local (spread %.2f m)" % r.spread)
	# Parallel resolves stacking at least as well as serial (small tolerance:
	# two-phase pushes converge in a slightly different order).
	check(results[1].min >= results[0].min - 0.15,
		"endstate: parallel min distance %.3f vs serial %.3f" % [results[1].min, results[0].min])
	check(results[1].min > 0.05, "endstate: parallel actually unstacked the pile")


func test_parallel_respects_skip_states_and_immunity() -> void:
	var w: Dictionary = _make_world(true)
	var um: UnitManager = w.um
	var mover: Unit = um.spawn_unit(BRAVE_SCENE, 0, Vector3(50.0, 5.0, 50.0))
	var corpse: Unit = um.spawn_unit(BRAVE_SCENE, 1, Vector3(50.2, 5.0, 50.0))
	corpse.state = Unit.State.DEAD
	var immune: Unit = um.spawn_unit(BRAVE_SCENE, 0, Vector3(50.0, 5.0, 50.2))
	immune.push_immune = true
	var corpse_pos: Vector3 = corpse.position
	var immune_pos: Vector3 = immune.position
	for i in range(30):
		um.tick(1.0 / 30.0)
	check(corpse.position == corpse_pos, "skip: a corpse is never pushed")
	check(immune.position == immune_pos, "skip: a push-immune unit is never pushed")
	check(Vector2(mover.position.x - 50.0, mover.position.z - 50.0).length() > 0.05,
		"skip: the live unit still got pushed (by the immune neighbour)")
	um.free()


func test_parallel_tight_overlap_ticks_accumulate() -> void:
	# Anti-stacking bookkeeping runs in the serial apply phase. Soft separation
	# frees a small free-standing stack before the escape threshold, so the
	# walled-in case is emulated by re-pinning both units onto the same spot
	# every tick: overlap_ticks must accumulate and trigger the escape order.
	var w: Dictionary = _make_world(true)
	var um: UnitManager = w.um
	var pos: Vector3 = w.nav.cell_to_world(Vector2i(60, 60))
	var a: Unit = um.spawn_unit(BRAVE_SCENE, 0, pos)
	var b: Unit = um.spawn_unit(BRAVE_SCENE, 0, pos)
	var escaped: bool = false
	for i in range(30):
		um.tick(1.0 / 30.0)
		if a.state == Unit.State.MOVE or b.state == Unit.State.MOVE:
			escaped = true
			break
		a.position = pos   # pin: soft separation "cannot" free them
		b.position = pos
	check(escaped, "tight: a permanently stacked unit gets an escape move order")
	um.free()
