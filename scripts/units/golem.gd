class_name Golem extends Unit

## Golem (Zauber 13, 2026-09-06): ein beschworenes Steinkonstrukt — gross (3 m
## tief x 4 m breit x 4 m hoch, eigenes 3D-Modell statt Sprite), stark
## (GOLEM_HP), langsam schlagend und zeitlich begrenzt.
##
## Kampf: FLAECHEN-Nahkampf. Sobald das Ziel innerhalb GOLEM_REACH steht, schlaegt
## der Golem alle GOLEM_STRIKE_COOLDOWN Sekunden in seine GESAMTE Hitbox (4 x 3 m)
## PLUS ein Rechteck VOR ihr (GOLEM_FIELD_WIDTH x GOLEM_FIELD_LENGTH, im
## Blickrahmen wie die Flamme der Feuerramme): jeder Feind darin nimmt
## GOLEM_DAMAGE, Ueberlebende werden mit je 30 % hochgewirbelt oder ins Rollen
## gebracht — vom Golem weg; jedes feindliche Gebaeude im Feld verliert eine
## Zerstoerungsstufe. Sitzende (Bekehrung) werden wie beim Katapult
## mitgetroffen; eigene Einheiten nie. Ziele in Reichweite gehen immer vor dem
## Verfolgen weggeschleuderter (_tick_attack).
##
## Der Golem haelt sich NICHT an die Kampfgruppenregeln (3er-Ringe, Warteringe):
## `_is_ranged()` ist der vorhandene Schalter dafuer — kein _bind_to_fight, der
## Naechster-nach-Distanz-Scan, und der Gebaeudeangriff laeuft ueber
## _bombard_building (von aussen, ohne Raider-Platz). Luftziele lehnt er ab
## (Nahkampf).
##
## Lebenszeit GOLEM_LIFETIME, +GOLEM_LIFE_PER_KILL je Kill; danach zerfaellt er
## (golem_death) und versinkt. Kein Anhaenger: zaehlt nicht als Bevoelkerung
## (kein Mana, kein Wohnraum, haelt keinen Stamm am Leben), aber gegen den
## Einheiten-Hardcap. Immun gegen Bekehrung, Hypnose, Panik, Wurf und Rollen;
## brennt nur mit GOLEM_BURN_DPS und ohne Panik. Nimmt sonst normalen Schaden.

const REACH: float = Balance.GOLEM_REACH
## Strike area in the heading frame (along = forward, side = right):
## the whole body box |side| <= BODY_HALF_WIDTH, -BODY_HALF_DEPTH <= along <=
## BODY_HALF_DEPTH, plus the field in front |side| <= FIELD_HALF_WIDTH,
## BODY_HALF_DEPTH < along <= FIELD_END.
const BODY_HALF_WIDTH: float = Balance.GOLEM_BODY_HALF_WIDTH
const BODY_HALF_DEPTH: float = Balance.GOLEM_BODY_HALF_DEPTH
const FIELD_HALF_WIDTH: float = Balance.GOLEM_FIELD_WIDTH * 0.5
const FIELD_END: float = Balance.GOLEM_BODY_HALF_DEPTH + Balance.GOLEM_FIELD_LENGTH
const STRIKE_COOLDOWN: float = Balance.GOLEM_STRIKE_COOLDOWN
## Fraction of REACH the golem walks in to when closing on a building (see
## Unit.stand_off_point / SiegeEngine.APPROACH_RANGE_FRACTION).
const APPROACH_RANGE_FRACTION: float = 0.85
## Wreck sink speed after the crumble (m/s), like the vehicle wrecks.
const SINK_SPEED: float = 0.8

const C_STONE: Color = Color(0.46, 0.45, 0.43)
const C_STONE_DARK: Color = Color(0.32, 0.31, 0.3)
const C_STONE_LIGHT: Color = Color(0.58, 0.57, 0.54)

## Seconds of life left; the golem crumbles at zero.
var life_left: float = Balance.GOLEM_LIFETIME
## Kills credited to the golem's strikes (each one extends the life).
var kills: int = 0

var _model: Node3D = null
var _arm: Node3D = null
var _flag_mesh: MeshInstance3D = null
## Strike swing progress (0 = just struck, 1 = arms back at rest).
var _arm_anim: float = 1.0


func _init() -> void:
	max_health = Balance.GOLEM_HP
	health = max_health
	speed = Balance.GOLEM_SPEED
	push_immune = true                 # infantry does not shove the giant around
	vehicle_separation = Balance.GOLEM_SEPARATION   # ...but big bodies keep apart
	joins_idle_groups = false          # never docks onto idle 6-packs
	counts_population = false          # a construct, not a believer


# --- Identity & rules --------------------------------------------------------------

func unit_kind() -> StringName:
	return &"golem"


func _is_combatant() -> bool:
	return true


## The existing "no melee groups" switch (see class doc). Side effects handled
## here: airborne targets are refused in _begin_attack, buildings are struck from
## outside in _bombard_building.
func _is_ranged() -> bool:
	return true


func renders_as_sprite() -> bool:
	return false   # own 3D model


func death_sfx_key() -> StringName:
	return &"golem_death"


func is_conversion_immune() -> bool:
	return true


func is_hypnosis_immune() -> bool:
	return true


func is_panic_immune() -> bool:
	return true


func can_crew_siege() -> bool:
	return false


func can_garrison() -> bool:
	return false


func burn_damage_per_second() -> float:
	return Balance.GOLEM_BURN_DPS


func burn_fx_scale() -> float:
	return 2.5


func burn_fx_height() -> float:
	return 3.0


## Too heavy to be thrown, rolled or shoved (damage still applies).
func throw_airborne(_velocity: Vector3, _fall_damage: int = 0,
		_force: bool = false) -> void:
	pass


func start_roll(_dir: Vector3, _duration: float = MINI_ROLL_DURATION,
		_initial_speed: float = 0.0, _stumble: bool = false) -> void:
	pass


func displace(_dir: Vector3, _dist: float) -> void:
	pass


## Whole hull is clickable; the selection ring encloses the body.
func pick_size_m() -> Vector2:
	return Vector2(4.0, 4.0)


func selection_ring_scale() -> float:
	return 4.0


# --- Lifetime -----------------------------------------------------------------------

func tick(delta: float) -> void:
	super.tick(delta)
	if state != State.DEAD and not doomed and not garrison_housed:
		life_left -= delta
		if life_left <= 0.0:
			_crumble()
	_tick_visual(delta)


## Time is up: the construct falls apart (a normal death — corpse, sink, removal).
func _crumble() -> void:
	if state == State.DEAD:
		return
	life_left = 0.0
	health = 0
	_die()


# --- Combat -------------------------------------------------------------------------

## Melee cannot reach flyers — _is_ranged() would otherwise let the base lock
## onto airborne targets.
func _begin_attack(enemy: Unit) -> void:
	if enemy != null and is_instance_valid(enemy) and enemy.is_airborne():
		return
	super._begin_attack(enemy)


## Lean attack loop without the group machinery: close to REACH, then strike the
## field in front on cooldown. Stays object-ticked (no SoA melee hold) — there are
## only ever a handful of golems.
##
## Target discipline (user feedback 2026-09-06): the golem does NOT run after a
## target it just hurled away while other enemies stand within reach — it turns
## on the nearest one in reach instead. Only when nobody is in reach does it
## chase; a target still in the air is waited for, not followed.
func _tick_attack(delta: float) -> void:
	if not _unit_target_attackable(attack_target) or attack_target.tribe_id == tribe_id:
		_tick_no_unit_target(delta)
		return
	var target: Unit = attack_target
	var dist: float = _flat_dist(position, target.position)
	if dist > REACH or target.is_airborne():
		var near: Unit = _nearest_enemy_in_reach()
		if near != null and near != target:
			_begin_attack(near)   # retarget keeps the cooldown (state stays ATTACK)
			return
		if target.is_airborne():
			_in_melee = false
			if _has_path():
				_clear_path()
			_face_point(target.position)   # wait for the body to land
			return
		_in_melee = false
		if not _approach(target.position, delta):
			_mark_target_unreachable(target)
			_retarget_or_idle()
			return
		_face_point(target.position)
		return
	if _has_path():
		_clear_path()
	_in_melee = true
	_face_point(target.position)
	_attack_cooldown -= delta
	if _attack_cooldown <= 0.0:
		_attack_cooldown = STRIKE_COOLDOWN
		_smash()


## Nearest living, standing enemy within REACH that the golem can strike (no
## flyers, no sitting converts, no devices); null when nobody is that close.
func _nearest_enemy_in_reach() -> Unit:
	if path_service == null:
		return null
	var best: Unit = null
	var best_d: float = INF
	for u in path_service.get_units_in_radius(position, REACH):
		if u == self or u.tribe_id == tribe_id or u.state == State.DEAD \
				or u.state == State.SIT:
			continue
		if not u.is_targetable() or u.is_airborne() or u is CrewedVehicle:
			continue
		var d: float = _flat_dist(position, u.position)
		if d < best_d:
			best_d = d
			best = u
	return best


## Building assault from OUTSIDE (the _is_ranged() dispatch lands here): walk to
## just inside REACH of the footprint, then strike on cooldown. The target
## building is guaranteed its stage per strike even when the field geometry
## misses it (e.g. an odd footprint corner).
func _bombard_building(building, delta: float) -> void:
	var center: Vector3 = building.center_world()
	var flat: Vector2 = Vector2(position.x, position.z)
	if building.footprint_distance_to(flat) > REACH - 0.5:
		_in_melee = false
		# Never path onto the footprint itself (unwalkable): stop short of it.
		_approach(stand_off_point(position, center, REACH * APPROACH_RANGE_FRACTION), delta)
		_face_point(center)
		return
	if _has_path():
		_clear_path()
	_in_melee = true
	_face_point(center)
	_attack_cooldown -= delta
	if _attack_cooldown <= 0.0:
		_attack_cooldown = STRIKE_COOLDOWN
		var struck: Dictionary = _smash()
		if not struck.has(building) and is_instance_valid(building) and building.health > 0:
			building.apply_destruction_stages(Balance.GOLEM_BUILDING_STAGES)


## True when the point at (along, side) in the heading frame lies inside the
## strike area: the golem's own body box or the field in front of it.
static func in_strike_area(along: float, side: float) -> bool:
	if along >= -BODY_HALF_DEPTH and along <= BODY_HALF_DEPTH \
			and absf(side) <= BODY_HALF_WIDTH:
		return true
	return along > BODY_HALF_DEPTH and along <= FIELD_END and absf(side) <= FIELD_HALF_WIDTH


## The area strike: everything inside in_strike_area — the golem's whole body box
## plus the field in front of it (heading frame, flat in XZ — same geometry as the
## fire ram's flame). Returns the buildings it hit (keys) so _bombard_building can
## top up its target. Kills extend the lifetime.
func _smash() -> Dictionary:
	attack_anim = &"punch"
	anim_base_name = attack_anim
	anim_start_ms = Time.get_ticks_msec()
	_arm_anim = 0.0
	_no_combat_timer = 0.0
	_play_sfx(&"golem_strike", 200)
	var forward: Vector3 = facing.normalized() if facing.length_squared() > 0.0 \
		else Vector3(0, 0, 1)
	var right: Vector3 = Vector3(-forward.z, 0.0, forward.x)
	var struck_buildings: Dictionary = {}
	if path_service != null:
		# Broad phase: a circle around the middle of the whole area (body + field).
		var centre: Vector3 = position + forward * ((FIELD_END - BODY_HALF_DEPTH) * 0.5)
		var broad: float = (FIELD_END + BODY_HALF_DEPTH) * 0.5 + BODY_HALF_WIDTH + 0.5
		for u in path_service.get_units_in_radius(centre, broad):
			if u == self or u.state == State.DEAD or u.tribe_id == tribe_id:
				continue
			if not u.is_targetable() or u.is_airborne() or u is CrewedVehicle:
				continue   # protected reserves, flyers, and devices (no HP) are out
			var rel: Vector3 = u.position - position
			var along: float = rel.x * forward.x + rel.z * forward.z
			var side: float = rel.x * right.x + rel.z * right.z
			if not in_strike_area(along, side):
				continue
			u.take_damage(Balance.GOLEM_DAMAGE, self)
			if not is_instance_valid(u) or u.state == State.DEAD or u.doomed:
				kills += 1
				life_left += Balance.GOLEM_LIFE_PER_KILL
				continue
			var away: Vector3 = Vector3(u.position.x - position.x, 0.0,
				u.position.z - position.z)
			match Fireball.impact_outcome(randf(), Balance.GOLEM_LIFT_CHANCE,
					Balance.GOLEM_ROLL_CHANCE):
				Fireball.OUTCOME_LIFT:
					u.apply_lift(away, Balance.GOLEM_LIFT_PUSH, Balance.GOLEM_LIFT_UP)
				Fireball.OUTCOME_ROLL:
					if away.length_squared() < 0.000001:
						away = forward
					u.start_roll(away.normalized(), Balance.GOLEM_ROLL_DURATION,
						Balance.GOLEM_ROLL_SPEED)
	if building_manager != null:
		# Centreline samples like the ram's blast; duplicate() because a stage
		# can level a construction site and mutate the list.
		var candidates: Array = building_manager.buildings.duplicate()
		# Centreline samples from the back of the body to the end of the field,
		# each with the half-width of the region it lies in.
		var along: float = -BODY_HALF_DEPTH + 0.5
		while along < FIELD_END:
			var sample: Vector3 = position + forward * along
			var flat: Vector2 = Vector2(sample.x, sample.z)
			var half: float = BODY_HALF_WIDTH if along <= BODY_HALF_DEPTH else FIELD_HALF_WIDTH
			for b in candidates:
				if not is_instance_valid(b) or b.health <= 0 or struck_buildings.has(b):
					continue
				if b.tribe_id == tribe_id or not b.is_attackable():
					continue
				if b.footprint_distance_to(flat) <= half:
					struck_buildings[b] = true
					b.apply_destruction_stages(Balance.GOLEM_BUILDING_STAGES)
			along += 1.0
	return struck_buildings


# --- Visuals (own 3D model, in-game only) -------------------------------------------

func _ready() -> void:
	_create_model()
	_refresh_flag_color()


## User-provided model (assets/models/units/golem.glb) when present — optional
## named children: "Arm" (Node3D) swings on a strike, "Flag" (MeshInstance3D)
## takes the tribe colour. Otherwise a blocky stone giant: 3 m deep, 4 m wide,
## 4 m tall, front +Z, origin at the feet.
func _create_model() -> void:
	var root: Node3D = Node3D.new()
	root.name = "Model"
	add_child(root)
	_model = root
	var custom: Node3D = AssetLibrary.instantiate_model("models/units/golem.glb")
	if custom != null:
		root.add_child(custom)
		_arm = custom.find_child("Arm", true, false) as Node3D
		_flag_mesh = custom.find_child("Flag", true, false) as MeshInstance3D
		_finish_model(root)
		return
	# Legs.
	for sx in [-1.0, 1.0]:
		_add_box(root, Vector3(1.2, 1.5, 1.4), Vector3(sx, 0.75, 0.0), C_STONE_DARK)
	# Torso (the bulk: 3.0 wide, 2.2 deep).
	_add_box(root, Vector3(3.0, 1.6, 2.2), Vector3(0.0, 2.3, 0.0), C_STONE)
	# Shoulders and head.
	_add_box(root, Vector3(3.4, 0.5, 1.6), Vector3(0.0, 3.2, 0.0), C_STONE_LIGHT)
	_add_box(root, Vector3(1.1, 0.9, 1.0), Vector3(0.0, 3.55, 0.2), C_STONE)
	# Arms under one pivot at shoulder height: they hang beside the torso and
	# swing forward/down on a strike (_tick_visual).
	_arm = Node3D.new()
	_arm.name = "Arm"
	_arm.position = Vector3(0.0, 3.0, 0.2)
	root.add_child(_arm)
	for sx in [-1.55, 1.55]:
		_add_box(_arm, Vector3(0.9, 2.2, 0.9), Vector3(sx, -1.1, 0.0), C_STONE_DARK)
		_add_box(_arm, Vector3(1.0, 0.7, 1.0), Vector3(sx, -2.3, 0.1), C_STONE)
	# Chest rune in the tribe colour (the "flag").
	_flag_mesh = _add_box(root, Vector3(0.9, 0.9, 0.12), Vector3(0.0, 2.4, 1.13), Color.WHITE)
	_flag_mesh.name = "Flag"
	_finish_model(root)


func _add_box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var m: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	m.mesh = box
	m.material_override = _mat(color)
	m.position = at
	parent.add_child(m)
	return m


## Same rig as CrewedVehicle._finish_model: no real-time shadows on units, a
## blob shadow quad instead.
func _finish_model(root: Node3D) -> void:
	for m in root.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var blob: MeshInstance3D = MeshInstance3D.new()
	blob.name = "BlobShadow"
	blob.mesh = UnitRenderer.make_blob_mesh(Vector2(3.4, 2.8))
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.position.y = 0.04
	root.add_child(blob)


func _mat(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	return mat


func _refresh_flag_color() -> void:
	if _flag_mesh == null:
		return
	var mat: StandardMaterial3D = _mat(TRIBE_COLORS[tribe_id % TRIBE_COLORS.size()])
	mat.emission_enabled = true
	mat.emission = TRIBE_COLORS[tribe_id % TRIBE_COLORS.size()]
	mat.emission_energy_multiplier = 0.6
	_flag_mesh.material_override = mat


## Rotates the model with the facing, swings the arms on a strike and sinks the
## crumbled wreck into the ground (the base corpse timer removes it).
func _tick_visual(delta: float) -> void:
	if not is_inside_tree():
		return
	if state == State.DEAD:
		position.y -= SINK_SPEED * delta
		return
	if facing.length_squared() > 0.000001:
		rotation.y = atan2(facing.x, facing.z)
	if _arm != null and _arm_anim < 1.0:
		_arm_anim = minf(_arm_anim + delta * 2.0, 1.0)
		# Raise, then slam down and settle: a half sine over the swing.
		_arm.rotation.x = -sin(_arm_anim * PI) * 1.3
