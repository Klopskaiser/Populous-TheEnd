extends TestBase

## Phase 7b: move/attack split (passive move vs. attack-move), fleeing with
## the throttled self-defence rule, the brave's small idle aggro radius,
## idle 6-pack regrouping, the anti-stacking escape and the queue windings
## around training buildings.

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const WARRIOR_CAMP_SCENE: PackedScene = preload("res://scenes/buildings/warrior_camp.tscn")


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
	return {
		"td": td, "nav": nav, "tribes": tribes,
		"unit_manager": um, "building_manager": bm,
		"tree_manager": tm, "wood_pile_manager": wpm,
	}


func _free_world(w: Dictionary) -> void:
	w.tree_manager.free()
	w.wood_pile_manager.free()
	w.building_manager.free()
	w.unit_manager.free()


## Runs world + unit ticks so throttled scans (0.25 s + offset) get their turn.
func _run_ticks(w: Dictionary, units: Array[Unit], seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		w.unit_manager.tick(0.1)
		for unit in units:
			if is_instance_valid(unit):
				unit.tick(0.1)
		t += 0.1


# --- Move/attack split -----------------------------------------------------------

func test_passive_move_ignores_enemies() -> void:
	var w: Dictionary = _make_world()
	var mover: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 1,
		w.nav.cell_to_world(Vector2i(60, 60)))
	# Passive enemy bystander well inside the 8 m aggro radius (a brave at
	# 4 m: outside ITS 3 m idle radius, so it stays put).
	w.unit_manager.spawn_unit(BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(64, 60)))
	mover.order_move(w.nav.cell_to_world(Vector2i(80, 60)), false, false)
	_run_ticks(w, w.unit_manager.units, 1.2)
	check(mover.state == Unit.State.MOVE,
		"a passive move marches past enemies in aggro range")
	check(mover.attack_target == null, "no target was acquired")
	_free_world(w)


func test_attack_move_engages_enemies() -> void:
	var w: Dictionary = _make_world()
	var mover: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 1,
		w.nav.cell_to_world(Vector2i(60, 60)))
	w.unit_manager.spawn_unit(BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(64, 60)))
	mover.order_move(w.nav.cell_to_world(Vector2i(80, 60)), false, true)
	_run_ticks(w, w.unit_manager.units, 1.2)
	check(mover.state == Unit.State.ATTACK,
		"an attack-move engages enemies on the way")
	_free_world(w)


# --- Fleeing ---------------------------------------------------------------------

func test_flee_breaks_off_and_self_defends() -> void:
	var w: Dictionary = _make_world()
	var runner: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 1,
		w.nav.cell_to_world(Vector2i(60, 60)))
	var chaser: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 0,
		w.nav.cell_to_world(Vector2i(60, 61)))
	runner.order_attack(chaser)
	check(runner.state == Unit.State.ATTACK, "fight started")

	# The flee order (passive move) breaks off the fight immediately.
	runner.order_move(w.nav.cell_to_world(Vector2i(80, 60)), false, false)
	check(runner.state == Unit.State.MOVE, "the flee order breaks off the fight")
	check(runner.attack_target == null, "the target is dropped")

	# Melee hits while fleeing: only every FLEE_RETALIATE_HITS-th pulls the
	# runner back into the fight (the chaser stands right next to it).
	for i in range(Unit.FLEE_RETALIATE_HITS - 1):
		runner.take_damage(1, chaser)
		check(runner.state == Unit.State.MOVE,
			"hit %d of the flee rule does not stop the escape" % (i + 1))
	runner.take_damage(1, chaser)
	check(runner.state == Unit.State.ATTACK,
		"the %d. melee hit forces self-defence" % Unit.FLEE_RETALIATE_HITS)
	_free_world(w)


func test_flee_ignores_ranged_pressure() -> void:
	var w: Dictionary = _make_world()
	var runner: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 1,
		w.nav.cell_to_world(Vector2i(60, 60)))
	var sniper: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 0,
		w.nav.cell_to_world(Vector2i(70, 60)))   # 10 m away — not melee
	runner.order_move(w.nav.cell_to_world(Vector2i(80, 60)), false, false)
	for i in range(Unit.FLEE_RETALIATE_HITS * 2):
		runner.take_damage(1, sniper)
	check(runner.state == Unit.State.MOVE,
		"ranged hits never break a flee (only melee pressure counts)")
	_free_world(w)


# --- Brave idle aggro (3 m) --------------------------------------------------------

func test_brave_idle_aggro_radius() -> void:
	var w: Dictionary = _make_world()
	var guard: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1,
		w.nav.cell_to_world(Vector2i(60, 60)))
	var far_enemy: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 0,
		w.nav.cell_to_world(Vector2i(65, 60)))   # 5 m: outside 3 m
	_run_ticks(w, [guard] as Array[Unit], 1.0)
	check(guard.state == Unit.State.IDLE,
		"an enemy at 5 m is outside the brave's idle aggro radius")

	var near_enemy: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 0,
		w.nav.cell_to_world(Vector2i(62, 60)))   # ~2 m: inside 3 m
	# Guards scan at a relaxed ~1 s interval — give it two full cycles.
	_run_ticks(w, [guard] as Array[Unit], 3.0)
	check(guard.state == Unit.State.ATTACK and guard.attack_target == near_enemy,
		"an enemy walking within 3 m gets attacked by the idle brave")
	check(is_instance_valid(far_enemy), "the far enemy is untouched")
	_free_world(w)


# --- Idle 6-pack regrouping ---------------------------------------------------------

func test_idle_regroup_step() -> void:
	var units: Array[Brave] = []
	for i in range(3):
		var brave: Brave = Brave.new()
		brave.state = Unit.State.IDLE
		brave.idle_seconds = UnitManager.IDLE_REGROUP_DELAY + 1.0
		units.append(brave)
	units[0].position = Vector3(0, 0, 0)
	units[1].position = Vector3(1.6, 0, 0)
	units[2].position = Vector3(0, 0, 1.6)

	var step: Vector2 = UnitManager.regroup_step(units[0],
		[units[1], units[2]] as Array[Unit])
	check(step != Vector2.ZERO, "an idle unit with idle mates drifts")
	check(step.length() <= UnitManager.IDLE_REGROUP_STEP + 0.001,
		"the drift is a tiny step (max %s m)" % UnitManager.IDLE_REGROUP_STEP)
	check(step.x > 0.0 and step.y > 0.0, "the drift points at the group centre")

	check(UnitManager.regroup_step(units[0], [] as Array[Unit]) == Vector2.ZERO,
		"a lone unit stays where it is")

	units[1].idle_seconds = 0.0   # freshly busy neighbour does not count
	units[2].state = Unit.State.MOVE
	check(UnitManager.regroup_step(units[0],
		[units[1], units[2]] as Array[Unit]) == Vector2.ZERO,
		"busy or freshly-idle neighbours do not attract")

	# Already packed tightly: no more drifting (the pack stands calm).
	units[1].idle_seconds = 10.0
	units[1].state = Unit.State.IDLE
	units[1].position = Vector3(0.4, 0, 0)
	check(UnitManager.regroup_step(units[0],
		[units[1]] as Array[Unit]) == Vector2.ZERO,
		"a formed pack stops drifting")

	for brave in units:
		brave.free()


# --- Anti-stacking escape -----------------------------------------------------------

func test_overlap_escape_cell() -> void:
	var w: Dictionary = _make_world()
	var pos: Vector3 = w.nav.cell_to_world(Vector2i(60, 60))
	for i in range(3):
		w.unit_manager.spawn_unit(BRAVE_SCENE, 1, pos)   # fully stacked
	w.unit_manager.tick(0.05)   # refresh the spatial hash
	var cell: Vector2i = w.unit_manager.find_free_cell_near(pos)
	check(cell.x >= 0, "a free nearby cell is found")
	check(cell != w.nav.world_to_cell(pos), "the escape cell is a different cell")
	check(w.nav.is_cell_walkable(cell), "the escape cell is walkable")
	_free_world(w)


# --- Queue windings around training buildings ----------------------------------------

func test_queue_slot_windings() -> void:
	var w: Dictionary = _make_world()
	var camp: TrainingBuilding = w.building_manager.place(
		WARRIOR_CAMP_SCENE, w.tribes[1], Vector2i(60, 60), 0, true) as TrainingBuilding
	var centre: Vector3 = camp.center_world()

	# Chebyshev distance from the building centre: winding 0 slots hug the
	# building; a high index lies on a farther winding.
	var d0: float = _cheby(camp.queue_slot_world(0), centre)
	var d40: float = _cheby(camp.queue_slot_world(40), centre)
	check(d40 > d0 + 0.5,
		"slot 40 sits on an outer winding (%.2f m vs %.2f m)" % [d40, d0])

	# No two of the first 30 slots collapse onto the same spot.
	var slots: Array[Vector3] = []
	for i in range(30):
		slots.append(camp.queue_slot_world(i))
	var min_dist: float = INF
	for a in range(slots.size()):
		for b in range(a + 1, slots.size()):
			min_dist = minf(min_dist, slots[a].distance_to(slots[b]))
	check(min_dist > 0.4,
		"the first 30 queue slots stay distinct (min spacing %.2f m)" % min_dist)
	_free_world(w)


func _cheby(pos: Vector3, centre: Vector3) -> float:
	return maxf(absf(pos.x - centre.x), absf(pos.z - centre.z))


# --- Double-click kind filter ---------------------------------------------------------

func test_double_click_kind_filter() -> void:
	var braves: Array[Unit] = []
	var warriors: Array[Unit] = []
	for i in range(2):
		braves.append(Brave.new())
	for i in range(3):
		warriors.append(WARRIOR_SCENE.instantiate() as Unit)
	var all_units: Array[Unit] = braves + warriors
	var picked: Array[Unit] = SelectionManager.filter_units_of_kind(all_units, &"warrior")
	check(picked.size() == 3, "only the warriors match the kind filter")
	warriors[0].state = Unit.State.DEAD
	picked = SelectionManager.filter_units_of_kind(all_units, &"warrior")
	check(picked.size() == 2, "dead units are filtered out")
	for unit in all_units:
		unit.free()
