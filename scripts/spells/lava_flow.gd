class_name LavaFlow extends Node3D

## A molten stream: spawns at a point, runs downhill (steered by the terrain
## gradient) and leaves a trail of segments. Molten segments IGNITE every
## unit they touch — lava knows no friends (Unit.ignite: contact damage +
## burn with panic). Visual: ONE continuous terrain-hugging ribbon whose
## width pulses viscously and whose colour ages from glowing orange at the
## head to black scorch at the cooled tail (fault lava skips the scorch and
## fades out instead). Ticked via the UnitManager projectile list; the
## ribbon only exists in-game (in-tree).

const FLOW_SPEED: float = 3.0
const SEGMENT_SPACING: float = 0.45
const CONTACT_RADIUS: float = 0.9
const CHECK_INTERVAL: float = 0.2
const VISUAL_INTERVAL: float = 0.1
## Below this slope the lava pools and stops flowing.
const MIN_SLOPE: float = 0.04
const HALF_WIDTH: float = 0.5
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
var lifetime: float = 12.0
var molten_time: float = 4.0
var scorch: bool = true

var _dir: Vector3 = Vector3(1, 0, 0)
var _head: Vector3 = Vector3.ZERO
var _flowing: bool = true
var _travelled: float = 0.0
var _since_segment: float = 999.0   # first segment drops immediately
var _life: float = 0.0
var _check_timer: float = 0.0
var _visual_timer: float = 0.0
## Segment entries: {pos: Vector3, age: float, cooled: bool}.
var _segments: Array[Dictionary] = []
var _ribbon: MeshInstance3D = null


func setup(at: Vector3, dir: Vector3, p_unit_manager: UnitManager,
		p_terrain_data: TerrainData, p_range: float = 7.0,
		p_lifetime: float = 12.0, p_molten: float = 4.0,
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
	if _flowing:
		_advance(delta)
	for seg in _segments:
		seg.age += delta
		if not seg.cooled and seg.age >= molten_time:
			seg.cooled = true
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = CHECK_INTERVAL
		_ignite_touching_units()
	_visual_timer -= delta
	if _visual_timer <= 0.0:
		_visual_timer = VISUAL_INTERVAL
		_rebuild_ribbon()


## Head movement: steered toward the local downhill direction, stopping once
## the range is exhausted or the ground levels out (the lava pools).
func _advance(delta: float) -> void:
	var downhill: Vector3 = _downhill(_head)
	if downhill != Vector3.ZERO:
		_dir = _dir.lerp(downhill, 0.45).normalized()
	_head += _dir * FLOW_SPEED * delta
	if terrain_data != null:
		_head.y = terrain_data.get_height(_head.x, _head.z)
	_travelled += FLOW_SPEED * delta
	_since_segment += FLOW_SPEED * delta
	if _since_segment >= SEGMENT_SPACING:
		_since_segment = 0.0
		_segments.append({"pos": _head, "age": 0.0, "cooled": false})
	if _travelled >= flow_range:
		_flowing = false
	elif _travelled > 1.0 and downhill == Vector3.ZERO:
		_flowing = false


func _downhill(at: Vector3) -> Vector3:
	if terrain_data == null:
		return Vector3.ZERO
	var e: float = 0.5
	var gx: float = terrain_data.get_height(at.x + e, at.z) \
		- terrain_data.get_height(at.x - e, at.z)
	var gz: float = terrain_data.get_height(at.x, at.z + e) \
		- terrain_data.get_height(at.x, at.z - e)
	var grad: Vector3 = Vector3(-gx, 0.0, -gz) / (2.0 * e)
	if grad.length() < MIN_SLOPE:
		return Vector3.ZERO
	return grad.normalized()


func _ignite_touching_units() -> void:
	if unit_manager == null:
		return
	var tm: TreeManager = unit_manager.tree_manager
	var wpm: WoodPileManager = unit_manager.wood_pile_manager
	for seg in _segments:
		if seg.cooled:
			continue
		for u in unit_manager.get_units_in_radius(seg.pos, CONTACT_RADIUS):
			if u.state == Unit.State.DEAD or u.is_airborne():
				continue   # airborne units (thrown, airship deck) pass over the lava
			u.ignite(seg.pos)
		# Lava also sets trees and wood piles alight (phase 7d).
		if tm != null:
			tm.ignite_in_radius(seg.pos, CONTACT_RADIUS)
		if wpm != null:
			wpm.ignite_in_radius(seg.pos, CONTACT_RADIUS)
	_touch_buildings()


## Buildings touched by any molten segment rack up lava contact time — once per
## check tick, no matter how many overlapping segments touch them.
func _touch_buildings() -> void:
	if building_manager == null or not damage_buildings:
		return
	var touched: Dictionary = {}
	for b in building_manager.buildings:
		if not is_instance_valid(b) or b.health <= 0:
			continue
		for seg in _segments:
			if seg.cooled:
				continue
			if b.footprint_distance_to(Vector2(seg.pos.x, seg.pos.z)) <= CONTACT_RADIUS:
				touched[b] = true
				break
	for b in touched.keys():
		b.add_lava_contact(CHECK_INTERVAL)


# --- Ribbon visual (in-game only) ----------------------------------------------------

## One triangle strip along the path: width pulses viscously per point, the
## colour fades from a glowing head over dark red to black (scorch) or to
## transparent (fault lava) as the segments age. Cheap: <= ~40 points,
## rebuilt at VISUAL_INTERVAL.
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
		# Viscous pulse: the molten body slowly swells and contracts.
		var wobble: float = 0.8 + 0.2 * sin(_life * 4.0 + float(i) * 1.7)
		var w: float = HALF_WIDTH * wobble
		if i == points.size() - 1 and _flowing:
			w *= 1.35   # bulbous advancing head
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
	var t: float = clampf(float(seg.age) / molten_time, 0.0, 1.0)
	if seg.cooled:
		# Cooled: black scorch stays, fault lava fades away.
		return Color(0.06, 0.05, 0.04, 1.0) if scorch \
			else Color(0.3, 0.1, 0.03, maxf(0.0, 1.0 - (float(seg.age) - molten_time)))
	# Glowing head -> dark viscous red as it ages.
	return Color(1.0, 0.55, 0.08, 1.0).lerp(Color(0.55, 0.12, 0.02, 1.0), t)


func _ready() -> void:
	_ribbon = MeshInstance3D.new()
	_ribbon.mesh = ImmediateMesh.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ribbon.material_override = mat
	add_child(_ribbon)
