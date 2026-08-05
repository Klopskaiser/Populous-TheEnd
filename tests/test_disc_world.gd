extends TestBase

## Phase 10j — Scheibenwelt: the data model. The world is a DISC inscribed in the
## square heightmap; outside it there is no cell and no ground.
##
## The one lever is the mask in `TerrainData.is_walkable()`/`is_grass()`:
## `NavGrid.update_region()` is the only solidity writer and asks exactly that
## question, so A*, the PathWorker clone, the vehicle grid, island labels, tree and
## unit spawns and `can_place_at` all inherit the disc for free. These tests pin the
## mask, the void's "no ground" property, and the two radial clamps that replaced
## the old rectangular ones.
##
## Kept cheap on purpose: mostly pure predicates, one terrain per method, and only
## the snapping test pays for a 288 grid (where the failure it guards actually lives).

const SEED: int = 1337


func _flat(cells: int = TerrainData.SIZE, h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new(cells)
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


# --- The mask ---------------------------------------------------------------------

func test_cells_outside_the_disc_are_unwalkable() -> void:
	var td: TerrainData = _flat()
	# Flat land at 5.0 would be walkable everywhere if the disc did not mask it.
	check(td.is_walkable(Vector2i(td.size / 2, td.size / 2)),
		"the centre is walkable")
	var outside: int = 0
	var inside_unwalkable: int = 0
	for cell in [Vector2i(0, 0), Vector2i(td.size - 1, 0), Vector2i(0, td.size - 1),
			Vector2i(td.size - 1, td.size - 1)]:
		if not td.is_walkable(cell):
			outside += 1
	check(outside == 4, "all four square corners are void, not land")
	for cell in [Vector2i(td.size / 2, 2), Vector2i(2, td.size / 2)]:
		if not td.is_walkable(cell):
			inside_unwalkable += 1
	check(inside_unwalkable == 0,
		"the disc still reaches the edge midpoints (the area is not lost)")


func test_cells_outside_the_disc_are_not_grass() -> void:
	var td: TerrainData = _flat(TerrainData.SIZE, TerrainData.GRASS_MIN + 0.5)
	check(td.is_grass(Vector2i(td.size / 2, td.size / 2)), "the centre is grass")
	check(not td.is_grass(Vector2i(0, 0)),
		"the void is not grass either (tree sprouting cannot reach it)")


func test_in_disc_includes_the_bounds_test() -> void:
	var td: TerrainData = _flat()
	check(not td.in_disc(Vector2i(-1, td.size / 2)), "negative cells are not in the disc")
	check(not td.in_disc(Vector2i(td.size, td.size / 2)), "past the edge is not either")
	check(td.in_disc(Vector2i(td.size / 2, td.size / 2)), "the centre is")


# --- The core: no ground out there -------------------------------------------------

func test_has_ground_is_false_outside_the_disc() -> void:
	var td: TerrainData = _flat()
	var c: float = td.disc_center()
	var r: float = td.disc_radius()
	check(td.has_ground(c, c), "ground at the centre")
	check(td.has_ground(c + r - 1.0, c), "ground just inside the rim")
	check(not td.has_ground(c + r + 3.0, c), "no ground just outside the rim")
	check(not td.has_ground(0.5, 0.5), "no ground in the square's corner")
	check(not td.has_ground(-50.0, c), "no ground far outside the rectangle")
	# get_height() keeps clamping on purpose (many callers want "the ground below"),
	# which is exactly why has_ground has to exist as a separate question.
	check(td.get_height(-50.0, c) > 0.0,
		"get_height still reports the rim height out there — hence has_ground")


func test_has_ground_covers_the_whole_last_walkable_cell() -> void:
	# The regression this guards: has_ground must be slightly MORE generous than the
	# cell mask, or a unit standing on the outer corner of a legitimately walkable rim
	# cell would count as standing over the void and drop out of the world.
	var td: TerrainData = _flat()
	var mid: int = td.size / 2
	var last: int = mid
	while td.in_disc(Vector2i(last + 1, mid)):
		last += 1
	var worst: int = 0
	for corner in [Vector2(0.02, 0.02), Vector2(0.98, 0.02),
			Vector2(0.02, 0.98), Vector2(0.98, 0.98)]:
		if not td.has_ground(float(last) + corner.x, float(mid) + corner.y):
			worst += 1
	check(worst == 0, "every corner of the last walkable cell has ground under it")


func test_average_height_ignores_the_void() -> void:
	# The airship's cruise reference. The void's heights are 0 and would be averaged
	# in as SEA_LEVEL, dragging the altitude down by about a fifth on every map.
	var td: TerrainData = _flat(TerrainData.SIZE, 20.0)
	for i in range(td.heights.size()):
		td.heights[i] = 20.0
	# Zero out everything outside the disc, the way generate_island does.
	for vz in range(td.verts):
		for vx in range(td.verts):
			if not td.vertex_in_disc(vx, vz):
				td.heights[vz * td.verts + vx] = 0.0
	check(is_equal_approx(td.average_height(), 20.0),
		"the mean is the disc's height (%.2f), not diluted by the void"
			% td.average_height())


func test_vertex_in_disc_keeps_the_rim_cells_outer_vertices() -> void:
	# The vertex-vs-cell layout trap: heights is verts², walkability size². A rim
	# cell needs its OUTER vertices, so a vertex belonging to any in-disc cell counts.
	var td: TerrainData = _flat()
	var mid: int = td.size / 2
	var last: int = mid
	while td.in_disc(Vector2i(last + 1, mid)):
		last += 1
	check(td.vertex_in_disc(last + 1, mid),
		"the outer vertex of the last walkable cell is still part of the disc")
	check(not td.vertex_in_disc(last + 3, mid),
		"a vertex with no in-disc cell around it is not")


# --- Radial clamps ----------------------------------------------------------------

func test_nearest_walkable_cell_works_from_a_void_corner_on_a_large_map() -> void:
	# The documented failure this replaces: nearest_walkable_cell clamped to the
	# RECTANGLE and then searched only MAX_SNAP_RADIUS = 32 rings. A corner of a 288
	# map is 0.5 * 288 * (sqrt(2) - 1) = 59.6 cells from the nearest disc cell, so the
	# search ran out and returned (-1, -1). That answer travelled on as island_at() ==
	# -1 into AIController._home_islands(), whose empty-set bail-outs silently switch
	# the AI's build-site guard off — a failure with no error message at all.
	var td: TerrainData = _flat(MapGenerator.LARGE_SIZE)
	var nav: NavGrid = NavGrid.new(td)
	for corner in [Vector2i(0, 0), Vector2i(td.size - 1, 0),
			Vector2i(0, td.size - 1), Vector2i(td.size - 1, td.size - 1)]:
		var snapped: Vector2i = nav.nearest_walkable_cell(corner)
		check(snapped.x >= 0 and nav.is_cell_walkable(snapped),
			"corner %s snaps onto real ground (got %s)" % [corner, snapped])
		check(nav.island_at(snapped) >= 0,
			"and the result has a real island label (the AI depends on it)")


func test_clamp_into_world_pulls_a_point_onto_the_disc() -> void:
	var td: TerrainData = _flat()
	var c: float = td.disc_center()
	var far: Vector2 = TerrainData.clamp_into_world(td, 500.0, 500.0)
	check(Vector2(far.x - c, far.y - c).length() <= td.disc_radius(),
		"a point far outside lands inside the disc")
	check(td.has_ground(far.x, far.y), "and it has ground under it")
	var inside: Vector2 = TerrainData.clamp_into_world(td, c + 5.0, c - 3.0)
	check(is_equal_approx(inside.x, c + 5.0) and is_equal_approx(inside.y, c - 3.0),
		"a point already inside is not moved")


func test_terrain_deforming_spells_cannot_extend_the_disc() -> void:
	# Structural, not a special case per spell: the mask sits IN is_walkable(), and
	# NavGrid.update_region() is the only solidity writer — so raising a void cell
	# cannot make it walkable, no matter which deform function did the raising.
	var td: TerrainData = _flat()
	var nav: NavGrid = NavGrid.new(td)
	var c: float = td.disc_center()
	var target: Vector2 = Vector2(c + td.disc_radius() + 6.0, c)
	# A landbridge and a plain raise, both aimed past the rim.
	var rect: Rect2i = td.raise_area(target, 12.0, 30.0)
	nav.update_region(rect)
	var rect2: Rect2i = td.raise_line(Vector2(c, c), target, 4.0, 20.0, 20.0)
	nav.update_region(rect2)
	var leaked: int = 0
	for z in range(td.size):
		for x in range(td.size):
			var cell: Vector2i = Vector2i(x, z)
			if not td.in_disc(cell) and nav.is_cell_walkable(cell):
				leaked += 1
	check(leaked == 0, "no void cell became walkable (%d leaked)" % leaked)


# --- The maps ---------------------------------------------------------------------

func test_all_maps_report_round_mask() -> void:
	var square: int = 0
	for map_id in MapGenerator.map_ids():
		if not MapGenerator.round_mask(map_id):
			square += 1
	check(square == 0, "every map is a disc")


func test_map_sizes_preserve_the_old_square_area() -> void:
	# The user requirement: the usable area must not shrink. A disc of radius
	# size/2 has area pi/4 of the square, so the edges grew by 2/sqrt(pi) = 1.128.
	check(MapGenerator.STANDARD_SIZE == 144, "standard map edge is 144")
	check(MapGenerator.LARGE_SIZE == 288, "large map edge is 288")
	var small_disc: float = PI * pow(float(MapGenerator.STANDARD_SIZE) * 0.5, 2.0)
	var large_disc: float = PI * pow(float(MapGenerator.LARGE_SIZE) * 0.5, 2.0)
	check(absf(small_disc / (128.0 * 128.0) - 1.0) < 0.01,
		"the 144 disc matches the old 128 square (%.3f)" % (small_disc / 16384.0))
	check(absf(large_disc / (256.0 * 256.0) - 1.0) < 0.01,
		"the 288 disc matches the old 256 square (%.3f)" % (large_disc / 65536.0))


func test_map_sizes_are_chunk_aligned() -> void:
	# Terrain._chunk_count truncates size / CHUNK: an edge that is not a multiple of
	# the chunk size leaves a strip unmeshed but still walkable, with no warning.
	check(MapGenerator.STANDARD_SIZE % Terrain.CHUNK == 0,
		"standard map is chunk-aligned (%d / %d)"
			% [MapGenerator.STANDARD_SIZE, Terrain.CHUNK])
	check(MapGenerator.LARGE_SIZE % Terrain.CHUNK == 0, "large map is chunk-aligned")


func test_every_map_anchor_lies_inside_the_disc_and_is_walkable() -> void:
	# THE blocker test. Corner anchors used to sit 0.4525 * size from the centre,
	# i.e. inside a 0.5 * size disc but with only 6.9 cells of clearance on a 144
	# map — not enough for a base. CORNER_INSET_F 0.18 -> 0.22 gives 15.4 / 29.5.
	for map_id in MapGenerator.map_ids():
		var td: TerrainData = MapGenerator.create_terrain(map_id, SEED)
		var nav: NavGrid = NavGrid.new(td)
		for count in [2, 3, 4]:
			var anchors: Array[Vector2i] = MapGenerator.spawn_anchors(td, map_id, count)
			var bad: int = 0
			var tight: int = 0
			for a in anchors:
				if not td.in_disc(a) or not nav.is_cell_walkable(a):
					bad += 1
				var d: float = Vector2(float(a.x) + 0.5 - td.disc_center(),
					float(a.y) + 0.5 - td.disc_center()).length()
				if td.disc_radius() - d < 10.0:
					tight += 1
			check(bad == 0, "%s/%d: every anchor is inside the disc and walkable"
				% [map_id, count])
			check(tight == 0,
				"%s/%d: every anchor keeps at least 10 cells clear of the rim"
					% [map_id, count])


func test_bergpass_ridge_still_seals_the_disc() -> void:
	# The disc cuts both ends off the ridge band. It only REMOVES cells, so it cannot
	# open a detour — but that has to be proven, not assumed.
	var td: TerrainData = MapGenerator.create_terrain("bergpass", SEED)
	var nav: NavGrid = NavGrid.new(td)
	var mid: int = td.size / 2
	var open_columns: int = 0
	for x in range(td.size):
		if not td.in_disc(Vector2i(x, mid)):
			continue
		var blocked: bool = false
		for z in range(mid - int(float(td.size) * 0.1), mid + int(float(td.size) * 0.1) + 1):
			if not nav.is_cell_walkable(Vector2i(x, z)):
				blocked = true
				break
		if not blocked:
			open_columns += 1
	# Only the three passes may be open; each is PASS_HALF wide on both sides.
	var max_open: int = 3 * (MapGenerator.PASS_HALF * 2 + 3)
	check(open_columns > 0, "the passes are open (%d columns)" % open_columns)
	check(open_columns <= max_open,
		"the ridge still seals everything but the passes (%d open, max %d)"
			% [open_columns, max_open])


func test_trees_never_spawn_outside_the_disc() -> void:
	var td: TerrainData = MapGenerator.create_terrain("island", SEED)
	var nav: NavGrid = NavGrid.new(td)
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	tm.spawn_trees(120, SEED)
	var outside: int = 0
	for tree in tm.trees:
		if not td.in_disc(nav.world_to_cell(tree.position)):
			outside += 1
	check(tm.trees.size() > 0, "trees did spawn")
	check(outside == 0, "no tree stands in the void (%d did)" % outside)
	tm.free()


# --- The AI's dependencies on all of this ------------------------------------------

func test_small_map_threshold_follows_the_standard_map() -> void:
	# Balance.SMALL_MAP_MAX_SIZE used to be TerrainData.SIZE, which is now only the
	# DEFAULT/test size (128) — the 144 maps would have been classified as large and
	# would have lost their 20 % starting-wood bonus.
	check(Balance.SMALL_MAP_MAX_SIZE == MapGenerator.STANDARD_SIZE,
		"the small-map threshold is the standard map edge")
	check(MapGenerator.map_size("island") <= Balance.SMALL_MAP_MAX_SIZE,
		"island counts as small")
	check(MapGenerator.map_size("seenland") > Balance.SMALL_MAP_MAX_SIZE,
		"seenland does not")


func test_tree_counts_are_unchanged_by_the_growth() -> void:
	# main.gd derives the tree count from (size / STANDARD_SIZE)^2 as a FLOAT. With
	# integer division against TerrainData.SIZE the large maps got a factor of 5
	# instead of 4 — 25 % too many trees.
	var small: float = float(MapGenerator.STANDARD_SIZE * MapGenerator.STANDARD_SIZE) \
		/ float(MapGenerator.STANDARD_SIZE * MapGenerator.STANDARD_SIZE)
	var large: float = float(MapGenerator.LARGE_SIZE * MapGenerator.LARGE_SIZE) \
		/ float(MapGenerator.STANDARD_SIZE * MapGenerator.STANDARD_SIZE)
	check(is_equal_approx(small, 1.0), "the standard map keeps factor 1")
	check(is_equal_approx(large, 4.0), "the large map gets factor 4, not 5")


func test_cramped_classification_is_unchanged_per_map() -> void:
	# AI_CRAMPED_ARENA is a CLIFF, not a dial: crossing it flips search radius
	# (18<->40), settlement anchors (2<->4), towers (3<->2) and wave size (8<->12)
	# at once. It grew with the map edges (60 -> 68) so every map keeps its profile.
	var s: float = float(MapGenerator.STANDARD_SIZE)
	# Island: anchors on a circle of radius 0.2 * size, nearest-neighbour span.
	check(AIState.is_cramped(0.4 * s * sin(PI / 4.0)),
		"island with 4 tribes stays cramped (%.1f)" % (0.4 * s * sin(PI / 4.0)))
	check(AIState.is_cramped(0.4 * s * sin(PI / 2.0)),
		"island with 2 tribes stays cramped (%.1f)" % (0.4 * s * sin(PI / 2.0)))
	# Corner-anchor maps: adjacent anchors are (size - 2 * inset * size) apart.
	var corner_span: float = s - 2.0 * MapGenerator.CORNER_INSET_F * s
	check(not AIState.is_cramped(corner_span),
		"plateau with corner anchors stays open (%.1f)" % corner_span)
