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


# --- Growth (continuous, deterministic) --------------------------------------------

func test_growth_rate_by_type_and_ground() -> void:
	var base: float = 1.0 / TreeResource.GROWTH_TIME
	var grass: Dictionary = _make_tm(_flat_terrain(5.0))
	var standard_g: TreeResource = grass.tm.spawn_tree(Vector2i(20, 20), 1)
	var leaf_g: TreeResource = grass.tm.spawn_tree(
		Vector2i(40, 40), 1, TreeResource.TreeType.LEAF)
	check_near(standard_g.growth_rate(), base, "standard on grass grows at the base rate")
	check_near(leaf_g.growth_rate(), base * 1.5, "leaf on grass grows 1.5x")
	var sand: Dictionary = _make_tm(_flat_terrain(3.0))
	var standard_s: TreeResource = sand.tm.spawn_tree(Vector2i(20, 20), 1)
	var leaf_s: TreeResource = sand.tm.spawn_tree(
		Vector2i(40, 40), 1, TreeResource.TreeType.LEAF)
	var bamboo_s: TreeResource = sand.tm.spawn_tree(
		Vector2i(60, 60), 1, TreeResource.TreeType.BAMBOO)
	check_near(standard_s.growth_rate(), base, "standard off grass keeps the base rate")
	check_near(leaf_s.growth_rate(), base * 0.75, "leaf off grass grows 0.75x")
	check_near(bamboo_s.growth_rate(), 0.0, "bamboo off grass grows 0 (pause)")
	grass.tm.free()
	sand.tm.free()


func test_growth_is_continuous_and_deterministic() -> void:
	var w: Dictionary = _make_tm(_flat_terrain(5.0))
	var tree: TreeResource = w.tm.spawn_tree(Vector2i(20, 20), 1)
	# Half a stage time: wood stage unchanged, model scale strictly between
	# the two neighbouring stage scales (continuous visual growth).
	tree.grow_tick(TreeResource.GROWTH_TIME * 0.5)
	check(tree.stage == 1, "half a stage time keeps the wood stage")
	check(tree.growth > 1.45 and tree.growth < 1.55, "growth progressed continuously")
	var s1: float = float(Balance.TREE_TYPE_PARAMS[0].stage_scales[1])
	var s2: float = float(Balance.TREE_TYPE_PARAMS[0].stage_scales[2])
	check(tree.scale.x > s1 and tree.scale.x < s2,
		"model scale sits between the stage scales")
	tree.grow_tick(TreeResource.GROWTH_TIME * 0.51)
	check(tree.stage == 2, "one full stage time advances exactly one wood stage")
	w.tm.free()


func test_growth_scale_updates_quantized() -> void:
	# A single 30-Hz tick moves growth far below GROWTH_SCALE_QUANT — the
	# transform must NOT be touched every tick (update budget), but it must
	# move once enough growth accumulated.
	var w: Dictionary = _make_tm(_flat_terrain(5.0))
	var tree: TreeResource = w.tm.spawn_tree(Vector2i(20, 20), 1)
	var before: float = tree.scale.x
	tree.grow_tick(1.0 / 30.0)
	check(tree.growth > 1.0, "growth advanced on the tick")
	check_near(tree.scale.x, before, "scale untouched below the quantisation step")
	tree.grow_tick(10.0)
	check(tree.scale.x > before, "scale advanced after enough growth")
	w.tm.free()


# --- Bamboo ----------------------------------------------------------------------

func test_bamboo_caps_at_stage_two_and_two_wood() -> void:
	var w: Dictionary = _make_tm(_flat_terrain(5.0))
	var bamboo: TreeResource = w.tm.spawn_tree(
		Vector2i(30, 30), 4, TreeResource.TreeType.BAMBOO)
	check(bamboo.stage == 2, "spawn stage is clamped to the bamboo max stage 2")
	check(bamboo.wood_yield() == 2, "stage 2 bamboo holds 2 wood")
	bamboo.grow_tick(TreeResource.GROWTH_TIME * 100.0)
	check(bamboo.stage == 2, "bamboo never grows past stage 2")
	var wood: int = bamboo.harvest_one() + bamboo.harvest_one()
	check(wood == 2 and bamboo.felled_flag, "bamboo yields exactly 2 wood in total")
	w.tm.free()


func test_bamboo_dead_on_sand() -> void:
	var w: Dictionary = _make_tm(_flat_terrain(3.0))
	var bamboo: TreeResource = w.tm.spawn_tree(
		Vector2i(30, 30), 1, TreeResource.TreeType.BAMBOO)
	check(not bamboo.on_grass, "bamboo registered as off-grass")
	bamboo.grow_tick(TreeResource.GROWTH_TIME * 10.0)
	check(bamboo.stage == 1, "bamboo off grass does not grow (rate 0)")
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
	# Start trees get a spread growth fraction so their (deterministic) wood
	# stage boundaries do not line up in sync.
	var fractional: int = 0
	for tree: TreeResource in w.tm.trees:
		if absf(tree.growth - roundf(tree.growth)) > 0.01:
			fractional += 1
	check(fractional > 0, "wild start trees carry spread growth fractions")
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
