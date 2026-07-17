extends Node

## Autoload "AudioManager": bus setup (Music/Ambience/SFX/UI), file-based
## one-shot SFX/UI sounds and the music/ambience playlists. All lookups go
## through AssetLibrary — a missing file simply plays nothing (one warning per
## name), so the game works without any audio assets. Combat hit sounds stay
## in CombatAudio (with its own throttle); this manager covers everything else.

const SFX_POOL_SIZE: int = 8
const UI_POOL_SIZE: int = 4
const BUSES: Array[String] = ["Music", "Ambience", "SFX", "UI"]

var _sfx_pool: Array[AudioStreamPlayer3D] = []
var _sfx_index: int = 0
var _ui_pool: Array[AudioStreamPlayer] = []
var _ui_index: int = 0
var _music_player: AudioStreamPlayer
var _ambience_player: AudioStreamPlayer
var _music_tracks: Array[AudioStream] = []
var _ambience_tracks: Array[AudioStream] = []
var _music_index: int = 0
var _ambience_index: int = 0
var _missing_warned: Dictionary = {}   # sfx/ui name -> true
var _sfx_last_ms: Dictionary = {}      # sfx name -> last play (min-interval throttle)


func _enter_tree() -> void:
	# Idempotent bus creation (autoload survives scene reloads, but guard anyway).
	for bus_name in BUSES:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx: int = AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func _ready() -> void:
	for i in range(SFX_POOL_SIZE):
		var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		player.max_distance = 60.0
		player.bus = "SFX"
		add_child(player)
		_sfx_pool.append(player)
	for i in range(UI_POOL_SIZE):
		var ui_player: AudioStreamPlayer = AudioStreamPlayer.new()
		ui_player.bus = "UI"
		add_child(ui_player)
		_ui_pool.append(ui_player)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.finished.connect(_on_music_finished)
	add_child(_music_player)
	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.bus = "Ambience"
	_ambience_player.finished.connect(_on_ambience_finished)
	add_child(_ambience_player)
	_music_tracks = AssetLibrary.stream_folder("audio/music")
	_ambience_tracks = AssetLibrary.stream_folder("audio/ambience")
	_start_playlists()
	var events: Node = get_node_or_null("/root/Events")
	if events != null:
		events.building_completed.connect(_on_building_completed)
		events.unit_trained.connect(_on_unit_trained)
		events.spell_cast.connect(_on_spell_cast)
		events.building_destroyed.connect(_on_building_destroyed)
		events.unit_died.connect(_on_unit_died)


# --- One-shot sounds -----------------------------------------------------------------

## Plays assets/audio/sfx/<name>.ogg positionally; silent when missing.
## min_interval_ms > 0 throttles repeats of the SAME name (mass events like
## panic waves or death piles collapse into one sound per interval).
func play_sfx(name: StringName, pos: Vector3, min_interval_ms: int = 0) -> void:
	if min_interval_ms > 0:
		var now: int = Time.get_ticks_msec()
		if now - int(_sfx_last_ms.get(name, -min_interval_ms)) < min_interval_ms:
			return
		_sfx_last_ms[name] = now
	var stream: AudioStream = _lookup(&"sfx", "audio/sfx/%s" % name)
	if stream == null:
		return
	var player: AudioStreamPlayer3D = _sfx_pool[_sfx_index]
	_sfx_index = (_sfx_index + 1) % SFX_POOL_SIZE
	if player.playing:
		return   # pool exhausted -> drop (throttle)
	player.stream = stream
	player.global_position = pos
	player.play()


## Plays assets/audio/ui/<name>.ogg non-positionally; silent when missing.
func play_ui(name: StringName) -> void:
	var stream: AudioStream = _lookup(&"ui", "audio/ui/%s" % name)
	if stream == null:
		return
	var player: AudioStreamPlayer = _ui_pool[_ui_index]
	_ui_index = (_ui_index + 1) % UI_POOL_SIZE
	if player.playing:
		return
	player.stream = stream
	player.play()


## True when a file for this sfx name exists (callers with a procedural
## fallback — e.g. the siege shot's synth whoosh — decide with this).
func has_sfx(name: StringName) -> bool:
	return AssetLibrary.exists("audio/sfx/%s.ogg" % name) \
		or AssetLibrary.exists("audio/sfx/%s.wav" % name)


## Resolves <rel>.ogg / <rel>.wav; warns once per missing name.
func _lookup(kind: StringName, rel: String) -> AudioStream:
	for ext in ["ogg", "wav"]:
		var stream: AudioStream = AssetLibrary.stream("%s.%s" % [rel, ext])
		if stream != null:
			return stream
	var key: String = "%s:%s" % [kind, rel]
	if not _missing_warned.has(key):
		_missing_warned[key] = true
	return null


# --- Playlists -----------------------------------------------------------------------

func _start_playlists() -> void:
	if not _music_tracks.is_empty():
		_music_player.stream = _music_tracks[0]
		_music_player.play()
	if not _ambience_tracks.is_empty():
		_ambience_player.stream = _ambience_tracks[0]
		_ambience_player.play()


func _on_music_finished() -> void:
	if _music_tracks.is_empty():
		return
	_music_index = (_music_index + 1) % _music_tracks.size()
	_music_player.stream = _music_tracks[_music_index]
	_music_player.play()


func _on_ambience_finished() -> void:
	if _ambience_tracks.is_empty():
		return
	_ambience_index = (_ambience_index + 1) % _ambience_tracks.size()
	_ambience_player.stream = _ambience_tracks[_ambience_index]
	_ambience_player.play()


# --- Event hooks ---------------------------------------------------------------------

func _on_building_completed(building: Node) -> void:
	if building is Node3D:
		play_sfx(&"building_complete", (building as Node3D).global_position)


func _on_unit_trained(_kind: StringName, pos: Vector3) -> void:
	play_sfx(&"training_done", pos)


func _on_spell_cast(spell_id: StringName, pos: Vector3) -> void:
	play_sfx(StringName("spell_%s" % spell_id), pos)


func _on_building_destroyed(building: Node) -> void:
	if building is Node3D:
		play_sfx(&"building_destroyed", (building as Node3D).global_position)


## Death cries: the shaman gets her own sound, everyone else shares one
## (throttled — a firestorm wiping a squad plays one cry, not twenty).
func _on_unit_died(unit: Node) -> void:
	if not (unit is Node3D):
		return
	var kind: StringName = unit.unit_kind() if unit.has_method("unit_kind") else &""
	if kind == &"shaman":
		play_sfx(&"shaman_death", (unit as Node3D).position)
	else:
		play_sfx(&"unit_death", (unit as Node3D).position, 200)


# --- Volume helpers (session-scoped, for the options UI) ------------------------------

static func bus_volume_percent(bus_name: String) -> float:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx == -1 or AudioServer.is_bus_mute(idx):
		return 0.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(idx)) * 100.0, 0.0, 100.0)


static func set_bus_volume_percent(bus_name: String, value: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	if value <= 0.0:
		AudioServer.set_bus_mute(idx, true)
		return
	AudioServer.set_bus_mute(idx, false)
	AudioServer.set_bus_volume_db(idx, linear_to_db(value / 100.0))
