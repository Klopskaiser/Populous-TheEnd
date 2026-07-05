class_name SelectionRingRenderer extends MultiMeshInstance3D

## Renders the selection rings of ALL selected units through one MultiMesh.
## Per-unit ring MeshInstances caused a visible hitch when box-selecting
## hundreds of units; here selecting 1000 units costs one transform update
## per ring per frame and zero node churn.

const MAX_RINGS: int = 1024
const RING_COLOR: Color = Color(1.0, 0.95, 0.3)
const RING_HEIGHT: float = 0.08

var _selection: SelectionManager = null
var _multimesh: MultiMesh = null


func setup(p_selection: SelectionManager) -> void:
	_selection = p_selection


func _ready() -> void:
	# Small ring around the feet; depth-tested so it does not draw over the
	# unit sprites (and lines up with the model's ground position).
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.26
	torus.outer_radius = 0.34
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = RING_COLOR
	torus.material = mat
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.mesh = torus
	_multimesh.instance_count = MAX_RINGS
	_multimesh.visible_instance_count = 0
	multimesh = _multimesh


func _process(_delta: float) -> void:
	if _selection == null:
		return
	var count: int = 0
	for unit in _selection.selected:
		if count >= MAX_RINGS:
			break
		if not is_instance_valid(unit) or unit.state == Unit.State.DEAD:
			continue
		_multimesh.set_instance_transform(count, Transform3D(
			Basis.IDENTITY, unit.position + Vector3(0.0, RING_HEIGHT, 0.0)))
		count += 1
	_multimesh.visible_instance_count = count
