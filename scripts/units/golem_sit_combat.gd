class_name GolemSitCombat extends RefCounted

## SITZANGRIFFE eines Golems (Nutzervorgabe 2026-11-17, plans/10l_golem_sitting.md).
## Gilt fuer alle drei Golems, nur in der Haltung STANCE_SIT. Die Golemin bekommt im
## Sitzen keine Befehle — sie greift von selbst an, was ihre Glieder vom Platz aus
## erreichen, und dreht sich (langsam) nach Feinden, die keines erreicht.
##
## ZWEI KANAELE, BEINE und ARME, jeder mit eigener Ausholzeit und Abklingzeit; beide
## duerfen gleichzeitig angreifen. Zonen nach den Vorgaben vom 2026-11-17/18 (Lage in
## Balance.GOLEM_SIT_*, gemessen an den Clips); jeder Sitzangriff hat seine eigenen Werte —
## Schaden, Ziele, Abklingzeit, Ausholzeit, Flaeche — in Balance.GOLEM_SIT_ATTACKS, darauf die
## Sitzfaktoren GOLEM_SIT_MULT_* fuer alle gleich (Nutzervorgabe 2026-11-19):
##  1. Fuss-Stampfer (Beine, links ODER rechts): Kreis um die Stelle, an der der Schuh
##     landet, nicht hinter die Ferse des ruhenden Schuhs.
##  2. Bein strecken (Beine, links ODER rechts): Schneise vom Hueftgelenk bis zur Spitze des
##     gestreckten Schuhs, so breit wie das Bein.
##  5. Arm-Wischer (Arme, immer nur EIN Arm): Kegel neben ihr auf seiner Seite, etwas hinter
##     den Ruecken.
##  7. Handschlag seitlich (Arme, links ODER rechts; Nutzervorgabe 2026-11-18): eine Schuh-Hand
##     schlaegt von oben flach auf den blinden Fleck aussen neben Oberschenkel und Knie (vor dem
##     Wischer, hinter dem Doppelstampfer). Kreis um die gemessene Aufschlagstelle. Kopf und
##     Oberkoerper drehen mit.
## Welche Seite: die, deren Angriff mehr bringt; bei Gleichstand die, deren Aufschlag
## naeher an den getroffenen Feinden liegt.
## GROSSE ANGRIFFE (brauchen und sperren beide Kanaele, erst ab GOLEM_SIT_BIG_MIN_TARGETS):
##  3. Po-Klatscher (sit_hop): Kreis um die Mitte der Sitzflaeche (alles unter ihr).
##  4. Doppelstampfer: Kreis um die Stelle, an der beide Schuhe landen (reicht ein Stueck
##     hinter die Fuesse).
##  6. Handstampfer hinten (sit_clap): Kreis um jede Hand, nur hinter der Sitzmitte.
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
const HAND_SLAM_L: StringName = &"sit_hand_slam_l"
const HAND_SLAM_R: StringName = &"sit_hand_slam_r"
## The stretch when she grows on the seat (clip sit_grow): not chosen like the attacks,
## it strikes once per growth (grow_strike) — like the kick, in both legs' lanes.
const GROW: StringName = &"sit_grow"
const KINDS: Array[StringName] = [STOMP_L, STOMP_R, KICK_L, KICK_R, WIPE_L, WIPE_R,
	HOP, CLAP, DOUBLE_STOMP, HAND_SLAM_L, HAND_SLAM_R]
## The single attacks of each channel (the choice weighs them against each other).
const LEG_KINDS: Array[StringName] = [STOMP_L, STOMP_R, KICK_L, KICK_R]
const ARM_KINDS: Array[StringName] = [WIPE_L, WIPE_R, HAND_SLAM_L, HAND_SLAM_R]

const CH_LEGS: int = 0
const CH_ARMS: int = 1
## How often a free channel looks for something to strike (seconds). A channel that just
## came free looks at once (user report 2026-11-19: up to this long the idle showed between attacks).
const THINK_INTERVAL: float = 0.25
## COMBAT REST (user report 2026-11-19): while a channel's attacks are possible, its limbs (arms with
## neck, head and upper body; legs) hold the rest pose instead of playing sit_idle between attacks —
## the attack clips start and end in it (tests/diag_golem_sit_rest_pose.gd). "Possible": a foe in
## reach of one of its attacks at the last choice, or its last attack's cooldown ran out less than
## this long ago (seconds). GolemSitAnim blends it in and out.
const COMBAT_REST_HOLD: float = 1.5

var g: Golem = null
## Per channel: the attack wound up (&"" = none), seconds to its impact, where it
## lands, and the cooldown left.
var pending: Array[StringName] = [&"", &""]
var pending_time: Array[float] = [0.0, 0.0]
var aim: Array[Vector3] = [Vector3.INF, Vector3.INF]
var cooldown: Array[float] = [0.0, 0.0]
## She is turning toward an enemy none of her limbs reaches (_turn_goal: that unit or
## building — gone, dead or out of her aggro radius, she stops turning).
var turning: bool = false
var _turn_goal: Object = null
## Turning for a better plan (user spec 2026-11-18): the direction she turns to and what that
## plan strikes — all of it dead or gone, she stops turning.
var _turn_dir: Vector3 = Vector3.ZERO
var _turn_targets: Array = []
## The way she turns (user spec 2026-11-18: only through headings her limbs can rest in): +1 / -1
## for the direction of the angle (atan2(x, z)), and the heading she turns to.
var _turn_sign: float = 0.0
var _turn_want: Vector3 = Vector3.ZERO
## Whether she turns out of a pose that has become impossible (grown, or the ground changed:
## _escape_pose).
var _turn_escape: bool = false
## Enemy ground vehicles around her, fetched with every search for foes (_foes_around).
var _vehicles: Array = []
var _sweep_sign: float = 0.0
var _arc: Vector2 = Vector2(TAU, TAU)
## The round over the other headings (_turn_sweep): next one to weigh (0 = none running), the
## heading it is measured from, and the best so far.
var _sweep_i: int = 0
var _sweep_from: Vector3 = Vector3.ZERO
var _sweep_v: float = 0.0
var _sweep_dir: Vector3 = Vector3.ZERO
var _sweep_parts: Array = []
## Her limbs' places and the area sizes, kept while heading, position and size stay the same
## (in_area runs for every target and, in the choice, for many headings).
var _ck: Array = [Vector3.INF, Vector3.INF, -1.0]
var _c_fw: Vector3
var _c_lf: Vector3
var _c_feet: Vector3
var _c_sx: float
var _c_sz: float
var _c_stomp: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]   # left, right
var _c_hand: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _c_dstomp: Vector3
var _c_stomp_r: float
var _c_wipe_r: float
var _c_hop_r: float
var _c_clap_r: float
var _c_dstomp_r: float
var _c_hslam: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]   # left, right
var _c_hslam_r: float
var _c_kick_out: float
var _think: float = 0.0
## Counts her looks (each _choose): what is judged once per look (Golem._foe_closing_in) keys on it.
var think_round: int = 0
## Guard against a turn that hangs (bugfix 2026-11-18): seconds without progress, angle turned in this
## turn without an attack, the heading last tick, seconds no new turn may start.
var _turn_stall: float = 0.0
var _turn_spun: float = 0.0
var _turn_last: Vector3 = Vector3.ZERO
var turn_block: float = 0.0
## Seconds her choices have found nothing within reach in a row (the crab walk waits a little for foes
## that are nearly there, Golem.sit_nothing_in_reach).
var nothing_for: float = 0.0
## Last landings (tests, diagnostics): kind -> victims struck, kind -> buildings struck.
var last_struck: Dictionary = {}
var last_struck_buildings: Dictionary = {}
## Seconds until the stretch of growing on the seat strikes (0 = none owed).
var _grow_left: float = 0.0
## Combat rest per channel (COMBAT_REST_HOLD): seconds since its last attack started, that attack's
## cooldown, and whether one of its attacks reached a foe at the last choice.
var _since_attack: Array[float] = [INF, INF]
var _attack_cycle: Array[float] = [0.0, 0.0]
var _reach: Array[bool] = [false, false]


func _init(p_golem: Golem) -> void:
	g = p_golem


## She gets up into the crab stand: the turn ends, the cooldowns keep running (cool) — a reset would give
## her every sit attack fresh at the next touch-down (bug report 2026-11-18: a burst of damage each time she
## sat down from the crab walk).
func leave_seat() -> void:
	_end_turn()
	_think = 0.0
	nothing_for = 0.0


## While she crawls: the cooldowns run on.
func cool(delta: float) -> void:
	for ch in [CH_LEGS, CH_ARMS]:
		cooldown[ch] = maxf(cooldown[ch] - delta, 0.0)


func reset() -> void:
	pending = [&"", &""]
	pending_time = [0.0, 0.0]
	aim = [Vector3.INF, Vector3.INF]
	cooldown = [0.0, 0.0]
	_end_turn()
	_think = 0.0
	_grow_left = 0.0
	_since_attack = [INF, INF]
	_attack_cycle = [0.0, 0.0]
	_reach = [false, false]


## Should the limbs of channel `ch` hold the rest pose (COMBAT_REST_HOLD)?
func rest_wanted(ch: int) -> bool:
	return pending[ch] != &"" or _reach[ch] or _since_attack[ch] < _attack_cycle[ch] + COMBAT_REST_HOLD


# --- What each attack is -------------------------------------------------------------

## Colour group of an attack in the debug view: "legs", "arms" or "big".
static func debug_group(kind: StringName) -> String:
	if kind == HOP or kind == CLAP or kind == DOUBLE_STOMP:
		return "big"
	if kind == WIPE_L or kind == WIPE_R or kind == HAND_SLAM_L or kind == HAND_SLAM_R:
		return "arms"
	return "legs"


## Which channels an attack needs (true = it uses or blocks that channel).
static func channels_of(kind: StringName) -> Array[int]:
	if kind == HOP or kind == CLAP or kind == DOUBLE_STOMP:
		return [CH_LEGS, CH_ARMS]
	if kind == WIPE_L or kind == WIPE_R or kind == HAND_SLAM_L or kind == HAND_SLAM_R:
		return [CH_ARMS]
	return [CH_LEGS]


## The animation layer it plays on (GolemSitAnim): one leg, one arm, or the body.
static func layer_of(kind: StringName) -> int:
	if kind == HOP or kind == CLAP or kind == DOUBLE_STOMP:
		return GolemSitAnim.LAYER_FULL
	if kind == WIPE_L or kind == WIPE_R:
		return GolemSitAnim.LAYER_ARMS
	if kind == HAND_SLAM_L or kind == HAND_SLAM_R:
		return GolemSitAnim.LAYER_ARM_TORSO   # both arms, upper body, neck and head (the clip leans)
	return GolemSitAnim.LAYER_LEGS


## Row of each sit attack in Balance.GOLEM_SIT_ATTACKS (left and right share one).
const TABLE_KEY: Dictionary = {
	STOMP_L: &"sit_stomp", STOMP_R: &"sit_stomp", KICK_L: &"sit_kick", KICK_R: &"sit_kick",
	WIPE_L: &"sit_wipe", WIPE_R: &"sit_wipe", HAND_SLAM_L: &"sit_hand_slam", HAND_SLAM_R: &"sit_hand_slam",
	HOP: &"sit_hop", DOUBLE_STOMP: &"sit_double_stomp", CLAP: &"sit_clap",
}


## The row of the sit attack `kind` in the attack table (user spec 2026-11-19: the sit
## attacks are attacks of their own, with their own base values).
static func sit_attack(kind: StringName) -> Dictionary:
	return Balance.GOLEM_SIT_ATTACKS[TABLE_KEY[kind]]


## The standing attack it sounds like (and plays the strike sound of).
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


## Damage (user spec 2026-11-19): its damage at 30 m (sit table) plus what this golem gains for its category
## from growth steps that began at 30 m or more (Golem.sit_damage_growth) — category trample: a multiple of
## the trample damage (from the height) —, times GOLEM_SIT_MULT_DAMAGE and the golem's sit modifier. The
## stretch on the seat (GROW) is no attack of the table: one trample tick (user spec 2026-11-17).
func damage(kind: StringName) -> int:
	if kind == GROW:
		return g.trample_damage()
	var row: Dictionary = sit_attack(kind)
	var category: StringName = row["category"]
	var dmg: float = float(row["damage"]) * float(g.trample_damage()) if category == Golem.CATEGORY_TRAMPLE 		else float(row["damage"]) + g.sit_damage_growth(category)
	return roundi(dmg * Balance.GOLEM_SIT_MULT_DAMAGE * float(g.sit_mod()["damage"]))


## Target cap: its share (column targets) of the golem's base count, times GOLEM_SIT_MULT_TARGETS, rounded down, at least 1.
func max_targets(kind: StringName) -> int:
	if kind == GROW:
		return 2 * g.max_targets_of(Golem.ATTACK_KICK)   # both legs' lanes, each with the kick's cap
	return maxi(int(floor(float(g.max_targets()) * float(sit_attack(kind)["targets"]) / 100.0
		* Balance.GOLEM_SIT_MULT_TARGETS + 0.000001)), 1)


## Cooldown: its own at 30 m (sit table), grown with her rhythm (Golem.sit_rhythm), times GOLEM_SIT_MULT_COOLDOWN
## (seated she strikes more easily, user spec 2026-11-17) and the golem's sit modifier.
func cooldown_of(kind: StringName) -> float:
	return float(sit_attack(kind)["cooldown"]) * g.sit_rhythm() * Balance.GOLEM_SIT_MULT_COOLDOWN 		* float(g.sit_mod()["cooldown"])


## Wind-up (user spec 2026-11-19): the clip fills the attack's cooldown, so the impact — and
## the damage — falls at the impact's share of the clip, of the cooldown. GolemSitAnim.fire
## plays the clip so that its impact meets this wind-up.
func windup_of(kind: StringName) -> float:
	return cooldown_of(kind) * float(GolemSitAnim.SIT_CLIP_IMPACT[kind]) / float(GolemSitAnim.SIT_CLIP_LENGTH[kind])


## Size of the area of the sit attack `kind`: its own at 30 m (sit table), grown exactly with her body
## (Golem.sit_body_ratio), times GOLEM_SIT_MULT_AREA (seated the areas are smaller, user spec 2026-11-17) and the
## golem's sit modifier.
func area_of(kind: StringName) -> float:
	return float(sit_attack(kind)["area"]) * g.sit_body_ratio() * _area_mult()


func _area_mult() -> float:
	return Balance.GOLEM_SIT_MULT_AREA * float(g.sit_mod()["area"])


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


## Radius of the foot stomp's circle. Like every sit zone it grows exactly with her body (user
## spec 2026-11-18; area_of).
func stomp_radius() -> float:
	return area_of(STOMP_L)


## How far the wipe reaches from the middle of the seat (the standing reach at her first
## seated size, grown with the body).
func wipe_reach() -> float:
	return area_of(WIPE_L)


## How far ahead of feet_point p lies (negative: behind).
func _ahead_of_feet(p: Vector3) -> float:
	return _flat(p - feet_point()).dot(forward())


## Fills the cache of her limbs' places for the current heading, position and size.
func _frame() -> void:
	var h: Vector3 = g.heading()
	var sf: float = g.size_factor()
	if h == _ck[0] and g.position == _ck[1] and sf == _ck[2]:
		return
	_ck = [h, g.position, sf]
	_c_fw = forward()
	_c_lf = left()
	_c_feet = feet_point()
	_c_sx = _sx()
	_c_sz = _sz()
	_c_stomp = [stomp_point(1.0), stomp_point(-1.0)]
	_c_hand = [hand_point(1.0), hand_point(-1.0)]
	_c_dstomp = double_stomp_point()
	_c_stomp_r = stomp_radius()
	_c_wipe_r = wipe_reach()
	_c_hop_r = hop_radius()
	_c_clap_r = clap_radius()
	_c_dstomp_r = double_stomp_radius()
	_c_hslam = [hand_slam_point(1.0), hand_slam_point(-1.0)]
	_c_hslam_r = hand_slam_radius()
	# The lane: the leg GOLEM_SIT_KICK_SIDE beside her middle, half its width (the sit table's area) beyond.
	_c_kick_out = Balance.GOLEM_SIT_KICK_SIDE * _c_sx * _area_mult() + area_of(KICK_L) * 0.5


## The leg's lane on side: from her hip joint to the tip of the stretched shoe, as
## wide as the leg — and inward up to her middle (the knees touch; user report
## 2026-11-17: a foe between her shoes was never struck by a single attack).
func in_kick_lane(p: Vector3, side: float) -> bool:
	_frame()
	var d: Vector3 = _flat(p - _c_feet)
	var along: float = d.dot(_c_fw)
	var out: float = d.dot(_c_lf) * side
	return along >= -Balance.GOLEM_SIT_KICK_FROM * _c_sz and along <= Balance.GOLEM_SIT_KICK_TO * _c_sz \
		and out >= 0.0 and out <= _c_kick_out


## The wipe's cone on side: beside the seat within reach(), from GOLEM_SIT_WIPE_BACK_DEG
## behind straight out forward to her pelvis — no further ahead than
## GOLEM_SIT_WIPE_FRONT before the middle of the seat (user report 2026-11-17: it
## reached out to her legs).
func in_wipe_cone(p: Vector3, side: float) -> bool:
	_frame()
	var d: Vector3 = _flat(p - g.position)
	var dist: float = d.length()
	if dist > _c_wipe_r or dist < 0.001:
		return dist < 0.001
	var out: float = d.dot(_c_lf) * side
	if out <= 0.0:
		return false
	var ahead: float = d.dot(_c_fw)
	if ahead > Balance.GOLEM_SIT_WIPE_FRONT * _c_sz + out * tan(deg_to_rad(Balance.GOLEM_SIT_WIPE_FRONT_DEG)):
		return false   # the front edge leans GOLEM_SIT_WIPE_FRONT_DEG forward
	return rad_to_deg(atan2(ahead, out)) >= -Balance.GOLEM_SIT_WIPE_BACK_DEG


## Radius of the po clap's circle around the middle of the seat.
func hop_radius() -> float:
	return area_of(HOP)


## Where the shoe-hand of side comes down in the side hand slam (clip sit_hand_slam_l/_r, measured
## on all three models: beside her thigh and knee, out of reach of every other sit attack).
func hand_slam_point(side: float) -> Vector3:
	return _off(feet_point(), side, Balance.GOLEM_SIT_HAND_SLAM_LAND.x, Balance.GOLEM_SIT_HAND_SLAM_LAND.y)


## Radius of the side hand slam's circle (user spec 2026-11-18: 2/3 of the foot stomp's, then 5 % more).
func hand_slam_radius() -> float:
	return area_of(HAND_SLAM_L)


## Radius of the circles of the hand stomp behind her (around each hand).
func clap_radius() -> float:
	return area_of(CLAP)


## Radius of the double stomp's circle.
func double_stomp_radius() -> float:
	return area_of(DOUBLE_STOMP)


## Where the double stomp's circle lies: about the heels of the resting shoes.
func double_stomp_point() -> Vector3:
	return _off(feet_point(), 1.0, 0.0, Balance.GOLEM_SIT_DOUBLE_STOMP_LAND)


## +1 for the attacks of her left side, -1 for the right, 0 for the others.
static func side_of_kind(kind: StringName) -> float:
	if kind == STOMP_L or kind == KICK_L or kind == WIPE_L or kind == HAND_SLAM_L:
		return 1.0
	if kind == STOMP_R or kind == KICK_R or kind == WIPE_R or kind == HAND_SLAM_R:
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
		HAND_SLAM_L, HAND_SLAM_R:
			return hand_slam_point(side)
		KICK_L, KICK_R:
			return _off(feet_point(), side, Balance.GOLEM_SIT_KICK_SIDE, 0.0)
		DOUBLE_STOMP:
			return double_stomp_point()
		CLAP:
			return g.position - forward() * (_flat(g.position - hand_point(1.0)).dot(forward()))
	return g.position


## A circle (x, z = centre, w = radius) that surely holds the whole area of `kind` — a cheap
## first test before in_area (the choice weighs many headings, user spec 2026-11-18).
func bound_of(kind: StringName) -> Vector3:
	_frame()
	var side: float = side_of_kind(kind)
	var c: Vector3 = g.position
	var r: float = INF
	match kind:
		STOMP_L, STOMP_R:
			c = _c_stomp[0 if side > 0.0 else 1]
			r = _c_stomp_r
		WIPE_L, WIPE_R:
			r = _c_wipe_r
		HAND_SLAM_L, HAND_SLAM_R:
			c = _c_hslam[0 if side > 0.0 else 1]
			r = _c_hslam_r
		KICK_L, KICK_R:
			var back: float = Balance.GOLEM_SIT_KICK_FROM * _c_sz
			var ahead: float = Balance.GOLEM_SIT_KICK_TO * _c_sz
			c = _c_feet + _c_fw * ((ahead - back) * 0.5) + _c_lf * (side * _c_kick_out * 0.5)
			r = Vector2((ahead + back) * 0.5, _c_kick_out * 0.5).length()
		CLAP:
			r = _flat(_c_hand[0] - g.position).length() + _c_clap_r
		DOUBLE_STOMP:
			c = _c_dstomp
			r = _c_dstomp_r
		HOP:
			r = _c_hop_r
	return Vector3(c.x, c.z, r + 0.01)


## Is p struck by the attack kind? (at is kept for callers; every sit attack
## lands at its fixed place.)
func in_area(kind: StringName, p: Vector3, at: Vector3 = Vector3.INF) -> bool:
	_frame()
	var side: float = side_of_kind(kind)
	match kind:
		STOMP_L, STOMP_R:
			return _flat(p - _c_stomp[0 if side > 0.0 else 1]).length() <= _c_stomp_r \
				and _flat(p - _c_feet).dot(_c_fw) >= -Balance.GOLEM_SIT_HEEL_BACK * _c_sz
		WIPE_L, WIPE_R:
			return in_wipe_cone(p, side)
		HAND_SLAM_L, HAND_SLAM_R:
			return _flat(p - _c_hslam[0 if side > 0.0 else 1]).length() <= _c_hslam_r
		KICK_L, KICK_R:
			return in_kick_lane(p, side)
		GROW:
			return in_kick_lane(p, 1.0) or in_kick_lane(p, -1.0)
		CLAP:
			if _flat(p - g.position).dot(_c_fw) > 0.0:
				return false   # only behind the middle of the seat: her back
			return _flat(p - _c_hand[0]).length() <= _c_clap_r or _flat(p - _c_hand[1]).length() <= _c_clap_r
		DOUBLE_STOMP:
			return _flat(p - _c_dstomp).length() <= _c_dstomp_r
		HOP:
			return _flat(p - g.position).length() <= _c_hop_r
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
	turn_block = maxf(turn_block - delta, 0.0)
	var was_free: Array[bool] = [channel_free(CH_LEGS), channel_free(CH_ARMS)]
	for ch in [CH_LEGS, CH_ARMS]:
		_since_attack[ch] += delta
		cooldown[ch] = maxf(cooldown[ch] - delta, 0.0)
		if pending[ch] == &"":
			continue
		pending_time[ch] -= delta
		if pending_time[ch] <= 0.0:
			var kind: StringName = pending[ch]
			_land(kind, aim[ch])
			for c in channels_of(kind):
				pending[c] = &""
	for ch in [CH_LEGS, CH_ARMS]:
		if not was_free[ch] and channel_free(ch):
			_think = 0.0   # it just came free: choose at once, no idle between two attacks
	if _grow_left > 0.0:
		_grow_left -= delta
		if _grow_left <= 0.0:
			_grow_left = 0.0
			_land(GROW, Vector3.INF)
	if g.sit_stretching():
		# She stretches (growing): no attack, the turn holds (user spec 2026-11-18).
		if turning:
			g.facing = g.heading()
			g.sit_turn_tick()
		return
	if turning and _turn_hangs(delta):
		# The turn makes no headway, or has gone all the way round without an attack (bug report
		# 2026-11-18: she turned on the spot for good): stop, no new turn for a while — not
		# stationary, she crawls to what is left in her aggro radius instead.
		g.facing = g.heading()
		g.sit_turn_tick()
		_end_turn()
		turn_block = Balance.GOLEM_SIT_TURN_BLOCK_TIME
		_think = THINK_INTERVAL
		g.sit_nothing_in_reach(_foes_around())
		return
	if turning:
		var goal: Vector3 = _turn_goal_point()
		if goal == Vector3.INF:
			# The one she turned to is dead or gone (user report 2026-11-18: she turned on to
			# a dead target): stop where she is, look again at once.
			g.facing = g.heading()
			g.sit_turn_tick()
			_end_turn()
			_think = 0.0
		else:
			var want: Vector3 = _flat(goal - g.position)
			if want.length_squared() > 0.0001 and not _turn_escape:
				_turn_want = want.normalized()   # follow it while it moves
			var next: Vector3 = Vector3.ZERO if g.is_turned_to(_turn_want, Balance.GOLEM_SIT_TURN_DONE_DEG) else _turn_step()
			if next == Vector3.ZERO:
				# Turned — or the next bit of the way is blocked (her limbs would rest on impossible ground).
				g.facing = g.heading()
				g.sit_turn_tick()
				_end_turn()
				_think = 0.0
			else:
				g.facing = next
				g.sit_turn_tick()
				_think -= delta
				if _think <= 0.0:
					_think = THINK_INTERVAL
					# No attack while she turns (user spec 2026-11-18: the turn was chosen by the damage
					# reckoning) — unless the situation changes: then she stops and chooses anew.
					if not _turn_escape and _situation_changed():
						g.facing = g.heading()
						g.sit_turn_tick()
						_end_turn()
						return
				return
	_think -= delta
	if _think > 0.0:
		return
	_think = THINK_INTERVAL
	think_round += 1
	if not is_busy() and not g.sit_heading_ok(g.heading()):
		_escape_pose()
		return
	_choose()


## Does the running turn hang? No headway for GOLEM_SIT_TURN_STALL_TIME, or a full round without a
## wound-up attack.
func _turn_hangs(delta: float) -> bool:
	var h: Vector3 = g.heading()
	if _turn_last == Vector3.ZERO:
		_turn_last = h
		return false
	var step: float = acos(clampf(h.dot(_turn_last), -1.0, 1.0))
	_turn_last = h
	_turn_spun += step
	if is_busy():
		_turn_spun = 0.0
	_turn_stall = _turn_stall + delta if step < deg_to_rad(0.5) * delta / 0.1 else 0.0
	return _turn_stall >= Balance.GOLEM_SIT_TURN_STALL_TIME or _turn_spun >= TAU


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
	if g._stretch_queued:
		return   # the stretch is owed: no new attack before it (it queues behind the running ones)
	if g.crab_order_pending():
		return   # an order waits for the crab walk: nothing new, she gets up once the wound-up ones land
	var legs: bool = channel_free(CH_LEGS)
	var arms: bool = channel_free(CH_ARMS)
	if not legs and not arms:
		return
	var foes: Array[Unit] = _foes_around()
	var builds: Array = _buildings_around()
	if foes.is_empty() and builds.is_empty() and _vehicles.is_empty():
		_reach = [false, false]
		if not is_busy():
			_maybe_turn(foes)   # maybe a building further off
			if not turning:
				nothing_for += THINK_INTERVAL
				g.sit_nothing_in_reach(foes)   # not stationary: her ordered target, crawling
			else:
				nothing_for = 0.0
		return
	if not is_busy() and g.crab_ship_waiting() and not _units_in_reach(foes):
		# An airship in her aggro radius goes before buildings and vehicles in reach — the strike from
		# the crab stand is the only way to hit it (bug report 2026-11-18). Units in reach go first.
		g.sit_nothing_in_reach(foes)
		if g.crab_target() != null:
			return
	if _turn_sweep(foes, builds):
		return
	var best_legs: Dictionary = _best_of(LEG_KINDS, foes, builds) if legs else {}
	var best_arms: Dictionary = _best_of(ARM_KINDS, foes, builds) if arms else {}
	if legs:
		_reach[CH_LEGS] = not best_legs.is_empty()
	if arms:
		_reach[CH_ARMS] = not best_arms.is_empty()
	var single: float = float(best_legs.get("value", 0.0)) + float(best_arms.get("value", 0.0))
	if legs and arms and not is_busy():
		var min_hit: int = Balance.GOLEM_SIT_BIG_MIN_TARGETS if single > 0.0 else 1
		var big: Dictionary = _best_of([HOP, CLAP, DOUBLE_STOMP], foes, builds, min_hit)
		if float(big.get("value", 0.0)) > single:
			_wind_up(big.kind, big.at)
			return
	elif legs != arms and _wait_for_big(legs, best_legs if legs else best_arms, foes, builds):
		return   # the free channel holds for a big attack (both channels) once the other comes free
	if not best_legs.is_empty():
		_wind_up(best_legs.kind, best_legs.at)
	if not best_arms.is_empty():
		_wind_up(best_arms.kind, best_arms.at)
	if best_legs.is_empty() and best_arms.is_empty() and not is_busy() \
			and float(_plan(foes, builds, 0.0).value) <= 0.0:
		# Only when NO attack reaches anything — not when the free channel reaches nothing while
		# the other cools down with a foe in its area (she turned away from it, 2026-11-18).
		_maybe_turn(foes)
		if not turning:
			nothing_for += THINK_INTERVAL
			g.sit_nothing_in_reach(foes)   # not stationary: she crawls toward it (user spec 2026-11-18)
		else:
			nothing_for = 0.0
	else:
		nothing_for = 0.0


## One channel is free, the other still busy: should the free one hold for a big attack (they need both
## channels)? Since a free channel chooses at once, the two hardly ever came free together and the big
## attacks starved (user report 2026-11-19: no po clap in 33 s of fighting). It holds when the big attack,
## its damage per second spread over its cooldown plus the wait for the other channel, beats what the two
## channels would strike apart (the free one now, the other one when it comes free) — at most
## BIG_WAIT_MAX seconds ahead.
const BIG_WAIT_MAX: float = 1.5

func _wait_for_big(legs_free: bool, best_free: Dictionary, foes: Array[Unit], builds: Array) -> bool:
	var other: int = CH_ARMS if legs_free else CH_LEGS
	var wait: float = maxf(cooldown[other], pending_time[other] if pending[other] != &"" else 0.0)
	if wait > BIG_WAIT_MAX:
		return false
	var best_other: Dictionary = _best_of(ARM_KINDS if legs_free else LEG_KINDS, foes, builds)
	var apart: float = float(best_free.get("value", 0.0)) + float(best_other.get("value", 0.0))
	var big: Dictionary = _best_of([HOP, CLAP, DOUBLE_STOMP], foes, builds,
		Balance.GOLEM_SIT_BIG_MIN_TARGETS if apart > 0.0 else 1)
	if big.is_empty():
		return false
	var cd: float = maxf(cooldown_of(big.kind), 0.05)
	return float(big.value) * cd / (cd + wait) > apart


## Is any of `foes` (enemy units) inside the area of one of her sit attacks as she faces now?
func _units_in_reach(foes: Array[Unit]) -> bool:
	var reach_r: float = _scan_radius()
	for u in foes:
		if _flat(u.position - g.position).length() <= reach_r and g._crab_reaches(u):
			return true
	return false


# --- Debug view (RangeRenderer, key G; user request 2026-11-18) -----------------------------
## Outlines of her sit attack zones as she sits now, flat in world x/z: [[kind, PackedVector2Array], ...]
## — built from the same measures in_area uses (circles cut where in_area cuts them).
func zone_outlines() -> Array:
	_frame()
	var out: Array = []
	for side in [1.0, -1.0]:
		var s_kind: StringName = STOMP_L if side > 0.0 else STOMP_R
		out.append([s_kind, _cut(_circle(_c_stomp[0 if side > 0.0 else 1], _c_stomp_r), _c_feet,
			-Balance.GOLEM_SIT_HEEL_BACK * _c_sz, INF)])
		var k_kind: StringName = KICK_L if side > 0.0 else KICK_R
		var back: float = Balance.GOLEM_SIT_KICK_FROM * _c_sz
		var ahead: float = Balance.GOLEM_SIT_KICK_TO * _c_sz
		var lane: PackedVector2Array = PackedVector2Array()
		for corner in [Vector2(0.0, -back), Vector2(0.0, ahead), Vector2(_c_kick_out, ahead), Vector2(_c_kick_out, -back)]:
			lane.append(_xz(_c_feet + _c_lf * (side * corner.x) + _c_fw * corner.y))
		out.append([k_kind, lane])
		out.append([WIPE_L if side > 0.0 else WIPE_R, _wipe_outline(side)])
		out.append([HAND_SLAM_L if side > 0.0 else HAND_SLAM_R, _circle(_c_hslam[0 if side > 0.0 else 1], _c_hslam_r)])
	out.append([HOP, _circle(g.position, _c_hop_r)])
	out.append([DOUBLE_STOMP, _circle(_c_dstomp, _c_dstomp_r)])
	for h in _c_hand:
		out.append([CLAP, _cut(_circle(h, _c_clap_r), g.position, -INF, 0.0)])
	return out


static func _xz(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


func _circle(c: Vector3, r: float, n: int = 48) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(n):
		var a: float = TAU * float(i) / float(n)
		pts.append(Vector2(c.x + cos(a) * r, c.z + sin(a) * r))
	return pts


## Moves every point whose distance ahead of `base` (along her heading) lies outside [lo, hi]
## onto that limit — the straight cut of a circle (heel line, middle of the seat).
func _cut(pts: PackedVector2Array, base: Vector3, lo: float, hi: float) -> PackedVector2Array:
	var fw: Vector2 = Vector2(_c_fw.x, _c_fw.z)
	var b: Vector2 = Vector2(base.x, base.z)
	var out: PackedVector2Array = PackedVector2Array()
	for p in pts:
		var a: float = (p - b).dot(fw)
		out.append(p + fw * (clampf(a, lo, hi) - a))
	return out


## The wipe's cone on `side`: from the middle of the seat out along the back edge (GOLEM_SIT_WIPE_BACK_DEG
## behind the cross direction), round the arc of its reach, back in along the tilted front edge.
func _wipe_outline(side: float) -> PackedVector2Array:
	var r: float = _c_wipe_r
	var front: float = Balance.GOLEM_SIT_WIPE_FRONT * _c_sz
	var tilt: float = tan(deg_to_rad(Balance.GOLEM_SIT_WIPE_FRONT_DEG))
	var at = func(out_m: float, ahead_m: float) -> Vector2:
		return _xz(g.position + _c_lf * (side * out_m) + _c_fw * ahead_m)
	var pts: PackedVector2Array = PackedVector2Array([at.call(0.0, 0.0)])
	var a0: float = -deg_to_rad(Balance.GOLEM_SIT_WIPE_BACK_DEG)
	var a: float = a0
	var step: float = deg_to_rad(3.0)
	while a < PI * 0.5:
		var o: float = r * cos(a)
		var f: float = r * sin(a)
		if f > front + o * tilt:
			break
		pts.append(at.call(o, f))
		a += step
	# The front edge, from where it meets the arc back to the body.
	var o_end: float = r * cos(a)
	for i in range(6, -1, -1):
		var o: float = o_end * float(i) / 6.0
		pts.append(at.call(o, front + o * tilt))
	return pts


## Radius around the seat beyond which no sit attack reaches.
func _scan_radius() -> float:
	return g.seat_back_m() + g.reach() + g.ground_radius(Golem.ATTACK_DRUM)


## Enemy units around her that any sit attack could ever reach, or that she could
## turn toward (aggro radius around the seat).
func _foes_around() -> Array[Unit]:
	var out: Array[Unit] = []
	_vehicles = _vehicles_around()   # (every choice starts here: the vehicles come fresh with it)
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


## Enemy GROUND vehicles near enough for a sit attack (user spec 2026-11-18: seated every golem
## strikes them, as the giant does standing; airships no). Each strike is a hit with the vehicle's
## own damage steps (Golem._crush_vehicle).
func _vehicles_around() -> Array:
	var out: Array = []
	if g.path_service == null:
		return out
	for u in g.path_service.get_units_in_radius(g.position, _scan_radius()):
		if not (u is CrewedVehicle) or u is Airship or not is_instance_valid(u) or u.state == Unit.State.DEAD:
			continue
		if u.tribe_id != g.tribe_id:
			out.append(u)
	return out


## The vehicles among `vehicles` the attack `kind` strikes: in its area, the nearest to the impact
## first, in the places of the target cap the units left free.
func vehicles_struck(kind: StringName, vehicles: Array, units_hit: int) -> Array:
	var free: int = max_targets(kind) - units_hit
	var out: Array = []
	if free <= 0:
		return out
	for v in vehicles:
		if is_instance_valid(v) and v.state != Unit.State.DEAD and in_area(kind, v.position):
			out.append(v)
	var centre: Vector3 = impact_point(kind)
	out.sort_custom(func(a, b) -> bool:
		return _flat(a.position - centre).length_squared() < _flat(b.position - centre).length_squared())
	if out.size() > free:
		out.resize(free)
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
		var hit_v: Array = vehicles_struck(kind, _vehicles, hit.size())
		var hit_b: Array = buildings_struck(kind, builds, hit.size() + hit_v.size())
		if hit.is_empty() and hit_v.is_empty() and hit_b.is_empty():
			continue
		if channels_of(kind).size() == 2 and hit.size() + hit_v.size() + hit_b.size() < min_big:
			continue   # the big ones are area attacks
		var v: float = _value(kind, hit, hit_b, hit_v)
		var near: float = _spread(kind, hit, hit_b)
		var bv: float = float(best.get("value", 0.0))
		if v > bv + 0.000001 or (absf(v - bv) <= 0.000001 and near < float(best.get("near", INF))):
			best = {"kind": kind, "at": Vector3.INF, "value": v, "near": near, "hit": hit, "hit_b": hit_b, "hit_v": hit_v}
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
func _value(kind: StringName, hit: Array[Unit], hit_b: Array = [], hit_v: Array = []) -> float:
	var dmg: int = damage(kind)
	var sum: float = Balance.GOLEM_STRUCTURE_VALUE * float(hit_v.size())
	var to_building: float = float(dmg) * Balance.GOLEM_BUILDING_VALUE_SHARE   # half a unit hit (user spec)
	for b in hit_b:
		if is_instance_valid(b):
			sum += minf(to_building, float(b.health))
	for u in hit:
		sum += float(mini(dmg, u.health))
	return sum / maxf(cooldown_of(kind), 0.05)


## Who the attack `kind` landing at `at` strikes: enemies in its area, the nearest to
## the impact first, up to its target cap.
func victims(kind: StringName, at: Vector3, foes: Array[Unit]) -> Array[Unit]:
	var hit: Array[Unit] = []
	var bd: Vector3 = bound_of(kind)
	var r2: float = bd.z * bd.z
	for u in foes:
		if not is_instance_valid(u) or u.state == Unit.State.DEAD:
			continue
		var dx: float = u.position.x - bd.x
		var dz: float = u.position.z - bd.y
		if dx * dx + dz * dz <= r2 and in_area(kind, u.position, at):
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
	var bd: Vector3 = bound_of(kind)
	for b in builds:
		if not is_instance_valid(b) or b.health <= 0:
			continue
		if b.footprint_distance_to(Vector2(bd.x, bd.y)) > bd.z:
			continue   # nowhere near the area
		if building_in_area(kind, b):
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
		_since_attack[ch] = 0.0
		_attack_cycle[ch] = cooldown[ch]
	g.sit_attack_started(kind, t)


## The landing: every unit struck takes the damage, every ground vehicle struck a hit of its own
## damage steps, every building struck GOLEM_BUILDING_DAMAGE_SHARE of the damage in hit points
## (user spec 2026-11-18; a building or vehicle brought down is a kill).
func _land(kind: StringName, at: Vector3) -> void:
	var dmg: int = damage(kind)
	var struck: Array[Unit] = victims(kind, at, _foes_around())
	var dealt: int = 0
	var killed: int = 0
	for u in struck:
		var hp: int = Golem.kill_hp_of(u)
		var before: int = u.health
		u.take_damage(dmg, g)
		dealt += before - (maxi(u.health, 0) if is_instance_valid(u) else 0)
		if not is_instance_valid(u) or u.state == Unit.State.DEAD or u.doomed:
			killed += 1
			g._credit_kill(hp)
	g.tally(kind, 1, struck.size(), killed, dealt)
	var struck_v: Array = vehicles_struck(kind, _vehicles_around(), struck.size())
	for v in struck_v:
		if is_instance_valid(v) and v.state != Unit.State.DEAD:
			g._crush_vehicle(v)
	var struck_b: Array = buildings_struck(kind, _buildings_around(), struck.size() + struck_v.size())
	for b in struck_b:
		if is_instance_valid(b) and b.health > 0:
			g._strike_building(b, Golem.building_damage_for(dmg))
	last_struck[kind] = struck
	last_struck_buildings[kind] = struck_b
	g._play_strike_sfx(model_of(kind))


## Where the one she turns to stands — INF when it is dead, gone, no longer an enemy
## target or out of her aggro radius.
func _turn_goal_point() -> Vector3:
	if _turn_escape:
		return g.position + _turn_dir
	if _turn_goal == null and _turn_dir != Vector3.ZERO:
		# Turning for a plan: on while anything it strikes is still there.
		for o in _turn_targets:
			if _alive_at(o, _scan_radius() + 0.5) != Vector3.INF:
				return g.position + _turn_dir
		return Vector3.INF
	return _alive_at(_turn_goal, g.aggro_radius() + 0.5)


## Where the enemy unit or building `o` stands — INF when it is dead, gone, no longer an
## enemy target or farther than `max_dist` from her.
## (Untyped on purpose: the one she turns to may have been freed meanwhile — a typed parameter fails at
## the call already, bug report 2026-11-18.)
func _alive_at(o, max_dist: float) -> Vector3:
	if o == null or not is_instance_valid(o):
		return Vector3.INF
	var at: Vector3 = Vector3.INF
	if o is Unit:
		var u: Unit = o as Unit
		if u.state == Unit.State.DEAD or u.doomed or u.tribe_id == g.tribe_id or not u.is_targetable():
			return Vector3.INF
		at = u.position
	else:
		if o.health <= 0 or o.tribe_id == g.tribe_id or not o.is_attackable():
			return Vector3.INF
		at = o.center_world()
	return at if _flat(at - g.position).length() <= max_dist else Vector3.INF


func _end_turn() -> void:
	_sweep_i = 0
	turning = false
	_turn_stall = 0.0
	_turn_spun = 0.0
	_turn_last = Vector3.ZERO
	_turn_sign = 0.0
	_turn_want = Vector3.ZERO
	_turn_escape = false
	_turn_goal = null
	_turn_dir = Vector3.ZERO
	_turn_targets = []


## Her best plan as _choose would pick it with both channels free, facing her current
## heading: {value, parts}. Each attack's time is stretched by `lead` (seconds of turning
## first) over GOLEM_SIT_TURN_PLAN_ATTACKS attacks — like the turn standing (attack_time).
## `strict`: the big attacks always need GOLEM_SIT_BIG_MIN_TARGETS (a turned heading must not win
## by leaving the single attacks nothing, which lets a big one strike a single foe).
func _plan(foes: Array[Unit], builds: Array, lead: float, strict: bool = false) -> Dictionary:
	var legs: Dictionary = _best_of(LEG_KINDS, foes, builds)
	var arms: Dictionary = _best_of(ARM_KINDS, foes, builds)
	var raw: float = float(legs.get("value", 0.0)) + float(arms.get("value", 0.0))
	var single: float = _stretched(legs, lead) + _stretched(arms, lead)
	var min_hit: int = Balance.GOLEM_SIT_BIG_MIN_TARGETS if raw > 0.0 or strict else 1
	var big: Dictionary = _best_of([HOP, CLAP, DOUBLE_STOMP], foes, builds, min_hit)
	var big_v: float = _stretched(big, lead)
	if big_v > single:
		return {"value": big_v, "parts": [big]}
	return {"value": single, "parts": [legs, arms]}


func _stretched(best: Dictionary, lead: float) -> float:
	if best.is_empty():
		return 0.0
	var cd: float = maxf(cooldown_of(best.kind), 0.05)
	return float(best.value) * cd / (cd + lead / float(Balance.GOLEM_SIT_TURN_PLAN_ATTACKS))


## Would another heading bring more? (user spec 2026-11-18: the turn counts in the choice.)
## GOLEM_SIT_TURN_PLAN_HEADINGS directions all round (at least GOLEM_SIT_TURN_MIN_DEG off),
## each weighed with its turn as a lead-in — GOLEM_SIT_TURN_PLAN_PER_THINK of them per call, so
## a round spreads over several thinks while she goes on striking. At the end of the round the
## best one beating the plan she has here wins and she turns to it (once she is not winding up).
## Returns true when she turns.
func _turn_sweep(foes: Array[Unit], builds: Array) -> bool:
	if turn_block > 0.0:
		return false
	var cur: Vector3 = g.heading()
	if _sweep_i == 0 or cur.dot(_sweep_from) < 0.9999:
		_sweep_i = 1
		_sweep_from = cur
		_sweep_v = 0.0
		_sweep_dir = Vector3.ZERO
		_sweep_parts = []
		_sweep_sign = 0.0
		_arc = free_arc()
	var here: Dictionary = _plan(foes, builds, 0.0)
	var n: int = Balance.GOLEM_SIT_TURN_PLAN_HEADINGS
	if _sweep_i < n:
		var cur_a: float = atan2(cur.x, cur.z)
		var rate: float = maxf(g.turn_rate(), 0.001)
		var saved: Vector3 = g._heading
		var done: int = 0
		while _sweep_i < n and done < Balance.GOLEM_SIT_TURN_PLAN_PER_THINK:
			var turn: float = TAU * float(_sweep_i) / float(n)
			_sweep_i += 1
			var ang: float = minf(turn, TAU - turn)
			if ang < deg_to_rad(Balance.GOLEM_SIT_TURN_MIN_DEG):
				continue
			done += 1
			var a: float = cur_a + turn
			var dir: Vector3 = Vector3(sin(a), 0.0, cos(a))
			var way: Dictionary = turn_way(dir, _arc)
			if way.sign == 0.0:
				continue   # her limbs cannot rest there, or not on the way there
			var lead: float = maxf(float(way.angle) - deg_to_rad(Balance.GOLEM_SIT_TURN_DONE_DEG), 0.0) / rate
			g._heading = dir
			var p: Dictionary = _plan(foes, builds, lead, float(here.value) > 0.0)
			if float(p.value) > _sweep_v + 0.000001:
				_sweep_v = float(p.value)
				_sweep_dir = dir
				_sweep_parts = p.parts
				_sweep_sign = float(way.sign)
		g._heading = saved
		if _sweep_i < n:
			return false
	if g._sit_layers_busy():
		# The round is done: hold its result until she is free — no attack wound up and no attack clip
		# playing any more (user spec 2026-11-19: the po clap's clip, filling its cooldown, went on into the turn).
		return false
	_sweep_i = 0
	if _sweep_dir == Vector3.ZERO or _sweep_v <= float(here.value) * Balance.GOLEM_SIT_TURN_PLAN_MARGIN + 0.000001:
		return false   # not clearly better: no turn for a trifle (bug report 2026-11-18)
	var best_dir: Vector3 = _sweep_dir
	# The round's values are up to a second old (and held while she was busy): weigh the chosen heading
	# afresh — the foes may have moved or died since (user report 2026-11-18: she turned and struck
	# differently although nothing seemed to change).
	var fresh: Dictionary = _fresh_turn_plan(best_dir, foes, builds, float(here.value) > 0.0)
	if fresh.is_empty() or float(fresh.value) <= float(here.value) * Balance.GOLEM_SIT_TURN_PLAN_MARGIN + 0.000001:
		return false
	_sweep_parts = fresh.parts
	_sweep_sign = float(fresh.sign)
	var targets: Array = []
	for part in _sweep_parts:
		if not part.is_empty():
			targets.append_array(part.hit)
			targets.append_array(part.hit_b)
	turning = true
	_turn_goal = null
	_turn_dir = best_dir
	_turn_targets = targets
	_turn_sign = _sweep_sign
	_turn_want = best_dir
	var first: Vector3 = _turn_step()
	if first == Vector3.ZERO:
		_end_turn()
		return false
	g.facing = first
	return true


## The plan facing `dir` as it stands right now, with the turn there as a lead-in: {value, parts, sign}
## (empty when she cannot turn there).
func _fresh_turn_plan(dir: Vector3, foes: Array[Unit], builds: Array, strict: bool) -> Dictionary:
	var way: Dictionary = turn_way(dir, free_arc())
	if way.sign == 0.0:
		return {}
	var lead: float = maxf(float(way.angle) - deg_to_rad(Balance.GOLEM_SIT_TURN_DONE_DEG), 0.0) \
		/ maxf(g.turn_rate(), 0.001)
	var saved: Vector3 = g._heading
	g._heading = dir
	var p: Dictionary = _plan(foes, builds, lead, strict)
	g._heading = saved
	return {"value": float(p.value), "parts": p.parts, "sign": float(way.sign)}


## Turning for a plan: is the rest of the turn still worth more than the plan where she
## points now? (Its foes died or moved off: she stops.)
func _turn_still_pays() -> bool:
	var foes: Array[Unit] = _foes_around()
	var builds: Array = _buildings_around()
	var here: Dictionary = _plan(foes, builds, 0.0)
	var left_rad: float = _left_on_way(_turn_dir)
	var lead: float = maxf(left_rad - deg_to_rad(Balance.GOLEM_SIT_TURN_DONE_DEG), 0.0) / maxf(g.turn_rate(), 0.001)
	var saved: Vector3 = g._heading
	g._heading = _turn_dir
	var there: Dictionary = _plan(foes, builds, lead, float(here.value) > 0.0)
	g._heading = saved
	return float(there.value) > float(here.value) + 0.000001


## While she turns: has the situation changed so that the turn should end? A turn for a plan:
## when the rest of it no longer pays (_turn_still_pays). A turn because nothing was in reach:
## as soon as something is (a foe walked under her — the po clap needs no aiming, it counts at
## every heading).
func _situation_changed() -> bool:
	if _turn_goal == null:
		return not _turn_still_pays()
	return float(_plan(_foes_around(), _buildings_around(), 0.0).value) > 0.0


## Nothing in reach: she turns (slowly) toward the nearest enemy unit within her aggro
## radius — none there, toward the nearest enemy building within it (user report
## 2026-11-17: she never turned to an airship wharf beside her) — if it lies more than
## GOLEM_SIT_TURN_MIN_DEG off her heading.
func _maybe_turn(foes: Array[Unit]) -> void:
	if turn_block > 0.0 or g._sit_layers_busy():
		return   # (no turn while an attack is wound up or its clip still plays, user spec 2026-11-19)
	var goal: Vector3 = Vector3.INF
	var goal_obj: Object = null
	var best: float = INF
	# Only what a zone could reach once she has turned (bug report 2026-11-18: she turned toward
	# foes and buildings far beyond her limbs and then could not strike them either).
	var range_m: float = minf(g.aggro_radius(), _scan_radius())
	for u in foes:
		var d: float = _flat(u.position - g.position).length()
		if d <= range_m and d < best:
			best = d
			goal = u.position
			goal_obj = u
	if goal == Vector3.INF and g.building_manager != null:
		for b in g.building_manager.buildings:
			if not is_instance_valid(b) or b.health <= 0 or b.tribe_id == g.tribe_id or not b.is_attackable():
				continue
			var d: float = b.footprint_distance_to(Vector2(g.position.x, g.position.z))
			if d <= range_m and d < best:
				best = d
				goal = b.center_world()
				goal_obj = b
	if goal == Vector3.INF:
		return
	var want: Vector3 = _flat(goal - g.position).normalized()
	if want == Vector3.ZERO or forward().dot(want) >= cos(deg_to_rad(Balance.GOLEM_SIT_TURN_MIN_DEG)):
		return
	var way: Dictionary = turn_way(want, free_arc())
	if way.sign == 0.0:
		return   # she cannot turn there (user spec 2026-11-18): no turn, no attack that way
	turning = true
	_turn_goal = goal_obj
	_turn_dir = Vector3.ZERO
	_turn_targets = []
	_turn_sign = float(way.sign)
	_turn_want = want
	var first: Vector3 = _turn_step()
	if first == Vector3.ZERO:
		_end_turn()
		return
	g.facing = first


## Her pose has become impossible — she has grown and her feet and hands reach further out, or
## the ground changed (user spec 2026-11-18): she turns to the nearest heading where she can sit
## (either way, checked every GOLEM_SIT_TURN_SAMPLE_DEG); is there none, she gets up.
func _escape_pose() -> void:
	if turn_block > 0.0:
		return
	var cur: Vector3 = g.heading()
	var a0: float = atan2(cur.x, cur.z)
	var step: float = deg_to_rad(Balance.GOLEM_SIT_TURN_SAMPLE_DEG)
	for i in range(1, int(ceil(PI / step)) + 1):
		for sgn in [1.0, -1.0]:
			var a: float = a0 + sgn * step * float(i)
			var dir: Vector3 = Vector3(sin(a), 0.0, cos(a))
			if g.sit_heading_ok(dir):
				turning = true
				_turn_escape = true
				_turn_goal = null
				_turn_dir = dir
				_turn_targets = []
				_turn_sign = sgn
				_turn_want = dir
				var b: float = a0 + sgn * minf(step * float(i), deg_to_rad(60.0))
				g.facing = Vector3(sin(b), 0.0, cos(b))
				return
	g.stand_up()   # no heading works: she gets up


## How far she can turn on the seat from where she faces now, each way (radians, up to a full
## turn; x: growing angle atan2(x, z), y: falling): every GOLEM_SIT_TURN_SAMPLE_DEG her limbs must
## rest on possible ground (Golem.sit_heading_ok, user spec 2026-11-18).
func free_arc() -> Vector2:
	var cur: Vector3 = g.heading()
	var a0: float = atan2(cur.x, cur.z)
	var step: float = deg_to_rad(Balance.GOLEM_SIT_TURN_SAMPLE_DEG)
	var n: int = int(ceil(TAU / step))
	var out: Vector2 = Vector2(TAU, TAU)
	for i in range(1, n + 1):
		var a: float = a0 + step * float(i)
		if not g.sit_heading_ok(Vector3(sin(a), 0.0, cos(a))):
			out.x = step * float(i - 1)
			break
	if out.x >= TAU:
		return out   # all the way round is free
	for i in range(1, n + 1):
		var a: float = a0 - step * float(i)
		if not g.sit_heading_ok(Vector3(sin(a), 0.0, cos(a))):
			out.y = step * float(i - 1)
			break
	return out


## The way to turn to `want` within the free arcs `arc`: {sign, angle} — the shorter way when both
## are free; sign 0: she cannot get there (or cannot rest there).
func turn_way(want: Vector3, arc: Vector2) -> Dictionary:
	var cur: Vector3 = g.heading()
	var up: float = wrapf(atan2(want.x, want.z) - atan2(cur.x, cur.z), 0.0, TAU)
	var down: float = TAU - up
	var done: float = deg_to_rad(Balance.GOLEM_SIT_TURN_DONE_DEG)
	if minf(up, down) <= done:
		return {"sign": 1.0 if up <= down else -1.0, "angle": minf(up, down)}
	if not g.sit_heading_ok(want):
		return {"sign": 0.0, "angle": INF}
	var up_ok: bool = up - done <= arc.x
	var down_ok: bool = down - done <= arc.y
	if up_ok and (not down_ok or up <= down):
		return {"sign": 1.0, "angle": up}
	if down_ok:
		return {"sign": -1.0, "angle": down}
	return {"sign": 0.0, "angle": INF}


## How much of the turn to `want` is left along the way she turns (radians).
func _left_on_way(want: Vector3) -> float:
	var cur: Vector3 = g.heading()
	var d: float = atan2(want.x, want.z) - atan2(cur.x, cur.z)
	return wrapf(d * (_turn_sign if _turn_sign != 0.0 else 1.0), 0.0, TAU)


## The next heading to aim at while turning: along her way (_turn_sign), at most 60 degrees ahead —
## ZERO when the next bit of the way would put her limbs on impossible ground.
## Is the way from angle `a0` by `by` radians (signed) free — her limbs on possible ground every
## GOLEM_SIT_TURN_SAMPLE_DEG and at its end?
func _way_free(a0: float, by: float) -> bool:
	var step: float = deg_to_rad(Balance.GOLEM_SIT_TURN_SAMPLE_DEG)
	var n: int = int(ceil(absf(by) / step))
	for i in range(1, n + 1):
		var a: float = a0 + signf(by) * minf(step * float(i), absf(by))
		if not g.sit_heading_ok(Vector3(sin(a), 0.0, cos(a))):
			return false
	return true


func _turn_step() -> Vector3:
	if _turn_sign == 0.0 or _turn_want == Vector3.ZERO:
		return Vector3.ZERO
	var cur: Vector3 = g.heading()
	var a0: float = atan2(cur.x, cur.z)
	# The short way, whenever it is free (bug report 2026-11-18: following a target that moved across
	# her heading — or overshooting it a little — she kept her first direction and turned almost all
	# the way round, the wrong way). The long way only while the short one is blocked.
	var short: float = wrapf(atan2(_turn_want.x, _turn_want.z) - a0, -PI, PI)
	if signf(short) != _turn_sign and absf(short) > 0.0001 and (_turn_escape or _way_free(a0, short)):
		_turn_sign = signf(short)
	var left: float = _left_on_way(_turn_want)
	var look: float = minf(left, deg_to_rad(Balance.GOLEM_SIT_TURN_SAMPLE_DEG))
	var a_look: float = a0 + _turn_sign * look
	if not _turn_escape and not g.sit_heading_ok(Vector3(sin(a_look), 0.0, cos(a_look))):
		return Vector3.ZERO
	var a: float = a0 + _turn_sign * minf(left, deg_to_rad(60.0))
	return Vector3(sin(a), 0.0, cos(a))
