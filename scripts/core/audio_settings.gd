class_name AudioSettings extends RefCounted

## Lautstärkeregler je Kanal — geteilt von den Hauptmenü-Optionen und dem
## Pausenmenü im Spiel (Nutzerwunsch 2026-09-02: neben "Gesamt" auch Effekte,
## Bedienung und Musik einzeln regelbar).
##
## Ein "Kanal" ist ein Regler und bildet auf einen oder mehrere AudioServer-Busse
## ab (der Musikregler auf Musik UND Umgebung — sonst wäre die Ambience-Spur
## nicht erreichbar, und als eigener Regler will sie niemand). Die Bus-Namen
## selbst legt AudioManager.BUSES an; ein Test hält die beiden Listen zusammen.
##
## Anders als früher wird der Wert GESPEICHERT (user://settings.cfg, eigener
## Abschnitt neben GameSettings) statt aus dem Bus zurückgelesen: ein Regler,
## den man nach jedem Start neu ziehen muss, ist ein Ärgernis, und der Rückweg
## über dB/linear rundet. AudioManager._ready ruft apply_all(), sobald die Busse
## stehen.

## Reihenfolge = Reihenfolge der Regler im Menü. Bewusst "Gesamt" zuerst.
const CHANNELS: Array = [
	{"key": &"master", "label": "Gesamt", "buses": ["Master"]},
	{"key": &"sfx", "label": "Effekte", "buses": ["SFX"]},
	{"key": &"ui", "label": "Bedienung", "buses": ["UI"]},
	{"key": &"music", "label": "Musik & Umgebung", "buses": ["Music", "Ambience"]},
]

const FILE_PATH: String = GameSettings.FILE_PATH
const SECTION: String = "audio"
const DEFAULT_PERCENT: float = 100.0

static var _loaded: bool = false
static var _levels: Dictionary = {}   # key -> 0..100


## Gespeicherter Wert eines Kanals (0..100).
static func volume_percent(key: StringName) -> float:
	_ensure_loaded()
	return float(_levels.get(key, DEFAULT_PERCENT))


## Setzt einen Kanal, wendet ihn sofort an und speichert ihn. 0 stummt die
## zugehörigen Busse (statt sie auf -80 dB zu schieben).
static func set_volume_percent(key: StringName, value: float) -> void:
	_ensure_loaded()
	_levels[key] = clampf(value, 0.0, 100.0)
	_apply(key)
	_save()


## Schiebt alle gespeicherten Werte in den AudioServer. Muss laufen, NACHDEM die
## Busse existieren (AudioManager._enter_tree legt sie an, _ready ruft dies).
static func apply_all() -> void:
	_ensure_loaded()
	for channel in CHANNELS:
		_apply(channel["key"] as StringName)


## Label eines Kanals für die Menüs; leer bei unbekanntem Schlüssel.
static func label_of(key: StringName) -> String:
	for channel in CHANNELS:
		if channel["key"] == key:
			return String(channel["label"])
	return ""


static func _apply(key: StringName) -> void:
	var value: float = volume_percent(key)
	for bus_name in _buses_of(key):
		var idx: int = AudioServer.get_bus_index(bus_name)
		if idx == -1:
			continue   # Bus noch nicht angelegt (headless, früher Start)
		if value <= 0.0:
			AudioServer.set_bus_mute(idx, true)
			continue
		AudioServer.set_bus_mute(idx, false)
		AudioServer.set_bus_volume_db(idx, linear_to_db(value / 100.0))


static func _buses_of(key: StringName) -> Array:
	for channel in CHANNELS:
		if channel["key"] == key:
			return channel["buses"] as Array
	return []


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg: ConfigFile = ConfigFile.new()
	var has_file: bool = cfg.load(FILE_PATH) == OK
	for channel in CHANNELS:
		var key: StringName = channel["key"] as StringName
		_levels[key] = float(cfg.get_value(SECTION, String(key), DEFAULT_PERCENT)) \
			if has_file else DEFAULT_PERCENT


static func _save() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(FILE_PATH)   # fremde Abschnitte (display) erhalten
	for channel in CHANNELS:
		var key: StringName = channel["key"] as StringName
		cfg.set_value(SECTION, String(key), float(_levels.get(key, DEFAULT_PERCENT)))
	cfg.save(FILE_PATH)
