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
	# UI geometry never enters the shadow pass (phase 8 shadow rework).
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(_delta: float) -> void:
	if _selection == null:
		return
	var count: int = 0
	for unit in _selection.selected:
		if count >= MAX_RINGS:
			break
		if not is_instance_valid(unit) or unit.state == Unit.State.DEAD:
			continue
		# The selected FLAG is authoritative: units can be deselected without
		# leaving the selection list (e.g. a brave walking into a training
		# building calls set_selected(false)) — no ring for those.
		if not unit.selected:
			continue
		# Per-unit ring size via the instance scale (siege engine: one big
		# ring around vehicle + crew, phase 7f). Non-circular rings (airship
		# deck) scale per axis and rotate to the unit's facing.
		var basis: Basis = ring_basis(
			unit.facing, unit.selection_ring_oriented(), unit.selection_ring_extents())
		count += 1
	_multimesh.visible_instance_count = count


## Ring transform basis: a per-axis scaled (oval) ring aligned to `facing` when
## `oriented`, else a plain scaled circle. Scaling must be applied in the ROTATED
## LOCAL frame (scaled_local = self * from_scale) so the oval's long axis follows
## `facing`. Basis.scaled() pre-multiplies (world-axis scaling), which pins the
## ellipse to the world axes — the oval then never turns with the platform (bug).
## For a circle (ext.x == ext.y) both are identical.
static func ring_basis(facing: Vector3, oriented: bool, ext: Vector2) -> Basis:
	var basis: Basis = Basis.IDENTITY
	if oriented and facing.length_squared() > 0.000001:
		basis = Basis(Vector3.UP, atan2(facing.x, facing.z))
	return basis.scaled_local(Vector3(ext.x, 1.0, ext.y))
