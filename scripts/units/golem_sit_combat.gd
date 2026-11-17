class_name GolemSitCombat extends RefCounted

## SITZANGRIFFE eines Golems (Nutzervorgabe 2026-11-17, plans/10l_golem_sitting.md).
## Gilt fuer alle drei Golems, nur in der Haltung STANCE_SIT. Die Golemin bekommt im
## Sitzen keine Befehle — sie greift von selbst an, was ihre Glieder vom Platz aus
## erreichen, und dreht sich (langsam) nach Feinden, die keines erreicht.
##
## ZWEI KANAELE, BEINE und ARME, jeder mit eigener Ausholzeit und Abklingzeit; beide
## duerfen gleichzeitig angreifen:
##  * Fuss-Stampfer (Beine, links ODER rechts): gezielt wie der Luftschlag — der Fuss
##    trifft das Ziel dort, wo es steht, und alles im Kreis des Handschlags darum.
##    Reichweite reach(), gemessen von der Ruhelage der Fuesse, nur nach vorn im
##    Halbkreis (wohin die Fuesse zeigen). Linker Fuss fuer Ziele links, rechter rechts.
##  * Bein strecken (Beine): eine lange Schneise geradeaus von den Fuessen,
##    GOLEM_SIT_KICK_REACH_SHARE x reach() lang, so breit wie die Tritt-Schneise. Die
##    Arme duerfen gleichzeitig angreifen.
##  * Arm-Wischer (Arme, immer nur EIN Arm): gezielt wie der Luftschlag, Kreis des
##    Handschlags um das Ziel. Erreichbar ist ein KEGEL seitlich und leicht hinter dem
##    Koerper, von der Ruhelage der Hand aus: Reichweite reach(), Achse
##    GOLEM_SIT_ARM_CONE_BACK_DEG nach hinten gedreht, halber Oeffnungswinkel
##    GOLEM_SIT_ARM_CONE_HALF_DEG. Linker Arm fuer Ziele links, rechter rechts.
## GROSSE ANGRIFFE (brauchen und sperren beide Kanaele):
##  * Po-Huepfer: die Sitzflaeche (GOLEM_SIT_HOP_AREA_FACTOR so gross) — sperrt Arme
##    und Beine.
##  * Doppelklatscher: beide Haende schlagen neben ihr auf (Kreis des Handschlags um
##    jede Hand) — sperrt die Beine.
##  * Doppelstampfer: beide Fuesse heben kurz ab und schlagen auf (Kreis um die Fuesse,
##    GOLEM_SIT_DOUBLE_STOMP_RADIUS_SHARE x Handschlag-Radius) — sperrt die Arme.
## Waehrend sie sich dreht, greift sie nicht an (und beginnt keine Drehung, solange ein
## Angriff ausholt).
##
## Werte (Schaden, Takt, Ausholzeit, Zielzahl) borgt jeder Sitzangriff vorerst von
## einem Stehangriff (VORSCHLAG, Nutzer legt fest): Stampfer und Wischer wie der
## Handschlag, Bein strecken wie der Tritt, Doppelklatscher und Doppelstampfer wie das
## Trommeln (alle drei Schlaege in einem), Po-Huepfer doppelter Sprung (= 4 x Trampeln).
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
const KINDS: Array[StringName] = [STOMP_L, STOMP_R, KICK_L, KICK_R, WIPE_L, WIPE_R,
	HOP, CLAP, DOUBLE_STOMP]

const CH_LEGS: int = 0
const CH_ARMS: int = 1
## How often a free channel looks for something to strike (seconds).
const THINK_INTERVAL: float = 0.25
## Enemies looked at as impact points of an aimed attack (the nearest ones).
const AIM_CANDIDATES: int = 12

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
## Last landings (tests, diagnostics): kind -> victims struck.
var last_struck: Dictionary = {}


func _init(p_golem: Golem) -> void:
	g = p_golem


func reset() -> void:
	pending = [&"", &""]
	pending_time = [0.0, 0.0]
	aim = [Vector3.INF, Vector3.INF]
	cooldown = [0.0, 0.0]
	turning = false
	_think = 0.0


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


## The standing attack whose numbers it borrows (see the class doc).
static func model_of(kind: StringName) -> StringName:
	if kind == KICK_L or kind == KICK_R:
		return Golem.ATTACK_KICK
	if kind == CLAP or kind == DOUBLE_STOMP:
		return Golem.ATTACK_DRUM
	if kind == HOP:
		return Golem.ATTACK_STOMP
	return Golem.ATTACK_SLAM


static func is_aimed(kind: StringName) -> bool:
	return kind == STOMP_L or kind == STOMP_R or kind == WIPE_L or kind == WIPE_R


func damage(kind: StringName) -> int:
	if kind == HOP:
		return 2 * g.attack_damage(Golem.ATTACK_STOMP)
	return g.attack_damage(model_of(kind))


func max_targets(kind: StringName) -> int:
	return g.max_targets_of(model_of(kind))


func cooldown_of(kind: StringName) -> float:
	return g.cooldown_for(model_of(kind))


func windup_of(kind: StringName) -> float:
	return g.current_windup(model_of(kind))


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


## Can the foot reach `p`? Within reach() of the feet, in the half circle ahead.
func in_foot_zone(p: Vector3) -> bool:
	var d: Vector3 = _flat(p - feet_point())
	return d.length() <= g.reach() and d.dot(forward()) >= 0.0


## Which foot / arm strikes at `p`: +1 left, -1 right.
func side_of(p: Vector3) -> float:
	return 1.0 if _flat(p - g.position).dot(left()) >= 0.0 else -1.0


## The axis of the arm's cone on `side`: straight out to that side, turned
## GOLEM_SIT_ARM_CONE_BACK_DEG backwards.
func arm_axis(side: float) -> Vector3:
	var a: float = deg_to_rad(Balance.GOLEM_SIT_ARM_CONE_BACK_DEG)
	return (left() * side * cos(a) - forward() * sin(a)).normalized()


## Can the arm of `side` reach `p`? Within reach() of the resting hand, inside the cone.
func in_arm_zone(p: Vector3, side: float) -> bool:
	var d: Vector3 = _flat(p - hand_point(side))
	var dist: float = d.length()
	if dist > g.reach():
		return false
	if dist < 0.001:
		return true
	return d.dot(arm_axis(side)) / dist >= cos(deg_to_rad(Balance.GOLEM_SIT_ARM_CONE_HALF_DEG))


## The leg's long lane: from the feet straight ahead, GOLEM_SIT_KICK_REACH_SHARE x
## reach() long, as wide as the kick's lane.
func in_kick_lane(p: Vector3) -> bool:
	var d: Vector3 = _flat(p - feet_point())
	var along: float = d.dot(forward())
	var half_w: float = Balance.GOLEM_KICK_WIDTH * 0.5 * g.reach_factor()
	return along >= 0.0 and along <= g.reach() * Balance.GOLEM_SIT_KICK_REACH_SHARE \
		and absf(d.dot(left())) <= half_w


## Is `p` struck by the attack `kind` landing at `at` (aimed attacks)?
func in_area(kind: StringName, p: Vector3, at: Vector3) -> bool:
	match kind:
		STOMP_L, STOMP_R, WIPE_L, WIPE_R:
			return _flat(p - at).length() <= g.slam_radius()
		KICK_L, KICK_R:
			return in_kick_lane(p)
		CLAP:
			return _flat(p - hand_point(1.0)).length() <= g.slam_radius() \
				or _flat(p - hand_point(-1.0)).length() <= g.slam_radius()
		DOUBLE_STOMP:
			return _flat(p - feet_point()).length() \
				<= g.slam_radius() * Balance.GOLEM_SIT_DOUBLE_STOMP_RADIUS_SHARE
		HOP:
			var d: Vector3 = _flat(p - g.position)
			var half: Vector2 = g.seat_half_extent() * Balance.GOLEM_SIT_HOP_AREA_FACTOR
			return absf(d.dot(left())) <= half.x and absf(d.dot(forward())) <= half.y
	return false


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# --- Ticking -------------------------------------------------------------------------

func is_busy() -> bool:
	return pending[CH_LEGS] != &"" or pending[CH_ARMS] != &""


func channel_free(ch: int) -> bool:
	return pending[ch] == &"" and cooldown[ch] <= 0.0


## One tick while she sits: wound-up attacks land, free channels pick the next one,
## or she turns toward an enemy no limb reaches.
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


## Picks what to strike with the free channels: the best plan by damage per second —
## a big attack (both channels) against the best single attack of each free channel
## together. Nothing within reach: turn toward the nearest enemy in aggro range.
func _choose() -> void:
	var legs: bool = channel_free(CH_LEGS)
	var arms: bool = channel_free(CH_ARMS)
	if not legs and not arms:
		return
	var foes: Array[Unit] = _foes_around()
	if foes.is_empty():
		return
	var best_legs: Dictionary = _best_of([STOMP_L, STOMP_R, KICK_L, KICK_R], foes) if legs else {}
	var best_arms: Dictionary = _best_of([WIPE_L, WIPE_R], foes) if arms else {}
	var single: float = float(best_legs.get("value", 0.0)) + float(best_arms.get("value", 0.0))
	if legs and arms and not is_busy():
		var big: Dictionary = _best_of([HOP, CLAP, DOUBLE_STOMP], foes)
		if float(big.get("value", 0.0)) > single:
			_wind_up(big.kind, big.at)
			return
	if not best_legs.is_empty():
		_wind_up(best_legs.kind, best_legs.at)
	if not best_arms.is_empty():
		_wind_up(best_arms.kind, best_arms.at)
	if best_legs.is_empty() and best_arms.is_empty() and not is_busy():
		_maybe_turn(foes)


## Enemy units around her that any sit attack could ever reach, or that she could
## turn toward (aggro radius around the seat).
func _foes_around() -> Array[Unit]:
	var out: Array[Unit] = []
	if g.path_service == null:
		return out
	var radius: float = maxf(g.aggro_radius(),
		g.seat_back_m() + g.reach() * (Balance.GOLEM_SIT_KICK_REACH_SHARE + 1.0))
	for u in g.path_service.get_units_in_radius(g.position, radius):
		if u == g or u.state == Unit.State.DEAD or u.doomed or u.tribe_id == g.tribe_id:
			continue
		if not u.is_targetable() or u.is_airborne() or u is CrewedVehicle:
			continue
		out.append(u)
	return out


## The best of `kinds` right now: {kind, at, value} (empty = none strikes anything).
func _best_of(kinds: Array, foes: Array[Unit]) -> Dictionary:
	var best: Dictionary = {}
	for kind in kinds:
		var options: Array[Vector3] = _aim_points(kind, foes)
		for at in options:
			if channels_of(kind).size() == 2 					and victims(kind, at, foes).size() < Balance.GOLEM_SIT_BIG_MIN_TARGETS:
				continue   # the big ones are area attacks
			var v: float = _value(kind, at, foes)
			if v > float(best.get("value", 0.0)):
				best = {"kind": kind, "at": at, "value": v}
	return best


## Where an attack could land: for aimed ones every (near) enemy in its zone, for the
## others their fixed place (INF = it lands where it is).
func _aim_points(kind: StringName, foes: Array[Unit]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if not is_aimed(kind):
		out.append(Vector3.INF)
		return out
	var side: float = 1.0 if kind == STOMP_L or kind == WIPE_L else -1.0
	var near: Array[Unit] = foes.duplicate()
	var origin: Vector3 = feet_point() if kind == STOMP_L or kind == STOMP_R else hand_point(side)
	near.sort_custom(func(a: Unit, b: Unit) -> bool:
		return _flat(a.position - origin).length_squared() < _flat(b.position - origin).length_squared())
	for u in near:
		if out.size() >= AIM_CANDIDATES:
			break
		if side_of(u.position) != side:
			continue
		var ok: bool = in_foot_zone(u.position) if kind == STOMP_L or kind == STOMP_R \
			else in_arm_zone(u.position, side)
		if ok:
			out.append(u.position)
	return out


## Damage per second the attack would bring: what it strikes (no overkill, target
## cap) over its cooldown.
func _value(kind: StringName, at: Vector3, foes: Array[Unit]) -> float:
	var dmg: int = damage(kind)
	var sum: float = 0.0
	for u in victims(kind, at, foes):
		sum += float(mini(dmg, u.health))
	return sum / maxf(cooldown_of(kind), 0.05)


## Who the attack `kind` landing at `at` strikes: enemies in its area, the nearest to
## the impact first, up to its target cap.
func victims(kind: StringName, at: Vector3, foes: Array[Unit]) -> Array[Unit]:
	var hit: Array[Unit] = []
	for u in foes:
		if is_instance_valid(u) and u.state != Unit.State.DEAD and in_area(kind, u.position, at):
			hit.append(u)
	var centre: Vector3 = at
	if centre == Vector3.INF:
		centre = g.position if kind == HOP or kind == CLAP else feet_point()
	hit.sort_custom(func(a: Unit, b: Unit) -> bool:
		return _flat(a.position - centre).length_squared() < _flat(b.position - centre).length_squared())
	if hit.size() > max_targets(kind):
		hit.resize(max_targets(kind))
	return hit


## Starts the attack: its channels are busy until it lands, its cooldown runs from now.
func _wind_up(kind: StringName, at: Vector3) -> void:
	var t: float = windup_of(kind)
	for ch in channels_of(kind):
		pending[ch] = kind
		pending_time[ch] = t
		aim[ch] = at
		cooldown[ch] = cooldown_of(kind)
	g.sit_attack_started(kind, t)


func _land(kind: StringName, at: Vector3) -> void:
	var dmg: int = damage(kind)
	var struck: Array[Unit] = victims(kind, at, _foes_around())
	for u in struck:
		var hp: int = Golem.kill_hp_of(u)
		u.take_damage(dmg, g)
		if not is_instance_valid(u) or u.state == Unit.State.DEAD or u.doomed:
			g._credit_kill(hp)
	last_struck[kind] = struck
	g._play_strike_sfx(model_of(kind))


## Nothing in reach: she turns (slowly) toward the nearest enemy within her aggro
## radius, if it lies more than GOLEM_SIT_TURN_MIN_DEG off her heading.
func _maybe_turn(foes: Array[Unit]) -> void:
	var nearest: Unit = null
	var best: float = INF
	for u in foes:
		var d: float = _flat(u.position - g.position).length()
		if d <= g.aggro_radius() and d < best:
			best = d
			nearest = u
	if nearest == null:
		return
	var want: Vector3 = _flat(nearest.position - g.position).normalized()
	if want == Vector3.ZERO or forward().dot(want) >= cos(deg_to_rad(Balance.GOLEM_SIT_TURN_MIN_DEG)):
		return
	g.facing = want
	turning = true
