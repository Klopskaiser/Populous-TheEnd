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
const CONVERT_RANGE: float = 5.0
## Random per-target conversion duration.
const CONVERT_TIME_MIN: float = 4.0
const CONVERT_TIME_MAX: float = 9.0
## Fight inertia: chance per pacify attempt that an already-fighting unit
## keeps brawling instead of sitting down (retried on the next scan).
const FIGHT_INERTIA_CHANCE: float = 0.4

## Enemy this preacher walks toward to convert (untyped: may be freed).
var _convert_target = null


func _init() -> void:
	max_health = 75
	health = 75
	speed = 4.0


func unit_kind() -> StringName:
	return &"preacher"


func _is_combatant() -> bool:
	return true


func _tick_state(delta: float) -> void:
	if state == State.CAST:
		_tick_convert(delta)
	else:
		super._tick_state(delta)


## Idle: prefer converting over brawling — normal enemies pull the preacher
## into CAST (approach + channel); preachers/shamans are attacked in melee.
func _tick_idle(delta: float) -> void:
	if not _due_to_scan(delta):
		return
	var enemy: Unit = _scan_for_enemy(AGGRO_RADIUS)
	if enemy == null:
		return
	if enemy.is_conversion_immune():
		_begin_attack(enemy)   # priest duel (or shaman) -> melee
	else:
		_convert_target = enemy
		_set_state(State.CAST)


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


## Scan pass while channeling: duel-check, pacify everyone convertible in
## range (with fight inertia), pick a new approach focus, or go idle.
func _refresh_conversion() -> void:
	if path_service == null:
		_set_state(State.IDLE)
		return
	var any_in_range: bool = false
	var nearest: Unit = null
	var nearest_d: float = INF
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
		elif u.state != State.SIT and d < nearest_d:
			nearest_d = d
			nearest = u
	if any_in_range:
		_convert_target = null   # stand and channel
		return
	if nearest != null:
		_convert_target = nearest
		return
	_convert_target = null
	_set_state(State.IDLE)


## Cast frames only while standing and channeling; walk while approaching.
func _anim_base() -> StringName:
	if state == State.CAST:
		return &"walk" if _has_path() else &"cast"
	return super._anim_base()