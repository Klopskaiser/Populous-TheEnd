extends SceneTree

## Diagnose des KI-Aufbaus: Gebaeude-Zusammensetzung, offene Baustellen und
## Baumangebot nach N Sekunden, vier KIs auf einer echten Karte. KEIN test_-Praefix,
## laeuft also nicht in der Suite.
##
##   godot --headless -s res://tests/diag_ai_buildup.gd -- map=bergpass sim=600
##
## Startbedingungen wie main.gd._setup_skirmish_base (1 Huette, 20 Braves, Baeume um
## den Anker), damit der Befund uebertragbar ist.
##
## Stand 2026-08-05 (vor 10g Teil 1): jede KI haelt 2 Baustellen offen und stellt in
## 600 s KEINE davon fertig — die headless Reproduktion des Nutzerreports "die KI
## macht etliche Baustellen auf, ohne dort Leute zum Bauen hinzuschicken". Nach dem
## ersten Schwung (alle 20 Braves noch idle) sind die Braves in Faell-Trupps
## gebunden, und BuildingManager._recruit_workers findet niemanden mehr.

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const SITE_SCENE: PackedScene = preload("res://scenes/buildings/reincarnation_site.tscn")

func _initialize() -> void:
	var map_id: String = "bergpass"
	var sim: float = 600.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("map="): map_id = a.trim_prefix("map=")
		elif a.begins_with("sim="): sim = float(a.trim_prefix("sim="))
	var td: TerrainData = MapGenerator.create_terrain(map_id, 12345)
	var nav: NavGrid = NavGrid.new(td)
	var tribes: Array[Tribe] = []
	for i in range(4): tribes.append(Tribe.new(i))
	var tm: TreeManager = TreeManager.new(); tm.setup(td, nav)
	var wpm: WoodPileManager = WoodPileManager.new(); wpm.setup(td)
	var um: UnitManager = UnitManager.new(); um.setup(td, nav, tribes, tm, wpm)
	var bm: BuildingManager = BuildingManager.new(); bm.setup(td, nav, um, wpm)
	um.building_manager = bm
	var tc: TribeCommands = TribeCommands.new(); tc.setup(nav, bm, um, tm)
	root.add_child(tm); root.add_child(wpm); root.add_child(um); root.add_child(bm)
	tm.spawn_trees(240 * (td.size * td.size) / (128 * 128), 999)
	var anchors: Array[Vector2i] = MapGenerator.spawn_anchors(td, map_id, 4)
	var ais: Array = []
	for i in range(4):
		bm.place(SITE_SCENE, tribes[i], anchors[i], 0, true)
		bm.place(HUT_SCENE, tribes[i], anchors[i] + Vector2i(6, 0), 0, true)
		# Baeume um den Anker, wie main.gd._ensure_trees_near: ohne die scheitert
		# MIN_TREES_NEAR_PLOT und die KI findet ueberhaupt keinen Bauplatz.
		var planted: int = 0
		for r in range(8, 26):
			for cell in AIController.ring_cells(anchors[i], r):
				if planted >= 60: break
				if not nav.is_cell_walkable(cell) or tm.has_tree_at(cell): continue
				if (cell.x + cell.y) % 3 != 0: continue
				tm.spawn_tree(cell, TreeResource.MAX_STAGE)
				planted += 1
		for j in range(20):
			um.spawn_unit(BRAVE_SCENE, i, nav.cell_to_world(anchors[i] + Vector2i(j % 5 - 2, 3)))
		um.spawn_unit(SHAMAN_SCENE, i, nav.cell_to_world(anchors[i] + Vector2i(0, -3)))
		var ai: AIController = AIController.new()
		ai.setup(tribes[i], tc, um, bm, tm, nav, anchors[i])
		ai.stagger_offset(float(i) / 4.0)
		root.add_child(ai)
		ais.append(ai)
	var steps: int = int(sim * 30.0)
	for s in range(steps):
		# tick_units ZUERST: UnitManager._physics_process macht genau das, und ohne
		# den Aufruf tickt keine einzige Einheit (der Fehler in der ersten Fassung
		# dieser Diagnose — sie sah einen voellig stillstehenden Stamm).
		um.tick_units(1.0 / 30.0)
		um.tick(1.0 / 30.0); bm.tick(1.0 / 30.0); tm.tick(1.0 / 30.0)
		for t in tribes: t.tick(1.0 / 30.0)
		for ai in ais: ai._process(1.0 / 30.0)
	print("Karte %s, %.0f s, 4 KIs | Baeume gesamt %d" % [map_id, sim, tm.trees.size()])
	# Herumliegendes Holz: Stapel, die NICHT im Absorptionsradius eines eigenen
	# Gebaeudes liegen — genau das, was der Nutzer als "Riesenstapel" gemeldet hat.
	var loose: int = 0
	var loose_piles: int = 0
	for pile in wpm.piles:
		if not is_instance_valid(pile) or pile.amount <= 0: continue
		var served: bool = false
		for t in tribes:
			for b in t.buildings:
				if not is_instance_valid(b) or b.health <= 0: continue
				var d: Vector3 = b.delivery_point()
				if Vector2(d.x, d.z).distance_to(Vector2(pile.position.x, pile.position.z)) 						<= Building.ABSORB_RADIUS:
					served = true
					break
			if served: break
		if not served:
			loose += pile.amount
			loose_piles += 1
	print("  Holz frei herumliegend: %d in %d Stapeln (von %d gesamt)" % [
		loose, loose_piles, wpm.total_wood()])
	print("  Fahrzeuge bemannt: %d | Verworfene Baustellen: %d | Nachschub-Truppe: %d" % [
		AIController.dbg_vehicles_crewed, AIController.dbg_site_scraps,
		AIController.dbg_supply_runs])
	print("  Bauarbeiter zugewiesen: %d | Miliz-Befehle: %d | Bedrohungs-Ticks: %d" % [
		AIController.dbg_builders_assigned, AIController.dbg_militia_orders,
		AIController.dbg_threat_ticks])
	for i in range(4):
		var idle: int = 0
		for u in tribes[i].units:
			if is_instance_valid(u) and u.state == Unit.State.IDLE and u is Brave:
				idle += 1
		var st: Dictionary = {}
		for u in tribes[i].units:
			if not is_instance_valid(u) or not (u is Brave): continue
			var k: String = Unit.State.keys()[u.state]
			st[k] = int(st.get(k, 0)) + 1
		if i == 0:
			var seen: Dictionary = {}
			for u in tribes[i].units:
				if not is_instance_valid(u) or not (u is Brave): continue
				if u.state != Unit.State.BUILD: continue
				var j = (u as Brave).job
				var key: String = "job=%s under_constr=%s upgrading=%s dem=%s hp=%d/%d task=%s" % [
					("null" if not is_instance_valid(j) else j.get_script().resource_path.get_file().get_basename()),
					("-" if not is_instance_valid(j) else str(j.under_construction)),
					("-" if not is_instance_valid(j) else str(j.upgrading)),
					("-" if not is_instance_valid(j) else str(j.demolishing)),
					(0 if not is_instance_valid(j) else j.health),
					(0 if not is_instance_valid(j) else j.max_health),
					Brave.Task.keys()[(u as Brave).task]]
				seen[key] = int(seen.get(key, 0)) + 1
			for k in seen:
				print("     BUILD-Brave x%d: %s" % [seen[k], k])
		print("  KI %d: idle Braves %d, Bravestrom %.1f/min, Zustaende %s" % [i, idle,
			ais[i].build_tick_cache().brave_stream, str(st)])
		var veh: Dictionary = {}
		for u in tribes[i].units:
			if not is_instance_valid(u) or u.state == Unit.State.DEAD: continue
			var uk: String = str(u.unit_kind())
			if uk in ["siege", "fireram", "airship"]:
				veh[uk] = int(veh.get(uk, 0)) + 1
		var stages: Dictionary = {}
		var racks: int = 0
		for b in tribes[i].buildings:
			if not is_instance_valid(b) or b.health <= 0: continue
			if b is Hut:
				var stage_i: int = (b as Hut).upgrade_stage
				stages[stage_i] = int(stages.get(stage_i, 0)) + 1
			elif b is WoodDepot and (b as WoodDepot).stored_wood() > 0:
				racks += 1
		if not stages.is_empty():
			print("     Huetten-Ausbaustufen: %s | gefuellte Regale: %d" % [
				str(stages), racks])
		if not veh.is_empty():
			print("     Fahrzeuge: %s" % str(veh))
		for b in tribes[i].buildings:
			if is_instance_valid(b) and b.under_construction:
				print("     Baustelle %s @%s: Arbeiter %d, Holz %d/%d, stalled %s, Fortschritt %.2f" % [
					b.get_script().resource_path.get_file().get_basename(), str(b.cell),
					b.workers.size(), b.wood_delivered, b.wood_cost,
					str(b.wood_stalled), b.build_progress])
		print("  Anker %d: Baeume im Umkreis 22: %d | Baustellen: %d" % [i,
			tm.count_trees_near(nav.cell_to_world(anchors[i]), 22.0),
			ais[i].build_tick_cache().sites.size()])
	for i in range(4):
		var c: Dictionary = {}
		for b in tribes[i].buildings:
			if not is_instance_valid(b) or b.health <= 0: continue
			var k: String = b.get_script().resource_path.get_file().get_basename()
			c[k] = int(c.get(k, 0)) + 1
		print("  KI %d: pop %4d | %s" % [i, tribes[i].population(), str(c)])
	quit(0)
