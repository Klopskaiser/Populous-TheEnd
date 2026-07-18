class_name LavaSurge extends Node3D

## One volcanic eruption wave: liquid lava wells up at the crater and runs
## down ALL flanks simultaneously — a radial sheet whose front expands
## quickly to max_radius, hugging the cone. While molten it ignites every
## unit it covers (Unit.ignite — lava knows no friends); the sheet then
## cools from the crater outward and stays behind as a black scorch skirt
## until the node expires. Visual: a terrain-conforming radial mesh with a
## viscous colour gradient (glowing front, darkening tail), in-game only.
## Ticked via the UnitManager projectile list.

const EXPAND_SPEED: float = 3.2      # the front races down the flank
const INNER_RADIUS: float = 0.5      # crater rim
## How long a band keeps glowing after the front passed it.
const MOLTEN_TIME: float = 1.5
const LIFETIME: float = 5.4
## Over the last stretch of its life the sheet SINKS into the ground
## instead of popping out of existence.
const SINK_TIME: float = 1.2
const SINK_DEPTH: float = 0.9
const CHECK_INTERVAL: float = 0.2
const VISUAL_INTERVAL: float = 0.1
const ANGLE_STEPS: int = 24
const RING_STEP: float = 0.8

var done: bool = false
var unit_manager: UnitManager = null
var terrain_data: TerrainData = null
var max_radius: float = 5.5
var building_manager: BuildingManager = null
## Buildings touched by the molten sheet accumulate lava contact (destruction
## stages, see Building.add_lava_contact). Off for the catapult puddle when the
## projectile itself already damaged a building (no double punishment).
var damage_buildings: bool = true

var _radius: float = INNER_RADIUS
var _life: float = 0.0
var _check_timer: float = 0.0
var _visual_timer: float = 0.0
var _mesh: MeshInstance3D = null


func setup(at: Vector3, p_unit_manager: UnitManager,
		p_terrain_data: TerrainData, p_max_radius: float = 5.5,
		p_building_manager: BuildingManager = null) -> void:
	position = at
	unit_manager = p_unit_manager
	terrain_data = p_terrain_data
	max_radius = p_max_radius
	building_manager = p_building_manager


## True while any band of the sheet is still glowing (damage window).
func is_molten() -> bool:
	return _life <= (max_radius - INNER_RADIUS) / EXPAND_SPEED + MOLTEN_TIME


func tick(delta: float) -> void:
	if done:
		return
	_life += delta
	if _life >= LIFETIME:
		done = true
		return
	if _radius < max_radius:
		_radius = minf(_radius + EXPAND_SPEED * delta, max_radius)
	if is_molten():
		_check_timer -= delta
		if _check_timer <= 0.0:
			_check_timer = CHECK_INTERVAL
			_ignite_covered_units()
			_touch_buildings()
	_visual_timer -= delta
	if _visual_timer <= 0.0:
		_visual_timer = VISUAL_INTERVAL
		_rebuild_mesh()


func _ignite_covered_units() -> void:
	if unit_manager == null:
		return
	for u in unit_manager.get_units_in_radius(position, _radius):
		if u.state == Unit.State.DEAD or u.state == Unit.State.THROWN:
			continue   # airborne units pass over the lava
		u.ignite(position)
	# Lava also sets trees and wood piles alight (phase 7d) — like the lava flow.
	if unit_manager.tree_manager != null:
		unit_manager.tree_manager.ignite_in_radius(position, _radius)
	if unit_manager.wood_pile_manager != null:
		unit_manager.wood_pile_manager.ignite_in_radius(position, _radius)


## Buildings covered by the molten sheet rack up lava contact time — one
## destruction stage per full Balance.LAVA_BUILDING_STAGE_TIME of it.
func _touch_buildings() -> void:
	if building_manager == null or not damage_buildings:
		return
	var flat: Vector2 = Vector2(position.x, position.z)
	for b in building_manager.buildings.duplicate():
		if not is_instance_valid(b) or b.health <= 0:
			continue
		if b.footprint_distance_to(flat) <= _radius:
			b.add_lava_contact(CHECK_INTERVAL)


# --- Radial sheet visual (in-game only) -----------------------------------------------

## Seconds since the expanding front passed a band at radius r; < 0 while
## the front has not reached it yet.
func _band_age(r: float) -> float:
	return _life - (r - INNER_RADIUS) / EXPAND_SPEED


func _band_color(r: float) -> Color:
	var age: float = _band_age(r)
	var t: float = clampf(age / MOLTEN_TIME, 0.0, 1.0)
	# Glowing fresh lava at the front -> viscous dark red -> black scorch.
	if t >= 1.0:
		return Color(0.06, 0.05, 0.04, 1.0)
	return Color(1.0, 0.55, 0.08, 1.0).lerp(Color(0.4, 0.09, 0.02, 1.0), t)


## Terrain-conforming radial triangle strips from the crater rim out to the
## current front. ~24 sectors x a handful of rings, rebuilt throttled.
func _rebuild_mesh() -> void:
	if _mesh == null or terrain_data == null:
		return
	var im: ImmediateMesh = _mesh.mesh
	im.clear_surfaces()
	if _radius <= INNER_RADIUS + 0.05:
		return
	var rings: Array[float] = []
	var r: float = INNER_RADIUS
	while r < _radius:
		rings.append(r)
		r += RING_STEP
	rings.append(_radius)
	for band in range(rings.size() - 1):
		var r0: float = rings[band]
		var r1: float = rings[band + 1]
		var c0: Color = _band_color(r0)
		var c1: Color = _band_color(r1)
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for a in range(ANGLE_STEPS + 1):
			var angle: float = TAU * float(a) / float(ANGLE_STEPS)
			var dir: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
			# Viscous, uneven front: the outer edge bulges per sector.
			var bulge: float = 1.0 + 0.06 * sin(angle * 5.0 + _life * 2.5)
			im.surface_set_color(c1)
			im.surface_add_vertex(_sheet_point(dir, r1 * bulge))
			im.surface_set_color(c0)
			im.surface_add_vertex(_sheet_point(dir, r0))
		im.surface_end()


## Downward offset at the end of life: the crust sinks into the ground.
func _sink_offset() -> float:
	var t: float = clampf((_life - (LIFETIME - SINK_TIME)) / SINK_TIME, 0.0, 1.0)
	return t * SINK_DEPTH


func _sheet_point(dir: Vector3, r: float) -> Vector3:
	var wx: float = position.x + dir.x * r
	var wz: float = position.z + dir.z * r
	return Vector3(wx - position.x,
		terrain_data.get_height(wx, wz) + 0.08 - _sink_offset() - position.y,
		wz - position.z)


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = ImmediateMesh.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = mat
	add_child(_mesh)
