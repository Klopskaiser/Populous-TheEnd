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
## - PRAY (State.PRAY): walk to the reincarnation site; while nearby,
##   is_praying() is true and the tribe's mana tick gets the prayer bonus.
##
## All logic runs in tick(delta) and works without the scene tree. References
## to trees/piles are kept untyped because they may be freed by other workers.

enum Task {NONE, FLATTEN, CHOP, PICKUP, DELIVER, CONSTRUCT, REPAIR, PRODUCE}
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

## Injected by UnitManager.spawn_unit() (or directly by tests).
var tree_manager: TreeManager = null
var wood_pile_manager: WoodPileManager = null

var job: Building = null
var task: Task = Task.NONE
var carried_wood: int = 0
var task_cell: Vector2i = Vector2i(-1, -1)
var task_tree: Object = null   # untyped: may be freed by another worker
var task_pile: Object = null   # untyped: may be freed
var target_building: Building = null   # pray site
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
## Consecutive unreachable-goal failures (escalating backoff, see
## _on_seek_failed); reset by any successfully completed sub-task.
var _seek_fail_streak: int = 0
var _working: bool = false
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
	if state == State.GATHER or state == State.BUILD or state == State.PRAY \
			or state == State.TRAIN or state == State.FORESTER:
		_interrupt_tasks()


## Harmless downhill stumble (phase 8.2): the carrier drops its wood on the
## spot but KEEPS its task — resuming the fetch, the normal task selection
## finds the dropped pile right at its feet and picks it back up.
func _on_stumble() -> void:
	if carried_wood > 0 and wood_pile_manager != null:
		wood_pile_manager.deposit(position, carried_wood)
		carried_wood = 0


func is_praying() -> bool:
	return state == State.PRAY and _working


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
	if state == State.GATHER or state == State.BUILD or state == State.PRAY:
		_interrupt_tasks()
	super.order_move(target, queue_up, aggressive)


## Braves keep a small guard radius even while idling (phase 7b): enemies
## walking right into the village get attacked; farther ones are ignored.
## Applied to Unit.idle_aggro in _init (a field, not a virtual — hot path).
const IDLE_AGGRO_RADIUS: float = Balance.BRAVE_IDLE_AGGRO_RADIUS


## Manual pickup order (right-click on a wood pile): fetch the pile, then
## deliver like loose-chopped wood (nearest own building's drop spot).
func order_pickup(pile: WoodPile) -> void:
	if not can_take_orders():
		return
	if pile == null or not is_instance_valid(pile) or pile.amount <= 0:
		return
	_interrupt_tasks()
	task_pile = pile
	task = Task.PICKUP
	_loose_return_pos = Vector3.INF
	_set_state(State.GATHER)


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
## count, even when the tree's harvest slots are full.
func order_chop(tree: TreeResource) -> void:
	if not can_take_orders():
		return
	if tree == null or not is_instance_valid(tree) or tree.felled_flag:
		return
	_interrupt_tasks()
	task_tree = tree
	tree.add_claimer(self)
	_chop_timer = tree.chop_time()
	task = Task.CHOP
	_loose_return_pos = Vector3.INF
	_set_state(State.GATHER)


## Join a construction site as a worker (fails silently when the site already
## has MAX_WORKERS helpers).
func order_build(building: Building) -> void:
	if not can_take_orders():
		return
	if building == null or not is_instance_valid(building) or not building.under_construction:
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


func order_pray(site: Building) -> void:
	if not can_take_orders():
		return
	_interrupt_tasks()
	target_building = site
	_set_state(State.PRAY)


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
			if task == Task.DELIVER:
				_tick_loose_deliver(delta)
			elif task == Task.PICKUP:
				_tick_pickup(delta)
			else:
				_tick_loose_chop(delta)
		State.BUILD:
			_tick_job(delta)
		State.PRAY:
			_tick_pray(delta)
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


## A job binds its workers while the building is under construction or (for
## repair jobs) damaged; a finished/fully repaired building releases them.
## Workshop workers (7f) stay bound only while they HOLD one of the three
## slots — construction workers are released when the workshop finishes and
## never slide into production duty without an explicit order.
func _job_active() -> bool:
	return job.under_construction \
		or (job.health > 0 and job.health < job.max_health) \
		or (job is Workshop and job.is_usable() and self in (job as Workshop).occupants)


## Workers pick their own sensible sub-task: deliver carried wood first; then
## flatten cells nobody works on yet; spare hands fetch wood in parallel
## (nearby tree or distant pile); leftover workers pile onto the remaining
## flatten cells; once the foundation is level, everyone constructs.
func _choose_job_task() -> void:
	if carried_wood > 0:
		task = Task.DELIVER
		_reset_seek()
		return
	if not job.under_construction:
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
	if state == State.GATHER and job == null and carried_wood > 0 \
			and _pile_near_friendly_building(pile_pos):
		var depot: WoodDepot = _nearest_depot(pile_pos, null, pile_pos)
		if depot != null:
			_haul_target = depot
			_start_loose_deliver()
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


## Wood demand of the current job (construction vs. repair vs. workshop stock).
func _job_wants_wood() -> bool:
	if job == null or not is_instance_valid(job):
		return false
	if job.under_construction:
		return job.wants_more_wood()
	if job is Workshop and job.health >= job.max_health:
		return (job as Workshop).wants_more_stock_wood()
	return job.wants_more_repair_wood()


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

func _tick_loose_chop(delta: float) -> void:
	if not _tree_valid(task_tree):
		task_tree = null
		if not _next_loose_tree():
			if carried_wood > 0:
				_start_loose_deliver()
			else:
				_stop_all()
			return
	if not _seek(task_tree.position, CHOP_RANGE, delta):
		return
	_set_working(true)
	_face_toward(task_tree.position)
	_chop_timer -= delta
	if _chop_timer <= 0.0:
		var got: int = tree_manager.harvest_tree(task_tree) if tree_manager != null else 0
		carried_wood += got
		_loose_return_pos = position
		# One piece per trip: release the tree and carry this single wood back
		# to the drop-off, then come back for the next piece.
		if tree_manager != null and _tree_valid(task_tree):
			tree_manager.release_claim(task_tree, self)
		task_tree = null
		_set_working(false)
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
		if not _next_loose_tree():
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
			var building: Building = _nearest_own_building()
			if building == null:
				# No building anywhere: drop the wood on the spot (old behaviour).
				if wood_pile_manager != null:
					wood_pile_manager.deposit(position, carried_wood)
					carried_wood = 0
				task = Task.CHOP
				if not _next_loose_tree():
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
	if not _next_loose_tree():
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
## returns to where it was working).
func _next_loose_tree() -> bool:
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


# --- Praying ---------------------------------------------------------------------------

func _tick_pray(delta: float) -> void:
	if not is_instance_valid(target_building):
		_stop_all()
		return
	if not _seek(target_building.center_world(), ReincarnationSite.PRAY_RADIUS, delta):
		return
	_set_working(true)
	_face_toward(target_building.center_world())
	# Praying itself is passive: Tribe.tick() counts is_praying() braves.


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


func _face_toward(target_pos: Vector3) -> void:
	var dir: Vector3 = Vector3(target_pos.x - position.x, 0.0, target_pos.z - position.z)
	if dir.length_squared() > 0.000001:
		facing = dir.normalized()


## Sub-state animations: chopping/building use the attack frames, flattening
## uses the hop-driven jump frames (arms up in the air, down on landing),
## praying stands (idle), walking phases use walk.
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
		State.PRAY:
			return &"idle" if _working else (&"walk" if _has_path() else &"idle")
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
