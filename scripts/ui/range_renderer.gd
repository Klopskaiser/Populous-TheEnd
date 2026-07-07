class_name RangeRenderer extends MultiMeshInstance3D

## Ground range rings for the player's ranged units, toggled with G (user
## request). One flat MultiMesh torus per unit, scaled to the unit's reach and
## coloured by kind, so the fire/convert coverage of the army is easy to read
## at a glance. Shown kinds: firewarrior (fire range), preacher (convert
## range), catapult (fire range + a dim inner minimum-range ring). Siege CREW
## have no range of their own — they belong to the vehicle — and are skipped.

const MAX_RINGS: int = 512
## Base torus radius; scaled per instance to the actual range (metres).
const BASE_RADIUS: float = 1.0
const RING_HEIGHT: float = 0.06

const C_FIREWARRIOR: Color = Color(1.0, 0.55, 0.15, 0.75)
const C_PREACHER: Color = Color(0.65, 0.45, 1.0, 0.75)
const C_SIEGE: Color = Color(1.0, 0.30, 0.20, 0.8)
const C_SIEGE_MIN: Color = Color(1.0, 0.30, 0.20, 0.4)

var _unit_manager: UnitManager = null
var _player_id: int = 0
## Toggled by the G key (toggle_ranges action).
var enabled: bool = false
var _multimesh: MultiMesh = null


func setup(p_unit_manager: UnitManager, p_player_id: int) -> void:
	_unit_manager = p_unit_manager
	_player_id = p_player_id


## Max attack/convert range shown for a unit kind, or 0 when it has none.
## Static + pure so it is headless-testable.
static func range_for_kind(kind: StringName) -> float:
	match kind:
		&"firewarrior":
			return Firewarrior.FIRE_RANGE
		&"preacher":
			return Preacher.CONVERT_RANGE
		&"siege":
			return SiegeEngine.FIRE_RANGE
	return 0.0


func _ready() -> void:
	# A thin flat ring lying in the XZ plane (torus axis = Y).
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = BASE_RADIUS - 0.03
	torus.outer_radius = BASE_RADIUS
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true   # per-instance colours
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color.WHITE
	torus.material = mat

	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.mesh = torus
	_multimesh.instance_count = MAX_RINGS
	_multimesh.visible_instance_count = 0
	multimesh = _multimesh


func toggle() -> void:
	enabled = not enabled
	if not enabled and _multimesh != null:
		_multimesh.visible_instance_count = 0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_ranges"):
		toggle()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not enabled or _unit_manager == null or _multimesh == null:
		return
	var count: int = 0
	for unit in _unit_manager.units:
		if count >= MAX_RINGS:
			break
		if unit.tribe_id != _player_id or unit.state == Unit.State.DEAD:
			continue
		if unit.siege_engine != null:
			continue   # siege crew: no range of its own
		var r: float = range_for_kind(unit.unit_kind())
		if r <= 0.0:
			continue
		_place_ring(count, unit.position, r, _color_for(unit.unit_kind()))
		count += 1
		# Catapults also show a dim inner minimum-range ring.
		if unit is SiegeEngine and count < MAX_RINGS:
			_place_ring(count, unit.position, SiegeEngine.MIN_RANGE, C_SIEGE_MIN)
			count += 1
	_multimesh.visible_instance_count = count


func _place_ring(index: int, pos: Vector3, radius: float, color: Color) -> void:
	_multimesh.set_instance_transform(index, Transform3D(
		Basis.IDENTITY.scaled(Vector3(radius, 1.0, radius)),
		pos + Vector3(0.0, RING_HEIGHT, 0.0)))
	_multimesh.set_instance_color(index, color)


static func _color_for(kind: StringName) -> Color:
	match kind:
		&"firewarrior":
			return C_FIREWARRIOR
		&"preacher":
			return C_PREACHER
		&"siege":
			return C_SIEGE
	return Color.WHITE
