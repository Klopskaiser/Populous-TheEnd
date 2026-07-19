class_name Hut extends Building

## Hut: houses population and spawns new Braves over time. Phase 7i: a hut only
## produces while it is MANNED — up to 4 brave crew (hidden inside, still counted
## in the population, no mana cost). Production rate scales with crew; a full hut
## is ~10% faster than the old flat rate, an empty hut produces nothing. Crew are
## pulled in automatically from nearby idle braves according to the tribe's
## growth mode (NONE / MINIMAL / MAXIMUM), or manned manually by right-clicking
## the hut with braves selected. Built by braves: foundation flattening first,
## then construction with delivered wood.

const WOOD_COST: int = Balance.HUT_WOOD_COST
const FOOTPRINT: Vector2i = Balance.HUT_FOOTPRINT
const CAPACITY: int = Balance.HUT_CAPACITY
const SPAWN_INTERVAL: float = Balance.HUT_SPAWN_INTERVAL   # s per brave at full crew
## Crew slots (production workers, braves only).
const CREW_CAPACITY: int = Balance.HUT_CREW_CAPACITY
## A full hut produces this much faster than the old flat SPAWN_INTERVAL rate.
const FULL_CREW_BONUS: float = Balance.HUT_FULL_CREW_BONUS
## Idle braves within this radius are auto-pulled to man the hut.
const MAN_RADIUS: float = 16.0
## Growth maintenance throttle.
const GROWTH_INTERVAL: float = 1.0

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")

var spawn_timer: float = SPAWN_INTERVAL
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


func _init() -> void:
	wood_cost = WOOD_COST
	footprint = FOOTPRINT
	max_health = Balance.HUT_HP
	health = max_health


func display_name() -> String:
	return "Hütte"


## Damaged huts (stage >= 1) house nobody until repaired.
func housing_capacity() -> int:
	return CAPACITY if is_usable() else 0


# --- Crew (production workers, phase 7i) ---------------------------------------

func crew_count() -> int:
	_prune_crew()
	return crew.size()


func has_crew_room() -> bool:
	_prune_crew()
	return is_usable() and crew.size() < CREW_CAPACITY


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
	if not is_usable() or crew.size() >= CREW_CAPACITY or not _crew_eligible(unit):
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
	if unit_manager == null or crew.size() >= CREW_CAPACITY:
		return
	for u in unit_manager.get_units_in_radius(center_world(), interact_range() + 0.5):
		if crew.size() >= CREW_CAPACITY:
			break
		if u.state == Unit.State.GARRISON and u.garrison_target == self \
				and u.garrison_reached and not u.garrison_housed:
			admit_crew(u)


# --- Growth maintenance --------------------------------------------------------

## Target crew size: the manual override when set, else the owning tribe's
## growth mode.
func _crew_target() -> int:
	if manual_crew_override >= 0:
		return clampi(manual_crew_override, 0, CREW_CAPACITY)
	if tribe == null:
		return 0
	match tribe.growth_mode:
		Tribe.GrowthMode.MINIMAL: return 1
		Tribe.GrowthMode.MAXIMUM: return CREW_CAPACITY
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

## Spawn speed factor from the crew count: 0 (empty) .. FULL_CREW_BONUS (full).
func _spawn_rate_factor() -> float:
	return FULL_CREW_BONUS * float(crew.size()) / float(CREW_CAPACITY)


## Progress toward the next brave (drives the bar above the hut); -1 while under
## construction/damaged, unmanned, or when the tribe is at its population cap.
func production_progress() -> float:
	if not is_usable() or tribe == null or crew.is_empty() or paused:
		return -1.0
	if tribe.population() >= tribe.housing_capacity() or tribe.at_unit_cap():
		return -1.0
	return clampf(1.0 - spawn_timer / SPAWN_INTERVAL, 0.0, 1.0)


## Estimated growth this hut contributes, in braves per minute (sidebar readout).
func growth_per_minute() -> float:
	if not is_usable() or tribe == null or crew.is_empty() or paused:
		return 0.0
	if tribe.population() >= tribe.housing_capacity() or tribe.at_unit_cap():
		return 0.0
	return _spawn_rate_factor() / SPAWN_INTERVAL * 60.0


## Spawns braves while manned and below the housing / hard cap. The timer only
## advances with crew (scaled by crew count), so an empty hut never produces.
func _tick_active(delta: float) -> void:
	if tribe == null or unit_manager == null:
		return
	_prune_crew()
	_admit_arrived_crew()
	_growth_timer -= delta
	if _growth_timer <= 0.0:
		_growth_timer = GROWTH_INTERVAL
		_tick_growth()
	if crew.is_empty() or paused:
		spawn_timer = SPAWN_INTERVAL
		return
	if tribe.population() >= tribe.housing_capacity() or tribe.at_unit_cap():
		spawn_timer = SPAWN_INTERVAL
		return
	spawn_timer -= delta * _spawn_rate_factor()
	if spawn_timer <= 0.0:
		spawn_timer += SPAWN_INTERVAL
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


# --- Crew overlay (world-space pips) -------------------------------------------
# The pip overlay itself lives in Building (all crew buildings share it); the
# hut just reports its manning to it.

func crew_display_capacity() -> int:
	return CREW_CAPACITY


func crew_display_filled() -> int:
	return crew_count()


func asset_kind() -> StringName:
	return &"hut"


## Authored with the entrance facing south (+z); the mesh root is rotated by
## the Building base according to `orientation`.
func _create_visuals() -> void:
	super._create_visuals()
	if _has_custom_model:
		return
	var body: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(float(footprint.x) * 0.85, 1.6, float(footprint.y) * 0.85)
	body.mesh = box
	body.material_override = _make_material(Color(0.52, 0.36, 0.2))
	body.position.y = 0.8
	_mesh_root.add_child(body)

	var roof: MeshInstance3D = MeshInstance3D.new()
	var prism: PrismMesh = PrismMesh.new()
	# Flush with the walls (no overhang) so it does not clip the heads of
	# braves standing right at the hut.
	prism.size = Vector3(float(footprint.x) * 0.85, 1.2, float(footprint.y) * 0.85)
	roof.mesh = prism
	roof.material_override = _make_material(Color(0.42, 0.26, 0.12))
	roof.position.y = 2.2
	_mesh_root.add_child(roof)

	# Entrance door on the south side.
	var door: MeshInstance3D = MeshInstance3D.new()
	var door_box: BoxMesh = BoxMesh.new()
	door_box.size = Vector3(0.8, 1.2, 0.15)
	door.mesh = door_box
	door.material_override = _make_material(Color(0.2, 0.13, 0.07))
	door.position = Vector3(0.0, 0.6, float(footprint.y) * 0.425)
	_mesh_root.add_child(door)

	_add_flag()
