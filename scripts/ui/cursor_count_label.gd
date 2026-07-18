class_name CursorCountLabel extends Label

## Small counter following the mouse cursor with the number of currently
## selected units (hidden when nothing is selected). Polls the selection like
## the sidebar does — there is no selection-changed signal.

const OFFSET: Vector2 = Vector2(18.0, 14.0)

var _selection: SelectionManager = null


func setup(p_selection: SelectionManager) -> void:
	_selection = p_selection


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	add_theme_font_size_override("font_size", 15)
	add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.02))
	add_theme_constant_override("outline_size", 4)
	visible = false


func _process(_delta: float) -> void:
	if _selection == null:
		visible = false
		return
	var count: int = 0
	for u in _selection.selected:
		if is_instance_valid(u) and u.state != Unit.State.DEAD:
			count += 1
	visible = count > 0
	if visible:
		text = str(count)
		position = get_viewport().get_mouse_position() + OFFSET
