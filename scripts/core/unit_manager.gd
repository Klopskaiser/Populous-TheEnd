class_name UnitManager extends Node

## Registry and spatial hash for all units (child of Main).
##
## The spatial hash (cell size ~4 m) enables cheap radius queries for target
## search and separation — never per-frame O(n^2) distance loops. The hash is
## refreshed in tick() (called from _physics_process; tests call it manually).
##
## Soft separation: units closer than SEPARATION_RADIUS push each other apart
## (each unit moves away from its neighbours, so pairs separate symmetrically).
## This prevents full overlap in normal play; scripted throws (Blast/Tornado,
## phase 5) use the THROWN state which is excluded here.

const HASH_CELL_SIZE: float = 4.0
## Minimum comfortable distance between unit centres (tight packing: group
## members stand just outside this radius).
const SEPARATION_RADIUS: float = 0.44
## Maximum push speed in metres per second.
const SEPARATION_SPEED: float = 1.6
## Separation processes at most this many units per tick (round-robin over
## slices; the push delta is scaled by the slice count) — a full pass every
## frame would dominate the frame time with thousands of units.
const SEPARATION_UNITS_PER_TICK: int = 600
## Max neighbour candidates examined per separated unit. Bounds the cost when
## thousands of units share one crowded hash bucket (the benchmark showed
## ~190 ms/tick without this cap when 4000 units converge on one point).
const SEPARATION_MAX_CHECKS: int = 20
## Max A* path computations per tick (mass move orders are spread over
## frames via the path queue instead of stalling one frame).
const PATHS_PER_TICK: int = 48

## Idle 6-packs (phase 7b, reworked on user feedback): EXPLICIT groups with
## sticky membership — the earlier centroid drift made units hop between
## packs. Formation move orders REGISTER their 6-packs as groups right away
## (see register_move_group — units walking to their spot already count as
## members, slots are reserved). The idle finder below only picks up units
## that ended up ungrouped (hut spawns etc.), and only after a LONG idle.
const IDLE_REGROUP_DELAY: float = 30.0
## Search/join range for groups and loose mates.
const IDLE_GROUP_JOIN_RADIUS: float = 4.0
## A member farther than this from its group anchor is dropped (ordered away).
const IDLE_GROUP_LEAVE_RADIUS: float = 6.0
## Founding needs this many loose idle mates nearby (3-unit core minimum).
const IDLE_GROUP_MIN_NEIGHBOURS: int = 2
## Mates this close already stand IN formation (e.g. after a group move
## order lands in its 6-pack pattern): the cluster is adopted as a group
## in place — NOBODY moves. Member offsets are ~0.55 m, so 1.5 m covers a
## settled pack including separation wiggle.
const IDLE_GROUP_SETTLED_RADIUS: float = 1.5
## Every unit is regroup-checked about once per this many ticks (sliced).
const IDLE_REGROUP_SPREAD_TICKS: int = 30


## One idle 6-pack: a fixed anchor and monotonically assigned member slots
## (TribeCommands.MEMBER_OFFSETS). Slots are never re-used — no churn.
class IdleGroup extends RefCounted:
	var anchor: Vector3 = Vector3.ZERO
	var next_slot: int = 0
	var members: Array = []   # untyped: entries may be freed

	func is_full() -> bool:
		return next_slot >= TribeCommands.GROUP_SIZE

## Anti-stacking fallback: a unit found tightly inside another for this many
## separation passes gets sent to a free nearby cell (soft separation could
## not free it — e.g. walled in by a crowd; visible as sprite flicker).
const OVERLAP_ESCAPE_PASSES: int = 8
const OVERLAP_TIGHT_FACTOR: float = 0.35

var terrain_data: TerrainData = null
var nav_grid: NavGrid = null
var tribes: Array[Tribe] = []
var tree_manager: TreeManager = null
var wood_pile_manager: WoodPileManager = null
## Central MultiMesh renderer (set by Main; null in headless tests).
var unit_renderer: UnitRenderer = null
## Injected by Main/tests; the siege engine (7f) scans enemy buildings with it.
var building_manager: BuildingManager = null

var units: Array[Unit] = []
## Live projectiles (Fireball), ticked here after the units.
var projectiles: Array = []
var _hash: Dictionary[Vector2i, Array] = {}   # hash cell -> Array of Unit
var _path_requests: Array[Unit] = []
var _path_head: int = 0
var _separation_phase: int = 0
var _regroup_index: int = 0


func setup(p_terrain_data: TerrainData, p_nav_grid: NavGrid,
		p_tribes: Array[Tribe] = [], p_tree_manager: TreeManager = null,
		p_wood_pile_manager: WoodPileManager = null) -> void:
	terrain_data = p_terrain_data
	nav_grid = p_nav_grid
	tribes = p_tribes
	tree_manager = p_tree_manager
	wood_pile_manager = p_wood_pile_manager


## In-game driver: ticks all units centrally (no per-unit _physics_process —
## the Node callback overhead alone would dominate with thousands of units),
## then runs the manager systems. Tests call unit.tick()/tick() directly.
func _physics_process(delta: float) -> void:
	# Iterate a snapshot: an expiring corpse deregisters itself mid-loop via the
	# corpse_expired signal (erasing from `units`), which would otherwise skip
	# elements. Dead units still tick — their tick runs the corpse decay.
	for unit in units.duplicate():
		if is_instance_valid(unit):
			unit.tick(delta)
	tick(delta)


func tick(delta: float) -> void:
	# Hash refresh, inlined (a function call per unit per tick adds up).
	for unit in units:
		var new_cell: Vector2i = Vector2i(
			int(floor(unit.position.x / HASH_CELL_SIZE)),
			int(floor(unit.position.z / HASH_CELL_SIZE)))
		if new_cell != unit._hash_cell:
			_move_hash_cell(unit, new_cell)
	_drain_path_queue()
	_apply_separation(delta)
	_apply_idle_regroup(delta)
	_tick_projectiles(delta)


# --- Projectiles -------------------------------------------------------------------

## Registers a projectile (e.g. a Fireball); it is ticked here until `done`
## flips, then freed. Always added as a child: in-game it enters the tree
## (visible, _ready builds the visual); in headless tests the manager stays
## outside the tree, so _ready never runs and the child is freed with it.
func register_projectile(projectile: Node3D) -> void:
	projectiles.append(projectile)
	add_child(projectile)


## Index loop instead of for-in: projectiles may register NEW projectiles
## while being ticked (firestorm spawns bolts, integrity rules spawn debris)
## — appended entries are picked up safely in the same pass.
func _tick_projectiles(delta: float) -> void:
	var i: int = 0
	while i < projectiles.size():
		var p = projectiles[i]
		if not is_instance_valid(p):
			projectiles.remove_at(i)
			continue
		p.tick(delta)
		if p.done:
			p.queue_free()
			projectiles.remove_at(i)
		else:
			i += 1


# --- Path queue -------------------------------------------------------------------

## Registers a unit whose pending move target needs a path (see
## Unit._start_path_to). Deduplicated via the unit's _path_queued flag.
func request_path(unit: Unit) -> void:
	_path_requests.append(unit)


func _drain_path_queue() -> void:
	var budget: int = PATHS_PER_TICK
	while budget > 0 and _path_head < _path_requests.size():
		var unit: Unit = _path_requests[_path_head]
		_path_head += 1
		if not is_instance_valid(unit):
			continue
		unit._resolve_pending_path()
		budget -= 1
	if _path_head >= _path_requests.size():
		_path_requests.clear()
		_path_head = 0


# --- Separation -----------------------------------------------------------------------

## Pushes overlapping units apart (soft, capped speed). Two scale guards:
## at most SEPARATION_UNITS_PER_TICK units are processed per tick (round-robin
## slices, push delta scaled by the slice count), and each unit examines at
## most SEPARATION_MAX_CHECKS neighbour candidates — so a mega-crowd on one
## spot cannot blow up the tick. Skips dead and thrown units; the target cell
## must stay walkable so nobody gets shoved into water.
func _apply_separation(delta: float) -> void:
	if units.is_empty():
		return
	var slices: int = maxi(1, int(ceil(float(units.size()) / float(SEPARATION_UNITS_PER_TICK))))
	if _separation_phase >= slices:
		_separation_phase = 0
	var max_step: float = SEPARATION_SPEED * delta * float(slices)
	for index in range(_separation_phase, units.size(), slices):
		var unit: Unit = units[index]
		if unit.state == Unit.State.DEAD or unit.state == Unit.State.THROWN \
				or unit.state == Unit.State.ROLL or unit.push_immune:
			continue
		var push: Vector2 = Vector2.ZERO
		var pos: Vector3 = unit.position
		var checks: int = SEPARATION_MAX_CHECKS
		var tight: bool = false
		var min_key: Vector2i = hash_key(pos - Vector3(SEPARATION_RADIUS, 0.0, SEPARATION_RADIUS))
		var max_key: Vector2i = hash_key(pos + Vector3(SEPARATION_RADIUS, 0.0, SEPARATION_RADIUS))
		for kz in range(min_key.y, max_key.y + 1):
			for kx in range(min_key.x, max_key.x + 1):
				var bucket: Array = _hash.get(Vector2i(kx, kz), [])
				for other: Unit in bucket:
					if other == unit or other.state == Unit.State.DEAD \
							or other.state == Unit.State.THROWN \
							or other.state == Unit.State.ROLL:
						continue
					checks -= 1
					var away: Vector2 = Vector2(pos.x - other.position.x, pos.z - other.position.z)
					var dist: float = away.length()
					if dist < SEPARATION_RADIUS:
						if dist < SEPARATION_RADIUS * OVERLAP_TIGHT_FACTOR:
							tight = true   # visibly stacked (sprite flicker)
						if dist < 0.001:
							# Full overlap: deterministic per-unit direction.
							var angle: float = float(unit.get_instance_id() % 628) * 0.01
							away = Vector2(cos(angle), sin(angle))
							dist = 0.001
						push += away / dist * (SEPARATION_RADIUS - dist)
					if checks <= 0:
						break
				if checks <= 0:
					break
			if checks <= 0:
				break
		# Anti-stacking fallback: soft separation could not free the unit for
		# several passes (walled in) -> walk it to a free nearby cell.
		if tight:
			unit.overlap_ticks += 1
			if unit.overlap_ticks >= OVERLAP_ESCAPE_PASSES \
					and unit.state == Unit.State.IDLE:
				unit.overlap_ticks = 0
				var free_cell: Vector2i = find_free_cell_near(pos)
				if free_cell.x >= 0 and nav_grid != null:
					unit.order_move(nav_grid.cell_to_world(free_cell))
				continue
		else:
			unit.overlap_ticks = 0
		if push == Vector2.ZERO:
			continue
		if push.length() > max_step:
			push = push.normalized() * max_step
		var nx: float = pos.x + push.x
		var nz: float = pos.z + push.y
		if nav_grid != null and not nav_grid.is_cell_walkable(
				nav_grid.world_to_cell(Vector3(nx, 0.0, nz))):
			continue
		unit.position.x = nx
		unit.position.z = nz
		if terrain_data != null:
			unit.position.y = terrain_data.get_height(nx, nz)
	_separation_phase = (_separation_phase + 1) % slices


# --- Idle regrouping (phase 7b) ---------------------------------------------------

## Sliced idle pass (phase 7b) — every unit gets a turn about once per
## IDLE_REGROUP_SPREAD_TICKS ticks, so the cost never spikes and the per-unit
## tick stays untouched. Does two things for IDLE units:
## 1. brave guard scan (small idle_aggro radius),
## 2. sticky idle 6-packs (join an existing group / found one).
func _apply_idle_regroup(delta: float) -> void:
	if units.is_empty():
		return
	var per_tick: int = maxi(1, int(ceil(float(units.size())
		/ float(IDLE_REGROUP_SPREAD_TICKS))))
	for i in range(per_tick):
		_regroup_index = (_regroup_index + 1) % units.size()
		var unit: Unit = units[_regroup_index]
		if unit.state != Unit.State.IDLE:
			continue
		# idle_seconds advances here (one visit per SPREAD interval on average).
		unit.idle_seconds += delta * float(IDLE_REGROUP_SPREAD_TICKS)
		# Village guard (braves): engage enemies inside the small idle radius.
		if unit.idle_aggro > 0.0:
			var enemy: Unit = unit._scan_for_enemy(unit.idle_aggro)
			if enemy != null:
				unit._begin_attack(enemy)
				continue
		if unit.idle_seconds < IDLE_REGROUP_DELAY:
			continue
		if unit.idle_group != null:
			# Sticky membership: members never switch; just keep it tidy.
			_prune_idle_group(unit.idle_group as IdleGroup)
			continue
		_join_or_found_group(unit)


## Ungrouped long-idle unit, in priority order:
## 1. A cluster of idle mates ALREADY standing tight (e.g. a group move
##    landed in its 6-pack formation): adopt it as a group IN PLACE —
##    nobody moves (the pack was already perfect, just not registered).
## 2. Join the first group with a free slot in range (actively WALKING
##    to its slot).
## 3. Only full groups nearby: do nothing (founding a new group right next
##    to one made units hop back and forth).
## 4. No group around and enough loose idle mates: found one at the unit's
##    own spot (it stays put as slot 0); the mates walk over in their turns.
func _join_or_found_group(unit: Unit) -> void:
	var group_nearby: bool = false
	var open_group: IdleGroup = null
	var loose_mates: int = 0
	var settled: Array[Unit] = []
	for other in get_units_in_radius(unit.position, IDLE_GROUP_JOIN_RADIUS, 12):
		if other == unit or other.tribe_id != unit.tribe_id:
			continue
		if other.idle_group != null:
			var group: IdleGroup = other.idle_group as IdleGroup
			group_nearby = true
			if open_group == null and not group.is_full() \
					and group.anchor.distance_to(unit.position) <= IDLE_GROUP_LEAVE_RADIUS:
				open_group = group
		elif other.state == Unit.State.IDLE:
			if other.position.distance_to(unit.position) <= IDLE_GROUP_SETTLED_RADIUS:
				settled.append(other)   # already standing in formation
			if other.idle_seconds >= IDLE_REGROUP_DELAY:
				loose_mates += 1
	if not group_nearby and settled.size() >= IDLE_GROUP_MIN_NEIGHBOURS:
		var adopted: IdleGroup = IdleGroup.new()
		adopted.anchor = unit.position
		join_idle_group(unit, adopted, false)
		for mate in settled:
			if adopted.is_full():
				break
			join_idle_group(mate, adopted, false)
		return
	if open_group != null:
		join_idle_group(unit, open_group)
		return
	if group_nearby:
		return
	if loose_mates >= IDLE_GROUP_MIN_NEIGHBOURS:
		var group: IdleGroup = IdleGroup.new()
		group.anchor = unit.position
		join_idle_group(unit, group)


## Adds the unit on the group's next slot (leaving any previous group).
## With `walk` it actively WALKS there (a real move order — no sliding);
## without (adopting a cluster that already stands in formation, or a
## formation move order that walks the unit itself) it just registers.
func join_idle_group(unit: Unit, group: IdleGroup, walk: bool = true) -> void:
	if unit.idle_group != null and unit.idle_group != group \
			and unit.idle_group is IdleGroup:
		(unit.idle_group as IdleGroup).members.erase(unit)
	group.members.append(unit)
	unit.idle_group = group
	var slot: int = mini(group.next_slot, TribeCommands.MEMBER_OFFSETS.size() - 1)
	group.next_slot += 1
	if not walk:
		return
	var target: Vector3 = group.anchor + TribeCommands.MEMBER_OFFSETS[slot]
	if Vector2(target.x - unit.position.x, target.z - unit.position.z).length() > 0.3:
		unit.order_move(target)


## Registers one 6-pack of a formation move order as an idle group at the
## formation centre: the units are still WALKING there, but they already
## count as members — their slots are reserved (nobody else docks on) and
## the idle finder leaves them alone once they arrive. Called by
## TribeCommands.order_move for every (non-aggressive) group batch.
func register_move_group(group_units: Array[Unit], anchor: Vector3) -> void:
	if group_units.size() < 2:
		return
	var group: IdleGroup = IdleGroup.new()
	group.anchor = anchor
	for unit in group_units:
		join_idle_group(unit, group, false)


## Drops freed/dead members and everyone busy elsewhere or too far away.
## Members still WALKING count by their move DESTINATION, not their current
## position — units en route to the formation stay members (their slot is
## reserved); a member ordered somewhere far is dropped right away. A group
## shrunk to one member dissolves, so a fresh group can form there later.
func _prune_idle_group(group: IdleGroup) -> void:
	var kept: Array = []
	for m in group.members:
		if not is_instance_valid(m) or m.state == Unit.State.DEAD:
			continue
		var unit: Unit = m as Unit
		if unit.idle_group != group:
			continue   # switched groups meanwhile (e.g. a new move order)
		var busy: bool = unit.state != Unit.State.IDLE and unit.state != Unit.State.MOVE
		var anchor_dist: float
		if unit.state == Unit.State.MOVE and not unit.waypoint_queue.is_empty():
			anchor_dist = unit.waypoint_queue.back().distance_to(group.anchor)
		else:
			anchor_dist = unit.position.distance_to(group.anchor)
		if busy or anchor_dist > IDLE_GROUP_LEAVE_RADIUS:
			unit.idle_group = null
			continue
		kept.append(unit)
	if kept.size() <= 1:
		for m in kept:
			(m as Unit).idle_group = null
		kept = []
	group.members = kept


## Nearest walkable cell with room to stand (fewer than 2 units within the
## cell's centre) — the anti-stacking escape target.
func find_free_cell_near(pos: Vector3) -> Vector2i:
	if nav_grid == null:
		return Vector2i(-1, -1)
	var start: Vector2i = nav_grid.world_to_cell(pos)
	for radius in range(1, 7):
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue   # ring only
				var cell: Vector2i = start + Vector2i(dx, dz)
				if not nav_grid.is_cell_walkable(cell):
					continue
				var centre: Vector3 = nav_grid.cell_to_world(cell)
				if get_units_in_radius(centre, 0.6, 2).size() < 2:
					return cell
	return Vector2i(-1, -1)


# --- Registry -------------------------------------------------------------------

func register(unit: Unit) -> void:
	if unit in units:
		return
	units.append(unit)
	unit.died.connect(_on_unit_died)
	unit.corpse_expired.connect(_on_corpse_expired)
	unit.converted.connect(_on_unit_converted)
	_update_hash_cell(unit)
	if unit_renderer != null and unit.renders_as_sprite():
		unit_renderer.register_unit(unit)   # siege engines draw their own model


func unregister(unit: Unit) -> void:
	units.erase(unit)
	if unit.died.is_connected(_on_unit_died):
		unit.died.disconnect(_on_unit_died)
	if unit.corpse_expired.is_connected(_on_corpse_expired):
		unit.corpse_expired.disconnect(_on_corpse_expired)
	if unit.converted.is_connected(_on_unit_converted):
		unit.converted.disconnect(_on_unit_converted)
	if _hash.has(unit._hash_cell):
		_hash[unit._hash_cell].erase(unit)
	unit._hash_cell = Vector2i(2147483647, 2147483647)
	if unit_renderer != null:
		unit_renderer.unregister_unit(unit)


## Removes a unit from the live simulation (registry, spatial hash, renderer)
## WITHOUT touching its tribe membership — used when a brave enters a training
## building: it stays alive and counted as population until it graduates into a
## combat unit. (unregister already leaves the tribe list alone.)
func remove_from_world(unit: Unit) -> void:
	unregister(unit)


func _on_unit_died(unit: Unit) -> void:
	# The unit is NOT removed here: it stays registered (and rendered) as a
	# lying corpse — combat, selection, separation and target scans all skip
	# DEAD units. Only the tribe loses it immediately (population drops).
	if unit.tribe != null:
		unit.tribe.remove_unit(unit)
	if is_inside_tree():
		var events: Node = get_node_or_null("/root/Events")
		if events != null:
			events.unit_died.emit(unit)


## Corpse finished fading: now actually remove and free the node. It is out of
## the registry, hash, renderer, tribe and (via _die) every combat slot.
func _on_corpse_expired(unit: Unit) -> void:
	unregister(unit)
	unit.queue_free()


## Preacher conversion switched the unit's tribe: refresh its rendered colour.
func _on_unit_converted(unit: Unit) -> void:
	if unit_renderer != null:
		unit_renderer.update_unit_color(unit)


# --- Spawning -------------------------------------------------------------------

func spawn_unit(scene: PackedScene, tribe_id: int, pos: Vector3) -> Unit:
	var unit: Unit = scene.instantiate() as Unit
	unit.tribe_id = tribe_id
	unit.terrain_data = terrain_data
	unit.nav_grid = nav_grid
	unit.path_service = self
	# Worker references — only Braves have these properties.
	unit.set("tree_manager", tree_manager)
	unit.set("wood_pile_manager", wood_pile_manager)
	# Building scan — only the SiegeEngine has this property (7f).
	unit.set("building_manager", building_manager)
	unit.position = pos
	if terrain_data != null:
		unit.position.y = terrain_data.get_height(pos.x, pos.z)
	add_child(unit)
	register(unit)
	if tribe_id >= 0 and tribe_id < tribes.size():
		tribes[tribe_id].add_unit(unit)
	return unit


# --- Spatial hash ----------------------------------------------------------------

func hash_key(pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(pos.x / HASH_CELL_SIZE)),
		int(floor(pos.z / HASH_CELL_SIZE)))


func _update_hash_cell(unit: Unit) -> void:
	var new_cell: Vector2i = hash_key(unit.position)
	if new_cell != unit._hash_cell:
		_move_hash_cell(unit, new_cell)


func _move_hash_cell(unit: Unit, new_cell: Vector2i) -> void:
	if _hash.has(unit._hash_cell):
		_hash[unit._hash_cell].erase(unit)
	if not _hash.has(new_cell):
		_hash[new_cell] = []
	_hash[new_cell].append(unit)
	unit._hash_cell = new_cell


## All units within radius (XZ distance) around pos. `max_count` > 0 caps the
## result (early out) — in a mega-crowd on one spot an uncapped query builds
## a thousands-entry array PER CALLER and dominates the tick.
func get_units_in_radius(pos: Vector3, radius: float, max_count: int = 0) -> Array[Unit]:
	var result: Array[Unit] = []
	var min_key: Vector2i = hash_key(pos - Vector3(radius, 0.0, radius))
	var max_key: Vector2i = hash_key(pos + Vector3(radius, 0.0, radius))
	var flat_pos: Vector2 = Vector2(pos.x, pos.z)
	for kz in range(min_key.y, max_key.y + 1):
		for kx in range(min_key.x, max_key.x + 1):
			var bucket: Array = _hash.get(Vector2i(kx, kz), [])
			for unit: Unit in bucket:
				var flat: Vector2 = Vector2(unit.position.x, unit.position.z)
				if flat.distance_to(flat_pos) <= radius:
					result.append(unit)
					if max_count > 0 and result.size() >= max_count:
						return result
	return result


func get_units_of_tribe(tribe_id: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in units:
		if unit.tribe_id == tribe_id:
			result.append(unit)
	return result
