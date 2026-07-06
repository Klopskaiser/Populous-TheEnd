extends TestBase

## Headless tests for phase 7d: the forester (worker slots, mana upkeep,
## sapling planting, eject, destruction) plus the fire mechanic (trees and wood
## piles burning) and the tornado shredding trees / scattering piles.

const TICK: float = 0.1
const MAX_TICKS: int = 3000

const FORESTER_SCENE: PackedScene = preload("res://scenes/buildings/forester.tscn")
const TREE_SCENE: PackedScene = preload("res://scenes/tree_resource.tscn")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")


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


## Ticks the whole world one step (building logic, all currently registered
## units, tree growth/burning, unit manager). Registered units change as the
## forester houses/dispatches workers, so we tick the live list each step.
func _tick_world(w: Dictionary) -> void:
	w.building_manager.tick(TICK)
	for u in w.unit_manager.units.duplicate():
		if is_instance_valid(u):
			u.tick(TICK)
	w.tree_manager.tick(TICK)
	w.unit_manager.tick(TICK)


# --- Forester: planting ---------------------------------------------------------

func test_forester_plants_sapling() -> void:
	var w: Dictionary = _make_world()
	var f: Forester = w.building_manager.place(
		FORESTER_SCENE, w.tribe, Vector2i(60, 60), 0, true) as Forester
	check(f != null and f.is_usable(), "pre-built forester is usable")
	w.tribe.mana = 100000.0   # plenty for the worker upkeep

	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(57, 60))) as Brave
	brave.order_forester(f)
	check(f.occupants.size() == 1, "the brave reserved a worker slot")
	check(brave.state == Unit.State.FORESTER, "brave is on its way to the forester")

	var ticks: int = 0
	while w.tree_manager.trees.is_empty() and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(not w.tree_manager.trees.is_empty(), "the forester planted a sapling (took %d ticks)" % ticks)
	if not w.tree_manager.trees.is_empty():
		var sap: TreeResource = w.tree_manager.trees[0]
		check(sap.stage == 0, "the planted tree is a sapling (stage 0, 0 wood)")
		var center: Vector2i = Vector2i(61, 61)
		var cell: Vector2i = w.nav.world_to_cell(sap.position)
		check(maxi(absi(cell.x - center.x), absi(cell.y - center.y)) <= Forester.PLANT_RADIUS,
			"the sapling sits inside the 11x11 planting area")
	_free_world(w)


# --- Forester: mana upkeep -------------------------------------------------------

func test_forester_mana_upkeep() -> void:
	var w: Dictionary = _make_world()
	var f: Forester = w.building_manager.place(
		FORESTER_SCENE, w.tribe, Vector2i(60, 60), 0, true) as Forester
	# Four housed workers (stubbed as already inside).
	var braves: Array[Brave] = []
	for i in range(4):
		var b: Brave = Brave.new()
		b.forester_home = f
		b.forester_inside = true
		w.tribe.add_unit(b)
		f.occupants.append(b)
		braves.append(b)

	w.tribe.mana = 10.0
	f._tick_active(1.0)
	check(f._active_workers == 4, "all four workers active while mana lasts")
	check_near(w.tribe.mana, 2.0, "4 workers drain 4x2 = 8 mana in one second")

	# Only 2 mana left: at 2/s each, just one worker can be paid this second.
	w.tribe.mana = 2.0
	f._tick_active(1.0)
	check(f._active_workers == 1, "scarce mana staffs only one worker")
	check_near(w.tribe.mana, 0.0, "the affordable worker's upkeep is spent")

	# No mana: no active workers, no planting.
	w.tribe.mana = 0.0
	f._tick_active(1.0)
	check(f._active_workers == 0, "no mana -> no active workers")

	for b in braves:
		w.tribe.remove_unit(b)
		b.free()
	_free_world(w)


# --- Forester: eject & destruction ----------------------------------------------

func _house_one_worker(w: Dictionary, f: Forester) -> Brave:
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(57, 60))) as Brave
	brave.order_forester(f)
	var ticks: int = 0
	while not brave.forester_inside and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	return brave


func test_forester_eject_worker() -> void:
	var w: Dictionary = _make_world()
	var f: Forester = w.building_manager.place(
		FORESTER_SCENE, w.tribe, Vector2i(60, 60), 0, true) as Forester
	w.tribe.mana = 100000.0
	var brave: Brave = _house_one_worker(w, f)
	check(brave.forester_inside, "the worker is housed inside")
	check(not (brave in w.unit_manager.units), "a housed worker is out of the live world")

	f.eject_worker(0)
	check(f.occupants.is_empty(), "the slot is free after ejecting")
	check(is_instance_valid(brave) and brave in w.unit_manager.units,
		"the ejected worker is back in the world")
	check(brave.forester_home == null, "the ejected worker no longer belongs to the forester")
	check(brave.state == Unit.State.IDLE, "the ejected worker goes idle")
	_free_world(w)


func test_forester_destroy_releases_workers() -> void:
	var w: Dictionary = _make_world()
	var f: Forester = w.building_manager.place(
		FORESTER_SCENE, w.tribe, Vector2i(60, 60), 0, true) as Forester
	w.tribe.mana = 100000.0
	var brave: Brave = _house_one_worker(w, f)
	check(brave.forester_inside, "worker housed before destruction")

	f.destroy()
	check(f.occupants.is_empty(), "occupants released on destruction")
	check(is_instance_valid(brave) and brave in w.unit_manager.units,
		"the housed worker returns to the world when the forester is destroyed")
	check(brave.state == Unit.State.IDLE, "the freed worker goes idle")
	_free_world(w)


func test_forester_damaged_releases_workers() -> void:
	var w: Dictionary = _make_world()
	var f: Forester = w.building_manager.place(
		FORESTER_SCENE, w.tribe, Vector2i(60, 60), 0, true) as Forester
	w.tribe.mana = 100000.0
	var brave: Brave = _house_one_worker(w, f)
	# Damage past stage 1 (>= 30%): the forester becomes unusable and ejects.
	f.take_damage(int(float(f.max_health) * 0.4))
	check(not f.is_usable(), "a damaged forester is unusable")
	check(f.occupants.is_empty(), "a damaged forester releases its workers")
	check(is_instance_valid(brave) and brave in w.unit_manager.units,
		"the worker steps back out when the forester is damaged")
	_free_world(w)


# --- Forester: area cap & dense planting -----------------------------------------

func test_forester_area_cap_blocks_planting() -> void:
	var w: Dictionary = _make_world()
	var f: Forester = w.building_manager.place(
		FORESTER_SCENE, w.tribe, Vector2i(60, 60), 0, true) as Forester
	var center: Vector2i = Vector2i(61, 61)
	# Fill the area to the cap (spacing 2 so they all register distinctly).
	var placed: int = 0
	for dz in range(-Forester.PLANT_RADIUS, Forester.PLANT_RADIUS + 1, 2):
		for dx in range(-Forester.PLANT_RADIUS, Forester.PLANT_RADIUS + 1, 2):
			if placed >= Forester.AREA_TREE_CAP:
				break
			var c: Vector2i = center + Vector2i(dx, dz)
			if not w.tree_manager._occupied.has(c):
				w.tree_manager.spawn_tree(c, 2)
				placed += 1
	check(w.tree_manager.trees_in_area(center, Forester.PLANT_RADIUS) >= Forester.AREA_TREE_CAP,
		"the area is filled to the cap")
	check(not f._dispatch_plant(), "no planting once the area is at the tree cap")
	_free_world(w)


func test_forester_planting_denser_than_wild() -> void:
	var w: Dictionary = _make_world()
	var tm: TreeManager = w.tree_manager
	tm.spawn_tree(Vector2i(60, 60), 2)
	# One cell away is too close for the wild spacing (2) but fine for the
	# forester's denser planting spacing (1).
	check(tm._too_close(Vector2i(61, 60)), "wild spacing rejects an adjacent cell")
	check(not tm.can_plant_at(Vector2i(61, 60), Forester.PLANT_SPACING),
		"even dense planting keeps one cell of gap")
	check(tm.can_plant_at(Vector2i(62, 60), Forester.PLANT_SPACING),
		"dense planting allows a tree two cells away (wild spacing would not)")
	_free_world(w)


# --- Fire: trees and wood piles burn ---------------------------------------------

func test_tree_burns_and_is_destroyed() -> void:
	var w: Dictionary = _make_world()
	var tree: TreeResource = w.tree_manager.spawn_tree(Vector2i(60, 60), 3)
	tree.ignite()
	check(tree.is_burning(), "an ignited tree is burning")
	check(not tree.can_claim(), "a burning tree cannot be harvested")

	var t: float = 0.0
	while not w.tree_manager.trees.is_empty() and t < 5.0:
		w.tree_manager.tick(TICK)
		t += TICK
	check(w.tree_manager.trees.is_empty(), "the tree burns down and is destroyed")
	check(w.wood_pile_manager.total_wood() == 0, "a burnt tree yields no wood")
	_free_world(w)


func test_wood_pile_burns() -> void:
	var w: Dictionary = _make_world()
	var wpm: WoodPileManager = w.wood_pile_manager
	wpm.deposit(Vector3(50.0, 5.0, 50.0), 3)
	check(wpm.total_wood() == 3, "pile deposited")
	var count: int = wpm.ignite_in_radius(Vector3(50.0, 5.0, 50.0), 1.0)
	check(count == 1, "the pile is set alight")

	var t: float = 0.0
	while wpm.total_wood() > 0 and t < 3.0:
		wpm.tick(TICK)
		t += TICK
	check(wpm.total_wood() == 0, "the burning pile is consumed")
	_free_world(w)


func test_fire_only_ignites_in_radius() -> void:
	var w: Dictionary = _make_world()
	var tm: TreeManager = w.tree_manager
	var near: TreeResource = tm.spawn_tree(Vector2i(60, 60), 3)
	var far: TreeResource = tm.spawn_tree(Vector2i(90, 90), 3)
	var lit: int = tm.ignite_in_radius(near.position, 2.0)
	check(lit == 1, "only one tree in radius is ignited")
	check(near.is_burning(), "the near tree burns")
	check(not far.is_burning(), "the far tree is untouched")
	_free_world(w)


# --- Tornado: shred trees, scatter piles keeping their wood ----------------------

func test_tornado_whirls_trees_and_piles() -> void:
	var w: Dictionary = _make_world()
	var pos: Vector3 = Vector3(60.5, 5.0, 60.5)
	w.tree_manager.spawn_tree(Vector2i(60, 60), 3)   # big tree in the funnel (3 wood)
	var far: TreeResource = w.tree_manager.spawn_tree(Vector2i(90, 90), 3)   # outside
	w.wood_pile_manager.deposit(pos, 4)              # pile in the funnel (4 wood)

	var vortex: TornadoVortex = TornadoVortex.new()
	vortex.setup(0, pos, w.unit_manager, w.td, w.building_manager)
	vortex._shred_trees_and_scatter_piles()

	check(w.tree_manager.trees.size() == 1 and (far in w.tree_manager.trees),
		"only the tree in the funnel was uprooted")
	check(w.wood_pile_manager.total_wood() == 0, "the pile is airborne (removed while flying)")
	check(w.unit_manager.projectiles.size() == 2,
		"two wood chunks are whirling (the uprooted tree + the pile)")

	# Let the flying wood arc and slide to rest.
	var ticks: int = 0
	while not w.unit_manager.projectiles.is_empty() and ticks < 400:
		w.unit_manager.tick(0.1)
		ticks += 1
	check(w.unit_manager.projectiles.is_empty(), "the whirled wood settled")
	check(w.wood_pile_manager.total_wood() == 7,
		"the tree became a 3-wood pile and the 4-wood pile kept its wood (3+4)")
	vortex.free()
	_free_world(w)


## A flying wood chunk spirals up, arcs and slides to rest as a pile with its
## wood; a sapling chunk (no wood) vanishes instead.
func test_tornado_debris_flight() -> void:
	var w: Dictionary = _make_world()
	var d: TornadoDebris = TornadoDebris.new()
	d.setup(Vector3(60, 5, 60), 2, w.td, w.wood_pile_manager, null, 0.0)
	d.tick(0.1)
	check(d.position.y > 5.0, "debris is whirled up off the ground")
	var ticks: int = 0
	while not d.done and ticks < 400:
		d.tick(0.1)
		ticks += 1
	check(d.done, "debris finishes its flight")
	check(w.wood_pile_manager.total_wood() == 2, "it settles into a pile with its wood")
	d.free()

	var sap: TornadoDebris = TornadoDebris.new()
	sap.setup(Vector3(70, 5, 70), 0, w.td, w.wood_pile_manager, null, 0.0)
	check(sap.vanish, "a no-wood chunk (sapling) is flagged to vanish")
	ticks = 0
	while not sap.done and ticks < 400:
		sap.tick(0.1)
		ticks += 1
	check(sap.done, "sapling debris finishes")
	check(w.wood_pile_manager.total_wood() == 2, "the sapling left no extra wood")
	sap.free()
	_free_world(w)
