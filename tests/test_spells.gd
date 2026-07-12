extends TestBase

## Headless tests for phase 6: the spell framework (charge system, round-robin
## mana conversion, cast flow via the shaman) and the shaman kill bonus.
## Spell-effect tests (landbridge, fireball, ...) are added per spell.

const TICK: float = 0.1
const MAX_TICKS: int = 400

const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const BRAVE_SCENE_T: PackedScene = preload("res://scenes/units/brave.tscn")


## Controllable spell for framework tests.
class DummySpell extends Spell:
	var executed: int = 0
	var succeed: bool = true

	func _init(p_id: StringName, cost: float, p_max: int) -> void:
		id = p_id
		charge_cost = cost
		max_charges = p_max

	func execute(_tribe: Tribe, _target: Vector3, _ctx: SpellContext) -> bool:
		if not succeed:
			return false
		executed += 1
		return true


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
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(nav, null, um)
	var ctx: SpellContext = SpellContext.new()
	ctx.terrain_data = td
	ctx.nav_grid = nav
	ctx.unit_manager = um
	tc.spell_context = ctx
	return {"td": td, "nav": nav, "tribe0": tribe0, "tribe1": tribe1,
		"unit_manager": um, "tc": tc, "ctx": ctx}


func _free_world(w: Dictionary) -> void:
	w.tc.free()
	w.unit_manager.free()


func _run(w: Dictionary, units: Array, done: Callable) -> int:
	for i in range(MAX_TICKS):
		if done.call():
			return i
		for u in units:
			if is_instance_valid(u) and u.state != Unit.State.DEAD:
				u.tick(TICK)
		w.unit_manager.tick(TICK)
	return MAX_TICKS


# --- Lava burns trees ----------------------------------------------------------

## The volcano's lava surge sets trees alight (was only igniting units before).
func test_lava_surge_ignites_trees() -> void:
	var td: TerrainData = _flat_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var tribe0: Tribe = Tribe.new(0)
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe0] as Array[Tribe], tm)
	var tree: TreeResource = tm.spawn_tree(Vector2i(64, 64), TreeResource.MAX_STAGE)
	check(tree != null and not tree.is_burning(), "tree starts unburnt")
	var surge: LavaSurge = LavaSurge.new()
	surge.setup(tree.position, um, td, 5.0)
	for i in range(10):
		surge.tick(0.1)
	check(tree.is_burning(), "the volcano lava surge sets nearby trees alight")
	surge.free()
	tm.free()
	um.free()


# --- Charge system -------------------------------------------------------------

func test_no_charge_without_enough_mana() -> void:
	var tribe: Tribe = Tribe.new(0)
	var spell: DummySpell = DummySpell.new(&"dummy", 10.0, 4)
	tribe.set_spells([spell] as Array[Spell])
	tribe.mana = 5.0
	tribe.tick(0.0)
	check(spell.charges == 0, "not enough mana -> no charge")
	check_near(tribe.mana, 5.0, "mana untouched below the charge cost")
	check_near(spell.charge_progress, 0.5, "partial fill shown on the pip")
	check(not spell.cast(tribe, Vector3.ZERO, null), "cast without charge fails")
	check(spell.executed == 0, "failed cast has no side effect")


func test_charging_over_ticks_until_full() -> void:
	var tribe: Tribe = Tribe.new(0)
	var spell: DummySpell = DummySpell.new(&"dummy", 10.0, 2)
	tribe.set_spells([spell] as Array[Spell])
	tribe.mana = 25.0
	tribe.tick(0.0)
	check(spell.charges == 2, "mana converts into charges up to max_charges")
	check_near(tribe.mana, 5.0, "each conversion costs charge_cost")
	tribe.mana += 20.0
	tribe.tick(0.0)
	check(spell.charges == 2, "full spell takes no more charges")
	check_near(tribe.mana, 25.0, "surplus mana accumulates unused")


func test_round_robin_serves_spells_fairly() -> void:
	var tribe: Tribe = Tribe.new(0)
	var cheap: DummySpell = DummySpell.new(&"cheap", 10.0, 4)
	var pricey: DummySpell = DummySpell.new(&"pricey", 20.0, 4)
	# Install in reverse order: set_spells sorts cheapest first.
	tribe.set_spells([pricey, cheap] as Array[Spell])
	tribe.mana = 30.0
	tribe.tick(0.0)
	check(cheap.charges == 1 and pricey.charges == 1,
		"one round serves both spells, cheapest first")
	check_near(tribe.mana, 0.0, "all mana converted")
	# Next round starts at the cheapest again...
	tribe.mana = 10.0
	tribe.tick(0.0)
	check(cheap.charges == 2 and pricey.charges == 1,
		"next round serves the cheap spell first")
	# ...but the expensive spell is NOT starved: the pointer now waits on it
	# until its cost has accumulated, instead of feeding the cheap one again.
	tribe.mana += 10.0
	tribe.tick(0.0)
	check(cheap.charges == 2 and pricey.charges == 1,
		"pointer waits on the expensive spell while mana is short")
	tribe.mana += 10.0
	tribe.tick(0.0)
	check(pricey.charges == 2, "expensive spell gets its turn once affordable")


func test_cast_consumes_exactly_one_charge() -> void:
	var tribe: Tribe = Tribe.new(0)
	var spell: DummySpell = DummySpell.new(&"dummy", 10.0, 4)
	tribe.set_spells([spell] as Array[Spell])
	spell.charges = 2
	tribe.mana = 7.0
	check(spell.cast(tribe, Vector3.ZERO, null), "cast with stored charge succeeds")
	check(spell.charges == 1, "exactly one charge consumed")
	check_near(tribe.mana, 7.0, "mana unchanged by the cast")
	check(spell.executed == 1, "effect executed once")


func test_failed_execute_keeps_charge() -> void:
	var tribe: Tribe = Tribe.new(0)
	var spell: DummySpell = DummySpell.new(&"dummy", 10.0, 4)
	tribe.set_spells([spell] as Array[Spell])
	spell.charges = 2
	spell.succeed = false
	check(not spell.cast(tribe, Vector3.ZERO, null), "failed effect -> cast false")
	check(spell.charges == 2, "charge kept when the effect fails")


# --- Cast flow via TribeCommands / shaman ------------------------------------------

func test_cast_spell_without_shaman_or_charge_fails() -> void:
	var w: Dictionary = _make_world()
	var spell: DummySpell = DummySpell.new(&"dummy", 10.0, 4)
	w.tribe0.set_spells([spell] as Array[Spell])
	check(not w.tc.cast_spell(w.tribe0, &"dummy", Vector3(30, 0, 30)),
		"no charge -> no cast order")
	spell.charges = 1
	check(not w.tc.cast_spell(w.tribe0, &"dummy", Vector3(30, 0, 30)),
		"no shaman -> no cast order")
	check(not w.tc.cast_spell(w.tribe0, &"missing", Vector3.ZERO),
		"unknown spell id -> false")
	_free_world(w)


func test_dead_shaman_blocks_casting() -> void:
	var w: Dictionary = _make_world()
	var shaman: Unit = w.unit_manager.spawn_unit(SHAMAN_SCENE, 0, Vector3(30, 0, 30))
	check(w.tribe0.shaman == shaman, "tribe.shaman set on spawn")
	var spell: DummySpell = DummySpell.new(&"dummy", 10.0, 4)
	w.tribe0.set_spells([spell] as Array[Spell])
	spell.charges = 1
	shaman.take_damage(9999)
	check(shaman.state == Unit.State.DEAD, "shaman died")
	check(w.tribe0.shaman == null, "tribe.shaman cleared on death")
	check(not w.tc.cast_spell(w.tribe0, &"dummy", Vector3(30, 0, 30)),
		"dead shaman -> no cast")
	check(spell.charges == 1, "charge kept")
	_free_world(w)


func test_shaman_walks_into_range_then_casts() -> void:
	var w: Dictionary = _make_world()
	var shaman: Unit = w.unit_manager.spawn_unit(SHAMAN_SCENE, 0, Vector3(20, 0, 20))
	var spell: DummySpell = DummySpell.new(&"dummy", 10.0, 4)
	w.tribe0.set_spells([spell] as Array[Spell])
	spell.charges = 2
	var target: Vector3 = Vector3(50, 0, 20)   # far beyond CAST_RANGE
	check(w.tc.cast_spell(w.tribe0, &"dummy", target), "cast order accepted")
	check(shaman.state == Unit.State.CAST, "shaman enters CAST")
	var ticks: int = _run(w, [shaman], func() -> bool: return spell.executed > 0)
	check(ticks < MAX_TICKS, "spell released after walking into range")
	check(shaman._flat_dist(shaman.position, target) <= spell.cast_range + 0.5,
		"shaman moved into the spell's cast range first")
	check(spell.charges == 1, "exactly one charge consumed on release")
	check(shaman.state == Unit.State.IDLE, "shaman idles after the cast")
	_free_world(w)


func test_move_order_cancels_pending_cast_and_keeps_charge() -> void:
	var w: Dictionary = _make_world()
	var shaman: Unit = w.unit_manager.spawn_unit(SHAMAN_SCENE, 0, Vector3(20, 0, 20))
	var spell: DummySpell = DummySpell.new(&"dummy", 10.0, 4)
	w.tribe0.set_spells([spell] as Array[Spell])
	spell.charges = 1
	check(w.tc.cast_spell(w.tribe0, &"dummy", Vector3(60, 0, 60)), "cast order accepted")
	shaman.order_move(Vector3(22, 0, 20))
	check(shaman.state != Unit.State.CAST, "move order cancels the cast")
	for i in range(30):
		shaman.tick(TICK)
	check(spell.executed == 0, "cancelled cast never fires")
	check(spell.charges == 1, "charge kept on cancel")
	_free_world(w)


# --- Shaman kill bonus ----------------------------------------------------------------

func test_shaman_kill_grants_charge_bonus() -> void:
	var w: Dictionary = _make_world()
	var shaman: Unit = w.unit_manager.spawn_unit(SHAMAN_SCENE, 0, Vector3(30, 0, 30))
	var killer: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 1, Vector3(31, 0, 30))
	# Killer tribe capacity: 20 * 10 = 200 -> bonus 15% = 30 -> 1 charge + 10 mana.
	var spell: DummySpell = DummySpell.new(&"dummy", 20.0, 10)
	w.tribe1.set_spells([spell] as Array[Spell])
	shaman.take_damage(9999, killer)
	check(shaman.state == Unit.State.DEAD, "shaman died")
	check(spell.charges == 1, "kill bonus converted into a stored charge")
	check_near(w.tribe1.mana, 10.0, "bonus remainder stays as mana")
	_free_world(w)


func test_shaman_death_without_attacker_grants_nothing() -> void:
	var w: Dictionary = _make_world()
	var shaman: Unit = w.unit_manager.spawn_unit(SHAMAN_SCENE, 0, Vector3(30, 0, 30))
	var spell: DummySpell = DummySpell.new(&"dummy", 20.0, 10)
	w.tribe1.set_spells([spell] as Array[Spell])
	shaman.take_damage(9999)
	check(spell.charges == 0, "no attacker -> no bonus")
	check_near(w.tribe1.mana, 0.0, "no bonus mana either")
	_free_world(w)


# --- Spell effects -------------------------------------------------------------------

func _make_world_with_buildings() -> Dictionary:
	var w: Dictionary = _make_world()
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(w.td, w.nav, w.unit_manager)
	w["bm"] = bm
	w.ctx.building_manager = bm
	return w


func _free_world_with_buildings(w: Dictionary) -> void:
	w.bm.free()
	_free_world(w)


func test_default_set_charge_counts() -> void:
	var spells: Array[Spell] = Spell.create_default_set()
	check(spells.size() == 10, "ten spells in the default set (phase 6 + 7c)")
	# 7c charge counts are binding: volcano 1, firestorm/earthquake 2,
	# flatten/sink 3 (see plans/07c_new_spells.md).
	var expected: Dictionary = {
		&"fireball": 4, &"lightning": 4, &"swarm": 4, &"landbridge": 4,
		&"tornado": 3, &"earthquake": 2, &"volcano": 1, &"firestorm": 2,
		&"flatten": 3, &"sink": 3}
	for spell in spells:
		check(expected.has(spell.id), "known spell id: %s" % spell.id)
		check(spell.max_charges == expected.get(spell.id, -1),
			"%s has %d max charges" % [spell.id, expected.get(spell.id, -1)])
		check(spell.charges == 0, "%s starts uncharged" % spell.id)


## Water channel (columns 60..66 below sea level) splitting two land halves.
func _channel_terrain(east_height: float = 5.0) -> TerrainData:
	var td: TerrainData = _flat_terrain()
	for vz in range(TerrainData.VERTS):
		for vx in range(TerrainData.VERTS):
			if vx >= 60 and vx <= 66:
				td.set_vertex_height(vx, vz, 0.0)
			elif vx > 66:
				td.set_vertex_height(vx, vz, east_height)
	return td


func test_landbridge_opens_water_crossing() -> void:
	var td: TerrainData = _channel_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var tribe: Tribe = Tribe.new(0)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe] as Array[Tribe])
	var shaman: Unit = um.spawn_unit(SHAMAN_SCENE, 0, Vector3(57, 0, 64))
	check(shaman != null, "shaman spawned")
	var ctx: SpellContext = SpellContext.new()
	ctx.terrain_data = td
	ctx.nav_grid = nav
	ctx.unit_manager = um
	check(not nav.is_cell_walkable(Vector2i(63, 64)), "channel starts unwalkable")
	check(nav.find_path(Vector3(56, 0, 64), Vector3(70, 0, 64)).is_empty(),
		"no path across the water before the cast")
	var spell: LandbridgeSpell = LandbridgeSpell.new()
	check(spell.execute(tribe, Vector3(68, 0, 64), ctx), "landbridge cast succeeds")
	# The lift is GRADUAL (morph over ~3 s): right after the cast the channel
	# is still water; halfway through, the terrain is visibly on its way up.
	check(not nav.is_cell_walkable(Vector2i(63, 64)),
		"channel not instantly walkable (gradual terraforming)")
	var start_h: float = td.get_height(63.0, 64.0)
	for i in range(15):
		um.tick(0.1)
	check(td.get_height(63.0, 64.0) > start_h + 0.2, "terrain rising mid-morph")
	for i in range(25):
		um.tick(0.1)
	check(nav.is_cell_walkable(Vector2i(63, 64)), "bridge cell walkable once the morph ends")
	check(td.get_height(63.0, 64.0) > TerrainData.SEA_LEVEL,
		"terrain raised above the water line")
	check(not nav.find_path(Vector3(56, 0, 64), Vector3(70, 0, 64)).is_empty(),
		"path leads across the new bridge")
	um.free()


func test_landbridge_builds_walkable_ramp() -> void:
	# East side sits 4 m higher: the corridor must become a walkable slope.
	var td: TerrainData = _channel_terrain(9.0)
	var nav: NavGrid = NavGrid.new(td)
	var tribe: Tribe = Tribe.new(0)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe] as Array[Tribe])
	um.spawn_unit(SHAMAN_SCENE, 0, Vector3(57, 0, 64))
	var ctx: SpellContext = SpellContext.new()
	ctx.terrain_data = td
	ctx.nav_grid = nav
	ctx.unit_manager = um
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	ctx.wood_pile_manager = wpm
	wpm.deposit(Vector3(65, 0, 64), 3)   # pile inside the future corridor
	var pile: WoodPile = wpm.piles[0]
	var spell: LandbridgeSpell = LandbridgeSpell.new()
	check(spell.execute(tribe, Vector3(69, 0, 64), ctx), "ramp cast succeeds")
	for i in range(35):
		um.tick(0.1)   # let the gradual morph finish
	check_near(pile.position.y, td.get_height(pile.position.x, pile.position.z),
		"wood pile rode up with the rising terrain", 0.3)
	wpm.free()
	for x in range(58, 69):
		check(nav.is_cell_walkable(Vector2i(x, 64)),
			"ramp cell (%d, 64) is walkable (slope below limit)" % x)
	check(not nav.find_path(Vector3(56, 0, 64), Vector3(70, 0, 64)).is_empty(),
		"path climbs the ramp onto the higher side")
	um.free()


func test_landbridge_grades_land_ridge_flat() -> void:
	# Pure land cast: a steep ridge blocks the way; the corridor is graded onto
	# the straight start->target line (bumps shaved, smooth surface).
	var td: TerrainData = _flat_terrain()
	for vz in range(60, 69):
		for vx in range(61, 65):
			td.set_vertex_height(vx, vz, 12.0)
	var nav: NavGrid = NavGrid.new(td)
	var tribe: Tribe = Tribe.new(0)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe] as Array[Tribe])
	um.spawn_unit(SHAMAN_SCENE, 0, Vector3(57, 0, 64))
	var ctx: SpellContext = SpellContext.new()
	ctx.terrain_data = td
	ctx.nav_grid = nav
	ctx.unit_manager = um
	check(not nav.is_cell_walkable(Vector2i(60, 64)), "ridge flank too steep before")
	var spell: LandbridgeSpell = LandbridgeSpell.new()
	check(spell.execute(tribe, Vector3(68, 0, 64), ctx), "land cast succeeds")
	for i in range(35):
		um.tick(0.1)
	for x in range(58, 68):
		check(nav.is_cell_walkable(Vector2i(x, 64)),
			"graded cell (%d, 64) is walkable" % x)
	check(td.get_height(63.0, 64.0) < 7.0, "ridge shaved down toward the straight line")
	um.free()


func test_fireball_damage_and_throw() -> void:
	var w: Dictionary = _make_world()
	w.unit_manager.spawn_unit(SHAMAN_SCENE, 0, Vector3(30, 0, 30))
	var target: Vector3 = Vector3(40, 0, 30)
	var direct: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1, target)
	var splash: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1, Vector3(41.5, 0, 30))
	var friend: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 0, Vector3(40.5, 0, 30.8))
	var spell: FireballSpell = FireballSpell.new()
	check(spell.execute(w.tribe0, target, w.ctx), "fireball launches")
	check(w.unit_manager.projectiles.size() == 1, "bolt registered as projectile")
	var bolt: FireballBolt = w.unit_manager.projectiles[0]
	var ticks: int = _run(w, [], func() -> bool: return bolt.done)
	check(ticks < MAX_TICKS, "bolt reaches the target point")
	check(direct.state == Unit.State.DEAD, "direct hit kills a brave (60 dmg)")
	check(splash.health == 30, "splash hit takes half a brave life")
	check(splash.state == Unit.State.THROWN, "survivor is thrown into the air")
	check(friend.health == 60 and friend.state != Unit.State.THROWN,
		"own units are unaffected")
	var start_pos: Vector3 = Vector3(41.5, 0, 30)
	ticks = _run(w, [splash], func() -> bool:
		return splash.state == Unit.State.IDLE or splash.state == Unit.State.DEAD)
	check(ticks < MAX_TICKS, "thrown unit lands, rolls out and stands up")
	if splash.state == Unit.State.IDLE:
		check(splash._flat_dist(splash.position, start_pos) > 0.8,
			"landed away from where it stood")
		check(w.nav.is_cell_walkable(w.nav.world_to_cell(splash.position)),
			"landing position is walkable")
	_free_world(w)


func test_lightning_kills_unit_and_rolls_neighbors() -> void:
	var w: Dictionary = _make_world_with_buildings()
	w.unit_manager.spawn_unit(SHAMAN_SCENE, 0, Vector3(30, 0, 30))
	var victim: Unit = w.unit_manager.spawn_unit(SHAMAN_SCENE, 1, Vector3(40, 0, 30))
	var neighbor: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1, Vector3(41, 0, 30))
	var own: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 0, Vector3(39, 0, 30))
	var spell: LightningSpell = LightningSpell.new()
	check(spell.execute(w.tribe0, Vector3(40.2, 0, 30), w.ctx), "lightning strikes")
	check(victim.state == Unit.State.DEAD, "240 damage kills even a full shaman")
	check(neighbor.state == Unit.State.ROLL, "adjacent enemy knocked into a roll")
	check(own.state != Unit.State.ROLL, "own unit next to the strike stays up")
	# No target at all -> the cast fails (charge would be kept).
	check(not spell.execute(w.tribe0, Vector3(90, 0, 90), w.ctx),
		"no target in range -> execute fails")
	_free_world_with_buildings(w)


func test_lightning_wrecks_building_two_stages() -> void:
	var w: Dictionary = _make_world_with_buildings()
	var tribe1: Tribe = w.tribe1
	var hut: Building = w.bm.place(preload("res://scenes/buildings/hut.tscn"),
		tribe1, Vector2i(50, 50), 0, true)
	var spell: LightningSpell = LightningSpell.new()
	check(spell.execute(w.tribe0, hut.center_world(), w.ctx), "strike on the hut")
	check(hut.destruction_stage() == 2, "lightning = +2 destruction stages")
	check(not hut.is_usable(), "hut unusable after the strike")
	_free_world_with_buildings(w)


func test_swarm_panics_enemies_not_shaman() -> void:
	var w: Dictionary = _make_world()
	var brave: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1, Vector3(41, 0, 30))
	var enemy_shaman: Unit = w.unit_manager.spawn_unit(SHAMAN_SCENE, 1, Vector3(41.5, 0, 30))
	var own: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 0, Vector3(40.5, 0, 30.5))
	var spell: SwarmSpell = SwarmSpell.new()
	check(spell.execute(w.tribe0, Vector3(40.5, 0, 30), w.ctx), "swarm spawned")
	var cloud: SwarmCloud = w.unit_manager.projectiles[0]
	var start_pos: Vector3 = brave.position
	var ticks: int = _run(w, [brave, enemy_shaman, own],
		func() -> bool: return brave.state == Unit.State.PANIC)
	check(ticks < MAX_TICKS, "enemy brave panics near the swarm")
	# Panicked units ignore orders and scramble around.
	brave.order_move(Vector3(60, 0, 60))
	check(brave.state == Unit.State.PANIC, "orders are ignored while panicking")
	_run(w, [brave, enemy_shaman, own], func() -> bool:
		return brave._flat_dist(brave.position, start_pos) > 1.0)
	check(brave._flat_dist(brave.position, start_pos) > 1.0, "panicked brave scrambles away")
	check(enemy_shaman.state != Unit.State.PANIC, "enemy shaman is panic-immune")
	check(own.state != Unit.State.PANIC, "own units are unaffected")
	# Light damage near the swarm (the immobile shaman keeps getting stung).
	_run(w, [brave, enemy_shaman, own],
		func() -> bool: return enemy_shaman.health < enemy_shaman.max_health)
	check(enemy_shaman.health < enemy_shaman.max_health, "swarm stings nearby enemies")
	# The cloud expires after its lifetime, the panic after its own duration.
	# Wait until the brave is ORDERABLE again — a downhill stumble mid-panic
	# briefly rolls it (state != PANIC, but orders are still refused; the
	# stumble no longer cancels the panic since phase 8.2).
	ticks = _run(w, [brave, enemy_shaman, own], func() -> bool:
		return cloud.done and brave.can_take_orders())
	check(ticks < MAX_TICKS, "cloud despawns and the panic wears off")
	check(brave.state != Unit.State.PANIC, "brave controllable again")
	brave.order_move(Vector3(60, 0, 60))
	check(brave.state == Unit.State.MOVE, "orders work again after the panic")
	_free_world(w)


func test_tornado_wrecks_building_stage_by_stage() -> void:
	var w: Dictionary = _make_world_with_buildings()
	var hut: Building = w.bm.place(preload("res://scenes/buildings/hut.tscn"),
		w.tribe1, Vector2i(50, 50), 0, true)
	var spell: TornadoSpell = TornadoSpell.new()
	check(spell.execute(w.tribe0, hut.center_world(), w.ctx), "tornado spawned")
	var vortex: TornadoVortex = w.unit_manager.projectiles[0]
	# Pin the vortex over the hut (its drift is random) to test the cadence.
	vortex._redirect = 999.0
	vortex._drift = Vector3.ZERO
	w.unit_manager.tick(0.1)   # first stage fires immediately
	check(hut.destruction_stage() == 1, "+1 stage on contact")
	w.unit_manager.tick(2.0)
	check(hut.destruction_stage() == 2, "+2 stages after ~2 s")
	w.unit_manager.tick(2.0)
	check(hut.destruction_stage() == 3, "+3 stages after ~4 s")
	w.unit_manager.tick(2.0)
	check(hut.health == 0, "fourth stage destroys the hut within the 8 s lifetime")
	check(w.nav.is_cell_walkable(Vector2i(51, 51)), "footprint free after the wreck")
	_free_world_with_buildings(w)


func test_tornado_lifts_carries_and_flings_units() -> void:
	var w: Dictionary = _make_world_with_buildings()
	var brave: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1, Vector3(40.5, 0, 40.5))
	var own: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 0, Vector3(39.5, 0, 39.5))
	var spell: TornadoSpell = TornadoSpell.new()
	check(spell.execute(w.tribe0, Vector3(40, 0, 40), w.ctx), "tornado spawned")
	var vortex: TornadoVortex = w.unit_manager.projectiles[0]
	vortex._redirect = 999.0
	vortex._drift = Vector3.ZERO
	var ticks: int = _run(w, [brave],
		func() -> bool: return brave.state == Unit.State.THROWN)
	check(ticks < MAX_TICKS, "unit in the path is whirled up")
	check(own.state == Unit.State.THROWN,
		"the twister is tribe-blind: OWN units in the way get whirled up too")
	var ground: float = w.td.get_height(brave.position.x, brave.position.z)
	_run(w, [brave], func() -> bool: return brave.position.y > ground + 3.0)
	check(brave.position.y > ground + 3.0, "rider gains height toward the tip")
	ticks = _run(w, [brave], func() -> bool:
		return brave.state == Unit.State.IDLE or brave.state == Unit.State.DEAD)
	check(ticks < MAX_TICKS, "flung unit lands and finishes its tumble")
	if brave.state == Unit.State.IDLE:
		check(brave._flat_dist(brave.position, Vector3(40, 0, 40)) > 3.0,
			"flung well away from the vortex")
		check(brave.health <= brave.max_health - TornadoVortex.FALL_DAMAGE,
			"fall damage (1/2 brave life) plus roll damage applied")
	_free_world_with_buildings(w)


func test_thrown_into_water_dies_instantly() -> void:
	var td: TerrainData = _channel_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var tribe: Tribe = Tribe.new(0)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe] as Array[Tribe])
	var brave: Unit = um.spawn_unit(BRAVE_SCENE_T, 0, Vector3(58, 0, 64))
	brave.throw_airborne(Vector3(8.0, 4.0, 0.0))   # arcs into the channel
	for i in range(100):
		brave.tick(TICK)
		if brave.state == Unit.State.DEAD:
			break
	check(brave.state == Unit.State.DEAD, "landing in water is instant death")
	um.free()


func test_shaman_stats() -> void:
	var w: Dictionary = _make_world()
	var shaman: Unit = w.unit_manager.spawn_unit(SHAMAN_SCENE, 0, Vector3(30, 0, 30))
	check(shaman.max_health == 240, "shaman HP = 4x brave (240)")
	check_near(shaman.melee_strength(), 2.0, "shaman melee = 2x brave")
	check(shaman.is_panic_immune(), "shaman is panic-immune")
	check(shaman.is_conversion_immune(), "shaman cannot be converted")
	_free_world(w)


# --- Phase 7c: terrain-integrity rules ---------------------------------------------

const HUT_SCENE_T: PackedScene = preload("res://scenes/buildings/hut.tscn")


func _has_debris(w: Dictionary) -> bool:
	for p in w.unit_manager.projectiles:
		if p is BuildingDebris:
			return true
	return false


func test_integrity_foundation_break_shatters_building() -> void:
	var w: Dictionary = _make_world_with_buildings()
	var hut: Building = w.bm.place(HUT_SCENE_T, w.tribe1, Vector2i(50, 50), 0, true)
	# A solid dip under one corner still stays below the break threshold
	# (buildings are fairly sturdy against terrain changes).
	w.td.set_vertex_height(50, 50, 3.2)
	w.ctx.apply_terrain_change(Rect2i(49, 49, 3, 3))
	check(hut.health > 0, "span below the threshold keeps the building standing")
	check(not _has_debris(w), "no debris while the foundation holds")
	# Tearing the corner further down breaks the foundation: instant burst.
	w.td.set_vertex_height(50, 50, 2.5)
	w.ctx.apply_terrain_change(Rect2i(49, 49, 3, 3))
	check(hut.health == 0, "foundation span > threshold bursts the building")
	check(hut not in w.bm.buildings, "burst building deregistered")
	check(_has_debris(w), "debris pieces fly off the burst building")
	_free_world_with_buildings(w)


func test_foundation_settles_after_surviving_terrain_change() -> void:
	var w: Dictionary = _make_world_with_buildings()
	var hut: Building = w.bm.place(HUT_SCENE_T, w.tribe1, Vector2i(50, 50), 0, true)
	w.td.set_vertex_height(50, 50, 3.4)   # span 1.6 m: bent but standing
	w.ctx.apply_terrain_change(Rect2i(49, 49, 3, 3))
	check(hut.health > 0, "hut survives the 1.6 m step")
	# The crooked foundation levels itself back over time.
	for i in range(120):
		w.bm.tick(0.1)
	var lo: float = INF
	var hi: float = -INF
	for vz in range(50, 55):
		for vx in range(50, 55):
			var h: float = w.td.vertex_height(vx, vz)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	check(hi - lo < 0.1, "foundation settled back to a level plane")
	check_near(hut.position.y, (lo + hi) * 0.5, "hut re-seated on the settled ground", 0.1)
	_free_world_with_buildings(w)


func test_integrity_flood_slides_building_and_drowns_units() -> void:
	var w: Dictionary = _make_world_with_buildings()
	var hut: Building = w.bm.place(HUT_SCENE_T, w.tribe1, Vector2i(50, 50), 0, true)
	var wet: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1, Vector3(49, 0, 49))
	var dry: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1, Vector3(30, 0, 30))
	# The whole plot sinks below the sea line (as the sink spell would do).
	for vz in range(47, 58):
		for vx in range(47, 58):
			w.td.set_vertex_height(vx, vz, 1.0)
	w.ctx.apply_terrain_change(Rect2i(47, 47, 11, 11))
	check(hut.health == 0, "mostly flooded building is destroyed (slides into the sea)")
	check(not _has_debris(w), "flooding sinks the model instead of bursting it")
	check(wet.state == Unit.State.DEAD, "follower on flooded ground drowns instantly")
	check(dry.state != Unit.State.DEAD, "follower on dry ground is unaffected")
	_free_world_with_buildings(w)


# --- Phase 7c: earthquake -----------------------------------------------------------

func test_earthquake_upheaval_buildings_and_units() -> void:
	var w: Dictionary = _make_world_with_buildings()
	w.unit_manager.spawn_unit(SHAMAN_SCENE, 0, Vector3(30, 0, 30))
	var hut: Building = w.bm.place(HUT_SCENE_T, w.tribe1, Vector2i(38, 28), 0, true)
	var enemy: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1, Vector3(42, 0, 30))
	var own: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 0, Vector3(41, 0, 31))
	var far_off: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1, Vector3(60, 0, 60))
	var spell: EarthquakeSpell = EarthquakeSpell.new()
	check(spell.execute(w.tribe0, Vector3(40, 5, 30), w.ctx), "earthquake cast succeeds")
	check(hut.destruction_stage() >= 2 or hut.health == 0,
		"building in the radius takes +2 destruction stages")
	check(enemy.health == enemy.max_health - EarthquakeSpell.UNIT_DAMAGE,
		"enemy takes 1/4 brave life")
	check(enemy.state == Unit.State.ROLL, "enemy tumbles away from the epicentre")
	check(own.health == own.max_health, "own units take no direct quake damage")
	check(far_off.health == far_off.max_health, "units outside the radius untouched")
	# The upheaval is gradual and stays inside the radius.
	var outside_before: float = w.td.vertex_height(60, 60)
	for i in range(25):
		w.unit_manager.tick(0.1)
	var moved: float = 0.0
	for vz in range(25, 36):
		for vx in range(35, 46):
			moved = maxf(moved, absf(w.td.vertex_height(vx, vz) - 5.0))
	check(moved > 0.3, "vertices inside the radius shifted after the morph")
	check_near(w.td.vertex_height(60, 60), outside_before,
		"vertices outside the radius unchanged")
	_free_world_with_buildings(w)


func test_earthquake_water_clamp() -> void:
	var td: TerrainData = _channel_terrain()
	var plan: Dictionary = EarthquakeSpell.upheaval_targets(td, Vector2(63, 64))
	var indices: PackedInt32Array = plan.indices
	var targets: PackedFloat32Array = plan.targets
	check(not indices.is_empty(), "quake in the channel still lowers ground")
	for i in range(indices.size()):
		if td.heights[indices[i]] <= TerrainData.SEA_LEVEL:
			check(targets[i] <= td.heights[indices[i]],
				"sea-floor vertices are never lifted")


func test_earthquake_forms_visible_fault_edge() -> void:
	var td: TerrainData = _flat_terrain()
	var plan: Dictionary = EarthquakeSpell.upheaval_targets(td, Vector2(40, 40))
	var indices: PackedInt32Array = plan.indices
	var targets: PackedFloat32Array = plan.targets
	check(not indices.is_empty(), "fault plan is non-empty")
	# Effective post-quake heights over the affected neighbourhood.
	var height_of: Dictionary = {}
	for i in range(indices.size()):
		height_of[indices[i]] = targets[i]
	var deepest: float = 0.0
	var highest: float = 0.0
	for i in range(indices.size()):
		var delta: float = targets[i] - 5.0
		deepest = minf(deepest, delta)
		highest = maxf(highest, delta)
	check(deepest <= -1.5, "the drop side sinks visibly")
	check(highest >= 0.3, "the rise side piles up slightly")
	# Somewhere along the line two ADJACENT vertices end up far apart: the
	# visible scarp edge (unchanged neighbours count with their old height).
	var edge_found: bool = false
	for vz in range(34, 47):
		for vx in range(34, 47):
			var idx: int = vz * TerrainData.VERTS + vx
			var h: float = height_of.get(idx, 5.0)
			var h_right: float = height_of.get(idx + 1, 5.0)
			var h_down: float = height_of.get(idx + TerrainData.VERTS, 5.0)
			if absf(h - h_right) >= 1.2 or absf(h - h_down) >= 1.2:
				edge_found = true
	check(edge_found, "adjacent vertices jump >= 1.2 m: a visible broken edge")


func test_earthquake_spawns_short_fault_lava() -> void:
	var w: Dictionary = _make_world()
	w.unit_manager.spawn_unit(SHAMAN_SCENE, 0, Vector3(30, 0, 30))
	var spell: EarthquakeSpell = EarthquakeSpell.new()
	check(spell.execute(w.tribe0, Vector3(40, 5, 40), w.ctx), "quake cast succeeds")
	var flows: int = 0
	for p in w.unit_manager.projectiles:
		if p is LavaFlow:
			flows += 1
			check(not (p as LavaFlow).scorch, "fault lava leaves no scorch")
			check((p as LavaFlow).lifetime <= 4.0, "fault lava vanishes quickly")
	check(flows == 3, "three lava streams spill over the fresh scarp")
	var ticks: int = 0
	while not w.unit_manager.projectiles.is_empty() and ticks < 100:
		w.unit_manager.tick(0.1)
		ticks += 1
	check(w.unit_manager.projectiles.is_empty(),
		"morph and fault lava are gone shortly after the quake")
	_free_world(w)


# --- Phase 7c: lava & burning ---------------------------------------------------------

func test_lava_flow_ignites_burns_and_panics() -> void:
	var w: Dictionary = _make_world()
	# Downhill slope in +x so the stream keeps flowing (on flat ground lava
	# pools after ~1 m — that is intended behaviour).
	for vz in range(34, 47):
		for vx in range(40, 50):
			w.td.set_vertex_height(vx, vz, 5.0 - 0.35 * float(vx - 40))
	var victim: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1, Vector3(43, 4, 40))
	var flow: LavaFlow = LavaFlow.new()
	flow.setup(Vector3(40, 5, 40), Vector3(1, 0, 0), w.unit_manager, w.td)
	w.unit_manager.register_projectile(flow)
	var panicked: bool = false
	var contact_seen: bool = false
	for i in range(120):
		w.unit_manager.tick(0.1)
		if is_instance_valid(victim) and victim.state != Unit.State.DEAD:
			victim.tick(0.1)
			if victim.state == Unit.State.PANIC:
				panicked = true
			if victim.health <= victim.max_health - Unit.LAVA_CONTACT_DAMAGE:
				contact_seen = true
	check(contact_seen, "lava contact costs half a brave life at once")
	check(panicked, "the burning brave scrambles around in panic")
	check(victim.state == Unit.State.DEAD, "contact + burn (2x brave life) kill a brave")
	check(flow._travelled <= flow.flow_range + 0.5, "the stream only flows a short distance")
	check((flow._segments[0] as Dictionary).cooled, "old segments have cooled (ground blackens)")
	_free_world(w)


func test_ignite_shaman_burns_without_panicking() -> void:
	var w: Dictionary = _make_world()
	var shaman: Unit = w.unit_manager.spawn_unit(SHAMAN_SCENE, 1, Vector3(40, 5, 40))
	shaman.ignite(Vector3(41, 5, 40))
	check(shaman.health == shaman.max_health - Unit.LAVA_CONTACT_DAMAGE,
		"contact damage applies to the panic-immune shaman too")
	check(shaman.state != Unit.State.PANIC, "the shaman burns without panicking")
	check(shaman.is_burning(), "burn timer is running")
	for i in range(45):
		shaman.tick(0.1)
	check(not shaman.is_burning(), "the burn wears off after its duration")
	check(shaman.health <= shaman.max_health - Unit.LAVA_CONTACT_DAMAGE
		- Unit.BURN_TOTAL_DAMAGE + 10,
		"the full burn dealt ~2x brave life on top of the contact hit")
	check(shaman.state != Unit.State.DEAD, "a full-health shaman survives one burn")
	_free_world(w)


# --- Phase 7c: volcano ---------------------------------------------------------------

func test_volcano_cone_lava_and_permanence() -> void:
	var w: Dictionary = _make_world_with_buildings()
	var target: Vector3 = Vector3(40, 5, 40)
	var enemy: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1, Vector3(43, 5, 40))
	var own: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 0, Vector3(37, 5, 40))
	var spell: VolcanoSpell = VolcanoSpell.new()
	check(spell.execute(w.tribe0, target, w.ctx), "volcano cast succeeds")
	for i in range(35):
		w.unit_manager.tick(0.1)   # cone morph (3 s) completes
	check(w.td.get_height(40.0, 40.0) >= 5.0 + VolcanoSpell.PEAK - 1.0,
		"cone tip rises to (nearly) peak height")
	var surges: int = 0
	for p in w.unit_manager.projectiles:
		if p is LavaSurge:
			surges += 1
	check(surges >= 1, "lava wells up once the cone is at max height")
	for i in range(15):
		w.unit_manager.tick(0.1)   # the sheet spreads over both flank units
	check(enemy.state == Unit.State.DEAD or enemy.health < enemy.max_health,
		"the surge covers ALL flanks: enemy on one side is burned")
	check(own.state == Unit.State.DEAD or own.health < own.max_health,
		"...and the own unit on the opposite side too (lava knows no friends)")
	var peak_after_morph: float = w.td.get_height(40.0, 40.0)
	for i in range(330):
		w.unit_manager.tick(0.1)   # zone (20 s) + last surge (9 s) expire
	check(w.unit_manager.projectiles.is_empty(),
		"eruption over: zone and every lava surge despawned")
	check_near(w.td.get_height(40.0, 40.0), peak_after_morph,
		"the mountain is permanent (height unchanged after the eruption)")
	_free_world_with_buildings(w)


func test_volcano_zone_building_cadence() -> void:
	var w: Dictionary = _make_world_with_buildings()
	var hut: Building = w.bm.place(HUT_SCENE_T, w.tribe1, Vector2i(50, 50), 0, true)
	var zone: VolcanoZone = VolcanoZone.new()
	zone.setup(0, hut.center_world(), w.unit_manager, w.td, w.bm)
	w.unit_manager.register_projectile(zone)
	for i in range(39):
		w.unit_manager.tick(0.1)
	check(hut.destruction_stage() == 0, "no stage before 4 s of lava contact")
	for i in range(4):
		w.unit_manager.tick(0.1)
	check(hut.destruction_stage() == 1, "+1 stage after 4 s in the lava")
	for i in range(40):
		w.unit_manager.tick(0.1)
	check(hut.destruction_stage() == 2, "+1 more stage after another 4 s")
	_free_world_with_buildings(w)


# --- Phase 7c: firestorm ---------------------------------------------------------------

func test_firestorm_salvo_spread_and_damage() -> void:
	var w: Dictionary = _make_world()
	w.unit_manager.spawn_unit(SHAMAN_SCENE, 0, Vector3(30, 0, 30))
	var target: Vector3 = Vector3(40, 5, 30)
	var cluster: Array[Unit] = []
	for offset in [Vector3(0, 0, 0), Vector3(1.2, 0, 0.5), Vector3(-1, 0, -0.8)]:
		cluster.append(w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1, target + offset))
	var spell: FirestormSpell = FirestormSpell.new()
	check(spell.execute(w.tribe0, target, w.ctx), "firestorm cast succeeds")
	check(w.unit_manager.projectiles.size() == 1, "shower scheduler registered")
	# Track every bolt the shower launches over its runtime.
	var seen: Dictionary = {}
	var from_sky: bool = true
	for i in range(80):
		w.unit_manager.tick(0.1)
		for p in w.unit_manager.projectiles:
			if p is FireballBolt:
				seen[p.get_instance_id()] = (p as FireballBolt).target_pos
				if (p as FireballBolt)._start.y < (p as FireballBolt).target_pos.y + 8.0:
					from_sky = false
	check(seen.size() == FirestormSpell.BOLT_COUNT, "8 bolts launched over the salvo")
	check(from_sky, "every bolt dives out of the sky above its impact point")
	for pos: Vector3 in seen.values():
		check(Vector2(pos.x - target.x, pos.z - target.z).length() \
			<= FirestormSpell.SPREAD_RADIUS + 0.01,
			"impact scattered within the spread radius")
	var hurt: int = 0
	for u in cluster:
		if u.state == Unit.State.DEAD or u.health < u.max_health:
			hurt += 1
	check(hurt >= 2, "the salvo hits the crowd repeatedly")
	check(w.unit_manager.projectiles.is_empty(), "shower and bolts all despawned")
	_free_world(w)


# --- Phase 7c: flatten ------------------------------------------------------------------

func test_flatten_levels_square_with_hard_edges() -> void:
	var w: Dictionary = _make_world_with_buildings()
	# Hill east of the target; its west slope reaches into the flatten square.
	for vz in range(27, 34):
		for vx in range(42, 49):
			w.td.set_vertex_height(vx, vz, 8.0)
	var hut: Building = w.bm.place(HUT_SCENE_T, w.tribe1, Vector2i(44, 28), 0, true)
	var on_hill: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1, Vector3(43, 8, 30))
	var outside: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1, Vector3(50, 8, 30))
	var target: Vector3 = Vector3(40, 5, 30)   # ground level 5.0
	var spell: FlattenSpell = FlattenSpell.new()
	check(spell.execute(w.tribe0, target, w.ctx), "flatten cast succeeds")
	check(on_hill.state == Unit.State.THROWN,
		"unit on the collapsing hill slope is flung")
	for i in range(10):
		w.unit_manager.tick(0.1)   # fast morph (0.5 s) completes
	for vx in range(36, 45):
		check_near(w.td.vertex_height(vx, 30), 5.0,
			"square vertex (%d, 30) exactly on target level" % vx)
	check_near(w.td.vertex_height(45, 30), 8.0,
		"first vertex outside the square untouched (hard cliff edge)")
	check(hut.health == 0, "building straddling the new cliff bursts apart")
	check(_has_debris(w), "burst building spawned debris")
	check(outside.state != Unit.State.THROWN and outside.health == outside.max_health,
		"unit outside the square unaffected")
	_free_world_with_buildings(w)


func test_flatten_below_sea_floods_and_drowns() -> void:
	var td: TerrainData = _channel_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var tribe0: Tribe = Tribe.new(0)
	var tribe1: Tribe = Tribe.new(1)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe0, tribe1] as Array[Tribe])
	var ctx: SpellContext = SpellContext.new()
	ctx.terrain_data = td
	ctx.nav_grid = nav
	ctx.unit_manager = um
	var victim: Unit = um.spawn_unit(BRAVE_SCENE_T, 1, Vector3(59.5, 5, 64))
	var spell: FlattenSpell = FlattenSpell.new()
	# Target in the water channel: the square flattens onto sea-floor level.
	check(spell.execute(tribe0, Vector3(63, 0, 64), ctx), "flatten onto water level works")
	for i in range(60):
		um.tick(0.1)
		if is_instance_valid(victim) and victim.state != Unit.State.DEAD:
			victim.tick(0.1)
	check(td.get_height(59.0, 64.0) <= TerrainData.SEA_LEVEL,
		"former land inside the square now sits below the sea line")
	check(victim.state == Unit.State.DEAD, "follower on the flooded square dies")
	um.free()


# --- Phase 7c: sink -----------------------------------------------------------------------

func test_sink_lowers_with_falloff_and_floor_clamp() -> void:
	var w: Dictionary = _make_world()
	var spell: SinkSpell = SinkSpell.new()
	check(spell.execute(w.tribe0, Vector3(40, 5, 40), w.ctx), "sink cast succeeds")
	for i in range(20):
		w.unit_manager.tick(0.1)
	check_near(w.td.vertex_height(40, 40), 5.0 - SinkSpell.DEPTH,
		"centre lowered by the full depth", 0.05)
	var rim: float = w.td.vertex_height(44, 40)
	check(rim > 5.0 - SinkSpell.DEPTH + 0.5 and rim < 5.0,
		"rim lowered less than the centre (soft falloff)")
	check_near(w.td.vertex_height(47, 40), 5.0, "outside the radius unchanged")
	# Repeated casts never dig below the sea floor.
	check(spell.execute(w.tribe0, Vector3(40, 2, 40), w.ctx), "second sink cast works")
	for i in range(20):
		w.unit_manager.tick(0.1)
	check(w.td.vertex_height(40, 40) >= SinkSpell.FLOOR_LEVEL - 0.01,
		"floor clamp: never below the sea floor")
	_free_world(w)


func test_sink_floods_coastal_building_and_units() -> void:
	var w: Dictionary = _make_world_with_buildings()
	# Low coastal shelf around the enemy plot.
	for vz in range(30, 52):
		for vx in range(30, 52):
			w.td.set_vertex_height(vx, vz, 3.5)
	var hut: Building = w.bm.place(HUT_SCENE_T, w.tribe1, Vector2i(38, 38), 0, true)
	var victim: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1, Vector3(41, 3.5, 41))
	var dry: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1, Vector3(60, 5, 60))
	var spell: SinkSpell = SinkSpell.new()
	check(spell.execute(w.tribe0, Vector3(40, 3.5, 40), w.ctx), "coastal sink cast succeeds")
	for i in range(20):
		w.unit_manager.tick(0.1)
	check(w.td.cell_height(Vector2i(40, 40)) <= TerrainData.SEA_LEVEL,
		"the plot sank below the sea line")
	check(hut.health == 0, "mostly flooded building slides into the water")
	check(not _has_debris(w), "flooded building sinks instead of bursting")
	check(victim.state == Unit.State.DEAD, "follower on the flooded plot drowns")
	check(dry.state != Unit.State.DEAD, "distant follower survives")
	_free_world_with_buildings(w)
