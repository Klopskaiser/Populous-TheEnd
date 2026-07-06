class_name AIState extends RefCounted

## Pure decision logic of the skirmish AI (phase 7): the state machine with
## its threshold transitions. No node/world access — next_state() maps
## (state, tribe snapshot) to the follow-up state, so it is headless-testable
## with hand-made snapshots. The AIController builds real snapshots and
## executes the per-state behaviour.

enum State { BUILD, TRAIN, ATTACK }

## Full base the AI keeps building toward (in the background, in EVERY state).
const TARGET_HUTS: int = 3
const TARGET_CAMPS: int = 3
## BUILD -> TRAIN already when the essentials stand (training starts early,
## the remaining buildings go up in parallel).
const MIN_HUTS_FOR_TRAIN: int = 2
const MIN_CAMPS_FOR_TRAIN: int = 1
const POP_FOR_TRAIN: int = 12

## TRAIN -> ATTACK at this army size (warriors + firewarriors + preachers),
## with the shaman alive.
const ARMY_ATTACK_SIZE: int = 8
## ATTACK -> fallback when the army drops below this (decimated) or the
## shaman dies.
const ARMY_RETREAT_SIZE: int = 4

## Keep at least this many braves out of training (economy keeps running).
const MIN_ECONOMY_BRAVES: int = 8


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
			if army >= ARMY_ATTACK_SIZE and shaman_alive:
				return State.ATTACK
			return State.TRAIN
		State.ATTACK:
			if army < ARMY_RETREAT_SIZE or not shaman_alive:
				if huts < 1 or camps < 1:
					return State.BUILD
				return State.TRAIN
			return State.ATTACK
	return State.BUILD


## Training kinds sorted by their deficit vs. the target mix (50% warriors,
## 30% firewarriors, 20% preachers), biggest deficit first. Pure -> testable.
static func training_kind_order(warriors: int, firewarriors: int, preachers: int) -> Array[StringName]:
	var total: float = float(warriors + firewarriors + preachers) + 1.0
	var deficits: Array = [
		[0.5 - float(warriors) / total, &"warrior"],
		[0.3 - float(firewarriors) / total, &"firewarrior"],
		[0.2 - float(preachers) / total, &"preacher"],
	]
	deficits.sort_custom(func(a: Array, b: Array) -> bool:
		return float(a[0]) > float(b[0]))
	var order: Array[StringName] = []
	for entry in deficits:
		order.append(entry[1])
	return order


## The single most-wanted kind (biggest deficit).
static func next_training_kind(warriors: int, firewarriors: int, preachers: int) -> StringName:
	return training_kind_order(warriors, firewarriors, preachers)[0]
