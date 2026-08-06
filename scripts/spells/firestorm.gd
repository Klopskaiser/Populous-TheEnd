class_name FirestormSpell extends Spell

## "Feuerregen": fireballs RAINING FROM THE SKY over DURATION (20 s since 10k)
## onto random points within SPREAD_RADIUS of the target — each bolt drops from
## high above its own impact point (not from the shaman). A small scheduler entity
## on the projectile list spawns them over time.
##
## Since 10k it is a DENIAL zone, not a salvo: the intervals are random with a
## 0,3-s mean (bursts included), the bolts do less damage but SET VICTIMS ON FIRE
## and damage buildings, they do NOT whirl anyone up, and units standing near but
## outside the impacts fall into panic. All of it drawn from the RNG seeded by the
## target cell, so the spell looks irregular and stays deterministic for tests.

const BOLT_COUNT: int = Balance.FIRESTORM_BOLT_COUNT
const SPREAD_RADIUS: float = Balance.FIRESTORM_SPREAD_RADIUS
const DURATION: float = Balance.FIRESTORM_DURATION
## Bolts spawn this high above their impact point, with a small sideways
## offset so the FireballBolt arc math yields a steep visible dive.
const SKY_HEIGHT: float = 14.0
const SKY_DRIFT: float = 5.0


func _init() -> void:
	id = &"firestorm"
	display_name_de = "Feuerregen"
	charge_cost = Balance.SPELL_FIRESTORM_CHARGE_COST
	max_charges = Balance.SPELL_FIRESTORM_MAX_CHARGES
	cast_range = Balance.SPELL_FIRESTORM_CAST_RANGE
	effect_delay = Balance.SPELL_EFFECT_DELAY_MID


func execute(tribe: Tribe, target: Vector3, ctx: SpellContext) -> bool:
	if ctx == null or ctx.terrain_data == null or ctx.unit_manager == null:
		return false
	var caster: Unit = tribe.shaman if tribe != null else null
	var shower: FirestormShower = FirestormShower.new()
	shower.setup(tribe.id, target, caster, ctx.unit_manager, ctx.terrain_data,
		ctx.building_manager)
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
	var building_manager: BuildingManager = null

	var _spawned: int = 0
	var _timer: float = 0.0
	var _elapsed: float = 0.0
	var _panic_timer: float = 0.0
	## Takt der Panikabfrage (s).
	const PANIC_INTERVAL: float = 1.0
	var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

	func setup(p_tribe_id: int, to: Vector3, p_shooter,
			p_unit_manager: UnitManager, p_terrain_data: TerrainData,
			p_building_manager: BuildingManager = null) -> void:
		tribe_id = p_tribe_id
		target_pos = to
		shooter = p_shooter
		unit_manager = p_unit_manager
		terrain_data = p_terrain_data
		building_manager = p_building_manager
		position = to
		var seed_cell: Vector2i = Vector2i(int(floor(to.x)), int(floor(to.z)))
		_rng.seed = seed_cell.x * 40503 + seed_cell.y * 96269

	func tick(delta: float) -> void:
		if done:
			return
		_elapsed += delta
		# Panik am Rand: wer nah genug steht, um den Feuersturm zu sehen, aber
		# ausserhalb der Einschlaege ist, geraet in Panik. Gedrosselt, weil das
		# ueber 20 s sonst 600 Radiusabfragen waeren.
		_panic_timer -= delta
		if _panic_timer <= 0.0:
			_panic_timer = PANIC_INTERVAL
			_panic_the_onlookers()
		_timer -= delta
		while _timer <= 0.0 and _may_spawn():
			# ZUFAELLIGER Abstand (10k) aus dem geseedeten RNG: der Zauber wirkt
			# unregelmaessig und bleibt trotzdem deterministisch und testbar.
			_timer += _rng.randf_range(Balance.FIRESTORM_INTERVAL_MIN,
				Balance.FIRESTORM_INTERVAL_MAX)
			_launch_bolt()
		if not _may_spawn():
			done = true


	## Solange die Dauer laeuft UND der Sicherheitsdeckel nicht erreicht ist.
	## BOLT_COUNT ist seit 10k nur noch dieser Deckel — die Zahl der Baelle
	## entscheiden die Zufallsintervalle (~67 bei 20 s und 0,3 s Mittel).
	func _may_spawn() -> bool:
		return _elapsed < FirestormSpell.DURATION \
			and _spawned < FirestormSpell.BOLT_COUNT


	## Einheiten zwischen Streuung und Panikradius geraten in Panik. Die
	## Schamanin ist global immun (Unit.is_panic_immune), Fahrzeuge ebenso —
	## hier ist dafuer nichts zu tun.
	func _panic_the_onlookers() -> void:
		if unit_manager == null:
			return
		for u in unit_manager.get_units_in_radius(target_pos,
				Balance.FIRESTORM_PANIC_RADIUS):
			if u.state == Unit.State.DEAD or u.tribe_id == tribe_id:
				continue
			var d: float = Vector2(u.position.x - target_pos.x,
				u.position.z - target_pos.z).length()
			if d <= FirestormSpell.SPREAD_RADIUS:
				continue   # im Feuer selbst — das machen die Baelle
			# start_panic, NICHT panic(): letzteres gibt es nicht und liess den
			# Zauber mit "Invalid call: nonexistent function 'panic'" abstuerzen
			# (Nutzerreport). Die Quelle ist der Feuersturm, davon flieht sie.
			u.start_panic(target_pos)

	func _launch_bolt() -> void:
		_spawned += 1
		if unit_manager == null:
			return
		if _spawned == 1:
			# One roar for the whole salvo, at its start — the twelve impacts
			# bring their own (throttled) fireball sounds.
			SpellAudio.play_effect(self, &"firestorm", target_pos)
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
		# Eigene Werte (10k): weniger Schaden je Ball, KEIN Hochwirbeln (67 Baelle
		# wuerden das Zielgebiet sonst dauerhaft durch die Luft wirbeln, und am
		# Scheibenrand waere der Zauber ein Massentoeter), dafuer Brand und
		# Gebaeudeschaden. Ohne diese Parametrisierung haetten Feuerball und
		# Feuerregen weiter dieselben Konstanten geteilt.
		bolt.direct_damage = Balance.FIRESTORM_DIRECT_DAMAGE
		bolt.splash_damage = Balance.FIRESTORM_SPLASH_DAMAGE
		bolt.whirl_direct = 0.0
		bolt.whirl_splash = 0.0
		bolt.ignites = true
		bolt.building_damage = Balance.FIRESTORM_BUILDING_DAMAGE
		bolt.building_manager = building_manager
		unit_manager.register_projectile(bolt)
