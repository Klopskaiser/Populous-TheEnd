class_name LavaFlow extends Node3D

## A molten stream: spawns at a point, creeps downhill (steered by the terrain
## gradient) and leaves a trail of segments. Phase 10c made it red, thick and
## slow — the head runs with LavaCommon.flow_speed, i.e. fast down a scarp and
## barely at all on the flat, where it pools. Molten segments IGNITE every unit
## they touch — lava knows no friends (Unit.ignite: contact damage + burn with
## panic). Visual: ONE continuous terrain-hugging ribbon whose width pulses
## viscously and whose colour ages from a glowing head to black scorch at the
## cooled tail (fault lava skips the scorch and fades out instead). Ticked via
## the UnitManager projectile list; the ribbon only exists in-game (in-tree).

const SEGMENT_SPACING: float = 0.6
## Hard cap on the trail: a long-lived flow must not grow its per-check cost
## without bound (phase 10c perf budget).
const MAX_SEGMENTS: int = 28
const CONTACT_RADIUS: float = 0.9
const CHECK_INTERVAL: float = Balance.LAVA_CONTACT_INTERVAL
const VISUAL_INTERVAL: float = Balance.LAVA_VISUAL_INTERVAL
## Below this slope the lava pools and stops flowing.
const MIN_SLOPE: float = Balance.LAVA_MIN_SLOPE
const HALF_WIDTH: float = 0.65
## Over the last stretch of its life the stream SINKS into the ground
## instead of popping out of existence.
const SINK_TIME: float = 1.0
const SINK_DEPTH: float = 0.8

var done: bool = false
var unit_manager: UnitManager = null
var terrain_data: TerrainData = null
var building_manager: BuildingManager = null
## Buildings touched by molten segments accumulate lava contact (destruction
## stages, see Building.add_lava_contact).
var damage_buildings: bool = true
## Per-use tuning: the volcano's flows scorch the ground black, the
## earthquake's fault lava is short and vanishes quickly without a trace.
var flow_range: float = 7.0
var lifetime: float = Balance.LAVA_LIFETIME
var molten_time: float = Balance.LAVA_MOLTEN_TIME
var scorch: bool = true
## Seconds the head waits before it starts running (earthquake: the scarp has
## to be torn open by the TerrainMorph first). It keeps following the ground
## height while it waits, so it rides the rising edge instead of hanging in it.
var start_delay: float = 0.0

var _dir: Vector3 = Vector3(1, 0, 0)
var _head: Vector3 = Vector3.ZERO
var _flowing: bool = true
var _travelled: float = 0.0
var _since_segment: float = 999.0   # first segment drops immediately
var _life: float = 0.0
var _check_timer: float = 0.0
var _since_check: float = 0.0
var _visual_timer: float = 0.0
## Segment entries: {pos: Vector3, age: float, cooled: bool}.
var _segments: Array[Dictionary] = []
var _ribbon: MeshInstance3D = null


func setup(at: Vector3, dir: Vector3, p_unit_manager: UnitManager,
		p_terrain_data: TerrainData, p_range: float = 7.0,
		p_lifetime: float = Balance.LAVA_LIFETIME,
		p_molten: float = Balance.LAVA_MOLTEN_TIME,
		p_scorch: bool = true, p_building_manager: BuildingManager = null) -> void:
	position = at
	_head = at
	unit_manager = p_unit_manager
	terrain_data = p_terrain_data
	building_manager = p_building_manager
	flow_range = p_range
	lifetime = p_lifetime
	molten_time = p_molten
	scorch = p_scorch
	var flat: Vector3 = Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() > 0.000001:
		_dir = flat.normalized()


func tick(delta: float) -> void:
	if done:
		return
	_life += delta
	if _life >= lifetime:
		done = true
		return
	if _life < start_delay:
		# Waiting for the ground to open up: the head only rides the terrain.
		if terrain_data != null:
			_head.y = terrain_data.get_height(_head.x, _head.z)
	elif _flowing:
		_advance(delta)
	for seg in _segments:
		seg.age += delta
		if not seg.cooled and seg.age >= molten_time:
			seg.cooled = true
	_since_check += delta
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = CHECK_INTERVAL
		var step: float = _since_check
		_since_check = 0.0
		_ignite_touching_units(step)
	_visual_timer -= delta
	if _visual_timer <= 0.0:
		_visual_timer = VISUAL_INTERVAL
		_rebuild_ribbon()


## Head movement: steered toward the local downhill direction and paced by the
## flow law (fast on a steep scarp, a crawl on the flat). It stops once the
## range is exhausted or the ground levels out — the lava pools there.
func _advance(delta: float) -> void:
	var grad: Vector3 = Vector3.ZERO
	if terrain_data != null:
		grad = LavaCommon.downhill(terrain_data, _head.x, _head.z)
	var slope: float = grad.length()
	if slope >= MIN_SLOPE:
		_dir = _dir.lerp(grad / slope, 0.6).normalized()
	var speed: float = LavaCommon.flow_speed(grad.dot(_dir))
	var step: float = speed * delta
	_head += _dir * step
	if terrain_data != null:
		_head.y = terrain_data.get_height(_head.x, _head.z)
	_travelled += step
	_since_segment += step
	if _since_segment >= SEGMENT_SPACING:
		_since_segment = 0.0
		_segments.append({"pos": _head, "age": 0.0, "cooled": false})
		if _segments.size() > MAX_SEGMENTS:
			_segments.remove_at(0)
	if _travelled >= flow_range:
		_flowing = false
	elif _travelled > 1.0 and slope < MIN_SLOPE:
		_flowing = false


## ONE spatial query over a hull circle around every molten segment, then a
## per-unit test against the segments (phase 10c: the old code ran one query
## PER segment — up to ~16 of them, three flows per earthquake).
func _ignite_touching_units(step: float) -> void:
	if unit_manager == null:
		return
	var molten: Array[Dictionary] = []
	var lo: Vector2 = Vector2(INF, INF)
	var hi: Vector2 = Vector2(-INF, -INF)
	for seg in _segments:
		if seg.cooled:
			continue
		molten.append(seg)
		var p: Vector3 = seg.pos
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	if molten.is_empty():
		return
	var mid: Vector2 = (lo + hi) * 0.5
	var hull_center: Vector3 = Vector3(mid.x, _head.y, mid.y)
	var hull_radius: float = lo.distance_to(hi) * 0.5 + CONTACT_RADIUS
	for u in unit_manager.get_units_in_radius(hull_center, hull_radius):
		if u.state == Unit.State.DEAD or u.is_airborne():
			continue   # airborne units (thrown, airship deck) pass over the lava
		var touch: Vector3 = _nearest_molten(molten, u.position)
		if touch.y == INF:
			continue
		# This flow is the fire source: a fire ram takes ONE life from the
		# flow no matter how long it stands in it (per-source throttle).
		u.ignite(touch, self)
	# Lava also sets trees and wood piles alight (phase 7d). Both take a radius
	# query, so they run once over the hull circle instead of per segment.
	if unit_manager.tree_manager != null:
		unit_manager.tree_manager.ignite_in_radius(hull_center, hull_radius)
	if unit_manager.wood_pile_manager != null:
		unit_manager.wood_pile_manager.ignite_in_radius(hull_center, hull_radius)
	_touch_buildings(molten, hull_center, hull_radius, step)


## Position of the molten segment covering `at`, or a y=INF sentinel when none
## does (the hull circle is wider than the ribbon).
func _nearest_molten(molten: Array[Dictionary], at: Vector3) -> Vector3:
	var best: Vector3 = Vector3(0.0, INF, 0.0)
	var best_d: float = CONTACT_RADIUS * CONTACT_RADIUS
	for seg in molten:
		var p: Vector3 = seg.pos
		var dx: float = p.x - at.x
		var dz: float = p.z - at.z
		var d: float = dx * dx + dz * dz
		if d <= best_d:
			best_d = d
			best = p
	return best


## Buildings touched by any molten segment rack up lava contact time — once per
## check tick, no matter how many overlapping segments touch them. The hull
## circle pre-filters the building list before the per-segment test.
func _touch_buildings(molten: Array[Dictionary], hull_center: Vector3,
		hull_radius: float, step: float) -> void:
	if building_manager == null or not damage_buildings:
		return
	var hull_flat: Vector2 = Vector2(hull_center.x, hull_center.z)
	for b in building_manager.buildings:
		if not is_instance_valid(b) or b.health <= 0:
			continue
		if b.footprint_distance_to(hull_flat) > hull_radius:
			continue
		for seg in molten:
			if b.footprint_distance_to(Vector2(seg.pos.x, seg.pos.z)) <= CONTACT_RADIUS:
				b.add_lava_contact(step)
				break


# --- Ribbon visual (in-game only) ----------------------------------------------------

## One triangle strip along the path: width pulses viscously per point, the
## colour fades from a glowing head over dark red to black (scorch) or to
## transparent (fault lava) as the segments age. Cheap: <= MAX_SEGMENTS + 1
## points, rebuilt at VISUAL_INTERVAL.
func _rebuild_ribbon() -> void:
	if _ribbon == null:
		return
	var im: ImmediateMesh = _ribbon.mesh
	im.clear_surfaces()
	var points: Array[Dictionary] = _segments.duplicate()
	if _flowing:
		points.append({"pos": _head, "age": -0.3, "cooled": false})
	if points.size() < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(points.size()):
		var p: Vector3 = points[i].pos
		var next: Vector3 = points[mini(i + 1, points.size() - 1)].pos
		var prev: Vector3 = points[maxi(i - 1, 0)].pos
		var along: Vector3 = Vector3(next.x - prev.x, 0.0, next.z - prev.z)
		if along.length_squared() < 0.000001:
			along = _dir
		along = along.normalized()
		var perp: Vector3 = Vector3(-along.z, 0.0, along.x)
		# Viscous pulse: the thick body swells and contracts slowly.
		var wobble: float = 0.85 + 0.15 * sin(_life * 1.8 + float(i) * 1.1)
		var w: float = HALF_WIDTH * wobble
		if i == points.size() - 1 and _flowing:
			w *= 1.5   # bulbous advancing head
		im.surface_set_color(_point_color(points[i]))
		var y: float = p.y + 0.07 - _sink_offset()
		var a: Vector3 = Vector3(p.x, y, p.z) + perp * w - position
		var b: Vector3 = Vector3(p.x, y, p.z) - perp * w - position
		im.surface_add_vertex(a)
		im.surface_set_color(_point_color(points[i]))
		im.surface_add_vertex(b)
	im.surface_end()


## Downward offset at the end of life: the stream sinks into the ground.
func _sink_offset() -> float:
	var t: float = clampf((_life - (lifetime - SINK_TIME)) / SINK_TIME, 0.0, 1.0)
	return t * SINK_DEPTH


func _point_color(seg: Dictionary) -> Color:
	return LavaCommon.color_for(maxf(float(seg.age), 0.0), molten_time,
		bool(seg.cooled), scorch)


func _ready() -> void:
	SpellAudio.play_named(self, &"lava_start", global_position, 250)
	_ribbon = MeshInstance3D.new()
	_ribbon.mesh = ImmediateMesh.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ribbon.material_override = mat
	add_child(_ribbon)
