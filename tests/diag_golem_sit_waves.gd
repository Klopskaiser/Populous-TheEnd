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
##   ... -- mobile_x15 [seed]: WACHSENDE WELLEN (Nutzerwunsch 2026-11-18): sitzend, stationaer aus, mit Wachsen;
##   Welle 1 je Trupp 25 (Sueden und Norden), jede Welle 1,5-mal so gross wie die davor (gerundet), alle 30 s, bis sie
##   faellt (hoechstens X15_WAVES Wellen). Dafuer eine 256er-Karte (gleicher Anmarsch: Front 52 m vor ihr, breitere
##   Reihen) und KEIN Einheitenlimit fuer den Angreiferstamm (nur in dieser Diagnose).
##   ... -- mobile_ramp [seed]: wie mobile, aber die ersten RAMP_FLAT_WAVES Wellen bleiben bei GROUP_START je Trupp,
##   danach wieder die normale Kurve (Welle 5: 25 + 4 x 8 = 57, dann +8 je Welle; Nutzerwunsch 2026-11-19).
##   ... -- demon_<modus> [seed] (z. B. demon_mobile): dasselbe mit der Daemonengolemin, ab ihrer ersten moeglichen
##   Sitzgroesse (32 m, durch Kills gewachsen wie im Spiel).
## Ohne Argument laufen still, mobile, still_fixed, mobile_fixed.
## Fehlersuche: Umgebungsvariable GOLEM_TRACE=<s> druckt ab dieser Zeit jeden Tick ihren Zustand (Leben, Krebsgang,
## Drehen, Strecken, ausstehende Angriffe, Abklingzeiten); GOLEM_ZONES=1 dazu je Sitzzone die Feinde darin und die im
## 30-m-Umkreis in keiner Zone, GOLEM_ZONES=pos auch deren Lage zu ihr (voraus / seitlich).

const GOLEM_SCENE: PackedScene = preload("res://scenes/units/golem.tscn")
const DEMON_SCENE: PackedScene = preload("res://scenes/units/demon_golem.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")
const PREACHER_SCENE: PackedScene = preload("res://scenes/units/preacher.tscn")
const TICK: float = 0.1
const WAVES: int = 10
const WAVE_INTERVAL: float = 30.0
const GROUP_START: int = 25
const GROUP_STEP: int = 8
## mobile_ramp: so viele Wellen bleiben bei GROUP_START, danach die normale Kurve.
const RAMP_FLAT_WAVES: int = 4
const REORDER_INTERVAL: float = 6.0
const AFTER_LAST_WAVE: float = 120.0
const X15_FACTOR: float = 1.5
const X15_WAVES: int = 12
const X15_MAP: int = 256
## Distance of a group's front row from her (all modes).
const FRONT_DIST: float = 52.0

var _centre: Vector3 = Vector3(64, 5, 64)
var _x15: bool = false
var _ramp: bool = false


## The attackers' tribe in the growing waves: no unit cap (only in this diagnosis).
class UncappedTribe extends Tribe:
	func _init(p_id: int) -> void:
		super(p_id)

	func at_unit_cap() -> bool:
		return false


func _world() -> Dictionary:
	var td: TerrainData = TerrainData.new(X15_MAP if _x15 else TerrainData.SIZE)
	for i in range(td.heights.size()):
		td.heights[i] = 5.0
	var nav: NavGrid = NavGrid.new(td)
	var t0: Tribe = Tribe.new(0)
	var t1: Tribe = UncappedTribe.new(1) if _x15 else Tribe.new(1)
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
	var base_arg: String = args[0].trim_prefix("demon_") if args.size() > 0 else ""
	if args.size() > 0 and (base_arg.trim_suffix("_fixed") in ["still", "mobile", "stand", "mobile_ramp"] or base_arg == "mobile_x15"):
		modes = [args[0]]
	var seed_value: int = int(args[1]) if args.size() > 1 and args[1].is_valid_int() else 4711
	for m in modes:
		_run(m, seed_value)
	quit()


func group_size(wave: int) -> int:
	if _x15:
		return roundi(float(GROUP_START) * pow(X15_FACTOR, wave - 1))
	if _ramp and wave <= RAMP_FLAT_WAVES:
		return GROUP_START
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
	var scene: PackedScene = DEMON_SCENE if mode.begins_with("demon_") else GOLEM_SCENE
	mode = mode.trim_prefix("demon_")
	var g: Golem = w.um.spawn_unit(scene, 0, _centre) as Golem
	g.facing = Vector3(0, 0, 1)
	g.snap_heading()
	# As the start mission (Main._spawn_chamber_golem): grown by kills to the first sit size.
	while not g.can_sit() and g.kills < 2000:
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
	var z0: float = _centre.z + FRONT_DIST if top else _centre.z - FRONT_DIST
	var dz: float = -1.2 if top else 1.2
	# Big groups stand in wider rows (at most ~16 rows deep), so they stay on the disc.
	var per_row: int = maxi(24, ceili(float(n) / 16.0))
	for i in range(n):
		@warning_ignore("integer_division")
		var row: int = i / per_row
		var col: int = i % per_row
		var x: float = _centre.x + (float(col) - float(per_row - 1) * 0.5) * 1.3
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
	var demon: bool = mode.begins_with("demon_")
	var base_mode: String = mode.trim_prefix("demon_")
	_x15 = base_mode == "mobile_x15"
	_ramp = base_mode.trim_suffix("_fixed") == "mobile_ramp"
	_centre = Vector3(float(X15_MAP) * 0.5, 5, float(X15_MAP) * 0.5) if _x15 else Vector3(64, 5, 64)
	var waves: int = X15_WAVES if _x15 else WAVES
	var w: Dictionary = _world()
	var g: Golem = _golem(w, mode)
	var fixed: bool = base_mode.ends_with("_fixed")
	var label: String = {"still": "sitzend, stationaer an", "mobile": "sitzend, stationaer aus (Krebsgang)",
		"stand": "stehend (Vergleich)", "mobile_x15": "sitzend, stationaer aus, Wellen x1,5",
		"mobile_ramp": "sitzend, stationaer aus, Wellen 1-4 je 25, dann +8"}[base_mode.trim_suffix("_fixed")] \
		+ (", OHNE Wachsen" if fixed else "")
	var base_steps: int = g.growth_steps
	var base_level: int = g.level
	var base_max: int = g.max_health
	print("")
	print("=== %s %s: %.1f m, %d/%d LP, %d Kills zu Beginn ===" % ["Daemonengolemin" if demon else "Golemin", label, g.height_m(), g.health, g.max_health, g.kills])
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
	var last_wave_t: float = WAVE_INTERVAL * float(waves - 1)
	var started_ms: int = Time.get_ticks_msec()
	var crab_ticks: int = 0
	var melee_peak: Dictionary = {}
	var melee_next: float = 0.0
	var report_at: float = 0.0
	print("  Zeit  Welle  Leben       Hoehe   Kills  Angreifer lebend / gespawnt  | davon Feuerkrieger, vom Sitz erreichbar")
	while true:
		if next_wave <= waves and t >= WAVE_INTERVAL * float(next_wave - 1) - 0.0001:
			var n: int = group_size(next_wave)
			wanted += 2 * n
			var a: Array = _spawn_group(w, n, true, g)
			var b: Array = _spawn_group(w, n, false, g)
			spawned += a.size() + b.size()
			enemies.append_array(a)
			enemies.append_array(b)
			if a.size() + b.size() < 2 * n:
				print("  (Welle %d: nur %d von %d gespawnt — Einheitenlimit des Stammes)" % [next_wave, a.size() + b.size(), 2 * n])
			if _x15 or _ramp:
				print("  >> Welle %d bei %.0f s: 2 x %d (vorher noch %d lebend; Golemin %.1f m, %d/%d LP)" % [next_wave, t, n,
					_alive(enemies) - a.size() - b.size(), g.height_m(), g.health, g.max_health])
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
		if is_instance_valid(g) and g.state != Unit.State.DEAD and t >= melee_next:
			melee_next += 1.0
			var ms: Dictionary = _melee_stats(g, enemies)
			if int(ms.n) > int(melee_peak.get("n", -1)):
				melee_peak = ms
				melee_peak["t"] = t
		if OS.get_environment("GOLEM_TRACE") != "" and t >= float(OS.get_environment("GOLEM_TRACE")) and is_instance_valid(g):
			var near: int = 0
			for u in enemies:
				if is_instance_valid(u) and u.state != Unit.State.DEAD and Vector2(u.position.x - g.position.x, u.position.z - g.position.z).length() < g.target_radius() + 3.0:
					near += 1
			if g.sit_combat != null and not g.is_crabbing() and OS.get_environment("GOLEM_ZONES") != "":
				var zc: Dictionary = {}
				var none: int = 0
				var nonefw: int = 0
				for u in enemies:
					if not is_instance_valid(u) or u.state == Unit.State.DEAD or u.doomed:
						continue
					var d: float = Vector2(u.position.x - g.position.x, u.position.z - g.position.z).length()
					if d > 30.0:
						continue
					var any: bool = false
					for k in GolemSitCombat.KINDS:
						if g.sit_combat.in_area(k, u.position):
							zc[k] = zc.get(k, 0) + 1
							any = true
					if not any:
						none += 1
						if u is Firewarrior:
							nonefw += 1
						if OS.get_environment("GOLEM_ZONES") == "pos":
							var rel: Vector3 = u.position - g.position
							var h: Vector3 = g.heading()
							print("      out: %s ahead %.1f side %.1f d %.1f st %d" % ["FK" if u is Firewarrior else "NK", rel.dot(h), rel.dot(Vector3(h.z, 0, -h.x)), d, u.state])
				print("    zones %s, within 30 m in no zone %d (FK %d), target_radius %.1f" % [str(zc), none, nonefw, g.target_radius()])
			print("    t %.1f hp %d st %d crab %d sw %s pos (%.1f %.1f %.1f) near %d stretch %s sitstr %s turn %s esc %s pend %s cd %s grow %.1f strikes %d sc %s" % [t, g.health, g.state, g._crab, g.is_switching_stance(), g.position.x, g.position.y, g.position.z, near, g.is_stretching(), g.sit_stretching(), g.sit_combat.turning if g.sit_combat else null, g.sit_combat._turn_escape if g.sit_combat else null, str(g.sit_combat.pending) if g.sit_combat else "", str(g.sit_combat.cooldown) if g.sit_combat else "", g.sit_combat._grow_left if g.sit_combat else 0.0, _strikes(g), g.sit_combat != null])
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
		if next_wave > waves and (_alive(enemies) == 0 or t > last_wave_t + AFTER_LAST_WAVE):
			break
	print("  ---")
	if died_at >= 0.0:
		print("  ERGEBNIS: gefallen nach %.0f s, in Welle %d" % [died_at, died_wave])
	else:
		print("  ERGEBNIS: ueberlebt, %d/%d LP (tiefster Stand %d), Ende nach %.0f s" % [g.health, g.max_health, min_hp, t])
	var kills: int = g.kills - kills0 if is_instance_valid(g) else -1
	print("  Kills %d von %d gespawnten Angreifern (gewollt %d), %d noch am Leben" % [kills, spawned, wanted, _alive(enemies)])
	print("  Groesse am Ende %.1f m; Zeit im Krebsgang %.0f s; Rechenzeit %.0f s" % [g.height_m() if is_instance_valid(g) else 0.0,
		float(crab_ticks) * TICK, float(Time.get_ticks_msec() - started_ms) / 1000.0])
	if not melee_peak.is_empty():
		print("  Nahkampf am Koerper, Hoechststand bei %.0f s (%.1f m, Zielradius %.2f m, Ring %.2f m): %d Nahkaempfer in" % [
			melee_peak.t, melee_peak.h, melee_peak.tr, melee_peak.tr + Unit.MELEE_RANGE, melee_peak.n]
			+ " Reichweite, davon %d innerhalb des Zielradius (unter ihr); Abstand zum naechsten Nahkaempfer: min %.2f m, Median %.2f m;" % [
			melee_peak.inside, melee_peak.nn_min, melee_peak.nn_med]
			+ " belegter Bogen %.0f Grad;" % melee_peak.arc
			+ " %d naeher als 0,3 m, %d naeher als 0,2 m; Ring-Plaetze bei 1 m: %d, bei 0,44 m (Abstandsregel): %d" % [
			melee_peak.close3, melee_peak.close2, melee_peak.slots_1m, melee_peak.slots_sep])
	if is_instance_valid(g):
		_print_stats(g)
		var taken: int = 0
		for k in g.damage_taken:
			taken += int(g.damage_taken[k])
		var parts: PackedStringArray = []
		for k in g.damage_taken:
			parts.append("%s %d (%.0f %%)" % [k, g.damage_taken[k], 100.0 * float(g.damage_taken[k]) / maxf(float(taken), 1.0)])
		print("  Erlittener Schaden %d: %s" % [taken, ", ".join(parts)])
	_free(w)


const KIND_NAMES: Dictionary = {
	&"sit_stomp_l": "Fuss-Stampfer links", &"sit_stomp_r": "Fuss-Stampfer rechts",
	&"sit_kick_l": "Bein strecken links", &"sit_kick_r": "Bein strecken rechts",
	&"sit_wipe_l": "Arm-Wischer links", &"sit_wipe_r": "Arm-Wischer rechts",
	&"sit_hand_slam_l": "Handschlag seitlich links", &"sit_hand_slam_r": "Handschlag seitlich rechts",
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


func _strikes(g: Golem) -> int:
	var n: int = 0
	for k in g.attack_stats:
		n += int(g.attack_stats[k][0])
	return n


## Melee fighters striking her right now: in reach of her target circle, attacking her, not firewarriors —
## how many, how many stand inside the circle (under her), and how close they stand to each other.
func _melee_stats(g: Golem, enemies: Array) -> Dictionary:
	var tr: float = g.target_radius()
	var pts: Array[Vector2] = []
	var angles: Array[float] = []
	var inside: int = 0
	for u in enemies:
		if not is_instance_valid(u) or u.state != Unit.State.ATTACK or u.attack_target != g or u is Firewarrior:
			continue
		var d: float = Vector2(u.position.x - g.position.x, u.position.z - g.position.z).length()
		if d - tr > Unit.MELEE_RANGE:
			continue
		pts.append(Vector2(u.position.x, u.position.z))
		angles.append(atan2(u.position.x - g.position.x, u.position.z - g.position.z))
		if d < tr:
			inside += 1
	var nn: Array[float] = []
	var close3: int = 0
	var close2: int = 0
	for i in range(pts.size()):
		var best: float = INF
		for k in range(pts.size()):
			if k != i:
				best = minf(best, pts[i].distance_to(pts[k]))
		if best < INF:
			nn.append(best)
			if best < 0.3:
				close3 += 1
			if best < 0.2:
				close2 += 1
	nn.sort()
	angles.sort()
	var gap: float = TAU
	for i in range(angles.size()):
		var nxt: float = angles[(i + 1) % angles.size()] + (TAU if i == angles.size() - 1 else 0.0)
		gap = minf(gap, TAU) if angles.size() < 2 else (maxf(nxt - angles[i], 0.0) if i == 0 else maxf(gap, nxt - angles[i]))
	var arc: float = 0.0 if angles.size() < 2 else rad_to_deg(TAU - gap)
	var ring: float = TAU * (tr + Unit.MELEE_SLOT_RADIUS)
	@warning_ignore("integer_division")
	var mid: int = nn.size() / 2
	return {"n": pts.size(), "inside": inside, "h": g.height_m(), "tr": tr,
		"nn_min": nn[0] if not nn.is_empty() else 0.0, "nn_med": nn[mid] if not nn.is_empty() else 0.0,
		"arc": arc, "close3": close3, "close2": close2, "slots_1m": int(ring / 1.0), "slots_sep": int(ring / UnitManager.SEPARATION_RADIUS)}
