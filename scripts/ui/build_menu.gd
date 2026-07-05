class_name BuildMenu extends Control

## Build UI (German labels): a button/hotkey enters placement mode, a ghost
## mesh (including an entrance marker) follows the mouse over the terrain
## (green = valid, red = invalid), R rotates the entrance side, left click
## places the construction site via TribeCommands.place_building(), Esc or
## right click cancels. No wood is paid up front — braves deliver it to the
## site. While placement mode is active the SelectionManager ignores mouse
## input (it checks is_active()).

const RAY_LENGTH: float = 1000.0
const TERRAIN_MASK: int = 1   # ghost snaps to terrain only
const COLOR_VALID: Color = Color(0.2, 1.0, 0.3, 0.45)
const COLOR_INVALID: Color = Color(1.0, 0.2, 0.2, 0.45)

const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")

var _tribe_commands: TribeCommands = null
var _nav_grid: NavGrid = null
var _world_root: Node3D = null   # parent for the ghost mesh
var _tribe: Tribe = null

var _build_scene: PackedScene = null
var _build_footprint: Vector2i = Vector2i.ONE
var _orientation: int = 0        # entrance side, rotated with R
var _ghost: MeshInstance3D = null
var _ghost_material: StandardMaterial3D = null
var _entrance_marker: MeshInstance3D = null
var _ghost_cell: Vector2i = Vector2i.ZERO
var _ghost_valid: bool = false


func setup(p_tribe_commands: TribeCommands, p_nav_grid: NavGrid,
		p_world_root: Node3D, p_tribe: Tribe) -> void:
	_tribe_commands = p_tribe_commands
	_nav_grid = p_nav_grid
	_world_root = p_world_root
	_tribe = p_tribe


func is_active() -> bool:
	return _build_scene != null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar: HBoxContainer = HBoxContainer.new()
	bar.name = "Bar"
	bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bar.position = Vector2(12, -52)
	add_child(bar)
	var hut_button: Button = Button.new()
	hut_button.text = "Hütte (%d Holz) [H]" % Hut.WOOD_COST
	hut_button.tooltip_text = "R = Eingang drehen, Esc = abbrechen"
	hut_button.pressed.connect(_on_hut_button)
	bar.add_child(hut_button)


func _on_hut_button() -> void:
	if is_active():
		_exit_build_mode()
	else:
		_enter_build_mode(HUT_SCENE)


func _enter_build_mode(scene: PackedScene) -> void:
	var probe: Building = scene.instantiate() as Building
	if probe == null:
		return
	_build_footprint = probe.footprint
	probe.free()
	_build_scene = scene
	_create_ghost()


func _exit_build_mode() -> void:
	_build_scene = null
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
		_entrance_marker = null


func _create_ghost() -> void:
	if _world_root == null:
		return
	_ghost = MeshInstance3D.new()
	_ghost.name = "BuildGhost"
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(float(_build_footprint.x), 1.6, float(_build_footprint.y))
	_ghost.mesh = box
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_material.albedo_color = COLOR_INVALID
	_ghost.material_override = _ghost_material
	_ghost.visible = false
	_world_root.add_child(_ghost)

	# Entrance marker: a small block on the entrance side of the footprint.
	_entrance_marker = MeshInstance3D.new()
	var marker_box: BoxMesh = BoxMesh.new()
	marker_box.size = Vector3(0.8, 0.5, 0.8)
	_entrance_marker.mesh = marker_box
	var marker_mat: StandardMaterial3D = StandardMaterial3D.new()
	marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mat.albedo_color = Color(1.0, 0.9, 0.2, 0.8)
	_entrance_marker.material_override = marker_mat
	_ghost.add_child(_entrance_marker)
	_update_entrance_marker()


func _update_entrance_marker() -> void:
	if _entrance_marker == null:
		return
	var dirs: Array[Vector3] = [
		Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)]
	var dist: float = float(maxi(_build_footprint.x, _build_footprint.y)) * 0.5 + 0.5
	_entrance_marker.position = dirs[_orientation] * dist + Vector3(0.0, -0.55, 0.0)


func _process(_delta: float) -> void:
	if not is_active() or _ghost == null:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var from: Vector3 = camera.project_ray_origin(mouse)
	var dir: Vector3 = camera.project_ray_normal(mouse)
	var space: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, from + dir * RAY_LENGTH)
	query.collision_mask = TERRAIN_MASK
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		_ghost.visible = false
		_ghost_valid = false
		return
	# Centre the footprint on the cursor cell.
	var hit_cell: Vector2i = _nav_grid.world_to_cell(hit.position)
	_ghost_cell = hit_cell - _build_footprint / 2
	_ghost_valid = _tribe_commands.can_place_at(_ghost_cell, _build_footprint)
	_ghost_material.albedo_color = COLOR_VALID if _ghost_valid else COLOR_INVALID
	var wx: float = (float(_ghost_cell.x) + float(_build_footprint.x) * 0.5) * TerrainData.CELL_SIZE
	var wz: float = (float(_ghost_cell.y) + float(_build_footprint.y) * 0.5) * TerrainData.CELL_SIZE
	var wy: float = GameState.terrain_data.get_height(wx, wz) if GameState.terrain_data != null else hit.position.y
	_ghost.position = Vector3(wx, wy + 0.8, wz)
	_ghost.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_hut"):
		_on_hut_button()
		get_viewport().set_input_as_handled()
		return
	if not is_active():
		return
	if event.is_action_pressed("rotate_building"):
		_orientation = (_orientation + 1) % 4
		_update_entrance_marker()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		_exit_build_mode()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if _ghost_valid:
				_tribe_commands.place_building(_tribe, _build_scene, _ghost_cell, _orientation)
				_exit_build_mode()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_exit_build_mode()
			get_viewport().set_input_as_handled()
