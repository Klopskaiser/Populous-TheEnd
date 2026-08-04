class_name Hut extends Building

## Hut: houses population and spawns new Braves over time. Phase 7i: a hut only
## produces while it is MANNED — brave crew hidden inside, still counted in the
## population, no mana cost. Production rate scales LINEARLY with crew, an empty
## hut produces nothing. Crew are pulled in automatically from nearby idle braves
## according to the tribe's growth mode (NONE / MINIMAL / MAXIMUM), or manned
## manually by right-clicking the hut with braves selected. Built by braves:
## foundation flattening first, then construction with delivered wood.
##
## Phase 10f: the hut GROWS. It starts small and cheap (8 wood, 10 places,
## 2 workers) and is upgraded in four stages to the Wohnpalast (28 wood
## cumulative, 45 places, 6 workers). Capacity, crew size and HP are therefore
## per-stage methods, not constants. An upgrade becomes due on a timer; the whole
## crew then leaves, fetches wood and builds — see the upgrade section below.

const WOOD_COST: int = Balance.HUT_WOOD_COST
const FOOTPRINT: Vector2i = Balance.HUT_FOOTPRINT
## Idle braves within this radius are auto-pulled to man the hut.
const MAN_RADIUS: float = 16.0
## Growth maintenance throttle.
const GROWTH_INTERVAL: float = 1.0
## Building name per upgrade stage (UI is German, see CLAUDE.md §8).
const STAGE_NAMES: Array[String] = ["Hütte", "Große Hütte", "Langhaus",
	"Wohnhaus", "Wohnpalast"]

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")

## Counts down from HUT_SPAWN_SECONDS_PER_WORKER at `crew.size()` per second, so
## the seconds per brave are that constant divided by the crew size.
var spawn_timer: float = Balance.HUT_SPAWN_SECONDS_PER_WORKER
var _spawn_counter: int = 0
## Brave crew removed from the world (hidden). Untyped like other occupant
## registries (entries may be freed).
var crew: Array = []
var _growth_timer: float = 0.0
## Manual crew override (-1 = follow the tribe's growth mode). Set by manual
## manning (right-click) and manual ejects (crew tab): the hut then holds that
## crew size until the player moves the growth slider again
## (Tribe.set_growth_mode clears all overrides).
var manual_crew_override: int = -1

## Upgrade stage 0..HUT_MAX_UPGRADE_STAGE — drives capacity, crew size, HP,
## display name and model.
var upgrade_stage: int = 0


func _init() -> void:
	wood_cost = WOOD_COST
	footprint = FOOTPRINT
	max_health = Balance.HUT_HP_PER_STAGE[0]
	health = max_health


func display_name() -> String:
	return STAGE_NAMES[upgrade_stage]


## Population places of this stage.
func capacity() -> int:
	return Balance.HUT_CAPACITY_PER_STAGE[upgrade_stage]


## Crew slots (production workers, braves only) of this stage.
func crew_capacity() -> int:
	return Balance.HUT_CREW_PER_STAGE[upgrade_stage]


## Damaged huts (stage >= 1) house nobody until repaired. A hut BEING UPGRADED
## keeps its housing on purpose (`upgrading` deliberately does not touch
## is_usable) — otherwise the tribe's population cap would collapse during every
## single upgrade. It only loses its production, because its crew is out.
func housing_capacity() -> int:
	return capacity() if is_usable() else 0


# --- Crew (production workers, phase 7i) ---------------------------------------

func crew_count() -> int:
	_prune_crew()
	return crew.size()


func has_crew_room() -> bool:
	_prune_crew()
	return is_usable() and not upgrading and crew.size() < crew_capacity()


## Only own living braves may man a hut.
func _crew_eligible(unit) -> bool:
	return is_instance_valid(unit) and unit.state != Unit.State.DEAD \
		and unit.tribe_id == tribe_id and unit.unit_kind() == &"brave"


## Admits a brave as crew: it is removed from the world (hidden inside), still
## counted in the population. Refused when full, unusable or not a valid brave.
func admit_crew(unit) -> bool:
	_prune_crew()
	if unit in crew:
		return true
	if not is_usable() or upgrading or crew.size() >= crew_capacity() \
			or not _crew_eligible(unit):
		return false
	crew.append(unit)
	# A manually sent brave pins the crew at the new size (override holds until
	# the growth slider moves); auto-pulled braves leave the override alone.
	if unit.man_hut_manual:
		unit.man_hut_manual = false
		manual_crew_override = crew.size()
	unit.enter_hut(self)
	if unit_manager != null:
		unit_manager.remove_from_world(unit)   # hidden reserve
	return true


## Ejects the crew member at `index` alive at the hut edge; walks it to the
## rally point when one is set. `manual` (crew-tab eject) pins the crew at the
## reduced size so the growth mode does not refill the hut.
func eject_crew(index: int, manual: bool = false) -> void:
	_prune_crew()
	if index < 0 or index >= crew.size():
		return
	var u = crew[index]
	crew.remove_at(index)
	if manual:
		manual_crew_override = crew.size()
	_release_crew_member(u, rally_point if rally_point != Vector3.ZERO else Vector3.INF)


## Back to following the tribe's growth mode (called on slider changes).
func clear_manual_override() -> void:
	manual_crew_override = -1


## Ejects every crew member. `killed` (ranged stage-1 fire / catapult hit)
## hurls them out with one brave life of damage (braves die in the tumble);
## otherwise they are shoved out alive (storm / damage / destruction).
func eject_occupants(killed: bool) -> void:
	_prune_crew()
	for u in crew.duplicate():
		if not is_instance_valid(u):
			continue
		if unit_manager != null:
			unit_manager.register(u)
		u.position = edge_spawn_position()
		u._sync_soa_pos()
		u.leave_garrison()
		_eject_unit(u, killed)
	crew.clear()


## Housed crew are storm occupants (thrown out alive when a melee storm begins).
func has_occupants() -> bool:
	_prune_crew()
	return not crew.is_empty()


func destroy() -> void:
	eject_occupants(false)
	if _crew_sprite != null:
		_crew_sprite.visible = false   # like the production bar during the sink
	super.destroy()


## Re-registers a released crew brave at the hut edge and (optionally) sends it
## to `dest`; INF dest leaves it idle at the edge.
func _release_crew_member(u, dest: Vector3) -> void:
	if not is_instance_valid(u):
		return
	if unit_manager != null:
		unit_manager.register(u)
	u.position = edge_spawn_position()
	u._sync_soa_pos()
	u.leave_garrison()
	if dest != Vector3.INF:
		u.order_move(dest)


func _prune_crew() -> void:
	var kept: Array = []
	for u in crew:
		if is_instance_valid(u) and u.state != Unit.State.DEAD and u.garrison_target == self:
			kept.append(u)
	crew = kept


## Admits own braves that have reached the entrance (State.GARRISON, waiting).
## Done in the building tick so removing them from the world does not mutate the
## live units list mid-iteration.
func _admit_arrived_crew() -> void:
	if unit_manager == null or upgrading or crew.size() >= crew_capacity():
		return
	for u in unit_manager.get_units_in_radius(center_world(), interact_range() + 0.5):
		if crew.size() >= crew_capacity():
			break
		if u.state == Unit.State.GARRISON and u.garrison_target == self \
				and u.garrison_reached and not u.garrison_housed:
			admit_crew(u)


# --- Growth maintenance --------------------------------------------------------

## Target crew size: the manual override when set, else the owning tribe's
## growth mode.
func _crew_target() -> int:
	if upgrading:
		return 0   # the whole crew is out on the upgrade
	if manual_crew_override >= 0:
		return clampi(manual_crew_override, 0, crew_capacity())
	if tribe == null:
		return 0
	match tribe.growth_mode:
		Tribe.GrowthMode.MINIMAL: return 1
		Tribe.GrowthMode.MAXIMUM: return crew_capacity()
		_: return 0   # NONE


## Keeps the crew at the target: ejects excess (mode lowered / NONE) or pulls
## nearby idle braves in (up to the deficit). Braves are only pulled when they
## are close — huts far from any idle brave can stay empty even at MAXIMUM.
func _tick_growth() -> void:
	if tribe == null or unit_manager == null or not is_usable():
		return
	var target: int = _crew_target()
	_prune_crew()
	if crew.size() > target:
		while crew.size() > target:
			eject_crew(crew.size() - 1)
		return
	var deficit: int = target - crew.size() - _incoming_crew_count()
	while deficit > 0:
		var brave: Unit = _find_idle_brave_near()
		if brave == null:
			return
		brave.order_man_hut(self)
		deficit -= 1


## Braves currently walking toward THIS hut to be admitted (not yet housed).
func _incoming_crew_count() -> int:
	var n: int = 0
	for u in unit_manager.get_units_in_radius(center_world(), MAN_RADIUS + 4.0):
		if u.state == Unit.State.GARRISON and u.garrison_target == self \
				and not u.garrison_housed:
			n += 1
	return n


## Nearest own idle brave within MAN_RADIUS that has no other task/destination.
func _find_idle_brave_near() -> Unit:
	var best: Unit = null
	var best_d: float = INF
	var here: Vector3 = center_world()
	for u in unit_manager.get_units_in_radius(here, MAN_RADIUS):
		if u.tribe_id != tribe_id or u.unit_kind() != &"brave":
			continue
		if u.state != Unit.State.IDLE or not u.can_take_orders():
			continue
		if u.garrison_target != null:
			continue
		var d: float = Vector2(u.position.x - here.x, u.position.z - here.z).length_squared()
		if d < best_d:
			best_d = d
			best = u
	return best


# --- Production ----------------------------------------------------------------

## Spawn speed factor = crew count (10f: linear, no full-crew bonus). One worker
## needs HUT_SPAWN_SECONDS_PER_WORKER seconds per brave, six need a sixth of that.
func _spawn_rate_factor() -> float:
	return float(crew.size())


## Progress toward the next brave (drives the bar above the hut); -1 while under
## construction/damaged, unmanned, or when the tribe is at its population cap.
## While upgrading the bar shows the upgrade instead (Building._update_overlay).
func production_progress() -> float:
	if not is_usable() or tribe == null or crew.is_empty() or paused:
		return -1.0
	if tribe.population() >= tribe.housing_capacity() or tribe.at_unit_cap():
		return -1.0
	return clampf(1.0 - spawn_timer / Balance.HUT_SPAWN_SECONDS_PER_WORKER, 0.0, 1.0)


## Estimated growth this hut contributes, in braves per minute (sidebar readout).
func growth_per_minute() -> float:
	if not is_usable() or tribe == null or crew.is_empty() or paused:
		return 0.0
	if tribe.population() >= tribe.housing_capacity() or tribe.at_unit_cap():
		return 0.0
	return _spawn_rate_factor() / Balance.HUT_SPAWN_SECONDS_PER_WORKER * 60.0


## Spawns braves while manned and below the housing / hard cap. The timer only
## advances with crew (scaled by crew count), so an empty hut never produces.
func _tick_active(delta: float) -> void:
	if tribe == null or unit_manager == null:
		return
	_prune_crew()
	_admit_arrived_crew()
	# Upgrade bookkeeping runs BEFORE the crew early-outs: the due timer must keep
	# filling in an empty hut, and a due upgrade must be able to start there.
	_tick_upgrade_timer(delta)
	_growth_timer -= delta
	if _growth_timer <= 0.0:
		_growth_timer = GROWTH_INTERVAL
		_tick_growth()
	if crew.is_empty() or paused:
		spawn_timer = Balance.HUT_SPAWN_SECONDS_PER_WORKER
		return
	if tribe.population() >= tribe.housing_capacity() or tribe.at_unit_cap():
		spawn_timer = Balance.HUT_SPAWN_SECONDS_PER_WORKER
		return
	spawn_timer -= delta * _spawn_rate_factor()
	if spawn_timer <= 0.0:
		spawn_timer += Balance.HUT_SPAWN_SECONDS_PER_WORKER
		_spawn_brave()


## New braves spawn at the entrance (slightly scattered) and walk to a slot in
## the usual 6-member group formation around the rally point, so they gather in
## packs there instead of standing around at random. A rally point set onto a
## training building instead sends them straight into its training queue.
func _spawn_brave() -> void:
	var pos: Vector3 = edge_spawn_position() \
		+ TribeCommands.formation_offset(_spawn_counter % 7) * 0.35
	var brave: Unit = unit_manager.spawn_unit(BRAVE_SCENE, tribe_id, pos)
	if brave != null:
		var camp: TrainingBuilding = rally_training_building()
		if camp != null:
			(brave as Brave).order_train(camp)
		elif rally_point != Vector3.ZERO:
			# Slot cycles through a few groups so the pack stays near the rally.
			brave.order_move(rally_point + TribeCommands.group_slot_offset(_spawn_counter % 36))
	_spawn_counter += 1


# --- Upgrade (phase 10f) -------------------------------------------------------
# The hut grows in four stages. A timer makes an upgrade DUE; once it is allowed
# and wood is in reach, the whole crew leaves the hut, fetches
# HUT_UPGRADE_WOOD_COST wood and builds — the hut then produces nothing (its crew
# is out) but keeps its housing, because `upgrading` deliberately does NOT flip
# is_usable().
#
# The work itself reuses the repair pipeline: Brave.Task.UPGRADE is structurally
# the same as Task.REPAIR, and the delivered wood is absorbed from ground piles
# at the entrance by Building._tick_upgrade_absorb.

## Seconds since completion / since the last upgrade, capped at HUT_UPGRADE_DELAY
## — the "progress" visibly stops at 100 % while an upgrade is due but blocked.
var _upgrade_timer: float = 0.0
## Work done on the running upgrade, 0..1.
var _upgrade_work: float = 0.0


## True when the next stage is due: the timer is full and there IS a next stage.
## Stays true while the upgrade is blocked (tribe lock, pause, no wood).
func upgrade_ready() -> bool:
	return upgrade_stage < Balance.HUT_MAX_UPGRADE_STAGE \
		and _upgrade_timer >= Balance.HUT_UPGRADE_DELAY


## All conditions for STARTING the building work. Repair has priority (a damaged
## hut is not `is_usable()` anyway, but the full-health test also keeps an
## almost-repaired hut from jumping the queue); `paused` gives the player a
## per-hut lock on top of the tribe-wide one.
func can_begin_upgrade() -> bool:
	return upgrade_ready() and not upgrading and not demolishing and is_usable() \
		and not paused and health >= max_health \
		and tribe != null and tribe.upgrades_allowed \
		and _upgrade_wood_reachable()


## Fills the due timer and starts the work when everything lines up. Called from
## _tick_active BEFORE the crew early-outs, so an empty hut still upgrades.
func _tick_upgrade_timer(delta: float) -> void:
	if upgrading or upgrade_stage >= Balance.HUT_MAX_UPGRADE_STAGE:
		return
	_upgrade_timer = minf(_upgrade_timer + delta, Balance.HUT_UPGRADE_DELAY)
	if can_begin_upgrade():
		begin_upgrade()


## Is there any wood the crew could actually fetch nearby? Without this the hut
## would eject its crew into a hopeless search. Headless (no managers at all) is
## permissive so tests stay stable.
func _upgrade_wood_reachable() -> bool:
	var tm: TreeManager = unit_manager.tree_manager if unit_manager != null else null
	if tm != null and tm.count_trees_near(center_world(),
			Balance.HUT_UPGRADE_WOOD_RADIUS) > 0:
		return true
	if wood_pile_manager != null and wood_pile_manager.wood_in_radius(
			center_world(), Balance.HUT_UPGRADE_WOOD_RADIUS) > 0:
		return true
	if tribe != null:
		for b: Building in tribe.buildings:
			if not is_instance_valid(b) or not (b is WoodDepot) or not b.is_usable():
				continue
			if (b as WoodDepot).stored_wood() <= 0:
				continue
			if b.center_world().distance_to(center_world()) \
					<= Balance.HUT_UPGRADE_WOOD_RADIUS:
				return true
	if tm == null and wood_pile_manager == null:
		return true   # headless: nothing to judge by
	return false


## Starts the building work: the WHOLE crew leaves and goes on the job. Released
## gently via _release_crew_member (not eject_occupants — that shoves and rolls
## them, which is for storms and damage, not for a construction detail).
func begin_upgrade() -> void:
	if upgrading or upgrade_stage >= Balance.HUT_MAX_UPGRADE_STAGE:
		return
	upgrading = true
	upgrade_wood = 0
	_upgrade_work = 0.0
	_upgrade_stall_timer = 0.0
	# A wood-stalled hut would keep its own workers away; the upgrade re-checks.
	wood_stalled = false
	_prune_crew()
	var released: Array = crew.duplicate()
	crew.clear()
	for u in released:
		_release_crew_member(u, Vector3.INF)
		if u is Brave:
			(u as Brave).order_upgrade(self)


func upgrade_wood_missing() -> int:
	if not upgrading:
		return 0
	return maxi(0, Balance.HUT_UPGRADE_WOOD_COST - upgrade_wood)


func wants_upgrade_wood() -> bool:
	return upgrading and upgrade_wood_missing() > wood_incoming()


func upgrade_progress() -> float:
	return _upgrade_work if upgrading else -1.0


## Cap on the work, proportional to the wood delivered so far (mirrors
## progress_cap() for construction) — the bar cannot outrun the material.
func _upgrade_progress_cap() -> float:
	if Balance.HUT_UPGRADE_WOOD_COST <= 0:
		return 1.0
	return float(upgrade_wood) / float(Balance.HUT_UPGRADE_WOOD_COST)


## Applies `amount` of upgrade work. False = blocked by missing wood, the worker
## then fetches more.
func work_upgrade(amount: float) -> bool:
	if not upgrading or demolishing or _destroyed:
		return false
	var cap: float = _upgrade_progress_cap()
	if _upgrade_work >= cap - 0.0001:
		return false
	_upgrade_work = clampf(_upgrade_work + amount, 0.0, cap)
	_upgrade_stall_timer = 0.0
	if _upgrade_work >= 1.0:
		_finish_upgrade()
	return true


## Next stage reached: bigger, tougher, and worth more on demolition. The workers
## release themselves on the next tick (Brave._job_active goes false) and the
## growth control pulls them back in as crew, because crew_capacity() has grown.
func _finish_upgrade() -> void:
	upgrade_stage = mini(upgrade_stage + 1, Balance.HUT_MAX_UPGRADE_STAGE)
	max_health = Balance.HUT_HP_PER_STAGE[upgrade_stage]
	health = max_health
	# The upgrade wood becomes part of the building's price: the demolition refund
	# (_demolish_refund_base) reads wood_cost, so without this the player would
	# lose up to 20 wood per fully upgraded hut. It also raises the repair cost.
	wood_cost += Balance.HUT_UPGRADE_WOOD_COST
	upgrade_wood = 0
	_upgrade_work = 0.0
	_upgrade_timer = 0.0
	_upgrade_stall_timer = 0.0
	upgrading = false
	# A manual override from a smaller stage must not survive as a wrong number.
	if manual_crew_override >= 0:
		manual_crew_override = clampi(manual_crew_override, 0, crew_capacity())
	_rebuild_visuals()
	if tribe != null:
		tribe.notify_housing_changed()


## Aborts the running upgrade and drops the delivered wood at the site. The
## upgrade stays DUE (timer full), so it retries once the cause is gone.
func cancel_upgrade(restart_delay: bool = false) -> void:
	if not upgrading:
		return
	var back: int = upgrade_wood
	abandon_upgrade()
	if restart_delay:
		# Stall case: the wood going back on the ground would otherwise satisfy
		# _upgrade_wood_reachable() again right away and restart the upgrade on the
		# next tick, forever. Wait the full delay before trying again.
		_upgrade_timer = 0.0
	_refund_wood(back)


## Drops the upgrade without paying the wood back (demolition folds it into its
## own refund, destruction loses it).
func abandon_upgrade() -> void:
	upgrading = false
	upgrade_wood = 0
	_upgrade_work = 0.0
	_upgrade_stall_timer = 0.0
	_upgrade_timer = Balance.HUT_UPGRADE_DELAY


# --- Crew overlay (world-space pips) -------------------------------------------
# The pip overlay itself lives in Building (all crew buildings share it); the
# hut just reports its manning to it.

func crew_display_capacity() -> int:
	return crew_capacity()


func crew_display_filled() -> int:
	return crew_count()


## Stage 0 keeps the plain "hut" kind (existing assets/textures stay valid); the
## upgraded stages get their own model and damage/build texture set.
func asset_kind() -> StringName:
	return &"hut" if upgrade_stage == 0 else StringName("hut%d" % upgrade_stage)


## Grows with the stage, like the placeholder does (walls 1.6..3.0 m plus roof).
func _click_body_height() -> float:
	return 2.5 + 0.5 * float(upgrade_stage)


## Authored with the entrance facing south (+z); the mesh root is rotated by
## the Building base according to `orientation`.
##
## The placeholder GROWS with the upgrade stage (10f): the body gets taller and
## wider, the roof rides higher, and from stage 3 on there is a side annex. The
## footprint stays 4x4 — the hut gains height and bulk, not ground. Without this
## the five stages would be visually identical as long as no .glb models exist.
func _create_visuals() -> void:
	super._create_visuals()
	if _has_custom_model:
		return
	var stage: float = float(upgrade_stage)
	var wide: float = 0.78 + 0.05 * stage          # 0.78 .. 0.98 of the footprint
	var tall: float = 1.6 + 0.35 * stage           # 1.6 .. 3.0 m walls
	var w: float = float(footprint.x) * wide
	var d: float = float(footprint.y) * wide

	var body: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(w, tall, d)
	body.mesh = box
	body.material_override = _make_material(Color(0.52, 0.36, 0.2))
	body.position.y = tall * 0.5
	_mesh_root.add_child(body)

	var roof: MeshInstance3D = MeshInstance3D.new()
	var prism: PrismMesh = PrismMesh.new()
	# Flush with the walls (no overhang) so it does not clip the heads of
	# braves standing right at the hut.
	prism.size = Vector3(w, 1.2 + 0.15 * stage, d)
	roof.mesh = prism
	roof.material_override = _make_material(Color(0.42, 0.26, 0.12))
	roof.position.y = tall + 0.6 + 0.075 * stage
	_mesh_root.add_child(roof)

	# From stage 3 on: a lower annex on the west side, so the late stages read as
	# a compound rather than just a taller box.
	if upgrade_stage >= 3:
		var annex: MeshInstance3D = MeshInstance3D.new()
		var annex_box: BoxMesh = BoxMesh.new()
		annex_box.size = Vector3(w * 0.45, tall * 0.6, d * 0.7)
		annex.mesh = annex_box
		annex.material_override = _make_material(Color(0.48, 0.33, 0.18))
		annex.position = Vector3(-(w * 0.5 + w * 0.2), tall * 0.3, 0.0)
		_mesh_root.add_child(annex)

	# Entrance door on the south side — on the wall face, which moves outward with
	# the stage.
	var door: MeshInstance3D = MeshInstance3D.new()
	var door_box: BoxMesh = BoxMesh.new()
	door_box.size = Vector3(0.8, 1.2, 0.15)
	door.mesh = door_box
	door.material_override = _make_material(Color(0.2, 0.13, 0.07))
	door.position = Vector3(0.0, 0.6, d * 0.5)
	_mesh_root.add_child(door)

	_add_flag()
