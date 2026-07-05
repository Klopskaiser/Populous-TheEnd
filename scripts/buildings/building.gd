class_name Building extends Node3D

## Base class for all buildings. Construction happens in two phases, driven by
## worker braves (max MAX_WORKERS per site):
##   1. FLATTEN: the footprint terrain is levelled to flatten_target (workers
##      hop on their claimed cell; parallel cells = faster). Meanwhile other
##      workers fell nearby trees and pile the wood at the entrance.
##   2. BUILD: build_progress grows (capped by the delivered-wood fraction);
##      the building can only be completed once all wood has arrived. Wood
##      piles near the entrance are absorbed automatically.
## Buildings have an entrance side (orientation 0..3 = S/E/N/W) used for the
## rally point, unit spawns and wood delivery.
##
## Gameplay logic lives in tick(delta) (driven by the BuildingManager) so
## tests can tick manually. Uses local `position` like Unit.

signal construction_finished(building: Building)
signal destroyed(building: Building)

const MAX_WORKERS: int = 10
## Piles within this radius of the entrance are absorbed into the site.
const ABSORB_RADIUS: float = 5.0
const ABSORB_INTERVAL: float = 0.5
## Terrain/nav updates are batched and flushed at this interval.
const FLUSH_INTERVAL: float = 0.25
const FLATTEN_EPS: float = 0.02
## When no wood source is reachable the site stalls; after this interval it
## becomes available for workers again (they re-check for new wood/trees).
const WOOD_RECHECK_INTERVAL: float = 30.0

var tribe_id: int = 0
var tribe: Tribe = null
var max_health: int = 300
var health: int = 300
var wood_cost: int = 20
var footprint: Vector2i = Vector2i(4, 4)   # cells
var cell: Vector2i = Vector2i.ZERO         # top-left footprint cell
## Entrance side: 0 = south (+z), 1 = east (+x), 2 = north (-z), 3 = west (-x).
var orientation: int = 0
var rally_point: Vector3 = Vector3.ZERO
var under_construction: bool = true
var build_progress: float = 0.0            # 0..1
var wood_delivered: int = 0
var foundation_done: bool = false
var flatten_target: float = 0.0
## True while the site waits for wood with no source in reach: workers left
## and recruiting pauses until the re-check timer expires (or wood arrives).
var wood_stalled: bool = false
## Worker braves currently assigned to this construction site.
var workers: Array[Brave] = []

## Selection state (buildings are selectable: left-click; right-click then sets
## the rally point). `hovered` is set by the SelectionManager on mouse-over.
var selected: bool = false
var hovered: bool = false

## Height of the info overlay (production bar) above the building origin.
const OVERLAY_Y: float = 4.4

## Injected by BuildingManager.place() (or directly by tests).
var terrain_data: TerrainData = null
var nav_grid: NavGrid = null
var unit_manager: UnitManager = null
var wood_pile_manager: WoodPileManager = null

var _mesh_root: Node3D = null
var _selection_ring: MeshInstance3D = null
var _rally_marker: Node3D = null
var _overlay_sprite: Sprite3D = null
var _overlay_progress: float = -1.0
var _flatten_remaining: Dictionary[Vector2i, bool] = {}
var _flatten_claims: Dictionary[Vector2i, int] = {}
var _dirty: Rect2i = Rect2i()
var _flush_timer: float = FLUSH_INTERVAL
var _absorb_timer: float = ABSORB_INTERVAL
var _wood_recheck_timer: float = 0.0


## German display name, overridden by subclasses (UI language is German).
func display_name() -> String:
	return "Gebäude"


## Housing capacity this building contributes (Hut overrides this).
func housing_capacity() -> int:
	return 0


func footprint_rect() -> Rect2i:
	return Rect2i(cell, footprint)


## World-space centre of the footprint, Y from the terrain.
func center_world() -> Vector3:
	var wx: float = (float(cell.x) + float(footprint.x) * 0.5) * TerrainData.CELL_SIZE
	var wz: float = (float(cell.y) + float(footprint.y) * 0.5) * TerrainData.CELL_SIZE
	var wy: float = terrain_data.get_height(wx, wz) if terrain_data != null else 0.0
	return Vector3(wx, wy, wz)


## Cell just outside the footprint in the middle of the entrance side.
func entrance_cell() -> Vector2i:
	var half_x: int = footprint.x / 2
	var half_y: int = footprint.y / 2
	match orientation:
		0:
			return cell + Vector2i(half_x, footprint.y)
		1:
			return cell + Vector2i(footprint.x, half_y)
		2:
			return cell + Vector2i(half_x, -1)
		_:
			return cell + Vector2i(-1, half_y)


func entrance_world() -> Vector3:
	var c: Vector2i = entrance_cell()
	var wx: float = (float(c.x) + 0.5) * TerrainData.CELL_SIZE
	var wz: float = (float(c.y) + 0.5) * TerrainData.CELL_SIZE
	var wy: float = terrain_data.get_height(wx, wz) if terrain_data != null else 0.0
	return Vector3(wx, wy, wz)


## Radius (from the centre) at which a unit counts as "at the building".
func interact_range() -> float:
	return float(maxi(footprint.x, footprint.y)) * 0.5 * TerrainData.CELL_SIZE + 1.6


## Walkable world position for spawning units: entrance first, then the
## perimeter rings (the flattened footprint may leave a steep rim).
func edge_spawn_position() -> Vector3:
	if nav_grid != null:
		if nav_grid.is_cell_walkable(entrance_cell()):
			return nav_grid.cell_to_world(entrance_cell())
		for grow in range(1, 4):
			var rect: Rect2i = footprint_rect().grow(grow)
			var inner: Rect2i = footprint_rect().grow(grow - 1)
			for z in range(rect.position.y, rect.position.y + rect.size.y):
				for x in range(rect.position.x, rect.position.x + rect.size.x):
					var c: Vector2i = Vector2i(x, z)
					if inner.has_point(c):
						continue
					if nav_grid.is_cell_walkable(c):
						return nav_grid.cell_to_world(c)
	return entrance_world()


func _ready() -> void:
	_create_visuals()
	if _mesh_root != null:
		_mesh_root.rotation.y = float(orientation) * PI * 0.5
	_create_click_body()
	_create_selection_ring()
	_create_rally_marker()
	_create_overlay()
	_update_construction_visual()


# --- Construction setup (called by BuildingManager.place) --------------------------

## Prepares the flatten phase: target height = average footprint vertex height.
func init_construction() -> void:
	foundation_done = false
	_flatten_remaining.clear()
	_flatten_claims.clear()
	var total: float = 0.0
	var count: int = 0
	for vz in range(cell.y, cell.y + footprint.y + 1):
		for vx in range(cell.x, cell.x + footprint.x + 1):
			total += terrain_data.vertex_height(vx, vz)
			count += 1
	flatten_target = total / float(count)
	for z in range(cell.y, cell.y + footprint.y):
		for x in range(cell.x, cell.x + footprint.x):
			_flatten_remaining[Vector2i(x, z)] = true
	# The entrance cell is levelled too, so the doorway sits flush.
	var entrance: Vector2i = entrance_cell()
	if terrain_data != null and terrain_data.in_bounds(entrance):
		_flatten_remaining[entrance] = true


# --- Gameplay tick (driven by BuildingManager) -----------------------------------

func tick(delta: float) -> void:
	if under_construction:
		_tick_construction(delta)
	else:
		_tick_active(delta)
	_update_overlay()
	_update_rally_marker()


## 0..1 progress toward the next produced/trained unit, or -1 when the building
## is not currently producing (base: none). Drives the bar above the building.
func production_progress() -> float:
	return -1.0


# --- Selection & overlay --------------------------------------------------------

func set_selected(p_selected: bool) -> void:
	selected = p_selected
	if _selection_ring != null:
		_selection_ring.visible = p_selected


func set_hovered(p_hovered: bool) -> void:
	hovered = p_hovered


func _create_selection_ring() -> void:
	_selection_ring = MeshInstance3D.new()
	_selection_ring.name = "SelectionRing"
	var torus: TorusMesh = TorusMesh.new()
	var r: float = float(maxi(footprint.x, footprint.y)) * 0.5 + 0.4
	torus.inner_radius = r - 0.18
	torus.outer_radius = r
	_selection_ring.mesh = torus
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.98, 0.85, 0.45)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_selection_ring.material_override = mat
	_selection_ring.position.y = 0.12
	_selection_ring.visible = false
	add_child(_selection_ring)


## Rally-point marker (ring + little pole), shown only while the building is
## selected. Positioned in world at the rally point each tick.
func _create_rally_marker() -> void:
	_rally_marker = Node3D.new()
	_rally_marker.name = "RallyMarker"
	_rally_marker.visible = false
	add_child(_rally_marker)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.98, 0.85, 0.45)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.45
	torus.outer_radius = 0.6
	ring.mesh = torus
	ring.material_override = mat
	ring.position.y = 0.06
	_rally_marker.add_child(ring)

	var pole: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.05
	cyl.height = 1.2
	pole.mesh = cyl
	pole.material_override = mat
	pole.position.y = 0.6
	_rally_marker.add_child(pole)


func _update_rally_marker() -> void:
	if _rally_marker == null:
		return
	var show: bool = selected and rally_point != Vector3.ZERO
	_rally_marker.visible = show
	if show:
		_rally_marker.position = rally_point - position


func _create_overlay() -> void:
	_overlay_sprite = Sprite3D.new()
	_overlay_sprite.name = "ProductionBar"
	_overlay_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_overlay_sprite.shaded = false
	_overlay_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_overlay_sprite.set_draw_flag(SpriteBase3D.FLAG_DISABLE_DEPTH_TEST, true)
	_overlay_sprite.pixel_size = 0.07
	_overlay_sprite.position.y = OVERLAY_Y
	_overlay_sprite.visible = false
	add_child(_overlay_sprite)


## Shows a progress bar above the building — only while it is selected or
## hovered (and actually producing). Texture is only rebuilt when the value
## moves.
func _update_overlay() -> void:
	if _overlay_sprite == null:
		return
	var p: float = production_progress() if (selected or hovered) else -1.0
	if p < 0.0:
		if _overlay_sprite.visible:
			_overlay_sprite.visible = false
		_overlay_progress = -1.0
		return
	_overlay_sprite.visible = true
	if absf(p - _overlay_progress) < 0.02:
		return
	_overlay_progress = p
	_overlay_sprite.texture = _make_bar_texture(p)


## Dark bar background with a gold fill proportional to progress.
static func _make_bar_texture(progress: float) -> ImageTexture:
	var w: int = 32
	var h: int = 6
	var img: Image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.09, 0.06, 0.03, 0.9))
	var fill: int = clampi(int(round(clampf(progress, 0.0, 1.0) * float(w - 2))), 0, w - 2)
	if fill > 0:
		img.fill_rect(Rect2i(1, 1, fill, h - 2), Color(0.85, 0.68, 0.30))
	return ImageTexture.create_from_image(img)


func _tick_construction(delta: float) -> void:
	_flush_timer -= delta
	if _flush_timer <= 0.0:
		_flush_timer = FLUSH_INTERVAL
		_flush_deformation()
	_absorb_timer -= delta
	if _absorb_timer <= 0.0:
		_absorb_timer = ABSORB_INTERVAL
		_absorb_piles()
	if wood_stalled:
		_wood_recheck_timer -= delta
		if _wood_recheck_timer <= 0.0:
			wood_stalled = false  # workers may try again (30-s re-check)


## Subclass logic while the building is operational.
func _tick_active(_delta: float) -> void:
	pass


# --- Worker management -----------------------------------------------------------

func join(worker: Brave) -> bool:
	if worker in workers:
		return true
	if workers.size() >= MAX_WORKERS:
		return false
	workers.append(worker)
	return true


func leave(worker: Brave) -> void:
	workers.erase(worker)


# --- Flatten phase -------------------------------------------------------------------

func needs_flatten() -> bool:
	return under_construction and not foundation_done and not _flatten_remaining.is_empty()


func flatten_cell_pending(c: Vector2i) -> bool:
	return _flatten_remaining.has(c)


## True while some foundation cell has no worker on it yet (workers split:
## unclaimed cells first, spare hands fetch wood in the meantime).
func has_unclaimed_flatten_cell() -> bool:
	for c: Vector2i in _flatten_remaining.keys():
		if _flatten_claims.get(c, 0) == 0:
			return true
	return false


## Picks an unflattened cell for a worker: least claims first, then nearest.
## Returns (-1, -1) when nothing is left. Multiple workers may share a cell.
func claim_flatten_cell(from_pos: Vector3) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_score: float = INF
	var flat: Vector2 = Vector2(from_pos.x, from_pos.z)
	for c: Vector2i in _flatten_remaining.keys():
		var claims: int = _flatten_claims.get(c, 0)
		var dist: float = Vector2(float(c.x) + 0.5, float(c.y) + 0.5).distance_to(flat)
		var score: float = float(claims) * 1000.0 + dist
		if score < best_score:
			best_score = score
			best = c
	if best.x >= 0:
		_flatten_claims[best] = _flatten_claims.get(best, 0) + 1
	return best


func release_flatten_cell(c: Vector2i) -> void:
	if not _flatten_claims.has(c):
		return
	_flatten_claims[c] -= 1
	if _flatten_claims[c] <= 0:
		_flatten_claims.erase(c)


## One worker's flatten contribution on a cell: moves its 4 corner vertices
## toward flatten_target by `amount` metres. Returns true when the cell is
## level (several workers on one cell stack their contributions).
func work_flatten(c: Vector2i, amount: float) -> bool:
	if foundation_done:
		return true
	if not _flatten_remaining.has(c):
		return true
	var done: bool = true
	for dz in range(2):
		for dx in range(2):
			var h: float = terrain_data.vertex_height(c.x + dx, c.y + dz)
			var nh: float = move_toward(h, flatten_target, amount)
			terrain_data.set_vertex_height(c.x + dx, c.y + dz, nh)
			if absf(nh - flatten_target) > FLATTEN_EPS:
				done = false
	_mark_dirty(c)
	if done:
		_flatten_remaining.erase(c)
		if _flatten_remaining.is_empty():
			foundation_done = true
			position.y = flatten_target  # settle onto the levelled ground
			_flush_deformation()
	return done


func _mark_dirty(c: Vector2i) -> void:
	var r: Rect2i = Rect2i(c, Vector2i(1, 1))
	_dirty = r if _dirty.size == Vector2i.ZERO else _dirty.merge(r)


## Pushes batched terrain changes to navigation and (via Events) to the
## terrain mesh. Grown by 1 because edge vertices affect neighbouring cells.
func _flush_deformation() -> void:
	if _dirty.size == Vector2i.ZERO:
		return
	var r: Rect2i = _dirty.grow(1)
	_dirty = Rect2i()
	if nav_grid != null:
		nav_grid.update_region(r)
	if is_inside_tree():
		var events: Node = get_node_or_null("/root/Events")
		if events != null:
			events.terrain_deformed.emit(r)


# --- Wood delivery ---------------------------------------------------------------------

func wood_needed_total() -> int:
	return maxi(0, wood_cost - wood_delivered)


## Wood already on its way: carried by workers, on claimed trees and lying in
## piles near the entrance (those get absorbed automatically).
func wood_incoming() -> int:
	var total: int = 0
	for worker in workers:
		if is_instance_valid(worker):
			total += worker.carried_wood + worker.claimed_tree_yield()
	if wood_pile_manager != null:
		total += wood_pile_manager.wood_in_radius(entrance_world(), ABSORB_RADIUS)
	return total


## True while workers should still fetch more wood.
func wants_more_wood() -> bool:
	return under_construction and wood_needed_total() > wood_incoming()


## Progress ceiling from the delivered-wood fraction.
func progress_cap() -> float:
	if wood_cost <= 0:
		return 1.0
	return float(wood_delivered) / float(wood_cost)


## Called by workers when no wood source is reachable anywhere: the site
## pauses (workers leave, recruiting skips it) until the re-check interval
## expires or wood arrives at the entrance.
func mark_wood_stalled() -> void:
	if wood_stalled:
		return
	wood_stalled = true
	_wood_recheck_timer = WOOD_RECHECK_INTERVAL


func _absorb_piles() -> void:
	if wood_pile_manager == null:
		return
	var need: int = wood_needed_total()
	if need <= 0:
		return
	var taken: int = wood_pile_manager.take_from_radius(entrance_world(), ABSORB_RADIUS, need)
	if taken > 0:
		wood_delivered += taken
		wood_stalled = false  # fresh wood on site: back to work


# --- Build phase --------------------------------------------------------------------------

## Adds construction progress, capped by the delivered-wood fraction — the
## building can only be completed once all wood is on site. Requires the
## foundation to be flattened first.
func add_build_progress(amount: float) -> void:
	if not under_construction or not foundation_done:
		return
	build_progress = clampf(build_progress + amount, 0.0, progress_cap())
	_update_construction_visual()
	if build_progress >= 1.0:
		finish_construction()


func finish_construction() -> void:
	if not under_construction:
		return
	under_construction = false
	foundation_done = true
	build_progress = 1.0
	_flatten_remaining.clear()
	_flatten_claims.clear()
	_flush_deformation()
	_update_construction_visual()
	construction_finished.emit(self)
	if tribe != null:
		tribe.notify_housing_changed()


# --- Damage / destruction ------------------------------------------------------------

func take_damage(amount: int) -> void:
	if health <= 0:
		return
	health -= amount
	if health <= 0:
		health = 0
		destroy()


## Frees the NavGrid footprint, deregisters from the tribe and removes the node.
func destroy() -> void:
	if nav_grid != null:
		nav_grid.fill_solid_region(footprint_rect(), false)
	if tribe != null:
		tribe.remove_building(self)
	destroyed.emit(self)
	if is_inside_tree():
		var events: Node = get_node_or_null("/root/Events")
		if events != null:
			events.building_destroyed.emit(self)
		queue_free()


# --- Visuals (placeholder meshes, created in _ready only) ----------------------------

## Subclasses build their placeholder meshes under _mesh_root. The root is
## rotated by `orientation`, so meshes are authored with the entrance south.
func _create_visuals() -> void:
	_mesh_root = Node3D.new()
	_mesh_root.name = "MeshRoot"
	add_child(_mesh_root)


## Small tribe-coloured flag next to the building.
func _add_flag() -> void:
	if _mesh_root == null:
		return
	var pole: MeshInstance3D = MeshInstance3D.new()
	var pole_mesh: CylinderMesh = CylinderMesh.new()
	pole_mesh.top_radius = 0.05
	pole_mesh.bottom_radius = 0.05
	pole_mesh.height = 2.4
	pole.mesh = pole_mesh
	pole.position = Vector3(float(footprint.x) * 0.5 - 0.2, 1.2, float(footprint.y) * 0.5 - 0.2)
	_mesh_root.add_child(pole)
	var flag: MeshInstance3D = MeshInstance3D.new()
	var flag_mesh: BoxMesh = BoxMesh.new()
	flag_mesh.size = Vector3(0.7, 0.4, 0.05)
	flag.mesh = flag_mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Unit.TRIBE_COLORS[tribe_id % Unit.TRIBE_COLORS.size()]
	flag.material_override = mat
	flag.position = pole.position + Vector3(0.35, 1.0, 0.0)
	_mesh_root.add_child(flag)


func _make_material(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	return mat


## StaticBody3D + BoxShape3D on layer 2 for mouse-ray selection/targeting.
func _create_click_body() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "ClickBody"
	body.collision_layer = 2
	body.collision_mask = 0
	body.set_meta("building", self)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(float(footprint.x), 2.5, float(footprint.y))
	shape.shape = box
	shape.position.y = 1.25
	body.add_child(shape)
	add_child(body)


## The building "grows out of the ground" with the build progress
## (placeholder); during the flatten phase only a sliver is visible.
func _update_construction_visual() -> void:
	if _mesh_root == null:
		return
	var s: float = 1.0 if not under_construction else 0.1 + 0.9 * build_progress
	_mesh_root.scale = Vector3(1.0, maxf(s, 0.05), 1.0)
