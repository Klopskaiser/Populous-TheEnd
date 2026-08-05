class_name Brave extends Unit

## Basic follower unit. On top of Unit it implements the worker behaviour:
##
## - Construction job (State.BUILD, `job` set): the brave picks its own
##   sub-task at the site — FLATTEN a foundation cell (hopping on the spot),
##   CHOP a nearby tree / PICKUP a distant wood pile and DELIVER the wood to
##   the entrance, or CONSTRUCT once the foundation is level. Wood is only
##   gathered when a construction site needs it.
## - Loose chopping (State.GATHER, right-click on a tree): fell the tree,
##   drop the wood as a pile on the spot, continue with nearby trees.
##
## All logic runs in tick(delta) and works without the scene tree. References
## to trees/piles are kept untyped because they may be freed by other workers.

## UPGRADE (10f) is appended on purpose — new entries go at the end so the
## existing ordinals stay stable.
enum Task {NONE, FLATTEN, CHOP, PICKUP, DELIVER, CONSTRUCT, REPAIR, PRODUCE,
	DEMOLISH, UPGRADE}
## Sub-phase of the forester job (State.FORESTER, phase 7d): walking in to be
## housed, walking out to a plant spot, kneeling to plant, walking back in.
enum ForesterPhase {JOIN, PLANT_GO, KNEEL, RETURN}

## How long the brave kneels to plant a sapling.
const PLANT_KNEEL_TIME: float = 0.8
const FORESTER_RANGE: float = 1.2
const PLANT_RANGE: float = 0.8

const CARRY_CAPACITY: int = 3
## When delivering loose wood, prefer merging onto an existing pile within this
## radius of the target building instead of starting a new one.
const DROP_CONSOLIDATE_RADIUS: float = 5.0
const CHOP_RANGE: float = 1.5
const WORK_RANGE: float = 1.7       # flatten-spot range
const DELIVER_RANGE: float = 2.0
const PICKUP_RANGE: float = 1.2
const TRAIN_SLOT_RANGE: float = 0.7   # how close to a queue slot counts as "in it"
## If the nav path ends short of the goal but within this distance, walk the
## last stretch in a straight line (footprint cells are nav-solid).
const DIRECT_WALK_RANGE: float = 4.5
const FLATTEN_RATE: float = 0.5     # metres of vertex adjustment per second
const BUILD_RATE: float = 0.2       # build_progress per second
const REPAIR_RATE: float = 10.0     # building HP repaired per second per worker
const JOB_TREE_RADIUS: float = 40.0 # tree search radius around the site
const CHOP_CHAIN_RADIUS: float = 8.0
const TASK_RETRY: float = 0.6
## Consecutive seek failures double the retry delay up to this cap (a worker
## whose goals stay unreachable must not burn a full-map failing A* at the
## base cadence forever)...
const TASK_RETRY_MAX: float = 4.8
## ...and after this many consecutive failures the worker QUITS the job
## (goes IDLE like a wood-stalled site's crew). The BuildingManager re-drafts
## idle braves periodically, so a transiently blocked site self-heals while a
## truly unreachable one stops eating pathfinding time.
const SEEK_FAIL_QUIT_STREAK: int = 6
## A wood pile is only preferred over chopping when it lies within this radius
## of the construction site (otherwise fetching it is not worth it) AND no enemy
## is within WOOD_ENEMY_RADIUS of it — a pile guarded by enemies is skipped in
## favour of a tree in a safer spot.
const PILE_PREFER_RADIUS: float = 24.0
const WOOD_ENEMY_RADIUS: float = 8.0

## Area orders (key B, phase 10e) fill the load before delivering — a grove 50 m
## away with one-piece trips would be unplayable. The single-tree order keeps its
## one-piece-per-trip behaviour.
const DEPOT_PREFER_RADIUS: float = Balance.HARVEST_DEPOT_PREFER_RADIUS
## Nothing claimable in the area right now (crewmates hold every slot): the order
## is HELD for TASK_RETRY and retried this often before the brave gives up.
const AREA_RETRY_MAX: int = 5

## Injected by UnitManager.spawn_unit() (or directly by tests).
var tree_manager: TreeManager = null
var wood_pile_manager: WoodPileManager = null

var job: Building = null
var task: Task = Task.NONE
var carried_wood: int = 0
var task_cell: Vector2i = Vector2i(-1, -1)
var task_tree: Object = null   # untyped: may be freed by another worker
var task_pile: Object = null   # untyped: may be freed
var target_building: Building = null   # forester / training site
## Training building this brave queues at (State.TRAIN). The building assigns a
## queue slot each tick; train_reached_slot flips true once the brave stands in
## it, and the building admits the front brave when its bay is free.
var train_target: TrainingBuilding = null
var train_slot_pos: Vector3 = Vector3.INF
var train_reached_slot: bool = false

## Forester assignment (State.FORESTER, phase 7d). `forester_home` is the
## forester whose worker slot this brave holds; `forester_inside` is true while
## it is housed (removed from the world); otherwise it is walking in/out.
var forester_home: Forester = null
var forester_inside: bool = false
## Workshop slot (phase 7f, forester-style): true while housed inside the
## workshop (removed from the world; `job` holds the workshop itself).
var workshop_inside: bool = false
var _forester_phase: ForesterPhase = ForesterPhase.JOIN
var _plant_target: Vector3 = Vector3.INF
var _kneel_timer: float = 0.0

var _chop_timer: float = 0.0
var _retry_timer: float = 0.0
## Throttle for the job reachability re-check (phase 10d): terrain deformation
## can cut a worker off from its site mid-job.
var _job_reach_timer: float = 0.0
## Consecutive unreachable-goal failures (escalating backoff, see
## _on_seek_failed); reset by any successfully completed sub-task.
var _seek_fail_streak: int = 0
var _working: bool = false
## Whether the continuous wood-chop sound loop is currently running for us
## (paired with AudioManager.start_loop/stop_loop, see _update_chop_loop).
var _chop_loop_on: bool = false
var _seek_goal: Vector3 = Vector3.INF
## Where the loose-chopping brave was working, to return after a delivery.
var _loose_return_pos: Vector3 = Vector3.INF
## Cached loose-delivery drop target (re-picked on a slow cadence with
## hysteresis — per-tick re-picking made carrying braves spin in place).
var _loose_deliver_goal: Vector3 = Vector3.INF
var _loose_deliver_recheck: float = 0.0
## Building the cached drop target belongs to (wood is stored INTO a depot).
var _loose_deliver_building: Building = null
## Depot haul (right-click on a wood depot / pile relay): fixed target depot;
## `_haul_source` additionally set for the depot->depot pendulum loop.
var _haul_source: WoodDepot = null
var _haul_target: WoodDepot = null
## Pinned SUPPLY target (10g Teil 4): a specific own building this brave carries
## wood to. Deliberately a SECOND field next to _haul_target instead of widening
## that one: _haul_target is not merely typed as a depot, its semantics ARE depot
## semantics (_haul_valid and the fixed-target branch both gate on
## storage_left() > 0). A site or workshop has no storage_left(); its "full"
## predicate is wants_more_wood() / wants_more_stock_wood(). Widening the type
## would spread the depot-haul invariants across type tests inside the hot
## delivery path — the same number of branches, but with a regression risk in a
## feature the tests already pin down.
var _supply_target: Building = null
## Carry-and-hold (10h): set by order_pickup. The brave keeps the wood in its hands
## and waits for a DROP order instead of delivering on its own — the second
## right-click decides where it goes. The automatic delivery is still what the
## standing area order (key B) does; only the single-pile right-click changed.
var carry_hold: bool = false
## Seconds the brave has been holding wood with no drop order. At
## Balance.BRAVE_CARRY_HOLD_TIMEOUT it puts the wood down where it stands, so a
## forgotten carrier does not walk around with it forever (user decision).
var _carry_hold_timer: float = 0.0
## Drop destination of the current hold order; INF while none is set.
var _carry_drop_goal: Vector3 = Vector3.INF
## Optional building the load goes INTO: a WoodDepot stores it in its rack, any
## other own building absorbs the dropped pile as usual. This replaces the old
## pile relay (a pile at a friendly building was carried to the nearest rack) —
## that only ever triggered on the single right-click, which now HOLDS the wood,
## so it had no trigger left at all.
var _carry_drop_into: Building = null

## Standing area-harvest order (phase 10e, key B and the AI wood crews): while
## set, the brave keeps claiming trees inside this world-XZ rectangle, fills
## CARRY_CAPACITY and delivers, until the area is worked out. Any other order
## clears it through _interrupt_tasks -> one order at a time, for free.
var chop_area: Rect2 = Rect2()
## Optional convex quad (world XZ) narrowing the rectangle — the four raycast
## drag corners under a rotated camera. Empty = plain rectangle.
var chop_area_poly: PackedVector2Array = PackedVector2Array()
## Hold timer / attempt counter while the area has no free claim slot.
var _area_retry: float = 0.0
var _area_retries: int = 0


func _init() -> void:
	max_health = Balance.BRAVE_HP
	health = max_health
	speed = Balance.BRAVE_SPEED
	idle_aggro = IDLE_AGGRO_RADIUS   # small village-guard radius (phase 7b)
	died.connect(func(_unit: Unit) -> void: _interrupt_tasks())


func unit_kind() -> StringName:
	return &"brave"


## Before the brave starts fighting (retaliation or an explicit attack order),
## release its worker claims / drop carried wood so nothing is left stranded.
func _on_combat_interrupt() -> void:
	if state == State.GATHER or state == State.BUILD \
			or state == State.TRAIN or state == State.FORESTER:
		_interrupt_tasks()


## Harmless downhill stumble (phase 8.2): the carrier drops its wood on the
## spot but KEEPS its task — resuming the fetch, the normal task selection
## finds the dropped pile right at its feet and picks it back up.
func _on_stumble() -> void:
	if carried_wood > 0 and wood_pile_manager != null:
		wood_pile_manager.deposit(position, carried_wood)
		carried_wood = 0


## Wood this worker expects to take from its claimed tree, counted by the
## site as incoming (capped by what the brave can still carry).
func claimed_tree_yield() -> int:
	if task == Task.CHOP and _tree_valid(task_tree):
		return mini(task_tree.wood_yield(), CARRY_CAPACITY - carried_wood)
	return 0


# --- Orders --------------------------------------------------------------------

## Move orders interrupt any running task (claims are released, carried wood
## is dropped as a pile).
func order_move(target: Vector3, queue_up: bool = false, aggressive: bool = false) -> void:
	if state == State.GATHER or state == State.BUILD:
		_interrupt_tasks()
	super.order_move(target, queue_up, aggressive)


## Braves keep a small guard radius even while idling (phase 7b): enemies
## walking right into the village get attacked; farther ones are ignored.
## Applied to Unit.idle_aggro in _init (a field, not a virtual — hot path).
const IDLE_AGGRO_RADIUS: float = Balance.BRAVE_IDLE_AGGRO_RADIUS


## Manual pickup order (right-click on a wood pile, 10h): fetch the pile and HOLD
## it. The brave no longer delivers on its own — the next right-click says where the
## wood goes (order_drop_wood). Holding it without an order for
## BRAVE_CARRY_HOLD_TIMEOUT puts it down on the spot.
##
## The automatic "carry it to the nearest wood spot" behaviour is deliberately kept
## for the standing AREA order (key B): there the player asked for a whole patch to
## be cleared, not for a hand-placed load.
func order_pickup(pile: WoodPile) -> void:
	if not can_take_orders():
		return
	if pile == null or not is_instance_valid(pile) or pile.amount <= 0:
		return
	_interrupt_tasks()
	task_pile = pile
	task = Task.PICKUP
	carry_hold = true
	_carry_hold_timer = 0.0
	_carry_drop_goal = Vector3.INF
	_loose_return_pos = Vector3.INF
	_set_state(State.GATHER)


## Drop order (second right-click while holding wood, 10h): walk to `point` and put
## the load down there. A point ON an own building uses its delivery_point, so the
## building absorbs the wood exactly as a worker delivery would.
func order_drop_wood(point: Vector3, into: Building = null) -> bool:
	if not can_take_orders() or not carry_hold or carried_wood <= 0:
		return false
	task_pile = null
	task_tree = null
	_carry_drop_into = into
	_carry_drop_goal = point
	_carry_hold_timer = 0.0
	task = Task.NONE
	_reset_seek()
	_set_state(State.GATHER)
	return true


## True while this brave holds wood and waits for a drop order — the predicate the
## UI needs to turn the next right-click into order_drop_wood.
func holds_wood_for_drop() -> bool:
	return carry_hold and carried_wood > 0


## Haul order (right-click on a wood depot): carry its stock to the nearest
## OTHER depot in a pendulum loop. Without a second depot (or with an empty
## source) the brave just walks there — a plain move (user decision).
func order_depot_haul(depot: WoodDepot) -> void:
	if not can_take_orders():
		return
	if depot == null or not is_instance_valid(depot) or not depot.is_usable():
		return
	var target: WoodDepot = _nearest_depot(depot.position, depot)
	if target == null or depot.stored_wood() <= 0:
		order_move(depot.center_world())
		return
	_interrupt_tasks()
	_haul_source = depot
	_haul_target = target
	task = Task.PICKUP
	_loose_return_pos = Vector3.INF
	_set_state(State.GATHER)


## Manual chop order (right-click on a tree): harvest it unit by unit, drop
## the wood on the spot, then continue with nearby trees. Player orders always
## count, even when the tree's harvest slots are full. Returns whether the order
## was taken — the UI only blinks its confirmation ring for an accepted one.
func order_chop(tree: TreeResource) -> bool:
	if not can_take_orders():
		return false
	if tree == null or not is_instance_valid(tree) or tree.felled_flag:
		return false
	_interrupt_tasks()
	task_tree = tree
	tree.add_claimer(self)
	_chop_timer = tree.chop_time()
	task = Task.CHOP
	_loose_return_pos = Vector3.INF
	_set_state(State.GATHER)
	return true


## True while a standing area-harvest order is set.
func has_chop_area() -> bool:
	return chop_area.size.x > 0.0 and chop_area.size.y > 0.0


## True while this brave runs a depot->depot haul loop. The AI's crew
## bookkeeping needs an exact predicate here — State.IDLE would misfire on the
## tick the order was given (the brave has not ticked yet).
##
## The _supply_target clause keeps the two predicates DISJOINT: a supply job may
## source its wood from a rack and therefore also sets _haul_source, and
## AIController._tick_forward_haul prunes its crew with this predicate.
func has_depot_haul() -> bool:
	return _supply_target == null and _haul_source != null 		and is_instance_valid(_haul_source)


## True while a standing supply job is set (10g Teil 4). Exact predicate for the
## AI bookkeeping, NEVER State.IDLE — same trap as has_chop_area().
func has_supply_job() -> bool:
	return _supply_target != null and is_instance_valid(_supply_target)


## Standing supply order (AI wood logistics): carry wood to ONE specific own
## building until it no longer wants any. Source is picked per trip: the nearest
## rack, else a ground pile, else a tree.
func order_supply_wood(target: Building) -> bool:
	if not can_take_orders():
		return false
	if target == null or not is_instance_valid(target) or target.health <= 0:
		return false
	if not _target_wants_wood(target):
		return false
	# Order matters: _interrupt_tasks CLEARS _supply_target.
	_interrupt_tasks()
	_supply_target = target
	_loose_return_pos = Vector3.INF
	_set_state(State.GATHER)
	if not _choose_supply_task():
		_stop_all()
		return false
	return true


## Whether a pinned delivery target can still take wood. THE one place that knows
## the per-kind predicate.
func _target_wants_wood(target: Building) -> bool:
	if target == null or not is_instance_valid(target) or target.health <= 0:
		return false
	if target is WoodDepot:
		return target.is_usable() and (target as WoodDepot).storage_left() > 0
	if target is Workshop:
		return target.is_usable() and (target as Workshop).wants_more_stock_wood()
	if target.under_construction:
		return target.wants_more_wood()
	if target.upgrading:
		return target.wants_upgrade_wood()
	return target.wants_more_repair_wood()


## Picks the wood source for the current supply trip. Mirrors _try_fetch_wood, but
## measured around the TARGET instead of a job.
##
## Explicitly does NOT call target.mark_wood_stalled() on failure: that would make
## BuildingManager._recruit_workers skip a construction target for 30 s and
## suppress a workshop's own fetch cycle — punishing the TARGET for the SUPPLIER's
## failure. The AI notices via has_supply_job() == false instead.
func _choose_supply_task() -> bool:
	if not _target_wants_wood(_supply_target):
		return false
	var drop: Vector3 = _supply_target.delivery_point()
	# 1) A rack with stock that does not already feed the target itself.
	var depot: WoodDepot = _nearest_depot_with_stock(drop)
	if depot != null:
		_haul_source = depot
		task = Task.PICKUP
		_reset_seek()
		return true
	# 2) A ground pile, outside the target's own absorb radius (that wood counts as
	#    delivered already).
	if wood_pile_manager != null:
		var pile: WoodPile = wood_pile_manager.nearest_pile(position, drop,
			Building.ABSORB_RADIUS)
		if pile != null and (nav_grid == null
				or nav_grid.same_island(position, pile.position)):
			task_pile = pile
			task = Task.PICKUP
			_reset_seek()
			return true
	# 3) Chop. 10e lesson A1: best_tree's `radius` steers the candidate filter AND
	#    the walk budget, so a tight radius kills every distant job.
	if tree_manager != null:
		var tree: TreeResource = tree_manager.best_tree(drop, position,
			JOB_TREE_RADIUS, true)
		if tree != null:
			tree.add_claimer(self)
			task_tree = tree
			_chop_timer = tree.chop_time()
			task = Task.CHOP
			_reset_seek()
			return true
	return false


## Nearest own usable rack with stock, same island, that is not the target and does
## not already sit inside the target's absorb radius (relaying a rack onto itself
## would be a pointless walk).
func _nearest_depot_with_stock(drop: Vector3) -> WoodDepot:
	if tribe == null:
		return null
	var best: WoodDepot = null
	var best_d: float = INF
	for building in tribe.buildings:
		if building == _supply_target or not is_instance_valid(building):
			continue
		if not (building is WoodDepot) or not building.is_usable():
			continue
		var depot: WoodDepot = building as WoodDepot
		if depot.stored_wood() <= 0:
			continue
		if depot.footprint_distance_to(Vector2(drop.x, drop.z)) <= Building.ABSORB_RADIUS:
			continue
		var d: float = _flat_dist(position, depot.delivery_point())
		if d >= best_d:
			continue
		if nav_grid != null and not nav_grid.same_island(position, depot.delivery_point()):
			continue
		best_d = d
		best = depot
	return best


## Standing area order (key B / AI wood crew): keep felling trees inside `area`
## and deliver full loads until it is worked out. Accepted even when nothing is
## claimable right now — the area is a JOB, not a single target, and crewmates
## free claim slots as they deliver (see _area_retry_hold). Returns whether the
## order was taken.
func order_chop_area(area: Rect2,
		poly: PackedVector2Array = PackedVector2Array()) -> bool:
	if not can_take_orders():
		return false
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return false
	# Order matters: _interrupt_tasks CLEARS chop_area, so it has to run first.
	_interrupt_tasks()
	chop_area = area
	chop_area_poly = poly
	task = Task.CHOP
	_loose_return_pos = Vector3.INF
	_set_state(State.GATHER)
	if not _next_area_source() and not _area_retry_hold():
		_stop_all()
		return false
	return true


## Next claimable tree inside the standing area (path-verified, island-checked —
## see TreeManager.claim_area_tree).
func _next_area_tree() -> bool:
	if tree_manager == null or not has_chop_area():
		return false
	var tree: TreeResource = tree_manager.claim_area_tree(
		chop_area, chop_area_poly, self, position)
	if tree == null:
		return false
	task_tree = tree
	task = Task.CHOP
	_chop_timer = tree.chop_time()
	_area_retry = 0.0
	_area_retries = 0
	_reset_seek()
	return true


## Next collectable wood pile inside the standing area (10g): lying wood counts
## as a wood source, gets picked up and goes to the drop-off like felled wood.
##
## Two guards keep this from becoming a loop, because the area order's own
## drop-off can lie inside the area:
##   * piles at a friendly building are DELIVERED wood, not loose wood (the same
##     test the manual pile relay uses) — that is exactly where this order drops
##     its own load;
##   * without any own building there is no drop-off at all, so nothing is
##     collected (the fallback would drop the load on the spot and re-collect it).
func _next_area_pile() -> bool:
	if wood_pile_manager == null or not has_chop_area():
		return false
	if carried_wood >= CARRY_CAPACITY:
		return false
	if _nearest_own_building() == null:
		return false
	var best: WoodPile = null
	var best_dist: float = INF
	for pile: WoodPile in wood_pile_manager.area_piles(chop_area, chop_area_poly):
		if _pile_near_friendly_building(pile.position):
			continue
		if nav_grid != null and not nav_grid.same_island(position, pile.position):
			continue
		var d: float = _flat_dist(position, pile.position)
		if d < best_dist:
			best_dist = d
			best = pile
	if best == null:
		return false
	task_pile = best
	task = Task.PICKUP
	_area_retry = 0.0
	_area_retries = 0
	_reset_seek()
	return true


## Next source inside the area, trees first (they are the primary job and their
## claim slots keep a crew spread out), lying wood second.
func _next_area_source() -> bool:
	return _next_area_tree() or _next_area_pile()


## Area order with nothing claimable at this moment: hold the order and retry
## after TASK_RETRY instead of running the (pooled, but not free) search every
## sim tick. False once the area counts as worked out — the caller stops then.
## Without this hold a whole crew goes idle at the tail of a grove, while its
## members still hold the last claim slots.
func _area_retry_hold() -> bool:
	if not has_chop_area():
		return false
	_area_retries += 1
	if _area_retries > AREA_RETRY_MAX:
		return false
	_area_retry = TASK_RETRY
	return true


## True while this brave can still take a worker slot at `building`. Checked
## BEFORE _interrupt_tasks (10d): a brave refused by a full site used to have
## dropped its wood and left its old job already, and then sat in State.BUILD
## with job == null until the next tick healed it. Own slot counts as room —
## _interrupt_tasks only frees it afterwards.
func _can_take_worker_slot(building: Building) -> bool:
	return self in building.workers or building.has_worker_room()


## Join a construction site as a worker (fails silently when the site already
## has MAX_WORKERS helpers).
func order_build(building: Building) -> void:
	if not can_take_orders():
		return
	if building == null or not is_instance_valid(building) or not building.under_construction:
		return
	if not _can_take_worker_slot(building):
		return
	_interrupt_tasks()
	if not building.join(self):
		return
	job = building
	_retry_timer = 0.0
	_set_state(State.BUILD)


## Repair a damaged building: join it as a worker. Wood for the repair
## (floor(damage * wood_cost), see Building.repair) is fetched with the same
## CHOP/PICKUP/DELIVER pipeline as construction (State.BUILD job system).
func order_repair(building: Building) -> void:
	if not can_take_orders():
		return
	if building == null or not is_instance_valid(building) or building.under_construction:
		return
	if building.health <= 0 or building.health >= building.max_health:
		return
	if not _can_take_worker_slot(building):
		return
	_interrupt_tasks()
	if not building.join(self):
		return
	job = building
	_retry_timer = 0.0
	_set_state(State.BUILD)


## Tear a building down (phase 10d): join it as a worker. The demolition itself
## is started by TribeCommands.demolish_building — this only puts hands on it.
func order_demolish(building: Building) -> void:
	if not can_take_orders():
		return
	if building == null or not is_instance_valid(building) or not building.demolishing:
		return
	if not _can_take_worker_slot(building):
		return
	_interrupt_tasks()
	if not building.join(self):
		return
	job = building
	_retry_timer = 0.0
	_set_state(State.BUILD)


## Upgrade a finished building (phase 10f, hut stages): join it as a worker. The
## upgrade is started by the building itself (Hut.begin_upgrade), which puts its
## own ejected crew on the job; the player can send more braves via right-click.
## Wood is fetched with the same CHOP/PICKUP/DELIVER pipeline as a repair.
func order_upgrade(building: Building) -> void:
	if not can_take_orders():
		return
	if building == null or not is_instance_valid(building) or not building.upgrading:
		return
	if not _can_take_worker_slot(building):
		return
	_interrupt_tasks()
	if not building.join(self):
		return
	job = building
	_retry_timer = 0.0
	_set_state(State.BUILD)


## Take a worker slot in a finished workshop (forester pattern, max
## Workshop.WORKER_SLOTS — ignored when no slot is free, no queue). The brave
## walks in and is housed inside; it only steps out to fetch stock wood
## (dispatched by the workshop) and to deliver it at the entrance.
func order_workshop(workshop: Workshop) -> void:
	if not can_take_orders():
		return
	if workshop == null or not is_instance_valid(workshop) or not workshop.is_usable():
		return
	if not workshop.has_free_slot():
		return
	_interrupt_tasks()
	if not workshop.reserve_slot(self):
		return
	job = workshop
	workshop_inside = false
	task = Task.PRODUCE   # PRODUCE = walk to the entrance and be housed
	_retry_timer = 0.0
	_reset_seek()
	_set_state(State.BUILD)


## Housed inside the workshop: already removed from the world, just settle
## (it stops ticking; the WORKSHOP contributes its worker-seconds).
func enter_workshop() -> void:
	_clear_path()
	task = Task.PRODUCE
	_set_working(false)
	set_selected(false)


## Dispatched by the workshop to fetch stock wood: back in the world (the
## workshop re-registered it), re-choose a task (the fetch pipeline).
func begin_workshop_fetch() -> void:
	task = Task.NONE
	_retry_timer = 0.0
	_reset_seek()


## Released from the workshop (ejected, building lost, or a new order).
## _interrupt_tasks releases the slot (release_worker is idempotent).
func leave_workshop() -> void:
	workshop_inside = false
	_stop_all()


## Queue up at a training building to be trained into a combat unit. The building
## assigns a slot each tick and admits the front brave when its bay is free.
func order_train(building: TrainingBuilding) -> void:
	if not can_take_orders():
		return
	if building == null or not is_instance_valid(building) or not building.is_usable():
		return
	_interrupt_tasks()
	building.add_trainee(self)
	train_target = building
	train_slot_pos = Vector3.INF
	train_reached_slot = false
	_set_state(State.TRAIN)


## Called by the building when the brave is admitted: it is already removed from
## the world, so just settle the state (it stops ticking after this).
func enter_training() -> void:
	_clear_path()
	train_reached_slot = true
	set_selected(false)


## Building gone / no longer trainable: leave the queue and go idle.
func cancel_training() -> void:
	train_target = null
	train_slot_pos = Vector3.INF
	train_reached_slot = false
	_stop_all()


# --- Forester assignment (phase 7d) ---------------------------------------------

## Assigns the brave to a forester's worker slot. It walks to the building and is
## housed inside (removed from the world, still counted as population). Ignored
## when no slot is free (no queue).
func order_forester(forester: Forester) -> void:
	if not can_take_orders():
		return
	if forester == null or not is_instance_valid(forester) or not forester.is_usable():
		return
	if not forester.has_free_slot():
		return
	_interrupt_tasks()
	if not forester.reserve_slot(self):
		return
	forester_home = forester
	forester_inside = false
	_forester_phase = ForesterPhase.JOIN
	_reset_seek()
	_set_state(State.FORESTER)


## Housed inside the forester: it is already removed from the world, so just
## settle the state (it stops ticking until dispatched to plant).
func enter_forester() -> void:
	_clear_path()
	_set_working(false)
	set_selected(false)


## Dispatched by the forester to plant a sapling at `target`: the brave steps
## back into the world (already re-registered by the forester) and walks out.
func begin_plant(target: Vector3) -> void:
	forester_inside = false
	_plant_target = target
	_forester_phase = ForesterPhase.PLANT_GO
	_reset_seek()
	if state != State.FORESTER:
		_set_state(State.FORESTER)


## Released from the forester (ejected, building lost, or a new order): drop the
## slot and go idle. forester_home is cleared FIRST so _interrupt_tasks does not
## call back into the forester.
func leave_forester() -> void:
	forester_home = null
	forester_inside = false
	_plant_target = Vector3.INF
	_stop_all()


# --- Tick ----------------------------------------------------------------------

## Worker-state dispatch; everything else (incl. the walk/idle/carry animation
## sync at the end of every tick) runs in the Unit base tick.
func _tick_state(delta: float) -> void:
	match state:
		State.GATHER:
			if carry_hold and carried_wood > 0:
				_tick_carry_hold(delta)
			elif task == Task.DELIVER:
				_tick_loose_deliver(delta)
			elif task == Task.PICKUP:
				_tick_pickup(delta)
			else:
				_tick_loose_chop(delta)
		State.BUILD:
			_tick_job(delta)
		State.TRAIN:
			_tick_train(delta)
		State.FORESTER:
			_tick_forester(delta)
		_:
			super._tick_state(delta)


# --- Construction job ---------------------------------------------------------------

func _tick_job(delta: float) -> void:
	if job == null or not is_instance_valid(job) or not _job_active():
		_interrupt_tasks()
		_set_state(State.IDLE)
		return
	# Terrain deformation (landbridge, earthquake, sink) can cut a worker off
	# from its site. Checked once a second (O(1) island compare): the brave then
	# drops its wood where it stands and quits instead of walking forever
	# against an unreachable goal (phase 10d).
	_job_reach_timer -= delta
	if _job_reach_timer <= 0.0:
		_job_reach_timer = 1.0
		if not (job as Building).worker_can_reach(position):
			if carried_wood > 0 and wood_pile_manager != null:
				wood_pile_manager.deposit(position, carried_wood)
				carried_wood = 0
			_interrupt_tasks()
			_set_state(State.IDLE)
			return
	match task:
		Task.NONE:
			_retry_timer -= delta
			if _retry_timer <= 0.0:
				_retry_timer = TASK_RETRY
				_choose_job_task()
		Task.FLATTEN:
			_tick_flatten(delta)
		Task.CHOP:
			_tick_job_chop(delta)
		Task.PICKUP:
			_tick_pickup(delta)
		Task.DELIVER:
			_tick_deliver(delta)
		Task.CONSTRUCT:
			_tick_construct(delta)
		Task.REPAIR:
			_tick_repair(delta)
		Task.PRODUCE:
			_tick_produce(delta)
		Task.DEMOLISH:
			_tick_demolish(delta)
		Task.UPGRADE:
			_tick_upgrade(delta)


## A job binds its workers while the building is under construction or (for
## repair jobs) damaged; a finished/fully repaired building releases them.
## Workshop workers (7f) stay bound only while they HOLD one of the three
## slots — construction workers are released when the workshop finishes and
## never slide into production duty without an explicit order.
## An UPGRADE (10f) has to be listed explicitly: the building it runs on is
## finished, undamaged and not being torn down, so without this clause every
## upgrade worker would drop the job on its very next tick.
func _job_active() -> bool:
	return job.under_construction \
		or job.demolishing \
		or job.upgrading \
		or (job.health > 0 and job.health < job.max_health) \
		or (job is Workshop and job.is_usable() and self in (job as Workshop).occupants)


## Workers pick their own sensible sub-task: deliver carried wood first; then
## flatten cells nobody works on yet; spare hands fetch wood in parallel
## (nearby tree or distant pile); leftover workers pile onto the remaining
## flatten cells; once the foundation is level, everyone constructs.
func _choose_job_task() -> void:
	if carried_wood > 0:
		# Deliver first even while tearing the building down: the wood lands as a
		# ground pile at the same delivery point the refund goes to (the site's
		# absorption is off during a demolition), so nothing is eaten — and the
		# brave is not stuck carrying 1-3 wood through the whole teardown.
		task = Task.DELIVER
		_reset_seek()
		return
	if job.demolishing:
		task = Task.DEMOLISH
		_reset_seek()
		return
	if not job.under_construction:
		# An upgrade (10f) only ever runs on a fully healthy building, so it never
		# competes with the repair below — repair keeps its priority by definition.
		if job.upgrading:
			_choose_upgrade_task()
			return
		# A healthy workshop is production duty; a damaged one falls through
		# to the repair pipeline (and back once fixed).
		if job is Workshop and job.health >= job.max_health:
			_choose_workshop_task()
			return
		_choose_repair_task()
		return
	if job.needs_flatten() and job.has_unclaimed_flatten_cell():
		if _claim_flatten():
			return
	if job.wants_more_wood():
		if _try_fetch_wood():
			return
	if job.needs_flatten():
		if _claim_flatten():
			return
	# Wood is missing but no source was found above AND the progress cap is
	# reached: the site stalls (re-checked after WOOD_RECHECK_INTERVAL) and
	# this worker quits instead of hammering forever.
	if job.wants_more_wood() and job.build_progress >= job.progress_cap() - 0.0001:
		job.mark_wood_stalled()
		_stop_all()
		return
	if job.foundation_done:
		task = Task.CONSTRUCT
		_reset_seek()
		return
	# Nothing to do right now: wait and re-check via the retry timer.


## Workshop duty OUTSIDE the building (7f; housed workers do not tick — the
## workshop contributes their worker-seconds itself): fetch stock wood while
## the entrance piles are short and production is idle, otherwise walk back
## in. Finding no reachable wood stalls the workshop's fetching for a while.
func _choose_workshop_task() -> void:
	var ws: Workshop = job as Workshop
	if not ws.production_active and ws.wants_more_stock_wood():
		if _try_fetch_wood():
			return
		ws.mark_wood_stalled()   # nothing reachable: re-checked on an interval
	task = Task.PRODUCE   # walk to the entrance and be housed again
	_reset_seek()


## Walks to the workshop entrance and is housed inside (the forester's JOIN
## walk, on the job system).
func _tick_produce(delta: float) -> void:
	if not (job is Workshop):
		_end_subtask()
		return
	var ws: Workshop = job as Workshop
	if _seek(ws.entrance_world(), FORESTER_RANGE, delta, true):
		ws.admit_worker(self)


## Repair job: fetch wood while the damage still owes some (delivered piles are
## absorbed into the building's repair buffer), hammer otherwise. No source at
## all -> the site stalls like a construction site out of wood.
func _choose_repair_task() -> void:
	if job.wants_more_repair_wood() and _try_fetch_wood():
		return
	if job.repair_wood > 0 or job.repair_wood_missing() == 0:
		task = Task.REPAIR
		_reset_seek()
		return
	# Repair wood is owed but none is banked yet. If usable wood already lies in
	# reach (a workshop banks its protected entrance stock into the repair buffer
	# only WHILE a worker is attached, and that absorb is throttled), stay on the
	# job and re-check — quitting here would detach the worker and stop the
	# absorption, deadlocking a lightly damaged workshop that still holds stock.
	# wood_incoming() and the absorb source share delivery_point()/ABSORB_RADIUS,
	# so counted wood is always bankable (no endless wait).
	if job.wood_incoming() > 0:
		_end_subtask(TASK_RETRY)
		return
	job.mark_wood_stalled()
	_stop_all()


## Upgrade job (10f): structurally the repair job — fetch wood while the upgrade
## still owes some, build otherwise. Unlike a repair this cannot deadlock on a
## protected stock, but the wood_incoming() wait is kept for the same reason:
## wood already lying at the entrance is about to be absorbed.
func _choose_upgrade_task() -> void:
	if job.wants_upgrade_wood() and _try_fetch_wood():
		return
	if job.upgrade_wood > 0 or job.upgrade_wood_missing() == 0:
		task = Task.UPGRADE
		_reset_seek()
		return
	if job.wood_incoming() > 0:
		_end_subtask(TASK_RETRY)
		return
	job.mark_wood_stalled()
	_stop_all()


## Chooses a wood source. A lying wood pile is used FIRST, but ONLY when it is
## close to the site AND enemy-free (see _best_safe_pile). If the nearby piles
## are threatened by enemies, a tree in a safer spot is chopped instead
## (_claim_safe_tree prefers an enemy-free tree, falling back to any). Returns
## true when a fetch sub-task was set.
func _try_fetch_wood() -> bool:
	if wood_pile_manager != null:
		var pile: WoodPile = _best_safe_pile()
		if pile != null:
			task_pile = pile
			task = Task.PICKUP
			_reset_seek()
			return true
	if tree_manager != null:
		var tree: TreeResource = _claim_safe_tree()
		if tree != null:
			task_tree = tree
			_chop_timer = tree.chop_time()
			task = Task.CHOP
			_reset_seek()
			return true
	return false


## Nearest wood pile (to the worker) that is close to the site, not already in
## the site's absorb radius (those get swallowed anyway) and has no enemy within
## WOOD_ENEMY_RADIUS. Null when no such safe, close pile exists.
func _best_safe_pile() -> WoodPile:
	if wood_pile_manager == null or job == null or not is_instance_valid(job):
		return null
	var site: Vector2 = Vector2(job.center_world().x, job.center_world().z)
	var entrance: Vector2 = Vector2(job.entrance_world().x, job.entrance_world().z)
	var worker: Vector2 = Vector2(position.x, position.z)
	var best: WoodPile = null
	var best_d: float = INF
	for pile in wood_pile_manager.piles:
		if not is_instance_valid(pile) or pile.amount <= 0:
			continue
		var pf: Vector2 = Vector2(pile.position.x, pile.position.z)
		if pf.distance_to(entrance) <= Building.ABSORB_RADIUS:
			continue   # the site absorbs these on its own
		if pf.distance_to(site) > PILE_PREFER_RADIUS:
			continue   # too far to be worth fetching over chopping
		if _enemies_near(pile.position, WOOD_ENEMY_RADIUS):
			continue   # guarded by enemies -> chop a tree instead
		if nav_grid != null and not nav_grid.same_island(position, pile.position):
			continue   # beeline-near but unreachable (below a cliff)
		var d: float = pf.distance_squared_to(worker)
		if d < best_d:
			best_d = d
			best = pile
	return best


## Claims the nearest chopable tree near the site, preferring one with no enemy
## within WOOD_ENEMY_RADIUS; if every reachable tree is contested, falls back to
## the nearest one anyway (better than stalling). Null when none is chopable.
func _claim_safe_tree() -> TreeResource:
	var tree: TreeResource = _nearest_claimable_tree(true)
	if tree == null:
		tree = _nearest_claimable_tree(false)
	if tree != null:
		tree.add_claimer(self)
	return tree


func _nearest_claimable_tree(require_safe: bool) -> TreeResource:
	if tree_manager == null or job == null or not is_instance_valid(job):
		return null
	# Central path-verified pick (bug backlog #4): ranked around the site,
	# walk distance checked from THIS worker — no more cliff detours.
	var filter: Callable = Callable()
	if require_safe:
		filter = func(tree: TreeResource) -> bool:
			return not _enemies_near(tree.position, WOOD_ENEMY_RADIUS)
	return tree_manager.best_tree(
		job.center_world(), position, JOB_TREE_RADIUS, true, filter)


## True when a living enemy of another tribe stands within `radius` of `pos`.
func _enemies_near(pos: Vector3, radius: float) -> bool:
	if path_service == null:
		return false
	for u in path_service.get_units_in_radius(pos, radius):
		if u.tribe_id != tribe_id and u.state != Unit.State.DEAD:
			return true
	return false


func _claim_flatten() -> bool:
	var c: Vector2i = job.claim_flatten_cell(position)
	if c.x < 0:
		return false
	task_cell = c
	task = Task.FLATTEN
	_reset_seek()
	return true


func _tick_flatten(delta: float) -> void:
	if not job.flatten_cell_pending(task_cell):
		_end_subtask()
		return
	if not _seek(_cell_world(task_cell), WORK_RANGE, delta, true):
		return
	_set_working(true)
	hop_visual = true
	if job.work_flatten(task_cell, FLATTEN_RATE * delta):
		job.release_flatten_cell(task_cell)
		_end_subtask()


## Harvests the claimed tree one wood at a time; keeps chopping the same tree
## until the carry capacity is full, the tree is gone or the site has enough
## incoming wood, then delivers.
func _tick_job_chop(delta: float) -> void:
	if not _tree_valid(task_tree):
		task_tree = null
		_end_subtask(TASK_RETRY)
		return
	if not _seek(task_tree.position, CHOP_RANGE, delta):
		return
	_set_working(true)
	_face_toward(task_tree.position)
	_chop_timer -= delta
	if _chop_timer <= 0.0:
		carried_wood += tree_manager.harvest_tree(task_tree)
		if carried_wood >= CARRY_CAPACITY or not _tree_valid(task_tree) \
				or not _job_wants_wood():
			if tree_manager != null and _tree_valid(task_tree):
				tree_manager.release_claim(task_tree, self)
			task_tree = null
			task = Task.DELIVER
			_set_working(false)
			_reset_seek()
		else:
			_chop_timer = task_tree.chop_time()


func _tick_pickup(delta: float) -> void:
	if _haul_source != null:
		_tick_haul_pickup(delta)
		return
	if task_pile == null or not is_instance_valid(task_pile) or task_pile.amount <= 0:
		task_pile = null
		_end_subtask(TASK_RETRY)
		return
	if not _seek(task_pile.position, PICKUP_RANGE, delta):
		return
	var pile_pos: Vector3 = task_pile.position
	carried_wood += wood_pile_manager.take_from_pile(task_pile, CARRY_CAPACITY - carried_wood)
	task_pile = null
	# Manual pickup of a pile that already lies at a friendly building: relay
	# the wood to the nearest wood depot instead (skipping depots that already
	# "own" this spot), if one exists — otherwise deliver as before.
	# The `_supply_target == null` guard is mandatory: without it a supply job turns
	# SILENTLY into a depot->depot relay as soon as its source pile lies at a
	# friendly building — and a rack's own stock pile always does. This is the
	# nastiest interaction of the whole change.
	if state == State.GATHER and job == null and carried_wood > 0 \
			and _supply_target == null and not carry_hold \
			and _pile_near_friendly_building(pile_pos):
		var depot: WoodDepot = _nearest_depot(pile_pos, null, pile_pos)
		if depot != null:
			_haul_target = depot
			_start_loose_deliver()
			return
	# Standing area order (10g): fill the load from the next source in the area
	# before hauling, exactly like the tree path does.
	if _fills_full_load() and carried_wood < CARRY_CAPACITY and _next_area_source():
		return
	if carry_hold and carried_wood > 0:
		# Aufnehmen und HALTEN (10h): kein Task.DELIVER. Der naechste Rechtsklick
		# entscheidet, wohin — bis dahin laeuft der Ablege-Countdown.
		task = Task.NONE
		_carry_hold_timer = 0.0
		_reset_seek()
		return
	task = Task.DELIVER if carried_wood > 0 else Task.NONE
	_reset_seek()


## Depot->depot haul: fetch a load from the source depot's rack, then deliver
## it via the loose-deliver path (fixed `_haul_target`).
func _tick_haul_pickup(delta: float) -> void:
	if not _haul_valid() or not is_instance_valid(_haul_source) \
			or _haul_source.stored_wood() <= 0:
		_stop_all()
		return
	if not _seek(_haul_source.delivery_point(), DELIVER_RANGE, delta, true):
		return
	carried_wood += _haul_source.take_stored(CARRY_CAPACITY - carried_wood)
	if carried_wood <= 0:
		_stop_all()
		return
	_start_loose_deliver()


func _haul_valid() -> bool:
	return _haul_source != null and is_instance_valid(_haul_source) \
		and _haul_source.is_usable() and _haul_target != null \
		and is_instance_valid(_haul_target) and _haul_target.is_usable() \
		and _haul_target.storage_left() > 0


func _tick_deliver(delta: float) -> void:
	if carried_wood <= 0:
		_end_subtask()
		return
	# Deliver to a reachable spot at the site (entrance, or the nearest walkable
	# perimeter cell if the doorway is walled off) — not the raw entrance, which
	# may be unreachable (water/slope) and leave the worker stuck with the wood.
	var target: Vector3 = job.delivery_point()
	if not _seek(target, DELIVER_RANGE, delta, true):
		return
	if wood_pile_manager != null:
		wood_pile_manager.deposit(position, carried_wood)
		carried_wood = 0
	_end_subtask()


func _tick_construct(delta: float) -> void:
	if not job.foundation_done:
		_end_subtask()
		return
	if not _seek(job.center_world(), job.interact_range(), delta):
		return
	_set_working(true)
	_face_toward(job.center_world())
	job.add_build_progress(BUILD_RATE * delta)
	# Periodically re-check whether wood ran short (then go chop instead of
	# hammering against the progress cap).
	_retry_timer -= delta
	if _retry_timer <= 0.0:
		_retry_timer = 2.0
		if job.wants_more_wood():
			_end_subtask()


## Tears the job building down (phase 10d): the mirror image of _tick_construct.
## build_progress runs backwards at the build rate; Building.work_demolish pays
## the refund out in portions and removes the building at zero. No wood re-check
## — a demolition never needs any.
func _tick_demolish(delta: float) -> void:
	if not job.demolishing:
		_end_subtask()
		return
	if not _seek(job.center_world(), job.interact_range(), delta):
		return
	_set_working(true)
	_face_toward(job.center_world())
	job.work_demolish(BUILD_RATE * Balance.DEMOLISH_RATE_FACTOR * delta)


## Hammers repair HP into the (damaged, finished) job building. Building.repair
## returns false when it runs dry of delivered wood — then re-choose (fetch
## more or stall). Full repair releases the worker via the _job_active guard.
func _tick_repair(delta: float) -> void:
	if job.under_construction or job.health <= 0 or job.health >= job.max_health:
		_end_subtask()
		return
	if not _seek(job.center_world(), job.interact_range(), delta):
		return
	_set_working(true)
	_face_toward(job.center_world())
	if not job.repair(REPAIR_RATE * delta):
		_end_subtask()


## Builds the next stage of the (finished, healthy) job building (phase 10f).
## Building.work_upgrade returns false when it runs dry of delivered wood — then
## re-choose (fetch more or stall). A finished upgrade clears `upgrading`, which
## releases the worker via the _job_active guard.
func _tick_upgrade(delta: float) -> void:
	if not job.upgrading:
		_end_subtask()
		return
	if not _seek(job.center_world(), job.interact_range(), delta):
		return
	_set_working(true)
	_face_toward(job.center_world())
	if not job.work_upgrade(BUILD_RATE * Balance.HUT_UPGRADE_RATE_FACTOR * delta):
		_end_subtask()


## Wood demand of the current job (construction vs. upgrade vs. repair vs.
## workshop stock). Without the upgrade branch a chopper would stop after its
## FIRST log, because a healthy building owes no repair wood.
func _job_wants_wood() -> bool:
	if job == null or not is_instance_valid(job):
		return false
	if job.under_construction:
		return job.wants_more_wood()
	if job.upgrading:
		return job.wants_upgrade_wood()
	if job is Workshop and job.health >= job.max_health:
		return (job as Workshop).wants_more_stock_wood()
	return job.wants_more_repair_wood()


## The job building just went into demolition (phase 10d): abandon whatever
## sub-task is running and re-choose. Without this a worker mid-flatten/chop/
## build/repair would never notice — _choose_job_task is only reached through the
## Task.NONE branch of _tick_job. Releases the claims _end_subtask does NOT
## release (flatten cell, claimed tree), same as _on_seek_failed.
func switch_to_demolish() -> void:
	if job != null and is_instance_valid(job):
		if task_cell.x >= 0:
			job.release_flatten_cell(task_cell)
	if tree_manager != null and _tree_valid(task_tree):
		tree_manager.release_claim(task_tree, self)
	task_tree = null
	task_pile = null
	_end_subtask()   # Task.NONE -> the next tick picks DEMOLISH


## Ends the current sub-task and re-chooses after `retry` seconds. Success
## paths pass 0.0 (immediate re-choose keeps workers responsive); FAILURE
## paths (unreachable goal, vanished tree/pile) pass TASK_RETRY — otherwise a
## stuck worker re-runs the expensive tree/pile search every sim tick (30 Hz)
## instead of at the nominal task cadence (phase 8 early-game lag).
func _end_subtask(retry: float = 0.0) -> void:
	task = Task.NONE
	task_cell = Vector2i(-1, -1)
	hop_visual = false
	_set_working(false)
	_reset_seek()
	_retry_timer = retry
	if retry <= 0.0:
		_seek_fail_streak = 0   # a successful sub-task ends the failure streak


# --- Loose chopping (manual order, no job) ----------------------------------------
## Chop ONE piece of wood, carry it to the nearest own building (preferring an
## existing pile there), then return to the chopping spot and take the next
## piece — one at a time, not a full load.
## An AREA order (has_chop_area, phase 10e) instead fills CARRY_CAPACITY before
## delivering; every deviating branch below is guarded by has_chop_area(), so
## the single-tree path stays exactly as it was.

func _tick_loose_chop(delta: float) -> void:
	if not _tree_valid(task_tree):
		task_tree = null
		if _area_retry > 0.0:
			# Holding an area order: wait out the retry delay without searching.
			_area_retry -= delta
			_set_working(false)
			return
		# No tree left: lying wood inside the area is the second source (10g).
		if not _next_loose_tree() and not _next_area_pile():
			if carried_wood > 0:
				_start_loose_deliver()
			elif not _area_retry_hold():
				_stop_all()
			return
		if task == Task.PICKUP:
			return   # switched to a pile: the PICKUP branch takes over next tick
	if not _seek(task_tree.position, CHOP_RANGE, delta):
		return
	_set_working(true)
	_face_toward(task_tree.position)
	_chop_timer -= delta
	if _chop_timer <= 0.0:
		var got: int = tree_manager.harvest_tree(task_tree) if tree_manager != null else 0
		carried_wood += got
		_loose_return_pos = position
		# Area order: keep filling the load, and prefer staying on the SAME tree
		# (harvest_tree only ever takes one piece and the claim is already ours,
		# so the next piece costs zero walking).
		if _fills_full_load() and carried_wood < CARRY_CAPACITY \
				and _tree_valid(task_tree) and task_tree.wood_yield() > 0:
			_chop_timer = task_tree.chop_time()
			return
		# One piece per trip: release the tree and carry this single wood back
		# to the drop-off, then come back for the next piece.
		if tree_manager != null and _tree_valid(task_tree):
			tree_manager.release_claim(task_tree, self)
		task_tree = null
		_set_working(false)
		# Load not full yet and the tree is spent: chain to the next area source
		# (tree, else lying wood) instead of walking a half-empty load home.
		if _fills_full_load() and carried_wood < CARRY_CAPACITY and _next_area_source():
			return
		if carried_wood > 0:
			_start_loose_deliver()
		elif not _next_loose_tree():
			_stop_all()


func _start_loose_deliver() -> void:
	task = Task.DELIVER
	_loose_deliver_goal = Vector3.INF
	_loose_deliver_recheck = 0.0
	_loose_deliver_building = null
	_set_working(false)
	_reset_seek()


func _tick_loose_deliver(delta: float) -> void:
	if carried_wood <= 0:
		task = Task.CHOP
		if not _next_loose_tree() and not _area_retry_hold():
			_stop_all()
		return
	# The drop target is picked ONCE per delivery and only re-evaluated on a
	# slow cadence with hysteresis. Recomputing building+pile every tick
	# flip-flopped between near-equidistant targets: the brave replanned each
	# tick and spun on the spot without moving (user bug report).
	_loose_deliver_recheck -= delta
	if _loose_deliver_goal == Vector3.INF or _loose_deliver_recheck <= 0.0:
		_loose_deliver_recheck = 1.5
		if _haul_target != null and is_instance_valid(_haul_target) \
				and _haul_target.is_usable() and _haul_target.storage_left() > 0:
			# Fixed depot target (pile relay / depot haul): no nearest-building
			# re-pick — the wood goes into exactly this rack.
			_loose_deliver_goal = _haul_target.delivery_point()
			_loose_deliver_building = _haul_target
		else:
			if _haul_target != null:
				# Target depot vanished/filled up: drop the fixed target (and
				# any haul loop) and deliver like normal loose wood.
				_haul_target = null
				_haul_source = null
				_loose_deliver_goal = Vector3.INF
			# 10h Teil 3: NEED before proximity. Picking the nearest target left huge
			# piles at workshops while huts waited to upgrade (user report). The
			# consumer with the biggest OPEN demand in reach wins now.
			var building: Building = _neediest_target_in_reach()
			if building == null and has_chop_area():
				# Nothing needs wood: an area crew still prefers a rack within
				# DEPOT_PREFER_RADIUS over a merely nearer hut, so the load ends up in
				# storage and the crew keeps hauling to ONE spot instead of scattering
				# piles across the village.
				var depot: WoodDepot = _nearest_depot(position)
				if depot != null and _flat_dist(position, depot.delivery_point()) \
						<= DEPOT_PREFER_RADIUS:
					building = depot
			if building == null:
				building = _nearest_own_building()
			if building == null:
				# No building anywhere: drop the wood on the spot (old behaviour).
				if wood_pile_manager != null:
					wood_pile_manager.deposit(position, carried_wood)
					carried_wood = 0
				task = Task.CHOP
				if not _next_loose_tree() and not _area_retry_hold():
					_stop_all()
				return
			var goal: Vector3 = _loose_drop_target(building)
			# Switch only when the fresh target is clearly (2 m) closer.
			if _loose_deliver_goal == Vector3.INF \
					or _flat_dist(position, goal) + 2.0 < _flat_dist(position, _loose_deliver_goal):
				_loose_deliver_goal = goal
				_loose_deliver_building = building
	if not _seek(_loose_deliver_goal, DELIVER_RANGE, delta, true):
		return
	if wood_pile_manager != null:
		# Deliver INTO a wood depot's rack first; leftovers (rack full) and
		# non-depot targets drop as a normal ground pile.
		if _loose_deliver_building is WoodDepot \
				and is_instance_valid(_loose_deliver_building):
			carried_wood -= (_loose_deliver_building as WoodDepot).store_wood(carried_wood)
		if carried_wood > 0:
			wood_pile_manager.deposit(position, carried_wood)
		carried_wood = 0
	_loose_deliver_goal = Vector3.INF
	_loose_deliver_building = null
	if has_supply_job():
		# Standing supply job (10g): next trip, or done once the target is funded.
		_haul_source = null
		if not _choose_supply_task():
			_stop_all()
		return
	if _haul_source != null:
		# Depot->depot pendulum: keep hauling until the source runs dry or the
		# target fills up, then rest at the target.
		if _haul_valid() and _haul_source.stored_wood() > 0:
			task = Task.PICKUP
			_reset_seek()
		else:
			_stop_all()
		return
	_haul_target = null
	task = Task.CHOP
	# _area_retry_hold keeps a standing area order alive when every remaining
	# claim slot is held by a crewmate that is still walking home.
	if not _next_loose_tree() and not _area_retry_hold():
		_stop_all()


## Preferred drop-off near a building: an existing pile with space close to the
## entrance (so wood consolidates onto it), otherwise the entrance itself.
func _loose_drop_target(building: Building) -> Vector3:
	# Reachable drop spot (entrance or nearest walkable perimeter cell), so wood
	# is not stranded at the trees when the doorway itself cannot be reached.
	var drop: Vector3 = building.delivery_point()
	if wood_pile_manager != null:
		var pile: WoodPile = wood_pile_manager.pile_with_space_near(
			drop, DROP_CONSOLIDATE_RADIUS)
		if pile != null:
			return pile.position
	return drop


func _nearest_own_building() -> Building:
	if tribe == null:
		return null
	var best: Building = null
	var best_dist: float = INF
	var flat: Vector2 = Vector2(position.x, position.z)
	for building in tribe.buildings:
		if not is_instance_valid(building):
			continue
		var d: float = Vector2(building.position.x, building.position.z).distance_squared_to(flat)
		if d >= best_dist:
			continue
		if nav_grid != null and not nav_grid.same_island(position, building.delivery_point()):
			continue   # beeline-near but unreachable (below a cliff)
		best_dist = d
		best = building
	return best


## Nearest own, usable wood depot with free storage. `exclude` skips a specific
## depot (haul source); with `exclude_near` set, depots whose footprint lies
## within ABSORB_RADIUS of that spot are skipped too (relaying a pile to a
## depot that already "owns" it would be a no-op walk).
func _nearest_depot(from: Vector3, exclude: WoodDepot = null,
		exclude_near: Vector3 = Vector3.INF) -> WoodDepot:
	if tribe == null:
		return null
	var best: WoodDepot = null
	var best_dist: float = INF
	var flat: Vector2 = Vector2(from.x, from.z)
	for building in tribe.buildings:
		if building == exclude or not is_instance_valid(building):
			continue
		if not (building is WoodDepot) or not building.is_usable():
			continue
		var depot: WoodDepot = building as WoodDepot
		if depot.storage_left() <= 0:
			continue
		if exclude_near != Vector3.INF and depot.footprint_distance_to(
				Vector2(exclude_near.x, exclude_near.z)) <= Building.ABSORB_RADIUS:
			continue
		var d: float = Vector2(depot.position.x, depot.position.z).distance_squared_to(flat)
		if d >= best_dist:
			continue
		if nav_grid != null and not nav_grid.same_island(position, depot.delivery_point()):
			continue
		best_dist = d
		best = depot
	return best


## Whether `pos` lies at a friendly building (within ABSORB_RADIUS of any own
## building's footprint) — such wood is already "delivered".
func _pile_near_friendly_building(pos: Vector3) -> bool:
	if tribe == null:
		return false
	var flat: Vector2 = Vector2(pos.x, pos.z)
	for building in tribe.buildings:
		if not is_instance_valid(building):
			continue
		if building.footprint_distance_to(flat) <= Building.ABSORB_RADIUS:
			return true
	return false


## Next tree near the current chopping spot (after a delivery the brave
## returns to where it was working). A standing area order overrides the
## chain radius and searches its rectangle instead.
func _next_loose_tree() -> bool:
	if has_chop_area():
		return _next_area_tree()
	if tree_manager == null:
		return false
	var search_from: Vector3 = _loose_return_pos if _loose_return_pos != Vector3.INF else position
	var tree: TreeResource = tree_manager.claim_nearest_tree(
		search_from, CHOP_CHAIN_RADIUS, self, position)
	if tree == null:
		return false
	task_tree = tree
	task = Task.CHOP
	_chop_timer = tree.chop_time()
	_reset_seek()
	return true


# --- Training ----------------------------------------------------------------------------

## Walks to the queue slot the building assigned; flags train_reached_slot while
## standing in it (recomputed each tick, so it drops when the slot shifts as the
## queue advances). The building admits the front brave on its own tick.
func _tick_train(delta: float) -> void:
	if not is_instance_valid(train_target) or not train_target.is_usable():
		cancel_training()
		return
	var slot: Vector3 = train_slot_pos
	if slot == Vector3.INF:
		slot = train_target.entrance_world()   # until the building assigns one
	train_reached_slot = _seek(slot, TRAIN_SLOT_RANGE, delta)
	if train_reached_slot:
		_face_toward(train_target.center_world())


# --- Forester work (phase 7d) ------------------------------------------------------

## Walks in to be housed, out to a plant spot (kneel, plant a sapling) and back
## in — one dispatched worker at a time (the forester drives the dispatching).
func _tick_forester(delta: float) -> void:
	if forester_home == null or not is_instance_valid(forester_home) \
			or not forester_home.is_usable():
		leave_forester()
		return
	match _forester_phase:
		ForesterPhase.JOIN:
			if _seek(forester_home.entrance_world(), FORESTER_RANGE, delta, true):
				forester_home.admit_worker(self)
		ForesterPhase.PLANT_GO:
			if _plant_target == Vector3.INF:
				_forester_phase = ForesterPhase.RETURN
				_reset_seek()
				return
			if _seek(_plant_target, PLANT_RANGE, delta, true):
				_face_toward(_plant_target)
				_set_working(true)
				_kneel_timer = PLANT_KNEEL_TIME
				_forester_phase = ForesterPhase.KNEEL
		ForesterPhase.KNEEL:
			_face_toward(_plant_target)
			_kneel_timer -= delta
			if _kneel_timer <= 0.0:
				_set_working(false)
				forester_home.on_worker_planted(self)
				_plant_target = Vector3.INF
				_forester_phase = ForesterPhase.RETURN
				_reset_seek()
		ForesterPhase.RETURN:
			if _seek(forester_home.entrance_world(), FORESTER_RANGE, delta, true):
				forester_home.reabsorb_worker(self)


# --- Task bookkeeping --------------------------------------------------------------------

## Releases all claims, drops carried wood as a pile and leaves the job.
## Called before any new order and on death.
func _interrupt_tasks() -> void:
	if task_cell.x >= 0 and job != null and is_instance_valid(job):
		job.release_flatten_cell(task_cell)
	if tree_manager != null and _tree_valid(task_tree):
		tree_manager.release_claim(task_tree, self)
	if job != null and is_instance_valid(job):
		job.leave(self)
	if train_target != null and is_instance_valid(train_target):
		train_target.remove_trainee(self)
	if forester_home != null and is_instance_valid(forester_home):
		forester_home.release_worker(self)
	if job != null and is_instance_valid(job) and job is Workshop:
		(job as Workshop).release_worker(self)
	workshop_inside = false
	job = null
	task = Task.NONE
	task_cell = Vector2i(-1, -1)
	task_tree = null
	task_pile = null
	target_building = null
	# One-order principle for the standing area harvest (10e): clearing it here
	# means EVERY other order (move, build, train, pray, ...) cancels it, and the
	# AI's crew bookkeeping sees the brave leave the crew for free.
	chop_area = Rect2()
	chop_area_poly = PackedVector2Array()
	_area_retry = 0.0
	_area_retries = 0
	route_end_action = Callable()   # a fresh task cancels a queued follow-up order
	train_target = null
	train_slot_pos = Vector3.INF
	train_reached_slot = false
	forester_home = null
	forester_inside = false
	_plant_target = Vector3.INF
	hop_visual = false
	_loose_return_pos = Vector3.INF
	_loose_deliver_building = null
	_haul_source = null
	_haul_target = null
	# Any other order cancels the supply job — the one-order principle, for free.
	_supply_target = null
	carry_hold = false
	_carry_hold_timer = 0.0
	_carry_drop_goal = Vector3.INF
	_carry_drop_into = null
	_set_working(false)
	if carried_wood > 0 and wood_pile_manager != null:
		wood_pile_manager.deposit(position, carried_wood)
		carried_wood = 0
	# Starting a worker task cancels any pending MOVE intent: a brave recruited
	# mid-walk (or one that just finished a job and drops to IDLE through here)
	# must not keep a stale destination — it left a phantom route marker on the
	# finished worker even though nobody walks there (bug, purely visual).
	waypoint_queue.clear()
	_reset_seek()


func _stop_all() -> void:
	_interrupt_tasks()
	_clear_path()
	_set_state(State.IDLE)


# --- Helpers ---------------------------------------------------------------------

## Fully untyped parameter on purpose: the referenced tree may already be
## freed, and passing a freed instance to ANY typed parameter (even `Object`)
## raises a script error.
func _tree_valid(tree) -> bool:
	return tree != null and is_instance_valid(tree) and not tree.felled_flag


func _cell_world(c: Vector2i) -> Vector3:
	var wx: float = (float(c.x) + 0.5) * TerrainData.CELL_SIZE
	var wz: float = (float(c.y) + 0.5) * TerrainData.CELL_SIZE
	var wy: float = terrain_data.get_height(wx, wz) if terrain_data != null else 0.0
	return Vector3(wx, wy, wz)


func _reset_seek() -> void:
	_seek_goal = Vector3.INF
	_clear_path()


## Walks toward target_pos until within arrive_range (XZ). Returns true once
## in range. Footprint cells are nav-solid, so when the nav path ends close to
## the goal (or allow_direct is set) the last stretch is walked directly.
func _seek(target_pos: Vector3, arrive_range: float, delta: float,
		allow_direct: bool = false) -> bool:
	var flat: Vector2 = Vector2(position.x, position.z)
	var flat_target: Vector2 = Vector2(target_pos.x, target_pos.z)
	var dist: float = flat.distance_to(flat_target)
	if dist <= arrive_range:
		if _has_path():
			_clear_path()
		return true
	if _working:
		_set_working(false)
		hop_visual = false
	if not _has_path() or _seek_goal.distance_to(target_pos) > 0.5:
		_seek_goal = target_pos
		if not _plan_path_to(target_pos):
			_on_seek_failed()
			return false
	if _advance_path(delta):
		# Path exhausted but still out of range: walk straight if close enough
		# (target sits on nav-solid footprint cells), otherwise give up.
		dist = Vector2(position.x, position.z).distance_to(flat_target)
		if dist <= arrive_range:
			return true
		if allow_direct or dist <= DIRECT_WALK_RANGE:
			_path = PackedVector3Array([target_pos])
			_path_index = 0
		else:
			_on_seek_failed()
	return false


## Unreachable goal: give up the current sub-task (job workers pick a new
## task, everything else stops). Consecutive failures escalate the retry
## delay (each failing A* explores the whole reachable component — multi-ms
## on big maps) and finally make the worker quit the job entirely; the
## periodic worker recruiting re-drafts it if the site frees up again.
func _on_seek_failed() -> void:
	if state == State.BUILD and job != null and is_instance_valid(job):
		if task_cell.x >= 0:
			job.release_flatten_cell(task_cell)
		if tree_manager != null and _tree_valid(task_tree):
			tree_manager.release_claim(task_tree, self)
		task_tree = null
		task_pile = null
		_seek_fail_streak += 1
		if _seek_fail_streak >= SEEK_FAIL_QUIT_STREAK:
			_seek_fail_streak = 0
			_stop_all()
			return
		_end_subtask(minf(TASK_RETRY * pow(2.0, float(_seek_fail_streak - 1)),
			TASK_RETRY_MAX))
	else:
		_stop_all()


func _set_working(working: bool) -> void:
	if _working == working:
		return
	_working = working
	_update_animation()
	_update_chop_loop()


## Continuous wood-chop sound: a positional loop that follows the brave while it
## actively hacks a tree (any chop sub-task). Uses its OWN key `wood_chop_loop`
## (falls back to repeating wood_chop.ogg until a dedicated loop asset exists),
## kept separate from the per-harvest one-shot `wood_chop` played on each felled
## piece — so the ongoing work and the actual hit can sound different.
func _update_chop_loop() -> void:
	var chopping: bool = _working and task == Task.CHOP
	if chopping == _chop_loop_on:
		return
	_chop_loop_on = chopping
	if not _audio_checked:
		_audio_checked = true
		if is_inside_tree():
			_audio_node = get_node_or_null("/root/AudioManager")
	if _audio_node == null:
		return
	if chopping:
		_audio_node.start_loop(&"wood_chop_loop", self)
	else:
		_audio_node.stop_loop(&"wood_chop_loop", self)


func _face_toward(target_pos: Vector3) -> void:
	var dir: Vector3 = Vector3(target_pos.x - position.x, 0.0, target_pos.z - position.z)
	if dir.length_squared() > 0.000001:
		facing = dir.normalized()


## Sub-state animations: chopping/building use the attack frames, flattening
## uses the hop-driven jump frames (arms up in the air, down on landing),
## walking phases use walk.
func _anim_base() -> StringName:
	match state:
		State.BUILD:
			if _working and task == Task.FLATTEN:
				return &"jump"
			if _working:
				return &"attack"
			return _carry_or(&"walk" if _has_path() else &"idle")
		State.GATHER:
			if _working:
				return &"attack"
			return _carry_or(&"walk" if _has_path() else &"idle")
		State.FORESTER:
			if _forester_phase == ForesterPhase.KNEEL:
				return &"attack"   # kneel/plant placeholder (crouch action)
			return &"walk" if _has_path() else &"idle"
		_:
			return super._anim_base()


## Swaps a walk/idle base for its wood-carrying variant when the brave is
## carrying wood (a distinct sprite; can stand or walk while carrying).
func _carry_or(base: StringName) -> StringName:
	if carried_wood <= 0:
		return base
	return &"carry_walk" if base == &"walk" else &"carry"


## Whether this brave fills its whole CARRY_CAPACITY before hauling. True for the
## standing area order (10e) and for a supply job (10g): one wood per 40-m trip is
## worthless. The single-tree right-click keeps its one-piece-per-trip behaviour.
func _fills_full_load() -> bool:
	return has_chop_area() or has_supply_job()


## Carry-and-hold tick (10h): the brave holds its load until a drop order arrives.
##
## With a destination it walks there and puts the wood down — on an own building's
## delivery point that means the building absorbs it, exactly like a worker delivery.
## Without one, BRAVE_CARRY_HOLD_TIMEOUT seconds later it drops the load where it
## stands, so a forgotten carrier never walks around with wood forever.
func _tick_carry_hold(delta: float) -> void:
	if carried_wood <= 0:
		carry_hold = false
		_stop_all()
		return
	if _carry_drop_goal != Vector3.INF:
		if not _seek(_carry_drop_goal, DELIVER_RANGE, delta, true):
			return
		_drop_held_wood()
		return
	_carry_hold_timer += delta
	if _carry_hold_timer >= Balance.BRAVE_CARRY_HOLD_TIMEOUT:
		_drop_held_wood()


## Puts the held load down at the current position and ends the hold.
func _drop_held_wood() -> void:
	# Into a rack first (that is what "tidy the wood away" means now), leftovers and
	# non-depot targets as a normal ground pile — which an own building absorbs.
	if _carry_drop_into is WoodDepot and is_instance_valid(_carry_drop_into) 			and (_carry_drop_into as WoodDepot).is_usable():
		carried_wood -= (_carry_drop_into as WoodDepot).store_wood(carried_wood)
	if wood_pile_manager != null and carried_wood > 0:
		wood_pile_manager.deposit(position, carried_wood)
	carried_wood = 0
	_carry_drop_into = null
	carry_hold = false
	_carry_hold_timer = 0.0
	_carry_drop_goal = Vector3.INF
	_carry_drop_into = null
	_stop_all()


## Own building within DEPOT_PREFER_RADIUS with the biggest OPEN wood demand, or
## null when nothing in reach needs any (10h Teil 3).
##
## Before this the carrier took the NEAREST target, which is why huge piles sat at
## workshops while huts waited to upgrade (user report). Ties go to the nearer one, so
## a village of equally hungry huts still gets short walks.
##
## Cost: one pass over tribe.buildings per DELIVERY TRIP (a trip is many seconds) —
## the same loop _nearest_own_building already does — plus one cheap pile query per
## workshop candidate. Deliberately NOT Workshop.stock_wood(), which is
## O(piles x buildings) because of its peer-reservation check.
func _neediest_target_in_reach() -> Building:
	if tribe == null:
		return null
	var best: Building = null
	var best_need: int = 0
	var best_dist: float = INF
	for building in tribe.buildings:
		if not is_instance_valid(building) or building.health <= 0:
			continue
		var drop: Vector3 = building.delivery_point()
		var d: float = _flat_dist(position, drop)
		if d > DEPOT_PREFER_RADIUS:
			continue
		var need: int = _delivery_demand(building)
		if need <= 0:
			continue
		if need < best_need or (need == best_need and d >= best_dist):
			continue
		if nav_grid != null and not nav_grid.same_island(position, drop):
			continue
		best = building
		best_need = need
		best_dist = d
	return best


## Wood `building` still openly needs. 0 = it wants nothing right now, so the carrier
## looks elsewhere — a workshop with a full product's worth of stock is NOT a
## consumer, which is exactly the "piles rot at the workshop" case.
func _delivery_demand(building: Building) -> int:
	if building.demolishing:
		return 0
	if building.under_construction:
		return maxi(0, building.wood_needed_total() - building.wood_incoming())
	if building.upgrading:
		return maxi(0, building.upgrade_wood_missing())
	if building.health < building.max_health:
		return maxi(0, building.repair_wood_missing())
	if building is Workshop:
		if wood_pile_manager == null:
			return 0
		var have: int = wood_pile_manager.wood_in_radius(
			building.delivery_point(), Building.ABSORB_RADIUS)
		return maxi(0, (building as Workshop).product_wood() - have)
	if building is WoodDepot:
		# A rack is a BUFFER, not a consumer: it competes only up to one upgrade's
		# worth, so a hut that actually wants to grow always outranks it.
		return mini((building as WoodDepot).storage_left(), Balance.AI_HUT_RACK_STOCK)
	return 0
