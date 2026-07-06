extends TestBase

## Headless tests for phase 5b: melee combat core — damage/death, the strike
## tick, warrior strength, the 3-attacker slot system with back-fill, 1v1 target
## preference, and aggro / brave retaliation. Flat walkable terrain, managers
## wired like in Main, all nodes created outside the scene tree and freed.

const TICK: float = 0.1
const MAX_TICKS: int = 400

const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")
const PREACHER_SCENE: PackedScene = preload("res://scenes/units/preacher.tscn")


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


## Ticks the given units (skipping freed/dead) plus a manager tick (hash refresh)
## until `done` returns true or MAX_TICKS is reached.
func _run(w: Dictionary, units: Array, done: Callable) -> int:
	for i in range(MAX_TICKS):
		if done.call():
			return i
		for u in units:
			if is_instance_valid(u) and u.state != Unit.State.DEAD:
				u.tick(TICK)
		w.unit_manager.tick(TICK)
	return MAX_TICKS


# --- Damage & death ----------------------------------------------------------------

func test_damage_reduces_hp_and_kills() -> void:
	var w: Dictionary = _make_world()
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	var died_count: Array[int] = [0]
	enemy.died.connect(func(_u: Unit) -> void: died_count[0] += 1)

	enemy.take_damage(10)
	check(enemy.health == 50, "non-lethal damage reduces HP")
	check(enemy.state != Unit.State.DEAD, "still alive above 0 HP")

	enemy.take_damage(100)
	check(enemy.state == Unit.State.DEAD, "lethal damage sets DEAD")
	check(died_count[0] == 1, "died signal fired once")
	check(enemy not in w.tribe1.units, "removed from its tribe")
	# The corpse stays in the world (registry/hash) until its decay finishes.
	check(enemy in w.unit_manager.units, "corpse stays registered while it lies")
	_free_world(w)


## A defeated unit lies as a corpse (dead sprite, fully visible) for
## CORPSE_DURATION, then fades and is removed from the world.
func test_corpse_lies_then_fades_and_expires() -> void:
	var w: Dictionary = _make_world()
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	unit.take_damage(1000)
	check(unit.state == Unit.State.DEAD, "unit is dead")
	check(unit in w.unit_manager.units, "corpse remains in the world")
	check(unit.anim_base_name == &"dead", "corpse uses the dead sprite")
	check(unit.corpse_alpha() == 1.0, "corpse starts fully visible")

	# 4.5 s: still lying, fully visible.
	for i in range(45):
		unit.tick(TICK)
	check(unit in w.unit_manager.units, "still lying before 5 s")
	check(unit.corpse_alpha() == 1.0, "fully visible before 5 s")

	# ~5.5 s: fading (alpha strictly between 0 and 1).
	for i in range(10):
		unit.tick(TICK)
	var alpha: float = unit.corpse_alpha()
	check(alpha > 0.0 and alpha < 1.0, "corpse fades after 5 s")

	# Past 6 s (5 s lying + 1 s fade): expired and removed.
	for i in range(10):
		unit.tick(TICK)
	check(unit not in w.unit_manager.units, "corpse removed after the fade")
	check(w.unit_manager.get_units_in_radius(Vector3(30, 0, 30), 5.0).is_empty(),
		"corpse removed from the spatial hash")
	_free_world(w)


# --- Strike tick ----------------------------------------------------------------

func test_melee_deals_damage_in_range() -> void:
	var w: Dictionary = _make_world()
	var attacker: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(30, 30))
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30.8, 30))  # within MELEE_RANGE
	attacker.order_attack(enemy)
	check(attacker.state == Unit.State.ATTACK, "attacker enters ATTACK")
	var hp0: int = enemy.health
	_run(w, [attacker], func() -> bool: return enemy.health < hp0)
	check(enemy.health < hp0, "enemy takes damage once the attacker strikes")
	check(attacker in enemy.melee_attackers, "attacker holds a melee slot on the enemy")
	_free_world(w)


func test_melee_pursues_when_out_of_range() -> void:
	var w: Dictionary = _make_world()
	var attacker: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(30, 30))
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(36, 30))  # 6 m away
	var d0: float = attacker.position.distance_to(enemy.position)
	attacker.order_attack(enemy)
	_run(w, [attacker], func() -> bool:
		return attacker.position.distance_to(enemy.position) < 1.5)
	check(attacker.position.distance_to(enemy.position) < d0,
		"attacker moved toward its out-of-range target")
	_free_world(w)


# --- Warrior strength --------------------------------------------------------------

func test_warrior_hits_three_times_harder() -> void:
	var warrior: Warrior = WARRIOR_SCENE.instantiate() as Warrior
	var brave: Brave = BRAVE_SCENE.instantiate() as Brave
	check(warrior.melee_damage(&"punch") == Unit.MELEE_PUNCH * 3,
		"warrior punch = 3x base")
	check(brave.melee_damage(&"punch") == Unit.MELEE_PUNCH, "brave punch = base")
	check(warrior.melee_damage(&"punch") == brave.melee_damage(&"punch") * 3,
		"warrior deals exactly 3x a brave")
	check(Unit.attack_base_damage(&"kick") > Unit.attack_base_damage(&"punch"),
		"a kick hurts more than a punch")
	check(Unit.attack_base_damage(&"shove") < Unit.attack_base_damage(&"punch"),
		"a shove hurts less than a punch")
	warrior.free()
	brave.free()


# --- Slot system --------------------------------------------------------------------

func test_melee_slots_cap_at_three_with_backfill() -> void:
	var w: Dictionary = _make_world()
	var target: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	# Make the target effectively unkillable so the slot bookkeeping can be
	# observed without it dying under four warriors first.
	target.max_health = 1000000
	target.health = 1000000
	var attackers: Array = []
	# Four attackers, all placed within striking range around the target.
	var offs: Array[Vector2] = [Vector2(0.8, 0), Vector2(-0.8, 0),
		Vector2(0, 0.8), Vector2(0, -0.8)]
	for o in offs:
		var a: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(30, 30) + o)
		a.order_attack(target)
		attackers.append(a)

	_run(w, attackers, func() -> bool:
		return target.active_melee_attacker_count() >= Unit.MAX_MELEE_ATTACKERS)
	check(target.active_melee_attacker_count() == Unit.MAX_MELEE_ATTACKERS,
		"exactly 3 attackers get a slot")
	# The 4th is still committed to the target but holds no slot.
	var without_slot: int = 0
	for a: Unit in attackers:
		if a.attack_target == target and a not in target.melee_attackers:
			without_slot += 1
	check(without_slot == 1, "the 4th attacker waits without a slot")

	# Kill one slot holder: the waiting attacker must back-fill into the free slot.
	var holder: Unit = target.melee_attackers[0]
	attackers.erase(holder)
	holder.take_damage(1000)
	check(not is_instance_valid(holder) or holder.state == Unit.State.DEAD,
		"slot holder died")
	_run(w, attackers, func() -> bool:
		return target.active_melee_attacker_count() >= Unit.MAX_MELEE_ATTACKERS)
	check(target.active_melee_attacker_count() == Unit.MAX_MELEE_ATTACKERS,
		"the waiting attacker back-filled the freed slot")
	_free_world(w)


func test_prefers_free_target_1v1() -> void:
	var w: Dictionary = _make_world()
	# Two attackers, two free enemies: each should end up on a different target.
	var a1: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(30, 30))
	var a2: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(30.5, 30))
	var e1: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(33, 30))
	var e2: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(33, 31))
	# Scan one at a time so the first commits before the second chooses.
	a1.tick(TICK)
	a2.tick(TICK)
	check(a1.attack_target != null and a2.attack_target != null,
		"both attackers engaged a target")
	check(a1.attack_target != a2.attack_target,
		"the two attackers split onto different enemies (1v1)")
	check((a1.attack_target == e1 or a1.attack_target == e2)
		and (a2.attack_target == e1 or a2.attack_target == e2),
		"both picked one of the two enemies")
	_free_world(w)


# --- Aggro & retaliation ------------------------------------------------------------

## Attack-move: combatants ordered across the map engage enemies they pass
## instead of marching through them (armies fight on contact).
func test_marching_combatants_engage_on_contact() -> void:
	var w: Dictionary = _make_world()
	var blue: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(30, 30))
	var red: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector2(44, 30))
	blue.order_move(Vector3(58, 0, 30))   # straight past/through the enemy
	red.order_move(Vector3(16, 0, 30))
	var ticks: int = _run(w, [blue, red], func() -> bool:
		return blue.state == Unit.State.ATTACK or red.state == Unit.State.ATTACK)
	check(ticks < MAX_TICKS, "marching combatants engage on contact")
	_free_world(w)


func test_combatant_aggros_idle_enemy() -> void:
	var w: Dictionary = _make_world()
	var warrior: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(30, 30))
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(34, 30))  # within AGGRO_RADIUS
	warrior.tick(TICK)  # one idle scan
	check(warrior.state == Unit.State.ATTACK, "idle warrior aggros a nearby enemy")
	check(warrior.attack_target == enemy, "it targets the enemy in range")
	_free_world(w)


# --- Firewarrior ranged (fireballs) --------------------------------------------------

## At medium range the firewarrior stands and throws fireballs instead of
## running into melee; the first impact deals exactly FIREBALL_DAMAGE.
func test_firewarrior_throws_fireballs_at_range() -> void:
	var w: Dictionary = _make_world()
	var fw: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(30, 30))
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(34, 30))  # 4 m: fire range
	enemy.max_health = 1000000
	enemy.health = 1000000
	fw.order_attack(enemy)
	var hp0: int = enemy.health
	_run(w, [fw], func() -> bool: return enemy.health < hp0)
	check(enemy.health == hp0 - Unit.FIREBALL_DAMAGE,
		"first fireball dealt exactly FIREBALL_DAMAGE")
	var dist: float = Vector2(fw.position.x, fw.position.z).distance_to(
		Vector2(enemy.position.x, enemy.position.z))
	check(dist > Unit.MELEE_RANGE, "firewarrior kept its distance (no melee rush)")
	check(fw.attack_anim == &"throw", "firewarrior plays the throw animation")
	_free_world(w)


## A fireball flies to its target and applies damage exactly once, then is done.
func test_fireball_hits_exactly_once() -> void:
	var w: Dictionary = _make_world()
	var shooter: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(26, 30))
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	enemy.max_health = 1000
	enemy.health = 1000
	var ball: Fireball = Fireball.new()
	ball.setup(shooter, enemy, shooter.position + Vector3(0.0, 1.1, 0.0))
	var ticks: int = 0
	while not ball.done and ticks < 200:
		ball.tick(TICK)
		ticks += 1
	check(ball.done, "fireball reaches its target and finishes")
	check(enemy.health == 1000 - Unit.FIREBALL_DAMAGE, "impact damage applied exactly once")
	for i in range(10):
		ball.tick(TICK)
	check(enemy.health == 1000 - Unit.FIREBALL_DAMAGE, "no further damage after impact")
	ball.free()
	_free_world(w)


## Inside melee range the firewarrior throws nothing and brawls at brave level.
func test_firewarrior_brawls_in_melee() -> void:
	var w: Dictionary = _make_world()
	var fw: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(30, 30))
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30.8, 30))  # melee range
	enemy.max_health = 1000000
	enemy.health = 1000000
	fw.order_attack(enemy)
	var hp0: int = enemy.health
	_run(w, [fw], func() -> bool: return enemy.health < hp0)
	check(enemy.health < hp0, "melee damage applied")
	check(w.unit_manager.projectiles.is_empty(), "no fireballs thrown in melee range")
	check(fw.melee_strength() == 1.0, "firewarrior brawls at brave strength")
	check(fw.attack_anim != &"throw", "melee uses a strike anim, not throw")
	_free_world(w)


# --- Hill movement & rolling (phase 5d) ------------------------------------------------

## Climbing a slope is slower than walking on flat ground.
func test_uphill_slows_movement() -> void:
	var w: Dictionary = _make_world()
	var flat_unit: Unit = _spawn(w, BRAVE_SCENE, 0, Vector2(30, 30))
	flat_unit.set_path(PackedVector3Array([Vector3(38, 0, 30)]))
	for i in range(10):
		flat_unit.tick(TICK)
	var flat_travel: float = flat_unit.position.x - 30.0

	var td: TerrainData = TerrainData.new()
	for z in range(TerrainData.SIZE + 1):
		for x in range(TerrainData.SIZE + 1):
			td.set_vertex_height(x, z, 5.0 + float(x) * 1.2)   # steep +x climb
	var climber: Unit = BRAVE_SCENE.instantiate() as Unit
	climber.terrain_data = td
	climber.position = Vector3(30, td.get_height(30, 30), 30)
	climber.set_path(PackedVector3Array([Vector3(38, 0, 30)]))
	for i in range(10):
		climber.tick(TICK)
	var climb_travel: float = climber.position.x - 30.0
	check(flat_travel > 3.5, "flat unit walks at full speed")
	check(climb_travel < flat_travel * 0.6, "climbing is clearly slower")
	climber.free()
	_free_world(w)


## A mini roll suspends all orders and ends on flat ground after its duration.
func test_mini_roll_runs_and_ends() -> void:
	var w: Dictionary = _make_world()
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	unit.start_roll(Vector3(1, 0, 0), 0.3)
	check(unit.state == Unit.State.ROLL, "the unit rolls")
	check(unit.anim_base_name == &"roll", "roll animation is active")
	check(not unit.can_take_orders(), "a rolling unit takes no orders")
	unit.order_move(Vector3(50, 0, 30))
	check(unit.state == Unit.State.ROLL, "order_move is ignored while rolling")
	for i in range(6):
		unit.tick(TICK)
	check(unit.state == Unit.State.IDLE, "the flat-ground mini roll ends")
	check(unit.position.x > 30.5, "the unit tumbled along the roll direction")
	_free_world(w)


## Another hit while rolling extends the tumble (homing fireballs).
func test_roll_extension() -> void:
	var w: Dictionary = _make_world()
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	unit.start_roll(Vector3(1, 0, 0), 0.2)
	unit.tick(TICK)
	unit.start_roll(Vector3(1, 0, 0), 1.0)   # extension mid-roll
	for i in range(5):
		unit.tick(TICK)   # 0.6 s total — past the original 0.2 s
	check(unit.state == Unit.State.ROLL, "the extended roll is still running")
	for i in range(7):
		unit.tick(TICK)   # past 1.1 s minimum
	check(unit.state == Unit.State.IDLE, "the extended roll ends afterwards")
	_free_world(w)


## Rolling into water kills instantly.
func test_roll_into_water_dies() -> void:
	var w: Dictionary = _make_world()
	# Lower everything left of x=26 below the sea level.
	for z in range(TerrainData.SIZE + 1):
		for x in range(0, 27):
			w.td.set_vertex_height(x, z, 1.0)
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	unit.start_roll(Vector3(-1, 0, 0), 5.0)
	for i in range(40):
		if unit.state == Unit.State.DEAD:
			break
		unit.tick(TICK)
	check(unit.state == Unit.State.DEAD, "rolling into water is instant death")
	_free_world(w)


## Roll damage kills only at the END of the roll (deferred death).
func test_roll_deferred_death() -> void:
	var w: Dictionary = _make_world()
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	unit.health = 2
	unit.start_roll(Vector3(1, 0, 0), 1.0)
	for i in range(7):
		unit.tick(TICK)   # 0.7 s: ~3 roll damage -> HP below zero mid-roll
	check(unit.health <= 0, "roll damage took the HP below zero mid-roll")
	check(unit.state == Unit.State.ROLL, "death is deferred while rolling")
	for i in range(5):
		unit.tick(TICK)   # past the 1.0 s minimum -> roll ends
	check(unit.state == Unit.State.DEAD, "the unit dies at the end of the roll")
	_free_world(w)


## A shove always shifts the target slightly along the shove direction.
func test_shove_displaces_target() -> void:
	var w: Dictionary = _make_world()
	var attacker: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(30, 30))
	var target: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30.8, 30))
	target.max_health = 1000000
	target.health = 1000000
	attacker._apply_shove(target)
	for i in range(6):
		target.tick(TICK)
	check(target.position.x > 30.95, "the shove shifted the target along +x")
	_free_world(w)


# --- Regeneration & stars (phase 5d) ---------------------------------------------------

func test_regeneration_after_delay() -> void:
	var w: Dictionary = _make_world()
	var unit: Unit = _spawn(w, BRAVE_SCENE, 0, Vector2(30, 30))
	unit.take_damage(20)
	check(unit.health == 40, "damage applied")
	for i in range(40):
		unit.tick(TICK)   # 4 s < REGEN_DELAY
	check(unit.health == 40, "no regeneration before the delay")
	for i in range(60):
		unit.tick(TICK)   # 10 s total: healing is running
	check(unit.health > 40, "the unit heals after the combat-free delay")
	# A fresh hit resets the timer.
	var hp: int = unit.health
	unit.take_damage(5)
	for i in range(40):
		unit.tick(TICK)
	check(unit.health == hp - 5, "a new hit stops the regeneration again")
	_free_world(w)


func test_stars_on_heavy_damage() -> void:
	var w: Dictionary = _make_world()
	var unit: Unit = _spawn(w, BRAVE_SCENE, 0, Vector2(30, 30))
	unit.take_damage(3)
	check(not unit.has_stars(), "light damage shows no stars")
	unit.take_damage(15)
	check(unit.has_stars(), "heavy damage triggers the circling stars")
	unit.take_damage(1000)
	check(not unit.has_stars(), "corpses never show stars")
	_free_world(w)


# --- Combat audio data (phase 5d) -------------------------------------------------------

func test_combat_audio_samples() -> void:
	for kind: StringName in CombatAudio.KINDS:
		var data: PackedByteArray = CombatAudio.generate_samples(kind, 0)
		check(data.size() > 500, "%s sound has sample data" % kind)
	check(CombatAudio.generate_samples(&"punch", 0)
		!= CombatAudio.generate_samples(&"punch", 1),
		"variants of the same kind differ")
	check(CombatAudio.generate_samples(&"punch", 0).size()
		< CombatAudio.generate_samples(&"fireball", 0).size(),
		"kinds have distinct durations")
	check(&"throw" in CombatAudio.SINGLE_VARIANT_KINDS
		and &"preach" in CombatAudio.SINGLE_VARIANT_KINDS,
		"throw and preach use a single sound file each")


# --- Strike animations ---------------------------------------------------------------

## Every kind carries the three strike animations; throw is firewarrior-only.
func test_strike_anims_in_atlas() -> void:
	var atlas: Dictionary = PlaceholderSprites.build_atlas(
		[&"brave", &"warrior", &"firewarrior"] as Array[StringName])
	var table: Dictionary = atlas.table
	for kind: StringName in [&"brave", &"warrior", &"firewarrior"]:
		for anim: StringName in [&"punch", &"kick", &"shove"]:
			check(table[kind].has(anim), "%s has a %s animation" % [kind, anim])
	check(table[&"firewarrior"].has(&"throw"), "firewarrior has a throw animation")
	check(not table[&"brave"].has(&"throw"), "throw is firewarrior-only")
	for kind: StringName in [&"brave", &"warrior", &"firewarrior"]:
		check(table[kind].has(&"dead"), "%s has a dead (corpse) sprite" % kind)
		check(table[kind].has(&"sit"), "%s has a sit (pacified) animation" % kind)
		check(table[kind].has(&"roll"), "%s has a roll (tumble) animation" % kind)
	var views: Array = table[&"brave"][&"punch"]
	check(views.size() == 4, "punch exists in all four views")
	check(int(views[0][1]) == 4, "punch alternates both fists (4 frames)")


## A strike switches the unit's animation to the rolled kind's animation.
func test_strike_sets_matching_anim() -> void:
	check(Unit.kind_to_anim(&"punch") == &"punch", "punch maps to punch anim")
	check(Unit.kind_to_anim(&"kick") == &"kick", "kick maps to kick anim")
	check(Unit.kind_to_anim(&"shove") == &"shove", "shove maps to shove anim")
	var w: Dictionary = _make_world()
	var attacker: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(30, 30))
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30.8, 30))
	enemy.max_health = 1000000
	enemy.health = 1000000
	attacker.order_attack(enemy)
	var hp0: int = enemy.health
	_run(w, [attacker], func() -> bool: return enemy.health < hp0)
	var strike_anims: Array[StringName] = [&"punch", &"kick", &"shove"]
	check(attacker.anim_base_name in strike_anims,
		"after a strike the anim base is the rolled strike animation")
	_free_world(w)


# --- Knockback (phase 5c) -------------------------------------------------------

## A knockback shoves the unit along the given direction; rapid successive
## hits stack the accumulator and shove progressively harder; the accumulator
## decays over time.
func test_knockback_accumulates_and_decays() -> void:
	var w: Dictionary = _make_world()
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	unit.apply_knockback(Vector3(1, 0, 0))
	check(unit.knockback_accum >= 1.0, "first hit charges the accumulator")
	for i in range(3):
		unit.tick(TICK)
	var dx1: float = unit.position.x - 30.0
	check(dx1 > 0.3, "the unit was shoved along +x")

	var before_second: float = unit.position.x
	unit.apply_knockback(Vector3(1, 0, 0))
	for i in range(3):
		unit.tick(TICK)
	var dx2: float = unit.position.x - before_second
	check(dx2 > dx1, "a rapid follow-up hit shoves farther (stacked)")

	for i in range(60):
		unit.tick(TICK)
	check(unit.knockback_accum == 0.0, "the accumulator decays back to zero")
	_free_world(w)


## A fireball impact knocks the target away from the shooter.
func test_fireball_applies_knockback() -> void:
	var w: Dictionary = _make_world()
	var shooter: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(26, 30))
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	enemy.max_health = 1000
	enemy.health = 1000
	var ball: Fireball = Fireball.new()
	ball.setup(shooter, enemy, shooter.position + Vector3(0.0, 1.1, 0.0))
	var ticks: int = 0
	while not ball.done and ticks < 200:
		ball.tick(TICK)
		ticks += 1
	check(ball.done, "fireball impacted")
	# One tick: the knockback (10 m/s) plays out fully, before the retaliation
	# walk toward the shooter can outweigh the 0.7 m shove.
	enemy.tick(TICK)
	check(enemy.position.x > 30.2, "the target was knocked back away from the shooter")
	check(enemy.knockback_accum > 0.0, "the hit charged the knockback accumulator")
	ball.free()
	_free_world(w)


# --- Preacher conversion (phase 5c) ------------------------------------------------

## A preacher near an enemy brave makes it sit, the progress runs, and on
## completion the unit has switched tribes (lists, tribe_id, colour signal).
func test_conversion_converts_enemy() -> void:
	var w: Dictionary = _make_world()
	var preacher: Unit = _spawn(w, PREACHER_SCENE, 0, Vector2(30, 30))
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(33, 30))  # in convert range
	var pair: Array = [preacher, enemy]

	_run(w, pair, func() -> bool: return enemy.state == Unit.State.SIT)
	check(enemy.state == Unit.State.SIT, "the enemy brave sits down")
	check(preacher.state == Unit.State.CAST, "the preacher channels (CAST)")
	check(enemy.converting_preacher == preacher, "the brave is bound to the preacher")

	var progressed: bool = false
	for i in range(20):
		for u: Unit in pair:
			u.tick(TICK)
		w.unit_manager.tick(TICK)
		if enemy.conversion_progress > 0.0:
			progressed = true
	check(progressed, "conversion progress accumulates while sitting")

	_run(w, pair, func() -> bool: return enemy.tribe_id == 0)
	check(enemy.tribe_id == 0, "the unit switched to the preacher's tribe")
	check(enemy in w.tribe0.units, "listed in the new tribe")
	check(enemy not in w.tribe1.units, "removed from the old tribe")
	check(enemy.state != Unit.State.SIT, "the convert stands up afterwards")
	_free_world(w)


## Preachers (and shamans) can never be converted.
func test_conversion_immune_targets() -> void:
	var w: Dictionary = _make_world()
	var preacher: Unit = _spawn(w, PREACHER_SCENE, 0, Vector2(30, 30))
	var enemy_preacher: Unit = _spawn(w, PREACHER_SCENE, 1, Vector2(33, 30))
	check(enemy_preacher.is_conversion_immune(), "preachers are conversion-immune")
	check(not enemy_preacher.begin_conversion(preacher, 5.0),
		"begin_conversion refuses an immune target")
	check(enemy_preacher.state != Unit.State.SIT, "the enemy preacher never sits")
	_free_world(w)


## An enemy preacher in range triggers a melee priest duel; the trance breaks
## and the released unit joins the fight against the converting preacher.
func test_priest_duel_breaks_trance() -> void:
	var w: Dictionary = _make_world()
	var preacher: Unit = _spawn(w, PREACHER_SCENE, 0, Vector2(30, 30))
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(32, 30))
	var units: Array = [preacher, enemy]
	_run(w, units, func() -> bool: return enemy.state == Unit.State.SIT)
	check(enemy.state == Unit.State.SIT, "the brave sits before the duel")

	# An enemy preacher walks into range: duel instead of channeling.
	var rival: Unit = _spawn(w, PREACHER_SCENE, 1, Vector2(33, 30))
	units.append(rival)
	_run(w, units, func() -> bool:
		return preacher.state == Unit.State.ATTACK and enemy.state != Unit.State.SIT)
	check(preacher.state == Unit.State.ATTACK, "the preacher switches to the duel")
	check(preacher.attack_target == rival, "the duel targets the rival preacher")
	check(enemy.state == Unit.State.ATTACK, "the released brave fights back")
	check(enemy.attack_target == preacher, "the released brave attacks the preacher")
	_free_world(w)


## Own units break off their attack when the target sits down under the own
## preacher's spell (only a 5% roll keeps an attacker fighting).
func test_attackers_break_off_vs_sitting_target() -> void:
	var w: Dictionary = _make_world()
	var preacher: Unit = _spawn(w, PREACHER_SCENE, 0, Vector2(30, 30))
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(33, 30))
	enemy.max_health = 1000000
	enemy.health = 1000000
	var attackers: Array = []
	var offs: Array[Vector2] = [Vector2(0.9, 0), Vector2(-0.9, 0), Vector2(0, 0.9),
		Vector2(0, -0.9), Vector2(0.7, 0.7)]
	for o in offs:
		var a: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(33, 30) + o)
		a.order_attack(enemy)
		attackers.append(a)

	var units: Array = [preacher, enemy]
	units.append_array(attackers)
	_run(w, units, func() -> bool: return enemy.state == Unit.State.SIT)
	check(enemy.state == Unit.State.SIT, "the target sits despite being attacked")
	# Let every attacker run its one-time roll.
	for i in range(5):
		for u: Unit in units:
			if u.state != Unit.State.DEAD:
				u.tick(TICK)
		w.unit_manager.tick(TICK)
	var still_fighting: int = 0
	for a: Unit in attackers:
		if a.attack_target == enemy:
			still_fighting += 1
	# 5% keep-fighting chance: statistically at least 3 of 5 break off
	# (P(fail) ~0.1%); usually all 5 do.
	check(still_fighting <= 2, "attackers break off against the sitting target")
	_free_world(w)


## A sitting (pacified) unit accepts no orders at all: it keeps sitting and
## converting until the preaching is interrupted.
func test_sitting_unit_refuses_orders() -> void:
	var w: Dictionary = _make_world()
	var preacher: Unit = _spawn(w, PREACHER_SCENE, 0, Vector2(30, 30))
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(33, 30))
	var other: Unit = _spawn(w, BRAVE_SCENE, 0, Vector2(40, 30))
	var pair: Array = [preacher, enemy]
	_run(w, pair, func() -> bool: return enemy.state == Unit.State.SIT)
	check(enemy.state == Unit.State.SIT, "the brave sits")
	check(not enemy.can_take_orders(), "a sitting unit reports it takes no orders")

	enemy.order_move(Vector3(50, 0, 30))
	check(enemy.state == Unit.State.SIT, "order_move is ignored while sitting")
	check(enemy.get_remaining_path().is_empty() and enemy.waypoint_queue.is_empty(),
		"no route was accepted while sitting")
	enemy.order_attack(other)
	check(enemy.state == Unit.State.SIT, "order_attack is ignored while sitting")
	check(enemy.attack_target == null, "no attack target was accepted while sitting")
	(enemy as Brave).order_chop(null)   # harmless no-op, must not throw
	check(enemy.state == Unit.State.SIT, "worker orders are ignored while sitting")

	# The spell still completes despite the ignored orders.
	_run(w, pair, func() -> bool: return enemy.tribe_id == 0)
	check(enemy.tribe_id == 0, "conversion still completes afterwards")
	_free_world(w)


## A fireball hit on a sitting unit resets its conversion progress and it
## stands back up.
func test_fireball_resets_conversion() -> void:
	var w: Dictionary = _make_world()
	var preacher: Unit = _spawn(w, PREACHER_SCENE, 0, Vector2(30, 30))
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(33, 30))
	enemy.max_health = 1000
	enemy.health = 1000
	var pair: Array = [preacher, enemy]
	_run(w, pair, func() -> bool: return enemy.conversion_progress > 0.5)
	check(enemy.state == Unit.State.SIT, "the target sits with progress > 0.5")

	var shooter: Unit = _spawn(w, FIREWARRIOR_SCENE, 1, Vector2(26, 30))
	var ball: Fireball = Fireball.new()
	ball.setup(shooter, enemy, shooter.position + Vector3(0.0, 1.1, 0.0))
	var ticks: int = 0
	while not ball.done and ticks < 200:
		ball.tick(TICK)
		ticks += 1
	check(ball.done, "the fireball reached the sitting unit")
	check(enemy.conversion_progress == 0.0, "the conversion progress was reset")
	check(enemy.state != Unit.State.SIT, "the unit stands back up")
	ball.free()
	_free_world(w)


func test_brave_retaliates_but_does_not_aggro() -> void:
	var w: Dictionary = _make_world()
	var brave: Unit = _spawn(w, BRAVE_SCENE, 0, Vector2(30, 30))
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(33, 30))
	# A brave never seeks out enemies on its own.
	for i in range(10):
		brave.tick(TICK)
		w.unit_manager.tick(TICK)
	check(brave.state == Unit.State.IDLE, "brave does not aggro over distance")
	check(brave.attack_target == null, "brave has no target while merely idle")
	# But it fights back when attacked.
	brave.take_damage(5, enemy)
	check(brave.state == Unit.State.ATTACK, "brave retaliates when hit")
	check(brave.attack_target == enemy, "brave targets its attacker")
	_free_world(w)
