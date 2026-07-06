class_name VolcanoZone extends Node3D

## The volcano's eruption controller: sits on the growing cone for LIFETIME
## seconds. Once the cone has reached its full height (the morph is done),
## the crater starts to erupt: every SURGE_INTERVAL a LavaSurge wells up and
## runs down ALL flanks simultaneously (ignites everything it covers — lava
## knows no friends — and leaves a black scorch skirt), and an ANIMATED
## smoke column rises from the crater (looping puffs that grow and fade;
## in-game only). Buildings in reach take +1 destruction stage every
## STAGE_INTERVAL. The mountain underneath is permanent and stays after the
## zone despawns. Ticked via the UnitManager projectile list.

const LIFETIME: float = 20.0
const RADIUS: float = 5.0
const STAGE_INTERVAL: float = 4.0
## Eruptions start only once the cone is at max height (morph duration).
const SURGE_START: float = VolcanoSpell.DURATION
const SURGE_INTERVAL: float = 4.5
## Smoke animation: puff cycle length, rise height and speed source values.
const SMOKE_PUFFS: int = 5
const SMOKE_CYCLE: float = 3.2
const SMOKE_RISE: float = 4.5

var done: bool = false
var tribe_id: int = 0
var unit_manager: UnitManager = null
var terrain_data: TerrainData = null
var building_manager: BuildingManager = null

var _time: float = 0.0
var _stage_timer: float = STAGE_INTERVAL
var _surge_timer: float = 0.0
var _smoke: Array[MeshInstance3D] = []
var _smoke_mats: Array[StandardMaterial3D] = []


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
	_time += delta
	if _time >= LIFETIME:
		done = true
		return
	# Ride the growing cone (crater visuals rise with the tip).
	if terrain_data != null:
		position.y = terrain_data.get_height(position.x, position.z)
	if _time >= SURGE_START:
		_surge_timer -= delta
		if _surge_timer <= 0.0:
			_surge_timer = SURGE_INTERVAL
			_spawn_surge()
	_animate_smoke()
	_stage_timer -= delta
	if _stage_timer <= 0.0:
		_stage_timer = STAGE_INTERVAL
		_wreck_buildings()


## Liquid lava wells up at the crater and races down every flank at once.
func _spawn_surge() -> void:
	if unit_manager == null:
		return
	var surge: LavaSurge = LavaSurge.new()
	surge.setup(position, unit_manager, terrain_data, RADIUS + 0.5)
	unit_manager.register_projectile(surge)


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


# --- Animated smoke column (in-game only) ----------------------------------------------

## Looping puffs: each rises out of the crater, swells and fades, phase-
## shifted against the others — a continuous column. Hidden until the cone
## has reached its full height.
func _animate_smoke() -> void:
	if _smoke.is_empty():
		return
	var active: bool = _time >= SURGE_START
	for i in range(_smoke.size()):
		var puff: MeshInstance3D = _smoke[i]
		puff.visible = active
		if not active:
			continue
		var t: float = fposmod((_time - SURGE_START) / SMOKE_CYCLE
			+ float(i) / float(SMOKE_PUFFS), 1.0)
		puff.position = Vector3(
			0.4 * sin(_time * 0.7 + float(i) * 2.1),
			VolcanoSpell.PEAK + 0.4 + t * SMOKE_RISE,
			0.4 * cos(_time * 0.6 + float(i) * 1.3))
		var s: float = 0.5 + t * 1.6
		puff.scale = Vector3(s, s, s)
		_smoke_mats[i].albedo_color.a = 0.5 * (1.0 - t)


func _ready() -> void:
	for i in range(SMOKE_PUFFS):
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.33, 0.32, 0.5)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var puff: MeshInstance3D = MeshInstance3D.new()
		var s: SphereMesh = SphereMesh.new()
		s.radius = 0.7
		s.height = 1.1
		puff.mesh = s
		puff.material_override = mat
		puff.visible = false
		add_child(puff)
		_smoke.append(puff)
		_smoke_mats.append(mat)
