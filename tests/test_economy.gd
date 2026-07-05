extends TestBase

## Headless tests for the economy: mana formula, tree growth/reproduction,
## wood piles, plot validation, the two-phase construction flow (flatten ->
## build with delivered wood), hut spawning, worker recruiting and manual
## chopping. All nodes are created outside the scene tree and freed manually.

const TICK: float = 0.05
const MAX_TICKS: int = 20000

const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const SITE_SCENE: PackedScene = preload("res://scenes/buildings/reincarnation_site.tscn")
const TREE_SCENE: PackedScene = preload("res://scenes/tree_resource.tscn")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


## Full standalone world: flat walkable terrain + managers wired like in Main.
func _make_world() -> Dictionary:
	var td: TerrainData = _flat_terrain()
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
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(nav, bm, um, tm)
	return {
		"td": td, "nav": nav, "tribe": tribe,
		"unit_manager": um, "building_manager": bm,
		"tree_manager": tm, "wood_pile_manager": wpm, "commands": tc,
	}


func _free_world(w: Dictionary) -> void:
	w.commands.free()
	w.tree_manager.free()        # frees spawned trees (children)
	w.wood_pile_manager.free()   # frees piles (children)
	w.building_manager.free()    # frees placed buildings (children)
	w.unit_manager.free()        # frees spawned units (children)


# --- Mana formula -----------------------------------------------------------------

func test_mana_formula() -> void:
	var tribe: Tribe = Tribe.new(0)
	var braves: Array[Brave] = []
	for i in range(5):
		var brave: Brave = Brave.new()
		braves.append(brave)
		tribe.add_unit(brave)
	# Two of them are praying (state + arrived flag as set by _tick_pray).
	for i in range(2):
		braves[i].state = Unit.State.PRAY
		braves[i]._working = true
	check(tribe.praying_braves() == 2, "praying_braves counts working PRAY braves")

	tribe.tick(1.0)
	check_near(tribe.mana,
		5.0 * Tribe.MANA_BASE_RATE + 2.0 * Tribe.MANA_PRAY_BONUS,
		"mana after tick(1.0) matches population * base + praying * bonus")

	var big_tribe: Tribe = Tribe.new(1)
	var extra: Array[Brave] = []
	for i in range(10):
		var brave: Brave = Brave.new()
		extra.append(brave)
		big_tribe.add_unit(brave)
	big_tribe.tick(1.0)
	check_near(big_tribe.mana, 10.0 * Tribe.MANA_BASE_RATE,
		"10 units without praying yield exactly the base rate")
	check(big_tribe.mana > 5.0 * Tribe.MANA_BASE_RATE,
		"more population means more base mana")

	for brave in braves:
		brave.free()
	for brave in extra:
		brave.free()


# --- Trees: growth stages & reproduction -----------------------------------------------

func test_tree_growth_and_yield() -> void:
	var tree: TreeResource = TREE_SCENE.instantiate() as TreeResource
	tree.set_stage(0)
	check(tree.wood_yield() == 1, "small tree yields 1 wood")
	tree.grow_tick(TreeResource.GROWTH_TIME + 0.1)
	check(tree.stage == 1, "tree grows to stage 1 after GROWTH_TIME")
	check(tree.wood_yield() == 1, "stage 1 tree yields 1 wood")
	tree.grow_tick(TreeResource.GROWTH_TIME + 0.1)
	check(tree.stage == 2, "tree grows to stage 2")
	check(tree.wood_yield() == 2, "stage 2 tree yields 2 wood")
	tree.grow_tick(TreeResource.GROWTH_TIME + 0.1)
	check(tree.stage == 3, "tree grows to stage 3 (max)")
	check(tree.wood_yield() == 3, "big tree yields 3 wood")
	tree.grow_tick(TreeResource.GROWTH_TIME * 5.0)
	check(tree.stage == 3, "tree never grows past the max stage")
	check(tree.chop_time() > 2.9, "big trees take longer to fell")
	tree.free()


func test_tree_reproduction() -> void:
	var w: Dictionary = _make_world()
	var tm: TreeManager = w.tree_manager
	tm._rng.seed = 42
	# Small wood: reproduction chance scales with the neighbour count.
	for c: Vector2i in [Vector2i(60, 60), Vector2i(63, 60), Vector2i(60, 63),
			Vector2i(63, 63), Vector2i(66, 61)]:
		tm.spawn_tree(c, 2)
	var initial: int = tm.trees.size()
	for i in range(6000):   # 300 simulated seconds
		tm.tick(TICK)
	check(tm.trees.size() > initial, "a dense wood seeds new trees over time")
	check(tm.trees.size() <= TreeManager.MAX_TREES, "global tree cap holds")
	# New trees always sprout small.
	var found_small: bool = false
	for tree in tm.trees:
		if tree.stage == 0:
			found_small = true
	check(found_small, "sprouted trees start at stage 0")
	_free_world(w)


# --- Wood piles ---------------------------------------------------------------------

func test_wood_piles() -> void:
	var w: Dictionary = _make_world()
	var wpm: WoodPileManager = w.wood_pile_manager
	var pos: Vector3 = Vector3(50.0, 5.0, 50.0)

	wpm.deposit(pos, 7)
	check(wpm.total_wood() == 7, "deposit stores all wood")
	check(wpm.piles.size() == 2, "7 wood spreads over 2 piles (max 5 each)")
	for pile in wpm.piles:
		check(pile.amount <= WoodPile.MAX_AMOUNT, "no pile exceeds the maximum")

	var taken: int = wpm.take_from_radius(pos, 6.0, 4)
	check(taken == 4, "take_from_radius returns the requested amount")
	check(wpm.total_wood() == 3, "remaining wood is correct")
	taken = wpm.take_from_radius(pos, 6.0, 100)
	check(taken == 3, "taking more than available yields the rest")
	check(wpm.total_wood() == 0, "piles are empty afterwards")
	check(wpm.piles.is_empty(), "empty piles are removed")
	_free_world(w)


# --- Plot validation -----------------------------------------------------------------

func test_place_building_validation() -> void:
	var w: Dictionary = _make_world()
	var td: TerrainData = w.td
	var tribe: Tribe = w.tribe
	var tc: TribeCommands = w.commands

	# Water: sink a corner region below sea level.
	for vz in range(0, 12):
		for vx in range(0, 12):
			td.set_vertex_height(vx, vz, 0.5)
	w.nav.update_region(Rect2i(0, 0, 12, 12))
	check(tc.place_building(tribe, HUT_SCENE, Vector2i(2, 2)) == null,
		"placement on water is rejected")

	# Too uneven: a steep spike exceeds MAX_LEVEL_DIFF.
	td.raise_area(Vector2(100.0, 100.0), 3.0, 5.0)
	check(tc.place_building(tribe, HUT_SCENE, Vector2i(98, 98)) == null,
		"placement on too-uneven terrain is rejected")

	# Valid plot.
	var hut: Building = tc.place_building(tribe, HUT_SCENE, Vector2i(60, 60))
	check(hut != null, "placement on a flat plot succeeds")
	check(hut.under_construction, "building starts as a construction site")
	check(not hut.foundation_done, "foundation is not levelled yet")
	check(not w.nav.is_cell_walkable(Vector2i(60, 60)), "footprint cells are nav-solid")

	# Overlap.
	check(tc.place_building(tribe, HUT_SCENE, Vector2i(61, 61)) == null,
		"overlapping footprint is rejected")

	# Orientation reaches the building.
	var hut2: Building = tc.place_building(tribe, HUT_SCENE, Vector2i(80, 80), 1)
	check(hut2 != null and hut2.orientation == 1, "orientation is stored")
	check(hut2.entrance_cell() == Vector2i(84, 82), "east entrance cell is outside the footprint")
	_free_world(w)


# --- Construction flow: flatten -> chop/deliver -> build --------------------------------

func test_flatten_and_construct_flow() -> void:
	var w: Dictionary = _make_world()
	var td: TerrainData = w.td
	var tribe: Tribe = w.tribe
	var bm: BuildingManager = w.building_manager

	# Bumpy but placeable plot.
	td.raise_area(Vector2(62.0, 62.0), 3.0, 1.5)
	w.nav.update_region(Rect2i(56, 56, 12, 12))

	var hut: Hut = w.commands.place_building(tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	check(hut != null, "construction site placed on bumpy plot")
	check(hut.needs_flatten(), "bumpy foundation needs flattening")

	# Enough big trees nearby (7 x 3 = 21 >= 20 wood).
	for c: Vector2i in [Vector2i(53, 60), Vector2i(53, 63), Vector2i(56, 67),
			Vector2i(67, 56), Vector2i(68, 60), Vector2i(67, 66), Vector2i(60, 53)]:
		w.tree_manager.spawn_tree(c, 3)

	var braves: Array[Brave] = []
	for i in range(3):
		var brave: Brave = w.unit_manager.spawn_unit(
			BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(56 + i, 58))) as Brave
		brave.order_build(hut)
		braves.append(brave)
	check(hut.workers.size() == 3, "all three braves joined the job")

	var ticks: int = 0
	while hut.under_construction and ticks < MAX_TICKS:
		bm.tick(TICK)
		for brave in braves:
			brave.tick(TICK)
		ticks += 1
	check(not hut.under_construction, "construction finishes (took %d ticks)" % ticks)
	check(hut.foundation_done, "foundation was levelled")
	check(hut.wood_delivered == Hut.WOOD_COST, "all wood was delivered and absorbed")
	# The footprint terrain is flat at the target height.
	var flat_ok: bool = true
	for vz in range(60, 65):
		for vx in range(60, 65):
			if absf(td.vertex_height(vx, vz) - hut.flatten_target) > 0.05:
				flat_ok = false
	check(flat_ok, "footprint vertices sit at the flatten target")
	# Workers are released.
	for brave in braves:
		brave.tick(TICK)
	var all_idle: bool = true
	for brave in braves:
		if brave.state != Unit.State.IDLE:
			all_idle = false
	check(all_idle, "workers go IDLE after the job is done")
	check(hut.workers.is_empty(), "worker list is empty after completion")
	_free_world(w)


func test_progress_requires_wood() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribe
	var bm: BuildingManager = w.building_manager

	# Flat plot, no trees anywhere -> foundation gets done, build stalls at 0.
	var hut: Hut = w.commands.place_building(tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(57, 60))) as Brave
	brave.order_build(hut)

	var ticks: int = 0
	while not hut.foundation_done and ticks < MAX_TICKS:
		bm.tick(TICK)
		brave.tick(TICK)
		ticks += 1
	check(hut.foundation_done, "flat foundation is levelled quickly")

	for i in range(400):   # 20 simulated seconds
		bm.tick(TICK)
		brave.tick(TICK)
	check(hut.under_construction, "without wood the build cannot finish")
	check_near(hut.build_progress, 0.0, "progress is capped at the delivered fraction (0)")

	# Deliver all wood as piles at the entrance -> absorbed -> build finishes.
	w.wood_pile_manager.deposit(hut.entrance_world(), Hut.WOOD_COST)
	ticks = 0
	while hut.under_construction and ticks < MAX_TICKS:
		bm.tick(TICK)
		brave.tick(TICK)
		ticks += 1
	check(not hut.under_construction, "build finishes once the wood is on site")
	check(hut.wood_delivered == Hut.WOOD_COST, "the piles were absorbed into the site")
	_free_world(w)


# --- Hut spawning ------------------------------------------------------------------

func test_hut_spawns_braves_until_capacity() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribe

	var hut: Hut = w.building_manager.place(
		HUT_SCENE, tribe, Vector2i(60, 60), 0, true) as Hut
	check(hut != null, "hut placed")
	check(tribe.housing_capacity() == Hut.CAPACITY, "capacity of one hut is %d" % Hut.CAPACITY)

	var t: float = 0.0
	while t < Hut.SPAWN_INTERVAL + 0.5 and tribe.population() == 0:
		hut.tick(TICK)
		t += TICK
	check(tribe.population() == 1, "one brave after one spawn interval")

	var dummies: Array[Unit] = []
	while tribe.population() < Hut.CAPACITY:
		var u: Unit = Unit.new()
		dummies.append(u)
		tribe.add_unit(u)
	for i in range(int(Hut.SPAWN_INTERVAL / TICK) * 3):
		hut.tick(TICK)
	check(tribe.population() == Hut.CAPACITY, "no spawns above the housing capacity")

	var hut2: Hut = w.building_manager.place(
		HUT_SCENE, tribe, Vector2i(70, 60), 0, true) as Hut
	check(tribe.housing_capacity() == 2 * Hut.CAPACITY, "second hut doubles the capacity")
	for i in range(int(Hut.SPAWN_INTERVAL / TICK) + 10):
		hut.tick(TICK)
	check(tribe.population() == Hut.CAPACITY + 1, "spawning continues with more capacity")
	check(hut2 != null, "second hut placed")

	for u in dummies:
		u.free()
	_free_world(w)


# --- Worker recruiting -----------------------------------------------------------------

func test_idle_braves_are_recruited() -> void:
	var w: Dictionary = _make_world()
	var bm: BuildingManager = w.building_manager

	var hut: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	var idle_brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(55, 60))) as Brave
	var praying: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(56, 60))) as Brave
	praying.state = Unit.State.PRAY   # busy braves must not be drafted
	w.unit_manager.tick(TICK)         # refresh the spatial hash

	bm.tick(BuildingManager.RECRUIT_INTERVAL + 0.1)
	check(idle_brave.state == Unit.State.BUILD, "idle brave is recruited to the site")
	check(idle_brave.job == hut, "recruited brave points at the job")
	check(praying.state == Unit.State.PRAY, "busy braves are left alone")
	_free_world(w)


# --- Manual chopping --------------------------------------------------------------------

func test_manual_chop_leaves_piles() -> void:
	var w: Dictionary = _make_world()
	var tm: TreeManager = w.tree_manager
	var wpm: WoodPileManager = w.wood_pile_manager

	var tree1: TreeResource = tm.spawn_tree(Vector2i(60, 60), 3)   # yield 3
	var tree2: TreeResource = tm.spawn_tree(Vector2i(63, 60), 2)   # yield 2, within chain radius
	check(tree2 != null, "second tree spawned")

	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(57, 60))) as Brave
	brave.order_chop(tree1)
	check(brave.state == Unit.State.GATHER, "brave is chopping after the order")

	var ticks: int = 0
	while brave.state != Unit.State.IDLE and ticks < MAX_TICKS:
		brave.tick(TICK)
		ticks += 1
	check(brave.state == Unit.State.IDLE, "brave stops when no tree is in reach")
	check(tm.trees.is_empty(), "both trees were felled (chain chopping)")
	check(wpm.total_wood() == 5, "the yield lies in piles on the ground (got %d)" % wpm.total_wood())
	check(brave.carried_wood == 0, "brave carries nothing afterwards")
	_free_world(w)
