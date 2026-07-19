extends TestBase

## Headless tests for the Holzstation (WoodDepot): storage as REAL wood piles
## (capacity, store/take, pile registry sync with tornado/fire/consumers),
## the single destruction stage, the destroyed-depot pile handover and the
## brave haul/relay delivery orders.

const TICK: float = 0.05
const MAX_TICKS: int = 20000

const DEPOT_SCENE: PackedScene = preload("res://scenes/buildings/wood_depot.tscn")
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
	return {
		"td": td, "nav": nav, "tribe": tribe,
		"unit_manager": um, "building_manager": bm,
		"tree_manager": tm, "wood_pile_manager": wpm,
	}


func _free_world(w: Dictionary) -> void:
	w.tree_manager.free()
	w.wood_pile_manager.free()
	w.building_manager.free()
	w.unit_manager.free()


func _depot(w: Dictionary, cell: Vector2i) -> WoodDepot:
	return w.building_manager.place(DEPOT_SCENE, w.tribe, cell, 0, true) as WoodDepot


# --- Basics ---------------------------------------------------------------------

func test_cost_footprint_and_single_stage() -> void:
	var w: Dictionary = _make_world()
	check(WoodDepot.WOOD_COST == 1, "depot costs 1 wood")
	var depot: WoodDepot = _depot(w, Vector2i(60, 60))
	check(depot != null and depot.footprint == Vector2i(1, 1), "1x1 footprint")
	check(depot.is_usable(), "finished depot is usable")
	# Single destruction stage: heavy damage never disables it...
	depot.health = 1
	check(depot.destruction_stage() == 0, "damaged depot stays at stage 0")
	check(depot.is_usable(), "damaged depot stays fully usable")
	# ...only health 0 destroys it.
	depot.health = 0
	check(depot.destruction_stage() == 4, "dead depot is stage 4")
	_free_world(w)


# --- Storage as real piles --------------------------------------------------------

func test_store_take_and_capacity() -> void:
	var w: Dictionary = _make_world()
	var wpm: WoodPileManager = w.wood_pile_manager
	var depot: WoodDepot = _depot(w, Vector2i(60, 60))
	check(depot.store_wood(7) == 7, "7 wood fit into the empty rack")
	check(depot.stored_wood() == 7, "stored amount is derived from the piles")
	check(depot.store_wood(WoodDepot.CAPACITY) == WoodDepot.CAPACITY - 7,
		"overflow is rejected at the capacity")
	check(depot.stored_wood() == WoodDepot.CAPACITY, "rack is full")
	check(depot.storage_left() == 0, "no space left")
	check(wpm.total_wood() == WoodDepot.CAPACITY, "stock are real registered piles")
	# The stock lies inside the consumer absorb radius around the entrance.
	check(wpm.wood_in_radius(depot.delivery_point(), Building.ABSORB_RADIUS)
		== WoodDepot.CAPACITY, "workshops/sites within 5 m see the stock")
	check(depot.take_stored(8) == 8, "take_stored hands out wood")
	check(depot.stored_wood() == WoodDepot.CAPACITY - 8, "stock shrank accordingly")
	# Stock piles must not steal right-clicks from the depot's own click body.
	for pile in wpm.piles_in_radius(depot.center_world(), 1.0):
		check(not pile.clickable, "stock piles are not click targets")
	_free_world(w)


func test_consumers_and_tornado_stay_in_sync() -> void:
	var w: Dictionary = _make_world()
	var wpm: WoodPileManager = w.wood_pile_manager
	var depot: WoodDepot = _depot(w, Vector2i(60, 60))
	depot.store_wood(12)
	# A construction site / workshop absorbing via take_from_radius drains the
	# rack directly — the derived count follows.
	var taken: int = wpm.take_from_radius(depot.delivery_point(), Building.ABSORB_RADIUS, 5)
	check(taken == 5, "radius consumers can take stock wood")
	check(depot.stored_wood() == 7, "stored count follows external takes")
	# The tornado removes whole piles (scatter) — the count follows too.
	var piles: Array[WoodPile] = wpm.piles_in_radius(depot.center_world(), 1.0)
	check(not piles.is_empty(), "stock piles found at the rack")
	var removed: int = piles[0].amount
	wpm.remove_pile(piles[0])
	check(depot.stored_wood() == 7 - removed, "stored count follows pile removal")
	_free_world(w)


func test_stock_burns_like_normal_piles() -> void:
	var w: Dictionary = _make_world()
	var wpm: WoodPileManager = w.wood_pile_manager
	var depot: WoodDepot = _depot(w, Vector2i(60, 60))
	depot.store_wood(10)
	var lit: int = wpm.ignite_in_radius(depot.center_world(), 1.5)
	check(lit > 0, "fire ignites the stock piles")
	wpm.tick(WoodPile.BURN_TIME + 0.5)
	check(depot.stored_wood() == 0, "burnt stock is gone")
	_free_world(w)


func test_adopts_foreign_piles_on_the_rack() -> void:
	var w: Dictionary = _make_world()
	var wpm: WoodPileManager = w.wood_pile_manager
	var depot: WoodDepot = _depot(w, Vector2i(60, 60))
	depot.store_wood(3)
	wpm.create_pile_at(depot.center_world(), true).set_amount(4)
	depot.tick(WoodDepot.ADOPT_INTERVAL + 0.1)
	check(depot.stored_wood() == 7, "a stray pile on the rack is folded into the stock")
	check(wpm.total_wood() == 7, "no wood was duplicated or lost")
	_free_world(w)


func test_destroyed_depot_leaves_clickable_piles() -> void:
	var w: Dictionary = _make_world()
	var wpm: WoodPileManager = w.wood_pile_manager
	var depot: WoodDepot = _depot(w, Vector2i(60, 60))
	depot.store_wood(9)
	depot.destroy()
	check(wpm.total_wood() == 9, "the stock keeps lying around after destruction")
	for pile in wpm.piles_in_radius(w.nav.cell_to_world(Vector2i(60, 60)), 1.5):
		check(pile.clickable, "left-over piles are right-click targets again")
	_free_world(w)


# --- Brave haul & relay orders ------------------------------------------------------

func test_depot_haul_moves_stock_to_the_other_depot() -> void:
	var w: Dictionary = _make_world()
	var source: WoodDepot = _depot(w, Vector2i(58, 60))
	var target: WoodDepot = _depot(w, Vector2i(66, 60))
	source.store_wood(7)
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(58, 63))) as Brave
	w.unit_manager.tick(TICK)
	brave.order_depot_haul(source)
	check(brave.state == Unit.State.GATHER, "haul order starts the gather loop")
	var ticks: int = 0
	while target.stored_wood() < 7 and ticks < MAX_TICKS:
		w.building_manager.tick(TICK)
		w.unit_manager.tick(TICK)
		brave.tick(TICK)
		ticks += 1
	check(target.stored_wood() == 7, "the whole stock arrived at the other depot")
	check(source.stored_wood() == 0, "the source depot ran dry")
	_free_world(w)


func test_depot_haul_without_second_depot_is_a_plain_move() -> void:
	var w: Dictionary = _make_world()
	var depot: WoodDepot = _depot(w, Vector2i(60, 60))
	depot.store_wood(5)
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(55, 60))) as Brave
	w.unit_manager.tick(TICK)
	brave.order_depot_haul(depot)
	check(brave.state == Unit.State.MOVE, "no second depot: the brave just walks there")
	check(depot.stored_wood() == 5, "the stock stays untouched")
	_free_world(w)


func test_pickup_relay_delivers_into_the_depot() -> void:
	var w: Dictionary = _make_world()
	var wpm: WoodPileManager = w.wood_pile_manager
	# A pile right at a friendly hut counts as "already delivered": a manual
	# pickup relays it to the (farther) wood depot instead.
	var hut: Hut = w.building_manager.place(HUT_SCENE, w.tribe, Vector2i(30, 30), 0, true) as Hut
	var depot: WoodDepot = _depot(w, Vector2i(44, 31))
	var pile: WoodPile = wpm.create_pile_at(hut.entrance_world() + Vector3(1.0, 0, 0))
	pile.set_amount(3)
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(36, 33))) as Brave
	w.unit_manager.tick(TICK)
	brave.order_pickup(pile)
	var ticks: int = 0
	while depot.stored_wood() < 3 and ticks < MAX_TICKS:
		w.building_manager.tick(TICK)
		w.unit_manager.tick(TICK)
		brave.tick(TICK)
		ticks += 1
	check(depot.stored_wood() == 3, "the relayed wood ends up in the depot rack")
	_free_world(w)
