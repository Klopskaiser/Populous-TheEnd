class_name Building extends Node3D

## Base class for all buildings. Construction happens in two phases, driven by
## worker braves (max MAX_WORKERS per site):
##   1. FLATTEN: the footprint terrain is levelled to flatten_target (workers
##      hop on their claimed cell; parallel cells = faster). Meanwhile other
##      workers fell nearby trees and pile the wood at the entrance.
##   2. BUILD: build_progress grows (capped by the delivered-wood fraction);
##      the building can only be completed once all wood has arrived. Wood
##      piles near the entrance are absorbed automatically.
## Buildings have an entrance side (orientation 0..3 = S/E/N/W) used for the
## rally point, unit spawns and wood delivery.
##
## Gameplay logic lives in tick(delta) (driven by the BuildingManager) so
## tests can tick manually. Uses local `position` like Unit.

signal construction_finished(building: Building)
signal destroyed(building: Building)

const MAX_WORKERS: int = 10
## Piles within this radius of the entrance are absorbed into the site.
const ABSORB_RADIUS: float = 5.0
const ABSORB_INTERVAL: float = 0.5
## Terrain/nav updates are batched and flushed at this interval.
const FLUSH_INTERVAL: float = 0.25
## Once construction really starts (>=1 wood built in), units standing on the
## footprint are pushed off at this interval so the rising building never buries
## them (phase 7i bugfix).
const CLEAR_INTERVAL: float = 0.5
const FLATTEN_EPS: float = 0.02
## When no wood source is reachable the site stalls; after this interval it
## becomes available for workers again (they re-check for new wood/trees).
const WOOD_RECHECK_INTERVAL: float = 30.0

# --- Destruction stages & repair (phase 6) ------------------------------------
## Damage fraction per destruction stage: stage 1 at >= 30%, 2 at >= 60%,
## 3 at >= 90%, 4 (destroyed) at 100%. From stage 1 on the building is
## unusable (no production, no capacity) until repaired.
const STAGE_DAMAGE: float = Balance.BUILDING_STAGE_DAMAGE
## Construction-site HP (bug backlog #2): a site's HP scale with the
## delivered-wood fraction, capped at this fraction of the full HP (3 of the
## 4 destruction stages — a site is never as sturdy as the finished building).
const SITE_HP_CAP_FRACTION: float = 0.75
## HP of a site with nothing built in yet (one hit fells the bare plot).
const SITE_MIN_HP: int = 1
## Destroyed buildings sink into the ground (visual only), then free themselves.
const SINK_DURATION: float = 2.0
const SINK_DEPTH: float = 5.0
## One slow rocking lean while the wreck goes under (radians / Hz) — purely
## visual, so the building settles instead of dropping like a lift.
const SINK_TILT: float = 0.14
const SINK_TILT_HZ: float = 0.8
## Sideways drift of a flooded wreck sliding into the water (7c integrity rule).
const SLIDE_SPEED: float = 1.6
## A building that survived a terrain morph levels its foundation back at
## this rate (metres per second per vertex) — the crooked ground "settles".
const FOUNDATION_SMOOTH_RATE: float = 0.3
## Placeholder damage visual: dark "broken out" chunks, 2 shown per stage.
const MAX_DAMAGE_HOLES: int = 6

# --- Building assault (phase 7g) ----------------------------------------------
## Damage source tags for take_damage: ranged fire (firewarrior) that reaches
## stage 1 on its own HURTS the ejected occupants (EJECT_RANGED_DAMAGE — weak
## units die in the tumble), everything else (spells, melee demolition) ejects
## them alive and unhurt.
const DMG_GENERIC: int = 0
const DMG_RANGED: int = 1
## Max melee raiders that can storm this building at once (the watchtower in
## phase 7h overrides this with 5). Extras wait outside like a full melee ring.
const MAX_MELEE_RAIDERS: int = Balance.MAX_MELEE_RAIDERS
## Demolition damage per raider per second: more raiders = faster teardown.
const RAID_DPS_PER_RAIDER: float = Balance.RAID_DPS_PER_RAIDER
## Wobble visual while raiders demolish (± this rotation, HZ below).
const RAID_WOBBLE_AMPLITUDE: float = 0.035   # ~2 degrees
const RAID_WOBBLE_HZ: float = 0.8
## A melee storm can only demolish once the entrance is clear of live enemies
## (phase 7g nachbesserung): defenders/ejected occupants within this radius of
## the entrance pull the demolishers back out to fight (SIT = in conversion is
## not counted). Makes buildings meaningfully harder to raze by melee.
const ENTRANCE_CLEAR_RADIUS: float = 6.0

var tribe_id: int = 0
var tribe: Tribe = null
var max_health: int = 300
var health: int = 300
var wood_cost: int = 20
var footprint: Vector2i = Vector2i(4, 4)   # cells
var cell: Vector2i = Vector2i.ZERO         # top-left footprint cell
## Entrance side: 0 = south (+z), 1 = east (+x), 2 = north (-z), 3 = west (-x).
var orientation: int = 0
var rally_point: Vector3 = Vector3.ZERO
var under_construction: bool = true
var build_progress: float = 0.0            # 0..1
var wood_delivered: int = 0
## Current site HP ceiling (grows with delivered wood); 0 once finished /
## for pre-built buildings (they keep the plain max_health model).
var _site_hp_cap: int = 0
var foundation_done: bool = false
var flatten_target: float = 0.0
## True while the site waits for wood with no source in reach: workers left
## and recruiting pauses until the re-check timer expires (or wood arrives).
var wood_stalled: bool = false
## Wood delivered for repairs and not yet consumed (absorbed from piles near
## the entrance while the building is damaged).
var repair_wood: int = 0
## Repair HP already paid for by consumed wood but not yet worked off.
var _repair_hp_pool: float = 0.0
## Sub-HP repair work accumulator.
var _repair_hp_frac: float = 0.0
var _destroyed: bool = false
var _sink_time: float = 0.0
## Destruction-visual variants (7c terrain integrity): burst wrecks vanish
## instantly (debris replaces the model), flooded wrecks slide sideways.
var _vanish_on_destroy: bool = false
var _slide_dir: Vector3 = Vector3.ZERO
## Set by the terrain-integrity check when the foundation got bent but held:
## tick() then levels the footprint back until it is flat again.
var _foundation_disturbed: bool = false
var _damage_holes: Array[MeshInstance3D] = []
## Per-building sound throttle: sfx name -> last play ms (see _play_sfx).
var _sfx_last_ms: Dictionary = {}
var _visual_stage: int = -1
## Custom-model texture-swap state (only used when _has_custom_model). The
## loaded .glb's texturable surfaces (flags excluded); the last applied
## build-stage index; a small cache of stage/build textures by relative path.
var _model_surfaces: Array[MeshInstance3D] = []
var _build_visual_stage: int = -1
var _stage_tex_cache: Dictionary = {}
## Worker braves currently assigned to this construction site.
var workers: Array[Brave] = []

## Melee raiders currently INSIDE demolishing (phase 7g). Untyped like the
## trainee/crew registries: entries are removed from the world and may be freed.
var raiders: Array = []
var _raid_damage_frac: float = 0.0
## Wobble animation clock while raiders are inside (in-game _process only).
var _wobble_time: float = 0.0
## True once the storm ejected this building's occupants (idempotent guard so
## they are only thrown out once per storm).
var _storm_started: bool = false

## Lava wrecks buildings: accumulated seconds of ongoing lava contact (surge/
## flow) and the grace window left before the accumulator resets — only
## SUSTAINED contact deals destruction stages (see add_lava_contact()).
var _lava_contact_accum: float = 0.0
var _lava_contact_grace: float = 0.0

## Selection state (buildings are selectable: left-click; right-click then sets
## the rally point). `hovered` is set by the SelectionManager on mouse-over.
var selected: bool = false
var hovered: bool = false

## Player-facing production switch (crew tab): producers (hut, training
## buildings, forester, workshop) freeze their production while paused; crew
## handling and growth maintenance keep running.
var paused: bool = false

## Height of the info overlay (production bar) above the building origin.
const OVERLAY_Y: float = 4.4

## Injected by BuildingManager.place() (or directly by tests).
var terrain_data: TerrainData = null
var nav_grid: NavGrid = null
var unit_manager: UnitManager = null
var wood_pile_manager: WoodPileManager = null

var _mesh_root: Node3D = null
## True when a user-provided .glb (assets/models/buildings/<asset_kind>.glb)
## was loaded in _create_visuals — subclasses then skip their placeholder meshes.
var _has_custom_model: bool = false
var _selection_ring: MeshInstance3D = null
var _rally_marker: Node3D = null
var _overlay_sprite: Sprite3D = null
var _overlay_progress: float = -1.0
## Which variant of the bar is currently drawn (BAR_* below), -1 = none.
var _overlay_mode: int = -1
## Crew-pip overlay (world-space, below the production bar), shown on
## select/hover for every building that reports a crew capacity (all except the
## watchtower — see crew_display_capacity).
var _crew_sprite: Sprite3D = null
var _crew_shown: int = -1
var _crew_shown_cap: int = -1
var _flatten_remaining: Dictionary[Vector2i, bool] = {}
var _flatten_claims: Dictionary[Vector2i, int] = {}
## Seconds each still-open flatten cell has gone without any grading progress
## (10i, F3). Accounted once per second over the open cells, not per tick.
var _flatten_stall: Dictionary[Vector2i, float] = {}
var _flatten_stall_tick: float = 0.0
var _dirty: Rect2i = Rect2i()
var _flush_timer: float = FLUSH_INTERVAL
var _absorb_timer: float = ABSORB_INTERVAL
var _clear_timer: float = 0.0   # footprint-clear throttle (phase 7i)
var _wood_recheck_timer: float = 0.0

# --- Demolition (phase 10d) ---------------------------------------------------
## True while the player's demolition order is being worked off: the building is
## unusable, build_progress runs BACKWARDS and the refund is paid out in
## portions as it drops. Never reset except by destroy() — the order is final.
var demolishing: bool = false
## build_progress when the demolition started (reference for the progress bar).
var _demolish_start_progress: float = 0.0
var _demolish_refund_total: int = 0
var _demolish_refund_paid: int = 0

# --- Upgrade (phase 10f) ------------------------------------------------------
# Only the hut upgrades today, but the flag lives in the base class for the same
# reason `demolishing` does: Brave._job_active/_job_wants_wood, tick()'s wood
# absorption, the overlay bar and the SelectionManager all have to ask about it
# without knowing the subclass. The behaviour itself is subclass-supplied through
# the virtuals below.
#
## True while an upgrade is being worked off: the crew is out (so the building
## produces nothing) but it deliberately stays `is_usable()` — see Hut.
var upgrading: bool = false
## Upgrade wood delivered and not yet built in (absorbed from piles near the
## entrance, exactly like repair_wood).
var upgrade_wood: int = 0
## Seconds without any upgrade progress: the whole crew can die on the way to a
## tree, and nobody else is recruited for upgrades. Times out into a cancel.
var _upgrade_stall_timer: float = 0.0

# --- Construction decay (phase 10d) -------------------------------------------
## Last observed progress signature (build_progress, wood_delivered, open
## flatten cells) and how long it has been unchanged. A site that makes no
## progress at all for Balance.CONSTRUCTION_STALL_TIMEOUT decays.
var _decay_signature: Vector3 = Vector3(-1.0, -1.0, -1.0)
var _decay_timer: float = 0.0
## Seconds the site has spent at build_progress == 0 (10i, F7). Independent of
## the signature timer above, which partial bookings keep resetting.
var _no_start_timer: float = 0.0

## Island label of the worker approach point, cached against the NavGrid's
## change_version (see approach_island()).
var _approach_island: int = -1
var _approach_island_version: int = -1

# --- Delivery anchor (phase 10i, F1) ------------------------------------------
## PERSISTED worker approach point. It used to be recomputed on every call, and
## because the ring search returns a perimeter cell, it JUMPED whenever anything
## nearby changed walkability (every graded cell does). On a 4x4 footprint
## opposite ring-1 corners are ~7 m apart, on an 8x8 ~14 m — far outside
## ABSORB_RADIUS. Wood then landed outside the absorption radius, wood_delivered
## stayed 0, wants_more_wood() stayed true forever and the workers hammered away
## at a site whose progress_cap() was 0: the reported stuck site with the
## ever-growing wood pile. Five consumers share this anchor (_absorb_piles,
## wood_incoming, the braves' delivery target, _refund_wood, approach_island),
## so it has to be ONE stable point.
var _delivery_point: Vector3 = Vector3.INF
## NavGrid.change_version the cached point was last validated against.
var _delivery_point_version: int = -1


## German display name, overridden by subclasses (UI language is German).
func display_name() -> String:
	return "Gebäude"


## Housing capacity this building contributes (Hut overrides this).
func housing_capacity() -> int:
	return 0


func footprint_rect() -> Rect2i:
	return Rect2i(cell, footprint)


## Flat world-space distance from `flat` (x/z) to the nearest point of the
## footprint rectangle — 0 inside it. Used by the lava contact checks.
func footprint_distance_to(flat: Vector2) -> float:
	var origin: Vector2 = Vector2(cell) * TerrainData.CELL_SIZE
	var size: Vector2 = Vector2(footprint) * TerrainData.CELL_SIZE
	var nearest: Vector2 = Vector2(
		clampf(flat.x, origin.x, origin.x + size.x),
		clampf(flat.y, origin.y, origin.y + size.y))
	return nearest.distance_to(flat)


## World-space centre of the footprint, Y from the terrain.
func center_world() -> Vector3:
	var wx: float = (float(cell.x) + float(footprint.x) * 0.5) * TerrainData.CELL_SIZE
	var wz: float = (float(cell.y) + float(footprint.y) * 0.5) * TerrainData.CELL_SIZE
	var wy: float = terrain_data.get_height(wx, wz) if terrain_data != null else 0.0
	return Vector3(wx, wy, wz)


## Cell just outside the footprint in the middle of the entrance side.
func entrance_cell() -> Vector2i:
	return entrance_cell_for(cell, footprint, orientation)


## Rings searched outward from the footprint for a walkable approach cell — the
## bound edge_spawn_position() has always used.
const APPROACH_SEARCH_RINGS: int = 3


## Entrance cell of a footprint at `cell` with this `orientation` (0..3 = S/E/N/W;
## cell.y IS the z axis). STATIC so the AI can ask it for a plot where no building
## stands yet (10g).
static func entrance_cell_for(cell: Vector2i, footprint: Vector2i,
		orientation: int) -> Vector2i:
	var half_x: int = footprint.x / 2
	var half_y: int = footprint.y / 2
	match orientation:
		0:
			return cell + Vector2i(half_x, footprint.y)
		1:
			return cell + Vector2i(footprint.x, half_y)
		2:
			return cell + Vector2i(half_x, -1)
		_:
			return cell + Vector2i(-1, half_y)


## Cell workers actually stand on to serve a building with this footprint,
## orientation and origin cell: the entrance cell when walkable, otherwise the
## nearest walkable perimeter cell within APPROACH_SEARCH_RINGS.
## (-1, -1) = nobody can ever serve this plot.
##
## STATIC on purpose (10g): the AI has to ask the question for a plot where no
## building exists yet, and BOTH paths must agree on the cell. Before this, the
## plot sweep judged reachability at the plot CENTRE (an A* from the base anchor)
## while _accept_or_scrap_site judged the APPROACH point (approach_island) — two
## different questions, so the AI placed sites it then demolished on the spot.
static func approach_cell_for(nav: NavGrid, cell: Vector2i, footprint: Vector2i,
		orientation: int) -> Vector2i:
	if nav == null:
		return entrance_cell_for(cell, footprint, orientation)
	var entrance: Vector2i = entrance_cell_for(cell, footprint, orientation)
	if nav.is_cell_walkable(entrance):
		return entrance
	var base: Rect2i = Rect2i(cell, footprint)
	for grow in range(1, APPROACH_SEARCH_RINGS + 1):
		var rect: Rect2i = base.grow(grow)
		var inner: Rect2i = base.grow(grow - 1)
		# The NEAREST candidate of this ring, not the first one the raster hits
		# (10i, F2). The plain loop order is north-west biased, so two calls with
		# slightly different walkability could pick cells on OPPOSITE sides of the
		# footprint — ~14 m apart on an 8x8. Scoring by distance to the entrance
		# also makes the point plausible: workers serve the door side.
		var best: Vector2i = Vector2i(-1, -1)
		var best_d: float = INF
		for z in range(rect.position.y, rect.position.y + rect.size.y):
			for x in range(rect.position.x, rect.position.x + rect.size.x):
				var c: Vector2i = Vector2i(x, z)
				if inner.has_point(c):
					continue
				if not nav.is_cell_walkable(c):
					continue
				var d: float = Vector2(c - entrance).length_squared()
				if d < best_d:
					best_d = d
					best = c
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


func entrance_world() -> Vector3:
	var c: Vector2i = entrance_cell()
	var wx: float = (float(c.x) + 0.5) * TerrainData.CELL_SIZE
	var wz: float = (float(c.y) + 0.5) * TerrainData.CELL_SIZE
	var wy: float = terrain_data.get_height(wx, wz) if terrain_data != null else 0.0
	return Vector3(wx, wy, wz)


## Radius (from the centre) at which a unit counts as "at the building".
func interact_range() -> float:
	return float(maxi(footprint.x, footprint.y)) * 0.5 * TerrainData.CELL_SIZE + 1.6


## Finished training building of the OWN tribe whose footprint contains this
## building's rally point — a rally point set onto e.g. the warrior camp makes
## freshly produced braves queue up for training there (phase 5d).
func rally_training_building() -> TrainingBuilding:
	if rally_point == Vector3.ZERO or tribe == null:
		return null
	var rc: Vector2i = Vector2i(
		int(floor(rally_point.x / TerrainData.CELL_SIZE)),
		int(floor(rally_point.z / TerrainData.CELL_SIZE)))
	for b in tribe.buildings:
		if is_instance_valid(b) and b is TrainingBuilding and b.is_usable():
			if Rect2i(b.cell, b.footprint).has_point(rc):
				return b as TrainingBuilding
	return null


## Walkable world position for spawning units: entrance first, then the
## perimeter rings (the flattened footprint may leave a steep rim).
func edge_spawn_position() -> Vector3:
	if nav_grid != null:
		# One truth with the AI's plot check (10g): approach_cell_for is the very
		# same search, extracted so a plot without a building can be asked too.
		var c: Vector2i = approach_cell_for(nav_grid, cell, footprint, orientation)
		if c.x >= 0:
			return nav_grid.cell_to_world(c)
	return entrance_world()


## Guaranteed-walkable spot next to the building where workers drop wood and the
## site absorbs it. Normally the entrance; if the entrance side is not reachable
## (water / slope / blocked), the nearest walkable perimeter cell — so wood
## delivery never gets stuck on an unreachable doorway (workers would otherwise
## stand around holding wood, or drop it back at the trees).
##
## PERSISTED (10i, F1): computed once and kept. It is only recomputed when the
## remembered cell actually stopped being walkable — a changed neighbourhood on
## its own must NOT move the anchor, or the wood already lying there falls out of
## ABSORB_RADIUS. Deliberately lazy instead of initialised in init_construction():
## pre-built buildings (every start site) skip that call entirely.
func delivery_point() -> Vector3:
	if nav_grid == null:
		return edge_spawn_position()   # headless tests without navigation
	if _delivery_point_version == nav_grid.change_version and _delivery_point.x < INF:
		return _delivery_point
	if _delivery_point.x < INF \
			and nav_grid.is_cell_walkable(nav_grid.world_to_cell(_delivery_point)):
		_delivery_point_version = nav_grid.change_version   # still good: keep it
		return _delivery_point
	_delivery_point = edge_spawn_position()
	_delivery_point_version = nav_grid.change_version
	return _delivery_point


# --- Worker reachability (phase 10d) ---------------------------------------------

## Island label of the worker approach point. delivery_point() is guaranteed to
## be a WALKABLE cell, so a plain island comparison is exact and O(1) — no A*
## needed. Cached against NavGrid.change_version (pattern from
## AIController._plot_reachable). -1 = no approach spot at all: nobody can ever
## work here (fully enclosed / island-less plot).
func approach_island() -> int:
	if nav_grid == null:
		return 0   # headless tests without navigation: permissive
	if _approach_island_version == nav_grid.change_version:
		return _approach_island
	_approach_island_version = nav_grid.change_version
	_approach_island = nav_grid.island_at(nav_grid.world_to_cell(delivery_point()))
	return _approach_island


## True when a worker standing at `from` can walk to this building's approach
## spot (same island). Permissive without a NavGrid so headless tests run.
func worker_can_reach(from: Vector3) -> bool:
	if nav_grid == null:
		return true
	var mine: int = approach_island()
	if mine < 0:
		return false
	var theirs: int = nav_grid.island_at(nav_grid.world_to_cell(from))
	if theirs < 0:
		# The worker's own cell is not walkable — it stands ON a footprint
		# (graders do), on a cliff or in shallow water. That says nothing about
		# island membership, so stay permissive instead of pulling it off the job.
		return true
	return theirs == mine


## True while another worker can still join this site/demolition. Freed workers
## are filtered out (10i, F5): a stale entry would silently shrink the crew cap
## and could starve a plot. wood_incoming() already guards this way.
func has_worker_room() -> bool:
	return live_workers() < MAX_WORKERS


## Number of workers that are still alive. `workers` is pruned by leave(), but a
## unit freed without leaving (test teardown, edge cases in destruction) would
## otherwise linger.
func live_workers() -> int:
	var count: int = 0
	for w in workers:
		if is_instance_valid(w):
			count += 1
	return count


## Drops `amount` wood as ground piles at the delivery point (there is no tribe
## wood stock). Wood dropped into water is lost — same rule as any other pile.
func _refund_wood(amount: int) -> void:
	if amount <= 0 or wood_pile_manager == null:
		return
	wood_pile_manager.deposit(delivery_point(), amount)


func _ready() -> void:
	set_process(false)   # only enabled for the destruction sink
	_create_visuals()
	if _mesh_root != null:
		_mesh_root.rotation.y = float(orientation) * PI * 0.5
	_create_click_body()
	_create_selection_ring()
	_create_rally_marker()
	_create_overlay()
	_update_construction_visual()
	_update_damage_visual()


# --- Construction setup (called by BuildingManager.place) --------------------------

## Prepares the flatten phase: target height = average footprint vertex height.
func init_construction() -> void:
	_site_hp_cap = _construction_hp_cap()
	health = _site_hp_cap
	foundation_done = false
	_flatten_remaining.clear()
	_flatten_claims.clear()
	var total: float = 0.0
	var count: int = 0
	for vz in range(cell.y, cell.y + footprint.y + 1):
		for vx in range(cell.x, cell.x + footprint.x + 1):
			total += terrain_data.vertex_height(vx, vz)
			count += 1
	flatten_target = total / float(count)
	for z in range(cell.y, cell.y + footprint.y):
		for x in range(cell.x, cell.x + footprint.x):
			_flatten_remaining[Vector2i(x, z)] = true
	# The entrance cell is levelled too, so the doorway sits flush — but that is
	# purely cosmetic, and it must never become a blocker (10i, F3). Inside a
	# FOREIGN footprint it can never be graded, _flatten_remaining would never
	# empty, foundation_done would stay false and add_build_progress stays gated
	# forever. Grading it there would also deform the neighbour's foundation.
	var entrance: Vector2i = entrance_cell()
	if terrain_data != null and terrain_data.in_bounds(entrance) \
			and not _cell_in_foreign_footprint(entrance):
		_flatten_remaining[entrance] = true
	_flatten_stall.clear()
	_flatten_stall_tick = 0.0


# --- Gameplay tick (driven by BuildingManager) -----------------------------------

func tick(delta: float) -> void:
	# Lava contact must be CONTINUOUS to wreck: once the grace window runs out
	# without a fresh add_lava_contact(), the accumulated contact time is void.
	if _lava_contact_grace > 0.0:
		_lava_contact_grace -= delta
		if _lava_contact_grace <= 0.0:
			_lava_contact_accum = 0.0
	if under_construction:
		_tick_construction(delta)
		if _destroyed:
			return   # the site decayed away (10d) or was torn down mid-tick
		# Sites are raidable too (bug backlog #2): melee demolition ticks the
		# (wood-scaled) site HP down; destroy() frees the plot mid-tick.
		_tick_raid(delta)
		if _destroyed:
			return
	else:
		if _foundation_disturbed and health > 0:
			_tick_foundation_smoothing(delta)
		_tick_raid(delta)
		# No repair absorption during the demolition — it would eat the refund.
		if health > 0 and health < max_health and _absorbs_repair_wood() \
				and not demolishing:
			_tick_repair_absorb(delta)
		# The upgrade needs its OWN absorption: _tick_repair_absorb only runs on a
		# DAMAGED building, so delivered upgrade wood would never be booked in.
		if upgrading:
			_tick_upgrade_absorb(delta)
			if _destroyed:
				return
		# A building being stormed from the inside stops producing (the stage
		# gate also disables it once the demolition passes 30 %).
		if is_usable() and raiders.is_empty():
			_tick_active(delta)
	_update_overlay()
	_update_crew_overlay()
	_update_rally_marker()


# --- Destruction stages & repair (phase 6) ----------------------------------------

## Current destruction stage from the damage fraction: 0 = intact/usable,
## 1..3 = increasingly wrecked (unusable, repairable), 4 = destroyed.
func destruction_stage() -> int:
	if health <= 0:
		return 4
	var damage: float = 1.0 - float(health) / float(max_health)
	if damage >= STAGE_DAMAGE * 3.0:
		return 3
	if damage >= STAGE_DAMAGE * 2.0:
		return 2
	if damage >= STAGE_DAMAGE:
		return 1
	return 0


## Usable = finished, alive, below stage 1 damage and not being torn down. Gates
## all production (hut spawns, training) and the housing capacity.
func is_usable() -> bool:
	return not under_construction and health > 0 and destruction_stage() == 0 \
		and not demolishing


## Damage worth `count` destruction stages (30% of max HP each) — lightning
## (+2) and the tornado (+1 every 2 s) deal damage in these steps.
## Construction sites are FRAGILE: any staged spell hit levels them outright
## (otherwise workers would finish a spell-damaged site and the building
## seemed indestructible while under construction).
func apply_destruction_stages(count: int) -> void:
	if count <= 0:
		return
	if under_construction:
		destroy()
		return
	take_damage(int(ceil(STAGE_DAMAGE * float(max_health))) * count)


## Lava contact (LavaSurge/LavaFlow, throttled check ticks): accumulates the
## contact seconds; every FULL Balance.LAVA_BUILDING_STAGE_TIME the building
## takes one destruction stage. Each call re-arms the grace window — tick()
## voids the accumulator once no lava has touched the building for
## Balance.LAVA_BUILDING_CONTACT_GRACE seconds. Construction sites shatter on
## their first stage (fragile rule in apply_destruction_stages).
func add_lava_contact(seconds: float) -> void:
	if health <= 0 or seconds <= 0.0:
		return
	_lava_contact_grace = Balance.LAVA_BUILDING_CONTACT_GRACE
	_lava_contact_accum += seconds
	while _lava_contact_accum >= Balance.LAVA_BUILDING_STAGE_TIME:
		_lava_contact_accum -= Balance.LAVA_BUILDING_STAGE_TIME
		apply_destruction_stages(1)
		if health <= 0:
			return


## HP of repair work one delivered wood pays for.
func repair_hp_per_wood() -> float:
	if wood_cost <= 0:
		return float(max_health)
	return float(max_health) / float(wood_cost)


## Wood the CURRENT damage still requires beyond what was already delivered:
## floor(damage fraction * wood_cost) — e.g. a hut repaired from 90% damage
## costs 90% of its wood cost, rounded down.
func repair_wood_missing() -> int:
	if wood_cost <= 0 or under_construction or health <= 0:
		return 0
	var damage: float = 1.0 - float(health) / float(max_health)
	return maxi(0, int(floor(damage * float(wood_cost))) - repair_wood)


## True while repair workers should still fetch more wood (analogous to
## wants_more_wood for construction; wood_incoming counts carried/claimed
## wood and piles near the entrance).
func wants_more_repair_wood() -> bool:
	return not under_construction and not demolishing \
		and health > 0 and health < max_health \
		and repair_wood_missing() > wood_incoming()


## Applies `amount` HP of repair work (from a worker). Work consumes the
## repair-wood buffer (1 wood per repair_hp_per_wood() HP); once the buffer is
## empty it only continues while the remaining damage rounds down to 0 owed
## wood (the floored total cost). Returns false when the repair stalls for
## wood — the worker then fetches more (or the site stalls).
func repair(amount: float) -> bool:
	if under_construction or health <= 0 or health >= max_health:
		return false
	if wood_cost > 0:
		while _repair_hp_pool < amount and repair_wood > 0:
			repair_wood -= 1
			_repair_hp_pool += repair_hp_per_wood()
		if _repair_hp_pool <= 0.0:
			if repair_wood_missing() > 0:
				return false   # wood still owed and none delivered
			_repair_hp_pool = amount   # sub-wood remainder repairs for free
		amount = minf(amount, _repair_hp_pool)
		_repair_hp_pool -= amount
	_repair_hp_frac += amount
	var whole: int = int(_repair_hp_frac)
	if whole > 0:
		_repair_hp_frac -= float(whole)
		health = mini(health + whole, max_health)
		if health >= max_health:
			_repair_hp_pool = 0.0
			_repair_hp_frac = 0.0
		_update_damage_visual()
	return true


# --- Upgrade API (phase 10f, overridden by Hut) -------------------------------
# Deliberately shaped like the repair API above — the upgrade IS "fetch wood for
# a FINISHED building", so the Brave reuses the same CHOP/PICKUP/DELIVER pipeline
# and only the work step differs.

## Upgrade wood still owed beyond what was already delivered.
func upgrade_wood_missing() -> int:
	return 0


## True while upgrade workers should still fetch more wood.
func wants_upgrade_wood() -> bool:
	return false


## Applies `amount` of upgrade work (a worker's build rate). Returns false when
## the upgrade stalls for wood — the worker then fetches more (or it stalls).
func work_upgrade(_amount: float) -> bool:
	return false


## Progress of the running upgrade (0..1), -1 when none is running. Feeds the
## (blue) info bar above the building.
func upgrade_progress() -> float:
	return -1.0


## Aborts a running upgrade and hands the delivered wood back as ground piles.
## `restart_delay` also resets the due timer: without it the refunded wood would
## instantly satisfy the "wood in reach" start condition again and the upgrade
## would restart on the very next tick — a cancel/restart loop. Damage and
## demolition pass false, because there the upgrade SHOULD resume once the cause
## is gone; the stall timeout passes true.
func cancel_upgrade(_restart_delay: bool = false) -> void:
	pass


## Drops a running upgrade WITHOUT paying the wood back — for the demolition,
## which folds `upgrade_wood` into its own (portion-wise) payout instead, and for
## destruction, where it is lost with the building like repair_wood is.
func abandon_upgrade() -> void:
	pass


## The building just crossed into stage >= 1 (unusable): eject occupants alive
## (spells keep the original living eject; the melee storm ejected them earlier).
func _on_disabled() -> void:
	eject_occupants(false)


## Damage the ranged eject (`killed` = true) deals to each occupant: one brave
## life. Braves/firewarriors die in the tumble, tougher units can survive.
const EJECT_RANGED_DAMAGE: int = Balance.BUILDING_EJECT_RANGED_DAMAGE


## Ejects any units housed inside (training trainee; tower crew in 7h). Base
## buildings have none. `killed` = ranged eject (firewarrior stage-1 fire /
## catapult hit): the occupants roll out with EJECT_RANGED_DAMAGE — weak units
## die once the tumble ends, tough ones survive hurt. Otherwise they are
## pushed out alive and unhurt (spells, melee storm start).
func eject_occupants(_killed: bool) -> void:
	pass


## Ejects one occupant that has just been put back into the world: it is shoved
## away from the building into a short tumble. `killed` (ranged fire / catapult)
## deals EJECT_RANGED_DAMAGE on top — for weak units that is lethal, and the
## ROLL state defers their death, so they visibly roll out and only collapse
## once at rest; tougher units come to rest hurt but alive. The usual roll
## damage applies during the tumble either way. Untyped param (freed-safe).
func _eject_unit(u, killed: bool) -> void:
	if not is_instance_valid(u) or u.state == Unit.State.DEAD:
		return
	var dir: Vector3 = u.position - center_world()
	dir.y = 0.0
	if dir.length_squared() < 0.000001:
		dir = Vector3(1.0, 0.0, 0.0)
	u.displace(dir, Unit.SHOVE_DISPLACE)
	u.start_roll(dir, Unit.MINI_ROLL_DURATION)
	if killed:
		u.take_damage(EJECT_RANGED_DAMAGE)


# --- Attack targeting (phase 7g, generalised in 10g) ------------------------------

## Whether this building may be TARGETED by an attack at all — the one truth for
## every path that picks a building to hit: ground units (melee storm +
## firewarrior fire), crewed vehicles (catapult/fire-ram bombardment, both the
## explicit order and the auto-scan), the airship deck crew, and the AI's spell
## and attack-wave target choice. False only for the reincarnation site.
##
## Renamed from is_assailable_by_units() in 10g, because the old name invited
## exactly the bug it was meant to prevent: it read as "units only", so the
## vehicle and airship paths were never gated by it and happily bombarded the
## invulnerable circle forever. DAMAGE is a separate, independent matter — the
## circle no-ops take_damage()/apply_destruction_stages()/add_lava_contact()
## itself (10d), so a spell landing on it is harmless regardless of this flag.
func is_attackable() -> bool:
	return true


## Max melee raiders that may storm this building at once (watchtower: 5).
func max_melee_raiders() -> int:
	return MAX_MELEE_RAIDERS


## True while another melee raider still fits (used by the unit building scan so
## overflow raiders do not keep re-targeting a full building).
func has_raider_room() -> bool:
	_prune_raiders()
	return raiders.size() < max_melee_raiders()


## True while enemy raiders are demolishing inside. Makes the building a valid
## catapult target for its OWN tribe (anti-raider bombardment, phase 7f).
func has_raiders() -> bool:
	_prune_raiders()
	return not raiders.is_empty()


## Catapult hit on the OWN building: every raider inside is thrown back out
## HURT (damage, then a short tumble away from the building) instead of killed.
## Ejected with this building as their target they resume the assault once the
## dust settles — or turn on the catapult — exactly like an entrance-threat
## ejection (_eject_raiders_to_fight).
func blast_raiders(damage: int, attacker = null) -> void:
	var center: Vector3 = center_world()
	for r in raiders:
		if not is_instance_valid(r) or r.state == Unit.State.DEAD:
			continue
		if unit_manager != null:
			unit_manager.register(r)
		r.exit_building_as_raider(edge_spawn_position(), self)
		r.take_damage(damage, attacker)
		if r.state == Unit.State.DEAD:
			continue
		var away: Vector3 = Vector3(r.position.x - center.x, 0.0, r.position.z - center.z)
		if away.length_squared() < 0.000001:
			away = Vector3(1, 0, 0).rotated(Vector3.UP, randf() * TAU)
		r.start_roll(away.normalized(), 1.0)
	raiders.clear()


## True when this building houses occupants that a storm should throw out
## (training trainee, forester/workshop crew). Base: none.
func has_occupants() -> bool:
	return false


## Begins the storm: throws the housed occupants out ALIVE (once) so the
## attackers must fight them at the entrance before they can demolish. Called by
## the first attacker that reaches the building; idempotent.
func begin_storm() -> void:
	if _storm_started:
		return
	_storm_started = true
	if has_occupants():
		eject_occupants(false)


## Nearest LIVE enemy of the building owner (defender / ejected occupant) within
## ENTRANCE_CLEAR_RADIUS of the entrance that is not in a conversion (SIT). Null
## when the entrance is clear. Drives the "clear before you demolish" rule.
func nearest_entrance_threat() -> Unit:
	if unit_manager == null:
		return null
	var entrance: Vector3 = entrance_world()
	var flat: Vector2 = Vector2(entrance.x, entrance.z)
	var best: Unit = null
	var best_d: float = ENTRANCE_CLEAR_RADIUS
	for u in unit_manager.get_units_in_radius(entrance, ENTRANCE_CLEAR_RADIUS):
		if u.tribe_id != tribe_id or u.state == Unit.State.DEAD or u.state == Unit.State.SIT:
			continue
		# A protected reserve (garrisoned tower crew) is INSIDE, not at the door:
		# attackers cannot engage it (_begin_attack refuses non-targetable units),
		# so counting it here dead-locked every assault on a manned watchtower
		# (walk anim in place, no approach, no storm — user bug report).
		if not u.is_targetable():
			continue
		var d: float = Vector2(u.position.x, u.position.z).distance_to(flat)
		if d < best_d:
			best_d = d
			best = u
	return best


func has_entrance_threat() -> bool:
	return nearest_entrance_threat() != null


## Lets an attacker enter as a melee raider: removed from the world (like a
## trainee), demolishing from the inside. Refused when the building is full OR
## the entrance is not clear of enemies (the storm must clear the doorway first).
func admit_raider(unit) -> bool:
	_prune_raiders()
	if unit in raiders:
		return true
	if raiders.size() >= max_melee_raiders():
		return false
	if has_entrance_threat():
		return false   # clear the entrance before anyone slips inside
	raiders.append(unit)
	if unit_manager != null:
		unit_manager.remove_from_world(unit)
	unit.enter_building_as_raider(self)
	set_process(true)   # start the wobble (in-game only)
	return true


## Drops freed/dead raiders and ones that are no longer inside this building.
func _prune_raiders() -> void:
	var kept: Array = []
	for r in raiders:
		if is_instance_valid(r) and r.state != Unit.State.DEAD and r.raiding_building == self:
			kept.append(r)
	raiders = kept


## Raiders demolish from the inside: HP damage scales with the raider count
## (more demolishers = faster teardown). If a live enemy shows up at the
## entrance (a defender, or the just-ejected occupants), the demolishers come
## back OUT to fight it first — demolition only continues once it is clear.
func _tick_raid(delta: float) -> void:
	if raiders.is_empty():
		return
	_prune_raiders()
	if raiders.is_empty():
		return
	if has_entrance_threat():
		_eject_raiders_to_fight()
		return
	_raid_damage_frac += RAID_DPS_PER_RAIDER * float(raiders.size()) * delta
	var whole: int = int(_raid_damage_frac)
	if whole > 0:
		_raid_damage_frac -= float(whole)
		# One demolition sound per building at a time, regardless of raider count.
		_play_sfx(&"building_attack_melee", 2500)
		take_damage(whole)   # generic: no re-eject (occupants already handled)


## Sends all demolishers back out (alive) to fight an entrance threat. They keep
## this building as their target and resume the assault once the way is clear.
func _eject_raiders_to_fight() -> void:
	for r in raiders:
		if is_instance_valid(r) and r.state != Unit.State.DEAD:
			if unit_manager != null:
				unit_manager.register(r)
			r.exit_building_as_raider(edge_spawn_position(), self)
	raiders.clear()


## Lets ONE demolisher step back out at the perimeter, alive and idle, without
## a building target — the hook behind an explicit order to a unit that is
## inside (Unit._leave_building_for_order). The caller issues the actual order
## afterwards; re-registering here is mandatory, or the unit would carry its
## new state around unregistered, never ticked and never drawn.
func release_raider(unit) -> void:
	var idx: int = raiders.find(unit)
	if idx >= 0:
		raiders.remove_at(idx)
	if not is_instance_valid(unit) or unit.state == Unit.State.DEAD:
		return
	if unit_manager != null:
		unit_manager.register(unit)
	unit.exit_building_as_raider(edge_spawn_position())


## Releases the demolishers back into the world at the perimeter (alive, IDLE)
## when the building collapses — they tear it down and step out.
func _release_raiders() -> void:
	for r in raiders:
		if is_instance_valid(r) and r.state != Unit.State.DEAD:
			var pos: Vector3 = edge_spawn_position()
			if unit_manager != null:
				unit_manager.register(r)
			r.exit_building_as_raider(pos)
	raiders.clear()


## Called by the terrain-integrity check (SpellContext) when a terrain morph
## bent the foundation without breaking it — the ground settles level again.
func mark_foundation_disturbed() -> void:
	if under_construction or health <= 0:
		return
	_foundation_disturbed = true


## Moves every footprint vertex toward the (current) mean height until the
## foundation is flat again; terrain/nav updates are batched like during
## construction. The building re-seats on the settling ground.
func _tick_foundation_smoothing(delta: float) -> void:
	if terrain_data == null:
		_foundation_disturbed = false
		return
	var total: float = 0.0
	var count: int = 0
	for vz in range(cell.y, cell.y + footprint.y + 1):
		for vx in range(cell.x, cell.x + footprint.x + 1):
			total += terrain_data.vertex_height(vx, vz)
			count += 1
	var mean: float = total / float(count)
	var level: bool = true
	for vz in range(cell.y, cell.y + footprint.y + 1):
		for vx in range(cell.x, cell.x + footprint.x + 1):
			var h: float = terrain_data.vertex_height(vx, vz)
			var nh: float = move_toward(h, mean, FOUNDATION_SMOOTH_RATE * delta)
			terrain_data.set_vertex_height(vx, vz, nh)
			if absf(nh - mean) > FLATTEN_EPS:
				level = false
	position.y = mean
	_dirty = footprint_rect() if _dirty.size == Vector2i.ZERO else _dirty.merge(footprint_rect())
	_flush_timer -= delta
	if _flush_timer <= 0.0 or level:
		_flush_timer = FLUSH_INTERVAL
		_flush_deformation()
	if level:
		_foundation_disturbed = false


## Whether a damaged building passively pulls nearby wood piles into its repair
## buffer. Default true (delivered repair wood is banked before a worker hammers).
## The workshop overrides this so its entrance PRODUCTION stock is only consumed
## during an actively staffed repair — never silently eaten on damage.
func _absorbs_repair_wood() -> bool:
	return true


## While damaged: absorb wood piles near the entrance into the repair buffer
## and run the wood-stall re-check (mirrors _tick_construction).
func _tick_repair_absorb(delta: float) -> void:
	if wood_stalled:
		_wood_recheck_timer -= delta
		if _wood_recheck_timer <= 0.0:
			wood_stalled = false
	_absorb_timer -= delta
	if _absorb_timer > 0.0:
		return
	_absorb_timer = ABSORB_INTERVAL
	if wood_pile_manager == null:
		return
	var need: int = repair_wood_missing()
	if need <= 0:
		return
	var taken: int = wood_pile_manager.take_from_radius(delivery_point(), ABSORB_RADIUS, need)
	if taken > 0:
		repair_wood += taken
		wood_stalled = false


## While upgrading (10f): absorb wood piles near the entrance into the upgrade
## buffer, run the wood-stall re-check and watch the stall timer. Nobody but the
## hut's own (ejected) crew works an upgrade, so if those braves die on the way
## the upgrade would hang forever — after HUT_UPGRADE_STALL_TIMEOUT without any
## progress it is cancelled and the delivered wood goes back on the ground.
func _tick_upgrade_absorb(delta: float) -> void:
	if wood_stalled:
		_wood_recheck_timer -= delta
		if _wood_recheck_timer <= 0.0:
			wood_stalled = false
	# Hopeless right now: a worker reported "no wood source anywhere" AND nobody is
	# left on the job with nothing banked. Waiting out the full timeout would leave
	# the ex-crew standing around outside for two minutes while the hut produces
	# nothing — give up at once so the growth control pulls them back inside.
	# (Not on wood_stalled alone: with one free tree the second worker reports a
	# stall while the first is legitimately chopping.)
	if wood_stalled and workers.is_empty() and upgrade_wood == 0:
		cancel_upgrade(true)
		return
	_upgrade_stall_timer += delta
	if _upgrade_stall_timer >= Balance.HUT_UPGRADE_STALL_TIMEOUT:
		cancel_upgrade(true)   # true = wait the full delay before retrying
		return
	_absorb_timer -= delta
	if _absorb_timer > 0.0:
		return
	_absorb_timer = ABSORB_INTERVAL
	if wood_pile_manager == null:
		return
	var need: int = upgrade_wood_missing()
	if need <= 0:
		return
	var taken: int = wood_pile_manager.take_from_radius(delivery_point(), ABSORB_RADIUS, need)
	if taken > 0:
		upgrade_wood += taken
		wood_stalled = false
		_upgrade_stall_timer = 0.0   # fresh wood on site: progress is being made


## 0..1 progress toward the next produced/trained unit, or -1 when the building
## is not currently producing (base: none). Drives the bar above the building.
func production_progress() -> float:
	return -1.0


# --- Selection & overlay --------------------------------------------------------

func set_selected(p_selected: bool) -> void:
	selected = p_selected
	if _selection_ring != null:
		_selection_ring.visible = p_selected


func set_hovered(p_hovered: bool) -> void:
	hovered = p_hovered


## Selection-ring gold; flash_ring() restores it after a coloured flash.
const RING_COLOR: Color = Color(0.98, 0.85, 0.45)
## Red flash when this building becomes the target of an attack order.
const ATTACK_FLASH_COLOR: Color = Color(0.9, 0.2, 0.15)

## Active flash tween; killed before a new flash so two quick orders in a row
## cannot run overlapping blink loops (visible now that colours can differ).
var _flash_tween: Tween = null


## Blinks the selection ring twice — feedback when units are sent inside
## (manning/training/garrison/crew), a rally point lands on this building, or
## (in red) an attack order targets it. Restores the ring colour and the
## current selection state afterwards.
func flash_ring(color: Color = RING_COLOR) -> void:
	if _selection_ring == null or not is_inside_tree():
		return
	var ring: MeshInstance3D = _selection_ring
	var mat: StandardMaterial3D = ring.material_override as StandardMaterial3D
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	if mat != null:
		mat.albedo_color = color
	var tween: Tween = create_tween()
	_flash_tween = tween
	for i in range(2):
		tween.tween_callback(func() -> void: ring.visible = true)
		tween.tween_interval(0.16)
		tween.tween_callback(func() -> void: ring.visible = false)
		tween.tween_interval(0.12)
	tween.tween_callback(func() -> void:
		if mat != null:
			mat.albedo_color = RING_COLOR
		ring.visible = selected)


func _create_selection_ring() -> void:
	_selection_ring = MeshInstance3D.new()
	_selection_ring.name = "SelectionRing"
	_selection_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var torus: TorusMesh = TorusMesh.new()
	var r: float = float(maxi(footprint.x, footprint.y)) * 0.5 + 0.4
	torus.inner_radius = r - 0.18
	torus.outer_radius = r
	_selection_ring.mesh = torus
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = RING_COLOR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_selection_ring.material_override = mat
	_selection_ring.position.y = 0.12
	_selection_ring.visible = false
	add_child(_selection_ring)


## Rally-point marker (ring + little pole), shown only while the building is
## selected. Positioned in world at the rally point each tick.
func _create_rally_marker() -> void:
	_rally_marker = Node3D.new()
	_rally_marker.name = "RallyMarker"
	_rally_marker.visible = false
	add_child(_rally_marker)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.98, 0.85, 0.45)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var ring: MeshInstance3D = MeshInstance3D.new()
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.45
	torus.outer_radius = 0.6
	ring.mesh = torus
	ring.material_override = mat
	ring.position.y = 0.06
	_rally_marker.add_child(ring)

	var pole: MeshInstance3D = MeshInstance3D.new()
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.05
	cyl.height = 1.2
	pole.mesh = cyl
	pole.material_override = mat
	pole.position.y = 0.6
	_rally_marker.add_child(pole)


func _update_rally_marker() -> void:
	if _rally_marker == null:
		return
	var show: bool = selected and rally_point != Vector3.ZERO
	_rally_marker.visible = show
	if show:
		_rally_marker.position = rally_point - position


func _create_overlay() -> void:
	_overlay_sprite = Sprite3D.new()
	_overlay_sprite.name = "ProductionBar"
	_overlay_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_overlay_sprite.shaded = false
	_overlay_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_overlay_sprite.set_draw_flag(SpriteBase3D.FLAG_DISABLE_DEPTH_TEST, true)
	_overlay_sprite.pixel_size = 0.07
	_overlay_sprite.position.y = OVERLAY_Y
	_overlay_sprite.visible = false
	add_child(_overlay_sprite)
	# Crew-pip overlay just below the production bar (all crew buildings).
	_crew_sprite = Sprite3D.new()
	_crew_sprite.name = "CrewPips"
	_crew_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_crew_sprite.shaded = false
	_crew_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_crew_sprite.set_draw_flag(SpriteBase3D.FLAG_DISABLE_DEPTH_TEST, true)
	_crew_sprite.pixel_size = 0.07
	_crew_sprite.position.y = OVERLAY_Y - 0.6
	_crew_sprite.visible = false
	add_child(_crew_sprite)


## Shows a progress bar above the building — only while it is selected or
## hovered (and actually producing). Texture is only rebuilt when the value
## moves. A demolition or an upgrade shows ITS progress instead: neither can go
## through a production_progress() override, because every producing subclass
## returns -1.0 as soon as the building is not usable (demolition) or has no crew
## left inside (upgrade).
func _update_overlay() -> void:
	if _overlay_sprite == null:
		return
	var p: float = -1.0
	var mode: int = BAR_PRODUCTION
	if selected or hovered:
		if demolishing:
			p = demolish_progress()
			mode = BAR_DEMOLISH
		elif upgrading:
			p = upgrade_progress()
			mode = BAR_UPGRADE
		else:
			p = production_progress()
	if p < 0.0:
		if _overlay_sprite.visible:
			_overlay_sprite.visible = false
		_overlay_progress = -1.0
		_overlay_mode = -1
		return
	_overlay_sprite.visible = true
	# The mode is part of the cache key: without it the bar would keep the old
	# colour when production switches to a demolition or an upgrade at a
	# near-identical progress value.
	if absf(p - _overlay_progress) < 0.02 and mode == _overlay_mode:
		return
	_overlay_progress = p
	_overlay_mode = mode
	_overlay_sprite.texture = _make_bar_texture(p, mode)


## Crew occupancy shown as pips on select/hover (hut pattern, generalised to
## every crew building; the watchtower opts out via crew_display_capacity 0).
func _update_crew_overlay() -> void:
	if _crew_sprite == null:
		return
	var cap: int = crew_display_capacity()
	if cap <= 0 or not (selected or hovered) or not is_usable():
		if _crew_sprite.visible:
			_crew_sprite.visible = false
		_crew_shown = -1
		_crew_shown_cap = -1
		return
	_crew_sprite.visible = true
	var n: int = crew_display_filled()
	# The CAPACITY is part of the cache key since 10f: a hut upgrade raises the
	# slot count without changing the filled count, and a pips-only comparison
	# would keep drawing the old, too-short row.
	if n == _crew_shown and cap == _crew_shown_cap:
		return
	_crew_shown = n
	_crew_shown_cap = cap
	_crew_sprite.texture = _make_crew_texture(n, cap)


## Crew-pip capacity for the hover overlay. Default 0 = no crew pips (wood
## depot, reincarnation site, AND the watchtower, which opts out by design).
## Crew buildings override this and crew_display_filled().
func crew_display_capacity() -> int:
	return 0


func crew_display_filled() -> int:
	return 0


## One square pip per slot: gold = occupied, dark = free.
static func _make_crew_texture(filled: int, capacity: int) -> ImageTexture:
	var pip: int = 6
	var gap: int = 2
	var cap: int = maxi(capacity, 1)
	var w: int = cap * pip + (cap - 1) * gap
	var img: Image = Image.create_empty(w, pip, false, Image.FORMAT_RGBA8)
	for i in cap:
		var color: Color = Color(0.85, 0.68, 0.30) if i < filled \
			else Color(0.09, 0.06, 0.03, 0.9)
		img.fill_rect(Rect2i(i * (pip + gap), 0, pip, pip), color)
	return ImageTexture.create_from_image(img)


## Variants of the one info bar above a building: gold = production (the normal
## case), red = demolition (10d), blue = upgrade (10f). One bar, three meanings —
## the colour is what tells them apart.
const BAR_PRODUCTION: int = 0
const BAR_DEMOLISH: int = 1
const BAR_UPGRADE: int = 2


## Dark bar background with a fill proportional to progress, coloured by `mode`.
static func _make_bar_texture(progress: float, mode: int = BAR_PRODUCTION) -> ImageTexture:
	var w: int = 32
	var h: int = 6
	var img: Image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.09, 0.06, 0.03, 0.9))
	var fill: int = clampi(int(round(clampf(progress, 0.0, 1.0) * float(w - 2))), 0, w - 2)
	if fill > 0:
		var color: Color = Color(0.85, 0.68, 0.30)
		match mode:
			BAR_DEMOLISH: color = Color(0.90, 0.28, 0.18)
			BAR_UPGRADE: color = Color(0.35, 0.62, 0.95)
		img.fill_rect(Rect2i(1, 1, fill, h - 2), color)
	return ImageTexture.create_from_image(img)


func _tick_construction(delta: float) -> void:
	_flush_timer -= delta
	if _flush_timer <= 0.0:
		_flush_timer = FLUSH_INTERVAL
		_flush_deformation()
	if not demolishing:
		_tick_decay(delta)
		if _destroyed:
			return
	_absorb_timer -= delta
	if _absorb_timer <= 0.0:
		_absorb_timer = ABSORB_INTERVAL
		# A site being torn down must NOT re-absorb the refund it just paid out
		# (the piles land at the same delivery point). Load-bearing guard.
		if not demolishing:
			_absorb_piles()
	if wood_stalled:
		_wood_recheck_timer -= delta
		if _wood_recheck_timer <= 0.0:
			wood_stalled = false  # workers may try again (30-s re-check)
	if not foundation_done and not demolishing:
		_tick_flatten_stall(delta)
	# From the first delivered wood on, keep the footprint clear of units so the
	# rising building does not bury (and hide) anyone standing on the plot.
	# Only AFTER the plot is fully graded: the building starts rising with
	# add_build_progress (gated on foundation_done), while the GRADERS must
	# stand on the plot — the sweep used to evict them every 0.5 s, the central
	# cells of big plots (8x8 wharf) never finished and the site deadlocked.
	if wood_delivered >= 1 and foundation_done:
		_clear_timer -= delta
		if _clear_timer <= 0.0:
			_clear_timer = CLEAR_INTERVAL
			_clear_footprint()


## Pushes any unit standing on the footprint to the nearest walkable cell
## outside it. Delivering workers wait at the entrance (outside), so they are
## unaffected; units that cannot take orders (dead/thrown/sitting/crew) are
## left. The site's OWN workers are never evicted — the order_move would rip
## them out of the job entirely (claim + membership) and the recruit/evict
## churn starved the plot (user bug report, 8x8 wharf).
func _clear_footprint() -> void:
	if unit_manager == null or nav_grid == null:
		return
	var rect: Rect2i = footprint_rect()
	var reach: float = float(maxi(footprint.x, footprint.y)) * 0.5 * TerrainData.CELL_SIZE + 1.0
	for u in unit_manager.get_units_in_radius(center_world(), reach):
		if not is_instance_valid(u) or not u.can_take_orders():
			continue
		if u.get("job") == self:
			continue   # own graders/builders stay at their work
		var cell: Vector2i = nav_grid.world_to_cell(u.position)
		if not rect.has_point(cell):
			continue
		var out: Vector2i = nav_grid.nearest_walkable_cell(cell)
		if out.x >= 0 and not rect.has_point(out):
			u.order_move(nav_grid.cell_to_world(out))


# --- Demolition (phase 10d) ----------------------------------------------------

## True once the building reached at least the first build stage. Only sites that
## never got that far can be scrapped instantly; everything else has to be torn
## down by workers. finish_construction sets build_progress = 1.0, so finished
## buildings always count as "with build stage".
func has_build_stage() -> bool:
	return build_progress > 0.0


## Wood physically sitting in this building. NOT wood_delivered alone: a
## pre_built building (match start, tests) never ran a delivery, so its
## wood_delivered is 0 while it still cost its full price. _repair_hp_pool is
## excluded — that wood is already converted into HP. `upgrade_wood` (10f) is
## wood lying in a half-finished upgrade; a FINISHED upgrade is already part of
## wood_cost (Hut._finish_upgrade adds it).
func _demolish_refund_base() -> int:
	var built: int = wood_delivered if under_construction else wood_cost
	return maxi(0, built) + repair_wood + upgrade_wood


## Wood the player gets back for scrapping this building.
func demolish_refund_total() -> int:
	var factor: float = Balance.DEMOLISH_REFUND_BUILT if has_build_stage() \
		else Balance.DEMOLISH_REFUND_UNBUILT
	return int(floor(float(_demolish_refund_base()) * factor))


## Starts the demolition. Returns true when the building was scrapped right away
## (no build stage reached): the full wood drops at the plot and it is gone.
## Otherwise the demolition becomes a worker job — build_progress then runs
## backwards and the refund is paid out in portions. The order is FINAL: there
## is no cancel.
func begin_demolish() -> bool:
	if _destroyed or demolishing:
		return _destroyed
	if not has_build_stage():
		_flush_deformation()
		_refund_wood(demolish_refund_total())
		abandon_upgrade()   # its wood is already part of the payout above
		destroy()
		return true
	demolishing = true
	_demolish_start_progress = build_progress
	_demolish_refund_total = demolish_refund_total()
	_demolish_refund_paid = 0
	# The refund total above already counts the wood of a half-finished upgrade
	# (10f), so drop the upgrade WITHOUT a second payout. Its workers are sent
	# back through the task choice by the switch_to_demolish loop below.
	abandon_upgrade()
	# A wood-stalled site is skipped by the recruiter — clear it, or the
	# demolition would never get any hands.
	wood_stalled = false
	_on_disabled()          # crew / trainees / garrison out, alive
	_flush_deformation()
	_update_construction_visual()
	if tribe != null:
		tribe.notify_housing_changed()
	# Workers already on this building are mid-sub-task (flatten/chop/build/
	# repair) and would keep working against the demolition: send them back
	# through the task choice.
	for worker in workers.duplicate():
		if is_instance_valid(worker):
			worker.switch_to_demolish()
	return false


## Progress of the demolition itself (0..1) — feeds the info bar above the
## building while it is being torn down.
func demolish_progress() -> float:
	if not demolishing:
		return -1.0
	return clampf(1.0 - build_progress / maxf(_demolish_start_progress, 0.0001), 0.0, 1.0)


## Applies `amount` of demolition work (a worker's build rate). Returns false
## once the building is gone. The refund is paid out along the way so the player
## sees the wood come back in portions.
func work_demolish(amount: float) -> bool:
	if not demolishing or _destroyed:
		return false
	build_progress = maxf(build_progress - amount, 0.0)
	_update_construction_visual()
	_pay_demolish_refund()
	if build_progress <= 0.0:
		_finish_demolish()
		return false
	return true


## Pays out the share of the refund the demolition has already earned.
func _pay_demolish_refund() -> void:
	var due: int = int(floor(float(_demolish_refund_total) * demolish_progress()))
	var owed: int = due - _demolish_refund_paid
	if owed <= 0:
		return
	# Counted as paid even when the wood lands in water and is lost — otherwise
	# this would retry every tick forever.
	_demolish_refund_paid += owed
	_refund_wood(owed)


## Last stone gone: pay whatever is left and remove the building.
func _finish_demolish() -> void:
	var rest: int = _demolish_refund_total - _demolish_refund_paid
	if rest > 0:
		_demolish_refund_paid += rest
		_refund_wood(rest)
	_flush_deformation()
	destroy()


## Construction decay (phase 10d): a site that makes NO progress at all for
## Balance.CONSTRUCTION_STALL_TIMEOUT falls apart again and gives its wood back.
## Progress is anything that moves the build forward — a graded cell, delivered
## wood or build progress. Catches the unreachable plot (no worker ever arrives),
## the forgotten site and the one whose wood source dried up for good.
func _tick_decay(delta: float) -> void:
	# Absolute second criterion (10i, F7): a site that never even STARTS to rise
	# gives up. The signature below is reset by every partial booking and every
	# graded cell, so a site whose anchor occasionally drifted back within reach
	# of its pile could live forever without ever building anything.
	if build_progress <= 0.0:
		_no_start_timer += delta
		if _no_start_timer >= Balance.CONSTRUCTION_NO_START_TIMEOUT:
			_decay_stalled_site()
			return
	else:
		_no_start_timer = 0.0
	var signature: Vector3 = Vector3(build_progress, float(wood_delivered),
		float(_flatten_remaining.size()))
	if signature != _decay_signature:
		_decay_signature = signature
		_decay_timer = 0.0
		return
	_decay_timer += delta
	if _decay_timer >= Balance.CONSTRUCTION_STALL_TIMEOUT:
		_decay_stalled_site()


## The site rotted away: hand the delivered wood back as piles and remove it.
## The refund MUST happen before destroy() — destroy() pays nothing and clears
## under_construction.
func _decay_stalled_site() -> void:
	_flush_deformation()
	_refund_wood(int(floor(float(wood_delivered) * Balance.CONSTRUCTION_STALL_REFUND)))
	destroy()


## Subclass logic while the building is operational.
func _tick_active(_delta: float) -> void:
	pass


# --- Worker management -----------------------------------------------------------

func join(worker: Brave) -> bool:
	if worker in workers:
		return true
	if not has_worker_room():
		return false
	workers.append(worker)
	return true


func leave(worker: Brave) -> void:
	workers.erase(worker)


# --- Flatten phase -------------------------------------------------------------------

func needs_flatten() -> bool:
	return under_construction and not foundation_done and not _flatten_remaining.is_empty()


## True when `c` lies inside the footprint of a building that is NOT this one.
## Its own plot is solid too, so a plain is_cell_blocked_by_building() would
## report every own cell as foreign.
func _cell_in_foreign_footprint(c: Vector2i) -> bool:
	if nav_grid == null or not nav_grid.is_cell_blocked_by_building(c):
		return false
	return not footprint_rect().has_point(c)


## Drops flatten cells that no worker managed to grade for FLATTEN_CELL_TIMEOUT
## (10i, F3). A single unreachable cell — in a neighbour's footprint, behind a
## grading trench, on the far side of a torn-up plot — used to keep
## _flatten_remaining non-empty forever, and with it foundation_done false and
## add_build_progress gated: the site could never be built at all. A dent next
## to the doorway is the better trade.
##
## Accounted once per SECOND over the open cells (an 8x8 has 65 of them), not
## once per tick. The clock only runs while the site HAS workers: an unattended
## plot (no wood, nobody recruited yet) must not quietly erode its own grading
## duty and then rise out of untouched terrain.
##
## Dropping every cell is deliberately allowed. The blocking cell is by
## definition the LAST one left — the reachable ones get graded and erased — so
## a "keep the last one" rule would defeat the whole fix. A site whose ENTIRE
## plot is unreachable is still caught: no worker arrives, build_progress stays
## 0 and the decay (10d, plus F7 below) removes it.
func _tick_flatten_stall(delta: float) -> void:
	if _flatten_remaining.is_empty() or live_workers() == 0:
		return
	_flatten_stall_tick += delta
	if _flatten_stall_tick < 1.0:
		return
	var elapsed: float = _flatten_stall_tick
	_flatten_stall_tick = 0.0
	var timed_out: Array[Vector2i] = []
	for c: Vector2i in _flatten_remaining.keys():
		var waited: float = _flatten_stall.get(c, 0.0) + elapsed
		_flatten_stall[c] = waited
		if waited >= Balance.FLATTEN_CELL_TIMEOUT:
			timed_out.append(c)
	for c in timed_out:
		_flatten_remaining.erase(c)
		_flatten_claims.erase(c)
		_flatten_stall.erase(c)
	if _flatten_remaining.is_empty():
		foundation_done = true
		position.y = flatten_target
		_flush_deformation()


func flatten_cell_pending(c: Vector2i) -> bool:
	return _flatten_remaining.has(c)


## True while some foundation cell has no worker on it yet (workers split:
## unclaimed cells first, spare hands fetch wood in the meantime).
func has_unclaimed_flatten_cell() -> bool:
	for c: Vector2i in _flatten_remaining.keys():
		if _flatten_claims.get(c, 0) == 0:
			return true
	return false


## Picks an unflattened cell for a worker: least claims first, then nearest.
## Returns (-1, -1) when nothing is left. Multiple workers may share a cell.
func claim_flatten_cell(from_pos: Vector3) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_score: float = INF
	var flat: Vector2 = Vector2(from_pos.x, from_pos.z)
	for c: Vector2i in _flatten_remaining.keys():
		var claims: int = _flatten_claims.get(c, 0)
		var dist: float = Vector2(float(c.x) + 0.5, float(c.y) + 0.5).distance_to(flat)
		var score: float = float(claims) * 1000.0 + dist
		if score < best_score:
			best_score = score
			best = c
	if best.x >= 0:
		_flatten_claims[best] = _flatten_claims.get(best, 0) + 1
	return best


func release_flatten_cell(c: Vector2i) -> void:
	if not _flatten_claims.has(c):
		return
	_flatten_claims[c] -= 1
	if _flatten_claims[c] <= 0:
		_flatten_claims.erase(c)


## One worker's flatten contribution on a cell: moves its 4 corner vertices
## toward flatten_target by `amount` metres. Returns true when the cell is
## level (several workers on one cell stack their contributions).
func work_flatten(c: Vector2i, amount: float) -> bool:
	if foundation_done:
		return true
	if not _flatten_remaining.has(c):
		return true
	var done: bool = true
	for dz in range(2):
		for dx in range(2):
			var h: float = terrain_data.vertex_height(c.x + dx, c.y + dz)
			var nh: float = move_toward(h, flatten_target, amount)
			terrain_data.set_vertex_height(c.x + dx, c.y + dz, nh)
			if absf(nh - flatten_target) > FLATTEN_EPS:
				done = false
	_mark_dirty(c)
	_flatten_stall[c] = 0.0   # somebody reached it: its stall clock restarts
	if done:
		_flatten_remaining.erase(c)
		_flatten_stall.erase(c)
		if _flatten_remaining.is_empty():
			foundation_done = true
			position.y = flatten_target  # settle onto the levelled ground
			_flush_deformation()
	return done


func _mark_dirty(c: Vector2i) -> void:
	var r: Rect2i = Rect2i(c, Vector2i(1, 1))
	_dirty = r if _dirty.size == Vector2i.ZERO else _dirty.merge(r)


## Pushes batched terrain changes to navigation and (via Events) to the
## terrain mesh. Grown by 1 because edge vertices affect neighbouring cells.
func _flush_deformation() -> void:
	if _dirty.size == Vector2i.ZERO:
		return
	var r: Rect2i = _dirty.grow(1)
	_dirty = Rect2i()
	if nav_grid != null:
		nav_grid.update_region(r)
	if is_inside_tree():
		var events: Node = get_node_or_null("/root/Events")
		if events != null:
			events.terrain_deformed.emit(r)


# --- Wood delivery ---------------------------------------------------------------------

func wood_needed_total() -> int:
	return maxi(0, wood_cost - wood_delivered)


## Wood already on its way: carried by workers, on claimed trees and lying in
## piles near the entrance (those get absorbed automatically).
func wood_incoming() -> int:
	var total: int = 0
	for worker in workers:
		if is_instance_valid(worker):
			total += worker.carried_wood + worker.claimed_tree_yield()
	if wood_pile_manager != null:
		total += wood_pile_manager.wood_in_radius(delivery_point(), ABSORB_RADIUS)
	return total


## True while workers should still fetch more wood.
func wants_more_wood() -> bool:
	return under_construction and not demolishing \
		and wood_needed_total() > wood_incoming()


## HP ceiling of the construction site from the delivered-wood fraction,
## capped at SITE_HP_CAP_FRACTION of the full HP (bug backlog #2).
func _construction_hp_cap() -> int:
	var frac: float = SITE_HP_CAP_FRACTION
	if wood_cost > 0:
		frac = minf(float(wood_delivered) / float(wood_cost), SITE_HP_CAP_FRACTION)
	return maxi(SITE_MIN_HP, int(round(float(max_health) * frac)))


## Raises the site's HP along with freshly delivered wood. Only the ceiling
## delta is added, so damage the site already took persists.
func _grow_site_hp() -> void:
	if not under_construction:
		return
	var cap: int = _construction_hp_cap()
	if cap > _site_hp_cap:
		health += cap - _site_hp_cap
		_site_hp_cap = cap


## Progress ceiling from the delivered-wood fraction.
func progress_cap() -> float:
	if wood_cost <= 0:
		return 1.0
	return float(wood_delivered) / float(wood_cost)


## Called by workers when no wood source is reachable anywhere: the site
## pauses (workers leave, recruiting skips it) until the re-check interval
## expires or wood arrives at the entrance.
func mark_wood_stalled() -> void:
	if wood_stalled:
		return
	wood_stalled = true
	_wood_recheck_timer = WOOD_RECHECK_INTERVAL


func _absorb_piles() -> void:
	if wood_pile_manager == null:
		return
	var need: int = wood_needed_total()
	if need <= 0:
		return
	var taken: int = wood_pile_manager.take_from_radius(delivery_point(), ABSORB_RADIUS, need)
	if taken > 0:
		wood_delivered += taken
		wood_stalled = false  # fresh wood on site: back to work
		_grow_site_hp()


# --- Build phase --------------------------------------------------------------------------

## Adds construction progress, capped by the delivered-wood fraction — the
## building can only be completed once all wood is on site. Requires the
## foundation to be flattened first.
func add_build_progress(amount: float) -> void:
	if not under_construction or not foundation_done or demolishing:
		return
	build_progress = clampf(build_progress + amount, 0.0, progress_cap())
	_update_construction_visual()
	if build_progress >= 1.0:
		finish_construction()


func finish_construction() -> void:
	if not under_construction:
		return
	under_construction = false
	foundation_done = true
	build_progress = 1.0
	# Leave the site HP model: the finished building has the full max_health,
	# minus any damage the site took (repairable like any other damage).
	if _site_hp_cap > 0:
		health = clampi(max_health - (_site_hp_cap - health), SITE_MIN_HP, max_health)
		_site_hp_cap = 0
		_update_damage_visual()
	_flatten_remaining.clear()
	_flatten_claims.clear()
	_flush_deformation()
	_update_construction_visual()
	construction_finished.emit(self)
	if is_inside_tree():
		var events: Node = get_node_or_null("/root/Events")
		if events != null:
			events.building_completed.emit(self)
	if tribe != null:
		tribe.notify_housing_changed()


# --- Damage / destruction ------------------------------------------------------------

func take_damage(amount: int, source: int = DMG_GENERIC) -> void:
	if health <= 0:
		return
	var was_usable: bool = is_usable()
	var stage_before: int = destruction_stage()
	health -= amount
	if health <= 0:
		health = 0
		destroy()
		return
	# Under-fire feedback: ranged hits get their own (per-building throttled)
	# sound; crossing into a higher destruction stage plays the "crack".
	if source == DMG_RANGED:
		_play_sfx(&"building_attack_ranged", 1500)
	if destruction_stage() > stage_before:
		_play_sfx(&"building_damaged")
		_spawn_damage_burst()
	if was_usable and not is_usable():
		# Just crossed into stage >= 1 (unusable). Ranged fire that reaches this
		# on its own hurls the occupants out hurt (weak units die in the tumble);
		# spells / melee demolition eject them alive (melee already ejected them
		# at the storm start -> no-op).
		if source == DMG_RANGED and raiders.is_empty():
			eject_occupants(true)
		else:
			_on_disabled()
		# A damaged building is repaired first (10f): the upgrade gives its wood
		# back and stays due, so it restarts once the hut is whole again.
		cancel_upgrade()
	_update_damage_visual()


## Frees the NavGrid footprint (the plot becomes buildable/walkable again),
## deregisters from the tribe and removes the building. In-game the wreck
## sinks into the ground first (visual only, _process) before freeing itself;
## outside the tree (headless tests) the owner frees the node.
func destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	health = 0
	# A wrecked construction site must not stay "under construction": workers
	# would keep building it (_job_active) and finish_construction could
	# resurrect it. The guard in finish_construction relies on this too.
	under_construction = false
	# Same reason for the demolition flag: the wreck lives on for SINK_DURATION,
	# and _job_active() honours `demolishing` — the crew would keep hammering at
	# a building that is already gone. `upgrading` (10f) is honoured there too,
	# and its wood is lost with the building (like repair_wood).
	demolishing = false
	abandon_upgrade()
	if nav_grid != null:
		nav_grid.fill_solid_region(footprint_rect(), false)
	# The footprint is walkable again: the demolishers step out alive (IDLE).
	_release_raiders()
	if tribe != null:
		tribe.remove_building(self)
	set_selected(false)
	destroyed.emit(self)
	if is_inside_tree():
		var events: Node = get_node_or_null("/root/Events")
		if events != null:
			events.building_destroyed.emit(self)
		_begin_sinking()


## Terrain integrity (7c): the foundation broke — the building is destroyed
## outright and the model vanishes instantly (the caller spawns the debris
## burst that replaces it).
func shatter() -> void:
	_vanish_on_destroy = true
	destroy()


## True while this wreck is sinking IN THE SEA — the WaterFxRenderer then draws
## a splash ring on the surface above it until it is gone. Presentation only.
func water_splash_active() -> bool:
	if not _destroyed or terrain_data == null or _sink_time >= SINK_DURATION:
		return false
	return terrain_data.get_height(position.x, position.z) \
		<= TerrainData.SEA_LEVEL + Unit.WATER_EPS


## Radius (metres) of that splash ring — a hut displaces less than a temple.
func water_splash_radius() -> float:
	return maxf(float(footprint.x), float(footprint.y)) * 0.6


## Terrain integrity (7c): mostly flooded — the wreck slides sideways into
## the water while sinking below the waves.
func slide_into_water(dir: Vector3) -> void:
	var flat: Vector3 = Vector3(dir.x, 0.0, dir.z)
	_slide_dir = flat.normalized() if flat.length_squared() > 0.000001 else Vector3(1, 0, 0)
	destroy()


## Visual-only sink of the destroyed building; all gameplay registration is
## already gone at this point (no clicks, no ticks).
func _begin_sinking() -> void:
	_sink_time = 0.0
	var body: Node = get_node_or_null("ClickBody")
	if body != null:
		body.queue_free()
	if _selection_ring != null:
		_selection_ring.visible = false
	if _overlay_sprite != null:
		_overlay_sprite.visible = false
	if _rally_marker != null:
		_rally_marker.visible = false
	if _vanish_on_destroy:
		visible = false
		queue_free()
		return
	if water_splash_active():
		_play_sfx(&"water_splash")   # the wreck hits the sea
	set_process(true)


func _process(delta: float) -> void:
	if _destroyed:
		var was_above: bool = _sink_time < SINK_DURATION * 0.5
		_sink_time += delta
		position.y -= SINK_DEPTH / SINK_DURATION * delta
		position += _slide_dir * SLIDE_SPEED * delta
		# Halfway down the wreck is under the surface (phase 10a).
		if was_above and _sink_time >= SINK_DURATION * 0.5 and water_splash_active():
			_play_sfx(&"water_sink")
		# One slow rocking lean while it goes under, so the wreck settles instead
		# of dropping straight down like a lift. Mutually exclusive with the raid
		# wobble (that branch is only reached when NOT destroyed).
		if _mesh_root != null:
			var lean: float = SINK_TILT * sin(_sink_time * TAU * SINK_TILT_HZ)
			_mesh_root.rotation.z = lean
			_mesh_root.rotation.x = lean * 0.6
		if _sink_time >= SINK_DURATION:
			queue_free()
		return
	_tick_wobble(delta)


## Rocks the model back and forth in slow swings while raiders demolish it;
## settles upright and stops processing once the storm ends (in-game only).
func _tick_wobble(delta: float) -> void:
	if _mesh_root == null:
		return
	if raiders.is_empty():
		_wobble_time = 0.0
		_mesh_root.rotation.x = 0.0
		_mesh_root.rotation.z = 0.0
		set_process(false)
		return
	_wobble_time += delta
	_mesh_root.rotation.z = RAID_WOBBLE_AMPLITUDE * sin(_wobble_time * TAU * RAID_WOBBLE_HZ)
	_mesh_root.rotation.x = RAID_WOBBLE_AMPLITUDE * 0.6 * sin(_wobble_time * TAU * RAID_WOBBLE_HZ * 1.3)


# --- Visuals (asset model or placeholder meshes, created in _ready only) -------------

## Asset lookup name for this building (assets/models/buildings/<kind>.glb);
## empty = no asset support, always procedural.
func asset_kind() -> StringName:
	return &""


## Subclasses build their placeholder meshes under _mesh_root — unless a
## user-provided model was loaded (_has_custom_model); then they return early.
## The root is rotated by `orientation`, so models/meshes are authored with
## the entrance south (+Z).
func _create_visuals() -> void:
	_mesh_root = Node3D.new()
	_mesh_root.name = "MeshRoot"
	add_child(_mesh_root)
	_try_load_custom_model()


## Throws the model away and builds it again — for a building whose asset_kind()
## or placeholder geometry changed at runtime (10f: the hut grows a stage). All
## caches that describe the OLD model have to be dropped with it, or the texture
## swaps and damage holes would keep pointing at freed nodes. Does nothing
## outside the scene tree (headless tests never built visuals in the first place).
func _rebuild_visuals() -> void:
	if _mesh_root == null:
		return
	# Detached before queue_free so the new "MeshRoot" cannot collide with the old
	# one (queue_free is deferred to the end of the frame).
	remove_child(_mesh_root)
	_mesh_root.queue_free()
	_mesh_root = null
	_has_custom_model = false
	_model_surfaces.clear()
	_damage_holes.clear()
	_stage_tex_cache.clear()
	_visual_stage = -1
	_build_visual_stage = -1
	_create_visuals()
	if _mesh_root != null:
		_mesh_root.rotation.y = float(orientation) * PI * 0.5
	# The click box is rebuilt too, in case a subclass sizes it from state that
	# just changed. No hut stage does — its hitbox is deliberately constant (user
	# report: a growing hitbox is wrong) — but a rebuilt model with a stale click
	# body would be a trap for the next subclass that varies one of them.
	var old_body: Node = get_node_or_null("ClickBody")
	if old_body != null:
		remove_child(old_body)
		old_body.queue_free()
		_create_click_body()
	_update_construction_visual()
	_update_damage_visual()


func _try_load_custom_model() -> void:
	var kind: StringName = asset_kind()
	if kind == &"":
		return
	var model: Node3D = AssetLibrary.instantiate_model("models/buildings/%s.glb" % kind)
	if model == null:
		return
	_mesh_root.add_child(model)
	_has_custom_model = true
	_collect_surfaces(model)
	if not _tint_flag_meshes(model):
		_add_flag()


## Gathers the loaded model's texturable MeshInstance3D surfaces (excluding
## "Flag" meshes, which keep the tribe tint) for the stage/build texture swap.
func _collect_surfaces(node: Node) -> void:
	if node is MeshInstance3D and node.name != "Flag":
		_model_surfaces.append(node)
	for child in node.get_children():
		_collect_surfaces(child)


## Loads a stage/build texture by relative path (cached; null when missing).
func _stage_texture(rel: String) -> Texture2D:
	if _stage_tex_cache.has(rel):
		return _stage_tex_cache[rel]
	var tex: Texture2D = AssetLibrary.texture(rel)
	_stage_tex_cache[rel] = tex
	return tex


## Swaps the albedo texture on all custom-model surfaces. null restores the
## model's baked material (= intact / finished). Alpha is rendered as
## alpha-scissor so transparent texture regions punch holes (see plan).
func _apply_surface_texture(tex: Texture2D) -> void:
	if tex == null:
		for surf in _model_surfaces:
			surf.material_override = null
		return
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = 1.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	for surf in _model_surfaces:
		surf.material_override = mat


## Tints every MeshInstance3D named "Flag" inside a loaded model with the
## tribe colour; returns true when at least one was found.
func _tint_flag_meshes(node: Node) -> bool:
	var found: bool = false
	if node is MeshInstance3D and node.name == "Flag":
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Unit.TRIBE_COLORS[tribe_id % Unit.TRIBE_COLORS.size()]
		(node as MeshInstance3D).material_override = mat
		found = true
	for child in node.get_children():
		if _tint_flag_meshes(child):
			found = true
	return found


## Plays a file-based one-shot at the building centre via the AudioManager.
## min_interval_ms throttles PER BUILDING (each keeps its own timestamps), so
## e.g. two raided huts each get their own demolition sound.
func _play_sfx(name: StringName, min_interval_ms: int = 0) -> void:
	if not is_inside_tree():
		return
	if min_interval_ms > 0:
		var now: int = Time.get_ticks_msec()
		if now - int(_sfx_last_ms.get(name, -min_interval_ms)) < min_interval_ms:
			return
		_sfx_last_ms[name] = now
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.play_sfx(name, center_world())


## Small tribe-coloured flag next to the building.
func _add_flag() -> void:
	if _mesh_root == null:
		return
	var pole: MeshInstance3D = MeshInstance3D.new()
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pole_mesh: CylinderMesh = CylinderMesh.new()
	pole_mesh.top_radius = 0.05
	pole_mesh.bottom_radius = 0.05
	pole_mesh.height = 2.4
	pole.mesh = pole_mesh
	pole.position = Vector3(float(footprint.x) * 0.5 - 0.2, 1.2, float(footprint.y) * 0.5 - 0.2)
	_mesh_root.add_child(pole)
	var flag: MeshInstance3D = MeshInstance3D.new()
	flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flag_mesh: BoxMesh = BoxMesh.new()
	flag_mesh.size = Vector3(0.7, 0.4, 0.05)
	flag.mesh = flag_mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Unit.TRIBE_COLORS[tribe_id % Unit.TRIBE_COLORS.size()]
	flag.material_override = mat
	flag.position = pole.position + Vector3(0.35, 1.0, 0.0)
	_mesh_root.add_child(flag)


func _make_material(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	return mat


## StaticBody3D + BoxShape3D on layer 2 for mouse-ray selection/targeting.
func _create_click_body() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "ClickBody"
	body.collision_layer = 2
	body.collision_mask = 0
	body.set_meta("building", self)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	var h: float = _click_body_height()
	box.size = Vector3(float(footprint.x), h, float(footprint.y))
	shape.shape = box
	shape.position.y = h * 0.5
	body.add_child(shape)
	add_child(body)


## Height (metres) of the click/selection collision box. Tall buildings (the
## watchtower) override this so clicks on the upper structure still register.
func _click_body_height() -> float:
	return 2.5


## The building "grows out of the ground" with the build progress
## (placeholder); during the flatten phase only a sliver is visible. A demolition
## (10d) runs the same visual backwards — build_progress is the single source for
## both directions.
func _update_construction_visual() -> void:
	if _mesh_root == null:
		return
	var building_up: bool = under_construction or demolishing
	# Asset-driven path: full-size model, texture swapped per build stage
	# (4 stages over build_progress; finished -> baked/default texture).
	if _has_custom_model and _has_build_textures():
		_mesh_root.scale = Vector3.ONE
		if not building_up:
			if _build_visual_stage != 0:
				_build_visual_stage = 0
				_apply_surface_texture(null)
			return
		var idx: int = 1 if not foundation_done else clampi(int(build_progress * 4.0), 0, 3) + 1
		if idx != _build_visual_stage:
			_build_visual_stage = idx
			_apply_surface_texture(_stage_texture(_build_tex_rel(idx)))
		return
	# Fallback: the placeholder "grows out of the ground" via Y scaling.
	var s: float = 1.0 if not building_up else 0.1 + 0.9 * build_progress
	_mesh_root.scale = Vector3(1.0, maxf(s, 0.05), 1.0)


func _build_tex_rel(idx: int) -> String:
	return "textures/buildings/%s_build%d.png" % [asset_kind(), idx]


## True when at least the first build-stage texture exists for this kind.
func _has_build_textures() -> bool:
	return _stage_texture(_build_tex_rel(1)) != null


## Placeholder damage visual: per destruction stage, two more dark chunks
## appear "broken out" of the model (real damage textures can replace this
## later via the same stage hook). Cached on the current stage.
func _update_damage_visual() -> void:
	if _mesh_root == null:
		return
	var stage: int = mini(destruction_stage(), 3)
	if stage == _visual_stage:
		return
	_visual_stage = stage
	# Asset-driven path: swap in the stage texture (stage 0 -> baked/default).
	if _has_custom_model:
		var stage_tex: Texture2D = null
		if stage > 0:
			stage_tex = _stage_texture("textures/buildings/%s_stage%d.png" % [asset_kind(), stage])
		if stage == 0 or stage_tex != null:
			_apply_surface_texture(stage_tex)
			return
	# Fallback: per stage, two more dark chunks appear "broken out".
	if _damage_holes.is_empty():
		if stage == 0:
			return
		_create_damage_holes()
	for i in range(_damage_holes.size()):
		_damage_holes[i].visible = i < stage * 2


func _create_damage_holes() -> void:
	var mat: StandardMaterial3D = _make_material(Color(0.07, 0.05, 0.03))
	var w: float = float(footprint.x)
	var d: float = float(footprint.y)
	for i in range(MAX_DAMAGE_HOLES):
		var hole: MeshInstance3D = MeshInstance3D.new()
		hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var box: BoxMesh = BoxMesh.new()
		var s: float = 0.5 + 0.18 * float(i % 3)
		box.size = Vector3(s, s, s)
		hole.mesh = box
		hole.material_override = mat
		var angle: float = TAU * float(i) / float(MAX_DAMAGE_HOLES) + 0.7
		hole.position = Vector3(
			cos(angle) * w * 0.38, 0.5 + 0.35 * float(i % 4), sin(angle) * d * 0.38)
		hole.rotation = Vector3(0.4 * float(i), 0.9 * float(i), 0.0)
		hole.visible = false
		_mesh_root.add_child(hole)
		_damage_holes.append(hole)


## Spawns a short-lived burst of falling fragments around the model when a new
## destruction stage is reached ("bits of texture flake off"). Ticked via the
## UnitManager projectile list; independent of assets (fallback fragments).
func _spawn_damage_burst() -> void:
	if unit_manager == null or under_construction:
		return
	var burst: BuildingDamageBurst = BuildingDamageBurst.new()
	burst.setup(
		center_world(),
		float(maxi(footprint.x, footprint.y)) * 0.5 * TerrainData.CELL_SIZE,
		terrain_data,
		Color(0.5, 0.4, 0.28))
	unit_manager.register_projectile(burst)
