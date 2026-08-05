extends TestBase

## Phase 10i, part 2: a FIGHTING enemy shaman breaks the sermon. Original
## Populous rule, and the answer to the preacher dominance the balance lab
## measured — 20 preachers convert 20 equally-trained warriors without a single
## loss. She has to be IN a fight; merely standing next to the preacher changes
## nothing, so the dominance stands wherever she is not.
##
## World setup follows tests/test_conversion_targeting.gd.

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
	um.building_manager = bm
	return {"td": td, "nav": nav, "um": um, "bm": bm, "tm": tm, "wpm": wpm,
		"t0": t0, "t1": t1}


func _free_world(w: Dictionary) -> void:
	w.tm.free()
	w.wpm.free()
	w.bm.free()
	w.um.free()


## Tribe 1's shaman at `at`, registered on the tribe (that pointer is what the
## disturbance check walks).
func _enemy_shaman(w: Dictionary, at: Vector3) -> Unit:
	var sh: Unit = w.um.spawn_unit(SHAMAN_SCENE, 1, at)
	w.t1.shaman = sh
	return sh


## Puts the shaman into a real fight: she is striking a victim of her own.
func _make_her_fight(w: Dictionary, sh: Unit) -> void:
	var prey: Unit = w.um.spawn_unit(BRAVE_SCENE, 0, sh.position + Vector3(0.6, 0, 0))
	prey.max_health = 100000
	prey.health = 100000
	sh.order_attack(prey)
	sh._begin_attack(prey)


func test_fighting_enemy_shaman_breaks_a_running_conversion() -> void:
	var w: Dictionary = _make_world()
	var preacher: Unit = w.um.spawn_unit(PREACHER_SCENE, 0, Vector3(50, 5, 50))
	var victim: Unit = w.um.spawn_unit(BRAVE_SCENE, 1, Vector3(51, 5, 50))
	check(victim.begin_conversion(preacher, 9.0), "the conversion started")
	preacher._set_state(Unit.State.CAST)
	victim.tick(0.1)
	check(victim.state == Unit.State.SIT, "and runs while nobody disturbs it")
	check(victim.conversion_progress > 0.0, "progress is accumulating")

	var sh: Unit = _enemy_shaman(w, Vector3(52, 5, 50))
	_make_her_fight(w, sh)
	victim.tick(0.1)
	check(victim.state != Unit.State.SIT, "the fighting shaman breaks the trance")
	check(victim.conversion_progress == 0.0, "and the progress is lost")
	_free_world(w)


## THE case from the spec: she attacks preacher A, and preacher B cannot carry on
## either — the disturbance hits every preacher in her radius.
func test_disturbance_hits_every_preacher_in_range() -> void:
	var w: Dictionary = _make_world()
	var sh: Unit = _enemy_shaman(w, Vector3(50, 5, 50))
	var preacher_a: Unit = w.um.spawn_unit(PREACHER_SCENE, 0, Vector3(51, 5, 50))
	var preacher_b: Unit = w.um.spawn_unit(PREACHER_SCENE, 0, Vector3(53, 5, 50))
	var victim_a: Unit = w.um.spawn_unit(BRAVE_SCENE, 1, Vector3(51.5, 5, 50))
	var victim_b: Unit = w.um.spawn_unit(BRAVE_SCENE, 1, Vector3(53.5, 5, 50))
	check(victim_a.begin_conversion(preacher_a, 9.0), "A is converting")
	check(victim_b.begin_conversion(preacher_b, 9.0), "B is converting")
	preacher_a._set_state(Unit.State.CAST)
	preacher_b._set_state(Unit.State.CAST)

	# She attacks preacher A only.
	sh.order_attack(preacher_a)
	sh._begin_attack(preacher_a)
	victim_a.tick(0.1)
	victim_b.tick(0.1)
	check(victim_a.state != Unit.State.SIT, "the attacked preacher's sermon breaks")
	check(victim_b.state != Unit.State.SIT,
		"and the OTHER preacher in her radius cannot carry on either")
	_free_world(w)


func test_conversion_cannot_start_inside_the_disturb_range() -> void:
	var w: Dictionary = _make_world()
	var sh: Unit = _enemy_shaman(w, Vector3(50, 5, 50))
	_make_her_fight(w, sh)
	var preacher: Unit = w.um.spawn_unit(PREACHER_SCENE, 0, Vector3(52, 5, 50))
	var victim: Unit = w.um.spawn_unit(BRAVE_SCENE, 1, Vector3(52.5, 5, 50))
	check(not victim.begin_conversion(preacher, 9.0),
		"no new conversion starts while she fights nearby")
	check(victim.state != Unit.State.SIT, "the victim stays on its feet")
	_free_world(w)


func test_idle_enemy_shaman_does_not_disturb() -> void:
	var w: Dictionary = _make_world()
	var sh: Unit = _enemy_shaman(w, Vector3(50, 5, 50))
	check(sh.state != Unit.State.ATTACK, "she is not fighting")
	var preacher: Unit = w.um.spawn_unit(PREACHER_SCENE, 0, Vector3(51, 5, 50))
	var victim: Unit = w.um.spawn_unit(BRAVE_SCENE, 1, Vector3(51.5, 5, 50))
	check(victim.begin_conversion(preacher, 9.0),
		"a shaman merely STANDING there changes nothing")
	preacher._set_state(Unit.State.CAST)
	victim.tick(0.1)
	check(victim.state == Unit.State.SIT, "and the sermon runs on")
	check(victim.conversion_progress > 0.0, "progress accumulates")
	_free_world(w)


## She counts as fighting when somebody is meleeing HER, too — not just when she
## is the one striking.
func test_shaman_under_attack_also_disturbs() -> void:
	var w: Dictionary = _make_world()
	var sh: Unit = _enemy_shaman(w, Vector3(50, 5, 50))
	var attacker: Unit = w.um.spawn_unit(WARRIOR_SCENE, 0, Vector3(50.6, 5, 50))
	attacker._begin_attack(sh)
	check(not sh.melee_attackers.is_empty(), "somebody is meleeing her")
	var preacher: Unit = w.um.spawn_unit(PREACHER_SCENE, 0, Vector3(52, 5, 50))
	var victim: Unit = w.um.spawn_unit(BRAVE_SCENE, 1, Vector3(52.5, 5, 50))
	check(not victim.begin_conversion(preacher, 9.0),
		"a shaman being attacked disturbs just as much")
	_free_world(w)


func test_own_shaman_never_disturbs() -> void:
	var w: Dictionary = _make_world()
	# Tribe 0's own shaman, in a fight, right next to her own preacher.
	var sh: Unit = w.um.spawn_unit(SHAMAN_SCENE, 0, Vector3(50, 5, 50))
	w.t0.shaman = sh
	var prey: Unit = w.um.spawn_unit(BRAVE_SCENE, 1, Vector3(50.6, 5, 50))
	prey.max_health = 100000
	prey.health = 100000
	sh._begin_attack(prey)
	var preacher: Unit = w.um.spawn_unit(PREACHER_SCENE, 0, Vector3(51, 5, 50))
	var victim: Unit = w.um.spawn_unit(BRAVE_SCENE, 1, Vector3(51.5, 5, 50))
	check(victim.begin_conversion(preacher, 9.0),
		"your OWN fighting shaman does not break your sermon")
	_free_world(w)


func test_shaman_outside_the_range_does_not_disturb() -> void:
	var w: Dictionary = _make_world()
	var preacher: Unit = w.um.spawn_unit(PREACHER_SCENE, 0, Vector3(50, 5, 50))
	var victim: Unit = w.um.spawn_unit(BRAVE_SCENE, 1, Vector3(50.5, 5, 50))
	# Just beyond the radius, measured from the PREACHER.
	var sh: Unit = _enemy_shaman(w,
		Vector3(50.0 + Balance.PREACHER_SHAMAN_DISTURB_RANGE + 0.5, 5, 50))
	_make_her_fight(w, sh)
	check(victim.begin_conversion(preacher, 9.0),
		"a fight just outside the radius does not reach the sermon")
	preacher._set_state(Unit.State.CAST)
	victim.tick(0.1)
	check(victim.state == Unit.State.SIT, "the conversion keeps running")
	# One metre closer and it does reach.
	sh.position = Vector3(50.0 + Balance.PREACHER_SHAMAN_DISTURB_RANGE - 0.5, 5, 50)
	sh._sync_soa_pos()
	victim.tick(0.1)
	check(victim.state != Unit.State.SIT, "inside the radius it breaks")
	_free_world(w)


## Tower and deck preachers channel through the same two hooks on the VICTIM, so
## they are covered by construction — this pins it.
func test_tower_and_deck_preachers_are_disturbed_too() -> void:
	var w: Dictionary = _make_world()
	var preacher: Unit = w.um.spawn_unit(PREACHER_SCENE, 0, Vector3(50, 5, 50))
	var victim: Unit = w.um.spawn_unit(BRAVE_SCENE, 1, Vector3(51, 5, 50))
	check(victim.begin_conversion(preacher, 9.0), "the conversion started")
	# Stationed channeling (tower platform / airship deck).
	preacher._set_state(Unit.State.GARRISON)
	preacher.station_channeling = true
	victim.tick(0.1)
	check(victim.state == Unit.State.SIT, "a stationed preacher channels normally")
	var sh: Unit = _enemy_shaman(w, Vector3(52, 5, 50))
	_make_her_fight(w, sh)
	victim.tick(0.1)
	check(victim.state != Unit.State.SIT,
		"and is disturbed by the fighting shaman just the same")
	_free_world(w)


## The preacher must not keep standing in CAST over victims that stood up.
func test_disturbed_preacher_leaves_the_cast_state() -> void:
	var w: Dictionary = _make_world()
	var preacher: Preacher = w.um.spawn_unit(PREACHER_SCENE, 0, Vector3(50, 5, 50)) as Preacher
	var victim: Unit = w.um.spawn_unit(BRAVE_SCENE, 1, Vector3(51, 5, 50))
	check(victim.begin_conversion(preacher, 9.0), "the conversion started")
	preacher._set_state(Unit.State.CAST)
	var sh: Unit = _enemy_shaman(w, Vector3(52, 5, 50))
	_make_her_fight(w, sh)
	preacher._refresh_conversion()
	check(preacher.state != Unit.State.CAST,
		"a disturbed preacher stops channelling instead of standing there")
	_free_world(w)
