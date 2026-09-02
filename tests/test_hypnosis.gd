extends TestBase

## Phase 10k, Teil 6: Zauber 12 "Hypnose". Bekehrt gegnerische Anhänger in einem
## 4x4-m-Quadrat VORÜBERGEHEND (30 s) zum eigenen Stamm; sie sind so lange normal
## steuerbar und kämpfen für den Kontrolleur.
##
## Der Stammeswechsel ist bewusst der VOLLE (convert_to_tribe): Bevölkerung,
## Manaerzeugung und Selektion wandern mit. Wer damit die letzten Einheiten eines
## Stammes hypnotisiert, beendet ihn — ausdrückliche Nutzerentscheidung, und
## test_hypnotizing_the_last_units_defeats_the_origin_tribe nagelt sie fest,
## damit sie später nicht als Bug "repariert" wird.

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const PREACHER_SCENE: PackedScene = preload("res://scenes/units/preacher.tscn")
const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")


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


func _spawn(w: Dictionary, scene: PackedScene, tribe_id: int, at: Vector3) -> Unit:
	return w.um.spawn_unit(scene, tribe_id, at)


func _hypnosis() -> HypnosisSpell:
	return HypnosisSpell.new()


# --- Kontrollwechsel ----------------------------------------------------------

func test_hypnotized_unit_changes_side_and_is_controllable() -> void:
	var w: Dictionary = _make_world()
	var victim: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector3(50, 5, 50))
	check(victim.tribe_id == 1, "the victim starts out enemy")
	check(victim.hypnotize(w.t0, Balance.HYPNOSIS_DURATION), "hypnosis takes")
	check(victim.tribe_id == 0, "it now belongs to the caster")
	check(victim.is_hypnotized(), "and is marked as hypnotized")
	check(victim in w.t0.units, "the controller has it in its unit list")
	check(not (victim in w.t1.units), "the origin tribe does not")
	# Controllable: a move order from the new owner is accepted.
	w.commands.order_move([victim] as Array[Unit], Vector3(60, 5, 50))
	check(victim.state == Unit.State.MOVE, "it obeys the new controller")
	_free_world(w)


func test_control_returns_after_the_duration() -> void:
	var w: Dictionary = _make_world()
	var victim: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector3(50, 5, 50))
	victim.hypnotize(w.t0, Balance.HYPNOSIS_DURATION)
	# Just before the end it is still controlled ...
	for i in range(int((Balance.HYPNOSIS_DURATION - 1.0) / 0.1)):
		victim.tick(0.1)
	check(victim.tribe_id == 0, "still controlled shortly before the end")
	check(victim.is_hypnotized(), "and still marked")
	# ... and afterwards it is back.
	for i in range(20):
		victim.tick(0.1)
	check(victim.tribe_id == 1, "control returns to the origin tribe")
	check(not victim.is_hypnotized(), "the mark is gone")
	check(victim in w.t1.units, "and the origin tribe has it back")
	_free_world(w)


func test_remaining_time_counts_down() -> void:
	var w: Dictionary = _make_world()
	var victim: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector3(50, 5, 50))
	victim.hypnotize(w.t0, Balance.HYPNOSIS_DURATION)
	check_near(victim.hypnosis_remaining(), Balance.HYPNOSIS_DURATION,
		"the full duration is on the clock")
	for i in range(50):
		victim.tick(0.1)
	check(victim.hypnosis_remaining() < Balance.HYPNOSIS_DURATION - 4.0,
		"the clock runs down")
	check(victim.hypnosis_remaining() > 0.0, "but has not expired yet")
	_free_world(w)


# --- Wer ist immun ------------------------------------------------------------

func test_shaman_is_immune() -> void:
	var w: Dictionary = _make_world()
	var shaman: Unit = _spawn(w, SHAMAN_SCENE, 1, Vector3(50, 5, 50))
	w.t1.shaman = shaman
	check(not shaman.hypnotize(w.t0, Balance.HYPNOSIS_DURATION),
		"the enemy shaman cannot be hypnotized (user spec)")
	check(shaman.tribe_id == 1, "she stays with her tribe")
	_free_world(w)


## Anders als bei der Bekehrung: Prediger sind hypnotisierbar.
func test_preacher_can_be_hypnotized() -> void:
	var w: Dictionary = _make_world()
	var preacher: Unit = _spawn(w, PREACHER_SCENE, 1, Vector3(50, 5, 50))
	check(preacher.is_conversion_immune(),
		"a preacher is immune to CONVERSION (7i rule, unchanged)")
	check(preacher.hypnotize(w.t0, Balance.HYPNOSIS_DURATION),
		"but hypnosis takes him — only the shaman is immune")
	check(preacher.tribe_id == 0, "he fights for the caster")
	_free_world(w)


func test_own_units_cannot_be_hypnotized() -> void:
	var w: Dictionary = _make_world()
	var own: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector3(50, 5, 50))
	check(not own.hypnotize(w.t0, Balance.HYPNOSIS_DURATION),
		"you cannot hypnotize your own people")
	_free_world(w)


# --- Zusammenspiel mit der Bekehrung ------------------------------------------

## Die Bekehrung gewinnt und ist ENDGÜLTIG: der Timer darf die Einheit nicht
## zurückziehen.
func test_preacher_conversion_beats_hypnosis_and_is_permanent() -> void:
	var w: Dictionary = _make_world()
	var victim: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector3(50, 5, 50))
	victim.hypnotize(w.t0, Balance.HYPNOSIS_DURATION)
	check(victim.is_hypnotized(), "hypnotized first")
	# Now a preacher of tribe 1 converts it back — permanently.
	victim.convert_to_tribe(w.t1)
	check(not victim.is_hypnotized(), "the conversion cleared the hypnosis")
	check(victim.tribe_id == 1, "and it belongs to the converting tribe")
	# The old timer must not drag it anywhere.
	for i in range(int(Balance.HYPNOSIS_DURATION / 0.1) + 20):
		victim.tick(0.1)
	check(victim.tribe_id == 1, "it STAYS there after the old duration elapsed")
	_free_world(w)


func test_rehypnotizing_refreshes_but_keeps_the_true_origin() -> void:
	var w: Dictionary = _make_world()
	var victim: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector3(50, 5, 50))
	victim.hypnotize(w.t0, Balance.HYPNOSIS_DURATION)
	for i in range(100):
		victim.tick(0.1)   # 10 s down
	victim.hypnotize(w.t0, Balance.HYPNOSIS_DURATION)
	check_near(victim.hypnosis_remaining(), Balance.HYPNOSIS_DURATION,
		"the clock is refreshed")
	# Run it out: it must fall back to tribe 1, NOT to the controller.
	for i in range(int(Balance.HYPNOSIS_DURATION / 0.1) + 20):
		victim.tick(0.1)
	check(victim.tribe_id == 1, "it returns to its TRUE origin, not the controller")
	_free_world(w)


# --- Siegbedingung (Nutzerentscheidung) ---------------------------------------

## NUTZERREGEL, kein Bug: wer die letzten Einheiten eines Stammes hypnotisiert,
## beendet ihn. Dieser Test hält das fest, damit es später nicht "repariert" wird.
func test_hypnotizing_the_last_units_defeats_the_origin_tribe() -> void:
	var w: Dictionary = _make_world()
	var last: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector3(50, 5, 50))
	check(not GameState.is_tribe_defeated(w.t1), "tribe 1 is alive to begin with")
	check(last.hypnotize(w.t0, Balance.HYPNOSIS_DURATION), "its last unit is taken")
	check(GameState.is_tribe_defeated(w.t1),
		"a tribe whose last unit is hypnotized away IS defeated (user decision)")
	_free_world(w)


## Folge daraus: der Rückweg zu einem gefallenen Stamm entfällt, der Wechsel
## wird endgültig — sonst stünde die Einheit bei einem toten Stamm.
func test_hypnosis_becomes_permanent_when_the_origin_tribe_fell() -> void:
	var w: Dictionary = _make_world()
	var victim: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector3(50, 5, 50))
	victim.hypnotize(w.t0, Balance.HYPNOSIS_DURATION)
	w.t1.eliminated = true          # the origin tribe is out for good (10d)
	for i in range(int(Balance.HYPNOSIS_DURATION / 0.1) + 20):
		victim.tick(0.1)
	check(victim.tribe_id == 0, "it stays with the controller")
	check(not victim.is_hypnotized(), "and is no longer temporary")
	_free_world(w)


## Die Manaerzeugung wandert mit — man verleiht nicht nur Kampfkraft.
func test_mana_income_follows_the_controller() -> void:
	var w: Dictionary = _make_world()
	var victim: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector3(50, 5, 50))
	var rate0: float = w.t0.mana_rate()
	var rate1: float = w.t1.mana_rate()
	victim.hypnotize(w.t0, Balance.HYPNOSIS_DURATION)
	check(w.t0.mana_rate() > rate0, "the controller earns more")
	check(w.t1.mana_rate() < rate1, "the origin tribe earns less")
	_free_world(w)


# --- Wirkfläche ---------------------------------------------------------------

func test_area_is_four_by_four_metres() -> void:
	check_near(Balance.HYPNOSIS_AREA_SIZE, 4.0, "the square is 4 m per side")
	check_near(Balance.HYPNOSIS_DURATION, 30.0, "control lasts 30 s")
	check_near(Balance.SPELL_HYPNOSIS_CHARGE_COST, 210.0, "210 mana per charge")
	check(Balance.SPELL_HYPNOSIS_MAX_CHARGES == 3, "three charges")
	check_near(Balance.SPELL_HYPNOSIS_CAST_RANGE, 10.0, "10 m cast range")


func test_units_inside_the_square_are_taken_and_outside_are_not() -> void:
	var w: Dictionary = _make_world()
	var centre: Vector3 = Vector3(50, 5, 50)
	var half: float = Balance.HYPNOSIS_AREA_SIZE * 0.5
	var inside: Unit = _spawn(w, WARRIOR_SCENE, 1, centre + Vector3(half - 0.3, 0, 0))
	var corner: Unit = _spawn(w, BRAVE_SCENE, 1,
		centre + Vector3(half - 0.2, 0, half - 0.2))
	var outside: Unit = _spawn(w, WARRIOR_SCENE, 1, centre + Vector3(half + 1.0, 0, 0))
	# Just outside a CORNER: inside the circumscribed circle, outside the square.
	var diagonal: Unit = _spawn(w, BRAVE_SCENE, 1,
		centre + Vector3(half + 0.3, 0, half + 0.3))
	var picked: Array[Unit] = HypnosisSpell.units_in_square(w.um, centre, 0)
	check(inside in picked, "a unit inside the square is taken")
	check(corner in picked, "including one near the corner")
	check(not (outside in picked), "one beyond the edge is not")
	check(not (diagonal in picked),
		"and the SQUARE is used, not the circumscribed circle")
	_free_world(w)


func test_own_and_shaman_are_never_in_the_area_selection() -> void:
	var w: Dictionary = _make_world()
	var centre: Vector3 = Vector3(50, 5, 50)
	var own: Unit = _spawn(w, WARRIOR_SCENE, 0, centre)
	var shaman: Unit = _spawn(w, SHAMAN_SCENE, 1, centre + Vector3(0.5, 0, 0))
	w.t1.shaman = shaman
	var enemy: Unit = _spawn(w, BRAVE_SCENE, 1, centre + Vector3(-0.5, 0, 0))
	var picked: Array[Unit] = HypnosisSpell.units_in_square(w.um, centre, 0)
	check(not (own in picked), "own units are never selected")
	check(not (shaman in picked), "the enemy shaman is never selected")
	check(enemy in picked, "the ordinary enemy is")
	_free_world(w)


# --- Als Zauber gewirkt -------------------------------------------------------

func test_casting_hypnosis_takes_the_whole_group() -> void:
	var w: Dictionary = _make_world()
	var centre: Vector3 = Vector3(50, 5, 50)
	var group: Array[Unit] = []
	for i in range(4):
		group.append(_spawn(w, BRAVE_SCENE, 1,
			centre + Vector3(-1.2 + float(i) * 0.8, 0, 0)))
	var spell: HypnosisSpell = _hypnosis()
	check(spell.execute(w.t0, centre, w.ctx), "the cast reports success")
	var taken: int = 0
	for u in group:
		if u.tribe_id == 0 and u.is_hypnotized():
			taken += 1
	check(taken == group.size(), "every enemy in the square changed side (%d)" % taken)
	_free_world(w)


## Ohne Ziel im Quadrat schlägt der Cast fehl — die Ladung bleibt erhalten
## (Spell.cast verbraucht nur bei Erfolg).
func test_casting_on_empty_ground_fails_and_keeps_the_charge() -> void:
	var w: Dictionary = _make_world()
	var spell: HypnosisSpell = _hypnosis()
	check(not spell.execute(w.t0, Vector3(50, 5, 50), w.ctx),
		"nothing to hypnotize: the cast fails")
	_free_world(w)


# --- Sounds -------------------------------------------------------------------

## Hypnose hat beide Zaubersounds wie jeder andere Zauber: die Formel läuft
## generisch über Events.spell_cast_started (AudioManager), den EFFEKT spielt
## execute() selbst — sie ist der einzige Zauber ohne Effekt-Entität, an der er
## sonst hängen würde. Der Test nagelt die vier Namen fest, damit Code und
## assets/README.md nicht auseinanderlaufen.
func test_spell_sound_names() -> void:
	var spell: HypnosisSpell = _hypnosis()
	check(spell.id == &"hypnosis", "die Zauber-Id heißt hypnosis")
	check(SpellAudio.voice_name(spell.id) == &"spell_voice_hypnosis",
		"die Zauberformel heißt spell_voice_hypnosis")
	check(SpellAudio.effect_name(spell.id) == &"spell_hypnosis",
		"der Effektsound heißt spell_hypnosis")
	check(AudioSlots.default_priority(SpellAudio.voice_name(spell.id))
		== AudioSlots.PRIO_CRITICAL, "die Formel erbt Prio 1 über den Präfix")
	check(AudioSlots.default_priority(SpellAudio.effect_name(spell.id))
		== AudioSlots.PRIO_NORMAL, "der Effektsound ist gewöhnlich")
