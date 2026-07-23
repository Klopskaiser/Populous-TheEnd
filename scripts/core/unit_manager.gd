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
## Static per kind (set at register): drives the per-cell preacher bits that
## make the firewarriors' priest-hunting scan grid-maskable.
const FLAG_PREACHER: int = 16
## Riding an airship deck at altitude (event-mirrored like the crew flags):
## melee scans skip such targets without an is_airborne() object call. The
## THROWN half of is_airborne() is read from soa_state instead.
const FLAG_AIRBORNE: int = 32

var soa_pos: PackedVector3Array = PackedVector3Array()
var soa_state: PackedInt32Array = PackedInt32Array()
var soa_tribe: PackedInt32Array = PackedInt32Array()
var soa_flags: PackedInt32Array = PackedInt32Array()
var soa_veh_sep: PackedFloat32Array = PackedFloat32Array()
var soa_sep_mult: PackedFloat32Array = PackedFloat32Array()
## Separation passes spent tightly stacked (only the separation touches this).
var soa_overlap: PackedInt32Array = PackedInt32Array()

# --- Combat/move-kernel SoA (Stufe C2, plans/08e) --------------------------------
## Hold modes (soa_mode): what the kernel services while a unit is held.
const HOLD_MELEE: int = 0    # in melee range, cooldown running (strike = drop)
const HOLD_FIRE: int = 1     # firewarrior standing in (melee, fire] band
const HOLD_MOVE: int = 2     # State.MOVE, walking its planned path (C2.4)
const HOLD_CHASE: int = 3    # ATTACK approach on a planned path (melee unit)
const HOLD_CHASE_FIRE: int = 4   # ATTACK approach of a firewarrior (fire range)
const HOLD_WAIT: int = 5     # second-row waiter standing near its fight
const HOLD_CHASE_DIRECT: int = 6   # direct-step pursuit inside COMBAT_DIRECT_RANGE
const HOLD_CORPSE: int = 7   # DEAD, lying flat until the sink phase begins
const HOLD_PANIC: int = 8    # panicked flight hop (entry span parked in goal.x)
const HOLD_CAST: int = 9     # preacher standing and channeling (span in goal.x)
## Attack-target handle per unit: slot index of attack_target (-1 = none),
## mirrored at every attack_target write (Unit._sync_soa_target). Because
## unregister swap-removes slots, the handle alone could silently point at a
## DIFFERENT unit — soa_tgen stores the slot generation at write time and the
## kernel validates it against _slot_gen (one compare). A mismatch is never an
## error: the unit just drops to its object tick, which re-syncs the handle.
var soa_target: PackedInt32Array = PackedInt32Array()
var soa_tgen: PackedInt32Array = PackedInt32Array()
## Hold state: -1 = normal object tick; >= 0 = the unit is HELD by the kernel.
## For the stand modes (HOLD_MELEE/FIRE) the value is the remaining attack
## cooldown (written back into Unit._attack_cooldown on drop); the path modes
## use it as a plain held-marker. While held the unit's object tick is skipped
## entirely (tick_units); the kernel services it over the arrays and drops it
## back on any event: strike/shot due, target lost/dead/SIT/converted, out of
## band, waypoint reached, scan due, steep downhill (stumble zone). Entered
## only by Unit._enter_soa_hold*, cleared by the kernel and by
## Unit._clear_soa_hold (state change, knockback, burn, new path...).
var soa_hold: PackedFloat32Array = PackedFloat32Array()
var soa_mode: PackedInt32Array = PackedInt32Array()
## Scan-cadence timer of a held unit (-1 = none). Runs for holds whose object
## code scans on the 0.25-s cadence (fire stand: threat/priest reaction;
## aggressive move: engage-on-sight; firewarrior chase): the kernel drops the
## unit back exactly when its next scan is due, so reactions keep their window.
var soa_scan: PackedFloat32Array = PackedFloat32Array()
## Current waypoint of a path hold (HOLD_MOVE/CHASE*): the kernel walks toward
## it and drops the unit for the waypoint switch (object _advance_path).
var soa_wp: PackedVector3Array = PackedVector3Array()
## Chase modes: the TARGET's position at plan time. The object approach
## re-plans once its goal drifted > 1 m — the slot offset is constant per
## slot, so target drift == goal drift and the kernel checks it exactly.
var soa_goal: PackedVector3Array = PackedVector3Array()
## Walk speed (Unit.speed), captured at register — static per unit kind.
var soa_speed: PackedFloat32Array = PackedFloat32Array()
## Knockback-density accumulator of HELD units (fireball salvos): captured
## from Unit.knockback_accum at hold entry, decayed by the kernel while held,
## written back on drop/clear. Without this, every fireball splash locked its
## victims out of the kernel until the accumulator decayed on object ticks.
var soa_kb: PackedFloat32Array = PackedFloat32Array()
## Per-slot occupancy generation: bumped in unregister for both touched slots
## (the freed index and the vacated last slot); never shrinks. Stored handles
## whose generation no longer matches are stale and fail validation.
var _slot_gen: PackedInt32Array = PackedInt32Array()

# --- Spatial grid (CSR buckets, rebuilt once per tick) -------------------------
var _grid_w: int = 64                 # cells per axis (from terrain size)
var _grid_cells: int = 64 * 64
var _cell_count: PackedInt32Array = PackedInt32Array()   # scratch (doubles as fill cursor)
var _cell_start: PackedInt32Array = PackedInt32Array()   # size _grid_cells + 1
var _cell_units: PackedInt32Array = PackedInt32Array()   # unit indices, bucket-sorted
var _unit_cell: PackedInt32Array = PackedInt32Array()    # scratch: cell id per unit
## Per cell, over the LIVE, TARGETABLE units in it: bits 0-7 = tribes present
## (1 << tribe_id), bits 8-15 = tribes with a PREACHER present — the enemy-scan
## prefilters. A cell whose mask holds no foreign bit is skipped wholesale by
## get_enemy_candidates / get_nearest_enemy_preacher: deep inside the own army
## a scan then costs ~a handful of mask checks instead of examining hundreds
## of friends (measured 42-47 ms units-phase in the 4-army stress test).
var _cell_tribes: PackedInt32Array = PackedInt32Array()
## OR over all cell masks (same bit layout) — the global early-out: a query
## whose mask finds nothing here returns immediately (e.g. the priest query
## in a battle without preachers, or scans after a tribe was wiped out).
var _grid_tribes_all: int = 0
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
	_cell_tribes.resize(_grid_cells)


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
	tick_units(delta)
	tick(delta)


## The central unit loop (Stufe C2, plans/08e): first the flat combat kernel
## services every HELD unit over the SoA arrays (no object access), then the
## object ticks run for everyone else. Iterates a snapshot: an expiring corpse
## deregisters itself mid-loop via the corpse_expired signal (erasing from
## `units`), which would otherwise skip elements. Dead units still tick —
## their tick runs the corpse decay.
func tick_units(delta: float) -> void:
	_scan_cache_ready = true   # in-game loop -> the shared scan cache is live
	_run_combat_kernels(delta)   # fills _obj_tick with every non-held unit
	for unit in _obj_tick:
		if is_instance_valid(unit):
			unit.tick(delta)


## Units to object-tick this frame, collected by the kernel pass (everyone it
## does not hold). Snapshot semantics like the old units.duplicate() loop:
## units (un)registered mid-loop are picked up next frame / tick once more.
var _obj_tick: Array[Unit] = []


## Round-robin phase of the staggered facing refresh (held units barely turn —
## a full _face_point per tick is object-property cost for nothing).
var _kernel_tick: int = 0


## Flat combat/move kernel (Stufe C2): one pass over the SoA arrays servicing
## every held unit — target-handle validation (generation compare), liveness/
## tribe/targetable/SIT checks, per-mode distance band or waypoint step, the
## attack cooldown (stand modes) and the scan-cadence timer. Anything beyond
## "keep holding" drops the unit back to its object tick THIS tick: soa_hold
## resets to -1 and the decremented timers are written back (minus this tick's
## delta — the object tick re-applies it), so no time is ever counted twice.
## Path modes read the terrain heightmap directly (inline bilinear lerp) — a
## get_height object call per mover would eat most of the kernel's win.
func _run_combat_kernels(delta: float) -> void:
	_kernel_tick += 1
	var n: int = units.size()
	if n == 0:
		return
	var hold: PackedFloat32Array = soa_hold
	var mode_arr: PackedInt32Array = soa_mode
	var scan: PackedFloat32Array = soa_scan
	var tgt: PackedInt32Array = soa_target
	var tgen: PackedInt32Array = soa_tgen
	var gen: PackedInt32Array = _slot_gen
	var pos: PackedVector3Array = soa_pos
	var wp_arr: PackedVector3Array = soa_wp
	var goal_arr: PackedVector3Array = soa_goal
	var speed_arr: PackedFloat32Array = soa_speed
	var sstate: PackedInt32Array = soa_state
	var stribe: PackedInt32Array = soa_tribe
	var sflags: PackedInt32Array = soa_flags
	var st_attack: int = Unit.State.ATTACK
	var st_move: int = Unit.State.MOVE
	var st_dead: int = Unit.State.DEAD
	var st_sit: int = Unit.State.SIT
	var st_panic: int = Unit.State.PANIC
	var st_cast: int = Unit.State.CAST
	var melee_r2: float = Balance.MELEE_RANGE * Balance.MELEE_RANGE
	var fire_r2: float = Balance.FIREWARRIOR_FIRE_RANGE * Balance.FIREWARRIOR_FIRE_RANGE
	var direct_r2: float = Unit.COMBAT_DIRECT_RANGE * Unit.COMBAT_DIRECT_RANGE
	# Waiters ring around the group ANCHOR, which may trail the defender by up
	# to 2x the wait radius — the drop band must cover that, or the wait hold
	# never engages (the fine positioning keeps its 0.25-s scan cadence).
	var wait_r2: float = (Unit.MELEE_WAIT_RADIUS * 2.0 + 0.6) \
		* (Unit.MELEE_WAIT_RADIUS * 2.0 + 0.6)
	var arrive: float = Unit.ARRIVE_EPS
	var kb: PackedFloat32Array = soa_kb
	var kb_decay: float = Unit.KNOCKBACK_ACCUM_DECAY * delta
	var obj: Array[Unit] = _obj_tick
	obj.clear()
	# Terrain heightmap for the inline Y snap / slope probe of the path modes
	# (path holds are only entered with the manager's terrain present).
	var heights: PackedFloat32Array = terrain_data.heights if terrain_data != null \
		else PackedFloat32Array()
	var hverts: int = terrain_data.verts if terrain_data != null else 2
	var hmax: float = float(hverts - 1)
	# Flat walkability mirror for the direct-step pursuit (entry gated on a
	# present nav grid, so the empty fallback is never actually read).
	var walkable: PackedByteArray = nav_grid.walkable_map if nav_grid != null \
		else PackedByteArray()
	var nav_size: int = terrain_data.size if terrain_data != null else 1
	var phase: int = _kernel_tick & 7
	for i in range(n):
		var cd: float = hold[i]
		if cd < 0.0:
			obj.append(units[i])
			continue
		# Knockback-accumulator decay of held units (object _tick_knockback is
		# skipped while held; written back into the object field on drop).
		if kb[i] > 0.0:
			kb[i] = maxf(kb[i] - kb_decay, 0.0)
		var mode: int = mode_arr[i]
		var st_i: int = sstate[i]
		var drop: bool
		match mode:
			HOLD_MOVE:
				drop = st_i != st_move
			HOLD_CORPSE:
				drop = st_i != st_dead
			HOLD_PANIC:
				drop = st_i != st_panic
			HOLD_CAST:
				drop = st_i != st_cast
			_:
				drop = st_i != st_attack
		# The held-value timer: attack cooldown in the stand modes; remaining
		# lie time for a corpse; min(panic end, redirect) for a panicker;
		# min(scan, chant) for a channeling preacher. The path/wait modes use
		# it as a plain marker (approach and second row never tick the attack
		# cooldown — same as the object code).
		if mode <= HOLD_FIRE or mode >= HOLD_CORPSE:
			cd -= delta
			if cd <= 0.0:
				drop = true
		# Scan cadence (fire stand / aggressive move / firewarrior chase).
		var sc: float = scan[i]
		if sc >= 0.0 and not drop:
			sc -= delta
			if sc <= 0.0:
				drop = true
				# Clamp: the drop write-back below keys on >= 0. An expired
				# timer must reach the object as "due now", or the object's
				# scheduled scan never fires again.
				scan[i] = 0.0
			else:
				scan[i] = sc
		# Target validation for every mode with a combat target.
		var dx: float = 0.0
		var dz: float = 0.0
		var d2: float = 0.0
		if not drop and mode != HOLD_MOVE and mode <= HOLD_CHASE_DIRECT:
			var t: int = tgt[i]
			if t < 0 or t >= n or tgen[i] != gen[t]:
				drop = true   # stale handle (target unregistered / slot reused)
			else:
				var ts: int = sstate[t]
				if ts == st_dead or ts == st_sit or stribe[t] == stribe[i] \
						or (sflags[t] & FLAG_TARGETABLE) == 0:
					drop = true
				else:
					var pi0: Vector3 = pos[i]
					var pt: Vector3 = pos[t]
					dx = pt.x - pi0.x
					dz = pt.z - pi0.z
					d2 = dx * dx + dz * dz
					match mode:
						HOLD_MELEE:
							if d2 > melee_r2:
								drop = true
						HOLD_FIRE:
							if d2 <= melee_r2 or d2 > fire_r2:
								drop = true
						HOLD_WAIT:
							# Second row: stand near the fight; drifting past
							# the waiting ring hands fine control back.
							if d2 > wait_r2:
								drop = true
						HOLD_CHASE_DIRECT:
							# Arrived in melee -> strike branch; target fled
							# past the direct band -> the object plans a path.
							if d2 <= melee_r2 or d2 > direct_r2:
								drop = true
						HOLD_CHASE:
							# Close enough for the direct-step pursuit (or the
							# strike itself) -> object; target drifted from its
							# plan-time spot -> object re-plans the path.
							if d2 <= direct_r2:
								drop = true
							else:
								var g: Vector3 = goal_arr[i]
								var gx: float = pt.x - g.x
								var gz: float = pt.z - g.z
								if gx * gx + gz * gz > 1.0:
									drop = true
						HOLD_CHASE_FIRE:
							if d2 <= fire_r2:
								drop = true
							else:
								var gf: Vector3 = goal_arr[i]
								var gfx: float = pt.x - gf.x
								var gfz: float = pt.z - gf.z
								if gfx * gfx + gfz * gfz > 1.0:
									drop = true
					if not drop and (mode <= HOLD_FIRE or mode == HOLD_WAIT
							or mode == HOLD_CHASE_DIRECT) \
							and ((i + phase) & 7) == 0 and d2 > 0.000001:
						# Staggered facing refresh (~4x per second at 30 Hz);
						# the path modes walk, so their facing tracks the
						# waypoint below.
						units[i].facing = Vector3(dx, 0.0, dz).normalized()
		# Path step (walk toward the current waypoint; the waypoint SWITCH also
		# happens here — dropping per waypoint cost an object tick every ~7
		# ticks per mover; only the route end / stumble zone drop out). The
		# panic hop shares it (its one-point flee path just never switches).
		if not drop and ((mode >= HOLD_MOVE and mode <= HOLD_CHASE_FIRE)
				or mode == HOLD_PANIC):
			var pi: Vector3 = pos[i]
			var wp: Vector3 = wp_arr[i]
			var wx: float = wp.x - pi.x
			var wz: float = wp.z - pi.z
			var wd: float = sqrt(wx * wx + wz * wz)
			# Slope probe 0.6 m ahead: pi.y IS the terrain height here (snapped
			# every step), so one bilinear read suffices.
			var inv_d: float = 1.0 / maxf(wd, 0.001)
			var fx: float = clampf(pi.x + wx * inv_d * 0.6, 0.0, hmax)
			var fz: float = clampf(pi.z + wz * inv_d * 0.6, 0.0, hmax)
			var x0: int = mini(int(fx), hverts - 2)
			var z0: int = mini(int(fz), hverts - 2)
			var tx: float = fx - float(x0)
			var tz: float = fz - float(z0)
			var row: int = z0 * hverts + x0
			var h1: float = lerpf(
				lerpf(heights[row], heights[row + 1], tx),
				lerpf(heights[row + hverts], heights[row + hverts + 1], tx), tz)
			var slope: float = (h1 - pi.y) / 0.6
			if slope < -Unit.STEEP_ROLL_SLOPE:
				drop = true   # stumble zone: the object path rolls the dice
			else:
				var spd: float = speed_arr[i]
				if slope > 0.0:
					spd *= clampf(1.0 - slope * Unit.UPHILL_SLOWDOWN,
						Unit.MIN_SPEED_FACTOR, 1.0)
				# Clamped like move_toward: never overshoot the waypoint.
				var step: float = minf(spd * delta, wd)
				var nx: float = pi.x + wx * inv_d * step
				var nz: float = pi.z + wz * inv_d * step
				fx = clampf(nx, 0.0, hmax)
				fz = clampf(nz, 0.0, hmax)
				x0 = mini(int(fx), hverts - 2)
				z0 = mini(int(fz), hverts - 2)
				tx = fx - float(x0)
				tz = fz - float(z0)
				row = z0 * hverts + x0
				var ny: float = lerpf(
					lerpf(heights[row], heights[row + 1], tx),
					lerpf(heights[row + hverts], heights[row + hverts + 1], tx), tz)
				var u3: Unit = units[i]
				var moved: Vector3 = Vector3(nx, ny, nz)
				pos[i] = moved
				u3.position = moved
				if wd - step <= arrive:
					# Waypoint reached (same check as _advance_path): advance
					# the object's path cursor right here; only the route end
					# drops back (arrival / _on_path_finished / _clear_path).
					var upath: PackedVector3Array = u3._path
					var nidx: int = u3._path_index + 1
					if nidx >= upath.size():
						drop = true
					else:
						u3._path_index = nidx
						var nwp: Vector3 = upath[nidx]
						wp_arr[i] = nwp
						var fdx: float = nwp.x - nx
						var fdz: float = nwp.z - nz
						if fdx * fdx + fdz * fdz > 0.000001:
							u3.facing = Vector3(fdx, 0.0, fdz).normalized()
		# Direct-step pursuit (C2.4b): walk straight at the target's slot
		# position (target pos + the constant slot offset parked in soa_goal),
		# with the slope brake and the per-step walkability check of
		# _step_toward (an unwalkable step is skipped, never a drop — the
		# object code stands still there too).
		if not drop and mode == HOLD_CHASE_DIRECT:
			var pid: Vector3 = pos[i]
			var offs: Vector3 = goal_arr[i]
			var ptd: Vector3 = pos[tgt[i]]
			var ddx: float = ptd.x + offs.x - pid.x
			var ddz: float = ptd.z + offs.z - pid.z
			var dd: float = sqrt(ddx * ddx + ddz * ddz)
			if dd > 0.001:
				var inv_dd: float = 1.0 / dd
				var sfx: float = clampf(pid.x + ddx * inv_dd * 0.6, 0.0, hmax)
				var sfz: float = clampf(pid.z + ddz * inv_dd * 0.6, 0.0, hmax)
				var sx0: int = mini(int(sfx), hverts - 2)
				var sz0: int = mini(int(sfz), hverts - 2)
				var stx: float = sfx - float(sx0)
				var stz: float = sfz - float(sz0)
				var srow: int = sz0 * hverts + sx0
				var sh1: float = lerpf(
					lerpf(heights[srow], heights[srow + 1], stx),
					lerpf(heights[srow + hverts], heights[srow + hverts + 1], stx), stz)
				var sslope: float = (sh1 - pid.y) / 0.6
				if sslope < -Unit.STEEP_ROLL_SLOPE:
					drop = true   # stumble zone: the object path rolls the dice
				else:
					var sspd: float = speed_arr[i]
					if sslope > 0.0:
						sspd *= clampf(1.0 - sslope * Unit.UPHILL_SLOWDOWN,
							Unit.MIN_SPEED_FACTOR, 1.0)
					var sstep: float = minf(sspd * delta, dd)
					var snx: float = pid.x + ddx * inv_dd * sstep
					var snz: float = pid.z + ddz * inv_dd * sstep
					var cellw: int = clampi(int(snz), 0, nav_size - 1) * nav_size \
						+ clampi(int(snx), 0, nav_size - 1)
					if walkable[cellw] != 0:
						sfx = clampf(snx, 0.0, hmax)
						sfz = clampf(snz, 0.0, hmax)
						sx0 = mini(int(sfx), hverts - 2)
						sz0 = mini(int(sfz), hverts - 2)
						stx = sfx - float(sx0)
						stz = sfz - float(sz0)
						srow = sz0 * hverts + sx0
						var sny: float = lerpf(
							lerpf(heights[srow], heights[srow + 1], stx),
							lerpf(heights[srow + hverts], heights[srow + hverts + 1], stx), stz)
						var smoved: Vector3 = Vector3(snx, sny, snz)
						pos[i] = smoved
						units[i].position = smoved
		if drop:
			hold[i] = -1.0
			var u: Unit = units[i]
			if mode <= HOLD_FIRE:
				u._attack_cooldown = cd + delta
			elif mode == HOLD_CORPSE:
				# Held time went into cd; the object tick re-applies its delta.
				u._corpse_timer = Unit.CORPSE_DURATION - cd - delta
			elif mode == HOLD_PANIC:
				# goal.x parked the entry value of min(panic, redirect).
				var elapsed: float = goal_arr[i].x - cd - delta
				u._panic_time -= elapsed
				u._panic_redirect -= elapsed
			elif mode == HOLD_CAST:
				# goal.x parked the entry value of min(scan, chant).
				var celapsed: float = goal_arr[i].x - cd - delta
				u._target_search_timer -= celapsed
				u._on_hold_elapsed(celapsed)
			if scan[i] >= 0.0:
				u._target_search_timer = scan[i] + delta
				scan[i] = -1.0
			u.knockback_accum = kb[i]
			obj.append(u)
		elif mode <= HOLD_FIRE or mode >= HOLD_CORPSE:
			hold[i] = cd


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
	_sim_tick += 1   # drives the scan-cache TTL (in-game AND manager tests)
	if (_sim_tick & 511) == 0:
		_scan_cache.clear()   # periodic full drop (dead battle areas)
	var n: int = units.size()
	_grid_built = n
	_grid_extra.clear()
	if _cell_start.size() != _grid_cells + 1:   # setup() not called (bare tests)
		_cell_count.resize(_grid_cells)
		_cell_start.resize(_grid_cells + 1)
		_cell_tribes.resize(_grid_cells)
	if _unit_cell.size() < n:
		_unit_cell.resize(n)
		_cell_units.resize(n)
	_cell_count.fill(0)
	_cell_tribes.fill(0)
	var pos: PackedVector3Array = soa_pos
	var sstate: PackedInt32Array = soa_state
	var stribe: PackedInt32Array = soa_tribe
	var sflags: PackedInt32Array = soa_flags
	var st_dead: int = Unit.State.DEAD
	var inv: float = 1.0 / HASH_CELL_SIZE
	var w: int = _grid_w
	var top: int = w - 1
	var all_bits: int = 0
	for i in range(n):
		var p: Vector3 = pos[i]
		var c: int = clampi(int(p.z * inv), 0, top) * w \
			+ clampi(int(p.x * inv), 0, top)
		_unit_cell[i] = c
		_cell_count[c] += 1
		# Scan-prefilter bits: only live, targetable units make a cell
		# "interesting" for enemy scans (corpses/reserves are never targets);
		# preachers additionally set their tribe's priest bit (bits 8-15).
		var fl: int = sflags[i]
		if sstate[i] != st_dead and (fl & FLAG_TARGETABLE) != 0:
			var tb: int = stribe[i] & 7
			var bit: int = 1 << tb
			if fl & FLAG_PREACHER:
				bit |= 1 << (tb + 8)
			_cell_tribes[c] = _cell_tribes[c] | bit
			all_bits |= bit
	_grid_tribes_all = all_bits
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


var _group_prune_phase: int = 0


func _apply_combat_groups(delta: float) -> void:
	if combat_groups.is_empty():
		return
	# Liveness + anchor follow every tick; the full prune sweep is staggered
	# (1/8 of the groups per tick — see CombatGroup.is_alive_light).
	_group_prune_phase = (_group_prune_phase + 1) & 7
	var gi: int = 0
	var kept: Array = []
	var anchor_hash: Dictionary = {}
	for g in combat_groups:
		gi += 1
		var alive: bool = g.is_alive() if (gi & 7) == _group_prune_phase \
			else g.is_alive_light()
		if not alive:
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
		var ny: float = defender.position.y
		if terrain_data != null:
			ny = terrain_data.get_height(nx, nz)
		defender.position = Vector3(nx, ny, nz)
		# SoA mirror (C1 writer audit gap, found in C2): a defender standing in
		# melee does not move on its own — without this its soa_pos went stale
		# under the group push until its next own movement.
		defender._sync_soa_pos()
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
		if unit.state != Unit.State.IDLE or not unit.joins_idle_groups:
			continue   # vehicles never regroup (a parked ram must not drive off)
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
		elif other.state == Unit.State.IDLE and other.joins_idle_groups:
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
	if not unit.joins_idle_groups:
		return   # vehicles: no 6-pack membership (all entry points gate here)
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
	soa_target.append(-1)
	soa_tgen.append(0)
	soa_hold.append(-1.0)
	soa_mode.append(HOLD_MELEE)
	soa_scan.append(-1.0)
	soa_wp.append(Vector3.ZERO)
	soa_goal.append(Vector3.ZERO)
	soa_speed.append(unit.speed)
	soa_kb.append(0.0)
	if _slot_gen.size() <= unit._idx:
		_slot_gen.resize(unit._idx + 1)   # zero-filled; unregister bumps
	unit._bind_soa(self)
	_grid_extra.append(unit._idx)   # visible to queries before the next build
	# A mass spawn (stress test: 4000 registers before the first tick) would
	# otherwise leave EVERY unit in the linear extra list — each enemy scan
	# then walked it wholesale (~0.6 ms per scan, one 600+ ms spawn tick).
	if _grid_extra.size() > 64:
		_rebuild_grid()
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
		soa_target[index] = soa_target[last]
		soa_tgen[index] = soa_tgen[last]
		soa_hold[index] = soa_hold[last]
		soa_mode[index] = soa_mode[last]
		soa_scan[index] = soa_scan[last]
		soa_wp[index] = soa_wp[last]
		soa_goal[index] = soa_goal[last]
		soa_speed[index] = soa_speed[last]
		soa_kb[index] = soa_kb[last]
		soa_pos.resize(last)
		soa_state.resize(last)
		soa_tribe.resize(last)
		soa_flags.resize(last)
		soa_veh_sep.resize(last)
		soa_sep_mult.resize(last)
		soa_overlap.resize(last)
		soa_target.resize(last)
		soa_tgen.resize(last)
		soa_hold.resize(last)
		soa_mode.resize(last)
		soa_scan.resize(last)
		soa_wp.resize(last)
		soa_goal.resize(last)
		soa_speed.resize(last)
		soa_kb.resize(last)
		# Both touched slots change occupancy: stored (index, generation)
		# handles onto the removed unit AND onto the moved unit go stale — the
		# kernel drops those holders to their object tick, which re-syncs.
		_slot_gen[index] += 1
		_slot_gen[last] += 1
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
	# Prefilter: a cell whose tribe mask (low byte) holds no bit besides the
	# scanner's own is skipped without touching its units (see _cell_tribes).
	var enemy_mask: int = 0xFF & ~(1 << (enemy_of & 7))
	if (_grid_tribes_all & enemy_mask) == 0 and _grid_extra.is_empty():
		return result   # no live targetable enemy anywhere (endgame)
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
				if kx >= 0 and kx < w and (_cell_tribes[row + kx] & enemy_mask) != 0:
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


# --- Cell scan cache (Stufe C3 / plans 08e Fortsetzung) ---------------------------

## The block-level enemy-candidate cache: combat scans in a mass battle run on
## the 0.25-s cadence but each paid a full ring collection (examined budget up
## to 300 array checks). Scanners inside the same 2x2-cell block hunting the
## same enemy tribe share ONE collection for SCAN_CACHE_TTL_TICKS instead: the
## cache stores candidate slot indices + generations collected from the BLOCK
## CENTRE with an enlarged radius; get_enemy_candidates_cached then applies
## the caller's EXACT radius and revalidates liveness/tribe/targetable per
## call (stale/swap-removed slots fail the generation check) — aggro ranges
## and target priorities stay exact, only the candidate-subset noise under the
## examined budget differs (same approximation class as the budget itself).
const SCAN_CACHE_TTL_TICKS: int = 6
## Covers the largest cached caller radius (firewarrior aggro 13) plus the
## worst scanner offset from its block centre (half block diagonal ~5.7).
const SCAN_CACHE_RADIUS: float = 19.0
## Small bucket for the common melee-aggro scans (radius <= 8): 8 + ~5.7.
const SCAN_CACHE_RADIUS_SMALL: float = 13.7
const SCAN_CACHE_MAX: int = 40

var _scan_cache: Dictionary = {}
## Sim-tick counter driving the cache TTL; bumped by _rebuild_grid (runs both
## in-game and in manager-driven tests). Consumers fall back to the uncached
## query until the first tick_units ran (bare tests keep exact behaviour).
var _sim_tick: int = 0
var _scan_cache_ready: bool = false
## Scan-cache telemetry (pure counters, benchmark output only).
static var dbg_scan_hits: int = 0
static var dbg_scan_builds: int = 0
static var dbg_scan_uncached: int = 0


## Index variant for the hot combat scans (same result contract as
## get_enemy_candidates: living targetable enemies of `enemy_of` within
## `radius`, capped at SCAN_MAX_CANDIDATES): callers filter and SCORE over the
## SoA arrays and only fetch the objects that survive — the per-candidate
## property reads (position/state/is_airborne) were the measured bulk of a
## scan, not the collection. Callers keep their own SIT/airborne/unreachable
## filtering and scoring.
func get_enemy_candidate_indices(pos: Vector3, radius: float,
		enemy_of: int) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	# Density gate (one mask read): with enemies present in the scanner's OWN
	# grid cell the direct masked collection is dirt cheap — it fills its
	# candidate cap within the first ring (measured ~+2-5 ms when the tightly
	# interleaved combat benchmark went through the cache). The shared cache
	# only pays off where enemies are SPARSE in scan range (deep inside a
	# friendly blob, where a direct scan burns its full examined budget).
	var dense: bool = false
	if _grid_w > 0 and _cell_tribes.size() == _grid_cells:
		var oc: int = clampi(int(pos.z / HASH_CELL_SIZE), 0, _grid_w - 1) * _grid_w \
			+ clampi(int(pos.x / HASH_CELL_SIZE), 0, _grid_w - 1)
		dense = (_cell_tribes[oc] & (0xFF & ~(1 << (enemy_of & 7)))) != 0
	if dense or not _scan_cache_ready or radius > SCAN_CACHE_RADIUS - 5.7:
		dbg_scan_uncached += 1
		for u in get_enemy_candidates(pos, radius, enemy_of, Unit.SCAN_MAX_CANDIDATES):
			if u._idx >= 0:
				result.append(u._idx)
		return result
	# Radius bucket: small scans (melee aggro 8 and below) must not pay the
	# full firewarrior-radius collection on every cache MISS — in a scattered
	# fight the hit rate is low and the build cost dominates (measured +7 ms
	# on the spread-out combat benchmark with one shared 19 m bucket).
	var bucket_r: float = SCAN_CACHE_RADIUS_SMALL if radius <= 8.0 else SCAN_CACHE_RADIUS
	var bw: float = HASH_CELL_SIZE * 2.0
	var bx: int = int(pos.x / bw)
	var bz: int = int(pos.z / bw)
	var key: int = ((bz * 4096 + bx) * 8 + (enemy_of & 7)) * 2 \
		+ (0 if bucket_r == SCAN_CACHE_RADIUS_SMALL else 1)
	var entry: Array = _scan_cache.get(key, [])
	if entry.is_empty() or _sim_tick >= int(entry[0]):
		dbg_scan_builds += 1
		var center: Vector3 = Vector3(
			(float(bx) + 0.5) * bw, 0.0, (float(bz) + 0.5) * bw)
		var found: Array[Unit] = get_enemy_candidates(
			center, bucket_r, enemy_of, SCAN_CACHE_MAX)
		var idxs: PackedInt32Array = PackedInt32Array()
		var gens: PackedInt32Array = PackedInt32Array()
		for u in found:
			var ui: int = u._idx
			if ui >= 0:
				idxs.append(ui)
				gens.append(_slot_gen[ui])
		entry = [_sim_tick + SCAN_CACHE_TTL_TICKS, idxs, gens]
		_scan_cache[key] = entry
	else:
		dbg_scan_hits += 1
	# Revalidate + exact-radius filter over the shared candidate list; capped
	# like the direct query so the callers' scoring cost stays bounded.
	var idx_list: PackedInt32Array = entry[1]
	var gen_list: PackedInt32Array = entry[2]
	var n: int = units.size()
	var r2: float = radius * radius
	var st_dead: int = Unit.State.DEAD
	for k in range(idx_list.size()):
		var i: int = idx_list[k]
		if i >= n or gen_list[k] != _slot_gen[i]:
			continue   # slot re-used since the collection
		if soa_tribe[i] == enemy_of or soa_state[i] == st_dead \
				or (soa_flags[i] & FLAG_TARGETABLE) == 0:
			continue
		var p: Vector3 = soa_pos[i]
		var ddx: float = p.x - pos.x
		var ddz: float = p.z - pos.z
		if ddx * ddx + ddz * ddz <= r2:
			result.append(i)
			if result.size() >= Unit.SCAN_MAX_CANDIDATES:
				break
	return result


## Object-list convenience wrapper over get_enemy_candidate_indices (callers
## that act on every candidate anyway, e.g. the preacher's pacify sweep).
func get_enemy_candidates_cached(pos: Vector3, radius: float,
		enemy_of: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for i in get_enemy_candidate_indices(pos, radius, enemy_of):
		result.append(units[i])
	return result


## Nearest living, targetable enemy PREACHER within `radius` around `pos`
## (firewarrior priest-hunting, phase 8.2). Grid-masked via the per-cell
## priest bits: with no enemy preacher nearby the query is ~a handful of mask
## checks — the old per-tribe list loop cost ~0.25 ms per scan in the 4-army
## stress test (300 preacher objects examined per call).
func get_nearest_enemy_preacher(pos: Vector3, radius: float, enemy_of: int) -> Unit:
	var n: int = units.size()
	var grid_n: int = mini(_grid_built, n)
	var pos_arr: PackedVector3Array = soa_pos
	var sstate: PackedInt32Array = soa_state
	var stribe: PackedInt32Array = soa_tribe
	var sflags: PackedInt32Array = soa_flags
	var st_dead: int = Unit.State.DEAD
	var want: int = FLAG_PREACHER | FLAG_TARGETABLE
	var priest_mask: int = (0xFF & ~(1 << (enemy_of & 7))) << 8
	if (_grid_tribes_all & priest_mask) == 0 and _grid_extra.is_empty():
		return null   # no enemy preacher anywhere (e.g. pure-warrior battles)
	var best: Unit = null
	var best_d2: float = radius * radius
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
			if (_cell_tribes[c] & priest_mask) == 0:
				continue
			for k in range(_cell_start[c], _cell_start[c + 1]):
				var i: int = _cell_units[k]
				if i >= grid_n:
					continue   # stale slot (unregistered since the grid build)
				if (sflags[i] & want) != want or stribe[i] == enemy_of \
						or sstate[i] == st_dead:
					continue
				var pi: Vector3 = pos_arr[i]
				var dx: float = pi.x - pos.x
				var dz: float = pi.z - pos.z
				var d2: float = dx * dx + dz * dz
				if d2 <= best_d2:
					best_d2 = d2
					best = units[i]
	# Units registered since the last grid build (bounded: register rebuilds
	# the grid once the extra list exceeds its threshold).
	for e in _grid_extra:
		if e < _grid_built or e >= n:
			continue
		if (sflags[e] & want) != want or stribe[e] == enemy_of \
				or sstate[e] == st_dead:
			continue
		var pe: Vector3 = pos_arr[e]
		var dx: float = pe.x - pos.x
		var dz: float = pe.z - pos.z
		var d2: float = dx * dx + dz * dz
		if d2 <= best_d2:
			best_d2 = d2
			best = units[e]
	return best


func get_units_of_tribe(tribe_id: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in units:
		if unit.tribe_id == tribe_id:
			result.append(unit)
	return result
