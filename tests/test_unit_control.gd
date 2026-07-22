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
	# Passive enemy bystander well inside the 8 m aggro radius but 4 m OFF the
	# march route: it must stay outside ITS OWN 3 m idle radius for the whole
	# walk (on-route it would idle-aggro the passing mover and the RNG brawl
	# made this test flaky), so it stays put.
	w.unit_manager.spawn_unit(BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(64, 64)))
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
	# Poll for the engagement instead of asserting a single instant: once the
	# brawl starts, a shove can knock the mover into a transient mini-ROLL
	# right at a fixed check time (flaky) — engaging at all is the contract.
	var engaged: bool = false
	for i in range(40):
		_run_ticks(w, w.unit_manager.units, 0.1)
		if mover.state == Unit.State.ATTACK:
			engaged = true
			break
	check(engaged, "an attack-move engages enemies on the way")
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


# --- Idle 6-packs (sticky groups) -----------------------------------------------------

func test_idle_group_formation() -> void:
	var w: Dictionary = _make_world()
	var mates: Array[Unit] = []
	for i in range(3):
		var brave: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1,
			w.nav.cell_to_world(Vector2i(60 + i * 2, 60)))
		mates.append(brave)
	# Long idle + several manager passes: a group forms, members walk to
	# their slots and settle there.
	for brave in mates:
		brave.idle_seconds = UnitManager.IDLE_REGROUP_DELAY + 1.0
	_run_ticks(w, mates, 4.0)
	var group = mates[0].idle_group
	check(group != null, "long-idle mates found a group")
	for brave in mates:
		check(brave.idle_group == group, "all three joined the SAME group")
	check((group as UnitManager.IdleGroup).members.size() == 3,
		"the group tracks its three members")
	_free_world(w)


func test_idle_group_adopts_settled_formation_in_place() -> void:
	var w: Dictionary = _make_world()
	# Four braves already standing tight (like a landed group move order).
	var anchor: Vector3 = w.nav.cell_to_world(Vector2i(60, 60))
	var offsets: Array[Vector3] = [Vector3.ZERO, Vector3(0.7, 0, 0),
		Vector3(0, 0, 0.7), Vector3(0.7, 0, 0.7)]
	var mates: Array[Unit] = []
	var before: Array[Vector3] = []
	for offset in offsets:
		var brave: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, anchor + offset)
		brave.idle_seconds = UnitManager.IDLE_REGROUP_DELAY + 1.0
		mates.append(brave)
		before.append(brave.position)
	_run_ticks(w, mates, 2.0)
	var group = mates[0].idle_group
	check(group != null, "the settled cluster was adopted as a group")
	for i in range(mates.size()):
		check(mates[i].idle_group == group, "all settled mates share the group")
		check(mates[i].state == Unit.State.IDLE,
			"adoption never issues move orders (unit %d stays idle)" % i)
		check(mates[i].position.distance_to(before[i]) < 0.05,
			"unit %d did not move (was already perfectly placed)" % i)
	_free_world(w)


func test_idle_group_membership_is_sticky() -> void:
	var w: Dictionary = _make_world()
	# An existing FULL group...
	var full: UnitManager.IdleGroup = UnitManager.IdleGroup.new()
	full.anchor = w.nav.cell_to_world(Vector2i(60, 60))
	full.next_slot = TribeCommands.GROUP_SIZE
	var members: Array[Unit] = []
	for i in range(TribeCommands.GROUP_SIZE):
		var brave: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1,
			full.anchor + TribeCommands.MEMBER_OFFSETS[i])
		brave.idle_seconds = 10.0
		brave.idle_group = full
		full.members.append(brave)
		members.append(brave)
	# ...and one loose long-idle brave right next to it.
	var loner: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1,
		w.nav.cell_to_world(Vector2i(62, 60)))
	loner.idle_seconds = UnitManager.IDLE_REGROUP_DELAY + 1.0

	_run_ticks(w, [loner] as Array[Unit], 3.0)
	check(loner.idle_group == null,
		"no NEW group forms right next to an existing (full) one")
	check(loner.state == Unit.State.IDLE, "the loner just stays put")
	for brave in members:
		check(brave.idle_group == full, "members never switch groups")
	_free_world(w)


func test_idle_group_join_walks_to_slot() -> void:
	var w: Dictionary = _make_world()
	var group: UnitManager.IdleGroup = UnitManager.IdleGroup.new()
	group.anchor = w.nav.cell_to_world(Vector2i(60, 60))
	var walker: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1,
		w.nav.cell_to_world(Vector2i(63, 60)))
	w.unit_manager.join_idle_group(walker, group)
	check(walker.idle_group == group, "the unit joined the group")
	check(walker.state == Unit.State.MOVE,
		"joining is an ACTIVE walk to the slot (no sliding)")
	_run_ticks(w, [walker] as Array[Unit], 3.0)
	check(walker.state == Unit.State.IDLE, "the member settles on its slot")
	check(walker.position.distance_to(group.anchor) < 1.5,
		"the member stands at the group anchor")
	_free_world(w)


func test_idle_group_prune() -> void:
	var w: Dictionary = _make_world()
	var group: UnitManager.IdleGroup = UnitManager.IdleGroup.new()
	group.anchor = w.nav.cell_to_world(Vector2i(60, 60))
	var members: Array[Unit] = []
	for i in range(3):
		var brave: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1,
			group.anchor + TribeCommands.MEMBER_OFFSETS[i])
		brave.idle_seconds = 10.0
		brave.idle_group = group
		group.members.append(brave)
		members.append(brave)
	# One member gets ordered far away -> dropped on the next prune.
	members[2].position = group.anchor + Vector3(20, 0, 0)
	members[2]._sync_soa_pos()
	w.unit_manager._prune_idle_group(group)
	check(members[2].idle_group == null, "a member ordered far away is dropped")
	check(group.members.size() == 2, "the group keeps the two remaining members")
	# Shrinking to one dissolves the group entirely.
	members[1].position = group.anchor + Vector3(20, 0, 0)
	members[1]._sync_soa_pos()
	w.unit_manager._prune_idle_group(group)
	check(members[0].idle_group == null and group.members.is_empty(),
		"a one-member group dissolves")
	_free_world(w)


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


func test_move_order_registers_groups_up_front() -> void:
	var w: Dictionary = _make_world()
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(w.nav, w.building_manager, w.unit_manager, w.tree_manager)
	var squad: Array[Unit] = []
	for i in range(8):
		squad.append(w.unit_manager.spawn_unit(BRAVE_SCENE, 1,
			w.nav.cell_to_world(Vector2i(40 + i * 2, 40))))
	var target: Vector3 = w.nav.cell_to_world(Vector2i(70, 70))
	tc.order_move(squad, target)

	# Groups exist IMMEDIATELY (units still walking): 6 + 2.
	var groups: Dictionary = {}
	for unit in squad:
		check(unit.idle_group != null, "every mover is already a group member")
		groups[unit.idle_group] = groups.get(unit.idle_group, 0) + 1
	check(groups.size() == 2, "8 movers split into two groups (6 + 2)")
	check(groups.values().has(6) and groups.values().has(2),
		"group sizes match the formation batches")

	# Walkers count by their DESTINATION: pruning drops nobody en route.
	var full_group: UnitManager.IdleGroup = null
	for group in groups:
		if (group as UnitManager.IdleGroup).members.size() == 6:
			full_group = group
	w.unit_manager._prune_idle_group(full_group)
	check(full_group.members.size() == 6,
		"members en route to the formation are not pruned")
	check(full_group.is_full(), "the 6-pack is full — nobody else can dock on")

	# A member ordered somewhere far away is dropped on the next prune.
	var deserter: Unit = full_group.members[0]
	deserter.order_move(w.nav.cell_to_world(Vector2i(20, 20)))
	deserter.idle_group = full_group   # order_move alone must not clear it...
	w.unit_manager._prune_idle_group(full_group)
	check(not (deserter in full_group.members),
		"...but pruning drops a member whose destination is far away")

	tc.free()
	_free_world(w)


func test_no_regrouping_after_formation_landed() -> void:
	var w: Dictionary = _make_world()
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(w.nav, w.building_manager, w.unit_manager, w.tree_manager)
	var squad: Array[Unit] = []
	for i in range(6):
		squad.append(w.unit_manager.spawn_unit(BRAVE_SCENE, 1,
			w.nav.cell_to_world(Vector2i(56 + i * 2, 56))))
	tc.order_move(squad, w.nav.cell_to_world(Vector2i(64, 64)))
	var group = squad[0].idle_group
	# Let them arrive, then idle far past the (long) regroup delay.
	_run_ticks(w, squad, 6.0)
	for unit in squad:
		unit.idle_seconds = UnitManager.IDLE_REGROUP_DELAY + 5.0
	var landed: Array[Vector3] = []
	for unit in squad:
		landed.append(unit.position)
	_run_ticks(w, squad, 3.0)
	for i in range(squad.size()):
		check(squad[i].idle_group == group,
			"a landed formation keeps its original group (unit %d)" % i)
		check(squad[i].position.distance_to(landed[i]) < 0.1,
			"no re-grouping movement after landing (unit %d)" % i)
	tc.free()
	_free_world(w)


# --- Combat pursuit stays on walkable ground -------------------------------------------

func test_combat_step_blocked_by_water() -> void:
	# Flat island with a sunken strip (below sea level) at x >= 68.
	var td: TerrainData = _flat_terrain()
	for vz in range(0, TerrainData.SIZE + 1):
		for vx in range(68, 74):
			td.set_vertex_height(vx, vz, 0.0)
	var nav: NavGrid = NavGrid.new(td)
	var tribes: Array[Tribe] = [Tribe.new(0), Tribe.new(1)]
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, tribes)
	var chaser: Unit = um.spawn_unit(WARRIOR_SCENE, 1, nav.cell_to_world(Vector2i(64, 60)))
	# Direct combat step toward a point across the water: must stop at the shore.
	for i in range(200):
		chaser._step_toward(nav.cell_to_world(Vector2i(80, 60)), 0.1)
	check(chaser.position.x < 68.5,
		"the direct combat chase stops at the water (x = %.1f)" % chaser.position.x)
	check(nav.is_cell_walkable(nav.world_to_cell(chaser.position)),
		"the chaser still stands on walkable ground")
	um.free()


func test_wait_near_stands_when_close() -> void:
	var w: Dictionary = _make_world()
	var target: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 0,
		w.nav.cell_to_world(Vector2i(60, 60)))
	var waiter: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 1,
		target.position + Vector3(1.5, 0, 0))   # already near the fight
	var before: Vector3 = waiter.position
	for i in range(30):
		waiter._wait_near(target, 0.1)
	check(waiter.position.distance_to(before) < 0.01,
		"a waiter already near the fight stands still (no ring-point chasing)")

	var far_waiter: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 1,
		target.position + Vector3(6.0, 0, 0))
	var far_before: Vector3 = far_waiter.position
	for i in range(10):
		far_waiter._wait_near(target, 0.1)
	check(far_waiter.position.distance_to(far_before) > 0.5,
		"a waiter too far out closes up on the fight")
	_free_world(w)


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
