extends TestBase

## Zauber 15 "Genesisgolem beschwören" (Nutzervorgabe 2026-11-17). Diese Datei
## nagelt die Vorgabe fest (Werte in Balance.GENESIS_GOLEM_*): 5 m und 1000 LP beim
## Erscheinen, keine Lebenszeit; Wachstum nur durch eigene Braves (geteilt), 9 Stufen
## zu 10/12/14/17/20/23/27/31/36 Braves, je +5 m, +40 LP, +2 LP/s; Schaden des
## frischen Daemonengolems, Reichweite des frischen Golems, Anstieg 2/3 des
## Daemonengolems; ab Stufe 5 Kollision, Einebnen, Luftschlag; Baeume mit einem
## Schlag faellen, Holz +50 %, Braves holen es wie von einem Stapel; 30 s unberuehrt
## -> 15 Holz/s fuer 2 %/s Wachstum bis 200 m (+2 LP und +0,15 LP/s je Meter); ab
## Stufe 8 Holz durch Trampeln. Kills bringen kein Wachstum.

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const GOLEM_SCENE: PackedScene = preload("res://scenes/units/golem.tscn")
const DEMON_SCENE: PackedScene = preload("res://scenes/units/demon_golem.tscn")
const GENESIS_SCENE: PackedScene = preload("res://scenes/units/genesis_golem.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")

const TICK: float = 0.1


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


func _make_world() -> Dictionary:
	var td: TerrainData = _flat_terrain()
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
	tc.spell_context = ctx
	t0.set_spells(Spell.create_player_set())
	t1.set_spells(Spell.create_default_set())
	return {"td": td, "nav": nav, "t0": t0, "t1": t1, "um": um, "bm": bm,
		"tm": tm, "wpm": wpm, "commands": tc, "ctx": ctx}


func _free_world(w: Dictionary) -> void:
	w.commands.free()
	w.tm.free()
	w.wpm.free()
	w.bm.free()
	w.um.free()


func _tick_world(w: Dictionary) -> void:
	w.bm.tick(TICK)
	for u in w.um.units.duplicate():
		if is_instance_valid(u):
			u.tick(TICK)
	w.um.tick(TICK)
	w.wpm.tick(TICK)


func _genesis(w: Dictionary, tribe_id: int, at: Vector3) -> GenesisGolem:
	return w.um.spawn_unit(GENESIS_SCENE, tribe_id, at) as GenesisGolem


func _to_stage(g: GenesisGolem, s: int) -> void:
	g.credit_brave(float(GenesisGolem.braves_for_stage(s)) - g.brave_xp)


# --- Zauber ---------------------------------------------------------------------------

func test_spell_is_the_players_alone_and_costs_what_the_demon_golem_costs() -> void:
	var w: Dictionary = _make_world()
	var spell: Spell = w.t0.get_spell(&"genesis_golem")
	check(spell != null and spell is GenesisGolemSpell, "the player's set carries the Genesis golem")
	check(w.t1.get_spell(&"genesis_golem") == null, "the default set (the AI's) does not")
	var demon: Spell = w.t0.get_spell(&"demon_golem")
	check(is_equal_approx(spell.charge_cost, demon.charge_cost)
		and spell.max_charges == demon.max_charges
		and is_equal_approx(spell.cast_range, demon.cast_range),
		"costs, charges and range of the demon golem")
	spell.charges = 1
	check(spell.cast(w.t0, Vector3(50, 5, 50), w.ctx), "the cast succeeds")
	var found: GenesisGolem = null
	for u in w.um.units:
		if u is GenesisGolem:
			found = u
	check(found != null and found.tribe_id == 0, "a Genesis golem of the caster stands there")
	if found != null:
		check_near(found.height_m(), 5.0, "5 m tall")
		check(found.health == 1000 and found.max_health == 1000, "1000 health")
		check(not found.has_lifetime(), "no lifetime")
		check(found.unit_kind() == &"golem" and found.display_name() == "Genesisgolem",
			"a golem by kind, the Genesis golem by name")
	_free_world(w)


func test_he_has_his_own_model_in_the_golems_build() -> void:
	var w: Dictionary = _make_world()
	var g: GenesisGolem = _genesis(w, 0, Vector3(50, 5, 50))
	check(g.model_file() == "models/units/golem_genesis.glb", "his own model")
	check(g.model_scale().is_equal_approx(Vector3(Golem.MODEL_SCALE, Golem.MODEL_SCALE_Y, Golem.MODEL_SCALE)),
		"scaled like the golem: 10 % lower than wide")
	check_near(g.walk_clip_speed(), 2.614 * Golem.MODEL_SCALE, "the walk clip's stride is his model's")
	_free_world(w)


# --- Stufen aus Braves ----------------------------------------------------------------

func test_stages_cost_the_listed_braves() -> void:
	var want: Array[int] = [0, 10, 22, 36, 53, 73, 96, 123, 154]
	for s in range(want.size()):
		check(GenesisGolem.braves_for_stage(s) == want[s],
			"stage %d after %d braves (%d)" % [s, want[s], GenesisGolem.braves_for_stage(s)])
	check(GenesisGolem.max_stage() == 8, "eight stages")
	check(GenesisGolem.stage_for_xp(9.99) == 0 and GenesisGolem.stage_for_xp(10.0) == 1,
		"the tenth brave brings stage 1")
	check(GenesisGolem.stage_for_xp(1000.0) == 8, "no stage beyond 8")


func test_every_stage_adds_three_and_a_half_metres_forty_health_two_regen() -> void:
	var w: Dictionary = _make_world()
	var g: GenesisGolem = _genesis(w, 0, Vector3(50, 5, 50))
	for i in range(10):
		g.credit_brave(1.0)
	check(g.stage == 1, "stage 1 after ten braves")
	check_near(g.height_m(), 8.5, "8,5 m")
	check(g.max_health == 1040 and g.health == 1040, "1040 health (%d/%d)" % [g.health, g.max_health])
	check_near(g.regen_per_second(), 2.0, "2 health per second")
	_to_stage(g, 8)
	check(g.stage == 8, "stage 8")
	check_near(g.height_m(), 33.0, "33 m at the last stage")
	check(g.max_health == 1320, "1320 health")
	check_near(g.regen_per_second(), 16.0, "16 health per second")
	g.credit_brave(500.0)
	check_near(g.height_m(), 33.0, "the stages end at 33 m")
	_free_world(w)


func test_braves_are_shared_between_the_tribes_genesis_golems() -> void:
	var w: Dictionary = _make_world()
	var a: GenesisGolem = _genesis(w, 0, Vector3(40, 5, 50))
	var b: GenesisGolem = _genesis(w, 0, Vector3(70, 5, 50))
	var foe: GenesisGolem = _genesis(w, 1, Vector3(100, 5, 50))
	for i in range(20):
		GenesisGolem.credit_brave_to_tribe(w.t0)
	check_near(a.brave_xp, 10.0, "each of two gets half (%.2f)" % a.brave_xp)
	check(a.stage == 1 and b.stage == 1, "twenty braves: both on stage 1")
	check(foe.brave_xp == 0.0, "another tribe's braves do not count")
	_free_world(w)


func test_a_brave_from_a_hut_feeds_him() -> void:
	var w: Dictionary = _make_world()
	var g: GenesisGolem = _genesis(w, 0, Vector3(80, 5, 80))
	var hut: Hut = w.bm.place(HUT_SCENE, w.t0, Vector2i(48, 48), 0, true) as Hut
	check(hut != null, "a hut stands")
	if hut != null:
		hut._spawn_brave()
		check_near(g.brave_xp, 1.0, "the hut's brave is one point of experience")
	_free_world(w)


func test_kills_do_not_make_him_grow() -> void:
	var w: Dictionary = _make_world()
	var g: GenesisGolem = _genesis(w, 0, Vector3(50, 5, 50))
	g.health = 900
	for i in range(60):
		g._credit_kill()
	check(g.kills == 60, "kills are counted")
	check(g.stage == 0 and is_equal_approx(g.height_m(), 5.0), "but bring no growth")
	check(g.health == 900 and g.max_health == 1000, "and no health")
	_free_world(w)


# --- Werte ----------------------------------------------------------------------------

func test_start_values_damage_of_the_demon_reach_of_the_golem() -> void:
	var w: Dictionary = _make_world()
	var g: GenesisGolem = _genesis(w, 0, Vector3(40, 5, 50))
	var golem: Golem = w.um.spawn_unit(GOLEM_SCENE, 0, Vector3(60, 5, 50)) as Golem
	var demon: DemonGolem = w.um.spawn_unit(DEMON_SCENE, 0, Vector3(80, 5, 50)) as DemonGolem
	for kind in [Golem.ATTACK_SLAM, Golem.ATTACK_KICK, Golem.ATTACK_DRUM]:
		check_near(g.damage_exact(kind), demon.damage_exact(kind),
			"%s: the freshly summoned demon golem's damage" % kind)
	check_near(g.reach(), golem.reach(), "the fresh golem's reach")
	check_near(g.slam_radius(), golem.slam_radius(), "the fresh golem's slam circle")
	check_near(g.reach_factor(), golem.reach_factor(), "and lane width")
	check(g.max_targets() == golem.max_targets(), "the fresh golem's targets (%d)" % g.max_targets())
	check(g.trample_damage() == 1, "trample damage 1 (4,7 m / 3,2)")
	_free_world(w)


func test_attack_values_grow_two_thirds_as_fast_as_the_demons() -> void:
	var w: Dictionary = _make_world()
	var g: GenesisGolem = _genesis(w, 0, Vector3(50, 5, 50))
	_to_stage(g, 8)   # 28 m grown -> 18,67 m count for the attack values
	# Per metre as before the demon golem took 3 m a step (his gain per step / 3).
	var m: float = 28.0 * 2.0 / 3.0
	check_near(g.damage_exact(Golem.ATTACK_SLAM), 15.5 + 0.75 * m, "slam +0,5 a metre")
	check_near(g.damage_exact(Golem.ATTACK_KICK), 24.5 + 0.8 * m, "kick +0,53 a metre")
	check_near(g.damage_exact(Golem.ATTACK_DRUM), 24.0 + 1.2 * m, "drum +0,8 a metre")
	check(g.max_targets() == 5 + 18, "two thirds of a target a metre (%d)" % g.max_targets())
	var cf: float = 1.0 + 28.0 / Balance.GOLEM_HEIGHT * 2.0 / 3.0
	check_near(g.combat_factor(), cf, "attack size factor %.2f" % cf)
	check_near(g.reach(), Balance.GOLEM_REACH * Golem.limb_factor_for(cf), "reach from it")
	check(g.reach() < Balance.GOLEM_REACH * Golem.limb_factor_for(33.0 / Balance.GOLEM_HEIGHT),
		"less than a 33-m demon golem's")
	check(g.trample_damage() == int(round(Balance.GOLEM_HEIGHT * cf / 3.2)) and g.trample_damage() == 7,
		"trample damage from the attack size (%d)" % g.trample_damage())
	check_near(g.trample_radius(), Balance.GOLEM_BODY_HALF_WIDTH * 33.0 / Balance.GOLEM_HEIGHT,
		"the body itself is 33 m")
	_free_world(w)


func test_from_stage_four_collision_levelling_and_air_strike() -> void:
	var w: Dictionary = _make_world()
	var g: GenesisGolem = _genesis(w, 0, Vector3(50, 5, 50))
	_to_stage(g, 3)
	check(not g.tramples() and not g.ignores_unit_collision() and not g.flattens()
		and not g.can_strike_air(), "stage 3: none of it")
	_to_stage(g, 4)
	check(g.tramples() and g.ignores_unit_collision() and g.flattens() and g.can_strike_air(),
		"stage 4: walks through units, tramples, levels the ground, strikes airships")
	check(not g.is_giant() and not g.walks_straight(), "but not the rest of the giant's package")
	check(not g.is_full_size(), "never hardened")
	_free_world(w)


# --- Holz ------------------------------------------------------------------------------

func test_harvest_yield_is_half_as_much_again_rounded_down() -> void:
	check(GenesisGolem.harvest_yield(4) == 6, "4 -> 6")
	check(GenesisGolem.harvest_yield(3) == 4, "3 -> 4")
	check(GenesisGolem.harvest_yield(1) == 1, "1 -> 1")
	check(GenesisGolem.harvest_yield(0) == 0, "a sapling -> 0")


func test_right_click_on_a_tree_fells_it_with_one_blow() -> void:
	var w: Dictionary = _make_world()
	var g: GenesisGolem = _genesis(w, 0, Vector3(40.5, 5, 40.5))
	var tree: TreeResource = w.tm.spawn_tree(Vector2i(50, 40), TreeResource.MAX_STAGE)
	var yield_wood: int = tree.wood_yield()
	check(w.commands.order_chop([g] as Array[Unit], tree) == 1, "the order is taken")
	for i in range(200):
		_tick_world(w)
		if not is_instance_valid(tree) or tree.felled_flag:
			break
	check(not is_instance_valid(tree) or tree.felled_flag, "the tree is down")
	check(g.trees_felled == 1, "one tree felled")
	check(g.total_wood() == GenesisGolem.harvest_yield(yield_wood),
		"he holds its wood plus half (%d)" % g.total_wood())
	check(not g.is_harvesting(), "and the order is done")
	_free_world(w)


func test_area_order_fells_every_tree_in_it() -> void:
	var w: Dictionary = _make_world()
	var g: GenesisGolem = _genesis(w, 0, Vector3(40.5, 5, 40.5))
	for x in [46, 49, 52]:
		w.tm.spawn_tree(Vector2i(x, 46), TreeResource.MAX_STAGE)
	var outside: TreeResource = w.tm.spawn_tree(Vector2i(70, 70), TreeResource.MAX_STAGE)
	check(w.commands.order_chop_area([g] as Array[Unit], Rect2(44, 44, 12, 6)) == 1,
		"the Genesis golem takes the B order")
	for i in range(600):
		_tick_world(w)
		if not g.is_harvesting():
			break
	check(g.trees_felled == 3, "all three felled (%d)" % g.trees_felled)
	check(is_instance_valid(outside) and not outside.felled_flag, "the tree outside stands")
	check(g.total_wood() == 3 * GenesisGolem.harvest_yield(4), "18 wood")
	_free_world(w)


func test_area_order_fells_a_cluster_with_one_ground_blow() -> void:
	var w: Dictionary = _make_world()
	var g: GenesisGolem = _genesis(w, 0, Vector3(40.5, 5, 46.5))
	for cell in [Vector2i(46, 46), Vector2i(47, 46), Vector2i(46, 47), Vector2i(47, 47), Vector2i(48, 46)]:
		w.tm.spawn_tree(cell, TreeResource.MAX_STAGE)
	check(w.commands.order_chop_area([g] as Array[Unit], Rect2(44, 44, 8, 6)) == 1, "the B order is taken")
	var most_at_once: int = 0
	var crouched: bool = false
	var kinds: Dictionary = {}
	for i in range(900):
		var before: int = g.trees_felled
		_tick_world(w)
		most_at_once = maxi(most_at_once, g.trees_felled - before)
		crouched = crouched or g.stance == Golem.STANCE_CROUCH
		if g._pending_attack != &"":
			kinds[g._pending_attack] = true
		if not g.is_harvesting():
			break
	check(g.trees_felled == 5, "all five felled (%d)" % g.trees_felled)
	check(most_at_once >= 2, "several trees fall with one blow (%d at once)" % most_at_once)
	check(crouched and (kinds.has(Golem.ATTACK_SLAM) or kinds.has(Golem.ATTACK_DRUM)),
		"he bends down for a ground blow (%s)" % str(kinds.keys()))
	check(g.total_wood() == 5 * GenesisGolem.harvest_yield(4), "30 wood")
	_free_world(w)


func test_a_single_tree_order_keeps_the_plain_blow() -> void:
	var w: Dictionary = _make_world()
	var g: GenesisGolem = _genesis(w, 0, Vector3(40.5, 5, 46.5))
	var tree: TreeResource = w.tm.spawn_tree(Vector2i(46, 46), TreeResource.MAX_STAGE)
	var beside: TreeResource = w.tm.spawn_tree(Vector2i(47, 46), TreeResource.MAX_STAGE)
	check(w.commands.order_chop([g] as Array[Unit], tree) == 1, "the order is taken")
	var crouched: bool = false
	for i in range(400):
		_tick_world(w)
		crouched = crouched or g.stance == Golem.STANCE_CROUCH
		if not g.is_harvesting():
			break
	check(g.trees_felled == 1 and not crouched, "one tree, with a kick from the stand")
	check(is_instance_valid(beside) and not beside.felled_flag, "the tree beside it stands")
	_free_world(w)


func test_his_aggro_radius_is_half_the_other_golems() -> void:
	var w: Dictionary = _make_world()
	var g: GenesisGolem = _genesis(w, 0, Vector3(50, 5, 50))
	check_near(g.aggro_radius(), 0.5 * Golem.AGGRO_RADIUS * g.size_factor(), "half at the start (%.2f m)" % g.aggro_radius())
	_to_stage(g, 9)
	check_near(g.aggro_radius(), 0.5 * minf(Golem.AGGRO_RADIUS * g.size_factor(), Balance.GOLEM_AGGRO_MAX),
		"and at 41 m (%.2f m)" % g.aggro_radius())
	_free_world(w)


func test_a_building_he_brings_down_gives_half_its_cost_in_wood() -> void:
	var w: Dictionary = _make_world()
	var g: GenesisGolem = _genesis(w, 0, Vector3(50, 5, 50))
	var hut: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(52, 52), 0, true)
	var cost: int = hut.wood_cost
	check(GenesisGolem.building_wood(hut) == cost / 2, "half the cost, rounded down (%d of %d)" % [cost / 2, cost])
	g._strike_building(hut, 1)
	check(g.total_wood() == 0, "a blow that leaves it standing brings nothing")
	for i in range(6):
		if is_instance_valid(hut) and hut.health > 0:
			g._strike_building(hut, 1)
	check(not is_instance_valid(hut) or hut.health <= 0, "the hut is down")
	check(g.total_wood() == cost / 2, "and half its cost is his (%d)" % g.total_wood())
	check(g._wood_idle == 0.0, "new wood restarts the idle clock")
	_free_world(w)


func test_a_move_order_ends_the_harvest() -> void:
	var w: Dictionary = _make_world()
	var g: GenesisGolem = _genesis(w, 0, Vector3(40.5, 5, 40.5))
	var tree: TreeResource = w.tm.spawn_tree(Vector2i(60, 40), TreeResource.MAX_STAGE)
	g.order_harvest_tree(tree)
	_tick_world(w)
	g.order_move(Vector3(30, 5, 30))
	check(not g.is_harvesting(), "a move order from outside ends it")
	_free_world(w)


func test_braves_take_his_wood_like_from_a_pile() -> void:
	var w: Dictionary = _make_world()
	var g: GenesisGolem = _genesis(w, 0, Vector3(50, 5, 50))
	g.add_wood(12)
	check(g.total_wood() == 12, "12 wood")
	var pile: WoodPile = g._wood_pile
	check(pile != null and w.wpm.piles.has(pile), "a pile lies at his feet")
	check(pile != null and not pile.visible, "but it is not shown: his wood is a number only")
	if pile != null:
		check(pile.amount == WoodPile.MAX_AMOUNT and g.wood == 12 - WoodPile.MAX_AMOUNT,
			"the pile is full, the rest he carries")
		check(g._flat_dist(pile.position, g.position) > g.trample_radius(),
			"in front of his body, not under it")
		g._wood_idle = 20.0
		check(w.wpm.take_from_pile(pile, 3) == 3, "a brave takes three")
		g._tick_wood_store()
		check(g._wood_idle == 0.0, "taking resets the idle clock")
		check(g.total_wood() == 9, "9 left")
		check(g._wood_pile.amount == WoodPile.MAX_AMOUNT, "the pile is topped up again")
	_free_world(w)


func test_unused_wood_is_eaten_after_thirty_seconds_for_growth() -> void:
	var w: Dictionary = _make_world()
	var g: GenesisGolem = _genesis(w, 0, Vector3(50, 5, 50))
	_to_stage(g, 8)
	g.add_wood(150)
	for i in range(int(29.5 / TICK)):
		g._tick_wood_growth(TICK)
	check(g.total_wood() == 150 and g.wood_growth_m == 0.0, "nothing eaten for 30 s")
	for i in range(int(10.5 / TICK)):
		g._tick_wood_growth(TICK)
	check(g.total_wood() == 0, "then 15 a second: all 150 in 10 s (%d left)" % g.total_wood())
	var want: float = 33.0 * pow(1.02, 10.0)
	check_near(g.height_m(), want, "2 %% a second: %.2f m" % want, 0.05)
	var grown: float = g.wood_growth_m
	check(g.max_health == 1320 + int(floor(3.0 * grown + 0.000001)), "+3 health a metre (%d)" % g.max_health)
	check_near(g.regen_per_second(), 16.0 + 0.15 * grown, "+0,15 regen a metre")
	_free_world(w)


func test_wood_growth_ends_at_one_hundred_metres() -> void:
	var w: Dictionary = _make_world()
	var g: GenesisGolem = _genesis(w, 0, Vector3(50, 5, 50))
	_to_stage(g, 8)
	g.grow_by_wood(100000.0)
	check_near(g.height_m(), 100.0, "100 m at most")
	g.credit_brave(1.0)
	check_near(g.height_m(), 100.0, "and stays there")
	_free_world(w)


func test_from_stage_seven_trampling_fells_trees() -> void:
	var w: Dictionary = _make_world()
	var g: GenesisGolem = _genesis(w, 0, Vector3(50.5, 5, 50.5))
	_to_stage(g, 6)
	var tree: TreeResource = w.tm.spawn_tree(Vector2i(51, 50), TreeResource.MAX_STAGE)
	g._tick_trample_wood(TICK, g.position - Vector3(0.3, 0, 0))
	check(is_instance_valid(tree) and not tree.felled_flag, "stage 6: the tree stands")
	_to_stage(g, 7)
	g._trample_wood_timer = 0.0
	g._tick_trample_wood(TICK, g.position - Vector3(0.3, 0, 0))
	check(not is_instance_valid(tree) or tree.felled_flag, "stage 7: trampled down")
	check(g.total_wood() == GenesisGolem.harvest_yield(4), "and its wood is his (%d)" % g.total_wood())
	_free_world(w)


func test_status_text_names_him_his_stage_and_wood() -> void:
	var w: Dictionary = _make_world()
	var g: GenesisGolem = _genesis(w, 0, Vector3(50, 5, 50))
	g.add_wood(7)
	var text: String = g.status_text()
	check(text.contains("Genesisgolem") and text.contains("Stufe 0/8")
		and text.contains("noch 10 Braves") and text.contains("Holz: 7"), text)
	_free_world(w)


func test_a_real_brave_fetches_wood_from_him() -> void:
	var w: Dictionary = _make_world()
	var g: GenesisGolem = _genesis(w, 0, Vector3(50.5, 5, 50.5))
	g.add_wood(12)
	var brave: Brave = w.um.spawn_unit(BRAVE_SCENE, 0, Vector3(56.5, 5, 50.5)) as Brave
	check(w.commands.order_pickup([brave] as Array[Unit], g._wood_pile) == 1, "the brave takes the job")
	for i in range(150):
		_tick_world(w)
		if brave.carried_wood > 0:
			break
	check(brave.carried_wood > 0, "the brave carries wood from him (%d)" % brave.carried_wood)
	check(g.total_wood() == 12 - brave.carried_wood, "taken from his store (%d left)" % g.total_wood())
	_free_world(w)
