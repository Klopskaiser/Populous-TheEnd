extends SceneTree

## Isolated FEUERREGEN cost benchmark (phase 10k, modelled on benchmark_lava).
##
## benchmark_stress cannot answer "did the firestorm get more expensive?" — it
## never casts one (its `lebend` counts come out identical with and without the
## change, which is exactly how that was discovered). And a gameplay comparison
## would be confounded anyway: the spell now kills and burns more, so a battle
## with it has fewer survivors and costs less everywhere.
##
## This harness keeps the population FIXED and IMMORTAL and ticks nothing but the
## projectile list, so the number it prints is the firestorm itself.
##
## NOT part of the test suite. Run with:
##   godot --headless -s res://tests/benchmark_firestorm.gd

const TICK: float = 1.0 / 30.0
const BENCH_SEED: int = 20260807
## Long enough to cover the whole 20-s spell plus its last bolts.
const SECONDS: float = 26.0
const UNITS: int = 900
const BLOB_RADIUS: int = 14
## Re-cast so the measurement covers a CONTINUOUS rain, not one lucky window.
const RECAST_SECONDS: float = 6.0

const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")


func _initialize() -> void:
	seed(BENCH_SEED)
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = 6.0
	var nav: NavGrid = NavGrid.new(td)
	var tribes: Array[Tribe] = [Tribe.new(0), Tribe.new(1)]
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, tribes)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um)

	var centre_cell: Vector2i = Vector2i(td.size / 2, td.size / 2)
	var centre: Vector3 = nav.cell_to_world(centre_cell)
	var spawned: int = 0
	for radius in range(0, BLOB_RADIUS + 20):
		for cell in AIController.ring_cells(centre_cell, radius):
			if spawned >= UNITS:
				break
			if not nav.is_cell_walkable(cell):
				continue
			var u: Unit = um.spawn_unit(WARRIOR_SCENE, 1, nav.cell_to_world(cell))
			if u == null:
				break
			# Immortal and fireproof: neither damage nor burning may thin the
			# crowd out, or later ticks would measure a smaller one.
			u.max_health = 100000000
			u.health = 100000000
			spawned += 1
		if spawned >= UNITS:
			break
	# A few buildings so the per-bolt building pass is measured too.
	var huts: int = 0
	for i in range(6):
		var at: Vector2i = centre_cell + Vector2i(-6 + i * 3, 8)
		if bm.place(HUT_SCENE, tribes[1], at, 0, true) != null:
			huts += 1
	for b in bm.buildings:
		b.max_health = 100000000
		b.health = 100000000
	print("firestorm-bench: %d Einheiten, %d Gebaeude, Streuung %.1f m, Dauer %.0f s"
		% [spawned, huts, Balance.FIRESTORM_SPREAD_RADIUS, Balance.FIRESTORM_DURATION])
	um._rebuild_grid()

	var ctx: SpellContext = SpellContext.new()
	ctx.terrain_data = td
	ctx.nav_grid = nav
	ctx.unit_manager = um
	ctx.building_manager = bm
	var spell: FirestormSpell = FirestormSpell.new()

	var total_us: int = 0
	var worst_us: int = 0
	var ticks: int = int(SECONDS / TICK)
	var recast_every: int = int(RECAST_SECONDS / TICK)
	var bolts_peak: int = 0
	for t in range(ticks):
		if t % recast_every == 0:
			spell.execute(tribes[0], centre, ctx)
		var t0: int = Time.get_ticks_usec()
		um._tick_projectiles(TICK)
		var dt: int = Time.get_ticks_usec() - t0
		total_us += dt
		worst_us = maxi(worst_us, dt)
		bolts_peak = maxi(bolts_peak, um.projectiles.size())
	print("proj-Phase: Ø %.3f ms/Tick, schlimmster %.3f ms, max. gleichzeitige Projektile %d"
		% [float(total_us) / float(ticks) / 1000.0, float(worst_us) / 1000.0, bolts_peak])
	quit(0)
