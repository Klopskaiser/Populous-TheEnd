class_name Warrior extends Unit

## Melee combat unit trained at the warrior camp (Kaserne). Tougher and much
## harder-hitting than a brave; melee only. Phase 5a only carries its stats and
## its sprite silhouette (shield + sword) — the full melee behaviour (2.5x punch
## strength, no shoving, aggro) is wired up in phase 5b.

const MELEE_STRENGTH: float = Balance.WARRIOR_MELEE_STRENGTH
## The warrior never shoves (2026-09-07): he punches and kicks, nothing else.
const WARRIOR_SHOVE_CHANCE: float = Balance.WARRIOR_SHOVE_CHANCE
const WARRIOR_KICK_CHANCE: float = Balance.WARRIOR_KICK_CHANCE


func _init() -> void:
	max_health = Balance.WARRIOR_HP
	health = max_health
	speed = Balance.WARRIOR_SPEED


func unit_kind() -> StringName:
	return &"warrior"


func _is_combatant() -> bool:
	return true


func melee_strength() -> float:
	return MELEE_STRENGTH


func _shove_chance() -> float:
	return WARRIOR_SHOVE_CHANCE


func _kick_chance() -> float:
	return WARRIOR_KICK_CHANCE
