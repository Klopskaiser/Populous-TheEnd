extends TestBase

## Headless tests for phase 7f: workshop production (worker-seconds, wood
## stock, pause, max cap, exit blockade, auto-manning), the siege engine's
## crew/ownership rules, bombardment (building stages, occupant kill,
## shockwave) and the roll hardening (rolls abort attacks, casts and
## conversions).

const TICK: float = 0.1
const MAX_TICKS: int = 3000

const WORKSHOP_SCENE: PackedScene = preload("res://scenes/buildings/workshop.tscn")
const WARRIOR_CAMP_SCENE: PackedScene = preload("res://scenes/buildings/warrior_camp.tscn")
const FORESTER_SCENE: PackedScene = preload("res://scenes/buildings/forester.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const SIEGE_SCENE: PackedScene = preload("res://scenes/units/siege_engine.tscn")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")


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
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe0, tribe1] as Array[Tribe], tm, wpm)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um, wpm)
	um.building_manager = bm
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(nav, bm, um, tm)
	return {
		"td": td, "nav": nav, "tribe": tribe0, "tribe1": tribe1,
		"unit_manager": um, "building_manager": bm,
		"tree_manager": tm, "wood_pile_manager": wpm, "commands": tc,
	}


func _free_world(w: Dictionary) -> void:
	w.commands.free()
	w.tree_manager.free()
	w.wood_pile_manager.free()
	w.building_manager.free()
	w.unit_manager.free()


func _tick_world(w: Dictionary) -> void:
	w.building_manager.tick(TICK)
	for u in w.unit_manager.units.duplicate():
		if is_instance_valid(u):
			u.tick(TICK)
	w.unit_manager.tick(TICK)


func _place_workshop(w: Dictionary, cell: Vector2i = Vector2i(60, 60)) -> Workshop:
	return w.building_manager.place(WORKSHOP_SCENE, w.tribe, cell, 0, true) as Workshop


func _siege_units(w: Dictionary, tribe_id: int = 0) -> Array:
	var found: Array = []
	for u in w.unit_manager.units:
		if is_instance_valid(u) and u is SiegeEngine and u.tribe_id == tribe_id \
				and u.state != Unit.State.DEAD:
			found.append(u)
	return found


## Spawns a brave and boards it onto the engine (ticking until it serves).
func _board_crew(w: Dictionary, engine: SiegeEngine, tribe_id: int = 0) -> Brave:
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, tribe_id, engine.position + Vector3(1.0, 0.0, 0.0)) as Brave
	brave.order_crew(engine)
	var ticks: int = 0
	while not brave.siege_boarded and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	return brave


# --- Workshop: production ---------------------------------------------------------

## Houses a worker in the workshop: order the slot, then tick until it walked
## in (forester pattern).
func _house_worker(w: Dictionary, ws: Workshop) -> Brave:
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, ws.entrance_world() + Vector3(1.0, 0.0, 1.0)) as Brave
	brave.order_workshop(ws)
	var ticks: int = 0
	while not brave.workshop_inside and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	return brave


## A non-siege enemy can never lock onto the vehicle itself — attacks go for the
## crew (spec: catapults are not directly attackable in melee/ranged).
func test_units_never_target_the_vehicle() -> void:
	var w: Dictionary = _make_world()
	var engine: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, Vector3(40, 0, 40)) as SiegeEngine
	_board_crew(w, engine, 0)
	var enemy: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 1, Vector3(41, 0, 40))
	# Direct order and auto-scan must both refuse the vehicle.
	enemy.order_attack(engine)
	check(enemy.attack_target != engine, "an enemy warrior cannot target the vehicle")
	enemy._begin_attack(engine)
	check(enemy.attack_target != engine, "_begin_attack rejects the non-targetable vehicle")
	_free_world(w)


## Several catapults sent to ONE point must settle spread apart, not shove each
## other around at the goal (their formation targets are scaled outside the
## vehicle separation bubble — same fix as the airships).
func test_multiple_catapults_to_one_point_settle_apart() -> void:
	var w: Dictionary = _make_world()
	var engines: Array[Unit] = []
	for i in range(3):
		var e: SiegeEngine = w.unit_manager.spawn_unit(
			SIEGE_SCENE, 0, w.nav.cell_to_world(Vector2i(56 + i * 2, 60))) as SiegeEngine
		_board_crew(w, e)   # 1 crew: enough to move
		engines.append(e)
	var target: Vector3 = w.nav.cell_to_world(Vector2i(74, 60))
	w.commands.order_move(engines, target)
	var ticks: int = 0
	while ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
		var moving: bool = false
		for e in engines:
			if e.state == Unit.State.MOVE:
				moving = true
		if not moving:
			break
	for e in engines:
		check(e.state != Unit.State.MOVE, "every catapult stops (does not shove forever)")
	# Pairwise gaps reach the separation bubble — no perpetual jostling/stacking.
	var sep: float = engines[0].vehicle_separation
	for i in range(engines.size()):
		for j in range(i + 1, engines.size()):
			var gap: float = Vector2(engines[i].position.x - engines[j].position.x,
				engines[i].position.z - engines[j].position.z).length()
			check(gap > sep * 0.8,
				"catapults settle apart, not stacked (gap=%.2f, sep=%.2f)" % [gap, sep])
	var flat_t: Vector2 = Vector2(target.x, target.z)
	for e in engines:
		check(Vector2(e.position.x, e.position.z).distance_to(flat_t) < 8.0,
			"each catapult ends up near the ordered point")
	_free_world(w)


## Catapult-vs-catapult (ranged) IS allowed: a catapult may aim at an enemy
## catapult (its shot's splash then hits the crew).
func test_catapult_may_target_enemy_catapult() -> void:
	var w: Dictionary = _make_world()
	var mine: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, Vector3(40, 0, 40)) as SiegeEngine
	var foe: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 1, Vector3(48, 0, 40)) as SiegeEngine
	check(mine._may_target_vehicle(foe), "a catapult may target another catapult")
	mine.order_attack(foe)
	check(mine.attack_target == foe, "catapult locks onto the enemy catapult")
	_free_world(w)


## An ORDERED catapult obeys the command: a target that sits within MIN_RANGE
## (too close to fire) is HELD, not swapped for another in-band enemy. Under the
## old code the min-range scan would re-aim at the band enemy on the next scan —
## the user bug report ("catapult has a target but shoots nearby units instead").
func test_ordered_catapult_holds_too_close_target() -> void:
	var w: Dictionary = _make_world()
	var engine: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, Vector3(40, 0, 40)) as SiegeEngine
	_board_crew(w, engine, 0)
	_board_crew(w, engine, 0)   # 2 crew: enough to fire
	# The ordered target sits inside MIN_RANGE (3 m); a second enemy stands in the
	# fire band (8 m) — the OLD code would swap onto it on the next scan tick.
	var close_enemy: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, Vector3(42, 0, 40))  # 2 m
	close_enemy.max_health = 100000
	close_enemy.health = 100000
	var band_enemy: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, Vector3(48, 0, 40))   # 8 m
	band_enemy.max_health = 100000
	band_enemy.health = 100000
	engine.order_attack(close_enemy)
	check(engine.attack_target == close_enemy, "starts on the ordered close target")
	check(engine._target_ordered, "the target is flagged as ordered")
	for i in range(40):
		_tick_world(w)
	check(engine.attack_target == close_enemy,
		"ordered catapult holds its too-close target instead of swapping to the band enemy")
	_free_world(w)


func test_workshop_produces_catapult() -> void:
	var w: Dictionary = _make_world()
	var ws: Workshop = _place_workshop(w)
	check(ws != null and ws.is_usable(), "pre-built workshop is usable")
	check(ws.footprint == Vector2i(7, 4), "workshop has the big 7x4 footprint")
	check(ws.wood_cost == 13, "workshop costs 13 wood")
	w.wood_pile_manager.deposit(ws.delivery_point(), 20)

	var brave: Brave = _house_worker(w, ws)
	check(ws.occupants.size() == 1, "the brave holds a worker slot")
	check(brave.workshop_inside, "the worker is housed INSIDE the workshop")
	check(not (brave in w.unit_manager.units),
		"a housed worker is out of the live world (forester pattern)")

	var stock_before: int = ws.stock_wood()
	ws._tick_active(1.0)   # start tick: consumes the wood
	check(ws.production_active, "production starts with a housed worker and wood")
	check(stock_before - ws.stock_wood() == Workshop.CATAPULT_WOOD,
		"starting consumed exactly %d wood from the piles" % Workshop.CATAPULT_WOOD)
	# 90 worker-seconds with 1 housed worker.
	for i in range(90):
		ws._tick_active(1.0)
	check(not ws.production_active, "the catapult is finished after 90 worker-seconds")
	check(_siege_units(w).size() == 1, "one siege engine rolled out")
	check(is_instance_valid(brave) and ws.occupants.size() == 1,
		"the worker was NOT consumed (unlike training)")
	_free_world(w)


func test_workshop_worker_pipeline_builds_catapult() -> void:
	# Integration: real braves walk in (stock pre-piled, nothing to fetch) and
	# the housed trio contributes 90 worker-seconds -> ~30 s.
	var w: Dictionary = _make_world()
	var ws: Workshop = _place_workshop(w)
	w.wood_pile_manager.deposit(ws.delivery_point(), 20)
	for i in range(3):
		var b: Brave = w.unit_manager.spawn_unit(BRAVE_SCENE, 0,
			ws.entrance_world() + Vector3(float(i), 0.0, 1.0)) as Brave
		b.order_workshop(ws)
	check(ws.occupants.size() == 3, "three braves hold the worker slots")
	var extra: Brave = w.unit_manager.spawn_unit(BRAVE_SCENE, 0,
		ws.entrance_world() + Vector3(3.0, 0.0, 1.0)) as Brave
	extra.order_workshop(ws)
	check(ws.occupants.size() == 3, "a fourth worker is rejected (max 3 slots)")
	check(extra.state == Unit.State.IDLE, "the rejected brave stays idle")

	var ticks: int = 0
	while _siege_units(w).is_empty() and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(not _siege_units(w).is_empty(),
		"the housed workers built a catapult (took %d ticks)" % ticks)
	check(float(ticks) * TICK < 60.0,
		"3 workers finish in well under 60 s (~30 s expected, took %.1f s)" % (float(ticks) * TICK))
	_free_world(w)


## A brave recruited into a job mid-walk must drop its pending move waypoint,
## so a finished/idle worker shows no phantom route marker (user bug report).
func test_worker_order_clears_stale_move_waypoint() -> void:
	var w: Dictionary = _make_world()
	var ws: Workshop = _place_workshop(w)
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, ws.entrance_world() + Vector3(2.0, 0.0, 2.0)) as Brave
	brave.order_move(w.nav.cell_to_world(Vector2i(90, 90)))
	check(not brave.waypoint_queue.is_empty(), "the move order queued a destination")
	# Being put to work cancels the pending move (no lingering route marker).
	brave.order_workshop(ws)
	check(brave.waypoint_queue.is_empty(),
		"starting work clears the stale move waypoint")
	# Ejecting it back out leaves it idle WITHOUT a phantom destination.
	ws.eject_worker(0)
	check(brave.state == Unit.State.IDLE and brave.waypoint_queue.is_empty(),
		"a released worker is idle with no stale waypoint")
	_free_world(w)


func test_construction_workers_are_not_auto_hired() -> void:
	# The bug from the user report: braves that BUILT the workshop must not
	# slide into production duty — slots are taken by explicit order only.
	var w: Dictionary = _make_world()
	var ws: Workshop = _place_workshop(w)
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, ws.entrance_world()) as Brave
	# Simulate the post-construction state: job still points at the (now
	# finished) workshop, but no slot was ever reserved.
	brave.job = ws
	brave._set_state(Unit.State.BUILD)
	brave.tick(TICK)
	check(brave.state == Unit.State.IDLE and brave.job == null,
		"a construction worker is released, not hired into the workshop")
	check(ws.occupants.is_empty(), "no slot was taken without an order")
	_free_world(w)


func test_workshop_stalls_without_wood_and_resumes() -> void:
	var w: Dictionary = _make_world()
	var ws: Workshop = _place_workshop(w)
	check(not ws.can_start_production(), "no wood -> production cannot start")
	w.wood_pile_manager.deposit(ws.delivery_point(), Workshop.CATAPULT_WOOD)
	check(ws.can_start_production(), "production can start once wood arrived")
	_free_world(w)


func test_workshop_pause_and_max_cap() -> void:
	var w: Dictionary = _make_world()
	var ws: Workshop = _place_workshop(w)
	w.wood_pile_manager.deposit(ws.delivery_point(), 20)
	ws.paused = true
	check(not ws.can_start_production(), "paused workshop starts nothing")
	ws.paused = false

	# Per-tribe cap: EVERY own catapult counts, manned or not.
	var engine: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, w.nav.cell_to_world(Vector2i(80, 80))) as SiegeEngine
	check(w.tribe.owned_catapult_count() == 1, "an UNMANNED own catapult counts")
	_board_crew(w, engine)
	check(w.tribe.owned_catapult_count() == 1, "boarding does not change the count")
	w.tribe.max_catapults = 1
	check(not ws.can_start_production(), "cap reached -> production auto-stops")
	w.tribe.max_catapults = 2
	check(ws.can_start_production(), "raising the cap resumes production")
	# An enemy-owned engine never counts toward this tribe's cap.
	w.unit_manager.spawn_unit(SIEGE_SCENE, 1, w.nav.cell_to_world(Vector2i(90, 90)))
	check(w.tribe.owned_catapult_count() == 1, "enemy catapults do not count")
	_free_world(w)


func test_workshop_exit_blockade_and_abort() -> void:
	var w: Dictionary = _make_world()
	var ws: Workshop = _place_workshop(w)
	w.wood_pile_manager.deposit(ws.delivery_point(), 25)
	var brave: Brave = _house_worker(w, ws)
	check(brave.workshop_inside, "worker housed")
	for i in range(91):
		ws._tick_active(1.0)
	var engines: Array = _siege_units(w)
	check(engines.size() == 1, "catapult finished")
	check(ws.exit_blocked(), "the fresh catapult blocks the entrance")
	check(not ws.can_start_production(), "no next production while blocked")
	engines[0].position += Vector3(10.0, 0.0, 10.0)
	check(not ws.exit_blocked(), "moving the catapult off clears the exit")
	check(ws.can_start_production(), "production may start again")

	# Abort: production running, the last slot is emptied -> progress AND
	# wood lost.
	ws._tick_active(1.0)
	check(ws.production_active, "second catapult started")
	var stock_after_start: int = ws.stock_wood()
	ws.eject_worker(0)
	check(ws.occupants.is_empty(), "the worker was ejected")
	check(is_instance_valid(brave) and brave.state == Unit.State.IDLE,
		"the ejected worker is back in the world and idle")
	ws._tick_active(TICK)
	check(not ws.production_active, "all slots empty -> production aborted")
	check(ws.stock_wood() == stock_after_start,
		"the consumed wood is NOT refunded on abort")
	_free_world(w)


func test_workshop_disabled_aborts_and_releases() -> void:
	var w: Dictionary = _make_world()
	var ws: Workshop = _place_workshop(w)
	w.wood_pile_manager.deposit(ws.delivery_point(), 20)
	var brave: Brave = _house_worker(w, ws)
	ws._tick_active(1.0)
	check(ws.production_active, "production running")
	ws.take_damage(int(float(ws.max_health) * 0.4))   # stage >= 1: unusable
	check(not ws.is_usable(), "damaged workshop is unusable")
	check(not ws.production_active, "damage aborted the production (no refund)")
	check(ws.occupants.is_empty(), "the workers were released (forester rule)")
	check(is_instance_valid(brave) and brave in w.unit_manager.units,
		"the housed worker stepped back into the world")
	_free_world(w)


func test_workshop_dispatches_fetchers_for_stock() -> void:
	# Low stock + reachable trees: the housed worker steps OUT, fetches wood
	# to the entrance and is housed again once the stock target is reached.
	var w: Dictionary = _make_world()
	var ws: Workshop = _place_workshop(w)
	for i in range(8):
		w.tree_manager.spawn_tree(Vector2i(55 + (i % 4), 68 + (i / 4) * 2),
			TreeResource.MAX_STAGE)
	var brave: Brave = _house_worker(w, ws)
	check(brave.workshop_inside, "worker housed before the stock check")
	var ticks: int = 0
	while ws.stock_wood() < Workshop.CATAPULT_WOOD and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(ws.stock_wood() >= Workshop.CATAPULT_WOOD,
		"the dispatched worker piled wood at the entrance (took %d ticks)" % ticks)
	_free_world(w)


func test_workshop_auto_mans_fresh_catapult() -> void:
	var w: Dictionary = _make_world()
	var ws: Workshop = _place_workshop(w)
	w.wood_pile_manager.deposit(ws.delivery_point(), 20)
	var worker: Brave = _house_worker(w, ws)
	check(worker.workshop_inside, "producer housed")
	# Two IDLE braves near the entrance (auto-crew candidates).
	var idle1: Brave = w.unit_manager.spawn_unit(BRAVE_SCENE, 0,
		ws.entrance_world() + Vector3(2.0, 0.0, 2.0)) as Brave
	var idle2: Brave = w.unit_manager.spawn_unit(BRAVE_SCENE, 0,
		ws.entrance_world() + Vector3(-2.0, 0.0, 2.0)) as Brave
	for i in range(91):
		ws._tick_active(1.0)
	var engines: Array = _siege_units(w)
	check(engines.size() == 1, "catapult finished")
	if engines.size() == 1:
		var engine: SiegeEngine = engines[0]
		check(idle1.siege_engine == engine and idle2.siege_engine == engine,
			"both idle braves were assigned as crew automatically")
		var ticks: int = 0
		while engine.boarded_count() < 2 and ticks < MAX_TICKS:
			_tick_world(w)
			ticks += 1
		check(engine.boarded_count() == 2, "the auto-crew boarded the catapult")
	_free_world(w)


# --- Siege engine: crew, ownership, protection -------------------------------------

func test_crew_movement_and_fire_gates() -> void:
	var w: Dictionary = _make_world()
	var engine: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, w.nav.cell_to_world(Vector2i(60, 60))) as SiegeEngine
	# Unmanned: move orders are refused.
	engine.order_move(w.nav.cell_to_world(Vector2i(70, 60)))
	check(engine.state == Unit.State.IDLE, "an unmanned catapult refuses move orders")

	var crew1: Brave = _board_crew(w, engine)
	check(engine.boarded_count() == 1, "one crew member serves")
	engine.order_move(w.nav.cell_to_world(Vector2i(70, 60)))
	check(engine.state == Unit.State.MOVE, "1 crew is enough to move")
	check_near(engine.speed, 2.0, "the catapult moves at half brave speed (0.5x)")
	check(is_inf(SiegeEngine.fire_cooldown_for_crew(1)), "1 crew cannot fire")
	check_near(SiegeEngine.fire_cooldown_for_crew(2), 6.0, "2 crew fire slowly")
	check_near(SiegeEngine.fire_cooldown_for_crew(6), 3.0, "full crew fires fastest")
	check(SiegeEngine.fire_cooldown_for_crew(4) < 6.0, "more crew -> faster")

	# Crew death unmans the vehicle.
	crew1.take_damage(9999)
	engine._prune_crew()
	check(engine.boarded_count() == 0, "dead crew no longer serves")
	_free_world(w)


func test_unmanned_catapult_takeover_switches_owner() -> void:
	var w: Dictionary = _make_world()
	var engine: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, w.nav.cell_to_world(Vector2i(60, 60))) as SiegeEngine
	check(engine.tribe_id == 0, "the catapult starts owned by tribe 0")
	var enemy_crew: Brave = _board_crew(w, engine, 1)
	check(engine.tribe_id == 1, "boarding an UNMANNED catapult takes it over")
	check(enemy_crew.siege_boarded, "the new crew serves it")
	# A manned engine refuses foreign recruits.
	var raider: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, engine.position + Vector3(1.5, 0.0, 0.0)) as Brave
	raider.order_crew(engine)
	check(raider.siege_engine == null, "a manned enemy catapult cannot be hijacked")
	_free_world(w)


func test_catapult_not_directly_attackable() -> void:
	var w: Dictionary = _make_world()
	var engine: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 1, w.nav.cell_to_world(Vector2i(60, 60))) as SiegeEngine
	var warrior: Warrior = w.unit_manager.spawn_unit(
		WARRIOR_SCENE, 0, w.nav.cell_to_world(Vector2i(62, 60))) as Warrior
	check(warrior._scan_for_enemy(10.0) == null,
		"enemy scans skip the (untargetable) catapult")
	w.commands.order_attack([warrior] as Array[Unit], engine)
	check(warrior.attack_target == null, "order_attack on a catapult is rejected")
	engine.take_damage(9999)
	check(engine.state != Unit.State.DEAD, "the device shrugs off direct damage")
	# But the CREW is a normal target.
	var crew: Brave = _board_crew(w, engine, 1)
	check(warrior._scan_for_enemy(10.0) == crew, "attackers go for the crew instead")
	_free_world(w)


func test_shaman_cannot_crew() -> void:
	var w: Dictionary = _make_world()
	var engine: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, w.nav.cell_to_world(Vector2i(60, 60))) as SiegeEngine
	var shaman: Shaman = Shaman.new()
	shaman.order_crew(engine)
	check(shaman.siege_engine == null and shaman.state == Unit.State.IDLE,
		"the shaman never mans a catapult")
	shaman.free()
	_free_world(w)


# --- Siege engine: bombardment ------------------------------------------------------

func test_bombard_building_stage_and_occupant_kill() -> void:
	var w: Dictionary = _make_world()
	# Enemy warrior camp with a trainee locked inside.
	var camp: WarriorCamp = w.building_manager.place(
		WARRIOR_CAMP_SCENE, w.tribe1, Vector2i(70, 60), 0, true) as WarriorCamp
	var trainee: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, camp.entrance_world()) as Brave
	w.unit_manager.remove_from_world(trainee)
	camp.trainee = trainee
	var own_hut: Hut = w.building_manager.place(
		HUT_SCENE, w.tribe, Vector2i(70, 66), 0, true) as Hut

	var health_before: int = camp.health
	var shot: SiegeShot = SiegeShot.new()
	shot.setup(0, w.nav.cell_to_world(Vector2i(60, 60)), camp.center_world(),
		null, w.unit_manager, w.td, w.building_manager)
	while not shot.done:
		shot.tick(TICK)
	check(camp.health < health_before, "the hit building took damage")
	check(camp.destruction_stage() >= 1, "one full destruction stage was applied")
	check(camp.trainee == null, "the training slot is empty after the strike")
	check(is_instance_valid(trainee) and trainee.state == Unit.State.ROLL,
		"the stationed trainee tumbles VISIBLY out of the building")
	var roll_ticks: int = 0
	while trainee.state == Unit.State.ROLL and roll_ticks < 100:
		trainee.tick(TICK)
		roll_ticks += 1
	check(trainee.state == Unit.State.DEAD,
		"the trainee dies once the tumble ends (deferred roll death)")
	check(trainee in w.unit_manager.units, "the trainee's corpse lies in the world")
	check(own_hut.health == own_hut.max_health, "own buildings are never damaged")
	shot.free()

	# Impact on an OWN building's plot: no damage, even from own shots.
	var shot2: SiegeShot = SiegeShot.new()
	shot2.setup(0, w.nav.cell_to_world(Vector2i(60, 66)), own_hut.center_world(),
		null, w.unit_manager, w.td, w.building_manager)
	while not shot2.done:
		shot2.tick(TICK)
	check(own_hut.health == own_hut.max_health, "friendly fire never wrecks own buildings")
	shot2.free()
	_free_world(w)


## Regression: a catapult hit on an enemy STAFFED forester silently deleted the
## housed workers — nothing ever became visible outside the building. Ranged
## rule now: they die at the door as corpses lying in the world.
func test_bombard_forester_kills_workers_visibly() -> void:
	var w: Dictionary = _make_world()
	var forester: Forester = w.building_manager.place(
		FORESTER_SCENE, w.tribe1, Vector2i(70, 60), 0, true) as Forester
	var workers: Array[Brave] = []
	for i in range(2):
		var b: Brave = w.unit_manager.spawn_unit(BRAVE_SCENE, 1,
			forester.entrance_world() + Vector3(float(i), 0.0, 1.0)) as Brave
		b.order_forester(forester)
		workers.append(b)
	var ticks: int = 0
	while ticks < MAX_TICKS \
			and workers.any(func(b: Brave) -> bool: return not b.forester_inside):
		_tick_world(w)
		ticks += 1
	check(forester.occupants.size() == 2, "two enemy workers are housed inside")

	var shot: SiegeShot = SiegeShot.new()
	shot.setup(0, w.nav.cell_to_world(Vector2i(60, 60)), forester.center_world(),
		null, w.unit_manager, w.td, w.building_manager)
	while not shot.done:
		shot.tick(TICK)
	check(forester.destruction_stage() >= 1, "the forester took a destruction stage")
	for b in workers:
		check(is_instance_valid(b) and b.state == Unit.State.ROLL,
			"a housed worker tumbles visibly out of the building")
	var roll_ticks: int = 0
	while roll_ticks < 100 \
			and workers.any(func(b: Brave) -> bool: return b.state == Unit.State.ROLL):
		_tick_world(w)
		roll_ticks += 1
	for b in workers:
		check(is_instance_valid(b) and b.state == Unit.State.DEAD,
			"a housed worker dies once the tumble ends (deferred roll death)")
		check(b in w.unit_manager.units, "the worker's corpse lies in the world")
	check(forester.occupants.is_empty(), "no worker slot stays occupied")
	shot.free()
	_free_world(w)


## A building hit still spills the lava puddle (units at the impact burn), but
## that puddle never wrecks buildings on top of the shot's own stage damage.
func test_building_hit_spills_nonwrecking_lava() -> void:
	var w: Dictionary = _make_world()
	var camp: WarriorCamp = w.building_manager.place(
		WARRIOR_CAMP_SCENE, w.tribe1, Vector2i(70, 60), 0, true) as WarriorCamp
	var shot: SiegeShot = SiegeShot.new()
	shot.setup(0, w.nav.cell_to_world(Vector2i(60, 60)), camp.center_world(),
		null, w.unit_manager, w.td, w.building_manager)
	while not shot.done:
		shot.tick(TICK)
	var surges: Array = w.unit_manager.projectiles.filter(func(p): return p is LavaSurge)
	check(surges.size() == 1, "a building hit STILL spills a lava puddle")
	if surges.size() == 1:
		check(not surges[0].damage_buildings,
			"the puddle does not wreck buildings (the shot already did that)")
	shot.free()
	_free_world(w)


func test_open_ground_lava_puddle_keeps_wrecking_on() -> void:
	var w: Dictionary = _make_world()
	var impact: Vector3 = w.nav.cell_to_world(Vector2i(60, 60))
	var shot: SiegeShot = SiegeShot.new()
	shot.setup(0, impact + Vector3(-10.0, 0.0, 0.0), impact,
		null, w.unit_manager, w.td, w.building_manager)
	while not shot.done:
		shot.tick(TICK)
	var surges: Array = w.unit_manager.projectiles.filter(func(p): return p is LavaSurge)
	check(surges.size() == 1 and surges[0].damage_buildings,
		"an open-ground puddle keeps the sustained-contact wrecking rule on")
	shot.free()
	_free_world(w)


## Anti-raider bombardment: a hit on the OWN building with enemy raiders inside
## blasts them back out hurt (alive, back in the world) and the own building
## pays one destruction stage.
func test_bombard_own_raided_building() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.building_manager.place(
		HUT_SCENE, w.tribe, Vector2i(70, 60), 0, true) as Hut
	var raider: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 1, hut.entrance_world())
	check(hut.admit_raider(raider), "the enemy warrior slips inside to demolish")
	check(hut.has_raiders(), "raiders registered inside")
	var health_before: int = raider.health

	var shot: SiegeShot = SiegeShot.new()
	shot.setup(0, w.nav.cell_to_world(Vector2i(60, 60)), hut.center_world(),
		null, w.unit_manager, w.td, w.building_manager)
	while not shot.done:
		shot.tick(TICK)
	check(hut.destruction_stage() >= 1,
		"the own building pays a stage for the anti-raider shot")
	check(not hut.has_raiders(), "the raiders were blasted back out")
	check(raider.state != Unit.State.DEAD, "the raider survives the hit")
	check(raider.raiding_building == null and raider.health < health_before,
		"...hurt and back in the world")
	shot.free()
	_free_world(w)


## The order path: an own building is only a valid bombardment target while
## raiders demolish it — and only for siege engines, never for foot units.
func test_order_attack_own_building_only_with_raiders() -> void:
	var w: Dictionary = _make_world()
	var engine: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, Vector3(40, 0, 40)) as SiegeEngine
	var hut: Hut = w.building_manager.place(
		HUT_SCENE, w.tribe, Vector2i(50, 50), 0, true) as Hut
	engine.order_attack_building(hut)
	check(engine.attack_building == null, "own building without raiders is refused")

	var raider: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 1, hut.entrance_world())
	check(hut.admit_raider(raider), "raider slips inside")
	engine.order_attack_building(hut)
	check(engine.attack_building == hut, "own building WITH raiders is a valid order")
	check(engine._building_target_valid(), "focus valid while the raiders demolish")
	hut.blast_raiders(0, null)   # raiders leave: the anti-raider focus dies too
	check(not engine._building_target_valid(), "focus dropped once the raiders are gone")

	# TribeCommands routes the own-building order to engines only.
	check(hut.admit_raider(raider), "the ejected raider re-enters")
	var warrior: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, Vector3(45, 0, 45))
	engine.attack_building = null
	w.commands.order_attack_building([warrior, engine] as Array[Unit], hut)
	check(warrior.attack_building != hut, "foot units never storm the own building")
	check(engine.attack_building == hut, "TribeCommands routes the order to the engine")
	_free_world(w)


func test_bombard_construction_site_shatters() -> void:
	var w: Dictionary = _make_world()
	var site: Hut = w.building_manager.place(
		HUT_SCENE, w.tribe1, Vector2i(70, 60), 0, false) as Hut
	check(site.under_construction, "the site is under construction")
	var shot: SiegeShot = SiegeShot.new()
	shot.setup(0, w.nav.cell_to_world(Vector2i(60, 60)), site.center_world(),
		null, w.unit_manager, w.td, w.building_manager)
	while not shot.done:
		shot.tick(TICK)
	check(site.health <= 0, "a construction site shatters outright (fragile rule)")
	shot.free()
	_free_world(w)


func test_shockwave_damages_all_units() -> void:
	var w: Dictionary = _make_world()
	var impact: Vector3 = w.nav.cell_to_world(Vector2i(60, 60))
	var foe: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, impact + Vector3(1.0, 0.0, 0.0)) as Brave
	var friend: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, impact + Vector3(-1.0, 0.0, 0.0)) as Brave
	var far: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, impact + Vector3(8.0, 0.0, 0.0)) as Brave
	var shot: SiegeShot = SiegeShot.new()
	shot.setup(0, impact + Vector3(-10.0, 0.0, 0.0), impact,
		null, w.unit_manager, w.td, w.building_manager)
	while not shot.done:
		shot.tick(TICK)
	check(foe.health == foe.max_health - SiegeShot.SHOCK_DAMAGE,
		"enemies in the 2-m radius take 1/4 brave life")
	check(friend.health == friend.max_health - SiegeShot.SHOCK_DAMAGE,
		"friendly fire: own units in the radius are hit too")
	check(far.health == far.max_health, "units outside the radius are untouched")
	check(w.unit_manager.projectiles.size() == 1,
		"a small lava puddle was spilled at the impact")
	shot.free()
	_free_world(w)


func test_roll_chance_by_slope() -> void:
	check_near(SiegeShot.roll_chance_for_slope(0.0), 0.4, "flat ground: 40%")
	check_near(SiegeShot.roll_chance_for_slope(0.3), 0.8, "mild slope: 80%")
	check_near(SiegeShot.roll_chance_for_slope(1.0), 1.0, "steep slope: always")
	check(SiegeShot.MIN_ROLL_DURATION >= 1.0, "shockwave rolls last at least 1 s")


## Teleports the engine AND its crew (a lone teleport would leash-prune the
## crew left behind).
func _teleport_engine(engine: SiegeEngine, pos: Vector3) -> void:
	engine.position = pos
	for m in engine.crew:
		if is_instance_valid(m):
			m.position = pos + Vector3(1.0, 0.0, 0.0)


func test_engine_range_band_and_priorities() -> void:
	var w: Dictionary = _make_world()
	var engine: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, w.nav.cell_to_world(Vector2i(50, 60))) as SiegeEngine
	_board_crew(w, engine)
	_board_crew(w, engine)
	check(engine.boarded_count() >= 2, "two crew serve (can fire)")

	# Enemy building ~20 m away: beyond range -> the engine advances.
	var camp: WarriorCamp = w.building_manager.place(
		WARRIOR_CAMP_SCENE, w.tribe1, Vector2i(70, 60), 0, true) as WarriorCamp
	engine.order_attack_building(camp)
	check(engine.state == Unit.State.ATTACK, "bombard order accepted")
	_tick_world(w)
	check(engine._has_path() or engine._pending_target != Vector3.INF
		or w.unit_manager.projectiles.size() > 0,
		"beyond 15 m the engine closes in")
	# Teleport into the band: it fires.
	_teleport_engine(engine, w.nav.cell_to_world(Vector2i(64, 60)))   # ~8.5 m
	engine._fire_cooldown = 0.0
	var ticks: int = 0
	while w.unit_manager.projectiles.filter(func(p): return p is SiegeShot).is_empty() \
			and ticks < 100:
		_tick_world(w)
		ticks += 1
	check(not w.unit_manager.projectiles.filter(func(p): return p is SiegeShot).is_empty(),
		"inside the band the engine launches shots")

	# Below minimum range: holds fire.
	for p in w.unit_manager.projectiles.duplicate():
		p.done = true
	_tick_world(w)   # flush finished projectiles
	_teleport_engine(engine, camp.center_world() + Vector3(2.0, 0.0, 0.0))
	engine._fire_cooldown = 0.0
	for i in range(30):
		_tick_world(w)
	check(w.unit_manager.projectiles.filter(func(p): return p is SiegeShot).is_empty(),
		"below the 3-m minimum range the engine holds fire")

	# Auto-priority: UNITS before buildings (user feedback) — with the camp
	# AND an enemy brave in range, the brave is engaged first.
	engine.attack_building = null
	engine._end_attack()
	engine._set_state(Unit.State.IDLE)
	_teleport_engine(engine, w.nav.cell_to_world(Vector2i(64, 60)))
	var foe: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, engine.position + Vector3(5.0, 0.0, 0.0)) as Brave
	engine._target_search_timer = 0.0
	var scan_ticks: int = 0
	while engine.state != Unit.State.ATTACK and scan_ticks < 50:
		_tick_world(w)
		scan_ticks += 1
	check(engine.attack_target == foe,
		"auto-aggro picks the enemy UNIT before the building in range")
	check(engine.attack_building == null, "no building focus while units are around")

	# Explicit unit order clears a building focus (order reliability fix).
	engine.attack_building = camp
	engine.order_attack(foe)
	check(engine.attack_target == foe and engine.attack_building == null,
		"an attack order on a unit overrides the building focus")

	# Sieging resumes on buildings once no unit is in range.
	foe.take_damage(9999)
	engine._end_attack()
	engine._set_state(Unit.State.IDLE)
	engine._target_search_timer = 0.0
	scan_ticks = 0
	while engine.attack_building == null and scan_ticks < 50:
		_tick_world(w)
		scan_ticks += 1
	check(engine.attack_building == camp,
		"without units in range the building is engaged as fallback")

	# order_attack_building now also storms ordinary units into the building
	# (phase 7g melee assault — braves storm on this explicit order).
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(52, 60))) as Brave
	w.commands.order_attack_building([brave] as Array[Unit], camp)
	check(brave.state == Unit.State.ATTACK and brave.attack_building == camp,
		"order_attack_building sends ordinary units to storm the building (7g)")
	_free_world(w)


## The catapult must never AUTO-chase a unit (it is the slowest unit — it
## would trundle after a fleeing target forever without firing, the reported
## "drives in but never shoots" bug). Out-of-band units are ignored; a
## building within aggro is approached instead.
func test_engine_does_not_auto_chase_units() -> void:
	var w: Dictionary = _make_world()
	var engine: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, w.nav.cell_to_world(Vector2i(50, 60))) as SiegeEngine
	_board_crew(w, engine)
	_board_crew(w, engine)
	# Enemy unit 18 m away — beyond the 15 m fire range, no building around.
	var foe: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, w.nav.cell_to_world(Vector2i(68, 60))) as Brave
	engine._target_search_timer = 0.0
	for i in range(20):
		_tick_world(w)
	check(engine.state == Unit.State.IDLE,
		"an out-of-band enemy unit is NOT auto-chased")
	check(engine.attack_target == null, "no unit target was locked")
	check(is_instance_valid(foe), "the far unit is left alone")

	# A building within aggro IS approached (stationary → catchable).
	var camp: WarriorCamp = w.building_manager.place(
		WARRIOR_CAMP_SCENE, w.tribe1, Vector2i(62, 58), 0, true) as WarriorCamp
	engine._target_search_timer = 0.0
	var t: int = 0
	while engine.attack_building == null and t < 50:
		_tick_world(w)
		t += 1
	check(engine.attack_building == camp,
		"a building within aggro is approached instead of the far unit")
	_free_world(w)


## An EXPLICIT attack order on a unit is honoured even out of the band: the
## catapult closes in and fires (the only case it chases a unit).
func test_engine_chases_ordered_unit() -> void:
	var w: Dictionary = _make_world()
	var engine: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, w.nav.cell_to_world(Vector2i(50, 60))) as SiegeEngine
	_board_crew(w, engine)
	_board_crew(w, engine)
	var foe: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, w.nav.cell_to_world(Vector2i(68, 60))) as Brave
	engine.order_attack(foe)
	check(engine.attack_target == foe and engine._target_ordered,
		"the ordered unit target is marked for chasing")
	var t: int = 0
	while w.unit_manager.projectiles.filter(func(p): return p is SiegeShot).is_empty() \
			and t < 300:
		_tick_world(w)
		t += 1
	check(not w.unit_manager.projectiles.filter(func(p): return p is SiegeShot).is_empty(),
		"the ordered unit is chased into range and fired on (took %d ticks)" % t)
	_free_world(w)


# --- Range display (G toggle) ------------------------------------------------------

func test_range_renderer_ranges() -> void:
	check_near(RangeRenderer.range_for_kind(&"firewarrior"), Firewarrior.FIRE_RANGE,
		"firewarrior ring = its fire range")
	check_near(RangeRenderer.range_for_kind(&"preacher"), Preacher.CONVERT_RANGE,
		"preacher ring = its convert range")
	check_near(RangeRenderer.range_for_kind(&"siege"), SiegeEngine.FIRE_RANGE,
		"catapult ring = its fire range")
	check(RangeRenderer.range_for_kind(&"brave") == 0.0, "braves have no range ring")
	check(RangeRenderer.range_for_kind(&"warrior") == 0.0, "warriors have no range ring")
	check(RangeRenderer.range_for_kind(&"shaman") == 0.0, "the shaman has no range ring")


## The range rings hug the terrain (one band surface per ring); a zero radius
## draws nothing.
func test_terrain_ring_builds_surface() -> void:
	var td: TerrainData = _flat_terrain()
	var im: ImmediateMesh = ImmediateMesh.new()
	TerrainRing.add_band(im, Vector3(60.0, 5.0, 60.0), 8.0, td, Color(1, 0, 0, 1))
	check(im.get_surface_count() == 1, "a ring band adds one terrain-conforming surface")
	im.clear_surfaces()
	TerrainRing.add_band(im, Vector3(60.0, 5.0, 60.0), 0.0, td, Color(1, 0, 0, 1))
	check(im.get_surface_count() == 0, "a zero-radius ring draws nothing")


# --- Attack-move resumes after combat (all units) ----------------------------------

## Deterministic (no combat RNG): attack-move, engage a target, the target
## dies → the unit must resume the march to its destination, not idle at the
## corpse. This is a general Unit behaviour (all units), verified via the
## warrior; combat outcome itself is left out to keep the test stable.
func test_attack_move_resumes_after_combat() -> void:
	var w: Dictionary = _make_world()
	var warrior: Warrior = w.unit_manager.spawn_unit(
		WARRIOR_SCENE, 0, w.nav.cell_to_world(Vector2i(50, 60))) as Warrior
	var foe: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, w.nav.cell_to_world(Vector2i(56, 60))) as Brave
	var dest: Vector3 = w.nav.cell_to_world(Vector2i(80, 60))
	warrior.order_move(dest, false, true)   # attack-move
	check(warrior.waypoint_queue.size() == 1, "the destination is queued")
	warrior._begin_attack(foe)              # engage an enemy on the way
	check(warrior.state == Unit.State.ATTACK, "the unit stops to fight")
	check(warrior.waypoint_queue.size() == 1, "the move destination is kept during combat")
	# The target dies; simulate the death notification the killer receives.
	foe.take_damage(9999)
	warrior._on_target_died(foe)
	check(warrior.state == Unit.State.MOVE,
		"the unit resumes marching once the fight is over")
	var d0: float = Vector2(warrior.position.x - dest.x, warrior.position.z - dest.z).length()
	for i in range(40):
		_tick_world(w)
	var d1: float = Vector2(warrior.position.x - dest.x, warrior.position.z - dest.z).length()
	check(d1 < d0 - 1.0,
		"it carries on toward the attack-move destination after combat")
	_free_world(w)


# --- Crew walks with the vehicle (no teleport) --------------------------------------

func test_crew_walks_with_engine() -> void:
	var w: Dictionary = _make_world()
	var engine: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, w.nav.cell_to_world(Vector2i(60, 60))) as SiegeEngine
	var crew: Brave = _board_crew(w, engine)
	# Settle at the slot: standing, not walking.
	for i in range(40):
		_tick_world(w)
	check(not crew._crew_walking, "a settled crew member stands (idle), not walking")

	# The engine moves: the crew follows on foot in bounded steps (no teleport).
	engine.order_move(w.nav.cell_to_world(Vector2i(72, 60)))
	for i in range(3):
		_tick_world(w)   # let the queued path resolve and the motion start
	var prev: Vector3 = crew.position
	_tick_world(w)
	var step: float = Vector2(crew.position.x - prev.x, crew.position.z - prev.z).length()
	check(crew._crew_walking, "the crew walks while the engine moves")
	check(step <= engine.speed * 2.0 * TICK + 0.06,
		"the crew steps at (about) the engine's speed — it does not teleport")
	# It keeps formation near its slot.
	var slot: Vector3 = engine.crew_slot_position(crew)
	check(Vector2(crew.position.x - slot.x, crew.position.z - slot.z).length() < 2.0,
		"the crew holds its side slot in lockstep")
	_free_world(w)


# --- Workshop dispatches the crewed catapult off the entrance -----------------------

func test_workshop_dispatches_crewed_catapult() -> void:
	var w: Dictionary = _make_world()
	var ws: Workshop = _place_workshop(w)
	w.wood_pile_manager.deposit(ws.delivery_point(), 20)
	var worker: Brave = _house_worker(w, ws)
	check(worker.workshop_inside, "producer housed")
	# Idle braves near the entrance auto-man the fresh catapult.
	w.unit_manager.spawn_unit(BRAVE_SCENE, 0, ws.entrance_world() + Vector3(2.0, 0.0, 2.0))
	w.unit_manager.spawn_unit(BRAVE_SCENE, 0, ws.entrance_world() + Vector3(-2.0, 0.0, 2.0))
	for i in range(91):
		ws._tick_active(1.0)
	var engines: Array = _siege_units(w)
	check(engines.size() == 1, "catapult finished")
	if engines.size() == 1:
		var engine: SiegeEngine = engines[0]
		# Once a crew has boarded, the catapult drives off the entrance pad.
		var t: int = 0
		while ws.exit_blocked() and t < MAX_TICKS:
			_tick_world(w)
			t += 1
		check(not ws.exit_blocked(),
			"the crewed catapult drives off the entrance pad (took %d ticks)" % t)
		check(engine.boarded_count() >= 1, "it moved under its own crew")
		var d: float = Vector2(engine.position.x - ws.entrance_world().x,
			engine.position.z - ws.entrance_world().z).length()
		check(d > Workshop.EXIT_CLEAR_RADIUS,
			"the catapult left the entrance area so the next one can be built")
	_free_world(w)


# --- Vehicle destruction (fire/lava burn, terrain rip) -----------------------------

func test_engine_burns_from_fire_spell_and_sinks() -> void:
	var w: Dictionary = _make_world()
	var engine: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, w.nav.cell_to_world(Vector2i(60, 60))) as SiegeEngine
	var crew: Brave = _board_crew(w, engine)
	# Enemy shaman fireball hits the vehicle: it catches fire...
	var bolt: FireballBolt = FireballBolt.new()
	bolt.setup(1, engine.position + Vector3(-8.0, 0.0, 0.0), engine.position,
		null, w.unit_manager, w.td)
	while not bolt.done:
		bolt.tick(TICK)
	bolt.free()
	check(engine.is_burning(), "a fire-spell hit sets the catapult alight")
	# ...burns out and is destroyed; the crew survives and is released.
	var t: float = 0.0
	while engine.state != Unit.State.DEAD and t < 10.0:
		_tick_world(w)
		t += TICK
	check(engine.state == Unit.State.DEAD, "the burning catapult is destroyed")
	check(is_instance_valid(crew) and crew.state != Unit.State.DEAD,
		"the crew survives the loss of the vehicle")
	check(crew.siege_engine == null and crew.state == Unit.State.IDLE,
		"the crew is released and individually controllable again")
	_free_world(w)


func test_engine_burns_from_lava() -> void:
	var w: Dictionary = _make_world()
	var engine: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, w.nav.cell_to_world(Vector2i(60, 60))) as SiegeEngine
	var surge: LavaSurge = LavaSurge.new()
	surge.setup(engine.position, w.unit_manager, w.td, 3.0)
	for i in range(10):
		surge.tick(TICK)
	check(engine.is_burning(), "lava sets the catapult alight")
	surge.free()
	_free_world(w)


func test_engine_bursts_on_terrain_rip() -> void:
	var w: Dictionary = _make_world()
	var engine: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, w.nav.cell_to_world(Vector2i(60, 60))) as SiegeEngine
	var crew: Brave = _board_crew(w, engine)
	check(engine.state != Unit.State.DEAD, "intact on level ground")
	# A spell rips a cliff under the chassis (way beyond drivable slopes):
	# the whole +x side of the vehicle is heaved several metres up.
	var c: Vector2i = w.nav.world_to_cell(engine.position)
	for vz in range(c.y - 2, c.y + 4):
		for vx in range(c.x + 1, c.x + 4):
			w.td.set_vertex_height(vx, vz, w.td.vertex_height(vx, vz) + 6.0)
	var t: float = 0.0
	while engine.state != Unit.State.DEAD and t < 3.0:
		_tick_world(w)
		t += TICK
	check(engine.state == Unit.State.DEAD, "the torn ground bursts the catapult")
	check(is_instance_valid(crew) and crew.state != Unit.State.DEAD
		and crew.siege_engine == null,
		"the crew survives the burst and is released")
	_free_world(w)


func test_tornado_lifts_and_bursts_catapult() -> void:
	var w: Dictionary = _make_world()
	var engine: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, w.nav.cell_to_world(Vector2i(60, 60))) as SiegeEngine
	_board_crew(w, engine)
	var vortex: TornadoVortex = TornadoVortex.new()
	vortex.setup(0, engine.position, w.unit_manager, w.td, w.building_manager)
	# Under 2 s near: lifted but intact.
	vortex._affect_siege_engines(1.0)
	check(engine.state != Unit.State.DEAD, "under 2 s the catapult is only lifted")
	check(engine._tornado_lift > 0.0, "the tornado lifts the catapult while near")
	# Cross the 2 s threshold: it bursts into two 1-wood chunks.
	vortex._affect_siege_engines(1.5)
	check(engine.state == Unit.State.DEAD, "after 2 s near the catapult bursts")
	var chunks: int = 0
	for p in w.unit_manager.projectiles:
		if p is TornadoDebris and p.wood == 1:
			chunks += 1
	check(chunks == 2, "the burst leaves two 1-wood chunks flying")
	# They fling and settle into 2 wood total.
	var t: int = 0
	while not w.unit_manager.projectiles.is_empty() and t < 400:
		w.unit_manager.tick(0.1)
		t += 1
	check(w.wood_pile_manager.total_wood() == 2,
		"the two chunks settle into 2 wood on the ground")
	vortex.free()
	_free_world(w)


## Drifting out of the near radius before 2 s resets the timer (the vehicle
## settles back down, no burst).
func test_tornado_near_reset_spares_catapult() -> void:
	var w: Dictionary = _make_world()
	var engine: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, w.nav.cell_to_world(Vector2i(60, 60))) as SiegeEngine
	_board_crew(w, engine)
	var vortex: TornadoVortex = TornadoVortex.new()
	vortex.setup(0, engine.position, w.unit_manager, w.td, w.building_manager)
	vortex._affect_siege_engines(1.5)   # 1.5 s near
	check(engine.state != Unit.State.DEAD, "not yet burst")
	# Tornado drifts away, then comes back briefly — the timer restarts.
	vortex.position += Vector3(20.0, 0.0, 0.0)
	vortex._affect_siege_engines(0.2)
	check(engine._tornado_lift == 0.0, "out of range: the catapult settles back down")
	vortex.position = engine.position
	vortex._affect_siege_engines(1.5)   # only 1.5 s again -> still alive
	check(engine.state != Unit.State.DEAD,
		"a broken-off approach does not accumulate — no burst under 2 s continuous")
	vortex.free()
	_free_world(w)


# --- Selection rules (crew selects the catapult) ------------------------------------

func test_crew_selection_maps_to_engine() -> void:
	var w: Dictionary = _make_world()
	var engine: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, w.nav.cell_to_world(Vector2i(60, 60))) as SiegeEngine
	var crew: Brave = _board_crew(w, engine)
	var loose: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(70, 70))) as Brave
	check(SelectionManager._crew_to_engine(crew) == engine,
		"picking a crew member yields its catapult")
	check(SelectionManager._crew_to_engine(loose) == loose,
		"ordinary units pass through the crew mapping")
	check(engine.selection_ring_scale() > loose.selection_ring_scale(),
		"the catapult shows a bigger selection ring than a unit")
	_free_world(w)


# --- Vehicle navigation ----------------------------------------------------------

func test_vehicle_paths_need_wide_corridors() -> void:
	var w: Dictionary = _make_world()
	var nav: NavGrid = w.nav
	# Wall across the map with a 1-cell gap: fine for units, closed to vehicles.
	var wall_x: int = 64
	for z in range(0, TerrainData.SIZE):
		if z == 60:
			continue   # the 1-cell gap
		nav.fill_solid_region(Rect2i(Vector2i(wall_x, z), Vector2i(1, 1)), true)
	var from: Vector3 = nav.cell_to_world(Vector2i(50, 60))
	var to: Vector3 = nav.cell_to_world(Vector2i(80, 60))
	check(not nav.find_path(from, to).is_empty(),
		"a unit squeezes through the 1-cell gap")
	check(nav.find_vehicle_path(from, to).is_empty(),
		"the vehicle cannot pass the 1-cell gap")
	# Widen to 2 cells: now the vehicle fits.
	nav.fill_solid_region(Rect2i(Vector2i(wall_x, 61), Vector2i(1, 1)), false)
	check(not nav.find_vehicle_path(from, to).is_empty(),
		"a 2-cell corridor is wide enough for the vehicle")
	_free_world(w)


# --- Roll hardening (§9): rolls abort attacks, casts and conversions ----------------

func test_roll_aborts_attack() -> void:
	var attacker: Warrior = Warrior.new()
	var victim: Brave = Brave.new()
	attacker._begin_attack(victim)
	check(attacker.attack_target == victim, "attack running")
	attacker.start_roll(Vector3(1, 0, 0))
	check(attacker.state == Unit.State.ROLL, "attacker rolls")
	check(attacker.attack_target == null, "the roll dropped the attack target")
	attacker.free()
	victim.free()


func test_roll_aborts_preacher_conversion() -> void:
	# Preacher rolls mid-channel: the sitting victim stands up.
	var preacher: Preacher = Preacher.new()
	var victim: Brave = Brave.new()
	preacher.state = Unit.State.CAST
	check(victim.begin_conversion(preacher, 5.0), "victim pacified")
	check(victim.state == Unit.State.SIT, "victim sits")
	preacher.start_roll(Vector3(1, 0, 0))
	check(preacher.state == Unit.State.ROLL, "preacher rolls")
	victim.tick(TICK)
	check(victim.state != Unit.State.SIT and victim.converting_preacher == null,
		"the victim stands up once the preacher tumbles")
	preacher.free()
	victim.free()


func test_roll_aborts_victim_conversion() -> void:
	# The SIT victim itself is bowled over: the conversion breaks.
	var preacher: Preacher = Preacher.new()
	var victim: Brave = Brave.new()
	preacher.state = Unit.State.CAST
	victim.begin_conversion(preacher, 5.0)
	victim.conversion_progress = 3.0
	victim.start_roll(Vector3(1, 0, 0))
	check(victim.state == Unit.State.ROLL, "the victim rolls")
	check(victim.converting_preacher == null and victim.conversion_progress == 0.0,
		"rolling broke the conversion (progress lost)")
	# And a rolling unit cannot be pacified at all.
	check(not victim.begin_conversion(preacher, 5.0),
		"a rolling unit cannot be converted")
	preacher.free()
	victim.free()


func test_roll_aborts_shaman_cast() -> void:
	var shaman: Shaman = Shaman.new()
	var spell: Spell = Spell.new()
	spell.charges = 1
	check(shaman.order_cast(spell, Vector3(5, 0, 5), null), "cast order accepted")
	check(shaman.state == Unit.State.CAST and shaman.pending_spell == spell,
		"shaman is casting")
	shaman.start_roll(Vector3(1, 0, 0))
	check(shaman.state == Unit.State.ROLL, "shaman rolls")
	check(shaman.pending_spell == null, "the roll cancelled the pending cast")
	check(spell.charges == 1, "the charge is kept (cast never released)")
	shaman.free()


# --- AI ---------------------------------------------------------------------------

func test_ai_builds_workshop_after_temple() -> void:
	var w: Dictionary = _make_world()
	var ai: AIController = AIController.new()
	ai.setup(w.tribe, w.commands, w.unit_manager, w.building_manager,
		w.tree_manager, w.nav, Vector2i(60, 60))
	# Enough trees near the base — otherwise the AI wants a forester first.
	for i in range(8):
		w.tree_manager.spawn_tree(Vector2i(58 + 3 * (i % 4), 66 + 3 * (i / 4)),
			TreeResource.MAX_STAGE)
	# Full essential base: huts, all three camps — the workshop is next.
	w.building_manager.place(HUT_SCENE, w.tribe, Vector2i(50, 50), 0, true)
	w.building_manager.place(HUT_SCENE, w.tribe, Vector2i(50, 56), 0, true)
	w.building_manager.place(HUT_SCENE, w.tribe, Vector2i(50, 62), 0, true)
	w.building_manager.place(WARRIOR_CAMP_SCENE, w.tribe, Vector2i(56, 50), 0, true)
	w.building_manager.place(
		preload("res://scenes/buildings/firewarrior_camp.tscn"), w.tribe,
		Vector2i(56, 56), 0, true)
	w.building_manager.place(
		preload("res://scenes/buildings/temple.tscn"), w.tribe,
		Vector2i(56, 62), 0, true)
	var next: PackedScene = ai._next_building_scene({})
	check(next != null and next.resource_path.ends_with("workshop.tscn"),
		"the AI plans the workshop right after the temple")
	# Staffing: idle braves are sent in as workers.
	var ws: Workshop = _place_workshop(w, Vector2i(64, 50))
	for i in range(12):
		w.unit_manager.spawn_unit(BRAVE_SCENE, 0,
			w.nav.cell_to_world(Vector2i(62, 48 + i)))
	ai._staff_workshops()
	check(ws.occupants.size() == 3, "the AI staffs the workshop with 3 braves")
	ai.free()
	_free_world(w)


## Phase 8.2: two siege engines keep the vehicle separation distance (crews
## included, they glide on their side slots) — engines parked on top of each
## other used to overlap visually and their crews clipped into each other.
## Pedestrians still cannot shove a vehicle around (push_immune).
func test_vehicle_separation_spreads_engines() -> void:
	var w: Dictionary = _make_world()
	var e1: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, w.nav.cell_to_world(Vector2i(60, 60))) as SiegeEngine
	var e2: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, Vector3(61.0, 0.0, 60.5)) as SiegeEngine
	check(e1.vehicle_separation > 2.0, "engines carry a big separation radius")
	for i in range(300):
		_tick_world(w)
	var d: float = Vector2(e1.position.x - e2.position.x,
		e1.position.z - e2.position.z).length()
	check(d >= e1.vehicle_separation - 0.4,
		"the engines spread apart (%.2f m)" % d)

	# A pedestrian right at an engine does not shove the vehicle around.
	var before: Vector3 = e1.position
	w.unit_manager.spawn_unit(BRAVE_SCENE, 0,
		e1.position + Vector3(0.2, 0.0, 0.0))
	for i in range(100):
		_tick_world(w)
	check(Vector2(e1.position.x - before.x, e1.position.z - before.z).length() < 0.5,
		"a pedestrian cannot push the vehicle away")
	_free_world(w)


# --- Damaged workshop keeps its production stock ------------------------------

## A merely damaged workshop leaves its entrance catapult-stock on the ground —
## the passive repair-absorb must NOT eat it (this was the catapult-shot bug).
## Only an actively staffed repair (or fire) consumes it.
func test_damaged_workshop_keeps_stock() -> void:
	var w: Dictionary = _make_world()
	var ws: Workshop = _place_workshop(w)
	w.wood_pile_manager.deposit(ws.delivery_point(), 15)
	var stock0: int = ws.stock_wood()
	check(stock0 > 0, "stock piled at the entrance")
	ws.apply_destruction_stages(1)   # damage into stage 1, nobody repairing
	check(ws.destruction_stage() >= 1 and ws.health > 0, "workshop damaged but standing")
	check(ws.workers.is_empty(), "no repair crew assigned")
	check(not ws._absorbs_repair_wood(), "no passive absorb without a repair crew")
	for i in range(300):
		_tick_world(w)
	check(ws.stock_wood() == stock0, "the damaged workshop leaves its stock lying")
	_free_world(w)
