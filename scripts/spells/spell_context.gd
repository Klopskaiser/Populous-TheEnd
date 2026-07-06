class_name SpellContext extends RefCounted

## Dependency bundle injected into Spell.execute(): spells reach the world
## exclusively through this. Headless tests build a context from bare
## TerrainData/NavGrid/UnitManager instances — no scene tree needed.

var terrain_data: TerrainData = null
var nav_grid: NavGrid = null
var unit_manager: UnitManager = null
var building_manager: BuildingManager = null
## Optional (landbridge morph re-snaps props to the moving ground).
var tree_manager: TreeManager = null
var wood_pile_manager: WoodPileManager = null

var _events: Node = null
var _events_resolved: bool = false


## Publishes a terrain deformation: navigation immediately, mesh/collision and
## minimap via Events.terrain_deformed (Main listens; the bus is absent in
## headless tests, where only TerrainData/NavGrid are checked).
func apply_terrain_change(rect: Rect2i) -> void:
	if rect.size == Vector2i.ZERO:
		return
	if nav_grid != null:
		nav_grid.update_region(rect)
	var bus: Node = _bus()
	if bus != null:
		bus.terrain_deformed.emit(rect)


func _bus() -> Node:
	if not _events_resolved:
		_events_resolved = true
		var loop: MainLoop = Engine.get_main_loop()
		if loop is SceneTree:
			_events = (loop as SceneTree).root.get_node_or_null("Events")
	return _events
