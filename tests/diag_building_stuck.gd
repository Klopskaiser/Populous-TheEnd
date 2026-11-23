extends SceneTree

## Diagnose 2026-11-23 (Nutzermeldung): Gegnertruppen haengen manchmal an einzelnen
## Gebaeuden fest und greifen sie nicht wirklich an. Spielt eine volle KI-Partie
## (Aufbau wie diag_ai_match) und beobachtet jede Einheit, die ein Gebaeude angreift
## (attack_building gesetzt, kein Einheitenziel). Eine Einheit gilt als
## FESTGEFAHREN, wenn sie STUCK_SECONDS lang ihr Gebaeude im Visier hat, sich dabei
## kaum bewegt und das Gebaeude keinen Schaden nimmt. Fuer jede solche Einheit wird
## einmal die Lage ausgegeben: Abstand zum Eingang, Eingang begehbar, Torwaechter
## (nearest_entrance_threat) und warum er nicht angegriffen wird, Raiderplaetze.
## KEIN test_-Praefix, laeuft also nicht in der Suite; urteilt nicht, liefert Faelle.
##
##   godot --headless -s res://tests/diag_building_stuck.gd -- map=insel sim=1500 seed=7

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const SITE_SCENE: PackedScene = preload("res://scenes/buildings/reincarnation_site.tscn")
const TICK: float = 1.0 / 30.0
const START_BRAVES: int = 20
const STUCK_SECONDS: float = 20.0
const MAX_REPORTS: int = 40

## unit id -> {b, since, pos, hp}
var _watch: Dictionary = {}
var _reported: Dictionary = {}
var _reports: int = 0
var _causes: Dictionary = {}


func _initialize() -> void:
	var map_id: String = "insel"
	var sim: float = 1500.0
	var seed_value: int = 4242
	var tribe_count: int = 4
	var kinds: Array[String] = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("map="): map_id = a.trim_prefix("map=")
		elif a.begins_with("sim="): sim = float(a.trim_prefix("sim="))
		elif a.begins_with("seed="): seed_value = int(a.trim_prefix("seed="))
		elif a.begins_with("tribes="): tribe_count = clampi(int(a.trim_prefix("tribes=")), 2, 4)
		elif a.begins_with("personalities="):
			for k in a.trim_prefix("personalities=").split(","):
				kinds.append(String(k))
	seed(seed_value)
	var td: TerrainData = MapGenerator.create_terrain(map_id, seed_value)
	var nav: NavGrid = NavGrid.new(td)
	var tribes: Array[Tribe] = []
	for i in range(tribe_count): tribes.append(Tribe.new(i))
	var tm: TreeManager = TreeManager.new(); tm.setup(td, nav)
	var wpm: WoodPileManager = WoodPileManager.new(); wpm.setup(td)
	var um: UnitManager = UnitManager.new(); um.setup(td, nav, tribes, tm, wpm)
	var bm: BuildingManager = BuildingManager.new(); bm.setup(td, nav, um, wpm)
	um.building_manager = bm
	var tc: TribeCommands = TribeCommands.new(); tc.setup(nav, bm, um, tm)
	var ctx: SpellContext = SpellContext.new()
	ctx.terrain_data = td
	ctx.nav_grid = nav
	ctx.unit_manager = um
	ctx.building_manager = bm
	ctx.tree_manager = tm
	ctx.wood_pile_manager = wpm
	tc.spell_context = ctx
	root.add_child(tm); root.add_child(wpm); root.add_child(um); root.add_child(bm)
	tm.spawn_trees(240 * (td.size * td.size) / (128 * 128), seed_value)
	var anchors: Array[Vector2i] = MapGenerator.spawn_anchors(td, map_id, tribe_count)
	var ais: Array[AIController] = []
	for i in range(tribe_count):
		tribes[i].set_spells(Spell.create_player_set())
		_setup_base(tribes[i], anchors[i], tc, bm, um, tm, nav)
		var ai: AIController = AIController.new()
		ai.setup(tribes[i], tc, um, bm, tm, nav, anchors[i])
		if i < kinds.size():
			ai.personality = AIPersonality.from_id(StringName(kinds[i]))
		ais.append(ai)
	print("Karte %s, %.0f s, %d KIs, Seed %d" % [map_id, sim, tribe_count, seed_value])
	var frames: int = int(sim / TICK)
	var ai_accum: float = 0.0
	var watch_accum: float = 0.0
	var t: float = 0.0
	for f in range(frames):
		um.tick_units(TICK)
		um.tick(TICK); bm.tick(TICK); tm.tick(TICK)
		for tr in tribes: tr.tick(TICK)
		t += TICK
		ai_accum += TICK
		if ai_accum >= 1.0:
			ai_accum -= 1.0
			for ai in ais: ai.tick_ai()
		watch_accum += TICK
		if watch_accum >= 1.0:
			watch_accum -= 1.0
			_watch_assaults(um, nav, t)
		if _reports >= MAX_REPORTS:
			break
	print("=== Ursachen ===")
	for k in _causes.keys():
		print("  %-40s %d" % [k, int(_causes[k])])
	print("Festgefahrene Einheiten gemeldet: %d" % _reports)
	quit(0)


func _watch_assaults(um: UnitManager, nav: NavGrid, t: float) -> void:
	var seen: Dictionary = {}
	for u in um.units:
		if not is_instance_valid(u) or u.state != Unit.State.ATTACK:
			continue
		var b = u.attack_building
		if b == null or not is_instance_valid(b) or b.health <= 0:
			continue
		if u.attack_target != null and is_instance_valid(u.attack_target) \
				and u.attack_target.state != Unit.State.DEAD:
			continue
		var id: int = u.get_instance_id()
		seen[id] = true
		var w = _watch.get(id)
		if w == null or w.b != b or u.position.distance_to(w.pos) > 1.5 or b.health != w.hp:
			_watch[id] = {"b": b, "since": t, "pos": u.position, "hp": b.health}
			continue
		if t - float(w.since) >= STUCK_SECONDS and not _reported.has(id):
			_reported[id] = true
			_report(u, b, nav, t - float(w.since), t)
	for id in _watch.keys():
		if not seen.has(id):
			_watch.erase(id)


func _report(u: Unit, b: Building, nav: NavGrid, stuck: float, t: float) -> void:
	_reports += 1
	var ent: Vector3 = b.entrance_world()
	var ent_cell: Vector2i = b.entrance_cell()
	var d_ent: float = Vector2(u.position.x - ent.x, u.position.z - ent.z).length()
	var d_ctr: float = Vector2(u.position.x - b.center_world().x, u.position.z - b.center_world().z).length()
	var threat: Unit = b.nearest_entrance_threat()
	var cause: String = "?"
	var threat_txt: String = "-"
	if threat != null:
		threat_txt = "%s(T%d) st=%s airborne=%s targetable=%s in_world=%s d=%.1f" % [
			threat.unit_kind(), threat.tribe_id, Unit.State.keys()[threat.state],
			threat.is_airborne(), threat.is_targetable(), threat.in_world,
			Vector2(threat.position.x - ent.x, threat.position.z - ent.z).length()]
		if threat.is_airborne() and not u._is_ranged():
			cause = "Torwaechter in der Luft (Nahkampf kann nicht)"
		else:
			cause = "Torwaechter vorhanden, aber nicht angegriffen"
	elif u._is_ranged():
		cause = "Fernkampf: ausser Reichweite (%.1f m zur Mitte)" % d_ctr
	elif not nav.is_cell_walkable(ent_cell):
		cause = "Eingang nicht begehbar"
	elif d_ent > Unit.RAID_ENTER_RANGE:
		cause = "erreicht den Eingang nicht"
	elif not b.has_raider_room():
		cause = "kein Raiderplatz"
	else:
		cause = "sonstiges"
	_causes[cause] = int(_causes.get(cause, 0)) + 1
	print("t=%5.0f %s(T%d) -> %s(T%d) %.0f s fest | %s | Eingang %.1f m, Zelle %s begehbar=%s, Mitte %.1f m | Raider %d/%d | Pfad=%s | Wache: %s | bau=%s hp=%d/%d" % [
		t, u.unit_kind(), u.tribe_id, b.display_name(), b.tribe_id, stuck, cause,
		d_ent, ent_cell, nav.is_cell_walkable(ent_cell), d_ctr,
		b.raiders.size(), b.max_melee_raiders(), u._has_path(), threat_txt,
		b.under_construction, b.health, b.max_health])


## Mirrors diag_ai_match._setup_base.
func _setup_base(tribe: Tribe, anchor: Vector2i, tc: TribeCommands,
		bm: BuildingManager, um: UnitManager, tm: TreeManager, nav: NavGrid) -> void:
	var site: Building = null
	for radius in range(0, 40):
		if site != null:
			break
		for cell in AIController.ring_cells(anchor, radius):
			if tc.can_place_at(cell, ReincarnationSite.FOOTPRINT):
				site = bm.place(SITE_SCENE, tribe, cell, 0, true)
				break
	if site != null:
		um.spawn_unit(SHAMAN_SCENE, tribe.id, site.edge_spawn_position())
	for radius in range(0, 40):
		var placed: bool = false
		for cell in AIController.ring_cells(anchor + Vector2i(-8, -3), radius):
			if tc.can_place_at(cell, Hut.FOOTPRINT):
				bm.place(HUT_SCENE, tribe, cell, 0, true)
				placed = true
				break
		if placed:
			break
	var spawned: int = 0
	for radius in range(0, 40):
		if spawned >= START_BRAVES:
			break
		for cell in AIController.ring_cells(anchor + Vector2i(0, 6), radius):
			if spawned >= START_BRAVES:
				break
			if not nav.is_cell_walkable(cell):
				continue
			if (cell.x + cell.y) % 2 != 0:
				continue
			um.spawn_unit(BRAVE_SCENE, tribe.id, nav.cell_to_world(cell))
			spawned += 1
	var anchor_world: Vector3 = nav.cell_to_world(anchor)
	var have: int = 0
	for tree in tm.trees:
		if tree.position.distance_to(anchor_world) <= 20.0:
			have += 1
	var missing: int = 12 - have
	var step: int = 0
	for radius in range(10, 20):
		if missing <= 0:
			break
		for cell in AIController.ring_cells(anchor, radius):
			if missing <= 0:
				break
			step += 1
			if step % 3 != 0:
				continue
			if not nav.is_cell_walkable(cell):
				continue
			var blocked: bool = false
			for dz in range(-TreeManager.MIN_SPACING, TreeManager.MIN_SPACING + 1):
				for dx in range(-TreeManager.MIN_SPACING, TreeManager.MIN_SPACING + 1):
					if tm.has_tree_at(cell + Vector2i(dx, dz)):
						blocked = true
			if blocked:
				continue
			tm.spawn_tree(cell, TreeResource.MAX_STAGE)
			missing -= 1
