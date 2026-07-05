class_name Tribe extends RefCounted

## One tribe (player or AI). Player and AI are identical Tribe instances —
## all mutations go through TribeCommands (or the tribe's own methods below).
## There is NO tribe wood stock: wood exists only physically as piles on the
## ground (WoodPileManager) and gets delivered to construction sites.
##
## Pure data class (no Node dependency) so it is headless-testable. Signals go
## through the Events autoload; the lookup is guarded so tests without
## autoloads work.

## Mana per second per population member.
const MANA_BASE_RATE: float = 0.1
## Extra mana per second per praying brave.
const MANA_PRAY_BONUS: float = 0.5

var id: int = 0
var color: Color = Color.WHITE
var mana: float = 0.0
var units: Array[Unit] = []
var buildings: Array[Building] = []
var shaman: Unit = null   # set in phase 5

var _events: Node = null
var _events_resolved: bool = false


func _init(p_id: int = 0, p_color: Color = Color.WHITE) -> void:
	id = p_id
	color = p_color


# --- Derived values ---------------------------------------------------------

func population() -> int:
	return units.size()


## Sum of the housing capacity of all (finished) buildings.
func housing_capacity() -> int:
	var total: int = 0
	for building in buildings:
		total += building.housing_capacity()
	return total


func praying_braves() -> int:
	var count: int = 0
	for unit in units:
		if unit.is_praying():
			count += 1
	return count


# --- Tick (mana economy) ------------------------------------------------------

func tick(delta: float) -> void:
	mana += (float(population()) * MANA_BASE_RATE
		+ float(praying_braves()) * MANA_PRAY_BONUS) * delta
	_emit_mana()


# --- Unit / building registry ---------------------------------------------------

func add_unit(unit: Unit) -> void:
	if unit in units:
		return
	units.append(unit)
	unit.tribe = self
	_emit_population()


func remove_unit(unit: Unit) -> void:
	units.erase(unit)
	_emit_population()


func add_building(building: Building) -> void:
	if building in buildings:
		return
	buildings.append(building)
	building.tribe = self
	_emit_population()


func remove_building(building: Building) -> void:
	buildings.erase(building)
	_emit_population()


## Called by buildings when their capacity changes (construction finished).
func notify_housing_changed() -> void:
	_emit_population()


# --- Events bus (guarded: absent in headless tests) --------------------------------

func _bus() -> Node:
	if not _events_resolved:
		_events_resolved = true
		var loop: MainLoop = Engine.get_main_loop()
		if loop is SceneTree:
			_events = (loop as SceneTree).root.get_node_or_null("Events")
	return _events


func _emit_mana() -> void:
	var bus: Node = _bus()
	if bus != null:
		bus.mana_changed.emit(id, mana)


func _emit_population() -> void:
	var bus: Node = _bus()
	if bus != null:
		bus.population_changed.emit(id, population(), housing_capacity())
