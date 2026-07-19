class_name Firewarrior extends Unit

## Ranged combat unit trained at the fire temple (Feuertempel). It throws
## fireballs (Fireball projectile) from range, but it does NOT kite: it holds
## ground. When an enemy reaches melee range it MUST fight in melee if a melee
## slot is free (self-defence, brave-level brawl); only when all three melee
## slots on the target are taken does it stand as a "reserve row" and keep
## FIRING instead of waiting idle. Between melee and FIRE_RANGE it fires; beyond
## FIRE_RANGE it closes in. Any number of firewarriors may fire at one target.

## Medium range: well above melee (1.2), below the aggro radius.
const FIRE_RANGE: float = Balance.FIREWARRIOR_FIRE_RANGE
## Seconds between fireballs (the throw animation cycle matches this).
const FIRE_COOLDOWN: float = Balance.FIREWARRIOR_FIRE_COOLDOWN
## Larger than the melee aggro (8) and above FIRE_RANGE: a firewarrior turns to
## fire on threats out to here — including an enemy shooting a neighbour — and
## then closes to fire range, instead of only reacting to enemies right on top.
const RANGED_AGGRO: float = Balance.FIREWARRIOR_AGGRO_RADIUS
## Building damage per fireball hit (phase 7g). Roughly HALF the melee raid
## DPS-equivalent: 5 HP / FIRE_COOLDOWN (1.5 s) ≈ 3.3 HP/s vs. a raider's
## 6 HP/s (Building.RAID_DPS_PER_RAIDER). Balance in phase 8.
const BUILDING_FIRE_DAMAGE: int = Balance.FIREWARRIOR_BUILDING_DAMAGE


func _init() -> void:
	max_health = Balance.FIREWARRIOR_HP
	health = max_health
	speed = Balance.FIREWARRIOR_SPEED


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
		_tick_no_unit_target(delta)   # falls back to a building assault (7g)
		return
	if _breaks_off_vs_sitting(attack_target):
		return
	# Threat + priest retarget, throttled to the scan cadence (phase 8.2): the
	# old PER-TICK threat query plus the uncapped priest sweep were the
	# dominant cost of the pure-firewarrior battle benchmark (~250 ms/tick at
	# 2x1000); a 0.25-s reaction window matches every other scan.
	if _due_to_scan(delta) \
			and _flat_dist(position, attack_target.position) > MELEE_RANGE:
		# Self-defence FIRST: an enemy on top of us takes priority (melee
		# entanglement is acceptable even under an explicit order).
		var threat: Unit = _melee_threat()
		if threat != null:
			_begin_attack(threat)
		elif not _target_ordered and attack_target.unit_kind() != &"preacher":
			# Priest priority: while not brawling AND not on an explicit order,
			# switch to an enemy preacher in range — killing it stops mass
			# conversions. An ordered target is honoured and never auto-swapped.
			var priest: Unit = _nearest_enemy_priest(aggro_radius())
			if priest != null and priest != attack_target:
				_begin_attack(priest)
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
			if not _approach(target.position, delta):
				# Unreachable (e.g. up on a cliff): disengage like the melee
				# path instead of standing frozen against the wall.
				_mark_target_unreachable(target)
				_retarget_or_idle()
				return
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


## Target selection prefers an enemy preacher in range (firewarriors hunt
## priests, which convert whole squads); otherwise the base nearest-enemy logic.
## Used by the idle/attack-move engage and by re-targeting after a kill.
func _scan_for_enemy(radius: float, max_examined: int = 0) -> Unit:
	var priest: Unit = _nearest_enemy_priest(radius)
	if priest != null:
		return priest
	return super._scan_for_enemy(radius, max_examined)


## Nearest living enemy preacher within `radius`; null when none is in range.
## Iterates the enemy tribes' preacher LISTS (a handful of units, phase 8.2)
## instead of an uncapped radius query over the whole battle — with 2x1000
## firewarriors that query alone cost a three-digit ms share per tick.
func _nearest_enemy_priest(radius: float) -> Unit:
	if path_service == null:
		return null
	var best: Unit = null
	var best_d: float = radius
	for t in path_service.tribes:
		if t == null or t.id == tribe_id:
			continue
		for u in t.preachers:
			if u == null or not is_instance_valid(u) or u.state == Unit.State.DEAD:
				continue
			if not u.is_targetable():
				continue
			var d: float = _flat_dist(position, u.position)
			if d <= best_d:
				best_d = d
				best = u
	return best


## Nearest living enemy within melee range (the immediate threat to defend
## against); null when nothing is in our face. Capped enemies-only candidate
## query (phase 8.2) — the tiny radius needs no deep sweep.
func _melee_threat() -> Unit:
	if path_service == null:
		return null
	var best: Unit = null
	var best_d: float = INF
	for u in path_service.get_enemy_candidates(position, MELEE_RANGE, tribe_id, 6, 48):
		if u.state == Unit.State.SIT:
			continue   # sitting converts are no threat
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
	ball.terrain_data = terrain_data
	path_service.register_projectile(ball)
	_emit_combat_hit(&"throw")


## Building bombardment (phase 7g): stand in FIRE_RANGE and lob fireballs at the
## building (half the melee raid DPS-equivalent); close in when out of range.
func _bombard_building(building, delta: float) -> void:
	var center: Vector3 = building.center_world()
	if _flat_dist(position, center) > FIRE_RANGE:
		_in_melee = false
		_approach(center, delta)
		_face_point(center)
		return
	if _has_path():
		_clear_path()
	_in_melee = true
	attack_anim = &"throw"
	_face_point(center)
	_attack_cooldown -= delta
	if _attack_cooldown <= 0.0:
		_attack_cooldown = FIRE_COOLDOWN
		anim_start_ms = Time.get_ticks_msec()
		_throw_fireball_at_building(building)


## Fires a fireball from a fixed origin at `target` (phase 7h: while stationed in
## a watchtower the shot leaves the platform, not the firewarrior's own — stale —
## position). Reuses the normal projectile.
func fire_from(origin: Vector3, target: Unit) -> void:
	if path_service == null or target == null or not is_instance_valid(target):
		return
	var ball: Fireball = Fireball.new()
	ball.setup(self, target, origin)
	ball.terrain_data = terrain_data
	path_service.register_projectile(ball)
	_emit_combat_hit(&"throw")


func _throw_fireball_at_building(building) -> void:
	if path_service == null:
		return
	var ball: Fireball = Fireball.new()
	ball.setup_building(self, building, position + Vector3(0.0, 1.1, 0.0))
	ball.terrain_data = terrain_data
	path_service.register_projectile(ball)
	_emit_combat_hit(&"throw")
