class_name CombatAudio extends Node

## Combat hit sounds, file-based with a procedural fallback.
##
## Per attack kind, numbered variants from assets/audio/sfx/combat/ are used
## when present (<kind>_0.ogg, <kind>_1.ogg, ...); otherwise a small set of
## AudioStreamWAV variants is generated (short filtered-noise bursts with
## distinct length/timbre per kind). A random variant plays per
## Events.combat_hit through a pooled set of positional players. Throttled
## (global min interval + fixed pool) so mass battles cannot overload the
## audio bus.
##
## Why this stays a subsystem of its own instead of moving into AudioManager:
## it owns a procedural synthesizer the manager has no use for, and it has by
## far the highest event density in the game. With its own pool, combat hits
## never compete for the slots AudioManager reserves for spell incantations and
## death cries. It does share the allocator (AudioSlots.pick_slot) so that a hit
## is no longer dropped while eleven of twelve slots sit idle — but with
## same-priority stealing disabled, so the pool size alone caps mass battles.

const VARIANTS: int = 3
const POOL_SIZE: int = 12
## Global minimum gap between two hit sounds (throttle).
const MIN_INTERVAL_MS: int = 45
const MIX_RATE: int = 22050

## throw = fireball launch, preach = preacher channeling — one variant each is
## plenty (user request); the melee strikes keep three. preach_enemy is the same
## chant sung by an ENEMY preacher: a foreign sermon has to be audible as such
## (user request), and it stays in this pool so it keeps the synthesized fallback
## the own chant has — otherwise enemy preachers would be silent without assets.
const KINDS: Array[StringName] = [
	&"punch", &"kick", &"shove", &"fireball", &"throw", &"preach", &"preach_enemy"]
const SINGLE_VARIANT_KINDS: Array[StringName] = [
	&"fireball", &"throw", &"preach", &"preach_enemy"]

var _sounds: Dictionary = {}   # kind -> Array[AudioStreamWAV]
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_index: int = 0
var _last_play_ms: int = 0
## Allocator state per slot (see AudioSlots) + reused busy-flag scratch.
var _pool_prio: PackedInt32Array = PackedInt32Array()
var _pool_start_ms: PackedInt64Array = PackedInt64Array()
var _pool_busy: Array = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 4242
	for kind in KINDS:
		var variants: Array = AssetLibrary.stream_variants("audio/sfx/combat/%s" % kind)
		if variants.is_empty():
			var count: int = 1 if kind in SINGLE_VARIANT_KINDS else VARIANTS
			for v in range(count):
				variants.append(_make_stream(kind, v))
		_sounds[kind] = variants
	_pool_prio.resize(POOL_SIZE)
	_pool_prio.fill(AudioSlots.PRIO_NORMAL)
	_pool_start_ms.resize(POOL_SIZE)
	_pool_busy.resize(POOL_SIZE)
	for i in range(POOL_SIZE):
		var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		player.max_distance = 60.0
		if AudioServer.get_bus_index("SFX") != -1:
			player.bus = "SFX"
		add_child(player)
		_pool.append(player)
	var events: Node = get_node_or_null("/root/Events")
	if events != null:
		events.combat_hit.connect(_on_combat_hit)


func _on_combat_hit(kind: StringName, pos: Vector3) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_play_ms < MIN_INTERVAL_MS:
		return
	var variants: Array = _sounds.get(kind, _sounds.get(&"punch", []))
	if variants.is_empty():
		return
	for i in range(POOL_SIZE):
		_pool_busy[i] = _pool[i].playing
	# steal_same_prio_ms = 0: hits never cut each other off — a full pool simply
	# drops the sound, which is the throttle that keeps mass battles sane.
	var idx: int = AudioSlots.pick_slot(_pool_busy, _pool_prio, _pool_start_ms,
		AudioSlots.PRIO_NORMAL, _pool_index, now, 0)
	if idx == -1:
		return   # pool exhausted -> drop the sound (throttle)
	_pool_index = (idx + 1) % POOL_SIZE
	_pool_start_ms[idx] = now
	var player: AudioStreamPlayer3D = _pool[idx]
	player.stream = variants[_rng.randi_range(0, variants.size() - 1)]
	player.global_position = pos
	player.play()
	_last_play_ms = now


## Sample generation is static + deterministic per (kind, variant) so headless
## tests can validate the data. Each kind has its own duration, smoothing
## (crude low-pass -> timbre) and attack time; "preach" is tonal (soft chant)
## instead of noise-based.
static func generate_samples(kind: StringName, variant: int) -> PackedByteArray:
	if kind == &"preach" or kind == &"preach_enemy":
		return _generate_chant(variant, kind == &"preach_enemy")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(kind) + variant * 7919
	var dur: float
	var smooth: float
	var attack: float
	match kind:
		&"kick":       # deeper, slightly longer thud
			dur = 0.13
			smooth = 0.78
			attack = 0.004
		&"shove":      # softer whoosh with a slow attack
			dur = 0.16
			smooth = 0.55
			attack = 0.03
		&"fireball":   # bright crackle (impact)
			dur = 0.2
			smooth = 0.25
			attack = 0.002
		&"throw":      # airy whoosh (fireball launch)
			dur = 0.18
			smooth = 0.45
			attack = 0.05
		_:             # punch: short mid thud
			dur = 0.09
			smooth = 0.68
			attack = 0.003
	var count: int = int(dur * float(MIX_RATE))
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(count * 2)
	var prev: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var noise: float = rng.randf_range(-1.0, 1.0)
		prev = lerpf(noise, prev, smooth)   # crude one-pole low-pass
		var env: float = minf(t / attack, 1.0) * exp(-t * (5.0 / dur))
		var sample: int = int(clampf(prev * env, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, sample)
	return bytes


## Soft tonal chant for the channeling preacher: low sine with slow vibrato
## and a gentle swell, ~0.6 s.
##
## `enemy` = the same chant from an ENEMY preacher. Same length and envelope, so
## the rhythm of the sermon reads identically, but clearly darker: a much lower
## fundamental, wider and faster vibrato and a dissonant partial instead of the
## clean octave. Both variants share this function on purpose — a second
## generator would drift apart from the own chant over time.
static func _generate_chant(variant: int, enemy: bool = false) -> PackedByteArray:
	var dur: float = 0.6
	var base_hz: float = 175.0 + float(variant) * 12.0
	var vibrato_hz: float = 5.0
	var vibrato_depth: float = 6.0
	var partial: float = 2.0            # octave above the fundamental
	if enemy:
		base_hz = 118.0 + float(variant) * 9.0
		vibrato_hz = 7.5
		vibrato_depth = 11.0
		partial = 1.5                   # fifth -> hollow, unsettling
	var count: int = int(dur * float(MIX_RATE))
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(count * 2)
	var phase: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var vibrato: float = sin(t * TAU * vibrato_hz) * vibrato_depth
		phase += TAU * (base_hz + vibrato) / float(MIX_RATE)
		var tone: float = sin(phase) * 0.7 + sin(phase * partial) * 0.2
		var env: float = sin(clampf(t / dur, 0.0, 1.0) * PI)   # swell in and out
		var sample: int = int(clampf(tone * env * 0.5, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, sample)
	return bytes


func _make_stream(kind: StringName, variant: int) -> AudioStreamWAV:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = generate_samples(kind, variant)
	return wav
