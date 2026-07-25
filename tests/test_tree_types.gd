extends TestBase

## Headless tests for the tree types (standard / leaf / bamboo): ground-band
## dependent growth and reproduction, bamboo's stage-2 cap and yield, sprout
## type inheritance, the grass-flag cache invalidation and the typed map-gen
## start distribution (spawn_trees shares + spawn_groves).


## Flat map at height h: 5.0 lies in the grass band, 3.0 is walkable sand.
func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


## Grass (x <= split_x) / sand split with the boundary column unwalkable
## (slope > MAX_SLOPE), so sprout candidates are cleanly grass or sand.
func _split_terrain(split_x: int = 64) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for z in range(td.verts):
		for x in range(td.verts):
			td.heights[z * td.verts + x] = 5.0 if x <= split_x else 3.0
	return td


func _make_tm(td: TerrainData) -> Dictionary:
	var nav: NavGrid = NavGrid.new(td)
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	return {"td": td, "nav": nav, "tm": tm}


# --- Growth factors -------------------------------------------------------------

func test_leaf_grows_faster_on_grass() -> void:
	var w: Dictionary = _make_tm(_flat_terrain(5.0))
	var standard: TreeResource = w.tm.spawn_tree(Vector2i(20, 20), 1)
	var leaf: TreeResource = w.tm.spawn_tree(
		Vector2i(40, 40), 1, TreeResource.TreeType.LEAF)
	check(standard.on_grass and leaf.on_grass, "both trees sit on grass")
	standard.growth_timer = 10.0
	leaf.growth_timer = 10.0
	for i in range(7):
		standard.grow_tick(1.0)
		leaf.grow_tick(1.0)
	check(leaf.stage == 2, "leaf on grass grew (factor 1.5: 7 ticks x 1.5 > 10)")
	check(standard.stage == 1, "standard did not grow yet (7 ticks x 1.0 < 10)")
	w.tm.free()


func test_leaf_grows_slower_off_grass() -> void:
	var w: Dictionary = _make_tm(_flat_terrain(3.0))
	var standard: TreeResource = w.tm.spawn_tree(Vector2i(20, 20), 1)
	var leaf: TreeResource = w.tm.spawn_tree(
		Vector2i(40, 40), 1, TreeResource.TreeType.LEAF)
	check(not standard.on_grass and not leaf.on_grass, "both trees sit on sand")
	standard.growth_timer = 10.0
	leaf.growth_timer = 10.0
	for i in range(10):
		standard.grow_tick(1.0)
		leaf.grow_tick(1.0)
	check(standard.stage == 2, "standard grew off grass (factor 1.0)")
	check(leaf.stage == 1, "leaf off grass is slower (10 ticks x 0.75 < 10)")
	w.tm.free()


# --- Bamboo ----------------------------------------------------------------------

func test_bamboo_caps_at_stage_two_and_two_wood() -> void:
	var w: Dictionary = _make_tm(_flat_terrain(5.0))
	var bamboo: TreeResource = w.tm.spawn_tree(
		Vector2i(30, 30), 4, TreeResource.TreeType.BAMBOO)
	check(bamboo.stage == 2, "spawn stage is clamped to the bamboo max stage 2")
	check(bamboo.wood_yield() == 2, "stage 2 bamboo holds 2 wood")
	bamboo.growth_timer = 0.5
	for i in range(5):
		bamboo.grow_tick(1.0)
	check(bamboo.stage == 2, "bamboo never grows past stage 2")
	var wood: int = bamboo.harvest_one() + bamboo.harvest_one()
	check(wood == 2 and bamboo.felled_flag, "bamboo yields exactly 2 wood in total")
	w.tm.free()


func test_bamboo_dead_on_sand() -> void:
	var w: Dictionary = _make_tm(_flat_terrain(3.0))
	var bamboo: TreeResource = w.tm.spawn_tree(
		Vector2i(30, 30), 1, TreeResource.TreeType.BAMBOO)
	check(not bamboo.on_grass, "bamboo registered as off-grass")
	bamboo.growth_timer = 1.0
	for i in range(50):
		bamboo.grow_tick(1.0)
	check(bamboo.stage == 1, "bamboo off grass does not grow (factor 0)")
	for i in range(60):
		w.tm._reproduce()
	check(w.tm.trees.size() == 1, "bamboo off grass never reproduces (factor 0)")
	w.tm.free()


func test_bamboo_sprouts_only_on_grass() -> void:
	var w: Dictionary = _make_tm(_split_terrain(64))
	w.tm.spawn_tree(Vector2i(62, 60), 2, TreeResource.TreeType.BAMBOO)
	for i in range(30):
		w.tm._sprout_near(Vector2i(62, 60), TreeResource.TreeType.BAMBOO)
	check(w.tm.trees.size() > 1, "sprouting at the grass/sand border produced trees")
	for tree: TreeResource in w.tm._tree_cells.keys():
		var c: Vector2i = w.tm._tree_cells[tree]
		check(w.td.is_grass(c), "tree at %s sits on grass" % c)
	w.tm.free()


# --- Inheritance & compatibility ---------------------------------------------------

func test_sprout_inherits_type() -> void:
	var w: Dictionary = _make_tm(_flat_terrain(5.0))
	var parent: TreeResource = w.tm.spawn_tree(
		Vector2i(60, 60), 3, TreeResource.TreeType.LEAF)
	for i in range(30):
		w.tm._sprout_near(Vector2i(60, 60), parent.type)
	check(w.tm.trees.size() > 1, "leaf parent produced sprouts")
	for tree: TreeResource in w.tm.trees:
		check(tree.type == TreeResource.TreeType.LEAF, "sprout inherited LEAF type")
	w.tm.free()


func test_spawn_tree_defaults_to_standard() -> void:
	var w: Dictionary = _make_tm(_flat_terrain(5.0))
	var tree: TreeResource = w.tm.spawn_tree(Vector2i(20, 20), 2)
	check(tree.type == TreeResource.TreeType.STANDARD,
		"two-argument spawn_tree stays STANDARD (forester compatibility)")
	check(tree.stage == 2, "stage argument unchanged")
	w.tm.free()


# --- Grass cache -------------------------------------------------------------------

func test_grass_cache_invalidated_on_deformation() -> void:
	var w: Dictionary = _make_tm(_flat_terrain(5.0))
	var cell: Vector2i = Vector2i(30, 30)
	var leaf: TreeResource = w.tm.spawn_tree(cell, 2, TreeResource.TreeType.LEAF)
	check(leaf.on_grass, "leaf starts on grass")
	# Raise the cell's four corner verts above the grass band (rock height).
	for dz in range(2):
		for dx in range(2):
			w.td.heights[(cell.y + dz) * w.td.verts + cell.x + dx] = 12.0
	w.tm._on_terrain_deformed(Rect2i(cell, Vector2i(1, 1)))
	check(not leaf.on_grass, "deformation refreshed the cached grass flag")
	w.tm.free()


# --- Map generation ------------------------------------------------------------------

func test_map_gen_rolls_all_types_on_grass() -> void:
	var w: Dictionary = _make_tm(_flat_terrain(5.0))
	w.tm.spawn_trees(120, 12345)
	w.tm.spawn_groves(3)
	var seen: Dictionary = {}
	for tree: TreeResource in w.tm.trees:
		seen[tree.type] = true
	check(seen.has(TreeResource.TreeType.STANDARD), "map gen placed standard trees")
	check(seen.has(TreeResource.TreeType.LEAF), "map gen placed leaf trees")
	check(seen.has(TreeResource.TreeType.BAMBOO), "map gen placed bamboo")
	w.tm.free()


func test_map_gen_standard_only_on_sand() -> void:
	var w: Dictionary = _make_tm(_flat_terrain(3.0))
	w.tm.spawn_trees(60, 12345)
	w.tm.spawn_groves(3)
	check(w.tm.trees.size() >= 60, "wild distribution spawned on sand")
	for tree: TreeResource in w.tm.trees:
		check(tree.type == TreeResource.TreeType.STANDARD,
			"off-grass map gen only places standard trees")
	w.tm.free()
