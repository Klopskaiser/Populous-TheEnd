extends TestBase

## Bug-Backlog #2: construction sites must be destroyable by units. A site's
## HP scale with the delivered-wood fraction (wood_delivered / wood_cost),
## capped at 3/4 of the finished building's HP (3 destruction stages — a site
## never has the full 4). Melee raiders demolish it like a finished building;
## at 0 HP the site is destroyed and the plot is free again.

const TICK: float = 0.1
const MAX_TICKS: int = 1500

const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")


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
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe0, tribe1] as Array[Tribe], null, wpm)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um, wpm)
	um.building_manager = bm
	return {"td": td, "nav": nav, "tribe0": tribe0, "tribe1": tribe1,
		"unit_manager": um, "bm": bm, "wpm": wpm}


func _free_world(w: Dictionary) -> void:
	w.bm.free()
	w.unit_manager.free()
	w.wpm.free()


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


## Unfinished hut (construction site) of the enemy tribe.
func _site(w: Dictionary) -> Building:
	return w.bm.place(HUT_SCENE, w.tribe1, Vector2i(40, 40), 0, false)


## Delivers `amount` wood to the site via piles at the delivery point (absorbed
## on the construction tick, like worker deliveries).
func _deliver_wood(w: Dictionary, site: Building, amount: int) -> void:
	w.wpm.deposit(site.delivery_point(), amount)
	for i in range(40):
		site.tick(0.5)
		if site.wood_delivered >= amount:
			break


# --- Site HP model -------------------------------------------------------------

func test_fresh_site_has_minimal_hp() -> void:
	var w: Dictionary = _make_world()
	var site: Building = _site(w)
	check(site.under_construction, "site starts under construction")
	check(site.health == 1, "a site with no wood built in has minimal HP (got %d)" % site.health)
	_free_world(w)


func test_site_hp_scales_with_delivered_wood() -> void:
	var w: Dictionary = _make_world()
	var site: Building = _site(w)
	_deliver_wood(w, site, 6)
	check(site.wood_delivered == 6, "6 of 12 wood delivered (got %d)" % site.wood_delivered)
	check(site.health == 150, "half the wood -> half the full HP (got %d)" % site.health)
	_deliver_wood(w, site, 6)
	check(site.wood_delivered == 12, "all wood delivered")
	check(site.health == 225, "site HP capped at 3/4 of the full HP (got %d)" % site.health)
	_free_world(w)


func test_finish_restores_full_hp_minus_damage() -> void:
	var w: Dictionary = _make_world()
	var site: Building = _site(w)
	_deliver_wood(w, site, 12)
	site.take_damage(100)
	check(site.health == 125, "damaged site at 225 - 100 HP (got %d)" % site.health)
	site.finish_construction()
	check(not site.under_construction, "construction finished")
	check(site.health == site.max_health - 100,
		"damage carries over into the finished building (got %d)" % site.health)
	_free_world(w)


func test_prebuilt_building_keeps_full_hp() -> void:
	var w: Dictionary = _make_world()
	var hut: Building = w.bm.place(HUT_SCENE, w.tribe1, Vector2i(60, 60), 0, true)
	check(hut.health == hut.max_health,
		"pre-built building has full HP (got %d)" % hut.health)
	_free_world(w)


# --- Units destroy construction sites -------------------------------------------

func test_melee_raiders_demolish_site() -> void:
	var w: Dictionary = _make_world()
	var site: Building = _site(w)
	_deliver_wood(w, site, 6)   # 150 HP — demolition must tick it down
	for i in range(3):
		site.admit_raider(w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, Vector3(41 + i, 0, 41)))
	check(site.raiders.size() == 3, "3 raiders inside the site")
	var hp: int = site.health
	site.tick(1.0)
	check(site.health < hp, "raiders damage the construction site (still %d HP)" % site.health)
	var razed: int = _run(w, [], func() -> bool: return site.health <= 0)
	check(razed < MAX_TICKS, "raiders raze the construction site")
	check(site not in w.bm.buildings, "razed site deregistered")
	check(w.nav.is_cell_walkable(Vector2i(41, 41)), "plot walkable/buildable again")
	_free_world(w)


func test_ordered_warriors_raze_site() -> void:
	var w: Dictionary = _make_world()
	var site: Building = _site(w)
	var squad: Array[Unit] = []
	for i in range(4):
		var wr: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, Vector3(35 + i, 0, 35))
		wr.order_attack_building(site)
		squad.append(wr)
	var razed: int = _run(w, squad, func() -> bool: return site.health <= 0)
	check(razed < MAX_TICKS, "ordered warriors destroy the construction site")
	_free_world(w)


func test_firewarrior_bombards_site() -> void:
	var w: Dictionary = _make_world()
	var site: Building = _site(w)
	_deliver_wood(w, site, 6)   # 150 HP
	var fw: Unit = w.unit_manager.spawn_unit(FIREWARRIOR_SCENE, 0, Vector3(35, 0, 35))
	fw.order_attack_building(site)
	var razed: int = _run(w, [fw], func() -> bool: return site.health <= 0)
	check(razed < MAX_TICKS, "firewarrior fire destroys the construction site")
	_free_world(w)
