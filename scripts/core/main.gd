extends Node3D

## Root of the main scene. Creates the TerrainData (fixed seed), builds the
## Terrain, creates the NavGrid, positions the camera over the island and
## spawns the starting units. Must be headless-robust: no viewport-texture
## access in _ready().

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const SITE_SCENE: PackedScene = preload("res://scenes/buildings/reincarnation_site.tscn")
const START_BRAVES: int = 10
const TREE_COUNT: int = 60

## Debug: spawn a small marker at the terrain raycast hit on left-click, to
## verify the HeightMapShape3D offset (marker must sit exactly under the cursor).
@export var debug_click_marker: bool = false

@onready var _terrain: Terrain = $Terrain
@onready var _camera_rig: CameraRig = $CameraRig
@onready var _unit_manager: UnitManager = $UnitManager
@onready var _building_manager: BuildingManager = $BuildingManager
@onready var _tree_manager: TreeManager = $TreeManager
@onready var _wood_pile_manager: WoodPileManager = $WoodPileManager
@onready var _tribe_commands: TribeCommands = $TribeCommands
@onready var _selection: SelectionManager = $UI/SelectionManager
@onready var _hud: Hud = $UI/Hud
@onready var _build_menu: BuildMenu = $UI/BuildMenu
@onready var _route_visualizer: RouteVisualizer = $RouteVisualizer

var _marker: MeshInstance3D = null


func _ready() -> void:
	var td: TerrainData = TerrainData.new()
	td.generate_island(GameState.ISLAND_SEED)
	GameState.terrain_data = td
	GameState.terrain = _terrain

	_terrain.build(td)

	var nav: NavGrid = NavGrid.new(td)
	GameState.nav_grid = nav

	# Tribes: 0 = player (blue), 1 = AI (red) — identical instances.
	var tribes: Array[Tribe] = []
	for i in range(2):
		tribes.append(Tribe.new(i, Unit.TRIBE_COLORS[i]))
	GameState.tribes = tribes

	_unit_manager.setup(td, nav, tribes, _tree_manager, _wood_pile_manager)
	_building_manager.setup(td, nav, _unit_manager, _wood_pile_manager)
	_tree_manager.setup(td, nav)
	_wood_pile_manager.setup(td)
	_tribe_commands.setup(nav, _building_manager, _unit_manager, _tree_manager)
	_selection.setup(_unit_manager, _tribe_commands, _build_menu)
	_build_menu.setup(_tribe_commands, nav, self, tribes[GameState.PLAYER_TRIBE])
	_hud.setup(tribes[GameState.PLAYER_TRIBE], _wood_pile_manager.total_wood())
	_route_visualizer.setup(_selection, td)

	# Terrain deformations (foundation flattening, later Landbridge) rebuild
	# the affected mesh chunks + collision here.
	Events.terrain_deformed.connect(_terrain.apply_deformation)

	_tree_manager.spawn_trees(TREE_COUNT, GameState.ISLAND_SEED)
	_place_start_site(tribes[GameState.PLAYER_TRIBE], nav)
	_spawn_start_units(td, nav)

	# Start the camera over the island centre.
	var center: float = TerrainData.SIZE * 0.5
	_camera_rig.global_position = Vector3(center, td.get_height(center, center), center)


## Pre-places the player's reincarnation site (free, fully built) on the first
## valid footprint near the island centre.
func _place_start_site(tribe: Tribe, nav: NavGrid) -> void:
	var fp: Vector2i = ReincarnationSite.FOOTPRINT
	var center: Vector2i = Vector2i(TerrainData.SIZE / 2 + 6, TerrainData.SIZE / 2)
	for radius in range(0, TerrainData.SIZE / 2):
		for cell in _ring_cells(center, radius):
			if _tribe_commands.can_place_at(cell, fp):
				_building_manager.place(SITE_SCENE, tribe, cell, 0, true)
				return
	push_warning("No valid spot for the start reincarnation site found")


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
	if not debug_click_marker:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_place_debug_marker(event.position)


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
