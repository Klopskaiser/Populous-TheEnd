class_name FireballBolt extends Node3D

## The shaman's fireball projectile (named "bolt" — scripts/units/fireball.gd
## is the firewarrior's projectile). Ticked by the UnitManager's projectile list;
## `done` marks it for removal.
##
## PARAMETERISED since 10k, because the firestorm rains dozens of these through
## the very same class and needs its own values: damage, whirl heights, ignite and
## building damage are per-INSTANCE fields with the fireball spell's numbers as
## defaults. Without that split every firestorm tweak silently changed the
## fireball spell too.
##
## Fireball spell (default): 20/10 damage, whirls the direct hit 4 m and splash
## victims 2 m up — they take fall damage on landing and roll on like any other
## fall. Firestorm: 20/10 too, but NO whirl, plus ignite and building damage.

const SPEED: float = Balance.FIREBALL_BOLT_SPEED
const ARC_HEIGHT: float = 2.5      # extra apex height of the flight arc
## Defaults; the per-instance fields below are what _explode actually reads.
const DIRECT_DAMAGE: int = Balance.FIREBALL_DIRECT_DAMAGE
const SPLASH_DAMAGE: int = Balance.FIREBALL_SPLASH_DAMAGE
const DIRECT_RADIUS: float = Balance.FIREBALL_DIRECT_RADIUS   # counts as a direct hit
const SPLASH_RADIUS: float = Balance.FIREBALL_SPLASH_RADIUS   # small area of effect
## Phase 10c: the blast SHOVES further than it burns — units between
## SPLASH_RADIUS and PUSH_RADIUS are thrown and lifted without taking damage.
const PUSH_RADIUS: float = Balance.FIREBALL_PUSH_RADIUS
const PUSH_SPEED: float = Balance.FIREBALL_PUSH_SPEED
const LIFT_SPEED: float = Balance.FIREBALL_LIFT_SPEED

var done: bool = false
var tribe_id: int = 0
var target_pos: Vector3 = Vector3.ZERO
var shooter = null   # untyped: the shaman may die mid-flight
var unit_manager: UnitManager = null
var terrain_data: TerrainData = null

var _start: Vector3 = Vector3.ZERO
var _travelled: float = 0.0
var _total: float = 0.0

# --- Per-instance effect values (10k) -----------------------------------------
var direct_damage: int = DIRECT_DAMAGE
var splash_damage: int = SPLASH_DAMAGE
## Whirl heights in metres (0 = no whirl, only the old ground shove).
var whirl_direct: float = Balance.FIREBALL_WHIRL_DIRECT
var whirl_splash: float = Balance.FIREBALL_WHIRL_SPLASH
## Sets victims on fire (firestorm) and damages buildings in the splash radius.
var ignites: bool = false
var building_damage: int = 0
## Explicitly handed in for the building damage (pattern: LavaSurge.setup) —
## relying on unit_manager.building_manager would make the effect depend on a
## wiring the caller cannot see, and it is not set in every test world.
var building_manager: BuildingManager = null

## Unit this bolt CHASES (10k): the enemy picked at cast time. The bolt follows it
## while it stays within FIREBALL_CHASE_MAX_DRIFT of the original target point;
## further away (or dead) it falls back to that fixed point. Untyped — the target
## may be freed mid-flight.
var chase_target = null
var _anchor: Vector3 = Vector3.ZERO


func setup(p_tribe_id: int, from: Vector3, to: Vector3, p_shooter,
		p_unit_manager: UnitManager, p_terrain_data: TerrainData) -> void:
	tribe_id = p_tribe_id
	_start = from + Vector3(0.0, 1.2, 0.0)
	target_pos = to
	shooter = p_shooter
	unit_manager = p_unit_manager
	terrain_data = p_terrain_data
	position = _start
	_anchor = to
	_total = maxf(Vector2(to.x - from.x, to.z - from.z).length(), 0.1)


func tick(delta: float) -> void:
	if done:
		return
	_update_chase()
	_travelled += SPEED * delta
	var t: float = clampf(_travelled / _total, 0.0, 1.0)
	position = _start.lerp(target_pos, t)
	position.y += sin(t * PI) * ARC_HEIGHT   # simple ballistic arc
	if t >= 1.0:
		_explode()


## Follows the chased unit as long as it has not run too far from the point the
## shaman actually aimed at. The parabola itself is unchanged — only its endpoint
## moves, which is why this is a two-line rule and not a new flight model.
func _update_chase() -> void:
	if chase_target == null:
		return
	if not is_instance_valid(chase_target) or chase_target.state == Unit.State.DEAD:
		chase_target = null
		return
	var pos: Vector3 = chase_target.position
	if Vector2(pos.x - _anchor.x, pos.z - _anchor.z).length() 			> Balance.FIREBALL_CHASE_MAX_DRIFT:
		chase_target = null   # ran out of the aimed area: keep the fixed point
		return
	target_pos = pos


func _explode() -> void:
	done = true
	# The impact IS the spell's sound (phase 10b). Throttled because a firestorm
	# rains twelve bolts through this very class.
	SpellAudio.play_effect(self, &"fireball", target_pos, 60)
	if unit_manager == null:
		return
	# Fire sets nearby trees and wood piles alight (phase 7d).
	if unit_manager.tree_manager != null:
		unit_manager.tree_manager.ignite_in_radius(target_pos, SPLASH_RADIUS)
	if unit_manager.wood_pile_manager != null:
		unit_manager.wood_pile_manager.ignite_in_radius(target_pos, SPLASH_RADIUS)
	# ONE query over the wider push radius; the damage test below narrows it
	# back down to the splash radius.
	for u in unit_manager.get_units_in_radius(target_pos, maxf(SPLASH_RADIUS, PUSH_RADIUS)):
		if u.state == Unit.State.DEAD or u.tribe_id == tribe_id:
			continue
		var flat_d: float = Vector2(u.position.x - target_pos.x,
			u.position.z - target_pos.z).length()
		var away: Vector3 = Vector3(u.position.x - target_pos.x, 0.0,
			u.position.z - target_pos.z)
		if flat_d > SPLASH_RADIUS:
			# Rim of the blast: shoved and lifted, but unhurt (and vehicles
			# out there are neither hulled nor set alight).
			if not (u is CrewedVehicle):
				u.apply_lift(away, PUSH_SPEED, LIFT_SPEED)
			continue
		if u is Airship:
			# The airship's hull takes a counted hit instead of burning:
			# two fireball-spell/firestorm bolts (or catapult intercepts)
			# bring it down. Its deck crew takes the splash on its own.
			u.register_hull_hit(target_pos)
			continue
		if u is CrewedVehicle:
			# Fire spells set the wooden vehicle alight (7f): it burns and
			# then sinks; the crew takes the splash on its own.
			u.ignite(target_pos)
			continue
		var direct: bool = flat_d <= DIRECT_RADIUS
		var dmg: int = direct_damage if direct else splash_damage
		var attacker = shooter if (shooter != null and is_instance_valid(shooter)) else null
		u.take_damage(dmg, attacker)
		if ignites:
			u.ignite(target_pos, attacker)   # firestorm: the fire keeps burning
		if u.state == Unit.State.DEAD:
			continue
		var whirl: float = whirl_direct if direct else whirl_splash
		if whirl <= 0.0:
			# No whirl (firestorm): 67 bolts would otherwise keep a whole area in
			# the air — and near the disc edge that would be a mass killer.
			u.apply_knockback(away)
			continue
		# Whirled UP instead of only shoved (10k): the arc height is prescribed, so
		# the fall damage follows the game-wide per-metre rule and the landing rolls
		# on exactly like any other fall (Unit.throw_airborne).
		u.throw_airborne(_whirl_velocity(away, whirl),
			fall_damage_for_height(whirl))
	if building_damage > 0:
		_damage_buildings()


## Upward velocity that reaches `height` metres, plus a little sideways drift so
## the victims do not land on the exact same spot they took off from.
static func _whirl_velocity(away: Vector3, height: float) -> Vector3:
	var up: float = sqrt(maxf(2.0 * Unit.THROW_GRAVITY * height, 0.0))
	var flat: Vector3 = away
	if flat.length_squared() > 0.000001:
		flat = flat.normalized() * PUSH_SPEED * 0.4
	else:
		flat = Vector3.ZERO
	return flat + Vector3.UP * up


## Fall damage for a drop of `height` metres — the same per-metre rule cliffs and
## the tornado use, so a whirl never has its own damage model.
static func fall_damage_for_height(height: float) -> int:
	return int(round(maxf(height, 0.0) * Balance.CLIFF_FALL_DAMAGE_PER_M))


## Buildings in the splash radius (firestorm only). HP damage, not destruction
## stages: that way the existing four-stage model of Building.take_damage decides
## what a hit looks like, and one bolt lands in the band of a warrior's melee
## strike (18-24) by construction.
func _damage_buildings() -> void:
	var bm: BuildingManager = building_manager
	if bm == null and unit_manager != null:
		bm = unit_manager.building_manager
	if bm == null:
		return
	for b in bm.buildings:
		if not is_instance_valid(b) or b.health <= 0 or b.tribe_id == tribe_id:
			continue
		if not b.is_attackable():
			continue   # the reincarnation circle is never a target (10g)
		if b.footprint_distance_to(Vector2(target_pos.x, target_pos.z)) > SPLASH_RADIUS:
			continue
		b.take_damage(building_damage)


func _ready() -> void:
	var ball: MeshInstance3D = MeshInstance3D.new()
	# No real shadow (phase 8 rule): a glowing bolt casts none.
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	ball.mesh = sphere
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.05)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball.material_override = mat
	add_child(ball)
