extends SceneTree

## Diagnostic (plans/08d stress follow-up): spawns the 4 stress-test armies,
## marches them at tick 150 and profiles the BATTLE window (ticks 300-449)
## per unit kind x state — the data basis for cutting the C2 kernels.
## Per-call timing adds ~0.1 us overhead per unit; relative shares matter.
##
## Run with: godot --headless -s res://tests/diag_stress_battle.gd

const TICK: float = 1.0 / 30.0
const TICKS: int = 450
const PROFILE_FROM: int = 300
const MARCH_TICK: int = 150

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
	var mgr_us: int = 0
	var total_us: int = 0
	var prof_ticks: int = TICKS - PROFILE_FROM
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
			for unit in um.units.duplicate():
				if is_instance_valid(unit):
					unit.tick(TICK)
			um.tick(TICK)
			continue
		var t0: int = Time.get_ticks_usec()
		for unit in um.units.duplicate():
			if not is_instance_valid(unit):
				continue
			var key: String = "%s/%s" % [unit.unit_kind(),
				Unit.State.keys()[unit.state]]
			var u0: int = Time.get_ticks_usec()
			unit.tick(TICK)
			var du: int = Time.get_ticks_usec() - u0
			key_us[key] = int(key_us.get(key, 0)) + du
			key_n[key] = int(key_n.get(key, 0)) + 1
		var m0: int = Time.get_ticks_usec()
		um.tick(TICK)
		mgr_us += Time.get_ticks_usec() - m0
		total_us += Time.get_ticks_usec() - t0
	print("Fenster t%d-%d: gesamt Ø %.2f ms/Tick (inkl. Mess-Overhead), Manager Ø %.2f ms" % [
		PROFILE_FROM, TICKS - 1,
		float(total_us) / float(prof_ticks) / 1000.0,
		float(mgr_us) / float(prof_ticks) / 1000.0])
	var keys: Array = key_us.keys()
	keys.sort_custom(func(a, b): return int(key_us[a]) > int(key_us[b]))
	for key in keys:
		var n: int = int(key_n[key])
		if int(key_us[key]) / prof_ticks < 100:
			continue   # < 0.1 ms/Tick: Rauschen
		print("  %-24s: Ø %6.2f ms/Tick | %7.2f µs/Einheit (Ø n=%d)" % [
			key, float(key_us[key]) / float(prof_ticks) / 1000.0,
			float(key_us[key]) / float(n), n / prof_ticks])
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
