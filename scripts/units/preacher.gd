class_name Preacher extends Unit

## Converter unit trained at the temple (Tempel). Pacifies nearby enemy units
## (they sit down and are converted to his tribe after a random per-target
## time) while he stands and channels (CAST state, cast animation). Never
## converts shamans or other preachers; an enemy preacher in range triggers a
## melee PRIEST DUEL instead — the trance breaks and the released units join
## the fight against him (handled in Unit._tick_sit). Slightly tougher than a
## brave; brawls at brave strength.

## Conversion (channel) range — deliberately below the firewarrior's
## FIRE_RANGE, so fireballs can interrupt conversions from outside.
const CONVERT_RANGE: float = Balance.PREACHER_CONVERT_RANGE
## Random per-target conversion duration.
const CONVERT_TIME_MIN: float = Balance.PREACHER_CONVERT_TIME_MIN
const CONVERT_TIME_MAX: float = Balance.PREACHER_CONVERT_TIME_MAX
## Fight inertia: chance per pacify attempt that an already-fighting unit
## keeps brawling instead of sitting down (retried on the next scan).
const FIGHT_INERTIA_CHANCE: float = 0.4

## Seconds between chant sounds while standing and channeling.
const PREACH_SOUND_INTERVAL: float = 2.0

## Enemy this preacher walks toward to convert (untyped: may be freed).
var _convert_target = null
var _preach_sound_timer: float = 0.0


func _init() -> void:
	max_health = Balance.PREACHER_HP
	health = max_health
	speed = Balance.PREACHER_SPEED


func unit_kind() -> StringName:
	return &"preacher"


func _is_combatant() -> bool:
	return true


func _tick_state(delta: float) -> void:
	if state == State.CAST:
		_tick_convert(delta)
	else:
		super._tick_state(delta)


## Prefer converting over brawling — normal enemies pull the preacher into
## CAST (approach + channel); preachers/shamans are attacked in melee. Runs
## from IDLE and while marching (attack-move, Unit._tick_move). Multiple
## preachers spread out: the approach focus prefers a target no other own
## preacher is already handling (phase 7i).
func _engage_on_sight(delta: float) -> bool:
	if not _due_to_scan(delta):
		return false
	var enemy: Unit = _scan_for_enemy(AGGRO_RADIUS)
	if enemy == null:
		return _try_engage_building()   # lowest-priority fallback (phase 7g)
	if enemy.is_conversion_immune():
		_begin_attack(enemy)   # priest duel (or shaman) -> melee
		return true
	# Convertible: prefer an unclaimed target so preachers fan out instead of
	# piling onto the same crowd (falls back to the nearest if all are claimed).
	var focus: Unit = _pick_convert_focus()
	_convert_target = focus if focus != null else enemy
	_set_state(State.CAST)
	return true


## True when another OWN preacher is already converting `u` (it sits under him)
## or walking toward it as its focus. Cheap: only a handful of preachers exist.
func _claimed_by_peer(u: Unit) -> bool:
	if tribe == null or u == null:
		return false
	for p in tribe.units:
		if p == self or p.state == State.DEAD or not (p is Preacher):
			continue
		if u.state == State.SIT and u.converting_preacher == p:
			return true
		if (p as Preacher)._convert_target == u:
			return true
	return false


## Nearest convertible enemy in range, preferring one no peer preacher has
## claimed; returns null when nobody convertible is in range.
func _pick_convert_focus() -> Unit:
	if path_service == null:
		return null
	var nearest_free: Unit = null
	var d_free: float = INF
	var nearest_any: Unit = null
	var d_any: float = INF
	# Enemies-only candidates (phase 8.2): friends in the crowd no longer eat
	# the candidate budget, and the buckets are visited without the NW bias.
	for u in path_service.get_enemy_candidates(
			position, AGGRO_RADIUS, tribe_id, SCAN_MAX_CANDIDATES):
		if u == self or u.state == State.SIT or u.is_conversion_immune():
			continue
		var d: float = _flat_dist(position, u.position)
		if d < d_any:
			d_any = d
			nearest_any = u
		if not _claimed_by_peer(u) and d < d_free:
			d_free = d
			nearest_free = u
	return nearest_free if nearest_free != null else nearest_any


## Explicit attack order: convertible enemies are converted (walk into range,
## then channel); enemy preachers/shamans get the normal melee attack.
func order_attack(enemy: Unit) -> void:
	if not can_take_orders():
		return
	if enemy != null and is_instance_valid(enemy) and enemy.state != State.DEAD \
			and enemy.tribe_id != tribe_id and not enemy.is_conversion_immune():
		_end_attack()
		_convert_target = enemy
		_set_state(State.CAST)
		return
	super.order_attack(enemy)


## While assaulting a building, clear the entrance by CONVERTING convertible
## defenders (enemy priests / shamans are fought in melee instead). The building
## stays the target, so the assault resumes once the doorway is clear.
func _engage_assault_foe(foe: Unit) -> void:
	if foe != null and is_instance_valid(foe) and not foe.is_conversion_immune():
		_convert_target = foe
		_set_state(State.CAST)
	else:
		_begin_attack(foe)


## CAST: channel on everything convertible in range; walk toward the focus
## target while nobody is in range; duel enemy preachers that come close.
func _tick_convert(delta: float) -> void:
	if _due_to_scan(delta):
		_refresh_conversion()
		if state != State.CAST:
			return   # switched to duel/idle during the refresh
	var t = _convert_target
	if t != null and is_instance_valid(t) and t.state != State.DEAD:
		if _flat_dist(position, t.position) > CONVERT_RANGE * 0.85:
			_approach(t.position, delta)
			_face_point(t.position)
			return
	if _has_path():
		_clear_path()
	if t != null and is_instance_valid(t):
		_face_point(t.position)
	# Soft chant while standing and channeling (single sound file, throttled).
	_preach_sound_timer -= delta
	if _preach_sound_timer <= 0.0:
		_preach_sound_timer = PREACH_SOUND_INTERVAL
		_emit_combat_hit(&"preach")


## Scan pass while channeling: duel-check, pacify everyone convertible in
## range (with fight inertia), pick a new approach focus, or go idle.
func _refresh_conversion() -> void:
	if path_service == null:
		_set_state(State.IDLE)
		return
	var any_in_range: bool = false
	# Approach focus for when nobody is in range: prefer a target no peer
	# preacher has claimed (spread out), else the nearest one (phase 7i).
	var nearest_free: Unit = null
	var d_free: float = INF
	var nearest_any: Unit = null
	var d_any: float = INF
	for u in path_service.get_units_in_radius(position, AGGRO_RADIUS):
		if u == self or u.state == State.DEAD or u.tribe_id == tribe_id:
			continue
		var d: float = _flat_dist(position, u.position)
		if u.is_conversion_immune():
			# An enemy priest in range breaks the channel: melee duel. The
			# sitting units stand up and join in (see Unit._tick_sit).
			if u is Preacher and d <= CONVERT_RANGE:
				_convert_target = null
				_begin_attack(u)
				return
			continue
		if d <= CONVERT_RANGE:
			any_in_range = true
			if u.state != State.SIT:
				# Fight inertia: an already-fighting unit sometimes keeps
				# brawling for now (retried on the next scan).
				if u.state == State.ATTACK and randf() < FIGHT_INERTIA_CHANCE:
					continue
				u.begin_conversion(self,
					randf_range(CONVERT_TIME_MIN, CONVERT_TIME_MAX))
		elif u.state != State.SIT:
			if d < d_any:
				d_any = d
				nearest_any = u
			if not _claimed_by_peer(u) and d < d_free:
				d_free = d
				nearest_free = u
	if any_in_range:
		_convert_target = null   # stand and channel
		return
	var nearest: Unit = nearest_free if nearest_free != null else nearest_any
	if nearest != null:
		_convert_target = nearest
		return
	_convert_target = null
	# Nothing left to convert: resume a building assault if one is pending
	# (cleared the entrance defenders), otherwise go idle.
	if _building_target_valid():
		_set_state(State.ATTACK)
	else:
		_set_state(State.IDLE)


## Cast frames only while standing and channeling; walk while approaching.
func _anim_base() -> StringName:
	if state == State.CAST:
		return &"walk" if _has_path() else &"cast"
	return super._anim_base()