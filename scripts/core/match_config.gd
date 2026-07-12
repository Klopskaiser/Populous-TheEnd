class_name MatchConfig extends RefCounted

## Configuration of the next match, built by the main menu and consumed by
## Main._ready(). Held in GameState.match_config; when absent (direct scene
## start, e.g. headless checks) Main falls back to the start mission.

enum Mode { SKIRMISH, START_MISSION, DEBUG_BATTLE, STRESS_TEST }

const MIN_AI: int = 1
const MAX_AI: int = 3

var mode: Mode = Mode.SKIRMISH
## Number of AI opponents (SKIRMISH only; clamped to MIN_AI..MAX_AI).
var ai_count: int = 1
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


## Number of tribes the match needs (player + AIs). START_MISSION and
## DEBUG_BATTLE always run with two tribes (blue vs. red), like before;
## the stress test always fields four armies.
func tribe_count() -> int:
	if mode == Mode.SKIRMISH:
		return 1 + clampi(ai_count, MIN_AI, MAX_AI)
	if mode == Mode.STRESS_TEST:
		return 4
	return 2
