extends TestBase

## Bug-Backlog #2: construction sites must be destroyable by units. A site's
## HP scale with the delivered-wood fraction (wood_delivered / wood_cost),
## capped at 3/4 of the finished building's HP (3 destruction stages — a site
## never has the full 4). Melee raiders demolish it like a finished building;
## at 0 HP the site is destroyed and the plot is free again.
## Since 2026-11-23 (user spec) a site only becomes a target once the first wood is
## BUILT IN (build_progress > 0, scaffold stage 1): a bare plot is no target and
## takes no damage. The tests below therefore start the build first.

const TICK: float = 0.1
const MAX_TICKS: int = 1500

const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")


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
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe0, tribe1] as Array[Tribe], null, wpm)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um, wpm)
	um.building_manager = bm
	return {"td": td, "nav": nav, "tribe0": tribe0, "tribe1": tribe1,
		"unit_manager": um, "bm": bm, "wpm": wpm}


func _free_world(w: Dictionary) -> void:
	w.bm.free()
	w.unit_manager.free()
	w.wpm.free()


func _run(w: Dictionary, units: Array, done: Callable) -> int:
	for i in range(MAX_TICKS):
		if done.call():
			return i
		for u in units:
			if is_instance_valid(u) and u.state != Unit.State.DEAD:
				u.tick(TICK)
		w.unit_manager.tick(TICK)
		w.bm.tick(TICK)
	return MAX_TICKS


## Unfinished hut (construction site) of the enemy tribe.
func _site(w: Dictionary) -> Building:
	return w.bm.place(HUT_SCENE, w.tribe1, Vector2i(40, 40), 0, false)


## Delivers `amount` wood to the site via piles at the delivery point (absorbed
## on the construction tick, like worker deliveries).
func _deliver_wood(w: Dictionary, site: Building, amount: int) -> void:
	w.wpm.deposit(site.delivery_point(), amount)
	for i in range(40):
		site.tick(0.5)
		if site.wood_delivered >= amount:
			break


## Levels the plot and builds in a first bit of the delivered wood: from here on
## the site stands as a scaffold and is attackable (2026-11-23).
func _start_building(site: Building) -> void:
	for c in site._flatten_remaining.keys():
		site.work_flatten(c, 100.0)
	site.add_build_progress(0.01)


# --- Site HP model -------------------------------------------------------------

func test_fresh_site_has_minimal_hp() -> void:
	var w: Dictionary = _make_world()
	var site: Building = _site(w)
	check(site.under_construction, "site starts under construction")
	check(site.health == 1, "a site with no wood built in has minimal HP (got %d)" % site.health)
	_free_world(w)


func test_site_hp_scales_with_delivered_wood() -> void:
	var w: Dictionary = _make_world()
	var site: Building = _site(w)
	# Aus Balance abgeleitet: die Huettenkosten sind mehrfach gesunken (12 -> 8 -> 7),
	# und feste Zahlen brachen hier jedes Mal.
	var full: int = Balance.HUT_WOOD_COST
	var half: int = full / 2
	_deliver_wood(w, site, half)
	check(site.wood_delivered == half,
		"%d von %d Holz geliefert (got %d)" % [half, full, site.wood_delivered])
	var expect_half: int = maxi(1, int(round(float(site.max_health)
		* minf(float(half) / float(full), Building.SITE_HP_CAP_FRACTION))))
	check(site.health == expect_half,
		"HP folgen dem gelieferten Holzanteil (erwartet %d, got %d)"
			% [expect_half, site.health])
	_deliver_wood(w, site, full - half)
	check(site.wood_delivered == full, "all wood delivered")
	var expect_cap: int = int(round(float(site.max_health) * Building.SITE_HP_CAP_FRACTION))
	check(site.health == expect_cap,
		"site HP capped at 3/4 of the full HP (erwartet %d, got %d)"
			% [expect_cap, site.health])
	_free_world(w)


func test_finish_restores_full_hp_minus_damage() -> void:
	var w: Dictionary = _make_world()
	var site: Building = _site(w)
	_deliver_wood(w, site, Balance.HUT_WOOD_COST)   # voller Preis
	_start_building(site)
	var cap: int = int(round(float(site.max_health) * Building.SITE_HP_CAP_FRACTION))
	site.take_damage(100)
	check(site.health == cap - 100,
		"damaged site at %d - 100 HP (got %d)" % [cap, site.health])
	site.finish_construction()
	check(not site.under_construction, "construction finished")
	check(site.health == site.max_health - 100,
		"damage carries over into the finished building (got %d)" % site.health)
	_free_world(w)


func test_prebuilt_building_keeps_full_hp() -> void:
	var w: Dictionary = _make_world()
	var hut: Building = w.bm.place(HUT_SCENE, w.tribe1, Vector2i(60, 60), 0, true)
	check(hut.health == hut.max_health,
		"pre-built building has full HP (got %d)" % hut.health)
	_free_world(w)


# --- Units destroy construction sites -------------------------------------------

func test_melee_raiders_demolish_site() -> void:
	var w: Dictionary = _make_world()
	var site: Building = _site(w)
	_deliver_wood(w, site, Balance.HUT_WOOD_COST / 2)   # Teil-HP, der Abriss muss sie abbauen
	_start_building(site)
	for i in range(3):
		site.admit_raider(w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, Vector3(41 + i, 0, 41)))
	check(site.raiders.size() == 3, "3 raiders inside the site")
	var hp: int = site.health
	site.tick(1.0)
	check(site.health < hp, "raiders damage the construction site (still %d HP)" % site.health)
	var razed: int = _run(w, [], func() -> bool: return site.health <= 0)
	check(razed < MAX_TICKS, "raiders raze the construction site")
	check(site not in w.bm.buildings, "razed site deregistered")
	check(w.nav.is_cell_walkable(Vector2i(41, 41)), "plot walkable/buildable again")
	_free_world(w)


func test_ordered_warriors_raze_site() -> void:
	var w: Dictionary = _make_world()
	var site: Building = _site(w)
	_deliver_wood(w, site, 2)
	_start_building(site)
	var squad: Array[Unit] = []
	for i in range(4):
		var wr: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, Vector3(35 + i, 0, 35))
		wr.order_attack_building(site)
		squad.append(wr)
	var razed: int = _run(w, squad, func() -> bool: return site.health <= 0)
	# Well before the 120-s construction decay could pass for a razing.
	check(razed < 600, "ordered warriors destroy the construction site (%d ticks)" % razed)
	_free_world(w)


func test_firewarrior_bombards_site() -> void:
	var w: Dictionary = _make_world()
	var site: Building = _site(w)
	_deliver_wood(w, site, Balance.HUT_WOOD_COST / 2)   # Teil-HP
	_start_building(site)
	var fw: Unit = w.unit_manager.spawn_unit(FIREWARRIOR_SCENE, 0, Vector3(35, 0, 35))
	fw.order_attack_building(site)
	var razed: int = _run(w, [fw], func() -> bool: return site.health <= 0)
	check(razed < 1000, "firewarrior fire destroys the construction site (%d ticks)" % razed)
	_free_world(w)


# --- Bare plot, scaffold stages (Nutzervorgabe 2026-11-23) ------------------------

## Kein Holz verbaut: nur der Grundriss, kein Ziel, kein Schaden. Mit dem ersten
## verbauten Holz steht Geruststufe 1 und die Baustelle ist angreifbar; drei
## Geruststufen, in der letzten Baustufe steht das Gebaeude im Geruest.
func test_bare_plot_is_no_target_until_first_wood_is_built_in() -> void:
	var w: Dictionary = _make_world()
	var site: Building = _site(w)
	check(site.is_bare_plot() and not site.is_attackable(), "fresh plot: bare, no target")
	check(site.construction_visual_stage() == 0, "stage 0 = ground plan")
	site.take_damage(50)
	site.apply_destruction_stages(2)
	site.add_lava_contact(60.0)
	check(site.health > 0 and site in w.bm.buildings, "a bare plot takes no damage")
	# Wood delivered but not yet built in: still only the plan.
	_deliver_wood(w, site, 3)
	check(site.wood_delivered == 3 and site.is_bare_plot(), "delivered wood alone builds nothing")
	# Units neither take the order nor find it with their own scan.
	var wr: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, Vector3(38, 0, 38))
	wr.order_attack_building(site)
	check(wr.attack_building == null, "an attack order on a bare plot is refused")
	check(wr._scan_for_enemy_building(30.0) == null, "the building scan skips a bare plot")
	# First wood built in: scaffold stage 1, attackable.
	_start_building(site)
	check(not site.is_bare_plot() and site.is_attackable(), "built-in wood: a target")
	check(site.construction_visual_stage() == 1, "scaffold tier 1")
	check(wr._scan_for_enemy_building(30.0) == site, "now the scan finds it")
	_deliver_wood(w, site, Balance.HUT_WOOD_COST)
	var expected: Array[int] = [2, 3, 4]
	var at: Array[float] = [0.3, 0.6, 0.8]
	for i in range(3):
		site.build_progress = at[i]
		check(site.construction_visual_stage() == expected[i],
			"progress %.1f -> stage %d (got %d)" % [at[i], expected[i], site.construction_visual_stage()])
	site.finish_construction()
	check(site.construction_visual_stage() == Building.VIS_FINISHED, "finished building")
	_free_world(w)


## Die Optik selbst (im Szenenbaum): Grundriss + Pfeil, Geruest mit drei Stufen,
## das Modell erst in der letzten Baustufe sichtbar.
func test_scaffold_visuals_follow_the_stages() -> void:
	var w: Dictionary = _make_world()
	var site: Building = _site(w)
	# Headless tests run outside the scene tree, so _ready (which builds the
	# visuals) never fires on its own - call it like the tree would.
	site._ready()
	var plan: Node = site.get_node_or_null("PlotMarker")
	check(plan != null and (plan as MeshInstance3D).mesh != null, "bare plot: ground plan mesh")
	check(site.get_node_or_null("Scaffold") == null, "bare plot: no scaffold")
	check(not site._mesh_root.visible, "bare plot: no building")
	_deliver_wood(w, site, Balance.HUT_WOOD_COST)
	_start_building(site)
	var sc: Scaffold = site.get_node_or_null("Scaffold") as Scaffold
	check(sc != null and sc.tiers.size() == 3, "scaffold with three tiers")
	check(site.get_node_or_null("PlotMarker") == null or site._plot_marker == null,
		"the ground plan is gone once building started")
	if sc != null:
		check(sc.shown_tiers == 1 and not site._mesh_root.visible, "stage 1: one tier, no building")
		check(sc.size.y >= 1.8, "scaffold as tall as the building (%.1f m)" % sc.size.y)
		site.add_build_progress(0.3)
		check(sc.shown_tiers == 2, "stage 2: two tiers")
		site.add_build_progress(0.25)
		check(sc.shown_tiers == 3 and not site._mesh_root.visible, "stage 3: three tiers")
		site.add_build_progress(0.2)
		check(sc.shown_tiers == 3 and site._mesh_root.visible
			and site._mesh_root.scale == Vector3.ONE, "stage 4: the full building inside the scaffold")
	site.finish_construction()
	check(site._scaffold == null and site._mesh_root.visible, "finished: scaffold gone")
	_free_world(w)
