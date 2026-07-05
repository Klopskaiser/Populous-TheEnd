extends Node3D

## Root of the main scene. Creates the TerrainData (fixed seed), builds the
## Terrain, and positions the camera over the island. Must be headless-robust:
## no viewport-texture access in _ready().

## Debug: spawn a small marker at the terrain raycast hit on left-click, to
## verify the HeightMapShape3D offset (marker must sit exactly under the cursor).
@export var debug_click_marker: bool = true

@onready var _terrain: Terrain = $Terrain
@onready var _camera_rig: CameraRig = $CameraRig

var _marker: MeshInstance3D = null


func _ready() -> void:
	var td: TerrainData = TerrainData.new()
	td.generate_island(GameState.ISLAND_SEED)
	GameState.terrain_data = td
	GameState.terrain = _terrain

	_terrain.build(td)

	# Start the camera over the island centre.
	var center: float = TerrainData.SIZE * 0.5
	_camera_rig.global_position = Vector3(center, td.get_height(center, center), center)


func _unhandled_input(event: InputEvent) -> void:
	if not debug_click_marker:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_place_debug_marker(event.position)


func _place_debug_marker(screen_pos: Vector2) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var from: Vector3 = cam.project_ray_origin(screen_pos)
	var dir: Vector3 = cam.project_ray_normal(screen_pos)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from + dir * 1000.0)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return
	if _marker == null:
		_marker = MeshInstance3D.new()
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = 0.6
		sphere.height = 1.2
		_marker.mesh = sphere
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.1, 0.1)
		_marker.material_override = mat
		add_child(_marker)
	_marker.global_position = hit.position
