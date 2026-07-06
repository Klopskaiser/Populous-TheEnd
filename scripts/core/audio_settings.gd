class_name AudioSettings extends RefCounted

## Master-bus volume helpers, shared by the main-menu options and the in-game
## pause menu (session-scoped — nothing is persisted).


static func master_volume_percent() -> float:
	var master: int = AudioServer.get_bus_index("Master")
	if AudioServer.is_bus_mute(master):
		return 0.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(master)) * 100.0, 0.0, 100.0)


## Sets the master volume from a 0..100 slider value; 0 mutes the bus.
static func set_master_volume_percent(value: float) -> void:
	var master: int = AudioServer.get_bus_index("Master")
	if value <= 0.0:
		AudioServer.set_bus_mute(master, true)
		return
	AudioServer.set_bus_mute(master, false)
	AudioServer.set_bus_volume_db(master, linear_to_db(value / 100.0))
