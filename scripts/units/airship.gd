class_name Airship extends CrewedVehicle

## Luftschiff: a flying crewed vehicle built by the airship wharf.
##
## - Cruises AIRSHIP_FLY_HEIGHT above "normal ground" (soft altitude model,
##   see _snap_to_ground: high terrain is followed at MIN_CLEARANCE instead)
##   and flies in a STRAIGHT line — nothing blocks the air, so there is
##   no A* and no path queue; water is no obstacle.
## - Up to 6 passengers of ANY kind including the shaman (accepts_crew_unit);
##   they ride VISIBLY on deck slots (crew_rides_on_deck) and stay normal,
##   individually targetable units — but only RANGED attacks can touch them
##   (Unit.is_airborne rules). Boarding: stand within board_range (1.5 m) of
##   the ground shadow. Empty airships are boardable by any tribe (takeover).
## - Crew combat ONLY WHILE STANDING: firewarriors fire and preachers convert
##   from the deck with +AIRSHIP_RANGE_BONUS reach (watchtower pattern); the
##   shaman casts from deck with the same bonus (Shaman.order_cast). Buildings
##   can only be attacked by firewarriors (no melee from the air). On an
##   explicit attack order only crew that CAN act on the target does — a
##   warrior-only airship never has anything to attack.
## - Hull: fireball-spell bolts and catapult air-intercepts each count one
##   hull hit; AIRSHIP_HULL_HITS destroy it. Lightning and tornado call
##   explode() directly. Fire/lava cannot ignite it (it flies), water cannot
##   drown it, terrain rips cannot reach it.
## - explode(): every passenger takes AIRSHIP_CRASH_DAMAGE, is hurled off the
##   deck and falls ~12 m (the throw path applies the crash damage again as
##   fall damage; water landing drowns). The hull bursts into debris.
## - Empty airships DRIFT slowly toward terrain reachable from the start
##   bases (nearest reincarnation site's island) so they never strand.

const MAX_CREW: int = Balance.AIRSHIP_MAX_CREW
const MIN_MOVE_CREW: int = Balance.AIRSHIP_MIN_MOVE_CREW
const FLY_HEIGHT: float = Balance.AIRSHIP_FLY_HEIGHT
const MIN_CLEARANCE: float = Balance.AIRSHIP_MIN_CLEARANCE
const CRUISE_TERRAIN_CAP: float = Balance.AIRSHIP_CRUISE_TERRAIN_CAP
const VERTICAL_RATE: float = Balance.AIRSHIP_VERTICAL_RATE
const RANGE_BONUS: float = Balance.AIRSHIP_RANGE_BONUS
const HULL_HITS: int = Balance.AIRSHIP_HULL_HITS
const CRASH_DAMAGE: int = Balance.AIRSHIP_CRASH_DAMAGE
const DRIFT_SPEED: float = Balance.AIRSHIP_DRIFT_SPEED
const UNLOAD_RANGE: float = Balance.AIRSHIP_UNLOAD_RANGE
## Deck height of the passenger slots above the hull origin.
const DECK_Y: float = 0.6
## Throttles (seconds): drift condition check, drift anchor re-pick.
const DRIFT_CHECK_INTERVAL: float = 1.0
const ANCHOR_REPICK_INTERVAL: float = 5.0
## Deck-combat target acquisition throttle: the per-crew enemy/building scans
## ran every frame (the only ungated per-frame combat scan). Re-acquired ~5x/s
## instead; fire/convert cadence is unaffected (cooldowns advance with the
## accumulated elapsed time passed to the crew handlers).
const DECK_SCAN_INTERVAL: float = 0.2

## Hull hits taken (fireball-spell bolts + catapult air-intercepts).
var _hull_hits: int = 0
## Fire cooldown per firewarrior passenger (watchtower pattern — deck crew
## has no own combat tick; preachers channel via begin_conversion/SIT).
var _fire_cd: Dictionary = {}
## Explicitly ordered targets (sticky, like _target_ordered elsewhere).
var _ordered_unit: Unit = null
## Drift state: throttle + current anchor (a reincarnation site, any tribe).
var _drift_check: float = 0.0
var _anchor_repick: float = 0.0
var _drift_anchor = null
## Auto-engage steering (user spec): with firewarriors aboard, an IDLE or
## attack-moving airship closes to deck fire reach of enemies/buildings
## within the deck-boosted firewarrior aggro radius and stands to fight; an
## interrupted attack-move resumes its route once nothing is left.
var _engage_scan: float = 0.0
## Deck-combat scan throttle + elapsed accumulator (see DECK_SCAN_INTERVAL):
## the crew handlers get the summed delta so fire/convert cooldowns stay exact.
var _deck_scan: float = 0.0
var _deck_elapsed: float = 0.0
## Building the deck firewarriors free-fire at (units always take priority).
var _auto_building = null
## True while flying an AUTO approach (not a player route): arriving stands
## to fight instead of popping the kept waypoint queue.
var _auto_approach: bool = false
## True after the first hull hit: the hull burns, drawn as the shared 2D flame
## billboard (StatusFxRenderer) high above the balloon; cleared on explode.
var _hull_on_fire: bool = false


func _init() -> void:
	super()
	speed = Balance.AIRSHIP_SPEED
	board_range = Balance.AIRSHIP_BOARD_RANGE
	max_crew = MAX_CREW
	min_move_crew = MIN_MOVE_CREW
	min_fire_crew = MIN_MOVE_CREW
	# A SMALL collision footprint so airships cannot fully overlap, but they
	# only separate against OTHER airships (never the ground units/vehicles they
	# fly over) and shove clear of each other fast (flies + speed mult).
	vehicle_separation = Balance.AIRSHIP_SEPARATION
	flies = true
	separation_speed_mult = Balance.AIRSHIP_SEPARATION_SPEED_MULT
	vehicle_ring_scale = 5.0
	# Passengers stand well inside the 1.6 m wide gondola deck.
	crew_side_offset = 0.55


func unit_kind() -> StringName:
	return &"airship"


## Own crash sound (a single cue — hull fire vs. tornado are indistinguishable
## at the airship's parameterless explode()).
func death_sfx_key() -> StringName:
	return &"airship_death"


## Anyone may board — including the shaman; only vehicles never crew.
func accepts_crew_unit(unit) -> bool:
	return not (unit is CrewedVehicle)


func crew_rides_on_deck() -> bool:
	return true


## The whole balloon + gondola is clickable (user feedback: the default
## sprite-sized pick rect made the high-hovering ship fiddly to select). The
## screen rect is actually built from pick_world_points() below (deck corners),
## so it follows the deck's rotation; this stays as a floor size.
func pick_size_m() -> Vector2:
	return Vector2(6.0, 3.5)


## Deck-corner (and balloon) world points so the pick rect frames the actual
## rotating platform — clicks on the deck CORNERS select / target the ship at
## any heading (user request). Deck is 1.6 m wide x 3.6 m long at DECK_Y.
func pick_world_points() -> PackedVector3Array:
	var forward: Vector3 = facing.normalized() if facing.length_squared() > 0.000001 \
		else Vector3(0, 0, 1)
	var right: Vector3 = Vector3(-forward.z, 0.0, forward.x)
	var half_w: float = 1.1   # a touch beyond the 1.6 m deck for easy corner hits
	var half_l: float = 2.1   # a touch beyond the 3.6 m deck
	var deck: Vector3 = position + Vector3(0.0, DECK_Y, 0.0)
	var pts: PackedVector3Array = PackedVector3Array()
	for sl in [-half_l, half_l]:
		for sw in [-half_w, half_w]:
			pts.append(deck + forward * sl + right * sw)
	# Balloon top so the whole silhouette (not just the deck) stays clickable.
	pts.append(position + Vector3(0.0, 4.3, 0.0))
	return pts


## An elongated ring framing the rectangular deck, aligned to the heading
## (base torus radius 0.34: x ~1.1 m half-width, z ~2.0 m half-length).
func selection_ring_extents() -> Vector2:
	return Vector2(3.3, 6.0)


func selection_ring_oriented() -> bool:
	return true


## The airship itself never attacks — its CREW does (deck combat tick), so
## the base auto-aggro state machine stays off.
func _is_combatant() -> bool:
	return false


func _may_target_vehicle(_enemy: Unit) -> bool:
	return false


# --- Immunities beyond the base vehicle ---------------------------------------------

## Fire and lava cannot reach the airborne hull — fire spells damage it via
## register_hull_hit (FireballBolt special-cases the airship) instead.
func ignite(_source_pos: Vector3, _source = null) -> void:
	pass


## A damaged hull burns until it explodes — shown as the shared 2D flame
## billboard (StatusFxRenderer), sized big and placed high above the balloon so
## it reads clearly against the sky (not a 3D blob inside the balloon mesh).
func is_burning() -> bool:
	return _hull_on_fire


func burn_fx_scale() -> float:
	return 3.0


func burn_fx_height() -> float:
	return 4.7


## Water below is irrelevant to a flying hull.
func drown() -> void:
	pass


## Terrain rips cannot reach the hull (disables the base tick's burst check).
func _chassis_height_span() -> float:
	return 0.0


## Tornado contact: the airship explodes (no wood-burst limbo state).
func burst_into_wood() -> void:
	explode()


# --- Flight (straight line, no A*) ---------------------------------------------------

## Base movement hook (called without delta after every horizontal step):
## only enforces the hard MIN_CLEARANCE floor — never clip into rising
## ground. The smooth climb/sink toward the cruise altitude runs once per
## tick in _tick_altitude.
func _snap_to_ground() -> void:
	if terrain_data != null:
		position.y = maxf(position.y,
			maxf(terrain_data.get_height(position.x, position.z),
				TerrainData.SEA_LEVEL) + MIN_CLEARANCE)


## Soft altitude model (user spec): cruise at FLY_HEIGHT above "normal
## ground" — terrain counts toward the cruise target only up to the map's
## average height + CRUISE_TERRAIN_CAP, so over high mountains the ship just
## follows the terrain at MIN_CLEARANCE instead of towering FLY_HEIGHT above
## the peaks. Climbs/sinks smoothly at VERTICAL_RATE; the MIN_CLEARANCE
## floor is enforced instantly (never clip into rising ground). Nice side
## effect: a freshly built ship visibly ascends from the wharf gate.
func _tick_altitude(delta: float) -> void:
	if terrain_data == null:
		return
	var ground: float = maxf(terrain_data.get_height(position.x, position.z),
		TerrainData.SEA_LEVEL)
	var ref: float = minf(ground,
		terrain_data.average_height() + CRUISE_TERRAIN_CAP)
	var target_y: float = maxf(ref + FLY_HEIGHT, ground + MIN_CLEARANCE)
	position.y = maxf(move_toward(position.y, target_y, VERTICAL_RATE * delta),
		ground + MIN_CLEARANCE)


## No slope in the air (also disables the downhill-stumble roll).
func _slope_ahead(_move_dir: Vector2) -> float:
	return 0.0


## A ship counts as arrived once within ~one separation radius of its target,
## so a second ship ordered to (near) the same point stops and goes IDLE at the
## edge of the first ship's collision bubble instead of endlessly circling to
## reach the unreachable exact spot (the separation push exceeds the fly speed
## inside the bubble). Parked (IDLE) ships never re-path, so they accept being
## nudged and do not reclaim their old spot.
func arrive_eps() -> float:
	return maxf(super.arrive_eps(), vehicle_separation)


## Airships keep their own (smaller) formation spread — their separation bubble
## (~2 m) is tighter than the ground vehicles' (~3 m), so the ground-vehicle
## scale would spread flights wider than needed.
func formation_scale() -> float:
	return Balance.AIRSHIP_FORMATION_SCALE


## Straight flight: bypasses the async path queue entirely (the PathWorker
## computes ground-grid paths) and never fails — only map bounds clamp.
func _start_path_to(target: Vector3) -> void:
	_auto_approach = false   # a real route replaces any auto approach
	_plan_path_to(target)
	_set_state(State.MOVE)


## An AUTO approach that reaches its stop point stands to fight — the kept
## waypoint queue (attack-move target) must NOT be popped; the route resumes
## via the engage scan once nothing is left to shoot.
func _on_path_finished() -> void:
	if _auto_approach:
		_auto_approach = false
		_set_state(State.IDLE)
		return
	super._on_path_finished()


func _plan_path_to(target: Vector3, _allow_partial: bool = false) -> bool:
	var t: Vector3 = target
	if terrain_data != null:
		var limit: float = float(terrain_data.size) * TerrainData.CELL_SIZE - 1.0
		t.x = clampf(t.x, 1.0, limit)
		t.z = clampf(t.z, 1.0, limit)
	_path = PackedVector3Array([t])
	_path_index = 0
	return true


# --- Passenger slots -------------------------------------------------------------------

## Deck slots: 2 columns x 3 ranks on the hull, at deck height (the base
## version would snap the slot to the terrain).
func crew_slot_position(unit) -> Vector3:
	var index: int = maxi(crew.find(unit), 0)
	var side: float = -1.0 if index % 2 == 0 else 1.0
	var rank: float = float(index / 2) - 1.0
	var forward: Vector3 = facing.normalized() if facing.length_squared() > 0.0 \
		else Vector3(0, 0, 1)
	var right: Vector3 = Vector3(-forward.z, 0.0, forward.x)
	return position + right * side * crew_side_offset \
		+ forward * rank * crew_rank_spacing + Vector3(0.0, DECK_Y, 0.0)


## Drops a passenger to the ground near `around` (nearest walkable cell, a
## deterministic ring so a full unload spreads out): the passenger leaves the
## crew at deck height and simply FALLS — water landing drowns, land landing
## is harmless (no fall damage on a controlled drop).
func drop_member(member, around: Vector3 = Vector3.INF) -> void:
	if member == null or not is_instance_valid(member) or member.state == State.DEAD:
		return
	var dest: Vector3 = around if around != Vector3.INF else position
	member.leave_crew()
	if nav_grid != null:
		var idx: int = maxi(crew.size(), 0) + _hull_hits   # cheap spread seed
		var angle: float = float((member.get_instance_id() + idx) % 628) * 0.01
		var probe: Vector3 = dest + Vector3(cos(angle) * 1.5, 0.0, sin(angle) * 1.5)
		var cell: Vector2i = nav_grid.nearest_walkable_cell(nav_grid.world_to_cell(probe))
		if cell.x >= 0:
			var ground: Vector3 = nav_grid.cell_to_world(cell)
			member.position.x = ground.x
			member.position.z = ground.z
	member.position.y = position.y + DECK_Y
	member.throw_airborne(Vector3.ZERO, 0)


## Dead passengers must not leave a corpse floating at 12 m: snap it down.
func remove_crew(unit) -> void:
	super.remove_crew(unit)
	_fire_cd.erase(unit)
	if unit != null and is_instance_valid(unit) and unit.state == State.DEAD \
			and terrain_data != null:
		unit.position.y = terrain_data.get_height(unit.position.x, unit.position.z)


# --- Orders ------------------------------------------------------------------------------

## Explicit attack on an enemy unit: fly into deck reach, then the standing
## crew engages it (only members that CAN act on it do anything).
func order_attack(enemy: Unit) -> void:
	if enemy == null or not is_instance_valid(enemy) or enemy.state == State.DEAD \
			or enemy.tribe_id == tribe_id:
		return
	if active_crew_count() < MIN_MOVE_CREW:
		return
	attack_building = null
	_ordered_unit = enemy
	_fly_into_reach(enemy.position)


## The airship never auto-fights as a Unit: all engagement runs through
## _tick_auto_engage (fly into deck reach + stand) and the deck crew. The base
## idle/attack-move auto-scan would ALSO call _begin_attack (a melee-approach
## driver) and fight _tick_auto_engage for control every tick — that conflict
## made the hull judder on approach (the attack-move stutter). Suppress it here,
## exactly as the fire ram / siege engine replace it with their own acquire.
func _engage_on_sight(_delta: float) -> bool:
	return false


## Explicit attack on a building: only firewarrior passengers can lob at it
## (no melee from the air); own buildings are never a target (the airship has
## no anti-raider shot).
func order_attack_building(building) -> void:
	if building == null or not is_instance_valid(building) or building.health <= 0 \
			or building.tribe_id == tribe_id:
		return
	if active_crew_count() < MIN_MOVE_CREW:
		return
	_ordered_unit = null
	attack_building = building
	_fly_into_reach(building.center_world())


## "Absetzen an ...": fly within UNLOAD_RANGE of the point and drop ALL
## passengers there. Any new order cancels the pending unload (order_move
## clears route_end_action).
func order_unload(point: Vector3) -> void:
	if active_crew_count() < MIN_MOVE_CREW:
		return
	var dest: Vector3 = point
	if nav_grid != null:
		var cell: Vector2i = nav_grid.nearest_walkable_cell(nav_grid.world_to_cell(point))
		if cell.x >= 0:
			dest = nav_grid.cell_to_world(cell)
	order_move(dest)
	route_end_action = func() -> void: _unload_all(dest)


func _unload_all(dest: Vector3) -> void:
	if _flat_dist(position, dest) > UNLOAD_RANGE + 1.0:
		_set_state(State.IDLE)
		return
	for m in crew.duplicate():
		if is_instance_valid(m) and m.siege_boarded:
			drop_member(m, dest)
	_set_state(State.IDLE)


## Flies to standing reach of `point` (deck combat only works standing);
## already in reach = stop and let the crew tick take over.
func _fly_into_reach(point: Vector3) -> void:
	var reach: float = _best_reach()
	if _flat_dist(position, point) > reach:
		var dir: Vector3 = Vector3(point.x - position.x, 0.0, point.z - position.z)
		var dest: Vector3 = point - dir.normalized() * maxf(reach - 1.0, 1.0)
		# order_move wipes the sticky targets (base rule) — keep them across
		# the approach flight.
		var ordered: Unit = _ordered_unit
		var building = attack_building
		order_move(dest)
		_ordered_unit = ordered
		attack_building = building
		return
	waypoint_queue.clear()
	_clear_path()
	_set_state(State.IDLE)


## Longest reach any current passenger can act with (firewarriors out-reach
## preachers); without capable crew the flight still closes to fireball reach.
func _best_reach() -> float:
	for m in crew:
		if is_instance_valid(m) and m.siege_boarded \
				and m.unit_kind() == &"firewarrior":
			return Firewarrior.FIRE_RANGE + RANGE_BONUS
	for m in crew:
		if is_instance_valid(m) and m.siege_boarded \
				and m.unit_kind() == &"preacher":
			return Preacher.CONVERT_RANGE + RANGE_BONUS
	return Firewarrior.FIRE_RANGE + RANGE_BONUS


# --- Hull damage & explosion ------------------------------------------------------------

## One hull hit (fireball-spell bolt or catapult air-intercept). The first
## hit sets the hull visibly on fire; HULL_HITS explode the ship.
func register_hull_hit(_source_pos: Vector3 = Vector3.ZERO) -> void:
	if state == State.DEAD:
		return
	_hull_hits += 1
	if _hull_hits >= HULL_HITS:
		explode()
	else:
		_hull_on_fire = true


## The airship bursts apart: every passenger takes CRASH_DAMAGE, is hurled
## off the deck and falls to the ground (the fall applies CRASH_DAMAGE again
## as fall damage — "counts as a 12 m fall"; water landing drowns). Walking
## recruits are simply released. The hull leaves debris.
func explode() -> void:
	if state == State.DEAD:
		return
	for m in crew.duplicate():
		if not is_instance_valid(m) or m.state == State.DEAD:
			continue
		var boarded: bool = m.siege_boarded
		m.leave_crew()
		if not boarded:
			continue
		# Hurl the passenger off the deck — it falls ~12 m, rolls and only dies
		# once the tumble runs out (user bug: they died instantly at altitude).
		# The crash damage is applied to HP directly (deferred death, resolved by
		# _tick_roll at roll-out) instead of a lethal fall hit that would kill on
		# landing before the roll.
		var angle: float = randf() * TAU
		var out: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		m.throw_airborne(out * randf_range(2.0, 4.0), 0)
		if m.state == State.THROWN:
			m.health -= CRASH_DAMAGE * 2
	crew.clear()
	_fire_cd.clear()
	attack_building = null
	_ordered_unit = null
	_hull_on_fire = false
	if _model != null:
		_model.visible = false
	if path_service != null:
		var debris: BuildingDebris = BuildingDebris.new()
		debris.setup(position, 1.5, terrain_data)
		path_service.register_projectile(debris)
	health = 0
	_die()


# --- Ticking ------------------------------------------------------------------------------

## Empty airships must not burst like a stranded siege engine — they drift home
## (see _tick_drift), so they opt out of the crewless self-destruct.
func destroys_when_uncrewed() -> bool:
	return false


func tick(delta: float) -> void:
	super.tick(delta)
	if state == State.DEAD:
		return
	# Hover height follows the (deformable) terrain every tick (soft model).
	_tick_altitude(delta)
	# Deck crew re-pin: the base crew tick may lag one frame behind a moving
	# hull — pin boarded passengers to their slots right after the hull moved.
	for m in crew:
		if is_instance_valid(m) and m.siege_boarded and m.state == State.CREW:
			m.position = crew_slot_position(m)
	_tick_auto_engage(delta)
	_tick_deck_combat(delta)
	_tick_drift(delta)


## Auto-engage steering: while IDLE or on an attack-move (with a firewarrior OR
## a preacher aboard), close to deck combat reach of the nearest enemy unit —
## or building — within the deck-boosted aggro radius, then stand so the deck
## crew fights. Passive moves march through; explicit targets and a pending
## unload steer themselves. Once nothing is left, an interrupted attack-move
## resumes its kept route.
func _tick_auto_engage(delta: float) -> void:
	_engage_scan -= delta
	if _engage_scan > 0.0:
		return
	_engage_scan = 0.5
	if path_service == null:
		return
	if state != State.IDLE \
			and not (state == State.MOVE and (move_aggressive or _auto_approach)):
		return
	if _ordered_unit != null or attack_building != null or route_end_action.is_valid():
		return
	var has_fw: bool = _has_deck_firewarrior()
	var has_pr: bool = _has_deck_preacher()
	if not has_fw and not has_pr:
		_auto_building = null
		return
	# Stop distance: close enough that the SHORTEST-reach active crew can act —
	# preachers (convert 5 + 3) must get nearer than firewarriors (fire 8 + 3),
	# so a preacher-carrying ship closes in and its firewarriors still fire from
	# farther out on the way. Detection uses the WIDEST crew aggro radius.
	var reach: float = (Preacher.CONVERT_RANGE if has_pr else Firewarrior.FIRE_RANGE) \
		+ RANGE_BONUS
	var aggro: float = RANGE_BONUS
	if has_fw:
		aggro = maxf(aggro, Firewarrior.RANGED_AGGRO + RANGE_BONUS)
	if has_pr:
		aggro = maxf(aggro, Unit.AGGRO_RADIUS + RANGE_BONUS)
	# Already standing: hold as long as the deck crew can fight from here — any
	# enemy within the ship-centred reach, or a preacher mid-conversion. Do NOT
	# inch toward the nearest/highest-priority unit whenever it drifts a few cm
	# past the stop line; that micro-positioning (targets churn, separation
	# nudges) was the attack-move STUTTER, and buys nothing since every crew
	# member fires/converts on the ship-centred reach anyway.
	if state == State.IDLE and (_best_enemy(reach) != null \
			or (has_pr and _deck_preacher_channeling())):
		return
	var stop_at: Vector3
	var dist: float
	var target: Unit = _best_enemy(aggro)
	if target != null:
		_auto_building = null
		stop_at = target.position
		dist = _flat_dist(position, target.position)
	else:
		# A deck preacher mid-conversion drops its target out of _best_enemy (it
		# now SITs), so hold position until the channel finishes — otherwise the
		# ship would fly off and break its own conversion (attack-move bug).
		if has_pr and _deck_preacher_channeling():
			return
		# Only firewarriors can attack buildings — a preacher-only ship that
		# found no unit target just resumes its route.
		var b = _nearest_enemy_building_by_wall(aggro) if has_fw else null
		_auto_building = b
		if b == null:
			# Nothing around: an interrupted attack-move resumes its route.
			if state == State.IDLE and move_aggressive \
					and not waypoint_queue.is_empty():
				_start_path_to(waypoint_queue[0])
			return
		stop_at = b.center_world()
		dist = b.footprint_distance_to(Vector2(position.x, position.z))
	if dist <= reach - 0.2:
		if state == State.MOVE:
			# In reach: stand and fight (the kept route resumes later).
			_auto_approach = false
			_clear_path()
			_set_state(State.IDLE)
		return
	# Beyond reach: close in so the deck crew can act.
	if active_crew_count() < MIN_MOVE_CREW:
		return
	var dir: Vector3 = Vector3(stop_at.x - position.x, 0.0, stop_at.z - position.z)
	if dir.length_squared() < 0.01:
		return
	# Aim the stop point deeper than the desired rest gap by arrive_eps(): a ship
	# counts as "arrived" (-> IDLE) once within arrive_eps (~one separation radius,
	# 2 m) of its path end. Aiming only reach-1.0 from the enemy therefore parked
	# the ship arrive_eps SHORT of that — still ~1 m OUTSIDE reach — so it never
	# entered firing range, re-planned another sub-arrive_eps hop every _engage_scan
	# and stepped forward in tiny choppy stutters. Subtracting arrive_eps makes the
	# ship actually fly INTO reach (the in-flight dist<=reach-0.2 check then halts it).
	var rest_gap: float = reach - 1.0 - arrive_eps()
	_plan_path_to(position + dir.normalized() * (dir.length() - rest_gap))
	_auto_approach = true
	_set_state(State.MOVE)


func _has_deck_firewarrior() -> bool:
	return _has_deck_crew_of_kind(&"firewarrior")


func _has_deck_preacher() -> bool:
	return _has_deck_crew_of_kind(&"preacher")


## True when a boarded, deck-riding crew member of `kind` is aboard (used for
## auto-engage steering and the range display).
func _has_deck_crew_of_kind(kind: StringName) -> bool:
	for m in crew:
		if is_instance_valid(m) and m.siege_boarded and m.state == State.CREW \
				and m.unit_kind() == kind:
			return true
	return false


## True while a boarded deck preacher is actively channeling a conversion (its
## sitting target dropped out of _best_enemy) — the ship holds instead of
## resuming its attack-move route mid-conversion.
func _deck_preacher_channeling() -> bool:
	for m in crew:
		if is_instance_valid(m) and m.siege_boarded and m.state == State.CREW \
				and m.unit_kind() == &"preacher" and m.station_channeling:
			return true
	return false


## Nearest living enemy building by WALL distance (footprint) — the centre of
## a big building can lie beyond the reach while its walls are shootable.
## Nearest enemy building by wall distance — but a WATCHTOWER manned by a
## firewarrior wins over plain buildings (user spec: prioritise tower
## firewarriors, which can't be shot as units while garrisoned). Ties by wall
## distance within each priority tier.
func _nearest_enemy_building_by_wall(radius: float):
	if building_manager == null:
		return null
	var flat: Vector2 = Vector2(position.x, position.z)
	var best = null
	var best_pri: int = -1
	var best_d: float = INF
	for b in building_manager.buildings:
		if not is_instance_valid(b) or b.tribe_id == tribe_id or b.health <= 0:
			continue
		var d: float = b.footprint_distance_to(flat)
		if d > radius:
			continue
		var pri: int = _building_priority(b)
		if pri > best_pri or (pri == best_pri and d < best_d):
			best_pri = pri
			best_d = d
			best = b
	return best


## 1 for a watchtower with a firewarrior aboard (a tower gunner shooting the
## airship), 0 otherwise.
func _building_priority(b) -> int:
	if b is Watchtower:
		for m in (b as Watchtower).crew:
			if is_instance_valid(m) and m.unit_kind() == &"firewarrior":
				return 1
	return 0


## Deck combat (watchtower pattern): only while the ship is STANDING; every
## boarded firewarrior fires (reach +3) and every boarded preacher converts
## (reach +3). An explicitly ordered target is preferred while valid; a
## warrior/brave crew idles (nothing it can do from the deck).
func _tick_deck_combat(delta: float) -> void:
	if state == State.MOVE:
		# A moving ship never channels: drop the deck preachers' conversion
		# channel so their sitting targets stand up instead of sticking to a
		# ship that is flying away.
		for m in crew:
			if is_instance_valid(m) and m.station_channeling:
				m.station_channeling = false
				_set_deck_anim(m, &"idle")
		_deck_elapsed = 0.0
		return
	if _ordered_unit != null and (not is_instance_valid(_ordered_unit)
			or _ordered_unit.state == State.DEAD
			or _ordered_unit.tribe_id == tribe_id):
		_ordered_unit = null
	if attack_building != null and (not is_instance_valid(attack_building)
			or attack_building.health <= 0):
		attack_building = null
	if path_service == null:
		return
	# Throttle the per-crew target scans (the only ungated per-frame combat
	# scan). The crew handlers get the accumulated elapsed time so their fire/
	# convert cooldowns advance exactly as before — only re-acquisition and the
	# channel refresh run at ~5x/s instead of once per frame.
	_deck_elapsed += delta
	_deck_scan -= delta
	if _deck_scan > 0.0:
		return
	_deck_scan = DECK_SCAN_INTERVAL
	var step: float = _deck_elapsed
	_deck_elapsed = 0.0
	for m in crew:
		if not is_instance_valid(m) or not m.siege_boarded or m.state != State.CREW:
			continue
		match m.unit_kind():
			&"firewarrior":
				_tick_deck_firewarrior(m, step)
			&"preacher":
				_tick_deck_preacher(m, step)
			_:
				pass   # warriors/braves/shaman: passengers only


func _tick_deck_firewarrior(fw, delta: float) -> void:
	var cd: float = float(_fire_cd.get(fw, 0.0)) - delta
	var reach: float = Firewarrior.FIRE_RANGE + RANGE_BONUS
	# Ordered unit first, then the ordered building, then free fire at will.
	var target: Unit = null
	if _ordered_unit != null and _flat_dist(position, _ordered_unit.position) <= reach \
			and _ordered_unit.is_targetable():
		target = _ordered_unit
	if target == null and attack_building != null \
			and _flat_dist(position, attack_building.center_world()) <= reach:
		_set_deck_anim(fw, &"throw")
		fw.facing = _flat_dir(position, attack_building.center_world())
		if cd <= 0.0:
			cd = Firewarrior.FIRE_COOLDOWN
			fw.anim_start_ms = Time.get_ticks_msec()
			fw.fire_at_building_from(fw.position, attack_building)
		_fire_cd[fw] = cd
		return
	if target == null:
		target = _best_enemy(reach)
	if target == null:
		# No unit in reach: free-fire at the nearest enemy BUILDING (lowest
		# priority, like ground firewarriors — user spec: buildings in reach
		# are attacked automatically).
		var b = _free_fire_building(reach)
		if b != null:
			fw.facing = _flat_dir(position, b.center_world())
			_set_deck_anim(fw, &"throw")
			if cd <= 0.0:
				cd = Firewarrior.FIRE_COOLDOWN
				fw.anim_start_ms = Time.get_ticks_msec()
				fw.fire_at_building_from(fw.position, b)
			_fire_cd[fw] = cd
			return
		_fire_cd[fw] = 0.0
		_set_deck_anim(fw, &"idle")
		return
	fw.facing = _flat_dir(position, target.position)
	_set_deck_anim(fw, &"throw")
	if cd <= 0.0:
		cd = Firewarrior.FIRE_COOLDOWN
		fw.anim_start_ms = Time.get_ticks_msec()
		fw.fire_from(fw.position, target)
	_fire_cd[fw] = cd


## Auto building target for the deck firewarriors: the engage scan's pick
## while its walls stay in reach, else a fresh wall-distance scan.
func _free_fire_building(reach: float):
	var b = _auto_building
	if b != null and is_instance_valid(b) and b.health > 0 and b.tribe_id != tribe_id \
			and b.footprint_distance_to(Vector2(position.x, position.z)) <= reach:
		return b
	return _nearest_enemy_building_by_wall(reach)


## Pacifies EVERY convertible ground enemy within the boosted reach via the
## standard begin_conversion/SIT path (ground-preacher pattern): targets
## visibly sit down and Unit._tick_sit runs the per-target timer — it keeps
## ticking while this preacher stays aboard and channeling
## (station_channeling; cleared while the ship moves, see _tick_deck_combat).
func _tick_deck_preacher(pr, delta: float) -> void:
	var reach: float = Preacher.CONVERT_RANGE + RANGE_BONUS
	var channeling: bool = false
	var nearest: Unit = null
	var nearest_d: float = INF
	for u in path_service.get_units_in_radius(position, reach, SCAN_MAX_CANDIDATES):
		if u.tribe_id == tribe_id or u.state == State.DEAD \
				or u.is_conversion_immune() or not u.is_targetable() \
				or u.is_airborne():
			continue
		var d: float = _flat_dist(position, u.position)
		if d > reach:
			continue
		if u.state == State.SIT:
			channeling = channeling or u.converting_preacher == pr
			continue
		# Fight inertia like the ground preacher: an already-fighting unit
		# sometimes keeps brawling for now (retried on the next tick).
		if u.state == State.ATTACK and randf() < Preacher.FIGHT_INERTIA_CHANCE:
			continue
		if u.begin_conversion(pr, randf_range(
				Preacher.CONVERT_TIME_MIN, Preacher.CONVERT_TIME_MAX), reach):
			channeling = true
			if d < nearest_d:
				nearest_d = d
				nearest = u
	pr.station_channeling = channeling
	if channeling:
		if nearest != null:
			pr.facing = _flat_dir(position, nearest.position)
		_set_deck_anim(pr, &"cast")
		# Chant sound like a ground preacher (throttled via its own timer) — a
		# deck preacher was silent while converting (user bug).
		pr._preach_sound_timer -= delta
		if pr._preach_sound_timer <= 0.0:
			pr._preach_sound_timer = Preacher.PREACH_SOUND_INTERVAL
			pr._emit_combat_hit(&"preach")
	else:
		_set_deck_anim(pr, &"idle")


func _flat_dir(from: Vector3, to: Vector3) -> Vector3:
	var d: Vector3 = Vector3(to.x - from.x, 0.0, to.z - from.z)
	return d.normalized() if d.length_squared() > 0.000001 else Vector3(0, 0, 1)


## Deck crew tick themselves (unlike housed tower crew), so their own
## _apply_animation would reset the anim each frame — drive the combat anim via
## crew_action_anim, which _anim_base() honours while riding (State.CREW).
func _set_deck_anim(u, base: StringName) -> void:
	u.crew_action_anim = base


## Attack-target scan (user spec): the airship prioritises the threats that can
## shoot it down — enemy FIREWARRIORS first (ground OR riding an enemy deck),
## then CATAPULT crew — over anything else; ties break on distance. Enemy
## firewarriors garrisoned on a tower are unreachable as units (protected
## reserve) — they are prioritised through the building scan instead.
func _best_enemy(radius: float) -> Unit:
	var best: Unit = null
	var best_pri: int = -1
	var best_d: float = INF
	for u in path_service.get_units_in_radius(position, radius, SCAN_MAX_CANDIDATES):
		if u.tribe_id == tribe_id or u.state == State.DEAD or not u.is_targetable():
			continue
		if u.state == State.SIT:
			continue   # sitting converts keep sitting (a preacher aboard works)
		var d: float = _flat_dist(position, u.position)
		if d > radius:
			continue
		var pri: int = _enemy_priority(u)
		if pri > best_pri or (pri == best_pri and d < best_d):
			best_pri = pri
			best_d = d
			best = u
	return best


## Target priority: enemy firewarriors (2) > catapult crew (1) > the rest (0).
func _enemy_priority(u: Unit) -> int:
	if u.unit_kind() == &"firewarrior":
		return 2
	var eng = u.siege_engine
	if eng != null and is_instance_valid(eng) and eng is SiegeEngine:
		return 1
	return 0


## Empty airships drift slowly toward the nearest reincarnation site's island
## (any tribe = "reachable from the start bases") so they never strand over
## water or on unreachable spots. Throttled; stops over walkable ground on
## that island.
func _tick_drift(delta: float) -> void:
	if state != State.IDLE or crew_count() > 0:
		return
	_drift_check -= delta
	if _drift_check > 0.0:
		_apply_drift(delta)
		return
	_drift_check = DRIFT_CHECK_INTERVAL
	_anchor_repick -= DRIFT_CHECK_INTERVAL
	if _anchor_repick <= 0.0 or _drift_anchor == null \
			or not is_instance_valid(_drift_anchor):
		_anchor_repick = ANCHOR_REPICK_INTERVAL
		_drift_anchor = _nearest_reincarnation_site()
	_drifting = _needs_drift()
	_apply_drift(delta)


var _drifting: bool = false


func _apply_drift(delta: float) -> void:
	if not _drifting or _drift_anchor == null or not is_instance_valid(_drift_anchor):
		return
	var dest: Vector3 = _drift_anchor.center_world()
	var dir: Vector3 = Vector3(dest.x - position.x, 0.0, dest.z - position.z)
	if dir.length_squared() < 1.0:
		_drifting = false
		return
	position += dir.normalized() * DRIFT_SPEED * delta


## Drift while the shadow is not on walkable ground of the anchor's island.
func _needs_drift() -> bool:
	if _drift_anchor == null or not is_instance_valid(_drift_anchor) or nav_grid == null:
		return false
	var cell: Vector2i = nav_grid.world_to_cell(position)
	if not nav_grid.is_cell_walkable(cell):
		return true
	return not nav_grid.same_island(position, _drift_anchor.center_world())


func _nearest_reincarnation_site():
	if building_manager == null:
		return null
	var best = null
	var best_d: float = INF
	for b in building_manager.buildings:
		if not is_instance_valid(b) or b.health <= 0 or not (b is ReincarnationSite):
			continue
		var d: float = _flat_dist(b.center_world(), position)
		if d < best_d:
			best_d = d
			best = b
	return best


# --- Visuals (own 3D model, in-game only) -------------------------------------------

func _create_model() -> void:
	var root: Node3D = Node3D.new()
	root.name = "Model"
	add_child(root)
	_model = root

	# User-provided model (assets/models/units/airship.glb) when present;
	# optional named child "Flag" (MeshInstance3D) takes the tribe colour.
	var custom: Node3D = AssetLibrary.instantiate_model("models/units/airship.glb")
	if custom != null:
		root.add_child(custom)
		_flag_mesh = custom.find_child("Flag", true, false) as MeshInstance3D
		_finish_model(root)
		_setup_ground_shadow(root)
		return

	# Balloon: a stretched ellipsoid, ~6 m long x 2 m wide, riding HIGH above
	# the gondola so the deck (and the passengers on it) stays freely visible
	# — passengers used to clip into the balloon (user feedback).
	var balloon: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	balloon.mesh = sphere
	balloon.material_override = _mat(Color(0.75, 0.68, 0.5))
	balloon.scale = Vector3(1.0, 0.9, 3.0)
	balloon.position.y = 3.4
	root.add_child(balloon)

	# Gondola (deck) hanging far under the balloon — the passengers stand on it.
	var gondola: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(1.6, 0.5, 3.6)
	gondola.mesh = box
	gondola.material_override = _mat(C_WOOD)
	gondola.position.y = 0.35
	root.add_child(gondola)

	# Four ropes tie the balloon to the gondola corners.
	for sx in [-0.7, 0.7]:
		for sz in [-1.5, 1.5]:
			_add_rope(root, Vector3(sx, 0.6, sz),
				Vector3(sx * 0.6, 2.7, sz * 0.75))

	# Owner flag at the stern of the balloon (recoloured on takeover).
	_flag_mesh = MeshInstance3D.new()
	var flag_box: BoxMesh = BoxMesh.new()
	flag_box.size = Vector3(0.5, 0.3, 0.03)
	_flag_mesh.mesh = flag_box
	_flag_mesh.position = Vector3(0.0, 3.5, -3.3)
	root.add_child(_flag_mesh)

	_finish_model(root)
	_setup_ground_shadow(root)


## Thin rope segment from `a` to `b` (model-local coordinates).
func _add_rope(root: Node3D, a: Vector3, b: Vector3) -> void:
	var rope: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.03
	cyl.height = a.distance_to(b)
	rope.mesh = cyl
	rope.material_override = _mat(C_WOOD_DARK)
	root.add_child(rope)
	rope.position = (a + b) * 0.5
	var dir: Vector3 = (b - a).normalized()
	var axis: Vector3 = Vector3.UP.cross(dir)
	if axis.length_squared() > 0.000001:
		rope.rotate(axis.normalized(), Vector3.UP.angle_to(dir))


## The base _finish_model blob sits at the model origin (12 m up) — move it
## to a dedicated node whose GLOBAL Y is re-set to the terrain each visual
## tick, so the shadow stays on the ground under the hull.
var _ground_shadow: MeshInstance3D = null


func _setup_ground_shadow(root: Node3D) -> void:
	var blob: MeshInstance3D = root.get_node_or_null("BlobShadow") as MeshInstance3D
	if blob == null:
		return
	blob.mesh = UnitRenderer.make_blob_mesh(Vector2(2.4, 6.0))
	_ground_shadow = blob


## Gentle hover bob + ground shadow follow; the base handles heading. The hull
## fire is the shared 2D StatusFxRenderer billboard (is_burning + burn_fx_*).
func _tick_visual(delta: float) -> void:
	super._tick_visual(delta)
	if not is_inside_tree():
		return
	if _model != null and state != State.DEAD:
		_model.position.y = 0.15 * sin(float(Time.get_ticks_msec()) * 0.0012)
	if _ground_shadow != null and terrain_data != null:
		var ground: float = maxf(terrain_data.get_height(position.x, position.z),
			TerrainData.SEA_LEVEL)
		_ground_shadow.global_position = Vector3(position.x, ground + 0.05, position.z)
