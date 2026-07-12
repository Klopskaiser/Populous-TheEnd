# Populous-TheEnd — Umsetzungs-Gesamtplan (Overview)

Dieses Dokument ist der Einstiegspunkt für alle Umsetzungssitzungen. Die Spezifikation des
Spiels steht in [../CLAUDE.md](../CLAUDE.md) — sie ist maßgeblich für *was* gebaut wird;
dieses Dokument und die Phasenpläne legen fest, *wie* und *in welcher Reihenfolge*.

## Phasen & Status

Nach Abschluss einer Phase: Checkbox abhaken, committen, pushen.

- [x] **Phase 1** — [01_project_terrain_camera.md](01_project_terrain_camera.md): Projektgerüst, verformbares Terrain, RTS-Kamera
- [x] **Phase 2** — [02_units_selection_movement.md](02_units_selection_movement.md): Pathfinding, Unit-Basis, Selektion & Bewegung
- [x] **Phase 3** — [03_buildings_economy_hud.md](03_buildings_economy_hud.md): Gebäude, Wirtschaft (Holz/Hütten/Mana), HUD
- [x] **Phase 4** — [04_ui.md](04_ui.md): Original-nahes UI (Sidebar, Minimap, Zauber-/Bau-Panels)
- [x] **Phase 5** — [05_training_combat_preacher.md](05_training_combat_preacher.md): Training, Rally Points, Kampf, Prediger *(Sub-Phasen 5a–5d, siehe Plandatei)*
- [x] **Phase 6** — [06_shaman_spells.md](06_shaman_spells.md): Schamanin, Reinkarnation, alle 5 Zauber, Panik/Schleuderphysik, Gebäudezerstörung *(überarbeitet 2026-07-06)*
- [x] **Phase 7** — [07_ai_win_conditions.md](07_ai_win_conditions.md): Hauptmenü (Vollbild, Skirmish-Setup), Multi-KI (bis zu 3 KIs / 4 Spieler), Siegbedingungen *(abgeschlossen 2026-07-06)*
- [x] **Phase 7b** — [07b_unit_control_behavior.md](07b_unit_control_behavior.md): Steuerung & Einheitenverhalten (Move/Attack-Split + Hotkey F, Fliehen, Brave-Idle-Aggro, Idle-6er-Gruppen, Warteschlangen, Anti-Stacking, Doppelklick-Selektion) *(abgeschlossen 2026-07-06)*
- [x] **Phase 7c** — [07c_new_spells.md](07c_new_spells.md): Neue Zauber Erdbeben, Vulkan, Feuerregen, Ebene, Absinken (+ Terrain-Integritätsregeln für Gebäude/Einheiten, Lava-/Brandmechanik, Zauberleiste auf 10 Slots, KI-Heuristik) *(abgeschlossen 2026-07-06)*
- [x] **Phase 7d** — [07d_economy_forester.md](07d_economy_forester.md): Wirtschaft — Försterei (4 Arbeiterplätze, Mana-Upkeep, pflanzt Setzlinge), Baum-Ertrag 1/2/3/4 + Setzling-Stufe, randomisiertes Wachstum, brennende Bäume/Holzstapel, Tornado-Baumschaden *(abgeschlossen 2026-07-06; manuelle Prüfung ausstehend)*
- [x] **Phase 7e** — [07e_sprite_directions.md](07e_sprite_directions.md): 8 Sprite-Blickrichtungen (Diagonalen) *(abgeschlossen 2026-07-07; manuelle Optik-Prüfung bestanden, inkl. Diagonal-Deko Krieger/Feuerkrieger/Prediger)*
- [x] **Phase 7g** — [07g_building_assault.md](07g_building_assault.md): Gebäudezerstörung durch Einheiten (Sturmangriff durch den Eingang, Insassen-Auswurf + Sturm-Kampfzyklus, Feuerkrieger-Fernbeschuss, 15/5-Nahkampf-Limits, Gebäude = niedrigste Scan-Priorität, Reinkarnationsplatz nur per Zauber/Katapult zerstörbar) *(abgeschlossen + manuelle Prüfung bestanden 2026-07-07)*
- [x] **Phase 7h** — [07h_watchtower.md](07h_watchtower.md): Wachturm (4 Holz, 2 Besatzungsplätze für Kampfeinheiten/Schamanin; +3 m Reichweite für Fernkampf/Bekehrung/Zauber — Krieger ohne Bonus, nur geschützte Reserve) *(abgeschlossen + manuelle Prüfung bestanden 2026-07-07)*
- [x] **Phase 7f** — [07f_siege_workshop.md](07f_siege_workshop.md): Belagerungswaffe + Werkstatt (Crew-System, Fahrzeug-Navigation, Werkstatt-Produktion) *(abgeschlossen 2026-07-07 — auf Nutzerentscheidung VOR 7g eigenständig umgesetzt: eigenes Siege-Gebäude-Targeting statt 7g-Basis; manuelle Prüfung ausstehend)*
- [x] **Phase 7i** — [07i_balancing_maps_economy.md](07i_balancing_maps_economy.md): Zwischenphase (Balancing/Features VOR 8) — Prediger-Verteilung + Bekehrte-kein-Ziel (Katapult-Ausnahme), Kartenauswahl + 3 neue Karten (2× doppelt groß → variable Terraingröße), Einheiten-Hardcap 1500/Spieler, Hütten billiger/kleiner (12 Holz/40 Platz) + bemannbar mit Wachstumsregler, Feuertempel/Tempel größer & teurer, Mana-Zuwachs als Zahl, höhere Kosten der hohen Zauber *(abgeschlossen 2026-07-07; manuelle Prüfung ausstehend)*
- [ ] **Phase 8** — [08_performance.md](08_performance.md): **Nur Performance.** FPS-Anzeige (über Optionen schaltbar), reproduzierbares Früh-Lag-Szenario (Bergpass, 3 KIs + Spieler, reiner Aufbau < 100/Spieler) als Profiling-Ziel beheben, Bewegung/Kampf skalieren (Ziel 6000, min. 2000 Einheiten), Ausbildung/Holzwirtschaft entlasten. Zauber-Performance vorerst ausgeklammert. *(Balance/Komfort/Feinschliff bewusst nach Phase 9 verschoben)* ⚠️ *(2026-07-12 **weitgehend zurückgerollt**: Wegfindungs-Regression im Langzeittest — Einheiten ignorierten Befehle. Behalten wurden nur Schatten-Umbau, Messwerkzeuge (FPS-/Draw-Call-Anzeige, lagtest, F9-Ausbau, Benchmarks, Pfad-Telemetrie) und der Aufholspiralen-Cap. Details + Täter-Hypothese: PROGRESS.md „Rückabwicklung". Neuanlauf über Phase 8.1.)*
- [ ] **Phase 8.2** — [08c_combat_groups_reachability.md](08c_combat_groups_reachability.md): **Verhaltens-Fixes aus dem Rückabwicklungs-Test, bewusst UNABHÄNGIG von der Performance-Arbeit und VOR 8.1 umzusetzen**: Kampfgruppen nach Original-Vorbild (3-gegen-1 + Warte-Ring, Gruppen mit kleinem Mindestabstand statt Einheiten-Blob; Scan-Fixes gegen „alle stehen rum" und den Nord-Drift) + Bergpass-KI-Fixes (keine Gebäude auf unerreichbaren Plateaus, keine Krieger-Trauben am Bergsockel). *(Nutzertest 2026-07-12: Wegpunkt-Bug nach Rollback bestätigt weg)*
- [ ] **Phase 8.1** — [08b_parallelization.md](08b_parallelization.md): Performance-Neuanlauf über **Parallelisierung (Multi-Core)**: Stufe A = Pfad-Worker-Thread (eigene A*-Grid-Klone, FIFO-Grid-Deltas, Ergebnis-Queue — beseitigt Wegfindungs-Spikes UND die Rückstau-Bug-Klasse strukturell), Stufe B = Separation-Fan-out via WorkerThreadPool (messgesteuert), plus Langzeit-Wächtertests gegen die Phase-8-Regression (Hypothese in PROGRESS.md „Rückabwicklung"). **Nutzer-Vorgabe: akkurate 30-Hz-Berechnung — keine Reduktion der Sim-Frequenz.** Der alte 20-Hz-Plan [08a_sim_20hz_interpolation.md](08a_sim_20hz_interpolation.md) ist **verworfen**; Render-/Physik-Thread-Settings sind nach Recherche ebenfalls verworfen (Begründung in 08b). *(2026-07-12: **Stufe A umgesetzt + headless verifiziert** — PathWorker-Thread, NavGrid-Deltas, UnitManager-Async-Integration, A/B-Schalter, 17 neue Tests + Regression-Wächter grün, lagtest-Smoke sauber; Details in PROGRESS.md „Phase 8.1". **Stufe B (Separation-Fan-out) offen** — Messung lohnt (>4 ms/Tick), aber laut Plan als eigener abgesicherter Schritt. Manuelle In-Game-Prüfung ausstehend.)*
- [ ] **Phase 9** — [09_comfort_balance_polish.md](09_comfort_balance_polish.md): Bedienkomfort (Kontrollgruppen, HUD-Ausbau), `balance.gd` (zentrale Konstanten), Balancing-Pass, Feinschliff (Sound-Hooks/Effekte), Testsuite-Kantenfälle, README *(aus der alten Phase 8 herausgelöst)*

Die Phasen sind **strikt sequenziell** — jede baut auf den Artefakten der vorherigen auf.
Jede Phase endet mit einem **lauffähigen, manuell spielbaren Zwischenstand** und
**grünen Headless-Tests**.

## Arbeitsanweisung pro Sitzung

1. Diese Datei + **[PROGRESS.md](PROGRESS.md)** (Ist-Stand inkl. Extras/Erkenntnissen der
   bisherigen Phasen) + den Phasenplan der nächsten offenen Phase lesen.
2. Phase umsetzen (Deliverables + Umsetzungsschritte des Phasenplans).
3. Nach **jeder** neuen/geänderten Skriptdatei: Syntax-Check (`--check-only`), nach neuen
   Dateien: `--headless --import` (wegen `.uid`-Erzeugung, siehe Risiken).
4. Testsuite headless ausführen — muss mit Exit-Code 0 enden.
5. Projekt-Ladecheck `--headless --quit` — Output muss frei von Fehlern sein.
6. Manuelle Prüfschritte des Phasenplans per Spielstart durchführen (bzw. den Nutzer
   bitten, wenn Interaktion nötig ist, die headless nicht prüfbar ist).
7. **[PROGRESS.md](PROGRESS.md) ergänzen:** Gebaut (Dateien + Kern-APIs), Extras/
   Abweichungen vom Plan, Erkenntnisse/Stolpersteine, Verifikationsstand.
8. Checkbox oben abhaken, committen, pushen:
   `git add -A && git commit -m "Phase N: <Titel>" && git push`
   (Repo ist eingerichtet: `main` → `origin/main`, SSH-Alias `github-privat`,
   lokale Commit-Identität nicht ändern, nie `--global`.)

## Verifikations-Befehle

```powershell
$GODOT = 'C:\Users\johannes.wutzke\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe'

# Nach dem Anlegen neuer Dateien (erzeugt .uid-Dateien, aktualisiert Import-Cache):
& $GODOT --path D:\game\Populous-TheEnd --headless --import

# Syntax-Check einer einzelnen Datei (prüft NUR Einzeldatei-Syntax!):
& $GODOT --path D:\game\Populous-TheEnd --headless --check-only --script <pfad>.gd

# Testsuite (Exit-Code 0 = grün, 1 = Fehlschlag):
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/run_tests.gd

# Projekt-Ladecheck (fängt class_name-/Szenen-Referenzfehler, die --check-only nicht sieht):
& $GODOT --path D:\game\Populous-TheEnd --headless --quit

# Spiel starten (manuelle Prüfung):
& $GODOT --path D:\game\Populous-TheEnd
```

## Architektur-Kernentscheidungen (verbindlich für alle Phasen)

### 1. Terrain: Heightmap-Datenmodell als Single Source of Truth
- `TerrainData` (RefCounted, `scripts/core/terrain_data.gd`): `PackedFloat32Array`-Heightmap,
  **128×128 Zellen, 1.0 Weltmeter pro Zelle** (129×129 Vertices). Mesh, Kollision und
  Navigation werden daraus abgeleitet.
- API: `get_height(world_x, world_z) -> float` (bilineare Interpolation — zentral für
  Y-Snapping von Einheiten/Gebäuden, kein Raycast), `raise_area(center, radius, amount)
  -> Rect2i` (Smoothstep-Falloff, gibt geändertes Zellrechteck für partielle Updates
  zurück), `is_walkable(cell) -> bool` (über Wasserlinie `sea_level` + Hangneigung unter
  Schwellwert).
- Mesh: **chunked ArrayMesh** (Chunks à 16×16 Zellen als eigene `MeshInstance3D`), gebaut
  direkt über `ArrayMesh.add_surface_from_arrays()` (kein SurfaceTool). Bei Verformung nur
  die vom `Rect2i` berührten Chunks neu bauen. Vertex-Farben nach Höhe (Sand/Gras/Fels).
- Kollision: **ein** `StaticBody3D` + `HeightMapShape3D`; nach Verformung `shape.map_data`
  neu zuweisen. Nur für Maus-Raycasts (Klickziel, Platzierung, Zauberziel) — Einheiten
  laufen ohne Physik.

### 2. Navigation: AStarGrid2D, KEIN NavMesh
- `NavGrid` (`scripts/core/nav_grid.gd`) kapselt `AStarGrid2D`:
  `find_path(from: Vector3, to: Vector3) -> PackedVector3Array`,
  `update_region(rect: Rect2i)`, `fill_solid_region()` für Gebäude-Footprints.
- Nach `raise_area()` genügt `set_point_solid()` für die betroffenen Zellen — sofort
  wirksam, kein Bake. Diagonalen: `DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES`. Y der Pfadpunkte
  aus `TerrainData.get_height()`.
- **Begründung:** NavigationRegion3D-Re-Bake nach jeder Landbridge kostet hunderte ms,
  läuft asynchron und NavigationAgent3D skaliert schlecht auf 200+ Einheiten. Das Grid
  macht die Landbridge trivial und ist headless deterministisch testbar.

### 3. Einheiten: Node3D ohne Physik
- `Unit` (class_name, `scripts/units/unit.gd`) extends **Node3D**. Bewegung: Pfad per
  `move_toward()` abschreiten, Y jeden Frame aus `TerrainData.get_height()`.
- Kein CharacterBody3D, kein NavigationAgent3D, kein Physik-Body pro Einheit.
- Zielsuche/weiche Separation über **Spatial-Hash** (`UnitManager`,
  `Dictionary[Vector2i, Array]`), Zielsuche per Timer alle 0.2–0.3 s mit Zufalls-Offset
  gestaffelt — nie pro Frame, nie O(n²).
- Visuals: Kind-`AnimatedSprite3D`, `billboard = BILLBOARD_ENABLED`, `shaded = false`,
  `alpha_cut = ALPHA_CUT_DISCARD` (gegen Transparenz-Sortierflackern). Stammfarbe via
  `modulate`. Animationen: Idle, Walk, Attack, Cast (Cast nur Schamanin/Prediger).
- State-Machine als `enum State` + `match` in `_tick()` — Logik testbar ohne Szenenbaum.

### 4. Spielzustand & Symmetrie
- Autoloads: `GameState` (Tribes, Match-Phase, Sieg/Niederlage-Signale) und `Events`
  (reiner Signal-Bus: `unit_died`, `building_destroyed`, `wood_changed`, `mana_changed`).
  Keine weiteren Autoloads.
- `Tribe` (`scripts/core/tribe.gd`): id, color, wood, mana, units, buildings,
  population/housing, shaman. **Spieler und KI sind identische Tribe-Instanzen.**
- **`TribeCommands` (`scripts/core/tribe_commands.gd`) ist die EINZIGE Mutations-API:**
  `place_building()`, `order_move()`, `order_train()`, `cast_spell()` — alle mit
  Kosten-/Gültigkeitsprüfung. UI ruft sie auf, KI ruft sie auf. Direkte Mutationen wie
  `tribe.wood += x` außerhalb von TribeCommands sind verboten (Ausnahme: TribeCommands
  selbst und Tests).
- Mana-Tick zentral: `Tribe.tick(delta)`:
  `mana += (population * BASE_RATE + praying_braves * PRAY_BONUS) * delta`.
- **Zauber-Ladungssystem (wie Original):** Mana wird automatisch in Zauber-Ladungen
  umgewandelt (je Zauber `charge_cost`/`max_charges`); Casts verbrauchen Ladungen,
  kein separater Cooldown. Details in Phase 6, Anzeige (Pips) in Phase 4.

### 5. Selektion & Input
- Terrain-/Gebäudeklick: Raycast (`project_ray_origin/normal` →
  `direct_space_state.intersect_ray()`), eigene Collision-Layer.
- Einheiten-Selektion **screen-space**: Box-Rect aus Drag, pro eigener Einheit
  `camera.unproject_position()` + `rect.has_point()` (+ `is_position_behind()`-Guard).
  Einzelklick = nächste Einheit im Pixelradius. Keine Physik-Shapes pro Einheit.
- Rechtsklick: Bewegung via `TribeCommands.order_move()`; Shift+Rechtsklick = Wegpunkt
  anhängen; Rechtsklick bei selektiertem Gebäude = `rally_point` setzen (Property der
  `Building`-Basisklasse → gilt automatisch für ALLE Gebäude).

### 6. Testbarkeits-Regel (wichtig!)
Spiellogik (Timer, Spawns, Mana, Kampf, KI) in **`tick(delta)`-Methoden** implementieren,
die von `_process`/`_physics_process` aufgerufen werden — Tests rufen `tick()` manuell mit
künstlichen Deltas auf. Keine Godot-`Timer`-Nodes für Kernlogik.

### 7. Placeholder-Assets: rein prozedural
- Einheiten-Sprites: `PlaceholderSprites.make_frames(color) -> SpriteFrames` — Frames per
  `Image.create()` + `fill_rect()`-Pixelmuster, `ImageTexture.create_from_image()`.
  Einheitentyp = Silhouette, Stamm = `modulate` (Blau = Spieler, Rot = KI).
- Gebäude: BoxMesh/CylinderMesh/PrismMesh + `StandardMaterial3D.albedo_color`
  (Hütte = brauner Prism, Lager = graue Box, Tempel = weißer Zylinder,
  Reinkarnationsplatz = flacher Ring); Stammfarben-Fahne als kleines Zweitmesh.
- Bäume: Zylinder-Stamm + Kegel (`CylinderMesh` mit `top_radius = 0`).
- Alles in `_ready()` erzeugt — **keine externen Asset-Dateien**, `assets\` bleibt leer.
- **Auch die UI-Optik ist prozedural:** Gold/Braun-StyleBoxes + generierte
  Pixel-Art-Icons in `scripts/ui/ui_theme.gd` (Phase 4) — echte Grafiken können
  später dieselben Slots ersetzen.
- UI-Sprache Deutsch, Code/Identifier Englisch, typisiertes GDScript (siehe CLAUDE.md §8).

## Test-Strategie

- **Eigener minimaler Runner, kein GUT-Addon:** `tests/run_tests.gd` extends `SceneTree`
  (Pflicht für `-s`). In `_initialize()`: alle `res://tests/test_*.gd` laden, pro
  Testklasse alle Methoden mit Präfix `test_` per Reflection (`get_method_list()`)
  aufrufen, Ergebnis auf stdout, `quit(0)` bei Erfolg / `quit(1)` bei Fehlschlag.
- `tests/test_base.gd`: Basisklasse mit `check(cond: bool, msg: String)` — sammelt Fehler
  statt hart abzubrechen (`assert()` ist in Release-Builds no-op → nicht verwenden).
- Testklassen extends RefCounted (oder Node, wenn Szenenbaum nötig — dann via
  `root.add_child()` im Runner).
- **Headless testbar:** Terrain-Mathe, NavGrid-Pfade/Region-Updates, Wirtschaft, Mana-Formel,
  Spawn-/Trainings-Timer, Rally-Zuweisung, Kampf-/Schadensrechnung, Konvertierung,
  Zauberkosten/-effekte auf Datenebene, Landbridge-Walkability, KI-State-Übergänge,
  Schamanin-Respawn, Siegbedingung.
- **Nur manuell testbar:** Rendering/Billboards, Kamera-Feel, Box-Select-Optik, HUD-Layout,
  Maus-Raycasts, Partikel.

## Bekannte Godot-4.x-Risiken (bei Umsetzung beachten)

1. **`HeightMapShape3D` ist origin-zentriert** mit festem 1.0-Raster → StaticBody3D um
   `(width/2, 0, depth/2)` versetzen; früh per Testklick-Marker verifizieren, sonst
   „Klicks landen daneben".
2. **`--check-only` prüft nur Einzeldatei-Syntax**, keine projektweiten
   `class_name`-Referenzen → immer zusätzlich `--headless --quit`. Achtung: dabei läuft
   `_ready()` der Hauptszene → Main muss headless-robust sein.
3. **`.uid`-Dateien:** Extern angelegte `.gd`/`.tscn` bekommen erst nach
   `--headless --import` ihre UID; vorher können Szenen-Referenzen brechen. Nach jedem
   Anlegen neuer Dateien einmal importieren; `.uid`-Dateien nie manuell löschen/umbenennen.
4. **Headless = Dummy-RenderingServer:** `Image`/`ImageTexture` funktionieren, alles
   Viewport-/Shader-abhängige nicht. Tests dürfen keine Texturinhalte prüfen;
   Sprite-Erzeugung nur in `_ready()` von Szenen, nicht in testbarer Kernlogik.
5. **200+ Einheiten:** verboten sind per-Frame-`get_nodes_in_group` + Distanzschleifen,
   NavigationAgent3D pro Einheit, Physik-Body pro Einheit. Massen-Pfadberechnungen ggf.
   über Frames verteilen (Queue im NavGrid).
6. **Einheiten ohne Physik laufen durch Gebäude** → Footprints als solid-Zellen im NavGrid;
   nach Blast/Tornado-Würfen Landeposition auf begehbare Zelle clampen.
7. **Skriptete Flugbahnen:** Würfe (Blast/Tornado) als Tween/manuelle Parabel, Einheit
   dabei in Sonder-State ohne Y-Snapping, bei Landung Snap.
8. **Chunk-Rebuild-Hitches:** nie das ganze Terrain neu vernetzen; `Rect2i` aus
   `raise_area()` strikt nutzen. `map_data`-Neuzuweisung einmal pro Verformung (bzw.
   gedrosselt), nicht pro Frame.
9. **KI-Symmetrie:** keine Abkürzungen an TribeCommands vorbei — der Symmetrie-Test in
   Phase 7 prüft das.
10. **API-Drift Godot 4.7:** bei Unsicherheit exakte Signaturen gegen die lokale 4.7-Doku
    prüfen statt älteren Tutorials zu vertrauen.

## Zielstruktur (aus CLAUDE.md §8, wächst über die Phasen)

```
D:\game\Populous-TheEnd\
├── project.godot
├── plans\                 # diese Pläne
├── scenes\                # main, terrain, ui, units, buildings
├── scripts\core|units|buildings|spells|ai|ui
├── tests\                 # run_tests.gd, test_base.gd, test_*.gd
└── assets\                # bleibt leer (prozedurale Placeholder)
```
