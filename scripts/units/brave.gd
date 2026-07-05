class_name Brave extends Unit

## Basic follower unit. GATHER/PRAY/BUILD behaviour comes in phase 3 — for now
## this only defines the type, its stats and the sprite silhouette key.

func _init() -> void:
	max_health = 60
	health = 60
	speed = 4.0


func unit_kind() -> StringName:
	return &"brave"
