class_name BuildingManager extends Node

## Registry for all buildings (child of Main) and the low-level placement
## used by TribeCommands.place_building(). Drives the building ticks from
## _physics_process (tests call tick() manually) and recruits idle braves as
## workers for construction sites (only braves without any other task/order
## help; max Building.MAX_WORKERS per site).

const RECRUIT_RADIUS: float = 30.0
const RECRUIT_INTERVAL: float = 1.0

var terrain_data: TerrainData = null
var nav_grid: NavGrid = null
var unit_manager: UnitManager = null
var wood_pile_manager: WoodPileManager = null

var buildings: Array[Building] = []
var _recruit_timer: float = RECRUIT_INTERVAL


func setup(p_terrain_data: TerrainData, p_nav_grid: NavGrid,
		p_unit_manager: UnitManager, p_wood_pile_manager: WoodPileManager = null) -> void:
	terrain_data = p_terrain_data
	nav_grid = p_nav_grid
	unit_manager = p_unit_manager
	wood_pile_manager = p_wood_pile_manager


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	# Iterate a snapshot: a building demolished by raiders (phase 7g) destroys
	# itself mid-tick and erases from `buildings`, which would otherwise skip an
	# element.
	for building in buildings.duplicate():
		if is_instance_valid(building):
			building.tick(delta)
	_recruit_timer -= delta
	if _recruit_timer <= 0.0:
		_recruit_timer += RECRUIT_INTERVAL
		_recruit_workers()


## Instantiates and registers a building at a footprint top-left cell.
## Validation happens in TribeCommands — this only executes the placement.
## pre_built skips the flatten/wood phases (used for the start sites).
func place(scene: PackedScene, tribe: Tribe, cell: Vector2i,
		orientation: int = 0, pre_built: bool = false) -> Building:
	var building: Building = scene.instantiate() as Building
	if building == null:
		return null
	building.tribe_id = tribe.id
	building.terrain_data = terrain_data
	building.nav_grid = nav_grid
	building.unit_manager = unit_manager
	building.wood_pile_manager = wood_pile_manager
	building.cell = cell
	building.orientation = orientation
	# Non-square footprints (workshop 8x4) turn with the entrance side: the
	# mesh root is rotated by the orientation, so the blocked cells must
	# follow. A no-op for the square buildings.
	if orientation % 2 == 1:
		building.footprint = Vector2i(building.footprint.y, building.footprint.x)
	building.position = _placement_position(building)
	add_child(building)
	register(building, tribe)
	if nav_grid != null:
		nav_grid.fill_solid_region(building.footprint_rect(), true)
	building.rally_point = _default_rally_point(building)
	if pre_built:
		building.finish_construction()
	else:
		building.init_construction()
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


## Sends idle braves of the owning tribe to under-construction sites nearby.
## Iterates the OWNING tribe's units instead of a 30-m radius query (phase 8):
## the uncapped query walked ~225 hash buckets and built an array of every
## unit near the base per site per second.
func _recruit_workers() -> void:
	if unit_manager == null:
		return
	for building in buildings:
		if not building.under_construction:
			continue
		if building.wood_stalled:
			continue  # waiting for new wood (re-checked on an interval)
		if building.workers.size() >= Building.MAX_WORKERS:
			continue
		if building.tribe == null:
			continue
		var center: Vector3 = building.center_world()
		var flat: Vector2 = Vector2(center.x, center.z)
		for unit in building.tribe.units:
			if building.workers.size() >= Building.MAX_WORKERS:
				break
			if not is_instance_valid(unit) or not (unit is Brave) \
					or unit.state != Unit.State.IDLE:
				continue
			if Vector2(unit.position.x, unit.position.z).distance_to(flat) \
					<= RECRUIT_RADIUS:
				(unit as Brave).order_build(building)


func _placement_position(building: Building) -> Vector3:
	var wx: float = (float(building.cell.x) + float(building.footprint.x) * 0.5) * TerrainData.CELL_SIZE
	var wz: float = (float(building.cell.y) + float(building.footprint.y) * 0.5) * TerrainData.CELL_SIZE
	var wy: float = terrain_data.get_height(wx, wz) if terrain_data != null else 0.0
	return Vector3(wx, wy, wz)


## Default rally point: walkable cell at (or near) the entrance.
func _default_rally_point(building: Building) -> Vector3:
	if nav_grid != null:
		var c: Vector2i = nav_grid.nearest_walkable_cell(building.entrance_cell())
		if c.x >= 0:
			return nav_grid.cell_to_world(c)
	return building.entrance_world()
