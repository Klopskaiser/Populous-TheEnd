extends SceneTree

## Diagnose einer vollen KI-gegen-KI-Partie (2026-11-22, KI-Persoenlichkeiten):
## vier KIs mit ZAUBERN auf einer echten Karte, Zwischenstand alle `report`
## Sekunden — Bevoelkerung, Huetten (mit Ausbaustufen), Lager, Tuerme, Werkstaetten,
## Fahrzeuge, Armee, Zustand und die Zauber JE STAMM. KEIN test_-Praefix, laeuft also
## nicht in der Suite; urteilt nicht, liefert Zahlen.
##
##   godot --headless -s res://tests/diag_ai_match.gd -- map=insel sim=1200 report=300
##   ... -- personalities=aggressive,economic,defensive,economic seed=7
##
## Startbedingungen wie main.gd._setup_skirmish_base (Platz, Schamanin, 1 Huette,
## 20 Braves, Baeume um den Anker), Zauber wie im Skirmish: voller Satz, leer.

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const SITE_SCENE: PackedScene = preload("res://scenes/buildings/reincarnation_site.tscn")
const TICK: float = 1.0 / 30.0
const START_BRAVES: int = 20


func _initialize() -> void:
	var map_id: String = "insel"
	var sim: float = 1200.0
	var report: float = 300.0
	var seed_value: int = 4242
	var kinds: Array[String] = []
	var tribe_count: int = 4
	for a in OS.get_cmdline_user_args():
		if a.begins_with("map="): map_id = a.trim_prefix("map=")
		elif a.begins_with("sim="): sim = float(a.trim_prefix("sim="))
		elif a.begins_with("report="): report = float(a.trim_prefix("report="))
		elif a.begins_with("seed="): seed_value = int(a.trim_prefix("seed="))
		elif a.begins_with("tribes="): tribe_count = clampi(int(a.trim_prefix("tribes=")), 2, 4)
		elif a.begins_with("personalities="):
			for k in a.trim_prefix("personalities=").split(","):
				kinds.append(String(k))
	seed(seed_value)
	var td: TerrainData = MapGenerator.create_terrain(map_id, seed_value)
	var nav: NavGrid = NavGrid.new(td)
	var tribes: Array[Tribe] = []
	for i in range(tribe_count): tribes.append(Tribe.new(i))
	var tm: TreeManager = TreeManager.new(); tm.setup(td, nav)
	var wpm: WoodPileManager = WoodPileManager.new(); wpm.setup(td)
	var um: UnitManager = UnitManager.new(); um.setup(td, nav, tribes, tm, wpm)
	var bm: BuildingManager = BuildingManager.new(); bm.setup(td, nav, um, wpm)
	um.building_manager = bm
	var tc: TribeCommands = TribeCommands.new(); tc.setup(nav, bm, um, tm)
	var ctx: SpellContext = SpellContext.new()
	ctx.terrain_data = td
	ctx.nav_grid = nav
	ctx.unit_manager = um
	ctx.building_manager = bm
	ctx.tree_manager = tm
	ctx.wood_pile_manager = wpm
	tc.spell_context = ctx
	root.add_child(tm); root.add_child(wpm); root.add_child(um); root.add_child(bm)
	tm.spawn_trees(240 * (td.size * td.size) / (128 * 128), seed_value)
	var anchors: Array[Vector2i] = MapGenerator.spawn_anchors(td, map_id, tribe_count)
	var ais: Array[AIController] = []
	for i in range(tribe_count):
		tribes[i].set_spells(Spell.create_player_set())
		_setup_base(tribes[i], anchors[i], tc, bm, um, tm, nav)
		var ai: AIController = AIController.new()
		ai.setup(tribes[i], tc, um, bm, tm, nav, anchors[i])
		if i < kinds.size() and "personality" in ai:
			ai.personality = AIPersonality.from_id(StringName(kinds[i]))
		ais.append(ai)
	print("Karte %s, %.0f s, %d KIs, Seed %d" % [map_id, sim, tribe_count, seed_value])
	for ai in ais:
		print("  KI %d: %s" % [ai.tribe.id, _personality_name(ai)])
	var frames: int = int(sim / TICK)
	var report_frames: int = int(report / TICK)
	var ai_accum: float = 0.0
	var t0: int = Time.get_ticks_msec()
	for f in range(frames):
		um.tick_units(TICK)
		um.tick(TICK); bm.tick(TICK); tm.tick(TICK)
		for t in tribes: t.tick(TICK)
		ai_accum += TICK
		if ai_accum >= 1.0:
			ai_accum -= 1.0
			for ai in ais: ai.tick_ai()
		if (f + 1) % report_frames == 0:
			_report(float(f + 1) * TICK, ais, tribes)
	print("Laufzeit %.1f s real" % (float(Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)


func _personality_name(ai: AIController) -> String:
	if "personality" in ai and ai.personality != null:
		return ai.personality.display_name()
	return "(ohne)"


func _report(t: float, ais: Array[AIController], tribes: Array[Tribe]) -> void:
	print("--- t=%4.0f s ---" % t)
	for ai in ais:
		var tribe: Tribe = ai.tribe
		var c: AIController.TickCache = ai.build_tick_cache()
		var stages: Array[int] = [0, 0, 0, 0, 0]
		var kinds: Dictionary = {}
		for b in tribe.buildings:
			if not is_instance_valid(b) or b.health <= 0 or b.under_construction: continue
			var k: String = b.get_script().resource_path.get_file().get_basename()
			kinds[k] = int(kinds.get(k, 0)) + 1
			if b is Hut:
				stages[clampi((b as Hut).upgrade_stage, 0, 4)] += 1
		var veh: int = 0
		for u in tribe.units:
			if is_instance_valid(u) and u.state != Unit.State.DEAD \
					and u.unit_kind() in [&"siege", &"fireram", &"airship"]:
				veh += 1
		var casts: Array[String] = []
		if "casts" in ai:
			var ids: Array = ai.casts.keys()
			ids.sort()
			for id in ids:
				casts.append("%s=%d" % [id, int(ai.casts[id])])
		var charges: Array[String] = []
		for s in tribe.spells:
			if s.charges > 0:
				charges.append("%s%d" % [String(s.id).substr(0, 4), s.charges])
		print("  KI %d %-11s %-6s%s pop %4d br %4d armee %3d | Huetten %2d %s | Lager K%d F%d T%d | Turm %d Werk %d Fz %d | Baust %d | Mana %.1f/s" % [
			tribe.id, _personality_name(ai), AIState.State.keys()[ai.state],
			" AUS" if tribe.eliminated else "", c.population, c.brave_count, c.army_count,
			c.usable_huts, str(stages), int(kinds.get("warrior_camp", 0)),
			int(kinds.get("firewarrior_camp", 0)), int(kinds.get("temple", 0)),
			int(kinds.get("watchtower", 0)),
			int(kinds.get("workshop", 0)) + int(kinds.get("fire_ram_workshop", 0))
				+ int(kinds.get("airship_wharf", 0)),
			veh, c.sites.size(), tribe.charging_income()])
		print("        Zauber: %s | geladen: %s | Vorstoesse: %d" % [", ".join(casts) if not casts.is_empty() else "-",
			" ".join(charges) if not charges.is_empty() else "-", int(ai.get("raids") if "raids" in ai else 0)])


## Mirrors main.gd::_setup_skirmish_base (site + shaman + prebuilt hut +
## start braves + guaranteed trees in reach) — copy of benchmark_earlygame.
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
