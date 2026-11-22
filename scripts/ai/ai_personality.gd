class_name AIPersonality extends RefCounted

## Personality of ONE skirmish AI (user spec 2026-11-22): the same rules and the
## same controller for every AI, but different priorities — when it attacks, how
## many huts it builds before the army, how many towers and how early vehicles, and
## which big spells it saves its mana for.
##
## - AGGRESSIVE: the behaviour the AI had before (small early waves, the shaman
##   marches with every wave). Its values are the old constants, so a controller
##   without an explicit personality plays exactly as before.
## - ECONOMIC: builds its first defenders early as well, but does not attack until
##   its economy stands — many more huts early, faster housing growth, a bigger
##   first wave.
## - DEFENSIVE: like the economist, but more watchtowers (they grow with the
##   village), vehicles earlier, and it spreads out somewhat more slowly (fewer
##   huts first, a more compact village).
##
## Pure data plus a few pure helpers — no world access, headless-testable.

enum Kind { AGGRESSIVE, ECONOMIC, DEFENSIVE }

const IDS: Array[StringName] = [&"aggressive", &"economic", &"defensive"]

var kind: Kind = Kind.AGGRESSIVE

# --- Attack -----------------------------------------------------------------------
## First attack wave (open arena / cramped arena) and its growth per finished wave.
var first_wave: int = AIState.ARMY_ATTACK_SIZE
var first_wave_cramped: int = Balance.AI_ARMY_ATTACK_SIZE_CRAMPED
var wave_growth: int = AIState.ATTACK_WAVE_GROWTH
## TRAIN -> ATTACK additionally needs this population (0 = no condition).
var attack_min_pop: int = 0

# --- Economy ----------------------------------------------------------------------
## Huts the base build order puts up before the second and third camp.
var target_huts: int = AIState.TARGET_HUTS
## Housing-pressure trigger (share of the capacity) and the absolute headroom.
var housing_pressure: float = Balance.AI_HOUSING_PRESSURE
var housing_headroom: int = Balance.AI_MIN_HOUSING_HEADROOM
## Hut construction sites at the same time.
var max_hut_sites: int = Balance.AI_MAX_HUT_SITES
## One parallel construction site per this many braves.
var braves_per_site: int = Balance.AI_BRAVES_PER_SITE
## Braves kept out of training (share of the population).
var economy_brave_share: float = Balance.AI_ECONOMY_BRAVE_SHARE
## Share of the huts whose fresh braves walk straight into training (BUILD / army lag).
var training_share_build: float = Balance.AI_TRAINING_HUT_SHARE_BUILD
var training_share_army: float = Balance.AI_TRAINING_HUT_SHARE_ARMY
## Settlement anchors the plot search may spread over (open arena; the cramped arena
## keeps its own compact value). Fewer = a more compact village.
var settlement_anchors: int = Balance.AI_MAX_SETTLEMENT_ANCHORS

# --- Army mix ---------------------------------------------------------------------
var share_warrior: float = Balance.AI_ARMY_SHARE_WARRIOR
var share_firewarrior: float = Balance.AI_ARMY_SHARE_FIREWARRIOR
var share_preacher: float = Balance.AI_ARMY_SHARE_PREACHER

# --- Defence ----------------------------------------------------------------------
## Home guard: the standing army this AI trains even before its first attack (also
## in BUILD) — `guard_base` plus `guard_per_pop` per follower. 0 = none (aggressive:
## its waves are its defence). The economist's "early defenders".
var guard_base: int = 0
var guard_per_pop: float = 0.0
## Watchtowers: a base count plus one per `huts_per_tower` usable huts (0 = no
## growth), capped. The cramped arena adds one, as before.
var towers_base: int = Balance.AI_TARGET_WATCHTOWERS
var huts_per_tower: int = 0
var towers_max: int = Balance.AI_TARGET_WATCHTOWERS
## Defensive build order: first towers / the first workshops right after the
## firewarrior camp instead of at the end of the ladder.
var early_towers: int = 0
var early_workshops: bool = false
## Defence radius around the village (factor on AIState.defend_radius).
var defend_radius_mult: float = 1.0

# --- Magic ------------------------------------------------------------------------
## Charges the AI keeps in stock of its everyday spells; it charges these first.
var spell_reserve: Dictionary = {
	&"fireball": 3, &"lightning": 2, &"swarm": 1, &"hypnosis": 1, &"tornado": 1,
	&"landbridge": 1,
}
## The big spells it saves for, in order: the first one WITHOUT a charge is the
## current savings goal, so over time it collects one of each.
var spell_goals: Array[StringName] = [
	&"firestorm", &"earthquake", &"demon_golem", &"supertornado", &"golem", &"volcano",
]
## Takes the shaman (with an escort) out to an enemy village when a big spell is
## charged, even outside an attack wave.
var spell_raids: bool = true


static func aggressive() -> AIPersonality:
	return AIPersonality.new()


static func economic() -> AIPersonality:
	var p: AIPersonality = AIPersonality.new()
	p.kind = Kind.ECONOMIC
	p.first_wave = 24
	p.first_wave_cramped = 16
	p.wave_growth = 10
	p.attack_min_pop = 70
	p.target_huts = 12
	p.housing_pressure = 0.55
	p.housing_headroom = 20
	p.max_hut_sites = 4
	p.braves_per_site = 6
	p.economy_brave_share = 0.45
	p.training_share_build = 0.12
	p.training_share_army = 0.45
	p.settlement_anchors = Balance.AI_MAX_SETTLEMENT_ANCHORS + 1
	p.guard_base = 6
	p.guard_per_pop = 0.12
	p.towers_base = Balance.AI_TARGET_WATCHTOWERS
	p.huts_per_tower = 10
	p.towers_max = 4
	p.spell_reserve = {
		&"fireball": 3, &"lightning": 2, &"swarm": 1, &"hypnosis": 2, &"tornado": 1,
		&"landbridge": 1,
	}
	p.spell_goals = [
		&"earthquake", &"volcano", &"golem", &"firestorm", &"supertornado", &"genesis_golem",
	]
	return p


static func defensive() -> AIPersonality:
	var p: AIPersonality = AIPersonality.new()
	p.kind = Kind.DEFENSIVE
	p.first_wave = 28
	p.first_wave_cramped = 18
	p.wave_growth = 10
	p.attack_min_pop = 80
	p.target_huts = 10
	p.housing_pressure = 0.58
	p.housing_headroom = 18
	p.max_hut_sites = 3
	p.braves_per_site = 6
	p.economy_brave_share = 0.42
	p.training_share_build = 0.15
	p.training_share_army = 0.45
	p.settlement_anchors = Balance.AI_MAX_SETTLEMENT_ANCHORS_CRAMPED
	p.share_warrior = 0.30
	p.share_firewarrior = 0.45
	p.share_preacher = 0.25
	p.guard_base = 6
	p.guard_per_pop = 0.15
	p.towers_base = 3
	p.huts_per_tower = 4
	p.towers_max = 10
	p.early_towers = 1
	p.early_workshops = true
	p.defend_radius_mult = 1.25
	p.spell_reserve = {
		&"fireball": 3, &"lightning": 2, &"swarm": 2, &"hypnosis": 2, &"tornado": 1,
		&"landbridge": 1,
	}
	p.spell_goals = [
		&"genesis_golem", &"firestorm", &"earthquake", &"supertornado", &"golem", &"volcano",
	]
	p.spell_raids = false
	return p


## Personality by id (&"aggressive", &"economic", &"defensive"); unknown -> aggressive.
static func from_id(id: StringName) -> AIPersonality:
	match id:
		&"economic":
			return economic()
		&"defensive":
			return defensive()
	return aggressive()


## Resolves the menu choice per AI slot: an id stays, &"random" (or anything unknown)
## draws one — and the drawn slots get DIFFERENT personalities as long as there are
## any left (three random AIs = one of each).
static func resolve_ids(choices: Array[StringName], rng: RandomNumberGenerator) -> Array[StringName]:
	var pool: Array[StringName] = []
	for id in IDS:
		if not choices.has(id):
			pool.append(id)
	var out: Array[StringName] = []
	for choice in choices:
		if IDS.has(choice):
			out.append(choice)
			continue
		if pool.is_empty():
			pool = IDS.duplicate()
		var pick: int = rng.randi_range(0, pool.size() - 1)
		out.append(pool[pick])
		pool.remove_at(pick)
	return out


func id() -> StringName:
	return IDS[int(kind)]


func display_name() -> String:
	match kind:
		Kind.ECONOMIC:
			return "Ökonom"
		Kind.DEFENSIVE:
			return "Verteidiger"
	return "Aggressiv"


## First attack wave for the arena.
func first_wave_for(cramped: bool) -> int:
	return first_wave_cramped if cramped else first_wave


## Watchtower target for the current village size.
func tower_target(usable_huts: int, cramped: bool) -> int:
	var n: int = towers_base
	if huts_per_tower > 0:
		n += usable_huts / huts_per_tower
	n = mini(n, towers_max)
	return n + (1 if cramped else 0)


## Standing army wanted at home for this population (0 = no home guard).
func guard_size(population: int) -> int:
	if guard_base <= 0 and guard_per_pop <= 0.0:
		return 0
	return guard_base + int(float(population) * guard_per_pop)


## Braves kept out of training: the floor plus this personality's share.
func min_economy_braves(population: int) -> int:
	return maxi(Balance.AI_MIN_ECONOMY_BRAVES, int(float(population) * economy_brave_share))
