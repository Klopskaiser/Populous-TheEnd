extends TestBase

## Bugfixes 2026-11-26 (user report):
##   1. a giant golem off screen got into every box select (pick rect along the
##      camera up axis — now the 3D body box, clipped at the camera);
##   2. wood orders (tree, pile, harvest rectangle) queue with Shift
##      (Unit.order_queue) instead of overwriting each other;
##   3. the fell rectangle at the map edge: corners over the void stay where they
##      were drawn (hull cropped to the disc), and a tree counts when its white
##      ring reaches into the rectangle.

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const GOLEM_SCENE: PackedScene = preload("res://scenes/units/golem.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")

const TICK: float = 1.0 / 30.0


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for vz in range(td.size + 1):
		for vx in range(td.size + 1):
			td.set_vertex_height(vx, vz, h)
	return td


func _make_world() -> Dictionary:
	var terrain: TerrainData = _flat_terrain()
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
	w.commands.free()
	w.bm.free()
	w.um.free()
	w.wpm.free()
	w.tm.free()


func _brave_at(w: Dictionary, cell: Vector2i) -> Brave:
	return w.um.spawn_unit(BRAVE_SCENE, 0, w.nav.cell_to_world(cell)) as Brave


func _cell_rect(w: Dictionary, from: Vector2i, to: Vector2i) -> Rect2:
	var a: Vector3 = w.nav.cell_to_world(from)
	var b: Vector3 = w.nav.cell_to_world(to)
	var lo: Vector2 = Vector2(minf(a.x, b.x), minf(a.z, b.z)) - Vector2(0.5, 0.5)
	var hi: Vector2 = Vector2(maxf(a.x, b.x), maxf(a.z, b.z)) + Vector2(0.5, 0.5)
	return Rect2(lo, hi - lo)


## Ticks the brave until `done` holds or `max_ticks` ran out; returns the ticks used.
func _run(brave: Unit, done: Callable, max_ticks: int = 6000) -> int:
	for i in range(max_ticks):
		brave.tick(TICK)
		if done.call():
			return i
	return max_ticks


# --- 1: golem pick rect -------------------------------------------------------------

## The game's camera (pitch -55, fov 75, boom 45) on a 1152 x 648 view, as plain
## math: Camera3D.unproject_position needs a camera inside a running scene tree,
## which the synchronous test runner does not have.
const VIEW: Vector2 = Vector2(1152.0, 648.0)


func _cam_transform(pivot: Vector3) -> Transform3D:
	var pitch: float = deg_to_rad(55.0)
	var eye: Vector3 = pivot + Vector3(0.0, sin(pitch), cos(pitch)) * 45.0
	return Transform3D(Basis.looking_at(pivot - eye, Vector3.UP), eye)


func _project(cam: Transform3D, p: Vector3) -> Vector2:
	var proj: Projection = Projection.create_perspective(75.0, VIEW.x / VIEW.y, 0.05, 2000.0)
	var v: Vector3 = cam.affine_inverse() * p
	var c: Vector4 = proj * Vector4(v.x, v.y, v.z, 1.0)
	return Vector2((c.x / c.w * 0.5 + 0.5) * VIEW.x, (-c.y / c.w * 0.5 + 0.5) * VIEW.y)


## The new pick rect: body box clipped at the camera, then projected (the same
## steps as SelectionManager._screen_rect_from_points).
func _box_rect(cam: Transform3D, unit: Unit) -> Rect2:
	var pts: PackedVector3Array = SelectionManager.clip_hull_to_front(
		unit.pick_world_points(), cam.origin, -cam.basis.z, 0.085)
	if pts.is_empty():
		return Rect2()
	var projected: PackedVector2Array = PackedVector2Array()
	for p in pts:
		projected.append(_project(cam, p))
	return SelectionManager.screen_part_of_hull(projected, Rect2(Vector2.ZERO, VIEW))


func _giant() -> Golem:
	var g: Golem = GOLEM_SCENE.instantiate() as Golem
	g.kills += 5000
	g._credit_kill()   # grows her to the 80-m cap
	return g


func test_golem_pick_box_is_her_body() -> void:
	var g: Golem = _giant()
	var pts: PackedVector3Array = g.pick_world_points()
	check(pts.size() == 8, "eight corners of the body box")
	var top: float = -INF
	var bottom: float = INF
	for p in pts:
		top = maxf(top, p.y)
		bottom = minf(bottom, p.y)
	check_near(top - bottom, g.height_m(), "the box is as tall as she is (world up)", 0.01)
	g.free()


func test_giant_golem_below_the_screen_is_not_box_selected() -> void:
	var pivot: Vector3 = Vector3(64.0, 0.0, 64.0)
	var cam: Transform3D = _cam_transform(pivot)
	var g: Golem = _giant()
	# She stands behind the camera, below the bottom edge of the screen; her
	# upper body passes the camera plane, her head is far behind it.
	g.position = pivot + Vector3(0.0, 0.0, 48.0)
	var feet: Vector2 = _project(cam, g.position)
	check(feet.y > VIEW.y, "the setup: her feet are below the screen (%s)" % feet)
	# The old billboard formula: 80 m stacked along the CAMERA up axis.
	var head_old: Vector2 = _project(cam, g.position + cam.basis.y * g.height_m())
	var box: Rect2 = Rect2(300.0, 60.0, 500.0, 250.0)   # a drag in the upper screen half
	check(head_old.y < box.end.y, "the old rect reached up into that box (the bug)")
	var rect: Rect2 = _box_rect(cam, g)
	check(not box.intersects(rect), "her body box does not (rect %s)" % rect)
	check(rect.size == Vector2.ZERO, "nothing of her is on screen at all")
	g.free()


func test_golem_on_screen_is_still_box_selected() -> void:
	var pivot: Vector3 = Vector3(64.0, 0.0, 64.0)
	var cam: Transform3D = _cam_transform(pivot)
	var g: Golem = GOLEM_SCENE.instantiate() as Golem
	g.position = pivot
	var rect: Rect2 = _box_rect(cam, g)
	check(rect.has_point(_project(cam, g.position)), "her rect covers her feet")
	check(rect.has_point(_project(cam, g.position + Vector3(0, g.height_m() * 0.9, 0))),
		"and her head")
	# A giant in the middle of the view, head behind the camera: clipped, not lost.
	var big: Golem = _giant()
	big.position = pivot
	var head: Vector3 = big.position + Vector3(0.0, big.height_m(), 0.0)
	check((head - cam.origin).dot(-cam.basis.z) < 0.0, "the setup: her head is behind the camera")
	var big_rect: Rect2 = _box_rect(cam, big)
	check(big_rect.size.y > 0.0 and big_rect.has_point(_project(cam, big.position)),
		"she stays pickable by her visible part")
	g.free()
	big.free()


# --- 2: Shift queue -------------------------------------------------------------------

func test_shift_chop_two_trees_fells_both_in_order() -> void:
	var w: Dictionary = _make_world()
	w.bm.place(HUT_SCENE, w.tribe, Vector2i(30, 20), 0, true)
	var a: TreeResource = w.tm.spawn_tree(Vector2i(20, 20), 1)
	var b: TreeResource = w.tm.spawn_tree(Vector2i(40, 26), 1)
	var brave: Brave = _brave_at(w, Vector2i(24, 22))
	var units: Array[Unit] = [brave] as Array[Unit]
	var trees: Array = [a, b]
	var chop_a: Callable = func(u: Unit) -> void: w.commands.order_chop([u] as Array[Unit], trees[0])
	var chop_b: Callable = func(u: Unit) -> void: w.commands.order_chop([u] as Array[Unit], trees[1])
	brave.queue_order(chop_a.bind(brave))
	check(brave.task_tree == a, "the first Shift order runs at once on an idle brave")
	brave.queue_order(chop_b.bind(brave))
	check(brave.task_tree == a and brave.order_queue.size() == 1,
		"the second one waits instead of replacing the first")
	var ra: WeakRef = weakref(a)
	var rb: WeakRef = weakref(b)
	var t: int = _run(brave, func() -> bool: return ra.get_ref() == null or ra.get_ref().felled_flag)
	check(t < 6000, "tree A gets felled")
	check(rb.get_ref() != null and not rb.get_ref().felled_flag, "B still stands then")
	var t2: int = _run(brave, func() -> bool: return rb.get_ref() == null or rb.get_ref().felled_flag)
	check(t2 < 6000, "then tree B")
	_free_world(w)


func test_shift_area_waits_behind_the_running_chop() -> void:
	var w: Dictionary = _make_world()
	w.bm.place(HUT_SCENE, w.tribe, Vector2i(30, 20), 0, true)
	var a: TreeResource = w.tm.spawn_tree(Vector2i(20, 20), 2)
	w.tm.spawn_tree(Vector2i(40, 40), 1)
	var ra: WeakRef = weakref(a)
	var brave: Brave = _brave_at(w, Vector2i(21, 21))
	var units: Array[Unit] = [brave] as Array[Unit]
	w.commands.order_chop(units, a)
	brave.tick(TICK)
	var area: Rect2 = _cell_rect(w, Vector2i(38, 38), Vector2i(42, 42))
	var queued: Callable = func(u: Unit) -> void:
		w.commands.order_chop_area([u] as Array[Unit], area)
	brave.queue_order(queued.bind(brave))
	check(brave.task_tree == a and not brave.has_chop_area(),
		"the chop keeps running; the area order is only queued")
	var t: int = _run(brave, func() -> bool: return brave.has_chop_area())
	check(t < 6000, "the area order starts once tree A is done")
	check(ra.get_ref() == null or ra.get_ref().felled_flag, "and tree A was felled first")
	_free_world(w)


func test_shift_move_behind_wood_work_does_not_break_it_off() -> void:
	var w: Dictionary = _make_world()
	var a: TreeResource = w.tm.spawn_tree(Vector2i(20, 20), 3)
	var brave: Brave = _brave_at(w, Vector2i(21, 21))
	w.commands.order_chop([brave] as Array[Unit], a)
	brave.order_move(w.nav.cell_to_world(Vector2i(50, 50)), true)
	check(brave.state == Unit.State.GATHER and brave.task_tree == a,
		"a Shift-move waits behind the chop")
	check(brave.order_queue.size() == 1, "it sits in the queue")
	brave.order_move(w.nav.cell_to_world(Vector2i(50, 50)))
	check(brave.state == Unit.State.MOVE and brave.order_queue.is_empty(),
		"a plain move still breaks off at once and drops the queue")
	_free_world(w)


# --- 3: fell rectangle -----------------------------------------------------------------

func test_ring_touching_the_area_counts() -> void:
	var w: Dictionary = _make_world()
	var tree: TreeResource = w.tm.spawn_tree(Vector2i(20, 20), 3)
	var p: Vector3 = tree.position
	var r: float = TreeManager.ring_radius(tree)
	# The area ends just short of the trunk, but well inside its ring.
	var area: Rect2 = Rect2(p.x + r * 0.5, p.z - 3.0, 6.0, 6.0)
	check(not w.tm.area_trees(area).has(tree), "trunk outside: the plain query skips it")
	check(w.tm.area_trees(area, PackedVector2Array(), true).has(tree),
		"its ring reaches in: the fell rectangle takes it")
	var far: Rect2 = Rect2(p.x + r + 0.2, p.z - 3.0, 6.0, 6.0)
	check(not w.tm.area_trees(far, PackedVector2Array(), true).has(tree),
		"a ring that stays outside does not count")
	_free_world(w)


func test_ring_touch_with_a_rotated_quad() -> void:
	# Diamond around (10, 10): a point 0,5 m outside an edge counts with margin 0,6.
	var diamond: PackedVector2Array = PackedVector2Array([
		Vector2(10, 4), Vector2(16, 10), Vector2(10, 16), Vector2(4, 10)])
	var rect: Rect2 = Rect2(4, 4, 12, 12)
	var outside: Vector2 = Vector2(13, 7) + Vector2(1, -1).normalized() * 0.5
	check(not TreeManager.point_in_area(outside, rect, diamond), "outside the drawn edge")
	check(TreeManager.point_in_area(outside, rect, diamond, 0.6), "but within the ring margin")
	check(not TreeManager.point_in_area(outside, rect, diamond, 0.4), "not with a smaller ring")


func test_crop_to_disc_keeps_the_rim_band() -> void:
	# A drag past the rim: the hull reaches 30 m into the void.
	var center: Vector2 = Vector2(64, 64)
	var radius: float = 60.0
	var hull: Rect2 = Rect2(44, -26, 40, 60)   # z from -26 (void) to 34 (ground)
	var cropped: Rect2 = TribeCommands.crop_to_disc(hull, center, radius)
	check(cropped.size.y > 0.0 and cropped.position.y <= 64.0 - radius + 0.01,
		"the crop still reaches the rim itself (top of the disc at z = 4)")
	check(cropped.position.y > -1.0, "but not out into the void")
	check(cropped.size.y <= TribeCommands.HARVEST_AREA_MAX_SIDE,
		"what is left is a normal-sized order")
	var inside: Rect2 = Rect2(50, 50, 10, 10)
	check(TribeCommands.crop_to_disc(inside, center, radius) == inside,
		"a rectangle fully on the disc stays exactly as it is")
	check(TribeCommands.crop_to_disc(Rect2(-80, -80, 10, 10), center, radius).size == Vector2.ZERO,
		"a rectangle entirely over the void is empty")


func test_unclamped_area_keeps_its_quad() -> void:
	# Float noise from re-centring used to make harvest_job_shape drop the quad.
	var rect: Rect2 = Rect2(130.37, 17.913, 21.71, 33.29)
	var quad: PackedVector2Array = PackedVector2Array([rect.position,
		Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var shape: Array = TribeCommands.harvest_job_shape(rect, quad)
	check(shape[0] == rect, "an in-range rectangle comes back unchanged")
	check((shape[1] as PackedVector2Array).size() == 4, "and keeps its quad")
