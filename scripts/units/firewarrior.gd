class_name Firewarrior extends Unit

## Ranged combat unit trained at the fire temple (Feuertempel). Throws fireballs
## from medium range; brawls like a brave in melee. Phase 5a only carries its
## stats and its sprite silhouette (helmet + fireballs in the hands) — the
## ranged fireball attack and knockback come in phase 5c.


func _init() -> void:
	max_health = 60
	health = 60
	speed = 4.0


func unit_kind() -> StringName:
	return &"firewarrior"


## A combat unit: brawls in melee in phase 5b (ranged fireballs come in 5c).
func _is_combatant() -> bool:
	return true
