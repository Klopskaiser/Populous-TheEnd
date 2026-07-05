class_name TribeCommands extends Node

## The ONLY mutation API for tribe actions. UI (phase 3) and AI (phase 6) both
## call these functions; every command validates first and fails without side
## effects (null/false).
##
## Building costs are NOT paid up front: wood is delivered physically to the
## construction site (see Building). Placement only validates the terrain.
## order_train() and cast_spell() follow in phases 4 and 5.

const FORMATION_SPACING: float = 1.3
## Units move in packs of GROUP_SIZE (like the original game): tight inside
## a group, visible spacing between groups.
const GROUP_SIZE: int = 6
## Distance between group centres in the target formation.
const GROUP_SPACING: float = 2.2
## Tight member offsets inside a group (centre + 5 around it); just outside
## the separation radius so the pack stands calm.
const MEMBER_OFFSETS: Array[Vector3] = [
	Vector3(0.0, 0.0, 0.0),
	Vector3(0.55, 0.0, 0.0), Vector3(-0.55, 0.0, 0.0),
	Vector3(0.27, 0.0, 0.48), Vector3(-0.27, 0.0, 0.48),
	Vector3(0.0, 0.0, -0.55),
]
## Maximum height range (max - min vertex) on a footprint; steeper plots
## cannot be built on (the flatten phase handles anything below this).
const MAX_LEVEL_DIFF: float = 3.0

var nav_grid: NavGrid = null
var building_manager: BuildingManager = null
var unit_manager: UnitManager = null
var tree_manager: TreeManager = null


func setup(p_nav_grid: NavGrid, p_building_manager: BuildingManager,
		p_unit_manager: UnitManager, p_tree_manager: TreeManager = null) -> void:
	nav_grid = p_nav_grid
	building_manager = p_building_manager
	unit_manager = p_unit_manager
	tree_manager = p_tree_manager


# --- Building placement -----------------------------------------------------------

## Places a building (as a construction site) with its footprint top-left at
## `cell`, entrance facing `orientation` (0..3 = S/E/N/W). Returns null when
## the plot is invalid.
func place_building(tribe: Tribe, building_scene: PackedScene, cell: Vector2i,
		orientation: int = 0) -> Building:
	if tribe == null or building_scene == null or building_manager == null:
		return null
	var probe: Building = building_scene.instantiate() as Building
	if probe == null:
		return null
	var fp: Vector2i = probe.footprint
	probe.free()
	if not can_place_at(cell, fp):
		return null
	return building_manager.place(building_scene, tribe, cell, orientation)


## A plot is valid when every footprint cell is on land, free of buildings and
## trees, and the total height range stays below MAX_LEVEL_DIFF (workers
## flatten the rest during construction).
func can_place_at(cell: Vector2i, footprint: Vector2i) -> bool:
	if nav_grid == null:
		return false
	var terrain: TerrainData = nav_grid.terrain
	var lo: float = INF
	var hi: float = -INF
	for z in range(cell.y, cell.y + footprint.y):
		for x in range(cell.x, cell.x + footprint.x):
			var c: Vector2i = Vector2i(x, z)
			if not terrain.in_bounds(c):
				return false
			if nav_grid.is_cell_blocked_by_building(c):
				return false
			if tree_manager != null and tree_manager.has_tree_at(c):
				return false
			if terrain.cell_height(c) <= TerrainData.SEA_LEVEL + 0.1:
				return false
	for vz in range(cell.y, cell.y + footprint.y + 1):
		for vx in range(cell.x, cell.x + footprint.x + 1):
			var h: float = terrain.vertex_height(vx, vz)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo <= MAX_LEVEL_DIFF


# --- Unit orders ----------------------------------------------------------------------

## Move order in packs of GROUP_SIZE: the selection is sorted spatially so
## nearby units end up in the same group, group centres get deterministic
## formation offsets (rings), members stand tightly around their centre.
func order_move(units: Array[Unit], target: Vector3, queue_up: bool = false) -> void:
	var alive: Array[Unit] = []
	for unit in units:
		if unit.state != Unit.State.DEAD:
			alive.append(unit)
	# Spatial sort: units that stand together march together.
	alive.sort_custom(func(a: Unit, b: Unit) -> bool:
		var ka: float = a.position.z * 1000.0 + a.position.x
		var kb: float = b.position.z * 1000.0 + b.position.x
		return ka < kb)
	var group_scale: float = GROUP_SPACING / FORMATION_SPACING
	for g in range(0, alive.size(), GROUP_SIZE):
		var group_index: int = g / GROUP_SIZE
		var group_target: Vector3 = target + formation_offset(group_index) * group_scale
		for m in range(g, mini(g + GROUP_SIZE, alive.size())):
			alive[m].order_move(group_target + MEMBER_OFFSETS[m - g], queue_up)


## Braves fell the tree (and keep chopping nearby ones); non-braves just walk
## there. The wood is dropped as piles on the spot.
func order_chop(units: Array[Unit], tree: TreeResource) -> void:
	var movers: Array[Unit] = []
	for unit in units:
		if unit.state == Unit.State.DEAD:
			continue
		if unit is Brave:
			(unit as Brave).order_chop(tree)
		else:
			movers.append(unit)
	if not movers.is_empty() and is_instance_valid(tree):
		order_move(movers, tree.position)


## Braves join the construction site as workers; non-braves just walk there.
func order_build(units: Array[Unit], building: Building) -> void:
	var movers: Array[Unit] = []
	for unit in units:
		if unit.state == Unit.State.DEAD:
			continue
		if unit is Brave:
			(unit as Brave).order_build(building)
		else:
			movers.append(unit)
	if not movers.is_empty():
		order_move(movers, building.center_world())


## Braves pray at the site (mana bonus); non-braves just walk there.
func order_pray(units: Array[Unit], site: Building) -> void:
	var movers: Array[Unit] = []
	for unit in units:
		if unit.state == Unit.State.DEAD:
			continue
		if unit is Brave:
			(unit as Brave).order_pray(site)
		else:
			movers.append(unit)
	if not movers.is_empty():
		order_move(movers, site.center_world())


static func formation_offset(index: int) -> Vector3:
	if index == 0:
		return Vector3.ZERO
	var ring: int = 1
	var ring_count: int = 6
	var i: int = index - 1
	while i >= ring_count:
		i -= ring_count
		ring += 1
		ring_count += 6
	var angle: float = TAU * float(i) / float(ring_count)
	var radius: float = FORMATION_SPACING * float(ring)
	return Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
