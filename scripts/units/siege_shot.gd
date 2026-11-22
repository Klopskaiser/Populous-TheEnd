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
## Air intercept (vs airships): the stone hits when it passes this close to a
## hull (XZ + height window); the air burst has DOUBLE the ground area
## (radius x sqrt(factor)) and produces NO lava and no building damage.
const AIR_INTERCEPT_RADIUS: float = Balance.SIEGE_SHOT_AIR_INTERCEPT_RADIUS
const AIR_INTERCEPT_HEIGHT: float = 2.0
const AIR_SPLASH_FACTOR: float = Balance.SIEGE_SHOT_AIR_SPLASH_FACTOR
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
## True when the shot was AIMED at an airship: a miss fizzles in the air
## (no phantom lava on the ground far below the dodged hull).
var air_shot: bool = false
var shooter = null   # untyped: the engine may sink mid-flight
var unit_manager: UnitManager = null
var terrain_data: TerrainData = null
var building_manager: BuildingManager = null

## Look only, handed over by a catapult whose model carries a "Stone" (see
## SiegeEngine._dress_shot): that stone flies instead of the fireball. It stays
## hidden for `release_delay` seconds — it still rides the arm — and then shows
## up at `release_from`, the point where the arm lets go of it. From there it
## closes in on the simulated arc; the arc itself, and with it every hit, is
## untouched.
var stone_mesh: Mesh = null
var stone_scale: Vector3 = Vector3.ONE
var release_from: Vector3 = Vector3.ZERO
var release_delay: float = 0.0
## The released stone has caught up with the simulated arc at this share of the flight.
const RELEASE_BLEND_END: float = 0.6
## Tumble of the flying stone (rad/s) and size of its embers next to the fireball's.
const STONE_SPIN: float = 7.0
const STONE_EMBER_SCALE: float = 0.7
## The stone flies larger than it lies in the bucket (0.34 m there): at the
## game's default zoom a metre is about 16 pixels, and an incoming shot has to
## stay readable. The fireball it replaces was 0.9 m across.
const STONE_FLIGHT_SCALE: float = 1.6

var _start: Vector3 = Vector3.ZERO
var _travelled: float = 0.0
var _total: float = 0.0
var _trail: Array[MeshInstance3D] = []
var _trail_timer: float = 0.0
var _ball: MeshInstance3D = null
var _age: float = 0.0
var _release_frac: float = -1.0
var _release_offset: Vector3 = Vector3.ZERO


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
	if _check_air_intercept():
		return
	_tick_look(delta, t)
	_tick_trail(delta)
	if t >= 1.0:
		if air_shot:
			done = true   # the hull dodged — the stone fizzles in the air
			_clear_trail()
			return
		_impact()


## Enemy airship hull(s) passing close to the stone: the shot bursts in the air
## — EVERY enemy hull the stone brushes past (XZ + height window) takes a hull
## hit at once, so a tight formation can be cleared with a single shot. Plus a
## shockwave with DOUBLE the ground area centred on the burst (deck crews and
## units under the ships take it via the flat radius); no lava, no building
## damage. Returns true when it intercepted at least one hull.
func _check_air_intercept() -> bool:
	if unit_manager == null:
		return false
	var hulls: Array = []
	for u in unit_manager.get_units_in_radius(position, AIR_INTERCEPT_RADIUS):
		if not (u is Airship) or u.state == Unit.State.DEAD or u.tribe_id == tribe_id:
			continue
		if absf(u.position.y - position.y) > AIR_INTERCEPT_HEIGHT:
			continue
		hulls.append(u)
	if hulls.is_empty():
		return false
	done = true
	_clear_trail()
	# Burst centred on the first hull brushed — the ships are within the small
	# intercept radius of the stone, so one shockwave covers the whole cluster.
	var center: Vector3 = (hulls[0] as Airship).position
	if is_inside_tree():
		var audio: Node = get_node_or_null("/root/AudioManager")
		if audio != null:
			audio.play_sfx(&"siege_impact", center)
	for h in hulls:
		(h as Airship).register_hull_hit(position)
	_shockwave(center, SHOCK_RADIUS * sqrt(AIR_SPLASH_FACTOR))
	return true


func _clear_trail() -> void:
	for ember in _trail:
		if is_instance_valid(ember):
			ember.queue_free()
	_trail.clear()


func _impact() -> void:
	done = true
	# The shot node is freed right after `done` — take the tail with it.
	_clear_trail()
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
			# stationed inside an enemy building is hurled out VISIBLY with one
			# brave life of damage — weak units collapse once their tumble ends,
			# tough ones survive hurt. Never silently deleted.
			building.eject_occupants(true)
		# Full destruction stage (construction sites shatter — fragile rule).
		building.apply_destruction_stages(Balance.SIEGE_SHOT_BUILDING_STAGES)
		_spawn_lava(false)   # the shot already did the building damage
	else:
		_spawn_lava(true)
	_shockwave(target_pos, SHOCK_RADIUS)


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
	surge.lifetime = Balance.LAVA_CATAPULT_LIFETIME
	unit_manager.register_projectile(surge)


## 1/4 brave life to every unit in the radius (friendly fire — positioning is
## tactical); enemies are knocked over with a slope-dependent roll chance.
## The air intercept passes the hull position and a widened radius.
func _shockwave(center: Vector3, radius: float) -> void:
	# A giant golem is hit by his BODY, not by his centre point: the query is
	# widened by the largest body there can be and every unit is then tested
	# against its own body radius (0 for everyone else).
	var widest: float = maxf(maxf(Balance.GOLEM_BODY_HALF_WIDTH * Golem.max_size_factor(),
		DemonGolem.max_body_radius()), GenesisGolem.max_body_radius())
	for u in unit_manager.get_units_in_radius(center, radius + widest):
		if u.state == Unit.State.DEAD or u == shooter:
			continue
		var dist: float = Vector2(u.position.x - center.x, u.position.z - center.z).length()
		if dist > radius + u.body_hit_radius():
			continue
		var attacker = shooter if (shooter != null and is_instance_valid(shooter)) else null
		u.take_damage(u.siege_shock_damage(SHOCK_DAMAGE, dist), attacker)
		if u.state == Unit.State.DEAD:
			continue
		if u.tribe_id == tribe_id:
			continue   # allies take the hit but are not bowled over
		var away: Vector3 = Vector3(u.position.x - center.x, 0.0,
			u.position.z - center.z)
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
	_ball = ball
	# No real shadow (phase 8 rule): a glowing stone casts none.
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if stone_mesh != null:
		# The stone of the catapult model, with the materials it came with.
		ball.mesh = stone_mesh
		ball.scale = stone_scale * STONE_FLIGHT_SCALE
		ball.visible = release_delay <= 0.0
		add_child(ball)
		return
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


## The model stone: hidden while it rides the arm, then from the release point
## onto the simulated arc, tumbling.
func _tick_look(delta: float, flown: float) -> void:
	if _ball == null or stone_mesh == null:
		return
	_age += delta
	if _age < release_delay:
		return
	if _release_frac < 0.0:
		_release_frac = flown
		_release_offset = release_from - global_position if release_delay > 0.0 else Vector3.ZERO
		_ball.visible = true
	var closed: float = 1.0
	if _release_frac < RELEASE_BLEND_END:
		closed = smoothstep(_release_frac, RELEASE_BLEND_END, flown)
	_ball.position = _release_offset * (1.0 - closed)
	_ball.rotate_x(STONE_SPIN * delta)


## Fading tail: small embers dropped along the arc (cheap, a handful of
## spheres that shrink and free themselves).
func _tick_trail(delta: float) -> void:
	if not is_inside_tree():
		return
	if _ball != null and not _ball.visible:
		return   # the stone has not left the arm yet
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
	ember.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	if stone_mesh != null:
		ember.scale = Vector3.ONE * STONE_EMBER_SCALE
	ember.global_position = _ball.global_position if _ball != null else global_position
	_trail.append(ember)
