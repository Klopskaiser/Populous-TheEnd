class_name VolcanoZone extends Node3D

## The volcano's lava zone: stationary on the (growing) cone for LIFETIME
## seconds. Lava knows no friends (documented design): ALL units in the
## radius take DPS damage per second — including the caster's own — and ALL
## buildings in reach take +1 destruction stage every STAGE_INTERVAL (first
## hit after one full interval of contact). The mountain underneath is
## permanent and stays after the zone despawns. Ticked via the UnitManager
## projectile list.

const LIFETIME: float = 20.0
const RADIUS: float = 5.0
const DPS: int = 10
const STAGE_INTERVAL: float = 4.0

var done: bool = false
var tribe_id: int = 0
var unit_manager: UnitManager = null
var terrain_data: TerrainData = null
var building_manager: BuildingManager = null

var _life: float = LIFETIME
var _damage_timer: float = 1.0
var _stage_timer: float = STAGE_INTERVAL


func setup(p_tribe_id: int, at: Vector3, p_unit_manager: UnitManager,
		p_terrain_data: TerrainData, p_building_manager: BuildingManager) -> void:
	tribe_id = p_tribe_id
	position = at
	unit_manager = p_unit_manager
	terrain_data = p_terrain_data
	building_manager = p_building_manager


func tick(delta: float) -> void:
	if done:
		return
	_life -= delta
	if _life <= 0.0:
		done = true
		return
	# Ride the growing cone.
	if terrain_data != null:
		position.y = terrain_data.get_height(position.x, position.z)
	_damage_timer -= delta
	if _damage_timer <= 0.0:
		_damage_timer = 1.0
		_burn_units()
	_stage_timer -= delta
	if _stage_timer <= 0.0:
		_stage_timer = STAGE_INTERVAL
		_wreck_buildings()


func _burn_units() -> void:
	if unit_manager == null:
		return
	for u in unit_manager.get_units_in_radius(position, RADIUS):
		if u.state == Unit.State.DEAD:
			continue
		u.take_damage(DPS)   # no tribe filter: lava burns everyone


func _wreck_buildings() -> void:
	if building_manager == null:
		return
	var flat: Vector2 = Vector2(position.x, position.z)
	for b in building_manager.buildings.duplicate():
		if not is_instance_valid(b) or b.health <= 0:
			continue
		var c: Vector3 = b.center_world()
		if Vector2(c.x, c.z).distance_to(flat) <= RADIUS:
			b.apply_destruction_stages(1)


func _ready() -> void:
	# Placeholder lava: a glowing dome plus a ring of ember blobs.
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.08, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var dome: MeshInstance3D = MeshInstance3D.new()
	var s: SphereMesh = SphereMesh.new()
	s.radius = 1.1
	s.height = 1.4
	dome.mesh = s
	dome.material_override = mat
	dome.position.y = 0.4
	add_child(dome)
	for i in range(8):
		var blob: MeshInstance3D = MeshInstance3D.new()
		var bs: SphereMesh = SphereMesh.new()
		bs.radius = 0.3
		bs.height = 0.45
		blob.mesh = bs
		blob.material_override = mat
		var angle: float = TAU * float(i) / 8.0
		var r: float = 1.8 + 0.9 * float(i % 3)
		blob.position = Vector3(cos(angle) * r, 0.15, sin(angle) * r)
		add_child(blob)
