class_name Preacher extends Unit

## Converter unit trained at the temple (Tempel). Converts nearby enemy units to
## its own tribe (cast). Slightly tougher than a brave; melee otherwise. Phase 5a
## only carries its stats and its sprite silhouette (hood + gown) — the
## conversion behaviour, priest duel and firewarrior reset come in phase 5c.


func _init() -> void:
	max_health = 75
	health = 75
	speed = 4.0


func unit_kind() -> StringName:
	return &"preacher"
