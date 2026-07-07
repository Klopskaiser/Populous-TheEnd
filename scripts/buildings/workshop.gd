class_name Workshop extends Building

## Werkstatt (phase 7f): continuously manufactures siege engines (catapults).
##
## Unlike the training buildings its workers are NOT consumed — up to
## WORKER_SLOTS braves join the finished workshop as a standing crew (the
## construction-job system, Brave.order_workshop -> State.BUILD with
## Task.PRODUCE). They behave like construction workers:
## - While the wood stock in piles at the entrance is below STOCK_TARGET and
##   they are not mid-production, they fetch wood (CHOP/PICKUP/DELIVER).
## - Otherwise they hammer at the building; each worker contributes
##   worker-seconds (add_production_work). One catapult takes
##   WORK_PER_CATAPULT worker-seconds: 3 workers ~30 s, 1 worker ~90 s.
##
## Production of ONE catapult: starting consumes CATAPULT_WOOD from the piles
## at the entrance (the wood visibly vanishes — no refund, ever). Production
## only starts while: not paused, the exit is clear (no finished catapult
## waiting at the entrance) and the tribe owns fewer than `max_catapults`
## MANNED engines. Aborts (building disabled/destroyed, all workers gone)
## lose the progress AND the consumed wood.
##
## The finished catapult appears at the entrance; up to AUTO_CREW braves
## idling nearby board it automatically (one shot — nobody near means it
## stays, blocking the next production until manned and moved off).

const WOOD_COST: int = 15
## Twice the hut's area (hut 4x4): authored 8 wide x 4 deep, entrance south.
## BuildingManager swaps the footprint for east/west orientations.
const FOOTPRINT: Vector2i = Vector2i(8, 4)
const MAX_HEALTH: int = 350
## Standing worker crew (max 3; production needs >= 1).
const WORKER_SLOTS: int = 3
## Worker-seconds per catapult: 3 workers -> 30 s build time.
const WORK_PER_CATAPULT: float = 90.0
## Wood consumed per catapult (taken from the entrance piles at start).
const CATAPULT_WOOD: int = 5
## Stock the workers keep piled at the entrance while not producing.
const STOCK_TARGET: int = 15
## A finished engine within this range of the entrance blocks the exit.
const EXIT_CLEAR_RADIUS: float = 3.0
## Auto-manning: this many IDLE braves within AUTO_CREW_RADIUS board the
## fresh catapult (one shot at spawn; nobody near -> it stays unmanned).
const AUTO_CREW: int = 2
const AUTO_CREW_RADIUS: float = 12.0
## Default cap of MANNED catapults before production auto-stops (UI-adjustable).
const DEFAULT_MAX_CATAPULTS: int = 3
const MAX_CATAPULTS_LIMIT: int = 20

const SIEGE_SCENE: PackedScene = preload("res://scenes/units/siege_engine.tscn")

const C_WALL: Color = Color(0.45, 0.33, 0.2)
const C_ROOF: Color = Color(0.32, 0.22, 0.12)
const C_METAL: Color = Color(0.5, 0.5, 0.53)

## Player-facing controls (sidebar panel).
var paused: bool = false
var max_catapults: int = DEFAULT_MAX_CATAPULTS

## True while a catapult is being built (its 5 wood are already consumed).
var production_active: bool = false
## Worker-seconds contributed to the current catapult.
var work_done: float = 0.0
## The finished engine still standing at the entrance (untyped: may be freed).
var pending_engine = null


func _init() -> void:
	wood_cost = WOOD_COST
	footprint = FOOTPRINT
	max_health = MAX_HEALTH
	health = MAX_HEALTH


func display_name() -> String:
	return "Werkstatt"


func housing_capacity() -> int:
	return 0


## Standing crew is capped at WORKER_SLOTS (construction of the workshop
## itself still uses the base MAX_WORKERS cap — this only gates the finished
## building's production crew).
func join(worker: Brave) -> bool:
	if under_construction:
		return super.join(worker)
	if worker in workers:
		return true
	if workers.size() >= WORKER_SLOTS:
		return false
	workers.append(worker)
	return true


# --- Stock (piles at the entrance) --------------------------------------------------

## Wood lying in piles near the entrance — the visible stock. Nothing is
## absorbed into a buffer; the piles stay on the ground until production
## consumes them.
func stock_wood() -> int:
	if wood_pile_manager == null:
		return 0
	return wood_pile_manager.wood_in_radius(delivery_point(), ABSORB_RADIUS)


## True while the workers should fetch more stock wood (counting what they
## already carry / have claimed on trees).
func wants_more_stock_wood() -> bool:
	if not is_usable():
		return false
	var incoming: int = 0
	for worker in workers:
		if is_instance_valid(worker):
			incoming += worker.carried_wood + worker.claimed_tree_yield()
	return stock_wood() + incoming < STOCK_TARGET


# --- Production ----------------------------------------------------------------------

## Whether a new catapult could START right now (gates the workers' PRODUCE
## task and the actual start below).
func can_start_production() -> bool:
	return is_usable() and not paused and not exit_blocked() \
		and manned_catapult_count() < max_catapults \
		and stock_wood() >= CATAPULT_WOOD


## One worker's production contribution (worker-seconds). Returns false when
## no work can be done right now — the worker then re-chooses (fetch stock
## wood or wait). Starting a catapult consumes its wood from the entrance
## piles on the spot (visibly — and never refunded).
func add_production_work(delta: float) -> bool:
	if not is_usable() or paused:
		return false
	if not production_active:
		if not can_start_production():
			return false
		if wood_pile_manager == null:
			return false
		var taken: int = wood_pile_manager.take_from_radius(
			delivery_point(), ABSORB_RADIUS, CATAPULT_WOOD)
		if taken < CATAPULT_WOOD:
			# Race lost (someone absorbed the piles): put the rest back.
			if taken > 0:
				wood_pile_manager.deposit(delivery_point(), taken)
			return false
		production_active = true
		work_done = 0.0
	work_done += delta
	if work_done >= WORK_PER_CATAPULT:
		_finish_catapult()
	return true


## Rolls the finished catapult out of the entrance and auto-mans it with up
## to AUTO_CREW idle braves nearby (one shot — see class doc).
func _finish_catapult() -> void:
	production_active = false
	work_done = 0.0
	if unit_manager == null:
		return
	var engine: Unit = unit_manager.spawn_unit(
		SIEGE_SCENE, tribe_id, edge_spawn_position())
	if engine == null:
		return
	pending_engine = engine
	var crewed: int = 0
	for u in unit_manager.get_units_in_radius(entrance_world(), AUTO_CREW_RADIUS):
		if crewed >= AUTO_CREW:
			break
		if u.tribe_id != tribe_id or u.state != Unit.State.IDLE:
			continue
		if not (u is Brave):
			continue
		u.order_crew(engine)
		if u.siege_engine == engine:
			crewed += 1


## True while a finished catapult still stands at the entrance — no further
## production until it is manned and moved off.
func exit_blocked() -> bool:
	var e = pending_engine
	if e == null or not is_instance_valid(e) or e.state == Unit.State.DEAD:
		pending_engine = null
		return false
	if Vector2(e.position.x - entrance_world().x,
			e.position.z - entrance_world().z).length() > EXIT_CLEAR_RADIUS:
		pending_engine = null
		return false
	return true


## MANNED catapults the tribe currently owns (>= 1 boarded crew) — basis of
## the max_catapults auto-stop.
func manned_catapult_count() -> int:
	if tribe == null:
		return 0
	var count: int = 0
	for u in tribe.units:
		if is_instance_valid(u) and u is SiegeEngine and u.state != Unit.State.DEAD:
			if (u as SiegeEngine).boarded_count() >= 1:
				count += 1
	return count


func _tick_active(_delta: float) -> void:
	_prune_workers()
	# Abort rule: production with NOBODY left on the job loses the progress
	# and the already-consumed wood (spec: no refunds on aborts).
	if production_active and workers.is_empty():
		production_active = false
		work_done = 0.0


## Drops workers that died or were ordered elsewhere (their job link is gone).
func _prune_workers() -> void:
	var kept: Array[Brave] = []
	for w in workers:
		if is_instance_valid(w) and w.state != Unit.State.DEAD and w.job == self:
			kept.append(w)
	workers = kept


func production_progress() -> float:
	if not is_usable() or not production_active:
		return -1.0
	return clampf(work_done / WORK_PER_CATAPULT, 0.0, 1.0)


## Damaged into stage >= 1: the running production is lost (no refund); the
## workers switch to repair duty on their own (the job system keeps them
## bound while the building is damaged).
func _on_disabled() -> void:
	production_active = false
	work_done = 0.0


func destroy() -> void:
	production_active = false
	work_done = 0.0
	super.destroy()


# --- Visuals (placeholder) -----------------------------------------------------------

## A long workshop hall: timber walls, a flat gabled roof across the long
## axis, a wide gate on the south side and a catapult arm sticking out of an
## open bay (so the building reads as "siege workshop"). Authored with the
## entrance facing south (+z), 8 wide x 4 deep.
func _create_visuals() -> void:
	super._create_visuals()
	var w: float = float(FOOTPRINT.x)
	var d: float = float(FOOTPRINT.y)

	var walls: MeshInstance3D = MeshInstance3D.new()
	var body: BoxMesh = BoxMesh.new()
	body.size = Vector3(w * 0.85, 1.8, d * 0.8)
	walls.mesh = body
	walls.material_override = _make_material(C_WALL)
	walls.position.y = 0.9
	_mesh_root.add_child(walls)

	var roof: MeshInstance3D = MeshInstance3D.new()
	var prism: PrismMesh = PrismMesh.new()
	prism.size = Vector3(w * 0.95, 1.0, d * 0.9)
	roof.mesh = prism
	roof.material_override = _make_material(C_ROOF)
	roof.position.y = 2.3
	_mesh_root.add_child(roof)

	# Wide gate on the south side.
	var gate: MeshInstance3D = MeshInstance3D.new()
	var gate_box: BoxMesh = BoxMesh.new()
	gate_box.size = Vector3(1.6, 1.3, 0.15)
	gate.mesh = gate_box
	gate.material_override = _make_material(Color(0.12, 0.08, 0.04))
	gate.position = Vector3(0.0, 0.65, d * 0.4)
	_mesh_root.add_child(gate)

	# A half-built catapult arm poking out of an open bay (workshop signature).
	var arm: MeshInstance3D = MeshInstance3D.new()
	var arm_box: BoxMesh = BoxMesh.new()
	arm_box.size = Vector3(0.16, 0.12, 2.2)
	arm.mesh = arm_box
	arm.material_override = _make_material(C_WOOD_ARM)
	arm.position = Vector3(-w * 0.28, 2.1, 0.0)
	arm.rotation.x = -0.5
	_mesh_root.add_child(arm)
	var wheel: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.4
	cyl.bottom_radius = 0.4
	cyl.height = 0.15
	wheel.mesh = cyl
	wheel.material_override = _make_material(C_METAL)
	wheel.rotation.z = PI * 0.5
	wheel.position = Vector3(w * 0.3, 0.4, d * 0.35)
	_mesh_root.add_child(wheel)

	_add_flag()


const C_WOOD_ARM: Color = Color(0.5, 0.36, 0.2)
