class_name Unit extends Node3D

## Base class for all units (Brave, Warrior, Firewarrior, Preacher, Shaman).
##
## No physics body: movement walks the NavGrid path via move_toward on the XZ
## plane, Y is snapped from TerrainData every tick. Core logic lives in
## tick(delta) (driven by the UnitManager) so tests can drive it manually
## with artificial deltas, outside the scene tree. Uses local `position`
## (units are direct children of UnitManager at the origin, so local == global
## and it also works outside the tree).
##
## Units have NO visual children: all units are drawn by the central
## UnitRenderer (one MultiMesh draw call). The unit only keeps its animation
## state (anim_base_name + anim_start_ms) and render cache fields.

## Later phases fill in the behaviour for GATHER/PRAY/BUILD/PANIC/CAST/THROWN.
## SIT = pacified by an enemy preacher (conversion, 5c); ROLL = tumbling
## downhill / knocked over (5d).
enum State {IDLE, MOVE, GATHER, PRAY, BUILD, ATTACK, TRAIN, PANIC, CAST, THROWN, DEAD, SIT, ROLL}

signal died(unit: Unit)
## Fired after this unit switched tribes (preacher conversion) — the
## UnitManager refreshes the renderer's instance colour.
signal converted(unit: Unit)
## Fired once when the corpse has finished fading; the UnitManager then removes
## and frees the node.
signal corpse_expired(unit: Unit)
signal state_changed(unit: Unit, new_state: State)

const TRIBE_COLORS: Array[Color] = [
	Color(0.35, 0.55, 1.0),   # 0 = player (blue)
	Color(1.0, 0.3, 0.25),    # 1 = AI (red)
	Color(1.0, 0.9, 0.35),
	Color(0.4, 0.9, 0.45),
]

const ARRIVE_EPS: float = 0.05       # metres: waypoint counts as reached

# --- Melee combat tuning (phase 5b) -------------------------------------------
## Distance at which a unit can land a melee hit on its target.
const MELEE_RANGE: float = 1.2
## Attackers pursue direct (no A*) once this close; farther away they path.
const COMBAT_DIRECT_RANGE: float = 2.5
## Combat units auto-attack enemies within this radius while idle. Braves do NOT
## (they only retaliate when attacked — see _maybe_retaliate).
const AGGRO_RADIUS: float = 8.0
## Fleeing (passive move while being hit in melee): every this many hits the
## unit falls back into fighting (self-defence) — escaping a brawl works, but
## not always on the first try. Deterministic, not per-frame random.
const FLEE_RETALIATE_HITS: int = 3
## An attacker counts as "in melee" for the flee rule within this range.
const FLEE_MELEE_RANGE: float = MELEE_RANGE * 1.5
## Seconds between melee strikes.
const ATTACK_COOLDOWN: float = 0.8
## Base target (re)search interval; a small per-unit offset staggers the scans
## so they never all fire on the same frame (never per-frame — see _due_to_scan).
const TARGET_SEARCH_INTERVAL: float = 0.25
## Max candidate units one enemy scan examines (crowd cost cap).
const SCAN_MAX_CANDIDATES: int = 24
## Max simultaneous melee attackers on one target; extras wait and back-fill.
const MAX_MELEE_ATTACKERS: int = 3
## Radius of the ring the (up to 3) attackers stand on around their target.
const MELEE_SLOT_RADIUS: float = 0.9
## Radius overflow attackers wait on around the target until a slot frees.
const MELEE_WAIT_RADIUS: float = 1.7

## Damage per attack kind (Tuning-Defaults, phase 8 adjustable). The kind is
## rolled per strike; the warrior scales all of these by melee_strength().
const MELEE_PUNCH: int = 6
const MELEE_KICK: int = 8
const MELEE_SHOVE: int = 3
## Chance of a kick / shove on any given strike (else punch). The warrior
## overrides _shove_chance() to shove rarely (he punches/kicks instead).
const KICK_CHANCE: float = 0.2
const SHOVE_CHANCE: float = 0.15
## Fireball impact damage (slightly above a brave punch; thrown by the
## firewarrior from medium range, see Firewarrior/Fireball).
const FIREBALL_DAMAGE: int = 7

## When an attack target sits down under a preacher's spell, its attackers
## break off — only this chance (rolled ONCE per attacker per sitting spell)
## keeps one fighting.
const SIT_ATTACK_CONTINUE_CHANCE: float = 0.05

## A defeated unit stays lying on the ground (dead sprite, no interaction) for
## this long, then dissolves over CORPSE_FADE_DURATION and is removed.
const CORPSE_DURATION: float = 5.0
const CORPSE_FADE_DURATION: float = 1.0

# --- Knockback (fireball, phase 5c; weakened in 5d for the roll chance) ---------
## Shove distance of a single un-stacked fireball hit (metres)...
const KNOCKBACK_BASE: float = 0.35
## ...plus this much extra per accumulated stack: rapid successive hits shove
## progressively harder (the accumulator decays over time).
const KNOCKBACK_STACK_BONUS: float = 0.25
## How fast the pending displacement is played out (m/s).
const KNOCKBACK_SPEED: float = 10.0
## Accumulator stacks lost per second.
const KNOCKBACK_ACCUM_DECAY: float = 0.8

# --- Rolling (phase 5d) ----------------------------------------------------------
## Ground speed while rolling (slope adds a bit on top).
const ROLL_SPEED: float = 5.5
## Duration of a flat-ground mini roll (shove / fireball knock-over).
const MINI_ROLL_DURATION: float = 0.35
## Even shorter tumble for adjacent units knocked over by a fireball roll.
const NEIGHBOR_ROLL_DURATION: float = 0.22
## Rolling hurts a little, scaling with how long it lasts.
const ROLL_DPS: float = 5.0
## The roll keeps following the fall line while the downhill slope exceeds
## this; on flatter ground it ends once the (mini) duration ran out.
const ROLL_END_SLOPE: float = 0.5
## Walking DOWN a slope steeper than this may trigger a roll on its own...
const STEEP_ROLL_SLOPE: float = 1.0
## ...with this chance per second.
const STEEP_ROLL_CHANCE_PER_SEC: float = 0.6

# --- Throw & panic (phase 6) ---------------------------------------------------------
## Gravity of scripted throw arcs (slightly snappy for gameplay feel).
const THROW_GRAVITY: float = 18.0
## Friction (m/s^2) that bleeds off a landing throw's roll speed on flat
## ground — thrown units tumble on and quickly come to a stop.
const ROLL_FRICTION: float = 6.0
## A speed-driven roll may end once its momentum decayed below this.
const ROLL_STOP_SPEED: float = 1.0
## Panic effect duration (swarm) and how often a new flee direction is picked.
const PANIC_DURATION: float = 6.0
const PANIC_REDIRECT_INTERVAL: float = 0.5

# --- Melee shove (phase 5d) --------------------------------------------------------
## A shove always displaces the target slightly (the brawl shifts around)...
const SHOVE_DISPLACE: float = 0.35
## ...and sometimes knocks it over into a very short roll, even on flat ground.
const SHOVE_ROLL_CHANCE: float = 0.2

# --- Hill movement (phase 5d) ------------------------------------------------------
## Speed factor lost per unit of uphill slope (rise per metre)...
const UPHILL_SLOWDOWN: float = 0.45
## ...clamped so steep climbs stay possible.
const MIN_SPEED_FACTOR: float = 0.35

# --- Regeneration (phase 5d) ---------------------------------------------------------
## Seconds without ANY combat involvement (dealt/received damage, rolling)
## before slow healing starts.
const REGEN_DELAY: float = 8.0
const REGEN_RATE: float = 2.0   # HP per second

# --- Stars overlay (phase 5d) -------------------------------------------------------
## Damage taken within STARS_WINDOW seconds that triggers the circling stars.
## (HP is NEVER shown — the stars are the only damage feedback.)
const STARS_DAMAGE_THRESHOLD: int = 12
const STARS_WINDOW: float = 1.0
const STARS_DURATION_MS: int = 1500

var tribe_id: int = 0
## Owning tribe, injected by UnitManager.spawn_unit()/Tribe.add_unit().
var tribe: Tribe = null
var max_health: int = 100
var health: int = 100
var speed: float = 4.0
var state: State = State.IDLE
var waypoint_queue: Array[Vector3] = []
var patrol: bool = false
## Move mode of the current route: aggressive (attack-move — combatants engage
## enemies they pass) or passive (plain move/flee: march through, only the
## throttled flee rule pulls the unit back into a fight). Set by order_move.
var move_aggressive: bool = false
## Melee hits taken while fleeing (passive move); see FLEE_RETALIATE_HITS.
var _flee_hits: int = 0
## Seconds spent in the current IDLE stretch (reset on every state change);
## drives the idle regrouping into 6-packs (UnitManager, phase 7b).
var idle_seconds: float = 0.0
## The idle 6-pack this unit belongs to (UnitManager.IdleGroup, untyped for
## freed-safety). Membership is STICKY — members never hop between groups;
## the manager's prune drops them when they leave/are ordered away.
var idle_group: RefCounted = null
## Auto-attack radius while idling for NON-combatants (0 = fully passive).
## A FIELD, not a virtual getter — this sits in the per-unit per-tick hot
## path, and one extra virtual call costs ~5 ms/tick with 4000 units. The
## brave sets its small 3 m guard radius in _init; the shaman stays 0.
var idle_aggro: float = 0.0
## Separation passes this unit spent tightly stacked inside another unit;
## past a threshold the UnitManager sends it to a free nearby cell.
var overlap_ticks: int = 0
## Visual-only: the sprite bounces (used by braves flattening terrain).
var hop_visual: bool = false

## Movement direction on the XZ plane (kept when the unit stops); drives the
## choice of the four sprite views. Default: facing the camera side (south).
var facing: Vector3 = Vector3(0, 0, 1)

## Injected by UnitManager.spawn_unit() (or directly by tests).
var terrain_data: TerrainData = null
var nav_grid: NavGrid = null
## When set (in-game), order_move paths are computed via the manager's path
## queue (spread over frames) instead of synchronously — 500 simultaneous
## move orders would otherwise stall a frame with 500 A* runs. Tests leave
## this null and get the old synchronous behaviour.
var path_service: UnitManager = null

var selected: bool = false

## Animation state, consumed by the UnitRenderer: base name (idle/walk/...)
## and the start time for frame timing.
var anim_base_name: StringName = &"idle"
var anim_start_ms: int = 0

## Current spatial-hash cell, managed by the UnitManager (stored on the unit
## because a Dictionary lookup per unit per tick is measurably slower).
var _hash_cell: Vector2i = Vector2i(2147483647, 2147483647)

## Render slot bookkeeping, managed by the UnitRenderer.
var _render_index: int = -1
var _render_kind: StringName = &"unit"
var _render_pos: Vector3 = Vector3.INF
var _render_frame: int = -1

var _path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0
## Queued move target awaiting path computation (INF = none).
var _pending_target: Vector3 = Vector3.INF
var _path_queued: bool = false

# --- Combat state (phase 5b) --------------------------------------------------
## Enemy this unit is meleeing (null = none). Typed, but every read is guarded
## with is_instance_valid — the target may be freed by another attacker.
var attack_target: Unit = null
## Units currently meleeing THIS unit (max MAX_MELEE_ATTACKERS get a slot).
## Untyped on purpose: entries may be freed, and binding a freed instance to a
## typed parameter raises a script error (see Brave._tree_valid rationale).
var melee_attackers: Array = []
## Count of units committed to attacking this one (targeting it, whether or not
## they hold a slot yet). Drives 1v1 target preference even before contact.
var incoming_attackers: int = 0
## Last unit that damaged this one (drives brave retaliation).
var last_attacker: Unit = null
var _attack_cooldown: float = 0.0
var _target_search_timer: float = 0.0
## True on ticks where the unit is in range and striking (vs. still approaching);
## drives the attack-vs-walk animation in _anim_base().
var _in_melee: bool = false
## Animation base of the current strike (punch/kick/shove — set per rolled
## attack kind in _do_strike; the firewarrior sets "throw" while firing).
var attack_anim: StringName = &"punch"
## Target this attacker rolled "keep fighting although it sits" for (untyped:
## may be freed) — the 5% roll happens once per sitting spell, not per tick.
var _sit_decision_target = null
## Cached A* goal while approaching a target (replanned when it drifts).
var _combat_goal: Vector3 = Vector3.INF
## Corpse decay: seconds since death; corpse_expired fires once at the end.
var _corpse_timer: float = 0.0
var _corpse_done: bool = false
## Instance alpha last written to the renderer (corpse fade), managed there.
var _render_alpha: float = 1.0

# --- Knockback state (fireball, phase 5c) ---------------------------------------
## Hit-density accumulator: +1 per fireball hit, decays over time; scales the
## shove distance of follow-up hits (salvos throw harder).
var knockback_accum: float = 0.0
## Pending displacement, played out at KNOCKBACK_SPEED in _tick_knockback.
var _knockback_remaining: Vector3 = Vector3.ZERO

# --- Conversion state (preacher, phase 5c) ---------------------------------------
## Enemy preacher currently pacifying this unit (untyped: may be freed).
var converting_preacher = null
var conversion_progress: float = 0.0
var conversion_time: float = 0.0

# --- Roll state (phase 5d) ---------------------------------------------------------
var roll_dir: Vector3 = Vector3.ZERO
var _roll_time: float = 0.0
var _roll_min_time: float = 0.0
var _roll_damage_frac: float = 0.0
## Momentum of a throw-landing roll (0 = plain constant-speed roll).
var _roll_init_speed: float = 0.0

# --- Throw / panic state (phase 6) ----------------------------------------------------
var _throw_velocity: Vector3 = Vector3.ZERO
var _throw_fall_damage: int = 0
## While set (untyped: may be freed), an external carrier (the tornado)
## controls this thrown unit's position; _tick_thrown idles until the carrier
## releases it via fling_from_carry.
var throw_carrier = null
## Position the panicked unit flees from (the swarm).
var panic_source: Vector3 = Vector3.ZERO
var _panic_time: float = 0.0
var _panic_redirect: float = 0.0

# --- Regeneration / stars state (phase 5d) --------------------------------------------
## Seconds since the last combat involvement; regen starts past REGEN_DELAY.
var _no_combat_timer: float = 0.0
var _regen_frac: float = 0.0
## Stars overlay visible until this tick-time (see has_stars()).
var stars_until_ms: int = 0
## Damage taken recently (decays over STARS_WINDOW).
var _recent_damage: float = 0.0
## Cached Events bus (combat_hit emissions), resolved once when in-tree.
var _events_node: Node = null
var _events_checked: bool = false


## Silhouette key for PlaceholderSprites; overridden by subclasses.
func unit_kind() -> StringName:
	return &"unit"


## True for units that seek out enemies on their own while idle (Warrior/
## Firewarrior/Preacher). Braves are false: they only retaliate when hit.
func _is_combatant() -> bool:
	return false


## Melee damage multiplier (Warrior returns 3.0; everyone else brawls at 1.0).
func melee_strength() -> float:
	return 1.0


## Probability that a strike is a shove (low-damage, can trigger a downhill roll
## in phase 5d). The warrior overrides this to shove rarely.
func _shove_chance() -> float:
	return SHOVE_CHANCE


## Hook called when combat overrides the current activity — Brave uses it to
## release its worker claims before it starts fighting.
func _on_combat_interrupt() -> void:
	pass


# --- Core logic (testable without scene tree) ---------------------------------

func tick(delta: float) -> void:
	_tick_knockback(delta)
	_tick_regen(delta)
	_tick_state(delta)
	_apply_animation(false)


## State dispatch; subclasses override this (NOT tick) so cross-state systems
## like knockback and regeneration keep running for them too.
func _tick_state(delta: float) -> void:
	match state:
		State.MOVE:
			_tick_move(delta)
		State.ATTACK:
			_tick_attack(delta)
		State.IDLE:
			_tick_idle(delta)
		State.SIT:
			_tick_sit(delta)
		State.ROLL:
			_tick_roll(delta)
		State.THROWN:
			_tick_thrown(delta)
		State.PANIC:
			_tick_panic(delta)
		State.DEAD:
			_tick_dead(delta)
		_:
			pass


func _tick_move(delta: float) -> void:
	if _pending_target != Vector3.INF:
		return  # waiting for the path queue
	# Attack-move: combat units engage enemies they pass on the way. A plain
	# (passive) move marches through — fleeing a fight is possible; only the
	# flee rule (_maybe_retaliate) can pull the unit back in.
	if move_aggressive and _is_combatant() and _engage_on_sight(delta):
		return
	if _advance_path(delta):
		_on_path_finished()


## Walks one step along the current path (also used by Brave sub-states that
## are not State.MOVE). Returns true when the path is exhausted. Uphill slopes
## slow the step down; very steep DOWNHILL stretches can knock the unit into a
## roll (phase 5d).
func _advance_path(delta: float) -> bool:
	if _path_index >= _path.size():
		return true
	var target: Vector3 = _path[_path_index]
	var flat_pos: Vector2 = Vector2(position.x, position.z)
	var flat_target: Vector2 = Vector2(target.x, target.z)
	var to_target: Vector2 = flat_target - flat_pos
	if to_target.length_squared() > 0.000001:
		facing = Vector3(to_target.x, 0.0, to_target.y).normalized()
	var slope: float = _slope_ahead(to_target)
	if slope < -STEEP_ROLL_SLOPE and randf() < STEEP_ROLL_CHANCE_PER_SEC * delta:
		start_roll(Vector3(to_target.x, 0.0, to_target.y), MINI_ROLL_DURATION)
		return false
	var next: Vector2 = flat_pos.move_toward(flat_target, _slope_speed(slope) * delta)
	position.x = next.x
	position.z = next.y
	_snap_to_ground()
	if next.distance_to(flat_target) <= ARRIVE_EPS:
		_path_index += 1
	return _path_index >= _path.size()


## Terrain slope (rise per metre) a short step ahead along move_dir; negative
## = downhill. 0 without terrain (tests) or when standing still.
func _slope_ahead(move_dir: Vector2) -> float:
	if terrain_data == null or move_dir.length_squared() < 0.000001:
		return 0.0
	var d: Vector2 = move_dir.normalized()
	var ahead: float = 0.6
	var h0: float = terrain_data.get_height(position.x, position.z)
	var h1: float = terrain_data.get_height(
		position.x + d.x * ahead, position.z + d.y * ahead)
	return (h1 - h0) / ahead


## Effective speed for a given slope: full speed on flat/downhill, slowed
## (clamped) while climbing.
func _slope_speed(slope: float) -> float:
	if slope <= 0.0:
		return speed
	return speed * clampf(1.0 - slope * UPHILL_SLOWDOWN, MIN_SPEED_FACTOR, 1.0)


func _has_path() -> bool:
	return _path_index < _path.size()


func _clear_path() -> void:
	_path = PackedVector3Array()
	_path_index = 0


func _snap_to_ground() -> void:
	if terrain_data != null:
		position.y = terrain_data.get_height(position.x, position.z)


func _on_path_finished() -> void:
	if waypoint_queue.is_empty():
		_set_state(State.IDLE)
		return
	if patrol:
		# Rotate the queue: the reached waypoint goes to the back.
		waypoint_queue.append(waypoint_queue.pop_front())
		_start_path_to(waypoint_queue[0])
	else:
		waypoint_queue.pop_front()
		if waypoint_queue.is_empty():
			_set_state(State.IDLE)
		else:
			_start_path_to(waypoint_queue[0])


# --- Orders --------------------------------------------------------------------

## While pacified by an enemy preacher (SIT) the unit accepts NO orders at all —
## it stays sitting until the preacher is attacked (priest duel), interrupted
## (fireball reset, out of range, death) or the conversion completes. Rolling,
## airborne (thrown) and panicking units are equally beyond control.
func can_take_orders() -> bool:
	return state != State.SIT and state != State.DEAD and state != State.ROLL \
		and state != State.THROWN and state != State.PANIC


## Move order. queue_up appends the target as an additional waypoint
## (Shift+right-click), otherwise the current route is replaced. `aggressive`
## selects attack-move (engage enemies on the way) vs. plain move (default —
## also the flee order: breaks off the current fight).
func order_move(target: Vector3, queue_up: bool = false, aggressive: bool = false) -> void:
	if not can_take_orders():
		return
	_end_attack()
	move_aggressive = aggressive
	_flee_hits = 0
	if not queue_up:
		waypoint_queue.clear()
		waypoint_queue.append(target)
		_start_path_to(target)
		return
	waypoint_queue.append(target)
	if state != State.MOVE:
		_start_path_to(waypoint_queue[0])


func _start_path_to(target: Vector3) -> void:
	if path_service != null:
		# Defer to the manager's path queue (spread over frames).
		_pending_target = target
		_clear_path()
		if not _path_queued:
			_path_queued = true
			path_service.request_path(self)
		_set_state(State.MOVE)
		return
	if not _plan_path_to(target):
		# Unreachable: drop the waypoint and stop.
		if not waypoint_queue.is_empty():
			waypoint_queue.pop_front()
		_set_state(State.IDLE)
		return
	_set_state(State.MOVE)


## Called by the UnitManager when this unit's queued path request is due.
func _resolve_pending_path() -> void:
	_path_queued = false
	if _pending_target == Vector3.INF:
		return
	var target: Vector3 = _pending_target
	_pending_target = Vector3.INF
	if state != State.MOVE:
		return  # order was superseded while waiting
	if not _plan_path_to(target):
		if not waypoint_queue.is_empty():
			waypoint_queue.pop_front()
		_set_state(State.IDLE)


## Computes and stores a path without touching the state (Brave sub-states
## use this too). Returns false if the target is unreachable.
func _plan_path_to(target: Vector3) -> bool:
	var path: PackedVector3Array
	if nav_grid != null:
		path = nav_grid.find_path(position, target)
	else:
		path = PackedVector3Array([target])
	if path.is_empty():
		return false
	_path = path
	_path_index = 0
	return true


## Directly injects a path (used by tests and by order handling).
func set_path(path: PackedVector3Array) -> void:
	_pending_target = Vector3.INF  # cancel any queued request
	_path = path
	_path_index = 0
	if _path.is_empty():
		_set_state(State.IDLE)
	else:
		_set_state(State.MOVE)


## Not-yet-walked part of the current path (for route visualisation).
func get_remaining_path() -> PackedVector3Array:
	var points: PackedVector3Array = PackedVector3Array()
	if state != State.MOVE:
		return points
	for i in range(_path_index, _path.size()):
		points.append(_path[i])
	return points


## True while this unit generates the prayer mana bonus (Brave overrides).
func is_praying() -> bool:
	return false


# --- Combat (phase 5b) --------------------------------------------------------

## Applies damage. `attacker` (untyped: may be a freed instance) drives brave
## retaliation. Lethal damage runs the combat cleanup and marks the unit DEAD;
## the UnitManager deregisters it via the died signal. While ROLLing, death is
## DEFERRED: the unit only dies once the roll ends (plan 5d).
func take_damage(amount: int, attacker = null) -> void:
	if state == State.DEAD:
		return
	health -= amount
	_no_combat_timer = 0.0
	_register_damage_for_stars(amount)
	if attacker != null and is_instance_valid(attacker):
		last_attacker = attacker
	if health <= 0:
		if state == State.ROLL:
			return   # deferred: _end_roll finishes it
		health = 0
		_die()
		return
	_maybe_retaliate(attacker)


func _die() -> void:
	# Release our own slot, then tell everyone attacking us to look elsewhere so
	# waiting attackers can back-fill onto a fresh target.
	_end_attack()
	for a in melee_attackers.duplicate():
		if is_instance_valid(a):
			a._on_target_died(self)
	melee_attackers.clear()
	# Corpse setup: no selection ring, no route, no hopping, no stars — the unit
	# stays in the world as a lying "dead" sprite until the decay timer removes it.
	selected = false
	hop_visual = false
	stars_until_ms = 0
	waypoint_queue.clear()
	_clear_path()
	_corpse_timer = 0.0
	_set_state(State.DEAD)
	died.emit(self)


## Corpse decay: lie for CORPSE_DURATION, fade over CORPSE_FADE_DURATION (the
## renderer reads corpse_alpha()), then fire corpse_expired exactly once.
func _tick_dead(delta: float) -> void:
	if _corpse_done:
		return
	_corpse_timer += delta
	if _corpse_timer >= CORPSE_DURATION + CORPSE_FADE_DURATION:
		_corpse_done = true
		corpse_expired.emit(self)


## 1.0 while the corpse lies, then a linear fade to 0.0.
func corpse_alpha() -> float:
	if state != State.DEAD:
		return 1.0
	return clampf(
		1.0 - (_corpse_timer - CORPSE_DURATION) / CORPSE_FADE_DURATION, 0.0, 1.0)


# --- Knockback (fireball, phase 5c) ----------------------------------------------

## Small instant displacement along dir (played out via the knockback system);
## used by fireball knockback and melee shoves.
func displace(dir: Vector3, dist: float) -> void:
	if state == State.DEAD:
		return
	var flat: Vector3 = Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.000001:
		return
	_knockback_remaining += flat.normalized() * dist


## Fireball knockback: the hit-density accumulator makes rapid successive hits
## shove progressively harder; it decays in _tick_knockback.
func apply_knockback(dir: Vector3) -> void:
	if state == State.DEAD:
		return
	var dist: float = KNOCKBACK_BASE + knockback_accum * KNOCKBACK_STACK_BONUS
	knockback_accum += 1.0
	displace(dir, dist)


## Plays out pending knockback displacement and decays the accumulator. Runs
## for every state except DEAD (a shove interrupts nothing by itself).
func _tick_knockback(delta: float) -> void:
	if knockback_accum > 0.0:
		knockback_accum = maxf(knockback_accum - KNOCKBACK_ACCUM_DECAY * delta, 0.0)
	if _knockback_remaining == Vector3.ZERO or state == State.DEAD:
		return
	var step_len: float = minf(KNOCKBACK_SPEED * delta, _knockback_remaining.length())
	var step: Vector3 = _knockback_remaining.normalized() * step_len
	_knockback_remaining -= step
	if _knockback_remaining.length_squared() < 0.0001:
		_knockback_remaining = Vector3.ZERO
	var nx: float = position.x + step.x
	var nz: float = position.z + step.z
	# Never shove anyone into water/obstacles (overview risk 6).
	if nav_grid != null and not nav_grid.is_cell_walkable(
			nav_grid.world_to_cell(Vector3(nx, 0.0, nz))):
		_knockback_remaining = Vector3.ZERO
		return
	position.x = nx
	position.z = nz
	_snap_to_ground()


# --- Rolling (phase 5d) --------------------------------------------------------------

## Starts (or extends) a roll along `dir`. Mini rolls on flat ground end after
## `duration`; on steep slopes the roll follows the fall line downhill until
## the ground flattens. `initial_speed` > 0 gives the roll momentum (throw
## landings) that bleeds off via ROLL_FRICTION — the unit tumbles on and only
## stands up once slow. Rolling suspends all orders and separation; rolling
## into water kills instantly; roll damage kills only at the roll's end.
func start_roll(dir: Vector3, duration: float = MINI_ROLL_DURATION,
		initial_speed: float = 0.0) -> void:
	if state == State.DEAD:
		return
	var flat: Vector3 = Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() > 0.000001:
		roll_dir = flat.normalized()
	elif roll_dir == Vector3.ZERO:
		roll_dir = facing
	_no_combat_timer = 0.0
	if state == State.ROLL:
		# Another hit while tumbling (e.g. a follow-up fireball): extend.
		_roll_min_time = maxf(_roll_min_time, _roll_time + duration)
		_roll_init_speed = maxf(_roll_init_speed, initial_speed)
		return
	_on_combat_interrupt()
	_end_attack()
	converting_preacher = null
	conversion_progress = 0.0
	waypoint_queue.clear()
	_clear_path()
	hop_visual = false
	_roll_time = 0.0
	_roll_min_time = duration
	_roll_damage_frac = 0.0
	_roll_init_speed = initial_speed
	_set_state(State.ROLL)


func _tick_roll(delta: float) -> void:
	_roll_time += delta
	# Rolling into water is instant death (no deferral).
	if terrain_data != null and terrain_data.get_height(position.x, position.z) \
			<= TerrainData.SEA_LEVEL + 0.05:
		health = 0
		_die()
		return
	# Follow the fall line while the ground is steep.
	var down: Vector3 = _downhill_vector()
	var slope: float = down.length()
	if slope > ROLL_END_SLOPE:
		roll_dir = down.normalized()
	# Momentum rolls (throw landings) use their decaying speed instead of the
	# constant tumble speed.
	var speed_now: float = ROLL_SPEED
	if _roll_init_speed > 0.0:
		speed_now = _roll_init_speed
		_roll_init_speed = maxf(_roll_init_speed - ROLL_FRICTION * delta, 0.0)
	var step: float = speed_now * (1.0 + slope * 0.4) * delta
	var nx: float = position.x + roll_dir.x * step
	var nz: float = position.z + roll_dir.z * step
	# Buildings stop the roll; steep/unwalkable open ground is rolled across.
	if nav_grid != null and nav_grid.is_cell_blocked_by_building(
			nav_grid.world_to_cell(Vector3(nx, 0.0, nz))):
		_end_roll()
		return
	position.x = nx
	position.z = nz
	facing = roll_dir
	_snap_to_ground()
	# Rolling hurts over time; death is deferred to the roll's end.
	_roll_damage_frac += ROLL_DPS * delta
	if _roll_damage_frac >= 1.0:
		var dmg: int = int(_roll_damage_frac)
		_roll_damage_frac -= float(dmg)
		health -= dmg
	if slope <= ROLL_END_SLOPE and _roll_time >= _roll_min_time \
			and _roll_init_speed <= ROLL_STOP_SPEED:
		_end_roll()


## Lands the unit: clamp onto a walkable cell (overview risk 6), then either
## die (deferred roll damage) or get back up.
func _end_roll() -> void:
	if nav_grid != null:
		var cell: Vector2i = nav_grid.world_to_cell(position)
		if not nav_grid.is_cell_walkable(cell):
			var near: Vector2i = nav_grid.nearest_walkable_cell(cell)
			if near.x >= 0:
				var w: Vector3 = nav_grid.cell_to_world(near)
				position.x = w.x
				position.z = w.z
	_snap_to_ground()
	if health <= 0:
		health = 0
		_die()
		return
	_set_state(State.IDLE)


# --- Throw (phase 6) --------------------------------------------------------------------

## Launches the unit into a scripted arc (State.THROWN: no Y snapping, no
## orders, no separation). `velocity` is the initial world velocity (Y up).
## On landing the unit takes `fall_damage`, then tumbles on with the throw's
## horizontal speed (momentum roll) until it decays; landing or rolling into
## water kills instantly. Another throw mid-flight stacks onto the velocity.
func throw_airborne(velocity: Vector3, fall_damage: int = 0) -> void:
	if state == State.DEAD:
		return
	if state == State.THROWN:
		_throw_velocity += velocity
		_throw_fall_damage = maxi(_throw_fall_damage, fall_damage)
		return
	_on_combat_interrupt()
	_end_attack()
	converting_preacher = null
	conversion_progress = 0.0
	waypoint_queue.clear()
	_clear_path()
	hop_visual = false
	_no_combat_timer = 0.0
	_throw_velocity = velocity
	_throw_fall_damage = fall_damage
	_set_state(State.THROWN)


func _tick_thrown(delta: float) -> void:
	if throw_carrier != null:
		if is_instance_valid(throw_carrier):
			return   # the carrier moves us
		throw_carrier = null   # carrier vanished mid-air: fall from here
	_throw_velocity.y -= THROW_GRAVITY * delta
	position += _throw_velocity * delta
	var flat: Vector3 = Vector3(_throw_velocity.x, 0.0, _throw_velocity.z)
	if flat.length_squared() > 0.000001:
		facing = flat.normalized()
	var ground: float = 0.0
	if terrain_data != null:
		ground = terrain_data.get_height(position.x, position.z)
	if position.y > ground and _throw_velocity.y > 0.0:
		return
	if position.y > ground:
		return   # still falling
	position.y = ground
	_land_from_throw(ground)


## The carrier (tornado) flings the carried unit away: it resumes the normal
## throw arc with the given velocity (fall damage was set at capture).
func fling_from_carry(velocity: Vector3) -> void:
	if state != State.THROWN:
		return
	throw_carrier = null
	_throw_velocity = velocity


## Landing: water kills instantly; building footprints are snapped out of;
## fall damage applies, then the momentum roll takes over.
func _land_from_throw(ground: float) -> void:
	var fall_damage: int = _throw_fall_damage
	_throw_fall_damage = 0
	var momentum: Vector3 = Vector3(_throw_velocity.x, 0.0, _throw_velocity.z)
	_throw_velocity = Vector3.ZERO
	if terrain_data != null and ground <= TerrainData.SEA_LEVEL + 0.05:
		health = 0
		_die()
		return
	if nav_grid != null:
		var cell: Vector2i = nav_grid.world_to_cell(position)
		if nav_grid.is_cell_blocked_by_building(cell):
			var near: Vector2i = nav_grid.nearest_walkable_cell(cell)
			if near.x >= 0:
				var wpos: Vector3 = nav_grid.cell_to_world(near)
				position.x = wpos.x
				position.z = wpos.z
	_snap_to_ground()
	if fall_damage > 0:
		take_damage(fall_damage)
		if state == State.DEAD:
			return
	start_roll(momentum, MINI_ROLL_DURATION, momentum.length())


# --- Panic (phase 6) --------------------------------------------------------------------

## Panics the unit (swarm effect): it flees in randomly changing directions
## away from `source_pos`, accepts no orders and does not fight back, until
## the effect runs out. Re-panicking refreshes the timer. Shamans are immune;
## thrown/rolling units finish their tumble first.
func start_panic(source_pos: Vector3, duration: float = PANIC_DURATION) -> void:
	if state == State.DEAD or state == State.THROWN or state == State.ROLL:
		return
	if is_panic_immune():
		return
	panic_source = source_pos
	if state == State.PANIC:
		_panic_time = maxf(_panic_time, duration)
		return
	_on_combat_interrupt()
	_end_attack()
	converting_preacher = null
	conversion_progress = 0.0
	waypoint_queue.clear()
	_clear_path()
	hop_visual = false
	_panic_time = duration
	_panic_redirect = 0.0
	_set_state(State.PANIC)


func _tick_panic(delta: float) -> void:
	_panic_time -= delta
	if _panic_time <= 0.0:
		_clear_path()
		_set_state(State.IDLE)
		return
	_panic_redirect -= delta
	if _panic_redirect <= 0.0 or not _has_path():
		_panic_redirect = PANIC_REDIRECT_INTERVAL + randf() * 0.3
		_pick_panic_target()
	_advance_path(delta)


## Short random flight hop, biased away from the panic source; clamped onto a
## walkable cell (direct waypoint, no A* — panic is headless scrambling).
func _pick_panic_target() -> void:
	var away: Vector3 = Vector3(
		position.x - panic_source.x, 0.0, position.z - panic_source.z)
	var base_angle: float
	if away.length_squared() > 0.01:
		base_angle = atan2(away.z, away.x)
	else:
		base_angle = randf() * TAU
	var angle: float = base_angle + randf_range(-1.2, 1.2)
	var dist: float = randf_range(2.0, 4.0)
	var target: Vector3 = position + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	if nav_grid != null:
		var cell: Vector2i = nav_grid.world_to_cell(target)
		if not nav_grid.is_cell_walkable(cell):
			var near: Vector2i = nav_grid.nearest_walkable_cell(cell)
			if near.x < 0:
				return
			target = nav_grid.cell_to_world(near)
	elif terrain_data != null:
		target.y = terrain_data.get_height(target.x, target.z)
	_path = PackedVector3Array([target])
	_path_index = 0


## Downhill direction at the current position; the vector length is the slope
## (rise per metre). ZERO without terrain.
func _downhill_vector() -> Vector3:
	if terrain_data == null:
		return Vector3.ZERO
	var e: float = 0.5
	var dx: float = terrain_data.get_height(position.x + e, position.z) \
		- terrain_data.get_height(position.x - e, position.z)
	var dz: float = terrain_data.get_height(position.x, position.z + e) \
		- terrain_data.get_height(position.x, position.z - e)
	return Vector3(-dx / (2.0 * e), 0.0, -dz / (2.0 * e))


# --- Regeneration & stars (phase 5d) ---------------------------------------------------

## Counts combat-free time and slowly heals past REGEN_DELAY; also decays the
## recent-damage window for the stars overlay. Rolling counts as combat.
func _tick_regen(delta: float) -> void:
	if _recent_damage > 0.0:
		_recent_damage = maxf(
			_recent_damage - float(STARS_DAMAGE_THRESHOLD) * delta / STARS_WINDOW, 0.0)
	if state == State.DEAD:
		return
	if state == State.ROLL or state == State.THROWN:
		_no_combat_timer = 0.0
		return
	_no_combat_timer += delta
	if _no_combat_timer < REGEN_DELAY or health >= max_health:
		return
	_regen_frac += REGEN_RATE * delta
	if _regen_frac >= 1.0:
		var heal: int = int(_regen_frac)
		_regen_frac -= float(heal)
		health = mini(health + heal, max_health)


## Heavy damage in a short window triggers the circling stars above the head
## (drawn by the StarsRenderer; HP itself is never shown).
func _register_damage_for_stars(amount: int) -> void:
	_recent_damage += float(amount)
	if _recent_damage >= float(STARS_DAMAGE_THRESHOLD):
		stars_until_ms = Time.get_ticks_msec() + STARS_DURATION_MS
		_recent_damage = 0.0


func has_stars() -> bool:
	return state != State.DEAD and Time.get_ticks_msec() < stars_until_ms


# --- Conversion (preacher, phase 5c) ----------------------------------------------

## Shamans and preachers can never be converted (original rule).
func is_conversion_immune() -> bool:
	return unit_kind() == &"shaman" or unit_kind() == &"preacher"


## Shamans are immune to the swarm's panic effect (phase 6, Shaman overrides).
func is_panic_immune() -> bool:
	return false


## Pacified by an enemy preacher: stop everything and sit down. The conversion
## completes after `duration` seconds of uninterrupted channeling (_tick_sit).
## Returns false when this unit cannot be converted.
func begin_conversion(preacher: Unit, duration: float) -> bool:
	if state == State.DEAD or state == State.SIT or is_conversion_immune():
		return false
	_on_combat_interrupt()
	_end_attack()
	waypoint_queue.clear()
	_clear_path()
	converting_preacher = preacher
	conversion_time = maxf(duration, 0.1)
	conversion_progress = 0.0
	_set_state(State.SIT)
	return true


## Sitting under a preacher's spell: progress while the preacher keeps
## channeling in range; stand up when the spell breaks. If the preacher got
## drawn into a fight (priest duel), the released units join in against him.
func _tick_sit(delta: float) -> void:
	var p = converting_preacher
	if p == null or not is_instance_valid(p) or p.state == State.DEAD:
		_stand_up(false)
		return
	if p.state == State.ATTACK:
		_stand_up(true)   # trance broken by a duel -> fight the preacher
		return
	if p.state != State.CAST \
			or _flat_dist(position, p.position) > Preacher.CONVERT_RANGE * 1.3:
		_stand_up(false)
		return
	conversion_progress += delta
	if conversion_progress >= conversion_time and p.tribe != null:
		convert_to_tribe(p.tribe)


## A firewarrior's fireball hit interrupts the conversion: the progress is
## lost and the unit stands back up (combatants re-aggro on their own).
func reset_conversion() -> void:
	if state != State.SIT:
		return
	conversion_progress = 0.0
	_stand_up(false)


func _stand_up(fight_preacher: bool) -> void:
	var p = converting_preacher
	converting_preacher = null
	conversion_progress = 0.0
	_set_state(State.IDLE)
	if fight_preacher and p != null and is_instance_valid(p) and p.state != State.DEAD:
		_begin_attack(p)


## Switches this unit to `new_tribe` (conversion complete): tribe lists are
## re-hung, colour follows via the converted signal (UnitManager -> renderer),
## running orders are gone and everyone attacking it drops the (now friendly)
## target.
func convert_to_tribe(new_tribe: Tribe) -> void:
	if tribe != null:
		tribe.remove_unit(self)
	tribe_id = new_tribe.id
	new_tribe.add_unit(self)
	converting_preacher = null
	conversion_progress = 0.0
	last_attacker = null
	_end_attack()
	for a in melee_attackers.duplicate():
		if is_instance_valid(a):
			a._on_target_died(self)   # drops the target and retargets
	melee_attackers.clear()
	incoming_attackers = 0
	selected = false
	_set_state(State.IDLE)
	converted.emit(self)


## Idle combatants scan for a nearby enemy (throttled) and engage it.
## Deliberately NOTHING else here — this is the hottest per-unit path with
## thousands idle. The 7b idle features (idle_seconds for regrouping, the
## brave's small guard scan) run in the UnitManager's sliced regroup pass.
func _tick_idle(delta: float) -> void:
	if _is_combatant():
		_engage_on_sight(delta)


## Throttled enemy scan + engage; used from IDLE and while marching (MOVE,
## attack-move). Returns true when the unit switched into a fight. The
## preacher overrides this to prefer converting over brawling.
func _engage_on_sight(delta: float) -> bool:
	if not _due_to_scan(delta):
		return false
	var enemy: Unit = _scan_for_enemy(AGGRO_RADIUS)
	if enemy == null:
		return false
	_begin_attack(enemy)
	return true


## Pursues the current target and strikes it when in range and holding a slot.
func _tick_attack(delta: float) -> void:
	# A converted target became friendly mid-fight -> drop it.
	if not _target_valid(attack_target) or attack_target.tribe_id == tribe_id:
		_retarget_or_idle()
		return
	if _breaks_off_vs_sitting(attack_target):
		return
	var target: Unit = attack_target
	var slot: int = target.request_melee_slot(self)
	if slot < 0:
		# Target is full (3 attackers). Prefer a still-free enemy (1v1), else
		# wait around the fight until a slot opens (checked, not per-frame).
		_in_melee = false
		if _due_to_scan(delta):
			var alt: Unit = _scan_for_enemy(AGGRO_RADIUS)
			if alt != null and alt != target and alt.active_melee_attacker_count() \
					< MAX_MELEE_ATTACKERS:
				_begin_attack(alt)
				return
		_wait_near(target, delta)
		return
	var slot_pos: Vector3 = target.melee_slot_position(slot)
	var dist: float = _flat_dist(position, target.position)
	if dist > MELEE_RANGE:
		_in_melee = false
		_approach(slot_pos, delta)
		_face_point(target.position)
		return
	# In range: stand still, face the target and strike on cooldown.
	_in_melee = true
	if _has_path():
		_clear_path()
	_face_point(target.position)
	_attack_cooldown -= delta
	if _attack_cooldown <= 0.0:
		_attack_cooldown = ATTACK_COOLDOWN
		_do_strike(target)


## Rolls an attack kind and applies its (strength-scaled) damage to the target.
func _do_strike(target: Unit) -> void:
	var kind: StringName = _roll_attack_kind()
	# Each kind has its own animation; restart it so the swing lands with the
	# hit (the punch/kick/shove cycles are tuned to ATTACK_COOLDOWN).
	attack_anim = kind_to_anim(kind)
	anim_base_name = attack_anim
	anim_start_ms = Time.get_ticks_msec()
	_no_combat_timer = 0.0   # dealing damage also blocks regeneration
	target.take_damage(melee_damage(kind), self)
	if kind == &"shove" and is_instance_valid(target) and target.state != State.DEAD:
		_apply_shove(target)
	_emit_combat_hit(kind)


## A shove always shifts the target slightly (the brawl moves around — the
## attackers close up on their ring slots automatically) and sometimes knocks
## it over into a very short roll, even on flat ground; on a slope the roll
## then follows the fall line downhill.
func _apply_shove(target: Unit) -> void:
	var dir: Vector3 = Vector3(
		target.position.x - position.x, 0.0, target.position.z - position.z)
	if dir.length_squared() < 0.000001:
		dir = facing
	target.displace(dir, SHOVE_DISPLACE)
	if randf() < SHOVE_ROLL_CHANCE:
		target.start_roll(dir, MINI_ROLL_DURATION)


## Emits the hit on the Events bus (CombatAudio plays a matching sound).
## Guarded: absent in headless tests without autoloads.
func _emit_combat_hit(kind: StringName) -> void:
	if not _events_checked:
		_events_checked = true
		if is_inside_tree():
			_events_node = get_node_or_null("/root/Events")
	if _events_node != null:
		_events_node.combat_hit.emit(kind, position)


## Animation base for an attack kind (the anim names match the kinds).
static func kind_to_anim(kind: StringName) -> StringName:
	match kind:
		&"kick":
			return &"kick"
		&"shove":
			return &"shove"
		_:
			return &"punch"


## Picks punch / kick / shove for this strike. Shoves are rare (rarer still for
## the warrior); kicks are uncommon; most strikes are punches.
func _roll_attack_kind() -> StringName:
	var r: float = randf()
	if r < _shove_chance():
		return &"shove"
	if r < _shove_chance() + KICK_CHANCE:
		return &"kick"
	return &"punch"


## Base (unscaled) damage for an attack kind. Pure + static so it is testable.
static func attack_base_damage(kind: StringName) -> int:
	match kind:
		&"kick":
			return MELEE_KICK
		&"shove":
			return MELEE_SHOVE
		_:
			return MELEE_PUNCH


## Damage this unit deals with the given attack kind (base * melee_strength()).
func melee_damage(kind: StringName) -> int:
	return int(round(float(attack_base_damage(kind)) * melee_strength()))


# --- Target selection & slots -------------------------------------------------

## Starts (or switches to) meleeing `enemy`. Releases any previous slot and lets
## the current activity clean up (Brave releases worker claims).
func _begin_attack(enemy: Unit) -> void:
	if not can_take_orders():
		return   # a sitting (pacified) unit cannot be sent into a fight
	if enemy == null or not is_instance_valid(enemy) or enemy.state == State.DEAD:
		return
	if attack_target == enemy:
		if state != State.ATTACK:
			_set_state(State.ATTACK)
		return
	_on_combat_interrupt()
	_end_attack()
	attack_target = enemy
	enemy.incoming_attackers += 1
	_attack_cooldown = 0.0
	_combat_goal = Vector3.INF
	_set_state(State.ATTACK)


## Public order entry used by TribeCommands.order_attack (UI + AI).
func order_attack(enemy: Unit) -> void:
	_begin_attack(enemy)


## Clears our attack and frees the slot we held on the target.
func _end_attack() -> void:
	if attack_target != null and is_instance_valid(attack_target):
		attack_target.release_melee_slot(self)
		attack_target.incoming_attackers = maxi(0, attack_target.incoming_attackers - 1)
	attack_target = null
	_in_melee = false
	_combat_goal = Vector3.INF


## Our target died: drop it and (combatants) look for another; braves go idle.
func _on_target_died(target) -> void:
	if attack_target != target:
		return
	attack_target = null
	_in_melee = false
	_combat_goal = Vector3.INF
	_retarget_or_idle()


func _retarget_or_idle() -> void:
	_end_attack()
	if _is_combatant():
		var enemy: Unit = _scan_for_enemy(AGGRO_RADIUS)
		if enemy != null:
			_begin_attack(enemy)
			return
	_set_state(State.IDLE)


## While a target is being converted (sitting), attackers break off — only a
## SIT_ATTACK_CONTINUE_CHANCE roll (once per attacker per sitting spell) keeps
## one fighting. Returns true when the attack was dropped.
func _breaks_off_vs_sitting(target: Unit) -> bool:
	if target.state != State.SIT:
		if _sit_decision_target == target:
			_sit_decision_target = null   # target stood up: fresh roll next time
		return false
	if _sit_decision_target == target:
		return false   # already rolled "keep fighting" for this spell
	if randf() < SIT_ATTACK_CONTINUE_CHANCE:
		_sit_decision_target = target
		return false
	_retarget_or_idle()
	return true


## Braves fight back when hit (from idle/moving only — busy workers keep working);
## combatants already have a target, so this is mostly a brave hook. FLEEING
## units (passive move) only fall back into the fight after every
## FLEE_RETALIATE_HITS-th melee hit — escaping a brawl usually works, but a
## cornered unit sometimes has to defend itself.
func _maybe_retaliate(attacker) -> void:
	if attacker == null or not is_instance_valid(attacker) or attacker.state == State.DEAD:
		return
	if attacker.tribe_id == tribe_id:
		return   # friendly fire (e.g. a rescue fireball) is not retaliated
	if attack_target != null and is_instance_valid(attack_target):
		return
	if state == State.IDLE:
		_begin_attack(attacker)
		return
	if state != State.MOVE:
		return
	if move_aggressive:
		_begin_attack(attacker)
		return
	# Fleeing: only melee-range pressure counts, and only every n-th hit.
	if _flat_dist(position, attacker.position) > FLEE_MELEE_RANGE:
		return
	_flee_hits += 1
	if _flee_hits >= FLEE_RETALIATE_HITS:
		_flee_hits = 0
		_begin_attack(attacker)


## Nearest enemy in radius, preferring targets with fewer attackers (1v1 bias).
## The candidate query is capped: in a mega-crowd an uncapped scan per unit
## per 0.25 s dominated the tick (measured 60 ms with 4000 stacked units).
func _scan_for_enemy(radius: float) -> Unit:
	if path_service == null:
		return null
	var flat: Vector2 = Vector2(position.x, position.z)
	var best: Unit = null
	var best_score: float = INF
	for u in path_service.get_units_in_radius(position, radius, SCAN_MAX_CANDIDATES):
		if u == self or u.state == State.DEAD or u.tribe_id == tribe_id:
			continue
		if u.state == State.SIT:
			continue   # sitting converts are no threat (and shall keep sitting)
		var d: float = Vector2(u.position.x, u.position.z).distance_to(flat)
		# Commitment count dominates the score so free enemies are picked first
		# (1v1 preference), even before anyone is in striking range.
		var score: float = float(u.incoming_attackers) * 1000.0 + d
		if score < best_score:
			best_score = score
			best = u
	return best


## Registers `attacker` on this unit's melee ring. Returns its slot index
## (0..MAX-1) or -1 when the ring is full. Untyped param (freed-safe).
func request_melee_slot(attacker) -> int:
	_prune_melee_attackers()
	var idx: int = melee_attackers.find(attacker)
	if idx >= 0:
		return idx
	if melee_attackers.size() < MAX_MELEE_ATTACKERS:
		melee_attackers.append(attacker)
		return melee_attackers.size() - 1
	return -1


func release_melee_slot(attacker) -> void:
	melee_attackers.erase(attacker)


func active_melee_attacker_count() -> int:
	_prune_melee_attackers()
	return melee_attackers.size()


## Drops freed/dead attackers and any that have since retargeted, freeing slots.
func _prune_melee_attackers() -> void:
	var kept: Array = []
	for a in melee_attackers:
		if is_instance_valid(a) and a.state != State.DEAD and a.attack_target == self:
			kept.append(a)
	melee_attackers = kept


## Ring position for slot index around this (target) unit.
func melee_slot_position(slot: int) -> Vector3:
	var angle: float = TAU * float(slot) / float(MAX_MELEE_ATTACKERS)
	return position + Vector3(cos(angle) * MELEE_SLOT_RADIUS, 0.0, sin(angle) * MELEE_SLOT_RADIUS)


# --- Combat movement ----------------------------------------------------------

## Approaches `dest`: A* while far (avoids water/obstacles), direct step when
## close (combat is chaotic and short-range — no need to re-path every metre).
func _approach(dest: Vector3, delta: float) -> void:
	if _flat_dist(position, dest) > COMBAT_DIRECT_RANGE and nav_grid != null:
		if not _has_path() or _flat_dist(_combat_goal, dest) > 1.0:
			_combat_goal = dest
			if not _plan_path_to(dest):
				_step_toward(dest, delta)
				return
		if _advance_path(delta):
			_clear_path()
		return
	_step_toward(dest, delta)


## Overflow attacker waits on a ring around the target (deterministic angle per
## unit so they spread out) until a slot frees.
func _wait_near(target: Unit, delta: float) -> void:
	var angle: float = float(get_instance_id() % 628) * 0.01
	var dest: Vector3 = target.position + Vector3(
		cos(angle) * MELEE_WAIT_RADIUS, 0.0, sin(angle) * MELEE_WAIT_RADIUS)
	if _flat_dist(position, dest) > 0.25:
		_step_toward(dest, delta)
	_face_point(target.position)


## Moves directly toward a point on the XZ plane (no pathing), snapping Y.
## Uphill slopes slow the step like regular path movement.
func _step_toward(point: Vector3, delta: float) -> void:
	var flat: Vector2 = Vector2(position.x, position.z)
	var flat_target: Vector2 = Vector2(point.x, point.z)
	var to_target: Vector2 = flat_target - flat
	if to_target.length_squared() > 0.000001:
		facing = Vector3(to_target.x, 0.0, to_target.y).normalized()
	var next: Vector2 = flat.move_toward(flat_target, _slope_speed(_slope_ahead(to_target)) * delta)
	position.x = next.x
	position.z = next.y
	_snap_to_ground()


func _face_point(point: Vector3) -> void:
	var dir: Vector3 = Vector3(point.x - position.x, 0.0, point.z - position.z)
	if dir.length_squared() > 0.000001:
		facing = dir.normalized()


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


## Untyped param (freed-safe): true while the target is a live, non-dead unit.
func _target_valid(target) -> bool:
	return target != null and is_instance_valid(target) and target.state != State.DEAD


## True at most every TARGET_SEARCH_INTERVAL (staggered per unit) — scans are
## never per-frame (Overview architecture rule).
func _due_to_scan(delta: float) -> bool:
	_target_search_timer -= delta
	if _target_search_timer <= 0.0:
		_target_search_timer = TARGET_SEARCH_INTERVAL + float(get_instance_id() % 50) * 0.002
		return true
	return false


# --- State & visuals -------------------------------------------------------------

func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	idle_seconds = 0.0
	state_changed.emit(self, new_state)
	_update_animation()


func _update_animation() -> void:
	_apply_animation(true)


## Which of the four sprite views matches a facing direction, given the
## camera's forward and right vectors. Returns an index into
## PlaceholderSprites.VIEWS (0 = front, 1 = back, 2 = right, 3 = left).
## Static + camera-free so it is headless-testable. Boundary (45 deg)
## prefers front/back.
static func view_index(p_facing: Vector3, cam_forward: Vector3, cam_right: Vector3) -> int:
	var flat_facing: Vector2 = Vector2(p_facing.x, p_facing.z)
	var flat_forward: Vector2 = Vector2(cam_forward.x, cam_forward.z)
	if flat_facing.length_squared() < 0.000001 or flat_forward.length_squared() < 0.000001:
		return 0
	flat_facing = flat_facing.normalized()
	flat_forward = flat_forward.normalized()
	var dot: float = flat_facing.dot(flat_forward)
	if dot >= 0.7071:
		return 1    # walking away from the camera -> back
	if dot <= -0.7071:
		return 0    # walking toward the camera -> front
	var flat_right: Vector2 = Vector2(cam_right.x, cam_right.z)
	return 2 if flat_facing.dot(flat_right) > 0.0 else 3


## StringName variant of view_index (kept for tests/readability).
static func view_suffix(p_facing: Vector3, cam_forward: Vector3, cam_right: Vector3) -> StringName:
	return PlaceholderSprites.VIEWS[view_index(p_facing, cam_forward, cam_right)]


## Animation base name for the current state; subclasses refine this for
## their sub-states (e.g. Brave chopping vs. walking while in GATHER).
func _anim_base() -> StringName:
	match state:
		State.MOVE, State.PANIC:
			return &"walk"
		State.ATTACK:
			# The rolled strike's animation while fighting; walk while closing in.
			return attack_anim if _in_melee else &"walk"
		State.CAST:
			return &"cast"
		State.SIT:
			return &"sit"
		State.ROLL, State.THROWN:
			return &"roll"
		State.DEAD:
			return &"dead"
		_:
			return &"idle"


## Refreshes the animation state consumed by the UnitRenderer: the base name
## follows the state (_anim_base hook); the timer restarts on a base change
## or an explicit restart, so frame timing starts at frame 0.
func _apply_animation(restart: bool) -> void:
	var base: StringName = _anim_base()
	if base != anim_base_name:
		anim_base_name = base
		anim_start_ms = Time.get_ticks_msec()
	elif restart:
		anim_start_ms = Time.get_ticks_msec()


## Marks the unit as selected. The rings are rendered centrally by the
## SelectionRingRenderer (one MultiMesh) — per-unit ring nodes caused a
## visible hitch when box-selecting hundreds of units.
func set_selected(p_selected: bool) -> void:
	selected = p_selected
