class_name SwarmCloud extends Node3D

## The insect swarm entity: lives for LIFETIME seconds, drifts randomly and
## panics enemy units close to it (6 s each, refreshed while they stay near)
## while dealing light damage. The caster's shaman is panic-immune but not
## damage-immune (she belongs to the caster's tribe anyway); ENEMY shamans
## shrug off the panic too (Unit.is_panic_immune) but take the damage.
## Ticked via the UnitManager projectile list.

const LIFETIME: float = 10.0
const RADIUS: float = 3.0
const DPS: int = 3                  # light damage per second near the swarm
const DRIFT_SPEED: float = 1.5
const REDIRECT_INTERVAL: float = 1.2
const EFFECT_INTERVAL: float = 0.4  # panic refresh cadence
const HOVER: float = 1.4

var done: bool = false
var tribe_id: int = 0
var unit_manager: UnitManager = null
var terrain_data: TerrainData = null

var _life: float = LIFETIME
var _drift: Vector3 = Vector3.ZERO
var _redirect: float = 0.0
var _effect_timer: float = 0.0
var _damage_timer: float = 1.0


func setup(p_tribe_id: int, at: Vector3, p_unit_manager: UnitManager,
		p_terrain_data: TerrainData) -> void:
	tribe_id = p_tribe_id
	position = at
	unit_manager = p_unit_manager
	terrain_data = p_terrain_data


func tick(delta: float) -> void:
	if done:
		return
	_life -= delta
	if _life <= 0.0:
		done = true
		return
	_tick_drift(delta)
	_effect_timer -= delta
	if _effect_timer <= 0.0:
		_effect_timer = EFFECT_INTERVAL
		_panic_nearby()
	_damage_timer -= delta
	if _damage_timer <= 0.0:
		_damage_timer = 1.0
		_sting_nearby()


func _tick_drift(delta: float) -> void:
	_redirect -= delta
	if _redirect <= 0.0:
		_redirect = REDIRECT_INTERVAL + randf() * 0.8
		var angle: float = randf() * TAU
		_drift = Vector3(cos(angle), 0.0, sin(angle)) * DRIFT_SPEED
	position += _drift * delta
	var limit: float = float(terrain_data.size if terrain_data != null else TerrainData.SIZE) * TerrainData.CELL_SIZE - 1.0
	position.x = clampf(position.x, 1.0, limit)
	position.z = clampf(position.z, 1.0, limit)
	if terrain_data != null:
		position.y = terrain_data.get_height(position.x, position.z) + HOVER


func _panic_nearby() -> void:
	if unit_manager == null:
		return
	for u in unit_manager.get_units_in_radius(position, RADIUS):
		if u.state == Unit.State.DEAD or u.tribe_id == tribe_id:
			continue
		u.start_panic(position)   # panic-immune units (shamans) ignore this


func _sting_nearby() -> void:
	if unit_manager == null:
		return
	for u in unit_manager.get_units_in_radius(position, RADIUS):
		if u.state == Unit.State.DEAD or u.tribe_id == tribe_id:
			continue
		u.take_damage(DPS)


func _ready() -> void:
	# Placeholder swarm visual: a loose cluster of small dark spheres.
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.12, 0.05)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in range(7):
		var dot: MeshInstance3D = MeshInstance3D.new()
		var s: SphereMesh = SphereMesh.new()
		s.radius = 0.12
		s.height = 0.24
		dot.mesh = s
		dot.material_override = mat
		var angle: float = TAU * float(i) / 7.0
		dot.position = Vector3(cos(angle) * 0.5, 0.3 * sin(float(i) * 1.7), sin(angle) * 0.5)
		add_child(dot)
