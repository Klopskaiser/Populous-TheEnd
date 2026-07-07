class_name SiegeEngine extends Unit

## Belagerungswaffe (Katapult, phase 7f): a crewed VEHICLE, not a believer.
##
## - Built by the workshop, manned by braves/combat units (never the shaman).
##   Ownership follows the crew: whoever boards an UNMANNED engine takes it
##   over (convert_to_tribe). Crew members walk on side slots (3 per side).
## - No own hit points and never targetable: attackers, spells and fire go
##   for the CREW instead. Only water kills the device (drown).
## - Movement needs >= 1 boarded crew; firing needs >= 2 (rate scales up to
##   6 crew). Slowest unit (0.75x brave); wide 1x2 m body -> vehicle paths
##   (NavGrid 2x2 clearance).
## - Attack: SiegeShot in a high arc, 15 m range, 3 m minimum. Auto-aggro
##   prioritises enemy BUILDINGS over units (the siege specialist), inverse
##   to every other unit.
## - Rendered as its OWN 3D model (renders_as_sprite false): wooden frame,
##   wheels, throwing arm; the crew stays normal sprites around it.

const MAX_CREW: int = 6
const MIN_MOVE_CREW: int = 1
const MIN_FIRE_CREW: int = 2
## A crew member counts as boarded/serving within this range of the engine.
const BOARD_RANGE: float = 2.5
## Boarded members straying farther than this (self-defence chases) are lost.
const CREW_LEASH: float = 8.0
## Fire range band: beyond FIRE_RANGE it advances, below MIN_RANGE the arc is
## too flat — it holds fire.
const FIRE_RANGE: float = 15.0
const MIN_RANGE: float = 3.0
## Shot cooldown by boarded crew: 2 -> slowest, 6 (full) -> fastest.
const COOLDOWN_MIN_CREW: float = 6.0
const COOLDOWN_FULL_CREW: float = 3.0
## Brave speed 4.0 * 0.75 (slowest unit in the game).
const SIEGE_SPEED: float = 3.0
## Crew slot layout: 3 per long side, this far out/apart.
const CREW_SIDE_OFFSET: float = 0.95
const CREW_RANK_SPACING: float = 0.85
## Auto-aggro scan radius (buildings first, then units).
const SIEGE_AGGRO: float = 16.0

const C_WOOD: Color = Color(0.42, 0.29, 0.15)
const C_WOOD_DARK: Color = Color(0.3, 0.2, 0.1)
const C_METAL: Color = Color(0.45, 0.45, 0.48)

## Crew members (untyped entries: may be freed). Includes recruits still
## walking over (not yet boarded).
var crew: Array = []
## Enemy building this engine bombards (takes priority over unit targets).
## Untyped: may be freed when it collapses.
var attack_building = null
## Injected by UnitManager.spawn_unit (set()); needed for the building scan.
var building_manager: BuildingManager = null

var _fire_cooldown: float = 0.0
var _crew_prune_timer: float = 0.0
## Own 3D model parts (in-game only, built in _ready).
var _arm: Node3D = null
var _flag_mesh: MeshInstance3D = null
var _arm_anim: float = 1.0


func _init() -> void:
	max_health = 1
	health = 1
	speed = SIEGE_SPEED
	push_immune = true       # pedestrians do not shove the vehicle around
	counts_population = false  # a device, not a believer (no mana, no housing)


func unit_kind() -> StringName:
	return &"siege"


func _is_combatant() -> bool:
	return true


func _is_ranged() -> bool:
	return true   # never takes melee slots; order_attack skips redistribution


func is_targetable() -> bool:
	return false  # attackers go for the crew


func renders_as_sprite() -> bool:
	return false  # own 3D model instead of the sprite MultiMesh


func is_conversion_immune() -> bool:
	return true   # a device, not a believer


func is_panic_immune() -> bool:
	return true


func aggro_radius() -> float:
	return SIEGE_AGGRO


func can_crew_siege() -> bool:
	return false


## The device takes no damage — attacks hit the crew (spec: catapults cannot
## be attacked directly). Only water destroys it (drown bypasses this).
func take_damage(_amount: int, _attacker = null) -> void:
	pass


## Too heavy for tornado throws, fireball knockback and rolls.
func throw_airborne(_velocity: Vector3, _fall_damage: int = 0) -> void:
	pass


func start_roll(_dir: Vector3, _duration: float = MINI_ROLL_DURATION,
		_initial_speed: float = 0.0) -> void:
	pass


func displace(_dir: Vector3, _dist: float) -> void:
	pass


func ignite(_source_pos: Vector3) -> void:
	pass


# --- Crew management --------------------------------------------------------------

## Registers a unit as (incoming) crew. Refused when full or when a foreign
## unit tries to join a MANNED enemy engine; an unmanned engine accepts any
## tribe (the takeover completes when the recruit boards).
func add_crew(unit) -> bool:
	_prune_crew()
	if unit in crew:
		return true
	if crew.size() >= MAX_CREW:
		return false
	if unit.tribe_id != tribe_id and boarded_count() > 0:
		return false   # manned engines cannot be hijacked while served
	crew.append(unit)
	return true


func remove_crew(unit) -> void:
	crew.erase(unit)


## Crew members currently serving the engine (boarded and within the leash).
func boarded_count() -> int:
	var count: int = 0
	for m in crew:
		if is_instance_valid(m) and m.state != State.DEAD and m.siege_boarded \
				and _flat_dist(m.position, position) <= CREW_LEASH:
			count += 1
	return count


func crew_count() -> int:
	_prune_crew()
	return crew.size()


## A recruit reached the engine: it boards. First boarder of another tribe
## takes the (unmanned) device over; a foreign recruit racing a fresh crew
## loses and is turned away.
func on_crew_boarded(unit) -> void:
	if not (unit in crew):
		return
	if unit.tribe_id != tribe_id:
		if boarded_count() > 0:
			crew.erase(unit)
			unit.leave_crew()
			return
		_switch_owner(unit.tribe)
	unit.siege_boarded = true


## Ownership follows the crew (spec: engines can change hands when the crew
## dies/flees and a new one takes over).
func _switch_owner(new_tribe: Tribe) -> void:
	if new_tribe == null or new_tribe == tribe:
		return
	attack_building = null
	convert_to_tribe(new_tribe)
	_refresh_flag_color()


## Side slot for a crew member: 3 per long side, moving with the vehicle.
## The slot index is the member's position in the crew list (stable enough —
## the list only compacts when members leave).
func crew_slot_position(unit) -> Vector3:
	var index: int = maxi(crew.find(unit), 0)
	var side: float = -1.0 if index % 2 == 0 else 1.0
	var rank: float = float(index / 2) - 1.0
	var forward: Vector3 = facing.normalized() if facing.length_squared() > 0.0 \
		else Vector3(0, 0, 1)
	var right: Vector3 = Vector3(-forward.z, 0.0, forward.x)
	var slot: Vector3 = position + right * side * CREW_SIDE_OFFSET \
		+ forward * rank * CREW_RANK_SPACING
	if terrain_data != null:
		slot.y = terrain_data.get_height(slot.x, slot.z)
	return slot


## Drops freed/dead members, deserters (new orders cleared siege_engine),
## foreign members after an ownership switch and boarded members beyond the
## leash. Recruits still walking over are kept regardless of distance.
## Detached members are released AFTER the list swap — leave_crew mutates
## `crew` via remove_crew, which must not run mid-iteration.
func _prune_crew() -> void:
	var kept: Array = []
	var dropped: Array = []
	for m in crew:
		if not is_instance_valid(m) or m.state == State.DEAD or m.siege_engine != self:
			continue
		if m.tribe_id != tribe_id and m.siege_boarded:
			dropped.append(m)   # converted away / engine changed hands
			continue
		# NOTE: foreign members that have NOT boarded yet are legitimate
		# takeover recruits walking over (an unmanned engine accepts any
		# tribe) — on_crew_boarded settles who wins on arrival.
		if m.siege_boarded and _flat_dist(m.position, position) > CREW_LEASH:
			dropped.append(m)
			continue
		kept.append(m)
	crew = kept
	for m in dropped:
		m.leave_crew()


## Re-summons boarded members that finished a self-defence fight (state fell
## back to IDLE): they return to their slots.
func _resummon_crew() -> void:
	for m in crew:
		if is_instance_valid(m) and m.state == State.IDLE and m.siege_engine == self:
			m._set_state(State.CREW)


# --- Orders & ticking ---------------------------------------------------------------

## Moving needs at least one boarded crew member.
func order_move(target: Vector3, queue_up: bool = false, aggressive: bool = false) -> void:
	if boarded_count() < MIN_MOVE_CREW:
		return
	attack_building = null
	super.order_move(target, queue_up, aggressive)


## Explicit bombard order on an enemy building (right-click, AI).
func order_attack_building(building) -> void:
	if building == null or not is_instance_valid(building) or building.health <= 0:
		return
	if building.tribe_id == tribe_id:
		return
	_end_attack()
	waypoint_queue.clear()
	_clear_path()
	attack_building = building
	_set_state(State.ATTACK)


## Vehicle body: paths on the eroded vehicle grid (narrow gaps are closed).
func _plan_path_to(target: Vector3) -> bool:
	if nav_grid != null:
		var path: PackedVector3Array = nav_grid.find_vehicle_path(position, target)
		if path.is_empty():
			return false
		_path = path
		_path_index = 0
		return true
	return super._plan_path_to(target)


func tick(delta: float) -> void:
	_crew_prune_timer -= delta
	if _crew_prune_timer <= 0.0:
		_crew_prune_timer = 0.5
		_prune_crew()
		_resummon_crew()
	# An unmanned (or under-crewed) vehicle rolls to a stop mid-route.
	if state == State.MOVE and boarded_count() < MIN_MOVE_CREW:
		waypoint_queue.clear()
		_clear_path()
		_set_state(State.IDLE)
	super.tick(delta)
	_tick_visual(delta)


## Auto-aggro, buildings FIRST (inverse of every other unit): the siege
## specialist tears down the base while the escort handles the defenders.
func _engage_on_sight(delta: float) -> bool:
	if boarded_count() < MIN_FIRE_CREW:
		return false
	if not _due_to_scan(delta):
		return false
	var b = _scan_enemy_building(FIRE_RANGE + 2.0)
	if b != null:
		order_attack_building(b)
		return true
	var enemy: Unit = _scan_for_enemy(aggro_radius())
	if enemy != null:
		_begin_attack(enemy)
		return true
	return false


func _tick_idle(delta: float) -> void:
	_engage_on_sight(delta)


## Bombardment: building target first, unit target second. Holds position in
## the [MIN_RANGE, FIRE_RANGE] band, advances beyond it, never melees.
func _tick_attack(delta: float) -> void:
	if boarded_count() < MIN_MOVE_CREW:
		attack_building = null
		_retarget_or_idle()
		return
	if attack_building != null:
		if not is_instance_valid(attack_building) or attack_building.health <= 0:
			attack_building = null
			_retarget_or_idle()
			return
		_bombard(attack_building.center_world(), delta)
		return
	if not _target_valid(attack_target) or attack_target.tribe_id == tribe_id:
		_retarget_or_idle()
		return
	_bombard(attack_target.position, delta)


func _bombard(target_pos: Vector3, delta: float) -> void:
	var dist: float = _flat_dist(position, target_pos)
	if dist > FIRE_RANGE:
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
	path_service.register_projectile(shot)
	_emit_combat_hit(&"throw")


## Nearest living enemy building within `radius`; null without a manager
## (bare tests) or when none is in range.
func _scan_enemy_building(radius: float):
	if building_manager == null:
		return null
	var best = null
	var best_d: float = radius
	for b in building_manager.buildings:
		if not is_instance_valid(b) or b.tribe_id == tribe_id or b.health <= 0:
			continue
		var d: float = _flat_dist(b.center_world(), position)
		if d <= best_d:
			best_d = d
			best = b
	return best


# --- Visuals (own 3D model, in-game only) -------------------------------------------

func _ready() -> void:
	_create_model()
	_refresh_flag_color()


func _create_model() -> void:
	var root: Node3D = Node3D.new()
	root.name = "Model"
	add_child(root)

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


func _refresh_flag_color() -> void:
	if _flag_mesh == null:
		return
	_flag_mesh.material_override = _mat(TRIBE_COLORS[tribe_id % TRIBE_COLORS.size()])


func _mat(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	return mat


## Rotates the model with the facing and plays the throwing-arm snap.
func _tick_visual(delta: float) -> void:
	if not is_inside_tree():
		return
	if facing.length_squared() > 0.000001:
		rotation.y = atan2(facing.x, facing.z)
	if _arm == null:
		return
	if _arm_anim < 1.0:
		_arm_anim = minf(_arm_anim + delta * 3.0, 1.0)
	# Cocked back (0.6 rad) at rest; the shot snaps it up-forward, then it
	# winds back over ~0.3 s.
	var snap: float = 1.0 - _arm_anim
	_arm.rotation.x = 0.6 - snap * 1.5
