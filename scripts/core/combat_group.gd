class_name CombatGroup extends RefCounted

## One melee fight in the original-Populous style (phase 8.2): exactly ONE
## defender, 1..MAX_MELEE_ATTACKERS attackers on its ring, plus a second row
## of waiters. Every unit is bound to at most one group — as its defender OR
## as an attacker/waiter (Unit.combat_group). Team fights (2v2/2v4) are
## structurally impossible: the defender seat holds one unit, so any clash
## decomposes into 1-vs-N groups (see Unit._bind_to_fight for the pairing
## rules: 1v1 first, surplus fills up to 1v3, latecomers of the outnumbered
## side pull attackers back out, waiters back-fill freed slots).
##
## Members are stored untyped (entries may be freed Nodes); every access is
## guarded. The UnitManager registers groups for the anchor pass (the anchor
## follows the defender lazily; nearby groups are pushed apart so a battle
## frays into distinct little brawls instead of one blob).

var defender = null        # Unit (untyped: may be freed)
var attackers: Array = []  # up to Unit.MAX_MELEE_ATTACKERS units
var waiters: Array = []    # second row, promoted in arrival order
## Fight location: follows the defender lazily (UnitManager pass); waiters
## ring around this instead of sticking to the defender's every step.
var anchor: Vector3 = Vector3.ZERO


func attacker_index(u) -> int:
	return attackers.find(u)


func is_waiter(u) -> bool:
	return waiters.has(u)


func member_count() -> int:
	return attackers.size() + waiters.size()


## Drops a member (attacker or waiter) and back-fills the freed slot from the
## second row. Clears the member's own binding.
func remove_member(u) -> void:
	waiters.erase(u)
	var idx: int = attackers.find(u)
	if idx >= 0:
		attackers.remove_at(idx)
		promote_waiters()
	if u != null and is_instance_valid(u) and u.combat_group == self:
		u.combat_group = null


## Moves waiters into free attacker slots (arrival order), skipping stale
## entries. Rule 5: the second row fills slots the moment they free up.
func promote_waiters() -> void:
	while attackers.size() < Unit.MAX_MELEE_ATTACKERS and not waiters.is_empty():
		var w = waiters.pop_front()
		if w != null and is_instance_valid(w) and w.state != Unit.State.DEAD \
				and w.combat_group == self:
			attackers.append(w)


## Drops freed/dead/foreign entries, then back-fills from the second row.
func prune() -> void:
	var i: int = 0
	while i < attackers.size():
		var a = attackers[i]
		if a == null or not is_instance_valid(a) or a.state == Unit.State.DEAD \
				or a.combat_group != self:
			attackers.remove_at(i)
		else:
			i += 1
	i = 0
	while i < waiters.size():
		var w = waiters[i]
		if w == null or not is_instance_valid(w) or w.state == Unit.State.DEAD \
				or w.combat_group != self:
			waiters.remove_at(i)
		else:
			i += 1
	promote_waiters()


## The nearest live attacker to `pos` (the defender's natural next opponent).
func nearest_attacker(pos: Vector3):
	var best = null
	var best_d: float = INF
	for a in attackers:
		if a == null or not is_instance_valid(a) or a.state == Unit.State.DEAD:
			continue
		var d: float = Vector2(a.position.x - pos.x, a.position.z - pos.z).length_squared()
		if d < best_d:
			best_d = d
			best = a
	return best


## True while this group is a live fight: valid defender that still points
## back at this group, and at least one live member. Prunes as a side effect.
func is_alive() -> bool:
	if defender == null or not is_instance_valid(defender) \
			or defender.state == Unit.State.DEAD or defender.combat_group != self:
		return false
	prune()
	return not (attackers.is_empty() and waiters.is_empty())


## Clears every binding without notifying anyone (stale-group cleanup; death
## and conversion use Unit._dissolve_own_group, which also retargets members).
func release_all() -> void:
	if defender != null and is_instance_valid(defender) and defender.combat_group == self:
		defender.combat_group = null
	defender = null
	for m in attackers + waiters:
		if m != null and is_instance_valid(m) and m.combat_group == self:
			m.combat_group = null
	attackers.clear()
	waiters.clear()
