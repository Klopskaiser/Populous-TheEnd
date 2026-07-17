class_name Watchtower extends Building

## Wachturm (phase 7h): a small-footprint, tall building (4 wood) with two crew
## slots for combat units and the shaman — never braves. Stationed occupants are
## removed from the world (protected reserve): they are NOT a valid target for
## fireballs or preacher conversion while inside.
##
## Ranged crew fight FROM the tower with +3 m range (TOWER_RANGE_BONUS):
##   - Firewarrior: lobs fireballs from the platform at enemies in FIRE_RANGE+3.
##   - Preacher: converts enemies within CONVERT_RANGE+3 (tower-driven channel).
##   - Shaman: casts via the spell bar at cast_range+3 from the tower (handled in
##     Shaman.order_cast) — she never leaves.
##   - Warrior: NO action and NO bonus (user decision) — a protected reserve that
##     only fights once thrown out by a storm, then with normal warrior stats.
##
## The tower is the coordinator: housed crew have no world tick of their own.
## Only a USABLE tower keeps its crew — any damage stage (>= 1) or destruction
## ejects them (base _on_disabled / destroy), and the 7g melee storm throws them
## out alive first (has_occupants -> begin_storm). Storming the tower is harder:
## max 5 melee raiders instead of 15.

const WOOD_COST: int = Balance.WATCHTOWER_WOOD_COST
const FOOTPRINT: Vector2i = Vector2i(2, 2)
const MAX_HEALTH: int = Balance.WATCHTOWER_HP
## Crew slots (combat units / shaman).
const CREW_CAPACITY: int = 2
## Extra range granted to ranged crew (fire / conversion / spells).
const TOWER_RANGE_BONUS: float = Balance.WATCHTOWER_RANGE_BONUS
## Fewer melee raiders fit (a tower is tougher to storm than a hut).
const TOWER_MAX_RAIDERS: int = Balance.WATCHTOWER_MAX_RAIDERS
## Height above the origin the crew fire/act from (platform level).
const PLATFORM_Y: float = 4.0
## Y (above the tower base) the crew sprites STAND at — on top of the platform,
## visibly manning the tower.
const PLATFORM_STAND_Y: float = 4.75

const C_SHAFT: Color = Color(0.5, 0.48, 0.44)
const C_PLATFORM: Color = Color(0.42, 0.3, 0.16)
const C_DOOR: Color = Color(0.16, 0.11, 0.06)

## Stationed units (combat / shaman), removed from the world. Untyped like the
## other occupant registries (entries may be freed).
var crew: Array = []
## Per-firewarrior fire cooldown (unit -> seconds remaining).
var _fire_cd: Dictionary = {}
## Per-preacher conversion channel: preacher -> {"target": Unit, "left": float}.
var _convert_state: Dictionary = {}


func _init() -> void:
	wood_cost = WOOD_COST
	footprint = FOOTPRINT
	max_health = MAX_HEALTH
	health = MAX_HEALTH


func display_name() -> String:
	return "Wachturm"


func housing_capacity() -> int:
	return 0


## The tower is tall — the click/selection box must cover the whole structure so
## clicks on the upper shaft/platform still select it.
func _click_body_height() -> float:
	return 5.5


## A tower is tougher to storm: only 5 melee raiders fit.
func max_melee_raiders() -> int:
	return TOWER_MAX_RAIDERS


# --- Crew (garrison) -----------------------------------------------------------

## Housed crew are storm occupants (thrown out alive when the storm begins).
func has_occupants() -> bool:
	_prune_crew()
	return not crew.is_empty()


func crew_count() -> int:
	_prune_crew()
	return crew.size()


func has_crew_room() -> bool:
	_prune_crew()
	return is_usable() and crew.size() < CREW_CAPACITY


## Only own combat units and the shaman may garrison (no braves / siege).
func _crew_eligible(unit) -> bool:
	return is_instance_valid(unit) and unit.state != Unit.State.DEAD \
		and unit.tribe_id == tribe_id and unit.can_garrison()


## Admits a unit as crew: it stays in the world, VISIBLE on the platform, but is
## a protected reserve (non-targetable) fully driven by the tower. Refused when
## full, unusable or the unit is not eligible.
func admit_crew(unit) -> bool:
	_prune_crew()
	if unit in crew:
		return true
	if not is_usable() or crew.size() >= CREW_CAPACITY:
		return false
	if not _crew_eligible(unit):
		return false
	var slot: int = crew.size()
	crew.append(unit)
	unit.enter_garrison(self, crew_slot_position(slot))
	return true


## World position of the index-th crew slot, standing on top of the platform.
func crew_slot_position(index: int) -> Vector3:
	var c: Vector3 = center_world()
	var off_x: float = -0.45 if index == 0 else 0.45
	return Vector3(c.x + off_x, c.y + PLATFORM_STAND_Y, c.z)


## Admits own units waiting at the entrance (State.GARRISON, garrison_reached).
## Runs in the building tick so removing them from the world does not mutate the
## live units list mid-iteration (same rationale as the training queue).
func _admit_arrived_crew() -> void:
	if unit_manager == null or crew.size() >= CREW_CAPACITY:
		return
	for u in unit_manager.get_units_in_radius(center_world(), interact_range() + 0.5):
		if crew.size() >= CREW_CAPACITY:
			break
		if u.state == Unit.State.GARRISON and u.garrison_target == self \
				and u.garrison_reached:
			admit_crew(u)


## Drops freed/dead crew and any that no longer point here (safety net).
func _prune_crew() -> void:
	var kept: Array = []
	for u in crew:
		if is_instance_valid(u) and u.state != Unit.State.DEAD and u.garrison_target == self:
			kept.append(u)
	if kept.size() != crew.size():
		var still: Dictionary = {}
		for u in kept:
			still[u] = true
		for key in _fire_cd.keys():
			if not still.has(key):
				_fire_cd.erase(key)
		for key in _convert_state.keys():
			if not still.has(key):
				_convert_state.erase(key)
	crew = kept


## Ejects all crew: `killed` (ranged stage-1 fire) flings them out dead at the
## door; otherwise they are shoved out alive (melee storm / spell disable).
func eject_occupants(killed: bool) -> void:
	_eject_all(killed, Vector3.INF)


## Sidebar eject (7h): the slot-`index` crew member steps out ALIVE at the
## perimeter and, if a rally/delivery point is set, walks there. Same idea as
## the forester/workshop worker eject.
func eject_crew(index: int) -> void:
	_prune_crew()
	if index < 0 or index >= crew.size():
		return
	var u = crew[index]
	crew.remove_at(index)
	_fire_cd.erase(u)
	_convert_state.erase(u)
	if not is_instance_valid(u):
		return
	if unit_manager != null:
		unit_manager.register(u)   # idempotent — crew stayed registered
	u.position = edge_spawn_position()
	u.leave_garrison()
	if rally_point != Vector3.ZERO:
		u.order_move(rally_point)


func _eject_all(killed: bool, dest: Vector3) -> void:
	for u in crew.duplicate():
		if not is_instance_valid(u):
			continue
		if unit_manager != null:
			unit_manager.register(u)
		u.position = edge_spawn_position()
		u.leave_garrison()
		if dest != Vector3.INF and not killed:
			u.order_move(dest)
		else:
			_eject_unit(u, killed)   # killed -> dies at the door, else shoved out
	crew.clear()
	_fire_cd.clear()
	_convert_state.clear()


func destroy() -> void:
	_eject_all(false, Vector3.INF)
	super.destroy()


# --- Crew range bonus (tower coordinates its ranged crew) ----------------------

## Drives the crew (they have no world tick of their own): pins them to their
## platform slot and, for ranged crew, auto-fires/converts at anything within
## the +3 m reach WITHOUT moving. Warriors/shaman just stand (a garrisoned
## warrior never attacks — it is a protected reserve). Only runs while the tower
## is usable and not being demolished (base tick() gate).
func _tick_active(delta: float) -> void:
	_prune_crew()
	_admit_arrived_crew()   # admitted here (building tick), not in the unit loop
	if crew.is_empty() or unit_manager == null:
		return
	for i in range(crew.size()):
		var u = crew[i]
		u.position = crew_slot_position(i)   # pin visibly to the platform slot
		match u.unit_kind():
			&"firewarrior":
				_tick_crew_firewarrior(u, delta)
			&"preacher":
				_tick_crew_preacher(u, delta)
			_:
				_set_crew_anim(u, &"idle")   # warrior / shaman: stand, no auto action


func _tick_crew_firewarrior(fw, delta: float) -> void:
	var cd: float = float(_fire_cd.get(fw, 0.0)) - delta
	var origin: Vector3 = fw.position   # fires from the platform slot
	var reach: float = Firewarrior.FIRE_RANGE + TOWER_RANGE_BONUS
	var target: Unit = _nearest_enemy(origin, reach)
	if target == null:
		_fire_cd[fw] = 0.0
		_set_crew_anim(fw, &"idle")
		return
	fw.facing = _flat_dir(origin, target.position)
	_set_crew_anim(fw, &"throw")
	if cd <= 0.0:
		cd = Firewarrior.FIRE_COOLDOWN
		fw.anim_start_ms = Time.get_ticks_msec()   # sync the throw with the shot
		fw.fire_from(origin, target)
	_fire_cd[fw] = cd


func _tick_crew_preacher(pr, delta: float) -> void:
	var origin: Vector3 = pr.position
	var reach: float = Preacher.CONVERT_RANGE + TOWER_RANGE_BONUS
	var st: Dictionary = _convert_state.get(pr, {})
	var target = st.get("target")
	# Keep channeling the current target while it stays convertible and in range.
	if target == null or not is_instance_valid(target) or target.state == Unit.State.DEAD \
			or target.tribe_id == tribe_id or target.is_conversion_immune() \
			or _flat_dist(origin, target.position) > reach:
		target = _nearest_convertible(origin, reach)
		if target == null:
			_convert_state.erase(pr)
			_set_crew_anim(pr, &"idle")
			return
		st = {"target": target,
			"left": randf_range(Preacher.CONVERT_TIME_MIN, Preacher.CONVERT_TIME_MAX)}
	pr.facing = _flat_dir(origin, target.position)
	_set_crew_anim(pr, &"cast")
	st["left"] = float(st.get("left", 0.0)) - delta
	if st["left"] <= 0.0:
		if pr.tribe != null:
			target.convert_to_tribe(pr.tribe)
		_convert_state.erase(pr)
		return
	_convert_state[pr] = st


## Sets a crew member's animation (they do not tick themselves, so the tower
## drives their anim state directly for the renderer).
func _set_crew_anim(u, base: StringName) -> void:
	if u.anim_base_name != base:
		u.anim_base_name = base
		u.anim_start_ms = Time.get_ticks_msec()


func _flat_dir(from: Vector3, to: Vector3) -> Vector3:
	var d: Vector3 = Vector3(to.x - from.x, 0.0, to.z - from.z)
	return d.normalized() if d.length_squared() > 0.000001 else Vector3(0.0, 0.0, 1.0)


## Nearest living, targetable enemy within `radius` of `origin`.
func _nearest_enemy(origin: Vector3, radius: float) -> Unit:
	var best: Unit = null
	var best_d: float = radius
	for u in unit_manager.get_units_in_radius(origin, radius):
		if u.tribe_id == tribe_id or u.state == Unit.State.DEAD or not u.is_targetable():
			continue
		var d: float = _flat_dist(origin, u.position)
		if d <= best_d:
			best_d = d
			best = u
	return best


## Nearest living, convertible enemy within `radius` of `origin`.
func _nearest_convertible(origin: Vector3, radius: float) -> Unit:
	var best: Unit = null
	var best_d: float = radius
	for u in unit_manager.get_units_in_radius(origin, radius):
		if u.tribe_id == tribe_id or u.state == Unit.State.DEAD \
				or u.is_conversion_immune() or not u.is_targetable():
			continue   # not_targetable covers a protected reserve in another tower
		var d: float = _flat_dist(origin, u.position)
		if d <= best_d:
			best_d = d
			best = u
	return best


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


# --- Visuals (placeholder) -----------------------------------------------------

## A tall slim tower: a stone shaft, a wider timber lookout platform on top, a
## dark doorway at the base (south) and the tribe flag. Authored entrance south.
func asset_kind() -> StringName:
	return &"watchtower"


func _create_visuals() -> void:
	super._create_visuals()
	if _has_custom_model:
		return
	var span: float = float(FOOTPRINT.x)

	var shaft: MeshInstance3D = MeshInstance3D.new()
	var sbox: BoxMesh = BoxMesh.new()
	sbox.size = Vector3(span * 0.6, 4.2, span * 0.6)
	shaft.mesh = sbox
	shaft.material_override = _make_material(C_SHAFT)
	shaft.position.y = 2.1
	_mesh_root.add_child(shaft)

	var platform: MeshInstance3D = MeshInstance3D.new()
	var pbox: BoxMesh = BoxMesh.new()
	pbox.size = Vector3(span * 0.9, 0.7, span * 0.9)
	platform.mesh = pbox
	platform.material_override = _make_material(C_PLATFORM)
	platform.position.y = 4.4
	_mesh_root.add_child(platform)

	# Crenellations: four small merlons at the platform corners.
	for sx in [-span * 0.32, span * 0.32]:
		for sz in [-span * 0.32, span * 0.32]:
			var merlon: MeshInstance3D = MeshInstance3D.new()
			var mbox: BoxMesh = BoxMesh.new()
			mbox.size = Vector3(0.28, 0.5, 0.28)
			merlon.mesh = mbox
			merlon.material_override = _make_material(C_PLATFORM)
			merlon.position = Vector3(sx, 5.0, sz)
			_mesh_root.add_child(merlon)

	# Dark doorway at the base, south side.
	var door: MeshInstance3D = MeshInstance3D.new()
	var dbox: BoxMesh = BoxMesh.new()
	dbox.size = Vector3(0.6, 1.1, 0.2)
	door.mesh = dbox
	door.material_override = _make_material(C_DOOR)
	door.position = Vector3(0.0, 0.55, span * 0.3)
	_mesh_root.add_child(door)

	_add_flag()
