extends TestBase

## Generic unit buffs (2026-09-09): fire resistance, conversion resistance,
## panic resistance, regeneration and strength. The technician's vehicle auras
## are the first user, later spells are meant to be the next ones — so these
## tests pin the MECHANISM, not the technician.
##
## Two design decisions are nailed down here on purpose, because both were
## seriously considered the other way round and would be silently broken by a
## "cleanup" later:
##  * timed buffs count DOWN in the unit's own tick (test_timed_buff_expires...)
##    instead of comparing against a shared clock — almost every test in this
##    suite ticks units directly, where a manager-driven clock would stand still;
##  * a unit with buff work pending refuses the flat combat kernel's hold
##    (test_regen_buff_refuses_the_soa_hold), otherwise "heals during combat"
##    would be a no-op precisely in combat.

const TICK: float = 0.1

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const PREACHER_SCENE: PackedScene = preload("res://scenes/units/preacher.tscn")
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")
const GOLEM_SCENE: PackedScene = preload("res://scenes/units/golem.tscn")


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


func _make_world() -> Dictionary:
	var td: TerrainData = _flat_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var t0: Tribe = Tribe.new(0)
	var t1: Tribe = Tribe.new(1)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [t0, t1] as Array[Tribe])
	return {"td": td, "nav": nav, "t0": t0, "t1": t1, "um": um}


func _free_world(w: Dictionary) -> void:
	w.um.free()


func _spawn(w: Dictionary, scene: PackedScene, tribe_id: int, at: Vector3) -> Unit:
	return w.um.spawn_unit(scene, tribe_id, at)


func _cell(w: Dictionary, x: int, z: int) -> Vector3:
	return w.nav.cell_to_world(Vector2i(x, z))


# --- Core mechanics -----------------------------------------------------------

func test_buff_mask_set_and_cleared() -> void:
	var w: Dictionary = _make_world()
	var u: Unit = _spawn(w, BRAVE_SCENE, 0, _cell(w, 20, 20))
	check(not u.has_any_buff(), "a fresh unit carries no buff")
	check(u.apply_buff(Unit.BUFF_PANIC_RESIST, 5.0), "the grant is accepted")
	check(u.has_buff(Unit.BUFF_PANIC_RESIST), "and the bit is set")
	check(u.has_any_buff(), "has_any_buff sees it")
	check(not u.has_buff(Unit.BUFF_REGEN), "other bits stay clear")
	u.remove_buff(Unit.BUFF_PANIC_RESIST)
	check(not u.has_any_buff(), "removing it clears the mask again")
	_free_world(w)


func test_timed_buff_expires_by_ticking_the_unit() -> void:
	var w: Dictionary = _make_world()
	var u: Unit = _spawn(w, BRAVE_SCENE, 0, _cell(w, 20, 20))
	u.apply_buff(Unit.BUFF_REGEN, 5.0)
	for i in range(49):
		u.tick(TICK)
	check(u.has_buff(Unit.BUFF_REGEN), "still running just under 5 s")
	for i in range(20):
		u.tick(TICK)
	check(not u.has_buff(Unit.BUFF_REGEN), "and gone afterwards")
	_free_world(w)


func test_timed_buff_refresh_keeps_the_longer_time() -> void:
	var w: Dictionary = _make_world()
	var u: Unit = _spawn(w, BRAVE_SCENE, 0, _cell(w, 20, 20))
	u.apply_buff(Unit.BUFF_REGEN, 10.0)
	u.apply_buff(Unit.BUFF_REGEN, 1.0)   # shorter: must not cut the running one
	check_near(u.buff_remaining(Unit.BUFF_REGEN), 10.0,
		"a shorter refresh never shortens a running buff")
	u.apply_buff(Unit.BUFF_REGEN, 20.0)
	check_near(u.buff_remaining(Unit.BUFF_REGEN), 20.0, "a longer one extends it")
	_free_world(w)


func test_aura_buff_has_no_timer() -> void:
	var w: Dictionary = _make_world()
	var u: Unit = _spawn(w, BRAVE_SCENE, 0, _cell(w, 20, 20))
	u.set_aura_buffs(Unit.BUFF_PANIC_RESIST)
	for i in range(600):
		u.tick(TICK)
	check(u.has_buff(Unit.BUFF_PANIC_RESIST), "an aura never times out (60 s)")
	check_near(u.buff_remaining(Unit.BUFF_PANIC_RESIST), 0.0,
		"and reports no remaining time — it is not a grant with a clock")
	u.set_aura_buffs(0)
	check(not u.has_any_buff(), "the holder dropping it ends it at once")
	_free_world(w)


func test_aura_replace_semantics_clears_dropped_bits() -> void:
	var w: Dictionary = _make_world()
	var u: Unit = _spawn(w, BRAVE_SCENE, 0, _cell(w, 20, 20))
	u.set_aura_buffs(Unit.BUFF_FIRE_RESIST | Unit.BUFF_PANIC_RESIST)
	check(u.has_buff(Unit.BUFF_FIRE_RESIST) and u.has_buff(Unit.BUFF_PANIC_RESIST),
		"both aura bits are up")
	u.set_aura_buffs(Unit.BUFF_FIRE_RESIST)
	check(u.has_buff(Unit.BUFF_FIRE_RESIST), "the kept bit stays")
	check(not u.has_buff(Unit.BUFF_PANIC_RESIST), "the dropped one is gone")
	_free_world(w)


func test_an_expiring_spell_does_not_cancel_a_running_aura() -> void:
	var w: Dictionary = _make_world()
	var u: Unit = _spawn(w, BRAVE_SCENE, 0, _cell(w, 20, 20))
	u.set_aura_buffs(Unit.BUFF_REGEN)
	u.apply_buff(Unit.BUFF_REGEN, 1.0)
	for i in range(30):
		u.tick(TICK)
	check(u.has_buff(Unit.BUFF_REGEN), "the aura outlives the timed grant")
	_free_world(w)


func test_dying_clears_all_buffs() -> void:
	var w: Dictionary = _make_world()
	var u: Unit = _spawn(w, BRAVE_SCENE, 0, _cell(w, 20, 20))
	u.set_aura_buffs(Unit.BUFF_STRENGTH, 3)
	u.apply_buff(Unit.BUFF_REGEN, 30.0)
	u.take_damage(9999)
	check(u.state == Unit.State.DEAD, "the unit is dead")
	check(not u.has_any_buff(), "nothing clings to the corpse")
	check_near(u.attack_multiplier(), 1.0, "and the strength factor is back to 1")
	_free_world(w)


# --- Fire resistance ----------------------------------------------------------

func test_fire_resist_caps_the_burn_damage() -> void:
	var w: Dictionary = _make_world()
	var plain: Unit = _spawn(w, BRAVE_SCENE, 0, _cell(w, 20, 20))
	var tough: Unit = _spawn(w, BRAVE_SCENE, 0, _cell(w, 24, 20))
	tough.set_aura_buffs(Unit.BUFF_FIRE_RESIST)
	check_near(plain.effective_burn_dps(), 15.0, "an unbuffed brave burns at 15/s")
	check_near(tough.effective_burn_dps(), Balance.BUFF_FIRE_RESIST_DPS_CAP,
		"fire resistance caps it at 5/s")
	_free_world(w)


func test_fire_resist_never_raises_the_golems_own_trickle() -> void:
	var w: Dictionary = _make_world()
	var g: Unit = _spawn(w, GOLEM_SCENE, 0, _cell(w, 20, 20))
	var before: float = g.effective_burn_dps()
	g.set_aura_buffs(Unit.BUFF_FIRE_RESIST)
	check_near(g.effective_burn_dps(), before,
		"the cap is a minf: it can only ever lower the rate")
	_free_world(w)


func test_fire_resist_prevents_the_burn_panic() -> void:
	var w: Dictionary = _make_world()
	var u: Unit = _spawn(w, BRAVE_SCENE, 0, _cell(w, 20, 20))
	u.set_aura_buffs(Unit.BUFF_FIRE_RESIST)
	u.ignite(u.position + Vector3(1.0, 0.0, 0.0))
	check(u.is_burning(), "it does burn")
	check(u.state != Unit.State.PANIC, "but it does not panic on ignition")
	for i in range(20):
		u.tick(TICK)
		if u.state == Unit.State.PANIC:
			break
	check(u.state != Unit.State.PANIC,
		"and the per-tick panic re-assert does not catch it either")
	_free_world(w)


func test_fire_resist_does_not_block_a_plain_panic() -> void:
	var w: Dictionary = _make_world()
	var u: Unit = _spawn(w, BRAVE_SCENE, 0, _cell(w, 20, 20))
	u.set_aura_buffs(Unit.BUFF_FIRE_RESIST)
	u.start_panic(u.position + Vector3(2.0, 0.0, 0.0))
	check(u.state == Unit.State.PANIC,
		"a swarm still scares him — fire resistance is about fire only")
	_free_world(w)


# --- Panic resistance ---------------------------------------------------------

func test_panic_resist_makes_start_panic_a_no_op() -> void:
	var w: Dictionary = _make_world()
	var u: Unit = _spawn(w, BRAVE_SCENE, 0, _cell(w, 20, 20))
	u.set_aura_buffs(Unit.BUFF_PANIC_RESIST)
	check(u.is_panic_immune(), "the buff reads as panic immunity")
	u.start_panic(u.position + Vector3(2.0, 0.0, 0.0))
	check(u.state != Unit.State.PANIC, "and no panic starts")
	_free_world(w)


func test_panic_resist_keeps_the_damage() -> void:
	var w: Dictionary = _make_world()
	var u: Unit = _spawn(w, BRAVE_SCENE, 0, _cell(w, 20, 20))
	u.set_aura_buffs(Unit.BUFF_PANIC_RESIST)
	var before: int = u.health
	u.take_damage(12)
	check(u.health == before - 12, "damage lands as usual (user spec)")
	_free_world(w)


# --- Regeneration -------------------------------------------------------------

func test_regen_buff_heals_right_after_a_hit() -> void:
	var w: Dictionary = _make_world()
	var u: Unit = _spawn(w, BRAVE_SCENE, 0, _cell(w, 20, 20))
	u.set_aura_buffs(Unit.BUFF_REGEN)
	u.take_damage(30)   # resets _no_combat_timer
	var hurt: int = u.health
	for i in range(10):
		u.tick(TICK)
	check(u.health > hurt, "healing starts inside the out-of-combat delay")
	_free_world(w)


func test_without_the_buff_regeneration_still_waits() -> void:
	var w: Dictionary = _make_world()
	var u: Unit = _spawn(w, BRAVE_SCENE, 0, _cell(w, 20, 20))
	u.take_damage(30)
	var hurt: int = u.health
	for i in range(10):
		u.tick(TICK)
	check(u.health == hurt, "the plain unit is still inside REGEN_DELAY")
	_free_world(w)


func test_regen_buff_refuses_the_soa_hold() -> void:
	var w: Dictionary = _make_world()
	var u: Unit = _spawn(w, BRAVE_SCENE, 0, _cell(w, 20, 20))
	var foe: Unit = _spawn(w, WARRIOR_SCENE, 1, _cell(w, 21, 20))
	u.attack_target = foe
	u.set_aura_buffs(Unit.BUFF_REGEN)
	u._enter_soa_hold()
	check(u._idx >= 0, "the unit is registered with the manager")
	check(w.um.soa_hold[u._idx] < 0.0,
		"a regenerating unit is never parked in the kernel — being held IS combat")
	_free_world(w)


func test_a_plain_unit_still_enters_the_soa_hold() -> void:
	var w: Dictionary = _make_world()
	var u: Unit = _spawn(w, BRAVE_SCENE, 0, _cell(w, 20, 20))
	var foe: Unit = _spawn(w, WARRIOR_SCENE, 1, _cell(w, 21, 20))
	u.attack_target = foe
	u._attack_cooldown = 0.5   # HOLD_MELEE parks the cooldown in the hold slot
	u._enter_soa_hold(0.2)
	check(w.um.soa_hold[u._idx] > 0.0, "counter-check: the gate is not always closed")
	_free_world(w)


# --- Strength -----------------------------------------------------------------

func test_strength_multiplies_melee_damage() -> void:
	var w: Dictionary = _make_world()
	var u: Unit = _spawn(w, BRAVE_SCENE, 0, _cell(w, 20, 20))
	var base: int = u.melee_damage(&"punch")
	u.set_aura_buffs(Unit.BUFF_STRENGTH, 1)
	check_near(u.attack_multiplier(), 1.5, "one stack = 1.5x")
	check(u.melee_damage(&"punch") == int(round(float(base) * 1.5)),
		"and the punch hits that much harder")
	_free_world(w)


func test_strength_stacks_multiply() -> void:
	var w: Dictionary = _make_world()
	var u: Unit = _spawn(w, BRAVE_SCENE, 0, _cell(w, 20, 20))
	u.set_aura_buffs(Unit.BUFF_STRENGTH, 2)
	check_near(u.attack_multiplier(), 2.25, "two stacks = 1.5^2")
	u.set_aura_buffs(Unit.BUFF_STRENGTH, 3)
	check_near(u.attack_multiplier(), 3.375, "three stacks = 1.5^3")
	check(u.buff_stacks(Unit.BUFF_STRENGTH) == 3, "and the count is readable")
	_free_world(w)


func test_strength_stacks_on_top_of_the_warriors_own_multiplier() -> void:
	var w: Dictionary = _make_world()
	var u: Unit = _spawn(w, WARRIOR_SCENE, 0, _cell(w, 20, 20))
	var base: int = u.melee_damage(&"kick")
	u.set_aura_buffs(Unit.BUFF_STRENGTH, 1)
	check(u.melee_damage(&"kick") > base,
		"melee_strength() overrides are not swallowed by the buff")
	check_near(u.melee_strength(), Balance.WARRIOR_MELEE_STRENGTH,
		"and melee_strength() itself is untouched")
	_free_world(w)


func test_strength_scales_the_fireball() -> void:
	var w: Dictionary = _make_world()
	var shooter: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, _cell(w, 20, 20))
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, _cell(w, 24, 20))
	shooter.set_aura_buffs(Unit.BUFF_STRENGTH, 1)
	var full: int = victim.health
	var ball: Fireball = Fireball.new()
	ball.setup(shooter, victim, shooter.position + Vector3(0.0, 1.1, 0.0))
	check_near(ball.strength_mult, 1.5, "the ball takes the multiplier along")
	for i in range(60):
		ball.tick(TICK)
		if ball.done:
			break
	var expected: int = int(round(float(Unit.FIREBALL_DAMAGE) * 1.5))
	check(full - victim.health == expected,
		"a strengthened firewarrior burns %d instead of %d" % [
			expected, Unit.FIREBALL_DAMAGE])
	ball.free()
	_free_world(w)


func test_the_fireball_freezes_the_multiplier_at_launch() -> void:
	var w: Dictionary = _make_world()
	var shooter: Unit = _spawn(w, FIREWARRIOR_SCENE, 0, _cell(w, 20, 20))
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, _cell(w, 24, 20))
	shooter.set_aura_buffs(Unit.BUFF_STRENGTH, 1)
	var ball: Fireball = Fireball.new()
	ball.setup(shooter, victim, shooter.position + Vector3(0.0, 1.1, 0.0))
	shooter.set_aura_buffs(0)   # buff lost while the ball is in the air
	check_near(ball.strength_mult, 1.5,
		"the shot keeps the strength it was fired with")
	ball.free()
	_free_world(w)


# --- Conversion resistance ----------------------------------------------------

func test_convert_resist_refuses_the_first_attempt() -> void:
	var w: Dictionary = _make_world()
	var pr: Unit = _spawn(w, PREACHER_SCENE, 0, _cell(w, 20, 20))
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, _cell(w, 22, 20))
	victim.set_aura_buffs(Unit.BUFF_CONVERT_RESIST)
	check(not victim.begin_conversion(pr, 5.0), "the first sermon does not seat it")
	check(victim.state != Unit.State.SIT, "it keeps standing")
	check(victim.sermon_warming_for(pr), "but the sermon IS running")
	_free_world(w)


func test_convert_resist_seats_after_the_delay() -> void:
	var w: Dictionary = _make_world()
	var pr: Unit = _spawn(w, PREACHER_SCENE, 0, _cell(w, 20, 20))
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, _cell(w, 22, 20))
	victim.set_aura_buffs(Unit.BUFF_CONVERT_RESIST)
	var seated: bool = false
	for i in range(60):
		if victim.begin_conversion(pr, 5.0):
			seated = true
			break
		victim.tick(TICK)
	check(seated, "after enough preaching it sits down")
	check(victim.state == Unit.State.SIT, "and is in the trance")
	_free_world(w)


func test_convert_resist_warmup_lapses_when_the_preacher_stops() -> void:
	var w: Dictionary = _make_world()
	var pr: Unit = _spawn(w, PREACHER_SCENE, 0, _cell(w, 20, 20))
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, _cell(w, 22, 20))
	victim.set_aura_buffs(Unit.BUFF_CONVERT_RESIST)
	for i in range(10):
		victim.begin_conversion(pr, 5.0)
		victim.tick(TICK)
	check(victim.sermon_warming_for(pr), "the warm-up is under way")
	for i in range(int(Balance.BUFF_CONVERT_RESIST_GRACE / TICK) + 3):
		victim.tick(TICK)   # the preacher stops trying
	check(not victim.sermon_warming_for(pr), "a broken-off sermon lapses")
	_free_world(w)


func test_two_preachers_do_not_reset_each_other() -> void:
	var w: Dictionary = _make_world()
	var a: Unit = _spawn(w, PREACHER_SCENE, 0, _cell(w, 20, 20))
	var b: Unit = _spawn(w, PREACHER_SCENE, 0, _cell(w, 20, 22))
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, _cell(w, 22, 21))
	victim.set_aura_buffs(Unit.BUFF_CONVERT_RESIST)
	var seated: bool = false
	for i in range(60):
		if victim.begin_conversion(a, 5.0):
			seated = true
			break
		check(not victim.begin_conversion(b, 5.0),
			"the second preacher never takes the slot from the incumbent")
		victim.tick(TICK)
	check(seated, "and the incumbent still gets there — no deadlock")
	check(victim.converting_preacher == a, "it is A's convert, not B's")
	_free_world(w)


func test_without_the_buff_conversion_is_instant() -> void:
	var w: Dictionary = _make_world()
	var pr: Unit = _spawn(w, PREACHER_SCENE, 0, _cell(w, 20, 20))
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, _cell(w, 22, 20))
	check(victim.begin_conversion(pr, 5.0), "an unbuffed unit sits down at once")
	check(victim.state == Unit.State.SIT, "no warm-up for anybody else")
	_free_world(w)


func test_standing_up_restarts_the_warmup() -> void:
	var w: Dictionary = _make_world()
	var pr: Unit = _spawn(w, PREACHER_SCENE, 0, _cell(w, 20, 20))
	var victim: Unit = _spawn(w, BRAVE_SCENE, 1, _cell(w, 22, 20))
	victim.set_aura_buffs(Unit.BUFF_CONVERT_RESIST)
	for i in range(60):
		if victim.begin_conversion(pr, 9.0):
			break
		victim.tick(TICK)
	check(victim.state == Unit.State.SIT, "seated")
	victim._stand_up(false)
	check(not victim.begin_conversion(pr, 9.0),
		"after standing up the full warm-up has to be paid again")
	_free_world(w)


# --- Overlay glyph ------------------------------------------------------------

func test_a_buffed_unit_carries_the_overlay_bit() -> void:
	var w: Dictionary = _make_world()
	var fx: StatusFxRenderer = StatusFxRenderer.new()
	var u: Unit = _spawn(w, BRAVE_SCENE, 0, _cell(w, 20, 20))
	check(fx.status_mask(u) & StatusFxRenderer.FX_BUFF == 0, "nothing without a buff")
	u.set_aura_buffs(Unit.BUFF_REGEN)
	check(fx.status_mask(u) & StatusFxRenderer.FX_BUFF != 0, "the bit appears")
	fx.free()
	_free_world(w)


func test_the_buff_glyph_yields_to_fire_panic_and_hypnosis() -> void:
	var buff: int = StatusFxRenderer.FX_BUFF
	check(StatusFxRenderer.visual_mask_of(buff) == buff, "alone it is drawn")
	check(StatusFxRenderer.visual_mask_of(buff | StatusFxRenderer.FX_BURNING) \
		== StatusFxRenderer.FX_BURNING, "the flame wins")
	check(StatusFxRenderer.visual_mask_of(buff | StatusFxRenderer.FX_PANIC) \
		== StatusFxRenderer.FX_PANIC, "panic wins")
	check(StatusFxRenderer.visual_mask_of(buff | StatusFxRenderer.FX_HYPNOTIZED) \
		== StatusFxRenderer.FX_HYPNOTIZED, "the hypnosis spiral wins")
