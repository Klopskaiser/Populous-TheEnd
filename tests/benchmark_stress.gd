extends SceneTree

## Headless replica of the STRESS-TEST match (main menu "Stresstest"; see
## Main._setup_stress_match / _tick_stress_match): four armies of 1000 foot
## units (60 % warriors, 30 % firewarriors, 10 % preachers) on the compass
## points around the island centre, six crewed catapults behind each line and
## one shaman per tribe. After 5 s everything attack-moves at the centre; the
## shamans cast a rolling barrage (tornado/earthquake/swarm/firestorm, one
## tribe per interval, charges refilled).
##
## Prints avg/worst tick times per phase like benchmark_mass. In-game frames
## additionally pay rendering + terrain-mesh rebuilds after the earthquakes,
## so this is the SIMULATION share of the stress test only.
##
## NOT part of the test suite (no test_ prefix). Run with:
##   godot --headless -s res://tests/benchmark_stress.gd

const TICK: float = 1.0 / 30.0
## 60 simulated seconds: 5 s idle, ~8 s march, then the mega-brawl.
const TICKS: int = 1800
## Combat window: from first contact (armies start 30 cells from the centre).
const WINDOW_FROM: int = 450

const ARMY: int = 1000
const WARRIOR_SHARE: float = 0.6
const FW_SHARE: float = 0.3
const SIEGES: int = 6
const SIEGE_CREW: int = 3
const OFFSET: int = 30
const MARCH_TICK: int = 150            # 5 s idle delay
const CAST_INTERVAL_TICKS: int = 150   # one tribe casts every 5 s
const SPELLS: Array[StringName] = [
	&"tornado", &"earthquake", &"swarm", &"firestorm"]

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")
const PREACHER_SCENE: PackedScene = preload("res://scenes/units/preacher.tscn")
const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")
const SIEGE_SCENE: PackedScene = preload("res://scenes/units/siege_engine.tscn")


func _initialize() -> void:
	var td: TerrainData = TerrainData.new()
	td.generate_island(1337)
	var nav: NavGrid = NavGrid.new(td)
	var tribes: Array[Tribe] = []
	for i in range(4):
		var tribe: Tribe = Tribe.new(i)
		tribe.set_spells(Spell.create_default_set())
		tribes.append(tribe)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, tribes)
	var commands: TribeCommands = TribeCommands.new()
	commands.setup(nav, null, um)
	var ctx: SpellContext = SpellContext.new()
	ctx.terrain_data = td
	ctx.nav_grid = nav
	ctx.unit_manager = um
	commands.spell_context = ctx

	var center_cell: Vector2i = Vector2i(td.size / 2, td.size / 2)
	var center: Vector3 = nav.cell_to_world(center_cell)
	var offsets: Array[Vector2i] = [
		Vector2i(0, OFFSET), Vector2i(0, -OFFSET),
		Vector2i(-OFFSET, 0), Vector2i(OFFSET, 0)]
	for i in range(4):
		var anchor: Vector2i = center_cell + offsets[i]
		var back: Vector2i = Vector2i(signi(offsets[i].x), signi(offsets[i].y))
		_spawn_army(um, nav, i, anchor)
		_spawn_sieges(um, nav, i, anchor, back)
		_spawn_shaman(um, nav, i, anchor + back * 8)
	print("stress: %d Einheiten gesamt" % um.units.size())
	_simulate(um, commands, tribes, nav, center)
	commands.free()
	um.free()
	quit(0)


func _simulate(um: UnitManager, commands: TribeCommands, tribes: Array[Tribe],
		nav: NavGrid, center: Vector3) -> void:
	Unit.dbg_plan_calls = 0
	Unit.dbg_plan_fails = 0
	Unit.dbg_plan_us = 0
	var total_us: int = 0
	var worst_us: int = 0
	var window_us: int = 0
	var units_us: int = 0
	var grid_us: int = 0
	var path_us: int = 0
	var sep_us: int = 0
	var rest_us: int = 0
	var spell_index: int = 0
	var alive_at_window: int = 0
	var worst_tick_at: int = -1
	# Per-150-tick block profile (5 s blocks): shows the peak window that the
	# in-game frame rate actually feels (averages hide it — the brawl burns out).
	var block_us: int = 0
	var block_units: int = 0
	var block_sep: int = 0
	var block_worst: int = 0
	for t in range(TICKS):
		if t == MARCH_TICK:
			for tribe in tribes:
				var squad: Array[Unit] = []
				for u in tribe.units:
					if not is_instance_valid(u) or u.state == Unit.State.DEAD:
						continue
					if u.unit_kind() == &"brave":
						continue   # catapult crews stay on their engines
					squad.append(u)
				if not squad.is_empty():
					commands.order_move(squad, center, false, true)
		if t > MARCH_TICK and (t - MARCH_TICK) % CAST_INTERVAL_TICKS == 0:
			for tribe in tribes:
				var shaman: Unit = tribe.shaman
				if shaman == null or not is_instance_valid(shaman) \
						or shaman.state == Unit.State.DEAD \
						or shaman.state == Unit.State.CAST:
					continue
				var spell_id: StringName = SPELLS[spell_index % SPELLS.size()]
				spell_index += 1
				var spell: Spell = tribe.get_spell(spell_id)
				if spell == null:
					continue
				spell.charges = maxi(spell.charges, 1)
				commands.cast_spell(tribe, spell_id,
					_spell_target(um, tribe, shaman, center))
		if t == WINDOW_FROM:
			for u in um.units:
				if is_instance_valid(u) and u.state != Unit.State.DEAD:
					alive_at_window += 1
		var t0: int = Time.get_ticks_usec()
		um.tick_units(TICK)   # kernel pass + object ticks (like _physics_process)
		var t1: int = Time.get_ticks_usec()
		um._rebuild_grid()
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
		grid_us += t2 - t1
		path_us += t3 - t2
		sep_us += t4 - t3
		rest_us += t5 - t4
		var took: int = t5 - t0
		total_us += took
		if took > worst_us:
			worst_us = took
			worst_tick_at = t
		if t >= WINDOW_FROM:
			window_us += took
		block_us += took
		block_units += t1 - t0
		block_sep += t4 - t3
		block_worst = maxi(block_worst, took)
		if (t + 1) % 150 == 0:
			var alive: int = 0
			for u in um.units:
				if is_instance_valid(u) and u.state != Unit.State.DEAD:
					alive += 1
			print("  t%4d-%4d: Ø %6.2f ms (units %6.2f, sep %5.2f) | worst %6.2f | lebend %d" % [
				t - 149, t, float(block_us) / 150000.0, float(block_units) / 150000.0,
				float(block_sep) / 150000.0, float(block_worst) / 1000.0, alive])
			block_us = 0
			block_units = 0
			block_sep = 0
			block_worst = 0
	var n: float = float(TICKS)
	print("stress 4x%d: Ø %.2f ms | Ø Kampf-Fenster %.2f ms | schlimmster Tick %.2f ms (t=%d) | lebend @Fenster %d | Pfade %d (%d Fehlschläge, %.1f ms) | Budget ~33 ms" % [
		ARMY, float(total_us) / n / 1000.0,
		float(window_us) / float(TICKS - WINDOW_FROM) / 1000.0,
		float(worst_us) / 1000.0, worst_tick_at, alive_at_window,
		Unit.dbg_plan_calls, Unit.dbg_plan_fails, float(Unit.dbg_plan_us) / 1000.0])
	print("  Ø Phasen: units %.2f | grid %.2f | paths %.2f | sep+groups %.2f | regroup+proj %.2f ms" % [
		float(units_us) / n / 1000.0, float(grid_us) / n / 1000.0,
		float(path_us) / n / 1000.0, float(sep_us) / n / 1000.0,
		float(rest_us) / n / 1000.0])


## Cast point like Main._stress_spell_target: nearest enemy around the shaman.
func _spell_target(um: UnitManager, tribe: Tribe, shaman: Unit,
		fallback: Vector3) -> Vector3:
	var best: Unit = null
	var best_d: float = INF
	for u in um.get_enemy_candidates(shaman.position, 30.0, tribe.id, 8):
		var d: float = shaman.position.distance_squared_to(u.position)
		if d < best_d:
			best_d = d
			best = u
	if best != null:
		return best.position
	return fallback


## Ring-fills one army around its anchor: warriors first (front rings), then
## firewarriors, preachers last (rear rings) — mirrors Main._spawn_stress_match_army.
func _spawn_army(um: UnitManager, nav: NavGrid, tribe_id: int, anchor: Vector2i) -> void:
	var warriors: int = int(float(ARMY) * WARRIOR_SHARE)
	var firewarriors: int = int(float(ARMY) * FW_SHARE)
	var spawned: int = 0
	for radius in range(0, 40):
		for cell in AIController.ring_cells(anchor, radius):
			if spawned >= ARMY:
				return
			if not nav.is_cell_walkable(cell):
				continue
			var scene: PackedScene = WARRIOR_SCENE
			if spawned >= warriors + firewarriors:
				scene = PREACHER_SCENE
			elif spawned >= warriors:
				scene = FIREWARRIOR_SCENE
			if um.spawn_unit(scene, tribe_id, nav.cell_to_world(cell)) == null:
				return
			spawned += 1


func _spawn_sieges(um: UnitManager, nav: NavGrid, tribe_id: int,
		anchor: Vector2i, back: Vector2i) -> void:
	var side: Vector2i = Vector2i(-back.y, back.x)
	for k in range(SIEGES):
		@warning_ignore("integer_division")
		var wish: Vector2i = anchor + back * 12 + side * ((k - SIEGES / 2) * 4)
		var cell: Vector2i = _walkable_near(nav, wish, 0)
		if cell.x < 0:
			continue
		var engine: Unit = um.spawn_unit(SIEGE_SCENE, tribe_id, nav.cell_to_world(cell))
		if engine == null:
			return
		for c in range(SIEGE_CREW):
			var crew_cell: Vector2i = _walkable_near(nav, cell, c + 1)
			if crew_cell.x < 0:
				continue
			var brave: Unit = um.spawn_unit(BRAVE_SCENE, tribe_id, nav.cell_to_world(crew_cell))
			if brave != null:
				brave.order_crew(engine)


func _spawn_shaman(um: UnitManager, nav: NavGrid, tribe_id: int, anchor: Vector2i) -> void:
	var cell: Vector2i = _walkable_near(nav, anchor, 0)
	if cell.x >= 0:
		um.spawn_unit(SHAMAN_SCENE, tribe_id, nav.cell_to_world(cell))


func _walkable_near(nav: NavGrid, center: Vector2i, skip: int) -> Vector2i:
	var seen: int = 0
	for radius in range(0, 24):
		for cell in AIController.ring_cells(center, radius):
			if not nav.is_cell_walkable(cell):
				continue
			if seen >= skip:
				return cell
			seen += 1
	return Vector2i(-1, -1)
