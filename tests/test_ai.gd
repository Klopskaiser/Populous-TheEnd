extends TestBase

## Phase 7: AI state machine, AI behaviour through TribeCommands (symmetry —
## the AI cannot cheat), MatchConfig and the N-tribe win condition. The
## GameState script is instantiated directly (autoloads are absent in the
## headless test runner).

const GameStateScript: GDScript = preload("res://scripts/core/game_state.gd")

const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const SITE_SCENE: PackedScene = preload("res://scenes/buildings/reincarnation_site.tscn")
const WARRIOR_CAMP_SCENE: PackedScene = preload("res://scenes/buildings/warrior_camp.tscn")
const FIREWARRIOR_CAMP_SCENE: PackedScene = preload("res://scenes/buildings/firewarrior_camp.tscn")
const TEMPLE_SCENE: PackedScene = preload("res://scenes/buildings/temple.tscn")
const FORESTER_SCENE: PackedScene = preload("res://scenes/buildings/forester.tscn")
const WORKSHOP_SCENE: PackedScene = preload("res://scenes/buildings/workshop.tscn")
const WATCHTOWER_SCENE: PackedScene = preload("res://scenes/buildings/watchtower.tscn")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


## Standalone world with two tribes (0 = enemy/player stand-in, 1 = AI).
func _make_world(height: float = 5.0) -> Dictionary:
	var td: TerrainData = _flat_terrain(height)
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


## Seenland early-game lag: several AIs must not tick in the SAME frame —
## stagger_offset phase-shifts each 1-Hz tick so the per-second work spreads
## across the second (still exactly one tick per second per AI).
func test_ai_tick_stagger() -> void:
	var w: Dictionary = _make_world()
	var ais: Array[AIController] = []
	for i in range(3):
		var ai: AIController = _make_ai(w, w.tribes[1], Vector2i(64, 64))
		ai.stagger_offset(float(i) / 3.0)
		ais.append(ai)
	# Feed 30-Hz deltas through the production _process path and record the
	# frame of each AI's first tick (visible via _tick_count).
	var first_frame: Array[int] = [-1, -1, -1]
	for f in range(120):
		for i in range(3):
			ais[i]._process(1.0 / 30.0)
			if first_frame[i] < 0 and ais[i]._tick_count > 0:
				first_frame[i] = f
	check(first_frame[0] >= 0 and first_frame[1] >= 0 and first_frame[2] >= 0,
		"every staggered AI ticked within the first 4 s")
	check(first_frame[0] != first_frame[1] and first_frame[1] != first_frame[2]
		and first_frame[0] != first_frame[2],
		"staggered AIs tick in three different frames (%s)" % [first_frame])
	# Still 1 Hz each: after 120 frames (4 s) every AI ticked 3-4 times.
	for i in range(3):
		check(ais[i]._tick_count >= 3 and ais[i]._tick_count <= 4,
			"AI %d keeps its 1-Hz cadence (%d ticks in 4 s)" % [i, ais[i]._tick_count])
	for ai in ais:
		ai.free()
	_free_world(w)


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

func test_build_tick_places_construction_site() -> void:
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


## Seenland early-game lag: a failed plot search backs off for a few ticks
## instead of re-running the expensive double ring scan every second.
func test_plot_search_cooldown_after_failure() -> void:
	var w: Dictionary = _make_world()
	var ai: AIController = _make_ai(w, w.tribes[1], Vector2i(64, 64))
	# No trees anywhere -> no supplied plot, no expansion anchor -> failure.
	AIController.dbg_plot_scans = 0
	ai.tick_ai()
	check(AIController.dbg_plot_scans == 1, "first tick runs the plot search")
	for i in range(AIController.PLOT_FAIL_COOLDOWN_TICKS):
		ai.tick_ai()
	check(AIController.dbg_plot_scans == 1,
		"the search is skipped during the cooldown")
	ai.tick_ai()
	check(AIController.dbg_plot_scans == 2,
		"after the cooldown the search runs again")
	ai.free()
	_free_world(w)


## On maps where can_place_at fails over huge areas (water) the ring scan is
## capped: it must not sweep all ~2800 cells of the 30-ring every tick.
func test_plot_search_scan_cap() -> void:
	var w: Dictionary = _make_world(1.0)   # below sea level -> nothing placeable
	var ai: AIController = _make_ai(w, w.tribes[1], Vector2i(64, 64))
	AIController.dbg_plot_cells = 0
	ai.tick_ai()
	check(AIController.dbg_plot_cells <= AIController.MAX_PLOT_SCAN_CELLS + 1,
		"the ring scan stops at the cell cap (%d cells)" % AIController.dbg_plot_cells)
	ai.free()
	_free_world(w)


## 10g ERSETZT test_plot_reachable_success_cache: der Positiv-Cache
## (_reachable_plots) ist entfallen, weil die Pruefung jetzt ein Insel-Lookup ist
## und den zu cachen teurer waere als der Lookup. Die beiden Tests hier pruefen
## dafuer das WICHTIGERE: dass die Pruefung dieselbe Frage stellt wie die
## Nachkontrolle, und dass ein Bann wieder ablaeuft.
func test_plot_reachability_accepts_flat_ground() -> void:
	var w: Dictionary = _make_world()
	var ai: AIController = _make_ai(w, w.tribes[1], Vector2i(64, 64))
	check(ai._plot_reachable(Vector2i(70, 64), Vector2i(2, 2), 0),
		"flacher Bauplatz ist erreichbar")
	ai.free()
	_free_world(w)


## WICHTIG fuer eigene Insel-Tests: NavGrid._ensure_islands ist gegen
## ISLAND_REFRESH_MS gedrosselt. Wer vor der Terrainaenderung schon etwas
## Insel-basiertes abfragt, bekommt danach VERALTETE Labels — deshalb hier eine
## frische Welt und kein Aufruf vor dem Graben.
func test_plot_reachability_rejects_a_cut_off_patch() -> void:
	var w: Dictionary = _make_world()
	var ai: AIController = _make_ai(w, w.tribes[1], Vector2i(20, 20))
	for vz in range(w.td.size + 1):
		for vx in range(w.td.size + 1):
			var inner: bool = vx >= 74 and vx <= 86 and vz >= 74 and vz <= 86
			var outer: bool = vx >= 70 and vx <= 90 and vz >= 70 and vz <= 90
			if outer and not inner:
				w.td.set_vertex_height(vx, vz, 1.0)   # unter der Wasserlinie
	w.nav.update_region(Rect2i(Vector2i(68, 68), Vector2i(24, 24)))
	check(w.nav.island_at(Vector2i(78, 78)) != w.nav.island_at(Vector2i(20, 20)),
		"der Graben trennt wirklich (Testvoraussetzung)")
	check(not ai._plot_reachable(Vector2i(78, 78), Vector2i(2, 2), 0),
		"eine abgeschnittene Insel ist NICHT erreichbar")
	ai.free()
	_free_world(w)


func test_plot_ban_expires_so_a_landbridge_reopens_the_ground() -> void:
	var w: Dictionary = _make_world()
	var ai: AIController = _make_ai(w, w.tribes[1], Vector2i(64, 64))
	var cell: Vector2i = Vector2i(90, 90)
	ai._ban_plot(cell)
	check(ai._plot_banned(cell), "frisch gebannt")
	ai._tick_count += Balance.AI_PLOT_BAN_TICKS
	check(not ai._plot_banned(cell),
		"der Bann laeuft ab - eine Landbruecke kann das Land anschliessen "
			+ "(vor 10g galt er die ganze Sitzung)")
	ai.free()
	_free_world(w)


## The expansion anchor (nearest tree to the base) is cached for a few ticks
## and drops out when the tree disappears.
func test_expansion_anchor_cache() -> void:
	var w: Dictionary = _make_world()
	var ai: AIController = _make_ai(w, w.tribes[1], Vector2i(64, 64))
	var tree: TreeResource = w.tree_manager.spawn_tree(Vector2i(90, 64), 3)
	var anchor: Vector2i = ai._expansion_anchor()
	check(anchor == Vector2i(90, 64), "anchor is the nearest tree's cell")
	# A nearer tree appears — the cached anchor is kept during the TTL...
	w.tree_manager.spawn_tree(Vector2i(80, 64), 3)
	check(ai._expansion_anchor() == Vector2i(90, 64),
		"within the TTL the cached anchor is reused")
	# ...and re-picked after it.
	for i in range(AIController.EXPANSION_ANCHOR_TTL_TICKS + 1):
		ai._expansion_anchor()
	check(ai._expansion_anchor() == Vector2i(80, 64),
		"after the TTL the anchor is re-picked (nearer grove wins)")
	# A vanished anchor tree forces an immediate re-pick.
	w.tree_manager._remove_tree(w.tree_manager._occupied[Vector2i(80, 64)])
	w.tree_manager._remove_tree(tree)
	check(ai._expansion_anchor() == Vector2i(-1, -1),
		"without trees the anchor is empty again")
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
	# Full base: TARGET_HUTS huts + one camp of each kind, all pre-built.
	for i in range(AIState.TARGET_HUTS):
		w.building_manager.place(HUT_SCENE, tribe, Vector2i(40 + 6 * i, 40), 0, true)
	# The base wood rack is new in 10e and comes right after the first camp —
	# without it every check below would just ask for the rack.
	w.building_manager.place(preload("res://scenes/buildings/wood_depot.tscn"),
		tribe, Vector2i(36, 44), 0, true)
	w.building_manager.place(WARRIOR_CAMP_SCENE, tribe, Vector2i(40, 50), 0, true)
	w.building_manager.place(preload("res://scenes/buildings/firewarrior_camp.tscn"),
		tribe, Vector2i(48, 50), 0, true)
	w.building_manager.place(preload("res://scenes/buildings/temple.tscn"),
		tribe, Vector2i(56, 50), 0, true)
	# A forester too (phase 7d): with no trees near the base the AI wants one
	# before expanding, so the "full base" must include it for this check.
	w.building_manager.place(preload("res://scenes/buildings/forester.tscn"),
		tribe, Vector2i(56, 58), 0, true)
	# And the workshop (phase 7f): it follows right after the temple.
	w.building_manager.place(preload("res://scenes/buildings/workshop.tscn"),
		tribe, Vector2i(64, 50), 0, true)
	# The catapult workshop is followed by the fire-ram workshop (cheap
	# pressure vehicle), then the two defensive watchtowers (phase 7h) and the
	# expensive airship wharf — the full base includes all of them before the
	# endless scaling kicks in.
	check(ai._next_building_scene(ai.build_tick_cache()) == AIController.FIRERAM_WORKSHOP_SCENE,
		"after the workshop the AI builds a fire-ram workshop")
	w.building_manager.place(preload("res://scenes/buildings/fire_ram_workshop.tscn"),
		tribe, Vector2i(72, 50), 0, true)
	check(ai._next_building_scene(ai.build_tick_cache()) == AIController.WATCHTOWER_SCENE,
		"after the fire-ram workshop the AI builds a watchtower")
	for i in range(Balance.AI_TARGET_WATCHTOWERS):
		w.building_manager.place(preload("res://scenes/buildings/watchtower.tscn"),
			tribe, Vector2i(40 + 4 * i, 64), 0, true)
	check(ai._next_building_scene(ai.build_tick_cache()) == AIController.AIRSHIP_WHARF_SCENE,
		"after the towers the AI builds the airship wharf")
	w.building_manager.place(preload("res://scenes/buildings/airship_wharf.tscn"),
		tribe, Vector2i(72, 60), 0, true)
	check(ai._next_building_scene(ai.build_tick_cache()) == null,
		"full base without housing pressure: nothing to build")

	# 10g: extra camps no longer follow the HUT COUNT but the BRAVE STREAM — an
	# unmanned hut delivers nothing, so two more empty huts must NOT raise the camp
	# target. Manning them does, because growth_per_minute() then rises.
	w.building_manager.place(HUT_SCENE, tribe, Vector2i(40, 58), 0, true)
	w.building_manager.place(HUT_SCENE, tribe, Vector2i(48, 58), 0, true)
	check(ai._next_building_scene(ai.build_tick_cache()) == null,
		"unbemannte Zusatzhuetten heben das Lagerziel NICHT (Strom statt Huettenzahl)")

	# Housing pressure: population at 80% capacity -> a new hut, forever.
	var braves: Array[Brave] = []
	var need: int = int(float(tribe.housing_capacity()) * Balance.AI_HOUSING_PRESSURE)
	for i in range(need):
		var brave: Brave = Brave.new()
		braves.append(brave)
		tribe.add_unit(brave)
	check(ai._next_building_scene(ai.build_tick_cache()) == AIController.HUT_SCENE,
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

	ai._tick_train(ai.build_tick_cache())
	check(camp.incoming.size() == AIState.train_batch(12),
		"TRAIN tick enrols a batch of braves at the camp")
	var training: int = 0
	for unit in ai_tribe.units:
		if unit.state == Unit.State.TRAIN:
			training += 1
	check(training == AIState.train_batch(12), "enrolled braves are in TRAIN state")

	# The economy floor is respected: never train below MIN_ECONOMY_BRAVES.
	var braves_left: int = 0
	for unit in ai_tribe.units:
		if unit is Brave and unit.state != Unit.State.TRAIN:
			braves_left += 1
	check(braves_left >= AIState.min_economy_braves(12) - AIState.train_batch(12),
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

	# Phase 10d: buildings no longer save a tribe. A hut only produces WITH crew,
	# and crew members are units themselves — with zero units every hut is idle
	# forever, so it must not keep a dead tribe in the match.
	var hut: Building = _usable_hut()
	tribe.add_building(hut)
	check(GameStateScript.is_tribe_defeated(tribe),
		"a usable hut cannot save a tribe without units (10d: no crew, no spawns)")
	tribe.remove_building(hut)
	hut.free()

	var site: Building = SITE_SCENE.instantiate() as Building
	site.under_construction = false
	tribe.add_building(site)
	check(GameStateScript.is_tribe_defeated(tribe),
		"a reincarnation site cannot save a tribe without units either (10d)")
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


# --- Spell heuristics (7c) ----------------------------------------------------------------

## Arms exactly one spell with a stored charge (all others stay empty), so a
## successful cast proves the heuristic picked that spell.
func _arm_only(tribe: Tribe, id: StringName) -> void:
	if tribe.spells.is_empty():
		tribe.set_spells(Spell.create_default_set())
	for s in tribe.spells:
		s.charges = 1 if s.id == id else 0


func _pending_spell_id(tribe: Tribe) -> StringName:
	var shaman = tribe.shaman
	if shaman == null or not is_instance_valid(shaman) \
			or (shaman as Shaman).pending_spell == null:
		return &""
	return (shaman as Shaman).pending_spell.id


func test_ai_casts_volcano_on_building_cluster() -> void:
	var w: Dictionary = _make_world()
	var ai_tribe: Tribe = w.tribes[1]
	var ai: AIController = _make_ai(w, ai_tribe, Vector2i(40, 40))
	w.unit_manager.spawn_unit(SHAMAN_SCENE, 1, Vector3(40, 5, 40))
	w.building_manager.place(HUT_SCENE, w.tribes[0], Vector2i(43, 38), 0, true)
	w.building_manager.place(HUT_SCENE, w.tribes[0], Vector2i(43, 43), 0, true)
	_arm_only(ai_tribe, &"volcano")
	ai._cast_spells()
	check(_pending_spell_id(ai_tribe) == &"volcano",
		"two clustered enemy buildings -> volcano")
	ai.free()
	_free_world(w)


func test_ai_casts_sink_on_coastal_building() -> void:
	var w: Dictionary = _make_world(3.5)   # low coastal shelf
	var ai_tribe: Tribe = w.tribes[1]
	var ai: AIController = _make_ai(w, ai_tribe, Vector2i(40, 40))
	w.unit_manager.spawn_unit(SHAMAN_SCENE, 1, Vector3(40, 3.5, 40))
	w.building_manager.place(HUT_SCENE, w.tribes[0], Vector2i(43, 38), 0, true)
	_arm_only(ai_tribe, &"sink")
	ai._cast_spells()
	check(_pending_spell_id(ai_tribe) == &"sink",
		"coastal enemy building -> sink (flooding)")
	ai.free()
	_free_world(w)


func test_ai_casts_flatten_on_slope_building() -> void:
	var w: Dictionary = _make_world()
	var ai_tribe: Tribe = w.tribes[1]
	var ai: AIController = _make_ai(w, ai_tribe, Vector2i(40, 40))
	w.unit_manager.spawn_unit(SHAMAN_SCENE, 1, Vector3(40, 5, 40))
	var hut: Building = w.building_manager.place(HUT_SCENE, w.tribes[0],
		Vector2i(43, 38), 0, true)
	# Terrain step right next to the hut: a flatten there breaks the foundation
	# (step must exceed the sturdier 2.0 m break threshold + margin).
	for vz in range(37, 44):
		for vx in range(48, 54):
			w.td.set_vertex_height(vx, vz, 8.0)
	check(hut.health > 0, "hut standing before the cast")
	_arm_only(ai_tribe, &"flatten")
	ai._cast_spells()
	check(_pending_spell_id(ai_tribe) == &"flatten",
		"building next to a height step -> flatten (foundation break)")
	ai.free()
	_free_world(w)


func test_ai_casts_firestorm_on_big_cluster() -> void:
	var w: Dictionary = _make_world()
	var ai_tribe: Tribe = w.tribes[1]
	var ai: AIController = _make_ai(w, ai_tribe, Vector2i(40, 40))
	w.unit_manager.spawn_unit(SHAMAN_SCENE, 1, Vector3(40, 5, 40))
	for i in range(5):
		w.unit_manager.spawn_unit(BRAVE_SCENE, 0,
			Vector3(44 + 0.6 * float(i % 3), 5, 40 + 0.6 * float(i % 2)))
	_arm_only(ai_tribe, &"firestorm")
	ai._cast_spells()
	check(_pending_spell_id(ai_tribe) == &"firestorm",
		"big enemy cluster -> firestorm before fireball")
	ai.free()
	_free_world(w)


# --- Elimination (phase 10d) ---------------------------------------------------

## The defeat chain: last follower dies -> the circle self-destructs -> the
## shaman dies -> the tribe is out and everything it still owned is razed.
func test_last_shaman_death_eliminates_tribe_and_razes_everything() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var site: Building = w.building_manager.place(
		SITE_SCENE, tribe, Vector2i(30, 30), 0, true)
	var hut: Building = w.building_manager.place(
		HUT_SCENE, tribe, Vector2i(40, 40), 0, true)
	var brave: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, Vector3(35, 0, 35))
	var shaman: Unit = w.unit_manager.spawn_unit(SHAMAN_SCENE, 1, Vector3(36, 0, 36))
	w.building_manager.tick(0.5)
	check(site.health > 0 and hut.health > 0, "the base stands while followers live")

	# Last follower falls -> the circle gives itself up.
	brave.take_damage(9999)
	w.building_manager.tick(0.5)
	check(site.health <= 0, "the circle self-destructs without followers")
	check(hut.health > 0, "the hut is still standing at this point")

	# The shaman falls too -> defeated, and eliminate() razes the rest.
	shaman.take_damage(9999)
	var gs: Node = GameStateScript.new()
	gs.tribes = w.tribes
	gs.start_win_tracking()
	gs.check_defeats()
	check(tribe.eliminated, "the tribe is out of the match")
	check(hut.health <= 0, "its remaining buildings were razed")
	check(tribe.buildings.is_empty(), "and deregistered from the tribe")
	gs.free()
	_free_world(w)


## An eliminated tribe accepts nothing any more — from the UI or the AI.
func test_eliminated_tribe_rejects_all_commands() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var brave: Brave = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, Vector3(40, 0, 40)) as Brave
	tribe.set_spells(Spell.create_default_set())
	for spell in tribe.spells:
		spell.charges = 2
	var hut: Building = w.building_manager.place(
		HUT_SCENE, tribe, Vector2i(50, 50), 0, true)

	tribe.eliminate()
	check(tribe.eliminated, "the tribe is flagged as eliminated")
	check(hut.health <= 0, "eliminate() razed the base")
	for spell in tribe.spells:
		check(spell.charges == 0, "spell charges are void")

	# Every command path refuses.
	check(w.commands.place_building(tribe, HUT_SCENE, Vector2i(60, 60)) == null,
		"no more building placement")
	check(not w.commands.cast_spell(tribe, &"blast", Vector3(45, 5, 45)),
		"no more spell casts")
	check(not w.commands.set_spell_active(tribe, &"blast", false),
		"no more spell toggling")
	var before: Vector3 = brave.position
	w.commands.order_move([brave] as Array[Unit], Vector3(60, 5, 60))
	check(brave.state != Unit.State.MOVE and brave.position == before,
		"no more move orders")
	_free_world(w)


func test_eliminated_ai_stops_ticking() -> void:
	# Same base setup as test_build_tick_places_construction_site: the AI needs a
	# reincarnation anchor, braves and wood in reach before it builds anything.
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var anchor: Vector2i = Vector2i(64, 64)
	w.building_manager.place(SITE_SCENE, tribe, anchor, 0, true)
	for i in range(10):
		w.unit_manager.spawn_unit(BRAVE_SCENE, 1,
			w.nav.cell_to_world(anchor + Vector2i(6, i - 4)))
	for i in range(4):
		w.tree_manager.spawn_tree(anchor + Vector2i(10 + 3 * i, 10), TreeResource.MAX_STAGE)
	var ai: AIController = _make_ai(w, tribe, anchor)

	var before: int = tribe.buildings.size()
	ai.tick_ai()
	check(tribe.buildings.size() > before, "a living AI builds")
	var while_alive: int = tribe.buildings.size()

	tribe.eliminated = true
	for i in range(20):
		ai.tick_ai()
	check(tribe.buildings.size() == while_alive,
		"an eliminated AI issues no further orders")
	ai.free()
	_free_world(w)


# --- Tick cache (phase 10e, 2.0) -------------------------------------------------

## The scaling guarantee: one pass over tribe.units and one over tribe.buildings
## per tick_ai(), no matter how many subsystems run. The world below is built so
## that NO branch returns early — otherwise a non-migrated list rebuild could
## hide behind a skipped subsystem.
func test_ai_tick_cache_walks_units_once_per_tick() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var anchor: Vector2i = Vector2i(64, 64)
	w.building_manager.place(SITE_SCENE, tribe, anchor, 0, true)
	# Covered branches: build, forester staffing, workshop staffing, watchtower
	# manning, training (all three camp kinds) and defence.
	w.building_manager.place(HUT_SCENE, tribe, anchor + Vector2i(4, 0), 0, true)
	w.building_manager.place(WARRIOR_CAMP_SCENE, tribe, anchor + Vector2i(-6, 0), 0, true)
	w.building_manager.place(FIREWARRIOR_CAMP_SCENE, tribe, anchor + Vector2i(0, 8), 0, true)
	w.building_manager.place(TEMPLE_SCENE, tribe, anchor + Vector2i(0, -8), 0, true)
	w.building_manager.place(FORESTER_SCENE, tribe, anchor + Vector2i(8, 8), 0, true)
	w.building_manager.place(WORKSHOP_SCENE, tribe, anchor + Vector2i(-12, 8), 0, true)
	w.building_manager.place(WATCHTOWER_SCENE, tribe, anchor + Vector2i(8, -8), 0, true)
	for i in range(20):
		w.unit_manager.spawn_unit(BRAVE_SCENE, 1,
			w.nav.cell_to_world(anchor + Vector2i(6, i - 10)))
	for i in range(4):
		w.unit_manager.spawn_unit(WARRIOR_SCENE, 1,
			w.nav.cell_to_world(anchor + Vector2i(-4, i)))
	w.unit_manager.spawn_unit(SHAMAN_SCENE, 1, w.nav.cell_to_world(anchor))
	for i in range(4):
		w.tree_manager.spawn_tree(anchor + Vector2i(10 + 3 * i, 10), TreeResource.MAX_STAGE)
	# An enemy inside DEFEND_RADIUS so the defence branch runs too.
	w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, w.nav.cell_to_world(anchor + Vector2i(8, 0)))
	var ai: AIController = _make_ai(w, tribe, anchor)
	ai.state = AIState.State.ATTACK

	AIController.dbg_unit_passes = 0
	AIController.dbg_building_passes = 0
	AIController.dbg_cache_builds = 0
	ai.tick_ai()
	check(AIController.dbg_cache_builds == 1, "exactly one cache per tick")
	check(AIController.dbg_unit_passes == 1,
		"tribe.units is walked ONCE per tick (war: %d)" % AIController.dbg_unit_passes)
	check(AIController.dbg_building_passes == 1,
		"tribe.buildings is walked ONCE per tick (war: %d)"
			% AIController.dbg_building_passes)
	ai.free()
	_free_world(w)


## The consuming idle pool: a brave handed to the foresters must not be handed
## to the training camps in the same tick as well.
func test_tick_cache_hands_out_each_idle_brave_once() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var anchor: Vector2i = Vector2i(64, 64)
	var braves: Array[Unit] = []
	for i in range(6):
		braves.append(w.unit_manager.spawn_unit(BRAVE_SCENE, 1,
			w.nav.cell_to_world(anchor + Vector2i(6, i - 3))))
	var ai: AIController = _make_ai(w, tribe, anchor)
	var cache: AIController.TickCache = ai.build_tick_cache()
	check(cache.idle_left() == 6, "all six braves start idle in the pool")
	var first: Array[Unit] = cache.take_idle(4)
	check(first.size() == 4, "four are handed out")
	check(cache.idle_left() == 2, "the pool shrank accordingly")
	var second: Array[Unit] = cache.take_idle(4)
	check(second.size() == 2, "only the remaining two are left")
	for unit in second:
		check(not (unit in first), "no brave is handed out twice")
	check(cache.take_idle(1).is_empty(), "the drained pool stays empty")
	ai.free()
	_free_world(w)


## A brave that left IDLE between cache build and read (recruited onto a site by
## the BuildingManager, pulled into a hut) is skipped instead of being ordered.
func test_tick_cache_skips_braves_that_left_idle() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var anchor: Vector2i = Vector2i(64, 64)
	var braves: Array[Unit] = []
	for i in range(3):
		braves.append(w.unit_manager.spawn_unit(BRAVE_SCENE, 1,
			w.nav.cell_to_world(anchor + Vector2i(6, i))))
	var ai: AIController = _make_ai(w, tribe, anchor)
	var cache: AIController.TickCache = ai.build_tick_cache()
	braves[0].state = Unit.State.BUILD   # taken by another system meanwhile
	check(cache.idle_left() == 2, "the busy brave no longer counts as available")
	var taken: Array[Unit] = cache.take_idle(3)
	check(taken.size() == 2, "only the two still-idle braves are handed out")
	check(not (braves[0] in taken), "the busy brave is skipped")
	ai.free()
	_free_world(w)


# --- Scaling rules (pure, phase 10e 2.1) -----------------------------------------

func test_min_economy_braves_scales_with_population() -> void:
	check(AIState.min_economy_braves(10) == Balance.AI_MIN_ECONOMY_BRAVES,
		"a small tribe keeps the floor")
	check(AIState.min_economy_braves(200) == 70, "200 pop -> 35 percent = 70 workers")
	check(AIState.min_economy_braves(400) > AIState.min_economy_braves(200),
		"the workforce keeps growing with the tribe")


func test_parallel_site_count_scales_with_braves() -> void:
	check(AIState.parallel_site_count(0) == 1, "there is always at least one site")
	check(AIState.parallel_site_count(8) == 1, "8 braves -> 1 site (unchanged)")
	check(AIState.parallel_site_count(20) == 2, "20 braves -> 2 sites (unchanged)")
	check(AIState.parallel_site_count(5000) == Balance.AI_MAX_PARALLEL_SITES,
		"the cap holds")


func test_wood_crew_count_leaves_the_early_game_alone() -> void:
	check(AIState.wood_crew_count(11) == 0,
		"below AI_BRAVES_PER_WOOD_CREW braves there is NO crew: the early game "
		+ "behaves exactly as before")
	check(AIState.wood_crew_count(12) == 1, "the first crew forms at 12 braves")
	check(AIState.wood_crew_count(500) == Balance.AI_MAX_WOOD_CREWS, "the cap holds")


func test_train_batch_scales_with_braves() -> void:
	check(AIState.train_batch(20) == Balance.AI_TRAIN_BATCH_MIN,
		"the early batch stays at the old value")
	check(AIState.train_batch(500) == Balance.AI_TRAIN_BATCH_MAX, "the cap holds")
	check(AIState.train_batch(120) > AIState.train_batch(40), "and it grows between")


func test_army_mix_favours_preachers() -> void:
	# 100 assignments with running counters: the resulting mix must approach the
	# configured shares, and preachers must clearly beat their old 20 percent.
	var counts: Dictionary = {&"warrior": 0, &"firewarrior": 0, &"preacher": 0}
	for i in range(100):
		counts[AIState.next_training_kind(counts[&"warrior"],
			counts[&"firewarrior"], counts[&"preacher"])] += 1
	var preacher_share: float = float(counts[&"preacher"]) / 100.0
	check(absf(preacher_share - Balance.AI_ARMY_SHARE_PREACHER) < 0.05,
		"the preacher share matches the target mix (ist %.2f)" % preacher_share)
	check(counts[&"warrior"] > counts[&"preacher"], "warriors still lead the mix")
	check(counts[&"preacher"] > 20, "clearly more preachers than the old 20 percent")


## sort_custom is not stable in Godot and the 30/30 mix produces exact deficit
## ties: without the explicit tiebreak the order (and the army mix) would jitter.
func test_army_mix_order_is_deterministic() -> void:
	var first: Array[StringName] = AIState.training_kind_order(6, 0, 0)
	for i in range(20):
		check(AIState.training_kind_order(6, 0, 0) == first,
			"a tied deficit resolves the same way every time")


func test_attack_wave_scales_to_late_game() -> void:
	var wave: int = AIState.ARMY_ATTACK_SIZE
	for i in range(50):
		wave = mini(wave + AIState.ATTACK_WAVE_GROWTH, AIState.ATTACK_WAVE_MAX)
	check(wave == AIState.ATTACK_WAVE_MAX, "the wave grows into the cap")
	check(AIState.ATTACK_WAVE_MAX >= 100, "late-game waves are three digits")


func test_first_attack_comes_later() -> void:
	var snap: Dictionary = AIState.make_snapshot(30, 15,
		AIState.ARMY_ATTACK_SIZE - 1, 3, 3, true)
	check(AIState.next_state(AIState.State.TRAIN, snap) == AIState.State.TRAIN,
		"one unit short of the wave size the AI keeps training")
	var ready: Dictionary = AIState.make_snapshot(30, 15,
		AIState.ARMY_ATTACK_SIZE, 3, 3, true)
	check(AIState.next_state(AIState.State.TRAIN, ready) == AIState.State.ATTACK,
		"at the wave size it attacks")
	check(AIState.ARMY_ATTACK_SIZE >= 12, "and that size is higher than before")


func test_vehicle_caps_scale_with_population() -> void:
	var base: Dictionary = AIState.vehicle_caps(0)
	check(int(base[&"catapults"]) == Tribe.MAX_CATAPULTS_DEFAULT,
		"without braves the tribe defaults hold")
	var big: Dictionary = AIState.vehicle_caps(400)
	check(int(big[&"catapults"]) > Tribe.MAX_CATAPULTS_DEFAULT,
		"a big tribe may field more catapults")
	check(int(big[&"fire_rams"]) > Tribe.MAX_FIRE_RAMS_DEFAULT, "and more fire rams")
	check(int(big[&"airships"]) > Tribe.MAX_AIRSHIPS_DEFAULT, "and more airships")


## The caps only take effect once the controller writes them onto the tribe,
## and it must clamp against the tribe's own hard limits.
func test_ai_raises_the_tribe_vehicle_caps() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var anchor: Vector2i = Vector2i(64, 64)
	check(tribe.max_catapults == Tribe.MAX_CATAPULTS_DEFAULT, "starts at the default")
	for i in range(60):
		w.unit_manager.spawn_unit(BRAVE_SCENE, 1,
			w.nav.cell_to_world(anchor + Vector2i(10, i - 30)))
	var ai: AIController = _make_ai(w, tribe, anchor)
	ai.tick_ai()
	check(tribe.max_catapults > Tribe.MAX_CATAPULTS_DEFAULT,
		"the AI raises its catapult cap with the tribe size")
	check(tribe.max_catapults <= Tribe.MAX_CATAPULTS_LIMIT, "but never past the limit")
	check(tribe.max_airships <= Tribe.MAX_AIRSHIPS_LIMIT, "airships stay in bounds too")
	ai.free()
	_free_world(w)


# --- Build order (pure) ------------------------------------------------------------

## Minimal counts dictionary for the pure build order.
func _counts(over: Dictionary = {}) -> Dictionary:
	var base: Dictionary = {
		"hut": 0, "hut_sites": 0, "warrior_camp": 0, "firewarrior_camp": 0,
		"temple": 0, "forester": 0, "workshop": 0, "fireram_workshop": 0,
		"airship_wharf": 0, "watchtower": 0, "wood_depot": 0, "forward_depot": 0,
		"braves": 0, "population": 0, "housing_capacity": 0,
		"wood_thin": false, "grove_far": false,
	}
	for key in over:
		base[key] = over[key]
	return base


func test_build_order_places_wood_depot_after_first_camp() -> void:
	check(AIState.next_building_kind(_counts()) == &"hut", "the first hut comes first")
	check(AIState.next_building_kind(_counts({"hut": 1})) == &"warrior_camp",
		"then the first training camp")
	check(AIState.next_building_kind(_counts({"hut": 1, "warrior_camp": 1}))
		== &"wood_depot",
		"then the base wood rack (new in 10e: the AI never built one before)")


func test_build_order_prioritises_housing_under_pressure() -> void:
	var pressed: Dictionary = _counts({
		"hut": AIState.TARGET_HUTS, "warrior_camp": 1, "wood_depot": 1,
		"firewarrior_camp": 1, "temple": 1,
		"population": 34, "housing_capacity": 40,
	})
	check(AIState.next_building_kind(pressed) == &"hut",
		"under housing pressure the AI builds another hut")
	# Regression guard for the trap: Hut.housing_capacity() is 0 while the hut is
	# still a construction site. Without the "housing_capacity > 0" guard the
	# branch would be TRUE from the very first tick (population >= 0) and the AI
	# would build ONLY huts and never a warrior camp.
	var no_capacity: Dictionary = pressed.duplicate()
	no_capacity["housing_capacity"] = 0
	check(AIState.next_building_kind(no_capacity) != &"hut",
		"capacity 0 must NOT trigger the housing branch")
	# And the site cap keeps it from filling every parallel slot with huts.
	var capped: Dictionary = pressed.duplicate()
	capped["hut_sites"] = Balance.AI_MAX_HUT_SITES
	check(AIState.next_building_kind(capped) != &"hut",
		"with AI_MAX_HUT_SITES sites open the housing branch stands down")


func test_build_order_scales_workshops_with_braves() -> void:
	var full: Dictionary = _counts({
		"hut": AIState.TARGET_HUTS, "warrior_camp": 1, "firewarrior_camp": 1,
		"temple": 1, "wood_depot": 1, "workshop": 1, "fireram_workshop": 1,
		"airship_wharf": 1, "watchtower": Balance.AI_TARGET_WATCHTOWERS,
		"braves": 0,
	})
	check(AIState.next_building_kind(full) == &"",
		"a small full base has nothing left to build")
	full["braves"] = 120
	check(AIState.next_building_kind(full) == &"workshop",
		"a big tribe wants a second catapult workshop")


func test_build_order_asks_for_a_forward_depot_at_a_remote_grove() -> void:
	var remote: Dictionary = _counts({
		"hut": 1, "warrior_camp": 1, "wood_depot": 1, "grove_far": true,
	})
	check(AIState.next_building_kind(remote) == &"wood_depot",
		"a distant grove earns a forward rack")
	remote["forward_depot"] = 1
	check(AIState.next_building_kind(remote) != &"wood_depot",
		"one forward rack is enough")


# --- Wood logistics (phase 10e 2.2) -----------------------------------------------

## The core fix: before 10e the AI issued NO gathering orders at all. Wood only
## arrived through BuildingManager._recruit_workers within 30 m of a site, so a
## grove 60 m away was simply never touched.
func test_ai_sends_wood_crew_to_remote_grove() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var anchor: Vector2i = Vector2i(40, 40)
	w.building_manager.place(SITE_SCENE, tribe, anchor, 0, true)
	for i in range(20):
		w.unit_manager.spawn_unit(BRAVE_SCENE, 1,
			w.nav.cell_to_world(anchor + Vector2i(4, i - 10)))
	# The ONLY trees stand 60 m away.
	for z in range(4):
		for x in range(4):
			w.tree_manager.spawn_tree(anchor + Vector2i(58 + x * 2, z * 2),
				TreeResource.MAX_STAGE)
	# An unfunded construction site creates the wood demand.
	w.building_manager.place(HUT_SCENE, tribe, anchor + Vector2i(-8, 0), 0, false)
	var ai: AIController = _make_ai(w, tribe, anchor)
	# The logistics tick is throttled to every AI_WOOD_TICK_INTERVAL-th tick.
	for i in range(Balance.AI_WOOD_TICK_INTERVAL + 1):
		ai._tick_count += 1
		ai._tick_wood_logistics(ai.build_tick_cache())
	var tasked: int = 0
	for unit in tribe.units:
		if unit is Brave and (unit as Brave).has_chop_area():
			tasked += 1
	check(tasked >= Balance.AI_WOOD_CREW_SIZE,
		"a full crew got an area order for the remote grove (ist %d)" % tasked)
	for unit in tribe.units:
		if unit is Brave and (unit as Brave).has_chop_area():
			var area: Rect2 = (unit as Brave).chop_area
			check(area.get_center().x > w.nav.cell_to_world(anchor).x + 30.0,
				"the assigned area lies out at the remote grove")
			break
	for unit in tribe.units:
		if unit is Brave:
			(unit as Brave)._interrupt_tasks()
	ai.free()
	_free_world(w)


## Crew membership is derived from has_chop_area(), never from State.IDLE:
## right after order_chop_area the brave has not ticked yet and is still IDLE.
func test_wood_crew_survives_the_tick_it_was_created_in() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var anchor: Vector2i = Vector2i(40, 40)
	w.building_manager.place(SITE_SCENE, tribe, anchor, 0, true)
	for i in range(20):
		w.unit_manager.spawn_unit(BRAVE_SCENE, 1,
			w.nav.cell_to_world(anchor + Vector2i(4, i - 10)))
	for z in range(4):
		for x in range(4):
			w.tree_manager.spawn_tree(anchor + Vector2i(58 + x * 2, z * 2),
				TreeResource.MAX_STAGE)
	w.building_manager.place(HUT_SCENE, tribe, anchor + Vector2i(-8, 0), 0, false)
	var ai: AIController = _make_ai(w, tribe, anchor)
	for i in range(Balance.AI_WOOD_TICK_INTERVAL + 1):
		ai._tick_count += 1
		ai._tick_wood_logistics(ai.build_tick_cache())
	var crews: int = ai._wood_crews.size()
	check(crews > 0, "a crew was formed")
	# Immediately another logistics tick: the crew must NOT be discarded.
	for i in range(Balance.AI_WOOD_TICK_INTERVAL):
		ai._tick_count += 1
		ai._tick_wood_logistics(ai.build_tick_cache())
	check(ai._wood_crews.size() >= crews,
		"the fresh crew survives the next prune (IDLE would have dropped it)")
	for unit in tribe.units:
		if unit is Brave:
			(unit as Brave)._interrupt_tasks()
	ai.free()
	_free_world(w)


func test_grove_candidates_prefer_dense_and_near() -> void:
	var w: Dictionary = _make_world()
	var from: Vector3 = w.nav.cell_to_world(Vector2i(20, 20))
	# A dense grove nearby and a single lonely tree far away.
	for z in range(4):
		for x in range(4):
			w.tree_manager.spawn_tree(Vector2i(30 + x * 2, 20 + z * 2),
				TreeResource.MAX_STAGE)
	w.tree_manager.spawn_tree(Vector2i(100, 100), TreeResource.MAX_STAGE)
	var groves: Array[Rect2] = w.tree_manager.grove_candidates(from, 4)
	check(not groves.is_empty(), "at least one grove is found")
	var best: Vector2 = groves[0].get_center()
	check(best.distance_to(Vector2(from.x, from.z)) < 40.0,
		"the dense nearby grove ranks first")
	check(groves[0].size.x <= Balance.HARVEST_AREA_MAX_SIDE,
		"a grove rect fits inside the area-order clamp")
	_free_world(w)


# --- Plot layout (phase 10e 2.3) --------------------------------------------------

func test_ai_plot_keeps_spacing_between_buildings() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var anchor: Vector2i = Vector2i(64, 64)
	w.building_manager.place(SITE_SCENE, tribe, anchor, 0, true)
	w.building_manager.place(HUT_SCENE, tribe, anchor + Vector2i(6, 0), 0, true)
	for i in range(20):
		w.tree_manager.spawn_tree(anchor + Vector2i(-12 + (i % 5) * 2, -12 + (i / 5) * 2),
			TreeResource.MAX_STAGE)
	var ai: AIController = _make_ai(w, tribe, anchor)
	var cell: Vector2i = ai._find_plot(Balance.HUT_FOOTPRINT, ai.build_tick_cache())
	check(cell.x >= 0, "a plot was found")
	var fp: Vector2i = Balance.HUT_FOOTPRINT
	if ai._plot_orientation % 2 == 1:
		fp = Vector2i(fp.y, fp.x)
	var r: Rect2i = Rect2i(cell, fp).grow(Balance.AI_PLOT_SPACING)
	var blocked: int = 0
	for z in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			if w.nav.is_cell_blocked_by_building(Vector2i(x, z)):
				blocked += 1
	check(blocked == 0,
		"no other building stands inside the spacing ring (%d Zellen belegt)" % blocked)
	ai.free()
	_free_world(w)


func test_ai_plot_entrance_faces_the_base() -> void:
	# Pure geometry: orientation 0..3 = S/E/N/W, cell.y IS the z axis.
	var fp: Vector2i = Vector2i(4, 4)
	check(AIController._orientation_toward(Vector2i(20, 10), fp, Vector2i(20, 40)) == 0,
		"anchor to the south -> entrance south")
	check(AIController._orientation_toward(Vector2i(20, 10), fp, Vector2i(60, 12)) == 1,
		"anchor to the east -> entrance east")
	check(AIController._orientation_toward(Vector2i(20, 40), fp, Vector2i(20, 10)) == 2,
		"anchor to the north -> entrance north")
	check(AIController._orientation_toward(Vector2i(60, 10), fp, Vector2i(20, 12)) == 3,
		"anchor to the west -> entrance west")


## Self-healing (10d + 10e): a site whose approach lies on another island is
## scrapped instantly (build_progress 0 = full refund) AND its cell is banned,
## because without the ban the AI would re-place and re-scrap it every tick.
func test_ai_discards_a_site_with_no_walkable_approach() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var anchor: Vector2i = Vector2i(20, 20)
	# An island far away, cut off by water (height below sea level everywhere
	# between): place a site there and let the AI judge it.
	for vz in range(w.td.size + 1):
		for vx in range(w.td.size + 1):
			# Ring-shaped moat around a dry patch at (75..85): the patch stays
			# walkable but is cut off from the mainland.
			var inner: bool = vx >= 74 and vx <= 86 and vz >= 74 and vz <= 86
			var outer: bool = vx >= 70 and vx <= 90 and vz >= 70 and vz <= 90
			if outer and not inner:
				w.td.set_vertex_height(vx, vz, 1.0)   # below sea level
	w.nav.update_region(Rect2i(Vector2i(68, 68), Vector2i(24, 24)))
	var far_cell: Vector2i = Vector2i(78, 78)
	var site: Building = w.building_manager.place(HUT_SCENE, tribe, far_cell, 0, false)
	var ai: AIController = _make_ai(w, tribe, anchor)
	check(site != null, "the isolated site was placed (test precondition)")
	check(w.nav.island_at(far_cell) != w.nav.island_at(anchor),
		"the moat really separates the patch from the base (test precondition)")
	var kept: bool = ai._accept_or_scrap_site(site, far_cell)
	check(not kept, "a site with no walkable approach is not accepted")
	check(ai._unreachable_plots.has(far_cell),
		"and its cell is banned (otherwise place/scrap loops forever)")
	ai.free()
	_free_world(w)


# --- Spells (phase 10e 2.4) --------------------------------------------------------

## Enemy preachers convert the AI's army away and cannot even be attacked in
## melee while converting: they now outrank the building ladder.
func test_ai_prioritises_enemy_preachers_with_spells() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var anchor: Vector2i = Vector2i(64, 64)
	var shaman: Unit = w.unit_manager.spawn_unit(SHAMAN_SCENE, 1,
		w.nav.cell_to_world(anchor))
	var preacher: Unit = w.unit_manager.spawn_unit(
		preload("res://scenes/units/preacher.tscn"), 0,
		w.nav.cell_to_world(anchor + Vector2i(5, 0)))
	# An enemy building in range too — the preacher must still win.
	w.building_manager.place(HUT_SCENE, w.tribes[0], anchor + Vector2i(0, 8), 0, true)
	var ai: AIController = _make_ai(w, tribe, anchor)
	_arm_only(tribe, &"lightning")
	ai._cast_spells()
	check(_pending_spell_id(tribe) == &"lightning",
		"the AI casts lightning")
	var target: Vector3 = (shaman as Shaman).pending_target
	check(target.distance_to(preacher.position) < 1.0,
		"and it aims at the enemy PREACHER, not at the building")
	ai.free()
	_free_world(w)


# --- Reincarnation circle is no AI target (10g) --------------------------------------
# Before 10g the three AI target functions took every enemy building, so the circle
# — sitting on the base anchor, usually the nearest — absorbed both the spell
# heuristic (lightning/volcano/sink burn charges on an invulnerable ring) and the
# whole attack wave, while the enemy FOLLOWERS lived on undisturbed.

func test_ai_attack_target_skips_the_reincarnation_site() -> void:
	var w: Dictionary = _make_world()
	var ai_tribe: Tribe = w.tribes[1]
	var anchor: Vector2i = Vector2i(20, 20)
	var ai: AIController = _make_ai(w, ai_tribe, anchor)
	# Enemy circle NEAR the AI, a normal enemy hut far away.
	var site: Building = w.building_manager.place(SITE_SCENE, w.tribes[0],
		Vector2i(30, 30), 0, true)
	var hut: Building = w.building_manager.place(HUT_SCENE, w.tribes[0],
		Vector2i(70, 70), 0, true)
	var target: Vector3 = ai._attack_target_position()
	check(target.distance_to(site.center_world()) > 1.0,
		"die Angriffswelle marschiert nicht auf den Kreis")
	check(target.distance_to(hut.center_world()) < 1.0,
		"sie nimmt das naechste ANGREIFBARE Gebaeude")
	ai.free()
	_free_world(w)


func test_ai_marches_at_enemy_units_when_only_the_circle_is_left() -> void:
	var w: Dictionary = _make_world()
	var ai_tribe: Tribe = w.tribes[1]
	var ai: AIController = _make_ai(w, ai_tribe, Vector2i(20, 20))
	w.building_manager.place(SITE_SCENE, w.tribes[0], Vector2i(30, 30), 0, true)
	var follower: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 0, Vector3(60, 5, 60))
	var target: Vector3 = ai._attack_target_position()
	check(target.distance_to(follower.position) < 1.0,
		"nur noch der Kreis steht -> die KI geht auf die ANHAENGER los (10d-Siegkette)")
	ai.free()
	_free_world(w)


func test_ai_spell_heuristic_ignores_the_reincarnation_site() -> void:
	var w: Dictionary = _make_world()
	var ai: AIController = _make_ai(w, w.tribes[1], Vector2i(20, 20))
	var site: Building = w.building_manager.place(SITE_SCENE, w.tribes[0],
		Vector2i(30, 30), 0, true)
	check(ai._nearest_enemy_building(site.center_world(), 40.0) == null,
		"der Kreis ist kein Zauberziel")
	check(ai._enemy_buildings_near(site.center_world(), 40.0) == 0,
		"der Kreis zaehlt nicht in die Vulkan-Ballung")
	# Control: a normal building is found again.
	var hut: Building = w.building_manager.place(HUT_SCENE, w.tribes[0],
		Vector2i(34, 34), 0, true)
	check(ai._nearest_enemy_building(site.center_world(), 40.0) == hut,
		"eine normale Huette bleibt Zauberziel")
	check(ai._enemy_buildings_near(site.center_world(), 40.0) == 1,
		"und zaehlt in die Ballung")
	ai.free()
	_free_world(w)


# --- Teil 7: Wohnraum und Ausbildung vor Werkstaetten (10g) --------------------------
# Nutzerreport: "6 Werkstaetten aber wenig Fahrzeuge und haette besser Huetten bauen
# sollen" und "nie mehr als 1 Trainingsgebaeude von jedem". Ursache war die
# REIHENFOLGE: der Zusatz-Lager-Zweig stand als LETZTER hinter bis zu 12
# Werkstaetten, und kein Lagerziel hing am Bravestrom.

func test_camp_targets_scale_with_the_brave_stream() -> void:
	var low: Dictionary = AIState.camp_targets(0.0)
	check(int(low[&"warrior_camp"]) == 1 and int(low[&"temple"]) == 1,
		"ohne Strom bleibt je Art ein Lager")
	# 100 Braves/min, Mix 40/30/30: Kaserne 40/min bei 20/min Durchsatz -> 2,
	# Feuertempel 30/min bei 15 -> 2, Tempel 30/min bei 12 -> 3 (aufgerundet).
	var high: Dictionary = AIState.camp_targets(100.0)
	check(int(high[&"warrior_camp"]) == 2, "Kaserne skaliert mit dem Strom")
	check(int(high[&"firewarrior_camp"]) == 2, "Feuertempel skaliert mit dem Strom")
	check(int(high[&"temple"]) == 3, "der langsame Tempel braucht am meisten")


func test_camp_targets_are_capped_per_kind() -> void:
	var huge: Dictionary = AIState.camp_targets(10000.0)
	for kind in [&"warrior_camp", &"firewarrior_camp", &"temple"]:
		check(int(huge[kind]) == Balance.AI_MAX_CAMPS_PER_KIND,
			"%s auf AI_MAX_CAMPS_PER_KIND gedeckelt" % kind)


func test_camp_targets_derive_from_the_training_times() -> void:
	# Nicht aus eigenen Konstanten: eine Balance-Aenderung an der Trainingszeit darf
	# die KI nicht auf die alte Rate planen lassen.
	var slowest: float = maxf(maxf(Balance.WARRIOR_CAMP_TRAINING_TIME,
		Balance.FIREWARRIOR_CAMP_TRAINING_TIME), Balance.TEMPLE_TRAINING_TIME)
	check(is_equal_approx(Balance.TEMPLE_TRAINING_TIME, slowest),
		"der Tempel ist das langsamste Lager - Grundlage der Erwartung oben")


func test_training_hut_share_stays_below_one() -> void:
	# Der gefaehrlichste Wert des Plans: bei 1,0 hat der Stamm keine freien Braves
	# mehr - keine Bauarbeiter, keine Holztrupps, keine Werkstattbesatzung.
	for army in [0, 1, 5, 50, 500]:
		var s: float = AIState.training_hut_share(AIState.State.ATTACK, army, 12)
		check(s < 1.0, "Anteil bleibt unter 1,0 (Armee %d)" % army)
	check(AIState.training_hut_share(AIState.State.BUILD, 0, 12) \
		== Balance.AI_TRAINING_HUT_SHARE_BUILD, "im Aufbau der niedrige Anteil")


func test_training_hut_share_rises_when_the_army_lags() -> void:
	var lagging: float = AIState.training_hut_share(AIState.State.TRAIN, 0, 12)
	var ready: float = AIState.training_hut_share(AIState.State.TRAIN, 12, 12)
	check(lagging > ready, "je weiter die Armee zurueckliegt, desto mehr Huetten")


func test_build_order_puts_extra_camps_before_workshops() -> void:
	# Ein grosser Bravestrom bei nur einem Lager je Art: die Bauordnung muss ein
	# LAGER liefern, nicht eine Werkstatt.
	var counts: Dictionary = {
		"hut": 6, "hut_sites": 0, "warrior_camp": 1, "firewarrior_camp": 1,
		"temple": 1, "forester": 1, "workshop": 0, "fireram_workshop": 0,
		"airship_wharf": 0, "watchtower": 0, "wood_depot": 1, "forward_depot": 0,
		"braves": 120, "population": 40, "housing_capacity": 200,
		"wood_thin": false, "grove_far": false, "brave_stream": 100.0,
	}
	var kind: StringName = AIState.next_building_kind(counts)
	check(kind == &"warrior_camp" or kind == &"firewarrior_camp" or kind == &"temple",
		"bei hohem Strom kommt ein Ausbildungslager, keine Werkstatt (war: %s)" % kind)


func test_build_order_still_builds_the_first_workshop() -> void:
	# Regressionswaechter: das Tor darf die Werkstaetten nicht ganz abschalten -
	# die ERSTE je Art ist nie gegattert, auch wenn die Lager zurueckliegen.
	var counts: Dictionary = {
		"hut": 6, "hut_sites": 0, "warrior_camp": 4, "firewarrior_camp": 4,
		"temple": 4, "forester": 1, "workshop": 0, "fireram_workshop": 0,
		"airship_wharf": 0, "watchtower": 0, "wood_depot": 1, "forward_depot": 0,
		"braves": 120, "population": 40, "housing_capacity": 200,
		"wood_thin": false, "grove_far": false, "brave_stream": 100.0,
	}
	check(AIState.next_building_kind(counts) == &"workshop",
		"bei gesaettigten Lagern kommt die Werkstatt")
	# Und selbst mit zurueckliegenden Lagern: die erste Werkstatt geht durch.
	counts["warrior_camp"] = 1
	counts["firewarrior_camp"] = 1
	counts["temple"] = 1
	counts["brave_stream"] = 0.0
	check(AIState.next_building_kind(counts) == &"workshop",
		"die erste Werkstatt ist nie gegattert")


func test_build_order_blocks_a_second_workshop_while_camps_lag() -> void:
	var counts: Dictionary = {
		"hut": 6, "hut_sites": 0, "warrior_camp": 1, "firewarrior_camp": 1,
		"temple": 1, "forester": 1, "workshop": 1, "fireram_workshop": 0,
		"airship_wharf": 0, "watchtower": 0, "wood_depot": 1, "forward_depot": 0,
		"braves": 120, "population": 40, "housing_capacity": 200,
		"wood_thin": false, "grove_far": false, "brave_stream": 100.0,
	}
	check(AIState.next_building_kind(counts) != &"workshop",
		"keine zweite Werkstatt, solange die Ausbildung hinterherhinkt")


func test_build_order_builds_a_hut_on_low_absolute_headroom() -> void:
	# Der zweite Wohnraum-Auslöser: 190 von 200 Plaetzen belegt sind nur 95 %, aber
	# der Prozentdruck (0,7) ist erfuellt - also ein Fall, der schon vorher zog.
	# Entscheidend ist der umgekehrte: viel Luft in Prozent, wenig in Plaetzen.
	var counts: Dictionary = {
		"hut": 1, "hut_sites": 0, "warrior_camp": 1, "firewarrior_camp": 1,
		"temple": 1, "forester": 1, "workshop": 0, "fireram_workshop": 0,
		"airship_wharf": 0, "watchtower": 0, "wood_depot": 1, "forward_depot": 0,
		"braves": 5, "population": 2, "housing_capacity": 10,
		"wood_thin": false, "grove_far": false, "brave_stream": 0.0,
	}
	# 2 von 10 = 20 % (Prozentdruck NICHT erfuellt), aber nur 8 Plaetze frei.
	check(counts["population"] < int(float(counts["housing_capacity"])
		* Balance.AI_HOUSING_PRESSURE), "Prozentdruck ist hier bewusst NICHT erfuellt")
	check(AIState.next_building_kind(counts) == &"hut",
		"wenig freie Plaetze in absoluten Zahlen loesen trotzdem eine Huette aus")


func test_ai_points_some_hut_rallies_at_training_buildings() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var anchor: Vector2i = Vector2i(40, 40)
	var ai: AIController = _make_ai(w, tribe, anchor)
	w.building_manager.place(SITE_SCENE, tribe, anchor, 0, true)
	w.building_manager.place(WARRIOR_CAMP_SCENE, tribe, Vector2i(50, 40), 0, true)
	var huts: Array[Building] = []
	for i in range(4):
		huts.append(w.building_manager.place(HUT_SCENE, tribe,
			Vector2i(30 + i * 5, 50), 0, true))
	ai.state = AIState.State.TRAIN
	ai._tick_count = Balance.AI_HUT_RALLY_TICK_INTERVAL   # Drossel treffen
	ai._tick_hut_rallies(ai.build_tick_cache())
	var routed: int = 0
	for hut in huts:
		if hut.rally_training_building() != null:
			routed += 1
	check(routed > 0, "mindestens eine Huette leitet ihren Strom ins Lager")
	check(routed < huts.size(), "aber NIE alle - sonst hat der Stamm keine freien Braves")
	check(AIController.dbg_hut_rallies == routed, "Zaehler stimmt mit der Zuordnung")
	ai.free()
	_free_world(w)


func test_ai_hut_rallies_need_a_usable_camp() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var ai: AIController = _make_ai(w, tribe, Vector2i(40, 40))
	var hut: Building = w.building_manager.place(HUT_SCENE, tribe, Vector2i(30, 50), 0, true)
	ai.state = AIState.State.TRAIN
	ai._tick_count = Balance.AI_HUT_RALLY_TICK_INTERVAL
	ai._tick_hut_rallies(ai.build_tick_cache())
	check(hut.rally_training_building() == null,
		"ohne Lager wird keine Huette umgeleitet")
	ai.free()
	_free_world(w)


func test_ai_does_not_reassign_hut_rallies_every_tick() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var ai: AIController = _make_ai(w, tribe, Vector2i(40, 40))
	w.building_manager.place(WARRIOR_CAMP_SCENE, tribe, Vector2i(50, 40), 0, true)
	for i in range(4):
		w.building_manager.place(HUT_SCENE, tribe, Vector2i(30 + i * 5, 50), 0, true)
	ai.state = AIState.State.TRAIN
	ai._tick_count = Balance.AI_HUT_RALLY_TICK_INTERVAL
	ai._tick_hut_rallies(ai.build_tick_cache())
	var before: int = AIController.dbg_hut_rallies
	# Ein Tick, der die Drossel NICHT trifft, darf nichts anfassen.
	AIController.dbg_hut_rallies = -1
	ai._tick_count += 1
	ai._tick_hut_rallies(ai.build_tick_cache())
	check(AIController.dbg_hut_rallies == -1,
		"zwischen den Drossel-Ticks wird nicht neu zugeordnet")
	AIController.dbg_hut_rallies = before
	ai.free()
	_free_world(w)


func test_set_rally_point_keeps_a_point_on_an_own_building() -> void:
	# Die Kernfalle: rally_training_building() vergleicht die Rally-ZELLE mit dem
	# Grundriss des Lagers, und ein Grundriss ist im NavGrid SOLID. Ein Snapping auf
	# die naechste begehbare Zelle wuerde den Punkt aus dem Lager schieben und die
	# ganze Umleitung lautlos kaputtmachen.
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var camp: Building = w.building_manager.place(WARRIOR_CAMP_SCENE, tribe,
		Vector2i(50, 40), 0, true)
	var hut: Building = w.building_manager.place(HUT_SCENE, tribe, Vector2i(30, 50), 0, true)
	check(w.commands.set_rally_point(tribe, hut, camp.center_world()),
		"Rally Point auf das Lager wird angenommen")
	check(hut.rally_training_building() == camp,
		"und liegt danach WIRKLICH im Grundriss des Lagers")
	# Ein Punkt im freien Gelaende wird dagegen auf eine begehbare Zelle gesnappt.
	check(w.commands.set_rally_point(tribe, hut, Vector3(60, 5, 60)), "freier Punkt ok")
	check(hut.rally_training_building() == null, "und zeigt dann auf kein Lager mehr")
	_free_world(w)


func test_set_rally_point_rejects_a_foreign_building() -> void:
	var w: Dictionary = _make_world()
	var enemy_hut: Building = w.building_manager.place(HUT_SCENE, w.tribes[0],
		Vector2i(30, 50), 0, true)
	check(not w.commands.set_rally_point(w.tribes[1], enemy_hut, Vector3(40, 5, 40)),
		"fremde Gebaeude nimmt der Befehl nicht an")
	_free_world(w)


# --- Teil 1: aktive Bauarbeiter-Zuweisung + Budget (10g) ------------------------------
# Vor 10g rief der AIController order_build NIE auf: Bauarbeiter kamen allein aus
# BuildingManager._recruit_workers (30 m, nur idle), waehrend Bauplaetze bis 40 Zellen
# draussen liegen und Training/Faell-Trupps/Werkstaetten den Idle-Pool vorher leerten.

func test_site_worker_target_scales_with_footprint_while_grading() -> void:
	var small: int = AIState.site_worker_target(1, true, 0)
	var hut: int = AIState.site_worker_target(16, true, 8)
	var camp: int = AIState.site_worker_target(64, true, 20)
	check(small == Balance.AI_SITE_WORKERS_MIN, "1x1 bekommt die Mindestbesatzung")
	check(hut > small, "der groessere Grundriss bekommt mehr Haende")
	check(camp > hut, "und der 8x8 noch mehr")
	check(camp <= Balance.AI_SITE_WORKERS_MAX, "gedeckelt auf AI_SITE_WORKERS_MAX")


func test_site_worker_target_drops_after_the_foundation() -> void:
	var grading: int = AIState.site_worker_target(64, true, 20)
	var building: int = AIState.site_worker_target(64, false, 20)
	check(building < grading, "nach dem Fundament braucht es weniger Haende")
	check(building <= Balance.AI_SITE_WORKERS_BUILD_MAX, "eigener, kleinerer Deckel")


func test_site_worker_target_leaves_room_for_the_passive_recruiter() -> void:
	for cells in [1, 16, 25, 36, 64]:
		for flat in [true, false]:
			check(AIState.site_worker_target(cells, flat, 100) <= Building.MAX_WORKERS - 2,
				"laesst dem passiven Rekrutierer zwei Plaetze (%d, %s)" % [cells, str(flat)])


func test_builder_budget_is_capped_by_the_actual_demand() -> void:
	check(AIState.builder_budget(200, 400, 3) == 3, "Budget folgt dem Bedarf")
	check(AIState.builder_budget(200, 400, 0) == 0, "kein Bedarf, kein Budget")


func test_builder_budget_never_exceeds_the_economy_crew() -> void:
	for pop in [10, 50, 200, 600]:
		var eco: int = AIState.min_economy_braves(pop)
		check(AIState.builder_budget(pop * 2, pop, 9999) <= eco,
			"Budget bleibt in der Wirtschaftsmannschaft (pop %d)" % pop)


func test_builder_budget_leaves_the_early_game_a_wood_crew() -> void:
	var b: int = AIState.builder_budget(10, 12, 9999)
	check(b == Balance.AI_MIN_BUILDER_BRAVES, "Bodensatz greift im Fruehspiel")
	check(10 - b >= Balance.AI_WOOD_CREW_SIZE, "ein Faell-Trupp bleibt moeglich")


func test_site_is_supplied_accepts_a_wood_starved_site() -> void:
	check(AIState.site_is_supplied(0, true, 0),
		"holzlose Baustelle gehoert der Holzlogistik, nicht dem Bautrupp-Tor")
	check(not AIState.site_is_supplied(0, false, 0), "handlose Baustelle blockiert das Tor")
	check(AIState.site_is_supplied(Balance.AI_SITE_SUPPLIED_WORKERS, false, 0),
		"ab AI_SITE_SUPPLIED_WORKERS gilt sie als versorgt")


func test_site_is_supplied_releases_the_gate_after_the_grace_period() -> void:
	check(not AIState.site_is_supplied(0, false, Balance.AI_SITE_SUPPLY_GRACE_TICKS - 1),
		"innerhalb der Gnadenfrist blockiert sie noch")
	check(AIState.site_is_supplied(0, false, Balance.AI_SITE_SUPPLY_GRACE_TICKS),
		"danach gibt sie das Tor frei - Verklemmungsschutz")


func test_ai_puts_workers_on_its_own_construction_site() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var anchor: Vector2i = Vector2i(40, 40)
	var ai: AIController = _make_ai(w, tribe, anchor)
	var site: Building = w.building_manager.place(WARRIOR_CAMP_SCENE, tribe,
		Vector2i(46, 40), 0, false)
	check(site.under_construction, "Baustelle steht")
	for i in range(6):
		w.unit_manager.spawn_unit(BRAVE_SCENE, 1, w.nav.cell_to_world(anchor + Vector2i(i, 2)))
	ai._tick_build_crews(ai.build_tick_cache())
	check(site.workers.size() >= Balance.AI_SITE_SUPPLIED_WORKERS,
		"die KI setzt Arbeiter auf die eigene Baustelle (war strukturell nie der Fall)")
	for worker in site.workers:
		check(worker.job == site, "und sie haengen wirklich an dieser Baustelle")
	ai.free()
	_free_world(w)


func test_ai_staffs_a_site_the_recruiter_cannot_reach() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var anchor: Vector2i = Vector2i(30, 30)
	var ai: AIController = _make_ai(w, tribe, anchor)
	var site: Building = w.building_manager.place(WARRIOR_CAMP_SCENE, tribe,
		Vector2i(75, 30), 0, false)
	var far: float = w.nav.cell_to_world(anchor).distance_to(site.center_world())
	check(far > BuildingManager.RECRUIT_RADIUS,
		"Baustelle liegt ausserhalb des Rekrutierungsradius (%.0f m)" % far)
	for i in range(6):
		w.unit_manager.spawn_unit(BRAVE_SCENE, 1, w.nav.cell_to_world(anchor + Vector2i(i, 2)))
	ai._tick_build_crews(ai.build_tick_cache())
	check(site.workers.size() > 0, "die KI schickt trotzdem Arbeiter hin")
	ai.free()
	_free_world(w)


func test_ai_skips_wood_stalled_sites_when_staffing() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var ai: AIController = _make_ai(w, tribe, Vector2i(40, 40))
	var site: Building = w.building_manager.place(WARRIOR_CAMP_SCENE, tribe,
		Vector2i(46, 40), 0, false)
	site.mark_wood_stalled()
	for i in range(6):
		w.unit_manager.spawn_unit(BRAVE_SCENE, 1, w.nav.cell_to_world(Vector2i(40 + i, 42)))
	ai._tick_build_crews(ai.build_tick_cache())
	check(site.workers.is_empty(),
		"holzlose Baustelle wird nicht bestueckt (Arbeiter gingen sofort wieder)")
	check(ai._site_worker_want(site) == 0, "sie ist kein Bestueckungsziel")
	ai.free()
	_free_world(w)


func test_ai_skips_a_site_being_demolished() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var ai: AIController = _make_ai(w, tribe, Vector2i(40, 40))
	var site: Building = w.building_manager.place(WARRIOR_CAMP_SCENE, tribe,
		Vector2i(46, 40), 0, false)
	site.build_progress = 0.5
	site.begin_demolish()
	check(site.demolishing and site.under_construction,
		"Abriss mit Baustufe bleibt under_construction - steht also in cache.sites")
	check(ai._site_worker_want(site) == 0, "der Abriss ist kein Bestueckungsziel")
	ai.free()
	_free_world(w)


func test_ai_does_not_reorder_braves_already_on_a_site() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var ai: AIController = _make_ai(w, tribe, Vector2i(40, 40))
	var site: Building = w.building_manager.place(WARRIOR_CAMP_SCENE, tribe,
		Vector2i(46, 40), 0, false)
	for i in range(8):
		w.unit_manager.spawn_unit(BRAVE_SCENE, 1, w.nav.cell_to_world(Vector2i(40 + i, 42)))
	ai._tick_build_crews(ai.build_tick_cache())
	var first: Array = []
	for worker in site.workers:
		first.append(worker)
	check(not first.is_empty(), "erste Zuweisung erfolgt")
	ai._tick_count += 1
	ai._tick_build_crews(ai.build_tick_cache())
	for worker in first:
		check(worker.job == site, "bestehender Arbeiter bleibt an seiner Baustelle")
	ai.free()
	_free_world(w)


func test_ai_opens_no_second_site_while_the_first_has_no_workers() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var anchor: Vector2i = Vector2i(40, 40)
	var ai: AIController = _make_ai(w, tribe, anchor)
	w.building_manager.place(SITE_SCENE, tribe, anchor, 0, true)
	var site: Building = w.building_manager.place(WARRIOR_CAMP_SCENE, tribe,
		Vector2i(46, 40), 0, false)
	check(site.workers.is_empty(), "Baustelle ohne Arbeiter")
	var cache: AIController.TickCache = ai.build_tick_cache()
	ai._prune_site_notes(cache)
	check(not ai._all_sites_supplied(cache), "Tor ist zu")
	ai._tick_count += Balance.AI_SITE_SUPPLY_GRACE_TICKS
	check(ai._all_sites_supplied(ai.build_tick_cache()),
		"nach AI_SITE_SUPPLY_GRACE_TICKS baut die KI wieder")
	ai.free()
	_free_world(w)


func test_site_notes_do_not_leak() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var ai: AIController = _make_ai(w, tribe, Vector2i(40, 40))
	var site: Building = w.building_manager.place(WARRIOR_CAMP_SCENE, tribe,
		Vector2i(46, 40), 0, false)
	ai._prune_site_notes(ai.build_tick_cache())
	check(ai._site_notes.size() == 1, "eine Notiz je Baustelle")
	site.finish_construction()
	ai._prune_site_notes(ai.build_tick_cache())
	check(ai._site_notes.is_empty(),
		"fertige Baustelle -> Notiz weg (die Buchfuehrung kann nicht lecken)")
	ai.free()
	_free_world(w)


func test_potential_growth_ignores_the_housing_cap() -> void:
	# Der Fehler, den die Diagnose aufdeckte: growth_per_minute() liefert am
	# Wohnraumdeckel 0, wodurch der Bravestrom genau dann kollabierte, wenn der
	# Stamm die meisten Braves hatte - die Lagerziele fielen auf eines je Art
	# zurueck und die KI baute stattdessen Werkstaetten.
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var hut: Hut = w.building_manager.place(HUT_SCENE, tribe, Vector2i(50, 50), 0, true) as Hut
	for i in range(hut.crew_capacity()):
		var b: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, hut.center_world())
		hut.admit_crew(b)
	check(hut.potential_growth_per_minute() > 0.0, "mit Besatzung ist das Potenzial > 0")
	# Bevoelkerung ueber die Kapazitaet druecken.
	while tribe.population() < tribe.housing_capacity() + 2:
		w.unit_manager.spawn_unit(BRAVE_SCENE, 1, w.nav.cell_to_world(Vector2i(60, 60)))
	check(hut.growth_per_minute() == 0.0, "die AKTUELLE Rate ist am Deckel korrekt 0")
	check(hut.potential_growth_per_minute() > 0.0,
		"das Potenzial bleibt - darauf plant die KI ihre Lager")
	_free_world(w)


# --- Teil 5: Arena-Enge, Bedrohungserkennung, zwei Baumuster (10g) --------------------
# Nutzerreport: "auf kleinen Karten greift sie sofort mit den Braves an".
# Ursache: DEFEND_RADIUS war fix 32 m, die Basisabstaende sind es nicht.
# MapGenerator._circle_anchors setzt die Anker auf einen Kreis mit Radius
# 0,2 * size — Insel 128 mit 4 Staemmen: naechste Nachbarbasis 36,2 Zellen. Damit
# war _detect_threat DAUERHAFT wahr: Holzlogistik nie, _tick_attack nie, und
# _tick_defend warf alle idle Braves auf den Nachbarn.

func test_is_cramped_matches_the_island_four_tribe_spacing() -> void:
	check(AIState.is_cramped(36.2), "Insel/4 Staemme (36,2 Zellen) ist eng")
	check(AIState.is_cramped(51.2), "Insel/2 Staemme (51,2) noch eng")
	check(not AIState.is_cramped(82.0), "Plateau (82, Eckanker) ist offen")
	check(not AIState.is_cramped(140.0), "Seenland/Bergpass offen")


func test_defend_radius_shrinks_on_a_cramped_arena() -> void:
	var island: float = AIState.defend_radius(36.2)
	var plateau: float = AIState.defend_radius(82.0)
	var big: float = AIState.defend_radius(200.0)
	check(island < 36.2 * 0.5,
		"auf der Insel reicht der Radius nicht mehr zur Nachbarbasis (%.1f)" % island)
	check(island >= Balance.AI_DEFEND_RADIUS_MIN, "aber nicht unter das Minimum")
	check(plateau > island, "je weiter die Basen, desto groesser der Radius")
	check(is_equal_approx(big, Balance.AI_DEFEND_RADIUS_MAX),
		"auf grossen Karten der alte Wert 32")


func test_cramped_profile_keeps_the_base_compact() -> void:
	check(AIState.plot_search_radius(36.2) < AIState.plot_search_radius(140.0),
		"engere Arena, kleinerer Suchradius (40 Zellen reichen sonst an der "
			+ "Nachbarbasis vorbei)")
	check(AIState.settlement_anchor_limit(36.2) < AIState.settlement_anchor_limit(140.0),
		"und weniger Siedlungsanker")
	check(AIState.target_watchtowers(36.2) > AIState.target_watchtowers(140.0),
		"dafuer mehr Wachtuerme - Kontakt kommt sofort")


func test_cramped_profile_forbids_forward_depots() -> void:
	check(not AIState.forward_depots_allowed(36.2),
		"AI_FORWARD_DEPOT_DISTANCE ist 35 - bei 36 Zellen zur Nachbarbasis waere "
			+ "das Lager vor deren Tuer")
	check(AIState.forward_depots_allowed(140.0), "auf grossen Karten erlaubt")


func test_cramped_profile_attacks_earlier_with_a_smaller_army() -> void:
	check(AIState.army_attack_size(36.2) < AIState.army_attack_size(140.0),
		"enge Arena: kleinere erste Welle, die KI braucht FRUEH echte Armee")
	check(AIState.pop_for_train(36.2) < AIState.pop_for_train(140.0),
		"und frueher Ausbildung statt weiter aufbauen")


func test_militia_takes_at_most_half_the_idle_pool() -> void:
	check(AIState.militia_count(20) <= 10, "hoechstens die Haelfte")
	check(AIState.militia_count(0) == 0, "ohne idle Braves keine Miliz")
	check(AIState.militia_count(1) == 1,
		"aber ein Raeuber IM Dorf wird auch von einem Ein-Brave-Stamm beantwortet")


func test_arena_span_uses_the_nearest_enemy_reincarnation_site() -> void:
	var w: Dictionary = _make_world()
	var ai: AIController = _make_ai(w, w.tribes[1], Vector2i(30, 30))
	w.building_manager.place(SITE_SCENE, w.tribes[0], Vector2i(66, 30), 0, true)
	var span: float = ai._arena_span()
	check(span > 30.0 and span < 42.0, "Abstand zum Feindanker gemessen (%.1f)" % span)
	check(AIState.is_cramped(span), "und als eng erkannt")
	ai.free()
	_free_world(w)


func test_arena_span_falls_back_to_the_map_when_no_enemy_stands() -> void:
	var w: Dictionary = _make_world()
	var ai: AIController = _make_ai(w, w.tribes[1], Vector2i(30, 30))
	check(not AIState.is_cramped(ai._arena_span()),
		"ohne feindliches Gebaeude gilt die Arena als offen")
	ai.free()
	_free_world(w)


func test_enemy_at_its_own_base_is_not_a_threat() -> void:
	# DER Kernfix. Zwei Anker 36 Zellen auseinander, Feindeinheiten an DEREN Anker:
	# vorher lag deren Basis im fixen 32-m-Radius und galt als Dauerbedrohung.
	var w: Dictionary = _make_world()
	var mine: Vector2i = Vector2i(30, 30)
	var theirs: Vector2i = Vector2i(66, 30)
	var ai: AIController = _make_ai(w, w.tribes[1], mine)
	w.building_manager.place(SITE_SCENE, w.tribes[1], mine, 0, true)
	w.building_manager.place(SITE_SCENE, w.tribes[0], theirs, 0, true)
	for i in range(5):
		w.unit_manager.spawn_unit(BRAVE_SCENE, 0, w.nav.cell_to_world(theirs + Vector2i(1, i)))
	check(ai._detect_threat().is_empty(),
		"Nachbarn an ihrem EIGENEN Anker sind keine Bedrohung")
	ai.free()
	_free_world(w)


func test_enemy_inside_our_territory_is_a_threat() -> void:
	# Gegenkontrolle zum vorigen Test.
	var w: Dictionary = _make_world()
	var mine: Vector2i = Vector2i(30, 30)
	var theirs: Vector2i = Vector2i(66, 30)
	var ai: AIController = _make_ai(w, w.tribes[1], mine)
	w.building_manager.place(SITE_SCENE, w.tribes[1], mine, 0, true)
	w.building_manager.place(SITE_SCENE, w.tribes[0], theirs, 0, true)
	w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, w.nav.cell_to_world(mine + Vector2i(2, 2)))
	check(not ai._detect_threat().is_empty(),
		"ein Gegner IN unserem Gebiet ist sehr wohl eine Bedrohung")
	ai.free()
	_free_world(w)


func test_expansion_anchor_avoids_enemy_territory() -> void:
	var w: Dictionary = _make_world()
	var mine: Vector2i = Vector2i(30, 30)
	var theirs: Vector2i = Vector2i(66, 30)
	var ai: AIController = _make_ai(w, w.tribes[1], mine)
	w.building_manager.place(SITE_SCENE, w.tribes[0], theirs, 0, true)
	ai._arena_span()   # fuellt _enemy_anchors
	# Der einzige Baum steht beim Feind.
	w.tree_manager.spawn_tree(theirs + Vector2i(3, 0), TreeResource.MAX_STAGE)
	check(ai._expansion_anchor().x < 0,
		"die KI expandiert nicht in Feindgebiet, auch wenn dort das Holz steht")
	ai.free()
	_free_world(w)


# --- Teil 2: Erreichbarkeit als EINE Wahrheit + Nachkontrolle (10g) -------------------
# Vorher urteilte die Vorpruefung ueber die PLOTMITTE (A* ab base_anchor), die
# Nachpruefung ueber den ANLAUFPUNKT (approach_island) — zwei verschiedene Fragen,
# also setzte die KI Bauplaetze, die sie sofort wieder abriss. Und NACH der
# Platzierung prueste nichts mehr.

func test_approach_cell_for_matches_the_live_delivery_point() -> void:
	var w: Dictionary = _make_world()
	var hut: Building = w.building_manager.place(HUT_SCENE, w.tribes[1],
		Vector2i(50, 50), 0, true)
	var statik: Vector2i = Building.approach_cell_for(w.nav, hut.cell, hut.footprint,
		hut.orientation)
	var live: Vector2i = w.nav.world_to_cell(hut.delivery_point())
	check(statik == live,
		"die statische Anlaufzelle stimmt mit delivery_point() ueberein (%s vs %s)"
			% [str(statik), str(live)])
	_free_world(w)


func test_approach_cell_for_reports_none_when_the_plot_is_enclosed() -> void:
	var w: Dictionary = _make_world()
	# Alles unter Wasser setzen: kein Ring findet mehr eine begehbare Zelle.
	for vz in range(w.td.size + 1):
		for vx in range(w.td.size + 1):
			w.td.set_vertex_height(vx, vz, 1.0)
	w.nav.update_region(Rect2i(0, 0, w.td.size, w.td.size))
	check(Building.approach_cell_for(w.nav, Vector2i(50, 50), Vector2i(4, 4), 0).x < 0,
		"ohne begehbare Anlaufzelle liefert sie (-1, -1) - diesen Fall liess die "
			+ "alte Mitten-Pruefung durch")
	_free_world(w)


func test_relax_pass_uses_one_ring_of_spacing() -> void:
	# Der Anti-Aushunger-Durchgang liess den Abstand vorher GANZ fallen und durfte
	# damit die Tuerschwelle eines Nachbarn zubauen.
	check(Balance.AI_PLOT_SPACING_RELAXED >= 1,
		"der Relax-Durchgang laesst einen Ring Luft, nicht null")
	check(Balance.AI_PLOT_SPACING_RELAXED < Balance.AI_PLOT_SPACING,
		"aber weniger als der normale Abstand")


func test_home_islands_include_the_base() -> void:
	var w: Dictionary = _make_world()
	var ai: AIController = _make_ai(w, w.tribes[1], Vector2i(40, 40))
	var homes: Dictionary = ai._home_islands()
	check(not homes.is_empty(), "die Basisinsel ist dabei")
	check(homes.has(w.nav.island_at(Vector2i(40, 40))), "und zwar genau sie")
	ai.free()
	_free_world(w)


func test_base_island_falls_back_to_the_reincarnation_site() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var ai: AIController = _make_ai(w, tribe, Vector2i(40, 40))
	w.building_manager.place(SITE_SCENE, tribe, Vector2i(40, 40), 0, true)
	check(ai._base_island() >= 0,
		"mit Reinkarnationsplatz auf dem Anker gibt es eine Basisinsel")
	ai.free()
	_free_world(w)


func test_site_guard_needs_two_strikes() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var ai: AIController = _make_ai(w, tribe, Vector2i(20, 20))
	for vz in range(w.td.size + 1):
		for vx in range(w.td.size + 1):
			var inner: bool = vx >= 74 and vx <= 86 and vz >= 74 and vz <= 86
			var outer: bool = vx >= 70 and vx <= 90 and vz >= 70 and vz <= 90
			if outer and not inner:
				w.td.set_vertex_height(vx, vz, 1.0)
	w.nav.update_region(Rect2i(Vector2i(68, 68), Vector2i(24, 24)))
	var site: Building = w.building_manager.place(HUT_SCENE, tribe,
		Vector2i(78, 78), 0, false)
	check(site != null and site.under_construction, "abgeschnittene Baustelle steht")
	# Erster Guard-Lauf: nur ein Strike, noch kein Abriss.
	ai._tick_count = Balance.AI_SITE_GUARD_INTERVAL
	ai._tick_site_guard(ai.build_tick_cache())
	check(is_instance_valid(site) and site.health > 0,
		"ein einzelner Fehlschlag verwirft nichts (Insel-Labels duerfen veralten)")
	ai._tick_count += Balance.AI_SITE_GUARD_INTERVAL
	ai._tick_site_guard(ai.build_tick_cache())
	check(not is_instance_valid(site) or site.health <= 0,
		"beim zweiten Strike wird die Baustelle ohne Baufortschritt verworfen")
	ai.free()
	_free_world(w)


func test_site_guard_abandons_instead_of_demolishing_a_half_built_site() -> void:
	# F8/F9: begin_demolish() macht daraus einen ARBEITER-Job und schaltet
	# _tick_decay ab. Ohne erreichbare Arbeiter blockiert das den Slot FUER IMMER —
	# schlimmer als der Bug. Verfallen bringt zudem 100 % statt 75 % zurueck.
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var ai: AIController = _make_ai(w, tribe, Vector2i(20, 20))
	for vz in range(w.td.size + 1):
		for vx in range(w.td.size + 1):
			var inner: bool = vx >= 74 and vx <= 86 and vz >= 74 and vz <= 86
			var outer: bool = vx >= 70 and vx <= 90 and vz >= 70 and vz <= 90
			if outer and not inner:
				w.td.set_vertex_height(vx, vz, 1.0)
	w.nav.update_region(Rect2i(Vector2i(68, 68), Vector2i(24, 24)))
	var site: Building = w.building_manager.place(HUT_SCENE, tribe,
		Vector2i(78, 78), 0, false)
	site.build_progress = 0.4
	check(site.has_build_stage(), "Baustelle MIT Baufortschritt")
	for i in range(Balance.AI_SITE_GUARD_STRIKES):
		ai._tick_count += Balance.AI_SITE_GUARD_INTERVAL
		ai._tick_site_guard(ai.build_tick_cache())
	check(is_instance_valid(site) and not site.demolishing,
		"sie wird NICHT abgerissen - der Verfall raeumt sie ab")
	check(ai._site_worker_want(site) == 0, "und sie wird nicht mehr bestueckt")
	check(ai._all_sites_supplied(ai.build_tick_cache()),
		"sie blockiert das Bau-Tor nicht mehr")
	ai.free()
	_free_world(w)


func test_scrapping_a_dead_site_does_not_pause_construction() -> void:
	# Latenter Fehler seit 10e: jeder Selbstabriss loeste den Rebuild-Cooldown aus
	# und pausierte den eigenen Bau 15 Ticks.
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[1]
	var ai: AIController = _make_ai(w, tribe, Vector2i(20, 20))
	for vz in range(w.td.size + 1):
		for vx in range(w.td.size + 1):
			var inner: bool = vx >= 74 and vx <= 86 and vz >= 74 and vz <= 86
			var outer: bool = vx >= 70 and vx <= 90 and vz >= 70 and vz <= 90
			if outer and not inner:
				w.td.set_vertex_height(vx, vz, 1.0)
	w.nav.update_region(Rect2i(Vector2i(68, 68), Vector2i(24, 24)))
	var site: Building = w.building_manager.place(HUT_SCENE, tribe,
		Vector2i(78, 78), 0, false)
	ai._rebuild_ticks = 0
	ai._accept_or_scrap_site(site, Vector2i(78, 78))
	check(ai._rebuild_ticks == 0,
		"ein Selbstabriss pausiert den eigenen Bau nicht")
	ai.free()
	_free_world(w)
