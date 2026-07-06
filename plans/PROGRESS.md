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
  `units`/`buildings` (typisierte Arrays), `shaman` (Phase 6). Abgeleitet als **Methoden**:
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
  3×3, `PRAY_RADIUS = 5`; in Phase 3 nur Gebetsplatz (Respawn folgt Phase 6).
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
  `THROWN` (Würfe ab Phase 6 — dort ist Overlap erlaubt) sind ausgenommen.
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

**Offen/bekannt (Phase 8):** 4000 `AnimatedSprite3D` sind weiterhin je ein
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
  Neue Einheiten-Typen (Phase 5/6): Kind in `UnitRenderer.KINDS` ergänzen.
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

---

## Phase 4 — Original-nahes UI (Sidebar, Minimap, Tabs, Pausemenü)

**Gebaut:**
- `scripts/ui/ui_theme.gd` — `UiTheme` (class_name, RefCounted): prozedurale
  Gold/Braun-Optik. `panel_style()`, `inset_style()`, `style_button(btn)`
  (StyleBoxFlat für normal/hover/pressed/focus/disabled + Font-Farben),
  `icon(key) -> ImageTexture` (24×24-Pixel-Art, Cache pro Key) für Tabs
  (`house`/`star`/`people`), Gebäude (`hut`/`warrior_camp`/`firewarrior_camp`/
  `temple`), die 5 Zauber (`blast`/`lightning`/`swarm`/`landbridge`/`tornado`),
  `shaman`, `pause`, `menu`. Alles zur Laufzeit erzeugt, `assets\` bleibt leer.
- `scripts/ui/minimap.gd` — `Minimap` (class_name, Control): rund, **Norden
  fest**. Terrain aus `TerrainData.cell_height` in ein `Image`/`ImageTexture`
  (Höhen-Farbstufen konsistent zu `Terrain._color_for_height`, Wasser dunkel),
  Kreismaske durch transparente Pixel außerhalb des Inkreises; partielles
  Update bei `Events.terrain_deformed(rect)` (`ImageTexture.update`). Overlay
  in `_draw()`: Einheiten (2-px-Punkte in Stammfarbe), Gebäude (Quadrate),
  Bäume (dunkelgrüne Punkte), Kamera-Marker; Punkte außerhalb des Kreises
  geclippt; Redraw gedrosselt (0,2 s). Links-Klick/Drag = Kamera dorthin.
  **Statisch/headless-testbar:** `world_to_map(world_xz, map_size, world_size)`,
  `map_to_world(...)` (beide clampen + div-0-sicher), `height_to_color(h)`.
- `scenes/ui/sidebar.tscn` + `scripts/ui/sidebar.gd` — `Sidebar` (class_name,
  Control auf CanvasLayer `UI`): komplette UI-Hülle links, feste Breite 260,
  volle Höhe, `PanelContainer` mit `mouse_filter = STOP`. Aufbau (VBox):
  Minimap → Tab-Leiste (3 Icon-Buttons) → Kopfbereich (Schamanin-Porträt
  **disabled**, je Stamm ein `ProgressBar` in Stammfarbe = Bevölkerungsbalken,
  „Bevölkerung x/y“, „Holz“, 20-Segment-Mana-Balken) → Tab-Inhalt → Menü-Button.
  - **Maus-Guard:** statisch `Sidebar.is_mouse_over_ui()` (Panel-Rect-Treffer);
    `process_mode = ALWAYS`, damit Esc/„Fortsetzen“ auch bei pausiertem Baum
    greift. Single-Instance in `_instance` (in `_exit_tree` geräumt).
  - **Signalgetrieben:** `Events.population_changed` → Balken + „x/y“,
    `mana_changed` → Mana-Segmente, `stockpile_changed` → Holz.
  - **Statisch/testbar:** `mana_segments(mana, cap, segments)`,
    `pip_state(charges, max, progress) -> {filled,empty,progress}`,
    `tribe_bar_fractions(populations) -> Array[float]` (normiert auf Max,
    all-null-sicher), `default_build_entries()`, `default_spell_entries()`.
  - **Tab Gebäude:** Button je `default_build_entries()`-Eintrag (Icon + Name +
    Kosten). Hütte aktiv → `build_menu.start_placement(HUT_SCENE)`; Krieger-/
    Feuerkrieger-Lager/Tempel disabled + Tooltip „ab Phase 5“ (scene = null).
  - **Tab Zauber:** 5 Zellen (Pip-Reihe aus `ColorRect`s über Icon-Button),
    alle **disabled**. Anzeige-API `set_spell_state(id, charges, max_charges,
    charge_progress, castable)` fertig (füllt Pips, aktiviert Button) — Phase 6
    verdrahtet nur noch Ladungssystem + Zielmodus.
  - **Tab Gefolgsleute:** Zähler je Typ aus `Tribe.units`/`unit_kind()`
    (gedrosselt 0,3 s); Brave aktiv, Krieger/Feuerkrieger/Prediger/Schamanin
    ausgegraut bei 0. Button „Untätige Braves wählen“ → selektiert eigene
    IDLE-Braves über `SelectionManager.select_units()`.
  - **Pausemenü:** Vollbild-Overlay (`process_mode = ALWAYS`), „Fortsetzen“
    (`get_tree().paused = false`) / „Beenden“ (`get_tree().quit()`); Menü-Button
    und Esc togglen (`_toggle_pause`), Esc nur wenn kein Bau-Placement aktiv.
- `scripts/ui/build_menu.gd` — zum **reinen Platzierungs-Controller**
  refaktoriert: eigener Button entfernt; neue öffentliche API
  `start_placement(scene)`, `cancel()`, `is_active()` (intern `_toggle_hut` für
  Hotkey H). Ghost wird bei `Sidebar.is_mouse_over_ui()` versteckt; Platzier-/
  Abbruch-Klicks über der Sidebar werden ignoriert.
- `scripts/ui/selection_manager.gd` — Maus-**Start** über der Sidebar wird
  ignoriert (laufende Drags dürfen dort enden); neue Methode
  `select_units(units)` (public Wrapper um `_set_selection`).
- `project.godot` — Input-Actions `cast_spell_1..5` (Tasten 1–5, in Phase 4
  ohne Wirkung, für Phase 6 reserviert).
- `scripts/core/main.gd` / `scenes/main.tscn` — altes HUD entfernt, `Sidebar`
  eingehängt und via `_sidebar.setup(tribes, player_id, unit_manager,
  building_manager, tree_manager, wood_pile_manager, tribe_commands, build_menu,
  selection, camera_rig, terrain_data)` verdrahtet.
- **Entfernt:** `scenes/ui/hud.tscn` + `scripts/ui/hud.gd` (Anzeigen sind in die
  Sidebar gewandert).
- `tests/test_ui_logic.gd` — 49 Checks: `world_to_map`/`map_to_world`
  (Mitte/Ecken/Clamp/Rundtrip/div-0), `height_to_color` (Wasser dunkel, Stufen
  konsistent zu Terrain-Schwellen), `mana_segments` (Hälfte/voll/Überlauf/
  Guards), `pip_state` (partiell/voll/0/Clamp), `tribe_bar_fractions`
  (proportional, all-null-sicher), Build-Registrierung (Hütte aktiv referenziert
  Hut-Szene + `Hut.WOOD_COST`; disabled ohne Szene), Zauberanzahl.

**Extras/Abweichungen vom Plan:**
- Kein separates `tribe_bars.gd` — Bevölkerungsbalken als gestylte
  `ProgressBar`s (Stammfarben-Fill), Längen aus `tribe_bar_fractions()`.
- Sidebar-Layout komplett in Code (`_build_ui`) aufgebaut; die `.tscn` enthält
  nur den Root-`Control` mit Skript (analog altem HUD/BuildMenu).
- Mana-Anzeige-Obergrenze `MANA_DISPLAY_CAP = 1000` (reine Anzeige-Konstante).

**Erkenntnisse/Stolpersteine:**
- `PanelContainer.mouse_filter = STOP` schluckt GUI-Events über sich bereits,
  bevor `_unhandled_input` läuft → der explizite `is_mouse_over_ui()`-Guard ist
  Zusatzsicherung (und deckt SelectionManager/BuildMenu ab, die auf
  `_unhandled_input` hören). Ein Drag, der über der Sidebar losgelassen wird,
  wird vom Panel geschluckt und nicht finalisiert (Rand-Edge-Case, unkritisch).
- Damit Esc/„Fortsetzen“ bei `get_tree().paused = true` noch reagieren, müssen
  Sidebar **und** Pausemenü `process_mode = PROCESS_MODE_ALWAYS` haben (pausable
  Nodes erhalten pausiert kein Input).

**Verifikation:** Testsuite grün (**233 Tests**, davon 49 neu in
`test_ui_logic.gd`), `--headless --import` + `--headless --quit` fehlerfrei,
Spiel 5 s headless ohne Laufzeitfehler (Sidebar-`_process`/Follower-Refresh
laufen). **Manuelle Prüfung durch Nutzer bestanden (2026-07-06)** — inkl. der
Folgerunden unten (Sprite-Tiefe an Gebäuden/Terrain, Holzwirtschaft-Feinschliff,
Trage-Animation, 6er-Gruppen aus Gebäuden, Gebäude-Auswahl/Rally-Marker/
Produktionsbalken, Lauf-Beinanimation). Phase 4 abgeschlossen und committet.

**Bugfix (Nutzerfeedback): Sprite-Tiefe an Gebäuden/planiertem Terrain.**
Der UnitRenderer-Shader zeichnete das Sprite als **spherisches Billboard** auf
**einer** konstanten Tiefe (= Bodenpunkt der Einheit). Dadurch lag der Kopf auf
Bodentiefe, und erhöhte Nachbargeometrie (Hüttendach, planierte Terrain-Kante
mit scharfen Ecken) war näher an der Kamera und verdeckte Sprite-Teile falsch
(Köpfe verschwanden im Haus; Terrain verdeckte Sprites uneinheitlich). Fix in
[unit_renderer.gd](../scripts/ui/unit_renderer.gd): Form/Bildschirmposition
bleiben kamerazugewandt (keine Verzerrung), aber die **Tiefe pro Vertex** wird
berechnet, als stünde das Sprite senkrecht in der Welt (jede Zeile um ihre echte
Welthöhe `up_view.z * VERTEX.y * ELEVATION_GAIN` Richtung Kamera versetzt) plus
kleiner Bias (`DEPTH_BIAS = 0.35`). Es wird nur `POSITION.z` (NDC-Tiefe)
geändert, x/y bleiben die spherische Projektion. Ergebnis: Geometrie verdeckt
Sprites nur noch, wenn sie wirklich davor ist.
- **Folgerunden (Nutzerfeedback):** Hüttendach-Überstand entfernt
  ([hut.gd](../scripts/buildings/hut.gd): Dach-Prisma 0.95× → **0.85×** =
  bündig mit den Wänden). `ELEVATION_GAIN` kurzzeitig auf 1.7 gesetzt (Kopf
  extra Richtung Kamera) — das **überschoss** (Kopf ragte vor die Wand / lugte
  hinter dem Haus übers Dach, Restsprite wirkte versetzt) und wurde auf **1.0**
  (physikalisch korrekt) zurückgesetzt: Kopf sitzt auf seiner echten Tiefe,
  vorne sichtbar / hinten verdeckt, ohne Überschießen.
- **Prinzipbedingte Grenze:** Ein flaches Billboard neben einem 3D-Gebäude
  kann nicht perfekt sein — die auf dem Bildschirm überlappende Sprite-Hälfte
  wird vor der Wand gezeichnet, wenn der Bodenpunkt der Einheit davor liegt
  (physikalisch korrekt). Ein völlig artefaktfreies Ergebnis bräuchte echtes
  2.5D-Grund-Sortieren (Einheiten/Gebäude nach Bodenlinie, ohne Per-Pixel-Z) —
  bewusst offen für Phase 8, falls gewünscht.
- **Optische Prüfung durch Nutzer bestanden (2026-07-06).**

**Holzwirtschaft-Feinschliff (Nutzerfeedback):**
- **Manuelles Sammeln = ein Stück pro Weg:** `Brave._tick_loose_chop` liefert
  jetzt nach **jedem einzelnen** Holz ab und kehrt danach zum Fällplatz zurück
  (vorher bis Tragekapazität 3 gefüllt). Test `test_manual_chop_one_piece_per_trip`
  prüft, dass `carried_wood` nie über 1 steigt.
- **Ablieferung konsolidiert auf bestehende Stapel:** neuer Helfer
  `Brave._loose_drop_target()` zielt bevorzugt auf einen vorhandenen Stapel mit
  Platz nahe dem Gebäude-Eingang (`WoodPileManager.pile_with_space_near`,
  Radius `DROP_CONSOLIDATE_RADIUS = 5`), sonst auf den Eingang.
- **Stapelgröße skaliert mit Menge:** `WoodPile._update_visual` skaliert den
  Knoten mit der Holzmenge (`0.8`…`1.45`); Basis bleibt am Boden (Sprite-Füße =
  Ursprung). Max weiterhin `MAX_AMOUNT = 5`.
- **HUD „Holz" = Holz nahe eigener Gebäude:** neue Abfrage
  `WoodPileManager.wood_near_positions(positions, radius)` (jeder Stapel einmal
  gezählt). Die Sidebar zeigt jetzt die Summe der Stapel im Umkreis
  `WOOD_NEAR_RADIUS = 12` um die eigenen Gebäude (statt der globalen Gesamtmenge),
  aktualisiert im gedrosselten Refresh (0,3 s) und bei `stockpile_changed`.
- Tests: `test_manual_chop_one_piece_per_trip`, `test_wood_pile_manager_near_queries`
  (Gesamt **241** grün); bestehende Manual-Chop-Tests unverändert grün.

**Trage-Animation, 6er-Gruppen aus Gebäuden, Gebäude-UI (Nutzerfeedback):**
- **Holz-Trage-Sprite:** `PlaceholderSprites` hat zwei neue Animationsbasen
  `carry` (stehend, Holzscheit vor dem Körper) und `carry_walk` (laufend) in
  allen 4 Ansichten (in `make_frames` und `build_atlas`/Atlas aufgenommen).
  `Brave._anim_base` liefert beim Tragen (`carried_wood > 0`) `carry_walk` beim
  Laufen bzw. `carry` beim Stehen (`_carry_or`); Walk/Idle/Carry werden per Tick
  via `_apply_animation(false)` (kein Timer-Neustart) an die echte Bewegung
  (`_has_path()`) angepasst.
- **6er-Gruppen aus Gebäuden:** neuer statischer Helfer
  `TribeCommands.group_slot_offset(index)` (gleiche Ring-Formation wie
  `order_move`). `Hut._spawn_brave` schickt neue Braves an einen Slot
  (`_spawn_counter % 36`) in 6er-Gruppen um den Rally-Point statt an einen
  zufällig gestreuten Punkt.
- **Gebäude anwählbar + Rally per Rechtsklick:** `Building` hat `selected` /
  `set_selected()` mit gold-farbenem Auswahlring (Torus, unshaded).
  `SelectionManager` wählt bei Linksklick zuerst ein eigenes Gebäude (Raycast
  Layer 2, `_select_building`, wechselseitig exklusiv zur Einheitenauswahl);
  bei ausgewähltem Gebäude setzt Rechtsklick dessen `rally_point` auf den
  Terrain-Trefferpunkt (`_set_rally`), sonst weiterhin `_command_move`.
- **Produktions-/Ausbildungsbalken über Gebäuden:** `Building.production_progress()`
  (Basis −1 = keiner) + billboard-Sprite-Balken (`_create_overlay`/`_update_overlay`,
  Tiefen­test aus, Textur nur bei Wertänderung neu). `Hut.production_progress()`
  = Fortschritt bis zum nächsten Brave (`1 - spawn_timer/SPAWN_INTERVAL`), −1
  während Bau oder bei erreichtem Bevölkerungslimit.
- Tests: `test_carry_animation_base`, `test_group_slot_offset`,
  `test_hut_production_progress` (Gesamt **256** grün).

**Nachbesserungen (Nutzerfeedback):**
- **Trage-Sprite Rückenansicht:** von hinten wird das Holz (vor dem Körper) nicht
  mehr gezeichnet — nur minimal kürzere Arme (`_draw_carry_arms_and_log`
  behandelt `back` separat).
- **Rally-Marker:** `Building` zeigt bei Auswahl einen Sammelpunkt-Marker
  (goldener Ring + Pfosten) an der `rally_point`-Position (`_create_rally_marker`/
  `_update_rally_marker`, Position je Tick aktualisiert).
- **Produktionsbalken nur bei Auswahl/Hover:** `_update_overlay` zeigt den Balken
  nur noch, wenn das Gebäude `selected` **oder** `hovered` ist. Hover kommt vom
  `SelectionManager._update_hover` (Raycast Layer 2 bei Mausbewegung →
  `Building.set_hovered`).

**Bewusst NICHT umgesetzt (Phase 5 nötig):** „Gebäude von Anhängern besetzen"
(Einheiten per Rechtsklick reinschicken) und das Slot-/Belegungs-Icon mit
Einheitentyp-Symbolen — das ist die Ausbildungsgebäude-Mechanik aus Phase 5
(Krieger-/Feuerkrieger-Lager, Tempel). Bei Hütten gibt es keine Besetzung.
Wird mit den Trainingsgebäuden in Phase 5 nachgezogen.

---

## Phase 5a — Training, Rally Points, Einheiten-Modelle (umgesetzt)

**Gebaut:**
- `scripts/units/warrior.gd` / `firewarrior.gd` / `preacher.gd` + Szenen —
  **dünne** `Unit`-Ableitungen mit nur Werten (Krieger 120 HP + `MELEE_STRENGTH
  = 3.0`; Feuerkrieger 60 HP; Prediger 75 HP), Speed = Basis, je eigenes
  `unit_kind()` (`&"warrior"`/`&"firewarrior"`/`&"preacher"`). Kampf-/
  Sonderverhalten folgt in 5b/5c.
- **Sprite-Silhouetten je Kind:** `PlaceholderSprites._build_frames(kind, anim,
  view)` reicht `kind` durch (in `make_frames` **und** `build_atlas`), spiegelt
  erst die Basis (Left = geflippte Right-Ansicht) und ruft dann
  `_decorate(img, kind, view, bob)` pro Frame in der **echten** Ansicht + mit dem
  **Pro-Frame-Bob** der Oberkörperbewegung. Dadurch: (a) Seitenansichten sind
  **nicht bloß gespiegelt** — der Krieger zeigt rechts das **Schwert**, links das
  **Schild** (das Fern-Hand-Objekt liegt hinter dem Körper); (b) Helm/Haube/
  Feuerbälle **bobben mit** (z. B. in Idle). Overlays (Shape +
  Helligkeitskontrast, da alles im Renderer mit der Stammfarbe multipliziert
  wird): Krieger = **Schild / erhobenes Schwert**, Feuerkrieger = **dunkle
  Helmkappe + Feuerbälle auf Handhöhe**, Prediger = **spitze Zauberhut-Haube +
  langes Gewand**. Brave/Schamanin bleiben schmucklos. Neue Kinds in
  `UnitRenderer.KINDS` (`brave/warrior/firewarrior/preacher`; Prediger ist bereits
  `CASTER_KIND` → bekommt `cast`-Anim).
- `scripts/buildings/training_building.gd` — `TrainingBuilding extends Building`:
  `produces: PackedScene`, `training_time`, **Warteschlange** `incoming`
  (Index 0 = vorne) + `trainee` (einer drinnen, `null` = Bucht frei). Ablauf im
  `_tick_active` (läuft im **BuildingManager**-Tick, nicht in der
  UnitManager-Schleife → kein Mutieren der `units`-Liste mitten in der
  Iteration): `_prune_queue` → `_assign_slots` (jeder wartende Brave bekommt
  `queue_slot_world(i)` als Ziel, Schlange **rückt automatisch auf**) →
  `_admit_front` (nur wenn Bucht frei **und** der vorderste an seinem Slot steht:
  `UnitManager.remove_from_world` = Alias `unregister`, raus aus
  Registry/Hash/Renderer, **Tribe-Mitgliedschaft bleibt** → Population zählt
  weiter) → Timer; `_finish_one` gibt den Trainee frei (aus Tribe + `queue_free`)
  und spawnt eine Kampfeinheit am Rand → `order_move(rally_point +
  group_slot_offset)`. `queue_slot_world(i)`: **einreihige Schlange entlang der
  Gebäude-Außenkante**, Start links vom Eingang (Blick von außen; Tangente
  `cross(out, up)`), läuft per `_rect_perimeter_point` an der Kante entlang und
  **um die Ecken herum** (bei langer Schlange), Slots auf begehbare Zellen
  geklemmt. Population bleibt beim Tausch konstant. `production_progress()`
  treibt den Balken; `destroy()` gibt Trainee frei + entlässt die Wartenden
  (`Brave.cancel_training`).
- `scripts/buildings/warrior_camp.gd` (Kaserne, 5 Holz/3 s, 5×5, Ring+Turm+
  Federbüschel+Schilde+Runentor), `firewarrior_camp.gd` (Feuertempel, 10 Holz/
  4 s, 4×4, Rundhütte+Kegeldach+2 lodernde Feuerschalen mit Emission),
  `temple.gd` (Tempel, 5 Holz/5 s, 4×4, Kuppel+breites Reetdach+blau-goldene
  Kegel-Spitze) + Szenen. Prozedurale Placeholder-Meshes im Stil der Referenz-
  bilder.
- `scripts/units/brave.gd` — neuer `State.TRAIN`-Zweig: `order_train(building)`
  (Task-Interrupt → `building.add_trainee` → State TRAIN), `_tick_train` seekt
  zum vom Gebäude zugewiesenen `train_slot_pos` (Fallback Eingang) und setzt
  `train_reached_slot` (jeden Tick neu → fällt ab, wenn der Slot beim Aufrücken
  wandert); `enter_training()` (vom Gebäude beim Admit: Pfad leeren, Selektion
  aus), `cancel_training()` (Gebäude weg → IDLE). `_interrupt_tasks` meldet den
  Brave vom `train_target` ab.
- `scripts/core/tribe_commands.gd` — `order_train(building, units)`: nur eigene,
  lebende Braves; lehnt ab, solange das Gebäude im Bau ist. UI und (später) KI
  rufen dieselbe API.
- `scripts/core/unit_manager.gd` — `remove_from_world(unit)` (Alias auf
  `unregister`, dokumentiert die „lebt weiter, zählt weiter"-Semantik).
- `scripts/ui/selection_manager.gd` — Rechtsklick auf ein fertiges eigenes
  `TrainingBuilding` mit selektierten Einheiten → `order_train`. Rally per
  Rechtsklick bei ausgewähltem Gebäude gilt automatisch (Building-Basis).
- `scripts/ui/sidebar.gd` — Bau-Tab-Buttons für Kaserne/Feuertempel/Tempel
  **aktiviert** (Szenen + Kosten aus den Camp-Konstanten; Labels „Kaserne
  (5 Holz)" usw. über die vorhandene Kosten-Anhängung); Gefolgsleute-Zeilen
  Krieger/Feuerkrieger/Prediger auf `active` (Schamanin bleibt grau bis Phase 6).
- `scripts/core/main.gd` — **Sparring-Setup:** roter Tribe (id 1) auf der
  gegenüberliegenden Inselseite mit vorgebauter Hütte + Kaserne und einer kleinen
  Truppe (4 Braves, 3 Krieger, 2 Feuerkrieger) via `_find_plot`/
  `_find_walkable_near` (Ring-Suche). Kämpfen noch nicht (5b), existieren aber.

**Erkenntnisse/Stolpersteine:**
- **Admit im Gebäude-Tick, nicht im Unit-Tick:** Würde der Brave sich selbst bei
  Ankunft admitten, liefe `UnitManager.units.erase` mitten in der
  `for unit in units`-Schleife → übersprungene Elemente. Deshalb flaggt der Brave
  nur `train_arrived`; das Gebäude (separater BuildingManager-Tick) holt ihn rein.
- **Population konstant:** `remove_from_world` lässt die Tribe-Liste bewusst in
  Ruhe; erst `_finish_one` tauscht Brave↔Kampfeinheit atomar.
- Alle Silhouetten-Overlays werden im Renderer mit der Stammfarbe multipliziert
  → Erkennbarkeit über **Form + Helligkeit**, nicht Farbton.

**Verifikation:** Testsuite grün (**285 Tests**, davon 21 neu in
`tests/test_training.gd`: Erzeugung Kampfeinheit + Population ±0 + Typwechsel,
Rally-Ziel inkl. Rally-Änderung für später fertige Einheiten, leeres Gebäude
produziert nichts, **Warteschlange einer-nach-dem-anderen** (Rest wartet
sichtbar in der Welt), FIFO-Queue; `test_ui_logic.gd` Bau-Eintrag-Test auf aktive
Trainingsgebäude umgestellt). `--headless --import` + `--headless --quit`
fehlerfrei.

**Nachbesserungen (Nutzerfeedback, erste Runde):**
- **Krieger-Seitenansichten** zeigen jetzt seitenabhängig Schwert (rechts) bzw.
  Schild (links) statt gespiegelt beides.
- **Feuerkrieger:** Feuerbälle auf Handhöhe, Helm + Feuer **bobben mit** der
  Idle-Bewegung.
- **Prediger:** Haube bobbt mit; oben spitzer **Zauberhut**-Kegel.
- **Ausbildungs-Warteschlange:** Braves verschwinden nicht mehr sofort, sondern
  bilden eine **echte einreihige Schlange entlang der Gebäudekante** (Start links
  vom Eingang), rücken auf und gehen einzeln rein; lange Schlangen laufen um die
  Ecken weiter.

**Nachbesserungen (Nutzerfeedback, zweite Runde):**
- **Feuerkrieger-Seitenansicht:** Feuerball sitzt jetzt IN der Hand statt davor
  zu schweben.
- **Krieger-Seitenansicht:** Schwert wird in der Hand gehalten und zeigt nach
  **oben** (wie in der Frontansicht), statt davor zu schweben/nach unten.
- **Prediger-Frontansicht:** Hutkrempe sitzt jetzt **über** den Augen, Hauben-
  Seiten lassen die Augen frei → Gesicht wieder sichtbar.
- **Startszenario erweitert:** Spieler startet mit **2 Hütten + allen drei
  Trainingsgebäuden** (vorgebaut, `_setup_player_base` mit `_find_plot`) und
  **20 Braves** (`START_BRAVES`).
- **Bestätigt:** Trainingsgebäude dürfen **quadratische** Grundrisse + Box-
  Hitboxen behalten (bereits so; Modelle unverändert).
- **Bugfix Selektion:** Ein ausgebildeter (per `queue_free` freigegebener) Brave
  blieb in `SelectionManager.selected` referenziert → beim nächsten Selektieren
  `set_selected` auf freigegebener Instanz = Crash, danach keine Selektion mehr
  möglich. `_set_selection`/`_prune_selection` nutzen jetzt explizite Schleifen
  mit `is_instance_valid`-Guard (statt typisiertem Filter-Lambda, das schon beim
  Binden einer freigegebenen Instanz crasht). Regressionstest
  `test_selection_tolerates_freed_unit`.

**Manuelle Prüfung durch Nutzer: bestanden** (nach zwei Nachbesserungsrunden +
Selektions-Bugfix bestätigt „funktioniert"). **Sub-Phase 5a abgeschlossen.**

---

## Phase 5b — Nahkampf-Kern (Slots, Krieger, Aggro) (umgesetzt)

**Kampf lebt in der Basisklasse `Unit`** — dadurch prügeln sich alle Einheiten
gleich (Braves verteidigen sich, Krieger/Feuerkrieger/Prediger kämpfen; Fern-/
Sonderverhalten folgt 5c). Kern-Ideen: Zielsuche nie pro Frame (gestaffelter
Timer), Slot-System auf dem **Ziel**, freigabesichere untypisierte Referenzen.

**Gebaut (`scripts/units/unit.gd`):**
- **Kampf-Konstanten:** `MELEE_RANGE 1.2`, `AGGRO_RADIUS 8`, `ATTACK_COOLDOWN
  0.8 s`, `TARGET_SEARCH_INTERVAL 0.25 s`, `MAX_MELEE_ATTACKERS 3`,
  `MELEE_SLOT_RADIUS 0.9` / `MELEE_WAIT_RADIUS 1.7`, `COMBAT_DIRECT_RANGE 2.5`,
  Schadenswerte `MELEE_PUNCH 6` / `MELEE_KICK 8` / `MELEE_SHOVE 3`,
  `KICK_CHANCE 0.2` / `SHOVE_CHANCE 0.15`.
- **`take_damage(amount, attacker=null)`** (Signatur erweitert, alter 1-Arg-Aufruf
  kompatibel): HP runter, `last_attacker` merken, bei ≤0 → `_die()`
  (Slot-Cleanup: eigenen Slot freigeben, allen eigenen Angreifern
  `_on_target_died` melden → Nachrücken/Neuausrichtung, dann State DEAD +
  `died`), sonst `_maybe_retaliate` (Vergeltung nur aus IDLE/MOVE, nicht bei
  arbeitenden Braves).
- **Virtuals:** `_is_combatant()` (Basis false; Krieger/Feuerkrieger/Prediger
  true), `melee_strength()` (1.0; Krieger 3.0), `_shove_chance()` (0.15; Krieger
  0.04 = schubst selten), `_on_combat_interrupt()` (Brave gibt Arbeits-Claims frei).
- **`tick()`** verzweigt jetzt auch nach `State.ATTACK` (`_tick_attack`) und
  `State.IDLE` (`_tick_idle`, nur Combatants scannen Aggro) und ruft am Ende
  `_apply_animation(false)` (Attack-Frames nur beim Zuschlagen, sonst Walk beim
  Anlaufen — `_in_melee`-Flag steuert `_anim_base()`).
- **Slot-System (auf dem Ziel):** `melee_attackers: Array` (untypisiert),
  `request_melee_slot(a) -> int` (Index 0..2 oder −1 wenn voll),
  `release_melee_slot`, `active_melee_attacker_count`, `_prune_melee_attackers`
  (droppt freigegebene/tote/umgezogene Angreifer → Slot frei), `melee_slot_position`
  (120°-Ring). **1v1-Bevorzugung** über `incoming_attackers` (Zähler der auf ein
  Ziel *festgelegten* Angreifer, schon vor Kontakt) → `_scan_for_enemy` wählt das
  am wenigsten bedrängte Ziel.
- **Ablauf `_tick_attack`:** Ziel ungültig → `_retarget_or_idle`; Slot voll →
  (gedrosselt) freies Alternativziel suchen, sonst `_wait_near` (Warte-Ring);
  außer Reichweite → `_approach` (A* wenn fern, Direktschritt wenn nah); in
  Reichweite → `_do_strike` (Angriffsart würfeln `_roll_attack_kind`,
  `melee_damage(kind) = attack_base_damage(kind) * melee_strength()`).
- **`order_attack(enemy)` / `_begin_attack`** (Interrupt der laufenden Tätigkeit,
  alten Slot freigeben, `incoming_attackers` pflegen). `order_move` beendet einen
  laufenden Angriff (`_end_attack`).

**Weitere Dateien:**
- `warrior.gd`: `_is_combatant`=true, `melee_strength`=3.0, seltenes Schubsen
  (`WARRIOR_SHOVE_CHANCE 0.04`). `firewarrior.gd`/`preacher.gd`: `_is_combatant`
  =true (prügeln im Nahkampf; Sonderverhalten 5c).
- `brave.gd`: `_on_combat_interrupt()` → `_interrupt_tasks()` (nur in Arbeits-/
  Trainings-States), damit Vergeltung/Angriffsbefehl keine Claims strandet.
- `unit_manager.gd`: zentrale Tick-Schleife iteriert **Snapshot** (`units.duplicate()`,
  überspringt DEAD/freigegeben) — eine im Kampf sterbende Einheit meldet sich per
  `died`-Signal selbst ab, ohne die Iteration zu zerreißen. `_on_unit_died`
  `queue_free()`t den toten Knoten (bereits aus Registry/Hash/Renderer/Tribe/
  Slots draußen).
- `tribe_commands.gd`: `order_attack(units, enemy)` — nur Feinde, intelligente
  Verteilung (Ziel voll → `_nearest_free_enemy_near`). UI und KI nutzen dieselbe API.
- `selection_manager.gd`: Rechtsklick auf Feindeinheit (Screen-Space-Pick
  `_enemy_under_cursor`, da Einheiten keine Physik-Body haben) → `order_attack`;
  sonst wie bisher Move/Kontextbefehl.

**Erkenntnisse/Stolpersteine:**
- **Tod während des Ticks:** Sterben mitten in der zentralen `for unit in units`-
  Schleife würde beim `units.erase` Elemente überspringen → Schleife iteriert
  jetzt eine Kopie und überspringt DEAD/freigegebene.
- **Slot-Buchhaltung freigabesicher:** `melee_attackers` untypisiert + überall
  `is_instance_valid` vor typisierter Nutzung (vgl. 3b/3c).
- **1v1 braucht Vorab-Commitment:** physische Slots füllen sich erst bei Kontakt;
  ohne `incoming_attackers` würden zwei Angreifer dasselbe (noch „freie") Ziel
  wählen. Zähler wird in `_begin_attack`/`_end_attack` gepflegt.
- **Test-Fallstrick:** 4 Krieger zerlegen einen 60-HP-Brave in einem Tick-Fenster,
  bevor 3 Slots beobachtbar sind → Slot-Test macht das Ziel künstlich unsterblich.

**Verifikation:** Testsuite grün (**321 Tests**, davon 29 neu in
`tests/test_combat.gd`: Schaden/Tod + Deregistrierung aus Tribe/Hash, Treffer in
Reichweite, Verfolgung außer Reichweite, Krieger 3×, Slot-Cap 3 + Nachrücken,
1v1-Verteilung, Combatant-Aggro, Brave-Vergeltung ohne Distanz-Aggro).
`--headless --import` + `--headless --quit` + `--quit-after 240` fehlerfrei.

**Nachbesserungen (Nutzerfeedback, erste Runde):** Kampf funktioniert
grundsätzlich (getestet: Krieger, Feuerkrieger). Zwei Punkte behoben:
- **Eigene Schlag-Animationen** (vorher lief im Kampf nur die Arbeits-/
  `attack`-Animation): `PlaceholderSprites` hat drei neue Animationsbasen für
  **alle** Kinds — `punch` (4 Frames: beide Fäuste nacheinander, helle
  Faust-Blöcke), `kick` (Standbein + horizontal ausschwingendes Bein mit
  Fuß-Block), `shove` (beide Handflächen stoßen nach vorn, 2 Phasen) — plus
  `throw` **nur für den Feuerkrieger** (Ausholen mit Feuerball überm Kopf →
  Arm nach vorn). Gemeinsame Anim-Liste jetzt in `_anims_for(kind)`
  (make_frames **und** build_atlas). **FPS an die Cooldowns gekoppelt:**
  Punch 5 / Kick+Schubs 2,5 (Zyklus = `ATTACK_COOLDOWN` 0,8 s), Throw 4/3
  (Zyklus = `FIRE_COOLDOWN` 1,5 s); `_do_strike` setzt `attack_anim` =
  Animationsname der gewürfelten Angriffsart (`Unit.kind_to_anim`, statisch)
  und startet den Timer neu → der Schwung sitzt auf dem Treffer.
  `_anim_base()` liefert im ATTACK-State `attack_anim` (statt `attack`).
- **Feuerkrieger-Fernkampf vorgezogen (Kern aus 5c):** `firewarrior.gd`
  überschreibt `_tick_attack`: **≤ MELEE_RANGE** → Prügeln (super, Slot-System,
  Brave-Stärke, keine Feuerbälle); **≤ FIRE_RANGE (6 m)** → stehen bleiben,
  `throw`-Animation, alle `FIRE_COOLDOWN` (1,5 s) ein Feuerball (gehaltener
  Melee-Slot wird freigegeben; Fernkampf braucht keinen — beliebig viele
  Schützen je Ziel); **darüber** → anlaufen. Neu `scripts/units/fireball.gd` —
  `Fireball` (Node3D, **kein** Physik-Body): fliegt getickt mit leichtem
  Sinus-Bogen auf Brusthöhe zum Ziel (homing solange es lebt), Treffer =
  Distanzcheck, Schaden **genau einmal** (`Unit.FIREBALL_DAMAGE = 7`,
  `done`-Flag), Shooter/Target untypisiert (freigabesicher); Visual (orange
  Glow-Kugel) nur in `_ready` (headless-/testneutral). Der **UnitManager**
  führt eine `projectiles`-Liste (`register_projectile`, in-game als Kind
  eingehängt; `_tick_projectiles` in `tick()`, fertige werden `queue_free`t).
  **Noch 5c:** Rückstoß-Akkumulator, Hand-Feuerball-Toggle, Konvertierungs-Reset.

**Verifikation (nach Nachbesserung):** Testsuite grün (**348 Tests**, +6 neu:
Feuerball auf Distanz = exakt 7 Schaden + Abstand gehalten + throw-Anim,
Fireball trifft genau einmal, Nahkampf-Fallback ohne Feuerbälle/Brave-Stärke,
Strike-Anims im Atlas (alle Kinds, throw nur Feuerkrieger, Punch 4 Frames),
`kind_to_anim`-Mapping + Anim nach Treffer). `--headless --quit` +
`--quit-after 240` fehlerfrei.

**Nachbesserung (Nutzerfeedback, zweite Runde): Leichname statt Sofort-Despawn.**
Besiegte Einheiten verschwinden nicht mehr sofort: Sie liegen **5 s** als
Leichnam am Boden (`CORPSE_DURATION`), werden dann über **1 s** transparent
(`CORPSE_FADE_DURATION`) und erst danach entfernt.
- **`dead`-Sprite:** neue Animationsbasis in `PlaceholderSprites._anims_for`
  (alle Kinds, 1 Frame) — bewusst **demolierte** Liegepose statt gerader
  Linie: Torso/Hüfte versetzt geknickt, Kopf zur Seite gekippt, ein Arm und
  ein angewinkeltes Bein ragen hoch, ein Bein ausgestreckt; unten am Canvas
  (Quad-Ursprung = Füße → liegt am Boden). **Keine** Ausrüstungs-Overlays
  auf der Leiche (`_decorate` wird für `dead` übersprungen — Schild/Helm
  säßen auf Steh-Positionen).
- **`Unit`:** `_die()` räumt zusätzlich Selektion/Route/Hop; `State.DEAD`
  tickt jetzt `_tick_dead` (Timer; `corpse_expired`-Signal genau einmal via
  `_corpse_done`), `corpse_alpha()` = 1.0 bis 5 s, dann linear → 0;
  `_anim_base()` liefert für DEAD `&"dead"`.
- **`UnitManager`:** `_on_unit_died` entfernt **nur noch** aus dem Tribe
  (Population) — Registry/Hash/Renderer behalten die Leiche (alle Abfragen
  überspringen DEAD: Kampf, Selektion, Separation, Zielsuche; **keine
  Kollision**, Einheiten liefen ohnehin ohne Physik). Tote werden in der
  zentralen Tick-Schleife mitgetickt (Verwesung). Erst `corpse_expired` →
  `_on_corpse_expired` → `unregister` + `queue_free`.
- **Fade ohne Transparenz-Pass:** `UnitRenderer`-Shader macht **Screen-Door-
  Dithering** (Interleaved-Gradient-Noise-Schwelle auf `tint.a` mit
  `discard`) statt echtem Alpha-Blending — die Einheiten-Sprites bleiben im
  opaken Pipeline-Pfad (kein Sortierproblem). `_update_frame` schreibt das
  abklingende `corpse_alpha()` in die Instanzfarbe (Cache `_render_alpha`
  auf der Unit, **vor** dem Frame-Gleichheits-Early-Out, da der Leichen-Frame
  statisch ist); Swap-Remove im Renderer setzt den Cache des verschobenen
  Units zurück.

**Verifikation (nach zweiter Runde):** Testsuite grün
(**359 Tests**, +11: Leiche bleibt registriert, `dead`-Anim aktiv, 5 s voll
sichtbar → Fade (0<α<1) → nach 6 s aus Registry und Spatial-Hash entfernt;
`dead`-Sprite im Atlas für alle Kinds; Todes-Test auf Leichen-Semantik
umgestellt). `--headless --import`/`--quit`/`--quit-after 240` fehlerfrei.

**Nachbesserung (Nutzerfeedback, dritte Runde): Feuerball gerade + Selektionsbug.**
- **Feuerball fliegt gerade:** Sinus-Bogen entfernt (`fireball.gd`) — direkter
  `move_toward` auf Brusthöhe des Ziels (weiter homing). Gegen das beobachtete
  „Hängenbleiben": harte Lebenszeit `MAX_LIFETIME = 3 s` (danach verpuffen
  ohne Schaden); `_impact` macht Schaden nur noch, wenn der Ball das Ziel
  wirklich erreicht hat (Distanz ≤ 2×HIT_RANGE), nicht beim Lifetime-Fizzle.
- **Selektionsbug (Ursachenanalyse):** (a) Klick-Auswahl testete einen festen
  **24-px-Radius** um einen Punkt auf ~0,7 m Höhe — bei nahem Zoom ist das
  Sprite deutlich größer als 24 px → Klicks auf Kopf/Füße gingen daneben.
  (b) **Edge-Scroll während des Box-Drags:** Der Auswahlrahmen ist Screen-
  Space; zieht man Richtung Fensterrand (< 8 px), pannt die Kamera **während**
  des Aufziehens, beim Loslassen liegen die Einheiten nicht mehr im Rahmen →
  leere Auswahl, die die bestehende Selektion löschte („Ringe blitzen kurz
  auf, dann abgewählt").
- **Fixes (`selection_manager.gd`, `camera_rig.gd`):**
  - Picking gegen das **projizierte Sprite-Rechteck** (`_unit_screen_rect`:
    Füße→Kopf unprojiziert, Breite über Sprite-Seitenverhältnis 16:24,
    Mindestgröße 14 px für ferne Winzlinge; +4 px Toleranz) — zoomunabhängig.
    Gemeinsamer Helfer `_pick_unit_at(pos, camera, tribe_id)` (eigener Stamm
    bzw. `-1` = Feind) für Klick-Auswahl **und** Rechtsklick-Angriffsziel;
    Box-Select testet `rect.intersects(sprite_rect)` statt Punkt-im-Rahmen.
  - **`SelectionManager.drag_active`** (static): solange die linke Taste für
    einen (potenziellen) Box-Drag gehalten wird, liefert
    `CameraRig._edge_scroll_vector()` Null — Kamera steht beim Aufziehen.
    Sicherheitsnetz in `_process`: wird das Release woanders geschluckt
    (Sidebar-Panel), endet der Drag, sobald die Taste oben ist.
  - **Leere Box wählt nicht mehr ab** (fast immer ein verrutschter Drag);
    Abwählen bleibt über Klick auf leeren Boden.
- Klick-/Box-Verhalten ist kamera-/screen-abhängig → **nur manuell testbar**
  (Test-Strategie Overview); Fireball-Tests decken die gerade Flugbahn ab.

**Verifikation (Stand nach allen Nachbesserungen):** Testsuite grün
(**359 Tests**), `--headless --quit` + `--quit-after 240` fehlerfrei.
**Manuelle Prüfung durch Nutzer: bestanden** — Kampf, Strike-Anims,
Feuerkrieger-Fernkampf, Leichen und Selektion funktionieren; es bleiben
**kleinere Unschärfen** (nicht näher spezifiziert), Feinschliff dafür in
5d bzw. Phase 8. **Sub-Phase 5b abgeschlossen** — weiter mit 5c
(Fernkampf-Rückstoß, Prediger-Konvertierung).

---

## Phase 5c — Fernkampf-Rückstoß & Prediger (umgesetzt)

**Gebaut:**
- **Feuerball-Rückstoß mit Akkumulator (`unit.gd`, `fireball.gd`):**
  `Unit.apply_knockback(dir)` schiebt das Ziel flach weg
  (`KNOCKBACK_BASE 0,7 m` + `KNOCKBACK_STACK_BONUS 0,5 m` × Akkumulator);
  `knockback_accum` (+1 je Treffer, Zerfall `0,8/s`) lässt **Salven stärker
  schleudern**. Verschiebung wird in `_tick_knockback` mit 10 m/s abgespielt
  (Walkability-Clamp — niemand wird ins Wasser geschoben; Roll-Auslöser
  hookt hier in 5d ein). **Tick-Refactor:** `Unit.tick` = Knockback →
  `_tick_state(delta)` (neuer virtueller Dispatch, Brave überschreibt jetzt
  diesen statt `tick`) → `_apply_animation(false)` — Querschnittssysteme
  laufen damit für alle Subklassen. `Fireball._impact` wendet Schaden +
  Knockback (Richtung Schütze→Ziel) an.
- **Hand-Feuerball-Toggle:** `throw`-Frames getauscht (Frame 0 = gerade
  abgefeuert, **Hand leer**; Frame 1 = nachgeladen, Feuerball wieder über
  der Hand). Anim startet je Schuss neu → Ball verschwindet exakt beim
  Abwurf, erscheint mitten im Cooldown wieder.
- **Prediger-Konvertierung (`preacher.gd` neu geschrieben, Sitz-Logik in
  `unit.gd`):** `CONVERT_RANGE 5 m` (bewusst < FIRE_RANGE 6 m),
  Konvertierzeit zufällig 4–9 s je Ziel, `FIGHT_INERTIA_CHANCE 0,4`
  (bereits kämpfende setzen sich pro Versuch nur mit 60 %). Prediger:
  IDLE-Scan bevorzugt Konvertieren (immune Ziele → Nahkampf), `State.CAST`
  = channeln + Anlaufen aufs Fokusziel (`_refresh_conversion` im
  Scan-Takt), `order_attack`-Override (Rechtsklick auf normalen Feind =
  konvertieren, auf Prediger/Schamanin = prügeln). **Ziel-Seite (`Unit`):**
  neuer `State.SIT` (ans Enum-Ende), `begin_conversion` (Interrupt +
  hinsetzen), `_tick_sit` (Fortschritt nur solange der Prediger in
  Reichweite **castet**; Prediger im ATTACK = **Duell → Trance bricht, die
  Freigelassenen greifen den Prediger an**), `convert_to_tribe`
  (Tribe-Listen umhängen, `tribe_id`, Angreifer-Slots lösen, Signal
  `converted` → UnitManager → `UnitRenderer.update_unit_color`).
  `is_conversion_immune()` (Schamanin/Prediger). Sitzende sind **kein
  Aggro-Ziel** (`_scan_for_enemy` überspringt SIT — schützt Konvertierungen
  vor eigenen Kampfeinheiten); `_tick_attack`/`_maybe_retaliate` droppen
  Ziele der **eigenen** Farbe (frisch Konvertierte werden nicht weiter
  verprügelt).
- **Priester-Duell:** feindlicher Prediger ≤ CONVERT_RANGE → `_begin_attack`
  (Nahkampf); die Sitzenden stehen auf und kämpfen mit (via `_tick_sit`).
- **Feuerkrieger-Reset:** `Fireball._impact` ruft auf sitzenden Zielen
  `reset_conversion()` (Fortschritt = 0, Ziel steht auf). Friendly-Fire
  löst keine Vergeltung aus (`_maybe_retaliate` prüft Tribe).
- **`sit`-Placeholder-Animation** (alle Kinds, 2 Frames mit Atem-Bob,
  gesenkter Kopf + gefaltete Beine; keine Ausrüstungs-Overlays wie bei
  `dead`).
- **Sparring:** rote Basis bekommt **2 Prediger** (Konvertierung/Duell
  manuell testbar). Selektion: `_prune_selection` wirft auch Einheiten
  raus, die **nicht mehr dem Spieler gehören** (wegkonvertiert).

**Auswahllogik (Nutzerreport „Rahmen blitzt kurz, dann abgewählt", v. a.
bei schnellen Rahmen) — drei Restursachen gefixt (`selection_manager.gd`):**
1. **Hin-und-zurück-Drags:** Release < 6 px vom Start wurde als Boden-Klick
   gewertet (→ Abwahl), obwohl ein Rahmen sichtbar war. Jetzt zählt die
   **maximale Drag-Ausdehnung** (`_drag_max_dist`) — einmal Rahmen, immer
   Rahmen.
2. **Preller-/Doppelklicks direkt nach dem Box-Select:** Boden-Klick-Abwahl
   ist für `DESELECT_GRACE_S = 0,3 s` nach einem erfolgreichen Box-Select
   gesperrt.
3. **Über der Sidebar geschlucktes Release:** das `_process`-Sicherheitsnetz
   **finalisiert** den Rahmen jetzt mit der letzten bekannten Mausposition
   statt ihn zu verwerfen.

**Erkenntnisse:**
- Vergeltung + Knockback im selben Tick: das Ziel läuft nach dem Treffer
  sofort auf den Schützen zu — Tests müssen die Verschiebung direkt nach
  einem Tick messen, sonst überwiegt die Laufbewegung.
- Zirkulärer Verweis `Unit._tick_sit` → `Preacher.CONVERT_RANGE` ist wie
  gehabt unkritisch (Ladecheck grün).

**Verifikation:** Testsuite grün (**389 Tests**, +30 in `test_combat.gd`:
Knockback-Stapelung + Zerfall, Fireball-Knockback, Konvertierung komplett
(Sitzen → Fortschritt → Tribe-Wechsel inkl. Listen), Immunität
(Prediger), Priester-Duell bricht Trance + Freigelassene kämpfen mit,
Feuerball-Reset, `sit` im Atlas). `--headless --import`/`--quit`/
`--quit-after 240` fehlerfrei. **Manuelle Prüfung durch Nutzer:
ausstehend** (Feuerball-Rückstoß sichtbar/Salven stärker, Hand-Feuerball
verschwindet beim Wurf; rote Einheiten setzen sich vor dem eigenen
Prediger und werden blau; Duell mit rotem Prediger; Selektion stabil bei
schnellen Rahmen).

**Nachbesserung (Nutzerfeedback): Reichweite + Befehlssperre beim Sitzen.**
Konvertieren vom Nutzer bestätigt („klappt"). Zwei Anpassungen:
- **Feuerkrieger-Reichweite** `FIRE_RANGE` 6 → **7 m**.
- **Sitzende nehmen keinerlei Befehle an:** neuer Guard
  `Unit.can_take_orders()` (false bei SIT/DEAD) in `order_move` und
  `_begin_attack` (deckt `order_attack` ab) sowie in allen Brave-Befehlen
  (`order_chop/build/pray/train`) und im Prediger-`order_attack`-Override.
  Sitzende bleiben sitzen, bis der gegnerische Prediger angegriffen wird
  (Duell), das Predigen anderweitig unterbrochen wird (Feuerball-Reset,
  außer Reichweite, Tod) oder die Konvertierung abschließt.
  `_stand_up` setzt IDLE vor dem Gegenangriff → Duell-Freilassung
  funktioniert weiter. Test `test_sitting_unit_refuses_orders`
  (Gesamt **397** grün).
- **Angreifer lassen von Sitzenden ab:** Setzt sich das Angriffsziel unter
  den Prediger-Bann (SIT), brechen seine Angreifer ab — nur mit
  `SIT_ATTACK_CONTINUE_CHANCE = 5 %` kämpft einer weiter. Der Wurf fällt
  **einmal pro Angreifer und Sitz-Phase** (`_sit_decision_target`, wird
  beim Aufstehen zurückgesetzt → neue Phase = neuer Wurf), eingehängt in
  `Unit._tick_attack` **und** den Feuerkrieger-Override
  (`_breaks_off_vs_sitting`). Abbrecher scannen neu (Sitzende bleiben
  ausgenommen) oder gehen auf IDLE. Test
  `test_attackers_break_off_vs_sitting_target` (statistisch: ≥3 von 5
  brechen ab; Gesamt **399** grün).

**Manuelle Prüfung durch Nutzer: bestanden** („das klappt" — Konvertieren,
Duell, Rückstoß, Selektion). **Sub-Phase 5c abgeschlossen** — weiter mit 5d
(Hügel-Bewegung, Rollen, Regeneration, Sterne-Overlay, Kampf-Sounds).

---

## Phase 5d — Bewegung, Rollen & Politur (+ Zusatzwünsche) (umgesetzt)

**Bewegung (`unit.gd`):**
- **Bergauf langsamer:** `_slope_ahead(dir)` (Höhendifferenz 0,6 m voraus) +
  `_slope_speed(slope)` — bergauf Faktor `1 − slope·UPHILL_SLOWDOWN(0,45)`,
  geklemmt auf `MIN_SPEED_FACTOR 0,35`; bergab/flach volle Geschwindigkeit.
  Gilt für Pfadbewegung (`_advance_path`) **und** Kampf-Annäherung
  (`_step_toward`).
- **Steilhang-Rollauslöser:** beim Laufen **bergab** steiler als
  `STEEP_ROLL_SLOPE 1,0` → Chance `0,6/s`, ins Rollen zu geraten.

**Rollen (`State.ROLL`, ans Enum-Ende):**
- `start_roll(dir, duration)` — startet **oder verlängert** (weiterer Treffer
  während des Rollens → `_roll_min_time` wächst). Interrupt wie im Kampf
  (Arbeits-Claims, Angriff, Sitzen/Konvertierung), keine Befehle
  (`can_take_orders` false), Separation ausgesetzt (UnitManager).
- `_tick_roll`: folgt der **Falllinie** (`_downhill_vector`, zentraler
  Gradient), solange Hang > `ROLL_END_SLOPE 0,5`; auf flachem Boden endet die
  Mini-Rolle nach Ablauf. `ROLL_SPEED 5,5` (+40 % je Hangeinheit).
  **Wasser = Sofort-Tod**; Gebäudezellen stoppen die Rolle. **Rollschaden**
  `ROLL_DPS 5` — **Tod aufgeschoben** bis zum Rollende (auch bei externem
  Schaden während des Rollens, `take_damage`-Guard); `_end_roll` klemmt auf
  begehbare Zelle und stirbt/steht auf.
- **Roll-Animation:** 4 Frames (eingerollter Ball, heller Kopf-Block + dunkler
  Glieder-Block kreisen, 10 fps), alle Kinds, ohne Ausrüstungs-Overlays.

**Schubsen (Zusatzwunsch):** `_do_strike` → `_apply_shove`: Schubs
**verschiebt immer** leicht (`SHOVE_DISPLACE 0,35 m`, über das
Knockback-System → Kämpfe wandern, Angreifer rücken über ihre Ring-Slots
automatisch nach) und löst mit `SHOVE_ROLL_CHANCE 0,2` eine **Mini-Rolle
(0,35 s) auch auf ebenem Boden** aus; am Hang rollt sie bergab weiter.

**Feuerball-Rückstoß überarbeitet (Zusatzwunsch, `fireball.gd`):**
- **Schwächer:** `KNOCKBACK_BASE` 0,7 → **0,35**, `STACK_BONUS` 0,5 → 0,25.
- **Dafür Rollchance:** `ROLL_CHANCE 0,1` je Ball (viele Projektile → höhere
  effektive Chance); Ziel **rollt bereits** → `ROLL_CHANCE_ROLLING 0,4`
  (homende Folgetreffer **verlängern** die Rolle). Frischer Umwurf kann in
  engen Formationen **angrenzende Einheiten (0,9 m) mit 50 % mitreißen**
  (noch kürzere Rolle 0,22 s).

**Regeneration:** `_tick_regen` — nach `REGEN_DELAY 8 s` ohne Kampf
(weder ausgeteilt noch eingesteckt, kein Rollen) heilt `REGEN_RATE 2 HP/s`
bis `max_health`; jeder Treffer/Strike/Roll setzt den Timer zurück.

**Sterne-Overlay:** `≥ STARS_DAMAGE_THRESHOLD 12` Schaden binnen 1 s →
`stars_until_ms` (1,5 s). Neuer `StarsRenderer`
(`scripts/ui/stars_renderer.gd`, MultiMesh-Billboard-Quads, prozedurale
4-Frame-Textur mit 3 kreisenden Sternen, Alpha-Scissor, max. 256) über den
Köpfen; **HP wird nie angezeigt**.

**Kampf-Sounds:** `scripts/core/combat_audio.gd` — je Angriffsart
(punch/kick/shove/fireball) **3 prozedurale `AudioStreamWAV`-Varianten**
(gefilterte Rausch-Bursts, Art-spezifische Dauer/Glättung/Attack;
`generate_samples` statisch + deterministisch = headless-testbar). Pool aus
12 `AudioStreamPlayer3D` (positional), globale Drossel 45 ms. Anbindung über
neues Signal **`Events.combat_hit(kind, pos)`** (emittiert von `_do_strike`
und `Fireball._impact`, Events-Lookup geguardet/gecacht). StarsRenderer +
CombatAudio werden von `main.gd` in Code erzeugt (keine Szenen-Änderung).

**Rally → Ausbildung (Zusatzwunsch):** `Building.rally_training_building()`
(fertiges eigenes Trainingsgebäude, dessen Footprint den Rally-Punkt
enthält); `Hut._spawn_brave` schickt neue Braves dann per `order_train`
**direkt in die Ausbildungs-Warteschlange** statt zum Sammelpunkt.

**Erkenntnisse:**
- `take_damage` während ROLL darf nicht töten (aufgeschobener Tod) — der
  Guard sitzt in `take_damage` selbst, Rollschaden läuft daran vorbei
  direkt über `health`.
- Schubs-Verschiebung über das vorhandene Knockback-System (`displace`)
  spart einen zweiten Bewegungs-Mechanismus; `apply_knockback` ist jetzt
  ein dünner Wrapper darüber.

**Verifikation:** Testsuite grün (**435 Tests**, +36: Bergauf-Verlangsamung,
Mini-Rolle inkl. Befehlssperre/Ende/Anim, Roll-Verlängerung, Wasser-Tod,
aufgeschobener Tod, Schubs-Verschiebung, Regeneration inkl. Reset, Sterne
(schwer/leicht/tot), Audio-Sample-Daten (Varianten/Dauern), `roll` im
Atlas, Rally→Training inkl. Abschluss zum Krieger).
`--headless --import`/`--quit`/`--quit-after 240` fehlerfrei.
**Manuelle Prüfung durch Nutzer: ausstehend** (bergauf langsamer; Rollen an
Steilhängen/durch Schubs/Feuerball inkl. Ketten-Umwurf in Formationen und
Verlängerung durch Folgetreffer; Rollen ins Wasser tötet; Sterne bei viel
Schaden; Heilung außer Kampf; Sounds je Angriffsart; Hütten-Rally auf
Kaserne → Braves stellen sich zur Ausbildung an).

**Nachbesserung (Nutzerfeedback):**
- **Neue Sounds `throw`** (Feuerball-Abwurf, luftiger Whoosh, emittiert in
  `Firewarrior._throw_fireball`) und **`preach`** (weicher tonaler Chant
  175 Hz + Vibrato, alle 2 s solange der Prediger stehend channelt) — beide
  mit **nur einer Sound-Variante**; der Feuerball-Einschlag steht ebenfalls
  in `SINGLE_VARIANT_KINDS` (1 statt 3 Varianten). `generate_samples` um
  beide Kinds erweitert (`_generate_chant` für den tonalen Pfad).
- **Sterne:** verschwinden beim Tod sofort (`stars_until_ms = 0` in `_die()`
  zusätzlich zum `has_stars`-DEAD-Guard). **Versatz behoben:** Sterne sitzen
  jetzt entlang der **Kamera-Hochachse** über der Einheit statt Welt-Y — die
  Einheiten-Sprites sind kamerazugewandte Billboards, deren Kopf entlang
  Bildschirm-oben liegt; mit Welt-Y wirkten die Sterne bei geneigter Kamera
  versetzt.
- **Pausemenü: „Soundlautstärke"** — HSlider (0–100 %, 5er-Schritte) für den
  Master-Bus (`Sidebar._on_volume_changed`: `linear_to_db`, 0 % = Mute);
  sitzt zwischen „Fortsetzen" und „Beenden", sessionweit.
- Testsuite **438 grün** (Audio-Test um throw/preach + Ein-Datei-Regel
  erweitert).
- **Pausemenü: „Debugschlacht"** — lädt die Karte neu als Schlacht-Szenario:
  `GameState.debug_battle` (One-Shot-Flag, von `Main._ready` konsumiert) →
  statt Basen/Start-Braves/Sparring spawnen **zwei Armeen à 800 Einheiten**
  (70 % Krieger innen, 30 % Feuerkrieger in den hinteren Reihen; Ring-Füllung
  begehbarer Zellen) links/rechts der Inselmitte (±26 Zellen) und marschieren
  auf den jeweils gegnerischen Anker — Aggro übernimmt beim Kontakt. Blau
  (Stamm 0) bleibt spielersteuerbar. Headless-Funktionstest: 1600 Einheiten,
  600 Frames fehlerfrei.

**Manuelle Prüfung durch Nutzer: bestanden** („soweit erstmal in ordnung").
**Bekannt/offen für Phase 8: Performancethemen** (vom Nutzer beobachtet,
vermutlich Massenschlachten — Kandidaten: Kampf-Zielsuche/Slot-Kontention
bei Hunderten Kämpfern auf engem Raum, Projektil-/Roll-Massen, GPU-seitig
weiterhin die bekannten Punkte aus Phase 3e/3f). **Sub-Phase 5d und damit
Phase 5 KOMPLETT abgeschlossen** — als Nächstes Phase 6 (Schamanin,
Reinkarnation, Zauber).

---

## Phase 6 — Schamanin, Zauber, Panik/Schleuderphysik, Gebäudezerstörung (umgesetzt)

Plan wurde vor der Umsetzung überarbeitet (Nutzerwunsch 2026-07-06): Feuerball
statt Blast, neue Ladungs-/Schadenswerte relativ zum Brave-Leben (60 HP),
Schamanin-Kill-Bonus, drei neue Kernmechaniken. Details + dokumentierte
Auslegungen: [06_shaman_spells.md](06_shaman_spells.md).

**Spell-Framework (`scripts/spells/spell.gd`, `spell_context.gd`):**
- `Spell` (RefCounted): `id`, `display_name_de`, `charge_cost`, `max_charges`,
  `charges`, `charge_progress`; `execute(tribe, target, ctx) -> bool` (virtuell),
  `cast(...)` (verbraucht genau 1 Ladung nur bei Erfolg),
  `Spell.create_default_set()` (je Tribe eigene Instanzen; Kosten-Startwerte
  Feuerball 40 / Schwarm 50 / Blitz 60 / Landbrücke 60 / Tornado 90, Ladungen
  4/4/4/4/3 — Feinbalance Phase 8).
- **Aufladung in `Tribe.tick`** (`_convert_mana_to_charges`): Round-Robin über
  die kostensortierten Zauber, **der Zeiger wartet auf den teuren Zauber**
  (keine Aushungerung); alle voll → Mana sammelt sich. **Pip-Anzeige: es lädt
  immer genau EIN Zauber** (der am Zeiger), `charge_progress` = Mana/Kosten.
  Neu auf Tribe: `set_spells`, `get_spell`, `charge_capacity_mana`,
  `grant_bonus_mana` (sofortige Umwandlung); `tribe.shaman` wird in
  `add_unit`/`remove_unit` gepflegt (Tod → null). Neues Signal
  `Events.spell_charges_changed(tribe_id)`.
- `SpellContext` (RefCounted): TerrainData/NavGrid/UnitManager/BuildingManager;
  `apply_terrain_change(rect)` = NavGrid-Update + `Events.terrain_deformed`
  (Mesh/Kollision/Minimap über Main). **Abweichung vom Plan:** ctx hält keine
  Terrain-Node-Referenz — der Event-Weg existierte schon (3b) und hält die
  Minimap aktuell; der `HeightMapShape3D.map_data`-Check ist damit nur manuell
  prüfbar (headless testen TerrainData + NavGrid).
- `TribeCommands.cast_spell(tribe, spell_id, target)`: prüft Ladung + lebende
  Schamanin, delegiert an `Shaman.order_cast` — **die Ladung wird erst beim
  Auslösen verbraucht** (Schamanin läuft in Reichweite; Fehleffekt = Ladung
  bleibt). `TribeCommands.spell_context` von Main injiziert.

**Schamanin (`scripts/units/shaman.gd` + Szene):** 240 HP (4× Brave),
`melee_strength 2.0`, panik-/konvertierungsimmun, kein Auto-Aggro (wie Brave).
`order_cast` → `State.CAST`: `_approach` bis `CAST_RANGE 9 m`, Wind-up
`CAST_TIME 0,6 s` (Cast-Anim nur in Reichweite, sonst walk), dann
`Spell.cast`. Move-Order bricht den Cast ab (Ladung bleibt). **Kill-Bonus:**
`_die()` zahlt dem Stamm des `last_attacker` einmalig
`15 % × charge_capacity_mana()` als Bonus-Mana direkt in die Umwandlung; ohne
Attacker (Wasser) kein Bonus. Kind `shaman` in `UnitRenderer.KINDS` ergänzt
(Cast-Anim existierte seit Phase 2). Beide Start-Tribes bekommen Schamanin +
Reinkarnationsplatz (`main.gd`: `_place_site_near`/`_spawn_shaman_near`, auch
für Rot beim Sparring-Setup).

**Respawn (`reincarnation_site.gd`):** `_tick_active` zählt `respawn_timer`
(`RESPAWN_TIME 20 s`) nur solange die Schamanin tot ist, spawnt dann genau
EINE neue am Platzrand; `respawn_remaining()` für den Porträt-Countdown.
Läuft nur bei `is_usable()` → **beschädigter/zerstörter Platz respawnt nicht**
(erst nach Reparatur weiter).

**Gebäudezerstörung (`building.gd` + Subklassen):**
- `destruction_stage()` aus dem Schadensanteil (≥30/60/90 % → Stufe 1–3,
  0 HP → 4), `is_usable()` (fertig + Stufe 0) gate-t **alle** Produktion:
  Hütten-Spawn/-Kapazität, Training (inkl. `rally_training_building`,
  `order_train`, Brave-`_tick_train`), Respawn; `production_progress` → −1.
- `apply_destruction_stages(n)` = n × 30 % Max-HP (Blitz +2, Tornado +1/2 s).
- Übergang auf Stufe ≥ 1 ruft Hook `_on_disabled()`: **TrainingBuilding wirft
  den Trainee lebend wieder aus** (zurück in Registry/Welt + `cancel_training`,
  Population ±0) und entlässt die Warteschlange — `destroy()` tötet den
  Trainee weiterhin (Gebäude kollabiert).
- **Stufe 4:** `destroy()` sofort spielmechanisch (NavGrid-Footprint frei,
  Tribe/Manager-Abmeldung, ClickBody weg), das Wrack **versinkt visuell** über
  `_process` (`SINK_DURATION 2 s`, nur in-game) und `queue_free`t sich.
- **Schadens-Visual:** je Stufe erscheinen 2 dunkle „herausgebrochene“
  Klötze am Placeholder-Mesh (`_create_damage_holes`, deterministisch,
  Cache über `_visual_stage`) — echte Texturen können den Stufen-Hook nutzen.
- **Reparatur:** Holzkosten = `floor(Schadensanteil × wood_cost)`;
  `repair_wood`-Puffer wird wie beim Bau aus Stapeln am Eingang absorbiert
  (`_tick_repair_absorb`, inkl. `wood_stalled`-Recheck); `repair(amount)`
  schaltet Arbeit über den Puffer frei (1 Holz = `max_health/wood_cost` HP),
  der **abgerundete Rest repariert holzfrei** (deckt exakt die
  floor-Semantik); `wood_cost 0` (Reinkarnationsplatz) repariert gratis.
- **Brave-Task REPAIR** über das bestehende Job-System (`State.BUILD`):
  `order_repair` (Brave + TribeCommands), `_choose_repair_task` (Holz holen ↔
  hämmern ↔ `mark_wood_stalled`), gemeinsamer Helfer `_try_fetch_wood()`
  (aus dem Bau-Zweig extrahiert), `_job_wants_wood()` (Bau vs. Reparatur),
  `REPAIR_RATE 10 HP/s`. **Rechtsklick** auf eigenes beschädigtes Gebäude →
  Reparatur (SelectionManager; nutzbare Trainings-/Gebetsgebäude behalten
  ihre Funktion, solange Stufe 0).

**Schleuderphysik & Panik (`unit.gd`):**
- **THROWN:** `throw_airborne(velocity, fall_damage)` — skriptete Parabel
  (`THROW_GRAVITY 18`), kein Y-Snap, keine Befehle/Separation; Mehrfachwürfe
  stapeln. Landung: Wasser = Sofort-Tod, Gebäudezellen → nächste begehbare
  Zelle, Sturzschaden, dann **Momentum-Roll**.
- **ROLL erweitert:** `start_roll(dir, duration, initial_speed)` — Anfangs-
  geschwindigkeit klingt über `ROLL_FRICTION 6 m/s²` ab (Ende erst unter
  `ROLL_STOP_SPEED 1`), auf Ebenem schnelles Ausrollen, an Hängen übernimmt
  die 5d-Falllinie; Rollschaden/Wasser-Tod unverändert.
- **Träger-Mechanik für den Tornado:** `throw_carrier` (untypisiert) friert
  `_tick_thrown` ein, solange der Träger lebt; `fling_from_carry(velocity)`
  löst den Wurf; verschwindet der Träger, fällt die Einheit normal.
- **PANIC:** `start_panic(source, 6 s)` (Refresh bei erneuter Nähe),
  Zufallsflucht von der Quelle weg (Direkt-Wegpunkte, kein A*), keine Befehle
  (`can_take_orders` false, auch für THROWN), kein Zurückschlagen; Schamanin
  immun (`is_panic_immune`). Walk-Anim; THROWN nutzt die Roll-Anim.

**Zauber (`scripts/spells/…`):**
- **Feuerball** (`fireball_spell.gd` + `fireball_bolt.gd` — Name „Bolt“, weil
  `scripts/units/fireball.gd` das Feuerkrieger-Projektil ist): Projektil
  fliegt in flachem Bogen zum ZielPUNKT (kein Homing), Explosion: Direkt ≤
  0,8 m = 60, Fläche ≤ 2,5 m = 30; Überlebende werden im kleinen Bogen
  weggeschleudert (THROWN → Roll). Attacker = Schamanin (Vergeltung/Kill-Credit).
- **Landbrücke** (`landbridge.gd` + **`TerrainData.raise_line`**): breiter
  Korridor (Halbbreite 1,6 + 1,5 Blend) von der Schamanin zum Ziel, Profil
  lerp(Starthöhe→Zielhöhe), Wasserenden auf Küstenniveau (`SEA_LEVEL + 1,2`);
  **hebt nur an**, Rampe bleibt begehbar; danach `apply_terrain_change`
  (NavGrid + terrain_deformed, EIN Update pro Cast).
- **Blitz** (`lightning.gd`, innere Klasse `LightningBeam` als kurzer weißer
  Strahl): Gebäude am Klickpunkt (Footprint +1 gewachsen, da der Terrain-Ray
  neben den Wänden landet) → **+2 Stufen**; sonst nächste Feindeinheit ≤ 3 m
  → **240 Schaden** (tötet auch eine volle Schamanin exakt), Nachbarn ≤ 1,5 m
  → Mini-Rolle; kein Ziel → `execute` false (Ladung bleibt).
- **Schwarm** (`swarm.gd` + `swarm_cloud.gd`): 10 s Lebenszeit, Zufallsdrift
  1,5 m/s, alle 0,4 s Panik-Refresh (6 s) + **3 Schaden/s** an Feinden ≤ 3 m;
  Schamaninnen nur gegen die Panik immun.
- **Tornado** (`tornado.gd` + `tornado_vortex.gd`): 8 s, Drift 2,5 m/s;
  Gebäude unter dem Wirbel **+1 Stufe sofort bei Kontakt, dann alle 2 s**
  (sonst wären in 8 s nur 3 Stufen möglich — ein geparkter Tornado zerlegt
  ein Gebäude damit komplett). Feinde ≤ 2,2 m werden gefangen
  (`throw_carrier`), spiralen in 0,9 s zur Spitze (6 m), reiten 0,6 s mit und
  werden mit 12 m/s + Sturzschaden 30 weggeschleudert (Landung → Momentum-
  Roll); Ablauf/Despawn schleudert Rest-Reiter ab.
- **Alle Schadens-/Kontrollzauber treffen nur Feinde** (dokumentierte
  Auslegung im Plan).

**UI (`spell_targeting.gd` neu, `sidebar.gd`, `selection_manager.gd`,
`ui_theme.gd`, `main.tscn`):**
- `SpellTargeting` (Control im UI-Layer, analog BuildMenu): goldener
  Ring-Cursor am Terrain, Hotkeys 1–5 togglen (`cast_spell_1..5`, Reihenfolge
  = `default_spell_entries`), Linksklick → `cast_spell` (Erfolg beendet den
  Zielmodus), Esc/Rechtsklick bricht ab; startet nur mit Ladung + lebender
  Schamanin; BuildMenu und Zielmodus schließen sich gegenseitig aus;
  SelectionManager ignoriert Eingaben solange aktiv; Esc-Priorität vor dem
  Pausemenü (Sidebar-Guard).
- Sidebar: `default_spell_entries` auf **Feuerball**/4-4-4-4-3 umgestellt
  (Icon-Key `blast` → `fireball`, Flammen-Icon), Buttons feuern
  `toggle_targeting`; `_refresh_spells` (throttled + `spell_charges_changed`)
  füttert `set_spell_state` (castable = Ladung > 0 UND Schamanin lebt).
  **Porträt aktiv:** Klick selektiert die Schamanin + springt mit der Kamera
  hin; tot → disabled mit **Respawn-Countdown** („12s“ bzw. „tot“ ohne Platz).
  Gefolgsleute-Zeile „Schamanin“ aktiv.
- `UnitManager.register_projectile` hängt Projektile jetzt **immer** als Kind
  ein (vorher nur in-tree): headless werden sie mit dem Manager freigegeben
  (Leak-Fix — `queue_free` läuft im Testrunner nie), `_ready`/Visuals laufen
  weiterhin nur in-game.

**Erkenntnisse/Stolpersteine:**
- `queue_free` außerhalb des Szenenbaums wird im Testrunner nie ausgeführt →
  Projektile leakten, bis sie Kinder des UnitManagers wurden.
- Tornado-Stufentakt: „alle 2 s“ ab Kontakt gerechnet (erster Schlag sofort),
  sonst schafft die 8-s-Lebenszeit nur 3 der 4 Stufen.
- Der Round-Robin-Zeiger darf nach einer Umwandlung NICHT auf den billigsten
  zurückspringen — er wartet am teuren Zauber, sonst verhungert dieser.
- Reparatur-Floor-Semantik sauber über „Puffer + holzfreier Rest“: 90 %
  Schaden an der 15-Holz-Hütte kosten exakt 13 Holz, Vollreparatur inklusive.

**Verifikation:** Testsuite grün (**627 Tests**; neu: `test_spells.gd` 124,
`test_building_destruction.gd` 48, `test_shaman_respawn.gd` 17 — Framework/
Round-Robin/Kill-Bonus/Cast-Flow, alle 5 Zaubereffekte inkl. Landbrücken-Rampe
und Wasser-Tod, Stufen/Reparatur/Trainee-Auswurf, Respawn inkl. beschädigter
Platz). `--headless --import`, `--headless --quit` und `--quit-after 240`
fehlerfrei. **Manuelle Prüfung durch Nutzer: ausstehend** (siehe Plan §Manuelle
Prüfung: Zauber-Tab/Pips/Hotkeys, Landbrücke im Live-Spiel inkl. Raycast auf
neuer Höhe, Feuerball-Bogen, Blitz auf Gebäude + Reparatur per Rechtsklick,
Schwarm-Panik, Tornado inkl. Hochwirbeln/Versinken, Schamanin-Tod →
Ladungsschub beim Gegner → Respawn-Countdown im Porträt).

**Nachbesserung (Nutzerfeedback, erste Runde):**
- **Landbrücke terraformt graduell:** neuer `LandbridgeMorph`
  (`scripts/spells/landbridge_morph.gd`, läuft über die Projektil-Liste):
  interpoliert die betroffenen Vertices über **3 s** (smoothstep, Schritte
  alle 0,15 s — nie pro Frame) von Start- zu Zielprofil;
  `TerrainData.line_raise_targets` (pur, ohne Schreiben) von `raise_line`
  abgespalten. **Requisiten reiten mit:** Bäume und Holzstapel im Rechteck
  werden je Schritt auf die neue Bodenhöhe gesnappt, Gebäude auf ihre
  Footprint-Mitte neu gesetzt (Einheiten snappen ohnehin pro Tick);
  `SpellContext` dafür um `tree_manager`/`wood_pile_manager` erweitert.
- **Zauber-Reichweiten pro Zauber** (`Spell.cast_range`, Schamanin nutzt sie
  statt der festen 9 m): Feuerball **8 m**, Blitz **10 m**, Tornado **8 m**,
  Schwarm 8 m, Landbrücke 9 m (bleibt).
- **Reichweiten-Ring im Zielmodus:** `SpellTargeting` zeigt beim Anwählen
  eines Zaubers einen hellblauen Ring mit `cast_range`-Radius **um die
  Schamanin**, folgt ihr pro Frame; Zielen außerhalb bleibt erlaubt (sie
  läuft hin). Stirbt sie während des Zielens, bricht der Modus ab.
- **Startszenario:** alle Zauber beginnen mit **1 Ladung** (beide Tribes,
  KI-symmetrisch).
- **Tornado-Optik:** Trichter jetzt aus 11 statt 5 Ringen (dichter, breiter).
- **Schamanin-Sprite weiblich/unverwechselbar:**
  `PlaceholderSprites._decorate_shaman` — langes **dunkles Haar** (Krone +
  Strähnen bis zu den Schultern, volle Mähne von hinten) und das **hellste
  Kleid im Spiel**, das ab dunklem Gürtel dreieckig bis zu den Knöcheln
  ausschwingt (Silhouette + stärkster Hell/Dunkel-Kontrast, da der Renderer
  mit der Stammfarbe multipliziert).
- Tests angepasst/ergänzt (Brücke erst nach Morph begehbar, Anstieg zur
  Halbzeit messbar, Holzstapel reitet mit, Cast-Reichweite aus dem Spell):
  Suite **630 grün**, Ladecheck + `--quit-after 240` fehlerfrei.
  **Manuelle Prüfung: ausstehend.**

**Nachbesserung (Nutzerfeedback, zweite Runde):**
- **Landbrücke planiert jetzt statt nur anzuheben:** Der Korridor wird auf
  die **gerade Linie Starthöhe→Zielhöhe gestuft** — Senken werden gefüllt
  UND Erhebungen abgetragen (`line_raise_targets` lerpt zur Profillinie
  statt `maxf`). Damit entsteht auch auf Land eine glatte begehbare Rampe
  (z. B. durch einen zu steilen Grat); ist die Strecke schon gerade, ändert
  sich nichts und der Cast schlägt fehl (Ladung bleibt). Wasserenden werden
  weiterhin auf Küstenniveau geklemmt (nie unter die Seelinie planiert).
- **Einheiten reiten mit dem Morph:** `LandbridgeMorph._snap_props` snappt
  jetzt auch **Einheiten** im Rechteck pro Schritt auf die neue Bodenhöhe
  (stehende Einheiten aktualisieren ihr Y sonst nie — sie versanken im
  wachsenden Boden, bis man sie bewegte); geworfene (THROWN) fliegen weiter.
- **Tornado-Bewegungsprofil:** parkt **1 s** am Zielpunkt, kriecht dann los
  (0,4 m/s) und beschleunigt über 4 s auf **max. 2,0 m/s** (vorher konstant
  2,5); `_drift` ist jetzt eine reine Richtungs-Einheit.
- **Blitz gezackt:** `LightningBeam` besteht aus 7 dünnen Zylinder-Segmenten
  entlang einer gezackten Polylinie (seitlicher Jitter je Knick, Einschlag-
  punkt exakt) statt eines geraden Strahls.
- **Schamanin-Figur:** schmalere Taille — der gemeinsame Torso wird an den
  Seiten transparent „abgeschnürt“ (Sanduhr-Silhouette), Haare/Gürtel/Kleid
  darüber.
- Neuer Test: Land-Cast planiert einen unbegehbaren Grat zur begehbaren
  Geraden. Suite **643 grün**, `--quit-after 240` fehlerfrei.
  **Manuelle Prüfung: ausstehend.**

**Erweiterung (Nutzerwunsch): Populous-Stil-Schamanin-Porträt.**
- Neues Porträt-Panel **unter der Minimap, über den Menü-Tabs**
  (`Sidebar._build_shaman_portrait`): zeigt die **ganze Figur live animiert**
  (AnimatedSprite2D mit `PlaceholderSprites.make_frames("shaman")`,
  Frontansicht, 3×-Pixelskalierung, Stammfarbe via modulate; die Animation
  spiegelt `shaman.anim_base_name` im 0,3-s-Refresh), darunter ein grüner
  **Lebensbalken** und eine Statuszeile. Tot → Leichen-Pose +
  „Wiederkehr in N s" (bzw. „Keine Wiederkehr" ohne Platz).
- **Klick aufs Porträt:** Kamera zentriert auf die Schamanin und **nur sie
  ist selektiert** (`select_units([shaman])` ersetzt die komplette Auswahl
  inkl. Gebäude-Abwahl).
- Der bisherige kleine Porträt-Button im Kopfbereich ist ersatzlos entfallen
  (Countdown lebt jetzt im großen Porträt).
- **Fenstergröße:** `display/window/size` auf **1280×800** gesetzt — mit dem
  Godot-Default (1152×648) wäre die höhere Sidebar unten übergelaufen (sie
  war schon vorher praktisch voll).
- Suite 643 grün, `--quit-after 240` fehlerfrei (Porträt baut auch headless).

**Manuelle Prüfung durch Nutzer: BESTANDEN** („ok, passt" — Zauber, Landbrücke,
Tornado, Blitz, Schamanin-Sprite, Porträt). **Phase 6 abgeschlossen**,
Checkbox in der Overview abgehakt.

**Nachtrag (Nutzerwunsch): Debugschlacht + Attack-Move.**
- **Attack-Move (Verhaltensänderung, gilt überall):** Kampfeinheiten scannen
  jetzt auch im MOVE-State (gedrosselt, `Unit._engage_on_sight` — von IDLE
  und MOVE genutzt) und greifen Feinde im Aggro-Radius an, statt durch die
  gegnerische Armee hindurchzumarschieren. Der Prediger überschreibt den
  Hook (Konvertieren vor Prügeln, wie sein Idle-Verhalten); Braves bleiben
  passiv (nur Vergeltung). Damit kämpfen die Debugschlacht-Armeen beim
  Aufeinandertreffen, statt aneinander vorbeizulaufen. Bewusste Konsequenz:
  auch spielerbefohlene Märsche von Kampfeinheiten enden im Kampf, wenn
  Feinde auf dem Weg stehen (Rückzug erst außerhalb des 8-m-Radius).
- **Debugschlacht mit Schamaninnen:** beide Armeen bringen ihre Schamanin
  hinter der Front mit (`_spawn_debug_shaman`), **alle Zauber voll geladen**
  (max_charges) für Zaubertests in der Massenschlacht.
- Neuer Test `test_marching_combatants_engage_on_contact`; Suite **644 grün**.

---

## Phase 7 — Hauptmenü, Multi-KI & Siegbedingungen (umgesetzt)

Plan: [07_ai_win_conditions.md](07_ai_win_conditions.md) (vor der Umsetzung um
Hauptmenü/Multi-KI erweitert; Steuerungs-/Verhaltenspunkte ausgegliedert nach
[07b](07b_unit_control_behavior.md)).

**Match-Konfiguration & Hauptmenü:**
- `scripts/core/match_config.gd` — `MatchConfig` (RefCounted): `mode`
  (SKIRMISH / START_MISSION / DEBUG_BATTLE), `ai_count` (1–3, geklemmt),
  `map_id` (nur `"island"`), `tribe_count()`. Gehalten in
  `GameState.match_config`; **ersetzt das alte One-Shot-Flag
  `GameState.debug_battle`** (Sidebar-Debugschlacht setzt jetzt
  `match_config = MatchConfig.debug_battle()` und lädt neu).
- `scenes/ui/main_menu.tscn` + `scripts/ui/main_menu.gd` — **neue Hauptszene**
  (`project.godot run/main_scene`): Vollbild-Control mit drei Code-gebauten
  Seiten in UiTheme-Optik — Hauptseite („Neues Skirmish", „Startmission",
  „Debugschlacht", „Optionen", „Beenden"), Skirmish-Setup (OptionButtons:
  1–3 KIs, Karte) und Optionen (Master-Lautstärke). `start_match` über
  `_launch(config)` → `change_scene_to_file(main.tscn)`.
- `scripts/core/audio_settings.gd` — `AudioSettings` (statisch):
  `master_volume_percent()` / `set_master_volume_percent()`; gemeinsame
  Quelle für Menü-Optionen UND Pausemenü (dort Duplikat entfernt).
- **Pausemenü ergänzt:** Button „Hauptmenü" (verlässt das Match →
  `GameState.reset()` + Szenenwechsel).
- `Main._ready()` konsumiert `GameState.match_config`; **ohne Config
  (Direktstart von main.tscn, Tests, Headless-Checks) Fallback =
  Startmission** — bisheriges Verhalten, Ladecheck bleibt grün.

**Multi-KI-Skirmish (bis 4 Spieler):**
- `Main` erzeugt **exakt `config.tribe_count()` Tribes** (statt fix 4);
  Startmission/Debugschlacht laufen wie bisher mit 2.
- `_setup_skirmish()`: je Tribe ein **identisches Starterkit** (kein Cheat):
  Reinkarnationsplatz + Schamanin + vorgebaute Hütte + 20 Start-Braves +
  **16 garantierte große Bäume im Umkreis** (`_ensure_trees_near`; eine
  volle Basis braucht ~65 Holz — mit 10 Bäumen stallten die
  Trainingslager-Baustellen im Sim-Lauf). Basen-Anker gleichmäßig auf einem
  **Kreis (Radius 26 Zellen)** um die Inselmitte (2 = gegenüber, 3 = Dreieck,
  4 = Quadranten), Spieler im Süden; Kamera startet über der Spielerbasis.
  `_spawn_start_units` generalisiert zu `_spawn_braves_near(tribe_id, …)`.
- **Ein `AIController` pro KI-Tribe** (Kind von Main, unabhängige Instanzen).

**Skirmish-KI (`scripts/ai/`):**
- `ai_state.gd` — `AIState`: reine State-Machine (`BUILD/TRAIN/ATTACK`),
  `next_state(state, snapshot)` mit Schwellwerten (3 Hütten + 3 Lagerarten +
  Pop ≥ 18 → TRAIN; Armee ≥ 12 + Schamanin lebt → ATTACK; Armee < 4 oder
  Schamanin tot → Rückfall TRAIN/BUILD; Gebäudeverlust → BUILD) und
  `next_training_kind()` (größtes Defizit ggü. Mix 50 % Krieger / 30 %
  Feuerkrieger / 20 % Prediger). Snapshots sind Dictionaries → headless
  testbar ohne Szenenbaum.
- `ai_controller.gd` — `AIController` (Node): tickt **1×/s** (Akkumulator,
  `tick_ai()` direkt aufrufbar), handelt **ausschließlich über
  TribeCommands**. BUILD: **eine Baustelle zugleich** (Arbeiter rekrutiert
  der BuildingManager selbst), Reihenfolge Hütten → Kaserne → Feuertempel →
  Tempel, Ringsuche um den Basis-Anker via `can_place_at`. Immer: 4 Braves
  beten am Platz (`_keep_praying`). TRAIN: 2 Braves/Tick ins Defizit-Lager,
  **Mindest-Wirtschaftscrew 8 Braves**. ATTACK: Armee + Schamanin per
  `order_move` (Attack-Move greift unterwegs) aufs **nächste Feindgebäude**
  (Fallback nächste Feindeinheit), Order nur alle 4 Ticks (Pfad-Thrash);
  Zauber-Heuristik: Blitz auf feindliche Schamanin → **Blitz auf nächstes
  Feindgebäude in Scanreichweite** → Feuerball auf dichtesten
  Einheiten-Cluster (≥ 4 in 3 m). Statuswechsel werden geloggt (`print`),
  Detail-Log über User-Arg `ai-log`.
- **Wichtige Erkenntnis:** Normale Einheiten können Gebäude NICHT angreifen —
  Gebäudezerstörung geht nur über Zauber. Ohne die Gebäude-Blitz-Heuristik
  konvergierte kein KI-Match (Armee tötete Einheiten, Hütten spawnten nach).

**Siegbedingung & Endscreen:**
- `game_state.gd`: Signale `tribe_defeated(tribe_id)` / `match_ended(winner_id)`,
  `start/stop_win_tracking()` (Main aktiviert es NACH dem Basenaufbau;
  Debugschlacht = Sandbox ohne Tracking), gedrosselte Prüfung (1 s) in
  `_process` + öffentliches `check_defeats()`; `match_over`-Flag.
- **`is_tribe_defeated` (statisch):** keine lebende Einheit UND kein
  **nutzbares** spawnfähiges Gebäude. **Abweichung vom Planwortlaut:** nur
  Hütte/Reinkarnationsplatz zählen als spawnfähig, Trainingsgebäude NICHT —
  sie brauchen einen lebenden Brave; ein Stamm mit 0 Einheiten und leerer
  Kaserne könnte sonst nie besiegt werden (Match hinge fest). Beschädigte
  (Stufe ≥ 1) und Baustellen-Gebäude retten ebenfalls nicht (niemand kann
  reparieren/fertigbauen). Die gedrosselte Prüfung deckt auch reine
  Schadensereignisse ab (Tornado macht letzte Hütte unbrauchbar, ohne dass
  ein Event feuert).
- **N-Tribes:** besiegte KIs scheiden aus, das Match läuft weiter; Ende erst
  wenn **nur ein Stamm übrig** ist (Sieg, falls Spieler) oder der
  **Spieler-Tribe fällt** (sofortige Niederlage). Keine Diplomatie.
- `scripts/ui/end_screen.gd` — `EndScreen`: Vollbild-Overlay „Sieg!" /
  „Niederlage" + „Zurück zum Menü" / „Beenden", pausiert das Spiel
  (`process_mode = ALWAYS`). **Abweichung:** als Code-Node in `main.tscn`
  (Muster BuildMenu/SpellTargeting) statt eigener `.tscn`.

**Headless-Testhooks (User-Args nach `--`):** `skirmish=N` (Menü überspringen,
Skirmish mit N KIs sofort starten), `ai-player` (auch Tribe 0 bekommt einen
AIController → KI-gegen-KI-Integrationslauf), `ai-log` (Statuszeile je KI
alle 60 Ticks). Beschleunigt mit `--fixed-fps 60 --quit-after <frames>`:

```powershell
& $GODOT --path D:\game\Populous-TheEnd --headless --fixed-fps 60 `
  --quit-after 108000 -- skirmish=1 ai-player ai-log   # 30 min Spielzeit
```

**Verifikation:**
- Testsuite grün (**692 Tests**, +48 in `tests/test_ai.gd`: State-Übergänge,
  Trainings-Mix, **Symmetrie/kein Cheat** (ungültige Platzierung ohne
  Seiteneffekt, Cast ohne Ladung/Schamanin schlägt fehl, Ladung bleibt),
  BUILD-Tick (platziert genau eine Baustelle via TribeCommands + 4 Beter),
  TRAIN-Tick (2 Braves in der Lager-Queue, Wirtschafts-Mindestcrew),
  Siegbedingung (Einheit/Hütte/Site/Kaserne-Fälle), N-Tribe-Ende (1 von 3
  besiegt → läuft weiter; Sieg; Spieler-Niederlage), MatchConfig-Klemmen.
  `game_state.gd` wird dafür als Skript instanziert (Autoloads fehlen im
  Runner).
- `--headless --import`, `--headless --quit` (lädt jetzt das Hauptmenü) und
  `main.tscn` direkt (`--quit-after 240`, Fallback Startmission) fehlerfrei.
- **KI-gegen-KI-Simulationsläufe** (fixed-fps): 1v1 über 30 min Spielzeit →
  beide KIs bauen (3 Hütten + 3 Lager), trainieren, greifen an, fallen nach
  Verlusten zurück; am Ende **genau ein `tribe_defeated` + `match_ended`**
  (Basis per Blitz zerlegt). 4-Spieler-Lauf (3 KIs + KI-Spieler, 25 min):
  alle vier Basen wachsen, mehrere Angriffs-/Rückfall-Zyklen, fehlerfrei.
- **Beobachtung:** Beim harten Exit (`--quit-after`) mitten im Kampf meldet
  Godot 4–11 geleakte ObjectDB-Instanzen; bei ruhigen Läufen nicht.
  Vermutlich vorbestehend (Kampf-/Wurfobjekte, Phase 5/6) — für Phase 8
  notiert, kein Gameplay-Einfluss.

**Manuelle Prüfung durch Nutzer: AUSSTEHEND** — Menü-Flow (Skirmish-Setup
1–3 KIs, Startmission, Debugschlacht, Optionen/Lautstärke, Beenden),
komplettes Match gegen 1 KI (KI baut/trainiert/greift an, Zauber), beide
Endscreens (Sieg/Niederlage → „Zurück zum Menü"), 4-Spieler-Match flüssig.

**Nachbesserung (Nutzerfeedback, erste Runde):**
- **Hauptmenü zentriert:** Die Seiten-Panels liegen jetzt in einem
  `CenterContainer` (voller Rect) statt `PRESET_CENTER` auf dem Panel —
  mit dem Anchor-Preset allein wuchs das nachträglich befüllte Panel vom
  Bildschirmmittelpunkt nach rechts unten (sichtbar außermittig, v. a. im
  Fenstermodus).
- **KI baut parallel:** bis zu **3 Baustellen gleichzeitig** (1 je 8 Braves,
  `BRAVES_PER_SITE`/`MAX_PARALLEL_SITES`); `_next_building_scene` zählt
  **geplante** Gebäude (inkl. Baustellen), sonst überbaut der Parallelbau.
  Reihenfolge: 1. Hütte → **Kaserne** (frühes Training) → restliche Hütten →
  Feuertempel → Tempel. **Bauen läuft jetzt in JEDEM State** (auch
  TRAIN/ATTACK — die Basis wird im Hintergrund vollendet).
- **Früher angreifen:** TRAIN ab 2 Hütten + 1 Lager + Pop 12 (vorher
  3/3/18), ATTACK ab **Armee 8** (vorher 12); TRAIN läuft im ATTACK weiter
  (Nachschub marschiert mit der nächsten Order zur Front). Rückfall zu BUILD
  nur noch bei Verlust der Essentials (keine Hütte/kein Lager).
- **Voller Einheitenmix:** `AIState.training_kind_order` (Defizite sortiert);
  `_tick_train` vergibt den Batch (jetzt 3/Tick) **rotierend** über die
  Defizit-Reihenfolge und weicht auf vorhandene Lager aus — Krieger,
  Feuerkrieger UND Prediger werden trainiert, sobald ihre Gebäude stehen.
- **Zauber jeden Tick:** `_cast_spells` läuft in jedem State (vorher nur im
  ATTACK — beim Überfall aufs eigene Dorf castete die Schamanin nie);
  Feuerball-Cluster ab 3 Feinden (vorher 4).
- **Verteidigung:** `_detect_threat` (Feinde im 32-m-Radius um den
  Basis-Anker) hat Vorrang vor dem Angriff: Armee + Schamanin rücken aus
  (Attack-Move), **Braves als Miliz** (expliziter `order_attack` — Braves
  haben kein Aggro) nur wenn die Kerntruppe unterlegen ist.
  **Chancen-Heuristik:** verteidigt nur, wenn eigene Kampfkraft
  (Armee + 4×Schamanin + 0,5×Miliz-Brave) ≥ 0,4 × Feindzahl — sonst kein
  Suizid-Ausfall, die Schamanin castet aus der Basis weiter.
- **Holzstapel nur noch im eigenen Dorf:** `WoodPileManager.nearest_pile`
  um `within_pos/within_radius` erweitert; `Brave._try_fetch_wood` zählt
  Stapel nur noch im **`JOB_TREE_RADIUS` (40 m) um die Baustelle** (gleicher
  Radius wie die Baumsuche) — ein Stapel quer über die Insel oder in der
  Gegnerbasis lockt keine Arbeiter mehr weg. Gilt für Spieler UND KI.
- Tests: **704 grün** (+12: neue Übergangs-Schwellwerte, Parallelbau-Deckel
  inkl. Kaserne-nach-erster-Hütte, Miliz-Verteidigung, Hoffnungslos-Fall
  ohne Suizid, Stapel-Radius nah/fern, `training_kind_order`).
- Sim-Läufe: 1v1 entschieden **innerhalb 20 min Spielzeit** mit mehreren
  Angriffs-/Verteidigungszyklen (vorher: TRAIN erst nach ~10 min, Sieg nach
  ~25+); 4-Spieler-Lauf fehlerfrei (ein Stamm eliminiert, Match lief
  korrekt weiter).

**Nachbesserung 2 (Nutzerwunsch): Zeitraffer statt langer Sim-Läufe.**
- **Zeitraffer im Spiel (Taste F10):** zykliert **1× → 10× → 100×**
  (`Main._cycle_time_scale`, Input-Action `time_scale_toggle`).
  `Engine.time_scale` + angehobenes `max_physics_steps_per_frame`
  (`clampi(faktor*4, 8, 120)`), damit die Simulation (läuft in
  `_physics_process`-Ticks) der skalierten Uhr wirklich folgt; der Deckel
  hält Frames kurz genug, dass F10 zum Zurückschalten bedienbar bleibt.
  Konsole meldet den aktiven Faktor. Jedes Match startet auf 1×
  (`Main._ready`), das Hauptmenü setzt ebenfalls zurück.
- **Ehrliche Grenze:** Bei 100× rechnet die Engine so viele
  Simulationsschritte pro Frame wie die CPU hergibt — real erreicht werden
  je nach Einheitenzahl **~10–30×** (Anzeige wird ruckelig, Simulation
  bleibt korrekt). Ein echter 100×-Durchsatz ist nicht möglich, weil jeder
  Tick gerechnet werden muss — auch headless laufen die Sim-Läufe bereits
  am CPU-Limit (~4–5× Echtzeit bei großen Schlachten).
- **Konsequenz für die Verifikation:** Die langen headless
  KI-gegen-KI-Läufe (5–6 min Wall-Time) sind **kein
  Standard-Verifikationsschritt mehr** — nur noch optional bei
  KI-Umbauten. Standard bleibt die Testsuite (~10 s) + Ladecheck; das
  Match-Verhalten testet der Nutzer manuell (jetzt mit F10-Zeitraffer).

**Nachbesserung 3 (Nutzerfeedback): Baustellen-Zerstörung, KI-Skalierung,
Wellen, alle Zauber.**
- **Baustellen sind fragil (Bugfix „unzerstörbare Fundamente"):** Ursache
  war zweiteilig: (1) Ein Blitz machte nur Teilschaden an der Baustelle,
  die Arbeiter bauten die beschädigte Baustelle einfach **fertig** (der
  Baufortschritt ignoriert health); (2) die KI platzierte zerstörte
  Baustellen im nächsten Tick am selben Plot neu → wirkte unzerstörbar.
  Fixes: `Building.apply_destruction_stages` **zerstört Baustellen sofort**
  (ein Stufen-Zaubertreffer = weg); `destroy()` setzt `under_construction
  = false` (sonst hielten Arbeiter am Wrack fest — `_job_active` — und
  `finish_construction` hätte das Wrack wiederbeleben können); die KI hat
  einen **Wiederaufbau-Cooldown von 15 s** nach jedem Gebäudeverlust
  (`Events.building_destroyed` → `_rebuild_ticks`, guarded für headless).
- **Endlose KI-Skalierung:** Nach dem Grundausbau (3 Hütten + 3 Lagerarten)
  baut die KI **für immer weiter**: neue Hütte bei **Bevölkerung ≥ 80 %
  der Kapazität** (`HOUSING_PRESSURE`), ein **zusätzliches Lager je 2
  weitere Hütten** (`HUTS_PER_EXTRA_CAMP`, Art mit den wenigsten
  Gebäuden). Bei mehreren Lagern einer Art trainiert das mit der
  **kürzesten Warteschlange** (Durchsatz für große Wellen).
- **Holznähe + Expansion:** Plots gelten nur mit **≥ 3 Bäumen im
  22-m-Umkreis** als versorgt (`_find_supplied_plot`, max. 40 Kandidaten);
  gibt es um die Basis keinen versorgten Plot mehr, **expandiert** die KI
  zum nächstgelegenen Baumbestand (`_expansion_anchor` via
  `TreeManager.nearest_tree`) und schickt **6 Idle-Braves als Eskorte**
  mit (der BuildingManager rekrutiert nur im ~30-m-Radius der Baustelle) —
  relevant für größere Karten.
- **Graduell größere Angriffe:** `attack_wave_size` startet bei 8 und
  wächst nach **jeder beendeten Welle um +4 (Deckel 40)**; der dynamische
  Schwellwert läuft als `army_target` im Snapshot in
  `AIState.next_state` ein.
- **Alle Kampfzauber in der Heuristik** (`_cast_spells`, ein Cast/Tick,
  ohne Ladung fällt die Priorität durch): 1. Blitz auf feindliche
  Schamanin → 2. Feindgebäude: **Tornado** (zerlegt stufenweise), Fallback
  Blitz → 3. **Schwarm** auf Gruppen ≥ 5 Feinde (Panik) → 4. Feuerball
  auf Cluster. Landbrücke bleibt bewusst außen vor (kein sinnvolles
  KI-Ziel ohne Pfadanalyse).
- Tests: **719 grün** (+15: fragile Baustelle inkl. „fertige Gebäude
  weiter stufenweise", Wellenwachstum inkl. `army_target`-Übergänge,
  endlose Skalierung (Camp-Ziel wächst mit Hütten, Housing-Pressure),
  Expansion zum entfernten Wald).

---

## Phase 7b — Steuerung & Einheitenverhalten (umgesetzt)

Plan: [07b_unit_control_behavior.md](07b_unit_control_behavior.md).

**1. Move/Attack-Split (`unit.gd`, `tribe_commands.gd`, `selection_manager.gd`):**
- `Unit.move_aggressive` (gesetzt von `order_move(target, queue_up,
  aggressive)`; Signatur auch auf Brave/Schamanin/TribeCommands erweitert):
  **passiver Move** (Default) marschiert an Feinden vorbei — `_tick_move`
  ruft `_engage_on_sight` nur noch bei `move_aggressive`. **Attack-Move**
  = bisheriges Verhalten (Kämpfer greifen unterwegs an).
- **Tastenbelegung wie abgestimmt:** Rechtsklick = passiver Move; Taste
  **A** schärft den Attack-Move (`attack_move_arm`, nur mit Selektion),
  der nächste Rechtsklick löst ihn aus; **roter Fadenkreuz-Cursor +
  „Angriff"-Label** solange geschärft; Esc bricht ab (Vorrang vor dem
  Pausemenü, Sidebar-Guard). Geschärfter Attack-Move überspringt
  Kontextbefehle (Fällen/Bauen/Beten) — er ist immer ein Marschbefehl.
- **A-Konflikt mit WASD-Kamera gelöst:** `SelectionManager.attack_arm_active`
  ist statisch (Muster `drag_active`); das CameraRig unterdrückt den
  Links-Pan solange geschärft. Ohne Selektion bleibt A reines Kamera-Pan.
- **KI & Debugschlacht** marschieren jetzt explizit aggressiv
  (`order_move(..., true)` in AIController-Angriff/-Verteidigung und im
  Debugschlacht-Setup); Rally-/Eskorten-Läufe bleiben passiv.

**2. Fliehen (`unit.gd`):** Ein passiver Move bricht den Kampf sofort ab
(`_end_attack`). **Rückfall-Regel deterministisch:** Während der Flucht
zählt nur Nahkampfdruck (Angreifer ≤ `FLEE_MELEE_RANGE` = 1,5×
Nahkampfreichweite); jeder **3. Treffer** (`FLEE_RETALIATE_HITS`) zwingt
die Einheit zurück in den Kampf (Selbstverteidigung). Fernbeschuss bricht
eine Flucht nie. `_flee_hits` wird je Move-Befehl zurückgesetzt.

**3. Brave-Idle-Aggro 3 m (`brave.gd`, `unit_manager.gd`):** Braves
greifen im Leerlauf Feinde im **3-m-Radius** an (`Unit.idle_aggro`-FELD,
von Brave im `_init` gesetzt — bewusst kein virtueller Getter, s.
Performance unten). Der Wach-Scan läuft im geslicten Manager-Pass
(~1 Prüfung/s je Einheit), nicht im Unit-Tick.

**4. Idle-6er-Grüppchen (`unit_manager.gd`):** Einheiten, die
`IDLE_REGROUP_DELAY` (2,5 s) untätig sind, **driften** mit Mini-Schritten
(max. 0,25 m je Durchgang) zum Zentrum von bis zu 5 idle Stammesgenossen
im 2,2-m-Radius; unter 0,5 m Abstand steht das Grüppchen still (die
Separation hält den 0,44-m-Mindestabstand dagegen → lockere 6er-Pulks wie
beim Original). `UnitManager.regroup_step` ist pur/testbar;
`Unit.idle_seconds` zählt der Manager-Pass hoch (Reset bei jedem
Statewechsel).
- **Gemeinsamer geslicter Idle-Pass** (`_apply_idle_regroup`): jede
  Einheit kommt ~1×/s dran (`IDLE_REGROUP_SPREAD_TICKS` 30) — Wach-Scan +
  idle_seconds + Drift, ohne den heißen Unit-Tick anzufassen.

**5. Anti-Stacking (`unit_manager.gd`):** Die Separation zählt jetzt
„eng gestapelt" (< 35 % des Separationsradius) pro Einheit
(`Unit.overlap_ticks`); wer `OVERLAP_ESCAPE_PASSES` (8) Durchgänge
eingekeilt bleibt und IDLE ist, bekommt per `find_free_cell_near`
(Ring-Suche: begehbar + < 2 Einheiten in 0,6 m) einen **echten
Ausweich-Move** auf eine freie Zelle.

**6. Warteschlangen-Windungen (`training_building.gd`):**
`queue_slot_world` verbraucht die Slot-Distanz **Windung für Windung**:
ist eine Runde ums Gebäude voll (Umfang der aktuellen Windung), läuft die
Schlange auf der nächsten Windung 1 m weiter außen weiter (max. 3
Windungen) — die Schlange wickelt sich ums Gebäude statt sich am
Clamp-Punkt zu knäueln.

**7. Doppelklick-Typselektion (`selection_manager.gd`):** Doppelklick auf
eine eigene Einheit selektiert **alle eigenen Einheiten desselben
`unit_kind()` im Sichtfenster** (Sprite-Rect gegen Viewport);
`filter_units_of_kind` ist statisch/testbar.

**Performance-Erkenntnisse (wichtig für spätere Arbeit):**
- **GDScript-Callkosten im Per-Unit-Per-Tick-Pfad sind massiv:** 1–2
  zusätzliche (virtuelle) Aufrufe pro Einheit und Tick kosten bei 4000
  Einheiten ~5–10 ms/Tick. Deshalb: `idle_aggro` als Feld statt Getter,
  Idle-Features im geslicten Manager-Pass statt im Unit-Tick.
- **`get_units_in_radius` hat jetzt einen `max_count`-Cap** (early out) —
  ohne Cap baute jede Abfrage im 4000er-Klumpen ein 4000er-Array pro
  Aufrufer; `_scan_for_enemy` prüft max. 24 Kandidaten
  (`SCAN_MAX_CANDIDATES`), Regroup 12, Zellsuche 2.
- **Benchmark auf EINEN Tribe umgestellt:** Seit dem Brave-Idle-Aggro
  wurden die gestapelten 4-Tribes-Braves im Benchmark zur
  4000-Mann-Schlacht (Messgröße verfälscht; Slot-Kontention ist ein
  eigenes Phase-8-Thema). A/B-Messung: 7b (Ø 40,0 ms) ≈ Stand davor
  (Ø 37,8 ms) im Worst-Case „alle 4000 auf einen Punkt" — **keine
  Regression**; die historischen 19 ms stammen aus Phase 3f vor den
  Kampf-/Regen-Systemen im Unit-Tick.

**Verifikation:** Testsuite grün (**745 Tests**, +26 in
`tests/test_unit_control.gd`: passiver Move ignoriert Feinde /
Attack-Move greift, Flucht bricht ab + 3.-Treffer-Regel +
Fernbeschuss zählt nicht, 3-m-Wache (nah/fern), `regroup_step`
(Drift/allein/beschäftigte Nachbarn/fertiger Pulk), Ausweichzelle,
Windungs-Slots (außen + paarweise verschieden), Doppelklick-Filter;
2 Alt-Tests an die neue Semantik angepasst). `--headless --quit`
fehlerfrei, Benchmark ohne Regression, 1v1-KI-Sim konvergiert weiter
(aggressive Orders der KI verifiziert).

**Manuelle Prüfung durch Nutzer: AUSSTEHEND** — Rechtsklick-Move läuft an
Feinden vorbei; F+Rechtsklick greift unterwegs an (roter Cursor, Esc
bricht ab); Flucht aus dem Nahkampf; Braves verteidigen das Dorf im
3-m-Umkreis; 6er-Grüppchen nach kurzer Idle-Zeit; geordnete Schlange in
mehreren Windungen um die Kaserne; kein Sprite-Flackern in dichten
Mengen; Doppelklick wählt alle sichtbaren Einheiten des Typs.

**Nachbesserung (Nutzerfeedback): feste Idle-Gruppen + Taste F.**
- **Idle-Gruppen komplett umgebaut** — der Zentroid-Drift ließ Leute
  zwischen Gruppen hin- und herwechseln und „rutschen" statt laufen.
  Jetzt **explizite Gruppen mit fester Mitgliedschaft**
  (`UnitManager.IdleGroup`: Anker + monoton vergebene Slots auf den
  `MEMBER_OFFSETS`, `Unit.idle_group`):
  - Ungruppierte Langzeit-Idle-Einheit (≥ 2,5 s) **tritt der ersten
    offenen Gruppe im 4-m-Umkreis bei** und **läuft aktiv** (echter
    Move-Befehl, Walk-Animation) auf ihren freien Slot; dort bleibt sie.
  - **Keine Neugründung neben bestehenden Gruppen:** Sind (auch volle)
    Gruppen in Reichweite, aber keine offen, bleibt die Einheit einfach
    stehen — genau das verhinderte das Hin-und-her-Switchen.
  - Neugründung nur ohne Gruppe in Reichweite und mit ≥ 2 losen
    Idle-Nachbarn; der Gründer bleibt an Ort und Stelle (Slot 0).
  - Mitglieder wechseln NIE die Gruppe; `_prune_idle_group` entfernt nur
    Tote/Beschäftigte/Weggeschickte (> 6 m vom Anker); auf 1 Mitglied
    geschrumpfte Gruppen lösen sich auf. Slots werden nicht recycelt
    (kein Nachrück-Gewusel).
- **Attack-Move-Taste A → F** (Nutzerwunsch; A kollidierte mit dem
  WASD-Kamera-Pan): Input-Action auf F umgehängt, die
  Kamera-Sonderbehandlung für A ersatzlos entfernt.
- Tests: **759 grün** (Gruppen-Tests ersetzen die Drift-Tests: Bildung +
  gemeinsame Gruppe, keine Neugründung neben voller Gruppe + sticky,
  aktiver Slot-Anlauf + Ankunft, Prune fern/Einzelauflösung). Benchmark
  Ø 35,6 ms (unter der HEAD-Referenz 37,8), Ladecheck + 1v1-Sim sauber.
