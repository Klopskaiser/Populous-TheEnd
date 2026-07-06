class_name Fireball extends Node3D

## Fireball projectile thrown by the firewarrior (phase 5b core; the knockback
## accumulator and the hand-sprite toggle follow in phase 5c).
##
## No physics: flies in tick(delta) (driven by the UnitManager's projectile
## list; tests tick it manually) toward the target with a light arc, homing on
## the target's current position while it lives. The hit is a distance check
## and applies damage exactly once, then `done` flips and the manager frees it.
## Shooter/target references are untyped — either may be freed mid-flight.

const SPEED: float = 12.0
const HIT_RANGE: float = 0.5
const ARC_HEIGHT: float = 1.2
## Aim at chest height rather than the feet.
const TARGET_HEIGHT: float = 0.8

var shooter = null   # untyped: may be freed mid-flight
var target = null    # untyped: may be freed mid-flight
var done: bool = false

var _dest: Vector3 = Vector3.ZERO
var _start: Vector3 = Vector3.ZERO


func setup(p_shooter, p_target, from: Vector3) -> void:
	shooter = p_shooter
	target = p_target
	position = from
	_start = from
	_dest = p_target.position + Vector3(0.0, TARGET_HEIGHT, 0.0)


func tick(delta: float) -> void:
	if done:
		return
	if _target_alive():
		_dest = target.position + Vector3(0.0, TARGET_HEIGHT, 0.0)
	var flat: Vector2 = Vector2(position.x, position.z)
	var flat_dest: Vector2 = Vector2(_dest.x, _dest.z)
	var next: Vector2 = flat.move_toward(flat_dest, SPEED * delta)
	position.x = next.x
	position.z = next.y
	# Light arc: Y interpolates start->dest with a sine bump on top.
	var total: float = Vector2(_start.x, _start.z).distance_to(flat_dest)
	var t: float = 1.0
	if total > 0.001:
		t = clampf(1.0 - next.distance_to(flat_dest) / total, 0.0, 1.0)
	position.y = lerpf(_start.y, _dest.y, t) + sin(t * PI) * ARC_HEIGHT
	if next.distance_to(flat_dest) <= HIT_RANGE:
		_impact()


## Applies the damage exactly once (only if the target is still alive —
## a dead/freed target just lets the ball fizzle at its last position).
func _impact() -> void:
	done = true
	if _target_alive():
		target.take_damage(Unit.FIREBALL_DAMAGE, shooter)


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
