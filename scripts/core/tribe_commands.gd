class_name TribeCommands extends Node

## The ONLY mutation API for tribe actions. UI (phase 3) and AI (phase 6) both
## call these functions; every command validates first and fails without side
## effects (null/false).
##
## Building costs are NOT paid up front: wood is delivered physically to the
## construction site (see Building). Placement only validates the terrain.
## order_train() and cast_spell() follow in phases 4 and 5.

const FORMATION_SPACING: float = 1.3
## Units move in packs of GROUP_SIZE (like the original game): tight inside
## a group, visible spacing between groups.
const GROUP_SIZE: int = 6
## Distance between group centres in the target formation.
const GROUP_SPACING: float = 2.2
## Tight member offsets inside a group (centre + 5 around it); just outside
## the separation radius so the pack stands calm.
const MEMBER_OFFSETS: Array[Vector3] = [
	Vector3(0.0, 0.0, 0.0),
	Vector3(0.55, 0.0, 0.0), Vector3(-0.55, 0.0, 0.0),
	Vector3(0.27, 0.0, 0.48), Vector3(-0.27, 0.0, 0.48),
	Vector3(0.0, 0.0, -0.55),
]
## Maximum height range (max - min vertex) on a footprint; steeper plots
## cannot be built on (the flatten phase handles anything below this).
const MAX_LEVEL_DIFF: float = 3.0

var nav_grid: NavGrid = null
var building_manager: BuildingManager = null
var unit_manager: UnitManager = null
var tree_manager: TreeManager = null
## World access for spell effects, injected by Main (tests build their own).
var spell_context: SpellContext = null


func setup(p_nav_grid: NavGrid, p_building_manager: BuildingManager,
		p_unit_manager: UnitManager, p_tree_manager: TreeManager = null) -> void:
	nav_grid = p_nav_grid
	building_manager = p_building_manager
	unit_manager = p_unit_manager
	tree_manager = p_tree_manager


# --- Elimination guards (phase 10d) -----------------------------------------------
# An eliminated tribe takes no orders at all. The API is inhomogeneous — only
# place_building/set_spell_active/cast_spell/demolish_building are handed a Tribe,
# every order_* method just gets units — so there are two guards: one on the tribe
# object, one that resolves the tribe from a unit.

## True while this tribe may still act.
func _tribe_active(tribe: Tribe) -> bool:
	return tribe != null and not tribe.eliminated


## True while this unit may still take orders (its tribe is not out). Units
## without a tribe reference (tests) are allowed through.
func _unit_active(unit: Unit) -> bool:
	return unit != null and (unit.tribe == null or not unit.tribe.eliminated)


# --- Building placement -----------------------------------------------------------

## Places a building (as a construction site) with its footprint top-left at
## `cell`, entrance facing `orientation` (0..3 = S/E/N/W). Returns null when
## the plot is invalid.
func place_building(tribe: Tribe, building_scene: PackedScene, cell: Vector2i,
		orientation: int = 0) -> Building:
	if not _tribe_active(tribe) or building_scene == null or building_manager == null:
		return null
	var probe: Building = building_scene.instantiate() as Building
	if probe == null:
		return null
	var fp: Vector2i = probe.footprint
	probe.free()
	if orientation % 2 == 1:
		fp = Vector2i(fp.y, fp.x)   # non-square footprints turn with the entrance
	if not can_place_at(cell, fp):
		return null
	return building_manager.place(building_scene, tribe, cell, orientation)


## A plot is valid when every footprint cell is on land, free of buildings and
## trees, and the total height range stays below MAX_LEVEL_DIFF (workers
## flatten the rest during construction).
func can_place_at(cell: Vector2i, footprint: Vector2i) -> bool:
	if nav_grid == null:
		return false
	var terrain: TerrainData = nav_grid.terrain
	var lo: float = INF
	var hi: float = -INF
	for z in range(cell.y, cell.y + footprint.y):
		for x in range(cell.x, cell.x + footprint.x):
			var c: Vector2i = Vector2i(x, z)
			if not terrain.in_bounds(c):
				return false
			if nav_grid.is_cell_blocked_by_building(c):
				return false
			if tree_manager != null and tree_manager.has_tree_at(c):
				return false
			if terrain.cell_height(c) <= TerrainData.SEA_LEVEL + 0.1:
				return false
	for vz in range(cell.y, cell.y + footprint.y + 1):
		for vx in range(cell.x, cell.x + footprint.x + 1):
			var h: float = terrain.vertex_height(vx, vz)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo <= MAX_LEVEL_DIFF


## Scraps one of the tribe's own buildings (key Entf, phase 10d). A site that
## never reached a build stage vanishes right away and drops its full wood; every
## other building becomes a worker job at 75 % refund. The order is FINAL.
## Returns true when the demolition was accepted (started or done instantly).
## The reincarnation circle cannot be scrapped — it is the tribe's lifeline and
## has no wood cost to hand back.
func demolish_building(tribe: Tribe, building: Building) -> bool:
	if not _tribe_active(tribe) or building == null or not is_instance_valid(building):
		return false
	if building.tribe_id != tribe.id or building.health <= 0:
		return false
	if building is ReincarnationSite:
		return false
	if building.demolishing:
		return false
	building.begin_demolish()
	return true


# --- Unit orders ----------------------------------------------------------------------

## Move order in packs of GROUP_SIZE: the selection is sorted spatially so
## nearby units end up in the same group, group centres get deterministic
## formation offsets (rings), members stand tightly around their centre.
## `aggressive` = attack-move (combatants engage enemies on the way);
## default is the plain (passive) move — also used to flee a fight.
func order_move(units: Array[Unit], target: Vector3, queue_up: bool = false,
		aggressive: bool = false) -> void:
	var alive: Array[Unit] = []
	for unit in units:
		if unit.state != Unit.State.DEAD and _unit_active(unit):
			alive.append(unit)
	if alive.is_empty():
		return
	# Spatial sort: units that stand together march together.
	alive.sort_custom(func(a: Unit, b: Unit) -> bool:
		var ka: float = a.position.z * 1000.0 + a.position.x
		var kb: float = b.position.z * 1000.0 + b.position.x
		return ka < kb)
	var group_scale: float = GROUP_SPACING / FORMATION_SPACING
	for g in range(0, alive.size(), GROUP_SIZE):
		var group_index: int = g / GROUP_SIZE
		# Vehicles get a much wider formation so each unit's target lies OUTSIDE
		# its neighbour's separation bubble — the tight ground offsets would sit
		# inside it and make vehicles shove each other around at the goal
		# (airships: circle; ground vehicles: jostle). Foot units stay tight.
		var fscale: float = alive[g].formation_scale()
		var group_target: Vector3 = target \
			+ formation_offset(group_index) * group_scale * fscale
		var batch: Array[Unit] = []
		for m in range(g, mini(g + GROUP_SIZE, alive.size())):
			var moff: float = alive[m].formation_scale()
			alive[m].order_move(group_target + MEMBER_OFFSETS[m - g] * moff,
				queue_up, aggressive)
			batch.append(alive[m])
		# The formation 6-pack IS the idle group: register it right away so
		# the walkers already count as members (slots reserved, and the idle
		# finder never re-groups a landed formation). Attack marches end in
		# combat — no point registering those.
		if not aggressive and unit_manager != null:
			unit_manager.register_move_group(batch, group_target)


## True if AT LEAST ONE of the units cannot reach `target` on foot (different
## nav island, or the target sits off the walkable grid) — used by the UI to
## play the blocked-move sound. O(1) per unit via the cached island labels
## (max one flood-fill per second); only ever called on a command, never per
## frame, so it costs nothing during play.
func any_unreachable(units: Array[Unit], target: Vector3) -> bool:
	if nav_grid == null:
		return false
	var ti: int = nav_grid.island_at(
		nav_grid.nearest_walkable_cell(nav_grid.world_to_cell(target)))
	if ti < 0:
		return true
	for u in units:
		if not is_instance_valid(u) or u.state == Unit.State.DEAD:
			continue
		var ui: int = nav_grid.island_at(
			nav_grid.nearest_walkable_cell(nav_grid.world_to_cell(u.position)))
		if ui != ti:
			return true
	return false


## Braves fell the tree (and keep chopping nearby ones); non-braves just walk
## there. The wood is dropped as piles on the spot.
## Braves fetch the wood pile and deliver it to the nearest own building's
## drop spot (like loose-chopped wood); non-braves just walk there.
## Returns the number of braves put on the pile — like order_chop, so the UI can
## blink its white confirmation ring only for an ACCEPTED order (10g).
func order_pickup(units: Array[Unit], pile: WoodPile) -> int:
	var assigned: int = 0
	var movers: Array[Unit] = []
	for unit in units:
		if unit.state == Unit.State.DEAD or not _unit_active(unit):
			continue
		if unit is Brave:
			(unit as Brave).order_pickup(pile)
			if (unit as Brave).task_pile == pile:
				assigned += 1
		else:
			movers.append(unit)
	if not movers.is_empty() and is_instance_valid(pile):
		order_move(movers, pile.position)
	return assigned


## Returns the number of braves put on the job — the UI only blinks its white
## confirmation ring for an ACCEPTED order.
func order_chop(units: Array[Unit], tree: TreeResource) -> int:
	var assigned: int = 0
	var movers: Array[Unit] = []
	for unit in units:
		if unit.state == Unit.State.DEAD or not _unit_active(unit):
			continue
		if unit is Brave:
			if (unit as Brave).order_chop(tree):
				assigned += 1
		else:
			movers.append(unit)
	if not movers.is_empty() and is_instance_valid(tree):
		order_move(movers, tree.position)
	return assigned


# --- Area harvest (key B, phase 10e) ------------------------------------------

const HARVEST_AREA_MIN_SIDE: float = Balance.HARVEST_AREA_MIN_SIDE
const HARVEST_AREA_MAX_SIDE: float = Balance.HARVEST_AREA_MAX_SIDE

## Standing area-harvest order (key B; from 10e part 2 also the AI wood crews):
## every brave keeps felling trees inside `area` (world XZ) and delivers full
## loads until it is worked out. `polygon` optionally narrows the rectangle to
## the four raycast drag corners (rotated camera).
##
## NON-BRAVES ARE IGNORED ENTIRELY — this is a worker job, and marching warriors
## into a grove would only strand them there. That is a deliberate difference to
## order_chop, where walking to the tree is at least a plausible intent.
## Returns the number of braves put on the job.
func order_chop_area(units: Array[Unit], area: Rect2,
		polygon: PackedVector2Array = PackedVector2Array()) -> int:
	var shape: Array = harvest_job_shape(area, polygon)
	var job_area: Rect2 = shape[0]
	if job_area.size.x <= 0.0:
		return 0
	var assigned: int = 0
	for unit in units:
		if unit == null or unit.state == Unit.State.DEAD or not _unit_active(unit):
			continue
		if not (unit is Brave):
			continue
		if (unit as Brave).order_chop_area(job_area, shape[1]):
			assigned += 1
	return assigned


## Effective shape of an area order as [Rect2, PackedVector2Array]: the clamped
## rectangle plus the quad, or an EMPTY quad when the quad is unusable (not four
## corners, concave or self-crossing) or when clamping moved the rectangle so the
## quad no longer matches it. Static and world-free, and called by BOTH the
## command and the UI's confirmation blink — so both see one truth.
static func harvest_job_shape(area: Rect2, polygon: PackedVector2Array) -> Array:
	var job: Rect2 = clamp_harvest_area(area)
	var poly: PackedVector2Array = polygon
	if job.size.x <= 0.0 or poly.size() != 4 or job != area.abs() \
			or not TreeManager.is_convex_quad(poly):
		poly = PackedVector2Array()
	return [job, poly]


## Area orders are clamped AROUND THEIR CENTRE: a whole-map drag must not become
## an absurd standing order. Below the minimum on BOTH sides it was a stray click
## (empty Rect2 = rejected); a legitimately thin strip along a row of trees only
## gets its short side widened to the minimum.
static func clamp_harvest_area(area: Rect2) -> Rect2:
	var a: Rect2 = area.abs()
	if a.size.x < HARVEST_AREA_MIN_SIDE and a.size.y < HARVEST_AREA_MIN_SIDE:
		return Rect2()
	var size: Vector2 = Vector2(
		clampf(a.size.x, HARVEST_AREA_MIN_SIDE, HARVEST_AREA_MAX_SIDE),
		clampf(a.size.y, HARVEST_AREA_MIN_SIDE, HARVEST_AREA_MAX_SIDE))
	return Rect2(a.get_center() - size * 0.5, size)


## Braves join the construction site as workers; non-braves just walk there.
## Returns the number of braves actually put on the job: braves on another
## island cannot reach the plot (phase 10d) and are left out entirely instead of
## walking off and getting stuck.
func order_build(units: Array[Unit], building: Building) -> int:
	if building == null or not is_instance_valid(building):
		return 0
	var assigned: int = 0
	var movers: Array[Unit] = []
	for unit in units:
		if unit.state == Unit.State.DEAD or not _unit_active(unit):
			continue
		if unit is Brave and unit.tribe_id == building.tribe_id \
				and building.worker_can_reach(unit.position):
			(unit as Brave).order_build(building)
			if (unit as Brave).job == building:
				assigned += 1
			else:
				movers.append(unit)   # site was full: at least walk over
		elif building.worker_can_reach(unit.position):
			movers.append(unit)
	if not movers.is_empty():
		order_move(movers, building.center_world())
	return assigned


## Braves repair the damaged (finished) building; non-braves just walk there.
## The wood cost — floor(damage fraction * wood_cost) — is fetched/absorbed by
## the same pipeline as construction wood. Returns the number of braves put on
## the job (see order_build for the reachability rule).
func order_repair(units: Array[Unit], building: Building) -> int:
	if building == null or not is_instance_valid(building) or building.under_construction:
		return 0
	if building.health <= 0 or building.health >= building.max_health:
		return 0
	var assigned: int = 0
	var movers: Array[Unit] = []
	for unit in units:
		if unit.state == Unit.State.DEAD or not _unit_active(unit):
			continue
		if unit is Brave and unit.tribe_id == building.tribe_id \
				and building.worker_can_reach(unit.position):
			(unit as Brave).order_repair(building)
			if (unit as Brave).job == building:
				assigned += 1
			else:
				movers.append(unit)
		elif building.worker_can_reach(unit.position):
			movers.append(unit)
	if not movers.is_empty():
		order_move(movers, building.center_world())
	return assigned


## Braves tear the building down (phase 10d); non-braves just walk there.
## Returns the number of braves actually put on the demolition.
func order_demolish(units: Array[Unit], building: Building) -> int:
	if building == null or not is_instance_valid(building) or not building.demolishing:
		return 0
	var assigned: int = 0
	var movers: Array[Unit] = []
	for unit in units:
		if unit.state == Unit.State.DEAD or not _unit_active(unit):
			continue
		if unit is Brave and unit.tribe_id == building.tribe_id \
				and building.worker_can_reach(unit.position):
			(unit as Brave).order_demolish(building)
			if (unit as Brave).job == building:
				assigned += 1
			else:
				movers.append(unit)
		elif building.worker_can_reach(unit.position):
			movers.append(unit)
	if not movers.is_empty():
		order_move(movers, building.center_world())
	return assigned


## Braves help with a running upgrade (phase 10f); non-braves just walk there.
## The building puts its OWN ejected crew on the job — this is the manual
## reinforcement path (right-click on an upgrading hut). Returns the number of
## braves actually put on the upgrade.
func order_upgrade(units: Array[Unit], building: Building) -> int:
	if building == null or not is_instance_valid(building) or not building.upgrading:
		return 0
	var assigned: int = 0
	var movers: Array[Unit] = []
	for unit in units:
		if unit.state == Unit.State.DEAD or not _unit_active(unit):
			continue
		if unit is Brave and unit.tribe_id == building.tribe_id \
				and building.worker_can_reach(unit.position):
			(unit as Brave).order_upgrade(building)
			if (unit as Brave).job == building:
				assigned += 1
			else:
				movers.append(unit)
		elif building.worker_can_reach(unit.position):
			movers.append(unit)
	if not movers.is_empty():
		order_move(movers, building.center_world())
	return assigned


## Assigns braves to a forester's worker slots; non-braves just walk there.
## The forester ignores braves when all slots are taken (no queue).
func order_forester(units: Array[Unit], forester: Forester) -> void:
	if forester == null or not is_instance_valid(forester) or not forester.is_usable():
		return
	var movers: Array[Unit] = []
	for unit in units:
		if unit.state == Unit.State.DEAD or not _unit_active(unit):
			continue
		if unit is Brave and unit.tribe_id == forester.tribe_id:
			(unit as Brave).order_forester(forester)
		else:
			movers.append(unit)
	if not movers.is_empty():
		order_move(movers, forester.center_world())


## Sends braves to a training building to be trained into combat units. Only
## own, living braves are enrolled; the building rejects them while it is
## under construction or damaged (stage >= 1). UI and AI both call this.
func order_train(building: TrainingBuilding, units: Array[Unit]) -> void:
	if building == null or not is_instance_valid(building) or not building.is_usable():
		return
	for unit in units:
		if unit is Brave and unit.state != Unit.State.DEAD \
				and _unit_active(unit) and unit.tribe_id == building.tribe_id:
			(unit as Brave).order_train(building)


## Switches a spell's charging on or off (right-click on its button in the
## spell bar). Stored charges stay castable and the partial fill is kept — only
## the mana income stops flowing into it, freeing that share for the others.
func set_spell_active(tribe: Tribe, spell_id: StringName, value: bool) -> bool:
	if not _tribe_active(tribe):
		return false
	var spell: Spell = tribe.get_spell(spell_id)
	if spell == null:
		return false
	tribe.set_spell_active(spell_id, value)
	return true


## Tribe-wide hut-upgrade lock (phase 10f, sidebar check button). Off = huts with
## a due upgrade wait instead of sending their crew out for wood; running upgrades
## are NOT cancelled (their wood is already on site).
func set_upgrades_allowed(tribe: Tribe, value: bool) -> bool:
	if not _tribe_active(tribe):
		return false
	tribe.upgrades_allowed = value
	return true


## Orders the tribe's shaman to cast `spell_id` at the target position. Fails
## without side effects when no charge is stored or the shaman is dead/absent.
## The charge itself is consumed when the shaman finishes the cast (walking
## into range first if needed); a failed effect keeps the charge. UI and AI
## both call this.
## `target_unit` (optional): a locked enemy device — the shaman tracks its live
## position while walking into range (UI spell-targeting on catapult/airship).
func cast_spell(tribe: Tribe, spell_id: StringName, target: Vector3,
		target_unit: Unit = null) -> bool:
	if not _tribe_active(tribe):
		return false
	var spell: Spell = tribe.get_spell(spell_id)
	if spell == null or spell.charges <= 0:
		return false
	var shaman: Unit = tribe.shaman
	if shaman == null or not is_instance_valid(shaman) \
			or shaman.state == Unit.State.DEAD or not (shaman is Shaman):
		return false
	return (shaman as Shaman).order_cast(spell, target, spell_context, target_unit)


## Assigns units to a crewed vehicle's crew (right-click on the vehicle, 7f).
## The vehicle validates who may crew it (accepts_crew_unit) and
## tribe/capacity (unmanned vehicles accept any tribe — takeover on boarding).
## Only as many units as there are FREE slots are sent (nearest first) — the
## rest of the group keeps doing what it did instead of being interrupted for
## a boarding the vehicle would refuse anyway.
func order_crew(units: Array[Unit], engine: Unit) -> void:
	if engine == null or not is_instance_valid(engine) \
			or engine.state == Unit.State.DEAD or not (engine is CrewedVehicle):
		return
	var vehicle: CrewedVehicle = engine as CrewedVehicle
	var candidates: Array[Unit] = []
	for unit in units:
		if unit == null or not is_instance_valid(unit) \
				or unit.state == Unit.State.DEAD or not _unit_active(unit):
			continue
		if unit.siege_engine == engine:
			continue   # already (walking to be) crew of this vehicle
		candidates.append(unit)
	candidates.sort_custom(func(a: Unit, b: Unit) -> bool:
		return a.position.distance_squared_to(engine.position) \
			< b.position.distance_squared_to(engine.position))
	# free_slots_for instead of max_crew - crew_count(): on a FOREIGN vehicle that is
	# genuinely unmanned, the owner's not-yet-boarded reservations do not count as
	# occupied. They used to, so a takeover was blocked until
	# VEHICLE_CREW_BOARD_TIMEOUT (45 s) expired — user report: an enemy catapult whose
	# crew had died could not be crewed, "only after quite a while".
	var free: int = vehicle.free_slots_for(
		candidates[0] if not candidates.is_empty() else null)
	for unit in candidates:
		if free <= 0:
			break
		unit.order_crew(engine)
		if unit.siege_engine == engine:
			free -= 1


## Assault order on an enemy building (7f siege bombardment + 7g melee storm /
## fireball siege): every unit type acts on it — melee units storm the entrance,
## firewarriors bombard, siege engines lob shots, braves storm on this explicit
## order. Own units and own-tribe targets are skipped — EXCEPT a siege engine
## sent against its OWN building while enemy raiders demolish it (anti-raider
## bombardment; the engine's order_attack_building enforces the raider rule).
func order_attack_building(units: Array[Unit], building: Building) -> void:
	if building == null or not is_instance_valid(building) or building.health <= 0:
		return
	for unit in units:
		if unit == null or not is_instance_valid(unit) \
				or unit.state == Unit.State.DEAD or not _unit_active(unit):
			continue
		if unit.tribe_id == building.tribe_id \
				and not (unit is CrewedVehicle and building.has_raiders()):
			continue
		unit.order_attack_building(building)


## Assigns braves to a workshop's standing worker crew (max 3); non-braves
## just walk there. The workshop ignores braves once its crew is full.
func order_workshop(units: Array[Unit], workshop: Workshop) -> void:
	if workshop == null or not is_instance_valid(workshop) or not workshop.is_usable():
		return
	var movers: Array[Unit] = []
	for unit in units:
		if unit.state == Unit.State.DEAD or not _unit_active(unit):
			continue
		if unit is Brave and unit.tribe_id == workshop.tribe_id:
			(unit as Brave).order_workshop(workshop)
		else:
			movers.append(unit)
	if not movers.is_empty():
		order_move(movers, workshop.center_world())


## Sends braves to haul a wood depot's stock to the nearest other depot;
## non-braves just walk there. Without a second depot the braves plain-move.
func order_depot_haul(units: Array[Unit], depot: WoodDepot) -> void:
	if depot == null or not is_instance_valid(depot) or not depot.is_usable():
		return
	var movers: Array[Unit] = []
	for unit in units:
		if unit.state == Unit.State.DEAD or not _unit_active(unit):
			continue
		if unit is Brave and unit.tribe_id == depot.tribe_id:
			(unit as Brave).order_depot_haul(depot)
		else:
			movers.append(unit)
	if not movers.is_empty():
		order_move(movers, depot.center_world())


## Braves carry wood to ONE specific own building (AI wood logistics, 10g Teil 4):
## they source it from the nearest rack, else a ground pile, else a tree, and drop it
## at the target's delivery point, where the target absorbs it.
##
## NON-BRAVES ARE IGNORED ENTIRELY — marching a warrior to a rack only strands it
## (same rule as order_chop_area, deliberately different from order_build).
##
## AI-INTERNAL: no UI caller, by explicit user decision. The architecture rule is
## still satisfied because the AI goes through this command; nothing in scripts/ui/
## may call it.
## Returns the number of braves put on the job.
func order_supply_wood(units: Array[Unit], target: Building) -> int:
	if target == null or not is_instance_valid(target) or target.health <= 0:
		return 0
	var assigned: int = 0
	for unit in units:
		if unit == null or not is_instance_valid(unit) or unit.state == Unit.State.DEAD:
			continue
		if not _unit_active(unit) or not (unit is Brave):
			continue
		if unit.tribe_id != target.tribe_id:
			continue
		if not target.worker_can_reach(unit.position):
			continue
		if (unit as Brave).order_supply_wood(target):
			assigned += 1
	return assigned


## Sets an own building's rally point, snapped to a walkable cell (phase 10g).
##
## The AI needs this because writing building.rally_point directly would bypass
## the only-mutation-API rule. Two callers: the hut rallies that route fresh
## braves into a training queue (Hut._spawn_brave -> rally_training_building) and
## the workshop muster point for finished vehicles.
##
## The UI still assigns rally points directly in SelectionManager._set_rally —
## it already has a terrain raycast hit, so it needs no snapping. Migrating it
## onto this command is a UI change and deliberately out of scope here.
##
## A target ON one of the tribe's own buildings is kept EXACTLY. That is not a
## nicety, it is the whole point of the hut rallies: rally_training_building()
## matches the rally cell against the camp's footprint_rect, and a footprint is
## SOLID in the NavGrid — snapping to the nearest walkable cell would push the
## point just outside the camp and silently break the routing.
func set_rally_point(tribe: Tribe, building: Building, target: Vector3) -> bool:
	if not _tribe_active(tribe) or building == null or not is_instance_valid(building):
		return false
	if building.tribe_id != tribe.id or building.health <= 0:
		return false
	var point: Vector3 = target
	if nav_grid != null and not _on_own_building(tribe, target):
		var cell: Vector2i = nav_grid.nearest_walkable_cell(nav_grid.world_to_cell(target))
		if cell.x < 0:
			return false
		point = nav_grid.cell_to_world(cell)
	building.rally_point = point
	return true


## True when `pos` lies on an own building's footprint (see set_rally_point).
func _on_own_building(tribe: Tribe, pos: Vector3) -> bool:
	var c: Vector2i = Vector2i(
		int(floor(pos.x / TerrainData.CELL_SIZE)),
		int(floor(pos.z / TerrainData.CELL_SIZE)))
	for b in tribe.buildings:
		if is_instance_valid(b) and Rect2i(b.cell, b.footprint).has_point(c):
			return true
	return false


## Garrisons an own watchtower with the selected combat units / shaman (phase
## 7h): each walks to the entrance and enters up to the 2 crew slots; braves and
## overflow units are ignored. The tower validates tribe/capacity/usability.
func order_garrison(units: Array[Unit], tower: Watchtower) -> void:
	if tower == null or not is_instance_valid(tower) or not tower.is_usable():
		return
	for unit in units:
		if unit == null or not is_instance_valid(unit) \
				or unit.state == Unit.State.DEAD or not _unit_active(unit):
			continue
		if unit.tribe_id != tower.tribe_id or not unit.can_garrison():
			continue
		unit.order_garrison(tower)


## Braves man a hut as production crew (phase 7i); non-braves just move there.
## Player-only path (right-click): manual manning pins the hut's crew size
## until the growth slider moves (Hut.manual_crew_override).
func order_man_hut(units: Array[Unit], hut: Hut) -> void:
	if hut == null or not is_instance_valid(hut) or not hut.is_usable():
		return
	var movers: Array[Unit] = []
	for unit in units:
		if unit == null or not is_instance_valid(unit) \
				or unit.state == Unit.State.DEAD or not _unit_active(unit):
			continue
		if unit is Brave and unit.tribe_id == hut.tribe_id:
			(unit as Brave).order_man_hut(hut, true)
		else:
			movers.append(unit)
	if not movers.is_empty():
		order_move(movers, hut.center_world())


## Right-click attack: selected units melee the clicked enemy. Units distribute
## intelligently — if the ordered target is already at its 3-attacker limit, a
## unit picks another free enemy near it instead of piling on a fourth.
func order_attack(units: Array[Unit], enemy: Unit) -> void:
	if enemy == null or not is_instance_valid(enemy) or enemy.state == Unit.State.DEAD:
		return
	# Vehicles are not targetable directly — only their crew. Exception: an
	# AIRSHIP may be ordered as a target (catapults intercept its hull); each
	# unit's _begin_attack/_may_target_vehicle filters who actually engages.
	if not enemy.is_targetable() and not (enemy is Airship):
		return
	for unit in units:
		if unit == null or not is_instance_valid(unit) \
				or unit.state == Unit.State.DEAD or not _unit_active(unit):
			continue
		if unit.tribe_id == enemy.tribe_id:
			continue   # never attack own tribe
		var target: Unit = enemy
		# Airship target: only units that may aim at the hull (catapults) keep
		# it; everyone else is redirected onto the ship's boarded crew — the
		# firewarrior shoots the passengers out one by one (user spec).
		if enemy is Airship and not unit._may_target_vehicle(enemy):
			var member: Unit = _nearest_airship_crew(enemy as Airship, unit)
			if member == null:
				continue   # nothing a non-catapult can do against an empty hull
			target = member
		# Ranged units (firewarriors) all fire at the ordered target — the
		# 3-attacker melee cap and its redistribution only apply to brawlers.
		elif not unit._is_ranged() \
				and enemy.active_melee_attacker_count() >= Unit.MAX_MELEE_ATTACKERS:
			var alt: Unit = _nearest_free_enemy_near(enemy, unit)
			if alt != null:
				target = alt
		unit.order_attack(target)


## Nearest boarded crew member of `ship` that `unit` may attack (ranged only —
## deck passengers are airborne and out of melee reach).
func _nearest_airship_crew(ship: Airship, unit: Unit) -> Unit:
	if not unit._is_ranged():
		return null
	var best: Unit = null
	var best_d: float = INF
	for m in ship.crew:
		if m == null or not is_instance_valid(m) or m.state == Unit.State.DEAD \
				or not m.siege_boarded or not m.is_targetable():
			continue
		var d: float = Vector2(unit.position.x - m.position.x,
			unit.position.z - m.position.z).length()
		if d < best_d:
			best_d = d
			best = m
	return best


## Nearest enemy (other than `avoid`) of `unit` that still has a free melee slot,
## searched around `avoid`. Uses the unit manager's spatial hash.
func _nearest_free_enemy_near(avoid: Unit, unit: Unit) -> Unit:
	if unit_manager == null:
		return null
	var flat: Vector2 = Vector2(unit.position.x, unit.position.z)
	var best: Unit = null
	var best_dist: float = INF
	for u in unit_manager.get_units_in_radius(avoid.position, Unit.AGGRO_RADIUS):
		if u == avoid or u == unit or u.state == Unit.State.DEAD:
			continue
		if u.tribe_id == unit.tribe_id or not u.is_targetable():
			continue   # never redistribute onto a vehicle/garrisoned crew
		if u.active_melee_attacker_count() >= Unit.MAX_MELEE_ATTACKERS:
			continue
		var d: float = Vector2(u.position.x, u.position.z).distance_to(flat)
		if d < best_dist:
			best_dist = d
			best = u
	return best


## Offset for the index-th unit when assembling into 6-member groups around a
## point (used by buildings so newly produced units gather in packs at the
## rally point instead of standing around at random). Same ring layout as
## order_move.
static func group_slot_offset(index: int) -> Vector3:
	var group: int = index / GROUP_SIZE
	var member: int = index % GROUP_SIZE
	var group_scale: float = GROUP_SPACING / FORMATION_SPACING
	return formation_offset(group) * group_scale + MEMBER_OFFSETS[member]


static func formation_offset(index: int) -> Vector3:
	if index == 0:
		return Vector3.ZERO
	var ring: int = 1
	var ring_count: int = 6
	var i: int = index - 1
	while i >= ring_count:
		i -= ring_count
		ring += 1
		ring_count += 6
	var angle: float = TAU * float(i) / float(ring_count)
	var radius: float = FORMATION_SPACING * float(ring)
	return Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
