class_name AIGolems extends RefCounted

## KI und Golems (Nutzervorgabe 2026-11-21: "arbeite die Golemmechanik auch fuer die KI ein, wie sie
## mit Golems umgeht und dass sie auch selber welche einsetzt"). Gehoert zu genau einem AIController.
##
## EIGENE GOLEMS
##   * Die KI hat alle drei Golemzauber (Spell.create_default_set). Sie beschwoert, wenn ihre Schamanin
##     vor einem Feindgebaeude steht, in einem grossen Gefecht (AI_GOLEM_SUMMON_MIN_ENEMIES Feinde im
##     Zauberradius) oder gegen einen feindlichen Golem — hoechstens AI_GOLEM_MAX eigene zugleich
##     (wants_summon). Welcher: summon_order — daheim zuerst der Genesisgolem (keine Lebenszeit, waechst
##     mit den eigenen Braves), draussen zuerst der Daemonengolem (waechst mit Kills).
##   * Der Genesisgolem bleibt als Hauswache daheim: er verteidigt, marschiert aber nicht mit der Welle
##     (marches_with_wave). Die beiden anderen ziehen mit der Welle.
##   * Ab GOLEM_SIT_MIN_HEIGHT setzt sich ein KI-Golem, wenn genug Feinde in Reichweite seiner Sitzangriffe
##     stehen, und steht wieder auf, wenn eine Weile keiner mehr darin ist (sit_decision) — ueber dieselben
##     Befehle wie die Taste V des Spielers (TribeCommands.order_golem_sit / order_golem_stand).
##   * In der Armee zaehlt ein Golem nach seinem Leben (power_of), nicht als ein Mann.
##
## FEINDLICHE GOLEMS (im AIController)
##   * Blitz auf den Golem (doppelter Schaden), sonst Feuerregen (voller Brandschaden), wenn keine eigenen
##     Einheiten darunter stehen.
##   * In der Bedrohung zaehlt er nach seinem Leben (power_of); die Feuerkrieger der Verteidigung nehmen ihn
##     gezielt aufs Korn, Milizbraves werden nie gegen einen Golem geschickt.

var _ai = null   # AIController (untyped: the two classes refer to each other)
## Instance id -> KI-Takte, die ein sitzender Golem schon ohne Feind in Reichweite sitzt.
var _calm_ticks: Dictionary = {}


func _init(p_ai = null) -> void:
	_ai = p_ai


# --- Pure decisions (headless-testable) -----------------------------------------------

## How many ordinary fighters a unit counts as: a golem by its health (at least one), anyone else one.
static func power_of(u: Unit) -> int:
	if u is Golem:
		return maxi(1, roundi(float(u.health) / Balance.AI_GOLEM_POWER_HP))
	return 1


## Should the AI summon a golem now? `own` = its living golems.
static func wants_summon(own: int, enemies_near: int, enemy_golem_near: bool,
		building_near: bool) -> bool:
	if own >= Balance.AI_GOLEM_MAX:
		return false
	return building_near or enemy_golem_near or enemies_near >= Balance.AI_GOLEM_SUMMON_MIN_ENEMIES


## The golem spells in the order the AI tries them (a spell without a charge falls through).
static func summon_order(at_home: bool) -> Array[StringName]:
	if at_home:
		return [&"genesis_golem", &"demon_golem", &"golem"]
	return [&"demon_golem", &"golem", &"genesis_golem"]


## +1: sit down now, -1: stand up now, 0: leave her. `calm` = ticks seated with nothing in reach.
static func sit_decision(sit_locked: bool, can_sit: bool, foes_in_reach: int, calm: int) -> int:
	if not sit_locked:
		return 1 if can_sit and foes_in_reach >= Balance.AI_GOLEM_SIT_MIN_ENEMIES else 0
	if foes_in_reach > 0:
		return 0
	return -1 if calm >= Balance.AI_GOLEM_STAND_TICKS else 0


## Does this golem march with the attack wave? The genesis golem guards the village.
static func marches_with_wave(u: Unit) -> bool:
	return not (u is GenesisGolem)


## The biggest enemy golem among `units` (most health), null if none.
static func biggest_golem(units: Array[Unit]) -> Golem:
	var best: Golem = null
	for u in units:
		if u is Golem and u.state != Unit.State.DEAD and (best == null or u.health > best.health):
			best = u as Golem
	return best


# --- Tick -------------------------------------------------------------------------------

## Sitting and standing of the AI's own golems (one pass per AI tick).
func tick(golems: Array[Unit]) -> void:
	if _ai == null or _ai.commands == null:
		return
	var seen: Dictionary = {}
	for u in golems:
		if not is_instance_valid(u) or u.state == Unit.State.DEAD or not (u is Golem):
			continue
		var g: Golem = u as Golem
		var id: int = g.get_instance_id()
		seen[id] = true
		var locked: bool = g.is_sit_locked()
		var foes: int = foes_in_sit_reach(g)
		var calm: int = int(_calm_ticks.get(id, 0))
		calm = calm + 1 if locked and foes == 0 else 0
		_calm_ticks[id] = calm
		var units: Array[Unit] = [g]
		match sit_decision(locked, g.can_sit(), foes, calm):
			1:
				_ai.commands.order_golem_sit(units)
			-1:
				if _ai.commands.order_golem_stand(units) > 0:
					_calm_ticks[id] = 0
	for id in _calm_ticks.keys():
		if not seen.has(id):
			_calm_ticks.erase(id)


## Enemy ground units her sit attacks could reach (the reach of GolemSitCombat around her).
func foes_in_sit_reach(g: Golem) -> int:
	if _ai == null or _ai.unit_manager == null:
		return 0
	var n: int = 0
	for u in _ai.unit_manager.get_units_in_radius(g.position, g.sit_reach_radius()):
		if u.tribe_id == g.tribe_id or u.state == Unit.State.DEAD or u.doomed:
			continue
		if not u.is_targetable() or u.is_airborne() or u is CrewedVehicle:
			continue
		n += 1
	return n
