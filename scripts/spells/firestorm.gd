class_name FirestormSpell extends Spell

## "Feuerregen": a salvo of BOLT_COUNT fireballs RAINING FROM THE SKY,
## staggered over DURATION seconds onto deterministically scattered points
## within SPREAD_RADIUS of the target — each bolt drops from high above its
## own impact point (not from the shaman) and is a full, unchanged
## FireballBolt (same direct/splash damage and throw-back, attacker =
## shaman). A small scheduler entity on the projectile list spawns the bolts
## over time.

const BOLT_COUNT: int = 8
const SPREAD_RADIUS: float = 5.5
const DURATION: float = 3.0
## Bolts spawn this high above their impact point, with a small sideways
## offset so the FireballBolt arc math yields a steep visible dive.
const SKY_HEIGHT: float = 14.0
const SKY_DRIFT: float = 5.0


func _init() -> void:
	id = &"firestorm"
	display_name_de = "Feuerregen"
	charge_cost = 70.0
	max_charges = 2
	cast_range = 10.0


func execute(tribe: Tribe, target: Vector3, ctx: SpellContext) -> bool:
	if ctx == null or ctx.terrain_data == null or ctx.unit_manager == null:
		return false
	var caster: Unit = tribe.shaman if tribe != null else null
	var shower: FirestormShower = FirestormShower.new()
	shower.setup(tribe.id, target, caster, ctx.unit_manager, ctx.terrain_data)
	ctx.unit_manager.register_projectile(shower)
	return true


## Scheduler: launches one FireballBolt every DURATION/BOLT_COUNT seconds at
## scatter points seeded from the target cell (deterministic, testable).
class FirestormShower extends Node3D:
	var done: bool = false
	var tribe_id: int = 0
	var target_pos: Vector3 = Vector3.ZERO
	var shooter = null   # untyped: the shaman may die mid-salvo
	var unit_manager: UnitManager = null
	var terrain_data: TerrainData = null

	var _spawned: int = 0
	var _timer: float = 0.0
	var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

	func setup(p_tribe_id: int, to: Vector3, p_shooter,
			p_unit_manager: UnitManager, p_terrain_data: TerrainData) -> void:
		tribe_id = p_tribe_id
		target_pos = to
		shooter = p_shooter
		unit_manager = p_unit_manager
		terrain_data = p_terrain_data
		position = to
		var seed_cell: Vector2i = Vector2i(int(floor(to.x)), int(floor(to.z)))
		_rng.seed = seed_cell.x * 40503 + seed_cell.y * 96269

	func tick(delta: float) -> void:
		if done:
			return
		_timer -= delta
		while _timer <= 0.0 and _spawned < FirestormSpell.BOLT_COUNT:
			_timer += FirestormSpell.DURATION / float(FirestormSpell.BOLT_COUNT)
			_launch_bolt()
		if _spawned >= FirestormSpell.BOLT_COUNT:
			done = true

	func _launch_bolt() -> void:
		_spawned += 1
		if unit_manager == null:
			return
		var angle: float = _rng.randf() * TAU
		var dist: float = sqrt(_rng.randf()) * FirestormSpell.SPREAD_RADIUS
		var impact: Vector3 = target_pos + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		if terrain_data != null:
			impact.y = terrain_data.get_height(impact.x, impact.z)
		# Drop point high above the impact: the bolt dives out of the sky.
		var drop_angle: float = _rng.randf() * TAU
		var from: Vector3 = impact + Vector3(
			cos(drop_angle) * FirestormSpell.SKY_DRIFT,
			FirestormSpell.SKY_HEIGHT,
			sin(drop_angle) * FirestormSpell.SKY_DRIFT)
		var bolt: FireballBolt = FireballBolt.new()
		bolt.setup(tribe_id, from, impact, shooter, unit_manager, terrain_data)
		unit_manager.register_projectile(bolt)
