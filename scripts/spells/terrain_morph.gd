class_name TerrainMorph extends Node3D

## Gradual terraforming shared by all terrain spells (landbridge, earthquake,
## volcano, flatten, sink): interpolates the affected vertices from their
## start heights to a target height map over `duration` seconds, in throttled
## steps (never per frame — chunk/collision rebuilds are batched per step).
## Trees, wood piles and buildings inside the area are re-snapped to the
## moving ground each step; units snap their own Y every tick anyway. The
## terrain-integrity rules (foundation break, flooding) run inside
## ctx.apply_terrain_change per step. Ticked via the UnitManager projectile
## list.

const STEP_INTERVAL: float = 0.15

var done: bool = false
var ctx: SpellContext = null
var duration: float = 3.0

var _indices: PackedInt32Array = PackedInt32Array()
var _from: PackedFloat32Array = PackedFloat32Array()
var _to: PackedFloat32Array = PackedFloat32Array()
var _rect: Rect2i = Rect2i()
var _time: float = 0.0
var _step_timer: float = 0.0


## `plan` is a target height map {indices: PackedInt32Array, targets:
## PackedFloat32Array, rect: Rect2i} (e.g. from TerrainData.line_raise_targets
## or a spell's own planner); start heights are captured now so the morph
## lerps from the cast moment.
func setup(p_ctx: SpellContext, plan: Dictionary, p_duration: float) -> void:
	ctx = p_ctx
	duration = maxf(p_duration, 0.05)
	_indices = plan.indices
	_to = plan.targets
	_rect = plan.rect
	var td: TerrainData = ctx.terrain_data
	_from.resize(_indices.size())
	for i in range(_indices.size()):
		_from[i] = td.heights[_indices[i]]


func tick(delta: float) -> void:
	if done:
		return
	_time += delta
	_step_timer -= delta
	if _step_timer > 0.0 and _time < duration:
		return
	_step_timer = STEP_INTERVAL
	var t: float = clampf(_time / duration, 0.0, 1.0)
	var smooth: float = t * t * (3.0 - 2.0 * t)
	var td: TerrainData = ctx.terrain_data
	for i in range(_indices.size()):
		td.heights[_indices[i]] = lerpf(_from[i], _to[i], smooth)
	ctx.apply_terrain_change(_rect)
	_snap_props()
	if t >= 1.0:
		done = true


## Keeps everything on the moving ground: units (idle ones never re-snap
## their Y on their own), trees and wood piles inside the rect follow the
## surface, buildings re-seat on their footprint centre. Airborne units
## (thrown/whirled or riding an airship deck) and airships themselves keep
## flying — the airship runs its own soft altitude model and must never be
## yanked to the ground while the terrain reshapes beneath it.
func _snap_props() -> void:
	var td: TerrainData = ctx.terrain_data
	var grown: Rect2i = _rect.grow(1)
	if ctx.unit_manager != null:
		for u in ctx.unit_manager.units:
			if not is_instance_valid(u) or u.is_airborne() or u is Airship:
				continue
			if grown.has_point(_world_cell(u.position)):
				u.position.y = td.get_height(u.position.x, u.position.z)
				u._sync_soa_pos()
	if ctx.tree_manager != null:
		for tree in ctx.tree_manager.trees:
			if not is_instance_valid(tree):
				continue
			if grown.has_point(_world_cell(tree.position)):
				tree.position.y = td.get_height(tree.position.x, tree.position.z)
	if ctx.wood_pile_manager != null:
		for pile in ctx.wood_pile_manager.piles:
			if not is_instance_valid(pile):
				continue
			if grown.has_point(_world_cell(pile.position)):
				pile.position.y = td.get_height(pile.position.x, pile.position.z)
	if ctx.building_manager != null:
		for b in ctx.building_manager.buildings:
			if not is_instance_valid(b):
				continue
			if grown.intersects(b.footprint_rect().grow(1)):
				var c: Vector3 = b.center_world()
				b.position.y = td.get_height(c.x, c.z)


static func _world_cell(pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(pos.x / TerrainData.CELL_SIZE)),
		int(floor(pos.z / TerrainData.CELL_SIZE)))
