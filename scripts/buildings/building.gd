class_name Building extends Node3D

## Base class for all buildings (Hut, training camps, Temple, Reincarnation
## Site). Placement runs through TribeCommands.place_building() ->
## BuildingManager.place(); the footprint cells are blocked in the NavGrid and
## freed again on destruction.
##
## Buildings start under construction; braves in the BUILD state drive
## build_progress to 1.0 via add_build_progress(). Gameplay logic lives in
## tick(delta) (driven by the BuildingManager) so tests can tick manually.
## Uses local `position` like Unit: buildings are direct children of the
## BuildingManager at the origin.

signal construction_finished(building: Building)
signal destroyed(building: Building)

var tribe_id: int = 0
var tribe: Tribe = null
var max_health: int = 300
var health: int = 300
var wood_cost: int = 20
var footprint: Vector2i = Vector2i(2, 2)   # cells
var cell: Vector2i = Vector2i.ZERO         # top-left footprint cell
var rally_point: Vector3 = Vector3.ZERO
var under_construction: bool = true
var build_progress: float = 0.0            # 0..1

## Injected by BuildingManager.place() (or directly by tests).
var terrain_data: TerrainData = null
var nav_grid: NavGrid = null
var unit_manager: UnitManager = null

var _mesh_root: Node3D = null


## German display name, overridden by subclasses (UI language is German).
func display_name() -> String:
	return "Gebäude"


## Housing capacity this building contributes (Hut overrides this).
func housing_capacity() -> int:
	return 0


func footprint_rect() -> Rect2i:
	return Rect2i(cell, footprint)


## World-space centre of the footprint, Y from the terrain.
func center_world() -> Vector3:
	var wx: float = (float(cell.x) + float(footprint.x) * 0.5) * TerrainData.CELL_SIZE
	var wz: float = (float(cell.y) + float(footprint.y) * 0.5) * TerrainData.CELL_SIZE
	var wy: float = terrain_data.get_height(wx, wz) if terrain_data != null else 0.0
	return Vector3(wx, wy, wz)


## Radius (from the centre) at which a unit counts as "at the building".
func interact_range() -> float:
	return float(maxi(footprint.x, footprint.y)) * 0.5 * TerrainData.CELL_SIZE + 1.6


## Walkable world position on the footprint edge (for spawning trained/new
## units). Falls back to the south edge when no NavGrid is available.
func edge_spawn_position() -> Vector3:
	if nav_grid != null:
		var rect: Rect2i = footprint_rect().grow(1)
		for z in range(rect.position.y, rect.position.y + rect.size.y):
			for x in range(rect.position.x, rect.position.x + rect.size.x):
				var c: Vector2i = Vector2i(x, z)
				if footprint_rect().has_point(c):
					continue  # perimeter only
				if nav_grid.is_cell_walkable(c):
					return nav_grid.cell_to_world(c)
	return center_world() + Vector3(0.0, 0.0, float(footprint.y) * 0.5 + 1.0)


func _ready() -> void:
	_create_visuals()
	_create_click_body()
	_update_construction_visual()


# --- Gameplay tick (driven by BuildingManager) -----------------------------------

func tick(delta: float) -> void:
	if under_construction:
		return
	_tick_active(delta)


## Subclass logic while the building is operational.
func _tick_active(_delta: float) -> void:
	pass


# --- Construction ------------------------------------------------------------------

func add_build_progress(amount: float) -> void:
	if not under_construction:
		return
	build_progress = clampf(build_progress + amount, 0.0, 1.0)
	_update_construction_visual()
	if build_progress >= 1.0:
		finish_construction()


func finish_construction() -> void:
	if not under_construction:
		return
	under_construction = false
	build_progress = 1.0
	_update_construction_visual()
	construction_finished.emit(self)
	if tribe != null:
		tribe.notify_housing_changed()


# --- Damage / destruction ------------------------------------------------------------

func take_damage(amount: int) -> void:
	if health <= 0:
		return
	health -= amount
	if health <= 0:
		health = 0
		destroy()


## Frees the NavGrid footprint, deregisters from the tribe and removes the node.
func destroy() -> void:
	if nav_grid != null:
		nav_grid.fill_solid_region(footprint_rect(), false)
	if tribe != null:
		tribe.remove_building(self)
	destroyed.emit(self)
	if is_inside_tree():
		var events: Node = get_node_or_null("/root/Events")
		if events != null:
			events.building_destroyed.emit(self)
		queue_free()


# --- Visuals (placeholder meshes, created in _ready only) ----------------------------

## Subclasses build their placeholder meshes under _mesh_root.
func _create_visuals() -> void:
	_mesh_root = Node3D.new()
	_mesh_root.name = "MeshRoot"
	add_child(_mesh_root)


## Small tribe-coloured flag next to the building.
func _add_flag() -> void:
	if _mesh_root == null:
		return
	var pole: MeshInstance3D = MeshInstance3D.new()
	var pole_mesh: CylinderMesh = CylinderMesh.new()
	pole_mesh.top_radius = 0.05
	pole_mesh.bottom_radius = 0.05
	pole_mesh.height = 2.4
	pole.mesh = pole_mesh
	pole.position = Vector3(float(footprint.x) * 0.5 - 0.2, 1.2, float(footprint.y) * 0.5 - 0.2)
	_mesh_root.add_child(pole)
	var flag: MeshInstance3D = MeshInstance3D.new()
	var flag_mesh: BoxMesh = BoxMesh.new()
	flag_mesh.size = Vector3(0.7, 0.4, 0.05)
	flag.mesh = flag_mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Unit.TRIBE_COLORS[tribe_id % Unit.TRIBE_COLORS.size()]
	flag.material_override = mat
	flag.position = pole.position + Vector3(0.35, 1.0, 0.0)
	_mesh_root.add_child(flag)


func _make_material(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	return mat


## StaticBody3D + BoxShape3D on layer 2 for mouse-ray selection/targeting.
func _create_click_body() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "ClickBody"
	body.collision_layer = 2
	body.collision_mask = 0
	body.set_meta("building", self)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(float(footprint.x), 2.5, float(footprint.y))
	shape.shape = box
	shape.position.y = 1.25
	body.add_child(shape)
	add_child(body)


## Construction sites are shown squashed; the mesh grows with the progress.
func _update_construction_visual() -> void:
	if _mesh_root == null:
		return
	var s: float = 1.0 if not under_construction else 0.15 + 0.85 * build_progress
	_mesh_root.scale = Vector3(1.0, maxf(s, 0.05), 1.0)
