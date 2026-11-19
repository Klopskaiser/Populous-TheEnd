class_name SurvivalMode extends Node

## Survival mode ("Überleben"): a second tribe without buildings, shaman or AI
## sends Balance.SURVIVAL_WAVE_COUNT waves of warriors, firewarriors and
## preachers at the player's base. Each wave is bigger than the one before and
## appears a fixed pause after the previous one APPEARED (not after it died) —
## a steady stream. Main builds the base and adds this node; the wave logic
## lives here.
##
## Size, mix and spawn directions of a wave are pure static functions of the
## wave number (no RNG), so they are exhaustively testable headless.
##
## WIN / LOSE: the wave tribe owns no unit before the first wave and whenever
## the player cleans up faster than the waves arrive — by the ordinary rule
## ("a tribe without a living unit is out") it would be eliminated and the
## match would end as a victory after seconds. The mode therefore shields the
## wave tribe via GameState.set_defeat_exempt() and releases the shield together
## with the LAST wave. From then on the ordinary defeat check decides: the last
## wave enemy dies -> the wave tribe is out -> the player is the last tribe
## standing -> victory. The player's defeat is never shielded.

const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")
const PREACHER_SCENE: PackedScene = preload("res://scenes/units/preacher.tscn")

const KIND_WARRIOR: StringName = &"warrior"
const KIND_FIREWARRIOR: StringName = &"firewarrior"
const KIND_PREACHER: StringName = &"preacher"

const WAVE_COUNT: int = Balance.SURVIVAL_WAVE_COUNT
const FIRST_WAVE_DELAY: float = Balance.SURVIVAL_FIRST_WAVE_DELAY
const WAVE_INTERVAL: float = Balance.SURVIVAL_WAVE_INTERVAL
const WAVE_BASE_SIZE: int = Balance.SURVIVAL_WAVE_BASE_SIZE
const WAVE_GROWTH: int = Balance.SURVIVAL_WAVE_GROWTH
const WAVE_GROWTH_SQ_PERCENT: int = Balance.SURVIVAL_WAVE_GROWTH_SQ_PERCENT
const FIREWARRIOR_PERCENT: int = Balance.SURVIVAL_FIREWARRIOR_PERCENT
const PREACHER_PERCENT: int = Balance.SURVIVAL_PREACHER_PERCENT
const SPAWN_POINTS: int = Balance.SURVIVAL_SPAWN_POINTS
const FRONTS_EARLY: int = Balance.SURVIVAL_FRONTS_EARLY
const FRONTS_LATE: int = Balance.SURVIVAL_FRONTS_LATE
const LATE_FRONT_WAVE: int = Balance.SURVIVAL_LATE_FRONT_WAVE
const FRONT_ROTATION: int = Balance.SURVIVAL_FRONT_ROTATION
const SPAWN_INSET: int = Balance.SURVIVAL_SPAWN_INSET
const SPAWN_MIN_DISTANCE: int = Balance.SURVIVAL_SPAWN_MIN_DISTANCE
const REGROUP_INTERVAL: float = Balance.SURVIVAL_REGROUP_INTERVAL

## Fired after a wave was put on the map (`wave` is 1-based, `count` the number
## of units that actually spawned).
signal wave_spawned(wave: int, count: int)

## Number of the wave that appeared last (0 = none yet, WAVE_COUNT = all out).
var wave: int = 0
## Endless survival (user spec 2026-11-16): the waves never run out — they go on
## past WAVE_COUNT with the same growing size formula, and the wave tribe stays
## shielded for good: the match ends only with the player's defeat. Set before
## setup().
var endless: bool = false
## Scenario knobs (user spec 2026-11-19), set before setup(); the defaults are the base survival.
## Seconds from one wave's appearance to the next, and until the first.
var wave_interval: float = WAVE_INTERVAL
var first_wave_delay: float = FIRST_WAVE_DELAY
## The growth per wave (linear and quadratic part) times this; the first wave stays WAVE_BASE_SIZE.
var growth_mult: int = 1
## > 0: linear waves instead — the first has linear_first units, every further one linear_step more.
var linear_first: int = 0
var linear_step: int = 0
## Every wave comes from EVERY spawn point at once (small groups all around) instead of its fronts.
var all_fronts: bool = false
## The player's units the match hangs on when he has no followers (the golem survival): while one of
## them lives the player tribe is shielded from the defeat check; when the last falls the shield goes.
var guardians: Array[Unit] = []
## Cells the waves appear at, one per direction that has walkable ground
## (see find_spawn_cells). Index-aligned with wave_spawn_slots().
var spawn_cells: Array[Vector2i] = []
## The cell every wave marches at (the player's base).
var base_cell: Vector2i = Vector2i.ZERO

var _wave_tribe: Tribe = null
var _player_tribe: Tribe = null
var _unit_manager: UnitManager = null
var _commands: TribeCommands = null
var _nav: NavGrid = null
## The GameState autoload — injected, because the headless tests run without
## autoloads and hand in their own instance.
var _game_state: Node = null
var _timer: float = FIRST_WAVE_DELAY
var _regroup_timer: float = REGROUP_INTERVAL


# --- Wave table (pure, deterministic) ---------------------------------------------

## Units in wave `p_wave` (1-based). Strictly increasing: the linear part alone
## adds WAVE_GROWTH per wave, the quadratic part never shrinks.
static func wave_size(p_wave: int) -> int:
	var k: int = maxi(p_wave, 1) - 1
	@warning_ignore("integer_division")
	return WAVE_BASE_SIZE + WAVE_GROWTH * k + (WAVE_GROWTH_SQ_PERCENT * k * k) / 100


## Mix of wave `p_wave`: unit kind -> count. Firewarriors and preachers take
## their (floored) percentage, warriors are the rest — always the majority.
static func wave_composition(p_wave: int) -> Dictionary[StringName, int]:
	var total: int = wave_size(p_wave)
	@warning_ignore("integer_division")
	var firewarriors: int = (total * FIREWARRIOR_PERCENT) / 100
	@warning_ignore("integer_division")
	var preachers: int = (total * PREACHER_PERCENT) / 100
	return {
		KIND_WARRIOR: total - firewarriors - preachers,
		KIND_FIREWARRIOR: firewarriors,
		KIND_PREACHER: preachers,
	}


## Units of all waves together — must stay below the per-tribe hard cap, so no
## wave can be cut short even when the player kills nothing.
static func total_wave_units() -> int:
	var total: int = 0
	for w in range(1, WAVE_COUNT + 1):
		total += wave_size(w)
	return total


## From how many directions wave `p_wave` comes at once.
static func wave_front_count(p_wave: int) -> int:
	return FRONTS_LATE if p_wave >= LATE_FRONT_WAVE else FRONTS_EARLY


## Indices into a list of `point_count` spawn points for wave `p_wave`: the
## fronts are spread evenly around the base and the whole pattern turns by
## FRONT_ROTATION points per wave, so consecutive waves come from elsewhere.
static func wave_spawn_slots(p_wave: int, point_count: int) -> PackedInt32Array:
	var slots: PackedInt32Array = PackedInt32Array()
	if point_count <= 0:
		return slots
	var fronts: int = mini(wave_front_count(p_wave), point_count)
	var start: int = ((maxi(p_wave, 1) - 1) * FRONT_ROTATION) % point_count
	for k in range(fronts):
		@warning_ignore("integer_division")
		slots.append((start + (k * point_count) / fronts) % point_count)
	return slots


## Spawn cells around `p_base`: one per compass direction (SPAWN_POINTS of them),
## each at the OUTERMOST walkable cell that is reachable from the base on foot
## (the shore of the island, the rim of the disc), pulled SPAWN_INSET cells
## inward so the group has room. Directions without such ground — or with none
## at least SPAWN_MIN_DISTANCE away — are left out.
static func find_spawn_cells(nav: NavGrid, p_base: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if nav == null or nav.terrain == null:
		return cells
	var origin: Vector2i = nav.nearest_walkable_cell(p_base)
	var island: int = nav.island_at(origin)
	if island < 0:
		return cells
	for i in range(SPAWN_POINTS):
		var angle: float = TAU * float(i) / float(SPAWN_POINTS)
		var dir: Vector2 = Vector2(cos(angle), sin(angle))
		for r in range(nav.terrain.size, SPAWN_MIN_DISTANCE - 1, -1):
			var outer: Vector2i = _ray_cell(origin, dir, r)
			if not nav.is_cell_walkable(outer) or nav.island_at(outer) != island:
				continue
			var inner: Vector2i = _ray_cell(origin, dir, maxi(r - SPAWN_INSET, SPAWN_MIN_DISTANCE))
			var pick: Vector2i = outer
			if nav.is_cell_walkable(inner) and nav.island_at(inner) == island:
				pick = inner
			if pick not in cells:
				cells.append(pick)
			break
	return cells


static func _ray_cell(origin: Vector2i, dir: Vector2, r: int) -> Vector2i:
	return origin + Vector2i(int(round(dir.x * float(r))), int(round(dir.y * float(r))))


# --- Setup ---------------------------------------------------------------------------

## `p_base` is the cell the waves march at. `p_game_state` is the GameState
## autoload (tests: their own instance); win tracking must already run.
func setup(p_wave_tribe: Tribe, p_player_tribe: Tribe, p_unit_manager: UnitManager,
		p_commands: TribeCommands, p_nav: NavGrid, p_base: Vector2i,
		p_game_state: Node) -> void:
	_wave_tribe = p_wave_tribe
	_player_tribe = p_player_tribe
	_unit_manager = p_unit_manager
	_commands = p_commands
	_nav = p_nav
	_game_state = p_game_state
	base_cell = p_base
	spawn_cells = find_spawn_cells(p_nav, p_base)
	if spawn_cells.is_empty():
		push_warning("Überleben: kein Spawnpunkt am Kartenrand gefunden")
	wave = 0
	_timer = first_wave_delay
	_regroup_timer = REGROUP_INTERVAL
	# The wave tribe starts without a single unit: shield it, or the very first
	# defeat check would eliminate it and hand the player the match.
	if _game_state != null and _wave_tribe != null:
		_game_state.set_defeat_exempt(_wave_tribe.id, true)
	# Guardians (golems are no followers): the player stands while one of them lives.
	if _game_state != null and _player_tribe != null and not guardians.is_empty():
		_game_state.set_defeat_exempt(_player_tribe.id, true)


## Units in wave `p_wave` (1-based) of THIS scenario (see the knobs; the defaults give wave_size).
func size_of(p_wave: int) -> int:
	var k: int = maxi(p_wave, 1) - 1
	if linear_first > 0:
		return linear_first + linear_step * k
	@warning_ignore("integer_division")
	return WAVE_BASE_SIZE + growth_mult * (WAVE_GROWTH * k + (WAVE_GROWTH_SQ_PERCENT * k * k) / 100)


## Mix of wave `p_wave` of this scenario, split like wave_composition.
func composition_of(p_wave: int) -> Dictionary[StringName, int]:
	var total: int = size_of(p_wave)
	@warning_ignore("integer_division")
	var firewarriors: int = (total * FIREWARRIOR_PERCENT) / 100
	@warning_ignore("integer_division")
	var preachers: int = (total * PREACHER_PERCENT) / 100
	return {
		KIND_WARRIOR: total - firewarriors - preachers,
		KIND_FIREWARRIOR: firewarriors,
		KIND_PREACHER: preachers,
	}


## The spawn points wave `p_wave` uses: its fronts, or with all_fronts every point.
func slots_of(p_wave: int) -> PackedInt32Array:
	if not all_fronts:
		return wave_spawn_slots(p_wave, spawn_cells.size())
	var slots: PackedInt32Array = PackedInt32Array()
	for k in range(spawn_cells.size()):
		slots.append(k)
	return slots


## Is any guardian still alive?
func guardians_alive() -> bool:
	for unit in guardians:
		if is_instance_valid(unit) and unit.state != Unit.State.DEAD and not unit.doomed:
			return true
	return false


# --- Queries (HUD) -----------------------------------------------------------------

func all_waves_spawned() -> bool:
	return not endless and wave >= WAVE_COUNT


## Seconds until the next wave appears; -1.0 once the last wave is out.
func time_to_next_wave() -> float:
	if all_waves_spawned():
		return -1.0
	return maxf(_timer, 0.0)


## Living units of the wave tribe (converted player units count: they fight
## for the waves now and have to fall for the victory).
func enemies_alive() -> int:
	if _wave_tribe == null:
		return 0
	var count: int = 0
	for unit in _wave_tribe.units:
		if is_instance_valid(unit) and unit.state != Unit.State.DEAD:
			count += 1
	return count


# --- Tick ------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	tick(delta)


## One simulation step (called from _physics_process; tests call it directly).
func tick(delta: float) -> void:
	if _wave_tribe == null or _match_over():
		return
	# The last guardian fell: the player's shield goes, the ordinary defeat check decides.
	if not guardians.is_empty() and _game_state != null and _player_tribe != null 			and _game_state.is_defeat_exempt(_player_tribe.id) and not guardians_alive():
		_game_state.set_defeat_exempt(_player_tribe.id, false)
		_game_state.check_defeats()
	if not all_waves_spawned():
		_timer -= delta
		if _timer <= 0.0:
			_spawn_next_wave()
			# Measured from the wave's APPEARANCE; carrying the remainder keeps the
			# rhythm exact however coarse the tick is.
			_timer += wave_interval
	_tick_regroup(delta)


func _match_over() -> bool:
	return _game_state != null and _game_state.match_over


## Puts the next wave on the map, split over its spawn points, and sends it at
## the base in attack-move. With the last wave the tribe's defeat shield falls.
func _spawn_next_wave() -> void:
	wave += 1
	var spawned: Array[Unit] = []
	var slots: PackedInt32Array = slots_of(wave)
	if not slots.is_empty():
		# Deal the units round robin onto the fronts: every front gets the same
		# mix. Warriors come first in the list and therefore stand in the middle
		# of each group, the preachers on its outside.
		var per_front: Array[Array] = []
		for k in range(slots.size()):
			per_front.append([])
		var index: int = 0
		for scene in _scenes_of(wave):
			per_front[index % slots.size()].append(scene)
			index += 1
		for k in range(slots.size()):
			spawned.append_array(_spawn_group(spawn_cells[slots[k]], per_front[k]))
	if not spawned.is_empty() and _commands != null and _nav != null:
		_commands.order_move(spawned, _nav.cell_to_world(base_cell), false, true)
	if all_waves_spawned() and _game_state != null:
		_game_state.set_defeat_exempt(_wave_tribe.id, false)
	_refill_player_spells()
	wave_spawned.emit(wave, spawned.size())


## The mode is a proving ground for spells: every new wave finds ALL of the
## player's spells fully charged again (Balance.SURVIVAL_REFILL_SPELLS_EACH_WAVE).
func _refill_player_spells() -> void:
	if not Balance.SURVIVAL_REFILL_SPELLS_EACH_WAVE or _player_tribe == null 			or _player_tribe.eliminated:
		return
	for spell in _player_tribe.spells:
		spell.charges = spell.max_charges
	_player_tribe._emit_spell_charges()


## The wave's units of this scenario as a scene list (see _wave_scenes).
func _scenes_of(p_wave: int) -> Array[PackedScene]:
	return _scenes_for(composition_of(p_wave))


## The wave's units as a scene list: warriors, then firewarriors, then preachers.
static func _wave_scenes(p_wave: int) -> Array[PackedScene]:
	return _scenes_for(wave_composition(p_wave))


static func _scenes_for(mix: Dictionary[StringName, int]) -> Array[PackedScene]:
	var scenes: Array[PackedScene] = []
	for i in range(mix[KIND_WARRIOR]):
		scenes.append(WARRIOR_SCENE)
	for i in range(mix[KIND_FIREWARRIOR]):
		scenes.append(FIREWARRIOR_SCENE)
	for i in range(mix[KIND_PREACHER]):
		scenes.append(PREACHER_SCENE)
	return scenes


## Ring-fills walkable cells around `center` with one unit per scene (every
## other cell, for spacing). Stays on the spawn point's own nav island so no
## unit lands on a stray islet it could never leave. Returns what spawned —
## fewer than asked when the tribe hits its hard unit cap.
func _spawn_group(center: Vector2i, scenes: Array) -> Array[Unit]:
	var out: Array[Unit] = []
	if scenes.is_empty() or _nav == null or _unit_manager == null:
		return out
	# A terrain spell may have taken the spawn point since setup.
	var origin: Vector2i = _nav.nearest_walkable_cell(center)
	if origin.x < 0:
		return out
	var island: int = _nav.island_at(origin)
	@warning_ignore("integer_division")
	for radius in range(0, _nav.terrain.size / 2):
		for cell in _ring_cells(origin, radius):
			if out.size() >= scenes.size():
				return out
			if (cell.x + cell.y) % 2 != 0:
				continue
			if not _nav.is_cell_walkable(cell) or _nav.island_at(cell) != island:
				continue
			var unit: Unit = _unit_manager.spawn_unit(
				scenes[out.size()], _wave_tribe.id, _nav.cell_to_world(cell))
			if unit == null:
				return out   # hard unit cap
			out.append(unit)
	return out


static func _ring_cells(center: Vector2i, radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if radius == 0:
		cells.append(center)
		return cells
	for dx in range(-radius, radius + 1):
		cells.append(center + Vector2i(dx, -radius))
		cells.append(center + Vector2i(dx, radius))
	for dz in range(-radius + 1, radius):
		cells.append(center + Vector2i(-radius, dz))
		cells.append(center + Vector2i(radius, dz))
	return cells


# --- Stragglers ------------------------------------------------------------------------

## A wave that reached the base and found nobody there just stands around — and
## so does every player unit a wave preacher converted. Without a new target
## they would neither threaten the player nor come to him to be killed, and the
## match could not end. Every REGROUP_INTERVAL the idle ones are sent at the
## player again.
func _tick_regroup(delta: float) -> void:
	_regroup_timer -= delta
	if _regroup_timer > 0.0:
		return
	_regroup_timer = REGROUP_INTERVAL
	if _commands == null or _nav == null:
		return
	var idle: Array[Unit] = []
	var centre: Vector3 = Vector3.ZERO
	for unit in _wave_tribe.units:
		if is_instance_valid(unit) and unit.in_world and unit.state == Unit.State.IDLE:
			idle.append(unit)
			centre += unit.position
	if idle.is_empty():
		return
	_commands.order_move(idle, _hunt_target(centre / float(idle.size())), false, true)


## Where idle wave units go next: the nearest player FOLLOWER that can be fought
## (followers are what keeps the player in the match — devices like vehicles
## and the golem are fought on contact, not hunted), else the nearest attackable
## player building (crews hide inside huts), else the base.
func _hunt_target(from: Vector3) -> Vector3:
	var best: Vector3 = _nav.cell_to_world(base_cell)
	var best_dist: float = INF
	if _player_tribe != null:
		for unit in _player_tribe.units:
			if not is_instance_valid(unit) or unit.state == Unit.State.DEAD \
					or not unit.is_targetable() or not unit.counts_population:
				continue
			var d: float = unit.position.distance_squared_to(from)
			if d < best_dist:
				best_dist = d
				best = unit.position
		if best_dist < INF:
			return best
		for building in _player_tribe.buildings:
			if not is_instance_valid(building) or building.health <= 0 \
					or not building.is_attackable():
				continue
			var d: float = building.center_world().distance_squared_to(from)
			if d < best_dist:
				best_dist = d
				best = building.center_world()
		if best_dist < INF:
			return best
		# No follower, no building: the guardians (the golem survival).
		for unit in guardians:
			if not is_instance_valid(unit) or unit.state == Unit.State.DEAD or not unit.is_targetable():
				continue
			var d: float = unit.position.distance_squared_to(from)
			if d < best_dist:
				best_dist = d
				best = unit.position
	return best
