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


# --- Growth (probabilistic rolls) -------------------------------------------------

func test_growth_chance_by_type_and_ground() -> void:
	var base: float = TreeResource.GROWTH_ROLL_INTERVAL / TreeResource.GROWTH_TIME
	var grass: Dictionary = _make_tm(_flat_terrain(5.0))
	var standard_g: TreeResource = grass.tm.spawn_tree(Vector2i(20, 20), 1)
	var leaf_g: TreeResource = grass.tm.spawn_tree(
		Vector2i(40, 40), 1, TreeResource.TreeType.LEAF)
	check_near(standard_g.growth_chance(), base, "standard on grass rolls the base chance")
	check_near(leaf_g.growth_chance(), base * 1.5, "leaf on grass rolls 1.5x")
	var sand: Dictionary = _make_tm(_flat_terrain(3.0))
	var standard_s: TreeResource = sand.tm.spawn_tree(Vector2i(20, 20), 1)
	var leaf_s: TreeResource = sand.tm.spawn_tree(
		Vector2i(40, 40), 1, TreeResource.TreeType.LEAF)
	var bamboo_s: TreeResource = sand.tm.spawn_tree(
		Vector2i(60, 60), 1, TreeResource.TreeType.BAMBOO)
	check_near(standard_s.growth_chance(), base, "standard off grass keeps the base chance")
	check_near(leaf_s.growth_chance(), base * 0.75, "leaf off grass rolls 0.75x")
	check_near(bamboo_s.growth_chance(), 0.0, "bamboo off grass rolls 0 (pause)")
	grass.tm.free()
	sand.tm.free()


func test_growth_mean_rate_preserved() -> void:
	# Many seeded stage-1 -> stage-2 runs: the MEAN tick count must stay close
	# to GROWTH_TIME (the roll chance is calibrated to preserve the old rate).
	var w: Dictionary = _make_tm(_flat_terrain(5.0))
	var tree: TreeResource = w.tm.spawn_tree(Vector2i(20, 20), 1)
	TreeResource.growth_rng.seed = 20260725
	var samples: int = 200
	var total_ticks: int = 0
	for i in range(samples):
		tree.set_stage(1)
		tree.growth_timer = TreeResource.GROWTH_ROLL_INTERVAL
		var guard: int = 0
		while tree.stage == 1 and guard < 100000:
			tree.grow_tick(1.0)
			guard += 1
		total_ticks += guard
	var mean: float = float(total_ticks) / float(samples)
	check(absf(mean - TreeResource.GROWTH_TIME) < TreeResource.GROWTH_TIME * 0.15,
		"mean stage time stays near GROWTH_TIME (got %.1f, want ~%.0f)"
			% [mean, TreeResource.GROWTH_TIME])
	w.tm.free()


func test_growth_roll_phases_desynced() -> void:
	# Trees created in the same frame start with different roll offsets — no
	# synchronised growth frame for the whole starting forest.
	var offsets: Dictionary = {}
	for i in range(8):
		var tree: TreeResource = TreeResource.new()
		offsets[snappedf(tree.growth_timer, 0.0001)] = true
		tree.free()
	check(offsets.size() > 1, "spawn-time roll phases differ between trees")


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
