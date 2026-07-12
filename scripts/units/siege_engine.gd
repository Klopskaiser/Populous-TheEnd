class_name SiegeEngine extends Unit

## Belagerungswaffe (Katapult, phase 7f): a crewed VEHICLE, not a believer.
##
## - Built by the workshop, manned by braves/combat units (never the shaman).
##   Ownership follows the crew: whoever boards an UNMANNED engine takes it
##   over (convert_to_tribe). Crew members walk on side slots (3 per side).
## - No own hit points and never targetable: attackers, spells and fire go
##   for the CREW instead. Only water kills the device (drown).
## - Movement needs >= 1 boarded crew; firing needs >= 2 (rate scales up to
##   6 crew). Slowest unit (0.75x brave); wide 1x2 m body -> vehicle paths
##   (NavGrid 2x2 clearance).
## - Attack: SiegeShot in a high arc, 15 m range, 3 m minimum. Auto-aggro
##   prioritises enemy BUILDINGS over units (the siege specialist), inverse
##   to every other unit.
## - Rendered as its OWN 3D model (renders_as_sprite false): wooden frame,
##   wheels, throwing arm; the crew stays normal sprites around it.

const MAX_CREW: int = 6
const MIN_MOVE_CREW: int = 1
const MIN_FIRE_CREW: int = 2
## A crew member counts as boarded/serving within this range of the engine.
const BOARD_RANGE: float = 2.5
## Boarded members straying farther than this (self-defence chases) are lost.
const CREW_LEASH: float = 8.0
## Fire range band: beyond FIRE_RANGE it advances, below MIN_RANGE the arc is
## too flat — it holds fire.
const FIRE_RANGE: float = 15.0
const MIN_RANGE: float = 3.0
## Shot cooldown by boarded crew: 2 -> slowest, 6 (full) -> fastest.
const COOLDOWN_MIN_CREW: float = 6.0
const COOLDOWN_FULL_CREW: float = 3.0
## Brave speed 4.0 * 0.5 (slowest unit in the game; user-tuned from 0.75).
const SIEGE_SPEED: float = 2.0
## Crew slot layout: 3 per long side, this far out/apart.
const CREW_SIDE_OFFSET: float = 0.95
const CREW_RANK_SPACING: float = 0.85
## Auto-aggro scan radius (UNITS first, then buildings — user feedback);
## comfortably above the fire range so approaching enemies are engaged early.
const SIEGE_AGGRO: float = 20.0

## How the device can be destroyed (user feedback): fire SPELLS or lava set
## it alight — it burns this long, then sinks into the ground; terrain
## morphing that leaves this height span under the chassis bursts it apart.
## The crew survives both, is released and controllable again.
const VEHICLE_BURN_TIME: float = 3.0
const SINK_SPEED: float = 0.8   # m/s downward while the wreck sinks
## Height span under the chassis that bursts it. Deliberately ABOVE what
## drivable terrain can present (walkable cells allow 1.5 m/cell → ~3 m over
## the vehicle) — only real terrain rips (quake/flatten/sink cliffs) trigger.
const BREAK_HEIGHT_SPAN: float = 3.5
## Chassis sample half-extents (along facing x sideways).
const CHASSIS_HALF_LENGTH: float = 1.1
const CHASSIS_HALF_WIDTH: float = 0.7

const C_WOOD: Color = Color(0.42, 0.29, 0.15)
const C_WOOD_DARK: Color = Color(0.3, 0.2, 0.1)
const C_METAL: Color = Color(0.45, 0.45, 0.48)

## Crew members (untyped entries: may be freed). Includes recruits still
## walking over (not yet boarded).
var crew: Array = []
## `attack_building` (the bombardment target) and `building_manager` (the
## building scan) are inherited from Unit (shared with the phase-7g assault).
## True while the CURRENT target came from an explicit player/AI order — only
## then may the slow catapult APPROACH a unit that is out of the fire band.
## Auto-acquired unit targets are never chased (it is the slowest unit on the
## field — trundling after a fleeing brave was the "drives in, never shoots"
## bug). Cleared on every _end_attack.
var _target_ordered: bool = false

var _fire_cooldown: float = 0.0
var _crew_prune_timer: float = 0.0
## Seconds of burn left after a fire-spell/lava hit (0 = not burning).
var _vehicle_burn: float = 0.0
## The destroyed wreck sinks into the ground (burn/water death).
var _sinking: bool = false
## Height the tornado currently lifts the whole vehicle by (0 = grounded).
var _tornado_lift: float = 0.0
## Own 3D model parts (in-game only, built in _ready).
var _model: Node3D = null
var _arm: Node3D = null
var _flag_mesh: MeshInstance3D = null
var _flame: MeshInstance3D = null
var _arm_anim: float = 1.0


func _init() -> void:
	max_health = 1
	health = 1
	speed = SIEGE_SPEED
	push_immune = true       # pedestrians do not shove the vehicle around
	counts_population = false  # a device, not a believer (no mana, no housing)


func unit_kind() -> StringName:
	return &"siege"


func _is_combatant() -> bool:
	return true


func _is_ranged() -> bool:
	return true   # never takes melee slots; order_attack skips redistribution


func is_targetable() -> bool:
	return false  # attackers go for the crew


## Catapult-vs-catapult (ranged): a catapult MAY aim at another catapult — its
## shot's splash then hits the enemy crew. Every other unit still targets the
## crew, never the vehicle.
func _may_target_vehicle(enemy: Unit) -> bool:
	return enemy is SiegeEngine


func renders_as_sprite() -> bool:
	return false  # own 3D model instead of the sprite MultiMesh


func is_conversion_immune() -> bool:
	return true   # a device, not a believer


func is_panic_immune() -> bool:
	return true


func aggro_radius() -> float:
	return SIEGE_AGGRO


func can_crew_siege() -> bool:
	return false


## Big ring enclosing the vehicle and its side crew (selecting a crew member
## selects the whole catapult — the ring mirrors that).
func selection_ring_scale() -> float:
	return 4.5


## The device takes no damage — attacks hit the crew (spec: catapults cannot
## be attacked directly). Only water destroys it (drown bypasses this).
func take_damage(_amount: int, _attacker = null) -> void:
	pass


## Too heavy for tornado throws, fireball knockback and rolls.
func throw_airborne(_velocity: Vector3, _fall_damage: int = 0) -> void:
	pass


func start_roll(_dir: Vector3, _duration: float = MINI_ROLL_DURATION,
		_initial_speed: float = 0.0) -> void:
	pass


func displace(_dir: Vector3, _dist: float) -> void:
	pass


## Fire spells and lava DO destroy the device (user feedback): it catches
## fire, burns for a moment and then sinks into the ground. The crew is
## released alive at the wreck (it takes the area damage on its own).
func ignite(_source_pos: Vector3) -> void:
	if state == State.DEAD or _vehicle_burn > 0.0:
		return
	_vehicle_burn = VEHICLE_BURN_TIME
	_show_flame(true)


func is_burning() -> bool:
	return _vehicle_burn > 0.0


## Tornado proximity: the vortex lifts the whole vehicle off the ground (the
## crew is sucked up separately as normal units). Set each tornado tick.
func set_tornado_lift(h: float) -> void:
	_tornado_lift = maxf(h, 0.0)


## The tornado tore the catapult apart (phase 7f, user request): it releases
## its crew and is destroyed leaving NOTHING itself — the vortex spawns the
## two wood chunks that scatter like any whirled-up wood.
func burst_into_wood() -> void:
	if state == State.DEAD:
		return
	_tornado_lift = 0.0
	for m in crew.duplicate():
		if is_instance_valid(m):
			m.leave_crew()
	crew.clear()
	attack_building = null
	_vehicle_burn = 0.0
	_show_flame(false)
	if _model != null:
		_model.visible = false
	health = 0
	_die()


## Flooded ground (terrain spells): the wreck goes under — crew released.
func drown() -> void:
	if state == State.DEAD:
		return
	for m in crew.duplicate():
		if is_instance_valid(m):
			m.leave_crew()
	crew.clear()
	_sinking = true
	super.drown()


# --- Vehicle destruction (phase 7f, user feedback) -----------------------------------

## Burn-out and water: the wreck sinks. Terrain rip: it bursts apart
## (debris). Either way the crew survives, is released and controllable.
func _destroy_vehicle(burst: bool) -> void:
	if state == State.DEAD:
		return
	for m in crew.duplicate():
		if is_instance_valid(m):
			m.leave_crew()
	crew.clear()
	attack_building = null
	_vehicle_burn = 0.0
	if burst:
		_show_flame(false)
		if _model != null:
			_model.visible = false
		if path_service != null:
			var debris: BuildingDebris = BuildingDebris.new()
			debris.setup(position, 1.5, terrain_data)
			path_service.register_projectile(debris)
	else:
		_sinking = true
	health = 0
	_die()


## Height span under the chassis (4 corner samples along the facing).
func _chassis_height_span() -> float:
	if terrain_data == null:
		return 0.0
	var forward: Vector3 = facing.normalized() if facing.length_squared() > 0.0 \
		else Vector3(0, 0, 1)
	var right: Vector3 = Vector3(-forward.z, 0.0, forward.x)
	var lo: float = INF
	var hi: float = -INF
	for sf in [-CHASSIS_HALF_LENGTH, CHASSIS_HALF_LENGTH]:
		for sr in [-CHASSIS_HALF_WIDTH, CHASSIS_HALF_WIDTH]:
			var p: Vector3 = position + forward * sf + right * sr
			var h: float = terrain_data.get_height(p.x, p.z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo


# --- Crew management --------------------------------------------------------------

## Registers a unit as (incoming) crew. Refused when full or when a foreign
## unit tries to join a MANNED enemy engine; an unmanned engine accepts any
## tribe (the takeover completes when the recruit boards).
func add_crew(unit) -> bool:
	_prune_crew()
	if unit in crew:
		return true
	if crew.size() >= MAX_CREW:
		return false
	if unit.tribe_id != tribe_id and boarded_count() > 0:
		return false   # manned engines cannot be hijacked while served
	crew.append(unit)
	return true


func remove_crew(unit) -> void:
	crew.erase(unit)


## Crew members currently serving the engine (boarded and within the leash).
func boarded_count() -> int:
	var count: int = 0
	for m in crew:
		if is_instance_valid(m) and m.state != State.DEAD and m.siege_boarded \
				and _flat_dist(m.position, position) <= CREW_LEASH:
			count += 1
	return count


func crew_count() -> int:
	_prune_crew()
	return crew.size()


## A recruit reached the engine: it boards. First boarder of another tribe
## takes the (unmanned) device over; a foreign recruit racing a fresh crew
## loses and is turned away.
func on_crew_boarded(unit) -> void:
	if not (unit in crew):
		return
	if unit.tribe_id != tribe_id:
		if boarded_count() > 0:
			crew.erase(unit)
			unit.leave_crew()
			return
		_switch_owner(unit.tribe)
	unit.siege_boarded = true


## Ownership follows the crew (spec: engines can change hands when the crew
## dies/flees and a new one takes over).
func _switch_owner(new_tribe: Tribe) -> void:
	if new_tribe == null or new_tribe == tribe:
		return
	attack_building = null
	convert_to_tribe(new_tribe)
	_refresh_flag_color()


## Side slot for a crew member: 3 per long side, moving with the vehicle.
## The slot index is the member's position in the crew list (stable enough —
## the list only compacts when members leave).
func crew_slot_position(unit) -> Vector3:
	var index: int = maxi(crew.find(unit), 0)
	var side: float = -1.0 if index % 2 == 0 else 1.0
	var rank: float = float(index / 2) - 1.0
	var forward: Vector3 = facing.normalized() if facing.length_squared() > 0.0 \
		else Vector3(0, 0, 1)
	var right: Vector3 = Vector3(-forward.z, 0.0, forward.x)
	var slot: Vector3 = position + right * side * CREW_SIDE_OFFSET \
		+ forward * rank * CREW_RANK_SPACING
	if terrain_data != null:
		slot.y = terrain_data.get_height(slot.x, slot.z)
	return slot


## Drops freed/dead members, deserters (new orders cleared siege_engine),
## foreign members after an ownership switch and boarded members beyond the
## leash. Recruits still walking over are kept regardless of distance.
## Detached members are released AFTER the list swap — leave_crew mutates
## `crew` via remove_crew, which must not run mid-iteration.
func _prune_crew() -> void:
	var kept: Array = []
	var dropped: Array = []
	for m in crew:
		if not is_instance_valid(m) or m.state == State.DEAD or m.siege_engine != self:
			continue
		if m.tribe_id != tribe_id and m.siege_boarded:
			dropped.append(m)   # converted away / engine changed hands
			continue
		# NOTE: foreign members that have NOT boarded yet are legitimate
		# takeover recruits walking over (an unmanned engine accepts any
		# tribe) — on_crew_boarded settles who wins on arrival.
		if m.siege_boarded and _flat_dist(m.position, position) > CREW_LEASH:
			dropped.append(m)
			continue
		kept.append(m)
	crew = kept
	for m in dropped:
		m.leave_crew()


## Re-summons boarded members that finished a self-defence fight (state fell
## back to IDLE): they return to their slots.
func _resummon_crew() -> void:
	for m in crew:
		if is_instance_valid(m) and m.state == State.IDLE and m.siege_engine == self:
			m._set_state(State.CREW)


# --- Orders & ticking ---------------------------------------------------------------

## Moving needs at least one boarded crew member.
func order_move(target: Vector3, queue_up: bool = false, aggressive: bool = false) -> void:
	if boarded_count() < MIN_MOVE_CREW:
		return
	attack_building = null
	super.order_move(target, queue_up, aggressive)


## Explicit attack order on a unit (right-click, AI): clears a building focus
## and marks the target as ORDERED, so the catapult will close in on it even
## out of the fire band (the only case a unit is chased).
func order_attack(enemy: Unit) -> void:
	attack_building = null
	super.order_attack(enemy)
	_target_ordered = true


## Clearing the attack always drops the "ordered" flag (auto re-targets are
## never treated as ordered chases).
func _end_attack() -> void:
	_target_ordered = false
	super._end_attack()


## Explicit bombard order on an enemy building (right-click, AI): replaces any
## pending route.
func order_attack_building(building) -> void:
	if building == null or not is_instance_valid(building) or building.health <= 0:
		return
	if building.tribe_id == tribe_id:
		return
	_set_building_target(building, false)


## Focuses a building for bombardment. `keep_route` preserves the pending
## (attack-)move waypoint so the catapult carries on to its destination after
## the building falls; explicit orders clear it.
func _set_building_target(building, keep_route: bool) -> void:
	_end_attack()
	if not keep_route:
		waypoint_queue.clear()
	_clear_path()
	attack_building = building
	_set_state(State.ATTACK)


## Vehicle body: paths on the eroded vehicle grid (narrow gaps are closed).
## `_allow_partial` is ignored — vehicle paths stay all-or-nothing.
func _plan_path_to(target: Vector3, _allow_partial: bool = false) -> bool:
	if nav_grid != null:
		var path: PackedVector3Array = nav_grid.find_vehicle_path(position, target)
		if path.is_empty():
			return false
		_path = path
		_path_index = 0
		return true
	return super._plan_path_to(target)


func tick(delta: float) -> void:
	# Burning wreck-to-be: count the fire down, then sink.
	if _vehicle_burn > 0.0 and state != State.DEAD:
		_vehicle_burn -= delta
		if _vehicle_burn <= 0.0:
			_destroy_vehicle(false)
	_crew_prune_timer -= delta
	if _crew_prune_timer <= 0.0:
		_crew_prune_timer = 0.5
		_prune_crew()
		_resummon_crew()
		# Terrain integrity: a spell ripped the ground under the chassis
		# apart (cliff beyond anything drivable) -> the vehicle bursts.
		if state != State.DEAD and _chassis_height_span() > BREAK_HEIGHT_SPAN:
			_destroy_vehicle(true)
	# An unmanned (or under-crewed) vehicle rolls to a stop mid-route.
	if state == State.MOVE and boarded_count() < MIN_MOVE_CREW:
		waypoint_queue.clear()
		_clear_path()
		_set_state(State.IDLE)
	super.tick(delta)
	_tick_visual(delta)


## Auto target acquisition (idle + aggressive move — NO explicit order). The
## siege weapon FIRES at whatever is already in the fire band (units first,
## then buildings) and, finding nothing to shoot, creeps toward the nearest
## enemy BUILDING within aggro (stationary → catchable). It never auto-chases
## a unit: as the slowest thing on the field it would just trundle after a
## fleeing target forever without ever firing. Returns true when it engaged.
func _auto_acquire(delta: float) -> bool:
	if boarded_count() < MIN_FIRE_CREW:
		return false
	if not _due_to_scan(delta):
		return false
	var u: Unit = _nearest_enemy_unit(FIRE_RANGE)
	if u != null:
		_begin_attack(u)   # auto: _target_ordered stays false (no chase)
		return true
	var b = _scan_enemy_building(SIEGE_AGGRO)
	if b != null:
		_set_building_target(b, true)   # keep the move route (resume after)
		return true
	return false


## Aggressive-move auto-engage (Unit._tick_move) and idle both use the same
## acquisition, so a catapult sent into a base stops and bombards reliably.
func _engage_on_sight(delta: float) -> bool:
	return _auto_acquire(delta)


func _tick_idle(delta: float) -> void:
	_auto_acquire(delta)


## Bombardment. A live unit target takes precedence over the building focus;
## a dead/gone target falls back to the building, then to re-acquisition.
func _tick_attack(delta: float) -> void:
	if boarded_count() < MIN_MOVE_CREW:
		attack_building = null
		_end_attack()
		_set_state(State.IDLE)
		return
	if _target_valid(attack_target) and attack_target.tribe_id != tribe_id:
		_bombard_unit(attack_target, delta)
		return
	if attack_target != null:
		_end_attack()   # dead/converted unit target: drop it cleanly
	if attack_building != null and is_instance_valid(attack_building) \
			and attack_building.health > 0 and attack_building.tribe_id != tribe_id:
		# A unit stepping into the fire band interrupts the siege (throttled);
		# the building focus stays as the fallback afterwards.
		if _due_to_scan(delta):
			var u: Unit = _nearest_enemy_unit(FIRE_RANGE)
			if u != null:
				_begin_attack(u)
				return
		_bombard_point(attack_building.center_world(), delta, true)
		return
	attack_building = null
	_retarget_or_idle()


## Re-acquisition after a target is lost — same "fire, don't chase" rule as
## _auto_acquire (the inherited version would lock the nearest enemy UNIT at
## any range and the catapult would trundle after it instead of sieging).
func _retarget_or_idle() -> void:
	_end_attack()
	if boarded_count() >= MIN_FIRE_CREW:
		var u: Unit = _nearest_enemy_unit(FIRE_RANGE)
		if u != null:
			_begin_attack(u)
			return
		var b = _scan_enemy_building(SIEGE_AGGRO)
		if b != null:
			_set_building_target(b, true)   # keep the move route
			return
	# Nothing left to shoot: carry on to the pending (attack-)move destination.
	if not waypoint_queue.is_empty():
		attack_building = null
		_start_path_to(waypoint_queue[0])
		return
	attack_building = null
	_set_state(State.IDLE)


## Unit target: fire while it is in the band. Only an ORDERED target is chased
## when it drifts out of the band; an auto target is dropped instead. A target
## that crept inside the minimum range is swapped for another in-band enemy.
func _bombard_unit(target: Unit, delta: float) -> void:
	var dist: float = _flat_dist(position, target.position)
	if dist > FIRE_RANGE:
		if not _target_ordered:
			_end_attack()
			_retarget_or_idle()
			return
		_in_melee = false
		_approach(target.position, delta)
		_face_point(target.position)
		return
	if dist < MIN_RANGE:
		if _due_to_scan(delta):
			var alt: Unit = _nearest_enemy_unit(FIRE_RANGE)
			if alt != null and alt != target:
				_begin_attack(alt)
				return
		if _has_path():
			_clear_path()
		_in_melee = true
		_face_point(target.position)
		return   # too close — hold fire until it clears the minimum
	_bombard_point(target.position, delta, false)


## Stands in the [MIN_RANGE, FIRE_RANGE] band and fires at a fixed point.
## `approach` closes the gap when the point is beyond the fire range (used for
## buildings — stationary and catchable). Never melees.
func _bombard_point(target_pos: Vector3, delta: float, approach: bool) -> void:
	var dist: float = _flat_dist(position, target_pos)
	if dist > FIRE_RANGE:
		if not approach:
			return
		_in_melee = false
		_approach(target_pos, delta)
		_face_point(target_pos)
		return
	if _has_path():
		_clear_path()
	_face_point(target_pos)
	_in_melee = true
	attack_anim = &"throw"
	if dist < MIN_RANGE:
		return   # arc too flat — holds fire until the target clears the minimum
	var crew_now: int = boarded_count()
	if crew_now < MIN_FIRE_CREW:
		return   # 1 crew can steer but not load and fire
	_fire_cooldown -= delta
	if _fire_cooldown > 0.0:
		return
	_fire_cooldown = fire_cooldown_for_crew(crew_now)
	_launch_shot(target_pos)


## Seconds between shots for a boarded crew of `count` (2 -> 6 s, 6 -> 3 s,
## linear in between; below 2 there is no shot at all).
static func fire_cooldown_for_crew(count: int) -> float:
	if count < MIN_FIRE_CREW:
		return INF
	var t: float = float(clampi(count, MIN_FIRE_CREW, MAX_CREW) - MIN_FIRE_CREW) \
		/ float(MAX_CREW - MIN_FIRE_CREW)
	return lerpf(COOLDOWN_MIN_CREW, COOLDOWN_FULL_CREW, t)


func _launch_shot(target_pos: Vector3) -> void:
	if path_service == null:
		return
	_arm_anim = 0.0   # throwing-arm snap animation
	anim_start_ms = Time.get_ticks_msec()
	var shot: SiegeShot = SiegeShot.new()
	shot.setup(tribe_id, position, target_pos, self, path_service,
		terrain_data, building_manager)
	path_service.register_projectile(shot)
	_emit_combat_hit(&"throw")


## Nearest attackable enemy UNIT within `max_range` that is not inside the
## minimum range (those cannot be hit by the arcing shot). Used with
## FIRE_RANGE so auto-fire only ever locks a target it can hit right away.
func _nearest_enemy_unit(max_range: float) -> Unit:
	if path_service == null:
		return null
	var best: Unit = null
	var best_d: float = max_range
	for u in path_service.get_units_in_radius(position, max_range, SCAN_MAX_CANDIDATES):
		if u == self or u.state == State.DEAD or u.tribe_id == tribe_id:
			continue
		# NOTE (phase 7i): unlike foot units, the catapult MAY bombard units that
		# are being converted (State.SIT) — its splash does not care about the
		# trance. So no SIT skip here.
		# Skip other non-targetable units, but an enemy CATAPULT is fair game
		# (its crew takes the shot's splash) — catapult-vs-catapult.
		if not u.is_targetable() and not (u is SiegeEngine):
			continue
		var d: float = _flat_dist(position, u.position)
		if d < MIN_RANGE or d > max_range:
			continue
		if d < best_d:
			best_d = d
			best = u
	return best


## Nearest living enemy building within `radius`; null without a manager
## (bare tests) or when none is in range.
func _scan_enemy_building(radius: float):
	if building_manager == null:
		return null
	var best = null
	var best_d: float = radius
	for b in building_manager.buildings:
		if not is_instance_valid(b) or b.tribe_id == tribe_id or b.health <= 0:
			continue
		var d: float = _flat_dist(b.center_world(), position)
		if d <= best_d:
			best_d = d
			best = b
	return best


# --- Visuals (own 3D model, in-game only) -------------------------------------------

func _ready() -> void:
	_create_model()
	_refresh_flag_color()


func _create_model() -> void:
	var root: Node3D = Node3D.new()
	root.name = "Model"
	add_child(root)
	_model = root

	# Base frame (the 1x2 m body).
	var frame: MeshInstance3D = MeshInstance3D.new()
	var frame_box: BoxMesh = BoxMesh.new()
	frame_box.size = Vector3(0.9, 0.3, 1.9)
	frame.mesh = frame_box
	frame.material_override = _mat(C_WOOD)
	frame.position.y = 0.45
	root.add_child(frame)

	# Four wheels.
	for sx in [-0.5, 0.5]:
		for sz in [-0.7, 0.7]:
			var wheel: MeshInstance3D = MeshInstance3D.new()
			var cyl: CylinderMesh = CylinderMesh.new()
			cyl.top_radius = 0.28
			cyl.bottom_radius = 0.28
			cyl.height = 0.14
			wheel.mesh = cyl
			wheel.material_override = _mat(C_WOOD_DARK)
			wheel.rotation.z = PI * 0.5
			wheel.position = Vector3(sx, 0.28, sz)
			root.add_child(wheel)

	# Upright supports.
	for sz in [-0.4, 0.4]:
		var post: MeshInstance3D = MeshInstance3D.new()
		var post_box: BoxMesh = BoxMesh.new()
		post_box.size = Vector3(0.12, 0.7, 0.12)
		post.mesh = post_box
		post.material_override = _mat(C_WOOD_DARK)
		post.position = Vector3(0.0, 0.9, sz)
		root.add_child(post)

	# Throwing arm (pivots at the back; snaps up when firing).
	_arm = Node3D.new()
	_arm.position = Vector3(0.0, 1.0, 0.55)
	root.add_child(_arm)
	var arm_mesh: MeshInstance3D = MeshInstance3D.new()
	var arm_box: BoxMesh = BoxMesh.new()
	arm_box.size = Vector3(0.14, 0.1, 1.5)
	arm_mesh.mesh = arm_box
	arm_mesh.material_override = _mat(C_WOOD)
	arm_mesh.position.z = -0.7
	_arm.add_child(arm_mesh)
	var basket: MeshInstance3D = MeshInstance3D.new()
	var basket_sphere: SphereMesh = SphereMesh.new()
	basket_sphere.radius = 0.16
	basket_sphere.height = 0.32
	basket.mesh = basket_sphere
	basket.material_override = _mat(C_METAL)
	basket.position.z = -1.4
	_arm.add_child(basket)

	# Owner flag (recoloured on takeover).
	var pole: MeshInstance3D = MeshInstance3D.new()
	var pole_cyl: CylinderMesh = CylinderMesh.new()
	pole_cyl.top_radius = 0.03
	pole_cyl.bottom_radius = 0.03
	pole_cyl.height = 1.0
	pole.mesh = pole_cyl
	pole.material_override = _mat(C_WOOD_DARK)
	pole.position = Vector3(0.0, 1.1, 0.85)
	root.add_child(pole)
	_flag_mesh = MeshInstance3D.new()
	var flag_box: BoxMesh = BoxMesh.new()
	flag_box.size = Vector3(0.4, 0.25, 0.03)
	_flag_mesh.mesh = flag_box
	_flag_mesh.position = Vector3(0.2, 1.5, 0.85)
	root.add_child(_flag_mesh)

	# Phase 8 shadow rework: units cast no real shadows — the model gets a
	# hardcoded blob quad instead (like the sprite units' blob MultiMesh).
	for m in root.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var blob: MeshInstance3D = MeshInstance3D.new()
	blob.name = "BlobShadow"
	blob.mesh = UnitRenderer.make_blob_mesh(Vector2(1.6, 2.4))
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.position.y = 0.04
	root.add_child(blob)


func _refresh_flag_color() -> void:
	if _flag_mesh == null:
		return
	_flag_mesh.material_override = _mat(TRIBE_COLORS[tribe_id % TRIBE_COLORS.size()])


func _mat(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	return mat


## Lazily built flame overlay while the vehicle burns (in-game only).
func _show_flame(show: bool) -> void:
	if not is_inside_tree():
		return
	if _flame == null:
		if not show:
			return
		_flame = MeshInstance3D.new()
		_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var s: SphereMesh = SphereMesh.new()
		s.radius = 0.6
		s.height = 1.2
		_flame.mesh = s
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.5, 0.1, 0.85)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.4, 0.05)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flame.material_override = mat
		_flame.position.y = 1.2
		add_child(_flame)
	_flame.visible = show


## Rotates the model with the facing, plays the throwing-arm snap, flickers
## the burn flame and sinks the destroyed wreck into the ground.
func _tick_visual(delta: float) -> void:
	if not is_inside_tree():
		return
	if _sinking and state == State.DEAD:
		position.y -= SINK_SPEED * delta
	elif _tornado_lift > 0.0 and terrain_data != null:
		# Whirled up by the tornado: hover above the ground until it bursts.
		position.y = terrain_data.get_height(position.x, position.z) + _tornado_lift
	if facing.length_squared() > 0.000001:
		rotation.y = atan2(facing.x, facing.z)
	if _flame != null and _flame.visible:
		_flame.scale = Vector3.ONE * (0.85 + 0.3 * absf(sin(
			float(Time.get_ticks_msec()) * 0.02)))
	if _arm == null:
		return
	if _arm_anim < 1.0:
		_arm_anim = minf(_arm_anim + delta * 3.0, 1.0)
	# Cocked back (0.6 rad) at rest; the shot snaps it up-forward, then it
	# winds back over ~0.3 s.
	var snap: float = 1.0 - _arm_anim
	_arm.rotation.x = 0.6 - snap * 1.5
