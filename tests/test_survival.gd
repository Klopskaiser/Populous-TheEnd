extends TestBase

## Survival mode ("Überleben"): the wave table (size, mix, spawn directions) is a
## pure function of the wave number; the wave tribe must not drop out of the
## match while it owns no unit between two waves; victory needs ALL waves out
## and the last wave enemy dead; the player's defeat stays the ordinary rule.
## GameState is instantiated directly (no autoloads in the headless runner).

const GameStateScript: GDScript = preload("res://scripts/core/game_state.gd")

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")

const PLAYER: int = 0
const WAVES: int = 1
const BASE: Vector2i = Vector2i(64, 64)


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


## Two tribes (0 = player with one brave at the base, 1 = wave tribe, empty), a
## GameState with win tracking and a SurvivalMode set up on the map centre.
func _make_world() -> Dictionary:
	var td: TerrainData = _flat_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var tribes: Array[Tribe] = [Tribe.new(PLAYER), Tribe.new(WAVES)]
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, tribes)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um)
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(nav, bm, um)
	var gs: Node = GameStateScript.new()
	gs.tribes = tribes
	var brave: Unit = um.spawn_unit(BRAVE_SCENE, PLAYER, nav.cell_to_world(BASE))
	gs.start_win_tracking()
	var mode: SurvivalMode = SurvivalMode.new()
	mode.setup(tribes[WAVES], tribes[PLAYER], um, tc, nav, BASE, gs)
	var winners: Array[int] = []
	gs.match_ended.connect(func(id: int) -> void: winners.append(id))
	return {
		"td": td, "nav": nav, "tribes": tribes, "um": um, "bm": bm, "tc": tc,
		"gs": gs, "mode": mode, "brave": brave, "winners": winners,
		"player": tribes[PLAYER], "waves": tribes[WAVES],
	}


func _free_world(w: Dictionary) -> void:
	w.mode.free()
	w.gs.free()
	w.tc.free()
	w.bm.free()
	w.um.free()


func _kill_all(tribe: Tribe) -> void:
	for unit in tribe.units.duplicate():
		unit.take_damage(999999)


func _count_kind(tribe: Tribe, kind: StringName) -> int:
	var count: int = 0
	for unit in tribe.units:
		if unit.unit_kind() == kind:
			count += 1
	return count


# --- Wave table (pure) -------------------------------------------------------------

func test_wave_size_grows_strictly_and_stays_below_the_cap() -> void:
	check(SurvivalMode.WAVE_COUNT == 20, "the mode runs 20 waves")
	check(SurvivalMode.wave_size(1) == 8, "wave 1 has 8 units")
	check(SurvivalMode.wave_size(10) == 37, "wave 10 has 37 units")
	check(SurvivalMode.wave_size(20) == 96, "wave 20 has 96 units")
	var last: int = SurvivalMode.wave_size(SurvivalMode.WAVE_COUNT)
	check(last >= 80 and last <= 100, "the last wave lies in the 80..100 target band")
	var total: int = 0
	for wave in range(1, SurvivalMode.WAVE_COUNT + 1):
		var size: int = SurvivalMode.wave_size(wave)
		total += size
		check(size < Balance.TRIBE_MAX_UNITS, "wave %d fits under the unit hard cap" % wave)
		if wave > 1:
			check(size > SurvivalMode.wave_size(wave - 1),
				"wave %d is bigger than wave %d" % [wave, wave - 1])
	check(SurvivalMode.total_wave_units() == total, "total_wave_units sums the table")
	check(total == 877, "all 20 waves together are 877 units (got %d)" % total)
	check(total < Balance.TRIBE_MAX_UNITS,
		"even with no kill at all the waves never reach the hard cap")


func test_wave_composition() -> void:
	for wave in range(1, SurvivalMode.WAVE_COUNT + 1):
		var mix: Dictionary[StringName, int] = SurvivalMode.wave_composition(wave)
		var warriors: int = mix[SurvivalMode.KIND_WARRIOR]
		var firewarriors: int = mix[SurvivalMode.KIND_FIREWARRIOR]
		var preachers: int = mix[SurvivalMode.KIND_PREACHER]
		var size: int = SurvivalMode.wave_size(wave)
		check(warriors + firewarriors + preachers == size,
			"wave %d: the mix adds up to the wave size" % wave)
		check(warriors * 2 > size, "wave %d: warriors are the majority" % wave)
		check(firewarriors >= 1, "wave %d: brings firewarriors" % wave)
		check(preachers < firewarriors and preachers * 10 <= size,
			"wave %d: preachers stay few" % wave)
		check(mix == SurvivalMode.wave_composition(wave),
			"wave %d: the mix follows from the wave number alone" % wave)
	var first: Dictionary[StringName, int] = SurvivalMode.wave_composition(1)
	check(first[SurvivalMode.KIND_WARRIOR] == 6 and first[SurvivalMode.KIND_FIREWARRIOR] == 2
		and first[SurvivalMode.KIND_PREACHER] == 0, "wave 1 = 6 warriors, 2 firewarriors")
	var tenth: Dictionary[StringName, int] = SurvivalMode.wave_composition(10)
	check(tenth[SurvivalMode.KIND_WARRIOR] == 23 and tenth[SurvivalMode.KIND_FIREWARRIOR] == 11
		and tenth[SurvivalMode.KIND_PREACHER] == 3, "wave 10 = 23 / 11 / 3")
	var last: Dictionary[StringName, int] = SurvivalMode.wave_composition(20)
	check(last[SurvivalMode.KIND_WARRIOR] == 59 and last[SurvivalMode.KIND_FIREWARRIOR] == 28
		and last[SurvivalMode.KIND_PREACHER] == 9, "wave 20 = 59 / 28 / 9")


func test_spawn_slots_rotate() -> void:
	var points: int = SurvivalMode.SPAWN_POINTS
	var previous: PackedInt32Array = PackedInt32Array()
	for wave in range(1, SurvivalMode.WAVE_COUNT + 1):
		var slots: PackedInt32Array = SurvivalMode.wave_spawn_slots(wave, points)
		var want: int = 2 if wave < SurvivalMode.LATE_FRONT_WAVE else 3
		check(slots.size() == want, "wave %d comes from %d directions" % [wave, want])
		var seen: Dictionary = {}
		for slot in slots:
			check(slot >= 0 and slot < points, "wave %d: slot inside the point list" % wave)
			seen[slot] = true
		check(seen.size() == slots.size(), "wave %d: every front has its own direction" % wave)
		check(slots != previous, "wave %d comes from elsewhere than the wave before" % wave)
		previous = slots
	check(SurvivalMode.wave_spawn_slots(5, 0).is_empty(), "no spawn point -> no slot")
	check(SurvivalMode.wave_spawn_slots(12, 1) == PackedInt32Array([0]),
		"a single spawn point is used once, not three times")


func test_spawn_cells_lie_at_the_rim_on_walkable_ground() -> void:
	var w: Dictionary = _make_world()
	var cells: Array[Vector2i] = w.mode.spawn_cells
	check(cells.size() == SurvivalMode.SPAWN_POINTS, "flat disc: one spawn cell per direction")
	var island: int = w.nav.island_at(BASE)
	for cell in cells:
		check(w.nav.is_cell_walkable(cell), "spawn cell %s is walkable" % cell)
		check(w.nav.island_at(cell) == island, "spawn cell %s is reachable from the base" % cell)
		var dist: float = Vector2(cell - BASE).length()
		check(dist >= float(SurvivalMode.SPAWN_MIN_DISTANCE),
			"spawn cell %s keeps its distance from the base" % cell)
		check(dist >= w.td.disc_radius() - float(SurvivalMode.SPAWN_INSET) - 2.0,
			"spawn cell %s sits at the edge of the map" % cell)
	_free_world(w)

	# The real map of the mode: a round island with water all around.
	var td: TerrainData = MapGenerator.create_terrain(MapGenerator.DEFAULT_MAP, 1337)
	var nav: NavGrid = NavGrid.new(td)
	var base: Vector2i = TerrainData.center_cell(td)
	var shore: Array[Vector2i] = SurvivalMode.find_spawn_cells(nav, base)
	check(shore.size() >= 3, "island: at least three directions (got %d)" % shore.size())
	var home: int = nav.island_at(nav.nearest_walkable_cell(base))
	for cell in shore:
		check(nav.is_cell_walkable(cell) and nav.island_at(cell) == home,
			"island spawn cell %s is on the base's landmass" % cell)


# --- Waves in the world --------------------------------------------------------------

func test_first_wave_spawns_marches_and_matches_its_mix() -> void:
	var w: Dictionary = _make_world()
	var mode: SurvivalMode = w.mode
	check(mode.wave == 0 and w.waves.units.is_empty(), "no wave before the delay")
	check_near(mode.time_to_next_wave(), SurvivalMode.FIRST_WAVE_DELAY,
		"the countdown starts at the first-wave delay")
	mode.tick(SurvivalMode.FIRST_WAVE_DELAY - 1.0)
	check(mode.wave == 0 and w.waves.units.is_empty(), "still nothing one second early")
	mode.tick(1.0)
	check(mode.wave == 1, "the first wave is out")
	check(w.waves.units.size() == SurvivalMode.wave_size(1), "wave 1 spawned in full")
	check(mode.enemies_alive() == SurvivalMode.wave_size(1), "enemies_alive counts them")
	var mix: Dictionary[StringName, int] = SurvivalMode.wave_composition(1)
	for kind in mix:
		check(_count_kind(w.waves, kind) == mix[kind], "wave 1 fields %d %s" % [mix[kind], kind])
	check(w.tribes[WAVES].buildings.is_empty() and w.waves.shaman == null,
		"the wave tribe has neither buildings nor a shaman")
	var base_world: Vector3 = w.nav.cell_to_world(BASE)
	var sides: Dictionary = {}
	for unit in w.waves.units:
		check(unit.state == Unit.State.MOVE and unit.move_aggressive,
			"wave units are on an attack-move")
		check(unit.waypoint_queue.size() == 1
			and unit.waypoint_queue[0].distance_to(base_world) < 12.0,
			"…at the player's base")
		check(w.nav.is_cell_walkable(w.nav.world_to_cell(unit.position)),
			"spawned on walkable ground")
		sides[unit.position.x > base_world.x] = true
	check(sides.size() == 2, "wave 1 comes from two opposite directions")
	check_near(mode.time_to_next_wave(), SurvivalMode.WAVE_INTERVAL,
		"the next countdown runs from the wave's appearance")
	_free_world(w)


func test_next_wave_comes_on_time_while_the_previous_lives() -> void:
	var w: Dictionary = _make_world()
	var mode: SurvivalMode = w.mode
	mode.tick(SurvivalMode.FIRST_WAVE_DELAY)
	mode.tick(SurvivalMode.WAVE_INTERVAL - 1.0)
	check(mode.wave == 1, "one second before the interval: still wave 1")
	mode.tick(1.0)
	check(mode.wave == 2, "wave 2 appears after the fixed pause")
	check(w.waves.units.size() == SurvivalMode.wave_size(1) + SurvivalMode.wave_size(2),
		"…on top of the living wave 1 (a steady stream, not wave-clear)")
	_free_world(w)


func test_wave_tribe_is_not_eliminated_between_waves() -> void:
	var w: Dictionary = _make_world()
	var mode: SurvivalMode = w.mode
	var defeated: Array[int] = []
	w.gs.tribe_defeated.connect(func(id: int) -> void: defeated.append(id))
	check(w.gs.is_defeat_exempt(WAVES), "setup shields the wave tribe")
	check(not w.gs.is_defeat_exempt(PLAYER), "the player is never shielded")
	# Before the first wave the tribe owns nothing at all.
	w.gs.check_defeats()
	check(not w.waves.eliminated and defeated.is_empty() and not w.gs.match_over,
		"empty before wave 1: not eliminated, match runs")
	# After a wave was wiped out completely.
	mode.tick(SurvivalMode.FIRST_WAVE_DELAY)
	_kill_all(w.waves)
	check(w.waves.units.is_empty() and mode.enemies_alive() == 0, "wave 1 is dead")
	w.gs.check_defeats()
	check(not w.waves.eliminated and defeated.is_empty() and not w.gs.match_over,
		"wiped out between two waves: not eliminated, match runs")
	check(w.winners.is_empty(), "no winner yet")
	# …and the next wave still comes and can still be commanded.
	mode.tick(SurvivalMode.WAVE_INTERVAL)
	check(mode.wave == 2 and w.waves.units.size() == SurvivalMode.wave_size(2),
		"wave 2 appears for the surviving tribe")
	check(w.waves.units[0].state == Unit.State.MOVE, "and takes its march order")
	_free_world(w)


func test_victory_needs_all_waves_and_the_last_enemy_dead() -> void:
	var w: Dictionary = _make_world()
	var mode: SurvivalMode = w.mode
	mode.tick(SurvivalMode.FIRST_WAVE_DELAY)
	for wave in range(1, SurvivalMode.WAVE_COUNT):
		check(mode.wave == wave, "wave %d is out" % wave)
		_kill_all(w.waves)
		w.gs.check_defeats()
		check(not w.gs.match_over and not w.waves.eliminated,
			"wave %d cleared: the match goes on" % wave)
		check(mode.time_to_next_wave() > 0.0, "wave %d: another countdown runs" % wave)
		mode.tick(SurvivalMode.WAVE_INTERVAL)
	check(mode.wave == SurvivalMode.WAVE_COUNT and mode.all_waves_spawned(),
		"the last wave is out")
	check(w.waves.units.size() == SurvivalMode.wave_size(SurvivalMode.WAVE_COUNT),
		"…in full")
	check_near(mode.time_to_next_wave(), -1.0, "no countdown after the last wave")
	check(not w.gs.is_defeat_exempt(WAVES), "the shield falls with the last wave")
	w.gs.check_defeats()
	check(not w.gs.match_over, "last wave alive: no victory yet")
	# Everyone but one dies.
	var units: Array[Unit] = w.waves.units.duplicate()
	for i in range(1, units.size()):
		units[i].take_damage(999999)
	w.gs.check_defeats()
	check(not w.gs.match_over and w.winners.is_empty(),
		"one wave enemy left: still no victory")
	units[0].take_damage(999999)
	w.gs.check_defeats()
	check(w.gs.match_over, "last enemy of the last wave dead: the match is decided")
	check(w.winners == ([PLAYER] as Array[int]), "…and the player won it")
	check(w.waves.eliminated, "the wave tribe is out by the ordinary rule")
	# A decided match spawns nothing any more.
	mode.tick(SurvivalMode.WAVE_INTERVAL * 3.0)
	check(mode.wave == SurvivalMode.WAVE_COUNT and w.waves.units.is_empty(),
		"nothing happens after the end")
	_free_world(w)


func test_player_wiped_out_is_a_defeat() -> void:
	var w: Dictionary = _make_world()
	var mode: SurvivalMode = w.mode
	mode.tick(SurvivalMode.FIRST_WAVE_DELAY)
	w.gs.check_defeats()
	check(not w.gs.match_over, "player alive: the match runs")
	w.brave.take_damage(999999)
	w.gs.check_defeats()
	check(w.gs.match_over, "the player's last unit died: the match is over")
	check(w.winners == ([WAVES] as Array[int]), "…and the wave tribe is the winner (Niederlage)")
	check(w.player.eliminated and not w.waves.eliminated, "the player is out, the waves are not")
	_free_world(w)

	# Also before the first wave and with an EMPTY wave tribe: the shield must not
	# turn a lost match into a draw.
	var w2: Dictionary = _make_world()
	w2.brave.take_damage(999999)
	w2.gs.check_defeats()
	check(w2.gs.match_over and w2.winners == ([WAVES] as Array[int]),
		"defeat counts even while the wave tribe owns no unit")
	_free_world(w2)


func test_idle_wave_units_are_sent_at_the_player_again() -> void:
	var w: Dictionary = _make_world()
	var mode: SurvivalMode = w.mode
	# A straggler standing around far from the player's only unit.
	var straggler: Unit = w.um.spawn_unit(WARRIOR_SCENE, WAVES, Vector3(40.5, 0, 40.5))
	check(straggler.state == Unit.State.IDLE, "the straggler idles")
	mode.tick(SurvivalMode.REGROUP_INTERVAL - 0.5)
	check(straggler.state == Unit.State.IDLE, "not before the regroup interval")
	mode.tick(0.5)
	check(straggler.state == Unit.State.MOVE and straggler.move_aggressive,
		"the regroup sends it on an attack-move")
	check(straggler.waypoint_queue[0].distance_to(w.brave.position) < 3.0,
		"…at the nearest player unit")
	_free_world(w)


func test_exemption_is_scoped_to_the_mode() -> void:
	# The ordinary rule is untouched: without a shield an empty tribe drops out.
	var gs: Node = GameStateScript.new()
	var tribes: Array[Tribe] = [Tribe.new(0), Tribe.new(1)]
	var brave: Brave = Brave.new()
	tribes[0].add_unit(brave)
	gs.tribes = tribes
	gs.start_win_tracking()
	gs.check_defeats()
	check(tribes[1].eliminated and gs.match_over,
		"no shield (skirmish): an empty tribe is eliminated and the match ends")
	gs.free()
	# The shield does not survive a new match.
	var gs2: Node = GameStateScript.new()
	gs2.set_defeat_exempt(1, true)
	check(gs2.is_defeat_exempt(1), "shield set")
	gs2.stop_win_tracking()
	check(not gs2.is_defeat_exempt(1), "stop_win_tracking clears the shield")
	gs2.set_defeat_exempt(1, true)
	gs2.reset()
	check(not gs2.is_defeat_exempt(1), "reset clears the shield")
	gs2.free()
	brave.free()


func test_match_config() -> void:
	var config: MatchConfig = MatchConfig.survival()
	check(config.mode == MatchConfig.Mode.SURVIVAL, "survival() selects the mode")
	check(config.tribe_count() == 2, "survival runs with two tribes (player + waves)")


# --- HUD texts (pure) ------------------------------------------------------------------

func test_hud_texts() -> void:
	check(SurvivalHud.wave_text(3, 20) == "Welle 3/20", "wave counter")
	check(SurvivalHud.wave_text(0, 20) == "Welle 0/20", "wave counter before the first wave")
	check(SurvivalHud.format_time(75.0) == "1:15", "minutes and seconds")
	check(SurvivalHud.format_time(44.2) == "0:45", "rounded up")
	check(SurvivalHud.format_time(-3.0) == "0:00", "never negative")
	check(SurvivalHud.status_text(0, 30.0, 0) == "Erste Welle in 0:30", "before wave 1")
	check(SurvivalHud.status_text(3, 12.0, 40) == "Nächste Welle in 0:12", "between waves")
	check(SurvivalHud.status_text(20, -1.0, 12) == "Letzte Welle — noch 12 Gegner",
		"after the last wave")
	check(SurvivalHud.status_text(20, -1.0, 0) == "Alle Wellen überstanden", "all done")


## Zaubertestgelaende: mit jeder Welle sind alle Zauber des Spielers wieder voll.
func test_every_wave_refills_the_players_spells() -> void:
	var w: Dictionary = _make_world()
	var player: Tribe = w.player
	if player.spells.is_empty():
		player.set_spells(Spell.create_default_set())
	for spell in player.spells:
		spell.charges = 0
	w.mode._spawn_next_wave()
	var full: bool = true
	for spell in player.spells:
		full = full and spell.charges == spell.max_charges
	check(Balance.SURVIVAL_REFILL_SPELLS_EACH_WAVE and full and not player.spells.is_empty(),
		"a new wave recharges every spell of the player")
	_free_world(w)
