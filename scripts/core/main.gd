extends Node3D

## Root of the main scene. Creates the TerrainData (fixed seed), builds the
## Terrain, creates the NavGrid, positions the camera over the island and
## spawns the starting units. Must be headless-robust: no viewport-texture
## access in _ready().

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const SITE_SCENE: PackedScene = preload("res://scenes/buildings/reincarnation_site.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const WARRIOR_CAMP_SCENE: PackedScene = preload("res://scenes/buildings/warrior_camp.tscn")
const FIREWARRIOR_CAMP_SCENE: PackedScene = preload("res://scenes/buildings/firewarrior_camp.tscn")
const TEMPLE_SCENE: PackedScene = preload("res://scenes/buildings/temple.tscn")
const FORESTER_SCENE: PackedScene = preload("res://scenes/buildings/forester.tscn")
const WORKSHOP_SCENE: PackedScene = preload("res://scenes/buildings/workshop.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")
const PREACHER_SCENE: PackedScene = preload("res://scenes/units/preacher.tscn")
const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")
const START_BRAVES: int = 20
const TREE_COUNT: int = 60

## Skirmish (phase 7): base anchors sit evenly spaced on this circle around
## the island centre (cells) — 2 players = opposite sides, 3 = triangle,
## 4 = quadrants.
const SKIRMISH_BASE_RADIUS: float = 26.0
## Every skirmish base is guaranteed this many trees within reach, so all
## start positions can build (wood is delivered physically). A full base
## needs ~65 wood (3 huts + 3 training camps); big trees now yield 4 each
## (phase 7d) and regrow, so 12 covers it with margin.
const SKIRMISH_BASE_TREES: int = 12
const SKIRMISH_TREE_RADIUS: float = 20.0

## Stress test (key F9): spawns this many braves per tribe per press,
## staggered over frames so the spawn itself does not hitch.
const STRESS_BATCH_PER_TRIBE: int = 250
const STRESS_SPAWNS_PER_FRAME: int = 40
## Spawn areas per tribe (island quadrants).
const STRESS_ANCHORS: Array[Vector2i] = [
	Vector2i(44, 44), Vector2i(84, 44), Vector2i(44, 84), Vector2i(84, 84)]

## Debug battle (pause-menu "Debugschlacht"): two armies of this size meet in
## the middle of the island. Blue (tribe 0) stays player-controllable.
const DEBUG_ARMY_SIZE: int = 800
## Share of warriors per army; the rest are firewarriors (spawned in the back
## rows, since the outer spawn rings fill last).
const DEBUG_WARRIOR_SHARE: float = 0.7
## Army anchor offset from the island centre (cells, along x).
const DEBUG_ARMY_OFFSET: int = 26

## Time-lapse steps for manual testing (key F10 cycles through them). The
## engine simulates as many physics steps per frame as the CPU allows — at
## 100x the game time effectively runs ~10-30x (CPU-capped, display gets
## choppy), which skips the AI build-up phase in seconds.
const TIME_SCALE_STEPS: Array[float] = [1.0, 10.0, 100.0]

## Debug: spawn a small marker at the terrain raycast hit on left-click, to
## verify the HeightMapShape3D offset (marker must sit exactly under the cursor).
@export var debug_click_marker: bool = false

@onready var _terrain: Terrain = $Terrain
@onready var _camera_rig: CameraRig = $CameraRig
@onready var _unit_manager: UnitManager = $UnitManager
@onready var _unit_renderer: UnitRenderer = $UnitRenderer
@onready var _building_manager: BuildingManager = $BuildingManager
@onready var _tree_manager: TreeManager = $TreeManager
@onready var _wood_pile_manager: WoodPileManager = $WoodPileManager
@onready var _tribe_commands: TribeCommands = $TribeCommands
@onready var _selection: SelectionManager = $UI/SelectionManager
@onready var _sidebar: Sidebar = $UI/Sidebar
@onready var _build_menu: BuildMenu = $UI/BuildMenu
@onready var _spell_targeting: SpellTargeting = $UI/SpellTargeting
@onready var _route_visualizer: RouteVisualizer = $RouteVisualizer
@onready var _ring_renderer: SelectionRingRenderer = $SelectionRingRenderer
@onready var _end_screen: EndScreen = $UI/EndScreen

var _marker: MeshInstance3D = null
var _stress_pending: Array[int] = []   # tribe ids of queued stress spawns
var _stress_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _time_scale_index: int = 0


func _ready() -> void:
	# Every match starts in real time (the time-lapse is per-session global).
	Engine.time_scale = 1.0
	var td: TerrainData = TerrainData.new()
	td.generate_island(GameState.ISLAND_SEED)
	GameState.terrain_data = td
	GameState.terrain = _terrain

	_terrain.build(td)

	var nav: NavGrid = NavGrid.new(td)
	GameState.nav_grid = nav

	# Match configuration (set by the main menu); direct scene starts (tests,
	# headless checks) fall back to the start mission — today's behaviour.
	var config: MatchConfig = GameState.match_config
	if config == null:
		config = MatchConfig.start_mission()
		GameState.match_config = config
	GameState.stop_win_tracking()

	# Tribes: 0 = player (blue), rest = AI — identical instances.
	var tribes: Array[Tribe] = []
	for i in range(config.tribe_count()):
		tribes.append(Tribe.new(i, Unit.TRIBE_COLORS[i]))
	GameState.tribes = tribes
	_stress_rng.seed = GameState.ISLAND_SEED

	_unit_manager.setup(td, nav, tribes, _tree_manager, _wood_pile_manager)
	_unit_manager.unit_renderer = _unit_renderer
	_unit_manager.building_manager = _building_manager   # siege building scan (7f)
	_building_manager.setup(td, nav, _unit_manager, _wood_pile_manager)
	_tree_manager.setup(td, nav)
	_wood_pile_manager.setup(td)
	_tribe_commands.setup(nav, _building_manager, _unit_manager, _tree_manager)
	# Phase 6: spell world access + one spell set (own charges) per tribe.
	var spell_ctx: SpellContext = SpellContext.new()
	spell_ctx.terrain_data = td
	spell_ctx.nav_grid = nav
	spell_ctx.unit_manager = _unit_manager
	spell_ctx.building_manager = _building_manager
	spell_ctx.tree_manager = _tree_manager
	spell_ctx.wood_pile_manager = _wood_pile_manager
	_tribe_commands.spell_context = spell_ctx
	for tribe in tribes:
		tribe.set_spells(Spell.create_default_set())
		# Every spell begins with one stored charge — EXCEPT in skirmish, where
		# both sides start with empty charges and must build mana up first.
		if config.mode != MatchConfig.Mode.SKIRMISH:
			for spell in tribe.spells:
				spell.charges = 1
	_selection.setup(_unit_manager, _tribe_commands, _build_menu, _spell_targeting)
	_ring_renderer.setup(_selection)
	_build_menu.setup(_tribe_commands, nav, self, tribes[GameState.PLAYER_TRIBE])
	_spell_targeting.setup(_tribe_commands, tribes[GameState.PLAYER_TRIBE], self,
		_build_menu)
	_sidebar.setup(tribes, GameState.PLAYER_TRIBE, _unit_manager, _building_manager,
		_tree_manager, _wood_pile_manager, _tribe_commands, _build_menu, _selection,
		_camera_rig, td, _spell_targeting)
	_route_visualizer.setup(_selection, td)

	# Phase 5d overlays/audio (created in code — no scene entries needed).
	var stars: StarsRenderer = StarsRenderer.new()
	stars.name = "StarsRenderer"
	add_child(stars)
	stars.setup(_unit_manager)
	# Range rings for ranged units, toggled with G (phase 7f).
	var ranges: RangeRenderer = RangeRenderer.new()
	ranges.name = "RangeRenderer"
	add_child(ranges)
	ranges.setup(_unit_manager, GameState.PLAYER_TRIBE, td)
	var combat_audio: CombatAudio = CombatAudio.new()
	combat_audio.name = "CombatAudio"
	add_child(combat_audio)

	# Terrain deformations (foundation flattening, later Landbridge) rebuild
	# the affected mesh chunks + collision here.
	Events.terrain_deformed.connect(_terrain.apply_deformation)

	# End screen (phase 7): shows Sieg/Niederlage once the match is decided.
	GameState.match_ended.connect(_end_screen.show_result)
	GameState.tribe_defeated.connect(func(id: int) -> void:
		print("Stamm %d ist besiegt" % id))
	GameState.match_ended.connect(func(id: int) -> void:
		print("Match beendet — Sieger: Stamm %d" % id))

	var center_cell: Vector2i = Vector2i(TerrainData.SIZE / 2, TerrainData.SIZE / 2)
	var camera_anchor: Vector2i = center_cell
	_tree_manager.spawn_trees(TREE_COUNT, GameState.ISLAND_SEED)
	match config.mode:
		MatchConfig.Mode.DEBUG_BATTLE:
			# Sandbox: two armies clashing, no bases and no win tracking.
			_setup_debug_battle(nav)
		MatchConfig.Mode.START_MISSION:
			_place_start_site(tribes[GameState.PLAYER_TRIBE], nav)
			_setup_player_base(tribes[GameState.PLAYER_TRIBE], nav)
			_spawn_braves_near(GameState.PLAYER_TRIBE, center_cell, START_BRAVES, nav)
			_setup_sparring(tribes, nav)
			GameState.start_win_tracking()
		MatchConfig.Mode.SKIRMISH:
			camera_anchor = _setup_skirmish(tribes, nav)
			GameState.start_win_tracking()

	# Start the camera over the player's base (skirmish) or the island centre.
	_camera_rig.global_position = nav.cell_to_world(camera_anchor)


## Pre-places the player's reincarnation site (free, fully built) on the first
## valid footprint near the island centre, plus the blue shaman next to it.
func _place_start_site(tribe: Tribe, nav: NavGrid) -> void:
	var center: Vector2i = Vector2i(TerrainData.SIZE / 2 + 6, TerrainData.SIZE / 2)
	var site: Building = _place_site_near(tribe, center)
	_spawn_shaman_near(tribe, site, center, nav)


## First valid footprint near `anchor` gets the tribe's reincarnation site.
func _place_site_near(tribe: Tribe, anchor: Vector2i) -> Building:
	var fp: Vector2i = ReincarnationSite.FOOTPRINT
	for radius in range(0, TerrainData.SIZE / 2):
		for cell in _ring_cells(anchor, radius):
			if _tribe_commands.can_place_at(cell, fp):
				return _building_manager.place(SITE_SCENE, tribe, cell, 0, true)
	push_warning("No valid spot for a reincarnation site near %s found" % anchor)
	return null


## Spawns the tribe's shaman at the site's edge (fallback: walkable cell near
## the anchor).
func _spawn_shaman_near(tribe: Tribe, site: Building, anchor: Vector2i, nav: NavGrid) -> void:
	var pos: Vector3
	if site != null:
		pos = site.edge_spawn_position()
	else:
		var cell: Vector2i = _find_walkable_near(anchor, nav, 0)
		if cell.x < 0:
			push_warning("No spawn spot for the shaman of tribe %d" % tribe.id)
			return
		pos = nav.cell_to_world(cell)
	_unit_manager.spawn_unit(SHAMAN_SCENE, tribe.id, pos)


## Spawns `count` braves for a tribe on walkable cells around `center`,
## spread out via a spiral ring search.
func _spawn_braves_near(tribe_id: int, center: Vector2i, count: int, nav: NavGrid) -> void:
	var spawned: int = 0
	for radius in range(0, TerrainData.SIZE / 2):
		for cell in _ring_cells(center, radius):
			if spawned >= count:
				return
			if not nav.is_cell_walkable(cell):
				continue
			if (cell.x + cell.y) % 2 != 0:
				continue  # every other cell, for spacing
			_unit_manager.spawn_unit(BRAVE_SCENE, tribe_id, nav.cell_to_world(cell))
			spawned += 1
	if spawned < count:
		push_warning("Only %d of %d start braves spawned (tribe %d)"
			% [spawned, count, tribe_id])


# --- Skirmish setup (phase 7) ---------------------------------------------------

## Places one identical starter base per tribe (reincarnation site + shaman +
## hut + start braves + trees in reach) evenly spread on a circle around the
## island centre, and attaches one AIController per AI tribe. Returns the
## player's base anchor (camera start).
func _setup_skirmish(tribes: Array[Tribe], nav: NavGrid) -> Vector2i:
	# Headless sim hook: `-- ai-player` lets an AI drive the player tribe too
	# (full AI-vs-AI integration run, see the phase 7 plan).
	var ai_player: bool = OS.get_cmdline_user_args().has("ai-player")
	for tribe in tribes:
		var anchor: Vector2i = _skirmish_anchor(tribe.id, tribes.size())
		_setup_skirmish_base(tribe, anchor, nav)
		if tribe.id != GameState.PLAYER_TRIBE or ai_player:
			var ai: AIController = AIController.new()
			ai.name = "AIController%d" % tribe.id
			ai.debug_log = OS.get_cmdline_user_args().has("ai-log")
			add_child(ai)
			ai.setup(tribe, _tribe_commands, _unit_manager, _building_manager,
				_tree_manager, nav, anchor)
	return _skirmish_anchor(GameState.PLAYER_TRIBE, tribes.size())


## Base anchor of the index-th tribe: evenly spaced on the circle, the player
## starting in the south.
func _skirmish_anchor(index: int, count: int) -> Vector2i:
	var center: float = float(TerrainData.SIZE) * 0.5
	var angle: float = TAU * float(index) / float(maxi(count, 1)) + PI * 0.5
	return Vector2i(
		int(round(center + cos(angle) * SKIRMISH_BASE_RADIUS)),
		int(round(center + sin(angle) * SKIRMISH_BASE_RADIUS)))


## One symmetric starter kit — the SAME for player and AI (no cheats).
func _setup_skirmish_base(tribe: Tribe, anchor: Vector2i, nav: NavGrid) -> void:
	var site: Building = _place_site_near(tribe, anchor)
	_spawn_shaman_near(tribe, site, anchor, nav)
	var hut_cell: Vector2i = _find_plot(anchor + Vector2i(-8, -3), Hut.FOOTPRINT, nav)
	if hut_cell.x >= 0:
		_building_manager.place(HUT_SCENE, tribe, hut_cell, 0, true)
	_spawn_braves_near(tribe.id, anchor + Vector2i(0, 6), START_BRAVES, nav)
	_ensure_trees_near(anchor, nav)


## Tops up the woods around a base anchor to SKIRMISH_BASE_TREES (big trees),
## respecting the tree manager's minimum spacing.
func _ensure_trees_near(anchor: Vector2i, nav: NavGrid) -> void:
	var anchor_world: Vector3 = nav.cell_to_world(anchor)
	var have: int = 0
	for tree in _tree_manager.trees:
		if tree.position.distance_to(anchor_world) <= SKIRMISH_TREE_RADIUS:
			have += 1
	var missing: int = SKIRMISH_BASE_TREES - have
	if missing <= 0:
		return
	var step: int = 0
	for radius in range(10, int(SKIRMISH_TREE_RADIUS)):
		for cell in _ring_cells(anchor, radius):
			if missing <= 0:
				return
			step += 1
			if step % 3 != 0:
				continue  # every third candidate, so the wood is loose
			if not nav.is_cell_walkable(cell):
				continue
			if _tree_too_close(cell):
				continue
			_tree_manager.spawn_tree(cell, TreeResource.MAX_STAGE)
			missing -= 1


func _tree_too_close(cell: Vector2i) -> bool:
	for dz in range(-TreeManager.MIN_SPACING, TreeManager.MIN_SPACING + 1):
		for dx in range(-TreeManager.MIN_SPACING, TreeManager.MIN_SPACING + 1):
			if _tree_manager.has_tree_at(cell + Vector2i(dx, dz)):
				return true
	return false


## Pre-places the player's starting base (fully built): two huts and all three
## training buildings (Kaserne/Feuertempel/Tempel) around the island centre, so
## training and rally points can be tried right away. Placements are sequential
## (each marks its footprint nav-solid), so _find_plot avoids overlaps.
func _setup_player_base(tribe: Tribe, nav: NavGrid) -> void:
	var center: Vector2i = Vector2i(TerrainData.SIZE / 2, TerrainData.SIZE / 2)
	var plan: Array = [
		[HUT_SCENE, center + Vector2i(-10, -9)],
		[HUT_SCENE, center + Vector2i(9, -9)],
		[WARRIOR_CAMP_SCENE, center + Vector2i(-12, 7)],
		[FIREWARRIOR_CAMP_SCENE, center + Vector2i(0, 12)],
		[TEMPLE_SCENE, center + Vector2i(12, 7)],
	]
	for entry in plan:
		var scene: PackedScene = entry[0]
		var anchor: Vector2i = entry[1]
		var probe: Building = scene.instantiate() as Building
		var fp: Vector2i = probe.footprint
		probe.free()
		var c: Vector2i = _find_plot(anchor, fp, nav)
		if c.x >= 0:
			_building_manager.place(scene, tribe, c, 0, true)


## Statically pre-places a red sparring tribe (id 1) on the far side of the
## island: a hut, a warrior camp and a handful of braves/warriors/firewarriors.
## They do not fight yet (that is phase 5b) — this is the target dummy setup so
## training and rally points can be tried against real enemy units.
func _setup_sparring(tribes: Array[Tribe], nav: NavGrid) -> void:
	if tribes.size() < 2:
		return
	var red: Tribe = tribes[1]
	var anchor: Vector2i = Vector2i(TerrainData.SIZE / 2 + 20, TerrainData.SIZE / 2 + 20)
	var hut_cell: Vector2i = _find_plot(anchor, Hut.FOOTPRINT, nav)
	if hut_cell.x >= 0:
		_building_manager.place(HUT_SCENE, red, hut_cell, 0, true)
	var camp_cell: Vector2i = _find_plot(anchor + Vector2i(-8, 0), WarriorCamp.FOOTPRINT, nav)
	if camp_cell.x >= 0:
		_building_manager.place(WARRIOR_CAMP_SCENE, red, camp_cell, 0, true)
	# Red reincarnation site + shaman (phase 6): the enemy shaman exists and
	# respawns just like the player's.
	var red_site: Building = _place_site_near(red, anchor + Vector2i(8, 8))
	_spawn_shaman_near(red, red_site, anchor + Vector2i(8, 8), nav)
	# A small starting force spread around the anchor.
	_spawn_sparring_units(red, anchor, nav)
	# Fully-staffed industry buildings so the phase-7g occupant eject can be
	# tried in-game: two manned foresters and one manned (idle) workshop.
	_setup_sparring_industry(red, anchor, nav)


## Two fully-staffed foresters and one staffed but idle (paused) workshop for
## the sparring enemy — targets to test the building-assault occupant eject.
func _setup_sparring_industry(red: Tribe, anchor: Vector2i, nav: NavGrid) -> void:
	for off in [Vector2i(-7, -6), Vector2i(7, -6)]:
		var fcell: Vector2i = _find_plot(anchor + off, Forester.FOOTPRINT, nav)
		if fcell.x >= 0:
			var f: Forester = _building_manager.place(
				FORESTER_SCENE, red, fcell, 0, true) as Forester
			_staff_building(f, Forester.WORKER_SLOTS, red.id, true)
	var wcell: Vector2i = _find_plot(anchor + Vector2i(0, 11), Workshop.FOOTPRINT, nav)
	if wcell.x >= 0:
		var ws: Workshop = _building_manager.place(
			WORKSHOP_SCENE, red, wcell, 0, true) as Workshop
		if ws != null:
			ws.paused = true   # manned, but produces nothing
			_staff_building(ws, Workshop.WORKER_SLOTS, red.id, false)


## Spawns `slots` braves and houses them inside a forester/workshop right away
## (skips the walk-in), so the building starts fully staffed.
func _staff_building(building: Building, slots: int, tribe_id: int, is_forester: bool) -> void:
	if building == null:
		return
	for i in range(slots):
		var b: Brave = _unit_manager.spawn_unit(
			BRAVE_SCENE, tribe_id, building.edge_spawn_position()) as Brave
		if b == null:
			return
		if is_forester:
			b.order_forester(building as Forester)
			(building as Forester).admit_worker(b)
		else:
			b.order_workshop(building as Workshop)
			(building as Workshop).admit_worker(b)


func _spawn_sparring_units(red: Tribe, anchor: Vector2i, nav: NavGrid) -> void:
	var plan: Array = [
		[BRAVE_SCENE, 4], [WARRIOR_SCENE, 3], [FIREWARRIOR_SCENE, 2],
		[PREACHER_SCENE, 2]]   # enemy preachers: conversion + priest duel (5c)
	var placed: int = 0
	for entry in plan:
		var scene: PackedScene = entry[0]
		for i in range(int(entry[1])):
			var cell: Vector2i = _find_walkable_near(anchor + Vector2i(6, 0), nav, placed)
			if cell.x >= 0:
				_unit_manager.spawn_unit(scene, red.id, nav.cell_to_world(cell))
			placed += 1


# --- Debug battle (pause menu) ---------------------------------------------------

## Two armies of DEBUG_ARMY_SIZE units each (blue = tribe 0, player-controlled;
## red = tribe 1) spawn left/right of the island centre and march at each
## other's anchor — the aggro system takes over on contact.
func _setup_debug_battle(nav: NavGrid) -> void:
	var center: Vector2i = Vector2i(TerrainData.SIZE / 2, TerrainData.SIZE / 2)
	var blue_anchor: Vector2i = center + Vector2i(-DEBUG_ARMY_OFFSET, 0)
	var red_anchor: Vector2i = center + Vector2i(DEBUG_ARMY_OFFSET, 0)
	_spawn_debug_army(0, blue_anchor, nav)
	_spawn_debug_army(1, red_anchor, nav)
	# Each army brings its shaman (behind the lines) with FULL spell charges.
	_spawn_debug_shaman(0, blue_anchor + Vector2i(-6, 0), nav)
	_spawn_debug_shaman(1, red_anchor + Vector2i(6, 0), nav)
	# March each army at the enemy anchor (attack-move: combatants engage on
	# contact); the path queue spreads the A* load.
	_tribe_commands.order_move(
		_unit_manager.get_units_of_tribe(0), nav.cell_to_world(red_anchor), false, true)
	_tribe_commands.order_move(
		_unit_manager.get_units_of_tribe(1), nav.cell_to_world(blue_anchor), false, true)
	print("Debugschlacht: %d Einheiten gesamt" % _unit_manager.units.size())


## Spawns the tribe's shaman for the debug battle and fills every spell to
## its maximum charges (spell testing in the brawl).
func _spawn_debug_shaman(tribe_id: int, anchor: Vector2i, nav: NavGrid) -> void:
	var cell: Vector2i = _find_walkable_near(anchor, nav, 0)
	if cell.x < 0:
		return
	_unit_manager.spawn_unit(SHAMAN_SCENE, tribe_id, nav.cell_to_world(cell))
	var tribe: Tribe = GameState.get_tribe(tribe_id)
	if tribe != null:
		for spell in tribe.spells:
			spell.charges = spell.max_charges


## Fills walkable cells ring by ring around the anchor: warriors first (inner
## rows), firewarriors behind them (outer rows).
func _spawn_debug_army(tribe_id: int, anchor: Vector2i, nav: NavGrid) -> void:
	var warriors: int = int(float(DEBUG_ARMY_SIZE) * DEBUG_WARRIOR_SHARE)
	var spawned: int = 0
	for radius in range(0, 40):
		for cell in _ring_cells(anchor, radius):
			if spawned >= DEBUG_ARMY_SIZE:
				return
			if not nav.is_cell_walkable(cell):
				continue
			var scene: PackedScene = WARRIOR_SCENE if spawned < warriors \
				else FIREWARRIOR_SCENE
			_unit_manager.spawn_unit(scene, tribe_id, nav.cell_to_world(cell))
			spawned += 1
	if spawned < DEBUG_ARMY_SIZE:
		push_warning("Debugschlacht: nur %d von %d Einheiten für Stamm %d gespawnt"
			% [spawned, DEBUG_ARMY_SIZE, tribe_id])


## Ring-searches outward from `center` for the first buildable footprint.
func _find_plot(center: Vector2i, footprint: Vector2i, _nav: NavGrid) -> Vector2i:
	for radius in range(0, TerrainData.SIZE / 2):
		for cell in _ring_cells(center, radius):
			if _tribe_commands.can_place_at(cell, footprint):
				return cell
	return Vector2i(-1, -1)


## Ring-searches for a walkable cell near `center`; `skip` staggers picks so
## repeated calls do not stack units on the same spot.
func _find_walkable_near(center: Vector2i, nav: NavGrid, skip: int) -> Vector2i:
	var seen: int = 0
	for radius in range(0, 24):
		for cell in _ring_cells(center, radius):
			if not nav.is_cell_walkable(cell):
				continue
			if not _tribe_commands.can_place_at(cell, Vector2i(1, 1)):
				continue
			if seen >= skip:
				return cell
			seen += 1
	return Vector2i(-1, -1)


func _ring_cells(center: Vector2i, radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if radius == 0:
		cells.append(center)
		return cells
	for dx in range(-radius, radius + 1):
		cells.append(center + Vector2i(dx, -radius))
		cells.append(center + Vector2i(dx, radius))
	for dz in range(-radius + 1, radius):
		cells.append(center + Vector2i(-radius, dz))
		cells.append(center + Vector2i(radius, dz))
	return cells


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("stress_test"):
		_queue_stress_batch()
		return
	if event.is_action_pressed("time_scale_toggle"):
		_cycle_time_scale()
		return
	if not debug_click_marker:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_place_debug_marker(event.position)


# --- Time-lapse (F10) -----------------------------------------------------------

## Cycles 1x -> 10x -> 100x game speed. max_physics_steps_per_frame is raised
## along with it so the physics (and with it the whole simulation, which runs
## in _physics_process ticks) actually keeps up with the scaled clock; the
## cap keeps single frames short enough that input (F10 again!) stays usable.
func _cycle_time_scale() -> void:
	_time_scale_index = (_time_scale_index + 1) % TIME_SCALE_STEPS.size()
	var factor: float = TIME_SCALE_STEPS[_time_scale_index]
	Engine.time_scale = factor
	Engine.max_physics_steps_per_frame = clampi(int(factor) * 4, 8, 120)
	print("Zeitraffer: %dx" % int(factor))


# --- Stress test (F9) ----------------------------------------------------------

## Queues STRESS_BATCH_PER_TRIBE braves for every tribe; _physics_process
## spawns them staggered over frames.
func _queue_stress_batch() -> void:
	for tribe_id in range(GameState.tribes.size()):
		for i in range(STRESS_BATCH_PER_TRIBE):
			_stress_pending.append(tribe_id)
	print("Stresstest: %d Einheiten in Warteschlange (gesamt danach: %d)" % [
		_stress_pending.size(), _unit_manager.units.size() + _stress_pending.size()])


func _physics_process(_delta: float) -> void:
	if _stress_pending.is_empty():
		return
	var spawned: int = 0
	while spawned < STRESS_SPAWNS_PER_FRAME and not _stress_pending.is_empty():
		_spawn_stress_brave(_stress_pending.pop_back())
		spawned += 1
	if _stress_pending.is_empty():
		print("Stresstest: Spawnen fertig — %d Einheiten gesamt" % _unit_manager.units.size())


func _spawn_stress_brave(tribe_id: int) -> void:
	var nav: NavGrid = GameState.nav_grid
	var anchor: Vector2i = STRESS_ANCHORS[tribe_id % STRESS_ANCHORS.size()]
	for attempt in range(24):
		var cell: Vector2i = anchor + Vector2i(
			_stress_rng.randi_range(-18, 18), _stress_rng.randi_range(-18, 18))
		if nav.is_cell_walkable(cell):
			_unit_manager.spawn_unit(BRAVE_SCENE, tribe_id, nav.cell_to_world(cell))
			return


func _place_debug_marker(screen_pos: Vector2) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var from: Vector3 = cam.project_ray_origin(screen_pos)
	var dir: Vector3 = cam.project_ray_normal(screen_pos)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from + dir * 1000.0)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return
	if _marker == null:
		_marker = MeshInstance3D.new()
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = 0.6
		sphere.height = 1.2
		_marker.mesh = sphere
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.1, 0.1)
		_marker.material_override = mat
		add_child(_marker)
	_marker.global_position = hit.position
