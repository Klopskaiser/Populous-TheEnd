class_name TerrainRim extends Node3D

## Phase 10j — the edge and the underside of the Scheibenwelt.
##
## The terrain chunks stop at the rim, which on its own leaves a paper-thin sheet: from
## a low camera angle you would look straight through the world. This node gives the
## disc a body, with two static meshes and no `tick()`:
##
##   * ROCK      — a short vertical cliff right under the rim, then an INVERTED CONE
##                 tapering inward and down to a rounded tip under the map centre
##                 (user decision 2026-08-05: "quasi ein umgedrehter Kegel mit
##                 abgerundeter Spitze"). A closed solid, so there is no underside left
##                 to see through.
##   * WATERFALL — wherever the rim is under water: a curtain hanging STRAIGHT DOWN from
##                 the waterline, deliberately not following the cone. The cone recedes
##                 inward while the water falls vertically, and that contrast is what
##                 makes the shape read. It dissolves via an alpha gradient well above
##                 the tip.
##
## ## Built from the mesh's own boundary, at the mesh's own snapped positions
##
## Two earlier attempts each failed one half of this:
##
## 1. A smooth ring of angular samples was round but could not follow the terrain, whose
##    edge was a cell staircase — wherever the staircase stuck out, an elevation's
##    cross-section stood open ("Ränder von Erhebungen haben keinen Abschluss").
## 2. Building per exposed cell side closed every flank exactly, but then inherited the
##    staircase and looked coarse ("die Zacken sind extrem groß").
##
## The fix is upstream, in the mesh: `TerrainData.vertex_mesh_xz()` snaps boundary
## vertices onto the rim circle, so the terrain edge is a smooth inscribed polygon. This
## node builds from the SAME snapped vertices along the SAME exposed sides — round like
## (1), gap-free like (2).

## Total depth below the waterline, split into the vertical cliff and the cone.
const SKIRT_DEPTH: float = Balance.WORLD_RIM_SKIRT_DEPTH
## Vertical rock immediately under the rim, so the very edge still reads as a cliff
## ("nackte Felskante") before the taper starts.
const CLIFF_DEPTH: float = 4.0
## Rings the cone is built from, spaced by equal ARC LENGTH along its profile (see
## cone_profile) so no part of the flank shows facets.
const CONE_RINGS: int = 14
## Shape exponent of the cone: y = cliff_bottom - depth * (1 - s^CONE_POW) over the
## radius factor s. Above 1 the slope reaches zero at s = 0, which is what rounds the
## tip instead of leaving a spike; larger values make the flanks steeper near the rim.
const CONE_POW: float = 2.5
## How far the waterfall hangs below the waterline.
const WATERFALL_HEIGHT: float = Balance.WATERFALL_HEIGHT
## Vertical UV tiling of the waterfall, in metres (matches the shader's `tile`).
const WATERFALL_TILE: float = 8.0
## The rock darkens toward the tip.
const BOTTOM_SHADE: float = 0.30
## The cliff is pushed this far OUTWARD along its normal, and each side is extended by
## the same amount at both ends.
##
## Both halves matter. The offset puts the rock unambiguously in FRONT of the sea's cut
## edge, which is otherwise all but coplanar with it — that hairline was the middle layer
## of the reported "Torte" (land on top, a strip of water below, then rock). The
## lengthwise extension closes the notches the offset would otherwise open where the
## boundary polygon turns.
const WALL_OUT: float = 0.06
## The waterfall hangs this far outside the cliff so the two never fight for depth.
const WATERFALL_OUT: float = 0.05
## A cell counts as submerged (and therefore pours) at or below this. Slightly above
## SEA_LEVEL so a cell lapping exactly at the waterline still produces a fall.
const SUBMERGED_EPS: float = 0.05

var _rock: MeshInstance3D = null
var _waterfall: MeshInstance3D = null


# --- Pure geometry (headless-testable) ----------------------------------------------

## The four neighbour offsets, paired with the cell-local edge they expose.
## Each entry is [neighbour offset, edge vertex A, edge vertex B] in cell-vertex space,
## ordered so that A -> B runs counter-clockwise around the cell.
const _SIDES: Array = [
	[Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 1)],    # +x
	[Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, 0)],   # -x
	[Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 1)],    # +z
	[Vector2i(0, -1), Vector2i(0, 0), Vector2i(1, 0)],   # -z
]


## Every exposed side of the disc: the boundary of the meshed cell set. Returns an array
## of [cell: Vector2i, side_index: int]. STATIC and pure, so the rim's extent is testable
## without a scene — and it is the SAME predicate the chunk mesh culls on.
static func exposed_sides(td: TerrainData) -> Array:
	var out: Array = []
	if td == null:
		return out
	for z in range(td.size):
		for x in range(td.size):
			var cell: Vector2i = Vector2i(x, z)
			if not td.in_disc(cell):
				continue
			for i in range(_SIDES.size()):
				if not td.in_disc(cell + _SIDES[i][0]):
					out.append([cell, i])
	return out


## True when this cell's surface lies at or below the waterline — water pours off here.
static func cell_is_submerged(td: TerrainData, cell: Vector2i) -> bool:
	if td == null or not td.in_disc(cell):
		return false
	return td.cell_height(cell) <= TerrainData.SEA_LEVEL + SUBMERGED_EPS


## How many exposed sides carry a waterfall. Pure, so "the island pours off all the way
## round, the land maps not at all" is headless-testable.
static func waterfall_side_count(td: TerrainData) -> int:
	var n: int = 0
	for entry in exposed_sides(td):
		if cell_is_submerged(td, entry[0]):
			n += 1
	return n


## True when a deformed cell rectangle comes close enough to the rim to change it.
static func touches_rim(td: TerrainData, rect: Rect2i) -> bool:
	if td == null:
		return false
	# Grown by one cell, because a deformation just INSIDE the boundary still moves the
	# vertices the cliff is built from.
	var grown: Rect2i = Rect2i(rect.position - Vector2i.ONE, rect.size + Vector2i.ONE * 2)
	for z in range(grown.position.y, grown.position.y + grown.size.y):
		for x in range(grown.position.x, grown.position.x + grown.size.x):
			var cell: Vector2i = Vector2i(x, z)
			if not td.in_disc(cell):
				continue
			for side in _SIDES:
				if not td.in_disc(cell + side[0]):
					return true
	return false


## Y where the vertical cliff ends and the cone begins.
static func cliff_bottom_y() -> float:
	return TerrainData.SEA_LEVEL - CLIFF_DEPTH


## Y of the cone's tip — the deepest point of the world.
static func bottom_y() -> float:
	return TerrainData.SEA_LEVEL - SKIRT_DEPTH


## The cone's profile: [radius factor (1 = rim, 0 = tip), Y] per ring.
##
## Shape: `y(s) = cliff_bottom - depth * (1 - s^CONE_POW)`. The exponent above 1 is what
## rounds the tip — `dy/ds` goes to zero on the axis, so the surface flattens into a dome
## instead of closing to a spike.
##
## Sampling is by EQUAL ARC LENGTH along that profile, which needs the real radius and is
## why this takes one. Two simpler choices are both wrong and were both tried: uniform
## radius steps put most of the 56 m drop into the outermost rings and leave metre-scale
## facets at the rim, while uniform VERTICAL steps do the opposite — the radius then
## collapses over the last two rings and the "rounded" tip comes out as a flat plate with
## a spike (caught by test_underside_is_a_cone_with_a_rounded_tip).
static func cone_profile(radius: float) -> Array:
	var top: float = cliff_bottom_y()
	var depth: float = top - bottom_y()   # positive
	var r: float = maxf(radius, 0.001)
	# Fine walk from rim to tip, accumulating arc length.
	var fine: int = 400
	var s_at: PackedFloat32Array = PackedFloat32Array()
	var arc_at: PackedFloat32Array = PackedFloat32Array()
	s_at.resize(fine + 1)
	arc_at.resize(fine + 1)
	var arc: float = 0.0
	var prev: Vector2 = Vector2(r, top)
	s_at[0] = 1.0
	arc_at[0] = 0.0
	for i in range(1, fine + 1):
		var s: float = 1.0 - float(i) / float(fine)
		var y: float = top - depth * (1.0 - pow(s, CONE_POW))
		var p: Vector2 = Vector2(s * r, y)
		arc += p.distance_to(prev)
		prev = p
		s_at[i] = s
		arc_at[i] = arc
	# Pick CONE_RINGS+1 points at equal fractions of the total arc.
	var out: Array = []
	var cursor: int = 0
	for k in range(CONE_RINGS + 1):
		var want: float = arc * float(k) / float(CONE_RINGS)
		while cursor < fine and arc_at[cursor] < want:
			cursor += 1
		var s: float = s_at[cursor]
		if k == CONE_RINGS:
			s = 0.0   # the last ring collapses exactly onto the axis
		out.append([s, top - depth * (1.0 - pow(s, CONE_POW))])
	return out


# --- Build --------------------------------------------------------------------------

func rebuild(td: TerrainData) -> void:
	if td == null:
		return
	_ensure_nodes()
	var sides: Array = exposed_sides(td)
	_rock.mesh = _build_rock(td, sides)
	_waterfall.mesh = _build_waterfall(td, sides)
	_waterfall.visible = _waterfall.mesh != null


## RADIAL outward direction of a rim side, from the map centre through the side's
## midpoint.
##
## Not the cell-face normal (+/-x, +/-z), which is what it used to be. With only four
## possible directions every quad on a round rim faced up to 45 degrees off true, so the
## waterfall curtains pointed sideways instead of outward and re-emphasised exactly the
## angularity the round rim was meant to remove (user report: "die Wasserfälle zeigen in
## die falsche Richtung, nicht nach außen sondern zur Seite"). Both endpoints of a side
## lie ON the rim circle after projection, so the side is a chord and its radial normal
## is the correct one — for the rock's lighting just as much as for the water.
func _outward(a: Vector3, b: Vector3, centre: float) -> Vector3:
	var mid: Vector2 = Vector2((a.x + b.x) * 0.5 - centre, (a.z + b.z) * 0.5 - centre)
	if mid.length_squared() < 0.000001:
		return Vector3(1.0, 0.0, 0.0)
	mid = mid.normalized()
	return Vector3(mid.x, 0.0, mid.y)


## World position of a cell-vertex, at the SNAPPED XZ the mesh uses, with its height.
func _vertex_world(td: TerrainData, cell: Vector2i, local: Vector2i) -> Vector3:
	var vx: int = cell.x + local.x
	var vz: int = cell.y + local.y
	var xz: Vector2 = td.vertex_mesh_xz(vx, vz)
	return Vector3(xz.x, td.vertex_height(vx, vz), xz.y)


## Cliff + cone as one mesh: per exposed side, a strip that starts at the two REAL
## terrain heights, drops vertically by CLIFF_DEPTH, then walks the cone profile inward
## and down to the tip. Every ring reuses the same two snapped directions, so nothing
## has to be sorted into a ring and no two levels can drift apart.
func _build_rock(td: TerrainData, sides: Array) -> ArrayMesh:
	if sides.is_empty():
		return null
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	var rock: Color = Terrain.COLOR_ROCK
	var deep: Color = Terrain.COLOR_ROCK * BOTTOM_SHADE
	deep.a = 1.0
	var profile: Array = cone_profile(td.rim_radius())
	var centre: Vector2 = Vector2(td.disc_center(), td.disc_center())
	var tip: float = bottom_y()
	var span: float = maxf(TerrainData.SEA_LEVEL - tip, 0.001)

	for entry in sides:
		var cell: Vector2i = entry[0]
		var side: Array = _SIDES[entry[1]]
		var a: Vector3 = _vertex_world(td, cell, side[1])
		var b: Vector3 = _vertex_world(td, cell, side[2])
		var outward: Vector3 = _outward(a, b, td.disc_center())
		var along: Vector3 = Vector3(b.x - a.x, 0.0, b.z - a.z)
		if along.length_squared() > 0.000001:
			along = along.normalized()
		var push: Vector3 = outward * WALL_OUT
		var pa: Vector3 = a + push - along * WALL_OUT
		var pb: Vector3 = b + push + along * WALL_OUT
		var ra: Vector2 = Vector2(pa.x, pa.z) - centre
		var rb: Vector2 = Vector2(pb.x, pb.z) - centre

		# Level 0: the terrain surface itself (two different heights).
		var prev_a: Vector3 = Vector3(pa.x, a.y, pa.z)
		var prev_b: Vector3 = Vector3(pb.x, b.y, pb.z)
		# Level 1: bottom of the vertical cliff, at constant Y.
		var levels: Array = [[prev_a, prev_b]]
		levels.append([Vector3(pa.x, cliff_bottom_y(), pa.z),
			Vector3(pb.x, cliff_bottom_y(), pb.z)])
		# Levels 2..n: the cone, scaled inward toward the centre.
		for i in range(1, profile.size()):
			var s: float = profile[i][0]
			var y: float = profile[i][1]
			levels.append([
				Vector3(centre.x + ra.x * s, y, centre.y + ra.y * s),
				Vector3(centre.x + rb.x * s, y, centre.y + rb.y * s)])

		for i in range(levels.size() - 1):
			var t0: Array = levels[i]
			var t1: Array = levels[i + 1]
			var base: int = verts.size()
			verts.append(t0[0]); verts.append(t0[1])
			verts.append(t1[0]); verts.append(t1[1])
			# Normal leans outward and downward as the cone tapers, so the flanks catch
			# the light instead of reading as one flat band.
			var n0: Vector3 = _strip_normal(t0[0], t0[1], t1[0], outward)
			for _k in range(4):
				normals.append(n0)
			colors.append(_shade(rock, deep, t0[0].y, tip, span))
			colors.append(_shade(rock, deep, t0[1].y, tip, span))
			colors.append(_shade(rock, deep, t1[0].y, tip, span))
			colors.append(_shade(rock, deep, t1[1].y, tip, span))
			indices.append(base); indices.append(base + 1); indices.append(base + 2)
			indices.append(base + 1); indices.append(base + 3); indices.append(base + 2)
	return _assemble(verts, normals, colors, indices)


## Outward-facing normal of a strip quad, falling back to `outward` when the quad
## degenerates (the innermost ring collapses onto the tip).
func _strip_normal(a: Vector3, b: Vector3, below: Vector3, outward: Vector3) -> Vector3:
	var n: Vector3 = (b - a).cross(below - a)
	if n.length_squared() < 0.000001:
		return outward
	n = n.normalized()
	# Keep it pointing away from the axis.
	if n.dot(outward) < 0.0:
		n = -n
	return n


## Rock colour by depth: full at the waterline, BOTTOM_SHADE at the tip. A vertical
## gradient sells the depth for free, with no extra light.
func _shade(top: Color, bottom: Color, y: float, tip: float, span: float) -> Color:
	var t: float = clampf((TerrainData.SEA_LEVEL - y) / span, 0.0, 1.0)
	var c: Color = top.lerp(bottom, t)
	c.a = 1.0
	return c


## The waterfall: a curtain hanging STRAIGHT DOWN from the waterline at the rim, one
## quad per submerged exposed side. Deliberately vertical — the cone tapers away behind
## it, and that separation is the effect the user asked for.
func _build_waterfall(td: TerrainData, sides: Array) -> ArrayMesh:
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	# Starts a hair ABOVE the sea surface so the lip tucks under the waves instead of
	# leaving a seam at the waterline.
	var top_y: float = TerrainData.SEA_LEVEL + Terrain.WATER_SURFACE_LIFT + 0.05
	var floor_y: float = TerrainData.SEA_LEVEL - WATERFALL_HEIGHT
	var v_max: float = WATERFALL_HEIGHT / WATERFALL_TILE
	var c: float = td.disc_center()
	for entry in sides:
		var cell: Vector2i = entry[0]
		if not cell_is_submerged(td, cell):
			continue
		var side: Array = _SIDES[entry[1]]
		var a: Vector3 = _vertex_world(td, cell, side[1])
		var b: Vector3 = _vertex_world(td, cell, side[2])
		var outward: Vector3 = _outward(a, b, c)
		var along: Vector3 = Vector3(b.x - a.x, 0.0, b.z - a.z)
		if along.length_squared() > 0.000001:
			along = along.normalized()
		var push: Vector3 = outward * (WALL_OUT + WATERFALL_OUT)
		var pa: Vector3 = a + push - along * WALL_OUT
		var pb: Vector3 = b + push + along * WALL_OUT
		# U comes from the ANGLE around the map centre, not from a running total over
		# the sides: `sides` is in cell-scan order, not ring order, so an accumulated run
		# would hand neighbouring quads unrelated streak phases and draw a seam at every
		# cell.
		var u0: float = _rim_u(pa, c)
		var u1: float = _rim_u(pb, c)
		if absf(u1 - u0) > PI * td.rim_radius() / WATERFALL_TILE:
			u1 = u0 + TerrainData.CELL_SIZE / WATERFALL_TILE   # the wrap-around quad
		var base: int = verts.size()
		verts.append(Vector3(pa.x, top_y, pa.z))
		verts.append(Vector3(pb.x, top_y, pb.z))
		verts.append(Vector3(pa.x, floor_y, pa.z))
		verts.append(Vector3(pb.x, floor_y, pb.z))
		for _k in range(4):
			normals.append(outward)
		uvs.append(Vector2(u0, 0.0))
		uvs.append(Vector2(u1, 0.0))
		uvs.append(Vector2(u0, v_max))
		uvs.append(Vector2(u1, v_max))
		indices.append(base); indices.append(base + 1); indices.append(base + 2)
		indices.append(base + 1); indices.append(base + 3); indices.append(base + 2)
	if indices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Horizontal UV along the rim: arc length from the map centre's angle, in tiles.
func _rim_u(p: Vector3, center: float) -> float:
	var r: float = Vector2(p.x - center, p.z - center).length()
	return atan2(p.z - center, p.x - center) * r / WATERFALL_TILE


func _assemble(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, indices: PackedInt32Array) -> ArrayMesh:
	if indices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _ensure_nodes() -> void:
	if _rock == null:
		_rock = _make_instance("Rock", _rock_material())
	if _waterfall == null:
		_waterfall = _make_instance("Waterfall", _waterfall_material())


func _make_instance(node_name: String, mat: Material) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.material_override = mat
	# A body around the whole map casting through every shadow cascade is pure waste,
	# and the sun never lights the underside anyway.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _rock_material() -> Material:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	# Two-sided: the cone is a per-side patchwork rather than one closed hull, so a
	# winding slip must not turn a stretch of rim invisible. At a few thousand triangles
	# the saved culling is irrelevant.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _waterfall_material() -> Material:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = preload("res://shaders/waterfall.gdshader")
	# Same colour pair as the sea, so the lip cannot drift out of tune.
	mat.set_shader_parameter("deep", Vector3(
		Terrain.COLOR_WATER.r, Terrain.COLOR_WATER.g, Terrain.COLOR_WATER.b))
	mat.set_shader_parameter("crest", Vector3(Terrain.COLOR_WATER_HIGHLIGHT.r,
		Terrain.COLOR_WATER_HIGHLIGHT.g, Terrain.COLOR_WATER_HIGHLIGHT.b))
	mat.set_shader_parameter("scroll_speed", Balance.WATERFALL_SCROLL_SPEED)
	mat.set_shader_parameter("tile", WATERFALL_TILE)
	# Dissolves over most of its length, so it thins out into the void instead of
	# ending on a hard line well above the cone's tip (user request).
	mat.set_shader_parameter("fade_fraction", 0.65)
	return mat
