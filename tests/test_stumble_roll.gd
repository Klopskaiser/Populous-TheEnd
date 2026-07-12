extends TestBase

## Headless tests for the phase-8.2 roll bugfixes:
## 1. A harmless downhill STUMBLE keeps the unit's orders — movers resume
##    their route, workers resume their task (the brave drops its carried
##    wood and picks the pile back up); combat rolls still clear orders.
## 2. Trapped rolls are no longer immortal: deferred lethal damage fires once
##    the minimum tumble ran out, no-progress rolls end early, and both rolls
##    and throws have a hard time cap.

const TICK: float = 1.0 / 30.0

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


## Flat highland with a deep, narrow V-groove along vertex column x = 50 —
## the earthquake-sink shape: a roll in the groove keeps sampling a steep
## fall line forever and (before the fix) never ended.
func _groove_terrain() -> TerrainData:
	var td: TerrainData = _flat_terrain(20.0)
	for vz in range(td.verts):
		td.set_vertex_height(50, vz, 5.0)
	return td


func _make_world(td: TerrainData = null) -> Dictionary:
	if td == null:
		td = _flat_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var tribe0: Tribe = Tribe.new(0)
	var tribe1: Tribe = Tribe.new(1)
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe0, tribe1] as Array[Tribe], tm, wpm)
	return {"td": td, "nav": nav, "tribe0": tribe0, "tribe1": tribe1,
		"unit_manager": um, "tree_manager": tm, "wood_pile_manager": wpm}


func _free_world(w: Dictionary) -> void:
	w.tree_manager.free()
	w.wood_pile_manager.free()
	w.unit_manager.free()


func _run(w: Dictionary, seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		for u in w.unit_manager.units.duplicate():
			if is_instance_valid(u):
				u.tick(TICK)
		w.unit_manager.tick(TICK)
		t += TICK


# --- Stumble keeps orders -------------------------------------------------------

## A mover that stumbles downhill resumes its route to the ordered waypoint.
func test_stumble_resumes_move_order() -> void:
	var w: Dictionary = _make_world()
	var mover: Unit = w.unit_manager.spawn_unit(
		WARRIOR_SCENE, 0, w.nav.cell_to_world(Vector2i(40, 40)))
	var goal: Vector3 = w.nav.cell_to_world(Vector2i(52, 40))
	mover.order_move(goal)
	_run(w, 0.5)
	check(mover.state == Unit.State.MOVE, "mover is on its way")

	mover.start_roll(Vector3(0, 0, 1), Unit.MINI_ROLL_DURATION, 0.0, true)   # stumble
	check(mover.state == Unit.State.ROLL, "the stumble knocks it over")
	check(not mover.waypoint_queue.is_empty(), "the route survives the stumble")
	_run(w, 1.0)
	check(mover.state == Unit.State.MOVE, "the mover resumes its route")
	_run(w, 6.0)
	check(Vector2(mover.position.x - goal.x, mover.position.z - goal.z).length() < 1.5,
		"…and still arrives at the ordered waypoint")
	_free_world(w)


## A combat roll (no stumble flag) still clears the route — original rules.
func test_combat_roll_still_clears_orders() -> void:
	var w: Dictionary = _make_world()
	var mover: Unit = w.unit_manager.spawn_unit(
		WARRIOR_SCENE, 0, w.nav.cell_to_world(Vector2i(40, 40)))
	mover.order_move(w.nav.cell_to_world(Vector2i(52, 40)))
	_run(w, 0.5)
	mover.start_roll(Vector3(0, 0, 1), Unit.MINI_ROLL_DURATION)
	check(mover.waypoint_queue.is_empty(), "a combat roll clears the route")
	_run(w, 1.0)
	check(mover.state == Unit.State.IDLE, "the unit gets up idle")
	_free_world(w)


## A combat hit that EXTENDS a harmless stumble turns it into a real combat
## roll: the saved orders are gone.
func test_combat_hit_during_stumble_clears_orders() -> void:
	var w: Dictionary = _make_world()
	var mover: Unit = w.unit_manager.spawn_unit(
		WARRIOR_SCENE, 0, w.nav.cell_to_world(Vector2i(40, 40)))
	mover.order_move(w.nav.cell_to_world(Vector2i(52, 40)))
	_run(w, 0.5)
	mover.start_roll(Vector3(0, 0, 1), Unit.MINI_ROLL_DURATION, 0.0, true)
	check(not mover.waypoint_queue.is_empty(), "stumble keeps the route at first")
	mover.start_roll(Vector3(0, 0, 1), Unit.MINI_ROLL_DURATION)   # e.g. a fireball
	check(mover.waypoint_queue.is_empty(), "the combat extension clears the route")
	_run(w, 1.5)
	check(mover.state == Unit.State.IDLE, "the unit gets up idle after the combat roll")
	_free_world(w)


## A stumbling wood carrier drops its load but keeps the chop task: the claim
## survives, and the dropped pile lies at its feet for the pickup.
func test_stumbling_brave_drops_wood_and_resumes_task() -> void:
	var w: Dictionary = _make_world()
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(40, 40))) as Brave
	var tree: TreeResource = w.tree_manager.spawn_tree(Vector2i(46, 40))
	check(tree != null, "test tree spawned")
	brave.order_chop(tree)
	check(brave.state == Unit.State.GATHER, "brave is chopping")
	brave.carried_wood = 2   # simulate a load mid-fetch

	brave.start_roll(Vector3(0, 0, 1), Unit.MINI_ROLL_DURATION, 0.0, true)   # stumble
	check(brave.carried_wood == 0, "the stumble drops the carried wood")
	check(not w.wood_pile_manager.piles.is_empty(), "the wood lies as a pile")
	check(brave.task == Brave.Task.CHOP and brave.task_tree == tree,
		"the chop task survives the stumble")
	_run(w, 1.0)
	check(brave.state == Unit.State.GATHER, "the brave resumes its task")
	var pile: WoodPile = w.wood_pile_manager.piles[0]
	check(Vector2(pile.position.x - brave.position.x,
		pile.position.z - brave.position.z).length() < 6.0,
		"the dropped pile lies within the brave's working reach")
	_free_world(w)


# --- Trapped rolls are mortal ------------------------------------------------------

## The earthquake-sink case: a unit rolling in a steep V-groove took damage
## but never died (deferred death + a roll that never ends). Now it dies.
func test_lethal_damage_in_trapped_roll_kills() -> void:
	var w: Dictionary = _make_world(_groove_terrain())
	var victim: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, Vector3(50.5, 0.0, 30.5))   # in the groove
	victim.start_roll(Vector3(1, 0, 0), 8.0)   # long tumble against the walls
	check(victim.state == Unit.State.ROLL, "the victim tumbles in the groove")
	victim.take_damage(100000)
	check(victim.state == Unit.State.ROLL, "death is deferred while rolling")
	_run(w, 6.0)
	check(victim.state == Unit.State.DEAD,
		"the trapped roll no longer defers death forever")
	_free_world(w)


## A HEALTHY unit trapped in the groove stands back up once the roll makes no
## progress (instead of tumbling in place for the full duration).
func test_trapped_roll_without_damage_ends_early() -> void:
	var w: Dictionary = _make_world(_groove_terrain())
	var victim: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, Vector3(50.5, 0.0, 30.5))
	victim.start_roll(Vector3(1, 0, 0), 20.0)
	_run(w, 6.0)
	check(victim.state != Unit.State.ROLL, "the no-progress roll ended early")
	check(victim.state != Unit.State.DEAD or victim.health <= 0,
		"an (almost) unhurt unit survives it")
	# Roll damage ticks a little; the unit must be alive and standing.
	check(victim.state == Unit.State.IDLE, "the unit stands back up")
	_free_world(w)


## A throw that never lands (carrier that never releases) ends at the hard
## cap: the unit dies and drops out of the sky as a corpse.
func test_endless_throw_dies_at_time_cap() -> void:
	var w: Dictionary = _make_world()
	var victim: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(40, 40)))
	var carrier: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, w.nav.cell_to_world(Vector2i(60, 60)))
	victim.throw_airborne(Vector3(0, 8, 0))
	victim.throw_carrier = carrier   # never releases (the bug shape)
	victim.position.y += 5.0
	for i in range(int(Unit.THROWN_MAX_DURATION * 2.0) + 4):
		victim.tick(0.5)
	check(victim.state == Unit.State.DEAD, "the endless throw ends as a corpse")
	check(victim.position.y <= w.td.get_height(victim.position.x, victim.position.z) + 0.1,
		"the corpse lies on the ground, not in the sky")
	_free_world(w)
