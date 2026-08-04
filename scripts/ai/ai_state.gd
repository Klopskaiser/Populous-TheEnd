class_name AIState extends RefCounted

## Pure decision logic of the skirmish AI (phase 7): the state machine with
## its threshold transitions. No node/world access — next_state() maps
## (state, tribe snapshot) to the follow-up state, so it is headless-testable
## with hand-made snapshots. The AIController builds real snapshots and
## executes the per-state behaviour.

enum State { BUILD, TRAIN, ATTACK }

## Full base the AI keeps building toward (in the background, in EVERY state).
const TARGET_HUTS: int = 4
const TARGET_CAMPS: int = 3
## BUILD -> TRAIN already when the essentials stand (training starts early,
## the remaining buildings go up in parallel).
const MIN_HUTS_FOR_TRAIN: int = 2
const MIN_CAMPS_FOR_TRAIN: int = 1
const POP_FOR_TRAIN: int = 16

## TRAIN -> ATTACK at this army size (warriors + firewarriors + preachers),
## with the shaman alive. This is the FIRST wave; the controller raises its
## per-tribe target after every attack (gradually bigger waves), passed in
## via the snapshot key "army_target". Raised in 10e: the AI attacks LATER and
## invests the early game into braves instead.
const ARMY_ATTACK_SIZE: int = 12
## Wave growth per finished attack and its cap (late-game waves scale far
## beyond the old 40).
const ATTACK_WAVE_GROWTH: int = 6
const ATTACK_WAVE_MAX: int = 120
## ATTACK -> fallback when the army drops below this (decimated) or the
## shaman dies.
const ARMY_RETREAT_SIZE: int = 4

## Braves kept out of training. Floor only — the real value scales with the
## population, see min_economy_braves().
const MIN_ECONOMY_BRAVES: int = Balance.AI_MIN_ECONOMY_BRAVES


## Snapshot keys (all int unless noted): "population", "braves", "army",
## "huts" (usable), "camps" (usable training buildings), "shaman_alive" (bool).
static func make_snapshot(population: int, braves: int, army: int, huts: int,
		camps: int, shaman_alive: bool) -> Dictionary:
	return {
		"population": population, "braves": braves, "army": army,
		"huts": huts, "camps": camps, "shaman_alive": shaman_alive,
	}


## Threshold transitions incl. fallback. Construction runs in EVERY state
## (the controller builds toward the full base in the background); the state
## only gates training and attacking.
static func next_state(state: State, snap: Dictionary) -> State:
	var huts: int = snap.get("huts", 0)
	var camps: int = snap.get("camps", 0)
	var army: int = snap.get("army", 0)
	var shaman_alive: bool = snap.get("shaman_alive", false)
	match state:
		State.BUILD:
			if huts >= MIN_HUTS_FOR_TRAIN and camps >= MIN_CAMPS_FOR_TRAIN \
					and snap.get("population", 0) >= POP_FOR_TRAIN:
				return State.TRAIN
			return State.BUILD
		State.TRAIN:
			# Losing the essentials (destroyed base) sends the AI back to BUILD.
			if huts < 1 or camps < 1:
				return State.BUILD
			if army >= int(snap.get("army_target", ARMY_ATTACK_SIZE)) and shaman_alive:
				return State.ATTACK
			return State.TRAIN
		State.ATTACK:
			if army < ARMY_RETREAT_SIZE or not shaman_alive:
				if huts < 1 or camps < 1:
					return State.BUILD
				return State.TRAIN
			return State.ATTACK
	return State.BUILD


## Training kinds sorted by their deficit vs. the target mix
## (Balance.AI_ARMY_SHARE_*), biggest deficit first. Pure -> testable.
##
## The tiebreak is not cosmetic: with the 10e mix of 40/30/30 firewarriors and
## preachers hit EXACT deficit ties, and Array.sort_custom is not stable in
## Godot — without a deterministic tiebreak the army mix would jitter and the
## mix test would be flaky.
static func training_kind_order(warriors: int, firewarriors: int, preachers: int) -> Array[StringName]:
	var total: float = float(warriors + firewarriors + preachers) + 1.0
	var deficits: Array = [
		[Balance.AI_ARMY_SHARE_WARRIOR - float(warriors) / total, 0, &"warrior"],
		[Balance.AI_ARMY_SHARE_FIREWARRIOR - float(firewarriors) / total, 1, &"firewarrior"],
		[Balance.AI_ARMY_SHARE_PREACHER - float(preachers) / total, 2, &"preacher"],
	]
	deficits.sort_custom(func(a: Array, b: Array) -> bool:
		if is_equal_approx(float(a[0]), float(b[0])):
			return int(a[1]) < int(b[1])   # warrior -> firewarrior -> preacher
		return float(a[0]) > float(b[0]))
	var order: Array[StringName] = []
	for entry in deficits:
		order.append(entry[2])
	return order


## The single most-wanted kind (biggest deficit).
static func next_training_kind(warriors: int, firewarriors: int, preachers: int) -> StringName:
	return training_kind_order(warriors, firewarriors, preachers)[0]


# --- Scaling rules (pure, phase 10e) ---------------------------------------------

## Braves kept out of training and logistics: a floor plus a share of the tribe,
## so a 300-pop tribe keeps a real workforce instead of the old fixed 8.
## 20 -> 8 | 100 -> 35 | 400 -> 140
static func min_economy_braves(population: int) -> int:
	return maxi(Balance.AI_MIN_ECONOMY_BRAVES,
		int(float(population) * Balance.AI_ECONOMY_BRAVE_SHARE))


## Parallel construction sites. 8 -> 1 | 20 -> 2 | 64 -> 8 (cap).
static func parallel_site_count(braves: int) -> int:
	return clampi(braves / Balance.AI_BRAVES_PER_SITE, 1, Balance.AI_MAX_PARALLEL_SITES)


## Standing wood crews. Deliberately 0 below AI_BRAVES_PER_WOOD_CREW braves:
## the early game keeps behaving exactly as before, and the parallel-site
## increase cannot starve it.
static func wood_crew_count(braves: int) -> int:
	return clampi(braves / Balance.AI_BRAVES_PER_WOOD_CREW, 0, Balance.AI_MAX_WOOD_CREWS)


## Braves sent into training per tick. < 60 braves -> 3 (as before) | 240 -> 12.
static func train_batch(braves: int) -> int:
	return clampi(braves / Balance.AI_BRAVES_PER_TRAIN_BATCH,
		Balance.AI_TRAIN_BATCH_MIN, Balance.AI_TRAIN_BATCH_MAX)


static func forester_target(braves: int) -> int:
	return clampi(1 + braves / Balance.AI_BRAVES_PER_FORESTER, 1, Balance.AI_MAX_FORESTERS)


## Workers per forester; capped at Forester.WORKER_SLOTS (4).
static func forester_workers(braves: int) -> int:
	return clampi(2 + braves / Balance.AI_FORESTER_WORKER_STEP, 2, 4)


## Target count PER workshop kind (catapult shop / fire-ram shop / wharf).
static func workshop_target(braves: int) -> int:
	return clampi(1 + braves / Balance.AI_BRAVES_PER_WORKSHOP, 1,
		Balance.AI_MAX_SHOPS_PER_KIND)


## Per-tribe vehicle caps by brave count. Pure: reads only Balance and the Tribe
## DEFAULT constants. The CONTROLLER clamps against the Tribe MAX_*_LIMIT values
## — those limits belong to the tribe, not to the mix.
## 0 -> 3/3/2 (defaults) | 200 -> 8/8/4 | 400 -> 13/13/7
static func vehicle_caps(braves: int) -> Dictionary:
	var slots: int = braves / Balance.AI_BRAVES_PER_VEHICLE_SLOT
	return {
		&"catapults": Tribe.MAX_CATAPULTS_DEFAULT + slots,
		&"fire_rams": Tribe.MAX_FIRE_RAMS_DEFAULT + slots,
		&"airships": Tribe.MAX_AIRSHIPS_DEFAULT + slots / 2,
	}


## The complete build order as a PURE function — headless-testable without ever
## instantiating a scene; the controller maps the returned identifier onto a
## PackedScene.
##
## `counts` keys, all int and PLANNED (construction sites included): "hut",
## "hut_sites", "warrior_camp", "firewarrior_camp", "temple", "forester",
## "workshop", "fireram_workshop", "airship_wharf", "watchtower", "wood_depot",
## "forward_depot"; plus the situation: "braves", "population",
## "housing_capacity" (int) and "wood_thin", "grove_far" (bool).
## Returns the kind identifier, or &"" for "nothing to build".
static func next_building_kind(counts: Dictionary) -> StringName:
	var braves: int = int(counts.get("braves", 0))
	var huts: int = int(counts.get("hut", 0))
	if huts < 1:
		return &"hut"
	if int(counts.get("warrior_camp", 0)) < 1:
		return &"warrior_camp"
	# A base wood rack early (1 wood, practically free): it is what makes the
	# depot haul and the area-harvest delivery preference work at all.
	if int(counts.get("wood_depot", 0)) < 1:
		return &"wood_depot"
	# Wood around the base is thin and there is no forester AT ALL: sustainable
	# supply before expanding away. Only the FIRST forester pre-empts here — the
	# scaling ones come after housing further down, because forester_target grows
	# with the tribe and would otherwise outrank housing forever (a 200-brave
	# tribe wants four foresters and would never build another hut again).
	if bool(counts.get("wood_thin", false)) and int(counts.get("forester", 0)) < 1:
		return &"forester"
	# The best grove is far off: a forward rack so the crews stop walking the
	# whole way home with every load.
	if bool(counts.get("grove_far", false)) and int(counts.get("forward_depot", 0)) < 1:
		return &"wood_depot"
	# Housing pressure, pulled FORWARD from the end of the ladder — this is what
	# unlocks the high population at all.
	#
	# The two guards are mandatory: Hut.housing_capacity() returns 0 while the
	# hut is not usable, so construction sites do not count. Without
	# "housing_capacity > 0" the branch is TRUE from the very first tick
	# (population >= 0) and the AI would build nothing but huts and never a
	# warrior camp; without the hut-site cap it would fill every parallel site
	# with huts.
	var housing: int = int(counts.get("housing_capacity", 0))
	var pressure: int = int(float(housing) * Balance.AI_HOUSING_PRESSURE)
	if housing > 0 and int(counts.get("population", 0)) >= pressure \
			and huts < Balance.AI_MAX_HUTS \
			and int(counts.get("hut_sites", 0)) < Balance.AI_MAX_HUT_SITES:
		return &"hut"
	if huts < TARGET_HUTS:
		return &"hut"
	if int(counts.get("firewarrior_camp", 0)) < 1:
		return &"firewarrior_camp"
	if int(counts.get("temple", 0)) < 1:
		return &"temple"
	# Scaling foresters (see the first-forester note above): behind housing, so
	# they grow the wood supply without ever blocking population growth.
	if bool(counts.get("wood_thin", false)) \
			and int(counts.get("forester", 0)) < forester_target(braves):
		return &"forester"
	# Production shops scale with the tribe (7f): together with the vehicle caps
	# this is the actual fix for "the AI hardly ever fields vehicles".
	var shops: int = workshop_target(braves)
	if int(counts.get("workshop", 0)) < shops:
		return &"workshop"
	if int(counts.get("fireram_workshop", 0)) < shops:
		return &"fireram_workshop"
	if int(counts.get("watchtower", 0)) < Balance.AI_TARGET_WATCHTOWERS:
		return &"watchtower"
	if int(counts.get("airship_wharf", 0)) < shops:
		return &"airship_wharf"
	var camp_total: int = int(counts.get("warrior_camp", 0)) \
		+ int(counts.get("firewarrior_camp", 0)) + int(counts.get("temple", 0))
	var camp_target: int = TARGET_CAMPS \
		+ maxi(0, huts - TARGET_HUTS) / Balance.AI_HUTS_PER_EXTRA_CAMP
	if camp_total < camp_target:
		return fewest_camp_kind(counts)
	return &""


## Camp kind with the fewest standing/planned buildings (ties: warrior ->
## firewarrior -> temple, mirroring the army mix priority).
static func fewest_camp_kind(counts: Dictionary) -> StringName:
	var best: StringName = &"warrior_camp"
	for kind in [&"firewarrior_camp", &"temple"]:
		if int(counts.get(kind, 0)) < int(counts.get(best, 0)):
			best = kind
	return best
