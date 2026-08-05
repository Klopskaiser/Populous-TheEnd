class_name Terrain extends Node3D

## Renders and collides the TerrainData heightmap.
##
## - Mesh: chunked ArrayMesh (16x16-cell chunks as MeshInstance3D children),
##   built directly via ArrayMesh.add_surface_from_arrays (no SurfaceTool).
##   Vertex colours by height (sand / grass / rock).
## - Collision: one StaticBody3D + HeightMapShape3D, used only for mouse raycasts.
##   HeightMapShape3D is origin-centred with a fixed 1.0 spacing, so the body is
##   offset by (SIZE/2, 0, SIZE/2) to line up with world coordinates [0..SIZE].
## - Water: an OPAQUE deep-blue PlaneMesh at sea_level (Populous style — there is
##   no sea floor to look at, it is simply water). The seabed geometry still
##   exists (get_height, HeightMapShape3D raycasts and every terrain spell need
##   it), it is just never visible.

const CHUNK: int = 16  # cells per chunk side

# Height thresholds for vertex colouring — the shared grass band from
# TerrainData (also drives the tree-type gameplay rules).
const SAND_TOP: float = TerrainData.GRASS_MIN
const ROCK_BOTTOM: float = TerrainData.GRASS_MAX

const COLOR_SAND: Color = Color(0.83, 0.74, 0.50)
const COLOR_GRASS: Color = Color(0.29, 0.55, 0.24)
const COLOR_ROCK: Color = Color(0.45, 0.44, 0.42)

## Deep, opaque Populous blue plus the lighter crest tint the water shader
## ripples towards.
const COLOR_WATER: Color = Color(0.055, 0.16, 0.40)
const COLOR_WATER_HIGHLIGHT: Color = Color(0.13, 0.30, 0.58)
## The sea plane sits this far ABOVE sea level. It keeps the plane out of the
## coplanar z-fight with terrain that a Flatten/Sink spell levelled exactly onto
## SEA_LEVEL, and it lines the visible waterline up with the gameplay water
## threshold (SEA_LEVEL + Unit.WATER_EPS).
const WATER_SURFACE_LIFT: float = 0.03
## Target edge length (metres) of one water-plane subdivision cell. The waves are
## a vertex displacement, so the sea needs geometry — but only enough to resolve
## an ~18 m swell smoothly.
const WATER_WAVE_CELL: float = 2.0
## Wet, darker sand right at the waterline; fades into COLOR_SAND over
## SHORE_BAND metres. Vertex colours are computed during the chunk build
## anyway, so the shore costs nothing at runtime.
const COLOR_SHORE: Color = Color(0.62, 0.55, 0.38)
const SHORE_BAND: float = 0.9
## Terrain more than this far below the sea line is not meshed at all — the sea
## is opaque and has no modelled depth, so the seabed can never be seen. The
## margin is far larger than the wave trough, so nothing shows through.
const SEABED_CULL_MARGIN: float = 0.6

var data: TerrainData = null

var _chunks_root: Node3D = null
var _static_body: StaticBody3D = null
var _collision_shape: CollisionShape3D = null
var _height_shape: HeightMapShape3D = null
var _material: Material = null
var _rim: TerrainRim = null
var _chunk_count: int = TerrainData.SIZE / CHUNK  # chunks per side


## Builds the whole terrain from the given data. Call once at startup.
func build(p_data: TerrainData) -> void:
	data = p_data
	_chunk_count = data.size / CHUNK   # map-driven (128 -> 8, 256 -> 16)
	_ensure_nodes()
	_build_all_chunks()
	update_collision()


func _ensure_nodes() -> void:
	if _material == null:
		_material = _create_material()

	if _chunks_root == null:
		_chunks_root = Node3D.new()
		_chunks_root.name = "Chunks"
		add_child(_chunks_root)

	if _static_body == null:
		_static_body = StaticBody3D.new()
		_static_body.name = "TerrainBody"
		# HeightMapShape3D is origin-centred -> shift to cover world [0..size].
		_static_body.position = Vector3(data.size * 0.5, 0.0, data.size * 0.5)
		add_child(_static_body)
		_collision_shape = CollisionShape3D.new()
		_static_body.add_child(_collision_shape)
		_height_shape = HeightMapShape3D.new()
		_height_shape.map_width = data.verts
		_height_shape.map_depth = data.verts
		_collision_shape.shape = _height_shape

	_ensure_water()

	if _rim == null:
		# The disc's edge (phase 10j): rock band + closed underside + waterfall.
		# Static meshes, no tick — see TerrainRim.
		_rim = TerrainRim.new()
		_rim.name = "Rim"
		add_child(_rim)
	_rim.rebuild(data)


## Textured triplanar shader when all three ground textures exist under
## assets/textures/terrain/, otherwise the vertex-colour placeholder material.
## Vertex colours are always generated (fallback + soft tint input for the
## shader), so the chunk builder is identical in both modes.
func _create_material() -> Material:
	var sand: Texture2D = AssetLibrary.texture("textures/terrain/sand.png")
	var grass: Texture2D = AssetLibrary.texture("textures/terrain/grass.png")
	var rock: Texture2D = AssetLibrary.texture("textures/terrain/rock.png")
	if sand != null and grass != null and rock != null:
		var shader_mat: ShaderMaterial = ShaderMaterial.new()
		shader_mat.shader = preload("res://shaders/terrain_triplanar.gdshader")
		shader_mat.set_shader_parameter("sand_tex", sand)
		shader_mat.set_shader_parameter("grass_tex", grass)
		shader_mat.set_shader_parameter("rock_tex", rock)
		shader_mat.set_shader_parameter("sand_top", SAND_TOP)
		shader_mat.set_shader_parameter("rock_bottom", ROCK_BOTTOM)
		return shader_mat
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	return mat


## The sea: one OPAQUE plane. Nothing below it is ever seen, which is exactly
## what makes a drowned unit disappear (it sinks through the surface) without
## any extra renderer work. Opaque is also cheaper than the old alpha-blended
## plane — it leaves the transparent pass and stops the seabed being overdrawn.
func _ensure_water() -> void:
	if has_node("Water"):
		return
	var water: MeshInstance3D = MeshInstance3D.new()
	water.name = "Water"
	# A map-sized plane casting through all shadow cascades is pure waste.
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(data.size, data.size)
	water.mesh = plane
	water.position = Vector3(
		data.size * 0.5, TerrainData.SEA_LEVEL + WATER_SURFACE_LIFT, data.size * 0.5)
	# The wave shader displaces vertices, so the plane needs geometry. One vertex per
	# WATER_WAVE_CELL metres — far finer than the ~18 m swell, far coarser than the
	# terrain (a 144 map gets 72x72 verts).
	var subdiv: int = clampi(int(float(data.size) / WATER_WAVE_CELL), 16, 160)
	plane.subdivide_width = subdiv
	plane.subdivide_depth = subdiv
	# ONE material path (phase 10j). The sea has to be cut to the disc, and only a
	# shader can discard — the old StandardMaterial3D texture variant would have left
	# square water hanging over the void. The texture is fed INTO the shader instead.
	var smat: ShaderMaterial = ShaderMaterial.new()
	smat.shader = preload("res://shaders/water.gdshader")
	smat.set_shader_parameter("deep", Vector3(
		COLOR_WATER.r, COLOR_WATER.g, COLOR_WATER.b))
	smat.set_shader_parameter("crest", Vector3(
		COLOR_WATER_HIGHLIGHT.r, COLOR_WATER_HIGHLIGHT.g, COLOR_WATER_HIGHLIGHT.b))
	smat.set_shader_parameter("disc_center",
		Vector2(data.disc_center(), data.disc_center()))
	# The land's mesh edge is now an inscribed polygon of exactly this circle, so a
	# radial cut matches it (bar a ~2 mm sagitta, which the rock flank's outward push
	# covers). The cell-mask cut this replaces was right only while the land was a
	# staircase.
	smat.set_shader_parameter("disc_radius", data.rim_radius())
	var water_tex: Texture2D = AssetLibrary.texture("textures/terrain/water.png")
	if water_tex != null:
		smat.set_shader_parameter("albedo_tex", water_tex)
		smat.set_shader_parameter("use_tex", true)
		smat.set_shader_parameter("uv_scale", float(data.size) * 0.05)
	water.material_override = smat
	add_child(water)


# --- Mesh building -----------------------------------------------------------

func _build_all_chunks() -> void:
	for cz in range(_chunk_count):
		for cx in range(_chunk_count):
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [cx, cz]
			mi.material_override = _material
			_chunks_root.add_child(mi)
			_build_chunk_mesh(cx, cz, mi)


func _chunk_node(cx: int, cz: int) -> MeshInstance3D:
	return _chunks_root.get_node_or_null("Chunk_%d_%d" % [cx, cz]) as MeshInstance3D


func _color_for_height(h: float) -> Color:
	if h < TerrainData.SEA_LEVEL + SHORE_BAND:
		# Wet sand at the waterline, fading into dry sand — gives the opaque sea
		# a readable shore instead of a hard colour cut.
		return COLOR_SHORE.lerp(COLOR_SAND, clampf(
			(h - TerrainData.SEA_LEVEL) / SHORE_BAND, 0.0, 1.0))
	if h < SAND_TOP:
		return COLOR_SAND
	elif h < ROCK_BOTTOM:
		var t: float = (h - SAND_TOP) / (ROCK_BOTTOM - SAND_TOP)
		return COLOR_SAND.lerp(COLOR_GRASS, clampf(t * 2.0, 0.0, 1.0))
	else:
		return COLOR_GRASS.lerp(COLOR_ROCK, clampf((h - ROCK_BOTTOM) / 6.0, 0.0, 1.0))


## Central-difference normal at a vertex from the heightmap.
func _normal_at(x: int, z: int) -> Vector3:
	var hl: float = data.vertex_height(x - 1, z)
	var hr: float = data.vertex_height(x + 1, z)
	var hd: float = data.vertex_height(x, z - 1)
	var hu: float = data.vertex_height(x, z + 1)
	return Vector3(hl - hr, 2.0 * TerrainData.CELL_SIZE, hd - hu).normalized()


func _build_chunk_mesh(cx: int, cz: int, mi: MeshInstance3D) -> void:
	var x0: int = cx * CHUNK
	var z0: int = cz * CHUNK
	var x1: int = mini(x0 + CHUNK, data.size)  # inclusive vertex range end
	var z1: int = mini(z0 + CHUNK, data.size)
	var w: int = x1 - x0 + 1  # vertices along x
	var d: int = z1 - z0 + 1  # vertices along z

	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	verts.resize(w * d)
	normals.resize(w * d)
	colors.resize(w * d)

	for lz in range(d):
		for lx in range(w):
			var gx: int = x0 + lx
			var gz: int = z0 + lz
			var h: float = data.vertex_height(gx, gz)
			var idx: int = lz * w + lx
			# XZ is pulled onto the rim circle where it would stick out (phase 10j):
			# cell culling alone leaves a one-metre staircase, which reads as coarse
			# jags. The height is the unsnapped grid height either way.
			var xz: Vector2 = data.vertex_mesh_xz(gx, gz)
			verts[idx] = Vector3(xz.x, h, xz.y)
			normals[idx] = _normal_at(gx, gz)
			colors[idx] = _color_for_height(h)

	# Godot front faces use CLOCKWISE winding (seen from the front, here: +Y above).
	# Cells that lie entirely under the (opaque, depthless) sea are skipped: they
	# can never be seen, so drawing them is pure overdraw. SEABED_CULL_MARGIN
	# keeps a band of terrain around the waterline so no gap opens under the
	# wave troughs. Vertices stay in the buffer, only the index list shrinks —
	# the index arithmetic is unchanged, and rebuild_chunks re-evaluates this
	# after every deformation (a landbridge brings its cells straight back).
	var cull_below: float = TerrainData.SEA_LEVEL - SEABED_CULL_MARGIN
	for lz in range(d - 1):
		for lx in range(w - 1):
			var tl: int = lz * w + lx
			var tr: int = tl + 1
			var bl: int = (lz + 1) * w + lx
			var br: int = bl + 1
			# A quad IS a cell, and outside the disc there is no cell (phase 10j).
			# Asking data.in_disc() instead of re-deriving the circle here keeps the
			# visible edge and the walkable edge the same thing by construction.
			if not data.in_disc(Vector2i(x0 + lx, z0 + lz)):
				continue
			if verts[tl].y < cull_below and verts[tr].y < cull_below \
					and verts[bl].y < cull_below and verts[br].y < cull_below:
				continue
			indices.append(tl); indices.append(tr); indices.append(bl)
			indices.append(tr); indices.append(br); indices.append(bl)

	if indices.is_empty():
		mi.mesh = null   # chunk is entirely open sea, or entirely void
		return

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = mesh


# --- Deformation hooks -------------------------------------------------------

## Rebuilds only the chunks touched by the given cell rectangle.
func rebuild_chunks(rect: Rect2i) -> void:
	if data == null:
		return
	var cx0: int = clampi(rect.position.x / CHUNK, 0, _chunk_count - 1)
	var cz0: int = clampi(rect.position.y / CHUNK, 0, _chunk_count - 1)
	var cx1: int = clampi((rect.position.x + rect.size.x - 1) / CHUNK, 0, _chunk_count - 1)
	var cz1: int = clampi((rect.position.y + rect.size.y - 1) / CHUNK, 0, _chunk_count - 1)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var mi: MeshInstance3D = _chunk_node(cx, cz)
			if mi != null:
				_build_chunk_mesh(cx, cz, mi)


## Re-uploads the whole heightmap to the collision shape.
func update_collision() -> void:
	if _height_shape != null and data != null:
		_height_shape.map_data = data.heights


## Applies a deformation: rebuilds affected chunk meshes and refreshes collision.
func apply_deformation(rect: Rect2i) -> void:
	rebuild_chunks(rect)
	update_collision()
	# The rim skirt samples the terrain height along the edge, so a deformation that
	# reaches the rim changes it — and a Sink out there can create new water, and with
	# it a new stretch of waterfall. Rare enough that a full rim rebuild is fine.
	if _rim != null and TerrainRim.touches_rim(data, rect):
		_rim.rebuild(data)
