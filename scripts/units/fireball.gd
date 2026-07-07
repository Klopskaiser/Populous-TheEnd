class_name Fireball extends Node3D

## Fireball projectile thrown by the firewarrior (phase 5b core; the knockback
## accumulator and the hand-sprite toggle follow in phase 5c).
##
## No physics: flies in tick(delta) (driven by the UnitManager's projectile
## list; tests tick it manually) STRAIGHT at the target, homing on its current
## position while it lives. The hit is a distance check and applies damage
## exactly once, then `done` flips and the manager frees it. A hard lifetime
## cap guarantees the ball can never linger (it fizzles without damage).
## Shooter/target references are untyped — either may be freed mid-flight.

const SPEED: float = 12.0
const HIT_RANGE: float = 0.5
## Aim at chest height rather than the feet.
const TARGET_HEIGHT: float = 0.8
## Safety net: after this many seconds the ball fizzles no matter what.
const MAX_LIFETIME: float = 3.0

## Chance that a hit knocks the target over into a short roll (phase 5d).
## Low per ball — many projectiles raise the effective odds.
const ROLL_CHANCE: float = 0.1
## A target that is ALREADY rolling is easier to keep rolling: follow-up hits
## (the balls are homing) extend the tumble with this higher chance.
const ROLL_CHANCE_ROLLING: float = 0.4
## In tight formations the knock-over can also topple adjacent units...
const NEIGHBOR_ROLL_RADIUS: float = 0.9
## ...each with this chance, for an even shorter tumble.
const NEIGHBOR_ROLL_CHANCE: float = 0.5

var shooter = null   # untyped: may be freed mid-flight
var target = null    # untyped: may be freed mid-flight
## Enemy building target (phase 7g, firewarrior siege); mutually exclusive with
## `target`. Untyped: may be freed when the building collapses.
var target_building = null
var done: bool = false

## Building hits count as reaching the target within this range (buildings are
## large; the shot aims at the footprint centre at chest height).
const BUILDING_HIT_RANGE: float = 1.6

var _dest: Vector3 = Vector3.ZERO
var _age: float = 0.0


var _launch_from: Vector3 = Vector3.ZERO


func setup(p_shooter, p_target, from: Vector3) -> void:
	shooter = p_shooter
	target = p_target
	position = from
	_launch_from = from
	_dest = p_target.position + Vector3(0.0, TARGET_HEIGHT, 0.0)


## Building bombardment variant (phase 7g): flies at the footprint centre and
## deals half-melee HP damage on impact (Firewarrior.BUILDING_FIRE_DAMAGE).
func setup_building(p_shooter, p_building, from: Vector3) -> void:
	shooter = p_shooter
	target_building = p_building
	position = from
	_launch_from = from
	_dest = p_building.center_world() + Vector3(0.0, TARGET_HEIGHT, 0.0)


func tick(delta: float) -> void:
	if done:
		return
	_age += delta
	if target_building != null:
		_tick_building(delta)
		return
	if _target_alive():
		_dest = target.position + Vector3(0.0, TARGET_HEIGHT, 0.0)
	position = position.move_toward(_dest, SPEED * delta)
	if position.distance_to(_dest) <= HIT_RANGE or _age >= MAX_LIFETIME:
		_impact()


func _tick_building(delta: float) -> void:
	if not _building_alive():
		done = true
		return
	_dest = target_building.center_world() + Vector3(0.0, TARGET_HEIGHT, 0.0)
	position = position.move_toward(_dest, SPEED * delta)
	if position.distance_to(_dest) <= BUILDING_HIT_RANGE or _age >= MAX_LIFETIME:
		_impact_building()


func _impact_building() -> void:
	done = true
	if not _building_alive() or position.distance_to(_dest) > BUILDING_HIT_RANGE * 1.5:
		return
	target_building.take_damage(Firewarrior.BUILDING_FIRE_DAMAGE, Building.DMG_RANGED)
	if is_inside_tree():
		var events: Node = get_node_or_null("/root/Events")
		if events != null:
			events.combat_hit.emit(&"fireball", position)


func _building_alive() -> bool:
	return target_building != null and is_instance_valid(target_building) \
		and target_building.health > 0


## Applies the damage exactly once — only if the target is still alive and the
## ball actually reached it (a lifetime fizzle or a dead/freed target does no
## damage). A hit also shoves the target back (stacking with rapid follow-up
## hits, see Unit.apply_knockback) and interrupts a running conversion.
func _impact() -> void:
	done = true
	if not _target_alive() or position.distance_to(
			target.position + Vector3(0.0, TARGET_HEIGHT, 0.0)) > HIT_RANGE * 2.0:
		return
	target.take_damage(Unit.FIREBALL_DAMAGE, shooter)
	# Impact sound via the Events bus (absent in headless tests).
	if is_inside_tree():
		var events: Node = get_node_or_null("/root/Events")
		if events != null:
			events.combat_hit.emit(&"fireball", position)
	if not _target_alive():
		return   # the hit killed it
	# Knockback away from the shooter (fallback: along the flight direction).
	var dir: Vector3
	if shooter != null and is_instance_valid(shooter):
		dir = target.position - shooter.position
	else:
		dir = target.position - _launch_from
	target.apply_knockback(dir)
	# Knock-over roll (phase 5d): low chance per ball, higher on targets that
	# already tumble (extends the roll). A fresh knock-over can also topple
	# adjacent units in tight formations, for an even shorter roll.
	var was_rolling: bool = target.state == Unit.State.ROLL
	var chance: float = ROLL_CHANCE_ROLLING if was_rolling else ROLL_CHANCE
	if randf() < chance:
		target.start_roll(dir, Unit.MINI_ROLL_DURATION)
		if not was_rolling and target.path_service != null:
			for u in target.path_service.get_units_in_radius(
					target.position, NEIGHBOR_ROLL_RADIUS):
				if u == target or u.state == Unit.State.DEAD \
						or u.state == Unit.State.THROWN:
					continue
				if randf() < NEIGHBOR_ROLL_CHANCE:
					u.start_roll(dir, Unit.NEIGHBOR_ROLL_DURATION)
	# Fire interrupts a preacher's conversion: progress is lost, the unit
	# stands back up (phase 5c). A roll above already broke the trance.
	if target.state == Unit.State.SIT:
		target.reset_conversion()


func _target_alive() -> bool:
	return target != null and is_instance_valid(target) \
		and target.state != Unit.State.DEAD


## Visual (in-game only; _ready never runs for the manually ticked test
## instances outside the tree): small glowing orange sphere, unshaded.
func _ready() -> void:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.55, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.05)
	sphere.material = mat
	mesh.mesh = sphere
	add_child(mesh)
