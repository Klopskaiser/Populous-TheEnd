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
## FORESTER = assigned to a forester (housed inside, or briefly out planting a
## sapling, phase 7d).
## CREW = manning a siege engine (phase 7f): the unit walks with the engine on
## its side slot; it defends itself when attacked and returns afterwards.
## RAID = a melee raider INSIDE an enemy building demolishing it (phase 7g):
## removed from the world like a trainee; it steps back out alive when the
## building collapses.
## GARRISON = walking to / stationed inside an own watchtower (phase 7h):
## while approaching the unit is a normal walker; once admitted it is removed
## from the world (protected reserve), driven by the tower.
enum State {IDLE, MOVE, GATHER, PRAY, BUILD, ATTACK, TRAIN, PANIC, CAST, THROWN, DEAD, SIT, ROLL, FORESTER, CREW, RAID, GARRISON}

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
## Max ENEMY candidates one scan collects (crowd cost cap). Since phase 8.2
## friendly units no longer consume this budget (blob blindness fix) — see
## UnitManager.get_enemy_candidates.
const SCAN_MAX_CANDIDATES: int = 24
## How long a combat target proven unreachable (failed A* while approaching)
## is ignored by scans — instead of walking into the cliff wall (phase 8.2).
const UNREACHABLE_TARGET_MS: int = 3000
## At most this many unreachable-target entries are remembered per unit.
const UNREACHABLE_CACHE_MAX: int = 8
## Radius at which idle / attack-moving combatants notice an enemy BUILDING to
## assault (phase 7g). Larger than the melee aggro so buildings (stationary, big
## targets) are reliably picked up — but still LOWEST priority: an enemy unit in
## the normal aggro radius is always engaged first.
const BUILDING_ENGAGE_RADIUS: float = 12.0
## A melee raider enters only through the ENTRANCE: it must be within this
## distance of the entrance point to slip in (they path around the footprint to
## the door instead of clipping in through the nearest wall). Admitted raiders
## leave the world immediately, so the doorway drains without a real bottleneck.
const RAID_ENTER_RANGE: float = 2.0
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
## Trapped-roll safety nets (phase 8.2): a roll in an earthquake bowl can
## follow the fall line forever (the walls stay steeper than ROLL_END_SLOPE)
## — with the deferred-death rule that made units IMMORTAL. A roll that
## makes no net progress ends early (stand up / finish dying), and no roll
## survives the hard time cap.
const ROLL_MAX_DURATION: float = 30.0
const ROLL_PROBE_INTERVAL: float = 2.0
const ROLL_PROBE_MIN_DIST: float = 1.0
## Same hard cap for scripted throws (e.g. a tornado carry that never lands):
## past this the unit dies and drops out of the sky as a corpse.
const THROWN_MAX_DURATION: float = 30.0
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
## A queued follow-up order (Shift+right-click on a building / catapult after a
## waypoint route): fired ONCE when the route completes, so the unit walks its
## waypoints first and only THEN enters the building / boards the engine. Cleared
## by any fresh (non-queued) order.
var route_end_action: Callable = Callable()
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
## True once the renderer collapsed this unit's blob shadow (corpses).
var _blob_hidden: bool = false

var _path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0
## Queued move target awaiting path computation (INF = none).
var _pending_target: Vector3 = Vector3.INF
var _path_queued: bool = false
## Monotonic id of the LATEST submitted async path request (phase 8.1). A new
## order bumps it; a worker result whose id no longer matches is stale and
## discarded — no throughput limit needed, so the phase-8 restack bug (units
## "ignore orders") is structurally impossible.
var _path_request_id: int = 0

# --- Combat state (phase 5b) --------------------------------------------------
## Enemy this unit is meleeing (null = none). Typed, but every read is guarded
## with is_instance_valid — the target may be freed by another attacker.
var attack_target: Unit = null
## Enemy BUILDING this unit assaults (phase 7g; untyped: may be freed when it
## collapses). Lowest-priority target: only pursued when no enemy unit is near.
## The siege engine (7f) reuses this field with its own bombardment logic.
var attack_building = null
## While set (untyped: may be freed), this unit is a melee raider INSIDE this
## building demolishing it (State.RAID, removed from the world like a trainee).
var raiding_building = null
## Watchtower this unit is walking to (approach) or stationed inside (phase 7h;
## untyped: may be freed). While housed (garrison_housed) the unit is removed
## from the world and driven by the tower.
var garrison_target = null
## True once this unit is HOUSED inside the tower (removed from the world). It
## then accepts no orders — the only way out is ejection (eject / storm / damage).
var garrison_housed: bool = false
## True while this unit stands at the tower entrance waiting to be admitted. The
## tower admits it on ITS tick (not here) so the units list is not mutated
## mid-iteration (same rationale as the training queue).
var garrison_reached: bool = false
## Enemy-building scan support (phase 7g); injected by UnitManager.spawn_unit()
## via set() for every unit (the siege engine used it first, 7f).
var building_manager: BuildingManager = null
## The 1-vs-N combat group this unit is bound to (CombatGroup, untyped for
## freed-safety) — as its defender, one of its attackers, or a waiter in the
## second row. At most ONE group per unit (phase 8.2 invariant: no 2v2).
var combat_group = null
## Compat view: units currently meleeing THIS unit (the own group's attacker
## list while this unit is the defender). Read-only.
var melee_attackers: Array:
	get:
		if combat_group != null and combat_group.defender == self:
			return combat_group.attackers
		var empty: Array = []
		return empty
## True while this unit stands in the second row of its group (drives the idle
## animation instead of walking in place).
var _combat_waiting: bool = false
## Recently-unreachable combat targets: instance id -> ignore-until ticks-msec
## (Bergpass fix: scans skip these instead of re-running failing A*).
var _unreach_targets: Dictionary = {}
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

# --- Siege crew state (phase 7f) ---------------------------------------------------
## The siege engine this unit is manning (untyped: may be freed). Membership
## survives self-defence fights (the engine's leash rule drops runaways);
## explicit move orders and conversions leave the crew.
var siege_engine = null
## True once this crew member reached its engine at least once. Fresh recruits
## walking over from afar are never leash-pruned; boarded members are.
var siege_boarded: bool = false
## True while a crew member is walking (to board or to keep its slot) — drives
## the walk animation without needing an A* path (crew glide in lockstep).
var _crew_walking: bool = false
## Excluded from the soft-separation push (siege engines: a vehicle is not
## shoved aside by pedestrians). A FIELD like idle_aggro — hot path.
var push_immune: bool = false
## > 0 for VEHICLES (siege engine): the separation keeps this distance to
## OTHER vehicles — sized so two devices incl. their side/rank crew slots
## never overlap (phase 8.2). Pedestrians keep the normal tiny radius.
var vehicle_separation: float = 0.0
## Counted in Tribe.population() (false for devices like the siege engine).
var counts_population: bool = true

# --- Roll state (phase 5d) ---------------------------------------------------------
var roll_dir: Vector3 = Vector3.ZERO
var _roll_time: float = 0.0
var _roll_min_time: float = 0.0
var _roll_damage_frac: float = 0.0
## Momentum of a throw-landing roll (0 = plain constant-speed roll).
var _roll_init_speed: float = 0.0
## State to resume when a harmless downhill STUMBLE ends (-1 = combat roll:
## orders were cleared, the unit gets up idle). Workers continue their task,
## movers continue their route (phase 8.2 — stumbling used to wipe orders).
var _stumble_resume: int = -1
## Trapped-roll progress probe (see ROLL_PROBE_* constants).
var _roll_probe_pos: Vector3 = Vector3.ZERO
var _roll_probe_timer: float = 0.0

# --- Throw / panic state (phase 6) ----------------------------------------------------
var _throw_velocity: Vector3 = Vector3.ZERO
var _throw_fall_damage: int = 0
## Continuous airborne time; past THROWN_MAX_DURATION the unit dies and
## drops out of the sky as a corpse (phase 8.2 safety net).
var _throw_time: float = 0.0
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


## True for ranged units (firewarrior): any number may fire at one target, so
## the 3-attacker melee cap and its target redistribution do not apply to them.
func _is_ranged() -> bool:
	return false


## False for units that can never be attacked directly (the siege engine:
## attackers hit its crew instead) or that are currently a protected reserve
## (tower crew, phase 7h — safe from fireballs/melee/conversion until ejected).
## Filtered in every enemy scan/order.
func is_targetable() -> bool:
	return not garrison_housed


## Drawn via the central sprite MultiMesh (UnitRenderer). The siege engine
## returns false and builds its own 3D model instead.
func renders_as_sprite() -> bool:
	return true


## Whether this unit may man a siege engine (everyone except the shaman and
## the engines themselves, phase 7f).
func can_crew_siege() -> bool:
	return unit_kind() != &"shaman" and unit_kind() != &"siege"


## Scale of the selection ring (SelectionRingRenderer). The siege engine uses
## a big ring that visually encloses the vehicle AND its crew.
func selection_ring_scale() -> float:
	return 1.0


## Radius at which an idle/marching combatant engages enemies on its own (and
## re-targets). Melee units use AGGRO_RADIUS; ranged units (firewarrior) see
## farther so they react to threats near their fire range — including an enemy
## shooting a neighbour — instead of only enemies right on top of them.
func aggro_radius() -> float:
	return AGGRO_RADIUS


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
	# Stationed tower crew (phase 7h) are fully driven by the tower (position,
	# facing, animation, fire/convert): they have no world tick of their own.
	if garrison_housed:
		return
	_tick_knockback(delta)
	_tick_regen(delta)
	_tick_burning(delta)
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
		State.CREW:
			_tick_crew(delta)
		State.GARRISON:
			_tick_garrison(delta)
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
		# Harmless downhill stumble: orders survive (resumed after the tumble).
		start_roll(Vector3(to_target.x, 0.0, to_target.y), MINI_ROLL_DURATION, 0.0, true)
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
		_finish_route()
		return
	if patrol:
		# Rotate the queue: the reached waypoint goes to the back.
		waypoint_queue.append(waypoint_queue.pop_front())
		_start_path_to(waypoint_queue[0])
	else:
		waypoint_queue.pop_front()
		if waypoint_queue.is_empty():
			_finish_route()
		else:
			_start_path_to(waypoint_queue[0])


## The waypoint route is exhausted: fire the queued follow-up order (Shift+
## right-click on a building/catapult after waypoints — enter/board only AFTER
## walking the route), otherwise just go idle.
func _finish_route() -> void:
	if route_end_action.is_valid():
		var act: Callable = route_end_action
		route_end_action = Callable()
		act.call()
		return
	_set_state(State.IDLE)


# --- Orders --------------------------------------------------------------------

## While pacified by an enemy preacher (SIT) the unit accepts NO orders at all —
## it stays sitting until the preacher is attacked (priest duel), interrupted
## (fireball reset, out of range, death) or the conversion completes. Rolling,
## airborne (thrown) and panicking units are equally beyond control.
func can_take_orders() -> bool:
	return state != State.SIT and state != State.DEAD and state != State.ROLL \
		and state != State.THROWN and state != State.PANIC and state != State.RAID \
		and not garrison_housed


## Move order. queue_up appends the target as an additional waypoint
## (Shift+right-click), otherwise the current route is replaced. `aggressive`
## selects attack-move (engage enemies on the way) vs. plain move (default —
## also the flee order: breaks off the current fight).
func order_move(target: Vector3, queue_up: bool = false, aggressive: bool = false) -> void:
	if not can_take_orders():
		return
	leave_crew()   # an explicit move order pulls the unit off its siege engine
	garrison_target = null   # a move order abandons a pending garrison approach
	_end_attack()
	_clear_building_target()   # a move order also breaks off a building assault
	move_aggressive = aggressive
	_flee_hits = 0
	if not queue_up:
		route_end_action = Callable()   # a fresh route cancels a queued follow-up
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
	if not _plan_path_to(target, move_aggressive):
		# Unreachable: drop the waypoint and stop.
		if not waypoint_queue.is_empty():
			waypoint_queue.pop_front()
		_set_state(State.IDLE)
		return
	_set_state(State.MOVE)


## Called by the UnitManager when this unit's queued path request is due
## (synchronous path service, tests and worker-disabled fallback).
func _resolve_pending_path() -> void:
	_path_queued = false
	if _pending_target == Vector3.INF:
		return
	var target: Vector3 = _pending_target
	_pending_target = Vector3.INF
	if state != State.MOVE:
		return  # order was superseded while waiting
	if not _plan_path_to(target, move_aggressive):
		if not waypoint_queue.is_empty():
			waypoint_queue.pop_front()
		_set_state(State.IDLE)


## Phase 8.1 (Stufe A): hands the pending target to the off-thread PathWorker as
## a POD request (grid cells + a fresh request id). Unlike _resolve_pending_path
## this does NOT clear _pending_target — the unit keeps waiting (and holds
## position, see _tick_move) until the async result lands in _apply_worker_path.
func _submit_path_request(worker: PathWorker) -> void:
	_path_queued = false
	if _pending_target == Vector3.INF or state != State.MOVE or nav_grid == null:
		return
	_path_request_id += 1
	var from_cell: Vector2i = nav_grid.world_to_cell(position)
	var target_cell: Vector2i = nav_grid.world_to_cell(_pending_target)
	# Attack-move waves accept a PARTIAL path (closest reachable point toward
	# the target) instead of idling at an unreachable wave target (phase 8.2).
	worker.submit_request(get_instance_id(), _path_request_id, from_cell,
		target_cell, move_aggressive)


## Applies a worker result (main thread). Discards stale/superseded results and
## does the world/Y conversion here (heights never cross the thread boundary):
## cell centres via NavGrid, and — reproducing NavGrid.find_path — the exact
## click point as the last point when the target cell was reached without a snap.
func _apply_worker_path(request_id: int, cells: PackedVector2Array) -> void:
	if request_id != _path_request_id:
		return  # a newer order was issued; this answer is stale — keep waiting
	if _pending_target == Vector3.INF:
		return  # already consumed (e.g. set_path cancelled it)
	# This IS the latest request: consume the pending target unconditionally, so
	# a later return to MOVE can never wait on an id that will never arrive.
	var target: Vector3 = _pending_target
	_pending_target = Vector3.INF
	if state != State.MOVE or nav_grid == null:
		return  # order superseded while waiting
	if cells.is_empty():
		# Unreachable target — same outcome as the synchronous failure branch.
		if not waypoint_queue.is_empty():
			waypoint_queue.pop_front()
		_set_state(State.IDLE)
		return
	var path: PackedVector3Array = PackedVector3Array()
	for c in cells:
		path.append(nav_grid.cell_to_world(Vector2i(c)))
	if Vector2i(cells[cells.size() - 1]) == nav_grid.world_to_cell(target):
		path[path.size() - 1] = Vector3(
			target.x, nav_grid.terrain.get_height(target.x, target.z), target.z)
	_path = path
	_path_index = 0


## Path-planning telemetry (phase 8 tooling), read/reset by the perf
## benchmarks — failing A* runs explore their whole walkable component, so
## the benchmarks watch these counters. Pure counters, no behaviour.
static var dbg_plan_calls: int = 0
static var dbg_plan_fails: int = 0
static var dbg_plan_us: int = 0


## Computes and stores a path without touching the state (Brave sub-states
## use this too). Returns false if the target is unreachable. `allow_partial`
## (attack-move routes) accepts a path to the closest REACHABLE point toward
## an unreachable target instead of failing (phase 8.2).
func _plan_path_to(target: Vector3, allow_partial: bool = false) -> bool:
	var path: PackedVector3Array
	var t0: int = Time.get_ticks_usec()
	if nav_grid != null:
		path = nav_grid.find_path(position, target, allow_partial)
	else:
		path = PackedVector3Array([target])
	dbg_plan_calls += 1
	dbg_plan_us += Time.get_ticks_usec() - t0
	if path.is_empty():
		dbg_plan_fails += 1
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
	# Release our own binding, then dissolve the fight around us so attackers
	# and the second row retarget onto fresh enemies right away.
	leave_crew()
	_end_attack()
	_clear_building_target()
	_dissolve_own_group()
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
## `stumble` marks a harmless downhill trip (steep-walk trigger, NO combat
## cause): orders and task fields survive, and the unit resumes them when it
## gets back up (phase 8.2 — see _resume_after_stumble).
func start_roll(dir: Vector3, duration: float = MINI_ROLL_DURATION,
		initial_speed: float = 0.0, stumble: bool = false) -> void:
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
		if not stumble and _stumble_resume >= 0:
			# A combat/spell hit extends a harmless stumble: from here on it
			# is a real combat roll — the saved orders are cleared like on a
			# fresh combat roll.
			_stumble_resume = -1
			_on_combat_interrupt()
			_end_attack()
			waypoint_queue.clear()
		return
	if stumble:
		_stumble_resume = state
		_on_stumble()
	else:
		_stumble_resume = -1
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
	_roll_probe_pos = position
	_roll_probe_timer = 0.0
	_set_state(State.ROLL)


## Hook for a harmless downhill stumble (start_roll with `stumble`); the
## Brave drops its carried wood here (and picks it back up on resume).
func _on_stumble() -> void:
	pass


func _tick_roll(delta: float) -> void:
	_roll_time += delta
	# Rolling into water is instant death (no deferral).
	if terrain_data != null and terrain_data.get_height(position.x, position.z) \
			<= TerrainData.SEA_LEVEL + 0.05:
		health = 0
		_die()
		return
	# Trapped-roll safety nets (phase 8.2, earthquake bowls — the fall line
	# there never flattens below ROLL_END_SLOPE, so the roll never ended and
	# the deferred-death rule made the unit IMMORTAL):
	# 1. Lethal damage is deferred only for the minimum tumble, not forever.
	if health <= 0 and _roll_time >= _roll_min_time:
		_end_roll()
		return
	# 2. No roll survives the hard time cap (dies as a corpse on the spot).
	if _roll_time >= ROLL_MAX_DURATION:
		health = 0
		_end_roll()
		return
	# 3. A roll that makes no net progress (bouncing between the bowl walls)
	# ends early — the unit stands back up instead of tumbling in place.
	_roll_probe_timer += delta
	if _roll_probe_timer >= ROLL_PROBE_INTERVAL:
		if _flat_dist(position, _roll_probe_pos) < ROLL_PROBE_MIN_DIST:
			_end_roll()
			return
		_roll_probe_timer = 0.0
		_roll_probe_pos = position
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
	if _stumble_resume >= 0:
		var resume: int = _stumble_resume
		_stumble_resume = -1
		_resume_after_stumble(resume)
		return
	_set_state(State.IDLE)


## Back on its feet after a harmless downhill stumble: continue what we were
## doing — the route to the next waypoint (fresh path from the landing spot),
## the running fight, or the worker task whose fields survived the tumble
## (the Brave picks its dropped wood back up via its normal task selection).
func _resume_after_stumble(prev: int) -> void:
	match prev:
		State.MOVE:
			if not waypoint_queue.is_empty():
				_start_path_to(waypoint_queue[0])
			else:
				_set_state(State.IDLE)
		State.ATTACK:
			if (_target_valid(attack_target) and attack_target.tribe_id != tribe_id) \
					or _building_target_valid():
				_set_state(State.ATTACK)
			else:
				_retarget_or_idle()
		State.IDLE, State.DEAD, State.ROLL, State.THROWN, State.SIT:
			_set_state(State.IDLE)
		_:
			# Worker/pray/train/crew/garrison/panic sub-states: their fields
			# were preserved, the state tick carries on where it left off.
			_set_state(prev as State)


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
	_stumble_resume = -1   # a throw is combat: any saved stumble order is void
	_throw_velocity = velocity
	_throw_fall_damage = fall_damage
	_throw_time = 0.0
	_set_state(State.THROWN)


func _tick_thrown(delta: float) -> void:
	_throw_time += delta
	if _throw_time >= THROWN_MAX_DURATION:
		# Safety net: a throw/carry that never lands (e.g. trapped over a
		# deformation pit) ends here — the unit dies and falls as a corpse.
		throw_carrier = null
		_snap_to_ground()
		health = 0
		_die()
		return
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


## Instant water death: landing in the sea after a throw, or the ground
## flooding away under the unit (terrain spells, 7c integrity rules).
func drown() -> void:
	if state == State.DEAD:
		return
	health = 0
	_die()


# --- Burning (7c lava) --------------------------------------------------------------

## Touching lava: instant contact damage, then the unit burns and scrambles
## around in panic for the whole burn (panic-immune units burn standing).
const LAVA_CONTACT_DAMAGE: int = 30    # half a brave life per touch
const BURN_DURATION: float = 4.0
const BURN_TOTAL_DAMAGE: int = 120     # 2x brave life spread over the burn

var _burn_time: float = 0.0
var _burn_frac: float = 0.0


func is_burning() -> bool:
	return _burn_time > 0.0


## Lava contact. Re-touching while already alight refreshes the burn instead
## of stacking it (and costs no second contact hit).
func ignite(source_pos: Vector3) -> void:
	if state == State.DEAD:
		return
	var fresh: bool = not is_burning()
	_burn_time = BURN_DURATION
	if fresh:
		take_damage(LAVA_CONTACT_DAMAGE)
		if state == State.DEAD:
			return
	start_panic(source_pos, BURN_DURATION)


func _tick_burning(delta: float) -> void:
	if _burn_time <= 0.0 or state == State.DEAD:
		return
	_burn_time -= delta
	_burn_frac += float(BURN_TOTAL_DAMAGE) / BURN_DURATION * delta
	var whole: int = int(_burn_frac)
	if whole > 0:
		_burn_frac -= float(whole)
		take_damage(whole)


## Landing: water kills instantly; building footprints are snapped out of;
## fall damage applies, then the momentum roll takes over.
func _land_from_throw(ground: float) -> void:
	var fall_damage: int = _throw_fall_damage
	_throw_fall_damage = 0
	var momentum: Vector3 = Vector3(_throw_velocity.x, 0.0, _throw_velocity.z)
	_throw_velocity = Vector3.ZERO
	if terrain_data != null and ground <= TerrainData.SEA_LEVEL + 0.05:
		drown()
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
	# Only re-pick on the redirect timer — NOT when the path is empty. A flee
	# hop clamped short by a cliff (or blocked entirely) exhausts its path in a
	# frame; re-picking on `not _has_path()` then ran _pick_panic_target (with a
	# fresh PackedVector3Array) EVERY frame for every cliff-blocked panicker —
	# an allocation storm that lagged swarm casts near cliffs (phase 7i fix).
	_panic_redirect -= delta
	if _panic_redirect <= 0.0:
		_panic_redirect = PANIC_REDIRECT_INTERVAL + randf() * 0.3
		_pick_panic_target()
	if _has_path():
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
	var target: Vector3
	if nav_grid != null:
		# March along the flee direction and stop before the first unwalkable
		# cell, so the straight (A*-less) panic hop never crosses a cliff/water
		# edge — panicking units used to clip up hard cliffs (phase 7i fix).
		target = _walkable_reach(Vector2(cos(angle), sin(angle)), dist)
	else:
		target = position + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		if terrain_data != null:
			target.y = terrain_data.get_height(target.x, target.z)
	_path = PackedVector3Array([target])
	_path_index = 0


## Furthest point up to `max_dist` along `dir` (XZ unit vector) whose whole
## straight segment stays on walkable ground; falls back to the current
## position when even the first step is blocked. Y snapped to the terrain.
func _walkable_reach(dir: Vector2, max_dist: float) -> Vector3:
	var flat: Vector2 = Vector2(position.x, position.z)
	var reached: Vector2 = flat
	var step: float = 0.5
	var d: float = step
	while d <= max_dist:
		var p: Vector2 = flat + dir * d
		if not nav_grid.is_cell_walkable(nav_grid.world_to_cell(Vector3(p.x, 0.0, p.y))):
			break
		reached = p
		d += step
	var y: float = terrain_data.get_height(reached.x, reached.y) if terrain_data != null else 0.0
	return Vector3(reached.x, y, reached.y)


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
## Returns false when this unit cannot be converted. Rolling, airborne and
## panicking units finish their tumble first (phase 7f roll hardening —
## a preacher must not yank a rolling unit into SIT mid-air).
func begin_conversion(preacher: Unit, duration: float) -> bool:
	if state == State.DEAD or state == State.SIT or is_conversion_immune():
		return false
	if garrison_housed:
		return false   # tower crew are a protected reserve (phase 7h)
	if state == State.ROLL or state == State.THROWN or state == State.PANIC:
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
	leave_crew()   # a converted crew member no longer serves the old engine
	if tribe != null:
		tribe.remove_unit(self)
	tribe_id = new_tribe.id
	new_tribe.add_unit(self)
	converting_preacher = null
	conversion_progress = 0.0
	last_attacker = null
	_end_attack()
	_clear_building_target()
	_dissolve_own_group()   # everyone fighting the (now friendly) unit retargets
	selected = false
	_set_state(State.IDLE)
	converted.emit(self)


# --- Siege crew (phase 7f) ---------------------------------------------------------

## Assigns this unit to a siege engine's crew (right-click on the engine, the
## workshop's auto-manning or the AI). The engine validates tribe/capacity;
## refused assignments are silently ignored. Shamans never crew.
func order_crew(engine) -> void:
	if not can_take_orders() or not can_crew_siege():
		return
	if engine == null or not is_instance_valid(engine) or engine.state == State.DEAD:
		return
	if siege_engine == engine and state == State.CREW:
		return
	route_end_action = Callable()
	_on_combat_interrupt()
	_end_attack()
	if not engine.add_crew(self):
		return
	leave_crew(engine)   # drop a previous engine's slot (keep the new one)
	siege_engine = engine
	siege_boarded = false
	waypoint_queue.clear()
	_clear_path()
	_set_state(State.CREW)


## Drops the crew membership (new order, conversion, death). `except` keeps
## a just-joined engine untouched when switching engines.
func leave_crew(except = null) -> void:
	var engine = siege_engine
	siege_engine = null
	siege_boarded = false
	if engine != null and engine != except and is_instance_valid(engine):
		engine.remove_crew(self)
	if state == State.CREW:
		_clear_path()
		_set_state(State.IDLE)


## Walks to (and holds) the side slot the engine assigned. Boarding is flagged
## on first contact; the engine's tick handles ownership, leash and re-summons
## after self-defence fights. While following, the crew moves at the ENGINE's
## speed (with a small lag boost) so it glides in lockstep and shows the walk
## animation — a faster crew used to dash-and-wait, which looked like the
## crew teleporting alongside (user feedback).
func _tick_crew(delta: float) -> void:
	var engine = siege_engine
	if engine == null or not is_instance_valid(engine) or engine.state == State.DEAD:
		leave_crew()
		return
	# Not yet aboard: walk over to board — at the crew member's own speed.
	if not siege_boarded:
		if _flat_dist(position, engine.position) <= engine.BOARD_RANGE:
			engine.on_crew_boarded(self)
			if siege_engine != engine:
				return   # boarding was refused (enemy took it meanwhile)
		else:
			_crew_walking = true
			_approach(engine.position, delta)
			return
	# Boarded: keep the side slot, gliding at the engine's speed.
	var slot: Vector3 = engine.crew_slot_position(self)
	var flat: Vector2 = Vector2(position.x, position.z)
	var flat_slot: Vector2 = Vector2(slot.x, slot.z)
	var to: Vector2 = flat_slot - flat
	var d: float = to.length()
	if d <= 0.08:
		_crew_walking = false
		if engine.facing.length_squared() > 0.000001:
			facing = engine.facing   # stand aligned with the vehicle
		_snap_to_ground()
		return
	_crew_walking = true
	facing = Vector3(to.x, 0.0, to.y).normalized()
	# Engine speed keeps formation smooth; a boost recovers from turns/boarding.
	var spd: float = engine.speed if d < 1.2 else engine.speed * 2.0
	var step: float = minf(spd * delta, d)
	var nxt: Vector2 = flat + to.normalized() * step
	position.x = nxt.x
	position.z = nxt.y
	_snap_to_ground()


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
	var enemy: Unit = _scan_for_enemy(aggro_radius())
	if enemy != null:
		_begin_attack(enemy)
		return true
	# Buildings are the LOWEST-priority target: only when no enemy unit is near
	# (phase 7g — attack-move / idle scan sieges an enemy building it can reach).
	return _try_engage_building()


## Pursues the current target and strikes it when in range. The combat-group
## binding (phase 8.2) decides the role: attackers hold a ring slot on the
## defender, the defender brawls its opponent directly (no slot needed — the
## pair IS the fight), waiters hold the second row until a slot frees. Bound
## fighters run NO enemy scans (the group is the target binding) — only the
## second row keeps its throttled look for a fight with room.
func _tick_attack(delta: float) -> void:
	# A converted target became friendly mid-fight -> drop it (or fall back to a
	# building assault, phase 7g).
	if not _target_valid(attack_target) or attack_target.tribe_id == tribe_id:
		_tick_no_unit_target(delta)
		return
	if _breaks_off_vs_sitting(attack_target):
		return
	var target: Unit = attack_target
	var g = combat_group
	# (Re)bind when the group link is missing or stale (target switched, the
	# group dissolved, direct set_path interference, ...).
	if g == null or (g.defender != self and g.defender != target):
		_bind_to_fight(target, true)
		g = combat_group
	_combat_waiting = false
	if g != null and g.defender == target and g.attacker_index(self) < 0:
		# Second row: hold the waiting ring; a throttled scan may find a fight
		# with a free seat instead (nearest group with room / fresh 1v1).
		_in_melee = false
		_combat_waiting = true
		if _due_to_scan(delta):
			var alt: Unit = _scan_for_enemy(aggro_radius())
			if alt != null and alt != target \
					and _melee_engage_cost(alt) < MAX_MELEE_ATTACKERS:
				_begin_attack(alt)
				return
		_wait_near(target, delta)
		return
	var dist: float = _flat_dist(position, target.position)
	if dist > MELEE_RANGE:
		_in_melee = false
		var dest: Vector3 = target.position
		if g != null and g.defender == target:
			var slot: int = g.attacker_index(self)
			if slot >= 0:
				dest = target.melee_slot_position(slot)
		if not _approach(dest, delta):
			# Unreachable (A* failed, e.g. an enemy up on a cliff): remember it
			# briefly and disengage instead of running into the wall (phase 8.2).
			_mark_target_unreachable(target)
			_retarget_or_idle()
			return
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
	# Never lock onto a non-targetable unit (a siege engine / a garrisoned tower
	# crew): attackers go for the crew instead, so a stray scan must not leave
	# them swinging at the vehicle for no damage. The only exception is a
	# catapult bombarding another catapult (_may_target_vehicle).
	if not enemy.is_targetable() and not _may_target_vehicle(enemy):
		return
	if attack_target == enemy:
		if state != State.ATTACK:
			_set_state(State.ATTACK)
		return
	garrison_target = null   # a fresh fight abandons a pending garrison approach
	route_end_action = Callable()
	_on_combat_interrupt()
	_end_attack()
	attack_target = enemy
	_attack_cooldown = 0.0
	_combat_goal = Vector3.INF
	# Melee units bind into the target's fight right away (pairing rules);
	# ranged units fire without a group seat and only brawl via
	# request_melee_slot when someone closes in.
	if not _is_ranged():
		_bind_to_fight(enemy, true)
	_set_state(State.ATTACK)


## Public order entry used by TribeCommands.order_attack (UI + AI).
func order_attack(enemy: Unit) -> void:
	_begin_attack(enemy)


## Whether this unit may attack a non-targetable vehicle directly. Only a
## catapult may bombard another catapult (its shot's splash hits the crew);
## every other unit targets the crew, never the vehicle. The siege engine
## overrides this.
func _may_target_vehicle(_enemy: Unit) -> bool:
	return false


# --- Building assault (phase 7g) ----------------------------------------------

## Untyped (freed-safe): true while our building target is a live enemy building.
func _building_target_valid() -> bool:
	return attack_building != null and is_instance_valid(attack_building) \
		and attack_building.health > 0 and attack_building.tribe_id != tribe_id


## Explicit order (right-click, AI, TribeCommands) to assault an enemy building.
## Every unit type accepts it (braves storm only on this explicit order); the
## route is cleared. Firewarriors bombard, everyone else storms the entrance.
func order_attack_building(building) -> void:
	if building == null or not is_instance_valid(building) or building.health <= 0:
		return
	if building.tribe_id == tribe_id or not can_take_orders():
		return
	if not building.is_assailable_by_units():
		return   # e.g. the reincarnation site — units cannot assault it
	_on_combat_interrupt()
	_end_attack()
	waypoint_queue.clear()
	attack_building = building
	_set_state(State.ATTACK)


## Auto-engage a building found by the idle / attack-move scan: keeps the
## pending route (attack-move resumes after the building falls).
func _begin_attack_building(building) -> void:
	if not can_take_orders():
		return
	_on_combat_interrupt()
	_end_attack()
	attack_building = building
	_set_state(State.ATTACK)


func _clear_building_target() -> void:
	attack_building = null


## Throttled lowest-priority scan: engage the nearest enemy building within the
## (slightly larger) building-engage radius. Only reached when no enemy unit was
## found in the normal aggro radius (units always take priority).
func _try_engage_building() -> bool:
	var b = _scan_for_enemy_building(maxf(aggro_radius(), BUILDING_ENGAGE_RADIUS))
	if b == null:
		return false
	_begin_attack_building(b)
	return true


## Nearest living enemy building within `radius` (null without a manager /
## in bare tests). Iteration is capped like the unit scan (hot-path rule).
func _scan_for_enemy_building(radius: float):
	if building_manager == null:
		return null
	var best = null
	var best_d: float = radius
	var checked: int = 0
	var ranged: bool = _is_ranged()
	for b in building_manager.buildings:
		if not is_instance_valid(b) or b.tribe_id == tribe_id or b.health <= 0:
			continue
		if not b.is_assailable_by_units():
			continue   # e.g. the reincarnation site — only spells/catapults harm it
		# Melee raiders skip a building with no room left (all raider slots taken)
		# so overflow units do not keep re-targeting a full building; firewarriors
		# bombard from range and are unaffected by the raider cap.
		if not ranged and not b.has_raider_room():
			continue
		checked += 1
		if checked > SCAN_MAX_CANDIDATES:
			break
		var d: float = _flat_dist(b.center_world(), position)
		if d <= best_d:
			best_d = d
			best = b
	return best


## No live unit target in ATTACK: fall back to the (lowest-priority) building
## assault, else re-target / idle. While sieging, an enemy unit that comes into
## aggro still takes precedence (buildings are always last).
func _tick_no_unit_target(delta: float) -> void:
	if attack_target != null:
		_end_attack()   # clear a stale/dead unit target and its slot
	if _building_target_valid():
		if _is_combatant() and _due_to_scan(delta):
			var enemy: Unit = _scan_for_enemy(aggro_radius())
			if enemy != null:
				_begin_attack(enemy)
				return
		_assault_building(delta)
		return
	_clear_building_target()
	_retarget_or_idle()


## Assault dispatch: firewarriors bombard from range, everyone else storms in.
func _assault_building(delta: float) -> void:
	if _is_ranged():
		_bombard_building(attack_building, delta)
	else:
		_storm_building(attack_building, delta)


## Melee raider. #2 (harder to raze): the entrance must be CLEAR of enemies
## before anyone demolishes — a live defender / ejected occupant near the door
## is fought first (preacher: converted). Only when clear does the unit enter as
## a raider (removed from the world, demolishing inside). Entry is ONLY through
## the entrance (RAID_ENTER_RANGE) — units path around the footprint to the door
## rather than clipping in through the nearest wall. When the building is FULL
## the unit gives up (idle / resume attack-move) instead of standing around.
func _storm_building(building, delta: float) -> void:
	var foe: Unit = building.nearest_entrance_threat()
	if foe != null:
		_engage_assault_foe(foe)   # clear the doorway first (keeps attack_building)
		return
	var entrance: Vector3 = building.entrance_world()
	if _flat_dist(position, entrance) > RAID_ENTER_RANGE:
		_in_melee = false
		_approach(entrance, delta)
		_face_point(entrance)
		return
	if not building.has_raider_room():
		_clear_building_target()
		_retarget_or_idle()
		return
	building.begin_storm()   # throw occupants out (once) -> they become threats
	foe = building.nearest_entrance_threat()
	if foe != null:
		_engage_assault_foe(foe)   # fight the just-ejected occupants before entering
		return
	_in_melee = false
	building.admit_raider(self)   # entrance clear + room -> demolish inside


## Engages a threat encountered while assaulting a building. attack_building is
## preserved, so once the threat is cleared the assault resumes (via
## _retarget_or_idle). The preacher overrides this to CONVERT convertible foes.
func _engage_assault_foe(foe: Unit) -> void:
	_begin_attack(foe)


## Ranged building bombardment (firewarrior override). Base units do not bombard
## buildings.
func _bombard_building(_building, _delta: float) -> void:
	pass


## Enters `building` as a melee raider: already removed from the world by the
## building, so just settle the state (stops ticking until ejected/collapse).
func enter_building_as_raider(building) -> void:
	raiding_building = building
	attack_building = null
	waypoint_queue.clear()
	_clear_path()
	selected = false
	_set_state(State.RAID)


## Steps back out at `pos` (the building re-registered the unit). When a valid
## enemy `building` is given (ejected to fight a threat), the unit RESUMES the
## assault (fight the threat, then re-enter when clear); otherwise — the building
## collapsed — it goes idle.
func exit_building_as_raider(pos: Vector3, building = null) -> void:
	raiding_building = null
	position = pos
	_snap_to_ground()
	if building != null and is_instance_valid(building) and building.health > 0 \
			and building.tribe_id != tribe_id and building.is_assailable_by_units():
		attack_building = building
		_set_state(State.ATTACK)
	else:
		_set_state(State.IDLE)


# --- Watchtower garrison (phase 7h) -------------------------------------------

## True for units that may man a watchtower: combat units and the shaman, never
## braves or siege engines.
func can_garrison() -> bool:
	return _is_combatant() or unit_kind() == &"shaman"


## Orders the unit to garrison an own watchtower: it walks to the entrance and
## is admitted (up to the tower's crew capacity). Rejected for braves/siege, a
## foreign or unusable/full tower, or while the unit is beyond control.
func order_garrison(tower) -> void:
	if not can_take_orders() or not can_garrison():
		return
	if tower == null or not is_instance_valid(tower) or tower.health <= 0:
		return
	if tower.tribe_id != tribe_id or not tower.is_usable() or not tower.has_crew_room():
		return
	route_end_action = Callable()
	_on_combat_interrupt()
	_end_attack()
	_clear_building_target()
	waypoint_queue.clear()
	_clear_path()
	garrison_target = tower
	garrison_reached = false
	_set_state(State.GARRISON)


## Walks to the tower entrance and waits there to be admitted. The tower does
## the actual admission on ITS tick (see Watchtower._admit_arrived_crew), so the
## live units list is never mutated from inside the unit loop. Gives up (idle)
## when the tower is gone / unusable / full.
func _tick_garrison(delta: float) -> void:
	var t = garrison_target
	if t == null or not is_instance_valid(t) or t.health <= 0 \
			or not t.is_usable() or t.tribe_id != tribe_id:
		garrison_target = null
		garrison_reached = false
		_set_state(State.IDLE)
		return
	# Head for the door but count as "arrived" once anywhere at the building
	# (within interact_range of the centre): the direct-step approach can be
	# blocked by the footprint corner right at the entrance, which used to leave
	# the unit oscillating just outside the strict entrance range forever.
	if _flat_dist(position, t.center_world()) > t.interact_range():
		garrison_reached = false
		_in_melee = false
		_approach(t.entrance_world(), delta)
		_face_point(t.center_world())
		return
	if not t.has_crew_room():
		garrison_target = null
		garrison_reached = false
		_set_state(State.IDLE)
		return
	if _has_path():
		_clear_path()
	_face_point(t.center_world())
	garrison_reached = true   # wait here; the tower admits us on its tick


## Called by the tower when admitted: the unit STAYS in the world (visible on
## the platform, rendered/animated by the renderer) but stops its own tick — the
## tower drives its position, facing, animation and ranged fire. It becomes a
## protected reserve (non-targetable, immune to the separation push, no orders).
func enter_garrison(tower, slot_pos: Vector3) -> void:
	garrison_target = tower
	garrison_housed = true
	garrison_reached = false
	push_immune = true
	waypoint_queue.clear()
	_clear_path()
	_end_attack()
	_clear_building_target()
	_dissolve_own_group()   # a protected reserve is no fight target (phase 8.2)
	selected = false
	position = slot_pos
	anim_base_name = &"idle"
	anim_start_ms = Time.get_ticks_msec()
	_set_state(State.GARRISON)


## Released from the tower (ejection / storm / damage / destruction): back to a
## normal world unit, go idle. The tower repositions it on the ground first.
func leave_garrison() -> void:
	garrison_target = null
	garrison_housed = false
	garrison_reached = false
	push_immune = false
	if state == State.GARRISON:
		_clear_path()
		_set_state(State.IDLE)


## Orders a BRAVE to man an own hut as production crew (phase 7i): it walks to
## the entrance (reusing the garrison approach) and the hut admits it. Rejected
## for non-braves, a foreign/unusable/full hut, or while beyond control.
func order_man_hut(hut) -> void:
	if unit_kind() != &"brave" or not can_take_orders():
		return
	if hut == null or not is_instance_valid(hut) or hut.health <= 0:
		return
	if hut.tribe_id != tribe_id or not hut.is_usable() or not hut.has_crew_room():
		return
	route_end_action = Callable()
	_on_combat_interrupt()
	_end_attack()
	_clear_building_target()
	waypoint_queue.clear()
	_clear_path()
	garrison_target = hut
	garrison_reached = false
	_set_state(State.GARRISON)


## Called by a hut when admitted as crew: like a garrison, but the hut also
## removes the brave from the world (hidden reserve). It keeps counting toward
## population; reuses the garrison_housed machinery (leave_garrison releases it).
func enter_hut(hut) -> void:
	garrison_target = hut
	garrison_housed = true
	garrison_reached = false
	push_immune = true
	waypoint_queue.clear()
	_clear_path()
	_end_attack()
	_clear_building_target()
	selected = false
	_set_state(State.GARRISON)


## Clears our attack and releases our seat in the fight (attacker/waiter; a
## freed slot is back-filled from the second row). A DEFENDER keeps its group
## on _end_attack — the group is the others' fight against us and only
## dissolves when we die, convert or leave the world.
func _end_attack() -> void:
	_leave_combat_group()
	attack_target = null
	_in_melee = false
	_combat_waiting = false
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
	# Self-defence continuity: someone is still meleeing US — fight the nearest
	# of our own group's attackers (no scan; the fight stays in the group).
	var own = combat_group
	if own != null and own.defender == self:
		var foe = own.nearest_attacker(position)
		if foe != null:
			_begin_attack(foe)
			return
	if _is_combatant():
		var enemy: Unit = _scan_for_enemy(aggro_radius())
		if enemy != null:
			_begin_attack(enemy)
			return
	# No enemy unit left: keep sieging a targeted building (phase 7g) before
	# giving up. Buildings are always the lowest-priority target.
	if _building_target_valid():
		_set_state(State.ATTACK)
		return
	# Combat over: resume a pending (attack-)move to its destination instead of
	# stopping where the fight ended — an attack-move must carry on to its
	# target point once the area is clear (applies to every unit).
	if not waypoint_queue.is_empty():
		_start_path_to(waypoint_queue[0])
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
	if state == State.IDLE or state == State.CREW:
		# Siege crew defends itself, leaving its post if necessary — it stays
		# crew (leash rule) and returns to the engine after the fight.
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


## Nearest enemy in radius, scored by the group-slot cost (free enemies and
## open seats first — 1v1 preference structurally). Candidates come from the
## ring-ordered, enemies-only query (phase 8.2): friendly units no longer
## consume the candidate budget (blob blindness) and buckets are visited
## outward from the own cell (no NW-first direction bias).
func _scan_for_enemy(radius: float, max_examined: int = 0) -> Unit:
	if path_service == null:
		return null
	var flat: Vector2 = Vector2(position.x, position.z)
	var best: Unit = null
	var best_score: float = INF
	var ranged: bool = _is_ranged()
	var now: int = Time.get_ticks_msec()
	var check_unreach: bool = not _unreach_targets.is_empty()
	if max_examined <= 0:
		max_examined = UnitManager.SCAN_MAX_EXAMINED
	for u in path_service.get_enemy_candidates(position, radius, tribe_id,
			SCAN_MAX_CANDIDATES, max_examined):
		if u == self:
			continue
		if u.state == State.SIT:
			continue   # sitting converts are no threat (and shall keep sitting)
		if check_unreach \
				and int(_unreach_targets.get(u.get_instance_id(), 0)) > now:
			continue   # recently proven unreachable (up on a cliff, phase 8.2)
		var d: float = Vector2(u.position.x, u.position.z).distance_to(flat)
		# The engage cost dominates the score so free enemies / open seats are
		# picked first (1-vs-N pairing); ranged units fire without a seat.
		var score: float = d
		if not ranged:
			score += float(_melee_engage_cost(u)) * 1000.0
		if score < best_score:
			best_score = score
			best = u
	return best


# --- Combat groups (phase 8.2) --------------------------------------------------

## Cost of engaging `u` in melee under the pairing rules: 0 = free (ungrouped /
## waiter / one of our own attackers), 1..2 = joins or reshapes an existing
## fight, >= 10 = full group (second row). Used as the scan score's major key.
func _melee_engage_cost(u: Unit) -> int:
	var g = u.combat_group
	if g == null:
		return 0
	if g == combat_group and g.defender == self:
		return 0   # one of OUR own attackers — that is our fight anyway
	if g.defender == u:
		var n: int = g.attackers.size()
		if n < MAX_MELEE_ATTACKERS:
			return n
		return 10 + g.waiters.size()
	if g.is_waiter(u):
		return 0   # waiting around someone else's fight: free for a 1v1
	return 1   # fighting elsewhere: flip (1v1 -> 2v1) or pull (fresh 1v1)


## Binds this (melee) unit into `enemy`'s fight following the 1-vs-N pairing
## rules (phase 8.2): free enemy -> found a new group on it; enemy defending
## with a free seat -> take it; full -> second row (allow_wait) or -1; enemy
## fighting as attacker/waiter elsewhere -> flip its 1v1 into a 2v1, or PULL
## it out into a fresh 1v1 (latecomer rule: 1v3 -> 1v2 + 1v1). Returns the
## attacker slot index, or -1 (second row / no seat).
func _bind_to_fight(enemy: Unit, allow_wait: bool) -> int:
	if enemy == null or not is_instance_valid(enemy) or enemy.state == State.DEAD:
		return -1
	# A unit DEFENDING its own live fight keeps that seat, whoever it swings
	# at (retaliation may pick an outside enemy, e.g. a ranged attacker): the
	# pairing structure hangs on the defender seat, not on its target choice.
	# Only an empty leftover group is released so the seat frees up.
	var own = combat_group
	if own != null and own.defender == self:
		if own.is_alive():
			return 0
		own.release_all()
	var g = enemy.combat_group
	if g != null and g == combat_group:
		# Same fight already: we hold a seat / wait here.
		return g.attacker_index(self)
	if g == null:
		_found_group_on(enemy)
		return 0
	if g.defender == enemy:
		var idx: int = g.attacker_index(self)
		if idx >= 0:
			return idx
		g.prune()
		if g.attackers.size() < MAX_MELEE_ATTACKERS:
			_leave_combat_group()
			g.attackers.append(self)
			combat_group = g
			return g.attackers.size() - 1
		if allow_wait and not g.is_waiter(self):
			_leave_combat_group()
			g.waiters.append(self)
			combat_group = g
		return -1
	if g.is_waiter(enemy):
		# A second-row waiter is effectively free: grab it into a fresh 1v1.
		g.remove_member(enemy)
		_found_group_on(enemy)
		enemy._switch_target_to(self)
		return 0
	# Enemy fights as an ATTACKER in another group.
	g.prune()
	if g.attackers.size() <= 1:
		# FLIP: its 1v1 becomes a 2v1 on the enemy — the old defender turns
		# into a fellow attacker (if it is actually brawling back) and we join.
		var od = g.defender
		g.attackers.erase(enemy)
		for w in g.waiters:
			if w != null and is_instance_valid(w) and w.combat_group == g:
				w.combat_group = null   # rebind on their next tick
		g.waiters.clear()
		g.defender = enemy
		g.anchor = enemy.position
		if od != null and is_instance_valid(od) and od.combat_group == g:
			if od.state != State.DEAD and od.attack_target == enemy:
				g.attackers.append(od)   # stays bound, now as a fellow attacker
			else:
				od.combat_group = null   # was not fighting back: unbound
		_leave_combat_group()
		g.attackers.append(self)
		combat_group = g
		return g.attackers.size() - 1
	# PULL (latecomer of the outnumbered side): take the enemy out of its
	# crowded group (1v3 -> 1v2); it defends a fresh 1v1 against us.
	g.remove_member(enemy)
	_found_group_on(enemy)
	enemy._switch_target_to(self)
	return 0


## Founds a fresh group with `enemy` as its defender and us as the first
## attacker; registered with the manager for the anchor/min-distance pass.
func _found_group_on(enemy: Unit) -> void:
	_leave_combat_group()
	var fresh: CombatGroup = CombatGroup.new()
	fresh.defender = enemy
	fresh.anchor = enemy.position
	fresh.attackers.append(self)
	enemy.combat_group = fresh
	combat_group = fresh
	if path_service != null:
		path_service.register_combat_group(fresh)


## Direct opponent swap while already fighting (pulled out of a group /
## grabbed as a waiter): the puller becomes the new target, nothing else
## changes — the group bookkeeping happened at the pull site.
func _switch_target_to(u: Unit) -> void:
	if state != State.ATTACK or u == null or not is_instance_valid(u):
		return
	attack_target = u
	_in_melee = false
	_combat_goal = Vector3.INF


## Releases our attacker/waiter seat (never the defender role — see
## _end_attack); the group back-fills the slot from the second row.
func _leave_combat_group() -> void:
	var g = combat_group
	if g == null:
		return
	if g.defender == self:
		return
	combat_group = null
	g.remove_member(self)


## Dissolves the fight we DEFEND (death, conversion, leaving the world,
## engaging elsewhere): every attacker and waiter is unbound and retargets.
func _dissolve_own_group() -> void:
	var g = combat_group
	if g == null or g.defender != self:
		return
	combat_group = null
	g.defender = null
	var members: Array = g.attackers.duplicate()
	members.append_array(g.waiters)
	g.attackers.clear()
	g.waiters.clear()
	for m in members:
		if m != null and is_instance_valid(m) and m.combat_group == g:
			m.combat_group = null
			m._on_target_died(self)


## Remembers a combat target as unreachable for a short while (scans skip it,
## _tick_attack disengages) — bounded, so a mass of blocked chasers does not
## re-run the expensive failing A* every scan (Bergpass fix, phase 8.2).
func _mark_target_unreachable(target: Unit) -> void:
	if _unreach_targets.size() >= UNREACHABLE_CACHE_MAX:
		_unreach_targets.clear()
	_unreach_targets[target.get_instance_id()] = \
		Time.get_ticks_msec() + UNREACHABLE_TARGET_MS


## Registers `attacker` as a melee attacker on this unit's fight (pairing
## rules; NO second-row fallback — the ranged self-defence brawl of the
## firewarrior fires from the reserve row instead of queueing). Returns the
## slot index (0..MAX-1) or -1. Untyped param (freed-safe).
func request_melee_slot(attacker) -> int:
	if attacker == null or not is_instance_valid(attacker) \
			or attacker.state == State.DEAD:
		return -1
	return attacker._bind_to_fight(self, false)


## Releases `attacker`'s seat on this unit's fight (a freed slot is
## back-filled from the second row).
func release_melee_slot(attacker) -> void:
	var g = combat_group
	if g != null and g.defender == self:
		g.remove_member(attacker)


func active_melee_attacker_count() -> int:
	var g = combat_group
	if g == null or g.defender != self:
		return 0
	g.prune()
	return g.attackers.size()


## Ring position for slot index around this (target) unit.
func melee_slot_position(slot: int) -> Vector3:
	var angle: float = TAU * float(slot) / float(MAX_MELEE_ATTACKERS)
	return position + Vector3(cos(angle) * MELEE_SLOT_RADIUS, 0.0, sin(angle) * MELEE_SLOT_RADIUS)


# --- Combat movement ----------------------------------------------------------

## Approaches `dest`: A* while far (avoids water/obstacles), direct step when
## close (combat is chaotic and short-range — no need to re-path every metre).
## Returns false when the destination is UNREACHABLE (A* failed) — the caller
## decides; the old blind direct-step fallback made blocked chasers run into
## cliff walls forever (Bergpass, phase 8.2).
func _approach(dest: Vector3, delta: float) -> bool:
	if _flat_dist(position, dest) > COMBAT_DIRECT_RANGE and nav_grid != null:
		if not _has_path() or _flat_dist(_combat_goal, dest) > 1.0:
			_combat_goal = dest
			if not _plan_path_to(dest):
				return false
		if _advance_path(delta):
			_clear_path()
		return true
	_step_toward(dest, delta)
	return true


## Second-row waiter holds position near its group's fight. Standing ANYWHERE
## close enough is fine: chasing an exact ring point that moves with the
## target coupled the movements (waiter follows its ring point, the pursuer
## follows the waiter's slot, ...) — whole blocks of units jogged after each
## other forever, never striking. Only units too far out close up (to a
## deterministic per-unit ring point, so they spread). The ring is centred on
## the group ANCHOR (follows the defender lazily) instead of sticking to the
## target's every step.
func _wait_near(target: Unit, delta: float) -> void:
	var center: Vector3 = target.position
	var g = combat_group
	if g != null and g.defender == target \
			and _flat_dist(g.anchor, target.position) <= MELEE_WAIT_RADIUS * 2.0:
		center = g.anchor
	if _flat_dist(position, center) > MELEE_WAIT_RADIUS + 0.6:
		var angle: float = float(get_instance_id() % 628) * 0.01
		var dest: Vector3 = center + Vector3(
			cos(angle) * MELEE_WAIT_RADIUS, 0.0, sin(angle) * MELEE_WAIT_RADIUS)
		_step_toward(dest, delta)
	_face_point(target.position)


## Moves directly toward a point on the XZ plane (no pathing), snapping Y.
## Uphill slopes slow the step like regular path movement. The step is
## dropped when it would leave walkable ground — direct combat pursuit must
## not drag brawls into the sea or off the map (the A* branch of _approach
## avoids those on its own; this is the short-range chase).
func _step_toward(point: Vector3, delta: float) -> void:
	var flat: Vector2 = Vector2(position.x, position.z)
	var flat_target: Vector2 = Vector2(point.x, point.z)
	var to_target: Vector2 = flat_target - flat
	if to_target.length_squared() > 0.000001:
		facing = Vector3(to_target.x, 0.0, to_target.y).normalized()
	var next: Vector2 = flat.move_toward(flat_target, _slope_speed(_slope_ahead(to_target)) * delta)
	if nav_grid != null and not nav_grid.is_cell_walkable(
			nav_grid.world_to_cell(Vector3(next.x, 0.0, next.y))):
		return
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


## Maps a 45-degree sector (0 = along camera forward = back view, +1 per 45 deg
## clockwise toward camera-right) to the matching PlaceholderSprites.VIEWS index.
## Index 0..3 stay front/back/right/left for compatibility; 4..7 are the
## diagonals. Lookup table = pure arithmetic on the hot path (no branch cascade).
const SECTOR_TO_VIEW: Array[int] = [1, 6, 2, 4, 0, 5, 3, 7]

## Which of the eight sprite views matches a facing direction, given the
## camera's forward and right vectors. Returns an index into
## PlaceholderSprites.VIEWS (0 = front, 1 = back, 2 = right, 3 = left,
## 4 = front_right, 5 = front_left, 6 = back_right, 7 = back_left).
## Static + camera-free so it is headless-testable. Runs per unit per frame:
## the sector comes from a single atan2 (22.5 deg boundaries), not a cascade.
static func view_index(p_facing: Vector3, cam_forward: Vector3, cam_right: Vector3) -> int:
	var flat_facing: Vector2 = Vector2(p_facing.x, p_facing.z)
	var flat_forward: Vector2 = Vector2(cam_forward.x, cam_forward.z)
	if flat_facing.length_squared() < 0.000001 or flat_forward.length_squared() < 0.000001:
		return 0
	# Normalise the camera axes (the flattened forward loses length when the
	# camera is pitched); the facing magnitude cancels inside atan2.
	flat_forward = flat_forward.normalized()
	var flat_right: Vector2 = Vector2(cam_right.x, cam_right.z).normalized()
	var dot_forward: float = flat_facing.dot(flat_forward)
	var dot_right: float = flat_facing.dot(flat_right)
	var sector: int = roundi(atan2(dot_right, dot_forward) / (PI / 4.0))
	return SECTOR_TO_VIEW[(sector + 8) % 8]


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
			# The rolled strike's animation while fighting; walk while closing
			# in; the second row stands calm instead of walking in place.
			if _in_melee:
				return attack_anim
			return &"idle" if _combat_waiting else &"walk"
		State.CAST:
			return &"cast"
		State.SIT:
			return &"sit"
		State.ROLL, State.THROWN:
			return &"roll"
		State.DEAD:
			return &"dead"
		State.CREW:
			return &"walk" if _crew_walking else &"idle"
		State.GARRISON:
			return &"walk"   # walking to the tower (housed units are not rendered)
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
