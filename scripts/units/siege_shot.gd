class_name SiegeShot extends Node3D

## The siege engine's projectile (phase 7f): a BIG fireball in a high arc
## with a glowing tail, flying to a fixed target point (no homing). Ticked by
## the UnitManager's projectile list; `done` marks it for removal.
##
## Impact:
## - ENEMY building under the impact point (footprint grown by 1, like the
##   lightning): +1 destruction stage AND every unit stationed INSIDE dies
##   (trainee / housed forester workers).
## - OWN building under the impact point, but ONLY while enemy raiders demolish
##   it from the inside (anti-raider bombardment): the raiders are thrown back
##   out HURT (they resume the assault or turn on the catapult), and the own
##   building pays +1 destruction stage per hit. Own buildings WITHOUT raiders
##   are never damaged (frustration guard).
## - Always: a SMALL, quickly vanishing lava puddle at the impact centre
##   (usual lava effects: ignite + burn panic). When the shot already damaged
##   a building, the puddle does NOT wreck buildings on top of that; on open
##   ground it does (sustained-contact rule, Building.add_lava_contact).
## - Always: a shockwave in SHOCK_RADIUS — 1/4 brave life to EVERY unit
##   (stones know no friends), and ENEMIES are knocked into a roll with a
##   slope-dependent chance (flat 40% / mild 80% / steep 100%); the roll
##   lasts at least MIN_ROLL_DURATION even on flat ground.

const SPEED: float = 12.0
const ARC_HEIGHT: float = 6.0          # high mortar arc
const SHOCK_RADIUS: float = Balance.SIEGE_SHOT_SHOCK_RADIUS
const SHOCK_DAMAGE: int = Balance.SIEGE_SHOT_SHOCK_DAMAGE
## Slope thresholds (rise per metre) for the roll chance bands.
const SLOPE_MILD: float = 0.2
const SLOPE_STEEP: float = 0.6
const ROLL_CHANCE_FLAT: float = 0.4
const ROLL_CHANCE_MILD: float = 0.8
const ROLL_CHANCE_STEEP: float = 1.0
## Flat-ground rolls are short but never below this (spec: min 1 s).
const MIN_ROLL_DURATION: float = 1.0
## Small lava puddle at the impact (LavaSurge with a tiny radius).
const LAVA_RADIUS: float = 0.8

var done: bool = false
var tribe_id: int = 0
var target_pos: Vector3 = Vector3.ZERO
var shooter = null   # untyped: the engine may sink mid-flight
var unit_manager: UnitManager = null
var terrain_data: TerrainData = null
var building_manager: BuildingManager = null

var _start: Vector3 = Vector3.ZERO
var _travelled: float = 0.0
var _total: float = 0.0
var _trail: Array[MeshInstance3D] = []
var _trail_timer: float = 0.0


func setup(p_tribe_id: int, from: Vector3, to: Vector3, p_shooter,
		p_unit_manager: UnitManager, p_terrain_data: TerrainData,
		p_building_manager: BuildingManager) -> void:
	tribe_id = p_tribe_id
	_start = from + Vector3(0.0, 1.4, 0.0)
	target_pos = to
	shooter = p_shooter
	unit_manager = p_unit_manager
	terrain_data = p_terrain_data
	building_manager = p_building_manager
	position = _start
	_total = maxf(Vector2(to.x - from.x, to.z - from.z).length(), 0.1)


func tick(delta: float) -> void:
	if done:
		return
	_travelled += SPEED * delta
	var t: float = clampf(_travelled / _total, 0.0, 1.0)
	position = _start.lerp(target_pos, t)
	position.y += sin(t * PI) * ARC_HEIGHT
	_tick_trail(delta)
	if t >= 1.0:
		_impact()


func _impact() -> void:
	done = true
	# The shot node is freed right after `done` — take the tail with it.
	for ember in _trail:
		if is_instance_valid(ember):
			ember.queue_free()
	_trail.clear()
	if is_inside_tree():
		var audio: Node = get_node_or_null("/root/AudioManager")
		if audio != null:
			audio.play_sfx(&"siege_impact", target_pos)
	if unit_manager == null:
		return
	var building = _building_at_impact()
	if building != null:
		if building.tribe_id == tribe_id:
			# Own raided building: blast the raiders back out hurt; the
			# building pays the same stage as any other hit.
			building.blast_raiders(Balance.SIEGE_SHOT_RAIDER_DAMAGE,
				shooter if (shooter != null and is_instance_valid(shooter)) else null)
		else:
			# Ranged rule (same as firewarrior fire reaching stage 1): everyone
			# stationed inside an enemy building dies VISIBLY — ejected into the
			# world, rolling away from the building, collapsing once at rest.
			# Never silently deleted: the defender must see the crew fall.
			building.eject_occupants(true)
		# Full destruction stage (construction sites shatter — fragile rule).
		building.apply_destruction_stages(Balance.SIEGE_SHOT_BUILDING_STAGES)
		_spawn_lava(false)   # the shot already did the building damage
	else:
		_spawn_lava(true)
	_shockwave()


## Building whose (slightly grown) footprint contains the impact cell — the
## lightning's search pattern. Own buildings only count while enemy raiders
## demolish them from the inside (anti-raider bombardment); otherwise they are
## skipped entirely (frustration guard).
func _building_at_impact():
	if building_manager == null:
		return null
	var cell: Vector2i = Vector2i(
		int(floor(target_pos.x / TerrainData.CELL_SIZE)),
		int(floor(target_pos.z / TerrainData.CELL_SIZE)))
	for b in building_manager.buildings:
		if not is_instance_valid(b) or b.health <= 0:
			continue
		if b.tribe_id == tribe_id and not b.has_raiders():
			continue   # own buildings are never damaged (frustration guard)
		if Rect2i(b.cell, b.footprint).grow(1).has_point(cell):
			return b
	return null




## Small, quickly vanishing lava puddle at the impact centre (usual lava
## mechanics: contact damage + burn panic via LavaSurge/ignite). With
## `wreck_buildings` off (the shot itself already damaged a building) the
## puddle never adds building lava contact on top.
func _spawn_lava(wreck_buildings: bool) -> void:
	var surge: LavaSurge = LavaSurge.new()
	surge.setup(Vector3(target_pos.x,
		terrain_data.get_height(target_pos.x, target_pos.z) if terrain_data != null
		else target_pos.y, target_pos.z),
		unit_manager, terrain_data, LAVA_RADIUS, building_manager)
	surge.damage_buildings = wreck_buildings
	unit_manager.register_projectile(surge)


## 1/4 brave life to every unit in the radius (friendly fire — positioning is
## tactical); enemies are knocked over with a slope-dependent roll chance.
func _shockwave() -> void:
	for u in unit_manager.get_units_in_radius(target_pos, SHOCK_RADIUS):
		if u.state == Unit.State.DEAD or u == shooter:
			continue
		var attacker = shooter if (shooter != null and is_instance_valid(shooter)) else null
		u.take_damage(SHOCK_DAMAGE, attacker)
		if u.state == Unit.State.DEAD:
			continue
		if u.tribe_id == tribe_id:
			continue   # allies take the hit but are not bowled over
		var away: Vector3 = Vector3(u.position.x - target_pos.x, 0.0,
			u.position.z - target_pos.z)
		if away.length_squared() < 0.000001:
			away = Vector3(1, 0, 0).rotated(Vector3.UP, randf() * TAU)
		var slope: float = _slope_at(u.position)
		if randf() < roll_chance_for_slope(slope):
			u.start_roll(away.normalized(), MIN_ROLL_DURATION)


## Roll chance from the local slope: flat ground 40%, mild slopes 80%,
## steep slopes always. Static + pure so it is headless-testable.
static func roll_chance_for_slope(slope: float) -> float:
	if slope >= SLOPE_STEEP:
		return ROLL_CHANCE_STEEP
	if slope >= SLOPE_MILD:
		return ROLL_CHANCE_MILD
	return ROLL_CHANCE_FLAT


## Magnitude of the terrain gradient (rise per metre) at a position; 0
## without terrain (tests).
func _slope_at(pos: Vector3) -> float:
	if terrain_data == null:
		return 0.0
	var e: float = 0.5
	var dx: float = terrain_data.get_height(pos.x + e, pos.z) \
		- terrain_data.get_height(pos.x - e, pos.z)
	var dz: float = terrain_data.get_height(pos.x, pos.z + e) \
		- terrain_data.get_height(pos.x, pos.z - e)
	return Vector2(dx / (2.0 * e), dz / (2.0 * e)).length()


# --- Visuals (in-game only) ---------------------------------------------------------

func _ready() -> void:
	var ball: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.45
	sphere.height = 0.9
	ball.mesh = sphere
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.35, 0.05)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball.material_override = mat
	add_child(ball)


## Fading tail: small embers dropped along the arc (cheap, a handful of
## spheres that shrink and free themselves).
func _tick_trail(delta: float) -> void:
	if not is_inside_tree():
		return
	for i in range(_trail.size() - 1, -1, -1):
		var ember: MeshInstance3D = _trail[i]
		if not is_instance_valid(ember):
			_trail.remove_at(i)
			continue
		ember.scale *= maxf(1.0 - 3.0 * delta, 0.0)
		if ember.scale.x < 0.1:
			ember.queue_free()
			_trail.remove_at(i)
	_trail_timer -= delta
	if _trail_timer > 0.0:
		return
	_trail_timer = 0.05
	var ember: MeshInstance3D = MeshInstance3D.new()
	var s: SphereMesh = SphereMesh.new()
	s.radius = 0.22
	s.height = 0.44
	ember.mesh = s
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.7, 0.2, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ember.material_override = mat
	get_parent().add_child(ember)
	ember.global_position = global_position
	_trail.append(ember)
