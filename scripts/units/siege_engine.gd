class_name SiegeEngine extends CrewedVehicle

## Belagerungswaffe (Katapult, phase 7f): a crewed VEHICLE, not a believer.
##
## - Built by the workshop, manned by braves/combat units (never the shaman).
##   Ownership follows the crew (see CrewedVehicle). Crew members walk on side
##   slots (3 per side).
## - Movement needs >= 1 boarded crew; firing needs >= 2 (rate scales up to
##   6 crew). Slowest unit (0.75x brave); wide 1x2 m body -> vehicle paths
##   (NavGrid 2x2 clearance).
## - Attack: SiegeShot in a high arc, 15 m range, 3 m minimum. Auto-aggro
##   FIRES at units already in the band, otherwise creeps toward the nearest
##   enemy BUILDING (the siege specialist).
## - Rendered as its OWN 3D model: wooden frame, wheels, throwing arm; the
##   crew stays normal sprites around it.

const MAX_CREW: int = Balance.SIEGE_MAX_CREW
const MIN_MOVE_CREW: int = Balance.SIEGE_MIN_MOVE_CREW
const MIN_FIRE_CREW: int = Balance.SIEGE_MIN_FIRE_CREW
## Fire range band: beyond FIRE_RANGE it advances, below MIN_RANGE the arc is
## too flat — it holds fire.
const FIRE_RANGE: float = Balance.SIEGE_FIRE_RANGE
const MIN_RANGE: float = Balance.SIEGE_MIN_RANGE
## Shot cooldown by boarded crew: 2 -> slowest, 6 (full) -> fastest.
const COOLDOWN_MIN_CREW: float = Balance.SIEGE_COOLDOWN_MIN_CREW
const COOLDOWN_FULL_CREW: float = Balance.SIEGE_COOLDOWN_FULL_CREW
## Slowest unit in the game (user-tuned).
const SIEGE_SPEED: float = Balance.SIEGE_SPEED
## Auto-aggro scan radius (UNITS first, then buildings — user feedback);
## comfortably above the fire range so approaching enemies are engaged early.
const SIEGE_AGGRO: float = Balance.SIEGE_AGGRO_RADIUS

## `attack_building` (the bombardment target), `building_manager` (the building
## scan) and `_target_ordered` (explicit-order flag) are inherited from Unit.
## For the catapult, `_target_ordered` additionally gates the slow APPROACH onto
## a unit outside the fire band — auto-acquired unit targets are never chased
## (trundling after a fleeing brave was the "drives in, never shoots" bug).

var _fire_cooldown: float = 0.0
var _arm: Node3D = null
var _arm_anim: float = 1.0


func _init() -> void:
	super()
	speed = SIEGE_SPEED
	max_crew = MAX_CREW
	min_move_crew = MIN_MOVE_CREW
	min_fire_crew = MIN_FIRE_CREW
	# Vehicle-vs-vehicle spacing (phase 8.2): body ~1x2 m plus the crew slots
	# (side offset 0.95, rank spacing 0.85) — engines parked/marching together
	# used to overlap visually and their crews clipped into each other.
	vehicle_separation = 3.2


func unit_kind() -> StringName:
	return &"siege"


## Catapult-vs-vehicle (ranged): a catapult MAY aim at another crewed vehicle
## (including airships) — its shot's splash then hits the enemy crew. Every
## other unit still targets the crew, never the vehicle.
func _may_target_vehicle(enemy: Unit) -> bool:
	return enemy is CrewedVehicle


func aggro_radius() -> float:
	return SIEGE_AGGRO


# --- Orders & ticking ---------------------------------------------------------------

## Explicit attack order on a unit (right-click, AI): clears a building focus;
## the base marks the target as ORDERED, so the catapult will close in on it
## even out of the fire band (the only case a unit is chased) and never
## auto-swaps off it when it creeps too close.
func order_attack(enemy: Unit) -> void:
	attack_building = null
	super.order_attack(enemy)


## Auto target acquisition (idle + aggressive move — NO explicit order). The
## siege weapon FIRES at whatever is already in the fire band (units first,
## then buildings) and, finding nothing to shoot, creeps toward the nearest
## enemy BUILDING within aggro (stationary → catchable). It never auto-chases
## a unit: as the slowest thing on the field it would just trundle after a
## fleeing target forever without ever firing. Returns true when it engaged.
func _auto_acquire(delta: float) -> bool:
	if boarded_count() < MIN_FIRE_CREW:
		return false
	if not _due_to_scan(delta):
		return false
	var u: Unit = _nearest_enemy_unit(FIRE_RANGE)
	if u != null:
		_begin_attack(u)   # auto: _target_ordered stays false (no chase)
		return true
	var b = _scan_enemy_building(SIEGE_AGGRO)
	if b != null:
		_set_building_target(b, true)   # keep the move route (resume after)
		return true
	return false


## Aggressive-move auto-engage (Unit._tick_move) and idle both use the same
## acquisition, so a catapult sent into a base stops and bombards reliably.
func _engage_on_sight(delta: float) -> bool:
	return _auto_acquire(delta)


func _tick_idle(delta: float) -> void:
	_auto_acquire(delta)


## Bombardment. A live unit target takes precedence over the building focus;
## a dead/gone target falls back to the building, then to re-acquisition.
func _tick_attack(delta: float) -> void:
	if boarded_count() < MIN_MOVE_CREW:
		attack_building = null
		_end_attack()
		_set_state(State.IDLE)
		return
	if _target_valid(attack_target) and attack_target.tribe_id != tribe_id:
		_bombard_unit(attack_target, delta)
		return
	if attack_target != null:
		_end_attack()   # dead/converted unit target: drop it cleanly
	if _building_target_valid():
		# A unit stepping into the fire band interrupts the siege (throttled);
		# the building focus stays as the fallback afterwards.
		if _due_to_scan(delta):
			var u: Unit = _nearest_enemy_unit(FIRE_RANGE)
			if u != null:
				_begin_attack(u)
				return
		_bombard_point(attack_building.center_world(), delta, true)
		return
	attack_building = null
	_retarget_or_idle()


## Re-acquisition after a target is lost — same "fire, don't chase" rule as
## _auto_acquire (the inherited version would lock the nearest enemy UNIT at
## any range and the catapult would trundle after it instead of sieging).
func _retarget_or_idle() -> void:
	_end_attack()
	if boarded_count() >= MIN_FIRE_CREW:
		var u: Unit = _nearest_enemy_unit(FIRE_RANGE)
		if u != null:
			_begin_attack(u)
			return
		var b = _scan_enemy_building(SIEGE_AGGRO)
		if b != null:
			_set_building_target(b, true)   # keep the move route
			return
	# Nothing left to shoot: carry on to the pending (attack-)move destination.
	if not waypoint_queue.is_empty():
		attack_building = null
		_start_path_to(waypoint_queue[0])
		return
	attack_building = null
	_set_state(State.IDLE)


## Unit target: fire while it is in the band. Only an ORDERED target is chased
## when it drifts out of the band; an auto target is dropped instead. A target
## that crept inside the minimum range is swapped for another in-band enemy.
func _bombard_unit(target: Unit, delta: float) -> void:
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
		# An AUTO target that crept too close is swapped for another in-band
		# enemy; an ORDERED target is held (the player picked it — obey the
		# order and just wait for it to clear the minimum instead of re-aiming).
		if not _target_ordered and _due_to_scan(delta):
			var alt: Unit = _nearest_enemy_unit(FIRE_RANGE)
			if alt != null and alt != target:
				_begin_attack(alt)
				return
		if _has_path():
			_clear_path()
		_in_melee = true
		_face_point(target.position)
		return   # too close — hold fire until it clears the minimum
	_bombard_point(target.position, delta, false)


## Stands in the [MIN_RANGE, FIRE_RANGE] band and fires at a fixed point.
## `approach` closes the gap when the point is beyond the fire range (used for
## buildings — stationary and catchable). Never melees.
func _bombard_point(target_pos: Vector3, delta: float, approach: bool) -> void:
	var dist: float = _flat_dist(position, target_pos)
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
	if dist < MIN_RANGE:
		return   # arc too flat — holds fire until the target clears the minimum
	var crew_now: int = boarded_count()
	if crew_now < MIN_FIRE_CREW:
		return   # 1 crew can steer but not load and fire
	_fire_cooldown -= delta
	if _fire_cooldown > 0.0:
		return
	_fire_cooldown = fire_cooldown_for_crew(crew_now)
	_launch_shot(target_pos)


## Seconds between shots for a boarded crew of `count` (2 -> 6 s, 6 -> 3 s,
## linear in between; below 2 there is no shot at all).
static func fire_cooldown_for_crew(count: int) -> float:
	if count < MIN_FIRE_CREW:
		return INF
	var t: float = float(clampi(count, MIN_FIRE_CREW, MAX_CREW) - MIN_FIRE_CREW) \
		/ float(MAX_CREW - MIN_FIRE_CREW)
	return lerpf(COOLDOWN_MIN_CREW, COOLDOWN_FULL_CREW, t)


func _launch_shot(target_pos: Vector3) -> void:
	if path_service == null:
		return
	_arm_anim = 0.0   # throwing-arm snap animation
	anim_start_ms = Time.get_ticks_msec()
	var shot: SiegeShot = SiegeShot.new()
	shot.setup(tribe_id, position, target_pos, self, path_service,
		terrain_data, building_manager)
	# Aimed at an airship hull: a miss fizzles in the air instead of dropping
	# phantom lava on the ground far below the dodged ship.
	shot.air_shot = attack_target is Airship
	path_service.register_projectile(shot)
	# Dedicated launch sound when the file exists; otherwise the shared
	# synthesised "throw" whoosh (pre-asset behaviour).
	if is_inside_tree():
		var audio: Node = get_node_or_null("/root/AudioManager")
		if audio != null and audio.has_sfx(&"siege_fire"):
			audio.play_sfx(&"siege_fire", position)
			return
	_emit_combat_hit(&"throw")


## Nearest attackable enemy UNIT within `max_range` that is not inside the
## minimum range (those cannot be hit by the arcing shot). Used with
## FIRE_RANGE so auto-fire only ever locks a target it can hit right away.
func _nearest_enemy_unit(max_range: float) -> Unit:
	if path_service == null:
		return null
	var best: Unit = null
	var best_d: float = max_range
	for u in path_service.get_units_in_radius(position, max_range, SCAN_MAX_CANDIDATES):
		if u == self or u.state == State.DEAD or u.tribe_id == tribe_id:
			continue
		# NOTE (phase 7i): unlike foot units, the catapult MAY bombard units that
		# are being converted (State.SIT) — its splash does not care about the
		# trance. So no SIT skip here.
		# Skip other non-targetable units, but an enemy VEHICLE is fair game
		# (its crew takes the shot's splash) — catapult-vs-catapult/ram/airship.
		if not u.is_targetable() and not (u is CrewedVehicle):
			continue
		var d: float = _flat_dist(position, u.position)
		if d < MIN_RANGE or d > max_range:
			continue
		if d < best_d:
			best_d = d
			best = u
	return best


# --- Visuals (own 3D model, in-game only) -------------------------------------------

func _create_model() -> void:
	var root: Node3D = Node3D.new()
	root.name = "Model"
	add_child(root)
	_model = root

	# User-provided model (assets/models/units/siege_engine.glb) when present.
	# Optional named children: "Arm" (Node3D) pivots on firing, "Flag"
	# (MeshInstance3D) takes the tribe colour. Without them the vehicle simply
	# fires without the snap animation / shows no flag.
	var custom: Node3D = AssetLibrary.instantiate_model("models/units/siege_engine.glb")
	if custom != null:
		root.add_child(custom)
		_arm = custom.find_child("Arm", true, false) as Node3D
		_flag_mesh = custom.find_child("Flag", true, false) as MeshInstance3D
		_finish_model(root)
		return

	# Base frame (the 1x2 m body).
	var frame: MeshInstance3D = MeshInstance3D.new()
	var frame_box: BoxMesh = BoxMesh.new()
	frame_box.size = Vector3(0.9, 0.3, 1.9)
	frame.mesh = frame_box
	frame.material_override = _mat(C_WOOD)
	frame.position.y = 0.45
	root.add_child(frame)

	# Four wheels.
	for sx in [-0.5, 0.5]:
		for sz in [-0.7, 0.7]:
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

	# Upright supports.
	for sz in [-0.4, 0.4]:
		var post: MeshInstance3D = MeshInstance3D.new()
		var post_box: BoxMesh = BoxMesh.new()
		post_box.size = Vector3(0.12, 0.7, 0.12)
		post.mesh = post_box
		post.material_override = _mat(C_WOOD_DARK)
		post.position = Vector3(0.0, 0.9, sz)
		root.add_child(post)

	# Throwing arm (pivots at the back; snaps up when firing).
	_arm = Node3D.new()
	_arm.position = Vector3(0.0, 1.0, 0.55)
	root.add_child(_arm)
	var arm_mesh: MeshInstance3D = MeshInstance3D.new()
	var arm_box: BoxMesh = BoxMesh.new()
	arm_box.size = Vector3(0.14, 0.1, 1.5)
	arm_mesh.mesh = arm_box
	arm_mesh.material_override = _mat(C_WOOD)
	arm_mesh.position.z = -0.7
	_arm.add_child(arm_mesh)
	var basket: MeshInstance3D = MeshInstance3D.new()
	var basket_sphere: SphereMesh = SphereMesh.new()
	basket_sphere.radius = 0.16
	basket_sphere.height = 0.32
	basket.mesh = basket_sphere
	basket.material_override = _mat(C_METAL)
	basket.position.z = -1.4
	_arm.add_child(basket)

	# Owner flag (recoloured on takeover).
	var pole: MeshInstance3D = MeshInstance3D.new()
	var pole_cyl: CylinderMesh = CylinderMesh.new()
	pole_cyl.top_radius = 0.03
	pole_cyl.bottom_radius = 0.03
	pole_cyl.height = 1.0
	pole.mesh = pole_cyl
	pole.material_override = _mat(C_WOOD_DARK)
	pole.position = Vector3(0.0, 1.1, 0.85)
	root.add_child(pole)
	_flag_mesh = MeshInstance3D.new()
	var flag_box: BoxMesh = BoxMesh.new()
	flag_box.size = Vector3(0.4, 0.25, 0.03)
	_flag_mesh.mesh = flag_box
	_flag_mesh.position = Vector3(0.2, 1.5, 0.85)
	root.add_child(_flag_mesh)

	_finish_model(root)


## Adds the throwing-arm snap on top of the shared vehicle visuals.
func _tick_visual(delta: float) -> void:
	super._tick_visual(delta)
	if not is_inside_tree() or _arm == null:
		return
	if _arm_anim < 1.0:
		_arm_anim = minf(_arm_anim + delta * 3.0, 1.0)
	# Cocked back (0.6 rad) at rest; the shot snaps it up-forward, then it
	# winds back over ~0.3 s.
	var snap: float = 1.0 - _arm_anim
	_arm.rotation.x = 0.6 - snap * 1.5
