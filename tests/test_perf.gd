extends TestBase

## Phase 8 — performance regression guards. These are ORDER-OF-MAGNITUDE
## watchdogs, not tight benchmarks: the budgets sit far above the measured
## values (move/combat 2000 ≈ 28-30 ms per tick on the dev machine) so normal
## machine variance never trips them, but an O(n^2) regression (hundreds of
## ms) fails loudly. Detailed numbers: tests/benchmark_mass.gd and
## tests/benchmark_earlygame.gd (not part of the suite).

const TICK: float = 1.0 / 30.0
## Generous per-tick budgets (usec) — see class doc.
const MOVE_BUDGET_US: int = 100000
const COMBAT_BUDGET_US: int = 120000
const ECONOMY_BUDGET_US: int = 25000

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")


func _make_world(td: TerrainData) -> Dictionary:
	var nav: NavGrid = NavGrid.new(td)
	var tribes: Array[Tribe] = []
	for i in range(4):
		tribes.append(Tribe.new(i))
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, tribes, tm, wpm)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um, wpm)
	return {"td": td, "nav": nav, "tribes": tribes, "um": um, "bm": bm,
		"tm": tm, "wpm": wpm}


func _free_world(w: Dictionary) -> void:
	w.bm.free()
	w.tm.free()
	w.wpm.free()
	w.um.free()


func _island_terrain() -> TerrainData:
	var td: TerrainData = TerrainData.new()
	td.generate_island(1337)
	return td


## Simulates `ticks` full frames (unit ticks + manager tick) and returns the
## average tick time in usec.
func _avg_tick_us(um: UnitManager, ticks: int) -> int:
	var total: int = 0
	for t in range(ticks):
		var t0: int = Time.get_ticks_usec()
		for unit in um.units.duplicate():
			if is_instance_valid(unit):
				unit.tick(TICK)
		um.tick(TICK)
		total += Time.get_ticks_usec() - t0
	return total / ticks


## 2000 braves (4 tribes, separate quadrants) on a mass move order: the
## per-tick cost must stay within the generous linear budget.
func test_mass_move_2000_budget() -> void:
	var w: Dictionary = _make_world(_island_terrain())
	var um: UnitManager = w.um
	var nav: NavGrid = w.nav
	var anchors: Array[Vector2i] = [
		Vector2i(38, 38), Vector2i(90, 38), Vector2i(38, 90), Vector2i(90, 90)]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var spawned: int = 0
	while spawned < 2000:
		var tribe_id: int = spawned % 4
		var cell: Vector2i = anchors[tribe_id] + Vector2i(
			rng.randi_range(-16, 16), rng.randi_range(-16, 16))
		if not nav.is_cell_walkable(cell):
			continue
		if um.spawn_unit(BRAVE_SCENE, tribe_id, nav.cell_to_world(cell)) == null:
			break
		spawned += 1
	check(spawned == 2000, "2000 braves spawned (got %d)" % spawned)
	for unit in um.units:
		unit.order_move(nav.cell_to_world(anchors[unit.tribe_id] + Vector2i(0, -10)))
	var avg_us: int = _avg_tick_us(um, 60)
	check(avg_us < MOVE_BUDGET_US,
		"mass move 2000 stays in budget (avg %d usec < %d)" % [avg_us, MOVE_BUDGET_US])
	_free_world(w)


## 2000 warriors of 4 tribes interleaved in tight rows: everyone fights
## (scans, melee slots, strikes, deaths) — per-tick cost within budget.
func test_mass_combat_2000_budget() -> void:
	var w: Dictionary = _make_world(_island_terrain())
	var um: UnitManager = w.um
	var nav: NavGrid = w.nav
	var spawned: int = 0
	var i: int = 0
	while spawned < 2000 and i < 10000:
		var cell: Vector2i = Vector2i(34, 34) + Vector2i(i % 60, i / 60)
		i += 1
		if not nav.is_cell_walkable(cell):
			continue
		if um.spawn_unit(WARRIOR_SCENE, spawned % 4, nav.cell_to_world(cell)) == null:
			break
		spawned += 1
	check(spawned == 2000, "2000 warriors spawned (got %d)" % spawned)
	var avg_us: int = _avg_tick_us(um, 60)
	check(avg_us < COMBAT_BUDGET_US,
		"mass combat 2000 stays in budget (avg %d usec < %d)" % [avg_us, COMBAT_BUDGET_US])
	_free_world(w)


## Early-lag root-cause regression (phase 8): wood on a DISCONNECTED island
## must not send workers into a failing-A*-retry storm. The site remembers the
## unreachable tree, the worker backs off and the site stalls for wood —
## the failing path plans stay bounded instead of repeating every other frame.
func test_unreachable_wood_is_cached() -> void:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = 5.0
	# Water moat: vertices 57..70 drop to 0, except the island block 61..67 —
	# cells 61..66 stay walkable but are unreachable from the mainland.
	for vz in range(57, 71):
		for vx in range(57, 71):
			if vx >= 61 and vx <= 67 and vz >= 61 and vz <= 67:
				continue
			td.set_vertex_height(vx, vz, 0.0)
	var w: Dictionary = _make_world(td)
	var um: UnitManager = w.um
	var tm: TreeManager = w.tm
	var nav: NavGrid = w.nav
	check(nav.is_cell_walkable(Vector2i(63, 63)), "island cell is walkable")
	check(nav.find_path(Vector3(42, 5, 42), nav.cell_to_world(Vector2i(63, 63))).is_empty(),
		"island is disconnected from the mainland")
	var tree: TreeResource = tm.spawn_tree(Vector2i(63, 63), TreeResource.MAX_STAGE)
	# Hut construction site on the mainland, foundation already level: the
	# only wood source in job reach is the island tree.
	var hut: Building = w.bm.place(HUT_SCENE, w.tribes[0], Vector2i(40, 40))
	hut.foundation_done = true
	hut._flatten_remaining.clear()
	var brave: Brave = um.spawn_unit(BRAVE_SCENE, 0, nav.cell_to_world(Vector2i(44, 44))) as Brave
	brave.order_build(hut)
	Unit.dbg_plan_calls = 0
	Unit.dbg_plan_fails = 0
	for t in range(int(6.0 / TICK)):
		brave.tick(TICK)
		hut.tick(TICK)
		um.tick(TICK)
	check(hut.is_wood_unreachable(tree), "site remembers the unreachable tree")
	check(Unit.dbg_plan_fails <= 3,
		"failing path plans stay bounded (%d fails in 6 s)" % Unit.dbg_plan_fails)
	check(hut.wood_stalled, "site stalls for wood instead of retrying")
	check(brave.state == Unit.State.IDLE, "worker gave up and idles")
	_free_world(w)


## Early-economy watchdog close to the lag scenario: bergpass, 4 AI-driven
## tribes with starter bases + a fresh construction site each, 30 simulated
## seconds — the average frame must stay far below the old regression
## (20-100 ms per frame before the phase 8 fixes).
func test_early_economy_budget() -> void:
	var td: TerrainData = MapGenerator.create_terrain("bergpass", 1337)
	var w: Dictionary = _make_world(td)
	var um: UnitManager = w.um
	var bm: BuildingManager = w.bm
	var tm: TreeManager = w.tm
	var nav: NavGrid = w.nav
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(nav, bm, um, tm)
	tm.spawn_trees(240, 1337)
	var anchors: Array[Vector2i] = MapGenerator.spawn_anchors(td, "bergpass", 4)
	var ais: Array[AIController] = []
	for tribe in w.tribes:
		var anchor: Vector2i = anchors[tribe.id]
		var hut_placed: bool = false
		for radius in range(0, 30):
			for cell in AIController.ring_cells(anchor, radius):
				if tc.can_place_at(cell, Hut.FOOTPRINT):
					bm.place(HUT_SCENE, tribe, cell, 0, true)
					hut_placed = true
					break
			if hut_placed:
				break
		# A fresh construction site right away, so the worker/fetch pipeline
		# is busy from second one (the old lag driver).
		for radius in range(0, 30):
			var placed: bool = false
			for cell in AIController.ring_cells(anchor + Vector2i(8, 8), radius):
				if tc.can_place_at(cell, Hut.FOOTPRINT):
					bm.place(HUT_SCENE, tribe, cell)
					placed = true
					break
			if placed:
				break
		var spawned: int = 0
		for radius in range(0, 30):
			if spawned >= 20:
				break
			for cell in AIController.ring_cells(anchor + Vector2i(0, 6), radius):
				if spawned >= 20:
					break
				if nav.is_cell_walkable(cell) and (cell.x + cell.y) % 2 == 0:
					um.spawn_unit(BRAVE_SCENE, tribe.id, nav.cell_to_world(cell))
					spawned += 1
		var ai: AIController = AIController.new()
		ai.setup(tribe, tc, um, bm, tm, nav, anchor)
		ais.append(ai)
	var frames: int = int(30.0 / TICK)
	var total_us: int = 0
	var ai_accum: float = 0.0
	for f in range(frames):
		var t0: int = Time.get_ticks_usec()
		for unit in um.units.duplicate():
			if is_instance_valid(unit):
				unit.tick(TICK)
		um.tick(TICK)
		bm.tick(TICK)
		tm.tick(TICK)
		for tribe in w.tribes:
			tribe.tick(TICK)
		ai_accum += TICK
		if ai_accum >= 1.0:
			ai_accum -= 1.0
			for ai in ais:
				ai.tick_ai()
		total_us += Time.get_ticks_usec() - t0
	var avg_us: int = total_us / frames
	check(avg_us < ECONOMY_BUDGET_US,
		"early economy stays in budget (avg %d usec < %d)" % [avg_us, ECONOMY_BUDGET_US])
	for ai in ais:
		ai.free()
	tc.free()
	_free_world(w)
