class_name AIState extends RefCounted

## Pure decision logic of the skirmish AI (phase 7): the state machine with
## its threshold transitions. No node/world access — next_state() maps
## (state, tribe snapshot) to the follow-up state, so it is headless-testable
## with hand-made snapshots. The AIController builds real snapshots and
## executes the per-state behaviour.

enum State { BUILD, TRAIN, ATTACK }

## Full base the AI keeps building toward (in the background, in EVERY state).
## 10f: raised from 4 because a stage-0 hut only houses 10 (was 40) — six huts are
## 60 base places. The rest of the housing comes from upgrades, which run by
## themselves (Tribe.upgrades_allowed defaults to true).
const TARGET_HUTS: int = 6
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
	# 10g: TWO triggers, because a pure percentage fails with the small 10f huts —
	# 80 % of 10 places is 8, i.e. the hut is nearly full before anything is even
	# planned, and the upgrade stages let capacity run ahead of the population so
	# the percentage branch often never fires at all (user report: "should have
	# built huts, wood was in reach"). The absolute headroom catches that.
	var housing: int = int(counts.get("housing_capacity", 0))
	var population: int = int(counts.get("population", 0))
	var pressure: int = int(float(housing) * Balance.AI_HOUSING_PRESSURE)
	var headroom: int = housing - population
	if housing > 0 and huts < Balance.AI_MAX_HUTS \
			and int(counts.get("hut_sites", 0)) < Balance.AI_MAX_HUT_SITES \
			and (population >= pressure or headroom < Balance.AI_MIN_HOUSING_HEADROOM):
		return &"hut"
	if huts < TARGET_HUTS:
		return &"hut"
	if int(counts.get("firewarrior_camp", 0)) < 1:
		return &"firewarrior_camp"
	if int(counts.get("temple", 0)) < 1:
		return &"temple"
	# 10g: extra training camps moved from the very END of the ladder to HERE.
	# They used to sit behind up to twelve workshops, and workshop_target grows
	# with the braves while the hut count grows far more slowly — so the AI never
	# reached this branch and fielded exactly one camp of each kind forever (user
	# report). The target now comes from the BRAVE STREAM, not the hut count: a
	# camp trains ONE unit at a time, so throughput is the limit.
	var camp_kind: StringName = missing_camp_kind(counts)
	if camp_kind != &"":
		return camp_kind
	# Scaling foresters (see the first-forester note above): behind housing, so
	# they grow the wood supply without ever blocking population growth.
	if bool(counts.get("wood_thin", false)) \
			and int(counts.get("forester", 0)) < forester_target(braves):
		return &"forester"
	# Production shops scale with the tribe (7f): together with the vehicle caps
	# this is the actual fix for "the AI hardly ever fields vehicles". The FIRST
	# shop of a kind is never gated — only the second and later, so a tribe that
	# cannot keep its camps saturated still gets vehicles at all.
	var shops: int = workshop_target(braves)
	if int(counts.get("workshop", 0)) < shops \
			and _may_add_shop(counts, int(counts.get("workshop", 0))):
		return &"workshop"
	if int(counts.get("fireram_workshop", 0)) < shops \
			and _may_add_shop(counts, int(counts.get("fireram_workshop", 0))):
		return &"fireram_workshop"
	if int(counts.get("watchtower", 0)) < Balance.AI_TARGET_WATCHTOWERS:
		return &"watchtower"
	if int(counts.get("airship_wharf", 0)) < shops \
			and _may_add_shop(counts, int(counts.get("airship_wharf", 0))):
		return &"airship_wharf"
	return &""


## Whether another production shop of a kind that already has `have` of them may
## be planned. The first one always may; from the second on the training camps
## must have caught up with the brave stream — building vehicle shops while the
## army production lags was the user's "6 workshops, few vehicles, should have
## been huts".
static func _may_add_shop(counts: Dictionary, have: int) -> bool:
	return have < 1 or missing_camp_kind(counts) == &""


## Camp kind that is short of its stream target, or &"" when all three are met.
## Picks the kind with the biggest ABSOLUTE shortfall so a tribe that needs three
## more barracks does not build one of each first.
static func missing_camp_kind(counts: Dictionary) -> StringName:
	var targets: Dictionary = camp_targets(float(counts.get("brave_stream", 0.0)))
	var best: StringName = &""
	var worst: int = 0
	for kind in [&"warrior_camp", &"firewarrior_camp", &"temple"]:
		var short: int = int(targets[kind]) - int(counts.get(kind, 0))
		if short > worst:
			worst = short
			best = kind
	return best


## Camp count per kind from the BRAVE STREAM (braves per minute the huts deliver)
## instead of the hut count. A camp trains ONE unit at a time — barracks 3 s =
## 20/min, fire temple 4 s = 15/min, temple 5 s = 12/min — so throughput is what
## decides how many are needed. The stream is split by the army mix
## (Balance.AI_ARMY_SHARE_*), and every kind keeps at least the one camp the old
## TARGET_CAMPS guaranteed.
##
## The per-camp throughput is DERIVED from the training times, not a second set
## of constants: a balance change to WARRIOR_CAMP_TRAINING_TIME must not silently
## leave the AI planning for the old rate.
static func camp_targets(brave_stream: float) -> Dictionary:
	return {
		&"warrior_camp": _camp_count(brave_stream, Balance.AI_ARMY_SHARE_WARRIOR,
			Balance.WARRIOR_CAMP_TRAINING_TIME),
		&"firewarrior_camp": _camp_count(brave_stream,
			Balance.AI_ARMY_SHARE_FIREWARRIOR, Balance.FIREWARRIOR_CAMP_TRAINING_TIME),
		&"temple": _camp_count(brave_stream, Balance.AI_ARMY_SHARE_PREACHER,
			Balance.TEMPLE_TRAINING_TIME),
	}


static func _camp_count(brave_stream: float, share: float, training_time: float) -> int:
	if training_time <= 0.0:
		return 1
	var per_camp: float = 60.0 / training_time      # units per minute, one camp
	var wanted: float = brave_stream * share / per_camp
	return clampi(int(ceil(wanted)), 1, Balance.AI_MAX_CAMPS_PER_KIND)


## Share of the tribe's huts whose rally point is put ON a training building, so
## their fresh braves walk straight into the training queue
## (Hut._spawn_brave -> Building.rally_training_building, engine behaviour since
## phase 5d that the AI never used).
##
## MUST stay below 1.0: with every hut routed into a camp the tribe gets no free
## braves at all — no builders, no wood crews, no workshop staff — and the
## economy dies without a single error message. In BUILD the share is low; it
## rises with how far the army is below its wave target.
static func training_hut_share(state: State, army: int, army_target: int) -> float:
	if state == State.BUILD:
		return Balance.AI_TRAINING_HUT_SHARE_BUILD
	var target: float = maxf(float(army_target), 1.0)
	var lag: float = clampf(1.0 - float(army) / target, 0.0, 1.0)
	return lerpf(Balance.AI_TRAINING_HUT_SHARE_BUILD,
		Balance.AI_TRAINING_HUT_SHARE_ARMY, lag)


## fewest_camp_kind() was removed in 10g: missing_camp_kind() replaces it and picks
## by SHORTFALL against the stream target instead of by raw count. Keeping both
## would have left two nearly identical camp choosers side by side — exactly the
## kind of duplication that let the is_attackable() targeting bug survive.
