class_name VolcanoZone extends Node3D

## The volcano's eruption controller: sits on the growing cone for LIFETIME
## seconds. Once the cone has reached its full height (the morph is done),
## the crater starts to erupt: every SURGE_INTERVAL a LavaSurge wells up and
## runs down ALL flanks simultaneously (leaves a black scorch skirt), and an
## ANIMATED smoke column rises from the crater (looping puffs that grow and
## fade; in-game only). While erupting the zone itself CONTINUOUSLY ignites
## every unit in the lava reach — lava knows no friends, and the per-surge
## molten window alone left burn-free gaps between waves. Buildings are
## wrecked by actual lava contact only (Building.add_lava_contact via the
## surges — one stage per full contact interval). The mountain underneath is
## permanent and stays after the zone despawns. Ticked via the UnitManager
## projectile list.

const LIFETIME: float = Balance.VOLCANO_ZONE_LIFETIME
const RADIUS: float = 5.0
## How far the lava sheets run past the cone (surge radius = lava reach).
const LAVA_REACH: float = RADIUS + 2.5
## Eruptions start only once the cone is at max height (morph duration).
const SURGE_START: float = VolcanoSpell.DURATION
const SURGE_INTERVAL: float = 4.5
const IGNITE_INTERVAL: float = 0.2
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
var _surge_timer: float = 0.0
var _ignite_timer: float = 0.0
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
		_ignite_timer -= delta
		if _ignite_timer <= 0.0:
			_ignite_timer = IGNITE_INTERVAL
			_ignite_covered_units()
	_animate_smoke()


## Liquid lava wells up at the crater and races down every flank at once,
## reaching past the foot of the mountain (a ring around its base).
func _spawn_surge() -> void:
	if unit_manager == null:
		return
	var surge: LavaSurge = LavaSurge.new()
	surge.setup(position, unit_manager, terrain_data, LAVA_REACH, building_manager)
	unit_manager.register_projectile(surge)


## Continuous burn while the volcano is erupting: units anywhere in the lava
## reach ignite, independent of the individual surges' molten windows (those
## alone left ~1 s burn-free gaps between waves). Same skip rule as LavaSurge:
## airborne (THROWN) units pass over the lava.
func _ignite_covered_units() -> void:
	if unit_manager == null:
		return
	for u in unit_manager.get_units_in_radius(position, LAVA_REACH):
		if u.state == Unit.State.DEAD or u.is_airborne():
			continue   # airborne units (thrown, airship deck) pass over the lava
		u.ignite(position)


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
