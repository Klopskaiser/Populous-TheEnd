extends TestBase

## Headless tests for phase 5a: training buildings turn braves into combat units
## and send them to the rally point. Flat walkable terrain, managers wired like
## in Main, all nodes created outside the scene tree and freed manually.

const TICK: float = 0.05
const MAX_TICKS: int = 4000

const WARRIOR_CAMP_SCENE: PackedScene = preload("res://scenes/buildings/warrior_camp.tscn")
const TEMPLE_SCENE: PackedScene = preload("res://scenes/buildings/temple.tscn")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
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
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe] as Array[Tribe], tm, wpm)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um, wpm)
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(nav, bm, um, tm)
	return {
		"td": td, "nav": nav, "tribe": tribe,
		"unit_manager": um, "building_manager": bm,
		"tree_manager": tm, "wood_pile_manager": wpm, "commands": tc,
	}


func _free_world(w: Dictionary) -> void:
	w.commands.free()
	w.tree_manager.free()
	w.wood_pile_manager.free()
	w.building_manager.free()
	w.unit_manager.free()


## Ticks all still-registered units and the given building until `done` returns
## true or MAX_TICKS is reached. Returns the tick count used.
func _run(w: Dictionary, building: Building, done: Callable) -> int:
	for i in range(MAX_TICKS):
		if done.call():
			return i
		for unit in w.unit_manager.units.duplicate():
			if is_instance_valid(unit):
				unit.tick(TICK)
		building.tick(TICK)
	return MAX_TICKS


func _spawn_brave(w: Dictionary, cell: Vector2i) -> Brave:
	return w.unit_manager.spawn_unit(BRAVE_SCENE, 0, w.nav.cell_to_world(cell)) as Brave


func _warriors(w: Dictionary) -> Array[Unit]:
	var result: Array[Unit] = []
	for u: Unit in w.tribe.units:
		if u is Warrior:
			result.append(u)
	return result


# --- Tests -------------------------------------------------------------------------

## A brave ordered to train walks in, disappears and comes out as a warrior;
## population stays constant (one in, one out) and the type has changed.
func test_train_produces_combat_unit() -> void:
	var w: Dictionary = _make_world()
	var camp: WarriorCamp = w.building_manager.place(
		WARRIOR_CAMP_SCENE, w.tribe, Vector2i(30, 30), 0, true) as WarriorCamp
	camp.rally_point = w.nav.cell_to_world(Vector2i(40, 30))
	var brave: Brave = _spawn_brave(w, Vector2i(30, 38))

	check(w.tribe.population() == 1, "population is 1 before training")
	w.commands.order_train(camp, [brave] as Array[Unit])
	check(brave.state == Unit.State.TRAIN, "brave switches to TRAIN state")

	var used: int = _run(w, camp, func() -> bool: return _warriors(w).size() >= 1)
	check(used < MAX_TICKS, "a warrior was produced within the tick budget")
	check(w.tribe.population() == 1, "population unchanged after the swap (1 in, 1 out)")
	check(not is_instance_valid(brave) or brave.state == Unit.State.DEAD \
		or brave not in w.tribe.units, "the original brave is gone from the tribe")
	var warriors: Array[Unit] = _warriors(w)
	check(warriors.size() == 1, "exactly one warrior exists")
	check(warriors[0].tribe_id == 0, "the warrior belongs to the same tribe")
	_free_world(w)


## The produced unit heads for the rally point; changing the rally point affects
## units finished afterwards.
func test_trained_unit_walks_to_rally() -> void:
	var w: Dictionary = _make_world()
	var camp: WarriorCamp = w.building_manager.place(
		WARRIOR_CAMP_SCENE, w.tribe, Vector2i(30, 30), 0, true) as WarriorCamp
	var rally_a: Vector3 = w.nav.cell_to_world(Vector2i(42, 30))
	camp.rally_point = rally_a
	var brave1: Brave = _spawn_brave(w, Vector2i(30, 38))
	w.commands.order_train(camp, [brave1] as Array[Unit])
	_run(w, camp, func() -> bool: return _warriors(w).size() >= 1)
	var w1: Unit = _warriors(w)[0]
	check(w1.waypoint_queue.size() >= 1, "first warrior has a move target")
	check(Vector2(w1.waypoint_queue[0].x, w1.waypoint_queue[0].z).distance_to(
		Vector2(rally_a.x, rally_a.z)) < 1.5, "first warrior heads to rally A")

	# Move the rally point, train a second brave.
	var rally_b: Vector3 = w.nav.cell_to_world(Vector2i(20, 30))
	camp.rally_point = rally_b
	var brave2: Brave = _spawn_brave(w, Vector2i(30, 38))
	w.commands.order_train(camp, [brave2] as Array[Unit])
	_run(w, camp, func() -> bool: return _warriors(w).size() >= 2)
	var w2: Unit = null
	for u: Unit in _warriors(w):
		if u != w1:
			w2 = u
	check(w2 != null, "a second warrior was produced")
	check(Vector2(w2.waypoint_queue[0].x, w2.waypoint_queue[0].z).distance_to(
		Vector2(rally_b.x, rally_b.z)) < 1.5, "second warrior heads to the new rally B")
	_free_world(w)


## Without any admitted braves the building produces nothing.
func test_idle_building_produces_nothing() -> void:
	var w: Dictionary = _make_world()
	var camp: WarriorCamp = w.building_manager.place(
		WARRIOR_CAMP_SCENE, w.tribe, Vector2i(30, 30), 0, true) as WarriorCamp
	camp.rally_point = w.nav.cell_to_world(Vector2i(40, 30))
	for i in range(200):
		camp.tick(TICK)
	check(_warriors(w).size() == 0, "no warrior is produced without trainees")
	check(camp.production_progress() < 0.0, "idle training building reports no progress")
	_free_world(w)


## Braves line up: only one is admitted at a time; the rest wait in the world
## (visible queue) until the bay frees up.
func test_queue_one_at_a_time() -> void:
	var w: Dictionary = _make_world()
	var camp: WarriorCamp = w.building_manager.place(
		WARRIOR_CAMP_SCENE, w.tribe, Vector2i(30, 30), 0, true) as WarriorCamp
	camp.rally_point = w.nav.cell_to_world(Vector2i(40, 30))
	var braves: Array[Unit] = []
	for i in range(3):
		braves.append(_spawn_brave(w, Vector2i(28 + i, 38)))
	w.commands.order_train(camp, braves)

	var got: int = _run(w, camp, func() -> bool: return camp.trainee != null)
	check(got < MAX_TICKS, "the front brave enters the building")
	check(camp.trainee != null, "exactly one brave is inside training")
	var waiting: int = 0
	for u: Unit in w.unit_manager.units:
		if u is Brave:
			waiting += 1
	check(waiting == 2, "the other two braves wait in the world (visible queue)")
	check(camp.incoming.size() == 2, "two braves still queued")
	_free_world(w)


## The queue is a single-file line hugging the building edge, starting left of
## the entrance (for a south-facing entrance: toward -x, along constant z).
func test_queue_slots_along_edge() -> void:
	var w: Dictionary = _make_world()
	var camp: WarriorCamp = w.building_manager.place(
		WARRIOR_CAMP_SCENE, w.tribe, Vector2i(30, 30), 0, true) as WarriorCamp
	var s0: Vector3 = camp.queue_slot_world(0)
	var s1: Vector3 = camp.queue_slot_world(1)
	var s2: Vector3 = camp.queue_slot_world(2)
	var entrance_x: float = (30.0 + 35.0) * 0.5 * TerrainData.CELL_SIZE  # footprint centre x
	check(s0.x < entrance_x, "front slot is left of the entrance (-x for south)")
	check(absf(s0.z - s1.z) < 0.01 and absf(s1.z - s2.z) < 0.01,
		"early slots run along the entrance edge (constant z)")
	check(absf(Vector2(s0.x, s0.z).distance_to(Vector2(s1.x, s1.z))
		- TrainingBuilding.QUEUE_SPACING) < 0.1, "slot 0->1 spacing matches")
	check(absf(Vector2(s1.x, s1.z).distance_to(Vector2(s2.x, s2.z))
		- TrainingBuilding.QUEUE_SPACING) < 0.1, "slot 1->2 spacing matches")
	check(s1.x < s0.x and s2.x < s1.x, "the line advances leftward along the edge")
	_free_world(w)


## A hut whose rally point sits ON a training building sends freshly spawned
## braves straight into that building's training queue (phase 5d).
func test_hut_rally_on_camp_trains_brave() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.building_manager.place(
		HUT_SCENE, w.tribe, Vector2i(30, 30), 0, true) as Hut
	var camp: WarriorCamp = w.building_manager.place(
		WARRIOR_CAMP_SCENE, w.tribe, Vector2i(42, 30), 0, true) as WarriorCamp
	hut.rally_point = camp.center_world()
	check(hut.rally_training_building() == camp,
		"the rally point resolves to the warrior camp")

	# A hut only produces while manned (phase 7i); the crew counts as population.
	for i in range(Hut.CREW_CAPACITY):
		hut.admit_crew(_spawn_brave(w, Vector2i(28, 28)))
	var base: int = w.tribe.population()

	# Tick the hut until it spawns a fresh (non-crew) brave.
	for i in range(int(Hut.SPAWN_INTERVAL / TICK) * 2 + 5):
		hut.tick(TICK)
		if w.tribe.population() > base:
			break
	check(w.tribe.population() == base + 1, "the manned hut spawned a brave")
	var brave: Brave = null
	for u: Unit in w.tribe.units:
		if u is Brave and u.state != Unit.State.GARRISON:   # skip hidden crew
			brave = u as Brave
	check(brave != null and brave.state == Unit.State.TRAIN,
		"the new brave heads for training instead of the rally spot")
	check(brave in camp.incoming, "the brave is queued at the camp")

	# And it actually becomes a warrior.
	var used: int = _run(w, camp, func() -> bool: return _warriors(w).size() >= 1)
	check(used < MAX_TICKS, "the rally-trained brave graduates into a warrior")
	_free_world(w)


## Multiple queued braves are trained FIFO, one after another.
func test_queue_fifo() -> void:
	var w: Dictionary = _make_world()
	var camp: WarriorCamp = w.building_manager.place(
		WARRIOR_CAMP_SCENE, w.tribe, Vector2i(30, 30), 0, true) as WarriorCamp
	camp.rally_point = w.nav.cell_to_world(Vector2i(40, 30))
	var braves: Array[Unit] = []
	for i in range(3):
		braves.append(_spawn_brave(w, Vector2i(28 + i, 38)))
	check(w.tribe.population() == 3, "three braves before training")
	w.commands.order_train(camp, braves)

	var used: int = _run(w, camp, func() -> bool: return _warriors(w).size() >= 3)
	check(used < MAX_TICKS, "all three braves finished training")
	check(_warriors(w).size() == 3, "three warriors produced")
	check(w.tribe.population() == 3, "population constant across all swaps")
	_free_world(w)
