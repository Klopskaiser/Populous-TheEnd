extends TestBase

## Bug-Backlog #4: the tree search preferred the beeline-nearest tree even when
## it stands below a cliff (reachable only via a long ramp detour), instead of a
## same-level tree slightly farther away. TreeManager.best_tree now ranks
## candidates by beeline + height malus and VERIFIES the best few with a real
## NavGrid path (early accept when the path is roughly the beeline; walks
## beyond PATH_RADIUS_FACTOR x the search radius are rejected). Also used by
## the construction-worker search (Brave._nearest_claimable_tree).

const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")

## Plateau world: high level (9 m) for x <= 40, low level (3 m) for x >= 46,
## hard cliff between them (unwalkable) — except a walkable ramp strip at
## z 60..70 (slope 1 m per cell). Both levels form ONE island via the ramp.
func _plateau_terrain() -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for vz in range(td.size + 1):
		for vx in range(td.size + 1):
			var h: float
			if vx <= 40:
				h = 9.0
			elif vx >= 46:
				h = 3.0
			elif vz >= 60 and vz <= 70:
				h = 9.0 - float(vx - 40)          # ramp: 1 m/cell, walkable
			else:
				h = 9.0 if vx <= 42 else 3.0      # cliff: 6 m step, unwalkable
			td.set_vertex_height(vx, vz, h)
	return td


func _make_world() -> Dictionary:
	var td: TerrainData = _plateau_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	return {"td": td, "nav": nav, "tm": tm}


func _free_world(w: Dictionary) -> void:
	w.tm.free()


## Search position on the plateau near the cliff edge.
func _edge_pos(w: Dictionary) -> Vector3:
	return w.nav.cell_to_world(Vector2i(38, 20))


func test_terrain_setup_ramp_connects_levels() -> void:
	var w: Dictionary = _make_world()
	check(w.nav.is_cell_walkable(Vector2i(38, 20)), "plateau is walkable")
	check(w.nav.is_cell_walkable(Vector2i(48, 20)), "low level is walkable")
	check(not w.nav.is_cell_walkable(Vector2i(42, 20)), "cliff is unwalkable")
	check(w.nav.same_island(_edge_pos(w), w.nav.cell_to_world(Vector2i(48, 20))),
		"ramp connects both levels into one island")
	_free_world(w)


func test_same_level_tree_wins_over_cliff_tree() -> void:
	var w: Dictionary = _make_world()
	# Beeline-nearest tree below the cliff (10 m away, 6 m lower) vs. a
	# same-level plateau tree 13.5 m away.
	var below: TreeResource = w.tm.spawn_tree(Vector2i(48, 20), 3)
	var level: TreeResource = w.tm.spawn_tree(Vector2i(25, 20), 3)
	check(w.tm.nearest_tree(_edge_pos(w)) == level,
		"the same-level tree wins although the cliff tree is beeline-nearer")
	var claimed: TreeResource = w.tm.claim_nearest_tree(_edge_pos(w), 50.0, self)
	check(claimed == level, "claiming picks the same-level tree too")
	check(below != null, "cliff tree still exists")   # silence unused warning
	_free_world(w)


func test_cliff_tree_still_found_as_fallback() -> void:
	var w: Dictionary = _make_world()
	# Only the tree below the cliff exists — it is reachable (via the ramp)
	# and must still be found despite the malus.
	var below: TreeResource = w.tm.spawn_tree(Vector2i(48, 20), 3)
	check(w.tm.nearest_tree(_edge_pos(w)) == below,
		"with no alternative the reachable cliff tree is still picked")
	_free_world(w)


func test_search_radius_still_respected() -> void:
	var w: Dictionary = _make_world()
	w.tm.spawn_tree(Vector2i(25, 20), 3)   # 13.5 m from the edge position
	check(w.tm.claim_nearest_tree(_edge_pos(w), 8.0, self) == null,
		"a tree beyond the search radius is not claimed")
	check(w.tm.claim_nearest_tree(_edge_pos(w), 20.0, self) != null,
		"the same tree is claimed once the radius covers it")
	_free_world(w)


func test_nearest_of_two_same_level_trees_wins() -> void:
	var w: Dictionary = _make_world()
	var near: TreeResource = w.tm.spawn_tree(Vector2i(30, 20), 3)
	w.tm.spawn_tree(Vector2i(20, 20), 3)
	check(w.tm.nearest_tree(_edge_pos(w)) == near,
		"on equal height plain distance still decides")
	_free_world(w)


# --- Construction workers (Brave._nearest_claimable_tree, the real repro) -----

## Plateau world with managers wired for buildings/units.
func _make_build_world() -> Dictionary:
	var td: TerrainData = _plateau_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var tribe: Tribe = Tribe.new(0)
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe] as Array[Tribe], tm, wpm)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um, wpm)
	return {"td": td, "nav": nav, "tribe": tribe, "tm": tm, "wpm": wpm,
		"um": um, "bm": bm}


func _free_build_world(w: Dictionary) -> void:
	w.bm.free()
	w.um.free()
	w.wpm.free()
	w.tm.free()


## The reported bug: hut site at the plateau edge, a tree below the cliff
## (beeline-near, huge ramp detour) and a tree on the plateau. The worker
## must pick the plateau tree.
func test_site_worker_prefers_plateau_tree() -> void:
	var w: Dictionary = _make_build_world()
	var site: Building = w.bm.place(HUT_SCENE, w.tribe, Vector2i(34, 18), 0, false)
	var brave: Brave = w.um.spawn_unit(BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(33, 20)))
	brave.job = site
	var below: TreeResource = w.tm.spawn_tree(Vector2i(44, 20), 3)   # below the cliff
	var level: TreeResource = w.tm.spawn_tree(Vector2i(24, 20), 3)   # on the plateau
	var picked: TreeResource = brave._nearest_claimable_tree(false)
	check(picked == level,
		"the construction worker picks the plateau tree, not the cliff tree")
	check(below != null, "cliff tree still exists")
	_free_build_world(w)


## With ONLY the cliff tree in reach the worker rejects the giant detour
## (the site stalls via the wood re-check instead of cliff-running).
func test_site_worker_rejects_giant_detour() -> void:
	var w: Dictionary = _make_build_world()
	var site: Building = w.bm.place(HUT_SCENE, w.tribe, Vector2i(34, 18), 0, false)
	var brave: Brave = w.um.spawn_unit(BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(33, 20)))
	brave.job = site
	w.tm.spawn_tree(Vector2i(44, 20), 3)   # only option: below the cliff
	check(brave._nearest_claimable_tree(false) == null,
		"a walk far beyond the search radius is not worth it -> no tree")
	_free_build_world(w)


## The loose chop chain (small radius) also refuses the cliff detour.
func test_chop_chain_refuses_cliff_detour() -> void:
	var w: Dictionary = _make_world()
	w.tm.spawn_tree(Vector2i(44, 20), 3)   # 6 m beeline, ~95 m walk
	check(w.tm.claim_nearest_tree(_edge_pos(w), 8.0, self, _edge_pos(w)) == null,
		"chain radius 8: the ~95 m ramp walk is rejected")
	_free_world(w)


# --- Negative-verdict cache (Seenland early-game lag) ---------------------------

## Rejected candidates (too far on foot) are cached: the SAME expensive A*
## must not run again on the next search, and cached negatives no longer eat
## the PATH_CANDIDATES budget — deeper candidates get verified instead.
func test_negative_verdicts_are_cached_and_budget_moves_on() -> void:
	var w: Dictionary = _make_world()
	# Four cliff trees rank first (beeline + malus < 46) but walk ~95 m; the
	# plateau tree at 46 m ranks fifth and is directly reachable.
	w.tm.spawn_tree(Vector2i(44, 20), 3)
	w.tm.spawn_tree(Vector2i(44, 23), 3)
	w.tm.spawn_tree(Vector2i(46, 20), 3)
	w.tm.spawn_tree(Vector2i(44, 17), 3)
	var plateau: TreeResource = w.tm.spawn_tree(Vector2i(38, 66), 3)
	var origin: Vector3 = _edge_pos(w)

	TreeManager.dbg_best_tree_paths = 0
	var first: TreeResource = w.tm.best_tree(origin, origin, 50.0, false)
	check(TreeManager.dbg_best_tree_paths == 4,
		"first search burns its 4 A* slots on the cliff trees")
	check(first == null, "all 4 verified candidates are too far -> no pick")

	TreeManager.dbg_best_tree_paths = 0
	var second: TreeResource = w.tm.best_tree(origin, origin, 50.0, false)
	check(TreeManager.dbg_best_tree_paths == 1,
		"second search skips the cached negatives (1 A* for the plateau tree)")
	check(second == plateau,
		"the budget moves past cached negatives to the reachable tree")
	_free_world(w)


## A cached NO_PATH verdict dies with the next walkability change — a
## construction footprint that blocked the way must not ban a tree for long.
func test_no_path_verdict_invalidated_by_grid_change() -> void:
	var w: Dictionary = _make_world()
	var tree: TreeResource = w.tm.spawn_tree(Vector2i(38, 66), 3)
	var origin: Vector3 = _edge_pos(w)
	var bucket: Vector2i = w.nav.world_to_cell(origin)
	bucket = Vector2i(bucket.x >> TreeManager.VERDICT_BUCKET_SHIFT,
		bucket.y >> TreeManager.VERDICT_BUCKET_SHIFT)
	var key: Vector4i = Vector4i(bucket.x, bucket.y, 38, 66)
	var now: int = Time.get_ticks_msec()

	# Seed a fresh NO_PATH verdict: the search skips the tree without an A*.
	w.tm._verdict_cache[key] = [TreeManager.VERDICT_NO_PATH, now + 100000,
		w.nav.change_version]
	check(w.tm.best_tree(origin, origin, 50.0, false) == null,
		"a fresh NO_PATH verdict suppresses the tree")

	# Any walkability change bumps change_version -> verdict is stale.
	w.nav.update_region(Rect2i(100, 100, 2, 2))
	check(w.tm.best_tree(origin, origin, 50.0, false) == tree,
		"a grid change invalidates the NO_PATH verdict immediately")

	# An expired verdict (TTL) is also re-checked.
	w.tm._verdict_cache[key] = [TreeManager.VERDICT_NO_PATH, now - 1,
		w.nav.change_version]
	check(w.tm.best_tree(origin, origin, 50.0, false) == tree,
		"an expired verdict is re-checked")
	_free_world(w)
