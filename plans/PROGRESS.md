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

## Phase 3 — Gebäude, Wirtschaft, HUD (offen)

*(bei Umsetzung ergänzen)*
