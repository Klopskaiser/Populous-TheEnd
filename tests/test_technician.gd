extends TestBase

## The technician (2026-09-09): trained at the training hall, statistically a
## brave, worth a lot more once he mans a vehicle.
##
## The one dangerous thing about deriving him from Brave is the wood pipeline:
## he must NOT fetch wood, but a worker that cannot fetch must also never mark
## its site as "wood stalled" — that would freeze the site for 30 s and keep the
## braves who CAN fetch away from it (BuildingManager._recruit_workers skips
## stalled sites). test_technician_never_stalls_a_site pins that down.

const TICK: float = 0.05
const MAX_TICKS: int = 4000

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const TECHNICIAN_SCENE: PackedScene = preload("res://scenes/units/technician.tscn")
const TRAINING_HALL_SCENE: PackedScene = preload("res://scenes/buildings/training_hall.tscn")
const WARRIOR_CAMP_SCENE: PackedScene = preload("res://scenes/buildings/warrior_camp.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const SIEGE_SCENE: PackedScene = preload("res://scenes/units/siege_engine.tscn")
const FIRERAM_SCENE: PackedScene = preload("res://scenes/units/fire_ram.tscn")
const AIRSHIP_SCENE: PackedScene = preload("res://scenes/units/airship.tscn")


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


func _spawn(w: Dictionary, scene: PackedScene, cell: Vector2i, tribe_id: int = 0) -> Unit:
	return w.unit_manager.spawn_unit(scene, tribe_id, w.nav.cell_to_world(cell))


## Boards `scene` onto the vehicle and ticks until it actually serves.
func _board(w: Dictionary, vehicle: CrewedVehicle, scene: PackedScene) -> Unit:
	var u: Unit = w.unit_manager.spawn_unit(
		scene, 0, vehicle.position + Vector3(1.0, 0.0, 0.0))
	u.order_crew(vehicle)
	var ticks: int = 0
	while not u.siege_boarded and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	return u


func _technicians(w: Dictionary) -> Array[Unit]:
	var found: Array[Unit] = []
	for u: Unit in w.tribe.units:
		if u is Technician:
			found.append(u)
	return found


# --- The unit itself ----------------------------------------------------------

func test_technician_stats_match_the_brave() -> void:
	var w: Dictionary = _make_world()
	var t: Unit = _spawn(w, TECHNICIAN_SCENE, Vector2i(20, 20))
	check(t.unit_kind() == &"technician", "own unit kind")
	check(t.max_health == Balance.BRAVE_HP, "same health as a brave")
	check_near(t.speed, Balance.BRAVE_SPEED, "same speed as a brave")
	check_near(t.melee_strength(), 1.0, "and the same base damage")
	check(t is Brave, "he IS a brave for the build/repair machinery")
	_free_world(w)


func test_technician_melee_split() -> void:
	var w: Dictionary = _make_world()
	var t: Unit = _spawn(w, TECHNICIAN_SCENE, Vector2i(20, 20))
	check_near(t._shove_chance(), 0.0, "the technician never shoves")
	check_near(t._kick_chance(), 0.5, "half his strikes are kicks")
	check(t._shove_chance() + t._kick_chance() <= 1.0,
		"and the remainder (the punch) is the other half")
	_free_world(w)


func test_technician_refuses_every_wood_order() -> void:
	var w: Dictionary = _make_world()
	var t: Brave = _spawn(w, TECHNICIAN_SCENE, Vector2i(20, 20)) as Brave
	check(not t.can_gather_wood(), "wood is not his job")
	var tree: TreeResource = w.tree_manager.spawn_tree(Vector2i(22, 20), 3)
	check(tree != null, "a tree stands next to him")
	check(not t.order_chop(tree), "chopping is refused")
	check(not t.order_chop_area(Rect2(Vector2(60.0, 60.0), Vector2(20.0, 20.0))),
		"the harvest rectangle is refused")
	w.wood_pile_manager.deposit(w.nav.cell_to_world(Vector2i(21, 20)), 3)
	var pile: WoodPile = w.wood_pile_manager.nearest_pile(
		w.nav.cell_to_world(Vector2i(21, 20)))
	t.order_pickup(pile)
	check(t.task == Brave.Task.NONE, "and picking a pile up as an order too")
	check(t.state == Unit.State.IDLE, "he just stands there")
	_free_world(w)


func test_a_brave_still_takes_wood_orders() -> void:
	var w: Dictionary = _make_world()
	var b: Brave = _spawn(w, BRAVE_SCENE, Vector2i(20, 20)) as Brave
	var tree: TreeResource = w.tree_manager.spawn_tree(Vector2i(22, 20), 3)
	check(b.can_gather_wood(), "counter-check: the brave may")
	check(b.order_chop(tree), "and takes the chop order")
	_free_world(w)


func test_technician_cannot_be_housed_anywhere() -> void:
	var w: Dictionary = _make_world()
	var t: Brave = _spawn(w, TECHNICIAN_SCENE, Vector2i(20, 20)) as Brave
	var hut: Hut = w.building_manager.place(
		HUT_SCENE, w.tribe, Vector2i(30, 30), 0, true) as Hut
	var camp: TrainingBuilding = w.building_manager.place(
		WARRIOR_CAMP_SCENE, w.tribe, Vector2i(40, 30), 0, true) as TrainingBuilding
	t.order_man_hut(hut)
	check(t.state != Unit.State.BUILD or t.job != hut, "he does not man huts")
	t.order_train(camp)
	check(camp.incoming.is_empty(), "and cannot be retrained into a warrior")
	check(t.job == null, "no job was taken at all")
	_free_world(w)


func test_technician_builds_a_site() -> void:
	var w: Dictionary = _make_world()
	var site: Building = w.building_manager.place(HUT_SCENE, w.tribe, Vector2i(30, 30), 0)
	check(site != null and site.under_construction, "a construction site stands")
	# Enough wood right at the site so nobody has to fell a tree for it.
	w.wood_pile_manager.deposit(site.delivery_point(), Hut.WOOD_COST + 2)
	var t: Brave = _spawn(w, TECHNICIAN_SCENE, Vector2i(29, 29)) as Brave
	w.commands.order_build([t] as Array[Unit], site)
	var progressed: bool = false
	for i in range(MAX_TICKS):
		_tick_world(w)
		if site.build_progress > 0.0 or not site.under_construction:
			progressed = true
			break
	check(progressed, "the technician builds it just like a brave")
	_free_world(w)


func test_technician_never_stalls_a_site() -> void:
	var w: Dictionary = _make_world()
	var site: Building = w.building_manager.place(HUT_SCENE, w.tribe, Vector2i(30, 30), 0)
	check(site != null, "a construction site stands, with NO wood anywhere")
	var t: Brave = _spawn(w, TECHNICIAN_SCENE, Vector2i(29, 29)) as Brave
	w.commands.order_build([t] as Array[Unit], site)
	for i in range(400):
		_tick_world(w)
	check(not site.wood_stalled,
		"a worker who cannot fetch wood must never mark the site as stalled — "
		+ "that would lock out the braves who can")
	_free_world(w)


# --- Training hall ------------------------------------------------------------

func test_training_hall_produces_a_technician() -> void:
	var w: Dictionary = _make_world()
	var hall: TrainingBuilding = w.building_manager.place(
		TRAINING_HALL_SCENE, w.tribe, Vector2i(30, 30), 0, true) as TrainingBuilding
	check(hall != null, "the hall stands")
	check(hall.display_name() == "Ausbildungshalle", "and is named in German")
	var b: Brave = _spawn(w, BRAVE_SCENE, Vector2i(28, 34)) as Brave
	w.commands.order_train(hall, [b] as Array[Unit])
	var made: bool = false
	for i in range(MAX_TICKS):
		_tick_world(w)
		hall.tick(TICK)
		if not _technicians(w).is_empty():
			made = true
			break
	check(made, "a brave walks in and a technician comes out")
	_free_world(w)


func test_training_hall_numbers() -> void:
	check(TrainingHall.WOOD_COST == 10, "10 wood (user spec)")
	check(TrainingHall.FOOTPRINT == Vector2i(4, 4), "4x4 (user spec)")
	check_near(TrainingHall.TRAINING_TIME, 10.0, "10 s of training (user spec)")


func test_training_hall_is_in_the_build_menu() -> void:
	var entries: Array[Dictionary] = Sidebar.default_build_entries()
	var found: Dictionary = {}
	for e in entries:
		if e["id"] == &"training_hall":
			found = e
	check(not found.is_empty(), "the build menu carries the hall")
	check(found["enabled"], "and it is buildable")
	check(found["scene"] == Sidebar.TRAINING_HALL_SCENE, "pointing at its scene")
	check(int(found["wood_cost"]) == TrainingHall.WOOD_COST, "with its own cost")


# --- Vehicle bonuses ----------------------------------------------------------

func test_speed_bonus_on_every_vehicle_kind() -> void:
	for entry in [[SIEGE_SCENE, Balance.SIEGE_SPEED],
			[FIRERAM_SCENE, Balance.FIRERAM_SPEED],
			[AIRSHIP_SCENE, Balance.AIRSHIP_SPEED]]:
		var w: Dictionary = _make_world()
		var v: CrewedVehicle = _spawn(w, entry[0], Vector2i(30, 30)) as CrewedVehicle
		_board(w, v, BRAVE_SCENE)
		for i in range(20):
			_tick_world(w)
		check_near(v.speed, entry[1],
			"%s with a brave crew keeps its base speed" % [v.unit_kind()])
		_board(w, v, TECHNICIAN_SCENE)
		for i in range(20):
			_tick_world(w)
		check_near(v.speed, float(entry[1]) * 1.33,
			"%s with a technician aboard is 33 %% faster" % [v.unit_kind()])
		_board(w, v, TECHNICIAN_SCENE)
		for i in range(20):
			_tick_world(w)
		check_near(v.speed, float(entry[1]) * 1.33,
			"%s: a second technician does NOT stack the speed" % [v.unit_kind()])
		_free_world(w)


func test_catapult_fire_rate_bonus_is_additive() -> void:
	var w: Dictionary = _make_world()
	var cat: SiegeEngine = _spawn(w, SIEGE_SCENE, Vector2i(30, 30)) as SiegeEngine
	_board(w, cat, BRAVE_SCENE)
	_board(w, cat, BRAVE_SCENE)
	for i in range(20):
		_tick_world(w)
	check_near(cat.fire_cooldown_now(2), SiegeEngine.fire_cooldown_for_crew(2),
		"no technician, no bonus")
	_board(w, cat, TECHNICIAN_SCENE)
	for i in range(20):
		_tick_world(w)
	check(cat.technician_crew_count() == 1, "one technician serves")
	check_near(cat.fire_cooldown_now(3), SiegeEngine.fire_cooldown_for_crew(3) / 1.33,
		"the first technician gives +33 % fire rate")
	_board(w, cat, TECHNICIAN_SCENE)
	_board(w, cat, TECHNICIAN_SCENE)
	for i in range(20):
		_tick_world(w)
	check(cat.technician_crew_count() == 3, "three technicians serve")
	check_near(cat.fire_cooldown_now(5), SiegeEngine.fire_cooldown_for_crew(5) / 1.53,
		"every further one adds 10 %, additively (33 + 10 + 10)")
	_free_world(w)


func test_fire_ram_first_technician_gives_no_rate_bonus() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _spawn(w, FIRERAM_SCENE, Vector2i(30, 30)) as FireRam
	_board(w, ram, TECHNICIAN_SCENE)
	for i in range(20):
		_tick_world(w)
	check(ram.technician_crew_count() == 1, "one technician serves")
	check_near(ram.flame_cooldown_now(1), FireRam.flame_cooldown_for_crew(1),
		"the ram's first technician pays in resistances, not in fire rate")
	_board(w, ram, TECHNICIAN_SCENE)
	for i in range(20):
		_tick_world(w)
	check_near(ram.flame_cooldown_now(2), FireRam.flame_cooldown_for_crew(2) / 1.10,
		"the second one adds 10 %")
	_free_world(w)


func test_fire_ram_technicians_get_the_three_resistances() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _spawn(w, FIRERAM_SCENE, Vector2i(30, 30)) as FireRam
	var tech: Unit = _board(w, ram, TECHNICIAN_SCENE)
	var brave: Unit = _board(w, ram, BRAVE_SCENE)
	for i in range(10):
		_tick_world(w)
	check(tech.has_buff(Unit.BUFF_FIRE_RESIST), "fire resistance")
	check(tech.has_buff(Unit.BUFF_PANIC_RESIST), "panic resistance")
	check(tech.has_buff(Unit.BUFF_CONVERT_RESIST), "conversion resistance")
	check(not brave.has_any_buff(), "the brave beside him gets nothing")
	tech.leave_crew()
	check(not tech.has_any_buff(), "leaving the crew ends the aura at once")
	_free_world(w)


func test_airship_strength_aura_starts_with_the_second_technician() -> void:
	var w: Dictionary = _make_world()
	var ship: Airship = _spawn(w, AIRSHIP_SCENE, Vector2i(30, 30)) as Airship
	var brave: Unit = _board(w, ship, BRAVE_SCENE)
	var t1: Unit = _board(w, ship, TECHNICIAN_SCENE)
	for i in range(10):
		_tick_world(w)
	check(not brave.has_buff(Unit.BUFF_STRENGTH), "one technician: no strength yet")
	check(not t1.has_buff(Unit.BUFF_STRENGTH), "not even for himself")
	_board(w, ship, TECHNICIAN_SCENE)
	for i in range(10):
		_tick_world(w)
	check(brave.buff_stacks(Unit.BUFF_STRENGTH) == 1,
		"the second technician buffs EVERY passenger with one stack")
	check(t1.buff_stacks(Unit.BUFF_STRENGTH) == 1, "the technicians included")
	check_near(brave.attack_multiplier(), 1.5, "which is 1.5x damage")
	_board(w, ship, TECHNICIAN_SCENE)
	for i in range(10):
		_tick_world(w)
	check(brave.buff_stacks(Unit.BUFF_STRENGTH) == 2, "a third one adds a stack")
	check_near(brave.attack_multiplier(), 2.25, "stacks multiply")
	_free_world(w)


## Brennende Technikerbesatzung bedient die Feuerramme weiter (Nutzervorgabe
## 2026-09-10). Die Ramme faehrt durch ihren eigenen Flammenkegel und zuendet
## dabei die eigene Crew an — mit Feuerresistenz ist das folgenlos (5 statt
## 15 HP/s, keine Panik), also darf es sie auch nicht aus dem Dienst nehmen.
func test_a_burning_technician_keeps_serving_the_fire_ram() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _spawn(w, FIRERAM_SCENE, Vector2i(30, 30)) as FireRam
	var tech: Unit = _board(w, ram, TECHNICIAN_SCENE)
	for i in range(10):
		_tick_world(w)
	check(tech.has_buff(Unit.BUFF_FIRE_RESIST), "the ram made him heat-proof")
	check(ram.active_crew_count() == 1, "he serves")
	tech.scorch(tech.position + Vector3(1.0, 0, 0))
	check(tech.is_burning(), "and now he is on fire")
	check(tech.state == Unit.State.CREW, "fire resistance keeps him at his post")
	check(ram.active_crew_count() == 1, "a burning technician still serves the ram")
	check(ram.technician_crew_count() == 1, "and still counts for the bonus")
	check(not ram.is_neutral(), "so the ram never falls neutral")
	_free_world(w)


## Und er FEUERT auch wirklich weiter — der eigentliche Punkt der Vorgabe.
func test_a_burning_technician_crew_still_fires_the_ram() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _spawn(w, FIRERAM_SCENE, Vector2i(30, 30)) as FireRam
	var tech: Unit = _board(w, ram, TECHNICIAN_SCENE)
	for i in range(10):
		_tick_world(w)
	var foe: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, ram.position + Vector3(0, 0, 2.2))
	ram.order_attack(foe)
	# Re-lit EVERY tick: without that the 4-s burn simply lapses and the ram
	# fires afterwards — the test would pass with or without the rule.
	var ticks: int = 0
	while not foe.is_burning() and ticks < 200:
		tech.scorch(tech.position + Vector3(1.0, 0, 0))
		_tick_world(w)
		ticks += 1
	check(tech.is_burning(), "the crew is still alight at the end")
	check(foe.is_burning(),
		"the ram burnt its target while its own crew was on fire (%d ticks)" % ticks)
	_free_world(w)


## Gegenprobe 1: ein brennender BRAVE auf derselben Ramme faellt aus — er
## bekommt die Aura nicht (sie gilt nur Technikern).
func test_a_burning_brave_on_the_ram_still_drops_out() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _spawn(w, FIRERAM_SCENE, Vector2i(30, 30)) as FireRam
	var brave: Unit = _board(w, ram, BRAVE_SCENE)
	for i in range(10):
		_tick_world(w)
	check(not brave.has_buff(Unit.BUFF_FIRE_RESIST), "no aura for a brave")
	check(ram.active_crew_count() == 1, "he serves while unhurt")
	# Panikresistenz per Hand, damit der Test WIRKLICH das Brennen misst und
	# nicht die Panik, die einen brennenden Brave ohnehin vom Posten wirft.
	brave.apply_buff(Unit.BUFF_PANIC_RESIST, 60.0)
	brave.scorch(brave.position + Vector3(1.0, 0, 0))
	check(brave.state == Unit.State.CREW, "he stays put (panic-proof for the test)")
	check(ram.active_crew_count() == 0,
		"but burning WITHOUT fire resistance takes him out of service")
	_free_world(w)


## Gegenprobe 2: derselbe Techniker auf einem KATAPULT faellt aus — dort gibt es
## die Aura nicht, die Ausnahme haengt am Buff und nicht an der Einheitenart.
func test_a_burning_technician_on_a_catapult_drops_out() -> void:
	var w: Dictionary = _make_world()
	var cat: SiegeEngine = _spawn(w, SIEGE_SCENE, Vector2i(30, 30)) as SiegeEngine
	var tech: Unit = _board(w, cat, TECHNICIAN_SCENE)
	for i in range(10):
		_tick_world(w)
	check(not tech.has_buff(Unit.BUFF_FIRE_RESIST), "the catapult grants no aura")
	tech.apply_buff(Unit.BUFF_PANIC_RESIST, 60.0)
	tech.scorch(tech.position + Vector3(1.0, 0, 0))
	check(tech.state == Unit.State.CREW, "he stays put (panic-proof for the test)")
	check(cat.active_crew_count() == 0,
		"a burning technician without the ram's aura is out of service")
	_free_world(w)


func test_airship_hull_repair_needs_a_technician() -> void:
	var w: Dictionary = _make_world()
	var plain: Airship = _spawn(w, AIRSHIP_SCENE, Vector2i(30, 30)) as Airship
	_board(w, plain, BRAVE_SCENE)
	plain.register_hull_hit()
	check(plain.is_burning(), "the hull is on fire after the first hit")
	for i in range(int(Balance.AIRSHIP_HULL_REGEN_TIME / TICK) + 40):
		_tick_world(w)
	check(plain.is_burning(), "a brave crew cannot patch it")
	_free_world(w)

	var w2: Dictionary = _make_world()
	var fixed: Airship = _spawn(w2, AIRSHIP_SCENE, Vector2i(30, 30)) as Airship
	_board(w2, fixed, TECHNICIAN_SCENE)
	fixed.register_hull_hit()
	check(fixed.is_burning(), "same damage")
	for i in range(int(Balance.AIRSHIP_HULL_REGEN_TIME / TICK) + 40):
		_tick_world(w2)
	check(not fixed.is_burning(),
		"with a technician aboard the hull is patched and the fire goes out")
	_free_world(w2)
