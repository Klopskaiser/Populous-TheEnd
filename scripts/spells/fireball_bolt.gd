class_name FireballBolt extends Node3D

## The shaman's fireball projectile (named "bolt" — scripts/units/fireball.gd
## is the firewarrior's projectile). Flies from the caster to a fixed target
## POINT (no homing) and explodes there: direct hits take a full brave life,
## the small splash area half of one, and every survivor is thrown back into
## a small arc (THROWN -> momentum roll). Ticked by the UnitManager's
## projectile list; `done` marks it for removal.

const SPEED: float = Balance.FIREBALL_BOLT_SPEED
const ARC_HEIGHT: float = 2.5      # extra apex height of the flight arc
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


func setup(p_tribe_id: int, from: Vector3, to: Vector3, p_shooter,
		p_unit_manager: UnitManager, p_terrain_data: TerrainData) -> void:
	tribe_id = p_tribe_id
	_start = from + Vector3(0.0, 1.2, 0.0)
	target_pos = to
	shooter = p_shooter
	unit_manager = p_unit_manager
	terrain_data = p_terrain_data
	position = _start
	_total = maxf(Vector2(to.x - from.x, to.z - from.z).length(), 0.1)


func tick(delta: float) -> void:
	if done:
		return
	_travelled += SPEED * delta
	var t: float = clampf(_travelled / _total, 0.0, 1.0)
	position = _start.lerp(target_pos, t)
	position.y += sin(t * PI) * ARC_HEIGHT   # simple ballistic arc
	if t >= 1.0:
		_explode()


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
		var dmg: int = DIRECT_DAMAGE if flat_d <= DIRECT_RADIUS else SPLASH_DAMAGE
		var attacker = shooter if (shooter != null and is_instance_valid(shooter)) else null
		u.take_damage(dmg, attacker)
		if u.state == Unit.State.DEAD:
			continue
		# Knocked back and lifted into a small arc; they land rolling and come
		# to a stop quickly on flat ground. A target that is already flying is
		# whirled higher still (Unit.apply_lift).
		u.apply_lift(away, PUSH_SPEED, LIFT_SPEED)


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
