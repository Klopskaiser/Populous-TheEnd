extends SceneTree

## GOLEM IM KAMPF — Protokoll der Entscheidungen (Recherche 2026-11-16, kein Test).
##
## Stellt einen Golem auf ebenem Boden gegen anrennende Krieger und protokolliert
## jeden Haltungswechsel und jeden Angriff mit dem, was die Angriffswahl in dem
## Moment sah (erwarteter Schaden je Angriff, Abstand des Ziels, Reichweite).
## Gezaehlt wird insbesondere "Tritt kurz nach dem Buecken": sie bueckt sich, und
## innerhalb von FOLLOW Sekunden nach dem Aufrichten kommt ein Tritt.
## Aufruf:
##   godot --headless -s res://tests/diag_golem_fight.gd
##   godot --headless -s res://tests/diag_golem_fight.gd -- 7 30 log
##     (Stufe, Zahl der Krieger, "log" = jedes Ereignis drucken)

const GOLEM_SCENE: PackedScene = preload("res://scenes/units/golem.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const TICK: float = 0.05
const FOLLOW: float = 3.0


func _world() -> Dictionary:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = 5.0
	var nav: NavGrid = NavGrid.new(td)
	var t0: Tribe = Tribe.new(0)
	var t1: Tribe = Tribe.new(1)
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [t0, t1] as Array[Tribe], tm, wpm)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um, wpm)
	um.building_manager = bm
	return {"td": td, "nav": nav, "t0": t0, "t1": t1, "um": um, "bm": bm, "tm": tm, "wpm": wpm}


func _tick(w: Dictionary) -> void:
	w.bm.tick(TICK)
	for u in w.um.units.duplicate():
		if is_instance_valid(u):
			u.tick(TICK)
	w.um.tick(TICK)


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var levels: Array[int] = [0, 3, 6, 7]
	var counts: Array[int] = [8, 20]
	var log_all: bool = false
	if args.size() > 0 and args[0].is_valid_int():
		levels = [int(args[0])]
	if args.size() > 1 and args[1].is_valid_int():
		counts = [int(args[1])]
	if args.size() > 2 and args[2] == "log":
		log_all = true
	for lvl in levels:
		for n in counts:
			for seed in [1, 2, 3]:
				_run(lvl, n, seed, log_all)
	quit()


func _values(g: Golem) -> String:
	if not (g.attack_target is Unit) and g.attack_building == null:
		return "kein Ziel"
	return "Wert/s Tritt %.0f Hand %.0f Trommel %.0f Sprung %.0f | Schaden Tritt %.0f Hand %.0f Trommel %.0f" % [
		g.attack_value(Golem.ATTACK_KICK), g.attack_value(Golem.ATTACK_SLAM), g.attack_value(Golem.ATTACK_DRUM),
		g.attack_value(Golem.ATTACK_STOMP) if g.can_stomp() else 0.0,
		g.attack_worth(Golem.ATTACK_KICK), g.attack_worth(Golem.ATTACK_SLAM), g.attack_worth(Golem.ATTACK_DRUM)]


func _target_info(g: Golem) -> String:
	if g.attack_target != null and is_instance_valid(g.attack_target):
		var d: float = Vector2(g.attack_target.position.x - g.position.x, g.attack_target.position.z - g.position.z).length()
		return "Ziel %.1f m (Reichweite %.1f, Handkreis bis %.1f vor ihr)" % [d, g.reach(),
			Balance.GOLEM_SLAM_FORWARD * g.limb_factor() + g.slam_radius()]
	return "Ziel -"


func _run(level: int, count: int, seed: int, log_all: bool) -> void:
	seed(seed)
	var w: Dictionary = _world()
	var g: Golem = w.um.spawn_unit(GOLEM_SCENE, 0, Vector3(64, 5, 64)) as Golem
	while g.level < level:
		g._credit_kill()
	g._stretch_queued = false
	g.max_health = 100000
	g.health = 100000
	g.stomp_enabled = true
	# Kein Wachsen waehrend der Messung (die Stufe soll bleiben): Kills nicht gutschreiben
	var warriors: Array = []
	for i in range(count):
		var ang: float = TAU * float(i) / float(count) * 0.35 + 0.3 * float(seed)
		var r: float = 12.0 + g.reach() + float(i % 4) * 1.5
		var u: Unit = w.um.spawn_unit(WARRIOR_SCENE, 1, Vector3(64 + cos(ang) * r, 5, 64 + sin(ang) * r))
		u.max_health = 400
		u.health = 400
		warriors.append(u)
	for u in warriors:
		u.order_attack(g)
	var t: float = 0.0
	var was_switching: bool = false
	var last_stance: int = g.stance
	var last_pending: StringName = &""
	var crouched_at: float = -100.0
	var stood_at: float = -100.0
	var crouch_reason: String = ""
	var kicks_after_crouch: int = 0
	var crouches: int = 0
	var attacks: Dictionary = {}
	var lines: Array[String] = []
	var kick_samples: Array[String] = []
	while t < 40.0:
		var before_values: String = _values(g)
		var before_target: String = _target_info(g)
		var target_before = g.attack_target
		var lvl_before: int = g.level
		var kills_before: int = g.kills
		_tick(w)
		t += TICK
		if g.kills != kills_before:
			pass
		var switching: bool = g.is_switching_stance()
		if switching and not was_switching:
			var to: String = "buecken" if g._stance_target == Golem.STANCE_CROUCH else "aufrichten"
			if g._stance_target == Golem.STANCE_CROUCH:
				crouches += 1
				crouch_reason = before_values + " | " + before_target
			var why: String = "Zustand %s, im Nahkampf %s, Ziel gewechselt %s, Haltung seit %.2f s, Ziel jetzt %s" % [
				Unit.State.keys()[g.state], g._in_melee, g.attack_target != target_before, g._stance_age, _target_info(g)]
			lines.append("%6.2f s  %s  | %s | %s
           %s" % [t, to, before_values, before_target, why])
		if g.stance != last_stance:
			if g.stance == Golem.STANCE_CROUCH:
				crouched_at = t
			else:
				stood_at = t
			last_stance = g.stance
		was_switching = switching
		if g._pending_attack != &"" and last_pending == &"":
			var k: StringName = g._pending_attack
			attacks[k] = int(attacks.get(k, 0)) + 1
			lines.append("%6.2f s  %s (Haltung %s) | %s | %s" % [t, k, "gebueckt" if g.stance == Golem.STANCE_CROUCH else "stehend", before_values, before_target])
			if k == Golem.ATTACK_KICK and crouched_at > 0.0 and t - stood_at < FOLLOW and stood_at > crouched_at:
				kicks_after_crouch += 1
				if kick_samples.size() < 3:
					kick_samples.append("    gebueckt bei %.2f s, aufgerichtet %.2f s, Tritt %.2f s\n      beim Buecken: %s\n      beim Tritt:   %s | %s" % [
						crouched_at, stood_at, t, crouch_reason, before_values, before_target])
		last_pending = g._pending_attack
		if g.level != lvl_before:
			pass
	var alive: int = 0
	for u in warriors:
		if is_instance_valid(u) and u.state != Unit.State.DEAD:
			alive += 1
	print("Stufe %d (%.1f m, Reichweite %.1f, Handkreis bis %.1f), %d Krieger, Lauf %d: Angriffe %s, Buecken %d, Tritt kurz nach dem Buecken %d, Krieger uebrig %d, Kills %d" % [
		level, g.height_m(), g.reach(), Balance.GOLEM_SLAM_FORWARD * g.limb_factor() + g.slam_radius(),
		count, seed, attacks, crouches, kicks_after_crouch, alive, g.kills])
	for s in kick_samples:
		print(s)
	if log_all:
		for l in lines:
			print(l)
	w.tm.free()
	w.wpm.free()
	w.bm.free()
	w.um.free()
