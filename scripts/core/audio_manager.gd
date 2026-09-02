extends Node

## Autoload "AudioManager": bus setup (Music/Ambience/SFX/UI), file-based
## one-shot SFX/UI sounds and the music/ambience playlists. All lookups go
## through AssetLibrary — a missing file simply plays nothing (one warning per
## name), so the game works without any audio assets. Combat hit sounds stay
## in CombatAudio (with its own throttle); this manager covers everything else.
##
## Slots are handed out by AudioSlots.pick_slot (phase 10b): prio 1 = spell
## incantations + shaman death, prio 2 = siege engine / airship deaths, prio 3 =
## everything else. A prio 3 sound is dropped before an important one is cut
## off, and a saturated pool never drops a sound while a slot is still idle.

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
## Per-slot allocator state (see AudioSlots): priority of the sound currently on
## the slot and when it started. Only meaningful while the slot is playing.
var _sfx_prio: PackedInt32Array = PackedInt32Array()
var _sfx_start_ms: PackedInt64Array = PackedInt64Array()
var _ui_prio: PackedInt32Array = PackedInt32Array()
var _ui_start_ms: PackedInt64Array = PackedInt64Array()
## Scratch buffers for the "is this slot busy" snapshot pick_slot works on
## (reused so a play call allocates nothing).
var _sfx_busy: Array = []
var _ui_busy: Array = []
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
	_sfx_prio.resize(SFX_POOL_SIZE)
	_sfx_start_ms.resize(SFX_POOL_SIZE)
	_ui_prio.resize(UI_POOL_SIZE)
	_ui_start_ms.resize(UI_POOL_SIZE)
	_sfx_prio.fill(AudioSlots.PRIO_NORMAL)
	_ui_prio.fill(AudioSlots.PRIO_NORMAL)
	_sfx_busy.resize(SFX_POOL_SIZE)
	_ui_busy.resize(UI_POOL_SIZE)
	for i in range(SFX_POOL_SIZE):
		var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		player.max_distance = AudioSlots.SFX_MAX_DISTANCE
		player.unit_size = AudioSlots.AUDIO_UNIT_SIZE
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
	# Gespeicherte Reglerstaende anwenden — hier, nicht in _enter_tree: die
	# Busse muessen stehen (AudioSettings ueberspringt fehlende Busse still).
	AudioSettings.apply_all()
	_music_tracks = AssetLibrary.stream_folder("audio/music")
	_ambience_tracks = AssetLibrary.stream_folder("audio/ambience")
	_start_playlists()
	var events: Node = get_node_or_null("/root/Events")
	if events != null:
		events.building_completed.connect(_on_building_completed)
		events.unit_trained.connect(_on_unit_trained)
		events.spell_cast_started.connect(_on_spell_cast_started)
		events.building_destroyed.connect(_on_building_destroyed)
		events.unit_died.connect(_on_unit_died)


# --- One-shot sounds -----------------------------------------------------------------

## Plays assets/audio/sfx/<name>.ogg positionally; silent when missing.
## Numbered variants (<name>_0.ogg, <name>_1.ogg, ...) may exist alongside or
## instead of the base file — one is picked at random per play.
## min_interval_ms > 0 throttles repeats of the SAME name (mass events like
## panic waves or death piles collapse into one sound per interval).
## priority: PRIO_AUTO derives it from the name (AudioSlots.default_priority);
## pass one explicitly to override.
func play_sfx(name: StringName, pos: Vector3, min_interval_ms: int = 0,
		priority: int = AudioSlots.PRIO_AUTO) -> void:
	# Resolve the file first: a missing sound must neither steal a slot nor burn
	# the throttle window.
	var streams: Array = _streams_for("audio/sfx/%s" % name)
	if streams.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	if min_interval_ms > 0 \
			and now - int(_sfx_last_ms.get(name, -min_interval_ms)) < min_interval_ms:
		return
	var want: int = priority if priority != AudioSlots.PRIO_AUTO \
		else AudioSlots.default_priority(name)
	var idx: int = AudioSlots.pick_slot(_busy_snapshot(_sfx_pool, _sfx_busy),
		_sfx_prio, _sfx_start_ms, want, _sfx_index, now)
	if idx == -1:
		return
	_sfx_index = (idx + 1) % SFX_POOL_SIZE
	_sfx_prio[idx] = want
	_sfx_start_ms[idx] = now
	# Only a sound that actually starts consumes its throttle window (before
	# phase 10b a dropped sound silenced the next interval as well).
	_sfx_last_ms[name] = now
	var player: AudioStreamPlayer3D = _sfx_pool[idx]
	player.stream = streams[randi() % streams.size()]
	player.global_position = pos
	player.play()


## Plays assets/audio/ui/<name>.ogg non-positionally; silent when missing.
## Supports the same random numbered variants as play_sfx. UI feedback is always
## prio 3 — it competes only with itself (own pool).
func play_ui(name: StringName) -> void:
	var streams: Array = _streams_for("audio/ui/%s" % name)
	if streams.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var idx: int = AudioSlots.pick_slot(_busy_snapshot(_ui_pool, _ui_busy),
		_ui_prio, _ui_start_ms, AudioSlots.PRIO_NORMAL, _ui_index, now)
	if idx == -1:
		return
	_ui_index = (idx + 1) % UI_POOL_SIZE
	_ui_prio[idx] = AudioSlots.PRIO_NORMAL
	_ui_start_ms[idx] = now
	var player: AudioStreamPlayer = _ui_pool[idx]
	player.stream = streams[randi() % streams.size()]
	player.play()


## Busy flags of a pool for AudioSlots.pick_slot. Fills a preallocated scratch
## array — play calls happen dozens of times per second in a battle.
func _busy_snapshot(pool: Array, scratch: Array) -> Array:
	for i in range(pool.size()):
		scratch[i] = pool[i].playing
	return scratch


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
	player.max_distance = AudioSlots.LOOP_MAX_DISTANCE
	player.unit_size = AudioSlots.AUDIO_UNIT_SIZE
	player.bus = "SFX"
	player.stream = streams[AudioSlots.next_variant(streams.size(), -1)]
	# Replay on finish -> loops regardless of the file's import loop flag, and
	# re-rolls the variant on every repetition (see _on_loop_finished).
	player.finished.connect(_on_loop_finished.bind(player, streams))
	add_child(player)
	player.global_position = owner.global_position
	player.play()
	entry.active.append({"owner": owner, "player": player})


## Every repetition picks a fresh variant: a loop with several files
## (spell_tornado_loop_0/_1) must not play the same one for the whole effect
## (user report). The current index comes from the stream itself — the variant
## list is cached and a handful of entries long, so the lookup costs nothing.
##
## NOTE: this hangs off `finished`, so a loop file imported WITH the loop flag
## set never gets here (the stream loops internally and stays on one variant).
## Ship loop files without import looping; the repeat is this manager's job.
func _on_loop_finished(player: AudioStreamPlayer3D, streams: Array) -> void:
	if not is_instance_valid(player):
		return
	if streams.size() > 1:
		player.stream = streams[AudioSlots.next_variant(
			streams.size(), streams.find(player.stream))]
	player.play()


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


## The shaman's incantation, at the START of the wind-up and at HER position
## (phase 10b). The sound of the spell itself is played by whatever entity
## creates the effect, when the effect actually happens — see SpellAudio.
## Critical priority: the incantation must never lose its slot to battle noise.
func _on_spell_cast_started(spell_id: StringName, pos: Vector3) -> void:
	play_sfx(SpellAudio.voice_name(spell_id), pos, 0, AudioSlots.PRIO_CRITICAL)


func _on_building_destroyed(building: Node) -> void:
	if building is Node3D:
		play_sfx(&"building_destroyed", (building as Node3D).global_position)


## Death cries: each unit names its own key (shaman cry, vehicle burn/burst,
## airship crash, or the shared man-sized cry). Throttled — a firestorm wiping
## a squad plays one cry per key, not twenty. Empty key = silent.
func _on_unit_died(unit: Node) -> void:
	if not (unit is Node3D):
		return
	var key: StringName = unit.death_sfx_key() if unit.has_method("death_sfx_key") \
		else &"unit_death"
	if key == &"":
		return
	play_sfx(key, (unit as Node3D).global_position, 200)
