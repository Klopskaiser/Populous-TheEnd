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


func test_workshop_produces_catapult() -> void:
	var w: Dictionary = _make_world()
	var ws: Workshop = _place_workshop(w)
	check(ws != null and ws.is_usable(), "pre-built workshop is usable")
	check(ws.footprint == Vector2i(8, 4), "workshop has the big 8x4 footprint")
	check(ws.wood_cost == 15, "workshop costs 15 wood")
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

	# Cap: one MANNED catapult of the tribe + max 1 -> auto-stop.
	var engine: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, w.nav.cell_to_world(Vector2i(80, 80))) as SiegeEngine
	_board_crew(w, engine)
	check(ws.manned_catapult_count() == 1, "the boarded catapult counts as manned")
	ws.max_catapults = 1
	check(not ws.can_start_production(), "cap reached -> production auto-stops")
	ws.max_catapults = 2
	check(ws.can_start_production(), "raising the cap resumes production")
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
	check(camp.trainee == null and not is_instance_valid(trainee),
		"the stationed trainee died in the strike")
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

	# order_attack_building on ordinary units is rejected.
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(52, 60))) as Brave
	w.commands.order_attack_building([brave] as Array[Unit], camp)
	check(brave.state == Unit.State.IDLE, "order_attack_building ignores non-siege units")
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
