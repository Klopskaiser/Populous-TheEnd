extends TestBase

## Headless tests for phase 10i, parts 3 and 4: what a FIREWARRIOR's fireball
## does on impact — area damage around it, and a lift chance that scales inversely
## with the target's remaining health.
##
## Both changes come out of the balance lab: firewarriors deal 100 % of the enemy
## warrior HP pool and kill almost nobody (20 warriors keep 19.7 of 20). Their
## damage is spread thin instead of concentrated, so the fix is area damage — not
## more damage.

const TICK: float = 0.1

const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")
const SIEGE_SCENE: PackedScene = preload("res://scenes/units/siege_engine.tscn")


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


func _make_world() -> Dictionary:
	var td: TerrainData = _flat_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var tribe0: Tribe = Tribe.new(0)
	var tribe1: Tribe = Tribe.new(1)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe0, tribe1] as Array[Tribe])
	return {"td": td, "nav": nav, "tribe0": tribe0, "tribe1": tribe1, "unit_manager": um}


func _free_world(w: Dictionary) -> void:
	w.unit_manager.free()


func _spawn(w: Dictionary, scene: PackedScene, tribe_id: int, at: Vector2) -> Unit:
	return w.unit_manager.spawn_unit(scene, tribe_id, Vector3(at.x, 0.0, at.y))


## Bystander spot for the splash tests: a FRACTION OF THE BLAST RADIUS next to the
## direct target instead of a pinned 0,8 m. The ball explodes on contact and thus
## lands ~0,4 m SHORT of its target's centre, so a hardcoded offset silently drifts
## out of the blast when the radius is retuned — exactly what happened when
## FW_FIREBALL_BLAST_RADIUS went 1,3 -> 1,2: the bystander sat 1,2101 m from the
## impact and the splash missed by a centimetre. Same lesson as the fraction below.
func _bystander_pos(target_at: Vector2) -> Vector2:
	return Vector2(target_at.x + Balance.FW_FIREBALL_BLAST_RADIUS * 0.4, target_at.y)


## Tough target: survives the direct hit so the splash can be read in isolation.
func _tough(u: Unit, hp: int = 10000) -> Unit:
	u.max_health = hp
	u.health = hp
	return u


## Flies one ball from `shooter` at `target` until it lands.
func _fire(shooter: Unit, target: Unit) -> Fireball:
	var ball: Fireball = Fireball.new()
	ball.setup(shooter, target, shooter.position + Vector3(0.0, 1.1, 0.0))
	var ticks: int = 0
	while not ball.done and ticks < 400:
		ball.tick(TICK)
		ticks += 1
	return ball


func _splash_damage() -> int:
	return maxi(1, int(roundf(float(Unit.FIREBALL_DAMAGE)
		* Balance.FW_FIREBALL_BLAST_FRAC)))


# --- Part 3: area damage ------------------------------------------------------------

func test_fireball_splash_damages_nearby_enemies() -> void:
	var w: Dictionary = _make_world()
	var shooter: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(26, 30))
	var target: Unit = _tough(_spawn(w, BRAVE_SCENE, 1, Vector2(30, 30)))
	var bystander: Unit = _tough(_spawn(w, BRAVE_SCENE, 1, _bystander_pos(Vector2(30, 30))))
	var hp_target: int = target.health
	var hp_by: int = bystander.health
	var ball: Fireball = _fire(shooter, target)
	check(ball.done, "the ball impacted")
	check(target.health < hp_target, "the direct target takes the full hit")
	check(bystander.health < hp_by, "an enemy standing next to it takes splash")
	ball.free()
	_free_world(w)


## The fraction itself is a balance dial (2,0 m / 50 % -> 1,3 m / 30 % on
## 2026-08-05), so this derives the expectation from Balance instead of pinning a
## number — the same lesson the wood costs taught three times.
func test_fireball_splash_matches_the_configured_fraction() -> void:
	var w: Dictionary = _make_world()
	var shooter: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(26, 30))
	var target: Unit = _tough(_spawn(w, BRAVE_SCENE, 1, Vector2(30, 30)))
	var bystander: Unit = _tough(_spawn(w, BRAVE_SCENE, 1, _bystander_pos(Vector2(30, 30))))
	var hp_by: int = bystander.health
	var ball: Fireball = _fire(shooter, target)
	check(hp_by - bystander.health == _splash_damage(),
		"splash is FW_FIREBALL_BLAST_FRAC of the direct damage (%d)" % _splash_damage())
	ball.free()
	_free_world(w)


func test_fireball_splash_spares_own_units() -> void:
	var w: Dictionary = _make_world()
	var shooter: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(26, 30))
	var target: Unit = _tough(_spawn(w, BRAVE_SCENE, 1, Vector2(30, 30)))
	# Same tribe as the shooter, right next to the impact.
	var friend: Unit = _tough(_spawn(w, BRAVE_SCENE, 0, _bystander_pos(Vector2(30, 30))))
	var hp_friend: int = friend.health
	var ball: Fireball = _fire(shooter, target)
	check(friend.health == hp_friend,
		"no friendly fire — the back row must not shred its own front")
	ball.free()
	_free_world(w)


func test_fireball_splash_ignores_units_outside_the_radius() -> void:
	var w: Dictionary = _make_world()
	var shooter: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(26, 30))
	var target: Unit = _tough(_spawn(w, BRAVE_SCENE, 1, Vector2(30, 30)))
	var far: Unit = _tough(_spawn(w, BRAVE_SCENE, 1,
		Vector2(30.0 + Balance.FW_FIREBALL_BLAST_RADIUS + 3.0, 30)))
	var hp_far: int = far.health
	var ball: Fireball = _fire(shooter, target)
	check(far.health == hp_far, "an enemy beyond the blast radius stays unhurt")
	ball.free()
	_free_world(w)


## THE regression guard for the ordering trap: the splash must not disappear
## exactly when the direct hit was lethal — the most common case against a
## battered target.
func test_fireball_splash_still_applies_when_the_direct_hit_kills() -> void:
	var w: Dictionary = _make_world()
	var shooter: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(26, 30))
	var target: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	target.health = 1   # the direct hit kills it
	var bystander: Unit = _tough(_spawn(w, BRAVE_SCENE, 1, _bystander_pos(Vector2(30, 30))))
	var hp_by: int = bystander.health
	var ball: Fireball = _fire(shooter, target)
	check(target.state == Unit.State.DEAD, "the direct hit killed the target")
	check(bystander.health < hp_by,
		"the splash still lands (it must not depend on the target surviving)")
	ball.free()
	_free_world(w)


func test_fireball_splash_skips_vehicles() -> void:
	var w: Dictionary = _make_world()
	var shooter: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(26, 30))
	var target: Unit = _tough(_spawn(w, BRAVE_SCENE, 1, Vector2(30, 30)))
	var engine: Unit = _spawn(w, SIEGE_SCENE, 1, _bystander_pos(Vector2(30, 30)))
	var hp_engine: int = engine.health
	var ball: Fireball = _fire(shooter, target)
	check(engine.health == hp_engine,
		"vehicles keep their own damage model (ignite / hull hits), no splash")
	ball.free()
	_free_world(w)


func test_fireball_splash_does_not_push_bystanders() -> void:
	var w: Dictionary = _make_world()
	var shooter: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(26, 30))
	var target: Unit = _tough(_spawn(w, BRAVE_SCENE, 1, Vector2(30, 30)))
	var bystander: Unit = _tough(_spawn(w, BRAVE_SCENE, 1, _bystander_pos(Vector2(30, 30))))
	var ball: Fireball = _fire(shooter, target)
	check(bystander._knockback_remaining == Vector3.ZERO,
		"a bystander is damaged but not shoved (hundreds of balls per battle)")
	check(bystander.state != Unit.State.THROWN and bystander.state != Unit.State.ROLL,
		"and not lifted or rolled either")
	ball.free()
	_free_world(w)


## The radius is not a free-floating number: it was chosen (user decision
## 2026-08-05) so that ONE unit pack is covered and the NEIGHBOURING pack is not.
## Pinning the geometry keeps that reasoning alive the next time somebody turns
## the dial — the failing assertion says which rule was broken.
func test_blast_radius_covers_one_pack_but_not_the_neighbour() -> void:
	var r: float = Balance.FW_FIREBALL_BLAST_RADIUS
	# Widest distance between two members of a 6-pack (TribeCommands.MEMBER_OFFSETS).
	var pack_width: float = 0.0
	for a: Vector3 in TribeCommands.MEMBER_OFFSETS:
		for b: Vector3 in TribeCommands.MEMBER_OFFSETS:
			pack_width = maxf(pack_width, Vector2(a.x - b.x, a.z - b.z).length())
	check(r >= pack_width,
		"the radius covers a whole 6-pack (%.2f m wide)" % pack_width)
	check(r >= Unit.MELEE_SLOT_RADIUS,
		"and a whole melee group (attackers on a %.2f m ring)" % Unit.MELEE_SLOT_RADIUS)
	check(r < TribeCommands.GROUP_SPACING,
		"but stays below the distance between pack centres (%.2f m) — at 2.0 m the "
			% TribeCommands.GROUP_SPACING
			+ "splash reached into the neighbouring pack and flipped the airship pairing")
	check(r < UnitManager.COMBAT_GROUP_MIN_DIST - Unit.MELEE_SLOT_RADIUS,
		"and below the nearest attacker of the neighbouring brawl (%.2f m)"
			% (UnitManager.COMBAT_GROUP_MIN_DIST - Unit.MELEE_SLOT_RADIUS))


# --- Part 4: lift chance rises as health drops --------------------------------------

func test_lift_chance_rises_as_health_drops() -> void:
	var base: float = Balance.FW_FIREBALL_LIFT_CHANCE
	var mult: float = Balance.FW_FIREBALL_LIFT_HP_MAX_MULT
	check_near(Fireball.lift_chance_for_health(1.0, base), base,
		"full health keeps the base chance")
	check_near(Fireball.lift_chance_for_health(0.0, base), base * mult,
		"an almost dead target reaches base x MAX_MULT")
	check_near(Fireball.lift_chance_for_health(0.5, base),
		base * (1.0 + (mult - 1.0) * 0.5), "half health sits exactly in the middle")
	var prev: float = Fireball.lift_chance_for_health(1.0, base)
	var monotone: bool = true
	for i in range(1, 11):
		var f: float = 1.0 - float(i) * 0.1
		var v: float = Fireball.lift_chance_for_health(f, base)
		if v < prev - 0.000001:
			monotone = false
		prev = v
	check(monotone, "the curve rises monotonically as health drops")
	check(mult > 1.0, "the scaling is a real one")


func test_lift_chance_clamps_outside_zero_one() -> void:
	var base: float = Balance.FW_FIREBALL_LIFT_CHANCE
	check_near(Fireball.lift_chance_for_health(-0.5, base),
		Fireball.lift_chance_for_health(0.0, base), "a negative fraction clamps to 0")
	check_near(Fireball.lift_chance_for_health(2.0, base),
		Fireball.lift_chance_for_health(1.0, base), "a fraction above 1 clamps to 1")
	check(Fireball.lift_chance_for_health(0.0, 0.9) <= 1.0,
		"the result never exceeds a probability of 1")


## health_fraction() is the shared helper the scaling reads; five call sites used
## to inline this calculation.
func test_health_fraction_helper() -> void:
	var w: Dictionary = _make_world()
	var u: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(30, 30))
	u.max_health = 200
	u.health = 200
	check_near(u.health_fraction(), 1.0, "full health is 1.0")
	u.health = 50
	check_near(u.health_fraction(), 0.25, "a quarter left reads 0.25")
	u.health = 0
	check_near(u.health_fraction(), 0.0, "dead reads 0.0")
	u.max_health = 0
	check(u.health_fraction() >= 0.0, "max_health 0 does not divide by zero")
	_free_world(w)
