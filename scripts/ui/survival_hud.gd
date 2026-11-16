class_name SurvivalHud extends PanelContainer

## Wave display of the survival mode, top centre: "Welle 3/20" and below it the
## countdown to the next wave (after the last wave: how many enemies are left).
## Reads SurvivalMode a few times per second; the texts are pure static
## functions so they are testable without a scene.

const UPDATE_INTERVAL: float = 0.25
const TOP_MARGIN: float = 8.0
const MIN_WIDTH: float = 220.0
const TITLE_FONT_SIZE: int = 20

var _mode: SurvivalMode = null
var _title: Label = null
var _status: Label = null
var _timer: float = 0.0


# --- Texts (pure) ----------------------------------------------------------------

## "Welle 3/20" — the wave that appeared last; before the first one "Welle 0/20".
## `total` <= 0 = endless survival: just "Welle 23".
static func wave_text(wave: int, total: int) -> String:
	if total <= 0:
		return "Welle %d" % maxi(wave, 0)
	return "Welle %d/%d" % [clampi(wave, 0, total), total]


## Minutes:seconds, rounded UP so the display reaches 0:00 exactly when the
## wave appears.
static func format_time(seconds: float) -> String:
	var s: int = int(ceil(maxf(seconds, 0.0)))
	@warning_ignore("integer_division")
	return "%d:%02d" % [s / 60, s % 60]


## The line under the wave counter. `time_to_next` < 0 = the last wave is out.
static func status_text(wave: int, time_to_next: float, enemies: int) -> String:
	if time_to_next < 0.0:
		if enemies <= 0:
			return "Alle Wellen überstanden"
		return "Letzte Welle — noch %d Gegner" % enemies
	var label: String = "Erste Welle in" if wave <= 0 else "Nächste Welle in"
	return "%s %s" % [label, format_time(time_to_next)]


# --- Node --------------------------------------------------------------------------

func setup(mode: SurvivalMode) -> void:
	_mode = mode
	_refresh()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UiTheme.panel_style())
	custom_minimum_size = Vector2(MIN_WIDTH, 0)
	# Inside the tree set_anchors_preset() rewrites the offsets so the control
	# keeps its old position (0, 0) — all four are therefore set explicitly
	# afterwards: a zero-width rect at the top centre that grows to both sides.
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = 0.0
	offset_right = 0.0
	offset_top = TOP_MARGIN
	offset_bottom = TOP_MARGIN
	grow_horizontal = Control.GROW_DIRECTION_BOTH

	var vb: VBoxContainer = VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vb)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_title.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
	vb.add_child(_title)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", UiTheme.TEXT)
	vb.add_child(_status)
	_refresh()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = UPDATE_INTERVAL
	_refresh()


func _refresh() -> void:
	if _mode == null or _title == null:
		return
	_title.text = wave_text(_mode.wave, 0 if _mode.endless else SurvivalMode.WAVE_COUNT)
	_status.text = status_text(_mode.wave, _mode.time_to_next_wave(),
		_mode.enemies_alive())
