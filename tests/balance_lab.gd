extends SceneTree

## BALANCE-LABOR — dritte Werkzeugkategorie neben tests/ und benchmark_*.
##
## tests/test_*.gd  : Zusicherungen, kennt die richtige Antwort vorher.
## tests/benchmark_*: Performance, misst Millisekunden.
## DIESES Skript    : Kampfkraft, misst AUSGÄNGE. Es urteilt NICHT — es stellt
##                    Aufstellungen gegeneinander, lässt sie ausfechten und gibt
##                    Zahlen aus, aus denen man Balance-Aussagen ableiten kann.
##
## Es hat deshalb bewusst KEINE Sollwerte und darf nie fehlschlagen: ein
## überraschendes Ergebnis ist das Produkt, nicht ein Fehler.
##
## NICHT Teil der Testsuite (kein test_-Präfix). Aufruf:
##   godot --headless -s res://tests/balance_lab.gd
##   godot --headless -s res://tests/balance_lab.gd -- scenario=krieger_vs_feuerkrieger
##   godot --headless -s res://tests/balance_lab.gd -- reps=9 seconds=120 csv=1
##
## WÄHRUNG: Einheiten kosten kein Holz, sondern **Braves und Ausbildungszeit**
## (Holz kostet nur das Gebäude bzw. der Fahrzeugrumpf). Die Effizienz wird
## deshalb in **Brave-Äquivalenten (BÄ)** gerechnet — das ist die wirklich knappe
## Ressource. Ein Katapult mit 3 Mann Besatzung kostet 3 BÄ + 6 Holz, drei
## Krieger kosten 3 BÄ + 9 s Ausbildung. Erst dieser Vergleich beantwortet
## "lohnt sich das Fahrzeug?".
##
## GELÄNDE ist absichtlich FLACH: auf einer Insel entscheidet sonst mit, wer den
## Hügel erwischt hat, und die Streuung erschlägt den Effekt, der gemessen werden
## soll. Wer Geländeeinfluss messen will, nimmt map=insel.
##
## GRENZEN DIESES LABORS — beim Deuten der Zahlen mitdenken:
## - KEINE ZAUBER. Die Schamanin ist hier nur eine Nahkämpferin mit 240 HP; ihre
##   eigentliche Macht (10 Zauber) wird nicht gemessen.
## - KEINE GEBÄUDE. Katapult und Feuerramme sind BELAGERUNGSwaffen; gegen reine
##   Fußtruppen gemessen sind sie systematisch unterbewertet. Für ein faires Bild
##   fehlt ein Szenario "Fahrzeuge gegen Basis".
## - DICHTER KLUMPEN, beide Seiten auf Angriffsbewegung. Das ist der Normalfall
##   einer KI-Schlacht, aber nicht der einer gespielten Formation.
## - Kills allein täuschen: der Schadensanteil steht daneben, weil verteilter
##   Schaden viel Wirkung ohne einen einzigen Kill erzeugt.

const TICK: float = 1.0 / 30.0
const BASE_SEED: int = 20260804
## Abbruch, wenn nach so vielen Sekunden keine Seite ausgelöscht ist.
const DEFAULT_SECONDS: float = 90.0
## Wiederholungen je Paarung (unterschiedliche Seeds). Kampf ist verrauscht
## (Schlag-/Schubs-/Bekehrwürfe, Zielwahl), ein Einzellauf sagt wenig.
const DEFAULT_REPS: int = 5
## Startabstand der beiden Aufstellungen in Zellen.
const SEPARATION: int = 26
## Flache Karte: kein Höhenvorteil, keine Klippen, kein Ertrinken.
const GROUND_HEIGHT: float = 5.0

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")
const PREACHER_SCENE: PackedScene = preload("res://scenes/units/preacher.tscn")
const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")
const SIEGE_SCENE: PackedScene = preload("res://scenes/units/siege_engine.tscn")
const FIRERAM_SCENE: PackedScene = preload("res://scenes/units/fire_ram.tscn")
const AIRSHIP_SCENE: PackedScene = preload("res://scenes/units/airship.tscn")

## Einheitenarten: Szene, Standard-Besatzung (0 = keine), Rumpfholz,
## Ausbildungs-/Bauzeit in Sekunden (für die Zeit-Spalte) und `crew_kind` =
## Einheitenart der Besatzung.
## Die BÄ-Kosten sind 1 je Fußeinheit und `crew` je Fahrzeug.
##
## `crew_kind` (10i Teil 5) korrigiert einen ungültigen Laborbefund: Fahrzeuge
## wurden ausnahmslos mit BRAVES besetzt. Für Katapult und Ramme ist das richtig
## (die schießen selbst), beim LUFTSCHIFF ist die Deckbesatzung aber die ganze
## Kampfkraft — gemessen wurden also unbewaffnete Zeppeline, und "Luftschiffe
## teilen 0 Schaden aus" war eine Aussage über brave-besetzte Rümpfe.
const KINDS: Dictionary = {
	&"brave":       {"scene": BRAVE_SCENE,       "crew": 0, "wood": 0, "time": 0.0,
		"crew_kind": &"brave"},
	&"krieger":     {"scene": WARRIOR_SCENE,     "crew": 0, "wood": 0, "time": 3.0,
		"crew_kind": &"brave"},
	&"feuerkrieger":{"scene": FIREWARRIOR_SCENE, "crew": 0, "wood": 0, "time": 4.0,
		"crew_kind": &"brave"},
	&"prediger":    {"scene": PREACHER_SCENE,    "crew": 0, "wood": 0, "time": 5.0,
		"crew_kind": &"brave"},
	&"schamanin":   {"scene": SHAMAN_SCENE,      "crew": 0, "wood": 0, "time": 0.0,
		"crew_kind": &"brave"},
	&"katapult":    {"scene": SIEGE_SCENE,       "crew": 3, "wood": 6, "time": 60.0,
		"crew_kind": &"brave"},
	&"feuerramme":  {"scene": FIRERAM_SCENE,     "crew": 2, "wood": 4, "time": 40.0,
		"crew_kind": &"brave"},
	&"luftschiff":  {"scene": AIRSHIP_SCENE,     "crew": 3, "wood": 8, "time": 80.0,
		"crew_kind": &"feuerkrieger"},
}

## Aufstellung = Liste von [art, anzahl] oder [art, anzahl, besatzung].
## Die Paarungen sind so gewählt, dass beide Seiten möglichst GLEICH VIELE BÄ
## kosten — sonst vergleicht man Budgets, nicht Einheiten. Wo die BÄ absichtlich
## auseinandergehen, sagt der Kommentar warum.
const SCENARIOS: Array = [
	# --- Eichmaß: was ist ein Krieger überhaupt wert? ---
	{"name": "krieger_vs_brave", "a": [[&"krieger", 10]], "b": [[&"brave", 10]],
	 "frage": "Wechselkurs Krieger gegen ungeschulte Braves (gleiche BÄ)"},
	{"name": "krieger_vs_brave_1zu3", "a": [[&"krieger", 10]], "b": [[&"brave", 30]],
	 "frage": "Wie viele Braves braucht es für einen Krieger? (3x BÄ auf B)"},

	# --- Das Kern-Dreieck der Armee ---
	{"name": "krieger_vs_feuerkrieger", "a": [[&"krieger", 20]], "b": [[&"feuerkrieger", 20]],
	 "frage": "Nahkampf gegen Fernkampf bei gleichen BÄ"},
	{"name": "krieger_vs_feuerkrieger_zeitgleich", "a": [[&"krieger", 20]], "b": [[&"feuerkrieger", 15]],
	 "frage": "Gleiche AUSBILDUNGSZEIT (60 s): 20x3 s gegen 15x4 s"},
	{"name": "krieger_vs_prediger", "a": [[&"krieger", 20]], "b": [[&"prediger", 20]],
	 "frage": "Bricht Bekehrung den Nahkampf? (gleiche BÄ)"},
	{"name": "feuerkrieger_vs_prediger", "a": [[&"feuerkrieger", 20]], "b": [[&"prediger", 20]],
	 "frage": "Ist der Feuerkrieger wirklich der Prediger-Konter?"},

	# --- Fahrzeuge gegen ihre BÄ in Fußtruppen ---
	{"name": "katapulte_vs_krieger", "a": [[&"katapult", 4, 3]], "b": [[&"krieger", 12]],
	 "frage": "4 Katapulte (12 Mann + 24 Holz) gegen 12 Krieger"},
	{"name": "katapulte_vs_feuerkrieger", "a": [[&"katapult", 4, 3]], "b": [[&"feuerkrieger", 12]],
	 "frage": "Katapult gegen Fernkampf — wer gewinnt das Duell auf Distanz?"},
	{"name": "feuerrammen_vs_krieger", "a": [[&"feuerramme", 6, 2]], "b": [[&"krieger", 12]],
	 "frage": "6 Feuerrammen (12 Mann + 24 Holz) gegen 12 Krieger"},
	{"name": "feuerrammen_vs_katapulte", "a": [[&"feuerramme", 6, 2]], "b": [[&"katapult", 4, 3]],
	 "frage": "Fahrzeug gegen Fahrzeug bei 12 BÄ je Seite"},
	# Luftschiffe: seit 10i mit FEUERKRIEGERN auf dem Deck besetzt. Die
	# Nutzererwartung ist "gewinnt gegen alles ausser Feuerkrieger und Katapult" —
	# genau diese vier Paarungen pruefen das.
	{"name": "luftschiffe_vs_feuerkrieger", "a": [[&"luftschiff", 4, 3]], "b": [[&"feuerkrieger", 12]],
	 "frage": "Deckfeuer gegen Bodenfeuer bei 12 BÄ je Seite"},
	{"name": "luftschiffe_vs_krieger", "a": [[&"luftschiff", 4, 3]], "b": [[&"krieger", 12]],
	 "frage": "Kommt der Nahkampf an bewaffnete Zeppeline heran? (12 BÄ je Seite)"},
	{"name": "luftschiffe_vs_prediger", "a": [[&"luftschiff", 4, 3]], "b": [[&"prediger", 12]],
	 "frage": "Bekehrung gegen Fliegende — Deckbesatzung ist unerreichbar"},
	{"name": "luftschiffe_vs_katapulte", "a": [[&"luftschiff", 4, 3]], "b": [[&"katapult", 4, 3]],
	 "frage": "Abfangschuss gegen Deckfeuer bei 12 BÄ je Seite"},

	# --- Schamanin ---
	# Die Wirkung von 10i Teil 2 ist NUR mit Schamanin auf der Anti-Prediger-Seite
	# messbar: ohne sie bleibt die Prediger-Dominanz unangetastet (so gewollt).
	# 21 gegen 20 BÄ — die Schamanin ist der Aufpreis, den die Regel kostet.
	{"name": "prediger_vs_krieger_mit_schamanin", "a": [[&"prediger", 20]],
	 "b": [[&"krieger", 20], [&"schamanin", 1]],
	 "frage": "Bricht die kaempfende Schamanin die Prediger-Dominanz? (10i Teil 2)"},
	{"name": "schamanin_vs_braves", "a": [[&"schamanin", 1]], "b": [[&"brave", 6]],
	 "frage": "Wie viele Braves kostet die Schamanin im Nahkampf?"},
	{"name": "schamanin_vs_krieger", "a": [[&"schamanin", 1]], "b": [[&"krieger", 3]],
	 "frage": "Schamanin ohne Zauber gegen Krieger"},

	# --- Gemischte Armeen (Plausibilitätsprobe des 10e-Mixes) ---
	{"name": "mix_40_30_30_vs_reine_krieger", "a": [[&"krieger", 12], [&"feuerkrieger", 9], [&"prediger", 9]],
	 "b": [[&"krieger", 30]],
	 "frage": "Der KI-Mix 40/30/30 gegen reine Krieger, 30 BÄ je Seite"},
	{"name": "mix_ohne_prediger_vs_mix", "a": [[&"krieger", 15], [&"feuerkrieger", 15]],
	 "b": [[&"krieger", 12], [&"feuerkrieger", 9], [&"prediger", 9]],
	 "frage": "Zahlt sich der Prediger-Anteil aus? 30 BÄ je Seite"},

	# --- Werte oder Verhalten? Die verteidigende Seite steht und schiesst. ---
	{"name": "krieger_vs_haltende_feuerkrieger", "a": [[&"krieger", 20]], "b": [[&"feuerkrieger", 20]],
	 "hold_b": true,
	 "frage": "Feuerkrieger HALTEN die Stellung — nutzen sie ihre 8 m dann aus?"},
	{"name": "krieger_vs_haltende_prediger", "a": [[&"krieger", 20]], "b": [[&"prediger", 20]],
	 "hold_b": true,
	 "frage": "Prediger halten: gewinnen sie auch ohne selbst anzurennen?"},

	# --- Preis in AUSBILDUNGSZEIT statt in Bevoelkerung ---
	# Braves begrenzt die Huette, Ausbildungszeit begrenzt das Lager. Wer bei
	# gleicher ZEIT gewinnt, ist der eigentliche Preis-Sieger.
	{"name": "prediger_vs_krieger_zeitgleich", "a": [[&"prediger", 20]], "b": [[&"krieger", 33]],
	 "frage": "Gleiche Ausbildungszeit (~100 s): 20 Prediger gegen 33 Krieger"},
	{"name": "prediger_vs_feuerkrieger_zeitgleich", "a": [[&"prediger", 20]], "b": [[&"feuerkrieger", 25]],
	 "frage": "Gleiche Ausbildungszeit (100 s): 20 Prediger gegen 25 Feuerkrieger"},
]


func _initialize() -> void:
	var args: Dictionary = _parse_args()
	var reps: int = int(args.get("reps", DEFAULT_REPS))
	var seconds: float = float(args.get("seconds", DEFAULT_SECONDS))
	var want: String = String(args.get("scenario", ""))
	var island: bool = String(args.get("map", "flach")) == "insel"
	var csv: bool = String(args.get("csv", "0")) == "1"

	print("=== BALANCE-LABOR === %d Wiederholung(en) je Paarung, Abbruch nach %.0f s, Karte %s" % [
		reps, seconds, "Insel" if island else "flach"])
	print("BÄ = Brave-Äquivalente (investierte Bevölkerung). 'zerstört/verloren' ist")
	print("das Verhältnis vernichteter FEINDLICHER zu eigenen verlorenen BÄ:")
	print("  > 1 = die Aufstellung zahlt sich aus, < 1 = sie verliert Substanz.")
	print("")
	var rows: Array = []
	for scenario in SCENARIOS:
		if want != "" and String(scenario["name"]) != want:
			continue
		rows.append(_run_scenario(scenario, reps, seconds, island))
	if rows.is_empty():
		print("Keine Paarung gefunden (scenario=%s). Verfügbar:" % want)
		for scenario in SCENARIOS:
			print("  %s" % scenario["name"])
		quit(0)
		return
	_print_summary(rows)
	if csv:
		_print_csv(rows)
	quit(0)


# --- Ablauf einer Paarung -----------------------------------------------------

func _run_scenario(scenario: Dictionary, reps: int, seconds: float,
		island: bool) -> Dictionary:
	var name: String = String(scenario["name"])
	print("--- %s" % name)
	print("    Frage: %s" % scenario["frage"])
	var cost_a: Dictionary = _composition_cost(scenario["a"])
	var cost_b: Dictionary = _composition_cost(scenario["b"])
	print("    A: %-38s %3d BÄ, %3d Holz, %5.0f s Ausbildung" % [
		_describe(scenario["a"]), cost_a["be"], cost_a["wood"], cost_a["time"]])
	print("    B: %-38s %3d BÄ, %3d Holz, %5.0f s Ausbildung" % [
		_describe(scenario["b"]), cost_b["be"], cost_b["wood"], cost_b["time"]])
	var wins_a: int = 0
	var wins_b: int = 0
	var draws: int = 0
	var sum_left_a: float = 0.0
	var sum_left_b: float = 0.0
	var sum_lost_a: float = 0.0
	var sum_lost_b: float = 0.0
	var sum_conv_a: float = 0.0
	var sum_conv_b: float = 0.0
	var sum_secs: float = 0.0
	var sum_dmg_a: float = 0.0
	var sum_dmg_b: float = 0.0
	var pool_a: float = 1.0
	var pool_b: float = 1.0
	var closest: float = INF
	var left_a_samples: Array[float] = []
	for rep in range(reps):
		var r: Dictionary = _fight(scenario, BASE_SEED + rep * 7919, seconds, island)
		match int(r["winner"]):
			0: wins_a += 1
			1: wins_b += 1
			_: draws += 1
		sum_left_a += float(r["left_a"])
		sum_left_b += float(r["left_b"])
		sum_lost_a += float(r["lost_a"])
		sum_lost_b += float(r["lost_b"])
		sum_conv_a += float(r["conv_a"])
		sum_conv_b += float(r["conv_b"])
		sum_secs += float(r["seconds"])
		closest = minf(closest, float(r["closest"]))
		sum_dmg_a += float(r["dmg_a"])
		sum_dmg_b += float(r["dmg_b"])
		pool_a = maxf(1.0, float(r["pool_a"]))
		pool_b = maxf(1.0, float(r["pool_b"]))
		left_a_samples.append(float(r["left_a"]))
	var n: float = float(reps)
	var lost_a: float = sum_lost_a / n
	var lost_b: float = sum_lost_b / n
	# Vernichtete Feind-BÄ je eigenem verlorenen BÄ. Verliert eine Seite nichts,
	# ist das Verhältnis unendlich — dafür steht INF in der Tabelle.
	var eff_a: float = (lost_b / lost_a) if lost_a > 0.001 else INF
	var eff_b: float = (lost_a / lost_b) if lost_b > 0.001 else INF
	print("    Siege: A %d : %d B   (unentschieden %d)   Ø Dauer %.1f s" % [
		wins_a, wins_b, draws, sum_secs / n])
	print("    Ø übrig: A %.1f/%d BÄ, B %.1f/%d BÄ   |   Ø bekehrt: A→B %.1f, B→A %.1f" % [
		sum_left_a / n, int(cost_a["be"]), sum_left_b / n, int(cost_b["be"]),
		sum_conv_a / n, sum_conv_b / n])
	print("    Ø zerstört/verloren: A %s   B %s   |   Streuung A übrig: %s" % [
		_fmt_ratio(eff_a), _fmt_ratio(eff_b), _fmt_spread(left_a_samples)])
	print("    Ø ausgeteilter Schaden: A %.0f HP (%.0f %% von B), B %.0f HP (%.0f %% von A)" % [
		sum_dmg_a / n, sum_dmg_a / n / pool_b * 100.0,
		sum_dmg_b / n, sum_dmg_b / n / pool_a * 100.0])
	print("    Engster Abstand der Seiten: %.1f m%s" % [closest,
		"   <<< KEIN KONTAKT — Ergebnis sagt nichts über Kampfkraft!"
			if closest > 8.0 else ""])
	print("")
	return {
		"name": name, "reps": reps,
		"be_a": cost_a["be"], "be_b": cost_b["be"],
		"wood_a": cost_a["wood"], "wood_b": cost_b["wood"],
		"time_a": cost_a["time"], "time_b": cost_b["time"],
		"wins_a": wins_a, "wins_b": wins_b, "draws": draws,
		"left_a": sum_left_a / n, "left_b": sum_left_b / n,
		"lost_a": lost_a, "lost_b": lost_b,
		"conv_a": sum_conv_a / n, "conv_b": sum_conv_b / n,
		"eff_a": eff_a, "eff_b": eff_b,
		"secs": sum_secs / n, "closest": closest,
		"dmg_a": sum_dmg_a / n, "dmg_b": sum_dmg_b / n,
		"share_a": sum_dmg_a / n / pool_b * 100.0,
		"share_b": sum_dmg_b / n / pool_a * 100.0,
	}


## Ein einzelnes Gefecht. Rückgabe in BÄ, damit alles vergleichbar bleibt.
func _fight(scenario: Dictionary, rep_seed: int, seconds: float,
		island: bool) -> Dictionary:
	seed(rep_seed)
	var td: TerrainData = TerrainData.new()
	if island:
		td.generate_island(1337)
	else:
		for vz in range(td.size + 1):
			for vx in range(td.size + 1):
				td.set_vertex_height(vx, vz, GROUND_HEIGHT)
	var nav: NavGrid = NavGrid.new(td)
	var tribes: Array[Tribe] = [Tribe.new(0), Tribe.new(1)]
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, tribes)
	var commands: TribeCommands = TribeCommands.new()
	commands.setup(nav, null, um)

	var mid: Vector2i = Vector2i(td.size / 2, td.size / 2)
	@warning_ignore("integer_division")
	var half: int = SEPARATION / 2
	# Ursprungsseite je Einheit festhalten: Bekehrte wechseln tribe_id, für die
	# Verlustrechnung zählt aber, wem sie ANFANGS gehörten.
	var origin: Dictionary = {}
	var be_of: Dictionary = {}
	_spawn_side(um, nav, 0, mid + Vector2i(0, -half), scenario["a"], origin, be_of)
	_spawn_side(um, nav, 1, mid + Vector2i(0, half), scenario["b"], origin, be_of)

	# Beide Seiten greifen an (Angriffsbewegung, wie im Stresstest): so entsteht
	# Kontakt auch dann, wenn eine Seite reine Fernkämpfer ohne Vorwärtsdrang hat.
	var center: Vector3 = nav.cell_to_world(mid)
	for tribe in tribes:
		var squad: Array[Unit] = []
		for u in tribe.units:
			if is_instance_valid(u) and u.state != Unit.State.DEAD \
					and u.state != Unit.State.CREW:
				squad.append(u)
		if not squad.is_empty():
			commands.order_move(squad, center, false, true)

	var spawned: Array[int] = [0, 0]
	for id in origin:
		spawned[int(origin[id])] += int(be_of.get(id, 1))
	# Lebenspunkte-Pool je Seite. Ohne diese Zahl ist "hat nichts getoetet" nicht
	# deutbar: 360 Schaden auf 20 Krieger mit je 120 HP verteilt toetet KEINEN
	# einzigen, ist aber 15 % des feindlichen Pools. Kills allein machen eine
	# Fernkampfeinheit deshalb faelschlich wertlos.
	var hp_pool: Array[int] = [0, 0]
	for u in um.units:
		if is_instance_valid(u) and origin.has(u.get_instance_id()):
			hp_pool[int(origin[u.get_instance_id()])] += u.max_health

	var ticks: int = int(seconds / TICK)
	var decided_at: int = ticks
	# Kleinster Abstand, den die beiden Seiten je erreicht haben. DAS unterscheidet
	# "Pattsituation, weil sie sich nicht wehtun können" von "sie haben sich nie
	# getroffen" — ohne diese Zahl ist ein 0:0 nicht deutbar.
	var closest: float = INF
	for t in range(ticks):
		um.tick_units(TICK)
		um._rebuild_grid()
		um._drain_path_queue()
		um._apply_separation(TICK)
		um._apply_combat_groups(TICK)
		um._apply_idle_regroup(TICK)
		um._tick_projectiles(TICK)
		# Alle 30 Ticks (1 s) prüfen, ob eine Seite ausgelöscht ist.
		if t % 30 == 29:
			closest = minf(closest, _closest_gap(tribes))
			if _fighting_be(tribes[0], be_of) <= 0 or _fighting_be(tribes[1], be_of) <= 0:
				decided_at = t + 1
				break

	var res: Dictionary = _tally(um, origin, be_of, spawned)
	res["seconds"] = float(decided_at) * TICK
	res["closest"] = closest
	# Schaden, den eine Seite AUSGETEILT hat = HP, die der Gegner verloren hat.
	var hp_left: Array[int] = [0, 0]
	for u in um.units:
		if not is_instance_valid(u) or u.state == Unit.State.DEAD:
			continue
		var oid: int = u.get_instance_id()
		if origin.has(oid):
			hp_left[int(origin[oid])] += maxi(0, u.health)
	res["dmg_a"] = maxi(0, hp_pool[1] - hp_left[1])   # A hat B zugefuegt
	res["dmg_b"] = maxi(0, hp_pool[0] - hp_left[0])
	res["pool_a"] = hp_pool[0]
	res["pool_b"] = hp_pool[1]
	var fight_a: int = _fighting_be(tribes[0], be_of)
	var fight_b: int = _fighting_be(tribes[1], be_of)
	if fight_a > 0 and fight_b <= 0:
		res["winner"] = 0
	elif fight_b > 0 and fight_a <= 0:
		res["winner"] = 1
	else:
		res["winner"] = -1   # unentschieden (Zeitablauf oder beide tot)
	commands.free()
	um.free()
	return res


## Kleinster Abstand zwischen einer lebenden Einheit von A und einer von B.
## Grob (O(a*b)), läuft aber nur 1x/s auf kleinen Aufstellungen.
func _closest_gap(tribes: Array[Tribe]) -> float:
	var a: Array[Unit] = []
	for u in tribes[0].units:
		if is_instance_valid(u) and u.state != Unit.State.DEAD:
			a.append(u)
	var best: float = INF
	for u in tribes[1].units:
		if not is_instance_valid(u) or u.state == Unit.State.DEAD:
			continue
		for v in a:
			best = minf(best, Vector2(u.position.x - v.position.x,
				u.position.z - v.position.z).length())
	return best


## BÄ, die aktuell FÜR diesen Stamm kämpfen (inkl. bekehrter Feinde).
func _fighting_be(tribe: Tribe, be_of: Dictionary) -> int:
	var total: int = 0
	for u in tribe.units:
		if is_instance_valid(u) and u.state != Unit.State.DEAD:
			total += int(be_of.get(u.get_instance_id(), 1))
	return total


## Schlussabrechnung je Ursprungsseite, alles in BÄ.
##
## Die Verluste werden als REST gerechnet (aufgestellt − übrig − bekehrt), NICHT
## durch Zählen der Leichen: eine gefallene Einheit verlässt `um.units`, sobald
## ihre Leiche abgelaufen ist. Ein Leichen-Zähler hat die Verluste dadurch
## verschluckt und die Effizienz als INF gemeldet, obwohl BÄ fehlten.
func _tally(um: UnitManager, origin: Dictionary, be_of: Dictionary,
		spawned: Array[int]) -> Dictionary:
	var left: Array[int] = [0, 0]   # lebt und gehört noch der eigenen Seite
	var conv: Array[int] = [0, 0]   # lebt, kämpft jetzt für den Feind
	for u in um.units:
		if not is_instance_valid(u) or u.state == Unit.State.DEAD:
			continue
		var id: int = u.get_instance_id()
		if not origin.has(id):
			continue
		var side: int = int(origin[id])
		var be: int = int(be_of.get(id, 1))
		if u.tribe_id != side:
			conv[side] += be
		else:
			left[side] += be
	return {
		"left_a": left[0], "left_b": left[1],
		"lost_a": maxi(0, spawned[0] - left[0] - conv[0]),
		"lost_b": maxi(0, spawned[1] - left[1] - conv[1]),
		# Eine bekehrte Einheit ist für die eigene Seite genauso verloren wie eine
		# tote — sie schießt jetzt zurück. Für die Effizienz zählt sie mit.
		"conv_a": conv[0], "conv_b": conv[1],
	}


# --- Aufstellen ---------------------------------------------------------------

func _spawn_side(um: UnitManager, nav: NavGrid, tribe_id: int, anchor: Vector2i,
		composition: Array, origin: Dictionary, be_of: Dictionary) -> void:
	var placed: int = 0
	for entry in composition:
		var kind: StringName = entry[0]
		var count: int = int(entry[1])
		var spec: Dictionary = KINDS[kind]
		var crew: int = int(entry[2]) if entry.size() > 2 else int(spec["crew"])
		for i in range(count):
			var cell: Vector2i = _free_cell(nav, anchor, placed)
			placed += 1
			if cell.x < 0:
				continue
			var unit: Unit = um.spawn_unit(spec["scene"] as PackedScene, tribe_id,
				nav.cell_to_world(cell))
			if unit == null:
				continue
			origin[unit.get_instance_id()] = tribe_id
			if crew <= 0:
				be_of[unit.get_instance_id()] = 1
				continue
			# Fahrzeug: der Rumpf selbst kostet keine Bevölkerung, seine
			# Besatzung schon. Die Braves zählen einzeln, der Rumpf mit 0 —
			# sonst würde die Besatzung doppelt berechnet.
			be_of[unit.get_instance_id()] = 0
			var crew_scene: PackedScene = KINDS[_crew_kind_of(kind)]["scene"] as PackedScene
			for c in range(crew):
				var crew_cell: Vector2i = _free_cell(nav, anchor, placed)
				placed += 1
				if crew_cell.x < 0:
					continue
				var member: Unit = um.spawn_unit(crew_scene, tribe_id,
					nav.cell_to_world(crew_cell))
				if member == null:
					continue
				origin[member.get_instance_id()] = tribe_id
				be_of[member.get_instance_id()] = 1
				member.order_crew(unit)


## `skip`-te begehbare Zelle in Ringen um `center` (dicht gepackte Aufstellung).
func _free_cell(nav: NavGrid, center: Vector2i, skip: int) -> Vector2i:
	var seen: int = 0
	for radius in range(0, 30):
		for cell in AIController.ring_cells(center, radius):
			if not nav.is_cell_walkable(cell):
				continue
			if seen >= skip:
				return cell
			seen += 1
	return Vector2i(-1, -1)


# --- Kosten & Ausgabe ---------------------------------------------------------

## Besatzungsart eines Fahrzeugs (Standard: Braves).
func _crew_kind_of(kind: StringName) -> StringName:
	var spec: Dictionary = KINDS[kind]
	return spec.get("crew_kind", &"brave") as StringName


func _composition_cost(composition: Array) -> Dictionary:
	var be: int = 0
	var wood: int = 0
	var time: float = 0.0
	for entry in composition:
		var spec: Dictionary = KINDS[entry[0]]
		var count: int = int(entry[1])
		var crew: int = int(entry[2]) if entry.size() > 2 else int(spec["crew"])
		be += count * (crew if crew > 0 else 1)
		wood += count * int(spec["wood"])
		time += float(count) * float(spec["time"])
		# Die AUSBILDUNGSZEIT der Besatzung gehört dazu (10i Teil 5): drei
		# Feuerkrieger auf dem Deck sind 3 BÄ UND 12 s Ausbildung, nicht nur der
		# Rumpf. Ohne das waren Fahrzeuge in der Zeit-Spalte zu billig.
		if crew > 0:
			var crew_spec: Dictionary = KINDS[_crew_kind_of(entry[0])]
			time += float(count * crew) * float(crew_spec["time"])
	return {"be": be, "wood": wood, "time": time}


func _describe(composition: Array) -> String:
	var parts: Array[String] = []
	for entry in composition:
		var spec: Dictionary = KINDS[entry[0]]
		var crew: int = int(entry[2]) if entry.size() > 2 else int(spec["crew"])
		if crew > 0:
			parts.append("%dx %s(%d Mann)" % [int(entry[1]), entry[0], crew])
		else:
			parts.append("%dx %s" % [int(entry[1]), entry[0]])
	return ", ".join(parts)


func _fmt_ratio(v: float) -> String:
	if v == INF:
		return "  INF"
	return "%5.2f" % v


## Min..Max der Wiederholungen — zeigt, wie verlässlich die Aussage ist.
func _fmt_spread(samples: Array[float]) -> String:
	if samples.is_empty():
		return "-"
	var lo: float = samples[0]
	var hi: float = samples[0]
	for v in samples:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return "%.0f..%.0f BÄ" % [lo, hi]


func _print_summary(rows: Array) -> void:
	print("=== ÜBERSICHT ===")
	print("%-38s %8s %9s %7s %6s %9s %6s" % [
		"Paarung", "Siege", "BÄ übrig", "zer/ver", "Dauer", "bekehrt", "Schaden%"])
	for r in rows:
		print("%-38s %3d:%-3d %4.1f:%-4.1f %5s %5.0fs %4.1f/%-4.1f %5.0f%%%s" % [
			r["name"], r["wins_a"], r["wins_b"], r["left_a"], r["left_b"],
			_fmt_ratio(r["eff_a"]), r["secs"], r["conv_a"], r["conv_b"],
			r["share_a"], " !" if r["closest"] > 8.0 else ""])
	print("")
	print("Lesehilfe: 'Siege' A:B über alle Wiederholungen, 'zer/ver' ist die")
	print("Effizienz der Seite A (vernichtete Feind-BÄ je eigenem verlorenen BÄ).")
	print("Unentschieden = nach Zeitablauf lebten beide Seiten noch.")
	print("'Schaden%' ist der Anteil des feindlichen HP-Pools, den A ausgeteilt hat.")
	print("Ein '!' heisst: die Seiten kamen nie in Waffenreichweite — dann ist die")
	print("Zeile KEINE Aussage ueber Kampfkraft, sondern ueber Verhalten.")


func _print_csv(rows: Array) -> void:
	print("")
	print("=== CSV ===")
	print("name,reps,be_a,be_b,wood_a,wood_b,time_a,time_b,wins_a,wins_b,draws,left_a,left_b,lost_a,lost_b,conv_a,conv_b,eff_a,secs,closest")
	for r in rows:
		print("%s,%d,%d,%d,%d,%d,%.0f,%.0f,%d,%d,%d,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.3f,%.1f,%.1f,%.0f,%.0f,%.1f" % [
			r["name"], r["reps"], r["be_a"], r["be_b"], r["wood_a"], r["wood_b"],
			r["time_a"], r["time_b"], r["wins_a"], r["wins_b"], r["draws"],
			r["left_a"], r["left_b"], r["lost_a"], r["lost_b"],
			r["conv_a"], r["conv_b"],
			999.0 if r["eff_a"] == INF else r["eff_a"], r["secs"], r["closest"],
			r["dmg_a"], r["dmg_b"], r["share_a"]])


func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		var parts: PackedStringArray = String(arg).split("=", true, 1)
		if parts.size() == 2:
			out[parts[0]] = parts[1]
	return out
