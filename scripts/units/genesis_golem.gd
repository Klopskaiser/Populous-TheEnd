class_name GenesisGolem extends Golem

## Genesisgolem (Zauber 15, Nutzervorgabe 2026-11-17): der dritte Golem. Er IST
## ein Golem (`is Golem`): Angriffe, Haltung, Zielwahl, Immunitaeten, Konter und
## Stimme kommen von dort. Eigenes Modell seit 2026-11-17: die Figur mit den rosa
## Schuhen in Shorts und Top (models/units/golem_genesis.glb), in der Statur des
## Golems (10 % niedriger als breit skaliert, Golem.model_scale). Die Werte stehen
## in Balance (GENESIS_GOLEM_*, dort auch die ganze Vorgabe). Anders als die
## anderen beiden:
##
##  * Er waechst NICHT durch Kills (sie werden nur gezaehlt), sondern durch die
##    BRAVES seines Stammes: jeder Brave, den eine Huette erzeugt, ist ein Punkt
##    Erfahrung, geteilt durch die Zahl der lebenden Genesisgolems des Stammes
##    (credit_brave_to_tribe). 9 Stufen (GENESIS_GOLEM_STAGE_BRAVES), jede +4 m
##    (2026-11-17, vorher 5), +40 Leben, +2 Leben/s. Start 5 m und 1000 Leben,
##    keine Lebenszeit. Aggroreichweite: die halbe der anderen Golems.
##  * Startwerte: Schaden des frisch beschworenen Daemonengolems, Reichweite,
##    Flaechen und Ziele des frischen Golems. Mit der Groesse steigen Schaden,
##    Flaechen, Reichweite, Zielzahl und Trampelschaden wie beim Daemonengolem,
##    aber nur 2/3 so stark (combat_factor()). Was am KOERPER haengt — Modell,
##    Koerperkreis (Trampeln, Sprung), Tempo, Takt, Drehrate, Haltungswechsel —
##    folgt der echten Groesse wie bei den anderen Golems.
##  * Ab Stufe 5: Kollision mit Einheiten ignorieren und trampeln, Boden einebnen,
##    Luftschlag. Das uebrige Riesenpaket (gerade Wege, Gebaeude niedertrampeln,
##    Fahrzeuge) bekommt er nicht.
##  * HOLZ: Baeume faellt er mit EINEM Schlag (Rechtsklick auf einen Baum, B-Bereich)
##    und bekommt ihr Holz plus 50 % (abgerundet); ab Stufe 8 auch alles, was er
##    zertrampelt. Beim Bereichsbefehl nimmt er den Schlag, der die meisten Baeume
##    auf einmal faellt (Tritt, Handschlag oder Trommeln, _harvest_attack). Ein
##    Gebaeude, das er zerstoert, bringt ihm die halben Baukosten als Holz. Das Holz
##    traegt er bei sich, ein Teil davon liegt als Stapel vor seinem Koerper
##    (_wood_pile) — dort holen es Braves wie von jedem Stapel. Der Stapel ist
##    UNSICHTBAR (2026-11-17): das Holz steht nur als Zahl im Besatzungsfeld.
##    Bleibt das Holz 30 s unberuehrt, verbraucht er 15 je Sekunde und waechst um
##    2 % je Sekunde, bis 200 m; je Meter daraus +2 Leben und +0,15 Leben/s.

## Seconds between two re-aimed walks toward the tree he is to fell.
const HARVEST_REPATH: float = 1.0
## How often the trampling checks for trees under him (from stage 8).
const TRAMPLE_WOOD_INTERVAL: float = 0.25
## Ground one loop of the walk clip covers in the 4-m model (golem_export.mjs
## prints it; the figure with the pink shoes stands a little taller than the
## golem's, so the same stride is 2,614 instead of 2,658 m).
const WALK_CLIP_STRIDE: float = 2.614

## Stage 0..9 and the experience (braves, fractions when shared) behind it.
var stage: int = 0
var brave_xp: float = 0.0
## Metres he has grown by eating wood (on top of the stage height).
var wood_growth_m: float = 0.0
## Wood he carries, NOT counting what lies in his pile (see total_wood()).
var wood: int = 0
## Trees he has felled (struck or trampled).
var trees_felled: int = 0

## The pile in front of him the braves take from (null while he carries nothing).
var _wood_pile: WoodPile = null
## Its amount after the last sync: a lower amount now means a brave took some.
var _pile_seen: int = 0
## Seconds since wood was last taken or added.
var _wood_idle: float = 0.0
var _wood_burn_acc: float = 0.0

## Harvest order: one tree, or an area worked out tree by tree.
var harvest_tree: TreeResource = null
var harvest_area: Rect2 = Rect2()
var harvest_poly: PackedVector2Array = PackedVector2Array()
var _harvest_strike: TreeResource = null
var _harvest_cooldown: float = 0.0
var _harvest_repath: float = 0.0
var _harvest_own_order: bool = false
## He fells from the crouch right now (slam or drum): keeps him down between blows.
var _harvest_low: bool = false
var _trample_wood_timer: float = 0.0


func _init() -> void:
	super._init()
	max_health = Balance.GENESIS_GOLEM_HP
	health = max_health
	speed = current_speed()
	_shown_size = size_factor()


func display_name() -> String:
	return "Genesisgolem"


# --- Stages -------------------------------------------------------------------------

## Braves needed for `p_stage` in total (10, 22, 36, ... 190).
static func braves_for_stage(p_stage: int) -> int:
	var total: int = 0
	var table: Array[int] = Balance.GENESIS_GOLEM_STAGE_BRAVES
	for i in range(mini(p_stage, table.size())):
		total += table[i]
	return total


static func max_stage() -> int:
	return Balance.GENESIS_GOLEM_STAGE_BRAVES.size()


static func stage_for_xp(xp: float) -> int:
	var s: int = 0
	while s < max_stage() and xp + 0.000001 >= float(braves_for_stage(s + 1)):
		s += 1
	return s


## Body height of the stage alone (5 m, +4 m per stage: 41 m at stage 9).
static func stage_height(p_stage: int) -> float:
	return Balance.GENESIS_GOLEM_START_HEIGHT + Balance.GENESIS_GOLEM_STAGE_HEIGHT * float(p_stage)


## Body radius of the largest Genesis golem there can be (the catapult's query).
static func max_body_radius() -> float:
	return Balance.GOLEM_BODY_HALF_WIDTH * Balance.GENESIS_GOLEM_MAX_HEIGHT / Balance.GOLEM_HEIGHT


## A hut of `tribe` has brought forth a brave: one point of experience, shared by
## the tribe's living Genesis golems.
static func credit_brave_to_tribe(tribe: Tribe) -> void:
	if tribe == null:
		return
	var golems: Array[GenesisGolem] = []
	for u in tribe.units:
		if is_instance_valid(u) and u is GenesisGolem and u.state != State.DEAD and not u.doomed:
			golems.append(u as GenesisGolem)
	if golems.is_empty():
		return
	var share: float = 1.0 / float(golems.size())
	for g in golems:
		g.credit_brave(share)


func credit_brave(amount: float) -> void:
	brave_xp += amount
	var target: int = stage_for_xp(brave_xp)
	while stage < target:
		_stage_up()


func _stage_up() -> void:
	var was_giant: bool = tramples()
	var cap_before: int = max_health_cap()
	stage += 1
	max_health = max_health_cap()
	health = mini(health + max_health - cap_before, max_health)
	_queue_stretch()
	_apply_speed()
	if tramples() != was_giant:
		_sync_soa_flags()   # from stage 5 he walks through units


## Kills only count — he does not grow, heal or live longer by them.
func _credit_kill() -> void:
	kills += 1


# --- Size -----------------------------------------------------------------------------

func height_m() -> float:
	return minf(stage_height(stage) + wood_growth_m, Balance.GENESIS_GOLEM_MAX_HEIGHT)


func size_factor() -> float:
	return height_m() / Balance.GOLEM_HEIGHT


## The scale of his attack values: 1 at the start (a fresh golem's reach, areas and
## targets), and from there two thirds of the demon golem's gain per metre.
func combat_factor() -> float:
	return 1.0 + (height_m() - Balance.GENESIS_GOLEM_START_HEIGHT) / Balance.GOLEM_HEIGHT \
		* Balance.GENESIS_GOLEM_GROWTH_SHARE


## Metres of growth that count for the attack values (two thirds of the real ones).
func combat_metres() -> float:
	return (height_m() - Balance.GENESIS_GOLEM_START_HEIGHT) * Balance.GENESIS_GOLEM_GROWTH_SHARE


func reach_factor() -> float:
	return pow(combat_factor(), DemonGolem.area_exponent())


func slam_scale() -> float:
	return pow(combat_factor(), DemonGolem.slam_exponent())


func limb_factor() -> float:
	return limb_factor_for(combat_factor())


## From the size like the golem's — the size of his attack values.
func trample_damage() -> int:
	return maxi(1, int(round(Balance.GOLEM_HEIGHT * combat_factor()
		/ Balance.GOLEM_TRAMPLE_HEIGHT_PER_DAMAGE)))


## The demon golem's walking speed at this height, never below the fresh golem's.
func current_speed() -> float:
	var s: float = size_factor()
	var giant: float = Golem.size_factor_for(Balance.GOLEM_MAX_LEVEL)
	var v: float = Balance.GOLEM_SPEED * sqrt(minf(s, giant))
	if s > giant:
		v *= pow(s / giant, DemonGolem.speed_exponent())
	return maxf(v, Balance.GOLEM_SPEED)


## Half the other golems' aggro radius at his size (user spec 2026-11-17).
func aggro_radius() -> float:
	return super.aggro_radius() * Balance.GENESIS_GOLEM_AGGRO_SHARE


func is_full_size() -> bool:
	return false


func has_lifetime() -> bool:
	return false


func is_giant() -> bool:
	return false


func tramples() -> bool:
	return stage >= Balance.GENESIS_GOLEM_GIANT_STAGE


func ignores_unit_collision() -> bool:
	return tramples()


func flattens() -> bool:
	return tramples()


func can_strike_air() -> bool:
	return tramples()


# --- Values ---------------------------------------------------------------------------

func max_targets() -> int:
	return Balance.GOLEM_MAX_TARGETS[0] + int(floor(combat_metres()
		* float(Balance.DEMON_GOLEM_GROWTH_TARGETS) + 0.000001))


func regen_per_second() -> float:
	return Balance.GENESIS_GOLEM_STAGE_REGEN * float(stage) \
		+ Balance.GENESIS_GOLEM_WOOD_REGEN_PER_M * wood_growth_m


func max_health_cap() -> int:
	return Balance.GENESIS_GOLEM_HP + Balance.GENESIS_GOLEM_STAGE_MAX_HP * stage \
		+ int(floor(Balance.GENESIS_GOLEM_WOOD_HP_PER_M * wood_growth_m + 0.000001))


func level_damage_bonus() -> int:
	return 0


## Damage with its fraction: the freshly summoned demon golem's, plus two thirds of
## the demon golem's gain for every metre he has grown.
func damage_exact(kind: StringName) -> float:
	var n: float = combat_metres()
	if kind == ATTACK_KICK:
		return float(Balance.GOLEM_KICK_DAMAGE) * Balance.DEMON_GOLEM_DAMAGE_SHARE \
			+ Balance.DEMON_GOLEM_START_KICK_BONUS + Balance.DEMON_GOLEM_GROWTH_KICK_DAMAGE * n
	if kind == ATTACK_DRUM:
		return float(Balance.GOLEM_DRUM_HIT_DAMAGE * Balance.GOLEM_DRUM_HITS.size()) \
			* Balance.DEMON_GOLEM_DAMAGE_SHARE + Balance.DEMON_GOLEM_START_DRUM_BONUS \
			+ Balance.DEMON_GOLEM_GROWTH_DRUM_DAMAGE * n
	return float(Balance.GOLEM_SLAM_DAMAGE) * Balance.DEMON_GOLEM_DAMAGE_SHARE \
		+ Balance.DEMON_GOLEM_START_SLAM_BONUS + Balance.DEMON_GOLEM_GROWTH_SLAM_DAMAGE * n


func attack_damage(kind: StringName) -> int:
	if kind == ATTACK_STOMP:
		return Balance.GOLEM_STOMP_TRAMPLE_MULT * trample_damage()
	return int(round(damage_exact(kind)))


func drum_hit_damage(hit: int) -> int:
	var hits: int = Balance.GOLEM_DRUM_HITS.size()
	var total: int = attack_damage(ATTACK_DRUM)
	var each: int = total / hits
	return total - each * (hits - 1) if hit >= hits - 1 else each


# --- Tick -----------------------------------------------------------------------------

func tick(delta: float) -> void:
	var before: Vector3 = _tick_pos
	super.tick(delta)
	if state == State.DEAD or doomed or garrison_housed:
		return
	_harvest_cooldown = maxf(_harvest_cooldown - delta, 0.0)
	_tick_harvest(delta)
	_tick_trample_wood(delta, before)
	_tick_wood_store()
	_tick_wood_growth(delta)


# --- Wood store ------------------------------------------------------------------------

func total_wood() -> int:
	var in_pile: int = 0
	if _pile_alive():
		in_pile = _wood_pile.amount
	return wood + in_pile


## Wood comes in (felled trees): it is stored, and the idle clock starts over.
func add_wood(amount: int) -> void:
	if amount <= 0:
		return
	wood += amount
	_wood_idle = 0.0
	_tick_wood_store()


func _wood_piles() -> WoodPileManager:
	return path_service.wood_pile_manager if path_service != null else null


func _pile_alive() -> bool:
	var wpm: WoodPileManager = _wood_piles()
	return _wood_pile != null and is_instance_valid(_wood_pile) and wpm != null \
		and wpm.piles.has(_wood_pile)


## Where his pile lies: just in front of his body, so the braves reach it without
## walking under him; on his own spot when that is no ground to stand on.
func pile_spot() -> Vector3:
	var p: Vector3 = position + heading() * (trample_radius() + Balance.GENESIS_GOLEM_PILE_GAP)
	if nav_grid != null and not nav_grid.is_cell_walkable(nav_grid.world_to_cell(p)):
		p = position
	if terrain_data != null:
		p.y = terrain_data.get_height(p.x, p.z)
	return p


## Keeps the pile in front of him filled from what he carries and notices when a
## brave (or a building that absorbs piles) took from it.
func _tick_wood_store() -> void:
	var wpm: WoodPileManager = _wood_piles()
	if wpm == null:
		return
	if _wood_pile != null and not _pile_alive():
		# Drained to nothing — someone took the rest. (Burnt: lost, but no use.)
		if is_instance_valid(_wood_pile) and _wood_pile.amount <= 0 and _pile_seen > 0:
			_wood_idle = 0.0
		_wood_pile = null
		_pile_seen = 0
	if _wood_pile != null and _wood_pile.amount < _pile_seen:
		_wood_idle = 0.0   # a brave took some
	if wood > 0:
		if _wood_pile == null:
			_wood_pile = wpm.create_pile_at(pile_spot(), false)
			# Not shown (user spec 2026-11-17): his wood is a number in the crew
			# panel. The pile itself stays — it is where the braves fetch it.
			_wood_pile.visible = false
		var put: int = wpm.add_to_pile(_wood_pile, mini(wood, _wood_pile.space_left()))
		wood -= put
	if _wood_pile != null:
		var spot: Vector3 = pile_spot()
		if _flat_dist(_wood_pile.position, spot) > 0.25:
			_wood_pile.position = spot
		_pile_seen = _wood_pile.amount


## 30 s without wood taken or added: he eats it — 15 a second, 2 % growth a second.
func _tick_wood_growth(delta: float) -> void:
	if total_wood() <= 0:
		_wood_burn_acc = 0.0
		return
	_wood_idle += delta
	if _wood_idle < Balance.GENESIS_GOLEM_WOOD_IDLE_TIME \
			or height_m() >= Balance.GENESIS_GOLEM_MAX_HEIGHT - 0.0001:
		_wood_burn_acc = 0.0
		return
	_wood_burn_acc += Balance.GENESIS_GOLEM_WOOD_BURN_RATE * delta
	var n: int = mini(int(_wood_burn_acc), total_wood())
	if n <= 0:
		return
	_wood_burn_acc -= float(n)
	_eat_wood(n)
	grow_by_wood(float(n))


## Takes `n` wood from his store (carried first, then the pile) without counting
## it as taken by someone.
func _eat_wood(n: int) -> void:
	var from_store: int = mini(n, wood)
	wood -= from_store
	var rest: int = n - from_store
	if rest > 0 and _pile_alive():
		_wood_piles().take_from_pile(_wood_pile, rest)
		if _pile_alive():
			_pile_seen = _wood_pile.amount
		else:
			_wood_pile = null
			_pile_seen = 0


## Growth from `eaten` wood: 2 % of his height per 15 wood (compounded), up to
## 200 m. Every metre gained adds 2 to the health limit (and to his health) and
## 0,15 to the regeneration.
func grow_by_wood(eaten: float) -> void:
	var h0: float = height_m()
	var h1: float = minf(h0 * pow(1.0 + Balance.GENESIS_GOLEM_WOOD_GROWTH_RATE,
		eaten / Balance.GENESIS_GOLEM_WOOD_BURN_RATE), Balance.GENESIS_GOLEM_MAX_HEIGHT)
	if h1 <= h0:
		return
	var cap_before: int = max_health_cap()
	wood_growth_m += h1 - h0
	max_health = max_health_cap()
	health = mini(health + max_health - cap_before, max_health)
	_apply_speed()


# --- Felling trees ---------------------------------------------------------------------

## The wood a felled tree brings him: its yield and half as much again, rounded down.
static func harvest_yield(tree_wood: int) -> int:
	return int(floor(float(tree_wood) * (1.0 + Balance.GENESIS_GOLEM_HARVEST_BONUS) + 0.000001))


func _trees() -> TreeManager:
	return path_service.tree_manager if path_service != null else null


## Untyped on purpose: the tree may have been freed meanwhile (felled by a brave).
static func _tree_ok(tree) -> bool:
	return tree != null and is_instance_valid(tree) and not (tree as TreeResource).felled_flag


## Fells `tree` at once and stores its wood (with the bonus).
func collect_tree(tree: TreeResource) -> int:
	var tm: TreeManager = _trees()
	if tm == null or not _tree_ok(tree):
		return 0
	var got: int = harvest_yield(tm.fell_tree(tree))
	trees_felled += 1
	add_wood(got)
	return got


func is_harvesting() -> bool:
	return harvest_tree != null or harvest_area.size.x > 0.0


## Right-click on a tree: walk there and fell it with a blow.
func order_harvest_tree(tree: TreeResource) -> bool:
	if not _tree_ok(tree) or not can_take_orders():
		return false
	_halt_for_harvest()
	harvest_tree = tree
	harvest_area = Rect2()
	harvest_poly = PackedVector2Array()
	return true


## Area order (key B): fell tree after tree in the area, the nearest first.
func order_harvest_area(area: Rect2, poly: PackedVector2Array = PackedVector2Array()) -> bool:
	if area.size.x <= 0.0 or not can_take_orders():
		return false
	_halt_for_harvest()
	harvest_tree = null
	harvest_area = area
	harvest_poly = poly
	return true


func end_harvest() -> void:
	_harvest_low = false
	harvest_tree = null
	harvest_area = Rect2()
	harvest_poly = PackedVector2Array()
	_harvest_strike = null


## Drops whatever he was doing (march, fight) for the harvest order.
func _halt_for_harvest() -> void:
	_harvest_own_order = true
	order_move(position)
	_harvest_own_order = false


## Any order from outside ends the harvest.
func order_move(target: Vector3, queue_up: bool = false, aggressive: bool = false) -> void:
	if not _harvest_own_order:
		end_harvest()
	super.order_move(target, queue_up, aggressive)


func order_attack(enemy: Unit) -> void:
	end_harvest()
	super.order_attack(enemy)


func order_attack_building(building) -> void:
	end_harvest()
	super.order_attack_building(building)


## Nearest standing tree of the area order on his island.
func _next_area_tree() -> TreeResource:
	var tm: TreeManager = _trees()
	if tm == null or harvest_area.size.x <= 0.0:
		return null
	var best: TreeResource = null
	var best_d: float = INF
	for tree in tm.area_trees(harvest_area, harvest_poly):
		if not _tree_ok(tree):
			continue
		if nav_grid != null and not nav_grid.same_island(position, tree.position):
			continue
		var d: float = _flat_dist(position, tree.position)
		if d < best_d:
			best_d = d
			best = tree
	return best


## Felling is attacking: he walks into reach, turns to the tree and strikes it —
## a single tree with his usual blow (standing a kick, crouched a slam), the trees
## of an area order with the blow that fells the most of them at once
## (_harvest_attack). Whatever else stands in the blow's area is struck as well.
## A fight goes first; afterwards he comes back to the trees.
func _tick_harvest(delta: float) -> void:
	if not is_harvesting() or _pending_attack != &"" or state == State.ATTACK:
		return
	if not _tree_ok(harvest_tree):
		harvest_tree = _next_area_tree()
		if harvest_tree == null:
			end_harvest()
			return
	var d: float = _flat_dist(position, harvest_tree.position)
	if d > reach():
		_harvest_repath -= delta
		if state != State.MOVE or _harvest_repath <= 0.0:
			_harvest_repath = HARVEST_REPATH
			_harvest_own_order = true
			order_move(harvest_tree.position, false, true)
			_harvest_own_order = false
		return
	if state == State.MOVE:
		waypoint_queue.clear()
		_clear_path()
		_set_state(State.IDLE)
	_face_point(harvest_tree.position)
	if is_switching_stance() or is_stretching() or _stretch_queued or _harvest_cooldown > 0.0:
		return
	if not is_turned_to_facing():
		return
	var kind: StringName = _harvest_attack()
	_harvest_low = stance_for(kind) == STANCE_CROUCH
	if stance != stance_for(kind):
		_begin_stance(stance_for(kind))   # the better blow needs the other stance
		return
	_harvest_strike = harvest_tree
	_harvest_cooldown = cooldown_for(kind)
	_wind_up(kind)


## The blow for the next tree. A single tree: the blow of the stance he is in. An
## area order (user spec 2026-11-17): the blow that fells the most trees of the
## order per second from where he stands — the kick's lane, the slam's circle or
## the drum's —, as long as the tree he came for is among them. A blow of the
## other stance pays for bending down AND getting up again (he has to walk on to
## the next trees): standing he crouches only where the ground blow fells clearly
## more than the kick. A tie goes to the stance he is in.
func _harvest_attack() -> StringName:
	var plain: StringName = ATTACK_SLAM if stance == STANCE_CROUCH else ATTACK_KICK
	var tm: TreeManager = _trees()
	if harvest_area.size.x <= 0.0 or tm == null or not _tree_ok(harvest_tree):
		return plain
	var frame: Array[Vector3] = _heading_frame()
	var trees: Array[TreeResource] = tm.area_trees(harvest_area, harvest_poly)
	var order: Array[StringName] = [ATTACK_KICK, ATTACK_SLAM, ATTACK_DRUM]
	if stance == STANCE_CROUCH:
		order = [ATTACK_SLAM, ATTACK_DRUM, ATTACK_KICK]
	var best: StringName = plain
	var best_value: float = 0.0
	for kind in order:
		if not _in_hit_zone(kind, harvest_tree.position, frame[0], frame[1]):
			continue
		var time: float = cooldown_for(kind)
		if stance_for(kind) != stance:
			time += 2.0 * stance_switch_time()
		var value: float = float(harvest_trees_in_blow(kind, trees).size()) / time
		if value > best_value + 0.0001:
			best = kind
			best_value = value
	return best


## The standing trees among `trees` the blow `kind` would strike right now.
func harvest_trees_in_blow(kind: StringName, trees: Array[TreeResource]) -> Array[TreeResource]:
	var frame: Array[Vector3] = _heading_frame()
	var out: Array[TreeResource] = []
	for tree in trees:
		if _tree_ok(tree) and _in_hit_zone(kind, tree.position, frame[0], frame[1]):
			out.append(tree)
	return out


## While he fells from the crouch he stays down between the blows — the stance
## logic would otherwise get him up as soon as the stance has settled.
func stance_settled() -> bool:
	if _harvest_low and state == State.IDLE and is_harvesting():
		return false
	return super.stance_settled()


func _land_attack(kind: StringName, hit: int = 0) -> Dictionary:
	var struck: Dictionary = super._land_attack(kind, hit)
	if _harvest_strike != null:
		var tree = _harvest_strike   # untyped: may be freed by now
		if kind != ATTACK_DRUM or hit >= Balance.GOLEM_DRUM_HITS.size() - 1:
			_harvest_strike = null
		# An area order: every tree of the order in the blow's area falls with it.
		var tm: TreeManager = _trees()
		if harvest_area.size.x > 0.0 and tm != null:
			for other in harvest_trees_in_blow(kind, tm.area_trees(harvest_area, harvest_poly)):
				collect_tree(other)
		if _tree_ok(tree) and _flat_dist(position, tree.position) <= reach() + 1.0:
			collect_tree(tree)
	return struck


## A building he brings down leaves him wood: half of what it cost to build,
## rounded down (user spec 2026-11-17).
func _strike_building(b, stages: int = Balance.GOLEM_BUILDING_STAGES) -> void:
	var gain: int = building_wood(b)
	super._strike_building(b, stages)
	if not is_instance_valid(b) or b.health <= 0:
		add_wood(gain)


## Wood a destroyed building is worth to him (a building site: what was delivered).
static func building_wood(b) -> int:
	if b == null or not is_instance_valid(b):
		return 0
	var built: int = b.wood_delivered if b.under_construction else b.wood_cost
	return int(floor(float(maxi(built, 0)) * Balance.GENESIS_GOLEM_BUILDING_WOOD_SHARE + 0.000001))


## From stage 8 the trampling fells the trees under him as he walks.
func _tick_trample_wood(delta: float, before: Vector3) -> void:
	if stage < Balance.GENESIS_GOLEM_TRAMPLE_WOOD_STAGE or before == Vector3.INF or delta <= 0.0:
		return
	if Vector2(position.x - before.x, position.z - before.z).length() / delta \
			< Balance.GOLEM_TRAMPLE_MIN_SPEED:
		return
	_trample_wood_timer -= delta
	if _trample_wood_timer > 0.0:
		return
	_trample_wood_timer = TRAMPLE_WOOD_INTERVAL
	var tm: TreeManager = _trees()
	if tm == null:
		return
	var r: float = trample_radius()
	for tree in tm.area_trees(Rect2(position.x - r, position.z - r, r * 2.0, r * 2.0)):
		if _tree_ok(tree) and _flat_dist(position, tree.position) <= r:
			collect_tree(tree)


# --- Build ------------------------------------------------------------------------------

## His own model; the build (scale, body box) stays the golem's.
func model_file() -> String:
	return "models/units/golem_genesis.glb"


func walk_clip_speed() -> float:
	return WALK_CLIP_STRIDE * MODEL_SCALE


# --- Display ----------------------------------------------------------------------------

func status_text() -> String:
	var next: String = ""
	if stage < max_stage():
		next = "   noch %d Braves bis Stufe %d" % [
			int(ceil(float(braves_for_stage(stage + 1)) - brave_xp - 0.000001)), stage + 1]
	var pose: String = "gebückt" if stance == STANCE_CROUCH else "stehend"
	return "Genesisgolem   Stufe %d/%d%s\nGröße: %.1f m   Leben: %d/%d   Heilung: %.2f/s\nHolz: %d   Kills: %d   Haltung: %s" % [
		stage, max_stage(), next, height_m(), health, max_health, regen_per_second(),
		total_wood(), kills, pose]
