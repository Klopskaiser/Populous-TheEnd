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
const MANA_BASE_RATE: float = Balance.MANA_BASE_RATE
## Float slack for the charge arithmetic.
const MANA_EPS: float = 0.0001

## Hard unit cap per tribe (phase 7i): no hut spawn / training beyond this, on
## top of the housing capacity — whichever limits first.
const MAX_UNITS: int = Balance.TRIBE_MAX_UNITS

## Population-growth control (phase 7i): governs how huts are auto-manned by
## nearby idle braves. NONE empties all huts (no growth); MINIMAL keeps one crew
## per hut; MAXIMUM fills huts to capacity. Manual manning works in every mode.
enum GrowthMode { NONE, MINIMAL, MAXIMUM }

## Per-tribe growth setting (player drives it via the sidebar; AI keeps the
## default). MAXIMUM = grow like before (huts fill up from nearby idle braves).
var growth_mode: GrowthMode = GrowthMode.MAXIMUM

## Military units (warrior/firewarrior/preacher) auto-crew nearby GROUND vehicles
## whose crew is short, and take over neutral (unmanned) ones — see
## CrewedVehicle._tick_auto_recrew. Default on; the AI keeps the default (player
## and AI share the same Tribe struct, so no AI code reads this). Airships are
## excluded; the shaman and braves are never pulled in.
var auto_recrew_vehicles: bool = true

## Tribe-wide hut-upgrade lock (phase 10f): while off, huts whose upgrade is due
## simply wait (the due "progress" holds at 100 %) instead of sending their crew
## out for wood. Default on, so the AI upgrades without needing any own logic.
## Player toggles it in the sidebar header, next to the growth control.
var upgrades_allowed: bool = true

## Per-tribe catapult cap: every workshop of the tribe stops producing once
## owned_catapult_count() reaches it. Player adjusts it in the sidebar
## (followers tab); AI keeps the default.
const MAX_CATAPULTS_DEFAULT: int = 3
const MAX_CATAPULTS_LIMIT: int = 20
var max_catapults: int = MAX_CATAPULTS_DEFAULT

## Analoge Pro-Stamm-Limits für die weiteren Fahrzeugtypen (eigene Stepper).
const MAX_FIRE_RAMS_DEFAULT: int = 3
const MAX_FIRE_RAMS_LIMIT: int = 20
var max_fire_rams: int = MAX_FIRE_RAMS_DEFAULT

const MAX_AIRSHIPS_DEFAULT: int = 2
const MAX_AIRSHIPS_LIMIT: int = 10
var max_airships: int = MAX_AIRSHIPS_DEFAULT

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
## Unpaid forester upkeep (phase 10c: there is no mana pool to draw it from,
## so it is a debt the following income settles before anything charges).
var _upkeep_debt: float = 0.0
## Income share (mana/s) already reserved by upkeep this tick; cleared in tick().
var _upkeep_rate_claimed: float = 0.0

## Out of the match (phase 10d): the tribe lost its last unit. Everything it
## still owned was razed by eliminate(); it takes no orders any more (UI and AI
## both bail out), produces nothing and charges no spells. The object itself
## stays around so the win evaluation and the statistics remain consistent.
## Irreversible.
var eliminated: bool = false

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


## Catapults counting toward the tribe's cap: every own siege engine, manned
## OR unmanned (enemy-captured ones leave `units` via convert_to_tribe and
## stop counting automatically).
func owned_catapult_count() -> int:
	var count: int = 0
	for unit in units:
		if is_instance_valid(unit) and unit is SiegeEngine \
				and unit.state != Unit.State.DEAD:
			count += 1
	return count


## Feuerrammen des Stamms (Zählung wie owned_catapult_count; über unit_kind,
## damit tribe.gd nicht von den Fahrzeugklassen abhängt).
func owned_fire_ram_count() -> int:
	var count: int = 0
	for unit in units:
		if is_instance_valid(unit) and unit.unit_kind() == &"fireram" \
				and unit.state != Unit.State.DEAD:
			count += 1
	return count


## Luftschiffe des Stamms (Zählung wie owned_catapult_count).
func owned_airship_count() -> int:
	var count: int = 0
	for unit in units:
		if is_instance_valid(unit) and unit.unit_kind() == &"airship" \
				and unit.state != Unit.State.DEAD:
			count += 1
	return count


## Applies a new growth mode (sidebar slider): manual crew overrides on huts
## only hold until the player moves the slider again — clear them all so every
## hut follows the new mode. Direct `growth_mode =` assignment (tests, setup)
## deliberately skips this.
func set_growth_mode(mode: GrowthMode) -> void:
	growth_mode = mode
	for building in buildings:
		if building.has_method("clear_manual_override"):
			building.clear_manual_override()


## Current mana income per second: purely the population base rate since
## phase 10c (praying at the reincarnation site was dropped as a feature).
## Forester upkeep is booked as a debt against this income (consume_mana) and
## is not netted here.
func mana_rate() -> float:
	return float(population()) * MANA_BASE_RATE


# --- Tick (mana economy) ------------------------------------------------------

## Mana is NOT banked (phase 10c): the income of this tick is spread over the
## active, not-yet-full spells right away, and whatever finds no taker is
## discarded. `mana` therefore only carries what a pending upkeep debt has not
## eaten yet — it is a flow, not a stock.
func tick(delta: float) -> void:
	# New round of upkeep claims: the foresters re-book their share every tick.
	_upkeep_rate_claimed = 0.0
	var income: float = mana_rate() * delta
	# Forester upkeep is a debt against the income, not against a pool: the
	# foresters have to be paid before anything charges (their intended cost).
	if _upkeep_debt > 0.0:
		var pay: float = minf(_upkeep_debt, income)
		_upkeep_debt -= pay
		income -= pay
	_distribute_mana(income)   # the remainder overflows and is lost
	_emit_mana()


# --- Spell charges (phase 6) ---------------------------------------------------

## Installs the spell set, cost-sorted (cheapest first) — that is the order the
## sidebar shows and it keeps the tab readable; the charging itself no longer
## depends on the order (every active spell is fed at once).
func set_spells(p_spells: Array[Spell]) -> void:
	spells = p_spells.duplicate()
	spells.sort_custom(func(a: Spell, b: Spell) -> bool:
		return a.charge_cost < b.charge_cost)


func get_spell(spell_id: StringName) -> Spell:
	for spell in spells:
		if spell.id == spell_id:
			return spell
	return null


## Total mana the charge stores can hold (sum over all spells). Informational
## since phase 10c (the shaman-kill bonus is derived from the victim tribe's
## production now, not from this).
func charge_capacity_mana() -> float:
	var total: float = 0.0
	for spell in spells:
		total += spell.charge_cost * float(spell.max_charges)
	return total


## Books forester worker upkeep (phase 7d). With mana no longer banked
## (phase 10c) there is no pool to take it from: the amount becomes a DEBT that
## the next ticks' income pays off before any spell charges. Returns the amount
## booked, which is always the full amount — the cost cannot be dodged, it can
## only delay the charging.
func consume_mana(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	_upkeep_debt += amount
	return amount


## How much of the current income (mana/s) is still free for upkeep this tick.
func free_upkeep_rate() -> float:
	return maxf(mana_rate() - _upkeep_rate_claimed, 0.0)


## Reserves a slice of the income for a continuous upkeep (forester workers)
## and returns what was granted — less than asked for when the tribe simply
## does not earn that much, or when other foresters already claimed it. The
## claim is per tick; Tribe.tick() clears it. Since phase 10c upkeep is paid
## from the INCOME, not from a hoard: a tribe cannot bank mana and then run
## more foresters than it can sustain.
func claim_upkeep_rate(rate: float) -> float:
	var granted: float = minf(maxf(rate, 0.0), free_upkeep_rate())
	_upkeep_rate_claimed += granted
	return granted


## One-time mana injection (the shaman-kill bonus), spread over the active
## spells exactly like ordinary income. Whatever finds no taker is lost.
func grant_bonus_mana(amount: float) -> void:
	if amount <= 0.0:
		return
	_distribute_mana(amount)
	_emit_mana()


## Spreads `amount` mana over ALL spells that want it (active and not full),
## in equal shares. Returns how much was actually placed — the rest had nowhere
## to go and is DISCARDED by the caller (no mana banking, user spec).
##
## Repeats in rounds because a share can overfill a nearly-complete spell; the
## leftover then goes to the others. Each round fills at least one spell to the
## brim, so the round count is bounded by the number of spells.
func _distribute_mana(amount: float) -> float:
	if amount <= 0.0 or spells.is_empty():
		return 0.0
	var before_charges: int = _total_charges()
	var remaining: float = amount
	var rounds: int = 0
	while remaining > MANA_EPS and rounds <= spells.size():
		rounds += 1
		var takers: int = 0
		for spell in spells:
			if spell.wants_mana():
				takers += 1
		if takers == 0:
			break
		var share: float = remaining / float(takers)
		var used: float = 0.0
		for spell in spells:
			if spell.wants_mana():
				used += spell.add_charge_mana(share)
		if used <= MANA_EPS:
			break
		remaining -= used
	if _total_charges() != before_charges:
		_emit_spell_charges()
	return amount - remaining


func _total_charges() -> int:
	var total: int = 0
	for spell in spells:
		total += spell.charges
	return total


## Switches a spell's charging on or off (right-click on its button). Stored
## charges and the partial fill are untouched — only the income stops.
func set_spell_active(spell_id: StringName, value: bool) -> void:
	var spell: Spell = get_spell(spell_id)
	if spell == null or spell.active == value:
		return
	spell.active = value
	_emit_spell_charges()


func active_spell_count() -> int:
	var count: int = 0
	for spell in spells:
		if spell.wants_mana():
			count += 1
	return count


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


# --- Elimination (phase 10d) ------------------------------------------------------

## The tribe is out: everything it still owns is razed and its magic goes dead.
## Called exactly once by GameState.check_defeats on the transition to "defeated".
## Buildings and vehicles go down so no orphaned base keeps standing on the map;
## the Tribe object itself lives on (see `eliminated`).
func eliminate() -> void:
	if eliminated:
		return
	eliminated = true
	# destroy() calls back into remove_building -> iterate a copy.
	for building in buildings.duplicate():
		if is_instance_valid(building) and building.health > 0:
			building.destroy()
	# Crewed vehicles (catapult, fire ram, airship) are units, not buildings —
	# with nobody left to man them they are scrap too.
	for unit in units.duplicate():
		if is_instance_valid(unit) and unit is CrewedVehicle \
				and unit.state != Unit.State.DEAD:
			unit.take_damage(unit.max_health)
	# No more magic: stored charges and the half-filled charge bars are void.
	for spell in spells:
		spell.charges = 0
		spell.charge_mana = 0.0
		spell.charge_progress = 0.0
	mana = 0.0
	_upkeep_debt = 0.0
	_emit_mana()
	_emit_spell_charges()
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
