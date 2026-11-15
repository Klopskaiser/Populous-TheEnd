class_name EndScreen extends Control

## Full-screen "Sieg!"/"Niederlage" overlay (phase 7). Hidden until
## GameState.match_ended fires (Main connects show_result); pauses the game
## while visible. Same look as the pause menu (UiTheme).

const MAIN_MENU_SCENE_PATH: String = "res://scenes/ui/main_menu.tscn"
## Seconds between the decision and the overlay. The loser's last buildings —
## above all the reincarnation circle — are razed in the very tick the match is
## decided (Tribe.eliminate); pausing at once froze them upright before they
## could sink (user report 2026-11-15: red beaten, but its circle and a building
## site still stood). The game runs on for this long, then the overlay pauses it.
const RESULT_DELAY: float = Building.SINK_DURATION + 0.5

## A decided match waiting for its overlay (see RESULT_DELAY).
var _result_pending: bool = false
var _pending_winner: int = -1
var _delay_left: float = 0.0

var _title: Label = null
var _subtitle: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(false)
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


## The match is decided: the overlay follows RESULT_DELAY seconds later (the
## wrecks sink first). `winner_id` comes straight from GameState.match_ended.
func show_result(winner_id: int) -> void:
	if visible or _result_pending:
		return
	_result_pending = true
	_pending_winner = winner_id
	_delay_left = RESULT_DELAY
	set_process(true)


## Counts the delay down in GAME time: this node runs while paused (the overlay
## must stay clickable), so an open pause menu must not eat the delay.
func _process(delta: float) -> void:
	if not _result_pending:
		set_process(false)
		return
	if is_inside_tree() and get_tree().paused:
		return
	_delay_left -= delta
	if _delay_left <= 0.0:
		_result_pending = false
		set_process(false)
		present_result(_pending_winner)


## Shows the result overlay and pauses the game.
func present_result(winner_id: int) -> void:
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
