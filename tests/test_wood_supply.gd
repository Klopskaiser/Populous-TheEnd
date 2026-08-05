extends TestBase

## Phase 10g Teil 4: gezielter Holznachschub (KI-intern) und das Holzregal an der
## Werkstatt. Nutzerreport: "Grundsaetzlich soll die KI das Holz besser verteilen.
## Holzstapel bauen in der Naehe von Werkstaetten und notfalls auch manuell Holz zu
## Baustellen und Werkstaetten schaffen mit Braves."
##
## Es gibt KEIN globales Holzlager — Holz existiert nur als physische WoodPiles.
## Arbeiter holen nur selbst (Stapel bis PILE_PREFER_RADIUS 24 m um die Baustelle,
## Baeume bis JOB_TREE_RADIUS 40 m); finden sie nichts, stallt die Baustelle und
## verfaellt nach CONSTRUCTION_STALL_TIMEOUT.

const TICK: float = 0.1
const MAX_TICKS: int = 900

const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const DEPOT_SCENE: PackedScene = preload("res://scenes/buildings/wood_depot.tscn")
const WORKSHOP_SCENE: PackedScene = preload("res://scenes/buildings/workshop.tscn")
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
	var tribes: Array[Tribe] = [Tribe.new(0), Tribe.new(1)]
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, tribes, tm, wpm)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um, wpm)
	um.building_manager = bm
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(nav, bm, um, tm)
	return {"td": td, "nav": nav, "tribe": tribes[1], "enemy": tribes[0],
		"unit_manager": um, "building_manager": bm, "tree_manager": tm,
		"wood_pile_manager": wpm, "commands": tc}


func _free_world(w: Dictionary) -> void:
	w.commands.free()
	w.tree_manager.free()
	w.wood_pile_manager.free()
	w.building_manager.free()
	w.unit_manager.free()


func _run(w: Dictionary, until: Callable) -> int:
	for i in range(MAX_TICKS):
		w.unit_manager.tick_units(TICK)
		w.unit_manager.tick(TICK)
		w.building_manager.tick(TICK)
		if until.call():
			return i
	return MAX_TICKS


# --- Der Befehl ---------------------------------------------------------------------

func test_supply_order_takes_only_braves() -> void:
	var w: Dictionary = _make_world()
	var site: Building = w.building_manager.place(HUT_SCENE, w.tribe, Vector2i(50, 50), 0, false)
	var depot: Building = w.building_manager.place(DEPOT_SCENE, w.tribe, Vector2i(40, 40), 0, true)
	(depot as WoodDepot).store_wood(10)
	var brave: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, Vector3(45, 5, 45))
	var warrior: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 1, Vector3(46, 5, 45))
	var n: int = w.commands.order_supply_wood([brave, warrior] as Array[Unit], site)
	check(n == 1, "nur der Brave nimmt den Auftrag an")
	check((brave as Brave).has_supply_job(), "und hat ihn wirklich")
	check(warrior.state != Unit.State.GATHER, "der Krieger wird nicht mitgeschickt")
	_free_world(w)


func test_supply_predicates_are_disjoint() -> void:
	# Ein Nachschubauftrag bezieht sein Holz aus einem Regal und setzt dabei
	# _haul_source. Ohne den _supply_target-Zusatz in has_depot_haul() haette
	# AIController._tick_forward_haul ihn als Pendel-Brave verbucht.
	var w: Dictionary = _make_world()
	var site: Building = w.building_manager.place(HUT_SCENE, w.tribe, Vector2i(50, 50), 0, false)
	var depot: Building = w.building_manager.place(DEPOT_SCENE, w.tribe, Vector2i(40, 40), 0, true)
	(depot as WoodDepot).store_wood(10)
	var brave: Brave = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, Vector3(45, 5, 45)) as Brave
	check(w.commands.order_supply_wood([brave] as Array[Unit], site) == 1, "Auftrag laeuft")
	check(brave.has_supply_job(), "Nachschub ja")
	check(not brave.has_depot_haul(), "Depot-Pendel NEIN - die Praedikate sind disjunkt")
	_free_world(w)


func test_supply_brave_sources_from_the_rack_and_funds_the_site() -> void:
	var w: Dictionary = _make_world()
	var site: Building = w.building_manager.place(HUT_SCENE, w.tribe, Vector2i(50, 50), 0, false)
	var depot: Building = w.building_manager.place(DEPOT_SCENE, w.tribe, Vector2i(44, 50), 0, true)
	(depot as WoodDepot).store_wood(20)
	var brave: Brave = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, Vector3(46, 5, 50)) as Brave
	check(w.commands.order_supply_wood([brave] as Array[Unit], site) == 1, "Auftrag laeuft")
	var before: int = site.wood_delivered
	var ticks: int = _run(w, func() -> bool: return site.wood_delivered > before)
	check(ticks < MAX_TICKS,
		"der Nachschub-Brave holt aus dem Regal und finanziert die Baustelle")
	_free_world(w)


func test_supply_job_does_not_relay_into_another_depot() -> void:
	# Die heikelste Interaktion: der Stapel-Relais-Zweig in _tick_pickup haette den
	# Auftrag still in ein Depot->Depot-Relais verwandelt, weil der Bestand eines
	# Regals immer "an einem eigenen Gebaeude" liegt.
	var w: Dictionary = _make_world()
	var site: Building = w.building_manager.place(HUT_SCENE, w.tribe, Vector2i(50, 50), 0, false)
	var src: Building = w.building_manager.place(DEPOT_SCENE, w.tribe, Vector2i(44, 50), 0, true)
	(src as WoodDepot).store_wood(20)
	w.building_manager.place(DEPOT_SCENE, w.tribe, Vector2i(40, 40), 0, true)
	var brave: Brave = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, Vector3(46, 5, 50)) as Brave
	check(w.commands.order_supply_wood([brave] as Array[Unit], site) == 1, "Auftrag laeuft")
	var drifted: bool = false
	for i in range(200):
		w.unit_manager.tick_units(TICK)
		w.unit_manager.tick(TICK)
		w.building_manager.tick(TICK)
		if not brave.has_supply_job():
			break
		if brave._supply_target != site:
			drifted = true
			break
	check(not drifted,
		"das Ziel bleibt die Baustelle - kein stilles Depot->Depot-Relais")
	_free_world(w)


func test_new_order_cancels_the_supply_job() -> void:
	var w: Dictionary = _make_world()
	var site: Building = w.building_manager.place(HUT_SCENE, w.tribe, Vector2i(50, 50), 0, false)
	var depot: Building = w.building_manager.place(DEPOT_SCENE, w.tribe, Vector2i(44, 50), 0, true)
	(depot as WoodDepot).store_wood(20)
	var brave: Brave = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, Vector3(46, 5, 50)) as Brave
	w.commands.order_supply_wood([brave] as Array[Unit], site)
	check(brave.has_supply_job(), "Auftrag laeuft")
	brave.order_move(Vector3(60, 5, 60))
	check(not brave.has_supply_job(), "jeder andere Befehl bricht ihn ab")
	_free_world(w)


func test_supply_job_never_marks_the_target_stalled() -> void:
	# Das Ziel darf nicht fuer das Versagen des LIEFERANTEN bestraft werden:
	# wood_stalled laesst den Rekrutierer die Baustelle 30 s ueberspringen.
	var w: Dictionary = _make_world()
	var site: Building = w.building_manager.place(HUT_SCENE, w.tribe, Vector2i(50, 50), 0, false)
	var brave: Brave = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, Vector3(46, 5, 50)) as Brave
	# Kein Regal, kein Stapel, kein Baum: der Auftrag muss scheitern.
	check(w.commands.order_supply_wood([brave] as Array[Unit], site) == 0,
		"ohne jede Quelle wird der Auftrag abgelehnt")
	check(not site.wood_stalled, "und die Baustelle wird NICHT als stalled markiert")
	_free_world(w)


# --- Das Regal an der Werkstatt ------------------------------------------------------

func test_rack_inside_the_absorb_radius_counts_as_shop_stock() -> void:
	# Der Kern von Teil 4: ein Regal im ABSORB_RADIUS des Lieferpunkts wird von
	# Workshop.stock_wood() als eigener Bestand gezaehlt, die Werkstatt schickt ihre
	# Insassen also nicht mehr zum Holzholen hinaus.
	var w: Dictionary = _make_world()
	var shop: Workshop = w.building_manager.place(WORKSHOP_SCENE, w.tribe,
		Vector2i(50, 50), 0, true) as Workshop
	var drop: Vector3 = shop.delivery_point()
	var cell: Vector2i = w.nav.world_to_cell(drop) + Vector2i(2, 0)
	var rack: WoodDepot = w.building_manager.place(DEPOT_SCENE, w.tribe, cell, 0, true) as WoodDepot
	check(rack != null, "Regal gesetzt")
	check(rack.footprint_distance_to(Vector2(drop.x, drop.z)) <= Building.ABSORB_RADIUS,
		"und es liegt im Absorptionsradius (Testvoraussetzung)")
	var before: int = shop.stock_wood()
	rack.store_wood(shop.product_wood())
	check(shop.stock_wood() > before,
		"der Regalbestand zaehlt als Werkstattbestand")
	check(not shop.wants_more_stock_wood(),
		"und die Werkstatt will kein Holz mehr holen - der Hol-Zyklus endet")
	_free_world(w)


func test_rack_outside_the_absorb_radius_is_not_shop_stock() -> void:
	# Negativkontrolle fuer AI_SHOP_RACK_MAX_DIST.
	var w: Dictionary = _make_world()
	var shop: Workshop = w.building_manager.place(WORKSHOP_SCENE, w.tribe,
		Vector2i(50, 50), 0, true) as Workshop
	var far: Vector2i = w.nav.world_to_cell(shop.delivery_point()) + Vector2i(12, 0)
	var rack: WoodDepot = w.building_manager.place(DEPOT_SCENE, w.tribe, far, 0, true) as WoodDepot
	rack.store_wood(shop.product_wood())
	check(shop.stock_wood() == 0, "ein zu weit entferntes Regal ist kein Bestand")
	check(Balance.AI_SHOP_RACK_MAX_DIST < Building.ABSORB_RADIUS,
		"deshalb klemmt AI_SHOP_RACK_MAX_DIST unter ABSORB_RADIUS")
	_free_world(w)
