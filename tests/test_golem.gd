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
	var near: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.0, 5, 51.0))        # along 1,0
	var far: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.0, 5, 54.2))         # along 4,2
	var edge: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.8, 5, 53.0))        # side 0,8
	var behind: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.0, 5, 47.5))      # along -2,5: the backswing
	var out_side: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(51.0, 5, 53.0))    # side 1,0 > 0,9
	var out_far: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.0, 5, 54.5))     # along 4,5 > 4,25
	var out_back: Unit = _spawn(w, BRAVE_SCENE, 1, Vector3(50.0, 5, 46.8))    # along -3,2 < -2,98
	var friend: Unit = _spawn(w, BRAVE_SCENE, 0, Vector3(50.0, 5, 52.0))
	for u in [near, far, edge, behind, out_side, out_far, out_back, friend]:
		u.max_health = 1000
		u.health = 1000
	g._kick()
	var hit: int = 1000 - Balance.GOLEM_KICK_DAMAGE
	check(near.health == hit and far.health == hit, "the whole lane ahead takes GOLEM_KICK_DAMAGE")
	check(edge.health == hit, "0,8 m aside is inside the 1,8-m-wide lane")
	check(behind.health == hit, "2,5 m BEHIND her the backswing hits too")
	check(out_side.health == 1000, "1,0 m aside is outside the lane")
	check(out_far.health == 1000, "4,5 m ahead is beyond the lane (4,25 m)")
	check(out_back.health == 1000, "3,2 m behind is beyond the backswing (2,98 m)")
	check(friend.health == 1000, "own units in the lane are never hit")
	var all_thrown: bool = true
	var all_forward: bool = true
	for u in [near, far, edge]:
		all_thrown = all_thrown and u.state == Unit.State.THROWN
		all_forward = all_forward and u._throw_velocity.z > 0.0 \
			and absf(u._throw_velocity.x) < 0.01
	check(all_thrown, "EVERY survivor of the kick is thrown (lots of knockback)")
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


## Angriffswahl: ab GOLEM_SLAM_MIN_TARGETS Feinden in der Flaeche des Handschlags
## schlaegt sie, darunter tritt sie.
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


func test_golem_slams_a_crowd_and_kicks_single_targets() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
	check(g._choose_attack() == Golem.ATTACK_KICK, "nobody around: the default is the kick")
	var foes: Array[Unit] = []
	for i in range(Balance.GOLEM_SLAM_MIN_TARGETS - 1):
		foes.append(_spawn(w, BRAVE_SCENE, 1, Vector3(49.0 + float(i), 5, 51.5)))
	check(g._choose_attack() == Golem.ATTACK_KICK, "two enemies: still the kick")
	foes.append(_spawn(w, BRAVE_SCENE, 1, Vector3(50.0, 5, 48.8)))   # behind her, in the circle
	check(g._choose_attack() == Golem.ATTACK_SLAM, "three enemies around her: the hand slam")
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
	g.order_attack(far)
	check(g.attack_target == far, "ordered onto the far one")
	_tick_world(w)
	check(g.attack_target == near, "...but turns on the enemy already in reach")
	# Nobody in reach any more: now it chases.
	near.take_damage(1000000)
	_tick_world(w)
	for i in range(20):
		_tick_world(w)
	check(g.attack_target == far, "with nobody near it goes for the far one")
	# Measured on the golem, not on the distance: once she is in reach she KICKS
	# the target, and a kicked survivor flies further off than it stood before.
	check(g.position.x > 52.0, "and walks after it (x %.1f)" % g.position.x)
	_free_world(w)


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func test_smash_throws_or_rolls_a_quarter_each_away_from_the_golem() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.facing = Vector3(0, 0, 1)
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
	check(lifted > trials * 0.2 and lifted < trials * 0.4,
		"about 30 percent are whirled up (%d of %d)" % [lifted, trials])
	check(rolled > trials * 0.2 and rolled < trials * 0.4,
		"about 30 percent are sent rolling (%d of %d)" % [rolled, trials])
	check(untouched > trials * 0.25, "the rest just take the hit (%d of %d)" % [untouched, trials])
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


## Alle 6 Kills eine Stufe, beginnend bei 0, bis Stufe 6 (36 Kills); Stufe 7
## braucht 50 weitere (86). Jeder Aufstieg bringt 20 s Lebenszeit (zusaetzlich
## zu den 6 s je Kill).
func test_levels_follow_the_kills_up_to_seven() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	check(g.level == 0 and is_equal_approx(g.size_factor(), 1.0), "a fresh golem is level 0")
	for i in range(Balance.GOLEM_KILLS_PER_LEVEL - 1):
		g._credit_kill()
	check(g.level == 0, "five kills are not a level yet")
	var before: float = g.life_left
	g._credit_kill()
	check(g.level == 1, "the sixth kill makes level 1")
	check_near(g.life_left, before + Balance.GOLEM_LIFE_PER_KILL + Balance.GOLEM_LEVEL_LIFETIME,
		"the level-up adds 20 s on top of the kill's 6 s")
	check(Golem.level_for_kills(11) == 1 and Golem.level_for_kills(12) == 2
		and Golem.level_for_kills(30) == 5 and Golem.level_for_kills(36) == 6,
		"levels follow the kills in steps of six up to level 6")
	check(Golem.level_for_kills(85) == 6 and Golem.level_for_kills(86) == 7
		and Golem.level_for_kills(1000) == 7 and Golem.kills_for_level(7) == 86,
		"level 7 takes 50 more kills (86) and is the last one")
	while g.kills < 85:
		g._credit_kill()
	check(g.level == 6, "85 kills: still level 6")
	g._credit_kill()
	check(g.level == 7 and Balance.GOLEM_MAX_LEVEL == 7, "the 86th kill makes level 7")
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
	check_near(g.reach(), Balance.GOLEM_REACH * r2, "the reach follows the reach factor")
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
	check_near(g.reach(), Balance.GOLEM_REACH * r6, "the reach is 1,1 ^ 6 = 1,77 times the base")
	check(r6 < s6 * 0.65, "the reach grows clearly slower than the body")
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
	check_near(g.reach(), reach7 * 1.0075, "reach and strike areas 0,75 percent", 0.0005)
	check_near(g.trample_radius(), trample7 * 1.0075, "the trample radius too", 0.0005)
	check(g.speed > speed7 and g.speed < speed7 * 1.01, "the speed rises only slightly (%.3f)" % g.speed)
	for i in range(Balance.GOLEM_GROWTH_KILLS):
		g._credit_kill()
	check_near(g.size_factor(), size7 * 1.03 * 1.03, "the growth compounds", 0.0005)
	check(g.attack_damage(Golem.ATTACK_KICK) == dmg7 and g.max_health == Balance.GOLEM_MAX_HP_CAP,
		"damage and health limit stay where they were")
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


## Je groesser, desto langsamer holt er aus — aber nie so langsam, dass die
## Animation laenger dauert als die Abklingzeit. Der Angriffstakt bleibt.
func test_attack_animations_slow_down_with_size_but_fit_the_cooldown() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	for kind in [Golem.ATTACK_SLAM, Golem.ATTACK_KICK, Golem.ATTACK_SWAT]:
		check_near(g.attack_speed(kind), 1.0, "level 0 plays %s at full speed" % kind)
	check_near(g.current_windup(Golem.ATTACK_KICK), Balance.GOLEM_KICK_WINDUP,
		"and lands the kick after the plain wind-up")
	_level_to(g, 2)
	check_near(g.attack_speed(Golem.ATTACK_KICK), 1.0 / sqrt(g.size_factor()),
		"level 2 swings slower, with the root of the size (%.2f)" % g.attack_speed(Golem.ATTACK_KICK))
	_level_to(g, 7)
	var fits: bool = true
	for kind in [Golem.ATTACK_SLAM, Golem.ATTACK_KICK, Golem.ATTACK_SWAT]:
		var played: float = float(Golem.CLIP_LENGTH[kind]) / g.attack_speed(kind)
		fits = fits and played <= Balance.GOLEM_STRIKE_COOLDOWN + 0.0001 \
			and g.current_windup(kind) < Balance.GOLEM_STRIKE_COOLDOWN
	check(fits, "at level 7 every attack animation still fits into the cooldown")
	check_near(float(Golem.CLIP_LENGTH[Golem.ATTACK_KICK]) / g.attack_speed(Golem.ATTACK_KICK),
		Balance.GOLEM_STRIKE_COOLDOWN, "the giant's kick fills the whole cooldown — no idling in between")
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


func test_burning_is_a_trickle_without_panic() -> void:
	var w: Dictionary = _make_world()
	var g: Golem = _golem(w, 0, Vector3(50, 5, 50))
	g.ignite(g.position)
	check(g.is_burning(), "fire does catch")
	check(g.state != Unit.State.PANIC, "but the golem does not panic")
	var after_contact: int = g.health
	check(after_contact == 800 - Balance.LAVA_CONTACT_DAMAGE, "the lava contact hit applies")
	for i in range(10):   # 1 s of burning
		g.tick(TICK)
	check(g.health == after_contact - int(Balance.GOLEM_BURN_DPS),
		"one second of fire costs 5 HP, not 15")
	check(g.state != Unit.State.PANIC, "still no panic while alight")
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
		and text.contains("noch %d Kills bis Stufe 1" % Balance.GOLEM_KILLS_PER_LEVEL),
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
