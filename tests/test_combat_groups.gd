extends TestBase

## Headless tests for phase 8.2: the 1-vs-N combat groups (CombatGroup) with
## the original-style pairing rules (1v1 split, surplus up to 1v3, second row,
## latecomer pull, no 2v2), the group min-distance, the scan fixes (enemy-only
## candidate budget, no NW direction bias -> no mass drift) and the
## reachability fixes (unreachable combat targets are dropped, attack-move
## takes a partial path, the AI skips unreachable plots).

const TICK: float = 0.1
const SIM_TICK: float = 1.0 / 30.0
const MAX_TICKS: int = 400

const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


## Flat terrain with a raised square plateau: its interior stays flat (and
## thus walkable) but the rim is steeper than MAX_SLOPE — walkable, yet
## unreachable from below (the Bergpass situation).
func _plateau_terrain(x0: int, z0: int, x1: int, z1: int) -> TerrainData:
	var td: TerrainData = _flat_terrain()
	for vz in range(z0, z1 + 1):
		for vx in range(x0, x1 + 1):
			td.set_vertex_height(vx, vz, 20.0)
	return td


## Flat terrain split in two by an unwalkable wall band at x = wall_x.
func _walled_terrain(wall_x: int) -> TerrainData:
	var td: TerrainData = _flat_terrain()
	for vz in range(td.verts):
		td.set_vertex_height(wall_x, vz, 20.0)
		td.set_vertex_height(wall_x + 1, vz, 20.0)
	return td


func _make_world(td: TerrainData = null) -> Dictionary:
	if td == null:
		td = _flat_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var tribe0: Tribe = Tribe.new(0)
	var tribe1: Tribe = Tribe.new(1)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe0, tribe1] as Array[Tribe])
	return {"td": td, "nav": nav, "tribe0": tribe0, "tribe1": tribe1, "unit_manager": um}


func _free_world(w: Dictionary) -> void:
	w.unit_manager.free()


func _spawn(w: Dictionary, scene: PackedScene, tribe_id: int, at: Vector2,
		tanky: bool = false) -> Unit:
	var u: Unit = w.unit_manager.spawn_unit(scene, tribe_id, Vector3(at.x, 0.0, at.y))
	if tanky:
		u.max_health = 1000000
		u.health = 1000000
	return u


func _run(w: Dictionary, units: Array, done: Callable, ticks: int = MAX_TICKS) -> int:
	for i in range(ticks):
		if done.call():
			return i
		for u in units:
			if is_instance_valid(u) and u.state != Unit.State.DEAD:
				u.tick(TICK)
		w.unit_manager.tick(TICK)
	return ticks


# --- Group formation & second row ------------------------------------------------

## 6 attackers on one target: exactly 3 fight, 3 wait in the second row; a
## dying attacker's slot is back-filled from the waiters immediately.
func test_six_on_one_three_fight_three_wait() -> void:
	var w: Dictionary = _make_world()
	var target: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30), true)
	var attackers: Array = []
	for i in range(6):
		var a: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(28 + i, 32))
		a.order_attack(target)
		attackers.append(a)
	var g = target.combat_group
	check(g != null and g.defender == target, "the target defends its group")
	check(g.attackers.size() == Unit.MAX_MELEE_ATTACKERS,
		"exactly 3 attackers hold a slot")
	check(g.waiters.size() == 3, "3 attackers wait in the second row")
	for a in attackers:
		check(a.combat_group == g, "every attacker is bound to the ONE group")

	# Kill a slot holder: the front row is back-filled from the second row.
	var holder: Unit = g.attackers[0]
	holder.take_damage(100000)
	check(g.attackers.size() == Unit.MAX_MELEE_ATTACKERS,
		"a waiter back-filled the freed slot immediately")
	check(g.waiters.size() == 2, "second row shrank by the promoted waiter")
	_free_world(w)


## Waiters stand on the second-row ring near the fight (not glued to the
## target, not wandering off).
func test_waiters_hold_the_second_row_ring() -> void:
	var w: Dictionary = _make_world()
	var target: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30), true)
	var units: Array = []
	for i in range(5):
		var a: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(26 + i * 2, 34), true)
		a.order_attack(target)
		units.append(a)
	_run(w, units, func() -> bool: return false, 80)
	var g = target.combat_group
	check(g != null and g.waiters.size() == 2, "two waiters in the second row")
	for wt in g.waiters:
		var d: float = Vector2(wt.position.x - target.position.x,
			wt.position.z - target.position.z).length()
		check(d <= Unit.MELEE_WAIT_RADIUS + 1.2,
			"waiter stands near the fight (%.2f m)" % d)
		check(d >= Unit.MELEE_RANGE * 0.5, "waiter does not stack on the defender")
	_free_world(w)


# --- Pairing rules -----------------------------------------------------------------

## 2v2 decomposes into two separate 1v1 groups — never one 2v2 clump.
func test_2v2_splits_into_two_1v1() -> void:
	var w: Dictionary = _make_world()
	var r1: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector2(30, 30), true)
	var r2: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector2(33, 30), true)
	var b1: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(30, 33), true)
	var b2: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(33, 33), true)
	var all: Array = [r1, r2, b1, b2]
	_run(w, all, func() -> bool:
		return b1.attack_target != null and b2.attack_target != null \
			and r1.attack_target != null and r2.attack_target != null, 20)
	var groups: Dictionary = {}
	for u in all:
		check(u.combat_group != null, "every unit is bound to a group")
		groups[u.combat_group] = true
	check(groups.size() == 2, "2v2 split into exactly two groups (got %d)" % groups.size())
	for g in groups:
		check(g.attackers.size() == 1, "each group is a clean 1v1")
		check(g.waiters.is_empty(), "no waiters in a 1v1")
		check(g.defender.tribe_id != g.attackers[0].tribe_id,
			"defender and attacker are enemies")
	_free_world(w)


## 2v4: the two of the outnumbered side each defend a 1v2 (surplus spreads
## over the existing fights instead of piling into one 1v3 + 1v1).
func test_2v4_splits_into_1v2_plus_1v2() -> void:
	var w: Dictionary = _make_world()
	var r1: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector2(30, 30), true)
	var r2: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector2(36, 30), true)
	var blues: Array = []
	for at in [Vector2(29, 32), Vector2(37, 32), Vector2(30, 33), Vector2(36, 33)]:
		blues.append(_spawn(w, WARRIOR_SCENE, 0, at, true))
	var all: Array = [r1, r2] + blues
	_run(w, all, func() -> bool:
		for b in blues:
			if b.attack_target == null:
				return false
		return true, 30)
	for red in [r1, r2]:
		var g = red.combat_group
		check(g != null and g.defender == red, "the outnumbered unit defends")
		check(g.attackers.size() == 2,
			"each defender has exactly 2 attackers (got %d)" % g.attackers.size())
		check(g.waiters.is_empty(), "no second row needed in a 2v4")
	_free_world(w)


## Latecomer of the outnumbered side pulls an attacker out of the full group:
## 1v3 becomes 1v2 + a fresh 1v1, and the pulled attacker retargets its puller.
func test_latecomer_pulls_attacker_from_full_group() -> void:
	var w: Dictionary = _make_world()
	var d: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector2(30, 30), true)
	for i in range(3):
		var b: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(28 + i * 2, 32), true)
		b.order_attack(d)
	check(d.active_melee_attacker_count() == 3, "the defender starts in a 1v3")

	var late: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector2(31, 33), true)
	late.tick(TICK)   # one idle scan: engages a blue attacker -> pull
	check(late.attack_target != null, "the latecomer engaged an enemy")
	var pulled: Unit = late.attack_target
	check(d.combat_group.attackers.size() == 2, "the old group shrank to a 1v2")
	check(pulled.combat_group != null and pulled.combat_group.defender == pulled,
		"the pulled attacker defends a fresh group")
	check(pulled.combat_group.attackers.has(late), "the latecomer fights it 1v1")
	check(pulled.attack_target == late, "the pulled attacker retargets its puller")
	_free_world(w)


## Structural invariant after a mixed brawl: every group holds at most 3
## attackers, every member points back at its group, and every defender
## belongs to no other group (no 2v2 possible).
func test_group_invariants_hold_in_a_brawl() -> void:
	var w: Dictionary = _make_world()
	var units: Array = []
	for i in range(8):
		units.append(_spawn(w, WARRIOR_SCENE, i % 2,
			Vector2(28 + (i % 4) * 2, 29 + (i / 4) * 4), true))
	_run(w, units, func() -> bool: return false, 120)
	var um: UnitManager = w.unit_manager
	check(not um.combat_groups.is_empty(), "the brawl produced registered groups")
	for g in um.combat_groups:
		if not g.is_alive():
			continue
		check(g.attackers.size() <= Unit.MAX_MELEE_ATTACKERS,
			"never more than 3 attackers per group")
		check(g.defender.combat_group == g, "the defender belongs to its own group")
		for m in g.attackers + g.waiters:
			check(m.combat_group == g, "members point back at their group")
			check(m.tribe_id != g.defender.tribe_id, "members are the defender's enemies")
	for u in units:
		if u.combat_group != null:
			var g2 = u.combat_group
			var roles: int = 0
			if g2.defender == u:
				roles += 1
			if g2.attackers.has(u):
				roles += 1
			if g2.waiters.has(u):
				roles += 1
			check(roles == 1, "a unit holds exactly one role in exactly one group")
	_free_world(w)


# --- Group min-distance --------------------------------------------------------------

## Two adjacent fights are pushed apart until their anchors keep the minimum
## group distance — the battle frays into separate brawls instead of a blob.
func test_adjacent_fights_keep_min_distance() -> void:
	seed(1337)   # trim the strike/shove/roll randomness between runs
	var w: Dictionary = _make_world()
	var r1: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector2(30, 30), true)
	var r2: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector2(31, 30), true)
	var b1: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(30, 31), true)
	var b2: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(31, 31), true)
	b1.order_attack(r1)
	b2.order_attack(r2)
	var units: Array = [r1, r2, b1, b2]
	_run(w, units, func() -> bool: return false, 200)
	var g1 = r1.combat_group
	var g2 = r2.combat_group
	check(g1 != null and g2 != null and g1 != g2, "two separate fights")
	var d: float = Vector2(g1.anchor.x - g2.anchor.x, g1.anchor.z - g2.anchor.z).length()
	check(d >= UnitManager.COMBAT_GROUP_MIN_DIST - 0.3,
		"anchors keep the minimum group distance (%.2f m)" % d)
	_free_world(w)


# --- Scan fixes ------------------------------------------------------------------------

## The enemy scan finds a target although the scanner stands inside a dense
## pack of FRIENDS (the old capped query returned 24 friends and went blind).
func test_scan_finds_enemy_inside_friend_blob() -> void:
	var w: Dictionary = _make_world()
	var scanner: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(30, 30))
	for i in range(40):
		_spawn(w, WARRIOR_SCENE, 0, Vector2(29 + (i % 7) * 0.35, 29 + (i / 7) * 0.35))
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(35, 30))
	w.unit_manager.tick(TICK)   # refresh the spatial hash
	var found: Unit = scanner._scan_for_enemy(Unit.AGGRO_RADIUS)
	check(found == enemy, "the scan sees the enemy through the friend blob")
	_free_world(w)


## Mirror-symmetric armies (north vs south): the mass centroid must not drift
## systematically, and after contact a solid share of the melee units actually
## FIGHTS (guards against "everyone stands around" / the old north drift).
func test_symmetric_battle_no_drift_and_high_melee_share() -> void:
	seed(1337)   # trim the strike/shove/roll randomness between runs
	var w: Dictionary = _make_world()
	var units: Array = []
	for i in range(36):
		var x: float = 25.0 + float(i % 12) * 1.2
		var z: float = 30.0 + float(i / 12) * 1.2
		var b: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(x, z), true)
		b.order_move(Vector3(x, 0, z + 14.0), false, true)   # attack-move north->south
		units.append(b)
		# Mirrored red unit (reflection at z = 40).
		var r: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector2(x, 80.0 - z), true)
		r.order_move(Vector3(x, 0, 80.0 - z - 14.0), false, true)
		units.append(r)
	var start_z: float = _centroid_z(units)
	var max_drift: float = 0.0
	var best_share: float = 0.0
	for t in range(400):
		for u in units:
			u.tick(SIM_TICK)
		w.unit_manager.tick(SIM_TICK)
		max_drift = maxf(max_drift, absf(_centroid_z(units) - start_z))
		var fighting: int = 0
		var in_attack: int = 0
		for u in units:
			if u.state == Unit.State.ATTACK:
				in_attack += 1
				if u._in_melee:
					fighting += 1
		if in_attack >= 20:
			best_share = maxf(best_share, float(fighting) / float(in_attack))
	# Tolerance: strikes/shoves/rolls are random (and the per-unit instance-id
	# stagger varies between runs), so the centroid random-walks a little —
	# up to ~3.7 m observed on green code. The SYSTEMATIC bias this guards
	# against measured -35 m in the full battle and 5+ m in this small setup.
	check(max_drift < 4.5,
		"no systematic drift of the mass centroid (max %.2f m)" % max_drift)
	check(best_share >= 0.35,
		"a solid share of the engaged units really fights (best %.0f%%)" % (best_share * 100.0))
	_free_world(w)


func _centroid_z(units: Array) -> float:
	var z: float = 0.0
	for u in units:
		z += u.position.z
	return z / float(units.size())


# --- Reachability (Bergpass) ------------------------------------------------------------

## An enemy on a walkable but unreachable plateau: the attacker drops the
## target (and remembers it) instead of pressing against the cliff forever.
func test_unreachable_combat_target_is_dropped() -> void:
	var w: Dictionary = _make_world(_plateau_terrain(44, 26, 52, 34))
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(48.5, 30.5), true)
	var warrior: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(41.5, 30.5))
	check(w.nav.is_cell_walkable(Vector2i(48, 30)), "the plateau top is walkable")
	check(not w.nav.is_cell_walkable(Vector2i(43, 30)), "the plateau rim is not")
	var start: Vector2 = Vector2(warrior.position.x, warrior.position.z)
	_run(w, [warrior], func() -> bool: return false, 60)
	var moved: float = Vector2(warrior.position.x, warrior.position.z).distance_to(start)
	check(moved < 1.0, "the warrior does not run against the cliff (moved %.2f m)" % moved)
	check(not warrior._unreach_targets.is_empty(),
		"the unreachable target is remembered")
	check(warrior.attack_target == null or warrior.state != Unit.State.ATTACK
		or not warrior._has_path(), "no permanent chase against the wall")
	_free_world(w)


## Attack-move at a target behind an unwalkable wall: the unit takes a PARTIAL
## path (as far as reachable) and settles — no oscillation, no idle-at-spawn.
func test_attack_move_takes_partial_path() -> void:
	var w: Dictionary = _make_world(_walled_terrain(60))
	var u: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(40.5, 30.5))
	u.order_move(Vector3(80.5, 0, 30.5), false, true)   # aggressive: partial allowed
	_run(w, [u], func() -> bool: return u.state == Unit.State.IDLE, 380)
	check(u.position.x > 45.0, "the unit marched toward the wall (x=%.1f)" % u.position.x)
	check(u.position.x < 61.0, "…but never crossed it")
	# Passive move to the same unreachable point still fails cleanly (IDLE, no path).
	var p: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(40.5, 34.5))
	p.order_move(Vector3(80.5, 0, 34.5))
	w.unit_manager.tick(TICK)   # drain the path queue
	check(p.state == Unit.State.IDLE and not p._has_path(),
		"a passive move to an unreachable point is dropped")
	_free_world(w)


## The AI plot search skips walkable-but-unreachable plateau plots (and caches
## the expensive negative), picking a reachable plot instead.
func test_ai_plot_search_skips_unreachable_plateau() -> void:
	var w: Dictionary = _make_world(_plateau_terrain(40, 40, 56, 56))
	var commands: TribeCommands = TribeCommands.new()
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(w.td, w.nav, w.unit_manager, null)
	commands.setup(w.nav, bm, w.unit_manager)
	var ai: AIController = AIController.new()
	ai.setup(w.tribe1, commands, w.unit_manager, bm, null, w.nav, Vector2i(30, 48))
	check(not ai._plot_reachable(Vector2i(47, 47)), "plateau plot is rejected")
	check(ai._unreachable_plots.has(Vector2i(47, 47)), "…and cached as unreachable")
	check(ai._plot_reachable(Vector2i(34, 48)), "a plot on the mainland passes")
	var probe: Building = HUT_SCENE.instantiate() as Building
	var fp: Vector2i = probe.footprint
	probe.free()
	# Anchor at the plateau's edge: candidates mix plateau plots (rejected as
	# unreachable) and mainland plots (pass) — the search must pick a mainland one.
	var plot: Vector2i = ai._find_supplied_plot(Vector2i(38, 48), fp)
	check(plot.x >= 0, "a plot was found near the plateau anchor")
	var on_plateau: bool = plot.x >= 40 and plot.x <= 56 - fp.x \
		and plot.y >= 40 and plot.y <= 56 - fp.y
	check(not on_plateau, "the chosen plot is not on the unreachable plateau")
	ai.free()
	commands.free()
	bm.free()
	_free_world(w)
