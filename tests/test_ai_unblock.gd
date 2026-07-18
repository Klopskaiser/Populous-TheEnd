extends TestBase

## AI terrain unblocking: when the attack target sits on another nav island
## (e.g. the only ramp to a base was removed by terrain spells), the AI shaman
## walks to the edge of her island toward the target and casts LANDBRIDGE
## across the gap until the ways are joined and the march can resume.

const TICK: float = 0.1

const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")


## Split world: plateau (9 m) for x <= 40, low land (3 m) for x >= 46 and a
## water-level trench (0.5 m) between them — NO ramp anywhere, two islands.
func _split_terrain() -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for vz in range(td.size + 1):
		for vx in range(td.size + 1):
			var h: float = 9.0
			if vx >= 46:
				h = 3.0
			elif vx >= 41:
				h = 0.5
			td.set_vertex_height(vx, vz, h)
	return td


func _make_world() -> Dictionary:
	var td: TerrainData = _split_terrain()
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
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(nav, bm, um, tm)
	var ctx: SpellContext = SpellContext.new()
	ctx.terrain_data = td
	ctx.nav_grid = nav
	ctx.unit_manager = um
	ctx.building_manager = bm
	ctx.tree_manager = tm
	ctx.wood_pile_manager = wpm
	tc.spell_context = ctx
	return {"td": td, "nav": nav, "tribes": tribes, "unit_manager": um,
		"building_manager": bm, "tree_manager": tm, "wood_pile_manager": wpm,
		"commands": tc, "ctx": ctx}


func _free_world(w: Dictionary) -> void:
	w.commands.free()
	w.tree_manager.free()
	w.wood_pile_manager.free()
	w.building_manager.free()
	w.unit_manager.free()


## AI for tribe 1 with its base anchor on the plateau, forced into ATTACK.
func _make_ai(w: Dictionary) -> AIController:
	var ai: AIController = AIController.new()
	ai.setup(w.tribes[1], w.commands, w.unit_manager, w.building_manager,
		w.tree_manager, w.nav, Vector2i(30, 20))
	ai.state = AIState.State.ATTACK
	return ai


## The island labels refresh at most once per real second — force the next
## check to recompute (tests tick sim time much faster than real time).
func _refresh_islands(w: Dictionary) -> void:
	w.nav._islands_computed_ms = Time.get_ticks_msec() - 2000


func test_split_terrain_is_two_islands() -> void:
	var w: Dictionary = _make_world()
	check(w.nav.is_cell_walkable(Vector2i(38, 20)), "plateau is walkable")
	check(w.nav.is_cell_walkable(Vector2i(50, 20)), "low land is walkable")
	check(not w.nav.same_island(
		w.nav.cell_to_world(Vector2i(38, 20)), w.nav.cell_to_world(Vector2i(50, 20))),
		"trench separates plateau and low land into two islands")
	_free_world(w)


func test_edge_and_bridge_point_helpers() -> void:
	var w: Dictionary = _make_world()
	var shaman: Unit = w.unit_manager.spawn_unit(SHAMAN_SCENE, 1, w.nav.cell_to_world(Vector2i(30, 20)))
	var hut: Building = w.building_manager.place(HUT_SCENE, w.tribes[0], Vector2i(55, 18), 0, true)
	var ai: AIController = _make_ai(w)
	var edge: Vector3 = ai._island_edge_toward(shaman.position, hut.center_world())
	check(edge != Vector3.INF, "edge point found")
	check(edge.x >= 37.0 and edge.x <= 41.0,
		"edge point sits at the plateau rim (x = %.1f)" % edge.x)
	check(absf(edge.y - 9.0) < 1.0, "edge point is on the plateau level")
	var cast_at: Vector3 = ai._bridge_cast_point(edge, hut.center_world(), 8.0)
	var gap: float = Vector2(cast_at.x - edge.x, cast_at.z - edge.z).length()
	check(gap <= 8.0, "cast point stays within the cast range (%.1f m)" % gap)
	check(cast_at.x > edge.x, "cast point lies across the gap toward the target")
	ai.free()
	_free_world(w)


func test_shaman_bridges_to_unreachable_target() -> void:
	var w: Dictionary = _make_world()
	var shaman: Unit = w.unit_manager.spawn_unit(SHAMAN_SCENE, 1, w.nav.cell_to_world(Vector2i(30, 20)))
	check(w.tribes[1].shaman == shaman, "tribe knows its shaman")
	var hut: Building = w.building_manager.place(HUT_SCENE, w.tribes[0], Vector2i(55, 18), 0, true)
	var bridge: Spell = LandbridgeSpell.new()
	w.tribes[1].set_spells([bridge] as Array[Spell])
	bridge.charges = 3
	var ai: AIController = _make_ai(w)
	check(not w.nav.same_island(shaman.position, hut.center_world()),
		"attack target starts unreachable")
	# Simulated seconds: attack tick (1/s, self-throttled) + 10 world ticks
	# each. _tick_attack is driven directly — with pop 1 and no army the state
	# machine would immediately leave ATTACK (covered by its own tests).
	var joined: bool = false
	for second in range(120):
		ai._tick_attack()
		for i in range(10):
			if shaman.state != Unit.State.DEAD:
				shaman.tick(TICK)
			w.unit_manager.tick(TICK)
			w.building_manager.tick(TICK)
		_refresh_islands(w)
		if w.nav.same_island(shaman.position, hut.center_world()):
			joined = true
			break
	check(joined, "the shaman's landbridge joins the islands")
	check(bridge.charges < 3, "a landbridge charge was spent")
	check(w.nav.find_path(shaman.position, hut.center_world()).size() > 0,
		"a walkable path to the attack target exists now")
	ai.free()
	_free_world(w)


func test_no_unblock_when_target_reachable() -> void:
	var w: Dictionary = _make_world()
	var shaman: Unit = w.unit_manager.spawn_unit(SHAMAN_SCENE, 1, w.nav.cell_to_world(Vector2i(30, 20)))
	# Target on the SAME island: the unblock hook must not kick in.
	var hut: Building = w.building_manager.place(HUT_SCENE, w.tribes[0], Vector2i(20, 18), 0, true)
	var bridge: Spell = LandbridgeSpell.new()
	w.tribes[1].set_spells([bridge] as Array[Spell])
	bridge.charges = 3
	var ai: AIController = _make_ai(w)
	check(not ai._tick_unblock_path(hut.center_world()),
		"reachable target -> no unblocking, normal march")
	check(bridge.charges == 3, "no charge wasted on a reachable target")
	ai.free()
	_free_world(w)


# --- Sink fallback (raised wall, no landbridge charges) ------------------------

## Wall world: high land (9 m) on both sides, a 13-m wall band (x 41..45)
## between them — steep on both faces, three islands, no ramp.
func _wall_terrain(side_h: float = 9.0, wall_h: float = 13.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for vz in range(td.size + 1):
		for vx in range(td.size + 1):
			var h: float = side_h
			if vx >= 41 and vx <= 45:
				h = wall_h
			td.set_vertex_height(vx, vz, h)
	return td


func _make_wall_world(side_h: float, wall_h: float) -> Dictionary:
	var w: Dictionary = _make_world()
	# Rebuild terrain/nav as a wall world (reuses the manager wiring).
	var td: TerrainData = _wall_terrain(side_h, wall_h)
	var nav: NavGrid = NavGrid.new(td)
	w.td = td
	w.nav = nav
	w.unit_manager.terrain_data = td
	w.unit_manager.nav_grid = nav
	w.building_manager.terrain_data = td
	w.building_manager.nav_grid = nav
	w.commands.nav_grid = nav
	w.ctx.terrain_data = td
	w.ctx.nav_grid = nav
	return w


func test_sink_fallback_cuts_raised_wall() -> void:
	var w: Dictionary = _make_wall_world(9.0, 13.0)
	# Shaman already AT the island edge (cell 39), wall right in front.
	var shaman: Unit = w.unit_manager.spawn_unit(SHAMAN_SCENE, 1, w.nav.cell_to_world(Vector2i(39, 20)))
	var hut: Building = w.building_manager.place(HUT_SCENE, w.tribes[0], Vector2i(55, 18), 0, true)
	var sink: Spell = SinkSpell.new()
	w.tribes[1].set_spells([sink] as Array[Spell])
	sink.charges = 3
	var ai: AIController = _make_ai(w)
	check(ai._tick_unblock_path(hut.center_world()), "blocked target -> unblocking")
	check(shaman.state == Unit.State.CAST, "shaman winds up the sink cast")
	for i in range(30):   # play out the cast wind-up (the charge is spent on release)
		shaman.tick(TICK)
		w.unit_manager.tick(TICK)
	check(sink.charges == 2, "a sink charge was spent on the wall (got %d)" % sink.charges)
	ai.free()
	_free_world(w)


func test_sink_fallback_skipped_on_low_coastal_ground() -> void:
	# Same wall but the shaman stands on LOW coastal ground (3 m, sea at 2 m):
	# sinking this close would flood her own feet — the fallback must pass.
	var w: Dictionary = _make_wall_world(3.0, 8.0)
	var shaman: Unit = w.unit_manager.spawn_unit(SHAMAN_SCENE, 1, w.nav.cell_to_world(Vector2i(39, 20)))
	var hut: Building = w.building_manager.place(HUT_SCENE, w.tribes[0], Vector2i(55, 18), 0, true)
	var sink: Spell = SinkSpell.new()
	w.tribes[1].set_spells([sink] as Array[Spell])
	sink.charges = 3
	var ai: AIController = _make_ai(w)
	check(ai._tick_unblock_path(hut.center_world()),
		"still counts as unblocking (waiting for safer charges)")
	check(sink.charges == 3, "no sink cast that would flood the caster")
	check(shaman.state != Unit.State.DEAD, "shaman unhurt")
	ai.free()
	_free_world(w)
