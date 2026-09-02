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


# --- Combat approach pathing -------------------------------------------------------

## A combat-approach path must not begin with the unit's OWN cell centre: moving
## off-centre, heading there first is a backward/sideways dart, and _approach
## re-plans it every tick against a moving target -> jitter instead of pursuit
## (firewarrior-vs-moving-airship / preacher wobble; the pedestrian sibling of the
## fire-ram fix).
func test_combat_path_skips_redundant_own_cell_waypoint() -> void:
	var w: Dictionary = _make_world()
	var cell: Vector2i = Vector2i(30, 30)
	var base: Vector3 = w.nav.cell_to_world(cell)
	# Spawn a ranged unit noticeably off-centre inside its cell.
	var fw: Unit = w.unit_manager.spawn_unit(
		FIREWARRIOR_SCENE, 0, base + Vector3(0.35, 0.0, 0.0))
	check(w.nav.world_to_cell(fw.position) == cell, "unit is inside cell (30,30)")
	check(fw._plan_path_to(w.nav.cell_to_world(Vector2i(40, 30))),
		"combat path to a far cell planned")
	var p: PackedVector3Array = fw._path
	check(p.size() > 0, "non-empty path")
	if p.size() > 0:
		check(w.nav.world_to_cell(p[0]) != cell,
			"path skips the redundant own-cell first waypoint (no backward dart)")
	_free_world(w)


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


## A defeated unit lies as a corpse (dead sprite, on the ground) for
## CORPSE_DURATION, then sinks into the ground and is removed from the world.
func test_corpse_lies_then_sinks_and_expires() -> void:
	var w: Dictionary = _make_world()
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	unit.take_damage(1000)
	check(unit.state == Unit.State.DEAD, "unit is dead")
	check(unit in w.unit_manager.units, "corpse remains in the world")
	check(unit.anim_base_name == &"dead", "corpse uses the dead sprite")
	check(unit.corpse_sink_depth() == 0.0, "corpse starts on the ground")

	# Half a second before the lie time ends: still on the surface.
	for i in range(int((Unit.CORPSE_DURATION - 0.5) / TICK)):
		unit.tick(TICK)
	check(unit in w.unit_manager.units, "still lying before CORPSE_DURATION")
	check(unit.corpse_sink_depth() == 0.0, "not sinking before CORPSE_DURATION")

	# Half a second into the sink: depth strictly between 0 and the full depth.
	for i in range(10):
		unit.tick(TICK)
	var depth: float = unit.corpse_sink_depth()
	check(depth > 0.0 and depth < Unit.CORPSE_SINK_DEPTH,
		"corpse sinks after CORPSE_DURATION")

	# Past lying + sinking (CORPSE_SINK_DURATION = 1 s): expired and removed.
	for i in range(10):
		unit.tick(TICK)
	check(unit not in w.unit_manager.units, "corpse removed after sinking")
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
	# Attack-move (aggressive) — a plain move marches past since phase 7b.
	blue.order_move(Vector3(58, 0, 30), false, true)
	red.order_move(Vector3(16, 0, 30), false, true)
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


## In melee range with a free slot the firewarrior must DEFEND in melee (no
## fireballs, brave-level brawl) — it does not kite away.
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
	check(w.unit_manager.projectiles.is_empty(), "no fireballs thrown while brawling in melee")
	check(fw.attack_anim != &"throw", "melee uses a strike anim, not throw")
	_free_world(w)


## When all three melee slots on the target are taken, a firewarrior that is
## itself in melee range does NOT stand idle as an overflow attacker — it fires
## fireballs as a reserve row.
func test_firewarrior_reserve_row_fires_when_slots_full() -> void:
	var w: Dictionary = _make_world()
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	enemy.max_health = 1000000
	enemy.health = 1000000
	# Fill the enemy's three melee slots with brawler stubs.
	var stubs: Array[Brave] = []
	for i in range(Unit.MAX_MELEE_ATTACKERS):
		var s: Brave = Brave.new()
		s.attack_target = enemy
		s.state = Unit.State.ATTACK
		enemy.request_melee_slot(s)
		stubs.append(s)
	check(enemy.active_melee_attacker_count() == Unit.MAX_MELEE_ATTACKERS,
		"all three melee slots are taken")

	var fw: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(30.8, 30))  # melee range
	fw.order_attack(enemy)
	var hp0: int = enemy.health
	# The three brawler stubs are not ticked, so ONLY the firewarrior's fireball
	# can damage the enemy — any HP loss proves the reserve fired (a 4th melee
	# attacker gets no slot and would deal nothing).
	_run(w, [fw], func() -> bool: return enemy.health < hp0)
	check(enemy.health < hp0, "the reserve firewarrior fires when the melee slots are full")
	check(fw.attack_anim == &"throw", "reserve row plays the throw animation")
	check(enemy.active_melee_attacker_count() == Unit.MAX_MELEE_ATTACKERS,
		"the reserve firewarrior did not take a melee slot")
	for s in stubs:
		s.free()
	_free_world(w)


## A firewarrior must STAND STILL to fire: within fire range it holds position
## (clears its path) and throws — it does not move while shooting. It only moves
## to close the distance when the target is beyond FIRE_RANGE.
func test_firewarrior_stands_still_to_fire() -> void:
	var w: Dictionary = _make_world()
	var fw: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(30, 30))
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(35, 30))  # 5 m: fire range
	enemy.max_health = 1000000
	enemy.health = 1000000
	fw.order_attack(enemy)
	var start: Vector2 = Vector2(fw.position.x, fw.position.z)
	var hp0: int = enemy.health
	_run(w, [fw], func() -> bool: return enemy.health < hp0)
	check(enemy.health < hp0, "firewarrior fired from fire range")
	var moved: float = Vector2(fw.position.x, fw.position.z).distance_to(start)
	check(moved < 0.3, "firewarrior stood still to fire (moved %.2f m)" % moved)
	check(not fw._has_path(), "no pending movement path while firing")
	_free_world(w)


## Firewarriors prioritise enemy preachers: given a nearer brave and a farther
## priest (both in range), the target scan returns the priest.
func test_firewarrior_prioritises_enemy_priests() -> void:
	var w: Dictionary = _make_world()
	var fw: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(30, 30))
	_spawn(w, BRAVE_SCENE, 1, Vector2(33, 30))            # 3 m: nearer
	var priest: Unit = _spawn(w, PREACHER_SCENE, 1, Vector2(38, 30))  # 8 m: farther, in range
	w.unit_manager.tick(TICK)   # refresh the spatial hash
	var target: Unit = fw._scan_for_enemy(fw.aggro_radius())
	check(target == priest, "firewarrior targets the enemy priest over a nearer brave")
	_free_world(w)


## An AUTO-acquired firewarrior (idle engage, no explicit order) still switches to
## an enemy priest that comes into range mid-fight — priest priority is preserved
## for auto targets.
func test_auto_firewarrior_switches_to_priest_midfight() -> void:
	var w: Dictionary = _make_world()
	var fw: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(30, 30))
	var brave_enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(35, 30))  # 5 m
	brave_enemy.max_health = 100000   # survive so we test the SWITCH, not a re-target after death
	brave_enemy.health = 100000
	# It auto-engages the lone brave first (no priest present yet, so no order).
	_run(w, [fw], func() -> bool: return fw.attack_target == brave_enemy)
	check(fw.attack_target == brave_enemy, "auto-engaged the brave")
	check(not fw._target_ordered, "an auto-acquired target is NOT flagged as ordered")
	var priest: Unit = _spawn(w, PREACHER_SCENE, 1, Vector2(36, 30))    # 6 m
	_run(w, [fw], func() -> bool: return fw.attack_target == priest)
	check(fw.attack_target == priest, "auto firewarrior switches to the priest in range")
	_free_world(w)


## An ORDERED firewarrior obeys the command: it keeps firing at the unit it was
## told to attack and does NOT auto-switch to an enemy priest that comes into
## range (explicit orders are sticky for ranged units — user bug report).
func test_ordered_firewarrior_ignores_priest_priority() -> void:
	var w: Dictionary = _make_world()
	var fw: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(30, 30))
	fw.max_health = 100000
	fw.health = 100000
	var brave_enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(35, 30))  # 5 m
	brave_enemy.max_health = 100000
	brave_enemy.health = 100000
	var priest: Unit = _spawn(w, PREACHER_SCENE, 1, Vector2(36, 30))    # 6 m, in aggro
	priest.max_health = 100000
	priest.health = 100000
	fw.order_attack(brave_enemy)
	check(fw._target_ordered, "the explicit attack order flags the target as ordered")
	# Run well past the scan cadence; the fw must never flip to the priest.
	_run(w, [fw], func() -> bool: return fw.attack_target != brave_enemy)
	check(fw.attack_target == brave_enemy,
		"ordered firewarrior ignores priest priority and stays on its commanded target")
	_free_world(w)


## A firewarrior reacts to enemies beyond the melee aggro radius (so it defends
## a neighbour being shot from fire range), then closes in and fires.
func test_firewarrior_aggro_reaches_past_melee_radius() -> void:
	var w: Dictionary = _make_world()
	var fw: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(30, 30))
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(40, 30))  # 10 m away
	enemy.max_health = 1000
	enemy.health = 1000
	check(10.0 > Unit.AGGRO_RADIUS, "the enemy is beyond the melee aggro radius (8)")
	check(10.0 < Firewarrior.RANGED_AGGRO, "but within the firewarrior's ranged aggro")
	var hp0: int = enemy.health
	_run(w, [fw], func() -> bool: return enemy.health < hp0)
	check(enemy.health < hp0,
		"an idle firewarrior engages and fires on an enemy past the melee aggro range")
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
	climber._sync_soa_pos()
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


## Stars = CRITICAL damage (<= 25 % health); burning has display priority.
func test_stars_show_critical_damage_and_fire_priority() -> void:
	var w: Dictionary = _make_world()
	var crit: Unit = _spawn(w, BRAVE_SCENE, 0, Vector2(30, 30))
	crit.take_damage(5)
	check(not crit.has_stars(), "light damage shows no stars")
	crit.take_damage(crit.health - int(float(crit.max_health) * Unit.BADLY_HURT_FRAC))
	check(crit.has_stars(), "critical damage shows the circling stars")
	var burning: Unit = _spawn(w, BRAVE_SCENE, 0, Vector2(34, 30))
	burning.ignite(burning.position)   # lava contact damage + alight + panic
	# Drop to exactly the critical threshold (independent of the lava damage).
	burning.take_damage(
		burning.health - int(float(burning.max_health) * Unit.BADLY_HURT_FRAC))
	check(burning.is_burning(), "second unit is alight")
	check(burning.health <= int(float(burning.max_health) * Unit.BADLY_HURT_FRAC),
		"second unit is critical")
	check(not burning.has_stars(), "burning suppresses the stars")
	crit.take_damage(1000)
	check(not crit.has_stars(), "corpses never show stars")
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
	check(&"preach_enemy" in CombatAudio.KINDS
		and &"preach_enemy" in CombatAudio.SINGLE_VARIANT_KINDS,
		"the enemy chant is a kind of its own, with one file")
	check(CombatAudio.generate_samples(&"preach_enemy", 0)
		!= CombatAudio.generate_samples(&"preach", 0),
		"the enemy chant really sounds different (not the same timbre twice)")


## The enemy chant must be selected by TRIBE, and from the local player's point
## of view (user request: a foreign sermon has to be audible as such). Own tribe
## is GameState.PLAYER_TRIBE = 0, so a preacher of tribe 1 is the enemy.
func test_preacher_chant_kind_follows_the_tribe() -> void:
	var w: Dictionary = _make_world()
	var mine: Unit = _spawn(w, PREACHER_SCENE, 0, Vector2(30, 30))
	var theirs: Unit = _spawn(w, PREACHER_SCENE, 1, Vector2(40, 30))
	check(mine.chant_sfx_kind() == &"preach", "our own preacher keeps the old chant")
	check(theirs.chant_sfx_kind() == &"preach_enemy", "an enemy preacher sings the other one")
	# A hypnotized enemy preacher preaches for us, so he sounds like ours.
	theirs.hypnotize(w.tribe0, 30.0)
	check(theirs.chant_sfx_kind() == &"preach",
		"while hypnotized he is on our side and sounds like it")
	_free_world(w)


## The landing sound only belongs to a touchdown the unit walks away from: a
## ragdoll (lethally hit in mid-air) lands silently, its death cry follows at
## the end of the tumble. Later roll damage is explicitly not considered.
func test_land_sfx_key_only_for_survivors() -> void:
	var w: Dictionary = _make_world()
	var lucky: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	lucky.throw_airborne(Vector3(1, 0, 0) * 4.0 + Vector3.UP * 5.0)
	check(lucky.land_sfx_key() == &"unit_land", "a body that survives thuds down")
	var doomed: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(34, 30))
	doomed.throw_airborne(Vector3(1, 0, 0) * 4.0 + Vector3.UP * 5.0)
	doomed.take_damage(10000)
	check(doomed.doomed, "the mid-air hit made it a ragdoll")
	check(doomed.land_sfx_key() == &"", "a ragdoll lands silently — its death cry carries it")
	_free_world(w)


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
	check(views.size() == 8, "punch exists in all eight views")
	check(int(views[0][1]) == 4, "punch alternates both fists (4 frames)")


## Phase 10a: flying through the air and dying in water are their own
## animations, for every kind. The frame counts are asserted so the atlas
## (5 kinds x 8 views) cannot silently balloon.
func test_airborne_and_drown_anims_in_atlas() -> void:
	var atlas: Dictionary = PlaceholderSprites.build_atlas(
		[&"brave", &"warrior", &"firewarrior"] as Array[StringName])
	var table: Dictionary = atlas.table
	for kind: StringName in [&"brave", &"warrior", &"firewarrior"]:
		check(table[kind].has(&"airborne"), "%s has an airborne animation" % kind)
		check(table[kind].has(&"drown"), "%s has a drown animation" % kind)
		check((table[kind][&"airborne"] as Array).size() == 8,
			"%s airborne exists in all eight views" % kind)
		check((table[kind][&"drown"] as Array).size() == 8,
			"%s drown exists in all eight views" % kind)
	check(int(table[&"brave"][&"airborne"][0][1]) == 2, "airborne has 2 frames")
	check(int(table[&"brave"][&"drown"][0][1]) == 3, "drown has 3 frames")


## The two LYING poses are painted UPRIGHT into the portrait cell (the renderer
## rolls them 90 degrees), so their ink must run along the LONG cell axis. A
## corpse painted lying down again would be 0.96 m short — and would stand up
## on screen once the roll is applied.
func test_lying_poses_are_drawn_along_the_long_cell_axis() -> void:
	for anim: StringName in PlaceholderSprites.FLAT_ANIMS:
		for slot in range(PlaceholderSprites.slot_count(anim)):
			var frames: Array[Image] = PlaceholderSprites.build_slot(&"brave", anim, slot)
			check(not frames.is_empty(), "%s/%d has frames" % [anim, slot])
			var box: Rect2i = _ink_box(frames[0])
			check(box.size.y >= 20,
				"%s/%d fills the long cell axis (%d of %d px)"
					% [anim, slot, box.size.y, PlaceholderSprites.H])
			check(box.size.y > box.size.x,
				"%s/%d runs along y, not along x" % [anim, slot])


## A viewless pose's eight table entries carry its VARIANTS, not views: the ones
## past the variant count point back at variant 0 instead of storing identical
## copies. The corpse's two landings are genuinely different drawings; the flying
## body has a single one.
func test_viewless_pose_stores_variants_not_views() -> void:
	var atlas: Dictionary = PlaceholderSprites.build_atlas(
		[&"brave", &"warrior"] as Array[StringName])
	var table: Dictionary = atlas.table
	for kind: StringName in [&"brave", &"warrior"]:
		for anim: StringName in PlaceholderSprites.FLAT_ANIMS:
			var entries: Array = table[kind][anim]
			var variants: int = PlaceholderSprites.slot_count(anim)
			check(entries.size() == 8, "%s/%s still has eight entries" % [kind, anim])
			for i in range(variants, entries.size()):
				check(int(entries[i][0]) == int(entries[0][0]),
					"%s/%s entry %d falls back on variant 0" % [kind, anim, i])
				check(int(entries[i][1]) == int(entries[0][1]),
					"%s/%s entry %d has the same frame count" % [kind, anim, i])
			for i in range(1, variants):
				check(int(entries[i][0]) != int(entries[0][0]),
					"%s/%s variant %d has its own slots" % [kind, anim, i])
	# The two corpse landings must not be the same picture — that is the whole
	# point of the variants.
	var supine: PackedByteArray = PlaceholderSprites.build_slot(
		&"warrior", &"dead", 0)[0].get_data()
	var prone: PackedByteArray = PlaceholderSprites.build_slot(
		&"warrior", &"dead", 1)[0].get_data()
	check(supine != prone, "the corpse on its back differs from the one on its belly")


## Row counts the sheet loader accepts, and how each maps rows to views. The
## 1-row variant exists for the viewless poses: the artist delivers one row.
func test_sheet_cut_plan_row_variants() -> void:
	for bad: int in [0, 2, 3, 4, 6, 7, 9, 16]:
		check(UnitSpriteLibrary.sheet_cut_plan(bad).is_empty(),
			"%d rows is not a valid sheet" % bad)
	var one: Dictionary = UnitSpriteLibrary.sheet_cut_plan(1)
	check(one.size() == 8, "a 1-row sheet still fills all eight views")
	for view: StringName in PlaceholderSprites.VIEWS:
		check(int(one[view][0]) == 0, "%s reads row 1 of a 1-row sheet" % view)
		check(not bool(one[view][1]), "%s is not mirrored on a 1-row sheet" % view)
	var five: Dictionary = UnitSpriteLibrary.sheet_cut_plan(5)
	check(five.size() == 8, "a 5-row sheet fills all eight views")
	check(int(five[&"right"][0]) == 2 and not bool(five[&"right"][1]),
		"right is drawn in row 3 of a 5-row sheet")
	check(int(five[&"left"][0]) == int(five[&"right"][0]) and bool(five[&"left"][1]),
		"left mirrors the right row")
	check(bool(five[&"front_left"][1]) and bool(five[&"back_left"][1]),
		"both left diagonals are mirrored")
	var eight: Dictionary = UnitSpriteLibrary.sheet_cut_plan(8)
	check(eight.size() == 8, "an 8-row sheet fills all eight views")
	for i in range(PlaceholderSprites.VIEWS.size()):
		var view: StringName = PlaceholderSprites.VIEWS[i]
		check(int(eight[view][0]) == i and not bool(eight[view][1]),
			"an 8-row sheet draws %s in row %d" % [view, i + 1])


## Bounding box of the opaque pixels of a placeholder frame.
static func _ink_box(img: Image) -> Rect2i:
	var x0: int = img.get_width()
	var y0: int = img.get_height()
	var x1: int = -1
	var y1: int = -1
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.5:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	return Rect2i() if x1 < 0 else Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


## The cast animation exists (phase 6) and stays caster-only.
func test_cast_anim_is_caster_only() -> void:
	var atlas: Dictionary = PlaceholderSprites.build_atlas(
		[&"shaman", &"preacher", &"brave", &"warrior"] as Array[StringName])
	var table: Dictionary = atlas.table
	check(table[&"shaman"].has(&"cast"), "the shaman has a cast animation")
	check(table[&"preacher"].has(&"cast"), "the preacher has a cast animation")
	check(not table[&"brave"].has(&"cast"), "the brave has no cast animation")
	check(not table[&"warrior"].has(&"cast"), "the warrior has no cast animation")


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
	# The impact charges knockback AWAY from the shooter (+x, shooter sits at x=26).
	# Assert the knockback in ISOLATION: a full unit tick would also run the enemy's
	# retaliation walk toward the shooter (brave speed 4 m/s > the 0.35 m shove),
	# which would mask the shove — that is expected AI, not a knockback failure.
	check(enemy._knockback_remaining.x > 0.0,
		"the impact shoves the target away from the shooter (+x)")
	check(enemy.knockback_accum > 0.0, "the hit charged the knockback accumulator")
	var x0: float = enemy.position.x
	enemy._tick_knockback(TICK)
	check(enemy.position.x > x0, "the knockback displaces the target away from the shooter")
	ball.free()
	_free_world(w)


# --- Phase 10c: lift instead of a ground shove -------------------------------------

## A ball that hits an ALREADY flying target never shoves the ground (a shove
## on a flying unit did nothing sensible anyway) — it always whirls it higher.
func test_firewarrior_fireball_always_lifts_airborne_target() -> void:
	var w: Dictionary = _make_world()
	var shooter: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(26, 30))
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	enemy.max_health = 100000
	enemy.health = 100000
	enemy.throw_airborne(Vector3(1.0, 0.0, 0.0) * 2.0 + Vector3.UP * 5.0)
	check(enemy.state == Unit.State.THROWN, "the target is in the air")
	var vy: float = enemy._throw_velocity.y
	var vx: float = enemy._throw_velocity.x
	var ball: Fireball = Fireball.new()
	ball.setup(shooter, enemy, shooter.position + Vector3(0.0, 1.1, 0.0))
	var ticks: int = 0
	while not ball.done and ticks < 200:
		ball.tick(TICK)
		ticks += 1
	check(ball.done, "fireball impacted")
	check(enemy._knockback_remaining == Vector3.ZERO,
		"no ground shove on a flying target")
	check(enemy._throw_velocity.y >= vy + Balance.LIFT_AIRBORNE_BONUS,
		"the hit adds height instead")
	check(enemy._throw_velocity.x > vx, "and a little more push along the flight")
	ball.free()
	_free_world(w)


## A ball chasing a whirled-up target keeps picking up speed until it catches
## it — at the flat base speed the shots just trailed behind (user report).
func test_firewarrior_fireball_accelerates_after_airborne_target() -> void:
	var w: Dictionary = _make_world()
	var shooter: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(20, 30))
	var flyer: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	flyer.max_health = 100000
	flyer.health = 100000
	# Hurled away from the shooter, faster than the ball's base speed.
	flyer.throw_airborne(Vector3(1, 0, 0) * (Fireball.SPEED * 1.2) + Vector3.UP * 5.0)
	check(flyer.is_airborne(), "the target is in the air and running away")
	var ball: Fireball = Fireball.new()
	ball.terrain_data = w.td
	ball.setup(shooter, flyer, shooter.position + Vector3(0.0, 1.1, 0.0))
	check(ball._speed == Fireball.SPEED, "it launches at the base speed")
	var ticks: int = 0
	while not ball.done and ticks < 200:
		ball.tick(TICK)
		if flyer.state == Unit.State.THROWN:
			flyer.tick(TICK)
		ticks += 1
	check(ball._speed > Fireball.SPEED,
		"the chase sped it up (%.1f -> %.1f m/s)" % [Fireball.SPEED, ball._speed])
	check(ball._speed <= Fireball.AIR_MAX_SPEED, "but not past the cap")
	check(flyer.health < 100000, "and it actually caught up and hit")
	ball.free()
	_free_world(w)


## A ground target needs no chase bonus: the ball stays at its base speed.
func test_firewarrior_fireball_keeps_base_speed_on_the_ground() -> void:
	var w: Dictionary = _make_world()
	var shooter: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(26, 30))
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	enemy.max_health = 100000
	enemy.health = 100000
	var ball: Fireball = Fireball.new()
	ball.setup(shooter, enemy, shooter.position + Vector3(0.0, 1.1, 0.0))
	var ticks: int = 0
	while not ball.done and ticks < 200:
		ball.tick(TICK)
		ticks += 1
	check(ball._speed == Fireball.SPEED, "no acceleration against a walker")
	check(enemy.health < 100000, "the shot still lands")
	ball.free()
	_free_world(w)


## The airborne damage bonus applies to HURLED units, not only to airship deck
## crew — Unit.is_airborne() is `THROWN or rides_airborne()`. This had no guard
## at all until the lift made the combo reliable (user question).
func test_firewarrior_fireball_bonus_hits_hurled_targets() -> void:
	var w: Dictionary = _make_world()
	var shooter: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(26, 30))
	var ground: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	var flying: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 34))
	for victim in [ground, flying]:
		victim.max_health = 100000
		victim.health = 100000
	flying.throw_airborne(Vector3.UP * 5.0)
	check(flying.is_airborne(), "the second victim is in the air")

	var plain: int = _fireball_damage(w, shooter, ground)
	var lifted: int = _fireball_damage(w, shooter, flying)
	check(plain == Unit.FIREBALL_DAMAGE,
		"a walking target takes the plain %d" % Unit.FIREBALL_DAMAGE)
	check(lifted > plain, "a hurled one takes more (%d vs %d)" % [lifted, plain])
	check(lifted == int(roundf(float(Unit.FIREBALL_DAMAGE)
		* Balance.FIREWARRIOR_AIRBORNE_MULT)),
		"...exactly the balance bonus")
	# Phase 10c: a +20 % bonus, no longer double.
	check(Balance.FIREWARRIOR_AIRBORNE_MULT < 1.5,
		"the bonus is a surcharge, not a doubling")
	_free_world(w)


## Flies one ball at `victim` and returns the damage it dealt.
func _fireball_damage(w: Dictionary, shooter: Unit, victim: Unit) -> int:
	var before: int = victim.health
	var ball: Fireball = Fireball.new()
	ball.setup(shooter, victim, shooter.position + Vector3(0.0, 1.1, 0.0))
	var ticks: int = 0
	while not ball.done and ticks < 400:
		ball.tick(TICK)
		if victim.state == Unit.State.THROWN:
			victim.tick(TICK)   # keep it airborne while the ball closes in
		ticks += 1
	ball.free()
	return before - victim.health


# --- Phase 10j: the rim replaces the wall ------------------------------------------

## Phase 10c put an invisible wall at the map border because a thrown shaman ended
## up outside the map. 10j inverts that: the world is a DISC, outside it there is no
## ground, and leaving it became a mechanic instead of a bug. The two bounce tests
## that lived here are gone with the wall; the fall itself is covered by
## tests/test_void_fall.gd. What stays is the movement-path invariant — with the
## opposite verdict.

## _snap_to_ground is the wide net every ordinary movement writer funnels through.
## It used to clamp a stray position back inside the map; now it starts the fall.
func test_snap_to_ground_over_the_void_starts_a_void_fall() -> void:
	var w: Dictionary = _make_world()
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	# Force the position into the void the way a rogue movement writer would.
	unit.position = Vector3(float(w.td.size) + 25.0, 5.0, -12.0)
	unit._snap_to_ground()
	check(unit.state == Unit.State.DEAD,
		"a unit over the void dies instead of standing on phantom ground")
	check(unit.death_sfx_key() == &"", "and it dies silently")
	_free_world(w)


## A shove over the rim: the other way a unit used to be pushed out of the world.
##
## The victim has to start at the very outer edge of the last real cell, because
## apply_knockback() uses its argument only as a DIRECTION — one shove is
## KNOCKBACK_BASE (0.35 m), not the vector's length. So a single shove can only tip
## someone over the rim who is already standing on the brink; that is a property of
## the shove, not of the rim, and stacked knockback covers the rest.
func test_knockback_over_the_rim_launches_into_the_void() -> void:
	var w: Dictionary = _make_world()
	var mid: int = w.td.size / 2
	# Outermost cell along +x that still exists, derived rather than hardcoded.
	var last: int = mid
	while w.td.in_disc(Vector2i(last + 1, mid)):
		last += 1
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1,
		Vector2(float(last) + 0.95, float(mid) + 0.5))
	victim.max_health = 100000
	victim.health = 100000
	check(w.nav.is_cell_walkable(Vector2i(last, mid)),
		"the victim starts on real ground at the brink")
	victim.apply_knockback(Vector3(1, 0, 0))
	var fell: bool = false
	for i in range(120):
		victim.tick(TICK)
		if victim.state == Unit.State.DEAD or victim.state == Unit.State.THROWN:
			fell = true
			break
	check(fell, "the shove carried it over the rim instead of into a wall")
	_free_world(w)


## Deck passengers ride the airship; nothing throws them off it.
func test_apply_lift_ignores_deck_passengers() -> void:
	var w: Dictionary = _make_world()
	var ship: Airship = w.unit_manager.spawn_unit(
		preload("res://scenes/units/airship.tscn"), 0, Vector3(30, 5, 30))
	var crew: Unit = _spawn(w, BRAVE_SCENE, 0, Vector2(30, 31))
	crew.order_crew(ship)
	var ticks: int = 0
	while not crew.is_crew_seated() and ticks < 400:
		crew.tick(TICK)
		w.unit_manager.tick(TICK)
		ticks += 1
	check(crew.rides_airborne(), "the brave rides the deck")
	var before: int = crew.state
	crew.apply_lift(Vector3(1, 0, 0), 8.0, 9.0)
	check(crew.state == before, "apply_lift leaves a deck passenger alone")
	check(crew.state != Unit.State.THROWN, "...it is never thrown off the ship")
	_free_world(w)


## The lightning hands over raw difference vectors — a unit standing exactly on
## the strike point yields a ZERO direction. It must still be launched, in some
## direction, instead of straight up or not at all.
func test_apply_lift_zero_direction_fallback() -> void:
	var w: Dictionary = _make_world()
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	victim.apply_lift(Vector3.ZERO, 6.0, 7.0)
	check(victim.state == Unit.State.THROWN, "a zero direction still launches")
	var flat: Vector2 = Vector2(victim._throw_velocity.x, victim._throw_velocity.z)
	check_near(flat.length(), 6.0, "the horizontal speed is the requested one")
	check_near(victim._throw_velocity.y, 7.0, "and so is the vertical one")
	_free_world(w)


## An unnormalised direction (the callers hand over raw offsets) must not scale
## the launch speed with the distance.
func test_apply_lift_normalises_the_direction() -> void:
	var w: Dictionary = _make_world()
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	victim.apply_lift(Vector3(12.0, 99.0, 0.0), 5.0, 6.0)
	var flat: Vector2 = Vector2(victim._throw_velocity.x, victim._throw_velocity.z)
	check_near(flat.length(), 5.0, "length and Y of the direction are ignored")
	check_near(victim._throw_velocity.y, 6.0, "the vertical speed is the parameter")
	_free_world(w)


## Stacked lifts must not fling anyone out of the picture: however many
## fireballs pile onto a flying unit, the arc tops out LIFT_MAX_HEIGHT above
## the ground below.
func test_throw_height_is_capped() -> void:
	var w: Dictionary = _make_world()
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	victim.max_health = 100000
	victim.health = 100000
	var ground: float = w.td.get_height(victim.position.x, victim.position.z)
	var peak: float = 0.0
	for i in range(200):
		# A fireball lands on it every few ticks — the worst case the spells
		# can produce (Unit.apply_lift stacks the velocity every time).
		if i % 4 == 0:
			victim.apply_lift(Vector3(1, 0, 0), Balance.FIREBALL_PUSH_SPEED,
				Balance.FIREBALL_LIFT_SPEED)
		victim.tick(0.02)
		peak = maxf(peak, victim.position.y - ground)
	check(peak > 1.0, "the lifts do get it off the ground (peak %.2f m)" % peak)
	# One frame of overshoot is allowed: the ceiling zeroes the RISE, it never
	# teleports the body back down.
	check(peak <= Balance.LIFT_MAX_HEIGHT + 0.5,
		"never higher than %.1f m (peak %.2f m)" % [Balance.LIFT_MAX_HEIGHT, peak])
	_free_world(w)


## A body hurled off an airship deck STARTS above the ceiling — the cap must
## not snap it down to 6 m, it just falls from where it is.
func test_height_cap_never_teleports_a_high_body_down() -> void:
	var w: Dictionary = _make_world()
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	victim.position.y = 20.0
	victim.throw_airborne(Vector3(1.0, 0.0, 0.0) * 2.0 + Vector3.UP * 3.0)
	victim.tick(0.05)
	check(victim.position.y > 15.0,
		"still up at %.1f m, not snapped to the ceiling" % victim.position.y)
	var y0: float = victim.position.y
	victim.tick(0.05)
	check(victim.position.y < y0, "and it falls from there")
	_free_world(w)


# --- Phase 10c: ragdoll — dead in mid-air stops costing anything -------------------

## The lethal hit still lands mid-air but the death stays deferred to the
## ground (a body must never wink out at altitude). Everything the world
## tracked about the unit is released immediately, though.
func test_airborne_death_enters_ragdoll() -> void:
	var w: Dictionary = _make_world()
	var attacker: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(30, 30))
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30.8, 30))
	attacker.order_attack(victim)
	_run(w, [attacker], func() -> bool: return victim.health < victim.max_health)
	check(victim.combat_group != null, "the fight is bound before the throw")
	victim.order_move(Vector3(50, 0, 50))
	victim.throw_airborne(Vector3(1, 0, 0) * 4.0 + Vector3.UP * 5.0)
	check(victim.state == Unit.State.THROWN, "the victim is in the air")
	victim.take_damage(10000, attacker)
	check(victim.state == Unit.State.THROWN,
		"no death at altitude — it is still flying")
	check(victim.doomed, "...but it is flagged as a goner")
	check(not victim.is_targetable(), "a ragdoll is no target for anyone")
	check(victim.combat_group == null, "its fight dissolved right away")
	check(victim.waypoint_queue.is_empty(), "its orders are gone")
	check(attacker.combat_group == null,
		"the attacker is free to retarget immediately, not in three seconds")
	_free_world(w)


## The ragdoll still plays out: it flies, lands, tumbles and ends as a corpse.
func test_ragdoll_lands_and_becomes_a_corpse() -> void:
	var w: Dictionary = _make_world()
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	victim.throw_airborne(Vector3(1, 0, 0) * 4.0 + Vector3.UP * 5.0)
	victim.take_damage(10000)
	var start_x: float = victim.position.x
	var ticks: int = 0
	while victim.state != Unit.State.DEAD and ticks < 600:
		victim.tick(TICK)
		ticks += 1
	check(victim.state == Unit.State.DEAD, "the ragdoll ends as a corpse")
	check(victim.position.x > start_x, "and it travelled while it fell")
	check(victim.health == 0, "health is clamped to 0 on death")
	_free_world(w)


## Regeneration must never bring a ragdoll back: the doomed unit skips the
## regen tick entirely, so its negative health cannot creep back above zero.
func test_ragdoll_never_regenerates_back_to_life() -> void:
	var w: Dictionary = _make_world()
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	victim.throw_airborne(Vector3.UP * 5.0)
	victim.take_damage(10000)
	for i in range(50):
		if victim.state == Unit.State.DEAD:
			break
		victim.tick(TICK)
	check(victim.health <= 0, "a ragdoll never heals")
	_free_world(w)


## The scan masks read FLAG_TARGETABLE out of the SoA arrays — a ragdoll has
## to disappear from them, or the living keep chasing a dead man.
func test_ragdoll_drops_out_of_enemy_scans() -> void:
	var w: Dictionary = _make_world()
	var hunter: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(30, 30))
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(32, 30))
	w.unit_manager.tick(TICK)
	check(not w.unit_manager.get_enemy_candidates(
		hunter.position, 8.0, hunter.tribe_id, 8).is_empty(),
		"the living brave is a candidate")
	victim.throw_airborne(Vector3.UP * 5.0)
	victim.take_damage(10000)
	w.unit_manager.tick(TICK)
	check(w.unit_manager.get_enemy_candidates(
		hunter.position, 8.0, hunter.tribe_id, 8).is_empty(),
		"the ragdoll is gone from the enemy scan")
	_free_world(w)


# --- Preacher conversion (phase 5c) ------------------------------------------------

## A preacher near an enemy brave makes it sit, the progress runs, and on
## completion the unit has switched tribes (lists, tribe_id, colour signal).
func test_conversion_converts_enemy() -> void:
	var w: Dictionary = _make_world()
	var preacher: Unit = _spawn(w, PREACHER_SCENE, 0, Vector2(30, 30))
	# 4 m: inside the 5 m convert range but OUTSIDE the brave's 3 m idle-guard,
	# so the victim never aggros the preacher. At 3 m the brave sat right on its
	# own guard boundary, retaliated, and the ensuing brawl raced the conversion
	# (RNG fight-inertia / durations decided whether it converted or died first).
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(34, 30))  # in convert range
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
	# 4 m: convertible, but clear of the brave's 3 m idle-guard (see
	# test_conversion_converts_enemy) so it sits without a boundary brawl.
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(34, 30))
	var units: Array = [preacher, enemy]
	_run(w, units, func() -> bool: return enemy.state == Unit.State.SIT)
	check(enemy.state == Unit.State.SIT, "the brave sits before the duel")

	# An enemy preacher walks into range (still within the preacher's 5 m convert
	# range): duel instead of channeling.
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
	# 4 m: convertible, clear of the brave's 3 m idle-guard (see
	# test_conversion_converts_enemy) so the victim sits without a brawl race.
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(34, 30))
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
	# 4 m: convertible, clear of the brave's 3 m idle-guard (see
	# test_conversion_converts_enemy) so the victim sits without a brawl race.
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(34, 30))
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
	# 5 m away: outside the brave's small 3 m idle guard radius (phase 7b) —
	# the close-range aggro case is covered in test_unit_control.gd.
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(35, 30))
	# A brave never seeks out distant enemies on its own.
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


# --- Cliff fights (Ebene-Klippen, user bug report) -----------------------------------

## Terrain with a hard cliff at x = 40: low ground (5 m) west of it, a
## plateau (15 m) east of it, spanning the full map depth (no way around).
func _cliff_terrain() -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for vz in range(td.verts):
		for vx in range(td.verts):
			td.heights[vz * td.verts + vx] = 15.0 if vx >= 40 else 5.0
	return td


func _make_cliff_world() -> Dictionary:
	var td: TerrainData = _cliff_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var tribe0: Tribe = Tribe.new(0)
	var tribe1: Tribe = Tribe.new(1)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe0, tribe1] as Array[Tribe])
	return {"td": td, "nav": nav, "tribe0": tribe0, "tribe1": tribe1, "unit_manager": um}


## A fireball fired from the low ground at a target on the plateau smacks
## into the cliff face and fizzles — no damage through terrain edges.
func test_fireball_blocked_by_cliff_face() -> void:
	var w: Dictionary = _make_cliff_world()
	var shooter: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(36, 30))
	shooter.position.y = 5.0
	shooter._sync_soa_pos()
	var target: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(44, 30))
	target.position.y = 15.0
	target._sync_soa_pos()
	var hp_before: int = target.health
	var ball: Fireball = Fireball.new()
	ball.setup(shooter, target, shooter.position + Vector3(0.0, 1.1, 0.0))
	ball.terrain_data = w.td
	for i in range(60):
		if ball.done:
			break
		ball.tick(TICK)
	check(ball.done, "cliff fireball finished")
	check(target.health == hp_before, "no damage through the cliff face")
	ball.free()
	_free_world(w)


## Same shot on open flat ground still connects (the terrain check must not
## eat legitimate hits at chest height above the floor).
func test_fireball_still_hits_on_flat_ground() -> void:
	var w: Dictionary = _make_world()
	var shooter: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(30, 30))
	shooter.position.y = 5.0
	shooter._sync_soa_pos()
	var target: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(35, 30))
	target.position.y = 5.0
	target._sync_soa_pos()
	var hp_before: int = target.health
	var ball: Fireball = Fireball.new()
	ball.setup(shooter, target, shooter.position + Vector3(0.0, 1.1, 0.0))
	ball.terrain_data = w.td
	for i in range(60):
		if ball.done:
			break
		ball.tick(TICK)
	check(target.health < hp_before, "flat-ground fireball still hits")
	ball.free()
	_free_world(w)


## A melee unit trapped under the cliff with MANY enemies above must not
## re-run the expensive failing A* on every scan: the fail cooldown plus the
## (evicting, never-clearing) unreachable cache bound the plan-fail rate.
func test_trapped_attacker_throttles_failing_paths() -> void:
	var w: Dictionary = _make_cliff_world()
	var warrior: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(38, 30))
	warrior.position.y = 5.0
	warrior._sync_soa_pos()
	# 12 enemies on the plateau, inside the warrior's 8 m aggro radius but
	# unreachable — more than the OLD cache cap of 8 (which cleared wholesale
	# and thrashed forever).
	for i in range(12):
		var e: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(42.0 + float(i % 3), 27.0 + float(i / 3) * 2.0))
		e.position.y = 15.0
		e._sync_soa_pos()
	Unit.dbg_plan_calls = 0
	Unit.dbg_plan_fails = 0
	for i in range(50):   # 5 simulated seconds
		warrior.tick(TICK)
		w.unit_manager.tick(TICK)
	# 5 s / 0.8 s cooldown ≈ 6 failing plans max (+1 margin); the old code
	# produced one failing FULL-REGION A* per scan interval (dozens).
	check(Unit.dbg_plan_fails <= 8,
		"failing A* is throttled (%d fails in 5 s)" % Unit.dbg_plan_fails)
	check(warrior.state != Unit.State.DEAD, "warrior still alive/idle below the cliff")
	_free_world(w)


## The unreachable-target cache evicts single entries instead of clearing
## wholesale (the wholesale clear caused the thrash above).
func test_unreachable_cache_evicts_instead_of_clearing() -> void:
	var w: Dictionary = _make_world()
	var unit: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(30, 30))
	var targets: Array = []
	for i in range(Unit.UNREACHABLE_CACHE_MAX + 2):
		targets.append(_spawn(w, BRAVE_SCENE, 1, Vector2(60, 20 + i)))
	for t in targets:
		unit._mark_target_unreachable(t)
	check(unit._unreach_targets.size() <= Unit.UNREACHABLE_CACHE_MAX,
		"cache stays bounded")
	check(unit._unreach_targets.size() >= Unit.UNREACHABLE_CACHE_MAX - 1,
		"cache is NOT cleared wholesale on overflow")
	var last: Unit = targets[targets.size() - 1]
	check(unit._unreach_targets.has(last.get_instance_id()),
		"the most recent target is remembered")
	_free_world(w)


## Phase 10j: a roll over the rim used to be reflected by the invisible wall. Now it
## tumbles over the edge and turns into a throw, which _tick_thrown converts into the
## fall — one code path for every way of leaving the disc.
##
## The loop collects a flag and asserts ONCE afterwards: a check() per iteration
## would make the suite's assertion count depend on how many ticks the roll lasts.
func test_rolling_unit_tumbles_over_the_rim() -> void:
	var w: Dictionary = _make_world()
	var rim: float = w.td.disc_center() + w.td.disc_radius()
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1,
		Vector2(rim - 1.0, w.td.disc_center()))
	victim.max_health = 100000
	victim.health = 100000
	victim.start_roll(Vector3(1, 0, 0), 3.0, 8.0)   # straight at the rim, with momentum
	var left_the_disc: bool = false
	for i in range(200):
		if victim.state == Unit.State.DEAD:
			left_the_disc = true
			break
		victim.tick(TICK)
		if not w.td.has_ground(victim.position.x, victim.position.z):
			left_the_disc = true
	check(left_the_disc, "the roll went over the rim instead of bouncing back")
	check(victim.state == Unit.State.DEAD or victim.state == Unit.State.THROWN,
		"and it is falling or already dead, not standing on nothing")
	_free_world(w)
# --- Weapon cooldown across target switches (user report 2026-09-02) ---------

## "Firewarriors feel like they switch to gatling mode in mass": they did.
## _begin_attack wiped _attack_cooldown, and since a retarget after a kill goes
## through it, every kill bought a free extra shot. With enough shooters the
## target always dies inside the 1.5 s cooldown, so the sustained rate measured
## 0.963 instead of 0.667 shots/s per head (1.44x). A retarget is not a reload.
func test_kill_retarget_keeps_the_weapon_cooldown() -> void:
	var w: Dictionary = _make_world()
	var fw: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(50, 50))
	var first: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(54, 50))
	# Tick until the first fireball is away (the cooldown is then full).
	var ticks: int = 0
	while fw._attack_cooldown <= 0.0 and ticks < 200:
		fw.tick(TICK)
		w.unit_manager.tick(TICK)
		ticks += 1
	check(fw._attack_cooldown > 0.0, "the firewarrior fired and is reloading")
	var cd_before: float = fw._attack_cooldown
	# The target dies; a fresh one stands right next to it.
	var second: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(54, 50.4))
	first.take_damage(10000)
	fw.tick(TICK)
	w.unit_manager.tick(TICK)
	check(fw.attack_target == second, "it retargets the survivor")
	check(fw._attack_cooldown >= cd_before - TICK * 3.0,
		"and carries its cooldown over (%.2f of %.2f left)"
			% [fw._attack_cooldown, cd_before])
	_free_world(w)


## The other half of the rule: a FRESH engagement still strikes without delay,
## so ordered attacks and idle units spotting an enemy stay responsive.
func test_fresh_engagement_still_strikes_at_once() -> void:
	var w: Dictionary = _make_world()
	var fw: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(50, 50))
	var foe: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(54, 50))
	fw._attack_cooldown = 99.0     # as if it had fired long ago (it freezes when idle)
	check(fw.state != Unit.State.ATTACK, "it is not in a fight yet")
	fw.order_attack(foe)
	check(fw._attack_cooldown == 0.0,
		"engaging out of IDLE clears the stale cooldown (no arbitrary wait)")
	_free_world(w)
## The air-death cry is ONE PER UNIT (user report 2026-09-02): further fireballs
## on the same falling body used to let it scream again, because play_sfx's
## throttle counts per SOUND NAME globally and neither call site was idempotent
## on its own — the doomed guard sits inside _enter_ragdoll, after the cry.
func test_air_death_cry_fires_once_per_unit() -> void:
	var w: Dictionary = _make_world()
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	victim.throw_airborne(Vector3(1, 0, 0) * 4.0 + Vector3.UP * 5.0)
	check(victim.state == Unit.State.THROWN, "the victim is in the air")
	check(not victim._air_death_cried, "nothing cried yet")
	victim.take_damage(10000)
	check(victim._air_death_cried, "the lethal hit in the air cries out")
	check(victim.state == Unit.State.THROWN and victim.doomed,
		"...and turns it into a falling ragdoll")
	# Follow-up hits land (the body is still a projectile target) but stay silent.
	victim.take_damage(10000)
	victim.take_damage(10000)
	check(not victim._cry_air_death(),
		"further hits on the same falling body never cry again")
	_free_world(w)
