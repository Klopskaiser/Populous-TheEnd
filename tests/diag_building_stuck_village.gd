extends SceneTree

## Diagnose 2026-11-23, zweiter Teil zu diag_building_stuck.gd: die volle KI-Partie
## zeigte keinen Fall, die KIs bauen aber mit grossem Abstand. Der Spieler baut eng.
## Hier stehen kleine Doerfer in kontrollierten Lagen (Eingang an der Nachbarwand,
## Eingang im Wasser, Eingang am Hang, Verteidiger an unerreichbarer Stelle, ...),
## eine Kriegertruppe greift im Angriffsmove an; ausgegeben wird je Lage, ob und wann
## jedes Gebaeude faellt und wer wie lange festsitzt.
##
##   godot --headless -s res://tests/diag_building_stuck_village.gd

const TICK: float = 0.1
const SIM_TICKS: int = 3000
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const CAMP_SCENE: PackedScene = preload("res://scenes/buildings/warrior_camp.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")
const FWCAMP_SCENE: PackedScene = preload("res://scenes/buildings/firewarrior_camp.tscn")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")


func _initialize() -> void:
	_scenario("Eingang an der Nachbarwand (0 m)", func(w: Dictionary) -> void:
		w.bm.place(HUT_SCENE, w.t1, Vector2i(40, 40), 0, true)
		w.bm.place(HUT_SCENE, w.t1, Vector2i(40, 40 + Hut.FOOTPRINT.y), 2, true))
	_scenario("Eingang im Wasser", func(w: Dictionary) -> void:
		var hut: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(40, 40), 0, true)
		var e: Vector2i = hut.entrance_cell()
		for dz in range(0, 3):
			for dx in range(-2, 3):
				_set_cell_height(w, e + Vector2i(dx, dz), -2.0))
	_scenario("Verteidiger auf Wasserinsel vor dem Eingang", func(w: Dictionary) -> void:
		var hut: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(40, 40), 0, true)
		var e: Vector2i = hut.entrance_cell()
		for dz in range(2, 8):
			for dx in range(-3, 4):
				if dz >= 4 and dz <= 5 and absi(dx) <= 1:
					continue   # the island
				_set_cell_height(w, e + Vector2i(dx, dz), -2.0)
		w.um.spawn_unit(BRAVE_SCENE, 1, w.nav.cell_to_world(e + Vector2i(0, 4))))
	_scenario("Verteidiger auf Wasserinsel vor dem Eingang, nur Nahkampf", func(w: Dictionary) -> void:
		var hut: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(40, 40), 0, true)
		var e: Vector2i = hut.entrance_cell()
		for dz in range(2, 8):
			for dx in range(-3, 4):
				if dz >= 4 and dz <= 5 and absi(dx) <= 1:
					continue   # the island
				_set_cell_height(w, e + Vector2i(dx, dz), -2.0)
		w.um.spawn_unit(BRAVE_SCENE, 1, w.nav.cell_to_world(e + Vector2i(0, 4))), true)
	_scenario("Eingang im Wasser, nur Nahkampf", func(w: Dictionary) -> void:
		var hut: Building = w.bm.place(HUT_SCENE, w.t1, Vector2i(40, 40), 0, true)
		var e: Vector2i = hut.entrance_cell()
		for dz in range(0, 3):
			for dx in range(-2, 3):
				_set_cell_height(w, e + Vector2i(dx, dz), -2.0), true)
	_scenario("enger Ring aus Huetten (1 m)", func(w: Dictionary) -> void:
		var fp: Vector2i = Hut.FOOTPRINT
		for i in range(3):
			for j in range(3):
				w.bm.place(HUT_SCENE, w.t1, Vector2i(36 + i * (fp.x + 1), 36 + j * (fp.y + 1)),
					(i + j) % 4, true))
	_scenario("Lager mit Ausbildungsschlange", func(w: Dictionary) -> void:
		var camp: TrainingBuilding = w.bm.place(CAMP_SCENE, w.t1, Vector2i(40, 40), 0, true) as TrainingBuilding
		for i in range(12):
			var b: Brave = w.um.spawn_unit(BRAVE_SCENE, 1, Vector3(30 + i, 0, 30)) as Brave
			b.order_train(camp))
	_scenario("Baustelle 8x8 mit Planierern, nur Nahkampf", func(w: Dictionary) -> void:
		var site: Building = w.bm.place(FWCAMP_SCENE, w.t1, Vector2i(40, 40), 0, false)
		# Uneven plot so the graders have work for a long time.
		for z in range(40, 49):
			for x in range(40, 49):
				w.td.set_vertex_height(x, z, 5.0 + 0.5 * float((x + z) % 3))
		w.nav.update_region(Rect2i(38, 38, 13, 13))
		site.init_construction()
		for i in range(8):
			var b: Brave = w.um.spawn_unit(BRAVE_SCENE, 1, Vector3(41 + i, 0, 50)) as Brave
			b.order_build(site), true)
	quit(0)


func _set_cell_height(w: Dictionary, c: Vector2i, h: float) -> void:
	for dz in range(2):
		for dx in range(2):
			w.td.set_vertex_height(c.x + dx, c.y + dz, h)
	w.nav.update_region(Rect2i(c - Vector2i.ONE, Vector2i(3, 3)))


func _scenario(title: String, setup: Callable, melee_only: bool = false) -> void:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = 5.0
	var nav: NavGrid = NavGrid.new(td)
	var t0: Tribe = Tribe.new(0)
	var t1: Tribe = Tribe.new(1)
	var wpm: WoodPileManager = WoodPileManager.new(); wpm.setup(td)
	var um: UnitManager = UnitManager.new(); um.setup(td, nav, [t0, t1] as Array[Tribe], null, wpm)
	var bm: BuildingManager = BuildingManager.new(); bm.setup(td, nav, um, wpm)
	um.building_manager = bm
	var w: Dictionary = {"td": td, "nav": nav, "t0": t0, "t1": t1, "um": um, "bm": bm, "wpm": wpm}
	setup.call(w)
	var attackers: Array[Unit] = []
	for i in range(10):
		var kind: PackedScene = FIREWARRIOR_SCENE if i % 4 == 3 and not melee_only else WARRIOR_SCENE
		var u: Unit = um.spawn_unit(kind, 0, Vector3(20.0 + float(i % 5), 0.0, 20.0 + float(i / 5)))
		attackers.append(u)
	var targets: Array[Building] = bm.get_buildings_of_tribe(1)
	var goal: Vector3 = targets[0].center_world()
	for u in attackers:
		u.order_move(goal, false, true)
	var still: Dictionary = {}
	var fell_at: Dictionary = {}
	for tick in range(SIM_TICKS):
		um.tick_units(TICK)
		um.tick(TICK)
		bm.tick(TICK)
		for b in targets:
			if not fell_at.has(b) and (not is_instance_valid(b) or b.health <= 0):
				fell_at[b] = tick
		if tick % 100 == 0 and tick > 0:
			var alive: int = 0
			for u in um.units:
				if is_instance_valid(u) and u.tribe_id == 1 and u.state != Unit.State.DEAD:
					alive += 1
			print("   t=%3.0f s: Verteidiger am Leben %d" % [float(tick) * TICK, alive])
		if fell_at.size() == targets.size():
			break
		for u in attackers:
			if not is_instance_valid(u) or u.state == Unit.State.DEAD:
				continue
			var s = still.get(u)
			if s == null or u.position.distance_to(s.pos) > 1.0:
				still[u] = {"pos": u.position, "since": tick}
	print("== %s: %d/%d Gebaeude gefallen" % [title, fell_at.size(), targets.size()])
	for b in targets:
		if fell_at.has(b):
			print("   faellt nach %.0f s" % (float(fell_at[b]) * TICK))
		else:
			print("   steht noch: %s hp %d/%d Raider %d" % [b.display_name(), b.health, b.max_health, b.raiders.size()])
	if fell_at.size() < targets.size():
		for u in attackers:
			if not is_instance_valid(u) or u.state == Unit.State.DEAD:
				continue
			var s = still.get(u)
			var since: float = float(SIM_TICKS - int(s.since)) * TICK if s != null else 0.0
			var b = u.attack_building
			var tgt = u.attack_target
			var txt: String = "%s %s steht %.0f s" % [u.unit_kind(), Unit.State.keys()[u.state], since]
			if b != null and is_instance_valid(b):
				var ent: Vector3 = b.entrance_world()
				txt += " | Gebaeude: Eingang %.1f m, begehbar=%s" % [Vector2(u.position.x - ent.x,
					u.position.z - ent.z).length(), nav.is_cell_walkable(b.entrance_cell())]
				var th: Unit = b.nearest_entrance_threat()
				if th != null:
					txt += ", Wache %s %.1f m, Insel %d/%d" % [th.unit_kind(), u.position.distance_to(th.position),
						nav.island_at(nav.world_to_cell(th.position)), nav.island_at(nav.world_to_cell(u.position))]
			if tgt != null and is_instance_valid(tgt):
				txt += " | Ziel %s %.1f m" % [tgt.unit_kind(), u.position.distance_to(tgt.position)]
			print("   " + txt)
	bm.free()
	um.free()
	wpm.free()
