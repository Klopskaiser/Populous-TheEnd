class_name TornadoVisual extends Node3D

## What a TornadoVortex looks like (in-tree only, no game logic): a funnel of
## scrolling streaks instead of the stack of static rings it replaced.
##
## Four draw calls per twister, nothing ticked per frame once it stands:
##   core   - the dense inner funnel
##   veil   - a faint outer layer whose mouth is EXACTLY the catch radius at the
##            tip (TornadoVortex.TOP_WIDEN), like the old top ring
##   dust   - a low skirt of kicked-up dust around the foot
##   specks - a MultiMesh of small bits spiralling up (orbit computed in the shader)
## All motion lives in shaders/tornado_funnel.gdshader / tornado_specks.gdshader.
## The meshes are built once in unit size and shared by every twister; a funnel
## only differs in its node scale (x/z = radius, y = height), so the Supertornado
## is the same picture, bigger.
##
## WHIRLED-UP UNITS STAY READABLE (user spec). Riders fly on
## 0.8 * TornadoVortex.radius_at_height(h), i.e. 0.8 r at the ground and 1.36 r at
## the tip. The CORE therefore stays inside that circle at every height (at most
## 0.7 of it: CORE_R_TOP = 0.95 against 1.36), so a rider is only ever dimmed while
## it passes straight behind the core. The only layer that can lie in FRONT of a
## rider is the veil's near wall, and that is held at VEIL_ALPHA * VEIL_NEAR_SHARE
## while its far wall carries the shape. Keep both rules when retuning the look.
##
## No randf() anywhere: the per-twister phase and the speck layout are hashed, so
## the seeded test RNG stream is untouched (same rule as UnitRenderer.idle_frame).

const FUNNEL_SHADER: Shader = preload("res://shaders/tornado_funnel.gdshader")
const SPECK_SHADER: Shader = preload("res://shaders/tornado_specks.gdshader")

## Mesh resolution of one layer: 24 x 12 quads = 576 triangles.
const SEGMENTS: int = 24
const ROWS: int = 12

## Funnel profiles in mesh units (1 = the vortex radius): radius at the ground,
## at the far end, and the exponent of the flare in between.
const CORE_R_BASE: float = 0.14
const CORE_R_TOP: float = 0.95
const CORE_FLARE: float = 1.3
const VEIL_R_BASE: float = 0.3
const VEIL_FLARE: float = 1.45
## Dust skirt: from wide and flat at the ground to narrow at DUST_HEIGHT (in
## radii — the skirt does not grow with the funnel height).
const DUST_R_OUTER: float = 1.55
const DUST_R_INNER: float = 0.22
const DUST_HEIGHT: float = 0.6

## Opacity of the densest streak per layer.
const CORE_ALPHA: float = 0.85
## The veil's FAR wall (behind everything that flies inside it) and the share of
## that its NEAR wall keeps: 0.55 * 0.5 = 0.275 in front of a rider at most.
const VEIL_ALPHA: float = 0.55
const VEIL_NEAR_SHARE: float = 0.5
const DUST_ALPHA: float = 0.6

## Reference size the pattern is tuned for (the plain tornado). Bigger funnels
## get proportionally more streaks and turn slower, so the streaks keep their
## size and the Supertornado reads as heavier rather than as a zoomed-in tornado.
const REF_RADIUS: float = 2.2
const REF_HEIGHT: float = 8.0
## Revolutions per second of the pattern at REF_RADIUS.
const CORE_REVS: float = 0.9
const VEIL_REVS: float = 0.55
const DUST_REVS: float = 0.7

const SPECK_COUNT: int = 26
## Seconds the funnel takes to rise out of the ground, and to dissolve once the
## vortex is over (dissipate()).
const GROW_TIME: float = 0.7
const FADE_TIME: float = 0.6
## How much wider the funnel gets while it dissolves.
const FADE_WIDEN: float = 0.35

static var _mesh_cache: Dictionary = {}

var _materials: Array[ShaderMaterial] = []
var _age: float = 0.0
var _fading: bool = false
var _fade: float = 0.0
var _base_scale: Vector3 = Vector3.ONE


## Builds the layers for a funnel of `radius` (ground) and `top_height`. `at`
## only seeds the per-twister phase.
func setup(radius: float, top_height: float, at: Vector3) -> void:
	var phase: float = fposmod(at.x * 12.9898 + at.z * 78.233, TAU)
	var size_factor: float = radius / REF_RADIUS
	var height_factor: float = top_height / REF_HEIGHT
	var slow: float = 1.0 / sqrt(maxf(size_factor, 0.01))
	var funnel_scale: Vector3 = Vector3(radius, top_height, radius)
	var core_streaks: float = maxf(roundf(4.0 * size_factor), 2.0)
	var veil_streaks: float = maxf(roundf(4.0 * size_factor), 2.0)
	var dust_streaks: float = maxf(roundf(4.0 * size_factor), 2.0)

	_add_layer(_funnel_mesh(DUST_R_OUTER, DUST_R_INNER, 1.0, 0.03, DUST_HEIGHT),
		Vector3(radius, radius, radius), -1, {
			"tint": Color(0.62, 0.56, 0.47), "tint_low": Color(0.56, 0.5, 0.41),
			"low_reach": 0.5, "max_alpha": DUST_ALPHA, "coverage": 0.5,
			"fill": 0.12, "edge": 0.14,
			"streaks": dust_streaks, "tile_v": 2.5, "twist": 1.6,
			"spin": DUST_REVS * slow * dust_streaks, "rise": 0.5, "sway": 0.0,
			"fade_bottom": 0.3, "fade_top": 0.4, "phase": phase,
		})
	_add_layer(_funnel_mesh(CORE_R_BASE, CORE_R_TOP, CORE_FLARE, 0.0, 1.0),
		funnel_scale, 0, {
			"tint": Color(0.74, 0.76, 0.82), "max_alpha": CORE_ALPHA, "coverage": 0.5,
			"fill": 0.5, "edge": 0.07,
			"streaks": core_streaks, "tile_v": 9.0 * height_factor, "twist": 3.0,
			"spin": CORE_REVS * slow * core_streaks, "rise": 1.6, "sway": 0.1,
			"fade_bottom": 0.04, "fade_top": 0.2, "phase": phase,
		})
	_add_layer(_funnel_mesh(VEIL_R_BASE, TornadoVortex.TOP_WIDEN, VEIL_FLARE, 0.0, 1.0),
		funnel_scale, 1, {
			"tint": Color(0.9, 0.91, 0.95), "max_alpha": VEIL_ALPHA, "coverage": 0.36,
			"fill": 0.0, "edge": 0.08, "wisps": 1.0, "near_alpha": VEIL_NEAR_SHARE,
			"streaks": veil_streaks, "tile_v": 6.0 * height_factor, "twist": 1.8,
			"spin": VEIL_REVS * slow * veil_streaks, "rise": 0.9, "sway": 0.14,
			"fade_bottom": 0.15, "fade_top": 0.1, "phase": phase + 1.9,
		})
	_add_specks(funnel_scale, int(round(float(SPECK_COUNT) * size_factor)), phase)
	_base_scale = scale
	_apply_transition()


## Called when the vortex is over: the funnel lets go of it, stays where it is,
## widens and fades, then frees itself. Until then it is a plain child and dies
## with the vortex.
func dissipate() -> void:
	if _fading:
		return
	_fading = true
	var holder: Node = get_parent()
	var stage: Node = holder.get_parent() if holder != null else null
	if is_inside_tree() and stage != null:
		var keep: Transform3D = global_transform
		holder.remove_child(self)
		stage.add_child(self)
		global_transform = keep
		_base_scale = scale
	set_process(true)


func _process(delta: float) -> void:
	_age += delta
	if _fading:
		_fade += delta / FADE_TIME
		if _fade >= 1.0:
			queue_free()
			return
	_apply_transition()
	if not _fading and _age >= GROW_TIME:
		set_process(false)   # standing funnel: the shaders do the rest


## Pushes the build-up / dissolve state into the materials.
func _apply_transition() -> void:
	var g: float = clampf(_age / GROW_TIME, 0.0, 1.0)
	g = 1.0 - (1.0 - g) * (1.0 - g)   # ease out
	var f: float = clampf(_fade, 0.0, 1.0)
	for mat in _materials:
		mat.set_shader_parameter("grow", g)
		mat.set_shader_parameter("opacity", 1.0 - f)
	if _fading:
		var widen: float = 1.0 + FADE_WIDEN * f
		scale = Vector3(_base_scale.x * widen, _base_scale.y, _base_scale.z * widen)


func _add_layer(mesh: ArrayMesh, layer_scale: Vector3, priority: int,
		params: Dictionary) -> void:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = FUNNEL_SHADER
	mat.render_priority = priority
	for key in params:
		mat.set_shader_parameter(key, params[key])
	_materials.append(mat)
	var inst: MeshInstance3D = MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.scale = layer_scale
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader sways the wall sideways: keep the bounds generous in x/z.
	inst.custom_aabb = AABB(Vector3(-2.2, -0.05, -2.2), Vector3(4.4, 1.15, 4.4))
	add_child(inst)


func _add_specks(funnel_scale: Vector3, count: int, phase: float) -> void:
	if count <= 0:
		return
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = count
	for i in range(count):
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_custom_data(i, Color(_hash(i, 1.0), _hash(i, 2.0),
			_hash(i, 3.0), _hash(i, 4.0)))
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = SPECK_SHADER
	mat.render_priority = 2
	mat.set_shader_parameter("phase", phase)
	_materials.append(mat)
	var inst: MultiMeshInstance3D = MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	inst.scale = funnel_scale
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The orbit is computed in the shader, so the instances all sit at the origin.
	inst.custom_aabb = AABB(Vector3(-2.2, -0.05, -2.2), Vector3(4.4, 1.15, 4.4))
	add_child(inst)


## Stateless 0..1 hash (no randf(), see class doc).
static func _hash(i: int, salt: float) -> float:
	return fposmod(sin(float(i) * 12.9898 + salt * 78.233) * 43758.5453, 1.0)


## A surface of revolution in unit size: radius runs from `r0` (UV.y = 0) to `r1`
## (UV.y = 1) along `flare`, height from `y0` to `y1`. Shared across twisters.
static func _funnel_mesh(r0: float, r1: float, flare: float, y0: float,
		y1: float) -> ArrayMesh:
	var key: String = "%.3f/%.3f/%.3f/%.3f/%.3f" % [r0, r1, flare, y0, y1]
	if _mesh_cache.has(key):
		return _mesh_cache[key] as ArrayMesh
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for row in range(ROWS + 1):
		var t: float = float(row) / float(ROWS)
		var r: float = lerpf(r0, r1, pow(t, flare))
		var y: float = lerpf(y0, y1, t)
		for seg in range(SEGMENTS + 1):
			var u: float = float(seg) / float(SEGMENTS)
			var dir: Vector3 = Vector3(cos(u * TAU), 0.0, sin(u * TAU))
			verts.append(Vector3(dir.x * r, y, dir.z * r))
			normals.append(dir)
			uvs.append(Vector2(u, t))
	var stride: int = SEGMENTS + 1
	for row in range(ROWS):
		for seg in range(SEGMENTS):
			var a: int = row * stride + seg
			var b: int = a + 1
			var c: int = a + stride
			var d: int = c + 1
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_cache[key] = mesh
	return mesh
