extends TestBase

## Phase 10k, Teil 5: der Vulkan hat einen echten KRATER statt eines spitzen
## Kegels — breiter (Radius 7 statt 5), der höchste Ring ist der Kraterrand, und
## innen liegt eine Mulde, in der die Lava hochquillt. Fließt sie über den Rand,
## füllt ein zweiter Morph die Mulde zum kleinen Gipfelplateau.
##
## Der wichtigste Test hier ist NICHT die Form, sondern
## test_a_single_surge_still_wrecks_a_building: Phase 10c hält im Code fest, dass
## der Gebäudeschaden des Vulkans an DURCHGEHENDEM Lavakontakt hängt. Mit nur
## noch EINEM Schwall (10k) darf er nicht still ausfallen.

const TICK: float = 0.1
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")


func _flat_terrain(h: float = 6.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


func _make_world(h: float = 6.0) -> Dictionary:
	var td: TerrainData = _flat_terrain(h)
	var nav: NavGrid = NavGrid.new(td)
	var t0: Tribe = Tribe.new(0)
	var t1: Tribe = Tribe.new(1)
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [t0, t1] as Array[Tribe], tm, wpm)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um, wpm)
	var ctx: SpellContext = SpellContext.new()
	ctx.terrain_data = td
	ctx.nav_grid = nav
	ctx.unit_manager = um
	ctx.building_manager = bm
	ctx.tree_manager = tm
	ctx.wood_pile_manager = wpm
	return {"td": td, "nav": nav, "t0": t0, "t1": t1, "um": um, "bm": bm,
		"tm": tm, "wpm": wpm, "ctx": ctx}


func _free_world(w: Dictionary) -> void:
	w.tm.free()
	w.wpm.free()
	w.bm.free()
	w.um.free()


# --- Die Form (reine Funktion) ------------------------------------------------

func test_the_rim_is_the_highest_point() -> void:
	var rim: float = VolcanoSpell.crater_profile(VolcanoSpell.RIM_RADIUS)
	check_near(rim, VolcanoSpell.PEAK, "the rim reaches the full peak height", 0.01)
	# Nowhere is higher than the rim — that is what makes it a crater.
	var highest: float = -1000.0
	for i in range(0, 141):
		highest = maxf(highest, VolcanoSpell.crater_profile(float(i) * 0.05))
	check_near(highest, rim, "no point of the profile rises above the rim", 0.01)


func test_the_hollow_sits_below_the_rim() -> void:
	var centre: float = VolcanoSpell.crater_profile(0.0)
	var rim: float = VolcanoSpell.crater_profile(VolcanoSpell.RIM_RADIUS)
	check_near(rim - centre, VolcanoSpell.CRATER_DEPTH,
		"the hollow lies CRATER_DEPTH below the rim", 0.01)
	check(centre > 0.0, "but still well above the surrounding ground")


func test_the_foot_is_untouched() -> void:
	check_near(VolcanoSpell.crater_profile(VolcanoSpell.RADIUS), 0.0,
		"at the outer radius the profile is back to ground level", 0.01)
	check_near(VolcanoSpell.crater_profile(VolcanoSpell.RADIUS + 3.0), 0.0,
		"and beyond it nothing changes", 0.01)


func test_the_outer_flank_rises_monotonically_toward_the_rim() -> void:
	var prev: float = -1000.0
	var monotone: bool = true
	var d: float = VolcanoSpell.RADIUS
	while d >= VolcanoSpell.RIM_RADIUS:
		var h: float = VolcanoSpell.crater_profile(d)
		if h < prev - 0.0001:
			monotone = false
		prev = h
		d -= 0.05
	check(monotone, "walking inward from the foot, the flank only rises")


func test_the_volcano_got_wider() -> void:
	check(Balance.VOLCANO_RADIUS > 5.0,
		"the mountain is wider than the old cone (%.1f m)" % Balance.VOLCANO_RADIUS)
	check(Balance.VOLCANO_SURGE_COUNT == 1, "ONE big surge instead of two")
	check(Balance.VOLCANO_LAVA_LIFETIME > Balance.LAVA_LIFETIME,
		"and its lava lives longer, so it runs further")


# --- Der Krater im Gelände ----------------------------------------------------

func test_casting_leaves_a_crater_in_the_terrain() -> void:
	var w: Dictionary = _make_world()
	var centre: Vector3 = Vector3(60.0, 6.0, 60.0)
	var spell: VolcanoSpell = VolcanoSpell.new()
	check(spell.execute(w.t0, centre, w.ctx), "the volcano was cast")
	# Run the morph out.
	for i in range(int((VolcanoSpell.DURATION + 0.5) / TICK)):
		w.um._tick_projectiles(TICK)
	var h_centre: float = w.td.get_height(centre.x, centre.z)
	var h_rim: float = w.td.get_height(centre.x + VolcanoSpell.RIM_RADIUS, centre.z)
	var h_foot: float = w.td.get_height(centre.x + VolcanoSpell.RADIUS + 1.0, centre.z)
	check(h_rim > h_centre + 0.5,
		"the rim stands above the hollow (%.2f vs %.2f)" % [h_rim, h_centre])
	check(h_rim > h_foot + 3.0, "and well above the surrounding ground")
	check(h_centre > h_foot, "the hollow is still a mountain top, not a pit")
	_free_world(w)


## Nach dem Überlaufen ist oben ein kleines rundes PLATEAU — und das ist eben.
func test_the_crater_fills_to_a_flat_plateau() -> void:
	var w: Dictionary = _make_world()
	var centre: Vector3 = Vector3(60.0, 6.0, 60.0)
	var base: float = w.td.get_height(centre.x, centre.z)
	var plan: Dictionary = VolcanoSpell.fill_crater_targets(
		w.td, Vector2(centre.x, centre.z), base)
	var idx: PackedInt32Array = plan.indices
	check(not idx.is_empty(), "the fill plan covers the hollow")
	# Apply it directly (the morph only animates the same values).
	var targets: PackedFloat32Array = plan.targets
	for i in range(idx.size()):
		w.td.heights[idx[i]] = targets[i]
	var want: float = base + VolcanoSpell.PEAK
	var flat: bool = true
	# Well INSIDE the filled circle: get_height interpolates between vertices, so
	# sampling near the edge would drag unfilled neighbours into the average.
	var r: float = VolcanoSpell.RIM_RADIUS - 1.5
	for a in range(8):
		var ang: float = TAU * float(a) / 8.0
		var h: float = w.td.get_height(centre.x + cos(ang) * r, centre.z + sin(ang) * r)
		if absf(h - want) > 0.05:
			flat = false
	check(flat, "the plateau is level at rim height")
	check_near(w.td.get_height(centre.x, centre.z), want,
		"including its middle", 0.05)
	_free_world(w)


func test_the_fill_never_lowers_the_ground() -> void:
	var w: Dictionary = _make_world()
	var centre: Vector2 = Vector2(60.0, 60.0)
	# Ground ALREADY above rim height: the fill must not dig it away.
	var base: float = 0.0
	var plan: Dictionary = VolcanoSpell.fill_crater_targets(w.td, centre, base)
	var idx: PackedInt32Array = plan.indices
	check(idx.is_empty(),
		"nothing to raise when the ground is already at or above rim level")
	_free_world(w)


# --- Der Wächter aus der 10c-Falle -------------------------------------------

## Phase 10c hält fest: der Gebäudeschaden des Vulkans kommt aus DURCHGEHENDEM
## Lavakontakt (Building.add_lava_contact, eine Stufe je LAVA_BUILDING_STAGE_TIME).
## Mit nur noch EINEM Schwall darf er nicht still ausfallen — deshalb die längere
## Lebensdauer der Vulkanlava.
func test_a_single_surge_still_wrecks_a_building() -> void:
	var w: Dictionary = _make_world()
	var centre: Vector3 = Vector3(60.0, 6.0, 60.0)
	# Hut just outside the cone, inside the lava reach.
	var hut: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(64, 58), 0, true)
	check(hut != null, "the enemy hut stands next to the volcano")
	var stage_before: int = hut.destruction_stage()
	var spell: VolcanoSpell = VolcanoSpell.new()
	check(spell.execute(w.t0, centre, w.ctx), "the volcano was cast")
	var elapsed: float = 0.0
	while elapsed < Balance.VOLCANO_ZONE_LIFETIME + 5.0:
		w.um._tick_projectiles(TICK)
		w.bm.tick(TICK)
		elapsed += TICK
		if not is_instance_valid(hut) or hut.health <= 0:
			break
	var wrecked: bool = not is_instance_valid(hut) or hut.health <= 0 \
		or hut.destruction_stage() > stage_before
	check(wrecked,
		"a single surge still damages a building in reach (10c trap: the damage "
			+ "needs CONTINUOUS lava contact)")
	check(Balance.VOLCANO_LAVA_LIFETIME
		> Balance.LAVA_MOLTEN_TIME + Balance.LAVA_BUILDING_CONTACT_GRACE,
		"and its lifetime outlasts the molten window plus the contact grace")
	_free_world(w)
