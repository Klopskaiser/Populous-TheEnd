class_name Terrain extends Node3D

## Renders and collides the TerrainData heightmap.
##
## - Mesh: chunked ArrayMesh (16x16-cell chunks as MeshInstance3D children),
##   built directly via ArrayMesh.add_surface_from_arrays (no SurfaceTool).
##   Vertex colours by height (sand / grass / rock).
## - Collision: one StaticBody3D + HeightMapShape3D, used only for mouse raycasts.
##   HeightMapShape3D is origin-centred with a fixed 1.0 spacing, so the body is
##   offset by (SIZE/2, 0, SIZE/2) to line up with world coordinates [0..SIZE].
## - Water: a semi-transparent PlaneMesh at sea_level.

const CHUNK: int = 16  # cells per chunk side

# Height thresholds for vertex colouring (relative to sea level).
const SAND_TOP: float = TerrainData.SEA_LEVEL + 1.5
const ROCK_BOTTOM: float = TerrainData.SEA_LEVEL + 8.0

const COLOR_SAND: Color = Color(0.83, 0.74, 0.50)
const COLOR_GRASS: Color = Color(0.29, 0.55, 0.24)
const COLOR_ROCK: Color = Color(0.45, 0.44, 0.42)

var data: TerrainData = null

var _chunks_root: Node3D = null
var _static_body: StaticBody3D = null
var _collision_shape: CollisionShape3D = null
var _height_shape: HeightMapShape3D = null
var _material: StandardMaterial3D = null
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
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 1.0

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


func _ensure_water() -> void:
	if has_node("Water"):
		return
	var water: MeshInstance3D = MeshInstance3D.new()
	water.name = "Water"
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(data.size, data.size)
	water.mesh = plane
	water.position = Vector3(data.size * 0.5, TerrainData.SEA_LEVEL, data.size * 0.5)
	var wmat: StandardMaterial3D = StandardMaterial3D.new()
	wmat.albedo_color = Color(0.15, 0.35, 0.6, 0.55)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.metallic = 0.2
	wmat.roughness = 0.1
	water.material_override = wmat
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
			verts[idx] = Vector3(float(gx) * TerrainData.CELL_SIZE, h, float(gz) * TerrainData.CELL_SIZE)
			normals[idx] = _normal_at(gx, gz)
			colors[idx] = _color_for_height(h)

	# Godot front faces use CLOCKWISE winding (seen from the front, here: +Y above).
	for lz in range(d - 1):
		for lx in range(w - 1):
			var tl: int = lz * w + lx
			var tr: int = tl + 1
			var bl: int = (lz + 1) * w + lx
			var br: int = bl + 1
			indices.append(tl); indices.append(tr); indices.append(bl)
			indices.append(tr); indices.append(br); indices.append(bl)

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
