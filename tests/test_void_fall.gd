extends TestBase

## Phase 10j — Sturz ins All: what happens to a unit that leaves the disc.
##
## The shape mirrors the existing drowning mechanic on purpose (`_drowning` is a flag
## on DEAD, not a State of its own), so these tests read like the drowning ones.
##
## The ordering rule they pin down: the unit dies AT THE RIM and only then keeps
## falling as a corpse. That is what makes the mana bonus, the shaman's cry and her
## respawn countdown happen where the player can see them — and it keeps the defeat
## check honest, because a unit that is "alive" but unreachable in space for 30 s
## would stall the victory evaluation.

const TICK: float = 0.1

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")
const SITE_SCENE: PackedScene = preload("res://scenes/buildings/reincarnation_site.tscn")
const SIEGE_SCENE: PackedScene = preload("res://scenes/units/siege_engine.tscn")
const AIRSHIP_SCENE: PackedScene = preload("res://scenes/units/airship.tscn")


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
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe0, tribe1] as Array[Tribe])
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um)
	return {"td": td, "nav": nav, "tribe0": tribe0, "tribe1": tribe1,
		"unit_manager": um, "bm": bm}


func _free_world(w: Dictionary) -> void:
	w.bm.free()
	w.unit_manager.free()


func _spawn(w: Dictionary, scene: PackedScene, tribe_id: int, at: Vector2) -> Unit:
	return w.unit_manager.spawn_unit(scene, tribe_id, Vector3(at.x, 0.0, at.y))


## A spot just inside the outermost real cell, on the +x axis through the centre.
func _brink(td: TerrainData) -> Vector2:
	var mid: int = td.size / 2
	var last: int = mid
	while td.in_disc(Vector2i(last + 1, mid)):
		last += 1
	return Vector2(float(last) + 0.5, float(mid) + 0.5)


## Hurls the unit outward hard enough to clear the rim, then ticks until it is
## either falling or removed. Returns the number of ticks spent.
func _hurl_over_the_rim(u: Unit, ticks: int = 200) -> int:
	u.throw_airborne(Vector3(1, 0, 0) * 30.0 + Vector3.UP * 4.0)
	for i in range(ticks):
		if u._falling_into_void:
			return i
		u.tick(TICK)
	return ticks


# --- The fall ---------------------------------------------------------------------

func test_thrown_unit_past_the_rim_keeps_falling() -> void:
	var w: Dictionary = _make_world()
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, _brink(w.td))
	_hurl_over_the_rim(victim)
	check(victim._falling_into_void, "it went over the rim and is falling")
	var y0: float = victim.position.y
	for i in range(10):
		victim.tick(TICK)
	check(victim.position.y < y0, "it keeps losing height (%.2f -> %.2f)"
		% [y0, victim.position.y])
	check(not w.td.has_ground(victim.position.x, victim.position.z),
		"and it is still out over the void")
	_free_world(w)


func test_thrown_unit_dies_at_the_rim_not_at_the_bottom() -> void:
	var w: Dictionary = _make_world()
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, _brink(w.td))
	_hurl_over_the_rim(victim)
	check(victim.state == Unit.State.DEAD,
		"dead the moment it crossed the rim — the bonus/cry/respawn must fire there")
	check(victim.position.y > TerrainData.SEA_LEVEL - Balance.VOID_FALL_DEPTH,
		"and it has barely begun to fall (%.1f)" % victim.position.y)
	_free_world(w)


func test_falling_unit_is_removed_below_the_void_depth() -> void:
	var w: Dictionary = _make_world()
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, _brink(w.td))
	var expired: Array[bool] = [false]
	victim.corpse_expired.connect(func(_u: Unit) -> void: expired[0] = true)
	_hurl_over_the_rim(victim)
	var start_y: float = victim.position.y
	for i in range(400):
		if expired[0]:
			break
		victim.tick(TICK)
	check(expired[0], "corpse_expired fired, so UnitManager removes the body")
	check(victim.position.y <= start_y - Balance.VOID_FALL_DEPTH + 5.0,
		"and it had really fallen the removal depth (%.1f m)"
			% (start_y - victim.position.y))
	_free_world(w)


func test_falling_unit_is_never_parked_by_the_corpse_hold() -> void:
	# Same reason drowning units are excluded: the C2 corpse hold would freeze the
	# body in mid-air for the full CORPSE_DURATION.
	var w: Dictionary = _make_world()
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, _brink(w.td))
	_hurl_over_the_rim(victim)
	var held: int = 0
	for i in range(20):
		victim.tick(TICK)
		if victim._idx >= 0 and w.unit_manager.soa_hold[victim._idx] > 0.0:
			held += 1
	check(held == 0, "the falling corpse is never handed to the hold kernel")
	_free_world(w)


func test_void_fall_keeps_its_momentum() -> void:
	var w: Dictionary = _make_world()
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, _brink(w.td))
	_hurl_over_the_rim(victim)
	var x0: float = victim.position.x
	for i in range(10):
		victim.tick(TICK)
	check(victim.position.x > x0,
		"the body sails on outwards instead of dropping straight down")
	_free_world(w)


# --- Silent, except for the shaman -------------------------------------------------

func test_void_death_is_silent() -> void:
	var w: Dictionary = _make_world()
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, _brink(w.td))
	check(victim.death_sfx_key() == &"unit_death", "a normal death is audible")
	_hurl_over_the_rim(victim)
	check(victim.death_sfx_key() == &"",
		"a void death has no sound key at all (AudioManager returns on empty)")
	_free_world(w)


func test_shaman_void_death_keeps_her_cry() -> void:
	# Her override ignores the flag, which is exactly why it needs a test: the
	# silence is implemented in the base class and must NOT reach her.
	var w: Dictionary = _make_world()
	var shaman: Unit = _spawn(w, SHAMAN_SCENE, 1, _brink(w.td))
	_hurl_over_the_rim(shaman)
	check(shaman._falling_into_void, "she went over the rim")
	check(shaman.death_sfx_key() == &"shaman_death",
		"and she still screams on the way down (user decision)")
	_free_world(w)


## Total charge progress of a tribe — grant_bonus_mana() feeds the SPELL charges,
## not `tribe.mana` (there is no mana banking since 10c), so that is where the kill
## bonus has to become visible.
func _charge_fill(tribe: Tribe) -> float:
	var total: float = 0.0
	for spell in tribe.spells:
		total += float(spell.charges) * spell.charge_cost + spell.charge_mana
	return total


func test_shaman_thrown_over_the_rim_grants_the_kill_bonus() -> void:
	# The trap: the bonus hangs off last_attacker, and throw_airborne() does NOT set
	# it — it comes from the hit that launched her.
	var w: Dictionary = _make_world()
	w.tribe0.set_spells(Spell.create_default_set())
	var shaman: Unit = _spawn(w, SHAMAN_SCENE, 1, _brink(w.td))
	var killer: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(30, 30))
	check(w.tribe1.mana_rate() > 0.0, "her tribe has a mana rate worth stealing")
	shaman.last_attacker = killer
	var before: float = _charge_fill(w.tribe0)
	_hurl_over_the_rim(shaman)
	check(shaman.state == Unit.State.DEAD, "she died at the rim")
	check(_charge_fill(w.tribe0) > before,
		"the tribe that threw her got the mana bonus (%.2f -> %.2f)"
			% [before, _charge_fill(w.tribe0)])
	_free_world(w)


func test_shaman_falling_alone_grants_no_bonus() -> void:
	var w: Dictionary = _make_world()
	w.tribe0.set_spells(Spell.create_default_set())
	var shaman: Unit = _spawn(w, SHAMAN_SCENE, 1, _brink(w.td))
	var before: float = _charge_fill(w.tribe0)
	_hurl_over_the_rim(shaman)   # no last_attacker: she went over by herself
	check(is_equal_approx(_charge_fill(w.tribe0), before),
		"nobody is rewarded for a shaman who fell on her own")
	_free_world(w)


func test_shaman_void_death_respawns_her() -> void:
	var w: Dictionary = _make_world()
	var site: Building = w.bm.place(SITE_SCENE, w.tribe1, Vector2i(30, 30), 0, true)
	check(site != null, "the reincarnation site stands")
	var shaman: Unit = _spawn(w, SHAMAN_SCENE, 1, _brink(w.td))
	w.tribe1.shaman = shaman
	_hurl_over_the_rim(shaman)
	# The respawn only needs her to be DEAD, and the body may already be freed —
	# reincarnation_site checks is_instance_valid too.
	for i in range(int(ReincarnationSite.RESPAWN_TIME / 0.5) + 4):
		w.bm.tick(0.5)
	var alive: int = 0
	for u in w.unit_manager.units:
		if is_instance_valid(u) and u.unit_kind() == &"shaman" \
				and u.state != Unit.State.DEAD:
			alive += 1
	check(alive == 1, "exactly one shaman came back at the site (got %d)" % alive)
	_free_world(w)


# --- No splash in the void ---------------------------------------------------------

func test_no_splash_ring_appears_in_the_void() -> void:
	# The trap: water_splash_active() asks _is_water_at(), which used to go through
	# the clamping get_height(). On the island the rim is under water, so the WHOLE
	# void read as sea and a falling body drew a splash ring in empty space.
	var w: Dictionary = _make_world()
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, _brink(w.td))
	_hurl_over_the_rim(victim)
	var splashed: int = 0
	for i in range(120):
		victim.tick(TICK)
		if victim.water_splash_active():
			splashed += 1
	check(splashed == 0, "no splash ring while falling through the SEA_LEVEL band")
	_free_world(w)


func test_is_water_at_is_false_over_the_void() -> void:
	var w: Dictionary = _make_world()
	# Sink the whole map below the waterline: now every clamped get_height() sample
	# outside the map would report water.
	for i in range(w.td.heights.size()):
		w.td.heights[i] = TerrainData.SEA_LEVEL - 1.0
	var probe: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30, 30))
	check(probe._is_water_at(float(w.td.size) / 2.0, float(w.td.size) / 2.0),
		"the sunken map itself is water")
	check(not probe._is_water_at(-40.0, float(w.td.size) / 2.0),
		"the void is not water, however the rim height reads")
	_free_world(w)


# --- Who can and cannot get out there ----------------------------------------------

func test_walking_unit_never_reaches_the_void() -> void:
	# The regular case, and the reason the mask is the one lever: A* only ever
	# returns in-disc cells, so an ordinary move order cannot walk off the edge.
	var w: Dictionary = _make_world()
	var brink: Vector2 = _brink(w.td)
	var unit: Unit = _spawn(w, BRAVE_SCENE, 1, brink)
	unit.order_move(Vector3(float(w.td.size) + 40.0, 0.0, brink.y))
	var left: bool = false
	for i in range(300):
		unit.tick(TICK)
		if not w.td.has_ground(unit.position.x, unit.position.z):
			left = true
			break
	check(not left, "a walking unit stays on the disc")
	check(unit.state != Unit.State.DEAD, "and survives the attempt")
	_free_world(w)


func test_a_carried_unit_is_not_killed_by_the_rim_check() -> void:
	# A tornado clamps ITSELF into the disc, but its passenger slot orbits — the rim
	# check must be skipped while a carrier holds the unit.
	var w: Dictionary = _make_world()
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, _brink(w.td))
	var carrier: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(30, 30))
	victim.throw_airborne(Vector3.UP * 2.0)
	victim.throw_carrier = carrier
	victim.position = Vector3(float(w.td.size) + 20.0, 12.0, w.td.disc_center())
	for i in range(20):
		victim.tick(TICK)
	check(not victim._falling_into_void,
		"the carried unit is not dropped into the void by the rim test")
	check(victim.state == Unit.State.THROWN, "it is still being carried")
	_free_world(w)


func test_siege_engine_cannot_be_hurled_over_the_rim() -> void:
	# CrewedVehicle no-ops throw_airborne/start_roll/displace, so a vehicle can never
	# be launched. Documented here so nobody builds fall machinery it cannot reach.
	var w: Dictionary = _make_world()
	var engine: Unit = _spawn(w, SIEGE_SCENE, 1, _brink(w.td))
	var before: Vector3 = engine.position
	engine.throw_airborne(Vector3(1, 0, 0) * 40.0 + Vector3.UP * 10.0)
	check(engine.state != Unit.State.THROWN, "a siege engine is too heavy to throw")
	check(engine.position.is_equal_approx(before), "it has not moved")
	check(not engine._falling_into_void, "and it is not falling")
	_free_world(w)


func test_airship_still_cannot_leave_the_map() -> void:
	# The airship keeps its clamp: it is COMMANDED, not hurled.
	var w: Dictionary = _make_world()
	var ship: Unit = _spawn(w, AIRSHIP_SCENE, 1, Vector2(30, 30))
	ship.order_move(Vector3(float(w.td.size) + 200.0, 0.0, -80.0))
	for i in range(400):
		ship.tick(TICK)
	check(w.td.has_ground(ship.position.x, ship.position.z),
		"the airship stayed over the disc (%.1f, %.1f)"
			% [ship.position.x, ship.position.z])
	check(ship.state != Unit.State.DEAD, "and it is still flying")
	_free_world(w)
