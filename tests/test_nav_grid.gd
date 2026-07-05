extends TestBase

## Headless tests for NavGrid (pathfinding, water snapping, landbridge
## walkability updates and building footprints).


## All vertices at the same height above sea level -> every cell walkable.
func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


## Land at 5.0 with a gentle valley along x = 64 whose floor lies below sea
## level -> a water strip splits the map into two landmasses. Slopes stay
## below MAX_SLOPE so a raise_area() can open a walkable corridor.
func _valley_terrain() -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for vz in range(TerrainData.VERTS):
		for vx in range(TerrainData.VERTS):
			var dx: float = absf(float(vx) - 64.0)
			var h: float = 5.0 - 0.5 * maxf(0.0, 10.0 - dx)
			td.heights[vz * TerrainData.VERTS + vx] = h
	return td


func test_path_between_land_cells() -> void:
	var td: TerrainData = _flat_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var path: PackedVector3Array = nav.find_path(Vector3(10.5, 0, 10.5), Vector3(50.5, 0, 30.5))
	check(path.size() > 0, "flat terrain: path between two land cells exists")
	var all_walkable: bool = true
	for p in path:
		if not td.is_walkable(nav.world_to_cell(p)):
			all_walkable = false
			break
	check(all_walkable, "flat terrain: every path cell is walkable")
	check(nav.world_to_cell(path[path.size() - 1]) == Vector2i(50, 30),
		"flat terrain: path ends at the target cell")


func test_water_target_snaps_to_shore() -> void:
	var td: TerrainData = _flat_terrain()
	# Dig a pond: vertices 90..110 down to 0 -> cells inside are below sea
	# level, the rim cells are too steep. Both unwalkable.
	for vz in range(90, 111):
		for vx in range(90, 111):
			td.heights[vz * TerrainData.VERTS + vx] = 0.0
	var nav: NavGrid = NavGrid.new(td)
	check(not td.is_walkable(Vector2i(100, 100)), "pond centre is not walkable")
	var path: PackedVector3Array = nav.find_path(Vector3(20.5, 0, 20.5), Vector3(100.5, 0, 100.5))
	check(path.size() > 0, "water target: path is not empty")
	if path.size() > 0:
		var last_cell: Vector2i = nav.world_to_cell(path[path.size() - 1])
		check(td.is_walkable(last_cell), "water target: path ends on a walkable cell")
		var dist: float = Vector2(last_cell - Vector2i(100, 100)).length()
		check(dist <= 20.0, "water target: end cell is near the pond (dist %f)" % dist)


func test_landbridge_connects_landmasses() -> void:
	var td: TerrainData = _valley_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var west: Vector3 = Vector3(30.5, 0, 64.5)
	var east: Vector3 = Vector3(100.5, 0, 64.5)
	check(td.is_walkable(Vector2i(30, 64)), "west landmass is walkable")
	check(td.is_walkable(Vector2i(100, 64)), "east landmass is walkable")
	var path: PackedVector3Array = nav.find_path(west, east)
	check(path.is_empty(), "valley: no path across the water strip")

	# Landbridge: raise the valley centre, then update only the changed rect.
	var rect: Rect2i = td.raise_area(Vector2(64.0, 64.0), 12.0, 3.0)
	check(rect.size.x > 0 and rect.size.y > 0, "raise_area returns a non-empty rect")
	nav.update_region(rect)
	path = nav.find_path(west, east)
	check(path.size() > 0, "valley: path exists after landbridge + update_region")
	if path.size() > 0:
		check(nav.world_to_cell(path[path.size() - 1]) == Vector2i(100, 64),
			"valley: path reaches the east landmass")


func test_fill_solid_region_blocks_and_unblocks() -> void:
	var td: TerrainData = _flat_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var wall: Rect2i = Rect2i(64, 30, 1, 68)  # wall at x=64, z rows 30..97
	nav.fill_solid_region(wall, true)
	var from: Vector3 = Vector3(40.5, 0, 64.5)
	var to: Vector3 = Vector3(90.5, 0, 64.5)
	var path: PackedVector3Array = nav.find_path(from, to)
	check(path.size() > 0, "solid wall: detour path exists")
	var crosses_wall: bool = false
	for p in path:
		if wall.has_point(nav.world_to_cell(p)):
			crosses_wall = true
			break
	check(not crosses_wall, "solid wall: path avoids the blocked cells")

	nav.fill_solid_region(wall, false)
	path = nav.find_path(from, to)
	check(path.size() > 0, "wall removed: path exists")
	crosses_wall = false
	for p in path:
		if wall.has_point(nav.world_to_cell(p)):
			crosses_wall = true
			break
	check(crosses_wall, "wall removed: direct path passes through the region again")
