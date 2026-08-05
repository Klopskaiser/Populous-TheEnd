extends TestBase

## Headless tests for phase 10i, part 1: construction sites where nothing
## happens. Each test reproduces ONE link of the reported causal chain, so a
## regression points at the link that broke.
##
## The chain: delivery_point() was recomputed on every call and the ring search
## returned the first walkable perimeter cell in raster order. A neighbouring
## footprint (or any graded cell) therefore made the anchor JUMP across the
## building — on an 8x8 up to ~14 m, far outside ABSORB_RADIUS. Wood dropped at
## the old spot was never booked, wants_more_wood() stayed true forever, the
## workers kept fetching wood (the reported ever-growing pile) and
## progress_cap() stayed 0, so they hammered a site that could never advance.

const TICK: float = 0.5
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const FIREWARRIOR_CAMP_SCENE: PackedScene = preload(
	"res://scenes/buildings/firewarrior_camp.tscn")
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
	var enemy: Tribe = Tribe.new(1)
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe, enemy] as Array[Tribe], tm, wpm)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um, wpm)
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(nav, bm, um, tm)
	return {
		"td": td, "nav": nav, "tribe": tribe, "enemy": enemy,
		"unit_manager": um, "building_manager": bm,
		"tree_manager": tm, "wood_pile_manager": wpm, "commands": tc,
	}


func _free_world(w: Dictionary) -> void:
	w.commands.free()
	w.tree_manager.free()
	w.wood_pile_manager.free()
	w.building_manager.free()
	w.unit_manager.free()


## Ticks buildings (and every unit) for `seconds` of game time.
func _run_for(w: Dictionary, seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds:
		for u in w.unit_manager.units.duplicate():
			if is_instance_valid(u):
				u.tick(TICK)
		w.building_manager.tick(TICK)
		elapsed += TICK


# --- F1: the anchor stays put --------------------------------------------------------

## THE core guard of the phase. Everything else in the chain hangs off this
## anchor, so nothing in the neighbourhood may move it while it is still usable.
##
## The decisive step is the LAST one: with the entrance blocked the anchor is a
## perimeter cell, and when the entrance frees up again the old code silently
## returned to it (the entrance is tested before the rings) — the anchor jumped
## away from the wood already lying at the perimeter.
func test_delivery_point_stays_put_when_neighbours_change() -> void:
	var w: Dictionary = _make_world()
	var site: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	var entrance: Vector2i = site.entrance_cell()
	# Exactly what a neighbouring footprint does: the entrance cell goes solid.
	w.nav.fill_solid_region(Rect2i(entrance, Vector2i.ONE), true)
	var anchor: Vector3 = site.delivery_point()
	check(w.nav.world_to_cell(anchor) != entrance,
		"with the entrance blocked the anchor is a perimeter cell")

	# Terrain deformation nearby (every graded cell does this) must not move it.
	w.td.raise_area(Vector2(58.0, 58.0), 3.0, 0.8)
	w.nav.update_region(Rect2i(54, 54, 12, 12))
	check(site.delivery_point() == anchor,
		"a terrain change nearby does not move the delivery point")

	# Another building appearing next door must not move it either.
	var neighbour: Hut = w.commands.place_building(
		w.tribe, HUT_SCENE, Vector2i(66, 60)) as Hut
	check(neighbour != null, "the neighbouring plot was placeable")
	check(site.delivery_point() == anchor,
		"a new neighbour does not move the delivery point")

	# The blocked entrance becomes free again (neighbour razed, cell graded).
	w.nav.fill_solid_region(Rect2i(entrance, Vector2i.ONE), false)
	check(w.nav.is_cell_walkable(entrance), "the entrance cell is walkable again")
	check(site.delivery_point() == anchor,
		"a freed entrance does NOT pull the anchor off the wood lying at it")
	_free_world(w)


## The remembered anchor is given up only when it actually became unwalkable —
## then a fresh, walkable one is picked.
func test_delivery_point_is_renewed_only_when_it_became_unwalkable() -> void:
	var w: Dictionary = _make_world()
	var site: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	var anchor: Vector3 = site.delivery_point()
	var anchor_cell: Vector2i = w.nav.world_to_cell(anchor)

	# Drown exactly the anchor cell: it stops being walkable.
	for vz in range(anchor_cell.y, anchor_cell.y + 2):
		for vx in range(anchor_cell.x, anchor_cell.x + 2):
			w.td.set_vertex_height(vx, vz, TerrainData.SEA_LEVEL - 2.0)
	w.nav.update_region(Rect2i(anchor_cell - Vector2i.ONE, Vector2i(4, 4)))
	check(not w.nav.is_cell_walkable(anchor_cell), "the old anchor cell sank")

	var fresh: Vector3 = site.delivery_point()
	check(fresh != anchor, "an unwalkable anchor is replaced")
	check(w.nav.is_cell_walkable(w.nav.world_to_cell(fresh)),
		"the replacement is walkable")
	_free_world(w)


# --- F2: the ring search picks the nearest cell --------------------------------------

## Per ring the candidate CLOSEST to the entrance wins, not the first one the
## raster loop happens to hit (which was north-west biased).
func test_delivery_point_prefers_the_cell_nearest_the_entrance() -> void:
	var w: Dictionary = _make_world()
	var fp: Vector2i = Balance.HUT_FOOTPRINT
	var origin: Vector2i = Vector2i(60, 60)
	var entrance: Vector2i = Building.entrance_cell_for(origin, fp, 0)
	# Block the entrance cell itself so the search has to fall into ring 1.
	w.td.set_vertex_height(entrance.x, entrance.y, TerrainData.SEA_LEVEL - 2.0)
	w.nav.update_region(Rect2i(entrance - Vector2i.ONE, Vector2i(3, 3)))
	check(not w.nav.is_cell_walkable(entrance), "the entrance cell is unusable")

	var picked: Vector2i = Building.approach_cell_for(w.nav, origin, fp, 0)
	check(picked.x >= 0, "a replacement approach cell was found")
	var picked_d: float = Vector2(picked - entrance).length()
	# The raster loop would have returned the north-west corner of ring 1.
	var nw_corner: Vector2i = origin - Vector2i.ONE
	var nw_d: float = Vector2(nw_corner - entrance).length()
	check(picked_d < nw_d,
		"the pick is nearer the entrance than the north-west raster corner")
	check(picked_d <= sqrt(2.0) + 0.001,
		"it is one of the cells adjoining the entrance")
	_free_world(w)


## A plot nobody can ever serve still reports "no approach cell" — the signal
## _recruit_workers and order_build rely on.
func test_fully_enclosed_plot_reports_no_approach_cell() -> void:
	var w: Dictionary = _make_world()
	var fp: Vector2i = Vector2i(2, 2)
	var origin: Vector2i = Vector2i(60, 60)
	# Sink everything around the plot out to beyond the search rings.
	var pad: int = Building.APPROACH_SEARCH_RINGS + 1
	for vz in range(origin.y - pad, origin.y + fp.y + pad + 1):
		for vx in range(origin.x - pad, origin.x + fp.x + pad + 1):
			if vx >= origin.x and vx <= origin.x + fp.x \
					and vz >= origin.y and vz <= origin.y + fp.y:
				continue
			w.td.set_vertex_height(vx, vz, TerrainData.SEA_LEVEL - 2.0)
	w.nav.update_region(Rect2i(origin - Vector2i(pad, pad),
		fp + Vector2i(pad * 2 + 1, pad * 2 + 1)))
	check(Building.approach_cell_for(w.nav, origin, fp, 0) == Vector2i(-1, -1),
		"an island-less plot has no approach cell at all")
	_free_world(w)


# --- The chain: wood is booked and the site advances ---------------------------------

## The endless loop, as a consequence test: with a jumping anchor the delivered
## wood was never booked, wood_delivered stayed 0 and wants_more_wood() never
## turned false, so every free hand kept fetching wood — the reported pile that
## grew without bound.
##
## Geometry makes the jump decisive: on an 8x8 camp with only the northern
## approach left, the perimeter anchor sits ~9 m from the entrance, well beyond
## ABSORB_RADIUS. The old code returned to the entrance the moment it was free.
func test_wood_is_booked_even_after_the_entrance_frees_up() -> void:
	var w: Dictionary = _make_world()
	var camp: Building = w.commands.place_building(
		w.tribe, FIREWARRIOR_CAMP_SCENE, Vector2i(50, 50))
	check(camp != null, "the 8x8 camp was placeable")
	var entrance: Vector2i = camp.entrance_cell()
	# Only the north side is approachable: south, east and west bands go solid
	# (neighbouring footprints in the real report).
	w.nav.fill_solid_region(Rect2i(47, 58, 14, 3), true)
	w.nav.fill_solid_region(Rect2i(58, 47, 3, 14), true)
	w.nav.fill_solid_region(Rect2i(47, 47, 3, 14), true)
	var anchor: Vector3 = camp.delivery_point()
	var anchor_cell: Vector2i = w.nav.world_to_cell(anchor)
	check(anchor_cell.y < camp.cell.y, "the anchor sits on the north side")
	check(Vector2(anchor_cell - entrance).length() > Building.ABSORB_RADIUS,
		"the anchor is farther from the entrance than the absorption radius")

	# The workers drop their load at the anchor ...
	var cost: int = Balance.FIREWARRIOR_CAMP_WOOD_COST
	w.wood_pile_manager.deposit(anchor, cost)
	# ... and only then does the entrance become usable again.
	w.nav.fill_solid_region(Rect2i(47, 58, 14, 3), false)
	check(w.nav.is_cell_walkable(entrance), "the entrance is walkable again")

	_run_for(w, 3.0)
	check(camp.wood_delivered >= cost,
		"the wood at the anchor is booked (%d of %d)" % [camp.wood_delivered, cost])
	check(not camp.wants_more_wood(), "the site stops asking for wood")
	check(camp.progress_cap() >= 1.0, "build progress is no longer capped at 0")
	_free_world(w)


## Symptom 1 end to end: a hut right next to a hut gets built.
func test_site_next_to_a_hut_still_makes_progress() -> void:
	var w: Dictionary = _make_world()
	var first: Hut = w.building_manager.place(
		HUT_SCENE, w.tribe, Vector2i(60, 60), 0, true) as Hut
	check(first != null, "the finished neighbour stands")
	var site: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 65)) as Hut
	check(site != null, "the tight second plot was placeable")

	w.wood_pile_manager.deposit(site.delivery_point(), Hut.WOOD_COST)
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, site.delivery_point()) as Brave
	brave.order_build(site)
	_run_for(w, 90.0)
	check(not site.under_construction,
		"the site finished (progress %.2f, wood %d/%d)"
			% [site.build_progress, site.wood_delivered, Hut.WOOD_COST])
	_free_world(w)


## Symptom 2: an 8x8 camp whose workers stand in the entrance area must still
## advance — with a stable anchor the wood lands where it gets absorbed.
func test_large_camp_absorbs_wood_at_its_stable_anchor() -> void:
	var w: Dictionary = _make_world()
	var camp: Building = w.commands.place_building(
		w.tribe, FIREWARRIOR_CAMP_SCENE, Vector2i(50, 50))
	check(camp != null, "the 8x8 camp was placeable")
	var anchor: Vector3 = camp.delivery_point()
	w.wood_pile_manager.deposit(anchor, Balance.FIREWARRIOR_CAMP_WOOD_COST)
	# Grade a few cells: this bumps change_version repeatedly, which used to be
	# what moved the anchor away from the wood.
	for i in range(6):
		var c: Vector2i = camp.claim_flatten_cell(anchor)
		if c.x < 0:
			break
		while camp.flatten_cell_pending(c):
			camp.work_flatten(c, 1.0)
	check(camp.delivery_point() == anchor, "grading did not move the anchor")
	_run_for(w, 3.0)
	check(camp.wood_delivered >= Balance.FIREWARRIOR_CAMP_WOOD_COST,
		"the wood was absorbed (%d of %d)"
			% [camp.wood_delivered, Balance.FIREWARRIOR_CAMP_WOOD_COST])
	_free_world(w)


# --- F3: the entrance flatten cell must never be a blocker ---------------------------

## Inside a FOREIGN footprint the entrance cell can never be graded. Taking it
## into the duty list kept _flatten_remaining non-empty forever, so
## foundation_done stayed false and add_build_progress was gated for good.
func test_entrance_flatten_cell_is_skipped_inside_a_foreign_footprint() -> void:
	var w: Dictionary = _make_world()
	# The entrance cell of a 4x4 at (60,60) is (62,64), so the neighbour has to
	# start at z = 64 to cover it.
	var first: Hut = w.building_manager.place(
		HUT_SCENE, w.tribe, Vector2i(60, 64), 0, true) as Hut
	check(first != null, "the neighbour stands")
	var site: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	check(site != null, "the site was placeable")
	var entrance: Vector2i = site.entrance_cell()
	check(w.nav.is_cell_blocked_by_building(entrance),
		"the neighbour really covers the site's entrance cell")
	check(not site.flatten_cell_pending(entrance),
		"the unusable entrance cell is not part of the grading duty")
	# Grading only the footprint cells is enough to finish the foundation.
	for z in range(site.cell.y, site.cell.y + site.footprint.y):
		for x in range(site.cell.x, site.cell.x + site.footprint.x):
			var c: Vector2i = Vector2i(x, z)
			while site.flatten_cell_pending(c):
				site.work_flatten(c, 1.0)
	check(site.foundation_done, "the foundation completes without the entrance cell")
	_free_world(w)


## A cell no worker can grade drops out after FLATTEN_CELL_TIMEOUT — one
## unreachable cell must not kill an otherwise fine site.
func test_unreachable_flatten_cell_is_dropped_after_the_timeout() -> void:
	var w: Dictionary = _make_world()
	var site: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	# A registered worker (the stall clock only runs with one) that is parked far
	# outside BuildingManager.RECRUIT_RADIUS, so nothing orders it to grade — this
	# stands in for the worker that cannot REACH the stuck cell.
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(20, 20))) as Brave
	check(site.join(brave), "a worker is on the site (the stall clock needs one)")
	# Everything graded except one cell that nobody ever works.
	var stuck: Vector2i = site.cell + Vector2i(1, 1)
	for z in range(site.cell.y, site.cell.y + site.footprint.y):
		for x in range(site.cell.x, site.cell.x + site.footprint.x):
			var c: Vector2i = Vector2i(x, z)
			if c == stuck:
				continue
			while site.flatten_cell_pending(c):
				site.work_flatten(c, 1.0)
	check(site.flatten_cell_pending(stuck), "the untouched cell is still pending")
	check(not site.foundation_done, "so the foundation is not done yet")

	_run_for(w, Balance.FLATTEN_CELL_TIMEOUT - 5.0)
	check(site.flatten_cell_pending(stuck), "it survives until the timeout")
	_run_for(w, 8.0)
	check(not site.flatten_cell_pending(stuck), "past the timeout it is dropped")
	check(site.foundation_done, "the foundation is complete and building can start")
	_free_world(w)


## The clock only runs while somebody is actually trying: an unattended plot must
## not erode its grading duty and rise out of untouched terrain.
func test_unattended_site_keeps_its_flatten_duty() -> void:
	var w: Dictionary = _make_world()
	var site: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	var cell: Vector2i = site.cell + Vector2i(1, 1)
	check(site.flatten_cell_pending(cell), "the cell starts out pending")
	_run_for(w, Balance.FLATTEN_CELL_TIMEOUT * 2.0)
	check(site.flatten_cell_pending(cell),
		"without workers the duty stands (no silent self-levelling)")
	_free_world(w)


# --- F4: no plot without an approach spot -------------------------------------------

## The root cause of symptom 1: a plot nobody can ever serve is refused up front
## instead of becoming a dead site with an ever-growing wood pile.
func test_can_place_at_rejects_a_plot_without_any_approach_cell() -> void:
	var w: Dictionary = _make_world()
	var fp: Vector2i = Vector2i(2, 2)
	var origin: Vector2i = Vector2i(60, 60)
	check(w.commands.can_place_at(origin, fp), "the open plot is fine to begin with")
	# Wall the plot in out to beyond the approach search rings.
	var pad: int = Building.APPROACH_SEARCH_RINGS + 1
	w.nav.fill_solid_region(Rect2i(origin - Vector2i(pad, pad),
		fp + Vector2i(pad * 2, pad * 2)), true)
	w.nav.fill_solid_region(Rect2i(origin, fp), false)   # the plot itself stays free
	check(not w.commands.can_place_at(origin, fp),
		"a plot without any reachable approach cell is refused")
	check(w.commands.place_building(w.tribe, HUT_SCENE, origin) == null,
		"and no building can be placed there")
	_free_world(w)


## F4 must not overshoot: tight but workable placements stay legal — the AI's
## plot search and every dense village depend on it.
func test_can_place_at_still_allows_tight_but_workable_placement() -> void:
	var w: Dictionary = _make_world()
	var first: Hut = w.building_manager.place(
		HUT_SCENE, w.tribe, Vector2i(60, 65), 0, true) as Hut
	check(first != null, "the neighbour stands")
	# Directly against the neighbour, entrance cell covered by it — but the
	# perimeter is wide open, so workers can serve it.
	var site: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	check(site != null, "a hut right next to a hut is still placeable")
	check(site.approach_island() >= 0, "and it has a reachable approach spot")
	_free_world(w)


# --- F5: trapped workers get out ----------------------------------------------------

## A brave that gave up its job while standing on unwalkable ground is snapped
## back out — the safety net for the reported workers stuck in the entrance area.
func test_trapped_worker_is_snapped_back_onto_walkable_ground() -> void:
	var w: Dictionary = _make_world()
	var site: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	# Standing INSIDE the (solid) footprint, exactly where graders stand.
	var inside: Vector2i = site.cell + Vector2i(1, 1)
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, w.nav.cell_to_world(inside)) as Brave
	check(not w.nav.is_cell_walkable(inside), "the cell it stands on is solid")
	brave.order_build(site)
	# Six seek failures in a row: the job is dropped and the escape kicks in.
	for i in range(Brave.SEEK_FAIL_QUIT_STREAK):
		brave._on_seek_failed()
	var cell_now: Vector2i = w.nav.world_to_cell(brave.position)
	check(w.nav.is_cell_walkable(cell_now),
		"the brave ends up on walkable ground (%s)" % cell_now)
	check(brave.state != Unit.State.BUILD, "and it is no longer on the job")
	_free_world(w)


## The escape must not touch a worker that stands on legal ground.
func test_worker_on_walkable_ground_is_not_moved() -> void:
	var w: Dictionary = _make_world()
	var site: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, site.delivery_point()) as Brave
	var before: Vector3 = brave.position
	brave.order_build(site)
	for i in range(Brave.SEEK_FAIL_QUIT_STREAK):
		brave._on_seek_failed()
	check(brave.position.distance_to(before) < 0.001,
		"a brave on walkable ground keeps its position")
	_free_world(w)


# --- F7: a site that never starts gives up ------------------------------------------

## Partial bookings reset the signature timer, so a site could stay alive forever
## without ever rising. The absolute no-start limit ends that.
func test_site_that_never_starts_decays_despite_partial_bookings() -> void:
	var w: Dictionary = _make_world()
	var site: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	# One wood every 20 s: the signature keeps changing, build_progress stays 0
	# (the foundation is never graded, so add_build_progress is gated).
	var elapsed: float = 0.0
	var drip: float = 0.0
	while elapsed < Balance.CONSTRUCTION_NO_START_TIMEOUT + 10.0 and site.health > 0:
		drip += TICK
		if drip >= 20.0:
			drip = 0.0
			w.wood_pile_manager.deposit(site.delivery_point(), 1)
		w.building_manager.tick(TICK)
		elapsed += TICK
	check(site.health <= 0, "the site that never started decayed")
	check(elapsed >= Balance.CONSTRUCTION_NO_START_TIMEOUT,
		"it survived until the no-start limit, not longer")
	check(elapsed < Balance.CONSTRUCTION_NO_START_TIMEOUT + 5.0,
		"and it did not outlive it (%.0f s)" % elapsed)
	_free_world(w)


## A site that IS rising must never hit the no-start limit.
func test_building_site_is_not_hit_by_the_no_start_limit() -> void:
	var w: Dictionary = _make_world()
	var site: Hut = w.commands.place_building(w.tribe, HUT_SCENE, Vector2i(60, 60)) as Hut
	w.wood_pile_manager.deposit(site.delivery_point(), Hut.WOOD_COST)
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, site.delivery_point()) as Brave
	brave.order_build(site)
	_run_for(w, Balance.CONSTRUCTION_NO_START_TIMEOUT + 20.0)
	check(site.health > 0, "a site with a working crew survives")
	check(not site.under_construction, "it finished instead")
	_free_world(w)
