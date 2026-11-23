class_name TribeStats extends RefCounted

## Kill statistics per tribe (user spec 2026-11-23) and the rows the end screen
## shows. The counters live on Tribe (kills_by_golems, kills_other, units_lost,
## peak_population) so they travel with the save game; this class only books a
## death and formats the table.
##
## WHO KILLED: every Unit remembers the tribe that harmed it last and whether a
## golem did it (Unit.note_harm — set by take_damage with an attacker, by
## ignite/scorch with a source, and by the tornado, swarm and volcano). A death
## by something without an owner (lava, drowning, a fall, burning) counts for
## that last harmer; a unit nobody ever harmed simply died (a loss without a
## killer). A kill of an own unit (own firestorm, own tornado) is no kill.
##
## Vehicles (catapult, fire ram, airship) are devices: neither a kill nor a loss.
## Golems are living beings here — killing an enemy golem is a kill.

const TRIBE_NAMES: Array[String] = ["Blau", "Rot", "Gelb", "Grün"]


## Books the death of `unit` (called by UnitManager when its died signal fires).
static func record_death(unit: Unit, tribes: Array[Tribe]) -> void:
	if unit == null or unit is CrewedVehicle:
		return
	var victim: int = unit.tribe_id
	if victim >= 0 and victim < tribes.size():
		tribes[victim].units_lost += 1
	var killer: int = unit.last_harm_tribe
	if killer < 0 or killer >= tribes.size() or killer == victim:
		return
	if unit.last_harm_by_golem:
		tribes[killer].kills_by_golems += 1
	else:
		tribes[killer].kills_other += 1


static func tribe_name(id: int) -> String:
	if id >= 0 and id < TRIBE_NAMES.size():
		return TRIBE_NAMES[id]
	return "Stamm %d" % id


## One row per tribe for the end screen: name, colour and the numbers.
## `alive` = the followers left at the end (population(), vehicles and golems
## excluded) — together with the peak and the losses it tells the course of the
## match without the double counting a "units made" total would have (a trained
## warrior is a NEW unit made from a brave, a converted unit changes sides).
static func rows(tribes: Array[Tribe], player_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for tribe in tribes:
		var label: String = tribe_name(tribe.id)
		if tribe.id == player_id:
			label += " (du)"
		elif tribe.ai_personality_name != "":
			label += " (%s)" % tribe.ai_personality_name
		out.append({
			"id": tribe.id,
			"name": label,
			"color": tribe.color,
			"alive": tribe.population(),
			"peak": tribe.peak_population,
			"lost": tribe.units_lost,
			"kills_golem": tribe.kills_by_golems,
			"kills_other": tribe.kills_other,
			"eliminated": tribe.eliminated,
		})
	return out


## "mm:ss" (or "h:mm:ss") of a match time in seconds.
static func format_time(seconds: float) -> String:
	var total: int = int(maxf(seconds, 0.0))
	@warning_ignore("integer_division")
	var h: int = total / 3600
	@warning_ignore("integer_division")
	var m: int = (total % 3600) / 60
	var s: int = total % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, s]
	return "%d:%02d" % [m, s]
