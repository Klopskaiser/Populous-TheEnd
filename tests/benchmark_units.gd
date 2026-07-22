extends SceneTree

## Headless performance benchmark (NOT part of the test suite — the runner
## only picks up test_*.gd). Simulates the in-game per-tick work for 4000
## units (4 tribes x 1000): unit ticks, spatial hash, path queue, separation.
##
## Run with:
##   godot --headless -s res://tests/benchmark_units.gd

const UNIT_COUNT: int = 4000
const TICKS: int = 600          # 30 simulated seconds at 20 ms
const TICK: float = 0.05

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")


func _initialize() -> void:
	var td: TerrainData = TerrainData.new()
	td.generate_island(1337)
	var nav: NavGrid = NavGrid.new(td)
	var tribes: Array[Tribe] = []
	for i in range(4):
		tribes.append(Tribe.new(i))
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, tribes)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 99
	var spawn_start: int = Time.get_ticks_usec()
	var spawned: int = 0
	while spawned < UNIT_COUNT:
		var cell: Vector2i = Vector2i(rng.randi_range(20, 107), rng.randi_range(20, 107))
		if not nav.is_cell_walkable(cell):
			continue
		# ONE tribe on purpose: this benchmark measures movement/hash/
		# separation/idle cost. Mixed tribes stacked on one point would turn it
		# into a 4000-man brawl since phase 7b (brave idle aggro) — melee slot
		# contention is a separate phase 8 topic.
		um.spawn_unit(BRAVE_SCENE, 0, nav.cell_to_world(cell))
		spawned += 1
	print("Spawned %d units in %.1f ms" % [
		UNIT_COUNT, float(Time.get_ticks_usec() - spawn_start) / 1000.0])

	# Mass move order: everyone to the island centre (via the path queue).
	var order_start: int = Time.get_ticks_usec()
	for unit in um.units:
		unit.order_move(Vector3(64.0, 0.0, 64.0))
	print("Issued %d move orders in %.1f ms" % [
		UNIT_COUNT, float(Time.get_ticks_usec() - order_start) / 1000.0])

	# Simulate the per-frame gameplay work (what _physics_process does),
	# timing each phase separately to expose the cost drivers.
	var worst_us: int = 0
	var total_us: int = 0
	var move_us: int = 0
	var hash_us: int = 0
	var path_us: int = 0
	var sep_us: int = 0
	for t in range(TICKS):
		var tick_start: int = Time.get_ticks_usec()
		for unit in um.units:
			unit.tick(TICK)
		var t1: int = Time.get_ticks_usec()
		move_us += t1 - tick_start
		um._rebuild_grid()   # Stufe C1: CSR grid from the SoA arrays
		var t2: int = Time.get_ticks_usec()
		hash_us += t2 - t1
		um._drain_path_queue()
		var t3: int = Time.get_ticks_usec()
		path_us += t3 - t2
		um._apply_separation(TICK)
		um._apply_idle_regroup(TICK)   # phase 7b: guard scan + 6-pack drift
		var t4: int = Time.get_ticks_usec()
		sep_us += t4 - t3
		var took: int = t4 - tick_start
		total_us += took
		worst_us = maxi(worst_us, took)
	print("Ticks: %d | avg %.2f ms | worst %.2f ms (budget ~33 ms at 30 Hz physics)" % [
		TICKS, float(total_us) / float(TICKS) / 1000.0, float(worst_us) / 1000.0])
	print("  avg per phase: move %.2f ms | hash %.2f ms | paths %.2f ms | separation %.2f ms" % [
		float(move_us) / float(TICKS) / 1000.0, float(hash_us) / float(TICKS) / 1000.0,
		float(path_us) / float(TICKS) / 1000.0, float(sep_us) / float(TICKS) / 1000.0])

	var moving: int = 0
	for unit in um.units:
		if unit.state == Unit.State.MOVE:
			moving += 1
	print("Still moving after %d ticks: %d of %d" % [TICKS, moving, UNIT_COUNT])

	um.free()
	quit(0)
