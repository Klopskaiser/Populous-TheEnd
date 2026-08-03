class_name TreeMarkRenderer extends MultiMeshInstance3D

## White confirmation rings around trees a fell order just accepted (phase 10e):
## each mark blinks TREE_MARK_BLINKS times, then it is gone. This is a RECEIPT
## ("these trees are on the job"), not a permanent marker.
##
## ONE MultiMesh of flat rings (pattern: SelectionRingRenderer) so a rectangle
## covering 60 trees stays a single draw call with zero node churn.
##
## Visibility comes from the PACKED INSTANCE COUNT, not from alpha: a transparent
## material would leave the opaque pass and start sorting per instance against
## terrain and units, and one MultiMesh material cannot carry a per-mark alpha at
## all without INSTANCE_COLOR plus a custom shader. Packing only the marks in
## their ON phase keeps the material unshaded and opaque, and makes the visible
## state exactly testable.

const MAX_MARKS: int = 256
const RING_COLOR: Color = Color(1.0, 1.0, 1.0)
const RING_HEIGHT: float = 0.1
## Ring radius = the tree's stage scale times this (so the circle clears the crown).
const RADIUS_PER_SCALE: float = 1.6
const MIN_RADIUS: float = 0.5
const BLINKS: int = Balance.TREE_MARK_BLINKS
const BLINK_TIME: float = Balance.TREE_MARK_BLINK_TIME
const TOTAL_TIME: float = float(BLINKS) * 2.0 * BLINK_TIME

var _multimesh: MultiMesh = null
## Active marks as [position: Vector3, radius: float, age: float]. POSITIONS ARE
## COPIED, the tree is not referenced: a tree felled mid-blink must not leave a
## dangling reference behind, and the ring belongs to the spot anyway.
var _marks: Array[Array] = []


func _ready() -> void:
	# Unit radius 1 -> the per-instance scale IS the ring radius.
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.88
	torus.outer_radius = 1.0
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = RING_COLOR
	torus.material = mat
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.mesh = torus
	_multimesh.instance_count = MAX_MARKS
	_multimesh.visible_instance_count = 0
	multimesh = _multimesh
	# UI geometry never enters the shadow pass (phase 8 shadow rework).
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Flashes a white ring around every tree. Untyped entries on purpose: callers
## hand in registry lists that may hold freed nodes.
func flash(trees: Array) -> void:
	for tree in trees:
		if tree == null or not is_instance_valid(tree):
			continue
		var t: TreeResource = tree as TreeResource
		if t == null or t.felled_flag:
			continue
		add_mark(t.position, mark_radius(t))


## Re-flashing the same spot RESTARTS its blink instead of stacking a second
## entry — right-clicking one tree twice must not double up its ring.
func add_mark(pos: Vector3, radius: float) -> void:
	for m in _marks:
		if (m[0] as Vector3).distance_squared_to(pos) < 0.01:
			m[2] = 0.0
			return
	if _marks.size() >= MAX_MARKS:
		return
	_marks.append([pos, radius, 0.0])


## Ring radius from the tree's GROWTH STAGE and TYPE, via the stage scales in
## Balance.TREE_TYPE_PARAMS (bamboo tops out at stage 2). Read from Balance and
## not from node.scale, so the value is defined for a tree whose visual transform
## was never applied (headless).
static func mark_radius(tree: TreeResource) -> float:
	var scales: Array = Balance.TREE_TYPE_PARAMS[tree.type].stage_scales
	var s: float = float(scales[clampi(tree.stage, 0, scales.size() - 1)])
	return maxf(s * RADIUS_PER_SCALE, MIN_RADIUS)


## On during the FIRST half of every blink period -> on/off/on/off across
## BLINKS * 2 * BLINK_TIME, then gone for good.
static func mark_visible(age: float) -> bool:
	if age < 0.0 or age >= TOTAL_TIME:
		return false
	return fmod(age, 2.0 * BLINK_TIME) < BLINK_TIME


func _process(delta: float) -> void:
	advance(delta)


## Ages every mark and packs the visible ones. Split out of _process so tests can
## drive the timing without a viewport.
func advance(delta: float) -> void:
	if _multimesh == null:
		return
	if _marks.is_empty():
		if _multimesh.visible_instance_count != 0:
			_multimesh.visible_instance_count = 0
		return
	var kept: Array[Array] = []
	var count: int = 0
	for m in _marks:
		var age: float = float(m[2]) + delta
		if age >= TOTAL_TIME:
			continue   # expired: drops out of the list
		m[2] = age
		kept.append(m)
		if not mark_visible(age) or count >= MAX_MARKS:
			continue
		var r: float = float(m[1])
		_multimesh.set_instance_transform(count, Transform3D(
			Basis.IDENTITY.scaled(Vector3(r, 1.0, r)),
			(m[0] as Vector3) + Vector3(0.0, RING_HEIGHT, 0.0)))
		count += 1
	_marks = kept
	_multimesh.visible_instance_count = count


## Number of marks still blinking (tests / telemetry readout).
func active_marks() -> int:
	return _marks.size()


## Marks currently drawn this frame (tests: the on/off phases).
func visible_marks() -> int:
	return _multimesh.visible_instance_count if _multimesh != null else 0
