class_name CameraRig extends Node3D

## Free-rotating RTS camera. Node structure (built in main.tscn):
##   CameraRig (this, yaw)  ->  Pitch (Node3D)  ->  Camera3D (pulled back by boom)
##
## Controls: WASD pan (camera-relative), screen-edge scroll, Q/E yaw rotation,
## mouse-wheel zoom (boom distance clamped). The rig's Y follows the terrain
## height beneath it so the camera stays above the ground.

@export var pan_speed: float = 40.0
@export var edge_scroll_speed: float = 40.0
@export var edge_margin: int = 8            # px from screen edge that triggers scroll
@export var rotate_speed: float = 1.8       # radians/second
@export var zoom_step: float = 4.0
@export var min_boom: float = 8.0
@export var max_boom: float = 90.0
@export var pitch_degrees: float = -55.0
@export var height_offset: float = 0.0      # extra Y above terrain
@export var edge_scroll_enabled: bool = true

var _boom: float = 45.0

@onready var _pitch: Node3D = $Pitch
@onready var _camera: Camera3D = $Pitch/Camera3D


func _ready() -> void:
	_pitch.rotation_degrees.x = pitch_degrees
	_apply_boom()


func _process(delta: float) -> void:
	_handle_rotation(delta)
	_handle_pan(delta)
	_clamp_to_terrain()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_zoom_in"):
		_boom = clampf(_boom - zoom_step, min_boom, max_boom)
		_apply_boom()
	elif event.is_action_pressed("camera_zoom_out"):
		_boom = clampf(_boom + zoom_step, min_boom, max_boom)
		_apply_boom()


func _apply_boom() -> void:
	# Camera sits behind the pitch pivot along its local +Z, then looks forward.
	_camera.position = Vector3(0.0, 0.0, _boom)


func _handle_rotation(delta: float) -> void:
	var dir: float = 0.0
	if Input.is_action_pressed("camera_rotate_left"):
		dir += 1.0
	if Input.is_action_pressed("camera_rotate_right"):
		dir -= 1.0
	if dir != 0.0:
		rotation.y += dir * rotate_speed * delta


func _handle_pan(delta: float) -> void:
	var input: Vector2 = Vector2.ZERO  # x = right, y = forward
	if Input.is_action_pressed("camera_forward"):
		input.y += 1.0
	if Input.is_action_pressed("camera_back"):
		input.y -= 1.0
	if Input.is_action_pressed("camera_right"):
		input.x += 1.0
	# Key A doubles as the attack-move arm hotkey (with units selected); the
	# camera must not pan left while that mode is armed.
	if Input.is_action_pressed("camera_left") and not SelectionManager.attack_arm_active:
		input.x -= 1.0

	input += _edge_scroll_vector()

	if input == Vector2.ZERO:
		return
	input = input.limit_length(1.0)
	# Camera-relative on the XZ plane (yaw only).
	var forward: Vector3 = -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right: Vector3 = global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var motion: Vector3 = (right * input.x + forward * input.y) * pan_speed * delta
	global_position += motion
	# Keep the rig within the terrain bounds.
	global_position.x = clampf(global_position.x, 0.0, float(TerrainData.SIZE))
	global_position.z = clampf(global_position.z, 0.0, float(TerrainData.SIZE))


func _edge_scroll_vector() -> Vector2:
	if not edge_scroll_enabled:
		return Vector2.ZERO
	# While a selection box is being dragged, the camera must hold still —
	# panning shifts the screen-space box off the units mid-drag.
	if SelectionManager.drag_active:
		return Vector2.ZERO
	# No window in headless mode -> skip.
	if DisplayServer.get_name() == "headless":
		return Vector2.ZERO
	var vp: Viewport = get_viewport()
	if vp == null:
		return Vector2.ZERO
	var mouse: Vector2 = vp.get_mouse_position()
	var size: Vector2 = vp.get_visible_rect().size
	# Ignore if the cursor is outside the window.
	if mouse.x < 0 or mouse.y < 0 or mouse.x > size.x or mouse.y > size.y:
		return Vector2.ZERO
	var v: Vector2 = Vector2.ZERO
	if mouse.x < edge_margin:
		v.x -= 1.0
	elif mouse.x > size.x - edge_margin:
		v.x += 1.0
	if mouse.y < edge_margin:
		v.y += 1.0
	elif mouse.y > size.y - edge_margin:
		v.y -= 1.0
	# Scale edge scroll relative to pan (applied via pan_speed later).
	return v * (edge_scroll_speed / maxf(pan_speed, 0.001))


func _clamp_to_terrain() -> void:
	var td: TerrainData = GameState.terrain_data
	if td == null:
		return
	var ground: float = td.get_height(global_position.x, global_position.z)
	global_position.y = maxf(ground, TerrainData.SEA_LEVEL) + height_offset
