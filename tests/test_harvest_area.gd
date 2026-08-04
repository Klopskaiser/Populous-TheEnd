extends TestBase

## Phase 10e part 1: the harvest rectangle (key B). A standing AREA order makes
## braves fell every tree inside a world-XZ rectangle in several loads, and an
## accepted fell order blinks a white confirmation ring around the trees.
##
## The critical assertion is test_area_job_skips_trees_on_another_island together
## with test_area_job_reaches_a_remote_grove: TreeManager.claim_area_tree searches
## from the WALKER, not from the area centre, because best_tree derives its walk
## budget from the search radius. A radius taken from the area's own diagonal
## would cap the walk at a few metres and kill every order on a distant grove.

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const DEPOT_SCENE: PackedScene = preload("res://scenes/buildings/wood_depot.tscn")

const TICK: float = 1.0 / 30.0


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for vz in range(td.size + 1):
		for vx in range(td.size + 1):
			td.set_vertex_height(vx, vz, h)
	return td


## Plateau world from test_tree_priority: high level (9 m) for x <= 40, low
## level (3 m) for x >= 46, hard cliff between them — except a walkable ramp at
## z 60..70. Both levels are ONE island, connected only by that ramp.
func _plateau_terrain() -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for vz in range(td.size + 1):
		for vx in range(td.size + 1):
			var h: float
			if vx <= 40:
				h = 9.0
			elif vx >= 46:
				h = 3.0
			elif vz >= 60 and vz <= 70:
				h = 9.0 - float(vx - 40)
			else:
				h = 9.0 if vx <= 42 else 3.0
			td.set_vertex_height(vx, vz, h)
	return td


func _make_world(td: TerrainData = null) -> Dictionary:
	var terrain: TerrainData = td if td != null else _flat_terrain()
	var nav: NavGrid = NavGrid.new(terrain)
	var tribe: Tribe = Tribe.new(0)
	var tm: TreeManager = TreeManager.new()
	tm.setup(terrain, nav)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(terrain)
	var um: UnitManager = UnitManager.new()
	um.setup(terrain, nav, [tribe] as Array[Tribe], tm, wpm)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(terrain, nav, um, wpm)
	var commands: TribeCommands = TribeCommands.new()
	commands.setup(nav, bm, um, tm)
	return {"td": terrain, "nav": nav, "tribe": tribe, "tm": tm, "wpm": wpm,
		"um": um, "bm": bm, "commands": commands}


func _free_world(w: Dictionary) -> void:
	w.bm.free()
	w.um.free()
	w.wpm.free()
	w.tm.free()


func _brave_at(w: Dictionary, cell: Vector2i) -> Brave:
	return w.um.spawn_unit(BRAVE_SCENE, 0, w.nav.cell_to_world(cell)) as Brave


## World-XZ rectangle covering the cell range [from, to] inclusive, with a
## half-cell margin so trees sitting on cell centres are safely inside.
func _cell_rect(w: Dictionary, from: Vector2i, to: Vector2i) -> Rect2:
	var a: Vector3 = w.nav.cell_to_world(from)
	var b: Vector3 = w.nav.cell_to_world(to)
	var lo: Vector2 = Vector2(minf(a.x, b.x), minf(a.z, b.z)) - Vector2(0.5, 0.5)
	var hi: Vector2 = Vector2(maxf(a.x, b.x), maxf(a.z, b.z)) + Vector2(0.5, 0.5)
	return Rect2(lo, hi - lo)


# --- Command layer -------------------------------------------------------------

func test_order_chop_area_tasks_only_braves() -> void:
	var w: Dictionary = _make_world()
	w.tm.spawn_tree(Vector2i(20, 20), 3)
	var brave: Brave = _brave_at(w, Vector2i(10, 20))
	var warrior: Unit = w.um.spawn_unit(WARRIOR_SCENE, 0, w.nav.cell_to_world(Vector2i(11, 20)))
	var area: Rect2 = _cell_rect(w, Vector2i(18, 18), Vector2i(24, 24))
	var units: Array[Unit] = [brave, warrior] as Array[Unit]
	check(w.commands.order_chop_area(units, area) == 1,
		"only the brave is put on the area job")
	check(brave.has_chop_area(), "the brave holds the standing area order")
	check(not warrior.has_method("has_chop_area"),
		"a warrior has no area order at all (non-braves are ignored, not moved)")
	check(warrior.state != Unit.State.MOVE,
		"the warrior is NOT marched into the grove")
	brave._interrupt_tasks()
	_free_world(w)


func test_oversized_area_is_clamped() -> void:
	# Pure static maths — no world needed.
	var huge: Rect2 = TribeCommands.clamp_harvest_area(Rect2(0.0, 0.0, 400.0, 400.0))
	check(is_equal_approx(huge.size.x, Balance.HARVEST_AREA_MAX_SIDE)
		and is_equal_approx(huge.size.y, Balance.HARVEST_AREA_MAX_SIDE),
		"a whole-map drag is clamped to HARVEST_AREA_MAX_SIDE")
	check(huge.get_center().is_equal_approx(Vector2(200.0, 200.0)),
		"clamping keeps the centre of the drawn rectangle")
	var tiny: Rect2 = TribeCommands.clamp_harvest_area(Rect2(5.0, 5.0, 0.5, 0.5))
	check(tiny.size == Vector2.ZERO,
		"below the minimum on BOTH sides it counts as a stray click -> rejected")
	var strip: Rect2 = TribeCommands.clamp_harvest_area(Rect2(5.0, 5.0, 0.5, 30.0))
	check(is_equal_approx(strip.size.x, Balance.HARVEST_AREA_MIN_SIDE)
		and is_equal_approx(strip.size.y, 30.0),
		"a thin strip along a tree row only gets its short side widened")


func test_unusable_quad_falls_back_to_the_rect_hull() -> void:
	# Uneven terrain can raycast the four drag corners into a self-crossing quad;
	# the order then uses the plain hull (a superset), never nothing.
	var rect: Rect2 = Rect2(0.0, 0.0, 10.0, 10.0)
	var crossed: PackedVector2Array = PackedVector2Array([
		Vector2(0, 0), Vector2(10, 10), Vector2(10, 0), Vector2(0, 10)])
	check(not TreeManager.is_convex_quad(crossed), "the crossed quad is rejected")
	var shape: Array = TribeCommands.harvest_job_shape(rect, crossed)
	check((shape[0] as Rect2).size.is_equal_approx(Vector2(10.0, 10.0)),
		"the rectangle survives")
	check((shape[1] as PackedVector2Array).is_empty(),
		"the unusable quad is dropped -> plain rectangle")
	var square: PackedVector2Array = PackedVector2Array([
		Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	check(TreeManager.is_convex_quad(square), "a proper square is convex")
	check(not (TribeCommands.harvest_job_shape(rect, square)[1] as PackedVector2Array).is_empty(),
		"a usable quad is kept")


# --- Area geometry -------------------------------------------------------------

func test_area_job_claims_only_trees_inside_the_rect() -> void:
	var w: Dictionary = _make_world()
	var inside_a: TreeResource = w.tm.spawn_tree(Vector2i(20, 20), 3)
	var inside_b: TreeResource = w.tm.spawn_tree(Vector2i(22, 22), 3)
	var outside: TreeResource = w.tm.spawn_tree(Vector2i(40, 40), 3)
	var area: Rect2 = _cell_rect(w, Vector2i(18, 18), Vector2i(24, 24))
	var found: Array[TreeResource] = w.tm.area_trees(area)
	check(found.size() == 2, "area_trees returns exactly the two trees inside")
	check(inside_a in found and inside_b in found, "both inside trees are listed")
	check(not (outside in found), "the tree outside the rectangle is not listed")
	# Claiming walks the same path and never leaves the area.
	var walker: Vector3 = w.nav.cell_to_world(Vector2i(10, 20))
	var picked: TreeResource = w.tm.claim_area_tree(area, PackedVector2Array(), self, walker)
	check(picked == inside_a or picked == inside_b, "claim_area_tree stays inside")
	_free_world(w)


func test_area_job_ignores_trees_outside_a_rotated_quad() -> void:
	# A diamond inscribed in the rectangle: its corners are outside the quad,
	# the centre is inside — the plain Rect2 test could not tell them apart.
	var rect: Rect2 = Rect2(0.0, 0.0, 10.0, 10.0)
	var diamond: PackedVector2Array = PackedVector2Array([
		Vector2(5, 0), Vector2(10, 5), Vector2(5, 10), Vector2(0, 5)])
	check(TreeManager.point_in_area(Vector2(5, 5), rect, diamond),
		"the centre is inside the diamond")
	check(not TreeManager.point_in_area(Vector2(0.5, 0.5), rect, diamond),
		"a rectangle corner lies OUTSIDE the diamond")
	check(not TreeManager.point_in_area(Vector2(20, 20), rect, diamond),
		"a point outside the hull is rejected by the cheap Rect2 filter")

	var w: Dictionary = _make_world()
	var centre_cell: Vector2i = Vector2i(20, 20)
	var centre: Vector3 = w.nav.cell_to_world(centre_cell)
	var inside: TreeResource = w.tm.spawn_tree(centre_cell, 3)
	var corner_cell: Vector2i = centre_cell + Vector2i(-4, -4)
	var corner_tree: TreeResource = w.tm.spawn_tree(corner_cell, 3)
	var area: Rect2 = _cell_rect(w, centre_cell - Vector2i(5, 5), centre_cell + Vector2i(5, 5))
	var quad: PackedVector2Array = PackedVector2Array([
		Vector2(centre.x, centre.z - 5.0), Vector2(centre.x + 5.0, centre.z),
		Vector2(centre.x, centre.z + 5.0), Vector2(centre.x - 5.0, centre.z)])
	var found: Array[TreeResource] = w.tm.area_trees(area, quad)
	check(found.size() == 1 and found[0] == inside,
		"only the tree inside the rotated quad is listed")
	check(corner_tree != null, "the corner tree still exists")
	_free_world(w)


func test_area_job_skips_trees_on_another_island() -> void:
	# The grove sits below the cliff: inside the rectangle, but only reachable
	# via the ~95 m ramp. Pins the A1 decision — the walk budget comes from the
	# distance to the WALKER, so a short detour is accepted and this one is not.
	var w: Dictionary = _make_world(_plateau_terrain())
	var below: TreeResource = w.tm.spawn_tree(Vector2i(44, 20), 3)
	var area: Rect2 = _cell_rect(w, Vector2i(42, 18), Vector2i(48, 24))
	var edge: Vector3 = w.nav.cell_to_world(Vector2i(38, 20))   # on the plateau
	check(w.tm.claim_area_tree(area, PackedVector2Array(), self, edge) == null,
		"a 6 m beeline behind a cliff (95 m walk) is refused")
	var near_side: Vector3 = w.nav.cell_to_world(Vector2i(48, 22))   # below the cliff
	check(w.tm.claim_area_tree(area, PackedVector2Array(), self, near_side) == below,
		"from the same level the very same tree IS claimed")
	_free_world(w)


func test_area_job_reaches_a_remote_grove() -> void:
	# The A1 regression guard: grove 60 m away, rectangle only 7 m across. With
	# a radius derived from the area diagonal the walk budget would be ~5 m and
	# the order would die instantly.
	var w: Dictionary = _make_world()
	var tree: TreeResource = w.tm.spawn_tree(Vector2i(80, 20), 3)
	var area: Rect2 = _cell_rect(w, Vector2i(77, 17), Vector2i(83, 23))
	var brave: Brave = _brave_at(w, Vector2i(20, 20))   # 60 m away
	var units: Array[Unit] = [brave] as Array[Unit]
	check(w.commands.order_chop_area(units, area) == 1,
		"the order for a grove 60 m away is accepted")
	check(brave.task_tree == tree, "the brave targets the remote tree")
	brave._interrupt_tasks()
	_free_world(w)


# --- Brave behaviour -----------------------------------------------------------

func test_area_job_fills_carry_capacity_before_delivering() -> void:
	var w: Dictionary = _make_world()
	w.bm.place(HUT_SCENE, w.tribe, Vector2i(10, 10), 0, true)
	for i in range(4):
		w.tm.spawn_tree(Vector2i(20 + i * 2, 20), 1)   # stage 1 = one wood each
	var area: Rect2 = _cell_rect(w, Vector2i(18, 18), Vector2i(28, 22))
	var brave: Brave = _brave_at(w, Vector2i(20, 20))
	var units: Array[Unit] = [brave] as Array[Unit]
	check(w.commands.order_chop_area(units, area) == 1, "area order accepted")
	var delivered_at: int = -1
	for i in range(2000):
		brave.tick(TICK)
		if brave.task == Brave.Task.DELIVER:
			delivered_at = brave.carried_wood
			break
	check(delivered_at == Brave.CARRY_CAPACITY,
		"delivery starts only with a FULL load (%d), not after one piece" % delivered_at)
	brave._interrupt_tasks()
	_free_world(w)


func test_single_tree_order_still_delivers_one_piece_per_trip() -> void:
	# Regression guard for the unchanged path: order_chop keeps its one-piece
	# behaviour, only the AREA order fills the load.
	var w: Dictionary = _make_world()
	w.bm.place(HUT_SCENE, w.tribe, Vector2i(10, 10), 0, true)
	var tree: TreeResource = w.tm.spawn_tree(Vector2i(20, 20), 4)
	var brave: Brave = _brave_at(w, Vector2i(20, 21))
	check(brave.order_chop(tree), "order_chop reports acceptance")
	var carried: int = -1
	for i in range(2000):
		brave.tick(TICK)
		if brave.task == Brave.Task.DELIVER:
			carried = brave.carried_wood
			break
	check(carried == 1, "the single-tree order still carries ONE piece per trip")
	brave._interrupt_tasks()
	_free_world(w)


func test_area_job_retargets_after_each_delivery() -> void:
	var w: Dictionary = _make_world()
	w.tm.spawn_tree(Vector2i(20, 20), 3)
	var second: TreeResource = w.tm.spawn_tree(Vector2i(23, 20), 3)
	var area: Rect2 = _cell_rect(w, Vector2i(18, 18), Vector2i(25, 22))
	var brave: Brave = _brave_at(w, Vector2i(19, 20))
	var units: Array[Unit] = [brave] as Array[Unit]
	w.commands.order_chop_area(units, area)
	# Simulate "load delivered": release the claim and ask for a new target.
	w.tm.release_claim(brave.task_tree as TreeResource, brave)
	brave.task_tree = null
	brave.carried_wood = 0
	check(brave._next_loose_tree(), "a fresh target is found after the delivery")
	var picked: TreeResource = brave.task_tree as TreeResource
	check(picked != null and TreeManager.point_in_area(
		Vector2(picked.position.x, picked.position.z), area, PackedVector2Array()),
		"the new target lies inside the area again")
	check(second != null, "the second tree exists")
	brave._interrupt_tasks()
	_free_world(w)


func test_area_job_delivers_to_nearest_own_building() -> void:
	var w: Dictionary = _make_world()
	var hut: Building = w.bm.place(HUT_SCENE, w.tribe, Vector2i(24, 20), 0, true)
	w.tm.spawn_tree(Vector2i(20, 20), 3)
	var area: Rect2 = _cell_rect(w, Vector2i(18, 18), Vector2i(22, 22))
	var brave: Brave = _brave_at(w, Vector2i(20, 21))
	var units: Array[Unit] = [brave] as Array[Unit]
	w.commands.order_chop_area(units, area)
	brave.carried_wood = Brave.CARRY_CAPACITY
	brave._start_loose_deliver()
	brave.tick(TICK)
	check(brave._loose_deliver_building == hut,
		"with no depot around the wood goes to the nearest own building")
	brave._interrupt_tasks()
	_free_world(w)


func test_area_job_prefers_a_nearby_wood_depot() -> void:
	var w: Dictionary = _make_world()
	# Hut right next door, depot 15 m away: the depot still wins for an AREA job.
	var hut: Building = w.bm.place(HUT_SCENE, w.tribe, Vector2i(22, 20), 0, true)
	var depot: WoodDepot = w.bm.place(DEPOT_SCENE, w.tribe, Vector2i(35, 20), 0, true) as WoodDepot
	w.tm.spawn_tree(Vector2i(20, 20), 3)
	var area: Rect2 = _cell_rect(w, Vector2i(18, 18), Vector2i(21, 22))
	var brave: Brave = _brave_at(w, Vector2i(20, 21))
	var units: Array[Unit] = [brave] as Array[Unit]
	w.commands.order_chop_area(units, area)
	brave.carried_wood = Brave.CARRY_CAPACITY
	brave._start_loose_deliver()
	brave.tick(TICK)
	check(brave._loose_deliver_building == depot,
		"a rack within DEPOT_PREFER_RADIUS beats the merely nearer hut")
	check(hut != null, "the hut exists")

	# Far beyond the prefer radius the nearest building wins again.
	var far: Dictionary = _make_world()
	var far_hut: Building = far.bm.place(HUT_SCENE, far.tribe, Vector2i(22, 20), 0, true)
	far.bm.place(DEPOT_SCENE, far.tribe, Vector2i(110, 20), 0, true)
	far.tm.spawn_tree(Vector2i(20, 20), 3)
	var far_area: Rect2 = _cell_rect(far, Vector2i(18, 18), Vector2i(21, 22))
	var far_brave: Brave = _brave_at(far, Vector2i(20, 21))
	var far_units: Array[Unit] = [far_brave] as Array[Unit]
	far.commands.order_chop_area(far_units, far_area)
	far_brave.carried_wood = Brave.CARRY_CAPACITY
	far_brave._start_loose_deliver()
	far_brave.tick(TICK)
	check(far_brave._loose_deliver_building == far_hut,
		"a depot beyond DEPOT_PREFER_RADIUS does not win")
	far_brave._interrupt_tasks()
	_free_world(far)
	brave._interrupt_tasks()
	_free_world(w)


func test_area_job_ends_when_the_area_is_empty() -> void:
	var w: Dictionary = _make_world()
	w.bm.place(HUT_SCENE, w.tribe, Vector2i(24, 20), 0, true)
	w.tm.spawn_tree(Vector2i(20, 20), 1)   # a single piece of wood
	var area: Rect2 = _cell_rect(w, Vector2i(19, 19), Vector2i(21, 21))
	var brave: Brave = _brave_at(w, Vector2i(20, 21))
	var units: Array[Unit] = [brave] as Array[Unit]
	check(w.commands.order_chop_area(units, area) == 1, "area order accepted")
	# Long enough for: fell, deliver, then run out the AREA_RETRY_MAX hold.
	var idle: bool = false
	for i in range(4000):
		brave.tick(TICK)
		if brave.state == Unit.State.IDLE:
			idle = true
			break
	check(idle, "the brave goes idle once the area is worked out")
	check(not brave.has_chop_area(), "the standing order is cleared")
	_free_world(w)


func test_new_order_cancels_the_area_job() -> void:
	var w: Dictionary = _make_world()
	w.tm.spawn_tree(Vector2i(20, 20), 3)
	var area: Rect2 = _cell_rect(w, Vector2i(18, 18), Vector2i(22, 22))
	var brave: Brave = _brave_at(w, Vector2i(20, 21))
	var units: Array[Unit] = [brave] as Array[Unit]
	w.commands.order_chop_area(units, area)
	check(brave.has_chop_area(), "the area order is set")
	brave.order_move(w.nav.cell_to_world(Vector2i(60, 60)))
	check(not brave.has_chop_area(), "a movement order cancels the area job")
	check(brave.chop_area_poly.is_empty(), "the quad is cleared too")
	check(brave.task == Brave.Task.NONE, "no sub-task is left over")
	_free_world(w)


# --- Confirmation blink (TreeMarkRenderer) -------------------------------------

func test_mark_flash_lasts_two_blinks() -> void:
	var w: Dictionary = _make_world()
	var tree: TreeResource = w.tm.spawn_tree(Vector2i(20, 20), 3)
	var marks: TreeMarkRenderer = TreeMarkRenderer.new()
	marks._ready()
	marks.flash([tree])
	check(marks.active_marks() == 1, "one mark is active right after the flash")
	var elapsed: float = 0.0
	while elapsed < TreeMarkRenderer.TOTAL_TIME + 0.1:
		marks.advance(0.02)
		elapsed += 0.02
	check(marks.active_marks() == 0,
		"after BLINKS * 2 * BLINK_TIME the mark is gone")
	check(marks.visible_marks() == 0, "nothing is drawn any more")
	marks.free()
	_free_world(w)


func test_mark_flash_is_on_off_on_off() -> void:
	# Pure timing maths at the four phase midpoints.
	var t: float = TreeMarkRenderer.BLINK_TIME
	check(TreeMarkRenderer.mark_visible(t * 0.5), "first half of blink 1: on")
	check(not TreeMarkRenderer.mark_visible(t * 1.5), "second half of blink 1: off")
	check(TreeMarkRenderer.mark_visible(t * 2.5), "first half of blink 2: on")
	check(not TreeMarkRenderer.mark_visible(t * 3.5), "second half of blink 2: off")
	check(not TreeMarkRenderer.mark_visible(TreeMarkRenderer.TOTAL_TIME),
		"exactly at the end it is over")
	check(not TreeMarkRenderer.mark_visible(-0.1), "a negative age is never visible")


func test_mark_flash_restarts_instead_of_stacking() -> void:
	var w: Dictionary = _make_world()
	var tree: TreeResource = w.tm.spawn_tree(Vector2i(20, 20), 3)
	var marks: TreeMarkRenderer = TreeMarkRenderer.new()
	marks._ready()
	marks.flash([tree])
	marks.advance(TreeMarkRenderer.BLINK_TIME)
	marks.flash([tree])
	check(marks.active_marks() == 1,
		"re-flashing the same tree keeps ONE mark instead of stacking a second")
	marks.free()
	_free_world(w)


func test_mark_radius_follows_tree_stage() -> void:
	var w: Dictionary = _make_world()
	var sapling: TreeResource = w.tm.spawn_tree(Vector2i(20, 20), 0)
	var small: TreeResource = w.tm.spawn_tree(Vector2i(24, 20), 1)
	var grown: TreeResource = w.tm.spawn_tree(Vector2i(28, 20), 4)
	check(TreeMarkRenderer.mark_radius(small) < TreeMarkRenderer.mark_radius(grown),
		"a grown tree gets a bigger ring than a small one")
	check(TreeMarkRenderer.mark_radius(sapling) >= TreeMarkRenderer.MIN_RADIUS,
		"a sapling still gets at least MIN_RADIUS")
	check(is_equal_approx(TreeMarkRenderer.mark_radius(grown),
		TreeMarkRenderer.RADIUS_PER_SCALE),
		"the full-grown standard tree uses stage scale 1.0")
	_free_world(w)


# --- Lying wood as an area source (10g) ---------------------------------------
# The fell rectangle treats wood piles as a wood source too: they are picked up
# and hauled to the drop-off like felled wood. Two guards prevent the order from
# eating its own delivery: piles at a friendly building count as DELIVERED wood,
# and with no own building there is no drop-off, so nothing is collected.

func test_area_piles_lists_only_piles_inside_the_shape() -> void:
	var w: Dictionary = _make_world()
	w.wpm.deposit(w.nav.cell_to_world(Vector2i(20, 20)), 3)   # inside
	w.wpm.deposit(w.nav.cell_to_world(Vector2i(60, 60)), 3)   # outside
	var area: Rect2 = _cell_rect(w, Vector2i(18, 18), Vector2i(22, 22))
	var inside: Array[WoodPile] = w.wpm.area_piles(area)
	check(inside.size() == 1, "only the pile inside the rectangle is listed")
	if inside.size() == 1:
		check(inside[0].amount == 3, "and it still holds its wood")
	# An emptied pile is no source any more.
	w.wpm.take_from_radius(w.nav.cell_to_world(Vector2i(20, 20)), 2.0, 99)
	check(w.wpm.area_piles(area).is_empty(), "an emptied pile is not a source")
	_free_world(w)


func test_area_order_collects_a_lying_pile() -> void:
	var w: Dictionary = _make_world()
	# Drop-off well outside the harvest area, so the collected wood leaves it.
	w.bm.place(HUT_SCENE, w.tribe, Vector2i(40, 40), 0, true)
	w.wpm.deposit(w.nav.cell_to_world(Vector2i(20, 20)), 3)
	var area: Rect2 = _cell_rect(w, Vector2i(18, 18), Vector2i(22, 22))
	var brave: Brave = _brave_at(w, Vector2i(21, 21))
	var units: Array[Unit] = [brave] as Array[Unit]
	check(w.commands.order_chop_area(units, area) == 1,
		"an area with only lying wood is still an accepted order")
	check(brave.task == Brave.Task.PICKUP, "the brave goes for the pile")
	check(brave.task_pile != null, "and has it as its target")
	var got: bool = false
	for i in range(int(30.0 / TICK)):
		brave.tick(TICK)
		w.um.tick(TICK)
		if brave.carried_wood > 0:
			got = true
			break
	check(got, "the lying wood is picked up")
	check(w.wpm.total_wood() == 0, "and is gone from the ground")
	_free_world(w)


func test_area_order_hauls_collected_wood_to_the_depot() -> void:
	var w: Dictionary = _make_world()
	var depot: WoodDepot = w.bm.place(
		DEPOT_SCENE, w.tribe, Vector2i(30, 20), 0, true) as WoodDepot
	w.wpm.deposit(w.nav.cell_to_world(Vector2i(20, 20)), 3)
	var area: Rect2 = _cell_rect(w, Vector2i(18, 18), Vector2i(22, 22))
	var brave: Brave = _brave_at(w, Vector2i(21, 21))
	var units: Array[Unit] = [brave] as Array[Unit]
	w.commands.order_chop_area(units, area)
	var stored: bool = false
	for i in range(int(60.0 / TICK)):
		brave.tick(TICK)
		w.um.tick(TICK)
		w.bm.tick(TICK)
		if depot.stored_wood() > 0:
			stored = true
			break
	check(stored, "the collected wood ends up in the depot rack")
	brave._interrupt_tasks()
	_free_world(w)


## The order's OWN drop-off lies inside the area: the delivered wood must not be
## picked up again (that would be an endless loop).
func test_area_order_does_not_re_collect_its_own_delivery() -> void:
	var w: Dictionary = _make_world()
	var hut: Building = w.bm.place(HUT_SCENE, w.tribe, Vector2i(20, 20), 0, true)
	# Wood lying right at the hut = delivered wood.
	w.wpm.deposit(hut.delivery_point(), 3)
	var area: Rect2 = _cell_rect(w, Vector2i(16, 16), Vector2i(26, 26))
	var brave: Brave = _brave_at(w, Vector2i(24, 24))
	check(w.wpm.area_piles(area).size() == 1, "the pile IS inside the area")
	brave.chop_area = area
	brave.chop_area_poly = PackedVector2Array()
	check(not brave._next_area_pile(),
		"wood at a friendly building is delivered wood, not a source")
	_free_world(w)


## No own building anywhere = no drop-off: collecting would only drop the load on
## the spot and pick it up again.
func test_area_order_ignores_piles_without_a_drop_off() -> void:
	var w: Dictionary = _make_world()
	w.wpm.deposit(w.nav.cell_to_world(Vector2i(20, 20)), 3)
	var area: Rect2 = _cell_rect(w, Vector2i(18, 18), Vector2i(22, 22))
	var brave: Brave = _brave_at(w, Vector2i(21, 21))
	brave.chop_area = area
	brave.chop_area_poly = PackedVector2Array()
	check(not brave._next_area_pile(),
		"without any own building no pile is collected")
	_free_world(w)


## Trees stay the primary source — their claim slots are what spreads a crew out.
func test_area_order_takes_trees_before_lying_wood() -> void:
	var w: Dictionary = _make_world()
	w.bm.place(HUT_SCENE, w.tribe, Vector2i(40, 40), 0, true)
	w.tm.spawn_tree(Vector2i(20, 20), 3)
	w.wpm.deposit(w.nav.cell_to_world(Vector2i(21, 21)), 3)
	var area: Rect2 = _cell_rect(w, Vector2i(18, 18), Vector2i(23, 23))
	var brave: Brave = _brave_at(w, Vector2i(22, 22))
	var units: Array[Unit] = [brave] as Array[Unit]
	w.commands.order_chop_area(units, area)
	check(brave.task == Brave.Task.CHOP and brave.task_tree != null,
		"the tree is taken first, the pile waits")
	brave._interrupt_tasks()
	_free_world(w)


# --- White confirmation ring on piles (10g) -----------------------------------

func test_pile_gets_the_same_white_confirmation_mark() -> void:
	var w: Dictionary = _make_world()
	w.wpm.deposit(w.nav.cell_to_world(Vector2i(20, 20)), 2)
	var piles: Array[WoodPile] = w.wpm.piles_in_radius(
		w.nav.cell_to_world(Vector2i(20, 20)), 3.0)
	check(piles.size() == 1, "one pile to mark")
	var marks: TreeMarkRenderer = TreeMarkRenderer.new()
	marks._ready()
	marks.flash_piles(piles)
	check(marks.active_marks() == 1, "the pile got a confirmation mark")
	# The MultiMesh is packed in advance(), so it takes one frame to be drawn.
	marks.advance(0.02)
	check(marks.visible_marks() == 1, "and it is drawn in its ON phase")
	# Same blink lifetime as a tree mark.
	var elapsed: float = 0.0
	while elapsed < TreeMarkRenderer.TOTAL_TIME + 0.1:
		marks.advance(0.02)
		elapsed += 0.02
	check(marks.active_marks() == 0, "and it expires like a tree mark")
	# An emptied pile is not marked at all.
	piles[0].set_amount(0)
	marks.flash_piles(piles)
	check(marks.active_marks() == 0, "an empty pile gets no mark")
	marks.free()
	_free_world(w)


func test_pile_and_tree_marks_share_one_renderer() -> void:
	var w: Dictionary = _make_world()
	var tree: TreeResource = w.tm.spawn_tree(Vector2i(20, 20), 3)
	w.wpm.deposit(w.nav.cell_to_world(Vector2i(26, 20)), 2)
	var marks: TreeMarkRenderer = TreeMarkRenderer.new()
	marks._ready()
	marks.flash([tree])
	marks.flash_piles(w.wpm.piles_in_radius(w.nav.cell_to_world(Vector2i(26, 20)), 3.0))
	check(marks.active_marks() == 2,
		"one area order marks its trees AND its lying wood")
	marks.free()
	_free_world(w)
