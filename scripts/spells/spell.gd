class_name Spell extends RefCounted

## Base class for the shaman's spells. Charge system: the tribe's mana income
## is spread over ALL active, not-yet-full spells at once (see
## Tribe._distribute_mana, driven from Tribe.tick); casting consumes one stored
## charge, there is no separate cooldown. Because every spell gets the same
## share but they cost differently, cheap spells come back far sooner than
## expensive ones — that is the whole balance of the system. Subclasses
## implement execute() against the injected SpellContext so every effect is
## headless-testable.

var id: StringName = &"spell"
var display_name_de: String = "Zauber"
## Mana converted per stored charge (start values, balancing in phase 8).
var charge_cost: float = 50.0
var max_charges: int = 4
## Range (metres) from which the shaman can release this spell at its target;
## she walks closer first when the target lies beyond it. The targeting UI
## shows this radius around her while the spell is armed.
var cast_range: float = 9.0
var charges: int = 0
## Whether the tribe pays mana into this spell. Toggled with a right-click on
## its button; every spell starts ON. Switching one OFF frees its share of the
## income for the others — the stored charges stay castable and the partial
## fill below is KEPT, so re-enabling resumes where it left off.
var active: bool = true
## Mana already paid toward the NEXT charge. Survives deactivation.
var charge_mana: float = 0.0
## 0..1 partial fill of the next charge (drives the sidebar bar and pips),
## derived from charge_mana whenever the tribe feeds this spell.
var charge_progress: float = 0.0


## True while the tribe should pay mana into this spell: switched on and not
## already at max_charges. A full spell costs nothing (user spec).
func wants_mana() -> bool:
	return active and not is_full()


## Adds up to `amount` mana, capped by what this spell can still store, and
## converts every full charge_cost into a charge. Returns the mana actually
## taken — the caller hands the rest to the other spells.
func add_charge_mana(amount: float) -> float:
	var room: float = float(max_charges - charges) * charge_cost - charge_mana
	var take: float = minf(amount, maxf(room, 0.0))
	if take <= 0.0:
		return 0.0
	charge_mana += take
	while charge_mana >= charge_cost and not is_full():
		charge_mana -= charge_cost
		charges += 1
	if is_full():
		charge_mana = 0.0
	_sync_charge_progress()
	return take


func _sync_charge_progress() -> void:
	charge_progress = 0.0 if is_full() \
		else clampf(charge_mana / maxf(charge_cost, 0.001), 0.0, 1.0)


## Spell effect. Returns false when the cast cannot happen (e.g. lightning
## without a target in range) — the charge is then kept.
func execute(_tribe: Tribe, _target: Vector3, _ctx: SpellContext) -> bool:
	return false


## Runs execute() and consumes exactly one stored charge on success.
func cast(tribe: Tribe, target: Vector3, ctx: SpellContext) -> bool:
	if charges <= 0:
		return false
	if not execute(tribe, target, ctx):
		return false
	charges -= 1
	# Dropping out of "full" reopens the partial fill display.
	_sync_charge_progress()
	return true


func is_full() -> bool:
	return charges >= max_charges


## One fresh set of all twelve spells (phase 6 + 7c + 10k) — charges are per-tribe
## state, so every tribe gets its own instances (Tribe.set_spells).
static func create_default_set() -> Array[Spell]:
	return [
		FireballSpell.new(),
		LightningSpell.new(),
		SwarmSpell.new(),
		LandbridgeSpell.new(),
		TornadoSpell.new(),
		EarthquakeSpell.new(),
		VolcanoSpell.new(),
		FirestormSpell.new(),
		FlattenSpell.new(),
		SinkSpell.new(),
		SupertornadoSpell.new(),
		HypnosisSpell.new(),
	]
