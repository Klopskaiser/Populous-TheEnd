class_name MatchConfig extends RefCounted

## Configuration of the next match, built by the main menu and consumed by
## Main._ready(). Held in GameState.match_config; when absent (direct scene
## start, e.g. headless checks) Main falls back to the start mission.

enum Mode { SKIRMISH, START_MISSION, DEBUG_BATTLE }

const MIN_AI: int = 1
const MAX_AI: int = 3

var mode: Mode = Mode.SKIRMISH
## Number of AI opponents (SKIRMISH only; clamped to MIN_AI..MAX_AI).
var ai_count: int = 1
## Map selection — currently only the fixed skirmish island exists.
var map_id: String = "island"


static func skirmish(p_ai_count: int, p_map_id: String = "island") -> MatchConfig:
	var config: MatchConfig = MatchConfig.new()
	config.mode = Mode.SKIRMISH
	config.ai_count = clampi(p_ai_count, MIN_AI, MAX_AI)
	config.map_id = p_map_id
	return config


static func start_mission() -> MatchConfig:
	var config: MatchConfig = MatchConfig.new()
	config.mode = Mode.START_MISSION
	return config


static func debug_battle() -> MatchConfig:
	var config: MatchConfig = MatchConfig.new()
	config.mode = Mode.DEBUG_BATTLE
	return config


## Number of tribes the match needs (player + AIs). START_MISSION and
## DEBUG_BATTLE always run with two tribes (blue vs. red), like before.
func tribe_count() -> int:
	if mode == Mode.SKIRMISH:
		return 1 + clampi(ai_count, MIN_AI, MAX_AI)
	return 2
