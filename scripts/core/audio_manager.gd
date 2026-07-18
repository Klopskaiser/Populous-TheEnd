extends Node

## Autoload "AudioManager": bus setup (Music/Ambience/SFX/UI), file-based
## one-shot SFX/UI sounds and the music/ambience playlists. All lookups go
## through AssetLibrary — a missing file simply plays nothing (one warning per
## name), so the game works without any audio assets. Combat hit sounds stay
## in CombatAudio (with its own throttle); this manager covers everything else.

const SFX_POOL_SIZE: int = 8
const UI_POOL_SIZE: int = 4
const BUSES: Array[String] = ["Music", "Ambience", "SFX", "UI"]
## Max simultaneous looping emitters PER loop name (status effects like
## burning/panic); further requests wait and are promoted when a slot frees.
const LOOP_CAP_PER_NAME: int = 4

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
var _sfx_last_ms: Dictionary = {}      # sfx name -> last play (min-interval throttle)
var _stream_cache: Dictionary = {}     # rel prefix -> Array[AudioStream] (all variants)
## Looping emitters: name -> {"active": [{owner, player}], "waiting": [owner]}.
var _loops: Dictionary = {}


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
## Numbered variants (<name>_0.ogg, <name>_1.ogg, ...) may exist alongside or
## instead of the base file — one is picked at random per play.
## min_interval_ms > 0 throttles repeats of the SAME name (mass events like
## panic waves or death piles collapse into one sound per interval).
func play_sfx(name: StringName, pos: Vector3, min_interval_ms: int = 0) -> void:
	if min_interval_ms > 0:
		var now: int = Time.get_ticks_msec()
		if now - int(_sfx_last_ms.get(name, -min_interval_ms)) < min_interval_ms:
			return
		_sfx_last_ms[name] = now
	var streams: Array = _streams_for("audio/sfx/%s" % name)
	if streams.is_empty():
		return
	var player: AudioStreamPlayer3D = _sfx_pool[_sfx_index]
	_sfx_index = (_sfx_index + 1) % SFX_POOL_SIZE
	if player.playing:
		return   # pool exhausted -> drop (throttle)
	player.stream = streams[randi() % streams.size()]
	player.global_position = pos
	player.play()


## Plays assets/audio/ui/<name>.ogg non-positionally; silent when missing.
## Supports the same random numbered variants as play_sfx.
func play_ui(name: StringName) -> void:
	var streams: Array = _streams_for("audio/ui/%s" % name)
	if streams.is_empty():
		return
	var player: AudioStreamPlayer = _ui_pool[_ui_index]
	_ui_index = (_ui_index + 1) % UI_POOL_SIZE
	if player.playing:
		return
	player.stream = streams[randi() % streams.size()]
	player.play()


## True when any file (base or numbered variant) for this sfx name exists
## (callers with a procedural fallback — e.g. the siege shot's synth whoosh —
## decide with this).
func has_sfx(name: StringName) -> bool:
	return not _streams_for("audio/sfx/%s" % name).is_empty()


## All streams for a sound name: the base file (<rel>.ogg/.wav) plus every
## numbered variant (<rel>_0.., gap-free). Cached — assets are session-static.
func _streams_for(rel: String) -> Array:
	if _stream_cache.has(rel):
		return _stream_cache[rel]
	var streams: Array = []
	for ext in ["ogg", "wav"]:
		var base: AudioStream = AssetLibrary.stream("%s.%s" % [rel, ext])
		if base != null:
			streams.append(base)
			break
	streams.append_array(AssetLibrary.stream_variants(rel))
	_stream_cache[rel] = streams
	return streams


# --- Looping status sounds -------------------------------------------------------------

## Starts a positional loop (assets/audio/sfx/<name>.ogg, replayed on finish)
## that follows `owner` until stop_loop. At most LOOP_CAP_PER_NAME emitters
## play per name; extra owners wait and are promoted when a slot frees.
## Missing file = no-op. Callers pair every start with a stop; freed or
## world-removed owners are also cleaned up in _process.
func start_loop(name: StringName, owner: Node3D) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	var entry: Dictionary = _loops.get_or_add(name, {"active": [], "waiting": []})
	for a in entry.active:
		if a.owner == owner:
			return
	if owner in entry.waiting:
		return
	if entry.active.size() >= LOOP_CAP_PER_NAME:
		entry.waiting.append(owner)
		return
	_activate_loop(name, entry, owner)


func stop_loop(name: StringName, owner: Node3D) -> void:
	if not _loops.has(name):
		return
	var entry: Dictionary = _loops[name]
	entry.waiting.erase(owner)
	for i in range(entry.active.size()):
		if entry.active[i].owner == owner:
			_release_loop_slot(name, entry, i)
			return


func _activate_loop(name: StringName, entry: Dictionary, owner: Node3D) -> void:
	var streams: Array = _streams_for("audio/sfx/%s" % name)
	if streams.is_empty() and String(name).ends_with("_loop"):
		# No dedicated loop file: fall back to the one-shot of the same effect
		# (unit_burning_loop -> unit_burning) and repeat it — a status stays
		# audible for its whole duration even when only one-shots are provided.
		streams = _streams_for("audio/sfx/%s" % String(name).trim_suffix("_loop"))
	if streams.is_empty():
		return
	var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	player.max_distance = 40.0
	player.bus = "SFX"
	player.stream = streams[randi() % streams.size()]
	# Replay on finish -> loops regardless of the file's import loop flag.
	player.finished.connect(player.play)
	add_child(player)
	player.global_position = owner.global_position
	player.play()
	entry.active.append({"owner": owner, "player": player})


func _release_loop_slot(name: StringName, entry: Dictionary, index: int) -> void:
	(entry.active[index].player as AudioStreamPlayer3D).queue_free()
	entry.active.remove_at(index)
	while not entry.waiting.is_empty():
		var next = entry.waiting.pop_front()
		if next != null and is_instance_valid(next) and (next as Node3D).is_inside_tree():
			_activate_loop(name, entry, next)
			return


## Follows the owners and drops loops whose owner vanished (freed / left the
## scene tree). A handful of dictionary entries — negligible per frame.
func _process(_delta: float) -> void:
	for name in _loops:
		var entry: Dictionary = _loops[name]
		for i in range(entry.active.size() - 1, -1, -1):
			var a: Dictionary = entry.active[i]
			var owner = a.owner
			if owner == null or not is_instance_valid(owner) \
					or not (owner as Node3D).is_inside_tree():
				_release_loop_slot(name, entry, i)
			else:
				(a.player as AudioStreamPlayer3D).global_position = \
					(owner as Node3D).global_position


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
