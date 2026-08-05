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


# --- Rim wall ----------------------------------------------------------------------

## The regression the per-edge rewrite fixes: the rim was built from a smooth ring of
## angular samples while the terrain mesh ends on a CELL staircase, so wherever the
## staircase stuck out past the ring an elevation's cross-section stood open (user
## report: "Ränder von Erhebungen haben keinen Abschluss, sie sind einfach beschnitten").
## Wall and mesh edge now come from the same predicate, so this pins that they agree.
func test_every_exposed_mesh_edge_gets_a_wall() -> void:
	var td: TerrainData = _flat()
	var sides: Array = TerrainRim.exposed_sides(td)
	check(sides.size() > 300,
		"the rim of a 128 disc has a few hundred exposed sides (%d)" % sides.size())
	var wrong: int = 0
	for entry in sides:
		var cell: Vector2i = entry[0]
		# Every listed side must be a real boundary: cell inside, neighbour outside.
		if not td.in_disc(cell):
			wrong += 1
	check(wrong == 0, "every exposed side belongs to a cell that is actually meshed")
	# And the count matches a boundary, not an area: a disc of radius r has a cell
	# boundary on the order of the circumference, not of r squared.
	check(sides.size() < td.size * td.size / 8,
		"the wall follows the boundary, not the interior (%d sides)" % sides.size())


func test_wall_spans_from_the_real_terrain_height_down_to_the_slab() -> void:
	# A wall built from the true vertex heights is what closes a cut-off ridge; a wall
	# built from one averaged sample per arc metre is what left it open.
	var td: TerrainData = _flat()
	# A ridge crossing the rim, like bergpass has.
	var mid: int = td.size / 2
	for vz in range(mid - 3, mid + 4):
		for vx in range(td.verts):
			td.set_vertex_height(vx, vz, 26.0)
	var terrain: Terrain = Terrain.new()
	terrain.build(td)
	var rim: TerrainRim = terrain.get_node_or_null("Rim") as TerrainRim
	check(rim != null, "the rim node exists")
	var rock: MeshInstance3D = rim.get_node_or_null("Rock") as MeshInstance3D
	check(rock != null and rock.mesh != null, "the rock wall is meshed")
	var arrays: Array = (rock.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var highest: float = -INF
	var lowest: float = INF
	for v in verts:
		highest = maxf(highest, v.y)
		lowest = minf(lowest, v.y)
	check(highest > 20.0,
		"the wall reaches the ridge's own height where the ridge meets the rim (%.1f)"
			% highest)
	check(is_equal_approx(lowest, TerrainRim.bottom_y()),
		"and it reaches down to the slab's underside (%.1f)" % lowest)
	terrain.free()


func test_waterfall_covers_the_island_rim_and_nothing_on_the_land_maps() -> void:
	# The consequence of the user's "nackte Felskante" decision: only the island has
	# water at its rim, so only the island has a waterfall. Three of four maps read as
	# bare rock — a deliberate trade for playable area.
	var island: TerrainData = MapGenerator.create_terrain("island", SEED)
	var total: int = TerrainRim.exposed_sides(island).size()
	var wet: int = TerrainRim.waterfall_side_count(island)
	check(wet == total,
		"the island pours off all the way round (%d of %d sides)" % [wet, total])
	for map_id in ["bergpass", "plateau"]:
		var td: TerrainData = MapGenerator.create_terrain(map_id, SEED)
		check(TerrainRim.waterfall_side_count(td) == 0,
			"%s has a dry rim: bare rock, no waterfall" % map_id)


func test_waterfall_hangs_from_the_waterline_downward() -> void:
	# "Es hört einfach auf" was the sea overhanging the fall. The band has to start AT
	# the surface and run continuously down past it.
	var td: TerrainData = MapGenerator.create_terrain("island", SEED)
	var terrain: Terrain = Terrain.new()
	terrain.build(td)
	var rim: TerrainRim = terrain.get_node_or_null("Rim") as TerrainRim
	var fall: MeshInstance3D = rim.get_node_or_null("Waterfall") as MeshInstance3D
	check(fall != null and fall.mesh != null and fall.visible,
		"the island has a visible waterfall mesh")
	var arrays: Array = (fall.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var top: float = -INF
	var bottom: float = INF
	for v in verts:
		top = maxf(top, v.y)
		bottom = minf(bottom, v.y)
	check(top >= TerrainData.SEA_LEVEL,
		"the lip starts at or above the waterline (%.2f)" % top)
	check(bottom <= TerrainData.SEA_LEVEL - Balance.WATERFALL_HEIGHT + 0.01,
		"and it falls the full WATERFALL_HEIGHT (%.1f)" % bottom)
	terrain.free()


## The "Torte": at the rim you saw land, then a strip of water below it, then rock —
## the sea's cut overhanging the rock. It is a RADIAL cut again, which is only correct
## because the land's mesh vertices are snapped onto the very same circle.
func test_the_sea_is_cut_on_the_rim_circle() -> void:
	var td: TerrainData = _flat()
	var terrain: Terrain = Terrain.new()
	terrain.build(td)
	var water: MeshInstance3D = terrain.get_node_or_null("Water") as MeshInstance3D
	check(water != null, "the sea plane exists")
	var mat: ShaderMaterial = water.material_override as ShaderMaterial
	check(mat != null, "and it is the shader material (the only path since 10j)")
	check(is_equal_approx(float(mat.get_shader_parameter("disc_radius")),
			td.rim_radius()),
		"the sea is cut exactly on the rim circle")
	check((mat.get_shader_parameter("disc_center") as Vector2).is_equal_approx(
			Vector2(td.disc_center(), td.disc_center())),
		"around the map centre")
	terrain.free()


## The roundness fix: the terrain's own boundary vertices are projected onto the rim
## circle, so the silhouette is a polygon whose corners all sit ON the rim instead of a
## staircase with 1 m steps (user report: "die Zacken sind extrem groß").
##
## It projects BOTH ways on purpose. A first attempt only pulled vertices lying OUTSIDE
## the circle inward, but the boundary ring of a 144 map sits at 70.0..72.1 m — almost
## every vertex is INSIDE, stayed on the grid, and the staircase survived. Worse, the sea
## (cut on the circle) then overhung the land by up to 2 m, which is the blue layer that
## appeared under the land at the rim. Hence: on the circle, not merely within it.
func test_mesh_boundary_sits_exactly_on_the_rim_circle() -> void:
	var td: TerrainData = _flat()
	var c: float = td.disc_center()
	var r: float = td.rim_radius()
	var boundary: int = 0
	var off_circle: int = 0
	var pulled_outward: int = 0
	for vz in range(td.verts):
		for vx in range(td.verts):
			if not td.is_boundary_vertex(vx, vz):
				continue
			boundary += 1
			var p: Vector2 = td.vertex_mesh_xz(vx, vz)
			if absf(Vector2(p.x - c, p.y - c).length() - r) > 0.01:
				off_circle += 1
			# The grid position was inside and had to be pushed OUT — the case the first
			# attempt missed entirely.
			if Vector2(float(vx) - c, float(vz) - c).length() < r - 0.01:
				pulled_outward += 1
	check(boundary > 300, "the boundary ring has a few hundred vertices (%d)" % boundary)
	check(off_circle == 0,
		"every boundary vertex lies ON the rim circle (%d did not)" % off_circle)
	check(pulled_outward > boundary / 4,
		"and most of them had to be pushed OUTWARD to get there (%d of %d)"
			% [pulled_outward, boundary])
	# Interior vertices must not move at all.
	var mid: int = td.size / 2
	var untouched: Vector2 = td.vertex_mesh_xz(mid, mid)
	check(untouched.is_equal_approx(Vector2(float(mid), float(mid))),
		"interior vertices are left exactly where they were")


## The cone must start from the LAND's real height, so a ridge meeting the rim juts
## further out into space than ground-level terrain does (user: "die Kegelform gilt auch
## für die Berge, die ragen an den Kanten also etwas mehr in den Weltraum").
func test_cone_starts_at_the_mountains_own_height_on_a_land_map() -> void:
	var td: TerrainData = MapGenerator.create_terrain("bergpass", SEED)
	var terrain: Terrain = Terrain.new()
	terrain.build(td)
	var rim: TerrainRim = terrain.get_node_or_null("Rim") as TerrainRim
	var rock: MeshInstance3D = rim.get_node_or_null("Rock") as MeshInstance3D
	check(rock != null and rock.mesh != null, "the land map has a rock body at all")
	var arrays: Array = (rock.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var c: float = td.disc_center()
	var highest: float = -INF
	var lowest: float = INF
	# Radius at the top of the body versus far below it: a cone tapers, a slab does not.
	var r_top: float = 0.0
	var r_deep: float = 0.0
	for v in verts:
		highest = maxf(highest, v.y)
		lowest = minf(lowest, v.y)
		var r: float = Vector2(v.x - c, v.z - c).length()
		if v.y > TerrainData.SEA_LEVEL - 1.0:
			r_top = maxf(r_top, r)
		if v.y < TerrainRim.bottom_y() + 20.0:
			r_deep = maxf(r_deep, r)
	check(highest > MapGenerator.LAND + 10.0,
		"the body reaches the ridge's own height where it meets the rim (%.1f)" % highest)
	check(is_equal_approx(lowest, TerrainRim.bottom_y()),
		"and runs down to the cone's tip (%.1f)" % lowest)
	check(r_deep < r_top * 0.75,
		"the body really tapers on a LAND map too (%.0f m at the top, %.0f m deep)"
			% [r_top, r_deep])
	terrain.free()


## The underside is an inverted cone with a ROUNDED tip, not a flat-bottomed slab
## (user decision 2026-08-05). Asserted on the SHAPE — the flank's slope has to ease off
## toward the axis — not on how the rings happen to be sampled.
func test_underside_is_a_cone_with_a_rounded_tip() -> void:
	var r: float = 72.0
	var profile: Array = TerrainRim.cone_profile(r)
	check(profile.size() >= 8, "the cone has enough rings to look smooth (%d)"
		% profile.size())
	check(is_equal_approx(float(profile[0][0]), 1.0), "it starts at the full rim radius")
	check(is_equal_approx(float(profile[profile.size() - 1][0]), 0.0),
		"and converges to the axis")
	check(is_equal_approx(float(profile[profile.size() - 1][1]), TerrainRim.bottom_y()),
		"reaching the tip at bottom_y")
	# Slope dy/dr of the outermost and innermost segment. A cone with a rounded tip is
	# steep at the rim and flattens on the axis; a spike would keep or raise its slope.
	var outer: float = _segment_slope(profile, 0, r)
	var inner: float = _segment_slope(profile, profile.size() - 2, r)
	check(outer > 1.0, "the flank is properly steep at the rim (slope %.2f)" % outer)
	check(inner < outer * 0.5,
		"and flattens toward the tip, so the tip is rounded (%.2f -> %.2f)"
			% [outer, inner])
	# Even arc-length spacing is what keeps the flanks from showing facets.
	var shortest: float = INF
	var longest: float = 0.0
	for i in range(profile.size() - 1):
		var d: float = Vector2(
			(float(profile[i][0]) - float(profile[i + 1][0])) * r,
			float(profile[i][1]) - float(profile[i + 1][1])).length()
		shortest = minf(shortest, d)
		longest = maxf(longest, d)
	check(longest < shortest * 2.0,
		"the rings are evenly spaced along the profile (%.2f..%.2f m)"
			% [shortest, longest])


## |dy/dr| of profile segment `i`.
func _segment_slope(profile: Array, i: int, radius: float) -> float:
	var dr: float = absf(float(profile[i][0]) - float(profile[i + 1][0])) * radius
	var dy: float = absf(float(profile[i][1]) - float(profile[i + 1][1]))
	if dr < 0.0001:
		return INF
	return dy / dr


## The curtains have to face OUTWARD. They used to take the cell-face normal, which on a
## round rim is up to 45 degrees off — the falls pointed sideways and re-emphasised exactly
## the angularity the round rim removes (user report: "die Wasserfälle zeigen in die
## falsche Richtung, nicht nach außen sondern zur Seite").
func test_waterfall_faces_radially_outward() -> void:
	var td: TerrainData = MapGenerator.create_terrain("island", SEED)
	var terrain: Terrain = Terrain.new()
	terrain.build(td)
	var rim: TerrainRim = terrain.get_node_or_null("Rim") as TerrainRim
	var fall: MeshInstance3D = rim.get_node_or_null("Waterfall") as MeshInstance3D
	check(fall != null and fall.mesh != null, "the island has a waterfall")
	var arrays: Array = (fall.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var c: float = td.disc_center()
	var worst: float = 1.0
	for i in range(verts.size()):
		var radial: Vector2 = Vector2(verts[i].x - c, verts[i].z - c)
		if radial.length() < 0.001:
			continue
		worst = minf(worst, Vector2(normals[i].x, normals[i].z).normalized()
			.dot(radial.normalized()))
	# The cell-face normal would bottom out around 0.707 (45 degrees off).
	check(worst > 0.99,
		"every curtain faces outward (worst dot(normal, radial) = %.4f)" % worst)
	terrain.free()


## The water falls STRAIGHT down while the cone tapers away behind it — that contrast is
## the whole point (user: "wasser sollte vom Rand gerade in den Abgrund stürzen").
func test_waterfall_is_vertical_and_dissolves_above_the_tip() -> void:
	var td: TerrainData = MapGenerator.create_terrain("island", SEED)
	var terrain: Terrain = Terrain.new()
	terrain.build(td)
	var rim: TerrainRim = terrain.get_node_or_null("Rim") as TerrainRim
	var fall: MeshInstance3D = rim.get_node_or_null("Waterfall") as MeshInstance3D
	check(fall != null and fall.mesh != null and fall.visible,
		"the island has a visible waterfall mesh")
	var arrays: Array = (fall.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var c: float = td.disc_center()
	# Vertical: top and bottom of each quad share their XZ, so every vertex sits at
	# essentially the same radius — the curtain does not follow the cone inward.
	var min_r: float = INF
	var max_r: float = -INF
	for v in verts:
		var d: float = Vector2(v.x - c, v.z - c).length()
		min_r = minf(min_r, d)
		max_r = maxf(max_r, d)
	check(max_r - min_r < 1.5,
		"the curtain hangs vertically at the rim radius (spread %.2f m)"
			% (max_r - min_r))
	check(Balance.WATERFALL_HEIGHT < Balance.WORLD_RIM_SKIRT_DEPTH,
		"and it stops well above the tip, where the alpha gradient has faded it out")
	terrain.free()


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
