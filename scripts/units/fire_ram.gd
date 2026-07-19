class_name FireRam extends CrewedVehicle

## Feuerramme: a pushable flame-thrower vehicle built by the fire-ram
## workshop.
##
## - Crew 1..4 (any unit except the shaman); ONE crew member both drives AND
##   fires. Slow (3 m/s) with a REAL turn rate: the hull slews toward the
##   facing at FIRERAM_TURN_RATE and the flame burst only starts once the
##   hull points at the target (sweeping DURING a burst is a feature).
## - Weapon: a forward flame burst — FLAME_DURATION seconds of flames over a
##   rectangle FIRE_RANGE long x FLAME_WIDTH wide in front of the hull, then
##   a crew-scaled reload. NO minimum range. Everything in the rectangle is
##   set alight: units get the no-contact-damage burn (Unit.scorch), wooden
##   vehicles ignite properly, buildings accrue lava-contact stage damage,
##   trees and wood piles catch fire. Friendly fire: flames burn everything
##   (consistent with lava and the catapult splash).
## - Crew is immune to ranged distraction (crew_defends_melee_only): being
##   shot at never pulls it off the vehicle — only direct melee pressure does.
## - Destruction/boarding/capture exactly like the catapult (CrewedVehicle).

const MAX_CREW: int = Balance.FIRERAM_MAX_CREW
const MIN_MOVE_CREW: int = Balance.FIRERAM_MIN_MOVE_CREW
const MIN_FIRE_CREW: int = Balance.FIRERAM_MIN_FIRE_CREW
const FIRE_RANGE: float = Balance.FIRERAM_FIRE_RANGE
## Units closer than this stand behind the nozzle — the ram holds its fire
## against them (buildings hugging the hull still burn fine).
const MIN_RANGE: float = Balance.FIRERAM_MIN_RANGE
const FLAME_WIDTH: float = Balance.FIRERAM_FLAME_WIDTH
const FLAME_DURATION: float = Balance.FIRERAM_FLAME_DURATION
const COOLDOWN_MIN_CREW: float = Balance.FIRERAM_COOLDOWN_MIN_CREW
const COOLDOWN_FULL_CREW: float = Balance.FIRERAM_COOLDOWN_FULL_CREW
const RAM_AGGRO: float = Balance.FIRERAM_AGGRO_RADIUS
const TURN_RATE: float = Balance.FIRERAM_TURN_RATE
const AIM_TOLERANCE: float = Balance.FIRERAM_AIM_TOLERANCE
## Flame area re-check cadence during a burst (LavaSurge rhythm).
const FLAME_CHECK_INTERVAL: float = 0.2
## Lava-contact credit per flame second on buildings — see Balance doc (the
## 1-s grace window between bursts would void raw contact seconds).
const FLAME_CONTACT_FACTOR: float = Balance.FIRERAM_FLAME_CONTACT_FACTOR
## Flame origin: this far in front of the hull centre.
const NOZZLE_OFFSET: float = 1.2

## Worker references (injected by UnitManager.spawn_unit via unit.set() — a
## silent no-op without these declarations; flames must ignite trees/piles).
var tree_manager = null
var wood_pile_manager = null

## Seconds of flame left in the running burst (0 = not flaming).
var _flame_time: float = 0.0
var _reload: float = 0.0
var _flame_check: float = 0.0
## Buildings already credited during the current check tick.
var _flamed_buildings: Dictionary = {}
## Hull heading, slewed toward `facing` at TURN_RATE (real turn inertia —
## `facing` itself snaps instantly everywhere in the codebase).
var _heading: Vector3 = Vector3(0, 0, 1)
## Flame cone visual meshes (in-game only, lazily built).
var _flame_cone: Node3D = null


func _init() -> void:
	super()
	speed = Balance.FIRERAM_SPEED
	max_crew = MAX_CREW
	min_move_crew = MIN_MOVE_CREW
	min_fire_crew = MIN_FIRE_CREW
	# 2 crew slots per side on the shorter hull.
	crew_side_offset = 0.9
	crew_rank_spacing = 1.0
	vehicle_ring_scale = 4.0
	vehicle_separation = 3.0


func unit_kind() -> StringName:
	return &"fireram"


## The ram may burn enemy GROUND vehicles (their hulls ignite); airships hover
## far above the flame cone.
func _may_target_vehicle(enemy: Unit) -> bool:
	return enemy is CrewedVehicle and not enemy.crew_rides_on_deck()


func crew_defends_melee_only() -> bool:
	return true


func aggro_radius() -> float:
	return RAM_AGGRO


## Hull heading with real turn inertia (the model rotates to this).
func _model_heading() -> Vector3:
	return _heading


# --- Orders & ticking ---------------------------------------------------------------

## Explicit attack order on a unit: clears a building focus; the base marks
## the target ORDERED so the ram chases it even beyond the flame range.
func order_attack(enemy: Unit) -> void:
	attack_building = null
	super.order_attack(enemy)


func tick(delta: float) -> void:
	_slew_heading(delta)
	_reload = maxf(_reload - delta, 0.0)
	# A started burst always finishes (even if the target died or the state
	# changed): the rectangle follows the CURRENT heading, so slow turning
	# sweeps the flames across the field.
	if _flame_time > 0.0 and state != State.DEAD:
		_flame_time -= delta
		_flame_check -= delta
		if _flame_check <= 0.0:
			_flame_check = FLAME_CHECK_INTERVAL
			_apply_flames()
		if _flame_time <= 0.0:
			_reload = flame_cooldown_for_crew(active_crew_count())
			_show_flame_cone(false)
	super.tick(delta)


## Rotates the hull toward `facing` at the fixed turn rate.
func _slew_heading(delta: float) -> void:
	var target: Vector3 = facing
	if target.length_squared() < 0.000001:
		return
	target = target.normalized()
	var cur: float = atan2(_heading.x, _heading.z)
	var want: float = atan2(target.x, target.z)
	var diff: float = wrapf(want - cur, -PI, PI)
	var step: float = TURN_RATE * delta
	if absf(diff) <= step:
		_heading = target
	else:
		var a: float = cur + signf(diff) * step
		_heading = Vector3(sin(a), 0.0, cos(a))


## Whether the hull points at `point` closely enough to open fire.
func _aimed_at(point: Vector3) -> bool:
	var to: Vector3 = Vector3(point.x - position.x, 0.0, point.z - position.z)
	if to.length_squared() < 0.000001:
		return true
	var cur: float = atan2(_heading.x, _heading.z)
	var want: float = atan2(to.x, to.z)
	return absf(wrapf(want - cur, -PI, PI)) <= AIM_TOLERANCE


## Auto target acquisition (idle + aggressive move): burn whatever is already
## inside the flame range (units first), otherwise roll toward the nearest
## enemy building within aggro — the catapult's proven "fire, don't chase"
## rule (auto unit targets are never chased; ordered ones are).
func _auto_acquire(delta: float) -> bool:
	if active_crew_count() < MIN_FIRE_CREW:
		return false
	if not _due_to_scan(delta):
		return false
	var u: Unit = _nearest_enemy_unit(FIRE_RANGE)
	if u != null:
		_begin_attack(u)   # auto: _target_ordered stays false (no chase)
		return true
	var b = _scan_enemy_building(RAM_AGGRO)
	if b != null:
		_set_building_target(b, true)   # keep the move route (resume after)
		return true
	return false


func _engage_on_sight(delta: float) -> bool:
	return _auto_acquire(delta)


func _tick_idle(delta: float) -> void:
	_auto_acquire(delta)


## Flame combat. A live unit target takes precedence over the building focus;
## a dead/gone target falls back to the building, then to re-acquisition.
func _tick_attack(delta: float) -> void:
	if active_crew_count() < MIN_MOVE_CREW:
		attack_building = null
		_end_attack()
		_set_state(State.IDLE)
		return
	if _unit_target_attackable(attack_target) and attack_target.tribe_id != tribe_id:
		_burn_unit(attack_target, delta)
		return
	if attack_target != null:
		_end_attack()
	if _building_target_valid():
		if _due_to_scan(delta):
			var u: Unit = _nearest_enemy_unit(FIRE_RANGE)
			if u != null:
				_begin_attack(u)
				return
		_burn_point(attack_building.center_world(), delta, true,
			attack_building.footprint_distance_to(
				Vector2(position.x, position.z)))
		return
	attack_building = null
	_retarget_or_idle()


## Re-acquisition after a lost target — same rule as _auto_acquire.
func _retarget_or_idle() -> void:
	_end_attack()
	if active_crew_count() >= MIN_FIRE_CREW:
		var u: Unit = _nearest_enemy_unit(FIRE_RANGE)
		if u != null:
			_begin_attack(u)
			return
		var b = _scan_enemy_building(RAM_AGGRO)
		if b != null:
			_set_building_target(b, true)
			return
	if not waypoint_queue.is_empty():
		attack_building = null
		_start_path_to(waypoint_queue[0])
		return
	attack_building = null
	_set_state(State.IDLE)


## Unit target: burn it while in the [MIN_RANGE, FIRE_RANGE] band; ORDERED
## targets are chased (slowly — at 3 m/s the ram pressures but rarely catches
## runners), auto targets are dropped once they leave the range. A unit that
## crept behind the nozzle is swapped for another in-band enemy (auto) or
## held without fire (ordered) — the catapult's minimum-range rule.
func _burn_unit(target: Unit, delta: float) -> void:
	var dist: float = _flat_dist(position, target.position)
	if dist > FIRE_RANGE:
		if not _target_ordered:
			_end_attack()
			_retarget_or_idle()
			return
		_in_melee = false
		_approach(target.position, delta)
		_face_point(target.position)
		return
	if dist < MIN_RANGE:
		if not _target_ordered and _due_to_scan(delta):
			var alt: Unit = _nearest_enemy_unit(FIRE_RANGE)
			if alt != null and alt != target:
				_begin_attack(alt)
				return
		if _has_path():
			_clear_path()
		_in_melee = true
		_face_point(target.position)
		return   # behind the nozzle — hold fire until it clears the minimum
	_burn_point(target.position, delta, false, dist)


## Stands (no minimum range) and burns toward a point: turn the hull, then
## open the burst once aimed and reloaded. `approach` closes the gap for
## far-away buildings. `dist` = flat distance to the target surface.
func _burn_point(target_pos: Vector3, delta: float, approach: bool,
		dist: float) -> void:
	if dist > FIRE_RANGE:
		if not approach:
			return
		_in_melee = false
		_approach(target_pos, delta)
		_face_point(target_pos)
		return
	if _has_path():
		_clear_path()
	_face_point(target_pos)
	_in_melee = true
	attack_anim = &"throw"
	if active_crew_count() < MIN_FIRE_CREW:
		return
	if _flame_time > 0.0 or _reload > 0.0:
		return
	if not _aimed_at(target_pos):
		return   # the hull is still turning toward the target
	_flame_time = FLAME_DURATION
	_flame_check = 0.0   # first area check right away
	_show_flame_cone(true)
	_play_sfx(&"siege_burning")


## Seconds of reload after a burst for a boarded crew of `count`
## (1 -> 3 s, 4 (full) -> 1.5 s, linear; below 1 there is no burst at all).
static func flame_cooldown_for_crew(count: int) -> float:
	if count < MIN_FIRE_CREW:
		return INF
	var t: float = float(clampi(count, MIN_FIRE_CREW, MAX_CREW) - MIN_FIRE_CREW) \
		/ float(MAX_CREW - MIN_FIRE_CREW)
	return lerpf(COOLDOWN_MIN_CREW, COOLDOWN_FULL_CREW, t)


## Nearest enemy unit inside the flame range that the ram may burn (its
## splash-like flames do not care about conversion trances — like the
## catapult, no SIT skip).
func _nearest_enemy_unit(max_range: float) -> Unit:
	if path_service == null:
		return null
	var best: Unit = null
	var best_d: float = max_range
	for u in path_service.get_units_in_radius(position, max_range, SCAN_MAX_CANDIDATES):
		if u == self or u.state == State.DEAD or u.tribe_id == tribe_id:
			continue
		if not u.is_targetable() and not _may_target_vehicle(u):
			continue
		if u.is_airborne():
			continue   # flames stay on the ground
		var d: float = _flat_dist(position, u.position)
		if d < MIN_RANGE or d > max_range:
			continue   # behind the nozzle — cannot be burnt
		if d < best_d:
			best_d = d
			best = u
	return best


# --- Flame area -----------------------------------------------------------------------

## One area check of the running burst: everything inside the FIRE_RANGE x
## FLAME_WIDTH rectangle in front of the hull catches fire. Runs every
## FLAME_CHECK_INTERVAL while the burst lasts; the rectangle follows the
## CURRENT hull heading (sweeping).
func _apply_flames() -> void:
	var forward: Vector3 = _heading.normalized() if _heading.length_squared() > 0.0 \
		else Vector3(0, 0, 1)
	var right: Vector3 = Vector3(-forward.z, 0.0, forward.x)
	var origin: Vector3 = position + forward * NOZZLE_OFFSET
	var half_width: float = FLAME_WIDTH * 0.5
	# Units: broad-phase radius around the rectangle centre, narrow-phase in
	# the heading frame. Friendly fire on purpose (flames know no friends).
	if path_service != null:
		var centre: Vector3 = origin + forward * (FIRE_RANGE * 0.5)
		var broad: float = FIRE_RANGE * 0.5 + half_width + 0.5
		for u in path_service.get_units_in_radius(centre, broad):
			if u == self or u.state == State.DEAD:
				continue
			if u.state == State.THROWN or u.rides_airborne():
				continue   # airborne units pass over the flames
			var rel: Vector3 = u.position - origin
			var along: float = rel.x * forward.x + rel.z * forward.z
			var side: float = rel.x * right.x + rel.z * right.z
			if along < 0.0 or along > FIRE_RANGE or absf(side) > half_width:
				continue
			u.scorch(origin)
	# Buildings: sample the rectangle's centreline; one lava-contact credit
	# per building per check (FLAME_CONTACT_FACTOR beats the grace window).
	_flamed_buildings.clear()
	if building_manager != null:
		for i in range(int(FIRE_RANGE)):
			var sample: Vector3 = origin + forward * (0.5 + float(i))
			var flat: Vector2 = Vector2(sample.x, sample.z)
			for b in building_manager.buildings:
				if not is_instance_valid(b) or b.health <= 0 \
						or _flamed_buildings.has(b):
					continue
				if b.footprint_distance_to(flat) <= half_width:
					_flamed_buildings[b] = true
					b.add_lava_contact(FLAME_CHECK_INTERVAL * FLAME_CONTACT_FACTOR)
	# Trees and wood piles along the centreline (samples overlap enough).
	for i in [0, 2, 4]:
		var sample: Vector3 = origin + forward * (0.5 + float(i))
		if tree_manager != null:
			tree_manager.ignite_in_radius(sample, half_width + 0.2)
		if wood_pile_manager != null:
			wood_pile_manager.ignite_in_radius(sample, half_width + 0.2)


# --- Visuals (own 3D model, in-game only) -------------------------------------------

func _create_model() -> void:
	var root: Node3D = Node3D.new()
	root.name = "Model"
	add_child(root)
	_model = root

	# User-provided model (assets/models/units/fire_ram.glb) when present;
	# optional named child "Flag" (MeshInstance3D) takes the tribe colour.
	var custom: Node3D = AssetLibrary.instantiate_model("models/units/fire_ram.glb")
	if custom != null:
		root.add_child(custom)
		_flag_mesh = custom.find_child("Flag", true, false) as MeshInstance3D
		_finish_model(root)
		return

	# Hull (slightly shorter than the catapult).
	var frame: MeshInstance3D = MeshInstance3D.new()
	var frame_box: BoxMesh = BoxMesh.new()
	frame_box.size = Vector3(1.0, 0.4, 1.7)
	frame.mesh = frame_box
	frame.material_override = _mat(C_WOOD)
	frame.position.y = 0.5
	root.add_child(frame)

	# Four wheels.
	for sx in [-0.55, 0.55]:
		for sz in [-0.6, 0.6]:
			var wheel: MeshInstance3D = MeshInstance3D.new()
			var cyl: CylinderMesh = CylinderMesh.new()
			cyl.top_radius = 0.28
			cyl.bottom_radius = 0.28
			cyl.height = 0.14
			wheel.mesh = cyl
			wheel.material_override = _mat(C_WOOD_DARK)
			wheel.rotation.z = PI * 0.5
			wheel.position = Vector3(sx, 0.28, sz)
			root.add_child(wheel)

	# Ram beam pointing forward (+z) with a glowing brazier nozzle at the tip.
	var beam: MeshInstance3D = MeshInstance3D.new()
	var beam_box: BoxMesh = BoxMesh.new()
	beam_box.size = Vector3(0.24, 0.24, 1.6)
	beam.mesh = beam_box
	beam.material_override = _mat(C_WOOD_DARK)
	beam.position = Vector3(0.0, 0.85, 0.7)
	root.add_child(beam)
	var brazier: MeshInstance3D = MeshInstance3D.new()
	var pot: SphereMesh = SphereMesh.new()
	pot.radius = 0.28
	pot.height = 0.56
	brazier.mesh = pot
	var glow: StandardMaterial3D = StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.45, 0.1)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.35, 0.05)
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	brazier.material_override = glow
	brazier.position = Vector3(0.0, 0.85, 1.5)
	root.add_child(brazier)

	# Owner flag (recoloured on takeover).
	var pole: MeshInstance3D = MeshInstance3D.new()
	var pole_cyl: CylinderMesh = CylinderMesh.new()
	pole_cyl.top_radius = 0.03
	pole_cyl.bottom_radius = 0.03
	pole_cyl.height = 1.0
	pole.mesh = pole_cyl
	pole.material_override = _mat(C_WOOD_DARK)
	pole.position = Vector3(0.0, 1.1, -0.7)
	root.add_child(pole)
	_flag_mesh = MeshInstance3D.new()
	var flag_box: BoxMesh = BoxMesh.new()
	flag_box.size = Vector3(0.4, 0.25, 0.03)
	_flag_mesh.mesh = flag_box
	_flag_mesh.position = Vector3(0.2, 1.5, -0.7)
	root.add_child(_flag_mesh)

	_finish_model(root)


## Lazily built flame-cone overlay along local +z while a burst runs
## (model-relative — it turns with the hull automatically).
func _show_flame_cone(show: bool) -> void:
	if not is_inside_tree() or _model == null:
		return
	if _flame_cone == null:
		if not show:
			return
		_flame_cone = Node3D.new()
		_flame_cone.name = "FlameCone"
		var colors: Array[Color] = [
			Color(1.0, 0.85, 0.3, 0.9), Color(1.0, 0.55, 0.08, 0.8),
			Color(0.85, 0.25, 0.05, 0.7)]
		for i in range(3):
			var seg: MeshInstance3D = MeshInstance3D.new()
			seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var box: BoxMesh = BoxMesh.new()
			box.size = Vector3(FLAME_WIDTH * (0.5 + 0.25 * float(i)), 0.5,
				FIRE_RANGE / 3.0)
			seg.mesh = box
			var mat: StandardMaterial3D = StandardMaterial3D.new()
			mat.albedo_color = colors[i]
			mat.emission_enabled = true
			mat.emission = Color(colors[i].r, colors[i].g * 0.8, 0.05)
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			seg.material_override = mat
			seg.position = Vector3(0.0, 0.7,
				NOZZLE_OFFSET + FIRE_RANGE / 6.0 + FIRE_RANGE / 3.0 * float(i))
			_flame_cone.add_child(seg)
		_model.add_child(_flame_cone)
	_flame_cone.visible = show


## Adds the flame-cone flicker on top of the shared vehicle visuals.
func _tick_visual(delta: float) -> void:
	super._tick_visual(delta)
	if not is_inside_tree():
		return
	if _flame_cone != null and _flame_cone.visible:
		var s: float = 0.85 + 0.3 * absf(sin(float(Time.get_ticks_msec()) * 0.02))
		_flame_cone.scale = Vector3(s, 1.0, 1.0)
