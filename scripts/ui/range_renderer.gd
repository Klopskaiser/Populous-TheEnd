class_name RangeRenderer extends MeshInstance3D

## Ground range rings for the player's ranged units, toggled with G (user
## request). One terrain-conforming ring per unit (TerrainRing — follows
## slopes instead of sinking into hills), coloured by kind, so the fire/
## convert coverage of the army is easy to read at a glance. Shown kinds:
## firewarrior (fire range), preacher (convert range), catapult (fire range +
## a dim inner minimum-range ring). Siege CREW have no range of their own —
## they belong to the vehicle — and are skipped. Rebuilt each frame while
## enabled (few units of these kinds, cheap).

const C_FIREWARRIOR: Color = Color(1.0, 0.55, 0.15, 0.8)
const C_PREACHER: Color = Color(0.65, 0.45, 1.0, 0.8)
const C_SIEGE: Color = Color(1.0, 0.30, 0.20, 0.85)
const C_SIEGE_MIN: Color = Color(1.0, 0.30, 0.20, 0.4)
const C_AIRSHIP: Color = Color(0.95, 0.85, 0.35, 0.8)

var _unit_manager: UnitManager = null
var _player_id: int = 0
var _terrain_data: TerrainData = null
## Toggled by the G key (toggle_ranges action).
var enabled: bool = false
var _im: ImmediateMesh = null


func setup(p_unit_manager: UnitManager, p_player_id: int,
		p_terrain_data: TerrainData) -> void:
	_unit_manager = p_unit_manager
	_player_id = p_player_id
	_terrain_data = p_terrain_data


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
		&"fireram":
			return FireRam.FIRE_RANGE
		&"airship":
			# The deck's best combat reach (firewarriors: 8 + 3 deck bonus).
			return Firewarrior.FIRE_RANGE + Balance.AIRSHIP_RANGE_BONUS
	return 0.0


func _ready() -> void:
	_im = ImmediateMesh.new()
	mesh = _im
	material_override = TerrainRing.make_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func toggle() -> void:
	enabled = not enabled
	if not enabled and _im != null:
		_im.clear_surfaces()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_ranges"):
		toggle()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not enabled or _unit_manager == null or _im == null:
		return
	_im.clear_surfaces()
	for unit in _unit_manager.units:
		if unit.tribe_id != _player_id or unit.state == Unit.State.DEAD:
			continue
		if unit.siege_engine != null:
			continue   # siege crew: no range of its own
		var r: float = range_for_kind(unit.unit_kind())
		if r <= 0.0:
			continue
		# Garrisoned tower crew (7h): the real reach is +3 m, centred on the
		# tower, not the crew's platform position.
		var origin: Vector3 = unit.position
		if unit.garrison_housed and unit.garrison_target != null \
				and is_instance_valid(unit.garrison_target):
			origin = unit.garrison_target.center_world()
			r += Watchtower.TOWER_RANGE_BONUS
		TerrainRing.add_band(_im, origin, r, _terrain_data,
			_color_for(unit.unit_kind()))
		# Catapults also show a dim inner minimum-range ring.
		if unit is SiegeEngine:
			TerrainRing.add_band(_im, unit.position, SiegeEngine.MIN_RANGE,
				_terrain_data, C_SIEGE_MIN, 0.15)


static func _color_for(kind: StringName) -> Color:
	match kind:
		&"firewarrior":
			return C_FIREWARRIOR
		&"preacher":
			return C_PREACHER
		&"siege", &"fireram":
			return C_SIEGE
		&"airship":
			return C_AIRSHIP
	return Color.WHITE
