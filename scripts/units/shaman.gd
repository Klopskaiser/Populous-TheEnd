class_name Shaman extends Unit

## The tribe's single spell caster (exactly one per tribe). Casts the spell
## chosen by the player/AI at a target position, walking into cast range
## first; the charge is consumed only when the cast actually releases
## (Spell.cast — a failed effect keeps the charge). On death the killer's
## tribe receives a one-time mana bonus and the tribe's reincarnation site
## starts the respawn timer.

const HP: int = Balance.SHAMAN_HP                        # 4x brave life
const SHAMAN_MELEE_STRENGTH: float = Balance.SHAMAN_MELEE_STRENGTH
## Wind-up of the cast animation before the effect fires. The release range
## is per spell (Spell.cast_range).
##
## Anteil der Reichweite, auf den sie sich beim Anmarsch heranarbeitet — knapp
## innerhalb, damit ein Schritt Ungenauigkeit den Cast nicht wieder verhindert.
const APPROACH_RANGE_FRACTION: float = 0.85
const CAST_TIME: float = Balance.SHAMAN_CAST_TIME
## Killing an enemy shaman grants the killer's tribe bonus mana worth this
## share of its total charge capacity, paid straight into spell charges.
const KILL_BONUS_SHARE: float = Balance.SHAMAN_KILL_MANA_MINUTE_SHARE

var pending_spell: Spell = null
var pending_target: Vector3 = Vector3.ZERO
var pending_ctx: SpellContext = null
## Optional locked target (enemy device): while set, pending_target is refreshed
## to its live position each cast tick so a moving airship/vehicle is still hit.
var pending_target_unit: Unit = null
var _cast_timer: float = 0.0
## Latched once the incantation for the CURRENT cast order was spoken. Needed
## because _casting flips back and forth every tick while she hovers on the edge
## of cast range — without the latch the incantation would stutter.
var _voice_played: bool = false
## True while standing in range playing the cast wind-up (vs. walking there).
var _casting: bool = false


func _init() -> void:
	max_health = HP
	health = HP
	speed = Balance.SHAMAN_SPEED


func unit_kind() -> StringName:
	return &"shaman"


func death_sfx_key() -> StringName:
	return &"shaman_death"


func melee_strength() -> float:
	return SHAMAN_MELEE_STRENGTH


## The shaman shrugs off the swarm's panic effect (not its damage).
func is_panic_immune() -> bool:
	return true


# --- Casting ---------------------------------------------------------------------

## Accepts a cast order (from TribeCommands.cast_spell). Interrupts movement
## and combat; returns false while the shaman is beyond control (rolling etc.).
func order_cast(spell: Spell, target: Vector3, ctx: SpellContext,
		target_unit: Unit = null) -> bool:
	if spell == null:
		return false
	_voice_played = false
	# Locked device target: aim at its current position (kept fresh below while
	# walking into range).
	if target_unit != null and is_instance_valid(target_unit) \
			and target_unit.state != State.DEAD:
		target = target_unit.position
	else:
		target_unit = null
	# Stationed in a watchtower (phase 7h): cast straight from the tower with
	# +3 m range instead of walking there — she never leaves the tower. Out of
	# range = the cast fails silently (charge kept), she stays put.
	if garrison_housed and garrison_target != null and is_instance_valid(garrison_target):
		var origin: Vector3 = garrison_target.center_world()
		if _flat_dist(origin, target) > spell.cast_range + Watchtower.TOWER_RANGE_BONUS:
			return false
		# No wind-up here, so incantation and effect coincide — she still speaks
		# it, and its critical priority guarantees it a slot.
		_emit_spell_voice(spell)
		if spell.cast(tribe, target, ctx):
			_emit_spell_cast(spell, target)
			return true
		return false
	# Riding an airship deck: cast straight from the deck with +3 m range —
	# but only while the ship is STANDING (like all deck combat). Out of range
	# or mid-flight = the cast fails silently (charge kept).
	if rides_airborne():
		var ship = siege_engine
		if ship.state == State.MOVE:
			return false
		if _flat_dist(ship.position, target) > spell.cast_range + Balance.AIRSHIP_RANGE_BONUS:
			return false
		_emit_spell_voice(spell)
		if spell.cast(tribe, target, ctx):
			_emit_spell_cast(spell, target)
			return true
		return false
	if not can_take_orders():
		return false
	_end_attack()
	waypoint_queue.clear()
	_clear_path()
	pending_spell = spell
	pending_target = target
	pending_target_unit = target_unit
	pending_ctx = ctx
	_cast_timer = CAST_TIME
	_casting = false
	_set_state(State.CAST)
	return true


## Once the incantation itself has STARTED (in range, wind-up running), only
## death or a tornado may break it (phase 10c, user spec): shoves, knock-overs,
## fireball throws and lifts bounce off her. She still takes the damage — she
## is immune to the interrupt, not to the hit. While she is still WALKING into
## range (`_casting` false) she is an ordinary unit.
func cast_locked() -> bool:
	return state == State.CAST and _casting


## Movement orders cancel a pending cast (the charge is kept).
func order_move(target: Vector3, queue_up: bool = false, aggressive: bool = false) -> void:
	if state == State.CAST:
		_cancel_cast()
	super.order_move(target, queue_up, aggressive)


func _cancel_cast() -> void:
	pending_spell = null
	pending_ctx = null
	pending_target_unit = null
	_casting = false
	_voice_played = false


## Rolls, throws and fights interrupt a pending cast for good (the charge is
## kept). Without this the stale pending_spell survived the tumble (phase 7f
## roll hardening).
func _on_combat_interrupt() -> void:
	if pending_spell != null:
		_cancel_cast()


func _tick_state(delta: float) -> void:
	if state == State.CAST:
		_tick_cast(delta)
		return
	super._tick_state(delta)


## Walks into the spell's cast range of the target, then plays the wind-up
## and releases it. The state ends in IDLE either way; a failed execute keeps
## the charge (Spell.cast).
func _tick_cast(delta: float) -> void:
	if pending_spell == null:
		_set_state(State.IDLE)
		return
	# Track a locked device target's live position (a moving airship/vehicle).
	if pending_target_unit != null:
		if is_instance_valid(pending_target_unit) \
				and pending_target_unit.state != State.DEAD:
			pending_target = pending_target_unit.position
		else:
			pending_target_unit = null
	if _flat_dist(position, pending_target) > pending_spell.cast_range:
		_casting = false
		_cast_timer = CAST_TIME
		# NICHT auf das Ziel selbst zulaufen: steht es auf unbegehbarem Grund —
		# im Grundriss eines Gebaeudes oder auf einem Vulkanberg — scheitert der
		# A* und sie blieb fuer immer stehen, obwohl der Zauber es erreicht
		# (Nutzerreport). Sie laeuft bis knapp INNERHALB der Reichweite.
		_approach(stand_off_point(position, pending_target,
			pending_spell.cast_range * APPROACH_RANGE_FRACTION), delta)
		return
	if _has_path():
		_clear_path()
	if not _casting:
		_casting = true
		_apply_animation(true)   # restart the cast wind-up at frame 0
		if not _voice_played:
			_emit_spell_voice(pending_spell)
	_face_point(pending_target)
	_cast_timer -= delta
	if _cast_timer > 0.0:
		return
	var spell: Spell = pending_spell
	var target: Vector3 = pending_target
	var ctx: SpellContext = pending_ctx
	_cancel_cast()
	if spell.effect_delay > 0.0 and ctx != null and ctx.unit_manager != null 			and spell.charges > 0:
		# Schwerer Zauber (Phase 10k-Nachtrag): die Ladung ist mit dem Wind-up weg,
		# der EFFEKT tritt spaeter ein. Die Schamanin ist sofort wieder frei — ein
		# Traeger auf der Projektilliste zuendet ihn.
		spell.consume_charge()
		var carrier: Spell.DelayedEffect = Spell.DelayedEffect.new()
		carrier.setup(spell, tribe, target, ctx, spell.effect_delay)
		ctx.unit_manager.register_projectile(carrier)
		_emit_spell_cast(spell, target)
	elif spell.cast(tribe, target, ctx):
		_emit_spell_cast(spell, target)
	_set_state(State.IDLE)


## Announces a successful cast (charge consumed) on the Events bus. Carries no
## sound since phase 10b — the effect's own sound comes from the entity that
## produces it, when it actually happens.
func _emit_spell_cast(spell: Spell, target: Vector3) -> void:
	if not is_inside_tree():
		return
	var events: Node = get_node_or_null("/root/Events")
	if events != null:
		events.spell_cast.emit(spell.id, target)


## The incantation at the START of the cast, at HER position (AudioManager plays
## spell_voice_<id>). The latch is set unconditionally — also outside the scene
## tree — so the "spoken once per cast order" rule holds in headless tests too.
func _emit_spell_voice(spell: Spell) -> void:
	if spell == null:
		return
	_voice_played = true
	if not is_inside_tree():
		return
	var events: Node = get_node_or_null("/root/Events")
	if events != null:
		events.spell_cast_started.emit(spell.id, position)


## Walk frames while moving into range; the cast animation only during the
## wind-up.
func _anim_base() -> StringName:
	if state == State.CAST and not _casting:
		return &"walk"
	return super._anim_base()


# --- Death (kill bonus) -------------------------------------------------------------

func _die() -> void:
	_grant_kill_bonus()
	_cancel_cast()
	super._die()


## Pays the one-time mana boost to the killer's tribe: 10 % of the MINUTE
## production of the tribe that just lost its shaman, spread over the killer's
## active charge rates (phase 10c — it used to be 15 % of the killer's own
## charge capacity, which said nothing about the value of the kill). Killing
## the shaman of a big tribe is worth accordingly more. No bonus without a
## (living) attacker — e.g. drowning after a self-inflicted roll.
func _grant_kill_bonus() -> void:
	var killer = last_attacker
	if killer == null or not is_instance_valid(killer):
		return
	var killer_tribe: Tribe = killer.tribe
	if killer_tribe == null or killer_tribe == tribe or tribe == null:
		return
	killer_tribe.grant_bonus_mana(tribe.mana_rate() * 60.0 * KILL_BONUS_SHARE)
