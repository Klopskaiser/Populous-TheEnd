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
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")
const PREACHER_SCENE: PackedScene = preload("res://scenes/units/preacher.tscn")
const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")
const START_BRAVES: int = 20
const TREE_COUNT: int = 60
## Max player count — one tribe per player, all identical instances.
const TRIBE_COUNT: int = 4

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

var _marker: MeshInstance3D = null
var _stress_pending: Array[int] = []   # tribe ids of queued stress spawns
var _stress_rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	var td: TerrainData = TerrainData.new()
	td.generate_island(GameState.ISLAND_SEED)
	GameState.terrain_data = td
	GameState.terrain = _terrain

	_terrain.build(td)

	var nav: NavGrid = NavGrid.new(td)
	GameState.nav_grid = nav

	# Tribes: 0 = player (blue), 1-3 = AI — identical instances (max 4 players).
	var tribes: Array[Tribe] = []
	for i in range(TRIBE_COUNT):
		tribes.append(Tribe.new(i, Unit.TRIBE_COLORS[i]))
	GameState.tribes = tribes
	_stress_rng.seed = GameState.ISLAND_SEED

	_unit_manager.setup(td, nav, tribes, _tree_manager, _wood_pile_manager)
	_unit_manager.unit_renderer = _unit_renderer
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
		# Start scenario: every spell begins with one stored charge.
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
	var combat_audio: CombatAudio = CombatAudio.new()
	combat_audio.name = "CombatAudio"
	add_child(combat_audio)

	# Terrain deformations (foundation flattening, later Landbridge) rebuild
	# the affected mesh chunks + collision here.
	Events.terrain_deformed.connect(_terrain.apply_deformation)

	if GameState.debug_battle:
		# Debug battle (one-shot flag from the pause menu): no bases, no start
		# braves — just two armies marching at each other.
		GameState.debug_battle = false
		_tree_manager.spawn_trees(TREE_COUNT, GameState.ISLAND_SEED)
		_setup_debug_battle(nav)
	else:
		_tree_manager.spawn_trees(TREE_COUNT, GameState.ISLAND_SEED)
		_place_start_site(tribes[GameState.PLAYER_TRIBE], nav)
		_setup_player_base(tribes[GameState.PLAYER_TRIBE], nav)
		_spawn_start_units(td, nav)
		_setup_sparring(tribes, nav)

	# Start the camera over the island centre.
	var center: float = TerrainData.SIZE * 0.5
	_camera_rig.global_position = Vector3(center, td.get_height(center, center), center)


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


## Spawns the starting Braves (player tribe) on walkable cells near the island
## centre, spread out via a spiral ring search.
func _spawn_start_units(td: TerrainData, nav: NavGrid) -> void:
	var center: Vector2i = Vector2i(TerrainData.SIZE / 2, TerrainData.SIZE / 2)
	var spawned: int = 0
	for radius in range(0, TerrainData.SIZE / 2):
		for cell in _ring_cells(center, radius):
			if spawned >= START_BRAVES:
				return
			if not nav.is_cell_walkable(cell):
				continue
			if (cell.x + cell.y) % 2 != 0:
				continue  # every other cell, for spacing
			_unit_manager.spawn_unit(BRAVE_SCENE, GameState.PLAYER_TRIBE, nav.cell_to_world(cell))
			spawned += 1
	if spawned < START_BRAVES:
		push_warning("Only %d of %d start braves spawned" % [spawned, START_BRAVES])


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
	# March each army at the enemy anchor; the path queue spreads the A* load.
	_tribe_commands.order_move(
		_unit_manager.get_units_of_tribe(0), nav.cell_to_world(red_anchor))
	_tribe_commands.order_move(
		_unit_manager.get_units_of_tribe(1), nav.cell_to_world(blue_anchor))
	print("Debugschlacht: %d Einheiten gesamt" % _unit_manager.units.size())


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
	if not debug_click_marker:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_place_debug_marker(event.position)


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
