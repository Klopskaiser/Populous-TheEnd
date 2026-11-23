class_name SnapshotContext extends RefCounted

## Everything GameSnapshot needs to read a running match or to rebuild one: the
## world managers, the tribes and the optional scenario parts. Main fills it from
## its own nodes; the headless tests fill it from a hand-built world.

var terrain_data: TerrainData = null
var nav_grid: NavGrid = null
var unit_manager: UnitManager = null
var building_manager: BuildingManager = null
var tree_manager: TreeManager = null
var wood_pile_manager: WoodPileManager = null
var tribe_commands: TribeCommands = null
## Golems need it for their terrain morphs (levelling, sitting).
var spell_context: SpellContext = null
var tribes: Array[Tribe] = []
var match_config: MatchConfig = null
var map_id: String = MapGenerator.DEFAULT_MAP

# --- Optional parts (capture only; the restore of these is Main's job) ---------------
## The GameState autoload (or a test instance): win tracking and game time.
var game_state: Node = null
## The AIControllers of the match (any order).
var ai_controllers: Array = []
## The survival driver, if the match is a survival scenario.
var survival: SurvivalMode = null
## The camera rig (position, turn, zoom).
var camera: Node3D = null
