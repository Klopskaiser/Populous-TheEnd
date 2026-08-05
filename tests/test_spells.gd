extends TestBase

## Headless tests for phase 6: the spell framework (charge system, parallel
## mana distribution, cast flow via the shaman) and the shaman kill bonus.
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

func test_partial_fill_is_shown_before_the_first_charge() -> void:
	var tribe: Tribe = Tribe.new(0)
	var spell: DummySpell = DummySpell.new(&"dummy", 10.0, 4)
	tribe.set_spells([spell] as Array[Spell])
	tribe.grant_bonus_mana(5.0)
	check(spell.charges == 0, "half the cost is not a charge yet")
	check_near(spell.charge_progress, 0.5, "...but the bar shows the half fill")
	check(not spell.cast(tribe, Vector3.ZERO, null), "cast without charge fails")
	check(spell.executed == 0, "failed cast has no side effect")


## Phase 10c: mana is a FLOW. A full spell takes nothing more, and income with
## no taker left is discarded instead of piling up in a bank.
func test_charging_stops_at_full_and_overflow_is_lost() -> void:
	var tribe: Tribe = Tribe.new(0)
	var spell: DummySpell = DummySpell.new(&"dummy", 10.0, 2)
	tribe.set_spells([spell] as Array[Spell])
	tribe.grant_bonus_mana(25.0)
	check(spell.charges == 2, "mana fills the spell up to max_charges")
	check_near(spell.charge_mana, 0.0, "a full spell carries no partial fill")
	check_near(tribe.mana, 0.0, "the 5 that no longer fitted is gone, not banked")
	tribe.grant_bonus_mana(20.0)
	check(spell.charges == 2, "a full spell takes nothing more at all")
	check_near(tribe.mana, 0.0, "and still nothing is banked")


## The round-robin is gone: every active spell is fed AT THE SAME TIME with an
## equal share, so the cheap one comes back sooner purely through its cost.
func test_all_active_spells_charge_in_parallel() -> void:
	var tribe: Tribe = Tribe.new(0)
	var cheap: DummySpell = DummySpell.new(&"cheap", 10.0, 4)
	var pricey: DummySpell = DummySpell.new(&"pricey", 30.0, 4)
	tribe.set_spells([pricey, cheap] as Array[Spell])
	tribe.grant_bonus_mana(20.0)   # 10 each
	check(cheap.charges == 1, "the cheap spell already has its first charge")
	check(pricey.charges == 0, "the expensive one is only a third of the way")
	check_near(pricey.charge_progress, 1.0 / 3.0, "...and shows exactly that")
	tribe.grant_bonus_mana(40.0)   # 20 each -> cheap +2, pricey reaches 30
	check(cheap.charges == 3, "cheap: three charges from 60 mana of income")
	check(pricey.charges == 1, "expensive: one - same income, higher cost")


## Switching a spell off frees its share for the others; its stored charges
## stay castable and its partial fill is kept for when it is switched back on.
func test_inactive_spell_stops_charging_but_keeps_progress() -> void:
	var tribe: Tribe = Tribe.new(0)
	var a: DummySpell = DummySpell.new(&"a", 10.0, 4)
	var b: DummySpell = DummySpell.new(&"b", 10.0, 4)
	tribe.set_spells([a, b] as Array[Spell])
	tribe.grant_bonus_mana(10.0)   # 5 each
	check_near(a.charge_progress, 0.5, "both are half full")
	a.charges = 1                  # a stored charge to prove it survives
	tribe.set_spell_active(&"a", false)
	check(tribe.active_spell_count() == 1, "only one spell still takes mana")
	tribe.grant_bonus_mana(10.0)   # all of it goes to b
	check_near(a.charge_progress, 0.5, "the paused spell keeps its partial fill")
	check(a.charges == 1, "...and its stored charge")
	check(b.charges == 1, "the whole income went to the active spell")
	check(a.cast(tribe, Vector3.ZERO, null), "a paused spell is still castable")
	check(a.charges == 0, "the cast spent it")
	check_near(a.charge_progress, 0.5, "the kept fill survives the cast too")
	tribe.set_spell_active(&"a", true)
	tribe.grant_bonus_mana(10.0)   # 5 each again
	check(a.charges == 1,
		"resumed where it left off: the kept 0.5 plus 0.5 completed a charge")


## Every spell starts switched on (user spec).
func test_spells_start_active() -> void:
	var tribe: Tribe = Tribe.new(0)
	tribe.set_spells(Spell.create_default_set())
	for spell in tribe.spells:
		check(spell.active, "%s starts active" % spell.id)
	check(tribe.active_spell_count() == tribe.spells.size(), "all of them take mana")


## With everything switched off the income has nowhere to go and is dropped -
## there is no mana banking any more.
func test_income_without_takers_is_discarded() -> void:
	var tribe: Tribe = Tribe.new(0)
	var spell: DummySpell = DummySpell.new(&"dummy", 10.0, 4)
	tribe.set_spells([spell] as Array[Spell])
	tribe.set_spell_active(&"dummy", false)
	var braves: Array[Brave] = []
	for i in range(10):
		var brave: Brave = Brave.new()
		braves.append(brave)
		tribe.add_unit(brave)
	check(tribe.mana_rate() > 0.0, "the tribe does produce mana")
	for i in range(100):
		tribe.tick(1.0)
	check_near(tribe.mana, 0.0, "100 s of income with no taker leaves nothing")
	check(spell.charges == 0, "and charges nothing")
	for brave in braves:
		brave.free()


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


# --- Cast wind-up and incantation (phase 10b) -----------------------------------------

## Spawns a shaman already inside cast range of `target`, with a charged spell
## ordered. Returns {shaman, spell}.
func _armed_shaman(w: Dictionary, target: Vector3) -> Dictionary:
	var shaman: Unit = w.unit_manager.spawn_unit(SHAMAN_SCENE, 0, Vector3(30, 0, 30))
	var spell: DummySpell = DummySpell.new(&"dummy", 10.0, 4)
	w.tribe0.set_spells([spell] as Array[Spell])
	spell.charges = 1
	w.tc.cast_spell(w.tribe0, &"dummy", target)
	return {"shaman": shaman, "spell": spell}


func test_cast_time_is_one_second() -> void:
	check_near(Balance.SHAMAN_CAST_TIME, 1.0, "the wind-up is 1.0 s for every spell")
	var w: Dictionary = _make_world()
	var a: Dictionary = _armed_shaman(w, Vector3(33, 0, 30))   # inside cast_range
	for i in range(9):
		a.shaman.tick(TICK)
	check(a.spell.executed == 0, "nothing fired after 0.9 s of wind-up")
	# Two more ticks, not one: 10 x 0.1 leaves the timer a hair above zero
	# (float accumulation), so bracket the wind-up instead of counting on the
	# exact tick it crosses.
	a.shaman.tick(TICK)
	a.shaman.tick(TICK)
	check(a.spell.executed == 1, "the spell releases once the 1.0 s wind-up is over")
	_free_world(w)


func test_spell_voice_emitted_at_windup_start() -> void:
	var w: Dictionary = _make_world()
	var a: Dictionary = _armed_shaman(w, Vector3(33, 0, 30))
	check(not a.shaman._voice_played, "no incantation before the first tick")
	a.shaman.tick(TICK)
	check(a.shaman._voice_played, "the incantation starts with the wind-up")
	check(a.spell.executed == 0, "and well before the spell itself goes off")
	_free_world(w)


## On the edge of cast range _casting flips off and on again every tick. The
## latch must survive that, otherwise the incantation stutters.
func test_spell_voice_not_repeated_at_range_edge() -> void:
	var w: Dictionary = _make_world()
	var a: Dictionary = _armed_shaman(w, Vector3(33, 0, 30))
	var shaman: Unit = a.shaman
	shaman.tick(TICK)
	check(shaman._casting and shaman._voice_played, "wind-up running, incantation spoken")
	# Shove her out of range: the wind-up aborts and she walks again.
	shaman.position = Vector3(60, 0, 30)
	shaman.tick(TICK)
	check(not shaman._casting, "out of range -> wind-up aborted")
	check(shaman._voice_played, "the latch survives the abort")
	# Back in range: the wind-up restarts, the incantation does NOT.
	shaman.position = Vector3(30, 0, 30)
	shaman.tick(TICK)
	check(shaman._casting, "back in range -> wind-up restarted")
	check(shaman._voice_played, "still latched, so nothing is spoken a second time")
	# Only a NEW cast order speaks again.
	shaman.order_move(Vector3(31, 0, 30))
	check(not shaman._voice_played, "cancelling the cast clears the latch")
	_free_world(w)


func test_spell_audio_names() -> void:
	check(SpellAudio.voice_name(&"fireball") == &"spell_voice_fireball",
		"incantation file name")
	check(SpellAudio.effect_name(&"lightning") == &"spell_lightning",
		"effect file name")
	check(SpellAudio.effect_name(&"tornado", &"_loop") == &"spell_tornado_loop",
		"suffixed effect name (the tornado's howl)")


# --- Shaman kill bonus ----------------------------------------------------------------

## Phase 10c: the bonus is 10 % of the MINUTE production of the tribe that
## lost its shaman, spread over the killer's active charge rates. Killing the
## shaman of a big tribe is worth more than of a small one.
func test_shaman_kill_grants_charge_bonus() -> void:
	var w: Dictionary = _make_world()
	var shaman: Unit = w.unit_manager.spawn_unit(SHAMAN_SCENE, 0, Vector3(30, 0, 30))
	var killer: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 1, Vector3(31, 0, 30))
	# Victim tribe: the shaman alone. Its minute production x 10 % is the bonus.
	var expected: float = w.tribe0.mana_rate() * 60.0 \
		* Balance.SHAMAN_KILL_MANA_MINUTE_SHARE
	check(expected > 0.0, "the victim tribe does produce mana")
	var spell: DummySpell = DummySpell.new(&"dummy", expected, 10)
	w.tribe1.set_spells([spell] as Array[Spell])
	shaman.take_damage(9999, killer)
	check(shaman.state == Unit.State.DEAD, "shaman died")
	check(spell.charges == 1, "the bonus is worth exactly one charge of that size")
	check_near(w.tribe1.mana, 0.0, "nothing is banked")
	_free_world(w)


## The bigger the victim tribe, the fatter the reward.
func test_shaman_kill_bonus_scales_with_the_victim_tribe() -> void:
	var small: Tribe = Tribe.new(0)
	var big: Tribe = Tribe.new(1)
	var braves: Array[Brave] = []
	for i in range(20):
		var brave: Brave = Brave.new()
		braves.append(brave)
		big.add_unit(brave)
	check(big.mana_rate() > small.mana_rate(), "the big tribe produces more")
	var from_small: float = small.mana_rate() * 60.0 \
		* Balance.SHAMAN_KILL_MANA_MINUTE_SHARE
	var from_big: float = big.mana_rate() * 60.0 \
		* Balance.SHAMAN_KILL_MANA_MINUTE_SHARE
	check(from_big > from_small, "so its shaman is the more valuable kill")
	for brave in braves:
		brave.free()


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
	check(spells.size() == 11, "eleven spells in the default set (phase 6 + 7c + supertornado)")
	# 7c charge counts are binding: volcano 1, firestorm/earthquake 2,
	# flatten/sink 3 (see plans/07c_new_spells.md). Supertornado: 1 charge.
	var expected: Dictionary = {
		&"fireball": 4, &"lightning": 4, &"swarm": 4, &"landbridge": 4,
		&"tornado": 3, &"earthquake": 2, &"volcano": 1, &"firestorm": 2,
		&"flatten": 3, &"sink": 3, &"supertornado": 1}
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
	# Wood cannot be dropped into the sea at all (phase 10a) — the pile that
	# rides the ramp up sits on the LAND part of the corridor.
	wpm.deposit(Vector3(65, 0, 64), 3)   # into the channel = into the water
	check(wpm.piles.is_empty(), "wood dropped into the channel is lost, not floating")
	wpm.deposit(Vector3(58.5, 0, 64), 3)   # land inside the future corridor
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


## Phase 10c: the bystanders are HURLED (THROWN) instead of merely bowled over
## — the tumble now happens by itself when they land (_land_from_throw).
func test_lightning_kills_unit_and_rolls_neighbors() -> void:
	var w: Dictionary = _make_world_with_buildings()
	w.unit_manager.spawn_unit(SHAMAN_SCENE, 0, Vector3(30, 0, 30))
	var victim: Unit = w.unit_manager.spawn_unit(SHAMAN_SCENE, 1, Vector3(40, 0, 30))
	var neighbor: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1, Vector3(41, 0, 30))
	var own: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 0, Vector3(39, 0, 30))
	var spell: LightningSpell = LightningSpell.new()
	check(spell.execute(w.tribe0, Vector3(40.2, 0, 30), w.ctx), "lightning strikes")
	check(victim.state == Unit.State.DEAD, "240 damage kills even a full shaman")
	check(neighbor.state == Unit.State.THROWN, "adjacent enemy is hurled away")
	check(own.state != Unit.State.ROLL and own.state != Unit.State.THROWN,
		"own unit next to the strike stays up")
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
	check(wet._drowning, "the flood death is an animated drowning (phase 10a)")
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
			check((p as LavaFlow).lifetime == Balance.LAVA_LIFETIME,
				"fault lava lives exactly one central lava lifetime")
	check(flows == 1, "ONE broad carpet spills over the fresh scarp")
	var ticks: int = 0
	while not w.unit_manager.projectiles.is_empty() and ticks < 100:
		w.unit_manager.tick(0.1)
		ticks += 1
	check(w.unit_manager.projectiles.is_empty(),
		"morph and fault lava are gone shortly after the quake")
	_free_world(w)


# --- Phase 10c: the shared lava model --------------------------------------------------

## Red and viscous, not orange: the hot front and the aged body both have to
## read as red on screen.
func test_lava_colour_is_red() -> void:
	var hot: Color = LavaCommon.color_for(0.0, Balance.LAVA_MOLTEN_TIME, false, true)
	check(hot.r > 0.85 and hot.g < 0.30, "the fresh front is a saturated red")
	var body: Color = LavaCommon.color_for(Balance.LAVA_MOLTEN_TIME * 0.5,
		Balance.LAVA_MOLTEN_TIME, false, true)
	check(body.r > body.g * 3.0 and body.g < 0.30, "the ageing body stays red")
	var cold: Color = LavaCommon.color_for(Balance.LAVA_MOLTEN_TIME + 1.0,
		Balance.LAVA_MOLTEN_TIME, true, true)
	check(cold == LavaCommon.COLOR_SCORCH, "a cooled crust is black scorch")
	var fading: Color = LavaCommon.color_for(Balance.LAVA_MOLTEN_TIME,
		Balance.LAVA_MOLTEN_TIME, true, false)
	check(fading.a > 0.9, "without scorch the crust starts fading instead")


func test_lava_flow_speed_law() -> void:
	check_near(LavaCommon.flow_speed(0.0), Balance.LAVA_FLOW_SPEED,
		"flat ground: the viscous base speed")
	check(LavaCommon.flow_speed(0.4) > LavaCommon.flow_speed(0.1),
		"the steeper the descent, the faster it runs")
	check(LavaCommon.flow_speed(-0.5) == 0.0, "uphill the mass piles up (speed 0)")
	check(LavaCommon.flow_speed(10.0) <= Balance.LAVA_FLOW_SPEED * 3.0,
		"a cliff face does not launch the lava (clamped)")


## Slow AND terrain-following: on a slope of 0.35 the law predicts
## FLOW_SPEED * (1 + BIAS * 0.35); the flow must land within 10 % of that and
## far below the old flat 3.0 m/s.
func test_lava_flows_slowly_downhill() -> void:
	var w: Dictionary = _make_world()
	for vz in range(34, 47):
		for vx in range(40, 56):
			w.td.set_vertex_height(vx, vz, 5.0 - 0.35 * float(vx - 40))
	var flow: LavaFlow = LavaFlow.new()
	flow.setup(Vector3(41, 5, 40), Vector3(1, 0, 0), w.unit_manager, w.td, 30.0)
	w.unit_manager.register_projectile(flow)
	for i in range(20):
		w.unit_manager.tick(0.1)
	var expected: float = LavaCommon.flow_speed(0.35) * 2.0
	check(absf(flow._travelled - expected) <= expected * 0.1,
		"after 2 s the front travelled %.2f m (law: %.2f m)" % [flow._travelled, expected])
	check(flow._travelled < 3.0 * 2.0 * 0.75,
		"clearly slower than the old fixed 3.0 m/s")
	_free_world(w)


## Every lava instance reads its life from Balance; only the catapult puddle
## carries its own value.
func test_lava_lifetime_constants() -> void:
	var flow: LavaFlow = LavaFlow.new()
	flow.setup(Vector3.ZERO, Vector3(1, 0, 0), null, null)
	check(flow.lifetime == Balance.LAVA_LIFETIME,
		"a default flow lives LAVA_LIFETIME")
	check(flow.molten_time == Balance.LAVA_MOLTEN_TIME,
		"...and glows for LAVA_MOLTEN_TIME")
	flow.free()
	var surge: LavaSurge = LavaSurge.new()
	check(surge.lifetime == Balance.LAVA_LIFETIME, "a default surge too")
	surge.free()
	var w: Dictionary = _make_world_with_buildings()
	var shot: SiegeShot = SiegeShot.new()
	shot.setup(0, Vector3(40, 5, 40), Vector3(50, 5, 40), null,
		w.unit_manager, w.td, w.bm)
	w.unit_manager.register_projectile(shot)
	var puddle: LavaSurge = null
	for i in range(200):
		w.unit_manager.tick(0.05)
		for p in w.unit_manager.projectiles:
			if p is LavaSurge:
				puddle = p
				break
		if puddle != null:
			break
	check(puddle != null and puddle.lifetime == Balance.LAVA_CATAPULT_LIFETIME,
		"the catapult puddle uses LAVA_CATAPULT_LIFETIME")
	_free_world_with_buildings(w)


## Two counted waves per eruption (phase 10c: was four).
func test_volcano_spawns_exactly_two_surges() -> void:
	var w: Dictionary = _make_world_with_buildings()
	var zone: VolcanoZone = VolcanoZone.new()
	zone.setup(0, Vector3(40, 5, 40), w.unit_manager, w.td, w.bm)
	w.unit_manager.register_projectile(zone)
	var surges: int = 0
	for i in range(200):
		w.unit_manager.tick(0.1)   # the zone's full 20 s life
		for p in w.unit_manager.projectiles:
			if p is LavaSurge and not p.has_meta(&"counted"):
				p.set_meta(&"counted", true)
				surges += 1
	check(surges == Balance.VOLCANO_SURGE_COUNT,
		"exactly %d lava waves per eruption (got %d)"
		% [Balance.VOLCANO_SURGE_COUNT, surges])
	check(Balance.VOLCANO_SURGE_INTERVAL
		<= Balance.LAVA_MOLTEN_TIME + Balance.LAVA_BUILDING_CONTACT_GRACE,
		"the wave gap stays inside the building contact grace window")
	_free_world_with_buildings(w)


## The vents sit on the RISE side of the fault (the upper lip) and point down
## the scarp into the trough.
func test_earthquake_lava_starts_on_upper_edge() -> void:
	var w: Dictionary = _make_world()
	w.unit_manager.spawn_unit(SHAMAN_SCENE, 0, Vector3(30, 0, 30))
	var target: Vector3 = Vector3(40, 5, 40)
	var plan: Dictionary = EarthquakeSpell.upheaval_targets(w.td,
		Vector2(target.x, target.z))
	var normal: Vector2 = plan.normal
	var spell: EarthquakeSpell = EarthquakeSpell.new()
	check(spell.execute(w.tribe0, target, w.ctx), "quake cast succeeds")
	var flows: int = 0
	for p in w.unit_manager.projectiles:
		if not (p is LavaFlow):
			continue
		flows += 1
		var f: LavaFlow = p
		var rel: Vector2 = Vector2(f.position.x - target.x, f.position.z - target.z)
		check_near(rel.dot(normal), Balance.EARTHQUAKE_LAVA_EDGE_OFFSET,
			"the vent sits on the rise side of the fault")
		check(Vector2(f._dir.x, f._dir.z).dot(normal) < -0.9,
			"...and runs down the edge toward the dropped side")
		# The carpet's width is measured ACROSS its flow direction, so it lies
		# along the fault line — that is what makes it cover the whole edge.
		check(f.half_width == Balance.EARTHQUAKE_LAVA_HALF_WIDTH,
			"it spans the scarp instead of trickling down one spot")
		check(f.half_width * 2.0 >= Balance.EARTHQUAKE_RADIUS,
			"...over most of the quake's diameter")
	check(flows == 1, "exactly one carpet, not a bundle of rivulets")
	_free_world(w)


## Regression (bug in the pre-10c code): the flows used to be spawned before
## the 2 s TerrainMorph had opened the scarp at all, so they ran over flat
## ground and pooled on the spot.
func test_earthquake_lava_waits_for_the_scarp() -> void:
	var w: Dictionary = _make_world()
	w.unit_manager.spawn_unit(SHAMAN_SCENE, 0, Vector3(30, 0, 30))
	var spell: EarthquakeSpell = EarthquakeSpell.new()
	check(spell.execute(w.tribe0, Vector3(40, 5, 40), w.ctx), "quake cast succeeds")
	var flow: LavaFlow = null
	for p in w.unit_manager.projectiles:
		if p is LavaFlow:
			flow = p
			break
	check(flow != null and flow.start_delay == Balance.EARTHQUAKE_LAVA_DELAY,
		"the fault lava waits for the morph")
	var steps: int = int(Balance.EARTHQUAKE_LAVA_DELAY / 0.1)
	for i in range(steps):
		w.unit_manager.tick(0.1)
	check(flow._travelled == 0.0, "nothing flows while the ground is still closed")
	for i in range(15):
		w.unit_manager.tick(0.1)
	check(flow._travelled > 0.0, "once the scarp is open the lava runs")
	_free_world(w)


## The radial sheet follows the terrain as well: on a slope the downhill
## sector outruns the uphill one by a wide margin.
func test_lava_surge_follows_terrain() -> void:
	var w: Dictionary = _make_world()
	for vz in range(30, 51):
		for vx in range(30, 51):
			w.td.set_vertex_height(vx, vz, 5.0 - 0.35 * float(vx - 30))
	var surge: LavaSurge = LavaSurge.new()
	surge.setup(Vector3(40, w.td.get_height(40.0, 40.0), 40), w.unit_manager, w.td, 8.0)
	w.unit_manager.register_projectile(surge)
	for i in range(40):
		w.unit_manager.tick(0.1)
	# Sector 0 points along +x (downhill), sector LAVA_SECTORS/2 along -x.
	@warning_ignore("integer_division")
	var uphill: float = surge._sector_radius[LavaSurge.LAVA_SECTORS / 2]
	var downhill: float = surge._sector_radius[0]
	check(downhill > uphill * 1.5,
		"downhill sector %.2f m vs uphill %.2f m" % [downhill, uphill])
	_free_world(w)


## Perf change guard: the ignition switched from one spatial query PER molten
## segment to a single hull-circle query. A unit under a MIDDLE segment (not
## the head, not the tail) must still be ignited.
func test_lava_flow_single_query_equivalence() -> void:
	var w: Dictionary = _make_world()
	for vz in range(34, 47):
		for vx in range(40, 56):
			w.td.set_vertex_height(vx, vz, 5.0 - 0.35 * float(vx - 40))
	var flow: LavaFlow = LavaFlow.new()
	flow.setup(Vector3(41, 5, 40), Vector3(1, 0, 0), w.unit_manager, w.td, 30.0)
	w.unit_manager.register_projectile(flow)
	for i in range(20):
		w.unit_manager.tick(0.1)   # lay down a few segments
	check(flow._segments.size() >= 3, "the trail has a middle to stand on")
	var mid: Vector3 = (flow._segments[flow._segments.size() / 2] as Dictionary).pos
	var victim: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1,
		Vector3(mid.x, mid.y, mid.z))
	for i in range(5):
		w.unit_manager.tick(0.1)
	check(victim.is_burning() or victim.state == Unit.State.DEAD,
		"a unit under a middle segment still burns")
	_free_world(w)


## Regression (user report): the fault carpet has to run STRAIGHT down the
## scarp. With gradient steering on, the head turned back at the bottom of the
## trough, turned again, and knotted up — the trail then had cross-vectors
## pointing every which way and the 10 m wide sheet looked as if it lay ACROSS
## its own scarp. Measured on the segment chain: its extent ALONG the fault line
## must be ~zero, all of its travel goes down the fault normal.
func test_earthquake_carpet_runs_straight_down_the_scarp() -> void:
	var w: Dictionary = _make_world()
	w.unit_manager.spawn_unit(SHAMAN_SCENE, 0, Vector3(30, 0, 30))
	var target: Vector3 = Vector3(64, 5, 64)
	var plan: Dictionary = EarthquakeSpell.upheaval_targets(w.td,
		Vector2(target.x, target.z))
	var fault: Vector2 = plan.fault
	var normal: Vector2 = plan.normal
	var spell: EarthquakeSpell = EarthquakeSpell.new()
	check(spell.execute(w.tribe0, target, w.ctx), "quake cast succeeds")
	var flow: LavaFlow = null
	for p in w.unit_manager.projectiles:
		if p is LavaFlow:
			flow = p
	check(flow != null and flow.steer == 0.0, "the carpet is not steered at all")
	for i in range(60):
		w.unit_manager.tick(0.1)
		if flow.done:
			break
	check(flow._segments.size() >= 2, "the carpet laid down a trail")
	var along_fault: float = 0.0
	var along_normal: float = 0.0
	for seg in flow._segments:
		var rel: Vector2 = Vector2(seg.pos.x - flow.position.x,
			seg.pos.z - flow.position.z)
		along_fault = maxf(along_fault, absf(rel.dot(fault)))
		along_normal = maxf(along_normal, absf(rel.dot(normal)))
	check(along_fault < 0.15,
		"the trail does not drift along the fault (%.2f m)" % along_fault)
	check(along_normal > along_fault * 5.0,
		"it travels down the normal instead (%.2f m)" % along_normal)
	_free_world(w)


## Turn-rate cap: even a steered rivulet may not spin on the spot.
func test_lava_flow_turn_rate_is_capped() -> void:
	var w: Dictionary = _make_world()
	# A bowl: the gradient points at the centre from every side, so an
	# unconstrained head would whip around once it overshoots the middle.
	for vz in range(50, 79):
		for vx in range(50, 79):
			var d: float = Vector2(float(vx) - 64.0, float(vz) - 64.0).length()
			w.td.set_vertex_height(vx, vz, 5.0 + 0.35 * d)
	var flow: LavaFlow = LavaFlow.new()
	flow.setup(Vector3(58, 5, 64), Vector3(1, 0, 0), w.unit_manager, w.td, 30.0)
	w.unit_manager.register_projectile(flow)
	var prev: Vector3 = flow._dir
	var worst: float = 0.0
	for i in range(40):
		w.unit_manager.tick(0.1)
		worst = maxf(worst, absf(prev.signed_angle_to(flow._dir, Vector3.UP)))
		prev = flow._dir
	check(worst <= LavaFlow.MAX_TURN_RATE * 0.1 + 0.001,
		"no step turns faster than the cap (worst %.3f rad)" % worst)
	_free_world(w)


## Regression (user report): the volcano sheet showed terrain through ring-shaped
## GAPS and its ragged front appeared to rotate. Both came from one animated
## bulge factor that scaled only the OUTER edge of each band — below 1.0 it tore
## the band pair apart, and the animation swept the tear around. The mesh must
## therefore be (a) identical for the same sector radii regardless of _life and
## (b) seamless: every band's outer radius is the next band's inner radius.
func test_lava_surge_mesh_is_static_and_seamless() -> void:
	var w: Dictionary = _make_world()
	# A cone, so the sectors advance and several bands exist.
	for vz in range(54, 75):
		for vx in range(54, 75):
			var d: float = Vector2(float(vx) - 64.0, float(vz) - 64.0).length()
			w.td.set_vertex_height(vx, vz, 11.0 - 0.7 * d)
	var surge: LavaSurge = LavaSurge.new()
	surge.setup(Vector3(64, w.td.get_height(64.0, 64.0), 64), w.unit_manager,
		w.td, 7.5)
	surge._mesh = MeshInstance3D.new()
	surge._mesh.mesh = ImmediateMesh.new()
	for i in range(30):
		surge.tick(0.1)
	var mesh: ImmediateMesh = surge._mesh.mesh
	check(mesh.get_surface_count() >= 2, "the sheet spans several bands")

	# (b) Seamless: band k's outer radius == band k+1's inner radius. Each
	# surface starts with [outer(sector 0), inner(sector 0)].
	var seam_error: float = 0.0
	var prev_outer: float = -1.0
	for surf in range(mesh.get_surface_count()):
		var verts: PackedVector3Array = mesh.surface_get_arrays(surf)[Mesh.ARRAY_VERTEX]
		if verts.size() < 2:
			continue
		var outer: float = Vector2(verts[0].x, verts[0].z).length()
		var inner: float = Vector2(verts[1].x, verts[1].z).length()
		if prev_outer >= 0.0:
			seam_error = maxf(seam_error, absf(inner - prev_outer))
		prev_outer = outer
	check(seam_error < 0.001,
		"no gap between the ring bands (worst seam %.4f m)" % seam_error)

	# (a) Static: same radii, later _life -> byte-identical vertices.
	var before: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var kept: PackedVector3Array = before.duplicate()
	surge._life += 1.7
	surge._rebuild_mesh()
	var after: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(after.size() == kept.size(), "same vertex count")
	# XZ only: the sheet DOES move down at the end of its life (_sink_offset,
	# 0.675 m at this point) — that is intended. What must not happen is any
	# horizontal creep, which is what the animated bulge caused.
	var moved: float = 0.0
	for i in range(mini(after.size(), kept.size())):
		moved = maxf(moved, Vector2(after[i].x - kept[i].x,
			after[i].z - kept[i].z).length())
	check(moved < 0.001,
		"the sheet does not creep/rotate sideways (worst %.4f m)" % moved)
	surge._mesh.free()
	surge.free()
	_free_world(w)


# --- Phase 10c: knockback & lift --------------------------------------------------------

## The blast SHOVES further than it burns: a brave just outside the splash
## radius keeps full health but is thrown.
func test_fireball_bolt_pushes_beyond_damage_radius() -> void:
	var w: Dictionary = _make_world()
	var target: Vector3 = Vector3(40, 5, 40)
	var rim: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1, Vector3(43, 5, 40))
	check(Balance.FIREBALL_PUSH_RADIUS > Balance.FIREBALL_SPLASH_RADIUS,
		"the push radius is the wider one")
	var bolt: FireballBolt = FireballBolt.new()
	bolt.setup(0, Vector3(30, 5, 40), target, null, w.unit_manager, w.td)
	bolt._explode()
	check(rim.health == rim.max_health, "3.0 m out: unhurt (splash ends at 2.5 m)")
	check(rim.state == Unit.State.THROWN, "...but shoved and lifted off the ground")
	bolt.free()
	_free_world(w)


## Every follow-up hit on an ALREADY flying unit whirls it higher.
func test_fireball_bolt_lift_amplifies_airborne_target() -> void:
	var w: Dictionary = _make_world()
	var target: Vector3 = Vector3(40, 5, 40)
	var victim: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1, Vector3(41, 5, 40))
	victim.max_health = 9999
	victim.health = 9999
	var bolt: FireballBolt = FireballBolt.new()
	bolt.setup(0, Vector3(30, 5, 40), target, null, w.unit_manager, w.td)
	bolt._explode()
	check(victim.state == Unit.State.THROWN, "the first hit launches it")
	var vy: float = victim._throw_velocity.y
	var bolt2: FireballBolt = FireballBolt.new()
	bolt2.setup(0, Vector3(30, 5, 40), target, null, w.unit_manager, w.td)
	bolt2._explode()
	check(victim._throw_velocity.y >= vy + Balance.LIFT_AIRBORNE_BONUS,
		"the second hit adds at least LIFT_AIRBORNE_BONUS of upward speed")
	bolt.free()
	bolt2.free()
	_free_world(w)


## The strike's shockwave reaches further than the old 1.5 m roll radius, and
## bystanders are hurled rather than bowled over.
func test_lightning_neighbours_are_lifted_not_just_rolled() -> void:
	var w: Dictionary = _make_world_with_buildings()
	w.unit_manager.spawn_unit(SHAMAN_SCENE, 0, Vector3(30, 0, 30))
	var victim: Unit = w.unit_manager.spawn_unit(SHAMAN_SCENE, 1, Vector3(40, 0, 30))
	var far: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1, Vector3(42.2, 0, 30))
	var spell: LightningSpell = LightningSpell.new()
	check(spell.execute(w.tribe0, Vector3(40, 0, 30), w.ctx), "lightning strikes")
	check(far.state == Unit.State.THROWN,
		"a bystander at 2.2 m is hurled (the old 1.5 m radius missed it)")
	check(victim.state == Unit.State.DEAD, "the victim itself dies")
	_free_world_with_buildings(w)


## Once the incantation is running, only death or a tornado breaks it. Damage
## still lands — she is immune to the INTERRUPT, not to the hit.
func test_casting_shaman_is_interrupt_immune() -> void:
	var w: Dictionary = _make_world()
	w.tribe0.set_spells(Spell.create_default_set())
	var shaman: Shaman = w.unit_manager.spawn_unit(SHAMAN_SCENE, 0, Vector3(40, 5, 40))
	var spell: Spell = w.tribe0.get_spell(&"fireball")
	check(spell != null, "the tribe knows the fireball")
	spell.charges = 1
	check(shaman.order_cast(spell, Vector3(41, 5, 40), w.ctx), "cast ordered")
	shaman.tick(0.05)   # in range: the wind-up starts
	check(shaman.cast_locked(), "the incantation is running")
	var hp0: int = shaman.health
	shaman.apply_knockback(Vector3(1, 0, 0))
	check(shaman._knockback_remaining == Vector3.ZERO, "no shove moves her")
	shaman.start_roll(Vector3(1, 0, 0))
	check(shaman.state == Unit.State.CAST, "no knock-over topples her")
	shaman.apply_lift(Vector3(1, 0, 0), 9.0, 9.0)
	check(shaman.state == Unit.State.CAST, "no fireball lifts her")
	shaman.take_damage(30)
	check(shaman.health == hp0 - 30, "...but the damage lands all the same")
	check(shaman.state == Unit.State.CAST, "and she keeps casting")
	# The tornado is the one exception (besides death).
	shaman.throw_airborne(Vector3.UP * 6.0, 0, true)
	check(shaman.state == Unit.State.THROWN, "a tornado DOES rip her out of it")
	_free_world(w)


## While she is still WALKING into range the wind-up has not begun — there she
## is an ordinary unit and can be knocked about.
func test_shaman_walking_into_range_is_not_immune() -> void:
	var w: Dictionary = _make_world()
	w.tribe0.set_spells(Spell.create_default_set())
	var shaman: Shaman = w.unit_manager.spawn_unit(SHAMAN_SCENE, 0, Vector3(20, 5, 20))
	var spell: Spell = w.tribe0.get_spell(&"fireball")
	check(spell != null, "the tribe knows the fireball")
	spell.charges = 1
	check(shaman.order_cast(spell, Vector3(60, 5, 60), w.ctx), "cast ordered far away")
	check(not shaman.cast_locked(), "no incantation while she is still walking")
	shaman.apply_lift(Vector3(1, 0, 0), 5.0, 6.0)
	check(shaman.state == Unit.State.THROWN, "she can be hurled on the way there")
	_free_world(w)


## At the ceiling the push that no longer fits upward is redirected SIDEWAYS
## instead of being discarded (user spec).
func test_lift_at_the_ceiling_pushes_sideways() -> void:
	var w: Dictionary = _make_world()
	var victim: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1, Vector3(40, 5, 40))
	victim.max_health = 100000
	victim.health = 100000
	# Park it right under the ceiling: no vertical budget left at all.
	victim.throw_airborne(Vector3.UP * 0.1)
	victim.position.y = w.td.get_height(40.0, 40.0) + Balance.LIFT_MAX_HEIGHT
	var h0: float = Vector2(victim._throw_velocity.x, victim._throw_velocity.z).length()
	var vy0: float = victim._throw_velocity.y
	victim.apply_lift(Vector3(1, 0, 0), Balance.FIREBALL_PUSH_SPEED,
		Balance.FIREBALL_LIFT_SPEED)
	var h1: float = Vector2(victim._throw_velocity.x, victim._throw_velocity.z).length()
	check(victim._throw_velocity.y <= vy0 + 0.001, "nothing was added upward")
	check(h1 > h0 + Balance.FIREBALL_PUSH_SPEED * Balance.LIFT_AIRBORNE_PUSH_FACTOR,
		"the leftover went into the sideways push (%.2f -> %.2f m/s)" % [h0, h1])
	_free_world(w)


func test_lightning_lift_stronger_than_fireball() -> void:
	check(Balance.LIGHTNING_PUSH_SPEED > Balance.FIREBALL_PUSH_SPEED,
		"the bolt shoves harder than a fireball")
	check(Balance.LIGHTNING_LIFT_SPEED > Balance.FIREBALL_LIFT_SPEED,
		"...and lifts higher")


## Exhaustive on the pure decision function plus the balance invariant: the
## lift chance was carved OUT of the old roll chance, the sum is unchanged.
##
## CAREFUL (phase 10i, part 4): this pins the BASE constants only. At RUNTIME the
## sum is deliberately NOT invariant any more — Fireball.lift_chance_for_health()
## scales the lift chance up as the target's health drops (4 % -> 12 %), which
## shrinks the plain-shove share. That is the intended effect, not a bug to
## "repair" by making the numbers add up again.
func test_firewarrior_fireball_outcome_split() -> void:
	check_near(Balance.FW_FIREBALL_LIFT_CHANCE + Balance.FW_FIREBALL_ROLL_CHANCE, 0.10,
		"standing target: lift + roll still add up to the old 10 %")
	check_near(Balance.FW_FIREBALL_LIFT_CHANCE_ROLLING
		+ Balance.FW_FIREBALL_ROLL_CHANCE_ROLLING, 0.40,
		"tumbling target: still the old 40 %")
	var lift: float = Balance.FW_FIREBALL_LIFT_CHANCE
	var roll: float = Balance.FW_FIREBALL_ROLL_CHANCE
	check(Fireball.impact_outcome(0.0, lift, roll) == Fireball.OUTCOME_LIFT,
		"the bottom slice lifts")
	check(Fireball.impact_outcome(lift - 0.001, lift, roll) == Fireball.OUTCOME_LIFT,
		"...right up to its edge")
	check(Fireball.impact_outcome(lift, lift, roll) == Fireball.OUTCOME_ROLL,
		"the next slice rolls")
	check(Fireball.impact_outcome(lift + roll - 0.001, lift, roll) == Fireball.OUTCOME_ROLL,
		"...right up to its edge")
	check(Fireball.impact_outcome(lift + roll, lift, roll) == Fireball.OUTCOME_PUSH,
		"everything above is a plain shove")
	check(Fireball.impact_outcome(0.999, lift, roll) == Fireball.OUTCOME_PUSH,
		"...including the top of the range")
	check(Fireball.impact_outcome(0.0, 0.0, 0.0) == Fireball.OUTCOME_PUSH,
		"with both chances at zero every hit is a shove")


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


## Regression: a unit ignited while tumbling (start_panic refuses THROWN/ROLL)
## used to finish its roll and then burn standing around — it could even keep
## fighting. Burning must ALWAYS re-enter panic once the unit is on its feet.
func test_ignited_while_rolling_panics_after_the_tumble() -> void:
	var w: Dictionary = _make_world()
	var brave: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1, Vector3(40, 5, 40))
	brave.start_roll(Vector3(1, 0, 0), Unit.MINI_ROLL_DURATION)
	brave.ignite(Vector3(41, 5, 40))
	check(brave.is_burning(), "the rolling brave is alight")
	check(brave.state == Unit.State.ROLL, "the tumble keeps running (no panic mid-roll)")
	var ticks: int = 0
	while brave.state == Unit.State.ROLL and ticks < 100:
		brave.tick(0.1)
		ticks += 1
	# _tick_burning runs before the state tick, so the re-assert lands on the
	# first full tick after the tumble ended.
	brave.tick(0.1)
	check(brave.is_burning(), "still burning after the short tumble")
	check(brave.state == Unit.State.PANIC,
		"back on its feet, the burning brave re-enters panic")
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


## Buildings are wrecked by ACTUAL lava contact now (Building.add_lava_contact
## via the surges — one stage per full 5 s of contact), not by a flat zone
## cadence. This is the GUARD for the phase-10c wave cadence: raise
## VOLCANO_SURGE_INTERVAL past the contact grace window and the volcano's
## building damage silently disappears (derivation in plans/10c).
func test_volcano_lava_contact_wrecks_buildings() -> void:
	var w: Dictionary = _make_world_with_buildings()
	var hut: Building = w.bm.place(HUT_SCENE_T, w.tribe1, Vector2i(50, 50), 0, true)
	var zone: VolcanoZone = VolcanoZone.new()
	zone.setup(0, hut.center_world(), w.unit_manager, w.td, w.bm)
	w.unit_manager.register_projectile(zone)
	# Eruptions start at 3 s; by 7 s only the first wave has been lying on the
	# hut for ~4 s — below the 5 s threshold.
	for i in range(70):
		w.unit_manager.tick(0.1)
	check(hut.destruction_stage() == 0, "no stage below 5 s of lava contact")
	for i in range(25):
		w.unit_manager.tick(0.1)   # the second wave pushes the contact past 5 s
	check(hut.destruction_stage() == 1, "+1 stage after 5 s of accumulated lava contact")
	_free_world_with_buildings(w)


## Only SUSTAINED contact wrecks: a break longer than the grace window voids
## the accumulated contact time (Building.tick).
func test_building_lava_contact_grace_resets() -> void:
	var w: Dictionary = _make_world_with_buildings()
	var hut: Building = w.bm.place(HUT_SCENE_T, w.tribe1, Vector2i(50, 50), 0, true)
	for i in range(20):
		hut.add_lava_contact(0.2)   # 4 s of contact
	check(hut.destruction_stage() == 0, "4 s of contact stay below the 5 s threshold")
	for i in range(12):
		hut.tick(0.1)   # 1.2 s without lava > grace window: accumulator voids
	for i in range(24):
		hut.add_lava_contact(0.2)   # 4.8 s of FRESH contact
	check(hut.destruction_stage() == 0, "the contact break voided the earlier 4 s")
	hut.add_lava_contact(0.2)
	hut.add_lava_contact(0.2)   # crosses 5 s of unbroken contact (float-safe)
	check(hut.destruction_stage() == 1, "5 s of unbroken contact -> +1 stage")
	_free_world_with_buildings(w)


## The catapult puddle after a building hit runs with damage_buildings off —
## such a surge must never stage buildings, an ordinary one does.
func test_lava_surge_building_damage_flag() -> void:
	var w: Dictionary = _make_world_with_buildings()
	var hut: Building = w.bm.place(HUT_SCENE_T, w.tribe1, Vector2i(50, 50), 0, true)
	# Two back-to-back non-wrecking surges: ~6.8 s of molten contact, no stage.
	for round in range(2):
		var surge: LavaSurge = LavaSurge.new()
		surge.setup(hut.center_world(), w.unit_manager, w.td, 6.0, w.bm)
		surge.damage_buildings = false
		for i in range(54):
			surge.tick(0.1)
		surge.free()
	check(hut.destruction_stage() == 0, "a non-wrecking surge never stages buildings")
	# The same two surges with wrecking on: the contact crosses 5 s -> stage 1.
	for round in range(2):
		var surge: LavaSurge = LavaSurge.new()
		surge.setup(hut.center_world(), w.unit_manager, w.td, 6.0, w.bm)
		for i in range(54):
			surge.tick(0.1)
		surge.free()
	check(hut.destruction_stage() == 1, "wrecking surges stage after 5 s of contact")
	_free_world_with_buildings(w)


## Standing IN the crater is lethal between two waves as well — the zone keeps
## its own continuous ignition loop, but since phase 10c it only covers the
## vent (CRATER_REACH); the flanks belong to the real, terrain-following lava.
## Ticked alone (its spawned surges never tick), so the burn can only come
## from the zone's own ignition loop.
func test_volcano_zone_ignites_units_in_the_crater_only() -> void:
	var w: Dictionary = _make_world_with_buildings()
	var in_crater: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1, Vector3(42.5, 5, 40))
	var on_flank: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE_T, 1, Vector3(46.5, 5, 40))
	check(not in_crater.is_burning() and not on_flank.is_burning(),
		"victims start unburnt")
	var zone: VolcanoZone = VolcanoZone.new()
	zone.setup(0, Vector3(40, 5, 40), w.unit_manager, w.td, w.bm)
	for i in range(32):
		zone.tick(0.1)   # past SURGE_START (3 s): eruption phase
	check(in_crater.is_burning(),
		"the erupting zone itself ignites units in the crater")
	check(not on_flank.is_burning(),
		"...but no longer torches the whole flank on its own (phase 10c)")
	zone.free()
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
	check(victim._drowning, "the flood death is an animated drowning (phase 10a)")
	check(dry.state != Unit.State.DEAD, "distant follower survives")
	_free_world_with_buildings(w)


# --- Kartenausdehnung: Wirbel auf den 256er-Karten (Nutzerreport) --------------------

## Flat TerrainData of an arbitrary size — the wandering spell effects clamp
## themselves to the map, and the 256er maps (Seenland/Bergpass) are exactly
## where the DEFAULT-size constant was the wrong bound.
func _flat_terrain_sized(cells: int, h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new(cells)
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


## Phase 10j: der Clamp ist radial (Scheibe) statt rechteckig. Er folgt weiter der
## KARTENGROESSE — genau der Fehler, der Tornados auf 256er Karten an die 127-Linie
## nagelte (Nutzerreport: Tornados am See).
func test_clamp_into_world_follows_the_map_size() -> void:
	var small: TerrainData = _flat_terrain_sized(128)
	var big: TerrainData = _flat_terrain_sized(256)
	# Ein Punkt weit ausserhalb landet auf dem Scheibenrand, nicht in der Mitte.
	var p_small: Vector2 = TerrainData.clamp_into_world(small, 400.0, 64.0)
	check(is_equal_approx(p_small.x, 126.5) and is_equal_approx(p_small.y, 64.0),
		"128er Karte: radial auf 62,5 m um die Mitte geklemmt")
	var p_big: Vector2 = TerrainData.clamp_into_world(big, 400.0, 128.0)
	check(is_equal_approx(p_big.x, 254.5) and is_equal_approx(p_big.y, 128.0),
		"256er Karte: eigene Grenze (vorher fest 127)")
	var p_null: Vector2 = TerrainData.clamp_into_world(null, 400.0, 64.0)
	check(is_equal_approx(p_null.x, 126.5),
		"ohne Terrain: Rückfall auf die Standardgröße")
	# Innerhalb der Scheibe bleibt der Punkt unangetastet.
	var inside: Vector2 = TerrainData.clamp_into_world(small, 70.0, 60.0)
	check(is_equal_approx(inside.x, 70.0) and is_equal_approx(inside.y, 60.0),
		"Punkt in der Scheibe wird nicht verschoben")
	# Die Ecke ist Void und wird radial hereingezogen.
	var corner: Vector2 = TerrainData.clamp_into_world(small, 127.0, 127.0)
	check(Vector2(corner.x - 64.0, corner.y - 64.0).length() <= 62.6,
		"Kartenecke liegt im Void und wird auf die Scheibe geklemmt")


func test_tornado_does_not_teleport_on_a_large_map() -> void:
	var td: TerrainData = _flat_terrain_sized(256)
	# Past the OLD hard-coded 127-line: on Seenland the lake is centred at
	# (128, 128), so this is a perfectly normal "cast at the lake" point.
	var at: Vector3 = Vector3(150.0, 5.0, 150.0)
	var vortex: TornadoVortex = TornadoVortex.new()
	vortex.setup(0, at, null, td, null)
	check(vortex.position.x > 140.0 and vortex.position.z > 140.0,
		"Wirbel entsteht am Zielpunkt, nicht an der Kartenmitte")
	var last: Vector3 = vortex.position
	var max_step: float = 0.0
	for i in range(120):   # 4 s at 30 Hz — well past IDLE_TIME
		vortex.tick(1.0 / 30.0)
		max_step = maxf(max_step, Vector2(vortex.position.x - last.x,
			vortex.position.z - last.z).length())
		last = vortex.position
	# MAX_SPEED 2.0 m/s at 1/30 s is ~0.07 m per tick; the bug jumped ~32 m in one.
	check(max_step < 0.5, "kein Sprung pro Tick (war ~32 m an der 127-Linie)")
	check(vortex.position.x > 127.5 or vortex.position.z > 127.5,
		"Wirbel bleibt jenseits der alten 127-Grenze frei beweglich")
	vortex.free()


func test_tornado_spawn_is_clamped_into_the_map() -> void:
	var td: TerrainData = _flat_terrain_sized(128)
	var vortex: TornadoVortex = TornadoVortex.new()
	vortex.setup(0, Vector3(400.0, 5.0, -50.0), null, td, null)
	check(vortex.position.x <= 127.0 and vortex.position.x >= 1.0,
		"x beim Spawn in die Karte geklemmt")
	check(vortex.position.z <= 127.0 and vortex.position.z >= 1.0,
		"z beim Spawn in die Karte geklemmt")
	var before: Vector3 = vortex.position
	for i in range(60):
		vortex.tick(1.0 / 30.0)
	check(Vector2(vortex.position.x - before.x, vortex.position.z - before.z).length() < 5.0,
		"kein verzögerter Sprung nach IDLE_TIME")
	vortex.free()


func test_center_cell_follows_the_map_size() -> void:
	check(TerrainData.center_cell(_flat_terrain_sized(128)) == Vector2i(64, 64),
		"128er Karte: Mitte (64, 64)")
	check(TerrainData.center_cell(_flat_terrain_sized(256)) == Vector2i(128, 128),
		"256er Karte: Mitte (128, 128) - vorher fest (64, 64)")
	check(TerrainData.center_cell(null) == Vector2i(64, 64),
		"ohne Terrain: Rueckfall auf die Standardgroesse")
