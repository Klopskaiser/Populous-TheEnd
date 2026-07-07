extends TestBase

## Phase 7i: skirmish map registry + the three new maps. Verifies variable
## terrain size, per-map anchors (walkable + mutually reachable), and the
## defining terrain features (central lake, mountain ridge with passes,
## hard-edged plateaus with a ramp).

const SEED: int = 1337


func test_variable_terrain_size() -> void:
	var small: TerrainData = TerrainData.new()
	check(small.size == TerrainData.SIZE and small.verts == TerrainData.SIZE + 1,
		"default TerrainData is the 128 map")
	var big: TerrainData = TerrainData.new(256)
	check(big.size == 256 and big.verts == 257, "256 map has 257 verts")
	check(big.heights.size() == 257 * 257, "heightmap resized for the big map")
	# Height access at the far edge of the big map must be in bounds.
	big.set_vertex_height(256, 256, 12.0)
	check_near(big.get_height(256.0, 256.0), 12.0, "far-corner height on the big map")


func test_registry_sizes_and_mask() -> void:
	check(MapGenerator.map_size("island") == 128, "island is standard size")
	check(MapGenerator.map_size("plateau") == 128, "plateau is standard size")
	check(MapGenerator.map_size("seenland") == 256, "seenland is twice as big")
	check(MapGenerator.map_size("bergpass") == 256, "bergpass is twice as big")
	check(MapGenerator.round_mask("island"), "island uses the round mask")
	check(not MapGenerator.round_mask("seenland"), "square maps drop the round mask")


## Every anchor sits on walkable ground and every base can reach every other.
func _check_anchors(map_id: String) -> void:
	var td: TerrainData = MapGenerator.create_terrain(map_id, SEED)
	var nav: NavGrid = NavGrid.new(td)
	var anchors: Array[Vector2i] = MapGenerator.spawn_anchors(td, map_id, 4)
	check(anchors.size() == 4, "%s: four anchors for four players" % map_id)
	for i in range(anchors.size()):
		check(nav.is_cell_walkable(anchors[i]),
			"%s: anchor %d is walkable" % [map_id, i])
	for i in range(1, anchors.size()):
		var path: PackedVector3Array = nav.find_path(
			nav.cell_to_world(anchors[0]), nav.cell_to_world(anchors[i]))
		check(not path.is_empty(),
			"%s: anchor 0 can reach anchor %d" % [map_id, i])


func test_island_anchors() -> void:
	_check_anchors("island")


func test_seenland() -> void:
	_check_anchors("seenland")
	var td: TerrainData = MapGenerator.create_terrain("seenland", SEED)
	var nav: NavGrid = NavGrid.new(td)
	var center: Vector2i = Vector2i(td.size / 2, td.size / 2)
	check(not nav.is_cell_walkable(center), "seenland has a lake in the middle")


func test_bergpass() -> void:
	_check_anchors("bergpass")
	var td: TerrainData = MapGenerator.create_terrain("bergpass", SEED)
	var nav: NavGrid = NavGrid.new(td)
	var mid: int = td.size / 2
	# A pass at x = size/2 is open.
	check(nav.is_cell_walkable(Vector2i(td.size / 2, mid)),
		"bergpass: the central pass is walkable")
	# Away from any pass (x = size/8), the ridge blocks a north-south crossing:
	# somewhere along that column there is an impassable cliff cell.
	var blocked: bool = false
	for z in range(mid - 30, mid + 31):
		if not nav.is_cell_walkable(Vector2i(td.size / 8, z)):
			blocked = true
			break
	check(blocked, "bergpass: the ridge between passes blocks a crossing")


func test_plateau() -> void:
	_check_anchors("plateau")
	var td: TerrainData = MapGenerator.create_terrain("plateau", SEED)
	# The plateau tops are strongly raised above the flat surroundings.
	var corner: Vector2i = Vector2i(int(round(float(td.size) * 0.18)),
		int(round(float(td.size) * 0.18)))
	check(td.cell_height(corner) > MapGenerator.LAND + MapGenerator.PLATEAU_HEIGHT - 2.0,
		"plateau top is raised")
	check(td.cell_height(Vector2i(td.size / 2, td.size / 2)) < MapGenerator.LAND + 2.0,
		"the map centre stays flat/low")
