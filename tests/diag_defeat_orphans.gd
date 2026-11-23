extends SceneTree

## Diagnose (2026-11-23, Nutzerreport): ein Stamm ohne sichtbare Anhaenger scheidet nicht
## aus — der Schamanenkreis bleibt stehen, einmal stand nur noch ein Huettengrundriss.
## Spielt volle KI-Partien (wie diag_ai_match) MIT Niederlage-Pruefung und sucht alle
## paar Sekunden "verwaiste" Einheiten: lebend, in tribe.units, zaehlen zur Bevoelkerung,
## aber weder in der Welt noch von einem Gebaeude/Fahrzeug gefuehrt. KEIN test_-Praefix.
##
##   godot --headless -s res://tests/diag_defeat_orphans.gd -- map=insel sim=2400 seed=7

const GameStateScript: GDScript = preload("res://scripts/core/game_state.gd")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const SITE_SCENE: PackedScene = preload("res://scenes/buildings/reincarnation_site.tscn")
const TICK: float = 1.0 / 30.0
const START_BRAVES: int = 20
const CHECK_EVERY: float = 5.0

var _reported: Dictionary = {}


func _initialize() -> void:
	var map_id: String = "insel"
	var sim: float = 2400.0
	var seed_value: int = 4242
	var tribe_count: int = 4
	for a in OS.get_cmdline_user_args():
		if a.begins_with("map="): map_id = a.trim_prefix("map=")
		elif a.begins_with("sim="): sim = float(a.trim_prefix("sim="))
		elif a.begins_with("seed="): seed_value = int(a.trim_prefix("seed="))
		elif a.begins_with("tribes="): tribe_count = clampi(int(a.trim_prefix("tribes=")), 2, 4)
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
		# Mixed personalities (the economist and the defender make the match last).
		ai.personality = AIPersonality.from_id(AIPersonality.IDS[(seed_value + i) % 3])
		ais.append(ai)
	var gs: Node = GameStateScript.new()
	gs.tribes = tribes
	gs.start_win_tracking()
	print("Karte %s, %.0f s, %d KIs, Seed %d" % [map_id, sim, tribe_count, seed_value])
	var frames: int = int(sim / TICK)
	var ai_accum: float = 0.0
	var check_accum: float = 0.0
	var t0: int = Time.get_ticks_msec()
	for f in range(frames):
		um.tick_units(TICK)
		um.tick(TICK); bm.tick(TICK); tm.tick(TICK)
		for t in tribes:
			if not t.eliminated:
				t.tick(TICK)
		ai_accum += TICK
		if ai_accum >= 1.0:
			ai_accum -= 1.0
			for ai in ais:
				if not ai.tribe.eliminated:
					ai.tick_ai()
			gs.check_defeats()
		check_accum += TICK
		if check_accum >= CHECK_EVERY:
			check_accum = 0.0
			_check(float(f + 1) * TICK, tribes, um, bm)
		if gs.match_over:
			print("t=%.0f s: Partie entschieden" % (float(f + 1) * TICK))
			break
	for t in tribes:
		print("  Stamm %d: %s, %d Einheiten, %d Gebaeude" % [t.id,
			"AUS" if t.eliminated else "lebt", t.units.size(), t.buildings.size()])
	print("Laufzeit %.1f s real, verwaiste Faelle: %d, vom Netz zurueckgeholt: %d" % [
		float(Time.get_ticks_msec() - t0) / 1000.0, _reported.size(), um.orphans_returned])
	quit(0)


## Where a living follower is: in the world, or held by something that brings it back.
static func whereabouts(u: Unit, bm: BuildingManager) -> String:
	if u.in_world:
		return "welt"
	for b in bm.buildings:
		if not is_instance_valid(b) or b.health <= 0:
			continue
		if b is Hut and u in (b as Hut).crew:
			return "huette"
		if b is TrainingBuilding and (b as TrainingBuilding).trainee == u:
			return "ausbildung"
		if b is Workshop and u in (b as Workshop).occupants:
			return "werkstatt"
		if b is Forester and u in (b as Forester).occupants:
			return "foersterei"
		if "raiders" in b and u in b.raiders:
			return "sturm"
	return "VERWAIST"


var _odd_seen: Dictionary = {}   # instance id -> times the same oddity was seen


## Living followers in a state they should not stay in: in space, far off the
## ground, a doomed body or a throw/roll that lasts over several checks, a unit
## "in the world" that the registry does not hold.
func _oddities(t: float, u: Unit, um: UnitManager) -> void:
	var td: TerrainData = um.terrain_data
	var odd: String = ""
	if u.in_world and (u._idx < 0 or u._idx >= um.units.size() or um.units[u._idx] != u):
		odd = "REGISTRY"
	elif u.in_world and not td.has_ground(u.position.x, u.position.z):
		odd = "IM_ALL"
	elif u.doomed:
		odd = "DOOMED"
	elif u.state == Unit.State.THROWN or u.state == Unit.State.ROLL:
		odd = "WURF"
	elif u.in_world and not u.flies and absf(u.position.y - td.get_height(u.position.x, u.position.z)) > 12.0:
		odd = "HOEHE"
	var id: int = u.get_instance_id()
	if odd == "":
		_odd_seen.erase(id)
		return
	var n: int = int(_odd_seen.get(id, 0)) + 1
	_odd_seen[id] = n
	if n == 3:   # the same oddity over three checks (15 s)
		print("t=%.0f s AUFFAELLIG %s Stamm %d: %s pos %s" % [t, odd, u.tribe_id, describe(u),
			u.position.snapped(Vector3.ONE * 0.1)])


func _check(t: float, tribes: Array[Tribe], um: UnitManager, bm: BuildingManager) -> void:
	for tribe in tribes:
		for u in tribe.units:
			if is_instance_valid(u) and u.state != Unit.State.DEAD and u.counts_population:
				_oddities(t, u, um)
		if tribe.eliminated:
			continue
		var alive: int = 0
		var visible: int = 0
		for u in tribe.units:
			if not is_instance_valid(u) or u.state == Unit.State.DEAD or not u.counts_population:
				continue
			alive += 1
			var where: String = whereabouts(u, bm)
			if where == "welt":
				visible += 1
			elif where == "VERWAIST" and not _reported.has(u.get_instance_id()):
				_reported[u.get_instance_id()] = true
				print("t=%.0f s VERWAIST Stamm %d: %s" % [t, tribe.id, describe(u)])
		if alive > 0 and visible == 0:
			var wheres: PackedStringArray = PackedStringArray()
			for u in tribe.units:
				if is_instance_valid(u) and u.state != Unit.State.DEAD and u.counts_population:
					wheres.append("%s@%s" % [u.unit_kind(), whereabouts(u, bm)])
			print("t=%.0f s Stamm %d: %d lebende Anhaenger, keiner in der Welt: %s" % [
				t, tribe.id, alive, ", ".join(wheres)])
		if alive > 0 and alive <= 3:
			var few: PackedStringArray = PackedStringArray()
			for u in tribe.units:
				if is_instance_valid(u) and u.state != Unit.State.DEAD and u.counts_population:
					few.append(describe(u) + " pos " + str(u.position.snapped(Vector3.ONE * 0.1)))
			print("t=%.0f s Stamm %d WENIGE: %s" % [t, tribe.id, " || ".join(few)])


static func describe(u: Unit) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%s %s hp %d doomed %s idx %d" % [u.unit_kind(), Unit.State.keys()[u.state],
		u.health, u.doomed, u._idx])
	parts.append("garrison %s housed %s" % [u.garrison_target, u.garrison_housed])
	parts.append("raid %s siege %s" % [u.raiding_building, u.siege_engine])
	if u is Brave:
		var b: Brave = u as Brave
		parts.append("job %s train %s ws_in %s forest %s/%s" % [b.job, b.train_target,
			b.workshop_inside, b.forester_home, b.forester_inside])
	return " | ".join(parts)


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
			if not nav.is_cell_walkable(cell) or (cell.x + cell.y) % 2 != 0:
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
			if step % 3 != 0 or not nav.is_cell_walkable(cell) or tm.has_tree_at(cell):
				continue
			tm.spawn_tree(cell, TreeResource.MAX_STAGE)
			missing -= 1
