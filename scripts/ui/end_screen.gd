class_name EndScreen extends Control

## Full-screen "Sieg!"/"Niederlage" overlay (phase 7). Hidden until
## GameState.match_ended fires (Main connects show_result); pauses the game
## while visible. Same look as the pause menu (UiTheme).

const MAIN_MENU_SCENE_PATH: String = "res://scenes/ui/main_menu.tscn"

var _title: Label = null
var _subtitle: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	add_child(dim)

	var box: PanelContainer = PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiTheme.panel_style())
	box.set_anchors_preset(Control.PRESET_CENTER)
	add_child(box)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	box.add_child(vb)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 32)
	vb.add_child(_title)

	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
	vb.add_child(_subtitle)

	var menu: Button = Button.new()
	menu.text = "Zurück zum Menü"
	UiTheme.style_button(menu)
	menu.pressed.connect(_back_to_menu)
	vb.add_child(menu)

	var quit: Button = Button.new()
	quit.text = "Beenden"
	UiTheme.style_button(quit)
	quit.pressed.connect(func() -> void: get_tree().quit())
	vb.add_child(quit)


## Shows the result overlay and pauses the game. `winner_id` comes straight
## from GameState.match_ended.
func show_result(winner_id: int) -> void:
	var won: bool = winner_id == GameState.PLAYER_TRIBE
	_title.text = "Sieg!" if won else "Niederlage"
	_title.add_theme_color_override("font_color",
		UiTheme.GOLD_BRIGHT if won else Color(0.85, 0.25, 0.2))
	_subtitle.text = "Alle Feinde sind vernichtet." if won \
		else "Dein Stamm wurde ausgelöscht."
	visible = true
	get_tree().paused = true


func _back_to_menu() -> void:
	get_tree().paused = false
	GameState.reset()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
