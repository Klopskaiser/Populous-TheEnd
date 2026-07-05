# Umsetzungsstand (PROGRESS)

Fortschrittsdoku für neue Sitzungen: **was tatsächlich gebaut wurde**, inkl. Abweichungen
und Extras gegenüber den Phasenplänen — damit kein Code durchsucht werden muss.

**Pflegeregel:** Am Ende jeder Phase (vor Commit/Push) einen Abschnitt ergänzen mit:
Gebaut (Dateien + Kern-APIs), Extras/Abweichungen vom Phasenplan, Erkenntnisse/Stolpersteine,
Verifikationsstand. Auch bei nachträglichen Erweiterungen außerhalb einer Phase hier eintragen.

---

## Phase 1 — Projektgerüst, Terrain, Kamera (abgeschlossen, Commit `71e0073`)

**Gebaut:**
- `scripts/core/terrain_data.gd` — `TerrainData` (RefCounted, Single Source of Truth):
  128×128 Zellen / 129×129 Vertices à 1 m, `PackedFloat32Array heights` (public).
  API: `get_height(wx, wz)` (bilinear), `raise_area(center: Vector2, radius, amount) -> Rect2i`
  (Smoothstep-Falloff, gibt geänderte Zellen zurück), `is_walkable(cell)` (Seelinie 2.0 +
  max. Hangneigung 1.5), `generate_island(seed)` (FastNoiseLite + Radialmaske),
  `vertex_height/set_vertex_height`, `cell_height`, `in_bounds`.
- `scripts/core/terrain.gd` — `Terrain` (Node3D): chunked ArrayMesh (16×16-Zellen-Chunks,
  Vertex-Farben nach Höhe), **ein** StaticBody3D + `HeightMapShape3D` (um SIZE/2 versetzt,
  da origin-zentriert), Wasser-PlaneMesh. `build(data)`, `apply_deformation(rect)`
  (= `rebuild_chunks(rect)` + `update_collision()`).
- `scripts/core/camera_rig.gd` — `CameraRig`: WASD-Pan, Q/E-Rotation, Mausrad-Zoom
  (Boom 8–90 m), Edge-Scroll (headless-guarded), Y folgt Terrainhöhe.
- Autoloads: `GameState` (`terrain_data`, `terrain`, `ISLAND_SEED = 1337`) und `Events`
  (Signal-Bus: `unit_died`, `building_destroyed`, `wood_changed`, `mana_changed`).
- Testrunner: `tests/run_tests.gd` (SceneTree, lädt `test_*.gd`, ruft `test_*`-Methoden per
  Reflection), `tests/test_base.gd` (`TestBase` mit `check`/`check_near`), `tests/test_terrain.gd`.
- `scenes/main.tscn` + `scripts/core/main.gd`: baut Terrain, positioniert Kamera;
  Debug-Klickmarker (`debug_click_marker`, seit Phase 2 default `false`).

**Erkenntnisse:**
- `HeightMapShape3D` ist origin-zentriert → Body-Offset nötig (per Klickmarker verifiziert).
- Godot-Exe liegt verschachtelt: der Eintrag `…win64.exe` im Downloads-Ordner ist ein
  **Ordner**, die Exe liegt gleichnamig darin (siehe CLAUDE.md §2).

**Verifikation:** Testsuite grün, `--headless --quit` fehlerfrei, manuelle Prüfung bestanden.

---

## Phase 2 — Pathfinding, Unit-Basis, Selektion & Bewegung (abgeschlossen, Commits `8eb8f1e` + `70c2bbf`)

**Gebaut:**
- `scripts/core/nav_grid.gd` — `NavGrid` (RefCounted) um `AStarGrid2D`
  (`DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES`): `find_path(from: Vector3, to: Vector3)
  -> PackedVector3Array` (Y aus TerrainData; unbegehbares Ziel → Ring-Suche zur nächsten
  begehbaren Zelle, max. Radius 32; unerreichbar → leeres Array; letzter Punkt = exakter
  Klickpunkt, wenn Zielzelle begehbar), `update_region(rect)` (nach `raise_area`),
  `fill_solid_region(rect, solid)` (Gebäude-Footprints, überleben `update_region`),
  `world_to_cell`/`cell_to_world`, `is_cell_walkable`, `nearest_walkable_cell`.
- `scripts/units/unit.gd` — `Unit` (Node3D, **ohne Physik**): kompletter `State`-Enum
  (IDLE…DEAD), `tick(delta)`-Bewegung (`move_toward` auf XZ + Y-Snapping; von
  `_physics_process` aufgerufen), Wegpunkt-Queue (`order_move(target, queue_up)`;
  `patrol = true` rotiert die Queue, Länge bleibt konstant), `set_path`,
  `get_remaining_path()`, `take_damage` (Gerüst), Signale `died`/`state_changed`,
  Selektionsring (Torus, `no_depth_test`) via `set_selected(bool)`, Stammfarbe via
  `modulate` (`TRIBE_COLORS`, 0 = Blau/Spieler, 1 = Rot/KI).
  **Wichtig:** Logik nutzt `position` (nicht `global_position`), damit sie außerhalb des
  Szenenbaums testbar ist; Units sind direkte Kinder des UnitManager am Ursprung.
- `scripts/units/brave.gd` + `scenes/units/brave.tscn` — `Brave` (60 HP, Speed 4);
  Verhalten GATHER/PRAY/BUILD folgt in Phase 3.
- `scripts/core/unit_manager.gd` — `UnitManager` (Node, Kind von Main): Registry +
  Spatial-Hash (4-m-Zellen, Update im `tick`), `spawn_unit(scene, tribe_id, pos)`,
  `get_units_in_radius`, `get_units_of_tribe`, `register/unregister`; re-emittiert
  `died` → `Events.unit_died`.
- `scripts/ui/selection_manager.gd` — `SelectionManager` (Control auf CanvasLayer `UI`):
  Klick-/Box-Selektion screen-space (`unproject_position` + `is_position_behind`-Guard),
  Drag-Rechteck in `_draw()`, Rechtsklick = Bewegung per Terrain-Raycast mit
  Formations-Streuung (Ringe à 6/12/18), Shift+Rechtsklick = Wegpunkt anhängen,
  Taste **P** = Patrouille togglen (Input-Action `toggle_patrol`).
- `scripts/core/main.gd`: erzeugt NavGrid (`GameState.nav_grid`), spawnt 10 Braves
  (Tribe 0) spiralförmig um die Inselmitte auf begehbaren Zellen.
- Tests: `tests/test_nav_grid.gd` (inkl. Landbridge: Tal-Terrain, `raise_area` +
  `update_region` öffnet Pfad) und `tests/test_unit_logic.gd`.

**Extras (nicht im Phasenplan, nachträglich gewünscht):**
- `scripts/ui/route_visualizer.gd` — `RouteVisualizer` (Node3D in main.tscn): zeichnet für
  **selektierte** Einheiten dünne terrainfolgende Linien (ImmediateMesh, 1-m-Sampling,
  `no_depth_test`) entlang Restpfad + Wegpunkten und kleine Kugel-Marker (MultiMesh, max.
  256) pro Wegpunkt; gilt auch für einfache Rechtsklick-Ziele; Patrouillen-Schleife wird
  geschlossen. Aufbau komplett pro Frame aus `selection.selected`.
- **4-Richtungs-Sprites:** Jede Animation existiert als `<anim>_<view>` mit view in
  `front/back/left/right` (z. B. `walk_back`). `Unit` trackt `facing` (Laufrichtung,
  bleibt beim Stehen erhalten); die Ansicht wird pro Frame aus `facing` relativ zur Kamera
  gewählt (statisch/testbar: `Unit.view_suffix(facing, cam_forward, cam_right)`, 45°-Grenze
  bevorzugt front/back). Ansichtswechsel übernimmt den Frame-Fortschritt (kein Neustart);
  Fallback-Kette: `<anim>_<view>` → `<anim>_front` → `<anim>` → `idle_front`.
  **Echte Sprites später:** einfach SpriteFrames mit denselben Animationsnamen liefern.
  Platzhalter: Front = 2 Augen, Rücken = Haaransatz, Seite = 1 Auge (links = gespiegelt);
  `cast_*` nur für `shaman`/`preacher` (`PlaceholderSprites.CASTER_KINDS`).

**Erkenntnisse/Stolpersteine:**
- `--check-only` kennt **keine Autoloads**: Skripte, die `GameState`/`Events` referenzieren
  (z. B. `main.gd`), melden fälschlich „Identifier not found" — kein echter Fehler, der
  Projekt-Ladecheck (`--headless --quit`) ist maßgeblich.
- GDScript-Präzedenz: `a == [1,2] as Array[int]` parst als `(a == [1,2]) as Array[int]`
  → Klammern setzen.
- PowerShell: `& $GODOT …; $LASTEXITCODE` liefert bei dieser Exe keinen Exit-Code —
  `Start-Process -Wait -PassThru` und `$p.ExitCode` verwenden.
- Neue `.gd`/`.tscn` erst nach `--headless --import` referenzierbar (`.uid`-Erzeugung);
  `.uid`-Dateien werden mit committet.

**Verifikation:** Testsuite grün (68 Tests), `--headless --quit` fehlerfrei, manuelle
Prüfung durch Nutzer bestanden (Selektion, Bewegung, Wegpunkte/Patrouille, Routen-Anzeige,
Richtungs-Sprites).

---

## Phase 3 — Gebäude, Wirtschaft, HUD (umgesetzt)

**Gebaut:**
- `scripts/core/tribe.gd` — `Tribe` (RefCounted): `id`, `color`, `wood`, `mana`,
  `units`/`buildings` (typisierte Arrays), `shaman` (Phase 5). Abgeleitet als **Methoden**:
  `population()`, `housing_capacity()` (Summe `Building.housing_capacity()`),
  `praying_braves()` (zählt `Unit.is_praying()`). `tick(delta)`:
  `mana += (pop * MANA_BASE_RATE(0.1) + betende * MANA_PRAY_BONUS(0.5)) * delta`.
  Eigene Mutations-API: `add_wood`, `spend_wood` (false ohne Seiteneffekt),
  `add/remove_unit`, `add/remove_building`, `notify_housing_changed`. Events-Bus-Lookup
  über `Engine.get_main_loop()` mit Guard (headless-Tests ohne Autoloads laufen).
- `scripts/core/tribe_commands.gd` — `TribeCommands` (Node, einzige Mutations-API):
  `place_building(tribe, scene, cell) -> Building` (Probe-Instanz für Kosten/Footprint,
  `can_place_at` + `spend_wood`, ungültig → `null` ohne Seiteneffekt),
  `can_place_at(cell, footprint)` (Walkability + baumfrei), `order_move` (mit
  Formations-Streuung, von SelectionManager hierher gezogen), `order_gather/build/pray`
  (Braves → Task, andere Einheiten → Move). `formation_offset()` jetzt statisch hier.
- `scripts/buildings/building.gd` — `Building` (Node3D-Basis): `tribe_id/tribe`, HP,
  `wood_cost`, `footprint`, `cell` (Footprint-Top-Left), `rally_point`,
  `under_construction`/`build_progress`, `add_build_progress()` → `finish_construction()`
  (Signal `construction_finished`, Kapazität wird erst danach wirksam), `take_damage`/
  `destroy()` (NavGrid-Footprint freigeben, `Events.building_destroyed`),
  `tick(delta)` → `_tick_active()` für Subklassen, `center_world()`, `interact_range()`,
  `edge_spawn_position()` (begehbare Perimeterzelle), Klick-Body (StaticBody3D,
  **Layer 2**, Meta `"building"`), Baustellen-Visual = Y-gestauchtes `MeshRoot`.
- `scripts/buildings/hut.gd` + `scenes/buildings/hut.tscn` — `Hut`: Kosten 20 Holz,
  Footprint 2×2, `CAPACITY = 100`, `SPAWN_INTERVAL = 10 s`; Spawn-Timer läuft nur bei
  freier Kapazität, neuer Brave läuft zum `rally_point` (Default: begehbare Zelle südlich,
  von BuildingManager gesetzt). Brauner PrismMesh + Stammfarben-Fahne.
- `scripts/buildings/reincarnation_site.gd` + Szene — `ReincarnationSite`: kostenlos,
  3×3, `PRAY_RADIUS = 5`; in Phase 3 nur Gebetsplatz (Respawn folgt Phase 5).
  Flacher Torus-Ring + Stein + Fahne.
- `scripts/core/tree_resource.gd` + `scenes/tree_resource.tscn` — `TreeResource`:
  `wood_remaining` (40), `harvest(amount) -> int` (nie mehr als vorhanden, einmaliges
  Signal `depleted`), Klick-Body **Layer 3** (Wert 4), Meta `"tree_resource"`.
  Bäume blockieren das NavGrid **nicht** (bewusst: dünne Hindernisse).
- `scripts/core/tree_manager.gd` — `TreeManager` (Node): Registry + Zellindex,
  `spawn_trees(count, seed)` (deterministisch, Mindestabstand 2 Zellen, nur begehbare
  Zellen), `nearest_tree(pos)`, `has_tree_at(cell)` (blockt Bauplätze); `depleted` →
  deregistrieren + `queue_free` (nur wenn im Baum; Standalone-Testknoten bleiben beim
  Ersteller).
- `scripts/core/building_manager.gd` — `BuildingManager` (Node): Registry, tickt alle
  Gebäude aus `_physics_process`, `place(scene, tribe, cell, pre_built)` (Injektion,
  Position/Y aus Terrain, `fill_solid_region`, Default-Rally); Validierung liegt bewusst
  in TribeCommands.
- `scripts/units/brave.gd` — GATHER (Baum suchen → hinlaufen → hacken 2 Holz/s →
  Tribe gutschreiben → nächster Baum, keiner mehr → IDLE), BUILD (`BUILD_RATE = 0.2`/s,
  bei Fertigstellung sofort IDLE), PRAY (`is_praying()` = angekommen; Tribe-Tick zählt).
  Gemeinsamer `_seek(target, range, delta)`-Helfer (Replan bei Zielwechsel, unerreichbar
  → IDLE), `_working`-Subzustand steuert Animation (`attack` beim Hacken/Bauen).
- `scripts/units/unit.gd` (erweitert): `tribe`-Referenz, `is_praying()` (Basis false),
  Bewegung refaktoriert in `_advance_path(delta) -> bool` + `_plan_path_to(target)`
  (State-frei, von Brave-Tasks mitbenutzt), `_anim_base()` als überschreibbarer Hook.
- `scripts/core/game_state.gd`: `tribes: Array[Tribe]` (0 = Spieler/Blau, 1 = KI/Rot,
  von Main erzeugt), tickt Tribes in `_process`, `get_tribe(id)`.
- `scripts/core/unit_manager.gd`: `setup(td, nav, tribes, tree_manager)` (optionale
  Parameter, alte Testaufrufe kompatibel); `spawn_unit` injiziert `tribe` +
  `tree_manager` (via `set()`, nur Braves haben das Property) und registriert beim Tribe;
  Tod → `tribe.remove_unit`.
- `scripts/ui/selection_manager.gd`: Rechtsklick-Routing über Collider-Metas — Baum →
  `order_gather`, eigene Baustelle → `order_build`, eigener Reinkarnationsplatz →
  `order_pray`, sonst `order_move` über TribeCommands; ignoriert Maus komplett, solange
  `BuildMenu.is_active()`.
- `scripts/ui/build_menu.gd` — `BuildMenu` (Control, UI-Layer): Button „Hütte (20 Holz)
  [H]“ + Input-Action `build_hut` (H, in project.godot); Ghost-BoxMesh folgt
  Terrain-Raycast (**Maske 1** = nur Terrain), Footprint auf Zelle gerastert,
  grün/rot je `can_place_at` + Holz; Linksklick platziert via
  `TribeCommands.place_building`, Esc/Rechtsklick bricht ab; Events als handled markiert.
- `scenes/ui/hud.tscn` + `scripts/ui/hud.gd` — `Hud`: „Holz/Mana/Bevölkerung x/y“
  oben links, rein signalgetrieben (`wood_changed`, `mana_changed`, **neu:**
  `population_changed(tribe_id, population, capacity)` in `events.gd`); Startwerte via
  `setup(tribe)`.
- `scripts/core/main.gd`: erzeugt 2 Tribes (Startholz je 100), verdrahtet alle Manager,
  verteilt 60 Bäume (Seed 1337), platziert den Spieler-Reinkarnationsplatz vorgebaut
  nahe der Inselmitte, spawnt danach die 10 Start-Braves.
- Tests: `tests/test_economy.gd` (41 Checks: Mana-Formel, Harvest, Gather-Zyklus inkl.
  Baum-Abmeldung, Hütten-Spawn bis Kapazität + Erweiterung, place_building-Validierung
  auf echter Insel, Baufortschritt durch Brave inkl. „vorher kein Spawn“).

**Extras/Abweichungen vom Plan:**
- Kollisionslayer-Konvention: Terrain = 1, Gebäude = 2, Bäume = 4 (Bit 3);
  Klickziel-Auflösung über Node-Metas (`"building"`, `"tree_resource"`).
- Bäume blockieren das NavGrid nicht (Plan ließ das offen: „falls blockiert“).
- Kein Holz-Tragen/Abliefern: Hacken schreibt direkt dem Tribe gut (wie geplant).

**Erkenntnisse/Stolpersteine:**
- Zirkuläre `class_name`-Referenzen (Unit ↔ Tribe ↔ Building) sind in Godot 4.7
  problemlos (Ladecheck grün).
- RefCounted-Klassen erreichen den Events-Bus über `Engine.get_main_loop()` →
  `root.get_node_or_null("Events")` — mit Guard laufen dieselben Klassen headless im
  Testrunner (dort keine Autoloads).
- Zustandswechsel am Tick-Ende beachten: Test „Brave IDLE nach Bauende“ schlug fehl,
  weil der Wechsel erst im Folge-Tick kam → Abschluss jetzt im selben Tick.
- `_unhandled_input`-Reihenfolge (BuildMenu nach SelectionManager im Baum → wird zuerst
  bedient) reicht nicht als Schutz allein; SelectionManager prüft zusätzlich explizit
  `BuildMenu.is_active()`.

**Verifikation:** Testsuite grün (109 Tests), `--headless --quit` fehlerfrei.
Manuelle Prüfung durch Nutzer bestanden („grundsätzlich klappt es“); danach folgte
der Wirtschafts-Umbau unten.

---

## Phase 3b — Original-nähere Wirtschaft (Umbau auf Nutzerwunsch)

**Kernänderungen gegenüber Phase 3:**
- **Kein Holz-Lager mehr.** `Tribe.wood`/`add_wood`/`spend_wood` und
  `Events.wood_changed` sind **entfernt**. Holz existiert nur physisch:
  `WoodPile` (`scripts/core/wood_pile.gd` + `scenes/wood_pile.tscn`, max. **5**
  Holz je Stapel, Klötzchen-Visual) verwaltet vom `WoodPileManager`
  (`scripts/core/wood_pile_manager.gd`: `deposit` (verschmilzt in Stapel im
  2,5-m-Radius), `take_from_radius`, `take_from_pile`, `nearest_pile` (mit
  Ausschlusszone), `wood_in_radius`, `total_wood`; leere Stapel verschwinden).
  HUD-„Holz“ = `Events.stockpile_changed(total)` (Summe aller Stapel).
- **Bäume wachsen:** `TreeResource` hat 4 Stufen (klein → mittelklein →
  mittelgroß → groß, Skalierung als Visual), Ertrag **1/1/2/3**, Fällzeit
  1,5–3 s. Gefällt wird der ganze Baum (`TreeManager.fell_tree` → Ertrag,
  `felled_flag` gegen Doppel-Fällen). Wachstum (`GROWTH_TIME` 75 s/Stufe) und
  **Vermehrung** tickt der TreeManager: alle 5 s Stichprobe, Spross-Chance
  superlinear zur Nachbarzahl (`0.004 * n^1.5`, Radius 8 Zellen); Anti-Wuchern
  über Dichtelimit (max. 6 Nachbarn), globalen Deckel (250) und Mindestabstand.
  Sprösslinge starten immer klein; nur Startbäume (Seed) sind zufällig groß.
- **Holz wird nur für Bauaufträge gesammelt.** Kein Sammel-Dauerzustand mehr;
  Rechtsklick auf Baum = `order_chop`: fällen, Holz als Stapel **vor Ort**
  ablegen, benachbarte Bäume (8 m) weiterfällen, dann IDLE.
- **Gebäude größer + Bauablauf in 2 Phasen** (`Building` stark umgebaut):
  Hütte jetzt **4×4** (Box + Prismendach + **Tür**), `orientation` 0–3 =
  Eingangsseite (S/E/N/W; MeshRoot wird rotiert, `entrance_cell()` außen
  mittig). Platzierung: **kein Holz nötig**, aber Höhenspanne der
  Footprint-Vertices ≤ `MAX_LEVEL_DIFF` (3 m, TribeCommands), Land + gebäude-/
  baumfrei. Ghost zeigt **Eingangs-Marker**, Taste **R** rotiert
  (Input-Action `rotate_building`).
  - **Phase 1 Fundament:** Arbeiter planieren Zellen auf die
    Durchschnittshöhe (`work_flatten`, 1 m/s je Arbeiter, parallele Zellen,
    Mehrfachbelegung möglich; Sprite **hüpft** via `Unit.hop_visual`).
    Terrain-/Nav-Updates gebatcht (0,25 s), Mesh über neues Signal
    `Events.terrain_deformed(rect)` → `Terrain.apply_deformation` (Main).
    Gleichzeitig fällen freie Arbeiter Bäume (Suchradius 30 m um die
    Baustelle) und stapeln das Holz am **Eingang**.
  - **Phase 2 Bau:** Stapel im 5-m-Radius des Eingangs werden automatisch
    absorbiert (`wood_delivered`); `build_progress` ist **gedeckelt auf
    wood_delivered/wood_cost** — fertig nur mit vollem Holz. Gebäude „wächst
    aus dem Boden“ (Y-Skalierung). Bei Fertigstellung `position.y` auf
    Planierhöhe.
- **Selbstorganisierte Bautrupps:** Braves wählen ihre Teilaufgabe selbst
  (`Brave.Task`: FLATTEN → CHOP/PICKUP (ferne Stapel holen, Tragekapazität 3)
  → DELIVER → CONSTRUCT; getragenes Holz wird bei Unterbrechung als Stapel
  fallen gelassen). Baum-Claims über `TreeManager.claim_nearest_tree`,
  Zell-Claims im Building. **Max. 10 Arbeiter je Baustelle**
  (`Building.MAX_WORKERS`, `join/leave`). Der `BuildingManager` **rekrutiert
  jede Sekunde untätige (IDLE) Braves** im 30-m-Radius — Einheiten mit
  Befehlen/Aufgaben werden nie eingezogen.
- **Bugfix aus Nutzertest:** „Hackanimation läuft weiter, Baum weg“ +
  `Invalid type in function '_tree_valid' … previously freed`: Baum-Referenzen
  (`task_tree`/`task_pile`) sind jetzt **untypisiert** (`Object`), `_tree_valid`
  nimmt `Object` und prüft `is_instance_valid` + `felled_flag`; Task-System
  beendet Teilaufgaben sauber (`_end_subtask`/`_interrupt_tasks`).

**Neue/geänderte Dateien:** `wood_pile.gd`, `wood_pile_manager.gd`,
`scenes/wood_pile.tscn` (neu); `tree_resource.gd`, `tree_manager.gd`,
`building.gd`, `brave.gd`, `tribe_commands.gd`, `building_manager.gd`,
`hut.gd`, `build_menu.gd` (weitgehend neu); `tribe.gd`, `events.gd`,
`nav_grid.gd` (`is_cell_blocked_by_building`), `unit.gd` (`hop_visual`,
`_advance_path`-Nutzung), `unit_manager.gd`, `selection_manager.gd`, `hud.gd`,
`main.gd`, `main.tscn`, `project.godot` (Action `rotate_building` = R).

**Erkenntnisse:**
- Referenzen auf Objekte, die andere Systeme freigeben können, **untypisiert**
  halten: Die Übergabe einer freigegebenen Instanz an einen **typisierten**
  Parameter wirft einen Script-Error (`is not a subclass of the expected
  argument class`) — `is_instance_valid` muss vor jeder typisierten Verwendung
  laufen.
- Footprint-Zellen sind nav-solid → Arbeiter erreichen innere Planier-Zellen
  über einen Direktlauf-Fallback im `_seek` (Pfadende nahe Ziel → letztes
  Stück gerade laufen).
- `const` ist in GDScript nur auf Klassenebene erlaubt (nicht im
  Funktionskörper).

**Verifikation:** Testsuite grün (**132 Tests**, `test_economy.gd` komplett neu:
Wachstum/Ertrag, Vermehrung inkl. Deckel, Stapel-Mechanik, Platzierungs-
validierung inkl. Unebenheits-Limit + Orientierung, kompletter Bau-Flow
Planieren→Fällen→Liefern→Bauen, Baustopp ohne Holz + Fortsetzung nach
Lieferung, Hütten-Spawn, Rekrutierung nur IDLE, manuelles Kettenfällen),
`--headless --quit` fehlerfrei. Manuelle Prüfung durch Nutzer bestanden
(„funktioniert gut“); danach Feinschliff-Runde unten.

---

## Phase 3c — Feinschliff-Runde (Nutzerfeedback)

**Änderungen:**
- **Holzstapel als Sprite:** `WoodPile`-Visual ist jetzt ein gebillboardetes
  `Sprite3D` mit prozeduraler 16×16-Pixel-Art (ein Klotz-Log je Holzeinheit,
  bei Mengenänderung neu generiert) statt 3D-Boxen — gleiche Optik-Schiene
  wie die Einheiten-Sprites.
- **Planieren dauert doppelt so lange:** `Brave.FLATTEN_RATE` 1.0 → **0.5** m/s
  (mehr Hopser pro Zelle).
- **Hüttenpreis:** `Hut.WOOD_COST` 20 → **15** (Button-Text folgt der Konstante).
- **Einheiten-Separation (kein Voll-Overlap):** `UnitManager.tick` schiebt
  Einheiten unter `SEPARATION_RADIUS` (0,55 m) weich auseinander
  (max. 1,6 m/s, Spatial-Hash-Abfrage, deterministische Richtung bei exakter
  Überlappung, Zielzelle muss begehbar bleiben, Y neu gesnappt). `DEAD` und
  `THROWN` (Würfe ab Phase 5 — dort ist Overlap erlaubt) sind ausgenommen.
  Zusätzlich streuen Hütten-Spawns Position + Rally-Ziel deterministisch
  (`_spawn_counter` + `formation_offset`).
- **Holz wird einzeln geerntet:** `TreeResource.harvest_one()` nimmt genau
  1 Holz und stuft den Baum **eine Wachstumsphase herab** (groß → mittelgroß
  → mittelklein → weg); ein großer Baum braucht drei Ernten. Restholz je
  Stufe = 1/1/2/3 (`wood_yield()`); `TreeManager.fell_tree` wurde durch
  `harvest_tree` ersetzt (entfernt den Baum erst bei der letzten Einheit).
  Herabgestufte Bäume wachsen über den Growth-Timer wieder nach.
- **Parallele Ernte:** Bäume haben Ernte-Slots = Restholz (max. **3** am
  großen Baum): `claimers`-Array + `can_claim/add_claimer/remove_claimer`,
  `claim_nearest_tree` vergibt Slots. Arbeiter hacken denselben Baum weiter,
  bis Tragekapazität (3) voll, Baum weg oder genug Holz unterwegs ist; beim
  manuellen Fällen wird jede Einheit sofort als Stapel abgelegt.

**Erkenntnis (wichtig):** Auch ein **`Object`-typisierter** Parameter wirft bei
freigegebenen Instanzen denselben Script-Error wie spezifischere Typen —
Prüf-Funktionen wie `_tree_valid` müssen ihren Parameter **komplett untypisiert**
lassen (Variant) und zuerst `is_instance_valid` prüfen.

**Verifikation:** Testsuite grün (**149 Tests**; neu: Ernte-Herabstufung,
parallele Ernte-Slots inkl. Freigabe, Separation-Test in `test_unit_logic.gd`),
`--headless --quit` fehlerfrei. Manuelle Prüfung durch Nutzer bestanden
(„das klappt gut“); danach Feinschliff-Runde 2 unten.

---

## Phase 3d — Feinschliff-Runde 2 (Nutzerfeedback)

**Änderungen:**
- **Baustellen-Stillstand bei Holzmangel:** Holz-Suchradius um die Baustelle
  30 → **40 m** (`Brave.JOB_TREE_RADIUS`). Findet ein Arbeiter weder Baum noch
  Stapel und der Baufortschritt steht am Holz-Deckel, ruft er
  `Building.mark_wood_stalled()` auf und **bricht ab** (IDLE). Gestallte
  Baustellen werden vom Rekrutieren übersprungen; nach
  `WOOD_RECHECK_INTERVAL` (**30 s**) wird der Stillstand aufgehoben und
  Arbeiter versuchen es erneut. Trifft vorher Holz am Eingang ein
  (`_absorb_piles` > 0), endet der Stillstand sofort. Neue Helfer:
  `Building.progress_cap()`.
- **Manuelles Fällen liefert ab:** Lose fällende Braves sammeln bis
  Tragekapazität (3) bzw. bis der Baum weg ist und tragen das Holz zum
  **nächstgelegenen eigenen Gebäude** (Stapel am Eingang), kehren dann zur
  Fällstelle zurück (`_loose_return_pos`) und machen weiter. Ohne eigenes
  Gebäude fällt das Holz wie bisher vor Ort. GATHER nutzt jetzt die Tasks
  CHOP/DELIVER.
- **Eingangsfeld wird mitplaniert:** `init_construction()` nimmt die
  `entrance_cell()` in die Planier-Liste auf — der Eingang liegt bündig.
- **Sprung-Animation beim Planieren:** neue Placeholder-Animation `jump`
  (Frame 0 = Arme unten/gelandet, Frame 1 = **Arme hochgerissen**/in der
  Luft, Beine angezogen). Kein Animations-Timer: `Unit._update_hop()` pausiert
  die Animation und wählt den Frame aus der Hop-Phase (Offset > 0,12 m =
  Luft). `Brave._anim_base()` liefert beim Planieren `jump` statt `attack`.

**Verifikation:** Testsuite grün (**159 Tests**; neu/angepasst: Stillstand +
Abbruch + kein Rekrutieren + Fortsetzung nach Holzlieferung, 30-s-Recheck-
Timer, Lieferung zum nächsten Gebäude beim manuellen Fällen, Eingang-Vertices
auf Planierhöhe), `--headless --quit` fehlerfrei. Manuelle Prüfung durch
Nutzer bestanden; danach Performance-Runde unten.

---

## Phase 3e — Performance für Massen (Ziel: 4000 Einheiten, 4 Spieler × 1000)

**Anlass:** Bei ~500 Einheiten stockte die Selektion, Bewegungsbefehle warfen
`MAX_MESH_SURFACES`-Fehler (RouteVisualizer: 1 ImmediateMesh-Surface **pro
selektierter Einheit**, Limit 256) und alles wurde langsam.

**Optimierungen:**
- **RouteVisualizer:** max. **24** Routenlinien (erste N der Selektion, Einheiten
  ohne Route zählen nicht), Rebuild nur alle **0,1 s** statt jeden Frame →
  Surface-Fehler weg.
- **Selektionsringe als ein MultiMesh:** neuer `SelectionRingRenderer`
  (`scripts/ui/selection_ring_renderer.gd`, Node in main.tscn, max. 1024
  Ringe). Vorher erzeugte jede Einheit beim ersten Selektieren einen eigenen
  Torus-MeshInstance → Stocken bei Box-Select von Hunderten.
  `Unit.set_selected` setzt nur noch ein Flag.
- **Pfad-Queue:** `Unit.order_move` rechnet in-game **nicht mehr synchron**
  (500 Befehle = 500 A* in einem Frame), sondern meldet sich beim UnitManager
  (`path_service`, `request_path`); der löst **48 Pfade pro Tick** auf
  (`_resolve_pending_path`, Einheit wartet in MOVE mit leerem Pfad).
  Tests ohne `path_service` behalten das synchrone Verhalten.
- **Zentrale Ticks statt Node-Callbacks:** `Unit` hat kein
  `_physics_process`/`_process` mehr; der UnitManager tickt alle Einheiten in
  einer Schleife und aktualisiert die Sprite-Ansicht/Hüpfen in **3 Slices**
  pro Frame mit **einmal pro Frame** geholter Kamera (`Unit.update_visual`).
- **SpriteFrames-Cache:** `PlaceholderSprites.make_frames` cacht pro Kind —
  vorher baute **jeder** Spawn alle Animationsbilder neu (Spawn-Hitches).
- **Separation skaliert:** Budget **600 Einheiten/Tick** (Round-Robin-Slices,
  Push-Delta skaliert) und max. **20 Nachbar-Kandidaten pro Einheit** —
  vorher explodierte der Tick, wenn Tausende in einem Hash-Bucket standen
  (gemessen: **190 ms → 9 ms**). Hash-Zelle liegt jetzt als Feld auf der Unit
  (`_hash_cell`) statt im Dictionary; Hash-Update inline im Manager-Tick.
- **Physik-Tickrate 30 Hz** (project.godot `physics_ticks_per_second=30`) —
  für ein RTS ausreichend, verdoppelt das Budget pro Tick auf ~33 ms.
- **Stresstest-Szenario:** 4 Tribes (Maximalausbau); Taste **F9** spawnt
  **250 Braves je Tribe** (= +1000), gestaffelt mit 40 Spawns/Frame über die
  Inselquadranten; Fortschritt/Gesamtzahl auf der Konsole. Input-Action
  `stress_test` (F9).
- **Benchmark-Werkzeug:** `tests/benchmark_units.gd` (kein test_-Präfix, läuft
  nicht in der Suite): 4000 Einheiten, Massen-Move auf einen Punkt, 600 Ticks,
  Phasen-Timing. Aufruf:
  `& $GODOT --path … --headless -s res://tests/benchmark_units.gd`

**Messwerte (Worst-Case: alle 4000 gleichzeitig auf EINEN Punkt):**
vorher Ø **215 ms**/Tick (Separation 190 ms), nachher Ø **23,7 ms**/Tick
(move 9,0 | hash 5,0 | paths 0,6 | separation 9,2), Spitze 64 ms — unter dem
33-ms-Budget; im normalen Spiel bewegt sich nur ein Bruchteil gleichzeitig.

**Offen/bekannt (Phase 7):** 4000 `AnimatedSprite3D` sind weiterhin je ein
Draw Call — falls die GPU-Seite beim Nutzer limitiert, wäre der nächste
Schritt ein MultiMesh-basiertes Einheiten-Rendering.

**Verifikation:** Testsuite grün (**163 Tests**; neu: Pfad-Queue-Verteilung
über Ticks), `--headless --quit` fehlerfrei, Benchmark unter Budget.
Manuelle Prüfung durch Nutzer: keine Fehler mehr, Performance aber weiterhin
unbefriedigend → Rendering-Umbau in Phase 3f unten.

---

## Phase 3f — MultiMesh-Rendering, Stapel-Priorität, 6er-Gruppen, Auswahlring

**Anlass:** Stresstest fehlerfrei, aber Performance weiter schlecht. Die
Simulation war gemessen im Budget → Hauptverdächtiger war das **Rendering**:
4000 `AnimatedSprite3D` = 4000 Draw Calls + 4000 Node-Updates pro Frame.

**1. MultiMesh-Einheiten-Rendering (ein Draw Call für alle Einheiten):**
- `scripts/ui/unit_renderer.gd` — `UnitRenderer` (MultiMeshInstance3D in
  main.tscn): QuadMesh (16×24 px × 0,06 m, Füße am Ursprung) mit
  ShaderMaterial — **Billboarding im Vertex-Shader**
  (`VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0..2], MODEL_MATRIX[3])`), Frame über
  per-Instanz-Custom-Data (Atlas-UV-Offset), Stammfarbe über Instanzfarbe,
  `discard` bei Alpha < 0,5. Kapazität 4096 Instanzen.
- `PlaceholderSprites.build_atlas(kinds)` packt alle Frames in EINE
  Atlas-Textur; Tabelle kind → anim → 4 Ansichten → `[start, count, fps]`.
  Neue Einheiten-Typen (Phase 4/5): Kind in `UnitRenderer.KINDS` ergänzen.
- Update-Strategie pro Frame: Kamera **einmal** holen; Frames/Ansichten in
  **3 Slices** (nur bei geändertem Frame-Index wird Custom-Data geschrieben,
  Cache `_render_frame` auf der Unit); **Transforms jeden Frame, aber nur
  für bewegte Einheiten** (`_render_pos`-Vergleich — Stehende kosten einen
  Vector-Vergleich). Hüpf-Offset global berechnet; Jump-Frame aus Hop-Phase.
- `Unit` hat **keine visuellen Kinder mehr** (brave.tscn = nur Root):
  Sprite-Maschinerie entfernt; Animations-Zustand als Daten
  (`anim_base_name` + `anim_start_ms`, `_apply_animation` setzt nur noch
  diese); neu `Unit.view_index()` (int, 0=front/1=back/2=right/3=left,
  `view_suffix` bleibt als Wrapper für Tests). Registrierung/Deregistrierung
  über UnitManager → Renderer (Swap-Remove, null-guarded für Tests).

**2. Stapel vor Bäumen (Bugfix):** In `Brave._choose_job_task()` wird bei
Holzbedarf jetzt **zuerst** nach Stapeln gesucht (PICKUP), erst dann nach
Bäumen (CHOP) — liegengelassenes Holz wird immer als erstes verbaut
(Stapel-Suche unbegrenzt über die Insel; Stapel im Absorb-Radius nimmt die
Baustelle weiter selbst).

**3. 6er-Gruppen + dichteres Packing (Original-Look):**
- `TribeCommands.order_move`: Selektion räumlich sortiert, in **Gruppen à 6**
  geteilt; Gruppenzentren im Ring-Formationsmuster mit `GROUP_SPACING = 2,2 m`,
  Mitglieder eng um ihr Zentrum (`MEMBER_OFFSETS`, Radius ~0,55 m).
- `SEPARATION_RADIUS` 0,55 → **0,44** (20 % dichter); Member-Abstände liegen
  knapp darüber → Gruppen stehen ruhig, zwischen Gruppen sichtbarer Abstand.
- Pfad-Sharing war unnötig: A* misst nur ~0,5 ms/Tick (Queue).

**4. Auswahlring:** kleiner (Torus 0,26/0,34 — „um die Beine“), **mit
Tiefentest** (zeichnet nicht mehr über die Sprites), Höhe 0,08 m — Ring und
Modell-Fußpunkt decken sich.

**Erkenntnisse:**
- `MODEL_MATRIX[3]` enthält bei MultiMesh die Instanz-Position — damit ist
  Shader-Billboarding pro Instanz trivial.
- Transform-Schreiben nur bei Positionsänderung macht stehende Massen fast
  gratis; die MultiMesh-API lädt den Buffer ohnehin gesammelt hoch.

**Verifikation:** Testsuite grün (**184 Tests**; neu: Stapel-Priorität
(Bäume bleiben unangetastet), 6er-Gruppenbildung, Separations-Schwelle an
0,44 angepasst), `--headless --quit` fehlerfrei (lädt Shader/Atlas),
Sim-Benchmark Ø 19,2 ms / Spitze 34 ms (Budget ~33 ms). Manuelle Prüfung:
**ausstehend — bitte durch Nutzer prüfen** (FPS mit 4000 Einheiten,
Sprite-Optik: Richtungen/Farben/Hüpfen — falls Sprites kopfstehen, eine
Zeile im Shader `UV.y` flippen; 6er-Grüppchen beim Massen-Move; kleiner
tiefengetesteter Ring; Baustelle nutzt Stapel zuerst).
