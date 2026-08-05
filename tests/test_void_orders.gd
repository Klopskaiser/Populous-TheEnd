extends TestBase

## Phase 10j — nothing may land in the void.
##
## `HeightMapShape3D` is unavoidably rectangular, so the terrain raycast still HITS
## out over the void: every click path has to reject it explicitly. The UI layer does
## that so no sound, ring or ghost pretends the click was valid, and `TribeCommands`
## does it again as the server-side backstop — it is the one mutation API that both
## the UI and the AI go through, which is why the guard belongs there.

const SITE_SCENE: PackedScene = preload("res://scenes/buildings/reincarnation_site.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


func _make_world() -> Dictionary:
	var td: TerrainData = _flat_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var tribe: Tribe = Tribe.new(0)
	tribe.set_spells(Spell.create_default_set())
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe] as Array[Tribe])
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um)
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(nav, bm, um, tm)
	return {"td": td, "nav": nav, "tribe": tribe, "um": um, "bm": bm,
		"tm": tm, "wpm": wpm, "tc": tc}


func _free_world(w: Dictionary) -> void:
	w.tc.free()
	w.wpm.free()
	w.tm.free()
	w.bm.free()
	w.um.free()


## A world point out in the void, on the +x axis through the centre.
func _void_point(td: TerrainData) -> Vector3:
	return Vector3(td.disc_center() + td.disc_radius() + 20.0, 5.0, td.disc_center())


# --- Orders ------------------------------------------------------------------------

func test_order_move_into_the_void_is_refused() -> void:
	var w: Dictionary = _make_world()
	var mid: float = w.td.disc_center()
	var brave: Unit = w.um.spawn_unit(BRAVE_SCENE, 0, Vector3(mid, 0.0, mid))
	var before: Vector3 = brave.position
	w.tc.order_move([brave] as Array[Unit], _void_point(w.td))
	check(brave.state != Unit.State.MOVE, "no march order was issued")
	check(brave.waypoint_queue.is_empty(), "and no waypoint was queued")
	for i in range(40):
		brave.tick(0.1)
	check(brave.position.distance_to(before) < 0.5,
		"the unit stayed where it was — the void is not a place")
	_free_world(w)


func test_order_move_onto_the_disc_still_works() -> void:
	# The guard must not become a blanket refusal: the same call one metre inside the
	# rim has to go through, otherwise this test file would pass on a broken build.
	var w: Dictionary = _make_world()
	var mid: float = w.td.disc_center()
	var brave: Unit = w.um.spawn_unit(BRAVE_SCENE, 0, Vector3(mid, 0.0, mid))
	w.tc.order_move([brave] as Array[Unit], Vector3(mid + 10.0, 0.0, mid))
	check(brave.state == Unit.State.MOVE, "an ordinary move order is still accepted")
	_free_world(w)


# --- Spells ------------------------------------------------------------------------

func test_cast_spell_into_the_void_is_refused_and_keeps_the_charge() -> void:
	var w: Dictionary = _make_world()
	var mid: float = w.td.disc_center()
	var shaman: Unit = w.um.spawn_unit(SHAMAN_SCENE, 0, Vector3(mid, 0.0, mid))
	w.tribe.shaman = shaman
	var spell: Spell = w.tribe.spells[0]
	spell.charges = 2
	var before: int = spell.charges
	check(not w.tc.cast_spell(w.tribe, spell.id, _void_point(w.td)),
		"the cast is refused")
	check(spell.charges == before,
		"and the charge is kept (%d -> %d)" % [before, spell.charges])
	_free_world(w)


func test_cast_spell_onto_the_disc_still_works() -> void:
	var w: Dictionary = _make_world()
	var mid: float = w.td.disc_center()
	var shaman: Unit = w.um.spawn_unit(SHAMAN_SCENE, 0, Vector3(mid, 0.0, mid))
	w.tribe.shaman = shaman
	var spell: Spell = w.tribe.spells[0]
	spell.charges = 2
	check(w.tc.cast_spell(w.tribe, spell.id, Vector3(mid + 4.0, 5.0, mid)),
		"a cast onto real ground is still accepted")
	_free_world(w)


# --- Building placement ------------------------------------------------------------

func test_no_building_can_be_placed_in_the_void() -> void:
	# can_place_at inherits the mask through is_walkable/approach_cell_for, so this is
	# a consequence rather than a separate guard — pinned because the build ghost and
	# the whole AI plot search rely on it.
	var w: Dictionary = _make_world()
	var mid: int = w.td.size / 2
	var last: int = mid
	while w.td.in_disc(Vector2i(last + 1, mid)):
		last += 1
	check(w.tc.can_place_at(Vector2i(mid, mid), Vector2i(2, 2), 0),
		"the centre is buildable")
	check(not w.tc.can_place_at(Vector2i(last + 3, mid), Vector2i(2, 2), 0),
		"a plot in the void is not")
	check(not w.tc.can_place_at(Vector2i(2, 2), Vector2i(2, 2), 0),
		"and neither is the square's corner")
	_free_world(w)
