class_name Fireball extends Node3D

## Fireball projectile thrown by the firewarrior (phase 5b core; the knockback
## accumulator and the hand-sprite toggle follow in phase 5c).
##
## No physics: flies in tick(delta) (driven by the UnitManager's projectile
## list; tests tick it manually) straight at the target IN XZ, homing on its
## current position while it lives. In Y the ground is a FLOOR, not a wall: the
## ball glides over hills at GROUND_CLEARANCE instead of burying itself in them
## (see _follow_ground_or_block — the fire ram's flame does the same, FireRam
## _tick_visual). The hit is a distance check and applies damage exactly once,
## then `done` flips and the manager frees it. A hard lifetime cap guarantees
## the ball can never linger (it fizzles without damage).
## Shooter/target references are untyped — either may be freed mid-flight.

const SPEED: float = Balance.FIREWARRIOR_FIREBALL_SPEED
## Chasing an AIRBORNE target the ball keeps picking up speed (phase 10c): a
## unit whirled up by a fireball combo outran the flat 12 m/s, so the shots
## trailed uselessly behind it (user report).
const AIR_ACCEL: float = Balance.FIREWARRIOR_FIREBALL_AIR_ACCEL
const AIR_MAX_SPEED: float = Balance.FIREWARRIOR_FIREBALL_AIR_MAX_SPEED
const HIT_RANGE: float = 0.5
## Aim at chest height rather than the feet.
const TARGET_HEIGHT: float = 0.8
## Height the ball keeps above the ground while gliding (2026-09-07). Same value
## as TARGET_HEIGHT on purpose: it cruises at exactly the height it aims for, so
## the final approach over level ground still lands inside HIT_RANGE.
const GROUND_CLEARANCE: float = TARGET_HEIGHT
## How steeply rising ground may push the ball up (metres of rise per metre
## travelled) before it counts as a WALL instead of a hill. Deliberately the same
## limit that decides whether a terrain cell is walkable: the ball glides over
## everything a unit could run up and fizzles against everything it could not.
const MAX_CLIMB_SLOPE: float = TerrainData.MAX_SLOPE
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
## Rolldauer je Treffer (verlaengert einen laufenden Sturz um diese Zeit).
const ROLL_DURATION: float = Balance.FW_FIREBALL_ROLL_DURATION
## Speed a hit adds to an already rolling target, and the ceiling it stacks to.
const ROLL_BOOST_GAIN: float = Balance.FW_FIREBALL_ROLL_BOOST_GAIN
const ROLL_BOOST_MAX: float = Balance.FW_FIREBALL_ROLL_BOOST_MAX
## A lift REPLACES the ground shove: less horizontal, a small hop upward.
const LIFT_PUSH: float = Balance.FW_FIREBALL_LIFT_PUSH
const LIFT_UP: float = Balance.FW_FIREBALL_LIFT_UP
## In tight formations the knock-over can also topple adjacent units...
const NEIGHBOR_ROLL_RADIUS: float = Balance.FW_FIREBALL_NEIGHBOR_ROLL_RADIUS
## ...each with this chance, for an even shorter tumble.
const NEIGHBOR_ROLL_CHANCE: float = Balance.FW_FIREBALL_NEIGHBOR_ROLL_CHANCE

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
## Current flight speed: SPEED on the ground, ramping up while the target is
## airborne (see AIR_ACCEL). Once gained it is kept — the ball has already
## committed to a fast chase and its lifetime is short anyway.
var _speed: float = SPEED


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
		if target.is_airborne():
			_speed = minf(_speed + AIR_ACCEL * delta, AIR_MAX_SPEED)
	var was: Vector3 = position
	position = position.move_toward(_dest, _speed * delta)
	if not _follow_ground_or_block(was):
		done = true   # smacked into a cliff face — no damage
		return
	if position.distance_to(_dest) <= HIT_RANGE or _age >= MAX_LIFETIME:
		_impact()


func _tick_building(delta: float) -> void:
	if not _building_alive():
		done = true
		return
	_dest = target_building.center_world() + Vector3(0.0, TARGET_HEIGHT, 0.0)
	var was: Vector3 = position
	position = position.move_toward(_dest, SPEED * delta)
	if not _follow_ground_or_block(was):
		done = true
		return
	if position.distance_to(_dest) <= BUILDING_HIT_RANGE or _age >= MAX_LIFETIME:
		_impact_building()


func _impact_building() -> void:
	done = true
	if not _building_alive() or position.distance_to(_dest) > BUILDING_HIT_RANGE * 1.5:
		return
	if not target_building.is_attackable():
		return   # e.g. the reincarnation site — only spells/catapults harm it
	target_building.take_damage(Firewarrior.BUILDING_FIRE_DAMAGE, Building.DMG_RANGED)
	if is_inside_tree():
		var events: Node = get_node_or_null("/root/Events")
		if events != null:
			events.combat_hit.emit(&"fireball", position)


## Keeps the ball GROUND_CLEARANCE above the terrain and reports whether it
## survived (2026-09-07, user report "the shots get lost in the terrain").
##
## The straight line from the thrower's hand (1.1 m) to the target's chest
## (0.8 m) has barely a metre of headroom over 9 m of fire range, so every
## hilltop, ramp edge and heightmap ripple in between used to swallow the ball
## silently — no damage, no effect. Now the ground is only a FLOOR: the ball is
## lifted onto it and glides over the hill (the fire ram's flame samples its
## height the same way, FireRam._tick_visual).
##
## A real WALL still stops it, which is the whole point of the distinction: if
## the ground demands more rise than MAX_CLIMB_SLOPE per metre travelled, this is
## a cliff or a Flatten edge, not a slope, and the ball fizzles against it as
## before (user bug report, Ebene-Klippen). The ball is never pushed DOWN — shots
## from a watchtower or an airship deck and chases after airborne targets keep
## their own height.
func _follow_ground_or_block(was: Vector3) -> bool:
	if terrain_data == null:
		return true   # old tests without terrain: no ground at all
	var ground: float = terrain_data.get_height(position.x, position.z)
	var floor_y: float = ground + GROUND_CLEARANCE
	if position.y >= floor_y:
		return true   # flying free; never pushed DOWN onto the ground
	# Hill or wall? Asked of the TERRAIN alone (rise per metre travelled), not of
	# the ball's own descent — a ball diving at a target behind the crest must not
	# read the sum of both as a wall.
	var step: float = Vector2(position.x - was.x, position.z - was.z).length()
	var rise: float = ground - terrain_data.get_height(was.x, was.z)
	if rise > MAX_CLIMB_SLOPE * maxf(step, 0.001):
		return false
	position.y = floor_y
	return true


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
	# Targets in the air (airship deck crew AND whirled-up units) take a damage
	# bonus — fire feeds on the wind. Phase 10c trimmed it from double to +20 %
	# (with the lift, "hurl it up and shoot it" became a reliable combo, and the
	# accelerating chase makes the balls connect); halved again to +10 % when the
	# area damage was raised. The factor lives in Balance, never inline.
	var dmg: int = Unit.FIREBALL_DAMAGE
	if target.is_airborne():
		dmg = int(roundf(float(dmg) * Balance.FIREWARRIOR_AIRBORNE_MULT))
	target.take_damage(dmg, shooter)
	# Impact sound via the Events bus (absent in headless tests).
	if is_inside_tree():
		var events: Node = get_node_or_null("/root/Events")
		if events != null:
			events.combat_hit.emit(&"fireball", position)
	# Splash BEFORE the "did the direct hit kill it" return (phase 10i, part 3):
	# otherwise the area damage would vanish exactly when the direct hit was
	# lethal — the most common case against a battered target.
	_apply_blast()
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
	var lift_chance: float = lift_chance_for_health(target.health_fraction(),
		LIFT_CHANCE_ROLLING if was_rolling else LIFT_CHANCE)
	var roll_chance: float = ROLL_CHANCE_ROLLING if was_rolling else ROLL_CHANCE
	match impact_outcome(randf(), lift_chance, roll_chance):
		OUTCOME_LIFT:
			# The lift REPLACES the ground shove (less horizontal, a hop up).
			target.apply_lift(dir, LIFT_PUSH, LIFT_UP)
			return
		OUTCOME_ROLL:
			if was_rolling:
				# Already tumbling: steer and accelerate instead of shoving, and
				# keep it down for another ROLL_DURATION.
				_steer_and_boost(target, dir, ROLL_DURATION)
				return
			target.apply_knockback(dir)
			target.start_roll(dir, ROLL_DURATION)
			# A FRESH knock-over topples tight neighbours with it (the rolling
			# case returned above, so no was_rolling check is needed here).
			if target.path_service != null:
				for u in target.path_service.get_units_in_radius(
						target.position, NEIGHBOR_ROLL_RADIUS):
					if u == target or u.state == Unit.State.DEAD \
							or u.state == Unit.State.THROWN:
						continue
					if randf() < NEIGHBOR_ROLL_CHANCE:
						u.start_roll(dir, Unit.NEIGHBOR_ROLL_DURATION)
		_:
			if was_rolling:
				# The plain shove was the ONLY effect this outcome had, and on a
				# rolling body it was pointless — steer and accelerate instead, but
				# without buying extra tumble time (that is the ROLL outcome's job).
				_steer_and_boost(target, dir, 0.0)
				return
			target.apply_knockback(dir)
	# Fire interrupts a preacher's conversion: progress is lost, the unit
	# stands back up (phase 5c). A roll above already broke the trance.
	if target.state == Unit.State.SIT:
		target.reset_conversion()


## A hit on a target that is ALREADY tumbling STEERS the roll and ACCELERATES it
## instead of shoving it (user decision 2026-09-02): next to the ~2.75 m a roll
## covers on its own, the 0.35 m shove was noise, and a body on the ground reads
## better rolling on than being nudged. Direction comes from `dir` (away from the
## shooter) exactly like the shove did.
##
## Stacking WITH A CEILING: each hit adds ROLL_BOOST_GAIN to the speed the roll
## currently travels at, capped at ROLL_BOOST_MAX. The cap is not cosmetic —
## _tick_roll hands the roll speed straight to throw_airborne at the disc rim and
## into cliff falls, so an uncapped stack would let a firing line punt bodies
## across the map. Building on roll_speed_now() (not on the raw field) matters:
## a constant-speed roll reports its real 5.5 m/s, so the first hit accelerates
## it to 7.5 instead of SLOWING it to 2.
##
## `extend` = extra minimum tumble time; 0 steers and accelerates only.
func _steer_and_boost(u, dir: Vector3, extend: float) -> void:
	var boosted: float = minf(u.roll_speed_now() + ROLL_BOOST_GAIN, ROLL_BOOST_MAX)
	u.start_roll(dir, extend, boosted)


## Which of the three impact reactions a roll `r` in [0,1) selects. Pure and
## static so the split is exhaustively testable headless (same pattern as
## SiegeShot.roll_chance_for_slope). LIFT takes the bottom slice, ROLL the
## next one, everything above is a plain shove.
## Area damage around the impact (phase 10i, part 3). Pattern: the cheapest of
## the three existing splash shapes, FireballBolt._explode — one radius query, a
## tribe_id filter, a DEAD check after every take_damage.
##
## Why at all: the balance lab shows firewarriors dealing 100 % of the enemy
## warrior HP pool while killing next to nobody (20 warriors keep 19.7 of 20).
## Their damage is spread thin over everyone instead of concentrated — area
## damage is exactly the fix for that.
##
## Deliberate limits (user decisions): ENEMIES ONLY (they fight in masses and
## fire constantly; friendly fire would have the back row shredding its own
## front) and DAMAGE ONLY, no knockback or lift on bystanders (hundreds of balls
## per battle would otherwise churn every front line — and cost accordingly).
func _apply_blast() -> void:
	if Balance.FW_FIREBALL_BLAST_RADIUS <= 0.0 or Balance.FW_FIREBALL_BLAST_FRAC <= 0.0:
		return
	if shooter == null or not is_instance_valid(shooter) or shooter.path_service == null:
		return   # without the shooter friend/foe is undecidable; guessing is not an option
	var um = shooter.path_service
	var base: int = maxi(1, int(roundf(float(Unit.FIREBALL_DAMAGE)
		* Balance.FW_FIREBALL_BLAST_FRAC)))
	for u in um.get_units_in_radius(position, Balance.FW_FIREBALL_BLAST_RADIUS):
		if u == target or u.state == Unit.State.DEAD or u.tribe_id == shooter.tribe_id:
			continue
		# Vehicles have their own damage models (ignite / register_hull_hit); a
		# 50-%-splash ignition would upgrade the firewarrior against vehicles
		# through a side door.
		if u is CrewedVehicle or u is Airship:
			continue
		var dmg: int = base
		if u.is_airborne():
			# Same bonus as on the main target — otherwise "flyers take the air
			# bonus" would depend on who happened to be the direct target.
			dmg = maxi(1, int(roundf(float(dmg) * Balance.FIREWARRIOR_AIRBORNE_MULT)))
		u.take_damage(dmg, shooter)


## Lift chance scaled by the target's remaining health: a battered unit is thrown
## far more easily than a fresh one. Linear inverse — full health keeps `base`, an
## almost dead target reaches base * FW_FIREBALL_LIFT_HP_MAX_MULT. Pure and static
## so the curve is exhaustively testable headless (pattern: impact_outcome,
## SiegeShot.roll_chance_for_slope).
static func lift_chance_for_health(hp_frac: float, base: float) -> float:
	var f: float = clampf(hp_frac, 0.0, 1.0)
	var mult: float = lerpf(Balance.FW_FIREBALL_LIFT_HP_MAX_MULT, 1.0, f)
	return clampf(base * mult, 0.0, 1.0)


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
