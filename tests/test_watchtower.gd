extends TestBase

## Headless tests for phase 7h: the watchtower (Wachturm). Two crew slots for
## combat units / the shaman (never braves); ranged crew fight from the tower
## with +3 m range; crew are a protected reserve (no fireball/conversion target)
## until ejected by a storm, ranged stage-1 fire (killed) or a disabling spell.

const TICK: float = 0.1
const MAX_TICKS: int = 1500

const TOWER_SCENE: PackedScene = preload("res://scenes/buildings/watchtower.tscn")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")
const PREACHER_SCENE: PackedScene = preload("res://scenes/units/preacher.tscn")
const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")


## Minimal spell that always releases (for the shaman cast-range test).
class StubSpell extends Spell:
	func execute(_tribe: Tribe, _target: Vector3, _ctx: SpellContext) -> bool:
		return true


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


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


func _tower(w: Dictionary, tribe: Tribe) -> Watchtower:
	return w.bm.place(TOWER_SCENE, tribe, Vector2i(30, 30), 0, true) as Watchtower


# --- Crew capacity & eligibility --------------------------------------------

func test_crew_capacity_and_eligibility() -> void:
	var w: Dictionary = _make_world()
	var tower: Watchtower = _tower(w, w.tribe0)
	var warrior: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, Vector3(31, 0, 33))
	var fire: Unit = w.unit_manager.spawn_unit(FIREWARRIOR_SCENE, 0, Vector3(32, 0, 33))
	var warrior2: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, Vector3(33, 0, 33))
	var brave: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 0, Vector3(34, 0, 33))
	var pop_before: int = w.tribe0.population()
	check(tower.admit_crew(warrior), "warrior admitted")
	check(tower.admit_crew(fire), "firewarrior admitted (2/2)")
	check(tower.crew_count() == 2, "tower full at 2 crew")
	check(not tower.admit_crew(warrior2), "third crew member rejected (full)")
	check(not tower.admit_crew(brave), "brave rejected (not crew-eligible)")
	check(warrior.garrison_housed and fire.garrison_housed, "admitted crew is housed")
	check(not warrior.is_targetable() and not fire.is_targetable(),
		"housed crew is a protected reserve (non-targetable)")
	check(warrior.position.y > tower.center_world().y + 3.0,
		"crew stands visibly up on the platform")
	check(w.tribe0.population() == pop_before, "population unchanged while garrisoned")
	# Eject: both step out alive, back in the world; population still constant.
	tower.eject_occupants(false)
	check(tower.crew.is_empty(), "crew empty after eject")
	check(warrior in w.unit_manager.units and fire in w.unit_manager.units,
		"ejected crew back in the world")
	check(warrior.state != Unit.State.DEAD and fire.state != Unit.State.DEAD,
		"ejected crew alive")
	check(warrior.is_targetable() and fire.is_targetable(),
		"ejected crew is targetable again")
	check(not warrior.garrison_housed and warrior.garrison_target == null,
		"ejected crew no longer housed")
	check(w.tribe0.population() == pop_before, "population constant across garrison in/out")
	_free_world(w)


## Shift+right-click after a waypoint route: the unit walks its waypoints FIRST
## and only then garrisons — the follow-up order must not be executed early.
func test_queued_garrison_runs_after_route() -> void:
	var w: Dictionary = _make_world()
	var tower: Watchtower = _tower(w, w.tribe0)   # footprint at (30,30)
	var fire: Unit = w.unit_manager.spawn_unit(FIREWARRIOR_SCENE, 0, Vector3(10, 0, 10))
	fire.order_move(Vector3(12, 0, 12))          # start the route
	fire.order_move(Vector3(14, 0, 16), true)    # queued waypoint
	# Arm the follow-up (as the SelectionManager does on Shift+right-click).
	fire.route_end_action = (func(u: Unit) -> void: u.order_garrison(tower)).bind(fire)
	# One tick in: still walking, NOT garrisoning yet.
	fire.tick(TICK)
	w.unit_manager.tick(TICK)
	check(fire.garrison_target == null and not fire.garrison_housed,
		"does not garrison while still walking the waypoint route")
	check(fire.state == Unit.State.MOVE, "walks the route first")
	# Runs to completion: garrisons only after the route is done.
	var housed: int = _run(w, [fire], func() -> bool: return fire.garrison_housed)
	check(housed < MAX_TICKS, "garrisons the tower after finishing the waypoints")
	check(fire in tower.crew, "firewarrior ends up as tower crew")
	_free_world(w)


func test_sidebar_eject_single_crew() -> void:
	var w: Dictionary = _make_world()
	var tower: Watchtower = _tower(w, w.tribe0)
	var warrior: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, Vector3(31, 0, 33))
	var fire: Unit = w.unit_manager.spawn_unit(FIREWARRIOR_SCENE, 0, Vector3(32, 0, 33))
	tower.admit_crew(warrior)
	tower.admit_crew(fire)
	check(tower.crew.size() == 2, "two crew garrisoned")
	# Eject only slot 0 (the sidebar per-slot eject) — the other stays inside.
	tower.eject_crew(0)
	check(tower.crew.size() == 1, "one crew member ejected, one remains")
	check(warrior.state != Unit.State.DEAD and warrior.is_targetable() \
		and not warrior.garrison_housed, "ejected crew is alive, targetable, not housed")
	check(fire in tower.crew and fire.garrison_housed, "the other crew member stays garrisoned")
	_free_world(w)


func test_order_garrison_full_flow() -> void:
	var w: Dictionary = _make_world()
	var tower: Watchtower = _tower(w, w.tribe0)
	var fire: Unit = w.unit_manager.spawn_unit(FIREWARRIOR_SCENE, 0, Vector3(30, 0, 40))
	fire.order_garrison(tower)
	check(fire.state == Unit.State.GARRISON, "firewarrior walks to garrison the tower")
	var housed: int = _run(w, [fire], func() -> bool: return fire.garrison_housed)
	check(housed < MAX_TICKS, "firewarrior reaches the tower and is admitted")
	check(fire in tower.crew, "firewarrior is now tower crew")
	check(not fire.is_targetable(), "housed crew is a protected reserve")
	check(fire.position.y > tower.center_world().y + 3.0, "crew stands on the platform")
	_free_world(w)


# --- Range bonus: firewarrior ------------------------------------------------

func test_firewarrior_fires_within_range_bonus() -> void:
	var w: Dictionary = _make_world()
	var tower: Watchtower = _tower(w, w.tribe0)
	var fire: Unit = w.unit_manager.spawn_unit(FIREWARRIOR_SCENE, 0, Vector3(31, 0, 32))
	tower.admit_crew(fire)
	# Tower centre is (31,31). FIRE_RANGE (7) + 3 = 10: a target at dist 9 is hit.
	var target: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, Vector3(40, 0, 31))
	var hp: int = target.health
	_run(w, [], func() -> bool: return target.health < hp)
	check(target.health < hp, "tower firewarrior hits a target within FIRE_RANGE + 3")
	_free_world(w)


func test_firewarrior_holds_fire_beyond_range_bonus() -> void:
	var w: Dictionary = _make_world()
	var tower: Watchtower = _tower(w, w.tribe0)
	var fire: Unit = w.unit_manager.spawn_unit(FIREWARRIOR_SCENE, 0, Vector3(31, 0, 32))
	tower.admit_crew(fire)
	# Target at dist 12 > FIRE_RANGE + 3 (10): out of reach, never fired at.
	var target: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, Vector3(43, 0, 31))
	var hp: int = target.health
	for i in range(60):
		w.unit_manager.tick(TICK)
		w.bm.tick(TICK)
	check(target.health == hp, "no fire on a target beyond FIRE_RANGE + 3")
	_free_world(w)


func test_crew_fires_at_base_and_stays_pinned() -> void:
	var w: Dictionary = _make_world()
	var tower: Watchtower = _tower(w, w.tribe0)
	var fire: Unit = w.unit_manager.spawn_unit(FIREWARRIOR_SCENE, 0, Vector3(31, 0, 32))
	tower.admit_crew(fire)
	var slot: Vector3 = fire.position
	# An enemy right at the tower foot: the crew fireballs it (no melee), and the
	# firewarrior does not leave its platform slot.
	var foe: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, Vector3(33, 0, 31))
	var hp: int = foe.health
	_run(w, [], func() -> bool: return foe.health < hp)
	check(foe.health < hp, "tower firewarrior fireballs an enemy at the tower base")
	check(fire.position == slot, "the firewarrior does not move while firing")
	_free_world(w)


# --- Range bonus: warrior does NOTHING ---------------------------------------

func test_warrior_in_tower_never_attacks() -> void:
	var w: Dictionary = _make_world()
	var tower: Watchtower = _tower(w, w.tribe0)
	var warrior: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, Vector3(31, 0, 32))
	tower.admit_crew(warrior)
	# Enemy right at the tower foot: a warrior crew member must not act.
	var foe: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, Vector3(32, 0, 31))
	var hp: int = foe.health
	for i in range(60):
		w.unit_manager.tick(TICK)
		w.bm.tick(TICK)
	check(foe.health == hp, "a garrisoned warrior deals no damage (protected reserve only)")
	_free_world(w)


# --- Range bonus: preacher ---------------------------------------------------

func test_preacher_converts_within_range_bonus() -> void:
	var w: Dictionary = _make_world()
	var tower: Watchtower = _tower(w, w.tribe0)
	var preacher: Unit = w.unit_manager.spawn_unit(PREACHER_SCENE, 0, Vector3(31, 0, 32))
	tower.admit_crew(preacher)
	# CONVERT_RANGE (5) + 3 = 8: a brave at dist 7 gets converted to tribe 0.
	var brave: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, Vector3(38, 0, 31))
	var converted: int = _run(w, [brave], func() -> bool: return brave.tribe_id == 0)
	check(converted < MAX_TICKS, "tower preacher converts an enemy within CONVERT_RANGE + 3")
	check(brave.tribe_id == 0, "the brave now belongs to the tower's tribe")
	_free_world(w)


## The tower preacher channels via the standard begin_conversion/SIT path:
## the target visibly SITS DOWN first (user bug report: nobody ever sat),
## and ejecting the preacher mid-channel breaks the trance — the target
## stands back up unconverted.
func test_tower_preacher_sit_then_eject_breaks_trance() -> void:
	var w: Dictionary = _make_world()
	var tower: Watchtower = _tower(w, w.tribe0)
	var preacher: Unit = w.unit_manager.spawn_unit(PREACHER_SCENE, 0, Vector3(31, 0, 32))
	tower.admit_crew(preacher)
	var brave: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, Vector3(38, 0, 31))
	var sat: int = _run(w, [brave],
		func() -> bool: return brave.state == Unit.State.SIT)
	check(sat < MAX_TICKS, "the target sits down under the tower preacher (SIT)")
	check(brave.converting_preacher == preacher, "pacified by the tower preacher")
	check(preacher.station_channeling, "the stationed preacher is channeling")
	# Eject the preacher mid-channel (only the brave keeps ticking, so the
	# ejected preacher cannot re-convert from the ground).
	tower.eject_occupants(false)
	check(not preacher.station_channeling, "the eject drops the channel flag")
	for i in range(20):
		brave.tick(TICK)
		w.unit_manager.tick(TICK)
		w.bm.tick(TICK)
	check(brave.tribe_id == 1, "no conversion happened (channel was broken)")
	check(brave.state != Unit.State.SIT, "the target stood back up after the eject")
	_free_world(w)


## The tower preacher chants while converting (Spieltest 5: it was silent). The
## audio itself needs the scene tree, so headless we assert the throttled chant
## PATH ran — the preacher's preach-sound timer is armed once channeling starts.
func test_tower_preacher_chants_while_converting() -> void:
	var w: Dictionary = _make_world()
	var tower: Watchtower = _tower(w, w.tribe0)
	var preacher: Preacher = w.unit_manager.spawn_unit(
		PREACHER_SCENE, 0, Vector3(31, 0, 32)) as Preacher
	tower.admit_crew(preacher)
	check(preacher._preach_sound_timer == 0.0, "chant timer starts unarmed")
	var brave: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, Vector3(37, 0, 31))
	var sat: int = _run(w, [brave],
		func() -> bool: return brave.state == Unit.State.SIT)
	check(sat < MAX_TICKS, "the tower preacher engages a target")
	check(preacher._preach_sound_timer > 0.0,
		"the chant (sound) path runs while the tower preacher channels")
	_free_world(w)


# --- Range bonus: shaman casts from the tower --------------------------------

func test_shaman_casts_from_tower_with_range_bonus() -> void:
	var w: Dictionary = _make_world()
	var tower: Watchtower = _tower(w, w.tribe0)
	var shaman: Unit = w.unit_manager.spawn_unit(SHAMAN_SCENE, 0, Vector3(31, 0, 32))
	tower.admit_crew(shaman)
	check(shaman.garrison_housed, "shaman garrisoned")
	var spell: StubSpell = StubSpell.new()
	spell.cast_range = 9.0
	spell.charges = 1
	# Tower centre (31,31); cast_range + 3 = 12. A target at dist 11 succeeds.
	var ok: bool = (shaman as Shaman).order_cast(spell, Vector3(42, 5, 31), null)
	check(ok, "shaman casts at cast_range + 3 from the tower")
	check(spell.charges == 0, "the charge was consumed on the successful cast")
	check(shaman.garrison_housed and shaman in tower.crew,
		"shaman never leaves the tower to cast")
	# A target beyond cast_range + 3 (dist 13) fails without spending a charge.
	spell.charges = 1
	var far: bool = (shaman as Shaman).order_cast(spell, Vector3(44, 5, 31), null)
	check(not far, "cast beyond cast_range + 3 fails")
	check(spell.charges == 1, "a failed cast keeps the charge")
	check(shaman in tower.crew, "shaman still stationed after an out-of-range cast")
	_free_world(w)


# --- Crew protection ---------------------------------------------------------

func test_garrisoned_crew_is_protected() -> void:
	var w: Dictionary = _make_world()
	var tower: Watchtower = _tower(w, w.tribe0)
	var fire: Unit = w.unit_manager.spawn_unit(FIREWARRIOR_SCENE, 0, Vector3(31, 0, 32))
	tower.admit_crew(fire)
	# The crew is visible but a protected reserve: an enemy scan cannot target it.
	var enemy: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 1, Vector3(31, 0, 33))
	check(not fire.is_targetable(), "garrisoned crew is non-targetable")
	check(enemy._scan_for_enemy(30.0) == null,
		"garrisoned crew is not a valid target (fireball/melee scan misses it)")
	check(not fire.begin_conversion(enemy, 1.0), "garrisoned crew cannot be converted")
	# After a storm eject it is targetable again.
	tower.begin_storm()
	check(fire in w.unit_manager.units, "ejected crew back in the world")
	check(fire.is_targetable(), "ejected crew is targetable again")
	check(enemy._scan_for_enemy(30.0) == fire, "ejected crew is targetable again")
	_free_world(w)


# --- 7g integration ----------------------------------------------------------

func test_tower_raider_cap_is_five() -> void:
	var w: Dictionary = _make_world()
	var tower: Watchtower = _tower(w, w.tribe1)
	check(tower.max_melee_raiders() == 5, "watchtower caps melee raiders at 5")
	var admitted: int = 0
	for i in range(8):
		var r: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, Vector3(31 + i, 0, 34))
		if tower.admit_raider(r):
			admitted += 1
	check(admitted == 5, "only 5 raiders fit (vs. 15 for a hut)")
	check(tower.raiders.size() == 5, "5 raiders inside the tower")
	_free_world(w)


func test_storm_ejects_crew_alive() -> void:
	var w: Dictionary = _make_world()
	var tower: Watchtower = _tower(w, w.tribe1)
	var warrior: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 1, Vector3(31, 0, 32))
	var fire: Unit = w.unit_manager.spawn_unit(FIREWARRIOR_SCENE, 1, Vector3(32, 0, 32))
	tower.admit_crew(warrior)
	tower.admit_crew(fire)
	check(tower.has_occupants(), "crew counts as storm occupants")
	tower.begin_storm()
	check(tower.crew.is_empty(), "storm throws the crew out")
	check(warrior.state != Unit.State.DEAD and fire.state != Unit.State.DEAD,
		"crew ejected ALIVE by the storm")
	check(warrior in w.unit_manager.units and fire in w.unit_manager.units,
		"ejected crew back in the world")
	_free_world(w)


func test_ranged_stage1_hurts_crew() -> void:
	var w: Dictionary = _make_world()
	var tower: Watchtower = _tower(w, w.tribe1)
	var warrior: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 1, Vector3(31, 0, 32))
	var fire: Unit = w.unit_manager.spawn_unit(FIREWARRIOR_SCENE, 1, Vector3(32, 0, 32))
	tower.admit_crew(warrior)
	tower.admit_crew(fire)
	var pop_before: int = w.tribe1.population()
	# 30% of 200 HP = 60 damage via RANGED fire crosses into stage 1.
	tower.take_damage(60, Building.DMG_RANGED)
	check(tower.destruction_stage() == 1, "tower at stage 1")
	check(tower.crew.is_empty(), "crew ejected")
	check(warrior.state == Unit.State.ROLL and fire.state == Unit.State.ROLL,
		"ranged stage-1 fire hurls the crew into a tumble")
	var ticks: int = 0
	while ticks < 100 \
			and (warrior.state == Unit.State.ROLL or fire.state == Unit.State.ROLL):
		if warrior.state == Unit.State.ROLL:
			warrior.tick(TICK)
		if fire.state == Unit.State.ROLL:
			fire.tick(TICK)
		ticks += 1
	# 65-HP firewarrior now SURVIVES the 60-damage eject (hurt); the warrior
	# (120) survives too — no tower crew is weak enough to die from it anymore.
	check(fire.state != Unit.State.DEAD
			and fire.health <= fire.max_health - Building.EJECT_RANGED_DAMAGE,
		"the firewarrior survives the eject, hurt by one brave life")
	check(warrior.state != Unit.State.DEAD
			and warrior.health <= warrior.max_health - Building.EJECT_RANGED_DAMAGE,
		"the tougher warrior survives the eject, hurt by one brave life")
	check(w.tribe1.population() == pop_before,
		"no crew died — population unchanged")
	_free_world(w)


func test_spell_stage1_ejects_crew_alive() -> void:
	var w: Dictionary = _make_world()
	var tower: Watchtower = _tower(w, w.tribe1)
	var warrior: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 1, Vector3(31, 0, 32))
	tower.admit_crew(warrior)
	# Generic (spell) damage crossing stage 1 keeps the living eject.
	tower.take_damage(60, Building.DMG_GENERIC)
	check(tower.destruction_stage() == 1, "tower at stage 1")
	check(tower.crew.is_empty(), "crew ejected")
	check(warrior.state != Unit.State.DEAD and warrior in w.unit_manager.units,
		"a disabling spell ejects the crew ALIVE")
	_free_world(w)


# --- Cost & placement --------------------------------------------------------

func test_cost_and_footprint() -> void:
	var w: Dictionary = _make_world()
	check(Watchtower.WOOD_COST == 4, "watchtower costs 4 wood")
	var site: Building = w.bm.place(TOWER_SCENE, w.tribe0, Vector2i(30, 30), 0, false)
	check(site != null and site.wood_cost == 4, "placed via the build pipeline at 4 wood")
	check(site.footprint == Vector2i(2, 2), "2x2 footprint")
	check(not w.nav.is_cell_walkable(Vector2i(30, 30)), "footprint blocks the NavGrid")
	check(not w.nav.is_cell_walkable(Vector2i(31, 31)), "whole footprint solid")
	_free_world(w)


# --- Preacher assaults a tower: melee, don't try to convert the housed crew --

## A preacher assaulting a garrisoned watchtower tears it down in melee — its
## crew can't be converted while housed, so the door defender is fought, not
## pacified.
func test_preacher_melees_watchtower_defender() -> void:
	var w: Dictionary = _make_world()
	var tower: Watchtower = _tower(w, w.tribe1)
	var preacher: Preacher = w.unit_manager.spawn_unit(
		PREACHER_SCENE, 0, Vector3(31, 5, 33)) as Preacher
	var foe: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 1, Vector3(31, 5, 34))
	preacher.attack_building = tower
	preacher._engage_assault_foe(foe)
	check(preacher.state == Unit.State.ATTACK,
		"the preacher melees the tower defender instead of converting it")
	_free_world(w)


## Control: assaulting a NON-tower building still converts its (ejected) defender.
func test_preacher_converts_non_tower_defender() -> void:
	var w: Dictionary = _make_world()
	var hut: Building = w.bm.place(HUT_SCENE, w.tribe1, Vector2i(30, 30), 0, true) as Building
	var preacher: Preacher = w.unit_manager.spawn_unit(
		PREACHER_SCENE, 0, Vector3(34, 5, 33)) as Preacher
	var foe: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 1, Vector3(34, 5, 34))
	preacher.attack_building = hut
	preacher._engage_assault_foe(foe)
	check(preacher.state == Unit.State.CAST,
		"a non-tower building's defender is still converted")
	_free_world(w)


# --- Assault on a MANNED tower (bugfix 2026-07-18) -----------------------------

## The garrisoned crew is a protected reserve INSIDE the tower — it must not
## count as an entrance threat: attackers can neither engage it (_begin_attack
## refuses non-targetable units) nor would they ever approach, dead-locking
## every melee/preacher assault on a manned tower (user bug report).
func test_manned_tower_crew_is_no_entrance_threat() -> void:
	var w: Dictionary = _make_world()
	var tower: Watchtower = _tower(w, w.tribe1)
	tower.admit_crew(w.unit_manager.spawn_unit(WARRIOR_SCENE, 1, Vector3(31, 5, 33)))
	check(tower.crew_count() == 1, "tower is manned")
	check(not tower.has_entrance_threat(),
		"housed crew does not count as an entrance threat")
	_free_world(w)


## Symptom check: a preacher ordered onto a manned enemy tower must actually
## walk toward it (the bug left it standing in place with a walk animation).
func test_preacher_approaches_manned_tower() -> void:
	var w: Dictionary = _make_world()
	var tower: Watchtower = _tower(w, w.tribe1)
	tower.admit_crew(w.unit_manager.spawn_unit(WARRIOR_SCENE, 1, Vector3(31, 5, 33)))
	var preacher: Preacher = w.unit_manager.spawn_unit(
		PREACHER_SCENE, 0, Vector3(20, 5, 20)) as Preacher
	preacher.order_attack_building(tower)
	var start: Vector3 = preacher.position
	for i in range(80):
		preacher.tick(TICK)
		w.unit_manager.tick(TICK)
		w.bm.tick(TICK)
	var moved: float = Vector2(preacher.position.x - start.x,
		preacher.position.z - start.z).length()
	check(moved > 2.0, "preacher approaches the manned tower (moved %.1f m)" % moved)
	_free_world(w)


## Full pipeline: ordered warriors approach the manned enemy tower, the storm
## throws the crew out, the doorway is fought clear and the tower is razed.
func test_ordered_warriors_raze_manned_tower() -> void:
	var w: Dictionary = _make_world()
	var tower: Watchtower = _tower(w, w.tribe1)
	var crew: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 1, Vector3(31, 5, 33))
	tower.admit_crew(crew)
	var squad: Array[Unit] = []
	for i in range(4):
		var wr: Unit = w.unit_manager.spawn_unit(WARRIOR_SCENE, 0, Vector3(24 + i, 5, 24))
		wr.order_attack_building(tower)
		squad.append(wr)
	var all_units: Array = squad + [crew]
	var razed: int = _run(w, all_units, func() -> bool: return tower.health <= 0)
	check(razed < MAX_TICKS, "ordered warriors raze the manned watchtower")
	check(tower not in w.bm.buildings, "razed tower deregistered")
	_free_world(w)
