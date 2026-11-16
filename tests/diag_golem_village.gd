extends SceneTree

## GOLEM IM DORF — Protokoll (Recherche 2026-11-16, kein Test).
##
## Ein Golem kommt an ein feindliches Dorf (Huetten im Raster, dazwischen Gassen);
## Verteidiger (Krieger, Feuerkrieger) stehen im Dorf. Protokolliert wird je
## Sekunde: Zustand, Ziel (Einheit oder Gebaeude) und dessen Luftlinie, Laenge des
## restlichen Wegs, erlittener Schaden, und jeder Angriff. So sieht man, ob sie sich
## erst lange durchs Dorf bewegt, statt zurueckzuschlagen, und wann sie springt.
## Hinweis: Kills heben die Lebensobergrenze des Golems neu an (hoechstens 1000) — die
## Spalte "Schaden bisher" springt dann; sie gilt nur bis zum ersten Kill.
## Aufruf:
##   godot --headless -s res://tests/diag_golem_village.gd -- [Stufe] [Befehl]
##   Befehl: idle (steht vor dem Dorf, Vorgabe), angriff (Angriffsbewegung zur
##   Dorfmitte), lauf (einfacher Bewegungsbefehl zur Dorfmitte), haus (Angriffsbefehl
##   auf die Huette in der Mitte)

const GOLEM_SCENE: PackedScene = preload("res://scenes/units/golem.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const FW_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const TICK: float = 0.05


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var level: int = int(args[0]) if args.size() > 0 and args[0].is_valid_int() else 3
	var modes: Array = [args[1]] if args.size() > 1 else ["idle", "angriff", "lauf", "haus"]
	for m in modes:
		_run(level, m)
	quit()


func _run(level: int, mode: String) -> void:
	seed(7)
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = 5.0
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
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(nav, bm, um, tm)
	# Dorf: 4 x 4 Huetten, Mitte bei (64, 64)
	var huts: Array = []
	for ix in range(4):
		for iz in range(4):
			var b: Building = bm.place(HUT_SCENE, t1, Vector2i(54 + ix * 6, 54 + iz * 6), 0, true)
			if b != null:
				huts.append(b)
	var centre_hut: Building = null
	var best: float = INF
	for b in huts:
		var d: float = b.center_world().distance_to(Vector3(64, 5, 64))
		if d < best:
			best = d
			centre_hut = b
	var g: Golem = um.spawn_unit(GOLEM_SCENE, 0, Vector3(64, 5, 40)) as Golem
	while g.level < level:
		g._credit_kill()
	g._stretch_queued = false
	g.max_health = 100000
	g.health = 100000
	g.facing = Vector3(0, 0, 1)
	g.snap_heading()
	# Verteidiger: Feuerkrieger am Dorfrand zum Golem hin, Krieger in den Gassen
	var defenders: Array = []
	for x in [56.0, 62.0, 68.0, 74.0]:
		defenders.append(um.spawn_unit(FW_SCENE, 1, Vector3(x, 5, 51)))
	for at in [Vector3(60, 5, 60), Vector3(66, 5, 66), Vector3(72, 5, 60), Vector3(60, 5, 72)]:
		defenders.append(um.spawn_unit(WARRIOR_SCENE, 1, at))
	for u in defenders:
		u.max_health = 100000
		u.health = 100000
	match mode:
		"angriff":
			g.order_move(Vector3(64, 5, 64), false, true)
		"lauf":
			g.order_move(Vector3(64, 5, 64))
		"haus":
			g.order_attack_building(centre_hut)
	print("== Stufe %d (%.1f m, Reichweite %.1f, Aggro %.1f), Befehl %s ==" % [level, g.height_m(), g.reach(), g.aggro_radius(), mode])
	var t: float = 0.0
	var hp0: int = g.health
	var last_pending: StringName = &""
	var first_attack: float = -1.0
	var walked: float = 0.0
	var last_pos: Vector3 = g.position
	var next_print: float = 0.0
	while t < 25.0:
		bm.tick(TICK)
		for u in um.units.duplicate():
			if is_instance_valid(u):
				u.tick(TICK)
		um.tick(TICK)
		t += TICK
		walked += Vector2(g.position.x - last_pos.x, g.position.z - last_pos.z).length()
		last_pos = g.position
		if g._pending_attack != &"" and last_pending == &"":
			if first_attack < 0.0:
				first_attack = t
			print("  %5.2f s  ANGRIFF %s (Haltung %s) | %s" % [t, g._pending_attack,
				"gebueckt" if g.stance == Golem.STANCE_CROUCH else "stehend", _ziel(g)])
		last_pending = g._pending_attack
		if t >= next_print:
			next_print += 1.0
			var rest: float = 0.0
			var p: Vector3 = g.position
			for q in g.get_remaining_path():
				rest += Vector2(q.x - p.x, q.z - p.z).length()
				p = q
			var nearest: float = INF
			for u in defenders:
				if is_instance_valid(u) and u.state != Unit.State.DEAD:
					nearest = minf(nearest, Vector2(u.position.x - g.position.x, u.position.z - g.position.z).length())
			print("  %5.2f s  %s | %s | Weg noch %.1f m | gelaufen %.1f m | Schaden bisher %d | naechster Feind %.1f m" % [
				t, Unit.State.keys()[g.state], _ziel(g), rest, walked, hp0 - g.health, nearest])
	print("  erster Angriff nach %.2f s, gelaufen %.1f m, Schaden bis dahin siehe oben" % [first_attack, walked])
	tc.free()
	tm.free()
	wpm.free()
	bm.free()
	um.free()


func _ziel(g: Golem) -> String:
	if g.attack_target != null and is_instance_valid(g.attack_target):
		var u: Unit = g.attack_target
		return "Ziel %s %.1f m (befohlen %s)" % [u.unit_kind(),
			Vector2(u.position.x - g.position.x, u.position.z - g.position.z).length(), g._target_ordered]
	if g.attack_building != null and is_instance_valid(g.attack_building):
		return "Ziel Gebaeude %.1f m" % g.attack_building.footprint_distance_to(Vector2(g.position.x, g.position.z))
	return "kein Ziel"
