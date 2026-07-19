extends TestBase

## Headless tests for the fire ram (Feuerramme) and its workshop: production
## (11-wood building, 4 wood / 40 worker-seconds per ram, independent per-tribe
## cap), the scorch burn (no contact damage), the forward flame rectangle
## (no minimum range, friendly fire, vehicle ignition, building stage per full
## burst, tree ignition), the crew's ranged-distraction immunity and the
## shared vehicle destruction/capture rules.

const TICK: float = 0.1
const MAX_TICKS: int = 3000

const RAM_WORKSHOP_SCENE: PackedScene = preload("res://scenes/buildings/fire_ram_workshop.tscn")
const WORKSHOP_SCENE: PackedScene = preload("res://scenes/buildings/workshop.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const FIRE_RAM_SCENE: PackedScene = preload("res://scenes/units/fire_ram.tscn")
const SIEGE_SCENE: PackedScene = preload("res://scenes/units/siege_engine.tscn")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
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
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe0, tribe1] as Array[Tribe], tm, wpm)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um, wpm)
	um.building_manager = bm
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(nav, bm, um, tm)
	return {
		"td": td, "nav": nav, "tribe": tribe0, "tribe1": tribe1,
		"unit_manager": um, "building_manager": bm,
		"tree_manager": tm, "wood_pile_manager": wpm, "commands": tc,
	}


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


func _spawn_ram(w: Dictionary, tribe_id: int, pos: Vector3) -> FireRam:
	return w.unit_manager.spawn_unit(FIRE_RAM_SCENE, tribe_id, pos) as FireRam


## Spawns a brave and boards it onto the vehicle (ticking until it serves).
func _board_crew(w: Dictionary, engine, tribe_id: int = 0) -> Brave:
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, tribe_id, engine.position + Vector3(1.0, 0.0, 0.0)) as Brave
	brave.order_crew(engine)
	var ticks: int = 0
	while not brave.siege_boarded and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	return brave


func _house_worker(w: Dictionary, ws: Workshop) -> Brave:
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, ws.entrance_world() + Vector3(1.0, 0.0, 1.0)) as Brave
	brave.order_workshop(ws)
	var ticks: int = 0
	while not brave.workshop_inside and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	return brave


# --- Workshop ---------------------------------------------------------------------

func test_fire_ram_workshop_produces_a_ram() -> void:
	var w: Dictionary = _make_world()
	var ws: FireRamWorkshop = w.building_manager.place(
		RAM_WORKSHOP_SCENE, w.tribe, Vector2i(60, 60), 0, true) as FireRamWorkshop
	check(ws != null, "fire-ram workshop placed")
	check(ws.wood_cost == 11, "fire-ram workshop costs 11 wood")
	check(ws.footprint == Vector2i(6, 4), "6x4 footprint")
	check(ws.worker_slots() == 3, "3 worker slots")
	check(ws.display_name() == "Feuerrammenwerkstatt", "display name")
	_house_worker(w, ws)
	w.wood_pile_manager.deposit(ws.delivery_point(), FireRamWorkshop.RAM_WOOD)
	var stock_before: int = ws.stock_wood()
	var ticks: int = 0
	while not ws.production_active and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(ws.production_active, "production started")
	check(stock_before - ws.stock_wood() == FireRamWorkshop.RAM_WOOD,
		"starting consumed exactly %d wood" % FireRamWorkshop.RAM_WOOD)
	ticks = 0
	var rams: int = 0
	while rams == 0 and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
		rams = w.tribe.owned_fire_ram_count()
	check(rams == 1, "one fire ram rolled out")
	# 1 housed worker: 40 worker-seconds = ~400 ticks (+ walk-in slack).
	check(ticks <= int(FireRamWorkshop.WORK_PER_RAM / TICK) + 200,
		"finished in roughly 40 worker-seconds with one worker")
	_free_world(w)


func test_caps_are_independent_per_vehicle_type() -> void:
	var w: Dictionary = _make_world()
	var ram_ws: FireRamWorkshop = w.building_manager.place(
		RAM_WORKSHOP_SCENE, w.tribe, Vector2i(60, 60), 0, true) as FireRamWorkshop
	var cat_ws: Workshop = w.building_manager.place(
		WORKSHOP_SCENE, w.tribe, Vector2i(80, 80), 0, true) as Workshop
	w.wood_pile_manager.deposit(ram_ws.delivery_point(), 10)
	w.wood_pile_manager.deposit(cat_ws.delivery_point(), 10)
	w.tribe.max_fire_rams = 1
	_spawn_ram(w, 0, Vector3(40, 0, 40))
	check(w.tribe.owned_fire_ram_count() == 1, "one own ram exists")
	check(w.tribe.owned_catapult_count() == 0, "rams never count as catapults")
	check(not ram_ws.can_start_production(), "ram cap blocks the ram workshop")
	check(cat_ws.can_start_production(), "the catapult workshop is unaffected")
	w.unit_manager.spawn_unit(SIEGE_SCENE, 0, Vector3(44, 0, 40))
	check(w.tribe.owned_catapult_count() == 1, "catapults keep their own count")
	check(w.tribe.owned_fire_ram_count() == 1, "catapults never count as rams")
	_free_world(w)


# --- Scorch (burn without contact damage) -------------------------------------------

func test_scorch_burns_without_contact_damage() -> void:
	var w: Dictionary = _make_world()
	var brave: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, Vector3(40, 0, 40))
	check(not brave.is_burning(), "starts unburnt")
	brave.scorch(Vector3(38, 0, 40))
	check(brave.is_burning(), "scorch sets the unit alight")
	check(brave.health == brave.max_health,
		"NO immediate contact damage (unlike lava ignite)")
	for i in range(20):
		_tick_world(w)
	check(brave.health < brave.max_health, "the burn ticks damage over time")
	_free_world(w)


# --- Flame rectangle ------------------------------------------------------------------

## Ram at (60,60) with heading +z; boards one brave (drives AND fires).
func _armed_ram(w: Dictionary) -> FireRam:
	var ram: FireRam = _spawn_ram(w, 0, w.nav.cell_to_world(Vector2i(60, 60)))
	_board_crew(w, ram)
	return ram


func test_flame_rectangle_hits_and_misses() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _armed_ram(w)
	var pos: Vector3 = ram.position
	# In front (heading starts +z): inside range 5, no minimum range.
	var near_front: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, pos + Vector3(0, 0, 2.2))
	var behind: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, pos + Vector3(0, 0, -3.0))
	var friend: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, pos + Vector3(0.5, 0, 3.0))
	ram.order_attack(near_front)
	var ticks: int = 0
	while not near_front.is_burning() and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(near_front.is_burning(), "enemy at 2.2 m in front burns (no minimum range)")
	check(friend.is_burning(), "own unit in the cone burns too (friendly fire)")
	check(not behind.is_burning(), "the unit BEHIND the ram never burns")
	check(near_front.health == near_front.max_health
			or near_front.health > near_front.max_health - 25,
		"no big instant hit — damage is the burn itself")
	_free_world(w)


func test_flames_ignite_enemy_ground_vehicles() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _armed_ram(w)
	var foe: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 1, ram.position + Vector3(0, 0, 3.0)) as SiegeEngine
	ram.order_attack(foe)
	var ticks: int = 0
	while not foe.is_burning() and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(foe.is_burning(), "an enemy catapult in the cone catches fire")
	while foe.state != Unit.State.DEAD and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(foe.state == Unit.State.DEAD, "the burning wreck is destroyed")
	_free_world(w)


func test_full_burst_stages_a_building_once() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _armed_ram(w)
	# Enemy hut with its near edge ~3 m in front of the nozzle.
	var cell: Vector2i = w.nav.world_to_cell(ram.position + Vector3(0, 0, 6.0))
	var hut: Building = w.building_manager.place(HUT_SCENE, w.tribe1, cell, 0, true)
	check(hut != null, "enemy hut placed in front of the ram")
	ram.order_attack_building(hut)
	# Run until the first full burst has been delivered (flame 1 s + checks).
	var ticks: int = 0
	while hut.destruction_stage() < 1 and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(hut.destruction_stage() == 1,
		"one full flame burst = exactly one destruction stage (grace-window rule)")
	# Immediately after the first stage no second stage may exist yet — the
	# reload gap (1.5 s at full crew, 3 s at 1) must not leak extra stages.
	for i in range(5):
		_tick_world(w)
	check(hut.destruction_stage() == 1, "no second stage during the reload")
	_free_world(w)


func test_flames_ignite_trees() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _armed_ram(w)
	var tree_cell: Vector2i = w.nav.world_to_cell(ram.position + Vector3(0, 0, 3.0))
	var tree = w.tree_manager.spawn_tree(tree_cell, 2)
	check(tree != null and not tree.is_burning(), "tree starts unburnt")
	var victim: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, ram.position + Vector3(0.4, 0, 3.0))
	ram.order_attack(victim)
	var ticks: int = 0
	while not tree.is_burning() and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(tree.is_burning(), "a tree in the flame cone catches fire")
	_free_world(w)


# --- Crew distraction immunity --------------------------------------------------------

func test_ram_crew_ignores_ranged_harassment() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _spawn_ram(w, 0, w.nav.cell_to_world(Vector2i(60, 60)))
	var crew: Brave = _board_crew(w, ram)
	# Ranged pressure from 6 m: the crew must NOT counter-attack.
	var shooter: Unit = w.unit_manager.spawn_unit(
		FIREWARRIOR_SCENE, 1, ram.position + Vector3(-6.0, 0, 0))
	crew._maybe_retaliate(shooter)
	check(crew.state == Unit.State.CREW,
		"ram crew ignores ranged harassment (stays at its post)")
	check(crew.attack_target == null, "no counter-target was locked")
	# Direct melee pressure: the crew defends itself.
	var brawler: Unit = w.unit_manager.spawn_unit(
		WARRIOR_SCENE, 1, crew.position + Vector3(0.8, 0, 0))
	crew._maybe_retaliate(brawler)
	check(crew.attack_target == brawler, "direct melee IS retaliated")
	_free_world(w)


func test_catapult_crew_still_retaliates_vs_ranged() -> void:
	var w: Dictionary = _make_world()
	var engine: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, w.nav.cell_to_world(Vector2i(60, 60))) as SiegeEngine
	var crew: Brave = _board_crew(w, engine)
	var shooter: Unit = w.unit_manager.spawn_unit(
		FIREWARRIOR_SCENE, 1, engine.position + Vector3(-6.0, 0, 0))
	crew._maybe_retaliate(shooter)
	check(crew.attack_target == shooter,
		"catapult crew behaviour is unchanged (retaliates vs ranged)")
	_free_world(w)


# --- Cooldown & movement gates ----------------------------------------------------------

func test_flame_cooldown_scales_with_crew() -> void:
	check(is_inf(FireRam.flame_cooldown_for_crew(0)), "0 crew cannot fire")
	check_near(FireRam.flame_cooldown_for_crew(1), 3.0, "1 crew reloads slowly")
	check_near(FireRam.flame_cooldown_for_crew(4), 1.5, "full crew reloads fastest")
	check(FireRam.flame_cooldown_for_crew(2) < 3.0, "more crew -> faster")


func test_one_crew_moves_and_fires() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _spawn_ram(w, 0, w.nav.cell_to_world(Vector2i(60, 60)))
	ram.order_move(w.nav.cell_to_world(Vector2i(70, 60)))
	check(ram.state != Unit.State.MOVE, "an unmanned ram never moves")
	_board_crew(w, ram)
	ram.order_move(w.nav.cell_to_world(Vector2i(70, 60)))
	check(ram.state == Unit.State.MOVE, "ONE crew member drives the ram")
	# ... and the same single member fires (covered by the flame tests above,
	# which run with exactly one boarded brave).
	_free_world(w)


# --- Destruction & capture (shared vehicle rules) ---------------------------------------

func test_ram_burns_and_sinks_and_is_capturable() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _spawn_ram(w, 0, w.nav.cell_to_world(Vector2i(60, 60)))
	# Unmanned ram: an enemy brave boards it -> ownership switches.
	var raider: Brave = _board_crew(w, ram, 1)
	check(ram.tribe_id == 1, "boarding an unmanned ram takes it over")
	check(raider.siege_boarded, "the raider serves the captured ram")
	# Fire destroys it: ignite -> burns -> sinks; the crew survives.
	ram.ignite(ram.position)
	check(ram.is_burning(), "fire sets the wooden ram alight")
	var ticks: int = 0
	while ram.state != Unit.State.DEAD and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(ram.state == Unit.State.DEAD, "the burnt ram is destroyed")
	check(raider.state != Unit.State.DEAD, "the crew survives and is released")
	check(raider.siege_engine == null, "crew membership was cleared")
	_free_world(w)
