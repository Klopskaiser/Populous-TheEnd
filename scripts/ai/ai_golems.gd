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
##   * Der Genesisgolem ist vor allem Hauswache (seit 2026-11-23 nicht mehr nur): er verteidigt, zieht aber
##     auch mit der Welle, solange daheim keine Bedrohung ist, er gesund genug ist und kein Holz ausliefert
##     (joins_wave). Untaetig faellt er Holz nahe der Basis und bringt es zu Baustellen, die welches brauchen
##     (_tick_genesis, GenesisGolem.order_deliver_wood). Die beiden anderen ziehen immer mit der Welle.
##   * Rueckzug (2026-11-23): faellt ein Golem fern der Basis unter AI_GOLEM_RETREAT_HP_SHARE, marschiert er
##     heim und ist von allen Marschbefehlen ausgenommen, bis er AI_GOLEM_RETURN_HP_SHARE wieder hat
##     (retreat_decision, is_retreating). Er heilt unterwegs (jeder Golem heilt staendig).
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
## Instance id -> true: golems on their way home to heal (2026-11-23).
var _retreating: Dictionary = {}
## A threat at home this tick (set in tick, read by joins_wave in the same AI tick).
var _threat: bool = false
## The AI is attacking and its wave has a target this tick (set in tick).
var _wave_has_target: bool = false
## Grove centre -> AI tick until which no Genesis golem is sent there (its order ran dry at once).
var _banned_groves: Dictionary = {}
## Instance id -> centre of the grove he was last sent to while that order still counts as fresh.
var _last_grove: Dictionary = {}
## Diagnostics: how often the AI sent a golem home / a Genesis golem to the trees / to a site.
var dbg_retreats: int = 0
var dbg_genesis_harvests: int = 0
var dbg_genesis_deliveries: int = 0
## Instance id -> why _tick_genesis left him as he is this tick (diagnostics, tests/diag_ai_match.gd).
var dbg_genesis_why: Dictionary = {}


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


## +1: send her home now, -1: she has healed and is back, 0: no change. `share` = health / max health,
## `far` = she stands beyond the defence radius of the base.
static func retreat_decision(share: float, retreating: bool, far: bool) -> int:
	if retreating:
		return -1 if share >= Balance.AI_GOLEM_RETURN_HP_SHARE else 0
	return 1 if share < Balance.AI_GOLEM_RETREAT_HP_SHARE and far else 0


## Is this golem on its way home to heal? It takes no march orders meanwhile.
func is_retreating(u: Unit) -> bool:
	return is_instance_valid(u) and _retreating.has(u.get_instance_id())


## Does this golem march with the attack wave (and the spell raid)? Every golem that is not retreating —
## the Genesis golem, the village guard, only while there is no threat at home, he is healthy
## (AI_GENESIS_ATTACK_HP_SHARE) and not carrying wood to a site (user spec 2026-11-23).
func joins_wave(u: Unit) -> bool:
	if not is_instance_valid(u) or is_retreating(u):
		return false
	if not (u is GenesisGolem):
		return true
	var g: GenesisGolem = u as GenesisGolem
	if _threat or (g.deliver_target != null and is_instance_valid(g.deliver_target)):
		return false
	return float(g.health) >= float(g.max_health) * Balance.AI_GENESIS_ATTACK_HP_SHARE


## The biggest enemy golem among `units` (most health), null if none.
static func biggest_golem(units: Array[Unit]) -> Golem:
	var best: Golem = null
	for u in units:
		if u is Golem and u.state != Unit.State.DEAD and (best == null or u.health > best.health):
			best = u as Golem
	return best


# --- Tick -------------------------------------------------------------------------------

## The AI's own golems, one pass per AI tick: retreat, sitting and standing, the Genesis golem's wood.
## `cache` = the AIController's TickCache (null: no wood work), `threat` = its threat this tick.
func tick(golems: Array[Unit], cache = null, threat: Dictionary = {}) -> void:
	if _ai == null or _ai.commands == null:
		return
	_threat = not threat.is_empty()
	# Measured 2026-11-23: an AI that had won stayed in ATTACK without a target, the wave gave no
	# orders and its Genesis golems stood idle for good. The wave leads him only while it has a target.
	_wave_has_target = _ai.state == AIState.State.ATTACK \
		and _ai._attack_target_position() != Vector3.INF
	var seen: Dictionary = {}
	for u in golems:
		if not is_instance_valid(u) or u.state == Unit.State.DEAD or not (u is Golem):
			continue
		var g: Golem = u as Golem
		var id: int = g.get_instance_id()
		seen[id] = true
		if _tick_retreat(g):
			continue
		if g is GenesisGolem and cache != null:
			_tick_genesis(g as GenesisGolem, cache)
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
	for id in _retreating.keys():
		if not seen.has(id):
			_retreating.erase(id)
	for id in _last_grove.keys():
		if not seen.has(id):
			_last_grove.erase(id)
	for centre in _banned_groves.keys():
		if int(_banned_groves[centre]) <= _ai._tick_count:
			_banned_groves.erase(centre)


## The base (the AI's anchor cell in the world), INF without one.
func _home() -> Vector3:
	if _ai.nav_grid == null:
		return Vector3.INF
	return _ai.nav_grid.cell_to_world(_ai.base_anchor)


static func _one(u: Unit) -> Array[Unit]:
	var out: Array[Unit] = [u]
	return out


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Retreat (2026-11-23): true while she is on her way home or healing there (nothing else is ordered).
func _tick_retreat(g: Golem) -> bool:
	var id: int = g.get_instance_id()
	var home: Vector3 = _home()
	if home == Vector3.INF:
		return false
	var share: float = float(g.health) / float(maxi(g.max_health, 1))
	var far: bool = _flat_dist(g.position, home) > _ai._defend_radius()
	match retreat_decision(share, _retreating.has(id), far):
		1:
			_retreating[id] = true
			dbg_retreats += 1
		-1:
			_retreating.erase(id)
			return false
		0:
			if not _retreating.has(id):
				return false
	if g.is_sit_locked():
		if not g.is_switching_stance():
			_ai.commands.order_golem_stand(_one(g))
		return true
	# Home, without fighting on the way (a golem on a plain march does not strike back). Ordered once:
	# while she is still marching there it is not repeated; at home she stays and heals.
	var marching_home: bool = g.state == Unit.State.MOVE and not g.move_aggressive
	if far and not marching_home:
		_ai.commands.order_move(_one(g), home, false, false)
	return true


## The Genesis golem's wood (user spec 2026-11-23): idle, he fells trees near the base; carrying
## enough, he takes his wood to the nearest site that still lacks some. Not under a threat at home
## (he defends), not while the wave leads him, not while he fights, sits or is already on a delivery.
func _tick_genesis(g: GenesisGolem, cache) -> void:
	var why: Dictionary = dbg_genesis_why
	var gid: int = g.get_instance_id()
	if _threat:
		why[gid] = "Bedrohung"
		return
	if g.is_sit_locked() or g.state == Unit.State.ATTACK:
		why[gid] = "kaempft/sitzt"
		return
	if _wave_has_target and joins_wave(g):
		why[gid] = "Welle"
		return   # the wave leads him (without a target it gives no orders: then he works)
	if g.deliver_target != null and is_instance_valid(g.deliver_target):
		why[gid] = "liefert"
		return
	var carried: int = g.total_wood()
	if carried > 0:
		var site = _wood_site_for(g, cache)
		if site != null:
			var gap: int = _ai._site_unfunded(site)
			if (carried >= Balance.AI_GENESIS_DELIVER_MIN or carried >= gap or not g.is_harvesting()) \
					and g.order_deliver_wood(site):
				dbg_genesis_deliveries += 1
				return
	if g.is_harvesting() or g.state != Unit.State.IDLE:
		why[gid] = "faellt" if g.is_harvesting() else "unterwegs"
		return
	var home: Vector3 = _home()
	if home == Vector3.INF:
		return
	# Measured 2026-11-23: an order on a grove with nothing he can fell ended at once and was given again
	# every AI tick (1228 orders, no wood). A grove whose order ran dry right away is banned for a while,
	# and only groves with a standing tree on his island are tried.
	var id: int = g.get_instance_id()
	if _last_grove.has(id):
		_banned_groves[_last_grove[id]] = _ai._tick_count + Balance.AI_GENESIS_GROVE_BAN_TICKS
		_last_grove.erase(id)
	for grove in _ai._grove_candidates_cached(home):
		var centre: Vector2 = (grove as Rect2).get_center()
		if int(_banned_groves.get(centre, -1)) > _ai._tick_count:
			continue
		if not _grove_has_tree_for(g, grove):
			continue
		if _ai.commands.order_chop_area(_one(g), grove) > 0:
			dbg_genesis_harvests += 1
			_last_grove[id] = centre
			why[gid] = "Auftrag"
		else:
			why[gid] = "Auftrag abgelehnt"
		return
	why[gid] = "kein Waldstueck"


## Does the grove hold a standing tree he could reach (on his island)?
func _grove_has_tree_for(g: GenesisGolem, grove: Rect2) -> bool:
	if _ai.tree_manager == null:
		return false
	for tree in _ai.tree_manager.area_trees(grove, PackedVector2Array()):
		if is_instance_valid(tree) and not tree.felled_flag \
				and (_ai.nav_grid == null or _ai.nav_grid.same_island(g.position, tree.position)):
			return true
	return false


## The nearest own construction site on his island that still lacks wood (after what is on its way).
func _wood_site_for(g: GenesisGolem, cache) -> Building:
	var best: Building = null
	var best_d: float = INF
	for site in cache.sites:
		if not is_instance_valid(site) or site.demolishing or site.health <= 0:
			continue
		if _ai._site_unfunded(site) <= 0:
			continue
		var door: Vector3 = site.delivery_point()
		if _ai.nav_grid != null and not _ai.nav_grid.same_island(g.position, door):
			continue
		var d: float = _flat_dist(g.position, door)
		if d < best_d:
			best_d = d
			best = site
	return best


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
