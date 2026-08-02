class_name SpellAudio

## Sound naming and playback for spells (phase 10b).
##
## Every spell has TWO sounds with different owners and different moments:
##
##   spell_voice_<id>  the shaman's incantation, spoken when the cast STARTS
##                     (wind-up). Emitted as Events.spell_cast_started by the
##                     shaman and played by AudioManager at critical priority.
##   spell_<id>        the spell itself — thunder, impact, eruption, the ground
##                     grinding upwards — played when the effect ACTUALLY
##                     happens, which for most spells is seconds after the cast.
##
## Ownership rule: the entity that produces the effect plays its sound. The
## shaman only speaks the incantation. That keeps the wiring intact when a spell
## is later rebuilt — a new bolt class brings its own sound along.

## "spell_voice_fireball" — the shaman's incantation for this spell.
static func voice_name(id: StringName) -> StringName:
	return StringName("spell_voice_%s" % id)


## "spell_fireball" — the sound of the effect itself. `suffix` builds the
## related names of a spell (e.g. "_loop" for a tornado's howl).
static func effect_name(id: StringName, suffix: StringName = &"") -> StringName:
	if suffix == &"":
		return StringName("spell_%s" % id)
	return StringName("spell_%s%s" % [id, suffix])


## Plays an effect sound from `from`'s position in the world.
##
## The is_inside_tree() guard is mandatory, not defensive: spell effects live as
## projectiles under the UnitManager (UnitManager.register_projectile), and in
## headless tests that manager sits OUTSIDE the scene tree — where
## get_node_or_null("/root/...") is an error, not null. Never bypass it.
static func play_effect(from: Node, id: StringName, pos: Vector3,
		min_interval_ms: int = 0, suffix: StringName = &"") -> void:
	play_named(from, effect_name(id, suffix), pos, min_interval_ms)


## Same guard, for effect sounds that are not named after a spell id
## (lava_start, spell_volcano_erupt, ...).
static func play_named(from: Node, name: StringName, pos: Vector3,
		min_interval_ms: int = 0) -> void:
	var audio: Node = _audio(from)
	if audio == null:
		return
	audio.play_sfx(name, pos, min_interval_ms)


## Starts a positional loop that follows `owner` until it is freed or leaves the
## world (AudioManager._process releases the slot). Same tree guard.
static func start_loop(owner: Node3D, name: StringName) -> void:
	var audio: Node = _audio(owner)
	if audio == null:
		return
	audio.start_loop(name, owner)


static func _audio(from: Node) -> Node:
	if from == null or not is_instance_valid(from) or not from.is_inside_tree():
		return null
	return from.get_node_or_null("/root/AudioManager")
