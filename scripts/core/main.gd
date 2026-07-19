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
const WATCHTOWER_SCENE: PackedScene = preload("res://scenes/buildings/watchtower.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")
const PREACHER_SCENE: PackedScene = preload("res://scenes/units/preacher.tscn")
const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")
const SIEGE_SCENE: PackedScene = preload("res://scenes/units/siege_engine.tscn")
const FIRE_RAM_SCENE: PackedScene = preload("res://scenes/units/fire_ram.tscn")
const AIRSHIP_SCENE: PackedScene = preload("res://scenes/units/airship.tscn")
const FIRERAM_WORKSHOP_SCENE: PackedScene = preload("res://scenes/buildings/fire_ram_workshop.tscn")
const AIRSHIP_WHARF_SCENE: PackedScene = preload("res://scenes/buildings/airship_wharf.tscn")
const START_BRAVES: int = 20
const TREE_COUNT: int = 60

## Startmission = Debug-Testkammer (user request): blue on the west side with
## one building of each kind, one vehicle of each kind and this many braves;
## red on the east side with one building of each kind but THREE fully manned
## watchtowers, two fully manned vehicles of each kind (firewarrior/preacher
## crews) and this many warriors/firewarriors/preachers — the red BUILDINGS
## face the player, everything else sits behind them. No AI: a static range.
const CHAMBER_BRAVES: int = 100
const CHAMBER_RED_ARMY: int = 100

## Phase 8.1 (Stufe A): route unit path requests through the off-main-thread
## PathWorker. Set to false for an A/B comparison or as an emergency fallback to
## the fully synchronous (pre-8.1) behaviour. Disabled with a single core.
const USE_PATH_WORKER: bool = true

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

## Stress test (key F9): spawns this many braves TOTAL per press (split over
## the tribes), staggered over frames so the spawn itself does not hitch.
## Phase-8 targets: one press = 2000 units, three presses = 6000 (needs a
## 4-player skirmish — the 1500-per-tribe hard cap still applies).
const STRESS_BATCH_TOTAL: int = 2000
const STRESS_SPAWNS_PER_FRAME: int = 40

## Debug battle (pause-menu "Debugschlacht"): two armies of this size meet in
## the middle of the island. Blue (tribe 0) stays player-controllable.
const DEBUG_ARMY_SIZE: int = 800
## Share of warriors per army; the rest are firewarriors (spawned in the back
## rows, since the outer spawn rings fill last).
const DEBUG_WARRIOR_SHARE: float = 0.7
## Army anchor offset from the island centre (cells, along x).
const DEBUG_ARMY_OFFSET: int = 26
## Extra reinforcements per side: fully crewed vehicles + foot units, spawned
## in each army's rear so they march in behind the main line.
const DEBUG_EXTRA_ARMY: int = 100      # additional foot units per side
const DEBUG_ZEPPELINS: int = 3
const DEBUG_CATAPULTS: int = 2
const DEBUG_FIRERAMS: int = 4
const DEBUG_REAR_OFFSET: int = 14      # cells behind the army anchor (rear direction)

## Stress-test match (main-menu "Stresstest", phase 8.2 follow-up): four full
## armies (tribe 0 stays player-controllable, the other three are scripted —
## no AIController) idle briefly, then all attack-move at the island centre
## while their shamans keep casting. A sandbox like the debug battle: no
## bases, no win tracking.
const STRESS_MATCH_ARMY: int = 1000
const STRESS_MATCH_WARRIOR_SHARE: float = 0.6
const STRESS_MATCH_FW_SHARE: float = 0.3     # the rest are preachers
const STRESS_MATCH_SIEGE: int = 6            # crewed catapults per army
const STRESS_MATCH_SIEGE_CREW: int = 3
## Army anchor offset from the island centre (cells).
const STRESS_MATCH_OFFSET: int = 30
## Idle time before the armies march.
const STRESS_MATCH_IDLE_DELAY: float = 5.0
## One cast per tribe every this many seconds, cycling through the list; the
## charge is refilled before each cast — sustained spell load is the point.
const STRESS_MATCH_CAST_INTERVAL: float = 5.0
const STRESS_MATCH_SPELLS: Array[StringName] = [
	&"tornado", &"earthquake", &"swarm", &"firestorm"]

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
# Stress-test match driver state (see STRESS_MATCH_* constants).
var _stress_match: bool = false
var _stress_match_marched: bool = false
var _stress_match_timer: float = 0.0
var _stress_cast_timer: float = 0.0
var _stress_spell_index: int = 0


func _ready() -> void:
	# Every match starts in real time (the time-lapse is per-session global);
	# the catch-up cap returns to the project default (see _cycle_time_scale).
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 2

	# Match configuration (set by the main menu); direct scene starts (tests,
	# headless checks) fall back to the start mission — today's behaviour.
	var config: MatchConfig = GameState.match_config
	if config == null:
		config = MatchConfig.start_mission()
		GameState.match_config = config
	GameState.stop_win_tracking()

	# Map (phase 7i): skirmish uses the chosen map; other modes use the default
	# island. The map decides the grid size (128 or 256) and its heightmap.
	var map_id: String = config.map_id if config.mode == MatchConfig.Mode.SKIRMISH \
		else MapGenerator.DEFAULT_MAP
	GameState.map_id = map_id
	var td: TerrainData = MapGenerator.create_terrain(map_id, GameState.ISLAND_SEED)
	GameState.terrain_data = td
	GameState.terrain = _terrain

	_terrain.build(td)

	var nav: NavGrid = NavGrid.new(td)
	GameState.nav_grid = nav

	# Phase 8.1: spin up the off-thread path worker seeded from the freshly built
	# grid, then wire it into NavGrid (delta mirror) and UnitManager (async
	# solve). Needs >1 core; UnitManager._exit_tree joins the thread on teardown.
	if USE_PATH_WORKER and OS.get_processor_count() > 1:
		var worker: PathWorker = PathWorker.new(
			Rect2i(0, 0, td.size, td.size),
			Vector2(TerrainData.CELL_SIZE, TerrainData.CELL_SIZE),
			AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES,
			nav.solid_snapshot(), td.size)
		nav.path_worker = worker
		_unit_manager.path_worker = worker

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
	_selection.setup(_unit_manager, _tribe_commands, _build_menu, _spell_targeting,
		_building_manager)
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
	# Persistent status overlays (panic/burning/injured) + their loop sounds.
	var status_fx: StatusFxRenderer = StatusFxRenderer.new()
	status_fx.name = "StatusFxRenderer"
	add_child(status_fx)
	status_fx.setup(_unit_manager, _tree_manager)
	# Range rings for ranged units, toggled with G (phase 7f).
	var ranges: RangeRenderer = RangeRenderer.new()
	ranges.name = "RangeRenderer"
	add_child(ranges)
	ranges.setup(_unit_manager, GameState.PLAYER_TRIBE, td)
	var combat_audio: CombatAudio = CombatAudio.new()
	combat_audio.name = "CombatAudio"
	add_child(combat_audio)
	# FPS counter (phase 8), toggled via the main-menu options (persisted).
	var fps_overlay: FpsOverlay = FpsOverlay.new()
	fps_overlay.name = "FpsOverlay"
	$UI.add_child(fps_overlay)
	# Selected-unit counter following the mouse cursor.
	var cursor_count: CursorCountLabel = CursorCountLabel.new()
	cursor_count.name = "CursorCountLabel"
	$UI.add_child(cursor_count)
	cursor_count.setup(_selection)

	# Terrain deformations (foundation flattening, later Landbridge) rebuild
	# the affected mesh chunks + collision here.
	Events.terrain_deformed.connect(_terrain.apply_deformation)

	# End screen (phase 7): shows Sieg/Niederlage once the match is decided.
	GameState.match_ended.connect(_end_screen.show_result)
	GameState.tribe_defeated.connect(func(id: int) -> void:
		print("Stamm %d ist besiegt" % id))
	GameState.match_ended.connect(func(id: int) -> void:
		print("Match beendet — Sieger: Stamm %d" % id))

	var center_cell: Vector2i = Vector2i(td.size / 2, td.size / 2)
	var camera_anchor: Vector2i = center_cell
	# Scale the wild-tree count with the map area (128 -> TREE_COUNT, 256 -> 4x).
	var tree_count: int = TREE_COUNT * (td.size * td.size) / (TerrainData.SIZE * TerrainData.SIZE)
	_tree_manager.spawn_trees(tree_count, GameState.ISLAND_SEED)
	match config.mode:
		MatchConfig.Mode.DEBUG_BATTLE:
			# Sandbox: two armies clashing, no bases and no win tracking.
			_setup_debug_battle(nav)
		MatchConfig.Mode.STRESS_TEST:
			# Sandbox: four full armies + catapults + spell barrage.
			camera_anchor = _setup_stress_match(nav)
		MatchConfig.Mode.START_MISSION:
			camera_anchor = _setup_test_chamber(tribes, nav)
			GameState.start_win_tracking()
		MatchConfig.Mode.SKIRMISH:
			camera_anchor = _setup_skirmish(tribes, nav)
			GameState.start_win_tracking()

	# Start the camera over the player's base (skirmish) or the island centre.
	_camera_rig.global_position = nav.cell_to_world(camera_anchor)


## First valid footprint near `anchor` gets the tribe's reincarnation site.
func _place_site_near(tribe: Tribe, anchor: Vector2i) -> Building:
	var fp: Vector2i = ReincarnationSite.FOOTPRINT
	for radius in range(0, GameState.terrain_data.size / 2):
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
	for radius in range(0, GameState.terrain_data.size / 2):
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
	var anchors: Array[Vector2i] = MapGenerator.spawn_anchors(
		GameState.terrain_data, GameState.map_id, tribes.size())
	for tribe in tribes:
		var anchor: Vector2i = anchors[tribe.id]
		_setup_skirmish_base(tribe, anchor, nav)
		if tribe.id != GameState.PLAYER_TRIBE or ai_player:
			var ai: AIController = AIController.new()
			ai.name = "AIController%d" % tribe.id
			ai.debug_log = OS.get_cmdline_user_args().has("ai-log")
			# Stagger the 1-Hz AI ticks across the second — without an offset
			# all AIs tick in the SAME frame and their (potentially expensive)
			# build/plot scans stack into one hitch per second.
			ai.stagger_offset(float(tribe.id) / float(tribes.size()))
			add_child(ai)
			ai.setup(tribe, _tribe_commands, _unit_manager, _building_manager,
				_tree_manager, nav, anchor)
	return anchors[GameState.PLAYER_TRIBE]


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


## Debug-Testkammer (Startmission, user request): blue base on the WEST side
## — one building of each kind, one unmanned vehicle of each kind and
## CHAMBER_BRAVES braves. Red on the EAST side: one building of each kind but
## THREE fully manned watchtowers, two fully manned vehicles of each kind
## (firewarrior/preacher crews) and CHAMBER_RED_ARMY warriors/firewarriors/
## preachers. The red BUILDINGS face the player base; site, vehicles and army
## sit behind them. No AIController — a static firing range.
func _setup_test_chamber(tribes: Array[Tribe], nav: NavGrid) -> Vector2i:
	var center: Vector2i = Vector2i(TerrainData.SIZE / 2, TerrainData.SIZE / 2)
	var blue_anchor: Vector2i = center + Vector2i(-22, 0)
	_setup_chamber_blue(tribes[GameState.PLAYER_TRIBE], blue_anchor, nav)
	if tribes.size() > 1:
		_setup_chamber_red(tribes[1], center, nav)
	return blue_anchor


func _setup_chamber_blue(tribe: Tribe, anchor: Vector2i, nav: NavGrid) -> void:
	var site: Building = _place_site_near(tribe, anchor + Vector2i(0, -12))
	_spawn_shaman_near(tribe, site, anchor + Vector2i(0, -12), nav)
	_place_chamber_buildings(tribe, [
		[HUT_SCENE, anchor + Vector2i(-12, -8)],
		[WARRIOR_CAMP_SCENE, anchor + Vector2i(-13, 3)],
		[FIREWARRIOR_CAMP_SCENE, anchor + Vector2i(-5, 12)],
		[TEMPLE_SCENE, anchor + Vector2i(7, 11)],
		[FORESTER_SCENE, anchor + Vector2i(-17, -3)],
		[WORKSHOP_SCENE, anchor + Vector2i(5, -12)],
		[FIRERAM_WORKSHOP_SCENE, anchor + Vector2i(13, -4)],
		[AIRSHIP_WHARF_SCENE, anchor + Vector2i(15, 6)],
		[WATCHTOWER_SCENE, anchor + Vector2i(0, -7)],
	], nav)
	# One unmanned vehicle of each kind next to the base (crew via right-click).
	for entry in [[SIEGE_SCENE, Vector2i(2, 2)], [FIRE_RAM_SCENE, Vector2i(5, 4)],
			[AIRSHIP_SCENE, Vector2i(0, 7)]]:
		var cell: Vector2i = _find_walkable_near(anchor + entry[1], nav, 0)
		if cell.x >= 0:
			_unit_manager.spawn_unit(entry[0], tribe.id, nav.cell_to_world(cell))
	_spawn_braves_near(tribe.id, anchor + Vector2i(0, 2), CHAMBER_BRAVES, nav)


func _setup_chamber_red(red: Tribe, center: Vector2i, nav: NavGrid) -> void:
	# Buildings CLOSE to the player base (west edge of the red zone)...
	var banchor: Vector2i = center + Vector2i(12, 0)
	_place_chamber_buildings(red, [
		[HUT_SCENE, banchor + Vector2i(2, -12)],
		[WARRIOR_CAMP_SCENE, banchor + Vector2i(2, 11)],
		[FIREWARRIOR_CAMP_SCENE, banchor + Vector2i(9, -7)],
		[TEMPLE_SCENE, banchor + Vector2i(9, 6)],
		[FORESTER_SCENE, banchor + Vector2i(1, 0)],
		[WORKSHOP_SCENE, banchor + Vector2i(16, -12)],
		[FIRERAM_WORKSHOP_SCENE, banchor + Vector2i(16, 0)],
		[AIRSHIP_WHARF_SCENE, banchor + Vector2i(17, 10)],
	], nav)
	# ...three fully manned watchtowers as the front line...
	var towers: Array = [
		[Vector2i(-5, -9), [PREACHER_SCENE, PREACHER_SCENE]],
		[Vector2i(-7, 0), [FIREWARRIOR_SCENE, FIREWARRIOR_SCENE]],
		[Vector2i(-5, 9), [FIREWARRIOR_SCENE, PREACHER_SCENE]],
	]
	for entry in towers:
		var cell: Vector2i = _find_plot(banchor + entry[0], Watchtower.FOOTPRINT, nav)
		if cell.x < 0:
			continue
		var tower: Watchtower = _building_manager.place(
			WATCHTOWER_SCENE, red, cell, 0, true) as Watchtower
		if tower == null:
			continue
		for crew_scene in entry[1]:
			var u: Unit = _unit_manager.spawn_unit(
				crew_scene, red.id, tower.edge_spawn_position())
			if u != null:
				tower.admit_crew(u)
	# ...and everything else BEHIND them (east): site + shaman, two fully
	# manned vehicles of each kind, then the army.
	var rear: Vector2i = center + Vector2i(30, 0)
	var red_site: Building = _place_site_near(red, rear + Vector2i(6, 0))
	_spawn_shaman_near(red, red_site, rear + Vector2i(6, 0), nav)
	var vehicles: Array = [
		[SIEGE_SCENE, Vector2i(0, -8)], [SIEGE_SCENE, Vector2i(0, -4)],
		[FIRE_RAM_SCENE, Vector2i(0, 4)], [FIRE_RAM_SCENE, Vector2i(0, 8)],
		[AIRSHIP_SCENE, Vector2i(3, -11)], [AIRSHIP_SCENE, Vector2i(3, 11)],
	]
	for entry in vehicles:
		var cell: Vector2i = _find_walkable_near(rear + entry[1], nav, 0)
		if cell.x < 0:
			continue
		var vehicle: CrewedVehicle = _unit_manager.spawn_unit(
			entry[0], red.id, nav.cell_to_world(cell)) as CrewedVehicle
		_crew_vehicle_full(vehicle, red.id)
	_spawn_chamber_army(red.id, rear + Vector2i(8, 0), CHAMBER_RED_ARMY, nav)


## Places pre-built buildings from a [scene, anchor] plan; _find_plot searches
## rings around each anchor, so sequential placements avoid overlaps.
func _place_chamber_buildings(tribe: Tribe, plan: Array, nav: NavGrid) -> void:
	for entry in plan:
		var scene: PackedScene = entry[0]
		var probe: Building = scene.instantiate() as Building
		var fp: Vector2i = probe.footprint
		probe.free()
		var c: Vector2i = _find_plot(entry[1], fp, nav)
		if c.x >= 0:
			_building_manager.place(scene, tribe, c, 0, true)


## Spawns and INSTANTLY boards a full firewarrior/preacher crew onto a
## vehicle (test chamber; skips the walk-in).
func _crew_vehicle_full(vehicle: CrewedVehicle, tribe_id: int) -> void:
	if vehicle == null:
		return
	for i in range(vehicle.max_crew):
		var scene: PackedScene = FIREWARRIOR_SCENE if i % 2 == 0 else PREACHER_SCENE
		var u: Unit = _unit_manager.spawn_unit(scene, tribe_id, vehicle.position)
		if u == null:
			continue
		u.order_crew(vehicle)
		vehicle.on_crew_boarded(u)


## Spawns `count` warriors/firewarriors/preachers (round robin) on walkable
## cells around `center` — the red test-chamber army.
func _spawn_chamber_army(tribe_id: int, center: Vector2i, count: int, nav: NavGrid) -> void:
	var kinds: Array = [WARRIOR_SCENE, FIREWARRIOR_SCENE, PREACHER_SCENE]
	var spawned: int = 0
	for radius in range(0, GameState.terrain_data.size / 2):
		for cell in _ring_cells(center, radius):
			if spawned >= count:
				return
			if not nav.is_cell_walkable(cell):
				continue
			if (cell.x + cell.y) % 2 != 0:
				continue  # every other cell, for spacing
			_unit_manager.spawn_unit(kinds[spawned % kinds.size()], tribe_id,
				nav.cell_to_world(cell))
			spawned += 1
	if spawned < count:
		push_warning("Testkammer: nur %d von %d Armee-Einheiten gespawnt (Stamm %d)"
			% [spawned, count, tribe_id])


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
	# Reinforcements per side: 3 zeppelins, 2 catapults, 4 fire rams (all fully
	# crewed) plus 100 extra foot units, spawned in each army's rear.
	_spawn_debug_reinforcements(0, blue_anchor, Vector2i(-1, 0), nav)
	_spawn_debug_reinforcements(1, red_anchor, Vector2i(1, 0), nav)
	# March each army at the enemy anchor (attack-move: combatants engage on
	# contact); the path queue spreads the A* load. Boarded crew (State.CREW) is
	# excluded — order_move() would call leave_crew() and disembark them; the
	# vehicles themselves march (fully crewed) and carry their crew along.
	_tribe_commands.order_move(
		_orderable_units(0), nav.cell_to_world(red_anchor), false, true)
	_tribe_commands.order_move(
		_orderable_units(1), nav.cell_to_world(blue_anchor), false, true)
	print("Debugschlacht: %d Einheiten gesamt" % _unit_manager.units.size())


## All units of a tribe that may receive a march order — excludes boarded crew
## (State.CREW), which would otherwise be pulled off their vehicles by order_move.
func _orderable_units(tribe_id: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in _unit_manager.get_units_of_tribe(tribe_id):
		if u.state != Unit.State.CREW:
			out.append(u)
	return out


## Spawns a side's reinforcements in the army's rear (dir points away from the
## island centre): fully crewed zeppelins/catapults/fire rams plus a mixed foot
## army. Vehicles get well-spread offsets so their boards don't overlap.
func _spawn_debug_reinforcements(tribe_id: int, anchor: Vector2i, dir: Vector2i,
		nav: NavGrid) -> void:
	var rear: Vector2i = anchor + dir * DEBUG_REAR_OFFSET
	var plan: Array = []
	for i in range(DEBUG_ZEPPELINS):
		plan.append([AIRSHIP_SCENE, Vector2i(0, -18 + i * 6)])
	for i in range(DEBUG_CATAPULTS):
		plan.append([SIEGE_SCENE, Vector2i(dir.x * 6, -4 + i * 8)])
	for i in range(DEBUG_FIRERAMS):
		plan.append([FIRE_RAM_SCENE, Vector2i(dir.x * 6, 8 + i * 5)])
	for entry in plan:
		var cell: Vector2i = _find_walkable_near(rear + entry[1], nav, 0)
		if cell.x < 0:
			continue
		var vehicle: CrewedVehicle = _unit_manager.spawn_unit(
			entry[0], tribe_id, nav.cell_to_world(cell)) as CrewedVehicle
		_crew_vehicle_full(vehicle, tribe_id)
	# 100 extra foot units (brave/warrior/firewarrior/preacher mix).
	_spawn_debug_extra_army(tribe_id, rear + dir * 4, DEBUG_EXTRA_ARMY, nav)


## Fills walkable cells ring by ring around the anchor with a brave/warrior/
## firewarrior/preacher round robin — the debug-battle reinforcement army.
func _spawn_debug_extra_army(tribe_id: int, center: Vector2i, count: int,
		nav: NavGrid) -> void:
	var kinds: Array = [BRAVE_SCENE, WARRIOR_SCENE, FIREWARRIOR_SCENE, PREACHER_SCENE]
	var spawned: int = 0
	for radius in range(0, 40):
		for cell in _ring_cells(center, radius):
			if spawned >= count:
				return
			if not nav.is_cell_walkable(cell):
				continue
			_unit_manager.spawn_unit(kinds[spawned % kinds.size()], tribe_id,
				nav.cell_to_world(cell))
			spawned += 1
	if spawned < count:
		push_warning("Debugschlacht: nur %d von %d Verstärkungen (Stamm %d)"
			% [spawned, count, tribe_id])


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


# --- Stress-test match (main menu, phase 8.2 follow-up) ---------------------------

## Four armies on the compass points around the island centre: 1000 foot units
## each (warriors/firewarriors/preachers), six crewed catapults behind the
## lines and a shaman with FULL spell charges. Tribe 0 (south, camera start)
## stays player-controllable; the march + spell barrage is driven by
## _tick_stress_match. Returns the player anchor.
func _setup_stress_match(nav: NavGrid) -> Vector2i:
	var td: TerrainData = GameState.terrain_data
	var center: Vector2i = Vector2i(td.size / 2, td.size / 2)
	var offsets: Array[Vector2i] = [
		Vector2i(0, STRESS_MATCH_OFFSET), Vector2i(0, -STRESS_MATCH_OFFSET),
		Vector2i(-STRESS_MATCH_OFFSET, 0), Vector2i(STRESS_MATCH_OFFSET, 0)]
	for i in range(mini(offsets.size(), GameState.tribes.size())):
		var anchor: Vector2i = center + offsets[i]
		var back: Vector2i = Vector2i(signi(offsets[i].x), signi(offsets[i].y))
		_spawn_stress_match_army(i, anchor, nav)
		_spawn_stress_match_sieges(i, anchor, back, nav)
		_spawn_debug_shaman(i, anchor + back * 8, nav)   # rear, full charges
	_stress_match = true
	_stress_match_timer = STRESS_MATCH_IDLE_DELAY
	_stress_cast_timer = STRESS_MATCH_IDLE_DELAY
	print("Stresstest: %d Einheiten gesamt — Abmarsch in %.0f s" % [
		_unit_manager.units.size(), STRESS_MATCH_IDLE_DELAY])
	return center + offsets[0]


## Ring-fills one army around its anchor: warriors first (front rings), then
## firewarriors, preachers last (rear rings).
func _spawn_stress_match_army(tribe_id: int, anchor: Vector2i, nav: NavGrid) -> void:
	var warriors: int = int(float(STRESS_MATCH_ARMY) * STRESS_MATCH_WARRIOR_SHARE)
	var firewarriors: int = int(float(STRESS_MATCH_ARMY) * STRESS_MATCH_FW_SHARE)
	var spawned: int = 0
	for radius in range(0, 40):
		for cell in _ring_cells(anchor, radius):
			if spawned >= STRESS_MATCH_ARMY:
				return
			if not nav.is_cell_walkable(cell):
				continue
			var scene: PackedScene = WARRIOR_SCENE
			if spawned >= warriors + firewarriors:
				scene = PREACHER_SCENE
			elif spawned >= warriors:
				scene = FIREWARRIOR_SCENE
			if _unit_manager.spawn_unit(scene, tribe_id, nav.cell_to_world(cell)) == null:
				return   # 1500-per-tribe hard cap
			spawned += 1
	if spawned < STRESS_MATCH_ARMY:
		push_warning("Stresstest: nur %d von %d Einheiten für Stamm %d gespawnt"
			% [spawned, STRESS_MATCH_ARMY, tribe_id])


## Six catapults per army in a line behind the anchor (outward side), each
## crewed by three braves spawned right next to it (they board immediately).
func _spawn_stress_match_sieges(tribe_id: int, anchor: Vector2i, back: Vector2i,
		nav: NavGrid) -> void:
	var side: Vector2i = Vector2i(-back.y, back.x)
	for k in range(STRESS_MATCH_SIEGE):
		@warning_ignore("integer_division")
		var wish: Vector2i = anchor + back * 12 + side * ((k - STRESS_MATCH_SIEGE / 2) * 4)
		var cell: Vector2i = _find_walkable_near(wish, nav, 0)
		if cell.x < 0:
			continue
		var engine: Unit = _unit_manager.spawn_unit(
			SIEGE_SCENE, tribe_id, nav.cell_to_world(cell))
		if engine == null:
			return
		for c in range(STRESS_MATCH_SIEGE_CREW):
			var crew_cell: Vector2i = _find_walkable_near(cell, nav, c + 1)
			if crew_cell.x < 0:
				continue
			var brave: Unit = _unit_manager.spawn_unit(
				BRAVE_SCENE, tribe_id, nav.cell_to_world(crew_cell))
			if brave != null:
				brave.order_crew(engine)


## Stress-match driver (called from _physics_process): after the idle delay
## every army attack-moves at the island centre ONCE (combat takes over on
## contact), then the shamans cast on a rolling timer — one spell per tribe
## per interval, cycling STRESS_MATCH_SPELLS, charges refilled (sandbox).
func _tick_stress_match(delta: float) -> void:
	var nav: NavGrid = GameState.nav_grid
	var td: TerrainData = GameState.terrain_data
	if nav == null or td == null:
		return
	var center: Vector3 = nav.cell_to_world(Vector2i(td.size / 2, td.size / 2))
	if not _stress_match_marched:
		_stress_match_timer -= delta
		if _stress_match_timer > 0.0:
			return
		_stress_match_marched = true
		for tribe in GameState.tribes:
			var squad: Array[Unit] = []
			for u in tribe.units:
				if not is_instance_valid(u) or u.state == Unit.State.DEAD:
					continue
				if u.unit_kind() == &"brave":
					continue   # the catapult crews stay on their engines
				squad.append(u)
			if not squad.is_empty():
				_tribe_commands.order_move(squad, center, false, true)   # attack-move
		print("Stresstest: Angriffsbefehl — alle Armeen marschieren zur Mitte")
		return
	_stress_cast_timer -= delta
	if _stress_cast_timer > 0.0:
		return
	_stress_cast_timer = STRESS_MATCH_CAST_INTERVAL
	for tribe in GameState.tribes:
		var shaman: Unit = tribe.shaman
		if shaman == null or not is_instance_valid(shaman) \
				or shaman.state == Unit.State.DEAD or shaman.state == Unit.State.CAST:
			continue
		var spell_id: StringName = STRESS_MATCH_SPELLS[
			_stress_spell_index % STRESS_MATCH_SPELLS.size()]
		_stress_spell_index += 1
		var spell: Spell = tribe.get_spell(spell_id)
		if spell == null:
			continue
		spell.charges = maxi(spell.charges, 1)   # sandbox: the barrage never dries up
		_tribe_commands.cast_spell(tribe, spell_id,
			_stress_spell_target(tribe, shaman, center))


## Cast point: the nearest enemy around the shaman (the barrage lands where
## the fighting is); before contact the island centre is the fallback.
func _stress_spell_target(tribe: Tribe, shaman: Unit, fallback: Vector3) -> Vector3:
	var best: Unit = null
	var best_d: float = INF
	for u in _unit_manager.get_enemy_candidates(shaman.position, 30.0, tribe.id, 8):
		var d: float = shaman.position.distance_squared_to(u.position)
		if d < best_d:
			best_d = d
			best = u
	if best != null:
		return best.position
	return fallback


## Ring-searches outward from `center` for the first buildable footprint.
func _find_plot(center: Vector2i, footprint: Vector2i, _nav: NavGrid) -> Vector2i:
	for radius in range(0, GameState.terrain_data.size / 2):
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
## At 1x the cap returns to the project default of 2 (phase 8: no catch-up
## death spiral in mass battles — overload degrades into slight slow motion).
func _cycle_time_scale() -> void:
	_time_scale_index = (_time_scale_index + 1) % TIME_SCALE_STEPS.size()
	var factor: float = TIME_SCALE_STEPS[_time_scale_index]
	Engine.time_scale = factor
	Engine.max_physics_steps_per_frame = 2 if factor <= 1.0 \
		else clampi(int(factor) * 4, 8, 120)
	print("Zeitraffer: %dx" % int(factor))


# --- Stress test (F9) ----------------------------------------------------------

## Queues STRESS_BATCH_TOTAL braves split over the tribes; _physics_process
## spawns them staggered over frames (tribes at their 1500 hard cap simply
## stop accepting spawns).
func _queue_stress_batch() -> void:
	var tribe_count: int = maxi(1, GameState.tribes.size())
	var per_tribe: int = int(ceil(float(STRESS_BATCH_TOTAL) / float(tribe_count)))
	for tribe_id in range(tribe_count):
		for i in range(per_tribe):
			_stress_pending.append(tribe_id)
	print("Stresstest: %d Einheiten in Warteschlange (gesamt danach: %d)" % [
		_stress_pending.size(), _unit_manager.units.size() + _stress_pending.size()])


func _physics_process(delta: float) -> void:
	if _stress_match:
		_tick_stress_match(delta)
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
	var anchor: Vector2i = _stress_anchor(tribe_id)
	for attempt in range(24):
		var cell: Vector2i = anchor + Vector2i(
			_stress_rng.randi_range(-18, 18), _stress_rng.randi_range(-18, 18))
		if nav.is_cell_walkable(cell):
			_unit_manager.spawn_unit(BRAVE_SCENE, tribe_id, nav.cell_to_world(cell))
			return


## Stress-spawn quadrant anchor per tribe, scaled to the map size (the old
## fixed island coordinates missed the 256 maps).
func _stress_anchor(tribe_id: int) -> Vector2i:
	var s: int = GameState.terrain_data.size
	var lo: int = int(float(s) * 0.34)
	var hi: int = int(float(s) * 0.66)
	match tribe_id % 4:
		0: return Vector2i(lo, lo)
		1: return Vector2i(hi, lo)
		2: return Vector2i(lo, hi)
		_: return Vector2i(hi, hi)


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
