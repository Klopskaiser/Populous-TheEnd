class_name LandbridgeMorph extends Node3D

## Gradual terraforming of a Landbridge cast: interpolates the affected
## vertices from their start heights to the corridor's target profile
## (TerrainData.line_raise_targets) over DURATION seconds, in throttled steps
## (never per frame — chunk/collision rebuilds are batched per step). Trees,
## wood piles and buildings inside the area are re-snapped to the moving
## ground each step; units snap their own Y every tick anyway. Ticked via the
## UnitManager projectile list.

const DURATION: float = 3.0
const STEP_INTERVAL: float = 0.15

var done: bool = false
var ctx: SpellContext = null

var _indices: PackedInt32Array = PackedInt32Array()
var _from: PackedFloat32Array = PackedFloat32Array()
var _to: PackedFloat32Array = PackedFloat32Array()
var _rect: Rect2i = Rect2i()
var _time: float = 0.0
var _step_timer: float = 0.0


## `plan` comes from TerrainData.line_raise_targets (indices/targets/rect);
## start heights are captured now so the morph lerps from the cast moment.
func setup(p_ctx: SpellContext, plan: Dictionary) -> void:
	ctx = p_ctx
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
	if _step_timer > 0.0 and _time < DURATION:
		return
	_step_timer = STEP_INTERVAL
	var t: float = clampf(_time / DURATION, 0.0, 1.0)
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
## surface, buildings re-seat on their footprint centre. Airborne (thrown)
## units keep flying.
func _snap_props() -> void:
	var td: TerrainData = ctx.terrain_data
	var grown: Rect2i = _rect.grow(1)
	if ctx.unit_manager != null:
		for u in ctx.unit_manager.units:
			if not is_instance_valid(u) or u.state == Unit.State.THROWN:
				continue
			if grown.has_point(_world_cell(u.position)):
				u.position.y = td.get_height(u.position.x, u.position.z)
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
