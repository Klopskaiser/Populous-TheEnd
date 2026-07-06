class_name AIState extends RefCounted

## Pure decision logic of the skirmish AI (phase 7): the state machine with
## its threshold transitions. No node/world access — next_state() maps
## (state, tribe snapshot) to the follow-up state, so it is headless-testable
## with hand-made snapshots. The AIController builds real snapshots and
## executes the per-state behaviour.

enum State { BUILD, TRAIN, ATTACK }

## BUILD -> TRAIN once the base stands: this many usable huts ...
const TARGET_HUTS: int = 3
## ... all three training buildings (warrior camp, firewarrior camp, temple) ...
const TARGET_CAMPS: int = 3
## ... and at least this population.
const POP_FOR_TRAIN: int = 18

## TRAIN -> ATTACK at this army size (warriors + firewarriors + preachers),
## with the shaman alive.
const ARMY_ATTACK_SIZE: int = 12
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


## Threshold transitions incl. fallback. Deliberately conservative: one step
## per tick, unknown states fall back to BUILD.
static func next_state(state: State, snap: Dictionary) -> State:
	var huts: int = snap.get("huts", 0)
	var camps: int = snap.get("camps", 0)
	var army: int = snap.get("army", 0)
	var shaman_alive: bool = snap.get("shaman_alive", false)
	match state:
		State.BUILD:
			if huts >= TARGET_HUTS and camps >= TARGET_CAMPS \
					and snap.get("population", 0) >= POP_FOR_TRAIN:
				return State.TRAIN
			return State.BUILD
		State.TRAIN:
			# Losses (destroyed base buildings) send the AI back to building.
			if huts < TARGET_HUTS or camps < TARGET_CAMPS:
				return State.BUILD
			if army >= ARMY_ATTACK_SIZE and shaman_alive:
				return State.ATTACK
			return State.TRAIN
		State.ATTACK:
			if army < ARMY_RETREAT_SIZE or not shaman_alive:
				if huts < TARGET_HUTS or camps < TARGET_CAMPS:
					return State.BUILD
				return State.TRAIN
			return State.ATTACK
	return State.BUILD


## Which combat unit the TRAIN state wants next, from the current counts and
## the target mix (50% warriors, 30% firewarriors, 20% preachers): the kind
## with the biggest relative deficit. Pure -> testable.
static func next_training_kind(warriors: int, firewarriors: int, preachers: int) -> StringName:
	var total: float = float(warriors + firewarriors + preachers) + 1.0
	var deficits: Array = [
		[0.5 - float(warriors) / total, &"warrior"],
		[0.3 - float(firewarriors) / total, &"firewarrior"],
		[0.2 - float(preachers) / total, &"preacher"],
	]
	deficits.sort_custom(func(a: Array, b: Array) -> bool:
		return float(a[0]) > float(b[0]))
	return deficits[0][1]
