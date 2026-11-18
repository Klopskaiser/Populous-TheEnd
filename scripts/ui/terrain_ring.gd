class_name TerrainRing

## Helper for drawing range circles that HUG the terrain instead of a flat
## disc that sinks into hills (user request). Adds one thin ring band to an
## ImmediateMesh: the vertices are sampled around the circle and each is
## lifted to the terrain height at that point (+ a small offset), so the ring
## follows slopes. Vertices are in WORLD space — the owning MeshInstance3D
## must sit at the origin. Colours are per-vertex (material:
## vertex_color_use_as_albedo).

const SEGMENTS: int = 64
const THICKNESS: float = 0.25
const Y_OFFSET: float = 0.12


## Appends a terrain-conforming ring band (radius `radius` around `center`) as
## one triangle-strip surface. No-op for a non-positive radius.
static func add_band(im: ImmediateMesh, center: Vector3, radius: float,
		td: TerrainData, color: Color, thickness: float = THICKNESS,
		y_offset: float = Y_OFFSET, segments: int = SEGMENTS) -> void:
	if radius <= 0.0:
		return
	var r_in: float = maxf(radius - thickness, 0.02)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(segments + 1):
		var a: float = TAU * float(i) / float(segments)
		var cx: float = cos(a)
		var sz: float = sin(a)
		var xo: float = center.x + cx * radius
		var zo: float = center.z + sz * radius
		var xi: float = center.x + cx * r_in
		var zi: float = center.z + sz * r_in
		var yo: float = (td.get_height(xo, zo) if td != null else center.y) + y_offset
		var yi: float = (td.get_height(xi, zi) if td != null else center.y) + y_offset
		im.surface_set_color(color)
		im.surface_add_vertex(Vector3(xo, yo, zo))
		im.surface_set_color(color)
		im.surface_add_vertex(Vector3(xi, yi, zi))
	im.surface_end()


## Batched variant for drawing MANY rings into a single, already-open surface
## (Mesh.PRIMITIVE_TRIANGLES) — used by RangeRenderer so an army-sized range
## display never allocates one mesh surface per ring. add_band's own
## surface_begin/surface_end per call used to add a fresh SURFACE per ring;
## with a big army (hundreds of firewarriors/preachers/siege units, some
## drawing two rings) that blew past Godot's per-mesh surface cap and spammed
## "mesh->surface_count == MAX_MESH_SURFACES" (user bug). Caller opens
## im.surface_begin(Mesh.PRIMITIVE_TRIANGLES) once, adds any number of rings
## via this function, then calls surface_end() once. No-op for a
## non-positive radius (mirrors add_band).
static func add_band_triangles(im: ImmediateMesh, center: Vector3, radius: float,
		td: TerrainData, color: Color, thickness: float = THICKNESS,
		y_offset: float = Y_OFFSET, segments: int = SEGMENTS) -> void:
	if radius <= 0.0:
		return
	var r_in: float = maxf(radius - thickness, 0.02)
	var prev_outer: Vector3 = Vector3.ZERO
	var prev_inner: Vector3 = Vector3.ZERO
	var have_prev: bool = false
	for i in range(segments + 1):
		var a: float = TAU * float(i) / float(segments)
		var cx: float = cos(a)
		var sz: float = sin(a)
		var xo: float = center.x + cx * radius
		var zo: float = center.z + sz * radius
		var xi: float = center.x + cx * r_in
		var zi: float = center.z + sz * r_in
		var yo: float = (td.get_height(xo, zo) if td != null else center.y) + y_offset
		var yi: float = (td.get_height(xi, zi) if td != null else center.y) + y_offset
		var outer: Vector3 = Vector3(xo, yo, zo)
		var inner: Vector3 = Vector3(xi, yi, zi)
		if have_prev:
			_add_quad_triangles(im, color, prev_outer, prev_inner, outer, inner)
		prev_outer = outer
		prev_inner = inner
		have_prev = true


## Batched polyline band (same contract as add_band_triangles: the caller has the surface open):
## the flat outline `pts` (x, y = world x, z), closed when `closed`, drawn `thickness` wide and
## lifted onto the terrain — every segment is sampled at most `step` metres apart, so long
## outlines follow the ground too. Used by the sit-zone debug view (RangeRenderer, key G).
static func add_path_triangles(im: ImmediateMesh, pts: PackedVector2Array, td: TerrainData,
		color: Color, thickness: float = THICKNESS, closed: bool = true, y_offset: float = Y_OFFSET,
		step: float = 1.0) -> void:
	var n: int = pts.size()
	if n < 2:
		return
	var segs: int = n if closed else n - 1
	var half: float = thickness * 0.5
	for i in range(segs):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var d: Vector2 = b - a
		var length: float = d.length()
		if length < 0.0001:
			continue
		var side: Vector2 = Vector2(-d.y, d.x) / length * half
		var parts: int = maxi(1, int(ceil(length / step)))
		for k in range(parts):
			var p0: Vector2 = a + d * (float(k) / float(parts))
			var p1: Vector2 = a + d * (float(k + 1) / float(parts))
			_add_quad_triangles(im, color, _on_ground(p0 + side, td, y_offset), _on_ground(p0 - side, td, y_offset),
				_on_ground(p1 + side, td, y_offset), _on_ground(p1 - side, td, y_offset))


static func _on_ground(p: Vector2, td: TerrainData, y_offset: float) -> Vector3:
	return Vector3(p.x, (td.get_height(p.x, p.y) if td != null else 0.0) + y_offset, p.y)


## One ring segment's trapezoid (o0-i0-o1-i1) as two independent triangles —
## matches the winding add_band's triangle-strip produces, but needs no
## adjacency to neighbouring rings (safe to batch unrelated rings together).
static func _add_quad_triangles(im: ImmediateMesh, color: Color, o0: Vector3,
		i0: Vector3, o1: Vector3, i1: Vector3) -> void:
	for v in [o0, i0, o1, i0, i1, o1]:
		im.surface_set_color(color)
		im.surface_add_vertex(v)


## Standard unshaded, alpha-blended, per-vertex-colour material for the rings.
static func make_material() -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
