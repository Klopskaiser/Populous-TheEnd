class_name Shaman extends Unit

## The tribe's single spell caster (exactly one per tribe). Casts the spell
## chosen by the player/AI at a target position, walking into cast range
## first; the charge is consumed only when the cast actually releases
## (Spell.cast — a failed effect keeps the charge). On death the killer's
## tribe receives a one-time mana bonus and the tribe's reincarnation site
## starts the respawn timer.

const HP: int = 240                        # 4x brave life (60)
const SHAMAN_MELEE_STRENGTH: float = 2.0   # 2x brave melee damage
## Wind-up of the cast animation before the effect fires. The release range
## is per spell (Spell.cast_range).
const CAST_TIME: float = 0.6
## Killing an enemy shaman grants the killer's tribe bonus mana worth this
## share of its total charge capacity, paid straight into spell charges.
const KILL_BONUS_SHARE: float = 0.15

var pending_spell: Spell = null
var pending_target: Vector3 = Vector3.ZERO
var pending_ctx: SpellContext = null
var _cast_timer: float = 0.0
## True while standing in range playing the cast wind-up (vs. walking there).
var _casting: bool = false


func _init() -> void:
	max_health = HP
	health = HP
	speed = 4.0


func unit_kind() -> StringName:
	return &"shaman"


func melee_strength() -> float:
	return SHAMAN_MELEE_STRENGTH


## The shaman shrugs off the swarm's panic effect (not its damage).
func is_panic_immune() -> bool:
	return true


# --- Casting ---------------------------------------------------------------------

## Accepts a cast order (from TribeCommands.cast_spell). Interrupts movement
## and combat; returns false while the shaman is beyond control (rolling etc.).
func order_cast(spell: Spell, target: Vector3, ctx: SpellContext) -> bool:
	if not can_take_orders() or spell == null:
		return false
	_end_attack()
	waypoint_queue.clear()
	_clear_path()
	pending_spell = spell
	pending_target = target
	pending_ctx = ctx
	_cast_timer = CAST_TIME
	_casting = false
	_set_state(State.CAST)
	return true


## Movement orders cancel a pending cast (the charge is kept).
func order_move(target: Vector3, queue_up: bool = false) -> void:
	if state == State.CAST:
		_cancel_cast()
	super.order_move(target, queue_up)


func _cancel_cast() -> void:
	pending_spell = null
	pending_ctx = null
	_casting = false


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
	if _flat_dist(position, pending_target) > pending_spell.cast_range:
		_casting = false
		_cast_timer = CAST_TIME
		_approach(pending_target, delta)
		return
	if _has_path():
		_clear_path()
	if not _casting:
		_casting = true
		_apply_animation(true)   # restart the cast wind-up at frame 0
	_face_point(pending_target)
	_cast_timer -= delta
	if _cast_timer > 0.0:
		return
	var spell: Spell = pending_spell
	var target: Vector3 = pending_target
	var ctx: SpellContext = pending_ctx
	_cancel_cast()
	spell.cast(tribe, target, ctx)
	_set_state(State.IDLE)


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


## Pays the one-time mana boost to the killer's tribe (15% of ITS total charge
## capacity, converted straight into charges). No bonus without a (living)
## attacker — e.g. drowning after a self-inflicted roll.
func _grant_kill_bonus() -> void:
	var killer = last_attacker
	if killer == null or not is_instance_valid(killer):
		return
	var killer_tribe: Tribe = killer.tribe
	if killer_tribe == null or killer_tribe == tribe:
		return
	killer_tribe.grant_bonus_mana(killer_tribe.charge_capacity_mana() * KILL_BONUS_SHARE)
