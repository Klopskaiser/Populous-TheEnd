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

var shooter = null   # untyped: may be freed mid-flight
var target = null    # untyped: may be freed mid-flight
var done: bool = false

var _dest: Vector3 = Vector3.ZERO
var _age: float = 0.0


var _launch_from: Vector3 = Vector3.ZERO


func setup(p_shooter, p_target, from: Vector3) -> void:
	shooter = p_shooter
	target = p_target
	position = from
	_launch_from = from
	_dest = p_target.position + Vector3(0.0, TARGET_HEIGHT, 0.0)


func tick(delta: float) -> void:
	if done:
		return
	_age += delta
	if _target_alive():
		_dest = target.position + Vector3(0.0, TARGET_HEIGHT, 0.0)
	position = position.move_toward(_dest, SPEED * delta)
	if position.distance_to(_dest) <= HIT_RANGE or _age >= MAX_LIFETIME:
		_impact()


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
	if not _target_alive():
		return   # the hit killed it
	# Knockback away from the shooter (fallback: along the flight direction).
	var dir: Vector3
	if shooter != null and is_instance_valid(shooter):
		dir = target.position - shooter.position
	else:
		dir = target.position - _launch_from
	target.apply_knockback(dir)
	# Fire interrupts a preacher's conversion: progress is lost, the unit
	# stands back up (phase 5c).
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
