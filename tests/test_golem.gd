extends TestBase

## Zauber 13 "Golem beschwören" (2026-09-06): beschwoert am Zielpunkt einen
## grossen, zeitlich begrenzten Steinriesen mit Flaechen-Nahkampf. Diese Datei
## nagelt die Nutzer-Spezifikation fest: 400 LP, 3,5 m/s, Reichweite 3 m,
## Wirkfeld 2 x 3 m vor ihm, 20 Schaden, 1 Gebaeudestufe je Schlag, 2 s
## Nachladen, je 25 % Hochwirbeln/Rollen, keine Kampfgruppen, 180 s Lebenszeit
## (+3 s je Kill), immun gegen Bekehrung/Hypnose/Panik/Wurf/Rollen, brennt nur
## mit 5 Schaden/s.

const GameStateScript: GDScript = preload("res://scripts/core/game_state.gd")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const PREACHER_SCENE: PackedScene = preload("res://scenes/units/preacher.tscn")
const GOLEM_SCENE: PackedScene = preload("res://scenes/units/golem.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")

const TICK: float = 0.1


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


func _make_world(height: float = 5.0) -> Dictionary:
	var td: TerrainData = _flat_terrain(height)
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
	t0.set_spells(Spell.create_default_set())
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


func _spawn(w: Dictionary, scene: PackedScene, tribe_id: int, at: Vector3) -> Unit:
	return w.um.spawn_unit(scene, tribe_id, at)


func _golem(w: Dictionary, tribe_id: int, at: Vector3) -> Golem:
	return _spawn(w, GOLEM_SCENE, tribe_id, at) as Golem


func _golems(w: Dictionary, tribe_id: int) -> Array:
	var out: Array = []
	for u in w.um.units:
		if is_instance_valid(u) and u is Golem and u.tribe_id == tribe_id \
				and u.state != Unit.State.DEAD:
			out.append(u)
	return out


# --- Beschwoerung -------------------------------------------------------------------

func test_summon_spawns_a_golem_and_spends_a_charge() -> void:
	var w: Dictionary = _make_world()
	var spell: Spell = w.t0.get_spell(&"golem")
	check(spell != null and spell is GolemSpell, "the default set carries the golem spell")
	check(spell.max_charges == 2 and is_equal_approx(spell.charge_cost, 900.0)
		and is_equal_approx(spell.cast_range, 10.0), "2 Ladungen, 900 Mana, 10 m")
	spell.charges = 2
	var pop: int = w.t0.population()
	var rate: float = w.t0.mana_rate()
	check(spell.cast(w.t0, Vector3(50, 5, 50), w.ctx), "the cast succeeds")
	check(spell.charges == 1, "one charge spent")
	var golems: Array = _golems(w, 0)
	check(golems.size() == 1, "exactly one golem appeared")
	if golems.size() == 1:
		var g: Golem = golems[0]
		check(g.tribe_id == 0 and g in w.t0.units, "it belongs to the caster")
		check(Vector2(g.position.x - 50.0, g.position.z - 50.0).length() < 1.5,
			"it stands at (or right next to) the target point")
		check(g.health == 400 and is_equal_approx(g.speed, 3.5), "400 LP, 3,5 m/s")
	check(w.t0.population() == pop, "a golem is not population")
	check(is_equal_approx(w.t0.mana_rate(), rate), "and produces no mana")
	_free_world(w)


func test_summon_fails_without_ground_and_keeps_the_charge() -> void:
	var w: Dictionary = _make_world(0.0)   # everything under water: nowhere to stand
	var spell: Spell = w.t0.get_spell(&"golem")
	spell.charges = 1
	check(not spell.cast(w.t0, Vector3(50, 0, 50), w.ctx), "no walkable cell -> no golem")
	check(spell.charges == 1, "the charge is kept")
	check(_golems(w, 0).is_empty(), "nothing was spawned")
	_free_world(w)


func test_lone_golem_does_not_keep_a_tribe_alive() -> void:
	var w: Dictionary = _make_world()
	_golem(w, 1, Vector3(50, 5, 50))
	check(GameStateScript.is_tribe_defeated(w.t1),
		"a tribe with nothing but a golem is out (it is no follower)")
	_free_world(w)


# --- Kampf ohne Gruppen -------------------------------------------------------------

func test_golem_engages_without_a_melee_seat() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	var foes: Array[Unit] = []
	for i in range(4):
		var f: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector3(55.0 + float(i) * 0.6, 5, 50.0 + float(i) * 0.6))
		f.max_health = 100000
		f.health = 100000
		foes.append(f)
	var ticks: int = 0
	while g.state != Unit.State.ATTACK and ticks < 100:
		_tick_world(w)
		ticks += 1
	check(g.state == Unit.State.ATTACK and g.attack_target != null,
		"the golem picks a fight on its own (%d ticks)" % ticks)
	for i in range(40):
		_tick_world(w)
	var seated: bool = g.combat_group != null and g.combat_group.attacker_index(g) >= 0
	check(not seated, "it never takes a seat in a melee group (no 3-attacker ring)")
	check(g.combat_group == null or g.combat_group.defender == g,
		"any group it is in is the one the enemies formed ON it")
	check(g.state != Unit.State.DEAD and g.health > 0, "four warriors do not kill it quickly")
	_free_world(w)


func test_smash_hits_the_field_in_front_and_spares_friends() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	var in_a: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.0, 5, 51.5))    # centre line
	var in_b: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.8, 5, 52.5))    # side 0,8 <= 1
	var out_side: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(52.0, 5, 51.0))  # side 2,0
	var out_far: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.0, 5, 54.0))   # along 4,0
	var behind: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.0, 5, 48.5))    # along < 0
	var friend: Unit = _spawn(w, BRAVE_SCENE, 0, Vector3(50.0, 5, 52.0))
	for u in [in_a, in_b, out_side, out_far, behind, friend]:
		u.max_health = 1000
		u.health = 1000
	g._smash()
	check(in_a.health == 1000 - Balance.GOLEM_DAMAGE, "the brave on the centre line takes 20")
	check(in_b.health == 1000 - Balance.GOLEM_DAMAGE, "the brave 0,8 m to the side takes 20")
	check(out_side.health == 1000, "2 m to the side is outside the 2-m-wide field")
	check(out_far.health == 1000, "4 m ahead is beyond the 3-m field")
	check(behind.health == 1000, "nothing behind the golem is hit")
	check(friend.health == 1000, "own units in the field are never hit")
	check(g.attack_anim == &"punch", "the strike plays the punch animation")
	_free_world(w)


func test_smash_throws_or_rolls_a_quarter_each_away_from_the_golem() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	var lifted: int = 0
	var rolled: int = 0
	var untouched: int = 0
	var trials: int = 200
	for i in range(trials):
		var v: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.0, 5, 51.5))
		v.max_health = 1000
		v.health = 1000
		g._smash()
		if v.state == Unit.State.THROWN:
			lifted += 1
			check(v._throw_velocity.z > 0.0, "a lifted victim flies AWAY from the golem (+Z)")
		elif v.state == Unit.State.ROLL:
			rolled += 1
		else:
			untouched += 1
		v.take_damage(100000)   # clear the field for the next trial
		w.um.tick(TICK)
	check(lifted > trials * 0.15 and lifted < trials * 0.35,
		"about a quarter are whirled up (%d of %d)" % [lifted, trials])
	check(rolled > trials * 0.15 and rolled < trials * 0.35,
		"about a quarter are sent rolling (%d of %d)" % [rolled, trials])
	check(untouched > trials * 0.35, "the rest just take the hit (%d of %d)" % [untouched, trials])
	_free_world(w)


func test_smash_takes_a_stage_off_enemy_buildings_only() -> void:
	var w: Dictionary = _make_world()
	# Enemy hut right in front of a tribe-0 golem facing +Z.
	var hut: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(48, 52), 0, true)
	check(hut != null, "the enemy hut stands")
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	var before: int = hut.health
	var struck: Dictionary = g._smash()
	check(struck.has(hut), "the hut lies in the strike field")
	check(hut.health < before and hut.destruction_stage() == 1,
		"one strike = one destruction stage")
	# The owner's own golem never damages the owner's hut.
	var own: Golem = _golem(w, 1, Vector3(50, 5, 46))
	own.facing = Vector3(0, 0, 1)
	var mid: int = hut.health
	own._smash()
	check(hut.health == mid, "an own building is never struck")
	_free_world(w)


func test_building_assault_from_outside_one_stage_per_two_seconds() -> void:
	var w: Dictionary = _make_world()
	var hut: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(48, 54), 0, true)
	var g: Golem = _golem(w, 0, Vector3(50, 5, 48))
	var before: int = hut.health
	g.order_attack_building(hut)
	check(g.attack_building == hut and g.state == Unit.State.ATTACK, "the order is taken")
	var ticks: int = 0
	while hut.health == before and ticks < 300:
		_tick_world(w)
		ticks += 1
	check(hut.health < before, "the golem walks up and lands the first stage (%d ticks)" % ticks)
	check(hut.destruction_stage() == 1, "exactly one stage")
	check(g.state != Unit.State.RAID and g.in_world, "it strikes from OUTSIDE (never a raider)")
	var after_first: int = hut.health
	for i in range(15):   # 1,5 s: still reloading
		_tick_world(w)
	check(hut.health == after_first, "no second stage inside the 2-s cooldown")
	for i in range(10):   # past 2 s
		_tick_world(w)
	check(hut.health < after_first, "the second strike lands after the cooldown")
	_free_world(w)


func test_airborne_targets_are_refused() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	var flyer: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(52, 5, 50))
	flyer.throw_airborne(Vector3(0, 0, 0) + Vector3.UP * 6.0)
	check(flyer.is_airborne(), "the victim is in the air")
	g._begin_attack(flyer)
	check(g.attack_target == null, "melee cannot reach a flyer — no lock")
	_free_world(w)


# --- Lebenszeit ---------------------------------------------------------------------

func test_lifetime_runs_out_and_kills_extend_it() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	check(is_equal_approx(g.life_left, Balance.GOLEM_LIFETIME), "starts with 180 s")
	g.facing = Vector3(0, 0, 1)
	var weak: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50, 5, 51.5))
	weak.health = 10
	g._smash()
	check(weak.state == Unit.State.DEAD, "the strike killed the weak brave")
	check(g.kills == 1, "the kill is credited")
	check(is_equal_approx(g.life_left, Balance.GOLEM_LIFETIME + Balance.GOLEM_LIFE_PER_KILL),
		"and buys 3 more seconds")
	g.life_left = 1.0
	for i in range(12):
		g.tick(TICK)
	check(g.state == Unit.State.DEAD, "at zero the golem crumbles")
	check(g.death_sfx_key() == &"golem_death", "with its own death sound")
	_free_world(w)


# --- Immunitaeten -------------------------------------------------------------------

func test_immunities() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	var preacher: Unit = _spawn(w, PREACHER_SCENE, 1, Vector3(52, 5, 50))
	preacher._set_state(Unit.State.CAST)
	check(not g.begin_conversion(preacher, 10.0), "a preacher cannot convert it")
	check(g.is_conversion_immune(), "conversion-immune")
	check(not g.hypnotize(w.t1, 30.0) and g.tribe_id == 0, "hypnosis does not take")
	check(HypnosisSpell.units_in_square(w.um, g.position, 1).is_empty(),
		"the hypnosis spell does not even pick it")
	g.start_panic(g.position + Vector3(1, 0, 0))
	check(g.state != Unit.State.PANIC, "no panic")
	g.throw_airborne(Vector3(3, 0, 0) + Vector3.UP * 5.0)
	check(g.state != Unit.State.THROWN, "cannot be thrown")
	g.start_roll(Vector3(1, 0, 0), 2.0, 5.0)
	check(g.state != Unit.State.ROLL, "cannot be rolled")
	check(not g.can_crew_siege() and not g.can_garrison(), "neither crew nor garrison")
	check(g.is_targetable(), "but it IS a normal attack target")
	g.take_damage(50)
	check(g.health == 350, "and takes normal damage")
	check(not g.renders_as_sprite() and g.pick_size_m().x > 0.0,
		"drawn as a 3D model with a hull-sized pick rect")
	_free_world(w)


func test_burning_is_a_trickle_without_panic() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.ignite(g.position)
	check(g.is_burning(), "fire does catch")
	check(g.state != Unit.State.PANIC, "but the golem does not panic")
	var after_contact: int = g.health
	check(after_contact == 400 - Balance.LAVA_CONTACT_DAMAGE, "the lava contact hit applies")
	for i in range(10):   # 1 s of burning
		g.tick(TICK)
	check(g.health == after_contact - int(Balance.GOLEM_BURN_DPS),
		"one second of fire costs 5 HP, not 15")
	check(g.state != Unit.State.PANIC, "still no panic while alight")
	_free_world(w)
