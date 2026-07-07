# Phase 7i — Balancing, Karten & Wirtschaft (Zwischenphase vor Phase 8)

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).
> **Bewusst VOR Phase 8** eingeschoben: kleinere Balancing-/Feature-Änderungen,
> die den Feature-Stand abrunden, bevor der reine Perf-/Feinschliff-Pass (Phase 8)
> darüber läuft. Die neuen Konstanten hier werden in Phase 8 nach `Balance` (zentrale
> Konstantenklasse) verschoben — hier bleiben sie noch in ihren Klassen.

## Ziel

Ein Bündel aus Balancing- und Verhaltensänderungen sowie zwei neuen Features
(Kartenauswahl mit 3 neuen Karten, bemannbare Hütten mit Wachstumssteuerung):

1. **Priester-Angriffsverhalten** — bessere Verteilung mehrerer Priester; Einheiten
   in Bekehrung sind kein legitimes Ziel für andere Einheiten (Ausnahme: Katapult).
2. **Kartenauswahl im Skirmish** + 3 neue Karten (zwei davon doppelt so groß).
3. **Sonstiges Balancing:** Einheiten-Hardcap 1500/Spieler; Hütten billiger & kleiner;
   Feuertempel/Tempel größer & teurer; bemannbare Hütten mit Wachstumsregler;
   Mana-Zuwachs als Zahl; höhere Manabedarfe für die „hohen" Zauber.

## Voraussetzungen

- Phasen 1–7h: vollständiges Skirmish, Prediger-Bekehrung (`Preacher`,
  `Unit.begin_conversion`/`_tick_sit`/`_scan_for_enemy`), Besatzungs-/Trainee-Mechanik
  (`garrison_housed`, `remove_from_world`, Wachturm-Crew als Vorlage), Skirmish-Setup
  (`main.gd::_setup_skirmish`), Sidebar-Wirtschaftsanzeige, Zauber-Ladungssystem.

## Dokumentierte Auslegungen (Entscheidungen & offene Punkte)

- **CLAUDE.md-Abgleich (wichtig):** Diese Phase ändert Spec-Werte aus CLAUDE.md
  bewusst ab: §5 „Hütte = 100 Platz" → **40 Platz, 12 Holz**; Zauberkosten §6.
  **Zu Phasenabschluss CLAUDE.md §5/§6 nachziehen**, damit Spec und Code
  konsistent bleiben (die konkreten neuen Werte stehen unten).
- **„Doppelt so groß" = 256×256 Zellen (Architektur-Risiko #1).** Standardkarte =
  `TerrainData.SIZE = 128` (fester `const`, an ~71 Stellen in 15 Dateien
  referenziert: main, terrain, nav_grid, minimap, camera_rig, tree_manager,
  Zauber …). Für variable Kartengrößen muss die Kantenlänge **pro TerrainData-Instanz**
  werden (Instanzfeld `size`/`verts` statt Klassen-`const`), inkl. `HeightMapShape3D`
  (origin-zentriert, Offset `size/2`), chunked ArrayMesh, `AStarGrid2D`-Region und
  Minimap-Skalierung. **Das ist der teuerste Teil dieser Phase** — zuerst umsetzen,
  Regressionsschutz über die bestehende Suite. Standard bleibt 128; die zwei großen
  Karten sind 256. (Kein Blocker, aber bewusst als eigener Schritt 0 geführt.)
- **Bekehrungs-Ziele bereits teilweise ignoriert:** `Unit._scan_for_enemy` und der
  Siege-Scan überspringen `State.SIT` schon heute. Neu ist v. a. (a) die
  **Prediger-Verteilung** und (b) die **Katapult-Ausnahme** (Siege soll SIT-Einheiten
  wieder angreifen dürfen). „Außer sie kämpfen noch": eine sitzende Einheit kämpft
  per Definition nicht (SIT), daher ist der reine SIT-Skip die korrekte Umsetzung.
- **Hütten-Besatzung analog Wachturm-Crew/Trainees:** besetzende Braves werden per
  `remove_from_world` aus der Welt genommen (Population zählt weiter), kosten **kein
  Mana**. Leere Hütte = keine Produktion.
- **Produktionsrate:** volle Besatzung (4) ≈ **10 % schneller als heute**
  (heute `SPAWN_INTERVAL = 10 s`). Vorschlag: Rate skaliert linear mit Besatzung,
  0 → keine Produktion, 4 → `10 / 1.10 ≈ 9.09 s`. Formel/Kurve tunebar
  (siehe Deliverables); exakte Zwischenwerte in der Umsetzung festlegen.
- **Größen-Zahlen (Vorschlag, tunebar):** Feuertempel Footprint **4×4 → 8×8**
  („vielmal so groß", vieleckiges Modell), Kosten **10 → 20 Holz**. Tempel Footprint
  **4×4 → 6×6** („doppelt so groß"), Kosten **5 → 15 Holz**. Bei Footprint-Wachstum:
  NavGrid-Solid-Footprint, `edge_spawn_position`, Platzierungsprüfung und KI-Bauplätze
  müssen mit den größeren Grundrissen klarkommen (mehr Platzbedarf in engen Basen).
- **Hardcap 1500/Spieler** gilt zusätzlich zum Housing-Limit (Hütten-Kapazität); es
  greift, was zuerst limitiert. Betrifft Hütten-Spawn UND Training (Kaserne/Feuertempel/
  Tempel/Werkstatt) — zentral in `UnitManager.spawn_unit` prüfen.

## Deliverables

| Bereich | Datei(en) | Inhalt |
|---|---|---|
| **0. Variable Terraingröße** | `terrain_data.gd`, `terrain.gd`, `nav_grid.gd`, `minimap.gd`, `camera_rig.gd`, alle `TerrainData.SIZE`-Aufrufer | Kantenlänge pro Instanz (`size`, `verts = size+1`) statt Klassen-`const`; `SIZE` bleibt als **Default (128)** für Fallbacks. Kollisions-Offset, Chunk-Loop, AStarGrid2D-`region`, Minimap-Maßstab aus der Instanzgröße ableiten. Regression: Suite grün mit 128. |
| **1. Kartensystem** | `scripts/core/map_generator.gd` (neu), `terrain_data.gd`, `match_config.gd`, `main.gd` | `MapGenerator` mit Registry `{id → {name, size, generate(td), spawn_anchors(n) }}`. `map_id` in `MatchConfig` bereits vorhanden → nutzen. `main.gd::_ready` ruft den Generator statt fest `generate_island`; Skirmish-Spawnanker kommen aus der Karte statt aus `SKIRMISH_BASE_RADIUS`. „island" bleibt als Standardkarte erhalten. |
| **1b. 3 neue Karten** | `map_generator.gd` | **A „Seenland" (256):** überwiegend Land, See in der Mitte, **angehobene Ecken**, 4 Startecken. **B „Bergpass" (256):** flach, kein Wasser, mittiges **Gebirge mit 3 engen Durchgängen** und scharfen Klippen an den Ausläufern; Gebirge teilt die Karte in zwei Hälften (je 2 Spieler), Basen relativ **nah beieinander**. **C „Plateau" (128):** jeder Spieler auf glatter, stark angehobener Ebene mit **harten Kanten**; restliches Terrain flach, kein Wasser. Höhen über `set_vertex_height`/`raise_area`; „harte Kanten"/„Klippen" = steile Höhendifferenz (bewusst > `MAX_SLOPE` → nicht begehbar außer über Rampen/Pässe). |
| **1c. Kartenauswahl-UI** | `scripts/ui/main_menu.gd` | Im Skirmish-Setup Auswahl der Karte (Buttons/Dropdown, deutsche Namen) → `MatchConfig.map_id`. Bei > 2 Spielern nur Karten mit genügend Startankern zulassen (Bergpass/Plateau ggf. auf passende Spielerzahl begrenzen; Regeln dokumentieren). |
| **2. Prediger-Verteilung** | `preacher.gd`, ggf. `unit.gd` | Mehrere Prediger verteilen sich: Fokusziel-Wahl (`_refresh_conversion`/`_scan_for_enemy`) bevorzugt Gegner, die **noch von keinem Prediger bekehrt werden** (SIT-Einheiten sind einem Prediger via `converting_preacher` zugeordnet und werden übersprungen). Erst wenn eine Einheit aus der Bekehrung kommt, ist sie wieder Ziel. Gilt auch bei **Attack-Move** (`_engage_on_sight` beim Marschieren). Ziel: keine zwei Prediger auf demselben Cluster/derselben Einheit. |
| **2b. Bekehrte = kein Ziel** | `unit.gd` (Scan bereits SIT-safe), `siege_engine.gd` | Nah-/Fernkampf ignorieren SIT-Einheiten weiterhin und suchen neue Ziele (Ist-Stand bestätigen/absichern). **Ausnahme Katapult:** der Siege-Scan (`siege_engine.gd`, aktuell `if u.state == State.SIT: continue`) soll SIT-Einheiten **wieder zulassen** → Katapult darf Konvertierende beschießen. |
| **3. Hardcap 1500** | `unit_manager.gd`, `tribe.gd` | `Tribe.MAX_UNITS = 1500` (oder Konstante in UnitManager). `spawn_unit` gibt `null` zurück / verweigert, wenn der Ziel-Tribe am Cap ist. Hütten-Spawn (`hut.gd`) und Training (`training_building.gd`) prüfen das Ergebnis sauber (kein Doppel-Zählen, keine „Geister"-Trainees). |
| **4. Hütte billiger/kleiner** | `hut.gd`, ggf. `main.gd`/KI | `WOOD_COST 15 → 12`, `CAPACITY 100 → 40`. Reparaturkosten (`floor(Schadensanteil × Holzkosten)`) folgen automatisch. |
| **5. Feuertempel groß/teuer** | `firewarrior_camp.gd` (+ `.tscn`) | `WOOD_COST 10 → 20`, Footprint **4×4 → 8×8**, **vieleckiges** (mehreckiges) größeres Placeholder-Modell (statt Rundhütte). |
| **6. Tempel groß/teuer** | `temple.gd` (+ `.tscn`) | `WOOD_COST 5 → 15`, Footprint **4×4 → 6×6**, Modell entsprechend skaliert. |
| **7. Bemannbare Hütten + Wachstumsregler** | `hut.gd`, `tribe.gd`, `tribe_commands.gd`, `selection_manager.gd`, `sidebar.gd`, `brave.gd`, `ai_controller.gd` | Kern-Feature, Details unten. |
| **8. Mana-Zuwachs als Zahl** | `sidebar.gd`, `tribe.gd` | Neben der segmentierten Manaleiste den aktuellen **Mana/s** als Zahl anzeigen (aus `population*MANA_BASE_RATE + praying*MANA_PRAY_BONUS`, minus Förster-Upkeep). |
| **9. Höhere Zauberkosten** | `earthquake.gd`, `volcano.gd`, `firestorm.gd` (ggf. `tornado.gd`, `flatten_spell.gd`) | „Hohe" Zauber teurer. Vorschlag: Erdbeben `80→110`, Vulkan `120→180`, Feuerregen `70→100`; optional Tornado `90→110`, Ebene `70→90`. Werte tunebar; Ladungssystem (`charge_cost`) sonst unverändert. |
| **10. Bauplatz freiräumen (Bugfix)** | `building.gd`, ggf. `unit.gd`/`unit_manager.gd` | **Bug:** `BuildingManager.place` markiert den Footprint zwar sofort als NavGrid-solid (neue Pfade laufen außen herum), aber Einheiten, die beim Baustart **bereits auf dem Footprint stehen** (oder idle darauf), werden nicht verdrängt → sie stecken im aufsteigenden Gebäudemesh und sind unsichtbar. **Fix:** sobald das Gebäude **wirklich gebaut wird** (BUILD-Phase, **`wood_delivered >= 1`** — nicht schon bei Platzierung/Flatten), räumt der Bau-Tick den Footprint: alle Einheiten mit Flat-Position in `footprint_rect()` (außer den zuliefernden Bauarbeitern am `delivery_point`, und außer DEAD/THROWN/ROLL) bekommen einen kurzen `order_move` auf die **nächste begehbare Zelle außerhalb** des Footprints. Gedrosselter Re-Check während der ganzen BUILD-Phase (falls jemand nachrückt). Einheitensuche über `path_service.get_units_in_radius(footprint_center, halbe Diagonale)` + Footprint-Filter. |
| **Doku** | CLAUDE.md, `PROGRESS.md` | CLAUDE.md ist veraltet und wird **generell nachgezogen** — nicht nur die neuen 7i-Werte (§5 Hütte 12 Holz/40 Platz; §6 höhere Zauberkosten), sondern auch der seit 7b–7h aufgelaufene Stand: §6 listet nur die 5 Ur-Zauber (jetzt 10: + Erdbeben/Vulkan/Feuerregen/Ebene/Absinken), §4/§5 kennen Wachturm/Belagerungswaffe+Werkstatt/Förster noch nicht. PROGRESS ergänzen. |
| **Tests** | `tests/test_hut_crew.gd` (neu), Erweiterungen in `test_preacher*`, `test_terrain*`, `test_unit_manager*`/`test_tribe*` | siehe unten |

### Feature 7 im Detail — Bemannbare Hütten & Wachstumsregler

- **Besatzung:** `hut.gd` bekommt `crew: Array` (max **4**), `admit_crew(brave)` /
  `eject_crew(n)` analog Wachturm-Crew (nur **Braves**; `remove_from_world`, Population
  bleibt gezählt, **kein Mana**). Leere Hütte (`crew.is_empty()`) → **keine Produktion**
  (`_tick_active` früh raus). Produktionsrate skaliert mit `crew.size()`
  (0 = aus … 4 = ~10 % schneller als heute); `production_progress` spiegelt das wider.
- **Manuell besetzen:** Braves selektiert + Rechtsklick auf **eigene** Hütte →
  `TribeCommands.order_man_hut` (Braves laufen zum Eingang, treten ein bis 4 Plätze;
  Überzählige bleiben). „Rauswerfen" über Gebäude-Selektion (wie Wachturm-Auswurf).
- **Wachstumsregler (neues UI im Bevölkerungs-/Holz-Bereich der Sidebar)** mit 3 Stufen:
  - **Kein Wachstum:** setzt alle Hütten-Besatzungen automatisch auf 0 und wirft alle
    raus; idle Braves besetzen **keine** leeren Hütten.
  - **Minimalwachstum:** nach jeder **neu fertiggestellten** Hütte geht **einer** der
    nahen Arbeiter dort arbeiten; wird eine Hütte leer, geht **ein** naher idle Brave
    (ohne andere Aufgabe / nicht im Kampf) hinein.
  - **Maximum:** neu fertiggestellte Hütten werden mit **4** aufgefüllt (wenn genug nahe
    Braves da); idle Braves füllen nahe Hütten bis 4.
- **Nähe-Regel:** Braves besetzen **nur** Hütten in ihrer Nähe automatisch → auch bei
  „Maximum" können Hütten leer bleiben. Auto-Besetzung nur aus **IDLE**, nicht wenn der
  Brave sammelt/baut/kämpft.
- **Anzeige:** neben dem Regler das **Bevölkerungswachstum** anzeigen (z. B. Braves/min
  oder aktive/max Hüttenplätze). Regler-Zustand pro Tribe (Spieler steuert seinen; KI
  hat internen Default, s. u.).
- **KI:** nutzt denselben Mechanismus (Symmetrie!) — sinnvoller Default (z. B.
  „Maximum" in der Aufbauphase), besetzt eigene Hütten über `order_man_hut`.

## Umsetzungsschritte

0. **Variable Terraingröße** (Refactor): `SIZE`-`const` → Instanzgröße; alle Aufrufer
   umstellen; Suite mit 128 grün halten (reiner Regressions-Schritt).
1. **Kartensystem + 3 Karten + Auswahl-UI**; Skirmish-Spawnanker aus der Karte.
2. **Prediger-Verteilung** + Katapult-Ausnahme + Bekehrte-kein-Ziel absichern.
3. **Kleines Balancing:** Hardcap, Hütten-/Feuertempel-/Tempel-Werte & Modelle,
   Zauberkosten, Mana-Zuwachs-Anzeige, **Bauplatz-Freiräumen-Bugfix**.
4. **Bemannbare Hütten + Wachstumsregler** (Datenebene → Commands → UI → KI).
5. **Verifikation** (Syntax-Check je Datei, `--headless --import`, Suite,
   `--headless --quit`), **manuelle Prüfung**, CLAUDE.md/PROGRESS nachziehen,
   Commit/Push.

## Tests

- **Terrain:** TerrainData mit `size = 256` erzeugt `257²` Vertices; `get_height`/
  `raise_area`/`is_walkable` an den neuen Rändern korrekt; Kollisions-Offset = `size/2`.
- **Karten:** jede der 3 Karten generiert; `spawn_anchors(n)` liefert für die
  unterstützte Spielerzahl begehbare, paarweise ausreichend entfernte Anker;
  Klippen/Plateau-Kanten sind wie erwartet **nicht** begehbar, die 3 Bergpässe **sind**
  begehbar.
- **Prediger:** zwei Prediger + ein Cluster konvertierbarer Gegner → sie fokussieren
  **verschiedene** Ziele; kein zweiter Prediger startet die Bekehrung einer bereits
  sitzenden (fremd zugeordneten) Einheit; nach `reset_conversion` ist sie wieder wählbar.
  Attack-Move: Prediger sucht beim Marsch nicht-bekehrte Ziele.
- **Bekehrte-kein-Ziel:** Krieger/Feuerkrieger ignorieren SIT-Einheiten (Scan findet
  sie nicht); **Katapult** wählt eine SIT-Einheit als Ziel.
- **Hardcap:** Tribe am Cap 1500 → `spawn_unit` verweigert; Hütte/Training erzeugen
  keine Einheit; Population bleibt exakt 1500.
- **Kosten/Kapazität:** Hütte 12 Holz/40 Platz; Feuertempel 20 Holz/8×8-Footprint blockt
  NavGrid; Tempel 15 Holz/6×6-Footprint.
- **Hütten-Crew:** `admit_crew` bis 4, fünfter abgewiesen, Brave-only; leere Hütte
  produziert nicht; volle Hütte ~10 % schneller als 10 s; Population konstant über
  Besetzen/Auswerfen; Regler „Kein Wachstum" wirft alle raus; „Minimal"/„Maximum"
  füllen nach Fertigstellung wie spezifiziert (Nähe-Regel testbar über gesetzte
  Positionen).
- **Zauberkosten:** neue `charge_cost`-Werte der hohen Zauber; Ladungslogik unverändert
  (Rundrobin, `is_full`).
- **Bauplatz freiräumen:** Einheit auf dem Footprint platziert, Bau erreicht
  `wood_delivered >= 1` → Einheit bekommt ein Move-Ziel **außerhalb** des Footprints
  (Endposition liegt nicht mehr in `footprint_rect()`); beim reinen Platzieren/Flatten
  (noch 0 Holz) wird **nicht** verdrängt.
- **Regression:** gesamte bestehende Suite bleibt grün.

## Manuelle Prüfung

- Skirmish-Menü: alle 4 Karten auswählbar, Spielerzahl-Regeln greifen; Match startet auf
  der gewählten Karte, Basen an den erwarteten Startpunkten (Ecken / je Hälfte / Plateau).
- Große Karten (256) laufen ohne Hitches beim Terrainaufbau; Landbridge/Zauber verformen
  auch am Rand korrekt.
- Zwei Prediger auf eine Gegnergruppe schicken → sie verteilen sich sichtbar; andere
  Einheiten laufen an Sitzenden vorbei zu neuen Zielen; Katapult beschießt Sitzende.
- Hütten billiger/kleiner; Feuertempel deutlich größer & vieleckig; Tempel größer.
- Hütte bauen → je nach Regler wird sie (nicht/1/4-fach) besetzt; leere Hütte produziert
  nicht; Regler auf „Kein Wachstum" leert alle Hütten; Wachstums-Zahl plausibel;
  Mana/s-Zahl stimmt mit dem Ladefortschritt überein.
- Hohe Zauber (Vulkan/Erdbeben/Feuerregen) brauchen spürbar länger bis zur Ladung.
- Einheiten auf einem gesetzten Bauplan stehen lassen → sobald der Bau anläuft (erstes
  Holz verbaut), laufen sie vom Footprint weg; niemand bleibt im fertigen Gebäude
  stecken/unsichtbar.
- Hardcap: mit Zeitraffer bis 1500 wachsen → Produktion stoppt sauber.

## Definition of Done

- [x] Gesamte Testsuite grün (1481), `--headless --quit` fehlerfrei
- [ ] Manuelle Prüfung bestanden *(ausstehend — Nutzer)*
- [x] CLAUDE.md generell auf aktuellen Stand gebracht (neue 7i-Werte + Nachtrag 7b–7h: Zauberliste §6, Gebäude/Einheiten §4/§5); PROGRESS.md ergänzt
- [x] Checkbox 7i in [00_overview.md](00_overview.md) abgehakt
- [x] `git add -A && git commit -m "Phase 7i: Balancing, Karten & Wirtschaft" && git push`
