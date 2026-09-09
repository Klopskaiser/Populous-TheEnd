extends SceneTree

## TIME TO KILL — Nachschlagetabelle, aus dem LEBENDEN Code gerechnet.
##
## Kein Test (keine Sollwerte, faellt nie durch) und kein Benchmark: reine
## Auskunft. Aufruf:
##   godot --headless -s res://tests/diag_ttk.gd
##
## Warum ein Skript und keine Tabelle in der Doku: die Werte haengen an
## Balance-Konstanten UND an gerundeten Schlagwerten (Unit.melee_damage rundet
## base * melee_strength je Schlagart einzeln, 3 x 2,5 = 7,5 -> 8). Handgerechnet
## driftet so eine Tabelle bei der ersten Balance-Aenderung.
##
## GRENZEN — beim Deuten mitdenken:
##  * Nahkampf ist ein ERWARTUNGSWERT ueber die Schlagarten, kein Wuerfelergebnis.
##  * Anmarsch, Zielwahl, Kampfgruppen-Ring (max. 3 Angreifer), Ausweichen,
##    Panik und Regeneration sind NICHT drin — das ist reine Waffenwirkung.
##  * Flaechenschaden (Feuerkrieger-Splash, Katapult, Golem, Ramme) ist hier nur
##    als Schaden am HAUPTZIEL gerechnet; in der Masse ist die Wirkung ein
##    Vielfaches davon (s. die Dichte-Notiz in CLAUDE.md).
##  * Fahrzeuge sind nicht direkt angreifbar (bekaempft wird die Crew), stehen
##    hier also nur als ANGREIFER in der Tabelle, nicht als Ziel.

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const TECHNICIAN_SCENE: PackedScene = preload("res://scenes/units/technician.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")
const PREACHER_SCENE: PackedScene = preload("res://scenes/units/preacher.tscn")
const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")
const GOLEM_SCENE: PackedScene = preload("res://scenes/units/golem.tscn")

## Reihenfolge der Tabellen.
const MELEE: Array = [
	[&"Brave", BRAVE_SCENE],
	[&"Techniker", TECHNICIAN_SCENE],
	[&"Krieger", WARRIOR_SCENE],
	[&"Feuerkrieger", FIREWARRIOR_SCENE],
	[&"Prediger", PREACHER_SCENE],
	[&"Schamanin", SHAMAN_SCENE],
]


func _initialize() -> void:
	var targets: Array = []
	for entry in MELEE:
		var probe: Unit = (entry[1] as PackedScene).instantiate() as Unit
		targets.append([entry[0], probe.max_health])
		probe.free()
	var golem: Unit = GOLEM_SCENE.instantiate() as Unit
	targets.append([&"Golem", golem.max_health])
	golem.free()

	print("")
	print("=== SCHADEN JE ANGREIFER (aus Unit.melee_damage / Balance) ===")
	print("Einheit        HP    Schlag/Tritt/Schubs   Chancen (P/T/S)      "
		+ "E[Schaden]  Takt    DPS")
	var attackers: Array = []
	for entry in MELEE:
		var u: Unit = (entry[1] as PackedScene).instantiate() as Unit
		var punch: int = u.melee_damage(&"punch")
		var kick: int = u.melee_damage(&"kick")
		var shove: int = u.melee_damage(&"shove")
		var p_shove: float = u._shove_chance()
		var p_kick: float = u._kick_chance()
		var p_punch: float = maxf(0.0, 1.0 - p_shove - p_kick)
		var expected: float = p_punch * float(punch) + p_kick * float(kick) \
			+ p_shove * float(shove)
		var dps: float = expected / Unit.ATTACK_COOLDOWN
		print("%-13s %4d   %2d / %2d / %2d          %.2f / %.2f / %.2f     "
			% [entry[0], u.max_health, punch, kick, shove, p_punch, p_kick, p_shove]
			+ "%6.2f   %.1fs  %5.2f" % [expected, Unit.ATTACK_COOLDOWN, dps])
		attackers.append([entry[0], dps])
		u.free()

	# Fernkampf und Sonderwaffen, jeweils Schaden am HAUPTZIEL.
	var fw_dps: float = float(Unit.FIREBALL_DAMAGE) / Balance.FIREWARRIOR_FIRE_COOLDOWN
	print("%-13s  —     Feuerball %d          Reichweite %.0f m          "
		% ["Feuerkr. (F)", Unit.FIREBALL_DAMAGE, Balance.FIREWARRIOR_FIRE_RANGE]
		+ "%6.2f   %.1fs  %5.2f" % [float(Unit.FIREBALL_DAMAGE),
			Balance.FIREWARRIOR_FIRE_COOLDOWN, fw_dps])
	var golem_dps: float = float(Balance.GOLEM_DAMAGE) / Balance.GOLEM_STRIKE_COOLDOWN
	print("%-13s %4d   Flaechenschlag %d     ganze Hitbox + Feld davor  "
		% ["Golem", Balance.GOLEM_HP, Balance.GOLEM_DAMAGE]
		+ "%6.2f   %.1fs  %5.2f" % [float(Balance.GOLEM_DAMAGE),
			Balance.GOLEM_STRIKE_COOLDOWN, golem_dps])
	attackers.append(["Feuerkr. (F)", fw_dps])
	attackers.append(["Golem", golem_dps])

	# Fahrzeuge: Crew-abhaengiger Takt, mit und ohne Technikerbesatzung.
	print("")
	print("=== FAHRZEUGE (Schaden am Hauptziel; Takt haengt an der Crew) ===")
	_vehicle_line("Katapult 2 Mann", Balance.SIEGE_SHOT_SHOCK_DAMAGE,
		SiegeEngine.fire_cooldown_for_crew(2), attackers)
	_vehicle_line("Katapult 6 Mann", Balance.SIEGE_SHOT_SHOCK_DAMAGE,
		SiegeEngine.fire_cooldown_for_crew(6), attackers)
	_vehicle_line("Katapult 6 Techn.", Balance.SIEGE_SHOT_SHOCK_DAMAGE,
		SiegeEngine.fire_cooldown_for_crew(6) / (1.0
			+ Balance.TECHNICIAN_SIEGE_FIRERATE_BASE
			+ Balance.TECHNICIAN_FIRERATE_PER_EXTRA * 5.0), attackers)
	# Die Ramme setzt einen BRAND: 60 HP ueber 4 s, unabhaengig vom Nachladen.
	# Der Takt sagt daher nur, wie oft sie einen NEUEN Gegner anzuenden kann.
	# Der Brand selbst ist der Schaden: solange die Ramme das Ziel angezuendet
	# haelt, laufen BURN_TOTAL_DAMAGE/BURN_DURATION HP/s. Ein Nachzuenden
	# ERNEUERT den Brand (kein Stapeln), der Takt begrenzt also nur, wie schnell
	# sie einen NEUEN Gegner erwischt.
	attackers.append(["Feuerramme (Brand)",
		float(Balance.BURN_TOTAL_DAMAGE) / Balance.BURN_DURATION])
	print("Feuerramme:   Brand %d HP ueber %.1f s (%.1f HP/s), Nachladen "
		% [Balance.BURN_TOTAL_DAMAGE, Balance.BURN_DURATION,
			float(Balance.BURN_TOTAL_DAMAGE) / Balance.BURN_DURATION]
		+ "%.2f s (1 Mann) / %.2f s (4 Mann) / %.2f s (4 Techniker)"
		% [FireRam.flame_cooldown_for_crew(1), FireRam.flame_cooldown_for_crew(4),
			FireRam.flame_cooldown_for_crew(4) / (1.0
				+ Balance.TECHNICIAN_FIRERAM_FIRERATE_BASE
				+ Balance.TECHNICIAN_FIRERATE_PER_EXTRA * 3.0)])

	print("")
	print("=== TIME TO KILL in Sekunden (Zeile schlaegt Spalte, 1 gegen 1) ===")
	var header: String = "%-19s" % "Angreifer \\ Ziel"
	for t in targets:
		header += "%13s" % t[0]
	print(header)
	for a in attackers:
		var line: String = "%-19s" % a[0]
		for t in targets:
			var dps: float = a[1]
			line += "%13s" % ("   —" if dps <= 0.0
				else "%.1f" % (float(t[1]) / dps))
		line += ""
		print(line)
	print("")
	print("HP der Ziele: " + ", ".join(_target_labels(targets)))
	print("")
	quit()


func _vehicle_line(label: String, damage: int, cooldown: float,
		attackers: Array) -> void:
	var dps: float = float(damage) / cooldown
	print("%-18s Treffer %2d im %.1f-m-Radius, alle %.2f s  ->  %5.2f DPS"
		% [label, damage, Balance.SIEGE_SHOT_SHOCK_RADIUS, cooldown, dps])
	attackers.append([label, dps])


func _target_labels(targets: Array) -> Array[String]:
	var out: Array[String] = []
	for t in targets:
		out.append("%s %d" % [t[0], t[1]])
	return out
