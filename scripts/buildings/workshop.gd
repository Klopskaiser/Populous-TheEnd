class_name Workshop extends Building

## Werkstatt (phase 7f): continuously manufactures siege engines (catapults).
##
## Worker model = the FORESTER's (user feedback), without mana upkeep: up to
## WORKER_SLOTS braves hold a slot (Brave.order_workshop -> reserve_slot),
## walk in and are HOUSED inside (removed from the world, still population).
## They work INSIDE the building; they only step out to fetch stock wood
## (dispatched via the construction-wood pipeline: chop/pickup/deliver to the
## entrance) and walk back in. The sidebar panel ejects them per slot —
## nobody joins without an explicit order (construction workers are released
## when the building finishes; they never become production workers).
##
## Production of ONE catapult: needs >= 1 housed worker; every housed worker
## contributes worker-seconds (WORK_PER_CATAPULT per catapult: 3 workers
## ~30 s, 1 worker ~90 s). Starting consumes CATAPULT_WOOD from the piles at
## the entrance (the wood visibly vanishes — no refund, ever). Production
## only starts while: not paused, the exit is clear (no finished catapult
## waiting at the entrance) and the tribe owns fewer than `max_catapults`
## MANNED engines. Aborts (building disabled/destroyed, all slots emptied)
## lose the progress AND the consumed wood.
##
## While NOT producing, the workers keep the entrance stock topped up to
## STOCK_TARGET; with no reachable wood the fetch stalls for
## WOOD_RECHECK_INTERVAL (base Building wood_stalled mechanism).
##
## The finished catapult appears at the entrance; up to AUTO_CREW braves
## idling nearby board it automatically (one shot — nobody near means it
## stays, blocking the next production until manned and moved off).

const WOOD_COST: int = 15
## Twice the hut's area (hut 4x4): authored 8 wide x 4 deep, entrance south.
## BuildingManager swaps the footprint for east/west orientations.
const FOOTPRINT: Vector2i = Vector2i(8, 4)
const MAX_HEALTH: int = 350
## Worker slots (housed inside; production needs >= 1).
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
const C_WOOD_ARM: Color = Color(0.5, 0.36, 0.2)

## Player-facing controls (sidebar panel).
var paused: bool = false
var max_catapults: int = DEFAULT_MAX_CATAPULTS

## Braves holding a worker slot (housed inside, walking in/out or fetching).
var occupants: Array[Brave] = []
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


# --- Worker slots (forester pattern, no mana upkeep) --------------------------------

func has_free_slot() -> bool:
	_prune_occupants()
	return is_usable() and occupants.size() < WORKER_SLOTS


## Reserves a slot for a brave heading here (called from Brave.order_workshop).
func reserve_slot(brave: Brave) -> bool:
	_prune_occupants()
	if not is_usable() or occupants.size() >= WORKER_SLOTS:
		return false
	if not (brave in occupants):
		occupants.append(brave)
	return true


## The brave reached the entrance: house it (removed from the world, still
## population). If the workshop turned unusable meanwhile, release the slot.
func admit_worker(brave: Brave) -> void:
	if not (brave in occupants):
		return
	if not is_usable():
		occupants.erase(brave)
		brave.leave_workshop()
		return
	if unit_manager != null:
		unit_manager.remove_from_world(brave)
	brave.workshop_inside = true
	brave.enter_workshop()


## Frees a slot when the brave leaves on its own (new order / death). Called
## from Brave._interrupt_tasks while its job still points here.
func release_worker(brave: Brave) -> void:
	occupants.erase(brave)


## UI eject: sends the slot-`index` worker back into the world and frees it.
func eject_worker(index: int) -> void:
	_prune_occupants()
	if index < 0 or index >= occupants.size():
		return
	var brave: Brave = occupants[index]
	occupants.remove_at(index)
	if brave.workshop_inside:
		_return_to_world(brave)
	if is_instance_valid(brave):
		brave.leave_workshop()


func _prune_occupants() -> void:
	var kept: Array[Brave] = []
	for b in occupants:
		if is_instance_valid(b) and b.state != Unit.State.DEAD and b.job == self:
			kept.append(b)
	occupants = kept


## Housed workers currently inside (the ones contributing worker-seconds).
func inside_count() -> int:
	var count: int = 0
	for b in occupants:
		if is_instance_valid(b) and b.workshop_inside:
			count += 1
	return count


## Re-registers a housed brave at a walkable edge cell (dispatch / eject /
## destruction).
func _return_to_world(brave: Brave) -> void:
	if unit_manager == null:
		return
	unit_manager.register(brave)
	brave.position = edge_spawn_position()
	brave.workshop_inside = false


## Sends a housed worker out to fetch stock wood (it re-enters on its own
## once the stock is full or nothing is reachable).
func _dispatch_fetch(brave: Brave) -> void:
	_return_to_world(brave)
	brave.begin_workshop_fetch()


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
	for b in occupants:
		if is_instance_valid(b):
			incoming += b.carried_wood + b.claimed_tree_yield()
	return stock_wood() + incoming < STOCK_TARGET


# --- Production ----------------------------------------------------------------------

## Whether a new catapult could START right now (housed workers are checked
## separately in the tick).
func can_start_production() -> bool:
	return is_usable() and not paused and not exit_blocked() \
		and manned_catapult_count() < max_catapults \
		and stock_wood() >= CATAPULT_WOOD


func _tick_active(delta: float) -> void:
	_prune_occupants()
	# Wood-stall re-check (mirrors the construction sites).
	if wood_stalled:
		_wood_recheck_timer -= delta
		if _wood_recheck_timer <= 0.0:
			wood_stalled = false
	# Abort rule: a running production with EVERY slot emptied loses the
	# progress and the already-consumed wood (spec: no refunds on aborts).
	if production_active and occupants.is_empty():
		production_active = false
		work_done = 0.0
	var inside: int = inside_count()
	if production_active:
		# Housed workers hammer worker-seconds into the current catapult.
		if inside > 0:
			work_done += float(inside) * delta
			if work_done >= WORK_PER_CATAPULT:
				_finish_catapult()
		return
	# Not producing: top the entrance stock up first (spec: fetch all the
	# wood BEFORE starting to work), then start the next catapult.
	if wants_more_stock_wood() and not wood_stalled:
		for b in occupants:
			if is_instance_valid(b) and b.workshop_inside:
				_dispatch_fetch(b)
		return
	if inside >= 1 and can_start_production():
		if wood_pile_manager == null:
			return
		var taken: int = wood_pile_manager.take_from_radius(
			delivery_point(), ABSORB_RADIUS, CATAPULT_WOOD)
		if taken < CATAPULT_WOOD:
			# Race lost (someone absorbed the piles): put the rest back.
			if taken > 0:
				wood_pile_manager.deposit(delivery_point(), taken)
			return
		production_active = true
		work_done = 0.0


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


func production_progress() -> float:
	if not is_usable() or not production_active:
		return -1.0
	return clampf(work_done / WORK_PER_CATAPULT, 0.0, 1.0)


# --- Disable / destruction -----------------------------------------------------------

## Damaged into stage >= 1: the running production is lost (no refund) and
## the workers are released (like the forester); re-staffing is manual.
func _on_disabled() -> void:
	production_active = false
	work_done = 0.0
	_release_all_occupants()


func destroy() -> void:
	production_active = false
	work_done = 0.0
	_release_all_occupants()
	super.destroy()


func _release_all_occupants() -> void:
	for b in occupants.duplicate():
		if not is_instance_valid(b):
			continue
		if b.workshop_inside:
			_return_to_world(b)
		b.leave_workshop()
	occupants.clear()


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
