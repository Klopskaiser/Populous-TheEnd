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
## Endless scaling: a new hut once the population reaches this share of the
## housing capacity, one extra training camp per HUTS_PER_EXTRA_CAMP huts
## beyond the base target.
const HOUSING_PRESSURE: float = 0.8
const HUTS_PER_EXTRA_CAMP: int = 2
## A plot only counts as supplied with this many trees in reach; otherwise
## the AI expands toward the nearest wood (bigger maps).
const PLOT_TREE_RADIUS: float = 22.0
const MIN_TREES_NEAR_PLOT: int = 3
const MAX_PLOT_CANDIDATES: int = 40
## Idle braves sent along to a remote expansion site (the BuildingManager
## only recruits workers within ~30 m of a site).
const EXPANSION_ESCORT: int = 6
const EXPANSION_DISTANCE: float = 25.0
## Ticks (seconds) without new construction after losing a building — the
## player can suppress the base instead of fighting instant rebuilds.
const REBUILD_COOLDOWN_TICKS: int = 15
## Spell heuristic ranges.
const SPELL_SCAN_RADIUS: float = 12.0
const CLUSTER_RADIUS: float = 3.0
const CLUSTER_MIN_ENEMIES: int = 3
## Swarm (panic) is worth it from this many enemies in scan range.
const SWARM_MIN_ENEMIES: int = 5
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
## Army size required for the next attack; grows after every wave
## (gradually bigger attacks).
var attack_wave_size: int = AIState.ARMY_ATTACK_SIZE
## Periodic status prints (enabled by the `ai-log` command-line user arg).
var debug_log: bool = false
var _accumulator: float = 0.0
var _attack_order_countdown: int = 0
var _tick_count: int = 0
var _rebuild_ticks: int = 0


func _ready() -> void:
	# Losing a building pauses NEW construction for a while (no instant
	# rebuild under fire). Guarded: absent in headless tests.
	var events: Node = get_node_or_null("/root/Events")
	if events != null:
		events.building_destroyed.connect(_on_building_destroyed)


func _on_building_destroyed(building) -> void:
	if tribe != null and is_instance_valid(building) \
			and building.tribe_id == tribe.id:
		_rebuild_ticks = REBUILD_COOLDOWN_TICKS


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
		# Leaving ATTACK ends a wave: the next one has to be bigger.
		if state == AIState.State.ATTACK:
			attack_wave_size = mini(attack_wave_size + AIState.ATTACK_WAVE_GROWTH,
				AIState.ATTACK_WAVE_MAX)
		print("KI %d: %s -> %s (Pop %d, Armee %d, nächste Welle %d)" % [tribe.id,
			AIState.State.keys()[state], AIState.State.keys()[next],
			snap.get("population", 0), snap.get("army", 0), attack_wave_size])
		state = next
	if _rebuild_ticks > 0:
		_rebuild_ticks -= 1
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
	var snap: Dictionary = AIState.make_snapshot(tribe.population(), braves, army,
		_usable_hut_count(), _usable_camp_kind_count(), _shaman_alive())
	snap["army_target"] = attack_wave_size
	return snap


# --- BUILD (runs in every state) ------------------------------------------------------

## Builds toward the full base and keeps scaling forever: several sites in
## parallel (one per BRAVES_PER_SITE braves — the BuildingManager recruits
## nearby idle braves as workers on its own). One new site per tick at most;
## paused for a while after losing a building (rebuild cooldown).
func _tick_build(snap: Dictionary) -> void:
	if _rebuild_ticks > 0:
		return
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
	if cell.x < 0:
		return
	if commands.place_building(tribe, scene, cell) != null:
		_send_escort_if_remote(cell)


## Decides what to place next. Counts PLANNED buildings (construction sites
## included) — with parallel sites the usable count alone would over-build.
## After the base essentials the AI keeps scaling forever: a new hut under
## housing pressure, one extra camp (kind with the fewest) per
## HUTS_PER_EXTRA_CAMP additional huts.
func _next_building_scene(_snap: Dictionary) -> PackedScene:
	var huts: int = 0
	var camps: Dictionary = {&"warrior_camp": 0, &"firewarrior_camp": 0, &"temple": 0}
	for building in tribe.buildings:
		if not is_instance_valid(building) or building.health <= 0:
			continue
		if building is Hut:
			huts += 1
		elif building is WarriorCamp:
			camps[&"warrior_camp"] += 1
		elif building is FirewarriorCamp:
			camps[&"firewarrior_camp"] += 1
		elif building is Temple:
			camps[&"temple"] += 1
	# Base build-up: first camp right after the first hut (early training),
	# the remaining huts and camp kinds follow.
	if huts < 1:
		return HUT_SCENE
	if camps[&"warrior_camp"] < 1:
		return WARRIOR_CAMP_SCENE
	if huts < AIState.TARGET_HUTS:
		return HUT_SCENE
	if camps[&"firewarrior_camp"] < 1:
		return FIREWARRIOR_CAMP_SCENE
	if camps[&"temple"] < 1:
		return TEMPLE_SCENE
	# Endless scaling: housing pressure -> hut; otherwise extra camps.
	if tribe.population() >= int(float(tribe.housing_capacity()) * HOUSING_PRESSURE):
		return HUT_SCENE
	var camp_total: int = camps[&"warrior_camp"] + camps[&"firewarrior_camp"] \
		+ camps[&"temple"]
	var camp_target: int = AIState.TARGET_CAMPS \
		+ maxi(0, huts - AIState.TARGET_HUTS) / HUTS_PER_EXTRA_CAMP
	if camp_total < camp_target:
		return _camp_scene_with_fewest(camps)
	return null


## Camp kind with the fewest standing/planned buildings (ties: warrior ->
## firewarrior -> temple, mirroring the army mix priority).
func _camp_scene_with_fewest(camps: Dictionary) -> PackedScene:
	var best_kind: StringName = &"warrior_camp"
	for kind in [&"firewarrior_camp", &"temple"]:
		if camps[kind] < camps[best_kind]:
			best_kind = kind
	match best_kind:
		&"firewarrior_camp":
			return FIREWARRIOR_CAMP_SCENE
		&"temple":
			return TEMPLE_SCENE
	return WARRIOR_CAMP_SCENE


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
		commands.order_move(squad, target, false, true)   # attack-move


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
		commands.order_move(defenders, threat.get("pos"), false, true)   # attack-move
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


## Heuristic, in priority order (one cast per tick; a spell without a stored
## charge simply falls through to the next option):
## 1. Lightning the enemy shaman near ours (kill = mana boost + disarms them).
## 2. Enemy building in scan range: TORNADO on it (wrecks it stage by stage),
##    lightning as the fallback — units cannot attack buildings, spells are
##    the AI's siege tool.
## 3. SWARM on a big enemy group (panic breaks up attacks/defence lines).
## 4. Fireball on the densest enemy clump.
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
	if target_building != null:
		var center: Vector3 = target_building.center_world()
		if commands.cast_spell(tribe, &"tornado", center):
			return
		if commands.cast_spell(tribe, &"lightning", center):
			return
	if enemies.size() >= SWARM_MIN_ENEMIES:
		var centroid: Vector3 = Vector3.ZERO
		for enemy in enemies:
			centroid += enemy.position
		if commands.cast_spell(tribe, &"swarm", centroid / float(enemies.size())):
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
## firewarrior_camp/temple). With several camps of one kind the one with the
## shortest queue wins (throughput for the bigger waves).
func _usable_camp_kinds() -> Dictionary:
	var kinds: Dictionary = {}
	for building in tribe.buildings:
		if not is_instance_valid(building) or not (building is TrainingBuilding) \
				or not building.is_usable():
			continue
		var key: StringName
		if building is WarriorCamp:
			key = &"warrior_camp"
		elif building is FirewarriorCamp:
			key = &"firewarrior_camp"
		elif building is Temple:
			key = &"temple"
		else:
			continue
		var current = kinds.get(key)
		if current == null or building.incoming.size() < current.incoming.size():
			kinds[key] = building
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


## Plot search with wood supply: first around the base anchor, and when no
## supplied plot exists there any more, EXPAND toward the nearest wood
## source (relevant on bigger maps — the tribe follows the trees).
func _find_plot(footprint: Vector2i) -> Vector2i:
	var cell: Vector2i = _find_supplied_plot(base_anchor, footprint)
	if cell.x >= 0:
		return cell
	var expansion: Vector2i = _expansion_anchor()
	if expansion.x >= 0:
		return _find_supplied_plot(expansion, footprint)
	return Vector2i(-1, -1)


## Ring search for the first valid plot that has wood in reach. Gives up
## after MAX_PLOT_CANDIDATES unsupplied candidates (then expansion takes over).
func _find_supplied_plot(anchor: Vector2i, footprint: Vector2i) -> Vector2i:
	var checked: int = 0
	for radius in range(0, 30):
		for cell in ring_cells(anchor, radius):
			if not commands.can_place_at(cell, footprint):
				continue
			if _trees_near_cell(cell) >= MIN_TREES_NEAR_PLOT:
				return cell
			checked += 1
			if checked >= MAX_PLOT_CANDIDATES:
				return Vector2i(-1, -1)
	return Vector2i(-1, -1)


func _trees_near_cell(cell: Vector2i) -> int:
	if tree_manager == null or nav_grid == null:
		return MIN_TREES_NEAR_PLOT   # no tree data (tests): treat as supplied
	var pos: Vector3 = nav_grid.cell_to_world(cell)
	var count: int = 0
	for tree in tree_manager.trees:
		if is_instance_valid(tree) and tree.position.distance_to(pos) <= PLOT_TREE_RADIUS:
			count += 1
	return count


## Cell of the nearest tree to the base — the anchor for expanding the base
## toward fresh wood.
func _expansion_anchor() -> Vector2i:
	if tree_manager == null or nav_grid == null:
		return Vector2i(-1, -1)
	var tree = tree_manager.nearest_tree(nav_grid.cell_to_world(base_anchor))
	if tree == null or not is_instance_valid(tree):
		return Vector2i(-1, -1)
	return nav_grid.world_to_cell(tree.position)


## A site far from the base gets an escort of idle braves — the
## BuildingManager only recruits workers within ~30 m of the site.
func _send_escort_if_remote(cell: Vector2i) -> void:
	if nav_grid == null:
		return
	if Vector2(cell - base_anchor).length() <= EXPANSION_DISTANCE:
		return
	var idle: Array[Unit] = _idle_braves()
	var escort: Array[Unit] = []
	for unit in idle:
		if escort.size() >= EXPANSION_ESCORT:
			break
		escort.append(unit)
	if not escort.is_empty():
		commands.order_move(escort, nav_grid.cell_to_world(cell))


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
