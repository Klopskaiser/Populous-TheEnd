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
	check(spell.max_charges == 2 and is_equal_approx(spell.charge_cost, 800.0)
		and is_equal_approx(spell.cast_range, 10.0), "2 Ladungen, 800 Mana (2026-11-18, vorher 900), 10 m")
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
	# The right leg kicks (2026-11-18: each leg has its own lane, kick_leg_offset beside her
	# middle — right is -x when she faces +z). Sideways distances count from that lane's middle.
	g.kick_side = 1.0
	var lx: float = 50.0 - g.kick_leg_offset()
	var near: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(lx, 5, 51.0))        # along 1,0
	var far: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(lx, 5, 54.2))         # along 4,2
	var edge: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(lx - 0.8, 5, 53.0))  # side 0,8
	var out_side: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(lx - 1.0, 5, 53.0))   # side 1,0 > 0,9
	var out_far: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(lx, 5, 54.5))     # along 4,5 > 4,25
	var out_back: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(lx, 5, 46.8))    # along -3,2 < -2,98
	var friend: Unit = _spawn(w, BRAVE_SCENE, 0, Vector3(lx, 5, 52.0))
	for u in [near, far, edge, out_side, out_far, out_back, friend]:
		u.max_health = 1000
		u.health = 1000
	g._kick()
	var hit: int = 1000 - Balance.GOLEM_KICK_DAMAGE
	check(near.health == hit and far.health == hit, "the whole lane ahead takes GOLEM_KICK_DAMAGE")
	check(edge.health == hit, "0,8 m aside is inside the 1,8-m-wide lane")
	# (The kick strikes three targets at level 0: the one behind her gets a kick of
	# its own — the three in front are in the air by then.)
	var behind: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(lx, 5, 47.5))      # along -2,5: the backswing
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
	# Since 2026-11-16 he levels only where others can strike him: his target
	# radius, half the radius of the selection ring (user spec).
	check_near(g.target_radius(), g.selection_ring_radius() * 0.5,
		"the target radius is half the selection ring's radius")
	check_near(g.flatten_radius(), g.target_radius(), "and so is the ground he levels")
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
	check(hut.health == before - Golem.building_damage_for(g.attack_damage(Golem.ATTACK_SLAM)),
		"one strike = half the slam's damage in hit points (2026-11-18; %d)" % (before - hut.health))
	# The owner's own golem never damages the owner's hut.
	var own: Golem = _golem(w, 1, Vector3(50, 5, 46))
	own.facing = Vector3(0, 0, 1)
	var mid: int = hut.health
	own._smash()
	check(hut.health == mid, "an own building is never struck")
	_free_world(w)


## Ein Gebaeude nimmt seit 2026-11-18 Lebenspunkte: die Haelfte dessen, was der Angriff einer Einheit
## naehme. Gegen ein einzelnes Gebaeude gewinnt damit der Angriff mit den meisten Lebenspunkten je
## Sekunde — auf Stufe 0 der Tritt (22 alle 1,8 s gegen 12 alle 1,25 s).
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
	var kick: int = Golem.building_damage_for(g.attack_damage(Golem.ATTACK_KICK))
	check(hut.health == before - kick, "the golem walks up and kicks: half the kick's damage (%d ticks, %d)" % [ticks, before - hut.health])
	check(hut.destruction_stage() == 0, "no stage yet: that takes 30 percent of its hit points")
	check(g.state != Unit.State.RAID and g.in_world, "it strikes from OUTSIDE (never a raider)")
	check(g.stance == Golem.STANCE_STAND, "standing: the kick takes the most hit points a second")
	var after_first: int = hut.health
	for i in range(11):   # 1,1 s: still reloading
		_tick_world(w)
	check(hut.health == after_first, "no second blow inside the kick's 1,8-s cooldown")
	for i in range(9):   # past 1,8 s
		_tick_world(w)
	check(hut.health == after_first - kick, "the second blow lands after the cooldown")
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
		and Balance.GOLEM_HP_PER_KILL == 15, "and healed exactly 15 (user spec 2026-11-18, before 10)")

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
## aufsummiert 5, 11, 18, 25, 33, 42, 62). Jeder Aufstieg bringt 20 s Lebenszeit
## (zusaetzlich zu den 6 s je Kill).
func test_levels_follow_the_kills_up_to_seven() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	check(g.level == 0 and is_equal_approx(g.size_factor(), 1.0), "a fresh golem is level 0")
	check(Balance.GOLEM_LEVEL_KILLS == ([5, 6, 7, 7, 8, 9, 20] as Array[int]),
		"kills per level: 5, 6, 7, 7, 8, 9 and 20 for the giant")
	for i in range(4):
		g._credit_kill()
	check(g.level == 0, "four kills are not a level yet")
	var before: float = g.life_left
	g._credit_kill()
	check(g.level == 1, "the fifth kill makes level 1")
	check_near(g.life_left, before + Balance.GOLEM_LIFE_PER_KILL + Balance.GOLEM_LEVEL_LIFETIME,
		"the level-up adds 20 s on top of the kill's 6 s")
	var sums: Array = [0, 5, 11, 18, 25, 33, 42, 62]
	var sums_ok: bool = true
	for lvl in range(1, 8):
		sums_ok = sums_ok and Golem.kills_for_level(lvl) == sums[lvl] \
			and Golem.level_for_kills(sums[lvl] - 1) == lvl - 1 \
			and Golem.level_for_kills(sums[lvl]) == lvl
	check(sums_ok, "the levels are reached after 5, 11, 18, 25, 33, 42 and 62 kills")
	check(Golem.level_for_kills(1000) == 7, "level 7 is the last one")
	while g.kills < 61:
		g._credit_kill()
	check(g.level == 6, "61 kills: still level 6")
	g._credit_kill()
	check(g.level == 7 and Balance.GOLEM_MAX_LEVEL == 7, "the 62nd kill makes level 7")
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
		and g.trample_damage() == maxi(1, int(round(g.height_m() / 3.2))),
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

	# Level 7, the giant (user spec 2026-11-17): a level like the others — 20 percent
	# bigger, reach and areas 10 percent, +5 damage, the regeneration +3/s.
	_level_to(g, 7)
	check_near(g.size_factor(), s6 * 1.2, "level 7: the body is 20 percent bigger than at 6 (16,9 m)")
	check_near(g.reach_factor(), r6 * 1.1, "reach and areas are 10 percent bigger than at 6")
	check_near(g.speed, Balance.GOLEM_SPEED * sqrt(s6 * 1.2), "the speed follows the size")
	check(g.attack_damage(Golem.ATTACK_KICK) == dmg6 + 5
		and g.attack_damage(Golem.ATTACK_SLAM) == Balance.GOLEM_SLAM_DAMAGE + 35
		and g.trample_damage() == 5,
		"level 7 adds 5 damage like the others; trampling is 16,9 m / 3,2 = 5")
	g.health = 100
	g._tick_level_regen(1.0)
	check(g.health == 127, "level 7 heals 6 + 21 per second (3 more than level 6)")
	check(g.max_health == Balance.GOLEM_MAX_HP_CAP + Balance.GOLEM_GIANT_MAX_HP and g.max_health == 1030,
		"its health limit is 1000 + 30 (user spec 2026-11-18)")
	_free_world(w)


## Grundheilung 6 LP/s schon auf Stufe 0 (Nutzervorgabe 2026-11-18), dazu ab Stufe 1 3 Leben je Sekunde und
## Stufe — bis zur Lebensobergrenze, nie darueber; die Erholung gewoehnlicher Einheiten gilt nicht.
func test_level_regeneration_heals_three_per_second_and_level() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.health = 500
	g._tick_level_regen(1.0)
	check(g.health == 506, "level 0 heals its base 6 per second")
	_level_to(g, 1)
	g.health = 500
	g._tick_level_regen(1.0)
	check(g.health == 509, "level 1 heals 6 + 3 per second")
	_level_to(g, 4)
	g.health = 500
	for i in range(10):
		g._tick_level_regen(TICK)
	check(g.health == 518, "level 4 heals 6 + 12 per second (in 0,1-s ticks)")
	# The ordinary units' rest healing (5/s after 8 s out of combat) does not apply to her.
	var lone: Golem = _golem(w, 0, Vector3(90, 5, 90))
	lone.health = 300
	var before: int = lone.health
	for i in range(int(12.0 / TICK)):
		lone._tick_regen(TICK)
	check(lone.health == before, "no rest healing of ordinary units (12 s out of combat: %d)" % (lone.health - before))
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
	# Trample damage = body height in metres / 3,2, rounded, at least 1 (user spec;
	# 25 at 80 m since 2026-11-17).
	var hit: int = g.trample_damage()
	check(hit == 2 and is_equal_approx(Balance.GOLEM_TRAMPLE_HEIGHT_PER_DAMAGE, 3.2),
		"at level 1 (5,7 m tall) trampling does 2 damage")
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


## Nach Stufe 7 waechst der Gigant weiter: alle 20 Kills 8 % groesser (aufgezinst),
## Wirkflaechen 1,96 %, das Tempo nur geringfuegig — bis 80 m (Nutzer 2026-11-17).
## Je Schritt +18 Lebensobergrenze; Dauerheilung und Schaden steigen nicht mehr.
func test_giant_keeps_growing_beyond_level_seven_up_to_eighty_metres() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	_level_to(g, 7)
	check(g.growth_steps == 0, "level 7 just reached: no growth step yet")
	var size7: float = g.size_factor()
	var reach7: float = g.reach()
	var trample7: float = g.trample_radius()
	var speed7: float = g.speed
	var dmg7: int = g.attack_damage(Golem.ATTACK_KICK)
	check(Golem.kills_for_growth_step(1) == 21 and Golem.kills_for_growth_step(2) == 22
		and Golem.kills_for_growth_step(6) == 27 and Golem.kills_for_growth_step(21) == 73,
		"each growth step 8 % more kills than the one before, rounded down: 21, 22 ... 27 ... 73 (user spec 2026-11-18)")
	check(Golem.kills_for_level(Balance.GOLEM_MAX_LEVEL) + Golem.kills_for_growth_steps(21) == 912,
		"80 m after 912 kills")
	for i in range(Golem.kills_for_growth_step(1) - 1):
		g._credit_kill()
	check(g.growth_steps == 0 and is_equal_approx(g.size_factor(), size7),
		"20 more kills: nothing yet")
	g._credit_kill()
	check(g.growth_steps == 1 and g.level == 7, "the 21st kill is one growth step (still level 7)")
	check_near(g.size_factor(), size7 * 1.08, "the body is 8 percent bigger")
	check_near(g.reach(), Balance.GOLEM_REACH * Golem.limb_factor_for(size7 * 1.08),
		"the reach grows with the limbs", 0.0005)
	check(g.reach() > reach7 * 1.06 and g.reach() < reach7 * 1.08,
		"between 6 and 8 percent a step (%.3f)" % (g.reach() / reach7))
	check_near(g.reach_factor(), Golem.reach_factor_for(7) * 1.019645, "the strike areas 1,96 percent", 0.0005)
	check_near(g.trample_radius(), trample7 * 1.08, "the body radius grows with the BODY (8 percent)", 0.0005)
	check(g.speed > speed7 and g.speed < speed7 * 1.01, "the speed rises only slightly (%.3f)" % g.speed)
	for i in range(Golem.kills_for_growth_step(2)):
		g._credit_kill()
	check_near(g.size_factor(), size7 * 1.08 * 1.08, "the growth compounds", 0.0005)
	check(g.attack_damage(Golem.ATTACK_KICK) == dmg7, "the damage stays where it was")
	check(g.max_health == Balance.GOLEM_MAX_HP_CAP + Balance.GOLEM_GIANT_MAX_HP + 2 * Balance.GOLEM_GROWTH_MAX_HP
		and Balance.GOLEM_GROWTH_MAX_HP == 30,
		"every growth step lifts the health limit by 30 (two steps: 1090)")
	check_near(g.regen_per_second(), 29.0, "the regeneration grows by 1 per step (6 + 21 + 2 = 29)")
	g.health = 100
	g._tick_level_regen(1.0)
	check(g.health == 129, "one second heals 29")
	# The cap: 80 m, however many kills follow.
	g.kills += 5000
	g._credit_kill()
	check_near(g.pick_size_m().y, Balance.GOLEM_MAX_HEIGHT, "the figure stops at 80 m", 0.01)
	check(g.growth_steps == Golem.max_growth_steps() and Golem.max_growth_steps() == 21,
		"that is 21 growth steps (420 kills beyond level 7)")
	var top_speed: float = g.speed
	g.kills += 5000
	g._credit_kill()
	check(is_equal_approx(g.speed, top_speed) and g.speed < 9.0,
		"areas and speed stop growing with it (%.2f m/s)" % g.speed)
	_free_world(w)


## Der Angriffstakt waechst langsam mit der Koerperhoehe: 1,8 s bei Startgroesse,
## 3 s bei 80 m (Nutzer 2026-11-17; vorher 4 s bei 100 m). Die Animationen werden entsprechend langsamer, dauern aber nie
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
	check(g.strike_cooldown() > 1.95 and g.strike_cooldown() < 2.05,
		"level 7 (16,9 m): the cooldown has grown only a little (%.2f s)" % g.strike_cooldown())
	var fits: bool = true
	for kind in [Golem.ATTACK_SLAM, Golem.ATTACK_KICK, Golem.ATTACK_SWAT, Golem.ATTACK_DRUM]:
		var played: float = float(Golem.CLIP_LENGTH[kind]) / (g.attack_speed(kind) * Golem.clip_rate(kind))
		fits = fits and played <= g.cooldown_for(kind) + 0.0001 \
			and g.current_windup(kind) < g.cooldown_for(kind)
	check(fits, "at level 7 every attack animation fits into its cooldown")
	check_near(float(Golem.CLIP_LENGTH[Golem.ATTACK_KICK]) / g.attack_speed(Golem.ATTACK_KICK),
		g.strike_cooldown(), "the giant's kick fills the whole cooldown — no idling in between")
	_grow_to_the_end(g)
	check_near(g.strike_cooldown(), Balance.GOLEM_STRIKE_COOLDOWN_MAX, "at 80 m: one attack every 3 s")
	check(Balance.GOLEM_STRIKE_COOLDOWN_MAX == 3.0, "the documented 3 s")
	check_near(float(Golem.CLIP_LENGTH[Golem.ATTACK_KICK]) / g.attack_speed(Golem.ATTACK_KICK), 3.0,
		"and the kick animation stretches over those 3 s")
	# In play: after a kick the next attack waits for the grown cooldown.
	g._wind_up(Golem.ATTACK_KICK)
	check_near(g._attack_cooldown, 3.0, "winding up sets the attack cooldown of the current size")
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
	# In play: an enemy behind the full-grown giant is not struck before he has turned
	# — by the DIRECTED attacks; the stomp needs no aim (test_the_stomp_needs_no_turn).
	var w2: Dictionary = _make_world()
	var g2: Golem = _golem(w2, 0, Vector3(50, 5, 50))
	g2.stomp_enabled = false
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


## Der Sprung braucht kein Anvisieren (Nutzervorgabe 2026-11-16): steht der Feind
## hinter dem Riesen, springt er sofort, statt sich erst umzudrehen — die Wahl
## rechnet die Drehzeit jedem gerichteten Angriff an, dem Sprung nicht.
func test_the_stomp_needs_no_turn() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	_grow_to_the_end(g)
	for i in range(100):   # let the stretch after the growth play out first
		if not g.is_stretching() and not g._stretch_queued:
			break
		g.tick(TICK)
	g.facing = Vector3(0, 0, 1)
	g.snap_heading()
	g.tick(TICK)
	var foe: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50, 5, 44))
	foe.max_health = 100000
	foe.health = 100000
	g.order_attack(foe)
	var first: StringName = &""
	var turned: bool = true
	var at: int = -1
	for i in range(200):
		g.tick(TICK)
		if g._pending_attack != &"":
			first = g._pending_attack
			turned = g.is_turned_to_facing()
			at = i
			break
	check(first == Golem.ATTACK_STOMP, "the first attack is the stomp (got %s)" % first)
	check(not turned, "struck while still turned away from the target")
	check(g.turn_time_needed() > 1.0, "a directed attack would have waited over a second")
	check(at >= 0 and at < int(1.0 / TICK), "so he strikes within the first second (tick %d)" % at)
	_free_world(w)


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
	check(lv.attack_damage(Golem.ATTACK_DRUM) == 98, "level 7 adds 8 like every level (14 + 7 + 35/3 per hit, 98)")
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
				check(hut.max_health - hut.health == 7 * hit_times.size(), "hit %d: the building loses half of it, every hit (%d)" % [hit_times.size(), hut.max_health - hut.health])
			seen = now
	check(hit_times.size() == 3, "three hits landed (%d)" % hit_times.size())
	if hit_times.size() == 3:
		check(absf(hit_times[0] - 0.35) < 0.11 and absf(hit_times[1] - 0.8) < 0.11
			and absf(hit_times[2] - 1.25) < 0.11,
			"at 0,35 / 0,8 / 1,25 s (%.2f / %.2f / %.2f)" % [hit_times[0], hit_times[1], hit_times[2]])
	check(crowd[0].health == 100000 - 42, "each unit took 42 in all")
	check(not thrown_early, "the first two hits only hurt, nobody is thrown yet")
	check(hut.max_health - hut.health == 21, "the building lost 3 x 7 hit points (2026-11-18)")
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


## Eigene Schneise je Bein (Nutzervorgabe 2026-11-18): ab 30 m beruehren sich die Schneisen in der
## Mitte, darunter ueberlappen sie; getreten wird mit dem Bein, das mehr trifft.
func test_each_leg_kicks_into_its_own_lane() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	var half: float = Golem.KICK_HALF_WIDTH * g.reach_factor()
	check(g.kick_leg_offset() > 0.0 and g.kick_leg_offset() < half, "level 0: the lanes overlap (offset %.2f, half width %.2f)" % [g.kick_leg_offset(), half])
	# A foe well to her left (+x when she faces +z): the left leg kicks.
	var left_foe: Unit = _foe(w, 50.0 + g.kick_leg_offset() + half * 0.8, 52.0, 1000)
	check(g.attack_worth(Golem.ATTACK_KICK) > 0.0 and g.kick_side < 0.0, "a foe on her left: the left leg")
	left_foe.health = 0
	left_foe.state = Unit.State.DEAD
	var a: Unit = _foe(w, 50.0 - g.kick_leg_offset() - half * 0.8, 52.0, 1000)
	var b: Unit = _foe(w, 50.0 - g.kick_leg_offset() - half * 0.5, 53.0, 1000)
	g.attack_worth(Golem.ATTACK_KICK)
	check(g.kick_side > 0.0, "two on her right: the right leg")
	g._wind_up(Golem.ATTACK_KICK)
	check(g._clip_for(Golem.ATTACK_KICK) == Golem.ATTACK_KICK, "(and the right leg's clip)")
	_free_world(w)
	var big: Golem = GOLEM_SCENE.instantiate() as Golem
	while not big.can_sit():
		big._credit_kill()
	check_near(big.kick_leg_offset(), Golem.KICK_HALF_WIDTH * big.reach_factor(), "31,3 m: the two lanes just touch in the middle")
	check_near(big._kick_extent().x, 19.2, "31,3 m: 5 % shorter ahead (%.1f m)" % big._kick_extent().x, 0.1)
	big.free()


## Clipwahl: der Tritt wechselt das Bein; der Schlag nach einem Luftschiff
## richtet sich nach dessen Hoehe am Koerper (oben: swat, Brust bis Huefte:
## swipe, darunter: Tritt).
func test_attack_clips_alternate_legs_and_follow_the_airships_height() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	# Each leg has its own lane (2026-11-18): the clip follows the leg; with nothing to choose
	# between them, the legs take turns.
	g.kick_side = 1.0
	check(g._clip_for(Golem.ATTACK_KICK) == Golem.ATTACK_KICK, "right leg: kick")
	g.kick_side = -1.0
	check(g._clip_for(Golem.ATTACK_KICK) == Golem.CLIP_KICK_LEFT, "left leg: kick_l")
	g._wind_up(Golem.ATTACK_KICK)
	var first: float = g.kick_side
	g._pending_attack = &""
	g._wind_up(Golem.ATTACK_KICK)
	check(g.kick_side != first, "the kick alternates between the right and the left leg")
	g._pending_attack = &""
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
	var td: int = Golem.building_damage_for(g.trample_damage())
	check(hut.max_health - hut.health == td, "walking over it takes half the trampling damage off the hut (%d)" % td)
	g._tick_pos = g.position - step
	g._tick_trample(TICK)
	check(hut.max_health - hut.health == td, "not again inside the interval")
	for i in range(int(Balance.GOLEM_TRAMPLE_BUILDING_INTERVAL / TICK) + 1):
		g._tick_pos = g.position - step
		g._tick_trample(TICK)
	check(hut.max_health - hut.health == 2 * td, "after the interval the next")
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


## ...und im Spiel: erst ab 30 m Koerperhoehe (Nutzervorgabe 2026-11-18; vorher ab Stufe 7).
func test_only_the_level_seven_giant_levels_the_ground() -> void:
	var w: Dictionary = _make_world(8.0)
	for vz in range(40, 61):
		for vx in range(40, 61):
			w.td.set_vertex_height(vx, vz, 8.0 + 0.6 * sin(float(vx) * 1.3) * cos(float(vz) * 1.1))
	w.nav.update_region(Rect2i(0, 0, w.td.size, w.td.size))
	var g: Golem = _golem(w, 0, Vector3(50, w.td.get_height(50.0, 50.0), 50))
	g.terrain_ctx = w.ctx
	_level_to(g, 7)
	check(not g.flattens(), "(level 7, 16,9 m: below 30 m)")
	for i in range(30):
		_tick_world(w)
	check(not (Golem.flatten_plan(w.td, g.position, g.flatten_radius(), 1.0, 0.25).indices
		as PackedInt32Array).is_empty(), "a 17-m golem leaves the bumpy ground as it is")
	while not g.flattens():
		g._credit_kill()
	g._stretch_queued = false
	check(g.height_m() >= 30.0, "from 30 m on she levels (%.1f m)" % g.height_m())
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
	check(g.health == after_contact - 15 + 6, "one second of fire costs the full 15 HP, her base healing gives 6 back (lost %d)"
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
## von 15 bei Startgroesse bis 80 kurz vor 80 m; der ausgewachsene nimmt
## hoechstens 40. Getroffen wird sein KOERPER, nicht nur sein Mittelpunkt.
func test_catapult_hits_hurt_more_the_bigger_the_golem_is() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(60, 5, 60))
	var shock: int = Balance.SIEGE_SHOT_SHOCK_DAMAGE
	check(Golem.siege_damage_for_height(shock, Balance.GOLEM_HEIGHT) == shock
		and Golem.siege_damage_for_height(shock, 79.9) == Balance.GOLEM_SIEGE_DAMAGE_MAX
		and Balance.GOLEM_SIEGE_DAMAGE_MAX == 80,
		"from the plain 15 at the starting size up to 80 just below 80 m")
	check(g.siege_shock_damage(shock, 0.0) == shock, "a fresh golem takes the plain shock damage")
	_level_to(g, 7)
	g.health = g.max_health
	var expect7: int = Golem.siege_damage_for_height(shock, g.height_m())
	check(expect7 > shock and expect7 == 26, "level 7 (16,9 m): %d per direct hit" % expect7)
	# A real shot: the stone lands 2 m beside his centre — inside his body circle (2,8 m).
	var shot: SiegeShot = SiegeShot.new()
	shot.setup(1, Vector3(40, 5, 60), g.position + Vector3(2.0, 0, 0), null, w.um, w.td, w.bm)
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
	check(not is_instance_valid(hut) or hut.health < hut.max_health,
		"walking through the hut tramples it (hit points since 2026-11-18)")
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
	check(text.contains("Heilung: 6.0 LP/s") and text.contains("Tempo: %.1f m/s" % g.current_speed()),
		"healing and walking speed, as for every golem (user spec 2026-11-18)")
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
	# The giant picks a fight 25 m away on his own; a fresh golem ignores one at 12 m.
	var far: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(75, 5, 50))
	far.max_health = 100000
	far.health = 100000
	for i in range(60):
		_tick_world(w)
		if g.state == Unit.State.ATTACK:
			break
	check(g.state == Unit.State.ATTACK and g.attack_target == far,
		"the idle giant turns on an enemy 25 m away")
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


## Bodenangriff auch gegen Gebaeude: stehen mehrere feindliche Gebaeude in seiner Flaeche, bueckt sie
## sich (jedes nimmt Lebenspunkte), statt eines zu treten.
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
	check(Golem.stance_for(g._choose_attack()) == Golem.STANCE_CROUCH,
		"two buildings beside her, none in the kick's lane: a ground attack (%s)" % g._choose_attack())
	var c: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(48, 53), 0, true)
	check(c != null, "a third hut in front of her")
	check(g._buildings_in_area(Golem.ATTACK_SLAM).size() == 3, "all three lie in the slam's area")
	check(Golem.stance_for(g._choose_attack()) == Golem.STANCE_CROUCH, "three buildings: a ground attack, not the kick (%s)" % g._choose_attack())
	var bd: int = Golem.building_damage_for(g.attack_damage(Golem.ATTACK_SLAM))
	g._smash()
	check(a.max_health - a.health == bd and b.max_health - b.health == bd and c.max_health - c.health == bd,
		"the slam takes its hit points off each of the three")
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
	# The hands come down limb_factor() x 1,2 m ahead; since 2026-11-18 the circle around them
	# grows with the body from 30 m on and reaches a little behind her middle at 80 m.
	var hands: float = Balance.GOLEM_SLAM_FORWARD * g.limb_factor()
	var slam_near: float = hands - g.slam_radius()
	var heel_at: float = minf(-0.5, slam_near - 0.5)
	check(-heel_at < body, "(behind the circle of the hands, still under her body: %.1f m)" % heel_at)
	var at: Callable = func(along: float, side: float) -> Vector3:
		return g.position + forward * along + right * side
	# SLAM
	check(not g._in_hit_zone(Golem.ATTACK_SLAM, at.call(1.0, body - 0.5), forward, right),
		"slam: the front half of her body circle no longer counts (2026-11-18), only the hands' circle")
	check(g._in_hit_zone(Golem.ATTACK_SLAM, at.call(hands + g.slam_radius() - 0.2, 0.0), forward, right)
		and not g._in_hit_zone(Golem.ATTACK_SLAM, at.call(hands + g.slam_radius() + 0.5, 0.0), forward, right),
		"slam: ahead as far as the circle of the hands reaches (%.1f m)" % (hands + g.slam_radius()))
	check(not g._in_hit_zone(Golem.ATTACK_SLAM, at.call(heel_at, 0.0), forward, right),
		"slam: at her heels, beyond that circle, nothing is struck although it is under her body")
	check(not g._in_hit_zone(Golem.ATTACK_SLAM, at.call(-1.0, body - 0.5), forward, right),
		"slam: the BACK half of the body circle is not added")
	# KICK
	var half: float = Balance.GOLEM_KICK_WIDTH * 0.5 * r
	g.kick_side = 1.0
	var mid: float = g.kick_leg_offset()   # the right leg's lane
	check(g._in_hit_zone(Golem.ATTACK_KICK, at.call(0.0, mid + half - 0.1), forward, right)
		and not g._in_hit_zone(Golem.ATTACK_KICK, at.call(0.0, mid + half + 0.5), forward, right),
		"kick: only the lane counts, also at the body — it is not widened to the body circle")
	check(g._in_hit_zone(Golem.ATTACK_KICK, at.call(body - 0.2, 0.0), forward, right)
		and g._in_hit_zone(Golem.ATTACK_KICK, at.call(-(body - 0.2), 0.0), forward, right),
		"kick: the lane runs through the whole body circle, ahead and behind")
	var lane: Vector2 = g._kick_extent()
	check_near(lane.x, Balance.GOLEM_KICK_LENGTH * g.kick_limb_factor() * Balance.GOLEM_BODY_KICK_FRONT_SHARE,
		"kick: the lane is as long as her leg reaches, from 30 m 5 % shorter ahead")
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
## seine Stufe erlaubt (5, 6, 6, 6, 7, 8, 8, 8; nach Stufe 7 jeder
## Wachstumsschritt eines mehr). Einheiten vor Gebaeuden; das Angriffsziel immer.
func test_target_cap_limits_every_damage_tick() -> void:
	check(Balance.GOLEM_MAX_TARGETS == ([5, 6, 6, 6, 7, 8, 8, 8] as Array[int]),
		"targets per level 0-7: 5, 6, 6, 6, 7, 8, 8, 8")
	check(Golem.max_targets_for(7, 2) == 10 and Golem.max_targets_for(7, 3) == 11
		and Golem.max_targets_for(7, Golem.max_growth_steps()) == 29,
		"beyond level 7 every growth step adds one (%d at 80 m)"
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
	check(hut4.health < hut4.max_health and hit4 == 4,
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
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50.8))
	g.facing = Vector3(0, 0, 1)
	g.stomp_enabled = false   # the plain stance change is tested here; with the stomp she would jump into the crouch
	# Foes of 30 HP beside the kick's lanes, in the slam's circle: the quick slam (no overkill) wins —
	# since 2026-11-18 buildings no longer make the case (they take hit points now).
	var crowd: Array = []
	for i in range(5):   # five: the slam's cap (with six the drum's bigger cap would win)
		var side: float = 1.0 if i % 2 == 0 else -1.0
		crowd.append(_foe(w, 50.0 + side * (1.6 + 0.3 * float(i / 2)), 52.2 + 0.2 * float(i / 2), 30))
	var front: Unit = crowd[0]
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
	g.order_attack(front)
	var t: float = 0.0
	var bent_at: float = -1.0
	var hits: Array = []
	var left: int = 5 * 30
	var saw_switch_without_attack: bool = false
	for i in range(60):
		_tick_world(w)
		t += TICK
		if g.is_switching_stance() and g._pending_attack == &"":
			saw_switch_without_attack = true
		if bent_at < 0.0 and g.stance == Golem.STANCE_CROUCH:
			bent_at = t
		var now: int = 0
		for u in crowd:
			now += maxi(u.health, 0) if is_instance_valid(u) else 0
		if now < left:
			left = now
			hits.append(t)
		if hits.size() >= 2:
			break
	check(saw_switch_without_attack, "foes in the slam's circle only: she bends down first, without striking yet")
	check(hits.size() >= 2, "then the slams land (%d)" % hits.size())
	if hits.size() >= 2:
		check_near(hits[0] - bent_at, Balance.GOLEM_SLAM_WINDUP,
			"the first slam lands 0,35 s after she is down (%.2f)" % (hits[0] - bent_at), TICK * 1.5)
		check_near(hits[1] - hits[0], g.cooldown_for(Golem.ATTACK_SLAM),
			"the next one follows after 1,25 s — no bending in between (%.2f)" % (hits[1] - hits[0]), TICK * 1.5)
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
	check(g.stance_switch_time() <= Balance.GOLEM_STANCE_SWITCH_MAX and g.stance_switch_time() > 1.6,
		"the 80-m giant: %.2f s, never more than the 2-s cap" % g.stance_switch_time())
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
	check(g.reach() > 9.2 and g.reach() < 9.3, "level 7: %.1f m (was 6,6)" % g.reach())
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
	check_near(g.limb_factor(), Balance.GOLEM_BODY_LIMB_FACTOR_AT_ANCHOR * g.body_anchor_ratio(),
		"at 80 m: limb factor %.1f, grown with the body from 30 m (2026-11-18)" % g.limb_factor())
	# The curve keeps its anchor at the old 100 m (user spec 2026-11-17): levels 1-6 unchanged.
	var anchor: float = Golem.limb_anchor_size()
	check_near(pow(anchor, Golem.limb_exponent()), Balance.GOLEM_LIMB_SHARE_AT_MAX * anchor,
		"the power law alone gives 60 percent of a body-proportional growth at 100 m", 0.01)
	check(g.reach() > 39.7 and g.reach() < 40.1, "the reach at 80 m is %.1f m (34,5 m before 2026-11-18)" % g.reach())
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
	var need2: float = big._golem_need(small)   # (knee high: only her legs count, 2026-11-18)
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
	check(g.stance_switch_time() > 0.75 and g.stance_switch_time() < 0.77, "level 7: %.2f s" % g.stance_switch_time())
	_grow_to_the_end(g)
	check(g.stance_switch_time() > 1.63 and g.stance_switch_time() < 1.66,
		"80 m: %.2f s (below the 2-s cap)" % g.stance_switch_time())
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
	for i in range(Golem.kills_for_growth_step(1)):
		g._credit_kill()
	check(g.growth_steps == 1 and g.slam_radius() > r7 * 1.041 and g.slam_radius() < r7 * 1.043,
		"one growth step: about 4,2 percent more (%.3f m)" % g.slam_radius())
	check_near(Balance.GOLEM_KICK_WIDTH * g.reach_factor(), Balance.GOLEM_KICK_WIDTH * Golem.reach_factor_for(7) * 1.019645,
		"the lane's width takes its 1,96 percent", 0.0005)
	_grow_to_the_end(g)
	check_near(g.slam_radius(), Balance.GOLEM_SLAM_RADIUS * Balance.GOLEM_BODY_SLAM_SCALE_AT_ANCHOR * g.body_anchor_ratio(),
		"at 80 m: with the body from 30 m on, about 18 m (%.1f; 12 m before 2026-11-18)" % g.slam_radius(), 0.001)
	check(Balance.GOLEM_SLAM_RADIUS_AT_MAX == 12.0, "the documented 12 m")
	# In play: an enemy 11 m from where the hands land is struck, one at 13 m is not.
	g.facing = Vector3(0, 0, 1)
	var hands: Vector3 = g.position + Vector3(0, 0, 1) * (Balance.GOLEM_SLAM_FORWARD * g.limb_factor())
	check(g._in_hit_zone(Golem.ATTACK_SLAM, hands + Vector3(11.0, 0, 5.0).normalized() * 17.0, Vector3(0, 0, 1), Vector3(-1, 0, 0))
		and not g._in_hit_zone(Golem.ATTACK_SLAM, hands + Vector3(0, 0, 19.0), Vector3(0, 0, 1), Vector3(-1, 0, 0)),
		"17 m from the hands is inside the circle, 19 m outside")
	_free_world(w)


## Der ausgewachsene Golem (80 m): noch einmal +3 Leben/s Dauerheilung, und die Lebensobergrenze bekommt 100
## dazu (Nutzervorgabe 2026-11-18): 21 + 21 + 3 = 45 LP/s, 1000 + 30 + 21 x 30 + 100 = 1760 LP.
func test_full_grown_golem_regenerates_three_more_and_has_1378_hp() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	_level_to(g, 7)
	while g.growth_steps < Golem.max_growth_steps() - 1:
		g._credit_kill()
	check_near(g.regen_per_second(), 27.0 + float(Golem.max_growth_steps() - 1), "one step before the end: 47 per second")
	check(g.max_health == 1030 + (Golem.max_growth_steps() - 1) * 30, "and 1630 health (%d)" % g.max_health)
	_grow_to_the_end(g)
	check(g.is_full_size(), "grown to 80 m")
	check_near(g.regen_per_second(), 48.0 + Balance.GOLEM_FULL_SIZE_REGEN, "full-grown: 6 + 21 + 21 + 3 = 51 per second")
	check(g.max_health == 1030 + Golem.max_growth_steps() * 30 + 100 and g.max_health == 1760,
		"the health limit is 1760 (%d)" % g.max_health)
	g.health = 100
	g._tick_level_regen(1.0)
	check(g.health == 151, "one second heals 51")
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
	check_near(ended_at - started_at, g.grow_time(),
		"and takes about 1 s at this size (%.2f)" % (ended_at - started_at), TICK * 1.5)
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
	for i in range(Golem.kills_for_growth_step(1)):
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
	check(g.max_targets() == 29 and g.max_targets_of(Golem.ATTACK_KICK) == 17
		and g.max_targets_of(Golem.ATTACK_DRUM) == 36 and g.max_targets_of(Golem.ATTACK_STOMP) == 58,
		"80 m: base 29, kick 17, drum 36, stomp 58")
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
	check(g.attack_damage(Golem.ATTACK_STOMP) == 10, "level 7 (16,9 m): 2 x 5 = 10, no level bonus on top")
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
	var sd: int = Golem.building_damage_for(g2.attack_damage(Golem.ATTACK_STOMP))
	g2._land_attack(Golem.ATTACK_STOMP)
	check(a_hut.max_health - a_hut.health == sd and b_hut.max_health - b_hut.health == sd and far_hut.health == far_hut.max_health,
		"both lose half the stomp's damage in hit points (2026-11-18), the hut farther away nothing")
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
	check(foe.health == 100000 - g.attack_damage(Golem.ATTACK_STOMP), "one landing, one damage tick")
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
	# Ten weak foes (4 HP) close around her — inside the stomp's circle and the slam's. (Until
	# 2026-11-18 two huts made the case; buildings take hit points now and the stomp's few points
	# hardly scratch them.)
	for i in range(10):
		var a: float = TAU * float(i) / 10.0
		_foe(w, 50.0 + cos(a) * 0.9, 50.0 + sin(a) * 0.9, 4)
	var lead: float = g.attack_worth(Golem.ATTACK_STOMP)
	check_near(lead, 10.0 * float(g.attack_damage(Golem.ATTACK_STOMP)), "the stomp strikes all ten")
	var n: float = float(Balance.GOLEM_STANCE_PLAN_ATTACKS)
	var plan: float = 0.0
	for kind in [Golem.ATTACK_SLAM, Golem.ATTACK_DRUM]:
		plan = maxf(plan, (lead + n * g.attack_worth(kind)) / (maxf(g.cooldown_for(Golem.ATTACK_STOMP), g.turn_time_needed()) + n * g.cooldown_for(kind)))
	check(g.stomp_plan_value() >= plan - 0.0001, "stomp, then three ground attacks: %.1f per second" % plan)
	check_near(g.attack_value(Golem.ATTACK_STOMP), g.stomp_plan_value(), "attack_value reports the plan")
	check(g.stomp_plan_value() > g.attack_value(Golem.ATTACK_SLAM) and g.stomp_plan_value() > g.attack_value(Golem.ATTACK_DRUM),
		"that beats bending down first")
	check(g._choose_attack() == Golem.ATTACK_STOMP, "she opens with the stomp")
	g._stance_age = 0.0
	check(g._choose_attack() != Golem.ATTACK_STOMP, "right after a stance change she does not jump")
	g._stance_age = 1000.0
	g.stomp_enabled = false
	check(g._choose_attack() != Golem.ATTACK_STOMP, "switched off: no stomp")
	g.stomp_enabled = true
	g.stance = Golem.STANCE_CROUCH
	check(g._choose_attack() != Golem.ATTACK_STOMP, "crouched the stomp is not on offer")
	_free_world(w)


## Im Ablauf: zwischen schwachen Feinden oeffnet sie mit dem Sprung, bleibt unten und schlaegt mit einem
## Bodenangriff weiter — ohne einen einzigen Haltungswechsel. (Bis 2026-11-18 mit zwei Huetten.)
func test_stomp_opens_the_assault_and_the_slams_follow_without_a_switch() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	var ring: Array = []
	for i in range(10):
		var a: float = TAU * float(i) / 10.0
		ring.append(_foe(w, 50.0 + cos(a) * 0.9, 50.0 + sin(a) * 0.9, 4))
	g.order_attack(ring[0])
	var saw_stomp: bool = false
	var saw_ground: bool = false
	var saw_switch: bool = false
	var hurt_by_stomp: bool = false
	for i in range(70):
		_tick_world(w)
		if g._pending_attack == Golem.ATTACK_STOMP:
			saw_stomp = true
		if g._pending_attack == Golem.ATTACK_SLAM or g._pending_attack == Golem.ATTACK_DRUM:
			saw_ground = true
		if g.is_switching_stance():
			saw_switch = true
		if saw_stomp and not saw_ground and g._pending_attack == &"" and not hurt_by_stomp:
			hurt_by_stomp = true
			for u in ring:
				hurt_by_stomp = hurt_by_stomp and is_instance_valid(u) and u.health < 4
		var alive: int = 0
		for u in ring:
			if is_instance_valid(u) and u.state != Unit.State.DEAD:
				alive += 1
		if alive == 0:
			break
	check(saw_stomp, "she opens with the stomp")
	check(hurt_by_stomp, "its landing hurts all ten")
	check(saw_ground and not saw_switch, "then she strikes from the crouch — no stance switch at all")
	_free_world(w)


## Trampeln auf Gebaeude (seit 2026-11-18 ueber Lebenspunkte): je Sekunde die Haelfte des Trampelschadens;
## Fahrzeuge behalten ihre 2 s.
func test_trampling_takes_hit_points_off_a_building_every_second() -> void:
	check_near(Balance.GOLEM_TRAMPLE_BUILDING_INTERVAL, 1.0, "buildings every second, like units")
	check_near(Balance.GOLEM_TRAMPLE_VEHICLE_INTERVAL, 2.0, "vehicles keep their 2 s")
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	_level_to(g, 7)
	var hut: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(49, 49), 0, true)
	var step: Vector3 = Vector3(0.4, 0, 0)
	var td: int = Golem.building_damage_for(g.trample_damage())
	var hits_at: Array = []
	var last: int = hut.health
	var t: float = 0.0
	for i in range(85):
		g._tick_pos = g.position - step
		g._tick_trample(TICK)
		t += TICK
		if hut.health < last:
			check(last - hut.health == td, "each time half the trampling damage (%d)" % (last - hut.health))
			last = hut.health
			hits_at.append(t)
	check(hits_at.size() >= 8, "8,5 s of walking over it: about once a second (%d)" % hits_at.size())
	if hits_at.size() >= 3:
		check_near(hits_at[1] - hits_at[0], 1.0, "one second apart (%.1f)" % (hits_at[1] - hits_at[0]), TICK * 1.5)
		check_near(hits_at[2] - hits_at[1], 1.0, "and again", TICK * 1.5)
	_free_world(w)


## Tritt-Schneise (2026-11-16): bei 100 m 10 % kuerzer als der Gliederfaktor
## allein ergaebe (der Anker bleibt seit 2026-11-17 bei 100 m: bei 80 m knapp 10 %),
## auf Stufe 0 unveraendert; vorn wie hinten.
func test_kick_lane_is_ten_percent_shorter_at_the_top() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	check_near(g.kick_limb_factor(), 1.0, "level 0: unchanged")
	check_near(g._kick_extent().x, Balance.GOLEM_KICK_LENGTH, "4,25 m ahead")
	_level_to(g, 7)
	check(g.kick_limb_factor() < g.limb_factor() and g.kick_limb_factor() > 1.0,
		"level 7: shorter than the limbs alone (%.2f against %.2f)" % [g.kick_limb_factor(), g.limb_factor()])
	_grow_to_the_end(g)
	var top: float = Golem.limb_factor_for(Golem.limb_anchor_size())
	check_near(1.0 + (top - 1.0) * Golem.kick_growth_share(), 0.9 * top, "100 m: 90 percent of the limb factor", 0.0001)
	check_near(g.kick_limb_factor() / g.limb_factor(), Balance.GOLEM_BODY_KICK_LIMB_AT_ANCHOR / Balance.GOLEM_BODY_LIMB_FACTOR_AT_ANCHOR,
		"80 m: the share it has at 31,3 m, both grow with the body (%.4f)" % (g.kick_limb_factor() / g.limb_factor()), 0.0001)
	var lane: Vector2 = g._kick_extent()
	check_near(lane.x, Balance.GOLEM_KICK_LENGTH * g.kick_limb_factor() * Balance.GOLEM_BODY_KICK_FRONT_SHARE, "%.1f m ahead" % lane.x, 0.001)
	check_near(lane.y, Balance.GOLEM_KICK_LENGTH * Balance.GOLEM_KICK_BACK_SHARE * g.kick_limb_factor(),
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
	check_near(g.ground_radius(Golem.ATTACK_DRUM), 1.1 * g.slam_radius(), "80 m: the drum still 10 percent larger (%.1f m)" % g.ground_radius(Golem.ATTACK_DRUM), 0.001)
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
	_level_to(g, 7)   # 16,9 m
	check_near(g.kick_throw_chance(), 0.20, "the giant (16,9 m): kick 20 %")
	check_near(g.slam_lift_chance(), 0.08, "slam throw 8 %")
	check_near(g.drum_roll_chance(), 0.08, "drum roll 8 %")
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


# --- Ufer (Bugfix 2026-11-16) ---------------------------------------------------------

## Ufer: Meer ab x = 55 (1,4 m), davor faellt das Land ab. Die Zelle x = 54 ist
## begehbar (Eckmittel ueber dem Meer), hat aber Punkte auf Wasserhoehe.
func _shore_world() -> Dictionary:
	var w: Dictionary = _make_world(5.0)
	for vz in range(w.td.verts):
		for vx in range(55, w.td.verts):
			w.td.set_vertex_height(vx, vz, 1.4)
		w.td.set_vertex_height(54, vz, 2.8)
		w.td.set_vertex_height(53, vz, 3.8)
		w.td.set_vertex_height(52, vz, 4.6)
	w.nav.update_region(Rect2i(0, 0, w.td.size, w.td.size))
	return w


## Nutzerbericht: Golems laufen ohne Kampf am Wasser entlang und sterben. Ursache:
## das Einebnen des Riesen senkte das Ufer unter ihm bis unter die Wasserlinie, und
## die Gelaendepruefung danach ertraenkte ihn. Jetzt bleibt das Ufer stehen.
func test_a_giant_levelling_along_the_shore_does_not_drown() -> void:
	var w: Dictionary = _shore_world()
	check(w.nav.is_cell_walkable(Vector2i(54, 50)), "the shore cell is walkable")
	var g: Golem = _golem(w, 0, Vector3(54.5, w.td.get_height(54.5, 50.5), 50.5))
	g.terrain_ctx = w.ctx
	while not g.flattens():   # from 30 m on (2026-11-18)
		g._credit_kill()
	g._stretch_queued = false
	g.order_move(Vector3(54.5, 2.1, 80.5), false, false)
	for i in range(300):
		_tick_world(w)
	check(g.state != Unit.State.DEAD, "30 s of levelling and walking along the shore: alive")
	var shore_kept: bool = true
	for vz in range(45, 85):
		shore_kept = shore_kept and absf(w.td.heights[vz * w.td.verts + 54] - 2.8) < 0.001
	check(shore_kept, "the vertices at the water are not lowered")
	var lowered: bool = false
	for vz in range(45, 85):
		lowered = lowered or w.td.heights[vz * w.td.verts + 53] < 3.8 - 0.05
	check(lowered, "further inland she still levels along her way")
	_free_world(w)


## Nasse Fuesse am Ufer ertraenken einen Golem nicht mehr, wenn nebenan das
## Gelaende geaendert wird — einen Krieger an derselben Stelle schon (unveraendert).
## Versinkt das Land unter dem Golem aber wirklich, ertrinkt er weiter.
func test_a_golem_wading_at_the_shore_survives_terrain_changes_but_not_sunken_land() -> void:
	var w: Dictionary = _shore_world()
	var spot: Vector3 = Vector3(54.9, 0.0, 50.5)
	spot.y = w.td.get_height(spot.x, spot.z)
	check(spot.y <= TerrainData.SEA_LEVEL + Unit.WATER_EPS, "his feet are at the waterline")
	var g: Golem = _golem(w, 0, spot)
	var foe: Unit = _spawn(w, WARRIOR_SCENE, 1, spot + Vector3(0, 0, 3))
	w.ctx.apply_terrain_change(Rect2i(50, 46, 8, 10))
	check(g.state != Unit.State.DEAD, "a terrain change nearby: the golem wades on")
	check(foe.state == Unit.State.DEAD, "a warrior at the waterline still drowns")
	for vz in range(48, 54):
		for vx in range(52, 58):
			w.td.set_vertex_height(vx, vz, TerrainData.SEA_LEVEL - Balance.GOLEM_DROWN_DEPTH - 0.2)
	w.ctx.apply_terrain_change(Rect2i(52, 48, 6, 6))
	check(g.state == Unit.State.DEAD, "the land under him sunk deep: he drowns")
	_free_world(w)


## Das Trommeln sind drei Schlaege mit je eigener Zielauswahl: was der erste
## toetet, ersetzt der naechste durch weitere Einheiten in der Flaeche. Die Wahl
## rechnete es frueher wie EINEN Schlag mit dem Gesamtschaden auf eine Zielzahl
## (Bugfix 2026-11-16, Untersuchung "Daemon trommelt nicht mehr").
func test_the_drum_is_valued_hit_by_hit_against_a_weak_crowd() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.stance = Golem.STANCE_CROUCH
	var impact: Vector3 = g.position + g.heading() * (Golem.SLAM_FORWARD * g.limb_factor())
	for i in range(12):
		var b: Unit = _spawn(w, BRAVE_SCENE, 1,
			impact + Vector3(cos(float(i)) * 0.6, 0, sin(float(i)) * 0.6))
		b.health = 10
	var cap: int = g.max_targets_of(Golem.ATTACK_DRUM)
	check(cap == 6, "six targets per drum hit at level 0 (got %d)" % cap)
	check_near(g.attack_worth(Golem.ATTACK_DRUM), 120.0,
		"hits one and two take six fresh braves each (12 x 10), the third finds no one", 0.001)
	check_near(g.attack_worth(Golem.ATTACK_SLAM), 50.0, "the slam: five braves", 0.001)
	_free_world(w)


# --- Zielradius und Zielpunkte (Nutzervorgabe 2026-11-16) -----------------------------

## Zwei Golems mit einem Bewegungsbefehl: ihre Zielpunkte liegen so weit
## auseinander, dass sich ihre Koerper nicht beruehren (vorher feste Packabstaende
## von 0,55 m — die Golems liefen sich in den Weg). Gilt auch fuer ungleiche Groessen.
func test_golems_sent_together_get_goals_clear_of_each_other() -> void:
	var w: Dictionary = _make_world()
	var big: Golem = _golem(w, 0, Vector3(30, 5, 30))
	var small: Golem = _golem(w, 0, Vector3(34, 5, 30))
	var third: Golem = _golem(w, 0, Vector3(30, 5, 34))
	var brave: Unit = _spawn(w, BRAVE_SCENE, 0, Vector3(32, 5, 32))
	_level_to(big, 6)
	_level_to(third, 3)
	var sel: Array[Unit] = [big, small, third, brave]
	var sent: int = w.commands.order_move(sel, Vector3(60, 5, 60))
	check(sent == 4, "all four get the order (got %d)" % sent)
	var gs: Array[Golem] = [big, small, third]
	var apart: bool = true
	for a in range(gs.size()):
		for b in range(a + 1, gs.size()):
			var need: float = (gs[a].trample_radius() + gs[b].trample_radius()) * Balance.GOLEM_BODY_GAP
			var ga: Vector3 = gs[a].waypoint_queue.back()
			var gb: Vector3 = gs[b].waypoint_queue.back()
			if Vector2(ga.x - gb.x, ga.z - gb.z).length() < need:
				apart = false
	check(apart, "no two golem goals closer than their two bodies")
	check(Vector2(big.waypoint_queue.back().x - 60.0, big.waypoint_queue.back().z - 60.0).length() < 0.01,
		"the biggest takes the clicked point")
	check(brave.state == Unit.State.MOVE, "the brave marches as before")
	_free_world(w)


## Angreifer schlagen den Golem vom Rand seines Zielradius aus (die Haelfte des
## Auswahlkreises), statt sich unter ihm zu draengen — im Objektcode wie in der
## Kampfschleife des UnitManagers. Gewoehnliche Einheiten haben Radius 0.
func test_attackers_strike_a_golem_from_the_edge_of_his_target_radius() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	_level_to(g, 7)
	var tr: float = g.target_radius()
	check(tr > 1.4, "the giant is a big target (%.2f m)" % tr)
	check_near(w.um.soa_reach[g._idx], tr, "the manager keeps the radius in step", 0.0001)
	var foe: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector3(50 + tr + 1.0, 5, 50))
	check(foe.target_radius() == 0.0, "an ordinary unit is a point")
	check_near(foe.reach_dist_to(g), 1.0, "measured to the edge of his circle", 0.001)
	check(foe.reach_dist_to(g) <= Balance.MELEE_RANGE, "so the warrior is already in melee range")
	check_near(_flat_len(g.melee_slot_position(0) - g.position), Unit.MELEE_SLOT_RADIUS + tr,
		"his melee slots lie outside the circle", 0.001)
	foe.max_health = 100000
	foe.health = 100000
	g.max_health = 100000
	g.health = 100000
	g.stance = Golem.STANCE_STAND
	foe.order_attack(g)
	var start_hp: int = g.health
	for i in range(60):
		foe.tick(TICK)   # only the warrior: the golem must not strike back here
		w.um.tick(TICK)
	check(g.health < start_hp, "the warrior hits him from out there")
	check(_flat_len(foe.position - g.position) > tr, "and never steps inside the circle")
	_free_world(w)


func _flat_len(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


# --- Bewegungsfreiheit unter Golems, Anlauf in Schlagdistanz (2026-11-17) ---------------

## Laesst Stretch und Haltungswechsel nach einem Stufenaufstieg auslaufen.
func _settle(w: Dictionary, ticks: int = 25) -> void:
	for i in range(ticks):
		_tick_world(w)


## Ist der Zielort von Golems belegt, gilt der Marsch nah davor als angekommen —
## die drei Golems dort werden nicht weggeschoben (Nutzervorgabe 2026-11-17).
func test_a_march_onto_golems_ends_close_to_them() -> void:
	var w: Dictionary = _make_world()
	var goal: Vector3 = Vector3(70, 5, 64)
	var blockers: Array[Golem] = []
	var probe: Golem = _golem(w, 0, Vector3(20, 5, 20))
	_level_to(probe, 3)
	var r: float = probe.trample_radius()
	for k in range(3):
		var ang: float = TAU * float(k) / 3.0
		var at: Vector3 = goal + Vector3(cos(ang), 0.0, sin(ang)) * (2.0 * r / sqrt(3.0) + 0.05)
		var b: Golem = _golem(w, 0, at)
		_level_to(b, 3)
		blockers.append(b)
	var mover: Golem = probe
	mover.position = Vector3(40, 5, 64)
	mover.snap_heading()
	_settle(w)
	var starts: Array[Vector3] = []
	for b in blockers:
		starts.append(b.position)
	mover.order_move(goal)
	var ticks: int = 0
	while mover.state == Unit.State.MOVE and ticks < 300:
		_tick_world(w)
		ticks += 1
	check(mover.state == Unit.State.IDLE, "the march ends although the goal is taken (%d ticks)" % ticks)
	var need: float = 2.0 * r * Balance.GOLEM_BODY_GAP
	check(_flat(mover.position, goal) <= need + r * Balance.GOLEM_BLOCKED_ARRIVE_BODIES + 0.1,
		"she stops close to it (%.2f m from the goal)" % _flat(mover.position, goal))
	var pushed: float = 0.0
	for k in range(3):
		pushed = maxf(pushed, _flat(blockers[k].position, starts[k]))
	for i in range(20):
		_tick_world(w)
	check(pushed < 0.3, "the golems on the spot are not shoved away (at most %.2f m)" % pushed)
	check(mover.blocked_goal_reached(goal) and not mover.blocked_goal_reached(Vector3(20, 5, 100)),
		"blocked_goal_reached: only a goal other golems stand on counts")
	_free_world(w)


## Ein untaetiger Golem, der einem laufenden im Weg steht, tritt zur Seite —
## quer zu dessen Laufrichtung — statt vor ihm hergeschoben zu werden.
func test_an_idle_golem_steps_aside_for_a_walking_one() -> void:
	var w: Dictionary = _make_world()
	var walker: Golem = _golem(w, 0, Vector3(40, 5, 64))
	var idle: Golem = _golem(w, 0, Vector3(52, 5, 64))
	_level_to(walker, 2)
	_level_to(idle, 2)
	_settle(w)
	var start: Vector3 = idle.position
	var goal: Vector3 = Vector3(66, 5, 64)
	walker.order_move(goal)
	var ticks: int = 0
	while walker.state == Unit.State.MOVE and ticks < 200:
		_tick_world(w)
		ticks += 1
	check(_flat(walker.position, goal) < 0.5, "the walker gets to its goal (%.2f m off, %d ticks)"
		% [_flat(walker.position, goal), ticks])
	var side: float = absf(idle.position.z - start.z)
	var along: float = absf(idle.position.x - start.x)
	check(side > 1.0 and side > along * 2.0,
		"the idle golem stepped aside (%.2f m across, %.2f m along the course)" % [side, along])
	var need: float = walker.trample_radius() + idle.trample_radius()
	check(side <= need + 0.5, "no farther than needed (%.2f m, %.2f m clear)" % [side, need])
	_free_world(w)


## Muss sie zum Ziel hinlaufen, laeuft sie bis in Schlagdistanz heran (das Ziel
## liegt dann im Kreis des Handschlags), nicht nur bis an den Rand ihrer
## Reichweite.
func test_walking_up_she_closes_in_to_strike_distance() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(30, 5, 64))
	_level_to(g, 6)
	_settle(w)
	var foe: Unit = _foe(w, 60.0, 64.0, 100000)
	check(g.strike_distance() < g.reach() - 1.5,
		"level 6: strike distance %.1f m, reach %.1f m" % [g.strike_distance(), g.reach()])
	g.order_attack(foe)
	var ticks: int = 0
	while g._pending_attack == &"" and ticks < 200:
		_tick_world(w)
		ticks += 1
	var d: float = _flat(g.position, foe.position)
	check(g._pending_attack != &"", "she strikes (%d ticks)" % ticks)
	check(d <= g.strike_distance() + 0.3, "having walked in to %.2f m (strike distance %.2f m)"
		% [d, g.strike_distance()])
	_free_world(w)


## Aus dem Stand greift sie weiter auf volle Reichweite an — sie laeuft nicht hin.
func test_standing_she_still_strikes_at_full_reach() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 64))
	_level_to(g, 6)
	_settle(w)
	var foe: Unit = _foe(w, 50.0 + g.reach() - 0.5, 64.0, 100000)
	var at: Vector3 = g.position
	g.order_attack(foe)
	var ticks: int = 0
	while g._pending_attack == &"" and ticks < 60:
		_tick_world(w)
		ticks += 1
	check(g._pending_attack != &"", "she strikes (%d ticks)" % ticks)
	check(_flat(g.position, at) < 0.05, "without taking a step (%.2f m)" % _flat(g.position, at))
	_free_world(w)


## Steht beim Heranlaufen ein anderer Golem im Weg, reicht die volle Reichweite:
## sie schiebt ihn nicht weg, um naeher heranzukommen.
func test_a_golem_in_the_way_leaves_her_the_full_reach() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(30, 5, 64))
	var other: Golem = _golem(w, 0, Vector3(20, 5, 100))
	_level_to(g, 6)
	_level_to(other, 6)
	_settle(w)
	var need: float = g.trample_radius() + other.trample_radius()
	var foe_x: float = 60.0
	# Where she first has the foe in reach, the other golem is already touching her.
	other.position = Vector3(foe_x - g.reach() + need + 0.3, 5, 64)
	var other_start: Vector3 = other.position
	# The other golem only stands in the way: no scan of its own (its scan phase hangs on its instance id,
	# so in the full run it sometimes went for the foe itself and walked off).
	other._target_search_timer = 1.0e9
	var foe: Unit = _foe(w, foe_x, 64.0, 100000)
	g.order_attack(foe)
	var ticks: int = 0
	while g._pending_attack == &"" and ticks < 200:
		_tick_world(w)
		ticks += 1
	var d: float = _flat(g.position, foe.position)
	check(g._pending_attack != &"", "she strikes (%d ticks)" % ticks)
	check(d > g.strike_distance() + 1.0 and d <= g.reach() + 0.05,
		"from the edge of her reach (%.2f m; reach %.2f, strike distance %.2f)"
			% [d, g.reach(), g.strike_distance()])
	check(_flat(other.position, other_start) < 0.3,
		"the golem in the way was not shoved (%.2f m)" % _flat(other.position, other_start))
	_free_world(w)


# --- Sitzen (Nutzervorgabe 2026-11-17, plans/10l_golem_sitting.md, erste Stufe) ------
# Dritte Haltung fuer alle Golems ab 30 m, nur ueber die gebueckte erreichbar und
# nur von Hand (Taste V / Seitenleiste). Im Sitzen keine Befehle, keine Bewegung,
# keine Angriffe; Sitzschaden auf das, was beim Aufsetzen unter dem Po steht.

func _run_stance(w: Dictionary, g: Golem, limit: int = 400) -> int:
	var ticks: int = 0
	while g.is_switching_stance() and ticks < limit:
		_tick_world(w)
		ticks += 1
	return ticks


## A golem grown to at least 30 m (the first growth step past it: 31,3 m).
func _sit_golem(w: Dictionary, tribe_id: int, at: Vector3) -> Golem:
	var g: Golem = _golem(w, tribe_id, at)
	while not g.can_sit():
		g._credit_kill()
	g._stretch_queued = false
	g.health = g.max_health
	g.facing = Vector3(0, 0, 1)
	g.snap_heading()
	g.tick(TICK)
	return g


## Asks her to sit and runs the world until she sits (or the limit).
func _sit_until_seated(w: Dictionary, g: Golem, limit: int = 400) -> bool:
	if not g.sit_down():
		return false
	var ticks: int = 0
	while not (g.is_sitting() and not g.is_switching_stance()) and ticks < limit:
		_tick_world(w)
		ticks += 1
	return g.is_sitting()


func test_sitting_needs_thirty_metres_and_works_for_every_golem() -> void:
	var w: Dictionary = _make_world()
	var small: Golem = _golem(w, 0, Vector3(30, 5, 30))
	small.tick(TICK)
	check(not small.can_sit() and not small.sit_down(), "a fresh golem (4,7 m) cannot sit")
	_level_to(small, 7)
	check(not small.can_sit(), "the giant (16,9 m) cannot yet")
	var g: Golem = _sit_golem(w, 0, Vector3(64, 5, 90))
	check(g.height_m() >= 30.0 and g.can_sit(), "from 30 m she can (%.1f m)" % g.height_m())
	var demon: DemonGolem = _spawn(w, load("res://scenes/units/demon_golem.tscn"), 0,
		Vector3(30, 5, 100)) as DemonGolem
	while demon.height_m() < 29.0:
		demon._credit_kill()
	check(not demon.can_sit(), "the demon golem at 29 m cannot")
	while demon.height_m() < 30.0:
		demon._credit_kill()
	check(demon.can_sit(), "at 32 m he can (%.0f m)" % demon.height_m())
	check_near(demon.sit_switch_time(), Balance.GOLEM_SIT_TIME * sqrt(demon.height_m() / 30.0) * 0.85,
		"and sits down 15 % faster than the golem of his size", 0.0001)
	var genesis: GenesisGolem = _spawn(w, load("res://scenes/units/genesis_golem.tscn"), 0,
		Vector3(100, 5, 30)) as GenesisGolem
	genesis.credit_brave(1000.0)
	check(genesis.height_m() >= 30.0 and genesis.can_sit(), "the Genesis golem on stage 8 (33 m) can too")
	_free_world(w)


## Stehen -> buecken -> sitzen, zurueck denselben Weg und am Ende stehend. Im Sitzen
## liegt ihr Standpunkt auf der Mitte der Sitzflaeche (hinter den Fuessen); beim
## Aufstehen kehrt er auf die Fuesse zurueck.
func test_sitting_goes_through_the_crouch_and_back() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _sit_golem(w, 0, Vector3(64, 5, 90))
	var feet: Vector3 = g.position
	check(g.sit_down(), "she takes the request to sit")
	check(g.is_sit_locked() and not g.can_take_orders(), "from now on she is sit-locked")
	_tick_world(w)
	check(g.is_switching_stance() and g._stance_target == Golem.STANCE_CROUCH, "first she bends down")
	_run_stance(w, g)
	_tick_world(w)
	check(g.is_switching_stance() and g._stance_target == Golem.STANCE_SIT,
		"then she sits down at once")
	check_near(g._stance_switch, Balance.GOLEM_SIT_TIME * sqrt(g.height_m() / 30.0),
		"sitting down takes 3 s x root(height / 30 m) (%.2f s)" % g.sit_switch_time(), 0.001)
	check(_flat(g.position, feet) < 0.01, "on the way down her feet stay where they are")
	_run_stance(w, g)
	check(g.is_sitting() and g.stance_name() == "sitzend", "she sits")
	var back: float = g.seat_back_m()
	check(back > 10.0 and back < 11.5, "the seat lies %.1f m behind her feet" % back)
	check_near(_flat(g.position, feet), back, "her position now is the middle of the seat", 0.01)
	check(g.position.z < feet.z, "behind her (she faces +z)")
	for i in range(300):
		_tick_world(w)
	check(g.is_sitting() and _flat(g.position, feet - Vector3(0, 0, back)) < 0.01,
		"with nothing happening she stays seated, on the spot, for 30 s")
	check(g.stand_up(), "called up")
	_tick_world(w)
	check(g.is_switching_stance() and g._stance_target == Golem.STANCE_CROUCH,
		"she gets up into the crouch first")
	check(_flat(g.position, feet) < 0.01, "back on her feet")
	var up_ticks: int = _run_stance(w, g)
	check_near(float(up_ticks + 1) * TICK, g.sit_switch_time(),
		"getting up takes as long as sitting down", TICK * 1.5)
	_tick_world(w)
	check(g.is_switching_stance() and g._stance_target == Golem.STANCE_STAND,
		"and straight on to standing")
	check(g.is_sit_locked(), "still locked until she stands")
	_run_stance(w, g)
	check(g.stance == Golem.STANCE_STAND and not g.is_sit_locked() and g.can_take_orders(),
		"she stands and takes orders again")
	check(_flat(g.position, feet) < 0.01, "where she stood before")
	_free_world(w)


## Im Sitzen ignoriert sie Bewegungs- und Angriffsbefehle und greift von sich aus
## nichts an; nur "Aufstehen" wirkt. Getroffen bleibt sie sitzen.
func test_seated_she_takes_no_orders_and_strikes_nothing() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _sit_golem(w, 0, Vector3(64, 5, 90))
	check(_sit_until_seated(w, g), "she sits")
	var seat: Vector3 = g.position
	var foe: Unit = _foe(w, 64.0, 99.0, 100000)
	var sel: Array[Unit] = [g]
	check(w.commands.order_move(sel, Vector3(64, 5, 40)) == 0, "a move order reaches nobody")
	w.commands.order_attack(sel, foe)
	g.order_move(Vector3(64, 5, 40))
	g.order_attack(foe)
	for i in range(100):
		_tick_world(w)
		g.take_damage(1, foe)
	check(g.is_sitting() and _flat(g.position, seat) < 0.01, "she stays seated on the spot")
	check(g.attack_target == null and g._pending_attack == &"",
		"no standing attack, no target from orders (her limbs strike on their own, GolemSitCombat)")
	check(g.state == Unit.State.IDLE, "she stays idle")
	_free_world(w)


## Taste V: setzt die gewaehlten Golems hin, sitzt einer, stehen alle auf. Zu kleine
## Golems antworten nicht.
func test_key_v_toggles_sitting() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _sit_golem(w, 0, Vector3(64, 5, 90))
	var small: Golem = _golem(w, 0, Vector3(20, 5, 20))
	small.tick(TICK)
	var sel: Array[Unit] = [g, small]
	check(w.commands.toggle_golem_sit(sel) == 1, "V: the big one sits down, the small one cannot")
	check(g._wants_sit and not small._wants_sit, "only the big one")
	check(w.commands.order_move(sel, Vector3(20, 5, 60)) == 1, "a move order now reaches only the small one")
	_tick_world(w)
	_tick_world(w)
	check(g.is_switching_stance(), "she is bending down")
	check(w.commands.toggle_golem_sit(sel) == 1, "V again: she gets up (even on her way down)")
	check(not g._wants_sit and g.is_sit_locked(), "and stays locked until she stands")
	_run_stance(w, g)
	_tick_world(w)
	_run_stance(w, g)
	check(g.stance == Golem.STANCE_STAND and not g.is_sit_locked(), "standing, free again")
	_free_world(w)


## Sitzplatz: die Sitzflaeche beruehrt kein Gebaeude; ist ihr Platz belegt, rueckt
## sie bis zu einem halben Koerperradius aus, sonst setzt sie sich nicht.
func test_no_seat_on_buildings() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _sit_golem(w, 0, Vector3(64, 5, 90))
	var seat: Vector3 = g.position - g.heading() * g.seat_back_m()
	check(g.seat_free(seat, g.heading(), g.seat_half_extent()), "her seat is free on open ground")
	# A hut whose corner reaches just into the seat: she moves aside.
	var half: Vector2 = g.seat_half_extent()
	var hut: Building = w.bm.place(HUT_SCENE, w.t1,
		Vector2i(int(floor(seat.x + half.x - 0.5)), int(floor(seat.z - 1.0))), 0, true)
	check(hut != null, "a hut stands at the edge of the seat")
	check(not g.seat_free(seat, g.heading(), g.seat_half_extent()), "the seat touches it")
	var feet: Vector3 = g.find_seat()
	check(feet != Vector3.INF and _flat(feet, g.position) <= g.trample_radius() * 0.5 + 0.01,
		"a free seat within half her body radius (%.2f m aside)" % (_flat(feet, g.position) if feet != Vector3.INF else -1.0))
	var start: Vector3 = g.position
	check(_sit_until_seated(w, g), "she sits down there")
	check(_flat(g.position + g.heading() * g.seat_back_m(), feet) < 0.05,
		"her feet moved onto the free spot while she bent down")
	check(g.seat_free(g.position, g.heading(), g.seat_half_extent()), "the seat touches no building")
	check(_flat(start, feet) > 0.01, "she did have to move")
	# A hut right under the middle of the seat: no seat within reach, the order is ignored.
	var g2: Golem = _sit_golem(w, 0, Vector3(30, 5, 50))
	var seat2: Vector3 = g2.position - g2.heading() * g2.seat_back_m()
	w.bm.place(HUT_SCENE, w.t1, Vector2i(int(seat2.x) - 1, int(seat2.z) - 1), 0, true)
	check(g2.find_seat() == Vector3.INF and not g2.sit_down() and not g2.is_sit_locked(),
		"a hut under the middle of the seat: she does not sit")
	_free_world(w)


## Sitzschaden: wer beim Aufsetzen unter dem Po steht — gleich welcher Stamm —, nimmt
## 4 x Trampelschaden, sofort und alle 5 s. Wer herauslaeuft, faellt heraus; wer
## spaeter kommt, wird nicht getroffen. Eigene Opfer zaehlen nicht als Kill.
func test_sit_damage_hits_who_was_under_her_when_she_sat_down() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _sit_golem(w, 0, Vector3(64, 5, 90))
	var seat: Vector3 = g.position - g.heading() * g.seat_back_m()
	var dmg: int = Balance.GOLEM_SIT_DAMAGE_MULT * g.trample_damage()
	check(dmg == 4 * g.trample_damage() and dmg >= 36, "4 x the trample damage (%d)" % dmg)
	var foe: Unit = _foe(w, seat.x + 1.0, seat.z, 1000)
	var leaver: Unit = _foe(w, seat.x - 1.0, seat.z + 1.0, 1000)
	var friend: Unit = _spawn(w, BRAVE_SCENE, 0, Vector3(seat.x, 5, seat.z - 1.0))
	friend.max_health = 1000
	friend.health = 1000
	var beside: Unit = _foe(w, seat.x + 6.0, seat.z, 1000)
	var weak: Unit = _foe(w, seat.x, seat.z + 0.5, dmg)
	g.sit_attacks_enabled = false   # only the sit damage here
	var kills: int = g.kills
	check(g.sit_down(), "she sits down on them")
	var ticks: int = 0
	while not (g.is_sitting() and not g.is_switching_stance()) and ticks < 400:
		g.tick(TICK)
		ticks += 1
	check(g.is_sitting(), "she sits")
	check(foe.health == 1000 - dmg and friend.health == 1000 - dmg and leaver.health == 1000 - dmg,
		"everyone under the seat takes it at once, her own tribe as well")
	check(beside.health == 1000, "6 m aside is not under her")
	check(weak.state == Unit.State.DEAD or weak.doomed, "the weak enemy dies")
	check(g.kills == kills + 1, "an enemy killed by sitting counts")
	# The leaver walks out, a newcomer walks in.
	leaver.position = Vector3(seat.x + 15.0, 5, seat.z)
	var late: Unit = _foe(w, seat.x - 1.0, seat.z - 1.0, 1000)
	friend.health = dmg   # the next tick kills the friend
	for i in range(int(Balance.GOLEM_SIT_DAMAGE_INTERVAL / TICK) + 1):
		g.tick(TICK)
	check(foe.health == 1000 - 2 * dmg, "after 5 s the next tick (%d)" % foe.health)
	check(leaver.health == 1000 - dmg, "who walked out takes nothing more")
	check(late.health == 1000, "who came later takes nothing")
	check(friend.state == Unit.State.DEAD or friend.doomed, "the own brave dies too")
	check(g.kills == kills + 1, "but her own victim counts as no kill")
	leaver.position = Vector3(seat.x - 1.0, 5, seat.z + 1.0)
	for i in range(int(Balance.GOLEM_SIT_DAMAGE_INTERVAL / TICK) + 1):
		g.tick(TICK)
	check(leaver.health == 1000 - dmg, "and coming back does not bring it back")
	_free_world(w)


## Feindliche Bodenfahrzeuge unter der Sitzflaeche nehmen Schaden (wie unter dem
## Trampeln), eigene nicht.
func test_sit_damage_wrecks_enemy_vehicles_under_her() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _sit_golem(w, 0, Vector3(64, 5, 90))
	var seat: Vector3 = g.position - g.heading() * g.seat_back_m()
	var catapult: Unit = _spawn(w, CATAPULT_SCENE, 1, Vector3(seat.x + 1.0, 5, seat.z))
	var own: Unit = _spawn(w, CATAPULT_SCENE, 0, Vector3(seat.x - 1.5, 5, seat.z))
	check(g.sit_down(), "she sits down")
	var ticks: int = 0
	while not (g.is_sitting() and not g.is_switching_stance()) and ticks < 400:
		g.tick(TICK)
		ticks += 1
	check(catapult.state == Unit.State.DEAD, "the enemy catapult under her is wrecked")
	check(own.state != Unit.State.DEAD, "her own is spared")
	_free_world(w)


## Im Sitzen ist sie das groessere Ziel (Zielradius x 2), auch im UnitManager.
func test_seated_her_target_radius_doubles() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _sit_golem(w, 0, Vector3(64, 5, 90))
	var standing: float = g.target_radius()
	check(_sit_until_seated(w, g), "she sits")
	check_near(g.target_radius(), standing * 2.0, "twice the target radius")
	check_near(w.um.soa_reach[g._idx], g.target_radius(), "the manager knows", 0.0001)
	g.stand_up()
	_tick_world(w)
	check_near(g.target_radius(), standing, "back to normal once she is up from the sit")
	_free_world(w)


## Waechst sie im Sitzen, bleibt sie sitzen (kein Strecken); die Sitzflaeche waechst
## nicht mit.
func test_growing_while_seated_keeps_her_seated() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _sit_golem(w, 0, Vector3(64, 5, 90))
	check(_sit_until_seated(w, g), "she sits")
	var half: Vector2 = g._seat_half
	var steps: int = g.growth_steps
	while g.kills < Golem.kills_for_level(Balance.GOLEM_MAX_LEVEL) + Golem.kills_for_growth_steps(steps + 1):
		g._credit_kill()
	check(g.growth_steps == steps + 1, "she grows a step")
	for i in range(30):
		_tick_world(w)
	check(g.is_sitting() and not g.is_switching_stance() and not g.is_stretching(),
		"she stays seated, without stretching")
	check(not g._stretch_queued, "the stretch is done with")
	check(g._seat_half == half, "the seat for the sit damage does not grow")
	_free_world(w)


## Ein anderer Golem schiebt die Sitzende nicht; er weicht ganz aus.
func test_a_sitting_golem_is_not_pushed() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _sit_golem(w, 0, Vector3(64, 5, 100))
	check(_sit_until_seated(w, g), "she sits")
	var seat: Vector3 = g.position
	var other: Golem = _golem(w, 0, seat + Vector3(1.0, 0, 0))
	other.tick(TICK)
	for i in range(40):
		_tick_world(w)
	check(_flat(g.position, seat) < 0.01, "the sitting golem stays put")
	check(_flat(other.position, seat) >= g._golem_need(other) - 0.05,
		"the other one moved out of her body (%.2f m)" % _flat(other.position, seat))
	_free_world(w)


## Lowers (or raises) every terrain vertex in the square of half side `half` around
## `at` to `h` (test helper for uneven ground under the seat).
func _set_ground(w: Dictionary, at: Vector3, half: float, h: float) -> void:
	var td: TerrainData = w.td
	for vz in range(int(floor(at.z - half)), int(ceil(at.z + half)) + 1):
		for vx in range(int(floor(at.x - half)), int(ceil(at.x + half)) + 1):
			td.heights[vz * td.verts + vx] = h


## Hoehe im Sitzen (Nutzer 2026-11-17): liegt der Sitz tiefer als die Fuesse, sinkt
## die Figur nicht ab (Arme und Beine verschwaenden im Boden) — hoeher darf sie liegen.
func test_seated_she_never_lies_lower_than_the_ground_under_her() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _sit_golem(w, 0, Vector3(64, 5, 90))
	var seat: Vector3 = g.position - g.heading() * g.seat_back_m()
	_set_ground(w, seat, 4.0, 3.0)   # a hollow under the seat, 2 m below her feet
	check(_sit_until_seated(w, g), "she sits (no terrain context: no levelling)")
	check(g.position.y >= 5.0 - 0.001, "she lies at the height of her feet, not in the hollow (%.2f)" % g.position.y)
	g.settle_on_ground(2.0)
	check(g.position.y >= 5.0 - 0.001, "sinking ground does not take her down")
	g.settle_on_ground(6.0)
	check_near(g.position.y, 6.0, "rising ground lifts her")
	g.stand_up()
	_tick_world(w)
	check_near(g.position.y, 5.0, "getting up she stands on her feet's ground again", 0.01)
	_free_world(w)


## Einebnen beim Sitzen (Nutzervorgaben 2026-11-18): beim Hinsetzen sofort der Auswahlkreis um
## die Sitzmitte, danach nach und nach der Rest der Figur — nur abgesenkt, nie angehoben;
## Gebaeude bleiben stehen, wie sie stehen.
func test_sitting_down_evens_out_the_ground_under_her() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _sit_golem(w, 0, Vector3(64, 5, 90))
	g.terrain_ctx = w.ctx
	var s: float = g.model_scale().z * g.size_factor()
	var fwd: Vector3 = g.heading()
	var seat: Vector3 = g.position - fwd * g.seat_back_m()
	var hands: Vector3 = g.position - fwd * (Balance.GOLEM_SIT_HAND_BACK * s)
	var ring: float = g.selection_ring_radius()
	var side: Vector3 = Vector3(fwd.z, 0.0, -fwd.x) * (ring * 0.5)
	check(seat.distance_to(hands) > ring, "(her hands lie outside the selection circle)")
	_set_ground(w, seat, 2.0, 3.5)          # a hollow under the seat
	_set_ground(w, seat + side, 1.0, 6.5)   # a bump in the selection circle
	_set_ground(w, hands, 1.5, 6.5)         # a bump under her hands
	var hut: Building = w.bm.place(HUT_SCENE, w.t0, Vector2i(80, 70), 0, true)   # her own: she does not turn to it
	var hut_corner: int = 70 * w.td.verts + 80
	var hut_h: float = w.td.heights[hut_corner]
	check(_sit_until_seated(w, g), "she sits")
	for i in range(10):
		_tick_world(w)
	var in_ring: Vector3 = seat + side
	check_near(w.td.get_height(in_ring.x, in_ring.z), 5.0, "the bump in her selection circle came down at once", 0.05)
	check_near(w.td.get_height(seat.x, seat.z), 3.5, "the hollow under the seat stays (nothing is raised)", 0.01)
	var early: float = w.td.get_height(hands.x, hands.z)
	check(early > 5.5, "the bump under her hands only begins to sink (%.2f m)" % early)
	for i in range(250):
		_tick_world(w)
	check_near(w.td.get_height(hands.x, hands.z), 5.0, "after a while it has come down to her feet' level", 0.05)
	check_near(g.position.y, 5.0, "and she lies on her feet's level, not on the old bump (%.2f)" % g.position.y, 0.05)
	check(hut == null or is_equal_approx(w.td.heights[hut_corner], hut_h), "the ground under a building stays")
	_free_world(w)


## Der Auswahlkreis (ihr Standpunkt) wechselt 0,5 s vor dem Aufsetzen auf die
## Sitzmitte; der Sitzschaden faellt erst beim Aufsetzen.
func test_the_ring_moves_onto_the_seat_half_a_second_early() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _sit_golem(w, 0, Vector3(64, 5, 90))
	var feet: Vector3 = g.position
	var seat: Vector3 = feet - g.heading() * g.seat_back_m()
	var foe: Unit = _foe(w, seat.x, seat.z, 1000)
	check(g.sit_down(), "she sits down")
	var moved_at: float = -1.0
	var hit_at: float = -1.0
	var t: float = 0.0
	while not g.is_sitting() and t < 10.0:
		g.tick(TICK)
		t += TICK
		if moved_at < 0.0 and _flat(g.position, seat) < 0.01:
			moved_at = t
		if hit_at < 0.0 and foe.health < 1000:
			hit_at = t
	check(moved_at > 0.0 and hit_at > 0.0, "both happened (%.1f / %.1f s)" % [moved_at, hit_at])
	check_near(hit_at - moved_at, Balance.GOLEM_SIT_SEAT_LEAD, "the position moved 0,5 s before the touch-down", TICK * 1.5)
	_free_world(w)


# --- Sitzangriffe (Vorarbeit 2026-11-17, GolemSitCombat / GolemSitAnim) ---------------
# Zwei Kanaele (Beine, Arme); jeder Angriff trifft, wo sein Clip das Glied hinsetzt (seit
# 2026-11-17); grosse Angriffe sperren beide; Drehen im Sitzen ohne Angriffe.

## A seated golem (facing +z) and her sit combat, the world otherwise frozen.
func _seated(w: Dictionary) -> Golem:
	var g: Golem = _sit_golem(w, 0, Vector3(64, 5, 70))
	_sit_until_seated(w, g)
	g.sit_combat = GolemSitCombat.new(g)
	return g


## Ticks only the golem until `cond` holds (or the limit).
func _tick_golem_until(g: Golem, cond: Callable, limit: int = 200) -> int:
	var n: int = 0
	while not cond.call() and n < limit:
		g.tick(TICK)
		n += 1
	return n


## 1. Fuss-Stampfer (Nutzervorgabe 2026-11-17): Aufschlag, wo der Schuh landet, Kreis mittlerer
## Groesse, der nicht hinter die Ferse des ruhenden Schuhs reicht; schnell, Werte des Handschlags.
func test_sit_stomp_lands_where_the_foot_comes_down() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _seated(w)
	var c: GolemSitCombat = g.sit_combat
	var f: Vector3 = c.feet_point()
	var fwd: Vector3 = g.heading()
	check_near(_flat(f, g.position), g.seat_back_m(), "the feet rest in front of the seat", 0.01)
	check(c.left().x > 0.9, "facing +z her left is +x (as in the model)")
	var fl: Vector3 = c.foot_point(1.0)
	var sl: Vector3 = c.stomp_point(1.0)
	check((fl - f).dot(c.left()) > 0.0 and (sl - fl).dot(fwd) > 0.0 and (sl - fl).dot(c.left()) > 0.0,
		"the left shoe lands ahead of and outside its resting place")
	var r: float = c.stomp_radius()
	check(r < g.slam_radius(), "a medium circle (%.1f m, slam %.1f m)" % [r, g.slam_radius()])
	check(c.in_area(GolemSitCombat.STOMP_L, sl + fwd * (r * 0.9)) and not c.in_area(GolemSitCombat.STOMP_L, sl + fwd * (r + 0.5)),
		"the circle around that spot")
	var heel: float = Balance.GOLEM_SIT_HEEL_BACK * g.model_scale().z * g.size_factor()
	var behind: Vector3 = sl - fwd * ((sl - f).dot(fwd) + heel + 0.05)
	check(not c.in_area(GolemSitCombat.STOMP_L, behind), "nothing behind the resting shoe's heel")
	check(GolemSitCombat.tempo_of(GolemSitCombat.STOMP_L) == Golem.ATTACK_SLAM
		and is_equal_approx(c.cooldown_of(GolemSitCombat.STOMP_L), g.cooldown_for(Golem.ATTACK_SLAM) * Balance.GOLEM_SIT_COOLDOWN_FACTOR),
		"quick: the crouched slam's tempo, seated 10 % faster")
	var foe: Unit = _foe(w, sl.x + r * 0.5, sl.z, 100000)
	_tick_golem_until(g, func() -> bool: return c.pending[GolemSitCombat.CH_LEGS] != &"")
	check(c.pending[GolemSitCombat.CH_LEGS] == GolemSitCombat.STOMP_L, "the LEFT foot stomps (%s)" % c.pending[GolemSitCombat.CH_LEGS])
	check(c.pending[GolemSitCombat.CH_ARMS] == &"", "the arms reach nothing there")
	_tick_golem_until(g, func() -> bool: return foe.health < 100000)
	check(foe.health == 100000 - g.attack_damage(Golem.ATTACK_SLAM),
		"it lands on the foe with the slam's damage (%d)" % (100000 - foe.health))
	_free_world(w)


## 5. Arm-Wischer: ein Kegel neben ihr auf seiner Seite, etwas hinter den Ruecken; Schaden
## und Zielzahl des Luftschlags. Ein Arm je Seite.
func test_sit_wipe_strikes_a_cone_beside_her_one_arm_each_side() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _seated(w)
	var c: GolemSitCombat = g.sit_combat
	var fwd: Vector3 = g.heading()
	var hl: Vector3 = c.hand_point(1.0)
	var hr: Vector3 = c.hand_point(-1.0)
	check(hl.x > g.position.x and hr.x < g.position.x and hl.z < g.position.z,
		"the hands rest beside and behind her hips")
	var reach: float = g.reach()
	var out_left: Vector3 = g.position + c.left() * (reach * 0.7)
	check(c.in_area(GolemSitCombat.WIPE_L, out_left) and not c.in_area(GolemSitCombat.WIPE_R, out_left),
		"straight out to the left: the left arm, not the right")
	var a: float = deg_to_rad(20.0)
	check(c.in_area(GolemSitCombat.WIPE_L, g.position + (c.left() * cos(a) - fwd * sin(a)) * reach * 0.7),
		"a little behind her back: yes")
	a = deg_to_rad(50.0)
	check(not c.in_area(GolemSitCombat.WIPE_L, g.position + (c.left() * cos(a) - fwd * sin(a)) * reach * 0.7),
		"far behind: no")
	check(not c.in_area(GolemSitCombat.WIPE_L, g.position + fwd * (reach * 0.7)), "straight ahead: no")
	var pelvis: float = Balance.GOLEM_SIT_WIPE_FRONT * g.model_scale().z * g.size_factor()
	var front: float = pelvis + reach * 0.6 * tan(deg_to_rad(Balance.GOLEM_SIT_WIPE_FRONT_DEG))   # the front edge leans 5 degrees forward
	check(c.in_area(GolemSitCombat.WIPE_L, g.position + c.left() * (reach * 0.6) + fwd * (front - 0.3))
		and not c.in_area(GolemSitCombat.WIPE_L, g.position + c.left() * (reach * 0.6) + fwd * (front + 0.5)),
		"it ends at her pelvis, leaning 5 degrees forward, not out at her legs")
	check(not c.in_area(GolemSitCombat.WIPE_L, g.position + c.left() * (reach + 0.5)), "beyond reach: no")
	var foe: Unit = _foe(w, g.position.x - reach * 0.6, g.position.z - 1.0, 100000)
	_tick_golem_until(g, func() -> bool: return c.pending[GolemSitCombat.CH_ARMS] != &"")
	check(c.pending[GolemSitCombat.CH_ARMS] == GolemSitCombat.WIPE_R, "the RIGHT arm wipes (%s)" % c.pending[GolemSitCombat.CH_ARMS])
	check(c.pending[GolemSitCombat.CH_LEGS] == &"", "only one arm, the legs stay")
	_tick_golem_until(g, func() -> bool: return foe.health < 100000)
	check(foe.health == 100000 - g.attack_damage(Golem.ATTACK_SWAT), "the swat's damage (%d)" % (100000 - foe.health))
	_free_world(w)


func test_sit_legs_and_arms_strike_at_the_same_time() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _seated(w)
	var c: GolemSitCombat = g.sit_combat
	var sl: Vector3 = c.stomp_point(1.0)
	_foe(w, sl.x, sl.z, 100000)
	_foe(w, g.position.x - g.reach() * 0.6, g.position.z - 1.0, 100000)
	var both: bool = false
	for i in range(40):
		g.tick(TICK)
		if c.pending[GolemSitCombat.CH_LEGS] != &"" and c.pending[GolemSitCombat.CH_ARMS] != &"" \
				and c.pending[GolemSitCombat.CH_LEGS] != c.pending[GolemSitCombat.CH_ARMS]:
			both = true
	check(both, "a foot and an arm wound up at once")
	_free_world(w)


## 2. Bein strecken: je Bein eine Schneise vom Koerper bis zur Spitze des gestreckten Schuhs,
## so schmal wie das Bein. Ein Feind unter dem rechten Knie: das rechte Bein (dort war vorher
## ein toter Winkel). Werte des Tritts.
func test_sit_leg_lane_runs_from_her_body_to_the_stretched_foot() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _seated(w)
	var c: GolemSitCombat = g.sit_combat
	var fwd: Vector3 = g.heading()
	var sz: float = g.model_scale().z * g.size_factor()
	var sx: float = g.model_scale().x * g.size_factor()
	var mid_r: Vector3 = c.impact_point(GolemSitCombat.KICK_R)
	check(c.in_kick_lane(mid_r + fwd * (Balance.GOLEM_SIT_KICK_TO * sz * 0.9), -1.0)
		and not c.in_kick_lane(mid_r + fwd * (Balance.GOLEM_SIT_KICK_TO * sz + 0.5), -1.0), "it ends just beyond the tip of the stretched shoe")
	check_near(Balance.GOLEM_SIT_KICK_TO * sz, 9.2, "9,2 m ahead of her feet at 31,3 m (user spec 2026-11-18)", 0.05)
	check(Balance.GOLEM_SIT_KICK_TO * sz > c._ahead_of_feet(c.stomp_point(-1.0)) + c.stomp_radius(),
		"it reaches further ahead than the foot stomp")
	check(c.in_kick_lane(mid_r - fwd * (Balance.GOLEM_SIT_KICK_FROM * sz * 0.9), -1.0)
		and not c.in_kick_lane(mid_r - fwd * (Balance.GOLEM_SIT_KICK_FROM * sz + 0.5), -1.0), "it starts at her hip")
	check(not c.in_kick_lane(mid_r - c.left() * (Balance.GOLEM_SIT_KICK_WIDTH * 0.5 * sx + 0.3), -1.0), "as narrow as the leg")
	var knee: Vector3 = mid_r - fwd * (Balance.GOLEM_SIT_KICK_FROM * sz * 0.5)
	check(c.in_kick_lane(knee, -1.0) and not c.in_kick_lane(knee, 1.0)
		and not c.in_area(GolemSitCombat.STOMP_R, knee) and not c.in_area(GolemSitCombat.WIPE_R, knee),
		"under her right knee: only the right leg's lane")
	var foe: Unit = _foe(w, knee.x, knee.z, 100000)
	_tick_golem_until(g, func() -> bool: return c.pending[GolemSitCombat.CH_LEGS] != &"")
	var kind: StringName = c.pending[GolemSitCombat.CH_LEGS]
	check(kind == GolemSitCombat.KICK_R, "she stretches the RIGHT leg (%s)" % kind)
	check(GolemSitCombat.channels_of(kind) == ([GolemSitCombat.CH_LEGS] as Array[int]), "the arms stay free for it")
	_tick_golem_until(g, func() -> bool: return foe.health < 100000)
	check(foe.health == 100000 - g.attack_damage(Golem.ATTACK_KICK), "the kick's damage")
	_free_world(w)


## 3./4./6. Die Werte der grossen Angriffe (Nutzervorgabe 2026-11-17).
func test_sit_big_attacks_take_the_users_values() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _seated(w)
	var c: GolemSitCombat = g.sit_combat
	var hop: StringName = GolemSitCombat.HOP
	check(c.damage(hop) == g.attack_damage(Golem.ATTACK_STOMP) and c.max_targets(hop) == g.max_targets_of(Golem.ATTACK_STOMP),
		"po clap: damage and targets of the jump")
	check_near(c.cooldown_of(hop), g.cooldown_for(Golem.ATTACK_STOMP) * Balance.GOLEM_SIT_HOP_COOLDOWN_FACTOR
		* Balance.GOLEM_SIT_HOP_SLOWER_COOLDOWN * Balance.GOLEM_SIT_COOLDOWN_FACTOR,
		"its cooldown: 1,1 x the jump's, about 0,2 s more at 30 m, seated 10 % faster (%.2f s)" % c.cooldown_of(hop))
	check_near(c.windup_of(hop), g.current_windup(Golem.ATTACK_STOMP) * Balance.GOLEM_SIT_HOP_SLOWER_ANIM,
		"its clip plays longer (wind-up %.2f s)" % c.windup_of(hop))
	var hop_r: float = g.stomp_radius() * Balance.GOLEM_SIT_AREA_FACTOR * Balance.GOLEM_SIT_HOP_AREA_FACTOR
	check_near(c.hop_radius(), hop_r, "its circle another 10 % smaller")
	check(c.in_area(hop, g.position + g.heading() * (hop_r * 0.95)) and not c.in_area(hop, g.position + g.heading() * (hop_r + 0.5)),
		"the jump's circle around the seat, 10 % smaller")
	var ds: StringName = GolemSitCombat.DOUBLE_STOMP
	check(c.damage(ds) > g.attack_damage(Golem.ATTACK_SWAT) and c.max_targets(ds) == g.max_targets_of(Golem.ATTACK_DRUM)
		and is_equal_approx(c.cooldown_of(ds), g.cooldown_for(Golem.ATTACK_DRUM) * Balance.GOLEM_SIT_COOLDOWN_FACTOR),
		"double stomp: more than the swat, the drum's targets, its cooldown 10 % shorter")
	check_near(c.cooldown_of(GolemSitCombat.CLAP), g.cooldown_for(Golem.ATTACK_DRUM) * Balance.GOLEM_SIT_CLAP_COOLDOWN_SHARE,
		"the hand stomp behind keeps its cooldown")
	check(c.in_area(ds, c.feet_point() - g.heading() * 1.0), "it reaches a little behind the feet")
	check(not c.in_area(ds, c.feet_point() + g.heading() * (c.double_stomp_radius() * 0.9)), "and not as far ahead as before")
	var clap: StringName = GolemSitCombat.CLAP
	check(c.damage(clap) == g.attack_damage(Golem.ATTACK_DRUM)
		and c.cooldown_of(clap) < g.cooldown_for(Golem.ATTACK_DRUM) and c.cooldown_of(clap) > g.cooldown_for(Golem.ATTACK_SLAM),
		"hand stomp behind: the drum's damage, a shorter cooldown (%.2f s)" % c.cooldown_of(clap))
	check_near(c.clap_radius(), g.ground_radius(Golem.ATTACK_DRUM) * Balance.GOLEM_SIT_CLAP_AREA_FACTOR,
		"its circles a share of the drum's (since 2026-11-18: 6 m at 31,3 m)")
	check_near(c.clap_radius(), 6.0, "6 m at her first sit size (user spec 2026-11-18)", 0.05)
	check(c.in_area(clap, c.hand_point(1.0)) and not c.in_area(clap, g.position + g.heading() * 1.0),
		"only behind her: at the hands yes, ahead of the seat no")
	_free_world(w)


func test_sit_big_attacks_take_both_channels() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _seated(w)
	var c: GolemSitCombat = g.sit_combat
	for kind in [GolemSitCombat.HOP, GolemSitCombat.CLAP, GolemSitCombat.DOUBLE_STOMP]:
		check(GolemSitCombat.channels_of(kind).size() == 2, "%s takes (or blocks) both channels" % kind)
	check(GolemSitCombat.layer_of(GolemSitCombat.HOP) == GolemSitAnim.LAYER_FULL
		and GolemSitCombat.layer_of(GolemSitCombat.STOMP_L) == GolemSitAnim.LAYER_LEGS
		and GolemSitCombat.layer_of(GolemSitCombat.WIPE_R) == GolemSitAnim.LAYER_ARMS, "and plays on the body layer")
	# A crowd around her feet: the double stomp beats a single foot.
	var f: Vector3 = c.feet_point()
	var crowd: Array = []
	for i in range(8):
		crowd.append(_foe(w, f.x + float(i % 4) - 1.5, f.z + 1.0 + float(i / 4), 100000))
	_tick_golem_until(g, func() -> bool: return c.is_busy())
	check(c.pending[GolemSitCombat.CH_LEGS] == GolemSitCombat.DOUBLE_STOMP
		and c.pending[GolemSitCombat.CH_ARMS] == GolemSitCombat.DOUBLE_STOMP,
		"a crowd at her feet: the double stomp, arms blocked (%s / %s)" % [c.pending[0], c.pending[1]])
	check(not c.channel_free(GolemSitCombat.CH_ARMS), "the arms are not free meanwhile")
	_tick_golem_until(g, func() -> bool: return not c.is_busy())
	var hit: int = 0
	for u in crowd:
		if u.health < 100000:
			hit += 1
	check(hit == mini(8, c.max_targets(GolemSitCombat.DOUBLE_STOMP)), "it strikes the crowd (%d)" % hit)
	# The hop strikes around the seat, the clap beside her hands.
	var seat_foe: Unit = _foe(w, g.position.x + g.seat_half_extent().x * 1.5, g.position.z, 100000)
	check(c.in_area(GolemSitCombat.HOP, seat_foe.position, Vector3.INF), "the hop's area is twice the seat")
	check(c.in_area(GolemSitCombat.CLAP, c.hand_point(1.0) + Vector3(1, 0, 0), Vector3.INF)
		and not c.in_area(GolemSitCombat.CLAP, c.feet_point(), Vector3.INF), "the clap lands beside her hands")
	_free_world(w)


## Sitzangriffe treffen feindliche Gebaeude: seit 2026-11-18 mit Lebenspunkten, der Haelfte dessen, was der
## Angriff einer Einheit naehme (wie im Stand); eigene nie.
func test_sit_attacks_take_a_stage_off_enemy_buildings_only() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _seated(w)
	var c: GolemSitCombat = g.sit_combat
	var sl: Vector3 = c.stomp_point(1.0)
	var sr: Vector3 = c.stomp_point(-1.0)
	var hut: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(int(sl.x), int(sl.z) + 2), 0, true)
	var own: Building = w.bm.place(HUT_SCENE, w.t0, Vector2i(int(sr.x) - 4, int(sr.z) + 2), 0, true)
	check(hut != null and own != null, "an enemy hut ahead on her left, her own on the right")
	check(c.building_in_area(GolemSitCombat.STOMP_L, hut), "the left foot's circle touches the enemy hut")
	var own_hp: int = own.health
	_tick_golem_until(g, func() -> bool: return not c.last_struck_buildings.is_empty())
	var kind: StringName = c.last_struck_buildings.keys()[0]
	check(hut.max_health - hut.health == Golem.building_damage_for(c.damage(kind)),
		"one strike = half its damage in hit points (%s: %d)" % [kind, hut.max_health - hut.health])
	for k in c.last_struck_buildings:
		check(not (c.last_struck_buildings[k] as Array).has(own), "never her own building (%s)" % k)
	check(own.health == own_hp, "her own hut is untouched")
	_free_world(w)


## Fahrzeuge im Sitzen (Nutzervorgabe 2026-11-18): die Sitzangriffe treffen feindliche Bodenfahrzeuge wie die
## Schlaege der Riesin im Stand — das Katapult ist sofort hin. (Luftschiffe nie.)
func test_sit_attacks_wreck_enemy_ground_vehicles() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _seated(w)
	var c: GolemSitCombat = g.sit_combat
	var sl: Vector3 = c.stomp_point(1.0)
	var cat: Unit = _spawn(w, CATAPULT_SCENE, 1, Vector3(sl.x, 5, sl.z))
	var own: Unit = _spawn(w, CATAPULT_SCENE, 0, Vector3(c.stomp_point(-1.0).x, 5, c.stomp_point(-1.0).z))
	check(c.in_area(GolemSitCombat.STOMP_L, cat.position), "(an enemy catapult in the left foot's circle)")
	_tick_golem_until(g, func() -> bool: return not is_instance_valid(cat) or cat.state == Unit.State.DEAD, 60)
	check(not is_instance_valid(cat) or cat.state == Unit.State.DEAD, "the stomp wrecks it")
	check(is_instance_valid(own) and own.state != Unit.State.DEAD, "her own catapult is spared")
	_free_world(w)


## Ein einzelner Feind zwischen den Schuhen oder hinter ihr wird getroffen (Nutzermeldung
## 2026-11-17: zwischen den Schuhen stand einer unbehelligt). Die Bein-Schneisen reichen bis
## zur Mitte; erreicht kein Einzelangriff etwas, kommen die grossen auch fuer ein Ziel.
func test_sit_no_blind_spot_between_the_shoes_or_behind_her() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _seated(w)
	var c: GolemSitCombat = g.sit_combat
	var mid: Vector3 = c.feet_point() - g.heading() * 2.0
	check(c.in_kick_lane(mid, 1.0) and c.in_kick_lane(mid, -1.0), "between the shoes: both legs' lanes")
	var foe: Unit = _foe(w, mid.x, mid.z, 100000)
	_tick_golem_until(g, func() -> bool: return foe.health < 100000)
	check(foe.health < 100000, "the foe between her shoes is struck")
	foe.health = 0
	foe.state = Unit.State.DEAD
	var w2: Dictionary = _make_world()
	var g2: Golem = _seated(w2)
	var c2: GolemSitCombat = g2.sit_combat
	var back: Vector3 = g2.position - g2.heading() * 3.0
	var single: bool = false
	for kind in [GolemSitCombat.STOMP_L, GolemSitCombat.STOMP_R, GolemSitCombat.KICK_L, GolemSitCombat.KICK_R,
			GolemSitCombat.WIPE_L, GolemSitCombat.WIPE_R]:
		single = single or c2.in_area(kind, back)
	check(not single, "right behind her hips no single attack reaches")
	var lone: Unit = _foe(w2, back.x, back.z, 100000)
	_tick_golem_until(g2, func() -> bool: return lone.health < 100000)
	check(lone.health < 100000, "a lone foe there is struck by a big attack (%s)" % str(c2.last_struck.keys()))
	_free_world(w2)
	_free_world(w)


## Waechst sie im Sitzen, treffen die gestreckten Beine wie der Tritt, in beiden
## Bein-Schneisen zugleich (Nutzervorgabe 2026-11-17).
func test_sit_growing_strikes_like_the_kick_in_both_lanes() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _seated(w)
	var c: GolemSitCombat = g.sit_combat
	var fwd: Vector3 = g.heading()
	var kl: Vector3 = c.impact_point(GolemSitCombat.KICK_L) - fwd * 3.0
	var kr: Vector3 = c.impact_point(GolemSitCombat.KICK_R) - fwd * 3.0
	var off: Vector3 = g.position + c.left() * (g.reach() * 0.7)   # beside her: the wipe's, not a leg's
	var a: Unit = _foe(w, kl.x, kl.z, 100000)
	var b: Unit = _foe(w, kr.x, kr.z, 100000)
	var o: Unit = _foe(w, off.x, off.z, 100000)
	check(c.damage(GolemSitCombat.GROW) == g.trample_damage()
		and c.max_targets(GolemSitCombat.GROW) == 2 * g.max_targets_of(Golem.ATTACK_KICK),
		"one trample tick's damage (user spec 2026-11-17), both lanes' targets")
	g._queue_stretch()
	g.tick(TICK)
	check(c._grow_left > 0.0, "growing on the seat owes the stretch's strike")
	c._land(GolemSitCombat.GROW, Vector3.INF)
	var dmg: int = g.trample_damage()
	check(a.health == 100000 - dmg and b.health == 100000 - dmg, "both legs' lanes are struck (%d)" % dmg)
	check(o.health == 100000, "beside her nothing")
	_free_world(w)


## Turm- und Deckschuetzen messen zum RAND des Zielkreises eines grossen Koerpers, wie die
## Schuetzen am Boden (Nutzermeldung 2026-11-17: Turm und Luftschiff schossen nicht auf eine
## sitzende Golemin, deren Mitte 11 m hinter den Fuessen ausser Reichweite lag).
func test_tower_and_airship_shoot_at_a_big_body_by_its_rim() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _seated(w)
	var r: float = g.target_radius()
	check(r > 2.0, "seated she is a big target (radius %.1f m)" % r)
	var tower: Watchtower = w.bm.place(load("res://scenes/buildings/watchtower.tscn"), w.t1, Vector2i(8, 8), 0, true) as Watchtower
	var reach_t: float = Firewarrior.FIRE_RANGE + Watchtower.TOWER_RANGE_BONUS
	var from_t: Vector3 = g.position - Vector3(reach_t + r * 0.5, 0.0, 0.0)
	w.um.tick(TICK)
	check(tower._nearest_enemy(from_t, reach_t) == g, "the tower's gunner aims at her: her rim is in reach, her middle is not")
	check(tower._nearest_enemy(g.position - Vector3(reach_t + r + 1.0, 0.0, 0.0), reach_t) == null, "beyond her rim: not")
	var reach_a: float = Firewarrior.FIRE_RANGE + Airship.RANGE_BONUS
	var ship: Airship = _spawn(w, AIRSHIP_SCENE, 1, g.position + Vector3(reach_a + r * 0.5, 5.0, 0.0)) as Airship
	w.um.tick(TICK)
	check(ship._best_enemy(reach_a) == g, "the airship's deck aims at her the same way")
	_free_world(w)


## Erreicht nichts ihre Glieder und steht kein Feind im Aggro-Radius, dreht sie sich zum
## naechsten feindlichen Gebaeude (Nutzermeldung 2026-11-17: zur Luftschiffwerft neben ihr
## drehte sie sich nie).
func test_sitting_she_turns_toward_an_enemy_building() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _seated(w)
	var c: GolemSitCombat = g.sit_combat
	var at: Vector3 = g.position + Vector3(0.0, 0.0, -g.reach() - 12.0)   # straight behind her, out of every zone
	var hut: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(int(at.x) - 2, int(at.z) - 2), 0, true)
	check(hut != null, "an enemy hut behind her")
	var reached: bool = false
	for kind in GolemSitCombat.KINDS:
		reached = reached or c.building_in_area(kind, hut)
	check(not reached, "no sit attack reaches it from here")
	_tick_golem_until(g, func() -> bool: return c.turning, 20)
	check(c.turning, "she turns toward it")
	_free_world(w)


## Waehrend des Drehens kein Angriff, es sei denn, die Lage aendert sich (Nutzervorgabe 2026-11-18):
## laeuft ihr ein Feind unter den Po, hoert sie auf zu drehen und greift an.
func test_sitting_the_po_clap_comes_while_she_turns() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _seated(w)
	var c: GolemSitCombat = g.sit_combat
	var far: Unit = _foe(w, g.position.x + 6.0, g.position.z - 17.0, 100000)   # behind her on the left
	_tick_golem_until(g, func() -> bool: return c.turning, 20)
	check(c.turning, "she turns toward the far foe")
	var under: Vector3 = g.position + g.heading() * 1.0
	var near: Unit = _foe(w, under.x, under.z, 100000)
	check(c.in_area(GolemSitCombat.HOP, near.position), "a foe under her, in the po clap's circle")
	_tick_golem_until(g, func() -> bool: return not c.turning, 10)
	check(not c.turning, "the situation changed: she stops turning")
	_tick_golem_until(g, func() -> bool: return c.is_busy(), 10)
	check(c.is_busy() and not c.turning, "and strikes the foe under her (%s)" % str(c.pending))
	check(far.health == 100000, "(the far one untouched)")
	_free_world(w)


## Stirbt das Ziel, zu dem sie sich dreht, hoert sie auf zu drehen (Nutzermeldung 2026-11-18:
## sie drehte sich weiter auf ein totes Ziel).
func test_sitting_she_stops_turning_when_the_target_is_gone() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _seated(w)
	var c: GolemSitCombat = g.sit_combat
	var foe: Unit = _foe(w, g.position.x + 6.0, g.position.z - 17.0, 100000)
	_tick_golem_until(g, func() -> bool: return c.turning, 20)
	check(c.turning, "she turns toward it")
	g.tick(TICK)
	var heading_then: Vector3 = g.heading()
	foe.health = 0
	foe.state = Unit.State.DEAD
	g.tick(TICK)
	g.tick(TICK)
	check(not c.turning, "the target died: she stops turning")
	check(g.heading().angle_to(heading_then) < deg_to_rad(5.0), "and stays facing where she was")
	_free_world(w)


## Die Drehung zaehlt in der Wahl (Nutzervorgabe 2026-11-18): trifft sie nach einer Drehung
## deutlich mehr, dreht sie sich dafuer — die Drehzeit als Vorlauf angerechnet wie im Stand.
func test_sitting_she_turns_for_a_much_better_attack() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _seated(w)
	var c: GolemSitCombat = g.sit_combat
	var fwd: Vector3 = g.heading()
	var turned: Vector3 = Vector3(fwd.z, 0.0, -fwd.x)   # a quarter turn to her left
	var saved: Vector3 = g._heading
	g._heading = turned
	var there: Vector3 = c.stomp_point(1.0)
	g._heading = saved
	check(not c.in_area(GolemSitCombat.STOMP_L, there) and not c.in_area(GolemSitCombat.STOMP_R, there),
		"(the spot lies outside her foot stomps as she sits now)")
	var lone: Unit = _foe(w, g.position.x - c.left().x * g.reach() * 0.6, g.position.z - c.left().z * g.reach() * 0.6, 100000)
	check(c.in_area(GolemSitCombat.WIPE_R, lone.position), "(one foe in her right wipe)")
	var group: Array[Unit] = []
	for i in range(6):
		var a: float = TAU * float(i) / 6.0
		group.append(_foe(w, there.x + cos(a) * 1.0, there.z + sin(a) * 1.0, 100000))
	_tick_golem_until(g, func() -> bool: return c.turning, 40)
	check(c.turning, "six foes a quarter turn away: she turns for them")
	# Toward a heading whose plan strikes the group (since 2026-11-18 — smaller foot stomps further back — that
	# may be the hand stomp behind her rather than the foot stomp after a quarter turn).
	var then: Vector3 = g._heading
	g._heading = c._turn_dir
	var plan: Dictionary = c._plan(c._foes_around(), [], 0.0, true)
	g._heading = then
	var struck: int = 0
	for part in plan.parts:
		if not part.is_empty():
			for u in part.hit:
				if group.has(u):
					struck += 1
	check(struck >= 5, "toward a plan that strikes the group (%d of 6, %s)" % [struck, str(plan.parts[0].get("kind", "-"))])
	check(c._turn_goal == null and c._turn_targets.size() >= 5, "she keeps what that plan strikes")
	# They die: she stops turning.
	for u in group:
		u.health = 0
		u.state = Unit.State.DEAD
	_tick_golem_until(g, func() -> bool: return not c.turning, 4)   # her next think
	check(not c.turning, "they are dead: she stops turning")
	_free_world(w)


## ... aber nicht fuer ein einzelnes Ziel, wenn sie schon eines erreicht: die Drehzeit frisst den Vorteil.
func test_sitting_she_does_not_turn_for_one_more_foe() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _seated(w)
	var c: GolemSitCombat = g.sit_combat
	var fwd: Vector3 = g.heading()
	var saved: Vector3 = g._heading
	g._heading = -fwd   # half a turn
	var there: Vector3 = c.stomp_point(1.0)
	g._heading = saved
	var here: Vector3 = c.stomp_point(1.0)
	_foe(w, here.x, here.z, 100000)   # in her left foot stomp
	_foe(w, there.x, there.z, 100000)   # where it would come down after half a turn
	for kind in GolemSitCombat.KINDS:
		if kind != GolemSitCombat.GROW and c.in_area(kind, there):
			check(false, "(the second one is out of her reach now: %s)" % kind)
	var turned: bool = false
	var wiped: bool = false
	for i in range(40):   # a whole round over the headings and more
		g.tick(TICK)
		turned = turned or c.turning
		wiped = wiped or c.pending[GolemSitCombat.CH_LEGS] == GolemSitCombat.STOMP_L
	check(wiped and not turned, "she stomps the one in reach and does not turn for the other")
	_free_world(w)


## Flaechen und Reichweiten im Stand: unter 30 m wie bisher, ab 30 m genau mit dem Koerper
## (Nutzervorgabe 2026-11-18) — mit den Anteilen des normalen Golems bei 31,3 m, alle drei Golems.
func test_standing_areas_grow_with_the_body_from_thirty_metres() -> void:
	var g: Golem = GOLEM_SCENE.instantiate() as Golem
	check_near(g.reach(), Golem.REACH, "fresh: the reach as before (3 m)")
	check_near(g.slam_radius(), Golem.SLAM_RADIUS, "and the slam's circle (2,6 m)")
	while g.level < Balance.GOLEM_MAX_LEVEL:
		g._credit_kill()
	check(not g.body_scaled(), "(16,9 m: below 30 m)")
	check_near(g.reach_factor(), g._base_reach_factor(), "level 7: its own slow growth")
	check_near(g.limb_factor(), g._base_limb_factor(), "and its own limbs")
	while not g.can_sit():
		g._credit_kill()
	check(g.body_scaled(), "31,3 m: body-scaled")
	check_near(g.reach_factor(), g._base_reach_factor(), "at 31,3 m no jump: lane width", 0.0001)
	check_near(g.slam_scale(), g._base_slam_scale(), "slam", 0.0001)
	check_near(g.limb_factor(), g._base_limb_factor(), "reach", 0.0001)
	check_near(g.kick_limb_factor(), 1.0 + (g._base_limb_factor() - 1.0) * Golem.kick_growth_share(), "lane length", 0.0001)
	var w31: float = g.model_scale().x * g.size_factor()
	var shares: Array[float] = [g.reach() / w31, g.slam_radius() / w31, g._kick_extent().x / w31]
	while not g.is_full_size():
		g._credit_kill()
	var w80: float = g.model_scale().x * g.size_factor()
	check_near(g.reach() / w80, shares[0], "80 m: the reach keeps its share of the body", 0.0001)
	check_near(g.slam_radius() / w80, shares[1], "the slam's circle too", 0.0001)
	check_near(g._kick_extent().x / w80, shares[2], "and the kick's lane", 0.0001)
	g.free()
	var s: GenesisGolem = (load("res://scenes/units/genesis_golem.tscn") as PackedScene).instantiate() as GenesisGolem
	s.wood_growth_m = 100.0
	var ws: float = s.model_scale().x * s.size_factor()
	check_near(s.reach() / ws, shares[0], "the genesis golem at 100 m: the same share of his body", 0.0001)
	check_near(s.slam_radius() / ws, shares[1], "(slam)", 0.0001)
	s.free()


## Alle Sitzzonen wachsen genau mit dem Koerper (Nutzervorgabe 2026-11-18): die Aufteilung bleibt
## ueber alle Groessen und bei allen drei Golems gleich; in der ersten Sitzgroesse aendert sich nichts.
func test_sit_zones_grow_exactly_with_the_body() -> void:
	var g: Golem = GOLEM_SCENE.instantiate() as Golem
	while not g.can_sit():
		g._credit_kill()
	var c: GolemSitCombat = GolemSitCombat.new(g)
	check_near(c.stomp_radius(), g.slam_radius() * Balance.GOLEM_SIT_STOMP_RADIUS_SHARE * Balance.GOLEM_SIT_AREA_FACTOR,
		"first seated size: the foot stomp as before (%.2f m)" % c.stomp_radius(), 0.001)
	check_near(c.wipe_reach(), g.reach() * Balance.GOLEM_SIT_AREA_FACTOR, "the wipe as before", 0.001)
	check_near(c.clap_radius(), g.ground_radius(Golem.ATTACK_DRUM) * Balance.GOLEM_SIT_CLAP_AREA_FACTOR, "the hand stomp as before", 0.001)
	var at_first: Array = _sit_zone_shares(g, c)
	while not g.is_full_size():
		g._credit_kill()
	var at_full: Array = _sit_zone_shares(g, c)
	for i in range(at_first.size()):
		check_near(at_full[i], at_first[i], "80 m: zone %d keeps its share of the body (%.3f)" % [i, at_full[i]], 0.0005)
	check_near(g.reach(), 0.499 * 80.0, "standing too: 80 m reach about 40 m (%.1f)" % g.reach(), 0.2)
	check_near(g.slam_radius(), 0.225 * 80.0, "the slam's circle about 18 m (%.1f)" % g.slam_radius(), 0.2)
	g.free()
	var d: DemonGolem = (load("res://scenes/units/demon_golem.tscn") as PackedScene).instantiate() as DemonGolem
	while not d.can_sit():
		d.growth_steps += 1
	var dc: GolemSitCombat = GolemSitCombat.new(d)
	var d_first: Array = _sit_zone_shares(d, dc)
	while d.height_m() < 118.0:
		d.growth_steps += 1
	var d_top: Array = _sit_zone_shares(d, dc)
	for i in range(at_first.size()):
		check_near(d_first[i], at_first[i], "the demon golem: zone %d, same share of his body" % i, 0.0005)
		check_near(d_top[i], at_first[i], "and at %.0f m" % d.height_m(), 0.0005)
	d.free()
	var s: GenesisGolem = (load("res://scenes/units/genesis_golem.tscn") as PackedScene).instantiate() as GenesisGolem
	s.wood_growth_m = 100.0
	var sc: GolemSitCombat = GolemSitCombat.new(s)
	var s_top: Array = _sit_zone_shares(s, sc)
	for i in range(at_first.size()):
		check_near(s_top[i], at_first[i], "the genesis golem at 100 m: zone %d, same share" % i, 0.0005)
	s.free()


## Every sit zone measured in the model's width at her size.
func _sit_zone_shares(g: Golem, c: GolemSitCombat) -> Array:
	c._ck = [Vector3.INF, Vector3.INF, -1.0]
	var sx: float = c._sx()
	var sz: float = c._sz()
	return [c.stomp_radius() / sx, c.wipe_reach() / sx, c.clap_radius() / sx, c.double_stomp_radius() / sx,
		c.hop_radius() / sx, g.seat_back_m() / sz, (Balance.GOLEM_SIT_KICK_FROM + Balance.GOLEM_SIT_KICK_TO) * sz / sz]


## Ab 30 m ertrinken Golems nicht und laufen durchs Wasser (Nutzervorgabe 2026-11-18); darunter nicht.
func test_from_thirty_metres_golems_wade_through_water() -> void:
	var w: Dictionary = _shore_world()
	var small: Golem = _golem(w, 0, Vector3(45.5, 5, 40.5))
	_level_to(small, 7)
	small._stretch_queued = false
	check(not small.crosses_water(), "(17 m: not yet)")
	check(w.commands.order_move([small] as Array[Unit], Vector3(75.5, 1.4, 40.5)) == 0,
		"a 17-m golem is not sent into open water")
	var big: Golem = _golem(w, 0, Vector3(45.5, 5, 60.5))
	while not big.crosses_water():
		big._credit_kill()
	big._stretch_queued = false
	check(big.height_m() >= 30.0, "(%.1f m)" % big.height_m())
	check(Golem.giant_line_clear(w.td, big.position, Vector3(75.5, 1.4, 60.5), big.giant_step_limit(), true)
		and not Golem.giant_line_clear(w.td, big.position, Vector3(75.5, 1.4, 60.5), big.giant_step_limit()),
		"the straight line into the sea: clear only with water allowed")
	check(w.commands.order_move([big] as Array[Unit], Vector3(75.5, 1.4, 60.5)) == 1, "a 31-m golem takes the order")
	for i in range(200):
		_tick_world(w)
		if big.position.x > 74.0:
			break
	check(big.position.x > 74.0, "she walks into the sea (x %.1f)" % big.position.x)
	check(big.state != Unit.State.DEAD and not big.is_flooded_on(w.td), "and does not drown there")
	_free_world(w)


## Terrain beim Hinsetzen (Nutzervorgabe 2026-11-18): Haende und Fuesse muessen auf Boden aufsetzen,
## den sie erklimmen koennte — an einer Klippe setzt sie sich nicht.
func test_she_does_not_sit_down_where_a_hand_would_rest_on_a_cliff() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _sit_golem(w, 0, Vector3(64, 5, 90))
	var fwd: Vector3 = g.heading()
	var seat: Vector3 = g.position - fwd * g.seat_back_m()
	check(g.sit_pose_ok(seat, fwd), "flat ground: she could sit")
	var hand: Vector3 = g.sit_contacts(seat, fwd)[2]
	_set_ground(w, hand, 6.0, 45.0)   # a 40-m block under her left hand (and the spots around)
	check(not g.sit_pose_ok(seat, fwd), "a 40-m cliff between seat and hand: no")
	g.sit_down()
	for i in range(150):
		_tick_world(w)
	check(not g.is_sitting(), "she does not sit down there")
	_free_world(w)


## Drehen im Sitzen nur ueber moegliche Richtungen (Nutzervorgabe 2026-11-18): ist der kurze Weg
## blockiert, dreht sie sich den langen Weg herum; ist die Zielrichtung selbst unmoeglich, gar nicht.
func test_seated_she_turns_only_through_possible_headings() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _seated(w)
	var c: GolemSitCombat = g.sit_combat
	var at: Callable = func(deg: float) -> Vector3:
		var a: float = deg_to_rad(deg)
		return Vector3(sin(a), 0.0, cos(a))
	check(g.heading().angle_to(at.call(0.0)) < 0.01, "(she faces +z, angle 0)")
	# A tall pillar where one of her feet would rest at +45 degrees (the other foot meets it a
	# little further on — both on the short way; a pillar under a hand would block both ways).
	var pillar: Vector3 = g.sit_contacts(g.position, at.call(45.0))[0]
	_set_ground(w, pillar, 0.5, 45.0)   # narrow: her hands, closer in, never touch it
	check(not g.sit_heading_ok(at.call(45.0)), "at +45 degrees her foot would rest on the pillar")
	check(g.sit_heading_ok(at.call(0.0)) and g.sit_heading_ok(at.call(90.0)), "0 and +90 degrees are fine")
	var way: Dictionary = c.turn_way(at.call(90.0), c.free_arc())
	check(way.sign == -1.0 and absf(rad_to_deg(float(way.angle)) - 270.0) < 0.5,
		"to +90 degrees she turns the long way round (%s)" % str(way))
	# A foe out at +90 degrees, beyond every zone but within their scan: she turns toward it — the long way.
	var foe_at: Vector3 = g.position + at.call(90.0) * 30.0
	_foe(w, foe_at.x, foe_at.z, 100000)
	_tick_golem_until(g, func() -> bool: return c.turning, 20)
	check(c.turning and c._turn_sign == -1.0, "she turns the long way round toward the foe")
	var crossed: bool = false
	for i in range(600):
		g.tick(TICK)
		var a: float = rad_to_deg(atan2(g.heading().x, g.heading().z))
		crossed = crossed or (a > 30.0 and a < 60.0)
		if not c.turning:
			break
	check(not crossed, "never through the blocked headings")
	check(g.heading().angle_to(at.call(90.0)) < deg_to_rad(5.0), "and arrives at +90 degrees")
	_free_world(w)


func test_seated_she_does_not_turn_toward_an_impossible_heading() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _seated(w)
	var c: GolemSitCombat = g.sit_combat
	var east: Vector3 = Vector3(1, 0, 0)
	var pillar: Vector3 = g.sit_contacts(g.position, east)[2]
	_set_ground(w, pillar, 1.0, 45.0)
	check(not g.sit_heading_ok(east), "facing +x her hand would rest on the pillar")
	check(c.turn_way(east, c.free_arc()).sign == 0.0, "so she cannot turn there")
	var foe_at: Vector3 = g.position + east * 30.0
	_foe(w, foe_at.x, foe_at.z, 100000)
	for i in range(20):
		g.tick(TICK)
	check(not c.turning, "a foe that way: she does not turn (and cannot strike it)")
	_free_world(w)


## Kleine Golems an grossen (Nutzervorgabe 2026-11-18): wer hoechstens bis zu den Knien des anderen
## reicht, haelt nur Abstand zu dessen Beinbereich (60 % seines Koerperradius).
func test_a_knee_high_golem_meets_only_the_big_ones_legs() -> void:
	var w: Dictionary = _make_world()
	var big: Golem = _golem(w, 0, Vector3(40, 5, 40))
	while not big.is_full_size():
		big._credit_kill()
	var small: Golem = _golem(w, 1, Vector3(70, 5, 70))
	_level_to(small, 6)
	check(small.height_m() <= big.height_m() * Balance.GOLEM_KNEE_HEIGHT_SHARE, "(%.1f m next to %.1f m: knee high)" % [small.height_m(), big.height_m()])
	var legs: float = (small.trample_radius() + big.trample_radius() * Balance.GOLEM_LEG_RADIUS_SHARE) * Balance.GOLEM_BODY_GAP
	check_near(small._golem_need(big), legs, "the small one keeps clear of the legs only (%.1f m)" % legs)
	check_near(big._golem_need(small), legs, "the same distance for both")
	var mid: Golem = _golem(w, 1, Vector3(90, 5, 40))
	while mid.height_m() < big.height_m() * 0.5:
		mid._credit_kill()
	check_near(mid._golem_need(big), (mid.trample_radius() + big.trample_radius()) * Balance.GOLEM_BODY_GAP,
		"a golem half as tall keeps the whole body's distance")
	# In play: closer than the whole body's distance, but clear of the legs — nobody is pushed.
	small.position = big.position + Vector3(legs + 0.5, 0, 0)
	var at: Vector3 = small.position
	for i in range(20):
		small._tick_golem_separation(TICK)
	check(small.position.distance_to(at) < 0.01, "standing at her legs, the small one is not pushed away")
	_free_world(w)


## Kein grundloses Drehen (Bugmeldung 2026-11-18): zu einem Feind, den nach dem Drehen keine Zone
## erreichen koennte, dreht sie sich nicht.
func test_seated_she_does_not_turn_toward_a_foe_no_zone_could_reach() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _seated(w)
	var c: GolemSitCombat = g.sit_combat
	var far: Vector3 = g.position + Vector3(1, 0, 0) * (c._scan_radius() + 8.0)
	check(_flat(far, g.position) < g.aggro_radius(), "(the foe stands within her aggro radius)")
	_foe(w, far.x, far.z, 100000)
	for i in range(30):
		g.tick(TICK)
	check(not c.turning and g.heading().angle_to(Vector3(0, 0, 1)) < 0.01, "beyond every zone: she does not turn")
	_free_world(w)


## Wird die Sitzlage unmoeglich (gewachsen, Boden veraendert), dreht sie sich, bis sie wieder sitzen
## kann — gibt es keine moegliche Richtung, steht sie auf (Nutzervorgabe 2026-11-18).
func test_seated_she_turns_out_of_an_impossible_pose_or_gets_up() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _seated(w)
	var c: GolemSitCombat = g.sit_combat
	var foot: Vector3 = g.sit_contacts(g.position, g.heading())[0]
	_set_ground(w, foot, 0.5, 45.0)
	check(not g.sit_heading_ok(g.heading()), "a pillar under her foot: this pose is impossible now")
	_tick_golem_until(g, func() -> bool: return c.turning, 10)
	check(c.turning and c._turn_escape, "she turns out of it")
	_tick_golem_until(g, func() -> bool: return not c.turning, 300)
	check(g.sit_heading_ok(g.heading()) and g.is_sitting(), "and sits where she can")
	_free_world(w)
	# All round impossible: a wall where her feet and hands rest, in every direction.
	var w2: Dictionary = _make_world()
	var g2: Golem = _seated(w2)
	var c2: GolemSitCombat = g2.sit_combat
	var near_r: float = INF
	var far_r: float = 0.0
	for p in g2.sit_contacts(g2.position, g2.heading()):
		near_r = minf(near_r, _flat(p, g2.position))
		far_r = maxf(far_r, _flat(p, g2.position))
	var td: TerrainData = w2.td
	for vz in range(td.verts):
		for vx in range(td.verts):
			var d: float = Vector2(float(vx) - g2.position.x, float(vz) - g2.position.z).length()
			if d >= near_r - 1.0 and d <= far_r + 1.0:
				td.heights[vz * td.verts + vx] = 45.0
	check(not g2.sit_heading_ok(g2.heading()), "(a wall all round)")
	for i in range(10):
		g2.tick(TICK)
	check(not g2._wants_sit, "no heading works: she gets up")
	_free_world(w2)


## Dreht sie sich fuer einen besseren Plan, kommt zwischendurch kein Angriff (Nutzervorgabe 2026-11-18).
func test_seated_she_does_not_strike_while_she_turns() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _seated(w)
	var c: GolemSitCombat = g.sit_combat
	var fwd: Vector3 = g.heading()
	var turned: Vector3 = Vector3(fwd.z, 0.0, -fwd.x)
	var saved: Vector3 = g._heading
	g._heading = turned
	var there: Vector3 = c.stomp_point(1.0)
	g._heading = saved
	for i in range(6):
		var a: float = TAU * float(i) / 6.0
		_foe(w, there.x + cos(a), there.z + sin(a), 100000)
	_tick_golem_until(g, func() -> bool: return c.turning, 40)
	check(c.turning, "six foes a quarter turn away: she turns")
	var struck: bool = false
	var ticks: int = 0
	while c.turning and ticks < 300:
		g.tick(TICK)
		ticks += 1
		struck = struck or (c.turning and c.is_busy())
	check(not struck, "no attack on the way")
	_free_world(w)


## Bugmeldung 2026-11-18: sie drehte manchmal genau falsch herum. Laeuft das Ziel, zu dem sie sich
## dreht, auf die andere Seite ihrer Blickrichtung, dreht sie den kurzen Weg dorthin — nicht weiter
## die ganze Runde in der ersten Richtung.
func test_seated_she_turns_the_short_way_when_the_target_crosses() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _seated(w)
	var c: GolemSitCombat = g.sit_combat
	var at: Callable = func(deg: float) -> Vector3:
		var a: float = deg_to_rad(deg)
		return Vector3(sin(a), 0.0, cos(a))
	var p: Vector3 = g.position + at.call(60.0) * 30.0
	var foe: Unit = _foe(w, p.x, p.z, 100000)
	_tick_golem_until(g, func() -> bool: return c.turning, 20)
	check(c.turning and c._turn_sign > 0.0, "she turns toward +60 degrees")
	for i in range(5):
		g.tick(TICK)
	var q: Vector3 = g.position + at.call(-40.0) * 30.0
	foe.position = q
	foe._sync_soa_pos()
	var worst: float = 0.0
	for i in range(300):
		g.tick(TICK)
		var a: float = rad_to_deg(atan2(g.heading().x, g.heading().z))
		worst = maxf(worst, absf(a))
		if not c.turning:
			break
	check(worst < 90.0, "it ran across to -40 degrees: she turns back the short way (never past %.0f degrees)" % worst)
	check(g.heading().angle_to(at.call(-40.0)) < deg_to_rad(5.0), "and faces it")
	_free_world(w)


## Dauer des Streckens mit der Groesse (Nutzervorgabe 2026-11-18): 1 s bei Startgroesse, leicht exponentiell
## bis 4 s bei 120 m — am Anfang waechst sie kaum.
func test_the_stretch_takes_longer_the_bigger_she_is() -> void:
	check_near(Golem.grow_time_for(Balance.GOLEM_HEIGHT), 1.0, "starting size: 1 s")
	check_near(Golem.grow_time_for(2.0), 1.0, "smaller (the 2-m demon golem): still 1 s")
	check_near(Golem.grow_time_for(120.0), 4.0, "120 m: 4 s")
	var mid: float = Golem.grow_time_for((Balance.GOLEM_HEIGHT + 120.0) * 0.5)
	check(mid < 2.5 and mid > 1.0, "half way it is still well below the straight line (%.2f s)" % mid)
	check(Golem.grow_time_for(30.0) < 1.5, "30 m: hardly longer (%.2f s)" % Golem.grow_time_for(30.0))


## Im Sitzen reiht sich das Strecken ein (Nutzervorgabe 2026-11-18): erst wenn kein Angriff mehr aussteht;
## solange es aussteht und laeuft, kommt kein neuer Angriff.
func test_seated_the_stretch_queues_behind_her_attacks() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _seated(w)
	var c: GolemSitCombat = g.sit_combat
	var sl: Vector3 = c.stomp_point(1.0)
	_foe(w, sl.x, sl.z, 100000)
	_tick_golem_until(g, func() -> bool: return c.is_busy(), 20)
	check(c.is_busy(), "(she winds up a stomp)")
	g._queue_stretch()
	g.tick(TICK)
	check(not g.sit_stretching() and g._stretch_queued, "the stretch waits while the attack is wound up")
	_tick_golem_until(g, func() -> bool: return g.sit_stretching(), 30)
	check(g.sit_stretching() and not c.is_busy(), "it starts once the attack has landed")
	var struck: bool = false
	var ticks: int = 0
	while g.sit_stretching() and ticks < 100:
		g.tick(TICK)
		ticks += 1
		struck = struck or c.pending[GolemSitCombat.CH_LEGS] != &"" or c.pending[GolemSitCombat.CH_ARMS] != &""
	check(not struck, "no attack while she stretches")
	check_near(float(ticks) * TICK, g.grow_time(), "it takes her stretch time (%.1f s)" % (float(ticks) * TICK), TICK * 1.5)
	_free_world(w)


## Erreicht kein Glied einen Feind, dreht sie sich langsam zu ihm (um den Po) — und
## greift waehrenddessen nicht an.
func test_sitting_she_turns_slowly_toward_an_enemy_out_of_reach() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _seated(w)
	var c: GolemSitCombat = g.sit_combat
	var seat: Vector3 = g.position
	# Behind her on the left (160 degrees off her heading, 18 m): no arm's cone and not the
	# hand stomp behind her reach it; once she faces it, her foot and leg do.
	var foe: Unit = _foe(w, seat.x + 6.0, seat.z - 17.0, 100000)
	var reaches: bool = false
	for kind in [GolemSitCombat.STOMP_L, GolemSitCombat.STOMP_R, GolemSitCombat.KICK_L, GolemSitCombat.KICK_R,
			GolemSitCombat.WIPE_L, GolemSitCombat.WIPE_R]:
		reaches = reaches or c.in_area(kind, foe.position)
	check(not reaches, "no limb reaches the foe")
	g.tick(TICK)
	g.tick(TICK)
	g.tick(TICK)
	check(c.turning and g.is_sit_turning(), "she turns toward it")
	check(g._sit_base_clip() == GolemSitAnim.CLIP_TURN_L, "to the left: sit_turn_l")
	if g._anim != null and g._anim.has_animation(GolemSitAnim.CLIP_TURN_L):
		check(g._anim.get_animation(GolemSitAnim.CLIP_TURN_L).loop_mode == Animation.LOOP_LINEAR,
			"the turn clip loops (it froze after one pass)")
	check_near(g.turn_rate(), Golem.sit_turn_rate_at(g.height_m()), "the seated turn rate of her height")
	check_near(rad_to_deg(Golem.sit_turn_rate_at(30.0)), rad_to_deg(Golem.standing_turn_rate(30.0)) * 0.125, "30 m: an eighth of the standing rate (41 deg/s)", 0.1)
	check_near(rad_to_deg(Golem.sit_turn_rate_at(80.0)), 13.0, "80 m: 13 deg/s (user spec 2026-11-18)", 0.01)
	check(Golem.sit_turn_rate_at(83.0) < Golem.sit_turn_rate_at(80.0), "beyond 80 m it falls on")
	check_near(rad_to_deg(Golem.sit_turn_rate_at(100.0)), 9.5, "down to 9,5 deg/s", 0.01)
	check_near(rad_to_deg(Golem.sit_turn_rate_at(120.0)), 9.5, "and no lower", 0.01)
	var struck: bool = false
	var ticks: int = 0
	while c.turning and ticks < 400:
		g.tick(TICK)
		ticks += 1
		struck = struck or (c.turning and c.is_busy())
	check(not c.turning, "she has turned (%.1f s)" % (float(ticks) * TICK))
	check(not struck, "no attack while turning")
	check(_flat(g.position, seat) < 0.01, "she turned about her hips, on the spot")
	check(g._seat_fwd.is_equal_approx(g.heading()), "the seat turned with her")
	_tick_golem_until(g, func() -> bool: return foe.health < 100000, 100)
	check(foe.health < 100000, "then a limb reaches it")
	_free_world(w)


## Die Animationsebenen: Beine, Arme und Koerper getrennt; ohne die Clips bleibt der
## Baum aus. Seit 2026-11-17 bringt das Modell die Clips mit (sit_stomp_l ...); fehlen
## sie einem Modell, laeuft der Test mit einem Ersatzclip (der Tritt als sit_stomp_l).
func test_sit_animation_layers_filter_legs_and_arms() -> void:
	var root: Node3D = (load("res://assets/models/units/golem.glb") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(root)
	var player: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	var layers: GolemSitAnim = GolemSitAnim.new(player)
	var has_clips: bool = player.has_animation(&"sit_stomp_l")
	check(layers.tree != null, "the tree is built")
	check(layers.usable() == has_clips, "it is in use exactly when the model brings sit attack clips")
	check(layers.leg_paths.size() == 6 and layers.arm_paths.size() == 8,
		"6 leg and 8 arm tracks (%d / %d)" % [layers.leg_paths.size(), layers.arm_paths.size()])
	var legs: AnimationNodeOneShot = layers._blend.get_node(&"legs") as AnimationNodeOneShot
	var arms: AnimationNodeOneShot = layers._blend.get_node(&"arms") as AnimationNodeOneShot
	var leg_path: NodePath = layers.leg_paths[0]
	var arm_path: NodePath = layers.arm_paths[0]
	check(legs.is_path_filtered(leg_path) and not legs.is_path_filtered(arm_path), "the leg layer moves only legs")
	check(arms.is_path_filtered(arm_path) and not arms.is_path_filtered(leg_path), "the arm layer moves only arms")
	check(layers.head_paths.size() == 2 and arms.is_path_filtered(layers.head_paths[0])
		and arms.is_path_filtered(layers.head_paths[1]) and not legs.is_path_filtered(layers.head_paths[0]),
		"... and neck and head (%d tracks): the head turns with the wipe" % layers.head_paths.size())
	check(not (layers._blend.get_node(&"full") as AnimationNodeOneShot).filter_enabled, "the body layer moves everything")
	var arm_torso: AnimationNodeOneShot = layers._blend.get_node(&"arm_torso") as AnimationNodeOneShot
	check(layers.torso_paths.size() >= 2 and arm_torso.is_path_filtered(layers.torso_paths[0])
		and arm_torso.is_path_filtered(arm_path) and arm_torso.is_path_filtered(layers.head_paths[1])
		and not arm_torso.is_path_filtered(leg_path) and not arms.is_path_filtered(layers.torso_paths[0]),
		"the arm+torso layer (side hand slam): arms, upper body (%d tracks), neck and head, no legs; the wipe's layer keeps the upper body still" % layers.torso_paths.size())
	if not has_clips:
		var lib: AnimationLibrary = player.get_animation_library(&"")
		lib.add_animation(&"sit_stomp_l", player.get_animation(&"kick").duplicate())
	check(layers.usable(), "with a sit clip the layers come into use")
	layers.set_active(true)
	check(layers.fire(GolemSitAnim.LAYER_LEGS, &"sit_stomp_l", 0.7), "the stomp fires on the leg layer")
	check(not layers.fire(GolemSitAnim.LAYER_ARMS, &"sit_no_such_clip", 0.35), "a missing clip does not")
	layers.tree.advance(0.05)
	check(layers.layer_running(GolemSitAnim.LAYER_LEGS) and not layers.layer_running(GolemSitAnim.LAYER_ARMS),
		"the leg layer runs, the arm layer does not")
	check_near(float(layers.tree.get("parameters/legs_speed/scale")), 0.35 / 0.7,
		"played so that the impact meets the wind-up", 0.0001)
	if player.has_animation(GolemSitAnim.CLIP_TURN_L):
		layers.set_base(GolemSitAnim.CLIP_TURN_L)
		layers.tree.advance(0.05)
		check(String(layers.tree.get("parameters/base/current_state")) == "turn_l",
			"turning: the base blends over to sit_turn_l (%s)" % str(layers.tree.get("parameters/base/current_state")))
	root.queue_free()


# --- Krebsgang (Nutzervorgabe 2026-11-18) -----------------------------------------------

## Eine sitzende Golemin bei (64, 40), Blick +z, mit dem Schalter "Stationaer" aus.
func _crab_golem(w: Dictionary, at: Vector3 = Vector3(64, 5, 40)) -> Golem:
	var g: Golem = _sit_golem(w, 0, at)
	g.sit_attacks_enabled = false
	_sit_until_seated(w, g)
	g.set_sit_stationary(false)
	return g


## Laeuft die Welt, bis `cond` gilt (oder das Limit); gibt die Zahl der Ticks zurueck.
func _run_until(w: Dictionary, cond: Callable, limit: int = 2000) -> int:
	var ticks: int = 0
	while not cond.call() and ticks < limit:
		_tick_world(w)
		ticks += 1
	return ticks


## Schalter "Stationaer": ein frischer Golem ist stationaer (wie bisher, Bewegungsbefehle im Sitzen
## prallen ab); aus, nimmt die Sitzende Bewegungsbefehle an.
func test_crab_switch_stationary_decides_whether_she_takes_orders() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _sit_golem(w, 0, Vector3(64, 5, 40))
	check(g.sit_stationary, "a fresh golem is stationary")
	check(_sit_until_seated(w, g), "she sits")
	var sel: Array[Unit] = [g]
	check(w.commands.order_move(sel, Vector3(64, 5, 70)) == 0 and g.sit_refuses_orders(),
		"stationary: the move order reaches nobody")
	check(w.commands.set_golem_stationary(sel, false) == 1 and not g.sit_stationary, "switched off")
	check(not g.sit_refuses_orders() and not g.can_take_orders(),
		"now move and attack orders reach her (the unit logic still may not start anything on its own)")
	check(w.commands.order_move(sel, Vector3(64, 5, 70)) == 1, "the move order reaches her")
	_tick_world(w)
	check(g._crab == Golem.CRAB_UP and g.is_sitting(), "she lifts her bottom (crab_up), still in the sit stance")
	check_near(g._crab_time, g.crab_switch_time(), "crab_up takes crab_switch_time()", 0.0001)
	g.set_sit_stationary(true)
	_run_until(w, func() -> bool: return not g.is_crabbing(), 200)
	check(g.is_sitting() and not g.is_crabbing() and g.crab_goal() == Vector3.INF,
		"switched on again during the crawl: she sits down where she is")
	_free_world(w)


## Bewegungsbefehl im Sitzen: crab_up -> Krebsgang zum Ziel (ein Drittel des Lauftempos, Fuesse voran)
## -> crab_down -> sitzt wieder; der Sitzschaden trifft, wer am neuen Platz darunter liegt.
func test_crab_walk_follows_a_move_order_and_sits_again() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _crab_golem(w)
	var start: Vector3 = g.position
	var goal: Vector3 = Vector3(64, 5, start.z + 30.0)
	g.order_move(goal)
	_run_until(w, func() -> bool: return g._crab == Golem.CRAB_STAND, 100)
	check(g._crab == Golem.CRAB_STAND, "in the crab stand")
	_run_until(w, func() -> bool: return g.state == Unit.State.MOVE, 20)
	for i in range(5):
		_tick_world(w)
	var a: Vector3 = g.position
	for i in range(10):
		_tick_world(w)
	var v: float = _flat(g.position, a) / (10.0 * TICK)
	check_near(v, g.current_speed() / 3.0, "she crawls at a third of her walking speed (%.2f m/s)" % v, 0.05)
	check(g.heading().dot(Vector3(0, 0, 1)) > 0.99 and g.position.z > a.z, "feet first, the way she faces")
	check(g._seat_center == g.position, "her middle moves with her (the seat layout follows)")
	# Someone at the goal, under the new seat.
	var victim: Unit = _foe(w, goal.x, goal.z, 100000)
	_run_until(w, func() -> bool: return not g.is_crabbing(), 2000)
	check(g.is_sitting() and not g.is_crabbing() and not g.is_switching_stance(), "she sits again")
	check(_flat(g.position, goal) < 1.0, "at the goal (%.2f m off)" % _flat(g.position, goal))
	check(g.sit_victims().has(victim) and victim.health < 100000,
		"the sit damage strikes who is under the new seat")
	check_near(g.target_radius(), g.selection_ring_radius() * Balance.GOLEM_TARGET_RADIUS_SHARE
		* Balance.GOLEM_SIT_TARGET_RADIUS_FACTOR, "seated again: the seated target radius", 0.001)
	_free_world(w)


## Im Krebsstand ist der Koerper Kollisions- und Trefferkreis: groesser als im Stand, auch fuer den
## UnitManager, das Katapult und den Abstand der Golems.
func test_crab_stand_body_is_the_collision_and_hit_circle() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _crab_golem(w)
	var seated_radius: float = g.target_radius()
	check(g.collision_radius() == g.trample_radius(), "seated: the body circle as before")
	g.order_move(g.position + Vector3(0, 0, 40))
	_run_until(w, func() -> bool: return g._crab == Golem.CRAB_STAND, 100)
	var body: float = g.crab_body_radius()
	check_near(body, Balance.GOLEM_CRAB_BODY_RADIUS * g.model_scale().z * g.size_factor(), "the crab body radius")
	check(body > g.trample_radius() and body > seated_radius, "bigger than her body circle and her seated target radius")
	check_near(g.collision_radius(), body, "collision circle = her whole body")
	check_near(g.target_radius(), body, "hit circle the same (user spec)")
	check_near(w.um.soa_reach[g._idx], body, "the manager knows", 0.0001)
	check_near(g.body_hit_radius(), body, "the catapult hits all of her")
	var other: Golem = _golem(w, 0, Vector3(20, 5, 20))
	check_near(g._golem_need(other), Golem.golem_pair_need(body, g.height_m(), other.trample_radius(), other.height_m()),
		"other golems keep clear of her whole body")
	check(not g.is_rooted(), "in the crab stand she can be pushed like a walker")
	_free_world(w)


## Trampeln im Krebsgang: nur unter den vier Gliedern (nicht unter dem Bauch), die Zielobergrenze
## gilt fuer alle vier zusammen; eigene Einheiten nie.
func test_crab_walk_tramples_under_the_four_limbs_with_one_cap() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _crab_golem(w)
	g.order_move(g.position + Vector3(0, 0, 40))
	_run_until(w, func() -> bool: return g._crab == Golem.CRAB_STAND, 100)
	check(g.crab_walking(), "crawling")
	var limbs: Array[Vector3] = g.crab_contacts()
	var r: float = g.crab_limb_radius()
	check(r > 1.0 and r < g.trample_radius(), "a limb treads a smaller circle than the body (%.2f m)" % r)
	var belly: Unit = _foe(w, g.position.x, g.position.z, 1000)
	var foot: Unit = _foe(w, limbs[0].x, limbs[0].z, 1000)
	var hand: Unit = _foe(w, limbs[3].x, limbs[3].z, 1000)
	var own: Unit = _spawn(w, BRAVE_SCENE, 0, Vector3(limbs[1].x, 5, limbs[1].z))
	g._tick_pos = g.position - Vector3(0, 0, 1)
	g._tick_trample(TICK)
	check(foot.health < 1000 and hand.health < 1000, "under a foot and under a hand: trampled")
	check(belly.health == 1000, "under her belly: not")
	check(own.health == own.max_health, "her own: never")
	# The cap counts for all four limbs together.
	g._trampled.clear()
	var crowd: Array[Unit] = []
	for i in range(g.max_targets() + 4):
		var p: Vector3 = limbs[i % 4]
		crowd.append(_foe(w, p.x + 0.1 * float(i / 4), p.z, 1000))
	g._tick_pos = g.position - Vector3(0, 0, 1)
	g._tick_trample(TICK)
	var hit: int = 0
	for u in crowd:
		if u.health < 1000:
			hit += 1
	check(hit == g.max_targets() - 2, "the cap holds for all four limbs (%d hit, cap %d, 2 places still taken)" % [hit, g.max_targets()])
	_free_world(w)


## Angriffsbefehl im Sitzen: sie krabbelt, bis ein Sitzangriff das Ziel erreicht, setzt sich und
## greift an. Ohne Befehl krabbelt sie zu Feinden in Aggro-Reichweite, die sie im Sitzen nicht
## erreicht; stationaer nicht.
func test_crab_walk_takes_her_within_reach_of_a_target() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _crab_golem(w)
	var foe: Unit = _foe(w, 64.0, g.position.z + 45.0, 100000)
	check(not g._crab_reaches(foe) and _flat(g.position, foe.position) < g.aggro_radius(),
		"a foe in her aggro radius, out of her reach from the seat")
	var sel: Array[Unit] = [g]
	w.commands.order_attack(sel, foe)
	check(g.crab_target() == foe and g._crab_focus == foe, "she means to crawl to it")
	_run_until(w, func() -> bool: return g.is_crabbing(), 20)
	_run_until(w, func() -> bool: return not g.is_crabbing(), 2000)
	check(g.is_sitting() and g._crab_reaches(foe), "she sat down within reach of it")
	# Of her own accord: a stationary one stays, a mobile one crawls.
	var w2: Dictionary = _make_world()
	var still: Golem = _sit_golem(w2, 0, Vector3(64, 5, 40))
	_sit_until_seated(w2, still)
	var far: Unit = _foe(w2, 64.0, still.position.z + 45.0, 100000)
	for i in range(30):
		_tick_world(w2)
	check(not still.is_crabbing() and still.crab_target() == null, "stationary: she stays seated")
	still.set_sit_stationary(false)
	_run_until(w2, func() -> bool: return still.is_crabbing(), 40)
	check(still.is_crabbing() and still.crab_target() == far, "not stationary: she crawls toward the foe")
	_free_world(w)
	_free_world(w2)


## Aus dem Krebsgang darf sie sich auf Gebaeude setzen; feindliche Gebaeude unter der Sitzflaeche
## nehmen je Sitzschaden-Tick die Haelfte davon in Lebenspunkten, eigene nichts.
func test_crab_walk_sits_down_on_buildings() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _crab_golem(w)
	var goal: Vector3 = Vector3(64, 5, g.position.z + 25.0)
	var hut: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(int(goal.x) + 1, int(goal.z) - 1), 0, true)
	var own: Building = w.bm.place(HUT_SCENE, w.t0, Vector2i(int(goal.x) - 4, int(goal.z) - 1), 0, true)
	check(hut != null and own != null, "an enemy and an own hut at the goal")
	check(not g.seat_free(goal, Vector3(0, 0, 1), g.seat_half_extent()), "the seat at the goal touches them")
	g.order_move(goal)
	_run_until(w, func() -> bool: return g._crab == Golem.CRAB_DOWN, 2000)
	var hp: int = hut.health   # (her feet may have trampled it on the way)
	var own_hp: int = own.health
	_run_until(w, func() -> bool: return not g.is_crabbing(), 200)
	check(g.is_sitting() and _flat(g.position, goal) < 1.5, "she sat down on them (%.2f m off)" % _flat(g.position, goal))
	check(g.sit_buildings().has(hut) and not g.sit_buildings().has(own), "the enemy hut is under her, her own does not count")
	var dmg: int = g.building_damage_for(Balance.GOLEM_SIT_DAMAGE_MULT * g.trample_damage())
	check(hut.health == hp - dmg, "the enemy hut takes half the sit damage (%d -> %d)" % [hp, hut.health])
	check(own.health == own_hp, "her own hut nothing")
	_free_world(w)


## Ruft man sie im Krebsgang auf (Aufstehen), setzt sie sich erst und steht dann auf.
func test_crab_stand_up_sits_down_first() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _crab_golem(w)
	g.order_move(g.position + Vector3(0, 0, 40))
	_run_until(w, func() -> bool: return g.crab_walking() and g.state == Unit.State.MOVE, 100)
	check(g.stand_up(), "called up while crawling")
	_tick_world(w)
	check(g._crab == Golem.CRAB_DOWN and g.state == Unit.State.IDLE, "she stops and sits down first")
	_run_until(w, func() -> bool: return g.stance == Golem.STANCE_STAND and not g.is_sit_locked(), 400)
	check(g.stance == Golem.STANCE_STAND and not g.is_sit_locked() and not g.is_crabbing(), "then she stands")
	_free_world(w)


## Zeppelin-Zerstoerer: nur im Krebsstand, Zielbereich hinter dem Kopf. Der einzige Weg, aus dem
## Sitzen ein Luftschiff zu treffen — stationaer bleibt sie sitzen und trifft es nie.
func test_crab_strike_behind_her_head_brings_airships_down() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _sit_golem(w, 0, Vector3(64, 5, 70))
	_sit_until_seated(w, g)
	var behind: Vector3 = g.crab_air_center()
	check(_flat(behind, g.position) > g.seat_back_m(), "the area lies behind her head (%.1f m behind her middle)"
		% _flat(behind, g.position))
	var ship: Airship = _crewed_airship(w, 1, Vector3(behind.x, 5, behind.z))
	check(ship.auto_attackable(), "a crewed enemy airship behind her")
	for i in range(40):
		_tick_world(w)
	check(ship._hull_hits == 0 and not g.is_crabbing(), "stationary: seated she cannot strike it")
	g.set_sit_stationary(false)
	_run_until(w, func() -> bool: return g.crab_air_pending(), 200)
	check(g.crab_air_pending() and g._crab == Golem.CRAB_STAND, "not stationary: up into the crab stand, she winds up")
	check_near(g._crab_air_time + TICK, g.current_windup(Golem.ATTACK_SWAT), "with the swat's wind-up", TICK + 0.0001)
	check(g.in_crab_air_zone(ship.position), "the ship is in the area behind her head")
	_run_until(w, func() -> bool: return ship.state == Unit.State.DEAD, 400)
	check(ship.state == Unit.State.DEAD, "two strikes bring it down (%d hull hits)" % ship._hull_hits)
	_run_until(w, func() -> bool: return not g.is_crabbing(), 400)
	check(g.is_sitting() and not g.is_crabbing(), "nothing left to strike: she sits down again")
	_free_world(w)


## Ein Luftschiff in Aggro-Reichweite vor ihr (Bugmeldung 2026-11-18: sie fand keinen Weg, es hinter
## den Kopf zu bekommen): sie krabbelt heran, bis es so weit weg ist wie die Zone hinter ihrem Kopf,
## dreht ihm den Ruecken zu und schlaegt. Sehr nah krabbelt sie von ihm weg.
func test_crab_strike_she_gets_an_airship_behind_her_head() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _crab_golem(w)
	g.sit_attacks_enabled = true
	var ship: Airship = _crewed_airship(w, 1, Vector3(64, 5, g.position.z + 35.0))
	check(_flat(g.position, ship.position) <= g.aggro_radius(), "the ship is in her aggro radius")
	var plan: Array = g._crab_ship_goal(ship)
	var back: float = Balance.GOLEM_CRAB_AIR_BACK * g.model_scale().z * g.size_factor()
	check(plan[0] != Vector3.INF and absf(_flat(plan[0], ship.position) - back) < 0.01 and plan[0].z < ship.position.z,
		"her goal lies short of the ship, as far from it as the area lies behind her")
	_run_until(w, func() -> bool: return g.crab_air_pending() or ship._hull_hits > 0, 1500)
	check(g.crab_air_pending() or ship._hull_hits > 0, "she gets it behind her head and strikes")
	check(g.in_crab_air_zone(ship.position), "the ship lies in the area behind her head")
	check(g.heading().dot(Vector3(0, 0, 1)) < 0.0, "she turned her back to it")
	check(g.position.z < ship.position.z, "without crawling under it")
	# Close by (about the area's distance): she only turns her back; very close she crawls away.
	g.position = Vector3(ship.position.x, g.position.y, ship.position.z - back)
	check(g._crab_ship_goal(ship)[0] == Vector3.INF and (g._crab_ship_goal(ship)[1] as Vector3).dot(Vector3(0, 0, -1)) > 0.99,
		"at the area's distance she only turns her back to it")
	g.position = Vector3(ship.position.x, g.position.y, ship.position.z - back * 0.3)
	var away: Array = g._crab_ship_goal(ship)
	check(away[0] != Vector3.INF and (away[1] as Vector3).dot(Vector3(0, 0, -1)) > 0.99, "very close she crawls away from it")
	_free_world(w)


## Vorrang (Bugmeldung 2026-11-18): steht ein Feind in Reichweite ihrer Sitzangriffe, steht sie fuer ein
## Luftschiff nicht auf; krabbelt sie von selbst einem Luftschiff nach und kommt ein Feind in Reichweite,
## setzt sie sich und kaempft.
func test_crab_foes_in_reach_go_before_an_airship() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _crab_golem(w)
	g.sit_attacks_enabled = true
	var ship: Airship = _crewed_airship(w, 1, Vector3(64, 5, g.position.z + 35.0))
	var feet: Vector3 = g.position + g.heading() * g.seat_back_m()
	var foe: Unit = _foe(w, feet.x, feet.z + 2.0, 100000)
	check(g._crab_reaches(foe), "a foe within reach of her sit attacks")
	for i in range(40):
		_tick_world(w)
	check(not g.is_crabbing() and foe.health < 100000, "she stays seated and strikes the foe (no crab walk for the ship)")
	foe.health = 1
	foe.take_damage(10, ship)
	_run_until(w, func() -> bool: return g._crab == Golem.CRAB_STAND and g.state == Unit.State.MOVE, 200)
	check(g.crab_target() == ship, "nothing in reach any more: she goes after the airship")
	var at: Vector3 = g.position + g.heading() * (g.seat_back_m() + 2.0)
	var second: Unit = _foe(w, at.x, at.z, 100000)
	_run_until(w, func() -> bool: return g._crab == Golem.CRAB_DOWN or not g.is_crabbing(), 20)
	check(g._crab == Golem.CRAB_DOWN or not g.is_crabbing(), "a foe comes within reach: she sits down to fight")
	check(g.crab_target() == null, "the airship is no longer her goal")
	check(second != null, "(foe placed)")
	_free_world(w)


## Steht sie im Krebsstand 4 s still und ist nichts in ihrer Aggro-Reichweite zum Angreifen, setzt sie
## sich hin (Nutzervorgabe 2026-11-18).
func test_crab_idle_four_seconds_without_foes_she_sits_down() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _crab_golem(w)
	var ship: Airship = _crewed_airship(w, 1, Vector3(64, 5, 120))
	g.order_move(g.position + Vector3(0, 0, 3))
	_run_until(w, func() -> bool: return g._crab == Golem.CRAB_STAND, 100)
	check(_flat(g.position, ship.position) > g.aggro_radius(), "the ship lies beyond her aggro radius")
	# She stands still with a goal she does not go after (a far airship, no re-aim for now).
	g._crab_goal = Vector3.INF
	g._crab_stop()
	g._crab_target = ship
	g._crab_aimed = ship.position
	g._crab_repath = 1000.0
	var ticks: int = _run_until(w, func() -> bool: return g._crab != Golem.CRAB_STAND, 100)
	check_near(float(ticks) * TICK, Balance.GOLEM_CRAB_IDLE_SIT_TIME, "after 4 s standing idle she sits down", TICK * 1.5)
	check(g._crab == Golem.CRAB_DOWN, "crab_down")
	_free_world(w)


## Tod im Sitzen und im Krebsstand: Clip sit_death statt death (der Sitz-Versatz des Modells bleibt).
## Die neuen Clips sind im Modell, crab_idle und crab_walk laufen in Schleife.
func test_dying_seated_plays_sit_death() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for f in ["res://scenes/units/golem.tscn", "res://scenes/units/demon_golem.tscn", "res://scenes/units/genesis_golem.tscn"]:
		var g: Golem = (load(f) as PackedScene).instantiate() as Golem
		tree.root.add_child(g)
		if g._model == null:
			g._create_model()   # (inside the test runner the root is not ready yet: no _ready)
		check(g._anim != null, "%s: the model has its clips" % f)
		for clip in [Golem.CLIP_SIT_DEATH, Golem.CLIP_CRAB_UP, Golem.CLIP_CRAB_IDLE, Golem.CLIP_CRAB_WALK, Golem.CLIP_CRAB_DOWN,
				Golem.CLIP_CRAB_HEADBUTT, Golem.CLIP_CRAB_TURN_L, Golem.CLIP_CRAB_TURN_R]:
			check(g._anim.has_animation(clip), "%s has %s" % [f.get_file(), clip])
		check(g._anim.get_animation(Golem.CLIP_CRAB_TURN_L).loop_mode == Animation.LOOP_LINEAR
			and g._anim.get_animation(Golem.CLIP_CRAB_TURN_R).loop_mode == Animation.LOOP_LINEAR, "crab_turn_l / _r loop")
		check(g._anim.get_animation(Golem.CLIP_CRAB_WALK).loop_mode == Animation.LOOP_LINEAR
			and g._anim.get_animation(Golem.CLIP_CRAB_IDLE).loop_mode == Animation.LOOP_LINEAR, "crab_idle / crab_walk loop")
		check(g.death_clip() == Golem.CLIP_DEATH, "standing she dies with death")
		g.stance = Golem.STANCE_SIT
		check(g.death_clip() == Golem.CLIP_SIT_DEATH, "seated (and in the crab stand) with sit_death")
		g.queue_free()


## Die Schrittweite von crab_walk je Modell (sonst rutschen Haende und Fuesse); Tempo ein Drittel.
func test_crab_walk_strides_per_model() -> void:
	var g: Golem = Golem.new()
	var d: DemonGolem = DemonGolem.new()
	var gen: GenesisGolem = GenesisGolem.new()
	check_near(g.crab_clip_speed(), 1.029 * g.model_scale().z, "golem 1,029 m per loop at 4 m")
	check_near(d.crab_clip_speed(), 0.997 * d.model_scale().z, "demon golem 0,997 m")
	check_near(gen.crab_clip_speed(), 1.012 * gen.model_scale().z, "genesis golem 1,012 m")
	check_near(Balance.GOLEM_CRAB_SPEED_SHARE, 1.0 / 3.0, "a third of the walking speed (user spec)")
	g.free()
	d.free()
	gen.free()


## Bugfix 2026-11-18 (Spieltest): sitzend, nicht stationaer, ein Feindgebaeude in Aggro-Reichweite ausser
## Reichweite der Sitzangriffe — die Einheitenlogik startete einen Gebaeudeangriff (Zustand ATTACK), richtete
## sie jeden Tick auf das Gebaeude aus, die Sitzlogik drehte dagegen: Dauerdrehung auf der Stelle. Jetzt kein
## Gebaeudeangriff im Sitzen; sie krabbelt hin.
func test_seated_no_endless_turn_toward_a_building() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _sit_golem(w, 0, Vector3(64, 5, 64))
	_sit_until_seated(w, g)
	g.set_sit_stationary(false)
	var a: float = deg_to_rad(110.0)
	var at: Vector3 = g.position + Vector3(sin(a), 0, cos(a)) * 40.0
	var hut: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(int(at.x), int(at.z)), 0, true)
	check(hut != null and hut.footprint_distance_to(Vector2(g.position.x, g.position.z)) < g.aggro_radius(),
		"an enemy hut in her aggro radius")
	var crawled: bool = false
	for i in range(600):
		_tick_world(w)
		if g.attack_building != null or g.state == Unit.State.ATTACK:
			check(false, "no building assault while she sits (tick %d)" % i)
			break
		if g.crab_target() == hut:
			crawled = true
	check(crawled, "she crawls toward the hut")
	_free_world(w)


## Sicherung: haengt eine Drehung im Sitzen fest (der Koerper kommt nicht voran), bricht sie nach
## GOLEM_SIT_TURN_STALL_TIME ab und dreht GOLEM_SIT_TURN_BLOCK_TIME nicht neu.
func test_seated_a_hanging_turn_is_given_up() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _sit_golem(w, 0, Vector3(64, 5, 64))
	_sit_until_seated(w, g)
	var foe: Unit = _foe(w, g.position.x - 20.0, g.position.z - 5.0, 100000)
	_run_until(w, func() -> bool: return g.sit_combat != null and g.sit_combat.turning, 40)
	check(g.sit_combat.turning, "she turns toward the foe beside her")
	var frozen: Vector3 = g.heading()
	var ticks: int = 0
	while g.sit_combat.turning and ticks < 60:
		g._heading = frozen   # something holds her body (as the old building assault did)
		_tick_world(w)
		ticks += 1
	check(not g.sit_combat.turning, "the hanging turn is given up (%d ticks)" % ticks)
	check_near(float(ticks) * TICK, Balance.GOLEM_SIT_TURN_STALL_TIME, "after the stall time", 0.35)
	check(g.sit_combat.turn_block > 0.0, "and no new turn for a while")
	check(foe != null, "(foe placed)")
	_free_world(w)


## Rueckwaerts krabbeln (Nutzervorgabe 2026-11-18): ein Ziel hinter ihr erreicht sie Kopf voran, ohne sich
## umzudrehen; ein Ziel vor ihr Fuesse voran.
func test_crab_walks_backward_to_save_a_turn() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _crab_golem(w, Vector3(64, 5, 90))
	var start: Vector3 = g.position
	g.order_move(start - Vector3(0, 0, 25))
	_run_until(w, func() -> bool: return g.crab_walking() and g.state == Unit.State.MOVE, 100)
	for i in range(20):
		_tick_world(w)
	check(g._crab_backward, "the goal behind her: she crawls backward")
	check(g.heading().dot(Vector3(0, 0, 1)) > 0.99, "without turning round")
	check(g.position.z < start.z - 1.0, "and moves toward the goal, head first")
	var a: Vector3 = g.position
	for i in range(10):
		_tick_world(w)
	check_near(_flat(g.position, a) / (10.0 * TICK), g.current_speed() / 3.0, "as fast as forward", 0.05)
	_run_until(w, func() -> bool: return not g.is_crabbing(), 2000)
	check(g.is_sitting() and _flat(g.position, start - Vector3(0, 0, 25)) < 1.0, "she sits at the goal")
	check(g.heading().dot(Vector3(0, 0, 1)) > 0.99, "still facing as before")
	g.order_move(g.position + Vector3(0, 0, 20))
	_run_until(w, func() -> bool: return g.crab_walking() and g.state == Unit.State.MOVE, 100)
	for i in range(5):
		_tick_world(w)
	check(not g._crab_backward, "a goal ahead: feet first")
	_free_world(w)


## Angriffswahl (Nutzervorgabe 2026-11-18): ein Gebaeudetreffer zaehlt halb so viel wie derselbe Treffer gegen
## eine Einheit — im Stand und im Sitz.
func test_building_hits_count_half_in_the_attack_choice() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(40, 5, 40))
	g.facing = Vector3(0, 0, 1)
	g.snap_heading()
	g.tick(TICK)
	check_near(Balance.GOLEM_BUILDING_VALUE_SHARE, 0.5, "half")
	for kind in [Golem.ATTACK_KICK, Golem.ATTACK_SLAM, Golem.ATTACK_DRUM]:
		var unit_worth: float = 0.0
		if kind == Golem.ATTACK_DRUM:
			for hit in range(Balance.GOLEM_DRUM_HITS.size()):
				unit_worth += float(g.drum_hit_damage(hit))
		else:
			unit_worth = float(g.attack_damage(kind))
		check_near(g.building_value(kind), unit_worth * 0.5, "%s: a building counts half a unit hit" % kind, 0.0001)
	var s: Golem = _sit_golem(w, 0, Vector3(64, 5, 100))
	_sit_until_seated(w, s)
	var c: GolemSitCombat = s.sit_combat if s.sit_combat != null else GolemSitCombat.new(s)
	var foe: Unit = _foe(w, 10, 10, 100000)
	var hut: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(10, 120), 0, true)
	var none: Array[Unit] = []
	var one: Array[Unit] = [foe]
	for kind in [GolemSitCombat.STOMP_L, GolemSitCombat.WIPE_R, GolemSitCombat.HOP]:
		var vu: float = c._value(kind, one)
		var vb: float = c._value(kind, none, [hut])
		check_near(vb, vu * 0.5, "seated %s: a building counts half a unit hit" % kind, 0.0001)
	_free_world(w)


## Spieltest 2026-11-18: ein Luftschiff in Aggro-Reichweite geht Gebaeuden in Reichweite der Sitzangriffe vor
## (sie zerlegte eine Huette, waehrend das Schiff sie beschoss); Einheiten in Reichweite gehen weiter vor.
func test_crab_an_airship_goes_before_a_building_in_reach() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _sit_golem(w, 0, Vector3(64, 5, 50))
	_sit_until_seated(w, g)
	g.set_sit_stationary(false)
	var feet: Vector3 = g.position + g.heading() * g.seat_back_m()
	var hut: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(int(feet.x) - 1, int(feet.z) + 2), 0, true)
	hut.max_health = 100000
	hut.health = 100000
	check(g._crab_reaches(hut), "a hut within reach of her sit attacks")
	var ship: Airship = _crewed_airship(w, 1, g.position + Vector3(-25, 0, -5))
	check(ship.auto_attackable() and _flat(ship.position, g.position) < g.aggro_radius(), "a crewed airship in her aggro radius")
	_run_until(w, func() -> bool: return g.crab_target() == ship, 60)
	check(g.crab_target() == ship, "she goes after the airship, not on battering the hut")
	_run_until(w, func() -> bool: return ship._hull_hits > 0, 900)
	check(ship._hull_hits > 0, "and strikes it")
	_free_world(w)


## Am Kartenrand: liegt der naechste Anflugpunkt (Schiff hinter dem Kopf) ausserhalb der Scheibe, nimmt sie einen
## anderen rund um das Schiff (Spieltest 2026-11-18: sie fand keinen Weg und sass herum).
func test_crab_airship_approach_avoids_the_rim() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _sit_golem(w, 0, Vector3(64, 5, 70))
	g.facing = Vector3(0, 0, -1)
	g.snap_heading()
	g.position = Vector3(64, 5, 112)
	g._sync_soa_pos()
	g.tick(TICK)
	check(_sit_until_seated(w, g), "she sits near the rim, facing the middle")
	g.set_sit_stationary(false)
	var ship: Airship = _crewed_airship(w, 1, Vector3(g.position.x, 5, g.position.z - 8.0))
	var back: float = Balance.GOLEM_CRAB_AIR_BACK * g.model_scale().z * g.size_factor()
	var plain: Vector3 = Vector3(ship.position.x, g.position.y, ship.position.z) \
		+ Vector3(g.position.x - ship.position.x, 0, g.position.z - ship.position.z).normalized() * back
	check(not g._crab_spot_on_disc(plain), "the plain spot behind the ship lies over the rim")
	var plan: Array = g._crab_ship_goal(ship)
	check(plan[0] != Vector3.INF and g._crab_spot_on_disc(plan[0]), "she picks another spot round the ship")
	check_near(_flat(plan[0], ship.position), back, "the area's distance from it", 0.01)
	_run_until(w, func() -> bool: return ship._hull_hits > 0, 1500)
	check(ship._hull_hits > 0, "and gets it behind her head")
	_free_world(w)


## Bugmeldung 2026-11-18 (SCRIPT ERROR "previously freed" in _alive_at / _crab_target_alive): das Ziel einer
## Drehung, ein Krabbelziel, der Fokus eines Befehls oder ein Luftschiff mit angesetztem Schlag wird mitten im
## Geschehen freigegeben (Leiche versunken, Wrack weg). Nichts davon darf den Tick abbrechen.
func _vanish(w: Dictionary, u: Unit) -> void:
	w.um.unregister(u)
	u.free()


func test_sitting_golem_copes_with_freed_targets() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _sit_golem(w, 0, Vector3(64, 5, 64))
	_sit_until_seated(w, g)
	# 1. The one she turns to.
	var side: Unit = _foe(w, g.position.x - 20.0, g.position.z - 5.0, 100000)
	_run_until(w, func() -> bool: return g.sit_combat != null and g.sit_combat.turning, 40)
	check(g.sit_combat.turning and g.sit_combat._turn_goal == side, "she turns toward the foe beside her")
	_vanish(w, side)
	_tick_world(w)
	_tick_world(w)
	check(not g.sit_combat.turning, "it is freed: the turn ends (no script error)")
	# 2. Her focus (an ordered target).
	g.set_sit_stationary(false)
	var ordered: Unit = _foe(w, g.position.x, g.position.z + 45.0, 100000)
	g._crab_focus = ordered
	_vanish(w, ordered)
	var none: Array[Unit] = []
	g.sit_nothing_in_reach(none)
	check(g.crab_target() == null and g._crab_focus == null, "a freed focus is dropped")
	# 3. The target she crawls to.
	var far: Unit = _foe(w, g.position.x, g.position.z + 45.0, 100000)
	g.crab_to(Vector3.INF, far)
	_run_until(w, func() -> bool: return g._crab == Golem.CRAB_STAND, 100)
	check(g._crab == Golem.CRAB_STAND, "crawling toward a foe")
	_vanish(w, far)
	_run_until(w, func() -> bool: return not g.is_crabbing(), 200)
	check(g.is_sitting() and not g.is_crabbing() and g.crab_target() == null, "it is freed: she sits down again")
	# 4. An airship freed while the strike behind her head is wound up.
	var ship: Airship = _crewed_airship(w, 1, g.crab_air_center())
	g.crab_to(Vector3.INF, ship)
	_run_until(w, func() -> bool: return g.crab_air_pending(), 200)
	check(g.crab_air_pending(), "the strike at the airship is wound up")
	for u in w.um.units.duplicate():
		if is_instance_valid(u) and u is Unit and (u as Unit).siege_engine == ship:
			_vanish(w, u)
	_vanish(w, ship)
	_tick_world(w)
	check(not g.crab_air_pending(), "the ship is freed: the strike is dropped (no script error)")
	_run_until(w, func() -> bool: return not g.is_crabbing(), 300)
	check(g.is_sitting() and not g.is_crabbing(), "and she sits down again")
	_free_world(w)


## Spieltest 2026-11-18: im Krebsgang dreht sie sich so schnell wie im Sitzen.
func test_crab_turns_as_slowly_as_seated() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _crab_golem(w)
	var seated: float = g.turn_rate()
	g.order_move(g.position + Vector3(0, 0, 30))
	_run_until(w, func() -> bool: return g._crab == Golem.CRAB_STAND, 100)
	check_near(g.turn_rate(), seated, "crab stand: the seated turn rate")
	check_near(g.turn_rate(), g.sit_turn_rate(), "(sit_turn_rate)")
	_free_world(w)


## Spieltest 2026-11-18 ("Sitzschaden beim Absetzen viel zu gross"): der Sitzschaden trifft nur die Sitzflaeche;
## die Sitzangriffe kamen aber bei jedem Absetzen sofort, weil das Aufstehen ihre Abklingzeiten zuruecksetzte.
## Jetzt laufen sie beim Krabbeln weiter.
func test_crab_keeps_the_sit_attack_cooldowns() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _crab_golem(w)
	g.sit_attacks_enabled = true
	_tick_world(w)
	var c: GolemSitCombat = g.sit_combat
	c.cooldown = [30.0, 30.0]
	g.order_move(g.position + Vector3(0, 0, 8))
	_run_until(w, func() -> bool: return g.is_crabbing(), 20)
	var t: int = _run_until(w, func() -> bool: return not g.is_crabbing(), 600)
	check(g.is_sitting() and not g.is_crabbing(), "she crawled and sat down again")
	check(c.cooldown[GolemSitCombat.CH_LEGS] > 0.0 and c.cooldown[GolemSitCombat.CH_ARMS] > 0.0,
		"the cooldowns were not reset (legs %.1f s, arms %.1f s left)" % [c.cooldown[0], c.cooldown[1]])
	check(c.cooldown[GolemSitCombat.CH_LEGS] < 30.0 - float(t) * TICK + 0.5, "and ran on while she crawled")
	# The sit damage itself: only the seat.
	var w2: Dictionary = _make_world()
	var h: Golem = _crab_golem(w2)
	var goal: Vector3 = h.position + Vector3(0, 0, 30)
	var near: Unit = _foe(w2, goal.x + 1.0, goal.z, 10000)
	var off: Unit = _foe(w2, goal.x + h.seat_half_extent().x + 1.5, goal.z, 10000)
	h.order_move(goal)
	_run_until(w2, func() -> bool: return h.is_crabbing(), 20)
	_run_until(w2, func() -> bool: return not h.is_crabbing(), 2000)
	check(h.sit_victims().has(near) and near.health < 10000, "the seat strikes who is on it")
	check(not h.sit_victims().has(off), "not who stands beside it")
	_free_world(w)
	_free_world(w2)


## Spieltest 2026-11-18 (sie stand auf und setzte sich gleich wieder): fuer eine Einheit knapp ausser Reichweite steht
## sie erst nach GOLEM_CRAB_PATIENCE auf, und sie setzt sich erst, wenn die Einheit ein Stueck tief in ihrer Zone liegt.
func test_crab_waits_for_a_foe_nearly_in_reach_and_sits_with_it_well_inside() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _crab_golem(w, Vector3(64, 5, 30))
	g.sit_attacks_enabled = true
	var feet: Vector3 = g.position + g.heading() * g.seat_back_m()
	var c: GolemSitCombat = GolemSitCombat.new(g)
	var ahead: float = 0.0
	while c.in_area(GolemSitCombat.KICK_L, feet + Vector3(0, 0, ahead + 0.5)) \
			or c.in_area(GolemSitCombat.KICK_R, feet + Vector3(0, 0, ahead + 0.5)) \
			or c.in_area(GolemSitCombat.STOMP_L, feet + Vector3(0, 0, ahead + 0.5)) or ahead < 2.0:
		ahead += 0.5
	var foe: Unit = _foe(w, feet.x + 0.6, feet.z + ahead + 1.5, 100000)
	check(not g._crab_reaches(foe) and _flat(foe.position, g.position) < g.sit_combat._scan_radius() if g.sit_combat
		else true, "a foe just beyond her reach")
	var up: int = _run_until(w, func() -> bool: return g.is_crabbing(), 100)
	check(float(up) * TICK >= Balance.GOLEM_CRAB_PATIENCE - 0.3, "she waits %.1f s before she gets up" % (float(up) * TICK))
	_run_until(w, func() -> bool: return g._crab == Golem.CRAB_DOWN or not g.is_crabbing(), 600)
	check(g._crab_reaches_deep(foe), "she sits down with it well within reach, not at the edge")
	_free_world(w)


## Debugansicht der Sitzzonen (Nutzerwunsch 2026-11-18, Taste G): jeder Umriss umschliesst genau die Zone, in der
## sie trifft (ein Punkt knapp innen liegt in der Zone, knapp aussen meist nicht), und die Reichweitenanzeige
## zeichnet sie fuer eine eigene sitzende Golemin.
func test_sit_zone_debug_outlines_match_the_zones() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _sit_golem(w, 0, Vector3(64, 5, 64))
	_sit_until_seated(w, g)
	var c: GolemSitCombat = g.sit_combat if g.sit_combat != null else GolemSitCombat.new(g)
	var zones: Array = c.zone_outlines()
	check(zones.size() == 12, "twelve outlines: two stomps, two lanes, two wipes, two side hand slams, po clap, double stomp, two hand stomps")
	for z in zones:
		var kind: StringName = z[0]
		var pts: PackedVector2Array = z[1]
		var centre: Vector2 = Vector2.ZERO
		for q in pts:
			centre += q
		centre /= float(pts.size())
		var inside: int = 0
		var outside: int = 0
		for q in pts:
			var to: Vector2 = (centre - q).normalized()
			var qi: Vector2 = q + to * 0.25
			var qo: Vector2 = q - to * 0.25
			if c.in_area(kind, Vector3(qi.x, 5, qi.y)):
				inside += 1
			if not c.in_area(kind, Vector3(qo.x, 5, qo.y)):
				outside += 1
		check(inside >= int(pts.size() * 0.9), "%s: points just inside are in the zone (%d of %d)" % [kind, inside, pts.size()])
		check(outside >= int(pts.size() * 0.75), "%s: points just outside mostly not (%d of %d)" % [kind, outside, pts.size()])
	var groups: Dictionary = {}
	for z in g.debug_zone_outlines():
		groups[z[0]] = true
	check(groups.has("legs") and groups.has("arms") and groups.has("big") and groups.has("seat"),
		"seated: legs, arms, big attacks and the seat (%s)" % str(groups.keys()))
	var ranges: RangeRenderer = RangeRenderer.new()
	ranges.setup(w.um, 0, w.td)
	ranges._ready()
	ranges.enabled = true
	ranges._process(TICK)
	check(ranges._im.get_surface_count() == 1, "key G draws them (one batched surface)")
	g.set_sit_stationary(false)
	g.order_move(g.position + Vector3(0, 0, 30))
	_run_until(w, func() -> bool: return g._crab == Golem.CRAB_STAND, 100)
	groups.clear()
	for z in g.debug_zone_outlines():
		groups[z[0]] = true
	check(groups.has("body") and groups.has("limb") and groups.has("air") and not groups.has("legs"),
		"crab stand: body, limbs and the airship area (%s)" % str(groups.keys()))
	ranges.free()
	_free_world(w)


## Drehen im Krebsstand (Nutzervorgabe 2026-11-18): crab_turn_l / crab_turn_r nach der echten Drehrate
## (links = gegen den Uhrzeigersinn von oben, wie sit_turn_l), abgespielt mit Drehrate / 33,3 Grad je
## Durchlauf, damit nichts rutscht; dreht sie beim Krabbeln, gewinnt, was Haende und Fuesse schneller bewegt.
func test_crab_turn_clips_follow_the_turn() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for f in ["res://scenes/units/golem.tscn", "res://scenes/units/demon_golem.tscn", "res://scenes/units/genesis_golem.tscn"]:
		var g: Golem = (load(f) as PackedScene).instantiate() as Golem
		tree.root.add_child(g)
		if g._model == null:
			g._create_model()
		g.stance = Golem.STANCE_SIT
		g._crab = Golem.CRAB_STAND
		var fname: String = f.get_file()
		g._crab_visual(0.0, 0.7)
		check(g._clip == Golem.CLIP_CRAB_TURN_L, "%s: turning left on the spot: crab_turn_l (%s)" % [fname, g._clip])
		check_near(g._anim.speed_scale, 0.7 / Golem.CRAB_TURN_CLIP_ANGLE, "%s: played at turn rate / 33,3 degrees" % fname)
		g._crab_visual(0.0, -0.7)
		check(g._clip == Golem.CLIP_CRAB_TURN_R, "%s: turning right: crab_turn_r" % fname)
		g._crab_visual(0.0, 0.0)
		check(g._clip == Golem.CLIP_CRAB_IDLE, "%s: no turn, no crawl: crab_idle" % fname)
		var reach: float = g.crab_limb_reach()
		check(reach > 0.5 and reach < 3.0, "%s: hands and feet %.2f m from the middle at summoning size" % [fname, reach])
		g._crab_visual(reach * 0.7 * 0.5, 0.7)
		check(g._clip == Golem.CLIP_CRAB_TURN_L, "%s: crawling slowly while turning fast: the turn clip" % fname)
		g._crab_visual(reach * 0.7 * 2.0, 0.7)
		check(g._clip == Golem.CLIP_CRAB_WALK, "%s: crawling fast while turning slowly: the walk clip" % fname)
		g._crab_visual(1.0, 0.01)
		check(g._clip == Golem.CLIP_CRAB_WALK, "%s: a tiny turn does not count" % fname)
		# The visual tick measures the turn from the body's angle (rotation.y = atan2(x, z) of the heading):
		# the angle growing = left, as sit_turn_l; across the +-PI seam too.
		check_near(g._measure_turn(0.0, 0.1), 0.0, "%s: the first tick measures nothing" % fname)
		check_near(g._measure_turn(0.06, 0.1), 0.6, "%s: angle growing: +0,6 rad/s (left)" % fname, 0.0001)
		check_near(g._measure_turn(0.0, 0.1), -0.6, "%s: angle falling: right" % fname, 0.0001)
		g._measure_turn(PI - 0.03, 0.1)
		check_near(g._measure_turn(-PI + 0.03, 0.1), 0.6, "%s: over the seam still left" % fname, 0.0001)
		check(GolemSitAnim.CLIP_TURN_L == &"sit_turn_l" and g._sit_base_clip() == Golem.CLIP_SIT_IDLE,
			"%s: same sign convention as the seated turn (_sit_base_clip: facing angle above heading = left)" % fname)
		g.queue_free()


## Nahkampfgrenze an Golems nach Groesse (Nutzervorgabe 2026-11-18): Ringumfang abgerundet / 0,5 m, davon 30 %,
## abgerundet — frisch beschworen 4, sitzend bei 31,3 m 24; die Plaetze liegen gleichmaessig rund um den Ring;
## gewoehnliche Einheiten behalten ihre 3.
func test_melee_cap_on_a_golem_grows_with_her() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(64, 5, 64))
	g.health = 100000
	g.max_health = 100000
	var ring: float = TAU * (Unit.MELEE_SLOT_RADIUS + g.target_radius())
	check(g.max_melee_attackers() == 4, "fresh golem: ring %.1f m -> 8 / 0,5 = 16, 30 %% = 4 (%d)" % [ring,
		g.max_melee_attackers()])
	check(g.melee_slot_count() == g.max_melee_attackers(), "as many seats as attackers")
	var big: Golem = _sit_golem(w, 0, Vector3(30, 5, 100))
	big._seat_center = big.position
	check(big.max_melee_attackers() == 24, "seated at 31,3 m: ring 40,1 m -> 80, 30 %% = 24 (%d)" % big.max_melee_attackers())
	big._seat_center = Vector3.INF
	check(big.max_melee_attackers() == 13, "standing at 31,3 m: ring 22,9 m -> 44, 30 %% = 13 (%d)" % big.max_melee_attackers())
	var brave: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(20, 5, 20))
	check(brave.max_melee_attackers() == Unit.MAX_MELEE_ATTACKERS, "an ordinary unit keeps its 3")
	var foes: Array = []
	for i in range(10):
		var a: float = TAU * float(i) / 10.0
		var u: Unit = _spawn(w, WARRIOR_SCENE, 1, g.position + Vector3(sin(a), 0, cos(a)) * 6.0)
		u.health = 100000
		u.max_health = 100000
		u.order_attack(g)
		foes.append(u)
	var peak: int = 0
	for i in range(150):
		_tick_world(w)
		peak = maxi(peak, g.active_melee_attacker_count())
	check(peak == 4, "4 of 10 warriors fight her at once, the rest waits (peak %d)" % peak)
	var r: float = Unit.MELEE_SLOT_RADIUS + g.target_radius()
	var p0: Vector3 = g.melee_slot_position(0)
	var p1: Vector3 = g.melee_slot_position(1)
	check_near(Vector2(p0.x - g.position.x, p0.z - g.position.z).length(), r, "the seats lie on her melee ring")
	check_near(Vector2(p0.x - p1.x, p0.z - p1.z).length(), 2.0 * r * sin(PI / 4.0),
		"four seats evenly round it", 0.01)
	_free_world(w)


## Der Po-Klatscher erreicht im Sitzen jeden, der sie im Nahkampf schlagen kann (Ring Zielradius + Nahkampf-
## reichweite um die Sitzmitte; Nutzervorgabe 2026-11-18) — bei allen drei Golems und jeder Sitzgroesse.
func test_po_clap_reaches_every_melee_attacker() -> void:
	var w: Dictionary = _make_world()
	var golems: Array = [_golem(w, 0, Vector3(64, 5, 64)),
		_spawn(w, load("res://scenes/units/demon_golem.tscn"), 0, Vector3(30, 5, 64)),
		_spawn(w, load("res://scenes/units/genesis_golem.tscn"), 0, Vector3(98, 5, 64))]
	var ge: GenesisGolem = golems[2]
	for i in range(700):
		var any: bool = false
		for gg in golems:
			var g: Golem = gg
			if g is GenesisGolem:
				ge.stage = 8
				ge.wood_growth_m = float(i) * 0.1
			elif g.height_m() < 119.0:
				g._credit_kill()
			if g.height_m() < 30.0:
				continue
			g._seat_center = g.position
			var c: GolemSitCombat = GolemSitCombat.new(g)
			var ring: float = g.target_radius() + Unit.MELEE_RANGE
			if c.hop_radius() < ring:
				check(false, "%s at %.1f m: po clap %.2f m short of the melee ring %.2f m" % [g.unit_kind(), g.height_m(),
					c.hop_radius(), ring])
				any = true
			g._seat_center = Vector3.INF
		if any:
			break
	check(true, "po clap covers the melee ring")
	_free_world(w)


## Handschlag seitlich (Nutzervorgabe 2026-11-18, Clips sit_hand_slam_l/_r): Armangriff in den blinden Fleck aussen
## neben Oberschenkel und Knie — Kreis mit 2/3 des Fuss-Stampfer-Radius um die gemessene Aufschlagstelle, dort trifft
## sonst kein Einzelangriff; mit einem Beinangriff gleichzeitig, auf der Arm-Ebene mit Oberkoerper.
func test_side_hand_slam_strikes_the_blind_spot() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _sit_golem(w, 0, Vector3(64, 5, 64))
	_sit_until_seated(w, g)
	var c: GolemSitCombat = g.sit_combat if g.sit_combat != null else GolemSitCombat.new(g)
	var sx: float = g.model_scale().x * g.size_factor()
	var sz: float = g.model_scale().z * g.size_factor()
	check_near(c.hand_slam_radius(), c.stomp_radius() * 2.0 / 3.0 * 1.05, "radius 2/3 of the foot stomp's, 5 % more")
	check(g.height_m() > 31.0 and g.height_m() < 31.5, "(first sit size, %.2f m)" % g.height_m())
	check(c.damage(GolemSitCombat.HAND_SLAM_L) == 75, "75 damage at 31,3 m (%d)" % c.damage(GolemSitCombat.HAND_SLAM_L))
	check_near(c.cooldown_of(GolemSitCombat.HAND_SLAM_R), 1.7, "cooldown 1,7 s at 31,3 m", 0.001)
	check_near(c.cooldown_of(GolemSitCombat.WIPE_L), 1.3, "the wipe's 1,3 s at 31,3 m", 0.001)
	check_near(c.cooldown_of(GolemSitCombat.STOMP_L), 1.39015, "the foot stomp keeps its 1,39 s", 0.001)
	for side in [1.0, -1.0]:
		var kind: StringName = GolemSitCombat.HAND_SLAM_L if side > 0.0 else GolemSitCombat.HAND_SLAM_R
		var p: Vector3 = c.hand_slam_point(side)
		var rel: Vector3 = p - c.feet_point()
		check_near(rel.dot(c.left()) * side / sx, 0.92, "%s: 0,92 m to her side (4-m model)" % kind, 0.001)
		check_near(rel.dot(c.forward()) / sz, -0.70, "%s: 0,70 m behind the feet" % kind, 0.001)
		check(c.in_area(kind, p) and not c.in_area(kind, p + c.left() * side * (c.hand_slam_radius() + 0.1)),
			"%s: a circle round the impact" % kind)
		var others: Array = []
		for k in [GolemSitCombat.STOMP_L, GolemSitCombat.STOMP_R, GolemSitCombat.KICK_L, GolemSitCombat.KICK_R,
				GolemSitCombat.WIPE_L, GolemSitCombat.WIPE_R]:
			if c.in_area(k, p):
				others.append(k)
		check(others.is_empty(), "%s: its middle lies in no other single attack's zone (%s)" % [kind, str(others)])
		check(GolemSitCombat.channels_of(kind) == [GolemSitCombat.CH_ARMS], "%s: an arm attack" % kind)
		check(GolemSitCombat.layer_of(kind) == GolemSitAnim.LAYER_ARM_TORSO, "%s: on the arm+torso layer" % kind)
		check(GolemSitCombat.side_of_kind(kind) == side and GolemSitCombat.debug_group(kind) == "arms", "%s: its side" % kind)
	# A foe in the left blind spot: she strikes it with the left hand.
	var foe: Unit = _spawn(w, BRAVE_SCENE, 1, c.hand_slam_point(1.0))
	foe.health = 10000
	foe.max_health = 10000
	var struck: bool = false
	for i in range(40):
		_tick_world(w)
		if c.pending[GolemSitCombat.CH_ARMS] == GolemSitCombat.HAND_SLAM_L:
			struck = true
			break
	check(struck, "a foe in the blind spot draws the side hand slam (arms: %s)" % c.pending[GolemSitCombat.CH_ARMS])
	_free_world(w)
