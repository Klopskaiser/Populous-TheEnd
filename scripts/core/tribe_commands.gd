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


# --- Building placement -----------------------------------------------------------

## Places a building (as a construction site) with its footprint top-left at
## `cell`, entrance facing `orientation` (0..3 = S/E/N/W). Returns null when
## the plot is invalid.
func place_building(tribe: Tribe, building_scene: PackedScene, cell: Vector2i,
		orientation: int = 0) -> Building:
	if tribe == null or building_scene == null or building_manager == null:
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
		if unit.state != Unit.State.DEAD:
			alive.append(unit)
	# Spatial sort: units that stand together march together.
	alive.sort_custom(func(a: Unit, b: Unit) -> bool:
		var ka: float = a.position.z * 1000.0 + a.position.x
		var kb: float = b.position.z * 1000.0 + b.position.x
		return ka < kb)
	var group_scale: float = GROUP_SPACING / FORMATION_SPACING
	for g in range(0, alive.size(), GROUP_SIZE):
		var group_index: int = g / GROUP_SIZE
		var group_target: Vector3 = target + formation_offset(group_index) * group_scale
		var batch: Array[Unit] = []
		for m in range(g, mini(g + GROUP_SIZE, alive.size())):
			alive[m].order_move(group_target + MEMBER_OFFSETS[m - g], queue_up, aggressive)
			batch.append(alive[m])
		# The formation 6-pack IS the idle group: register it right away so
		# the walkers already count as members (slots reserved, and the idle
		# finder never re-groups a landed formation). Attack marches end in
		# combat — no point registering those.
		if not aggressive and unit_manager != null:
			unit_manager.register_move_group(batch, group_target)


## Braves fell the tree (and keep chopping nearby ones); non-braves just walk
## there. The wood is dropped as piles on the spot.
## Braves fetch the wood pile and deliver it to the nearest own building's
## drop spot (like loose-chopped wood); non-braves just walk there.
func order_pickup(units: Array[Unit], pile: WoodPile) -> void:
	var movers: Array[Unit] = []
	for unit in units:
		if unit.state == Unit.State.DEAD:
			continue
		if unit is Brave:
			(unit as Brave).order_pickup(pile)
		else:
			movers.append(unit)
	if not movers.is_empty() and is_instance_valid(pile):
		order_move(movers, pile.position)


func order_chop(units: Array[Unit], tree: TreeResource) -> void:
	var movers: Array[Unit] = []
	for unit in units:
		if unit.state == Unit.State.DEAD:
			continue
		if unit is Brave:
			(unit as Brave).order_chop(tree)
		else:
			movers.append(unit)
	if not movers.is_empty() and is_instance_valid(tree):
		order_move(movers, tree.position)


## Braves join the construction site as workers; non-braves just walk there.
func order_build(units: Array[Unit], building: Building) -> void:
	var movers: Array[Unit] = []
	for unit in units:
		if unit.state == Unit.State.DEAD:
			continue
		if unit is Brave:
			(unit as Brave).order_build(building)
		else:
			movers.append(unit)
	if not movers.is_empty():
		order_move(movers, building.center_world())


## Braves pray at the site (mana bonus); non-braves just walk there.
func order_pray(units: Array[Unit], site: Building) -> void:
	var movers: Array[Unit] = []
	for unit in units:
		if unit.state == Unit.State.DEAD:
			continue
		if unit is Brave:
			(unit as Brave).order_pray(site)
		else:
			movers.append(unit)
	if not movers.is_empty():
		order_move(movers, site.center_world())


## Braves repair the damaged (finished) building; non-braves just walk there.
## The wood cost — floor(damage fraction * wood_cost) — is fetched/absorbed by
## the same pipeline as construction wood.
func order_repair(units: Array[Unit], building: Building) -> void:
	if building == null or not is_instance_valid(building) or building.under_construction:
		return
	if building.health <= 0 or building.health >= building.max_health:
		return
	var movers: Array[Unit] = []
	for unit in units:
		if unit.state == Unit.State.DEAD:
			continue
		if unit is Brave and unit.tribe_id == building.tribe_id:
			(unit as Brave).order_repair(building)
		else:
			movers.append(unit)
	if not movers.is_empty():
		order_move(movers, building.center_world())


## Assigns braves to a forester's worker slots; non-braves just walk there.
## The forester ignores braves when all slots are taken (no queue).
func order_forester(units: Array[Unit], forester: Forester) -> void:
	if forester == null or not is_instance_valid(forester) or not forester.is_usable():
		return
	var movers: Array[Unit] = []
	for unit in units:
		if unit.state == Unit.State.DEAD:
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
				and unit.tribe_id == building.tribe_id:
			(unit as Brave).order_train(building)


## Orders the tribe's shaman to cast `spell_id` at the target position. Fails
## without side effects when no charge is stored or the shaman is dead/absent.
## The charge itself is consumed when the shaman finishes the cast (walking
## into range first if needed); a failed effect keeps the charge. UI and AI
## both call this.
func cast_spell(tribe: Tribe, spell_id: StringName, target: Vector3) -> bool:
	if tribe == null:
		return false
	var spell: Spell = tribe.get_spell(spell_id)
	if spell == null or spell.charges <= 0:
		return false
	var shaman: Unit = tribe.shaman
	if shaman == null or not is_instance_valid(shaman) \
			or shaman.state == Unit.State.DEAD or not (shaman is Shaman):
		return false
	return (shaman as Shaman).order_cast(spell, target, spell_context)


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
	var free: int = vehicle.max_crew - vehicle.crew_count()
	var candidates: Array[Unit] = []
	for unit in units:
		if unit == null or not is_instance_valid(unit) or unit.state == Unit.State.DEAD:
			continue
		if unit.siege_engine == engine:
			continue   # already (walking to be) crew of this vehicle
		candidates.append(unit)
	candidates.sort_custom(func(a: Unit, b: Unit) -> bool:
		return a.position.distance_squared_to(engine.position) \
			< b.position.distance_squared_to(engine.position))
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
		if unit == null or not is_instance_valid(unit) or unit.state == Unit.State.DEAD:
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
		if unit.state == Unit.State.DEAD:
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
		if unit.state == Unit.State.DEAD:
			continue
		if unit is Brave and unit.tribe_id == depot.tribe_id:
			(unit as Brave).order_depot_haul(depot)
		else:
			movers.append(unit)
	if not movers.is_empty():
		order_move(movers, depot.center_world())


## Garrisons an own watchtower with the selected combat units / shaman (phase
## 7h): each walks to the entrance and enters up to the 2 crew slots; braves and
## overflow units are ignored. The tower validates tribe/capacity/usability.
func order_garrison(units: Array[Unit], tower: Watchtower) -> void:
	if tower == null or not is_instance_valid(tower) or not tower.is_usable():
		return
	for unit in units:
		if unit == null or not is_instance_valid(unit) or unit.state == Unit.State.DEAD:
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
		if unit == null or not is_instance_valid(unit) or unit.state == Unit.State.DEAD:
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
		if unit == null or not is_instance_valid(unit) or unit.state == Unit.State.DEAD:
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
