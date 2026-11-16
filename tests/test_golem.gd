extends TestBase

## Zauber 13 "Golem beschwören" (2026-09-06): beschwoert am Zielpunkt eine
## grosse, zeitlich begrenzte Riesin mit Flaechen-Nahkampf. Diese Datei nagelt
## die Nutzer-Spezifikation fest: 800 LP, 3,5 m/s, Reichweite 3 m, ZWEI Angriffe
## (2026-11-15) — Handschlag = Kreis rundherum (25 Schaden, je 30 %
## Hochwirbeln/Rollen), Tritt = Schneise nach vorn (45 Schaden, jeder
## Ueberlebende fliegt weit) —, beide mit Ausholzeit, 1 Gebaeudestufe je
## Angriff, 1,8 s Takt, keine Kampfgruppen, 180 s Lebenszeit (+6 s je Kill),
## Stufen 0-6 (alle 6 Kills; s. den Abschnitt "Stufen" unten),
## immun gegen Bekehrung/Hypnose/Panik/Wurf/Rollen, brennt nur mit 5 Schaden/s.

const GameStateScript: GDScript = preload("res://scripts/core/game_state.gd")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const PREACHER_SCENE: PackedScene = preload("res://scenes/units/preacher.tscn")
const GOLEM_SCENE: PackedScene = preload("res://scenes/units/golem.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const AIRSHIP_SCENE: PackedScene = preload("res://scenes/units/airship.tscn")

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
		check(g.health == 800 and is_equal_approx(g.speed, 3.5), "800 LP, 3,5 m/s")
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


## HANDSCHLAG: Kreis mit 2,6 m Radius um den Aufschlagpunkt 1,2 m vor dem Golem —
## Schaden RUNDHERUM, also auch neben und hinter ihm.
## Golem bei (50, 50), Blick +Z: Aufschlagpunkt (50, 51,2).
func test_slam_hits_a_circle_around_the_golem_and_spares_friends() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	var in_front: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.0, 5, 52.5))    # 1,3 m vom Aufschlag
	var beside: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(51.8, 5, 50.0))      # daneben, 2,16 m
	var behind: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.0, 5, 48.7))      # dahinter, 2,5 m
	var diagonal: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(51.8, 5, 52.6))    # schraeg vorn, 2,28 m
	var out_front: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.0, 5, 53.9))   # 2,7 m > 2,6
	var out_back: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.0, 5, 48.5))    # 2,7 m dahinter
	var out_side: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(52.7, 5, 51.2))    # 2,7 m daneben
	var friend: Unit = _spawn(w, BRAVE_SCENE, 0, Vector3(50.0, 5, 52.0))
	for u in [in_front, beside, behind, diagonal, out_front, out_back, out_side, friend]:
		u.max_health = 1000
		u.health = 1000
	g._smash()
	var hit: int = 1000 - Balance.GOLEM_SLAM_DAMAGE
	check(in_front.health == hit, "in front of the golem takes GOLEM_SLAM_DAMAGE")
	check(beside.health == hit, "beside the golem counts (damage all AROUND)")
	check(behind.health == hit, "behind the golem counts too")
	check(diagonal.health == hit, "2,28 m from the impact point is inside the circle")
	check(out_front.health == 1000, "2,7 m ahead of the impact point is outside")
	check(out_back.health == 1000, "2,7 m behind the impact point is outside")
	check(out_side.health == 1000, "2,7 m aside is outside")
	check(friend.health == 1000, "own units in the area are never hit")
	check(Golem.in_slam_area(1.2, 2.6) and Golem.in_slam_area(3.8, 0.0)
		and not Golem.in_slam_area(3.81, 0.0) and not Golem.in_slam_area(1.2, 2.61),
		"the slam predicate has the documented edges")
	_free_world(w)


## TRITT: Schneise 1,8 m breit, vom Golem 4,25 m nach vorn UND — das Bein holt
## aus — 70 % davon (2,98 m) nach hinten. Mehr Schaden als der Handschlag,
## weniger Flaeche, und JEDER Ueberlebende fliegt: vorn in Trittrichtung, hinten
## nach hinten weg.
func test_kick_hits_a_lane_ahead_and_behind_and_throws_everyone() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	g.knock_height_override = 53.0   # the throw chance by size: 100 % from 53 m (here only the throw is under test)
	var near: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.0, 5, 51.0))        # along 1,0
	var far: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.0, 5, 54.2))         # along 4,2
	var edge: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.8, 5, 53.0))        # side 0,8
	var out_side: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(51.0, 5, 53.0))    # side 1,0 > 0,9
	var out_far: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.0, 5, 54.5))     # along 4,5 > 4,25
	var out_back: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.0, 5, 46.8))    # along -3,2 < -2,98
	var friend: Unit = _spawn(w, BRAVE_SCENE, 0, Vector3(50.0, 5, 52.0))
	for u in [near, far, edge, out_side, out_far, out_back, friend]:
		u.max_health = 1000
		u.health = 1000
	g._kick()
	var hit: int = 1000 - Balance.GOLEM_KICK_DAMAGE
	check(near.health == hit and far.health == hit, "the whole lane ahead takes GOLEM_KICK_DAMAGE")
	check(edge.health == hit, "0,8 m aside is inside the 1,8-m-wide lane")
	# (The kick strikes three targets at level 0: the one behind her gets a kick of
	# its own — the three in front are in the air by then.)
	var behind: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.0, 5, 47.5))      # along -2,5: the backswing
	behind.max_health = 1000
	behind.health = 1000
	var all_thrown: bool = true
	var all_forward: bool = true
	for u in [near, far, edge]:
		all_thrown = all_thrown and u.state == Unit.State.THROWN
		all_forward = all_forward and u._throw_velocity.z > 0.0 \
			and absf(u._throw_velocity.x) < 0.01
	g._kick()
	check(behind.health == hit, "2,5 m BEHIND her the backswing hits too")
	check(out_side.health == 1000, "1,0 m aside is outside the lane")
	check(out_far.health == 1000, "4,5 m ahead is beyond the lane (4,25 m)")
	check(out_back.health == 1000, "3,2 m behind is beyond the backswing (2,98 m)")
	check(friend.health == 1000, "own units in the lane are never hit")
	check(all_thrown, "at 100 percent EVERY survivor of the kick is thrown (lots of knockback)")
	check(all_forward, "in front they fly along the kick, not sideways")
	check(behind.state == Unit.State.THROWN and behind._throw_velocity.z < 0.0,
		"the one behind her flies off backward")
	var len: float = Balance.GOLEM_KICK_LENGTH
	var back: float = len * Balance.GOLEM_KICK_BACK_SHARE
	check(is_equal_approx(len, 4.25) and is_equal_approx(Balance.GOLEM_KICK_BACK_SHARE, 0.7),
		"15 percent less in front (4,25 m), 70 percent of that behind")
	check(Golem.in_kick_lane(len, 0.9) and Golem.in_kick_lane(-back, 0.0)
		and not Golem.in_kick_lane(len + 0.01, 0.0) and not Golem.in_kick_lane(2.0, 0.91)
		and not Golem.in_kick_lane(-back - 0.01, 0.0),
		"the lane predicate has the documented edges")
	# User spec: more damage and knockback, but less area than the slam.
	check(Balance.GOLEM_KICK_DAMAGE > Balance.GOLEM_SLAM_DAMAGE, "the kick hurts more than the slam")
	check(Balance.GOLEM_KICK_PUSH > Balance.GOLEM_LIFT_PUSH * 2.0, "and throws much further")
	var lane_area: float = Balance.GOLEM_KICK_WIDTH * (len + back)
	var slam_area: float = PI * Balance.GOLEM_SLAM_RADIUS * Balance.GOLEM_SLAM_RADIUS
	check(lane_area < slam_area, "but still covers less area than the slam (%.1f vs %.1f m2)"
		% [lane_area, slam_area])
	_free_world(w)


## Nutzervorgaben 2026-11-15: die STATUR einer Figur so gross wie der Wachturm
## (Schaft 4,2 m, Plattform bis 4,75 m, Zinnen bis 5,25 m) — aber 10 % NIEDRIGER,
## bei gleicher Breite und Tiefe (sie wirkte zu schlank). Das 4-m-Modell wird
## entsprechend ungleich skaliert.
func test_golem_has_the_build_of_the_watchtower_but_is_a_tenth_shorter() -> void:
	check_near(Balance.GOLEM_BUILD_HEIGHT, 5.25, "the build is that of a watchtower-high figure")
	check_near(Balance.GOLEM_HEIGHT, Balance.GOLEM_BUILD_HEIGHT * 0.9,
		"the height is 10 percent less")
	check_near(Golem.MODEL_SCALE * Golem.MODEL_HEIGHT, Balance.GOLEM_BUILD_HEIGHT,
		"width and depth of the 4-m model scale with the build")
	check_near(Golem.MODEL_SCALE_Y * Golem.MODEL_HEIGHT, Balance.GOLEM_HEIGHT,
		"its height scales with the real height")
	var g: Golem = GOLEM_SCENE.instantiate() as Golem
	check_near(g.pick_size_m().y, Balance.GOLEM_HEIGHT, "and is clickable over its whole height")
	check(g.pick_size_m().x < 3.0, "its body is slim (the old golem was 4 m wide)")
	# The body box is 75 percent of the earlier 2,3 x 1,8 m (user 2026-11-15) — and
	# with it the trample radius and the ground the giant levels.
	check_near(Balance.GOLEM_BODY_HALF_WIDTH, 1.15 * 0.75 * 0.9,
		"body box: 75 percent of the old width, then another 10 percent less")
	check_near(Balance.GOLEM_BODY_HALF_DEPTH, 0.9 * 0.75 * 0.9, "and the same for the depth")
	check_near(g.trample_radius(), Balance.GOLEM_BODY_HALF_WIDTH, "the trample radius is the body box")
	check_near(g.flatten_radius(), g.trample_radius(), "and so is the ground he levels")
	g.free()


## Feind mit `hp` Leben an (x, z).
func _foe(w: Dictionary, x: float, z: float, hp: int) -> Unit:
	var u: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(x, 5, z))
	u.max_health = maxi(hp, u.max_health)
	u.health = hp
	return u


## Angriffswahl nach SCHADEN (Nutzervorgabe 2026-11-16): es gewinnt der Angriff
## mit dem meisten erwarteten Schaden je Sekunde — was er jetzt treffen wuerde,
## ohne Ueberschaden, geteilt durch seine Abklingzeit (plus ein Drittel des
## Haltungswechsels, wenn er dafuer die Haltung wechseln muesste).
func test_attack_choice_follows_the_expected_damage_per_second() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	check(g._choose_attack() == Golem.ATTACK_KICK, "nobody around: the default is the kick")
	# The clock of each attack, standing and crouched (level 0).
	var third: float = Balance.GOLEM_STANCE_SWITCH_TIME / float(Balance.GOLEM_STANCE_PLAN_ATTACKS)
	check_near(g.attack_time(Golem.ATTACK_KICK), 1.8, "standing: the kick costs its 1,8 s")
	check_near(g.attack_time(Golem.ATTACK_SLAM), 1.25 + third,
		"standing: the slam costs 1,25 s plus a third of the bending (%.2f)" % g.attack_time(Golem.ATTACK_SLAM))
	check_near(g.attack_time(Golem.ATTACK_DRUM), 1.8 + third, "and the drum 1,8 s plus that third")
	# One healthy enemy in front: all three would hit it — the kick does most per second.
	var one: Unit = _foe(w, 50.0, 51.5, 1000)
	check_near(g.attack_value(Golem.ATTACK_KICK), 45.0 / 1.8, "one target: kick 25,0 damage per second")
	check_near(g.attack_value(Golem.ATTACK_SLAM), 25.0 / (1.25 + third), "slam 17,9")
	check_near(g.attack_value(Golem.ATTACK_DRUM), 42.0 / (1.8 + third), "drum 21,5")
	check(g._choose_attack() == Golem.ATTACK_KICK, "one target, standing: she kicks")
	# A second healthy enemy beside the lane, inside the circle: two hits beat one.
	var two: Unit = _foe(w, 51.6, 51.2, 1000)
	check(g._victims(Golem.ATTACK_KICK).size() == 1 and g._victims(Golem.ATTACK_SLAM).size() == 2,
		"one enemy in the lane, two in the circle")
	check(g._choose_attack() == Golem.ATTACK_DRUM,
		"two healthy targets in the circle against one in the lane: worth bending down, and drumming")
	# The same two, almost dead: no overkill counts — the quick slam does most.
	one.health = 20
	two.health = 20
	check_near(g.attack_worth(Golem.ATTACK_DRUM), 40.0, "two targets with 20 HP are worth 40, not 80")
	check(g._choose_attack() == Golem.ATTACK_SLAM, "weak targets: the quick slam instead of the drum")
	# The turning point between slam and drum, crouched (no switch in either):
	# 25/1,25 = 20,0 against min(42, hp)/1,8 — equal at 36 HP.
	g.stance = Golem.STANCE_CROUCH
	one.health = 30
	two.health = 30
	check(g._choose_attack() == Golem.ATTACK_SLAM, "30 HP left: slam (20,0 against 16,7 per target)")
	one.health = 40
	two.health = 40
	check(g._choose_attack() == Golem.ATTACK_DRUM, "40 HP left: drum (22,2 against 20,0)")
	# Crouched with ONE healthy target: the drum (23,3) now just beats the kick
	# (23,1 incl. a third of getting up) — she stays down.
	two.position = Vector3(90, 5, 90)
	two._sync_soa_pos()
	one.health = 1000
	check_near(g.attack_value(Golem.ATTACK_KICK), 45.0 / (1.8 + third), "crouched, one target: kick 23,1")
	check_near(g.attack_value(Golem.ATTACK_DRUM), 42.0 / 1.8, "drum 23,3")
	check(g._choose_attack() == Golem.ATTACK_DRUM, "crouched, a single healthy target: she stays down and drums")
	# Standing with the same single target the kick wins (25,0 against 21,5): the
	# stance she is in has the edge.
	g.stance = Golem.STANCE_STAND
	check(g._choose_attack() == Golem.ATTACK_KICK, "standing, the same target: the kick")
	_free_world(w)


## Ausholzeit: der Angriff wird angesetzt (Animation laeuft), der Schaden faellt
## erst beim Aufschlag. Waehrenddessen bleibt sie stehen.
func test_attack_lands_after_its_wind_up() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	var foe: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector3(50, 5, 52))
	foe.max_health = 100000
	foe.health = 100000
	g.order_attack(foe)
	var ticks: int = 0
	while g._pending_attack == &"" and ticks < 60:
		_tick_world(w)
		ticks += 1
	check(g._pending_attack == Golem.ATTACK_KICK, "a single target is kicked (%d ticks)" % ticks)
	check(g.attack_anim == Golem.ATTACK_KICK, "the attack names its animation")
	check(foe.health == 100000, "winding up does no damage yet")
	var at: Vector3 = g.position
	# Kick wind-up is 0,5 s; the tick that set it already counted 0,1 s of it.
	for i in range(3):
		_tick_world(w)
	check(foe.health == 100000, "0,4 s in: still winding up")
	check(g.position.is_equal_approx(at), "she stands still while winding up")
	for i in range(2):
		_tick_world(w)
	check(foe.health == 100000 - Balance.GOLEM_KICK_DAMAGE, "the kick lands after GOLEM_KICK_WINDUP")
	check(g._pending_attack == &"", "and the wind-up is over")
	check(is_equal_approx(Golem.attack_windup(Golem.ATTACK_SLAM), Balance.GOLEM_SLAM_WINDUP)
		and Balance.GOLEM_SLAM_WINDUP < Balance.GOLEM_STRIKE_COOLDOWN
		and Balance.GOLEM_KICK_WINDUP < Balance.GOLEM_STRIKE_COOLDOWN,
		"both wind-ups fit inside the attack cooldown")
	_free_world(w)


## Zielwahl (Nutzerfeedback): wer in Reichweite steht, wird geschlagen — dem
## weggeschleuderten Ziel wird erst nachgelaufen, wenn niemand mehr nah ist.
func test_golem_turns_on_the_nearest_enemy_in_reach_before_chasing() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	var far: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector3(57, 5, 50))    # 7 m: out of reach
	var near: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector3(52, 5, 50))   # 2 m: in reach
	for u in [far, near]:
		u.max_health = 100000
		u.health = 100000
	g._begin_attack(far)   # picked by herself (an ORDERED target is kept, see test_an_ordered_target_is_kept_while_others_fight_around_her)
	check(g.attack_target == far, "locked onto the far one")
	_tick_world(w)
	check(g.attack_target == near, "...but turns on the enemy already in reach")
	# Nobody in reach any more: now it chases.
	near.take_damage(1000000)
	_tick_world(w)
	for i in range(20):
		_tick_world(w)
	check(g.attack_target == far, "with nobody near it goes for the far one")
	# Measured on the golem, not on the distance: the warrior runs at her as well.
	# (Until 2026-11-16 she kicked it away and had to follow it further; a golem
	# under 8 m throws nobody now.)
	check(g.position.x > 51.0, "and walks toward it (x %.1f)" % g.position.x)
	check(far.health < 100000, "and strikes it")
	_free_world(w)


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func test_smash_throws_or_rolls_a_quarter_each_away_from_the_golem() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	g.knock_height_override = 28.0   # 24 percent whirled up, 24 percent rolled (size rule 2026-11-16)
	var lifted: int = 0
	var rolled: int = 0
	var untouched: int = 0
	var trials: int = 200
	# ONE aggregated assertion for the direction (not one per lifted victim): the
	# number of lifts is random, and a check() inside the loop would make the
	# suite's assertion count drift from run to run.
	var all_away: bool = true
	for i in range(trials):
		var v: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.0, 5, 51.5))
		v.max_health = 1000
		v.health = 1000
		g._smash()
		if v.state == Unit.State.THROWN:
			lifted += 1
			all_away = all_away and v._throw_velocity.z > 0.0
		elif v.state == Unit.State.ROLL:
			rolled += 1
		else:
			untouched += 1
		v.take_damage(100000)   # clear the field for the next trial
		w.um.tick(TICK)
	check(all_away, "every lifted victim flies AWAY from the golem (+Z)")
	check(lifted > trials * 0.14 and lifted < trials * 0.34,
		"about 24 percent are whirled up (%d of %d)" % [lifted, trials])
	check(rolled > trials * 0.14 and rolled < trials * 0.34,
		"about 24 percent are sent rolling (%d of %d)" % [rolled, trials])
	check(untouched > trials * 0.40, "the rest just take the hit (%d of %d)" % [untouched, trials])
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
	check(struck.has(hut), "the hut lies in the slam's circle")
	check(hut.health < before and hut.destruction_stage() == 1,
		"one strike = one destruction stage")
	# The owner's own golem never damages the owner's hut.
	var own: Golem = _golem(w, 1, Vector3(50, 5, 46))
	own.facing = Vector3(0, 0, 1)
	var mid: int = hut.health
	own._smash()
	check(hut.health == mid, "an own building is never struck")
	_free_world(w)


## Ein einzelnes Gebaeude nimmt von jedem Angriff genau eine Stufe — also gewinnt
## nach der Schadenswahl der schnellste: der Handschlag aus der gebueckten Haltung
## (alle 1,25 s; frueher der Tritt alle 1,8 s).
func test_building_assault_from_outside_one_stage_per_attack() -> void:
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
	check(g.stance == Golem.STANCE_CROUCH, "she has bent down for it: the slam is the fastest attack on a building")
	var after_first: int = hut.health
	for i in range(11):   # 1,1 s: still reloading
		_tick_world(w)
	check(hut.health == after_first, "no second stage inside the slam's 1,25-s cooldown")
	for i in range(6):   # past 1,25 s
		_tick_world(w)
	check(hut.health < after_first and hut.destruction_stage() == 2,
		"the second strike lands after the cooldown")
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
	var weak: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50, 5, 52.5))
	weak.health = 10
	g._smash()
	check(weak.state == Unit.State.DEAD, "the strike killed the weak brave")
	check(g.kills == 1, "the kill is credited")
	check(is_equal_approx(g.life_left, Balance.GOLEM_LIFETIME + Balance.GOLEM_LIFE_PER_KILL)
		and is_equal_approx(Balance.GOLEM_LIFE_PER_KILL, 6.0),
		"and buys 6 more seconds")
	g.life_left = 1.0
	for i in range(12):
		g.tick(TICK)
	check(g.state == Unit.State.DEAD, "at zero the golem crumbles")
	check(g.death_sfx_key() == &"golem_death", "with its own death sound")
	_free_world(w)


## Ein Kill hebt die Lebensobergrenze um GOLEM_MAX_HP_PER_KILL (5) und heilt um
## GOLEM_HP_PER_KILL (10) — bis zur Obergrenze (Nutzervorgabe 2026-11-15: die
## Grenze bleibt, sonst heilte er sich passiv unendlich hoch).
func test_kills_raise_the_health_limit_and_heal_up_to_it() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	var start_max: int = g.max_health
	check(start_max == Balance.GOLEM_HP, "starts with GOLEM_HP as its limit")
	g.health = start_max - 30
	var weak: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50, 5, 52.5))
	weak.health = 5
	g._smash()
	check(weak.state == Unit.State.DEAD, "the strike killed the brave")
	check(g.max_health == start_max + Balance.GOLEM_MAX_HP_PER_KILL
		and Balance.GOLEM_MAX_HP_PER_KILL == 5, "the kill raised the health limit by 5")
	check(g.health == start_max - 30 + Balance.GOLEM_HP_PER_KILL
		and Balance.GOLEM_HP_PER_KILL == 10, "and healed exactly 10")

	# Nearly full: the heal stops at the (raised) limit.
	g.health = g.max_health - 2
	var weak2: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50, 5, 52.5))
	weak2.health = 5
	g._smash()
	check(weak2.state == Unit.State.DEAD, "the second brave died too")
	check(g.max_health == start_max + 2 * Balance.GOLEM_MAX_HP_PER_KILL,
		"the limit rose again")
	check(g.health == g.max_health, "and the heal is capped at the raised limit")

	# A strike that kills nobody changes neither.
	g.health = g.max_health - 40
	var limit: int = g.max_health
	var tough: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50, 5, 52.5))
	tough.max_health = 1000
	tough.health = 1000
	g._smash()
	check(tough.state != Unit.State.DEAD, "the tough one survived")
	check(g.health == limit - 40 and g.max_health == limit,
		"a strike without a kill heals nothing and raises nothing")
	_free_world(w)


# --- Stufen (Nutzervorgabe 2026-11-15) ------------------------------------------------

## Bringt den Golem ueber gutgeschriebene Kills auf die Stufe.
func _level_to(g: Golem, target: int) -> void:
	while g.level < target:
		g._credit_kill()


## Die Stufen brauchen 5, 6, 7, 7, 8, 9 und 45 Kills (Balance.GOLEM_LEVEL_KILLS;
## aufsummiert 5, 11, 18, 25, 33, 42, 87). Jeder Aufstieg bringt 20 s Lebenszeit
## (zusaetzlich zu den 6 s je Kill).
func test_levels_follow_the_kills_up_to_seven() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	check(g.level == 0 and is_equal_approx(g.size_factor(), 1.0), "a fresh golem is level 0")
	check(Balance.GOLEM_LEVEL_KILLS == ([5, 6, 7, 7, 8, 9, 45] as Array[int]),
		"kills per level: 5, 6, 7, 7, 8, 9 and 45 for the giant")
	for i in range(4):
		g._credit_kill()
	check(g.level == 0, "four kills are not a level yet")
	var before: float = g.life_left
	g._credit_kill()
	check(g.level == 1, "the fifth kill makes level 1")
	check_near(g.life_left, before + Balance.GOLEM_LIFE_PER_KILL + Balance.GOLEM_LEVEL_LIFETIME,
		"the level-up adds 20 s on top of the kill's 6 s")
	var sums: Array = [0, 5, 11, 18, 25, 33, 42, 87]
	var sums_ok: bool = true
	for lvl in range(1, 8):
		sums_ok = sums_ok and Golem.kills_for_level(lvl) == sums[lvl] \
			and Golem.level_for_kills(sums[lvl] - 1) == lvl - 1 \
			and Golem.level_for_kills(sums[lvl]) == lvl
	check(sums_ok, "the levels are reached after 5, 11, 18, 25, 33, 42 and 87 kills")
	check(Golem.level_for_kills(1000) == 7, "level 7 is the last one")
	while g.kills < 86:
		g._credit_kill()
	check(g.level == 6, "86 kills: still level 6")
	g._credit_kill()
	check(g.level == 7 and Balance.GOLEM_MAX_LEVEL == 7, "the 87th kill makes level 7")
	_free_world(w)


## Je Stufe wird der KOERPER 20 % groesser als davor (1,2 hoch Stufe), Reichweite
## und Wirkflaechen aber nur 10 % (1,1 hoch Stufe — Nutzervorgabe: langsamer als
## die Groesse). Der Schaden steigt um 5, das Tempo mit der Wurzel der Groesse.
func test_levels_grow_size_reach_area_damage_and_speed() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	check_near(g.reach(), Balance.GOLEM_REACH, "level 0 has the base reach")
	check(g.attack_damage(Golem.ATTACK_SLAM) == Balance.GOLEM_SLAM_DAMAGE
		and g.attack_damage(Golem.ATTACK_KICK) == Balance.GOLEM_KICK_DAMAGE,
		"level 0 has the base damage")
	check_near(g.speed, Balance.GOLEM_SPEED, "level 0 has the base speed")
	var r2: float = pow(1.0 + Balance.GOLEM_LEVEL_REACH_GROWTH, 2.0)   # 1,21
	# 3,0 m beside the impact point: outside the 2,6-m circle of level 0, inside
	# the 3,15-m circle of level 2.
	var bystander: Unit = _spawn(w, BRAVE_SCENE, 1,
		Vector3(53.0, 5, 50.0 + Balance.GOLEM_SLAM_FORWARD * r2))
	bystander.max_health = 1000
	bystander.health = 1000
	g._smash()
	check(bystander.health == 1000, "at level 0 the slam does not reach 3 m")

	_level_to(g, 2)
	check_near(g.size_factor(), 1.44, "level 2: the body is 1,2 x 1,2 = 44 percent bigger")
	check_near(g.reach_factor(), 1.21, "but reach and areas only 1,1 x 1,1 = 21 percent")
	check_near(g.reach(), Balance.GOLEM_REACH * g.limb_factor(), "the reach follows the limbs, not the areas")
	check(g.limb_factor() > r2 and g.limb_factor() < g.size_factor(),
		"the limbs grow faster than the areas and a little slower than the body (%.2f)" % g.limb_factor())
	check(g.attack_damage(Golem.ATTACK_SLAM) == Balance.GOLEM_SLAM_DAMAGE + 10
		and g.attack_damage(Golem.ATTACK_KICK) == Balance.GOLEM_KICK_DAMAGE + 10
		and g.trample_damage() == maxi(1, int(round(g.height_m() / 5.0))),
		"every level adds 5 damage flat to the attacks; trampling follows the size")
	check_near(g.speed, Balance.GOLEM_SPEED * sqrt(1.44), "the speed grows with the root of the SIZE")
	check(Golem.in_slam_area(1.2 * r2, 2.6 * r2, r2)
		and not Golem.in_slam_area(1.2 * r2, 2.6 * r2 + 0.01, r2)
		and Golem.in_kick_lane(Balance.GOLEM_KICK_LENGTH * r2, 0.9 * r2, r2)
		and not Golem.in_kick_lane(Balance.GOLEM_KICK_LENGTH * r2 + 0.01, 0.0, r2),
		"both strike areas scale with the reach factor")
	g._smash()
	check(bystander.health == 1000 - (Balance.GOLEM_SLAM_DAMAGE + 10),
		"at level 2 the slam reaches 3 m and hits for 35")

	_level_to(g, Balance.GOLEM_FINAL_BONUS_LEVEL)
	var s6: float = pow(1.0 + Balance.GOLEM_LEVEL_GROWTH, 6.0)         # 2,986
	var r6: float = pow(1.0 + Balance.GOLEM_LEVEL_REACH_GROWTH, 6.0)   # 1,772
	check_near(g.size_factor(), s6, "level 6: the body is 1,2 ^ 6 = 2,99 times the starting size")
	check_near(g.pick_size_m().y, Balance.GOLEM_HEIGHT * s6, "and as much taller (15,7 m)")
	check_near(g.reach_factor(), r6, "the strike areas are 1,1 ^ 6 = 1,77 times the base")
	check(r6 < s6 * 0.65, "the areas grow clearly slower than the body")
	check_near(g.reach(), Balance.GOLEM_REACH * Golem.limb_factor_for(s6),
		"the reach follows the limbs (%.1f m at level 6)" % g.reach())
	check_near(g.speed, Balance.GOLEM_SPEED * sqrt(s6), "speed at level 6 (%.2f m/s)" % g.speed)
	var dmg6: int = g.attack_damage(Golem.ATTACK_KICK)

	# Level 7, the giant: half as big again, reach and areas a quarter more, the
	# regeneration goes on by 3/s — but the damage no longer rises.
	_level_to(g, 7)
	check_near(g.size_factor(), s6 * 1.5, "level 7: the body is 50 percent bigger than at 6")
	check_near(g.reach_factor(), r6 * 1.25, "reach and areas are 25 percent bigger than at 6")
	check_near(g.speed, Balance.GOLEM_SPEED * sqrt(s6 * 1.5), "the speed follows the size")
	check(g.attack_damage(Golem.ATTACK_KICK) == dmg6
		and g.attack_damage(Golem.ATTACK_SLAM) == Balance.GOLEM_SLAM_DAMAGE + 30
		and g.trample_damage() == 4,
		"the attack damage does not rise any more at level 7; trampling is 21 m / 5 = 4")
	g.health = 100
	g._tick_level_regen(1.0)
	check(g.health == 121, "level 7 heals 21 per second (3 more than level 6)")
	check(g.max_health == Balance.GOLEM_MAX_HP_CAP and Balance.GOLEM_MAX_HP_CAP == 1000,
		"its health limit is a flat 1000")
	_free_world(w)


## Ab Stufe 1 heilt er 3 Leben je Sekunde und Stufe — bis zur Lebensobergrenze,
## nie darueber.
func test_level_regeneration_heals_three_per_second_and_level() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.health = 500
	g._tick_level_regen(1.0)
	check(g.health == 500, "level 0 does not regenerate")
	_level_to(g, 1)
	g.health = 500
	g._tick_level_regen(1.0)
	check(g.health == 503, "level 1 heals 3 per second")
	_level_to(g, 4)
	g.health = 500
	for i in range(10):
		g._tick_level_regen(TICK)
	check(g.health == 512, "level 4 heals 12 per second (in 0,1-s ticks)")
	g.health = g.max_health - 5
	g._tick_level_regen(1.0)
	check(g.health == g.max_health, "the regeneration stops at the health limit")
	g._tick_level_regen(5.0)
	check(g.health == g.max_health, "and never heals past it")
	_free_world(w)


## Ab Stufe 1 ignoriert er die Kollision mit Einheiten: er nimmt an der
## Abstandsregelung nicht mehr teil und schiebt niemanden weg.
func test_from_level_one_the_golem_ignores_unit_collision() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	check(not g.ignores_unit_collision()
		and w.um.soa_flags[g._idx] & UnitManager.FLAG_NO_COLLISION == 0,
		"level 0 still collides")
	_level_to(g, 1)
	check(g.ignores_unit_collision()
		and w.um.soa_flags[g._idx] & UnitManager.FLAG_NO_COLLISION != 0,
		"level 1 switches the collision off (flag mirrored to the manager)")
	# A brave standing right on him is not pushed out from under him.
	var on_him: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.1, 5, 50))
	var at: Vector3 = on_him.position
	for i in range(30):
		w.um.tick(TICK)
	check(_flat_dist(on_him.position, at) < 0.01, "a unit standing on him stays where it is")
	check(_flat_dist(g.position, Vector3(50, 5, 50)) < 0.01, "and he is not pushed either")
	_free_world(w)


## Trampeln (ab Stufe 1): Feinde unter seinem Koerper nehmen Schaden, solange er
## LAEUFT — nie im Stehen, nie eigene Einheiten, dasselbe Opfer hoechstens einmal
## je GOLEM_TRAMPLE_INTERVAL.
func test_trample_hurts_enemies_under_a_walking_golem_only() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	var under: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.5, 5, 50))
	var friend: Unit = _spawn(w, BRAVE_SCENE, 0, Vector3(49.5, 5, 50))
	var beside: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(53, 5, 50))
	for u in [under, friend, beside]:
		u.max_health = 1000
		u.health = 1000
	var step: Vector3 = Vector3(0.4, 0, 0)   # 0,4 m in 0,1 s = 4 m/s
	# Level 0 never tramples, however fast he walks.
	g._tick_pos = g.position - step
	g._tick_trample(TICK)
	check(under.health == 1000, "a level-0 golem does not trample")
	_level_to(g, 1)
	# Standing still: nothing.
	g._tick_pos = g.position
	g._tick_trample(TICK)
	check(under.health == 1000, "a standing golem tramples nobody")
	# Walking: the enemy under him is hit, friend and bystander are not.
	g._tick_pos = g.position - step
	g._tick_trample(TICK)
	# Trample damage = body height in metres / 5, rounded, at least 1 (user spec).
	var hit: int = g.trample_damage()
	check(hit == 1 and is_equal_approx(Balance.GOLEM_TRAMPLE_HEIGHT_PER_DAMAGE, 5.0),
		"at level 1 (5,7 m tall) trampling does 1 damage")
	check(under.health == 1000 - hit, "the enemy under the walking golem takes the trample damage")
	check(friend.health == 1000, "own units are never trampled")
	check(beside.health == 1000, "3 m aside is not under his body")
	# The same victim only once per interval.
	g._tick_pos = g.position - step
	g._tick_trample(TICK)
	check(under.health == 1000 - hit, "no second hit inside the trample interval")
	for i in range(int(Balance.GOLEM_TRAMPLE_INTERVAL / TICK) + 1):
		g._tick_pos = g.position - step
		g._tick_trample(TICK)
	check(under.health == 1000 - 2 * hit, "after the interval he is trampled again")
	# A trampled-down enemy is a kill like any other.
	var kills_before: int = g.kills
	var weak: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50, 5, 50.5))
	weak.health = 1
	g._tick_pos = g.position - step
	g._tick_trample(TICK)
	check(weak.state == Unit.State.DEAD and g.kills == kills_before + 1,
		"trampling an enemy to death counts as a kill")
	_free_world(w)


## Bemanntes Luftschiff des Stammes `tribe_id` ueber `pos` (ein Brave an Bord,
## sonst waere es neutral und fuer niemanden ein Ziel).
func _crewed_airship(w: Dictionary, tribe_id: int, pos: Vector3) -> Airship:
	var ship: Airship = _spawn(w, AIRSHIP_SCENE, tribe_id, pos) as Airship
	for i in range(80):   # climbs to its cruise height
		_tick_world(w)
	var pilot: Unit = _spawn(w, BRAVE_SCENE, tribe_id,
		Vector3(ship.position.x + 1.0, 0.0, ship.position.z))
	pilot.order_crew(ship)
	var ticks: int = 0
	while not pilot.siege_boarded and ticks < 600:
		_tick_world(w)
		ticks += 1
	return ship


## Stufe 5: der Golem schlaegt auch nach Luftschiffen — in seiner normalen
## Reichweite (flach gemessen), mit einem eigenen Schlag nach oben. Zwei Treffer
## zerstoeren das Schiff, wie beim Katapult (AIRSHIP_HULL_HITS).
func test_max_level_golem_swats_airships_out_of_the_sky() -> void:
	var w: Dictionary = _make_world()
	var ship: Airship = _crewed_airship(w, 1, Vector3(50, 5, 50))
	check(ship.auto_attackable() and ship.flies and ship.position.y > 8.0,
		"a crewed enemy airship is up (%.1f m)" % ship.position.y)
	var g: Golem = _golem(w, 0, Vector3(ship.position.x + 3.0, 5, ship.position.z))
	_level_to(g, Balance.GOLEM_FINAL_BONUS_LEVEL - 1)
	check(not g.can_strike_air() and g._airship_in_reach() == null,
		"below the maximum level airships are out of his league")
	_level_to(g, Balance.GOLEM_FINAL_BONUS_LEVEL)
	check(g.can_strike_air(), "the maximum level can strike the air")
	check(g._airship_in_reach() == ship, "an enemy airship 3 m away (flat) is in reach")
	# Same reach as on the ground, measured flat.
	g.position = Vector3(ship.position.x + g.reach() + 0.5, 5, ship.position.z)
	g._sync_soa_pos()
	check(g._airship_in_reach() == null, "half a metre beyond reach() it is not")
	g.position = Vector3(ship.position.x + 3.0, 5, ship.position.z)
	g._sync_soa_pos()
	# He winds up on his own, with the upward strike.
	var ticks: int = 0
	while g._pending_attack == &"" and ticks < 40:
		g.tick(TICK)
		ticks += 1
	check(g._pending_attack == Golem.ATTACK_SWAT and g._pending_airship == ship,
		"he winds up the swat at the airship (%d ticks)" % ticks)
	check(ship._hull_hits == 0, "winding up does not hit yet")
	for i in range(int(g.current_windup(Golem.ATTACK_SWAT) / TICK) + 1):
		g.tick(TICK)
	check(ship._hull_hits == 1 and ship.state != Unit.State.DEAD,
		"the first swat is one hull hit (the ship burns but flies)")
	check(Balance.AIRSHIP_HULL_HITS == 2, "an airship has two hull hits, as against the catapult")
	check(g._land_swat(ship) and ship.state == Unit.State.DEAD,
		"the second swat brings it down")
	check(not g._land_swat(ship), "a wreck is not hit again")
	_free_world(w)


## Der Luftschlag trifft nur feindliche, bemannte Schiffe.
func test_swat_spares_own_and_neutral_airships() -> void:
	var w: Dictionary = _make_world()
	var own: Airship = _crewed_airship(w, 0, Vector3(40, 5, 40))
	var g: Golem = _golem(w, 0, Vector3(own.position.x + 2.0, 5, own.position.z))
	_level_to(g, Balance.GOLEM_FINAL_BONUS_LEVEL)
	check(g._airship_in_reach() == null, "an own airship is no target")
	check(not g._land_swat(own) and own._hull_hits == 0, "and a swat aimed at it does nothing")
	var empty: Airship = _spawn(w, AIRSHIP_SCENE, 1, Vector3(60, 5, 60)) as Airship
	g.position = Vector3(empty.position.x + 2.0, 5, empty.position.z)
	g._sync_soa_pos()
	check(empty.is_neutral() and g._airship_in_reach() == null,
		"an uncrewed (neutral) enemy airship is nobody's target")
	_free_world(w)


## Nutzer-Bugmeldung 2026-11-15: der Gigant senkte das Gelaende auf seinem ganzen
## Weg auf das Niveau ab, auf dem er losgelaufen war ("immer auf Uferniveau"),
## weil seine eigene Mulde als tiefste Stelle unter ihm zaehlte und mitwanderte.
## Massgeblich ist das tiefste NATUERLICHE Gelaende in dem Feld, auf dem er steht.
func test_giant_levels_to_the_local_ground_and_does_not_drag_the_low_level_along() -> void:
	var w: Dictionary = _make_world(8.0)
	# A long slope rising along x: 5 m at x = 30, +0,3 m per metre.
	for vz in range(w.td.verts):
		for vx in range(30, 91):
			w.td.set_vertex_height(vx, vz, 5.0 + 0.3 * float(vx - 30))
	w.nav.update_region(Rect2i(0, 0, w.td.size, w.td.size))
	var g: Golem = _golem(w, 0, Vector3(40, w.td.get_height(40.0, 50.0), 50))
	g.terrain_ctx = w.ctx
	_level_to(g, 7)
	var r: float = g.flatten_radius()
	var start_level: float = 5.0 + 0.3 * (40.0 - r - 30.0)   # lowest ground under him at the start
	# He walks 20 m UP the slope in steps, pausing on each.
	for step in range(10):
		var x: float = 42.0 + float(step) * 2.0
		g.position = Vector3(x, w.td.get_height(x, 50.0), 50)
		g._sync_soa_pos()
		for i in range(30):
			_tick_world(w)
	var lowest_here: float = INF
	for vz in range(40, 61):
		for vx in range(40, 81):
			if Vector2(float(vx) - g.position.x, float(vz) - g.position.z).length() <= r:
				lowest_here = minf(lowest_here, w.td.heights[vz * w.td.verts + vx])
	# Each vertex was covered by footprints centred up to one radius behind it, and
	# each of those levelled to ITS lowest natural ground (another radius behind):
	# so the floor can lie as low as the natural ground three radii behind his
	# centre — but never lower, however far he has come.
	var natural_floor: float = 5.0 + 0.3 * (g.position.x - 3.0 * r - 30.0)
	check(lowest_here > start_level + 3.0,
		"20 m up the slope the ground under him is NOT cut down to where he started (%.1f vs %.1f m)"
			% [lowest_here, start_level])
	check(lowest_here >= natural_floor - 0.1,
		"it never lies below the natural ground his own body has covered (%.1f, floor %.1f m)"
			% [lowest_here, natural_floor])
	# The static plan: a pit he dug earlier does not set the level.
	var natural: Dictionary = {}
	var pit: int = 50 * w.td.verts + 20
	natural[pit] = 8.0
	w.td.heights[pit] = 2.0   # lowered by him earlier; the natural ground there is 8,0
	w.td.heights[50 * w.td.verts + 21] = 9.0   # a bump next to it
	var plan: Dictionary = Golem.flatten_plan(w.td, Vector3(20, 8, 50), 3.0, 1.0, 0.25, INF, natural)
	var lowest_target: float = INF
	for t in (plan.targets as PackedFloat32Array):
		lowest_target = minf(lowest_target, t)
	check((plan.indices as PackedInt32Array).size() > 0 and lowest_target >= 7.99,
		"the bump comes down to the NATURAL level (8,0), not to the old pit (2,0)")
	_free_world(w)


## Nach Stufe 7 waechst der Gigant weiter: alle 15 Kills 3 % groesser (aufgezinst),
## Wirkflaechen und Trampelradius 0,75 %, das Tempo nur geringfuegig — bis 100 m.
## Dauerheilung, Schaden und Lebensobergrenze steigen nicht mehr.
func test_giant_keeps_growing_beyond_level_seven_up_to_a_hundred_metres() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	_level_to(g, 7)
	check(g.growth_steps == 0, "level 7 just reached: no growth step yet")
	var size7: float = g.size_factor()
	var reach7: float = g.reach()
	var trample7: float = g.trample_radius()
	var speed7: float = g.speed
	var dmg7: int = g.attack_damage(Golem.ATTACK_KICK)
	for i in range(Balance.GOLEM_GROWTH_KILLS - 1):
		g._credit_kill()
	check(g.growth_steps == 0 and is_equal_approx(g.size_factor(), size7),
		"14 more kills: nothing yet")
	g._credit_kill()
	check(g.growth_steps == 1 and g.level == 7, "the 15th kill is one growth step (still level 7)")
	check_near(g.size_factor(), size7 * 1.03, "the body is 3 percent bigger")
	check_near(g.reach(), Balance.GOLEM_REACH * Golem.limb_factor_for(size7 * 1.03),
		"the reach grows with the limbs", 0.0005)
	check(g.reach() > reach7 * 1.02 and g.reach() < reach7 * 1.03,
		"between 2 and 3 percent a step (%.3f)" % (g.reach() / reach7))
	check_near(g.reach_factor(), Golem.reach_factor_for(7) * 1.0075, "the strike areas 0,75 percent", 0.0005)
	check_near(g.trample_radius(), trample7 * 1.03, "the body radius grows with the BODY (3 percent)", 0.0005)
	check(g.speed > speed7 and g.speed < speed7 * 1.01, "the speed rises only slightly (%.3f)" % g.speed)
	for i in range(Balance.GOLEM_GROWTH_KILLS):
		g._credit_kill()
	check_near(g.size_factor(), size7 * 1.03 * 1.03, "the growth compounds", 0.0005)
	check(g.attack_damage(Golem.ATTACK_KICK) == dmg7, "the damage stays where it was")
	check(g.max_health == Balance.GOLEM_MAX_HP_CAP + 2 * Balance.GOLEM_GROWTH_MAX_HP
		and Balance.GOLEM_GROWTH_MAX_HP == 7,
		"every growth step lifts the health limit by 7 (two steps: 1014)")
	check_near(g.regen_per_second(), 21.0, "the regeneration stays at 21 per second while he grows")
	g.health = 100
	g._tick_level_regen(1.0)
	check(g.health == 121, "and the regeneration stays at 21 per second")
	# The cap: 100 m, however many kills follow.
	g.kills += 5000
	g._credit_kill()
	check_near(g.pick_size_m().y, Balance.GOLEM_MAX_HEIGHT, "the figure stops at 100 m", 0.01)
	check(g.growth_steps == Golem.max_growth_steps() and Golem.max_growth_steps() == 53,
		"that is 53 growth steps (795 kills beyond level 7)")
	var top_speed: float = g.speed
	g.kills += 5000
	g._credit_kill()
	check(is_equal_approx(g.speed, top_speed) and g.speed < 9.0,
		"areas and speed stop growing with it (%.2f m/s)" % g.speed)
	_free_world(w)


## Der Angriffstakt waechst langsam mit der Koerperhoehe: 1,8 s bei Startgroesse,
## 4 s bei 100 m. Die Animationen werden entsprechend langsamer, dauern aber nie
## laenger als die Abklingzeit ihres Angriffs.
func test_attack_cooldown_and_animations_slow_down_with_the_size() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	check_near(g.strike_cooldown(), Balance.GOLEM_STRIKE_COOLDOWN, "level 0 attacks every 1,8 s")
	for kind in [Golem.ATTACK_SLAM, Golem.ATTACK_KICK, Golem.ATTACK_SWAT]:
		check_near(g.attack_speed(kind), 1.0, "level 0 plays %s at full speed" % kind)
	check_near(g.current_windup(Golem.ATTACK_KICK), Balance.GOLEM_KICK_WINDUP,
		"and lands the kick after the plain wind-up")
	_level_to(g, 2)
	check_near(g.attack_speed(Golem.ATTACK_KICK), 1.0 / sqrt(g.size_factor()),
		"level 2 swings slower, with the root of the size (%.2f)" % g.attack_speed(Golem.ATTACK_KICK))
	_level_to(g, 7)
	check(g.strike_cooldown() > 2.1 and g.strike_cooldown() < 2.3,
		"level 7 (21 m): the cooldown has grown only a little (%.2f s)" % g.strike_cooldown())
	var fits: bool = true
	for kind in [Golem.ATTACK_SLAM, Golem.ATTACK_KICK, Golem.ATTACK_SWAT, Golem.ATTACK_DRUM]:
		var played: float = float(Golem.CLIP_LENGTH[kind]) / (g.attack_speed(kind) * Golem.clip_rate(kind))
		fits = fits and played <= g.cooldown_for(kind) + 0.0001 \
			and g.current_windup(kind) < g.cooldown_for(kind)
	check(fits, "at level 7 every attack animation fits into its cooldown")
	check_near(float(Golem.CLIP_LENGTH[Golem.ATTACK_KICK]) / g.attack_speed(Golem.ATTACK_KICK),
		g.strike_cooldown(), "the giant's kick fills the whole cooldown — no idling in between")
	_grow_to_the_end(g)
	check_near(g.strike_cooldown(), Balance.GOLEM_STRIKE_COOLDOWN_MAX, "at 100 m: one attack every 4 s")
	check(Balance.GOLEM_STRIKE_COOLDOWN_MAX == 4.0, "the documented 4 s")
	check_near(float(Golem.CLIP_LENGTH[Golem.ATTACK_KICK]) / g.attack_speed(Golem.ATTACK_KICK), 4.0,
		"and the kick animation stretches over those 4 s")
	# In play: after a kick the next attack waits for the grown cooldown.
	g._wind_up(Golem.ATTACK_KICK)
	check_near(g._attack_cooldown, 4.0, "winding up sets the attack cooldown of the current size")
	_free_world(w)


## Drehrate: der Koerper folgt der Blickrichtung — schnell bei Startgroesse,
## bei 100 m nur noch mit 70 % der Feuerrammen-Drehrate. Angegriffen wird erst,
## wenn er zum Ziel gedreht ist; beim Drehen laeuft er langsamer.
func test_body_turns_slower_the_bigger_the_golem_is() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	check_near(g.turn_rate(), Balance.GOLEM_TURN_RATE, "a fresh golem turns at GOLEM_TURN_RATE")
	g.facing = Vector3(0, 0, 1)
	g.tick(TICK)
	check(g.heading().dot(Vector3(0, 0, 1)) > 0.999, "the first tick takes the facing as it is")
	g.facing = Vector3(0, 0, -1)
	check(g.heading().dot(Vector3(0, 0, 1)) > 0.999 and not g.is_turned_to_facing(),
		"a new facing does not turn the body at once")
	check(g._heading_frame()[0].dot(Vector3(0, 0, 1)) > 0.999, "attacks still land where the body points")
	check_near(g._slope_speed(0.0), g.speed * Balance.GOLEM_TURN_MIN_SPEED_SHARE,
		"turned away from where he wants to go he only creeps")
	var ticks_small: int = 0
	while not g.is_turned_to_facing() and ticks_small < 200:
		g._slew_heading(TICK)
		ticks_small += 1
	_grow_to_the_end(g)
	check_near(g.turn_rate(), Balance.FIRERAM_TURN_RATE * 0.7 / 1.1,
		"at 100 m: the turn takes 10 percent longer than at 70 percent of the fire ram's rate (%.2f rad/s)" % g.turn_rate())
	g.facing = Vector3(0, 0, 1)
	var ticks_big: int = 0
	while not g.is_turned_to_facing() and ticks_big < 400:
		g._slew_heading(TICK)
		ticks_big += 1
	check(ticks_big > ticks_small * 4,
		"the half turn takes the giant far longer (%d ticks instead of %d)" % [ticks_big, ticks_small])
	check_near(float(ticks_big) * TICK, (PI - deg_to_rad(Balance.GOLEM_ATTACK_ALIGN_DEG)) / g.turn_rate(),
		"exactly the angle divided by the rate", TICK * 1.5)
	g._heading = Vector3(0, 0, 1)
	check_near(g._slope_speed(0.0), g.speed, "aligned again he walks at full speed")
	_free_world(w)
	# In play: an enemy behind the full-grown giant is not struck before he has turned.
	var w2: Dictionary = _make_world()
	var g2: Golem = _golem(w2, 0, Vector3(50, 5, 50))
	_grow_to_the_end(g2)
	g2.facing = Vector3(0, 0, 1)
	g2.tick(TICK)
	var foe: Unit = _spawn(w2, BRAVE_SCENE, 1, Vector3(50, 5, 44))
	foe.max_health = 100000
	foe.health = 100000
	g2.order_attack(foe)
	var wound_up_at: int = -1
	for i in range(200):
		g2.tick(TICK)
		if g2._pending_attack != &"" and wound_up_at < 0:
			wound_up_at = i
			break
	check(wound_up_at > int(1.0 / TICK),
		"he needs well over a second to turn before he winds up (tick %d)" % wound_up_at)
	check(g2.is_turned_to_facing(), "and he is turned to the target when he does")
	_free_world(w2)


## TROMMELN: drei Schlaege auf den Boden (links, rechts, links) statt eines
## Handschlags, wenn das mehr Schaden je Sekunde bringt. Jeder Schlag 14 (zusammen 42),
## Hochwirbeln/Rollen und Gebaeudestufe nur beim letzten Schlag; Abklingzeit ist
## der normale Angriffstakt.
func test_drum_lands_three_hits_and_is_chosen_for_big_crowds() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	check(Balance.GOLEM_DRUM_HIT_DAMAGE == 14 and g.drum_hit_damage(0) == 14
		and g.drum_hit_damage(1) == 14 and g.drum_hit_damage(2) == 14
		and g.attack_damage(Golem.ATTACK_DRUM) == 42,
		"level 0: every hit does 14, 42 in all")
	check_near(g.cooldown_for(Golem.ATTACK_DRUM), g.strike_cooldown(),
		"the drum's cooldown is the plain attack rhythm (1,8 s), not the crouch's shorter one")
	check_near(g.cooldown_for(Golem.ATTACK_DRUM), 1.8, "1,8 s at the starting size")
	# Per level: +1 for every hit, on top of the flat +5 for the whole attack.
	var lv: Golem = _golem(w, 0, Vector3(20, 5, 20))
	_level_to(lv, 1)
	check(lv.drum_hit_damage(0) == 16 and lv.drum_hit_damage(1) == 16 and lv.drum_hit_damage(2) == 18
		and lv.attack_damage(Golem.ATTACK_DRUM) == 50,
		"level 1: 14 + 1 per hit, and the flat 5 split 1 + 1 + 3 — 16 / 16 / 18 = 50")
	_level_to(lv, 6)
	check(lv.drum_hit_damage(0) == 30 and lv.drum_hit_damage(2) == 30
		and lv.attack_damage(Golem.ATTACK_DRUM) == 90,
		"level 6: 14 + 6 + 10 = 30 per hit, 90 in all (+8 per level)")
	_level_to(lv, 7)
	check(lv.attack_damage(Golem.ATTACK_DRUM) == 90, "level 7 adds no damage, like the other attacks")
	lv.position = Vector3(20, 5, 90)
	lv._sync_soa_pos()
	check(float(Golem.CLIP_LENGTH[Golem.ATTACK_DRUM]) <= g.cooldown_for(Golem.ATTACK_DRUM),
		"long enough for the whole crouched drum clip (1,7 s)")
	var hut: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(48, 53), 0, true)
	var crowd: Array = []
	for i in range(4):
		# beside the kick's lane (0,9 m to each side), inside the slam's circle
		var u: Unit = _spawn(w, BRAVE_SCENE, 1,
			Vector3(50.0 + (1.3 + 0.5 * float(i / 2)) * (1.0 if i % 2 == 0 else -1.0), 5, 51.2))
		u.max_health = 100000
		u.health = 100000
		crowd.append(u)
	check(g._victims(Golem.ATTACK_SLAM).size() == 4 and g._victims(Golem.ATTACK_KICK).is_empty(),
		"four healthy enemies in the circle, none in the kick's lane")
	check(g._choose_attack() == Golem.ATTACK_DRUM,
		"healthy targets in the circle: the drum does the most damage per second")
	g._wind_up(g._choose_attack())
	check(g._pending_attack == Golem.ATTACK_DRUM
		and is_equal_approx(g._pending_time, Balance.GOLEM_DRUM_HITS[0])
		and Balance.GOLEM_DRUM_HITS == ([0.35, 0.8, 1.25] as Array[float]),
		"from the crouch the first hit lands 0,35 s after the start")
	var hit_times: Array = []
	var seen: int = 100000
	var thrown_early: bool = false
	var t: float = 0.0
	for i in range(40):
		g._tick_pending_attack(TICK)
		t += TICK
		var now: int = crowd[0].health
		if now < seen:
			hit_times.append(t)
			if hit_times.size() < 3:
				for u in crowd:
					thrown_early = thrown_early or u.state == Unit.State.THROWN \
						or u.state == Unit.State.ROLL
				check(hut.destruction_stage() == 0, "hit %d: the building is not struck yet" % hit_times.size())
			seen = now
	check(hit_times.size() == 3, "three hits landed (%d)" % hit_times.size())
	if hit_times.size() == 3:
		check(absf(hit_times[0] - 0.35) < 0.11 and absf(hit_times[1] - 0.8) < 0.11
			and absf(hit_times[2] - 1.25) < 0.11,
			"at 0,35 / 0,8 / 1,25 s (%.2f / %.2f / %.2f)" % [hit_times[0], hit_times[1], hit_times[2]])
	check(crowd[0].health == 100000 - 42, "each unit took 42 in all")
	check(not thrown_early, "the first two hits only hurt, nobody is thrown yet")
	check(hut.destruction_stage() == 1, "the last hit takes the building's stage")
	check(g._pending_attack == &"", "after the third hit the drum is over")
	_free_world(w)
	# Weak targets: the quick slam (no overkill counted).
	var w2: Dictionary = _make_world()
	var g2: Golem = _golem(w2, 0, Vector3(50, 5, 50))
	g2.facing = Vector3(0, 0, 1)
	for i in range(3):
		_foe(w2, 51.4 + 0.4 * float(i), 51.2, 20)
	check(g2._choose_attack() == Golem.ATTACK_SLAM, "three targets with 20 HP: the plain slam")
	_free_world(w2)


## Clipwahl: der Tritt wechselt das Bein; der Schlag nach einem Luftschiff
## richtet sich nach dessen Hoehe am Koerper (oben: swat, Brust bis Huefte:
## swipe, darunter: Tritt).
func test_attack_clips_alternate_legs_and_follow_the_airships_height() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	var first: StringName = g._clip_for(Golem.ATTACK_KICK)
	var second: StringName = g._clip_for(Golem.ATTACK_KICK)
	var third: StringName = g._clip_for(Golem.ATTACK_KICK)
	check(first != second and first == third
		and [first, second].has(Golem.ATTACK_KICK) and [first, second].has(Golem.CLIP_KICK_LEFT),
		"the kick alternates between the right and the left leg")
	check(g._clip_for(Golem.ATTACK_SLAM) == Golem.CLIP_SLAM_LOW
		and g._clip_for(Golem.ATTACK_DRUM) == Golem.CLIP_DRUM_LOW,
		"slam and drum play their crouched clips")
	var ship: Airship = _spawn(w, AIRSHIP_SCENE, 1, Vector3(50, 5, 53)) as Airship
	_level_to(g, 6)
	var h: float = g.height_m()
	ship.position.y = g.position.y + h * 0.95
	check(g._clip_for(Golem.ATTACK_SWAT, ship) == Golem.ATTACK_SWAT, "a ship above her head: the upward strike")
	ship.position.y = g.position.y + Balance.AIRSHIP_FLY_HEIGHT
	check(g._clip_for(Golem.ATTACK_SWAT, ship) == Golem.CLIP_SWIPE,
		"level 6 (14 m), ship at 10 m: chest height, the level swipe")
	_grow_to_the_end(g)
	var low: StringName = g._clip_for(Golem.ATTACK_SWAT, ship)
	check(low == Golem.ATTACK_KICK or low == Golem.CLIP_KICK_LEFT,
		"the 100-m giant kicks at a ship at 10 m")
	check_near(g.current_windup(Golem.ATTACK_SWAT), Balance.GOLEM_SWAT_WINDUP / g.attack_speed(Golem.ATTACK_SWAT),
		"whichever clip: the strike keeps the swat's timing")
	_free_world(w)


## Ab Stufe 7 trampelt der Gigant auch Gebaeude nieder: eine Zerstoerungsstufe
## alle 2 s je feindlichem Gebaeude unter seinem Koerper, solange er laeuft.
func test_giant_tramples_buildings_one_stage_every_two_seconds() -> void:
	var w: Dictionary = _make_world()
	var hut: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(48, 48), 0, true)
	var own_hut: Building = w.bm.place(HUT_SCENE, w.t0, Vector2i(48, 56), 0, true)
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	var step: Vector3 = Vector3(0.4, 0, 0)
	_level_to(g, 6)
	g._tick_pos = g.position - step
	g._tick_trample(TICK)
	check(hut.destruction_stage() == 0, "a level-6 golem does not trample buildings")
	_level_to(g, 7)
	g._tick_pos = g.position
	g._tick_trample(TICK)
	check(hut.destruction_stage() == 0, "the giant standing still tramples nothing")
	g._tick_pos = g.position - step
	g._tick_trample(TICK)
	check(hut.destruction_stage() == 1, "walking over it takes one destruction stage off the hut")
	g._tick_pos = g.position - step
	g._tick_trample(TICK)
	check(hut.destruction_stage() == 1, "not again inside the 2-s interval")
	for i in range(int(Balance.GOLEM_TRAMPLE_BUILDING_INTERVAL / TICK) + 1):
		g._tick_pos = g.position - step
		g._tick_trample(TICK)
	check(hut.destruction_stage() == 2, "after 2 s the next stage")
	g.position = Vector3(50, 5, 58)
	g._sync_soa_pos()
	g._tick_pos = g.position - step
	g._tick_trample(TICK)
	check(own_hut.destruction_stage() == 0, "own buildings are never trampled")
	_free_world(w)


## Hoehenunterschied des Gelaendes unter dem Koerper des Golems.
func _spread_under(w: Dictionary, g: Golem) -> float:
	var lo: float = INF
	var hi: float = -INF
	var r: float = g.flatten_radius()
	for vz in range(maxi(int(g.position.z - r) - 1, 0), mini(int(g.position.z + r) + 2, w.td.verts)):
		for vx in range(maxi(int(g.position.x - r) - 1, 0), mini(int(g.position.x + r) + 2, w.td.verts)):
			if Vector2(float(vx) - g.position.x, float(vz) - g.position.z).length() <= r:
				lo = minf(lo, w.td.heights[vz * w.td.verts + vx])
				hi = maxf(hi, w.td.heights[vz * w.td.verts + vx])
	return hi - lo


## Ohne Angriffsbefehl losgeschickt, laeuft der Golem zum Ziel und laesst sich
## unterwegs verpruegeln, statt bei jedem Gefecht stehen zu bleiben. Im
## Angriffsmove und im Stand wehrt er sich wie bisher.
func test_golem_on_a_plain_move_ignores_being_beaten() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	var foe: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector3(50.6, 5, 50))
	foe.max_health = 100000
	foe.health = 100000
	g.order_move(Vector3(80, 5, 50), false, false)
	for i in range(Unit.FLEE_RETALIATE_HITS * 3):
		g._maybe_retaliate(foe)
	check(g.state == Unit.State.MOVE and g.attack_target == null,
		"nine melee hits on a plain move: he keeps walking")
	g.order_move(Vector3(80, 5, 50), false, true)
	g._maybe_retaliate(foe)
	check(g.attack_target == foe, "on an attack-move he turns on the attacker at once")
	var idle: Golem = _golem(w, 0, Vector3(30, 5, 30))
	var foe2: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector3(30.6, 5, 30))
	idle._maybe_retaliate(foe2)
	check(idle.attack_target == foe2, "standing still he defends himself")
	_free_world(w)


## Die Lebensobergrenze steigt je Kill um 5, aber hoechstens auf 1000.
func test_health_limit_stops_at_one_thousand() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	for i in range(39):
		g._credit_kill()
	check(g.max_health == 995, "39 kills: 800 + 39 x 5 = 995")
	g._credit_kill()
	check(g.max_health == 1000, "the 40th kill reaches 1000")
	for i in range(20):
		g._credit_kill()
	check(g.max_health == 1000, "and it never goes beyond that")
	_free_world(w)


## Ein vom Golem zerstoertes GEBAEUDE zaehlt als ein Kill (Nutzervorgabe).
func test_a_destroyed_building_counts_as_one_kill() -> void:
	var w: Dictionary = _make_world()
	var hut: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(48, 52), 0, true)
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	g._smash()
	check(g.kills == 0 and is_instance_valid(hut) and hut.health > 0,
		"damaging a building is not a kill yet")
	hut.health = 1
	var life: float = g.life_left
	g._smash()
	check(not is_instance_valid(hut) or hut.health <= 0, "the hut is destroyed")
	check(g.kills == 1, "and counts as exactly one kill")
	check_near(g.life_left, life + Balance.GOLEM_LIFE_PER_KILL, "with the usual 6 s of life")
	_free_world(w)


## Stufe 7: wo der Gigant steht, wird der Boden EBEN — auf die tiefste Stelle
## unter seinem Koerper. Ringsum bleibt eine begehbare Boeschung; es wird nur
## gesenkt, nie gehoben.
func test_flatten_plan_levels_to_the_lowest_ground_with_a_walkable_bank() -> void:
	var w: Dictionary = _make_world(8.0)
	# A dip under him: lowest vertex 6,5 at (50, 50), rising all around.
	for vz in range(44, 57):
		for vx in range(44, 57):
			var d: float = Vector2(float(vx) - 50.0, float(vz) - 50.0).length()
			w.td.set_vertex_height(vx, vz, minf(8.0, 6.5 + 0.4 * d))
	var at: Vector3 = Vector3(50, 6.5, 50)
	var plan: Dictionary = Golem.flatten_plan(w.td, at, 3.0, 1.0, 0.25)
	var indices: PackedInt32Array = plan.indices
	var targets: PackedFloat32Array = plan.targets
	check(indices.size() > 10, "there is ground to level (%d vertices)" % indices.size())
	var raised: int = 0
	var off_plate: int = 0
	var too_steep: int = 0
	for i in range(indices.size()):
		var vx: int = indices[i] % w.td.verts
		var vz: int = indices[i] / w.td.verts
		var d: float = Vector2(float(vx) - 50.0, float(vz) - 50.0).length()
		if targets[i] > w.td.heights[indices[i]] + 0.0001:
			raised += 1
		if d <= 3.0 and absf(targets[i] - 6.5) > 0.0001:
			off_plate += 1
		if d > 3.0 and targets[i] > 6.5 + (d - 3.0) * 1.0 + 0.0001:
			too_steep += 1
	check(raised == 0, "the ground is only ever lowered")
	check(off_plate == 0, "under the body everything goes to the LOWEST spot (6,5)")
	check(too_steep == 0, "around it the bank rises at most 1 m per metre (walkable)")
	# Gradual: with a step limit no vertex sinks further than that in one step.
	var slow: Dictionary = Golem.flatten_plan(w.td, at, 3.0, 1.0, 0.25, 0.15)
	var deepest: float = 0.0
	for i in range((slow.indices as PackedInt32Array).size()):
		deepest = maxf(deepest, w.td.heights[slow.indices[i]] - slow.targets[i])
	check((slow.indices as PackedInt32Array).size() > 10 and deepest <= 0.1501,
		"one step lowers the ground by at most the step limit (%.3f m)" % deepest)
	# The waterline guard: nothing sinks below the floor, and ground that already
	# lies below it (sea bed) is left exactly as it is — neither lowered nor raised.
	w.td.set_vertex_height(70, 70, 0.5)    # sea bed
	w.td.set_vertex_height(71, 70, 1.0)    # sea bed
	w.td.set_vertex_height(70, 71, 6.0)    # a dune right next to it
	var wet: Dictionary = Golem.flatten_plan(w.td, Vector3(70, 2, 70), 3.0, 1.0, 0.25, INF, {},
		TerrainData.SEA_LEVEL + Balance.GOLEM_FLATTEN_ABOVE_WATER)
	var below_floor: int = 0
	var sea_bed_touched: int = 0
	for i in range((wet.indices as PackedInt32Array).size()):
		if wet.targets[i] < TerrainData.SEA_LEVEL + Balance.GOLEM_FLATTEN_ABOVE_WATER - 0.0001:
			below_floor += 1
		if w.td.heights[wet.indices[i]] <= TerrainData.SEA_LEVEL:
			sea_bed_touched += 1
	check((wet.indices as PackedInt32Array).size() > 5 and below_floor == 0,
		"at the shore nothing is lowered below the waterline")
	check(sea_bed_touched == 0, "and the sea bed itself is not touched (neither lowered nor raised)")
	# Level ground: nothing to do.
	var flat: Dictionary = Golem.flatten_plan(w.td, Vector3(20, 8, 20), 3.0, 1.0, 0.25)
	check((flat.indices as PackedInt32Array).is_empty(), "level ground is left alone")
	_free_world(w)


## ...und im Spiel: nur der Gigant (Stufe 7) ebnet, Stufe 6 nicht.
func test_only_the_level_seven_giant_levels_the_ground() -> void:
	var w: Dictionary = _make_world(8.0)
	for vz in range(40, 61):
		for vx in range(40, 61):
			w.td.set_vertex_height(vx, vz, 8.0 + 0.6 * sin(float(vx) * 1.3) * cos(float(vz) * 1.1))
	w.nav.update_region(Rect2i(0, 0, w.td.size, w.td.size))
	var g: Golem = _golem(w, 0, Vector3(50, w.td.get_height(50.0, 50.0), 50))
	g.terrain_ctx = w.ctx
	_level_to(g, 6)
	for i in range(30):
		_tick_world(w)
	check(not (Golem.flatten_plan(w.td, g.position, g.flatten_radius(), 1.0, 0.25).indices
		as PackedInt32Array).is_empty(), "a level-6 golem leaves the bumpy ground as it is")
	_level_to(g, 7)
	var before: float = _spread_under(w, g)
	for i in range(15):
		_tick_world(w)
	var soon: float = _spread_under(w, g)
	check(soon < before - 0.05 and soon > 0.3,
		"after 1,5 s the ground has only begun to sink (%.2f -> %.2f m): gradual" % [before, soon])
	for i in range(360):
		_tick_world(w)
	var lo: float = INF
	var hi: float = -INF
	var r: float = g.flatten_radius()
	for vz in range(40, 61):
		for vx in range(40, 61):
			if Vector2(float(vx) - g.position.x, float(vz) - g.position.z).length() <= r:
				lo = minf(lo, w.td.heights[vz * w.td.verts + vx])
				hi = maxf(hi, w.td.heights[vz * w.td.verts + vx])
	check(hi - lo < 0.26, "after a while the ground under the giant is level (spread %.3f m)" % (hi - lo))
	check(absf(g.position.y - lo) < 0.05, "and he stands on it")
	_free_world(w)


## Hoechste Stufe: er VERFOLGT Luftschiffe, wenn er untaetig ist und sie zu Fuss
## erreichen kann — und schlaegt sie dann herunter.
func test_max_level_golem_chases_a_reachable_airship() -> void:
	var w: Dictionary = _make_world()
	var ship: Airship = _crewed_airship(w, 1, Vector3(50, 5, 50))
	var start: Vector3 = Vector3(ship.position.x + 18.0, 5, ship.position.z)
	var g: Golem = _golem(w, 0, start)
	_level_to(g, Balance.GOLEM_FINAL_BONUS_LEVEL - 1)
	for i in range(15):
		g.tick(TICK)
	check(g.state == Unit.State.IDLE and _flat_dist(g.position, start) < 0.01,
		"below the maximum level he ignores the airship 18 m away")
	_level_to(g, Balance.GOLEM_FINAL_BONUS_LEVEL)
	check(g._airship_in_reach() == null and g._chase_target() == ship,
		"out of reach, but inside the chase radius and reachable on foot")
	var ticks: int = 0
	while ship.state != Unit.State.DEAD and ticks < 400:
		_tick_world(w)
		ticks += 1
	check(_flat_dist(g.position, start) > 5.0, "he walked after it")
	check(ship.state == Unit.State.DEAD, "and swatted it out of the sky (%d ticks)" % ticks)
	_free_world(w)


## Die Verfolgung endet bei einem Befehl von aussen und beginnt gar nicht erst
## fuer ein Schiff ausserhalb des Radius oder ueber unerreichbarem Grund.
func test_airship_chase_respects_orders_range_and_reachability() -> void:
	var w: Dictionary = _make_world()
	# Open water east of x = 80: nothing there is reachable on foot.
	for z in range(w.td.verts):
		for x in range(80, w.td.verts):
			w.td.heights[z * w.td.verts + x] = 0.0
	w.nav.update_region(Rect2i(0, 0, w.td.size, w.td.size))
	var over_water: Airship = _crewed_airship(w, 1, Vector3(70, 5, 50))
	over_water.position = Vector3(95.0, over_water.position.y, 50.0)
	over_water._sync_soa_pos()
	var g: Golem = _golem(w, 0, Vector3(76, 5, 50))
	_level_to(g, Balance.GOLEM_FINAL_BONUS_LEVEL)
	check(_flat_dist(g.position, over_water.position) < Balance.GOLEM_AIR_CHASE_RADIUS,
		"the ship over the water is inside the chase radius")
	check(g._chase_point(over_water) == Vector3.INF and g._chase_target() == null,
		"but 15 m out over open water it cannot be reached on foot")
	# A ship over land, but beyond the chase radius.
	var far: Airship = _crewed_airship(w, 1, Vector3(30, 5, 20))
	g.position = Vector3(30.0 + Balance.GOLEM_AIR_CHASE_RADIUS + 3.0, 5, 20)
	g._sync_soa_pos()
	check(g._chase_target() == null, "a ship beyond the chase radius is left alone")
	# In range: he starts chasing; an order from outside ends the chase.
	g.position = Vector3(30.0 + 15.0, 5, 20)
	g._sync_soa_pos()
	for i in range(10):
		g.tick(TICK)
	check(g._chase_ship == far and g.state == Unit.State.MOVE, "15 m away he starts the chase")
	g.order_move(Vector3(60, 5, 60), false, false)
	check(g._chase_ship == null, "a move order from outside ends the chase")
	_free_world(w)


## Der Golem steigt auf KEIN Luftschiff (Nutzer-Bugmeldung 2026-11-15) — auf
## keiner Stufe, auch nicht auf ein eigenes oder ein leeres zum Kapern.
func test_golem_never_boards_an_airship() -> void:
	var w: Dictionary = _make_world()
	var own: Airship = _spawn(w, AIRSHIP_SCENE, 0, Vector3(50, 5, 50)) as Airship
	var empty_enemy: Airship = _spawn(w, AIRSHIP_SCENE, 1, Vector3(60, 5, 50)) as Airship
	var g: Golem = _golem(w, 0, Vector3(52, 5, 50))
	for lvl in [0, Balance.GOLEM_FINAL_BONUS_LEVEL]:
		_level_to(g, lvl)
		for ship in [own, empty_enemy]:
			check(not ship.accepts_crew_unit(g), "level %d: the airship refuses the golem" % lvl)
			g.order_crew(ship)
			check(g.state != Unit.State.CREW and g.siege_engine != ship and not g.siege_boarded,
				"level %d: the boarding order does nothing" % lvl)
	var brave: Unit = _spawn(w, BRAVE_SCENE, 0, Vector3(51, 5, 50))
	check(own.accepts_crew_unit(brave), "a brave may still board")
	_free_world(w)


## Hoechste Stufe: keine Lebenszeitbegrenzung mehr.
func test_max_level_ends_the_lifetime_limit() -> void:
	var w: Dictionary = _make_world()
	var mortal: Golem = _golem(w, 0, Vector3(40, 5, 40))
	_level_to(mortal, Balance.GOLEM_FINAL_BONUS_LEVEL - 1)
	mortal.life_left = 0.5
	var eternal: Golem = _golem(w, 0, Vector3(60, 5, 60))
	_level_to(eternal, Balance.GOLEM_FINAL_BONUS_LEVEL)
	eternal.life_left = 0.5
	for i in range(12):
		mortal.tick(TICK)
		eternal.tick(TICK)
	check(mortal.state == Unit.State.DEAD, "a level-5 golem still crumbles when its time is up")
	check(eternal.state != Unit.State.DEAD, "a level-6 golem no longer crumbles")
	check_near(eternal.life_left, 0.5, "its lifetime does not run down any more")
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
	check(g.health == 750, "and takes normal damage")
	check(not g.renders_as_sprite() and g.pick_size_m().x > 0.0,
		"drawn as a 3D model with a hull-sized pick rect")
	_free_world(w)


## Feuer ist wieder ein Konter: voller Brandschaden (15/s), aber keine Panik.
## Nur der ausgewachsene Golem (100 m) ist feuerresistent (5/s).
func test_fire_burns_at_full_rate_without_panic_until_full_size() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.ignite(g.position)
	check(g.is_burning(), "fire does catch")
	check(g.state != Unit.State.PANIC, "but the golem does not panic")
	var after_contact: int = g.health
	check(after_contact == 800 - Balance.LAVA_CONTACT_DAMAGE, "the lava contact hit applies")
	for i in range(10):   # 1 s of burning
		g.tick(TICK)
	check(g.health == after_contact - 15, "one second of fire costs the full 15 HP (lost %d)"
		% [after_contact - g.health])
	check(g.state != Unit.State.PANIC, "still no panic while alight")
	check_near(g.burn_damage_per_second(), 15.0, "burns like every unit")
	_grow_to_the_end(g)
	check(g.is_full_size(), "grown to 100 m")
	check_near(g.burn_damage_per_second(), Balance.GOLEM_BURN_DPS,
		"the full-grown golem is fire-resistant (5 per second)")
	_free_world(w)


## Blitz macht doppelten Schaden am Golem — am ausgewachsenen nur den normalen.
func test_lightning_strikes_the_golem_twice_as_hard() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	check(g.lightning_damage(Balance.LIGHTNING_UNIT_DAMAGE) == 2 * Balance.LIGHTNING_UNIT_DAMAGE,
		"twice the bolt's damage")
	var before: int = g.health
	var spell: LightningSpell = LightningSpell.new()
	check(spell.execute(w.t1, g.position, w.ctx), "the enemy bolt strikes the golem")
	check(g.health == before - 2 * Balance.LIGHTNING_UNIT_DAMAGE,
		"the cast takes %d HP off him" % [2 * Balance.LIGHTNING_UNIT_DAMAGE])
	var brave: Unit = _spawn(w, BRAVE_SCENE, 0, Vector3(20, 5, 20))
	check(brave.lightning_damage(240) == 240, "everyone else takes the plain damage")
	_grow_to_the_end(g)
	check(g.lightning_damage(Balance.LIGHTNING_UNIT_DAMAGE) == Balance.LIGHTNING_UNIT_DAMAGE,
		"the full-grown golem takes only the plain bolt")
	_free_world(w)


## Katapult: ein Volltreffer macht umso mehr Schaden, je groesser der Golem ist —
## von 15 bei Startgroesse bis 80 kurz vor 100 m; der ausgewachsene nimmt
## hoechstens 40. Getroffen wird sein KOERPER, nicht nur sein Mittelpunkt.
func test_catapult_hits_hurt_more_the_bigger_the_golem_is() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(60, 5, 60))
	var shock: int = Balance.SIEGE_SHOT_SHOCK_DAMAGE
	check(Golem.siege_damage_for_height(shock, Balance.GOLEM_HEIGHT) == shock
		and Golem.siege_damage_for_height(shock, 99.9) == Balance.GOLEM_SIEGE_DAMAGE_MAX
		and Balance.GOLEM_SIEGE_DAMAGE_MAX == 80,
		"from the plain 15 at the starting size up to 80 just below 100 m")
	check(g.siege_shock_damage(shock, 0.0) == shock, "a fresh golem takes the plain shock damage")
	_level_to(g, 7)
	g.health = g.max_health
	var expect7: int = Golem.siege_damage_for_height(shock, g.height_m())
	check(expect7 > shock and expect7 == 26, "level 7 (21 m): %d per direct hit" % expect7)
	# A real shot: the stone lands 3 m beside his centre — inside his body circle.
	var shot: SiegeShot = SiegeShot.new()
	shot.setup(1, Vector3(40, 5, 60), g.position + Vector3(3.0, 0, 0), null, w.um, w.td, w.bm)
	while not shot.done:
		shot.tick(TICK)
	check(g.health == g.max_health - expect7,
		"a stone landing inside his body is a direct hit (lost %d)" % [g.max_health - g.health])
	shot.free()
	# Just outside the body, inside the shock ring: the plain damage. Further out: nothing.
	check(g.siege_shock_damage(shock, g.trample_radius() + 1.0) == shock,
		"a graze by the shock ring does the plain damage")
	g.health = g.max_health
	var far_shot: SiegeShot = SiegeShot.new()
	far_shot.setup(1, Vector3(40, 5, 60),
		g.position + Vector3(g.trample_radius() + Balance.SIEGE_SHOT_SHOCK_RADIUS + 1.0, 0, 0),
		null, w.um, w.td, w.bm)
	while not far_shot.done:
		far_shot.tick(TICK)
	check(g.health == g.max_health, "a stone beyond body and shock ring misses him")
	far_shot.free()
	# One growth step before the end: almost 80. Full-grown: capped at 40.
	while g.growth_steps < Golem.max_growth_steps() - 1:
		g._credit_kill()
	var late: int = g.siege_shock_damage(shock, 0.0)
	check(late > 70 and late <= Balance.GOLEM_SIEGE_DAMAGE_MAX and not g.is_full_size(),
		"at %.0f m a direct hit does %d" % [g.height_m(), late])
	_grow_to_the_end(g)
	check(g.is_full_size() and g.siege_shock_damage(shock, 0.0) == Balance.GOLEM_SIEGE_DAMAGE_FULL_SIZE
		and Balance.GOLEM_SIEGE_DAMAGE_FULL_SIZE == 40,
		"the full-grown golem takes at most 40")
	_free_world(w)


# --- Gerade Wege des Giganten (Stufe 7) --------------------------------------------------

## Wartet, bis die Wegsuche geantwortet hat (Warteschlange oder Worker).
func _await_path(w: Dictionary, g: Golem) -> void:
	for i in range(60):
		if g._has_path() or g.state != Unit.State.MOVE:
			return
		_tick_world(w)


## Stufe 6 laeuft um ein Haus herum. Der Gigant (Stufe 7) nimmt die Luftlinie —
## mitten durch das Haus, ohne Abweichung von der Geraden — und trampelt es dabei an.
func test_giant_walks_straight_through_buildings() -> void:
	var w: Dictionary = _make_world()
	var hut: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(58, 48), 0, true)
	check(w.nav.is_cell_blocked_by_building(Vector2i(59, 50)), "the hut lies on the beeline")
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	var target: Vector3 = Vector3(72, 5, 50)
	_level_to(g, 6)
	check(not g.walks_straight(), "level 6 still walks like everyone else")
	g.order_move(target)
	_await_path(w, g)
	check(g._path.size() > 2, "level 6 gets a detour around the hut (%d waypoints)" % g._path.size())
	g.position = Vector3(50, 5, 50)
	g._sync_soa_pos()
	_level_to(g, 7)
	check(g.walks_straight(), "the giant walks straight")
	g.order_move(target)
	check(g._path.size() == 1 and g._pending_target == Vector3.INF and g.state == Unit.State.MOVE,
		"the giant's route is one straight leg, set at once without the path queue")
	var worst: float = 0.0
	for i in range(600):
		_tick_world(w)
		worst = maxf(worst, absf(g.position.z - 50.0))
		if g.state != Unit.State.MOVE:
			break
	check(worst < 0.05, "he never leaves the beeline (max. %.2f m aside)" % worst)
	check(Vector2(g.position.x - target.x, g.position.z - target.z).length() < 0.5,
		"and arrives at the target behind the hut")
	check(not is_instance_valid(hut) or hut.health <= 0 or hut.destruction_stage() >= 1,
		"walking through the hut tramples it")
	# A target INSIDE a building: he does not stop in there.
	var own: Building = w.bm.place(HUT_SCENE, w.t0, Vector2i(80, 60), 0, true)
	var goal: Vector3 = g._giant_goal(Vector3(82, 5, 62))
	check(is_instance_valid(own) and w.nav.is_cell_walkable(w.nav.world_to_cell(goal)),
		"a target inside a building is moved to the nearest free cell")
	_free_world(w)


## Was den Giganten noch aufhaelt: das Meer und GROSSE Klippen (mehr als 20 %
## seiner Koerperhoehe auf einem Meter Weg). Ein Absatz, an dem Fusseinheiten
## scheitern, ist fuer ihn keiner.
func test_giant_line_stops_only_at_the_sea_and_big_cliffs() -> void:
	var w: Dictionary = _make_world()
	var td: TerrainData = w.td
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	_level_to(g, 7)
	var limit: float = g.giant_step_limit()
	check_near(limit, g.height_m() * Balance.GOLEM_GIANT_STEP_SHARE,
		"the step limit is a fifth of the body height (%.2f m at level 7)" % limit)
	var a: Vector3 = Vector3(20, 5, 20)
	var b: Vector3 = Vector3(40, 5, 20)
	check(Golem.giant_line_clear(td, a, b, limit), "level ground is free")
	# A 3-m ledge: too steep for foot units, nothing for the giant.
	for z in range(14, 27):
		for x in range(30, 34):
			td.set_vertex_height(x, z, 8.0)
	w.nav.update_region(Rect2i(27, 12, 10, 17))
	check(not w.nav.is_cell_walkable(Vector2i(29, 20)), "foot units cannot take the 3-m ledge")
	check(Golem.giant_line_clear(td, a, b, limit), "the giant can")
	# A 9-m cliff stops him too ...
	for z in range(14, 27):
		for x in range(30, 34):
			td.set_vertex_height(x, z, 14.0)
	check(not Golem.giant_line_clear(td, a, b, limit), "a 9-m cliff stops the level-7 giant")
	check(Golem.giant_line_clear(td, a, b, 20.0), "but not one who has grown to 100 m")
	# ... and the sea always does.
	for z in range(14, 27):
		for x in range(30, 34):
			td.set_vertex_height(x, z, 0.5)
	check(not Golem.giant_line_clear(td, a, b, 1000.0), "the sea is never crossed")
	_free_world(w)


## Ist die Luftlinie versperrt (Meeresarm), sucht er den normalen Weg — der wird
## begradigt: wenige gerade Stuecke statt Zickzack am Gitter entlang.
func test_giant_detour_around_water_is_pulled_straight() -> void:
	var w: Dictionary = _make_world()
	for z in range(0, 57):
		for x in range(60, 64):
			w.td.set_vertex_height(x, z, 0.5)
	w.nav.update_region(Rect2i(57, 0, 9, 60))
	var target: Vector3 = Vector3(72, 5, 50)
	var foot: Golem = _golem(w, 0, Vector3(50, 5, 50))
	foot.order_move(target)
	_await_path(w, foot)
	var plain: int = foot._path.size()
	check(plain > 8, "the grid route around the inlet has many waypoints (%d)" % plain)
	foot.position = Vector3(20, 5, 90)
	foot._sync_soa_pos()
	foot.order_move(Vector3(20, 5, 90))
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	_level_to(g, 7)
	g.order_move(target)
	_await_path(w, g)
	check(g._path.size() >= 2 and g._path.size() <= 4,
		"the giant's route has only the bends the water forces (%d legs)" % g._path.size())
	var legs_clear: bool = true
	var from: Vector3 = g.position
	for p in g._path:
		legs_clear = legs_clear and Golem.giant_line_clear(w.td, from, p, g.giant_step_limit())
		from = p
	check(legs_clear, "every leg is a line he can really walk")
	for i in range(900):
		_tick_world(w)
		if g.state != Unit.State.MOVE:
			break
	check(g.state != Unit.State.DEAD and not g.doomed
		and Vector2(g.position.x - target.x, g.position.z - target.z).length() < 0.5,
		"he arrives on the far side without touching the water")
	_free_world(w)


## Besatzungsfeld: ein ausgewaehlter Golem meldet Stufe, Groesse, Leben, Lebenszeit.
func test_status_text_reports_level_size_health_and_lifetime() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	var text: String = g.status_text()
	check(g.display_name() == "Golem", "the panel title is Golem")
	check(text.contains("Stufe 0/%d" % Balance.GOLEM_MAX_LEVEL)
		and text.contains("noch %d Kills bis Stufe 1" % Balance.GOLEM_LEVEL_KILLS[0]),
		"level and the kills to the next one")
	check(text.contains("Größe: %.1f m" % g.height_m())
		and text.contains("Leben: %d/%d" % [g.health, g.max_health]), "size and health")
	check(text.contains("Lebenszeit: %d s" % int(ceil(g.life_left))), "the lifetime left in seconds")
	_level_to(g, 7)
	text = g.status_text()
	check(text.contains("Stufe 7/7") and text.contains("Lebenszeit: unbegrenzt")
		and text.contains("nächsten Wachstum") and text.contains("Größe: %.1f m" % g.height_m()),
		"the giant: unlimited lifetime, kills to the next growth step, the new size")
	_free_world(w)


# --- Aggro, Gebaeude-Handschlag, Koerperkreis, Fahrzeuge (2026-11-15) ---------------------

const CATAPULT_SCENE: PackedScene = preload("res://scenes/units/siege_engine.tscn")
const FIRE_RAM_SCENE: PackedScene = preload("res://scenes/units/fire_ram.tscn")


func _grow_to_the_end(g: Golem) -> void:
	_level_to(g, 7)
	while g.growth_steps < Golem.max_growth_steps():
		g._credit_kill()


## Der Radius, in dem er von sich aus angreift, waechst mit dem Koerper (8 m x
## Groesse), gedeckelt bei GOLEM_AGGRO_MAX.
func test_aggro_radius_grows_with_the_body_up_to_a_cap() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	check_near(g.aggro_radius(), Balance.MELEE_AGGRO_RADIUS, "level 0 has the plain melee aggro radius")
	_level_to(g, 6)
	check_near(g.aggro_radius(), Balance.MELEE_AGGRO_RADIUS * g.size_factor(),
		"level 6: 8 m x size (%.1f m)" % g.aggro_radius())
	_level_to(g, 7)
	check_near(g.aggro_radius(), Balance.MELEE_AGGRO_RADIUS * g.size_factor(),
		"level 7: %.1f m" % g.aggro_radius())
	check(g.aggro_radius() > g.reach() * 3.0, "far beyond his own reach")
	# The giant picks a fight 30 m away on his own; a fresh golem ignores one at 12 m.
	var far: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(80, 5, 50))
	far.max_health = 100000
	far.health = 100000
	for i in range(60):
		_tick_world(w)
		if g.state == Unit.State.ATTACK:
			break
	check(g.state == Unit.State.ATTACK and g.attack_target == far,
		"the idle giant turns on an enemy 30 m away")
	var fresh: Golem = _golem(w, 0, Vector3(20, 5, 20))
	var near: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(32, 5, 20))
	near.max_health = 100000
	near.health = 100000
	near.order_hold() if near.has_method("order_hold") else null
	for i in range(30):
		fresh.tick(TICK)
	check(fresh.state == Unit.State.IDLE, "a level-0 golem leaves an enemy 12 m away alone")
	_grow_to_the_end(g)
	check_near(g.aggro_radius(), Balance.GOLEM_AGGRO_MAX, "capped at GOLEM_AGGRO_MAX for the grown giant")
	_free_world(w)


## Handschlag auch gegen Gebaeude: stehen drei feindliche Gebaeude in seiner
## Flaeche, schlaegt er (alle drei verlieren eine Stufe), statt eines zu treten.
func test_slam_is_chosen_when_three_buildings_stand_in_its_area() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	var a: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(51, 48), 0, true)
	var b: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(45, 48), 0, true)
	check(a != null and b != null, "two enemy huts beside her")
	# This is about slam against kick; with the stomp on offer she would open with
	# it here (see test_attack_choice_weighs_the_stomp_as_a_plan).
	g.stomp_enabled = false
	check(g._choose_attack() == Golem.ATTACK_SLAM,
		"two buildings beside her, none in the kick's lane: the slam (the drum takes longer for the same stage)")
	var c: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(48, 53), 0, true)
	check(c != null, "a third hut in front of her")
	check(g._buildings_in_area(Golem.ATTACK_SLAM).size() == 3, "all three lie in the slam's area")
	check(g._choose_attack() == Golem.ATTACK_SLAM, "three buildings: she slams — three stages against one for the kick")
	g._smash()
	check(a.destruction_stage() == 1 and b.destruction_stage() == 1 and c.destruction_stage() == 1,
		"the slam takes one stage off each of the three")
	# One building in front and two enemies beside her: a ground attack beats the kick.
	var w2: Dictionary = _make_world()
	var g2: Golem = _golem(w2, 0, Vector3(50, 5, 50))
	g2.facing = Vector3(0, 0, 1)
	w2.bm.place(HUT_SCENE, w2.t1, Vector2i(48, 53), 0, true)
	_spawn(w2, BRAVE_SCENE, 1, Vector3(51.5, 5, 50.5))
	_spawn(w2, BRAVE_SCENE, 1, Vector3(48.5, 5, 50.5))
	check(g2._choose_attack() != Golem.ATTACK_KICK
		and g2.attack_value(g2._choose_attack()) > g2.attack_value(Golem.ATTACK_KICK),
		"one building plus two enemies beside the lane: a ground attack does more than the kick")
	_free_world(w2)
	_free_world(w)


## Trefferzonen (Nutzervorgabe 2026-11-15):
##  * Der Koerperradius waechst mit dem Koerper, auch nach Stufe 7.
##  * HANDSCHLAG: Kreis um die Haende plus der VORDERE Halbkreis des Koerpers.
##    Hinter ihr, an den Fersen, trifft nur, was der Kreis der Haende erreicht.
##  * TRITT: nur die Schneise. Sie laeuft durch den ganzen Koerperkreis, wird dort
##    aber nicht auf den Koerper verbreitert.
func test_hit_zones_slam_front_half_of_the_body_kick_lane_only() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	var forward: Vector3 = Vector3(0, 0, 1)
	var right: Vector3 = Vector3(-1, 0, 0)
	_level_to(g, 7)
	check_near(g.trample_radius(), Balance.GOLEM_BODY_HALF_WIDTH * g.size_factor(),
		"level 7: the body radius is the body box times the size")
	_grow_to_the_end(g)
	var body: float = g.trample_radius()
	check_near(body, Balance.GOLEM_BODY_HALF_WIDTH * g.size_factor(),
		"and it keeps growing with the body beyond level 7 (%.1f m at 100 m)" % body)
	var r: float = g.reach_factor()
	# The hands come down limb_factor() x 1,2 m ahead; the circle around them has
	# the slowly grown radius. At 100 m it lies wholly in front of her.
	var hands: float = Balance.GOLEM_SLAM_FORWARD * g.limb_factor()
	var slam_near: float = hands - g.slam_radius()
	check(body > g.slam_radius(), "at 100 m the body is wider than the slam circle")
	check(slam_near > 0.0, "and the circle of the hands lies wholly in front of her (from %.1f m on)" % slam_near)
	var at: Callable = func(along: float, side: float) -> Vector3:
		return g.position + forward * along + right * side
	# SLAM
	check(g._in_hit_zone(Golem.ATTACK_SLAM, at.call(1.0, body - 0.5), forward, right),
		"slam: the front half of the body circle is struck, far beside the hands")
	check(g._in_hit_zone(Golem.ATTACK_SLAM, at.call(hands + g.slam_radius() - 0.2, 0.0), forward, right)
		and not g._in_hit_zone(Golem.ATTACK_SLAM, at.call(hands + g.slam_radius() + 0.5, 0.0), forward, right),
		"slam: ahead as far as the circle of the hands reaches (%.1f m)" % (hands + g.slam_radius()))
	check(not g._in_hit_zone(Golem.ATTACK_SLAM, at.call(-0.5, 0.0), forward, right),
		"slam: at her heels, beyond that circle, nothing is struck although it is under her body")
	check(not g._in_hit_zone(Golem.ATTACK_SLAM, at.call(-1.0, body - 0.5), forward, right),
		"slam: the BACK half of the body circle is not added")
	# KICK
	var half: float = Balance.GOLEM_KICK_WIDTH * 0.5 * r
	check(g._in_hit_zone(Golem.ATTACK_KICK, at.call(0.0, half - 0.1), forward, right)
		and not g._in_hit_zone(Golem.ATTACK_KICK, at.call(0.0, half + 0.5), forward, right),
		"kick: only the lane counts, also at the body — it is not widened to the body circle")
	check(g._in_hit_zone(Golem.ATTACK_KICK, at.call(body - 0.2, 0.0), forward, right)
		and g._in_hit_zone(Golem.ATTACK_KICK, at.call(-(body - 0.2), 0.0), forward, right),
		"kick: the lane runs through the whole body circle, ahead and behind")
	var lane: Vector2 = g._kick_extent()
	check_near(lane.x, Balance.GOLEM_KICK_LENGTH * g.kick_limb_factor(), "kick: the lane is as long as her leg reaches")
	check(lane.x > body and g._in_hit_zone(Golem.ATTACK_KICK, at.call(lane.x - 0.2, 0.0), forward, right)
		and not g._in_hit_zone(Golem.ATTACK_KICK, at.call(lane.x + 0.5, 0.0), forward, right),
		"kick: and ends there (%.1f m ahead)" % lane.x)
	# In play, at level 7: nobody behind her heels is hurt by the slam.
	var w2: Dictionary = _make_world()
	var g2: Golem = _golem(w2, 0, Vector3(50, 5, 50))
	g2.facing = Vector3(0, 0, 1)
	_level_to(g2, 7)
	var back7: float = g2.slam_radius() \
		- Balance.GOLEM_SLAM_FORWARD * g2.limb_factor()
	check(g2.trample_radius() > back7 + 0.2, "level 7: her body reaches further back than the slam circle")
	var heel: Unit = _spawn(w2, BRAVE_SCENE, 1, Vector3(50, 5, 50.0 - (back7 + 0.2)))
	var front: Unit = _spawn(w2, BRAVE_SCENE, 1, Vector3(50, 5, 52.0))
	for u in [heel, front]:
		u.max_health = 100000
		u.health = 100000
	g2._smash()
	check(front.health < 100000 and heel.health == 100000,
		"the slam hits in front and spares the enemy at her heels")
	g2._kick()
	check(heel.health < 100000, "the kick's backswing lane does reach him")
	_free_world(w2)
	_free_world(w)


## Zielobergrenze: je Schadenstick trifft der Golem hoechstens so viele Ziele, wie
## seine Stufe erlaubt (5, 6, 6, 6, 7, 8, 8, 8; nach Stufe 7 alle 3
## Wachstumsschritte eines mehr). Einheiten vor Gebaeuden; das Angriffsziel immer.
func test_target_cap_limits_every_damage_tick() -> void:
	check(Balance.GOLEM_MAX_TARGETS == ([5, 6, 6, 6, 7, 8, 8, 8] as Array[int]),
		"targets per level 0-7: 5, 6, 6, 6, 7, 8, 8, 8")
	check(Golem.max_targets_for(7, 2) == 8 and Golem.max_targets_for(7, 3) == 9
		and Golem.max_targets_for(7, Golem.max_growth_steps()) == 8 + Golem.max_growth_steps() / 3,
		"beyond level 7 every third growth step adds one (%d at 100 m)"
			% Golem.max_targets_for(7, Golem.max_growth_steps()))
	# --- slam into a crowd: 5 of 9, the attack target among them -----------------
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	var crowd: Array = []
	for i in range(8):
		var ang: float = TAU * float(i) / 8.0
		crowd.append(_spawn(w, BRAVE_SCENE, 1,
			Vector3(50.0 + cos(ang) * 0.9, 5, 51.2 + sin(ang) * 0.9)))
	var target: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.0, 5, 53.6))   # the farthest one
	crowd.append(target)
	for u in crowd:
		u.max_health = 100000
		u.health = 100000
	check(g._victims(Golem.ATTACK_SLAM).size() == 9, "nine enemies stand in the slam's area")
	g._begin_attack(target)
	g._smash()
	var hit: int = 0
	for u in crowd:
		if u.health < 100000:
			hit += 1
	check(hit == 5 and g.max_targets() == 5, "level 0 strikes exactly 5 of them (struck %d)" % hit)
	check(target.health < 100000, "the unit she is attacking is always among them, though it stands farthest")
	_free_world(w)
	# --- units before buildings; the building she attacks always -------------------
	var w2: Dictionary = _make_world()
	var g2: Golem = _golem(w2, 0, Vector3(50, 5, 50))
	g2.facing = Vector3(0, 0, 1)
	var hut: Building = w2.bm.place(HUT_SCENE, w2.t1, Vector2i(48, 53), 0, true)
	var braves: Array = []
	for i in range(6):
		var b: Unit = _spawn(w2, BRAVE_SCENE, 1, Vector3(49.0 + 0.4 * float(i), 5, 51.0 + 0.2 * float(i % 3)))
		b.max_health = 100000
		b.health = 100000
		braves.append(b)
	g2._smash()
	var hit2: int = 0
	for b in braves:
		if b.health < 100000:
			hit2 += 1
	check(hit2 == 5 and hut.destruction_stage() == 0,
		"six enemies and a hut: the 5 slots go to units, the hut is spared (units before buildings)")
	_free_world(w2)
	# (a fresh world: the first slam threw some of them out of the area)
	var w4: Dictionary = _make_world()
	var g4: Golem = _golem(w4, 0, Vector3(50, 5, 50))
	g4.facing = Vector3(0, 0, 1)
	var hut4: Building = w4.bm.place(HUT_SCENE, w4.t1, Vector2i(48, 53), 0, true)
	var braves4: Array = []
	for i in range(6):
		var b4: Unit = _spawn(w4, BRAVE_SCENE, 1, Vector3(49.0 + 0.4 * float(i), 5, 51.0 + 0.2 * float(i % 3)))
		b4.max_health = 100000
		b4.health = 100000
		braves4.append(b4)
	g4.order_attack_building(hut4)
	g4._smash()
	var hit4: int = 0
	for b4 in braves4:
		if b4.health < 100000:
			hit4 += 1
	check(hut4.destruction_stage() == 1 and hit4 == 4,
		"attacking the hut: it is always struck and takes one slot, 4 units fill the rest (struck %d)" % hit4)
	_free_world(w4)
	# --- trampling: at most max_targets per second -----------------------------------
	var w3: Dictionary = _make_world()
	var g3: Golem = _golem(w3, 0, Vector3(50, 5, 50))
	_level_to(g3, 1)
	var under: Array = []
	for i in range(10):
		var ang3: float = TAU * float(i) / 10.0
		var u3: Unit = _spawn(w3, BRAVE_SCENE, 1, Vector3(50.0 + cos(ang3) * 0.5, 5, 50.0 + sin(ang3) * 0.5))
		u3.max_health = 100000
		u3.health = 100000
		under.append(u3)
	var step: Vector3 = Vector3(0.4, 0, 0)
	var count_hit: Callable = func() -> int:
		var n: int = 0
		for u4 in under:
			if u4.health < 100000:
				n += 1
		return n
	g3._tick_pos = g3.position - step
	g3._tick_trample(TICK)
	check(count_hit.call() == 6 and g3.max_targets() == 6, "level 1 tramples 6 of the 10 under her (%d)" % count_hit.call())
	g3._tick_pos = g3.position - step
	g3._tick_trample(TICK)
	check(count_hit.call() == 6, "and no more in the same second")
	for i in range(int(Balance.GOLEM_TRAMPLE_INTERVAL / TICK) + 1):
		g3._tick_pos = g3.position
		g3._tick_trample(TICK)
	g3._tick_pos = g3.position - step
	g3._tick_trample(TICK)
	var lost: int = 0
	for u5 in under:
		lost += 100000 - u5.health
	check(lost == 12 * g3.trample_damage(),
		"a second later the next 6 hits fall — 12 in all, never more than 6 per second (%d)"
			% [lost / g3.trample_damage()])
	_free_world(w3)


## Ab Stufe 7 treffen Angriffe und Trampeln auch fremde Bodenfahrzeuge, mit deren
## eigenen Schadensstufen: Katapult sofort zerstoert, Feuerramme drei Leben.
func test_giant_wrecks_foreign_vehicles_by_their_own_damage_steps() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	var catapult: Unit = _spawn(w, CATAPULT_SCENE, 1, Vector3(50, 5, 53))
	var own: Unit = _spawn(w, CATAPULT_SCENE, 0, Vector3(50.5, 5, 55))
	_level_to(g, 6)
	g._kick()
	check(catapult.state != Unit.State.DEAD, "a level-6 golem's kick does nothing to a vehicle")
	_level_to(g, 7)
	check(g.crushes_vehicle(catapult) and not g.crushes_vehicle(own),
		"the giant wrecks foreign vehicles, never those under his own flag")
	var kills: int = g.kills
	g._kick()
	check(catapult.state == Unit.State.DEAD, "one kick destroys the catapult at once")
	check(own.state != Unit.State.DEAD, "the own catapult in the same lane is spared")
	check(g.kills == kills + 1, "a wrecked vehicle counts as one kill")
	var ram: FireRam = _spawn(w, FIRE_RAM_SCENE, 1, Vector3(50, 5, 54)) as FireRam
	var blows: int = 0
	while ram.state != Unit.State.DEAD and blows < 10:
		g._kick()
		blows += 1
	check(blows == Balance.FIRERAM_FIRE_LIVES, "the fire ram takes %d blows (took %d)"
		% [Balance.FIRERAM_FIRE_LIVES, blows])
	# Trampling: the catapult under his feet is gone at once, the ram loses one
	# life every GOLEM_TRAMPLE_BUILDING_INTERVAL — only while he walks.
	var cat2: Unit = _spawn(w, CATAPULT_SCENE, 1, Vector3(51, 5, 50))
	var ram2: FireRam = _spawn(w, FIRE_RAM_SCENE, 1, Vector3(49, 5, 50)) as FireRam
	var step: Vector3 = Vector3(0.4, 0, 0)
	g._tick_pos = g.position
	g._tick_trample(TICK)
	check(cat2.state != Unit.State.DEAD, "standing still he tramples no vehicle")
	g._tick_pos = g.position - step
	g._tick_trample(TICK)
	check(cat2.state == Unit.State.DEAD, "walking over the catapult wrecks it")
	check(ram2.state != Unit.State.DEAD and ram2._fire_hits == 1, "the ram under him lost one life")
	g._tick_pos = g.position - step
	g._tick_trample(TICK)
	check(ram2._fire_hits == 1, "not again inside the 2-s interval")
	_free_world(w)


# --- Haltung: stehend / gebueckt (2026-11-16) ---------------------------------------------

## Drei feindliche Huetten in der Handschlag-Flaeche des Golems an (50, 50.8);
## zurueck kommt die vordere (das Angriffsziel).
func _three_huts(w: Dictionary) -> Building:
	w.bm.place(HUT_SCENE, w.t1, Vector2i(51, 48), 0, true)
	w.bm.place(HUT_SCENE, w.t1, Vector2i(45, 48), 0, true)
	return w.bm.place(HUT_SCENE, w.t1, Vector2i(48, 53), 0, true)


## Der Golem steht oder ist gebueckt. Bodenangriffe schlaegt er gebueckt: aus dem
## Stand muss er sich erst buecken (0,4 s), danach kommt der Handschlag nach
## 0,35 s und alle 1,25 s wieder — statt 0,8 s Ausholen im 1,8-s-Takt.
func test_stance_crouching_makes_the_ground_attacks_faster() -> void:
	var w: Dictionary = _make_world()
	var front: Building = _three_huts(w)
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50.8))
	g.facing = Vector3(0, 0, 1)
	g.stomp_enabled = false   # the plain stance change is tested here; with the stomp she would jump into the crouch
	check(g.stance == Golem.STANCE_STAND and Golem.stance_for(Golem.ATTACK_SLAM) == Golem.STANCE_CROUCH
		and Golem.stance_for(Golem.ATTACK_DRUM) == Golem.STANCE_CROUCH
		and Golem.stance_for(Golem.ATTACK_KICK) == Golem.STANCE_STAND
		and Golem.stance_for(Golem.ATTACK_SWAT) == Golem.STANCE_STAND,
		"she starts standing; slam and drum need the crouch, kick and swat the stand")
	check_near(g.stance_switch_time(), Balance.GOLEM_STANCE_SWITCH_TIME, "level 0 switches in 0,4 s")
	check(Balance.GOLEM_STANCE_SWITCH_TIME == 0.4, "the documented 0,4 s")
	check_near(g.cooldown_for(Golem.ATTACK_SLAM),
		Balance.GOLEM_SLAM_COOLDOWN, "the crouched slam comes back after 1,25 s")
	check(Balance.GOLEM_SLAM_COOLDOWN == 1.25, "the documented 1,25 s")
	check(g.status_text().contains("Haltung: stehend"), "the panel shows the stance")
	g.order_attack_building(front)
	var t: float = 0.0
	var bent_at: float = -1.0
	var hits: Array = []
	var stage: int = 0
	var saw_switch_without_attack: bool = false
	for i in range(60):
		_tick_world(w)
		t += TICK
		if g.is_switching_stance() and g._pending_attack == &"":
			saw_switch_without_attack = true
		if bent_at < 0.0 and g.stance == Golem.STANCE_CROUCH:
			bent_at = t
		if is_instance_valid(front) and front.destruction_stage() > stage:
			stage = front.destruction_stage()
			hits.append(t)
		if hits.size() >= 3:
			break
	check(saw_switch_without_attack, "three buildings in the area: she bends down first, without striking yet")
	check(hits.size() >= 3, "then the slams land (%d)" % hits.size())
	if hits.size() >= 3:
		check_near(hits[0] - bent_at, Balance.GOLEM_SLAM_WINDUP,
			"the first slam lands 0,35 s after she is down (%.2f)" % (hits[0] - bent_at), TICK * 1.5)
		check_near(hits[1] - hits[0], g.cooldown_for(Golem.ATTACK_SLAM),
			"the next ones follow every 1,25 s — no bending in between (%.2f)" % (hits[1] - hits[0]), TICK * 1.5)
		check_near(hits[2] - hits[1], g.cooldown_for(Golem.ATTACK_SLAM), "and again", TICK * 1.5)
	check(g.stance == Golem.STANCE_CROUCH and g.status_text().contains("Haltung: gebückt"),
		"she stays crouched between the slams")
	check_near(g._slope_speed(0.0), 0.0, "crouched she cannot walk")
	_free_world(w)


## Zum Laufen muss er stehen: ein Bewegungsbefehl laesst ihn sofort aufstehen
## (auch kurz nach dem Buecken), er laeuft aber erst los, wenn er steht.
func test_stance_she_gets_up_before_she_walks() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(1, 0, 0)
	g.tick(TICK)
	g.stance = Golem.STANCE_CROUCH
	g._stance_age = 0.0
	var start: Vector3 = g.position
	g.order_move(Vector3(70, 5, 50))
	_tick_world(w)
	check(g.is_switching_stance() and g._stance_target == Golem.STANCE_STAND,
		"a move order gets her up at once, although she only just bent down")
	for i in range(3):
		_tick_world(w)
	check(_flat(g.position, start) < 0.01, "while getting up she does not move")
	for i in range(12):
		_tick_world(w)
	check(g.stance == Golem.STANCE_STAND and _flat(g.position, start) > 1.0,
		"once she stands she walks off (%.1f m)" % _flat(g.position, start))
	_free_world(w)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Haltung und Wahl: der Haltungswechsel kostet in der Rechnung ein Drittel seiner
## Zeit — die aktuelle Haltung hat also einen kleinen Vorteil (Hysterese). Und
## freiwillig wechselt sie fruehestens 3 s nach dem letzten Wechsel; bis dahin
## nimmt sie den besten Angriff ihrer Haltung — ausser sie kann aus ihrer Haltung
## gar nichts treffen.
func test_stance_choice_has_hysteresis_and_a_minimum_time() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	# A healthy enemy far down the kick's lane, beyond the slam's circle (it
	# reaches 3,8 m ahead, the lane 4,25 m) — and a weak one beside her in the circle.
	var far: Unit = _foe(w, 50.0, 54.1, 100000)
	var weak: Unit = _foe(w, 51.6, 51.2, 10)
	check(g._victims(Golem.ATTACK_KICK) == ([far] as Array[Unit])
		and g._victims(Golem.ATTACK_SLAM) == ([weak] as Array[Unit]),
		"the kick reaches only the far one, the ground attacks only the weak one")
	g.stance = Golem.STANCE_CROUCH
	check(g.attack_time(Golem.ATTACK_KICK) > g.cooldown_for(Golem.ATTACK_KICK)
		and is_equal_approx(g.attack_time(Golem.ATTACK_DRUM), g.cooldown_for(Golem.ATTACK_DRUM)),
		"crouched the kick carries the cost of getting up, the ground attacks do not")
	check(g._choose_attack() == Golem.ATTACK_KICK, "the kick at the healthy one is worth far more")
	# ... but she has only just bent down: she makes do with a ground attack.
	g._stance_age = 0.5
	g._attack_or_switch()
	check(g._pending_attack == Golem.ATTACK_SLAM and not g.is_switching_stance()
		and g.stance == Golem.STANCE_CROUCH,
		"too early to get up again: she slams the weak one from the crouch (%s)" % g._pending_attack)
	g._pending_attack = &""
	# With NOTHING to strike from the crouch the minimum time does not hold her.
	weak.position = Vector3(90, 5, 90)
	weak._sync_soa_pos()
	g._attack_or_switch()
	check(g.is_switching_stance() and g._stance_target == Golem.STANCE_STAND and g._pending_attack == &"",
		"nothing in reach of the ground attacks: she gets up at once, minimum time or not")
	for i in range(int(g.stance_switch_time() / TICK) + 2):
		g._tick_stance(TICK)
	check(g.stance == Golem.STANCE_STAND and not g.is_switching_stance(), "0,4 s later she stands")
	# The ordinary case: settled in the crouch, the better attack needs the stand.
	weak.position = Vector3(51.6, 5, 51.2)
	weak._sync_soa_pos()
	g.stance = Golem.STANCE_CROUCH
	g._stance_age = Balance.GOLEM_STANCE_MIN_TIME + 0.1
	g._attack_or_switch()
	check(g.is_switching_stance() and g._stance_target == Golem.STANCE_STAND,
		"after 3 s in the crouch she gets up for the kick")
	for i in range(int(g.stance_switch_time() / TICK) + 2):
		g._tick_stance(TICK)
	# And the other way round: standing with a crowd beside the lane, but she only just got up.
	for i in range(3):
		_foe(w, 51.4 + 0.4 * float(i), 51.6, 100000)
	check(Golem.stance_for(g._choose_attack()) == Golem.STANCE_CROUCH,
		"a crowd in the circle: a ground attack would be best")
	g._attack_or_switch()
	check(g._pending_attack == Golem.ATTACK_KICK and g.stance == Golem.STANCE_STAND,
		"but she only just got up: she kicks instead of bending down again")
	_free_world(w)


## Der Wechsel dauert mit der Groesse laenger (Wurzel der Groesse, hoechstens 2 s),
## und der Luftschlag geht nur im Stand.
func test_stance_switch_slows_with_size_and_swats_need_the_stand() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	_level_to(g, 7)
	check_near(g.stance_switch_time(), Balance.GOLEM_STANCE_SWITCH_TIME * sqrt(g.size_factor()),
		"level 7 needs %.2f s to bend down or get up" % g.stance_switch_time())
	var ship: Airship = _crewed_airship(w, 1, Vector3(50, 5, 53))
	g.facing = Vector3(0, 0, 1)
	g.stance = Golem.STANCE_CROUCH
	g._stance_age = 0.0
	g._air_cooldown = 0.0
	g._tick_air_strike(TICK)
	check(g._pending_attack == &"", "crouched she does not strike at the airship above her")
	g.stance = Golem.STANCE_STAND
	g._air_cooldown = 0.0
	g._tick_air_strike(TICK)
	check(g._pending_attack == Golem.ATTACK_SWAT and is_instance_valid(ship), "standing she does")
	_grow_to_the_end(g)
	check(g.stance_switch_time() <= Balance.GOLEM_STANCE_SWITCH_MAX and g.stance_switch_time() > 1.8,
		"the 100-m giant: %.2f s, never more than the 2-s cap" % g.stance_switch_time())
	_free_world(w)


# --- Reichweite mit den Gliedern, Sounds (2026-11-16) --------------------------------------

## Die Reichweite waechst mit den Gliedern: Groessenfaktor hoch 0,83 — so, dass
## bei 100 m 60 % des koerperproportionalen Werts herauskommen (38 m statt 63 m;
## vorher 9,9 m). Die Schneise ist so lang, die Haende landen so weit vorn; die
## GROESSE der Flaechen bleibt beim langsamen Wachstum.
func test_reach_grows_with_the_limbs() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	check_near(g.limb_factor(), 1.0, "a fresh golem: limb factor 1")
	check_near(g.reach(), Balance.GOLEM_REACH, "and the base reach of 3 m")
	check(Golem.limb_exponent() > 0.82 and Golem.limb_exponent() < 0.85,
		"the exponent is about 0,83 (%.3f)" % Golem.limb_exponent())
	_level_to(g, 6)
	check(g.reach() > 7.8 and g.reach() < 8.0, "level 6: %.1f m (was 5,3)" % g.reach())
	_level_to(g, 7)
	check(g.reach() > 11.1 and g.reach() < 11.3, "level 7: %.1f m (was 6,6)" % g.reach())
	check_near(g.limb_factor() - 1.0, (pow(g.size_factor(), Golem.limb_exponent()) - 1.0) * 1.1,
		"the gain over a fresh golem is 10 percent more than the plain power law gives", 0.0005)
	check(Balance.GOLEM_LIMB_GROWTH_BONUS == 1.1, "the documented 10 percent")
	check_near(g._kick_extent().x, Balance.GOLEM_KICK_LENGTH * g.kick_limb_factor(),
		"the kick's lane follows its own, slightly slower factor", 0.001)
	# Whatever stands at the edge of her reach, straight ahead, the kick can strike.
	var forward: Vector3 = Vector3(0, 0, 1)
	var right: Vector3 = Vector3(-1, 0, 0)
	g.facing = forward
	check(g._in_hit_zone(Golem.ATTACK_KICK, g.position + forward * g.reach(), forward, right),
		"a target at the edge of the reach lies in the kick's lane")
	check_near(Balance.GOLEM_KICK_WIDTH * g.reach_factor(), 1.8 * Golem.reach_factor_for(7),
		"the lane's WIDTH still follows the slow area growth", 0.001)
	_grow_to_the_end(g)
	check_near(g.limb_factor(), Golem.limb_factor_for(g.size_factor()), "at 100 m: limb factor %.1f" % g.limb_factor())
	check_near(pow(g.size_factor(), Golem.limb_exponent()), Balance.GOLEM_LIMB_SHARE_AT_MAX * g.size_factor(),
		"the power law alone gives 60 percent of a body-proportional growth there", 0.01)
	check(g.reach() > 41.4 and g.reach() < 41.8, "with the 10 percent on top the reach is %.1f m" % g.reach())
	check(g.aggro_radius() > g.reach(), "still inside her aggro radius")
	_free_world(w)


## Eigene Sounds: Anwahl und Befehle (UI) und je Angriff ein eigener Aufschlag.
func test_golem_has_its_own_sound_keys() -> void:
	check(SelectionManager.voice_key("select", false, true) == &"select_golem"
		and SelectionManager.voice_key("move", false, true) == &"move_golem",
		"a golem in the selection answers with select_golem / move_golem")
	check(SelectionManager.voice_key("select", true, true) == &"select_shaman",
		"the shaman in the group still overrides")
	check(SelectionManager.voice_key("select", false, false) == &"select_unit"
		and SelectionManager.voice_key("move", false, false) == &"move_unit",
		"without a golem (or without its sound file) the general sound plays")
	check(Golem.strike_sfx_key(Golem.ATTACK_KICK) == &"golem_kick"
		and Golem.strike_sfx_key(Golem.ATTACK_SLAM) == &"golem_slam"
		and Golem.strike_sfx_key(Golem.ATTACK_DRUM) == &"golem_drum"
		and Golem.strike_sfx_key(Golem.ATTACK_SWAT) == &"golem_swat",
		"every attack has its own impact sound")
	check(Golem.strike_sfx_key(&"something") == &"golem_strike", "anything else keeps the common strike sound")


# --- Golems untereinander, Ausholzeit des Handschlags, Tritt-Obergrenze (2026-11-16) -------

## Golems koennen nicht ineinander stehen: zwei halten die Summe ihrer
## Koerperradien Abstand, der kleinere weicht staerker aus. Mit normalen
## Einheiten kollidieren sie ab Stufe 1 weiterhin nicht.
func test_golems_do_not_stand_inside_one_another() -> void:
	var w: Dictionary = _make_world()
	var a: Golem = _golem(w, 0, Vector3(50, 5, 50))
	var b: Golem = _golem(w, 0, Vector3(50.4, 5, 50))
	_level_to(a, 1)
	_level_to(b, 1)
	check(a.ignores_unit_collision() and b.ignores_unit_collision(),
		"from level 1 on both ignore the ordinary unit collision")
	var need: float = (a.trample_radius() + b.trample_radius()) * Balance.GOLEM_BODY_GAP
	check(_flat(a.position, b.position) < need, "they start overlapping (0,4 m apart, %.2f m needed)" % need)
	for i in range(40):
		_tick_world(w)
	check(_flat(a.position, b.position) >= need - 0.02,
		"after a moment they stand the sum of their body radii apart (%.2f m)" % _flat(a.position, b.position))
	check(a.position.x < 49.8 and b.position.x > 50.6,
		"two golems of the same size both give way (%.2f and %.2f)" % [a.position.x, b.position.x])
	# A giant and a fresh golem, enemy tribes: the small one gives way.
	var big: Golem = _golem(w, 0, Vector3(20, 5, 20))
	_level_to(big, 7)
	var small: Golem = _golem(w, 1, Vector3(21, 5, 20))
	var big_start: Vector3 = big.position
	var small_start: Vector3 = small.position
	var need2: float = big.trample_radius() + small.trample_radius()
	for i in range(80):
		big._tick_golem_separation(TICK)
		small._tick_golem_separation(TICK)
	check(_flat(big.position, small.position) >= need2 - 0.02,
		"a giant and a fresh golem of another tribe separate too (%.1f m apart)" % _flat(big.position, small.position))
	check(_flat(small.position, small_start) > _flat(big.position, big_start) * 3.0,
		"the smaller body yields far more (%.2f m against %.2f m)"
			% [_flat(small.position, small_start), _flat(big.position, big_start)])
	# An ordinary enemy unit inside a level-1 golem is not pushed out, and does not push.
	var foe: Unit = _foe(w, 80.0, 80.0, 100000)
	var solo: Golem = _golem(w, 0, Vector3(80.2, 5, 80))
	_level_to(solo, 1)
	var solo_start: Vector3 = solo.position
	solo._tick_golem_separation(TICK)
	check(_flat(solo.position, solo_start) < 0.001 and is_instance_valid(foe),
		"ordinary units do not take part in this")
	_free_world(w)


## Buecken und Aufstehen dauern 0,4 s bei Startgroesse und wachsen mit der Wurzel
## der Groesse; der Handschlag holt aus der gebueckten Haltung 0,35 s aus. Aus dem
## Stand landet der erste Handschlag also nach 0,75 s.
func test_bending_takes_four_tenths_and_the_slam_winds_up_035() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	check_near(g.stance_switch_time(), 0.4, "level 0: bending down takes 0,4 s")
	check_near(Balance.GOLEM_SLAM_WINDUP, 0.35, "the slam's wind-up is 0,35 s")
	check_near(g.current_windup(Golem.ATTACK_SLAM), 0.35, "level 0: the slam lands 0,35 s after its start")
	check_near(g.stance_switch_time() + g.current_windup(Golem.ATTACK_SLAM), 0.75,
		"from the stand the first slam lands after 0,75 s")
	check_near(Golem.clip_rate(Golem.ATTACK_SLAM), 1.0, "the slam's clip plays as it was built")
	g._wind_up(Golem.ATTACK_SLAM)
	check_near(g._pending_time, 0.35, "winding up sets the 0,35 s")
	_level_to(g, 6)
	check(g.stance_switch_time() > 0.68 and g.stance_switch_time() < 0.70,
		"level 6: %.2f s (0,4 x root of the size)" % g.stance_switch_time())
	_level_to(g, 7)
	check(g.stance_switch_time() > 0.84 and g.stance_switch_time() < 0.86, "level 7: %.2f s" % g.stance_switch_time())
	_grow_to_the_end(g)
	check(g.stance_switch_time() > 1.82 and g.stance_switch_time() < 1.86,
		"100 m: %.2f s (below the 2-s cap)" % g.stance_switch_time())
	_free_world(w)


## Der Tritt trifft 40 % weniger Ziele als die Grundzahl (abgerundet): Stufe 0
## 3 statt 5. (Bis 2026-11-16: eines weniger.)
func test_kick_strikes_forty_percent_fewer_targets() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	check(g.max_targets_of(Golem.ATTACK_KICK) == 3 and g.max_targets_of(Golem.ATTACK_SLAM) == 5
		and g.max_targets_of(Golem.ATTACK_DRUM) == 6 and g.max_targets() == 5,
		"level 0: the kick strikes 3, the slam 5, the drum 6")
	var lane: Array = []
	for i in range(6):
		lane.append(_foe(w, 50.0 + (0.3 if i % 2 == 0 else -0.3), 50.8 + 0.5 * float(i), 100000))
	check(g._victims(Golem.ATTACK_KICK).size() == 6, "six enemies stand in the kick's lane")
	g._kick()
	var hit: int = 0
	for u in lane:
		if u.health < 100000:
			hit += 1
	check(hit == 3, "the kick strikes exactly three of them (struck %d)" % hit)
	_level_to(g, 7)
	check(g.max_targets_of(Golem.ATTACK_KICK) == 4 and g.max_targets_of(Golem.ATTACK_SLAM) == 8,
		"level 7: 4 against 8")
	_free_world(w)


## Der Radius von Handschlag und Trommeln: bis Stufe 7 das langsame
## Flaechenwachstum (5,8 m), danach gleichmaessig bis 12 m bei 100 m (vorher 8,6 m).
func test_slam_radius_reaches_twelve_metres() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	check_near(g.slam_radius(), Balance.GOLEM_SLAM_RADIUS, "level 0: 2,6 m")
	_level_to(g, 6)
	check_near(g.slam_radius(), Balance.GOLEM_SLAM_RADIUS * Golem.reach_factor_for(6), "level 6: unchanged (4,6 m)")
	_level_to(g, 7)
	var r7: float = g.slam_radius()
	check_near(r7, Balance.GOLEM_SLAM_RADIUS * Golem.reach_factor_for(7), "level 7: unchanged (%.1f m)" % r7)
	for i in range(Balance.GOLEM_GROWTH_KILLS):
		g._credit_kill()
	check(g.growth_steps == 1 and g.slam_radius() > r7 * 1.013 and g.slam_radius() < r7 * 1.015,
		"one growth step: about 1,4 percent more (%.3f m)" % g.slam_radius())
	check_near(Balance.GOLEM_KICK_WIDTH * g.reach_factor(), Balance.GOLEM_KICK_WIDTH * Golem.reach_factor_for(7) * 1.0075,
		"the lane's width keeps its 0,75 percent", 0.0005)
	_grow_to_the_end(g)
	check_near(g.slam_radius(), Balance.GOLEM_SLAM_RADIUS_AT_MAX, "at 100 m: 12 m", 0.001)
	check(Balance.GOLEM_SLAM_RADIUS_AT_MAX == 12.0, "the documented 12 m")
	# In play: an enemy 11 m from where the hands land is struck, one at 13 m is not.
	g.facing = Vector3(0, 0, 1)
	var hands: Vector3 = g.position + Vector3(0, 0, 1) * (Balance.GOLEM_SLAM_FORWARD * g.limb_factor())
	check(g._in_hit_zone(Golem.ATTACK_SLAM, hands + Vector3(11.0, 0, 5.0).normalized() * 11.0, Vector3(0, 0, 1), Vector3(-1, 0, 0))
		and not g._in_hit_zone(Golem.ATTACK_SLAM, hands + Vector3(0, 0, 13.0), Vector3(0, 0, 1), Vector3(-1, 0, 0)),
		"11 m from the hands is inside the circle, 13 m outside")
	_free_world(w)


## Der ausgewachsene Golem (100 m): noch einmal +3 Leben/s Dauerheilung (24), und
## die Lebensobergrenze ist 1000 + 53 x 7 = 1371.
func test_full_grown_golem_regenerates_three_more_and_has_1371_hp() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	_level_to(g, 7)
	while g.growth_steps < Golem.max_growth_steps() - 1:
		g._credit_kill()
	check_near(g.regen_per_second(), 21.0, "one step before the end: still 21 per second")
	_grow_to_the_end(g)
	check(g.is_full_size(), "grown to 100 m")
	check_near(g.regen_per_second(), 21.0 + Balance.GOLEM_FULL_SIZE_REGEN, "full-grown: 24 per second")
	check(g.max_health == 1000 + Golem.max_growth_steps() * 7 and g.max_health == 1371,
		"the health limit is 1371 (%d)" % g.max_health)
	g.health = 100
	g._tick_level_regen(1.0)
	check(g.health == 124, "one second heals 24")
	_free_world(w)


# --- Strecken beim Wachsen (2026-11-16) ----------------------------------------------------

## Waechst der Golem (Stufenaufstieg oder Wachstumsschritt), streckt er sich
## einmal: 1,0 s (bis 2026-11-16: 0,5 s), in denen er weder angreift noch laeuft. Die laufende
## Angriffsanimation wird vorher zu Ende gespielt, er steht danach und darf
## sofort weitermachen — auch sich sofort wieder buecken.
func test_growing_golem_stretches_for_a_second() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	check(not g._stretch_queued and not g.is_stretching(), "a fresh golem owes no stretch")
	check_near(Balance.GOLEM_GROW_TIME, 1.0, "the stretch takes a second")
	check_near(Golem.GROW_CLIP_LENGTH, 1.0, "and so does its clip")
	# She winds up a kick; the kill that lifts her to level 1 lands with it.
	g._wind_up(Golem.ATTACK_KICK)
	var clip_time: float = g._attack_anim_left
	check_near(clip_time, 1.2, "the kick's animation takes 1,2 s at level 0")
	_level_to(g, 1)
	check(g._stretch_queued and g.level == 1, "the level-up owes a stretch")
	var t: float = 0.0
	var started_at: float = -1.0
	var ended_at: float = -1.0
	var rooted: bool = true
	var no_new_attack: bool = true
	for i in range(40):
		g._tick_pending_attack(TICK)
		g._tick_stretch(TICK)
		t += TICK
		if g.is_stretching() and started_at < 0.0:
			started_at = t
		if g.is_stretching():
			rooted = rooted and is_zero_approx(g._slope_speed(0.0))
			no_new_attack = no_new_attack and not g._begin_stance(Golem.STANCE_CROUCH)
		if started_at >= 0.0 and not g.is_stretching() and ended_at < 0.0:
			ended_at = t
	check(started_at >= clip_time - 0.001 and started_at <= clip_time + TICK * 1.5,
		"the stretch waits for the kick's animation to play out (begins at %.1f s)" % started_at)
	check_near(ended_at - started_at, Balance.GOLEM_GROW_TIME,
		"and takes 1,0 s (%.2f)" % (ended_at - started_at), TICK * 1.5)
	check(rooted, "while stretching she does not walk")
	check(no_new_attack, "nor does she bend down or strike")
	check(g.stance == Golem.STANCE_STAND and g.stance_settled() and not g._stretch_queued,
		"afterwards she stands and may go on at once — bending down included")
	# While the stretch is still owed she begins no new attack.
	var foe: Unit = _foe(w, 50.0, 51.5, 100000)
	g._stretch_queued = true
	g._attack_or_switch()
	check(g._pending_attack == &"" and is_instance_valid(foe), "an owed stretch goes before the next attack")
	# From the crouch she straightens up with it.
	g.stance = Golem.STANCE_CROUCH
	g._attack_anim_left = 0.0
	g._tick_stretch(TICK)
	check(g.is_stretching() and g.stance == Golem.STANCE_STAND, "crouched, she rises into the stretch")
	for i in range(12):
		g._tick_stretch(TICK)
	g._attack_or_switch()
	check(g._pending_attack == Golem.ATTACK_KICK, "after the stretch the attack follows at once")
	# The growth steps beyond level 7 stretch too.
	var giant: Golem = _golem(w, 0, Vector3(20, 5, 20))
	_level_to(giant, 7)
	giant._stretch_queued = false
	for i in range(Balance.GOLEM_GROWTH_KILLS):
		giant._credit_kill()
	check(giant.growth_steps == 1 and giant._stretch_queued, "a growth step beyond level 7 owes a stretch as well")
	_free_world(w)


# --- Sprung (stomp), Zielzahl je Angriff, Trampeln auf Gebaeude (2026-11-16) -----------------

## Zielzahl je Angriff: GOLEM_MAX_TARGETS ist die Grundzahl; der Tritt trifft 40 %
## weniger, das Trommeln ein Viertel mehr, der Sprung doppelt so viele (wie das
## Trampeln: Nutzer 2026-11-16, vorher die Haelfte mehr) —
## abgerundet. Handschlag und Trampeln halten sich an die Grundzahl.
func test_every_attack_has_its_share_of_the_target_count() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	check(Balance.GOLEM_TARGET_PERCENT_KICK == 60 and Balance.GOLEM_TARGET_PERCENT_DRUM == 125
		and Balance.GOLEM_TARGET_PERCENT_STOMP == 200, "kick 60 %, drum 125 %, stomp 200 % of the base count")
	var want: Dictionary = {0: [5, 3, 6, 10], 1: [6, 3, 7, 12], 4: [7, 4, 8, 14], 7: [8, 4, 10, 16]}
	for lv in [0, 1, 4, 7]:
		_level_to(g, lv)
		var got: Array = [g.max_targets_of(Golem.ATTACK_SLAM), g.max_targets_of(Golem.ATTACK_KICK),
			g.max_targets_of(Golem.ATTACK_DRUM), g.max_targets_of(Golem.ATTACK_STOMP)]
		check(got == want[lv] and g.max_targets() == want[lv][0],
			"level %d: slam/kick/drum/stomp %s (want %s), trampling the base %d" % [lv, got, want[lv], g.max_targets()])
	_grow_to_the_end(g)
	check(g.max_targets() == 25 and g.max_targets_of(Golem.ATTACK_KICK) == 15
		and g.max_targets_of(Golem.ATTACK_DRUM) == 31 and g.max_targets_of(Golem.ATTACK_STOMP) == 50,
		"100 m: base 25, kick 15, drum 31, stomp 50")
	_free_world(w)


## SPRUNG: Schaden rundherum um sie selbst — der Trampelradius und zwei Drittel
## mehr —, doppelt so viel wie ein Trampeltick, niemand wird geworfen; eigene
## Einheiten trifft er nie. Danach ist sie gebueckt.
func test_stomp_strikes_all_around_her_with_twice_the_trample_damage() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	check_near(Balance.GOLEM_STOMP_RADIUS_FACTOR, 5.0 / 3.0, "two thirds more than the trample radius")
	check_near(g.stomp_radius(), g.trample_radius() * 5.0 / 3.0, "the stomp's radius follows the body (%.2f m)" % g.stomp_radius())
	check(g.attack_damage(Golem.ATTACK_STOMP) == 2 * g.trample_damage() and g.attack_damage(Golem.ATTACK_STOMP) == 2,
		"level 0: twice the trample tick = 2")
	var inside: Array = [_foe(w, 50.0, 51.2, 1000), _foe(w, 50.0, 48.8, 1000), _foe(w, 51.2, 50.0, 1000),
		_foe(w, 48.8, 50.0, 1000)]
	var outside: Array = [_foe(w, 50.0, 51.4, 1000), _foe(w, 48.6, 50.0, 1000)]
	var friend: Unit = _spawn(w, BRAVE_SCENE, 0, Vector3(50.5, 5, 50.5))
	friend.max_health = 1000
	friend.health = 1000
	check(g._victims(Golem.ATTACK_STOMP).size() == 4, "four enemies stand inside 1,29 m — ahead, behind, left and right")
	g._land_attack(Golem.ATTACK_STOMP)
	var all_hit: bool = true
	var none_thrown: bool = true
	for u in inside:
		all_hit = all_hit and u.health == 998
		none_thrown = none_thrown and u.state != Unit.State.THROWN and u.state != Unit.State.ROLL
	check(all_hit, "all four take the 2 damage — the one behind her as well")
	check(none_thrown, "the stomp throws nobody")
	check(outside[0].health == 1000 and outside[1].health == 1000, "1,4 m away is outside")
	check(friend.health == 1000, "own units are never hit")
	check(g.stance == Golem.STANCE_CROUCH and g._stomp_landed, "after the landing she is crouched")
	_level_to(g, 7)
	check(g.attack_damage(Golem.ATTACK_STOMP) == 8, "level 7 (21 m): 2 x 4 = 8, no level bonus on top")
	check_near(g.stomp_radius(), Balance.GOLEM_BODY_HALF_WIDTH * g.size_factor() * 5.0 / 3.0, "and the circle grows with the body")
	_free_world(w)


## Der Sprung trifft doppelt so viele Ziele wie die Grundzahl (Stufe 0: 10),
## die naechsten zuerst; Gebaeude in seiner Flaeche verlieren eine Stufe.
func test_stomp_strikes_half_again_as_many_targets_and_buildings() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	var ring: Array = []
	for i in range(12):
		var a: float = TAU * float(i) / 12.0
		ring.append(_foe(w, 50.0 + cos(a) * (0.5 + 0.05 * float(i)), 50.0 + sin(a) * (0.5 + 0.05 * float(i)), 1000))
	check(g._victims(Golem.ATTACK_STOMP).size() == 12, "twelve enemies stand inside the stomp's circle")
	g._land_attack(Golem.ATTACK_STOMP)
	var hit: int = 0
	for u in ring:
		if u.health < 1000:
			hit += 1
	check(hit == 10, "the stomp strikes exactly ten of them (struck %d)" % hit)
	check(ring[10].health == 1000 and ring[11].health == 1000, "the two farthest are spared")
	var w2: Dictionary = _make_world()
	var g2: Golem = _golem(w2, 0, Vector3(50, 5, 50))
	g2.facing = Vector3(0, 0, 1)
	var a_hut: Building = w2.bm.place(HUT_SCENE, w2.t1, Vector2i(51, 48), 0, true)
	var b_hut: Building = w2.bm.place(HUT_SCENE, w2.t1, Vector2i(45, 48), 0, true)
	var far_hut: Building = w2.bm.place(HUT_SCENE, w2.t1, Vector2i(48, 56), 0, true)
	check(g2._buildings_in_area(Golem.ATTACK_STOMP).size() == 2, "two huts stand inside the stomp's circle, the third does not")
	check(Balance.GOLEM_STOMP_BUILDING_STAGES == 1, "a building loses one stage, as with every attack")
	g2._land_attack(Golem.ATTACK_STOMP)
	check(a_hut.destruction_stage() == 1 and b_hut.destruction_stage() == 1 and far_hut.destruction_stage() == 0,
		"both lose a stage, the hut farther away none")
	_free_world(w2)
	_free_world(w)


## Der Sprung geht nur aus dem Stand. Der Schaden faellt bei der Landung (0,6 s),
## der Clip faengt den Sprung danach in die gebueckte Haltung ab (bis 1,0 s) —
## das gehoert zum Angriff. Steht sie im Kampf und ihr bester Angriff ist ein
## Bodenangriff, bleibt sie unten und schlaegt ohne Haltungswechsel weiter.
func test_stomp_lands_after_the_jump_and_leaves_her_crouched() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	check(Golem.stance_for(Golem.ATTACK_STOMP) == Golem.STANCE_STAND and g.can_stomp(), "the stomp is struck standing")
	check_near(Golem.attack_windup(Golem.ATTACK_STOMP), 0.6, "the landing comes 0,6 s after the start")
	check_near(g.cooldown_for(Golem.ATTACK_STOMP), 1.0, "its cooldown is the clip's length (1,0 s)")
	check_near(float(Golem.CLIP_LENGTH[Golem.ATTACK_STOMP]), 1.0, "the clip takes 1,0 s")
	check(Golem.ATTACK_CLIPS.has(Golem.ATTACK_STOMP) and Golem.strike_sfx_key(Golem.ATTACK_STOMP) == &"golem_stomp",
		"it is an attack clip with its own sound")
	g.stance = Golem.STANCE_CROUCH
	check(not g.can_stomp(), "crouched she cannot jump")
	g.stance = Golem.STANCE_STAND
	g._stance_age = 0.0
	check(not g.can_stomp(), "nor right after a stance change")
	g._stance_age = 1000.0
	var foe: Unit = _foe(w, 50.0, 51.0, 100000)
	g._begin_attack(foe)
	g._in_melee = true
	g._wind_up(Golem.ATTACK_STOMP)
	check(g.stance == Golem.STANCE_STAND and g._pending_attack == Golem.ATTACK_STOMP, "she takes off standing")
	check_near(g._attack_anim_left, 1.0, "the whole attack takes 1,0 s")
	check_near(g._attack_cooldown, 1.0, "and the next one may follow right after it")
	var t: float = 0.0
	var hit_at: float = -1.0
	var stood_in_the_air: bool = true
	var got_up_early: bool = false
	for i in range(15):
		if hit_at < 0.0:
			stood_in_the_air = stood_in_the_air and g.stance == Golem.STANCE_STAND
		g._tick_pending_attack(TICK)
		g._tick_stance(TICK)
		g._tick_stretch(TICK)
		t += TICK
		if hit_at < 0.0 and foe.health < 100000:
			hit_at = t
			check(g.stance == Golem.STANCE_CROUCH, "with the landing she is crouched")
		if hit_at >= 0.0 and g.is_switching_stance():
			got_up_early = true
	check_near(hit_at, 0.6, "the damage falls at the landing (%.1f s)" % hit_at, TICK * 1.5)
	check(stood_in_the_air, "until then she counts as standing")
	check(foe.health == 100000 - 2, "one landing, one damage tick")
	check(not got_up_early and g.stance == Golem.STANCE_CROUCH and not g._stomp_landed,
		"in the fight, with a ground attack as her best: she stays down")
	check_near(g._slope_speed(0.0), 0.0, "and crouched she is rooted")
	g._attack_or_switch()
	check(g._pending_attack == Golem.ATTACK_DRUM and not g.is_switching_stance(),
		"the ground attack follows without a stance switch")
	_free_world(w)


## Hat sie nach dem Sprung nichts mehr zu schlagen (oder muss sie laufen), richtet
## sie sich sofort wieder auf: das dauert so lange wie ein Haltungswechsel und
## wartet nicht auf die Mindestzeit der Haltung — aber erst, wenn der Clip
## ausgelaufen ist.
func test_stomp_gets_her_up_again_when_nothing_is_left_to_strike() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	g._wind_up(Golem.ATTACK_STOMP)
	var t: float = 0.0
	var crouched_at: float = -1.0
	var up_began: float = -1.0
	var stood_at: float = -1.0
	for i in range(30):
		g._tick_pending_attack(TICK)
		g._tick_stance(TICK)
		g._tick_stretch(TICK)
		t += TICK
		if crouched_at < 0.0 and g.stance == Golem.STANCE_CROUCH:
			crouched_at = t
		if up_began < 0.0 and g.is_switching_stance():
			up_began = t
			check(g._stance_target == Golem.STANCE_STAND and not g.stance_settled(),
				"she gets up although the stance has not settled — it belongs to the attack")
		if up_began >= 0.0 and stood_at < 0.0 and g.stance == Golem.STANCE_STAND and not g.is_switching_stance():
			stood_at = t
	check_near(crouched_at, 0.6, "crouched from the landing on (%.1f s)" % crouched_at, TICK * 1.5)
	check(up_began >= 1.0 - 0.001 and up_began <= 1.0 + TICK * 2.5,
		"the getting-up waits for the clip to settle (begins at %.1f s)" % up_began)
	check_near(stood_at - up_began, g.stance_switch_time(),
		"and takes as long as a stance switch (%.2f s)" % (stood_at - up_began), TICK * 1.5)
	_free_world(w)


## Die Wahl mit dem Sprung, als Plan gerechnet (Einleitung + 3 Angriffe, Schaden
## je Sekunde): der Sprung kostet seine Abklingzeit, bringt seinen eigenen
## Schaden und endet gebueckt. Er wird nur erwogen, wenn er selbst etwas trifft.
func test_attack_choice_weighs_the_stomp_as_a_plan() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	check_near(g.stomp_plan_value(), 0.0, "nobody around: the stomp is worth nothing")
	# One healthy enemy 3 m ahead: in reach of kick and slam, outside the stomp.
	var far: Unit = _foe(w, 50.0, 53.0, 100000)
	check_near(g.attack_worth(Golem.ATTACK_STOMP), 0.0, "an enemy 3 m ahead is outside the stomp's circle")
	check_near(g.stomp_plan_value(), 0.0, "a stomp that strikes nothing is never weighed — she does not jump just to get down")
	check(g._choose_attack() == Golem.ATTACK_KICK, "so she kicks")
	far.health = 0
	far.state = Unit.State.DEAD
	# Two enemy huts beside her, inside the stomp's circle and inside the slam's.
	w.bm.place(HUT_SCENE, w.t1, Vector2i(51, 48), 0, true)
	w.bm.place(HUT_SCENE, w.t1, Vector2i(45, 48), 0, true)
	var lead: float = g.attack_worth(Golem.ATTACK_STOMP)
	var slam: float = g.attack_worth(Golem.ATTACK_SLAM)
	check_near(lead, 60.0, "two huts in the stomp's circle are worth 2 x 30")
	check_near(slam, 60.0, "and as much to the slam")
	var plan: float = (lead + 3.0 * slam) / (1.0 + 3.0 * 1.25)
	check_near(g.stomp_plan_value(), plan, "stomp, then three slams: %.1f per second" % plan)
	check_near(g.attack_value(Golem.ATTACK_STOMP), plan, "attack_value reports the plan")
	check(plan > g.attack_value(Golem.ATTACK_SLAM),
		"that beats bending down first (%.1f against %.1f)" % [plan, g.attack_value(Golem.ATTACK_SLAM)])
	check(g._choose_attack() == Golem.ATTACK_STOMP, "she opens with the stomp")
	g._stance_age = 0.0
	check(g._choose_attack() == Golem.ATTACK_SLAM, "right after a stance change she does not jump: the slam")
	g._stance_age = 1000.0
	g.stomp_enabled = false
	check(g._choose_attack() == Golem.ATTACK_SLAM, "switched off: the slam")
	g.stomp_enabled = true
	g.stance = Golem.STANCE_CROUCH
	check(g._choose_attack() == Golem.ATTACK_SLAM, "crouched the stomp is not on offer")
	_free_world(w)


## Im Ablauf: zwischen zwei Huetten oeffnet sie mit dem Sprung (beide verlieren
## eine Stufe), bleibt unten und schlaegt mit dem Handschlag weiter — ohne einen
## einzigen Haltungswechsel.
func test_stomp_opens_the_assault_and_the_slams_follow_without_a_switch() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	var a_hut: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(51, 48), 0, true)
	var b_hut: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(45, 48), 0, true)
	g.order_attack_building(a_hut)
	var saw_stomp: bool = false
	var saw_slam: bool = false
	var saw_switch: bool = false
	var both_after_stomp: bool = false
	for i in range(70):
		_tick_world(w)
		if g._pending_attack == Golem.ATTACK_STOMP:
			saw_stomp = true
		if g._pending_attack == Golem.ATTACK_SLAM:
			saw_slam = true
		if g.is_switching_stance():
			saw_switch = true
		if saw_stomp and not saw_slam and g._pending_attack == &"" and not both_after_stomp \
				and is_instance_valid(a_hut) and is_instance_valid(b_hut):
			both_after_stomp = a_hut.destruction_stage() == 1 and b_hut.destruction_stage() == 1
		if not is_instance_valid(a_hut) or a_hut.destruction_stage() >= 3:
			break
	check(saw_stomp, "she opens with the stomp")
	check(both_after_stomp, "its landing takes a stage off both huts")
	check(saw_slam and not saw_switch, "then she slams from the crouch — no stance switch at all")
	check(not is_instance_valid(a_hut) or a_hut.destruction_stage() >= 3, "and the hut goes down stage by stage")
	_free_world(w)


## Trampeln auf Gebaeude: seit 2026-11-16 nur noch alle 4 s eine Stufe (die halbe
## Schadensrate); Fahrzeuge behalten ihre 2 s.
func test_trampling_takes_a_building_stage_only_every_four_seconds() -> void:
	check_near(Balance.GOLEM_TRAMPLE_BUILDING_INTERVAL, 4.0, "a building stage every 4 s")
	check_near(Balance.GOLEM_TRAMPLE_VEHICLE_INTERVAL, 2.0, "vehicles keep their 2 s")
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	_level_to(g, 7)
	var hut: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(49, 49), 0, true)
	var step: Vector3 = Vector3(0.4, 0, 0)
	var stages_at: Array = []
	var t: float = 0.0
	for i in range(85):
		g._tick_pos = g.position - step
		g._tick_trample(TICK)
		t += TICK
		if hut.destruction_stage() > stages_at.size():
			stages_at.append(t)
	check(stages_at.size() == 3, "8,5 s of walking over it: three stages (%d)" % stages_at.size())
	if stages_at.size() >= 3:
		check_near(stages_at[1] - stages_at[0], 4.0, "4 s between the stages (%.1f)" % (stages_at[1] - stages_at[0]), TICK * 1.5)
		check_near(stages_at[2] - stages_at[1], 4.0, "and again", TICK * 1.5)
	_free_world(w)


## Tritt-Schneise (2026-11-16): bei 100 m 10 % kuerzer als der Gliederfaktor
## allein ergaebe, auf Stufe 0 unveraendert; vorn wie hinten.
func test_kick_lane_is_ten_percent_shorter_at_the_top() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	check_near(g.kick_limb_factor(), 1.0, "level 0: unchanged")
	check_near(g._kick_extent().x, Balance.GOLEM_KICK_LENGTH, "4,25 m ahead")
	_level_to(g, 7)
	check(g.kick_limb_factor() < g.limb_factor() and g.kick_limb_factor() > 1.0,
		"level 7: shorter than the limbs alone (%.2f against %.2f)" % [g.kick_limb_factor(), g.limb_factor()])
	_grow_to_the_end(g)
	check_near(g.kick_limb_factor(), 0.9 * g.limb_factor(), "100 m: 90 percent of the limb factor", 0.0001)
	var lane: Vector2 = g._kick_extent()
	check_near(lane.x, 0.9 * Balance.GOLEM_KICK_LENGTH * g.limb_factor(), "%.1f m ahead" % lane.x, 0.001)
	check_near(lane.y, 0.9 * Balance.GOLEM_KICK_LENGTH * Balance.GOLEM_KICK_BACK_SHARE * g.limb_factor(),
		"%.1f m behind" % lane.y, 0.001)
	check(lane.x > g.reach(), "still longer than her reach (%.1f m)" % g.reach())
	_free_world(w)


## Trommeln (2026-11-16): sein Kreis ist auf allen Stufen 10 % groesser als der
## des Handschlags, um denselben Mittelpunkt.
func test_drum_circle_is_ten_percent_larger_than_the_slam() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	g.snap_heading()
	var forward: Vector3 = Vector3(0, 0, 1)
	var right: Vector3 = Vector3(-1, 0, 0)
	for lv in [0, 3, 6, 7]:
		_level_to(g, lv)
		check_near(g.ground_radius(Golem.ATTACK_DRUM), 1.1 * g.slam_radius(), "level %d: drum %.2f m, slam %.2f m"
			% [lv, g.ground_radius(Golem.ATTACK_DRUM), g.slam_radius()], 0.0001)
		check_near(g.ground_radius(Golem.ATTACK_SLAM), g.slam_radius(), "and the slam keeps its own")
		var tip: float = Balance.GOLEM_SLAM_FORWARD * g.limb_factor() + g.slam_radius() + 0.05 * g.slam_radius()
		var p: Vector3 = g.position + forward * tip
		check(g._in_hit_zone(Golem.ATTACK_DRUM, p, forward, right) and not g._in_hit_zone(Golem.ATTACK_SLAM, p, forward, right),
			"level %d: 5 percent beyond the slam's edge the drum still strikes, the slam does not" % lv)
	_grow_to_the_end(g)
	check_near(g.ground_radius(Golem.ATTACK_DRUM), 13.2, "100 m: 13,2 m (slam 12 m)", 0.001)
	_free_world(w)


# --- Rueckstoss nach Groesse (Nutzervorgabe 2026-11-16) -----------------------------

## Unter 8 m wirft und rollt nichts; ab 8 m steigt jede Chance stufenweise: Tritt
## +10 % je 5 m (bis jeden), Handschlag werfen und rollen je +8 % je 10 m (Grenze je
## 40 %), Trommeln nur rollen, +8 % je 10 m ohne eigene Grenze.
func test_knockback_chances_climb_with_the_size() -> void:
	var c: Callable = func(h: float, step: float, per: float, cap: float) -> float:
		return Golem.knock_chance(h, step, per, cap)
	var k: Array = [Balance.GOLEM_KICK_THROW_STEP_M, Balance.GOLEM_KICK_THROW_PER_STEP, Balance.GOLEM_KICK_THROW_MAX]
	var sl: Array = [Balance.GOLEM_SLAM_LIFT_STEP_M, Balance.GOLEM_SLAM_LIFT_PER_STEP, Balance.GOLEM_SLAM_LIFT_MAX]
	var sr: Array = [Balance.GOLEM_SLAM_ROLL_STEP_M, Balance.GOLEM_SLAM_ROLL_PER_STEP, Balance.GOLEM_SLAM_ROLL_MAX]
	var dr: Array = [Balance.GOLEM_DRUM_ROLL_STEP_M, Balance.GOLEM_DRUM_ROLL_PER_STEP, Balance.GOLEM_DRUM_ROLL_MAX]
	for h in [2.0, 4.725, 7.99]:
		check(c.call(h, k[0], k[1], k[2]) == 0.0 and c.call(h, sl[0], sl[1], sl[2]) == 0.0
			and c.call(h, sr[0], sr[1], sr[2]) == 0.0 and c.call(h, dr[0], dr[1], dr[2]) == 0.0,
			"%.2f m: nothing is thrown or rolled" % h)
	check_near(c.call(8.0, k[0], k[1], k[2]), 0.10, "kick: 8 m 10 %")
	check_near(c.call(12.9, k[0], k[1], k[2]), 0.10, "kick: 12,9 m still 10 %")
	check_near(c.call(13.0, k[0], k[1], k[2]), 0.20, "kick: 13 m 20 %")
	check_near(c.call(48.0, k[0], k[1], k[2]), 0.90, "kick: 48 m 90 %")
	check_near(c.call(53.0, k[0], k[1], k[2]), 1.0, "kick: from 53 m every survivor")
	check_near(c.call(100.0, k[0], k[1], k[2]), 1.0, "kick: no more than 100 %")
	check_near(c.call(8.0, sl[0], sl[1], sl[2]), 0.08, "slam throw: 8 m 8 %")
	check_near(c.call(18.0, sl[0], sl[1], sl[2]), 0.16, "slam throw: 18 m 16 %")
	check_near(c.call(48.0, sl[0], sl[1], sl[2]), 0.40, "slam throw: 48 m 40 %")
	check_near(c.call(100.0, sl[0], sl[1], sl[2]), 0.40, "slam throw: capped at 40 %")
	check_near(c.call(38.0, sr[0], sr[1], sr[2]), 0.32, "slam roll: 38 m 32 %")
	check_near(c.call(100.0, sr[0], sr[1], sr[2]), 0.40, "slam roll: capped at 40 %")
	check_near(c.call(98.0, dr[0], dr[1], dr[2]), 0.80, "drum roll: 98 m 80 %")
	check_near(c.call(118.0, dr[0], dr[1], dr[2]), 0.96, "drum roll: 118 m 96 % (no cap of its own)")
	check_near(c.call(128.0, dr[0], dr[1], dr[2]), 1.0, "drum roll: from 128 m every survivor")


func test_a_small_golem_throws_and_rolls_nobody() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	check(g.height_m() < Balance.GOLEM_KNOCK_MIN_HEIGHT, "a fresh golem is below 8 m")
	check(g.kick_throw_chance() == 0.0 and g.slam_lift_chance() == 0.0 and g.slam_roll_chance() == 0.0
		and g.drum_roll_chance() == 0.0, "all its chances are 0")
	var still: bool = true
	for i in range(20):
		var v: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.0, 5, 51.5))
		v.max_health = 1000
		v.health = 1000
		g._smash()
		g._kick()
		g._land_attack(Golem.ATTACK_DRUM, Balance.GOLEM_DRUM_HITS.size() - 1)
		still = still and v.state != Unit.State.THROWN and v.state != Unit.State.ROLL and v.health < 1000
		v.take_damage(100000)
		w.um.tick(TICK)
	check(still, "slam, kick and drum hurt, but nobody flies or rolls")
	_free_world(w)


func test_the_chances_follow_the_golems_own_height() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	_level_to(g, 3)   # 8,2 m
	check(g.height_m() >= 8.0 and g.height_m() < 13.0, "level 3 is just above 8 m (%.1f m)" % g.height_m())
	check_near(g.kick_throw_chance(), 0.10, "kick 10 %")
	check_near(g.slam_lift_chance(), 0.08, "slam throw 8 %")
	check_near(g.slam_roll_chance(), 0.08, "slam roll 8 %")
	check_near(g.drum_roll_chance(), 0.08, "drum roll 8 %")
	_level_to(g, 7)   # 21,2 m
	check_near(g.kick_throw_chance(), 0.30, "the giant (21 m): kick 30 %")
	check_near(g.slam_lift_chance(), 0.16, "slam throw 16 %")
	check_near(g.drum_roll_chance(), 0.16, "drum roll 16 %")
	_free_world(w)


func test_drum_never_throws_and_rolls_by_its_chance() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	g.knock_height_override = 128.0   # drum roll 100 %
	var thrown: bool = false
	var all_rolled: bool = true
	for i in range(10):
		var v: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.0, 5, 51.5))
		v.max_health = 1000
		v.health = 1000
		g._land_attack(Golem.ATTACK_DRUM, Balance.GOLEM_DRUM_HITS.size() - 1)
		thrown = thrown or v.state == Unit.State.THROWN
		all_rolled = all_rolled and v.state == Unit.State.ROLL
		v.take_damage(100000)
		w.um.tick(TICK)
	check(not thrown, "the drum never throws")
	check(all_rolled, "at 100 percent every survivor of its last hit rolls")
	_free_world(w)


## Bugmeldung 2026-11-16: zum Ziel geschickt, drehte sich der Golem manchmal erst in
## die falsche Richtung. Der Weg aus der Warteschlange begann mit der Mitte seiner
## eigenen Zelle — stand er davor, lag sie hinter ihm.
func test_a_queued_path_does_not_turn_her_the_wrong_way_first() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50.5, 5, 50.9))   # in front of the centre of her cell
	g.facing = Vector3(0, 0, 1)
	g.snap_heading()
	g._slew_heading(0.0)
	var target: Vector3 = Vector3(60, 5, 70)   # ahead and to the left
	var path: PackedVector3Array = w.nav.find_path(g.position, target)
	check(w.nav.world_to_cell(path[0]) == w.nav.world_to_cell(g.position),
		"the raw path starts in her own cell (the case of the report)")
	var cells: PackedVector2Array = PackedVector2Array()
	for p in path:
		var cell: Vector2i = w.nav.world_to_cell(p)
		cells.append(Vector2(cell.x, cell.y))
	g._pending_target = target
	g._path_request_id += 1
	g._set_state(Unit.State.MOVE)
	g._apply_worker_path(g._path_request_id, cells)
	check(w.nav.world_to_cell(g._path[0]) != w.nav.world_to_cell(g.position),
		"the queued path no longer starts in her own cell")
	var want: float = atan2(target.x - g.position.x, target.z - g.position.z)
	var away: float = 0.0
	var prev: float = absf(wrapf(want - atan2(g.heading().x, g.heading().z), -PI, PI))
	for i in range(30):
		g.tick(0.05)
		var now: float = absf(wrapf(want - atan2(g.heading().x, g.heading().z), -PI, PI))
		if now > prev + 0.001:
			away += now - prev
		prev = now
	check(away < deg_to_rad(50.0), "she does not swing away from the goal first (%.0f degrees)" % rad_to_deg(away))
	_free_world(w)


# --- Befehle haben Vorrang (Bugmeldung 2026-11-16) ------------------------------------

## Ein Angriffsbefehl auf eine bestimmte Einheit wurde ignoriert, wenn andere um sie
## herum kaempften: der Golem wechselte jedes Mal auf den Naechsten in Reichweite.
## Ein Golem wird nicht im Nahkampf gebunden - das befohlene Ziel bleibt.
func test_an_ordered_target_is_kept_while_others_fight_around_her() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	var far: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector3(58, 5, 50))    # 8 m: out of reach
	var near: Array = []
	for at in [Vector3(51.5, 5, 50), Vector3(50, 5, 51.8), Vector3(50, 5, 48.2)]:
		near.append(_spawn(w, WARRIOR_SCENE, 1, at))                     # in reach, fighting her
	for u in near + [far]:
		u.max_health = 100000
		u.health = 100000
	for u in near:
		u.order_attack(g)
	far.order_move(Vector3(58, 5, 50))   # stands still: she has to walk to it
	w.commands.order_attack([g] as Array[Unit], far)
	check(g.attack_target == far and g._target_ordered, "ordered onto the far one")
	var kept: bool = true
	var start: float = _flat_dist(g.position, far.position)
	for i in range(30):
		_tick_world(w)
		kept = kept and g.attack_target == far
	check(kept, "she keeps the ordered target the whole time (target now %s)" % [g.attack_target])
	check(_flat_dist(g.position, far.position) < start - 0.5,
		"and walks toward it through the crowd (%.1f m left of %.1f)" % [_flat_dist(g.position, far.position), start])
	_free_world(w)


## Bugmeldung 2026-11-16: "bueckt sich, steht wieder auf und tritt". Jeder Zielwechsel
## setzte den Nahkampf-Merker zurueck, und die Haltung las das als "muss laufen" — hier
## der Wechsel auf einen Feind in Reichweite, weil das alte Ziel ausser Reichweite stand.
func test_a_target_switch_in_reach_keeps_her_crouched() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.stomp_enabled = false
	var far: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector3(58, 5, 50))    # 8 m: out of reach
	var near: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector3(51.5, 5, 50))  # 1,5 m: in reach
	for u in [far, near]:
		u.max_health = 100000
		u.health = 100000
		u.order_move(u.position)
	g._begin_attack(far)
	g.facing = Vector3(1, 0, 0)
	g.snap_heading()
	g.stance = Golem.STANCE_CROUCH
	g._stance_target = Golem.STANCE_CROUCH
	g._stance_age = 0.5   # just bent down: the stance's minimum time is not over
	g._in_melee = true
	g.tick(TICK)
	check(g.attack_target == near, "she switches to the enemy in reach")
	check(g.stance == Golem.STANCE_CROUCH and not g.is_switching_stance(),
		"and stays crouched (no getting up for a target right in front of her)")
	var kinds: Array = []
	for i in range(40):
		g.tick(TICK)
		if g._pending_attack != &"" and not kinds.has(g._pending_attack):
			kinds.append(g._pending_attack)
	check(not kinds.has(Golem.ATTACK_KICK) and not kinds.is_empty(),
		"she strikes from the crouch, no kick (%s)" % [kinds])
	_free_world(w)


## Derselbe Fehler auf dem zweiten Weg: das Ziel stirbt, die Zielwahl nimmt das naechste.
func test_she_stays_crouched_when_her_target_dies_and_the_next_stands_close() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.stomp_enabled = false
	var first: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector3(51.5, 5, 50))
	var second: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector3(51.2, 5, 51.0))
	second.max_health = 100000
	second.health = 100000
	for u in [first, second]:
		u.order_move(u.position)
	g._begin_attack(first)
	g.facing = Vector3(1, 0, 0)
	g.snap_heading()
	g.stance = Golem.STANCE_CROUCH
	g._stance_target = Golem.STANCE_CROUCH
	g._stance_age = 0.5
	g._in_melee = true
	first.take_damage(100000, g)
	g.tick(TICK)
	check(g.attack_target == second, "she takes on the next enemy")
	check(g.stance == Golem.STANCE_CROUCH and not g.is_switching_stance(), "and stays crouched")
	_free_world(w)


# --- Expliziter Gebaeudeangriff (Bugmeldung 2026-11-16) -------------------------------

## Bei einem BEFOHLENEN Gebaeudeangriff griff der Golem Einheiten an, die gar nicht
## beim Gebaeude standen. Jetzt nur noch Einheiten in seiner Reichweite des Gebaeudes.
func test_an_ordered_building_assault_only_fights_units_near_the_building() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	var hut: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(48, 55), 0, true)
	check(hut != null, "an enemy hut stands ahead")
	var away: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector3(43, 5, 49))    # 7 m aside of her, far from the hut
	away.max_health = 100000
	away.health = 100000
	away.order_move(away.position)
	w.commands.order_attack_building([g] as Array[Unit], hut)
	check(g.has_ordered_building(), "ordered onto the hut")
	check(hut.footprint_distance_to(Vector2(away.position.x, away.position.z)) > g.reach(),
		"the warrior stands out of her reach of the hut")
	var ignored: bool = true
	for i in range(40):
		_tick_world(w)
		ignored = ignored and g.attack_target != away
	check(ignored and g.attack_building == hut, "she leaves the warrior alone and keeps to the hut")
	check(hut.health < hut.max_health, "and strikes the hut")
	# A unit right at the hut is fought (her blows land there anyway).
	var guard: Unit = _spawn(w, WARRIOR_SCENE, 1, hut.center_world() + Vector3(-2.5, 0, 0))
	guard.max_health = 100000
	guard.health = 100000
	guard.order_move(guard.position)
	check(hut.footprint_distance_to(Vector2(guard.position.x, guard.position.z)) <= g.reach(),
		"the guard stands in her reach of the hut")
	var fought: bool = false
	for i in range(40):
		_tick_world(w)
		fought = fought or g.attack_target == guard
	check(fought, "the guard at the hut is fought")
	# It runs off: she drops it and goes back to the hut.
	guard.position = Vector3(30, 5, 50)
	guard._sync_soa_pos()
	for i in range(3):
		_tick_world(w)
	check(g.attack_target != guard and g.attack_building == hut, "a guard that leaves the hut is let go")
	_free_world(w)


## Ein Gebaeude, das sie sich SELBST ausgesucht hat, weicht wie bisher jedem Feind im
## Aggro-Radius.
func test_a_building_she_picked_herself_gives_way_to_units() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	var hut: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(48, 55), 0, true)
	var away: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector3(44, 5, 50))
	away.max_health = 100000
	away.health = 100000
	away.order_move(away.position)
	g._begin_attack_building(hut)
	check(not g.has_ordered_building(), "picked by herself, not ordered")
	var fought: bool = false
	for i in range(40):
		_tick_world(w)
		fought = fought or g.attack_target == away
	check(fought, "the warrior in her aggro radius comes first")
	_free_world(w)
