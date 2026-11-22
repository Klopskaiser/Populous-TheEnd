extends TestBase

## KI-Persoenlichkeiten und Zauberwahl (Nutzervorgabe 2026-11-22):
## - drei Persoenlichkeiten (aggressiv = bisheriges Verhalten, Oekonom, Verteidiger),
##   die sich in Bauordnung, Angriffszeitpunkt, Tuermen und Zaubern unterscheiden;
## - die Ladeauswahl haelt einen Alltagsvorrat und spart nebenher auf EINEN grossen
##   Zauber (vorher lud sie nur die billigsten und kam an teure nie heran);
## - die Zauber-Heuristik setzt Hypnose, Supertornado und Erdbeben ein (vorher nie).

const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


func _make_world() -> Dictionary:
	var td: TerrainData = _flat_terrain()
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
	return {"td": td, "nav": nav, "tribes": tribes, "unit_manager": um,
		"building_manager": bm, "tree_manager": tm, "wood_pile_manager": wpm, "commands": tc}


func _free_world(w: Dictionary) -> void:
	w.commands.free()
	w.tree_manager.free()
	w.wood_pile_manager.free()
	w.building_manager.free()
	w.unit_manager.free()


func _make_ai(w: Dictionary, tribe: Tribe, anchor: Vector2i) -> AIController:
	var ai: AIController = AIController.new()
	ai.setup(tribe, w.commands, w.unit_manager, w.building_manager,
		w.tree_manager, w.nav, anchor)
	return ai


func _arm_only(tribe: Tribe, id: StringName) -> void:
	tribe.set_spells(Spell.create_player_set())
	for s in tribe.spells:
		s.charges = 1 if s.id == id else 0


func _pending(tribe: Tribe) -> StringName:
	var shaman = tribe.shaman
	if shaman == null or not is_instance_valid(shaman) \
			or (shaman as Shaman).pending_spell == null:
		return &""
	return (shaman as Shaman).pending_spell.id


func _entry(id: String, cost: float, charges: int = 0, full: bool = false) -> Dictionary:
	return {"id": StringName(id), "cost": cost, "charges": charges, "full": full}


## Base counts of a tribe whose first essentials stand (hut, barracks, rack).
func _base_counts() -> Dictionary:
	return {"hut": 6, "warrior_camp": 1, "wood_depot": 1, "braves": 30,
		"population": 40, "housing_capacity": 200}


# --- Personalities (pure) -----------------------------------------------------------

func test_aggressive_is_the_old_behaviour() -> void:
	var p: AIPersonality = AIPersonality.aggressive()
	check(p.first_wave == AIState.ARMY_ATTACK_SIZE, "first wave as before")
	check(p.wave_growth == AIState.ATTACK_WAVE_GROWTH, "wave growth as before")
	check(p.attack_min_pop == 0, "no population condition")
	check(p.target_huts == AIState.TARGET_HUTS, "same hut target")
	check(p.tower_target(20, false) == Balance.AI_TARGET_WATCHTOWERS
		and p.tower_target(20, true) == Balance.AI_TARGET_WATCHTOWERS_CRAMPED,
		"same tower targets as AIState.target_watchtowers")
	check(AIController.new().personality.kind == AIPersonality.Kind.AGGRESSIVE,
		"a controller without a choice plays aggressive")


func test_personalities_differ_as_specified() -> void:
	var a: AIPersonality = AIPersonality.aggressive()
	var e: AIPersonality = AIPersonality.economic()
	var d: AIPersonality = AIPersonality.defensive()
	check(e.first_wave > a.first_wave and e.attack_min_pop > 0, "the economist attacks later")
	check(e.target_huts > a.target_huts, "and builds many more huts early")
	check(e.target_huts > d.target_huts, "more than the defender (who spreads more slowly)")
	check(d.tower_target(20, false) > e.tower_target(20, false), "the defender builds more towers")
	check(d.tower_target(20, false) > d.tower_target(4, false), "its towers grow with the village")
	check(d.early_workshops and not e.early_workshops, "the defender builds vehicles earlier")
	check(d.settlement_anchors < e.settlement_anchors, "and a more compact village")
	check(not d.spell_raids and a.spell_raids, "the defender keeps its shaman at home")
	check(a.guard_size(50) == 0, "aggressive: its waves are its defence (no home guard)")
	check(e.guard_size(50) >= 6 and d.guard_size(50) > e.guard_size(50),
		"economist and defender keep early defenders at home, the defender more")


func test_random_choices_resolve_to_different_personalities() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var ids: Array[StringName] = AIPersonality.resolve_ids(
		[&"random", &"random", &"random"] as Array[StringName], rng)
	check(ids.size() == 3, "three slots")
	check(ids.has(&"aggressive") and ids.has(&"economic") and ids.has(&"defensive"),
		"three random AIs are one of each (%s)" % str(ids))
	var fixed: Array[StringName] = AIPersonality.resolve_ids(
		[&"economic", &"random"] as Array[StringName], rng)
	check(fixed[0] == &"economic" and fixed[1] != &"economic",
		"a fixed choice stays, the random one avoids it")
	check(AIPersonality.from_id(&"unknown").kind == AIPersonality.Kind.AGGRESSIVE,
		"an unknown id falls back to aggressive")


func test_economist_waits_for_its_population_before_attacking() -> void:
	var snap: Dictionary = AIState.make_snapshot(40, 20, 24, 6, 3, true)
	snap["army_target"] = 24
	snap["attack_min_pop"] = 70
	check(AIState.next_state(AIState.State.TRAIN, snap) == AIState.State.TRAIN,
		"army ready but the village small: keep training")
	snap["population"] = 80
	check(AIState.next_state(AIState.State.TRAIN, snap) == AIState.State.ATTACK,
		"village stands: attack")
	snap["population"] = 40
	snap["army"] = 48
	check(AIState.next_state(AIState.State.TRAIN, snap) == AIState.State.ATTACK,
		"twice the wave marches anyway")


func test_build_order_follows_the_personality() -> void:
	# Economist: after the first six huts and the firewarrior camp, more huts before the temple.
	var c: Dictionary = _base_counts()
	c["firewarrior_camp"] = 1
	c["target_huts"] = 12
	check(AIState.next_building_kind(c) == &"hut", "economist: more huts before the temple")
	c["hut"] = 12
	check(AIState.next_building_kind(c) == &"temple", "then the temple")
	# Defender: a tower right after the firewarrior camp, a catapult shop after its huts.
	var d: Dictionary = _base_counts()
	d["firewarrior_camp"] = 1
	d["target_huts"] = 10
	d["early_towers"] = 1
	d["early_workshops"] = true
	check(AIState.next_building_kind(d) == &"watchtower", "defender: a tower first")
	d["watchtower"] = 1
	check(AIState.next_building_kind(d) == &"hut", "then its remaining huts")
	d["hut"] = 10
	check(AIState.next_building_kind(d) == &"workshop", "then a catapult shop")
	d["workshop"] = 1
	check(AIState.next_building_kind(d) == &"temple", "the temple")
	d["temple"] = 1
	check(AIState.next_building_kind(d) == &"fireram_workshop", "and early fire rams")
	# Aggressive (no personality keys): the old ladder.
	var a: Dictionary = _base_counts()
	check(AIState.next_building_kind(a) == &"firewarrior_camp", "aggressive: as before")


# --- Spell charging (pure) ---------------------------------------------------------------

func test_the_goal_spell_charges_alongside_the_stock() -> void:
	var spells: Array = [
		_entry("fireball", 30.0, 1), _entry("swarm", 100.0, 0),
		_entry("earthquake", 400.0, 0), _entry("volcano", 1600.0, 0),
	]
	var reserve: Dictionary = {&"fireball": 3, &"swarm": 1}
	var goals: Array = [&"earthquake", &"volcano"]
	var plan: Array[StringName] = AIState.spell_charge_plan(spells, 5.0, reserve, goals)
	check(&"fireball" in plan and &"swarm" in plan, "the everyday stock charges")
	check(&"earthquake" in plan, "and the first goal alongside (%s)" % str(plan))
	check(not (&"volcano" in plan), "one goal at a time")
	# Old rule for comparison: cheapest-first never reached the earthquake here.
	check(not (&"earthquake" in AIState.spells_to_charge(spells, 5.0)),
		"the old rule would not have charged it")


func test_goals_rotate_once_charged() -> void:
	var spells: Array = [_entry("earthquake", 400.0, 1), _entry("volcano", 1600.0, 0)]
	check(AIState.spell_goal(spells, [&"earthquake", &"volcano"]) == &"volcano",
		"the earthquake has a charge: save for the volcano next")
	var all: Array = [_entry("earthquake", 400.0, 1), _entry("volcano", 1600.0, 1, true)]
	check(AIState.spell_goal(all, [&"earthquake", &"volcano"]) == &"earthquake",
		"everything has one: top up the first that is not full")
	var full: Array = [_entry("earthquake", 400.0, 2, true)]
	check(AIState.spell_goal(full, [&"earthquake"]) == &"", "all full: no goal")


func test_nothing_is_wasted_when_stock_and_goals_are_full() -> void:
	var spells: Array = [
		_entry("fireball", 30.0, 4, true), _entry("volcano", 1600.0, 1, true),
		_entry("sink", 350.0, 0),
	]
	var plan: Array[StringName] = AIState.spell_charge_plan(spells, 5.0,
		{&"fireball": 3}, [&"volcano"])
	check(plan.size() == 1 and plan[0] == &"sink", "the rest charges (no mana banking): %s" % str(plan))


func test_a_goal_out_of_reach_waits() -> void:
	var spells: Array = [_entry("fireball", 30.0, 0), _entry("volcano", 1600.0, 0)]
	var plan: Array[StringName] = AIState.spell_charge_plan(spells, 1.0,
		{&"fireball": 3}, [&"volcano"])
	check(plan.size() == 1 and plan[0] == &"fireball",
		"at 1 mana/s the volcano does not split the income yet: %s" % str(plan))


# --- Spell heuristic -------------------------------------------------------------

func test_hypnosis_on_a_squad() -> void:
	var w: Dictionary = _make_world()
	var ai_tribe: Tribe = w.tribes[1]
	var ai: AIController = _make_ai(w, ai_tribe, Vector2i(100, 100))
	w.unit_manager.spawn_unit(SHAMAN_SCENE, 1, Vector3(40, 5, 40))
	for i in range(4):
		w.unit_manager.spawn_unit(WARRIOR_SCENE, 0,
			Vector3(47 + 0.7 * float(i % 2), 5, 40 + 0.7 * float(i / 2)))
	_arm_only(ai_tribe, &"hypnosis")
	ai._cast_spells()
	check(_pending(ai_tribe) == &"hypnosis", "four warriors in one square -> hypnosis")
	ai.free()
	_free_world(w)


func test_no_hypnosis_on_a_lone_unit() -> void:
	var w: Dictionary = _make_world()
	var ai_tribe: Tribe = w.tribes[1]
	var ai: AIController = _make_ai(w, ai_tribe, Vector2i(100, 100))
	w.unit_manager.spawn_unit(SHAMAN_SCENE, 1, Vector3(40, 5, 40))
	w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, Vector3(47, 5, 40))
	_arm_only(ai_tribe, &"hypnosis")
	ai._cast_spells()
	check(_pending(ai_tribe) == &"", "one warrior is not worth it")
	ai.free()
	_free_world(w)


func _crowd(w: Dictionary, n: int, at: Vector3) -> void:
	for i in range(n):
		w.unit_manager.spawn_unit(WARRIOR_SCENE, 0,
			at + Vector3(0.8 * float(i % 4), 0, 0.8 * float(i / 4)))


func test_supertornado_on_a_big_crowd_away_from_own_units() -> void:
	var w: Dictionary = _make_world()
	var ai_tribe: Tribe = w.tribes[1]
	var ai: AIController = _make_ai(w, ai_tribe, Vector2i(100, 100))
	w.unit_manager.spawn_unit(SHAMAN_SCENE, 1, Vector3(30, 5, 40))
	_crowd(w, 12, Vector3(40, 5, 39))
	_arm_only(ai_tribe, &"supertornado")
	ai._cast_spells()
	check(_pending(ai_tribe) == &"supertornado", "twelve enemies in a crowd -> supertornado")
	ai.free()
	_free_world(w)
	# Own warrior in the crowd: never the tribe-blind twister.
	var w2: Dictionary = _make_world()
	var ai2: AIController = _make_ai(w2, w2.tribes[1], Vector2i(100, 100))
	w2.unit_manager.spawn_unit(SHAMAN_SCENE, 1, Vector3(30, 5, 40))
	_crowd(w2, 12, Vector3(40, 5, 39))
	w2.unit_manager.spawn_unit(WARRIOR_SCENE, 1, Vector3(41, 5, 40))
	_arm_only(w2.tribes[1], &"supertornado")
	ai2._cast_spells()
	check(_pending(w2.tribes[1]) == &"", "not onto the own warrior")
	ai2.free()
	_free_world(w2)


func test_earthquake_on_a_crowd_but_not_in_the_own_village() -> void:
	var w: Dictionary = _make_world()
	var ai_tribe: Tribe = w.tribes[1]
	var ai: AIController = _make_ai(w, ai_tribe, Vector2i(100, 100))
	w.unit_manager.spawn_unit(SHAMAN_SCENE, 1, Vector3(36, 5, 40))
	_crowd(w, 10, Vector3(42, 5, 39))
	_arm_only(ai_tribe, &"earthquake")
	ai._cast_spells()
	check(_pending(ai_tribe) == &"earthquake", "a crowd far from home -> earthquake")
	ai.free()
	_free_world(w)
	var w2: Dictionary = _make_world()
	var ai2: AIController = _make_ai(w2, w2.tribes[1], Vector2i(100, 100))
	w2.unit_manager.spawn_unit(SHAMAN_SCENE, 1, Vector3(36, 5, 40))
	w2.building_manager.place(HUT_SCENE, w2.tribes[1], Vector2i(46, 44), 0, true)
	_crowd(w2, 10, Vector3(42, 5, 39))
	_arm_only(w2.tribes[1], &"earthquake")
	ai2._cast_spells()
	check(_pending(w2.tribes[1]) == &"", "no quake next to an own hut")
	ai2.free()
	_free_world(w2)


func test_earthquake_on_two_enemy_buildings() -> void:
	var w: Dictionary = _make_world()
	var ai_tribe: Tribe = w.tribes[1]
	var ai: AIController = _make_ai(w, ai_tribe, Vector2i(100, 100))
	w.unit_manager.spawn_unit(SHAMAN_SCENE, 1, Vector3(40, 5, 40))
	w.building_manager.place(HUT_SCENE, w.tribes[0], Vector2i(43, 38), 0, true)
	w.building_manager.place(HUT_SCENE, w.tribes[0], Vector2i(43, 43), 0, true)
	_arm_only(ai_tribe, &"earthquake")
	ai._cast_spells()
	check(_pending(ai_tribe) == &"earthquake", "two huts together -> earthquake")
	ai.free()
	_free_world(w)


func test_a_full_fireball_stock_is_spent_on_a_lone_soldier() -> void:
	var w: Dictionary = _make_world()
	var ai_tribe: Tribe = w.tribes[1]
	var ai: AIController = _make_ai(w, ai_tribe, Vector2i(100, 100))
	w.unit_manager.spawn_unit(SHAMAN_SCENE, 1, Vector3(40, 5, 40))
	w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, Vector3(47, 5, 40))
	_arm_only(ai_tribe, &"fireball")
	ai._cast_spells()
	check(_pending(ai_tribe) == &"", "one charge: kept for a cluster")
	var fb: Spell = ai_tribe.get_spell(&"fireball")
	fb.charges = fb.max_charges
	ai._cast_spells()
	check(_pending(ai_tribe) == &"fireball", "full stock: income would be lost, so fire")
	ai.free()
	_free_world(w)
