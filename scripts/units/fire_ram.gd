class_name FireRam extends CrewedVehicle

## Feuerramme: a pushable flame-thrower vehicle built by the fire-ram
## workshop.
##
## - Crew 1..4 (any unit except the shaman); ONE crew member both drives AND
##   fires. Slow (3 m/s) with a REAL turn rate: the hull slews toward the
##   facing at FIRERAM_TURN_RATE and the flame burst only starts once the
##   hull points at the target (sweeping DURING a burst is a feature).
## - Weapon: a forward flame burst — FLAME_DURATION seconds of flames over a
##   rectangle FIRE_RANGE long x FLAME_WIDTH wide in front of the hull, then
##   a crew-scaled reload. NO minimum range. Everything in the rectangle is
##   set alight: units get the no-contact-damage burn (Unit.scorch), wooden
##   vehicles ignite properly, buildings accrue lava-contact stage damage,
##   trees and wood piles catch fire. Friendly fire: flames burn everything
##   (consistent with lava and the catapult splash).
## - Crew is immune to ranged distraction (crew_defends_melee_only): being
##   shot at never pulls it off the vehicle — only direct melee pressure does.
## - Destruction/boarding/capture exactly like the catapult (CrewedVehicle).

const MAX_CREW: int = Balance.FIRERAM_MAX_CREW
const MIN_MOVE_CREW: int = Balance.FIRERAM_MIN_MOVE_CREW
const MIN_FIRE_CREW: int = Balance.FIRERAM_MIN_FIRE_CREW
const FIRE_RANGE: float = Balance.FIRERAM_FIRE_RANGE
## Units closer than this stand behind the nozzle — the ram holds its fire
## against them (buildings hugging the hull still burn fine).
const MIN_RANGE: float = Balance.FIRERAM_MIN_RANGE
## Flame rectangle widths: FLAME_WIDTH at the nozzle, FLAME_END_WIDTH at the far
## end of the range — the cone fans out linearly from 2 to 3 wide.
const FLAME_WIDTH: float = Balance.FIRERAM_FLAME_WIDTH
const FLAME_END_WIDTH: float = Balance.FIRERAM_FLAME_END_WIDTH
const FLAME_DURATION: float = Balance.FIRERAM_FLAME_DURATION
const COOLDOWN_MIN_CREW: float = Balance.FIRERAM_COOLDOWN_MIN_CREW
const COOLDOWN_FULL_CREW: float = Balance.FIRERAM_COOLDOWN_FULL_CREW
const RAM_AGGRO: float = Balance.FIRERAM_AGGRO_RADIUS
const TURN_RATE: float = Balance.FIRERAM_TURN_RATE
const AIM_TOLERANCE: float = Balance.FIRERAM_AIM_TOLERANCE
## Fraction of FIRE_RANGE a unit target is closed to while burning: runners
## near the range edge are pursued (firing on the move) instead of popping in
## and out of the band; only this deep inside does the ram actually stop.
const HOLD_RANGE_FRAC: float = 0.5
## Flame area re-check cadence during a burst (LavaSurge rhythm).
const FLAME_CHECK_INTERVAL: float = 0.2
## Lava-contact credit per flame second on buildings — see Balance doc (the
## 1-s grace window between bursts would void raw contact seconds).
const FLAME_CONTACT_FACTOR: float = Balance.FIRERAM_FLAME_CONTACT_FACTOR
## Flame origin: this far in front of the hull centre. Gameplay value (flame
## rectangle start, dead zone vs MIN_RANGE) — kept despite the smaller model.
const NOZZLE_OFFSET: float = 1.2
## True minimum firing distance: the flame rectangle only starts at NOZZLE_OFFSET,
## so a unit closer than that sits in the dead zone behind the nozzle and cannot
## be hit even though it is past the (display) MIN_RANGE. Targeting and the
## retreat use THIS as the near edge so the ram backs up far enough to actually
## land flames again. (>= MIN_RANGE by construction; MIN_RANGE still drives the
## RangeRenderer inner ring and balance.)
const FLAME_MIN_RANGE: float = maxf(NOZZLE_OFFSET, Balance.FIRERAM_MIN_RANGE)
## Flame segments hover this far above the sampled ground (box half-height plus a
## touch), so the beam licks along the terrain instead of clipping into it.
const FLAME_LIFT: float = 0.35
## Placeholder-model shrink factor (footprint 1.2 x 1.8 instead of the shared
## vehicle chassis 1.4 x 2.2).
const MODEL_SCALE: float = 0.85
## Fire resistance: the ram survives FIRE_LIVES fire hits (max 1 per source per
## attack) instead of dying on the first; a crewed ram heals 1 hit every
## LIFE_REGEN_TIME. Physical destruction (water/terrain/tornado) bypasses this.
const FIRE_LIVES: int = Balance.FIRERAM_FIRE_LIVES
const LIFE_REGEN_TIME: float = Balance.FIRERAM_LIFE_REGEN_TIME

## Worker references (injected by UnitManager.spawn_unit via unit.set() — a
## silent no-op without these declarations; flames must ignite trees/piles).
var tree_manager = null
var wood_pile_manager = null

## Seconds of flame left in the running burst (0 = not flaming).
var _flame_time: float = 0.0
var _reload: float = 0.0
var _flame_check: float = 0.0
## Buildings already credited during the current check tick.
var _flamed_buildings: Dictionary = {}
## Fire-resistance state (see _apply_fire_hit): accumulated FIRE damage
## (0 = unhurt, FIRE_LIVES = burnt down).
var _fire_hits: int = 0
## Bumped at the START of each own flame burst so one sustained burst counts as
## ONE hit on a target while separate bursts each count (see fire_attack_key).
var _burst_seq: int = 0
## Attack keys already counted toward _fire_hits (per-source/-attack throttle);
## cleared once the ram fully regenerates.
var _seen_attacks: Dictionary = {}
## Fractional accumulator for the crewed 1-life-per-LIFE_REGEN_TIME regen.
var _life_regen_frac: float = 0.0
## Hull heading, slewed toward `facing` at TURN_RATE (real turn inertia —
## `facing` itself snaps instantly everywhere in the codebase).
var _heading: Vector3 = Vector3(0, 0, 1)
## Flame cone visual meshes (in-game only, lazily built).
var _flame_cone: Node3D = null
## The 3 flame segments, laid onto the terrain each visual tick.
var _flame_segs: Array[MeshInstance3D] = []


func _init() -> void:
	super()
	speed = Balance.FIRERAM_SPEED
	max_crew = MAX_CREW
	min_move_crew = MIN_MOVE_CREW
	min_fire_crew = MIN_FIRE_CREW
	# 2 crew slots per side on the shorter hull.
	crew_side_offset = 0.75
	crew_rank_spacing = 0.85
	vehicle_ring_scale = 3.4
	vehicle_separation = 3.0
	# Smaller footprint than the shared vehicle default (1.4 x 2.2).
	chassis_half_width = 0.6
	chassis_half_length = 0.9


func unit_kind() -> StringName:
	return &"fireram"


## Smaller hull than the shared vehicle pick rect (2.6 x 2.2).
func pick_size_m() -> Vector2:
	return Vector2(2.2, 1.8)


## The ram may burn enemy GROUND vehicles (their hulls ignite); airships hover
## far above the flame cone.
func _may_target_vehicle(enemy: Unit) -> bool:
	return enemy is CrewedVehicle and not enemy.crew_rides_on_deck()


func crew_defends_melee_only() -> bool:
	return true


func aggro_radius() -> float:
	return RAM_AGGRO


## Hull heading with real turn inertia (the model rotates to this).
func _model_heading() -> Vector3:
	return _heading


# --- Orders & ticking ---------------------------------------------------------------

## Explicit attack order on a unit: clears a building focus; the base marks
## the target ORDERED so the ram chases it even beyond the flame range.
func order_attack(enemy: Unit) -> void:
	attack_building = null
	super.order_attack(enemy)


func tick(delta: float) -> void:
	_slew_heading(delta)
	_reload = maxf(_reload - delta, 0.0)
	# A started burst always finishes (even if the target died or the state
	# changed): the rectangle follows the CURRENT heading, so slow turning
	# sweeps the flames across the field.
	if _flame_time > 0.0 and state != State.DEAD:
		_flame_time -= delta
		_flame_check -= delta
		if _flame_check <= 0.0:
			_flame_check = FLAME_CHECK_INTERVAL
			_apply_flames()
		if _flame_time <= 0.0:
			# Never store an INFINITE reload: if the crew was pacified/converted
			# away exactly as the burst ended, active_crew_count() is 0 and
			# flame_cooldown_for_crew would return INF, which maxf() could never
			# decay — the ram would stay unable to fire even after re-crewing
			# (user bug). Compute the reload as if at least a firing crew.
			_reload = flame_cooldown_for_crew(maxi(active_crew_count(), MIN_FIRE_CREW))
			_show_flame_cone(false)
	_tick_fire_regen(delta)
	super.tick(delta)


## Crewed rams heal 1 fire life every LIFE_REGEN_TIME — even mid-combat (no
## out-of-combat delay, unlike Unit._tick_regen). An uncrewed ram does not heal.
func _tick_fire_regen(delta: float) -> void:
	if _fire_hits > 0 and state != State.DEAD and active_crew_count() > 0:
		_life_regen_frac += delta
		if _life_regen_frac >= LIFE_REGEN_TIME:
			_life_regen_frac -= LIFE_REGEN_TIME
			_fire_hits -= 1
			if _fire_hits <= 0:
				_seen_attacks.clear()
	else:
		_life_regen_frac = 0.0


# --- Fire resistance (3 lives) --------------------------------------------------------

## Fire resistance: instead of the one-hit burn-and-sink of a plain vehicle, the
## ram funnels every fire contact (ram flames, lava, fireball, lightning — they
## all route through ignite/scorch) into the lives model. Physical destruction
## (water/terrain/tornado) does NOT call ignite, so it still kills instantly.
func ignite(_source_pos: Vector3, source = null) -> void:
	_apply_fire_hit(source)


## Adds at most one fire hit PER SOURCE PER ATTACK. The attack key is stable
## within one attack but differs between attacks (an enemy ram's key changes per
## burst; a lava puddle / bolt keeps its instance id), so sustained contact from
## one source costs one life while a fresh source/burst costs another. At
## FIRE_LIVES the ram burns down (sinks; the crew survives and is released).
func _apply_fire_hit(source) -> void:
	if state == State.DEAD:
		return
	var key: String = _attack_key_for(source)
	if key != "":
		if _seen_attacks.has(key):
			return
		_seen_attacks[key] = true
	_fire_hits += 1
	if _fire_hits == 1:
		_play_sfx(&"siege_burning")
	if _fire_hits >= FIRE_LIVES:
		_death_sfx = &"siege_death_burn"
		_destroy_vehicle(false)


## Throttle key for a fire source. A source exposing fire_attack_key() (the fire
## ram) picks its own per-burst key; any other object throttles by instance
## (one life per lava puddle / bolt). A null source is an anonymous one-shot
## (fireball bolt, lightning) that always counts once.
func _attack_key_for(source) -> String:
	if source == null:
		return ""
	if source.has_method("fire_attack_key"):
		return source.fire_attack_key()
	if source is Object:
		return str(source.get_instance_id())
	return ""


## Key this ram stamps on the fire it deals: unique per burst so each of its
## flame bursts counts once on a target (the 0.2 s re-checks within a burst share
## the key and do not stack).
func fire_attack_key() -> String:
	return "%d:%d" % [get_instance_id(), _burst_seq]


## Burning while it carries any fire damage (drives the shared flame billboard).
func is_burning() -> bool:
	return _fire_hits > 0


## Flame size shows the accumulated damage: 1 = small, 2 = medium, 3 = big (the
## lethal hit, shown as it sinks).
func burn_fx_scale() -> float:
	match _fire_hits:
		1: return 1.3
		2: return 1.8
		_: return 2.8


## Rotates the hull toward `facing` at the fixed turn rate.
func _slew_heading(delta: float) -> void:
	var target: Vector3 = facing
	if target.length_squared() < 0.000001:
		return
	target = target.normalized()
	var cur: float = atan2(_heading.x, _heading.z)
	var want: float = atan2(target.x, target.z)
	var diff: float = wrapf(want - cur, -PI, PI)
	var step: float = TURN_RATE * delta
	if absf(diff) <= step:
		_heading = target
	else:
		var a: float = cur + signf(diff) * step
		_heading = Vector3(sin(a), 0.0, cos(a))


## Whether the hull points at `point` closely enough to open fire.
func _aimed_at(point: Vector3) -> bool:
	var to: Vector3 = Vector3(point.x - position.x, 0.0, point.z - position.z)
	if to.length_squared() < 0.000001:
		return true
	var cur: float = atan2(_heading.x, _heading.z)
	var want: float = atan2(to.x, to.z)
	return absf(wrapf(want - cur, -PI, PI)) <= AIM_TOLERANCE


## Auto target acquisition (idle + aggressive move): burn whatever is already
## inside the flame range (units first), otherwise roll toward the nearest
## enemy building within aggro. Once engaged, _burn_unit prefers in-range
## enemies and only chases (leashed to RAM_AGGRO for auto targets) when the
## target was practically the only foe around.
func _auto_acquire(delta: float) -> bool:
	if active_crew_count() < MIN_FIRE_CREW:
		return false
	if not _due_to_scan(delta):
		return false
	# Units before buildings across the WHOLE aggro radius (not just flame
	# range): a nearer enemy unit must win over a farther building — the ram
	# rolls toward it and burns once inside FIRE_RANGE. Auto target, so the
	# chase stays leashed to RAM_AGGRO in _burn_unit.
	var u: Unit = _nearest_enemy_unit(RAM_AGGRO)
	if u != null:
		_begin_attack(u)   # auto: _target_ordered stays false (leashed chase)
		return true
	var b = _scan_enemy_building(RAM_AGGRO)
	if b != null:
		_set_building_target(b, true)   # keep the move route (resume after)
		return true
	return false


func _engage_on_sight(delta: float) -> bool:
	return _auto_acquire(delta)


func _tick_idle(delta: float) -> void:
	_auto_acquire(delta)


## Flame combat. A live unit target takes precedence over the building focus;
## a dead/gone target falls back to the building, then to re-acquisition.
func _tick_attack(delta: float) -> void:
	if active_crew_count() < MIN_MOVE_CREW:
		attack_building = null
		_end_attack()
		_set_state(State.IDLE)
		return
	if _unit_target_attackable(attack_target) and attack_target.tribe_id != tribe_id:
		_burn_unit(attack_target, delta)
		return
	if attack_target != null:
		_end_attack()
	if _building_target_valid():
		if _due_to_scan(delta):
			# Divert from the building to any enemy unit within aggro (units
			# before buildings), preferring fresh over already-burning ones.
			var u: Unit = _nearest_enemy_unit(RAM_AGGRO)
			if u != null:
				_begin_attack(u)
				return
		_burn_point(attack_building.center_world(), delta, true,
			attack_building.footprint_distance_to(
				Vector2(position.x, position.z)))
		return
	attack_building = null
	_retarget_or_idle()


## Re-acquisition after a lost target — same rule as _auto_acquire.
func _retarget_or_idle() -> void:
	_end_attack()
	if active_crew_count() >= MIN_FIRE_CREW:
		# Units before buildings across the aggro radius (fresh before burning).
		var u: Unit = _nearest_enemy_unit(RAM_AGGRO)
		if u != null:
			_begin_attack(u)
			return
		var b = _scan_enemy_building(RAM_AGGRO)
		if b != null:
			_set_building_target(b, true)
			return
	if not waypoint_queue.is_empty():
		attack_building = null
		_start_path_to(waypoint_queue[0])
		return
	attack_building = null
	_set_state(State.IDLE)


## Unit target: burn it while in the [MIN_RANGE, FIRE_RANGE] band, firing ON
## THE MOVE (no stop-and-go at the 5 m border — user feedback: the ram used
## to "twitch" after fleeing scorched units). A nearer enemy already inside
## the flame range ALWAYS takes over, even over an ordered target; the ram
## only chases when it was (nearly) the only foe — ordered targets without
## an in-range alternative, auto targets additionally leashed to RAM_AGGRO.
## A unit that crept behind the nozzle is swapped for another in-band enemy
## (auto) or held without fire (ordered) — the catapult's minimum-range rule.
func _burn_unit(target: Unit, delta: float) -> void:
	var dist: float = _flat_dist(position, target.position)
	if dist > FIRE_RANGE:
		# Prefer whoever is already in range over any chase (user spec).
		if _due_to_scan(delta):
			var near: Unit = _nearest_enemy_unit(FIRE_RANGE)
			if near != null and near != target:
				_begin_attack(near)
				return
		if not _target_ordered and dist > RAM_AGGRO:
			_end_attack()
			_retarget_or_idle()
			return
		_in_melee = false
		_approach(target.position, delta)
		_face_point(target.position)
		return
	if dist < FLAME_MIN_RANGE:
		# A target inside the nozzle dead zone cannot be hit. Prefer ANY
		# shootable enemy in the firing band over holding fire — even over an
		# ordered target (it is unhittable from here anyway). _nearest_enemy_unit
		# only returns units in [FLAME_MIN_RANGE, FIRE_RANGE], i.e. exactly the
		# "shootable" set. Unthrottled: this branch only runs in the rare
		# behind-the-nozzle state.
		var alt: Unit = _nearest_enemy_unit(FIRE_RANGE)
		if alt != null and alt != target:
			_begin_attack(alt)
			return
		# Nobody else to shoot: back away from the threat to reopen the firing
		# distance, staying aimed at it so we fire the instant it clears the dead
		# zone (dist >= FLAME_MIN_RANGE falls through to _burn_point below).
		if _has_path():
			_clear_path()
		_in_melee = false
		_face_point(target.position)
		_reverse_from(target.position, delta)
		return
	_burn_point(target.position, delta, false, dist)


## Burns toward a point: turn the hull, then open the burst once aimed and
## reloaded — the burst does NOT require standing still (the flame rectangle
## follows the current hull heading every check anyway, so driving sweeps).
## `approach` closes the gap for far-away buildings; buildings in range are
## burnt standing (they do not run). `dist` = flat distance to the target
## surface.
func _burn_point(target_pos: Vector3, delta: float, approach: bool,
		dist: float) -> void:
	if dist > FIRE_RANGE:
		if not approach:
			return
		_in_melee = false
		_approach(target_pos, delta)
		_face_point(target_pos)
		return
	if not approach and dist > FIRE_RANGE * HOLD_RANGE_FRAC:
		# Unit target near the range edge: keep rolling after it while firing.
		_in_melee = false
		_approach(target_pos, delta)
	else:
		if _has_path():
			_clear_path()
		_in_melee = true
	_face_point(target_pos)
	attack_anim = &"throw"
	if active_crew_count() < MIN_FIRE_CREW:
		return
	if _flame_time > 0.0 or _reload > 0.0:
		return
	if not _aimed_at(target_pos):
		return   # the hull is still turning toward the target
	_flame_time = FLAME_DURATION
	_flame_check = 0.0   # first area check right away
	_burst_seq += 1      # new burst -> new fire_attack_key (one hit per burst)
	_show_flame_cone(true)
	# Dedicated attack whoosh — was wrongly reusing "siege_burning" (reserved
	# for the vehicle CATCHING fire via ignite(), see CrewedVehicle) for every
	# burst, so any siege_burning.ogg asset would fire on every attack too.
	# Mirrors the catapult's siege_fire pattern: a custom asset takes over,
	# otherwise the shared synthesised "throw" whoosh (Firewarrior's launch
	# sound) plays instead of staying silent.
	if is_inside_tree():
		var audio: Node = get_node_or_null("/root/AudioManager")
		if audio != null and audio.has_sfx(&"fireram_burst"):
			audio.play_sfx(&"fireram_burst", position)
			return
	_emit_combat_hit(&"throw")


## Backs the hull straight away from `threat_pos` by one step, WITHOUT touching
## `facing` (the caller keeps the hull aimed at the threat via _face_point, so
## the ram fires the instant the threat clears the minimum range). Refuses to
## move without a driving crew, and never reverses onto a cell it cannot occupy
## (water/cliff/narrow ledge) — a cornered ram just holds and keeps aiming.
func _reverse_from(threat_pos: Vector3, delta: float) -> void:
	if active_crew_count() < MIN_MOVE_CREW:
		return
	var away: Vector2 = Vector2(position.x - threat_pos.x, position.z - threat_pos.z)
	if away.length_squared() < 0.000001:
		return
	away = away.normalized()
	var step: float = _slope_speed(_slope_ahead(away)) * delta
	var nx: float = position.x + away.x * step
	var nz: float = position.z + away.y * step
	if nav_grid != null and not nav_grid.is_cell_vehicle_walkable(
			nav_grid.world_to_cell(Vector3(nx, 0.0, nz))):
		return
	position.x = nx
	position.z = nz
	_snap_to_ground()


## Seconds of reload after a burst for a boarded crew of `count`
## (1 -> 3 s, 4 (full) -> 1.4 s, linear; below 1 there is no burst at all).
static func flame_cooldown_for_crew(count: int) -> float:
	if count < MIN_FIRE_CREW:
		return INF
	var t: float = float(clampi(count, MIN_FIRE_CREW, MAX_CREW) - MIN_FIRE_CREW) \
		/ float(MAX_CREW - MIN_FIRE_CREW)
	return lerpf(COOLDOWN_MIN_CREW, COOLDOWN_FULL_CREW, t)


## Nearest enemy unit inside `max_range` that the ram may burn (its splash-like
## flames do not care about conversion trances — like the catapult, no SIT
## skip). Two-tier preference: a unit that is NOT already burning wins over any
## burning one, and only within a tier does distance decide. A single scorch
## already lands the full 4-s / 60-HP burn (lethal to soft units), so re-aiming
## at an already-lit enemy wastes the burst — spread the fire to fresh targets
## and fall back to burning ones only when nothing fresh is in range.
func _nearest_enemy_unit(max_range: float) -> Unit:
	if path_service == null:
		return null
	var best_fresh: Unit = null
	var best_fresh_d: float = max_range
	var best_burn: Unit = null
	var best_burn_d: float = max_range
	for u in path_service.get_units_in_radius(position, max_range, SCAN_MAX_CANDIDATES):
		if u == self or u.state == State.DEAD or u.tribe_id == tribe_id:
			continue
		if not u.is_targetable() and not _may_target_vehicle(u):
			continue
		if u.is_airborne():
			continue   # flames stay on the ground
		var d: float = _flat_dist(position, u.position)
		if d < FLAME_MIN_RANGE or d > max_range:
			continue   # inside the nozzle dead zone — cannot be burnt
		if u.is_burning():
			if d < best_burn_d:
				best_burn_d = d
				best_burn = u
		elif d < best_fresh_d:
			best_fresh_d = d
			best_fresh = u
	return best_fresh if best_fresh != null else best_burn


# --- Flame area -----------------------------------------------------------------------

## One area check of the running burst: everything inside the FIRE_RANGE x
## FLAME_WIDTH rectangle in front of the hull catches fire. Runs every
## FLAME_CHECK_INTERVAL while the burst lasts; the rectangle follows the
## CURRENT hull heading (sweeping).
func _apply_flames() -> void:
	var forward: Vector3 = _heading.normalized() if _heading.length_squared() > 0.0 \
		else Vector3(0, 0, 1)
	var right: Vector3 = Vector3(-forward.z, 0.0, forward.x)
	var origin: Vector3 = position + forward * NOZZLE_OFFSET
	# Units: broad-phase radius around the rectangle centre, narrow-phase in the
	# heading frame with a half-width that widens toward the far end (2 -> 3).
	# Friendly fire on purpose (flames know no friends).
	if path_service != null:
		var centre: Vector3 = origin + forward * (FIRE_RANGE * 0.5)
		var broad: float = FIRE_RANGE * 0.5 + FLAME_END_WIDTH * 0.5 + 0.5
		for u in path_service.get_units_in_radius(centre, broad):
			if u == self or u.state == State.DEAD:
				continue
			if u.state == State.THROWN or u.rides_airborne():
				continue   # airborne units pass over the flames
			var rel: Vector3 = u.position - origin
			var along: float = rel.x * forward.x + rel.z * forward.z
			var side: float = rel.x * right.x + rel.z * right.z
			if along < 0.0 or along > FIRE_RANGE or absf(side) > _flame_half_width(along):
				continue
			u.scorch(origin, self)
	# Buildings: sample the rectangle's centreline; one lava-contact credit
	# per building per check (FLAME_CONTACT_FACTOR beats the grace window).
	_flamed_buildings.clear()
	if building_manager != null:
		for i in range(int(FIRE_RANGE)):
			var d: float = 0.5 + float(i)
			var sample: Vector3 = origin + forward * d
			var flat: Vector2 = Vector2(sample.x, sample.z)
			var hw: float = _flame_half_width(d)
			for b in building_manager.buildings:
				if not is_instance_valid(b) or b.health <= 0 \
						or _flamed_buildings.has(b):
					continue
				if b.footprint_distance_to(flat) <= hw:
					_flamed_buildings[b] = true
					b.add_lava_contact(FLAME_CHECK_INTERVAL * FLAME_CONTACT_FACTOR)
	# Trees and wood piles along the centreline (samples overlap enough).
	for i in [0, 2, 4]:
		var d: float = 0.5 + float(i)
		var sample: Vector3 = origin + forward * d
		var radius: float = _flame_half_width(d) + 0.2
		if tree_manager != null:
			tree_manager.ignite_in_radius(sample, radius)
		if wood_pile_manager != null:
			wood_pile_manager.ignite_in_radius(sample, radius)


## Flame half-width at `along` metres in front of the nozzle: fans out linearly
## from FLAME_WIDTH (nozzle) to FLAME_END_WIDTH (range end).
func _flame_half_width(along: float) -> float:
	return lerpf(FLAME_WIDTH * 0.5, FLAME_END_WIDTH * 0.5,
		clampf(along / FIRE_RANGE, 0.0, 1.0))


# --- Visuals (own 3D model, in-game only) -------------------------------------------

func _create_model() -> void:
	var root: Node3D = Node3D.new()
	root.name = "Model"
	add_child(root)
	_model = root

	# User-provided model (assets/models/units/fire_ram.glb) when present;
	# optional named child "Flag" (MeshInstance3D) takes the tribe colour.
	var custom: Node3D = AssetLibrary.instantiate_model("models/units/fire_ram.glb")
	if custom != null:
		root.add_child(custom)
		_flag_mesh = custom.find_child("Flag", true, false) as MeshInstance3D
		_finish_model(root)
		return

	# Placeholder body in its own node so the shrink never touches the flame
	# cone (which must keep showing the real 5 x 2 m flame area).
	var body: Node3D = Node3D.new()
	body.name = "Body"
	body.scale = Vector3.ONE * MODEL_SCALE
	root.add_child(body)

	# Hull (slightly shorter than the catapult).
	var frame: MeshInstance3D = MeshInstance3D.new()
	var frame_box: BoxMesh = BoxMesh.new()
	frame_box.size = Vector3(1.0, 0.4, 1.7)
	frame.mesh = frame_box
	frame.material_override = _mat(C_WOOD)
	frame.position.y = 0.5
	body.add_child(frame)

	# Four wheels.
	for sx in [-0.55, 0.55]:
		for sz in [-0.6, 0.6]:
			var wheel: MeshInstance3D = MeshInstance3D.new()
			var cyl: CylinderMesh = CylinderMesh.new()
			cyl.top_radius = 0.28
			cyl.bottom_radius = 0.28
			cyl.height = 0.14
			wheel.mesh = cyl
			wheel.material_override = _mat(C_WOOD_DARK)
			wheel.rotation.z = PI * 0.5
			wheel.position = Vector3(sx, 0.28, sz)
			body.add_child(wheel)

	# Ram beam pointing forward (+z) with a glowing brazier nozzle at the tip.
	var beam: MeshInstance3D = MeshInstance3D.new()
	var beam_box: BoxMesh = BoxMesh.new()
	beam_box.size = Vector3(0.24, 0.24, 1.6)
	beam.mesh = beam_box
	beam.material_override = _mat(C_WOOD_DARK)
	beam.position = Vector3(0.0, 0.85, 0.7)
	body.add_child(beam)
	var brazier: MeshInstance3D = MeshInstance3D.new()
	var pot: SphereMesh = SphereMesh.new()
	pot.radius = 0.28
	pot.height = 0.56
	brazier.mesh = pot
	var glow: StandardMaterial3D = StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.45, 0.1)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.35, 0.05)
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	brazier.material_override = glow
	brazier.position = Vector3(0.0, 0.85, 1.5)
	body.add_child(brazier)

	# Owner flag (recoloured on takeover).
	var pole: MeshInstance3D = MeshInstance3D.new()
	var pole_cyl: CylinderMesh = CylinderMesh.new()
	pole_cyl.top_radius = 0.03
	pole_cyl.bottom_radius = 0.03
	pole_cyl.height = 1.0
	pole.mesh = pole_cyl
	pole.material_override = _mat(C_WOOD_DARK)
	pole.position = Vector3(0.0, 1.1, -0.7)
	body.add_child(pole)
	_flag_mesh = MeshInstance3D.new()
	var flag_box: BoxMesh = BoxMesh.new()
	flag_box.size = Vector3(0.4, 0.25, 0.03)
	_flag_mesh.mesh = flag_box
	_flag_mesh.position = Vector3(0.2, 1.5, -0.7)
	body.add_child(_flag_mesh)

	_finish_model(root)


## Lazily built flame-cone overlay along local +z while a burst runs
## (model-relative — it turns with the hull automatically).
func _show_flame_cone(show: bool) -> void:
	if not is_inside_tree() or _model == null:
		return
	if _flame_cone == null:
		if not show:
			return
		_flame_cone = Node3D.new()
		_flame_cone.name = "FlameCone"
		var colors: Array[Color] = [
			Color(1.0, 0.85, 0.3, 0.9), Color(1.0, 0.55, 0.08, 0.8),
			Color(0.85, 0.25, 0.05, 0.7)]
		for i in range(3):
			var seg: MeshInstance3D = MeshInstance3D.new()
			seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# Placed in world space each visual tick (_tick_visual) so the beam
			# follows the ground; top_level keeps the parent's Y-rotation/scale out.
			seg.top_level = true
			var box: BoxMesh = BoxMesh.new()
			# Segment widths fan out 2 -> 3 across the beam (matches the collision
			# taper in _flame_half_width): 2.0 / 2.5 / 3.0.
			box.size = Vector3(lerpf(FLAME_WIDTH, FLAME_END_WIDTH, float(i) / 2.0),
				0.5, FIRE_RANGE / 3.0)
			seg.mesh = box
			var mat: StandardMaterial3D = StandardMaterial3D.new()
			mat.albedo_color = colors[i]
			mat.emission_enabled = true
			mat.emission = Color(colors[i].r, colors[i].g * 0.8, 0.05)
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			seg.material_override = mat
			_flame_cone.add_child(seg)
			_flame_segs.append(seg)
		_model.add_child(_flame_cone)
	_flame_cone.visible = show


## Lays the flame beam along the terrain in front of the hull (each segment
## snapped to the ground height and pitched to the slope) plus the width flicker.
func _tick_visual(delta: float) -> void:
	super._tick_visual(delta)
	if not is_inside_tree():
		return
	if _flame_cone == null or not _flame_cone.visible or terrain_data == null:
		return
	var s: float = 0.85 + 0.3 * absf(sin(float(Time.get_ticks_msec()) * 0.02))
	var fwd: Vector3 = Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	var half: float = FIRE_RANGE / 6.0
	for i in range(_flame_segs.size()):
		var d: float = NOZZLE_OFFSET + FIRE_RANGE / 6.0 + FIRE_RANGE / 3.0 * float(i)
		var cx: float = position.x + fwd.x * d
		var cz: float = position.z + fwd.z * d
		var y_back: float = terrain_data.get_height(cx - fwd.x * half, cz - fwd.z * half)
		var y_front: float = terrain_data.get_height(cx + fwd.x * half, cz + fwd.z * half)
		var cy: float = 0.5 * (y_back + y_front) + FLAME_LIFT
		# Pitch the segment along the slope so the segments chain into a beam that
		# runs down/up the hill instead of stepping through it.
		var slope_fwd: Vector3 = Vector3(fwd.x, (y_front - y_back) / (2.0 * half),
			fwd.z).normalized()
		var right: Vector3 = Vector3.UP.cross(slope_fwd).normalized()
		var up: Vector3 = slope_fwd.cross(right).normalized()
		_flame_segs[i].global_transform = Transform3D(
			Basis(right * s, up, slope_fwd), Vector3(cx, cy, cz))
