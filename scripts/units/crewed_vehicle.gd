class_name CrewedVehicle extends Unit

## Shared base of all crewed VEHICLES (catapult, fire ram, airship): a device,
## not a believer.
##
## - Ownership follows the crew: whoever boards an UNMANNED vehicle takes it
##   over (convert_to_tribe). Crew members walk on side slots.
## - No own hit points and never targetable: attackers, spells and fire go
##   for the CREW instead.
## - Movement needs >= min_move_crew boarded members.
## - Destruction paths shared by the ground vehicles: fire spells/lava ignite
##   it (burns, then the wreck sinks), the tornado bursts it into wood, water
##   drowns it, terrain rips under the chassis burst it apart. The airship
##   overrides these with its own explosion.
##
## GDScript cannot override parent constants, so everything that DIFFERS per
## vehicle is an instance var assigned in each subclass _init(); everything
## shared stays a const here.
## Boarded members straying farther than this (self-defence chases) are lost.
const CREW_LEASH: float = Balance.SIEGE_CREW_LEASH
## Burn time after a fire-spell/lava hit, then the wreck sinks.
const VEHICLE_BURN_TIME: float = Balance.SIEGE_VEHICLE_BURN_TIME
const SINK_SPEED: float = 0.8   # m/s downward while the wreck sinks
## Height span under the chassis that bursts it. Deliberately ABOVE what
## drivable terrain can present — only real terrain rips trigger.
const BREAK_HEIGHT_SPAN: float = 3.5
## Seconds an abandoned (crewless) siege engine survives before it bursts.
const UNCREWED_LIFETIME: float = 180.0
## Auto-recrew (per-tribe toggle): a short-crewed / neutral GROUND vehicle pulls
## nearby military units in to man it. Coarse-grained scan (user spec: 1-2 s) over
## a small radius — cheap because vehicles are few (see _tick_auto_recrew).
const RECREW_SCAN_INTERVAL: float = 1.0
const RECREW_SCAN_RADIUS: float = 3.0
const C_WOOD: Color = Color(0.42, 0.29, 0.15)
const C_WOOD_DARK: Color = Color(0.3, 0.2, 0.1)
const C_METAL: Color = Color(0.45, 0.45, 0.48)

## Per-vehicle knobs (constants cannot be overridden — see class doc).
## A crew member counts as boarded/serving within this range of the vehicle
## (the airship: flat distance to its ground shadow).
var board_range: float = Balance.SIEGE_BOARD_RANGE
var max_crew: int = Balance.SIEGE_MAX_CREW
var min_move_crew: int = Balance.SIEGE_MIN_MOVE_CREW
var min_fire_crew: int = Balance.SIEGE_MIN_FIRE_CREW
## Crew slot layout: 2 columns along the sides, this far out/apart.
var crew_side_offset: float = 0.95
var crew_rank_spacing: float = 0.85
var vehicle_ring_scale: float = 4.5
## Chassis sample half-extents (along facing x sideways).
var chassis_half_length: float = 1.1
var chassis_half_width: float = 0.7

## Crew members (untyped entries: may be freed). Includes recruits still
## walking over (not yet boarded).
var crew: Array = []

var _crew_prune_timer: float = 0.0
## Throttle for the auto-recrew scan (staggered per instance in _tick_auto_recrew).
var _recrew_timer: float = 0.0
## Seconds this vehicle has stood continuously without any crew (recruits still
## walking over count as crew). At UNCREWED_LIFETIME an abandoned siege engine
## bursts. Reset the moment anyone is aboard or inbound.
var _no_crew_time: float = 0.0
## Seconds of burn left after a fire-spell/lava hit (0 = not burning).
var _vehicle_burn: float = 0.0
## The destroyed wreck sinks into the ground (burn/water death).
var _sinking: bool = false
## Vehicle-grid cells this vehicle currently blocks while parked unmanned (so
## other vehicles path around it). Empty while manned/moving/destroyed.
var _nav_blocked_cells: Array[Vector2i] = []
## Position the current nav block was registered at (re-parked when displaced).
var _nav_block_anchor: Vector3 = Vector3.INF
## Death sound key, set at the destruction site: "siege_death_burn" when the
## wreck burns down/sinks, "siege_death_burst" when it bursts apart (tornado /
## terrain rip). Catapult and fire ram share these (both are CrewedVehicles).
var _death_sfx: StringName = &"siege_death_burst"
## While true the tornado has captured the vehicle and drives its full position
## every tick (rides along + rises); the vehicle skips its own tick meanwhile.
var _tornado_captured: bool = false
## Own 3D model parts (in-game only, built in _ready).
var _model: Node3D = null
var _flag_mesh: MeshInstance3D = null


func _init() -> void:
	max_health = 1
	health = 1
	push_immune = true       # pedestrians do not shove the vehicle around
	counts_population = false  # a device, not a believer (no mana, no housing)
	joins_idle_groups = false  # vehicles never dock onto idle 6-packs


func _is_combatant() -> bool:
	return true


func _is_ranged() -> bool:
	return true   # never takes melee slots; order_attack skips redistribution


func is_targetable() -> bool:
	return false  # attackers go for the crew


## Vehicles never play the man-sized death cry — they have their own burn/burst
## cues (set at the destruction site).
func death_sfx_key() -> StringName:
	return _death_sfx


func renders_as_sprite() -> bool:
	return false  # own 3D model instead of the sprite MultiMesh


## Wide formation spread so several vehicles sent to one point get targets
## outside each other's (large) separation bubble — otherwise they shove each
## other around at the goal (their bubble ~3 m dwarfs the ~0.55 m member
## offsets). The airship keeps its own smaller scale.
func formation_scale() -> float:
	return Balance.VEHICLE_FORMATION_SCALE


func is_conversion_immune() -> bool:
	return true   # a device, not a believer


func is_panic_immune() -> bool:
	return true


func can_crew_siege() -> bool:
	return false


## Which units may crew this vehicle. The airship overrides this (it also
## takes the shaman); order_crew consults the VEHICLE, not the unit.
func accepts_crew_unit(unit) -> bool:
	return unit.can_crew_siege()


## Deck vehicles (airship) pin boarded crew to their slot at altitude instead
## of letting them glide on the ground.
func crew_rides_on_deck() -> bool:
	return false


## Fire-ram rule: the crew ignores ranged harassment and only defends against
## direct melee (checked by Unit._maybe_retaliate).
func crew_defends_melee_only() -> bool:
	return false


## Big ring enclosing the vehicle and its side crew (selecting a crew member
## selects the whole vehicle — the ring mirrors that).
func selection_ring_scale() -> float:
	return vehicle_ring_scale


## The whole hull is clickable, not just a sprite-sized sliver (the ground
## vehicles' 3D models are ~2 m tall and ~2 m long).
func pick_size_m() -> Vector2:
	return Vector2(2.6, 2.2)


## The device takes no damage — attacks hit the crew. Only its specific
## destruction paths (fire, tornado, water, terrain rip) kill it.
func take_damage(_amount: int, _attacker = null) -> void:
	pass


## Too heavy for tornado throws, fireball knockback and rolls.
func throw_airborne(_velocity: Vector3, _fall_damage: int = 0) -> void:
	pass


func start_roll(_dir: Vector3, _duration: float = MINI_ROLL_DURATION,
		_initial_speed: float = 0.0, _stumble: bool = false) -> void:
	pass


func displace(_dir: Vector3, _dist: float) -> void:
	pass


## Fire spells and lava DO destroy the device: it catches fire, burns for a
## moment and then sinks into the ground. The crew is released alive at the
## wreck (it takes the area damage on its own).
func ignite(_source_pos: Vector3, _source = null) -> void:
	if state == State.DEAD or _vehicle_burn > 0.0:
		return
	_vehicle_burn = VEHICLE_BURN_TIME
	_play_sfx(&"siege_burning")


## Flame contact (fire ram): the wooden vehicle catches fire properly — same
## as a fire-spell hit (units get the no-contact-damage burn instead).
func scorch(source_pos: Vector3, source = null) -> void:
	ignite(source_pos, source)


func is_burning() -> bool:
	return _vehicle_burn > 0.0


## Vehicles burn with a bigger flame than the man-sized default.
func burn_fx_scale() -> float:
	return 2.0


func burn_fx_height() -> float:
	return 1.4


## The tornado has caught the vehicle: from now the vortex drives its full
## position each tick (rides along the funnel and rises) and the vehicle skips
## its own tick, so nothing yanks it back to the ground.
func tornado_capture() -> void:
	_tornado_captured = true


## The tornado tore the vehicle apart: it releases its crew and is destroyed
## leaving NOTHING itself — the vortex spawns the wood chunks that scatter
## like any whirled-up wood.
func burst_into_wood() -> void:
	if state == State.DEAD:
		return
	_tornado_captured = false
	for m in crew.duplicate():
		if is_instance_valid(m):
			m.leave_crew()
	crew.clear()
	_unblock_nav()
	attack_building = null
	_vehicle_burn = 0.0
	_death_sfx = &"siege_death_burst"   # torn apart by the tornado
	if _model != null:
		_model.visible = false
	# Visibly burst apart at the tornado tip (was silently hiding the model —
	# user report: lifted vehicles never "burst", no effect). Same debris burst
	# as the terrain-rip death; the tornado additionally scatters its wood chunks.
	_spawn_burst_debris()
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
	_unblock_nav()
	_sinking = true
	_death_sfx = &"siege_death_burn"   # sinks like a burnt-out wreck
	super.drown()


# --- Vehicle destruction --------------------------------------------------------

## Whether this vehicle self-destructs after UNCREWED_LIFETIME without crew.
## True for ground siege engines (catapult, fire ram); the airship overrides it
## to false so empty ships keep drifting home instead of bursting.
func destroys_when_uncrewed() -> bool:
	return true


## Burn-out and water: the wreck sinks. Terrain rip: it bursts apart
## (debris). Either way the crew survives, is released and controllable.
func _destroy_vehicle(burst: bool) -> void:
	if state == State.DEAD:
		return
	for m in crew.duplicate():
		if is_instance_valid(m):
			m.leave_crew()
	crew.clear()
	_unblock_nav()
	attack_building = null
	_vehicle_burn = 0.0
	_death_sfx = &"siege_death_burst" if burst else &"siege_death_burn"
	if burst:
		if _model != null:
			_model.visible = false
		_spawn_burst_debris()
	else:
		_sinking = true
	health = 0
	_die()


## Debris burst effect at the current position (a vehicle bursting apart). Shared
## by the terrain-rip death and the tornado-tip burst.
func _spawn_burst_debris() -> void:
	if path_service == null:
		return
	var debris: BuildingDebris = BuildingDebris.new()
	debris.setup(position, 1.5, terrain_data)
	path_service.register_projectile(debris)


## Grid cells the parked-vehicle nav obstacle covers: a DISC of the vehicle's
## separation radius around its centre — NOT just the chassis. Vehicle paths
## must keep waypoints outside the separation bubble (another vehicle's centre
## can physically never come closer than ITS vehicle_separation to ours): the
## old chassis-only 3x3 block let A* route ~1.5 m past a parked hulk, which the
## separation then fought off every tick — the mover wrestled at the hulk for
## a long time instead of driving around (user report: catapult stuck at the
## parked fire ram in the start base).
func _obstacle_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if nav_grid == null:
		return cells
	var r: float = vehicle_separation + 0.2   # + margin: routes graze the rim
	var cr: int = int(ceil(r))
	var center: Vector2i = nav_grid.world_to_cell(position)
	var r2: float = r * r
	for dz in range(-cr, cr + 1):
		for dx in range(-cr, cr + 1):
			var c: Vector2i = center + Vector2i(dx, dz)
			var wc: Vector3 = nav_grid.cell_to_world(c)
			var ddx: float = wc.x - position.x
			var ddz: float = wc.z - position.z
			if ddx * ddx + ddz * ddz <= r2:
				cells.append(c)
	return cells


## Parks/unparks this vehicle as a nav obstacle: a stationary UNMANNED vehicle
## blocks its separation disc on the vehicle grid so other vehicles route
## around it (user report: vehicles shove past parked hulks forever). Cleared
## the moment it is crewed or destroyed. Cheap: toggles on a state change; the
## anchor check re-parks the block only if something displaced the hulk
## (terrain morph, scripted throw) by more than a cell.
func _refresh_nav_block() -> void:
	if nav_grid == null or crew_rides_on_deck() or flies:
		return   # airships fly over ground vehicles — they never block the grid
	var want: bool = state != State.DEAD and not _sinking and boarded_count() == 0
	var blocked: bool = not _nav_blocked_cells.is_empty()
	if want and blocked \
			and position.distance_squared_to(_nav_block_anchor) < 2.25:
		return   # already parked here
	if not want and not blocked:
		return
	_unblock_nav()
	if want:
		_nav_blocked_cells = _obstacle_cells()
		nav_grid.set_vehicle_obstacle(_nav_blocked_cells, true)
		_nav_block_anchor = position


func _unblock_nav() -> void:
	if nav_grid != null and not _nav_blocked_cells.is_empty():
		nav_grid.set_vehicle_obstacle(_nav_blocked_cells, false)
	_nav_blocked_cells = []


## Height span under the chassis (4 corner samples along the facing).
func _chassis_height_span() -> float:
	if terrain_data == null:
		return 0.0
	var forward: Vector3 = facing.normalized() if facing.length_squared() > 0.0 \
		else Vector3(0, 0, 1)
	var right: Vector3 = Vector3(-forward.z, 0.0, forward.x)
	var lo: float = INF
	var hi: float = -INF
	for sf in [-chassis_half_length, chassis_half_length]:
		for sr in [-chassis_half_width, chassis_half_width]:
			var p: Vector3 = position + forward * sf + right * sr
			var h: float = terrain_data.get_height(p.x, p.z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo


# --- Crew management --------------------------------------------------------------

## Registers a unit as (incoming) crew. Refused when full or when a foreign
## unit tries to join a MANNED enemy vehicle; an unmanned vehicle accepts any
## tribe (the takeover completes when the recruit boards).
func add_crew(unit) -> bool:
	_prune_crew()
	if unit in crew:
		return true
	if crew.size() >= max_crew:
		return false
	if unit.tribe_id != tribe_id and boarded_count() > 0:
		return false   # manned vehicles cannot be hijacked while served
	crew.append(unit)
	return true


func remove_crew(unit) -> void:
	crew.erase(unit)


## Crew members currently serving the vehicle (boarded and within the leash).
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


## Boarded members currently ABLE to serve: pacified (SIT under a preacher),
## panicking/burning and tumbling members still count as boarded (ownership,
## hijack protection) but cannot drive or fire — a vehicle whose whole crew
## is incapacitated does nothing until they recover (user spec).
func active_crew_count() -> int:
	var count: int = 0
	for m in crew:
		if is_instance_valid(m) and m.state != State.DEAD and m.siege_boarded \
				and _flat_dist(m.position, position) <= CREW_LEASH \
				and (m.state == State.CREW or m.can_take_orders()):
			count += 1
	return count


## A recruit reached the vehicle: it boards. First boarder of another tribe
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
	unit._sync_soa_flags()   # seated: excluded from the separation kernel
	_unblock_nav()   # now manned — stop being a nav obstacle for other vehicles


## Ownership follows the crew (spec: vehicles can change hands when the crew
## dies/flees and a new one takes over).
func _switch_owner(new_tribe: Tribe) -> void:
	if new_tribe == null or new_tribe == tribe:
		return
	attack_building = null
	convert_to_tribe(new_tribe)
	# A taken-over vehicle starts fresh: never resume the previous owner's move
	# route or target (user report: a hijacked/recrewed vehicle drove off with no
	# order). convert_to_tribe ends the attack + goes IDLE, but the pending route
	# survives it — clear it here.
	waypoint_queue.clear()
	_clear_path()
	_set_state(State.IDLE)
	_refresh_flag_color()


## Side slot for a crew member: 2 columns along the sides, moving with the
## vehicle. The slot index is the member's position in the crew list (stable
## enough — the list only compacts when members leave).
func crew_slot_position(unit) -> Vector3:
	var index: int = maxi(crew.find(unit), 0)
	var side: float = -1.0 if index % 2 == 0 else 1.0
	var rank: float = float(index / 2) - 1.0
	# Anchor the slots to the VISIBLE hull heading (_model_heading), not the raw
	# `facing`. The fire ram slews its hull toward the target at a real turn rate
	# while `facing` snaps instantly — computing slots from `facing` swung the
	# crew through the hull and back whenever the aim jumped. The base and the
	# catapult return `facing` here, so their behaviour is unchanged.
	var heading: Vector3 = _model_heading()
	var forward: Vector3 = heading.normalized() if heading.length_squared() > 0.0 \
		else Vector3(0, 0, 1)
	var right: Vector3 = Vector3(-forward.z, 0.0, forward.x)
	var slot: Vector3 = position + right * side * crew_side_offset \
		+ forward * rank * crew_rank_spacing
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
			dropped.append(m)   # converted away / vehicle changed hands
			continue
		# NOTE: foreign members that have NOT boarded yet are legitimate
		# takeover recruits walking over (an unmanned vehicle accepts any
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

## Moving needs at least min_move_crew ACTIVE crew members (pacified or
## panicking crew cannot drive).
func order_move(target: Vector3, queue_up: bool = false, aggressive: bool = false) -> void:
	if active_crew_count() < min_move_crew:
		return
	attack_building = null
	super.order_move(target, queue_up, aggressive)


## Explicit bombard/burn order on a building (right-click, AI): replaces any
## pending route. Enemy buildings always; the OWN building only while enemy
## raiders demolish it from the inside (anti-raider bombardment, phase 7f).
func order_attack_building(building) -> void:
	if building == null or not is_instance_valid(building) or building.health <= 0:
		return
	if building.tribe_id == tribe_id and not building.has_raiders():
		return
	_set_building_target(building, false)


## Building focus stays valid for a live enemy building — or the OWN building
## while enemy raiders are still demolishing it (once they are gone or thrown
## out for good, the focus is dropped).
func _building_target_valid() -> bool:
	if attack_building == null or not is_instance_valid(attack_building) \
			or attack_building.health <= 0:
		return false
	if attack_building.tribe_id != tribe_id:
		return true
	return attack_building.has_raiders()


## Focuses a building for the vehicle weapon. `keep_route` preserves the
## pending (attack-)move waypoint so the vehicle carries on to its destination
## after the building falls; explicit orders clear it.
func _set_building_target(building, keep_route: bool) -> void:
	_end_attack()
	if not keep_route:
		waypoint_queue.clear()
	_clear_path()
	attack_building = building
	_set_state(State.ATTACK)


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


## Vehicle body: paths on the eroded vehicle grid (narrow gaps are closed).
## `_allow_partial` is ignored — vehicle paths stay all-or-nothing.
func _plan_path_to(target: Vector3, _allow_partial: bool = false) -> bool:
	if nav_grid != null:
		var path: PackedVector3Array = nav_grid.find_vehicle_path(position, target)
		if path.is_empty():
			return false
		# Drop the redundant own-cell first waypoint (see Unit._trim_own_cell_waypoint):
		# without it a combat approach against a moving target darts to the current
		# cell centre on every re-plan and the vehicle jitters instead of pursuing.
		_path = _trim_own_cell_waypoint(path)
		_path_index = 0
		return true
	return super._plan_path_to(target)


## MOVE orders plan SYNCHRONOUSLY on the vehicle grid, bypassing the async
## PathWorker. The worker is seeded with the PEDESTRIAN solidity snapshot
## (NavGrid.solid_snapshot) and knows nothing about the eroded vehicle grid — so
## routing a MOVE through it hands the vehicle a pedestrian route onto a narrow
## ridge that its own combat approach (_approach -> find_vehicle_path) then
## refuses to hold. That grid mismatch made the fire ram judder forward/back on
## hills, never reaching firing range. Vehicles are few, so a per-order sync A*
## is cheap (the airship overrides this the same way). Unreachable target ->
## drop the whole route and stop, exactly like Unit._start_path_to's sync branch.
func _start_path_to(target: Vector3) -> void:
	if not _plan_path_to(target, move_aggressive):
		waypoint_queue.clear()
		_set_state(State.IDLE)
		return
	_set_state(State.MOVE)


func tick(delta: float) -> void:
	# Captured by a tornado: the vortex fully drives the position (rides along +
	# rises) and ends it with a burst/mid-air explosion, so the vehicle has no
	# world tick of its own — like stationed tower crew (see Unit.tick).
	if _tornado_captured:
		return
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
		# Abandoned: no crew (and none inbound, crew already pruned above) for
		# UNCREWED_LIFETIME seconds -> the siege engine bursts. Airships opt out
		# (empty ones drift home instead, see destroys_when_uncrewed).
		elif state != State.DEAD and destroys_when_uncrewed():
			if crew.is_empty():
				_no_crew_time += 0.5
				if _no_crew_time >= UNCREWED_LIFETIME:
					_destroy_vehicle(true)
			else:
				_no_crew_time = 0.0
	# Truly unmanned (nobody aboard — not merely incapacitated): drop EVERY
	# pending order so a later takeover / auto-recrew starts idle and never drives
	# off on the previous owner's route or target (user report). Gated on
	# boarded_count (not active), so a boarded-but-pacified/panicking crew keeps
	# its target to resume on recovery.
	if state != State.DEAD and not _sinking and boarded_count() == 0:
		if state == State.MOVE or state == State.ATTACK or _has_path() \
				or not waypoint_queue.is_empty() or attack_building != null:
			waypoint_queue.clear()
			_clear_path()
			attack_building = null
			_end_attack()
			if state != State.IDLE:
				_set_state(State.IDLE)
	# An under-crewed / incapacitated-crew (but still boarded) vehicle rolls to a
	# stop mid-route; it keeps its target and resumes once the crew recovers.
	elif state == State.MOVE and active_crew_count() < min_move_crew:
		waypoint_queue.clear()
		_clear_path()
		_set_state(State.IDLE)
	_refresh_nav_block()   # park/unpark as a nav obstacle for other vehicles
	_tick_auto_recrew(delta)
	super.tick(delta)
	_tick_visual(delta)


## Auto-recrew (per-tribe toggle auto_recrew_vehicles, default on — covers the AI
## too): a short-crewed or neutral GROUND vehicle pulls nearby MILITARY units in to
## man it. Vehicle-driven (few vehicles scan a small radius) instead of unit-driven
## (many units scanning) — geometrically identical for a small radius but far
## cheaper. Airships opt out (they ride on deck and have their own AI manning).
## Skips entirely once full, so only under-crewed vehicles ever scan.
func _tick_auto_recrew(delta: float) -> void:
	if crew_rides_on_deck():
		return   # airships (zeppelins) are excluded — user spec
	if state == State.DEAD or _vehicle_burn > 0.0 or _sinking:
		return
	if path_service == null or crew_count() >= max_crew:
		return
	_recrew_timer -= delta
	if _recrew_timer > 0.0:
		return
	# Coarse throttle with a per-instance jitter so many vehicles don't scan the
	# same frame (mirrors Unit._due_to_scan).
	_recrew_timer = RECREW_SCAN_INTERVAL + float(get_instance_id() % 50) * 0.01
	for u in path_service.get_units_in_radius(position, RECREW_SCAN_RADIUS):
		var members: int = crew_count()   # prunes once; also gates the takeover below
		if members >= max_crew:
			break
		if not is_instance_valid(u) or u.state == State.DEAD:
			continue
		# Military only: _is_combatant() excludes braves AND the shaman; the
		# vehicle's accepts_crew_unit rejects the shaman/chassis as well.
		if not u._is_combatant() or not accepts_crew_unit(u):
			continue
		if u.siege_engine != null:
			continue   # already crew / walking to a vehicle — crews never search
		if u._in_melee:
			continue   # engaged in melee — must not be pulled off
		if u.state != State.IDLE and u.state != State.ATTACK:
			continue   # idle or (ranged) combat only; explicit MOVE orders stand
		if not u.can_take_orders():
			continue
		if u.tribe == null or not u.tribe.auto_recrew_vehicles:
			continue   # the CANDIDATE's tribe governs (own backfill + neutral takeover)
		# Own vehicles are backfilled at any crew level; a FOREIGN unit only claims a
		# genuinely abandoned vehicle (no boarded OR inbound crew) — it never snipes
		# one the owner is actively manning (recruits still walking over count).
		if u.tribe_id != tribe_id and members > 0:
			continue
		u.order_crew(self)   # add_crew/on_crew_boarded enforce the hijack rules


# --- Visuals (own 3D model, in-game only) -------------------------------------------

func _ready() -> void:
	_create_model()
	_refresh_flag_color()


## Builds the vehicle's 3D model; each subclass provides its own.
func _create_model() -> void:
	pass


## Heading the model rotates to each visual tick; the fire ram overrides this
## with its slewed heading (real turn rate).
func _model_heading() -> Vector3:
	return facing


## Blinks a temporary gold ring twice — feedback for a crew order. The unit
## selection rings are drawn centrally (MultiMesh, selected units only), so
## the vehicle spawns its own short-lived ring mesh.
func flash_ring() -> void:
	if not is_inside_tree():
		return
	var ring: MeshInstance3D = MeshInstance3D.new()
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.26 * selection_ring_scale()
	torus.outer_radius = 0.34 * selection_ring_scale()
	ring.mesh = torus
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.95, 0.3)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	ring.position.y = 0.1
	add_child(ring)
	var tween: Tween = create_tween()
	for i in range(2):
		tween.tween_callback(func() -> void: ring.visible = true)
		tween.tween_interval(0.16)
		tween.tween_callback(func() -> void: ring.visible = false)
		tween.tween_interval(0.12)
	tween.tween_callback(ring.queue_free)


## Phase 8 shadow rework: units cast no real shadows — the model gets a
## hardcoded blob quad instead (like the sprite units' blob MultiMesh).
func _finish_model(root: Node3D) -> void:
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


## Rotates the model with the heading and sinks the destroyed wreck into the
## ground (the burn flame is the shared StatusFxRenderer billboard).
func _tick_visual(delta: float) -> void:
	if not is_inside_tree():
		return
	if _sinking and state == State.DEAD:
		position.y -= SINK_SPEED * delta
	var heading: Vector3 = _model_heading()
	if heading.length_squared() > 0.000001:
		rotation.y = atan2(heading.x, heading.z)
