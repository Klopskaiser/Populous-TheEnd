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
## Sideways drift of a flooded wreck sliding into the water (7c integrity rule).
const SLIDE_SPEED: float = 1.6
## A building that survived a terrain morph levels its foundation back at
## this rate (metres per second per vertex) — the crooked ground "settles".
const FOUNDATION_SMOOTH_RATE: float = 0.3
## Placeholder damage visual: dark "broken out" chunks, 2 shown per stage.
const MAX_DAMAGE_HOLES: int = 6

# --- Building assault (phase 7g) ----------------------------------------------
## Damage source tags for take_damage: ranged fire (firewarrior) that reaches
## stage 1 on its own KILLS the trapped occupants, everything else (spells,
## melee demolition) ejects them alive.
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
var _flatten_remaining: Dictionary[Vector2i, bool] = {}
var _flatten_claims: Dictionary[Vector2i, int] = {}
var _dirty: Rect2i = Rect2i()
var _flush_timer: float = FLUSH_INTERVAL
var _absorb_timer: float = ABSORB_INTERVAL
var _clear_timer: float = 0.0   # footprint-clear throttle (phase 7i)
var _wood_recheck_timer: float = 0.0


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
		if nav_grid.is_cell_walkable(entrance_cell()):
			return nav_grid.cell_to_world(entrance_cell())
		for grow in range(1, 4):
			var rect: Rect2i = footprint_rect().grow(grow)
			var inner: Rect2i = footprint_rect().grow(grow - 1)
			for z in range(rect.position.y, rect.position.y + rect.size.y):
				for x in range(rect.position.x, rect.position.x + rect.size.x):
					var c: Vector2i = Vector2i(x, z)
					if inner.has_point(c):
						continue
					if nav_grid.is_cell_walkable(c):
						return nav_grid.cell_to_world(c)
	return entrance_world()


## Guaranteed-walkable spot next to the building where workers drop wood and the
## site absorbs it. Normally the entrance; if the entrance side is not reachable
## (water / slope / blocked), the nearest walkable perimeter cell — so wood
## delivery never gets stuck on an unreachable doorway (workers would otherwise
## stand around holding wood, or drop it back at the trees).
func delivery_point() -> Vector3:
	return edge_spawn_position()


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
	# The entrance cell is levelled too, so the doorway sits flush.
	var entrance: Vector2i = entrance_cell()
	if terrain_data != null and terrain_data.in_bounds(entrance):
		_flatten_remaining[entrance] = true


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
		# Sites are raidable too (bug backlog #2): melee demolition ticks the
		# (wood-scaled) site HP down; destroy() frees the plot mid-tick.
		_tick_raid(delta)
		if _destroyed:
			return
	else:
		if _foundation_disturbed and health > 0:
			_tick_foundation_smoothing(delta)
		_tick_raid(delta)
		if health > 0 and health < max_health and _absorbs_repair_wood():
			_tick_repair_absorb(delta)
		# A building being stormed from the inside stops producing (the stage
		# gate also disables it once the demolition passes 30 %).
		if is_usable() and raiders.is_empty():
			_tick_active(delta)
	_update_overlay()
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


## Usable = finished, alive and below stage 1 damage. Gates all production
## (hut spawns, training) and the housing capacity.
func is_usable() -> bool:
	return not under_construction and health > 0 and destruction_stage() == 0


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
	return not under_construction and health > 0 and health < max_health \
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


## The building just crossed into stage >= 1 (unusable): eject occupants alive
## (spells keep the original living eject; the melee storm ejected them earlier).
func _on_disabled() -> void:
	eject_occupants(false)


## Ejects any units housed inside (training trainee; tower crew in 7h). Base
## buildings have none. `killed` = ejected units die at the door (ranged fire
## reached stage 1); otherwise they are pushed out alive (melee storm start).
func eject_occupants(_killed: bool) -> void:
	pass


## Ejects one occupant that has just been put back into the world: `killed`
## flings it out and kills it at the door (ranged stage-1 fire), otherwise it is
## shoved away from the building into a short tumble. Untyped param (freed-safe).
func _eject_unit(u, killed: bool) -> void:
	if not is_instance_valid(u) or u.state == Unit.State.DEAD:
		return
	if killed:
		u.take_damage(u.health + 1000)
		return
	var dir: Vector3 = u.position - center_world()
	dir.y = 0.0
	if dir.length_squared() < 0.000001:
		dir = Vector3(1.0, 0.0, 0.0)
	u.displace(dir, Unit.SHOVE_DISPLACE)
	u.start_roll(dir, Unit.MINI_ROLL_DURATION)


# --- Melee raiders / storm (phase 7g) --------------------------------------------

## Whether ground units may assault this building (melee storm + firewarrior
## fireballs). False for the reincarnation site: only SPELLS and CATAPULTS may
## damage it — those go through apply_destruction_stages()/take_damage() and are
## NOT gated by this flag.
func is_assailable_by_units() -> bool:
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


## Shows a progress bar above the building — only while it is selected or
## hovered (and actually producing). Texture is only rebuilt when the value
## moves.
func _update_overlay() -> void:
	if _overlay_sprite == null:
		return
	var p: float = production_progress() if (selected or hovered) else -1.0
	if p < 0.0:
		if _overlay_sprite.visible:
			_overlay_sprite.visible = false
		_overlay_progress = -1.0
		return
	_overlay_sprite.visible = true
	if absf(p - _overlay_progress) < 0.02:
		return
	_overlay_progress = p
	_overlay_sprite.texture = _make_bar_texture(p)


## Dark bar background with a gold fill proportional to progress.
static func _make_bar_texture(progress: float) -> ImageTexture:
	var w: int = 32
	var h: int = 6
	var img: Image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.09, 0.06, 0.03, 0.9))
	var fill: int = clampi(int(round(clampf(progress, 0.0, 1.0) * float(w - 2))), 0, w - 2)
	if fill > 0:
		img.fill_rect(Rect2i(1, 1, fill, h - 2), Color(0.85, 0.68, 0.30))
	return ImageTexture.create_from_image(img)


func _tick_construction(delta: float) -> void:
	_flush_timer -= delta
	if _flush_timer <= 0.0:
		_flush_timer = FLUSH_INTERVAL
		_flush_deformation()
	_absorb_timer -= delta
	if _absorb_timer <= 0.0:
		_absorb_timer = ABSORB_INTERVAL
		_absorb_piles()
	if wood_stalled:
		_wood_recheck_timer -= delta
		if _wood_recheck_timer <= 0.0:
			wood_stalled = false  # workers may try again (30-s re-check)
	# From the first delivered wood on, keep the footprint clear of units so the
	# rising building does not bury (and hide) anyone standing on the plot.
	if wood_delivered >= 1:
		_clear_timer -= delta
		if _clear_timer <= 0.0:
			_clear_timer = CLEAR_INTERVAL
			_clear_footprint()


## Pushes any unit standing on the footprint to the nearest walkable cell
## outside it. Delivering workers wait at the entrance (outside), so they are
## unaffected; units that cannot take orders (dead/thrown/sitting/crew) are left.
func _clear_footprint() -> void:
	if unit_manager == null or nav_grid == null:
		return
	var rect: Rect2i = footprint_rect()
	var reach: float = float(maxi(footprint.x, footprint.y)) * 0.5 * TerrainData.CELL_SIZE + 1.0
	for u in unit_manager.get_units_in_radius(center_world(), reach):
		if not is_instance_valid(u) or not u.can_take_orders():
			continue
		var cell: Vector2i = nav_grid.world_to_cell(u.position)
		if not rect.has_point(cell):
			continue
		var out: Vector2i = nav_grid.nearest_walkable_cell(cell)
		if out.x >= 0 and not rect.has_point(out):
			u.order_move(nav_grid.cell_to_world(out))


## Subclass logic while the building is operational.
func _tick_active(_delta: float) -> void:
	pass


# --- Worker management -----------------------------------------------------------

func join(worker: Brave) -> bool:
	if worker in workers:
		return true
	if workers.size() >= MAX_WORKERS:
		return false
	workers.append(worker)
	return true


func leave(worker: Brave) -> void:
	workers.erase(worker)


# --- Flatten phase -------------------------------------------------------------------

func needs_flatten() -> bool:
	return under_construction and not foundation_done and not _flatten_remaining.is_empty()


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
	if done:
		_flatten_remaining.erase(c)
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
	return under_construction and wood_needed_total() > wood_incoming()


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
	if not under_construction or not foundation_done:
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
		# on its own kills the trapped occupants; spells / melee demolition eject
		# them alive (melee already ejected them at the storm start -> no-op).
		if source == DMG_RANGED and raiders.is_empty():
			eject_occupants(true)
		else:
			_on_disabled()
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
	set_process(true)


func _process(delta: float) -> void:
	if _destroyed:
		_sink_time += delta
		position.y -= SINK_DEPTH / SINK_DURATION * delta
		position += _slide_dir * SLIDE_SPEED * delta
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
## (placeholder); during the flatten phase only a sliver is visible.
func _update_construction_visual() -> void:
	if _mesh_root == null:
		return
	# Asset-driven path: full-size model, texture swapped per build stage
	# (4 stages over build_progress; finished -> baked/default texture).
	if _has_custom_model and _has_build_textures():
		_mesh_root.scale = Vector3.ONE
		if not under_construction:
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
	var s: float = 1.0 if not under_construction else 0.1 + 0.9 * build_progress
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
