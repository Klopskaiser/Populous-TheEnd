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
const MELEE_RANGE: float = Balance.MELEE_RANGE
## Attackers pursue direct (no A*) once this close; farther away they path.
const COMBAT_DIRECT_RANGE: float = 2.5
## Combat units auto-attack enemies within this radius while idle. Braves do NOT
## (they only retaliate when attacked — see _maybe_retaliate).
const AGGRO_RADIUS: float = Balance.MELEE_AGGRO_RADIUS
## Fleeing (passive move while being hit in melee): every this many hits the
## unit falls back into fighting (self-defence) — escaping a brawl works, but
## not always on the first try. Deterministic, not per-frame random.
const FLEE_RETALIATE_HITS: int = 3
## An attacker counts as "in melee" for the flee rule within this range.
const FLEE_MELEE_RANGE: float = MELEE_RANGE * 1.5
## Seconds between melee strikes.
const ATTACK_COOLDOWN: float = Balance.ATTACK_COOLDOWN
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
const UNREACHABLE_CACHE_MAX: int = 32
## After a FAILED combat path plan (A* flooded the whole reachable region —
## the most expensive call there is), this unit plans no further combat paths
## for this long. Together with the unreachable cache this caps the failing-A*
## rate of units trapped under a cliff (Ebene-Klippen lag, user bug report).
const COMBAT_PATH_FAIL_COOLDOWN_MS: int = 800
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
const MELEE_PUNCH: int = Balance.MELEE_PUNCH
const MELEE_KICK: int = Balance.MELEE_KICK
const MELEE_SHOVE: int = Balance.MELEE_SHOVE
## Chance of a kick / shove on any given strike (else punch). The warrior
## overrides _shove_chance() to shove rarely (he punches/kicks instead).
const KICK_CHANCE: float = Balance.KICK_CHANCE
const SHOVE_CHANCE: float = Balance.SHOVE_CHANCE
## Fireball impact damage (slightly above a brave punch; thrown by the
## firewarrior from medium range, see Firewarrior/Fireball).
const FIREBALL_DAMAGE: int = Balance.FIREWARRIOR_FIREBALL_DAMAGE

## When an attack target sits down under a preacher's spell, its attackers
## break off — only this chance (rolled ONCE per attacker per sitting spell)
## keeps one fighting.
const SIT_ATTACK_CONTINUE_CHANCE: float = 0.05

## A defeated unit stays lying on the ground (dead sprite, no interaction) for
## this long, then sinks into the ground over CORPSE_SINK_DURATION and is removed.
const CORPSE_DURATION: float = Balance.CORPSE_DURATION
const CORPSE_SINK_DURATION: float = Balance.CORPSE_SINK_DURATION
## How deep the corpse sprite submerges while sinking (sprite height + margin,
## so nothing pokes out of slopes at the end).
const CORPSE_SINK_DEPTH: float = Balance.CORPSE_SINK_DEPTH

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
const ROLL_SPEED: float = Balance.ROLL_SPEED
## Duration of a flat-ground mini roll (shove / fireball knock-over).
const MINI_ROLL_DURATION: float = Balance.MINI_ROLL_DURATION
## Even shorter tumble for adjacent units knocked over by a fireball roll.
const NEIGHBOR_ROLL_DURATION: float = Balance.NEIGHBOR_ROLL_DURATION
## Rolling hurts a little, scaling with how long it lasts.
const ROLL_DPS: float = Balance.ROLL_DPS
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
const STEEP_ROLL_CHANCE_PER_SEC: float = Balance.STEEP_ROLL_CHANCE_PER_SEC

# --- Throw & panic (phase 6) ---------------------------------------------------------
## Gravity of scripted throw arcs (slightly snappy for gameplay feel).
const THROW_GRAVITY: float = 18.0
## Friction (m/s^2) that bleeds off a landing throw's roll speed on flat
## ground — thrown units tumble on and quickly come to a stop.
const ROLL_FRICTION: float = 6.0
## A speed-driven roll may end once its momentum decayed below this.
const ROLL_STOP_SPEED: float = 1.0

# --- Cliff fall (combat shove / roll over a cliff edge) ------------------------------
## Being shoved (combat/fireball) or rolling over a cliff edge launches the unit
## off it instead of stopping at the rim: fall damage scales with the drop
## (capped at 1/2 brave life) and it rolls away from the impact for a
## drop-scaled duration (capped at 2 s). Steep-but-walkable slopes never trigger.
const CLIFF_FALL_MIN_DROP: float = Balance.CLIFF_FALL_MIN_DROP
const CLIFF_PROBE_DIST: float = Balance.CLIFF_PROBE_DIST
const CLIFF_FALL_DAMAGE_PER_M: float = Balance.CLIFF_FALL_DAMAGE_PER_M
const CLIFF_FALL_MAX_DAMAGE: int = Balance.CLIFF_FALL_MAX_DAMAGE
const CLIFF_ROLL_PER_M: float = Balance.CLIFF_ROLL_PER_M
const CLIFF_ROLL_MAX_DURATION: float = Balance.CLIFF_ROLL_MAX_DURATION
const CLIFF_LAUNCH_SPEED: float = Balance.CLIFF_LAUNCH_SPEED
const CLIFF_LAUNCH_UP: float = Balance.CLIFF_LAUNCH_UP

## Panic effect duration (swarm) and how often a new flee direction is picked.
const PANIC_DURATION: float = Balance.PANIC_DURATION
const PANIC_REDIRECT_INTERVAL: float = 0.5
## Health fraction below which the one-time "badly hurt" sound plays.
const BADLY_HURT_FRAC: float = 0.25

# --- Melee shove (phase 5d) --------------------------------------------------------
## A shove always displaces the target slightly (the brawl shifts around)...
const SHOVE_DISPLACE: float = 0.35
## ...and sometimes knocks it over into a very short roll, even on flat ground.
const SHOVE_ROLL_CHANCE: float = Balance.SHOVE_ROLL_CHANCE

# --- Hill movement (phase 5d) ------------------------------------------------------
## Speed factor lost per unit of uphill slope (rise per metre)...
const UPHILL_SLOWDOWN: float = 0.45
## ...clamped so steep climbs stay possible.
const MIN_SPEED_FACTOR: float = 0.35

# --- Regeneration (phase 5d) ---------------------------------------------------------
## Seconds without ANY combat involvement (dealt/received damage, rolling)
## before slow healing starts.
const REGEN_DELAY: float = Balance.REGEN_DELAY
const REGEN_RATE: float = Balance.REGEN_RATE   # HP per second

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
## False for vehicles (set in CrewedVehicle._init): they never join the idle
## 6-packs — a parked ram must not drive off to a formation slot (user report:
## idle rams creeping toward each other). A FIELD like idle_aggro (hot path).
var joins_idle_groups: bool = true
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
## While riding an airship deck (State.CREW) the ship drives the combat anim
## here: unlike tower crew (housed, no tick), deck passengers tick and their own
## _apply_animation would reset the anim every frame — _anim_base() honours this
## instead. Empty = fall back to the plain crew idle/walk.
var crew_action_anim: StringName = &""

## SoA slot in the UnitManager registry (Stufe C1, plans/08d): index into the
## manager's `units` array and every soa_* array; -1 while unregistered. The
## packed-array refs below share the manager's storage (packed arrays are
## by-reference in Godot 4), so the hot position/state writers mirror their
## values without a manager call. The arrays are AUTHORITATIVE for the
## manager's hot loops — every position writer MUST double-write (a missed
## site produces ghost targets at stale positions).
var _idx: int = -1
var _soa_pos: PackedVector3Array
var _soa_state: PackedInt32Array
var _soa_flags: PackedInt32Array
## Combat/move-kernel arrays (Stufe C2, plans/08e): target handle + hold state.
var _soa_target: PackedInt32Array
var _soa_tgen: PackedInt32Array
var _soa_hold: PackedFloat32Array
var _soa_mode: PackedInt32Array
var _soa_scan: PackedFloat32Array
var _soa_wp: PackedVector3Array
var _soa_goal: PackedVector3Array
var _soa_kb: PackedFloat32Array
var _mgr_slot_gen: PackedInt32Array


## Called by UnitManager.register after the SoA slots were appended.
func _bind_soa(manager: UnitManager) -> void:
	_soa_pos = manager.soa_pos
	_soa_state = manager.soa_state
	_soa_flags = manager.soa_flags
	_soa_target = manager.soa_target
	_soa_tgen = manager.soa_tgen
	_soa_hold = manager.soa_hold
	_soa_mode = manager.soa_mode
	_soa_scan = manager.soa_scan
	_soa_wp = manager.soa_wp
	_soa_goal = manager.soa_goal
	_soa_kb = manager.soa_kb
	_mgr_slot_gen = manager._slot_gen


## Mirrors position into the manager's SoA arrays. Every writer that sets the
## position of a REGISTERED unit and does not end in _snap_to_ground must call
## this (see plans/08d C1 writer audit).
func _sync_soa_pos() -> void:
	var i: int = _idx
	if i >= 0:
		_soa_pos[i] = position


## Event-mirrored separation/scan flags (garrison, crew boarding, conversion
## immunity via targetable). Call after any input of _compute_soa_flags changed.
func _sync_soa_flags() -> void:
	if _idx >= 0:
		_soa_flags[_idx] = _compute_soa_flags()


func _compute_soa_flags() -> int:
	var f: int = 0
	if flies:
		f |= UnitManager.FLAG_FLIES
	if push_immune:
		f |= UnitManager.FLAG_PUSH_IMMUNE
	if is_crew_seated():
		f |= UnitManager.FLAG_CREW_SEATED
	if is_targetable():
		f |= UnitManager.FLAG_TARGETABLE
	if unit_kind() == &"preacher":
		f |= UnitManager.FLAG_PREACHER
	return f


## Mirrors attack_target into the SoA handle (slot index + generation, see
## UnitManager.soa_target) — call after EVERY attack_target write. A target
## without a live slot (unregistered, bare test) stores -1.
func _sync_soa_target() -> void:
	var i: int = _idx
	if i < 0:
		return
	var t: Unit = attack_target
	if t != null and is_instance_valid(t) and t._idx >= 0:
		_soa_target[i] = t._idx
		_soa_tgen[i] = _mgr_slot_gen[t._idx]
	else:
		_soa_target[i] = -1


## Opts this unit into the manager's STAND hold kernel (Stufe C2, plans/08e):
## from the NEXT tick_units on, the flat kernel services it over the arrays
## and its object tick is skipped, until the kernel (or an event) drops it
## back. Called from the stable in-range branches of _tick_attack (melee
## strike hold; firewarrior fire stand passes its scan timer + mode). Refuses
## units with per-tick object work pending (burning, knockback playout/decay).
func _enter_soa_hold(scan_timer: float = -1.0,
		mode: int = UnitManager.HOLD_MELEE) -> void:
	var i: int = _idx
	if i < 0 or _burn_time > 0.0 or _knockback_remaining != Vector3.ZERO:
		return
	var t: Unit = attack_target
	if t == null or not is_instance_valid(t):
		return
	var ti: int = t._idx
	if ti < 0:
		return
	_soa_target[i] = ti
	_soa_tgen[i] = _mgr_slot_gen[ti]
	# Stand modes park their cooldown in the hold slot; the waiter hold has
	# none and stores a plain held-marker.
	_soa_hold[i] = _attack_cooldown if mode <= UnitManager.HOLD_FIRE else 1.0
	_soa_mode[i] = mode
	_soa_scan[i] = scan_timer
	_soa_kb[i] = knockback_accum   # kernel-side decay while held


## Path-hold entry (C2.4): the kernel walks this unit toward `wp` (the current
## path waypoint) and drops it back for the waypoint switch, the stumble roll
## on steep downhill, or — chase modes — when the target needs a reaction
## (arrival in range, drift past the re-plan threshold, death/SIT/conversion).
## `goal` is the TARGET's position at plan time (chase drift check); the plain
## walk (HOLD_MOVE) passes no target. Same pending-work gates as the stand
## entry; additionally ground foot units only (vehicles/flyers keep their own
## movement code) and never without terrain (bare tests).
func _enter_soa_path_hold(mode: int, wp: Vector3, goal: Vector3 = Vector3.ZERO,
		scan_timer: float = -1.0) -> void:
	var i: int = _idx
	if i < 0 or _burn_time > 0.0 or _knockback_remaining != Vector3.ZERO:
		return
	if vehicle_separation > 0.0 or flies or terrain_data == null:
		return
	if mode != UnitManager.HOLD_MOVE:
		var t: Unit = attack_target
		if t == null or not is_instance_valid(t):
			return
		var ti: int = t._idx
		if ti < 0:
			return
		_soa_target[i] = ti
		_soa_tgen[i] = _mgr_slot_gen[ti]
	_soa_hold[i] = 1.0   # held-marker; path modes carry no cooldown
	_soa_mode[i] = mode
	_soa_scan[i] = scan_timer
	_soa_wp[i] = wp
	_soa_goal[i] = goal
	_soa_kb[i] = knockback_accum   # kernel-side decay while held


## Panic-hold entry (see _tick_panic): holds until the next redirect or the
## panic end, whichever comes first — both object timers are reconstructed
## from the elapsed held time on drop (entry value parked in goal.x).
func _enter_soa_panic_hold() -> void:
	var i: int = _idx
	if i < 0 or _burn_time > 0.0 or _knockback_remaining != Vector3.ZERO:
		return
	if vehicle_separation > 0.0 or flies or terrain_data == null:
		return
	var span: float = minf(_panic_time, _panic_redirect)
	if span <= 0.0:
		return
	_soa_hold[i] = span
	_soa_mode[i] = UnitManager.HOLD_PANIC
	_soa_scan[i] = -1.0
	_soa_wp[i] = _path[_path_index]
	_soa_goal[i] = Vector3(span, 0.0, 0.0)
	_soa_kb[i] = knockback_accum   # kernel-side decay while held


## Drops this unit out of the hold kernel (no-op when not held), writing the
## kernel-side timers back into the object fields (stand modes own the attack
## cooldown while held; path modes never touch it). MUST run on every event
## that gives a held unit per-tick object work again while its state stays
## unchanged (displace/knockback, ignite/scorch, target switch, a replaced
## path); state changes clear via _set_state.
func _clear_soa_hold() -> void:
	var i: int = _idx
	if i < 0 or _soa_hold.size() <= i or _soa_hold[i] < 0.0:
		return
	var mode: int = _soa_mode[i]
	if mode <= UnitManager.HOLD_FIRE:
		_attack_cooldown = _soa_hold[i]
	elif mode == UnitManager.HOLD_CORPSE:
		_corpse_timer = CORPSE_DURATION - _soa_hold[i]
	elif mode == UnitManager.HOLD_PANIC:
		var elapsed: float = _soa_goal[i].x - _soa_hold[i]
		_panic_time -= elapsed
		_panic_redirect -= elapsed
	_soa_hold[i] = -1.0
	if _soa_scan[i] >= 0.0:
		_target_search_timer = _soa_scan[i]
		_soa_scan[i] = -1.0
	knockback_accum = _soa_kb[i]   # kernel-decayed while held

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
## True while attack_target came from an EXPLICIT player/AI order (order_attack)
## rather than an auto-acquired scan. Ranged units (firewarrior, catapult) keep
## firing at an ordered target and do NOT auto-switch to nearby enemies while it
## stays valid — only melee self-defence still pulls them off. Cleared on
## _end_attack (any auto re-target goes through it) and on auto _begin_attack.
var _target_ordered: bool = false
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
## Maintained by UnitManager.register/unregister: false while the unit lives
## INSIDE a building (trainee, forester/workshop worker, raider, tower crew).
## Stale attack_target references onto such a unit must drop it (it would be
## struck invisibly at its old spot and could be yanked out of the building's
## bookkeeping without ever being re-registered — the "vanished trainee" bug).
var in_world: bool = true
## True while this unit stands at the tower entrance waiting to be admitted. The
## tower admits it on ITS tick (not here) so the units list is not mutated
## mid-iteration (same rationale as the training queue).
var garrison_reached: bool = false
## True while this brave walks to a hut on a MANUAL man order (player
## right-click): the hut then pins its crew size on admission (manual
## override). Cleared on admission, release, or when the approach is abandoned.
var man_hut_manual: bool = false
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
## No combat path planning before this tick (set after a failed A*).
var _combat_path_fail_until_ms: int = 0
## Corpse decay: seconds since death; corpse_expired fires once at the end.
var _corpse_timer: float = 0.0
var _corpse_done: bool = false

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
## Channel range the pacifying preacher converts at — a tower/deck preacher
## reaches further than the ground CONVERT_RANGE (set in begin_conversion).
var conversion_reach: float = 0.0
## True while THIS unit is a stationed preacher (tower crew / airship deck)
## channeling a conversion — the station tick drives it, there is no CAST
## state. Only honoured while the preacher is GARRISON/CREW (_tick_sit).
var station_channeling: bool = false

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
## Separation LAYER: flying vehicles (airship) only separate against other
## flyers, never against ground units/vehicles they pass over (and their Y is
## left to their own altitude logic, not snapped to the terrain).
var flies: bool = false
## Per-unit multiplier on the separation push speed — airships shove clear of
## each other far faster than ground units drift apart.
var separation_speed_mult: float = 1.0
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
## Roll duration applied on landing. Only a cliff fall sets a longer value
## (drop-scaled); tornado/fireball landings keep the default mini roll.
var _throw_roll_duration: float = MINI_ROLL_DURATION
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

# --- Regeneration state (phase 5d) ----------------------------------------------------
## Seconds since the last combat involvement; regen starts past REGEN_DELAY.
var _no_combat_timer: float = 0.0
var _regen_frac: float = 0.0
## Active status-effect bits + frame stamp, managed by the StatusFxRenderer
## (panic / burning / crit-damage loop sounds + icons).
var _status_fx_mask: int = 0
var _status_fx_seen: int = 0
## Cached Events bus (combat_hit emissions), resolved once when in-tree.
var _events_node: Node = null
var _events_checked: bool = false
## Cached AudioManager (positional one-shot sounds), resolved once when in-tree.
var _audio_node: Node = null
var _audio_checked: bool = false


## Silhouette key for PlaceholderSprites; overridden by subclasses.
func unit_kind() -> StringName:
	return &"unit"


## Sound key played on death (AudioManager._on_unit_died). Subclasses override:
## the shaman has her own cry, vehicles have burn/burst variants, the airship
## its own crash. Empty = silent.
func death_sfx_key() -> StringName:
	return &"unit_death"


## True for units that seek out enemies on their own while idle (Warrior/
## Firewarrior/Preacher). Braves are false: they only retaliate when hit.
func _is_combatant() -> bool:
	return false


## True for ranged units (firewarrior): any number may fire at one target, so
## the 3-attacker melee cap and its target redistribution do not apply to them.
func _is_ranged() -> bool:
	return false


## False for units that can never be attacked directly (the siege engine:
## attackers hit its crew instead), that are currently a protected reserve
## (tower crew, phase 7h — safe from fireballs/melee/conversion until ejected)
## or that left the live world into a building (in_world = false).
## Filtered in every enemy scan/order.
func is_targetable() -> bool:
	return in_world and not garrison_housed


## Drawn via the central sprite MultiMesh (UnitRenderer). The siege engine
## returns false and builds its own 3D model instead.
func renders_as_sprite() -> bool:
	return true


## Whether this unit may man a GROUND vehicle (everyone except the shaman and
## the vehicles themselves, phase 7f). The airship asks via its own
## accepts_crew_unit override instead (it also takes the shaman).
func can_crew_siege() -> bool:
	return unit_kind() != &"shaman" and unit_kind() != &"siege"


## True while boarded on ANY vehicle (ground siege/ram side slots or airship
## deck): the member is glued to its slot by _tick_crew and must be left alone by
## soft separation — otherwise it gets shoved off-slot and its Y snaps to terrain
## for a frame (flicker/vanish on slopes, plus an idle<->walk toggle, user bug).
func is_crew_seated() -> bool:
	return siege_boarded and siege_engine != null and is_instance_valid(siege_engine)


## True while riding a deck vehicle (airship) at altitude: boarded on a
## vehicle whose crew rides ON it instead of walking beside it.
func rides_airborne() -> bool:
	return is_crew_seated() and siege_engine.crew_rides_on_deck()


## In the air right now: thrown/whirled through the sky or riding an airship
## deck. Melee can never engage such targets, preachers cannot convert them,
## and firewarrior fireballs deal double damage against them.
func is_airborne() -> bool:
	return state == State.THROWN or rides_airborne()


## Scale of the selection ring (SelectionRingRenderer). The siege engine uses
## a big ring that visually encloses the vehicle AND its crew.
func selection_ring_scale() -> float:
	return 1.0


## Per-axis ring scale (x = width across facing, z = length along facing). The
## default is the uniform selection_ring_scale() (a circle); the airship
## overrides this with an elongated pair to frame its rectangular deck.
func selection_ring_extents() -> Vector2:
	var s: float = selection_ring_scale()
	return Vector2(s, s)


## When true the selection ring is rotated to the unit's facing (needed for a
## non-circular ring to line up with the hull); circular rings ignore it.
func selection_ring_oriented() -> bool:
	return false


## World-space clickable size (width x height, metres) for the screen-space
## pick rect (SelectionManager). ZERO means "the default billboard sprite
## size"; vehicles override this with their hull dimensions so their whole
## 3D model is clickable.
func pick_size_m() -> Vector2:
	return Vector2.ZERO


## Optional world-space points whose screen projection bounds the pick rect —
## used for a rotated/elongated hull (airship deck) so clicks on the deck
## CORNERS register regardless of the ship's heading. Empty = use pick_size_m().
func pick_world_points() -> PackedVector3Array:
	return PackedVector3Array()


## Blinks a short-lived red ring at this unit's feet (2x on/off) — feedback
## when it becomes the target of an attack order. Spawns its own mesh because
## the selection rings are drawn centrally (MultiMesh, selected units only);
## as a child it follows the moving target, and the ring-local tween dies with
## the unit if the target is freed mid-flash.
func flash_target_ring(color: Color = Color(0.9, 0.2, 0.15)) -> void:
	if not is_inside_tree():
		return
	var ring: MeshInstance3D = MeshInstance3D.new()
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.26 * selection_ring_scale()
	torus.outer_radius = 0.34 * selection_ring_scale()
	ring.mesh = torus
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	ring.position.y = 0.1
	add_child(ring)
	var tween: Tween = ring.create_tween()
	for i in range(2):
		tween.tween_callback(func() -> void: ring.visible = true)
		tween.tween_interval(0.16)
		tween.tween_callback(func() -> void: ring.visible = false)
		tween.tween_interval(0.12)
	tween.tween_callback(ring.queue_free)


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


## Probability that a strike is a kick (see _roll_attack_kind). Per-unit
## override point, same pattern as _shove_chance(); the remainder is a punch.
func _kick_chance() -> float:
	return KICK_CHANCE


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
	# Corpses only decay (knockback/regen/burning already no-op when DEAD, and the
	# pose was locked in _die): skip the four dead-weight calls per corpse per
	# tick — a mass battle carries hundreds of them (phase 8 perf).
	if state == State.DEAD:
		_tick_dead(delta)
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
		return
	# C2.4 walk hold: steady march along the planned path — the kernel steps
	# toward the current waypoint (aggressive movers keep their scan cadence
	# via the timer) and drops us back for the waypoint switch/stumble zone.
	if state == State.MOVE and _has_path():
		var scan_t: float = -1.0
		if move_aggressive and _is_combatant():
			scan_t = maxf(_target_search_timer, 0.0)
		_enter_soa_path_hold(UnitManager.HOLD_MOVE, _path[_path_index],
			Vector3.ZERO, scan_t)


## Distance at which a waypoint counts as reached. Ground units need pinpoint
## arrival; the airship overrides this to ~its separation radius so a ship
## whose target sits inside another ship's collision bubble still counts as
## arrived (and goes IDLE) instead of circling forever against it.
func arrive_eps() -> float:
	return ARRIVE_EPS


## Multiplier applied to the (tight) formation MEMBER/GROUP offsets in a move
## order (TribeCommands.order_move). Foot units stand in a tight pack (1.0);
## vehicles override this so several sent to one point get targets OUTSIDE each
## other's separation bubble instead of shoving each other around at the goal.
func formation_scale() -> float:
	return 1.0


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
	# Crew walking over to board a vehicle must not stumble-roll on the way — the
	# tumble looks like an animation glitch beside an idle siege engine.
	var boarding: bool = siege_engine != null and is_instance_valid(siege_engine) \
		and not siege_boarded
	if not boarding and slope < -STEEP_ROLL_SLOPE \
			and randf() < STEEP_ROLL_CHANCE_PER_SEC * delta:
		# Harmless downhill stumble: orders survive (resumed after the tumble).
		start_roll(Vector3(to_target.x, 0.0, to_target.y), MINI_ROLL_DURATION, 0.0, true)
		return false
	var next: Vector2 = flat_pos.move_toward(flat_target, _slope_speed(slope) * delta)
	position = Vector3(next.x, position.y, next.y)   # one set (hot path)
	_snap_to_ground()
	if next.distance_to(flat_target) <= arrive_eps():
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
	# One property get + one set (component writes cost a get/set roundtrip
	# each) — this is the hottest per-mover call.
	var p: Vector3 = position
	if terrain_data != null:
		p.y = terrain_data.get_height(p.x, p.z)
		position = p
	# SoA double-write, inlined (hot path: every mover, every tick). Covers all
	# movement writers that end here (_advance_path, _step_toward, knockback,
	# roll, throw landing, crew glide).
	var i: int = _idx
	if i >= 0:
		_soa_pos[i] = p


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
	man_hut_manual = false
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
	# A replaced route invalidates a running walk hold (same-state order, e.g.
	# MOVE -> new MOVE: _set_state's clear does not fire) — without this the
	# kernel would keep walking the OLD waypoint until its next drop.
	_clear_soa_hold()
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
		# Unreachable: give up the whole route and stop — no periodic re-search.
		waypoint_queue.clear()
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
		waypoint_queue.clear()
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
		# Unreachable target — give up the whole route (no periodic re-search).
		waypoint_queue.clear()
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
	_path = _trim_own_cell_waypoint(path)
	_path_index = 0
	return true


## Drops the redundant leading waypoint that find_path/find_vehicle_path place at
## the unit's OWN cell centre. Moving off-centre inside that cell, heading to the
## centre first is a backward/sideways dart before the real next cell — harmless
## for a one-shot move, but a combat approach re-plans on every tick against a
## MOVING target, so the dart repeats each re-plan and the unit jitters in place
## instead of pursuing (fire-ram / firewarrior / preacher wobble). The dropped
## point is the cell the unit already stands in, so the next real waypoint is
## always a walkable neighbour — safe to skip.
func _trim_own_cell_waypoint(path: PackedVector3Array) -> PackedVector3Array:
	if nav_grid != null and path.size() >= 2 \
			and nav_grid.world_to_cell(path[0]) == nav_grid.world_to_cell(position):
		path.remove_at(0)
	return path


## Directly injects a path (used by tests and by order handling).
func set_path(path: PackedVector3Array) -> void:
	_clear_soa_hold()   # a replaced path invalidates a running walk hold
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
	var health_before: int = health
	health -= amount
	_no_combat_timer = 0.0
	if attacker != null and is_instance_valid(attacker):
		last_attacker = attacker
	if health <= 0:
		# Already tumbling (thrown through the air or rolling): the damage still
		# lands but the DEATH is deferred to the end of the tumble. This makes a
		# falling unit unkillable in mid-air — e.g. the same catapult shot that
		# bursts an airship then sends a shockwave over the just-hurled deck crew
		# must not delete them at altitude; they die once they roll out below.
		if state == State.ROLL or state == State.THROWN:
			return   # deferred: _end_roll / the landing roll finishes it
		# Deck passengers (airship): a lethal hit while riding at altitude is
		# converted into a fall — they leave the deck, tumble off and die at the
		# END of the roll (user spec), never standing dead at 12 m. The landing
		# roll scales with the drop like a cliff fall (min ~1 s): with the ship
		# hovering low the plain mini roll read as "spawns dead on the ground"
		# instead of a visible crash-tumble (user report).
		if rides_airborne():
			var drop: float = position.y
			if terrain_data != null:
				drop -= terrain_data.get_height(position.x, position.z)
			_throw_roll_duration = clampf(maxf(drop, 3.0) * CLIFF_ROLL_PER_M,
				MINI_ROLL_DURATION, CLIFF_ROLL_MAX_DURATION)
			leave_crew()
			var out_angle: float = randf() * TAU
			throw_airborne(Vector3(cos(out_angle), 0.0, sin(out_angle))
				* randf_range(1.5, 3.0) + Vector3.UP * 2.0)
			return
		health = 0
		_die()
		return
	# Hurt sounds: the shaman calls out on every hit (throttled); everyone else
	# only once when dropping below the badly-hurt threshold.
	if unit_kind() == &"shaman":
		_play_sfx(&"shaman_hurt", 1200)
	else:
		var threshold: int = int(float(max_health) * BADLY_HURT_FRAC)
		if health <= threshold and health_before > threshold:
			_play_sfx(&"unit_injured", 300)
	_maybe_retaliate(attacker)


func _die() -> void:
	# Release our own binding, then dissolve the fight around us so attackers
	# and the second row retarget onto fresh enemies right away.
	leave_crew()
	_end_attack()
	_clear_building_target()
	_dissolve_own_group()
	# Corpse setup: no selection ring, no route, no hopping — the unit stays in
	# the world as a lying "dead" sprite until the decay timer removes it.
	selected = false
	hop_visual = false
	waypoint_queue.clear()
	_clear_path()
	_corpse_timer = 0.0
	_set_state(State.DEAD)
	# Lock in the "dead" pose here, once, so the per-tick corpse path can skip
	# _apply_animation entirely (see tick()) — a corpse never changes animation.
	_apply_animation(true)
	died.emit(self)


## Corpse decay: lie for CORPSE_DURATION, sink into the ground over
## CORPSE_SINK_DURATION (the renderer reads corpse_sink_depth()), then fire
## corpse_expired exactly once.
func _tick_dead(delta: float) -> void:
	if _corpse_done:
		return
	_corpse_timer += delta
	if _corpse_timer >= CORPSE_DURATION + CORPSE_SINK_DURATION:
		_corpse_done = true
		corpse_expired.emit(self)
		return
	# C2 corpse hold: a lying corpse only counts this timer — park the whole
	# LIE phase in the kernel (a mass battle carries hundreds of corpses).
	# The kernel drops us back exactly when the sink phase starts, which the
	# object ticks (corpse_sink_depth reads the live timer while sinking).
	if _idx >= 0 and _corpse_timer < CORPSE_DURATION:
		_soa_hold[_idx] = CORPSE_DURATION - _corpse_timer
		_soa_mode[_idx] = UnitManager.HOLD_CORPSE
		_soa_scan[_idx] = -1.0
		_soa_kb[_idx] = knockback_accum


## 0.0 while the corpse lies, then how many metres it has sunk below its
## ground position (linear until fully submerged at CORPSE_SINK_DEPTH).
func corpse_sink_depth() -> float:
	if state != State.DEAD:
		return 0.0
	return CORPSE_SINK_DEPTH * clampf(
		(_corpse_timer - CORPSE_DURATION) / CORPSE_SINK_DURATION, 0.0, 1.0)


# --- Knockback (fireball, phase 5c) ----------------------------------------------

## Small instant displacement along dir (played out via the knockback system);
## used by fireball knockback and melee shoves.
func displace(dir: Vector3, dist: float) -> void:
	if state == State.DEAD or rides_airborne():
		return   # deck passengers are carried by the airship, never shoved
	var flat: Vector3 = Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.000001:
		return
	_clear_soa_hold()   # the knockback playout needs the object tick (C2)
	_knockback_remaining += flat.normalized() * dist


## Fireball knockback: the hit-density accumulator makes rapid successive hits
## shove progressively harder; it decays in _tick_knockback (or, while the
## unit is kernel-held, in the kernel — hence the clear FIRST, which writes
## the decayed value back into knockback_accum before it is read here).
func apply_knockback(dir: Vector3) -> void:
	if state == State.DEAD:
		return
	_clear_soa_hold()
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
	# Never shove anyone into water/obstacles (overview risk 6) — but a downward
	# cliff edge launches the unit off it instead of stopping at the rim.
	if nav_grid != null and not nav_grid.is_cell_walkable(
			nav_grid.world_to_cell(Vector3(nx, 0.0, nz))):
		_knockback_remaining = Vector3.ZERO
		var push_dir: Vector3 = Vector3(step.x, 0.0, step.z)
		var drop: float = _cliff_drop_ahead(push_dir)
		if drop > 0.0:
			fall_off_cliff(push_dir, drop)
		return
	position.x = nx
	position.z = nz
	_snap_to_ground()


# --- Cliff fall (combat shove / roll over a cliff edge) -----------------------------

## Height drop when a genuine cliff lies ahead along `dir`, else 0. A cliff is
## an UNWALKABLE steep FACE cell right ahead (~1 m) — this discriminates a real
## cliff from a merely steep but walkable slope, which must NOT trigger a fall.
## The drop that drives damage/roll duration is read from the lower ground
## CLIFF_PROBE_DIST beyond the face; water/building bases return 0 (the caller
## keeps its normal "don't shove into water" stop). Cheap: called only from the
## knockback clamp and the roll tick, never in the normal walk hot path.
func _cliff_drop_ahead(dir: Vector3) -> float:
	if terrain_data == null or nav_grid == null:
		return 0.0
	var flat: Vector3 = Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.000001:
		return 0.0
	flat = flat.normalized()
	var face_cell: Vector2i = nav_grid.world_to_cell(
		Vector3(position.x + flat.x, 0.0, position.z + flat.z))
	if nav_grid.is_cell_walkable(face_cell) or nav_grid.is_cell_blocked_by_building(face_cell):
		return 0.0   # walkable slope or a building ahead — not a cliff
	var below: Vector3 = Vector3(
		position.x + flat.x * CLIFF_PROBE_DIST, 0.0, position.z + flat.z * CLIFF_PROBE_DIST)
	var below_h: float = terrain_data.get_height(below.x, below.z)
	if below_h <= TerrainData.SEA_LEVEL + 0.05:
		return 0.0   # water at the base: keep the caller's stop, do not launch in
	var drop: float = position.y - below_h
	return drop if drop >= CLIFF_FALL_MIN_DROP else 0.0


## Launches the unit off a cliff edge: a scripted throw arc in `horizontal_dir`
## carries it over the rim, then it takes drop-scaled fall damage (capped at
## 1/2 brave life) and rolls away for a drop-scaled duration (capped at 2 s).
func fall_off_cliff(horizontal_dir: Vector3, drop: float) -> void:
	if state == State.DEAD or state == State.THROWN:
		return
	var flat: Vector3 = Vector3(horizontal_dir.x, 0.0, horizontal_dir.z)
	if flat.length_squared() < 0.000001:
		flat = facing
	flat = flat.normalized()
	var dmg: int = mini(int(drop * CLIFF_FALL_DAMAGE_PER_M), CLIFF_FALL_MAX_DAMAGE)
	_throw_roll_duration = clampf(
		drop * CLIFF_ROLL_PER_M, MINI_ROLL_DURATION, CLIFF_ROLL_MAX_DURATION)
	throw_airborne(flat * CLIFF_LAUNCH_SPEED + Vector3.UP * CLIFF_LAUNCH_UP, dmg)


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
	if state == State.DEAD or rides_airborne():
		return   # nobody tumbles across an airship deck
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
	# Rolling over a real cliff edge (unwalkable, lower ground) turns into a fall.
	var drop: float = _cliff_drop_ahead(roll_dir)
	if drop > 0.0:
		fall_off_cliff(roll_dir, drop)
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
			if (_unit_target_attackable(attack_target) and attack_target.tribe_id != tribe_id) \
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
	if state == State.DEAD or rides_airborne():
		return   # deck passengers stay aboard (the ship's explode() drops them)
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
	_sync_soa_pos()   # THROWN never snaps to ground — mirror here
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
	_sync_soa_pos()
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
const LAVA_CONTACT_DAMAGE: int = Balance.LAVA_CONTACT_DAMAGE
const BURN_DURATION: float = Balance.BURN_DURATION
const BURN_TOTAL_DAMAGE: int = Balance.BURN_TOTAL_DAMAGE

var _burn_time: float = 0.0
var _burn_frac: float = 0.0


func is_burning() -> bool:
	return _burn_time > 0.0


## Size multiplier for the shared StatusFxRenderer flame (vehicles override).
func burn_fx_scale() -> float:
	return 1.0


## Flame anchor height; < 0 means "use the renderer's default".
func burn_fx_height() -> float:
	return -1.0


## Lava contact. Re-touching while already alight refreshes the burn instead
## of stacking it (and costs no second contact hit).
## `source` (optional, untyped): the object dealing the fire — subclasses that
## throttle fire per source (the fire ram's lives model) read its identity; the
## base ignores it.
func ignite(source_pos: Vector3, _source = null) -> void:
	if state == State.DEAD:
		return
	_clear_soa_hold()   # burn damage/panic re-assert need the object tick (C2)
	var fresh: bool = not is_burning()
	_burn_time = BURN_DURATION
	if fresh:
		_play_sfx(&"unit_burning", 200)
		take_damage(LAVA_CONTACT_DAMAGE)
		if state == State.DEAD:
			return
	start_panic(source_pos, BURN_DURATION)


## Flame contact (fire ram): burn + panic exactly like lava, but WITHOUT the
## one-time contact hit — the ram's damage is the burn alone. Re-scorching
## refreshes the burn (no stacking). CrewedVehicle overrides this with a real
## ignite (wooden vehicles catch fire properly).
func scorch(source_pos: Vector3, _source = null) -> void:
	if state == State.DEAD:
		return
	_clear_soa_hold()   # burn damage/panic re-assert need the object tick (C2)
	if not is_burning():
		_play_sfx(&"unit_burning", 200)
	_burn_time = BURN_DURATION
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
	# Invariant: burning ALWAYS panics (visible scramble). ignite()'s own
	# start_panic is refused while the unit is mid-air/tumbling — without this
	# re-assert such a unit finished its tumble, then burned standing around
	# and could even fight. Immune units (shaman) burn standing on purpose.
	if _burn_time > 0.0 and state != State.PANIC and state != State.DEAD \
			and state != State.THROWN and state != State.ROLL \
			and not is_panic_immune():
		start_panic(position, _burn_time)


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
	var roll_dur: float = _throw_roll_duration
	_throw_roll_duration = MINI_ROLL_DURATION
	start_roll(momentum, roll_dur, momentum.length())


# --- Panic (phase 6) --------------------------------------------------------------------

## Panics the unit (swarm effect): it flees in randomly changing directions
## away from `source_pos`, accepts no orders and does not fight back, until
## the effect runs out. Re-panicking refreshes the timer. Shamans are immune;
## thrown/rolling units finish their tumble first.
func start_panic(source_pos: Vector3, duration: float = PANIC_DURATION) -> void:
	if state == State.DEAD or state == State.THROWN or state == State.ROLL:
		return
	if rides_airborne():
		return   # deck passengers cannot scramble around at 12 m
	if is_panic_immune():
		return
	panic_source = source_pos
	if state == State.PANIC:
		_clear_soa_hold()   # settle the held time BEFORE refreshing the timer
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
	_play_sfx(&"unit_panic", 150)


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
		# C2 panic hold: the scramble hop is a plain one-point walk — the
		# kernel steps it and counts min(panic end, redirect) in the hold
		# value (entry parked in goal.x for the drop write-back). Burning
		# panickers keep their object tick (burn damage), via the entry gate.
		if state == State.PANIC and _has_path():
			_enter_soa_panic_hold()


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

## Counts combat-free time and slowly heals past REGEN_DELAY. Rolling counts
## as combat.
func _tick_regen(delta: float) -> void:
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


## Circling stars = CRITICAL DAMAGE (below BADLY_HURT_FRAC of max health;
## HP itself is never shown). Burning has display priority and suppresses
## the stars; the siege engine's 1-HP convention never counts as hurt.
func has_stars() -> bool:
	return state != State.DEAD and renders_as_sprite() and not is_burning() \
		and health <= int(float(max_health) * BADLY_HURT_FRAC)


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
func begin_conversion(preacher: Unit, duration: float,
		reach: float = Preacher.CONVERT_RANGE) -> bool:
	if state == State.DEAD or state == State.SIT or is_conversion_immune():
		return false
	if garrison_housed:
		return false   # tower crew are a protected reserve (phase 7h)
	if state == State.ROLL or state == State.THROWN or state == State.PANIC:
		return false
	if rides_airborne():
		return false   # airship passengers are out of a preacher's reach
	_on_combat_interrupt()
	_end_attack()
	waypoint_queue.clear()
	_clear_path()
	converting_preacher = preacher
	conversion_time = maxf(duration, 0.1)
	conversion_progress = 0.0
	conversion_reach = reach
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
	# Channeling either on the ground (CAST) or stationed on a tower platform /
	# airship deck (the station tick keeps station_channeling alive).
	var channeling: bool = p.state == State.CAST \
		or (p.station_channeling
			and (p.state == State.GARRISON or p.state == State.CREW))
	if not channeling \
			or _flat_dist(position, p.position) > conversion_reach * 1.3:
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

## Assigns this unit to a vehicle's crew (right-click on the vehicle, the
## workshop's auto-manning or the AI). The VEHICLE decides who may crew it
## (accepts_crew_unit — ground vehicles refuse the shaman, the airship takes
## everyone) and validates tribe/capacity; refused assignments are ignored.
func order_crew(engine) -> void:
	if not can_take_orders():
		return
	if engine == null or not is_instance_valid(engine) or engine.state == State.DEAD:
		return
	if not engine.accepts_crew_unit(self):
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
	_sync_soa_flags()
	waypoint_queue.clear()
	_clear_path()
	_set_state(State.CREW)


## Drops the crew membership (new order, conversion, death). `except` keeps
## a just-joined engine untouched when switching engines.
func leave_crew(except = null) -> void:
	var engine = siege_engine
	siege_engine = null
	siege_boarded = false
	_sync_soa_flags()   # no longer seated: separation applies again
	station_channeling = false
	crew_action_anim = &""
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
		if _flat_dist(position, engine.position) <= engine.board_range:
			engine.on_crew_boarded(self)
			if siege_engine != engine:
				return   # boarding was refused (enemy took it meanwhile)
		else:
			_crew_walking = true
			_approach(engine.position, delta)
			return
	# Deck vehicle (airship): ride pinned to the deck slot at altitude — no
	# ground glide, no Y snap (the vehicle carries the passenger).
	if engine.crew_rides_on_deck():
		position = engine.crew_slot_position(self)
		_sync_soa_pos()   # pinned at deck height, no ground snap
		if engine.facing.length_squared() > 0.000001:
			facing = engine.facing
		_crew_walking = false
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
	# building assault, phase 7g). Same for a target that left the live world
	# (admitted into a building) or became a protected reserve.
	if not _unit_target_attackable(attack_target) or attack_target.tribe_id == tribe_id:
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
		# C2 wait hold: already standing near the fight (the ring centres on
		# the ANCHOR, so allow its full trail distance) — the kernel keeps
		# watch (target liveness, ring band, scan cadence) until the next
		# scheduled scan; a slot promotion clears the hold directly
		# (CombatGroup.promote_waiters).
		if state == State.ATTACK and attack_target == target \
				and _flat_dist(position, target.position) <= MELEE_WAIT_RADIUS * 2.0:
			_enter_soa_hold(maxf(_target_search_timer, 0.0), UnitManager.HOLD_WAIT)
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
		# C2.4 chase hold (planned-path leg only — the direct-step pursuit
		# keeps its per-step walkability check on the object path): the kernel
		# walks the path and drops us back on arrival in direct range, target
		# drift past the re-plan threshold, or the waypoint switch. goal =
		# target position now: dest is target + a constant slot offset, so
		# target drift equals the object's goal-drift re-plan check.
		if state == State.ATTACK and attack_target == target and _has_path() \
				and _combat_goal != Vector3.INF \
				and dist > COMBAT_DIRECT_RANGE:
			_enter_soa_path_hold(UnitManager.HOLD_CHASE, _path[_path_index],
				target.position)
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
	# Stable melee hold (Stufe C2, plans/08e): waiting out the cooldown in
	# range is the most common ATTACK situation — hand it to the manager's
	# flat kernel; the object tick resumes on strike/any change. The strike
	# above may have killed/rolled the target or retargeted us — re-validate.
	if _attack_cooldown > 0.0 and state == State.ATTACK \
			and attack_target == target and is_instance_valid(target) \
			and target.state != State.DEAD:
		_enter_soa_hold()


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


## Plays a file-based one-shot at the unit's position via the AudioManager.
## Guarded like _emit_combat_hit: absent in headless tests without autoloads.
func _play_sfx(name: StringName, min_interval_ms: int = 0) -> void:
	if not _audio_checked:
		_audio_checked = true
		if is_inside_tree():
			_audio_node = get_node_or_null("/root/AudioManager")
	if _audio_node != null:
		_audio_node.play_sfx(name, position, min_interval_ms)


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
## the warrior); kicks are uncommon; most strikes are punches. Both
## probabilities are per-unit overridable (_shove_chance / _kick_chance); the
## remainder always falls back to a punch.
func _roll_attack_kind() -> StringName:
	var r: float = randf()
	if r < _shove_chance():
		return &"shove"
	if r < _shove_chance() + _kick_chance():
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
	# catapult bombarding another vehicle (_may_target_vehicle).
	if not enemy.is_targetable() and not _may_target_vehicle(enemy):
		return
	# Airborne targets (airship deck crew, whirled units) are out of reach for
	# melee — only ranged attacks can touch them.
	if enemy.is_airborne() and not _is_ranged():
		return
	if attack_target == enemy:
		if state != State.ATTACK:
			_set_state(State.ATTACK)
		return
	garrison_target = null   # a fresh fight abandons a pending garrison approach
	man_hut_manual = false
	route_end_action = Callable()
	_on_combat_interrupt()
	_end_attack()
	attack_target = enemy
	_sync_soa_target()
	_attack_cooldown = 0.0
	_combat_goal = Vector3.INF
	# Melee units bind into the target's fight right away (pairing rules);
	# ranged units fire without a group seat and only brawl via
	# request_melee_slot when someone closes in.
	if not _is_ranged():
		_bind_to_fight(enemy, true)
	_set_state(State.ATTACK)


## Public order entry used by TribeCommands.order_attack (UI + AI). Marks the
## target as ORDERED so ranged units stick to it instead of auto-retargeting.
func order_attack(enemy: Unit) -> void:
	_begin_attack(enemy)
	if attack_target == enemy:
		_target_ordered = true


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
	man_hut_manual = false
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
		man_hut_manual = false
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
		man_hut_manual = false
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
	station_channeling = false
	waypoint_queue.clear()
	_clear_path()
	_end_attack()
	_clear_building_target()
	_dissolve_own_group()   # a protected reserve is no fight target (phase 8.2)
	selected = false
	position = slot_pos
	_sync_soa_pos()
	_sync_soa_flags()   # non-targetable + push-immune reserve
	anim_base_name = &"idle"
	anim_start_ms = Time.get_ticks_msec()
	_set_state(State.GARRISON)


## Released from the tower (ejection / storm / damage / destruction): back to a
## normal world unit, go idle. The tower repositions it on the ground first.
func leave_garrison() -> void:
	garrison_target = null
	garrison_housed = false
	garrison_reached = false
	man_hut_manual = false
	push_immune = false
	station_channeling = false
	_sync_soa_flags()   # targetable/pushable again
	if state == State.GARRISON:
		_clear_path()
		_set_state(State.IDLE)


## Orders a BRAVE to man an own hut as production crew (phase 7i): it walks to
## the entrance (reusing the garrison approach) and the hut admits it. Rejected
## for non-braves, a foreign/unusable/full hut, or while beyond control.
func order_man_hut(hut, manual: bool = false) -> void:
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
	man_hut_manual = manual
	_set_state(State.GARRISON)


## Called by a hut when admitted as crew: like a garrison, but the hut also
## removes the brave from the world (hidden reserve). It keeps counting toward
## population; reuses the garrison_housed machinery (leave_garrison releases it).
func enter_hut(hut) -> void:
	garrison_target = hut
	garrison_housed = true
	garrison_reached = false
	push_immune = true
	_sync_soa_flags()
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
	_clear_soa_hold()
	_leave_combat_group()
	attack_target = null
	_sync_soa_target()
	_target_ordered = false
	_in_melee = false
	_combat_waiting = false
	_combat_goal = Vector3.INF


## Our target died: drop it and (combatants) look for another; braves go idle.
func _on_target_died(target) -> void:
	if attack_target != target:
		return
	_clear_soa_hold()
	attack_target = null
	_sync_soa_target()
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
	if rides_airborne():
		return   # deck passengers never leave the airship; it returns fire itself
	if state == State.IDLE or state == State.CREW:
		# Siege crew defends itself, leaving its post if necessary — it stays
		# crew (leash rule) and returns to the engine after the fight.
		# Fire-ram crew is immune to ranged distraction (user spec): it only
		# defends against direct melee pressure.
		if state == State.CREW and siege_engine != null \
				and is_instance_valid(siege_engine) \
				and siege_engine.crew_defends_melee_only() \
				and _flat_dist(position, attacker.position) > FLEE_MELEE_RANGE:
			return
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
		if not ranged and u.is_airborne():
			continue   # melee cannot reach airship deck crew / whirled units
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
	_clear_soa_hold()   # must react to the new opponent on its object tick
	attack_target = u
	_sync_soa_target()
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
	var now: int = Time.get_ticks_msec()
	if _unreach_targets.size() >= UNREACHABLE_CACHE_MAX:
		# Evict expired entries; if none expired, drop the soonest-expiring
		# one. NEVER clear wholesale: with more unreachable enemies in aggro
		# range than the cap, the old clear() forgot everything and the
		# expensive failing A* re-ran forever (Ebene-Klippen lag).
		var soonest_key: int = 0
		var soonest_expiry: int = 9223372036854775807
		for key in _unreach_targets.keys():
			var expiry: int = int(_unreach_targets[key])
			if expiry <= now:
				_unreach_targets.erase(key)
			elif expiry < soonest_expiry:
				soonest_expiry = expiry
				soonest_key = int(key)
		if _unreach_targets.size() >= UNREACHABLE_CACHE_MAX and soonest_key != 0:
			_unreach_targets.erase(soonest_key)
	_unreach_targets[target.get_instance_id()] = now + UNREACHABLE_TARGET_MS


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
			# Failed-plan cooldown: a failing A* floods the whole reachable
			# region (worst case). One recent failure = report "unreachable"
			# cheaply instead of flooding again for every scanned enemy.
			var now: int = Time.get_ticks_msec()
			if now < _combat_path_fail_until_ms:
				return false
			_combat_goal = dest
			if not _plan_path_to(dest):
				_combat_path_fail_until_ms = now + COMBAT_PATH_FAIL_COOLDOWN_MS
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
	position = Vector3(next.x, position.y, next.y)   # one set (hot path)
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


## _target_valid PLUS targetable: an ongoing attack must also drop a target
## that left the live world (building occupant) or turned into a protected
## reserve — otherwise the attacker keeps striking an invisible unit at its old
## position. Vehicles stay attackable for the units allowed to target them.
func _unit_target_attackable(target) -> bool:
	return _target_valid(target) \
		and (target.is_targetable() or _may_target_vehicle(target))


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
	_clear_soa_hold()   # a held unit leaving ATTACK ticks itself again (C2)
	state = new_state
	if _idx >= 0:
		_soa_state[_idx] = new_state   # SoA mirror (sole state writer)
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
			if crew_action_anim != &"":
				return crew_action_anim   # airship deck combat (throw / cast)
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
