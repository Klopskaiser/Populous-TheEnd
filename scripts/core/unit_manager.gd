class_name UnitManager extends Node

## Registry and spatial grid for all units (child of Main).
##
## Stufe C1 (data-oriented, plans/08d): the hot per-unit data lives in parallel
## packed arrays (soa_*), indexed by Unit._idx (= the unit's slot in `units`;
## append on register, swap-remove on unregister). The arrays are AUTHORITATIVE
## for every hot loop here (grid build, separation, enemy scans) — position
## writers double-write (array + Node3D.position, see Unit._snap_to_ground and
## the external writer sites), event-driven flags mirror at their set sites.
## There is deliberately NO per-tick object->array mirror (measured O(n) killer,
## see PROGRESS "Stufe B").
##
## The spatial grid (cell size ~4 m, CSR layout: counting sort over soa_pos,
## rebuilt once per tick) enables cheap radius queries for target search and
## separation — never per-frame O(n^2) distance loops. Units registered since
## the last build sit in _grid_extra (scanned linearly by queries); stale grid
## entries after a swap-remove are filtered by the live index/position checks.
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

# --- Combat groups (phase 8.2) ---------------------------------------------------
## Minimum distance between the anchors of neighbouring combat groups: closer
## fights are pushed apart (via their defenders — the members follow their
## rings), so a battle frays into distinct little brawls instead of one blob.
## Small but > 0 per user spec (~2.5-3 m, tunable).
const COMBAT_GROUP_MIN_DIST: float = 2.8
## Push speed of the group separation (m/s, split between both defenders).
const COMBAT_GROUP_PUSH_SPEED: float = 1.2
## How fast a group's anchor trails its (moving) defender.
const COMBAT_ANCHOR_FOLLOW_SPEED: float = 3.0
## The push pass processes at most this many groups per tick (round-robin
## slices, push delta scaled by the slice count) and each group examines at
## most this many neighbour candidates — a mega-battle with thousands of
## groups packed together must not blow up the tick (same guards as the unit
## separation).
const COMBAT_GROUPS_PER_TICK: int = 256
const COMBAT_GROUP_MAX_CHECKS: int = 12
## Max units one enemy scan may EXAMINE (friends included) while collecting
## its enemy candidates — bounds the cost of a scan deep inside a mega-crowd.
const SCAN_MAX_EXAMINED: int = 300

var terrain_data: TerrainData = null
var nav_grid: NavGrid = null
var tribes: Array[Tribe] = []
var tree_manager: TreeManager = null
var wood_pile_manager: WoodPileManager = null
## Central MultiMesh renderer (set by Main; null in headless tests).
var unit_renderer: UnitRenderer = null
## Injected by Main/tests; the siege engine (7f) scans enemy buildings with it.
var building_manager: BuildingManager = null
## Phase 8.1 (Stufe A): off-main-thread pathfinding. When set, path requests are
## solved on the worker thread and applied here without any per-tick limit. Null
## → the synchronous, frame-budgeted queue below (tests, headless, A/B fallback).
var path_worker: PathWorker = null

## Registry, aligned with the soa_* arrays: units[i]._idx == i.
var units: Array[Unit] = []
## Live projectiles (Fireball), ticked here after the units.
var projectiles: Array = []
## Registered combat groups (phase 8.2); pruned in _apply_combat_groups.
var combat_groups: Array = []
var _path_requests: Array[Unit] = []
var _path_head: int = 0
var _separation_phase: int = 0
var _regroup_index: int = 0

# --- SoA hot data (Stufe C1) --------------------------------------------------
## Bit flags in soa_flags (event-mirrored via Unit._sync_soa_flags).
const FLAG_FLIES: int = 1
const FLAG_PUSH_IMMUNE: int = 2
const FLAG_CREW_SEATED: int = 4
const FLAG_TARGETABLE: int = 8

var soa_pos: PackedVector3Array = PackedVector3Array()
var soa_state: PackedInt32Array = PackedInt32Array()
var soa_tribe: PackedInt32Array = PackedInt32Array()
var soa_flags: PackedInt32Array = PackedInt32Array()
var soa_veh_sep: PackedFloat32Array = PackedFloat32Array()
var soa_sep_mult: PackedFloat32Array = PackedFloat32Array()
## Separation passes spent tightly stacked (only the separation touches this).
var soa_overlap: PackedInt32Array = PackedInt32Array()

# --- Spatial grid (CSR buckets, rebuilt once per tick) -------------------------
var _grid_w: int = 64                 # cells per axis (from terrain size)
var _grid_cells: int = 64 * 64
var _cell_count: PackedInt32Array = PackedInt32Array()   # scratch (doubles as fill cursor)
var _cell_start: PackedInt32Array = PackedInt32Array()   # size _grid_cells + 1
var _cell_units: PackedInt32Array = PackedInt32Array()   # unit indices, bucket-sorted
var _unit_cell: PackedInt32Array = PackedInt32Array()    # scratch: cell id per unit
## Units registered since the last grid build (queries scan these linearly).
var _grid_extra: PackedInt32Array = PackedInt32Array()
## units.size() at the last grid build (grid entries >= this are stale).
var _grid_built: int = 0


func setup(p_terrain_data: TerrainData, p_nav_grid: NavGrid,
		p_tribes: Array[Tribe] = [], p_tree_manager: TreeManager = null,
		p_wood_pile_manager: WoodPileManager = null) -> void:
	terrain_data = p_terrain_data
	nav_grid = p_nav_grid
	tribes = p_tribes
	tree_manager = p_tree_manager
	wood_pile_manager = p_wood_pile_manager
	if terrain_data != null:
		_grid_w = maxi(1, int(ceil(
			float(terrain_data.size) * TerrainData.CELL_SIZE / HASH_CELL_SIZE)))
	_grid_cells = _grid_w * _grid_w
	_cell_count.resize(_grid_cells)
	_cell_start.resize(_grid_cells + 1)


## In-game driver: ticks all units centrally (no per-unit _physics_process —
## the Node callback overhead alone would dominate with thousands of units),
## then runs the manager systems. Tests call unit.tick()/tick() directly.
## Joins the path worker thread on teardown (scene change / quit) so it never
## outlives the tree. Idempotent; safe when no worker was created.
func _exit_tree() -> void:
	if path_worker != null:
		path_worker.stop()
		path_worker = null
		if nav_grid != null:
			nav_grid.path_worker = null


func _physics_process(delta: float) -> void:
	# Iterate a snapshot: an expiring corpse deregisters itself mid-loop via the
	# corpse_expired signal (erasing from `units`), which would otherwise skip
	# elements. Dead units still tick — their tick runs the corpse decay.
	for unit in units.duplicate():
		if is_instance_valid(unit):
			unit.tick(delta)
	tick(delta)


func tick(delta: float) -> void:
	_rebuild_grid()
	_drain_path_queue()
	_apply_separation(delta)
	_apply_combat_groups(delta)
	_apply_idle_regroup(delta)
	_tick_projectiles(delta)


## Rebuilds the CSR bucket grid from the authoritative position arrays
## (counting sort: count per cell, prefix sums, back-fill). Out-of-bounds
## positions clamp into the edge cells. Queries between builds see units
## registered afterwards via _grid_extra; swap-removed slots are filtered by
## the callers' live index/position checks.
func _rebuild_grid() -> void:
	var n: int = units.size()
	_grid_built = n
	_grid_extra.clear()
	if _cell_start.size() != _grid_cells + 1:   # setup() not called (bare tests)
		_cell_count.resize(_grid_cells)
		_cell_start.resize(_grid_cells + 1)
	if _unit_cell.size() < n:
		_unit_cell.resize(n)
		_cell_units.resize(n)
	_cell_count.fill(0)
	var pos: PackedVector3Array = soa_pos
	var inv: float = 1.0 / HASH_CELL_SIZE
	var w: int = _grid_w
	var top: int = w - 1
	for i in range(n):
		var p: Vector3 = pos[i]
		var c: int = clampi(int(p.z * inv), 0, top) * w \
			+ clampi(int(p.x * inv), 0, top)
		_unit_cell[i] = c
		_cell_count[c] += 1
	var acc: int = 0
	for c in range(_grid_cells):
		_cell_start[c] = acc
		acc += _cell_count[c]
	_cell_start[_grid_cells] = acc
	# Back-fill from the bucket ends, reusing _cell_count as the cursor.
	for i in range(n):
		var c: int = _unit_cell[i]
		var slot: int = _cell_count[c] - 1
		_cell_count[c] = slot
		_cell_units[_cell_start[c] + slot] = i


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
	if path_worker != null:
		_drain_path_queue_async()
		return
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


## Worker path: submit ALL queued requests to the worker thread (no per-tick
## limit — submitting is cheap), then apply every result the worker has ready.
## Applying is billed only for the world/Y conversion, so no throughput cap is
## needed either → the request queue can never back up (phase-8 restack bug).
func _drain_path_queue_async() -> void:
	for i in range(_path_head, _path_requests.size()):
		var unit: Unit = _path_requests[i]
		if is_instance_valid(unit):
			unit._submit_path_request(path_worker)
	_path_requests.clear()
	_path_head = 0
	for res in path_worker.drain_results():
		var obj: Object = instance_from_id(res[0])
		if obj is Unit and is_instance_valid(obj):
			(obj as Unit)._apply_worker_path(res[1], res[2])


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
	# Flat SoA kernel (Stufe C1): everything hot reads/writes the packed arrays;
	# the Unit object is only fetched for the rare cases (actual push, escape,
	# full overlap). Grid entries can be one tick stale after a swap-remove —
	# the live index guard + array positions keep the pass safe.
	var n: int = units.size()
	var pos: PackedVector3Array = soa_pos
	var sstate: PackedInt32Array = soa_state
	var sflags: PackedInt32Array = soa_flags
	var sveh: PackedFloat32Array = soa_veh_sep
	var cell_units: PackedInt32Array = _cell_units
	var cell_start: PackedInt32Array = _cell_start
	var st_dead: int = Unit.State.DEAD
	var st_thrown: int = Unit.State.THROWN
	var st_roll: int = Unit.State.ROLL
	var grid_top: int = _grid_w - 1
	var grid_n: int = mini(_grid_built, n)
	var inv_cell: float = 1.0 / HASH_CELL_SIZE
	var slices: int = maxi(1, int(ceil(float(n) / float(SEPARATION_UNITS_PER_TICK))))
	if _separation_phase >= slices:
		_separation_phase = 0
	var max_step: float = SEPARATION_SPEED * delta * float(slices)
	for index in range(_separation_phase, n, slices):
		var st: int = sstate[index]
		if st == st_dead or st == st_thrown or st == st_roll:
			continue
		var fl: int = sflags[index]
		# Seated crew (airship deck AND ground siege/ram side slots) are pinned to
		# their slots by _tick_crew; the flat separation would shove them off-slot
		# and SNAP their Y onto the terrain for a frame (they flicker/vanish on
		# slopes, user bug). They neither separate nor push others.
		if fl & FLAG_CREW_SEATED:
			continue
		# Vehicles (siege engines) are push_immune against pedestrians but keep
		# a big spacing among EACH OTHER (their crews clip otherwise, phase
		# 8.2); other push_immune units (tower/hut reserves) skip entirely.
		var veh_r: float = sveh[index]
		if (fl & FLAG_PUSH_IMMUNE) != 0 and veh_r <= 0.0:
			continue
		var radius: float = SEPARATION_RADIUS if veh_r <= 0.0 else veh_r
		var own: Vector3 = pos[index]
		var pos_x: float = own.x
		var pos_z: float = own.z
		var push_x: float = 0.0
		var push_z: float = 0.0
		var checks: int = SEPARATION_MAX_CHECKS
		var tight: bool = false
		var kx0: int = clampi(int((pos_x - radius) * inv_cell), 0, grid_top)
		var kx1: int = clampi(int((pos_x + radius) * inv_cell), 0, grid_top)
		var kz0: int = clampi(int((pos_z - radius) * inv_cell), 0, grid_top)
		var kz1: int = clampi(int((pos_z + radius) * inv_cell), 0, grid_top)
		for kz in range(kz0, kz1 + 1):
			var row: int = kz * _grid_w
			for kx in range(kx0, kx1 + 1):
				var c: int = row + kx
				for k in range(cell_start[c], cell_start[c + 1]):
					var j: int = cell_units[k]
					if j == index or j >= grid_n:
						continue
					var stj: int = sstate[j]
					if stj == st_dead or stj == st_thrown or stj == st_roll:
						continue
					var flj: int = sflags[j]
					if flj & FLAG_CREW_SEATED:
						continue
					if veh_r > 0.0 and (sveh[j] <= 0.0
							or ((flj ^ fl) & FLAG_FLIES) != 0):
						continue   # vehicles separate only vs same-layer vehicles
						# (airships vs airships, ground vs ground — an airship is
						# never pushed by the ground vehicles it flies over)
					checks -= 1
					var pj: Vector3 = pos[j]
					var away_x: float = pos_x - pj.x
					var away_z: float = pos_z - pj.z
					var dist: float = sqrt(away_x * away_x + away_z * away_z)
					if dist < radius:
						if dist < radius * OVERLAP_TIGHT_FACTOR:
							tight = true   # visibly stacked (sprite flicker)
						if dist < 0.001:
							# Full overlap: deterministic per-unit direction.
							var angle: float = float(
								units[index].get_instance_id() % 628) * 0.01
							away_x = cos(angle)
							away_z = sin(angle)
							dist = 0.001
						var f: float = (radius - dist) / dist
						push_x += away_x * f
						push_z += away_z * f
					if checks <= 0:
						break
				if checks <= 0:
					break
			if checks <= 0:
				break
		# Anti-stacking fallback: soft separation could not free the unit for
		# several passes (walled in) -> walk it to a free nearby cell.
		# Pedestrians only — a vehicle resolves via the push alone.
		if tight and veh_r <= 0.0:
			var ticks: int = soa_overlap[index] + 1
			soa_overlap[index] = ticks
			if ticks >= OVERLAP_ESCAPE_PASSES and st == Unit.State.IDLE:
				soa_overlap[index] = 0
				var free_cell: Vector2i = find_free_cell_near(own)
				if free_cell.x >= 0 and nav_grid != null:
					units[index].order_move(nav_grid.cell_to_world(free_cell))
				continue
		elif soa_overlap[index] != 0:
			soa_overlap[index] = 0
		if push_x == 0.0 and push_z == 0.0:
			continue
		# Airships shove clear much faster than ground units drift apart.
		var step_cap: float = max_step * soa_sep_mult[index]
		var push_len: float = sqrt(push_x * push_x + push_z * push_z)
		if push_len > step_cap:
			var scale: float = step_cap / push_len
			push_x *= scale
			push_z *= scale
		var nx: float = pos_x + push_x
		var nz: float = pos_z + push_z
		# Flyers may be pushed over water/blocked ground (they fly); ground units
		# must not be shoved into an unwalkable cell.
		var is_flyer: bool = (fl & FLAG_FLIES) != 0
		if not is_flyer and nav_grid != null and not nav_grid.is_cell_walkable(
				nav_grid.world_to_cell(Vector3(nx, 0.0, nz))):
			continue
		# Ground units snap to the terrain; a flyer keeps its own altitude
		# (its _snap_to_ground runs each tick) — never drop it to the ground.
		var ny: float = own.y
		if terrain_data != null and not is_flyer:
			ny = terrain_data.get_height(nx, nz)
		var moved: Vector3 = Vector3(nx, ny, nz)
		pos[index] = moved
		units[index].position = moved
	_separation_phase = (_separation_phase + 1) % slices


# --- Combat groups (phase 8.2) -----------------------------------------------------

## Registers a freshly founded combat group (called by Unit._found_group_on;
## bare tests without a manager run their groups unregistered).
func register_combat_group(group) -> void:
	combat_groups.append(group)


## Per-tick combat-group pass: prune dead fights, trail each anchor after its
## defender, and push the DEFENDERS of too-close groups apart (min anchor
## distance) — the attackers/waiters follow their rings, so the whole battle
## frays into separate little brawls instead of one blob (phase 8.2).
var _group_push_phase: int = 0
var _group_empty_bucket: Array = []


func _apply_combat_groups(delta: float) -> void:
	if combat_groups.is_empty():
		return
	# Prune + anchor follow, every tick (cheap, O(groups)).
	var kept: Array = []
	var anchor_hash: Dictionary = {}
	for g in combat_groups:
		if not g.is_alive():
			g.release_all()
			continue
		g.anchor = g.anchor.move_toward(
			g.defender.position, COMBAT_ANCHOR_FOLLOW_SPEED * delta)
		kept.append(g)
		var key: Vector2i = hash_key(g.anchor)
		if not anchor_hash.has(key):
			anchor_hash[key] = []
		anchor_hash[key].append(g)
	combat_groups = kept
	# Min-distance push, sliced + check-capped (see constant doc).
	var slices: int = maxi(1, int(ceil(float(kept.size()) / float(COMBAT_GROUPS_PER_TICK))))
	if _group_push_phase >= slices:
		_group_push_phase = 0
	var max_step: float = COMBAT_GROUP_PUSH_SPEED * delta * float(slices)
	for index in range(_group_push_phase, kept.size(), slices):
		var g = kept[index]
		var defender = g.defender
		if defender.state == Unit.State.DEAD or defender.state == Unit.State.THROWN \
				or defender.state == Unit.State.ROLL or defender.push_immune:
			continue
		var pos: Vector3 = g.anchor
		var push: Vector2 = Vector2.ZERO
		var key: Vector2i = hash_key(pos)
		var checks: int = COMBAT_GROUP_MAX_CHECKS
		# Centre-first bucket order, mirrored for every second defender: a
		# fixed min->max sweep would spend the check budget on NORTHERN
		# neighbours first and push every crowded group systematically south
		# (the same direction-bias class as the old scan drift).
		var flip: int = -1 if (defender.get_instance_id() & 1) == 0 else 1
		for rz in [0, -1, 1]:
			var kz: int = key.y + rz * flip
			for rx in [0, -1, 1]:
				var kx: int = key.x + rx * flip
				for other in anchor_hash.get(Vector2i(kx, kz), _group_empty_bucket):
					if other == g:
						continue
					checks -= 1
					var away: Vector2 = Vector2(
						pos.x - other.anchor.x, pos.z - other.anchor.z)
					var dist: float = away.length()
					if dist < COMBAT_GROUP_MIN_DIST:
						if dist < 0.001:
							# Full overlap: deterministic per-defender direction.
							var angle: float = float(defender.get_instance_id() % 628) * 0.01
							away = Vector2(cos(angle), sin(angle))
							dist = 0.001
						push += away / dist * (COMBAT_GROUP_MIN_DIST - dist)
					if checks <= 0:
						break
				if checks <= 0:
					break
			if checks <= 0:
				break
		if push == Vector2.ZERO:
			continue
		if push.length() > max_step:
			push = push.normalized() * max_step
		var nx: float = defender.position.x + push.x
		var nz: float = defender.position.z + push.y
		if nav_grid != null and not nav_grid.is_cell_walkable(
				nav_grid.world_to_cell(Vector3(nx, 0.0, nz))):
			continue
		defender.position.x = nx
		defender.position.z = nz
		if terrain_data != null:
			defender.position.y = terrain_data.get_height(nx, nz)
	_group_push_phase = (_group_push_phase + 1) % slices


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
		# Small examine budget: this scan runs for EVERY idle brave (sliced),
		# and deep inside a friendly crowd the full budget would iterate
		# hundreds of friends per scan (measured +14 ms/tick at 6000 idle).
		if unit.idle_aggro > 0.0:
			var enemy: Unit = unit._scan_for_enemy(unit.idle_aggro, 32)
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
	if unit._idx >= 0:
		return
	unit._idx = units.size()
	units.append(unit)
	unit.in_world = true
	# SoA slots (Stufe C1): captured from the unit's current fields; position
	# writers double-write from here on, flags mirror at their event sites.
	soa_pos.append(unit.position)
	soa_state.append(unit.state)
	soa_tribe.append(unit.tribe_id)
	soa_flags.append(unit._compute_soa_flags())
	soa_veh_sep.append(unit.vehicle_separation)
	soa_sep_mult.append(unit.separation_speed_mult)
	soa_overlap.append(0)
	unit._bind_soa(self)
	_grid_extra.append(unit._idx)   # visible to queries before the next build
	unit.died.connect(_on_unit_died)
	unit.corpse_expired.connect(_on_corpse_expired)
	unit.converted.connect(_on_unit_converted)
	if unit_renderer != null and unit.renders_as_sprite():
		unit_renderer.register_unit(unit)   # siege engines draw their own model


## Swap-remove (same pattern as UnitRenderer.unregister_unit): the last slot's
## unit moves into the freed slot across `units` and every soa_* array. Stale
## grid entries pointing at the old last slot are dropped by the queries' index
## guard until the next rebuild.
func unregister(unit: Unit) -> void:
	var index: int = unit._idx
	if index >= 0:
		var last: int = units.size() - 1
		var moved: Unit = units[last]
		units[index] = moved
		units.remove_at(last)
		soa_pos[index] = soa_pos[last]
		soa_state[index] = soa_state[last]
		soa_tribe[index] = soa_tribe[last]
		soa_flags[index] = soa_flags[last]
		soa_veh_sep[index] = soa_veh_sep[last]
		soa_sep_mult[index] = soa_sep_mult[last]
		soa_overlap[index] = soa_overlap[last]
		soa_pos.resize(last)
		soa_state.resize(last)
		soa_tribe.resize(last)
		soa_flags.resize(last)
		soa_veh_sep.resize(last)
		soa_sep_mult.resize(last)
		soa_overlap.resize(last)
		if moved != unit:
			moved._idx = index
		unit._idx = -1
	unit.in_world = false
	# Leaving the world ends the unit's fight: its own group dissolves (the
	# attackers retarget) and any attacker/waiter seat is released (phase 8.2).
	unit._dissolve_own_group()
	unit._leave_combat_group()
	if unit.died.is_connected(_on_unit_died):
		unit.died.disconnect(_on_unit_died)
	if unit.corpse_expired.is_connected(_on_corpse_expired):
		unit.corpse_expired.disconnect(_on_corpse_expired)
	if unit.converted.is_connected(_on_unit_converted):
		unit.converted.disconnect(_on_unit_converted)
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


## Preacher conversion switched the unit's tribe: mirror the SoA slot and
## refresh its rendered colour.
func _on_unit_converted(unit: Unit) -> void:
	if unit._idx >= 0:
		soa_tribe[unit._idx] = unit.tribe_id
	if unit_renderer != null:
		unit_renderer.update_unit_color(unit)


# --- Spawning -------------------------------------------------------------------

func spawn_unit(scene: PackedScene, tribe_id: int, pos: Vector3) -> Unit:
	# Hard unit cap per tribe (phase 7i): refuse to spawn beyond it. Callers
	# (hut spawn, training completion) must handle the null return.
	if tribe_id >= 0 and tribe_id < tribes.size() and tribes[tribe_id].at_unit_cap():
		return null
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


# --- Spatial grid ----------------------------------------------------------------

## Cell key on the (unclamped) infinite grid — still used by the combat-group
## anchor hash (its own small dictionary, not the unit grid).
func hash_key(pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(pos.x / HASH_CELL_SIZE)),
		int(floor(pos.z / HASH_CELL_SIZE)))


## All units within radius (XZ distance) around pos. `max_count` > 0 caps the
## result (early out) — in a mega-crowd on one spot an uncapped query builds
## a thousands-entry array PER CALLER and dominates the tick.
func get_units_in_radius(pos: Vector3, radius: float, max_count: int = 0) -> Array[Unit]:
	var result: Array[Unit] = []
	var n: int = units.size()
	var grid_n: int = mini(_grid_built, n)
	var pos_arr: PackedVector3Array = soa_pos
	var r2: float = radius * radius
	var inv_cell: float = 1.0 / HASH_CELL_SIZE
	var grid_top: int = _grid_w - 1
	var kx0: int = clampi(int((pos.x - radius) * inv_cell), 0, grid_top)
	var kx1: int = clampi(int((pos.x + radius) * inv_cell), 0, grid_top)
	var kz0: int = clampi(int((pos.z - radius) * inv_cell), 0, grid_top)
	var kz1: int = clampi(int((pos.z + radius) * inv_cell), 0, grid_top)
	for kz in range(kz0, kz1 + 1):
		var row: int = kz * _grid_w
		for kx in range(kx0, kx1 + 1):
			var c: int = row + kx
			for k in range(_cell_start[c], _cell_start[c + 1]):
				var i: int = _cell_units[k]
				if i >= grid_n:
					continue   # stale slot (unregistered since the grid build)
				var pi: Vector3 = pos_arr[i]
				var dx: float = pi.x - pos.x
				var dz: float = pi.z - pos.z
				if dx * dx + dz * dz <= r2:
					result.append(units[i])
					if max_count > 0 and result.size() >= max_count:
						return result
	# Units registered since the last grid build.
	for e in _grid_extra:
		if e < _grid_built or e >= n:
			continue
		var pe: Vector3 = pos_arr[e]
		var dx: float = pe.x - pos.x
		var dz: float = pe.z - pos.z
		if dx * dx + dz * dz <= r2:
			result.append(units[e])
			if max_count > 0 and result.size() >= max_count:
				return result
	return result


## Enemy-candidate query for combat scans (phase 8.2): collects up to
## `max_count` LIVING, targetable enemies of tribe `enemy_of` within `radius`.
## Two deliberate differences to get_units_in_radius:
## 1. Friendly units never consume the result budget — deep inside the own
##    blob the old capped query returned 24 friends and the scan went blind.
## 2. Buckets are visited ring by ring OUTWARD from the own cell — the old
##    min->max iteration found targets NW-first, which made whole battles
##    drift north (measured -35 m in 30 s, see plans/08c).
## The total number of EXAMINED units is capped (SCAN_MAX_EXAMINED) so one
## scan inside a mega-crowd stays bounded.
func get_enemy_candidates(pos: Vector3, radius: float, enemy_of: int,
		max_count: int, max_examined: int = SCAN_MAX_EXAMINED) -> Array[Unit]:
	var result: Array[Unit] = []
	var n: int = units.size()
	var grid_n: int = mini(_grid_built, n)
	var pos_arr: PackedVector3Array = soa_pos
	var sstate: PackedInt32Array = soa_state
	var stribe: PackedInt32Array = soa_tribe
	var sflags: PackedInt32Array = soa_flags
	var st_dead: int = Unit.State.DEAD
	var r2: float = radius * radius
	var center: Vector2i = hash_key(pos)
	var cell_r: int = int(ceil(radius / HASH_CELL_SIZE))
	var w: int = _grid_w
	var examined: int = 0
	for r in range(0, cell_r + 1):
		var z0: int = center.y - r
		var z1: int = center.y + r
		for kz in range(z0, z1 + 1):
			if kz < 0 or kz >= w:
				continue
			# Inner rows of the ring only contribute their left/right edge cells.
			var edge_row: bool = kz == z0 or kz == z1
			var row: int = kz * w
			var kx: int = center.x - r
			var x1: int = center.x + r
			while kx <= x1:
				if kx >= 0 and kx < w:
					var c: int = row + kx
					for k in range(_cell_start[c], _cell_start[c + 1]):
						var i: int = _cell_units[k]
						if i >= grid_n:
							continue   # stale slot (unregistered since the build)
						examined += 1
						if examined > max_examined:
							return result   # budget spent (possibly mid-bucket)
						if stribe[i] == enemy_of or sstate[i] == st_dead \
								or (sflags[i] & FLAG_TARGETABLE) == 0:
							continue
						var pi: Vector3 = pos_arr[i]
						var dx: float = pi.x - pos.x
						var dz: float = pi.z - pos.z
						if dx * dx + dz * dz <= r2:
							result.append(units[i])
							if result.size() >= max_count:
								return result
				if edge_row or r == 0:
					kx += 1
				else:
					kx = x1 if kx < x1 else x1 + 1
	# Units registered since the last grid build (same filters/budget).
	for e in _grid_extra:
		if e < _grid_built or e >= n:
			continue
		examined += 1
		if examined > max_examined:
			return result
		if stribe[e] == enemy_of or sstate[e] == st_dead \
				or (sflags[e] & FLAG_TARGETABLE) == 0:
			continue
		var pe: Vector3 = pos_arr[e]
		var dx: float = pe.x - pos.x
		var dz: float = pe.z - pos.z
		if dx * dx + dz * dz <= r2:
			result.append(units[e])
			if result.size() >= max_count:
				return result
	return result


func get_units_of_tribe(tribe_id: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in units:
		if unit.tribe_id == tribe_id:
			result.append(unit)
	return result
