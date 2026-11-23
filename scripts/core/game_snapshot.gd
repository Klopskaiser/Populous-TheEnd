class_name GameSnapshot extends RefCounted

## The state of a running match as plain data, and back (save game, 2026-11-23).
##
## capture() reads the world through a SnapshotContext into a Dictionary of
## engine-native values (Vector3, Packed*Array, int, float, String) — SaveGame
## writes it with store_var, so nothing is lost to a text format. apply()
## rebuilds the world from it into freshly set-up managers, through the same
## spawn/placement APIs the match setup uses (BuildingManager.place,
## UnitManager.spawn_unit, TreeManager.spawn_tree, ...), and returns the restored
## units and buildings in save order (AI and survival reference units by index).
##
## WHAT IS SAVED: terrain heights (all deformations), trees (cell, type, growth),
## wood piles (also the racks' stock), buildings (type, tribe, cell, orientation,
## health, construction / demolition / repair / upgrade progress, rally point,
## pause, hut stage and timers, crews of huts and towers, workers of workshops and
## foresters, training queue and trainee with its timer, reincarnation timer),
## units of every kind (position, facing, health, move route, crew seat on a
## vehicle, construction job, hypnosis, golem size/level/kills/settings/sitting,
## Genesis stage/experience/wood, vehicle damage), tribes (mana, debt, spell
## charges and switches, growth and vehicle settings, statistics, eliminated).
##
## WHAT IS NOT: anything in flight or burning — projectiles, spell effects in the
## air (tornado, swarm, firestorm, lava flows), burning units/trees/piles, panic,
## throws and rolls (a thrown unit lands where it was), corpses, timed buffs,
## combat engagements and target locks (units pick their fights again), paths
## (a moving unit gets its route re-issued), selection. A trainee restarts nothing:
## its remaining training time is kept.

## Bumped whenever the data layout changes incompatibly (SaveGame.FORMAT_VERSION
## is the file format; this is the content).
const DATA_VERSION: int = 1


# --- Capture -------------------------------------------------------------------------

static func capture(ctx: SnapshotContext) -> Dictionary:
	var units: Array[Unit] = _saved_units(ctx)
	var unit_index: Dictionary = {}
	for i in range(units.size()):
		unit_index[units[i]] = i
	var buildings: Array[Building] = _saved_buildings(ctx)
	var building_index: Dictionary = {}
	for i in range(buildings.size()):
		building_index[buildings[i]] = i
	var piles: Array[WoodPile] = _saved_piles(ctx)
	var pile_index: Dictionary = {}
	for i in range(piles.size()):
		pile_index[piles[i]] = i

	var data: Dictionary = {
		"data_version": DATA_VERSION,
		"match_config": ctx.match_config.to_dict() if ctx.match_config != null else {},
		"map_id": ctx.map_id,
		"terrain": {
			"size": ctx.terrain_data.size,
			"heights": ctx.terrain_data.heights.duplicate(),
		},
		"trees": _capture_trees(ctx),
		"piles": piles.map(func(p: WoodPile) -> Dictionary:
			return {"pos": p.position, "amount": p.amount, "clickable": p.clickable}),
		"buildings": buildings.map(func(b: Building) -> Dictionary:
			return _capture_building(b, unit_index, pile_index)),
		"units": units.map(func(u: Unit) -> Dictionary:
			return _capture_unit(u, unit_index, building_index)),
		"tribes": ctx.tribes.map(func(t: Tribe) -> Dictionary: return _capture_tribe(t)),
		"ai": ctx.ai_controllers.map(func(ai) -> Dictionary: return ai.save_state()),
	}
	if ctx.survival != null:
		data["survival"] = ctx.survival.save_state(unit_index)
	if ctx.game_state != null:
		data["tracking"] = ctx.game_state.save_tracking()
	if ctx.camera != null and ctx.camera.has_method("save_view"):
		data["camera"] = ctx.camera.save_view()
	return data


## Every living unit of every tribe, housed ones (huts, workshops, training) included.
## Corpses and doomed bodies (struck dead in mid-air) are gone in the save.
static func _saved_units(ctx: SnapshotContext) -> Array[Unit]:
	var out: Array[Unit] = []
	for tribe in ctx.tribes:
		for u in tribe.units:
			if not is_instance_valid(u) or u.state == Unit.State.DEAD or u.doomed:
				continue
			if u.scene_file_path == "":
				continue   # not built from a scene — cannot be re-created
			out.append(u)
	return out


static func _saved_buildings(ctx: SnapshotContext) -> Array[Building]:
	var out: Array[Building] = []
	if ctx.building_manager == null:
		return out
	for b in ctx.building_manager.buildings:
		if not is_instance_valid(b) or b._destroyed or b.health <= 0:
			continue
		if b.scene_file_path == "" or b.tribe_id < 0 or b.tribe_id >= ctx.tribes.size():
			continue
		out.append(b)
	return out


static func _saved_piles(ctx: SnapshotContext) -> Array[WoodPile]:
	var out: Array[WoodPile] = []
	if ctx.wood_pile_manager == null:
		return out
	for p in ctx.wood_pile_manager.piles:
		if is_instance_valid(p) and not p.is_queued_for_deletion() and p.amount > 0:
			out.append(p)
	return out


static func _capture_trees(ctx: SnapshotContext) -> Array:
	var out: Array = []
	if ctx.tree_manager == null:
		return out
	for tree in ctx.tree_manager.trees:
		if not is_instance_valid(tree) or tree.is_queued_for_deletion():
			continue
		var cell: Vector2i = ctx.tree_manager._tree_cells.get(tree,
			ctx.nav_grid.world_to_cell(tree.position))
		out.append({"cell": cell, "type": int(tree.type), "growth": tree.growth})
	return out


static func _indices(list: Array, index: Dictionary) -> Array:
	var out: Array = []
	for item in list:
		if is_instance_valid(item) and index.has(item):
			out.append(index[item])
	return out


static func _capture_building(b: Building, unit_index: Dictionary, pile_index: Dictionary) -> Dictionary:
	var d: Dictionary = {
		"scene": b.scene_file_path,
		"tribe": b.tribe_id,
		"cell": b.cell,
		"orientation": b.orientation,
		"health": b.health,
		"under_construction": b.under_construction,
		"build_progress": b.build_progress,
		"wood_delivered": b.wood_delivered,
		"foundation_done": b.foundation_done,
		"site_hp_cap": b._site_hp_cap,
		"rally": b.rally_point,
		"paused": b.paused,
		"repair_wood": b.repair_wood,
		"demolishing": b.demolishing,
	}
	if b.demolishing:
		d["demolish"] = [b._demolish_start_progress, b._demolish_refund_total,
			b._demolish_refund_paid]
	if b is Hut:
		var hut: Hut = b as Hut
		d["hut"] = {
			"stage": hut.upgrade_stage,
			"upgrading": hut.upgrading,
			"upgrade_wood": hut.upgrade_wood,
			"upgrade_work": hut._upgrade_work,
			"upgrade_timer": hut._upgrade_timer,
			"manual_override": hut.manual_crew_override,
			"spawn_timer": hut.spawn_timer,
			"growth_timer": hut._growth_timer,
		}
		d["crew"] = _indices(hut.crew, unit_index)
	elif b is Watchtower:
		d["crew"] = _indices((b as Watchtower).crew, unit_index)
	if b is TrainingBuilding:
		var tb: TrainingBuilding = b as TrainingBuilding
		d["training"] = {
			"trainee": unit_index.get(tb.trainee, -1) if is_instance_valid(tb.trainee) else -1,
			"queue": _indices(tb.incoming, unit_index),
			"timer": tb._train_timer,
			"queue_limit": tb.queue_limit,
		}
	if b is Workshop:
		var ws: Workshop = b as Workshop
		d["workshop"] = {"active": ws.production_active, "work": ws.work_done}
		d["occupants"] = _occupants(ws.occupants, unit_index, &"workshop_inside")
	elif b is Forester:
		d["occupants"] = _occupants((b as Forester).occupants, unit_index, &"forester_inside")
	if b is WoodDepot:
		d["stock"] = _indices((b as WoodDepot)._stock_piles, pile_index)
	if b is ReincarnationSite:
		var site: ReincarnationSite = b as ReincarnationSite
		d["site"] = [site.respawn_timer, site.respawn_pending, site._saw_followers]
	return d


## [[unit index, inside], ...] of a workshop's / forester's workers.
static func _occupants(list: Array, unit_index: Dictionary, inside_flag: StringName) -> Array:
	var out: Array = []
	for brave in list:
		if is_instance_valid(brave) and unit_index.has(brave):
			out.append([unit_index[brave], bool(brave.get(inside_flag))])
	return out


static func _capture_unit(u: Unit, unit_index: Dictionary, building_index: Dictionary) -> Dictionary:
	var d: Dictionary = {
		"scene": u.scene_file_path,
		"tribe": u.tribe_id,
		"pos": u.position,
		"facing": u.facing,
		"health": u.health,
		"max_health": u.max_health,
	}
	if u.patrol:
		d["patrol"] = true
	if u.is_hypnotized() and u._hypnosis_origin != null:
		d["hypnosis"] = [u._hypnosis_origin.id, u._hypnosis_time]
	# Seat on a vehicle (walking to it or aboard).
	var engine = u.siege_engine
	if engine != null and is_instance_valid(engine) and unit_index.has(engine):
		d["crew_of"] = unit_index[engine]
		d["boarded"] = u.siege_boarded
	# Walking to a hut / tower to man it (the housed ones are in the building's list).
	var g = u.garrison_target
	if g != null and is_instance_valid(g) and not u.garrison_housed and building_index.has(g):
		d["garrison_go"] = building_index[g]
	if u is Brave:
		var brave: Brave = u as Brave
		if brave.carried_wood > 0:
			d["wood"] = brave.carried_wood
			if brave.carry_hold:
				d["carry_hold"] = true
		var job = brave.job
		if job != null and is_instance_valid(job) and building_index.has(job) \
				and not (job is Workshop):
			d["job"] = building_index[job]
	if u is Golem:
		var golem: Golem = u as Golem
		d["golem"] = _capture_golem(golem)
		if golem.is_sitting():
			# Seated, her position is the middle of the seat behind her feet; the
			# restore sits her down again from her FEET (sit_down -> find_seat).
			d["pos"] = golem.position + golem.heading() * golem.seat_back_m()
	if u is FireRam:
		d["fire_hits"] = (u as FireRam)._fire_hits
	elif u is Airship:
		d["hull_hits"] = (u as Airship)._hull_hits
	# A walking route (the one that is not part of a binding above).
	if u.state == Unit.State.MOVE and not u.waypoint_queue.is_empty() \
			and not d.has("crew_of") and not d.has("garrison_go") and not d.has("job"):
		d["route"] = PackedVector3Array(u.waypoint_queue)
		d["aggressive"] = u.move_aggressive
	return d


static func _capture_golem(g: Golem) -> Dictionary:
	var d: Dictionary = {
		"kills": g.kills,
		"level": g.level,
		"growth_steps": g.growth_steps,
		"life_left": g.life_left,
		"sitting": g.is_sitting() or g._wants_sit,
		"stationary": g.sit_stationary,
		"sit_attacks": g.sit_attacks_enabled,
		"stomp": g.stomp_enabled,
	}
	if not g._flatten_natural.is_empty():
		# The ground her levelling lowered, with its height before: the level of
		# the plate comes from it (Golem.flatten_plan).
		d["natural"] = [PackedInt32Array(g._flatten_natural.keys()),
			PackedFloat32Array(g._flatten_natural.values())]
	if g is GenesisGolem:
		var gg: GenesisGolem = g as GenesisGolem
		d["genesis"] = [gg.stage, gg.brave_xp, gg.wood_growth_m, gg.wood, gg.trees_felled]
	return d


static func _capture_tribe(t: Tribe) -> Dictionary:
	var spells: Array = []
	for spell in t.spells:
		spells.append({"id": String(spell.id), "charges": spell.charges,
			"charge_mana": spell.charge_mana, "active": spell.active})
	return {
		"id": t.id,
		"mana": t.mana,
		"upkeep_debt": t._upkeep_debt,
		"growth_mode": int(t.growth_mode),
		"auto_recrew": t.auto_recrew_vehicles,
		"upgrades_allowed": t.upgrades_allowed,
		"max_catapults": t.max_catapults,
		"max_fire_rams": t.max_fire_rams,
		"max_airships": t.max_airships,
		"eliminated": t.eliminated,
		"ritual_sacrifices": t.ritual_sacrifices,
		"ai_personality_name": t.ai_personality_name,
		"spells": spells,
		"stats": {
			"kills_by_golems": t.kills_by_golems,
			"kills_other": t.kills_other,
			"units_lost": t.units_lost,
			"peak_population": t.peak_population,
		},
	}


# --- Restore -------------------------------------------------------------------------

## The saved heights replace the generated map (before the Terrain mesh, NavGrid
## and everything else are built from it). False when the save does not fit the
## map size (then the generated map stays).
static func apply_terrain(td: TerrainData, data: Dictionary) -> bool:
	var terrain: Dictionary = data.get("terrain", {})
	var heights: PackedFloat32Array = terrain.get("heights", PackedFloat32Array())
	if int(terrain.get("size", -1)) != td.size or heights.size() != td.heights.size():
		push_warning("Spielstand: Terraingröße passt nicht zur Karte — Höhen verworfen")
		return false
	td.heights = heights.duplicate()
	td._average_height = -INF
	return true


## Rebuilds trees, piles, buildings, units and tribe state into the (empty, set-up)
## managers of `ctx`. The terrain must already carry the saved heights (apply_terrain
## before the NavGrid was built). Returns {"units": Array, "buildings": Array} in
## save order (entries may be null where something could not be restored).
static func apply(data: Dictionary, ctx: SnapshotContext) -> Dictionary:
	_restore_trees(data.get("trees", []), ctx)
	var piles: Array = _restore_piles(data.get("piles", []), ctx)
	var building_data: Array = data.get("buildings", [])
	var buildings: Array = []
	for d in building_data:
		buildings.append(_restore_building(d, ctx))
	var unit_data: Array = data.get("units", [])
	var units: Array = []
	for d in unit_data:
		units.append(_restore_unit(d, ctx))
	# Bindings need every unit and building in place. Units a building takes in
	# (crews, workers, trainees) stay exactly where they were saved.
	var housed: Dictionary = _building_bound_units(building_data)
	for i in range(units.size()):
		if units[i] != null:
			_restore_unit_bindings(units[i], unit_data[i], units, buildings, ctx,
				housed.has(i))
	for i in range(buildings.size()):
		if buildings[i] != null:
			_restore_building_people(buildings[i], building_data[i], units, piles)
	# Golems sit down last: everything around them stands where it belongs.
	for i in range(units.size()):
		if units[i] is Golem and bool(unit_data[i].get("golem", {}).get("sitting", false)):
			_restore_sitting(units[i] as Golem)
	var tribe_data: Array = data.get("tribes", [])
	for td in tribe_data:
		var id: int = int(td.get("id", -1))
		if id >= 0 and id < ctx.tribes.size():
			_restore_tribe(ctx.tribes[id], td)
	return {"units": units, "buildings": buildings}


static func _restore_trees(list: Array, ctx: SnapshotContext) -> void:
	if ctx.tree_manager == null:
		return
	for d in list:
		var cell: Vector2i = d.get("cell", Vector2i(-1, -1))
		if cell.x < 0 or ctx.tree_manager.has_tree_at(cell):
			continue
		var type: TreeResource.TreeType = int(d.get("type", 0)) as TreeResource.TreeType
		var tree: TreeResource = ctx.tree_manager.spawn_tree(cell, 0, type)
		tree.set_growth(float(d.get("growth", 0.0)))


static func _restore_piles(list: Array, ctx: SnapshotContext) -> Array:
	var out: Array = []
	for d in list:
		if ctx.wood_pile_manager == null:
			out.append(null)
			continue
		var pile: WoodPile = ctx.wood_pile_manager.create_pile_at(d.get("pos", Vector3.ZERO),
			bool(d.get("clickable", true)))
		ctx.wood_pile_manager.add_to_pile(pile, int(d.get("amount", 0)))
		out.append(pile)
	return out


static func _restore_building(d: Dictionary, ctx: SnapshotContext) -> Building:
	var scene: PackedScene = load(String(d.get("scene", ""))) as PackedScene
	var tribe_id: int = int(d.get("tribe", -1))
	if scene == null or tribe_id < 0 or tribe_id >= ctx.tribes.size() or ctx.building_manager == null:
		push_warning("Spielstand: Gebäude %s nicht wiederherstellbar" % d.get("scene", "?"))
		return null
	var finished: bool = not bool(d.get("under_construction", false))
	var b: Building = ctx.building_manager.place(scene, ctx.tribes[tribe_id],
		d.get("cell", Vector2i.ZERO), int(d.get("orientation", 0)), finished)
	if b == null:
		return null
	if finished:
		if b is Hut:
			(b as Hut).upgrade_instantly(int(d.get("hut", {}).get("stage", 0)))
		b.health = clampi(int(d.get("health", b.max_health)), 1, b.max_health)
	else:
		b.wood_delivered = int(d.get("wood_delivered", 0))
		b.foundation_done = bool(d.get("foundation_done", false))
		if b.foundation_done:
			b._flatten_remaining.clear()
			b._flatten_claims.clear()
		b._site_hp_cap = int(d.get("site_hp_cap", b._construction_hp_cap()))
		b.health = maxi(int(d.get("health", 1)), 1)
		b.build_progress = float(d.get("build_progress", 0.0))
	b.wood_delivered = int(d.get("wood_delivered", b.wood_delivered))
	b.rally_point = d.get("rally", b.rally_point)
	b.paused = bool(d.get("paused", false))
	b.repair_wood = int(d.get("repair_wood", 0))
	if bool(d.get("demolishing", false)):
		var dem: Array = d.get("demolish", [b.build_progress, 0, 0])
		b.demolishing = true
		b._demolish_start_progress = float(dem[0])
		b._demolish_refund_total = int(dem[1])
		b._demolish_refund_paid = int(dem[2])
	if b is Hut:
		var h: Dictionary = d.get("hut", {})
		var hut: Hut = b as Hut
		hut.manual_crew_override = int(h.get("manual_override", -1))
		hut.spawn_timer = float(h.get("spawn_timer", hut.spawn_timer))
		hut._growth_timer = float(h.get("growth_timer", 0.0))
		hut._upgrade_timer = float(h.get("upgrade_timer", 0.0))
		if bool(h.get("upgrading", false)):
			# Set before the units come back: the upgrade workers re-join it. An
			# upgrading hut has no crew (begin_upgrade sends it out).
			hut.upgrading = true
			hut.upgrade_wood = int(h.get("upgrade_wood", 0))
			hut._upgrade_work = float(h.get("upgrade_work", 0.0))
	if b is TrainingBuilding:
		var t: Dictionary = d.get("training", {})
		(b as TrainingBuilding).queue_limit = int(t.get("queue_limit", 0))
		(b as TrainingBuilding)._train_timer = float(t.get("timer", 0.0))
	if b is Workshop:
		var w: Dictionary = d.get("workshop", {})
		(b as Workshop).production_active = bool(w.get("active", false))
		(b as Workshop).work_done = float(w.get("work", 0.0))
	if b is ReincarnationSite:
		var s: Array = d.get("site", [0.0, false, false])
		var site: ReincarnationSite = b as ReincarnationSite
		site.respawn_timer = float(s[0])
		site.respawn_pending = bool(s[1])
		site._saw_followers = bool(s[2])
	if b.is_inside_tree():
		b._update_construction_visual()
		b._update_damage_visual()
		b._update_rally_marker()
	return b


static func _restore_unit(d: Dictionary, ctx: SnapshotContext) -> Unit:
	var scene: PackedScene = load(String(d.get("scene", ""))) as PackedScene
	var tribe_id: int = int(d.get("tribe", -1))
	if scene == null or tribe_id < 0 or tribe_id >= ctx.tribes.size() or ctx.unit_manager == null:
		push_warning("Spielstand: Einheit %s nicht wiederherstellbar" % d.get("scene", "?"))
		return null
	var pos: Vector3 = d.get("pos", Vector3.ZERO)
	var u: Unit = ctx.unit_manager.spawn_unit(scene, tribe_id, pos)
	if u == null:
		return null   # hard unit cap
	if u.flies:
		u.position.y = pos.y
	u.facing = d.get("facing", u.facing)
	if u is Golem:
		_restore_golem(u as Golem, d.get("golem", {}), ctx)
	u.max_health = int(d.get("max_health", u.max_health))
	u.health = clampi(int(d.get("health", u.max_health)), 1, u.max_health)
	u.patrol = bool(d.get("patrol", false))
	if u is FireRam:
		(u as FireRam)._fire_hits = int(d.get("fire_hits", 0))
	elif u is Airship:
		(u as Airship)._hull_hits = int(d.get("hull_hits", 0))
	if d.has("hypnosis"):
		var hyp: Array = d["hypnosis"]
		var origin: int = int(hyp[0])
		if origin >= 0 and origin < ctx.tribes.size():
			u._hypnosis_origin = ctx.tribes[origin]
			u._hypnosis_time = float(hyp[1])
	u._sync_soa_pos()
	return u


static func _restore_golem(g: Golem, d: Dictionary, ctx: SnapshotContext) -> void:
	g.terrain_ctx = ctx.spell_context
	g.kills = int(d.get("kills", 0))
	g.level = int(d.get("level", 0))
	g.growth_steps = int(d.get("growth_steps", 0))
	g.life_left = float(d.get("life_left", g.life_left))
	g.sit_stationary = bool(d.get("stationary", g.sit_stationary))
	g.sit_attacks_enabled = bool(d.get("sit_attacks", g.sit_attacks_enabled))
	g.stomp_enabled = bool(d.get("stomp", g.stomp_enabled))
	if d.has("natural"):
		var keys: PackedInt32Array = d["natural"][0]
		var values: PackedFloat32Array = d["natural"][1]
		for i in range(mini(keys.size(), values.size())):
			g._flatten_natural[keys[i]] = values[i]
	if g is GenesisGolem and d.has("genesis"):
		var gen: Array = d["genesis"]
		var gg: GenesisGolem = g as GenesisGolem
		gg.stage = int(gen[0])
		gg.brave_xp = float(gen[1])
		gg.wood_growth_m = float(gen[2])
		gg.wood = int(gen[3])
		gg.trees_felled = int(gen[4])
	g._apply_speed()
	g._sync_soa_flags()
	g._stretch_queued = false
	g.snap_shown_size()
	g.snap_heading()


## Sits her down again at once: the sitting takes seconds of stance changes, so
## they are run through here (only her own tick — the world stands still).
static func _restore_sitting(g: Golem) -> void:
	var life: float = g.life_left
	var health: int = g.health
	var facing: Vector3 = g.facing
	if not g.sit_down():
		return
	for i in range(400):
		if g.is_sitting() and not g.is_switching_stance():
			break
		g.tick(0.05)
	g.life_left = life
	g.health = health
	g.facing = facing   # the look of the moment (her seat keeps its own heading)


## Indices of the units the buildings list as crew, workers, trainee or queue.
static func _building_bound_units(building_data: Array) -> Dictionary:
	var out: Dictionary = {}
	for d in building_data:
		for i in d.get("crew", []):
			out[int(i)] = true
		for entry in d.get("occupants", []):
			out[int(entry[0])] = true
		var t: Dictionary = d.get("training", {})
		if int(t.get("trainee", -1)) >= 0:
			out[int(t["trainee"])] = true
		for i in t.get("queue", []):
			out[int(i)] = true
	return out


static func _restore_unit_bindings(u: Unit, d: Dictionary, units: Array, buildings: Array,
		ctx: SnapshotContext, building_bound: bool) -> void:
	var housed: bool = building_bound
	if d.has("crew_of"):
		var vi: int = int(d["crew_of"])
		var vehicle: Unit = units[vi] if vi >= 0 and vi < units.size() else null
		if vehicle is CrewedVehicle:
			u.order_crew(vehicle)
			if bool(d.get("boarded", false)) and u.siege_engine == vehicle:
				(vehicle as CrewedVehicle).on_crew_boarded(u)
			housed = true
	if d.has("garrison_go"):
		var b: Building = _building_at(buildings, int(d["garrison_go"]))
		if b is Hut:
			u.order_man_hut(b)
		elif b is Watchtower:
			u.order_garrison(b)
	if u is Brave:
		var brave: Brave = u as Brave
		if d.has("job"):
			var job: Building = _building_at(buildings, int(d["job"]))
			if job != null:
				if job.demolishing:
					brave.order_demolish(job)
				elif job.under_construction:
					brave.order_build(job)
				elif job is Hut and (job as Hut).upgrading:
					brave.order_upgrade(job)
				elif job.health < job.max_health:
					brave.order_repair(job)
		if d.has("wood"):
			if brave.job != null or bool(d.get("carry_hold", false)):
				# A worker keeps his load (he delivers it first, Brave._choose_job_task);
				# so does a brave holding wood on the player's order.
				brave.carried_wood = int(d["wood"])
				brave.carry_hold = bool(d.get("carry_hold", false))
			else:
				# Anyone else carries it to the nearest site or pile (the loose
				# delivery of a picked-up pile) — the errand it was on is not saved.
				brave.carried_wood = int(d["wood"])
				brave._set_state(Unit.State.GATHER)
				brave._start_loose_deliver()
	if d.has("job"):
		housed = true   # a builder may stand on his own site's footprint
	if not housed and ctx.nav_grid != null and not u.flies:
		# A unit saved on a footprint (storming a building, thrown onto a roof)
		# steps off it.
		var cell: Vector2i = ctx.nav_grid.world_to_cell(u.position)
		if ctx.nav_grid.is_cell_blocked_by_building(cell):
			var near: Vector2i = ctx.nav_grid.nearest_walkable_cell(cell)
			if near.x >= 0:
				var w: Vector3 = ctx.nav_grid.cell_to_world(near)
				u.position = Vector3(w.x, u.position.y, w.z)
				u._snap_to_ground()
				u._sync_soa_pos()
	if d.has("route"):
		var route: PackedVector3Array = d["route"]
		var aggressive: bool = bool(d.get("aggressive", false))
		for i in range(route.size()):
			u.order_move(route[i], i > 0, aggressive)


## Puts the housed people back in: hut and tower crews, workshop and forester
## workers, the training queue and the trainee; the upgrade of a hut and the
## racks' stock piles.
static func _restore_building_people(b: Building, d: Dictionary, units: Array, piles: Array) -> void:
	if b is Hut:
		var hut: Hut = b as Hut
		var override: int = hut.manual_crew_override
		for i in d.get("crew", []):
			var u: Unit = _unit_at(units, int(i))
			if u != null:
				hut.admit_crew(u)
		hut.manual_crew_override = override
	elif b is Watchtower:
		for i in d.get("crew", []):
			var u: Unit = _unit_at(units, int(i))
			if u != null:
				(b as Watchtower).admit_crew(u)
	if b is TrainingBuilding:
		var tb: TrainingBuilding = b as TrainingBuilding
		var t: Dictionary = d.get("training", {})
		var trainee: Unit = _unit_at(units, int(t.get("trainee", -1)))
		if trainee is Brave:
			(trainee as Brave).order_train(tb)
			if tb.incoming.has(trainee):
				(trainee as Brave).train_reached_slot = true
				tb._admit_front()
				if tb.trainee == trainee:
					tb._train_timer = float(t.get("timer", tb.training_time))
		for i in t.get("queue", []):
			var u: Unit = _unit_at(units, int(i))
			if u is Brave:
				(u as Brave).order_train(tb)
	if b is Workshop:
		var ws: Workshop = b as Workshop
		for entry in d.get("occupants", []):
			var u: Unit = _unit_at(units, int(entry[0]))
			if u is Brave:
				(u as Brave).order_workshop(ws)
				if bool(entry[1]) and (u as Brave).job == ws:
					ws.admit_worker(u as Brave)
	elif b is Forester:
		var f: Forester = b as Forester
		for entry in d.get("occupants", []):
			var u: Unit = _unit_at(units, int(entry[0]))
			if u is Brave:
				(u as Brave).order_forester(f)
				if bool(entry[1]) and (u as Brave).forester_home == f:
					f.admit_worker(u as Brave)
	if b is WoodDepot:
		var stock: Array = []
		for i in d.get("stock", []):
			var p = piles[int(i)] if int(i) >= 0 and int(i) < piles.size() else null
			if p != null:
				stock.append(p)
		(b as WoodDepot)._stock_piles = stock


static func _restore_tribe(t: Tribe, d: Dictionary) -> void:
	t.mana = float(d.get("mana", 0.0))
	t._upkeep_debt = float(d.get("upkeep_debt", 0.0))
	t.growth_mode = int(d.get("growth_mode", int(t.growth_mode))) as Tribe.GrowthMode
	t.auto_recrew_vehicles = bool(d.get("auto_recrew", true))
	t.upgrades_allowed = bool(d.get("upgrades_allowed", true))
	t.max_catapults = int(d.get("max_catapults", t.max_catapults))
	t.max_fire_rams = int(d.get("max_fire_rams", t.max_fire_rams))
	t.max_airships = int(d.get("max_airships", t.max_airships))
	t.eliminated = bool(d.get("eliminated", false))
	t.ritual_sacrifices = int(d.get("ritual_sacrifices", 0))
	t.ai_personality_name = String(d.get("ai_personality_name", ""))
	for s in d.get("spells", []):
		var spell: Spell = t.get_spell(StringName(String(s.get("id", ""))))
		if spell == null:
			continue
		spell.charges = clampi(int(s.get("charges", 0)), 0, spell.max_charges)
		spell.charge_mana = float(s.get("charge_mana", 0.0))
		spell.active = bool(s.get("active", true))
		spell._sync_charge_progress()
	var stats: Dictionary = d.get("stats", {})
	t.kills_by_golems = int(stats.get("kills_by_golems", 0))
	t.kills_other = int(stats.get("kills_other", 0))
	t.units_lost = int(stats.get("units_lost", 0))
	t.peak_population = maxi(int(stats.get("peak_population", 0)), t.population())
	t._emit_mana()
	t._emit_spell_charges()
	t._emit_population()


static func _unit_at(units: Array, i: int) -> Unit:
	if i < 0 or i >= units.size():
		return null
	return units[i] as Unit


static func _building_at(buildings: Array, i: int) -> Building:
	if i < 0 or i >= buildings.size():
		return null
	return buildings[i] as Building


# --- Comparison (tests, the save round-trip check) ---------------------------------------

## A flat, order-independent fingerprint of a snapshot: one line per tree, pile,
## building, unit and tribe with floats rounded to centimetres. Two snapshots
## of the same world give the same lines — the save round-trip tests compare
## capture(world) with capture(restore(capture(world))).
static func fingerprint(data: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("map %s cfg %s" % [data.get("map_id", ""), _norm(data.get("match_config", {}))])
	var terrain: Dictionary = data.get("terrain", {})
	var heights: PackedFloat32Array = terrain.get("heights", PackedFloat32Array())
	var sum: float = 0.0
	for h in heights:
		sum += h
	lines.append("terrain %d %d %.2f" % [int(terrain.get("size", 0)), heights.size(), sum])
	for section in ["trees", "piles", "buildings", "units", "tribes", "ai"]:
		var items: PackedStringArray = PackedStringArray()
		for item in data.get(section, []):
			if section == "units":
				# A unit's height is the ground under it (spawn snaps it there);
				# a builder mid-hop or a thrown body is not a different state.
				item = (item as Dictionary).duplicate()
				var pos: Vector3 = item["pos"]
				item["pos"] = Vector2(pos.x, pos.z)
			items.append("%s %s" % [section, _norm(item)])
		items.sort()
		lines.append_array(items)
	for key in ["survival", "tracking"]:
		if data.has(key):
			lines.append("%s %s" % [key, _norm(data[key])])
	return lines


static func _norm(v) -> String:
	match typeof(v):
		TYPE_FLOAT:
			return "%.2f" % v
		TYPE_VECTOR3:
			return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]
		TYPE_VECTOR2:
			return "(%.2f,%.2f)" % [v.x, v.y]
		TYPE_DICTIONARY:
			var keys: Array = v.keys()
			keys.sort()
			var parts: PackedStringArray = PackedStringArray()
			for k in keys:
				parts.append("%s=%s" % [k, _norm(v[k])])
			return "{%s}" % ", ".join(parts)
		TYPE_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT32_ARRAY:
			var parts: PackedStringArray = PackedStringArray()
			for item in v:
				parts.append(_norm(item))
			return "[%s]" % ", ".join(parts)
	return str(v)
