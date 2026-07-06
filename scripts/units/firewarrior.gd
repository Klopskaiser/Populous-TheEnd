class_name Firewarrior extends Unit

## Ranged combat unit trained at the fire temple (Feuertempel). A KITER: it
## throws fireballs (Fireball projectile) at anything within FIRE_RANGE and any
## number of firewarriors may fire at one target (no melee-slot cap). It never
## brawls — when an enemy closes inside KITE_MIN_DIST it BACKS OFF while still
## firing, so a whole battle line of firewarriors keeps shooting instead of
## piling into melee and standing around waiting for a slot (which let a few
## enemy priests convert whole armies). Approaches only when out of fire range.

## Medium range: well above melee (1.2), below the aggro radius (8).
const FIRE_RANGE: float = 7.0
## Enemies closer than this make the firewarrior step back (kite) while firing.
const KITE_MIN_DIST: float = 3.5
## Seconds between fireballs (the throw animation cycle matches this).
const FIRE_COOLDOWN: float = 1.5


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


## Ranged kiter: approach when out of fire range; otherwise fire on cooldown,
## backing away when an enemy gets closer than KITE_MIN_DIST. Never occupies a
## melee slot and never brawls.
func _tick_attack(delta: float) -> void:
	if not _target_valid(attack_target) or attack_target.tribe_id == tribe_id:
		_retarget_or_idle()
		return
	if _breaks_off_vs_sitting(attack_target):
		return
	var target: Unit = attack_target
	# Ranged: release any melee slot so a real brawler can take it.
	target.release_melee_slot(self)
	var dist: float = _flat_dist(position, target.position)
	if dist > FIRE_RANGE:
		_in_melee = false
		_approach(target.position, delta)
		_face_point(target.position)
		return
	# In fire range: hold the throw stance, keep distance, and fire on cooldown.
	_in_melee = true
	attack_anim = &"throw"
	_face_point(target.position)
	if dist < KITE_MIN_DIST:
		_retreat_from(target.position, delta)   # back off but keep firing
	elif _has_path():
		_clear_path()
	_attack_cooldown -= delta
	if _attack_cooldown <= 0.0:
		_attack_cooldown = FIRE_COOLDOWN
		anim_start_ms = Time.get_ticks_msec()   # sync the throw with the shot
		_throw_fireball(target)


## Steps directly away from `from` (kiting), clamped to walkable ground by the
## base _step_toward (a step into water/off-map is dropped).
func _retreat_from(from: Vector3, delta: float) -> void:
	var away: Vector3 = Vector3(position.x - from.x, 0.0, position.z - from.z)
	if away.length_squared() < 0.000001:
		away = -facing
	_step_toward(position + away.normalized() * 2.0, delta)


## Spawns a fireball flying at the target (registered with the manager's
## projectile list; without a manager — bare tests — nothing is thrown).
func _throw_fireball(target: Unit) -> void:
	if path_service == null:
		return
	var ball: Fireball = Fireball.new()
	ball.setup(self, target, position + Vector3(0.0, 1.1, 0.0))
	path_service.register_projectile(ball)
	_emit_combat_hit(&"throw")
