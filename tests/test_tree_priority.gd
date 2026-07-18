extends TestBase

## Bug-Backlog #4: the tree search preferred the beeline-nearest tree even when
## it stands below a cliff (reachable only via a long ramp detour), instead of a
## same-level tree slightly farther away. _nearest now adds a height-detour
## malus (HEIGHT_DETOUR_PENALTY per metre of height difference).

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
