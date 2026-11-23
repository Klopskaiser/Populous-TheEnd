extends TestBase

## Invisible braves (user report 2026-11-23): a tribe without any visible follower
## was not defeated and its reincarnation circle never sank — a brave was alive in
## tribe.units but out of the world (never ticked, drawn or attacked); after loading
## a save it turned up. Path found: Brave._interrupt_tasks released the slot of a
## brave housed IN a workshop or forester without putting it back into the world.
## Plus the safety net UnitManager._sweep_orphans for any other such path.

const GameStateScript: GDScript = preload("res://scripts/core/game_state.gd")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WORKSHOP_SCENE: PackedScene = preload("res://scenes/buildings/workshop.tscn")
const FORESTER_SCENE: PackedScene = preload("res://scenes/buildings/forester.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const CAMP_SCENE: PackedScene = preload("res://scenes/buildings/warrior_camp.tscn")
const SITE_SCENE: PackedScene = preload("res://scenes/buildings/reincarnation_site.tscn")
const TICK: float = 0.1


func _make_world() -> Dictionary:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = 5.0
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
	return {"td": td, "nav": nav, "tribes": tribes, "tm": tm, "wpm": wpm, "um": um, "bm": bm}


func _free_world(w: Dictionary) -> void:
	w.tm.free()
	w.wpm.free()
	w.bm.free()
	w.um.free()


## Ticks the manager past one orphan sweep (no unit ticks: nothing else moves).
func _sweep(w: Dictionary) -> void:
	for i in range(int(UnitManager.ORPHAN_SWEEP_INTERVAL / TICK) + 2):
		w.um.tick(TICK)


func _registered(w: Dictionary, u: Unit) -> bool:
	return u.in_world and u._idx >= 0 and u._idx < w.um.units.size() and w.um.units[u._idx] == u


func test_an_order_brings_a_workshop_worker_back_into_the_world() -> void:
	var w: Dictionary = _make_world()
	var ws: Workshop = w.bm.place(WORKSHOP_SCENE, w.tribes[0], Vector2i(50, 50), 0, true) as Workshop
	var b: Brave = w.um.spawn_unit(BRAVE_SCENE, 0, ws.edge_spawn_position()) as Brave
	b.order_workshop(ws)
	ws.admit_worker(b)
	check(not b.in_world and b.workshop_inside and b.is_held_out_of_world(),
		"the worker is housed in the workshop")
	b.order_move(ws.edge_spawn_position() + Vector3(8, 0, 0))
	check(_registered(w, b), "an order brings him back into the world (registered)")
	check(not b.workshop_inside and not ws.occupants.has(b), "and frees his slot")
	check(b.state == Unit.State.MOVE, "he walks off")
	_free_world(w)


func test_an_order_brings_a_forester_worker_back_into_the_world() -> void:
	var w: Dictionary = _make_world()
	var f: Forester = w.bm.place(FORESTER_SCENE, w.tribes[0], Vector2i(50, 50), 0, true) as Forester
	var b: Brave = w.um.spawn_unit(BRAVE_SCENE, 0, f.edge_spawn_position()) as Brave
	b.order_forester(f)
	f.admit_worker(b)
	check(not b.in_world and b.forester_inside and b.is_held_out_of_world(),
		"the worker is housed in the forester")
	b.order_move(f.edge_spawn_position() + Vector3(8, 0, 0))
	check(_registered(w, b), "an order brings him back into the world")
	check(not b.forester_inside and not f.occupants.has(b), "and frees his slot")
	_free_world(w)


func test_the_sweep_returns_an_orphan_and_the_tribe_can_be_defeated_again() -> void:
	var w: Dictionary = _make_world()
	var site: Building = w.bm.place(SITE_SCENE, w.tribes[1], Vector2i(80, 80), 0, true)
	var third: Tribe = Tribe.new(2)
	w.tribes.append(third)   # two more tribes stay in, so the match is not decided
	w.um.spawn_unit(BRAVE_SCENE, 0, Vector3(30.5, 5.0, 30.5))
	w.um.spawn_unit(BRAVE_SCENE, 2, Vector3(100.5, 5.0, 30.5))
	var b: Brave = w.um.spawn_unit(BRAVE_SCENE, 1, Vector3(60.5, 5.0, 60.5)) as Brave
	# The broken state: out of the world, held by nothing.
	w.um.remove_from_world(b)
	b._set_state(Unit.State.MOVE)
	check(not b.is_held_out_of_world(), "nothing holds him")
	var gs: Node = GameStateScript.new()
	gs.tribes = w.tribes
	gs.start_win_tracking()
	gs.check_defeats()
	check(not w.tribes[1].eliminated, "an orphan keeps his tribe in the match")
	_sweep(w)
	check(w.um.orphans_returned == 1, "the sweep found one orphan")
	check(_registered(w, b) and b.state == Unit.State.IDLE, "he is back in the world, idle")
	b.take_damage(9999)
	gs.check_defeats()
	check(w.tribes[1].eliminated, "killed, his tribe is out")
	check(site.health <= 0, "and its reincarnation circle is razed")
	gs.free()
	_free_world(w)


## The case the 4-AI diagnosis caught (diag_defeat_orphans, Seenland seed 3): a
## brave thrown and struck dead in mid-air (doomed) while out of the world. It
## never ticks, so it never lands and never dies — the sweep lets it die.
func test_a_doomed_orphan_dies_and_a_doomed_zombie_too() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[0]
	var b: Brave = w.um.spawn_unit(BRAVE_SCENE, 0, Vector3(60.5, 5.0, 60.5)) as Brave
	b.throw_airborne(Vector3(1, 6, 0), 0, true)
	b.take_damage(9999)
	check(b.doomed and b.state == Unit.State.THROWN, "doomed in mid-air")
	w.um.remove_from_world(b)
	check(tribe.units.has(b) and _defeated(tribe) == false, "and still counts for its tribe")
	_sweep(w)
	check(b.state == Unit.State.DEAD and not tribe.units.has(b), "the sweep lets him die")
	check(tribe.units_lost == 1, "a loss in the statistics")
	# In the world, doomed but out of his fall (a state change took him out of it).
	var z: Brave = w.um.spawn_unit(BRAVE_SCENE, 0, Vector3(70.5, 5.0, 60.5)) as Brave
	z.throw_airborne(Vector3(1, 6, 0), 0, true)
	z.take_damage(9999)
	z._set_state(Unit.State.IDLE)
	check(z.doomed and z.state == Unit.State.IDLE, "a doomed body standing idle")
	_sweep(w)
	check(z.state == Unit.State.DEAD and not tribe.units.has(z), "the sweep lets the zombie die")
	_free_world(w)


static func _defeated(tribe: Tribe) -> bool:
	return GameStateScript.is_tribe_defeated(tribe)


func test_the_sweep_drops_a_unit_that_died_out_of_the_world() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[0]
	var b: Brave = w.um.spawn_unit(BRAVE_SCENE, 0, Vector3(60.5, 5.0, 60.5)) as Brave
	w.um.remove_from_world(b)
	b.take_damage(9999)   # dies with nobody listening to its died signal
	check(b.state == Unit.State.DEAD and tribe.units.has(b), "dead, but still in the tribe")
	_sweep(w)
	check(not tribe.units.has(b) and tribe.population() == 0, "the sweep drops him from the tribe")
	check(w.um.orphans_returned == 0, "a dead unit is no orphan to bring back")
	_free_world(w)


func test_the_sweep_leaves_held_units_alone() -> void:
	var w: Dictionary = _make_world()
	var t0: Tribe = w.tribes[0]
	var hut: Hut = w.bm.place(HUT_SCENE, t0, Vector2i(40, 40), 0, true) as Hut
	var crew: Unit = w.um.spawn_unit(BRAVE_SCENE, 0, hut.edge_spawn_position())
	check(hut.admit_crew(crew), "hut crew admitted")
	var ws: Workshop = w.bm.place(WORKSHOP_SCENE, t0, Vector2i(60, 40), 0, true) as Workshop
	var worker: Brave = w.um.spawn_unit(BRAVE_SCENE, 0, ws.edge_spawn_position()) as Brave
	worker.order_workshop(ws)
	ws.admit_worker(worker)
	var camp: TrainingBuilding = w.bm.place(CAMP_SCENE, t0, Vector2i(40, 70), 0, true) as TrainingBuilding
	var trainee: Brave = w.um.spawn_unit(BRAVE_SCENE, 0, camp.edge_spawn_position()) as Brave
	trainee.order_train(camp)
	trainee.train_reached_slot = true
	camp._admit_front()
	check(camp.trainee == trainee, "the trainee is inside")
	_sweep(w)
	check(w.um.orphans_returned == 0, "no orphan among them")
	check(not crew.in_world and not worker.in_world and not trainee.in_world,
		"crew, worker and trainee stay inside")
	_free_world(w)
