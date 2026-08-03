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

const SPEED: float = Balance.FIREWARRIOR_FIREBALL_SPEED
const HIT_RANGE: float = 0.5
## Aim at chest height rather than the feet.
const TARGET_HEIGHT: float = 0.8
## Safety net: after this many seconds the ball fizzles no matter what.
const MAX_LIFETIME: float = 3.0

## Chance that a hit knocks the target over into a short roll (phase 5d).
## Low per ball — many projectiles raise the effective odds. Phase 10c split
## part of it off into LIFT_CHANCE: the sum is unchanged, some knock-overs
## became small uppercuts instead.
const ROLL_CHANCE: float = Balance.FW_FIREBALL_ROLL_CHANCE
## A target that is ALREADY rolling is easier to keep rolling: follow-up hits
## (the balls are homing) extend the tumble with this higher chance.
const ROLL_CHANCE_ROLLING: float = Balance.FW_FIREBALL_ROLL_CHANCE_ROLLING
## Chance that the hit lifts the target off the ground instead (phase 10c).
const LIFT_CHANCE: float = Balance.FW_FIREBALL_LIFT_CHANCE
const LIFT_CHANCE_ROLLING: float = Balance.FW_FIREBALL_LIFT_CHANCE_ROLLING
## A lift REPLACES the ground shove: less horizontal, a small hop upward.
const LIFT_PUSH: float = Balance.FW_FIREBALL_LIFT_PUSH
const LIFT_UP: float = Balance.FW_FIREBALL_LIFT_UP
## In tight formations the knock-over can also topple adjacent units...
const NEIGHBOR_ROLL_RADIUS: float = 0.9
## ...each with this chance, for an even shorter tumble.
const NEIGHBOR_ROLL_CHANCE: float = 0.5

## Outcomes of impact_outcome (see below).
const OUTCOME_PUSH: int = 0
const OUTCOME_ROLL: int = 1
const OUTCOME_LIFT: int = 2

var shooter = null   # untyped: may be freed mid-flight
var target = null    # untyped: may be freed mid-flight
## Terrain for in-flight collision: the ball fizzles against ground/cliff
## faces instead of passing through them (null in old tests = no check).
var terrain_data: TerrainData = null
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
	if _hits_terrain():
		done = true   # smacked into a cliff face / the ground — no damage
		return
	if position.distance_to(_dest) <= HIT_RANGE or _age >= MAX_LIFETIME:
		_impact()


func _tick_building(delta: float) -> void:
	if not _building_alive():
		done = true
		return
	_dest = target_building.center_world() + Vector3(0.0, TARGET_HEIGHT, 0.0)
	position = position.move_toward(_dest, SPEED * delta)
	if _hits_terrain():
		done = true
		return
	if position.distance_to(_dest) <= BUILDING_HIT_RANGE or _age >= MAX_LIFETIME:
		_impact_building()


func _impact_building() -> void:
	done = true
	if not _building_alive() or position.distance_to(_dest) > BUILDING_HIT_RANGE * 1.5:
		return
	if not target_building.is_assailable_by_units():
		return   # e.g. the reincarnation site — only spells/catapults harm it
	target_building.take_damage(Firewarrior.BUILDING_FIRE_DAMAGE, Building.DMG_RANGED)
	if is_inside_tree():
		var events: Node = get_node_or_null("/root/Events")
		if events != null:
			events.combat_hit.emit(&"fireball", position)


## True when the ball's current position lies below the terrain surface —
## it flew into the ground or a cliff face (e.g. a Flatten edge). Upward
## flight stays free; only terrain blocks (user bug report, Ebene-Klippen).
func _hits_terrain() -> bool:
	return terrain_data != null \
		and position.y < terrain_data.get_height(position.x, position.z)


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
	# Targets in the air (airship deck crew, whirled units) take DOUBLE damage
	# — fire feeds on the wind (user spec).
	var dmg: int = Unit.FIREBALL_DAMAGE
	if target.is_airborne():
		dmg *= Balance.FIREWARRIOR_AIRBORNE_MULT
	target.take_damage(dmg, shooter)
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
	# A target that is ALREADY in the air takes NO ground shove (a shove on a
	# flying unit did nothing sensible anyway) — the ball whirls it higher
	# instead, which is what makes fireball combos read on screen.
	if target.is_airborne():
		target.apply_lift(dir, LIFT_PUSH, LIFT_UP)
		return
	# Knock-over roll (phase 5d) / uppercut (phase 10c): low chance per ball,
	# higher on targets that already tumble (extends the roll). A fresh
	# knock-over can also topple adjacent units in tight formations.
	var was_rolling: bool = target.state == Unit.State.ROLL
	var lift_chance: float = LIFT_CHANCE_ROLLING if was_rolling else LIFT_CHANCE
	var roll_chance: float = ROLL_CHANCE_ROLLING if was_rolling else ROLL_CHANCE
	match impact_outcome(randf(), lift_chance, roll_chance):
		OUTCOME_LIFT:
			# The lift REPLACES the ground shove (less horizontal, a hop up).
			target.apply_lift(dir, LIFT_PUSH, LIFT_UP)
			return
		OUTCOME_ROLL:
			target.apply_knockback(dir)
			target.start_roll(dir, Unit.MINI_ROLL_DURATION)
			if not was_rolling and target.path_service != null:
				for u in target.path_service.get_units_in_radius(
						target.position, NEIGHBOR_ROLL_RADIUS):
					if u == target or u.state == Unit.State.DEAD \
							or u.state == Unit.State.THROWN:
						continue
					if randf() < NEIGHBOR_ROLL_CHANCE:
						u.start_roll(dir, Unit.NEIGHBOR_ROLL_DURATION)
		_:
			target.apply_knockback(dir)
	# Fire interrupts a preacher's conversion: progress is lost, the unit
	# stands back up (phase 5c). A roll above already broke the trance.
	if target.state == Unit.State.SIT:
		target.reset_conversion()


## Which of the three impact reactions a roll `r` in [0,1) selects. Pure and
## static so the split is exhaustively testable headless (same pattern as
## SiegeShot.roll_chance_for_slope). LIFT takes the bottom slice, ROLL the
## next one, everything above is a plain shove.
static func impact_outcome(r: float, lift_chance: float, roll_chance: float) -> int:
	if r < lift_chance:
		return OUTCOME_LIFT
	if r < lift_chance + roll_chance:
		return OUTCOME_ROLL
	return OUTCOME_PUSH


func _target_alive() -> bool:
	return target != null and is_instance_valid(target) \
		and target.state != Unit.State.DEAD


## Visual (in-game only; _ready never runs for the manually ticked test
## instances outside the tree): small glowing orange sphere, unshaded.
func _ready() -> void:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	# No real shadow (phase 8 rule): a glowing ball should not cast one, and a
	# mass battle floods the Sun's shadow map with hundreds of these.
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
