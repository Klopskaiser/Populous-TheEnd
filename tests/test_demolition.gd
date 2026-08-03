extends TestBase

## Headless tests for phase 10d: demolishing own buildings (key Entf). A site
## that never reached a build stage is scrapped instantly at 100 % refund;
## everything else becomes a worker job at 75 %, with build_progress running
## backwards and the wood coming back in portions. All nodes live outside the
## scene tree and are freed manually.

const TICK: float = 0.05
const MAX_TICKS: int = 20000

const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const SITE_SCENE: PackedScene = preload("res://scenes/buildings/reincarnation_site.tscn")
const CAMP_SCENE: PackedScene = preload("res://scenes/buildings/warrior_camp.tscn")
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
	var enemy: Tribe = Tribe.new(1)
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe, enemy] as Array[Tribe], tm, wpm)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um, wpm)
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(nav, bm, um, tm)
	return {
		"td": td, "nav": nav, "tribe": tribe, "enemy": enemy,
		"unit_manager": um, "building_manager": bm,
		"tree_manager": tm, "wood_pile_manager": wpm, "commands": tc,
	}


func _free_world(w: Dictionary) -> void:
	w.commands.free()
	w.tree_manager.free()
	w.wood_pile_manager.free()
	w.building_manager.free()
	w.unit_manager.free()


## Wood lying in piles anywhere on the map.
func _total_pile_wood(w: Dictionary) -> int:
	return w.wood_pile_manager.total_wood()


## Spawns `n` braves next to `building` and puts them on the demolition.
func _demolishers(w: Dictionary, building: Building, n: int) -> Array[Brave]:
	var crew: Array[Brave] = []
	for i in range(n):
		var pos: Vector3 = building.delivery_point() + Vector3(float(i) * 1.2, 0.0, 2.0)
		var b: Brave = w.unit_manager.spawn_unit(BRAVE_SCENE, building.tribe_id, pos) as Brave
		b.order_demolish(building)
		crew.append(b)
	return crew


## Ticks buildings + braves until `building` is gone (or the tick budget runs out).
func _run_until_gone(w: Dictionary, building: Building, crew: Array[Brave]) -> int:
	var ticks: int = 0
	while building.health > 0 and ticks < MAX_TICKS:
		w.building_manager.tick(TICK)
		for b in crew:
			if is_instance_valid(b):
				b.tick(TICK)
		ticks += 1
	return ticks


# --- Instant scrapping (no build stage) ---------------------------------------

func test_demolish_unbuilt_site_is_instant_and_refunds_all() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	# Wood delivered but nothing built yet: the plot is still being graded.
	hut.wood_delivered = 7
	check(not hut.has_build_stage(), "no build stage reached yet")
	check(hut.demolish_refund_total() == 7, "unbuilt site refunds 100 % of its wood")

	check(w.commands.demolish_building(w.tribe, hut), "demolition accepted")
	check(hut.health <= 0, "an unbuilt site is scrapped instantly")
	check(_total_pile_wood(w) == 7, "the full wood lies at the plot")
	_free_world(w)


func test_demolished_building_frees_nav_footprint() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	var cell: Vector2i = hut.cell + Vector2i(1, 1)
	check(w.nav.is_cell_blocked_by_building(cell), "the plot blocks navigation")
	w.commands.demolish_building(w.tribe, hut)
	check(not w.nav.is_cell_blocked_by_building(cell),
		"the scrapped plot is walkable/buildable again")
	_free_world(w)


# --- Worker demolition (build stage reached) ----------------------------------

func test_demolish_after_build_stage_needs_workers() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.building_manager.place(HUT_SCENE, w.tribe, Vector2i(60, 60), 0, true) as Hut
	check(hut.has_build_stage(), "a finished building always counts as built")

	check(w.commands.demolish_building(w.tribe, hut), "demolition accepted")
	check(hut.health > 0, "a built building is NOT scrapped instantly")
	check(hut.demolishing, "it is flagged for demolition")
	# Without any worker nothing happens at all, however long it ticks.
	var progress_before: float = hut.build_progress
	for i in range(200):
		w.building_manager.tick(TICK)
	check(is_equal_approx(hut.build_progress, progress_before),
		"no worker -> no demolition progress")
	check(hut.health > 0, "still standing")

	var crew: Array[Brave] = _demolishers(w, hut, 2)
	var ticks: int = _run_until_gone(w, hut, crew)
	check(ticks < MAX_TICKS, "workers tear it down")
	check(hut.health <= 0, "the building is gone")
	_free_world(w)


func test_demolish_refund_is_75_percent() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.building_manager.place(HUT_SCENE, w.tribe, Vector2i(60, 60), 0, true) as Hut
	var expected: int = int(floor(float(Hut.WOOD_COST) * Balance.DEMOLISH_REFUND_BUILT))
	check(hut.demolish_refund_total() == expected,
		"a finished building refunds 75 %% of its wood cost (%d)" % expected)

	w.commands.demolish_building(w.tribe, hut)
	var crew: Array[Brave] = _demolishers(w, hut, 3)
	_run_until_gone(w, hut, crew)
	check(_total_pile_wood(w) == expected,
		"exactly the 75 %% refund ends up in piles")
	_free_world(w)


func test_demolish_pays_refund_progressively() -> void:
	var w: Dictionary = _make_world()
	# The big camp gives the refund enough granularity to observe portions.
	var camp: Building = w.building_manager.place(
		CAMP_SCENE, w.tribe, Vector2i(58, 58), 0, true)
	var total: int = camp.demolish_refund_total()
	check(total >= 2, "the camp's refund is big enough for portions")

	w.commands.demolish_building(w.tribe, camp)
	var crew: Array[Brave] = _demolishers(w, camp, 1)
	var saw_partial: bool = false
	var ticks: int = 0
	while camp.health > 0 and ticks < MAX_TICKS:
		w.building_manager.tick(TICK)
		for b in crew:
			if is_instance_valid(b):
				b.tick(TICK)
		var paid: int = _total_pile_wood(w)
		if paid > 0 and paid < total:
			saw_partial = true
		ticks += 1
	check(saw_partial, "wood came back in portions, not only at the end")
	check(_total_pile_wood(w) == total, "the full refund arrived by the end")
	_free_world(w)


## Load-bearing guard: without it the site absorbs the piles it just paid out
## every 0.5 s and the refund never reaches the player.
func test_demolishing_site_does_not_reabsorb_its_refund() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	hut.wood_delivered = Hut.WOOD_COST
	hut.foundation_done = true
	hut._flatten_remaining.clear()
	hut.add_build_progress(0.5)
	check(hut.has_build_stage(), "the site reached a build stage")
	var expected: int = hut.demolish_refund_total()

	w.commands.demolish_building(w.tribe, hut)
	var crew: Array[Brave] = _demolishers(w, hut, 2)
	_run_until_gone(w, hut, crew)
	check(_total_pile_wood(w) == expected,
		"the refund stays in the piles (never re-absorbed)")
	check(hut.wood_delivered == Hut.WOOD_COST,
		"the site never took wood back in during the demolition")
	_free_world(w)


## A worker that is mid-CONSTRUCT when the demolition starts must not keep
## building against it (otherwise the bar bounces and the teardown never ends).
func test_demolishing_site_does_not_rebuild_itself() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	hut.wood_delivered = Hut.WOOD_COST
	hut.foundation_done = true
	hut._flatten_remaining.clear()
	hut.add_build_progress(0.4)

	var builder: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, hut.delivery_point()) as Brave
	builder.order_build(hut)
	# Let it settle into the CONSTRUCT sub-task.
	for i in range(40):
		w.building_manager.tick(TICK)
		builder.tick(TICK)
	check(builder.task == Brave.Task.CONSTRUCT, "the worker is hammering")
	var peak: float = hut.build_progress

	w.commands.demolish_building(w.tribe, hut)
	check(builder.task != Brave.Task.CONSTRUCT,
		"the demolition pulled the worker out of CONSTRUCT")
	for i in range(40):
		w.building_manager.tick(TICK)
		builder.tick(TICK)
	check(hut.build_progress <= peak + 0.0001,
		"build progress never grows again during a demolition")
	check(builder.task == Brave.Task.DEMOLISH, "it switched over to tearing down")
	_free_world(w)


func test_demolishing_building_is_unusable_and_ejects_occupants() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.building_manager.place(HUT_SCENE, w.tribe, Vector2i(60, 60), 0, true) as Hut
	var crew_member: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 0, hut.center_world())
	check(hut.admit_crew(crew_member), "hut manned before the demolition")
	check(hut.crew_count() == 1, "one crew member inside")
	check(hut.housing_capacity() > 0, "a usable hut houses population")

	w.commands.demolish_building(w.tribe, hut)
	check(not hut.is_usable(), "a building being torn down is unusable")
	check(hut.crew_count() == 0, "the crew was thrown out")
	check(hut.housing_capacity() == 0, "it houses nobody any more")
	check(crew_member.state != Unit.State.DEAD, "the crew survives the eject")
	_free_world(w)


func test_wood_stalled_site_still_gets_demolishers() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	hut.wood_delivered = Hut.WOOD_COST
	hut.foundation_done = true
	hut._flatten_remaining.clear()
	hut.add_build_progress(0.5)
	hut.mark_wood_stalled()
	check(hut.wood_stalled, "the site is stalled for wood")

	w.commands.demolish_building(w.tribe, hut)
	check(not hut.wood_stalled, "the demolition clears the wood stall")
	# The recruiter must draft an idle brave nearby (it skips stalled sites).
	var idle: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, hut.delivery_point() + Vector3(2.0, 0.0, 2.0)) as Brave
	for i in range(40):
		w.building_manager.tick(TICK)
		idle.tick(TICK)
	check(idle.job == hut, "the recruiter drafted the idle brave")
	_free_world(w)


func test_recruiter_drafts_braves_for_demolition() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.building_manager.place(HUT_SCENE, w.tribe, Vector2i(60, 60), 0, true) as Hut
	w.commands.demolish_building(w.tribe, hut)
	var idle: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, hut.delivery_point() + Vector3(2.0, 0.0, 2.0)) as Brave
	check(idle.state == Unit.State.IDLE, "the brave starts idle")
	for i in range(40):
		w.building_manager.tick(TICK)
		idle.tick(TICK)
	check(idle.job == hut, "an idle brave was drafted onto the finished building")
	check(idle.state == Unit.State.BUILD, "on the job system")
	_free_world(w)


# --- Refusals ----------------------------------------------------------------

func test_demolish_rejects_foreign_building() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.building_manager.place(HUT_SCENE, w.enemy, Vector2i(60, 60), 0, true) as Hut
	check(not w.commands.demolish_building(w.tribe, hut),
		"a tribe cannot scrap an enemy building")
	check(not hut.demolishing and hut.health > 0, "the enemy hut is untouched")
	_free_world(w)


func test_demolish_rejects_reincarnation_site() -> void:
	var w: Dictionary = _make_world()
	var site: Building = w.building_manager.place(
		SITE_SCENE, w.tribe, Vector2i(60, 60), 0, true)
	check(not w.commands.demolish_building(w.tribe, site),
		"the reincarnation circle cannot be scrapped")
	check(not site.demolishing and site.health > 0, "the circle is untouched")
	_free_world(w)


func test_demolish_is_final_and_not_ordered_twice() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.building_manager.place(HUT_SCENE, w.tribe, Vector2i(60, 60), 0, true) as Hut
	check(w.commands.demolish_building(w.tribe, hut), "first order accepted")
	check(not w.commands.demolish_building(w.tribe, hut),
		"a second Entf does not re-trigger (no cancel, no restart)")
	check(hut.demolishing, "still being torn down")
	_free_world(w)


func test_eliminated_tribe_cannot_demolish() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.building_manager.place(HUT_SCENE, w.tribe, Vector2i(60, 60), 0, true) as Hut
	w.tribe.eliminated = true
	check(not w.commands.demolish_building(w.tribe, hut),
		"an eliminated tribe issues no demolition order")
	_free_world(w)
