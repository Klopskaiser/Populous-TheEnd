extends TestBase

## Headless tests for phase 10d: construction decay. A site that makes NO
## progress at all for Balance.CONSTRUCTION_STALL_TIMEOUT (2 min) falls apart
## again and hands its delivered wood back as piles — that clears unreachable
## plots and forgotten sites off the map. Any progress (a graded cell, delivered
## wood, build progress) resets the timer.

const TICK: float = 0.5
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
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(nav, bm, um, tm)
	return {
		"td": td, "nav": nav, "tribe": tribe,
		"unit_manager": um, "building_manager": bm,
		"tree_manager": tm, "wood_pile_manager": wpm, "commands": tc,
	}


func _free_world(w: Dictionary) -> void:
	w.commands.free()
	w.tree_manager.free()
	w.wood_pile_manager.free()
	w.building_manager.free()
	w.unit_manager.free()


## Ticks the buildings for `seconds` of game time (no workers involved).
func _idle_for(w: Dictionary, seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds:
		w.building_manager.tick(TICK)
		elapsed += TICK


func test_stalled_site_decays_after_timeout() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	# Just short of the timeout it is still there ...
	_idle_for(w, Balance.CONSTRUCTION_STALL_TIMEOUT - 5.0)
	check(hut.health > 0, "a stalled site survives until the timeout")
	# ... and past it, it is gone.
	_idle_for(w, 10.0)
	check(hut.health <= 0, "no progress for 2 min -> the site decays")
	_free_world(w)


func test_working_site_never_decays() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	# Wood + a worker: real progress every tick, so the timer keeps resetting.
	w.wood_pile_manager.deposit(hut.delivery_point(), Hut.WOOD_COST)
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, hut.delivery_point()) as Brave
	brave.order_build(hut)
	var elapsed: float = 0.0
	while elapsed < Balance.CONSTRUCTION_STALL_TIMEOUT * 1.5 and hut.under_construction:
		w.building_manager.tick(TICK)
		brave.tick(TICK)
		elapsed += TICK
	check(hut.health > 0, "a site with a working crew never decays")
	check(not hut.under_construction, "it finished instead")
	_free_world(w)


func test_flatten_progress_resets_the_decay_timer() -> void:
	var w: Dictionary = _make_world()
	# Bumpy plot so there is something to grade.
	w.td.raise_area(Vector2(62.0, 62.0), 3.0, 1.2)
	w.nav.update_region(Rect2i(56, 56, 14, 14))
	var hut: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	check(hut.needs_flatten(), "the bumpy plot needs grading")

	_idle_for(w, Balance.CONSTRUCTION_STALL_TIMEOUT - 10.0)
	check(hut.health > 0, "still standing shortly before the timeout")
	# One graded cell = progress -> the clock starts over.
	var cell: Vector2i = hut.claim_flatten_cell(hut.delivery_point())
	check(cell.x >= 0, "a flatten cell could be claimed")
	while hut.flatten_cell_pending(cell):
		hut.work_flatten(cell, 1.0)
	_idle_for(w, 20.0)
	check(hut.health > 0, "grading a cell reset the decay timer")
	_free_world(w)


func test_wood_delivery_resets_the_decay_timer() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	_idle_for(w, Balance.CONSTRUCTION_STALL_TIMEOUT - 10.0)
	check(hut.health > 0, "still standing shortly before the timeout")
	# Wood arrives at the entrance and gets absorbed -> progress.
	w.wood_pile_manager.deposit(hut.delivery_point(), 3)
	_idle_for(w, 2.0)
	check(hut.wood_delivered >= 3, "the wood was absorbed")
	_idle_for(w, 20.0)
	check(hut.health > 0, "delivered wood reset the decay timer")
	_free_world(w)


func test_decayed_site_refunds_delivered_wood_as_piles() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	hut.wood_delivered = 5
	# Absorption would take the piles back in, so keep the plot pile-free until
	# the decay fires: the timer runs on the unchanged signature either way.
	_idle_for(w, Balance.CONSTRUCTION_STALL_TIMEOUT + 5.0)
	check(hut.health <= 0, "the site decayed")
	check(w.wood_pile_manager.total_wood() == 5,
		"the delivered wood lies at the plot afterwards")
	_free_world(w)


func test_decayed_site_frees_its_plot() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	var cell: Vector2i = hut.cell + Vector2i(1, 1)
	check(w.nav.is_cell_blocked_by_building(cell), "the plot blocks navigation")
	_idle_for(w, Balance.CONSTRUCTION_STALL_TIMEOUT + 5.0)
	check(hut.health <= 0, "the site decayed")
	check(not w.nav.is_cell_blocked_by_building(cell), "the plot is free again")
	_free_world(w)
