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
## Braves sent into training per tick (at most).
const TRAIN_BATCH: int = 2
## The attack order is re-issued every this many ticks (path thrash guard).
const ATTACK_ORDER_TICKS: int = 4
## Spell heuristic ranges.
const SPELL_SCAN_RADIUS: float = 12.0
const CLUSTER_RADIUS: float = 3.0
const CLUSTER_MIN_ENEMIES: int = 4

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
		print("KI %d [%s] Pop %d, Braves %d, Armee %d, Hütten %d, Lager %d, Baustelle %s" % [
			tribe.id, AIState.State.keys()[state], snap.get("population", 0),
			snap.get("braves", 0), snap.get("army", 0), snap.get("huts", 0),
			snap.get("camps", 0), str(_has_construction_site())])
	var next: AIState.State = AIState.next_state(state, snap)
	if next != state:
		print("KI %d: %s -> %s (Pop %d, Armee %d)" % [tribe.id,
			AIState.State.keys()[state], AIState.State.keys()[next],
			snap.get("population", 0), snap.get("army", 0)])
		state = next
	_keep_praying()
	match state:
		AIState.State.BUILD:
			_tick_build(snap)
		AIState.State.TRAIN:
			_tick_train(snap)
		AIState.State.ATTACK:
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


# --- BUILD -------------------------------------------------------------------------

## Builds the base up: one construction site at a time (the BuildingManager
## recruits nearby idle braves as workers on its own); next missing building =
## huts up to target, then the three training buildings.
func _tick_build(snap: Dictionary) -> void:
	if _has_construction_site():
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


func _next_building_scene(snap: Dictionary) -> PackedScene:
	if snap.get("huts", 0) < AIState.TARGET_HUTS:
		return HUT_SCENE
	var kinds: Dictionary = _usable_camp_kinds()
	if not kinds.has(&"warrior_camp"):
		return WARRIOR_CAMP_SCENE
	if not kinds.has(&"firewarrior_camp"):
		return FIREWARRIOR_CAMP_SCENE
	if not kinds.has(&"temple"):
		return TEMPLE_SCENE
	return null


# --- TRAIN -------------------------------------------------------------------------

## Sends idle braves into the training building whose unit kind has the
## biggest deficit vs. the target mix; keeps a minimum economy crew.
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
	var kind: StringName = AIState.next_training_kind(
		_count_kind(&"warrior"), _count_kind(&"firewarrior"), _count_kind(&"preacher"))
	var building: TrainingBuilding = _usable_camp_for(kind)
	if building == null:
		return
	var batch: Array[Unit] = []
	for unit in idle:
		if batch.size() >= mini(TRAIN_BATCH, spare):
			break
		batch.append(unit)
	commands.order_train(building, batch)


# --- ATTACK ------------------------------------------------------------------------

## Marches the army (attack-move engages on contact) at the nearest enemy
## building — fallback: nearest enemy unit — and casts spells situationally.
func _tick_attack() -> void:
	_cast_spells()
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


func _has_construction_site() -> bool:
	for building in tribe.buildings:
		if is_instance_valid(building) and building.under_construction:
			return true
	return false


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
