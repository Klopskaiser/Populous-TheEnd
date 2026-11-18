extends SceneTree

## WIE STARK IST EINE SITZENDE GOLEMIN? (Diagnose 2026-11-18, kein Test der Suite)
##
## Eine normale Golemin wie in der Startmission (ueber Kills auf die erste Sitzgroesse
## gebracht, 31,3 m), sitzend in der Kartenmitte. Gegnerwellen aus gemischten Truppen
## (Mischung des Ueberlebensmodus: 30 % Feuerkrieger, 10 % Prediger, Rest Krieger) greifen
## gleichzeitig von oben und von unten an: je Welle zwei Trupps, jeder Trupp 25 Einheiten
## in Welle 1 und je Welle 8 mehr (Welle 10: 97), eine Welle alle 30 s, 10 Wellen. Die Trupps
## laufen im Angriffsmarsch auf sie zu; untaetige Angreifer bekommen alle 6 s einen neuen
## Marschbefehl (wie im Ueberlebensmodus). Sie waechst und heilt durch ihre Kills wie im Spiel.
## Ende: sie stirbt, oder alle Wellen sind da und alle Angreifer tot, spaetestens 120 s nach
## der letzten Welle.
##
## Aufruf:
##   godot --headless -s res://tests/diag_golem_sit_waves.gd
##   godot --headless -s res://tests/diag_golem_sit_waves.gd -- mobile   (nur "Stationaer aus")
##   godot --headless -s res://tests/diag_golem_sit_waves.gd -- still    (nur "Stationaer an")
##   godot --headless -s res://tests/diag_golem_sit_waves.gd -- stand    (Vergleich: stehend)
##   ... -- still_fixed / mobile_fixed / stand_fixed: dieselbe Golemin OHNE Wachsen durch Kills (Groesse,
##   Lebensobergrenze und Werte bleiben bei 31,3 m; die Heilung je Kill bleibt) — wie stark ist sie als solche?
## Ohne Argument laufen still, mobile, still_fixed, mobile_fixed.

const GOLEM_SCENE: PackedScene = preload("res://scenes/units/golem.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")
const PREACHER_SCENE: PackedScene = preload("res://scenes/units/preacher.tscn")
const TICK: float = 0.1
const WAVES: int = 10
const WAVE_INTERVAL: float = 30.0
const GROUP_START: int = 25
const GROUP_STEP: int = 8
const REORDER_INTERVAL: float = 6.0
const AFTER_LAST_WAVE: float = 120.0
const CENTRE: Vector3 = Vector3(64, 5, 64)


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


func _free(w: Dictionary) -> void:
	w.tm.free()
	w.wpm.free()
	w.bm.free()
	w.um.free()


func _tick(w: Dictionary) -> void:
	w.bm.tick(TICK)
	for u in w.um.units.duplicate():
		if is_instance_valid(u):
			u.tick(TICK)
	w.um.tick(TICK)


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var modes: Array[String] = ["still", "mobile", "still_fixed", "mobile_fixed"]
	if args.size() > 0 and args[0].trim_suffix("_fixed") in ["still", "mobile", "stand"]:
		modes = [args[0]]
	var seed_value: int = int(args[1]) if args.size() > 1 and args[1].is_valid_int() else 4711
	for m in modes:
		_run(m, seed_value)
	quit()


static func group_size(wave: int) -> int:
	return GROUP_START + GROUP_STEP * (wave - 1)


## The mix of one group (survival mode): 30 % firewarriors, 10 % preachers, the rest warriors.
static func group_mix(n: int) -> Array[PackedScene]:
	@warning_ignore("integer_division")
	var fw: int = n * Balance.SURVIVAL_FIREWARRIOR_PERCENT / 100
	@warning_ignore("integer_division")
	var pr: int = n * Balance.SURVIVAL_PREACHER_PERCENT / 100
	var out: Array[PackedScene] = []
	for i in range(n):
		out.append(FIREWARRIOR_SCENE if i < fw else (PREACHER_SCENE if i < fw + pr else WARRIOR_SCENE))
	out.shuffle()
	return out


func _golem(w: Dictionary, mode: String) -> Golem:
	var g: Golem = w.um.spawn_unit(GOLEM_SCENE, 0, CENTRE) as Golem
	g.facing = Vector3(0, 0, 1)
	g.snap_heading()
	# As the start mission (Main._spawn_chamber_golem): grown by kills to the first sit size.
	while g.height_m() < 30.0 and g.growth_steps < Golem.max_growth_steps():
		g._credit_kill()
	g._stretch_queued = false
	g.health = g.max_health
	g.tick(TICK)
	if mode.begins_with("stand"):
		return g
	g.sit_down()
	var n: int = 0
	while not (g.is_sitting() and not g.is_switching_stance()) and n < 400:
		_tick(w)
		n += 1
	g.set_sit_stationary(mode.begins_with("still"))
	return g


## Spawns one group of `n` at the top (+z) or bottom (-z) edge, in rows, and sends it on.
func _spawn_group(w: Dictionary, n: int, top: bool, g: Golem) -> Array:
	var out: Array = []
	var mix: Array[PackedScene] = group_mix(n)
	var z0: float = 116.0 if top else 12.0
	var dz: float = -1.2 if top else 1.2
	var per_row: int = 24
	for i in range(n):
		@warning_ignore("integer_division")
		var row: int = i / per_row
		var col: int = i % per_row
		var x: float = 64.0 + (float(col) - float(per_row - 1) * 0.5) * 1.3
		var z: float = z0 - dz * float(row)
		var u: Unit = w.um.spawn_unit(mix[i], 1, Vector3(x, 5, z))
		if u == null:
			continue   # the tribe's unit cap
		out.append(u)
	for u in out:
		u.order_move(_aim(g), false, true)
	return out


func _aim(g: Golem) -> Vector3:
	return Vector3(g.position.x + randf_range(-4.0, 4.0), 5.0, g.position.z + randf_range(-4.0, 4.0))


func _alive(list: Array) -> int:
	var n: int = 0
	for u in list:
		if is_instance_valid(u) and u.state != Unit.State.DEAD and not u.doomed:
			n += 1
	return n


func _run(mode: String, seed_value: int = 4711) -> void:
	seed(seed_value)
	var w: Dictionary = _world()
	var g: Golem = _golem(w, mode)
	var fixed: bool = mode.ends_with("_fixed")
	var label: String = {"still": "sitzend, stationaer an", "mobile": "sitzend, stationaer aus (Krebsgang)",
		"stand": "stehend (Vergleich)"}[mode.trim_suffix("_fixed")] + (", OHNE Wachsen" if fixed else "")
	var base_steps: int = g.growth_steps
	var base_level: int = g.level
	var base_max: int = g.max_health
	print("")
	print("=== Golemin %s: %.1f m, %d/%d LP, %d Kills zu Beginn ===" % [label, g.height_m(), g.health, g.max_health, g.kills])
	var kills0: int = g.kills
	var enemies: Array = []
	var spawned: int = 0
	var wanted: int = 0
	var t: float = 0.0
	var next_wave: int = 1
	var reorder: float = REORDER_INTERVAL
	var min_hp: int = g.health
	var died_at: float = -1.0
	var died_wave: int = 0
	var last_wave_t: float = WAVE_INTERVAL * float(WAVES - 1)
	var crab_ticks: int = 0
	var report_at: float = 0.0
	print("  Zeit  Welle  Leben       Hoehe   Kills  Angreifer lebend / gespawnt  | davon Feuerkrieger, vom Sitz erreichbar")
	while true:
		if next_wave <= WAVES and t >= WAVE_INTERVAL * float(next_wave - 1) - 0.0001:
			var n: int = group_size(next_wave)
			wanted += 2 * n
			var a: Array = _spawn_group(w, n, true, g)
			var b: Array = _spawn_group(w, n, false, g)
			spawned += a.size() + b.size()
			enemies.append_array(a)
			enemies.append_array(b)
			if a.size() + b.size() < 2 * n:
				print("  (Welle %d: nur %d von %d gespawnt — Einheitenlimit des Stammes)" % [next_wave, a.size() + b.size(), 2 * n])
			next_wave += 1
		_tick(w)
		t += TICK
		if fixed and is_instance_valid(g) and g.state != Unit.State.DEAD and g.growth_steps != base_steps:
			# No growth from kills: size, health ceiling and values stay (the heal per kill stays).
			g.growth_steps = base_steps
			g.level = base_level
			g.max_health = base_max
			g.health = mini(g.health, base_max)
			g._stretch_queued = false
			g._apply_speed()
		if is_instance_valid(g) and g.is_crabbing():
			crab_ticks += 1
		reorder -= TICK
		if reorder <= 0.0:
			reorder = REORDER_INTERVAL
			for u in enemies:
				if is_instance_valid(u) and u.state == Unit.State.IDLE:
					u.order_move(_aim(g), false, true)
		if is_instance_valid(g) and g.state != Unit.State.DEAD:
			min_hp = mini(min_hp, g.health)
		if t >= report_at - 0.0001:
			report_at += 10.0
			if is_instance_valid(g):
				var fw: int = 0
				var reach: int = 0
				var fw_out: int = 0
				for u in enemies:
					if not is_instance_valid(u) or u.state == Unit.State.DEAD or u.doomed:
						continue
					var hit: bool = g.is_sitting() and not g.is_crabbing() and g._crab_reaches(u)
					if hit:
						reach += 1
					if u is Firewarrior:
						fw += 1
						if not hit:
							fw_out += 1
				print("  %5.0f  %4d   %5d/%-5d  %5.1f m  %5d  %5d / %-5d  | FK %d (%d ausser Reichweite), erreichbar %d" % [t,
					next_wave - 1, maxi(g.health, 0), g.max_health, g.height_m(), g.kills - kills0, _alive(enemies), spawned,
					fw, fw_out, reach])
		if not is_instance_valid(g) or g.state == Unit.State.DEAD:
			died_at = t
			died_wave = next_wave - 1
			break
		if next_wave > WAVES and (_alive(enemies) == 0 or t > last_wave_t + AFTER_LAST_WAVE):
			break
	print("  ---")
	if died_at >= 0.0:
		print("  ERGEBNIS: gefallen nach %.0f s, in Welle %d" % [died_at, died_wave])
	else:
		print("  ERGEBNIS: ueberlebt, %d/%d LP (tiefster Stand %d), Ende nach %.0f s" % [g.health, g.max_health, min_hp, t])
	var kills: int = g.kills - kills0 if is_instance_valid(g) else -1
	print("  Kills %d von %d gespawnten Angreifern (gewollt %d), %d noch am Leben" % [kills, spawned, wanted, _alive(enemies)])
	print("  Groesse am Ende %.1f m; Zeit im Krebsgang %.0f s" % [g.height_m() if is_instance_valid(g) else 0.0, float(crab_ticks) * TICK])
	if is_instance_valid(g):
		_print_stats(g)
	_free(w)


const KIND_NAMES: Dictionary = {
	&"sit_stomp_l": "Fuss-Stampfer links", &"sit_stomp_r": "Fuss-Stampfer rechts",
	&"sit_kick_l": "Bein strecken links", &"sit_kick_r": "Bein strecken rechts",
	&"sit_wipe_l": "Arm-Wischer links", &"sit_wipe_r": "Arm-Wischer rechts",
	&"sit_hop": "Po-Klatscher", &"sit_clap": "Handstampfer hinten", &"sit_double_stomp": "Doppelstampfer",
	&"sit_grow": "Strecken beim Wachsen", &"sit_damage": "Sitzschaden", &"trample": "Trampeln",
	&"crab_trample": "Trampeln im Krebsgang", &"crab_headbutt": "Kopfstoss (Luftschiff)",
	&"kick": "Tritt (Stand)", &"slam": "Handschlag (Stand)", &"drum": "Trommeln (Stand)",
	&"stomp": "Sprung (Stand)", &"swat": "Luftschlag (Stand)",
}


## Attack distribution: per kind strikes, units hit, kills and damage dealt, sorted by damage.
func _print_stats(g: Golem) -> void:
	var total_dmg: int = 0
	var total_kills: int = 0
	var total_strikes: int = 0
	for k in g.attack_stats:
		total_dmg += int(g.attack_stats[k][3])
		total_kills += int(g.attack_stats[k][2])
		total_strikes += int(g.attack_stats[k][0])
	var kinds: Array = g.attack_stats.keys()
	kinds.sort_custom(func(a, b) -> bool: return int(g.attack_stats[a][3]) > int(g.attack_stats[b][3]))
	print("  Angriffsverteilung (Ausloesungen / getroffene Einheiten / Kills / Schaden, Anteil am Schaden):")
	for k in kinds:
		var st: Array = g.attack_stats[k]
		var per: String = (" %.1f je Ausloesung" % (float(st[1]) / float(st[0]))) if int(st[0]) > 0 else ""
		print("    %-24s %5d / %6d / %5d / %7d  %5.1f %%  (%4.1f %% der Ausloesungen)%s" % [KIND_NAMES.get(k, String(k)),
			st[0], st[1], st[2], st[3], 100.0 * float(st[3]) / maxf(float(total_dmg), 1.0),
			100.0 * float(st[0]) / maxf(float(total_strikes), 1.0), per])
