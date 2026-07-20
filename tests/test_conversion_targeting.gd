extends TestBase

## Phase 7i: units being converted (State.SIT) are no legitimate target for foot
## units (they seek someone else) — EXCEPT the catapult, which may still bombard
## them. Multiple preachers spread out: each prefers a target no peer preacher
## has claimed.

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const PREACHER_SCENE: PackedScene = preload("res://scenes/units/preacher.tscn")
const SIEGE_SCENE: PackedScene = preload("res://scenes/units/siege_engine.tscn")


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
	return {"td": td, "nav": nav, "um": um, "bm": bm, "tm": tm, "wpm": wpm}


func _free_world(w: Dictionary) -> void:
	w.tm.free()
	w.wpm.free()
	w.bm.free()
	w.um.free()


func test_foot_unit_ignores_converting_target() -> void:
	var w: Dictionary = _make_world()
	var warrior: Unit = w.um.spawn_unit(WARRIOR_SCENE, 0, Vector3(50, 5, 50))
	var victim: Unit = w.um.spawn_unit(BRAVE_SCENE, 1, Vector3(52, 5, 50))
	var preacher: Unit = w.um.spawn_unit(PREACHER_SCENE, 0, Vector3(53, 5, 50))
	check(victim.begin_conversion(preacher, 9.0), "victim is now being converted (SIT)")
	check(warrior._scan_for_enemy(20.0) == null,
		"a warrior ignores an enemy that is being converted")
	_free_world(w)


func test_catapult_may_target_converting_unit() -> void:
	var w: Dictionary = _make_world()
	var siege: Unit = w.um.spawn_unit(SIEGE_SCENE, 0, Vector3(50, 5, 50))
	var victim: Unit = w.um.spawn_unit(BRAVE_SCENE, 1, Vector3(55, 5, 50))
	var preacher: Unit = w.um.spawn_unit(PREACHER_SCENE, 0, Vector3(56, 5, 50))
	check(victim.begin_conversion(preacher, 9.0), "victim is being converted (SIT)")
	check(siege._nearest_enemy_unit(30.0) == victim,
		"the catapult still targets the converting unit")
	_free_world(w)


func test_preachers_spread_to_different_targets() -> void:
	var w: Dictionary = _make_world()
	var pa: Preacher = w.um.spawn_unit(PREACHER_SCENE, 0, Vector3(50, 5, 50)) as Preacher
	var pb: Preacher = w.um.spawn_unit(PREACHER_SCENE, 0, Vector3(51, 5, 50)) as Preacher
	var e1: Unit = w.um.spawn_unit(BRAVE_SCENE, 1, Vector3(53, 5, 50))
	var e2: Unit = w.um.spawn_unit(BRAVE_SCENE, 1, Vector3(53, 5, 52))
	# Preacher A has already claimed e1 as its focus.
	pa._convert_target = e1
	check(pb._claimed_by_peer(e1), "e1 is seen as claimed by peer preacher A")
	check(not pb._claimed_by_peer(e2), "e2 is unclaimed")
	# So B picks the OTHER enemy instead of piling onto e1.
	check(pb._pick_convert_focus() == e2, "preacher B fans out to the unclaimed target")
	_free_world(w)


func test_second_preacher_does_not_pin_on_peers_victim() -> void:
	# User report: several preachers channel on the SAME victim, which is
	# pointless — one converting preacher is enough. Fix: a preacher whose only
	# in-range convertible already sits under a PEER must walk to a free target
	# instead of standing pinned next to it (the old any_in_range bug).
	var w: Dictionary = _make_world()
	var pa: Preacher = w.um.spawn_unit(PREACHER_SCENE, 0, Vector3(50, 5, 50)) as Preacher
	var pb: Preacher = w.um.spawn_unit(PREACHER_SCENE, 0, Vector3(51, 5, 50)) as Preacher
	# Shared victim within CONVERT_RANGE (5 m) of BOTH preachers.
	var shared: Unit = w.um.spawn_unit(BRAVE_SCENE, 1, Vector3(52, 5, 50))
	# A free convertible 7 m from B: inside AGGRO_RADIUS (8 m), outside convert range.
	var free_target: Unit = w.um.spawn_unit(BRAVE_SCENE, 1, Vector3(51, 5, 57))
	# A channels first and pacifies the shared victim (it sits under A).
	pa._refresh_conversion()
	check(shared.state == Unit.State.SIT, "shared victim sits down under a preacher")
	check(shared.converting_preacher == pa, "shared victim is converted by preacher A")
	# B refreshes: its only in-range convertible sits under A, so B fans out to
	# the free target instead of double-teaming A's victim.
	pb._refresh_conversion()
	check(pb._convert_target == free_target,
		"preacher B walks to the free target instead of pinning on A's victim")
	check(shared.converting_preacher == pa,
		"the shared victim stays bound to A only (no second converter)")
	_free_world(w)


func test_second_preacher_goes_idle_without_free_target() -> void:
	# Same clash but with NO free target elsewhere: the second preacher must not
	# stand channeling over A's victim either — it goes idle (an idle preacher
	# never re-grabs a SIT unit, so this does not oscillate).
	var w: Dictionary = _make_world()
	var pa: Preacher = w.um.spawn_unit(PREACHER_SCENE, 0, Vector3(50, 5, 50)) as Preacher
	var pb: Preacher = w.um.spawn_unit(PREACHER_SCENE, 0, Vector3(51, 5, 50)) as Preacher
	var shared: Unit = w.um.spawn_unit(BRAVE_SCENE, 1, Vector3(52, 5, 50))
	pa._set_state(Unit.State.CAST)
	pb._set_state(Unit.State.CAST)
	pa._refresh_conversion()
	check(shared.converting_preacher == pa, "victim converts under preacher A")
	pb._refresh_conversion()
	check(pb.state == Unit.State.IDLE,
		"the second preacher goes idle instead of channeling over A's victim")
	check(shared.converting_preacher == pa, "victim stays bound to A only")
	_free_world(w)
