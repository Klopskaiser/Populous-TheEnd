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
## Battle scenarios run longer: the armies need ~2 s to close in, then the
## brunt of the fighting happens (reported separately as the combat window).
const BATTLE_TICKS: int = 450

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")


func _initialize() -> void:
	# Phase 8.1 A/B: the same mass-move scenario with and without the off-thread
	# PathWorker. The interesting figure is the WORST tick after the mass order
	# (spike behaviour) — the worker should submit cheaply and never spike.
	print("== Stufe-A A/B (Massenbewegung) ==")
	for count in [2000, 6000]:
		_run_move(count, false)
		_run_move(count, true)
	for count in [2000, 6000]:
		_run_combat(count)
	# Phase 8.2 battle scenarios (user request): two armies marching at each
	# other like the debug battle, one unit kind per run — pure melee
	# (warriors: groups/slots/strikes) and pure ranged (firewarriors:
	# fire-range targeting + projectile load, which the grid scenario and the
	# warrior battle never exercise).
	print("== Schlacht-Szenarien (2 Armeen, Attack-Move) ==")
	_run_battle(1000, WARRIOR_SCENE, "schlacht krieger 2x1000     ")
	_run_battle(1000, FIREWARRIOR_SCENE, "schlacht feuerkrieger 2x1000")
	quit(0)


## Mass move: `count` braves split over 4 tribes in the map quadrants, each
## quadrant marching to its own gathering point (no cross-tribe contact —
## pure movement/hash/separation/path-queue cost).
func _run_move(count: int, use_worker: bool = false) -> void:
	var w: Dictionary = _make_world(use_worker)
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
	var tag: String = "move %d [worker]" % spawned if use_worker else "move %d [sync]  " % spawned
	_simulate(tag, um, MOVE_TICKS)
	_teardown(w)


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
	_teardown(w)


## Debug-battle shape: two armies (one tribe each) ring-packed around anchors
## left/right of the island centre, attack-moving at each other's anchor. The
## aggro/pairing systems take over on contact.
func _run_battle(per_side: int, scene: PackedScene, label: String) -> void:
	var w: Dictionary = _make_world()
	var um: UnitManager = w.um
	var nav: NavGrid = w.nav
	var commands: TribeCommands = TribeCommands.new()
	commands.setup(nav, null, um)
	var center: Vector2i = Vector2i(64, 64)
	for side in range(2):
		var dir: int = -1 if side == 0 else 1
		var anchor: Vector2i = center + Vector2i(dir * 20, 0)
		var spawned: int = 0
		for radius in range(0, 40):
			if spawned >= per_side:
				break
			for cell in AIController.ring_cells(anchor, radius):
				if spawned >= per_side:
					break
				if not nav.is_cell_walkable(cell):
					continue
				if um.spawn_unit(scene, side, nav.cell_to_world(cell)) == null:
					spawned = per_side   # 1500-per-tribe hard cap
					break
				spawned += 1
		commands.order_move(um.get_units_of_tribe(side),
			nav.cell_to_world(center + Vector2i(-dir * 20, 0)), false, true)
	_simulate(label, um, BATTLE_TICKS, BATTLE_TICKS / 3)
	commands.free()
	_teardown(w)


## `window_from` > 0 additionally reports the average over the ticks FROM that
## index (battle scenarios: the fighting window, skipping the approach march).
func _simulate(label: String, um: UnitManager, ticks: int, window_from: int = 0) -> void:
	Unit.dbg_plan_calls = 0
	Unit.dbg_plan_fails = 0
	Unit.dbg_plan_us = 0
	var total_us: int = 0
	var worst_us: int = 0
	var window_us: int = 0
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
		um._apply_combat_groups(TICK)
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
		if window_from > 0 and t >= window_from:
			window_us += took
	var n: float = float(ticks)
	var window_txt: String = ""
	if window_from > 0:
		window_txt = " | Ø Kampf-Fenster %.2f ms" % (
			float(window_us) / float(ticks - window_from) / 1000.0)
	print("%s: Ø %.2f ms%s | schlimmster Tick %.2f ms | Pfade %d (%d Fehlschläge, %.1f ms) | Budget ~33 ms" % [
		label, float(total_us) / n / 1000.0, window_txt, float(worst_us) / 1000.0,
		Unit.dbg_plan_calls, Unit.dbg_plan_fails, float(Unit.dbg_plan_us) / 1000.0])
	print("  Ø Phasen: units %.2f | hash %.2f | paths %.2f | sep %.2f | regroup+proj %.2f ms" % [
		float(units_us) / n / 1000.0, float(hash_us) / n / 1000.0,
		float(path_us) / n / 1000.0, float(sep_us) / n / 1000.0,
		float(regroup_us) / n / 1000.0])


func _make_world(use_worker: bool = false) -> Dictionary:
	var td: TerrainData = TerrainData.new()
	td.generate_island(1337)
	var nav: NavGrid = NavGrid.new(td)
	var tribes: Array[Tribe] = []
	for i in range(4):
		tribes.append(Tribe.new(i))
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, tribes)
	var worker: PathWorker = null
	if use_worker:
		worker = PathWorker.new(
			Rect2i(0, 0, td.size, td.size),
			Vector2(TerrainData.CELL_SIZE, TerrainData.CELL_SIZE),
			AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES,
			nav.solid_snapshot(), td.size)
		nav.path_worker = worker
		um.path_worker = worker
	return {"td": td, "nav": nav, "tribes": tribes, "um": um, "worker": worker}


## Joins the worker thread (the UnitManager lives outside the tree here, so
## _exit_tree never fires) before freeing.
func _teardown(w: Dictionary) -> void:
	if w.worker != null:
		w.worker.stop()
		w.nav.path_worker = null
		w.um.path_worker = null
	w.um.free()
