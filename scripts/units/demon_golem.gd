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
##    Kills, alle 2 Stufen 2 mehr bis 62 m, danach alle 2 Stufen 2 weniger (2026-11-18).
##    Mit 120 m (40. Stufe) zerfaellt er.
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
##  * Unterhalt: wie jeder Golem 8 % des Brutto-Manaeinkommens + 2 Mana/s (Golem._pay_upkeep; bis 2026-11-18 5 Mana/s).
##
## unit_kind() bleibt "golem": er zaehlt in der Seitenleiste bei den Golems und
## ueberall dort, wo nach der Einheitenart gefragt wird, als Golem.

## Ground one loop of the walk clip covers in the 4-m model (golem_export.mjs
## prints it; the figure with the jeans shoes is a little taller than the golem's,
## so the same stride is 2,575 instead of 2,658 m).
const WALK_CLIP_STRIDE: float = 2.575
## The same for one loop of crab_walk (crab walk, 2026-11-18): 0,997 m.
const CRAB_CLIP_STRIDE_DEMON: float = 0.997


func _init() -> void:
	super._init()
	# Summoned with his first growth step (user spec 2026-11-18): 5 m and its bonuses.
	growth_steps = Balance.DEMON_GOLEM_START_STEPS
	max_health = max_health_cap()
	health = max_health
	speed = current_speed()
	_shown_size = size_factor()   # he starts small — no shrinking from the golem's size


func display_name() -> String:
	return "Dämonengolem"


# --- Growth ---------------------------------------------------------------------------

## Kills the growth step `step` (1 = the first) costs by itself (user spec 2026-11-18): 4, and
## DEMON_GOLEM_GROWTH_KILLS_ADD more every DEMON_GOLEM_GROWTH_KILLS_STEP steps up to the step that
## takes him past DEMON_GOLEM_SLOW_HEIGHT (slow_step, the 20th: 22 kills); after it, as much
## less every pair of steps (21-22: 20 ... 39-40: 2), never below 1.
static func kills_for_step(step: int) -> int:
	# The thresholds moved on by the steps he is summoned with (user spec 2026-11-18): the first two
	# steps after them cost 4 each.
	step -= Balance.DEMON_GOLEM_START_STEPS
	var pair: int = Balance.DEMON_GOLEM_GROWTH_KILLS_STEP
	var add: int = Balance.DEMON_GOLEM_GROWTH_KILLS_ADD
	var top: int = slow_step()
	if step <= top:
		return Balance.DEMON_GOLEM_GROWTH_KILLS + add * (maxi(step - 1, 0) / pair)
	var peak: int = Balance.DEMON_GOLEM_GROWTH_KILLS + add * ((top - 1) / pair)
	return maxi(peak - add * ((step - top + pair - 1) / pair), 1)


## The first growth step that takes him to DEMON_GOLEM_SLOW_HEIGHT or beyond (20: 62 m). From
## there the kills per step fall and the targets grow slowly.
static func slow_step() -> int:
	return int(ceil((Balance.DEMON_GOLEM_SLOW_HEIGHT - Balance.DEMON_GOLEM_START_HEIGHT)
		/ Balance.DEMON_GOLEM_GROWTH_HEIGHT - 0.000001))


## Kills needed for `steps` growth steps in total (counted from 2 m; the steps he is summoned with are free).
static func kills_for_steps(steps: int) -> int:
	var total: int = 0
	for s in range(Balance.DEMON_GOLEM_START_STEPS + 1, steps + 1):
		total += kills_for_step(s)
	return total


## The step at which he is DEMON_GOLEM_MAX_HEIGHT tall (40).
static func max_steps() -> int:
	return int(ceil((Balance.DEMON_GOLEM_MAX_HEIGHT - Balance.DEMON_GOLEM_START_HEIGHT)
		/ Balance.DEMON_GOLEM_GROWTH_HEIGHT - 0.000001))


## Growth steps a demon golem with `p_kills` kills has taken.
static func steps_for_kills(p_kills: int) -> int:
	var steps: int = Balance.DEMON_GOLEM_START_STEPS
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


## Every golem tramples from its first step on (user spec 2026-11-23; before: from 30 m) — he is
## summoned with it. Walking through units stays with the giant (ignores_unit_collision).
func tramples() -> bool:
	return growth_steps >= 1


func ignores_unit_collision() -> bool:
	return is_giant()


func can_strike_air() -> bool:
	return height_m() >= Balance.DEMON_GOLEM_AIR_HEIGHT - 0.0001


# --- Values that follow the growth step ----------------------------------------------

## +DEMON_GOLEM_GROWTH_TARGETS a step up to slow_step(); beyond, one every
## DEMON_GOLEM_SLOW_TARGETS_STEP steps (user spec 2026-11-18).
func max_targets() -> int:
	var top: int = slow_step()
	var fast: int = mini(growth_steps, top)
	var slow: int = maxi(growth_steps - top, 0) / Balance.DEMON_GOLEM_SLOW_TARGETS_STEP
	return Balance.DEMON_GOLEM_TARGETS + Balance.DEMON_GOLEM_GROWTH_TARGETS * fast + slow


func regen_per_second() -> float:
	return Balance.GOLEM_BASE_REGEN + Balance.DEMON_GOLEM_GROWTH_REGEN * float(growth_steps)


func max_health_cap() -> int:
	return Balance.DEMON_GOLEM_HP + Balance.DEMON_GOLEM_GROWTH_MAX_HP * growth_steps


func level_damage_bonus(_category: StringName) -> int:
	return 0


## Damage of an attack of the attack table as it stands in the books — with its fraction: half the
## attack's OWN base damage (user spec 2026-11-19: no attack depends on another one's value), a start
## bonus by its category (slam +3, kick +2, drum +3; swat as slam), plus the gain of every growth step.
## The genesis golem takes the same with his own steps.
static func damage_exact_at(row: Dictionary, steps: float) -> float:
	var category: StringName = row["category"]
	var base: float = float(row["damage"]) * Balance.DEMON_GOLEM_DAMAGE_SHARE
	if category == ATTACK_KICK:
		return base + Balance.DEMON_GOLEM_START_KICK_BONUS + Balance.DEMON_GOLEM_GROWTH_KICK_DAMAGE * steps
	if category == ATTACK_DRUM:
		return base + Balance.DEMON_GOLEM_START_DRUM_BONUS + Balance.DEMON_GOLEM_GROWTH_DRUM_DAMAGE * steps
	return base + Balance.DEMON_GOLEM_START_SLAM_BONUS + Balance.DEMON_GOLEM_GROWTH_SLAM_DAMAGE * steps


## Growth per step for attacks of `category` (slam, kick, drum; swat as slam).
static func damage_growth_per_step(category: StringName) -> float:
	if category == ATTACK_KICK:
		return Balance.DEMON_GOLEM_GROWTH_KICK_DAMAGE
	if category == ATTACK_DRUM:
		return Balance.DEMON_GOLEM_GROWTH_DRUM_DAMAGE
	return Balance.DEMON_GOLEM_GROWTH_SLAM_DAMAGE


## Growth steps that began at GOLEM_SIT_MIN_HEIGHT (30 m) or more: 29 -> 32 m does not count, 32 -> 35 m does.
func sit_steps() -> int:
	var n: int = 0
	for k in range(1, growth_steps + 1):
		if height_for_steps(k - 1) >= Balance.GOLEM_SIT_MIN_HEIGHT - 0.0001:
			n += 1
	return n


func sit_damage_growth(category: StringName) -> float:
	if category == CATEGORY_TRAMPLE:
		return 0.0
	return damage_growth_per_step(category) * float(sit_steps())


func sit_mod() -> Dictionary:
	return Balance.DEMON_GOLEM_SIT_MOD


## The standing attack `kind` (tests, diagnostics).
func damage_exact(kind: StringName) -> float:
	return damage_exact_at(Golem.stand_attack(kind), float(growth_steps))


func damage_value(row: Dictionary) -> float:
	if row["category"] == CATEGORY_TRAMPLE:
		return super.damage_value(row)   # from the size like the golem's
	return damage_exact_at(row, float(growth_steps))


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
func _base_reach_factor() -> float:
	return pow(size_factor(), area_exponent())


func _base_slam_scale() -> float:
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


## And getting into and out of the crab stand (assumption, like every stance change).
func crab_switch_time() -> float:
	return super.crab_switch_time() * (1.0 - Balance.DEMON_GOLEM_ATTACK_SPEEDUP)


func crab_stride() -> float:
	return CRAB_CLIP_STRIDE_DEMON


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


func status_text() -> String:
	var next: String = ""
	if growth_steps < max_steps():
		next = "   noch %d Kills bis %d m" % [
			kills_for_steps(growth_steps + 1) - kills, int(round(height_for_steps(growth_steps + 1)))]
	return status_lines("Dämonengolem   Wachstumsstufe %d/%d%s" % [growth_steps, max_steps(), next], "")


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
