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
Manuelle Prüfung (HUD-Live-Update, Ghost-Platzierung, Sammeln/Beten/Bauen per
Rechtsklick, Umlaufen von Footprints): **ausstehend — bitte durch Nutzer prüfen.**
