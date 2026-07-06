extends TestBase

## Headless tests for phase 6: the shaman respawn at the reincarnation site —
## countdown only while she is dead, exactly one new shaman, no respawn
## without a (usable) site.

const TICK: float = 0.5

const SITE_SCENE: PackedScene = preload("res://scenes/buildings/reincarnation_site.tscn")
const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


func _make_world() -> Dictionary:
	var td: TerrainData = _flat_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var tribe0: Tribe = Tribe.new(0)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe0] as Array[Tribe])
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um)
	return {"td": td, "nav": nav, "tribe0": tribe0, "unit_manager": um, "bm": bm}


func _free_world(w: Dictionary) -> void:
	w.bm.free()
	w.unit_manager.free()


func _living_shamans(w: Dictionary) -> int:
	var count: int = 0
	for u in w.unit_manager.units:
		if is_instance_valid(u) and u.unit_kind() == &"shaman" \
				and u.state != Unit.State.DEAD:
			count += 1
	return count


func test_respawn_after_timer() -> void:
	var w: Dictionary = _make_world()
	var site: ReincarnationSite = w.bm.place(SITE_SCENE, w.tribe0, Vector2i(30, 30), 0, true)
	var shaman: Unit = w.unit_manager.spawn_unit(SHAMAN_SCENE, 0, Vector3(40, 0, 40))
	w.bm.tick(TICK)
	check(not site.respawn_pending, "no countdown while the shaman lives")
	shaman.take_damage(9999)
	check(w.tribe0.shaman == null, "tribe.shaman cleared on death")
	# Just before the timer expires: still no new shaman.
	var elapsed: float = 0.0
	while elapsed < ReincarnationSite.RESPAWN_TIME - 1.0:
		w.bm.tick(TICK)
		elapsed += TICK
	check(site.respawn_pending, "countdown runs while she is dead")
	check(site.respawn_remaining() > 0.0, "remaining time exposed for the UI")
	check(_living_shamans(w) == 0, "no early respawn")
	# Let it expire.
	for i in range(6):
		w.bm.tick(TICK)
	check(_living_shamans(w) == 1, "exactly one new shaman after the timer")
	check(w.tribe0.shaman != null and w.tribe0.shaman.state != Unit.State.DEAD,
		"tribe.shaman set again")
	var dist: float = Vector2(w.tribe0.shaman.position.x - site.center_world().x,
		w.tribe0.shaman.position.z - site.center_world().z).length()
	check(dist < 6.0, "respawned at the site")
	# The site never spawns a second one while she lives.
	for i in range(60):
		w.bm.tick(TICK)
	check(_living_shamans(w) == 1, "never two shamans")
	_free_world(w)


func test_no_respawn_without_site() -> void:
	var w: Dictionary = _make_world()
	var site: ReincarnationSite = w.bm.place(SITE_SCENE, w.tribe0, Vector2i(30, 30), 0, true)
	var shaman: Unit = w.unit_manager.spawn_unit(SHAMAN_SCENE, 0, Vector3(40, 0, 40))
	site.destroy()
	shaman.take_damage(9999)
	var elapsed: float = 0.0
	while elapsed < ReincarnationSite.RESPAWN_TIME * 2.0:
		w.bm.tick(TICK)
		elapsed += TICK
	check(_living_shamans(w) == 0, "destroyed site -> no respawn")
	check(w.tribe0.shaman == null, "shaman stays dead")
	_free_world(w)


func test_no_respawn_while_site_is_damaged() -> void:
	var w: Dictionary = _make_world()
	var site: ReincarnationSite = w.bm.place(SITE_SCENE, w.tribe0, Vector2i(30, 30), 0, true)
	var shaman: Unit = w.unit_manager.spawn_unit(SHAMAN_SCENE, 0, Vector3(40, 0, 40))
	site.apply_destruction_stages(1)
	check(not site.is_usable(), "damaged site is unusable")
	shaman.take_damage(9999)
	var elapsed: float = 0.0
	while elapsed < ReincarnationSite.RESPAWN_TIME * 2.0:
		w.bm.tick(TICK)
		elapsed += TICK
	check(_living_shamans(w) == 0, "damaged site cannot reincarnate")
	# Repair it -> the countdown starts and she returns.
	site.repair_wood = 99
	while site.health < site.max_health:
		check(site.repair(100.0), "repair works with wood delivered")
	check(site.is_usable(), "site usable again")
	elapsed = 0.0
	while elapsed < ReincarnationSite.RESPAWN_TIME + 2.0:
		w.bm.tick(TICK)
		elapsed += TICK
	check(_living_shamans(w) == 1, "respawn resumes after the repair")
	_free_world(w)
