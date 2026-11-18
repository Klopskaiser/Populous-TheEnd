class_name DemonGolem extends Golem

## Dämonengolem (Zauber 14, Nutzervorgabe 2026-11-16): ein zweiter Golem — die
## Figur mit den Jeansschuhen, muskuloeser und gedrungen (eigenes Modell
## models/units/golem_demon.glb). Er IST ein Golem (`is Golem`): Angriffe, Haltung,
## Zielwahl, Immunitaeten, Konter, Stimme und der Abstand der Golems untereinander
## kommen unveraendert von dort. Was anders ist, steht in Balance
## (DEMON_GOLEM_*, dort auch die ganze Vorgabe) und wird hier ueberschrieben:
##
##  * keine Stufen (`level` bleibt 0), keine Lebenszeit. Er beginnt 2 m klein und
##    waechst je WACHSTUMSSTUFE um genau 3 m (`growth_steps`); die Stufe kostet 4
##    Kills, alle 2 Stufen einen mehr. Mit 120 m (40. Stufe) zerfaellt er.
##  * die Groesse treibt alles: size_factor() = Hoehe / GOLEM_HEIGHT, und die
##    Golem-Formeln fuer Reichweite, Schneise, Tempo, Takt usw. rechnen damit.
##    Die Flaechen wachsen wie beim Golem nach Stufe 7.
##  * je Wachstumsstufe +15 Lebensobergrenze, +0,45 Leben/s, +3 Ziele und Schaden
##    (Handschlag +2,25, Tritt +2,4, Trommeln +3,6) auf den halben Startschaden.
##  * alles 15 % schneller als beim Golem gleicher Groesse: Angriffe, Animationen,
##    Haltungswechsel und Lauftempo.
##  * ab 20 m Luftschiffe, ab 30 m das Riesenpaket (is_giant) samt Trampeln und
##    Kollision. Nie gehaertet (is_full_size ist immer falsch).
##  * Kill: die Lebensobergrenze des Opfers, halb sofort, halb ueber 5 s, stapelbar
##    (ohne Lebenspunkte: 10 sofort und 15 ueber 5 s).
##  * Wachstumsstufe: 90 Leben sofort und 135 ueber 5 s, dazu.
##  * Unterhalt: 5 Mana je Sekunde, solange er lebt (_pay_upkeep).
##
## unit_kind() bleibt "golem": er zaehlt in der Seitenleiste bei den Golems und
## ueberall dort, wo nach der Einheitenart gefragt wird, als Golem.

## Ground one loop of the walk clip covers in the 4-m model (golem_export.mjs
## prints it; the figure with the jeans shoes is a little taller than the golem's,
## so the same stride is 2,575 instead of 2,658 m).
const WALK_CLIP_STRIDE: float = 2.575

## Running heals over time: one entry per kill or growth step, x = seconds left,
## y = health per second.
var _heal_stacks: Array[Vector2] = []
var _heal_frac: float = 0.0


func _init() -> void:
	super._init()
	max_health = Balance.DEMON_GOLEM_HP
	health = max_health
	speed = current_speed()
	_shown_size = size_factor()   # he starts small — no shrinking from the golem's size


func display_name() -> String:
	return "Dämonengolem"


# --- Growth ---------------------------------------------------------------------------

## Kills the growth step `step` (1 = the first) costs by itself: 5, and one more
## for every 10 steps before it.
static func kills_for_step(step: int) -> int:
	return Balance.DEMON_GOLEM_GROWTH_KILLS \
		+ maxi(step - 1, 0) / Balance.DEMON_GOLEM_GROWTH_KILLS_STEP


## Kills needed for `steps` growth steps in total.
static func kills_for_steps(steps: int) -> int:
	var total: int = 0
	for s in range(1, steps + 1):
		total += kills_for_step(s)
	return total


## The step at which he is DEMON_GOLEM_MAX_HEIGHT tall (40).
static func max_steps() -> int:
	return int(ceil((Balance.DEMON_GOLEM_MAX_HEIGHT - Balance.DEMON_GOLEM_START_HEIGHT)
		/ Balance.DEMON_GOLEM_GROWTH_HEIGHT - 0.000001))


## Growth steps a demon golem with `p_kills` kills has taken.
static func steps_for_kills(p_kills: int) -> int:
	var steps: int = 0
	var left: int = p_kills
	while steps < max_steps() and left >= kills_for_step(steps + 1):
		left -= kills_for_step(steps + 1)
		steps += 1
	return steps


## Body height in metres after `steps` growth steps.
static func height_for_steps(steps: int) -> float:
	return minf(Balance.DEMON_GOLEM_START_HEIGHT
		+ Balance.DEMON_GOLEM_GROWTH_HEIGHT * float(steps), Balance.DEMON_GOLEM_MAX_HEIGHT)


## Body radius of the largest demon golem there can be (the catapult's query).
static func max_body_radius() -> float:
	return Balance.GOLEM_BODY_HALF_WIDTH * Balance.DEMON_GOLEM_WIDTH_FACTOR \
		* Balance.DEMON_GOLEM_MAX_HEIGHT / Balance.GOLEM_HEIGHT


## The golem's formulas all run on the size factor — his is his height measured
## in fresh golems (2 m: 0,42; 80 m: 16,9; 119 m: 25,2).
func size_factor() -> float:
	return height_for_steps(growth_steps) / Balance.GOLEM_HEIGHT


## Never "full-grown": he keeps his weaknesses to the end (user spec).
func is_full_size() -> bool:
	return false


func has_lifetime() -> bool:
	return false


## The giant's package — and with it trampling and walking through units — from
## DEMON_GOLEM_GIANT_HEIGHT on.
func is_giant() -> bool:
	return height_m() >= Balance.DEMON_GOLEM_GIANT_HEIGHT - 0.0001


func tramples() -> bool:
	return is_giant()


func ignores_unit_collision() -> bool:
	return is_giant()


func can_strike_air() -> bool:
	return height_m() >= Balance.DEMON_GOLEM_AIR_HEIGHT - 0.0001


# --- Values that follow the growth step ----------------------------------------------

func max_targets() -> int:
	return Balance.DEMON_GOLEM_TARGETS + Balance.DEMON_GOLEM_GROWTH_TARGETS * growth_steps


func regen_per_second() -> float:
	return Balance.DEMON_GOLEM_GROWTH_REGEN * float(growth_steps)


func max_health_cap() -> int:
	return Balance.DEMON_GOLEM_HP + Balance.DEMON_GOLEM_GROWTH_MAX_HP * growth_steps


func level_damage_bonus() -> int:
	return 0


## Damage of an attack as it stands in the books — with its fraction: half the
## golem's starting damage, a start bonus (slam +3, kick +2, drum +3), plus the gain
## of every growth step.
func damage_exact(kind: StringName) -> float:
	var n: float = float(growth_steps)
	if kind == ATTACK_KICK:
		return float(Balance.GOLEM_KICK_DAMAGE) * Balance.DEMON_GOLEM_DAMAGE_SHARE \
			+ Balance.DEMON_GOLEM_START_KICK_BONUS + Balance.DEMON_GOLEM_GROWTH_KICK_DAMAGE * n
	if kind == ATTACK_DRUM:
		return float(Balance.GOLEM_DRUM_HIT_DAMAGE * Balance.GOLEM_DRUM_HITS.size()) \
			* Balance.DEMON_GOLEM_DAMAGE_SHARE + Balance.DEMON_GOLEM_START_DRUM_BONUS \
			+ Balance.DEMON_GOLEM_GROWTH_DRUM_DAMAGE * n
	return float(Balance.GOLEM_SLAM_DAMAGE) * Balance.DEMON_GOLEM_DAMAGE_SHARE \
		+ Balance.DEMON_GOLEM_START_SLAM_BONUS + Balance.DEMON_GOLEM_GROWTH_SLAM_DAMAGE * n


## Damage of an attack right now: the exact value, rounded when it lands. The
## stomp comes from the size like the golem's (twice the trample damage).
func attack_damage(kind: StringName) -> int:
	if kind == ATTACK_STOMP:
		return Balance.GOLEM_STOMP_TRAMPLE_MULT * trample_damage()
	return int(round(damage_exact(kind)))


## Damage of ONE of the drum's hits: the whole attack split evenly, the last hit
## takes the remainder.
func drum_hit_damage(hit: int) -> int:
	var hits: int = Balance.GOLEM_DRUM_HITS.size()
	var total: int = attack_damage(ATTACK_DRUM)
	var each: int = total / hits
	return total - each * (hits - 1) if hit >= hits - 1 else each


# --- Values that follow the size ------------------------------------------------------

## How much faster the body grows than the strike areas beyond the golem's level
## 7 — as exponents: an area factor is the size factor to this power.
static func area_exponent() -> float:
	return Balance.GOLEM_GROWTH_AREA_EXPONENT


## The slam's circle grows faster there — with the golem's exponent from before
## 2026-11-17, kept fixed (DEMON_GOLEM_SLAM_EXPONENT).
static func slam_exponent() -> float:
	return Balance.DEMON_GOLEM_SLAM_EXPONENT


static func speed_exponent() -> float:
	return Balance.GOLEM_GROWTH_SPEED_EXPONENT


## Scale of the lane's width: like the golem's areas beyond level 7, from the
## start — a 4,7-m demon golem has a fresh golem's areas.
func reach_factor() -> float:
	return pow(size_factor(), area_exponent())


func slam_scale() -> float:
	return pow(size_factor(), slam_exponent())


## The golem's speed at this size, DEMON_GOLEM_MOVE_SPEEDUP faster (user spec
## 2026-11-17; the 4-m/s floor for the small one is gone).
func current_speed() -> float:
	return Golem.speed_for_size(size_factor()) * (1.0 + Balance.DEMON_GOLEM_MOVE_SPEEDUP)


## The golem's stance switch at this size, 15 % shorter (user spec 2026-11-17).
func stance_switch_time() -> float:
	return super.stance_switch_time() * (1.0 - Balance.DEMON_GOLEM_ATTACK_SPEEDUP)


## Sitting down and getting up as well.
func sit_switch_time() -> float:
	return super.sit_switch_time() * (1.0 - Balance.DEMON_GOLEM_ATTACK_SPEEDUP)


## He turns 15 % faster than the golem of his size, standing and seated (user spec 2026-11-18).
func turn_rate() -> float:
	return super.turn_rate() * (1.0 + Balance.DEMON_GOLEM_TURN_SPEEDUP)


func aggro_radius() -> float:
	return clampf(AGGRO_RADIUS * size_factor(), AGGRO_RADIUS, Balance.GOLEM_AGGRO_MAX)


## The golem's cooldown at this height, 15 % shorter. Linear in the body height
## — carried on beyond 80 m and back below the golem's starting size.
func strike_cooldown() -> float:
	var t: float = (height_m() - Balance.GOLEM_HEIGHT) \
		/ (Balance.GOLEM_MAX_HEIGHT - Balance.GOLEM_HEIGHT)
	return lerpf(STRIKE_COOLDOWN, Balance.GOLEM_STRIKE_COOLDOWN_MAX, t) \
		* (1.0 - Balance.DEMON_GOLEM_ATTACK_SPEEDUP)


## Playback speed of an attack animation: the golem's at this size (slower with
## the root of the size — and faster for a small body), sped up so that it takes
## 15 % less time, and never so slow that it would outlast the attack's cooldown.
func attack_speed(kind: StringName) -> float:
	var slowest: float = float(CLIP_LENGTH.get(kind, STRIKE_COOLDOWN)) / clip_rate(kind) \
		/ cooldown_for(kind)
	return maxf(1.0 / sqrt(size_factor()) / (1.0 - Balance.DEMON_GOLEM_ATTACK_SPEEDUP), slowest)


# --- Kills ----------------------------------------------------------------------------

## A kill: heals at once and over time, and counts toward the next growth step.
## At DEMON_GOLEM_MAX_HEIGHT he falls apart.
func _credit_kill(victim_hp: int = -1) -> void:
	kills += 1
	var steps: int = steps_for_kills(kills)
	if steps != growth_steps:
		var was_giant: bool = is_giant()
		var gained: int = steps - growth_steps
		growth_steps = steps
		max_health = max_health_cap()
		_apply_speed()
		_queue_stretch()
		if is_giant() != was_giant:
			_sync_soa_flags()   # from 30 m he walks through units
		# Growing heals as well (user spec 2026-11-16): at once and over time.
		for i in range(gained):
			health = mini(health + Balance.DEMON_GOLEM_GROWTH_HEAL, max_health)
			_add_heal_over_time(Balance.DEMON_GOLEM_GROWTH_HEAL_OVER_TIME,
				Balance.DEMON_GOLEM_GROWTH_HEAL_DURATION)
	var heal: Vector2i = kill_heal_for(victim_hp)
	health = mini(health + heal.x, max_health)
	_add_heal_over_time(heal.y, Balance.DEMON_GOLEM_KILL_HEAL_DURATION)
	if growth_steps >= max_steps():
		_crumble()


## What a kill heals (user spec 2026-11-17): the victim's health limit, half of it
## at once (rounded down) and the rest over time. A victim without health
## (`victim_hp` < 0: building, vehicle, ritual reward) brings the old 10 + 15.
## x = at once, y = over DEMON_GOLEM_KILL_HEAL_DURATION.
static func kill_heal_for(victim_hp: int) -> Vector2i:
	if victim_hp <= 0:
		return Vector2i(Balance.DEMON_GOLEM_KILL_HEAL, Balance.DEMON_GOLEM_KILL_HEAL_OVER_TIME)
	var now: int = victim_hp / 2
	return Vector2i(now, victim_hp - now)


func tick(delta: float) -> void:
	super.tick(delta)
	if state != State.DEAD and not doomed:
		_tick_kill_heal(delta)
		_pay_upkeep(delta)


## His upkeep (user spec 2026-11-16): DEMON_GOLEM_MANA_UPKEEP mana per second for
## as long as he lives — the forester's pattern: a claim on the tribe's income,
## paid before any spell charges. A tribe that earns less gives what it earns; no
## debt is left that would run on after his death.
func _pay_upkeep(delta: float) -> void:
	if tribe == null or delta <= 0.0:
		return
	var granted: float = tribe.claim_upkeep_rate(Balance.DEMON_GOLEM_MANA_UPKEEP)
	tribe.consume_mana(granted * delta)


## The healing over time of the last kills: every kill's share runs for
## DEMON_GOLEM_KILL_HEAL_DURATION, all of them side by side.
func _tick_kill_heal(delta: float) -> void:
	if _heal_stacks.is_empty() or delta <= 0.0:
		return
	for i in range(_heal_stacks.size() - 1, -1, -1):
		var s: Vector2 = _heal_stacks[i]
		_heal_frac += s.y * minf(delta, s.x)
		s.x -= delta
		if s.x <= 0.0:
			_heal_stacks.remove_at(i)
		else:
			_heal_stacks[i] = s
	if _heal_frac >= 1.0:
		var heal: int = int(_heal_frac)
		_heal_frac -= float(heal)
		health = mini(health + heal, max_health)


## Starts a heal of `amount` health spread over `duration` seconds; it runs beside
## all others (stacking).
func _add_heal_over_time(amount: int, duration: float) -> void:
	if amount > 0 and duration > 0.0:
		_heal_stacks.append(Vector2(duration, float(amount) / duration))


## Leben, das die Heilung ueber Zeit (Kills, Wachstum) noch nachliefert (fuer die Anzeige).
func pending_kill_heal() -> float:
	var left: float = _heal_frac
	for s in _heal_stacks:
		left += s.x * s.y
	return left


func status_text() -> String:
	var next: String = ""
	if growth_steps < max_steps():
		next = "   noch %d Kills bis %d m" % [
			kills_for_steps(growth_steps + 1) - kills, int(round(height_for_steps(growth_steps + 1)))]
	var pose: String = stance_name()
	return "Dämonengolem   Größe: %d m%s\nLeben: %d/%d   Heilung: %.2f/s\nKills: %d   Ziele: %d   Haltung: %s" % [
		int(round(height_m())), next, health, max_health, regen_per_second(), kills,
		max_targets(), pose]


# --- Build ----------------------------------------------------------------------------

func model_file() -> String:
	return "models/units/golem_demon.glb"


## Stockier: at the same height a quarter wider and deeper than the golem.
func model_scale() -> Vector3:
	return Vector3(MODEL_SCALE * Balance.DEMON_GOLEM_WIDTH_FACTOR, MODEL_SCALE_Y,
		MODEL_SCALE * Balance.DEMON_GOLEM_WIDTH_FACTOR)


func body_half_width() -> float:
	return BODY_HALF_WIDTH * Balance.DEMON_GOLEM_WIDTH_FACTOR


func body_half_depth() -> float:
	return BODY_HALF_DEPTH * Balance.DEMON_GOLEM_WIDTH_FACTOR


func walk_clip_speed() -> float:
	return WALK_CLIP_STRIDE * MODEL_SCALE * Balance.DEMON_GOLEM_WIDTH_FACTOR


func rise_depth() -> float:
	return height_m() + 0.2


func selection_ring_scale() -> float:
	return super.selection_ring_scale() * Balance.DEMON_GOLEM_WIDTH_FACTOR
