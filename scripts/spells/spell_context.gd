class_name SpellContext extends RefCounted

## Dependency bundle injected into Spell.execute(): spells reach the world
## exclusively through this. Headless tests build a context from bare
## TerrainData/NavGrid/UnitManager instances — no scene tree needed.

## Terrain-integrity rules (phase 7c), applied after EVERY spell-driven
## terrain change (all terrain-morphing spells: landbridge, earthquake,
## volcano, flatten, sink). Terrain violence is tribe-blind — own buildings
## and followers are just as much at risk (documented design).
## Max height span under a building's foundation before it bursts apart
## (buildings are fairly sturdy; below this the foundation survives and
## slowly levels itself back — Building.mark_foundation_disturbed).
const FOUNDATION_BREAK_DIFF: float = 2.0
## A building slides into the water once this fraction of its footprint
## cells sits below the sea line.
const FLOOD_FRACTION: float = 0.3

var terrain_data: TerrainData = null
var nav_grid: NavGrid = null
var unit_manager: UnitManager = null
var building_manager: BuildingManager = null
## Optional (terrain morphs re-snap props to the moving ground).
var tree_manager: TreeManager = null
var wood_pile_manager: WoodPileManager = null

var _events: Node = null
var _events_resolved: bool = false


## Publishes a terrain deformation: navigation immediately, then the
## integrity rules (buildings burst/slide, units drown), mesh/collision and
## minimap via Events.terrain_deformed (Main listens; the bus is absent in
## headless tests, where only TerrainData/NavGrid are checked).
func apply_terrain_change(rect: Rect2i) -> void:
	if rect.size == Vector2i.ZERO:
		return
	if nav_grid != null:
		nav_grid.update_region(rect)
	check_terrain_integrity(rect)
	var bus: Node = _bus()
	if bus != null:
		bus.terrain_deformed.emit(rect)


## Buildings touched by the change burst when their foundation got too
## uneven (debris flies, instant destruction) or slide into the water once
## mostly flooded; units standing on flooded ground drown instantly (thrown
## units keep flying — their landing handles water on its own).
func check_terrain_integrity(rect: Rect2i) -> void:
	if terrain_data == null:
		return
	var grown: Rect2i = rect.grow(1)
	if building_manager != null:
		for b in building_manager.buildings.duplicate():
			if not is_instance_valid(b) or b.health <= 0:
				continue
			if not grown.intersects(b.footprint_rect()):
				continue
			if _flooded_fraction(b) >= FLOOD_FRACTION:
				b.slide_into_water(_downhill_direction(b))
				continue
			var span: float = _foundation_span(b)
			if span > FOUNDATION_BREAK_DIFF:
				_shatter_building(b)
			elif span > 0.05:
				# Survived a crooked foundation: it settles level again.
				b.mark_foundation_disturbed()
	if unit_manager != null:
		for u in unit_manager.units:
			if not is_instance_valid(u) or u.state == Unit.State.DEAD \
					or u.state == Unit.State.THROWN:
				continue
			var cell: Vector2i = Vector2i(
				int(floor(u.position.x / TerrainData.CELL_SIZE)),
				int(floor(u.position.z / TerrainData.CELL_SIZE)))
			if not grown.has_point(cell):
				continue
			if terrain_data.get_height(u.position.x, u.position.z) \
					<= TerrainData.SEA_LEVEL + 0.05:
				u.drown()


## Height span (highest minus lowest vertex) under the building's footprint.
func _foundation_span(b: Building) -> float:
	var lo: float = INF
	var hi: float = -INF
	for vz in range(b.cell.y, b.cell.y + b.footprint.y + 1):
		for vx in range(b.cell.x, b.cell.x + b.footprint.x + 1):
			var h: float = terrain_data.vertex_height(vx, vz)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo


## Fraction of footprint cells whose average height sits below the sea line.
func _flooded_fraction(b: Building) -> float:
	var flooded: int = 0
	var total: int = 0
	for z in range(b.cell.y, b.cell.y + b.footprint.y):
		for x in range(b.cell.x, b.cell.x + b.footprint.x):
			var c: Vector2i = Vector2i(x, z)
			if not terrain_data.in_bounds(c):
				continue
			total += 1
			if terrain_data.cell_height(c) <= TerrainData.SEA_LEVEL:
				flooded += 1
	if total == 0:
		return 0.0
	return float(flooded) / float(total)


func _shatter_building(b: Building) -> void:
	if unit_manager != null:
		var debris: BuildingDebris = BuildingDebris.new()
		debris.setup(b.center_world(),
			float(maxi(b.footprint.x, b.footprint.y)) * 0.5 * TerrainData.CELL_SIZE,
			terrain_data)
		unit_manager.register_projectile(debris)
	b.shatter()


## Direction from the building centre toward its lowest footprint corner —
## the side the wreck slides off into the water.
func _downhill_direction(b: Building) -> Vector3:
	var c: Vector3 = b.center_world()
	var corners: Array[Vector2i] = [
		b.cell, b.cell + Vector2i(b.footprint.x, 0),
		b.cell + Vector2i(0, b.footprint.y), b.cell + b.footprint]
	var best: Vector3 = Vector3(1, 0, 0)
	var best_h: float = INF
	for corner in corners:
		var h: float = terrain_data.vertex_height(corner.x, corner.y)
		if h < best_h:
			best_h = h
			best = Vector3(float(corner.x) * TerrainData.CELL_SIZE - c.x, 0.0,
				float(corner.y) * TerrainData.CELL_SIZE - c.z)
	if best.length_squared() < 0.000001:
		return Vector3(1, 0, 0)
	return best.normalized()


func _bus() -> Node:
	if not _events_resolved:
		_events_resolved = true
		var loop: MainLoop = Engine.get_main_loop()
		if loop is SceneTree:
			_events = (loop as SceneTree).root.get_node_or_null("Events")
	return _events
