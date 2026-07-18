extends SceneTree

## Headless benchmark of the EARLY-GAME lag scenario (phase 8): bergpass map,
## 4 tribes all driven by an AIController, symmetric starter bases, pure
## build-up (no combat contact for a long while). Simulates SIM_SECONDS of
## game time at 30 Hz and reports the per-frame cost of every subsystem in
## 30-second windows — the numbers expose which system scales badly while the
## armies are still tiny (<100 units per tribe).
##
## NOT part of the test suite (no test_ prefix). Run with:
##   godot --headless -s res://tests/benchmark_earlygame.gd
## Optional user args (after --): map=<id> sim=<seconds>, e.g.
##   godot --headless -s res://tests/benchmark_earlygame.gd -- map=seenland sim=300

const MAP_ID: String = "bergpass"
const TRIBE_COUNT: int = 4
const SIM_SECONDS: float = 150.0
const TICK: float = 1.0 / 30.0
const START_BRAVES: int = 20
const TREE_COUNT: int = 240   # main.gd scales 60 by map area (256^2 / 128^2)

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const SITE_SCENE: PackedScene = preload("res://scenes/buildings/reincarnation_site.tscn")


func _initialize() -> void:
	var map_id: String = MAP_ID
	var sim_seconds: float = SIM_SECONDS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("map="):
			map_id = arg.trim_prefix("map=")
		elif arg.begins_with("sim="):
			sim_seconds = float(arg.trim_prefix("sim="))
	if not MapGenerator.map_ids().has(map_id):
		push_error("Unbekannte Karte: %s" % map_id)
		quit(1)
		return
	print("Karte: %s, Sim: %.0f s" % [map_id, sim_seconds])
	var setup_start: int = Time.get_ticks_usec()
	var td: TerrainData = MapGenerator.create_terrain(map_id, 1337)
	var nav: NavGrid = NavGrid.new(td)
	var tribes: Array[Tribe] = []
	for i in range(TRIBE_COUNT):
		tribes.append(Tribe.new(i))
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, tribes, tm, wpm)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um, wpm)
	um.building_manager = bm
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(nav, bm, um, tm)
	var spell_ctx: SpellContext = SpellContext.new()
	spell_ctx.terrain_data = td
	spell_ctx.nav_grid = nav
	spell_ctx.unit_manager = um
	spell_ctx.building_manager = bm
	spell_ctx.tree_manager = tm
	spell_ctx.wood_pile_manager = wpm
	tc.spell_context = spell_ctx

	tm.spawn_trees(TREE_COUNT, 1337)
	var anchors: Array[Vector2i] = MapGenerator.spawn_anchors(td, map_id, TRIBE_COUNT)
	var ais: Array[AIController] = []
	for tribe in tribes:
		tribe.set_spells(Spell.create_default_set())
		var anchor: Vector2i = anchors[tribe.id]
		_setup_base(tribe, anchor, tc, bm, um, tm, nav)
		var ai: AIController = AIController.new()
		ai.setup(tribe, tc, um, bm, tm, nav, anchor)
		ais.append(ai)
	print("Setup: %.1f ms, %d Einheiten, %d Bäume" % [
		float(Time.get_ticks_usec() - setup_start) / 1000.0,
		um.units.size(), tm.trees.size()])

	# --- Simulation with per-system timing, reported in 30-s windows ---------
	var frames: int = int(sim_seconds / TICK)
	var window_frames: int = int(30.0 / TICK)
	var t_units: int = 0
	var t_manager: int = 0
	var t_buildings: int = 0
	var t_trees: int = 0
	var t_tribes: int = 0
	var t_ai: int = 0
	var worst_frame: int = 0
	var worst_frame_at: float = 0.0
	var worst_ai: int = 0
	var ai_accum: float = 0.0
	var state_cost: Dictionary = {}   # "kind/state[/task]" -> usec in window
	for f in range(frames):
		var f0: int = Time.get_ticks_usec()
		for unit in um.units.duplicate():
			if is_instance_valid(unit):
				var u0: int = Time.get_ticks_usec()
				var key: String = "%s/s%d" % [unit.unit_kind(), unit.state]
				if unit is Brave:
					key += "/t%d" % unit.task
				unit.tick(TICK)
				state_cost[key] = int(state_cost.get(key, 0)) + (Time.get_ticks_usec() - u0)
		var f1: int = Time.get_ticks_usec()
		um.tick(TICK)
		var f2: int = Time.get_ticks_usec()
		bm.tick(TICK)
		var f3: int = Time.get_ticks_usec()
		tm.tick(TICK)
		var f4: int = Time.get_ticks_usec()
		for tribe in tribes:
			tribe.tick(TICK)
		var f5: int = Time.get_ticks_usec()
		ai_accum += TICK
		if ai_accum >= 1.0:
			ai_accum -= 1.0
			for ai in ais:
				ai.tick_ai()
		var f6: int = Time.get_ticks_usec()
		t_units += f1 - f0
		t_manager += f2 - f1
		t_buildings += f3 - f2
		t_trees += f4 - f3
		t_tribes += f5 - f4
		t_ai += f6 - f5
		worst_ai = maxi(worst_ai, f6 - f5)
		var frame_us: int = f6 - f0
		if frame_us > worst_frame:
			worst_frame = frame_us
			worst_frame_at = float(f) * TICK
		if (f + 1) % window_frames == 0:
			var n: float = float(window_frames)
			var pop: int = 0
			for tribe in tribes:
				pop += tribe.population()
			print("t=%3ds  pop %4d | Ø units %5.2f | mgr %5.2f | bldg %5.2f | trees %4.2f | tribes %4.2f | ai %5.2f ms" % [
				int((f + 1) * TICK), pop,
				float(t_units) / n / 1000.0, float(t_manager) / n / 1000.0,
				float(t_buildings) / n / 1000.0, float(t_trees) / n / 1000.0,
				float(t_tribes) / n / 1000.0, float(t_ai) / n / 1000.0])
			t_units = 0
			t_manager = 0
			t_buildings = 0
			t_trees = 0
			t_tribes = 0
			t_ai = 0
			var keys: Array = state_cost.keys()
			keys.sort_custom(func(a: String, b: String) -> bool:
				return int(state_cost[a]) > int(state_cost[b]))
			var top: String = "  top:"
			for k in range(mini(5, keys.size())):
				top += " %s=%.1fms" % [keys[k], float(state_cost[keys[k]]) / n / 1000.0]
			print(top)
			state_cost.clear()
			print("  paths: %d calls (%d fails) %.1f ms gesamt im Fenster" % [
				Unit.dbg_plan_calls, Unit.dbg_plan_fails, float(Unit.dbg_plan_us) / 1000.0])
			Unit.dbg_plan_calls = 0
			Unit.dbg_plan_fails = 0
			Unit.dbg_plan_us = 0
			print("  best_tree: %d calls, %d paths, %.1f ms | islands: %d fills, %.1f ms | plots: %d scans, %d cells, %.1f ms" % [
				TreeManager.dbg_best_tree_calls, TreeManager.dbg_best_tree_paths,
				float(TreeManager.dbg_best_tree_us) / 1000.0,
				NavGrid.dbg_island_fills, float(NavGrid.dbg_island_us) / 1000.0,
				AIController.dbg_plot_scans, AIController.dbg_plot_cells,
				float(AIController.dbg_plot_us) / 1000.0])
			TreeManager.dbg_best_tree_calls = 0
			TreeManager.dbg_best_tree_paths = 0
			TreeManager.dbg_best_tree_us = 0
			NavGrid.dbg_island_fills = 0
			NavGrid.dbg_island_us = 0
			AIController.dbg_plot_scans = 0
			AIController.dbg_plot_cells = 0
			AIController.dbg_plot_us = 0
	print("Schlimmster Frame: %.2f ms (bei t=%.0fs) | schlimmster KI-Tick: %.2f ms (Budget ~33 ms)" % [
		float(worst_frame) / 1000.0, worst_frame_at, float(worst_ai) / 1000.0])

	for ai in ais:
		ai.free()
	tc.free()
	bm.free()
	tm.free()
	wpm.free()
	um.free()
	quit(0)


## Mirrors main.gd::_setup_skirmish_base (site + shaman + prebuilt hut +
## start braves + guaranteed trees in reach).
func _setup_base(tribe: Tribe, anchor: Vector2i, tc: TribeCommands,
		bm: BuildingManager, um: UnitManager, tm: TreeManager, nav: NavGrid) -> void:
	var site: Building = null
	for radius in range(0, 40):
		if site != null:
			break
		for cell in AIController.ring_cells(anchor, radius):
			if tc.can_place_at(cell, ReincarnationSite.FOOTPRINT):
				site = bm.place(SITE_SCENE, tribe, cell, 0, true)
				break
	if site != null:
		um.spawn_unit(SHAMAN_SCENE, tribe.id, site.edge_spawn_position())
	for radius in range(0, 40):
		var placed: bool = false
		for cell in AIController.ring_cells(anchor + Vector2i(-8, -3), radius):
			if tc.can_place_at(cell, Hut.FOOTPRINT):
				bm.place(HUT_SCENE, tribe, cell, 0, true)
				placed = true
				break
		if placed:
			break
	var spawned: int = 0
	for radius in range(0, 40):
		if spawned >= START_BRAVES:
			break
		for cell in AIController.ring_cells(anchor + Vector2i(0, 6), radius):
			if spawned >= START_BRAVES:
				break
			if not nav.is_cell_walkable(cell):
				continue
			if (cell.x + cell.y) % 2 != 0:
				continue
			um.spawn_unit(BRAVE_SCENE, tribe.id, nav.cell_to_world(cell))
			spawned += 1
	# Guaranteed wood in reach (main.gd::_ensure_trees_near).
	var anchor_world: Vector3 = nav.cell_to_world(anchor)
	var have: int = 0
	for tree in tm.trees:
		if tree.position.distance_to(anchor_world) <= 20.0:
			have += 1
	var missing: int = 12 - have
	var step: int = 0
	for radius in range(10, 20):
		if missing <= 0:
			break
		for cell in AIController.ring_cells(anchor, radius):
			if missing <= 0:
				break
			step += 1
			if step % 3 != 0:
				continue
			if not nav.is_cell_walkable(cell):
				continue
			var blocked: bool = false
			for dz in range(-TreeManager.MIN_SPACING, TreeManager.MIN_SPACING + 1):
				for dx in range(-TreeManager.MIN_SPACING, TreeManager.MIN_SPACING + 1):
					if tm.has_tree_at(cell + Vector2i(dx, dz)):
						blocked = true
			if blocked:
				continue
			tm.spawn_tree(cell, TreeResource.MAX_STAGE)
			missing -= 1
