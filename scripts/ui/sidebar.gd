class_name Sidebar extends Control

## The complete, permanent UI shell in the style of Populous: The Beginning —
## a gold/brown panel down the left edge (fixed width, full height). Top to
## bottom: round minimap, shaman portrait, tab bar (buildings / spells /
## followers / crew), header (per-tribe population bars, population count,
## segmented mana bar, wood readout, growth slider), the active tab's content,
## and a menu panel with a pause button. All optics are procedural (see
## UiTheme); the layout is built in code in _ready() and wired via setup().
##
## The CREW tab shows the occupants of the single selected mannable object
## (hut / forester / workshop / watchtower / catapult) as icon buttons (click
## ejects) plus a production pause toggle; it auto-activates on selection and
## is greyed out otherwise. Displays are signal-driven (Events.*_changed); the
## follower counters and minimap overlay are throttled. SelectionManager and
## BuildMenu ignore mouse events over the panel via is_mouse_over_ui().

const PANEL_WIDTH: float = 260.0
const MINIMAP_SIZE: float = 236.0
## Min height of the tab content area. Kept low so the whole sidebar column fits
## into a 1080p (windowed) client area — with the tall fixed elements above
## (minimap, portrait, header) a large floor here pushes the lower rows and the
## menu button off-screen. Every tab is a ScrollContainer, so a small floor only
## means more scrolling on tiny windows; the area still expands (SIZE_EXPAND_FILL)
## to the full remaining height on taller windows.
const TAB_CONTENT_HEIGHT: float = 160.0
## Index of the auto-activating crew tab.
const TAB_CREW: int = 3
const MANA_SEGMENTS: int = 20
## Mana value that fills the whole segmented bar (display only).
## Full mana bar at this INCOME (mana/s) — with MANA_BASE_RATE 0.1 that is a
## population of 300. There is no stored mana to show any more (phase 10c).
const MANA_RATE_DISPLAY_CAP: float = 30.0
const FOLLOWER_INTERVAL: float = 0.3
## "Holz" counts wood in piles within this radius of any of the player's own
## buildings (delivered/stacked wood at the base), not the whole map.
const WOOD_NEAR_RADIUS: float = 12.0

## Follower rows: kind key -> German label.
const FOLLOWER_ROWS: Array[Dictionary] = [
	{"kind": &"brave", "name": "Gefolgsleute", "active": true},
	{"kind": &"warrior", "name": "Krieger", "active": true},
	{"kind": &"firewarrior", "name": "Feuerkrieger", "active": true},
	{"kind": &"preacher", "name": "Prediger", "active": true},
	{"kind": &"siege", "name": "Belagerungswaffe", "active": true},
	{"kind": &"fireram", "name": "Feuerrammen", "active": true},
	{"kind": &"airship", "name": "Luftschiffe", "active": true},
	{"kind": &"shaman", "name": "Schamanin", "active": true},
]

const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const WARRIOR_CAMP_SCENE: PackedScene = preload("res://scenes/buildings/warrior_camp.tscn")
const FIREWARRIOR_CAMP_SCENE: PackedScene = preload("res://scenes/buildings/firewarrior_camp.tscn")
const TEMPLE_SCENE: PackedScene = preload("res://scenes/buildings/temple.tscn")
const FORESTER_SCENE: PackedScene = preload("res://scenes/buildings/forester.tscn")
const WORKSHOP_SCENE: PackedScene = preload("res://scenes/buildings/workshop.tscn")
const FIRERAM_WORKSHOP_SCENE: PackedScene = preload("res://scenes/buildings/fire_ram_workshop.tscn")
const AIRSHIP_WHARF_SCENE: PackedScene = preload("res://scenes/buildings/airship_wharf.tscn")
const WATCHTOWER_SCENE: PackedScene = preload("res://scenes/buildings/watchtower.tscn")
const WOOD_DEPOT_SCENE: PackedScene = preload("res://scenes/buildings/wood_depot.tscn")

# --- Injected references (setup) --------------------------------------------
var _tribes: Array[Tribe] = []
var _player_id: int = 0
var _unit_manager: UnitManager = null
var _building_manager: BuildingManager = null
var _tree_manager: TreeManager = null
var _wood_pile_manager: WoodPileManager = null
var _tribe_commands: TribeCommands = null
var _build_menu: BuildMenu = null
var _selection: SelectionManager = null
var _spell_targeting: SpellTargeting = null
var _camera_rig: Node3D = null

# --- Widgets ----------------------------------------------------------------
var _panel: PanelContainer = null
var _minimap: Minimap = null
var _pop_label: Label = null
var _wood_label: Label = null
var _tribe_bars: Array[ProgressBar] = []
var _mana_segments: Array[ColorRect] = []
var _mana_label: Label = null   # numeric mana + income per second (phase 7i)
var _growth_slider: HSlider = null   # hut growth control (phase 7i)
var _growth_label: Label = null
## Tribe-wide hut-upgrade lock (phase 10f), header row under the growth control.
var _upgrades_check: CheckButton = null
var _tab_buttons: Array[Button] = []
var _tab_panels: Array[Control] = []
var _tab_content: Control = null
var _spell_ui: Dictionary = {}       # id -> {"button": Button, "pips": Array[ColorRect]}
var _follower_labels: Dictionary = {}  # kind -> Label
var _idle_button: Button = null
## Per-tribe vehicle-cap steppers (followers tab): one entry per vehicle type
## with {label, title, get_cap, set_cap, get_owned, limit}.
var _cap_steppers: Array[Dictionary] = []
## Per-tribe toggle (followers tab): military units auto-crew nearby ground vehicles.
var _auto_recrew_check: CheckButton = null
var _pause_menu: Control = null
## Crew tab widgets: occupants of the selected mannable object as icon buttons
## (click ejects) plus a production pause toggle.
var _crew_title: Label = null
var _crew_info: Label = null
var _crew_slot_buttons: Array[Button] = []
var _crew_pause_button: Button = null
var _crew_unload_button: Button = null   # airship "Absetzen an…" (unload arm)
## Edge detection for the crew tab's auto-switch: last polled target, the tab
## to return to on deselection, and the currently active tab index.
var _crew_target_obj: Object = null
var _crew_return_tab: int = 0
var _active_tab: int = 0
## Shaman portrait (below the minimap, Populous style): full live-animated
## figure + health bar; click centres the camera on her and selects ONLY her.
var _portrait_sprite: AnimatedSprite2D = null
var _portrait_hp: ProgressBar = null
var _portrait_status: Label = null

var _follower_timer: float = 0.0

## Single instance for the static mouse guard.
static var _instance: Sidebar = null


# --- Static, headless-testable helpers ---------------------------------------

## Whether the pointer is currently over the sidebar panel (used by
## SelectionManager/BuildMenu to ignore clicks that start over the UI).
static func is_mouse_over_ui() -> bool:
	if _instance == null or not is_instance_valid(_instance) or not _instance.visible:
		return false
	var panel: PanelContainer = _instance._panel
	if panel == null:
		return false
	return panel.get_global_rect().has_point(panel.get_global_mouse_position())


## Filled segment count of the mana bar from a mana value, capped at `segments`.
static func mana_segments(mana: float, cap: float, segments: int) -> int:
	if cap <= 0.0 or segments <= 0:
		return 0
	return clampi(int(floor(mana / cap * float(segments))), 0, segments)


# --- Charge gauge: rate sweep + ETA (phase 10k) --------------------------------
## Sweep period bounds (seconds for one gold pass) and the log mapping constants.
const CHARGE_SWEEP_MIN: float = 0.3
const CHARGE_SWEEP_MAX: float = 2.5
const CHARGE_SWEEP_SLOPE: float = 0.35
const CHARGE_SWEEP_BASE: float = 0.3
## The remaining time is spelled out from here on — below that the bar says it.
const CHARGE_ETA_MIN_SECONDS: float = 30.0


## Period (seconds) of one gold sweep, derived from the seconds left until the
## next charge. LOGARITHMIC on purpose: with the 10k costs the remaining times
## span three orders of magnitude (~1 s for a lone fireball, ~900 s for a volcano
## on a full bar). A linear mapping would make every slow spell look identical,
## which is exactly the information the sweep is supposed to carry.
##
## Pure and static — exhaustively testable headless (pattern: pip_state).
static func sweep_period(remaining_s: float) -> float:
	if not is_finite(remaining_s):
		return CHARGE_SWEEP_MAX   # nothing charging — the bar is frozen anyway
	if remaining_s <= 0.0:
		return CHARGE_SWEEP_MIN   # about to pop: the fastest sweep, not the slowest
	var mapped: float = CHARGE_SWEEP_SLOPE * (log(remaining_s + 1.0) / log(10.0)) \
		+ CHARGE_SWEEP_BASE
	return clampf(mapped, CHARGE_SWEEP_MIN, CHARGE_SWEEP_MAX)


## Remaining time as shown in the cell: "" below the threshold (the bar speaks),
## seconds up to a minute, m:ss above. INF (nothing charging) also yields "".
static func charge_eta_text(remaining_s: float) -> String:
	if not is_finite(remaining_s) or remaining_s < CHARGE_ETA_MIN_SECONDS:
		return ""
	if remaining_s < 60.0:
		return "%ds" % int(round(remaining_s))
	var total: int = int(round(remaining_s))
	return "%d:%02d" % [total / 60, total % 60]


## Charge-pip display state: how many pips are full, how many empty, and the
## fill fraction of the next (partial) pip. When all charges are full the
## progress is 0 (nothing is charging).
static func pip_state(charges: int, max_charges: int, charge_progress: float) -> Dictionary:
	var full: int = clampi(charges, 0, max_charges)
	var empty: int = max_charges - full
	var progress: float = 0.0 if full >= max_charges else clampf(charge_progress, 0.0, 1.0)
	return {"filled": full, "empty": empty, "progress": progress}


## Bar length fractions (0..1) proportional to each tribe's population,
## normalised to the largest tribe. All-zero populations yield all zeros
## (no division by zero).
static func tribe_bar_fractions(populations: Array[int]) -> Array[float]:
	var result: Array[float] = []
	var top: int = 0
	for p in populations:
		top = maxi(top, p)
	for p in populations:
		result.append(0.0 if top <= 0 else float(p) / float(top))
	return result


## Registry for the building tab. Disabled entries have no scene (so they yield
## no start_placement target); the hut entry references the Hut scene and cost.
static func default_build_entries() -> Array[Dictionary]:
	return [
		{"id": &"hut", "name": "Hütte", "scene": HUT_SCENE, "icon": &"hut",
			"wood_cost": Hut.WOOD_COST, "enabled": true, "hotkey": "H"},
		{"id": &"warrior_camp", "name": "Kaserne", "scene": WARRIOR_CAMP_SCENE,
			"icon": &"warrior_camp", "wood_cost": WarriorCamp.WOOD_COST, "enabled": true},
		{"id": &"firewarrior_camp", "name": "Feuertempel", "scene": FIREWARRIOR_CAMP_SCENE,
			"icon": &"firewarrior_camp", "wood_cost": FirewarriorCamp.WOOD_COST, "enabled": true},
		{"id": &"temple", "name": "Tempel", "scene": TEMPLE_SCENE,
			"icon": &"temple", "wood_cost": Temple.WOOD_COST, "enabled": true},
		{"id": &"forester", "name": "Försterei", "scene": FORESTER_SCENE,
			"icon": &"forester", "wood_cost": Forester.WOOD_COST, "enabled": true},
		{"id": &"workshop", "name": "Katapultwerkstatt", "scene": WORKSHOP_SCENE,
			"icon": &"workshop", "wood_cost": Workshop.WOOD_COST, "enabled": true},
		{"id": &"fireram_workshop", "name": "Feuerrammenwerkstatt",
			"scene": FIRERAM_WORKSHOP_SCENE, "icon": &"fireram_workshop",
			"wood_cost": FireRamWorkshop.RAM_WOOD_COST, "enabled": true},
		{"id": &"airship_wharf", "name": "Luftschiffwerft", "scene": AIRSHIP_WHARF_SCENE,
			"icon": &"airship_wharf", "wood_cost": AirshipWharf.WHARF_WOOD_COST,
			"enabled": true},
		{"id": &"watchtower", "name": "Wachturm", "scene": WATCHTOWER_SCENE,
			"icon": &"watchtower", "wood_cost": Watchtower.WOOD_COST, "enabled": true},
		{"id": &"wood_depot", "name": "Holzstation", "scene": WOOD_DEPOT_SCENE,
			"icon": &"wood_depot", "wood_cost": WoodDepot.WOOD_COST, "enabled": true},
	]


## Order matches SpellTargeting.HOTKEY_SPELLS (hotkeys 1-9 and 0 for slot 10).
static func default_spell_entries() -> Array[Dictionary]:
	return [
		{"id": &"fireball", "name": "Feuerball", "icon": &"fireball",
			"max_charges": 4, "hotkey": "1"},
		{"id": &"lightning", "name": "Blitz", "icon": &"lightning",
			"max_charges": 4, "hotkey": "2"},
		{"id": &"swarm", "name": "Insektenschwarm", "icon": &"swarm",
			"max_charges": 4, "hotkey": "3"},
		{"id": &"landbridge", "name": "Landbrücke", "icon": &"landbridge",
			"max_charges": 4, "hotkey": "4"},
		{"id": &"tornado", "name": "Tornado", "icon": &"tornado",
			"max_charges": 3, "hotkey": "5"},
		{"id": &"earthquake", "name": "Erdbeben", "icon": &"earthquake",
			"max_charges": 2, "hotkey": "6"},
		{"id": &"volcano", "name": "Vulkan", "icon": &"volcano",
			"max_charges": 1, "hotkey": "7"},
		{"id": &"firestorm", "name": "Feuerregen", "icon": &"firestorm",
			"max_charges": 2, "hotkey": "8"},
		{"id": &"flatten", "name": "Ebene", "icon": &"flatten",
			"max_charges": 3, "hotkey": "9"},
		{"id": &"sink", "name": "Absinken", "icon": &"sink",
			"max_charges": 3, "hotkey": "0"},
		{"id": &"supertornado", "name": "Supertornado", "icon": &"supertornado",
			"max_charges": 1, "hotkey": "ß"},
		{"id": &"hypnosis", "name": "Hypnose", "icon": &"hypnosis",
			"max_charges": Balance.SPELL_HYPNOSIS_MAX_CHARGES, "hotkey": "´"},
	]


# --- Lifecycle --------------------------------------------------------------

func _ready() -> void:
	_instance = self
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Runs while the tree is paused so Esc/Fortsetzen can unpause the game.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_build_pause_menu()
	var events: Node = get_node_or_null("/root/Events")
	if events != null:
		events.population_changed.connect(_on_population_changed)
		events.mana_changed.connect(_on_mana_changed)
		events.stockpile_changed.connect(_on_stockpile_changed)
		events.spell_charges_changed.connect(_on_spell_charges_changed)


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


## Wires the sidebar to the game and does the initial refresh. Called by Main
## after all managers exist.
func setup(p_tribes: Array[Tribe], p_player_id: int, p_unit_manager: UnitManager,
		p_building_manager: BuildingManager, p_tree_manager: TreeManager,
		p_wood_pile_manager: WoodPileManager, p_tribe_commands: TribeCommands,
		p_build_menu: BuildMenu, p_selection: SelectionManager,
		p_camera_rig: Node3D, p_terrain_data: TerrainData,
		p_spell_targeting: SpellTargeting = null) -> void:
	_tribes = p_tribes
	_player_id = p_player_id
	_unit_manager = p_unit_manager
	_building_manager = p_building_manager
	_tree_manager = p_tree_manager
	_wood_pile_manager = p_wood_pile_manager
	_tribe_commands = p_tribe_commands
	_build_menu = p_build_menu
	_selection = p_selection
	_spell_targeting = p_spell_targeting
	_camera_rig = p_camera_rig

	_minimap.setup(p_terrain_data, p_unit_manager, p_building_manager,
		p_tree_manager, p_camera_rig, MapGenerator.round_mask(GameState.map_id))
	_refresh_tribe_bars()
	var player: Tribe = _tribes[_player_id] if _player_id < _tribes.size() else null
	if player != null:
		_set_population(player.population(), player.housing_capacity())
		_set_mana(player.mana)
		if _growth_slider != null:
			_growth_slider.set_value_no_signal(float(int(player.growth_mode)))
		if _upgrades_check != null:
			_upgrades_check.set_pressed_no_signal(player.upgrades_allowed)
	_update_growth_label()
	_refresh_wood_near_base()
	_refresh_spells()
	_refresh_portrait()


func _process(delta: float) -> void:
	_refresh_crew_tab()   # responsive to selection changes (cheap: a few widgets)
	_advance_charge_sweeps(delta)   # every frame: the sweep must look continuous
	_follower_timer -= delta
	if _follower_timer <= 0.0:
		_follower_timer = FOLLOWER_INTERVAL
		_refresh_followers()
		_refresh_wood_near_base()
		_refresh_spells()
		_refresh_portrait()
		_update_growth_label()


## Advances the gold rate bars. Runs EVERY frame (not on the throttled refresh)
## so the sweep is smooth; a spell that is full or switched off keeps its phase,
## which reads as "paused" instead of "empty".
func _advance_charge_sweeps(delta: float) -> void:
	for id in _spell_ui:
		var ui: Dictionary = _spell_ui[id]
		var rate: ColorRect = ui.get("rate") as ColorRect
		if rate == null:
			continue
		if not bool(ui.get("sweeping", false)):
			continue
		var period: float = maxf(float(ui.get("period", CHARGE_SWEEP_MAX)), 0.01)
		var phase: float = fposmod(float(ui.get("phase", 0.0)) + delta / period, 1.0)
		ui["phase"] = phase
		rate.anchor_right = phase
		rate.offset_right = 0.0


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.anchor_left = 0.0
	_panel.anchor_right = 0.0
	_panel.offset_right = PANEL_WIDTH
	_panel.add_theme_stylebox_override("panel", UiTheme.panel_style())
	add_child(_panel)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	_panel.add_child(root)

	_build_minimap(root)
	_build_shaman_portrait(root)
	_build_tab_bar(root)
	_build_header(root)
	_build_tab_content(root)
	_build_menu_panel(root)
	_select_tab(0)


func _build_minimap(root: Control) -> void:
	_minimap = Minimap.new()
	_minimap.name = "Minimap"
	_minimap.custom_minimum_size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	var wrap: CenterContainer = CenterContainer.new()
	wrap.add_child(_minimap)
	root.add_child(wrap)


## Populous-style shaman portrait below the minimap: the whole figure with her
## CURRENT animation (front view, tribe-coloured) over a health bar. While she
## is dead it shows the corpse pose and the respawn countdown. Clicking it
## centres the camera on her and selects ONLY her.
func _build_shaman_portrait(root: Control) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "ShamanPortrait"
	panel.add_theme_stylebox_override("panel", UiTheme.inset_style())
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.tooltip_text = "Schamanin: Klick zentriert die Kamera und wählt nur sie aus"
	panel.gui_input.connect(_on_portrait_gui_input)
	root.add_child(panel)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE   # clicks land on the panel
	panel.add_child(vb)

	# Stage for the animated figure (AnimatedSprite2D is a Node2D, so it lives
	# inside a plain Control and is re-centred whenever the stage resizes).
	# 72 px = exactly the sprite height (24 px x scale 3): no dead space below.
	var stage: Control = Control.new()
	stage.custom_minimum_size = Vector2(0, 72)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(stage)
	_portrait_sprite = AnimatedSprite2D.new()
	_portrait_sprite.sprite_frames = PlaceholderSprites.make_frames(&"shaman")
	_portrait_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait_sprite.scale = Vector2(3.0, 3.0)
	_portrait_sprite.animation = &"idle_front"
	_portrait_sprite.play()
	stage.add_child(_portrait_sprite)
	stage.resized.connect(func() -> void:
		_portrait_sprite.position = stage.size * 0.5)

	_portrait_hp = ProgressBar.new()
	_portrait_hp.show_percentage = false
	_portrait_hp.custom_minimum_size = Vector2(0, 8)
	_portrait_hp.max_value = 1.0
	_portrait_hp.value = 1.0
	_portrait_hp.add_theme_stylebox_override("background", UiTheme.inset_style())
	var hp_fill: StyleBoxFlat = StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.35, 0.8, 0.3)
	hp_fill.set_corner_radius_all(2)
	_portrait_hp.add_theme_stylebox_override("fill", hp_fill)
	vb.add_child(_portrait_hp)

	# Hidden while empty (alive shaman) so it does not reserve a blank row
	# below the health bar; _refresh_portrait toggles it.
	_portrait_status = Label.new()
	_portrait_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait_status.add_theme_color_override("font_color", UiTheme.TEXT)
	_portrait_status.text = ""
	_portrait_status.visible = false
	vb.add_child(_portrait_status)


func _build_tab_bar(root: Control) -> void:
	var bar: HBoxContainer = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	root.add_child(bar)
	var defs: Array = [
		{"icon": &"house", "tip": "Gebäude"},
		{"icon": &"star", "tip": "Zauber"},
		{"icon": &"people", "tip": "Gefolgsleute"},
		{"icon": &"crew", "tip": "Besatzung"},
	]
	for i in range(defs.size()):
		var b: Button = Button.new()
		b.toggle_mode = true
		b.icon = UiTheme.icon(defs[i]["icon"])
		b.tooltip_text = defs[i]["tip"]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiTheme.style_button(b)
		var idx: int = i
		b.pressed.connect(func() -> void: _select_tab(idx))
		bar.add_child(b)
		_tab_buttons.append(b)


func _build_header(root: Control) -> void:
	var header: PanelContainer = PanelContainer.new()
	header.add_theme_stylebox_override("panel", UiTheme.inset_style())
	root.add_child(header)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	header.add_child(vb)

	# Per-tribe population bars.
	var bars: VBoxContainer = VBoxContainer.new()
	bars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bars.add_theme_constant_override("separation", 2)
	vb.add_child(bars)
	for i in range(Unit.TRIBE_COLORS.size()):
		var pb: ProgressBar = _make_tribe_bar(Unit.TRIBE_COLORS[i])
		bars.add_child(pb)
		_tribe_bars.append(pb)

	_pop_label = Label.new()
	_pop_label.add_theme_color_override("font_color", UiTheme.TEXT)
	_pop_label.text = "Bevölkerung: 0/0"
	vb.add_child(_pop_label)

	_wood_label = Label.new()
	_wood_label.add_theme_color_override("font_color", UiTheme.TEXT)
	_wood_label.text = "Holz: 0"
	vb.add_child(_wood_label)

	# Segmented mana bar.
	var mana_row: HBoxContainer = HBoxContainer.new()
	mana_row.add_theme_constant_override("separation", 2)
	vb.add_child(mana_row)
	for i in range(MANA_SEGMENTS):
		var seg: ColorRect = ColorRect.new()
		seg.custom_minimum_size = Vector2(0, 10)
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.color = _mana_empty_color()
		mana_row.add_child(seg)
		_mana_segments.append(seg)

	# Numeric mana readout + income per second (phase 7i).
	_mana_label = Label.new()
	_mana_label.add_theme_color_override("font_color", UiTheme.TEXT)
	_mana_label.text = "Mana: 0  (+0.0/s)"
	vb.add_child(_mana_label)

	# Growth control (phase 7i): 0 = Kein, 1 = Minimal, 2 = Maximum hut manning.
	var growth_row: HBoxContainer = HBoxContainer.new()
	growth_row.add_theme_constant_override("separation", 6)
	vb.add_child(growth_row)
	var gl: Label = Label.new()
	gl.text = "Wachstum"
	gl.add_theme_color_override("font_color", UiTheme.TEXT)
	growth_row.add_child(gl)
	_growth_slider = HSlider.new()
	_growth_slider.min_value = 0.0
	_growth_slider.max_value = 2.0
	_growth_slider.step = 1.0
	_growth_slider.custom_minimum_size = Vector2(90, 16)
	_growth_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_growth_slider.value_changed.connect(_on_growth_changed)
	growth_row.add_child(_growth_slider)
	_growth_label = Label.new()
	_growth_label.add_theme_color_override("font_color", UiTheme.GOLD)
	_growth_label.text = "Maximum  (+0/min)"
	vb.add_child(_growth_label)

	# Tribe-wide hut-upgrade lock (phase 10f), right below the growth control it
	# belongs with. The long label must NOT dictate the panel width — wrap and clip
	# it, or its minimum width pushes the whole header past the panel edge (same
	# lesson as the auto-recrew toggle in the followers tab).
	_upgrades_check = CheckButton.new()
	_upgrades_check.text = "Ausbau erlauben"
	_upgrades_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrades_check.clip_text = true
	_upgrades_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_upgrades_check.tooltip_text = "Hütten bauen sich selbst in vier Stufen zum" \
		+ " Wohnpalast aus (je 5 Holz). Aus: fällige Ausbauten warten, die" \
		+ " Besatzung bleibt in der Hütte und produziert weiter. Gilt für den" \
		+ " ganzen Stamm; eine einzelne Hütte lässt sich über ihren Pause-Knopf" \
		+ " sperren."
	UiTheme.style_button(_upgrades_check)
	_upgrades_check.set_pressed_no_signal(true)
	_upgrades_check.toggled.connect(_on_upgrades_toggled)
	vb.add_child(_upgrades_check)


func _make_tribe_bar(color: Color) -> ProgressBar:
	var pb: ProgressBar = ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 8)
	pb.max_value = 1.0
	pb.value = 0.0
	pb.add_theme_stylebox_override("background", UiTheme.inset_style())
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)
	pb.add_theme_stylebox_override("fill", fill)
	return pb


func _build_tab_content(root: Control) -> void:
	var content: Control = Control.new()
	# Takes all remaining panel height (min height for short windows); every tab
	# also scrolls as a safety net.
	content.custom_minimum_size = Vector2(0, TAB_CONTENT_HEIGHT)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.clip_contents = true
	root.add_child(content)
	_tab_content = content
	_tab_panels.append(_build_building_tab())
	_tab_panels.append(_build_spell_tab())
	_tab_panels.append(_build_followers_tab())
	_tab_panels.append(_build_crew_tab())
	for p in _tab_panels:
		p.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.add_child(p)


func _build_building_tab() -> Control:
	# Icon grid like the spell tab: two cells per row, wood cost below the icon,
	# name/hotkey in the tooltip.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 6)
	for entry in default_build_entries():
		grid.add_child(_make_build_cell(entry))
	scroll.add_child(grid)
	return scroll


func _make_build_cell(entry: Dictionary) -> Control:
	var cell: VBoxContainer = VBoxContainer.new()
	cell.add_theme_constant_override("separation", 2)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var b: Button = Button.new()
	b.icon = UiTheme.icon(entry["icon"])
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tip: String = entry["name"]
	if entry.has("hotkey"):
		tip += "  [%s]" % entry["hotkey"]
	b.tooltip_text = tip if entry["enabled"] else "%s — ab Phase 5" % entry["name"]
	b.disabled = not entry["enabled"]
	UiTheme.style_button(b)
	if entry["enabled"]:
		var scene: PackedScene = entry["scene"]
		b.pressed.connect(func() -> void: _on_build_pressed(scene))
	cell.add_child(b)

	var cost: Label = Label.new()
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.add_theme_color_override("font_color",
		UiTheme.TEXT if entry["enabled"] else UiTheme.TEXT_DIM)
	cost.text = "%d Holz" % int(entry["wood_cost"])
	cell.add_child(cost)
	return cell


func _build_spell_tab() -> Control:
	# Scrolls like the building tab so all rows stay reachable when the tab
	# content area is compact (short windows / 1080p).
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 6)
	for entry in default_spell_entries():
		grid.add_child(_make_spell_cell(entry))
	scroll.add_child(grid)
	return scroll


func _make_spell_cell(entry: Dictionary) -> Control:
	var cell: VBoxContainer = VBoxContainer.new()
	cell.add_theme_constant_override("separation", 2)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var pip_row: HBoxContainer = HBoxContainer.new()
	pip_row.add_theme_constant_override("separation", 2)
	pip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	# Decoration only: the pips must not swallow the cell's right-click
	# (MOUSE_FILTER_STOP is the default and blocks the bubbling, see below).
	pip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pips: Array[ColorRect] = []
	for i in range(int(entry["max_charges"])):
		var pip: ColorRect = ColorRect.new()
		pip.custom_minimum_size = Vector2(6, 5)
		pip.color = _pip_empty_color()
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip_row.add_child(pip)
		pips.append(pip)
	cell.add_child(pip_row)

	var b: Button = Button.new()
	b.icon = UiTheme.icon(entry["icon"])
	b.tooltip_text = "%s  [%s]\nRechtsklick: Aufladen an/aus" \
		% [entry["name"], entry.get("hotkey", "")]
	b.disabled = true   # enabled by set_spell_state once a charge is stored
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# PASS, not the default STOP: a Control with STOP ends the gui_input
	# bubbling even for events it does not handle at all. The button ignores
	# right-clicks (and a disabled one ignores everything), so with STOP the
	# cell below never saw the toggle click — the first version of this simply
	# did nothing (user report). PASS keeps the left-click working and lets the
	# right-click travel on to the cell.
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	UiTheme.style_button(b)
	var spell_id: StringName = entry["id"]
	b.pressed.connect(func() -> void: _on_spell_pressed(spell_id))
	cell.add_child(b)

	# Charge bar (phase 10c): the fill toward the NEXT charge. Every active
	# spell charges at once now, so each one needs its own progress — a single
	# shared pip could no longer show it.
	var bar_bg: ColorRect = ColorRect.new()
	bar_bg.custom_minimum_size = Vector2(0, 3)
	bar_bg.color = _pip_empty_color()
	bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE   # decoration only
	# Two bars like the original game (phase 10k): a GOLD rate bar that sweeps
	# 0->1 over and over, and the BLUE real progress on top of it. Since later
	# children draw over earlier ones, the blue fill covers the gold on its own
	# length — so the sweep is only visible in the still-open part of the gauge,
	# exactly the original's look, with no arithmetic. The sweep SPEED carries the
	# charging rate: with 10k costs a single bar can sit still for minutes.
	var bar_rate: ColorRect = _make_bar_layer(UiTheme.GOLD)
	bar_bg.add_child(bar_rate)
	var bar_fill: ColorRect = _make_bar_layer(UiTheme.CHARGE_BLUE)
	bar_bg.add_child(bar_fill)
	cell.add_child(bar_bg)

	# Remaining time for the next charge, shown only when waiting is a decision
	# (see CHARGE_ETA_MIN_SECONDS). Overlays the cell's bottom-right corner.
	var eta: Label = Label.new()
	eta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eta.add_theme_font_size_override("font_size", 9)
	eta.add_theme_color_override("font_color", UiTheme.TEXT)
	eta.add_theme_color_override("font_outline_color", UiTheme.BROWN_DARK)
	eta.add_theme_constant_override("outline_size", 3)
	eta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	eta.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	eta.offset_top = -13.0
	eta.offset_bottom = -3.0
	eta.offset_right = -3.0
	eta.visible = false
	b.add_child(eta)

	# Right-click anywhere on the cell toggles the spell's charging. The handler
	# sits on the CELL (the button and the decorations pass their events on, see
	# their mouse_filter above), so the whole tile is a valid target.
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.gui_input.connect(func(event: InputEvent) -> void:
		_on_spell_cell_input(event, spell_id))

	_spell_ui[entry["id"]] = {"button": b, "pips": pips, "bar": bar_fill,
		"cell": cell, "rate": bar_rate, "eta": eta,
		"phase": 0.0, "period": CHARGE_SWEEP_MAX, "sweeping": false}
	return cell


## One full-height bar layer inside the charge gauge, left-anchored and driven
## through anchor_right.
func _make_bar_layer(color: Color) -> ColorRect:
	var bar: ColorRect = ColorRect.new()
	bar.color = color
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_left = 0.0
	bar.anchor_top = 0.0
	bar.anchor_right = 0.0
	bar.anchor_bottom = 1.0
	bar.offset_left = 0.0
	bar.offset_top = 0.0
	bar.offset_right = 0.0
	bar.offset_bottom = 0.0
	return bar


## Right-click on a spell cell: stop/resume paying mana into it. Stored charges
## stay castable and the partial fill is kept (Tribe.set_spell_active).
func _on_spell_cell_input(event: InputEvent, spell_id: StringName) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if mb.button_index != MOUSE_BUTTON_RIGHT or not mb.pressed:
		return
	var player: Tribe = _player_tribe()
	if player == null or _tribe_commands == null:
		return
	var spell: Spell = player.get_spell(spell_id)
	if spell == null:
		return
	_tribe_commands.set_spell_active(player, spell_id, not spell.active)
	_refresh_spells()
	# Consume it, or the same right-click would also reach the world below and
	# be read as a move order.
	accept_event()


func _build_followers_tab() -> Control:
	# Scrolls for the same reason as the spell tab (compact tab content height on
	# short windows / 1080p).
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vb: VBoxContainer = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 4)
	for row in FOLLOWER_ROWS:
		var lbl: Label = Label.new()
		var active: bool = row["active"]
		lbl.add_theme_color_override("font_color",
			UiTheme.TEXT if active else UiTheme.TEXT_DIM)
		lbl.text = "%s: 0" % row["name"]
		vb.add_child(lbl)
		_follower_labels[row["kind"]] = lbl

	_idle_button = Button.new()
	_idle_button.text = "Untätige Braves wählen"
	_idle_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(_idle_button)
	_idle_button.pressed.connect(_on_select_idle)
	vb.add_child(_idle_button)

	# Per-tribe vehicle caps (independent of any selected building): every
	# production shop of the tribe reads its Tribe.max_* value. Label shows
	# "Max. <Typ>: cap (owned)" in one line — three steppers must fit the tab.
	_add_cap_stepper(vb, "Katapulte",
		"Katapult-Limit des Stammes: alle Katapultwerkstätten stoppen die"
		+ " Fertigung, sobald so viele eigene Katapulte existieren",
		Tribe.MAX_CATAPULTS_LIMIT,
		func(t: Tribe) -> int: return t.max_catapults,
		func(t: Tribe, v: int) -> void: t.max_catapults = v,
		func(t: Tribe) -> int: return t.owned_catapult_count())
	_add_cap_stepper(vb, "Feuerrammen",
		"Feuerrammen-Limit des Stammes: alle Feuerrammenwerkstätten stoppen"
		+ " die Fertigung, sobald so viele eigene Feuerrammen existieren",
		Tribe.MAX_FIRE_RAMS_LIMIT,
		func(t: Tribe) -> int: return t.max_fire_rams,
		func(t: Tribe, v: int) -> void: t.max_fire_rams = v,
		func(t: Tribe) -> int: return t.owned_fire_ram_count())
	_add_cap_stepper(vb, "Luftschiffe",
		"Luftschiff-Limit des Stammes: alle Luftschiffwerften stoppen die"
		+ " Fertigung, sobald so viele eigene Luftschiffe existieren",
		Tribe.MAX_AIRSHIPS_LIMIT,
		func(t: Tribe) -> int: return t.max_airships,
		func(t: Tribe, v: int) -> void: t.max_airships = v,
		func(t: Tribe) -> int: return t.owned_airship_count())

	# Per-tribe toggle: military units auto-crew nearby ground vehicles (default on).
	# Its long label must NOT dictate the width — wrap it (and let it shrink), or
	# its minimum width forces the whole followers column past the panel edge.
	_auto_recrew_check = CheckButton.new()
	_auto_recrew_check.text = "Fahrzeuge automatisch bemannen"
	_auto_recrew_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_auto_recrew_check.clip_text = true
	_auto_recrew_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_auto_recrew_check.tooltip_text = "Eigene Militäreinheiten (Krieger, Feuerkrieger," \
		+ " Prediger) besetzen nahe Bodenfahrzeuge (max. 3 m) automatisch nach oder" \
		+ " übernehmen neutrale — auch im Kampf, außer im Nahkampf. Schamanin und" \
		+ " Braves sind ausgenommen; Luftschiffe ebenfalls."
	UiTheme.style_button(_auto_recrew_check)
	_auto_recrew_check.toggled.connect(_on_auto_recrew_toggled)
	vb.add_child(_auto_recrew_check)

	scroll.add_child(vb)
	return scroll


func _on_auto_recrew_toggled(pressed: bool) -> void:
	var player: Tribe = _player_tribe()
	if player != null:
		player.auto_recrew_vehicles = pressed


## Builds one vehicle-cap stepper row [Titel  −  Zahl  +] and registers it for
## the periodic refresh. The title label absorbs the free width and ellipsizes,
## so the −/Zahl/+ group stays inside the panel; the number label has a fixed
## width for two digits, so the "+" button stays visible up to a cap of 99.
func _add_cap_stepper(vb: VBoxContainer, title: String, tooltip: String,
		limit: int, get_cap: Callable, set_cap: Callable, get_owned: Callable) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	vb.add_child(row)
	var entry: Dictionary = {"title": title, "limit": limit, "get_cap": get_cap,
		"set_cap": set_cap, "get_owned": get_owned}
	var title_label: Label = Label.new()
	title_label.add_theme_color_override("font_color", UiTheme.TEXT)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.clip_text = true   # may shrink below its text width -> ellipsis
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.tooltip_text = tooltip
	row.add_child(title_label)
	var minus: Button = Button.new()
	minus.text = "−"
	UiTheme.style_button(minus)
	minus.pressed.connect(func() -> void: _on_cap_delta(entry, -1))
	row.add_child(minus)
	var count_label: Label = Label.new()
	count_label.add_theme_color_override("font_color", UiTheme.TEXT)
	count_label.custom_minimum_size = Vector2(26, 0)   # room for two digits
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.tooltip_text = tooltip
	row.add_child(count_label)
	var plus: Button = Button.new()
	plus.text = "+"
	UiTheme.style_button(plus)
	plus.pressed.connect(func() -> void: _on_cap_delta(entry, 1))
	row.add_child(plus)
	entry["title_label"] = title_label
	entry["count_label"] = count_label
	_cap_steppers.append(entry)


func _on_cap_delta(entry: Dictionary, delta: int) -> void:
	var player: Tribe = _player_tribe()
	if player == null:
		return
	var cap: int = int((entry["get_cap"] as Callable).call(player))
	(entry["set_cap"] as Callable).call(player,
		clampi(cap + delta, 0, int(entry["limit"])))
	_refresh_cap_steppers()


func _refresh_cap_steppers() -> void:
	var player: Tribe = _player_tribe()
	if player == null:
		return
	for entry in _cap_steppers:
		var title_label: Label = entry["title_label"]
		var count_label: Label = entry["count_label"]
		if title_label == null or not is_instance_valid(title_label):
			continue
		var owned: int = int((entry["get_owned"] as Callable).call(player))
		var cap: int = int((entry["get_cap"] as Callable).call(player))
		# "Name: Besitz/Limit"; the editable limit also shows between the buttons.
		title_label.text = "%s: %d/%d" % [entry["title"], owned, cap]
		count_label.text = "%d" % cap


# --- Crew tab (occupancy of the selected mannable object) ---------------------

## German label for a crew unit kind (shown in the slot tooltips).
static func _crew_kind_label(kind: StringName) -> String:
	match kind:
		&"brave":
			return "Gefolgsmann"
		&"warrior":
			return "Krieger"
		&"firewarrior":
			return "Feuerkrieger"
		&"preacher":
			return "Prediger"
		&"shaman":
			return "Schamanin"
	return "Einheit"


## Crew tab: title + info line, one icon button per occupant (click ejects)
## and a production pause toggle for producers.
func _build_crew_tab() -> Control:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vb: VBoxContainer = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 4)

	_crew_title = Label.new()
	_crew_title.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
	vb.add_child(_crew_title)

	_crew_info = Label.new()
	_crew_info.add_theme_color_override("font_color", UiTheme.TEXT)
	_crew_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_crew_info)

	# Slot buttons for the largest crew (the catapult); surplus slots hide.
	var slot_row: HBoxContainer = HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 4)
	vb.add_child(slot_row)
	for i in range(SiegeEngine.MAX_CREW):
		var b: Button = Button.new()
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UiTheme.style_button(b)
		var idx: int = i
		b.pressed.connect(func() -> void: _on_crew_eject(idx))
		slot_row.add_child(b)
		_crew_slot_buttons.append(b)

	_crew_pause_button = Button.new()
	_crew_pause_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(_crew_pause_button)
	_crew_pause_button.pressed.connect(_on_crew_pause)
	vb.add_child(_crew_pause_button)

	# Airship only: arms the unload mode — the next right-click on terrain
	# sends the ship there and drops ALL passengers (SelectionManager).
	_crew_unload_button = Button.new()
	_crew_unload_button.text = "Absetzen an…"
	_crew_unload_button.tooltip_text = "Rechtsklick auf einen Zielpunkt:" \
		+ " das Luftschiff fliegt hin und setzt die gesamte Besatzung ab"
	_crew_unload_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(_crew_unload_button)
	_crew_unload_button.pressed.connect(_on_crew_unload)
	vb.add_child(_crew_unload_button)

	scroll.add_child(vb)
	return scroll


func _on_crew_unload() -> void:
	var target: Object = _selected_crew_target()
	if target is Airship and _selection != null:
		_selection.arm_unload(target as Airship)


## The single selected mannable object (own building or own catapult), or null.
func _selected_crew_target() -> Object:
	if _selection == null:
		return null
	var b: Building = _selection.selected_building
	if is_instance_valid(b) and not b.under_construction and b.health > 0 \
			and not b.demolishing and b.tribe_id == _player_id:
		return b
	if _selection.selected.size() == 1:
		var u: Unit = _selection.selected[0]
		if is_instance_valid(u) and u is CrewedVehicle and u.state != Unit.State.DEAD \
				and u.tribe_id == _player_id:
			return u
	return null


## Normalised occupancy view of a crew target: occupants list, slot capacity
## and info line (bridges the crew/occupants field split across the classes).
func _crew_view(target: Object) -> Dictionary:
	if target is Hut:
		var hut: Hut = target as Hut
		# 10f: capacity is per upgrade stage, so `cap` (which drives how many slot
		# buttons show) has to come from the instance, not a class constant.
		var stage: String = "Stufe %d/%d" % [hut.upgrade_stage,
			Balance.HUT_MAX_UPGRADE_STAGE]
		var info: String = ""
		if hut.upgrading:
			info = "%s   Ausbau: %.0f %%   Holz: %d/%d" % [stage,
				hut.upgrade_progress() * 100.0, hut.upgrade_wood,
				Balance.HUT_UPGRADE_WOOD_COST]
		else:
			info = "%s   Besatzung: %d/%d   Wachstum: +%.1f/min" % [stage,
				hut.crew_count(), hut.crew_capacity(), hut.growth_per_minute()]
		return {"members": hut.crew, "cap": hut.crew_capacity(), "info": info}
	if target is Forester:
		var f: Forester = target as Forester
		return {"members": f.occupants, "cap": Forester.WORKER_SLOTS,
			"info": "Arbeiter: %d/%d" % [f.occupants.size(), Forester.WORKER_SLOTS]}
	# Subclasses BEFORE the Workshop branch (`is Workshop` matches them too).
	if target is FireRamWorkshop:
		var rws: FireRamWorkshop = target as FireRamWorkshop
		return {"members": rws.occupants, "cap": rws.worker_slots(),
			"info": "Arbeiter: %d/%d   Vorrat: %d/%d   Feuerrammen: %d/%d" % [
				rws.occupants.size(), rws.worker_slots(),
				rws.stock_wood(), rws.stock_target(),
				rws.tribe.owned_fire_ram_count() if rws.tribe != null else 0,
				rws.tribe.max_fire_rams if rws.tribe != null else 0]}
	if target is AirshipWharf:
		var aw: AirshipWharf = target as AirshipWharf
		return {"members": aw.occupants, "cap": aw.worker_slots(),
			"info": "Arbeiter: %d/%d   Vorrat: %d/%d   Luftschiffe: %d/%d" % [
				aw.occupants.size(), aw.worker_slots(),
				aw.stock_wood(), aw.stock_target(),
				aw.tribe.owned_airship_count() if aw.tribe != null else 0,
				aw.tribe.max_airships if aw.tribe != null else 0]}
	if target is Workshop:
		var ws: Workshop = target as Workshop
		return {"members": ws.occupants, "cap": ws.worker_slots(),
			"info": "Arbeiter: %d/%d   Vorrat: %d/%d   Katapulte: %d/%d" % [
				ws.occupants.size(), ws.worker_slots(),
				ws.stock_wood(), ws.stock_target(),
				ws.tribe.owned_catapult_count() if ws.tribe != null else 0,
				ws.tribe.max_catapults if ws.tribe != null else 0]}
	if target is Watchtower:
		var t: Watchtower = target as Watchtower
		return {"members": t.crew, "cap": Watchtower.CREW_CAPACITY,
			"info": "Besatzung: %d/%d" % [t.crew.size(), Watchtower.CREW_CAPACITY]}
	if target is WoodDepot:
		var d: WoodDepot = target as WoodDepot
		return {"members": [], "cap": 0,
			"info": "Lager: %d/%d Holz" % [d.stored_wood(), WoodDepot.CAPACITY]}
	if target is Airship:
		var a: Airship = target as Airship
		return {"members": a.crew, "cap": a.max_crew,
			"info": "Passagiere: %d/%d  (Kampf nur im Stand, +3 Reichweite)" % [
				a.boarded_count(), a.max_crew]}
	if target is CrewedVehicle:
		var e: CrewedVehicle = target as CrewedVehicle
		return {"members": e.crew, "cap": e.max_crew,
			"info": "Besatzung: %d/%d  %s" % [
				e.boarded_count(), e.max_crew, _vehicle_crew_hint(e)]}
	if target is TrainingBuilding:
		var tb: TrainingBuilding = target as TrainingBuilding
		var queue: int = tb.incoming.size() + (1 if is_instance_valid(tb.trainee) else 0)
		return {"members": [], "cap": 0, "info": "In Ausbildung: %d" % queue}
	return {"members": [], "cap": 0, "info": ""}


## Short crew-rule hint per vehicle type for the crew tab's info line.
func _vehicle_crew_hint(e: CrewedVehicle) -> String:
	match e.unit_kind():
		&"siege":
			return "(min. 1 fahren, 2 feuern)"
		&"fireram":
			return "(min. 1 fahren & feuern)"
	return ""


## Whether the target has a production the player can pause (crew tab toggle).
func _crew_target_pausable(target: Object) -> bool:
	return target is Hut or target is TrainingBuilding \
		or target is Forester or target is Workshop


## Polled every frame: auto-activates the crew tab when a mannable object
## becomes the single selection (edge, not level — manual tab clicks while the
## selection persists are respected), returns to the previous tab when the
## selection drops, and greys the tab button out while there is no target.
func _refresh_crew_tab() -> void:
	if _crew_title == null or _tab_buttons.size() <= TAB_CREW:
		return
	var target: Object = _selected_crew_target()
	_tab_buttons[TAB_CREW].disabled = target == null
	if target != null and _crew_target_obj == null:
		_crew_return_tab = _active_tab if _active_tab != TAB_CREW else 0
		_select_tab(TAB_CREW)
	elif target == null and _crew_target_obj != null and _active_tab == TAB_CREW:
		_select_tab(_crew_return_tab)
	_crew_target_obj = target
	if target == null:
		return
	var view: Dictionary = _crew_view(target)
	_crew_title.text = target.display_name() if target.has_method("display_name") \
		else "Belagerungswaffe"
	_crew_info.text = view["info"]
	_crew_info.visible = view["info"] != ""
	var members: Array = view["members"]
	var cap: int = view["cap"]
	for i in range(_crew_slot_buttons.size()):
		var btn: Button = _crew_slot_buttons[i]
		if i >= cap:
			btn.visible = false
			continue
		btn.visible = true
		var member = members[i] if i < members.size() else null
		if member != null and is_instance_valid(member):
			btn.icon = UiTheme.icon(member.unit_kind())
			btn.disabled = false
			var label: String = _crew_kind_label(member.unit_kind())
			if target is CrewedVehicle and not member.siege_boarded:
				label += " (unterwegs)"
			btn.tooltip_text = "%s — Klick: rauswerfen" % label
		else:
			btn.icon = null
			btn.disabled = true
			btn.tooltip_text = "frei"
	_crew_pause_button.visible = _crew_target_pausable(target)
	if _crew_pause_button.visible:
		_crew_pause_button.text = "Produktion fortsetzen" if target.paused \
			else "Produktion pausieren"
	if _crew_unload_button != null:
		_crew_unload_button.visible = target is Airship \
			and (target as Airship).boarded_count() > 0


## Slot click: eject that occupant. The hut eject is MANUAL (pins the crew
## size so the growth mode does not refill it, see Hut.manual_crew_override).
func _on_crew_eject(index: int) -> void:
	var target: Object = _selected_crew_target()
	if target == null:
		return
	if target is Hut:
		(target as Hut).eject_crew(index, true)
	elif target is Forester:
		(target as Forester).eject_worker(index)
	elif target is Workshop:
		(target as Workshop).eject_worker(index)
	elif target is Watchtower:
		(target as Watchtower).eject_crew(index)
	elif target is Airship:
		# Airship eject: the passenger is DROPPED to the ground below (a plain
		# leave_crew would strand it standing mid-air).
		var ship: Airship = target as Airship
		if index >= 0 and index < ship.crew.size():
			var passenger = ship.crew[index]
			if passenger != null and is_instance_valid(passenger):
				ship.drop_member(passenger)
	elif target is CrewedVehicle:
		var engine: CrewedVehicle = target as CrewedVehicle
		if index >= 0 and index < engine.crew.size():
			var member = engine.crew[index]
			if member != null and is_instance_valid(member):
				member.leave_crew()
	_refresh_crew_tab()


func _on_crew_pause() -> void:
	var target: Object = _selected_crew_target()
	if target != null and _crew_target_pausable(target):
		target.paused = not target.paused
		_refresh_crew_tab()


func _build_menu_panel(root: Control) -> void:
	var pause: Button = Button.new()
	pause.icon = UiTheme.icon(&"pause")
	pause.text = "Menü"
	pause.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(pause)
	pause.pressed.connect(_toggle_pause)
	root.add_child(pause)


func _build_pause_menu() -> void:
	_pause_menu = Control.new()
	_pause_menu.name = "PauseMenu"
	_pause_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_menu.visible = false
	add_child(_pause_menu)

	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.5)
	_pause_menu.add_child(dim)

	var box: PanelContainer = PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiTheme.panel_style())
	box.set_anchors_preset(Control.PRESET_CENTER)
	_pause_menu.add_child(box)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	box.add_child(vb)

	var title: Label = Label.new()
	title.text = "Pause"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
	vb.add_child(title)

	var resume: Button = Button.new()
	resume.text = "Fortsetzen"
	UiTheme.style_button(resume)
	resume.pressed.connect(_toggle_pause)
	vb.add_child(resume)

	# Sound volume (master bus), session-scoped.
	var volume_label: Label = Label.new()
	volume_label.text = "Soundlautstärke"
	volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	volume_label.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
	vb.add_child(volume_label)

	var volume: HSlider = HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 100.0
	volume.step = 5.0
	volume.custom_minimum_size = Vector2(180, 20)
	volume.value = AudioSettings.master_volume_percent()
	volume.value_changed.connect(AudioSettings.set_master_volume_percent)
	vb.add_child(volume)

	var battle: Button = Button.new()
	battle.text = "Debugschlacht"
	UiTheme.style_button(battle)
	battle.pressed.connect(_start_debug_battle)
	vb.add_child(battle)

	var menu: Button = Button.new()
	menu.text = "Hauptmenü"
	UiTheme.style_button(menu)
	menu.pressed.connect(_back_to_main_menu)
	vb.add_child(menu)

	var quit: Button = Button.new()
	quit.text = "Beenden"
	UiTheme.style_button(quit)
	quit.pressed.connect(func() -> void: get_tree().quit())
	vb.add_child(quit)


## Reloads the map as the debug battle scenario (two 800-unit armies meeting
## in the middle; Main._ready consumes GameState.match_config).
func _start_debug_battle() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		return
	gs.match_config = MatchConfig.debug_battle()
	# No GameState.reset() here: the old scene still runs until the deferred
	# reload, and Main._ready re-populates everything anyway.
	get_tree().paused = false
	get_tree().reload_current_scene()


## Leaves the running match and returns to the full-screen main menu.
func _back_to_main_menu() -> void:
	get_tree().paused = false
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.reset()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


# --- Tab switching ----------------------------------------------------------

func _select_tab(index: int) -> void:
	_active_tab = index
	for i in range(_tab_panels.size()):
		_tab_panels[i].visible = i == index
	for i in range(_tab_buttons.size()):
		_tab_buttons[i].button_pressed = i == index


# --- Signal handlers --------------------------------------------------------

func _on_population_changed(tribe_id: int, population: int, capacity: int) -> void:
	if tribe_id == _player_id:
		_set_population(population, capacity)
	_refresh_tribe_bars()


func _on_mana_changed(tribe_id: int, amount: float) -> void:
	if tribe_id == _player_id:
		_set_mana(amount)


func _on_stockpile_changed(_total: int) -> void:
	# The readout is "wood near own buildings", not the global total, so
	# recompute from the piles rather than using the emitted total.
	_refresh_wood_near_base()


## Sums wood in piles near the player's own buildings (delivered/base wood).
func _refresh_wood_near_base() -> void:
	if _wood_pile_manager == null or _building_manager == null:
		return
	var positions: Array[Vector3] = []
	for b: Building in _building_manager.get_buildings_of_tribe(_player_id):
		positions.append(b.center_world())
	_set_wood(_wood_pile_manager.wood_near_positions(positions, WOOD_NEAR_RADIUS))


func _set_population(population: int, capacity: int) -> void:
	if _pop_label != null:
		_pop_label.text = "Bevölkerung: %d/%d" % [population, capacity]


## Growth slider moved: apply the mode to the player's tribe (clears all manual
## hut-crew overrides — the slider is the master switch) and refresh the label.
func _on_growth_changed(value: float) -> void:
	if _player_id < _tribes.size():
		_tribes[_player_id].set_growth_mode(int(value) as Tribe.GrowthMode)
	_update_growth_label()


## Hut-upgrade lock toggled (phase 10f): tribe-wide, routed through TribeCommands
## like every other tribe mutation (see 00_overview.md §4).
func _on_upgrades_toggled(pressed: bool) -> void:
	var player: Tribe = _player_tribe()
	if player != null and _tribe_commands != null:
		_tribe_commands.set_upgrades_allowed(player, pressed)


func _update_growth_label() -> void:
	# The upgrade lock rides along on the same refresh: it can also be changed
	# from outside the sidebar (elimination resets, tests), so mirror the tribe.
	var player: Tribe = _player_tribe()
	if _upgrades_check != null and player != null:
		_upgrades_check.set_pressed_no_signal(player.upgrades_allowed)
	if _growth_label == null:
		return
	var names: Array[String] = ["Kein", "Minimal", "Maximum"]
	var mode: int = 0
	if _player_id < _tribes.size():
		mode = int(_tribes[_player_id].growth_mode)
	_growth_label.text = "%s  (+%.0f/min)" % [names[clampi(mode, 0, 2)], _player_growth_per_min()]


## Total brave growth per minute across the player's manned huts (readout).
func _player_growth_per_min() -> float:
	if _building_manager == null:
		return 0.0
	var total: float = 0.0
	for b: Building in _building_manager.get_buildings_of_tribe(_player_id):
		if is_instance_valid(b) and b is Hut:
			total += (b as Hut).growth_per_minute()
	return total


func _set_wood(amount: int) -> void:
	if _wood_label != null:
		_wood_label.text = "Holz: %d" % amount


## Mana is no longer banked (phase 10c) — a stored amount would always read 0.
## The bar and the label therefore show the INCOME and where it goes: the rate
## per second and how many spells are currently sharing it.
func _set_mana(_amount: float) -> void:
	var player: Tribe = _player_tribe()
	# NET income (bugfix): the label used to show the gross mana_rate(), so
	# staffing a forester or starting a training changed nothing on screen even
	# though both really cost mana. The upkeep is named separately, otherwise a
	# shrinking number would look like the population had dropped.
	var upkeep: float = player.upkeep_rate() if player != null else 0.0
	var rate: float = player.charging_income() if player != null else 0.0
	var takers: int = player.active_spell_count() if player != null else 0
	var filled: int = mana_segments(rate, MANA_RATE_DISPLAY_CAP, MANA_SEGMENTS)
	for i in range(_mana_segments.size()):
		_mana_segments[i].color = _mana_fill_color() if i < filled else _mana_empty_color()
	if _mana_label != null:
		var cost: String = "  (−%.1f Unterhalt)" % upkeep if upkeep > 0.05 else ""
		if takers > 0:
			_mana_label.text = "Mana: +%.1f/s%s  auf %d Zauber" % [rate, cost, takers]
		else:
			_mana_label.text = "Mana: +%.1f/s%s  (verfällt)" % [rate, cost]


func _refresh_tribe_bars() -> void:
	var pops: Array[int] = []
	for i in range(_tribe_bars.size()):
		pops.append(_tribes[i].population() if i < _tribes.size() else 0)
	var fracs: Array[float] = tribe_bar_fractions(pops)
	for i in range(_tribe_bars.size()):
		_tribe_bars[i].value = fracs[i]


func _refresh_followers() -> void:
	if _unit_manager == null:
		return
	var counts: Dictionary = {}
	for row in FOLLOWER_ROWS:
		counts[row["kind"]] = 0
	for u: Unit in _unit_manager.get_units_of_tribe(_player_id):
		if u.state == Unit.State.DEAD:
			continue
		var kind: StringName = u.unit_kind()
		if counts.has(kind):
			counts[kind] += 1
	for row in FOLLOWER_ROWS:
		var kind: StringName = row["kind"]
		var lbl: Label = _follower_labels.get(kind)
		if lbl != null:
			lbl.text = "%s: %d" % [row["name"], counts[kind]]
	_refresh_cap_steppers()
	var player: Tribe = _player_tribe()
	if _auto_recrew_check != null and player != null:
		_auto_recrew_check.set_pressed_no_signal(player.auto_recrew_vehicles)


# --- Spells & shaman portrait (phase 6) ----------------------------------------

func _player_tribe() -> Tribe:
	if _player_id >= 0 and _player_id < _tribes.size():
		return _tribes[_player_id]
	return null


func _player_shaman_alive() -> bool:
	var player: Tribe = _player_tribe()
	if player == null:
		return false
	var shaman: Unit = player.shaman
	return shaman != null and is_instance_valid(shaman) \
		and shaman.state != Unit.State.DEAD


func _on_spell_charges_changed(tribe_id: int) -> void:
	if tribe_id == _player_id:
		_refresh_spells()


## Feeds the charge system into the pip display: castable = stored charge +
## living shaman.
func _refresh_spells() -> void:
	var player: Tribe = _player_tribe()
	if player == null:
		return
	if player.spells.is_empty():
		for entry in default_spell_entries():
			set_spell_state(entry["id"], 0, entry["max_charges"], 0.0, false)
		return
	var alive: bool = _player_shaman_alive()
	for spell in player.spells:
		set_spell_state(spell.id, spell.charges, spell.max_charges,
			spell.charge_progress, alive and spell.charges > 0, spell.active,
			player.seconds_to_next_charge(spell))


func _on_spell_pressed(spell_id: StringName) -> void:
	if _spell_targeting != null:
		_spell_targeting.toggle_targeting(spell_id)


func _on_portrait_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_on_portrait_pressed()


## Portrait click: centre the camera on the shaman and select ONLY her
## (select_units replaces the whole selection and clears any building).
func _on_portrait_pressed() -> void:
	var player: Tribe = _player_tribe()
	if player == null or not _player_shaman_alive():
		return
	var shaman: Unit = player.shaman
	if _selection != null:
		_selection.select_units([shaman] as Array[Unit])
	if _camera_rig != null:
		_camera_rig.global_position = shaman.position


## Mirrors the shaman into the portrait: her current animation (front view),
## tribe colour, health bar; corpse pose + respawn countdown while dead.
func _refresh_portrait() -> void:
	if _portrait_sprite == null:
		return
	var player: Tribe = _player_tribe()
	if player != null:
		_portrait_sprite.modulate = player.color
	if _player_shaman_alive():
		var shaman: Unit = player.shaman
		_set_portrait_anim(StringName("%s_front" % shaman.anim_base_name))
		_portrait_hp.value = float(shaman.health) / float(maxi(shaman.max_health, 1))
		_portrait_status.text = ""
		_portrait_status.visible = false
		return
	_set_portrait_anim(&"dead_front")
	_portrait_hp.value = 0.0
	var remaining: float = -1.0
	if player != null:
		for b in player.buildings:
			if is_instance_valid(b) and b is ReincarnationSite:
				remaining = (b as ReincarnationSite).respawn_remaining()
				break
	if remaining >= 0.0:
		_portrait_status.text = "Wiederkehr in %d s" % int(ceil(remaining))
	else:
		_portrait_status.text = "Keine Wiederkehr"
	_portrait_status.visible = true


func _set_portrait_anim(anim: StringName) -> void:
	var frames: SpriteFrames = _portrait_sprite.sprite_frames
	if frames == null:
		return
	if not frames.has_animation(anim):
		anim = &"idle_front"
	if _portrait_sprite.animation != anim or not _portrait_sprite.is_playing():
		_portrait_sprite.play(anim)


# --- Spell display API ---------------------------------------------------------

func set_spell_state(id: StringName, charges: int, max_charges: int,
		charge_progress: float, castable: bool, active: bool = true,
		remaining_s: float = INF) -> void:
	if not _spell_ui.has(id):
		return
	var ui: Dictionary = _spell_ui[id]
	var pips: Array = ui["pips"]
	var st: Dictionary = pip_state(charges, max_charges, charge_progress)
	var filled: int = st["filled"]
	var progress: float = st["progress"]
	for i in range(pips.size()):
		var pip: ColorRect = pips[i]
		if i < filled:
			pip.color = _pip_full_color()
		elif i == filled and progress > 0.0:
			pip.color = _pip_empty_color().lerp(_pip_full_color(), progress)
		else:
			pip.color = _pip_empty_color()
	(ui["button"] as Button).disabled = not castable
	# Charge bar: how far the NEXT charge has filled. A switched-off spell
	# keeps its bar (the progress is preserved) but the cell is dimmed, so it
	# reads as "paused", not as "empty".
	var bar: ColorRect = ui["bar"]
	bar.anchor_right = progress
	bar.offset_right = 0.0
	bar.color = UiTheme.CHARGE_BLUE if active \
		else _pip_empty_color().lerp(UiTheme.CHARGE_BLUE, 0.4)
	(ui["cell"] as Control).modulate = Color.WHITE if active else Color(0.55, 0.55, 0.55)

	# Rate bar + ETA (phase 10k). The sweep only runs while the spell really
	# takes mana; a full or switched-off spell freezes it, which is the visual
	# difference between "paused" and "charging slowly".
	var sweeping: bool = active and progress > 0.0 or (active and charges < max_charges)
	ui["sweeping"] = sweeping and is_finite(remaining_s)
	ui["period"] = sweep_period(remaining_s)
	var rate: ColorRect = ui.get("rate") as ColorRect
	if rate != null:
		rate.color = UiTheme.GOLD if active else _pip_empty_color()
		if not bool(ui["sweeping"]):
			rate.anchor_right = 0.0
			rate.offset_right = 0.0
	var eta: Label = ui.get("eta") as Label
	if eta != null:
		var text: String = charge_eta_text(remaining_s) if active else ""
		eta.text = text
		eta.visible = text != ""


# --- Button actions ---------------------------------------------------------

func _on_build_pressed(scene: PackedScene) -> void:
	if _spell_targeting != null and _spell_targeting.is_active():
		_spell_targeting.cancel()   # only one target mode at a time
	if _build_menu != null and scene != null:
		_build_menu.start_placement(scene)


func _on_select_idle() -> void:
	if _unit_manager == null or _selection == null:
		return
	var idle: Array[Unit] = []
	for u: Unit in _unit_manager.get_units_of_tribe(_player_id):
		if is_instance_valid(u) and u is Brave and u.state == Unit.State.IDLE:
			idle.append(u)
	_selection.select_units(idle)


# --- Pause menu -------------------------------------------------------------

func _toggle_pause() -> void:
	var paused: bool = not get_tree().paused
	get_tree().paused = paused
	if _pause_menu != null:
		_pause_menu.visible = paused


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# While placing a building, targeting a spell or with an armed attack-move,
	# Esc cancels that mode (handled there) instead of pausing.
	if _build_menu != null and _build_menu.is_active():
		return
	if _spell_targeting != null and _spell_targeting.is_active():
		return
	if SelectionManager.attack_arm_active:
		return
	_toggle_pause()
	get_viewport().set_input_as_handled()


# --- Colours ----------------------------------------------------------------

func _mana_fill_color() -> Color:
	return Color(0.35, 0.6, 1.0)


func _mana_empty_color() -> Color:
	return Color(0.1, 0.12, 0.18)


func _pip_full_color() -> Color:
	return UiTheme.GOLD_BRIGHT


func _pip_empty_color() -> Color:
	return Color(0.15, 0.11, 0.06)
