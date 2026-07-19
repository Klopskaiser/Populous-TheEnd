extends TestBase

## Phase 7i: manned huts + growth control. A hut only produces while it has crew
## (braves hidden inside, still counted in population, no mana cost); the rate
## scales with crew, an empty hut produces nothing. Nearby idle braves are
## auto-manned per the tribe's growth mode; the hard unit cap is enforced.

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
	return {"td": td, "nav": nav, "tribe": tribe, "um": um, "bm": bm, "tm": tm, "wpm": wpm}


func _free_world(w: Dictionary) -> void:
	w.tm.free()
	w.wpm.free()
	w.bm.free()
	w.um.free()


func _place_hut(w: Dictionary, cell: Vector2i) -> Hut:
	return w.bm.place(HUT_SCENE, w.tribe, cell, 0, true) as Hut


## One simulation step: move every unit, refresh the manager (hash/paths), then
## tick the hut (production / growth / crew admission on the fresh hash).
func _step(w: Dictionary, hut: Hut, dt: float) -> void:
	for u in w.um.units.duplicate():
		if is_instance_valid(u):
			u.tick(dt)
	w.um.tick(dt)
	hut.tick(dt)


func test_crew_admit_limit_and_eligibility() -> void:
	var w: Dictionary = _make_world()
	w.tribe.growth_mode = Tribe.GrowthMode.NONE   # no auto-manning interference
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	for i in range(Hut.CREW_CAPACITY):
		var b: Unit = w.um.spawn_unit(BRAVE_SCENE, 0, hut.center_world())
		check(hut.admit_crew(b), "brave %d admitted as crew" % i)
	check(hut.crew_count() == Hut.CREW_CAPACITY, "hut is full at CREW_CAPACITY")
	var fifth: Unit = w.um.spawn_unit(BRAVE_SCENE, 0, hut.center_world())
	check(not hut.admit_crew(fifth), "a fifth brave is refused")
	check(w.tribe.population() == Hut.CREW_CAPACITY + 1,
		"crew + the rejected brave all count toward population")
	_free_world(w)


func test_empty_hut_produces_nothing() -> void:
	var w: Dictionary = _make_world()
	w.tribe.growth_mode = Tribe.GrowthMode.NONE
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	for i in range(int(Hut.SPAWN_INTERVAL / TICK) * 2):
		hut.tick(TICK)
	check(w.tribe.population() == 0, "an unmanned hut never spawns")
	check(hut.production_progress() < 0.0, "no production bar without crew")
	check_near(hut.growth_per_minute(), 0.0, "no growth without crew")
	_free_world(w)


func test_rate_scales_with_crew() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	# Manually set crew size and read the rate factor (0 .. FULL_CREW_BONUS).
	for i in range(Hut.CREW_CAPACITY):
		hut.admit_crew(w.um.spawn_unit(BRAVE_SCENE, 0, hut.center_world()))
	check_near(hut._spawn_rate_factor(), Hut.FULL_CREW_BONUS, "full crew ~10% faster")
	hut.eject_crew(0)
	hut.eject_crew(0)
	hut.eject_crew(0)   # down to 1 crew
	check(hut.crew_count() == 1, "one crew left after ejects")
	check_near(hut._spawn_rate_factor(), Hut.FULL_CREW_BONUS / float(Hut.CREW_CAPACITY),
		"one crew produces at a quarter of the full bonus")
	_free_world(w)


func test_eject_returns_brave_to_world() -> void:
	var w: Dictionary = _make_world()
	w.tribe.growth_mode = Tribe.GrowthMode.NONE
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	var b: Unit = w.um.spawn_unit(BRAVE_SCENE, 0, hut.center_world())
	hut.admit_crew(b)
	check(not (b in w.um.units), "crew brave is removed from the world (hidden)")
	var pop: int = w.tribe.population()
	hut.eject_crew(0)
	check(hut.crew_count() == 0, "crew empty after eject")
	check(b in w.um.units, "ejected brave is back in the world")
	check(w.tribe.population() == pop, "population unchanged by the eject")
	_free_world(w)


func test_growth_none_empties_huts() -> void:
	var w: Dictionary = _make_world()
	w.tribe.growth_mode = Tribe.GrowthMode.MAXIMUM
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	for i in range(Hut.CREW_CAPACITY):
		hut.admit_crew(w.um.spawn_unit(BRAVE_SCENE, 0, hut.center_world()))
	check(hut.crew_count() == Hut.CREW_CAPACITY, "manned before switching mode")
	w.tribe.growth_mode = Tribe.GrowthMode.NONE
	for i in range(int(Hut.GROWTH_INTERVAL / TICK) + 2):
		hut.tick(TICK)
	check(hut.crew_count() == 0, "NONE ejects all hut crew")
	_free_world(w)


func test_growth_maximum_auto_fills_from_nearby() -> void:
	var w: Dictionary = _make_world()
	w.tribe.growth_mode = Tribe.GrowthMode.MAXIMUM
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	# Four idle braves standing right next to the hut.
	for i in range(Hut.CREW_CAPACITY):
		w.um.spawn_unit(BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(57 + i, 57)))
	var ok: bool = false
	for i in range(int(20.0 / TICK)):   # up to 20 s of sim
		_step(w, hut, TICK)
		if hut.crew_count() >= Hut.CREW_CAPACITY:
			ok = true
			break
	check(ok, "MAXIMUM pulls nearby idle braves up to full crew")
	_free_world(w)


func test_growth_only_pulls_nearby_braves() -> void:
	var w: Dictionary = _make_world()
	w.tribe.growth_mode = Tribe.GrowthMode.MAXIMUM
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	# One idle brave far beyond MAN_RADIUS.
	var far: Unit = w.um.spawn_unit(BRAVE_SCENE, 0,
		w.nav.cell_to_world(Vector2i(60 + int(Hut.MAN_RADIUS) + 12, 60)))
	for i in range(int(6.0 / TICK)):
		_step(w, hut, TICK)
	check(hut.crew_count() == 0, "a distant idle brave is not pulled in")
	check(far.state != Unit.State.GARRISON, "the distant brave keeps standing idle")
	_free_world(w)


func test_manual_eject_holds() -> void:
	var w: Dictionary = _make_world()
	w.tribe.growth_mode = Tribe.GrowthMode.MAXIMUM
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	for i in range(Hut.CREW_CAPACITY):
		hut.admit_crew(w.um.spawn_unit(BRAVE_SCENE, 0, hut.center_world()))
	# Manual eject (crew tab): the ejected brave idles right at the hut, but the
	# override pins the crew below the MAXIMUM target — no auto-refill.
	hut.eject_crew(Hut.CREW_CAPACITY - 1, true)
	check(hut.manual_crew_override == Hut.CREW_CAPACITY - 1,
		"manual eject pins the crew at the reduced size")
	for i in range(int(4.0 / TICK)):
		_step(w, hut, TICK)
	check(hut.crew_count() == Hut.CREW_CAPACITY - 1,
		"MAXIMUM does not refill past a manual eject")
	_free_world(w)


func test_manual_man_holds() -> void:
	var w: Dictionary = _make_world()
	w.tribe.growth_mode = Tribe.GrowthMode.NONE
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	var b: Unit = w.um.spawn_unit(BRAVE_SCENE, 0, hut.entrance_world())
	b.order_man_hut(hut, true)
	var housed: bool = false
	for i in range(int(20.0 / TICK)):
		_step(w, hut, TICK)
		if hut.crew_count() == 1:
			housed = true
			break
	check(housed, "the manually sent brave is admitted")
	check(hut.manual_crew_override == 1, "manual manning pins the crew size")
	for i in range(int(4.0 / TICK)):
		_step(w, hut, TICK)
	check(hut.crew_count() == 1, "NONE does not empty a manually manned hut")
	_free_world(w)


func test_slider_change_clears_overrides() -> void:
	var w: Dictionary = _make_world()
	w.tribe.growth_mode = Tribe.GrowthMode.MAXIMUM
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	for i in range(Hut.CREW_CAPACITY):
		hut.admit_crew(w.um.spawn_unit(BRAVE_SCENE, 0, hut.center_world()))
	hut.eject_crew(Hut.CREW_CAPACITY - 1, true)
	check(hut.manual_crew_override >= 0, "override set before the slider moves")
	w.tribe.set_growth_mode(Tribe.GrowthMode.MAXIMUM)
	check(hut.manual_crew_override == -1, "moving the slider clears the override")
	var ok: bool = false
	for i in range(int(10.0 / TICK)):
		_step(w, hut, TICK)
		if hut.crew_count() >= Hut.CREW_CAPACITY:
			ok = true
			break
	check(ok, "after the slider move the hut follows MAXIMUM again")
	_free_world(w)


func test_paused_hut_produces_nothing() -> void:
	var w: Dictionary = _make_world()
	# MAXIMUM so the growth tick does not eject the crew (pause must not).
	w.tribe.growth_mode = Tribe.GrowthMode.MAXIMUM
	var hut: Hut = _place_hut(w, Vector2i(60, 60))
	for i in range(Hut.CREW_CAPACITY):
		hut.admit_crew(w.um.spawn_unit(BRAVE_SCENE, 0, hut.center_world()))
	hut.paused = true
	var pop: int = w.tribe.population()
	for i in range(int(Hut.SPAWN_INTERVAL / TICK) * 2):
		hut.tick(TICK)
	check(w.tribe.population() == pop, "a paused hut never spawns")
	check(hut.production_progress() < 0.0, "no production bar while paused")
	check(hut.crew_count() == Hut.CREW_CAPACITY, "the crew stays housed while paused")
	_free_world(w)


func test_hard_unit_cap() -> void:
	var w: Dictionary = _make_world()
	var dummies: Array[Unit] = []
	while w.tribe.population() < Tribe.MAX_UNITS:
		var u: Unit = Unit.new()
		dummies.append(u)
		w.tribe.add_unit(u)
	check(w.tribe.at_unit_cap(), "tribe reports being at the cap")
	var over: Unit = w.um.spawn_unit(BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(60, 60)))
	check(over == null, "spawn_unit refuses beyond the hard cap")
	check(w.tribe.population() == Tribe.MAX_UNITS, "population held exactly at the cap")
	for u in dummies:
		u.free()
	_free_world(w)
