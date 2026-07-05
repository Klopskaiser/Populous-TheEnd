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

## Later phases fill in the behaviour for GATHER/PRAY/BUILD/ATTACK/TRAIN/
## PANIC/CAST/THROWN.
enum State {IDLE, MOVE, GATHER, PRAY, BUILD, ATTACK, TRAIN, PANIC, CAST, THROWN, DEAD}

signal died(unit: Unit)
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
## Seconds between melee strikes.
const ATTACK_COOLDOWN: float = 0.8
## Base target (re)search interval; a small per-unit offset staggers the scans
## so they never all fire on the same frame (never per-frame — see _due_to_scan).
const TARGET_SEARCH_INTERVAL: float = 0.25
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

var tribe_id: int = 0
## Owning tribe, injected by UnitManager.spawn_unit()/Tribe.add_unit().
var tribe: Tribe = null
var max_health: int = 100
var health: int = 100
var speed: float = 4.0
var state: State = State.IDLE
var waypoint_queue: Array[Vector3] = []
var patrol: bool = false
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
## Cached A* goal while approaching a target (replanned when it drifts).
var _combat_goal: Vector3 = Vector3.INF


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
	match state:
		State.MOVE:
			_tick_move(delta)
		State.ATTACK:
			_tick_attack(delta)
		State.IDLE:
			_tick_idle(delta)
		_:
			pass
	_apply_animation(false)


func _tick_move(delta: float) -> void:
	if _pending_target != Vector3.INF:
		return  # waiting for the path queue
	if _advance_path(delta):
		_on_path_finished()


## Walks one step along the current path (also used by Brave sub-states that
## are not State.MOVE). Returns true when the path is exhausted.
func _advance_path(delta: float) -> bool:
	if _path_index >= _path.size():
		return true
	var target: Vector3 = _path[_path_index]
	var flat_pos: Vector2 = Vector2(position.x, position.z)
	var flat_target: Vector2 = Vector2(target.x, target.z)
	var to_target: Vector2 = flat_target - flat_pos
	if to_target.length_squared() > 0.000001:
		facing = Vector3(to_target.x, 0.0, to_target.y).normalized()
	var next: Vector2 = flat_pos.move_toward(flat_target, speed * delta)
	position.x = next.x
	position.z = next.y
	_snap_to_ground()
	if next.distance_to(flat_target) <= ARRIVE_EPS:
		_path_index += 1
	return _path_index >= _path.size()


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

## Move order. queue_up appends the target as an additional waypoint
## (Shift+right-click), otherwise the current route is replaced.
func order_move(target: Vector3, queue_up: bool = false) -> void:
	_end_attack()
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
## the UnitManager deregisters it via the died signal.
func take_damage(amount: int, attacker = null) -> void:
	if state == State.DEAD:
		return
	health -= amount
	if attacker != null and is_instance_valid(attacker):
		last_attacker = attacker
	if health <= 0:
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
	_set_state(State.DEAD)
	died.emit(self)


## Idle combatants scan for a nearby enemy (throttled) and engage it.
func _tick_idle(delta: float) -> void:
	if not _is_combatant():
		return
	if _due_to_scan(delta):
		var enemy: Unit = _scan_for_enemy(AGGRO_RADIUS)
		if enemy != null:
			_begin_attack(enemy)


## Pursues the current target and strikes it when in range and holding a slot.
func _tick_attack(delta: float) -> void:
	if not _target_valid(attack_target):
		_retarget_or_idle()
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
	# Restart the attack animation on each swing for a visible hit cadence.
	anim_start_ms = Time.get_ticks_msec()
	target.take_damage(melee_damage(kind), self)
	# Shove/roll knockback and hit sounds are wired in phases 5b(shove)/5d.


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


## Braves fight back when hit (from idle/moving only — busy workers keep working);
## combatants already have a target, so this is mostly a brave hook.
func _maybe_retaliate(attacker) -> void:
	if attacker == null or not is_instance_valid(attacker) or attacker.state == State.DEAD:
		return
	if attack_target != null and is_instance_valid(attack_target):
		return
	if state == State.IDLE or state == State.MOVE:
		_begin_attack(attacker)


## Nearest enemy in radius, preferring targets with fewer attackers (1v1 bias).
func _scan_for_enemy(radius: float) -> Unit:
	if path_service == null:
		return null
	var flat: Vector2 = Vector2(position.x, position.z)
	var best: Unit = null
	var best_score: float = INF
	for u in path_service.get_units_in_radius(position, radius):
		if u == self or u.state == State.DEAD or u.tribe_id == tribe_id:
			continue
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
func _step_toward(point: Vector3, delta: float) -> void:
	var flat: Vector2 = Vector2(position.x, position.z)
	var flat_target: Vector2 = Vector2(point.x, point.z)
	var to_target: Vector2 = flat_target - flat
	if to_target.length_squared() > 0.000001:
		facing = Vector3(to_target.x, 0.0, to_target.y).normalized()
	var next: Vector2 = flat.move_toward(flat_target, speed * delta)
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
			# Attack frames only while actually striking; walk while closing in.
			return &"attack" if _in_melee else &"walk"
		State.CAST:
			return &"cast"
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
