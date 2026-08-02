extends TestBase

## Headless tests for Stufe C2 (plans/08e): the soa_target handle (index +
## slot generation, C2.1), the melee hold kernel (C2.2) and the firewarrior
## fire kernel (C2.3). All battle loops drive UnitManager.tick_units — the
## in-game loop and the ONLY path that engages the kernels; plain unit.tick
## keeps the old object behaviour (the rest of the suite runs unchanged).

const TICK: float = 1.0 / 30.0

const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")
const SIEGE_SCENE: PackedScene = preload("res://scenes/units/siege_engine.tscn")


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
	return {"td": td, "nav": nav, "tribe0": tribe0, "tribe1": tribe1, "unit_manager": um}


func _free_world(w: Dictionary) -> void:
	w.unit_manager.free()


func _spawn(w: Dictionary, scene: PackedScene, tribe_id: int, at: Vector2) -> Unit:
	return w.unit_manager.spawn_unit(scene, tribe_id, Vector3(at.x, 0.0, at.y))


## One in-game frame: kernel pass + object ticks, then the manager systems.
func _frame(w: Dictionary) -> void:
	w.unit_manager.tick_units(TICK)
	w.unit_manager.tick(TICK)


## The C2.1 debug invariant: every VALIDATING handle (generation matches)
## points at the unit's actual attack_target object. Stale handles (generation
## mismatch) are legal — the kernel drops those units to their object tick.
func _check_target_handles(w: Dictionary, label: String) -> void:
	var um: UnitManager = w.unit_manager
	for i in range(um.units.size()):
		var t: int = um.soa_target[i]
		if t < 0:
			continue
		if t >= um.units.size() or um.soa_tgen[i] != um._slot_gen[t]:
			continue   # stale handle: never validates, so it is safe
		check(um.units[t] == um.units[i].attack_target,
			"%s: validating handle of slot %d points at attack_target" % [label, i])


func test_soa_target_mirrors_attack_target() -> void:
	var w: Dictionary = _make_world()
	var a: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(30, 30))
	var b: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector2(31, 30))
	a._begin_attack(b)
	check(w.unit_manager.soa_target[a._idx] == b._idx,
		"handle written on _begin_attack")
	check(w.unit_manager.soa_tgen[a._idx] == w.unit_manager._slot_gen[b._idx],
		"generation captured on _begin_attack")
	a._end_attack()
	check(w.unit_manager.soa_target[a._idx] == -1, "handle cleared on _end_attack")
	_free_world(w)


## Two warriors brawl through the kernel loop: the hold engages (soa_hold >= 0
## between strikes), strikes keep landing at the melee cadence, and the C2.1
## handle invariant holds on every frame.
func test_melee_hold_engages_and_strikes() -> void:
	seed(20260723)
	var w: Dictionary = _make_world()
	var a: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(30.0, 30.0))
	var b: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector2(30.8, 30.0))
	a.max_health = 100000
	a.health = a.max_health
	b.max_health = 100000
	b.health = b.max_health
	a._begin_attack(b)
	var held_seen: bool = false
	var strikes: int = 0
	var last_hp: int = b.health
	for i in range(91):   # ~3 s
		_frame(w)
		_check_target_handles(w, "melee brawl")
		if a._idx >= 0 and w.unit_manager.soa_hold[a._idx] >= 0.0:
			held_seen = true
		if b.health < last_hp:
			strikes += 1
			last_hp = b.health
	check(held_seen, "attacker was held by the kernel between strikes")
	check(strikes >= 3, "strikes keep landing under the kernel (got %d)" % strikes)
	check(strikes <= 6, "kernel does not double-tick the cooldown (got %d)" % strikes)
	check(a.state == Unit.State.ATTACK, "attacker still fighting")
	_free_world(w)


## A held attacker whose target dies drops out of the hold the same frame and
## retargets/idles instead of striking a corpse.
func test_hold_drops_on_target_death() -> void:
	seed(7)
	var w: Dictionary = _make_world()
	var a: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(30.0, 30.0))
	var b: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30.8, 30.0))
	b.max_health = 100000
	b.health = b.max_health
	a._begin_attack(b)
	for i in range(3):
		_frame(w)
	check(a._idx >= 0 and w.unit_manager.soa_hold[a._idx] >= 0.0,
		"attacker is held before the kill")
	b.take_damage(9999999)
	check(b.state == Unit.State.DEAD, "target died")
	check(w.unit_manager.soa_hold[a._idx] < 0.0,
		"hold cleared by the death cascade")
	_frame(w)
	check(a.attack_target != b, "attacker dropped the dead target")
	check(a.state != Unit.State.DEAD, "attacker alive and object-ticked again")
	_free_world(w)


## Swap-remove safety (the C2.1 core problem): removing a unit moves the last
## slot's unit into the freed index. Stale handles onto BOTH slots must stop
## validating (generation bump) instead of silently pointing at the wrong
## unit; the affected attacker re-syncs on its object tick and fights on.
func test_swap_remove_invalidates_stale_handles() -> void:
	seed(99)
	var w: Dictionary = _make_world()
	# Pair 1 far away from pair 2 (no cross-aggro).
	var a: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(20.0, 20.0))
	var b: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(20.8, 20.0))
	var c: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(60.0, 60.0))
	var d: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(60.8, 60.0))
	for u in [a, b, c, d]:
		u.max_health = 100000
		u.health = u.max_health
	a._begin_attack(b)
	c._begin_attack(d)
	for i in range(3):
		_frame(w)
	check(w.unit_manager.soa_hold[a._idx] >= 0.0, "a holds on b")
	check(w.unit_manager.soa_hold[c._idx] >= 0.0, "c holds on d")
	var d_old_idx: int = d._idx
	var d_old_gen: int = w.unit_manager._slot_gen[d_old_idx]
	# Remove b from the world (like entering a building): the last unit (d)
	# swaps into b's slot, so c's stored handle (old index of d) goes stale.
	w.unit_manager.remove_from_world(b)
	check(d._idx == 1, "last unit swapped into the freed slot")
	check(w.unit_manager._slot_gen[d_old_idx] != d_old_gen,
		"vacated slot's generation bumped")
	for i in range(3):
		_frame(w)
		_check_target_handles(w, "after swap-remove")
	check(c.attack_target == d, "c still fights d after the swap")
	check(w.unit_manager.soa_target[c._idx] == d._idx,
		"c's handle re-synced onto d's new slot")
	check(a.attack_target != b, "a dropped the removed (out-of-world) target")
	_free_world(w)


## Firewarrior fire stand: held by the fire kernel (soa_scan >= 0) between
## shots, fireballs keep coming — and the scan cadence survives, so a melee
## threat appearing on top of it still pulls it into self-defence quickly.
func test_fire_hold_fires_and_keeps_threat_reaction() -> void:
	seed(4242)
	var w: Dictionary = _make_world()
	var fw: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, Vector2(30.0, 30.0))
	var target: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(35.0, 30.0))
	# Pin the target at range: bind it into a melee brawl of its own (against a
	# friendly-of-fw brave) so retaliation does not walk it into the
	# firewarrior's melee range — the fire STAND is what this test is about.
	var pin: Unit = _spawn(w, BRAVE_SCENE, 0, Vector2(35.8, 30.0))
	fw.max_health = 100000
	fw.health = fw.max_health
	for u in [target, pin]:
		u.max_health = 100000
		u.health = u.max_health
	target._begin_attack(pin)
	var fire_held: bool = false
	var fired: bool = false
	for i in range(60):   # 2 s: engage + first shots
		_frame(w)
		_check_target_handles(w, "fire stand")
		if fw._idx >= 0 and w.unit_manager.soa_scan[fw._idx] >= 0.0:
			fire_held = true
		if not w.unit_manager.projectiles.is_empty():
			fired = true
	check(fw.attack_target == target, "firewarrior engaged the enemy")
	check(fire_held, "fire hold engaged between shots")
	check(fired, "fireballs keep flying under the kernel")
	# A melee threat walks onto the firewarrior: the kernel must keep dropping
	# it back on the scan cadence, so self-defence reacts within ~0.5 s.
	var thug: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector2(30.4, 30.0))
	thug.max_health = 100000
	thug.health = thug.max_health
	thug._begin_attack(fw)
	var reacted_at: int = -1
	for i in range(30):
		_frame(w)
		if fw.attack_target == thug:
			reacted_at = i
			break
	check(reacted_at >= 0, "held firewarrior still reacts to a melee threat")
	_free_world(w)


## Walk hold (C2.4): a plain move order crosses the map through the kernel —
## the unit is path-held while marching and arrives exactly at its target.
func test_walk_hold_marches_and_arrives() -> void:
	seed(3)
	var w: Dictionary = _make_world()
	var u: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(30.0, 30.0))
	var goal: Vector3 = Vector3(42.0, 0.0, 30.0)
	u.order_move(goal)
	var walk_held: bool = false
	var arrived_at: int = -1
	for i in range(300):
		_frame(w)
		if u._idx >= 0 and w.unit_manager.soa_hold[u._idx] >= 0.0 \
				and w.unit_manager.soa_mode[u._idx] == UnitManager.HOLD_MOVE:
			walk_held = true
		if u.state == Unit.State.IDLE:
			arrived_at = i
			break
	check(walk_held, "walker was held by the path kernel")
	check(arrived_at >= 0, "walker arrived and went idle")
	check(u._flat_dist(u.position, goal) < 0.5,
		"walker stands at the ordered point (dist %.2f)" % u._flat_dist(u.position, goal))
	_free_world(w)


## Chase hold (C2.4): an attacker approaches a distant enemy on its planned
## path through the kernel, arrives, and the fight starts normally.
func test_chase_hold_reaches_distant_target() -> void:
	seed(5)
	var w: Dictionary = _make_world()
	var a: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(30.0, 30.0))
	var b: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(40.0, 30.0))
	b.max_health = 100000
	b.health = b.max_health
	a.order_attack(b)
	var chase_held: bool = false
	var struck: bool = false
	var hp0: int = b.health
	for i in range(300):
		_frame(w)
		_check_target_handles(w, "chase")
		if a._idx >= 0 and w.unit_manager.soa_hold[a._idx] >= 0.0 \
				and w.unit_manager.soa_mode[a._idx] == UnitManager.HOLD_CHASE:
			chase_held = true
		if b.health < hp0:
			struck = true
			break
	check(chase_held, "attacker chased through the path kernel")
	check(struck, "attacker arrived and landed a strike")
	_free_world(w)


## Corpse hold: a fresh corpse parks in the kernel for its whole lie time and
## still expires (and frees its slot) on the normal schedule.
func test_corpse_hold_expires_on_schedule() -> void:
	var w: Dictionary = _make_world()
	var u: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30.0, 30.0))
	u.take_damage(9999)
	check(u.state == Unit.State.DEAD, "unit died")
	_frame(w)   # first dead tick enters the corpse hold
	check(w.unit_manager.soa_hold[u._idx] >= 0.0
		and w.unit_manager.soa_mode[u._idx] == UnitManager.HOLD_CORPSE,
		"corpse parked in the kernel")
	# Halfway through the lie time: still held, sink depth still zero.
	var half_ticks: int = int(Unit.CORPSE_DURATION * 0.5 * 30.0)
	for i in range(half_ticks):
		_frame(w)
	check(u in w.unit_manager.units, "corpse still lying at half time")
	check(u.corpse_sink_depth() == 0.0, "no sinking while held")
	# Run past lie + sink time: the corpse must expire and unregister.
	var rest: int = int((Unit.CORPSE_DURATION * 0.5 + Unit.CORPSE_SINK_DURATION) * 30.0) + 30
	for i in range(rest):
		_frame(w)
	check(u not in w.unit_manager.units, "corpse expired and left the registry")
	_free_world(w)


## Regression (user bug after C2): a vehicle wreck pushes its own sink visual
## from _tick_visual (object tick), so the corpse hold must NOT park it — under
## the kernel loop the burnt catapult stood fully intact for the whole lie time
## while the death cue had already played. A dead vehicle keeps its object
## ticks (its corpse timer counts live, headless proxy for the sink motion —
## the position.y drift itself is gated on is_inside_tree and only shows
## in-game); sprite corpses stay parked, and expiry keeps its schedule.
func test_vehicle_wreck_keeps_object_ticks_when_dead() -> void:
	var w: Dictionary = _make_world()
	var veh: SiegeEngine = w.unit_manager.spawn_unit(
		SIEGE_SCENE, 1, Vector3(30.0, 0.0, 30.0)) as SiegeEngine
	var corpse: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(40, 40))
	corpse.take_damage(9999)
	veh._destroy_vehicle(false)   # burn-out death: the sink path
	check(veh.state == Unit.State.DEAD, "vehicle died")
	_frame(w)   # first dead tick: the sprite corpse parks, the vehicle must not
	check(w.unit_manager.soa_mode[corpse._idx] == UnitManager.HOLD_CORPSE,
		"the sprite corpse still parks in the kernel (contrast)")
	check(w.unit_manager.soa_hold[veh._idx] < 0.0,
		"a dead vehicle is never parked in the corpse hold")
	for i in range(30):   # ~1 s
		_frame(w)
	check(veh._corpse_timer > 0.9,
		"the wreck's object tick keeps running (corpse timer live at %.2f s)"
			% veh._corpse_timer)
	var rest: int = int((Unit.CORPSE_DURATION + Unit.CORPSE_SINK_DURATION) * 30.0) + 30
	for i in range(rest):
		_frame(w)
	check(veh not in w.unit_manager.units, "the wreck expired on the corpse schedule")
	_free_world(w)


## Second row (2026-08-02, plans/08e): a waiter whose target's melee slots are
## full belongs to the kernel in BOTH of its situations — walking to its ring
## point (HOLD_WAIT_WALK) and standing settled there (HOLD_WAIT). Before the
## rework the hold gate measured the distance to the DEFENDER while the ring
## centres on the group anchor, and it covered only the standing case: in the
## stress battle 213 of ~225 waiters paid a full object tick every tick.
func test_waiter_holds_while_closing_up_and_standing() -> void:
	seed(4711)
	var w: Dictionary = _make_world()
	var defender: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector2(30.0, 30.0))
	defender.max_health = 100000
	defender.health = defender.max_health
	var attackers: Array[Unit] = []
	for k in range(Unit.MAX_MELEE_ATTACKERS):
		var a: Unit = _spawn(w, WARRIOR_SCENE, 0,
			Vector2(30.0 + 0.8 * cos(float(k)), 30.0 + 0.8 * sin(float(k))))
		a.max_health = 100000
		a.health = a.max_health
		a._begin_attack(defender)
		attackers.append(a)
	# The surplus attacker finds every slot taken -> second row.
	var waiter: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(36.0, 30.0))
	waiter.max_health = 100000
	waiter.health = waiter.max_health
	waiter.order_attack(defender)
	var start_dist: float = waiter._flat_dist(waiter.position, defender.position)
	var walk_held: bool = false
	var stand_held: bool = false
	var object_ticks: int = 0
	for i in range(240):   # 8 s
		_frame(w)
		if i % 30 == 0:
			_check_target_handles(w, "second row")   # sampled: 5 units x 240 = noise
		if waiter._idx < 0:
			break
		if w.unit_manager.soa_hold[waiter._idx] >= 0.0:
			if w.unit_manager.soa_mode[waiter._idx] == UnitManager.HOLD_WAIT_WALK:
				walk_held = true
			elif w.unit_manager.soa_mode[waiter._idx] == UnitManager.HOLD_WAIT:
				stand_held = true
		elif waiter._combat_waiting:
			object_ticks += 1
	check(walk_held, "the closing-up waiter walks in the kernel (HOLD_WAIT_WALK)")
	check(stand_held, "the settled waiter stands in the kernel (HOLD_WAIT)")
	check(waiter._flat_dist(waiter.position, defender.position) < start_dist - 1.0,
		"the kernel actually moved the waiter toward the fight (%.1f -> %.1f m)" % [
			start_dist, waiter._flat_dist(waiter.position, defender.position)])
	# Scan cadence (0.25 s) is the only regular object tick left for a waiter;
	# 8 s therefore allow ~32 of them plus a few event ticks.
	check(object_ticks < 60,
		"waiting costs object ticks only at the scan cadence (got %d in 240)" % object_ticks)
	_free_world(w)


## A freed melee slot promotes a KERNEL-HELD waiter immediately (the hold must
## not delay it to the next scan drop) — CombatGroup.promote_waiters.
func test_waiter_promotion_clears_the_kernel_hold() -> void:
	seed(4712)
	var w: Dictionary = _make_world()
	var defender: Unit = _spawn(w, WARRIOR_SCENE, 1, Vector2(30.0, 30.0))
	defender.max_health = 100000
	defender.health = defender.max_health
	var attackers: Array[Unit] = []
	for k in range(Unit.MAX_MELEE_ATTACKERS):
		var a: Unit = _spawn(w, WARRIOR_SCENE, 0,
			Vector2(30.0 + 0.8 * cos(float(k)), 30.0 + 0.8 * sin(float(k))))
		a.max_health = 100000
		a.health = a.max_health
		a._begin_attack(defender)
		attackers.append(a)
	var waiter: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(31.5, 31.5))
	waiter.max_health = 100000
	waiter.health = waiter.max_health
	waiter.order_attack(defender)
	for i in range(60):
		_frame(w)
	var group = defender.combat_group
	check(group != null and group.is_waiter(waiter), "surplus attacker sits in the second row")
	attackers[0]._end_attack()   # frees a slot -> promote_waiters
	check(w.unit_manager.soa_hold[waiter._idx] < 0.0,
		"promotion cleared the waiter's kernel hold at once")
	_frame(w)
	check(group.attacker_index(waiter) >= 0, "the promoted waiter took the free slot")
	_free_world(w)


## Knockback needs the object tick: a displace on a held unit clears its hold.
func test_hold_clears_on_displace() -> void:
	seed(11)
	var w: Dictionary = _make_world()
	var a: Unit = _spawn(w, WARRIOR_SCENE, 0, Vector2(30.0, 30.0))
	var b: Unit = _spawn(w, BRAVE_SCENE, 1, Vector2(30.8, 30.0))
	b.max_health = 100000
	b.health = b.max_health
	a._begin_attack(b)
	for i in range(3):
		_frame(w)
	check(w.unit_manager.soa_hold[a._idx] >= 0.0, "attacker is held")
	a.displace(Vector3(1, 0, 0), 0.3)
	check(w.unit_manager.soa_hold[a._idx] < 0.0, "displace cleared the hold")
	_frame(w)
	check(a.state == Unit.State.ATTACK, "still fighting after the shove")
	_free_world(w)
