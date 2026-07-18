extends Node

## Central game-state autoload. Autoload "GameState".
##
## Holds access points to the terrain data model and the tribes (created by
## Main at startup), drives the tribe ticks (mana economy) and — once Main
## enables tracking — the win/lose condition (phase 7).

## A tribe with no units and no usable spawn-capable building left is
## defeated. Fired once per tribe.
signal tribe_defeated(tribe_id: int)
## The match is decided: the player lost (winner_id != PLAYER_TRIBE) or is the
## last tribe standing (winner_id == PLAYER_TRIBE). Fired once.
signal match_ended(winner_id: int)

var terrain_data: TerrainData = null
var terrain: Node3D = null   # the Terrain node (set by Main on startup)
var nav_grid: NavGrid = null

## Id of the active map (phase 7i); drives minimap mask/label. Set by Main.
var map_id: String = MapGenerator.DEFAULT_MAP

## Player (index 0, blue) and AIs — identical Tribe instances.
var tribes: Array[Tribe] = []

## Fixed seed for the skirmish island (kept here so all systems agree on it).
const ISLAND_SEED: int = 1337

## Tribe id of the human player.
const PLAYER_TRIBE: int = 0

## Seconds between defeat checks (they also cover pure damage events, e.g. a
## tornado disabling the last hut without destroying it).
const DEFEAT_CHECK_INTERVAL: float = 1.0

## Configuration of the next/current match, set by the main menu and consumed
## by Main._ready(). null = direct scene start (Main falls back to the
## start mission).
var match_config: MatchConfig = null

## Win-condition tracking (enabled by Main once the bases are populated;
## stays off for the debug battle sandbox).
var match_over: bool = false
var _win_tracking: bool = false
var _defeated: Dictionary[int, bool] = {}
var _defeat_timer: float = 0.0


func _ready() -> void:
	# First autoload: apply persisted keyboard overrides to the InputMap once,
	# before any scene (menu or match) processes input.
	InputSettings.apply_overrides()


func _process(delta: float) -> void:
	for tribe in tribes:
		tribe.tick(delta)
	if _win_tracking and not match_over:
		_defeat_timer -= delta
		if _defeat_timer <= 0.0:
			_defeat_timer = DEFEAT_CHECK_INTERVAL
			check_defeats()


func get_tribe(id: int) -> Tribe:
	if id >= 0 and id < tribes.size():
		return tribes[id]
	return null


## Starts win/lose tracking for the current tribes. Call AFTER the bases are
## populated (a tribe without units/buildings would be "defeated" instantly).
func start_win_tracking() -> void:
	match_over = false
	_defeated.clear()
	_defeat_timer = DEFEAT_CHECK_INTERVAL
	_win_tracking = true


## Disables tracking (scene rebuild, debug-battle sandbox).
func stop_win_tracking() -> void:
	_win_tracking = false
	match_over = false
	_defeated.clear()


## Checks every tribe once and fires tribe_defeated/match_ended. Public so
## tests (and events) can force a check without waiting for the throttle.
func check_defeats() -> void:
	if not _win_tracking or match_over:
		return
	for tribe in tribes:
		if _defeated.get(tribe.id, false):
			continue
		if is_tribe_defeated(tribe):
			_defeated[tribe.id] = true
			tribe_defeated.emit(tribe.id)
	_evaluate_match_end()


## Defeated = no units left AND no usable building that can spawn units
## without worker help: a hut (spawns braves) or a reincarnation site
## (respawns the shaman). Training buildings need a living brave to walk in
## and damaged/under-construction buildings need workers to fix them — with
## zero units neither can ever produce again, so they do not save the tribe.
static func is_tribe_defeated(tribe: Tribe) -> bool:
	for unit in tribe.units:
		if is_instance_valid(unit) and unit.state != Unit.State.DEAD:
			return false
	for building in tribe.buildings:
		if not is_instance_valid(building) or not building.is_usable():
			continue
		if building is Hut or building is ReincarnationSite:
			return false
	return true


## Ends the match when the player fell or only one tribe is left standing.
func _evaluate_match_end() -> void:
	if _defeated.get(PLAYER_TRIBE, false):
		match_over = true
		match_ended.emit(_last_survivor())
		return
	var survivors: Array[int] = []
	for tribe in tribes:
		if not _defeated.get(tribe.id, false):
			survivors.append(tribe.id)
	if survivors.size() == 1:
		match_over = true
		match_ended.emit(survivors[0])


## Any surviving tribe id (for the defeat case; -1 when everyone is gone).
func _last_survivor() -> int:
	for tribe in tribes:
		if not _defeated.get(tribe.id, false):
			return tribe.id
	return -1


func reset() -> void:
	terrain_data = null
	terrain = null
	nav_grid = null
	tribes = []
	match_over = false
	_win_tracking = false
	_defeated.clear()
