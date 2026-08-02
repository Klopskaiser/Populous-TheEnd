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

## The waterline gets a darker wet-sand band that fades into dry sand.
func test_shore_color_is_wet_sand() -> void:
	var terrain: Terrain = Terrain.new()
	var wet: Color = terrain._color_for_height(TerrainData.SEA_LEVEL + 0.05)
	var dry: Color = terrain._color_for_height(TerrainData.SEA_LEVEL + Terrain.SHORE_BAND + 0.1)
	check(wet.v < dry.v, "sand right at the waterline is darker (wet)")
	check(dry.is_equal_approx(Terrain.COLOR_SAND), "beyond the band it is plain sand")
	terrain.free()
