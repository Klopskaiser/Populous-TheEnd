extends TestBase

## Save game (2026-11-23): GameSnapshot captures a running world, SaveGame writes
## it into user://saves and reads it back, and GameSnapshot.apply rebuilds it into
## a fresh world. The round trip must give the same fingerprint — terrain, trees,
## piles, buildings with crews/queues/progress, units with their bindings (vehicle
## crew, hut and tower crew, trainee, builders, routes), golems with size, kills
## and sitting, tribes with spells, settings and statistics. Plus the file format
## (header, version, slot list), the AI / survival / win-tracking states.

const GameStateScript: GDScript = preload("res://scripts/core/game_state.gd")

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")
const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")
const GOLEM_SCENE: PackedScene = preload("res://scenes/units/golem.tscn")
const DEMON_SCENE: PackedScene = preload("res://scenes/units/demon_golem.tscn")
const GENESIS_SCENE: PackedScene = preload("res://scenes/units/genesis_golem.tscn")
const SIEGE_SCENE: PackedScene = preload("res://scenes/units/siege_engine.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const CAMP_SCENE: PackedScene = preload("res://scenes/buildings/warrior_camp.tscn")
const TOWER_SCENE: PackedScene = preload("res://scenes/buildings/watchtower.tscn")

const TEST_SLOT: String = "test_suite_roundtrip"
const TICK: float = 0.1


func _make_world(heights: PackedFloat32Array = PackedFloat32Array()) -> Dictionary:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = 5.0
	if not heights.is_empty():
		td.heights = heights.duplicate()
	var nav: NavGrid = NavGrid.new(td)
	var tribes: Array[Tribe] = [Tribe.new(0, Unit.TRIBE_COLORS[0]), Tribe.new(1, Unit.TRIBE_COLORS[1])]
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
	var sc: SpellContext = SpellContext.new()
	sc.terrain_data = td
	sc.nav_grid = nav
	sc.unit_manager = um
	sc.building_manager = bm
	sc.tree_manager = tm
	sc.wood_pile_manager = wpm
	tc.spell_context = sc
	for tribe in tribes:
		tribe.set_spells(Spell.create_player_set())
	var ctx: SnapshotContext = SnapshotContext.new()
	ctx.terrain_data = td
	ctx.nav_grid = nav
	ctx.unit_manager = um
	ctx.building_manager = bm
	ctx.tree_manager = tm
	ctx.wood_pile_manager = wpm
	ctx.tribe_commands = tc
	ctx.spell_context = sc
	ctx.tribes = tribes
	ctx.match_config = MatchConfig.skirmish(1, MapGenerator.DEFAULT_MAP)
	return {"td": td, "nav": nav, "tribes": tribes, "tm": tm, "wpm": wpm, "um": um,
		"bm": bm, "tc": tc, "ctx": ctx}


func _free_world(w: Dictionary) -> void:
	w.tc.free()
	w.tm.free()
	w.wpm.free()
	w.bm.free()
	w.um.free()


func _tick_world(w: Dictionary) -> void:
	w.bm.tick(TICK)
	for u in w.um.units.duplicate():
		if is_instance_valid(u):
			u.tick(TICK)
	w.um.tick(TICK)


func _at(w: Dictionary, cell: Vector2i) -> Vector3:
	return w.nav.cell_to_world(cell)


func _spawn(w: Dictionary, scene: PackedScene, tribe_id: int, cell: Vector2i) -> Unit:
	return w.um.spawn_unit(scene, tribe_id, _at(w, cell))


## A world with a bit of everything the save has to carry.
func _populate(w: Dictionary) -> Dictionary:
	var t0: Tribe = w.tribes[0]
	var t1: Tribe = w.tribes[1]
	# Red's grown golem sits down FIRST: the world ticks meanwhile, and nothing
	# else exists yet that those ticks could move on.
	var golem: Golem = _spawn(w, GOLEM_SCENE, 1, Vector2i(64, 100)) as Golem
	while not golem.can_sit():
		golem._credit_kill()
	golem._stretch_queued = false
	golem.health = golem.max_health - 50
	golem.sit_stationary = false
	golem.snap_shown_size()
	golem.facing = Vector3(0, 0, 1)
	golem.snap_heading()
	golem.tick(TICK)
	check(golem.sit_down(), "the golem takes the order to sit")
	var ticks: int = 0
	while not (golem.is_sitting() and not golem.is_switching_stance()) and ticks < 400:
		_tick_world(w)
		ticks += 1
	check(golem.is_sitting(), "the golem sits before the save")
	# Terrain deformation (a hill in the north-west corner).
	w.td.raise_area(Vector2(20, 20), 6.0, 3.0)
	# Trees and a pile.
	var tree: TreeResource = w.tm.spawn_tree(Vector2i(30, 100), 2, TreeResource.TreeType.LEAF)
	tree.set_growth(2.4)
	w.tm.spawn_tree(Vector2i(36, 100), TreeResource.MAX_STAGE)
	w.wpm.deposit(_at(w, Vector2i(40, 104)), 3)
	# A finished hut on stage 1 with two crew braves.
	var hut: Hut = w.bm.place(HUT_SCENE, t0, Vector2i(40, 40), 0, true) as Hut
	hut.upgrade_instantly(1)
	hut.manual_crew_override = 2
	for i in range(2):
		var b: Unit = _spawn(w, BRAVE_SCENE, 0, hut.entrance_cell())
		check(hut.admit_crew(b), "hut crew %d admitted" % i)
	# A warrior camp: one trainee inside, two braves in the queue.
	var camp: TrainingBuilding = w.bm.place(CAMP_SCENE, t0, Vector2i(54, 40), 0, true) as TrainingBuilding
	var trainee: Brave = _spawn(w, BRAVE_SCENE, 0, camp.entrance_cell()) as Brave
	trainee.order_train(camp)
	trainee.train_reached_slot = true
	camp._admit_front()
	camp._train_timer = 1.25
	for i in range(2):
		(_spawn(w, BRAVE_SCENE, 0, Vector2i(54 + i * 2, 52)) as Brave).order_train(camp)
	# A construction site with a builder and some wood in, one with a damaged
	# finished building nearby.
	var site: Building = w.bm.place(HUT_SCENE, t0, Vector2i(70, 40), 1, false)
	site.wood_delivered = 3
	site._flatten_remaining.clear()
	site.foundation_done = true
	site._grow_site_hp()
	site.add_build_progress(0.2)
	var builder: Brave = _spawn(w, BRAVE_SCENE, 0, Vector2i(74, 52)) as Brave
	builder.order_build(site)
	builder.carried_wood = 2
	# A watchtower with a warrior on top; the tower is damaged.
	var tower: Building = w.bm.place(TOWER_SCENE, t0, Vector2i(40, 60), 2, true)
	var guard: Unit = _spawn(w, WARRIOR_SCENE, 0, tower.entrance_cell())
	check(tower.admit_crew(guard), "tower crew admitted")
	tower.health = tower.max_health - 40
	# A catapult with three firewarriors aboard.
	var catapult: CrewedVehicle = _spawn(w, SIEGE_SCENE, 0, Vector2i(80, 80)) as CrewedVehicle
	for i in range(3):
		var fw: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2i(80, 80))
		fw.order_crew(catapult)
		catapult.on_crew_boarded(fw)
	# A brave on a two-leg route, one holding wood, the shaman.
	var walker: Unit = _spawn(w, BRAVE_SCENE, 0, Vector2i(60, 70))
	walker.order_move(_at(w, Vector2i(90, 70)))
	walker.order_move(_at(w, Vector2i(90, 90)), true)
	var carrier: Brave = _spawn(w, BRAVE_SCENE, 0, Vector2i(62, 74)) as Brave
	carrier.carried_wood = 2
	carrier.carry_hold = true
	_spawn(w, SHAMAN_SCENE, 0, Vector2i(64, 64))
	# Red: a demon and a Genesis golem, a hypnotized warrior.
	var demon: Golem = _spawn(w, DEMON_SCENE, 1, Vector2i(100, 30)) as Golem
	for i in range(5):
		demon._credit_kill()
	var genesis: GenesisGolem = _spawn(w, GENESIS_SCENE, 1, Vector2i(100, 60)) as GenesisGolem
	genesis.credit_brave(25.0)
	genesis.wood = 4
	var hypno: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector2i(30, 70))
	check(hypno.hypnotize(t0, 20.0), "the warrior is hypnotized by blue")
	# Tribe state: spells, settings, statistics.
	t0.get_spell(&"fireball").charges = 2
	t0.get_spell(&"fireball").add_charge_mana(5.0)
	t0.set_spell_active(&"tornado", false)
	t0.growth_mode = Tribe.GrowthMode.MINIMAL
	t0.max_catapults = 5
	t0.upgrades_allowed = false
	t0.kills_by_golems = 3
	t0.kills_other = 12
	t1.units_lost = 15
	t1.mana = 7.5
	return {"hut": hut, "camp": camp, "site": site, "tower": tower, "catapult": catapult,
		"walker": walker, "golem": golem, "genesis": genesis, "demon": demon}



func _first_building(w: Dictionary, script_class: String) -> Building:
	for b in w.bm.buildings:
		if b.get_script().get_global_name() == script_class:
			return b
	return null


func test_round_trip_through_a_file_restores_the_world() -> void:
	var a: Dictionary = _make_world()
	var made: Dictionary = _populate(a)
	var data: Dictionary = GameSnapshot.capture(a.ctx)
	var before: PackedStringArray = GameSnapshot.fingerprint(data)
	check(SaveGame.write(TEST_SLOT, data, "Test") == OK, "the save is written")
	var loaded: Dictionary = SaveGame.read(TEST_SLOT)
	check(not loaded.has("error"), "the save is read back (%s)" % loaded.get("error", ""))
	var body: Dictionary = loaded.get("body", {})
	check(GameSnapshot.fingerprint(body) == before, "the file keeps every value")

	# A fresh world: the saved heights go in before the NavGrid is built.
	var td: TerrainData = TerrainData.new()
	check(GameSnapshot.apply_terrain(td, body), "the terrain fits")
	var b: Dictionary = _make_world(td.heights)
	var restored: Dictionary = GameSnapshot.apply(body, b.ctx)
	var after: PackedStringArray = GameSnapshot.fingerprint(GameSnapshot.capture(b.ctx))
	var missing: PackedStringArray = PackedStringArray()
	for line in before:
		if not after.has(line):
			missing.append(line.left(300))
	var extra: PackedStringArray = PackedStringArray()
	for line in after:
		if not before.has(line):
			extra.append(line.left(300))
	check(missing.is_empty() and extra.is_empty(),
		"the restored world has the same fingerprint\n  before: %s\n  after:  %s" % [
			"\n          ".join(missing), "\n          ".join(extra)])

	var t0: Tribe = b.tribes[0]
	var t1: Tribe = b.tribes[1]
	check((restored["units"] as Array).size() == (data["units"] as Array).size(),
		"every unit came back")
	check(t0.population() == a.tribes[0].population() and t1.population() == a.tribes[1].population(),
		"the populations match (%d / %d)" % [t0.population(), t1.population()])
	check(b.td.heights == a.td.heights, "the deformed terrain is back")
	check(b.tm.trees.size() == 2 and b.wpm.total_wood() == a.wpm.total_wood(),
		"trees and wood are back")
	var hut: Hut = _first_building(b, "Hut") as Hut
	check(hut != null and not hut.under_construction and hut.upgrade_stage == 1
		and hut.crew_count() == 2 and hut.manual_crew_override == 2,
		"the hut: stage 1, two crew inside, manual override")
	for u in hut.crew:
		check(not u.in_world and u.garrison_housed, "a crew brave is housed out of the world")
	var camp: TrainingBuilding = null
	for bb in b.bm.buildings:
		if bb is TrainingBuilding:
			camp = bb
	check(camp != null and camp.trainee != null and not camp.trainee.in_world,
		"the trainee is inside the camp")
	check_near(camp._train_timer, 1.25, "with his remaining training time")
	check(camp.incoming.size() == 2, "two braves wait in the queue")
	var site: Building = null
	for bb in b.bm.buildings:
		if bb.under_construction:
			site = bb
	check(site != null and site.foundation_done and site.wood_delivered == 3
		and absf(site.build_progress - 0.2) < 0.001 and site.orientation == 1,
		"the site: foundation, 3 wood, 20 %, turned")
	check(site.workers.size() == 1, "its builder works on it again")
	var tower: Watchtower = _first_building(b, "Watchtower") as Watchtower
	check(tower != null and tower.crew.size() == 1 and tower.health == tower.max_health - 40,
		"the tower: one guard on top, damaged")
	var catapult: CrewedVehicle = null
	for u in t0.units:
		if u is SiegeEngine:
			catapult = u
	check(catapult != null and catapult.boarded_count() == 3, "the catapult with three aboard")
	var walker: Unit = null
	for u in t0.units:
		if u.state == Unit.State.MOVE and u.waypoint_queue.size() == 2:
			walker = u
	check(walker != null, "the walker is on his two-leg route again")
	var golems: Array = []
	for u in t1.units:
		if u is Golem:
			golems.append(u)
	check(golems.size() == 3, "three golems for red")
	for g in golems:
		if g is GenesisGolem:
			check(g.stage == made.genesis.stage and g.wood == 4
				and absf(g.height_m() - made.genesis.height_m()) < 0.01,
				"the Genesis golem: stage, wood and height")
		elif g is DemonGolem:
			check(g.kills == 5 and g.growth_steps == made.demon.growth_steps,
				"the demon: kills and growth")
		else:
			check(g.is_sitting(), "the golem sits again")
			check(absf(g.height_m() - made.golem.height_m()) < 0.01 and g.kills == made.golem.kills
				and g.level == made.golem.level, "with her size, kills and level")
			check(g.health == made.golem.health and not g.sit_stationary, "health and settings")
			check(Vector2(g.position.x, g.position.z).distance_to(
				Vector2(made.golem.position.x, made.golem.position.z)) < 0.05,
				"on her old seat (%s vs %s)" % [g.position, made.golem.position])
	var hypno: Unit = null
	for u in t0.units:
		if u.is_hypnotized():
			hypno = u
	check(hypno != null and hypno._hypnosis_origin == t1, "the hypnotized warrior goes back to red later")
	check(t0.get_spell(&"fireball").charges == 2 and not t0.get_spell(&"tornado").active,
		"spell charges and switches")
	check(t0.growth_mode == Tribe.GrowthMode.MINIMAL and t0.max_catapults == 5
		and not t0.upgrades_allowed, "tribe settings")
	check(t0.kills_by_golems == 3 and t0.kills_other == 12 and t1.units_lost == 15,
		"the statistics")
	check_near(t1.mana, 7.5, "red's mana")

	# The restored world runs on.
	for i in range(30):
		_tick_world(b)
	check(camp.trainee == null or camp._train_timer < 1.25, "the training goes on")
	SaveGame.delete_slot(TEST_SLOT)
	check(not SaveGame.exists(TEST_SLOT), "the test slot is removed again")
	_free_world(a)
	_free_world(b)


func test_save_file_header_slots_and_versions() -> void:
	var w: Dictionary = _make_world()
	_spawn(w, BRAVE_SCENE, 0, Vector2i(60, 60))
	var data: Dictionary = GameSnapshot.capture(w.ctx)
	data["tracking"] = {"match_time": 754.0, "defeated": [], "exempt": []}
	check(SaveGame.sanitize_slot("Mein Spiel #1") == "mein_spiel_1", "slot names are file-safe")
	check(SaveGame.slot_path("quicksave") == "user://saves/quicksave.sav", "slot path")
	check(SaveGame.write(TEST_SLOT, data, "Testspiel") == OK, "written")
	var header: Dictionary = SaveGame.read_header(TEST_SLOT)
	check(header.get("format") == SaveGame.FORMAT_ID and int(header.get("version")) == SaveGame.FORMAT_VERSION,
		"the header carries format and version")
	check(header.get("title") == "Testspiel" and header.get("map_id") == MapGenerator.DEFAULT_MAP
		and int(header.get("tribes")) == 2 and absf(float(header.get("match_time")) - 754.0) < 0.01,
		"title, map, tribes and game time")
	check(String(header.get("mode_label")).begins_with("Skirmish"), "the mode")
	var listed: bool = false
	for h in SaveGame.list_slots():
		if h.get("slot") == TEST_SLOT:
			listed = true
	check(listed, "the slot list shows it")
	check(SaveGame.describe(header).contains("12:34"), "the description shows the game time")
	# A file from a newer version is refused, a foreign file too.
	var file: FileAccess = FileAccess.open_compressed(SaveGame.slot_path(TEST_SLOT),
		FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	var newer: Dictionary = header.duplicate()
	newer["version"] = SaveGame.FORMAT_VERSION + 1
	file.store_var(newer)
	file.store_var(data)
	file.close()
	check(SaveGame.read(TEST_SLOT).has("error"), "a newer format is refused")
	file = FileAccess.open_compressed(SaveGame.slot_path(TEST_SLOT), FileAccess.WRITE,
		FileAccess.COMPRESSION_ZSTD)
	file.store_var({"format": "something else"})
	file.close()
	check(SaveGame.read(TEST_SLOT).has("error") and SaveGame.read_header(TEST_SLOT).is_empty(),
		"a foreign file is no save")
	check(SaveGame.delete_slot(TEST_SLOT) == OK, "deleted")
	check(SaveGame.read("does_not_exist_slot").has("error"), "a missing slot gives an error")
	_free_world(w)


func test_match_config_ai_survival_and_tracking_states() -> void:
	var config: MatchConfig = MatchConfig.skirmish(3, "bergpass",
		[&"economic", &"random"] as Array[StringName])
	var back: MatchConfig = MatchConfig.from_dict(config.to_dict())
	check(back.mode == MatchConfig.Mode.SKIRMISH and back.ai_count == 3 and back.map_id == "bergpass"
		and back.ai_personalities == config.ai_personalities, "the match config survives")
	var golems: MatchConfig = MatchConfig.from_dict(MatchConfig.survival_golems().to_dict())
	check(golems.variant == MatchConfig.VARIANT_GOLEMS and golems.endless, "the golem survival too")
	check(config.can_save() and golems.can_save() and not MatchConfig.debug_battle().can_save(),
		"skirmish and survival save, the sandboxes do not")

	var w: Dictionary = _make_world()
	var ai: AIController = AIController.new()
	ai.setup(w.tribes[1], w.tc, w.um, w.bm, w.tm, w.nav, Vector2i(80, 40))
	ai.personality = AIPersonality.defensive()
	ai.state = AIState.State.ATTACK
	ai.attack_wave_size = 23
	ai.raids = 2
	var ai2: AIController = AIController.new()
	ai2.setup(w.tribes[1], w.tc, w.um, w.bm, w.tm, w.nav, Vector2i.ZERO)
	ai2.load_state(ai.save_state())
	check(ai2.base_anchor == Vector2i(80, 40) and ai2.personality.id() == &"defensive"
		and ai2.state == AIState.State.ATTACK and ai2.attack_wave_size == 23 and ai2.raids == 2,
		"the AI's lasting decisions survive")
	check(w.tribes[1].ai_personality_name == ai2.personality.display_name(),
		"and the tribe shows its personality")
	ai.free()
	ai2.free()

	var gs: Node = GameStateScript.new()
	gs.tribes = w.tribes
	gs.start_win_tracking()
	var mode: SurvivalMode = SurvivalMode.new()
	mode.wave_interval = 40.0
	mode.growth_mult = 2
	var guard: Unit = _spawn(w, GOLEM_SCENE, 0, Vector2i(64, 64))
	mode.guardians = [guard] as Array[Unit]
	mode.setup(w.tribes[1], w.tribes[0], w.um, w.tc, w.nav, Vector2i(64, 64), gs)
	for i in range(int((Balance.SURVIVAL_FIRST_WAVE_DELAY + 5.0) / 0.5)):
		mode.tick(0.5)
	check(mode.wave == 1, "the first wave is out")
	var index: Dictionary = {guard: 0}
	var saved: Dictionary = mode.save_state(index)
	gs.match_time = 321.0
	var tracking: Dictionary = gs.save_tracking()

	var gs2: Node = GameStateScript.new()
	gs2.tribes = w.tribes
	gs2.start_win_tracking()
	var mode2: SurvivalMode = SurvivalMode.new()
	mode2.configure_from_save(saved, [guard])
	mode2.setup(w.tribes[1], w.tribes[0], w.um, w.tc, w.nav, saved["base_cell"], gs2)
	mode2.load_state(saved)
	gs2.load_tracking(tracking)
	check(mode2.wave == 1 and absf(mode2.time_to_next_wave() - mode.time_to_next_wave()) < 0.001,
		"wave counter and timer survive")
	check(mode2.wave_interval == 40.0 and mode2.growth_mult == 2 and mode2.guardians.size() == 1
		and mode2.guardians[0] == guard, "the scenario knobs and the guardians")
	check(mode2.spawn_cells == mode.spawn_cells and mode2.base_cell == mode.base_cell, "the spawn points")
	check(gs2.is_defeat_exempt(1) and gs2.is_defeat_exempt(0), "the shields of both tribes")
	check_near(gs2.match_time, 321.0, "the game time")
	mode.free()
	mode2.free()
	gs.free()
	gs2.free()
	_free_world(w)
