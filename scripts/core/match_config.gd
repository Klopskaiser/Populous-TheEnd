class_name MatchConfig extends RefCounted

## Configuration of the next match, built by the main menu and consumed by
## Main._ready(). Held in GameState.match_config; when absent (direct scene
## start, e.g. headless checks) Main falls back to the start mission.

enum Mode { SKIRMISH, START_MISSION, DEBUG_BATTLE, STRESS_TEST, SURVIVAL }

const MIN_AI: int = 1
const MAX_AI: int = 3

var mode: Mode = Mode.SKIRMISH
## Number of AI opponents (SKIRMISH only; clamped to MIN_AI..MAX_AI).
var ai_count: int = 1
## SURVIVAL only: endless survival — the waves never stop and keep growing
## (user spec 2026-11-16); the match ends only with the player's defeat.
var endless: bool = false
## SURVIVAL only: the scenario (user spec 2026-11-19) — VARIANT_BASE (the base against the waves),
## VARIANT_LARGE (the same on the large island: twice the growth, twice the pause) or VARIANT_GOLEMS
## (two golems, nothing else, endless waves from every side).
const VARIANT_BASE: StringName = &"base"
const VARIANT_LARGE: StringName = &"large"
const VARIANT_GOLEMS: StringName = &"golems"
var variant: StringName = VARIANT_BASE
## Map selection (phase 7i: island / seenland / bergpass / plateau).
var map_id: String = MapGenerator.DEFAULT_MAP


static func skirmish(p_ai_count: int, p_map_id: String = MapGenerator.DEFAULT_MAP) -> MatchConfig:
	var config: MatchConfig = MatchConfig.new()
	config.mode = Mode.SKIRMISH
	config.ai_count = clampi(p_ai_count, MIN_AI, MAX_AI)
	config.map_id = p_map_id if p_map_id in MapGenerator.map_ids() else MapGenerator.DEFAULT_MAP
	return config


static func start_mission() -> MatchConfig:
	var config: MatchConfig = MatchConfig.new()
	config.mode = Mode.START_MISSION
	return config


static func debug_battle() -> MatchConfig:
	var config: MatchConfig = MatchConfig.new()
	config.mode = Mode.DEBUG_BATTLE
	return config


## Stress-test sandbox (phase 8.2 follow-up): four full armies (units +
## catapults + spell-slinging shamans) clash in the island centre.
static func stress_test() -> MatchConfig:
	var config: MatchConfig = MatchConfig.new()
	config.mode = Mode.STRESS_TEST
	return config


## Survival ("Überleben"): a small player base against Balance.SURVIVAL_WAVE_COUNT
## waves of a second tribe that owns no building, no shaman and no AI — the
## waves are driven by SurvivalMode.
static func survival() -> MatchConfig:
	var config: MatchConfig = MatchConfig.new()
	config.mode = Mode.SURVIVAL
	return config


## Endless survival ("Endlos-Überleben", 2026-11-16): the same base and waves,
## but past wave SURVIVAL_WAVE_COUNT it goes on, every wave bigger than the last.
static func survival_endless() -> MatchConfig:
	var config: MatchConfig = survival()
	config.endless = true
	return config


## Survival on the large island (user spec 2026-11-19): the 20 waves with twice the growth per wave
## and twice the pause between them (Balance.SURVIVAL_LARGE_*).
static func survival_large() -> MatchConfig:
	var config: MatchConfig = survival()
	config.variant = VARIANT_LARGE
	config.map_id = MapGenerator.ISLAND_LARGE
	return config


## Golem survival (user spec 2026-11-19): two golems grown to their first sit size, no base; endless
## waves in small groups from every side; lost only when both golems are dead (Balance.GOLEM_SURVIVAL_*).
static func survival_golems() -> MatchConfig:
	var config: MatchConfig = survival()
	config.variant = VARIANT_GOLEMS
	config.endless = true
	return config


## Number of tribes the match needs (player + AIs). START_MISSION, DEBUG_BATTLE
## and SURVIVAL always run with two tribes (blue vs. red), like before; the
## stress test always fields four armies.
func tribe_count() -> int:
	if mode == Mode.SKIRMISH:
		return 1 + clampi(ai_count, MIN_AI, MAX_AI)
	if mode == Mode.STRESS_TEST:
		return 4
	return 2
