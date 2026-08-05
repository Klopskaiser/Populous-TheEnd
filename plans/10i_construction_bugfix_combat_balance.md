# Phase 10i — Bugfix steckengebliebene Baustellen, Prediger-Störung, Feuerkrieger-Flächenschaden

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).
> **Abhängigkeit:** [Phase 10h](10h_wood_logistics_expansion.md) ist abgeschlossen.
> **Folgephase:** [10j](10j_disc_world.md) baut die Weltgrenze um, die diese Phase
> unangetastet lässt — 10i zuerst.

## Ziel

Zwei **Bugs** (einer spielbrechend) und drei Balance-Mechaniken aus dem Original
Populous. Die Bugs kommen zuerst.

Die Balance-Änderungen betreffen genau die zwei Einheiten, die das
**Balance-Labor** (`tests/balance_lab.gd`, Phase 10e) als Ausreißer entlarvt hat:

- **Prediger sind ein Win-Button.** Bei gleicher Ausbildungszeit bekehren 20
  Prediger **33 von 33 Kriegern** verlustfrei und gewinnen gegen 25 Feuerkrieger
  5:0 — auch wenn sie nur stehen. Es fehlt ein Gegenmittel. Im Original bricht die
  **kämpfende feindliche Schamanin** die Predigt.
  *(Das widerlegt die Annahme aus 10e, Feuerkrieger seien der Prediger-Konter.)*
- **Feuerkriegern fehlt Wirkung, nicht Schaden.** Sie teilen 36 % des Kriegerpools
  aus und töten fast nichts: 870 HP auf 20 Krieger à 120 HP reißt keinen einzigen
  um. Haltend ändert sich nichts (865 statt 870 HP) — es ist kein
  Positionierungs-, sondern ein **Konzentrationsproblem**. Flächenschaden behebt
  genau das.

## Nutzer-Festlegungen (2026-08-04)

| Thema | Entscheidung |
|---|---|
| Flächenschaden Friendly Fire | **Nur Feinde** (Muster Zauber-Feuerball) |
| Flächenwirkung | **Nur Schaden**, kein Rückstoß/Anheben auf Umstehende |
| Anhebe-Kurve | **bis 3-fach** bei fast totem Ziel (4 % → 12 %) |
| „Schamanin kämpft" | `state == ATTACK` **oder** sie hat Angreifer |
| Radius Prediger-Störung | **6 m** um die Schamanin, in `Balance` |
| Flächenradius | **2 m**, in `Balance` (Nutzer-Schätzwert, bewusst tunbar) |

## Stand 2026-08-05 — am Code nachgeprüft

Phasen 10f–10h haben das Bauumfeld stark umgebaut. Nachgeprüft, was davon diesen
Plan berührt:

**Schon da und hier nutzbar:**
- **`Building.approach_cell_for(nav, cell, footprint, orientation)`**
  (`building.gd:302-320`) ist mit 10g entstanden, ausdrücklich als *„one truth
  with the AI's plot check"* — damit kann auch ein Bauplatz **ohne** Gebäude
  gefragt werden. Genau das braucht **F4**, das dadurch zum Einzeiler wird.
- Die Holzpipeline wurde überarbeitet (Aufnehmen/Halten, Ablege-Countdown,
  Ablieferung nach Bedarf statt nach Nähe), `_absorb_piles` setzt jetzt
  `wood_stalled = false`. Das **dämpft** das Symptom, behebt die Ursache nicht.

**Weiterhin offen — der Kernbefund steht:**
- `edge_spawn_position()` (`:354-361`) delegiert jetzt an `approach_cell_for`,
  rechnet aber **immer noch bei jedem Aufruf neu** und liefert die **erste**
  begehbare Zelle in Rasterordnung (verschachtelte x/z-Schleifen, `:313-319`),
  nicht die nächste zum Eingang. **Der Anker springt weiter.**
- `delivery_point()` (`:369-370`), `_absorb_piles` (`:1604`), `wood_incoming`
  (`:1551`) und `approach_island` (`:380-387`) hängen unverändert daran.
- `can_place_at` prüft **keinen** Anlaufpunkt → F4 offen.
- `_anim_base()` in `brave.gd` (`:1784-1799`) hat **keinen** `State.TRAIN`-Zweig
  → F8 offen.
- Nicht vorhanden: `PREACHER_SHAMAN_DISTURB_RANGE`, `FW_FIREBALL_BLAST_*`,
  `lift_chance_for_health`, `health_fraction`, `FLATTEN_CELL_TIMEOUT`,
  `CONSTRUCTION_NO_START_TIMEOUT`, `FOUNDATION_RIM_BLEND`, `crew_kind` im Labor.

> **Zeilenangaben:** die oben nachgeprüften Stellen sind aktuell. Die Zeilen in der
> **Ursachenkette unten** stammen aus der Untersuchung von *vor* 10f–10h und sind
> teils verschoben — `building.gd` hat seither drei Phasen abbekommen. Sie benennen
> die richtigen **Funktionen**, nicht zwingend die richtigen Zeilen: beim Umsetzen
> die Datei neu lesen statt den Nummern zu folgen.

---

# Teil 1 — Bugfix: Baustellen, an denen nichts passiert

## Der Nutzerreport

**Symptom 1:** Eine Hütte relativ nah an einer anderen Hütte. Bauarbeiter machen
nichts. Beim **Abriss** kommt ein **riesiger Stapel Holz** zurück (viel mehr als
die Baukosten). Eine angrenzende zweite Hütte lässt sich ebenfalls nicht bauen,
auch manuelle Arbeiterzuweisung schlägt fehl. Erst nach Entfernen der ersten
Hütte baut die zweite. Danach ließ sich die abgerissene Hütte **auf demselben
Feld** neu setzen und wurde normal gebaut.

**Symptom 2:** Ein Feuertempel (8×8) wird platziert, genug Platz. Drei Arbeiter
**stecken im Eingangsbereich fest**, kein Baufortschritt. Planieren scheint
fertig; die Braves können den Grundriss nicht verlassen.

## Untersuchungsergebnis

Beide Symptome haben **eine gemeinsame Wurzel**: `delivery_point()` ist nicht
persistiert und **springt**.

`delivery_point()` → `edge_spawn_position()` → `approach_cell_for()` rechnet bei
**jedem Aufruf** neu: Eingangszelle, wenn begehbar; sonst Ringsuche
`grow 1..APPROACH_SEARCH_RINGS` und dort die **erste** begehbare Zelle in
Rasterordnung (NW-lastig, *nicht* die nächste zum Eingang); sonst `(-1,-1)` und
damit Fallback auf das **unbegehbare** `entrance_world()`.

Dieser Punkt ist der gemeinsame Anker von fünf Dingen: `_absorb_piles()`
(Holzbuchung), `wood_incoming()`, das Lieferziel der Braves, `_refund_wood()` und
**`approach_island()`**.

**Die Kette (belegt bis auf Schritt 4, der zwingend folgt):**

1. Steht ein Nachbargebäude so, dass die Eingangszelle in dessen Grundriss liegt
   (nav-solid über `NavGrid._building_cells`), fällt `delivery_point()` in die
   Ringsuche und **springt**, sobald sich in der Nachbarschaft irgendeine
   Begehbarkeit ändert — und das passiert dauernd (`_flush_deformation` →
   `update_region`; jede Planierkante).
2. Bei einem 4×4-Grundriss liegen gegenüberliegende Ring-1-Ecken ~7 m
   auseinander, beim 8×8 ~14 m — **weit mehr als `ABSORB_RADIUS = 5.0`**.
3. Damit liegt abgelegtes Holz außerhalb des Absorptionsradius: `_absorb_piles`
   bucht **nichts**, `wood_delivered` bleibt 0, `wood_incoming()` zählt dieselben
   Stapel auch nicht → **`wants_more_wood()` bleibt dauerhaft true**.
4. `_choose_job_task` schickt daraufhin alle freien Hände endlos ins Holzholen →
   **der Stapel wächst unbegrenzt**. Das ist der „riesige Stapel Holz", **nicht**
   die Erstattung.
5. `progress_cap() = wood_delivered / wood_cost` bleibt 0 → `add_build_progress`
   ist **wirkungslos**. Die Arbeiter stehen formal in `interact_range()` (beim
   8×8: 5,6 m — der Eingangsbereich zählt schon als „angekommen") und hämmern ins
   Leere. **Das ist Symptom 2 wörtlich.**
6. Läuft die Ringsuche ganz durch (Nachbargrundriss + Planierkante über alle
   Ringe), landet der Fallback auf unbegehbarem Terrain → `approach_island() == -1`
   → `BuildingManager._recruit_workers` überspringt die Baustelle **und**
   `TribeCommands.order_build` liefert 0. **Das ist „manuelle Zuweisung schlug
   fehl".**
7. Der Wert ist gegen `nav_grid.change_version` gecacht. Erst der **Abriss des
   Nachbarn** gibt `_building_cells` frei (nur `destroy()` tut das) → Version
   steigt → Cache fällt → die zweite Hütte baut. **Das ist „erst nach Entfernen
   der ersten Hütte ging die zweite"**, und weil die Nachbarschaft danach anders
   war, ging derselbe Bauplatz beim zweiten Versuch problemlos.

**Zwei verstärkende Nebenursachen (belegt):**

- **Die Eingangszelle wandert ungeprüft in die Planierliste** (nur `in_bounds`).
  Liegt sie im Grundriss des Nachbarn, ist sie nie planierbar →
  `_flatten_remaining` wird nie leer → `foundation_done` bleibt false →
  `add_build_progress` ist gegated → **niemals Baufortschritt**. Dazu verformen die
  Arbeiter das **Fundament des Nachbarn** (`work_flatten` prüft kein Eigentum).
  Und es gibt **keinen Timeout** für nicht abschließbares Planieren.
- **Der Planier-Ringgraben** (rechnerisch belastbar, vom Code selbst kommentiert):
  `can_place_at` erlaubt `MAX_LEVEL_DIFF = 3.0` über den Grundriss,
  `flatten_target` ist der **Mittelwert**. Am Rand weicht das Gelände also bis
  ~1,5 m ab, und `TerrainData.is_walkable` verwirft ab `MAX_SLOPE = 1.5`. Um einen
  legal gesetzten 8×8-Grundriss kann so ein **unbegehbarer Ring** entstehen:
  innen solid, außen Steilkante — die Braves sitzen in einem selbst erzeugten
  Graben. `worker_can_reach` bleibt dabei absichtlich permissiv, befreit sie also
  nicht; nach 6 Seek-Fehlschlägen wirft der Brave sein Holz **an der aktuellen
  Position** ab und füttert damit denselben Stapel.

**Ausgeschlossen** (geprüft, nicht die Ursache): `wood_delivered > wood_cost`
(einzige Schreibstelle ist mit `need` gedeckelt), Erstattung > Baukosten,
Doppelbuchung Stapel/`wood_delivered` (`_drain` entnimmt physisch),
Höhen-Endlosschleife beim Planieren (`move_toward` konvergiert), Pfadfehlschlag am
soliden Startpunkt (`find_path` snappt), Arbeiter-Slot-Leak in `Building.workers`.

**Warum der Bauverfall aus 10d nicht rettet:** die Signatur
`Vector3(build_progress, wood_delivered, offene Flatten-Zellen)` wird von **jeder**
Teilbuchung und **jeder** fertigen Planierzelle auf 0 zurückgesetzt — genau so
getestet (`test_construction_decay.gd:108`). Fällt der springende Anker
gelegentlich (< 120 s) wieder in die Nähe der Stapel, lebt die Baustelle
**unbegrenzt** ohne je zu bauen.

## Die Fixes

**F1 — `delivery_point()` persistieren (der Kernfix).**
Den Punkt **einmal** in `init_construction()` bzw. bei der Platzierung bestimmen
und in einem Feld halten (`_delivery_point: Vector3`). Neu berechnet wird er
**nur**, wenn er unbegehbar geworden ist (`nav_grid.change_version`-getriggert),
nicht bei jedem Aufruf. Damit hören Holzbuchung, `wood_incoming`, Lieferziel,
Erstattung und `approach_island` auf, gegeneinander zu laufen.

**F2 — Ringsuche nimmt die NÄCHSTE Zelle, nicht die erste im Raster.**
In `approach_cell_for()` je Ring den Kandidaten mit der kleinsten Distanz zur
Eingangszelle wählen statt den ersten Schleifentreffer. Allein das macht den Punkt
stabil und plausibel. **Da die Funktion `static` ist und die KI sie mitbenutzt,
profitiert die Bauplatzprüfung automatisch mit.**

**F3 — Die Eingangs-Planierzelle wird optional.**
Sie ist rein kosmetisch („so the doorway sits flush"). Sie kommt nur in
`_flatten_remaining`, wenn sie begehbar ist **und nicht** im Grundriss eines
**fremden** Gebäudes liegt (`nav_grid.is_cell_blocked_by_building`). Zusätzlich:
eine Planierzelle, die `FLATTEN_CELL_TIMEOUT` lang von niemandem erreicht wurde,
fällt aus der Liste — eine einzige unerreichbare Zelle darf keine Baustelle
dauerhaft blockieren.

**F4 — Anlaufpunkt schon bei der Platzierung prüfen.**
`TribeCommands.can_place_at` prüft Land, Gebäudekollision, Bäume und Höhenspanne —
aber **nicht**, ob das Gebäude hinterher einen erreichbaren Anlaufpunkt hat.
**Das ist jetzt ein Einzeiler:** `Building.approach_cell_for(nav_grid, cell,
footprint, orientation)` (`building.gd:302`) ist mit 10g genau dafür extrahiert
worden („so a plot without a building can be asked too") — `>= 0` verlangen.
Verhindert die Konstellation aus Symptom 1 **an der Wurzel**, ohne dichtes Bauen
generell zu verbieten.

> **Achtung Reihenfolge:** `approach_cell_for` fragt `nav.is_cell_walkable`, und
> zum Prüfzeitpunkt ist der eigene Grundriss noch **nicht** solid. Eine Zelle im
> eigenen Grundriss darf nicht als Anlaufpunkt durchgehen — die Ringsuche startet
> bei `grow 1`, und die Eingangszelle liegt außerhalb des Grundrisses, ist also
> unkritisch. Im Test festnageln.

> Bewusst **kein** pauschaler Mindestabstand für den Spieler (die KI hat einen,
> `AI_PLOT_SPACING = 2`). Der wäre einfacher, würde aber auch alle
> *funktionierenden* engen Dörfer verbieten. F4 verbietet nur das, was tatsächlich
> kaputt ist. Falls es im Spieltest weiter klemmt, ist der Mindestabstand die
> Rückfallebene.

**F5 — Fluchtweg für eingeschlossene Braves.**
Ein Brave, dessen Seek `SEEK_FAIL_QUIT_STREAK`-mal scheitert **und** der auf einer
unbegehbaren Zelle steht, wird auf `nav_grid.nearest_walkable_cell` gesetzt
(Muster: `_end_roll`) statt nur den Job abzugeben. Das ist das Sicherheitsnetz für
Symptom 2, unabhängig davon, wie der Graben entstand. Dazu
`Building.workers`/`has_worker_room` defensiv mit `is_instance_valid` filtern
(`wood_incoming` macht das schon) — kein belegter Leak, aber eine offene
Härtungslücke.

**F6 — ~~Planierkante abflachen (gegen den Ringgraben)~~ → nach Messung VERWORFEN
(2026-08-05).**
Geplant war: der Ring **eine Zelle außerhalb** des Grundrisses wird auf einen
**gemittelten** Wert zwischen `flatten_target` und Originalhöhe gezogen, womit
sich die Kantenstufe halbiert (~1,5 m → ~0,75 m) und unter `MAX_SLOPE` bleibt.

**Umgesetzt, gemessen, wieder entfernt.** Es kostete die KI ein Drittel bis die
Hälfte ihrer Bevölkerung — `benchmark_earlygame` bergpass, pop@300 s: **242/244**
ohne die Phase, **158/159** mit allen Fixes inklusive F6, und die Bisektion
isoliert F6 als Alleinursache (**F6 allein 134**, **F3 allein 241**). Erklärung:
der Blend entfernt die Stufe am Grundriss und öffnet dafür eine **neue** gegen
das unberührte Gelände eine Zelle weiter außen. Eine Klemmung gegen
`TerrainData.MAX_SLOPE` (nur blenden, soweit keine steilere Kante entsteht)
brachte trotzdem nur 162 — also Implementierung entfernt statt einen
Halb-Effekt mit vollem Risiko zu behalten.

Der Ringgraben, gegen den F6 gedacht war, ist über **F5** (Fluchtweg für
eingeschlossene Braves), **F3** (Zell-Timeout) und **F4** (Anlauftor schon bei
der Platzierung) abgedeckt. Diese Plandatei hatte F6 selbst als größtes
Regressionsrisiko geführt und die Messung zur Pflicht gemacht — genau dafür war
sie da.

**F7 — Bauverfall härten.**
Zusätzlich zur Signatur ein **absolutes** Limit: eine Baustelle mit
`build_progress == 0`, die `CONSTRUCTION_NO_START_TIMEOUT` lang nicht in die
Bauphase gekommen ist, verfällt — unabhängig davon, wie oft Teilbuchungen den
Signatur-Timer zurückgesetzt haben.

## F8 — Zweiter, unabhängiger Bug: Braves laufen in der Idle-Animation zum Lager

**Symptom:** Rechtsklick auf ein Trainingsgebäude → der Brave läuft hin, zeigt
dabei aber die **Idle**-Animation.

**Ursache eingegrenzt:** `State.TRAIN` fehlt in **beiden** `_anim_base()`-
Implementierungen — weder `Unit._anim_base()` (behandelt
MOVE/PANIC/ATTACK/CAST/SIT/ROLL/THROWN/DEAD/CREW/GARRISON) noch
`Brave._anim_base()` (`brave.gd:1784-1799`, behandelt BUILD/GATHER/FORESTER) hat
einen Zweig dafür. Der Zustand fällt in den `_:`-Default und liefert `&"idle"`.
Bewegt wird er trotzdem, denn `Brave._tick_train` läuft per
`_seek(slot, TRAIN_SLOT_RANGE, delta)` zum Warteslot.

**Fix** in `Brave._anim_base()` (die Felder sind Brave-Felder, nur Braves trainieren):

```gdscript
		State.TRAIN:
			# Walking to the camp's queue slot; only the WAIT in the slot stands
			# still. train_reached_slot is exactly what _tick_train computes each
			# tick, so a reassigned slot makes the brave walk again on its own.
			return &"idle" if train_reached_slot else &"walk"
```

**Vollständigkeitsprüfung der übrigen Zustände**, damit der Fix nicht symptomatisch
bleibt: von den 16 `State`-Werten fallen nur `IDLE`, `TRAIN` und `RAID` in den
Default. `IDLE` ist korrekt. `RAID` ist **harmlos** — ein Raider wird vom Gebäude
aus der Welt entfernt, bevor `_set_state(State.RAID)` läuft, und ist damit nicht
gerendert. **`TRAIN` ist der einzige echte Defekt dieser Klasse.**

## Neue Konstanten (Teil 1)

```gdscript
# --- Baustellen-Robustheit (Phase 10i) ---
## Eine Planierzelle, die so lange von keinem Arbeiter erreicht wurde, fällt aus
## der Pflichtliste — eine einzige unerreichbare Zelle darf keine Baustelle
## dauerhaft blockieren.
const FLATTEN_CELL_TIMEOUT: float = 25.0
## Absolutes Limit für eine Baustelle, die NIE in die Bauphase kommt
## (build_progress == 0). Fängt den Fall, in dem Teilbuchungen den
## Signatur-Timer des Bauverfalls immer wieder zurückstellen.
const CONSTRUCTION_NO_START_TIMEOUT: float = 180.0
## Anteil, auf den die Planierkante EINE Zelle außerhalb des Grundrisses gezogen
## wird (0 = gar nicht, 1 = voll auf flatten_target). 0.5 halbiert die Stufe und
## hält sie unter TerrainData.MAX_SLOPE.
const FOUNDATION_RIM_BLEND: float = 0.5
```

---

# Teil 2 — Die kämpfende Schamanin stört die Predigt

**Regel:** Kämpft eine **feindliche** Schamanin innerhalb
`PREACHER_SHAMAN_DISTURB_RANGE` (6 m) **um den Prediger**, kann dieser nicht
bekehren — laufende Bekehrungen brechen ab, neue beginnen nicht. Das gilt für
**alle** Prediger im Radius, nicht nur für den, den sie angreift (genau der Fall
aus der Vorgabe: sie greift Prediger A an, Prediger B kann trotzdem nicht
weiterpredigen).

**Zwei Einhängepunkte reichen für alles.** Beide liegen auf dem **Opfer**
(`scripts/units/unit.gd`) und haben den Prediger zur Hand — damit sind Boden-,
Wachturm- und Deck-Prediger erfasst, weil alle drei Kanalquellen ausschließlich
hier einlaufen:

1. **`begin_conversion(preacher, …)`** — *verhindern*: früher `return false` neben
   den bestehenden Guards.
2. **`_tick_sit(delta)`** — *abbrechen*: `_stand_up(false)`, analog zum vorhandenen
   „Prediger im Duell"-Zweig. `_stand_up` nullt `conversion_progress` — der
   Fortschritt ist also verloren, wie gewollt.

```gdscript
## True when an ENEMY shaman is fighting within PREACHER_SHAMAN_DISTURB_RANGE of
## `preacher`. Populous rule: her presence in a brawl breaks the sermon — and it
## breaks it for EVERY preacher in her radius, not just the one she attacks.
##
## Deliberately NOT a grid query: there is exactly one shaman per tribe and
## Tribe.shaman is a direct pointer, so this is O(#tribes) — 2 to 4 iterations
## with one distance check each. Cheaper than any get_units_in_radius call, which
## matters because _tick_sit runs per sitting unit per tick (SIT has no SoA hold).
func _preach_disturbed_by_enemy_shaman(preacher: Unit) -> bool
```

Kampf-Kriterium (Nutzerentscheidung): `sh.state == State.ATTACK` **oder**
`not sh.melee_attackers.is_empty()`. Es gibt **kein** `is_in_combat()` im Projekt;
`_in_melee` allein wäre zu eng (flackert pro Tick, die Predigt liefe zwischen zwei
Schlägen weiter).

**Kein Throttle** und bewusst keiner: 300 sitzende Einheiten × 4 Stämme = 1200
Distanzrechnungen pro Tick, das verschwindet neben der bestehenden
Pro-Einheit-Arbeit. Ein Timer wäre vorgetäuschte Sorgfalt und würde die Störung
unzuverlässig machen.

**Optionaler Feinschliff** (`preacher.gd` `_refresh_conversion`, dort ist der Scan
über `_due_to_scan` schon gedrosselt): denselben Test einhängen, damit ein
Prediger im Störradius nicht sinnlos in `State.CAST` stehen bleibt.

**Distanz zum Prediger, nicht zum Opfer** — beide liegen höchstens
`conversion_reach` (5 m) auseinander, aber Code und Test müssen dieselbe
Bezugsgröße nutzen, sonst wird der Test bei 6 m Radius zufällig grün.

---

# Teil 3 — Flächenschaden des Feuerkrieger-Feuerballs

**Vorlage ist `FireballBolt._explode()`** (`scripts/spells/fireball_bolt.gd`): eine
`get_units_in_radius`-Abfrage, `tribe_id`-Filter, DEAD-Check nach jedem
`take_damage`. Das billigste der drei vorhandenen Flächenmuster (die anderen:
Katapult-Schockwelle `siege_shot.gd` mit Friendly Fire, Feuerrammen-Explosion
`fire_ram.gd` mit Rechteck-Test).

**Einhängepunkt:** `Fireball._impact()` (`scripts/units/fireball.gd`), direkt nach
Hauptschaden und `combat_hit`-Event.

> **Falle:** unbedingt **vor** dem `if not _target_alive(): return`. Sonst
> entfällt der Flächenschaden ausgerechnet dann, wenn der Direkttreffer tödlich
> war — also im häufigsten Fall bei angeschlagenen Zielen.

Nutzerentscheidungen: **nur Feinde** (Feuerkrieger kämpfen in Massen und schießen
dauernd; mit Friendly Fire würde die hintere Reihe die eigene Front zerlegen) und
**nur Schaden**, kein Rückstoß/Anheben auf Umstehende (hunderte Bälle pro Schlacht
würden sonst jede Front durchwirbeln — und entsprechend kosten).

Details:
- `unit_manager` über `shooter.path_service`. Ist der Schütze freigegeben, **kein**
  Flächenschaden — ohne ihn ist Freund/Feind nicht entscheidbar; ein Fallback wäre
  geraten, nicht korrekt.
- Hauptziel im Loop überspringen (`u == target`), sonst doppelter Schaden.
- `CrewedVehicle` und `Airship` überspringen: die haben eigene Schadensmodelle
  (`ignite()` / `register_hull_hit()`), und 50-%-Splash-Zündung würde den
  Feuerkrieger gegen Fahrzeuge durch eine Seitentür aufwerten.
- Luftziel-Bonus `FIREWARRIOR_AIRBORNE_MULT` **pro Splash-Opfer** genauso wie beim
  Hauptziel — sonst hinge „Fliegende nehmen +20 %" davon ab, wer zufällig
  Hauptziel war.
- Schaden: `maxi(1, int(roundf(FIREBALL_DAMAGE * FW_FIREBALL_BLAST_FRAC)))`
  → bei 9 HP Hauptschaden **5 HP**.

**Perf-Pflicht:** eine zusätzliche Radius-Abfrage **pro Einschlag**, in der
Debugschlacht hunderte pro Sekunde. `benchmark_stress` vorher/nachher (Phase
`proj`), sonst ist Teil 3 nicht abgenommen — dieses Projekt hat wegen genau
solcher Posten schon eine ganze Phase zurückgerollt.

---

# Teil 4 — Anhebe-Chance skaliert invers mit den Lebenspunkten

Je verletzter das Ziel, desto leichter fliegt es. Einziger Hebel ist die Stelle in
`scripts/units/fireball.gd`, an der `lift_chance` gewählt wird (Luftziele heben
ohnehin immer ab und bleiben unberührt).

Neue **reine, statische** Funktion neben `impact_outcome` — das Projekt hat diese
Kultur schon bei `SiegeShot.roll_chance_for_slope`, beide headless erschöpfend
testbar:

```gdscript
## Lift chance scaled by the target's remaining health: a battered unit is thrown
## far more easily than a fresh one. Linear inverse — full health keeps `base`,
## an almost dead target reaches base * FW_FIREBALL_LIFT_HP_MAX_MULT.
static func lift_chance_for_health(hp_frac: float, base: float) -> float
```

Bei `MAX_MULT = 3.0` (Nutzerentscheidung): voll 4 % → fast tot 12 %; rollendes
Ziel 10 % → 30 %.

Dazu ein Helfer auf `Unit` neben `has_stars()`, das die HP-Anteil-Rechnung heute an
fünf Stellen inline wiederholt: `func health_fraction() -> float` mit dem
`maxi(max_health, 1)`-Schutz aus `sidebar.gd`.

**Testablage:** die neuen Splash- und Lift-Tests kommen in eine **neue Datei
`tests/test_fireball_impact.gd`**, nicht in `tests/test_spells.gd` — beide Themen
(Einschlagwirkung des Feuerkrieger-Balls) gehören zusammen, und `test_spells.gd`
ist eine von Parallelsitzungen häufig angefasste Datei.

**Test-Invariante:** `tests/test_spells.gd:1350-1355` sichert
`LIFT_CHANCE + ROLL_CHANCE == 0.10` bzw. `== 0.40`. Das gilt weiter — es prüft die
**Basis**konstanten. Zur Laufzeit ist die Summe aber **nicht mehr invariant**
(steigt `lift_chance` auf 0,12, schrumpft der reine Schub-Anteil). Das ist die
gewollte Wirkung und muss im Testkommentar stehen, damit der nächste Leser die
Invariante nicht „reparieren" will.

## Neue Konstanten (Teile 2–4)

```gdscript
# --- Prediger ---
## Kämpft die FEINDLICHE Schamanin so nah an einem Prediger, bricht seine Predigt
## ab und er kann keine neue beginnen (Original-Populous-Regel).
const PREACHER_SHAMAN_DISTURB_RANGE: float = 6.0

# --- Feuerkrieger ---
## Flächenschaden des Feuerkrieger-Feuerballs: Radius und Anteil am
## Hauptzielschaden. Trifft NUR Feinde und macht keinen Rückstoß.
const FW_FIREBALL_BLAST_RADIUS: float = 2.0
const FW_FIREBALL_BLAST_FRAC: float = 0.5
## Anhebe-Chance bei fast totem Ziel als Vielfaches der Basis (1.0 = keine
## Skalierung), linear invers über die HP.
const FW_FIREBALL_LIFT_HP_MAX_MULT: float = 3.0
```

---

# Teil 5 — Balance-Labor korrigieren (der Luftschiff-Befund war falsch)

`tests/balance_lab.gd` besetzt Fahrzeuge fest mit Braves (`_spawn_side`,
`um.spawn_unit(BRAVE_SCENE, …)`). Für Katapult und Ramme ist das richtig (die
schießen selbst), für das **Luftschiff macht es die Messung wertlos** — dessen
ganze Kampfkraft ist die Deck-Crew. Der Laborbefund „Luftschiffe teilen 0 HP aus"
hat also **unbewaffnete Zeppeline** gemessen und ist zu verwerfen.

1. `KINDS` bekommt `crew_kind` (Standard `&"brave"`), das Luftschiff
   `&"feuerkrieger"`; `_spawn_side` nutzt es statt der festen Konstante.
2. `_composition_cost` muss die **Ausbildungszeit der Crew** mitrechnen: drei
   Feuerkrieger auf dem Deck sind 3 BÄ **und** 12 s Ausbildung, nicht nur der
   Rumpf. Heute fehlt das und macht Fahrzeuge zu billig.
3. Neue Paarungen `luftschiffe_vs_krieger`, `luftschiffe_vs_prediger`,
   `luftschiffe_vs_katapulte` plus das korrigierte `luftschiffe_vs_feuerkrieger`
   — damit ist die Nutzer-Erwartung („gewinnt gegen alles außer Feuerkrieger und
   Katapult") direkt prüfbar.

---

## Umsetzungsschritte

1. **F8 ganz zuerst** — ein Zweig, unabhängig von allem anderen, sofort
   verifizierbar. Nicht mit dem Baustellen-Bug vermischen.
2. **Teil 1** (Bug vor Feature), in dieser Reihenfolge: F1+F2 (Kernfix, kleinster
   Eingriff mit der größten Wirkung) → Tests → F3 → F5 → F4 → F7 → F6 (Terrain,
   größtes Regressionsrisiko, zuletzt).
3. Teil 5 (Labor-Korrektur, unabhängig und schnell) — liefert die Messbasis.
4. Teil 4 (kleinste Balance-Änderung, rein lokal).
5. Teil 3 inkl. `benchmark_stress` vorher/nachher.
6. Teil 2.
7. Doku: `docs/game_mechanics.md` (Feuerkrieger-Zeile: Flächenschaden;
   Prediger-Zeile: Schamanin-Störung), `CLAUDE.md` §4.
8. `plans/PROGRESS.md`, Checkbox in [00_overview.md](00_overview.md), Commit/Push.

**Commit-Strategie:** **zwei** Commits statt einem, damit eine Kollision mit
Parallelsitzungen nicht alles blockiert — erst die **beiden Bugs** (F8 + Teil 1),
dann die **Balance-Änderungen** (Teile 2–5). Gestaged wird per Pfad
(**kein `git add -A`**), solange andere Sitzungen im Repo arbeiten.

## Tests

**Neu `tests/test_construction_stuck.gd`** — jeder Test reproduziert eine Stufe der
Kette, damit ein Rückfall zuordenbar ist:
`test_delivery_point_stays_put_when_neighbours_change` (**Kernwächter**: Punkt
merken, Nachbargebäude setzen/entfernen, Terrain verformen → Punkt bleibt),
`test_delivery_point_prefers_the_cell_nearest_the_entrance`,
`test_wood_is_booked_even_after_a_neighbour_is_placed` (die Endlosschleife:
`wood_delivered` muss steigen, `wants_more_wood()` irgendwann false),
`test_site_next_to_a_hut_still_makes_progress` (Symptom 1 als Ganzes),
`test_entrance_flatten_cell_is_skipped_inside_a_foreign_footprint`,
`test_unreachable_flatten_cell_is_dropped_after_the_timeout`,
`test_can_place_at_rejects_a_plot_without_any_approach_cell` (F4),
`test_can_place_at_still_allows_tight_but_workable_placement` (F4 darf nicht
überschießen),
`test_trapped_worker_is_snapped_back_onto_walkable_ground` (F5),
`test_foundation_rim_stays_walkable_on_a_slope` (F6: 8×8 auf Hang, Ring rundum
begehbar),
`test_site_that_never_starts_decays_despite_partial_bookings` (F7).

**Für F8** (in `tests/test_training.gd`, wo die Trainingslogik liegt):
`test_brave_walking_to_the_camp_plays_the_walk_animation`,
`test_brave_waiting_in_the_queue_slot_plays_idle`,
`test_no_state_falls_through_to_idle_while_moving` — der Wächter gegen die
**Klasse** des Fehlers: über alle `Unit.State`-Werte iterieren und für jeden
prüfen, dass er entweder in `_anim_base()` behandelt wird oder bewusst auf der
Ausnahmeliste (`IDLE`, `RAID` — letzterer wird nicht gerendert) steht. Ohne diesen
Test fällt der nächste neue Zustand genauso durch.

**Neu `tests/test_preach_disturb.gd`** (Weltaufbau nach
`tests/test_conversion_targeting.gd`):
`test_fighting_enemy_shaman_breaks_a_running_conversion`,
`test_disturbance_hits_every_preacher_in_range` (**der Fall aus der Vorgabe**: zwei
Prediger, die Schamanin greift nur einen an — beide Bekehrungen brechen),
`test_conversion_cannot_start_inside_the_disturb_range`,
`test_idle_enemy_shaman_does_not_disturb` (sie muss **kämpfen**),
`test_shaman_under_attack_also_disturbs`,
`test_own_shaman_never_disturbs`,
`test_shaman_outside_the_range_does_not_disturb` (knapp über 6 m),
`test_tower_and_deck_preachers_are_disturbed_too`.

**Neu `tests/test_fireball_impact.gd`:**
`test_fireball_splash_damages_nearby_enemies`,
`test_fireball_splash_is_half_the_direct_damage`,
`test_fireball_splash_spares_own_units`,
`test_fireball_splash_ignores_units_outside_the_radius`,
`test_fireball_splash_still_applies_when_the_direct_hit_kills` (**Regressions-
wächter** für die Reihenfolge-Falle),
`test_fireball_splash_skips_vehicles`,
`test_fireball_splash_does_not_push_bystanders`,
`test_lift_chance_rises_as_health_drops` (voll = Basis, halb = Mitte, fast tot =
Basis × MAX_MULT), `test_lift_chance_clamps_outside_zero_one`.

**Anzupassen:** `tests/test_construction_decay.gd` (F7 ergänzt ein zweites
Verfallskriterium; `test_wood_delivery_resets_the_decay_timer` bleibt gültig),
`tests/test_economy.gd` (Holzbuchung), evtl. `tests/test_ai.gd` (F4 verschärft
`can_place_at`, das die KI-Bauplatzsuche nutzt).

## Verifikation

```bash
godot --headless --check-only --script <datei>.gd     # je geänderte Datei
godot --headless -s res://tests/run_tests.gd          # Exit 0, kein "SCRIPT ERROR"
godot --headless --quit                               # Ladecheck
godot --headless -s res://tests/benchmark_stress.gd   # Teil 3: Phase `proj` vorher/nachher
godot --headless -s res://tests/benchmark_earlygame.gd -- map=bergpass sim=600
godot --headless -s res://tests/balance_lab.gd -- reps=5 csv=1
```

Godot-Läufe über das **Bash**-Tool (PowerShell verschluckt Godot-stdout), Output
auf `SCRIPT ERROR` filtern — abgebrochene Testmethoden melden trotzdem
„0 failed". Perf-Messungen verschränkt A/B: das Maschinenrauschen liegt hier bei
bis zu 40 %, Einzelläufe beweisen nichts.

`benchmark_earlygame` gehört zu **Teil 1**: F4 verschärft `can_place_at`, das die
KI-Bauplatzsuche benutzt. Findet die KI danach deutlich weniger Plätze
(`dbg_plot_scans`/`plots`-Spalte, gebaute Gebäude), ist F4 zu streng.

**Balance-Abnahme statt Sollwerten** — das Labor ist das Messgerät:
- Die Prediger-Paarungen bleiben **ohne Schamanin unverändert**; das ist erwartet
  und kein Fehlschlag. Für die Wirkung von Teil 2 braucht es eine **neue Paarung
  mit Schamanin auf der Anti-Prediger-Seite**, sonst ist sie gar nicht messbar.
- Die Feuerkrieger-Paarungen müssen sich sichtbar verbessern: die 36 % Poolschaden
  sollen jetzt in **Kills** umschlagen. Bleibt die Kill-Zahl bei ~0, hat der
  Flächenschaden das Kernproblem nicht getroffen.

**Manuelle Prüfung:**
- **F8:** Brave selektieren, Rechtsklick auf ein Trainingsgebäude → er läuft in der
  **Lauf**-Animation hin und steht erst im Warteslot still.
- Hütte dicht neben eine Hütte setzen → wird gebaut, kein Holzberg, Arbeiter machen
  Fortschritt. Feuertempel (8×8) auf leicht hängiges Gelände → Arbeiter kommen rein
  *und* raus, Fortschritt läuft.
- Prediger bekehren, eigene Schamanin in den Nahkampf daneben → Bekehrung bricht
  sichtbar ab; Schamanin nur daneben stehen lassen → läuft weiter.
- Feuerkrieger auf eine dichte Gruppe → Umstehende nehmen Schaden, eigene nicht.
  Angeschlagene Ziele fliegen merklich öfter.

## Risiken

1. **F4 könnte die KI aushungern** (`can_place_at` ist ihr Bauplatz-Filter).
   Messung über `benchmark_earlygame` ist Pflicht, nicht optional.
2. **F6 verformt Terrain** über den Grundriss hinaus. Das kann mit
   Landbrücke/Erdbeben/Ebene interagieren und bestehende Terrain-Tests brechen.
   Deshalb zuletzt und mit eigenem Test.
3. **F3 lässt Planierzellen fallen** — im Extremfall bleibt eine Delle neben dem
   Eingang. Bewusster Tausch: eine Delle ist besser als eine tote Baustelle.
4. **Perf des Flächenschadens** (Teil 3), eine Radius-Abfrage je Einschlag.
5. **Feuerkrieger könnten überschießen:** Flächenschaden + höhere Anhebe-Chance
   treffen dieselbe Einheit, die bisher der Verlierer war. Nachjustieren über
   `FW_FIREBALL_BLAST_RADIUS` (2 m ist ein Schätzwert) bzw. `_BLAST_FRAC` — reine
   Balance-Werte, kein Codeeingriff.
6. **Prediger-Störung könnte zu stark sein**, wenn eine kämpfende Schamanin einen
   ganzen Trupp lahmlegt (6 m fassen mehrere Prediger). Absicht, aber der Radius
   ist der Regler. Ohne Schamanin bleibt die Prediger-Dominanz unangetastet — die
   Änderung ist ein Gegenmittel, keine Nerfung.
7. **Parallelsitzungen** arbeiten im selben Repo. Teil 1 berührt `building.gd`
   stark; vor Beginn `git pull` und die Bereiche abgleichen.

## Definition of Done

- [ ] F8 behoben, inkl. Wächter-Test über alle `State`-Werte
- [ ] Baustelle neben einer Hütte baut; kein wachsender Holzstapel; Arbeiter
      kommen aus dem Grundriss heraus
- [ ] `delivery_point()` bleibt stabil, wenn sich die Nachbarschaft ändert
- [ ] Prediger-Störung wirkt auf **alle** Prediger im Radius der kämpfenden
      feindlichen Schamanin
- [ ] Feuerkrieger-Flächenschaden trifft nur Feinde, auch bei tödlichem
      Direkttreffer; `benchmark_stress` ohne Regress
- [ ] Anhebe-Chance skaliert invers mit den HP
- [ ] Balance-Labor besetzt Luftschiffe mit Feuerkriegern; Luftschiff-Paarungen neu
      bewertet
- [ ] Testsuite grün, `--headless --quit` fehlerfrei
- [ ] Manuelle Prüfung durch den Nutzer bestanden
- [ ] PROGRESS.md ergänzt, Checkbox in [00_overview.md](00_overview.md), Commit/Push
