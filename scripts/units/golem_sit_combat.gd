class_name GolemSitCombat extends RefCounted

## SITZANGRIFFE eines Golems (Nutzervorgabe 2026-11-17, plans/10l_golem_sitting.md).
## Gilt fuer alle drei Golems, nur in der Haltung STANCE_SIT. Die Golemin bekommt im
## Sitzen keine Befehle — sie greift von selbst an, was ihre Glieder vom Platz aus
## erreichen, und dreht sich (langsam) nach Feinden, die keines erreicht.
##
## ZWEI KANAELE, BEINE und ARME, jeder mit eigener Ausholzeit und Abklingzeit; beide
## duerfen gleichzeitig angreifen. Zonen und Werte nach den Vorgaben vom 2026-11-17
## (Masse in Balance.GOLEM_SIT_*, gemessen an den Clips):
##  1. Fuss-Stampfer (Beine, links ODER rechts): Kreis (mittel) um die Stelle, an der der
##     Schuh landet, nicht hinter die Ferse des ruhenden Schuhs. Schnell (wie der gebueckte
##     Handschlag), Schaden und Zielzahl wie der Handschlag.
##  2. Bein strecken (Beine, links ODER rechts): Schneise vom Hueftgelenk bis zur Spitze des
##     gestreckten Schuhs, so breit wie das Bein. Werte wie der Tritt.
##  5. Arm-Wischer (Arme, immer nur EIN Arm): Kegel neben ihr auf seiner Seite, etwas hinter
##     den Ruecken, Reichweite reach(). Schaden und Zielzahl wie der Luftschlag, schnell.
## Welche Seite: die, deren Angriff mehr bringt; bei Gleichstand die, deren Aufschlag
## naeher an den getroffenen Feinden liegt.
## GROSSE ANGRIFFE (brauchen und sperren beide Kanaele, erst ab GOLEM_SIT_BIG_MIN_TARGETS):
##  3. Po-Klatscher (sit_hop): Kreis des Sprungs um die Mitte der Sitzflaeche (alles unter
##     ihr). Schaden und Zielzahl wie der Sprung, Abklingzeit etwas laenger als dessen.
##  4. Doppelstampfer: Kreis des Trommelns um die Stelle, an der beide Schuhe landen (reicht
##     ein Stueck hinter die Fuesse). Werte wie das Trommeln.
##  6. Handstampfer hinten (sit_clap): Kreis des Trommelns um jede Hand, nur hinter der
##     Sitzmitte. Schaden und Zielzahl wie das Trommeln, Abklingzeit kuerzer.
## Waehrend sie sich dreht, greift sie nicht an (und beginnt keine Drehung, solange ein
## Angriff ausholt). Die Wahl haengt allein daran, wo die Feinde stehen: jeder Angriff
## wird mit dem bewertet, was er in seiner Zone jetzt trifft.
## Getroffen werden vorerst nur feindliche Einheiten am Boden (keine Gebaeude, keine
## Fahrzeuge, kein Rueckstoss).
##
## Die ANIMATION laeuft ueber GolemSitAnim (eigene Ebenen fuer Beine, Arme und den
## ganzen Koerper); solange die Clips fehlen, wirken die Angriffe ohne Bild.

const STOMP_L: StringName = &"sit_stomp_l"
const STOMP_R: StringName = &"sit_stomp_r"
const KICK_L: StringName = &"sit_kick_l"
const KICK_R: StringName = &"sit_kick_r"
const WIPE_L: StringName = &"sit_wipe_l"
const WIPE_R: StringName = &"sit_wipe_r"
const HOP: StringName = &"sit_hop"
const CLAP: StringName = &"sit_clap"
const DOUBLE_STOMP: StringName = &"sit_double_stomp"
## The stretch when she grows on the seat (clip sit_grow): not chosen like the attacks,
## it strikes once per growth (grow_strike) — like the kick, in both legs' lanes.
const GROW: StringName = &"sit_grow"
const KINDS: Array[StringName] = [STOMP_L, STOMP_R, KICK_L, KICK_R, WIPE_L, WIPE_R,
	HOP, CLAP, DOUBLE_STOMP]

const CH_LEGS: int = 0
const CH_ARMS: int = 1
## How often a free channel looks for something to strike (seconds).
const THINK_INTERVAL: float = 0.25

var g: Golem = null
## Per channel: the attack wound up (&"" = none), seconds to its impact, where it
## lands, and the cooldown left.
var pending: Array[StringName] = [&"", &""]
var pending_time: Array[float] = [0.0, 0.0]
var aim: Array[Vector3] = [Vector3.INF, Vector3.INF]
var cooldown: Array[float] = [0.0, 0.0]
## She is turning toward an enemy none of her limbs reaches.
var turning: bool = false
var _think: float = 0.0
## Last landings (tests, diagnostics): kind -> victims struck, kind -> buildings struck.
var last_struck: Dictionary = {}
var last_struck_buildings: Dictionary = {}
## Seconds until the stretch of growing on the seat strikes (0 = none owed).
var _grow_left: float = 0.0


func _init(p_golem: Golem) -> void:
	g = p_golem


func reset() -> void:
	pending = [&"", &""]
	pending_time = [0.0, 0.0]
	aim = [Vector3.INF, Vector3.INF]
	cooldown = [0.0, 0.0]
	turning = false
	_think = 0.0
	_grow_left = 0.0


# --- What each attack is -------------------------------------------------------------

## Which channels an attack needs (true = it uses or blocks that channel).
static func channels_of(kind: StringName) -> Array[int]:
	if kind == HOP or kind == CLAP or kind == DOUBLE_STOMP:
		return [CH_LEGS, CH_ARMS]
	if kind == WIPE_L or kind == WIPE_R:
		return [CH_ARMS]
	return [CH_LEGS]


## The animation layer it plays on (GolemSitAnim): one leg, one arm, or the body.
static func layer_of(kind: StringName) -> int:
	if kind == HOP or kind == CLAP or kind == DOUBLE_STOMP:
		return GolemSitAnim.LAYER_FULL
	if kind == WIPE_L or kind == WIPE_R:
		return GolemSitAnim.LAYER_ARMS
	return GolemSitAnim.LAYER_LEGS


## The standing attack it sounds like (and whose numbers it starts from).
static func model_of(kind: StringName) -> StringName:
	if kind == KICK_L or kind == KICK_R or kind == GROW:
		return Golem.ATTACK_KICK
	if kind == CLAP or kind == DOUBLE_STOMP:
		return Golem.ATTACK_DRUM
	if kind == HOP:
		return Golem.ATTACK_STOMP
	if kind == WIPE_L or kind == WIPE_R:
		return Golem.ATTACK_SWAT
	return Golem.ATTACK_SLAM


## Damage and target cap: those of the standing attack (model_of).
func damage(kind: StringName) -> int:
	if kind == GROW:
		return g.trample_damage()   # the stretch on the seat: one trample tick (user spec 2026-11-17)
	return g.attack_damage(model_of(kind))


func max_targets(kind: StringName) -> int:
	if kind == GROW:
		return 2 * g.max_targets_of(Golem.ATTACK_KICK)   # both legs' lanes, each with the kick's cap
	return g.max_targets_of(model_of(kind))


## The attack whose tempo it takes: the quick crouched slam for the foot stomps and the
## wipes (user's choice 2026-11-17), its own otherwise.
static func tempo_of(kind: StringName) -> StringName:
	if kind == STOMP_L or kind == STOMP_R or kind == WIPE_L or kind == WIPE_R:
		return Golem.ATTACK_SLAM
	return model_of(kind)


## Seated she strikes more easily (user spec 2026-11-17): every sit attack but the hand
## stomp behind her comes back GOLEM_SIT_COOLDOWN_FACTOR faster — and reaches
## GOLEM_SIT_AREA_FACTOR less far (area_scale).
func cooldown_of(kind: StringName) -> float:
	var cd: float = g.cooldown_for(tempo_of(kind))
	if kind == CLAP:
		return cd * Balance.GOLEM_SIT_CLAP_COOLDOWN_SHARE
	if kind == HOP:
		cd *= Balance.GOLEM_SIT_HOP_COOLDOWN_FACTOR
	return cd * Balance.GOLEM_SIT_COOLDOWN_FACTOR


## Size of the target areas of the sit attacks (all but the hand stomp behind her).
static func area_scale() -> float:
	return Balance.GOLEM_SIT_AREA_FACTOR


func windup_of(kind: StringName) -> float:
	return g.current_windup(tempo_of(kind))


# --- Where her limbs are -------------------------------------------------------------

func forward() -> Vector3:
	return g.heading()


## Her LEFT side (the model's +x when she faces +z — measured on the clip sit_idle).
func left() -> Vector3:
	var f: Vector3 = forward()
	return Vector3(f.z, 0.0, -f.x)


## Where her feet rest while she sits (in front of the seat).
func feet_point() -> Vector3:
	return g.position + forward() * g.seat_back_m()


## Where the hand of `side` (+1 left, -1 right) rests: behind and beside the hips.
func hand_point(side: float) -> Vector3:
	var s: float = g.size_factor()
	return feet_point() - forward() * (Balance.GOLEM_SIT_HAND_BACK * g.model_scale().z * s) \
		+ left() * (side * Balance.GOLEM_SIT_HAND_SIDE * g.model_scale().x * s)


## Metres of the 4-m model -> metres in the world, across (x) and along (z) her body.
func _sx() -> float:
	return g.model_scale().x * g.size_factor()


func _sz() -> float:
	return g.model_scale().z * g.size_factor()


## A point `out` to the side `side` (+1 left, -1 right) and `ahead` forward of `base`,
## both in metres of the 4-m model (the measures in Balance, taken from the clips).
func _off(base: Vector3, side: float, out: float, ahead: float) -> Vector3:
	return base + left() * (side * out * _sx()) + forward() * (ahead * _sz())


## Where the shoe of side rests (its middle).
func foot_point(side: float) -> Vector3:
	return _off(feet_point(), side, Balance.GOLEM_SIT_FOOT_SIDE, 0.0)


## Where the stomping shoe of side comes down (the clip sit_stomp_l/_r): a bit
## further ahead and out than it rests.
func stomp_point(side: float) -> Vector3:
	return _off(foot_point(side), side, Balance.GOLEM_SIT_STOMP_LAND.x, Balance.GOLEM_SIT_STOMP_LAND.y)


## Radius of the foot stomp's circle.
func stomp_radius() -> float:
	return g.slam_radius() * Balance.GOLEM_SIT_STOMP_RADIUS_SHARE * area_scale()


## How far ahead of feet_point p lies (negative: behind).
func _ahead_of_feet(p: Vector3) -> float:
	return _flat(p - feet_point()).dot(forward())


## The leg's lane on side: from her hip joint to the tip of the stretched shoe, as
## wide as the leg — and inward up to her middle (the knees touch; user report
## 2026-11-17: a foe between her shoes was never struck by a single attack).
func in_kick_lane(p: Vector3, side: float) -> bool:
	var d: Vector3 = _flat(p - feet_point())
	var along: float = d.dot(forward())
	var out: float = d.dot(left()) * side
	return along >= -Balance.GOLEM_SIT_KICK_FROM * _sz() and along <= Balance.GOLEM_SIT_KICK_TO * _sz() \
		and out >= 0.0 and out <= (Balance.GOLEM_SIT_KICK_SIDE + Balance.GOLEM_SIT_KICK_WIDTH * 0.5) * _sx() * area_scale()


## The wipe's cone on side: beside the seat within reach(), from GOLEM_SIT_WIPE_BACK_DEG
## behind straight out forward to her pelvis — no further ahead than
## GOLEM_SIT_WIPE_FRONT before the middle of the seat (user report 2026-11-17: it
## reached out to her legs).
func in_wipe_cone(p: Vector3, side: float) -> bool:
	var d: Vector3 = _flat(p - g.position)
	var dist: float = d.length()
	if dist > g.reach() * area_scale() or dist < 0.001:
		return dist < 0.001
	var out: float = d.dot(left()) * side
	if out <= 0.0:
		return false
	var ahead: float = d.dot(forward())
	if ahead > Balance.GOLEM_SIT_WIPE_FRONT * _sz():
		return false
	return rad_to_deg(atan2(ahead, out)) >= -Balance.GOLEM_SIT_WIPE_BACK_DEG


## Radius of the circles of the hand stomp behind her (around each hand).
func clap_radius() -> float:
	return g.ground_radius(Golem.ATTACK_DRUM) * Balance.GOLEM_SIT_CLAP_AREA_FACTOR


## Radius of the double stomp's circle.
func double_stomp_radius() -> float:
	return g.ground_radius(Golem.ATTACK_DRUM) * area_scale() * Balance.GOLEM_SIT_DOUBLE_STOMP_AREA_FACTOR


## Where the double stomp's circle lies: about the heels of the resting shoes.
func double_stomp_point() -> Vector3:
	return _off(feet_point(), 1.0, 0.0, Balance.GOLEM_SIT_DOUBLE_STOMP_LAND)


## +1 for the attacks of her left side, -1 for the right, 0 for the others.
static func side_of_kind(kind: StringName) -> float:
	if kind == STOMP_L or kind == KICK_L or kind == WIPE_L:
		return 1.0
	if kind == STOMP_R or kind == KICK_R or kind == WIPE_R:
		return -1.0
	return 0.0


## Where an attack comes down (victims are taken nearest to it first; ties between two
## attacks go to the one closer to them).
func impact_point(kind: StringName) -> Vector3:
	var side: float = side_of_kind(kind)
	match kind:
		STOMP_L, STOMP_R:
			return stomp_point(side)
		WIPE_L, WIPE_R:
			return hand_point(side)
		KICK_L, KICK_R:
			return _off(feet_point(), side, Balance.GOLEM_SIT_KICK_SIDE, 0.0)
		DOUBLE_STOMP:
			return double_stomp_point()
		CLAP:
			return g.position - forward() * (_flat(g.position - hand_point(1.0)).dot(forward()))
	return g.position


## Is p struck by the attack kind? (at is kept for callers; every sit attack
## lands at its fixed place.)
func in_area(kind: StringName, p: Vector3, at: Vector3 = Vector3.INF) -> bool:
	var side: float = side_of_kind(kind)
	match kind:
		STOMP_L, STOMP_R:
			return _flat(p - stomp_point(side)).length() <= stomp_radius() \
				and _ahead_of_feet(p) >= -Balance.GOLEM_SIT_HEEL_BACK * _sz()
		WIPE_L, WIPE_R:
			return in_wipe_cone(p, side)
		KICK_L, KICK_R:
			return in_kick_lane(p, side)
		GROW:
			return in_kick_lane(p, 1.0) or in_kick_lane(p, -1.0)
		CLAP:
			if _flat(p - g.position).dot(forward()) > 0.0:
				return false   # only behind the middle of the seat: her back
			var r: float = clap_radius()
			return _flat(p - hand_point(1.0)).length() <= r or _flat(p - hand_point(-1.0)).length() <= r
		DOUBLE_STOMP:
			return _flat(p - double_stomp_point()).length() <= double_stomp_radius()
		HOP:
			return _flat(p - g.position).length() <= g.stomp_radius() * area_scale()
	return false


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# --- Ticking -------------------------------------------------------------------------

func is_busy() -> bool:
	return pending[CH_LEGS] != &"" or pending[CH_ARMS] != &""


func channel_free(ch: int) -> bool:
	return pending[ch] == &"" and cooldown[ch] <= 0.0


## One tick while she sits: wound-up attacks land, the strike of a stretch (growing on
## the seat) lands, free channels pick the next attack, or she turns toward an enemy no
## limb reaches.
func tick(delta: float) -> void:
	for ch in [CH_LEGS, CH_ARMS]:
		cooldown[ch] = maxf(cooldown[ch] - delta, 0.0)
		if pending[ch] == &"":
			continue
		pending_time[ch] -= delta
		if pending_time[ch] <= 0.0:
			var kind: StringName = pending[ch]
			_land(kind, aim[ch])
			for c in channels_of(kind):
				pending[c] = &""
	if _grow_left > 0.0:
		_grow_left -= delta
		if _grow_left <= 0.0:
			_grow_left = 0.0
			_land(GROW, Vector3.INF)
	if turning:
		if g.is_turned_to(g.facing, Balance.GOLEM_SIT_TURN_DONE_DEG):
			g.sit_turn_tick()
			turning = false
			_think = 0.0
		else:
			g.sit_turn_tick()
			return
	_think -= delta
	if _think > 0.0:
		return
	_think = THINK_INTERVAL
	_choose()


## She grows on the seat (user spec 2026-11-17): the stretch (clip sit_grow) strikes like
## the kick in BOTH legs' lanes, `delay` seconds from now (when the legs are stretched).
func grow_strike(delay: float) -> void:
	_grow_left = maxf(delay, 0.001)


## Picks what to strike with the free channels: the best plan by damage per second —
## a big attack (both channels) against the best single attack of each free channel
## together. Units AND enemy buildings count (a building like GOLEM_STRUCTURE_VALUE
## damage; each strike takes one destruction stage off it). The big attacks need
## GOLEM_SIT_BIG_MIN_TARGETS targets — unless no single attack reaches anything: then
## one target is enough (no blind spot under or behind her). Nothing within reach:
## turn toward the nearest enemy unit in aggro range.
func _choose() -> void:
	var legs: bool = channel_free(CH_LEGS)
	var arms: bool = channel_free(CH_ARMS)
	if not legs and not arms:
		return
	var foes: Array[Unit] = _foes_around()
	var builds: Array = _buildings_around()
	if foes.is_empty() and builds.is_empty():
		if not is_busy():
			_maybe_turn(foes)   # maybe a building further off
		return
	var best_legs: Dictionary = _best_of([STOMP_L, STOMP_R, KICK_L, KICK_R], foes, builds) if legs else {}
	var best_arms: Dictionary = _best_of([WIPE_L, WIPE_R], foes, builds) if arms else {}
	var single: float = float(best_legs.get("value", 0.0)) + float(best_arms.get("value", 0.0))
	if legs and arms and not is_busy():
		var min_hit: int = Balance.GOLEM_SIT_BIG_MIN_TARGETS if single > 0.0 else 1
		var big: Dictionary = _best_of([HOP, CLAP, DOUBLE_STOMP], foes, builds, min_hit)
		if float(big.get("value", 0.0)) > single:
			_wind_up(big.kind, big.at)
			return
	if not best_legs.is_empty():
		_wind_up(best_legs.kind, best_legs.at)
	if not best_arms.is_empty():
		_wind_up(best_arms.kind, best_arms.at)
	if best_legs.is_empty() and best_arms.is_empty() and not is_busy():
		_maybe_turn(foes)


## Radius around the seat beyond which no sit attack reaches.
func _scan_radius() -> float:
	return g.seat_back_m() + g.reach() + g.ground_radius(Golem.ATTACK_DRUM)


## Enemy units around her that any sit attack could ever reach, or that she could
## turn toward (aggro radius around the seat).
func _foes_around() -> Array[Unit]:
	var out: Array[Unit] = []
	if g.path_service == null:
		return out
	var radius: float = maxf(g.aggro_radius(), _scan_radius())
	for u in g.path_service.get_units_in_radius(g.position, radius):
		if u == g or u.state == Unit.State.DEAD or u.doomed or u.tribe_id == g.tribe_id:
			continue
		if not u.is_targetable() or u.is_airborne() or u is CrewedVehicle:
			continue
		out.append(u)
	return out


## Enemy buildings near enough for a sit attack (like the standing attacks: attackable,
## not her own).
func _buildings_around() -> Array:
	var out: Array = []
	if g.building_manager == null:
		return out
	var radius: float = _scan_radius()
	for b in g.building_manager.buildings:
		if not is_instance_valid(b) or b.health <= 0 or b.tribe_id == g.tribe_id or not b.is_attackable():
			continue
		if b.footprint_distance_to(Vector2(g.position.x, g.position.z)) <= radius:
			out.append(b)
	return out


## Does the attack `kind` touch the building's footprint? Sampled every cell (corners
## and middles) over the footprint.
func building_in_area(kind: StringName, b) -> bool:
	var r: Rect2i = b.footprint_rect()
	var step: float = TerrainData.CELL_SIZE * 0.5
	var nx: int = r.size.x * 2
	var nz: int = r.size.y * 2
	for i in range(nx + 1):
		for k in range(nz + 1):
			var p: Vector3 = Vector3(float(r.position.x) * TerrainData.CELL_SIZE + step * float(i), 0.0,
				float(r.position.y) * TerrainData.CELL_SIZE + step * float(k))
			if in_area(kind, p):
				return true
	return false


## The best of `kinds` right now: {kind, at, value} (empty = none strikes anything).
## Equal value (e.g. both legs reach the same foes): the one whose impact lies closer
## to what it strikes — so a foe on her right gets the right leg.
func _best_of(kinds: Array, foes: Array[Unit], builds: Array = [], min_big: int = Balance.GOLEM_SIT_BIG_MIN_TARGETS) -> Dictionary:
	var best: Dictionary = {}
	for kind in kinds:
		var hit: Array[Unit] = victims(kind, Vector3.INF, foes)
		var hit_b: Array = buildings_struck(kind, builds, hit.size())
		if hit.is_empty() and hit_b.is_empty():
			continue
		if channels_of(kind).size() == 2 and hit.size() + hit_b.size() < min_big:
			continue   # the big ones are area attacks
		var v: float = _value(kind, hit, hit_b)
		var near: float = _spread(kind, hit, hit_b)
		var bv: float = float(best.get("value", 0.0))
		if v > bv + 0.000001 or (absf(v - bv) <= 0.000001 and near < float(best.get("near", INF))):
			best = {"kind": kind, "at": Vector3.INF, "value": v, "near": near}
	return best


## Mean flat distance from the impact of `kind` to what it strikes.
func _spread(kind: StringName, hit: Array[Unit], hit_b: Array = []) -> float:
	var c: Vector3 = impact_point(kind)
	var s: float = 0.0
	for u in hit:
		s += _flat(u.position - c).length()
	for b in hit_b:
		s += _flat(b.center_world() - c).length()
	return s / float(maxi(hit.size() + hit_b.size(), 1))


## Damage per second the attack would bring: what it strikes (no overkill, target
## cap; a building counts GOLEM_STRUCTURE_VALUE) over its cooldown.
func _value(kind: StringName, hit: Array[Unit], hit_b: Array = []) -> float:
	var dmg: int = damage(kind)
	var sum: float = Balance.GOLEM_STRUCTURE_VALUE * float(hit_b.size())
	for u in hit:
		sum += float(mini(dmg, u.health))
	return sum / maxf(cooldown_of(kind), 0.05)


## Who the attack `kind` landing at `at` strikes: enemies in its area, the nearest to
## the impact first, up to its target cap.
func victims(kind: StringName, at: Vector3, foes: Array[Unit]) -> Array[Unit]:
	var hit: Array[Unit] = []
	for u in foes:
		if is_instance_valid(u) and u.state != Unit.State.DEAD and in_area(kind, u.position, at):
			hit.append(u)
	var centre: Vector3 = impact_point(kind)
	hit.sort_custom(func(a: Unit, b: Unit) -> bool:
		return _flat(a.position - centre).length_squared() < _flat(b.position - centre).length_squared())
	if hit.size() > max_targets(kind):
		hit.resize(max_targets(kind))
	return hit


## The buildings the attack strikes: those its area touches, nearest first, in the
## places of the target cap the units left free (units go first, as standing).
func buildings_struck(kind: StringName, builds: Array, units_hit: int) -> Array:
	var free: int = max_targets(kind) - units_hit
	var out: Array = []
	if free <= 0:
		return out
	var centre: Vector3 = impact_point(kind)
	for b in builds:
		if is_instance_valid(b) and b.health > 0 and building_in_area(kind, b):
			out.append(b)
	out.sort_custom(func(a, b) -> bool:
		return _flat(a.center_world() - centre).length_squared() < _flat(b.center_world() - centre).length_squared())
	if out.size() > free:
		out.resize(free)
	return out


## Starts the attack: its channels are busy until it lands, its cooldown runs from now.
func _wind_up(kind: StringName, at: Vector3) -> void:
	var t: float = windup_of(kind)
	for ch in channels_of(kind):
		pending[ch] = kind
		pending_time[ch] = t
		aim[ch] = at
		cooldown[ch] = cooldown_of(kind)
	g.sit_attack_started(kind, t)


## The landing: every unit struck takes the damage, every building struck loses ONE
## destruction stage (like the standing attacks; a building brought down is a kill).
func _land(kind: StringName, at: Vector3) -> void:
	var dmg: int = damage(kind)
	var struck: Array[Unit] = victims(kind, at, _foes_around())
	for u in struck:
		var hp: int = Golem.kill_hp_of(u)
		u.take_damage(dmg, g)
		if not is_instance_valid(u) or u.state == Unit.State.DEAD or u.doomed:
			g._credit_kill(hp)
	var struck_b: Array = buildings_struck(kind, _buildings_around(), struck.size())
	for b in struck_b:
		g._strike_building(b, Balance.GOLEM_BUILDING_STAGES)
	last_struck[kind] = struck
	last_struck_buildings[kind] = struck_b
	g._play_strike_sfx(model_of(kind))


## Nothing in reach: she turns (slowly) toward the nearest enemy unit within her aggro
## radius — none there, toward the nearest enemy building within it (user report
## 2026-11-17: she never turned to an airship wharf beside her) — if it lies more than
## GOLEM_SIT_TURN_MIN_DEG off her heading.
func _maybe_turn(foes: Array[Unit]) -> void:
	var goal: Vector3 = Vector3.INF
	var best: float = INF
	for u in foes:
		var d: float = _flat(u.position - g.position).length()
		if d <= g.aggro_radius() and d < best:
			best = d
			goal = u.position
	if goal == Vector3.INF and g.building_manager != null:
		for b in g.building_manager.buildings:
			if not is_instance_valid(b) or b.health <= 0 or b.tribe_id == g.tribe_id or not b.is_attackable():
				continue
			var d: float = b.footprint_distance_to(Vector2(g.position.x, g.position.z))
			if d <= g.aggro_radius() and d < best:
				best = d
				goal = b.center_world()
	if goal == Vector3.INF:
		return
	var want: Vector3 = _flat(goal - g.position).normalized()
	if want == Vector3.ZERO or forward().dot(want) >= cos(deg_to_rad(Balance.GOLEM_SIT_TURN_MIN_DEG)):
		return
	g.facing = want
	turning = true
