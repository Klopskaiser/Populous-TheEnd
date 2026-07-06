class_name Forester extends Building

## Försterei (phase 7d): a building with four worker slots. Braves ordered here
## walk in and are housed (removed from the world, still counted as population).
## While staffed it plants SAPLINGS (TreeResource stage 0) on free walkable cells
## in an 11x11 area (Chebyshev radius PLANT_RADIUS) around itself — sustainable
## wood without expansion. Each staffed slot costs MANA_PER_WORKER mana/second;
## when the tribe cannot pay, slots idle (from the back). The more ACTIVE
## workers, the faster it plants: 4 workers plant one sapling every 15 s
## (PLANT_WORK_PER_TREE worker-seconds per tree), fewer workers proportionally
## slower. To plant, one housed worker steps out, walks to the spot, kneels,
## plants and walks back in (Brave.State.FORESTER). Planting pauses at
## AREA_TREE_CAP trees in the area or when no free cell is left.

const WOOD_COST: int = 20
const FOOTPRINT: Vector2i = Vector2i(3, 3)
const MAX_HEALTH: int = 250
## Worker slots.
const WORKER_SLOTS: int = 4
## Half-size of the square planting area in cells (radius 5 -> 11x11 field).
const PLANT_RADIUS: int = 5
## Minimum cell gap between planted saplings (denser than the wild MIN_SPACING).
const PLANT_SPACING: int = 1
## No more planting once this many trees stand in the area.
const AREA_TREE_CAP: int = 30
## Mana per second drained per ACTIVE worker.
const MANA_PER_WORKER: float = 2.0
## Worker-seconds of work per sapling: 4 active workers -> one per 15 s.
const PLANT_WORK_PER_TREE: float = 60.0

const C_WALL: Color = Color(0.42, 0.3, 0.16)
const C_ROOF: Color = Color(0.2, 0.45, 0.2)
const C_LEAF: Color = Color(0.16, 0.42, 0.18)

## Braves holding a worker slot (housed inside, walking in/out, or planting).
var occupants: Array[Brave] = []
## The worker currently out planting (also still an occupant); null = none out.
var _planting_worker: Brave = null
## Cell the dispatched worker is planting on.
var _plant_cell: Vector2i = Vector2i(-1, -1)
var _plant_progress: float = 0.0
## Active worker count from the last tick (mana-limited); drives the bar.
var _active_workers: int = 0


func _init() -> void:
	wood_cost = WOOD_COST
	footprint = FOOTPRINT
	max_health = MAX_HEALTH
	health = MAX_HEALTH


func display_name() -> String:
	return "Försterei"


## Foresters do not add housing capacity (occupants stay counted as population
## via their tribe membership regardless).
func housing_capacity() -> int:
	return 0


# --- Worker slots -------------------------------------------------------------

func has_free_slot() -> bool:
	_prune_occupants()
	return is_usable() and occupants.size() < WORKER_SLOTS


## Reserves a slot for a brave heading here (called from Brave.order_forester).
func reserve_slot(brave: Brave) -> bool:
	_prune_occupants()
	if not is_usable() or occupants.size() >= WORKER_SLOTS:
		return false
	if not (brave in occupants):
		occupants.append(brave)
	return true


## The brave reached the entrance: house it (remove from the world, still
## population). If the forester turned unusable meanwhile, release the slot.
func admit_worker(brave: Brave) -> void:
	if not (brave in occupants):
		return
	if not is_usable():
		occupants.erase(brave)
		brave.leave_forester()
		return
	if unit_manager != null:
		unit_manager.remove_from_world(brave)
	brave.forester_inside = true
	brave.enter_forester()


## The dispatched worker finished kneeling: plant the sapling (re-checking the
## cell is still free).
func on_worker_planted(brave: Brave) -> void:
	if brave != _planting_worker:
		return
	var tm: TreeManager = _tree_manager()
	if tm != null and _plant_cell.x >= 0 and tm.can_plant_at(_plant_cell, PLANT_SPACING):
		tm.spawn_tree(_plant_cell, 0)   # sapling (stage 0)
	_plant_cell = Vector2i(-1, -1)


## The worker returned to the entrance: house it again.
func reabsorb_worker(brave: Brave) -> void:
	if brave != _planting_worker:
		return
	if unit_manager != null:
		unit_manager.remove_from_world(brave)
	brave.forester_inside = true
	brave.enter_forester()
	_planting_worker = null


## Frees a slot when the brave leaves on its own (new order / death). Called
## from Brave._interrupt_tasks while it still points here.
func release_worker(brave: Brave) -> void:
	occupants.erase(brave)
	if brave == _planting_worker:
		_planting_worker = null
		_plant_cell = Vector2i(-1, -1)


## UI eject: sends the slot-`index` worker back into the world and frees it.
func eject_worker(index: int) -> void:
	_prune_occupants()
	if index < 0 or index >= occupants.size():
		return
	var brave: Brave = occupants[index]
	occupants.remove_at(index)
	if brave == _planting_worker:
		_planting_worker = null
		_plant_cell = Vector2i(-1, -1)
	elif brave.forester_inside:
		_return_to_world(brave)
	if is_instance_valid(brave):
		brave.leave_forester()


func _prune_occupants() -> void:
	var kept: Array[Brave] = []
	for b in occupants:
		if is_instance_valid(b) and b.state != Unit.State.DEAD and b.forester_home == self:
			kept.append(b)
		elif b == _planting_worker:
			_planting_worker = null
	occupants = kept


## Re-registers a housed brave at a walkable edge cell (eject / destruction).
func _return_to_world(brave: Brave) -> void:
	if unit_manager == null:
		return
	unit_manager.register(brave)
	var pos: Vector3 = edge_spawn_position()
	brave.position = pos
	brave.forester_inside = false


# --- Tick ---------------------------------------------------------------------

func _tick_active(delta: float) -> void:
	_prune_occupants()
	var filled: int = occupants.size()
	if filled == 0:
		_active_workers = 0
		return
	# Mana upkeep: staff as many workers as the tribe can pay for this tick.
	var active: int = filled
	if tribe == null:
		active = 0
	elif delta > 0.0:
		var full_cost: float = MANA_PER_WORKER * float(filled) * delta
		if tribe.mana < full_cost:
			active = clampi(int(tribe.mana / (MANA_PER_WORKER * delta)), 0, filled)
		tribe.consume_mana(MANA_PER_WORKER * float(active) * delta)
	_active_workers = active
	if active <= 0:
		return
	# Planting progress in worker-seconds; capped so it does not run away while
	# a worker is out (the next plant fires as soon as it returns).
	_plant_progress = minf(_plant_progress + float(active) * delta, PLANT_WORK_PER_TREE)
	if _plant_progress >= PLANT_WORK_PER_TREE and _planting_worker == null:
		if _dispatch_plant():
			_plant_progress = 0.0


## Sends one housed worker out to plant on a free cell in the area. Returns false
## when the area is full, no free cell exists or no housed worker is available.
func _dispatch_plant() -> bool:
	var tm: TreeManager = _tree_manager()
	if tm == null or nav_grid == null or unit_manager == null:
		return false
	var center: Vector2i = cell + footprint / 2
	if tm.trees_in_area(center, PLANT_RADIUS) >= AREA_TREE_CAP:
		return false
	var target_cell: Vector2i = _find_plant_cell(tm, center)
	if target_cell.x < 0:
		return false
	var worker: Brave = _first_housed_worker()
	if worker == null:
		return false
	_return_to_world(worker)
	_planting_worker = worker
	_plant_cell = target_cell
	worker.begin_plant(nav_grid.cell_to_world(target_cell))
	return true


## Ring-searches the 11x11 area for the nearest free plantable cell (denser
## packing than the wild spacing), skipping cells occupied by wood piles.
func _find_plant_cell(tm: TreeManager, center: Vector2i) -> Vector2i:
	for radius in range(1, PLANT_RADIUS + 1):
		for c in _ring(center, radius):
			if not tm.can_plant_at(c, PLANT_SPACING):
				continue
			if _pile_on_cell(c):
				continue
			return c
	# Center cell last (it may be free too, though the building sits nearby).
	if tm.can_plant_at(center, PLANT_SPACING) and not _pile_on_cell(center):
		return center
	return Vector2i(-1, -1)


## Cells on the square ring at Chebyshev distance `radius` around `center`.
static func _ring(center: Vector2i, radius: int) -> Array[Vector2i]:
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


func _pile_on_cell(c: Vector2i) -> bool:
	if wood_pile_manager == null or nav_grid == null:
		return false
	return wood_pile_manager.wood_in_radius(nav_grid.cell_to_world(c), 0.6) > 0


func _first_housed_worker() -> Brave:
	for b in occupants:
		if is_instance_valid(b) and b.forester_inside and b != _planting_worker:
			return b
	return null


func _tree_manager() -> TreeManager:
	return unit_manager.tree_manager if unit_manager != null else null


## Planting progress bar (only while actually staffed and paying).
func production_progress() -> float:
	if not is_usable() or occupants.is_empty() or _active_workers <= 0:
		return -1.0
	return clampf(_plant_progress / PLANT_WORK_PER_TREE, 0.0, 1.0)


# --- Disable / destruction ----------------------------------------------------

## Damaged into stage >= 1: release the workers (like the training buildings).
func _on_disabled() -> void:
	_release_all_occupants()


func destroy() -> void:
	_release_all_occupants()
	super.destroy()


func _release_all_occupants() -> void:
	for b in occupants.duplicate():
		if not is_instance_valid(b):
			continue
		if b.forester_inside and b != _planting_worker:
			_return_to_world(b)
		b.leave_forester()
	occupants.clear()
	_planting_worker = null
	_plant_progress = 0.0
	_active_workers = 0


# --- Visuals (placeholder) ----------------------------------------------------

## A little forester's lodge: a log cabin with a green pitched roof and a couple
## of saplings out front. Authored with the entrance facing south (+z).
func _create_visuals() -> void:
	super._create_visuals()
	var span: float = float(footprint.x)

	var walls: MeshInstance3D = MeshInstance3D.new()
	var body: BoxMesh = BoxMesh.new()
	body.size = Vector3(span * 0.7, 1.6, span * 0.7)
	walls.mesh = body
	walls.material_override = _make_material(C_WALL)
	walls.position.y = 0.8
	_mesh_root.add_child(walls)

	var roof: MeshInstance3D = MeshInstance3D.new()
	var prism: PrismMesh = PrismMesh.new()
	prism.size = Vector3(span * 0.85, 0.9, span * 0.85)
	roof.mesh = prism
	roof.material_override = _make_material(C_ROOF)
	roof.position.y = 2.05
	_mesh_root.add_child(roof)

	# Door on the south side.
	var door: MeshInstance3D = MeshInstance3D.new()
	var door_box: BoxMesh = BoxMesh.new()
	door_box.size = Vector3(0.6, 1.0, 0.1)
	door.mesh = door_box
	door.material_override = _make_material(Color(0.12, 0.08, 0.04))
	door.position = Vector3(0.0, 0.5, span * 0.35)
	_mesh_root.add_child(door)

	# A couple of saplings out front (decorative sticks with a leaf tuft).
	for sx in [-1.0, 1.0]:
		var stem: MeshInstance3D = MeshInstance3D.new()
		var scyl: CylinderMesh = CylinderMesh.new()
		scyl.top_radius = 0.05
		scyl.bottom_radius = 0.07
		scyl.height = 0.7
		stem.mesh = scyl
		stem.material_override = _make_material(Color(0.4, 0.27, 0.15))
		stem.position = Vector3(sx, 0.35, span * 0.5)
		_mesh_root.add_child(stem)
		var leaf: MeshInstance3D = MeshInstance3D.new()
		var cone: CylinderMesh = CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.28
		cone.height = 0.5
		leaf.mesh = cone
		leaf.material_override = _make_material(C_LEAF)
		leaf.position = Vector3(sx, 0.85, span * 0.5)
		_mesh_root.add_child(leaf)

	_add_flag()
