class_name Spell extends RefCounted

## Base class for the shaman's spells. Charge system like the original game:
## the tribe's mana is converted automatically into stored charges (see
## Tribe._convert_mana_to_charges, driven from Tribe.tick); casting consumes
## one stored charge, there is no separate cooldown — the recharge time
## follows from the mana rate. Subclasses implement execute() against the
## injected SpellContext so every effect is headless-testable.

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
## 0..1 partial fill of the NEXT charge (drives the sidebar pips); maintained
## by the tribe's charging tick for the spell currently being served.
var charge_progress: float = 0.0


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
	return true


func is_full() -> bool:
	return charges >= max_charges


## One fresh set of the five phase-6 spells — charges are per-tribe state, so
## every tribe gets its own instances (Tribe.set_spells).
static func create_default_set() -> Array[Spell]:
	return [
		FireballSpell.new(),
		LightningSpell.new(),
		SwarmSpell.new(),
		LandbridgeSpell.new(),
		TornadoSpell.new(),
	]
