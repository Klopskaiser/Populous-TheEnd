extends TestBase

## Headless tests for phase 7g: units destroy enemy buildings by storming the
## entrance (melee raiders demolish from inside, occupants ejected) or by
## firewarrior bombardment (half the melee DPS; stage-1 fire kills the
## occupants). Buildings are always the LOWEST-priority target.

const TICK: float = 0.1
const MAX_TICKS: int = 1500

const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const WARRIOR_CAMP_SCENE: PackedScene = preload("res://scenes/buildings/warrior_camp.tscn")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


## World with an owning tribe (0) and an enemy tribe (1), unit + building
## managers wired up (building_manager set so unit building-scans work).
func _make_world() -> Dictionary:
	var td: TerrainData = _flat_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var tribe0: Tribe = Tribe.new(0)
	var tribe1: Tribe = Tribe.new(1)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe0, tribe1] as Array[Tribe], null, wpm)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um, wpm)
	um.building_manager = bm
	return {"td": td, "nav": nav, "tribe0": tribe0, "tribe1": tribe1,
		"unit_manager": um, "bm": bm, "wpm": wpm}


func _free_world(w: Dictionary) -> void:
	w.bm.free()
	w.unit_manager.free()
	w.wpm.free()


func _run(w: Dictionary, units: Array, done: Callable) -> int:
	for i in range(MAX_TICKS):
		if done.call():
			return i
		for u in units:
			if is_instance_valid(u) and u.state != Unit.State.DEAD:
				u.tick(TICK)
		w.unit_manager.tick(TICK)
		w.bm.tick(TICK)
	return MAX_TICKS


# --- Raider slots & demolition scaling ---------------------------------------

func test_raider_cap_and_wait() -> void:
	var w: Dictionary = _make_world()
	var hut: Building = w.bm.place(HUT_SCENE, w.tribe1, Vector2i(30, 30), 0, true)
	var raiders: Array[Unit] = []
	for i in range(20):
		raiders.append(w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, Vector3(20 + i, 0, 20)))
	var admitted: int = 0
	for r in raiders:
		if hut.admit_raider(r):
			admitted += 1
	check(admitted == Building.MAX_MELEE_RAIDERS, "exactly 15 raiders admitted (cap)")
	check(hut.raiders.size() == 15, "15 raiders inside")
	var inside: int = 0
	var outside: int = 0
	for r in raiders:
		if r.state == Unit.State.RAID:
			inside += 1
		else:
			outside += 1
	check(inside == 15, "15 raiders in RAID state (removed from the world)")
	check(outside == 5, "5 overflow raiders stay out")
	check(w.unit_manager.get_units_in_radius(Vector3(20, 0, 20), 60).size() == 5,
		"only the 5 overflow raiders remain in the live world")
	_free_world(w)


func test_demolition_scales_with_raider_count() -> void:
	var w: Dictionary = _make_world()
	var hut_a: Building = w.bm.place(HUT_SCENE, w.tribe1, Vector2i(30, 30), 0, true)
	var hut_b: Building = w.bm.place(HUT_SCENE, w.tribe1, Vector2i(50, 50), 0, true)
	for i in range(3):
		hut_a.admit_raider(w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, Vector3(31 + i, 0, 31)))
	for i in range(6):
		hut_b.admit_raider(w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, Vector3(51 + i, 0, 51)))
	w.bm.tick(1.0)
	var dmg_a: int = hut_a.max_health - hut_a.health
	var dmg_b: int = hut_b.max_health - hut_b.health
	check(dmg_a == 18, "3 raiders deal 3*6 = 18 HP/s")
	check(dmg_b == 36, "6 raiders deal 6*6 = 36 HP/s")
	check(dmg_b == dmg_a * 2, "2x raiders => 2x demolition damage")
	_free_world(w)


func test_demolition_destroys_and_releases_raiders() -> void:
	var w: Dictionary = _make_world()
	var hut: Building = w.bm.place(HUT_SCENE, w.tribe1, Vector2i(30, 30), 0, true)
	var raiders: Array[Unit] = []
	for i in range(5):
		var r: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, Vector3(31 + i, 0, 31))
		raiders.append(r)
		hut.admit_raider(r)
	check(not w.nav.is_cell_walkable(Vector2i(31, 31)), "footprint blocked while standing")
	var ticks: int = _run(w, [], func() -> bool: return hut.health <= 0)
	check(ticks < MAX_TICKS, "5 raiders demolish the hut to rubble")
	check(hut not in w.bm.buildings, "destroyed hut deregistered")
	check(w.nav.is_cell_walkable(Vector2i(31, 31)), "footprint walkable/buildable again")
	for r in raiders:
		check(is_instance_valid(r) and r.state == Unit.State.IDLE,
			"raider steps back out alive and idle")
		check(r.raiding_building == null, "raider no longer inside a building")
		check(r in w.unit_manager.units, "raider re-registered in the world")
	_free_world(w)


# --- Storm ejects occupants --------------------------------------------------

func _camp_with_trainee(w: Dictionary) -> TrainingBuilding:
	var camp: TrainingBuilding = w.bm.place(WARRIOR_CAMP_SCENE, w.tribe0, Vector2i(40, 40), 0, true)
	var b1: Brave = w.unit_manager.spawn_unit(BRAVE_SCENE, 0, Vector3(38, 0, 38))
	b1.order_train(camp)
	_run(w, [b1], func() -> bool: return camp.trainee != null)
	return camp


func test_storm_ejects_trainee_alive() -> void:
	var w: Dictionary = _make_world()
	var camp: TrainingBuilding = _camp_with_trainee(w)
	check(camp.trainee != null, "a brave is being trained inside the camp")
	var trainee: Brave = camp.trainee
	var raider: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 1, Vector3(44, 0, 44))
	var ok: bool = camp.admit_raider(raider)
	check(ok, "raider admitted, storm begins")
	check(camp.trainee == null, "bay cleared as the storm begins")
	check(is_instance_valid(trainee) and trainee.state != Unit.State.DEAD,
		"trainee ejected ALIVE")
	check(trainee.state != Unit.State.TRAIN, "trainee no longer training")
	check(trainee in w.unit_manager.units, "ejected trainee back in the world")
	check(raider in camp.raiders and raider.state == Unit.State.RAID,
		"raider is inside demolishing")
	_free_world(w)


# --- Ranged fire ----------------------------------------------------------------

func test_ranged_stage1_kills_occupants() -> void:
	var w: Dictionary = _make_world()
	var camp: TrainingBuilding = _camp_with_trainee(w)
	var trainee: Brave = camp.trainee
	var pop_before: int = w.tribe0.population()
	# 30% of 400 HP = 120 damage crosses into stage 1 via RANGED fire.
	camp.take_damage(120, Building.DMG_RANGED)
	check(camp.destruction_stage() == 1, "camp at stage 1")
	check(camp.trainee == null, "bay cleared")
	check(is_instance_valid(trainee) and trainee.state == Unit.State.DEAD,
		"ranged stage-1 fire KILLS the trapped occupant")
	check(w.tribe0.population() == pop_before - 1, "population dropped by the dead trainee")
	_free_world(w)


func test_spell_stage1_ejects_occupants_alive() -> void:
	var w: Dictionary = _make_world()
	var camp: TrainingBuilding = _camp_with_trainee(w)
	var trainee: Brave = camp.trainee
	# Generic (spell) damage crossing stage 1 keeps the living eject.
	camp.take_damage(120, Building.DMG_GENERIC)
	check(camp.destruction_stage() == 1, "camp at stage 1")
	check(is_instance_valid(trainee) and trainee.state != Unit.State.DEAD,
		"spell stage-1 damage ejects the occupant ALIVE")
	check(trainee in w.unit_manager.units, "ejected trainee back in the world")
	_free_world(w)


func test_ranged_after_melee_storm_no_double_eject() -> void:
	var w: Dictionary = _make_world()
	var camp: TrainingBuilding = _camp_with_trainee(w)
	var trainee: Brave = camp.trainee
	var raider: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 1, Vector3(44, 0, 44))
	camp.admit_raider(raider)   # storm ejects the trainee alive
	check(camp.trainee == null and trainee.state != Unit.State.DEAD,
		"trainee ejected alive at storm start")
	# Ranged fire now crosses stage 1 — but the occupants are already out, so
	# there is no second (killing) eject.
	camp.take_damage(200, Building.DMG_RANGED)
	check(is_instance_valid(trainee) and trainee.state != Unit.State.DEAD,
		"already-ejected trainee is not killed by the later ranged stage-1 hit")
	_free_world(w)


func test_fireball_damages_building_half_of_melee() -> void:
	var w: Dictionary = _make_world()
	var hut: Building = w.bm.place(HUT_SCENE, w.tribe1, Vector2i(30, 30), 0, true)
	var ball: Fireball = Fireball.new()
	ball.setup_building(null, hut, hut.center_world())
	for i in range(5):
		ball.tick(TICK)
		if ball.done:
			break
	check(hut.max_health - hut.health == Firewarrior.BUILDING_FIRE_DAMAGE,
		"one fireball deals BUILDING_FIRE_DAMAGE to the building")
	# Ranged siege is roughly HALF the melee raid DPS.
	var ranged_dps: float = float(Firewarrior.BUILDING_FIRE_DAMAGE) / Firewarrior.FIRE_COOLDOWN
	var ratio: float = ranged_dps / Building.RAID_DPS_PER_RAIDER
	check(ratio >= 0.4 and ratio <= 0.7, "ranged building DPS is about half the melee DPS")
	ball.free()
	_free_world(w)


# --- Priority: units before buildings, braves ignore buildings ----------------

func test_unit_target_takes_priority_over_building() -> void:
	var w: Dictionary = _make_world()
	w.bm.place(HUT_SCENE, w.tribe1, Vector2i(30, 30), 0, true)
	var warrior: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, Vector3(28, 0, 28))
	var enemy: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 1, Vector3(29, 0, 29))
	warrior._engage_on_sight(0.3)
	check(warrior.attack_target == enemy, "engages the enemy UNIT first")
	check(warrior.attack_building == null, "does not target the building while a unit is near")
	_free_world(w)


func test_lone_building_is_engaged() -> void:
	var w: Dictionary = _make_world()
	var hut: Building = w.bm.place(HUT_SCENE, w.tribe1, Vector2i(30, 30), 0, true)
	var warrior: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, Vector3(29, 0, 29))
	warrior._engage_on_sight(0.3)
	check(warrior.attack_building == hut, "with no enemy unit near, the building is engaged")
	check(warrior.state == Unit.State.ATTACK, "warrior switches to assault the building")
	_free_world(w)


func test_idle_brave_ignores_buildings() -> void:
	var w: Dictionary = _make_world()
	w.bm.place(HUT_SCENE, w.tribe1, Vector2i(30, 30), 0, true)
	var brave: Brave = w.unit_manager.spawn_unit(BRAVE_SCENE, 0, Vector3(29, 0, 29))
	brave.tick(0.3)
	check(brave.attack_building == null, "an idle brave never auto-targets a building")
	check(brave.state == Unit.State.IDLE, "idle brave stays idle next to an enemy building")
	_free_world(w)


# --- Order routing ------------------------------------------------------------

func test_order_attack_building_routes_all_types() -> void:
	var w: Dictionary = _make_world()
	var enemy_hut: Building = w.bm.place(HUT_SCENE, w.tribe1, Vector2i(30, 30), 0, true)
	var own_hut: Building = w.bm.place(HUT_SCENE, w.tribe0, Vector2i(50, 50), 0, true)
	var brave: Brave = w.unit_manager.spawn_unit(BRAVE_SCENE, 0, Vector3(20, 0, 20))
	var warrior: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, Vector3(21, 0, 20))
	var fire: Unit = w.unit_manager.spawn_unit(FIREWARRIOR_SCENE, 0, Vector3(22, 0, 20))
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(w.nav, w.bm, w.unit_manager)
	var sel: Array[Unit] = [brave, warrior, fire]
	tc.order_attack_building(sel, enemy_hut)
	for u in sel:
		check(u.attack_building == enemy_hut and u.state == Unit.State.ATTACK,
			"%s got the enemy building assault order" % u.unit_kind())
	# Own building: rejected.
	tc.order_attack_building(sel, own_hut)
	check(warrior.attack_building == enemy_hut, "own building is not assaulted")
	tc.free()
	_free_world(w)


func test_move_order_cancels_building_assault() -> void:
	var w: Dictionary = _make_world()
	var hut: Building = w.bm.place(HUT_SCENE, w.tribe1, Vector2i(30, 30), 0, true)
	var warrior: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, Vector3(20, 0, 20))
	warrior.order_attack_building(hut)
	check(warrior.attack_building == hut, "warrior ordered to assault the building")
	warrior.order_move(Vector3(10, 0, 10))
	check(warrior.attack_building == null, "a move order breaks off the assault")
	_free_world(w)


# --- Full pipeline: ordered warriors storm and level a building ---------------

func test_ordered_warriors_storm_and_level_building() -> void:
	var w: Dictionary = _make_world()
	var hut: Building = w.bm.place(HUT_SCENE, w.tribe1, Vector2i(40, 40), 0, true)
	var squad: Array[Unit] = []
	for i in range(4):
		var wr: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, Vector3(35 + i, 0, 35))
		wr.order_attack_building(hut)
		squad.append(wr)
	# They path to the entrance, enter as raiders and demolish the hut.
	var entered: int = _run(w, squad, func() -> bool: return not hut.raiders.is_empty())
	check(entered < MAX_TICKS, "at least one warrior entered the building as a raider")
	var razed: int = _run(w, squad, func() -> bool: return hut.health <= 0)
	check(razed < MAX_TICKS, "the storming warriors level the building")
	check(hut not in w.bm.buildings, "razed building deregistered")
	_free_world(w)
