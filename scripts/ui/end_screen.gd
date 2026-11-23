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

## Line under "Sieg!". A mode with its own victory condition (survival) sets
## its own text before the match is decided.
var victory_subtitle: String = "Alle Feinde sind vernichtet."

## A decided match waiting for its overlay (see RESULT_DELAY).
var _result_pending: bool = false
var _pending_winner: int = -1
var _delay_left: float = 0.0

var _title: Label = null
var _subtitle: Label = null
## Statistics per tribe (2026-11-23): header row + one row per tribe.
var _stats_grid: GridContainer = null
var _time_label: Label = null

## Column headers of the statistics table (TribeStats.rows keys in that order).
const STAT_COLUMNS: Array[String] = ["Stamm", "Anhänger", "Höchststand", "Gefallen",
	"Kills Golems", "Kills sonst"]
const STAT_KEYS: Array[String] = ["name", "alive", "peak", "lost", "kills_golem", "kills_other"]


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
	# Grow from the centre in every direction: with the statistics table the box is
	# big, and the default (grow right/down) pushed it off the middle.
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
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

	_time_label = Label.new()
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.add_theme_color_override("font_color", UiTheme.GOLD)
	vb.add_child(_time_label)

	_stats_grid = GridContainer.new()
	_stats_grid.columns = STAT_COLUMNS.size()
	_stats_grid.add_theme_constant_override("h_separation", 18)
	_stats_grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(_stats_grid)

	var note: Label = Label.new()
	note.text = ("Anhänger: am Ende lebend · Höchststand: die meisten gleichzeitig · "
		+ "Gefallen: eigene Tote\nKills Golems: von Golems getötet · Kills sonst: Einheiten, "
		+ "Türme, Fahrzeuge, Zauber, Lava …")
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", UiTheme.GOLD)
	vb.add_child(note)

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
	_subtitle.text = victory_subtitle if won \
		else "Dein Stamm wurde ausgelöscht."
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		show_stats(gs.tribes, gs.PLAYER_TRIBE, gs.match_time)
	visible = true
	get_tree().paused = true


## Fills the statistics table (also used by the stand-alone render check).
func show_stats(tribes: Array[Tribe], player_id: int, match_time: float) -> void:
	_time_label.text = "Spielzeit %s" % TribeStats.format_time(match_time)
	for child in _stats_grid.get_children():
		_stats_grid.remove_child(child)
		child.queue_free()
	for title in STAT_COLUMNS:
		var head: Label = Label.new()
		head.text = title
		head.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
		_stats_grid.add_child(head)
	for row in TribeStats.rows(tribes, player_id):
		for key in STAT_KEYS:
			var cell: Label = Label.new()
			cell.text = str(row[key])
			if key == "name":
				cell.add_theme_color_override("font_color", row["color"] as Color)
				if bool(row["eliminated"]):
					cell.text += " †"
			else:
				cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_stats_grid.add_child(cell)


func _back_to_menu() -> void:
	get_tree().paused = false
	GameState.reset()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
