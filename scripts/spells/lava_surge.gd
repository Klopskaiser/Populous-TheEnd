class_name LavaSurge extends Node3D

## One volcanic eruption wave: red, viscous lava wells up at the crater and
## creeps down the flanks. Phase 10c replaced the single expanding radius with
## LAVA_SECTORS independent fronts: every sector probes the terrain gradient at
## its own front point and advances with LavaCommon.flow_speed — so the mass
## RUNS down the steep flanks, dawdles on flat ground and piles up where it
## would have to climb. While molten it ignites every unit it covers
## (Unit.ignite — lava knows no friends); the sheet then cools sector by sector
## and stays behind as a black scorch skirt until the node expires. Visual: a
## sheet built on the TERRAIN'S OWN GRID (so it lies exactly parallel to the
## ground and no rock can poke through), with a ragged front drawn by the lava
## shader; in-game only. Ticked via the UnitManager projectile list.

const INNER_RADIUS: float = 0.5      # crater rim
## How long a patch keeps glowing after the front passed it.
const MOLTEN_TIME: float = Balance.LAVA_MOLTEN_TIME
## Default life; the catapult puddle overrides `lifetime` with its own value.
const LIFETIME: float = Balance.LAVA_LIFETIME
## Over the last stretch of its life the sheet SINKS into the ground
## instead of popping out of existence.
const SINK_TIME: float = 1.2
const SINK_DEPTH: float = 0.9
const CHECK_INTERVAL: float = Balance.LAVA_CONTACT_INTERVAL
const VISUAL_INTERVAL: float = Balance.LAVA_VISUAL_INTERVAL
## Independent fronts around the crater.
const LAVA_SECTORS: int = 20
## How far the sheet floats above the ground it covers. The sheet used to be a
## polar ring mesh, whose triangles cut CHORDS through the curved terrain — on
## the volcano's cone the rock poked back through the lava however much lift
## was added (user reports, twice). Since 2026-11-15 the sheet reuses the
## terrain's own vertices and its own triangle split, so it is the ground
## surface moved up by exactly this much — a few centimetres are enough.
const SURFACE_LIFT: float = 0.08
## Width of the soft edge the shader frays (metres): the coverage falls from 1
## to 0 over this distance in front of a sector's front, and the sheet reaches
## EDGE_REACH beyond the front so the visible edge sits on it, not inside it.
const EDGE_WIDTH: float = 0.9
const EDGE_REACH: float = 0.35

var done: bool = false
var unit_manager: UnitManager = null
var terrain_data: TerrainData = null
var max_radius: float = 5.5
var building_manager: BuildingManager = null
## Buildings touched by the molten sheet accumulate lava contact (destruction
## stages, see Building.add_lava_contact). Off for the catapult puddle when the
## projectile itself already damaged a building (no double punishment).
var damage_buildings: bool = true
## Per-use tuning (the catapult puddle has its own value).
var lifetime: float = LIFETIME

var _life: float = 0.0
var _check_timer: float = 0.0
## Real time elapsed since the last check step — the throttle only decides
## WHEN a step runs, this decides how much ground it covers.
var _since_check: float = 0.0
var _visual_timer: float = 0.0
var _mesh: MeshInstance3D = null
## Per-sector front radius and the time at which that front last advanced —
## the sector stops glowing MOLTEN_TIME after it came to a halt.
var _sector_radius: PackedFloat32Array = PackedFloat32Array()
var _sector_front_time: PackedFloat32Array = PackedFloat32Array()
## Terrain steepness at each sector's front, taken from the same gradient
## probe that drives the flow — the mesh reuses it to lift itself clear of
## the rock, so it costs no extra samples (the mesh no longer needs it since it
## follows the terrain grid, 2026-11-15).
var _sector_slope: PackedFloat32Array = PackedFloat32Array()
var _front_radius: float = INNER_RADIUS   # largest sector radius (hull circle)


func _init() -> void:
	_sector_radius.resize(LAVA_SECTORS)
	_sector_front_time.resize(LAVA_SECTORS)
	_sector_slope.resize(LAVA_SECTORS)
	_sector_radius.fill(INNER_RADIUS)
	_sector_front_time.fill(0.0)
	_sector_slope.fill(0.0)


func setup(at: Vector3, p_unit_manager: UnitManager,
		p_terrain_data: TerrainData, p_max_radius: float = 5.5,
		p_building_manager: BuildingManager = null) -> void:
	position = at
	unit_manager = p_unit_manager
	terrain_data = p_terrain_data
	max_radius = p_max_radius
	building_manager = p_building_manager


## True while ANY sector is still glowing (damage window). A sector glows for
## MOLTEN_TIME after its front last moved, so a sheet that has stalled all
## round (flat ground, uphill) cools off while one still running down a flank
## keeps the whole surge molten.
func is_molten() -> bool:
	for i in range(LAVA_SECTORS):
		if _life - _sector_front_time[i] < MOLTEN_TIME:
			return true
	return false


func tick(delta: float) -> void:
	if done:
		return
	_life += delta
	if _life >= lifetime:
		done = true
		return
	_since_check += delta
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = CHECK_INTERVAL
		var step: float = _since_check
		_since_check = 0.0
		_advance_sectors(step)
		if is_molten():
			_ignite_covered_units()
			_touch_buildings(step)
	_visual_timer -= delta
	if _visual_timer <= 0.0:
		_visual_timer = VISUAL_INTERVAL
		_rebuild_mesh()


## One gradient probe per sector, at that sector's own front point: the flow
## law turns the outward descent into a speed (uphill -> 0, the mass piles up).
func _advance_sectors(step: float) -> void:
	var largest: float = INNER_RADIUS
	for i in range(LAVA_SECTORS):
		var r: float = _sector_radius[i]
		if r < max_radius:
			var dir: Vector3 = _sector_dir(i)
			var slope: float = 0.0
			if terrain_data != null:
				var grad: Vector3 = LavaCommon.downhill(terrain_data,
					position.x + dir.x * r, position.z + dir.z * r)
				slope = grad.dot(dir)
				_sector_slope[i] = grad.length()
			var advance: float = LavaCommon.flow_speed(slope) * step
			if advance > 0.0:
				r = minf(r + advance, max_radius)
				_sector_radius[i] = r
				_sector_front_time[i] = _life
		largest = maxf(largest, r)
	_front_radius = largest


func _sector_dir(i: int) -> Vector3:
	var a: float = TAU * float(i) / float(LAVA_SECTORS)
	return Vector3(cos(a), 0.0, sin(a))


## ONE spatial query over the hull circle, then each unit is assigned to its
## sector via atan2 and tested against THAT sector's front radius — the ragged
## sheet burns exactly what it covers without twenty separate queries.
func _ignite_covered_units() -> void:
	if unit_manager == null:
		return
	for u in unit_manager.get_units_in_radius(position, _front_radius):
		if u.state == Unit.State.DEAD or u.is_airborne():
			continue   # airborne units (thrown, airship deck) pass over the lava
		var dx: float = u.position.x - position.x
		var dz: float = u.position.z - position.z
		if dx * dx + dz * dz > _sector_radius_at(dx, dz) ** 2:
			continue
		# Pass this surge as the fire source: a fire ram in the lava takes ONE
		# life from a given puddle no matter how long it stands there; a fresh
		# surge (new catapult shot) is a new source and costs another life.
		u.ignite(position, self)
	# Lava also sets trees and wood piles alight (phase 7d) — like the lava
	# flow. Both are cheap radius queries, so they use the hull circle.
	if unit_manager.tree_manager != null:
		unit_manager.tree_manager.ignite_in_radius(position, _front_radius)
	if unit_manager.wood_pile_manager != null:
		unit_manager.wood_pile_manager.ignite_in_radius(position, _front_radius)


## Front radius of the sector that contains the offset (dx, dz).
func _sector_radius_at(dx: float, dz: float) -> float:
	var a: float = fposmod(atan2(dz, dx), TAU)
	var i: int = int(a / TAU * float(LAVA_SECTORS)) % LAVA_SECTORS
	return _sector_radius[i]


## Buildings covered by the molten sheet rack up lava contact time — one
## destruction stage per full Balance.LAVA_BUILDING_STAGE_TIME of it. The hull
## circle is enough here: a footprint is far larger than one sector's slice.
func _touch_buildings(step: float) -> void:
	if building_manager == null or not damage_buildings:
		return
	var flat: Vector2 = Vector2(position.x, position.z)
	for b in building_manager.buildings.duplicate():
		if not is_instance_valid(b) or b.health <= 0:
			continue
		if b.footprint_distance_to(flat) <= _front_radius:
			b.add_lava_contact(step)


# --- Radial sheet visual (in-game only) -----------------------------------------------

## Seconds since the front of sector `i` passed the band at radius r. Linear
## between "poured at spawn" at the crater rim and "just now" at the front —
## exact inversion is impossible with per-sector variable speeds, and the ramp
## only feeds the colour.
func _band_age(i: int, r: float) -> float:
	var front: float = _sector_radius[i]
	if front <= INNER_RADIUS + 0.001:
		return _life
	var u: float = clampf((r - INNER_RADIUS) / (front - INNER_RADIUS), 0.0, 1.0)
	return _life - u * _sector_front_time[i]


func _band_color(i: int, r: float) -> Color:
	var age: float = _band_age(i, r)
	return LavaCommon.color_for(age, MOLTEN_TIME, age >= MOLTEN_TIME, true)


## Front radius in the direction (dx, dz), interpolated between the two
## neighbouring sectors — the mesh edge must not jump at a sector boundary.
func _front_at(dx: float, dz: float) -> float:
	var f: float = fposmod(atan2(dz, dx), TAU) / TAU * float(LAVA_SECTORS)
	var i: int = int(f) % LAVA_SECTORS
	return lerpf(_sector_radius[i], _sector_radius[(i + 1) % LAVA_SECTORS], f - floorf(f))


## The sheet, built on the terrain's own grid: every terrain cell the lava
## reaches contributes its two triangles — the same vertices and the same
## diagonal as the terrain mesh (Terrain: tl-tr-bl, tr-br-bl) — lifted by
## SURFACE_LIFT. It therefore lies exactly parallel to the ground; nothing can
## poke through. The ragged front is not geometry any more: each vertex carries
## its COVERAGE (1 inside, 0 beyond the front) and the shader frays the edge.
## Geometry is static for unchanged fronts (no animated factor in here).
## Rebuilt throttled.
func _rebuild_mesh() -> void:
	if _mesh == null or terrain_data == null:
		return
	var im: ImmediateMesh = _mesh.mesh
	im.clear_surfaces()
	if _front_radius <= INNER_RADIUS + 0.05:
		return
	var td: TerrainData = terrain_data
	var cs: float = TerrainData.CELL_SIZE
	var reach: float = _front_radius + EDGE_REACH + cs
	var x0: int = clampi(int(floor((position.x - reach) / cs)), 0, td.size - 1)
	var x1: int = clampi(int(floor((position.x + reach) / cs)), 0, td.size - 1)
	var z0: int = clampi(int(floor((position.z - reach) / cs)), 0, td.size - 1)
	var z1: int = clampi(int(floor((position.z + reach) / cs)), 0, td.size - 1)
	var cols: int = x1 - x0 + 2
	var rows: int = z1 - z0 + 2
	var sink: float = _sink_offset()
	# One pass over the grid vertices: position, colour, heat and coverage.
	var pts: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var uvs: PackedVector2Array = PackedVector2Array()
	pts.resize(cols * rows)
	colors.resize(cols * rows)
	uvs.resize(cols * rows)
	for rz in range(rows):
		for rx in range(cols):
			var vx: int = x0 + rx
			var vz: int = z0 + rz
			var xz: Vector2 = td.vertex_mesh_xz(vx, vz)
			var dx: float = xz.x - position.x
			var dz: float = xz.y - position.z
			var r: float = sqrt(dx * dx + dz * dz)
			var k: int = rz * cols + rx
			pts[k] = Vector3(dx, td.heights[vz * td.verts + vx] + SURFACE_LIFT - sink
				- position.y, dz)
			var sector: int = int(fposmod(atan2(dz, dx), TAU) / TAU
				* float(LAVA_SECTORS)) % LAVA_SECTORS
			var inside: float = minf(r, _sector_radius[sector])
			var age: float = _band_age(sector, inside)
			var cooled: bool = age >= MOLTEN_TIME
			colors[k] = LavaCommon.color_for(age, MOLTEN_TIME, cooled, true)
			uvs[k] = Vector2(LavaCommon.heat_for(age, MOLTEN_TIME, cooled),
				clampf((_front_at(dx, dz) + EDGE_REACH - r) / EDGE_WIDTH, 0.0, 1.0))
	var begun: bool = false
	for rz in range(rows - 1):
		for rx in range(cols - 1):
			var tl: int = rz * cols + rx
			var tr: int = tl + 1
			var bl: int = tl + cols
			var br: int = bl + 1
			if uvs[tl].y <= 0.0 and uvs[tr].y <= 0.0 and uvs[bl].y <= 0.0 \
					and uvs[br].y <= 0.0:
				continue   # the lava has not reached this cell
			if not td.has_ground((float(x0 + rx) + 0.5) * cs, (float(z0 + rz) + 0.5) * cs):
				continue   # the void beyond the disc's rim
			if not begun:
				im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
				begun = true
			for k in [tl, tr, bl, tr, br, bl]:
				im.surface_set_color(colors[k])
				im.surface_set_uv(uvs[k])
				im.surface_add_vertex(pts[k])
	if begun:
		im.surface_end()


## Downward offset at the end of life: the crust sinks into the ground.
func _sink_offset() -> float:
	var t: float = clampf((_life - (lifetime - SINK_TIME)) / SINK_TIME, 0.0, 1.0)
	return t * SINK_DEPTH


func _ready() -> void:
	# Shared by every lava source (volcano surge, catapult puddle) — throttled
	# because an eruption stacks several of these.
	SpellAudio.play_named(self, &"lava_start", global_position, 250)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = ImmediateMesh.new()
	_mesh.material_override = LavaCommon.make_material()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
