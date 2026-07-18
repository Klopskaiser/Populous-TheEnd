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


## Mans a hut with `n` fresh braves (phase 7i crew; each counts toward
## population). Returns the crew braves.
func _man_hut(w: Dictionary, hut: Hut, n: int) -> Array[Unit]:
	var crew: Array[Unit] = []
	for i in range(n):
		var b: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, hut.tribe_id, hut.center_world())
		if b != null and hut.admit_crew(b):
			crew.append(b)
	return crew


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
	check(tree.wood_yield() == 0, "sapling (stage 0) holds no wood")
	check(not tree.can_claim(), "a sapling cannot be harvested")
	# A step >= (1 + GROWTH_SPREAD) * GROWTH_TIME always crosses the randomised
	# interval, so one grow_tick call advances exactly one stage.
	var step: float = TreeResource.GROWTH_TIME * 2.0
	tree.grow_tick(step)
	check(tree.stage == 1, "sapling grows to stage 1")
	check(tree.wood_yield() == 1, "stage 1 yields 1 wood")
	tree.grow_tick(step)
	check(tree.stage == 2 and tree.wood_yield() == 2, "stage 2 yields 2 wood")
	tree.grow_tick(step)
	check(tree.stage == 3 and tree.wood_yield() == 3, "stage 3 yields 3 wood")
	tree.grow_tick(step)
	check(tree.stage == 4 and tree.wood_yield() == 4, "big tree (stage 4) yields 4 wood")
	tree.grow_tick(step * 5.0)
	check(tree.stage == 4, "tree never grows past the max stage")
	check(tree.chop_time() > 3.4, "big trees take longer to fell")

	# Harvesting takes one wood at a time and drops the tree a stage; a big tree
	# needs four trips (4 -> 3 -> 2 -> 1 -> gone).
	check(tree.harvest_one() == 1, "harvest takes exactly one wood")
	check(tree.stage == 3, "big tree drops to stage 3 after one harvest")
	check(tree.harvest_one() == 1 and tree.stage == 2, "drops to stage 2")
	check(tree.harvest_one() == 1 and tree.stage == 1, "drops to stage 1")
	check(tree.harvest_one() == 1, "fourth harvest takes the last wood")
	check(tree.felled_flag, "tree is gone after its last wood")
	check(tree.harvest_one() == 0, "a felled tree yields nothing")
	tree.free()


func test_tree_parallel_harvest_slots() -> void:
	var w: Dictionary = _make_world()
	var tm: TreeManager = w.tree_manager
	var big: TreeResource = tm.spawn_tree(Vector2i(60, 60), 4)   # 4 wood

	var workers: Array[Brave] = []
	for i in range(5):
		workers.append(Brave.new())
	# A big tree (4 wood) supports up to 4 parallel harvesters.
	for i in range(4):
		check(tm.claim_nearest_tree(Vector3(60, 5, 60), 10.0, workers[i]) == big,
			"harvest slot %d on the big tree" % (i + 1))
	check(tm.claim_nearest_tree(Vector3(60, 5, 60), 10.0, workers[4]) == null,
		"a big tree has no fifth harvest slot")
	tm.release_claim(big, workers[0])
	check(tm.claim_nearest_tree(Vector3(60, 5, 60), 10.0, workers[4]) == big,
		"released slot can be claimed again")

	# A small tree (stage 1, 1 wood) supports only one harvester.
	var small: TreeResource = tm.spawn_tree(Vector2i(80, 80), 1)
	check(tm.claim_nearest_tree(Vector3(80, 5, 80), 5.0, workers[0]) == small,
		"single slot on a small tree")
	check(tm.claim_nearest_tree(Vector3(80, 5, 80), 5.0, workers[1]) == null,
		"small tree has no second harvest slot")

	for worker in workers:
		worker.free()
	_free_world(w)


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
	# Natural sprouts start as small grown trees (stage 1), never as saplings.
	var found_small: bool = false
	var found_sapling: bool = false
	for tree in tm.trees:
		if tree.stage == 1:
			found_small = true
		elif tree.stage == 0:
			found_sapling = true
	check(found_small, "sprouted trees start at stage 1")
	check(not found_sapling, "natural reproduction never makes saplings")
	_free_world(w)


# --- Wood piles ---------------------------------------------------------------------

## The bucket-indexed tree counting must be EXACTLY equivalent to the old
## linear scan over all trees (same 3D-distance term) — including after
## removals and across bucket borders.
func test_count_trees_near_matches_linear_scan() -> void:
	var w: Dictionary = _make_world()
	var tm: TreeManager = w.tree_manager
	tm.spawn_trees(80, 42)
	check(tm.trees.size() > 40, "enough trees for a meaningful comparison")
	var probes: Array[Vector3] = [
		w.nav.cell_to_world(Vector2i(64, 64)),
		w.nav.cell_to_world(Vector2i(8, 8)),
		w.nav.cell_to_world(Vector2i(120, 30)),
		Vector3(63.9, 5.0, 64.1),   # off-grid, near bucket borders
	]
	for radius: float in [6.0, 22.0, 40.0]:
		for pos in probes:
			var linear: int = 0
			for tree in tm.trees:
				if is_instance_valid(tree) and tree.position.distance_to(pos) <= radius:
					linear += 1
			check(tm.count_trees_near(pos, radius) == linear,
				"bucket count == linear count (r=%.0f @ %s)" % [radius, pos])
	# Removals keep the index in sync.
	for i in range(10):
		tm._remove_tree(tm.trees[0])
	var pos0: Vector3 = probes[0]
	var linear0: int = 0
	for tree in tm.trees:
		if is_instance_valid(tree) and tree.position.distance_to(pos0) <= 40.0:
			linear0 += 1
	check(tm.count_trees_near(pos0, 40.0) == linear0,
		"bucket count stays in sync after removals")
	_free_world(w)


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
	# The entrance cell (62, 64) is levelled too.
	check_near(td.vertex_height(62, 64), hut.flatten_target,
		"entrance cell vertex is levelled", 0.05)
	check_near(td.vertex_height(63, 65), hut.flatten_target,
		"entrance cell far vertex is levelled", 0.05)
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


func test_progress_requires_wood_and_site_stalls() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribe
	var bm: BuildingManager = w.building_manager

	# Flat plot, no trees anywhere -> foundation gets done, then the site
	# stalls and the worker quits instead of hammering forever.
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

	ticks = 0
	while brave.state != Unit.State.IDLE and ticks < 200:
		bm.tick(TICK)
		brave.tick(TICK)
		ticks += 1
	check(brave.state == Unit.State.IDLE, "worker quits when no wood source exists")
	check(hut.wood_stalled, "site is marked wood-stalled")
	check(hut.workers.is_empty(), "no workers stay on a stalled site")
	check_near(hut.build_progress, 0.0, "progress is capped at the delivered fraction (0)")

	# While stalled, recruiting leaves the idle brave alone.
	w.unit_manager.tick(TICK)
	for i in range(60):   # 3 simulated seconds > recruit interval
		bm.tick(TICK)
		brave.tick(TICK)
	check(brave.state == Unit.State.IDLE, "stalled site does not draft workers")

	# Wood arrives at the entrance -> absorbed -> unstalled -> the idle brave
	# is recruited again and finishes the build.
	w.wood_pile_manager.deposit(hut.entrance_world(), Hut.WOOD_COST)
	ticks = 0
	while hut.under_construction and ticks < MAX_TICKS:
		bm.tick(TICK)
		w.unit_manager.tick(TICK)
		brave.tick(TICK)
		ticks += 1
	check(not hut.under_construction, "build finishes once the wood is on site")
	check(hut.wood_delivered == Hut.WOOD_COST, "the piles were absorbed into the site")
	_free_world(w)


## Seenland early-game lag: a FAILED sub-task (vanished tree/pile, unreachable
## goal) must re-choose only after TASK_RETRY — otherwise a stuck worker
## re-runs the expensive path-verified tree search every sim tick (30 Hz).
## Success paths keep the immediate re-choose (responsiveness).
func test_failed_subtask_backs_off() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(57, 60))) as Brave
	brave.order_build(hut)
	check(brave.state == Unit.State.BUILD, "worker joined the job")

	# Vanished tree: the sub-task ends with a retry delay, and the expensive
	# tree search does NOT run again within the backoff window.
	brave.task = Brave.Task.CHOP
	brave.task_tree = null
	TreeManager.dbg_best_tree_calls = 0
	brave.tick(TICK)
	check(brave.task == Brave.Task.NONE, "invalid tree ends the sub-task")
	check_near(brave._retry_timer, Brave.TASK_RETRY,
		"failed chop backs off by TASK_RETRY", 0.001)
	for i in range(int(Brave.TASK_RETRY / TICK) - 2):
		brave.tick(TICK)
	check(TreeManager.dbg_best_tree_calls == 0,
		"no tree search inside the backoff window")

	# Vanished pile: same backoff.
	brave.task = Brave.Task.PICKUP
	brave.task_pile = null
	brave._retry_timer = 0.0
	brave.tick(TICK)
	check_near(brave._retry_timer, Brave.TASK_RETRY,
		"failed pickup backs off by TASK_RETRY", 0.001)

	# Unreachable goal (seek failure) in BUILD: ends the sub-task with backoff.
	brave.task = Brave.Task.DELIVER
	brave._on_seek_failed()
	check(brave.task == Brave.Task.NONE, "seek failure ends the sub-task")
	check_near(brave._retry_timer, Brave.TASK_RETRY,
		"seek failure backs off by TASK_RETRY", 0.001)

	# Success path keeps the immediate re-choose and resets the fail streak.
	brave._end_subtask()
	check_near(brave._retry_timer, 0.0, "plain _end_subtask re-chooses at once", 0.001)
	check(brave._seek_fail_streak == 0, "a successful sub-task resets the streak")

	# Consecutive seek failures escalate the delay and finally quit the job.
	brave._on_seek_failed()
	check_near(brave._retry_timer, Brave.TASK_RETRY, "streak 1: base delay", 0.001)
	brave._on_seek_failed()
	check_near(brave._retry_timer, Brave.TASK_RETRY * 2.0, "streak 2: doubled", 0.001)
	brave._on_seek_failed()
	brave._on_seek_failed()
	check_near(brave._retry_timer, Brave.TASK_RETRY_MAX, "streak 4: capped", 0.001)
	brave._on_seek_failed()
	check(brave.state == Unit.State.BUILD, "streak 5: still on the job")
	brave._on_seek_failed()
	check(brave.state == Unit.State.IDLE, "streak 6: the worker quits the job")
	check(brave.job == null, "the quit worker left the job")
	_free_world(w)


func test_workers_use_piles_before_trees() -> void:
	var w: Dictionary = _make_world()
	var tm: TreeManager = w.tree_manager
	var bm: BuildingManager = w.building_manager

	var hut: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	# Skip the flatten phase — this test is about the wood source choice.
	hut._flatten_remaining.clear()
	hut.foundation_done = true

	# Trees right next to the site AND enough piled wood further away:
	# the piles must be used first, the trees must stay untouched.
	for c: Vector2i in [Vector2i(55, 58), Vector2i(55, 62), Vector2i(68, 58),
			Vector2i(68, 62), Vector2i(60, 55)]:
		tm.spawn_tree(c, 3)
	var pile_pos: Vector3 = w.nav.cell_to_world(Vector2i(62, 76))   # ~11 m from entrance
	w.wood_pile_manager.deposit(pile_pos, Hut.WOOD_COST)

	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(57, 60))) as Brave
	brave.order_build(hut)
	for i in range(30):
		bm.tick(TICK)
		brave.tick(TICK)
		if brave.task != Brave.Task.NONE:
			break
	check(brave.task == Brave.Task.PICKUP, "worker fetches piled wood, not a tree")

	var ticks: int = 0
	while hut.under_construction and ticks < MAX_TICKS:
		bm.tick(TICK)
		brave.tick(TICK)
		ticks += 1
	check(not hut.under_construction, "build finishes on piled wood alone")
	check(hut.wood_delivered == Hut.WOOD_COST, "all wood came from the piles")
	check(tm.trees.size() == 5, "no tree was felled")
	var all_big: bool = true
	for tree in tm.trees:
		if tree.stage != 3:
			all_big = false
	check(all_big, "no tree was even harvested")
	_free_world(w)


## Regression (phase 7d bugfix): when the entrance side is walled off, wood
## delivery must fall back to a reachable perimeter spot instead of stranding
## workers with wood (or dropping it back at the trees).
func test_delivery_survives_unreachable_entrance() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	# Skip the flatten phase; this is about delivery.
	hut._flatten_remaining.clear()
	hut.foundation_done = true
	# Block the entrance approach with nav-solid cells (like a footprint —
	# permanent, not undone by anything).
	var ec: Vector2i = hut.entrance_cell()
	w.nav.fill_solid_region(Rect2i(60, ec.y, 4, 3), true)
	check(not w.nav.is_cell_walkable(ec), "the entrance cell is unreachable")
	check(w.nav.is_cell_walkable(w.nav.world_to_cell(hut.delivery_point())),
		"the delivery point falls back to a walkable perimeter cell")

	# Big trees on the reachable (north) side; 4x4 = 16 wood >= 15 cost.
	for c: Vector2i in [Vector2i(52, 56), Vector2i(56, 52), Vector2i(60, 52),
			Vector2i(68, 56), Vector2i(64, 52)]:
		w.tree_manager.spawn_tree(c, 4)
	var braves: Array[Brave] = []
	for i in range(3):
		var b: Brave = w.unit_manager.spawn_unit(
			BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(55 + i, 55))) as Brave
		b.order_build(hut)
		braves.append(b)

	var ticks: int = 0
	while hut.under_construction and ticks < MAX_TICKS:
		w.building_manager.tick(TICK)
		for b in braves:
			if is_instance_valid(b):
				b.tick(TICK)
		w.tree_manager.tick(TICK)
		w.unit_manager.tick(TICK)
		ticks += 1
	check(not hut.under_construction, "build finishes via the reachable delivery point")
	check(hut.wood_delivered == Hut.WOOD_COST, "all wood was delivered and absorbed")
	_free_world(w)


## A close wood pile is preferred over chopping — but ONLY when it is safe. A
## pile guarded by an enemy is skipped in favour of a tree in a safer spot.
func test_workers_skip_enemy_guarded_piles() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	hut._flatten_remaining.clear()
	hut.foundation_done = true

	# A pile close to the site, but an enemy stands right next to it.
	var pile_pos: Vector3 = w.nav.cell_to_world(Vector2i(62, 72))
	w.wood_pile_manager.deposit(pile_pos, Hut.WOOD_COST)
	w.unit_manager.spawn_unit(BRAVE_SCENE, 1, w.nav.cell_to_world(Vector2i(63, 72)))
	# A safe tree on the other side of the site (no enemies).
	var tree: TreeResource = w.tree_manager.spawn_tree(Vector2i(56, 55), 4)
	check(tree != null, "safe tree spawned")

	var worker: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(58, 60))) as Brave
	worker.order_build(hut)
	w.unit_manager.tick(TICK)   # refresh the spatial hash so the enemy is seen

	var ticks: int = 0
	while worker.task == Brave.Task.NONE and ticks < 200:
		w.building_manager.tick(TICK)
		worker.tick(TICK)
		w.unit_manager.tick(TICK)
		ticks += 1
	check(worker.task == Brave.Task.CHOP,
		"worker chops the safe tree instead of the enemy-guarded pile")
	check(is_instance_valid(worker.task_tree), "a tree was claimed")
	# The safe tree, not the pile.
	check(worker.task_pile == null, "no pile was chosen")
	_free_world(w)


func test_wood_stall_recheck_timer() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	hut.mark_wood_stalled()
	check(hut.wood_stalled, "site can be marked stalled")
	var t: float = 0.0
	while t < Building.WOOD_RECHECK_INTERVAL + 1.0:
		w.building_manager.tick(TICK)
		t += TICK
	check(not hut.wood_stalled, "stall clears after the re-check interval")
	_free_world(w)


# --- Hut spawning ------------------------------------------------------------------

func test_hut_spawns_braves_until_capacity() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribe

	var hut: Hut = w.building_manager.place(
		HUT_SCENE, tribe, Vector2i(60, 60), 0, true) as Hut
	check(hut != null, "hut placed")
	check(tribe.housing_capacity() == Hut.CAPACITY, "capacity of one hut is %d" % Hut.CAPACITY)

	# An unmanned hut produces nothing (phase 7i). NONE prevents auto-manning.
	tribe.growth_mode = Tribe.GrowthMode.NONE
	for i in range(int(Hut.SPAWN_INTERVAL / TICK) + 5):
		hut.tick(TICK)
	check(tribe.population() == 0, "an unmanned hut produces no braves")

	# Man it fully -> it produces again. Crew counts toward population.
	tribe.growth_mode = Tribe.GrowthMode.MAXIMUM
	_man_hut(w, hut, Hut.CREW_CAPACITY)
	var base: int = tribe.population()
	check(base == Hut.CREW_CAPACITY, "crew counts toward population")

	var t: float = 0.0
	while t < Hut.SPAWN_INTERVAL + 1.0 and tribe.population() == base:
		hut.tick(TICK)
		t += TICK
	check(tribe.population() == base + 1, "a manned hut spawns a brave")

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


func test_manual_chop_delivers_to_nearest_building() -> void:
	var w: Dictionary = _make_world()
	var wpm: WoodPileManager = w.wood_pile_manager

	# A finished hut nearby: the chopped wood is carried to its entrance.
	var hut: Hut = w.building_manager.place(
		HUT_SCENE, w.tribe, Vector2i(70, 60), 0, true) as Hut
	var tree: TreeResource = w.tree_manager.spawn_tree(Vector2i(60, 60), 3)   # 3 wood
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(58, 60))) as Brave
	brave.order_chop(tree)

	var ticks: int = 0
	while brave.state != Unit.State.IDLE and ticks < MAX_TICKS:
		brave.tick(TICK)
		ticks += 1
	check(w.tree_manager.trees.is_empty(), "the tree was fully harvested")
	check(wpm.total_wood() == 3, "all wood ended up in piles")
	check(wpm.wood_in_radius(hut.entrance_world(), 5.0) == 3,
		"the wood was carried to the hut entrance")
	_free_world(w)


func test_manual_chop_one_piece_per_trip() -> void:
	var w: Dictionary = _make_world()
	var wpm: WoodPileManager = w.wood_pile_manager
	var hut: Hut = w.building_manager.place(
		HUT_SCENE, w.tribe, Vector2i(70, 60), 0, true) as Hut
	var tree: TreeResource = w.tree_manager.spawn_tree(Vector2i(60, 60), 3)   # 3 wood
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(58, 60))) as Brave
	brave.order_chop(tree)

	var max_carried: int = 0
	var ticks: int = 0
	while brave.state != Unit.State.IDLE and ticks < MAX_TICKS:
		brave.tick(TICK)
		max_carried = maxi(max_carried, brave.carried_wood)
		ticks += 1
	check(max_carried == 1, "manual gather carries at most one wood at a time (got %d)" % max_carried)
	check(wpm.total_wood() == 3, "all three wood delivered over separate trips")
	check(wpm.wood_in_radius(hut.entrance_world(), 5.0) == 3,
		"the wood consolidated near the hut")
	_free_world(w)


func test_hut_production_progress() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.building_manager.place(
		HUT_SCENE, w.tribe, Vector2i(60, 60), 0, true) as Hut   # prebuilt, producing
	_man_hut(w, hut, Hut.CREW_CAPACITY)   # a hut only shows a bar while manned (phase 7i)
	hut.spawn_timer = Hut.SPAWN_INTERVAL
	check_near(hut.production_progress(), 0.0, "fresh spawn timer -> 0 progress")
	hut.spawn_timer = Hut.SPAWN_INTERVAL * 0.5
	check_near(hut.production_progress(), 0.5, "half-elapsed timer -> 0.5 progress")
	hut.spawn_timer = 0.0
	check_near(hut.production_progress(), 1.0, "timer done -> full progress")

	var site: Hut = w.building_manager.place(
		HUT_SCENE, w.tribe, Vector2i(70, 70), 0, false) as Hut   # under construction
	check(site.production_progress() < 0.0, "under-construction hut has no production bar")
	_free_world(w)


## Phase 7i bugfix: once construction really starts (>=1 wood built in), units
## standing on the footprint are pushed off so the rising building never buries
## them.
func test_construction_clears_footprint() -> void:
	var w: Dictionary = _make_world()
	var site: Hut = w.building_manager.place(
		HUT_SCENE, w.tribe, Vector2i(60, 60), 0, false) as Hut   # under construction
	var rect: Rect2i = site.footprint_rect()
	# A brave standing right on the footprint.
	var mid: Vector2i = site.cell + site.footprint / 2
	var brave: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, w.nav.cell_to_world(mid))
	check(rect.has_point(w.nav.world_to_cell(brave.position)),
		"brave starts on the footprint")
	# Before any wood: no clearing (still flattening/placing).
	site.tick(1.0)
	brave.tick(0.1)
	w.unit_manager.tick(0.1)
	check(brave.state != Unit.State.MOVE, "no eviction before the first wood")
	# First wood delivered -> the site clears its footprint.
	site.wood_delivered = 1
	var cleared: bool = false
	for i in range(int(10.0 / 0.1)):
		site.tick(0.1)
		brave.tick(0.1)
		w.unit_manager.tick(0.1)
		if not rect.has_point(w.nav.world_to_cell(brave.position)):
			cleared = true
			break
	check(cleared, "the brave is pushed off the footprint once building starts")
	_free_world(w)


func test_wood_pile_manager_near_queries() -> void:
	var w: Dictionary = _make_world()
	var wpm: WoodPileManager = w.wood_pile_manager
	wpm.deposit(Vector3(30.0, 0.0, 30.0), 3)   # pile A
	wpm.deposit(Vector3(80.0, 0.0, 80.0), 2)   # pile B, far away

	# wood_near_positions counts only piles within radius of a given position.
	check(wpm.wood_near_positions([Vector3(31.0, 0.0, 31.0)], 5.0) == 3,
		"counts only the nearby pile")
	check(wpm.wood_near_positions([Vector3(0.0, 0.0, 0.0)], 5.0) == 0,
		"no piles near the position -> 0")
	check(wpm.wood_near_positions([Vector3(31.0, 0.0, 31.0), Vector3(81.0, 0.0, 81.0)], 5.0) == 5,
		"both piles counted across multiple positions")

	# pile_with_space_near finds a pile with room within radius.
	var p: WoodPile = wpm.pile_with_space_near(Vector3(31.0, 0.0, 31.0), 5.0)
	check(p != null and p.amount == 3, "finds the nearby pile with space")
	check(wpm.pile_with_space_near(Vector3(0.0, 0.0, 0.0), 5.0) == null,
		"no pile in radius -> null")
	_free_world(w)


## Right-click pickup order (user feature): the brave fetches the pile and
## delivers it to the nearest own building's drop spot like loose-chopped wood.
func test_order_pickup_fetches_pile_and_delivers() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.building_manager.place(HUT_SCENE, w.tribe, Vector2i(30, 30), 0, true)
	var brave: Brave = w.unit_manager.spawn_unit(BRAVE_SCENE, 0, Vector3(50.5, 0, 30.5))
	w.wood_pile_manager.deposit(Vector3(52.5, 5.0, 30.5), 3)
	var pile: WoodPile = w.wood_pile_manager.piles[0]
	w.commands.order_pickup([brave] as Array[Unit], pile)
	check(brave.state == Unit.State.GATHER, "pickup order enters GATHER")
	check(brave.task == Brave.Task.PICKUP, "pickup order sets Task.PICKUP")
	var drop: Vector3 = hut.delivery_point()
	var delivered: bool = false
	for i in range(600):
		brave.tick(0.1)
		w.unit_manager.tick(0.1)
		for p in w.wood_pile_manager.piles:
			if is_instance_valid(p) and p.amount >= 3 \
					and Vector2(p.position.x, p.position.z).distance_to(
						Vector2(drop.x, drop.z)) <= 6.0:
				delivered = true
		if delivered:
			break
	check(delivered, "wood ends up on a pile at the hut's drop spot")
	check(brave.carried_wood == 0, "brave dropped everything")
	_free_world(w)
