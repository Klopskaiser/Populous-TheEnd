extends TestBase

## Headless tests for phase 6: building destruction stages (0-4), usability
## gating (no production/capacity from stage 1), the sinking removal at stage
## 4 (footprint free again) and the worker repair with proportional wood cost
## (floor(damage * wood_cost)).

const TICK: float = 0.1
const MAX_TICKS: int = 800

const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const WARRIOR_CAMP_SCENE: PackedScene = preload("res://scenes/buildings/warrior_camp.tscn")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


func _make_world() -> Dictionary:
	var td: TerrainData = _flat_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var tribe0: Tribe = Tribe.new(0)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe0] as Array[Tribe], null, wpm)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um, wpm)
	return {"td": td, "nav": nav, "tribe0": tribe0, "unit_manager": um,
		"bm": bm, "wpm": wpm}


func _free_world(w: Dictionary) -> void:
	w.bm.free()
	w.unit_manager.free()
	w.wpm.free()


## Ticks units + building manager (+ unit manager) together.
func _run(w: Dictionary, units: Array, done: Callable) -> int:
	for i in range(MAX_TICKS):
		if done.call():
			return i
		for u in units:
			if is_instance_valid(u) and u.state != Unit.State.DEAD:
				u.tick(TICK)
		w.unit_manager.tick(TICK)
		w.bm.tick(TICK)
	return MAX_TICKS


# --- Stages & usability -----------------------------------------------------------

func test_destruction_stage_thresholds() -> void:
	var w: Dictionary = _make_world()
	var hut: Building = w.bm.place(HUT_SCENE, w.tribe0, Vector2i(30, 30), 0, true)
	check(hut.destruction_stage() == 0 and hut.is_usable(), "intact hut = stage 0, usable")
	hut.take_damage(89)   # 29.7% damage
	check(hut.destruction_stage() == 0 and hut.is_usable(), "below 30% still stage 0")
	hut.take_damage(1)    # 30%
	check(hut.destruction_stage() == 1, "30% damage = stage 1")
	check(not hut.is_usable(), "stage 1 is unusable")
	hut.take_damage(90)   # 60%
	check(hut.destruction_stage() == 2, "60% damage = stage 2")
	hut.take_damage(90)   # 90%
	check(hut.destruction_stage() == 3, "90% damage = stage 3")
	check(not w.nav.is_cell_walkable(Vector2i(31, 31)), "footprint blocked while standing")
	hut.take_damage(30)   # 100%
	check(hut.destruction_stage() == 4, "100% = stage 4 (destroyed)")
	check(hut.health == 0, "destroyed at 0 HP")
	check(hut not in w.bm.buildings, "deregistered from the building manager")
	check(w.tribe0.buildings.is_empty(), "deregistered from the tribe")
	check(w.nav.is_cell_walkable(Vector2i(31, 31)), "footprint walkable/buildable again")
	_free_world(w)


func test_apply_destruction_stages_deals_stage_damage() -> void:
	var w: Dictionary = _make_world()
	var hut: Building = w.bm.place(HUT_SCENE, w.tribe0, Vector2i(30, 30), 0, true)
	hut.apply_destruction_stages(2)   # lightning: +2 stages = 60% of max HP
	check(hut.health == 120, "+2 stages = 60% max-HP damage (300 -> 120)")
	check(hut.destruction_stage() == 2, "building sits at stage 2")
	hut.apply_destruction_stages(1)
	check(hut.destruction_stage() == 3, "another stage on top -> stage 3")
	hut.apply_destruction_stages(1)
	check(hut.destruction_stage() == 4 and hut.health == 0, "fourth stage destroys")
	_free_world(w)


func test_damaged_hut_stops_production_and_capacity() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.bm.place(HUT_SCENE, w.tribe0, Vector2i(30, 30), 0, true) as Hut
	check(hut.housing_capacity() == Hut.CAPACITY, "intact hut houses Hut.CAPACITY")
	# A manned hut works toward a spawn (phase 7i: unmanned huts do nothing).
	for i in range(Hut.CREW_CAPACITY):
		var b: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, w.tribe0.id, hut.center_world())
		hut.admit_crew(b)
	w.bm.tick(3.0)
	check(hut.spawn_timer < Hut.SPAWN_INTERVAL, "intact manned hut works toward a spawn")
	hut.take_damage(90)   # stage 1 -> unusable, crew ejected
	check(hut.housing_capacity() == 0, "damaged hut houses nobody")
	check_near(hut.production_progress(), -1.0, "no production bar while damaged")
	var frozen: float = hut.spawn_timer
	var pop_after_damage: int = w.tribe0.population()
	w.bm.tick(5.0)
	check_near(hut.spawn_timer, frozen, "spawn timer frozen while damaged")
	check(w.tribe0.population() == pop_after_damage, "no new braves from a damaged hut")
	_free_world(w)


func test_damaged_camp_releases_trainee_and_queue() -> void:
	var w: Dictionary = _make_world()
	var camp: TrainingBuilding = w.bm.place(WARRIOR_CAMP_SCENE, w.tribe0, Vector2i(40, 40), 0, true)
	var b1: Brave = w.unit_manager.spawn_unit(BRAVE_SCENE, 0, Vector3(38, 0, 38))
	var b2: Brave = w.unit_manager.spawn_unit(BRAVE_SCENE, 0, Vector3(37, 0, 38))
	b1.order_train(camp)
	b2.order_train(camp)
	var ticks: int = _run(w, [b1, b2], func() -> bool: return camp.trainee != null)
	check(ticks < MAX_TICKS, "one brave was admitted for training")
	var trainee: Brave = camp.trainee
	var pop_before: int = w.tribe0.population()
	camp.apply_destruction_stages(1)
	check(camp.destruction_stage() >= 1, "camp damaged into stage >= 1")
	check(camp.trainee == null, "trainee bay cleared")
	check(is_instance_valid(trainee) and trainee.state != Unit.State.TRAIN,
		"trainee released instead of killed")
	check(trainee in w.unit_manager.units, "ejected trainee is back in the world")
	check(camp.incoming.is_empty(), "queue released")
	check(b2.state != Unit.State.TRAIN, "queued brave released too")
	check(w.tribe0.population() == pop_before, "population unchanged by the ejection")
	# Damaged camp rejects new enrolments.
	b2.order_train(camp)
	check(b2.state != Unit.State.TRAIN, "damaged camp rejects training orders")
	_free_world(w)


# --- Repair ---------------------------------------------------------------------------

func test_repair_stalls_without_wood() -> void:
	var w: Dictionary = _make_world()
	var hut: Building = w.bm.place(HUT_SCENE, w.tribe0, Vector2i(30, 30), 0, true)
	hut.take_damage(270)   # 90% damage, health 30
	check(hut.repair_wood_missing() == 10,
		"90% damage on a 12-wood hut owes floor(10.8) = 10 wood")
	var brave: Brave = w.unit_manager.spawn_unit(BRAVE_SCENE, 0, Vector3(28, 0, 28))
	brave.order_repair(hut)
	_run(w, [brave], func() -> bool: return brave.state == Unit.State.IDLE)
	check(hut.health == 30, "no repair progress without wood")
	check(hut.wood_stalled, "site stalls when no wood source exists")
	check(brave.state == Unit.State.IDLE, "worker gives up instead of hammering")
	_free_world(w)


func test_repair_consumes_floored_wood_and_restores_usability() -> void:
	var w: Dictionary = _make_world()
	var hut: Building = w.bm.place(HUT_SCENE, w.tribe0, Vector2i(30, 30), 0, true)
	hut.take_damage(270)   # 90% damage -> owes 10 wood
	# Deliver exactly 10 wood as piles inside the absorb radius of the entrance.
	var entrance: Vector3 = hut.entrance_world()
	w.wpm.deposit(entrance, 5)
	w.wpm.deposit(entrance + Vector3(2.8, 0, 0), 5)
	var absorb_ticks: int = _run(w, [], func() -> bool: return hut.repair_wood >= 10)
	check(absorb_ticks < MAX_TICKS, "delivered piles absorbed into the repair buffer")
	check(hut.repair_wood_missing() == 0, "all owed wood delivered")
	var brave: Brave = w.unit_manager.spawn_unit(BRAVE_SCENE, 0, Vector3(28, 0, 28))
	brave.order_repair(hut)
	var ticks: int = _run(w, [brave], func() -> bool: return hut.health >= hut.max_health)
	check(ticks < MAX_TICKS, "worker repairs the hut to full HP")
	check(hut.health == hut.max_health, "fully repaired")
	check(hut.repair_wood == 0, "exactly the floored wood amount consumed")
	check(hut.destruction_stage() == 0 and hut.is_usable(), "usable again after repair")
	check(hut.housing_capacity() == Hut.CAPACITY, "capacity restored")
	_run(w, [brave], func() -> bool: return brave.state == Unit.State.IDLE)
	check(brave.state == Unit.State.IDLE, "worker released after full repair")
	_free_world(w)


func test_partial_repair_lowers_stage() -> void:
	var w: Dictionary = _make_world()
	var hut: Building = w.bm.place(HUT_SCENE, w.tribe0, Vector2i(30, 30), 0, true)
	hut.take_damage(200)   # health 100 -> 66.7% damage, stage 2
	check(hut.destruction_stage() == 2, "start at stage 2")
	hut.repair_wood = 99   # plenty of wood delivered
	check(hut.repair(50.0), "repair works with wood in the buffer")
	check(hut.destruction_stage() == 1, "stage drops as HP returns (150/300 = 50%)")
	check(hut.repair(200.0), "repair up to full")
	check(hut.health == hut.max_health, "clamped at max HP")
	_free_world(w)
