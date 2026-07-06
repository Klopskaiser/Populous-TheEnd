class_name LavaFlow extends Node3D

## A molten stream: spawns at a point, runs downhill for a short distance
## (steered by the terrain gradient) and leaves a trail of lava segments.
## Molten segments IGNITE every unit they touch — lava knows no friends
## (Unit.ignite: contact damage + burn with panic). When a segment cools it
## blackens the ground beneath it (scorch decal); the earthquake's fault lava
## skips the scorch and simply vanishes. Ticked via the UnitManager
## projectile list; visuals only exist in-game (in-tree).

const FLOW_SPEED: float = 2.2
const SEGMENT_SPACING: float = 0.7
const CONTACT_RADIUS: float = 0.9
const CHECK_INTERVAL: float = 0.2
## Below this slope the lava pools and stops flowing.
const MIN_SLOPE: float = 0.04

var done: bool = false
var unit_manager: UnitManager = null
var terrain_data: TerrainData = null
## Per-use tuning: the volcano flows far and scorches, the earthquake's
## fault lava is short and vanishes quickly without a trace.
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
## Segment entries: {pos: Vector3, age: float, cooled: bool, node: MeshInstance3D|null}.
var _segments: Array[Dictionary] = []
var _molten_mat: StandardMaterial3D = null
var _scorch_mat: StandardMaterial3D = null


func setup(at: Vector3, dir: Vector3, p_unit_manager: UnitManager,
		p_terrain_data: TerrainData, p_range: float = 7.0,
		p_lifetime: float = 12.0, p_molten: float = 4.0,
		p_scorch: bool = true) -> void:
	position = at
	_head = at
	unit_manager = p_unit_manager
	terrain_data = p_terrain_data
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
			_cool_visual(seg)
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = CHECK_INTERVAL
		_ignite_touching_units()


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
		_add_segment(_head)
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


func _add_segment(at: Vector3) -> void:
	var node: MeshInstance3D = null
	if is_inside_tree() and _molten_mat != null:
		node = MeshInstance3D.new()
		var blob: SphereMesh = SphereMesh.new()
		blob.radius = 0.45
		blob.height = 0.5
		node.mesh = blob
		node.material_override = _molten_mat
		add_child(node)
		node.position = at - position + Vector3(0.0, 0.1, 0.0)
	_segments.append({"pos": at, "age": 0.0, "cooled": false, "node": node})


## Cooling: the volcano's lava blackens the ground (flattened dark decal),
## the quick fault lava just disappears.
func _cool_visual(seg: Dictionary) -> void:
	var node = seg.node
	if node == null or not is_instance_valid(node):
		return
	if scorch:
		node.material_override = _scorch_mat
		node.scale = Vector3(1.1, 0.12, 1.1)
	else:
		node.visible = false


func _ignite_touching_units() -> void:
	if unit_manager == null:
		return
	for seg in _segments:
		if seg.cooled:
			continue
		for u in unit_manager.get_units_in_radius(seg.pos, CONTACT_RADIUS):
			if u.state == Unit.State.DEAD or u.state == Unit.State.THROWN:
				continue   # airborne units pass over the lava
			u.ignite(seg.pos)


func _ready() -> void:
	_molten_mat = StandardMaterial3D.new()
	_molten_mat.albedo_color = Color(1.0, 0.42, 0.06)
	_molten_mat.emission_enabled = true
	_molten_mat.emission = Color(1.0, 0.3, 0.0)
	_molten_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_scorch_mat = StandardMaterial3D.new()
	_scorch_mat.albedo_color = Color(0.06, 0.05, 0.04)
	_scorch_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
