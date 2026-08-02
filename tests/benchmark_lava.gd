extends SceneTree

## Isolated LAVA cost benchmark (phase 10c). benchmark_stress cannot answer
## "did the lava code get more expensive?": the gameplay change alters how many
## units survive, and a battle with more survivors costs more everywhere. This
## harness keeps the population FIXED and ticks nothing but the projectile list,
## so the number it prints is the lava itself.
##
## NOT part of the test suite. Run with:
##   godot --headless -s res://tests/benchmark_lava.gd

const TICK: float = 1.0 / 30.0
const BENCH_SEED: int = 20260803
const TICKS: int = 900          # 30 simulated seconds
const UNITS: int = 1500
const BLOB_RADIUS: int = 22
## One volcano + three fault flows, re-cast every 10 s like a real fight.
const RESPAWN_TICKS: int = 300

const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")


func _initialize() -> void:
	seed(BENCH_SEED)
	var td: TerrainData = TerrainData.new()
	td.generate_island(1337)
	var nav: NavGrid = NavGrid.new(td)
	var tribes: Array[Tribe] = []
	for i in range(2):
		tribes.append(Tribe.new(i))
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, tribes)

	var center_cell: Vector2i = Vector2i(td.size / 2, td.size / 2)
	var center: Vector3 = nav.cell_to_world(center_cell)
	var spawned: int = 0
	for radius in range(0, BLOB_RADIUS + 20):
		for cell in AIController.ring_cells(center_cell, radius):
			if spawned >= UNITS:
				break
			if not nav.is_cell_walkable(cell):
				continue
			var u: Unit = um.spawn_unit(WARRIOR_SCENE, spawned % 2,
				nav.cell_to_world(cell))
			if u == null:
				break
			# Immortal: the lava must not thin out the population, or the later
			# ticks would measure a smaller crowd (that is exactly the bias this
			# harness exists to avoid).
			u.max_health = 1000000
			u.health = 1000000
			spawned += 1
		if spawned >= UNITS:
			break
	print("lava-bench: %d Einheiten" % spawned)
	um._rebuild_grid()

	var total_us: int = 0
	var worst_us: int = 0
	var block_us: int = 0
	for t in range(TICKS):
		if t % RESPAWN_TICKS == 0:
			_spawn_lava(um, td, center)
		var t0: int = Time.get_ticks_usec()
		um._tick_projectiles(TICK)
		var took: int = Time.get_ticks_usec() - t0
		total_us += took
		block_us += took
		worst_us = maxi(worst_us, took)
		if (t + 1) % 150 == 0:
			print("  t%4d-%4d: proj Ø %6.3f ms" % [t - 149, t, float(block_us) / 150000.0])
			block_us = 0
	print("lava-bench: proj Ø %.3f ms | schlimmster Tick %.3f ms über %d Ticks" % [
		float(total_us) / float(TICKS) / 1000.0, float(worst_us) / 1000.0, TICKS])
	um.free()
	quit(0)


## One eruption (surge sheet) plus three downhill ribbons — the two shapes the
## game actually produces, at the sizes the volcano and the earthquake use.
func _spawn_lava(um: UnitManager, td: TerrainData, center: Vector3) -> void:
	var surge: LavaSurge = LavaSurge.new()
	surge.setup(center, um, td, 7.5, null)
	um.register_projectile(surge)
	for i in range(3):
		var a: float = TAU * float(i) / 3.0
		var at: Vector3 = center + Vector3(cos(a), 0.0, sin(a)) * 3.0
		at.y = td.get_height(at.x, at.z)
		var flow: LavaFlow = LavaFlow.new()
		flow.setup(at, Vector3(cos(a), 0.0, sin(a)), um, td, 7.0, 12.0, 4.0, true, null)
		um.register_projectile(flow)
