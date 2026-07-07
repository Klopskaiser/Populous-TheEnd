class_name RouteVisualizer extends Node3D

## Draws thin route lines and small waypoint markers for the currently
## selected units — visible only while the units stay selected. Covers both
## simple right-click moves (one line + one marker) and waypoint routes
## (line along the whole route, marker per waypoint; patrol routes close the
## loop). Lines are sampled onto the terrain so they follow the ground.
##
## Scale limits: at most MAX_ROUTES units get a route line (one ImmediateMesh
## surface each — the renderer caps a mesh at 256 surfaces, and hundreds of
## per-frame surface rebuilds would stall anyway), and the rebuild runs on an
## interval instead of every frame.

const LINE_COLOR: Color = Color(1.0, 0.95, 0.3, 0.65)
const MARKER_COLOR: Color = Color(1.0, 0.8, 0.2)
const LINE_HEIGHT: float = 0.15    # metres above the terrain
const MARKER_HEIGHT: float = 0.2
const SAMPLE_STEP: float = 1.0     # metres between terrain samples along a line
const MAX_MARKERS: int = 256
const MAX_ROUTES: int = 24         # route lines for the first N selected units
const UPDATE_INTERVAL: float = 0.1 # seconds between rebuilds

var _selection: SelectionManager = null
var _terrain_data: TerrainData = null

var _line_mesh: ImmediateMesh = null
var _multimesh: MultiMesh = null
var _update_timer: float = 0.0


func setup(p_selection: SelectionManager, p_terrain_data: TerrainData) -> void:
	_selection = p_selection
	_terrain_data = p_terrain_data


func _ready() -> void:
	_line_mesh = ImmediateMesh.new()
	var lines: MeshInstance3D = MeshInstance3D.new()
	lines.name = "RouteLines"
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lines.mesh = _line_mesh
	var line_mat: StandardMaterial3D = StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.no_depth_test = true
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.albedo_color = LINE_COLOR
	lines.material_override = line_mat
	add_child(lines)

	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	sphere.radial_segments = 8
	sphere.rings = 4
	var marker_mat: StandardMaterial3D = StandardMaterial3D.new()
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mat.no_depth_test = true
	marker_mat.albedo_color = MARKER_COLOR
	sphere.material = marker_mat
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.mesh = sphere
	_multimesh.instance_count = MAX_MARKERS
	_multimesh.visible_instance_count = 0
	var markers: MultiMeshInstance3D = MultiMeshInstance3D.new()
	markers.name = "RouteMarkers"
	markers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	markers.multimesh = _multimesh
	add_child(markers)


func _process(delta: float) -> void:
	_update_timer -= delta
	if _update_timer > 0.0:
		return
	_update_timer = UPDATE_INTERVAL
	_line_mesh.clear_surfaces()
	var marker_count: int = 0
	var routes_drawn: int = 0
	if _selection != null and _terrain_data != null:
		for unit in _selection.selected:
			if routes_drawn >= MAX_ROUTES:
				break
			if not is_instance_valid(unit) or unit.state == Unit.State.DEAD:
				continue
			if unit.state != Unit.State.MOVE and unit.waypoint_queue.is_empty():
				continue  # nothing to draw, keep the route budget
			marker_count = _draw_unit_route(unit, marker_count)
			routes_drawn += 1
	_multimesh.visible_instance_count = marker_count


## Draws one unit's route; returns the updated marker count.
func _draw_unit_route(unit: Unit, marker_count: int) -> int:
	for wp in unit.waypoint_queue:
		if marker_count >= MAX_MARKERS:
			break
		var pos: Vector3 = Vector3(
			wp.x, _terrain_data.get_height(wp.x, wp.z) + MARKER_HEIGHT, wp.z)
		_multimesh.set_instance_transform(marker_count, Transform3D(Basis.IDENTITY, pos))
		marker_count += 1

	# Line: unit -> remaining path to the current waypoint -> queued waypoints
	# (straight preview; their exact paths are computed on arrival).
	var points: PackedVector3Array = PackedVector3Array()
	points.append(unit.position)
	points.append_array(unit.get_remaining_path())
	for i in range(1, unit.waypoint_queue.size()):
		points.append(unit.waypoint_queue[i])
	if unit.patrol and unit.waypoint_queue.size() >= 2:
		points.append(unit.waypoint_queue[0])  # close the patrol loop
	if points.size() < 2:
		return marker_count

	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(points.size() - 1):
		_append_ground_segment(points[i], points[i + 1], i == 0)
	_line_mesh.surface_end()
	return marker_count


## Adds a segment as terrain-following samples (start vertex only for the
## first segment of a strip).
func _append_ground_segment(a: Vector3, b: Vector3, include_start: bool) -> void:
	var flat_a: Vector2 = Vector2(a.x, a.z)
	var flat_b: Vector2 = Vector2(b.x, b.z)
	var steps: int = maxi(1, int(ceil(flat_a.distance_to(flat_b) / SAMPLE_STEP)))
	var start: int = 0 if include_start else 1
	for s in range(start, steps + 1):
		var p: Vector2 = flat_a.lerp(flat_b, float(s) / float(steps))
		_line_mesh.surface_add_vertex(
			Vector3(p.x, _terrain_data.get_height(p.x, p.y) + LINE_HEIGHT, p.y))
