extends TestBase

## Headless tests for phase 3: mana formula, wood harvesting (incl. the brave
## gather cycle), hut spawning, TribeCommands.place_building and construction
## progress. All nodes are created outside the scene tree and freed manually.

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
## Callers must free world.unit_manager/building_manager/tree_manager/commands.
func _make_world() -> Dictionary:
	var td: TerrainData = _flat_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var tribe: Tribe = Tribe.new(0)
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe] as Array[Tribe], tm)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um)
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(nav, bm, um, tm)
	return {
		"td": td, "nav": nav, "tribe": tribe,
		"unit_manager": um, "building_manager": bm,
		"tree_manager": tm, "commands": tc,
	}


func _free_world(w: Dictionary) -> void:
	w.commands.free()
	w.tree_manager.free()      # frees spawned trees (children)
	w.building_manager.free()  # frees placed buildings (children)
	w.unit_manager.free()      # frees spawned units (children)


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

	# More population -> more mana per tick.
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


# --- Wood harvesting ----------------------------------------------------------------

func test_tree_harvest() -> void:
	var tree: TreeResource = TREE_SCENE.instantiate() as TreeResource
	tree.wood_remaining = 40
	var depleted_count: Array[int] = [0]
	tree.depleted.connect(func(_t: TreeResource) -> void: depleted_count[0] += 1)

	check(tree.harvest(10) == 10, "harvest returns the requested amount")
	check(tree.wood_remaining == 30, "wood_remaining is reduced")
	check(tree.harvest(1000) == 30, "harvest never returns more than remaining")
	check(tree.wood_remaining == 0, "tree is empty afterwards")
	check(depleted_count[0] == 1, "depleted emitted exactly once")
	check(tree.harvest(5) == 0, "empty tree yields nothing")
	check(depleted_count[0] == 1, "no second depleted emission")
	tree.free()


func test_brave_gather_cycle() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribe
	var tm: TreeManager = w.tree_manager

	var tree: TreeResource = w.tree_manager.spawn_tree(Vector2i(60, 60))
	tree.wood_remaining = 6

	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(55, 60))) as Brave
	brave.order_gather(tree)
	check(brave.state == Unit.State.GATHER, "brave is in GATHER after the order")

	var ticks: int = 0
	while tribe.wood == 0 and ticks < MAX_TICKS:
		brave.tick(TICK)
		ticks += 1
	check(tribe.wood > 0, "gathering credits wood to the tribe")

	while (tm.trees.size() > 0) and ticks < MAX_TICKS:
		brave.tick(TICK)
		ticks += 1
	check(tm.trees.is_empty(), "depleted tree is deregistered from the TreeManager")
	check(tribe.wood == 6, "all of the tree's wood ended up at the tribe (got %d)" % tribe.wood)

	# No trees left -> the brave stops gathering.
	for i in range(20):
		brave.tick(TICK)
	check(brave.state == Unit.State.IDLE, "brave goes IDLE when no tree is left")
	_free_world(w)


# --- Hut spawning ------------------------------------------------------------------

func test_hut_spawns_braves_until_capacity() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribe

	var hut: Hut = w.building_manager.place(HUT_SCENE, tribe, Vector2i(60, 60), true) as Hut
	check(hut != null, "hut placed")
	check(tribe.housing_capacity() == Hut.CAPACITY, "capacity of one hut is %d" % Hut.CAPACITY)

	# One spawn interval -> exactly one new brave.
	var t: float = 0.0
	while t < Hut.SPAWN_INTERVAL + 0.5 and tribe.population() == 0:
		hut.tick(TICK)
		t += TICK
	check(tribe.population() == 1, "one brave after one spawn interval")

	# Fill up to capacity with dummy units -> no further spawns.
	var dummies: Array[Unit] = []
	while tribe.population() < Hut.CAPACITY:
		var u: Unit = Unit.new()
		dummies.append(u)
		tribe.add_unit(u)
	for i in range(int(Hut.SPAWN_INTERVAL / TICK) * 3):
		hut.tick(TICK)
	check(tribe.population() == Hut.CAPACITY, "no spawns above the housing capacity")

	# A second hut raises the capacity -> spawning continues.
	var hut2: Hut = w.building_manager.place(HUT_SCENE, tribe, Vector2i(70, 60), true) as Hut
	check(tribe.housing_capacity() == 2 * Hut.CAPACITY, "second hut doubles the capacity")
	for i in range(int(Hut.SPAWN_INTERVAL / TICK) + 10):
		hut.tick(TICK)
	check(tribe.population() == Hut.CAPACITY + 1, "spawning continues with more capacity")
	check(hut2 != null, "second hut placed")

	for u in dummies:
		u.free()
	_free_world(w)


# --- place_building -----------------------------------------------------------------

func test_place_building_validation() -> void:
	# Island terrain so there are real water cells for the invalid case.
	var td: TerrainData = TerrainData.new()
	td.generate_island(1337)
	var nav: NavGrid = NavGrid.new(td)
	var tribe: Tribe = Tribe.new(0)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe] as Array[Tribe], null)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um)
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(nav, bm, um, null)

	tribe.wood = 100
	var center: Vector2i = Vector2i(TerrainData.SIZE / 2, TerrainData.SIZE / 2)

	var hut: Building = tc.place_building(tribe, HUT_SCENE, center)
	check(hut != null, "placement with enough wood succeeds")
	check(tribe.wood == 100 - Hut.WOOD_COST, "wood reduced by the hut cost")
	check(not nav.is_cell_walkable(center), "footprint cells are solid in the NavGrid")

	# Same spot again -> occupied -> null, wood unchanged.
	var before: int = tribe.wood
	check(tc.place_building(tribe, HUT_SCENE, center) == null,
		"occupied footprint is rejected")
	check(tribe.wood == before, "no wood deducted on rejection")

	# Water cell (island corner is below sea level).
	check(tc.place_building(tribe, HUT_SCENE, Vector2i(0, 0)) == null,
		"placement on water is rejected")
	check(tribe.wood == before, "no wood deducted for water placement")

	# Not enough wood.
	tribe.wood = Hut.WOOD_COST - 1
	check(tc.place_building(tribe, HUT_SCENE, center + Vector2i(6, 0)) == null,
		"placement without enough wood is rejected")
	check(tribe.wood == Hut.WOOD_COST - 1, "wood unchanged when too poor")

	tc.free()
	bm.free()
	um.free()


# --- Construction progress -----------------------------------------------------------

func test_build_progress_via_brave() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribe
	tribe.wood = 100

	var hut: Hut = w.commands.place_building(tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	check(hut != null, "construction site placed")
	check(hut.under_construction, "building starts under construction")
	check(tribe.housing_capacity() == 0, "unfinished hut provides no capacity")

	# An unfinished hut must not spawn.
	for i in range(int(Hut.SPAWN_INTERVAL / TICK) * 2):
		hut.tick(TICK)
	check(tribe.population() == 0, "unfinished hut does not spawn braves")

	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(56, 60))) as Brave
	brave.order_build(hut)
	var ticks: int = 0
	while hut.under_construction and ticks < MAX_TICKS:
		brave.tick(TICK)
		ticks += 1
	check(not hut.under_construction, "brave BUILD ticks finish the construction")
	check_near(hut.build_progress, 1.0, "build_progress reaches 1.0")
	check(brave.state == Unit.State.IDLE, "brave goes IDLE after finishing")
	check(tribe.housing_capacity() == Hut.CAPACITY, "finished hut provides capacity")

	# Now the hut spawns (population 1 = the builder brave; capacity 100).
	var pop_before: int = tribe.population()
	for i in range(int(Hut.SPAWN_INTERVAL / TICK) + 10):
		hut.tick(TICK)
	check(tribe.population() == pop_before + 1, "finished hut spawns a brave")
	_free_world(w)
