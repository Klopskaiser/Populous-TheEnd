class_name BuildingManager extends Node

## Registry for all buildings (child of Main) and the low-level placement
## used by TribeCommands.place_building(). Drives the building ticks from
## _physics_process (tests call tick() manually).

var terrain_data: TerrainData = null
var nav_grid: NavGrid = null
var unit_manager: UnitManager = null

var buildings: Array[Building] = []


func setup(p_terrain_data: TerrainData, p_nav_grid: NavGrid, p_unit_manager: UnitManager) -> void:
	terrain_data = p_terrain_data
	nav_grid = p_nav_grid
	unit_manager = p_unit_manager


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	for building in buildings:
		building.tick(delta)


## Instantiates and registers a building at a footprint top-left cell.
## Validation (cost, walkability) happens in TribeCommands — this only
## executes the placement. pre_built skips the construction phase (used for
## the start reincarnation sites).
func place(scene: PackedScene, tribe: Tribe, cell: Vector2i, pre_built: bool = false) -> Building:
	var building: Building = scene.instantiate() as Building
	if building == null:
		return null
	building.tribe_id = tribe.id
	building.terrain_data = terrain_data
	building.nav_grid = nav_grid
	building.unit_manager = unit_manager
	building.cell = cell
	building.position = _placement_position(building)
	add_child(building)
	register(building, tribe)
	if nav_grid != null:
		nav_grid.fill_solid_region(building.footprint_rect(), true)
	building.rally_point = _default_rally_point(building)
	if pre_built:
		building.finish_construction()
	return building


func register(building: Building, tribe: Tribe) -> void:
	if building in buildings:
		return
	buildings.append(building)
	tribe.add_building(building)
	building.destroyed.connect(_on_building_destroyed)


func get_buildings_of_tribe(tribe_id: int) -> Array[Building]:
	var result: Array[Building] = []
	for building in buildings:
		if building.tribe_id == tribe_id:
			result.append(building)
	return result


func _on_building_destroyed(building: Building) -> void:
	buildings.erase(building)


func _placement_position(building: Building) -> Vector3:
	var wx: float = (float(building.cell.x) + float(building.footprint.x) * 0.5) * TerrainData.CELL_SIZE
	var wz: float = (float(building.cell.y) + float(building.footprint.y) * 0.5) * TerrainData.CELL_SIZE
	var wy: float = terrain_data.get_height(wx, wz) if terrain_data != null else 0.0
	return Vector3(wx, wy, wz)


## Default rally point: walkable cell south of the footprint.
func _default_rally_point(building: Building) -> Vector3:
	var south: Vector2i = building.cell + Vector2i(building.footprint.x / 2, building.footprint.y + 1)
	if nav_grid != null:
		var c: Vector2i = nav_grid.nearest_walkable_cell(south)
		if c.x >= 0:
			return nav_grid.cell_to_world(c)
	return building.center_world() + Vector3(0.0, 0.0, float(building.footprint.y) * 0.5 + 1.5)
