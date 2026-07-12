extends SceneTree

## Phase-8.2 diagnosis script (NOT part of the suite): reproduces the debug
## battle headless and prints combat-state shares + mass-centroid drift, to
## verify the hypotheses from plans/08c (blob blindness via friend-counting
## scan cap, NW bucket-iteration bias -> north drift, low melee share).
## Run: godot --headless -s res://tests/diag_8_2.gd

const TICK: float = 1.0 / 30.0
const ARMY: int = 800
const WARRIOR_SHARE: float = 0.7
const REPORT_EVERY: int = 60
const TOTAL_TICKS: int = 900

const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")


func _initialize() -> void:
	var td: TerrainData = TerrainData.new()
	td.generate_island(1337)
	var nav: NavGrid = NavGrid.new(td)
	var tribes: Array[Tribe] = [Tribe.new(0), Tribe.new(1)]
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, tribes)
	var commands: TribeCommands = TribeCommands.new()
	commands.setup(nav, null, um)

	var center: Vector2i = Vector2i(td.size / 2, td.size / 2)
	_spawn_army(um, nav, 0, center + Vector2i(-26, 0))
	_spawn_army(um, nav, 1, center + Vector2i(26, 0))
	commands.order_move(um.get_units_of_tribe(0),
		nav.cell_to_world(center + Vector2i(26, 0)), false, true)
	commands.order_move(um.get_units_of_tribe(1),
		nav.cell_to_world(center + Vector2i(-26, 0)), false, true)
	print("diag: %d units total" % um.units.size())

	var start_centroid: Vector3 = _centroid(um)
	for t in range(TOTAL_TICKS + 1):
		if t % REPORT_EVERY == 0:
			_report(um, t, start_centroid)
		for unit in um.units.duplicate():
			if is_instance_valid(unit):
				unit.tick(TICK)
		um.tick(TICK)
	commands.free()
	um.free()
	quit(0)


func _spawn_army(um: UnitManager, nav: NavGrid, tribe_id: int, anchor: Vector2i) -> void:
	var warriors: int = int(float(ARMY) * WARRIOR_SHARE)
	var spawned: int = 0
	for radius in range(0, 40):
		for cell in AIController.ring_cells(anchor, radius):
			if spawned >= ARMY:
				return
			if not nav.is_cell_walkable(cell):
				continue
			var scene: PackedScene = WARRIOR_SCENE if spawned < warriors else FIREWARRIOR_SCENE
			um.spawn_unit(scene, tribe_id, nav.cell_to_world(cell))
			spawned += 1


func _centroid(um: UnitManager) -> Vector3:
	var c: Vector3 = Vector3.ZERO
	var n: int = 0
	for u in um.units:
		if u.state != Unit.State.DEAD:
			c += u.position
			n += 1
	return c / float(maxi(n, 1))


func _report(um: UnitManager, t: int, start: Vector3) -> void:
	var alive: int = 0
	var in_melee: int = 0
	var attack_no_slot: int = 0
	var attack_pursue: int = 0
	var moving: int = 0
	var idle: int = 0
	var other: int = 0
	for u in um.units:
		if u.state == Unit.State.DEAD:
			continue
		alive += 1
		match u.state:
			Unit.State.ATTACK:
				if u._in_melee:
					in_melee += 1
				elif u.attack_target != null and is_instance_valid(u.attack_target) \
						and not u._is_ranged() \
						and u not in u.attack_target.melee_attackers:
					attack_no_slot += 1
				else:
					attack_pursue += 1
			Unit.State.MOVE:
				moving += 1
			Unit.State.IDLE:
				idle += 1
			_:
				other += 1
	var c: Vector3 = _centroid(um)
	print("t=%4d alive=%4d melee=%4d atk_no_slot=%4d atk_pursue=%4d move=%4d idle=%4d other=%3d | drift dx=%+.2f dz=%+.2f" % [
		t, alive, in_melee, attack_no_slot, attack_pursue, moving, idle, other,
		c.x - start.x, c.z - start.z])
