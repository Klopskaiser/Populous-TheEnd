class_name VolcanoZone extends Node3D

## The volcano's eruption controller: sits on the (growing) cone for
## LIFETIME seconds and regularly releases LAVA FLOWS out of the crater that
## run down the flanks (LavaFlow: ignites everything it touches — lava knows
## no friends — and blackens the ground as it cools). Buildings in reach of
## the eruption take +1 destruction stage every STAGE_INTERVAL (first hit
## after one full interval of contact). Placeholder visual: a smoke column
## above the crater. The mountain underneath is permanent and stays after
## the zone despawns. Ticked via the UnitManager projectile list.

const LIFETIME: float = 20.0
const RADIUS: float = 5.0
const STAGE_INTERVAL: float = 4.0
## Lava flows: the first once the cone has some height, then regularly,
## fanned out around the crater (deterministic base angle from the cell).
const FLOW_START_DELAY: float = 1.5
const FLOW_INTERVAL: float = 2.5

var done: bool = false
var tribe_id: int = 0
var unit_manager: UnitManager = null
var terrain_data: TerrainData = null
var building_manager: BuildingManager = null

var _life: float = LIFETIME
var _stage_timer: float = STAGE_INTERVAL
var _flow_timer: float = FLOW_START_DELAY
var _flow_count: int = 0
var _base_angle: float = 0.0


func setup(p_tribe_id: int, at: Vector3, p_unit_manager: UnitManager,
		p_terrain_data: TerrainData, p_building_manager: BuildingManager) -> void:
	tribe_id = p_tribe_id
	position = at
	unit_manager = p_unit_manager
	terrain_data = p_terrain_data
	building_manager = p_building_manager
	var cell: Vector2i = Vector2i(int(floor(at.x)), int(floor(at.z)))
	_base_angle = float((cell.x * 7 + cell.y * 13) % 16) * TAU / 16.0


func tick(delta: float) -> void:
	if done:
		return
	_life -= delta
	if _life <= 0.0:
		done = true
		return
	# Ride the growing cone (the smoke column rises with the crater).
	if terrain_data != null:
		position.y = terrain_data.get_height(position.x, position.z)
	_flow_timer -= delta
	if _flow_timer <= 0.0:
		_flow_timer = FLOW_INTERVAL
		_spawn_flow()
	_stage_timer -= delta
	if _stage_timer <= 0.0:
		_stage_timer = STAGE_INTERVAL
		_wreck_buildings()


## One lava stream out of the crater, fanned around the tip so successive
## flows cover different flanks; it steers itself downhill from there.
func _spawn_flow() -> void:
	if unit_manager == null:
		return
	var angle: float = _base_angle + TAU * float(_flow_count) / 7.0
	_flow_count += 1
	var dir: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
	var flow: LavaFlow = LavaFlow.new()
	flow.setup(position + dir * 0.4, dir, unit_manager, terrain_data)
	unit_manager.register_projectile(flow)


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
	# Placeholder smoke column above the crater: stacked grey puffs.
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.33, 0.32, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in range(5):
		var puff: MeshInstance3D = MeshInstance3D.new()
		var s: SphereMesh = SphereMesh.new()
		var r: float = 0.6 + 0.35 * float(i)
		s.radius = r
		s.height = r * 1.6
		puff.mesh = s
		puff.material_override = mat
		puff.position = Vector3(0.25 * float(i % 3) - 0.25,
			VolcanoSpell.PEAK + 0.6 + 1.1 * float(i), 0.2 * float(i % 2))
		add_child(puff)