class_name TrainingBuilding extends Building

## Base class for the three training buildings (warrior camp, fire temple,
## temple). Braves ordered to train form a single-file queue that runs ALONG the
## building edge, starting just to the LEFT of the entrance (looking at it from
## outside) and continuing around the corners (`incoming`, index 0 = front,
## nearest the door). Only ONE brave trains at a time (`trainee`): when the bay
## is free the front brave, once it stands in its slot, walks in (removed from
## the live world but kept alive and counted). The rest shuffles forward. After
## `training_time` the
## trainee graduates: it is freed and replaced by one `produces` combat unit
## spawned at the edge, which walks to the rally point. Population stays constant
## across the swap (brave out, unit in).
##
## Subclasses set `produces`, `training_time`, cost, footprint and the mesh.

## How far outside the footprint the queue line runs (metres).
const QUEUE_MARGIN: float = 0.9
## Spacing between braves standing in the queue (metres).
const QUEUE_SPACING: float = 1.0
## Offset of the first (front) slot from the entrance, along the edge to the left.
const QUEUE_START_OFFSET: float = 0.9
## Once the line has wrapped all the way around the building it continues in
## the NEXT winding (a snake coiling around the building, phase 7b): each
## winding runs this much farther out. Capped so the search stays bounded.
const QUEUE_WINDING_SPACING: float = 1.0
const QUEUE_MAX_WINDINGS: int = 3

## Combat unit spawned when a brave finishes training.
var produces: PackedScene = null
var training_time: float = 3.0
## Braves lined up to train (index 0 = front of the queue).
var incoming: Array[Brave] = []
## The brave currently inside being trained (null = bay free).
var trainee: Brave = null
var _train_timer: float = 0.0
var _spawn_counter: int = 0


## Training buildings do not house population.
func housing_capacity() -> int:
	return 0


## A trainee inside is a storm occupant (thrown out when the storm begins).
func has_occupants() -> bool:
	return is_instance_valid(trainee)


# --- Enrolment ------------------------------------------------------------------

## Registers a brave at the back of the training queue (called by
## Brave.order_train).
func add_trainee(brave: Brave) -> void:
	if brave == null or brave in incoming or brave == trainee:
		return
	incoming.append(brave)


## Removes a brave from the queue (on death / new order / interruption). If it
## was the one inside, the bay frees up.
func remove_trainee(brave) -> void:
	incoming.erase(brave)
	if brave == trainee:
		trainee = null
		# Safety net: whatever yanked the INSIDE brave out of the training slot
		# (combat interrupt, death) must put it back into the live world at the
		# door — otherwise it stays an invisible, never-ticked orphan (the
		# "vanished trainee" bug). register() is idempotent.
		if is_instance_valid(brave) and unit_manager != null and not brave.in_world:
			brave.position = edge_spawn_position()
			unit_manager.register(brave)
			if brave.state == Unit.State.DEAD and brave.tribe != null:
				# It died while unregistered: died.emit fired with the manager's
				# handler disconnected, so the tribe never dropped it.
				brave.tribe.remove_unit(brave)


# --- Tick -----------------------------------------------------------------------

func _tick_active(delta: float) -> void:
	_prune_queue()
	_assign_slots()
	# Paused (crew tab): the queue keeps forming but nobody new is admitted and
	# a trainee inside keeps waiting (timer frozen) until production resumes.
	if paused:
		return
	_admit_front()
	if trainee != null:
		_train_timer -= delta
		if _train_timer <= 0.0:
			_finish_one()


## Drops braves that are gone or no longer heading here.
func _prune_queue() -> void:
	var still: Array[Brave] = []
	for brave in incoming:
		if is_instance_valid(brave) and brave.state == Unit.State.TRAIN \
				and brave.train_target == self:
			still.append(brave)
	incoming = still
	if trainee != null and not is_instance_valid(trainee):
		trainee = null


## Tells every queued brave where to stand (its slot follows its index, so the
## line shuffles forward automatically as the front is admitted).
func _assign_slots() -> void:
	for i in range(incoming.size()):
		incoming[i].train_slot_pos = queue_slot_world(i)


## When the bay is free and the front brave has reached the head of the line,
## it walks in: removed from the live world (kept alive + counted), trained next.
## Runs during the BuildingManager tick (not the UnitManager unit loop), so
## removing the brave here does not mutate a list mid-iteration.
func _admit_front() -> void:
	if trainee != null or incoming.is_empty() or unit_manager == null:
		return
	var front: Brave = incoming[0]
	if not front.train_reached_slot:
		return
	# A brave that enemies are actively brawling with stays outside: admitting
	# it would leave the attackers' attack_target pointing INTO the building.
	# is_alive() self-prunes, so a finished fight never blocks admission.
	var fight = front.combat_group
	if fight != null and fight.defender == front and fight.is_alive():
		return
	incoming.pop_front()
	trainee = front
	unit_manager.remove_from_world(front)
	front.enter_training()
	_train_timer = training_time


## Graduates the trainee: free it (drop from tribe) and spawn one combat unit at
## the edge, sent to the rally point. Population stays constant.
func _finish_one() -> void:
	var brave: Brave = trainee
	trainee = null
	if is_instance_valid(brave):
		if brave.tribe != null:
			brave.tribe.remove_unit(brave)
		brave.queue_free()
	if produces != null and unit_manager != null:
		var pos: Vector3 = edge_spawn_position()
		var unit: Unit = unit_manager.spawn_unit(produces, tribe_id, pos)
		if unit != null:
			if is_inside_tree():
				var events: Node = get_node_or_null("/root/Events")
				if events != null:
					events.unit_trained.emit(unit.unit_kind(), pos)
			if rally_point != Vector3.ZERO:
				unit.order_move(rally_point + TribeCommands.group_slot_offset(_spawn_counter % 36))
				_spawn_counter += 1


## World position of the index-th queue slot: a single-file line running along
## the building's outer edge, starting just left of the entrance (when facing it
## from outside) and continuing around the corners. Once a winding is full
## (one lap around the building) the line continues on the NEXT winding
## farther out — a snake coiling around the building instead of piling up.
func queue_slot_world(index: int) -> Vector3:
	var cs: float = TerrainData.CELL_SIZE
	var dist: float = QUEUE_START_OFFSET + float(index) * QUEUE_SPACING
	# Walk the distance winding by winding: each lap consumes one perimeter.
	var winding: int = 0
	var margin: float = QUEUE_MARGIN
	while winding < QUEUE_MAX_WINDINGS:
		margin = QUEUE_MARGIN + float(winding) * QUEUE_WINDING_SPACING
		var perimeter: float = 2.0 * ((float(footprint.x) * cs + 2.0 * margin)
			+ (float(footprint.y) * cs + 2.0 * margin))
		if dist < perimeter:
			break
		dist -= perimeter
		winding += 1
	var min_x: float = float(cell.x) * cs - margin
	var max_x: float = float(cell.x + footprint.x) * cs + margin
	var min_z: float = float(cell.y) * cs - margin
	var max_z: float = float(cell.y + footprint.y) * cs + margin
	var cx: float = (min_x + max_x) * 0.5
	var cz: float = (min_z + max_z) * 0.5
	# Outward entrance normal and the "left" tangent (cross(out, up)) that the
	# queue runs along, plus the entrance-edge midpoint to start from.
	var out2: Vector2
	var start: Vector2
	match orientation:
		0:
			out2 = Vector2(0.0, 1.0); start = Vector2(cx, max_z)
		1:
			out2 = Vector2(1.0, 0.0); start = Vector2(max_x, cz)
		2:
			out2 = Vector2(0.0, -1.0); start = Vector2(cx, min_z)
		_:
			out2 = Vector2(-1.0, 0.0); start = Vector2(min_x, cz)
	var left2: Vector2 = Vector2(-out2.y, out2.x)
	var p: Vector2 = _rect_perimeter_point(
		Vector2(min_x, min_z), Vector2(max_x, max_z), start, left2, dist)
	var pos: Vector3 = Vector3(p.x, 0.0, p.y)
	if nav_grid != null:
		var c: Vector2i = nav_grid.world_to_cell(pos)
		if not nav_grid.is_cell_walkable(c):
			var w: Vector2i = nav_grid.nearest_walkable_cell(c)
			if w.x >= 0:
				pos = nav_grid.cell_to_world(w)
	if terrain_data != null:
		pos.y = terrain_data.get_height(pos.x, pos.z)
	return pos


## Marches `dist` metres along the perimeter of the axis-aligned rectangle
## [min..max], starting at `start` (a point on an edge) and moving initially in
## the `dir` tangent, turning corners to follow the rectangle edge.
static func _rect_perimeter_point(minv: Vector2, maxv: Vector2, start: Vector2,
		dir: Vector2, dist: float) -> Vector2:
	var loop: Array[Vector2] = [
		Vector2(minv.x, minv.y), Vector2(maxv.x, minv.y),
		Vector2(maxv.x, maxv.y), Vector2(minv.x, maxv.y)]
	# Nearest edge to the start point.
	var edge_i: int = 0
	var best: float = INF
	for i in range(4):
		var d: float = _dist_point_seg(start, loop[i], loop[(i + 1) % 4])
		if d < best:
			best = d
			edge_i = i
	# Traverse forward (toward loop[edge_i+1]) or backward, whichever matches dir.
	var forward: bool = (loop[(edge_i + 1) % 4] - loop[edge_i]).normalized().dot(dir) >= 0.0
	var pts: Array[Vector2] = [start]
	for k in range(7):
		if forward:
			pts.append(loop[(edge_i + 1 + k) % 4])
		else:
			pts.append(loop[posmod(edge_i - k, 4)])
	var remaining: float = dist
	for i in range(pts.size() - 1):
		var seg: Vector2 = pts[i + 1] - pts[i]
		var seg_len: float = seg.length()
		if seg_len <= 0.0001:
			continue
		if remaining <= seg_len or i == pts.size() - 2:
			return pts[i] + seg.normalized() * clampf(remaining, 0.0, seg_len)
		remaining -= seg_len
	return pts[pts.size() - 1]


static func _dist_point_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var denom: float = ab.length_squared()
	var t: float = 0.0 if denom <= 0.0 else clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Progress toward the next graduating unit (drives the bar above the building);
## -1 while under construction/damaged or when nobody is inside training.
func production_progress() -> float:
	if not is_usable() or trainee == null or paused:
		return -1.0
	return clampf(1.0 - _train_timer / training_time, 0.0, 1.0)


## Damaged into stage >= 1 (or stormed): training stops. The trainee is ejected
## — pushed out alive for spells / the melee storm (`killed` = false), or
## tumbling out with one brave life of damage (a brave trainee dies once the
## roll ends) when RANGED fire / a catapult hit did it (`killed` = true).
## The queued braves are always released.
func eject_occupants(killed: bool) -> void:
	if is_instance_valid(trainee):
		var t: Brave = trainee
		trainee = null
		t.position = edge_spawn_position()
		if unit_manager != null:
			unit_manager.register(t)
		t.cancel_training()
		_eject_unit(t, killed)   # killed → lethal tumble, else shoved out alive
	trainee = null
	for brave in incoming:
		if is_instance_valid(brave):
			brave.cancel_training()
	incoming.clear()


## Destroyed with a trainee inside: never delete it silently — throw it out
## with the lethal tumble (visible death, normal tribe/corpse bookkeeping) and
## release the queued braves.
func destroy() -> void:
	eject_occupants(true)
	super.destroy()
