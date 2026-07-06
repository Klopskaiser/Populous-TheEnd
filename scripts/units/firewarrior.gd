class_name Firewarrior extends Unit

## Ranged combat unit trained at the fire temple (Feuertempel). Throws fireballs
## (Fireball projectile) from medium range — any number of firewarriors may
## shoot one target (the 3-attacker cap only applies to brawling). Inside melee
## range it does NOT throw and brawls like a brave instead. The knockback
## accumulator and the hand-sprite toggle follow in phase 5c.

## Medium range: well above melee (1.2), below the aggro radius (8).
const FIRE_RANGE: float = 6.0
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


## Melee inside MELEE_RANGE (base behaviour, slot system, brave-level damage);
## stand and throw fireballs between MELEE_RANGE and FIRE_RANGE; approach when
## farther out.
func _tick_attack(delta: float) -> void:
	if not _target_valid(attack_target) or attack_target.tribe_id == tribe_id:
		_retarget_or_idle()
		return
	var target: Unit = attack_target
	var dist: float = _flat_dist(position, target.position)
	if dist <= MELEE_RANGE:
		super._tick_attack(delta)   # brawl — no fireballs at close quarters
		return
	# Ranged: no melee slot needed (and any held one is released so a brawler
	# can take it).
	target.release_melee_slot(self)
	if dist > FIRE_RANGE:
		_in_melee = false
		_approach(target.position, delta)
		_face_point(target.position)
		return
	if _has_path():
		_clear_path()
	_in_melee = true            # attack stance: plays attack_anim
	attack_anim = &"throw"
	_face_point(target.position)
	_attack_cooldown -= delta
	if _attack_cooldown <= 0.0:
		_attack_cooldown = FIRE_COOLDOWN
		anim_start_ms = Time.get_ticks_msec()   # sync the throw with the shot
		_throw_fireball(target)


## Spawns a fireball flying at the target (registered with the manager's
## projectile list; without a manager — bare tests — nothing is thrown).
func _throw_fireball(target: Unit) -> void:
	if path_service == null:
		return
	var ball: Fireball = Fireball.new()
	ball.setup(self, target, position + Vector3(0.0, 1.1, 0.0))
	path_service.register_projectile(ball)
