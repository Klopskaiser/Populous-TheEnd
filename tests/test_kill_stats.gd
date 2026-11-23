extends TestBase

## Kill statistics per tribe (2026-11-23, TribeStats): who killed whom — golems
## (all three kinds) against everything else — the own losses, the peak of the
## followers; deaths without a fresh blow count for the last harmer; own kills,
## vehicles and a crumbling golem count for nobody.

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const GOLEM_SCENE: PackedScene = preload("res://scenes/units/golem.tscn")
const DEMON_SCENE: PackedScene = preload("res://scenes/units/demon_golem.tscn")
const GENESIS_SCENE: PackedScene = preload("res://scenes/units/genesis_golem.tscn")
const SIEGE_SCENE: PackedScene = preload("res://scenes/units/siege_engine.tscn")


## A spell effect stand-in: anything with a tribe_id (tornado, swarm, volcano).
class FakeSpellEffect extends Node3D:
	var tribe_id: int = 0


func _make_world() -> Dictionary:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = 5.0
	var nav: NavGrid = NavGrid.new(td)
	var tribes: Array[Tribe] = [Tribe.new(0), Tribe.new(1), Tribe.new(2)]
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, tribes)
	return {"td": td, "nav": nav, "tribes": tribes, "um": um}


func _free_world(w: Dictionary) -> void:
	w.um.free()


func _spawn(w: Dictionary, scene: PackedScene, tribe_id: int, x: float = 60.0) -> Unit:
	return w.um.spawn_unit(scene, tribe_id, Vector3(x, 5.0, 60.0))


func test_a_unit_kill_counts_for_the_killers_tribe_and_as_a_loss() -> void:
	var w: Dictionary = _make_world()
	var t: Array[Tribe] = w.tribes
	var warrior: Unit = _spawn(w, WARRIOR_SCENE, 0)
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, 62.0)
	victim.take_damage(victim.max_health + 10, warrior)
	check(victim.state == Unit.State.DEAD, "the brave is dead")
	check(t[0].kills_other == 1 and t[0].kills_by_golems == 0, "one kill for blue, not by a golem")
	check(t[1].units_lost == 1, "one loss for red")
	check(t[1].kills_other == 0 and t[0].units_lost == 0, "nothing else booked")
	_free_world(w)


func test_all_three_golems_count_as_golem_kills() -> void:
	var w: Dictionary = _make_world()
	var t: Array[Tribe] = w.tribes
	var x: float = 40.0
	for scene in [GOLEM_SCENE, DEMON_SCENE, GENESIS_SCENE]:
		var golem: Unit = _spawn(w, scene, 0, x)
		check(golem.is_golem(), "%s is a golem" % golem.display_name())
		var victim: Unit = _spawn(w, BRAVE_SCENE, 1, x + 3.0)
		victim.take_damage(9999, golem)
		x += 20.0
	check(t[0].kills_by_golems == 3, "three golem kills (got %d)" % t[0].kills_by_golems)
	check(t[0].kills_other == 0, "none of them counts as an other kill")
	check(not _spawn(w, WARRIOR_SCENE, 2).is_golem(), "a warrior is no golem")
	_free_world(w)


func test_a_death_without_a_blow_counts_for_the_last_harmer() -> void:
	var w: Dictionary = _make_world()
	var t: Array[Tribe] = w.tribes
	var golem: Unit = _spawn(w, GOLEM_SCENE, 2)
	var victim: Unit = _spawn(w, WARRIOR_SCENE, 1, 63.0)
	victim.take_damage(1, golem)
	# Lava (no tribe) finishes him: the record of the golem's blow stands.
	var lava: Node3D = Node3D.new()
	victim.ignite(victim.position, lava)
	check(victim.last_harm_tribe == 2 and victim.last_harm_by_golem,
		"lava carries no tribe — the golem stays the last harmer")
	victim.take_damage(9999)
	check(t[2].kills_by_golems == 1, "the golem's tribe gets the kill")
	lava.free()
	_free_world(w)


func test_spell_effects_with_a_tribe_count_as_other_kills() -> void:
	var w: Dictionary = _make_world()
	var t: Array[Tribe] = w.tribes
	var effect: FakeSpellEffect = FakeSpellEffect.new()
	effect.tribe_id = 1
	var victim: Unit = _spawn(w, BRAVE_SCENE, 0)
	victim.note_harm(effect)
	victim.take_damage(9999)   # the fall after the throw: no attacker
	check(t[1].kills_other == 1 and t[1].kills_by_golems == 0, "the caster's tribe gets an other kill")
	effect.free()
	_free_world(w)


func test_no_kill_for_own_units_unharmed_deaths_vehicles_and_crumbling() -> void:
	var w: Dictionary = _make_world()
	var t: Array[Tribe] = w.tribes
	# Own firestorm: no kill, but a loss.
	var own: Unit = _spawn(w, BRAVE_SCENE, 0)
	var friend: Unit = _spawn(w, WARRIOR_SCENE, 0, 64.0)
	own.take_damage(9999, friend)
	check(t[0].kills_other == 0 and t[0].kills_by_golems == 0, "killing an own unit is no kill")
	check(t[0].units_lost == 1, "but it is a loss")
	# Nobody ever touched him (drowned on his own): a loss without a killer.
	var lonely: Unit = _spawn(w, BRAVE_SCENE, 1, 70.0)
	lonely.take_damage(9999)
	check(t[1].units_lost == 1, "a death without a harmer is a loss")
	for tribe in t:
		check(tribe.kills_other + tribe.kills_by_golems == 0, "… and nobody's kill")
	# A vehicle is a device: neither a kill nor a loss.
	var catapult: Unit = _spawn(w, SIEGE_SCENE, 1, 80.0)
	var warrior: Unit = _spawn(w, WARRIOR_SCENE, 0, 82.0)
	catapult.note_harm(warrior)
	catapult.drown()
	check(catapult.state == Unit.State.DEAD, "the catapult is gone")
	check(t[0].kills_other == 0 and t[1].units_lost == 1, "a vehicle is no kill and no loss")
	# A golem that falls apart at the end of its life is nobody's kill.
	var golem: Golem = _spawn(w, GOLEM_SCENE, 1, 90.0) as Golem
	golem.take_damage(1, warrior)
	golem._crumble()
	check(golem.state == Unit.State.DEAD, "the golem crumbled")
	check(t[0].kills_other == 0, "crumbling is no kill for the last harmer")
	check(t[1].units_lost == 2, "but the golem is a loss")
	_free_world(w)


func test_peak_population_follows_the_followers() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribes[0]
	var braves: Array[Unit] = []
	for i in range(5):
		braves.append(_spawn(w, BRAVE_SCENE, 0, 40.0 + float(i) * 2.0))
	check(tribe.peak_population == 5, "five followers at the peak")
	for i in range(3):
		braves[i].take_damage(9999)
	check(tribe.population() == 2 and tribe.peak_population == 5, "the peak stays when they die")
	_spawn(w, GOLEM_SCENE, 0, 90.0)
	_spawn(w, SIEGE_SCENE, 0, 100.0)
	check(tribe.peak_population == 5, "golems and vehicles are no followers")
	for i in range(4):
		_spawn(w, BRAVE_SCENE, 0, 20.0 + float(i) * 2.0)
	check(tribe.peak_population == 6, "a new high raises the peak (got %d)" % tribe.peak_population)
	_free_world(w)


func test_end_screen_rows_and_time_format() -> void:
	var a: Tribe = Tribe.new(0, Unit.TRIBE_COLORS[0])
	var b: Tribe = Tribe.new(1, Unit.TRIBE_COLORS[1])
	b.ai_personality_name = "Ökonom"
	a.kills_by_golems = 4
	a.kills_other = 7
	b.units_lost = 11
	b.peak_population = 30
	b.eliminated = true
	var rows: Array[Dictionary] = TribeStats.rows([a, b] as Array[Tribe], 0)
	check(rows.size() == 2, "one row per tribe")
	check(rows[0]["name"] == "Blau (du)" and rows[1]["name"] == "Rot (Ökonom)",
		"names: the player and the AI's personality (%s / %s)" % [rows[0]["name"], rows[1]["name"]])
	check(rows[0]["kills_golem"] == 4 and rows[0]["kills_other"] == 7, "the kills of blue")
	check(rows[1]["lost"] == 11 and rows[1]["peak"] == 30 and rows[1]["eliminated"],
		"losses, peak and the elimination of red")
	check(TribeStats.format_time(0.0) == "0:00", "0:00")
	check(TribeStats.format_time(754.9) == "12:34", "12:34")
	check(TribeStats.format_time(3723.0) == "1:02:03", "1:02:03")
