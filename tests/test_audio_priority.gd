extends TestBase

## Phase 10b: the priority-based audio slot allocator (AudioSlots). Pure static
## logic on arrays — no autoloads, no scene tree, no AudioServer needed.

const NOW: int = 100000


## Full pool (every slot busy) of `size` slots.
func _busy(size: int) -> Array:
	var a: Array = []
	for i in range(size):
		a.append(true)
	return a


# --- Free slots ---------------------------------------------------------------

## Regression guard for the pre-10b bug: play_sfx looked at the ONE slot under
## the round-robin cursor and dropped the sound when it was busy, even with
## seven of eight slots idle.
func test_pick_slot_uses_any_free_slot() -> void:
	var playing: Array = _busy(8)
	playing[5] = false
	var prios: PackedInt32Array = PackedInt32Array([3, 3, 3, 3, 3, 3, 3, 3])
	var starts: PackedInt64Array = PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0])
	var idx: int = AudioSlots.pick_slot(playing, prios, starts,
		AudioSlots.PRIO_NORMAL, 2, NOW)
	check(idx == 5, "the one free slot is used even though the cursor sits on a busy one (got %d)" % idx)


func test_free_slot_search_wraps_around() -> void:
	var playing: Array = _busy(8)
	playing[1] = false
	var prios: PackedInt32Array = PackedInt32Array([3, 3, 3, 3, 3, 3, 3, 3])
	var starts: PackedInt64Array = PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0])
	var idx: int = AudioSlots.pick_slot(playing, prios, starts,
		AudioSlots.PRIO_NORMAL, 7, NOW)
	check(idx == 1, "the ring search wraps past the end of the pool (got %d)" % idx)


func test_cursor_position_is_preferred_when_free() -> void:
	var playing: Array = [false, false, false, false]
	var prios: PackedInt32Array = PackedInt32Array([3, 3, 3, 3])
	var starts: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])
	check(AudioSlots.pick_slot(playing, prios, starts, AudioSlots.PRIO_NORMAL, 2, NOW) == 2,
		"an idle pool hands out the slot at the cursor (round-robin spread)")


# --- Stealing from lower-ranked sounds ----------------------------------------

func test_prio1_steals_oldest_prio3() -> void:
	var prios: PackedInt32Array = PackedInt32Array([3, 3, 3, 3])
	var starts: PackedInt64Array = PackedInt64Array([
		NOW - 700, NOW - 900, NOW - 500, NOW - 600])
	var idx: int = AudioSlots.pick_slot(_busy(4), prios, starts,
		AudioSlots.PRIO_CRITICAL, 0, NOW)
	check(idx == 1, "an incantation takes over the longest-running prio 3 slot (got %d)" % idx)


func test_prio2_steals_only_prio3() -> void:
	var prios: PackedInt32Array = PackedInt32Array([1, 3, 2, 3])
	var starts: PackedInt64Array = PackedInt64Array([
		NOW - 1000, NOW - 600, NOW - 1000, NOW - 800])
	var idx: int = AudioSlots.pick_slot(_busy(4), prios, starts,
		AudioSlots.PRIO_IMPORTANT, 0, NOW)
	check(idx == 3, "a vehicle death takes the older of the two prio 3 slots (got %d)" % idx)


func test_prio3_never_evicts_prio1_or_2() -> void:
	var prios: PackedInt32Array = PackedInt32Array([1, 2, 1, 2])
	var starts: PackedInt64Array = PackedInt64Array([
		NOW - 5000, NOW - 5000, NOW - 5000, NOW - 5000])
	var idx: int = AudioSlots.pick_slot(_busy(4), prios, starts,
		AudioSlots.PRIO_NORMAL, 0, NOW)
	check(idx == -1, "ordinary sounds are dropped rather than cutting off important ones (got %d)" % idx)


# --- Same-priority stealing ---------------------------------------------------

## Mass battle: the pool is full of equally ranked hits that all just started,
## so the throttle holds and the new sound is dropped.
func test_equal_prio3_full_pool_drops() -> void:
	var prios: PackedInt32Array = PackedInt32Array([3, 3, 3, 3])
	var starts: PackedInt64Array = PackedInt64Array([
		NOW - 40, NOW - 80, NOW - 20, NOW - 60])
	var idx: int = AudioSlots.pick_slot(_busy(4), prios, starts,
		AudioSlots.PRIO_NORMAL, 0, NOW)
	check(idx == -1, "a saturated pool of fresh same-rank sounds stays throttled (got %d)" % idx)


func test_same_prio_steal_needs_age() -> void:
	var prios: PackedInt32Array = PackedInt32Array([1, 1, 1, 1])
	var young: PackedInt64Array = PackedInt64Array([
		NOW - 100, NOW - 120, NOW - 90, NOW - 110])
	check(AudioSlots.pick_slot(_busy(4), prios, young, AudioSlots.PRIO_CRITICAL, 0, NOW) == -1,
		"a second incantation does not cut off one that just started")
	var aged: PackedInt64Array = PackedInt64Array([
		NOW - 100, NOW - 120, NOW - AudioSlots.STEAL_SAME_PRIO_MS - 1, NOW - 110])
	var idx: int = AudioSlots.pick_slot(_busy(4), prios, aged,
		AudioSlots.PRIO_CRITICAL, 0, NOW)
	check(idx == 2, "past STEAL_SAME_PRIO_MS the long-running incantation yields (got %d)" % idx)


## CombatAudio passes steal_same_prio_ms = 0: hits never displace each other,
## the pool size alone caps them.
func test_no_same_prio_steal_when_disabled() -> void:
	var prios: PackedInt32Array = PackedInt32Array([3, 3, 3, 3])
	var starts: PackedInt64Array = PackedInt64Array([
		NOW - 5000, NOW - 5000, NOW - 5000, NOW - 5000])
	var idx: int = AudioSlots.pick_slot(_busy(4), prios, starts,
		AudioSlots.PRIO_NORMAL, 0, NOW, 0)
	check(idx == -1, "same-rank stealing stays off for CombatAudio even on stale slots (got %d)" % idx)


func test_empty_pool_drops() -> void:
	check(AudioSlots.pick_slot([], PackedInt32Array(), PackedInt64Array(),
		AudioSlots.PRIO_CRITICAL, 0, NOW) == -1, "an empty pool has nothing to hand out")


# --- Priority derivation ------------------------------------------------------

func test_default_priority_mapping() -> void:
	check(AudioSlots.default_priority(&"spell_voice_fireball") == AudioSlots.PRIO_CRITICAL,
		"spell incantations are critical")
	check(AudioSlots.default_priority(&"spell_voice_supertornado") == AudioSlots.PRIO_CRITICAL,
		"every incantation matches by prefix, not by a hardcoded list")
	check(AudioSlots.default_priority(&"shaman_death") == AudioSlots.PRIO_CRITICAL,
		"the shaman's death cry is critical")
	check(AudioSlots.default_priority(&"airship_death") == AudioSlots.PRIO_IMPORTANT,
		"airship death is important")
	check(AudioSlots.default_priority(&"siege_death_burn") == AudioSlots.PRIO_IMPORTANT,
		"burning siege engine death is important")
	check(AudioSlots.default_priority(&"siege_death_burst") == AudioSlots.PRIO_IMPORTANT,
		"bursting siege engine death is important")
	check(AudioSlots.default_priority(&"unit_death") == AudioSlots.PRIO_NORMAL,
		"the shared man-sized death cry is ordinary")
	check(AudioSlots.default_priority(&"spell_lightning") == AudioSlots.PRIO_NORMAL,
		"spell EFFECT sounds are ordinary — only the incantation is critical")
	check(AudioSlots.default_priority(&"wood_chop") == AudioSlots.PRIO_NORMAL,
		"unknown names fall back to ordinary")


# --- Loop variants ------------------------------------------------------------

## User report: a tornado with two loop files (spell_tornado_loop_0/_1) only ever
## played one of them, because _activate_loop rolled the variant once and then
## replayed that same stream forever. next_variant re-rolls per repetition.
func test_next_variant_single_file() -> void:
	check(AudioSlots.next_variant(1, -1) == 0, "a single file always plays itself")
	check(AudioSlots.next_variant(1, 0) == 0, "...and repeats without a second choice")
	check(AudioSlots.next_variant(0, -1) == 0, "an empty list cannot pick out of range")


func test_next_variant_never_repeats_itself() -> void:
	# One assertion per (count, current) pair, not per draw — the draws only
	# collect the failures so a rare bad pick cannot hide behind a lucky run.
	for count in [2, 3, 4]:
		for current in range(count):
			var seen: Dictionary = {}
			var out_of_range: int = 0
			var repeats: int = 0
			for _i in range(200):
				var pick: int = AudioSlots.next_variant(count, current)
				if pick < 0 or pick >= count:
					out_of_range += 1
				if pick == current:
					repeats += 1
				seen[pick] = true
			check(out_of_range == 0,
				"count %d: every pick stays inside 0..%d (%d escaped)"
					% [count, count - 1, out_of_range])
			check(repeats == 0,
				"count %d: variant %d is never repeated back to back (%d times)"
					% [count, current, repeats])
			check(seen.size() == count - 1,
				"count %d from %d reaches all %d other variants (got %d)"
					% [count, current, count - 1, seen.size()])


## The first start has no current variant, so every file is reachable there.
func test_next_variant_first_start_uses_all_files() -> void:
	var seen: Dictionary = {}
	for _i in range(200):
		seen[AudioSlots.next_variant(3, -1)] = true
	check(seen.size() == 3, "the initial pick can land on any of the three files")
