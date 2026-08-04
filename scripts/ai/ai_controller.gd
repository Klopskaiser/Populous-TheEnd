class_name AIController extends Node

## Skirmish AI (phase 7): drives ONE AI tribe, one instance per tribe (child
## of Main). Ticks once per second; every action goes through TribeCommands —
## the same validated API the player UI uses, so the AI plays by identical
## rules (no cheats, enforced architecturally).
##
## The state machine transitions live in AIState (pure, tested headless);
## this node builds the snapshots and executes the per-state behaviour.

## Read model of the own tribe for exactly ONE tick_ai(): filled by two passes
## (units, buildings) and handed to every subroutine as a PARAMETER, so no
## routine can accidentally read a stale cache from a previous tick. Before this
## the controller rebuilt up to 17 of these lists per tick (the train batch alone
## re-scanned the buildings up to nine times), which is what put the 1-Hz tick on
## the frame budget in the late game.
##
## Object REFERENCES are cached for everything that mutates during the tick
## (foresters, workshops, towers, depots — their slot counts are still read live
## off the cached object); only values that cannot change within one tick are
## cached as scalars.
class TickCache extends RefCounted:
	# --- units ---
	var population: int = 0
	var brave_count: int = 0
	var army_count: int = 0
	## StringName -> int for warrior/firewarrior/preacher.
	var kind_counts: Dictionary = {}
	var shaman_alive: bool = false
	var army: Array[Unit] = []
	var total_firewarriors: int = 0
	var understaffed_airships: Array[Unit] = []
	# --- buildings ---
	var usable_huts: int = 0
	var huts: Array[Building] = []
	## Braves per minute the usable huts deliver — read straight off
	## Hut.growth_per_minute(), which already accounts for crew size, upgrade stage,
	## damage, pause and the housing/unit caps. The camp targets come from THIS,
	## not from the hut count: a camp trains one unit at a time, so throughput is
	## what decides how many camps are needed (10g).
	var brave_stream: float = 0.0
	## Kind identifier -> planned count (construction sites INCLUDED).
	var planned: Dictionary = {}
	var housing_capacity: int = 0
	## Kind identifier -> the usable TrainingBuilding with the shortest queue.
	var camps_by_kind: Dictionary = {}
	var foresters: Array[Building] = []
	var workshops: Array[Building] = []
	var towers: Array[Building] = []
	var depots: Array[Building] = []
	## Depots far enough from the base to count as forward racks (the crews
	## deliver there instead of walking the whole way home).
	var forward_depots: Array[Building] = []
	var sites: Array[Building] = []
	var stalled_sites: Array[Building] = []

	## Idle pools are CONSUMED, not just read: _staff_foresters sends braves away
	## and _tick_train reads the same cache right after. Each entry is re-checked
	## for State.IDLE on the way out (O(1)) so braves another system pulled out
	## meanwhile — the BuildingManager's worker recruiting between ticks, hut
	## auto-manning — are skipped instead of being ordered around twice.
	var _idle_braves: Array[Unit] = []
	var _idle_fw: Array[Unit] = []

	static func _take(pool: Array[Unit], count: int) -> Array[Unit]:
		var out: Array[Unit] = []
		while out.size() < count and not pool.is_empty():
			var unit: Unit = pool.pop_back()
			if is_instance_valid(unit) and unit.state == Unit.State.IDLE:
				out.append(unit)
		return out

	static func _left(pool: Array[Unit]) -> int:
		var count: int = 0
		for unit in pool:
			if is_instance_valid(unit) and unit.state == Unit.State.IDLE:
				count += 1
		return count

	## Pops up to `count` braves that are STILL idle and marks them consumed.
	func take_idle(count: int) -> Array[Unit]:
		return _take(_idle_braves, count)

	func idle_left() -> int:
		return _left(_idle_braves)

	## Same for firewarriors. One shared pool for towers AND airships: they used
	## to build separate lists and could order the same firewarrior twice (the
	## boarding order then overwrote the garrison march).
	func take_idle_fw(count: int) -> Array[Unit]:
		return _take(_idle_fw, count)

	func idle_fw_left() -> int:
		return _left(_idle_fw)


const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const WARRIOR_CAMP_SCENE: PackedScene = preload("res://scenes/buildings/warrior_camp.tscn")
const FIREWARRIOR_CAMP_SCENE: PackedScene = preload("res://scenes/buildings/firewarrior_camp.tscn")
const TEMPLE_SCENE: PackedScene = preload("res://scenes/buildings/temple.tscn")
const FORESTER_SCENE: PackedScene = preload("res://scenes/buildings/forester.tscn")
const WORKSHOP_SCENE: PackedScene = preload("res://scenes/buildings/workshop.tscn")
const FIRERAM_WORKSHOP_SCENE: PackedScene = preload("res://scenes/buildings/fire_ram_workshop.tscn")
const AIRSHIP_WHARF_SCENE: PackedScene = preload("res://scenes/buildings/airship_wharf.tscn")
const WATCHTOWER_SCENE: PackedScene = preload("res://scenes/buildings/watchtower.tscn")
const WOOD_DEPOT_SCENE: PackedScene = preload("res://scenes/buildings/wood_depot.tscn")

## Kind identifier (AIState.next_building_kind) -> scene. Keeps the build order
## itself scene-free and therefore testable without instantiating anything.
const BUILD_SCENES: Dictionary = {
	&"hut": HUT_SCENE,
	&"warrior_camp": WARRIOR_CAMP_SCENE,
	&"firewarrior_camp": FIREWARRIOR_CAMP_SCENE,
	&"temple": TEMPLE_SCENE,
	&"forester": FORESTER_SCENE,
	&"workshop": WORKSHOP_SCENE,
	&"fireram_workshop": FIRERAM_WORKSHOP_SCENE,
	&"airship_wharf": AIRSHIP_WHARF_SCENE,
	&"watchtower": WATCHTOWER_SCENE,
	&"wood_depot": WOOD_DEPOT_SCENE,
}

## Footprints straight from Balance — saves instantiating and freeing a probe
## building on every single build tick just to read one Vector2i off it.
const BUILD_FOOTPRINTS: Dictionary = {
	&"hut": Balance.HUT_FOOTPRINT,
	&"warrior_camp": Balance.WARRIOR_CAMP_FOOTPRINT,
	&"firewarrior_camp": Balance.FIREWARRIOR_CAMP_FOOTPRINT,
	&"temple": Balance.TEMPLE_FOOTPRINT,
	&"forester": Balance.FORESTER_FOOTPRINT,
	&"workshop": Balance.WORKSHOP_FOOTPRINT,
	&"fireram_workshop": Balance.FIRERAM_WORKSHOP_FOOTPRINT,
	&"airship_wharf": Balance.AIRSHIP_WHARF_FOOTPRINT,
	&"watchtower": Balance.WATCHTOWER_FOOTPRINT,
	&"wood_depot": Balance.WOOD_DEPOT_FOOTPRINT,
}

const TICK_INTERVAL: float = 1.0
## Idle firewarriors kept mobile before any get garrisoned into a tower.
const WATCHTOWER_MIN_MOBILE_FW: int = 2
## The attack/defend order is re-issued every this many ticks (path thrash guard).
const ATTACK_ORDER_TICKS: int = 4
## A plot only counts as supplied with this many trees in reach; otherwise
## the AI expands toward the nearest wood (bigger maps).
const PLOT_TREE_RADIUS: float = 22.0
const MIN_TREES_NEAR_PLOT: int = 3
## Fewer than this many trees within PLOT_TREE_RADIUS of the base anchor and no
## forester yet -> build a forester (sustainable wood) before expanding away.
const FORESTER_MIN_TREES: int = 6
## Expensive candidates (each costs a _plot_reachable A*) per ANCHOR sweep; the
## shared ceiling across the whole search is _plot_candidates_left.
const MAX_PLOT_CANDIDATES: int = 40
## Hard cap on ring cells INSPECTED per plot search. Water/blocked cells fail
## can_place_at without counting toward MAX_PLOT_CANDIDATES — on lakeside anchors
## (Seenland) the ring search would otherwise sweep every cell every tick.
const MAX_PLOT_SCAN_CELLS: int = Balance.AI_MAX_PLOT_SCAN_CELLS
# Scaling thresholds that used to live here (TARGET_WATCHTOWERS, TRAIN_BATCH,
# BRAVES_PER_SITE, MAX_PARALLEL_SITES, HOUSING_PRESSURE, HUTS_PER_EXTRA_CAMP,
# FORESTER_WORKERS, WORKSHOP_WORKERS) moved to Balance.AI_* / AIState in phase
# 10e. They are NOT mirrored here on purpose: a local copy would be a second
# source of truth that silently drifts and that tests could assert against.
## Ticks (seconds) the build tick skips the plot search after it came up
## empty — the full double search (base + expansion) is the most expensive
## thing the AI does and repeating it every second changes nothing.
const PLOT_FAIL_COOLDOWN_TICKS: int = 5
## Ticks a resolved expansion anchor is reused before re-picking.
const EXPANSION_ANCHOR_TTL_TICKS: int = 10
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
## Firestorm replaces the single fireball from this many enemies around the
## densest cluster (its spread radius).
const FIRESTORM_MIN_ENEMIES: int = 5
## Volcano is worth its single charge from this many enemy buildings within
## its lava radius of the target building.
const VOLCANO_MIN_BUILDINGS: int = 2
## A building counts as coastal (sink floods it) below this ground height.
const SINK_COAST_HEIGHT: float = TerrainData.SEA_LEVEL + 2.0
## Offset of the flatten cast next to a slope building (square edge cuts
## through the footprint) and the height step that promises a foundation break.
const FLATTEN_OFFSET: float = 5.5
const FLATTEN_MIN_STEP: float = SpellContext.FOUNDATION_BREAK_DIFF + 0.3
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
## Plot cells proven UNREACHABLE from the base (phase 8.2): the expensive
## failing A* runs once per candidate, then the cell is banned for the session
## (Bergpass: walkable-but-isolated plateau tops are valid plots per
## can_place_at, but no worker can ever reach them).
var _unreachable_plots: Dictionary = {}
## Plot cells proven reachable, valid as long as walkability is unchanged
## (value = NavGrid.change_version at proof time) — exact, no TTL guessing.
var _reachable_plots: Dictionary[Vector2i, int] = {}
var _plot_fail_ticks: int = 0
var _expansion_anchor_cache: Vector2i = Vector2i(-1, -1)
var _expansion_anchor_age: int = 0
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


## Phase-shifts this AI's 1-Hz tick by `fraction` of the interval so several
## AIs spread their work across different frames (still exactly 1 Hz each).
func stagger_offset(fraction: float) -> void:
	_accumulator = -TICK_INTERVAL * clampf(fraction, 0.0, 1.0)


func _process(delta: float) -> void:
	_accumulator += delta
	while _accumulator >= TICK_INTERVAL:
		_accumulator -= TICK_INTERVAL
		tick_ai()


## Telemetry proving the once-per-tick contract (pattern: dbg_plot_scans).
static var dbg_cache_builds: int = 0
static var dbg_unit_passes: int = 0
static var dbg_building_passes: int = 0
## Huts currently routed into a training queue (10g) — the one number to watch in
## a play test, because too high starves the whole economy.
static var dbg_hut_rallies: int = 0


## One AI decision tick (1x/s in game; tests call it directly).
func tick_ai() -> void:
	if tribe == null or commands == null:
		return
	if tribe.eliminated:
		return   # out of the match (10d): no decisions, no orders
	var cache: TickCache = build_tick_cache()
	var snap: Dictionary = make_snapshot(cache)
	_tick_count += 1
	if debug_log and _tick_count % 60 == 0:
		print("KI %d [%s] Pop %d, Braves %d, Armee %d, Hütten %d, Lager %d, Baustellen %d" % [
			tribe.id, AIState.State.keys()[state], snap.get("population", 0),
			snap.get("braves", 0), snap.get("army", 0), snap.get("huts", 0),
			snap.get("camps", 0), cache.sites.size()])
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
	# Threat detection runs FIRST (one spatial query): under attack the economy
	# subsystems must not grab the idle braves before the militia gets a look in.
	var threat: Dictionary = _detect_threat()
	# Vehicle caps scale with the tribe (10e): together with the scaling
	# workshop targets this is the actual fix for "the AI hardly ever fields
	# catapults or fire rams" — before, it never raised the defaults at all.
	var caps: Dictionary = AIState.vehicle_caps(cache.brave_count)
	tribe.max_catapults = mini(int(caps[&"catapults"]), Tribe.MAX_CATAPULTS_LIMIT)
	tribe.max_fire_rams = mini(int(caps[&"fire_rams"]), Tribe.MAX_FIRE_RAMS_LIMIT)
	tribe.max_airships = mini(int(caps[&"airships"]), Tribe.MAX_AIRSHIPS_LIMIT)
	# Economy and magic run in EVERY state: keep building toward the
	# full base, cast spells whenever enemies are near the shaman.
	_tick_build(cache)
	if threat.is_empty():
		# Under attack the wood crews must not grab the braves the militia needs.
		_tick_wood_logistics(cache)
	_staff_foresters(cache)
	_staff_workshops(cache)
	# Routes part of the brave stream into training at the source, so _tick_train
	# has fewer per-brave orders to give. Runs in EVERY state (a BUILD-state tribe
	# still wants its first warriors) but is skipped under threat: re-pointing huts
	# while the militia mobilises would only fight _tick_defend for the same braves.
	if threat.is_empty():
		_tick_hut_rallies(cache)
	_man_watchtowers(cache)
	_man_airships(cache)
	_cast_spells()
	# An attack on the own village takes priority over everything else.
	if not threat.is_empty():
		_tick_defend(cache, threat)
	match state:
		AIState.State.TRAIN:
			_tick_train(cache)
		AIState.State.ATTACK:
			_tick_train(cache)   # keep reinforcements coming
			if threat.is_empty():
				_tick_attack(cache)


## Builds the per-tick read model: ONE pass over tribe.units and ONE over
## tribe.buildings. Every predicate here is a verbatim copy of the routine it
## replaces — a silent change would shift AI behaviour without any test noticing.
func build_tick_cache() -> TickCache:
	var cache: TickCache = TickCache.new()
	if tribe == null:
		return cache
	dbg_cache_builds += 1
	dbg_unit_passes += 1
	cache.population = tribe.population()
	cache.kind_counts = {&"warrior": 0, &"firewarrior": 0, &"preacher": 0}
	for unit in tribe.units:
		if not is_instance_valid(unit) or unit.state == Unit.State.DEAD:
			continue
		var kind: StringName = unit.unit_kind()
		match kind:
			&"brave":
				cache.brave_count += 1
				# _militia_braves and _idle_braves had identical predicates —
				# one pool serves both.
				if unit.state == Unit.State.IDLE:
					cache._idle_braves.append(unit)
			&"warrior", &"firewarrior", &"preacher":
				cache.army_count += 1
				cache.kind_counts[kind] += 1
				if kind == &"firewarrior":
					cache.total_firewarriors += 1
					if unit.state == Unit.State.IDLE:
						cache._idle_fw.append(unit)
				# Vehicle/deck crew rides along — never pull it off.
				if unit.state != Unit.State.CREW:
					cache.army.append(unit)
			&"siege", &"fireram", &"airship":
				# Manned vehicles march/fly with the wave (7f).
				if (unit as CrewedVehicle).boarded_count() \
						>= (unit as CrewedVehicle).min_move_crew:
					cache.army.append(unit)
				if kind == &"airship" \
						and unit.crew_count() < (unit as Airship).max_crew:
					cache.understaffed_airships.append(unit)
	cache.shaman_alive = _shaman_alive()

	dbg_building_passes += 1
	cache.planned = {
		&"hut": 0, &"hut_sites": 0, &"warrior_camp": 0, &"firewarrior_camp": 0,
		&"temple": 0, &"forester": 0, &"workshop": 0, &"fireram_workshop": 0,
		&"airship_wharf": 0, &"watchtower": 0, &"wood_depot": 0,
	}
	for building in tribe.buildings:
		if not is_instance_valid(building) or building.health <= 0:
			continue
		cache.housing_capacity += building.housing_capacity()
		if building.under_construction:
			cache.sites.append(building)
			if building.wood_stalled:
				cache.stalled_sites.append(building)
		var usable: bool = building.is_usable()
		# Subclasses BEFORE their base class (FireRamWorkshop/AirshipWharf are
		# Workshops), exactly as the old counting ladder did.
		if building is Forester:
			cache.planned[&"forester"] += 1
			if usable:
				cache.foresters.append(building)
		elif building is FireRamWorkshop:
			cache.planned[&"fireram_workshop"] += 1
			if usable:
				cache.workshops.append(building)
		elif building is AirshipWharf:
			cache.planned[&"airship_wharf"] += 1
			if usable:
				cache.workshops.append(building)
		elif building is Workshop:
			cache.planned[&"workshop"] += 1
			if usable:
				cache.workshops.append(building)
		elif building is Watchtower:
			cache.planned[&"watchtower"] += 1
			if usable and building.has_crew_room():
				cache.towers.append(building)
		elif building is WoodDepot:
			cache.planned[&"wood_depot"] += 1
			if usable:
				cache.depots.append(building)
			if Vector2(building.cell - base_anchor).length() \
					> Balance.AI_FORWARD_DEPOT_DISTANCE:
				cache.forward_depots.append(building)
		elif building is Hut:
			cache.planned[&"hut"] += 1
			cache.huts.append(building)
			if building.under_construction:
				cache.planned[&"hut_sites"] += 1
			if usable:
				cache.usable_huts += 1
				cache.brave_stream += (building as Hut).growth_per_minute()
		elif building is WarriorCamp:
			cache.planned[&"warrior_camp"] += 1
			_note_camp(cache, building, &"warrior_camp", usable)
		elif building is FirewarriorCamp:
			cache.planned[&"firewarrior_camp"] += 1
			_note_camp(cache, building, &"firewarrior_camp", usable)
		elif building is Temple:
			cache.planned[&"temple"] += 1
			_note_camp(cache, building, &"temple", usable)
	return cache


## With several camps of one kind the one with the SHORTEST queue wins
## (throughput for the bigger waves) — the old _usable_camp_kinds rule.
func _note_camp(cache: TickCache, building: Building, key: StringName,
		usable: bool) -> void:
	if not usable:
		return
	var current = cache.camps_by_kind.get(key)
	if current == null or building.incoming.size() < current.incoming.size():
		cache.camps_by_kind[key] = building


## Live tribe snapshot in the AIState format, read off the tick cache.
func make_snapshot(cache: TickCache = null) -> Dictionary:
	var c: TickCache = cache if cache != null else build_tick_cache()
	var snap: Dictionary = AIState.make_snapshot(c.population, c.brave_count,
		c.army_count, c.usable_huts, c.camps_by_kind.size(), c.shaman_alive)
	snap["army_target"] = attack_wave_size
	return snap


# --- BUILD (runs in every state) ------------------------------------------------------

## Builds toward the full base and keeps scaling forever: several sites in
## parallel (AIState.parallel_site_count — the BuildingManager recruits
## nearby idle braves as workers on its own). One new site per tick at most;
## paused for a while after losing a building (rebuild cooldown).
func _tick_build(cache: TickCache) -> void:
	if _rebuild_ticks > 0:
		return
	if _plot_fail_ticks > 0:
		_plot_fail_ticks -= 1
		return
	var max_sites: int = AIState.parallel_site_count(cache.brave_count)
	if cache.sites.size() >= max_sites:
		return
	var kind: StringName = next_building_kind(cache)
	if kind == &"":
		return
	var scene: PackedScene = BUILD_SCENES[kind] as PackedScene
	var footprint: Vector2i = BUILD_FOOTPRINTS[kind]
	# A forward wood rack is anchored at the GROVE, not at the village.
	var prefer: Vector2i = Vector2i(-1, -1)
	if kind == &"wood_depot" and cache.planned[&"wood_depot"] > 0:
		prefer = _forward_depot_anchor()
	var cell: Vector2i = _find_plot(footprint, cache, prefer)
	if cell.x < 0:
		# Nothing buildable right now — repeating the expensive double ring
		# search every second changes nothing, so back off for a few ticks.
		_plot_fail_ticks = PLOT_FAIL_COOLDOWN_TICKS
		return
	var site: Building = commands.place_building(tribe, scene, cell, _plot_orientation)
	if site != null and _accept_or_scrap_site(site, cell):
		_send_escort_if_remote(cache, cell)


## Decides what to place next. The ORDER itself lives in AIState as a pure
## function (headless-testable without scenes); this wrapper only supplies the
## situation the pure function cannot see (wood around the base, grove distance).
func next_building_kind(cache: TickCache) -> StringName:
	var counts: Dictionary = cache.planned.duplicate()
	counts["braves"] = cache.brave_count
	counts["population"] = cache.population
	counts["housing_capacity"] = cache.housing_capacity
	counts["forward_depot"] = cache.forward_depots.size()
	counts["wood_thin"] = _wood_thin_near_base()
	counts["grove_far"] = _best_grove_is_remote()
	counts["brave_stream"] = cache.brave_stream
	return AIState.next_building_kind(counts)


## Kept as a thin wrapper so existing tests can ask for the next SCENE.
func _next_building_scene(cache: TickCache) -> PackedScene:
	var kind: StringName = next_building_kind(cache)
	return BUILD_SCENES.get(kind) as PackedScene


# --- Wood logistics (phase 10e, 2.2) ----------------------------------------------

## Standing wood crews: {"units": Array[Unit], "area": Rect2}. Membership is
## derived from Brave.has_chop_area(), NEVER from State.IDLE — right after
## order_chop_area the brave has not ticked yet and is still IDLE, so an
## IDLE-based check would discard the crew one tick after creating it.
var _wood_crews: Array[Dictionary] = []
## Braves shuttling a forward rack's stock back to the base.
var _haul_crew: Array[Unit] = []
var _grove_cache: Array[Rect2] = []
## TICK the cache was filled on — not a per-call counter: next_building_kind and
## the wood tick both ask, so a call counter would expire the TTL twice as fast
## and re-walk every position bucket for nothing.
var _grove_cache_tick: int = -100000
var _grove_cache_from: Vector2i = Vector2i(-1000, -1000)


## The AI's own wood supply. Before 10e it had NO gathering orders at all: wood
## only ever came from BuildingManager._recruit_workers pulling idle braves
## within 30 m of a site, which stalls the moment the nearby trees are gone.
## Crews use the very same order_chop_area command as the player.
func _tick_wood_logistics(cache: TickCache) -> void:
	if commands == null or tree_manager == null or nav_grid == null:
		return
	if _tick_count % Balance.AI_WOOD_TICK_INTERVAL != 0:
		return
	_prune_wood_crews()
	_tick_forward_haul(cache)
	var target_crews: int = AIState.wood_crew_count(cache.brave_count)
	if _wood_crews.size() >= target_crews:
		return
	# Demand: unfunded wood on own sites (cache.sites is a short list — no extra
	# full pass). wood_incoming() does a pile radius query per site, which is why
	# this only runs on the throttled tick.
	var need: int = 0
	for site in cache.sites:
		need += maxi(0, site.wood_needed_total() - site.wood_incoming())
	if need <= 0 and cache.stalled_sites.is_empty():
		return
	# Escort the blocked sites first: a stalled site has workers waiting on wood
	# that nobody is bringing.
	var escorted: int = 0
	for site in cache.stalled_sites:
		if escorted >= Balance.AI_STALLED_ESCORTS_PER_TICK:
			break
		_send_escort_if_remote(cache, site.cell)
		escorted += 1
	var groves: Array[Rect2] = _grove_candidates_cached(
		nav_grid.cell_to_world(base_anchor))
	if groves.is_empty():
		return
	for grove in groves:
		if _wood_crews.size() >= target_crews:
			break
		if cache.idle_left() < Balance.AI_WOOD_CREW_SIZE:
			break
		if _grove_is_taken(grove):
			continue
		var crew: Array[Unit] = cache.take_idle(Balance.AI_WOOD_CREW_SIZE)
		if commands.order_chop_area(crew, grove) > 0:
			_wood_crews.append({"units": crew, "area": grove})


## Drops crew members that lost their area order (any other order clears it via
## Brave._interrupt_tasks, and a worked-out area clears it through _stop_all) and
## disbands crews that shrank below half strength — their remnants are idle
## again and get folded into a fresh crew next round.
func _prune_wood_crews() -> void:
	var kept: Array[Dictionary] = []
	for crew in _wood_crews:
		var alive: Array[Unit] = []
		for unit in crew["units"]:
			if is_instance_valid(unit) and unit is Brave \
					and (unit as Brave).has_chop_area():
				alive.append(unit)
		if alive.size() >= Balance.AI_WOOD_CREW_SIZE / 2:
			crew["units"] = alive
			kept.append(crew)
	_wood_crews = kept


func _grove_is_taken(grove: Rect2) -> bool:
	for crew in _wood_crews:
		if (crew["area"] as Rect2).get_center().distance_to(grove.get_center()) < 1.0:
			return true
	return false


## Grove list around `from`, cached for AI_WOOD_GROVE_TTL_TICKS (the scan walks
## every position bucket; the nearest groves do not move second-to-second).
func _grove_candidates_cached(from: Vector3) -> Array[Rect2]:
	var from_cell: Vector2i = nav_grid.world_to_cell(from)
	if _grove_cache_from == from_cell \
			and _tick_count - _grove_cache_tick <= Balance.AI_WOOD_GROVE_TTL_TICKS:
		return _grove_cache
	_grove_cache = tree_manager.grove_candidates(from, Balance.AI_MAX_WOOD_CREWS + 1)
	_grove_cache_from = from_cell
	_grove_cache_tick = _tick_count
	return _grove_cache


## True when the best grove is far enough from the base that a forward rack pays
## for itself (drives the "wood_depot" branch of the build order).
func _best_grove_is_remote() -> bool:
	if tree_manager == null or nav_grid == null:
		return false
	var base_world: Vector3 = nav_grid.cell_to_world(base_anchor)
	var groves: Array[Rect2] = _grove_candidates_cached(base_world)
	if groves.is_empty():
		return false
	var centre: Vector2 = groves[0].get_center()
	return centre.distance_to(Vector2(base_world.x, base_world.z)) \
		> Balance.AI_FORWARD_DEPOT_DISTANCE


## Anchor cell for a forward rack: the centre of the best grove.
func _forward_depot_anchor() -> Vector2i:
	if tree_manager == null or nav_grid == null:
		return Vector2i(-1, -1)
	var groves: Array[Rect2] = _grove_candidates_cached(
		nav_grid.cell_to_world(base_anchor))
	if groves.is_empty():
		return Vector2i(-1, -1)
	var centre: Vector2 = groves[0].get_center()
	return nav_grid.world_to_cell(Vector3(centre.x, 0.0, centre.y))


## Two braves shuttle a forward rack's stock back to the base, so the wood ends
## up where the construction sites are.
func _tick_forward_haul(cache: TickCache) -> void:
	var kept: Array[Unit] = []
	for unit in _haul_crew:
		if is_instance_valid(unit) and unit is Brave \
				and (unit as Brave).has_depot_haul():
			kept.append(unit)
	_haul_crew = kept
	if _haul_crew.size() >= 2 or cache.depots.size() < 2:
		return
	for depot in cache.forward_depots:
		if not (depot as WoodDepot).is_usable() \
				or (depot as WoodDepot).stored_wood() <= 0:
			continue
		var haulers: Array[Unit] = cache.take_idle(2 - _haul_crew.size())
		if haulers.is_empty():
			return
		commands.order_depot_haul(haulers, depot as WoodDepot)
		for unit in haulers:
			_haul_crew.append(unit)
		return


# --- TRAIN -------------------------------------------------------------------------

## Sends idle braves into training, spread over the camps by deficit vs. the
## target mix (warriors AND firewarriors AND preachers get trained — the
## counts are advanced per assignment, so one batch rotates through the
## kinds); keeps a minimum economy crew.
func _tick_train(cache: TickCache) -> void:
	var spare: int = cache.brave_count - AIState.min_economy_braves(cache.population)
	if spare <= 0:
		return
	var counts: Dictionary = cache.kind_counts.duplicate()
	var batch_size: int = mini(mini(AIState.train_batch(cache.brave_count), spare),
		cache.idle_left())
	for i in range(batch_size):
		var order: Array[StringName] = AIState.training_kind_order(
			counts[&"warrior"], counts[&"firewarrior"], counts[&"preacher"])
		# Biggest deficit whose camp actually stands and is usable.
		for kind in order:
			var building: TrainingBuilding = _camp_for(cache, kind)
			if building == null:
				continue
			# Claimed only once a camp is found — a kind without a camp must not
			# burn a brave from the pool.
			var brave: Array[Unit] = cache.take_idle(1)
			if brave.is_empty():
				return
			commands.order_train(building, brave)
			counts[kind] += 1
			break


# --- ATTACK ------------------------------------------------------------------------

## Marches the army (attack-move engages on contact) at the nearest enemy
## building — fallback: nearest enemy unit. Spells are cast by the global
## per-tick heuristic.
func _tick_attack(cache: TickCache) -> void:
	_attack_order_countdown -= 1
	if _attack_order_countdown > 0:
		return
	_attack_order_countdown = ATTACK_ORDER_TICKS
	var target: Vector3 = _attack_target_position()
	if target == Vector3.INF:
		return
	var squad: Array[Unit] = cache.army.duplicate()
	var shaman: Unit = tribe.shaman
	if _shaman_alive() and shaman.state != Unit.State.CAST \
			and not _tick_unblock_path(target):
		squad.append(shaman)
	if not squad.is_empty():
		commands.order_move(squad, target, false, true)   # attack-move


# --- Terrain unblocking (attack path via landbridge/sink) --------------------------

## Terrain spells can cut the AI off (e.g. the only ramp to a plateau base
## removed): the attack target then sits on another nav island. The shaman
## walks to the edge of her island toward the target and casts LANDBRIDGE
## across the gap — partial bridges allowed (capped at the cast range); every
## cast grows her island until the ways are joined and the march resumes.
## SINK on a raised barrier is the fallback when the landbridge is out of
## charges. The army keeps its attack-move order meanwhile (partial paths
## gather it at the edge).

## The shaman counts as "at the island edge" within this distance of it.
const UNBLOCK_EDGE_DIST: float = 2.5
## Sampling step (metres) along the shaman->target line.
const UNBLOCK_STEP: float = 1.0
## A barrier at least this much above the island edge counts as a wall the
## sink fallback may cut down (lower gaps are the landbridge's job).
const UNBLOCK_WALL_MIN_STEP: float = 1.5

## Returns true while the shaman is busy unblocking the path to `target`
## (the caller then leaves her out of the march order). False when the target
## is reachable on foot — the normal attack-move handles it.
func _tick_unblock_path(target: Vector3) -> bool:
	if nav_grid == null or commands == null or not _shaman_alive():
		return false
	var shaman: Unit = tribe.shaman
	if shaman.garrison_housed:
		return false
	if nav_grid.same_island(shaman.position, target):
		return false
	var edge: Vector3 = _island_edge_toward(shaman.position, target)
	if edge == Vector3.INF:
		return false
	if Vector2(shaman.position.x - edge.x, shaman.position.z - edge.z).length() \
			> UNBLOCK_EDGE_DIST:
		commands.order_move([shaman] as Array[Unit], edge)
		return true
	# At the edge: bridge toward the target. A point on the far island within
	# cast range connects directly; otherwise the farthest point along the
	# line (partial bridge over the gap, continued next casts).
	var bridge: Spell = tribe.get_spell(&"landbridge")
	if bridge != null and bridge.charges > 0:
		var cast_at: Vector3 = _bridge_cast_point(shaman.position, target,
			bridge.cast_range - 1.0)
		if commands.cast_spell(tribe, &"landbridge", cast_at):
			if debug_log:
				print("KI %d: Landbrücke zum Angriffsziel (%.0f/%.0f)" % [
					tribe.id, cast_at.x, cast_at.z])
			return true
	var sink: Spell = tribe.get_spell(&"sink")
	if sink != null and sink.charges > 0:
		var wall: Vector3 = _wall_point_toward(shaman.position, target,
			sink.cast_range - 1.0)
		if wall != Vector3.INF and _sink_would_flood_caster(shaman, wall):
			wall = Vector3.INF   # too close on low ground — wait for a landbridge
		if wall != Vector3.INF and commands.cast_spell(tribe, &"sink", wall):
			if debug_log:
				print("KI %d: Absinken schneidet Barriere (%.0f/%.0f)" % [
					tribe.id, wall.x, wall.z])
			return true
	return true   # blocked, nothing castable yet — hold at the edge for charges


## Walkable point on the shaman's island nearest to `target` along the
## straight line — the "shore" the bridge is built from. INF without an
## island label (shouldn't happen for a live shaman).
func _island_edge_toward(from: Vector3, target: Vector3) -> Vector3:
	var my_island: int = nav_grid.island_at(
		nav_grid.nearest_walkable_cell(nav_grid.world_to_cell(from)))
	if my_island < 0:
		return Vector3.INF
	var flat_from: Vector2 = Vector2(from.x, from.z)
	var flat_to: Vector2 = Vector2(target.x, target.z)
	var dist: float = flat_from.distance_to(flat_to)
	if dist < 0.001:
		return from
	var dir: Vector2 = (flat_to - flat_from) / dist
	var edge_cell: Vector2i = nav_grid.world_to_cell(from)
	var t: float = UNBLOCK_STEP
	while t < dist:
		var p: Vector2 = flat_from + dir * t
		var cell: Vector2i = nav_grid.world_to_cell(Vector3(p.x, 0.0, p.y))
		if nav_grid.island_at(cell) == my_island:
			edge_cell = cell
		t += UNBLOCK_STEP
	return nav_grid.cell_to_world(edge_cell)


## Landbridge target: the first point of ANOTHER island along the line within
## `reach` (direct connection), else the farthest point at `reach` (partial
## bridge over water / down a canyon).
func _bridge_cast_point(from: Vector3, target: Vector3, reach: float) -> Vector3:
	var flat_from: Vector2 = Vector2(from.x, from.z)
	var flat_to: Vector2 = Vector2(target.x, target.z)
	var dist: float = flat_from.distance_to(flat_to)
	var dir: Vector2 = (flat_to - flat_from) / maxf(dist, 0.001)
	var my_island: int = nav_grid.island_at(
		nav_grid.nearest_walkable_cell(nav_grid.world_to_cell(from)))
	var limit: float = minf(reach, dist)
	var t: float = UNBLOCK_STEP
	while t <= limit:
		var p: Vector2 = flat_from + dir * t
		var isl: int = nav_grid.island_at(nav_grid.world_to_cell(Vector3(p.x, 0.0, p.y)))
		if isl >= 0 and isl != my_island:
			return Vector3(p.x, 0.0, p.y)   # lands on the far shore
		t += UNBLOCK_STEP
	var far: Vector2 = flat_from + dir * limit
	return Vector3(far.x, 0.0, far.y)


## The sink also lowers the ground under the caster (smoothstep falloff over
## its radius): on low coastal ground that would flood the shaman's own feet
## and drown her. True when casting at `wall` is unsafe for the caster.
func _sink_would_flood_caster(shaman: Unit, wall: Vector3) -> bool:
	var d: float = Vector2(wall.x - shaman.position.x,
		wall.z - shaman.position.z).length()
	if d >= SinkSpell.RADIUS:
		return false
	var t: float = clampf((SinkSpell.RADIUS - d) / SinkSpell.RADIUS, 0.0, 1.0)
	var falloff: float = t * t * (3.0 - 2.0 * t)
	return shaman.position.y - SinkSpell.DEPTH * falloff <= TerrainData.SEA_LEVEL + 0.4


## First point along the line (within `reach`) whose ground rises clearly
## ABOVE the shaman's level — a raised wall the sink fallback can cut down.
## INF when the blockade is not a wall (water/chasm -> landbridge only).
func _wall_point_toward(from: Vector3, target: Vector3, reach: float) -> Vector3:
	var flat_from: Vector2 = Vector2(from.x, from.z)
	var flat_to: Vector2 = Vector2(target.x, target.z)
	var dist: float = flat_from.distance_to(flat_to)
	var dir: Vector2 = (flat_to - flat_from) / maxf(dist, 0.001)
	var limit: float = minf(reach, dist)
	var t: float = UNBLOCK_STEP
	while t <= limit:
		var p: Vector2 = flat_from + dir * t
		var cell: Vector2i = nav_grid.world_to_cell(Vector3(p.x, 0.0, p.y))
		var h: float = nav_grid.cell_to_world(cell).y
		if h > from.y + UNBLOCK_WALL_MIN_STEP:
			return Vector3(p.x, 0.0, p.y)
		t += UNBLOCK_STEP
	return Vector3.INF


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
## (attack-move engages), and when they alone are outnumbered, idle
## braves join as militia (explicit attack order — braves have no aggro).
## Hopeless odds: no suicide charge, the shaman keeps casting from the base.
func _tick_defend(cache: TickCache, threat: Dictionary) -> void:
	_attack_order_countdown -= 1
	if _attack_order_countdown > 0:
		return
	_attack_order_countdown = ATTACK_ORDER_TICKS
	var army: Array[Unit] = cache.army
	var enemy_count: int = threat.get("count", 1)
	var core_power: float = float(army.size()) \
		+ (SHAMAN_POWER if cache.shaman_alive else 0.0)
	var full_power: float = core_power + float(cache.idle_left()) * BRAVE_POWER
	if full_power < float(enemy_count) * DEFEND_CHANCE_FACTOR:
		return   # hopeless — spells only
	var defenders: Array[Unit] = army.duplicate()
	var shaman: Unit = tribe.shaman
	if _shaman_alive() and shaman.state != Unit.State.CAST:
		defenders.append(shaman)
	if not defenders.is_empty():
		commands.order_move(defenders, threat.get("pos"), false, true)   # attack-move
	# Militia only when the army alone is outnumbered. Idle braves only — the
	# pool never holds workers on sites or trainees in a queue.
	if core_power < float(enemy_count):
		var braves: Array[Unit] = cache.take_idle(cache.idle_left())
		var enemy: Unit = threat.get("enemy")
		if not braves.is_empty() and enemy != null and is_instance_valid(enemy):
			commands.order_attack(braves, enemy)


## Nearest ATTACKABLE enemy building (to the base anchor); none left -> nearest
## enemy unit; nothing -> INF.
##
## The is_attackable() filter is what makes the AI pursue the actual win
## condition (10g): the enemy reincarnation circle stands on its base anchor and
## was usually the nearest building, so the whole attack wave marched at an
## invulnerable ring while the tribe's FOLLOWERS lived on. Filtered out, the
## existing "nearest enemy unit" fallback takes over — and that is exactly the
## 10d defeat chain: last follower dies -> the circle sinks itself -> the shaman
## dies -> the tribe is out.
func _attack_target_position() -> Vector3:
	var anchor_world: Vector3 = nav_grid.cell_to_world(base_anchor) \
		if nav_grid != null else Vector3.ZERO
	var best: Vector3 = Vector3.INF
	var best_dist: float = INF
	if building_manager != null:
		for building in building_manager.buildings:
			if not is_instance_valid(building) or building.tribe_id == tribe.id:
				continue
			if not building.is_attackable():
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
	# Enemy preachers are the AI's worst matchup — they convert its army away
	# and converting units cannot even be attacked in melee. They die first;
	# lightning one-shots them, fireball is the fallback. Filtering the already
	# collected `enemies` list costs no extra scan.
	for enemy in enemies:
		if enemy.unit_kind() != &"preacher":
			continue
		if commands.cast_spell(tribe, &"lightning", enemy.position):
			return
		if commands.cast_spell(tribe, &"fireball", enemy.position):
			return
		break
	var target_building: Building = _nearest_enemy_building(shaman.position,
		SPELL_SCAN_RADIUS)
	if target_building != null:
		var center: Vector3 = target_building.center_world()
		# Building priorities (7c): volcano on clusters, sink floods coastal
		# plots, flatten breaks foundations on slopes, then the old
		# tornado/quake/lightning ladder.
		if _enemy_buildings_near(center, VolcanoZone.RADIUS) >= VOLCANO_MIN_BUILDINGS:
			if commands.cast_spell(tribe, &"volcano", center):
				return
		if center.y <= SINK_COAST_HEIGHT:
			if commands.cast_spell(tribe, &"sink", center):
				return
		var flatten_at: Vector3 = _flatten_break_point(target_building)
		if flatten_at != Vector3.INF:
			if commands.cast_spell(tribe, &"flatten", flatten_at):
				return
		if commands.cast_spell(tribe, &"tornado", center):
			return
		if commands.cast_spell(tribe, &"earthquake", center):
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
		# A big pile is worth the salvo; smaller ones get the single fireball.
		if _count_enemies_near(enemies, cluster, FirestormSpell.SPREAD_RADIUS) \
				>= FIRESTORM_MIN_ENEMIES:
			if commands.cast_spell(tribe, &"firestorm", cluster):
				return
		commands.cast_spell(tribe, &"fireball", cluster)


## Nearest ATTACKABLE enemy building whose centre is within `radius` of `pos`.
## Feeds the spell heuristic (lightning / volcano / sink / flatten), so the filter
## stops the AI from burning charges on the invulnerable reincarnation circle.
func _nearest_enemy_building(pos: Vector3, radius: float) -> Building:
	if building_manager == null:
		return null
	var best: Building = null
	var best_dist: float = radius
	for building in building_manager.buildings:
		if not is_instance_valid(building) or building.tribe_id == tribe.id:
			continue
		if building.health <= 0 or not building.is_attackable():
			continue
		var d: float = building.center_world().distance_to(pos)
		if d <= best_dist:
			best_dist = d
			best = building
	return best


## Number of ATTACKABLE enemy buildings whose centre lies within `radius` of
## `pos` — the volcano's "is this cluster worth a charge" count must not be
## inflated by the reincarnation circle, which the lava cannot touch.
func _enemy_buildings_near(pos: Vector3, radius: float) -> int:
	if building_manager == null:
		return 0
	var count: int = 0
	for building in building_manager.buildings:
		if not is_instance_valid(building) or building.tribe_id == tribe.id \
				or building.health <= 0 or not building.is_attackable():
			continue
		if building.center_world().distance_to(pos) <= radius:
			count += 1
	return count


func _count_enemies_near(enemies: Array[Unit], pos: Vector3, radius: float) -> int:
	var count: int = 0
	for enemy in enemies:
		if enemy.position.distance_to(pos) <= radius:
			count += 1
	return count


## Cast point for a foundation-breaking flatten next to a slope building: a
## square centred here reaches into the footprint while its level differs
## from the building's ground by more than the break threshold. INF when the
## surroundings are level (flatten would change nothing).
func _flatten_break_point(building: Building) -> Vector3:
	var td: TerrainData = building.terrain_data
	if td == null:
		return Vector3.INF
	var center: Vector3 = building.center_world()
	var base_h: float = td.get_height(center.x, center.z)
	for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var probe: Vector3 = center + dir * FLATTEN_OFFSET
		var h: float = td.get_height(probe.x, probe.z)
		if h <= TerrainData.SEA_LEVEL:
			continue   # flattening onto a water-level point is the sink's job
		if absf(h - base_h) > FLATTEN_MIN_STEP:
			return Vector3(probe.x, h, probe.z)
	return Vector3.INF


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

func _shaman_alive() -> bool:
	return tribe.shaman != null and is_instance_valid(tribe.shaman) \
		and tribe.shaman.state != Unit.State.DEAD


## The usable training building that produces `kind` units, from the tick cache.
func _camp_for(cache: TickCache, kind: StringName) -> TrainingBuilding:
	match kind:
		&"warrior":
			return cache.camps_by_kind.get(&"warrior_camp") as TrainingBuilding
		&"firewarrior":
			return cache.camps_by_kind.get(&"firewarrior_camp") as TrainingBuilding
		&"preacher":
			return cache.camps_by_kind.get(&"temple") as TrainingBuilding
	return null


## Telemetry for the benchmarks (pattern: Unit.dbg_plan_*) — pure counters.
static var dbg_plot_scans: int = 0
static var dbg_plot_cells: int = 0
static var dbg_plot_us: int = 0


## Orientation of the plot _find_plot just accepted. Only valid IMMEDIATELY
## after a successful call — keeping _find_plot's return type a plain Vector2i
## avoids touching every caller and test.
var _plot_orientation: int = 0
## Shared cell budget for ONE _find_plot call (all anchors, both passes). It
## used to be a per-sweep budget, which with up to 4 anchors x 2 passes would
## have allowed 9600 cells in a single tick.
var _plot_budget: int = 0
## Shared budget of EXPENSIVE candidates (each one costs a _plot_reachable A*,
## and a failing one explores the whole reachable component). This has to be
## shared for the same reason as the cell budget: 10e sweeps up to 4 settlement
## anchors plus the expansion anchor in two passes, so a per-sweep budget of 40
## would allow 400 A* runs in a single tick. Measured: that alone pushed the
## worst AI tick from ~54 ms to ~130 ms. Two sweeps' worth is the old ceiling.
var _plot_candidates_left: int = 0
## True while _find_plot sweeps its anchors — then both budgets are SHARED and
## must not be refilled between anchors. A direct _find_supplied_plot call
## (tests, single-anchor probes) refills them instead of scanning nothing.
var _plot_sweep: bool = false
## Round-robin cursor over the non-base settlement anchors (see _find_plot).
var _anchor_cursor: int = 0
var _settlement_cache: Array[Vector2i] = []
var _settlement_age: int = 0
var _base_island_cache: int = -1
var _base_island_version: int = -1


## Plot search with wood supply, sweeping the settlement anchors nearest-first
## (base, hut clusters, forward racks — a 25-hut village outgrows a single ring
## around one point) and falling back to the wood expansion anchor.
##
## TWO passes: first everything with the spacing requirement, then everything
## without. The relax pass is mandatory — on tight maps a hard spacing rule can
## starve the search completely and the AI would simply stop building.
func _find_plot(footprint: Vector2i, cache: TickCache = null,
		prefer: Vector2i = Vector2i(-1, -1)) -> Vector2i:
	var t0: int = Time.get_ticks_usec()
	dbg_plot_scans += 1
	_plot_budget = Balance.AI_MAX_PLOT_SCAN_CELLS
	_plot_candidates_left = MAX_PLOT_CANDIDATES * 2
	_plot_orientation = 0
	# The sweep COUNT is what the plot search costs: each sweep chews through the
	# shared cell budget before giving up. Sweeping all settlement anchors in both
	# passes (up to 10 sweeps) measured at 1149 cells per search against ~269
	# before 10e. So the list stays short: the base, ONE rotating hut cluster (so
	# every cluster gets its turn across ticks instead of all of them every tick)
	# and the wood expansion anchor.
	var anchors: Array[Vector2i] = []
	if prefer.x >= 0:
		anchors.append(prefer)
	var settlement: Array[Vector2i] = _settlement_anchors(cache)
	if not settlement.is_empty() and not (settlement[0] in anchors):
		anchors.append(settlement[0])   # always the base
	if settlement.size() > 1:
		_anchor_cursor = (_anchor_cursor + 1) % (settlement.size() - 1)
		var rotating: Vector2i = settlement[1 + _anchor_cursor]
		if not (rotating in anchors):
			anchors.append(rotating)
	var expansion: Vector2i = _expansion_anchor()
	if expansion.x >= 0 and not (expansion in anchors):
		anchors.append(expansion)
	var cell: Vector2i = Vector2i(-1, -1)
	_plot_sweep = true
	for anchor in anchors:
		cell = _find_supplied_plot(anchor, footprint, true)
		if cell.x >= 0:
			break
	if cell.x < 0 and not anchors.is_empty():
		# Anti-starvation relax pass, BASE ONLY: a hard spacing rule can starve
		# the search on tight maps and stop the AI building at all, but relaxing
		# every anchor would double the whole search.
		cell = _find_supplied_plot(anchors[0], footprint, false)
	_plot_sweep = false
	dbg_plot_us += Time.get_ticks_usec() - t0
	return cell


## Ring search for the first valid plot that has wood in reach AND is
## reachable from the base (phase 8.2). Gives up after MAX_PLOT_CANDIDATES
## unsupplied/unreachable candidates (then the next anchor takes over).
## The ring starts at AI_PLOT_MIN_RADIUS so buildings stop clinging to the anchor.
func _find_supplied_plot(anchor: Vector2i, footprint: Vector2i,
		require_clearance: bool = true) -> Vector2i:
	if not _plot_sweep:
		_plot_budget = Balance.AI_MAX_PLOT_SCAN_CELLS
		_plot_candidates_left = MAX_PLOT_CANDIDATES * 2
	# Per-sweep share on top of the shared ceiling: the shared budget alone is
	# first-come-first-served, so a base sweep over treeless ground would eat it
	# all and the expansion anchor — the whole point of expanding toward wood —
	# would never get a single candidate.
	var checked: int = 0
	var per_sweep: int = maxi(1, MAX_PLOT_CANDIDATES / 2)
	for radius in range(Balance.AI_PLOT_MIN_RADIUS, Balance.AI_PLOT_SEARCH_RADIUS):
		for cell in ring_cells(anchor, radius):
			if _plot_budget <= 0:
				return Vector2i(-1, -1)
			dbg_plot_cells += 1
			_plot_budget -= 1
			# Entrance faces the settlement; a non-square footprint turns with
			# it, so orientation has to be decided BEFORE the placement checks.
			var orientation: int = _orientation_toward(cell, footprint, anchor)
			var fp: Vector2i = footprint
			if orientation % 2 == 1:
				fp = Vector2i(footprint.y, footprint.x)
			# Checks strictly cheapest-first: can_place_at (a few cell lookups),
			# then the bucket-indexed tree count, then the clearance ring
			# ((footprint+4)^2 lookups — 144 for the 8x8 firewarrior camp), and
			# only last the A* reachability. Measured: with clearance ahead of the
			# tree count the plot search cost 3x as much per tick.
			if not commands.can_place_at(cell, fp):
				continue
			# Every placeable-but-rejected candidate counts toward the per-sweep
			# give-up counter, so a hopeless anchor (treeless ground around the
			# base) bails out early and leaves cell budget for the other anchors.
			if checked >= per_sweep:
				return Vector2i(-1, -1)
			if _trees_near_cell(cell) < MIN_TREES_NEAR_PLOT:
				checked += 1
				continue
			if require_clearance and not _plot_has_clearance(cell, fp):
				checked += 1
				continue
			# Only the A* consumes the SHARED expensive ceiling.
			if _plot_candidates_left <= 0:
				return Vector2i(-1, -1)
			if not _plot_reachable(cell):
				_plot_candidates_left -= 1
				checked += 1
				continue
			_plot_orientation = orientation
			return cell
	return Vector2i(-1, -1)


## No other building within AI_PLOT_SPACING cells of the footprint. This is what
## ends the "building blocked / unreachable" symptom: the AI used to pack plots
## edge to edge around one anchor. Only ever called for candidates that already
## passed can_place_at, so its own footprint cells are known to be free.
func _plot_has_clearance(cell: Vector2i, footprint: Vector2i) -> bool:
	if nav_grid == null:
		return true   # headless AI tests without terrain wiring
	var r: Rect2i = Rect2i(cell, footprint).grow(Balance.AI_PLOT_SPACING)
	for z in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			if nav_grid.is_cell_blocked_by_building(Vector2i(x, z)):
				return false
	return true


## Entrance side facing `anchor` (Building.orientation 0..3 = S/E/N/W; cell.y IS
## the z axis). Before 10e the AI placed EVERYTHING with orientation 0, which
## left doors facing away from the village and paths running around the building.
static func _orientation_toward(cell: Vector2i, footprint: Vector2i,
		anchor: Vector2i) -> int:
	var centre: Vector2 = Vector2(cell) + Vector2(footprint) * 0.5
	var d: Vector2 = Vector2(anchor) - centre
	if absf(d.x) >= absf(d.y):
		return 1 if d.x > 0.0 else 3
	return 0 if d.y > 0.0 else 2


## Anchors the plot search sweeps, base first: the base anchor, hut-cluster
## centres and the forward wood racks. Cached for AI_SETTLEMENT_TTL_TICKS.
func _settlement_anchors(cache: TickCache) -> Array[Vector2i]:
	if cache == null:
		return [base_anchor] as Array[Vector2i]
	_settlement_age += 1
	if not _settlement_cache.is_empty() \
			and _settlement_age <= Balance.AI_SETTLEMENT_TTL_TICKS:
		return _settlement_cache
	var anchors: Array[Vector2i] = [base_anchor]
	# Greedy clustering: each hut joins the first cluster within the radius.
	var centres: Array[Vector2] = []
	var weights: Array[int] = []
	for hut in cache.huts:
		var p: Vector2 = Vector2(hut.cell)
		var joined: bool = false
		for i in range(centres.size()):
			if centres[i].distance_to(p) <= float(Balance.AI_SETTLEMENT_CLUSTER_RADIUS):
				var w: float = float(weights[i])
				centres[i] = (centres[i] * w + p) / (w + 1.0)
				weights[i] += 1
				joined = true
				break
		if not joined:
			centres.append(p)
			weights.append(1)
	for centre in centres:
		var c: Vector2i = Vector2i(roundi(centre.x), roundi(centre.y))
		if not (c in anchors):
			anchors.append(c)
	for depot in cache.forward_depots:
		if not (depot.cell in anchors):
			anchors.append(depot.cell)
	# Nearest to the base first, then cap — the base itself stays at index 0.
	anchors.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a - base_anchor).length_squared() \
			< Vector2(b - base_anchor).length_squared())
	if anchors.size() > Balance.AI_MAX_SETTLEMENT_ANCHORS:
		anchors.resize(Balance.AI_MAX_SETTLEMENT_ANCHORS)
	_settlement_cache = anchors
	_settlement_age = 0
	return anchors


## Island the base stands on (cached against the walkability version).
func _base_island() -> int:
	if nav_grid == null:
		return -1
	if _base_island_version == nav_grid.change_version:
		return _base_island_cache
	# The anchor cell itself is usually COVERED by the reincarnation site and
	# therefore unwalkable (island -1) — snap to the nearest walkable cell first,
	# otherwise every fresh site would look unreachable and get scrapped.
	_base_island_cache = nav_grid.island_at(nav_grid.nearest_walkable_cell(base_anchor))
	_base_island_version = nav_grid.change_version
	return _base_island_cache


## Accepts a freshly placed site, or scraps it when no worker can ever reach it.
## Thanks to 10d an unbuilt site (build_progress == 0) vanishes instantly with a
## full refund, so a layout mistake no longer blocks a construction slot forever.
##
## Banning the cell is the essential half: without it the AI would place and
## demolish the SAME cell on every tick — an endless loop, worse than the bug.
func _accept_or_scrap_site(site: Building, cell: Vector2i) -> bool:
	if nav_grid == null or site == null or not is_instance_valid(site):
		return true
	var base: int = _base_island()
	if base < 0:
		return true   # cannot tell — never scrap on a guess
	var island: int = site.approach_island()
	if island >= 0 and island == base:
		return true
	commands.demolish_building(tribe, site)
	_unreachable_plots[cell] = true
	return false


## True when a worker can actually WALK from the base anchor to the plot.
## can_place_at only checks the plot itself (land/flat/free) — a walkable but
## isolated plateau passes it, the workers never arrive and the dead
## construction site blocks a build slot (Bergpass bug). The failing A*
## is expensive (it explores the whole reachable component), so negatives go
## into a session cache and are never re-tried.
func _plot_reachable(cell: Vector2i) -> bool:
	if nav_grid == null:
		return true   # headless AI tests without terrain wiring
	if _unreachable_plots.has(cell):
		return false
	# A proven-reachable plot stays proven while walkability is unchanged
	# (exact — every walkability change bumps change_version).
	if _reachable_plots.get(cell, -1) == nav_grid.change_version:
		return true
	var to: Vector3 = nav_grid.cell_to_world(cell)
	var path: PackedVector3Array = nav_grid.find_path(
		nav_grid.cell_to_world(base_anchor), to)
	if not path.is_empty():
		# find_path snaps an unwalkable target to the nearest walkable cell —
		# that snap can land ACROSS the cliff, so the path must really end at
		# the plot to count.
		var endp: Vector3 = path[path.size() - 1]
		if Vector2(endp.x - to.x, endp.z - to.z).length() <= 3.0:
			_reachable_plots[cell] = nav_grid.change_version
			return true
	_unreachable_plots[cell] = true
	return false


## True when fewer than FORESTER_MIN_TREES trees stand within PLOT_TREE_RADIUS
## of the base anchor (no tree data -> false, so headless AI tests are stable).
func _wood_thin_near_base() -> bool:
	if tree_manager == null or nav_grid == null:
		return false
	var pos: Vector3 = nav_grid.cell_to_world(base_anchor)
	return tree_manager.count_trees_near(pos, PLOT_TREE_RADIUS) < FORESTER_MIN_TREES


## Keeps AIState.forester_workers idle braves working in each usable forester
## (never below the minimum economy crew). The forester ignores braves once
## its slots are full.
func _staff_foresters(cache: TickCache) -> void:
	if cache.foresters.is_empty():
		return
	if cache.brave_count <= AIState.min_economy_braves(cache.population):
		return
	# 2 workers early, up to the forester's full 4 once the tribe can spare them.
	var workers: int = AIState.forester_workers(cache.brave_count)
	for f in cache.foresters:
		while f.occupants.size() < workers and f.has_free_slot():
			var brave: Array[Unit] = cache.take_idle(1)
			if brave.is_empty():
				return
			commands.order_forester(brave, f)


## Keeps idle braves working in each usable production shop up to its own
## slot count (7f; never below the minimum economy crew) — the Workshop check
## covers the fire-ram workshop and the airship wharf (subclasses). Fresh
## vehicles are auto-manned by their shop.
func _staff_workshops(cache: TickCache) -> void:
	if cache.workshops.is_empty():
		return
	if cache.brave_count <= AIState.min_economy_braves(cache.population):
		return
	for ws in cache.workshops:
		while ws.occupants.size() < ws.worker_slots() and ws.has_free_slot():
			var brave: Array[Unit] = cache.take_idle(1)
			if brave.is_empty():
				return
			commands.order_workshop(brave, ws)


## Routes part of the brave stream into training AT THE SOURCE (10g): a hut whose
## rally point lies on a usable training building sends every fresh brave straight
## into that camp's queue (Hut._spawn_brave -> Building.rally_training_building,
## engine behaviour since 5d that the AI never used — it set no rally point on ANY
## building).
##
## Two things this buys beyond saving commands: the brave never becomes IDLE, so it
## cannot be grabbed by the wood crews / workshop staffing that read the same idle
## pool, and _tick_train no longer needs one order per brave.
##
## Deliberately throttled and hysteretic: a rally point that moves every tick would
## send the stream ping-ponging between camps. Only re-assigned every
## AI_HUT_RALLY_TICK_INTERVAL ticks.
func _tick_hut_rallies(cache: TickCache) -> void:
	if commands == null or cache.huts.is_empty():
		return
	if _tick_count % Balance.AI_HUT_RALLY_TICK_INTERVAL != 0:
		return
	# Camps that can actually take a queue, in army-mix deficit order — the same
	# truth _tick_train uses, so the routing and the batch cannot disagree.
	var order: Array[StringName] = AIState.training_kind_order(
		cache.kind_counts[&"warrior"], cache.kind_counts[&"firewarrior"],
		cache.kind_counts[&"preacher"])
	var camps: Array[Building] = []
	for kind in order:
		var camp: TrainingBuilding = _camp_for(cache, kind)
		if camp != null:
			camps.append(camp)
	var share: float = AIState.training_hut_share(state, cache.army_count,
		attack_wave_size)
	# floori, never ceil: rounding UP would route every hut of a one-hut tribe and
	# leave it without a single free brave.
	var wanted: int = clampi(int(floor(float(cache.usable_huts) * share)),
		0, maxi(cache.usable_huts - 1, 0))
	if camps.is_empty():
		wanted = 0
	var assigned: int = 0
	for i in range(cache.huts.size()):
		var hut: Building = cache.huts[i]
		if not is_instance_valid(hut) or not hut.is_usable():
			continue
		if assigned < wanted:
			var camp: Building = camps[assigned % camps.size()]
			# Already pointing at the right camp: leave it alone (hysteresis).
			if hut.rally_training_building() != camp:
				commands.set_rally_point(tribe, hut, camp.center_world())
			assigned += 1
		elif hut.rally_training_building() != null:
			# Over the share: hand the hut back to free-brave production.
			commands.set_rally_point(tribe, hut, hut.edge_spawn_position())
	dbg_hut_rallies = assigned


## Boards idle firewarriors onto own under-crewed airships (first AI stage:
## the ship flies with the attack wave and its deck crew fires on arrival —
## no unload micro). Uses the same mobile-reserve rule as the towers so the
## ground force is not starved.
func _man_airships(cache: TickCache) -> void:
	if cache.understaffed_airships.is_empty():
		return
	# Keep a mobile reserve on the ground (same rule as the watchtowers).
	var budget: int = mini(cache.idle_fw_left(),
		cache.total_firewarriors - WATCHTOWER_MIN_MOBILE_FW)
	for ship in cache.understaffed_airships:
		while budget > 0 and ship.crew_count() < (ship as Airship).max_crew:
			var fw: Array[Unit] = cache.take_idle_fw(1)
			if fw.is_empty():
				return
			commands.order_crew(fw, ship)
			budget -= 1


## Mans usable watchtowers that still have room with idle firewarriors, keeping
## at least WATCHTOWER_MIN_MOBILE_FW firewarriors mobile so the attack force is
## not starved (7h). Warriors/preachers stay in the field; the AI garrisons the
## ranged fire posts.
func _man_watchtowers(cache: TickCache) -> void:
	if cache.towers.is_empty():
		return
	for tower in cache.towers:
		while tower.has_crew_room():
			if cache.idle_fw_left() <= WATCHTOWER_MIN_MOBILE_FW:
				return   # keep a mobile firewarrior reserve
			var fw: Array[Unit] = cache.take_idle_fw(1)
			if fw.is_empty():
				return
			commands.order_garrison(fw, tower)


func _trees_near_cell(cell: Vector2i) -> int:
	if tree_manager == null or nav_grid == null:
		return MIN_TREES_NEAR_PLOT   # no tree data (tests): treat as supplied
	var pos: Vector3 = nav_grid.cell_to_world(cell)
	return tree_manager.count_trees_near(pos, PLOT_TREE_RADIUS)


## Cell of the nearest tree to the base — the anchor for expanding the base
## toward fresh wood. Cached for a few ticks: the pick scans every tree with
## an island check each, and the nearest grove does not move second-to-second.
func _expansion_anchor() -> Vector2i:
	if tree_manager == null or nav_grid == null:
		return Vector2i(-1, -1)
	_expansion_anchor_age += 1
	if _expansion_anchor_cache.x >= 0 \
			and _expansion_anchor_age <= EXPANSION_ANCHOR_TTL_TICKS \
			and tree_manager.has_tree_at(_expansion_anchor_cache):
		return _expansion_anchor_cache
	var tree = tree_manager.nearest_tree(nav_grid.cell_to_world(base_anchor))
	if tree == null or not is_instance_valid(tree):
		_expansion_anchor_cache = Vector2i(-1, -1)
		return Vector2i(-1, -1)
	_expansion_anchor_cache = nav_grid.world_to_cell(tree.position)
	_expansion_anchor_age = 0
	return _expansion_anchor_cache


## A site far from the base gets an escort of idle braves — the
## BuildingManager only recruits workers within ~30 m of the site.
func _send_escort_if_remote(cache: TickCache, cell: Vector2i) -> void:
	if nav_grid == null:
		return
	if Vector2(cell - base_anchor).length() <= EXPANSION_DISTANCE:
		return
	var escort: Array[Unit] = cache.take_idle(EXPANSION_ESCORT)
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
