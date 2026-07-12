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

## Hard unit cap per tribe (phase 7i): no hut spawn / training beyond this, on
## top of the housing capacity — whichever limits first.
const MAX_UNITS: int = 1500

## Population-growth control (phase 7i): governs how huts are auto-manned by
## nearby idle braves. NONE empties all huts (no growth); MINIMAL keeps one crew
## per hut; MAXIMUM fills huts to capacity. Manual manning works in every mode.
enum GrowthMode { NONE, MINIMAL, MAXIMUM }

## Per-tribe growth setting (player drives it via the sidebar; AI keeps the
## default). MAXIMUM = grow like before (huts fill up from nearby idle braves).
var growth_mode: GrowthMode = GrowthMode.MAXIMUM

var id: int = 0
var color: Color = Color.WHITE
var mana: float = 0.0
var units: Array[Unit] = []
var buildings: Array[Building] = []
## The tribe's single spell caster; kept in sync by add_unit/remove_unit
## (null while she is dead — the reincarnation site respawns her).
var shaman: Unit = null
## The tribe's preachers, kept in sync by add_unit/remove_unit (phase 8.2):
## the firewarrior's priest-priority scan iterates THESE few units instead of
## an uncapped radius query over the whole battle (measured hotspot).
var preachers: Array[Unit] = []
## Spell set (charge system), installed via set_spells (cost-sorted).
var spells: Array[Spell] = []
## Round-robin pointer into `spells`: the pointed spell is the next to
## receive a charge once enough mana has accumulated.
var _charge_index: int = 0

var _events: Node = null
var _events_resolved: bool = false


func _init(p_id: int = 0, p_color: Color = Color.WHITE) -> void:
	id = p_id
	color = p_color


# --- Derived values ---------------------------------------------------------

func population() -> int:
	return units.size()


## At or above the hard unit cap (phase 7i).
func at_unit_cap() -> bool:
	return units.size() >= MAX_UNITS


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


## Current mana income per second (phase 7i display): the same term the tick
## adds, i.e. population base rate + praying-brave bonus. Forester upkeep drains
## the pool separately (consume_mana) and is not netted here.
func mana_rate() -> float:
	return float(population()) * MANA_BASE_RATE + float(praying_braves()) * MANA_PRAY_BONUS


# --- Tick (mana economy) ------------------------------------------------------

func tick(delta: float) -> void:
	mana += (float(population()) * MANA_BASE_RATE
		+ float(praying_braves()) * MANA_PRAY_BONUS) * delta
	_convert_mana_to_charges()
	_emit_mana()


# --- Spell charges (phase 6) ---------------------------------------------------

## Installs the spell set, cost-sorted so the round-robin serves the cheapest
## spell first within each round.
func set_spells(p_spells: Array[Spell]) -> void:
	spells = p_spells.duplicate()
	spells.sort_custom(func(a: Spell, b: Spell) -> bool:
		return a.charge_cost < b.charge_cost)
	_charge_index = 0


func get_spell(spell_id: StringName) -> Spell:
	for spell in spells:
		if spell.id == spell_id:
			return spell
	return null


## Total mana the charge stores can hold (sum over all spells); basis of the
## 15% shaman-kill bonus.
func charge_capacity_mana() -> float:
	var total: float = 0.0
	for spell in spells:
		total += spell.charge_cost * float(spell.max_charges)
	return total


## Spends up to `amount` mana from the pool (forester worker upkeep, phase 7d);
## returns how much was actually taken. Competes with the charge conversion —
## running foresters slow charge build-up (their intended cost).
func consume_mana(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var take: float = minf(amount, mana)
	mana -= take
	if take > 0.0:
		_emit_mana()
	return take


## One-time mana injection (e.g. the shaman-kill bonus), converted into spell
## charges immediately through the regular charging path.
func grant_bonus_mana(amount: float) -> void:
	if amount <= 0.0:
		return
	mana += amount
	_convert_mana_to_charges()
	_emit_mana()


## Converts available mana into stored charges: round-robin over the
## (cost-sorted) spells, one charge per turn. A spell that is not affordable
## yet blocks its turn until the mana accumulated (fairness — cheap spells
## cannot starve expensive ones). All spells full -> mana keeps accumulating.
func _convert_mana_to_charges() -> void:
	if spells.is_empty():
		return
	var converted: bool = false
	while true:
		var skipped: int = 0
		while skipped < spells.size() and spells[_charge_index].is_full():
			_charge_index = (_charge_index + 1) % spells.size()
			skipped += 1
		if skipped >= spells.size():
			break   # all full
		var spell: Spell = spells[_charge_index]
		if mana < spell.charge_cost:
			break   # this spell is served next, once the mana is there
		mana -= spell.charge_cost
		spell.charges += 1
		converted = true
		_charge_index = (_charge_index + 1) % spells.size()
	_update_charge_progress()
	if converted:
		_emit_spell_charges()


## The pips show one charge filling at a time: the round-robin spell currently
## waiting for mana; every other spell shows no partial fill.
func _update_charge_progress() -> void:
	for spell in spells:
		spell.charge_progress = 0.0
	var current: Spell = spells[_charge_index]
	if not current.is_full():
		current.charge_progress = clampf(mana / current.charge_cost, 0.0, 1.0)


# --- Unit / building registry ---------------------------------------------------

func add_unit(unit: Unit) -> void:
	if unit in units:
		return
	units.append(unit)
	unit.tribe = self
	if unit.unit_kind() == &"shaman":
		shaman = unit
	elif unit.unit_kind() == &"preacher" and unit not in preachers:
		preachers.append(unit)
	_emit_population()


func remove_unit(unit: Unit) -> void:
	units.erase(unit)
	if shaman == unit:
		shaman = null
	if not preachers.is_empty():
		preachers.erase(unit)
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


func _emit_spell_charges() -> void:
	var bus: Node = _bus()
	if bus != null:
		bus.spell_charges_changed.emit(id)
