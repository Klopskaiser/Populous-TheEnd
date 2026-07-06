extends TestBase

## Phase 7: AI state machine, AI behaviour through TribeCommands (symmetry —
## the AI cannot cheat), MatchConfig and the N-tribe win condition. The
## GameState script is instantiated directly (autoloads are absent in the
## headless test runner).

const GameStateScript: GDScript = preload("res://scripts/core/game_state.gd")

const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const SITE_SCENE: PackedScene = preload("res://scenes/buildings/reincarnation_site.tscn")
const WARRIOR_CAMP_SCENE: PackedScene = preload("res://scenes/buildings/warrior_camp.tscn")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


## Standalone world with two tribes (0 = enemy/player stand-in, 1 = AI).
func _make_world() -> Dictionary:
	var td: TerrainData = _flat_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var tribes: Array[Tribe] = [Tribe.new(0), Tribe.new(1)]
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, tribes, tm, wpm)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um, wpm)
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(nav, bm, um, tm)
	return {
		"td": td, "nav": nav, "tribes": tribes,
		"unit_manager": um, "building_manager": bm,
		"tree_manager": tm, "wood_pile_manager": wpm, "commands": tc,
	}


func _free_world(w: Dictionary) -> void:
	w.commands.free()
	w.tree_manager.free()
	w.wood_pile_manager.free()
	w.building_manager.free()
	w.unit_manager.free()


func _make_ai(w: Dictionary, tribe: Tribe, anchor: Vector2i) -> AIController:
	var ai: AIController = AIController.new()
	ai.setup(tribe, w.commands, w.unit_manager, w.building_manager,
		w.tree_manager, w.nav, anchor)
	return ai


# --- State machine (pure) ------------------------------------------------------------

func test_state_transitions() -> void:
	var low: Dictionary = AIState.make_snapshot(5, 5, 0, 1, 0, true)
	check(AIState.next_state(AIState.State.BUILD, low) == AIState.State.BUILD,
		"low population/buildings keeps BUILD")

	var built: Dictionary = AIState.make_snapshot(AIState.POP_FOR_TRAIN, 18, 0,
		AIState.TARGET_HUTS, AIState.TARGET_CAMPS, true)
	check(AIState.next_state(AIState.State.BUILD, built) == AIState.State.TRAIN,
		"base complete + population -> TRAIN")

	var army_ready: Dictionary = AIState.make_snapshot(30, 15, AIState.ARMY_ATTACK_SIZE,
		AIState.TARGET_HUTS, AIState.TARGET_CAMPS, true)
	check(AIState.next_state(AIState.State.TRAIN, army_ready) == AIState.State.ATTACK,
		"army at target + shaman alive -> ATTACK")

	var no_shaman: Dictionary = AIState.make_snapshot(30, 15, AIState.ARMY_ATTACK_SIZE,
		AIState.TARGET_HUTS, AIState.TARGET_CAMPS, false)
	check(AIState.next_state(AIState.State.TRAIN, no_shaman) == AIState.State.TRAIN,
		"dead shaman blocks the attack")

	var lost_huts: Dictionary = AIState.make_snapshot(30, 15, 5,
		AIState.TARGET_HUTS - 1, AIState.TARGET_CAMPS, true)
	check(AIState.next_state(AIState.State.TRAIN, lost_huts) == AIState.State.BUILD,
		"lost hut sends TRAIN back to BUILD")

	var decimated: Dictionary = AIState.make_snapshot(20, 10, AIState.ARMY_RETREAT_SIZE - 1,
		AIState.TARGET_HUTS, AIState.TARGET_CAMPS, true)
	check(AIState.next_state(AIState.State.ATTACK, decimated) == AIState.State.TRAIN,
		"decimated army falls back to TRAIN (base intact)")

	var decimated_no_base: Dictionary = AIState.make_snapshot(20, 10, 0, 1, 1, false)
	check(AIState.next_state(AIState.State.ATTACK, decimated_no_base) == AIState.State.BUILD,
		"decimated army + wrecked base falls back to BUILD")

	var attacking: Dictionary = AIState.make_snapshot(30, 10, AIState.ARMY_ATTACK_SIZE,
		AIState.TARGET_HUTS, AIState.TARGET_CAMPS, true)
	check(AIState.next_state(AIState.State.ATTACK, attacking) == AIState.State.ATTACK,
		"healthy attack keeps running")


func test_training_mix() -> void:
	check(AIState.next_training_kind(0, 0, 0) == &"warrior",
		"empty army trains a warrior first (biggest share)")
	check(AIState.next_training_kind(6, 0, 0) == &"firewarrior",
		"warrior surplus -> firewarrior next")
	check(AIState.next_training_kind(5, 3, 0) == &"preacher",
		"warrior+firewarrior covered -> preacher next")


# --- Symmetry: the AI cannot cheat ----------------------------------------------------

func test_symmetry_no_cheat() -> void:
	var w: Dictionary = _make_world()
	var ai_tribe: Tribe = w.tribes[1]

	# Invalid plot (out of bounds) -> no building, no side effects.
	var before: int = ai_tribe.buildings.size()
	var built: Building = w.commands.place_building(ai_tribe, HUT_SCENE, Vector2i(-10, -10))
	check(built == null, "place_building on an invalid cell fails for the AI")
	check(ai_tribe.buildings.size() == before, "failed placement adds no building")

	# Occupied plot -> second placement fails.
	var cell: Vector2i = Vector2i(60, 60)
	var first: Building = w.commands.place_building(ai_tribe, HUT_SCENE, cell)
	check(first != null, "valid placement works")
	check(w.commands.place_building(ai_tribe, HUT_SCENE, cell) == null,
		"occupied plot rejects the second building")

	# No stored charge -> cast fails; a charge without a living shaman too.
	ai_tribe.set_spells(Spell.create_default_set())
	check(not w.commands.cast_spell(ai_tribe, &"fireball", Vector3(60, 5, 60)),
		"cast without stored charge fails")
	var spell: Spell = ai_tribe.get_spell(&"fireball")
	spell.charges = 1
	check(not w.commands.cast_spell(ai_tribe, &"fireball", Vector3(60, 5, 60)),
		"cast without living shaman fails")
	check(spell.charges == 1, "failed cast keeps the charge")

	_free_world(w)


# --- BUILD tick -----------------------------------------------------------------------

func test_build_tick_places_and_prays() -> void:
	var w: Dictionary = _make_world()
	var ai_tribe: Tribe = w.tribes[1]
	var anchor: Vector2i = Vector2i(64, 64)
	w.building_manager.place(SITE_SCENE, ai_tribe, anchor, 0, true)
	for i in range(10):
		w.unit_manager.spawn_unit(BRAVE_SCENE, 1,
			w.nav.cell_to_world(anchor + Vector2i(6, i - 4)))
	var ai: AIController = _make_ai(w, ai_tribe, anchor)

	var buildings_before: int = ai_tribe.buildings.size()
	ai.tick_ai()
	check(ai.state == AIState.State.BUILD, "fresh base starts in BUILD")
	check(ai_tribe.buildings.size() == buildings_before + 1,
		"BUILD tick places a construction site via TribeCommands")
	var site: Building = ai_tribe.buildings[ai_tribe.buildings.size() - 1]
	check(site.under_construction, "the new building is a construction site")
	check(site is Hut, "the first building is a hut")

	var praying: int = 0
	for unit in ai_tribe.units:
		if unit.state == Unit.State.PRAY:
			praying += 1
	check(praying == AIController.PRAY_BRAVES,
		"BUILD tick sends %d braves to pray" % AIController.PRAY_BRAVES)

	ai.tick_ai()
	check(ai_tribe.buildings.size() == buildings_before + 1,
		"only one construction site at a time")

	ai.free()
	_free_world(w)


# --- TRAIN tick -----------------------------------------------------------------------

func test_train_tick_enrolls_braves() -> void:
	var w: Dictionary = _make_world()
	var ai_tribe: Tribe = w.tribes[1]
	var anchor: Vector2i = Vector2i(64, 64)
	var camp: TrainingBuilding = w.building_manager.place(
		WARRIOR_CAMP_SCENE, ai_tribe, anchor, 0, true) as TrainingBuilding
	check(camp != null and camp.is_usable(), "pre-built warrior camp is usable")
	for i in range(12):
		w.unit_manager.spawn_unit(BRAVE_SCENE, 1,
			w.nav.cell_to_world(anchor + Vector2i(8, i - 6)))
	var ai: AIController = _make_ai(w, ai_tribe, anchor)

	ai._tick_train(ai.make_snapshot())
	check(camp.incoming.size() == AIController.TRAIN_BATCH,
		"TRAIN tick enrols a batch of braves at the camp")
	var training: int = 0
	for unit in ai_tribe.units:
		if unit.state == Unit.State.TRAIN:
			training += 1
	check(training == AIController.TRAIN_BATCH, "enrolled braves are in TRAIN state")

	# The economy floor is respected: never train below MIN_ECONOMY_BRAVES.
	var braves_left: int = 0
	for unit in ai_tribe.units:
		if unit is Brave and unit.state != Unit.State.TRAIN:
			braves_left += 1
	check(braves_left >= AIState.MIN_ECONOMY_BRAVES - AIController.TRAIN_BATCH,
		"a minimum economy crew stays out of training")

	ai.free()
	_free_world(w)


# --- Win condition ---------------------------------------------------------------------

func _usable_hut() -> Building:
	var hut: Building = HUT_SCENE.instantiate() as Building
	hut.under_construction = false
	return hut


func test_defeat_condition() -> void:
	var tribe: Tribe = Tribe.new(0)
	check(GameStateScript.is_tribe_defeated(tribe),
		"empty tribe counts as defeated")

	var brave: Brave = Brave.new()
	tribe.add_unit(brave)
	check(not GameStateScript.is_tribe_defeated(tribe),
		"a living unit keeps the tribe alive")
	brave.state = Unit.State.DEAD
	check(GameStateScript.is_tribe_defeated(tribe),
		"a dead unit does not keep the tribe alive")
	tribe.remove_unit(brave)

	var hut: Building = _usable_hut()
	tribe.add_building(hut)
	check(not GameStateScript.is_tribe_defeated(tribe),
		"a usable hut keeps the tribe alive (spawns braves)")
	hut.health = int(hut.max_health * 0.5)   # stage >= 1 -> unusable
	check(GameStateScript.is_tribe_defeated(tribe),
		"a damaged (unusable) hut cannot save a tribe without units")
	tribe.remove_building(hut)
	hut.free()

	var site: Building = SITE_SCENE.instantiate() as Building
	site.under_construction = false
	tribe.add_building(site)
	check(not GameStateScript.is_tribe_defeated(tribe),
		"a usable reincarnation site keeps the tribe alive (shaman respawn)")
	tribe.remove_building(site)
	site.free()

	var camp: Building = WARRIOR_CAMP_SCENE.instantiate() as Building
	camp.under_construction = false
	tribe.add_building(camp)
	check(GameStateScript.is_tribe_defeated(tribe),
		"a training building alone cannot save a tribe without units")
	tribe.remove_building(camp)
	camp.free()
	brave.free()


func test_n_tribe_win_condition() -> void:
	var gs: Node = GameStateScript.new()
	var tribes: Array[Tribe] = [Tribe.new(0), Tribe.new(1), Tribe.new(2)]
	var braves: Array[Brave] = []
	for tribe in tribes:
		var brave: Brave = Brave.new()
		braves.append(brave)
		tribe.add_unit(brave)
	gs.tribes = tribes

	var defeated: Array[int] = []
	var winner: Array[int] = []
	gs.tribe_defeated.connect(func(id: int) -> void: defeated.append(id))
	gs.match_ended.connect(func(id: int) -> void: winner.append(id))
	gs.start_win_tracking()

	gs.check_defeats()
	check(defeated.is_empty(), "nobody defeated at match start")

	# First AI falls -> defeated, but the match keeps running (2 tribes left).
	braves[1].state = Unit.State.DEAD
	gs.check_defeats()
	check(defeated == ([1] as Array[int]), "tribe 1 is defeated")
	check(winner.is_empty() and not gs.match_over,
		"two survivors -> the match keeps running")

	# Second AI falls -> only the player remains: victory.
	braves[2].state = Unit.State.DEAD
	gs.check_defeats()
	check(gs.match_over, "one survivor ends the match")
	check(winner == ([0] as Array[int]), "the player is the winner")

	# Player defeated while AIs live -> immediate loss.
	var gs2: Node = GameStateScript.new()
	var tribes2: Array[Tribe] = [Tribe.new(0), Tribe.new(1), Tribe.new(2)]
	var braves2: Array[Brave] = []
	for tribe in tribes2:
		var brave: Brave = Brave.new()
		braves2.append(brave)
		tribe.add_unit(brave)
	gs2.tribes = tribes2
	var winner2: Array[int] = []
	gs2.match_ended.connect(func(id: int) -> void: winner2.append(id))
	gs2.start_win_tracking()
	braves2[0].state = Unit.State.DEAD
	gs2.check_defeats()
	check(gs2.match_over, "player defeat ends the match immediately")
	check(winner2.size() == 1 and winner2[0] != 0,
		"an AI tribe is reported as winner")

	for brave in braves:
		brave.free()
	for brave in braves2:
		brave.free()
	gs.free()
	gs2.free()


# --- MatchConfig ------------------------------------------------------------------------

func test_match_config() -> void:
	check(MatchConfig.skirmish(1).tribe_count() == 2, "1 AI -> 2 tribes")
	check(MatchConfig.skirmish(3).tribe_count() == 4, "3 AIs -> 4 tribes")
	check(MatchConfig.skirmish(99).ai_count == MatchConfig.MAX_AI,
		"AI count is clamped to MAX_AI")
	check(MatchConfig.skirmish(0).tribe_count() == 2,
		"AI count is clamped to MIN_AI")
	check(MatchConfig.start_mission().tribe_count() == 2,
		"start mission runs with 2 tribes")
	check(MatchConfig.debug_battle().tribe_count() == 2,
		"debug battle runs with 2 tribes")
