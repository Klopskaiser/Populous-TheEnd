extends TestBase

## Ritualkammer (experimentell, Nutzervorgabe 2026-11-16): ein Ausbildungsgebaeude,
## aus dem niemand herauskommt. Je zwei geopferte Braves bekommt ein zufaelliger
## eigener Golem einen Kill; ohne Golem gehen 10 Mana in einen der Golemzauber.
## Nur mit dem Optionsschalter im Baumenue. Dazu der Bauabstand: um jedes Gebaeude
## bleibt Balance.BUILDING_MIN_GAP (1 m) frei.

const TICK: float = 0.05
const MAX_TICKS: int = 4000

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const GOLEM_SCENE: PackedScene = preload("res://scenes/units/golem.tscn")
const CHAMBER_SCENE: PackedScene = preload("res://scenes/buildings/ritual_chamber.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")


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
	um.building_manager = bm
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(nav, bm, um, tm)
	tribe.set_spells(Spell.create_player_set())
	return {"td": td, "nav": nav, "tribe": tribe, "enemy": enemy,
		"unit_manager": um, "building_manager": bm, "tree_manager": tm,
		"wood_pile_manager": wpm, "commands": tc}


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


func _chamber(w: Dictionary) -> RitualChamber:
	var c: RitualChamber = w.building_manager.place(
		CHAMBER_SCENE, w.tribe, Vector2i(30, 30), 0, true) as RitualChamber
	c.rng.seed = 7
	return c


## Schickt `count` Braves hinein und tickt, bis alle geopfert sind.
func _sacrifice(w: Dictionary, chamber: RitualChamber, count: int) -> Array[Brave]:
	var braves: Array[Brave] = []
	for i in range(count):
		braves.append(w.unit_manager.spawn_unit(BRAVE_SCENE, 0,
			w.nav.cell_to_world(Vector2i(26 + i, 36))) as Brave)
	var sel: Array[Unit] = []
	sel.assign(braves)
	w.commands.order_train(chamber, sel)
	var start: int = w.tribe.ritual_sacrifices
	for i in range(MAX_TICKS):
		_tick_world(w)
		if w.tribe.ritual_sacrifices - start >= count:
			break
	return braves


func _living_units_of(w: Dictionary) -> int:
	var n: int = 0
	for u in w.tribe.units:
		if is_instance_valid(u) and u.state != Unit.State.DEAD:
			n += 1
	return n


func test_numbers() -> void:
	check(RitualChamber.WOOD_COST == 20, "20 wood")
	check(RitualChamber.FOOTPRINT == Vector2i(3, 3), "3x3")
	check_near(RitualChamber.TRAINING_TIME, 1.0, "1 s inside")
	var c: RitualChamber = CHAMBER_SCENE.instantiate() as RitualChamber
	check(c.produces == null, "nobody comes out")
	check_near(c.training_mana_rate() * c.training_time,
		Balance.TRAINING_MANA_PER_BUILDING * Balance.WARRIOR_CAMP_TRAINING_TIME,
		"one brave costs as much mana as one warrior at the barracks", 0.0001)
	check(c.display_name() == "Ritualkammer", "named in German")
	c.free()


func test_build_menu_only_with_the_option() -> void:
	var ids_off: Array = []
	for e in Sidebar.default_build_entries(0):
		ids_off.append(e["id"])
	check(not ids_off.has(&"ritual_chamber"), "option off: not in the build menu")
	var found: Dictionary = {}
	for e in Sidebar.default_build_entries(1):
		if e["id"] == &"ritual_chamber":
			found = e
	check(not found.is_empty() and found["enabled"], "option on: buildable")
	check(found.get("scene") == Sidebar.RITUAL_CHAMBER_SCENE, "pointing at its scene")
	check(int(found.get("wood_cost", 0)) == 20, "for 20 wood")


func test_two_sacrifices_credit_one_kill_to_an_own_golem() -> void:
	var w: Dictionary = _make_world()
	var chamber: RitualChamber = _chamber(w)
	var golem: Golem = w.unit_manager.spawn_unit(GOLEM_SCENE, 0,
		w.nav.cell_to_world(Vector2i(60, 60))) as Golem
	var foreign: Golem = w.unit_manager.spawn_unit(GOLEM_SCENE, 1,
		w.nav.cell_to_world(Vector2i(80, 80))) as Golem
	var before: int = _living_units_of(w)
	_sacrifice(w, chamber, 1)
	check(w.tribe.ritual_sacrifices == 1 and golem.kills == 0, "one brave: no reward yet")
	_sacrifice(w, chamber, 1)
	check(w.tribe.ritual_sacrifices == 2, "two braves sacrificed")
	check(golem.kills == 1, "the own golem got one kill (got %d)" % golem.kills)
	check(foreign.kills == 0, "never a golem of another tribe")
	check(_living_units_of(w) == before, "both braves are gone, nobody came out")
	_free_world(w)


func test_without_a_golem_twenty_mana_go_into_a_golem_spell() -> void:
	var w: Dictionary = _make_world()
	var chamber: RitualChamber = _chamber(w)
	var g: Spell = w.tribe.get_spell(&"golem")
	var d: Spell = w.tribe.get_spell(&"demon_golem")
	var gs: Spell = w.tribe.get_spell(&"genesis_golem")
	var before: float = g.charge_mana + d.charge_mana + gs.charge_mana
	_sacrifice(w, chamber, 2)
	check_near(g.charge_mana + d.charge_mana + gs.charge_mana - before, Balance.RITUAL_CHAMBER_MANA_REWARD,
		"20 mana into one of the three golem spells", 0.0001)
	check_near(Balance.RITUAL_CHAMBER_MANA_REWARD, 20.0, "20 (user spec 2026-11-18, before 10)")
	check(chamber.grant_reward() == &"mana", "the reward is mana")
	g.charges = g.max_charges
	g.charge_mana = 0.0
	d.charges = d.max_charges
	d.charge_mana = 0.0
	var gen: Spell = w.tribe.get_spell(&"genesis_golem")
	gen.charges = gen.max_charges
	gen.charge_mana = 0.0
	check(chamber.grant_reward() == &"none", "all three spells full: nothing to give")
	_free_world(w)


## Nutzervorgabe 2026-11-18: das Mana geht nur in einen aktiven (ladenden), nicht vollen Golemzauber; ist keiner
## aktiv und offen, wie vorher in einen zufaelligen nicht vollen.
func test_ritual_mana_prefers_an_active_golem_spell() -> void:
	var w: Dictionary = _make_world()
	var chamber: RitualChamber = _chamber(w)
	var g: Spell = w.tribe.get_spell(&"golem")
	var d: Spell = w.tribe.get_spell(&"demon_golem")
	var gen: Spell = w.tribe.get_spell(&"genesis_golem")
	check(gen != null, "the player's set has the genesis golem spell")
	g.active = false
	d.active = true
	gen.active = false
	for i in range(3):   # (20 a time: far from a full 600-mana charge)
		var gm: float = g.charge_mana
		var dm: float = d.charge_mana
		var genm: float = gen.charge_mana
		check(chamber.grant_reward() == &"mana", "mana")
		check(is_equal_approx(g.charge_mana, gm) and is_equal_approx(gen.charge_mana, genm) and d.charge_mana > dm,
			"only the active demon golem spell takes it (reward %d)" % i)
	# The genesis golem spell takes it as well (user spec 2026-11-18): the only active one.
	d.active = false
	gen.active = true
	var gen_before: float = gen.charge_mana
	check(chamber.grant_reward() == &"mana" and gen.charge_mana > gen_before,
		"the genesis golem spell is filled too, when it is the active one")
	# The active one full, the others switched off: as before, into one that is not full.
	gen.charges = gen.max_charges
	gen.charge_mana = 0.0
	d.charges = d.max_charges
	d.charge_mana = 0.0
	var before: float = g.charge_mana
	check(chamber.grant_reward() == &"mana" and g.charge_mana > before,
		"the only active spell full: into the switched-off one that is not")
	# None active: a random one that is not full.
	d.charges = 0
	gen.charges = 0
	g.active = false
	d.active = false
	gen.active = false
	var sum: float = g.charge_mana + d.charge_mana + gen.charge_mana
	check(chamber.grant_reward() == &"mana", "none active: still mana")
	check_near(g.charge_mana + d.charge_mana + gen.charge_mana - sum, Balance.RITUAL_CHAMBER_MANA_REWARD,
		"into one of them", 0.0001)
	_free_world(w)


# --- Bauabstand ------------------------------------------------------------------------

func test_buildings_keep_a_free_gap_around_them() -> void:
	var w: Dictionary = _make_world()
	check(Balance.BUILDING_MIN_GAP == 1, "1 m by default")
	var hut: Building = w.building_manager.place(HUT_SCENE, w.tribe, Vector2i(40, 40), 0, true)
	var fp: Vector2i = hut.footprint
	var east: int = 40 + fp.x
	check(not w.commands.can_place_at(Vector2i(east, 40), Vector2i(2, 2)),
		"right next to the hut: refused")
	check(w.commands.can_place_at(Vector2i(east + 1, 40), Vector2i(2, 2)),
		"one free metre between them: allowed")
	check(not w.commands.can_place_at(Vector2i(40, 40 - 2), Vector2i(2, 2)),
		"touching from the north: refused")
	check(w.commands.can_place_at(Vector2i(40, 40 - 3), Vector2i(2, 2)),
		"one free metre to the north: allowed")
	_free_world(w)
