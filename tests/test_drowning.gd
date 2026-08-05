extends TestBase

## Headless tests for phase 10a: the drowning mechanic.
##
## Core rule: pathfinding must NEVER route a unit into water, but every form of
## FORCED movement (knockback, roll, throw, cliff launch) may now carry a unit
## into the sea — where it drowns, flails briefly and sinks out of sight below
## the opaque water plane. Vehicles keep their own instant wreck sink.

const TICK: float = 0.1

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const FIRE_RAM_SCENE: PackedScene = preload("res://scenes/units/fire_ram.tscn")


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


func _make_world() -> Dictionary:
	var td: TerrainData = _flat_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var tribe0: Tribe = Tribe.new(0)
	var tribe1: Tribe = Tribe.new(1)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe0, tribe1] as Array[Tribe])
	return {"td": td, "nav": nav, "tribe0": tribe0, "tribe1": tribe1, "unit_manager": um}


## Coast running north-south: open sea (height 1.0, i.e. below SEA_LEVEL) west
## of `shore_x`, land (height 5.0) east of it. The NavGrid is refreshed so the
## sea and the shore cell read as unwalkable.
func _make_coast(w: Dictionary, shore_x: int = 26) -> void:
	for z in range(w.td.verts):
		for x in range(w.td.verts):
			w.td.set_vertex_height(x, z, 1.0 if x < shore_x else 5.0)
	w.nav.update_region(Rect2i(0, 0, w.td.size, w.td.size))


## Gently shelving beach: the seabed rises 0.5 m per metre from x=16 (depth 2 m)
## up to dry land. Unlike _make_coast this has a real shallow zone — the case
## where a body used to sink standing on the waterline.
func _make_beach(w: Dictionary) -> void:
	for z in range(w.td.verts):
		for x in range(w.td.verts):
			w.td.set_vertex_height(x, z, clampf((float(x) - 16.0) * 0.5, 0.0, 6.0))
	w.nav.update_region(Rect2i(0, 0, w.td.size, w.td.size))


func _free_world(w: Dictionary) -> void:
	w.unit_manager.free()


func _spawn(w: Dictionary, scene: PackedScene, tribe_id: int, at: Vector2) -> Unit:
	return w.unit_manager.spawn_unit(scene, tribe_id, Vector3(at.x, 0.0, at.y))


# --- Forced movement into the water ------------------------------------------------

## Knockback used to be CANCELLED at the shoreline (water is unwalkable). It now
## carries the unit in and drowns it. A stacked shove (several fireball hits in
## a row) is used so the displacement actually clears the shore cell.
func test_knockback_pushes_into_water_and_drowns() -> void:
	var w: Dictionary = _make_world()
	_make_coast(w)
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(26.2, 30))
	var x0: float = unit.position.x
	unit.displace(Vector3(-1, 0, 0), 3.0)
	for i in range(40):
		if unit.state == Unit.State.DEAD:
			break
		unit.tick(TICK)
	check(unit.state == Unit.State.DEAD, "a shove into the sea kills")
	check(unit._drowning, "the death is flagged as a drowning")
	check(unit.position.x < x0, "the unit was pushed seawards, not clamped")
	check_near(unit.position.y, TerrainData.SEA_LEVEL - Unit.DROWN_FLOAT_DEPTH,
		"the body floats just below the surface", 0.01)
	_free_world(w)


## Rolling into the sea drowns (and shows the drown pose, not the corpse pose).
func test_roll_into_water_plays_drown_anim() -> void:
	var w: Dictionary = _make_world()
	_make_coast(w)
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	unit.start_roll(Vector3(-1, 0, 0), 5.0)
	for i in range(40):
		if unit.state == Unit.State.DEAD:
			break
		unit.tick(TICK)
	check(unit.state == Unit.State.DEAD, "rolling into water is instant death")
	check(unit._drowning, "the roll death is a drowning")
	check(unit.anim_base_name == &"drown", "the drown animation is playing")
	_free_world(w)


## A roll that ENDS over water (building block / stall probe / time cap) must not
## be snapped back onto the nearest walkable cell any more.
func test_end_roll_over_water_does_not_snap_back() -> void:
	var w: Dictionary = _make_world()
	_make_coast(w)
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	unit.position.x = 20.0        # place it out over the sea
	unit.position.z = 30.0
	unit._end_roll()
	check(unit.state == Unit.State.DEAD, "ending a roll over water drowns")
	check(unit._drowning, "flagged as a drowning")
	check_near(unit.position.x, 20.0, "the unit was NOT pulled back to land", 0.01)
	_free_world(w)


## A coastal cliff now launches units out over the sea (it used to return a drop
## of 0, which made the caller stop at the rim).
func test_cliff_over_water_launches() -> void:
	var w: Dictionary = _make_world()
	# Land at height 8 east of x=27, sea to the west.
	for z in range(w.td.verts):
		for x in range(w.td.verts):
			w.td.set_vertex_height(x, z, 1.0 if x < 27 else 8.0)
	w.nav.update_region(Rect2i(0, 0, w.td.size, w.td.size))
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(27.5, 30))
	var drop: float = unit._cliff_drop_ahead(Vector3(-1, 0, 0))
	check(drop >= Unit.CLIFF_FALL_MIN_DROP,
		"the coastal cliff reports a real drop (%.2f m)" % drop)
	_free_world(w)


## A unit thrown out over the sea drowns on landing.
func test_throw_into_water_drowns() -> void:
	var w: Dictionary = _make_world()
	_make_coast(w)
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(28, 30))
	unit.throw_airborne(Vector3(-12, 5, 0))
	for i in range(60):
		if unit.state == Unit.State.DEAD:
			break
		unit.tick(TICK)
	check(unit.state == Unit.State.DEAD, "landing in the sea kills")
	check(unit._drowning, "the landing death is a drowning")
	_free_world(w)


# --- Pathfinding is untouched -------------------------------------------------------

## The invariant that makes all of the above safe: ordinary movement can still
## never end up in the water.
func test_pathfinding_never_routes_through_water() -> void:
	var w: Dictionary = _make_world()
	_make_coast(w)
	var path: PackedVector3Array = w.nav.find_path(
		Vector3(30, 0, 30), Vector3(10, 0, 30))
	for p in path:
		check(w.td.get_height(p.x, p.z) > TerrainData.SEA_LEVEL,
			"no path waypoint lies in the sea")
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	unit.order_move(Vector3(10, 0, 30))
	for i in range(120):
		unit.tick(TICK)
		w.unit_manager.tick(TICK)
		if unit.state == Unit.State.IDLE:
			break
	check(unit.state != Unit.State.DEAD, "a plain move order never drowns anyone")
	check(w.td.get_height(unit.position.x, unit.position.z) > TerrainData.SEA_LEVEL,
		"the unit ended up on land")
	_free_world(w)


# --- Being pulled just past the waterline ---------------------------------------------

## A unit that goes under right on the shoreline is nudged seawards until it is
## properly behind the waterline — and no further. Water is defined by the sea
## level alone (no modelled depth), so this is a purely horizontal correction.
func test_drowning_body_is_pulled_past_the_waterline() -> void:
	var w: Dictionary = _make_world()
	_make_beach(w)
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	# Right on the waterline: water here, dry land a step further inland.
	unit.position = Vector3(20.0, 0.0, 30.0)
	check(w.td.get_height(unit.position.x + Unit.DROWN_SHORE_MARGIN, 30.0)
		> TerrainData.SEA_LEVEL, "it starts balancing on the waterline")
	unit.drown()
	check(unit._drowning, "the unit drowns")
	var pull: float = unit.position.distance_to(unit._drown_target)
	check(pull > 0.0, "it gets pulled seawards")
	check(pull <= Unit.DROWN_DRAG_MAX,
		"the pull stays short (%.2f m <= %.2f m)" % [pull, Unit.DROWN_DRAG_MAX])
	while not unit._corpse_done:
		unit.tick(TICK)
		if absf(unit.position.x - unit._drown_target.x) < 0.05:
			break
	# Target reached and genuinely past the waterline in the seaward direction.
	check_near(unit.position.x, unit._drown_target.x, "the body arrived", 0.1)
	check(w.td.get_height(unit.position.x, unit.position.z)
		<= TerrainData.SEA_LEVEL + Unit.WATER_EPS, "it sinks in the water")
	check(w.td.get_height(unit.position.x - Unit.DROWN_SHORE_MARGIN, unit.position.z)
		<= TerrainData.SEA_LEVEL + Unit.WATER_EPS,
		"…and a margin further out is still water, so it is not on the edge")
	_free_world(w)


## A unit that is already properly in the water is not moved at all.
func test_drowning_in_open_water_does_not_drag() -> void:
	var w: Dictionary = _make_world()
	_make_beach(w)
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	unit.position = Vector3(12.0, 0.0, 30.0)
	unit.drown()
	check_near(unit._drown_target.x, 12.0, "the drag target is where it died", 0.01)
	check_near(unit._drown_target.z, 30.0, "…on both axes", 0.01)
	_free_world(w)


## Touching water ends every kind of motion — no knockback play-out, no throw
## arc, no rolling slide carries a body on once it is in the sea.
func test_water_contact_kills_all_momentum() -> void:
	var w: Dictionary = _make_world()
	_make_coast(w)
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(12, 30))
	unit.throw_airborne(Vector3(-8, 4, 0))
	unit.displace(Vector3(-1, 0, 0), 3.0)
	unit.drown()
	check(unit._knockback_remaining == Vector3.ZERO, "pending knockback is gone")
	check(unit._throw_velocity == Vector3.ZERO, "the throw velocity is gone")
	check_near(unit._roll_init_speed, 0.0, "no roll momentum is left", 0.001)
	check(unit.throw_carrier == null, "no carrier keeps hold of the body")
	_free_world(w)


# --- Surface splash -------------------------------------------------------------------

## The splash ring shows from the moment of drowning until the body is gone.
func test_drowning_shows_a_surface_splash() -> void:
	var w: Dictionary = _make_world()
	_make_coast(w)
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	check(not unit.water_splash_active(), "a living unit shows no splash")
	unit.position = Vector3(12.0, 0.0, 30.0)
	unit.drown()
	check(unit.water_splash_active(), "the drowning body splashes")
	var t: float = 0.0
	while t < Unit.DROWN_FLAIL_DURATION + Unit.DROWN_SINK_DURATION * 0.5:
		unit.tick(TICK)
		t += TICK
	check(unit.water_splash_active(), "it keeps splashing while it sinks")
	while not unit._corpse_done:
		unit.tick(TICK)
	check(not unit.water_splash_active(), "the splash ends with the body")
	_free_world(w)


## A death on dry land never splashes.
func test_land_death_shows_no_splash() -> void:
	var w: Dictionary = _make_world()
	_make_coast(w)
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(40, 30))
	unit.take_damage(unit.max_health)
	check(unit.state == Unit.State.DEAD, "the unit died on land")
	check(not unit.water_splash_active(), "no splash on dry land")
	_free_world(w)


## Buildings that slide into the sea splash too; ones that sink on land do not.
func test_building_splash_only_in_water() -> void:
	var w: Dictionary = _make_world()
	_make_coast(w)
	var hut: Building = Building.new()
	hut.terrain_data = w.td
	hut.footprint = Vector2i(3, 3)
	hut.position = Vector3(40, 5, 30)
	hut._destroyed = true
	check(not hut.water_splash_active(), "a wreck on land does not splash")
	hut.position = Vector3(12, 1, 30)
	check(hut.water_splash_active(), "a wreck in the sea splashes")
	check(hut.water_splash_radius() > 1.0, "the ring scales with the footprint")
	hut._sink_time = Building.SINK_DURATION
	check(not hut.water_splash_active(), "the splash ends when the wreck is gone")
	hut.free()
	_free_world(w)


## The procedural splash frames widen over their four phases.
func test_splash_frames_expand() -> void:
	var frames: Array[Texture2D] = []
	for i in range(4):
		frames.append(WaterFxRenderer.splash_frame(i))
	check(frames.size() == 4, "four splash phases exist")
	for f in frames:
		check(f.get_width() == WaterFxRenderer.TEX, "frames are square and sized")
	# The ring of the last phase reaches further out than the first one.
	var first: Image = frames[0].get_image()
	var last: Image = frames[3].get_image()
	var edge: int = WaterFxRenderer.TEX - 3
	var mid: int = WaterFxRenderer.TEX / 2
	check(first.get_pixel(edge, mid).a < 0.5, "the first ring is still narrow")
	check(last.get_pixel(edge, mid).a > 0.5, "the last ring has widened outwards")


# --- Everything else that ends up in the water ----------------------------------------

## A siege engine in the sea is destroyed no matter how it got there — the
## vehicle checks its own ground, independently of the spell that flooded it.
func test_vehicle_in_water_destroys_itself() -> void:
	var w: Dictionary = _make_world()
	_make_coast(w)
	var ram: Unit = _spawn(w, FIRE_RAM_SCENE, 0, Vector2(40, 30))
	check(ram.state != Unit.State.DEAD, "it starts alive on land")
	# Move it into the sea without any spell involvement.
	ram.position = Vector3(12.0, 5.0, 30.0)
	for i in range(12):
		ram.tick(TICK)
		if ram.state == Unit.State.DEAD:
			break
	check(ram.state == Unit.State.DEAD, "a siege engine in the sea is destroyed")
	check(ram._sinking, "the wreck sinks")
	_free_world(w)


## Trees swallowed by a terrain morph are destroyed instead of standing in the sea.
func test_flooded_trees_are_destroyed() -> void:
	var w: Dictionary = _make_world()
	var tm: TreeManager = TreeManager.new()
	tm.terrain_data = w.td
	tm.nav_grid = w.nav
	tm.spawn_trees(30, 12345)
	var before: int = tm.trees.size()
	check(before > 0, "trees were planted")
	# Flood the whole map, then run the integrity rules over it.
	for z in range(w.td.verts):
		for x in range(w.td.verts):
			w.td.set_vertex_height(x, z, 0.5)
	check(tm.remove_flooded(Rect2i(0, 0, w.td.size, w.td.size)) == before,
		"every flooded tree is gone")
	check(tm.trees.is_empty(), "no tree is left standing in the sea")
	tm.free()
	_free_world(w)


## Wood piles behave the same, and no new pile can be dropped into the water.
func test_flooded_wood_piles_are_destroyed() -> void:
	var w: Dictionary = _make_world()
	_make_coast(w)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.terrain_data = w.td
	wpm.deposit(Vector3(40, 0, 30), 4)
	check(wpm.piles.size() == 1, "a pile lies on the land")
	# Dropping wood into the sea leaves nothing behind.
	wpm.deposit(Vector3(12, 0, 30), 4)
	check(wpm.piles.size() == 1, "wood dropped into the sea is lost, not floating")
	# Flood the land pile's ground and re-run the rule.
	for z in range(w.td.verts):
		for x in range(w.td.verts):
			w.td.set_vertex_height(x, z, 0.5)
	check(wpm.remove_flooded(Rect2i(0, 0, w.td.size, w.td.size)) == 1,
		"the flooded pile is removed")
	check(wpm.piles.is_empty(), "no wood is left floating")
	wpm.free()
	_free_world(w)


# --- Water sounds ---------------------------------------------------------------------

## A death in water is announced by the splash, not the normal death cry.
func test_drowning_death_sound_is_the_splash() -> void:
	var w: Dictionary = _make_world()
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	check(unit.death_sfx_key() == &"unit_death", "a live unit uses the normal cry")
	unit.drown()
	check(unit.death_sfx_key() == &"water_splash", "drowning plays the splash")
	_free_world(w)


## The sinking wreck of a vehicle announces itself with the splash too.
func test_vehicle_water_death_sound() -> void:
	var w: Dictionary = _make_world()
	_make_coast(w)
	var ram: Unit = _spawn(w, FIRE_RAM_SCENE, 0, Vector2(40, 30))
	ram.drown()
	check(ram.death_sfx_key() == &"water_splash",
		"a wreck going into the sea uses the water sound, not the burn sound")
	_free_world(w)


# --- Corpse behaviour ---------------------------------------------------------------

## A drowned body flails briefly, sinks deep and is gone far sooner than a land
## corpse — nothing may be left floating on the sea.
func test_drowning_corpse_sinks_fast_and_expires() -> void:
	var w: Dictionary = _make_world()
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	var expired: Array[int] = [0]
	unit.corpse_expired.connect(func(_u: Unit) -> void: expired[0] += 1)
	unit.drown()
	check(unit.state == Unit.State.DEAD, "drown() kills immediately")
	check_near(unit.corpse_sink_depth(), 0.0, "it floats while flailing", 0.001)
	var t: float = 0.0
	while t < Unit.DROWN_FLAIL_DURATION - TICK:
		unit.tick(TICK)
		t += TICK
	check_near(unit.corpse_sink_depth(), 0.0, "still at the surface after the flail", 0.05)
	while t < Unit.DROWN_FLAIL_DURATION + Unit.DROWN_SINK_DURATION + TICK:
		unit.tick(TICK)
		t += TICK
	check(expired[0] == 1, "corpse_expired fired exactly once")
	check(t < Balance.CORPSE_DURATION,
		"a drowned body is gone long before a land corpse would be")
	_free_world(w)


## Guards the main risk of the feature: the kernel corpse hold skips the whole
## object tick, so a held drowning unit would float on the sea for the full
## CORPSE_DURATION instead of sinking.
func test_drowning_unit_is_never_kernel_held() -> void:
	var w: Dictionary = _make_world()
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	unit.drown()
	var last: float = unit._corpse_timer
	for i in range(15):
		unit.tick(TICK)
		w.unit_manager.tick(TICK)
		check(unit._idx < 0 or w.unit_manager.soa_hold[unit._idx] < 0.0,
			"the drowning unit is never parked in the corpse hold")
		if unit._corpse_done:
			break
		check(unit._corpse_timer > last, "the corpse timer keeps running")
		last = unit._corpse_timer
	_free_world(w)


## A normal (land) death keeps the long corpse curve and the kernel hold.
func test_land_corpse_keeps_its_long_curve() -> void:
	var w: Dictionary = _make_world()
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	unit.take_damage(unit.max_health)
	check(unit.state == Unit.State.DEAD, "the unit died")
	check(not unit._drowning, "a land death is not a drowning")
	check(unit.anim_base_name == &"dead", "it uses the corpse pose")
	check_near(unit._corpse_lie_duration(), Balance.CORPSE_DURATION,
		"the land corpse lies for the full duration", 0.001)
	_free_world(w)


# --- Animations ----------------------------------------------------------------------

## THROWN and ROLL are visually distinct now (they both used to render "roll").
func test_thrown_unit_uses_airborne_anim() -> void:
	var w: Dictionary = _make_world()
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	unit.throw_airborne(Vector3(2, 6, 0))
	unit.tick(TICK)
	check(unit.state == Unit.State.THROWN, "the unit is in the air")
	check(unit.anim_base_name == &"airborne", "flying uses the airborne animation")
	for i in range(60):
		if unit.state != Unit.State.THROWN:
			break
		unit.tick(TICK)
	check(unit.state == Unit.State.ROLL, "it tumbles on after landing")
	check(unit.anim_base_name == &"roll", "the ground tumble uses the roll animation")
	_free_world(w)


# --- Vehicles ------------------------------------------------------------------------

## Vehicles keep their own wreck sink; they never use the sprite drown pose, and
## the wreck starts sinking AT the surface (with an opaque sea it would
## otherwise be born invisible on the seabed).
func test_vehicle_drown_stays_instant() -> void:
	var w: Dictionary = _make_world()
	var ram: Unit = _spawn(w, FIRE_RAM_SCENE, 0, Vector2(30, 30))
	ram.position.y = 1.0   # standing on the sea floor
	ram.drown()
	check(ram.state == Unit.State.DEAD, "the vehicle dies")
	check(not ram._drowning, "a vehicle does not use the sprite drown pose")
	check(ram._sinking, "the wreck sinks with its own vehicle sink")
	check(ram.position.y >= TerrainData.SEA_LEVEL,
		"the wreck starts sinking at the water surface")
	_free_world(w)


# --- Terrain / shore colour ----------------------------------------------------------

## The sea is opaque and has no depth, so the seabed is not meshed at all — but
## the band around the waterline must survive, or a wave trough would open a
## hole into the void.
func test_seabed_is_not_meshed() -> void:
	var td: TerrainData = _flat_terrain()
	var deep: float = TerrainData.SEA_LEVEL - Terrain.SEABED_CULL_MARGIN - 1.0
	for i in range(td.heights.size()):
		td.heights[i] = deep
	# A single land plateau so the map is not entirely sea. It has to sit near the
	# MIDDLE: since phase 10j the map is a disc, and a plateau in the square's corner
	# would be in the void — unmeshed for that reason instead of the one under test.
	var mid: int = td.size / 2
	for z in range(mid - 8, mid + 12):
		for x in range(mid - 8, mid + 12):
			td.set_vertex_height(x, z, 6.0)
	var terrain: Terrain = Terrain.new()
	terrain.build(td)
	var chunk_mid: int = mid / Terrain.CHUNK
	# Open sea, but still well inside the disc.
	var open_sea: MeshInstance3D = terrain.get_node_or_null(
		"Chunks/Chunk_%d_%d" % [chunk_mid - 2, chunk_mid])
	check(open_sea != null and open_sea.mesh == null,
		"a chunk of pure open sea carries no mesh at all")
	var land: MeshInstance3D = terrain.get_node_or_null(
		"Chunks/Chunk_%d_%d" % [chunk_mid, chunk_mid])
	check(land != null and land.mesh != null, "the land chunk is meshed")
	# Shallow water just under the line stays, so nothing shows through a trough.
	for z in range(td.verts):
		for x in range(td.verts):
			td.set_vertex_height(x, z, TerrainData.SEA_LEVEL - 0.1)
	terrain.rebuild_chunks(Rect2i(0, 0, td.size, td.size))
	var shallow: MeshInstance3D = terrain.get_node_or_null("Chunks/Chunk_5_5")
	check(shallow != null and shallow.mesh != null,
		"terrain right under the waterline is still meshed")
	terrain.free()


## The waterline gets a darker wet-sand band that fades into dry sand.
func test_shore_color_is_wet_sand() -> void:
	var terrain: Terrain = Terrain.new()
	var wet: Color = terrain._color_for_height(TerrainData.SEA_LEVEL + 0.05)
	var dry: Color = terrain._color_for_height(TerrainData.SEA_LEVEL + Terrain.SHORE_BAND + 0.1)
	check(wet.v < dry.v, "sand right at the waterline is darker (wet)")
	check(dry.is_equal_approx(Terrain.COLOR_SAND), "beyond the band it is plain sand")
	terrain.free()
