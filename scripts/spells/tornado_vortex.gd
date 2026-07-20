class_name TornadoVortex extends Node3D

## The tornado entity: lives for `lifetime` seconds and drifts randomly. The
## twister is TRIBE-BLIND (like all terrain violence): buildings under the
## vortex — own ones included — take +1 destruction stage every
## STAGE_INTERVAL, and ANY unit in its path is whirled up to the tip
## (carried via Unit.throw_carrier), briefly dragged along and then flung
## away at high speed; they land with fall damage (1/2 brave life), tumble
## on with the fling's momentum and stand up once slow — water kills
## instantly (all of that is the normal THROWN/ROLL handling). Ticked via
## the UnitManager projectile list; on expiry any remaining riders are flung.

## Size/lifetime are per-instance so a variant (Supertornado) can be bigger:
## a plain tornado keeps the defaults, the Supertornado's main funnel is set
## larger via setup(). Defaults = the normal tornado.
var lifetime: float = Balance.TORNADO_LIFETIME
var radius: float = Balance.TORNADO_RADIUS   # pickup / building-hit radius
var top_height: float = 8.0                  # riders spiral up to the tip
## Movement profile: parks on the cast point first, then crawls off and
## accelerates over ACCEL_TIME up to MAX_SPEED.
const IDLE_TIME: float = 1.0
const ACCEL_TIME: float = 4.0
const MIN_SPEED: float = 0.4
const MAX_SPEED: float = 2.0
const REDIRECT_INTERVAL: float = 1.0
const STAGE_INTERVAL: float = Balance.TORNADO_STAGE_INTERVAL   # +1 stage per interval over a building
const LIFT_TIME: float = 0.9         # seconds to reach the tip
const CARRY_TIME: float = 0.6        # dragged along at the tip before release
const SPIN_SPEED: float = 7.0        # rider angular speed (rad/s)
const FLING_SPEED: float = 12.0      # horizontal release speed
const FLING_UP: float = 3.5
const FALL_DAMAGE: int = Balance.TORNADO_FALL_DAMAGE   # applied on landing

# --- Siege engines (phase 7f) ------------------------------------------------------
## A catapult/fire ram too heavy to whirl up like a unit gets a survival window:
## once it has stood SIEGE_GRACE_TIME continuous seconds inside the influence
## radius the vortex CAPTURES it — from then on it rides along with the drifting
## funnel and rises over SIEGE_RISE_TIME up to the tip, where it bursts into
## SIEGE_WOOD_CHUNKS wood chunks (1 wood each). If the vortex ends before it
## reaches the tip it explodes in mid-air (chunks flung from the current height).
## Leaving the radius BEFORE capture only resets the grace timer (it never left
## the ground, so it cannot drop onto a building). Its crew is sucked up
## separately as normal units.
const SIEGE_GRACE_TIME: float = 1.0
const SIEGE_RISE_TIME: float = 2.0
const SIEGE_WOOD_CHUNKS: int = 2

var done: bool = false
var tribe_id: int = 0
var unit_manager: UnitManager = null
var terrain_data: TerrainData = null
var building_manager: BuildingManager = null

var _life: float = Balance.TORNADO_LIFETIME
var _drift: Vector3 = Vector3.ZERO
var _redirect: float = 0.0
## First building hit fires on contact, then every STAGE_INTERVAL.
var _stage_timer: float = 0.0
var _pickup_timer: float = 0.0
## Rider entries: {unit, time: float, angle: float}.
var _riders: Array = []
## Per not-yet-captured siege engine: seconds continuously within the influence
## radius (the grace timer). Reset when it leaves before SIEGE_GRACE_TIME.
var _siege_timers: Dictionary = {}
## Captured siege engines riding the funnel: {unit, rise: float, angle: float}.
var _siege_riders: Array = []


func setup(p_tribe_id: int, at: Vector3, p_unit_manager: UnitManager,
		p_terrain_data: TerrainData, p_building_manager: BuildingManager,
		p_radius: float = Balance.TORNADO_RADIUS, p_top_height: float = 8.0,
		p_lifetime: float = Balance.TORNADO_LIFETIME) -> void:
	tribe_id = p_tribe_id
	position = at
	unit_manager = p_unit_manager
	terrain_data = p_terrain_data
	building_manager = p_building_manager
	radius = p_radius
	top_height = p_top_height
	lifetime = p_lifetime
	_life = lifetime
	# Spawn on the GROUND under the cast point, never at the target's altitude:
	# casting on a flying airship passes its high y, which would make the vortex
	# form up in the air on the hull and only drop later. Snapping to the terrain
	# here forms it where the ship's shadow is (right under it), so it destroys
	# the airship from the ground up.
	if terrain_data != null:
		position.y = terrain_data.get_height(at.x, at.z)


func tick(delta: float) -> void:
	if done:
		return
	_life -= delta
	if _life <= 0.0:
		_release_all_riders()
		done = true
		return
	_tick_drift(delta)
	_stage_timer -= delta
	if _stage_timer <= 0.0:
		_stage_timer = STAGE_INTERVAL
		_wreck_buildings()
	_pickup_timer -= delta
	if _pickup_timer <= 0.0:
		_pickup_timer = 0.2
		_pick_up_units()
		_shred_trees_and_scatter_piles()
	_tick_riders(delta)
	_affect_siege_engines(delta)
	_affect_airships()


## `_drift` is a unit DIRECTION; the actual speed ramps with age: 1 s parked
## on the cast point, then crawling off and accelerating toward MAX_SPEED.
func _tick_drift(delta: float) -> void:
	var age: float = lifetime - _life
	if age < IDLE_TIME:
		return
	_redirect -= delta
	if _redirect <= 0.0:
		_redirect = REDIRECT_INTERVAL + randf() * 0.6
		var angle: float = randf() * TAU
		_drift = Vector3(cos(angle), 0.0, sin(angle))
	var speed: float = lerpf(MIN_SPEED, MAX_SPEED,
		clampf((age - IDLE_TIME) / ACCEL_TIME, 0.0, 1.0))
	position += _drift * speed * delta
	var limit: float = float(TerrainData.SIZE) * TerrainData.CELL_SIZE - 1.0
	position.x = clampf(position.x, 1.0, limit)
	position.z = clampf(position.z, 1.0, limit)
	if terrain_data != null:
		position.y = terrain_data.get_height(position.x, position.z)


## Buildings whose (slightly grown) footprint contains the vortex take one
## destruction stage per interval — tribe-blind, own buildings included.
func _wreck_buildings() -> void:
	if building_manager == null:
		return
	var cell: Vector2i = Vector2i(
		int(floor(position.x / TerrainData.CELL_SIZE)),
		int(floor(position.z / TerrainData.CELL_SIZE)))
	for b in building_manager.buildings.duplicate():
		if not is_instance_valid(b) or b.health <= 0:
			continue
		if b.footprint_rect().grow(1).has_point(cell):
			b.apply_destruction_stages(1)


## Trees and wood piles caught by the twister are WHIRLED UP like units: each
## becomes a flying TornadoDebris chunk (a tree's model turns into a wood pile as
## it lifts) that spirals up, is flung out and slides to rest as a pile — a
## sapling (no wood) vanishes on impact instead. Phase 7d / 7d-fix.
func _shred_trees_and_scatter_piles() -> void:
	if unit_manager == null:
		return
	var tm: TreeManager = unit_manager.tree_manager
	var wpm: WoodPileManager = unit_manager.wood_pile_manager
	if tm != null:
		for d in tm.uproot_in_radius(position, radius):
			_spawn_debris(d["position"], d["wood"])
	if wpm != null:
		for pile in wpm.piles_in_radius(position, radius):
			var amount: int = pile.amount
			var at: Vector3 = pile.position
			wpm.remove_pile(pile)
			_spawn_debris(at, amount)


## Launches one flying wood chunk from `at` carrying `wood` (0 = a sapling that
## vanishes on landing). With `fling_now` the chunk is flung straight from `at`
## instead of spiralling up the funnel first (mid-air siege explosion).
func _spawn_debris(at: Vector3, wood: int, fling_now: bool = false) -> void:
	if unit_manager == null:
		return
	var debris: TornadoDebris = TornadoDebris.new()
	debris.setup(at, wood, terrain_data, unit_manager.wood_pile_manager, self,
		randf() * TAU, top_height, radius * 0.9, fling_now)
	unit_manager.register_projectile(debris)


## Whirls up ANY unit in the pickup radius (not already airborne) — the
## twister doesn't care whose followers stand in its way. The fall damage
## for the later landing is set at capture.
func _pick_up_units() -> void:
	if unit_manager == null:
		return
	for u in unit_manager.get_units_in_radius(position, radius):
		if u.state == Unit.State.DEAD or u.state == Unit.State.THROWN:
			continue
		u.throw_airborne(Vector3.ZERO, FALL_DAMAGE)
		if u.state != Unit.State.THROWN:
			continue   # could not be thrown (e.g. died)
		u.throw_carrier = self
		_riders.append({"unit": u, "time": 0.0, "angle": randf() * TAU})


## Riders spiral up to the tip, ride along briefly, then get flung outward.
func _tick_riders(delta: float) -> void:
	if _riders.is_empty():
		return
	var kept: Array = []
	for r in _riders:
		var u = r.unit
		if u == null or not is_instance_valid(u) or u.state != Unit.State.THROWN \
				or u.throw_carrier != self:
			continue
		r.time += delta
		r.angle += SPIN_SPEED * delta
		var lift: float = clampf(r.time / LIFT_TIME, 0.0, 1.0)
		var spiral_r: float = lerpf(radius * 0.8, 0.5, lift)   # narrows to the tip
		u.position = Vector3(
			position.x + cos(r.angle) * spiral_r,
			position.y + lift * top_height,
			position.z + sin(r.angle) * spiral_r)
		u.facing = Vector3(cos(r.angle + PI * 0.5), 0.0, sin(r.angle + PI * 0.5))
		if r.time >= LIFT_TIME + CARRY_TIME:
			_fling(u, r.angle)
		else:
			kept.append(r)
	_riders = kept


## Ground vehicles get a grace window before being torn up: a vehicle that has
## stood SIEGE_GRACE_TIME continuous seconds inside the influence radius is
## CAPTURED and starts riding the funnel (see _tick_siege_riders); one that
## drifts out before that only loses its grace timer — it never left the ground,
## so it cannot drop onto a building. Runs every tick with the real delta so the
## timing is exact. Airships are NOT lifted — contact kills them instantly.
func _affect_siege_engines(delta: float) -> void:
	if unit_manager == null:
		return
	_tick_siege_riders(delta)
	var near_now: Dictionary = {}
	for u in unit_manager.get_units_in_radius(position, radius):
		if not (u is CrewedVehicle) or u is Airship or u.state == Unit.State.DEAD:
			continue
		if _is_siege_rider(u):
			continue   # already captured and rising
		near_now[u] = true
		var t: float = float(_siege_timers.get(u, 0.0)) + delta
		_siege_timers[u] = t
		if t >= SIEGE_GRACE_TIME:
			_capture_siege(u as CrewedVehicle)
			_siege_timers.erase(u)
	# Vehicles that left the radius before capture reset their grace timer.
	for engine in _siege_timers.keys():
		if not near_now.has(engine):
			_siege_timers.erase(engine)


func _is_siege_rider(u) -> bool:
	for r in _siege_riders:
		if r.unit == u:
			return true
	return false


## Captures a vehicle into the funnel: from now the vortex drives its position.
func _capture_siege(engine: CrewedVehicle) -> void:
	if not is_instance_valid(engine):
		return
	engine.tornado_capture()
	_siege_riders.append({"unit": engine, "rise": 0.0, "angle": randf() * TAU})


## Captured vehicles spiral around the (drifting) funnel centre and rise to the
## tip over SIEGE_RISE_TIME, then burst. Mirrors _tick_riders but for vehicles,
## which cannot use the normal THROWN rider path.
func _tick_siege_riders(delta: float) -> void:
	if _siege_riders.is_empty():
		return
	var kept: Array = []
	for r in _siege_riders:
		var u = r.unit
		if u == null or not is_instance_valid(u) or u.state == Unit.State.DEAD:
			continue
		r.rise += delta
		r.angle += SPIN_SPEED * delta
		var f: float = clampf(r.rise / SIEGE_RISE_TIME, 0.0, 1.0)
		var spiral_r: float = lerpf(radius * 0.6, 0.4, f)   # narrows to the tip
		u.position = Vector3(
			position.x + cos(r.angle) * spiral_r,
			position.y + f * top_height,
			position.z + sin(r.angle) * spiral_r)
		if r.rise >= SIEGE_RISE_TIME:
			_burst_siege(u as CrewedVehicle)   # reached the tip
		else:
			kept.append(r)
	_siege_riders = kept


## Airship contact (shadow within the funnel): no lift phase — the vortex
## tears the ship apart INSTANTLY (user spec); the explosion hurls the
## passengers down and two wood chunks scatter like any whirled-up wood.
func _affect_airships() -> void:
	if unit_manager == null:
		return
	for u in unit_manager.get_units_in_radius(position, radius):
		if not (u is Airship) or u.state == Unit.State.DEAD:
			continue
		var at: Vector3 = Vector3(u.position.x, position.y, u.position.z)
		(u as Airship).explode()
		for i in range(SIEGE_WOOD_CHUNKS):
			_spawn_debris(at, 1)


## Bursts a captured vehicle at the tip: it releases its crew and is destroyed,
## and two 1-wood chunks are whirled up from its spot (they fling/settle like any
## tornado wood debris).
func _burst_siege(engine: CrewedVehicle) -> void:
	if not is_instance_valid(engine):
		return
	var at: Vector3 = engine.position
	engine.burst_into_wood()
	for i in range(SIEGE_WOOD_CHUNKS):
		_spawn_debris(at, 1)


## Explodes a captured vehicle in MID-AIR: the vortex ended before it reached the
## tip, so the two wood chunks are flung straight from its current height instead
## of spiralling up first.
func _explode_siege_in_air(engine: CrewedVehicle) -> void:
	if not is_instance_valid(engine):
		return
	var at: Vector3 = engine.position
	engine.burst_into_wood()
	for i in range(SIEGE_WOOD_CHUNKS):
		_spawn_debris(at, 1, true)


func _fling(u: Unit, angle: float) -> void:
	var out: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
	u.fling_from_carry(out * FLING_SPEED + Vector3.UP * FLING_UP)


func _release_all_riders() -> void:
	for r in _riders:
		var u = r.unit
		if u != null and is_instance_valid(u) and u.state == Unit.State.THROWN \
				and u.throw_carrier == self:
			_fling(u, r.angle)
	_riders.clear()
	# Captured siege engines that never reached the tip explode where they are.
	for r in _siege_riders:
		var e = r.unit
		if e != null and is_instance_valid(e) and e.state != Unit.State.DEAD:
			_explode_siege_in_air(e as CrewedVehicle)
	_siege_riders.clear()


func _ready() -> void:
	# Placeholder funnel: a dense stack of widening grey rings.
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.75, 0.78, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var count: int = 11
	for i in range(count):
		var ring: MeshInstance3D = MeshInstance3D.new()
		var torus: TorusMesh = TorusMesh.new()
		var t: float = float(i) / float(count - 1)
		var r: float = lerpf(radius * 0.16, radius, t)
		torus.inner_radius = r - 0.22 * (radius / 2.2)
		torus.outer_radius = r
		ring.mesh = torus
		ring.material_override = mat
		ring.position.y = lerpf(0.3, top_height, t)
		add_child(ring)
