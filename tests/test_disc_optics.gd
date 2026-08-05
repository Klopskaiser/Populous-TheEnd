extends TestBase

## Phase 10j — the parts of the Scheibenwelt's look that ARE headless-testable.
##
## Rendering itself is not (headless has a dummy RenderingServer), so this covers the
## geometry decisions instead: which chunks get triangles, where the rim band starts,
## which stretch of the rim carries a waterfall, and that the minimap draws the same
## circle the gameplay uses. The rest — sky brightness, seams, z-fighting — is on the
## manual checklist by necessity.

const SEED: int = 1337


func _flat(cells: int = TerrainData.SIZE, h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new(cells)
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


# --- Chunk mesh --------------------------------------------------------------------

func test_corner_chunks_are_not_meshed_at_all() -> void:
	# A quad is a cell; outside the disc there is no cell, so the corner chunks lose
	# every triangle and fall out via the existing "indices.is_empty()" path.
	var terrain: Terrain = Terrain.new()
	terrain.build(_flat())
	var per_side: int = TerrainData.SIZE / Terrain.CHUNK
	var corner: MeshInstance3D = terrain.get_node_or_null(
		"Chunks/Chunk_0_0") as MeshInstance3D
	var middle: MeshInstance3D = terrain.get_node_or_null(
		"Chunks/Chunk_%d_%d" % [per_side / 2, per_side / 2]) as MeshInstance3D
	check(corner != null and middle != null, "both chunks exist as nodes")
	check(corner.mesh == null, "the corner chunk has no mesh (it is pure void)")
	check(middle.mesh != null, "the centre chunk does")
	terrain.free()


func test_no_triangle_lies_outside_the_disc() -> void:
	var td: TerrainData = _flat()
	var terrain: Terrain = Terrain.new()
	terrain.build(td)
	var per_side: int = TerrainData.SIZE / Terrain.CHUNK
	var outside: int = 0
	var total: int = 0
	for cz in range(per_side):
		for cx in range(per_side):
			var mi: MeshInstance3D = terrain.get_node_or_null(
				"Chunks/Chunk_%d_%d" % [cx, cz]) as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var arrays: Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in range(0, idx.size(), 3):
				total += 1
				# Centroid of the triangle: a quad inside the disc can have a corner
				# vertex just outside it (that is the vertex-vs-cell rule), but its
				# centroid must be within the disc plus one cell of slack.
				var ctr: Vector3 = (verts[idx[i]] + verts[idx[i + 1]]
					+ verts[idx[i + 2]]) / 3.0
				if Vector2(ctr.x - td.disc_center(), ctr.z - td.disc_center()).length() \
						> td.disc_radius() + TerrainData.CELL_SIZE:
					outside += 1
	check(total > 0, "the terrain produced triangles at all")
	check(outside == 0, "no triangle sits out in the void (%d of %d did)"
		% [outside, total])
	terrain.free()


# --- Rim skirt ---------------------------------------------------------------------

func test_rim_skirt_top_never_dips_below_the_water_line() -> void:
	# The no-hole rule: where the rim is submerged, the rock band's top is lifted to
	# the waterline. Without it there is a visible gap between the cut edge of the sea
	# and the top of the rock.
	var below: int = 0
	for h in [-3.0, 0.0, TerrainData.SEA_LEVEL - 0.1, TerrainData.SEA_LEVEL,
			TerrainData.SEA_LEVEL + 4.0, 30.0]:
		if TerrainRim.rock_top_y(h) < TerrainData.SEA_LEVEL:
			below += 1
	check(below == 0, "the rock band always reaches at least the waterline")
	check(is_equal_approx(TerrainRim.rock_top_y(30.0), 30.0),
		"and follows the terrain where the rim is high and dry")


func test_rim_is_sampled_finely_enough_to_look_round() -> void:
	var small: int = TerrainRim.segment_count(_flat(MapGenerator.STANDARD_SIZE))
	var large: int = TerrainRim.segment_count(_flat(MapGenerator.LARGE_SIZE))
	check(small > 300 and small < 700, "standard map: ~1 m per segment (%d)" % small)
	check(large > small, "the large map gets proportionally more segments (%d)" % large)


func test_waterfall_covers_the_island_rim_and_nothing_on_the_land_maps() -> void:
	# The consequence of the user's "nackte Felskante" decision: only the island has
	# water at its rim, so only the island has a waterfall. Three of four maps read as
	# bare rock — a deliberate trade for playable area.
	var island: TerrainData = MapGenerator.create_terrain("island", SEED)
	var wet: PackedInt32Array = TerrainRim.waterfall_segments(island)
	check(wet.size() == TerrainRim.segment_count(island),
		"the island pours off all the way round (%d of %d segments)"
			% [wet.size(), TerrainRim.segment_count(island)])
	for map_id in ["bergpass", "plateau"]:
		var td: TerrainData = MapGenerator.create_terrain(map_id, SEED)
		check(TerrainRim.waterfall_segments(td).is_empty(),
			"%s has a dry rim: bare rock, no waterfall" % map_id)


func test_touches_rim_only_fires_for_deformations_at_the_edge() -> void:
	var td: TerrainData = _flat()
	var mid: int = td.size / 2
	check(not TerrainRim.touches_rim(td, Rect2i(mid - 4, mid - 4, 8, 8)),
		"a deformation in the middle leaves the rim alone")
	var last: int = mid
	while td.in_disc(Vector2i(last + 1, mid)):
		last += 1
	check(TerrainRim.touches_rim(td, Rect2i(last - 2, mid - 2, 6, 6)),
		"a deformation at the edge rebuilds the rim")


# --- Minimap -----------------------------------------------------------------------

func test_minimap_circle_matches_the_gameplay_disc() -> void:
	# The minimap used to carry its OWN copy of the circle formula. Two formulas
	# eventually disagree by a cell, and then the map paints land you cannot walk on.
	# _cell_color now asks in_disc(), and this compares the two answers cell by cell.
	var td: TerrainData = _flat()
	var minimap: Minimap = Minimap.new()
	minimap.setup(td, null, null, null, null, true)
	var mismatch: int = 0
	for i in range(0, td.size, 5):
		for j in range(0, td.size, 5):
			var cell: Vector2i = Vector2i(i, j)
			var transparent: bool = minimap._cell_color(i, j).a <= 0.0
			if transparent == td.in_disc(cell):
				mismatch += 1
	check(mismatch == 0,
		"the minimap paints exactly the walkable disc (%d cells disagreed)" % mismatch)
	# And the corners really are transparent on every map now that round_mask is true.
	check(MapGenerator.round_mask("bergpass"), "even the land maps use the round mask")
	check(minimap._cell_color(0, 0).a <= 0.0, "so the square's corner stays unpainted")
	minimap.free()


# --- Camera ------------------------------------------------------------------------

func test_camera_may_overshoot_the_rim_but_not_reach_the_underside() -> void:
	var td: TerrainData = _flat()
	var c: float = td.disc_center()
	# The overshoot ring: the rig can sit outside the disc to look back at the edge.
	var out: Vector2 = TerrainData.clamp_into_world(td, c + 500.0, c,
		-CameraRig.PAN_RIM_OVERSHOOT)
	var reach: float = Vector2(out.x - c, out.y - c).length()
	check(reach > td.disc_radius(),
		"the rig may pan past the rim (%.1f > %.1f)" % [reach, td.disc_radius()])
	check(reach <= td.disc_radius() + CameraRig.PAN_RIM_OVERSHOOT + 1.0,
		"but only by the overshoot margin")
	# The rig's Y floor is the waterline, which is WORLD_RIM_SKIRT_DEPTH above the
	# disc's underside — that is what makes the closed bottom unreachable in play.
	check(Balance.WORLD_RIM_SKIRT_DEPTH > 10.0,
		"the underside sits well below the rig's sea-level floor")
