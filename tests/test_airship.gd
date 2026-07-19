extends TestBase

## Headless tests for the airship (Luftschiff) and its wharf: production
## (20-wood building, 8 wood / 80 worker-seconds, own per-tribe cap), boarding
## rules (everyone incl. the shaman, 1.5 m to the shadow, empty-ship capture),
## straight flight over water at hover height, deck combat only while
## standing (+3 reach, firewarrior-only vs buildings), the shaman's deck
## cast, the anti-air rules (lightning/tornado instant, 2 fireball bolts,
## catapult air intercept without lava), airborne target rules and the
## explosion (30 damage + 12 m fall; water = drowning), unload and drift.

const TICK: float = 0.1
const MAX_TICKS: int = 3000

const WHARF_SCENE: PackedScene = preload("res://scenes/buildings/airship_wharf.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const REINC_SCENE: PackedScene = preload("res://scenes/buildings/reincarnation_site.tscn")
const AIRSHIP_SCENE: PackedScene = preload("res://scenes/units/airship.tscn")
const SIEGE_SCENE: PackedScene = preload("res://scenes/units/siege_engine.tscn")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")
const PREACHER_SCENE: PackedScene = preload("res://scenes/units/preacher.tscn")
const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


func _make_world(td: TerrainData = null) -> Dictionary:
	if td == null:
		td = _flat_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var tribe0: Tribe = Tribe.new(0)
	var tribe1: Tribe = Tribe.new(1)
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe0, tribe1] as Array[Tribe], tm, wpm)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um, wpm)
	um.building_manager = bm
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(nav, bm, um, tm)
	var ctx: SpellContext = SpellContext.new()
	ctx.terrain_data = td
	ctx.nav_grid = nav
	ctx.unit_manager = um
	ctx.building_manager = bm
	ctx.tree_manager = tm
	ctx.wood_pile_manager = wpm
	return {
		"td": td, "nav": nav, "tribe": tribe0, "tribe1": tribe1,
		"unit_manager": um, "building_manager": bm,
		"tree_manager": tm, "wood_pile_manager": wpm, "commands": tc, "ctx": ctx,
	}


func _free_world(w: Dictionary) -> void:
	# w.ctx is RefCounted and frees itself.
	w.commands.free()
	w.tree_manager.free()
	w.wood_pile_manager.free()
	w.building_manager.free()
	w.unit_manager.free()


func _tick_world(w: Dictionary) -> void:
	w.building_manager.tick(TICK)
	for u in w.unit_manager.units.duplicate():
		if is_instance_valid(u):
			u.tick(TICK)
	w.unit_manager.tick(TICK)


func _spawn_ship(w: Dictionary, tribe_id: int, pos: Vector3) -> Airship:
	var ship: Airship = w.unit_manager.spawn_unit(AIRSHIP_SCENE, tribe_id, pos) as Airship
	_tick_world(w)   # first tick snaps the hull to hover height
	return ship


## Spawns a unit next to the ship's shadow and boards it (ticks until aboard).
func _board(w: Dictionary, ship: Airship, scene: PackedScene, tribe_id: int = 0) -> Unit:
	var u: Unit = w.unit_manager.spawn_unit(
		scene, tribe_id, Vector3(ship.position.x + 1.0, 0.0, ship.position.z))
	u.order_crew(ship)
	var ticks: int = 0
	while not u.siege_boarded and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	return u


func _house_worker(w: Dictionary, ws: Workshop) -> Brave:
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, ws.entrance_world() + Vector3(1.0, 0.0, 1.0)) as Brave
	brave.order_workshop(ws)
	var ticks: int = 0
	while not brave.workshop_inside and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	return brave


# --- Wharf -----------------------------------------------------------------------------

func test_wharf_produces_an_airship() -> void:
	var w: Dictionary = _make_world()
	var ws: AirshipWharf = w.building_manager.place(
		WHARF_SCENE, w.tribe, Vector2i(60, 60), 0, true) as AirshipWharf
	check(ws != null, "airship wharf placed")
	check(ws.wood_cost == 20, "wharf costs 20 wood")
	check(ws.footprint == Vector2i(8, 8), "8x8 footprint")
	check(ws.worker_slots() == 4, "4 worker slots")
	check(ws.display_name() == "Luftschiffwerft", "display name")
	_house_worker(w, ws)
	_house_worker(w, ws)
	w.wood_pile_manager.deposit(ws.delivery_point(), AirshipWharf.AIRSHIP_WOOD)
	var stock_before: int = ws.stock_wood()
	var ticks: int = 0
	while w.tribe.owned_airship_count() == 0 and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(w.tribe.owned_airship_count() == 1, "one airship rolled out")
	check(stock_before - ws.stock_wood() == AirshipWharf.AIRSHIP_WOOD,
		"production consumed exactly %d wood" % AirshipWharf.AIRSHIP_WOOD)
	# Cap: with the fresh ship counted, cap 1 blocks the next production.
	w.tribe.max_airships = 1
	check(not ws.can_start_production(), "airship cap blocks the wharf")
	_free_world(w)


# --- Boarding & ownership ----------------------------------------------------------------

func test_everyone_boards_including_the_shaman() -> void:
	var w: Dictionary = _make_world()
	var ship: Airship = _spawn_ship(w, 0, w.nav.cell_to_world(Vector2i(60, 60)))
	check(ship.position.y >= 5.0 + Airship.FLY_HEIGHT - 0.1, "hovers at 12 m")
	var shaman: Unit = _board(w, ship, SHAMAN_SCENE)
	check(shaman.siege_boarded, "the SHAMAN may board an airship")
	check(shaman.position.y > 5.0 + Airship.FLY_HEIGHT * 0.8,
		"the passenger rides at deck height")
	# The same shaman is still refused by a ground vehicle.
	var engine: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, w.nav.cell_to_world(Vector2i(64, 60))) as SiegeEngine
	shaman.order_crew(engine)
	check(shaman.siege_engine != engine, "a catapult still refuses the shaman")
	_free_world(w)


func test_empty_ship_is_captured_manned_ship_is_not() -> void:
	var w: Dictionary = _make_world()
	var ship: Airship = _spawn_ship(w, 0, w.nav.cell_to_world(Vector2i(60, 60)))
	var raider: Unit = _board(w, ship, BRAVE_SCENE, 1)
	check(ship.tribe_id == 1, "boarding an EMPTY enemy airship takes it over")
	check(raider.siege_boarded, "the raider serves the captured ship")
	# A foreign unit can no longer join the now-manned ship.
	var late: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, Vector3(ship.position.x + 1.0, 0.0, ship.position.z))
	late.order_crew(ship)
	for i in range(30):
		_tick_world(w)
	check(late.siege_engine != ship or not late.siege_boarded,
		"a manned enemy airship cannot be hijacked")
	_free_world(w)


# --- Flight over water -------------------------------------------------------------------

func test_flies_straight_across_water() -> void:
	# A water channel (below SEA_LEVEL) splits the map: ground units cannot
	# cross, the airship flies straight over it at sea hover height.
	var td: TerrainData = _flat_terrain()
	for z in range(td.size):
		for x in range(60, 68):
			td.set_vertex_height(x, z, 0.0)
	var w: Dictionary = _make_world(td)
	check(w.nav.find_path(w.nav.cell_to_world(Vector2i(50, 60)),
		w.nav.cell_to_world(Vector2i(80, 60))).is_empty(),
		"ground path across the channel is impossible")
	var ship: Airship = _spawn_ship(w, 0, w.nav.cell_to_world(Vector2i(50, 60)))
	_board(w, ship, BRAVE_SCENE)
	ship.order_move(w.nav.cell_to_world(Vector2i(80, 60)))
	check(ship.state == Unit.State.MOVE, "the flight order was accepted")
	var over_water_checked: bool = false
	var ticks: int = 0
	while ship.state == Unit.State.MOVE and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
		if not over_water_checked and ship.position.x > 61.0 and ship.position.x < 66.0:
			over_water_checked = true
			check(absf(ship.position.y - (TerrainData.SEA_LEVEL + Airship.FLY_HEIGHT)) < 0.5,
				"over water it hovers at sea level + 12 m")
	check(over_water_checked, "the flight actually crossed the water channel")
	check(ship.position.x > 75.0, "the airship reached the far side")
	_free_world(w)


# --- Deck combat ---------------------------------------------------------------------------

func test_deck_firewarrior_fires_with_bonus_reach_only_standing() -> void:
	var w: Dictionary = _make_world()
	var ship: Airship = _spawn_ship(w, 0, w.nav.cell_to_world(Vector2i(60, 60)))
	var fw: Unit = _board(w, ship, FIREWARRIOR_SCENE)
	check(fw.siege_boarded, "firewarrior aboard")
	# Enemy at 10 m: beyond the ground fire range (8) but inside 8 + 3.
	var victim: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, ship.position + Vector3(10.0, -ship.position.y + 5.0, 0.0))
	victim.position.y = 5.0
	var ticks: int = 0
	while victim.health == victim.max_health and victim.state != Unit.State.DEAD \
			and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(victim.health < victim.max_health or victim.state == Unit.State.DEAD,
		"the deck firewarrior hits a target at 10 m (8 + 3 reach)")
	_free_world(w)


func test_warrior_only_ship_never_attacks() -> void:
	var w: Dictionary = _make_world()
	var ship: Airship = _spawn_ship(w, 0, w.nav.cell_to_world(Vector2i(60, 60)))
	_board(w, ship, WARRIOR_SCENE)
	var bystander: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, w.nav.cell_to_world(Vector2i(63, 60)))
	ship.order_attack(bystander)
	for i in range(60):
		_tick_world(w)
	check(bystander.health == bystander.max_health,
		"a warrior-only airship never has anything to attack")
	# Building order with a warrior-only crew: nothing happens either.
	var hut: Building = w.building_manager.place(HUT_SCENE, w.tribe1,
		Vector2i(64, 64), 0, true)
	ship.order_attack_building(hut)
	for i in range(60):
		_tick_world(w)
	check(hut.destruction_stage() == 0 and hut.health == hut.max_health,
		"buildings can only be harmed by firewarrior passengers")
	_free_world(w)


func test_deck_preacher_converts_with_bonus_reach() -> void:
	var w: Dictionary = _make_world()
	var ship: Airship = _spawn_ship(w, 0, w.nav.cell_to_world(Vector2i(60, 60)))
	_board(w, ship, PREACHER_SCENE)
	var victim: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, w.nav.cell_to_world(Vector2i(67, 60)))
	var ticks: int = 0
	while victim.tribe_id != 0 and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(victim.tribe_id == 0, "the deck preacher converts a target at 7 m (5 + 3)")
	_free_world(w)


func test_shaman_casts_from_deck_only_standing() -> void:
	var w: Dictionary = _make_world()
	var ship: Airship = _spawn_ship(w, 0, w.nav.cell_to_world(Vector2i(60, 60)))
	var shaman: Shaman = _board(w, ship, SHAMAN_SCENE) as Shaman
	var spell: FireballSpell = FireballSpell.new()
	spell.charges = 4   # cast() consumes stored charges
	var in_reach: Vector3 = ship.position + Vector3(spell.cast_range + 2.0, 0.0, 0.0)
	in_reach.y = 5.0
	check(shaman.order_cast(spell, in_reach, w.ctx),
		"deck cast succeeds within cast_range + 3")
	var too_far: Vector3 = ship.position + Vector3(spell.cast_range + 5.0, 0.0, 0.0)
	too_far.y = 5.0
	check(not shaman.order_cast(spell, too_far, w.ctx),
		"beyond cast_range + 3 the deck cast fails silently")
	_board(w, ship, BRAVE_SCENE)   # a pilot so the ship can move
	ship.order_move(w.nav.cell_to_world(Vector2i(90, 60)))
	check(ship.state == Unit.State.MOVE, "ship under way")
	check(not shaman.order_cast(spell, in_reach, w.ctx),
		"no casting while the airship is moving")
	_free_world(w)


# --- Anti-air -------------------------------------------------------------------------------

func test_lightning_kills_the_airship_instantly() -> void:
	var w: Dictionary = _make_world()
	var ship: Airship = _spawn_ship(w, 1, w.nav.cell_to_world(Vector2i(60, 60)))
	var passenger: Unit = _board(w, ship, BRAVE_SCENE, 1)
	var spell: LightningSpell = LightningSpell.new()
	check(spell.execute(w.tribe, Vector3(ship.position.x, 5.0, ship.position.z), w.ctx),
		"lightning aimed at the shadow strikes")
	check(ship.state == Unit.State.DEAD, "the bolt kills the airship instantly")
	check(passenger.state == Unit.State.THROWN or passenger.state == Unit.State.DEAD
			or passenger.state == Unit.State.ROLL,
		"the passenger is hurled off the exploding ship")
	_free_world(w)


func test_two_fireball_bolts_bring_it_down() -> void:
	var w: Dictionary = _make_world()
	var ship: Airship = _spawn_ship(w, 1, w.nav.cell_to_world(Vector2i(60, 60)))
	ship.register_hull_hit(ship.position)
	check(ship.state != Unit.State.DEAD, "one hull hit: damaged but flying")
	# A real fireball bolt exploding at the shadow registers the second hit.
	var bolt: FireballBolt = FireballBolt.new()
	bolt.setup(0, Vector3(ship.position.x - 8.0, 5.0, ship.position.z),
		Vector3(ship.position.x, 5.0, ship.position.z), null, w.unit_manager, w.td)
	w.unit_manager.register_projectile(bolt)
	var ticks: int = 0
	while not bolt.done and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(ship.state == Unit.State.DEAD, "the second (bolt) hit destroys the ship")
	_free_world(w)


func test_tornado_contact_is_instant_death() -> void:
	var w: Dictionary = _make_world()
	var ship: Airship = _spawn_ship(w, 1, w.nav.cell_to_world(Vector2i(60, 60)))
	var vortex: TornadoVortex = TornadoVortex.new()
	vortex.setup(0, Vector3(ship.position.x, 5.0, ship.position.z),
		w.unit_manager, w.td, w.building_manager)
	w.unit_manager.register_projectile(vortex)
	for i in range(5):
		_tick_world(w)
	check(ship.state == Unit.State.DEAD, "tornado contact shreds the airship")
	_free_world(w)


func test_catapult_intercept_two_hits_no_lava() -> void:
	var w: Dictionary = _make_world()
	var engine: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, w.nav.cell_to_world(Vector2i(60, 60))) as SiegeEngine
	# Full-crew the catapult quickly (2 needed to fire).
	for i in range(2):
		var b: Brave = w.unit_manager.spawn_unit(BRAVE_SCENE, 0,
			engine.position + Vector3(1.0, 0.0, float(i))) as Brave
		b.order_crew(engine)
	var ticks: int = 0
	while engine.boarded_count() < 2 and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	var ship: Airship = _spawn_ship(w, 1, w.nav.cell_to_world(Vector2i(68, 60)))
	engine.order_attack(ship)
	var projectiles_seen: int = 0
	ticks = 0
	while ship.state != Unit.State.DEAD and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
		for p in w.unit_manager.projectiles:
			if p is SiegeShot:
				projectiles_seen = maxi(projectiles_seen, 1)
			check(not (p is LavaSurge), "air shots never spawn lava")
	check(projectiles_seen == 1, "the catapult lobbed at the airship")
	check(ship.state == Unit.State.DEAD, "two air intercepts destroy the airship")
	_free_world(w)


# --- Airborne target rules -------------------------------------------------------------------

func test_airborne_rules_for_deck_crew() -> void:
	var w: Dictionary = _make_world()
	var ship: Airship = _spawn_ship(w, 1, w.nav.cell_to_world(Vector2i(60, 60)))
	var passenger: Unit = _board(w, ship, BRAVE_SCENE, 1)
	check(passenger.is_airborne(), "deck crew counts as airborne")
	# Melee can never engage it.
	var warrior: Unit = w.unit_manager.spawn_unit(
		WARRIOR_SCENE, 0, w.nav.cell_to_world(Vector2i(61, 60)))
	warrior._begin_attack(passenger)
	check(warrior.attack_target != passenger, "melee refuses an airborne target")
	# Preachers cannot convert it.
	check(not passenger.begin_conversion(null, 5.0),
		"airship passengers cannot be pacified")
	# Firewarrior fireballs deal DOUBLE damage against it.
	var fw: Unit = w.unit_manager.spawn_unit(
		FIREWARRIOR_SCENE, 0, w.nav.cell_to_world(Vector2i(64, 60)))
	w.commands.order_attack([fw] as Array[Unit], passenger)
	var ticks: int = 0
	while passenger.health == passenger.max_health \
			and passenger.state != Unit.State.DEAD and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(passenger.health <= passenger.max_health - 18,
		"a fireball hit deals double damage (18) against deck crew")
	_free_world(w)


func test_lava_never_reaches_the_deck() -> void:
	var w: Dictionary = _make_world()
	var ship: Airship = _spawn_ship(w, 0, w.nav.cell_to_world(Vector2i(60, 60)))
	var passenger: Unit = _board(w, ship, BRAVE_SCENE)
	var surge: LavaSurge = LavaSurge.new()
	surge.setup(Vector3(ship.position.x, 5.0, ship.position.z),
		w.unit_manager, w.td, 3.0, w.building_manager)
	w.unit_manager.register_projectile(surge)
	for i in range(20):
		_tick_world(w)
	check(not passenger.is_burning(), "lava under the ship ignites nobody aboard")
	check(not ship.is_burning(), "the hull cannot be ignited either")
	_free_world(w)


# --- Explosion, unload, drift ------------------------------------------------------------------

func test_explosion_hurls_passengers_down() -> void:
	var w: Dictionary = _make_world()
	var ship: Airship = _spawn_ship(w, 0, w.nav.cell_to_world(Vector2i(60, 60)))
	var brave: Unit = _board(w, ship, BRAVE_SCENE)
	var warrior: Unit = _board(w, ship, WARRIOR_SCENE)
	ship.explode()
	check(ship.state == Unit.State.DEAD, "the ship is gone")
	# 30 explosion damage + 30 fall damage = a full brave life.
	var ticks: int = 0
	while warrior.state == Unit.State.THROWN or warrior.state == Unit.State.ROLL:
		_tick_world(w)
		ticks += 1
		if ticks >= MAX_TICKS:
			break
	check(brave.state == Unit.State.DEAD,
		"a brave (60 HP) dies to explosion + 12 m fall")
	check(warrior.state != Unit.State.DEAD, "a warrior (120 HP) survives hurt")
	check(warrior.health <= warrior.max_health - 60,
		"the warrior took explosion AND fall damage")
	_free_world(w)


func test_crash_over_water_drowns_the_crew() -> void:
	var td: TerrainData = _flat_terrain()
	for z in range(td.size):
		for x in range(60, 70):
			td.set_vertex_height(x, z, 0.0)
	var w: Dictionary = _make_world(td)
	var ship: Airship = _spawn_ship(w, 0, w.nav.cell_to_world(Vector2i(50, 60)))
	var brave: Unit = _board(w, ship, BRAVE_SCENE)
	# Fly out over the water, then blow it up mid-channel.
	ship.order_move(w.nav.cell_to_world(Vector2i(80, 60)))
	var ticks: int = 0
	while ship.position.x < 64.0 and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	ship.explode()
	ticks = 0
	while brave.state != Unit.State.DEAD and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(brave.state == Unit.State.DEAD, "falling into water drowns the passenger")
	_free_world(w)


func test_unload_drops_all_passengers_at_the_target() -> void:
	var w: Dictionary = _make_world()
	var ship: Airship = _spawn_ship(w, 0, w.nav.cell_to_world(Vector2i(60, 60)))
	var a: Unit = _board(w, ship, BRAVE_SCENE)
	var b: Unit = _board(w, ship, WARRIOR_SCENE)
	var dest: Vector3 = w.nav.cell_to_world(Vector2i(80, 60))
	ship.order_unload(dest)
	var ticks: int = 0
	while (a.siege_boarded or b.siege_boarded) and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(not a.siege_boarded and not b.siege_boarded, "both passengers were dropped")
	ticks = 0
	while (a.state == Unit.State.THROWN or b.state == Unit.State.THROWN) \
			and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(a.state != Unit.State.DEAD and b.state != Unit.State.DEAD,
		"a controlled drop is harmless")
	check(a._flat_dist(a.position, dest) < 8.0, "dropped near the unload target")
	check(w.nav.is_cell_walkable(w.nav.world_to_cell(a.position)),
		"passengers land on walkable ground")
	_free_world(w)


func test_empty_ship_drifts_toward_the_start_island() -> void:
	var td: TerrainData = _flat_terrain()
	for z in range(td.size):
		for x in range(40, 128):
			td.set_vertex_height(x, z, 0.0)
	var w: Dictionary = _make_world(td)
	w.building_manager.place(REINC_SCENE, w.tribe, Vector2i(20, 60), 0, true)
	# Empty ship stranded far out over the water.
	var ship: Airship = _spawn_ship(w, 0, w.nav.cell_to_world(Vector2i(80, 60)))
	var start_x: float = ship.position.x
	for i in range(300):
		_tick_world(w)
	check(ship.position.x < start_x - 5.0,
		"the empty airship drifts back toward the start-base island")
	_free_world(w)
