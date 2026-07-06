class_name Firewarrior extends Unit

## Ranged combat unit trained at the fire temple (Feuertempel). It throws
## fireballs (Fireball projectile) from range, but it does NOT kite: it holds
## ground. When an enemy reaches melee range it MUST fight in melee if a melee
## slot is free (self-defence, brave-level brawl); only when all three melee
## slots on the target are taken does it stand as a "reserve row" and keep
## FIRING instead of waiting idle. Between melee and FIRE_RANGE it fires; beyond
## FIRE_RANGE it closes in. Any number of firewarriors may fire at one target.

## Medium range: well above melee (1.2), below the aggro radius.
const FIRE_RANGE: float = 7.0
## Seconds between fireballs (the throw animation cycle matches this).
const FIRE_COOLDOWN: float = 1.5
## Larger than the melee aggro (8) and above FIRE_RANGE: a firewarrior turns to
## fire on threats out to here — including an enemy shooting a neighbour — and
## then closes to fire range, instead of only reacting to enemies right on top.
const RANGED_AGGRO: float = 13.0


func _init() -> void:
	max_health = 60
	health = 60
	speed = 4.0


func unit_kind() -> StringName:
	return &"firewarrior"


func _is_combatant() -> bool:
	return true


func _is_ranged() -> bool:
	return true


func aggro_radius() -> float:
	return RANGED_AGGRO


## Holds ground: melee an enemy in melee range if a slot is free (must defend
## itself), fire as a reserve when the target's melee slots are full, fire at
## medium range, close in beyond FIRE_RANGE.
func _tick_attack(delta: float) -> void:
	if not _target_valid(attack_target) or attack_target.tribe_id == tribe_id:
		_retarget_or_idle()
		return
	if _breaks_off_vs_sitting(attack_target):
		return
	# Self-defence: an enemy on top of us takes priority. If the current target
	# is out of melee range but something is meleeing us, turn to fight it.
	if _flat_dist(position, attack_target.position) > MELEE_RANGE:
		var threat: Unit = _melee_threat()
		if threat != null:
			_begin_attack(threat)
	var target: Unit = attack_target
	var dist: float = _flat_dist(position, target.position)
	if dist <= MELEE_RANGE:
		# In melee: brawl when a slot is free (self-defence). Only the overflow
		# "reserve row" (all 3 slots taken) fires instead of standing idle.
		if target.request_melee_slot(self) >= 0:
			super._tick_attack(delta)
			return
	else:
		target.release_melee_slot(self)   # ranged stance: not holding a slot
		if dist > FIRE_RANGE:
			_in_melee = false
			_approach(target.position, delta)
			_face_point(target.position)
			return
	# Fire (stand): medium range, or reserve row inside melee range.
	if _has_path():
		_clear_path()
	_in_melee = true
	attack_anim = &"throw"
	_face_point(target.position)
	_attack_cooldown -= delta
	if _attack_cooldown <= 0.0:
		_attack_cooldown = FIRE_COOLDOWN
		anim_start_ms = Time.get_ticks_msec()   # sync the throw with the shot
		_throw_fireball(target)


## Nearest living enemy within melee range (the immediate threat to defend
## against); null when nothing is in our face.
func _melee_threat() -> Unit:
	if path_service == null:
		return null
	var best: Unit = null
	var best_d: float = INF
	for u in path_service.get_units_in_radius(position, MELEE_RANGE):
		if u.tribe_id == tribe_id or u.state == Unit.State.DEAD or u.state == Unit.State.SIT:
			continue
		var d: float = _flat_dist(position, u.position)
		if d < best_d:
			best_d = d
			best = u
	return best


## Spawns a fireball flying at the target (registered with the manager's
## projectile list; without a manager — bare tests — nothing is thrown).
func _throw_fireball(target: Unit) -> void:
	if path_service == null:
		return
	var ball: Fireball = Fireball.new()
	ball.setup(self, target, position + Vector3(0.0, 1.1, 0.0))
	path_service.register_projectile(ball)
	_emit_combat_hit(&"throw")
