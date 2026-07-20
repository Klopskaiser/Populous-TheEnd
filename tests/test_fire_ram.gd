extends TestBase

## Headless tests for the fire ram (Feuerramme) and its workshop: production
## (11-wood building, 4 wood / 40 worker-seconds per ram, independent per-tribe
## cap), the scorch burn (no contact damage), the forward flame rectangle
## (no minimum range, friendly fire, vehicle ignition, building stage per full
## burst, tree ignition), the crew's ranged-distraction immunity and the
## shared vehicle destruction/capture rules.

const TICK: float = 0.1
const MAX_TICKS: int = 3000

const RAM_WORKSHOP_SCENE: PackedScene = preload("res://scenes/buildings/fire_ram_workshop.tscn")
const WORKSHOP_SCENE: PackedScene = preload("res://scenes/buildings/workshop.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const FIRE_RAM_SCENE: PackedScene = preload("res://scenes/units/fire_ram.tscn")
const SIEGE_SCENE: PackedScene = preload("res://scenes/units/siege_engine.tscn")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")
const PREACHER_SCENE: PackedScene = preload("res://scenes/units/preacher.tscn")


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
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe0, tribe1] as Array[Tribe], tm, wpm)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um, wpm)
	um.building_manager = bm
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(nav, bm, um, tm)
	return {
		"td": td, "nav": nav, "tribe": tribe0, "tribe1": tribe1,
		"unit_manager": um, "building_manager": bm,
		"tree_manager": tm, "wood_pile_manager": wpm, "commands": tc,
	}


func _free_world(w: Dictionary) -> void:
	w.commands.free()
	w.tree_manager.free()
	w.wood_pile_manager.free()
	w.building_manager.free()
	w.unit_manager.free()


func _tick_world(w: Dictionary) -> void:
	w.building_manager.tick(TICK)
	for u in w.unit_manager.units.duplicate():
		if is_instance_valid(u):
			u.tick(TICK)
	w.unit_manager.tick(TICK)


func _spawn_ram(w: Dictionary, tribe_id: int, pos: Vector3) -> FireRam:
	return w.unit_manager.spawn_unit(FIRE_RAM_SCENE, tribe_id, pos) as FireRam


## Spawns a brave and boards it onto the vehicle (ticking until it serves).
func _board_crew(w: Dictionary, engine, tribe_id: int = 0) -> Brave:
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, tribe_id, engine.position + Vector3(1.0, 0.0, 0.0)) as Brave
	brave.order_crew(engine)
	var ticks: int = 0
	while not brave.siege_boarded and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	return brave


func _house_worker(w: Dictionary, ws: Workshop) -> Brave:
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, ws.entrance_world() + Vector3(1.0, 0.0, 1.0)) as Brave
	brave.order_workshop(ws)
	var ticks: int = 0
	while not brave.workshop_inside and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	return brave


# --- Workshop ---------------------------------------------------------------------

func test_fire_ram_workshop_produces_a_ram() -> void:
	var w: Dictionary = _make_world()
	var ws: FireRamWorkshop = w.building_manager.place(
		RAM_WORKSHOP_SCENE, w.tribe, Vector2i(60, 60), 0, true) as FireRamWorkshop
	check(ws != null, "fire-ram workshop placed")
	check(ws.wood_cost == 11, "fire-ram workshop costs 11 wood")
	check(ws.footprint == Vector2i(6, 4), "6x4 footprint")
	check(ws.worker_slots() == 3, "3 worker slots")
	check(ws.display_name() == "Feuerrammenwerkstatt", "display name")
	_house_worker(w, ws)
	w.wood_pile_manager.deposit(ws.delivery_point(), FireRamWorkshop.RAM_WOOD)
	var stock_before: int = ws.stock_wood()
	var ticks: int = 0
	while not ws.production_active and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(ws.production_active, "production started")
	check(stock_before - ws.stock_wood() == FireRamWorkshop.RAM_WOOD,
		"starting consumed exactly %d wood" % FireRamWorkshop.RAM_WOOD)
	ticks = 0
	var rams: int = 0
	while rams == 0 and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
		rams = w.tribe.owned_fire_ram_count()
	check(rams == 1, "one fire ram rolled out")
	# 1 housed worker: 40 worker-seconds = ~400 ticks (+ walk-in slack).
	check(ticks <= int(FireRamWorkshop.WORK_PER_RAM / TICK) + 200,
		"finished in roughly 40 worker-seconds with one worker")
	_free_world(w)


func test_caps_are_independent_per_vehicle_type() -> void:
	var w: Dictionary = _make_world()
	var ram_ws: FireRamWorkshop = w.building_manager.place(
		RAM_WORKSHOP_SCENE, w.tribe, Vector2i(60, 60), 0, true) as FireRamWorkshop
	var cat_ws: Workshop = w.building_manager.place(
		WORKSHOP_SCENE, w.tribe, Vector2i(80, 80), 0, true) as Workshop
	w.wood_pile_manager.deposit(ram_ws.delivery_point(), 10)
	w.wood_pile_manager.deposit(cat_ws.delivery_point(), 10)
	w.tribe.max_fire_rams = 1
	_spawn_ram(w, 0, Vector3(40, 0, 40))
	check(w.tribe.owned_fire_ram_count() == 1, "one own ram exists")
	check(w.tribe.owned_catapult_count() == 0, "rams never count as catapults")
	check(not ram_ws.can_start_production(), "ram cap blocks the ram workshop")
	check(cat_ws.can_start_production(), "the catapult workshop is unaffected")
	w.unit_manager.spawn_unit(SIEGE_SCENE, 0, Vector3(44, 0, 40))
	check(w.tribe.owned_catapult_count() == 1, "catapults keep their own count")
	check(w.tribe.owned_fire_ram_count() == 1, "catapults never count as rams")
	_free_world(w)


## Regression (user bug): a lightly damaged workshop that STILL holds its
## production stock at the entrance could not be repaired — the repair worker
## detached before the workshop banked that stock into the repair buffer, so it
## deadlocked (right-click "did nothing"). The worker must now stay and repair.
func test_damaged_workshop_repairs_with_entrance_stock() -> void:
	var w: Dictionary = _make_world()
	var ws: FireRamWorkshop = w.building_manager.place(
		RAM_WORKSHOP_SCENE, w.tribe, Vector2i(60, 60), 0, true) as FireRamWorkshop
	check(ws.is_usable(), "pre-built workshop is usable")
	# The production stock sits at the entrance (>= the floored repair cost).
	w.wood_pile_manager.deposit(ws.delivery_point(), FireRamWorkshop.RAM_WOOD)
	# Stage-1 damage (30% HP): unusable, ~floor(0.30 * 11) = 3 wood to repair.
	ws.apply_destruction_stages(1)
	check(not ws.is_usable() and ws.destruction_stage() >= 1,
		"stage-1 damage makes it unusable")
	var hp_before: int = ws.health
	var brave: Brave = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, ws.entrance_world() + Vector3(1.5, 0.0, 1.5)) as Brave
	brave.order_repair(ws)
	check(brave.job == ws, "the brave took the repair job")
	var ticks: int = 0
	while ws.health < ws.max_health and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(ws.health > hp_before, "the damaged workshop is actually repaired (no deadlock)")
	check(ws.health == ws.max_health, "repair completes back to full HP")
	check(ws.is_usable(), "the repaired workshop is usable again")
	_free_world(w)


# --- Scorch (burn without contact damage) -------------------------------------------

func test_scorch_burns_without_contact_damage() -> void:
	var w: Dictionary = _make_world()
	var brave: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, Vector3(40, 0, 40))
	check(not brave.is_burning(), "starts unburnt")
	brave.scorch(Vector3(38, 0, 40))
	check(brave.is_burning(), "scorch sets the unit alight")
	check(brave.health == brave.max_health,
		"NO immediate contact damage (unlike lava ignite)")
	for i in range(20):
		_tick_world(w)
	check(brave.health < brave.max_health, "the burn ticks damage over time")
	_free_world(w)


# --- Flame rectangle ------------------------------------------------------------------

## Ram at (60,60) with heading +z; boards one brave (drives AND fires).
func _armed_ram(w: Dictionary) -> FireRam:
	var ram: FireRam = _spawn_ram(w, 0, w.nav.cell_to_world(Vector2i(60, 60)))
	_board_crew(w, ram)
	return ram


func test_flame_rectangle_hits_and_misses() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _armed_ram(w)
	var pos: Vector3 = ram.position
	# In front (heading starts +z): inside range 5, no minimum range.
	var near_front: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, pos + Vector3(0, 0, 2.2))
	var behind: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, pos + Vector3(0, 0, -3.0))
	var friend: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 0, pos + Vector3(0.5, 0, 3.0))
	ram.order_attack(near_front)
	var ticks: int = 0
	while not near_front.is_burning() and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(near_front.is_burning(), "enemy at 2.2 m in front burns")
	check(friend.is_burning(), "own unit in the cone burns too (friendly fire)")
	check(not behind.is_burning(), "the unit BEHIND the ram never burns")
	check(near_front.health == near_front.max_health
			or near_front.health > near_front.max_health - 25,
		"no big instant hit — damage is the burn itself")
	_free_world(w)


## The flame cone fans out 2 -> 3 wide: a unit at a side offset that is OUTSIDE
## the cone near the nozzle is INSIDE it near the far end.
func test_flame_cone_widens_toward_the_far_end() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _armed_ram(w)   # heading +z
	var p: Vector3 = ram.position
	# Target straight ahead, close enough that the ram stops and fires (no roll).
	var target_pos: Vector3 = p + Vector3(0, 0, 2.0)
	var target: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, target_pos)
	# Same side offset (1.3 m) at two ranges: near the nozzle (narrow, ~1.07 m
	# half-width) it is outside; near the far end (wide, ~1.45 m) it is inside.
	var near_pos: Vector3 = p + Vector3(1.3, 0, 1.9)
	var far_pos: Vector3 = p + Vector3(1.3, 0, 5.7)
	var near_side: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, near_pos)
	var far_side: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, far_pos)
	ram.order_attack(target)
	var ticks: int = 0
	while not far_side.is_burning() and ticks < MAX_TICKS:
		target.position = target_pos
		near_side.position = near_pos
		far_side.position = far_pos
		_tick_world(w)
		ticks += 1
	check(far_side.is_burning(),
		"a unit at side 1.3 m near the far end is caught (cone widened to 3)")
	check(not near_side.is_burning(),
		"the same side offset near the nozzle is NOT caught (cone still 2 wide)")
	_free_world(w)


func test_flames_ignite_enemy_ground_vehicles() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _armed_ram(w)
	var foe: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 1, ram.position + Vector3(0, 0, 3.0)) as SiegeEngine
	ram.order_attack(foe)
	var ticks: int = 0
	while not foe.is_burning() and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(foe.is_burning(), "an enemy catapult in the cone catches fire")
	while foe.state != Unit.State.DEAD and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(foe.state == Unit.State.DEAD, "the burning wreck is destroyed")
	_free_world(w)


func test_full_burst_stages_a_building_once() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _armed_ram(w)
	# Enemy hut with its near edge ~3 m in front of the nozzle.
	var cell: Vector2i = w.nav.world_to_cell(ram.position + Vector3(0, 0, 6.0))
	var hut: Building = w.building_manager.place(HUT_SCENE, w.tribe1, cell, 0, true)
	check(hut != null, "enemy hut placed in front of the ram")
	ram.order_attack_building(hut)
	# Run until the first full burst has been delivered (flame 1 s + checks).
	var ticks: int = 0
	while hut.destruction_stage() < 1 and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(hut.destruction_stage() == 1,
		"one full flame burst = exactly one destruction stage (grace-window rule)")
	# Immediately after the first stage no second stage may exist yet — the
	# reload gap (1.5 s at full crew, 3 s at 1) must not leak extra stages.
	for i in range(5):
		_tick_world(w)
	check(hut.destruction_stage() == 1, "no second stage during the reload")
	_free_world(w)


func test_flames_ignite_trees() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _armed_ram(w)
	var tree_cell: Vector2i = w.nav.world_to_cell(ram.position + Vector3(0, 0, 3.0))
	var tree = w.tree_manager.spawn_tree(tree_cell, 2)
	check(tree != null and not tree.is_burning(), "tree starts unburnt")
	var victim: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, ram.position + Vector3(0.4, 0, 3.0))
	ram.order_attack(victim)
	var ticks: int = 0
	while not tree.is_burning() and ticks < MAX_TICKS:
		_tick_world(w)
		ticks += 1
	check(tree.is_burning(), "a tree in the flame cone catches fire")
	_free_world(w)


func test_minimum_range_holds_fire_point_blank() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _armed_ram(w)
	# An enemy INSIDE the 1 m minimum range stands behind the nozzle — the ram
	# holds its fire against it instead of wasting bursts.
	var hugger: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, ram.position + Vector3(0, 0, 0.5))
	ram.order_attack(hugger)
	for i in range(40):
		# Pin the hugger point-blank: its melee brawl with the ram's crew would
		# otherwise shove it randomly past the 1 m minimum, where the ram
		# legitimately opens fire (flaky) — INSIDE the minimum is the contract.
		hugger.position = ram.position + Vector3(0, 0, 0.5)
		_tick_world(w)
	check(not hugger.is_burning(),
		"a unit inside the 1 m minimum range is never burnt")
	check(ram._flame_time <= 0.0, "no burst was started against it")
	_free_world(w)


# --- Crew distraction immunity --------------------------------------------------------

func test_ram_crew_ignores_ranged_harassment() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _spawn_ram(w, 0, w.nav.cell_to_world(Vector2i(60, 60)))
	var crew: Brave = _board_crew(w, ram)
	# Ranged pressure from 6 m: the crew must NOT counter-attack.
	var shooter: Unit = w.unit_manager.spawn_unit(
		FIREWARRIOR_SCENE, 1, ram.position + Vector3(-6.0, 0, 0))
	crew._maybe_retaliate(shooter)
	check(crew.state == Unit.State.CREW,
		"ram crew ignores ranged harassment (stays at its post)")
	check(crew.attack_target == null, "no counter-target was locked")
	# Direct melee pressure: the crew defends itself.
	var brawler: Unit = w.unit_manager.spawn_unit(
		WARRIOR_SCENE, 1, crew.position + Vector3(0.8, 0, 0))
	crew._maybe_retaliate(brawler)
	check(crew.attack_target == brawler, "direct melee IS retaliated")
	_free_world(w)


func test_catapult_crew_still_retaliates_vs_ranged() -> void:
	var w: Dictionary = _make_world()
	var engine: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 0, w.nav.cell_to_world(Vector2i(60, 60))) as SiegeEngine
	var crew: Brave = _board_crew(w, engine)
	var shooter: Unit = w.unit_manager.spawn_unit(
		FIREWARRIOR_SCENE, 1, engine.position + Vector3(-6.0, 0, 0))
	crew._maybe_retaliate(shooter)
	check(crew.attack_target == shooter,
		"catapult crew behaviour is unchanged (retaliates vs ranged)")
	_free_world(w)


# --- Cooldown & movement gates ----------------------------------------------------------

func test_flame_cooldown_scales_with_crew() -> void:
	check(is_inf(FireRam.flame_cooldown_for_crew(0)), "0 crew cannot fire")
	check_near(FireRam.flame_cooldown_for_crew(1), 3.0, "1 crew reloads slowly")
	check_near(FireRam.flame_cooldown_for_crew(4), 1.4, "full crew reloads fastest")
	check(FireRam.flame_cooldown_for_crew(2) < 3.0, "more crew -> faster")


func test_one_crew_moves_and_fires() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _spawn_ram(w, 0, w.nav.cell_to_world(Vector2i(60, 60)))
	ram.order_move(w.nav.cell_to_world(Vector2i(70, 60)))
	check(ram.state != Unit.State.MOVE, "an unmanned ram never moves")
	_board_crew(w, ram)
	ram.order_move(w.nav.cell_to_world(Vector2i(70, 60)))
	check(ram.state == Unit.State.MOVE, "ONE crew member drives the ram")
	# ... and the same single member fires (covered by the flame tests above,
	# which run with exactly one boarded brave).
	_free_world(w)


## Anti-twitch (Spieltest 3): the ram fires ON THE MOVE — a runner that keeps
## its distance near the range edge is pursued and burnt without the ram
## stopping at the 5 m border first.
func test_ram_fires_while_rolling_after_a_runner() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _armed_ram(w)
	var runner: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, ram.position + Vector3(0, 0, 4.0))
	ram.order_attack(runner)
	var start_z: float = ram.position.z
	var burst_started: bool = false
	for i in range(60):
		# Pin the runner 4 m ahead (inside the band, beyond the hold point) —
		# a stop-and-go ram would stand still instead of closing in.
		runner.position = ram.position + Vector3(0, 0, 4.0)
		_tick_world(w)
		burst_started = burst_started or ram._flame_time > 0.0
	check(burst_started, "the burst starts while the chase is still rolling")
	check(ram.position.z > start_z + 1.0,
		"the ram kept rolling after the runner while firing")
	check(runner.is_burning(), "the fleeing runner was scorched on the move")
	_free_world(w)


## Anti-twitch (Spieltest 3): a foe already inside the flame range always
## takes over — the ram does not chase an ordered runner past an enemy
## standing right in front of the nozzle.
func test_ram_prefers_in_range_target_over_chase() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _armed_ram(w)
	var runner: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, ram.position + Vector3(0, 0, 9.0))
	var near: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, ram.position + Vector3(0, 0, 3.0))
	ram.order_attack(runner)   # ordered chase target beyond FIRE_RANGE
	for i in range(30):
		runner.position = ram.position + Vector3(0, 0, 9.0)
		near.position = ram.position + Vector3(0, 0, 3.0)
		_tick_world(w)
		if ram.attack_target == near:
			break
	check(ram.attack_target == near,
		"the ram swaps the out-of-range order for the enemy already in range")
	check(not ram._target_ordered, "the swapped target is a normal auto target")
	_free_world(w)


## Target priority (user request): an ordered target that has crept INSIDE the
## minimum range (unhittable) is swapped for any shootable enemy in the flame
## band — the ram must not sit and hold fire while a reachable foe stands there.
func test_ram_swaps_too_close_ordered_target_for_band_enemy() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _armed_ram(w)
	# Ordered target hugging the nozzle (inside 1 m), a second enemy in the band.
	var close_enemy: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, ram.position + Vector3(0, 0, 0.6))
	close_enemy.max_health = 100000
	close_enemy.health = 100000
	var band_enemy: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, ram.position + Vector3(0, 0, 3.0))
	var band_pos: Vector3 = band_enemy.position
	ram.order_attack(close_enemy)
	check(ram._target_ordered, "starts on the ordered close target")
	var swapped: bool = false
	for i in range(60):
		close_enemy.position = ram.position + Vector3(0, 0, 0.6)   # pin inside min
		band_enemy.position = band_pos
		_tick_world(w)
		if ram.attack_target == band_enemy:
			swapped = true
		if band_enemy.is_burning():
			break
	check(swapped, "the ram swaps the too-close ordered target for the band enemy")
	check(not ram._target_ordered, "the swapped-in band enemy is a normal auto target")
	check(band_enemy.is_burning(), "the shootable band enemy is actually burnt")
	_free_world(w)


## Retreat (user request): with a threat inside the minimum range and NO other
## target to shoot, the ram drives backwards to reopen the firing distance and
## opens fire again the instant the minimum range is clear.
func test_ram_reverses_from_point_blank_then_fires() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _armed_ram(w)
	# A single enemy hugging the nozzle (inside 1 m), pinned in the WORLD so the
	# ram genuinely opens the gap by reversing (not by the enemy moving).
	var foe_pos: Vector3 = ram.position + Vector3(0, 0, 0.7)
	var foe: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, foe_pos)
	foe.max_health = 100000
	foe.health = 100000
	var start_z: float = ram.position.z
	ram.order_attack(foe)
	for i in range(80):
		foe.position = foe_pos
		_tick_world(w)
		if foe.is_burning():
			break
	check(ram.position.z < start_z - 0.1,
		"the ram reversed away from the point-blank threat")
	check(foe.is_burning(),
		"once the minimum range cleared, the ram opened fire again")
	_free_world(w)


## Regression (Spieltest 4): if the crew is pacified/converted away exactly as
## a burst ends, active_crew_count() is 0 and the reload must NOT latch to INF —
## otherwise the re-crewed ram could move but never fire again (user bug).
func test_ram_fires_again_after_crew_converted() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _armed_ram(w)
	var old_crew = ram.crew[0]
	var preacher: Unit = w.unit_manager.spawn_unit(
		PREACHER_SCENE, 1, ram.position + Vector3(0, 0, 6.0))
	# Force a burst to end on the very tick the sole crew sits down (pacified).
	ram._flame_time = 0.05
	old_crew.begin_conversion(preacher, 5.0)
	check(ram.active_crew_count() == 0, "the pacified crew no longer counts as active")
	ram.tick(0.1)   # burst ends here with zero active crew
	check(is_finite(ram._reload), "the reload never latches to INF (root of the bug)")
	# The old crew is converted away; a fresh brave re-mans the ram.
	old_crew.leave_crew()
	_board_crew(w, ram)
	var enemy: Unit = w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, ram.position + Vector3(0, 0, 3.0))
	ram.order_attack(enemy)
	var fired: bool = false
	for i in range(80):
		enemy.position = ram.position + Vector3(0, 0, 3.0)
		_tick_world(w)
		fired = fired or ram._flame_time > 0.0
	check(fired, "the re-crewed ram can fire again")
	_free_world(w)


# --- Destruction & capture (shared vehicle rules) ---------------------------------------

func test_ram_burns_and_sinks_and_is_capturable() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _spawn_ram(w, 0, w.nav.cell_to_world(Vector2i(60, 60)))
	# Unmanned ram: an enemy brave boards it -> ownership switches.
	var raider: Brave = _board_crew(w, ram, 1)
	check(ram.tribe_id == 1, "boarding an unmanned ram takes it over")
	check(raider.siege_boarded, "the raider serves the captured ram")
	# Fire resistance: the ram has FIRE_LIVES lives. Anonymous (null-source)
	# ignites each count as one hit; only the FIRE_LIVES-th burns it down.
	ram.ignite(ram.position)
	check(ram.is_burning(), "fire sets the wooden ram alight")
	check(ram.state != Unit.State.DEAD, "one fire hit does not destroy the ram (3 lives)")
	for _i in range(FireRam.FIRE_LIVES - 2):
		ram.ignite(ram.position)
	check(ram.state != Unit.State.DEAD, "still alive one hit short of lethal")
	ram.ignite(ram.position)   # the lethal hit
	check(ram.state == Unit.State.DEAD, "the FIRE_LIVES-th fire hit burns it down")
	check(raider.state != Unit.State.DEAD, "the crew survives and is released")
	check(raider.siege_engine == null, "crew membership was cleared")
	_free_world(w)


func test_ram_throttles_repeated_hits_from_one_source() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _spawn_ram(w, 0, w.nav.cell_to_world(Vector2i(60, 60)))
	_board_crew(w, ram)
	# One source (identified by instance) can only cost ONE life however often it
	# touches the ram — until it counts as a fresh attack.
	var src: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, ram.position + Vector3(4, 0, 0))
	for _i in range(5):
		ram.ignite(ram.position, src)
	check(ram._fire_hits == 1, "repeated contact from the same source is one hit")
	# A different source adds a second hit.
	var src2: Unit = w.unit_manager.spawn_unit(BRAVE_SCENE, 1, ram.position + Vector3(5, 0, 0))
	ram.ignite(ram.position, src2)
	check(ram._fire_hits == 2, "a different source costs another life")
	check(ram.state != Unit.State.DEAD, "two hits are not lethal (3 lives)")
	_free_world(w)


func test_ram_fire_source_counts_once_per_burst() -> void:
	var w: Dictionary = _make_world()
	var target: FireRam = _spawn_ram(w, 0, w.nav.cell_to_world(Vector2i(60, 60)))
	_board_crew(w, target)
	# An attacking ram is keyed per burst: repeated contact within one burst is
	# one hit, a new burst (bumped _burst_seq) is a fresh hit.
	var attacker: FireRam = _spawn_ram(w, 1, w.nav.cell_to_world(Vector2i(70, 70)))
	target.ignite(target.position, attacker)
	target.ignite(target.position, attacker)
	check(target._fire_hits == 1, "same burst from one ram is a single hit")
	attacker._burst_seq += 1   # next flame burst
	target.ignite(target.position, attacker)
	check(target._fire_hits == 2, "a fresh burst from the same ram hits again")
	_free_world(w)


func test_ram_regenerates_a_life_while_crewed() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _spawn_ram(w, 0, w.nav.cell_to_world(Vector2i(60, 60)))
	_board_crew(w, ram)
	ram.ignite(ram.position)
	# Ignite source spawned OUTSIDE the ram's aggro radius: the source only needs
	# to be a valid enemy for the hit's attribution key, and this test isolates
	# the time-based regen. If it sat in aggro the (correctly pursuing) ram would
	# engage it, its crew would leave for direct-melee retaliation and
	# active_crew_count() -> 0 would stall regen — unrelated to what we assert.
	ram.ignite(ram.position, w.unit_manager.spawn_unit(
		BRAVE_SCENE, 1, ram.position + Vector3(40, 0, 0)))
	check(ram._fire_hits == 2, "took two fire hits")
	# Crewed: heals one life after LIFE_REGEN_TIME (even without combat pause).
	var elapsed: float = 0.0
	while ram._fire_hits > 1 and elapsed < FireRam.LIFE_REGEN_TIME + 5.0:
		_tick_world(w)
		elapsed += TICK
	check(ram._fire_hits == 1, "a crewed ram regenerated one life after ~30 s")
	_free_world(w)


func test_ram_does_not_regenerate_without_crew() -> void:
	var w: Dictionary = _make_world()
	var ram: FireRam = _spawn_ram(w, 0, w.nav.cell_to_world(Vector2i(60, 60)))
	ram.ignite(ram.position)   # unmanned
	check(ram._fire_hits == 1, "took a fire hit")
	for _i in range(int((FireRam.LIFE_REGEN_TIME + 5.0) / TICK)):
		_tick_world(w)
	check(ram._fire_hits == 1, "an uncrewed ram does not heal")
	_free_world(w)
