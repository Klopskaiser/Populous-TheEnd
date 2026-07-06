class_name CombatAudio extends Node

## Procedural combat hit sounds — no external asset files (overview par. 7).
##
## Generates a small set of AudioStreamWAV variants per attack kind (short
## filtered-noise bursts with distinct length/timbre per kind) and plays a
## random one per Events.combat_hit through a pooled set of positional
## players. Throttled (global min interval + fixed pool) so mass battles
## cannot overload the audio bus.

const VARIANTS: int = 3
const POOL_SIZE: int = 12
## Global minimum gap between two hit sounds (throttle).
const MIN_INTERVAL_MS: int = 45
const MIX_RATE: int = 22050

const KINDS: Array[StringName] = [&"punch", &"kick", &"shove", &"fireball"]

var _sounds: Dictionary = {}   # kind -> Array[AudioStreamWAV]
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_index: int = 0
var _last_play_ms: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 4242
	for kind in KINDS:
		var variants: Array = []
		for v in range(VARIANTS):
			variants.append(_make_stream(kind, v))
		_sounds[kind] = variants
	for i in range(POOL_SIZE):
		var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		player.max_distance = 60.0
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
	var player: AudioStreamPlayer3D = _pool[_pool_index]
	_pool_index = (_pool_index + 1) % POOL_SIZE
	if player.playing:
		return   # pool exhausted -> drop the sound (throttle)
	player.stream = variants[_rng.randi_range(0, variants.size() - 1)]
	player.global_position = pos
	player.play()
	_last_play_ms = now


## Sample generation is static + deterministic per (kind, variant) so headless
## tests can validate the data. Each kind has its own duration, smoothing
## (crude low-pass -> timbre) and attack time.
static func generate_samples(kind: StringName, variant: int) -> PackedByteArray:
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
		&"fireball":   # bright crackle
			dur = 0.2
			smooth = 0.25
			attack = 0.002
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


func _make_stream(kind: StringName, variant: int) -> AudioStreamWAV:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = generate_samples(kind, variant)
	return wav
