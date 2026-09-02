class_name AudioSlots

## Priority-based slot allocator for pooled audio players (phase 10b).
##
## Pure static logic: it works on plain arrays describing a pool's state, so it
## has no Node, no AudioServer and no autoload dependency and is fully testable
## headless. Both the AudioManager pool (SFX/UI one-shots) and CombatAudio's own
## pool run through pick_slot().
##
## Why priorities: a fixed pool means sounds compete. Without ranking, a spell
## incantation loses its slot to the twentieth punch of a mass battle. Prio 1
## (incantations, the shaman's death cry) always wins, prio 2 (siege engine and
## airship deaths) beats the rest, prio 3 is everything else and may be dropped.

## Caller passes this to mean "derive the priority from the sound name".
const PRIO_AUTO: int = 0
## Spell incantations, shaman death — must always be heard.
const PRIO_CRITICAL: int = 1
## Siege engine / airship deaths — loud, rare, worth interrupting chatter for.
const PRIO_IMPORTANT: int = 2
## Everything else. Dropped first when the pool is saturated.
const PRIO_NORMAL: int = 3

## A same-priority sound may only be cut off once it has played this long. Keeps
## a burst of equally ranked sounds (mass battle hits) throttled instead of
## letting each new one restart the pool, while still allowing a long-running
## sound to yield to a fresh one of the same rank.
const STEAL_SAME_PRIO_MS: int = 250


## Picks the pool index to play a `want_prio` sound on, or -1 to drop it.
##
## `playing[i]` = is slot i busy, `prios[i]` = priority of the sound on slot i,
## `starts[i]` = when it started (ms). `cursor` is the round-robin position;
## the CALLER advances it (`cursor = (idx + 1) % size`) when the result is >= 0.
## `steal_same_prio_ms` = 0 disables same-priority stealing entirely.
##
## Order: free slot first (never drop while the pool has room — the pre-10b bug
## checked only the one slot under the cursor), then the oldest lower-ranked
## victim, then the oldest same-ranked victim that is old enough.
static func pick_slot(playing: Array, prios: PackedInt32Array,
		starts: PackedInt64Array, want_prio: int, cursor: int, now_ms: int,
		steal_same_prio_ms: int = STEAL_SAME_PRIO_MS) -> int:
	var size: int = playing.size()
	if size == 0:
		return -1
	# 1) Any free slot, starting at the cursor so playback spreads over the pool.
	for step in range(size):
		var i: int = (cursor + step) % size
		if not playing[i]:
			return i
	# 2) Oldest slot holding a strictly lower-ranked sound (higher number = lower).
	var victim: int = _oldest_matching(prios, starts, want_prio, true, 0, 0)
	if victim != -1:
		return victim
	# 3) Oldest same-ranked slot, but only past the grace period.
	if steal_same_prio_ms > 0:
		victim = _oldest_matching(prios, starts, want_prio, false,
			steal_same_prio_ms, now_ms)
		if victim != -1:
			return victim
	return -1


## Oldest slot whose priority is worse than (`lower_only`) or equal to
## `want_prio`. For the equal case a slot must have played at least
## `min_age_ms` to qualify. -1 when nothing matches.
static func _oldest_matching(prios: PackedInt32Array, starts: PackedInt64Array,
		want_prio: int, lower_only: bool, min_age_ms: int, now_ms: int) -> int:
	var best: int = -1
	var best_start: int = 0
	for i in range(prios.size()):
		if lower_only:
			if prios[i] <= want_prio:
				continue
		else:
			if prios[i] != want_prio:
				continue
			if now_ms - int(starts[i]) < min_age_ms:
				continue
		if best == -1 or int(starts[i]) < best_start:
			best = i
			best_start = int(starts[i])
	return best


## Variant index to play on the NEXT repetition of a looping sound. `current` is
## the index playing now (-1 on the first start). With several files a loop must
## neither lock onto the variant picked at start (user report: two tornado loop
## files, only ever one heard) nor immediately repeat the same one — with exactly
## two files that makes them alternate.
static func next_variant(count: int, current: int) -> int:
	if count <= 1:
		return 0
	var pick: int = randi() % count
	if pick == current:
		pick = (pick + 1) % count
	return pick


## Priority of a sound derived from its name. The death keys are the actual
## return values of Unit.death_sfx_key() and its overrides (shaman.gd,
## airship.gd, crewed_vehicle.gd).
static func default_priority(name: StringName) -> int:
	var s: String = String(name)
	if s.begins_with("spell_voice_") or s == "shaman_death":
		return PRIO_CRITICAL
	if s == "airship_death" or s == "siege_death_burn" or s == "siege_death_burst":
		return PRIO_IMPORTANT
	return PRIO_NORMAL
