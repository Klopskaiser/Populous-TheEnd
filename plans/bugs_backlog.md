# Bug-Backlog — offene Fehler für spätere Behebung

> Gesammelt am 2026-07-13 (Nutzertest nach Phase 8.2). Behebung geplant als eigener
> Bugfix-Pass **vor oder zu Beginn von Phase 9**. Pro Bug: Symptom, Soll-Verhalten,
> bekannte Code-Ansatzpunkte. Nach Behebung: Checkbox abhaken, Eintrag ggf. um
> Ursache/Fix ergänzen (Erkenntnisse zusätzlich in PROGRESS.md).

## Bug 1 — UI-Skalierung / Auflösung

- [x] **Status: behoben (2026-07-18)**

**Symptom:** UI ist ungünstig skaliert. Bei 1080p ist z. B. im Werkstatt-Panel unten
die Katapult-Anzahl abgeschnitten und die Arbeiterplätze sind nicht alle sichtbar.

**Soll:**
- Zielauflösungen sind **1920×1080 und 2560×1440** — dort müssen alle UI-Elemente
  vollständig sichtbar und gut lesbar sein.
- **Neuer Optionspunkt „Auflösung"** im Optionsmenü (Auswahl der Fensterauflösung,
  mind. 1080p und 1440p).

**Ursache/Fix (2026-07-18):**
- Ursache: `project.godot` hatte Basis 1280×800 **ohne Stretch-Mode** (UI skalierte
  nicht mit dem Fenster), und die Sidebar-VBox stapelte Tab-Content (min. 300 px)
  + Gebäudepanel über die verfügbare Höhe hinaus → Werkstatt-Panel unten abgeschnitten.
- `project.godot`: Basisauflösung **1920×1080**, `window/stretch/mode="canvas_items"`,
  `aspect="expand"` — bei 1080p rendert das UI 1:1, bei 1440p skaliert es ×1,33.
- `game_settings.gd`: Auflösung persistiert (`resolution_w/h` in `user://settings.cfg`,
  Sektion `display`), `apply_resolution()` setzt/zentriert das Fenster
  (Headless-Guard für Tests).
- `main_menu.gd`: Optionspunkt „Auflösung" (OptionButton 1920×1080 / 2560×1440),
  Anwendung beim Start in `_ready()`.
- `sidebar.gd`: Tab-Content schrumpft auf Kompakt-Höhe (120 px), solange ein
  Gebäude-/Crew-Panel offen ist (`_update_tab_content_height()`); Zauber- und
  Gefolgsleute-Tab scrollen dafür jetzt wie der Gebäude-Tab.

## Bug 2 — Unfertige Gebäude durch Einheiten nicht zerstörbar

- [x] **Status: behoben (2026-07-18)**

**Symptom:** Nicht fertig errichtete Gebäude (Baustellen) können von Einheiten
angegriffen werden, werden aber nie zerstört — nur Katapulte (und Zauber, siehe
`apply_destruction_stages`) können Baustellen vernichten.

**Soll:**
- Einheiten können halb fertige Gebäude **auch zerstören**.
- Unfertige Gebäude haben **Lebenspunkte auf Grundlage des bisher verbauten Holzes**:
  maximal **3 Stufen** (weil noch nicht fertig) — fertige Gebäude haben 4 Stufen.
  D. h. HP skalieren mit `wood_delivered / wood_cost`, gedeckelt bei 3/4 der
  Voll-HP.

**Ansatzpunkte:**
- `scripts/buildings/building.gd`: `take_damage()` / `under_construction` /
  `apply_destruction_stages()` (Baustellen werden dort bei Zauber-Stufenschaden sofort
  eingeebnet, Zeile ~326). Prüfen, warum Einheiten-Angriffe (Sturmangriff/Fernkampf aus
  Phase 7g) Baustellen nicht töten — vermutlich sind HP der Baustelle von Anfang an auf
  `max_health` bzw. der Sturm-/Zerstörungspfad ist auf fertige Gebäude beschränkt.
- HP-Modell für Baustellen einführen: aktuelle HP an Baufortschritt/verbautes Holz
  koppeln; bei 0 HP Baustelle zerstören (versinkt, Bauplatz wieder frei — wie Stufe 4).
- Phase-7g-Logik (Sturmangriff, Insassen-Auswurf) gegen Baustellen absichern
  (Baustellen haben keine Insassen/Raiders).

**Ursache/Fix (2026-07-18):**
- Bestätigt per Repro-Test: Baustellen starteten mit **vollen HP** (300), und
  `Building.tick()` rief `_tick_raid()` nur für **fertige** Gebäude auf —
  Nahkampf-Raider wurden zwar eingelassen, machten aber nie Schaden.
  (Feuerkrieger-Beschuss konnte Baustellen schon vorher zerstören, nur eben
  gegen volle 300 HP.)
- Fix in `building.gd`: Baustellen-HP-Modell — `health` startet bei
  `SITE_MIN_HP` (1) und wächst mit dem angelieferten Holz
  (`wood_delivered / wood_cost × max_health`, Deckel `SITE_HP_CAP_FRACTION`
  = 3/4 der Voll-HP = 3 von 4 Zerstörungsstufen). Schaden bleibt beim
  HP-Wachstum erhalten (nur das Deckel-Delta wird addiert) und wird bei
  `finish_construction()` in das Voll-HP-Modell übernommen (reparierbar).
  `tick()` ruft `_tick_raid()` jetzt auch während der Bauphase auf.
- Tests: `tests/test_construction_assault.gd` (neu, 17 Checks: HP-Modell,
  Nahkampf-Raid, Befehls-Pipeline, Feuerkrieger, Pre-Built unverändert).

## ~~Bug 3 — Reparatur von Gebäuden~~ (gestrichen)

**Gestrichen 2026-07-13:** Reparatur ist bereits implementiert und funktioniert
(Nutzer bestätigt) — `TribeCommands.order_repair()`, `Brave.order_repair()`,
`Building.repair()` mit `floor(Schadensanteil × Holzkosten)` gemäß CLAUDE.md §5.
Kein Handlungsbedarf.

## Bug 4 — Holzsuche: Priorisierung nach Luftlinie führt zu Umwegen

- [x] **Status: behoben (2026-07-18)**

**Symptom:** Braves machen große Umwege, um Bäume zu fällen, die z. B. mitten an einer
Klippe wachsen (Arbeiter muss erst eine Rampe hinunter), obwohl näher erreichbare Bäume
auf der gleichen Ebene stehen.

**Ursache (verifiziert):** `TreeManager._nearest()`
(`scripts/core/tree_manager.gd:199`) wählt Bäume rein nach **XZ-Luftlinie**
(`distance_squared_to`), ohne Erreichbarkeit/Laufweg zu berücksichtigen. Genutzt von
`claim_nearest_tree()` (Brave-Holzsuche, `scripts/units/brave.gd:804`) und
`nearest_tree()` (KI).

**Soll:**
- Bäume auf der **gleichen Ebene** bevorzugen — nicht bloße Luftlinie.
- Vermutlich reicht bereits der Vergleich der **tatsächlichen Laufweg-Länge**
  (NavGrid-Pfadkosten) statt Luftlinie. Priorisierung insgesamt prüfen.

**Ansatzpunkte:**
- Kandidaten weiterhin per Luftlinie vorfiltern (Top-N), dann per
  `NavGrid.find_path()`-Länge (oder einer billigeren Erreichbarkeits-/Höhenheuristik,
  z. B. Höhendifferenz-Malus) nachsortieren — **Achtung Performance:** keine
  Pfadberechnung pro Baum pro Scan für hunderte Braves; ggf. Path-Worker (Phase 8.1)
  nutzen oder Ergebnis cachen.
- Betroffene Stellen: `tree_manager.gd` (`_nearest`, `claim_nearest_tree`,
  `nearest_tree`), Aufrufer `brave.gd` (CHOP_CHAIN_RADIUS-Suche) und
  `ai_controller.gd:884`.

**Ursache/Fix (2026-07-18):**
- Ein `same_island`-Check existierte bereits (völlig unerreichbare Bäume
  wurden übersprungen), half aber nicht im Plateau-Fall: Der Baum unter der
  Klippe IST über die Rampe erreichbar (gleiche Insel) — nur mit Riesenumweg.
- Fix in `TreeManager._nearest()`: **Höhendifferenz-Malus** statt reiner
  Luftlinie — Score = Flachdistanz + `HEIGHT_DETOUR_PENALTY` (6,0) ×
  |Höhendifferenz|. Bäume auf gleicher Ebene gewinnen gegen luftlinien-nähere
  Bäume auf anderer Ebene; ohne Alternative wird der erreichbare Klippen-Baum
  weiterhin gewählt. Bewusst O(1) pro Baum (kein `find_path` im Scan —
  Perf-Vorgabe). Gilt automatisch auch für die KI (`nearest_tree`).
- Tests: `tests/test_tree_priority.gd` (neu, 11 Checks mit Plateau+Rampen-
  Terrain: gleiche Ebene gewinnt, Fallback, Radius, Gleichstand).

## ~~Bug 5 — Katapult & Feuermechanik (Lava, Brennen, Raider-Beschuss)~~ (behoben)

- [x] **Status: behoben 2026-07-18** (gemeldet und gefixt am selben Tag)

Vier zusammenhängende Bugs, alle behoben:

1. **Katapult-Treffer auf Gebäude erzeugte keine Lavapfütze** — Einheiten am Einschlag
   brannten nicht. Fix: `SiegeShot._impact()` spawnt die Pfütze jetzt IMMER; bei
   Gebäudetreffern mit `damage_buildings = false` (das Projektil hat den Gebäudeschaden
   schon gemacht, die Pfütze beschädigt dann keine Gebäude mehr).
2. **Lava beschädigte Gebäude nicht.** Fix: `Building.add_lava_contact()` — 1
   Zerstörungsstufe je volle 5 s Lavakontakt (`Balance.LAVA_BUILDING_STAGE_TIME`),
   Zähler-Reset nach 1 s ohne Kontakt (`LAVA_BUILDING_CONTACT_GRACE`, nur DAUERHAFTER
   Kontakt zählt). `LavaSurge`/`LavaFlow` melden Kontakt im 0,2-s-Takt. Der pauschale
   `VolcanoZone._wreck_buildings()`-Schaden (alle 4 s, Radius 5) wurde ERSETZT —
   Vulkan-Gebäudeschaden kommt jetzt nur noch aus echtem Lavakontakt der Wellen
   (Reichweite 7,5).
3. **Einheiten brannten am Vulkan nicht zuverlässig** (Zündlücke zwischen den
   Eruptionswellen: molten-Fenster ~3,7 s je Welle, Intervall 4,5 s). Fix: die
   `VolcanoZone` zündet während der Eruptionsphase selbst kontinuierlich (alle 0,2 s)
   alle Einheiten im Lavabereich.
4. **Katapult gegen eigenes Gebäude mit Raidern war nutzlos** (eigene Gebäude waren für
   Befehl und Einschlag komplett gesperrt). Fix: eigenes Gebäude MIT Raidern ist gültiges
   Ziel (`SiegeEngine.order_attack_building`, `SiegeShot._building_at_impact`,
   `SelectionManager._dispatch_own_raided_building`); Treffer ruft
   `Building.blast_raiders()` — Raider fliegen mit 30 Schaden
   (`Balance.SIEGE_SHOT_RAIDER_DAMAGE`) und Roll-Effekt raus, können danach wieder rein
   oder das Katapult angreifen — und das eigene Gebäude nimmt 1 Stufe pro Treffer.
   Eigene Gebäude OHNE Raider bleiben unantastbar (Frust-Schutz).

Tests: `test_siege.gd` (+4 Tests) und `test_spells.gd` (Kadenz-Test umgeschrieben,
+3 Tests) decken alle vier Fälle ab.

## Bug 6 — Angriff auf bemannten Wachturm: Einheiten laufen nicht los

- [x] **Status: behoben (2026-07-18)** (gemeldet und gefixt am selben Tag)

**Symptom:** Prediger oder Nahkämpfer mit Gebäude-Angriffsbefehl auf einen
(bemannten) Wachturm zeigen die Bewegungsanimation, laufen aber nicht los und
können den Turm nie angreifen. Bei anderen Gebäuden funktioniert der Befehl.
Nachstellbar auf der Startmission.

**Ursache:** `Building.nearest_entrance_threat()` filterte nicht auf
`is_targetable()`. Die garnisonierte Turm-Crew (geschützte Reserve, bleibt in
der Welt registriert und steht auf der Plattform nahe dem Eingang) zählte
dadurch als „Bedrohung am Eingang". `_storm_building()` versuchte jeden Tick,
diese Bedrohung per `_begin_attack()` anzugreifen — das weist nicht-zielbare
Einheiten aber grundsätzlich ab (Katapult-/Turm-Crew-Schutzregel). Ergebnis:
Deadlock — kein Anmarsch, kein Sturm, nur stehende „Lauf"-Animation.

**Fix:** `nearest_entrance_threat()` überspringt nicht-zielbare Einheiten.
Die Crew ist IM Turm, nicht an der Tür — der Sturm beginnt normal, wirft die
Crew lebend raus (dann ist sie zielbar und verteidigt), danach wird abgerissen.

Tests: `test_watchtower.gd` +3 (Crew ≠ Eingangs-Bedrohung; Prediger marschiert
los — ohne Fix „moved 0.0 m"; volle Pipeline: Krieger schleifen bemannten Turm).
