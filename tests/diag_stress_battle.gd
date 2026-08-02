extends SceneTree

## Diagnostic (plans/08d stress follow-up): spawns the 4 stress-test armies,
## marches them at tick 150 and profiles the BATTLE window (ticks 300-449)
## per unit kind x state — the data basis for cutting the combat kernels.
## Per-call timing adds ~0.1 us overhead per unit; relative shares matter.
##
## Runs the REAL loop (2026-08-02): kernel pass first, then object ticks for
## the units the kernel did not hold — exactly what UnitManager.tick_units does
## in-game. The pre-C2 version object-ticked EVERY unit and therefore measured
## a world that no longer exists (74 ms/tick against 44-48 in benchmark_stress);
## its buckets were pure pre-kernel numbers. Besides the per-bucket object time
## the window now reports the kernel/object/manager split and, per hold mode,
## how many units the kernel carried and how many it dropped back — the drops
## ARE the remaining object cost, so this is the target list for further work.
## Unlike benchmark_stress this scenario casts no spells (pure melee/ranged mix).
##
## Run with: godot --headless -s res://tests/diag_stress_battle.gd

const TICK: float = 1.0 / 30.0
const TICKS: int = 450
const PROFILE_FROM: int = 300
const MARCH_TICK: int = 150

## Labels for the UnitManager.HOLD_* modes, indexed by their value.
const HOLD_NAMES: Array[String] = [
	"MELEE", "FIRE", "MOVE", "CHASE", "CHASE_FIRE", "WAIT", "CHASE_DIRECT",
	"CORPSE", "PANIC", "CAST", "WAIT_WALK"]

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")
const PREACHER_SCENE: PackedScene = preload("res://scenes/units/preacher.tscn")
const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")
const SIEGE_SCENE: PackedScene = preload("res://scenes/units/siege_engine.tscn")


func _initialize() -> void:
	var td: TerrainData = TerrainData.new()
	td.generate_island(1337)
	var nav: NavGrid = NavGrid.new(td)
	var tribes: Array[Tribe] = []
	for i in range(4):
		tribes.append(Tribe.new(i))
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, tribes)
	var center: Vector2i = Vector2i(td.size / 2, td.size / 2)
	var offsets: Array[Vector2i] = [
		Vector2i(0, 30), Vector2i(0, -30), Vector2i(-30, 0), Vector2i(30, 0)]
	for i in range(4):
		var anchor: Vector2i = center + offsets[i]
		var back: Vector2i = Vector2i(signi(offsets[i].x), signi(offsets[i].y))
		_spawn_army(um, nav, i, anchor)
		_spawn_sieges(um, nav, i, anchor, back)
		var cell: Vector2i = _walkable_near(nav, anchor + back * 8, 0)
		if cell.x >= 0:
			um.spawn_unit(SHAMAN_SCENE, i, nav.cell_to_world(cell))
	print("diag battle: %d Einheiten" % um.units.size())
	var commands: TribeCommands = TribeCommands.new()
	commands.setup(nav, null, um)
	var center_w: Vector3 = nav.cell_to_world(center)

	var key_us: Dictionary = {}
	var key_n: Dictionary = {}
	var key_drop_us: Dictionary = {}
	var key_drop_n: Dictionary = {}
	var key_nohold_us: Dictionary = {}
	var key_nohold_n: Dictionary = {}
	var why_us: Dictionary = {}
	var why_n: Dictionary = {}
	var held_n: PackedInt64Array = PackedInt64Array()
	var drop_n: PackedInt64Array = PackedInt64Array()
	held_n.resize(HOLD_NAMES.size())
	drop_n.resize(HOLD_NAMES.size())
	var kernel_us: int = 0
	var obj_us: int = 0
	var mgr_us: int = 0
	var total_us: int = 0
	var prof_ticks: int = TICKS - PROFILE_FROM
	# Hold mode per unit slot at kernel entry (-1 = object tick anyway); read
	# back right after the pass to tell "kernel carried it" from "kernel dropped
	# it". Sampled around the kernel only — no unregister can shift slots there.
	var pre_mode: PackedInt32Array = PackedInt32Array()
	for t in range(TICKS):
		if t == MARCH_TICK:
			for tribe in tribes:
				var squad: Array[Unit] = []
				for u in tribe.units:
					if not is_instance_valid(u) or u.state == Unit.State.DEAD:
						continue
					if u.unit_kind() == &"brave":
						continue
					squad.append(u)
				if not squad.is_empty():
					commands.order_move(squad, center_w, false, true)
		if t < PROFILE_FROM:
			um.tick_units(TICK)
			um.tick(TICK)
			continue
		var n: int = um.units.size()
		pre_mode.resize(n)
		for i in range(n):
			pre_mode[i] = um.soa_mode[i] if um.soa_hold[i] >= 0.0 else -1
		var t0: int = Time.get_ticks_usec()
		um._scan_cache_ready = true   # as in tick_units: the shared scan cache is live
		um._run_combat_kernels(TICK)
		var t1: int = Time.get_ticks_usec()
		kernel_us += t1 - t0
		for i in range(mini(n, um.units.size())):
			var pm: int = pre_mode[i]
			if pm < 0:
				continue
			if um.soa_hold[i] >= 0.0:
				held_n[pm] += 1
			else:
				drop_n[pm] += 1
		# Was this object tick a kernel DROP or a unit the kernel never held?
		# Captured before the first object tick runs: a corpse expiring mid-loop
		# swap-removes slots and would invalidate the index mapping.
		var was_held: Array[bool] = []
		was_held.resize(um._obj_tick.size())
		for j in range(um._obj_tick.size()):
			var idx: int = um._obj_tick[j]._idx
			was_held[j] = idx >= 0 and idx < pre_mode.size() and pre_mode[idx] >= 0
		for j in range(um._obj_tick.size()):
			var unit: Unit = um._obj_tick[j]
			if not is_instance_valid(unit):
				continue
			var key: String = "%s/%s" % [unit.unit_kind(),
				Unit.State.keys()[unit.state]]
			var u0: int = Time.get_ticks_usec()
			unit.tick(TICK)
			var du: int = Time.get_ticks_usec() - u0
			key_us[key] = int(key_us.get(key, 0)) + du
			key_n[key] = int(key_n.get(key, 0)) + 1
			if was_held[j]:
				key_drop_us[key] = int(key_drop_us.get(key, 0)) + du
				key_drop_n[key] = int(key_drop_n.get(key, 0)) + 1
			# Did this object tick hand the unit back to the kernel? A tick that
			# ends WITHOUT a hold pays full object cost again next tick — the
			# churn source. Classify the misses so the fix has an address.
			var idx2: int = unit._idx
			if idx2 >= 0 and idx2 < um.soa_hold.size() and um.soa_hold[idx2] < 0.0:
				key_nohold_n[key] = int(key_nohold_n.get(key, 0)) + 1
				key_nohold_us[key] = int(key_nohold_us.get(key, 0)) + du
				if unit.state == Unit.State.ATTACK:
					var why: String
					if unit.attack_target == null \
							or not is_instance_valid(unit.attack_target) \
							or unit.attack_target.state == Unit.State.DEAD:
						why = "kein Ziel"
					elif unit._combat_waiting:
						# Sub-classify: which gate refused the wait hold?
						if unit._burn_time > 0.0:
							why = "Waiter (brennt)"
						elif unit._knockback_remaining != Vector3.ZERO:
							why = "Waiter (Knockback)"
						elif Vector2(unit.position.x - unit._wait_center(unit.attack_target).x,
								unit.position.z - unit._wait_center(unit.attack_target).z).length() \
								> Unit.MELEE_WAIT_RADIUS + 0.6:
							why = "Waiter (nicht settled)"
						else:
							why = "Waiter (sonst)"
					elif unit._in_melee:
						why = "Nahkampf-Stand"
					elif not unit._path.is_empty():
						why = "Anmarsch (Pfad)"
					else:
						why = "sonstige"
					var wkey: String = "%s/%s" % [unit.unit_kind(), why]
					why_n[wkey] = int(why_n.get(wkey, 0)) + 1
					why_us[wkey] = int(why_us.get(wkey, 0)) + du
		var t2: int = Time.get_ticks_usec()
		obj_us += t2 - t1
		um.tick(TICK)
		mgr_us += Time.get_ticks_usec() - t2
		total_us += Time.get_ticks_usec() - t0
	var pt: float = float(prof_ticks)
	print("Fenster t%d-%d: gesamt Ø %.2f ms/Tick (inkl. Mess-Overhead) | Kernel Ø %.2f | Objekt Ø %.2f | Manager Ø %.2f ms" % [
		PROFILE_FROM, TICKS - 1, float(total_us) / pt / 1000.0,
		float(kernel_us) / pt / 1000.0, float(obj_us) / pt / 1000.0,
		float(mgr_us) / pt / 1000.0])
	print("Hold-Modi (Ø je Tick, gehalten -> gedroppt):")
	for m in range(HOLD_NAMES.size()):
		if held_n[m] + drop_n[m] == 0:
			continue
		var total_m: float = float(held_n[m] + drop_n[m]) / pt
		print("  %-14s: %7.1f gehalten | %7.1f gedroppt (%4.1f %% Drop-Quote)" % [
			HOLD_NAMES[m], float(held_n[m]) / pt, float(drop_n[m]) / pt,
			100.0 * float(drop_n[m]) / pt / maxf(total_m, 0.001)])
	print("Objekt-Ticks je kind/state (Drops = vom Kernel zurückgegeben, ohne Hold = Tick endet ungehalten):")
	var keys: Array = key_us.keys()
	keys.sort_custom(func(a, b): return int(key_us[a]) > int(key_us[b]))
	for key in keys:
		if int(key_us[key]) / prof_ticks < 100:
			continue   # < 0.1 ms/Tick: Rauschen
		print("  %-24s: Ø %6.2f ms/Tick | %7.2f µs/Einheit (Ø n=%d) | Drops Ø %5.2f ms (n=%d) | ohne Hold Ø %5.2f ms (n=%d)" % [
			key, float(key_us[key]) / pt / 1000.0,
			float(key_us[key]) / float(int(key_n[key])),
			int(key_n[key]) / prof_ticks,
			float(int(key_drop_us.get(key, 0))) / pt / 1000.0,
			int(key_drop_n.get(key, 0)) / prof_ticks,
			float(int(key_nohold_us.get(key, 0))) / pt / 1000.0,
			int(key_nohold_n.get(key, 0)) / prof_ticks])
	print("ATTACK-Ticks, die ohne Hold enden — Grund:")
	var wkeys: Array = why_us.keys()
	wkeys.sort_custom(func(a, b): return int(why_us[a]) > int(why_us[b]))
	for wkey in wkeys:
		print("  %-28s: Ø %6.2f ms/Tick | %7.2f µs/Einheit (Ø n=%d)" % [
			wkey, float(int(why_us[wkey])) / pt / 1000.0,
			float(int(why_us[wkey])) / float(int(why_n[wkey])),
			int(why_n[wkey]) / prof_ticks])
	commands.free()
	um.free()
	quit(0)


func _spawn_army(um: UnitManager, nav: NavGrid, tribe_id: int, anchor: Vector2i) -> void:
	var spawned: int = 0
	for radius in range(0, 40):
		for cell in AIController.ring_cells(anchor, radius):
			if spawned >= 1000:
				return
			if not nav.is_cell_walkable(cell):
				continue
			var scene: PackedScene = WARRIOR_SCENE
			if spawned >= 900:
				scene = PREACHER_SCENE
			elif spawned >= 600:
				scene = FIREWARRIOR_SCENE
			if um.spawn_unit(scene, tribe_id, nav.cell_to_world(cell)) == null:
				return
			spawned += 1


func _spawn_sieges(um: UnitManager, nav: NavGrid, tribe_id: int,
		anchor: Vector2i, back: Vector2i) -> void:
	var side: Vector2i = Vector2i(-back.y, back.x)
	for k in range(6):
		@warning_ignore("integer_division")
		var wish: Vector2i = anchor + back * 12 + side * ((k - 3) * 4)
		var cell: Vector2i = _walkable_near(nav, wish, 0)
		if cell.x < 0:
			continue
		var engine: Unit = um.spawn_unit(SIEGE_SCENE, tribe_id, nav.cell_to_world(cell))
		if engine == null:
			return
		for c in range(3):
			var crew_cell: Vector2i = _walkable_near(nav, cell, c + 1)
			if crew_cell.x < 0:
				continue
			var brave: Unit = um.spawn_unit(BRAVE_SCENE, tribe_id, nav.cell_to_world(crew_cell))
			if brave != null:
				brave.order_crew(engine)


func _walkable_near(nav: NavGrid, center: Vector2i, skip: int) -> Vector2i:
	var seen: int = 0
	for radius in range(0, 24):
		for cell in AIController.ring_cells(center, radius):
			if not nav.is_cell_walkable(cell):
				continue
			if seen >= skip:
				return cell
			seen += 1
	return Vector2i(-1, -1)
