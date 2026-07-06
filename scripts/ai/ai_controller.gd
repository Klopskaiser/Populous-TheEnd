class_name AIController extends Node

## Skirmish AI (phase 7): drives ONE AI tribe, one instance per tribe (child
## of Main). Ticks once per second; every action goes through TribeCommands —
## the same validated API the player UI uses, so the AI plays by identical
## rules (no cheats, enforced architecturally).
##
## The state machine transitions live in AIState (pure, tested headless);
## this node builds the snapshots and executes the per-state behaviour.

const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const WARRIOR_CAMP_SCENE: PackedScene = preload("res://scenes/buildings/warrior_camp.tscn")
const FIREWARRIOR_CAMP_SCENE: PackedScene = preload("res://scenes/buildings/firewarrior_camp.tscn")
const TEMPLE_SCENE: PackedScene = preload("res://scenes/buildings/temple.tscn")

const TICK_INTERVAL: float = 1.0
## Braves kept praying at the reincarnation site (mana income).
const PRAY_BRAVES: int = 4
## Braves sent into training per tick (at most), spread over the camps by
## deficit so all three unit kinds get trained.
const TRAIN_BATCH: int = 3
## The attack/defend order is re-issued every this many ticks (path thrash guard).
const ATTACK_ORDER_TICKS: int = 4
## Parallel construction sites: one per this many braves (capped below).
const BRAVES_PER_SITE: int = 8
const MAX_PARALLEL_SITES: int = 3
## Spell heuristic ranges.
const SPELL_SCAN_RADIUS: float = 12.0
const CLUSTER_RADIUS: float = 3.0
const CLUSTER_MIN_ENEMIES: int = 3
## Enemies this close to the base anchor trigger the defence reaction.
const DEFEND_RADIUS: float = 32.0
## Effective combat weight of the shaman / a militia brave in the
## chance-of-success estimate.
const SHAMAN_POWER: float = 4.0
const BRAVE_POWER: float = 0.5
## Defend only when own power >= enemy count * this (no hopeless suicides —
## the shaman keeps casting from the base instead).
const DEFEND_CHANCE_FACTOR: float = 0.4

var tribe: Tribe = null
var commands: TribeCommands = null
var unit_manager: UnitManager = null
var building_manager: BuildingManager = null
var tree_manager: TreeManager = null
var nav_grid: NavGrid = null
## Centre of the tribe's starter base; construction spreads around it.
var base_anchor: Vector2i = Vector2i.ZERO

var state: AIState.State = AIState.State.BUILD
## Periodic status prints (enabled by the `ai-log` command-line user arg).
var debug_log: bool = false
var _accumulator: float = 0.0
var _attack_order_countdown: int = 0
var _tick_count: int = 0


func setup(p_tribe: Tribe, p_commands: TribeCommands, p_unit_manager: UnitManager,
		p_building_manager: BuildingManager, p_tree_manager: TreeManager,
		p_nav_grid: NavGrid, p_base_anchor: Vector2i) -> void:
	tribe = p_tribe
	commands = p_commands
	unit_manager = p_unit_manager
	building_manager = p_building_manager
	tree_manager = p_tree_manager
	nav_grid = p_nav_grid
	base_anchor = p_base_anchor


func _process(delta: float) -> void:
	_accumulator += delta
	while _accumulator >= TICK_INTERVAL:
		_accumulator -= TICK_INTERVAL
		tick_ai()


## One AI decision tick (1x/s in game; tests call it directly).
func tick_ai() -> void:
	if tribe == null or commands == null:
		return
	var snap: Dictionary = make_snapshot()
	_tick_count += 1
	if debug_log and _tick_count % 60 == 0:
		print("KI %d [%s] Pop %d, Braves %d, Armee %d, Hütten %d, Lager %d, Baustellen %d" % [
			tribe.id, AIState.State.keys()[state], snap.get("population", 0),
			snap.get("braves", 0), snap.get("army", 0), snap.get("huts", 0),
			snap.get("camps", 0), _construction_site_count()])
	var next: AIState.State = AIState.next_state(state, snap)
	if next != state:
		print("KI %d: %s -> %s (Pop %d, Armee %d)" % [tribe.id,
			AIState.State.keys()[state], AIState.State.keys()[next],
			snap.get("population", 0), snap.get("army", 0)])
		state = next
	# Economy and magic run in EVERY state: pray, keep building toward the
	# full base, cast spells whenever enemies are near the shaman.
	_keep_praying()
	_tick_build(snap)
	_cast_spells()
	# An attack on the own village takes priority over everything else.
	var threat: Dictionary = _detect_threat()
	if not threat.is_empty():
		_tick_defend(threat)
	match state:
		AIState.State.TRAIN:
			_tick_train(snap)
		AIState.State.ATTACK:
			_tick_train(snap)   # keep reinforcements coming
			if threat.is_empty():
				_tick_attack()


## Live tribe snapshot in the AIState format.
func make_snapshot() -> Dictionary:
	var braves: int = 0
	var army: int = 0
	for unit in tribe.units:
		if not is_instance_valid(unit) or unit.state == Unit.State.DEAD:
			continue
		match unit.unit_kind():
			&"brave":
				braves += 1
			&"warrior", &"firewarrior", &"preacher":
				army += 1
	return AIState.make_snapshot(tribe.population(), braves, army,
		_usable_hut_count(), _usable_camp_kind_count(), _shaman_alive())


# --- BUILD (runs in every state) ------------------------------------------------------

## Builds toward the full base: several construction sites in parallel (one
## per BRAVES_PER_SITE braves — the BuildingManager recruits nearby idle
## braves as workers on its own); next missing building = huts up to target,
## then the three training buildings. One new site per tick at most.
func _tick_build(snap: Dictionary) -> void:
	var max_sites: int = clampi(snap.get("braves", 0) / BRAVES_PER_SITE,
		1, MAX_PARALLEL_SITES)
	if _construction_site_count() >= max_sites:
		return
	var scene: PackedScene = _next_building_scene(snap)
	if scene == null:
		return
	var probe: Building = scene.instantiate() as Building
	var footprint: Vector2i = probe.footprint
	probe.free()
	var cell: Vector2i = _find_plot(footprint)
	if cell.x >= 0:
		commands.place_building(tribe, scene, cell)


## Decides what to place next. Counts PLANNED buildings (construction sites
## included) — with parallel sites the usable count alone would over-build.
func _next_building_scene(_snap: Dictionary) -> PackedScene:
	var huts: int = 0
	var kinds: Dictionary = {}
	for building in tribe.buildings:
		if not is_instance_valid(building) or building.health <= 0:
			continue
		if building is Hut:
			huts += 1
		elif building is WarriorCamp:
			kinds[&"warrior_camp"] = true
		elif building is FirewarriorCamp:
			kinds[&"firewarrior_camp"] = true
		elif building is Temple:
			kinds[&"temple"] = true
	# The first camp goes up right after the first hut (early training),
	# the remaining huts and camps follow.
	if huts < 1:
		return HUT_SCENE
	if not kinds.has(&"warrior_camp"):
		return WARRIOR_CAMP_SCENE
	if huts < AIState.TARGET_HUTS:
		return HUT_SCENE
	if not kinds.has(&"firewarrior_camp"):
		return FIREWARRIOR_CAMP_SCENE
	if not kinds.has(&"temple"):
		return TEMPLE_SCENE
	return null


# --- TRAIN -------------------------------------------------------------------------

## Sends idle braves into training, spread over the camps by deficit vs. the
## target mix (warriors AND firewarriors AND preachers get trained — the
## counts are advanced per assignment, so one batch rotates through the
## kinds); keeps a minimum economy crew.
func _tick_train(_snap: Dictionary) -> void:
	var idle: Array[Unit] = _idle_braves()
	var brave_count: int = 0
	for unit in tribe.units:
		if is_instance_valid(unit) and unit is Brave \
				and unit.state != Unit.State.DEAD:
			brave_count += 1
	var spare: int = brave_count - AIState.MIN_ECONOMY_BRAVES
	if spare <= 0 or idle.is_empty():
		return
	var counts: Dictionary = {
		&"warrior": _count_kind(&"warrior"),
		&"firewarrior": _count_kind(&"firewarrior"),
		&"preacher": _count_kind(&"preacher"),
	}
	var batch_size: int = mini(mini(TRAIN_BATCH, spare), idle.size())
	for i in range(batch_size):
		var order: Array[StringName] = AIState.training_kind_order(
			counts[&"warrior"], counts[&"firewarrior"], counts[&"preacher"])
		# Biggest deficit whose camp actually stands and is usable.
		for kind in order:
			var building: TrainingBuilding = _usable_camp_for(kind)
			if building == null:
				continue
			var brave: Unit = idle.pop_back()
			commands.order_train(building, [brave] as Array[Unit])
			counts[kind] += 1
			break


# --- ATTACK ------------------------------------------------------------------------

## Marches the army (attack-move engages on contact) at the nearest enemy
## building — fallback: nearest enemy unit. Spells are cast by the global
## per-tick heuristic.
func _tick_attack() -> void:
	_attack_order_countdown -= 1
	if _attack_order_countdown > 0:
		return
	_attack_order_countdown = ATTACK_ORDER_TICKS
	var target: Vector3 = _attack_target_position()
	if target == Vector3.INF:
		return
	var squad: Array[Unit] = _army_units()
	var shaman: Unit = tribe.shaman
	if _shaman_alive() and shaman.state != Unit.State.CAST:
		squad.append(shaman)
	if not squad.is_empty():
		commands.order_move(squad, target)


# --- DEFEND ------------------------------------------------------------------------

## Enemies near the base anchor: nearest enemy unit + head count. Empty
## dictionary when the village is safe.
func _detect_threat() -> Dictionary:
	if unit_manager == null or nav_grid == null:
		return {}
	var anchor_world: Vector3 = nav_grid.cell_to_world(base_anchor)
	var nearest: Unit = null
	var nearest_dist: float = INF
	var count: int = 0
	for unit in unit_manager.get_units_in_radius(anchor_world, DEFEND_RADIUS):
		if unit.tribe_id == tribe.id or unit.state == Unit.State.DEAD:
			continue
		count += 1
		var d: float = unit.position.distance_to(anchor_world)
		if d < nearest_dist:
			nearest_dist = d
			nearest = unit
	if nearest == null:
		return {}
	return {"enemy": nearest, "count": count, "pos": nearest.position}


## Defends the village when there is a fighting chance: army + shaman move in
## (attack-move engages), and when they alone are outnumbered, praying/idle
## braves join as militia (explicit attack order — braves have no aggro).
## Hopeless odds: no suicide charge, the shaman keeps casting from the base.
func _tick_defend(threat: Dictionary) -> void:
	_attack_order_countdown -= 1
	if _attack_order_countdown > 0:
		return
	_attack_order_countdown = ATTACK_ORDER_TICKS
	var army: Array[Unit] = _army_units()
	var braves: Array[Unit] = _militia_braves()
	var enemy_count: int = threat.get("count", 1)
	var core_power: float = float(army.size()) \
		+ (SHAMAN_POWER if _shaman_alive() else 0.0)
	var full_power: float = core_power + float(braves.size()) * BRAVE_POWER
	if full_power < float(enemy_count) * DEFEND_CHANCE_FACTOR:
		return   # hopeless — spells only
	var defenders: Array[Unit] = army.duplicate()
	var shaman: Unit = tribe.shaman
	if _shaman_alive() and shaman.state != Unit.State.CAST:
		defenders.append(shaman)
	if not defenders.is_empty():
		commands.order_move(defenders, threat.get("pos"))
	# Militia only when the army alone is outnumbered.
	if core_power < float(enemy_count) and not braves.is_empty():
		var enemy: Unit = threat.get("enemy")
		if enemy != null and is_instance_valid(enemy):
			commands.order_attack(braves, enemy)


## Braves available as militia: idle or praying (never pulls workers off
## construction sites or trainees out of the queue).
func _militia_braves() -> Array[Unit]:
	var militia: Array[Unit] = []
	for unit in tribe.units:
		if not is_instance_valid(unit) or not (unit is Brave):
			continue
		if unit.state == Unit.State.IDLE or unit.state == Unit.State.PRAY:
			militia.append(unit)
	return militia


## Nearest enemy building (to the base anchor); no buildings left -> nearest
## enemy unit; nothing -> INF.
func _attack_target_position() -> Vector3:
	var anchor_world: Vector3 = nav_grid.cell_to_world(base_anchor) \
		if nav_grid != null else Vector3.ZERO
	var best: Vector3 = Vector3.INF
	var best_dist: float = INF
	if building_manager != null:
		for building in building_manager.buildings:
			if not is_instance_valid(building) or building.tribe_id == tribe.id:
				continue
			var pos: Vector3 = building.center_world()
			var d: float = pos.distance_to(anchor_world)
			if d < best_dist:
				best_dist = d
				best = pos
	if best != Vector3.INF or unit_manager == null:
		return best
	for unit in unit_manager.units:
		if not is_instance_valid(unit) or unit.tribe_id == tribe.id \
				or unit.state == Unit.State.DEAD:
			continue
		var d: float = unit.position.distance_to(anchor_world)
		if d < best_dist:
			best_dist = d
			best = unit.position
	return best


## Simple heuristic, in priority order: lightning the enemy shaman when she
## is near ours; lightning the nearest enemy building in scan range (units
## cannot attack buildings — spells are the AI's siege tool); fireball the
## densest enemy clump.
func _cast_spells() -> void:
	if not _shaman_alive() or unit_manager == null:
		return
	var shaman: Unit = tribe.shaman
	if shaman.state == Unit.State.CAST:
		return
	var enemies: Array[Unit] = []
	for unit in unit_manager.get_units_in_radius(shaman.position, SPELL_SCAN_RADIUS):
		if unit.tribe_id != tribe.id and unit.state != Unit.State.DEAD:
			enemies.append(unit)
	for enemy in enemies:
		if enemy.unit_kind() == &"shaman":
			if commands.cast_spell(tribe, &"lightning", enemy.position):
				return
			break
	var target_building: Building = _nearest_enemy_building(shaman.position,
		SPELL_SCAN_RADIUS)
	if target_building != null \
			and commands.cast_spell(tribe, &"lightning", target_building.center_world()):
		return
	var cluster: Vector3 = _densest_cluster(enemies)
	if cluster != Vector3.INF:
		commands.cast_spell(tribe, &"fireball", cluster)


## Nearest enemy building whose centre is within `radius` of `pos`.
func _nearest_enemy_building(pos: Vector3, radius: float) -> Building:
	if building_manager == null:
		return null
	var best: Building = null
	var best_dist: float = radius
	for building in building_manager.buildings:
		if not is_instance_valid(building) or building.tribe_id == tribe.id:
			continue
		if building.health <= 0:
			continue
		var d: float = building.center_world().distance_to(pos)
		if d <= best_dist:
			best_dist = d
			best = building
	return best


## Centre of the first enemy that has CLUSTER_MIN_ENEMIES-1 more enemies
## within CLUSTER_RADIUS; INF when the enemies are too spread out.
func _densest_cluster(enemies: Array[Unit]) -> Vector3:
	for candidate in enemies:
		var close: int = 0
		var centroid: Vector3 = Vector3.ZERO
		for other in enemies:
			if other.position.distance_to(candidate.position) <= CLUSTER_RADIUS:
				close += 1
				centroid += other.position
		if close >= CLUSTER_MIN_ENEMIES:
			return centroid / float(close)
	return Vector3.INF


# --- Shared helpers ------------------------------------------------------------------

## Keeps PRAY_BRAVES braves praying at the reincarnation site (mana income).
func _keep_praying() -> void:
	var site: Building = null
	for building in tribe.buildings:
		if is_instance_valid(building) and building is ReincarnationSite \
				and building.is_usable():
			site = building
			break
	if site == null:
		return
	var praying: int = 0
	for unit in tribe.units:
		if is_instance_valid(unit) and unit.state == Unit.State.PRAY:
			praying += 1
	if praying >= PRAY_BRAVES:
		return
	var idle: Array[Unit] = _idle_braves()
	var batch: Array[Unit] = []
	for unit in idle:
		if batch.size() >= PRAY_BRAVES - praying:
			break
		batch.append(unit)
	if not batch.is_empty():
		commands.order_pray(batch, site)


func _idle_braves() -> Array[Unit]:
	var idle: Array[Unit] = []
	for unit in tribe.units:
		if is_instance_valid(unit) and unit is Brave \
				and unit.state == Unit.State.IDLE:
			idle.append(unit)
	return idle


func _army_units() -> Array[Unit]:
	var army: Array[Unit] = []
	for unit in tribe.units:
		if not is_instance_valid(unit) or unit.state == Unit.State.DEAD:
			continue
		match unit.unit_kind():
			&"warrior", &"firewarrior", &"preacher":
				army.append(unit)
	return army


func _count_kind(kind: StringName) -> int:
	var count: int = 0
	for unit in tribe.units:
		if is_instance_valid(unit) and unit.state != Unit.State.DEAD \
				and unit.unit_kind() == kind:
			count += 1
	return count


func _shaman_alive() -> bool:
	return tribe.shaman != null and is_instance_valid(tribe.shaman) \
		and tribe.shaman.state != Unit.State.DEAD


func _construction_site_count() -> int:
	var count: int = 0
	for building in tribe.buildings:
		if is_instance_valid(building) and building.under_construction:
			count += 1
	return count


func _usable_hut_count() -> int:
	var count: int = 0
	for building in tribe.buildings:
		if is_instance_valid(building) and building is Hut and building.is_usable():
			count += 1
	return count


## Which training-building kinds are usable right now (keys: warrior_camp/
## firewarrior_camp/temple).
func _usable_camp_kinds() -> Dictionary:
	var kinds: Dictionary = {}
	for building in tribe.buildings:
		if not is_instance_valid(building) or not (building is TrainingBuilding) \
				or not building.is_usable():
			continue
		if building is WarriorCamp:
			kinds[&"warrior_camp"] = building
		elif building is FirewarriorCamp:
			kinds[&"firewarrior_camp"] = building
		elif building is Temple:
			kinds[&"temple"] = building
	return kinds


func _usable_camp_kind_count() -> int:
	return _usable_camp_kinds().size()


## The usable training building that produces `kind` units.
func _usable_camp_for(kind: StringName) -> TrainingBuilding:
	var kinds: Dictionary = _usable_camp_kinds()
	match kind:
		&"warrior":
			return kinds.get(&"warrior_camp") as TrainingBuilding
		&"firewarrior":
			return kinds.get(&"firewarrior_camp") as TrainingBuilding
		&"preacher":
			return kinds.get(&"temple") as TrainingBuilding
	return null


## Ring search around the base anchor for the first valid plot.
func _find_plot(footprint: Vector2i) -> Vector2i:
	for radius in range(0, 30):
		for cell in ring_cells(base_anchor, radius):
			if commands.can_place_at(cell, footprint):
				return cell
	return Vector2i(-1, -1)


static func ring_cells(center: Vector2i, radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if radius == 0:
		cells.append(center)
		return cells
	for dx in range(-radius, radius + 1):
		cells.append(center + Vector2i(dx, -radius))
		cells.append(center + Vector2i(dx, radius))
	for dz in range(-radius + 1, radius):
		cells.append(center + Vector2i(-radius, dz))
		cells.append(center + Vector2i(radius, dz))
	return cells
