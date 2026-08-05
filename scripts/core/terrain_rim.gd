class_name TerrainRim extends Node3D

## Phase 10j — the edge of the Scheibenwelt.
##
## The terrain chunks stop at the disc, which on its own leaves a paper-thin sheet:
## from a low camera angle you would look straight through the world. This node
## closes it with three static meshes and no `tick()`:
##
##   * ROCK      — a vertical wall along the whole rim, from the terrain surface down
##                 to the disc's underside. The "nackte Felskante"; it does all the
##                 visible work.
##   * BOTTOM    — a downward-facing cap that closes the slab (user decision: a finite
##                 disc with an underside, not a bottomless wall).
##   * WATERFALL — wherever the rim is under water, a band from the waterline down,
##                 with scrolled UVs so the sea pours off continuously.
##
## ## Built from the mesh's own EXPOSED CELL EDGES, not from a circle
##
## The first version sampled the rim at ~1 m of arc and joined those samples into a
## smooth ring. That was wrong, and visibly so: `Terrain._build_chunk_mesh` culls whole
## CELLS, so the terrain's edge is a staircase that oscillates around the ideal circle
## by up to a cell diagonal. A smooth ring cannot follow it — wherever the staircase
## stuck out past the ring, the cell's cross-section stood open (user report: "Ränder
## von Erhebungen haben keinen Abschluss, sie sind einfach beschnitten").
##
## So the rim is now derived from exactly the same rule the mesh uses: every in-disc
## cell that has a non-disc neighbour contributes one wall quad per exposed side,
## spanning its two real terrain vertex heights. Mesh edge and wall are the same line
## by construction, so there is nothing left to line up.

## Metres of rock below the waterline, i.e. the thickness of the slab.
const SKIRT_DEPTH: float = Balance.WORLD_RIM_SKIRT_DEPTH
## How far the waterfall band hangs below the waterline.
const WATERFALL_HEIGHT: float = Balance.WATERFALL_HEIGHT
## Vertical UV tiling of the waterfall, in metres (matches the shader's `tile`).
const WATERFALL_TILE: float = 8.0
## The rock darkens toward the bottom: multiplier at the very bottom.
const BOTTOM_SHADE: float = 0.35
## The wall is pushed this far OUTWARD along its normal, and each edge is extended by
## the same amount at both ends.
##
## Both halves matter. The offset puts the wall unambiguously in FRONT of the sea's cut
## edge, which is otherwise exactly coplanar with it — that hairline was the middle
## layer of the reported "Torte" (land on top, a strip of water below it, then rock).
## The lengthwise extension closes the notches the offset would otherwise open at
## convex corners of the staircase.
const WALL_OUT: float = 0.06
## The waterfall sits this far outside the wall so the two never fight for depth.
const WATERFALL_OUT: float = 0.05
## A cell counts as submerged (and therefore pours) when its surface is at or below
## this. Slightly above SEA_LEVEL so a cell lapping exactly at the waterline still
## produces a fall instead of a dry gap.
const SUBMERGED_EPS: float = 0.05

var _rock: MeshInstance3D = null
var _bottom: MeshInstance3D = null
var _waterfall: MeshInstance3D = null


# --- Pure geometry (headless-testable) ----------------------------------------------

## The four neighbour offsets, paired with the cell-local edge they expose.
## Each entry is [neighbour offset, edge vertex A, edge vertex B] in cell-vertex space.
const _SIDES: Array = [
	[Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 1)],    # +x
	[Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, 0)],   # -x
	[Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 1)],    # +z
	[Vector2i(0, -1), Vector2i(0, 0), Vector2i(1, 0)],   # -z
]


## Every exposed side of the disc: the boundary of the meshed cell set. Returns an
## array of [cell: Vector2i, side_index: int]. STATIC and pure, so the rim's extent is
## testable without a scene — and it is the SAME predicate the chunk mesh culls on.
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


## True when this cell's surface lies at or below the waterline — i.e. water pours off
## here. Used for the waterfall's extent.
static func cell_is_submerged(td: TerrainData, cell: Vector2i) -> bool:
	if td == null or not td.in_disc(cell):
		return false
	return td.cell_height(cell) <= TerrainData.SEA_LEVEL + SUBMERGED_EPS


## How many of the exposed sides carry a waterfall. Pure, so "the island pours off all
## the way round, the land maps not at all" is headless-testable.
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
	# vertices the wall is built from.
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


## Y the rock wall reaches down to.
static func bottom_y() -> float:
	return TerrainData.SEA_LEVEL - SKIRT_DEPTH


# --- Build --------------------------------------------------------------------------

func rebuild(td: TerrainData) -> void:
	if td == null:
		return
	_ensure_nodes()
	var sides: Array = exposed_sides(td)
	_rock.mesh = _build_wall(td, sides)
	_bottom.mesh = _build_cap(td, sides)
	_waterfall.mesh = _build_waterfall(td, sides)
	_waterfall.visible = _waterfall.mesh != null


## Horizontal UV along the rim: arc length from the map centre's angle, in tiles.
func _rim_u(p: Vector3, center: float) -> float:
	var r: float = Vector2(p.x - center, p.z - center).length()
	return atan2(p.z - center, p.x - center) * r / WATERFALL_TILE


## World position of a cell-vertex, plus its terrain height.
func _vertex_world(td: TerrainData, cell: Vector2i, local: Vector2i) -> Vector3:
	var vx: int = cell.x + local.x
	var vz: int = cell.y + local.y
	return Vector3(float(vx) * TerrainData.CELL_SIZE,
		td.vertex_height(vx, vz), float(vz) * TerrainData.CELL_SIZE)


## The vertical rock wall: one quad per exposed cell side, from the two REAL terrain
## vertex heights of that side down to the slab's bottom.
func _build_wall(td: TerrainData, sides: Array) -> ArrayMesh:
	if sides.is_empty():
		return null
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	var top_col: Color = Terrain.COLOR_ROCK
	var bottom_col: Color = Terrain.COLOR_ROCK * BOTTOM_SHADE
	bottom_col.a = 1.0
	var floor_y: float = bottom_y()
	for entry in sides:
		var cell: Vector2i = entry[0]
		var side: Array = _SIDES[entry[1]]
		var a: Vector3 = _vertex_world(td, cell, side[1])
		var b: Vector3 = _vertex_world(td, cell, side[2])
		var outward: Vector3 = Vector3(float(side[0].x), 0.0, float(side[0].y))
		var along: Vector3 = (b - a)
		along.y = 0.0
		if along.length_squared() > 0.000001:
			along = along.normalized()
		# Pushed out, and stretched at both ends so convex corners stay closed.
		var push: Vector3 = outward * WALL_OUT
		var a_top: Vector3 = a + push - along * WALL_OUT
		var b_top: Vector3 = b + push + along * WALL_OUT
		var base: int = verts.size()
		verts.append(a_top)
		verts.append(b_top)
		verts.append(Vector3(a_top.x, floor_y, a_top.z))
		verts.append(Vector3(b_top.x, floor_y, b_top.z))
		for i in range(4):
			normals.append(outward)
		colors.append(top_col)
		colors.append(top_col)
		colors.append(bottom_col)
		colors.append(bottom_col)
		indices.append(base); indices.append(base + 1); indices.append(base + 2)
		indices.append(base + 1); indices.append(base + 3); indices.append(base + 2)
	return _assemble(verts, normals, colors, indices)


## Downward-facing cap that closes the slab. One triangle per exposed side, fanned to
## the map centre — the staircase boundary is radially monotone around the centre, so a
## fan covers it exactly without needing the edges sorted into a ring.
func _build_cap(td: TerrainData, sides: Array) -> ArrayMesh:
	if sides.is_empty():
		return null
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	var col: Color = Terrain.COLOR_ROCK * BOTTOM_SHADE
	col.a = 1.0
	var floor_y: float = bottom_y()
	var c: float = td.disc_center()
	for entry in sides:
		var cell: Vector2i = entry[0]
		var side: Array = _SIDES[entry[1]]
		var a: Vector3 = _vertex_world(td, cell, side[1])
		var b: Vector3 = _vertex_world(td, cell, side[2])
		var base: int = verts.size()
		verts.append(Vector3(c, floor_y, c))
		verts.append(Vector3(a.x, floor_y, a.z))
		verts.append(Vector3(b.x, floor_y, b.z))
		for i in range(3):
			normals.append(Vector3.DOWN)
			colors.append(col)
		indices.append(base); indices.append(base + 1); indices.append(base + 2)
	return _assemble(verts, normals, colors, indices)


## The waterfall: one quad per exposed side whose cell is under water, from the
## waterline down. Aligned to the very same edge as the sea's cut, so the surface flows
## over the lip instead of stopping short of it.
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
		var outward: Vector3 = Vector3(float(side[0].x), 0.0, float(side[0].y))
		var along: Vector3 = (b - a)
		along.y = 0.0
		if along.length_squared() > 0.000001:
			along = along.normalized()
		var push: Vector3 = outward * (WALL_OUT + WATERFALL_OUT)
		var pa: Vector3 = a + push - along * WALL_OUT
		var pb: Vector3 = b + push + along * WALL_OUT
		# U comes from the ANGLE around the map centre, not from a running total over the
		# sides. `sides` is in cell-scan order, not ring order, so an accumulated run
		# would hand neighbouring quads unrelated streak phases and draw a seam at every
		# cell. The angle is continuous around the whole rim (bar the one quad at ±pi).
		var u0: float = _rim_u(pa, c)
		var u1: float = _rim_u(pb, c)
		if absf(u1 - u0) > TAU * 0.5 * td.disc_radius() / WATERFALL_TILE:
			u1 = u0 + TerrainData.CELL_SIZE / WATERFALL_TILE   # the wrap-around quad
		var base: int = verts.size()
		verts.append(Vector3(pa.x, top_y, pa.z))
		verts.append(Vector3(pb.x, top_y, pb.z))
		verts.append(Vector3(pa.x, floor_y, pa.z))
		verts.append(Vector3(pb.x, floor_y, pb.z))
		for i in range(4):
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
	if _bottom == null:
		_bottom = _make_instance("Bottom", _rock_material())
	if _waterfall == null:
		_waterfall = _make_instance("Waterfall", _waterfall_material())


func _make_instance(node_name: String, mat: Material) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.material_override = mat
	# A wall around the whole map casting through every shadow cascade is pure waste,
	# and the sun never lights the underside anyway.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _rock_material() -> Material:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	# Two-sided: the wall and the cap are a per-edge patchwork rather than one closed
	# hull, so a winding slip must not turn a stretch of rim invisible. A few thousand
	# triangles make the saved culling irrelevant.
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
	return mat
