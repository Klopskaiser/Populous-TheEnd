class_name TerrainRim extends Node3D

## Phase 10j — the edge of the Scheibenwelt.
##
## The terrain chunks stop at the disc, which on its own leaves a paper-thin sheet:
## from a low camera angle you would look straight through the world. This node
## closes it with three static meshes and no `tick()` at all:
##
##   * ROCK    — a vertical band from the rim height down to the disc's underside.
##               This is the "nackte Felskante" the user asked for and it does all
##               the visible work.
##   * BOTTOM  — a downward-facing cap that closes the slab (user decision: a finite
##               disc with an underside, not a bottomless wall). With the camera
##               pitch fixed at -55 degrees and the rig floored at sea level it is
##               effectively never in shot; it exists so the mesh is closed if the
##               pitch is ever made adjustable, and it costs one fan of triangles.
##   * WATERFALL — only across the stretches where the rim lies below the waterline
##               (today that is the island, all the way round). Scrolled UVs, one
##               draw call, in front of the rock so the two never z-fight.
##
## All three are rebuilt together from `rebuild()`, which `Terrain.apply_deformation`
## calls when a deformation reaches the rim — a Sink at the edge can create new water
## and with it a new stretch of waterfall.

## Metres of rock below the rim, i.e. the thickness of the slab.
const SKIRT_DEPTH: float = Balance.WORLD_RIM_SKIRT_DEPTH
## How far the waterfall band hangs below the waterline.
const WATERFALL_HEIGHT: float = Balance.WATERFALL_HEIGHT
## Target arc length of one rim segment, in metres. ~1 m gives 452 segments on a 144
## map and 905 on a 288 one — under 2k triangles for the whole rim.
const SEGMENT_ARC: float = 1.0
## The rock band sits a hair inside the disc radius so its top samples real terrain;
## the waterfall sits a hair outside it so it never fights the rock for depth.
const ROCK_INSET: float = 0.01
const WATERFALL_OFFSET: float = 0.02
## Vertical UV tiling of the waterfall, in metres (matches the shader's `tile`).
const WATERFALL_TILE: float = 8.0
## The rock darkens toward the bottom: this is the multiplier at the very bottom.
const BOTTOM_SHADE: float = 0.35

var _rock: MeshInstance3D = null
var _bottom: MeshInstance3D = null
var _waterfall: MeshInstance3D = null


## True when the rim lies below the waterline at this angular sample — i.e. water
## pours off here. STATIC and pure so it is testable without a scene.
static func segment_is_submerged(td: TerrainData, angle: float) -> bool:
	if td == null:
		return false
	var c: float = td.disc_center()
	var r: float = td.disc_radius() - ROCK_INSET
	var x: float = c + cos(angle) * r
	var z: float = c + sin(angle) * r
	return td.get_height(x, z) <= TerrainData.SEA_LEVEL


## How many angular samples the rim of this map is built from.
static func segment_count(td: TerrainData) -> int:
	if td == null:
		return 0
	return maxi(int(ceil(TAU * td.disc_radius() / SEGMENT_ARC)), 8)


## Indices of the samples where water pours off — the waterfall's extent. Pure, so
## the "island has a full ring, the land maps have none" rule is headless-testable.
static func waterfall_segments(td: TerrainData) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if td == null:
		return out
	var n: int = segment_count(td)
	for i in range(n):
		if segment_is_submerged(td, TAU * float(i) / float(n)):
			out.append(i)
	return out


## True when a deformed cell rectangle comes close enough to the rim to change it.
static func touches_rim(td: TerrainData, rect: Rect2i) -> bool:
	if td == null:
		return false
	var c: float = td.disc_center()
	var r: float = td.disc_radius()
	# Nearest and farthest corner distances of the rect from the disc centre: the
	# rect matters when the rim ring passes between them.
	var near_x: float = maxf(0.0, maxf(float(rect.position.x) - c,
		c - float(rect.position.x + rect.size.x)))
	var near_z: float = maxf(0.0, maxf(float(rect.position.y) - c,
		c - float(rect.position.y + rect.size.y)))
	var near: float = sqrt(near_x * near_x + near_z * near_z)
	var far_x: float = maxf(absf(float(rect.position.x) - c),
		absf(float(rect.position.x + rect.size.x) - c))
	var far_z: float = maxf(absf(float(rect.position.y) - c),
		absf(float(rect.position.y + rect.size.y) - c))
	var far: float = sqrt(far_x * far_x + far_z * far_z)
	return near <= r + 2.0 and far >= r - 2.0


## The Y the rock band starts at for a given rim height. Lifted to the waterline
## where the rim is submerged: without this there would be a visible GAP between the
## cut edge of the water plane and the top of the rock.
static func rock_top_y(rim_height: float) -> float:
	return maxf(rim_height, TerrainData.SEA_LEVEL)


func rebuild(td: TerrainData) -> void:
	if td == null:
		return
	_ensure_nodes()
	var n: int = segment_count(td)
	var c: float = td.disc_center()
	var rock_r: float = td.disc_radius() - ROCK_INSET
	var fall_r: float = td.disc_radius() + WATERFALL_OFFSET

	# Sample the rim once; both bands and the cap reuse it.
	var dirs: PackedVector2Array = PackedVector2Array()
	var tops: PackedFloat32Array = PackedFloat32Array()
	var wet: PackedByteArray = PackedByteArray()
	dirs.resize(n)
	tops.resize(n)
	wet.resize(n)
	for i in range(n):
		var a: float = TAU * float(i) / float(n)
		var dir: Vector2 = Vector2(cos(a), sin(a))
		dirs[i] = dir
		var h: float = td.get_height(c + dir.x * rock_r, c + dir.y * rock_r)
		tops[i] = rock_top_y(h)
		wet[i] = 1 if h <= TerrainData.SEA_LEVEL else 0

	var bottom_y: float = TerrainData.SEA_LEVEL - SKIRT_DEPTH
	_rock.mesh = _build_band(dirs, tops, c, rock_r, bottom_y, true)
	_bottom.mesh = _build_cap(dirs, c, rock_r, bottom_y)
	_waterfall.mesh = _build_waterfall(dirs, wet, c, fall_r)
	_waterfall.visible = _waterfall.mesh != null


# --- Mesh construction --------------------------------------------------------------

## Vertical band around the rim, from `tops[i]` down to `bottom_y`. Wraps closed.
## `shade` darkens the lower edge so the drop reads as depth for free.
func _build_band(dirs: PackedVector2Array, tops: PackedFloat32Array,
		c: float, radius: float, bottom_y: float, shade: bool) -> ArrayMesh:
	var n: int = dirs.size()
	if n < 3:
		return null
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	var rock_top: Color = Terrain.COLOR_ROCK
	var rock_bottom: Color = Terrain.COLOR_ROCK * BOTTOM_SHADE if shade \
		else Terrain.COLOR_ROCK
	rock_bottom.a = 1.0
	for i in range(n):
		var dir: Vector2 = dirs[i]
		var outward: Vector3 = Vector3(dir.x, 0.0, dir.y)
		verts.append(Vector3(c + dir.x * radius, tops[i], c + dir.y * radius))
		verts.append(Vector3(c + dir.x * radius, bottom_y, c + dir.y * radius))
		normals.append(outward)
		normals.append(outward)
		colors.append(rock_top)
		colors.append(rock_bottom)
	for i in range(n):
		var a0: int = i * 2
		var a1: int = a0 + 1
		var b0: int = ((i + 1) % n) * 2
		var b1: int = b0 + 1
		# Clockwise seen from outside (+outward), matching Godot's front faces.
		indices.append(a0); indices.append(b0); indices.append(a1)
		indices.append(b0); indices.append(b1); indices.append(a1)
	return _assemble(verts, normals, colors, indices)


## Downward-facing disc that closes the slab (the user's "endliche Scheibe mit
## geschlossener Unterseite"). A triangle fan around a centre vertex.
func _build_cap(dirs: PackedVector2Array, c: float, radius: float,
		bottom_y: float) -> ArrayMesh:
	var n: int = dirs.size()
	if n < 3:
		return null
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	var under: Color = Terrain.COLOR_ROCK * BOTTOM_SHADE
	under.a = 1.0
	verts.append(Vector3(c, bottom_y, c))
	normals.append(Vector3.DOWN)
	colors.append(under)
	for i in range(n):
		var dir: Vector2 = dirs[i]
		verts.append(Vector3(c + dir.x * radius, bottom_y, c + dir.y * radius))
		normals.append(Vector3.DOWN)
		colors.append(under)
	for i in range(n):
		var a: int = 1 + i
		var b: int = 1 + (i + 1) % n
		# Wound so the face points DOWN (seen from below it is clockwise).
		indices.append(0); indices.append(a); indices.append(b)
	return _assemble(verts, normals, colors, indices)


## The waterfall band: only the runs of submerged samples become geometry, so a map
## with a dry rim produces no mesh at all (and no draw call).
func _build_waterfall(dirs: PackedVector2Array, wet: PackedByteArray,
		c: float, radius: float) -> ArrayMesh:
	var n: int = dirs.size()
	if n < 3:
		return null
	var top_y: float = TerrainData.SEA_LEVEL + Terrain.WATER_SURFACE_LIFT
	var bottom_y: float = TerrainData.SEA_LEVEL - WATERFALL_HEIGHT
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var arc: float = TAU * radius / float(n)
	var v_max: float = WATERFALL_HEIGHT / WATERFALL_TILE
	var any: bool = false
	for i in range(n):
		var j: int = (i + 1) % n
		if wet[i] == 0 or wet[j] == 0:
			continue   # only spans whose BOTH ends are under water get a quad
		any = true
		var base: int = verts.size()
		for k in [i, j]:
			var dir: Vector2 = dirs[k]
			var outward: Vector3 = Vector3(dir.x, 0.0, dir.y)
			verts.append(Vector3(c + dir.x * radius, top_y, c + dir.y * radius))
			verts.append(Vector3(c + dir.x * radius, bottom_y, c + dir.y * radius))
			normals.append(outward)
			normals.append(outward)
			var u: float = float(k) * arc / WATERFALL_TILE
			uvs.append(Vector2(u, 0.0))
			uvs.append(Vector2(u, v_max))
		indices.append(base); indices.append(base + 2); indices.append(base + 1)
		indices.append(base + 2); indices.append(base + 3); indices.append(base + 1)
	if not any:
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
	# A 40 m band around the whole map casting through every shadow cascade is pure
	# waste — and the sun never lights the underside anyway.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _rock_material() -> Material:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
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
