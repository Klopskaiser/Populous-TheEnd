extends TestBase

## Phase 8 — performance regression guards. These are ORDER-OF-MAGNITUDE
## watchdogs, not tight benchmarks: the budgets sit far above the measured
## values (move/combat 2000 ≈ 30-50 ms per tick on the dev machine) so normal
## machine variance never trips them, but an O(n^2) regression (hundreds of
## ms) fails loudly. Detailed numbers: tests/benchmark_mass.gd and
## tests/benchmark_earlygame.gd (not part of the suite).
##
## Note (Rückabwicklung): the unreachable-wood and early-economy guards were
## removed together with the rolled-back phase-8 behaviour changes.

const TICK: float = 1.0 / 30.0
## Generous per-tick budgets (usec) — see class doc.
const MOVE_BUDGET_US: int = 100000
const COMBAT_BUDGET_US: int = 120000

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")


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


# --- Seenland early-economy guard (phase 8.3) ----------------------------------

const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const SITE_SCENE: PackedScene = preload("res://scenes/buildings/reincarnation_site.tscn")
## Generous avg per-tick budget for the seenland churn (measured ~1-4 ms
## after the phase-8.3 fixes; the old thrash sat at 60-100 ms).
const SEENLAND_BUDGET_US: int = 25000

## Rebuild of the reported lag: seenland (256, central lake), 4 AI tribes in
## full build-up. Two guards in one scenario: (1) the economy churn stays
## within an order-of-magnitude tick budget (the retry-storm regression class
## explodes this by 20x+); (2) fresh move commands still respond immediately
## (the phase-8 rollback class: "units ignore orders" — commands must never
## starve behind economy path churn).
func test_seenland_churn_budget_and_command_response() -> void:
	var td: TerrainData = MapGenerator.create_terrain("seenland", 1337)
	var w: Dictionary = _make_world(td)
	var um: UnitManager = w.um
	var nav: NavGrid = w.nav
	um.building_manager = w.bm
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(nav, w.bm, um, w.tm)
	w.tm.spawn_trees(240, 1337)
	var anchors: Array[Vector2i] = MapGenerator.spawn_anchors(td, "seenland", 4)
	var ais: Array[AIController] = []
	for tribe in w.tribes:
		var anchor: Vector2i = anchors[tribe.id]
		# Minimal starter base: prebuilt hut + braves (no shaman needed).
		for radius in range(0, 40):
			var placed: bool = false
			for cell in AIController.ring_cells(anchor, radius):
				if tc.can_place_at(cell, Hut.FOOTPRINT):
					w.bm.place(HUT_SCENE, tribe, cell, 0, true)
					placed = true
					break
			if placed:
				break
		var spawned: int = 0
		for radius in range(0, 40):
			if spawned >= 12:
				break
			for cell in AIController.ring_cells(anchor + Vector2i(0, 6), radius):
				if spawned >= 12:
					break
				if nav.is_cell_walkable(cell) and (cell.x + cell.y) % 2 == 0:
					um.spawn_unit(BRAVE_SCENE, tribe.id, nav.cell_to_world(cell))
					spawned += 1
		var ai: AIController = AIController.new()
		ai.setup(tribe, tc, um, w.bm, w.tm, nav, anchor)
		ais.append(ai)

	# 45 s churn: AI builds, workers hit lakeside/unreachable layouts.
	var total_us: int = 0
	var ticks: int = 45 * 30
	var ai_accum: float = 0.0
	for t in range(ticks):
		var t0: int = Time.get_ticks_usec()
		for unit in um.units.duplicate():
			if is_instance_valid(unit):
				unit.tick(TICK)
		um.tick(TICK)
		w.bm.tick(TICK)
		w.tm.tick(TICK)
		ai_accum += TICK
		if ai_accum >= 1.0:
			ai_accum -= 1.0
			for ai in ais:
				ai.tick_ai()
		total_us += Time.get_ticks_usec() - t0
	var avg_us: int = total_us / ticks
	check(avg_us < SEENLAND_BUDGET_US,
		"seenland churn stays in budget (avg %d usec < %d)" % [avg_us, SEENLAND_BUDGET_US])

	# Fresh braves obey a move order DURING the churn (no starved commands).
	var movers: Array[Unit] = []
	var spawn_cell: Vector2i = anchors[0] + Vector2i(0, 14)
	for i in range(20):
		var cell: Vector2i = spawn_cell + Vector2i(i % 5, i / 5)
		if nav.is_cell_walkable(cell):
			var u: Unit = um.spawn_unit(BRAVE_SCENE, 0, nav.cell_to_world(cell))
			if u != null:
				movers.append(u)
	check(movers.size() >= 10, "enough command braves spawned (%d)" % movers.size())
	var target: Vector3 = nav.cell_to_world(anchors[0] + Vector2i(-12, 14))
	var starts: Array[Vector3] = []
	for u in movers:
		starts.append(u.position)
	tc.order_move(movers, target)
	for t in range(60):   # 2 s
		for unit in um.units.duplicate():
			if is_instance_valid(unit):
				unit.tick(TICK)
		um.tick(TICK)
	var responded: int = 0
	for i in range(movers.size()):
		var u: Unit = movers[i]
		if not is_instance_valid(u):
			continue
		if u.position.distance_to(starts[i]) > 0.5 \
				or Vector2(u.position.x - target.x, u.position.z - target.z).length() < 4.0:
			responded += 1
	check(responded == movers.size(),
		"every ordered brave responds during churn (%d/%d)" % [responded, movers.size()])
	for ai in ais:
		ai.free()
	tc.free()
	_free_world(w)
