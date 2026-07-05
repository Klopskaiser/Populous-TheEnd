extends TestBase

## Tests for TerrainData: bilinear height, raise_area deformation, walkability
## and deterministic island generation.

func test_get_height_at_vertices() -> void:
	var td: TerrainData = TerrainData.new()
	td.set_vertex_height(10, 10, 5.0)
	td.set_vertex_height(11, 10, 9.0)
	check_near(td.get_height(10.0, 10.0), 5.0, "height at vertex (10,10)")
	check_near(td.get_height(11.0, 10.0), 9.0, "height at vertex (11,10)")


func test_get_height_bilinear() -> void:
	var td: TerrainData = TerrainData.new()
	# Set a unit cell with known corners.
	td.set_vertex_height(0, 0, 0.0)
	td.set_vertex_height(1, 0, 10.0)
	td.set_vertex_height(0, 1, 20.0)
	td.set_vertex_height(1, 1, 30.0)
	# Center of the cell = average of the four corners.
	check_near(td.get_height(0.5, 0.5), 15.0, "bilinear center = corner average")
	# Midpoint of the top edge = average of the two top corners.
	check_near(td.get_height(0.5, 0.0), 5.0, "bilinear top-edge midpoint")
	# Midpoint of the left edge = average of the two left corners.
	check_near(td.get_height(0.0, 0.5), 10.0, "bilinear left-edge midpoint")


func test_raise_area_center_and_falloff() -> void:
	var td: TerrainData = TerrainData.new()
	var center: Vector2 = Vector2(64.0, 64.0)
	var radius: float = 10.0
	var amount: float = 8.0
	td.raise_area(center, radius, amount)
	var h_center: float = td.get_height(64.0, 64.0)
	var h_mid: float = td.get_height(69.0, 64.0)   # halfway to the edge
	var h_edge: float = td.get_height(74.0, 64.0)  # at the radius
	check(absf(h_center - amount) < 0.5, "center raised by ~amount")
	check(h_mid < h_center and h_mid > 0.5, "midpoint raised less than center")
	check(h_mid > h_edge, "falloff is monotonic (edge < mid)")
	# Outside the radius: unchanged.
	check_near(td.get_height(90.0, 64.0), 0.0, "outside radius unchanged")


func test_raise_area_returns_bounding_rect() -> void:
	var td: TerrainData = TerrainData.new()
	var center: Vector2 = Vector2(64.0, 64.0)
	var radius: float = 5.0
	var rect: Rect2i = td.raise_area(center, radius, 4.0)
	# Rect must enclose the affected cells...
	check(rect.has_point(Vector2i(64, 64)), "rect contains center cell")
	# ...and not be wildly larger than the radius (diameter ~10 cells + margin).
	check(rect.size.x <= 14 and rect.size.y <= 14, "rect not much larger than radius")
	check(rect.size.x >= 8 and rect.size.y >= 8, "rect actually covers the area")


func test_is_walkable_sea_level() -> void:
	var td: TerrainData = TerrainData.new()
	# Fresh terrain is all zeros -> below sea level -> not walkable.
	check(not td.is_walkable(Vector2i(50, 50)), "flat sea-level cell not walkable")
	# Landbridge core: raising above sea level makes it walkable.
	td.raise_area(Vector2(50.0, 50.0), 8.0, 6.0)
	check(td.is_walkable(Vector2i(50, 50)), "raised cell above sea level is walkable")


func test_is_walkable_slope() -> void:
	var td: TerrainData = TerrainData.new()
	# Build a steep edge on one cell: corners far apart in height, above sea.
	td.set_vertex_height(30, 30, 3.0)
	td.set_vertex_height(31, 30, 3.0)
	td.set_vertex_height(30, 31, 3.0)
	td.set_vertex_height(31, 31, 3.0 + td.MAX_SLOPE + 2.0)
	check(not td.is_walkable(Vector2i(30, 30)), "steep cell not walkable")


func test_is_walkable_out_of_bounds() -> void:
	var td: TerrainData = TerrainData.new()
	check(not td.is_walkable(Vector2i(-1, 0)), "negative cell not walkable")
	check(not td.is_walkable(Vector2i(td.SIZE, 0)), "past-edge cell not walkable")


func test_generate_island_deterministic() -> void:
	var a: TerrainData = TerrainData.new()
	var b: TerrainData = TerrainData.new()
	a.generate_island(42)
	b.generate_island(42)
	check(a.heights == b.heights, "same seed -> identical heightmap")
	var c: TerrainData = TerrainData.new()
	c.generate_island(43)
	check(a.heights != c.heights, "different seed -> different heightmap")


func test_generate_island_border_under_water() -> void:
	var td: TerrainData = TerrainData.new()
	td.generate_island(7)
	var all_under: bool = true
	var last: int = td.SIZE - 1
	for i in range(td.SIZE):
		if td.cell_height(Vector2i(i, 0)) > td.SEA_LEVEL: all_under = false
		if td.cell_height(Vector2i(i, last)) > td.SEA_LEVEL: all_under = false
		if td.cell_height(Vector2i(0, i)) > td.SEA_LEVEL: all_under = false
		if td.cell_height(Vector2i(last, i)) > td.SEA_LEVEL: all_under = false
	check(all_under, "all border cells are below sea level")


func test_generate_island_has_walkable_land() -> void:
	var td: TerrainData = TerrainData.new()
	td.generate_island(7)
	var count: int = 0
	for z in range(td.SIZE):
		for x in range(td.SIZE):
			if td.is_walkable(Vector2i(x, z)):
				count += 1
	check(count > 500, "island has a substantial walkable land area (got %d)" % count)
