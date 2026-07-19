extends TestBase

## Headless tests for the workshop wood economy (Spieltest 4):
## - stock_target() is one product's worth (bunker enough for ONE siege engine).
## - an OCCUPIED workshop's entrance stock is protected from a neighbour
##   workshop's absorb; only an unoccupied owner's wood may be relocated.
## - the generalised hover crew-pip display (all crew buildings except the
##   watchtower report a capacity).

const TICK: float = 0.1

const WORKSHOP_SCENE: PackedScene = preload("res://scenes/buildings/workshop.tscn")
const RAM_WORKSHOP_SCENE: PackedScene = preload("res://scenes/buildings/fire_ram_workshop.tscn")
const WHARF_SCENE: PackedScene = preload("res://scenes/buildings/airship_wharf.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const FORESTER_SCENE: PackedScene = preload("res://scenes/buildings/forester.tscn")
const WARRIOR_CAMP_SCENE: PackedScene = preload("res://scenes/buildings/warrior_camp.tscn")
const TOWER_SCENE: PackedScene = preload("res://scenes/buildings/watchtower.tscn")
const DEPOT_SCENE: PackedScene = preload("res://scenes/buildings/wood_depot.tscn")
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


## Gives the workshop an occupant (holds a slot -> has_occupants() true) without
## the full walk-in dance.
func _occupy(w: Dictionary, ws: Workshop) -> Brave:
	var b: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, ws.tribe_id, ws.edge_spawn_position()) as Brave
	ws.reserve_slot(b)
	b.job = ws
	return b


# --- Stock target = one product ----------------------------------------------

func test_stock_target_is_one_product() -> void:
	var ws: Workshop = WORKSHOP_SCENE.instantiate() as Workshop
	check(ws.stock_target() == ws.product_wood(),
		"the workshop bunkers exactly one product's worth of wood")
	check(ws.product_wood() == Balance.WORKSHOP_CATAPULT_WOOD,
		"a catapult costs its balance wood")
	var rws: Workshop = RAM_WORKSHOP_SCENE.instantiate() as Workshop
	check(rws.stock_target() == rws.product_wood(),
		"the fire-ram workshop bunkers one ram's worth")
	var aw: Workshop = WHARF_SCENE.instantiate() as Workshop
	check(aw.stock_target() == aw.product_wood(),
		"the wharf bunkers one airship's worth")
	ws.free()
	rws.free()
	aw.free()


# --- Neighbour wood protection ----------------------------------------------

func test_occupied_workshop_wood_is_protected_from_neighbour() -> void:
	var w: Dictionary = _make_world()
	var a: Workshop = w.bm.place(WORKSHOP_SCENE, w.tribe0, Vector2i(30, 30), 0, true) as Workshop
	var b: Workshop = w.bm.place(WORKSHOP_SCENE, w.tribe0, Vector2i(38, 30), 0, true) as Workshop
	check(a != null and b != null, "both workshops placed")
	# A pile nearer A but still inside B's absorb radius (the overlap zone).
	var pile_pos: Vector3 = a.delivery_point().lerp(b.delivery_point(), 0.4)
	w.wpm.deposit(pile_pos, 6)
	# Geometry sanity: with A idle, B can see the shared pile at all.
	var _occ_b: Brave = _occupy(w, b)
	check(b.stock_wood() > 0, "B sees the shared pile while A is unoccupied (in radius)")
	# Occupy A too: now the pile is A's protected stock — B must not count it.
	var occ_a: Brave = _occupy(w, a)
	check(a.stock_wood() > 0, "A counts its own (nearer) stock")
	check(b.stock_wood() == 0, "an occupied A's stock is protected from neighbour B")
	# Vacate A: its wood is now relocatable, so B may absorb it again.
	a.release_worker(occ_a)
	check(b.stock_wood() > 0, "an UNOCCUPIED A's stock is free for B to take")
	_free_world(w)


# --- Generalised crew-pip display -------------------------------------------

func test_crew_display_capacities() -> void:
	var hut: Hut = HUT_SCENE.instantiate() as Hut
	check(hut.crew_display_capacity() == Hut.CREW_CAPACITY,
		"the hut shows its manning as pips")
	var ws: Workshop = WORKSHOP_SCENE.instantiate() as Workshop
	check(ws.crew_display_capacity() == ws.worker_slots(),
		"the workshop shows its worker slots as pips")
	var f: Forester = FORESTER_SCENE.instantiate() as Forester
	check(f.crew_display_capacity() == Forester.WORKER_SLOTS,
		"the forester shows its worker slots as pips")
	var camp: TrainingBuilding = WARRIOR_CAMP_SCENE.instantiate() as TrainingBuilding
	check(camp.crew_display_capacity() == 1,
		"a training building shows the single trainee bay")
	var tower: Watchtower = TOWER_SCENE.instantiate() as Watchtower
	check(tower.crew_display_capacity() == 0,
		"the watchtower opts OUT of crew pips (user request)")
	var depot: WoodDepot = DEPOT_SCENE.instantiate() as WoodDepot
	check(depot.crew_display_capacity() == 0,
		"the wood depot has no crew and shows no pips")
	for n in [hut, ws, f, camp, tower, depot]:
		n.free()
