extends SceneTree

## Headless mass benchmark (phase 8): movement and combat at the target sizes
## (2000 = Mindestziel, 6000 = Zielgröße). Prints avg/worst tick times per
## phase — the in-game FPS overlay is the authoritative number (headless has
## no rendering); this is the order-of-magnitude guard for the simulation.
##
## NOT part of the test suite (no test_ prefix). Run with:
##   godot --headless -s res://tests/benchmark_mass.gd

const TICK: float = 1.0 / 30.0
const MOVE_TICKS: int = 300     # 10 simulated seconds
const COMBAT_TICKS: int = 300

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")


func _initialize() -> void:
	for count in [2000, 6000]:
		_run_move(count)
	for count in [2000, 6000]:
		_run_combat(count)
	quit(0)


## Mass move: `count` braves split over 4 tribes in the map quadrants, each
## quadrant marching to its own gathering point (no cross-tribe contact —
## pure movement/hash/separation/path-queue cost).
func _run_move(count: int) -> void:
	var w: Dictionary = _make_world()
	var um: UnitManager = w.um
	var nav: NavGrid = w.nav
	var anchors: Array[Vector2i] = [
		Vector2i(38, 38), Vector2i(90, 38), Vector2i(38, 90), Vector2i(90, 90)]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var spawned: int = 0
	while spawned < count:
		var tribe_id: int = spawned % 4
		var cell: Vector2i = anchors[tribe_id] + Vector2i(
			rng.randi_range(-16, 16), rng.randi_range(-16, 16))
		if not nav.is_cell_walkable(cell):
			continue
		if um.spawn_unit(BRAVE_SCENE, tribe_id, nav.cell_to_world(cell)) == null:
			break   # 1500-per-tribe hard cap
		spawned += 1
	for unit in um.units:
		unit.order_move(nav.cell_to_world(anchors[unit.tribe_id] + Vector2i(0, -10)))
	_simulate("move %d" % spawned, um, MOVE_TICKS)
	um.free()


## Mass combat: two armies of warriors interleaved in tight rows — everyone
## engages via the idle scan (slots, strikes, deaths, corpses).
func _run_combat(count: int) -> void:
	var w: Dictionary = _make_world()
	var um: UnitManager = w.um
	var nav: NavGrid = w.nav
	var spawned: int = 0
	var start: Vector2i = Vector2i(34, 34)
	var cols: int = 60
	var i: int = 0
	while spawned < count and i < 10000:
		var cell: Vector2i = start + Vector2i(i % cols, i / cols)
		i += 1
		if not nav.is_cell_walkable(cell):
			continue
		# Alternate tribes per cell: everyone starts next to an enemy.
		if um.spawn_unit(WARRIOR_SCENE, spawned % 4, nav.cell_to_world(cell)) == null:
			break
		spawned += 1
	_simulate("combat %d" % spawned, um, COMBAT_TICKS)
	um.free()


func _simulate(label: String, um: UnitManager, ticks: int) -> void:
	Unit.dbg_plan_calls = 0
	Unit.dbg_plan_fails = 0
	Unit.dbg_plan_us = 0
	var total_us: int = 0
	var worst_us: int = 0
	var units_us: int = 0
	var hash_us: int = 0
	var path_us: int = 0
	var sep_us: int = 0
	var regroup_us: int = 0
	for t in range(ticks):
		var t0: int = Time.get_ticks_usec()
		for unit in um.units.duplicate():
			if is_instance_valid(unit):
				unit.tick(TICK)
		var t1: int = Time.get_ticks_usec()
		for unit in um.units:
			um._update_hash_cell(unit)
		var t2: int = Time.get_ticks_usec()
		um._drain_path_queue()
		var t3: int = Time.get_ticks_usec()
		um._apply_separation(TICK)
		var t4: int = Time.get_ticks_usec()
		um._apply_idle_regroup(TICK)
		um._tick_projectiles(TICK)
		var t5: int = Time.get_ticks_usec()
		units_us += t1 - t0
		hash_us += t2 - t1
		path_us += t3 - t2
		sep_us += t4 - t3
		regroup_us += t5 - t4
		var took: int = t5 - t0
		total_us += took
		worst_us = maxi(worst_us, took)
	var n: float = float(ticks)
	print("%s: Ø %.2f ms | schlimmster Tick %.2f ms | Pfade %d (%d Fehlschläge, %.1f ms) | Budget ~33 ms" % [
		label, float(total_us) / n / 1000.0, float(worst_us) / 1000.0,
		Unit.dbg_plan_calls, Unit.dbg_plan_fails, float(Unit.dbg_plan_us) / 1000.0])
	print("  Ø Phasen: units %.2f | hash %.2f | paths %.2f | sep %.2f | regroup+proj %.2f ms" % [
		float(units_us) / n / 1000.0, float(hash_us) / n / 1000.0,
		float(path_us) / n / 1000.0, float(sep_us) / n / 1000.0,
		float(regroup_us) / n / 1000.0])


func _make_world() -> Dictionary:
	var td: TerrainData = TerrainData.new()
	td.generate_island(1337)
	var nav: NavGrid = NavGrid.new(td)
	var tribes: Array[Tribe] = []
	for i in range(4):
		tribes.append(Tribe.new(i))
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, tribes)
	return {"td": td, "nav": nav, "tribes": tribes, "um": um}
