class_name FpsOverlay extends Label

## In-game FPS counter (phase 8): frames per second plus the frame time in
## milliseconds and the renderer's draw calls / objects per frame (GPU-side
## diagnosis, e.g. before/after the shadow rework), top-right corner.
## Visibility follows GameSettings.show_fps() live, so the options toggle
## applies without restarting the match.

const UPDATE_INTERVAL: float = 0.25

var _timer: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -230.0
	offset_top = 8.0
	offset_right = -10.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_theme_color_override("font_color", Color(0.98, 0.85, 0.45))
	add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.03))
	add_theme_constant_override("outline_size", 4)
	visible = false


func _process(delta: float) -> void:
	var show: bool = GameSettings.show_fps()
	if visible != show:
		visible = show
	if not show:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = UPDATE_INTERVAL
	var fps: float = Engine.get_frames_per_second()
	var draw_calls: int = RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var objects: int = RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	text = "FPS: %d (%.1f ms)\nDraw-Calls: %d | Objekte: %d" % [
		int(fps), 1000.0 / maxf(fps, 1.0), draw_calls, objects]
