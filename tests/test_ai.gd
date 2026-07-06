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
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")


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

	var built: Dictionary = AIState.make_snapshot(AIState.POP_FOR_TRAIN, 12, 0,
		AIState.MIN_HUTS_FOR_TRAIN, AIState.MIN_CAMPS_FOR_TRAIN, true)
	check(AIState.next_state(AIState.State.BUILD, built) == AIState.State.TRAIN,
		"essentials standing + population -> TRAIN (base finishes in parallel)")

	var army_ready: Dictionary = AIState.make_snapshot(30, 15, AIState.ARMY_ATTACK_SIZE,
		AIState.TARGET_HUTS, AIState.TARGET_CAMPS, true)
	check(AIState.next_state(AIState.State.TRAIN, army_ready) == AIState.State.ATTACK,
		"army at target + shaman alive -> ATTACK")

	var no_shaman: Dictionary = AIState.make_snapshot(30, 15, AIState.ARMY_ATTACK_SIZE,
		AIState.TARGET_HUTS, AIState.TARGET_CAMPS, false)
	check(AIState.next_state(AIState.State.TRAIN, no_shaman) == AIState.State.TRAIN,
		"dead shaman blocks the attack")

	var lost_huts: Dictionary = AIState.make_snapshot(30, 15, 5,
		0, AIState.TARGET_CAMPS, true)
	check(AIState.next_state(AIState.State.TRAIN, lost_huts) == AIState.State.BUILD,
		"losing every hut sends TRAIN back to BUILD")

	var decimated: Dictionary = AIState.make_snapshot(20, 10, AIState.ARMY_RETREAT_SIZE - 1,
		AIState.TARGET_HUTS, AIState.TARGET_CAMPS, true)
	check(AIState.next_state(AIState.State.ATTACK, decimated) == AIState.State.TRAIN,
		"decimated army falls back to TRAIN (base intact)")

	var decimated_no_base: Dictionary = AIState.make_snapshot(20, 10, 0, 0, 0, false)
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
	var order: Array[StringName] = AIState.training_kind_order(6, 0, 0)
	check(order.size() == 3 and order[0] == &"firewarrior",
		"training_kind_order sorts all three kinds by deficit")


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
	# Plots need wood in reach — give the base a small grove.
	for i in range(4):
		w.tree_manager.spawn_tree(anchor + Vector2i(10 + 3 * i, 10), TreeResource.MAX_STAGE)
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
		"10 braves support only one construction site at a time")

	# More braves allow parallel sites: the next tick opens a second one
	# (a warrior camp — the first camp follows right after the first hut).
	for i in range(10):
		w.unit_manager.spawn_unit(BRAVE_SCENE, 1,
			w.nav.cell_to_world(anchor + Vector2i(-6, i - 4)))
	ai.tick_ai()
	check(ai_tribe.buildings.size() == buildings_before + 2,
		"20 braves support a second parallel construction site")
	var second: Building = ai_tribe.buildings[ai_tribe.buildings.size() - 1]
	check(second is WarriorCamp,
		"the first training camp goes up right after the first hut")
	ai.tick_ai()
	check(ai_tribe.buildings.size() == buildings_before + 2,
		"the parallel-site cap holds (no third site with 20 braves)")

	ai.free()
	_free_world(w)


# --- Defence ---------------------------------------------------------------------

func test_defense_militia() -> void:
	var w: Dictionary = _make_world()
	var ai_tribe: Tribe = w.tribes[1]
	var anchor: Vector2i = Vector2i(64, 64)
	w.building_manager.place(SITE_SCENE, ai_tribe, anchor, 0, true)
	for i in range(5):
		w.unit_manager.spawn_unit(BRAVE_SCENE, 1,
			w.nav.cell_to_world(anchor + Vector2i(6, i)))
	# One enemy warrior walks into the village.
	var enemy: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 0,
		w.nav.cell_to_world(anchor + Vector2i(2, 6)))
	var ai: AIController = _make_ai(w, ai_tribe, anchor)

	ai.tick_ai()
	var attacking: int = 0
	for unit in ai_tribe.units:
		if unit.state == Unit.State.ATTACK:
			attacking += 1
	check(attacking > 0,
		"a lone raider triggers the brave militia (explicit attack order)")
	check(is_instance_valid(enemy), "the enemy itself is untouched by the order")

	ai.free()
	_free_world(w)


func test_defense_hopeless_no_suicide() -> void:
	var w: Dictionary = _make_world()
	var ai_tribe: Tribe = w.tribes[1]
	var anchor: Vector2i = Vector2i(64, 64)
	for i in range(10):
		w.unit_manager.spawn_unit(WARRIOR_SCENE, 0,
			w.nav.cell_to_world(anchor + Vector2i(2 + (i % 3), 4 + i / 3)))
	var brave: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1,
		w.nav.cell_to_world(anchor + Vector2i(-4, 0)))
	var ai: AIController = _make_ai(w, ai_tribe, anchor)

	ai.tick_ai()
	check(brave.state != Unit.State.ATTACK,
		"hopeless odds: the lone brave is not sent into a suicide defence")

	ai.free()
	_free_world(w)


# --- Wood piles: only near the site -------------------------------------------------

func test_wood_pile_only_near_site() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var site_cell: Vector2i = Vector2i(60, 60)
	var hut: Building = w.commands.place_building(tribe, HUT_SCENE, site_cell)
	check(hut != null, "construction site placed")
	var brave: Brave = w.unit_manager.spawn_unit(BRAVE_SCENE, 1,
		w.nav.cell_to_world(site_cell + Vector2i(4, 0))) as Brave
	brave.order_build(hut)

	# A far pile (way beyond JOB_TREE_RADIUS — e.g. in an enemy base) must be
	# ignored; with a tree nearby the brave chops instead.
	w.wood_pile_manager.deposit(w.nav.cell_to_world(Vector2i(120, 120)), 3)
	w.tree_manager.spawn_tree(Vector2i(66, 66), TreeResource.MAX_STAGE)
	check(brave._try_fetch_wood(), "a wood source is found")
	check(brave.task == Brave.Task.CHOP,
		"the distant pile is ignored — the nearby tree wins")

	# A pile near the site takes priority again (leftovers get used first).
	w.wood_pile_manager.deposit(w.nav.cell_to_world(Vector2i(70, 60)), 3)
	check(brave._try_fetch_wood(), "a wood source is found again")
	check(brave.task == Brave.Task.PICKUP,
		"a pile near the site is preferred over the tree")

	ai_cleanup_brave(brave)
	_free_world(w)


## Releases claims so freeing the world does not warn (tree claims etc.).
func ai_cleanup_brave(brave: Brave) -> void:
	brave._interrupt_tasks()


# --- Fragile construction sites (spells wreck them outright) --------------------------

func test_fragile_construction_site() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var site: Building = w.commands.place_building(tribe, HUT_SCENE, Vector2i(60, 60))
	check(site != null and site.under_construction, "construction site placed")
	site.apply_destruction_stages(1)
	check(site.health == 0, "one staged spell hit levels a construction site")
	check(not site.under_construction,
		"the wreck is no longer under construction (workers drop it)")
	check(not (site in tribe.buildings), "the wreck left the tribe registry")

	# A finished building still takes staged damage normally.
	var hut: Building = w.building_manager.place(HUT_SCENE, tribe, Vector2i(80, 80), 0, true)
	hut.apply_destruction_stages(1)
	check(hut.health > 0 and hut.destruction_stage() == 1,
		"a finished building only drops one stage per hit")

	_free_world(w)


# --- Gradually bigger waves ------------------------------------------------------------

func test_attack_wave_growth() -> void:
	var w: Dictionary = _make_world()
	var ai: AIController = _make_ai(w, w.tribes[1], Vector2i(64, 64))
	check(ai.attack_wave_size == AIState.ARMY_ATTACK_SIZE,
		"the first wave uses the base attack size")
	ai.state = AIState.State.ATTACK
	ai.tick_ai()   # empty tribe -> falls back, wave grows
	check(ai.state != AIState.State.ATTACK, "empty tribe falls out of ATTACK")
	check(ai.attack_wave_size == AIState.ARMY_ATTACK_SIZE + AIState.ATTACK_WAVE_GROWTH,
		"the next wave target grew after the attack ended")

	# The snapshot carries the dynamic target into the state machine.
	var snap: Dictionary = AIState.make_snapshot(30, 10, AIState.ARMY_ATTACK_SIZE,
		AIState.TARGET_HUTS, AIState.TARGET_CAMPS, true)
	snap["army_target"] = AIState.ARMY_ATTACK_SIZE + AIState.ATTACK_WAVE_GROWTH
	check(AIState.next_state(AIState.State.TRAIN, snap) == AIState.State.TRAIN,
		"the old army size no longer triggers the bigger wave")
	snap["army"] = snap["army_target"]
	check(AIState.next_state(AIState.State.TRAIN, snap) == AIState.State.ATTACK,
		"reaching the grown target triggers the attack")

	ai.free()
	_free_world(w)


# --- Endless scaling & expansion --------------------------------------------------------

func test_endless_building_scaling() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var ai: AIController = _make_ai(w, tribe, Vector2i(64, 64))
	# Full base: 3 huts + one camp of each kind, all pre-built.
	for i in range(3):
		w.building_manager.place(HUT_SCENE, tribe, Vector2i(40 + 6 * i, 40), 0, true)
	w.building_manager.place(WARRIOR_CAMP_SCENE, tribe, Vector2i(40, 50), 0, true)
	w.building_manager.place(preload("res://scenes/buildings/firewarrior_camp.tscn"),
		tribe, Vector2i(48, 50), 0, true)
	w.building_manager.place(preload("res://scenes/buildings/temple.tscn"),
		tribe, Vector2i(56, 50), 0, true)
	check(ai._next_building_scene({}) == null,
		"full base without housing pressure: nothing to build")

	# Two more huts -> the camp target grows -> another camp (fewest kind).
	w.building_manager.place(HUT_SCENE, tribe, Vector2i(40, 58), 0, true)
	w.building_manager.place(HUT_SCENE, tribe, Vector2i(48, 58), 0, true)
	check(ai._next_building_scene({}) == AIController.WARRIOR_CAMP_SCENE,
		"extra huts raise the camp target (warrior camp first)")

	# Housing pressure: population at 80% capacity -> a new hut, forever.
	var braves: Array[Brave] = []
	var need: int = int(float(tribe.housing_capacity()) * AIController.HOUSING_PRESSURE)
	for i in range(need):
		var brave: Brave = Brave.new()
		braves.append(brave)
		tribe.add_unit(brave)
	check(ai._next_building_scene({}) == AIController.HUT_SCENE,
		"housing pressure always asks for another hut")

	for brave in braves:
		brave.free()
	ai.free()
	_free_world(w)


func test_expansion_toward_wood() -> void:
	var w: Dictionary = _make_world()
	var ai: AIController = _make_ai(w, w.tribes[1], Vector2i(64, 64))
	# No trees near the base, a grove far away: the plot search expands there.
	for i in range(4):
		w.tree_manager.spawn_tree(Vector2i(100 + 3 * (i % 2), 100 + 3 * (i / 2)),
			TreeResource.MAX_STAGE)
	var cell: Vector2i = ai._find_plot(Vector2i(4, 4))
	check(cell.x >= 0, "an expansion plot is found at the distant wood")
	check(Vector2(cell - Vector2i(100, 100)).length() < 40.0,
		"the plot sits near the distant grove, not near the empty base")

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
