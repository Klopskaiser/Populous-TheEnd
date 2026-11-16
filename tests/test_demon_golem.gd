extends TestBase

## Zauber 14 "Dämonengolem beschwören" (Nutzervorgabe 2026-11-16): der zweite
## Golem. Diese Datei nagelt die Vorgabe fest (Werte in Balance.DEMON_GOLEM_*):
## 2 m gross und 400 LP beim Erscheinen, keine Stufen, keine Lebenszeit; je
## Wachstumsstufe +1 m, +5 LP, +0,15 LP/s, +1 Ziel und Schaden (Handschlag +0,75,
## Tritt +0,8, Trommeln +1) auf den halben Startschaden des Golems; die Stufe kostet
## 5 Kills und alle 10 Stufen einen mehr; bei 150 m zerfaellt er. Alle Angriffe
## 15 % schneller als beim Golem gleicher Groesse. Ab 20 m Luftschiffe, ab 30 m das
## Riesenpaket. Nie gehaertet. Kill: 10 LP sofort und 10 ueber 5 s, stapelbar.
## Der Zauber steht nur im Satz des menschlichen Spielers.

const GameStateScript: GDScript = preload("res://scripts/core/game_state.gd")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const GOLEM_SCENE: PackedScene = preload("res://scenes/units/golem.tscn")
const DEMON_SCENE: PackedScene = preload("res://scenes/units/demon_golem.tscn")

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


func _demon(w: Dictionary, tribe_id: int, at: Vector3) -> DemonGolem:
	return w.um.spawn_unit(DEMON_SCENE, tribe_id, at) as DemonGolem


## Lets him grow to `metres` (credits kills until he is that tall).
func _grow_to(d: DemonGolem, metres: float) -> void:
	while d.height_m() < metres - 0.001 and d.state != Unit.State.DEAD:
		d._credit_kill()


# --- Zauber ---------------------------------------------------------------------------

func test_spell_is_the_players_alone_and_costs_what_the_golem_costs() -> void:
	var w: Dictionary = _make_world()
	var spell: Spell = w.t0.get_spell(&"demon_golem")
	check(spell != null and spell is DemonGolemSpell, "the player's set carries the demon golem")
	check(w.t1.get_spell(&"demon_golem") == null, "the default set (the AI's) does not")
	var golem: Spell = w.t0.get_spell(&"golem")
	check(is_equal_approx(spell.charge_cost, golem.charge_cost)
		and spell.max_charges == golem.max_charges
		and is_equal_approx(spell.cast_range, golem.cast_range), "same cost, charges and range as the golem")
	check(Spell.create_default_set().size() + 1 == Spell.create_player_set().size(),
		"the player's set is the default set plus this one spell")
	spell.charges = 1
	check(spell.cast(w.t0, Vector3(50, 5, 50), w.ctx), "the cast succeeds")
	check(spell.charges == 0, "one charge spent")
	var found: DemonGolem = null
	for u in w.um.units:
		if u is DemonGolem:
			found = u
	check(found != null and found.tribe_id == 0, "a demon golem of the caster appeared")
	if found != null:
		check(found is Golem and found.unit_kind() == &"golem", "he IS a golem (rules, sidebar row)")
		check(found.display_name() == "Dämonengolem", "with his own name")
		check(found.terrain_ctx == w.ctx, "and got the spell context (levelling the ground later)")
		check(found.health == 400 and found.max_health == 400, "400 LP")
		check_near(found.height_m(), 2.0, "2 m tall")
	_free_world(w)


func test_lone_demon_golem_is_no_follower() -> void:
	var w: Dictionary = _make_world()
	_demon(w, 1, Vector3(50, 5, 50))
	check(GameStateScript.is_tribe_defeated(w.t1), "a tribe with nothing but a demon golem is out")
	_free_world(w)


# --- Wachstum -------------------------------------------------------------------------

func test_growth_step_costs_five_kills_and_one_more_every_ten_steps() -> void:
	check(DemonGolem.kills_for_step(1) == 5 and DemonGolem.kills_for_step(10) == 5,
		"steps 1-10 cost 5 kills each")
	check(DemonGolem.kills_for_step(11) == 6 and DemonGolem.kills_for_step(20) == 6,
		"steps 11-20 cost 6")
	check(DemonGolem.kills_for_step(21) == 7 and DemonGolem.kills_for_step(148) == 19,
		"21-30 cost 7 ... the last ones 19")
	check(DemonGolem.kills_for_steps(10) == 50 and DemonGolem.kills_for_steps(11) == 56
		and DemonGolem.kills_for_steps(20) == 110, "summed: 50 after ten steps, 56, 110 after twenty")
	check(DemonGolem.steps_for_kills(4) == 0 and DemonGolem.steps_for_kills(5) == 1
		and DemonGolem.steps_for_kills(55) == 10 and DemonGolem.steps_for_kills(56) == 11,
		"the step count follows the kills")
	check(DemonGolem.max_steps() == 148 and DemonGolem.kills_for_steps(148) == 1762,
		"148 steps to 150 m: 1762 kills")


func test_every_step_adds_one_metre_five_health_and_fifteen_hundredths_regen() -> void:
	var w: Dictionary = _make_world()
	var d: DemonGolem = _demon(w, 0, Vector3(50, 5, 50))
	check(d.level == 0 and d.growth_steps == 0, "no levels; no growth step yet")
	check_near(d.regen_per_second(), 0.0, "no regeneration at the start")
	for i in range(4):
		d._credit_kill()
	check(d.growth_steps == 0 and is_equal_approx(d.height_m(), 2.0), "four kills: still 2 m")
	d._credit_kill()
	check(d.growth_steps == 1, "the fifth kill is a growth step")
	check_near(d.height_m(), 3.0, "exactly one metre taller (no percentage)")
	check(d.max_health == 405, "+5 health limit")
	check_near(d.regen_per_second(), 0.15, "+0,15 health per second")
	check(d.level == 0, "and still no level")
	check(d.is_stretching() or d._stretch_queued, "he stretches when he grows")
	_grow_to(d, 25.0)
	check(d.growth_steps == 23 and d.max_health == 400 + 5 * 23, "25 m: step 23, 515 LP")
	check_near(d.regen_per_second(), 3.45, "3,45 health per second")
	check(d.kills == DemonGolem.kills_for_steps(23), "after exactly the kills the table gives (139)")
	_free_world(w)


func test_he_falls_apart_at_one_hundred_and_fifty_metres() -> void:
	var w: Dictionary = _make_world()
	var d: DemonGolem = _demon(w, 0, Vector3(50, 5, 50))
	_grow_to(d, 149.0)
	check(d.state != Unit.State.DEAD and is_equal_approx(d.height_m(), 149.0), "149 m: alive")
	_grow_to(d, 150.0)
	check(d.state == Unit.State.DEAD, "reaching 150 m he falls apart")
	check(d.kills == 1762, "after 1762 kills")
	_free_world(w)


func test_no_lifetime() -> void:
	var w: Dictionary = _make_world()
	var d: DemonGolem = _demon(w, 0, Vector3(50, 5, 50))
	check(not d.has_lifetime(), "the lifetime does not run")
	for i in range(int(400.0 / TICK)):
		d.tick(TICK)
	check(d.state != Unit.State.DEAD, "still standing after 400 s (a golem lasts 180)")
	_free_world(w)


# --- Schaden, Ziele ---------------------------------------------------------------------

func test_damage_starts_at_half_the_golems_and_grows_per_step() -> void:
	var w: Dictionary = _make_world()
	var d: DemonGolem = _demon(w, 0, Vector3(50, 5, 50))
	check_near(d.damage_exact(Golem.ATTACK_SLAM), 15.5, "slam 15,5 (half of 25, +3)")
	check_near(d.damage_exact(Golem.ATTACK_KICK), 24.5, "kick 24,5 (half of 45, +2)")
	check_near(d.damage_exact(Golem.ATTACK_DRUM), 24.0, "drum 24 for the three hits (half of 42, +3)")
	check(d.attack_damage(Golem.ATTACK_SLAM) == 16 and d.attack_damage(Golem.ATTACK_KICK) == 25
		and d.attack_damage(Golem.ATTACK_DRUM) == 24, "rounded when it lands: 16 / 25 / 24")
	check(d.level_damage_bonus() == 0, "no level bonus")
	_grow_to(d, 12.0)   # ten growth steps
	check_near(d.damage_exact(Golem.ATTACK_SLAM), 15.5 + 0.75 * 10, "slam +0,75 a step")
	check_near(d.damage_exact(Golem.ATTACK_KICK), 24.5 + 0.8 * 10, "kick +0,8 a step")
	check_near(d.damage_exact(Golem.ATTACK_DRUM), 24.0 + 1.0 * 10, "drum +1 a step for all three hits")
	check(d.attack_damage(Golem.ATTACK_SLAM) == 23 and d.attack_damage(Golem.ATTACK_KICK) == 33
		and d.attack_damage(Golem.ATTACK_DRUM) == 34, "23 / 33 / 34")
	var sum: int = 0
	for hit in range(Balance.GOLEM_DRUM_HITS.size()):
		sum += d.drum_hit_damage(hit)
	check(sum == d.attack_damage(Golem.ATTACK_DRUM), "the three hits add up to the drum's damage")
	check(d.drum_hit_damage(0) == 11 and d.drum_hit_damage(2) == 12, "11 / 11 / 12")
	_free_world(w)


func test_trample_and_stomp_damage_follow_the_height_like_the_golems() -> void:
	var w: Dictionary = _make_world()
	var d: DemonGolem = _demon(w, 0, Vector3(50, 5, 50))
	check(d.trample_damage() == 1 and d.attack_damage(Golem.ATTACK_STOMP) == 2, "2 m: 1 and 2")
	_grow_to(d, 50.0)
	check(d.trample_damage() == 10 and d.attack_damage(Golem.ATTACK_STOMP) == 20,
		"50 m: height / 5 = 10, the stomp twice that")
	_free_world(w)


func test_targets_start_at_three_and_one_more_every_step() -> void:
	var w: Dictionary = _make_world()
	var d: DemonGolem = _demon(w, 0, Vector3(50, 5, 50))
	check(d.max_targets() == 3, "three targets at the start")
	check(d.max_targets_of(Golem.ATTACK_SLAM) == 3 and d.max_targets_of(Golem.ATTACK_KICK) == 1
		and d.max_targets_of(Golem.ATTACK_DRUM) == 3 and d.max_targets_of(Golem.ATTACK_STOMP) == 6,
		"shares like the golem's: slam 3, kick 1, drum 3, stomp 6")
	_grow_to(d, 25.0)
	check(d.max_targets() == 26, "25 m (23 steps): 26")
	check(d.max_targets_of(Golem.ATTACK_KICK) == 15 and d.max_targets_of(Golem.ATTACK_DRUM) == 32
		and d.max_targets_of(Golem.ATTACK_STOMP) == 52, "kick 15, drum 32, stomp 52")
	_free_world(w)


# --- Heilung --------------------------------------------------------------------------

## (Die Heilung wird hier direkt getickt: im ganzen Tick liefe nach 8 s ohne Kampf
## auch die normale Erholung jeder Einheit mit.)
func test_a_kill_heals_ten_at_once_and_ten_over_five_seconds_stacking() -> void:
	var w: Dictionary = _make_world()
	var d: DemonGolem = _demon(w, 0, Vector3(50, 5, 50))
	d.health = 100
	d._credit_kill()
	check(d.health == 110, "ten at once")
	check(d.max_health == 400, "a kill alone does not raise the limit")
	for i in range(25):
		d._tick_kill_heal(TICK)
	check(d.health >= 114 and d.health <= 116, "about five more after 2,5 s (got %d)" % d.health)
	for i in range(30):
		d._tick_kill_heal(TICK)
	check(d.health == 120, "ten over the five seconds, then it ends (got %d)" % d.health)
	for i in range(30):
		d._tick_kill_heal(TICK)
	check(d.health == 120, "nothing more afterwards")
	# Two kills right after one another: both run side by side.
	d.health = 100
	d._credit_kill()
	d._credit_kill()
	check(d.health == 120, "twice ten at once")
	for i in range(10):
		d._tick_kill_heal(TICK)
	check(d.health >= 123 and d.health <= 125, "two shares in the first second: about 4 (got %d)" % d.health)
	for i in range(50):
		d._tick_kill_heal(TICK)
	check(d.health == 140, "and twenty over the five seconds (got %d)" % d.health)
	# The limit holds.
	d.health = d.max_health - 3
	d._credit_kill()
	for i in range(60):
		d._tick_kill_heal(TICK)
	check(d.health == d.max_health, "healing ends at the health limit")
	_free_world(w)


func test_regeneration_heals_in_a_fight_up_to_the_limit() -> void:
	var w: Dictionary = _make_world()
	var d: DemonGolem = _demon(w, 0, Vector3(50, 5, 50))
	_grow_to(d, 22.0)   # 20 steps: 3 health per second
	d._heal_stacks.clear()
	d._heal_frac = 0.0
	d.health = 100
	for i in range(100):
		d._tick_level_regen(TICK)
	check(d.health >= 129 and d.health <= 131, "20 steps x 0,15 = 3/s: about 30 in 10 s (got %d)" % d.health)
	_free_world(w)


# --- Groesse, Flaechen, Tempo -----------------------------------------------------------

func test_everything_that_hangs_on_the_size_uses_the_golems_formula() -> void:
	var w: Dictionary = _make_world()
	var d: DemonGolem = _demon(w, 0, Vector3(50, 5, 50))
	check_near(d.size_factor(), 2.0 / Balance.GOLEM_HEIGHT, "size factor = height in fresh golems")
	check_near(d.reach(), Balance.GOLEM_REACH * Golem.limb_factor_for(d.size_factor()),
		"reach from the limb factor of his size")
	check(d.reach() < Balance.GOLEM_REACH, "shorter than a fresh golem's while he is small (%.2f m)" % d.reach())
	check_near(d.current_speed(), Balance.DEMON_GOLEM_MIN_SPEED, "never slower than 4 m/s")
	check_near(d.aggro_radius(), Balance.MELEE_AGGRO_RADIUS, "aggro never below the plain 8 m")
	_grow_to(d, 100.0)
	var full: Golem = GOLEM_SCENE.instantiate() as Golem
	while not full.is_full_size():
		full._credit_kill()
	check_near(d.reach(), full.reach(), "100 m: the reach of the 100-m golem", 0.05)
	check_near(d.current_speed(), full.current_speed(), "and its speed", 0.05)
	check_near(d._kick_extent().x, full._kick_extent().x, "and the length of the kick's lane", 0.1)
	check(d.trample_damage() == full.trample_damage(), "and its trample damage")
	check_near(d.stance_switch_time(), full.stance_switch_time(), "and the stance switch time", 0.01)
	check_near(d.turn_rate(), full.turn_rate(), "and the turn rate", 0.01)
	# The areas grow as the golem's do beyond level 7 — from the start.
	check_near(d.reach_factor(), pow(d.size_factor(), DemonGolem.area_exponent()), "area factor = size ^ 0,25")
	check_near(d.slam_radius(), Balance.GOLEM_SLAM_RADIUS * pow(d.size_factor(), DemonGolem.slam_exponent()),
		"slam radius = 2,6 m x size ^ 0,47")
	check(d.slam_radius() > 10.0 and d.slam_radius() < 12.0, "about 10,9 m at 100 m (%.2f)" % d.slam_radius())
	check_near(d.ground_radius(Golem.ATTACK_DRUM), d.slam_radius() * Balance.GOLEM_DRUM_RADIUS_FACTOR,
		"the drum's circle 10 % larger, as the golem's")
	full.free()
	_free_world(w)


func test_areas_of_a_demon_at_the_golems_starting_size_match_a_fresh_golem() -> void:
	# At size factor 1 (4,7 m — he passes it between 4 and 5 m) the formulas give
	# exactly a fresh golem's areas: that anchors the area growth.
	check_near(pow(1.0, DemonGolem.area_exponent()), 1.0, "area factor 1 at size 1")
	check(DemonGolem.area_exponent() > 0.24 and DemonGolem.area_exponent() < 0.26,
		"0,75 % area per 3 % body: exponent 0,25")
	check(DemonGolem.slam_exponent() > 0.45 and DemonGolem.slam_exponent() < 0.49,
		"the slam's circle 1,4 % per 3 %: exponent 0,47")


func test_he_is_a_quarter_stockier_than_the_golem() -> void:
	var w: Dictionary = _make_world()
	var d: DemonGolem = _demon(w, 0, Vector3(50, 5, 50))
	var g: Golem = GOLEM_SCENE.instantiate() as Golem
	check_near(d.body_half_width(), g.body_half_width() * 1.25, "body box 25 % wider")
	check_near(d.body_half_depth(), g.body_half_depth() * 1.25, "and deeper")
	check_near(d.model_scale().x, g.model_scale().x * 1.25, "model 25 % wider at the same height")
	check_near(d.model_scale().z, g.model_scale().z * 1.25, "and deeper")
	check_near(d.model_scale().y, g.model_scale().y, "the height scale is the golem's")
	check_near(d.trample_radius(), g.body_half_width() * 1.25 * d.size_factor(), "the trample radius follows")
	check(d.model_file() == "models/units/golem_demon.glb" and g.model_file() == "models/units/golem.glb",
		"each has its own model")
	check_near(d._shown_size, d.size_factor(), "he appears at his own size (no shrinking from 4,7 m)")
	g.free()
	_free_world(w)


# --- Tempo der Angriffe ---------------------------------------------------------------

func test_all_attacks_are_fifteen_percent_faster_than_a_golems_of_the_same_size() -> void:
	var w: Dictionary = _make_world()
	var d: DemonGolem = _demon(w, 0, Vector3(50, 5, 50))
	check_near(d.strike_cooldown(), (1.8 + 2.2 * (2.0 - 4.725) / (100.0 - 4.725)) * 0.85,
		"2 m: the golem's line carried back, 15 % shorter (1,48 s)")
	_grow_to(d, 100.0)
	var full: Golem = GOLEM_SCENE.instantiate() as Golem
	while not full.is_full_size():
		full._credit_kill()
	check_near(d.strike_cooldown(), 3.4, "100 m: 4 s minus 15 %")
	for kind in [Golem.ATTACK_KICK, Golem.ATTACK_SLAM, Golem.ATTACK_DRUM, Golem.ATTACK_STOMP]:
		check_near(d.cooldown_for(kind), full.cooldown_for(kind) * 0.85,
			"cooldown of %s 15 %% shorter than the 100-m golem's" % kind, 0.001)
		check_near(d.current_windup(kind), full.current_windup(kind) * 0.85,
			"wind-up of %s 15 %% shorter" % kind, 0.01)
	_grow_to(d, 149.0)
	check_near(d.strike_cooldown(), (1.8 + 2.2 * (149.0 - 4.725) / (100.0 - 4.725)) * 0.85,
		"beyond 100 m the cooldown goes on rising at the same rate (149 m: 4,36 s)")
	check(d.strike_cooldown() > 3.4, "so at the end he strikes slower than at 100 m")
	full.free()
	_free_world(w)


# --- Schwellen ------------------------------------------------------------------------

func test_airships_from_twenty_metres_the_giants_package_from_thirty() -> void:
	var w: Dictionary = _make_world()
	var d: DemonGolem = _demon(w, 0, Vector3(50, 5, 50))
	check(not d.can_strike_air() and not d.is_giant() and not d.tramples()
		and not d.ignores_unit_collision() and not d.walks_straight(), "2 m: none of it")
	_grow_to(d, 19.0)
	check(not d.can_strike_air(), "19 m: no airships yet")
	_grow_to(d, 20.0)
	check(d.can_strike_air(), "20 m: he strikes at airships")
	check(not d.is_giant() and not d.tramples() and not d.ignores_unit_collision(),
		"but the rest still waits")
	_grow_to(d, 29.0)
	check(not d.is_giant() and not d.ignores_unit_collision() and not d.walks_straight(), "29 m: not yet")
	_grow_to(d, 30.0)
	check(d.is_giant(), "30 m: the giant's package")
	check(d.ignores_unit_collision() and d.tramples(), "he walks through units and tramples")
	check(d.walks_straight(), "walks straight")
	check((w.um.soa_flags[d._idx] & UnitManager.FLAG_NO_COLLISION) != 0,
		"the manager knows about the collision switch")
	_free_world(w)


func test_giant_demon_tramples_what_stands_under_him() -> void:
	var w: Dictionary = _make_world()
	var d: DemonGolem = _demon(w, 0, Vector3(50, 5, 50))
	var small: DemonGolem = _demon(w, 0, Vector3(80, 5, 50))
	_grow_to(d, 30.0)
	var victim: Unit = w.um.spawn_unit(BRAVE_SCENE, 1, Vector3(50.5, 5, 50))
	var spared: Unit = w.um.spawn_unit(BRAVE_SCENE, 1, Vector3(80.2, 5, 50))
	var hp: int = victim.health
	# He "walks": the position moves between two ticks.
	d._tick_pos = d.position
	d.position += Vector3(0.3, 0, 0)
	d._tick_trample(TICK)
	check(victim.health == hp - d.trample_damage(), "the 30-m demon tramples (%d damage)" % d.trample_damage())
	small._tick_pos = small.position
	small.position += Vector3(0.3, 0, 0)
	small._tick_trample(TICK)
	check(spared.health == spared.max_health, "the 2-m demon does not")
	_free_world(w)


# --- Schwaechen -----------------------------------------------------------------------

func test_he_is_never_hardened() -> void:
	var w: Dictionary = _make_world()
	var d: DemonGolem = _demon(w, 0, Vector3(50, 5, 50))
	_grow_to(d, 120.0)
	check(not d.is_full_size(), "never 'full-grown', not even beyond 100 m")
	check(d.lightning_damage(240) == 480, "lightning still strikes twice as hard")
	check(d.burn_damage_per_second() > Balance.GOLEM_BURN_DPS, "fire still burns at the full rate")
	check(d.siege_shock_damage(15, 0.0) == Balance.GOLEM_SIEGE_DAMAGE_MAX,
		"a catapult's direct hit does the full 80 (no cap at 40)")
	check(is_equal_approx(d.regen_per_second(), 0.15 * d.growth_steps), "and no extra regeneration")
	check(d.is_conversion_immune() and d.is_hypnosis_immune() and d.is_panic_immune(),
		"the golem's immunities stay")
	_free_world(w)


func test_status_text_names_him_and_his_growth() -> void:
	var w: Dictionary = _make_world()
	var d: DemonGolem = _demon(w, 0, Vector3(50, 5, 50))
	var text: String = d.status_text()
	check(text.contains("Dämonengolem") and text.contains("2 m"), "name and size")
	check(text.contains("noch 5 Kills bis 3 m"), "kills to the next metre")
	check(not text.contains("Stufe") and not text.contains("Lebenszeit"), "no level, no lifetime")
	_free_world(w)


# --- Unterhalt (Nutzervorgabe 2026-11-16) ---------------------------------------------

## Solange er lebt, kostet er 5 Mana je Sekunde vom laufenden Einkommen — wie die
## Foersterei, vor dem Aufladen der Zauber; ohne Schuld, die nach seinem Tod weiterliefe.
func test_he_costs_five_mana_per_second_while_he_lives() -> void:
	var w: Dictionary = _make_world()
	for i in range(60):
		w.um.spawn_unit(BRAVE_SCENE, 0, Vector3(30 + float(i % 10), 5, 30 + float(i / 10)))
	var income: float = w.t0.mana_rate()
	check(income > Balance.DEMON_GOLEM_MANA_UPKEEP, "60 braves earn more than 5 mana/s (%.1f)" % income)
	var d: DemonGolem = _demon(w, 0, Vector3(50, 5, 50))
	w.t0.tick(0.1)
	d.tick(0.1)
	check_near(w.t0.upkeep_rate(), 5.0, "he claims 5 mana per second")
	check_near(w.t0.charging_income(), income - 5.0, "the spells get 5 less", 0.001)
	check_near(w.t0.upkeep_debt(), 0.5, "0,5 mana for the 0,1 s")
	w.t0.tick(0.1)   # pays the 0,5 from this tick's income
	check_near(w.t0.upkeep_debt(), 0.0, "paid off at once from the income")
	d.take_damage(100000)
	w.t0.tick(0.1)
	d.tick(0.1)
	check_near(w.t0.upkeep_rate(), 0.0, "dead, he costs nothing")
	check_near(w.t0.upkeep_debt(), 0.0, "and leaves no debt behind")
	_free_world(w)


func test_a_poor_tribe_pays_what_it_earns_and_no_more() -> void:
	var w: Dictionary = _make_world()
	for i in range(10):
		w.um.spawn_unit(BRAVE_SCENE, 0, Vector3(30 + float(i), 5, 30))
	var income: float = w.t0.mana_rate()
	check(income < Balance.DEMON_GOLEM_MANA_UPKEEP, "10 braves earn less than 5 mana/s (%.2f)" % income)
	var d: DemonGolem = _demon(w, 0, Vector3(50, 5, 50))
	w.t0.tick(0.1)
	d.tick(0.1)
	check_near(w.t0.upkeep_rate(), income, "he takes the whole income", 0.0001)
	check_near(w.t0.charging_income(), 0.0, "nothing is left for the spells")
	check_near(w.t0.upkeep_debt(), income * 0.1, "and books only what was earned", 0.0001)
	_free_world(w)
