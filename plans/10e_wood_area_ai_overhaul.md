# Phase 10e — Holzfäll-Rechteck & KI-Überarbeitung

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

1. **Komfort-Kommando für den Spieler:** Mit selektierten Braves die Taste `B`
   drücken, dann mit gedrückter linker Maustaste ein Rechteck auf dem Boden
   aufziehen — **alle Bäume darin** werden von diesen Braves gefällt, in
   mehreren Fuhren. Danach gehen sie zum nächsten Holzablagepunkt oder eigenen
   Gebäude.
2. **KI-Überarbeitung.** Das Frühspiel ist in Ordnung, das Spätspiel nicht: die
   KI soll besser skalieren (bis ~1000 Bevölkerung möglich), **Holz auch von
   weit weg** holen (Hauptproblem), Basen sauberer bauen (keine blockierten
   Gebäude), **mehr Prediger** ausbilden, anfangs **etwas weniger aggressiv**
   sein, dafür stärker in Braves skalieren, und **häufiger Fahrzeuge** bauen.

**Abhängigkeit:** Die KI-Holzlogistik nutzt genau dasselbe
`order_chop_area`-Kommando wie der Spieler — Teil 1 muss vor Teil 2 stehen.
Ebenso wird der Sofort-Abriss aus [10d](10d_buildings_win_conditions_ui.md) für
die Selbstheilung bei unerreichbaren Bauplätzen gebraucht.

## Bestandsaufnahme (vor Umsetzung verifiziert)

- **Die KI erteilt heute überhaupt keine Sammelbefehle.** Holz kommt
  ausschließlich über `BuildingManager._recruit_workers` (30 m Radius um jede
  Baustelle, nur idle Braves) und `Brave.JOB_TREE_RADIUS 40`. Bauplätze
  brauchen zusätzlich ≥ 3 Bäume innerhalb `PLOT_TREE_RADIUS 22`.
- **Die KI hat kein `WoodDepot` im Bauprogramm** — `wood_depot.gd` wird von
  `ai_controller.gd` nirgends referenziert.
- **Fahrzeuglimits bleiben auf den Defaults:** `Tribe.max_catapults 3`,
  `max_fire_rams 3`, `max_airships 2` (tribe.gd:40-52) werden von der KI nie
  angehoben. Das ist der eigentliche Grund für „zu wenige Fahrzeuge" — nicht
  die Werkstattzahl.
- **Skalierungsbremsen:** `MAX_PARALLEL_SITES 3`, `BRAVES_PER_SITE 8`, eine
  Platzierung pro Tick, Ringsuche nur bis Radius 30 um **einen** Anker,
  `MIN_ECONOMY_BRAVES 8` (fix), `TRAIN_BATCH 3`, `ATTACK_WAVE_MAX 40`. Der
  Wohnraumdruck-Zweig in `_next_building_scene` (:328) steht **ganz am Ende**
  der Bauordnung.
- **Perf-Bremse:** `AIController` baut pro Tick ~8-mal eigene Listen aus
  `tribe.units` / `tribe.buildings` (idle Braves, Kind-Zählungen, Förstereien,
  Werkstätten, Türme, Luftschiffe, Lager, Baustellen). Bei 1000 Einheiten ist
  das der dominierende Kostenpunkt und blockiert das 1000-Bevölkerungs-Ziel.
- Armee-Mix heute 50/30/**20** (Krieger/Feuerkrieger/Prediger),
  `AIState.training_kind_order` (:78).
- `TreeManager.best_tree` (:375) hat bereits Inselprüfung, echte
  Pfadverifikation (`PATH_CANDIDATES 4`), Höhen-Umwegstrafe und Verdict-Caches
  — die Flächensuche muss das wiederverwenden, nicht neu bauen.
- `SelectionManager` hat die Drag-Box bereits vollständig (`_drag_rect` :261,
  `_box_select` :290, `_draw` :252, `DRAG_THRESHOLD_PX 6.0`, Out-and-back-Wächter,
  Freigabe-Sicherung im `_process`).
- **`B` ist belegt** (`select_all_huts`, physical keycode 66).
- Bestehende lose Hackaufträge: `Brave._tick_loose_chop` (:817),
  `_start_loose_deliver` (:847), `_loose_drop_target` (:928),
  `_nearest_own_building` (:940), `_next_loose_tree` (:1007,
  `CHOP_CHAIN_RADIUS 8.0`), `CARRY_CAPACITY 3`.

## Dokumentierte Auslegungen (Nutzer-Festlegungen)

- **`B` = Holzfäll-Rechteck**, **`Shift+B` = „alle Hütten auswählen"**.
- **Ein-Auftrag-Prinzip:** Der Flächenauftrag ist ein *stehender* Auftrag am
  Brave. Jeder andere Befehl (Bewegen, Bauen, Beten, Ausbilden …) bricht ihn
  ab — das ergibt sich automatisch, weil `Brave._interrupt_tasks()` das Feld
  löscht.
- **Bei Flächenaufträgen wird die Tragkapazität gefüllt** (`CARRY_CAPACITY 3`),
  bevor abgeliefert wird. Der bestehende Einzelbaum-Befehl behält seine
  Ein-Stück-pro-Fuhre-Logik — ein 50 m entfernter Hain wäre mit
  Einzelstücktransport unspielbar.
- **Das 1000-Bevölkerungs-Ziel muss nicht getestet werden** (Laufzeit), aber
  die Mechanik darf es nicht strukturell verhindern. Hinweis:
  `CLAUDE.md` §4 nennt 1500 Einheiten pro Stamm, `Balance.TRIBE_MAX_UNITS`
  steht auf 1000 — **dieser Widerspruch ist in diesem Plan zu klären**
  (Vorschlag: Code auf 1500 anheben oder CLAUDE.md auf 1000 korrigieren, nach
  Rückfrage beim Nutzer).

---

## Teil 1 — Holzfäll-Rechteck

| Bereich | Datei(en) | Inhalt |
|---|---|---|
| **Baumsuche** | `scripts/core/tree_manager.gd` | `claim_area_tree(area, poly, claimer, walker) -> TreeResource` — ruft **`best_tree`** mit Flächenmittelpunkt, Radius = halbe Flächendiagonale + 1 m und dem Flächenfilter als `filter`-Callable auf. Damit werden Inselprüfung, Pfadverifikation und Verdict-Caches unverändert mitgenutzt. Dazu `static point_in_area(p, area, poly) -> bool` (Rechteck-Grobfilter + optionales konvexes Viereck für gedrehte Kamera) |
| **Kommando** | `scripts/core/tribe_commands.gd` | `order_chop_area(units, area: Rect2, polygon := PackedVector2Array()) -> int` — setzt den stehenden Auftrag, ignoriert Nicht-Braves, prüft `HARVEST_AREA_MIN_SIDE` und klemmt auf `HARVEST_AREA_MAX_SIDE` um den Mittelpunkt (ein Ganzkarten-Zug darf keinen absurden Auftrag erzeugen), liefert die Zahl der beauftragten Braves |
| **Brave** | `scripts/units/brave.gd` | Felder `chop_area: Rect2`, `chop_area_poly: PackedVector2Array`; `has_chop_area()`, `order_chop_area(area, poly)` (erst `_interrupt_tasks()`, dann setzen — Reihenfolge ist wichtig), `_next_area_tree()`. `_next_loose_tree()` (:1007) verzweigt bei Flächenauftrag dorthin; `_tick_loose_chop()` (:817) füllt die Tragkapazität; `_tick_loose_deliver()` (:856) bevorzugt ein Depot innerhalb `HARVEST_DEPOT_PREFER_RADIUS`, sonst wie bisher `_nearest_own_building()`/`_loose_drop_target()`. Fläche leer + nichts getragen → `_stop_all()` |
| **UI** | `scripts/ui/selection_manager.gd` | `static harvest_arm_active`; Armieren nur mit selektierten Braves; Linksklick-Drag nutzt die bestehende Drag-Mechanik; bei Freigabe werden die 4 Rechteck-Ecken auf das Terrain geraycastet → Welt-Viereck (XZ) + Hülle; unterhalb der Drag-Schwelle wird nur entwaffnet (kein versehentlicher Riesenauftrag). Darstellung: grünes Fadenkreuz + „Holz fällen" am Cursor, grünes statt blaues Rechteck |
| **Input** | `project.godot` | Neue Action `harvest_area_arm` = Taste 66 ohne Modifier; `select_all_huts` auf Taste 66 **mit** `shift_pressed`. **Wichtig:** im `elif`-Zweig muss `select_all_huts` **vor** `harvest_area_arm` geprüft werden — eine Action ohne Modifier matcht in Godot auch einen Tastendruck mit Modifier. Rückfallebene, falls das im Spieltest zickt: `harvest_area_arm` auf eine freie Taste (C/X/N/M) legen |

### Neue Balance-Konstanten (Teil 1)

```gdscript
# --- Flächen-Holzernte (Taste B) ---
const HARVEST_AREA_MIN_SIDE: float = 2.0
const HARVEST_AREA_MAX_SIDE: float = 80.0
## Innerhalb dieses Radius wird ein Holzlager dem nächsten Gebäude vorgezogen.
const HARVEST_DEPOT_PREFER_RADIUS: float = 40.0
```

---

## Teil 2 — KI-Überarbeitung

### 2.0 Tick-Cache (Voraussetzung, zuerst umsetzen)

`AIController`: **ein** Durchlauf über `tribe.units`/`tribe.buildings` zu Beginn
von `tick_ai()` füllt einen Cache (`idle_braves`, `brave_count`, `kind_counts`,
`foresters`, `workshops`, `towers`, `airships`, `camps_by_kind`, `sites`,
`depots`). Alle Unterroutinen lesen daraus. Größter Einzelgewinn im Spätspiel
und Voraussetzung für alles Weitere. **Vorher/nachher messen.**

### 2.1 Schwellwerte & reine Funktionen (`scripts/ai/ai_state.gd`)

Geändert: `TARGET_HUTS 3 → 4`, `POP_FOR_TRAIN 12 → 16`,
`ARMY_ATTACK_SIZE 8 → 12` (später angreifen),
`ATTACK_WAVE_GROWTH 4 → 6`, `ATTACK_WAVE_MAX 40 → 120`,
Armee-Mix aus `Balance`: **40 / 30 / 30** (Prediger 0,20 → 0,30). Die
gleichzeitige Anhebung der Feuerkrieger ist beabsichtigt — sie sind der
eigentliche Konter gegen eine Prediger-Masse.

Neue **reine** Statics (headless ohne Welt testbar):
`min_economy_braves(population)`, `parallel_site_count(braves)`,
`wood_crew_count(braves)`, `vehicle_caps(braves)`,
`next_building_kind(counts) -> StringName` (die **komplette Bauordnung** als
reine Funktion; der Controller bildet die Kennung auf eine `PackedScene` ab —
damit ist die Bauordnung ohne Szeneninstanziierung testbar).

Neue Bauordnung (Auszug, gegenüber `_next_building_scene` :270):
1. erste Hütte → erstes Kriegerlager
2. **Holzlager an der Basis** (neu — die KI baute nie eines)
3. Försterei, wenn Holz knapp (Ziel skaliert mit Braves)
4. **vorgeschobenes Holzlager**, wenn der beste Hain weit weg ist (neu)
5. **Wohnraumdruck-Zweig hierher vorgezogen** (bisher ganz am Ende) — das
   allein schaltet die hohe Bevölkerung frei
6. Hütten bis `TARGET_HUTS`, dann Feuertempel → Tempel → Werkstätten →
   Wachtürme → Luftschiffwerft, jede Werkstattart mit einem an der
   Bravezahl skalierenden Ziel statt hartem „< 1"
7. Zusatzlager nach dem seltensten Typ (unverändert)

### 2.2 Holzlogistik (`scripts/ai/ai_controller.gd`) — der Hauptfix

Neues Subsystem `_tick_wood_logistics()`, gedrosselt auf jeden
`AI_WOOD_TICK_INTERVAL`-ten Tick:

- **Bedarf:** Summe über eigene Baustellen aus
  `wood_needed_total() - wood_incoming()` plus Werkstattbedarf; > 0 oder eine
  `wood_stalled`-Baustelle löst einen Trupp aus.
- **Hain finden:** neue `TreeManager.grove_candidates(from, max_results)` legt
  den vorhandenen 8-m-Bucket-Index offen; bewertet wird
  `Baumzahl / (1 + Luftlinie)` mit Inselfilter. Ergebnis ist ein `Rect2`, kein
  Einzelbaum. Cache `AI_WOOD_GROVE_TTL_TICKS`.
- **Trupps:** `AIState.wood_crew_count(braves)` Trupps à `AI_WOOD_CREW_SIZE`
  idle Braves, jeder per **`commands.order_chop_area(crew, grove_rect)`** — das
  Spieler-Kommando aus Teil 1. Trupps, deren Mitglieder idle werden (Fläche
  leer), bekommen einen neuen Hain.
- **Vorgeschobenes Lager:** liegt der Hain weiter als
  `AI_FORWARD_DEPOT_DISTANCE`, liefert die Bauordnung ein `WoodDepot` und
  `_find_plot` nimmt den Hain als Anker. Die Braves nutzen es danach
  automatisch (`_nearest_depot`), zwei idle Braves pendeln den Bestand per
  `order_depot_haul` heim.
- `_send_escort_if_remote` (:1135) feuert zusätzlich für **jede** eigene
  `wood_stalled`-Baustelle, mit dem Hain nächst **dieser** Baustelle.
- `_staff_foresters`: 2 → 4 Arbeiter je Försterei ab ~30 Braves.

### 2.3 Bauplatzsuche & Layout

- Ringbereich `AI_PLOT_MIN_RADIUS 3 .. AI_PLOT_SEARCH_RADIUS 40` statt 0..30 —
  Gebäude kleben nicht mehr am Anker und die Suche reicht weiter.
- `_plot_has_clearance(cell, footprint)`: der um `AI_PLOT_SPACING` vergrößerte
  Grundriss darf keine Gebäudezelle enthalten → beendet das Symptom
  „Gebäude blockiert/unerreichbar". Nur für Kandidaten geprüft, die
  `can_place_at` bereits bestanden haben.
- `_orientation_toward(cell, footprint, anchor)`: die KI platziert heute
  **immer** mit `orientation = 0`. Der Eingang zeigt künftig zur Basis — hält
  Türen und Wege frei.
- `_settlement_anchors()` (Cache `AI_SETTLEMENT_TTL_TICKS`): Basisanker +
  Hüttencluster-Zentren + vorgeschobene Lager. Für 25+ Hütten mit Abstand
  reicht ein einzelner Anker nicht.
- **Selbstheilung:** nach `place_building(...)` prüfen, ob die Anlaufstelle auf
  der Basisinsel liegt; sonst `commands.demolish_building(...)` — die frische
  Baustelle hat `build_progress == 0` und wird nach 10d **sofort** mit voller
  Erstattung abgerissen. Layoutfehler blockieren damit keinen Baustellen-Slot
  mehr dauerhaft.
- `max_sites = AIState.parallel_site_count(braves)` (bis 8 statt 3).

### 2.4 Armee, Fahrzeuge, Zauber

- `tick_ai()` setzt `tribe.max_catapults/max_fire_rams/max_airships` aus
  `AIState.vehicle_caps(braves)` (geklemmt auf die `MAX_*_LIMIT`-Konstanten).
  **Das ist zusammen mit den skalierenden Werkstattzahlen der eigentliche Fix
  für „zu selten Fahrzeuge".**
- `_tick_train`: `min_economy_braves(population)` statt fix 8;
  `TRAIN_BATCH = clamp(braves / 20, 3, 12)`.
- `_cast_spells`: neuer Vorrangzweig auf **feindliche Prediger** (Blitz, sonst
  Feuerball) direkt nach dem Schamanin-Zweig. Billig, weil `tribe.preachers`
  bereits als Liste gepflegt wird.

### Neue Balance-Konstanten (Teil 2)

```gdscript
# --- KI: Wirtschaft / Holzlogistik ---
const AI_MIN_ECONOMY_BRAVES: int = 8
const AI_ECONOMY_BRAVE_SHARE: float = 0.35
const AI_WOOD_CREW_SIZE: int = 6
const AI_BRAVES_PER_WOOD_CREW: int = 12
const AI_MAX_WOOD_CREWS: int = 4
const AI_WOOD_TICK_INTERVAL: int = 3
const AI_WOOD_GROVE_TTL_TICKS: int = 30
const AI_FORWARD_DEPOT_DISTANCE: float = 35.0
const AI_BRAVES_PER_FORESTER: int = 25
const AI_MAX_FORESTERS: int = 4

# --- KI: Bau / Skalierung ---
const AI_MAX_PARALLEL_SITES: int = 8
const AI_PLOT_MIN_RADIUS: int = 3
const AI_PLOT_SEARCH_RADIUS: int = 40
const AI_PLOT_SPACING: int = 2
const AI_MAX_PLOT_SCAN_CELLS: int = 1200
const AI_MAX_HUTS: int = 30
const AI_BRAVES_PER_WORKSHOP: int = 30
const AI_MAX_SHOPS_PER_KIND: int = 4
const AI_BRAVES_PER_VEHICLE_SLOT: int = 40
const AI_SETTLEMENT_TTL_TICKS: int = 60

# --- KI: Armee-Mix ---
const AI_ARMY_SHARE_WARRIOR: float = 0.40
const AI_ARMY_SHARE_FIREWARRIOR: float = 0.30
const AI_ARMY_SHARE_PREACHER: float = 0.30
```

## Umsetzungsschritte

1. Teil 1: `TreeManager.claim_area_tree` + `point_in_area` + Tests.
2. Teil 1: `TribeCommands.order_chop_area` + Brave-Flächenauftrag + Tests.
3. Teil 1: UI (Armieren, Rechteck, Raycast) + `project.godot` (`B`/`Shift+B`)
   → danach `--headless --quit`.
4. Teil 2.0: KI-Tick-Cache, **vorher/nachher messen**
   (`tests/benchmark_earlygame.gd`, `tests/benchmark_stress.gd`).
5. Teil 2.1: `ai_state.gd` — Schwellwerte + reine Funktionen + Tests
   (schnell, komplett headless).
6. Teil 2.2: Holzlogistik (braucht Schritt 2).
7. Teil 2.3: Bauplatzsuche/Layout (braucht den Sofort-Abriss aus 10d).
8. Teil 2.4: Armee/Fahrzeuge/Zauber.
9. Klärung `TRIBE_MAX_UNITS` 1000 vs. CLAUDE.md 1500, Doku, PROGRESS.md,
   Commit/Push.

## Tests

**Neu `tests/test_harvest_area.gd`:**
`test_order_chop_area_tasks_only_braves`,
`test_area_job_claims_only_trees_inside_the_rect`,
`test_area_job_ignores_trees_outside_a_rotated_quad`,
`test_area_job_fills_carry_capacity_before_delivering`,
`test_area_job_retargets_after_each_delivery`,
`test_area_job_delivers_to_nearest_own_building`,
`test_area_job_prefers_a_nearby_wood_depot`,
`test_area_job_ends_when_the_area_is_empty`,
`test_new_order_cancels_the_area_job`,
`test_oversized_area_is_clamped`,
`test_area_job_skips_trees_on_another_island`.

**Erweiterung `tests/test_ai.gd`** (reine Statics + Ein-Tick-Zusicherungen,
keine Langläufe):
`test_min_economy_braves_scales_with_population`,
`test_parallel_site_count_scales_with_braves`,
`test_army_mix_favours_preachers`,
`test_attack_wave_scales_to_late_game`,
`test_first_attack_comes_later`,
`test_vehicle_caps_scale_with_population`,
`test_build_order_places_wood_depot_after_first_camp`,
`test_build_order_prioritises_housing_under_pressure`,
`test_build_order_scales_workshops_with_braves`,
`test_ai_sends_wood_crew_to_remote_grove` (Welt, deren einzige Bäume 60 m
entfernt stehen → nach einem `tick_ai()` haben N Braves einen Flächenauftrag),
`test_ai_plot_keeps_spacing_between_buildings`,
`test_ai_plot_entrance_faces_the_base`,
`test_ai_discards_a_site_with_no_walkable_approach` (Sofort-Abriss greift),
`test_ai_prioritises_enemy_preachers_with_spells`,
`test_ai_tick_cache_walks_units_once_per_tick` (Zähler-basiert, sichert das
Skalierungsziel).

**Erweiterung `tests/test_ui_logic.gd`:**
`test_harvest_arm_requires_selected_braves`,
`test_harvest_arm_and_attack_arm_are_exclusive`.

## Manuelle Prüfung

- Braves selektieren, `B`, Rechteck über einen Hain ziehen → alle Bäume darin
  werden abgearbeitet, mehrere Fuhren, Ablage am nächsten Lager/Gebäude,
  danach stehen die Braves dort still.
- `Shift+B` wählt weiterhin alle Hütten.
- Ein Bewegungsbefehl bricht den Flächenauftrag sofort ab.
- Langes Skirmish gegen die KI: baut sie über 300 Bevölkerung hinaus weiter,
  holt sie sichtbar Holz von weit entfernten Hainen, stehen ihre Gebäude mit
  Abstand und freien Eingängen, kommen Katapulte/Feuerrammen in Wellen, und
  bringt eine Prediger-Masse sie **nicht** mehr trivial um?
- FPS im KI-Spätspiel (Tick-Cache muss sich auszahlen).

## Risiken

1. **Ohne den Tick-Cache** wird der 1-Hz-KI-Tick bei 1000 Einheiten zum
   sichtbaren Ruckler. Schritt 2.0 zwingend zuerst und messen.
2. **`best_tree` mit Flächenfilter** durchsucht alle Bäume (≤ 1000) pro
   Neuziel. Eine Neuzielsuche pro Brave und Fuhre (viele Sekunden) — gleiche
   Größenordnung wie heute. `TreeManager.dbg_best_tree_calls/_us` beobachten;
   bei Bedarf einen Bucket-Vorfilter in `claim_area_tree` ergänzen.
3. **Abstandsprüfung beim Bauplatz** kostet `(Grundriss+4)²` Lookups je
   gültigem Kandidaten. Gedeckelt durch `AI_MAX_PLOT_SCAN_CELLS` und den
   Fehlschlag-Cooldown; `dbg_plot_us` beobachten.
4. **`Shift+B`-Matching:** eine Action ohne Modifier matcht in Godot auch einen
   Tastendruck mit Modifier — die `elif`-Reihenfolge ist der Fix, sonst auf
   eine freie Taste ausweichen.
5. **Mehr Prediger auf beiden Seiten** verschiebt das Balancing spürbar
   (Bekehrungen, „Einheiten in Bekehrung sind kein gültiges Ziel"). Nach dem
   Spieltest ggf. `AI_ARMY_SHARE_*` nachziehen.
6. **8 parallele Baustellen** binden deutlich mehr Braves; ohne die neue
   Holzlogistik würde die KI dadurch **schlechter**. Reihenfolge einhalten.
7. **Doku-Widerspruch** `TRIBE_MAX_UNITS` 1000 vs. CLAUDE.md 1500 muss geklärt
   werden, sonst ist das 1000-Ziel formal unerreichbar bzw. falsch dokumentiert.

## Definition of Done

- [ ] Testsuite grün, `--headless --quit` fehlerfrei
- [ ] KI-Tick-Kosten vor/nach dem Cache in PROGRESS.md dokumentiert
- [ ] Manuelle Prüfung (langes Skirmish) durch den Nutzer bestanden
- [ ] `TRIBE_MAX_UNITS`-Widerspruch geklärt
- [ ] PROGRESS.md ergänzt, Checkbox 10e in [00_overview.md](00_overview.md) abgehakt
- [ ] Commit/Push
