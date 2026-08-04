extends TestBase

## Phase 10f: the hut grows. It starts small and cheap (8 wood, 10 places,
## 2 workers) and is upgraded in four stages to the Wohnpalast (28 wood
## cumulative, 45 places, 6 workers). A timer makes an upgrade DUE; the whole crew
## then leaves, fetches HUT_UPGRADE_WOOD_COST wood and builds. Blocked upgrades
## hold at "due" instead of starting: tribe-wide lock, per-hut pause, damage, or
## no wood in reach.
##
## The single most important guard here is
## test_hut_keeps_its_housing_while_upgrading: `upgrading` must NOT flip
## is_usable(), because housing_capacity() returns 0 for an unusable hut — the
## tribe's whole population cap would collapse during every upgrade.

const TICK: float = 0.05
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


func _make_world() -> Dictionary:
	var td: TerrainData = _flat_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var tribe: Tribe = Tribe.new(0)
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe] as Array[Tribe], tm, wpm)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um, wpm)
	var commands: TribeCommands = TribeCommands.new()
	commands.setup(nav, bm, um, tm)
	return {"td": td, "nav": nav, "tribe": tribe, "um": um, "bm": bm, "tm": tm,
		"wpm": wpm, "commands": commands}


func _free_world(w: Dictionary) -> void:
	w.tm.free()
	w.wpm.free()
	w.bm.free()
	w.um.free()


func _place_hut(w: Dictionary, cell: Vector2i) -> Hut:
	return w.bm.place(HUT_SCENE, w.tribe, cell, 0, true) as Hut


## One simulation step: move every unit, refresh the manager (hash/paths), then
## tick the hut.
func _step(w: Dictionary, hut: Hut, dt: float) -> void:
	for u in w.um.units.duplicate():
		if is_instance_valid(u):
			u.tick(dt)
	w.um.tick(dt)
	hut.tick(dt)


## Wood in reach so _upgrade_wood_reachable() passes. A pile is used instead of a
## tree wherever the test only needs the START condition — it needs no chopping.
func _wood_near(w: Dictionary, hut: Hut, amount: int) -> void:
	w.wpm.deposit(hut.delivery_point(), amount)


## Fast-forwards the due timer without simulating 90 s: the timer is filled
## directly and one tick lets _tick_upgrade_timer evaluate the start conditions.
func _make_due(hut: Hut) -> void:
	hut._upgrade_timer = Balance.HUT_UPGRADE_DELAY


## Fills the hut with crew (up to its stage capacity).
func _man_hut(w: Dictionary, hut: Hut) -> void:
	while hut.crew_count() < hut.crew_capacity():
		hut.admit_crew(w.um.spawn_unit(BRAVE_SCENE, 0, hut.center_world()))


func test_stage_zero_hut_has_the_new_small_values() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	check(hut.wood_cost == 8, "a fresh hut costs 8 wood (was 12)")
	check(hut.upgrade_stage == 0, "a fresh hut starts at stage 0")
	check(hut.capacity() == 10, "stage 0 houses 10 (was 40)")
	check(hut.crew_capacity() == 2, "stage 0 has 2 worker slots (was 4)")
	check(hut.housing_capacity() == 10, "the tribe sees those 10 places")
	check(hut.display_name() == "Hütte", "stage 0 is still called Hütte")
	_free_world(w)


func test_capacity_and_crew_grow_per_stage() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	for stage in range(Balance.HUT_MAX_UPGRADE_STAGE + 1):
		hut.upgrade_stage = stage
		check(hut.capacity() == Balance.HUT_CAPACITY_PER_STAGE[stage],
			"stage %d capacity matches the balance array" % stage)
		check(hut.crew_capacity() == Balance.HUT_CREW_PER_STAGE[stage],
			"stage %d crew matches the balance array" % stage)
	# The concrete ladder the design asks for: +8 per stage, +11 on the last one.
	check(Balance.HUT_CAPACITY_PER_STAGE == ([10, 18, 26, 34, 45] as Array[int]),
		"places per stage are 10/18/26/34/45 (last stage +11, not +8)")
	check(Balance.HUT_CREW_PER_STAGE == ([2, 3, 4, 5, 6] as Array[int]),
		"workers per stage are 2/3/4/5/6")
	check(hut.display_name() == "Wohnpalast", "the last stage is the Wohnpalast")
	_free_world(w)


func test_spawn_rate_is_linear_in_the_crew() -> void:
	var w: Dictionary = _make_world()
	w.tribe.growth_mode = Tribe.GrowthMode.NONE
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	hut.admit_crew(w.um.spawn_unit(BRAVE_SCENE, 0, hut.center_world()))
	var one: float = hut.growth_per_minute()
	hut.admit_crew(w.um.spawn_unit(BRAVE_SCENE, 0, hut.center_world()))
	check(hut.crew_count() == 2, "two workers in a stage-0 hut")
	check_near(hut.growth_per_minute(), one * 2.0,
		"two workers produce exactly twice as fast (no full-crew bonus)")
	check_near(one, 60.0 / Balance.HUT_SPAWN_SECONDS_PER_WORKER,
		"one worker's rate is 60 / seconds-per-worker")
	_free_world(w)


func test_upgrade_becomes_ready_after_the_delay() -> void:
	var w: Dictionary = _make_world()
	w.tribe.growth_mode = Tribe.GrowthMode.NONE
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	check(not hut.upgrade_ready(), "a fresh hut has no upgrade due yet")
	# No wood anywhere, so the timer fills but nothing starts.
	var steps: int = int(Balance.HUT_UPGRADE_DELAY / TICK) + 4
	for i in range(steps):
		hut.tick(TICK)
	check(hut.upgrade_ready(), "after HUT_UPGRADE_DELAY the upgrade is due")
	check(not hut.upgrading, "but it does not start without wood in reach")
	_free_world(w)


func test_upgrade_progress_stops_at_full_while_forbidden() -> void:
	var w: Dictionary = _make_world()
	w.tribe.growth_mode = Tribe.GrowthMode.NONE
	w.tribe.upgrades_allowed = false
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	_wood_near(w, hut, Balance.HUT_UPGRADE_WOOD_COST)
	_make_due(hut)
	for i in range(40):
		hut.tick(TICK)
	check(hut.upgrade_ready(), "the due state HOLDS while the tribe lock is on")
	check(not hut.upgrading, "no upgrade starts while the tribe lock is on")
	check(hut.upgrade_stage == 0, "still stage 0")
	# Released: the very next tick starts the work.
	w.tribe.upgrades_allowed = true
	hut.tick(TICK)
	check(hut.upgrading, "releasing the lock starts the waiting upgrade")
	_free_world(w)


func test_paused_hut_does_not_upgrade() -> void:
	var w: Dictionary = _make_world()
	w.tribe.growth_mode = Tribe.GrowthMode.NONE
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	_wood_near(w, hut, Balance.HUT_UPGRADE_WOOD_COST)
	hut.paused = true
	_make_due(hut)
	for i in range(40):
		hut.tick(TICK)
	check(hut.upgrade_ready(), "the upgrade stays due while the hut is paused")
	check(not hut.upgrading, "a paused hut does not start its upgrade")
	hut.paused = false
	hut.tick(TICK)
	check(hut.upgrading, "unpausing starts it")
	_free_world(w)


func test_upgrade_waits_for_reachable_wood() -> void:
	var w: Dictionary = _make_world()
	# MAXIMUM, or the growth tick itself would empty the hut after a second and
	# the "crew was not ejected" check below would test nothing.
	w.tribe.growth_mode = Tribe.GrowthMode.MAXIMUM
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	_man_hut(w, hut)
	var crew_before: int = hut.crew_count()
	_make_due(hut)
	for i in range(40):
		hut.tick(TICK)
	check(not hut.upgrading, "no wood in reach: the upgrade waits")
	check(hut.crew_count() == crew_before,
		"and the crew is NOT ejected into a hopeless search")
	# A tree well inside HUT_UPGRADE_WOOD_RADIUS is enough to start.
	w.tm.spawn_tree(Vector2i(66, 60))
	hut.tick(TICK)
	check(hut.upgrading, "a tree in reach starts the upgrade")
	_free_world(w)


func test_upgrade_ejects_the_whole_crew() -> void:
	var w: Dictionary = _make_world()
	w.tribe.growth_mode = Tribe.GrowthMode.NONE
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	_wood_near(w, hut, Balance.HUT_UPGRADE_WOOD_COST)
	_man_hut(w, hut)
	var crew: Array = hut.crew.duplicate()
	var pop: int = w.tribe.population()
	_make_due(hut)
	hut.tick(TICK)
	check(hut.upgrading, "upgrade started")
	check(hut.crew_count() == 0, "the WHOLE crew left the hut")
	for u: Unit in crew:
		check(u in w.um.units, "every ex-crew brave is back in the world")
		check((u as Brave).job == hut, "and is on the upgrade job")
	check(w.tribe.population() == pop, "population unchanged by the eject")
	check(not hut.has_crew_room(), "an upgrading hut takes no new crew")
	_free_world(w)


func test_hut_produces_nothing_while_upgrading() -> void:
	var w: Dictionary = _make_world()
	# MAXIMUM would normally refill the crew — it must not while upgrading.
	w.tribe.growth_mode = Tribe.GrowthMode.MAXIMUM
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	_wood_near(w, hut, Balance.HUT_UPGRADE_WOOD_COST)
	_man_hut(w, hut)
	_make_due(hut)
	hut.tick(TICK)
	check(hut.upgrading, "upgrade started")
	var pop: int = w.tribe.population()
	for i in range(int(Balance.HUT_SPAWN_SECONDS_PER_WORKER / TICK)):
		hut.tick(TICK)
		if not hut.upgrading:
			break
	check(w.tribe.population() == pop, "no braves are produced during the upgrade")
	check(hut.production_progress() < 0.0, "no production bar during the upgrade")
	_free_world(w)


## Regression guard for the is_usable() trap: housing_capacity() returns 0 for an
## unusable building, so if `upgrading` ever flipped is_usable() the tribe's
## population cap would collapse during every upgrade.
func test_hut_keeps_its_housing_while_upgrading() -> void:
	var w: Dictionary = _make_world()
	w.tribe.growth_mode = Tribe.GrowthMode.NONE
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	_wood_near(w, hut, Balance.HUT_UPGRADE_WOOD_COST)
	var housing: int = w.tribe.housing_capacity()
	check(housing == 10, "stage-0 housing before the upgrade")
	_make_due(hut)
	hut.tick(TICK)
	check(hut.upgrading, "upgrade started")
	check(hut.is_usable(), "an upgrading hut stays USABLE on purpose")
	check(hut.housing_capacity() == housing, "the hut keeps its housing capacity")
	check(w.tribe.housing_capacity() == housing, "so the tribe's cap does not drop")
	_free_world(w)


func test_finished_upgrade_raises_stage_capacity_crew_and_hp() -> void:
	var w: Dictionary = _make_world()
	w.tribe.growth_mode = Tribe.GrowthMode.NONE
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	_wood_near(w, hut, Balance.HUT_UPGRADE_WOOD_COST)
	_make_due(hut)
	hut.tick(TICK)
	check(hut.upgrading, "upgrade started")
	# Absorb the pile, then do the work in one go.
	for i in range(int(Building.ABSORB_INTERVAL / TICK) + 2):
		hut.tick(TICK)
	check(hut.upgrade_wood == Balance.HUT_UPGRADE_WOOD_COST,
		"the delivered pile is absorbed into the upgrade buffer")
	check(hut.work_upgrade(1.0), "the work is applied")
	check(not hut.upgrading, "a full upgrade ends the building work")
	check(hut.upgrade_stage == 1, "stage raised to 1")
	check(hut.capacity() == 18, "stage 1 houses 18")
	check(hut.crew_capacity() == 3, "stage 1 has 3 worker slots")
	check(hut.max_health == Balance.HUT_HP_PER_STAGE[1], "stage 1 max HP applied")
	check(hut.health == hut.max_health, "and the hut is at full health")
	check(hut.wood_cost == 8 + Balance.HUT_UPGRADE_WOOD_COST,
		"the upgrade wood became part of the hut's price")
	check(hut.upgrade_wood == 0, "the upgrade buffer is spent")
	check(not hut.upgrade_ready(), "the next upgrade is not due yet")
	_free_world(w)


func test_full_ladder_reaches_the_wohnpalast() -> void:
	var w: Dictionary = _make_world()
	w.tribe.growth_mode = Tribe.GrowthMode.NONE
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	for stage in range(Balance.HUT_MAX_UPGRADE_STAGE):
		_wood_near(w, hut, Balance.HUT_UPGRADE_WOOD_COST)
		_make_due(hut)
		hut.tick(TICK)
		check(hut.upgrading, "upgrade %d started" % (stage + 1))
		for i in range(int(Building.ABSORB_INTERVAL / TICK) + 2):
			hut.tick(TICK)
		hut.work_upgrade(1.0)
		check(hut.upgrade_stage == stage + 1, "reached stage %d" % (stage + 1))
	check(hut.upgrade_stage == Balance.HUT_MAX_UPGRADE_STAGE, "stage 4 reached")
	check(hut.capacity() == 45, "the Wohnpalast houses 45")
	check(hut.crew_capacity() == 6, "the Wohnpalast has 6 worker slots")
	check(hut.wood_cost == 8 + 4 * Balance.HUT_UPGRADE_WOOD_COST,
		"a fully upgraded hut cost 28 wood in total")
	_free_world(w)


func test_max_stage_hut_never_upgrades_again() -> void:
	var w: Dictionary = _make_world()
	w.tribe.growth_mode = Tribe.GrowthMode.NONE
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	hut.upgrade_stage = Balance.HUT_MAX_UPGRADE_STAGE
	_wood_near(w, hut, 50)
	_make_due(hut)
	for i in range(200):
		hut.tick(TICK)
	check(not hut.upgrade_ready(), "the top stage is never 'due'")
	check(not hut.upgrading, "and never starts an upgrade")
	check(hut.upgrade_stage == Balance.HUT_MAX_UPGRADE_STAGE, "still at the top stage")
	_free_world(w)


func test_upgrade_refund_counts_toward_the_demolition_payout() -> void:
	var w: Dictionary = _make_world()
	w.tribe.growth_mode = Tribe.GrowthMode.NONE
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	# Straight to stage 3: 8 + 3 * 5 = 23 wood invested.
	for stage in range(3):
		_wood_near(w, hut, Balance.HUT_UPGRADE_WOOD_COST)
		_make_due(hut)
		hut.tick(TICK)
		for i in range(int(Building.ABSORB_INTERVAL / TICK) + 2):
			hut.tick(TICK)
		hut.work_upgrade(1.0)
	check(hut.upgrade_stage == 3, "stage 3 reached")
	check(hut.wood_cost == 23, "8 + 3 x 5 = 23 wood invested")
	var expected: int = int(floor(23.0 * Balance.DEMOLISH_REFUND_BUILT))
	check(hut.demolish_refund_total() == expected,
		"the refund is 75 %% of 23 (not of the base 8): %d" % expected)
	_free_world(w)


func test_damage_cancels_a_running_upgrade_and_returns_the_wood() -> void:
	var w: Dictionary = _make_world()
	w.tribe.growth_mode = Tribe.GrowthMode.NONE
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	_wood_near(w, hut, Balance.HUT_UPGRADE_WOOD_COST)
	_make_due(hut)
	hut.tick(TICK)
	for i in range(int(Building.ABSORB_INTERVAL / TICK) + 2):
		hut.tick(TICK)
	check(hut.upgrading and hut.upgrade_wood > 0, "upgrade running with wood on site")
	var banked: int = hut.upgrade_wood
	var on_ground: int = w.wpm.total_wood()
	# Past 30 % damage the hut is unusable -> stage 1 -> the upgrade is dropped.
	hut.take_damage(int(hut.max_health * 0.5))
	check(not hut.upgrading, "damage cancels the running upgrade")
	check(hut.upgrade_stage == 0, "and does not advance the stage")
	check(hut.upgrade_wood == 0, "the upgrade buffer is emptied")
	check(w.wpm.total_wood() == on_ground + banked,
		"the delivered upgrade wood is back on the ground")
	check(hut.upgrade_ready(), "the upgrade stays DUE for after the repair")
	_free_world(w)


func test_stalled_upgrade_is_cancelled_and_refunded() -> void:
	var w: Dictionary = _make_world()
	w.tribe.growth_mode = Tribe.GrowthMode.NONE
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	# Only part of the wood: the upgrade can never finish, and with no workers
	# left nothing ever moves — exactly the "crew died on the way" case.
	_wood_near(w, hut, 2)
	_make_due(hut)
	hut.tick(TICK)
	check(hut.upgrading, "upgrade started")
	var steps: int = int(Balance.HUT_UPGRADE_STALL_TIMEOUT / TICK) + 20
	for i in range(steps):
		hut.tick(TICK)
		if not hut.upgrading:
			break
	check(not hut.upgrading, "a stalled upgrade is cancelled after the timeout")
	check(hut.upgrade_stage == 0, "no stage was gained")
	check(hut.upgrade_wood == 0, "the upgrade buffer is emptied")
	check(w.wpm.total_wood() == 2, "the 2 absorbed wood are back on the ground")
	# And it does NOT restart on the next tick just because its own refund now
	# satisfies "wood in reach" again — that was a cancel/restart loop.
	check(not hut.upgrade_ready(), "the due timer was reset, so no instant restart")
	for i in range(40):
		hut.tick(TICK)
	check(not hut.upgrading, "still not upgrading a moment later")
	_free_world(w)


func test_demolition_of_an_upgrading_hut_keeps_the_wood_in_the_payout() -> void:
	var w: Dictionary = _make_world()
	w.tribe.growth_mode = Tribe.GrowthMode.NONE
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	_wood_near(w, hut, Balance.HUT_UPGRADE_WOOD_COST)
	_make_due(hut)
	hut.tick(TICK)
	for i in range(int(Building.ABSORB_INTERVAL / TICK) + 2):
		hut.tick(TICK)
	check(hut.upgrading and hut.upgrade_wood == Balance.HUT_UPGRADE_WOOD_COST,
		"upgrade running, its wood banked")
	# 8 (hut) + 5 (banked upgrade wood) at 75 %.
	var expected: int = int(floor(float(8 + Balance.HUT_UPGRADE_WOOD_COST)
		* Balance.DEMOLISH_REFUND_BUILT))
	check(hut.demolish_refund_total() == expected,
		"the banked upgrade wood is part of the demolition payout")
	hut.begin_demolish()
	check(not hut.upgrading, "the demolition drops the upgrade")
	check(hut.upgrade_wood == 0, "without paying its wood out a second time")
	_free_world(w)


func test_upgrade_workers_stay_on_the_job() -> void:
	var w: Dictionary = _make_world()
	w.tribe.growth_mode = Tribe.GrowthMode.NONE
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	_wood_near(w, hut, Balance.HUT_UPGRADE_WOOD_COST)
	_man_hut(w, hut)
	var crew: Array = hut.crew.duplicate()
	_make_due(hut)
	hut.tick(TICK)
	check(hut.upgrading, "upgrade started")
	# Without the `job.upgrading` clause in Brave._job_active the workers would
	# drop the job on their very next tick (the hut is finished and undamaged).
	for i in range(20):
		_step(w, hut, TICK)
		if not hut.upgrading:
			break
	var still: int = 0
	for u: Unit in crew:
		if is_instance_valid(u) and (u as Brave).job == hut:
			still += 1
	check(still > 0 or not hut.upgrading,
		"the upgrade workers keep their job (or the upgrade already finished)")
	_free_world(w)


func test_braves_finish_an_upgrade_on_their_own() -> void:
	var w: Dictionary = _make_world()
	w.tribe.growth_mode = Tribe.GrowthMode.NONE
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	# A tree in reach (start condition) AND a pile at the entrance, so the crew
	# can deliver without a long chopping detour.
	w.tm.spawn_tree(Vector2i(66, 60))
	_wood_near(w, hut, Balance.HUT_UPGRADE_WOOD_COST)
	_man_hut(w, hut)
	_make_due(hut)
	hut.tick(TICK)
	check(hut.upgrading, "upgrade started")
	var done: bool = false
	for i in range(int(60.0 / TICK)):   # up to 60 s of sim
		_step(w, hut, TICK)
		if hut.upgrade_stage == 1:
			done = true
			break
	check(done, "the ejected crew builds the upgrade to completion by itself")
	check(not hut.upgrading, "and the upgrade flag is cleared")
	_free_world(w)
