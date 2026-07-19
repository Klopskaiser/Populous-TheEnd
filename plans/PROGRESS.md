# Umsetzungsstand (PROGRESS)

Fortschrittsdoku für neue Sitzungen: **was tatsächlich gebaut wurde**, inkl. Abweichungen
und Extras gegenüber den Phasenplänen — damit kein Code durchsucht werden muss.

**Pflegeregel:** Am Ende jeder Phase (vor Commit/Push) einen Abschnitt ergänzen mit:
Gebaut (Dateien + Kern-APIs), Extras/Abweichungen vom Phasenplan, Erkenntnisse/Stolpersteine,
Verifikationsstand. Auch bei nachträglichen Erweiterungen außerhalb einer Phase hier eintragen.

---

## UI-Aufräumen: Besatzungs-Tab, Wachstums-Overrides, Katapult-Limit pro Stamm (2026-07-19)

**Mechanik:**
- **Manuelle Hütten-Besatzung „hält"** (`scripts/buildings/hut.gd`):
  `manual_crew_override: int = -1` (−1 = folgt Regler) + `clear_manual_override()`;
  `_crew_target()` bevorzugt den Override. `eject_crew(index, manual := false)` —
  manueller Rauswurf (Besatzungs-Tab) pinnt die Crew auf den neuen Stand; ebenso
  manuelles Bemannen: `Unit.order_man_hut(hut, manual := false)` setzt
  `Unit.man_hut_manual`, `Hut.admit_crew` übernimmt es als Override.
  `TribeCommands.order_man_hut` (nur Spieler-Rechtsklick) ruft mit `manual = true`.
  Das Flag wird bei Befehlsabbruch/-wechsel zurückgesetzt (`leave_garrison`,
  `order_move`, `_begin_attack`, `order_garrison`, `_tick_garrison`-Abbrüche).
  **Reglerwechsel löscht alle Overrides:** `Tribe.set_growth_mode()` (nur vom
  Sidebar-Slider gerufen; Direktzuweisung in Tests/Setup räumt bewusst nichts).
- **Katapult-Limit pro Stamm** (`scripts/core/tribe.gd`): `Tribe.max_catapults`
  (Default 3, 0–20) + `owned_catapult_count()` — zählt **alle eigenen** Katapulte
  (bemannt UND unbemannt, nicht DEAD); gegnerische/übernommene fallen durch den
  Ownerwechsel (`convert_to_tribe` verlässt `tribe.units`) automatisch raus.
  `Workshop.max_catapults`/`manned_catapult_count()` **entfernt**;
  `can_start_production()` prüft das Stamm-Limit. KI bleibt beim Default 3.
- **Generisches `paused`** (`scripts/buildings/building.gd`): Produzenten frieren
  nur ihren Produktionspfad ein — Hütte (Spawn-Timer; Crew-Aufnahme + Growth
  laufen weiter), Trainingsgebäude (kein Admit, Timer eingefroren), Förster
  (kein Pflanzen, kein Mana-Upkeep), Werkstatt (wie bisher).
- **Crew-Pips an der Hütte** (`hut.gd`): zweites Overlay-Sprite unter der
  Produktionsleiste (4 Pips, gold = bemannt), sichtbar bei Selektion/Hover.

**UI (`scripts/ui/sidebar.gd`, `scripts/ui/ui_theme.gd`):**
- **Neuer 4. Tab „Besatzung"** (`TAB_CREW`): zeigt das einzeln selektierte
  bemannbare Objekt (Hütte/Försterei/Werkstatt/Wachturm/Katapult; Trainingsgebäude
  nur Info+Pause) — Titel, Info-Zeile, **Insassen als Icon-Buttons (Klick = Rauswurf**,
  Hütte mit `manual = true`), Pause-Button für Produzenten. Normalisierung
  `crew` vs. `occupants` in `_crew_view(target)`. **Auto-Umschaltung mit
  Kanten-Logik** (`_refresh_crew_tab` in `_process`): Selektion null→Ziel öffnet
  den Tab (merkt Rücksprung-Tab), Ziel→null springt zurück; Zielwechsel und
  manuelle Tab-Klicks schalten nicht um. Tab-Button ausgegraut ohne Ziel.
- **Die vier alten Kontextpanels entfernt** (Förster/Werkstatt/Wachturm/Katapult)
  samt `TAB_CONTENT_HEIGHT_COMPACT`/`_update_tab_content_height`.
- **Gebäude-Tab als 2-Spalten-Icon-Grid** (`_make_build_cell`, Spiegel der
  Zauberzellen): Icon-Button + „N Holz"-Label, Name/Hotkey im Tooltip.
- **Katapult-Stepper im Gefolgsleute-Tab** (werkstattunabhängig):
  „Max. Katapulte: N (aktuell: M)" auf `Tribe.max_catapults`.
- **Schamanen-Porträt kompakter:** Bühne 80→72 px (exakt Spritehöhe), das
  Status-Label ist unsichtbar solange leer (keine Leerzeile unter dem HP-Balken).
- **Neue prozedurale Icons** (`ui_theme.gd`): `brave` (Figur), `preacher`
  (Robe+Stab), `crew` (Figur im Türrahmen); `warrior`→Schwert, `firewarrior`→Flamme,
  `siege`→Katapult als Alias bestehender Painter.

**Verifikation:** **1834 Tests grün** (neu in `test_hut_crew.gd`:
`test_manual_eject_holds`, `test_manual_man_holds`, `test_slider_change_clears_overrides`,
`test_paused_hut_produces_nothing`; `test_siege.gd` auf Stamm-Limit/`owned_catapult_count`
umgestellt inkl. unbemannt-zählt/Gegner-zählt-nicht). `--headless --quit` fehlerfrei;
Spielszene 40 s headless ohne Skriptfehler. Manueller Spieltest (Tab-Auto-Umschaltung,
Grid-Optik, Overlay-Pips) steht noch aus.

## Bugfixes nach 7h (Nutzerfeedback, 2026-07-07)

- **Katapult-Zielregel:** Einheiten konnten über Umwege (Angriffs-Umverteilung
  `TribeCommands._nearest_free_enemy_near`, Feuerkrieger-`_melee_threat`) das
  **Fahrzeug selbst** als Ziel bekommen → Gegner schlug aufs Katapult ein
  (`take_damage` = No-op), die Crew wurde nie angegriffen und wehrte sich nicht.
  Fix: `Unit._begin_attack` weist **nicht-zielbare** Ziele grundsätzlich ab
  (`not is_targetable() and not _may_target_vehicle()`), plus `is_targetable()`-
  Filter in den beiden lecken Scans. **Ausnahme Katapult-gegen-Katapult
  (Fernkampf):** `SiegeEngine._may_target_vehicle(enemy) = enemy is SiegeEngine`
  und `_nearest_enemy_unit` lässt gegnerische Katapulte zu (der Schuss trifft per
  Splash die Crew). Regel: Katapulte sind nah/fern nicht direkt angreifbar, nur
  ihre Crews — außer Katapult vs. Katapult im Fernkampf.
- **Lava verbrennt Bäume:** `LavaSurge._ignite_covered_units` entzündete nur
  Einheiten. Jetzt auch Bäume + Holzstapel im Radius
  (`tree_manager.ignite_in_radius` / `wood_pile_manager.ignite_in_radius`, wie
  beim `LavaFlow`) — Vulkan-Lava und die Katapult-Lavapfütze setzen Bäume in Brand.
- **Verifikation:** **1389 Tests grün** (neu: `test_units_never_target_the_vehicle`,
  `test_catapult_may_target_enemy_catapult` in `test_siege.gd`;
  `test_lava_surge_ignites_trees` in `test_spells.gd`), `--headless --quit` fehlerfrei.

### Wegpunkt-Folgebefehle + Turm-Anmarsch + Start-Katapult (2026-07-07)

- **Wegpunkte + Gebäudebefehl am Ende:** Shift+Rechtsklick auf ein Gebäude/einen
  Baum/ein Katapult **nach** einer Wegpunktroute führte den Befehl sofort aus
  (Route ignoriert). Neu: `Unit.route_end_action: Callable` — ein per
  Shift+Rechtsklick gesetzter Folgebefehl, der **erst nach Abschluss der Route**
  feuert (`_finish_route`). Der `SelectionManager` hängt bei Shift den
  Anlaufpunkt als letzten Wegpunkt an (`_queue_route_action`) und bewaffnet je
  Einheit `route_end_action` (Bau/Reparatur/Beten/Förster/Werkstatt/Garnison/
  Training via `_apply_building_command`, Baum via `order_chop`, Katapult-Crew
  via `order_crew`). Jeder frische, nicht-gequeuete Befehl löscht die pending
  Action (`order_move`, `_begin_attack`, `order_garrison`, `order_crew`,
  `Brave._interrupt_tasks`). **Gilt auch für Katapulte** (Crew mit Wegpunkten).
- **Turm-Anmarsch robuster:** Der strikte Eingang-Radius (2 m) ließ Einheiten am
  Footprint-Eck hängen (Direktschritt blockiert). `_tick_garrison` zählt jetzt
  „angekommen", sobald die Einheit im `interact_range` der Turmmitte ist; der
  Turm nimmt im selben Radius auf.
- **Start-Katapult (Spieler):** `_setup_player_base` spawnt ein **unbemanntes**
  Katapult neben der Spielerbasis (Test der Crew-Zuweisung, auch mit Wegpunkten).
- **Verifikation:** **1397 Tests grün** (neu: `test_queued_garrison_runs_after_route`
  in `test_watchtower.gd`), `--headless --quit` fehlerfrei.

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
  war schon vorher praktisch voll). *(Überholt seit 2026-07-18: Basis
  1920×1080 + Stretch-Mode, siehe „Bugfix Backlog #1".)*
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

**Manuelle Prüfung durch Nutzer: BESTANDEN (2026-07-06)** — nach den
Nachbesserungen unten; Phase 7 abgeschlossen.

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

**Manuelle Prüfung durch Nutzer: BESTANDEN (2026-07-06)** — nach den
Nachbesserungen unten (feste Gruppen, Adopt-in-Place, Move-Gruppen ab
Befehl, Taste F, Kampf-Wander-Bugfix, Selektionsring-Fix); Phase 7b
abgeschlossen.

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

**Nachbesserung 2 (Nutzerfeedback): Adopt-in-Place.** Nach einem
Formations-Move standen die Leute am Wegpunkt bereits perfekt im
6er-Muster — der Gruppenfinder gründete dann trotzdem eine Gruppe am
Standort des Gründers und ließ alle auf Slots ANLAUFEN (unnötige
Bewegung). Jetzt hat der Finder eine vorgelagerte Stufe: Stehen ≥ 2 idle
Stammesgenossen bereits **eng beieinander** (`IDLE_GROUP_SETTLED_RADIUS`
1,5 m — deckt das gelandete 6er-Muster ab), wird der Klumpen **an Ort und
Stelle als Gruppe adoptiert** (`join_idle_group(..., walk = false)`):
niemand bewegt sich, die Formation wird nur registriert (und ist damit
sticky — auch eine nicht ganz volle „perfekte" Gruppe bleibt stehen).
Gelaufen wird nur noch beim Beitritt zu einer offenen Gruppe oder bei
einer Neugründung mit verstreuten Nachbarn. Tests: **772 grün**
(+ Adopt-Test: gemeinsame Gruppe, keine Move-Orders, Positionen exakt
unverändert).

**Kampf-Bugfix (Nutzerreport): wandernde Einheitenblöcke.** Symptom: Ein
Block Gegner „drückte sich vor dem Kampf" und wanderte endlos — auch
durch Wasser und über den Kartenrand. Ursache war eine
**Bewegungs-Rückkopplung** in der Nahkampf-Logik: Ein Angreifer ohne
freien Slot verfolgte in `_wait_near` einen **exakten Ringpunkt um sein
Ziel** (Punkt wandert mit dem Ziel mit); das Ziel wiederum verfolgte die
Slot-Position SEINES Ziels — die Ziele hingen aneinander, alle liefen
einander mit identischem Tempo ewig hinterher, niemand kam je in
Schlagreichweite. Und die direkte Kampfverfolgung (`_step_toward`) hatte
**keinen Begehbarkeits-Check** (A* läuft nur > 2,5 m) → der Zug lief
ungebremst ins Meer/über den Rand. Fixes:
- `_wait_near`: Wartende **stehen**, sobald sie nah genug am Kampf sind
  (≤ Warteradius + 0,6 m) — nur zu weit entfernte rücken nach. Bricht die
  Kopplung: der „Flüchtende" bleibt stehen, der Verfolger holt auf und
  schlägt zu.
- `_step_toward`: Schritte, die auf unbegehbaren Boden führen (Wasser,
  Kartenrand — `world_to_cell` clampt auf die Meer-Randzellen), werden
  verworfen.
- Tests: **776 grün** (+4: Direktverfolgung stoppt am Wasser und bleibt
  auf begehbarem Boden; naher Wartender steht still, ferner rückt nach).
  KI-Sim konvergiert unverändert.

**Nachbesserung 3 (Nutzerfeedback): Gruppen entstehen beim Move-Befehl.**
- **Formations-Moves registrieren ihre 6er-Päckchen SOFORT als Gruppen**
  (`TribeCommands.order_move` → `UnitManager.register_move_group`, Anker =
  Formationszentrum, `walk = false` — die Einheiten laufen ja ohnehin per
  Move-Befehl auf ihre Plätze). Damit gilt ab Befehlserteilung:
  - Alle Marschierer sind bereits Mitglieder → der Idle-Finder fasst eine
    gelandete Formation **nie wieder an** (keine Neu-/Umgruppierung).
  - **Slots sind ab Befehl reserviert:** Laufende zählen als künftige
    Mitglieder — `_prune_idle_group` bewertet MOVE-Mitglieder nach ihrem
    **Bewegungsziel** statt der aktuellen Position; niemand Fremdes dockt
    an eine Gruppe an, die durch Ankommende gefüllt wird, und Mitglieder
    einer werdenden Gruppe wandern nicht zu anderen ab.
  - Ein Mitglied, das woandershin geschickt wird (Ziel fern vom Anker),
    fliegt beim nächsten Prune raus; `join_idle_group` trägt beim
    Gruppenwechsel sauber aus der alten Gruppe aus (Prune einer alten
    Gruppe nullt keine neue Mitgliedschaft mehr).
  - Aggressive Märsche (Attack-Move der KI/des Spielers) registrieren
    keine Gruppen — sie enden im Kampf.
- **Idle-Delay 2,5 s → 30 s** (`IDLE_REGROUP_DELAY`): Der Idle-Finder
  (Adopt-in-Place, Beitritt, Neugründung) greift nur noch bei Einheiten,
  die eine halbe Minute untätig herumstanden (Hütten-Spawns u. Ä.) —
  Formations-Gruppen brauchen ihn nicht mehr.
- Tests: **801 grün** (+25: Move registriert 6+2-Gruppen sofort,
  Laufende werden nicht geprunt + volle Gruppe reserviert, Deserteur
  fliegt per Ziel-Distanz, gelandete Formation behält Gruppe und bewegt
  sich nicht mehr). Ladecheck + KI-Sim unverändert sauber.

---

## Phase 7c — Neue Zauber: Erdbeben, Vulkan, Feuerregen, Ebene, Absinken (umgesetzt)

Plan: [07c_new_spells.md](07c_new_spells.md) (vor der Umsetzung um Ebene/
Absinken + verbindliche Ladungszahlen erweitert). Zauberleiste jetzt 10 Slots.

**Terrain-Integritätsregeln (`spell_context.gd`, gilt für ALLE Terrain-Zauber):**
- `SpellContext.apply_terrain_change(rect)` ruft nach dem NavGrid-Update
  `check_terrain_integrity(rect)` auf (läuft damit bei jedem Morph-Schritt):
  - **(a) Fundament-Bruch:** Höhenspanne unter dem Footprint >
    `FOUNDATION_BREAK_DIFF` (1,2 m) → `Building.shatter()` (sofortige
    Zerstörung, Modell verschwindet, `BuildingDebris`-Trümmer fliegen in
    Parabeln davon — neue Entität über die Projektil-Liste).
  - **(b) Überflutung:** ≥ `FLOOD_FRACTION` (30 %) der Footprint-Zellen unter
    `SEA_LEVEL` → `Building.slide_into_water(dir)` (Wrack rutscht seitlich
    Richtung tiefster Ecke und versinkt; `SLIDE_SPEED` im Sink-`_process`).
  - **(c) Ertrinken:** Einheiten (außer THROWN — deren Landung prüft selbst)
    auf Boden ≤ `SEA_LEVEL + 0,05` → neues öffentliches `Unit.drown()`
    (auch von `_land_from_throw` genutzt).
  - **Dokumentierte Auslegung: Terrain-Gewalt ist stammesblind** — eigene
    Gebäude/Anhänger sind genauso gefährdet (anders als die "nur Feinde"-
    Doktrin der direkten Schadenszauber).
- **`TerrainMorph` (neu, `terrain_morph.gd`) ersetzt `LandbridgeMorph`:**
  generalisierter gradueller Morph auf eine Ziel-Höhenkarte
  (`{indices, targets, rect}`), Dauer pro Zauber; Snap von Einheiten/Bäumen/
  Stapeln/Gebäuden unverändert. Landbrücke nutzt ihn mit 3 s.
- `UnitManager._tick_projectiles` als Index-Schleife: Projektile dürfen beim
  Ticken NEUE Projektile registrieren (Feuerregen-Bolts, Trümmer).

**Zauber (Startwerte; verbindliche Ladungszahlen laut Plan):**
- **Erdbeben** (`earthquake.gd`, 80 Mana / **2** Ladungen / 10 m):
  deterministische Vertex-Verwerfung ±1,5 m im 7-m-Radius (Seed aus
  Zielzelle, Falloff), Morph 2 s; Feindgebäude im Radius +2 Stufen,
  Feindeinheiten ¼ Brave-Leben + Mini-Rolle; Wasser-Klemme: Meeresboden wird
  nie angehoben, Absenken unter die Seelinie erlaubt (flutet).
- **Vulkan** (`volcano.gd` + `volcano_zone.gd`, 120 / **1** / 12 m):
  permanenter Smoothstep-Kegel +6 m (Radius 5, Morph 3 s, Mittelhang
  unbegehbar = gewollt) + 20-s-Lava-Zone: 10 Schaden/s an ALLEN Einheiten,
  +1 Stufe alle 4 s an ALLEN Gebäuden im 5-m-Radius (Lava kennt keine
  Freunde).
- **Feuerregen** (`firestorm.gd`, 70 / **2** / 10 m): innere
  Scheduler-Klasse `FirestormShower` spawnt 8 unveränderte `FireballBolt`s
  über 3 s auf deterministisch gestreute Punkte (≤ 4 m, Seed aus Zielzelle).
- **Ebene** (`flatten_spell.gd`, 70 / **3** / 10 m): Quadrat 9×9 m exakt auf
  Zielpunkt-Höhe, HARTE Kanten (kein Falloff → Klippen), SCHNELL (0,5 s);
  Einheiten auf der Fläche werden je nach Höhendelta geschleudert (Anheben →
  Wurfparabel, Absenken → Sturz mit skalierendem Fallschaden); keine Klemme
  nach unten (Zielpunkt unter See flutet die Fläche).
- **Absinken** (`sink.gd`, 60 / **3** / 10 m): Gegenstück zur Landbrücke —
  senkt 6-m-Radius um bis 3 m, weicher Smoothstep-Falloff, Morph 1,5 s,
  Klemme auf Meeresboden (`FLOOR_LEVEL` 0,5); Küstenland flutet →
  Integritätsregeln.
- `Spell.create_default_set()` liefert 10 Zauber; Startladung-1-Regel aus
  `main.gd` gilt automatisch mit.

**UI:** Sidebar `default_spell_entries()` 10 Einträge (Reihenfolge =
Hotkeys 1–9, 0), neue 24×24-Icons `earthquake`/`volcano`/`firestorm`/
`flatten`/`sink` in `ui_theme.gd`; Input-Actions `cast_spell_6..10`
(Tasten 6–9 und 0) in `project.godot`; `SpellTargeting.HOTKEY_SPELLS`
erweitert, Cursor zeigt für **Ebene ein 9×9-Quadrat** statt des Rings
(`_cursor_ring`/`_cursor_square`). Zauber-Tab bleibt 3-spaltig (10 Zellen =
4 Reihen, passt in die 260-px-Sidebar).

**KI (`ai_controller.gd`, `_cast_spells`-Leiter erweitert):** Blitz auf
Feindschamanin (unverändert) → **Vulkan** ab 2 Feindgebäuden im
5-m-Umkreis → **Absinken** auf küstennahe Gebäude (Bodenhöhe ≤ SEA+2) →
**Ebene** neben Gebäuden an Höhenstufen (`_flatten_break_point`: 4
Kardinal-Proben bei 5,5 m, Stufe > 1,5 m → Cast auf den Probepunkt,
Quadratkante schneidet durchs Fundament) → Tornado → **Erdbeben** (neuer
Gebäude-Fallback) → Blitz; bei Einheiten: Schwarm (≥5) → **Feuerregen**
statt Feuerball ab ≥5 Feinden im 4-m-Cluster → Feuerball.

**Erkenntnisse/Stolpersteine:**
- Projektile, die beim Ticken neue Projektile registrieren, brauchen die
  Index-Schleife — das alte `for p in projectiles` + `kept`-Rebuild hätte
  mitten in der Iteration angehängte Einträge verlieren können.
- Reihenfolge der Integritätsprüfung: Flut VOR Fundament-Bruch prüfen —
  beim Absinken über einem Gebäude wächst die Spanne langsamer als die
  Flutung (weicher Falloff), so rutscht es korrekt ins Wasser statt zu
  zerplatzen; bei harten Kanten (Ebene) greift der Bruch.
- Ein Gebäude NEBEN einem Vulkan überlebt nie den Kegel selbst (Fundament-
  Bruch durch die Kegelflanke) — der Lava-Stufen-Takt ist deshalb separat
  über eine direkt platzierte `VolcanoZone` getestet.

**Verifikation:** Testsuite grün (**959 Tests**, +315: Integritätsregeln
(Bruch-Schwelle, Flut-Rutschen, Ertrinken inkl. Trockengrenze), Erdbeben
(Verwerfung im/außerhalb Radius, +2 Stufen, ¼-Schaden+Rolle nur Feinde,
Wasser-Klemme), Vulkan (Kegel ≥ +5, Lava trifft Feind UND eigene, Berg
bleibt nach Zonen-Despawn, 4-s-Stufentakt), Feuerregen (8 Bolts, Streuung
≤ 4 m, Trefferwirkung), Ebene (exakte Planierung + harte Kante messbar,
Schleudern, Gebäude-Zerplatzen + Trümmer, Flutung + Ertrinken), Absinken
(Falloff, Meeresboden-Klemme, Küsten-Flut: Gebäude versinkt + Anhänger
ertrinkt), Set-/UI-Abgleich (10 Zauber, Pips == max_charges, Hotkey-
Reihenfolge), KI-Heuristiken (Vulkan/Absinken/Ebene/Feuerregen via
`pending_spell`)). `--headless --import`, `--headless --quit` und
`--quit-after 240` fehlerfrei. **Manuelle Prüfung durch Nutzer: ausstehend**
(siehe Plan §Manuelle Prüfung: 10 Slots + Hotkeys 1–0, Quadrat-Vorschau,
Erdbeben-Optik, Vulkan-Berg + Lava, Feuerregen-Salve, Ebene-Klippen +
zerplatzende Gebäude, Absinken-Flutung, KI castet die neuen Zauber).

**Nachbesserung (Nutzerfeedback, erste Runde):**
- **Tornado ist stammesblind:** Tribe-Filter in `TornadoVortex`
  (`_wreck_buildings`/`_pick_up_units`) entfernt — auch eigene Einheiten und
  Gebäude im Weg werden hochgewirbelt bzw. gestuft (konsistent mit der
  Terrain-Gewalt-Doktrin).
- **Gebäude resistenter + selbstglättendes Fundament:**
  `FOUNDATION_BREAK_DIFF` 1,2 → **2,0 m**. Überlebt ein Gebäude eine
  Terrainänderung mit schiefem Fundament (Spanne > 5 cm), markiert die
  Integritätsprüfung es (`mark_foundation_disturbed`); `Building.tick`
  planiert die Footprint-Vertices dann mit `FOUNDATION_SMOOTH_RATE`
  (0,3 m/s) zurück auf den Mittelwert (gebatchte Nav-/Mesh-Updates wie beim
  Bau, Gebäude setzt sich mit).
- **Feuerregen fällt vom Himmel:** Bolts starten `SKY_HEIGHT` (14 m) über
  ihrem eigenen Einschlagpunkt (kleiner Seitenversatz für den
  Sturzflug-Bogen) statt bei der Schamanin; `SPREAD_RADIUS` 4 → **5,5 m**
  (KI-Schwelle skaliert mit).
- **Lava-Mechanik (neu, `lava_flow.gd`):** `LavaFlow`-Entität — Strom folgt
  dem Terraingradienten bergab (auf Ebenem staut er nach ~1 m), begrenzte
  Reichweite, hinterlässt Segmente: glühend (zündet ALLES an — Lava kennt
  keine Freunde) → abgekühlt (schwärzt den Boden: Scorch-Decal). **Brand auf
  Unit:** `Unit.ignite()` = einmalig `LAVA_CONTACT_DAMAGE` (30 = ½ Brave)
  + Brand `BURN_DURATION` 4 s mit `BURN_TOTAL_DAMAGE` 120 (2× Brave) über
  die Laufzeit; Brennende laufen in Panik umher (Panik-immune Schamanin
  brennt ohne Panik); erneute Berührung refresht statt zu stapeln.
- **Vulkan speit Lavaströme:** `VolcanoZone` ohne Flächen-DPS/Orange-Dome —
  stattdessen ab 1,5 s alle 2,5 s ein `LavaFlow` aus dem Krater (Richtungen
  deterministisch aufgefächert, fließen die Flanken hinab und schwärzen
  sie); Placeholder-**Rauchsäule** über dem Krater; Gebäude-Stufentakt
  (alle 4 s im 5-m-Radius) unverändert.
- **Erdbeben = sichtbare Bruchkante statt Zufallsverwerfung:**
  `upheaval_targets` legt eine **Verwerfungslinie** durch den Zielpunkt
  (Ausrichtung deterministisch aus der Zielzelle): Absenkungsseite bis
  −2,2 m direkt an der Kante (auslaufend), Gegenseite türmt sich bis
  +0,8 m auf → benachbarte Vertices springen an der Linie um mehrere Meter
  (der Boden "bricht"). An der frischen Kante laufen **3 kurzlebige
  Lavaströme** die Abbruchseite hinab (Reichweite 3,5 m, 3,5 s Lebenszeit,
  ohne Scorch — verschwinden schnell). Gebäude-/Einheiten-Effekte und
  Wasser-Klemme unverändert.
- Tests: **986 grün** (+27: Fundament-Settling, härtere Bruchschwelle,
  Tornado wirbelt eigene Einheit, Feuerregen-Himmelsstart, Vulkan-Lavaströme
  + Eruptionsende, Bruchkanten-Geometrie (Drop/Lift/Kantensprung messbar),
  Erdbeben-Lava (3 Ströme, kein Scorch, schnell weg), Lava-Kontakt/Brand/
  Panik/Reichweite/Abkühlung, Schamanin brennt ohne Panik).
  Ladecheck + `--quit-after 240` fehlerfrei.
  **Manuelle Prüfung durch Nutzer: ausstehend.**

**Nachbesserung (Nutzerfeedback, zweite Runde — Lava-Optik & Vulkan-Eruption):**
- **Lavaströme als zähflüssiges Band** (`lava_flow.gd` umgebaut): statt
  einzelner orangefarbener Ovale zeichnet der Strom EIN durchgehendes,
  terrainfolgendes Ribbon-Mesh (ImmediateMesh-Triangle-Strip über die
  Segmentpunkte, throttled 0,1 s): Breite pulsiert viskos pro Punkt
  (Sinus-Wobble), der vorrückende Kopf ist bauchig verdickt, die Farbe
  altert vom glühenden Orange am Kopf über dunkles Zähflüssig-Rot zur
  schwarzen Kruste am abgekühlten Ende (Vertex-Farben; Fault-Lava blendet
  stattdessen aus). `FLOW_SPEED` 2,2 → 3,0, Segmentabstand 0,7 → 0,45
  (glatterer Verlauf). Schadenslogik unverändert.
- **Vulkan-Eruption über alle Flanken** (neue `lava_surge.gd`): statt
  einzelner Ströme, die um den Berg herumkriechen, quillt die Lava jetzt am
  Krater auf und läuft als **radiale Decke an ALLEN Seiten gleichzeitig**
  schnell herunter (Front expandiert mit 3,2 m/s bis Radius 5,5; kegelan-
  schmiegendes Radialmesh, 24 Sektoren, unregelmäßig vorbeulende Front,
  Farbverlauf glühende Front → schwarze Kruste von innen nach außen).
  Solange die Decke glüht, entzündet sie alles darunter (`Unit.ignite`);
  die schwarze Kruste bleibt bis zum Ablauf (9 s) liegen. Eine Surge alle
  4,5 s.
- **Rauch erst ab Maximalhöhe + animiert** (`volcano_zone.gd`):
  Eruptionen und Rauch starten erst, wenn der Kegel fertig ist
  (`SURGE_START = VolcanoSpell.DURATION`); die Rauchsäule ist eine
  Schleifen-Animation aus 5 phasenversetzten Puffs, die aus dem Krater
  aufsteigen, anwachsen und ausblenden (leichtes seitliches Wabern).
  Statischer Puff-Stapel und die alten Einzel-`LavaFlow`s des Vulkans sind
  entfernt (das Erdbeben nutzt `LavaFlow` weiter).
- Tests: **988 grün** (Vulkan-Test auf `LavaSurge` umgestellt und wieder um
  die deterministischen Brand-Checks ergänzt — Decke trifft beide
  gegenüberliegenden Flanken-Einheiten). Ladecheck + `--quit-after 240`
  fehlerfrei. **Manuelle Prüfung durch Nutzer: ausstehend.**

**Nachbesserung (Nutzerfeedback, dritte Runde — Lava-Feintuning):**
- **Vulkan-Lava reicht bis über den Bergfuß:** Surge-Radius `RADIUS + 0,5`
  → **`RADIUS + 2,5`** (7,5 m) — die Decke bildet einen Ring um die
  Bergbasis. Dafür **Lavadauer × 0,6**: `LavaSurge.LIFETIME` 9 → 5,4 s,
  `MOLTEN_TIME` 2,5 → 1,5 s.
- **Lava versinkt im Boden statt zu verpuffen:** `LavaSurge` und `LavaFlow`
  senken ihr Mesh in der letzten Lebensphase (`SINK_TIME` 1,2/1,0 s) um
  `SINK_DEPTH` unter die Oberfläche ab (Vertex-Y-Offset) — die Kruste
  taucht sichtbar ins Terrain ab.
- Tests: 988 grün, `--quit-after 240` fehlerfrei.

**Manuelle Prüfung durch Nutzer: BESTANDEN** („ok, das funktioniert gut") —
Zauber, Integritätsregeln, Lava-/Brandmechanik, Vulkan-Eruption,
Erdbeben-Bruchkante. **Phase 7c abgeschlossen**, Checkbox in der Overview
abgehakt.

---

## Phase 7d — Wirtschaft: Försterei, Setzlinge, Baumertrag 1/2/3/4, Feuer & Tornado

**Gebaut:**
- **Baum-Ertrag & Setzling-Stufe** (`scripts/core/tree_resource.gd`): fünf
  Stufen statt vier. `MAX_STAGE 4`, `YIELDS [0,1,2,3,4]`,
  `STAGE_SCALES [0.28,0.35,0.55,0.8,1.0]`. **Stufe 0 = Setzling** (0 Holz, bloßer
  senkrechter Stock — Krone via `_crown.visible = stage >= 1` ausgeblendet), nicht
  claimbar. Stufen 1–4 = die bisherigen vier Wachstumsstufen mit Ertrag 1/2/3/4.
  Großer Baum (Stufe 4) = **4 Ernten**, `chop_time` 1,5 + 0,5·stage.
  **Randomisiertes Wachstum:** `_next_growth_time()` = `GROWTH_TIME·(1±0,5)`
  (Mittelwert unverändert 75 s); `grow_tick` wächst weiter genau eine Stufe je
  Auslösung. Neu `ignite()`/`is_burning()`/`burn_tick(delta)->bool` (Brand ~1,8 s,
  danach zerstört, kein Holz).
- **TreeManager** (`scripts/core/tree_manager.gd`): `MAX_TREES 250 → 400`.
  `_reproduce` überspringt Stufe-0-/brennende Eltern; `_sprout_near` spross jetzt
  **Stufe 1** (Setzling bleibt der Försterei vorbehalten → Wildwirtschaft
  unverändert). `tick` brennt Bäume ab (`burn_tick` → `_remove_tree`). Neue APIs:
  `trees_in_area(center, radius)` (Chebyshev-Zählung), `can_plant_at(cell, spacing)`
  (walkable + frei + Mindestabstand), `ignite_in_radius(pos, r) -> int`,
  `destroy_in_radius(pos, r)`, `_remove_tree` (Dereg + free).
- **Försterei** (`scripts/buildings/forester.gd` + `scenes/buildings/forester.tscn`,
  `extends Building`): `display_name "Försterei"`, **20 Holz**, Footprint **3×3**,
  HP 250, **4 Arbeiterplätze** (`WORKER_SLOTS`). `_tick_active`: **Mana-Upkeep
  2/s je aktivem Arbeiter** (`tribe.consume_mana`; bei knappem Mana werden Plätze
  von hinten inaktiv, `_active_workers`); **Pflanztempo** über Arbeitssekunden
  (`PLANT_WORK_PER_TREE 60` → 4 Arbeiter = 1 Setzling/15 s), Deckel **30 Bäume**
  im **11×11-Feld** (`PLANT_RADIUS 5`), dichtere Pflanzung `PLANT_SPACING 1`. Ein
  Arbeiter wird zum Pflanzen dispatcht: `_dispatch_plant` → `begin_plant`.
  Slot-API: `reserve_slot`/`admit_worker`/`on_worker_planted`/`reabsorb_worker`/
  `release_worker`/`eject_worker`; `_on_disabled`/`destroy` geben alle Insassen
  frei. Bäume via `unit_manager.tree_manager` (keine neue Injektion nötig).
- **Brave-Förster-Flow** (`scripts/units/brave.gd`): neuer `Unit.State.FORESTER`
  (ans Enum-Ende angehängt → keine Ordinal-Verschiebung). `order_forester`
  (reserviert Slot, läuft zum Eingang), Phasen `JOIN → PLANT_GO → KNEEL → RETURN`
  (`_tick_forester`): hineingehen (aus Welt entfernt via
  `unit_manager.remove_from_world`, zählt weiter zur Bevölkerung), zum Pflanzort
  laufen, **kurz knien** (`attack`-Anim als Platzhalter, 0,8 s), Setzling setzen,
  zurücklaufen, wieder hineingehen. `enter_forester`/`begin_plant`/`leave_forester`;
  Hooks in `_interrupt_tasks`/`_on_combat_interrupt`/`_anim_base`.
- **Holzstapel brennen** (`scripts/core/wood_pile.gd`): `ignite()`/`is_burning()`/
  `burn_tick` (~1,5 s, flackert, dann entfernt). **WoodPileManager**
  (`scripts/core/wood_pile_manager.gd`): `_physics_process`→`tick(delta)` brennt
  Stapel ab; `ignite_in_radius(pos,r)->int`, `piles_in_radius`, `remove_pile`.
- **Feuerquellen zünden Bäume/Stapel:** `FireballBolt._explode` (Splash-Radius),
  `LavaFlow._ignite_touching_units` (Segment-Kontaktradius), `LightningSpell.execute`
  (Einschlag-Radius, gilt auch ohne getroffene Einheit/Gebäude als Erfolg, wenn
  etwas brannte), `FirestormSpell` automatisch über seine `FireballBolt`s. Alle
  über `unit_manager.tree_manager`/`unit_manager.wood_pile_manager` bzw.
  `ctx.*` — kein neues Durchreichen nötig.
- **Tornado** (`scripts/spells/tornado_vortex.gd`): `_shred_trees_and_scatter_piles`
  (im Pickup-Takt): Bäume im Radius werden **zerstört** (`destroy_in_radius`);
  Holzstapel werden **herumgeschleudert ohne Holzverlust** (`remove_pile` +
  `deposit` mit vollem Betrag an einer Zelle jenseits des Trichters, dry-ground-
  Retry via `_scatter_landing`).
- **UI** (`scripts/ui/sidebar.gd`, `scripts/ui/ui_theme.gd`): Baumenü-Eintrag
  „Försterei (20 Holz)"; neues `forester`-Icon (`_draw_seedling`). **Insassen-Panel**
  `_forester_panel` (4 Slot-Buttons), erscheint bei Auswahl einer Försterei
  (`_refresh_forester_panel` jeden Frame); Klick auf besetzten Slot →
  `eject_worker`. Rechtsklick eigener Braves auf die Försterei →
  `TribeCommands.order_forester` (Routing in `selection_manager._dispatch_context_command`).
- **KI** (`scripts/ai/ai_controller.gd`): `_next_building_scene` baut nach Hütte +
  erster Kaserne eine **Försterei**, wenn `_wood_thin_near_base()` (< 6 Bäume im
  22-m-Umkreis des Basis-Ankers) und noch keine existiert — VOR der Expansion.
  `_staff_foresters()` hält bis zu 2 Braves je Försterei besetzt (nie unter
  Wirtschafts-Minimum).
- **Balance** (`scripts/core/main.gd`): `SKIRMISH_BASE_TREES 16 → 12` (4er-Bäume
  liefern mehr Holz).

**Abweichungen/Entscheidungen:**
- Mana-Kosten der Arbeiter = **Dauer-Upkeep 2/s je aktivem Arbeiter** (mit dem
  Nutzer geklärt), nicht per gepflanztem Baum.
- Feuerquellen greifen auf die Manager über die bereits vorhandene
  `UnitManager`-Referenz (`tree_manager`/`wood_pile_manager`) zu bzw. beim Blitz
  über `SpellContext` — der Plan hatte optional zusätzliches Durchreichen
  vorgesehen, das war nicht nötig.
- **Knie-Animation** ist ein Platzhalter (`attack`-Frames); eine echte Crouch-Anim
  gibt es noch nicht (Phase 7e/8).
- Natürliche Vermehrung sprießt als Stufe 1 statt 0 — so bleibt die Wildwirtschaft
  identisch zu vorher; der Setzling ist rein der Försterei vorbehalten.

**Erkenntnisse/Stolpersteine:**
- Housed Braves (aus der Welt entfernt) dürfen im Test **nicht** aus einer festen
  Liste getickt werden — die Test-Tickschleife iteriert `unit_manager.units`
  (die Live-Registry), damit ein Brave nur tickt, während er tatsächlich in der
  Welt ist (JOIN/Pflanzen), nicht während er „drin" sitzt.
- `test_endless_building_scaling` musste eine Försterei in die „volle Basis"
  aufnehmen: ohne Bäume um die (Test-)Basis will die KI jetzt korrekt zuerst eine
  Försterei — die alte Erwartung „nichts zu bauen" galt nur ohne die neue Regel.
- Randomisiertes Wachstum in `test_economy` perturbiert die globale RNG-Sequenz;
  die Kampf-Tests in `test_unit_control` sind wegen unseeded `randf()` ohnehin
  leicht flaky (bekannt) — der Baum-Wachstums-Test nutzt jetzt deterministische
  2×-`GROWTH_TIME`-Schritte (überquert jedes randomisierte Intervall sicher).

**Verifikation:** Testsuite **1033 grün** (neu: `tests/test_forester.gd`, 43 Checks —
Setzling-Pflanzung, Mana-Upkeep/aktive Arbeiter, Rausschicken, Zerstörung/Beschädigung
gibt Insassen frei, Gebiets-Deckel, dichtere Pflanzung, Baumbrand, Holzstapelbrand,
Radius-Zündung, Tornado-Baumschaden + Holzstapel-Wurf ohne Verlust; `test_economy`
auf 5 Stufen umgestellt). `--headless --quit` fehlerfrei; 12-s-Headless-Skirmish
(`-- ai-player`) ohne Script-Fehler. **Manuelle Prüfung durch Nutzer: ausstehend**
(Förster bauen, Braves zuweisen → Arbeiter tritt heraus/kniet/pflanzt/geht zurück,
Insassen-Pips + Rausschicken, Mana sinkt; Feuer/Blitz/Lava entzündet Wald + Stapel;
Tornado zerstört Bäume und schleudert Stapel mit vollem Holz weg).

**Bugfix (Nutzerfeedback nach 7d — Holzablieferung an unerreichbaren Eingang):**
Wurde eine Kaserne (oder ein anderes Gebäude) so gebaut, dass die Eingangszelle
schlecht erreichbar war (Wasser/Hang/Blockade), scheiterte die Wegfindung zur
Ablieferung: Bauarbeiter blieben mit dem Holz stehen (DELIVER-`_seek` schlug
endlos fehl), manuelle Sammler ließen das Holz beim Baum fallen, und das letzte
Holz kam nie an. Fix: neue `Building.delivery_point()` (= `edge_spawn_position()`
— Eingang, sonst nächste begehbare Randzelle). Ablieferung UND Absorption laufen
jetzt über diesen garantiert erreichbaren Punkt: `Brave._tick_deliver` /
`_loose_drop_target` liefern dorthin (mit `allow_direct`), `Building._absorb_piles`/
`_tick_repair_absorb`/`wood_incoming` nehmen Holz im `ABSORB_RADIUS` um diesen
Punkt auf. Regressionstest `test_delivery_survives_unreachable_entrance` in
`test_economy.gd` (Eingang per Nav-Solid blockiert → Bau wird trotzdem fertig).
Tests: **1037 grün**, Ladecheck fehlerfrei.

**Änderung (Nutzerwunsch — Baumaterialwahl mit Feindmeidung):** Bauarbeiter
bevorzugen Holzstapel jetzt nur noch, wenn der Stapel **nah am Bauplatz**
(`Brave.PILE_PREFER_RADIUS 24 m`) **und feindfrei** ist (kein Gegner im
`WOOD_ENEMY_RADIUS 8 m`). Steht ein Feind am Stapel, wird stattdessen ein Baum
**ohne Feinde in der Nähe** gefällt (`_claim_safe_tree` bevorzugt einen sicheren
Baum, fällt sonst auf den nächsten zurück). Neue Helfer in `brave.gd`:
`_best_safe_pile`, `_claim_safe_tree`/`_nearest_claimable_tree`, `_enemies_near`
(nutzt `path_service.get_units_in_radius`). Regressionstest
`test_workers_skip_enemy_guarded_piles` in `test_economy.gd`. Tests: **1041 grün**.

**Fix (Nutzerfeedback — Feuerkrieger-Fernkampf):** Große Feuerkrieger-Trupps
liefen in den Nahkampf und blieben dort stehen (nur 3 bekamen einen
Nahkampf-Slot, der Rest wartete untätig) — ganze Armeen wurden so von wenigen
Predigern bekehrt, weil die Feuerkrieger nicht schossen. Feuerkrieger sind
jetzt echte **Kiter**: sie feuern auf alles in `FIRE_RANGE`, halten Abstand
(weichen zurück, wenn ein Gegner näher als `KITE_MIN_DIST 3,5 m` kommt) und
prügeln nicht mehr / belegen keinen Nahkampf-Slot (`Firewarrior._tick_attack`
neu, `_retreat_from`, `_is_ranged()`). `TribeCommands.order_attack` verteilt
Fernkämpfer nicht mehr über das 3-Nahkämpfer-Limit um (alle feuern auf das
befohlene Ziel). Test `test_firewarrior_brawls_in_melee` → `…_kites_when_crowded`
umgestellt. Tests: **1040 grün**.

**Feinschliff (Nutzerfeedback — Feuerkrieger-Aggro-Radius):** Der Aggro-Radius
ist jetzt pro Einheit überschreibbar (`Unit.aggro_radius()`, Default `AGGRO_RADIUS`
8 m); der Feuerkrieger sieht mit `RANGED_AGGRO 13 m` deutlich weiter — er dreht
auf Bedrohungen jenseits der Feuerreichweite (7 m) ein, verteidigt also auch
einen beschossenen Nachbarn, statt nur auf Gegner direkt neben sich zu
reagieren. Alle Selbst-Aggro-/Retarget-Scans (`_engage_on_sight`,
`_retarget_or_idle`, Alt-Scan im Nahkampf) nutzen jetzt `aggro_radius()`. Test
`test_firewarrior_aggro_reaches_past_melee_radius`. Tests: **1043 grün**.

**Korrektur (Nutzerfeedback — Feuerkrieger kiten war zu stark):** Kein Kiting
mehr. Feuerkrieger halten die Stellung: In Nahkampfreichweite **müssen** sie sich
im Nahkampf wehren, wenn ein Slot frei ist (brave-starker Prügel, kein
Zurückweichen); nur die **Ersatzreihe** (alle 3 Nahkampf-Slots am Ziel belegt)
**feuert** statt untätig zu warten. Zwischen Nahkampf- und Feuerreichweite wird
gefeuert, jenseits `FIRE_RANGE` angerückt. Zusätzlich: greift ein Gegner sie im
Nahkampf an, während ihr Ziel weiter weg steht, drehen sie auf den
Nahkampf-Angreifer (`_melee_threat`). `Firewarrior._tick_attack` neu
(`_retreat_from`/`KITE_MIN_DIST` entfernt). Tests: `test_firewarrior_brawls_in_melee`
(Nahkampf-Wehr) + `test_firewarrior_reserve_row_fires_when_slots_full`. **1047 grün.**

**Feinschliff (Nutzerwunsch — Feuerkrieger priorisieren Prediger):** Feuerkrieger
zielen bevorzugt auf feindliche Prediger in Reichweite (die bekehren ganze
Trupps): `Firewarrior._scan_for_enemy` gibt zuerst den nächsten feindlichen
Prediger im Radius zurück (`_nearest_enemy_priest`), sonst die normale
Zielwahl — greift bei Idle-/Attack-Move-Aggro und beim Retarget nach einem Kill.
Zusätzlich schaltet ein Feuerkrieger mitten im Gefecht (throttled) auf einen
Prediger in Reichweite um, solange er nicht gerade im Nahkampf steht
(Selbstverteidigung im Nahkampf hat weiter Vorrang). Tests
`test_firewarrior_prioritises_enemy_priests` + `…_switches_to_priest_midfight`.
Tests: **1053 grün** (test_unit_control-Kampf-Tests bleiben durch unseeded randf
gelegentlich flaky — nicht durch diese Änderung).

**Erweiterung (Nutzerwunsch — Tornado wirbelt Holz physikalisch):** Statt
Holzstapel nur zu versetzen, wirbelt der Tornado Stapel UND getroffene Bäume wie
Einheiten hoch. Neue Flug-Entität `scripts/spells/tornado_debris.gd`
(`TornadoDebris`, projektil-getickt): spiralt am Trichter hoch (LIFT/CARRY),
wird in einer Parabel weggeschleudert (FLING) und **rutscht** beim Aufprall mit
Reibung aus (SLIDE), bis es als `WoodPile` mit unverändertem Holz zur Ruhe kommt
(kein Rollen wie Einheiten). Ein getroffener Baum wird beim Anheben zum
Holzstapel-Modell (Debris trägt `tree.wood_yield()`); ein zu kleiner Baum
(Setzling, 0 Holz) wird umhergewirbelt und **verschwindet beim Aufprall**
(`vanish`); Landung/Rutschen ins Wasser = Holz verloren. `TornadoVortex`
spawnt jetzt Debris (`_spawn_debris`) statt Stapel zu teleportieren; neue
`TreeManager.uproot_in_radius` (entfernt Bäume, liefert Position + Holz). Tests:
`test_tornado_whirls_trees_and_piles`, `test_tornado_debris_flight` (+ Setzling)
in `test_forester.gd`. **1060 grün**, Ladecheck fehlerfrei.

---

## Phase 7e — 8 Sprite-Blickrichtungen (Diagonalen)

**Gebaut:**
- `scripts/units/unit.gd` — `view_index` von 4 auf **8 Sektoren** umgestellt:
  ein `atan2(dot_right, dot_forward)` liefert den Winkel, `roundi(a / (PI/4))`
  den 45°-Sektor (22,5°-Grenzen), eine Klassen-Konstante
  `SECTOR_TO_VIEW = [1,6,2,4,0,5,3,7]` mappt den Sektor auf den View-Index —
  **reine Arithmetik, keine Verzweigungskaskade** (läuft pro Einheit pro Frame,
  Hot-Path-Regel 7b). Rückgabe **0–7**: 0 front, 1 back, 2 right, 3 left
  (Kompatibilität), 4 front_right, 5 front_left, 6 back_right, 7 back_left.
  Die flach projizierten Kamera-Achsen werden normalisiert (der geneigte
  Forward-Vektor verliert beim Abflachen Länge); die Facing-Magnitude kürzt sich
  in `atan2`. `view_suffix`-Wrapper unverändert.
- `scripts/ui/placeholder_sprites.gd` — `VIEWS` auf 8 Einträge erweitert (Reihen-
  folge = `view_index`-Rückgabe), neue Konstante `MIRRORED_VIEWS`
  (`left`/`front_left`/`back_left` = gespiegelte Rechts-Zwillinge).
  - **Diagonal-Frames prozedural:** Links-Diagonalen werden als ihr
    Rechts-Zwilling gezeichnet und dann `flip_x`. Die Painter sind
    diagonal-fähig: `_draw_torso`/`_draw_arms_side` zeichnen für `front_right`/
    `back_right` eine **3/4-Silhouette** (7 px breiter Rumpf, prominenter
    Nah-Arm + schmaler Fern-Arm) zwischen Profil und Frontal.
  - **Kopf-Tells** in neuer Hilfsfunktion `_paint_face(img, view, top)` (von
    `_draw_head` und `_frame_sit` gemeinsam genutzt, relativ zur Kopf-Oberkante,
    damit die Sitz-Pose sie tiefer wiederverwenden kann): `front_*` = beide Augen
    zur Nahseite versetzt + Haarsträhne an der abgewandten (hinteren) Kopfseite;
    `back_*` = Haaransatz + **ein** Nah-Wangen-Auge, das unter dem Haar
    hervorlugt.
  - **Dekorationen:** `_decorate` normalisiert Diagonalen auf ihre Nahseite
    (`front_right`/`back_right` → `right`, `front_left`/`back_left` → `left`),
    da das Bild für Links-Views bereits gespiegelt ist — Krieger zeigt in der
    Diagonale das Nahseiten-Accessoire (Schwert rechts / Schild links),
    Feuerkrieger einen Nahhand-Feuerball, Prediger/Schamanin ihre Profil-Deko.
    `back_right`-Trage-Pose versteckt das Holz (wie `back`).
  - Nicht-diagonalfähige Sonderposen (`dead`/`roll`) sind view-agnostisch;
    `sit` ist über `_paint_face` jetzt diagonal-fähig. Action-Frames
    (attack/jump/punch/kick/shove/throw/cast) verzweigen weiter nur auf `right`
    → Diagonalen laufen in ihren Frontal-Zweig, kombiniert mit diagonalem
    Rumpf/Kopf/Deko (bewusst simpel; echte Sprites ersetzen später dieselben
    Anim-Namen).
- Atlas/`build_atlas`/`make_frames` unverändert im Aufbau — sie iterieren
  `for view in VIEWS` und liefern damit automatisch **8** View-Einträge je Anim;
  `UnitRenderer` indexiert `views[view]` mit 0–7 (kein Codeänderung, Atlas ~2×).

**Tests:**
- `tests/test_unit_logic.gd`: `test_view_index_diagonals` (4 Diagonal-Headings
  → korrekte Views, Kardinal-Indizes bleiben 0–3, `SECTOR_TO_VIEW`/`VIEWS`
  haben 8 Einträge), `test_view_index_sector_boundaries` (Sweep über alle 8
  Sektorzentren via `fwd*cos+right*sin`, plus gedrehte Kamera). Bestehende
  4-Richtungs-Tests (`test_view_suffix_directions`) laufen unverändert weiter.
- `tests/test_combat.gd`: „punch exists in all **eight** views" (war 4).

**Erkenntnisse:**
- Der 8-Sektor-Lookup ersetzt die 4-fach-Schwellenkaskade durch eine
  Konstanten-Tabelle → gleiche/geringere Hot-Path-Kosten (1× `atan2` + 2×
  `normalized`, wie zuvor die 2 Normalisierungen der 4-Wege-Variante).
- Weil die gesamte Atlas-Tabelle über `VIEWS` iteriert, genügt für 8 Views das
  Erweitern der Konstante + diagonalfähige Painter; Renderer und Tabellenformat
  bleiben unangetastet.

**Verifikation:** Testsuite grün (**1079 Tests, 0 Fehler**),
`--headless --quit` fehlerfrei (lädt den ~2× größeren Atlas ohne Fehler).
**Manuelle Optik-Prüfung ausstehend** (durch Nutzer): Kamera per Q/E um
stehende/laufende Einheiten aller Typen drehen → 8 klar unterscheidbare
Ansichten, kein Flackern an den 22,5°-Sektorgrenzen, kein Frame-Neustart beim
Ansichtswechsel; F9-Stresstest → keine Perf-Regression.

**Korrektur (Nutzertest — Diagonal-Accessoires saßen daneben):** Krieger- und
Feuerkrieger-Deko lag in den Diagonalen auf der **Profil**-Handposition (Einhand,
x7), während der 3/4-Körper zwei Arme an x4 (fern) / x11–12 (nah) hat → Feuerball
schwebte, obwohl zwei Hände sichtbar waren. Fix: Diagonalen zeigen jetzt **beide**
Accessoires an den echten Handpositionen des 3/4-Frames (Feuerkrieger: zwei
Feuerbälle an beiden Händen; Krieger: Schwert an der Nah-, Schild an der
Fernhand). Umgesetzt, indem Diagonalen in ihrer **Rechts-Form vor dem Spiegeln**
dekoriert werden (`DIAGONAL_PAINT_VIEWS`), sodass `flip_x` Körper UND Accessoires
gemeinsam auf die Links-Diagonalen mappt — die Kardinal-Seitenansichten bleiben
wie bisher (spiegeln zuerst, dekorieren dann in der realen View). Tests weiter
**1079 grün**, Ladecheck fehlerfrei. Erneute manuelle Optik-Prüfung ausstehend.

**Korrektur 2 (Nutzertest — Prediger-Auge in den Front-Diagonalen verkehrt):**
Bei `front_right` lag das **nahe** Auge auf x10 — genau unter der rechten
Kapuzenwange (x10–11) und damit verdeckt; sichtbar blieb nur das **ferne** Auge
(x7), das Gesicht wirkte falsch gedreht. `_paint_face` legt die Diagonal-Augen
jetzt auf x6/x9 (frei von den Kapuzenwangen x4–5 / x10–11); die Drehung wird
über den verkürzten Haaransatz an der Fernkante erzählt. `back_right`-Peek-Auge
analog von x10 → x9. Tests **1079 grün**, Ladecheck fehlerfrei.

**Manuelle Optik-Prüfung durch Nutzer bestanden (2026-07-07):** 8 Ansichten klar
unterscheidbar, Diagonal-Accessoires (Krieger Schwert/Schild, Feuerkrieger zwei
Feuerbälle) und Prediger-Augen sitzen korrekt. Phase 7e abgeschlossen.

---

## Phase 7f — Belagerungswaffe (Katapult) & Werkstatt

**Vorbemerkung (bewusste Abweichung von der Phasenreihenfolge):** Laut Overview
war 7f NACH 7g/7h geplant (generisches Gebäude-Targeting aus 7g als Basis). Auf
Nutzerentscheidung wurde 7f **eigenständig** umgesetzt: Das Katapult bringt sein
EIGENES Gebäude-Targeting mit (`order_attack_building` + Auto-Scan nur auf der
`SiegeEngine`); 7g liefert später das generische Targeting für alle Einheiten
und kann die Siege-Pfade darauf umziehen.

**Gebaut:**
- `scripts/buildings/workshop.gd` + `scenes/buildings/workshop.tscn` —
  **Werkstatt**: 15 Holz, Footprint **8×4** (doppelte Hüttenfläche), HP 350.
  KEINE `TrainingBuilding`-Subklasse (bewusste Abweichung vom alten Planstand):
  Arbeiter werden nicht verbraucht, sondern sind eine **stehende Crew (max 3)**
  auf dem Bau-Job-System (`Building.workers`, `join()`-Override mit 3er-Cap).
  Kern-APIs: `stock_wood()` (Holzvorrat = Stapel am Eingang, Ziel 15;
  `wants_more_stock_wood()` zählt getragenes/reserviertes Holz mit),
  `can_start_production()` (usable + nicht pausiert + Ausgang frei + Kap nicht
  erreicht + ≥5 Holz), `add_production_work(delta)` (Arbeiter-Sekunden;
  **90 je Katapult** → 3 Arbeiter ≈ 30 s; Start verbraucht 5 Holz sichtbar aus
  den Stapeln, **keine Erstattung**), `exit_blocked()` (fertiges Katapult ≤3 m
  vor dem Eingang blockiert die nächste Fertigung), `manned_catapult_count()`,
  `paused` (Toggle) und `max_catapults` (Default 3, 0–20). Abbruchregeln:
  Beschädigung (Stufe ≥1) oder „alle Arbeiter weg" → Produktion + Holz verloren;
  beschädigte Werkstatt wird von der Crew über die Repair-Pipeline repariert
  und danach weiterbetrieben. Auto-Bemannung: nach Fertigstellung entern bis zu
  **2 idle Braves** (≤12 m, one-shot) das neue Katapult.
- `scripts/units/siege_engine.gd` + `scenes/units/siege_engine.tscn` —
  **SiegeEngine** (`unit_kind &"siege"`): **Fahrzeug**, kein Gläubiger.
  **Nicht direkt angreifbar** (`is_targetable() false`, `take_damage` no-op,
  wurf-/roll-/panik-/bekehrungs-/feuerimmun; nur Wasser zerstört es via
  `drown`). Zählt nicht als Bevölkerung (`counts_population false` →
  `Tribe.population()` filtert), erzeugt kein Mana. Speed **3.0** (0,75×Brave),
  `push_immune` (Separation schiebt es nicht). **Crew-System**: `add_crew`/
  `on_crew_boarded`/`boarded_count` (dient ab Board + ≤8 m Leash),
  min 1 Crew für Bewegung, min 2 zum Feuern; Feuerrate
  `fire_cooldown_for_crew`: 2→6 s … 6→3 s linear; max 6 (3 je Längsseite,
  `crew_slot_position` wandert mit `facing` mit). **Besitz folgt der Crew**:
  Entern eines unbemannten Katapults beliebiger Herkunft übernimmt es
  (`_switch_owner` via `convert_to_tribe`); bemannte fremde Geräte sind nicht
  kapierbar. Angriff: Band **3–15 m** (darunter Feuerpause, darüber
  Nachrücken), `order_attack_building` + **Auto-Aggro Gebäude VOR Einheiten**
  (invers zur Normalregel; `building_manager` wird per `unit.set()` injiziert).
  Rendering: **eigenes 3D-Modell** (Rahmen, 4 Räder, Wurfarm mit
  Abschuss-Animation, Besitzerfahne) statt Sprite-MultiMesh
  (`renders_as_sprite() false`).
- `scripts/units/siege_shot.gd` — **SiegeShot**: großer Feuerball in hoher
  Parabel (ARC 6 m) mit Glut-Schweif. Einschlag: feindliches Gebäude im
  (+1 gewachsenen) Footprint → `apply_destruction_stages(1)` (Baustelle
  zerschellt, Fragil-Regel) **und stationierte Insassen sterben**
  (`TrainingBuilding.trainee`, gehauste `Forester`-Arbeiter); **eigene Gebäude
  nie beschädigt**. Ohne Gebäudetreffer: kleine, schnell verschwindende **Lava**
  (`LavaSurge` mit Radius 0,8). Immer: **Schockwelle 2 m** — 15 Schaden
  (¼ Brave-Leben) auf ALLE Einheiten (Friendly Fire), Gegner mit
  Slope-abhängiger Roll-Chance (`roll_chance_for_slope`: flach 40 % / ab 0,2
  Steigung 80 % / ab 0,6 100 %), Rolldauer min. **1 s**.
- `scripts/units/unit.gd` — neuer **State `CREW`** (angehängt) + Crew-Felder
  (`siege_engine`, `siege_boarded`, `push_immune`, `counts_population`):
  `order_crew` (alle außer Schamanin, `can_crew_siege()`), `leave_crew`
  (Move-Order, Konversion und Tod verlassen die Crew), `_tick_crew` (läuft zum
  Seiten-Slot, Boarding bei ≤2,5 m). `_maybe_retaliate` feuert jetzt auch aus
  CREW (Crew verteidigt sich, bleibt per Leash Crew und kehrt zurück —
  `_resummon_crew` holt IDLE-Mitglieder an die Slots). `_scan_for_enemy`
  filtert `is_targetable()`. **Roll-Härtung (§9):** `begin_conversion` lehnt
  ROLL/THROWN/PANIC ab (Prediger kann rollende/fliegende Einheiten nicht mehr
  in SIT reißen).
- `scripts/units/shaman.gd` — `_on_combat_interrupt` → `_cancel_cast()`:
  Roll/Wurf/Kampf brechen einen laufenden Cast sauber ab (vorher blieb
  `pending_spell` als Leiche stehen; Ladung bleibt erhalten).
- `scripts/units/brave.gd` — `order_workshop` + **`Task.PRODUCE`**
  (`_tick_produce` hämmert `add_production_work`), `_choose_workshop_task`
  (Priorität: laufende Produktion > Vorrat auffüllen > Produktion starten),
  `_job_active`/`_job_wants_wood` um Werkstatt erweitert; Holz-Beschaffung
  läuft über die vorhandene CHOP/PICKUP/DELIVER-Pipeline an den
  `delivery_point`.
- `scripts/core/nav_grid.gd` — **Fahrzeug-Navigation**: zweites `AStarGrid2D`,
  Zelle fahrzeug-passierbar, wenn ein voll begehbarer **2×2-Block** sie enthält
  (1-Zellen-Lücken bleiben zu); `find_vehicle_path`,
  `is_cell_vehicle_walkable`, Sync über `update_region`/`fill_solid_region`
  (`_refresh_vehicle_region` mit grow(1)). `SiegeEngine._plan_path_to` nutzt
  den Fahrzeug-Pfad.
- `scripts/core/unit_manager.gd` — Renderer-Registrierung nur für
  `renders_as_sprite()`, Separation überspringt `push_immune`, neues Feld
  `building_manager` (Main verdrahtet es; `spawn_unit` injiziert per `set()`).
- `scripts/core/tribe_commands.gd` — `order_crew`, `order_attack_building`
  (wirkt NUR auf SiegeEngines — Braves/Krieger ignorieren den Befehl),
  `order_workshop`; `order_attack` lehnt untargetable Ziele ab.
  `place_building` dreht nicht-quadratische Footprints bei Ost/West-Eingang
  (Swap x/y), ebenso `BuildingManager.place` und der `BuildMenu`-Ghost
  (`_effective_footprint`, Box-Resize bei R-Rotation).
- `scripts/ui/selection_manager.gd` — Rechtsklick-Routing: (1) Katapult unter
  dem Cursor (eigen ODER unbemannt) + crewfähige Selektion → `order_crew`;
  (2) Feindgebäude + SiegeEngines in der Selektion → `order_attack_building`,
  Rest eskortiert per Attack-Move; (3) eigene nutzbare Werkstatt →
  `order_workshop`. Feind-Pick überspringt untargetable Katapulte.
- `scripts/ui/sidebar.gd` — Baumenü „Werkstatt (15 Holz)", Follower-Zeile
  „Belagerungswaffe" (`&"siege"`), **Werkstatt-Panel** (Arbeiter x/3, Vorrat
  x/15, bemannte Katapulte, Pause-Toggle, Max-Katapulte −/+);
  `scripts/ui/ui_theme.gd` — `workshop`-Icon (Katapult-Piktogramm).
- `scripts/ai/ai_controller.gd` — Werkstatt im Grundausbau **nach dem Tempel**
  (1×), `_staff_workshops` (bis 3 idle Braves, Wirtschafts-Minimum beachtet),
  `_army_units` nimmt **bemannte** Katapulte in Angriffs-/Verteidigungswellen
  auf (Auto-Bemannung der Werkstatt gilt symmetrisch für die KI).

**Tests:** `tests/test_siege.gd` (neu, 96 Checks): Fertigung (Arbeiter-Sekunden,
5-Holz-Verbrauch, Arbeiter bleiben erhalten, 3er-Cap, Integration mit echten
Braves < 60 s), Stall ohne Holz + Wiederanlauf, Pause, Max-Kap (bemannt
gezählt), Eingang-Blockade, Abbruch ohne Rückerstattung (Arbeiterabzug +
Beschädigung), Auto-Bemannung, Crew-Gates (1/2/6), Übernahme unbemannter /
Schutz bemannter Katapulte, Nicht-Angreifbarkeit (Scan + order_attack +
take_damage), Schamanin-Verbot, Beschuss (+1 Stufe, Insassen-Kill, eigenes
Gebäude heil, Baustelle zerschellt), Schockwelle (Friendly Fire, Radius),
Roll-Chance-Bänder, Reichweiten-Band + Auto-Gebäude-Priorität +
`order_attack_building`-Ablehnung für Nicht-Siege, Fahrzeug-Korridore
(1 Zelle zu / 2 Zellen offen), Roll-Härtung (Angreifer/Prediger/SIT-Opfer/
Schamanin). `test_ai.gd`-Vollausbau um die Werkstatt ergänzt.

**Erkenntnisse/Stolpersteine:**
- `_prune_crew` darf fremde, noch NICHT geboardete Rekruten nicht rauswerfen —
  sonst bricht die Übernahme unbemannter Katapulte (Leash gilt nur für
  geboardete Mitglieder); außerdem `leave_crew` nie mid-iteration über `crew`
  aufrufen (`remove_crew` mutiert die Liste).
- `queue_free()` außerhalb des Szenenbaums wird in Headless-Tests nicht
  geflusht → Insassen-Kill nutzt `is_inside_tree() ? queue_free : free`.
- Teleport-Tests müssen die Crew MIT versetzen, sonst leasht sie aus und das
  Katapult ist bewegungsunfähig.
- Nicht-quadratische Footprints brauchten den Orientierungs-Swap an DREI
  Stellen (Validierung, Platzierung, Ghost) — für quadratische Gebäude no-op.

**Verifikation:** Testsuite grün (**1175 Tests, 0 Fehler**),
`--headless --import` und `--headless --quit` fehlerfrei.
**Manuelle Prüfung ausstehend** (durch Nutzer, siehe Plan 7f): Werkstatt bauen,
Vorrat/Produktion/Pause/Max-Grenze im Panel, Auto-Bemannung, Crew-Verhalten
(Verteidigung + Rückkehr, Übernahme), Beschuss-Optik (Bogen + Schweif, Lava,
Umwerfen), KI-Match mit Katapulten.

**Überarbeitung nach Nutzertest (2026-07-07):**
1. **Werkstatt auf das Förster-Arbeitersystem umgestellt** (ohne Mana-Upkeep):
   `occupants`-Slots (3) mit `reserve_slot`/`admit_worker`/`eject_worker` —
   Arbeiter werden per Befehl zugewiesen, im Gebäude **gehaust** (aus der Welt
   genommen; die Werkstatt trägt ihre Arbeiter-Sekunden selbst bei) und kommen
   nur zum Holzholen heraus (`_dispatch_fetch` → vorhandene
   CHOP/PICKUP/DELIVER-Pipeline → `admit_worker` beim Rückweg). Sidebar-Panel
   mit 3 Slot-Buttons (rausschicken) wie beim Förster. **Bugfix:** Die
   BAU-Arbeiter der Werkstatt übernahmen nach Fertigstellung nahtlos die
   Produktion (bis zu 8 ohne Befehl) — `_job_active` bindet Werkstatt-Arbeiter
   jetzt nur noch über einen gehaltenen Slot; Bauarbeiter werden bei
   Fertigstellung freigegeben (Test `test_construction_workers_are_not_auto_hired`).
   Kein reachbares Holz → `mark_wood_stalled` (30-s-Recheck) statt
   Rein/Raus-Pingpong. `add_production_work` entfällt (Tick-getrieben).
2. **Zielpriorität umgedreht: EINHEITEN vor Gebäuden** (auch mitten im
   Gebäudebeschuss wird auf ankommende Einheiten gewechselt; Gebäudefokus
   bleibt als Fallback). Aggroradius 16 → **20 m**. **Befehls-Fix:**
   `order_attack` räumt den Gebäudefokus (vorher übersteuerte die alte
   Gebäude-Priorität stillschweigend explizite Einheiten-Befehle —
   die gemeldete Unzuverlässigkeit); Einheiten-Scans überspringen Ziele
   innerhalb der 3-m-Mindestreichweite, ein Ziel das hineinkriecht wird
   (throttled) gegen ein triffbares getauscht.
3. **Speed 3.0 → 2.0** (0,5 × Brave).
4. **Crew nicht mehr einzeln selektierbar:** Klick/Box auf ein Crew-Mitglied
   selektiert das KATAPULT (`_crew_to_engine`-Mapping in Pick/Box;
   Doppelklick-Typselektion überspringt Crew). Katapult zeigt einen
   **großen Auswahlring** (`selection_ring_scale` 4,5×, Ring-Renderer
   skaliert per Instanz-Transform). Crew-Verwaltung über das neue
   **Besatzungs-Panel** im Sidebar (6 Slots, „aussteigen" je Mitglied),
   sichtbar wenn genau ein Katapult selektiert ist.
5. **Zerstörungswege des Katapults:** (a) **Feuerzauber** (FireballBolt →
   auch Feuerregen) und **Lava** (`ignite`) setzen es in Brand
   (Flammen-Overlay, 3 s) → es versinkt im Boden (`_sinking` im DEAD-Visual);
   (b) **Terrainriss**: Höhenspanne unter dem Chassis > 3,5 m (bewusst über
   dem fahrbaren Maximum — begehbare Zellen erlauben 1,5 m/Zelle) → es
   **zerplatzt** (BuildingDebris-Burst, Modell verschwindet); (c) Wasser
   (`drown`) versinkt wie gehabt. In allen Fällen überlebt die **Crew**, wird
   freigegeben und ist wieder einzeln steuerbar (sie nimmt Flächenschaden
   weiterhin normal, da sie als normale Einheiten neben dem Gerät stehen).

Tests: Werkstatt-Sektion auf das Slot-System umgeschrieben (+ Dispatch-Test,
Bauarbeiter-Bugtest), Prioritätstest umgedreht (+ Befehls-Override-,
Fallback-Test), neue Tests für Brand (Feuerball + Lava), Terrainriss-Burst,
Crew-Überleben und das Selektions-Mapping. **1199 Tests, 0 Fehler**,
Ladecheck fehlerfrei. Manuelle Prüfung erneut ausstehend.

**Überarbeitung 2 nach Nutzertest (2026-07-07):**
1. **Katapult-Targeting robust „feuern statt jagen"** (`siege_engine.gd`): Der
   gemeldete Bug „fährt rein und schießt nicht" kam vom **Auto-Verfolgen von
   Einheiten** — als langsamste Einheit trottete das Katapult ewig hinter
   fliehenden Zielen her, ohne je in Reichweite zu feuern. Neu: `_auto_acquire`
   (idle **und** Angriffsbewegung teilen dieselbe Akquise) feuert nur, was
   **bereits im Feuerband** (`_nearest_enemy_unit(FIRE_RANGE)`) steht
   (Einheiten bevorzugt), und nähert sich sonst dem nächsten **Gebäude** in
   Aggro (stationär → erreichbar). Einheiten werden NIE automatisch verfolgt.
   Neues Flag `_target_ordered` (gesetzt nur in `order_attack`, gelöscht in
   jedem `_end_attack`): **nur explizit befohlene** Einheitenziele werden aus
   dem Band heraus verfolgt (`_bombard_unit`), Auto-Ziele fallen zurück.
   `_retarget_or_idle` überschrieben (sonst hätte die geerbte Version wieder
   die nächste Einheit auf jede Distanz gepackt). `_bombard` in
   `_bombard_unit`/`_bombard_point` aufgeteilt. So stoppt ein hineingeschicktes
   Katapult zuverlässig und beschießt Gebäude/Einheiten in Reichweite.
2. **Reichweitenanzeige, Taste G** (`scripts/ui/range_renderer.gd`, neu): Ein
   MultiMesh aus flachen Ringen (per-Instanz-Farbe) zeigt auf Knopfdruck die
   Reichweiten der **eigenen** Feuerkrieger (7 m), Prediger (5 m) und Katapulte
   (15 m + dünner innerer 3-m-Mindestreichweiten-Ring). Toggle über neue
   Input-Action `toggle_ranges` (G); in Main verdrahtet
   (`ranges.setup(unit_manager, player)`). **Besatzungen werden übersprungen**
   (`unit.siege_engine != null`), sie haben keine eigene Reichweite. Statischer
   Helfer `range_for_kind(kind)` (headless-testbar).

Tests: neue Fälle `test_engine_does_not_auto_chase_units` (Out-of-Band-Einheit
wird ignoriert, Gebäude in Aggro stattdessen angefahren),
`test_engine_chases_ordered_unit` (explizit befohlene Einheit wird verfolgt +
beschossen), `test_range_renderer_ranges` (Reichweiten je Kind, Crew/Nahkämpfer
= 0). **1211 Tests, 0 Fehler**, Ladecheck fehlerfrei. Manuelle Prüfung erneut
ausstehend (v. a.: Katapult per Angriffsbewegung in die Basis → stoppt und
feuert; G blendet Reichweitenringe ein/aus).

**Überarbeitung 3 nach Nutzertest (2026-07-07):**
1. **Reichweitenringe folgen dem Gelände** (`scripts/ui/terrain_ring.gd`, neu):
   Wiederverwendbarer `TerrainRing.add_band(im, center, radius, td, color)` —
   eine dünne Ring-Bahn als Triangle-Strip, deren Stützpunkte pro Winkel auf
   die Terrainhöhe gehoben werden (kein flacher Disc, der in Hügeln versinkt).
   `RangeRenderer` von MultiMesh auf ein pro Frame neu gebautes ImmediateMesh
   umgestellt; `SpellTargeting` zeichnet Cast-Range-Ring (um die Schamanin)
   und Cursor-Ring jetzt ebenfalls terrain-folgend (world-origin
   ImmediateMesh, pro Frame neu). Flatten-Quadrat unverändert (Sonderfall).
2. **Katapult wird nach Bemannung vom Eingang weggefahren**
   (`workshop.gd`): `_maybe_dispatch_engine` schickt das frische Katapult,
   sobald ≥1 Crew an Bord ist, per `order_move` zum Auslieferungspunkt
   (`_dispatch_point`: gesetzter Rally-Point, sonst ein paar Meter entlang der
   Eingangs-Normalen) — der Bauplatz wird frei, das nächste Katapult kann
   gebaut werden. Ohne Crew in der Nähe bleibt es stehen (unverändert).
3. **Crew läuft mit dem Katapult statt zu teleportieren** (`unit.gd`
   `_tick_crew`): Beim Anmarsch zum Boarding eigenes Tempo; **an Bord** folgt
   die Crew ihrem Seiten-Slot **im Katapult-Tempo** (mit kleinem
   Aufhol-Boost nach Drehungen/Boarding) statt in schnellen Sprüngen (die
   schnellere Crew „dash-and-wait" wirkte wie Teleportieren). Neues Flag
   `_crew_walking` treibt die Lauf-Animation im CREW-Zustand (unabhängig von
   einem A*-Pfad).
4. **Angriffsbewegung läuft nach dem Kampf weiter** (`unit.gd`
   `_retarget_or_idle` — gilt für ALLE Einheiten): Ist der Kampf vorbei und
   kein Gegner mehr da, wird ein noch anstehender Wegpunkt (das
   Attack-Move-Ziel) wieder aufgenommen (`_start_path_to`) statt am Ort zu
   verharren. Für das Katapult zusätzlich: Auto-Beschuss von Gebäuden behält
   die Route (`_set_building_target(..., keep_route=true)`), explizite Befehle
   ersetzen sie; das Katapult-`_retarget_or_idle` nimmt die Route ebenfalls
   wieder auf.

Tests: `test_terrain_ring_builds_surface`, `test_attack_move_resumes_after_combat`
(deterministisch, ohne Kampf-RNG), `test_crew_walks_with_engine` (gebundene
Schrittweite ≈ Katapult-Tempo, Formation gehalten),
`test_workshop_dispatches_crewed_catapult` (Katapult verlässt den Bauplatz nach
Bemannung). **1227 Tests, 0 Fehler**, Ladecheck fehlerfrei. Manuelle Prüfung
erneut ausstehend.

**Erweiterung 4 nach Nutzerwunsch (2026-07-07) — Tornado wirkt aufs Katapult:**
Bisher saugte der Tornado nur die **Crew** ein (normale Einheiten); das
Katapult selbst war wurf-immun. Neu (`tornado_vortex.gd` +
`siege_engine.gd`): Ist der Tornado ≥ **2 s durchgehend** innerhalb
`SIEGE_NEAR_RADIUS` (**2 m**) eines Katapults, wird das Gerät währenddessen
sichtbar **angehoben** (`SiegeEngine.set_tornado_lift`, hover bis 4 m) und
**zerplatzt** dann: `SiegeEngine.burst_into_wood()` gibt die Crew frei und
zerstört das Gerät (ohne eigenes Trümmer-Mesh), der Vortex spawnt **zwei
1-Holz-Trümmer** (`TornadoDebris`), die wie jedes hochgewirbelte Holz
weggeschleudert werden und als 1-Holz-Stapel liegen bleiben. Verlässt der
Tornado den 2-m-Radius vor Ablauf, wird der Timer zurückgesetzt und das
Katapult sinkt wieder ab (die 2 s müssen durchgehend sein). Umgesetzt in
`TornadoVortex._affect_siege_engines`/`_burst_siege` (pro Tick mit echtem
delta). Tests: `test_tornado_lifts_and_bursts_catapult` (Lift < 2 s, Burst ≥ 2 s,
zwei 1-Holz-Chunks → 2 Holz am Boden), `test_tornado_near_reset_spares_catapult`
(unterbrochene Nähe akkumuliert nicht). **1235 Tests, 0 Fehler**, Ladecheck
fehlerfrei. Manuelle Prüfung ausstehend.

**Bugfix (Nutzertest 2026-07-07) — Phantom-Routenmarker an fertigen Arbeitern:**
Wählte man Arbeiter nach getaner Arbeit aus, zeigten sich manchmal
Ziel-/Routenmarker (z. B. an einer alten Baumstelle), obwohl niemand dorthin
läuft. Ursache: `Brave._interrupt_tasks` räumte Aufgaben/Claims und `_path`
(`_reset_seek`) ab, **nicht aber `waypoint_queue`**. Wird ein Brave mitten in
einer Bewegung zu einem Job rekrutiert (order_build/chop/pray/train/forester/
workshop) — oder fällt er nach dem Job über `_interrupt_tasks` → IDLE —, blieb
die alte Bewegungsabsicht als Wegpunkt hängen; der `RouteVisualizer` zeichnete
dafür einen Marker. Fix: `_interrupt_tasks` leert jetzt zusätzlich
`waypoint_queue` (Beginn eines Arbeitsauftrags verwirft die Laufabsicht). Der
Attack-Move-Resume bleibt unberührt (fliehende/laufende Braves sind im
MOVE-Zustand und lösen `_interrupt_tasks` beim Retaliieren nicht aus). Test
`test_worker_order_clears_stale_move_waypoint`. **1238 Tests, 0 Fehler**,
Ladecheck fehlerfrei.

---

## Phase 7g — Gebäudezerstörung durch Einheiten (Sturmangriff) (umgesetzt)

Einheiten können gegnerische Gebäude ohne Zauber schleifen: **Nahkampfsturm**
(durch den Eingang eindringen, Insassen auswerfen, von innen demolieren) und
**Feuerkrieger-Fernbeschuss** (halb so effektiv). Gebäude sind **immer die
niedrigste Zielpriorität** (erst Feindeinheiten, dann Gebäude).

**Gebaut:**
- `scripts/buildings/building.gd` — **Raider-Registry** (`raiders: Array`,
  untypisiert wie Trainee/Crew): `max_melee_raiders()` (Basis
  `MAX_MELEE_RAIDERS = 15`, Turm überschreibt in 7h), `admit_raider(unit)`
  (voll → false; nimmt bis Limit, `remove_from_world` + `enter_building_as_raider`;
  **erster Raider** startet den Sturm → `eject_occupants(false)` + Wackel-Visual),
  `_prune_raiders`, `_tick_raid(delta)` (`RAID_DPS_PER_RAIDER = 6` HP/s ×
  Raiderzahl, in `tick()` außerhalb des `is_usable`-Gates), `_release_raiders`
  (bei `destroy()` treten alle Demolierer **lebend/IDLE** am Rand aus, nach
  Footprint-Freigabe). **Auswurf-Hooks:** `eject_occupants(killed)` (Basis leer),
  `_on_disabled()` → `eject_occupants(false)` (lebender Auswurf für Zauber).
  **Schadensquelle:** `take_damage(amount, source = DMG_GENERIC/DMG_RANGED)` —
  überschreitet **Fernkampf** allein Stufe 1 (`raiders.is_empty()`), sterben die
  Insassen (`eject_occupants(true)`); Zauber/Nahkampf werfen lebend aus. Produktion
  pausiert, solange Raider drin sind (`_tick_active`-Gate um `raiders.is_empty()`).
  **Wackel-Visual:** `_process` schwingt `_mesh_root` (Rotation z/x, Sinus ~0,8 Hz,
  ±2°) solange Raider drin sind (nur in-game); `_process` unterscheidet jetzt
  Sink-Phase (`_destroyed`) vs. Wackeln.
- `scripts/buildings/training_building.gd` — `_on_disabled`-Override durch
  `eject_occupants(killed)` ersetzt: `killed = true` → Trainee wird am Auswurfpunkt
  registriert und **getötet** (`take_damage(health+1000)` → Leiche, Pop −1);
  `killed = false` → registriert, `cancel_training`, **rausgeschubst + Mini-Roll**
  (`_shove_out`). Warteschlange wird immer freigegeben. `destroy()` (Trainee-Kill
  bei Kollaps) unverändert.
- `scripts/units/unit.gd` — neuer **`State.RAID`** (angehängt; Demolierer sind aus
  der Welt, nicht angreifbar/selektierbar) + Felder `attack_building`,
  `building_manager` (beide **jetzt in der Basis**, von SiegeEngine geerbt),
  `raiding_building`. Neu: `order_attack_building(b)` (expliziter Befehl, alle
  Typen, räumt Route), `_begin_attack_building(b)` (Auto-Scan, behält Route),
  `_building_target_valid`, `_clear_building_target` (in `order_move`/`_die`/
  `convert_to_tribe`), `_try_engage_building`, `_scan_for_enemy_building`
  (Feindgebäude im Aggro-Radius, Kandidaten-Cap), `_tick_no_unit_target`
  (kein Einheitenziel → Gebäude-Assault, Einheiten bleiben Vorrang),
  `_assault_building` (ranged → `_bombard_building`, sonst `_storm_building`),
  `_storm_building` (zum Eingang laufen → `admit_raider`, voll → `_wait_near_point`),
  `_bombard_building` (Basis no-op), `_wait_near_point`, `enter/exit_building_as_raider`.
  `_engage_on_sight`/`_retarget_or_idle` bekommen den Gebäude-Fallback (niedrigste
  Priorität); `_tick_attack` routet fehlendes Einheitenziel über
  `_tick_no_unit_target`.
- `scripts/units/firewarrior.gd` — `_tick_attack` fällt bei fehlendem
  Einheitenziel auf `_tick_no_unit_target` (Gebäude-Assault); `_bombard_building`
  (in `FIRE_RANGE` stehen, `throw`-Anim, alle `FIRE_COOLDOWN` ein Feuerball aufs
  Gebäude) + `_throw_fireball_at_building`. `BUILDING_FIRE_DAMAGE = 5` (≈ halber
  Nahkampf-DPS: 5/1,5 s ≈ 3,3 vs. 6 HP/s).
- `scripts/units/preacher.gd` — `_engage_on_sight`-Fallback `_try_engage_building`
  (Prediger stürmt als Nahkämpfer, wenn nichts zu bekehren/duelieren ist).
- `scripts/units/fireball.gd` — `target_building` + `setup_building` + `_tick_building`
  + `_impact_building` (`building.take_damage(BUILDING_FIRE_DAMAGE, DMG_RANGED)`,
  `BUILDING_HIT_RANGE = 1,6`).
- `scripts/units/siege_engine.gd` — doppelte `attack_building`/`building_manager`
  entfernt (jetzt geerbt); Siege-Logik unverändert (eigenes `_tick_attack`/
  `order_attack_building`/`_retarget_or_idle`).
- `scripts/core/tribe_commands.gd` — `order_attack_building(units, building)`
  wirkt jetzt auf **alle** Einheitentypen (nicht mehr nur SiegeEngine); eigenes
  Gebäude/eigener Stamm wird übersprungen.
- `scripts/ui/selection_manager.gd` — Rechtsklick auf Feindgebäude schickt die
  **ganze** Selektion in `order_attack_building` (kein Siege/Escort-Split mehr).
- `scripts/core/building_manager.gd` — `tick` iteriert `buildings.duplicate()`
  (ein per Raid mitten im Tick zerstörtes Gebäude meldet sich sonst mitten in
  der Iteration ab).

**KI:** keine Heuristik-Änderung nötig — die KI greift bereits per **Attack-Move**
(`order_move(..., aggressive = true)`, `ai_controller.gd:348/397`) an; der neue
Gebäude-Scan-Fallback in `_engage_on_sight` lässt die Wellen erst Verteidiger,
dann die Basis schleifen (400-Frame-Headless-Lauf fehlerfrei).

**Dokumentierte Auslegungen:** Demolierer im Gebäude sind aus der Welt (nicht
angreifbar/selektierbar, kein Gegensturm in V1). Braves stürmen nur auf expliziten
Befehl (nicht combatant → kein Auto-Scan). Idle-Combatants (Krieger/Feuerkrieger/
Prediger) und Attack-Move zählen Feindgebäude im Aggro-Radius als niedrigste
Priorität.

**Tests:** `tests/test_building_assault.gd` (neu, 60 Checks): Raider-Cap (20 →
15 drin/5 warten), DPS-Skalierung (2× Raider = 2× Schaden), Demolierung bis
Kollaps + lebender Raider-Austritt + Footprint frei, Sturm wirft Trainee lebend
aus, Fernkampf-Stufe-1 tötet Insassen / Zauber-Stufe-1 wirft lebend aus / kein
Doppel-Auswurf nach Nahkampfsturm, Feuerball-Gebäudeschaden = halber DPS,
Prioritäts-Tests (Einheit vor Gebäude, einzelnes Gebäude wird angegriffen, Brave
ignoriert Gebäude), Order-Routing (alle Typen, eigenes Gebäude abgelehnt),
Move-Order bricht Assault ab, Voll-Pipeline (befohlene Krieger stürmen und
schleifen). `test_siege.gd`-Fall „order_attack_building" auf das neue
Alle-Typen-Verhalten umgestellt.

**Erkenntnisse/Stolpersteine:**
- `attack_building`/`building_manager` mussten von SiegeEngine in die Basis
  wandern (Doppel-Deklaration wäre ein Parse-Fehler); Siege-Overrides bleiben
  unberührt, da sie `_tick_attack`/`order_attack_building` komplett ersetzen.
- Raider werden im **UnitManager-Unit-Loop** (der `units.duplicate()` iteriert)
  über `remove_from_world` aus der Welt genommen — mitten im Tick sicher.
- `BuildingManager.tick` musste auf `buildings.duplicate()` umgestellt werden, weil
  Raid-Schaden ein Gebäude in seinem eigenen Tick zerstören kann.

**Verifikation:** Testsuite grün (**1298 Tests, 0 Fehler**), `--headless --import`,
`--headless --quit` und `--headless --quit-after 400` fehlerfrei.

**Nachbesserung 1 nach Nutzertest (2026-07-07):**
1. **Schamanin unangreifbar für Nah-/Fernkampf** (nur Zauber + Katapulte): neue
   `Unit.is_targetable_by_units()` (Basis true, `Shaman` false) + `_can_attack_protected()`
   (Basis false, `SiegeEngine` true). Geprüft in `_scan_for_enemy`, `_begin_attack`,
   `_maybe_retaliate` (auch Brave-Wache) und `Firewarrior._melee_threat`; Zauber
   (direkter `take_damage`) und Katapult-Beschuss/-Schockwelle treffen sie weiter.
2. **Überzählige Stürmer stehen nicht mehr rum:** `_storm_building` nimmt jetzt im
   **`interact_range`** des Gebäudes auf (nicht nur am exakten Eingang → kein
   Stau an einer Türzelle, ~15 kommen zügig rein). Ist das Gebäude **voll**, gibt
   die Einheit auf (`_clear_building_target` + `_retarget_or_idle` → IDLE bzw.
   Attack-Move fortsetzen) statt mit Lauf-Animation zu warten;
   `_scan_for_enemy_building` überspringt für Nahkämpfer volle Gebäude
   (`Building.has_raider_room()`), Feuerkrieger bombardieren weiter.
3. **Gebäude-Auto-Angriff zuverlässiger:** eigener, etwas größerer Erkennungsradius
   `BUILDING_ENGAGE_RADIUS = 12 m` (statt nur Melee-Aggro 8 m) im Idle-/Attack-Move-
   Scan — weiterhin **niedrigste Priorität** (Einheiten im normalen Aggro-Radius
   zuerst). Headless verifiziert: idle Combatants und Attack-Move schleifen ein
   Feindgebäude ohne Extra-Befehl.
4. **Auswurf testbar im Spiel:** `Forester`/`Workshop` überschreiben jetzt
   `eject_occupants(killed)` (gehauste Arbeiter fliegen raus — lebend beim Sturm,
   tot bei Fernkampf-Stufe-1), gemeinsamer Helfer `Building._eject_unit`. Das
   START_MISSION-Gegnerlager (`main.gd:_setup_sparring_industry`) bekommt **2 voll
   besetzte Förstereien + 1 besetzte, pausierte Werkstatt** (`_staff_building`).

Tests: +19 in `test_building_assault.gd` (Auto-Raze idle/Attack-Move, Overflow→IDLE
bei vollem Gebäude, Schamanin-Immunität gegen Nah-/Fernkampf + Zauber-Tod, Förster-/
Werkstatt-Auswurf lebend/tot). `test_siege.gd`-Fall auf Alle-Typen-Routing
umgestellt. **1317 Tests, 0 Fehler**, `--headless --quit` und `--quit-after 400`
(Startszenario mit besetzten Gebäuden) fehlerfrei.

**Manuelle Prüfung ausstehend** (durch Nutzer): Rechtsklick auf Feindhütte
(≤15 rein, Rest IDLE), Wackeln/Stufen, Trainee-/Förster-/Werkstatt-Auswurf
(START_MISSION-Gegnerlager), Feuerkrieger-Stufe-1-Kill, Attack-Move/Idle-Auto-
Angriff auf Gebäude, Schamanin immun gegen Krieger/Feuerkrieger (nur Zauber/
Katapult), KI ohne Zauber.

**Nachbesserung 2 nach Nutzertest (2026-07-07):**
1. **Schamanin-Schutz war falsch — zurückgebaut:** `is_targetable_by_units()` /
   `_can_attack_protected()` komplett entfernt (Schamanin wieder durch **alle**
   angreifbar). Stattdessen ist jetzt der **Reinkarnationsplatz**
   (`Building.is_assailable_by_units()` Basis true, `ReincarnationSite` false)
   gegen **Einheiten**-Angriffe geschützt: Gate in `_scan_for_enemy_building`,
   `order_attack_building`, `Fireball._impact_building` und
   `SelectionManager._dispatch_enemy_building` (Rechtsklick fällt auf Move →
   Katapult beschießt ihn dann von selbst). **Zauber** (`apply_destruction_stages`)
   und **Katapult** (`SiegeShot`) treffen ihn weiter (SiegeEngine-`order_attack_building`
   ohne Gate).
2. **Nahkampf-Zerstörung schwerer + Sturm-Kampfzyklus:** Demoliert wird nur bei
   **freiem Eingang**. Neu am Gebäude: `ENTRANCE_CLEAR_RADIUS` (6 m),
   `nearest_entrance_threat()`/`has_entrance_threat()` (lebende Besitzer-Einheit
   ≤6 m am Eingang, `SIT`/Konversion zählt **nicht**), `has_occupants()` +
   `begin_storm()` (wirft Insassen **vor** dem Betreten einmalig lebend aus).
   `admit_raider` nimmt nur bei freiem Eingang + Platz auf; `_tick_raid` wirft bei
   Bedrohung **alle Demolierer wieder raus** (`_eject_raiders_to_fight` →
   `exit_building_as_raider(pos, self)` → Einheit nimmt das Gebäude wieder als
   Ziel auf und kämpft). Einheit: `_storm_building` bekämpft zuerst
   `nearest_entrance_threat` (`_engage_assault_foe`, `attack_building` bleibt →
   nach dem Kampf setzt `_retarget_or_idle` den Sturm fort), dann `begin_storm`,
   dann `admit_raider`. **Prediger** override `_engage_assault_foe` (konvertiert
   Verteidiger; immune → Nahkampf) und setzt nach der Konversion den Sturm fort
   (`_refresh_conversion` → `State.ATTACK` bei gültigem `attack_building`).
   `has_occupants()`-Overrides in TrainingBuilding/Forester/Workshop.

Tests: `test_building_assault.gd` überarbeitet (Sturm-Auswurf jetzt via
`begin_storm()`; Schamanin-Immunitäts-Tests ersetzt durch **Schamanin wieder
angreifbar** + **Reinkarnationsplatz** un-assailable/Fireball-no-op/per Zauber
zerstörbar + **Eingang-räumen/Demolierer-Auswurf**-Zyklus inkl. SIT-Ausnahme).
**1323 Tests, 0 Fehler**, `--headless --quit` und `--quit-after 400` fehlerfrei.
**Manuelle Prüfung ausstehend.**

**Bugfix (Nutzertest 2026-07-07) — Eintritt „von hinten":** Raider wurden
aufgenommen, sobald sie im `interact_range` der Gebäude**mitte** waren (also von
jeder Seite/„von hinten", ohne den Eingang zu erreichen). Fix
(`Unit._storm_building`): Eintritt nur noch **am Eingang** (`RAID_ENTER_RANGE`
2 m um `entrance_world()`); Einheiten laufen um den nav-soliden Footprint zur
Tür. Kein Stau, da aufgenommene Raider sofort aus der Welt verschwinden. **1323
Tests, 0 Fehler**, Ladecheck + `--quit-after 400` fehlerfrei.

**Manuelle Prüfung durch Nutzer bestanden (2026-07-07): Phase 7g abgeschlossen.**
Bestätigt: Sturmangriff durch den Eingang, Insassen-Auswurf + Kampf + Wieder-
Eintritt, Demolierer verlassen das Haus bei Bedrohung am Eingang, Reinkarnations-
platz durch Truppen unzerstörbar (nur Zauber/Katapult), Schamanin wieder normal
angreifbar.

---

## Phase 7h — Wachturm (abgeschlossen; manuelle Prüfung ausstehend)

**Gebaut:**
- `scripts/buildings/watchtower.gd` + `scenes/buildings/watchtower.tscn` —
  `Watchtower` (extends Building): „Wachturm", **4 Holz**, Footprint **2×2**,
  HP 200, `housing_capacity() = 0`, `max_melee_raiders() = 5` (zäher zu stürmen
  als eine Hütte mit 15). Konstanten `CREW_CAPACITY = 2`,
  `TOWER_RANGE_BONUS = 3.0`, `PLATFORM_Y = 4.0`. Hohes schlankes Placeholder-
  Mesh (Steinschaft + breite Plattform mit 4 Zinnen + Tür Süd + Fahne).
  - **Besatzung** `crew: Array` (max. 2): `admit_crew(unit)` (nur eigene
    Kampfeinheiten/Schamanin via `Unit.can_garrison()`; `remove_from_world`,
    Population bleibt gezählt), `has_crew_room()`, `crew_count()`, `_prune_crew()`,
    `eject_occupants(killed)` / `eject_crew_to(dest)` / `_eject_all()`,
    `destroy()`-Override (wirft Besatzung lebend raus). `has_occupants()` → Sturm
    (7g `begin_storm`) wirft die Besatzung lebend aus. Base `_on_disabled`
    (Stufe ≥ 1 durch Zauber/Nahkampf) wirft lebend aus; `take_damage(.., DMG_RANGED)`
    bei leeren Raidern tötet die Besatzung an der Tür (7g-Regel).
  - **Aufnahme kollisionssicher:** Anmarsch-Einheiten stehen am Eingang und
    setzen `garrison_reached`; der **Turm** nimmt sie in `_tick_active` →
    `_admit_arrived_crew()` auf (Gebäude-Tick, nicht Unit-Loop → keine Mutation
    der `units`-Liste mid-iteration; gleiche Logik wie die Trainings-Queue).
  - **Reichweitenbonus (nur Fernwirker)** in `_tick_active`: je Besatzung ein
    Scan von der Turmposition mit Basisreichweite + 3 —
    Feuerkrieger: Feuerball ab Plattformhöhe (`Firewarrior.fire_from(origin,
    target)`, `FIRE_RANGE + 3`, eigene `_fire_cd`-Map); Prediger: turmgetriebener
    Konvertierungs-Channel (`CONVERT_RANGE + 3`, `_convert_state`-Map, konvertiert
    nach Ablauf direkt via `convert_to_tribe`); **Krieger: keine Aktion**
    (geschützte Reserve); Schamanin: siehe unten.
  - **Belegungsanzeige:** `production_progress()` liefert `crew/CREW_CAPACITY`
    (Balken-Overlay = Belegung, versteckt wenn leer).
- `scripts/units/unit.gd` — neuer `State.GARRISON`; Felder `garrison_target`,
  `garrison_housed`, `garrison_reached`. `can_garrison()`
  (`_is_combatant() or shaman` — keine Braves/Siege), `order_garrison(tower)`,
  `_tick_garrison(delta)` (läuft zum Eingang, wartet auf Aufnahme),
  `enter_garrison(tower)` (housed), `leave_garrison()`. `can_take_orders()` ist
  false solange `garrison_housed` (Besatzung nimmt keine Befehle an; Move/Cast
  außerhalb Reichweite lässt sie NICHT aussteigen). `order_move`/`_begin_attack`
  brechen einen laufenden Anmarsch ab. `_anim_base`: GARRISON → walk.
- `scripts/units/shaman.gd` — `order_cast` castet bei `garrison_housed` **sofort
  vom Turm** (Ursprung = Turmmitte, `cast_range + TOWER_RANGE_BONUS`); außer
  Reichweite scheitert der Cast lautlos (Ladung bleibt), sie steigt nie aus.
- `scripts/units/firewarrior.gd` — `fire_from(origin, target)` (Feuerball von
  fester Position, für den Turmbeschuss).
- `scripts/core/tribe_commands.gd` — `order_garrison(units, tower)` (nur eigene
  garrison-fähige Einheiten; UI + KI).
- `scripts/ui/selection_manager.gd` — Rechtsklick mit garrison-fähiger Selektion
  auf eigenen Wachturm → `order_garrison`; Turm selektiert + Rechtsklick auf
  Boden → `eject_crew_to(punkt)` (Besatzung steigt aus und läuft dorthin) +
  Rally gesetzt. Helfer `_selection_has_garrison_capable()`, `_eject_tower_crew()`.
- `scripts/ui/sidebar.gd` — Baumenü-Eintrag „Wachturm (4 Holz)" (`WATCHTOWER_SCENE`).
- `scripts/ui/ui_theme.gd` — Icon `watchtower` (`_draw_watchtower`).
- `scripts/ai/ai_controller.gd` — `_next_building_scene` baut nach der Werkstatt
  **2 Wachtürme** (`TARGET_WATCHTOWERS`), `_man_watchtowers()` bemannt leere,
  nutzbare Türme mit **untätigen Feuerkriegern** (hält `WATCHTOWER_MIN_MOBILE_FW`
  = 2 mobil, damit die Armee nicht ausblutet); jede Sekunde getickt.

**Erkenntnisse/Stolpersteine:**
- **Mid-Iteration-Falle:** Die Aufnahme der Besatzung darf NICHT im Unit-Tick
  `remove_from_world` aufrufen (mutiert die `units`-Liste, über die der
  UnitManager gerade iteriert). Lösung wie die Trainings-Queue: Einheit wartet
  am Eingang (`garrison_reached`), der Turm nimmt im **Gebäude-Tick** auf.
- **Schutz gratis:** Housed = aus der Welt abgemeldet → Fernkampf-/Prediger-
  Scans (über den Spatial-Hash) finden die Besatzung nicht; nach Auswurf sofort
  wieder registriert/angreifbar. Kein Sondercode nötig, aber getestet.
- `range` ist eine GDScript-Builtin — lokale Variablen heißen `reach`.
- `_next_building_scene` verschob die KI-Baureihenfolge → `test_ai.gd`
  („endless scaling") um die 2 Wachtürme ergänzt.

**Bewusste Abweichung:** Die 2 KI-Wachtürme werden über den normalen
Plot-Finder um den Base-Anchor platziert (nicht gezielt „Richtung Feindseite" —
der Plot-Finder hat keine Richtungs-Bias; funktional ausreichend).

**Verifikation:** Testsuite grün (**1376 Tests**, davon 52 neu in
`test_watchtower.gd`: Besatzung/Kapazität/Eignung, kompletter order_garrison-
Flow, Feuerkrieger-Reichweite +3 (trifft/trifft nicht), Krieger greift nie an,
Prediger-Konvertierung +3, Schamanin-Cast +3 ohne Auszug, Besatzungsschutz,
7g-5er-Cap/Sturm-Auswurf/Fernkampf-Tod/Zauber-Auswurf, Kosten/Footprint),
`--headless --import` + `--headless --quit` fehlerfrei. **Manuelle Prüfung durch
Nutzer ausstehend** (Turm bauen + bemannen, Reichweite spürbar, Schamanin-Ring
+3, Krieger tut nichts, Sturm-Auswurf, Aussteigen per Rechtsklick, KI baut/bemannt).

### Nachbesserung (Nutzerfeedback, 2026-07-07)

**Besatzung sichtbar + Turm als Koordinator (Redesign):** Statt aus der Welt
abgemeldet zu werden, **bleibt die Besatzung registriert und sichtbar** oben auf
der Plattform (`crew_slot_position(i)`, `PLATFORM_STAND_Y = 4.75`, zwei Slots
±0,45 m). `Unit.tick()` bricht bei `garrison_housed` sofort ab — der **Turm**
treibt Position, `facing`, Animation und Beschuss (`_tick_active`). Vorteile: die
zentrale Sprite-Rendering-/Animationsmaschinerie greift automatisch, man sieht,
wer im Turm steht, und die Kampfanimation passt.
- **Schutz** jetzt über `Unit.is_targetable() = not garrison_housed` (Fern-/
  Nahkampf-Scans überspringen sie) + `begin_conversion` lehnt housed ab + der
  Turm-Prediger-Scan filtert `not is_targetable()`. `push_immune` hält sie im
  Separations-Pass fest. Nach Auswurf sofort wieder angreifbar.
- **Verhalten** (Nutzer-Festlegung): Stationierte greifen **alles in
  Fernreichweite** an (Feuerkrieger → Feuerball ab Plattformslot, Prediger →
  Konvertierung), **bewegen sich nicht** (nur `facing` dreht), **initiieren
  keinen Nahkampf**. Feuerbälle gehen daher auch auf Feinde direkt am Turmfuß.
  Krieger/Schamanin stehen nur (Krieger = geschützte Reserve, greift nie an).
  Ziehen aus dem Turm → normale Regeln.
- **Reichweitenanzeige stimmt (real):** `range_renderer.gd` (Taste G) und
  `spell_targeting.gd` (Zauber-Zielring) zeichnen für stationierte Einheiten den
  Ring **um die Turmmitte mit Basisreichweite + 3** (Feuerkrieger/Prediger bzw.
  Schamanin-`cast_range + 3`).
- **Auswahl:** garrisonierte Crew ist nicht mehr einzeln box-/klick-/
  doppelklick-selektierbar (gehört dem Turm).
- **Manuelles Testszenario** (`main.gd` `_setup_sparring_towers`, START_MISSION):
  der rote Gegner hat **3 bemannte Wachtürme** — Turm 1: 2 Prediger, Turm 2:
  2 Feuerkrieger, Turm 3: 1 Feuerkrieger + 1 Krieger.

**Besatzung über das Sidemenü (Nutzerfeedback):** Der Wachturm nutzt jetzt
dasselbe Bedienmuster wie Förster/Werkstatt — ein **Wachturm-Besatzungspanel**
in der Sidebar (`sidebar.gd` `_build/_refresh_watchtower_panel`, sichtbar solange
ein Wachturm selektiert ist) mit einem Knopf je Platz (zeigt die Einheitenart,
Klick = rauswerfen → `Watchtower.eject_crew(index)`, lebend an den Rand, läuft
zum Rally-Punkt falls gesetzt). Der **In-World-Füllstandsbalken** über dem Turm
ist entfernt (`production_progress`-Override raus → Basis liefert -1).
**Rechtsklick auf den Boden setzt nur den Auslieferungs-/Rally-Punkt** (wie bei
allen Gebäuden) und wirft die Besatzung NICHT mehr automatisch raus (der frühere
`eject_crew_to`/`_eject_tower_crew`-Pfad ist entfernt).

**Bugfixes (Nutzerfeedback):**
- **Baumenü-Eintrag unklickbar:** Mit 7 Einträgen lief die Bauliste aus dem
  festen Tab-Bereich (200 px) heraus, der Wachturm-Button war nicht erreichbar.
  Fix: `content`-Höhe auf 300 und Bau-Tab in einen `ScrollContainer`
  (`sidebar.gd`) — die komplette Liste bleibt immer erreichbar.
- **Turm im 3D nicht anklickbar:** Der Klick-/Auswahlkörper der `Building`-Basis
  war fix 2,5 m hoch → Klicks auf den hohen Turmschaft/Plattform trafen nichts.
  Neu: Hook `Building._click_body_height()` (Standard 2,5), `Watchtower`
  überschreibt auf 5,5 m.

**Verifikation nach Nachbesserung:** **1383 Tests grün** (59 in
`test_watchtower.gd`; neu: sichtbar auf der Plattform, Beschuss am Turmfuß ohne
Bewegung, Nicht-Konvertierbarkeit, Schutz via `is_targetable`),
`--headless --import`/`--quit` fehlerfrei (Ladecheck baut in START_MISSION die
Sidebar + das 3-Turm-Testszenario). Manuelle Prüfung weiter ausstehend.


## Phase 7i — Balancing, Karten & Wirtschaft (Zwischenphase, umgesetzt)

Plan: [07i_balancing_maps_economy.md](07i_balancing_maps_economy.md). Bündel aus
Balancing- und zwei Feature-Blöcken (Kartenauswahl, bemannbare Hütten).

**Variable Terraingröße (Refactor).** `TerrainData.SIZE/VERTS` sind weiterhin
Consts (Default 128/129), aber die tatsächliche Größe liegt jetzt pro Instanz in
`size`/`verts` (`_init(p_size := SIZE)`). Alle internen Methoden nutzen die
Instanzfelder; externe Aufrufer lesen die Instanz statt der Const:
`nav_grid` (`terrain.size`), `terrain.gd` (`data.size/verts`, `_chunk_count` in
`build()`), `camera_rig` (Pan-Clamp aus `GameState.terrain_data.size`),
`minimap` (`_terrain_data.size` + neues `round_mask`), `tree_manager`,
`main.gd` (Zentrum/Ring-Suchen), Zauber `earthquake/flatten/sink` (statische
`*_targets(td,…)` → `td.verts/td.size`), `swarm_cloud/tornado_debris`
(`terrain_data.size`). Standardkarte bleibt 128; die großen Karten sind 256.

**Kartensystem + 3 neue Karten.** Neu `scripts/core/map_generator.gd`
(`MapGenerator`): Registry (`map_ids`, `display_name`, `map_size`, `round_mask`,
`max_players`), `create_terrain(map_id, seed)` und `spawn_anchors(td, map_id, n)`.
Karten teilen Anker- und Generierungszellen (Ecken/Hälften):
- **island** (128, rund): unverändert, Anker auf Kreis.
- **seenland** (256, eckig): überwiegend Land, mittiger See (unter Meeresspiegel),
  angehobene Ecken, 4 Startecken (diagonal für 2 Spieler).
- **bergpass** (256, eckig): flach, kein Wasser, mittiger Gebirgsriegel (Höhe
  +26) mit **3 Pässen** (x=¼,½,¾) und steilen Flanken (Klippen), 2 Spieler je
  Hälfte, Basen relativ nah.
- **plateau** (128, eckig): flache Ebene, je Spieler ein stark angehobenes
  Plateau (+12) mit harten Kanten und **einer begehbaren Rampe** Richtung
  Kartenmitte (`raise_line`).
Integration: `main.gd::_ready` baut das Terrain über `MapGenerator` (Skirmish =
gewählte Karte, sonst Insel), setzt `GameState.map_id`, skaliert die Baumzahl mit
der Fläche und nutzt `spawn_anchors` statt des alten Kreis-Ankers
(`_skirmish_anchor` entfernt). `MatchConfig.map_id` wird gegen die Registry
validiert. `main_menu.gd`: Kartenauswahl aus `MapGenerator.map_ids()` +
Beschreibungslabel; Headless-Hook `-- skirmish=N [map=<id>]`. Minimap wird für
eckige Karten quadratisch (Maske/Umrandung, kein Beschnitt der Eck-Basen) via
`Sidebar.setup → Minimap.setup(..., round_mask)`.

**Prediger-Verteilung + Bekehrte als Nicht-Ziel.** `preacher.gd`: `_engage_on_sight`
und `_refresh_conversion` bevorzugen bei der Fokuswahl ein Ziel, das **kein anderer
eigener Prediger** bereits bearbeitet (`_claimed_by_peer` prüft `converting_preacher`
bzw. fremdes `_convert_target`; `_pick_convert_focus` liefert nächstes unbelegtes,
sonst nächstes Ziel) → mehrere Prediger fächern auf, auch bei Attack-Move.
Sitzende (SIT) werden vom Nah-/Fernkampf ohnehin übersprungen (bestehend). **Katapult-
Ausnahme:** der Siege-Scan (`siege_engine.gd::_nearest_enemy_unit`) überspringt SIT
nicht mehr → Katapult beschießt Konvertierende weiter.

**Balancing-Werte.** Hardcap **1500 Einheiten/Stamm** (`Tribe.MAX_UNITS`,
`Tribe.at_unit_cap()`; `UnitManager.spawn_unit` gibt am Cap `null` zurück —
Training entfernt den Trainee vor dem Spawn, daher kein Verlust). Hütte **12 Holz /
40 Platz** (vorher 15/100). Feuertempel **20 Holz, 8×8**, neues **vieleckiges
(oktagonales)** Placeholder-Modell, HP 600. Tempel **15 Holz, 6×6**, HP 440.
Zauberkosten der hohen Zauber erhöht: Erdbeben 80→110, Vulkan 120→180,
Feuerregen 70→100, Tornado 90→110, Ebene 70→90. Mana-Zuwachs als Zahl:
`Tribe.mana_rate()` + Sidebar-Label „Mana: N (+X.X/s)".

**Bemannbare Hütten + Wachstumsregler.** `hut.gd`: `crew: Array` (max 4,
`CREW_CAPACITY`), `admit_crew`/`eject_crew`/`eject_occupants`, `has_crew_room`,
`crew_count`. Crew = Braves, per `Unit.enter_hut` versteckt (über
`UnitManager.remove_from_world`, Population bleibt gezählt, kein Mana) — reutzt die
Garrison-Maschinerie (`Unit.order_man_hut` mirror von `order_garrison`, aber
Brave-only; `leave_garrison` beim Auswurf). **Leere Hütte produziert nichts**;
Produktionsrate skaliert mit Crew (`_spawn_rate_factor` 0..`FULL_CREW_BONUS 1.1`;
volle Hütte ≈ 9,1 s statt 10 s). Wachstumsregler pro Stamm
(`Tribe.GrowthMode {NONE,MINIMAL,MAXIMUM}`, Default MAXIMUM): `hut._tick_growth`
(alle `GROWTH_INTERVAL`=1 s) hält die Crew auf `_crew_target()` (0/1/4) — wirft
Überzählige aus (NONE leert alle Hütten) bzw. zieht **nahe idle Braves**
(`MAN_RADIUS`=16, `_find_idle_brave_near`, nur IDLE ohne andere Aufgabe) über
`order_man_hut` herein; nur nahe Braves → Hütten können auch bei MAXIMUM leer
bleiben. Auto-Bemannung gilt symmetrisch für die KI (kein KI-Sondercode).
Manuell: Braves selektiert + Rechtsklick auf eigene Hütte →
`TribeCommands.order_man_hut` (Nicht-Braves laufen nur hin);
`selection_manager` (`_building_is_actionable`/`_apply_building_command` +
`_selection_has_brave`-Guard). Sidebar: Wachstums-Regler (`HSlider` 0/1/2) +
Label „<Modus> (+N/min)" (`Hut.growth_per_minute`, Summe über eigene Hütten).

**Bugfix — Bauplatz freiräumen.** `Building._clear_footprint` (in
`_tick_construction`, ab `wood_delivered >= 1`, gedrosselt `CLEAR_INTERVAL`=0,5 s):
Einheiten mit Position im Footprint (die Order annehmen können — DEAD/THROWN/ROLL/
SIT/Crew ausgenommen) bekommen `order_move` auf die nächste begehbare Zelle
außerhalb → keiner steckt mehr unsichtbar im aufsteigenden Gebäude.

**Tests/Verifikation.** **1481 Tests grün**, `--headless --quit` fehlerfrei,
Skirmish-Läufe auf island/seenland/bergpass/plateau headless fehlerfrei
(inkl. 2500-Frame-KI-Läufe island + bergpass 256). Neu:
`tests/test_maps.gd` (variable Größe, Anker begehbar+erreichbar, See/Pässe/
Plateau-Features), `tests/test_hut_crew.gd` (Crew-Limit/Eignung, leere Hütte
ohne Produktion, Ratenskalierung, Auswurf, Wachstumsmodi NONE/MAXIMUM,
Nähe-Regel, Hardcap), `tests/test_conversion_targeting.gd` (Fußtruppe ignoriert
SIT, Katapult zielt auf SIT, Prediger-Verteilung). Bestehende Hütten-/Produktions-
Tests auf Crew umgestellt (test_economy/test_training/test_building_destruction).
Manuelle Prüfung ausstehend.

**Erkenntnisse/Stolpersteine.**
- `UnitManager.tick()` bewegt Einheiten NICHT — Bewegung liegt in `unit.tick()`
  (im Spiel über `_physics_process`). Ein Sim-Schritt in Tests = jede Unit ticken
  **und** `um.tick()` (Hash-Refresh, damit `get_units_in_radius`/Crew-Admit die
  neuen Positionen sehen) **und** das Gebäude.
- Der Gebirgsriegel (bergpass) ist oben flach (begehbares, aber isoliertes
  Plateau) — nur die Flanken sind Klippen; die Blockade wirkt über die
  unpassierbaren Flanken (nur die 3 Pässe verbinden die Hälften).
- Bekannter, vorbestehender Flaky-Test `test_spells: orders work again after the
  panic` (randf-Panikdauer) — unabhängig von 7i.

**Nachbesserungen 7i (Nutzerfeedback).**
- **Vulkan repariert:** `volcano.gd::cone_targets` nutzte noch `TerrainData.VERTS/SIZE`
  (Klassen-Const) statt `td.verts/td.size` → auf 256er-Karten falscher Heightmap-Stride,
  daher kein Berg (nur Lava) und am Reichweitenrand scheiterte `execute` (leere Indizes).
  Jetzt instanzbasiert. (Der übersehene Rest des Schritt-0-Sweeps.)
- **Cast-in-Reichweite-laufen:** war bereits korrekt implementiert/getestet
  (`Shaman._tick_cast` läuft hin, castet, Move-Order bricht ab —
  `test_shaman_walks_into_range_then_casts`); der Eindruck „castet nicht" kam vom
  Vulkan-Bug. Keine Änderung nötig.
- **Panik durch Klippen:** Panik-Flucht nutzt einen Direkt-Wegpunkt (kein A*); die
  Gerade zum begehbaren Zielfeld konnte Klippenzellen kreuzen → Einheiten klippten
  hoch. Neu `Unit._walkable_reach(dir, max_dist)`: `_pick_panic_target` beschneidet
  die Flucht auf das durchgehend begehbare Segment (Stopp vor der ersten
  unbegehbaren Zelle).
- **Dächer** von Tempel (Kegel-Radius span·0,5 → 0,42) und Feuertempel (0,55 → 0,46)
  verkleinert — überlappen noch, aber ohne extremen Überhang.
- **Tests:** 1487 grün; neu `test_volcano_cone_on_large_map` (Index-Stride auf 256)
  und `test_panic_hop_stops_before_cliff`.

**Nachbesserungen 7i (2. Runde, Nutzerfeedback).**
- **Crash behoben:** `Sidebar._selected_siege` (und die anderen Auswahl-Helfer)
  prüften `x is Type` VOR `is_instance_valid(x)` — bei einer inzwischen
  freigegebenen Selektion (Einheit/Gebäude zerstört) wirft der `is`-Operator
  „Left operand of 'is' is a previously freed instance". Reihenfolge überall auf
  **`is_instance_valid(x) and x is Type`** gedreht (sidebar.gd, building.gd,
  ai_controller.gd).
- **Lag bei Insektenzauber an Klippen behoben:** Der 7i-Panik-Fix beschnitt das
  Fluchtziel auf begehbares Terrain; an einer Klippe blockierte Einheiten bekamen
  dadurch einen Pfad, der im selben Frame „ankam" → `not _has_path()` triggerte in
  `_tick_panic` **jeden Frame** ein neues `_pick_panic_target` inkl. frischer
  `PackedVector3Array` — bei vielen Panik-Einheiten eine Allokations-Lawine. Fix:
  Neu-Picken nur noch über den Redirect-Timer (~0,8 s), nicht mehr bei leerem Pfad.
  Perf-Sanity: 200 Panik-Einheiten an einer Klippe ≈ 2,5 ms/Frame (headless, nur
  Logik).

---

## Phase 8 — Performance (umgesetzt; manuelle Prüfung ausstehend)

Plan: [08_performance.md](08_performance.md). Reine Performance-Phase,
messgestützt (headless-Benchmarks + Pfad-Telemetrie); Balance/Komfort bewusst
in Phase 9.

**Messwerkzeuge (neu):**
- `scripts/core/game_settings.gd` — `GameSettings` (statisch): persistente
  Nutzereinstellungen via ConfigFile (`user://settings.cfg`); aktuell
  `show_fps` (Default aus).
- `scripts/ui/fps_overlay.gd` — `FpsOverlay` (Label, oben rechts): FPS +
  Frame-Zeit in ms, 4x/s aktualisiert; folgt `GameSettings.show_fps()` live.
  In `main.gd` in den UI-Layer gehängt; Optionen-Seite im Hauptmenü hat den
  CheckButton „FPS-Anzeige" (persistiert).
- **Lag-Szenario per Flag:** `godot --path . -- lagtest` startet direkt
  Skirmish Bergpass mit 3 KIs (main_menu.gd; F10-Zeitraffer rafft den Aufbau).
- `tests/benchmark_earlygame.gd` — Headless-Nachbau des Lag-Szenarios
  (Bergpass, 4 KI-Stämme, 150 s Sim): Kosten pro Subsystem in 30-s-Fenstern,
  Top-Kostenstellen pro Einheiten-State, Pfad-Telemetrie.
- `tests/benchmark_mass.gd` — Bewegung + Kampf bei 2000/6000 Einheiten mit
  Phasen-Split (units/hash/paths/sep/regroup).
- `Unit.dbg_plan_calls/-fails/-us` (statisch) — Pfadplanungs-Telemetrie, von
  Benchmarks und `test_perf.gd` gelesen.

**Früh-Lag: Befund (gemessen) und Fix.** Das Benchmark reproduzierte den Lag
exakt: Ø-Frame-Kosten der Unit-Ticks stiegen bei nur ~220 Einheiten auf
**~100 ms/Frame** (Budget 33 ms), Treiber war `brave/BUILD/CHOP`. Ursache:
**fehlschlagende A*-Läufe** — auf Bergpass stehen Bäume auf begehbaren, aber
**isolierten** Bergkuppen; Bauarbeiter wählten so einen Baum, der Pfad schlug
fehl (Voll-Exploration der halben 256er-Karte, ~6,5 ms je Fehlschlag),
`_end_subtask` setzte den Retry-Timer auf 0 → derselbe Baum wurde **alle 2
Frames** neu gewählt. Gemessen: 8327 Pfad-Fehlschläge in 30 s (54 s
CPU-Zeit im Fenster). Fixes:
- `Building.mark_wood_unreachable()`/`is_wood_unreachable()` — Baustelle merkt
  sich unerreichbare Bäume/Stapel (TTL 30 s, geteilt von allen Arbeitern der
  Baustelle; nach Ablauf Re-Check, falls z. B. eine Landbrücke den Weg öffnet).
  `Brave._on_seek_failed` markiert; `_nearest_claimable_tree`/
  `_nearest_eligible_pile` filtern.
- Retry-Backoff: `TASK_RETRY_IDLE` (1,5 s + Jitter) wenn die Task-Wahl leer
  ausgeht oder ein Seek scheitert (vorher 0,6 s bzw. sofort).
- Pfad-Queue zusätzlich **zeitbudgetiert** (`PATH_BUDGET_USEC` 4 ms neben dem
  48er-Cap) — teure/fehlschlagende Pfade auf großen Karten können den Tick
  nicht mehr sprengen (test_unit_logic-Queue-Test auf „höchstens N pro Tick,
  Rest später" angepasst).
- Fetch-Sicherheitsscan entschärft: Gegner-Check nur noch für den **besten**
  Kandidaten statt pro Stapel/Baum (`_best_safe_pile`/`_claim_safe_tree`
  zweiphasig); `UnitManager.has_enemy_in_radius()` als allokationsfreier
  Existenz-Check.

**Ergebnis Früh-Lag (Benchmark vorher → nachher):** Ø-Unit-Tick-Kosten
t=90s: 22→0,9 ms; t=120s: 49→1,2 ms; t=150s: 99→**1,8 ms**; schlimmster
Frame 583→55 ms; Pfad-Fehlschläge 8327→185 pro 30-s-Fenster.

**Wirtschaft/Gebäude-Ticks entlastet (Per-Frame-Kosten weg):**
- `Hut`: Aufnahme-Radius-Query + Bevölkerungs-/Cap-Check nur noch alle 0,25 s
  (gestaffelt, `MAINTAIN_INTERVAL`, Cache `_cap_blocked`); `_tick_growth`
  bündelt Incoming-Zählung + Idle-Brave-Suche in **eine** Radius-Query
  (vorher bis zu 6 Queries/s je Hütte).
- `Watchtower`: Prune/Aufnahme alle 0,25 s; Besatzungs-Scans (Feuer/
  Konvertierung) über 0,15-s-Akkumulator statt pro Frame (Cooldowns laufen
  über das akkumulierte Delta → gleiche Kadenz).
- `TrainingBuilding`: `_prune_queue` ohne Allokation im Normalfall;
  `_assign_slots` (Perimeter-Geometrie + Nav-Snap je Brave) nur alle 0,25 s
  bzw. sofort bei Queue-Längen-Änderung.
- `Workshop`: Vorrats-/Start-Checks (Stapelsummen, Katapult-Zählung) alle
  0,3 s statt pro Frame.
- `Forester`: 2-s-Backoff nach fehlgeschlagenem Pflanz-Dispatch (volle
  Fläche/keine freie Zelle wurde vorher pro Frame neu gescannt).
- `BuildingManager._recruit_workers`: iteriert die Einheiten des BESITZER-
  Stamms mit Distanzcheck statt einer ungecappten 30-m-Radius-Query je
  Baustelle.
- `AIController`: Plot-Ringsuche hart gedeckelt (`MAX_PLOT_CELLS` 1200) +
  5-Ticks-Cooldown nach erfolgloser Suche (vorher bis ~3700 `can_place_at`
  pro KI-Tick).
- `GameState`: Tribe-Ticks (Mana; `praying_braves()` läuft über alle
  Einheiten) auf 10 Hz statt pro Render-Frame (Einkommen identisch:
  Rate × Delta).

**Bewegung & Kampf skaliert:**
- Bewegungs-Hotpath: Steigung aus dem letzten Schritt (`_ground_slope`, 1 Tick
  Verzögerung) statt 2 zusätzlicher Terrain-Samples pro Tick — Laufen braucht
  nur noch das eine `get_height` des Y-Snaps (auch in `_step_toward`);
  `_slope_ahead` entfernt.
- `UnitManager.nearest_enemy()` — allokationsfreier Gegner-Scan (ersetzt
  `get_units_in_radius`-Arrays in `Unit._scan_for_enemy`); Kandidaten-Cap
  zählt wie vorher JEDE Einheit im Radius (sonst degeneriert der Scan in
  Freundes-Massen zum Voll-Bucket-Lauf — gemessen: Regroup-Pass 34→1 ms bei
  6000).
- `_prune_melee_attackers` alloziert nur noch bei tatsächlich ungültigen
  Einträgen (lief pro Angreifer pro Tick).
- Separation-Budget 600→450 Einheiten/Tick (Slices skalieren den Push wie
  gehabt).
- `UnitRenderer.MAX_UNITS` 4096→**8192** (4×1500-Hardcap + Leichen).
- **F9-Stresstest:** 2000 Einheiten pro Druck (auf die vorhandenen Stämme
  verteilt), Spawn-Anker skalieren mit der Kartengröße; 6000 erreichbar im
  4-Spieler-Skirmish (3× F9; Hardcap 1500/Stamm bleibt).

**Messwerte Masse (headless, Ø/Tick, Budget ~33 ms):** Bewegung 2000:
38→**29,5 ms**; Kampf 2000 (alle kämpfen): 50→**28 ms** → Mindestziel 2000
erreicht. Richtung 6000 (Kennzahl, kein hartes Ziel): Bewegung 6000
~46 ms, Kampf ~4700 ~76 ms — Sim läuft dann unter 30 Hz (Zeitlupe), bleibt
aber bedienbar. Headless misst nur die Logik; maßgeblich im Spiel ist die
neue FPS-Anzeige.

**Rendering:** bewusst NICHT angefasst (Plan: „nur bei Bedarf, wenn GPU
limitiert" — headless nicht messbar). Falls die FPS-Anzeige im Spiel GPU-
Limits zeigt, sind MultiMesh-Bäume (statt ~2-4 MeshInstance3D je Baum) und
Culling der Overlays die nächsten Hebel.

**Tests:** `tests/test_perf.gd` (neu, 4 Wächter): Massen-Bewegung 2000 und
Massen-Kampf 2000 unter großzügigem O(n²)-Budget, Unreachable-Holz-Regression
(deterministische Insel: begrenzte Pfad-Fehlschläge, Baustelle stallt,
Arbeiter idlet), Früh-Wirtschafts-Budget (Bergpass, 4 KI-Stämme, 30 s Sim,
Ø-Frame-Budget). **1499 Tests grün, 0 Fehler**; `--headless --quit` und
`--headless --quit-after 600 -- lagtest` fehlerfrei.

**Erkenntnisse/Stolpersteine:**
- Ein fehlschlagender A* auf einer 256er-Karte exploriert die GANZE
  erreichbare Komponente (~6,5 ms) — fehlgeschlagene Ziele dürfen nie im
  Frame-Takt neu versucht werden. Konnektivitäts-Labels (O(1)-Fail) wurden
  erwogen und verworfen: Rebuild nach jeder Terrain-Verformung (Planier-Flush
  alle 0,25 s je Baustelle) wäre teurer als die Krankheit.
- Kandidaten-Caps müssen ALLE untersuchten Einheiten zählen, nicht nur
  Treffer — sonst degeneriert der Scan in dichten Freundes-Massen.
- Headless-Zeitmessungen auf dieser Maschine streuen stark (±30 %, einzelne
  Ausreißer-Frames durch OS-Jitter); Suite-Budgets deshalb als Größenordnungs-
  Wächter (3-4× Messwert) ausgelegt.

**Manuelle Prüfung ausstehend (durch Nutzer):** FPS-Anzeige über Optionen
ein-/ausschalten; Lag-Szenario (`-- lagtest` oder Skirmish Bergpass + 3 KIs)
im Spiel flüssig; F9-Stresstest 2000/4000/6000 im 4-Spieler-Skirmish (FPS
beobachten — falls GPU limitiert: Rendering-Hebel oben); Wachturm-Beschuss,
Hütten-Bemannung und Trainings-Queues verhalten sich unverändert.

### Nachbesserung Phase 8 — Schatten-Umbau + Aufhellung (Nutzerfeedback, 2026-07-07)

**Anlass:** F9 (2000 Einheiten) im Skirmish drückte die FPS auf ~10, ohne
Bewegung — Simulation headless bei ~1-2 ms, also render-seitig. Analyse: Der
Unit-Shader hat zwar `shadows_disabled`, das deaktiviert aber nur das
**Empfangen** — `cast_shadow` des MultiMeshInstance3D stand auf Default ON,
d. h. bis zu 8192 zur Schattenkamera gebillboardete Alpha-discard-Quads
liefen durch **alle 4 Schatten-Kaskaden** (Default-Setup: 4 Splits, 4096er
Map, 100 m Distanz — nirgends konfiguriert).

**Umgesetzt („nur grobe Formen werfen Schatten"):**
- `unit_renderer.gd`: `cast_shadow = OFF` für das Einheiten-MultiMesh;
  stattdessen **hartkodierte Kreis-Blob-Schatten** über ein zweites,
  slot-synchrones MultiMesh (flacher PlaneMesh-Quad 0,7 m, prozedurale
  radiale Alpha-Textur, unshaded/alpha, +0,04 m über Boden; Transforms
  laufen im vorhandenen Positions-Cache-Loop mit, Leichen blenden ihren
  Blob per Null-Skalierung aus — Flag `Unit._blob_hidden`). Statische Helfer
  `UnitRenderer.blob_texture()`/`make_blob_mesh(size)`.
- `siege_engine.gd`: alle Modell-Meshes `cast_shadow = OFF` + eigener
  Blob-Quad (1,6×2,4 m) unterm Chassis; Flammen-Overlay ebenfalls OFF.
- `cast_shadow = OFF` für sämtliche Hilfs-/UI-Geometrie: Selection-Ring-
  MultiMesh (bis 1024 Tori!), Gebäude-Auswahlring/Rally-Marker/Flaggen/
  Damage-Holes, Wasser-Plane, Routen-Linien+Marker, Reichweiten-Ringe,
  Zauber-Cursor/-Ringe, Bau-Ghost. **Schatten behalten:** Terrain-Chunks,
  Bäume, Gebäudekörper (die groben Formen).
- Schattenqualität vergröbert: Sun auf **2 PSSM-Splits** (statt 4),
  `directional_shadow_max_distance = 70`, project.godot:
  `directional_shadow/size = 2048` (statt 4096), Soft-Filter „low",
  Positional-Atlas 512 (keine Punktlichter vorhanden).
- **Aufgehellt:** `ambient_light_energy` 0,5 → 0,75 und `Sun.shadow_opacity
  = 0.8` (Schatten durchscheinend statt schwarz) — Startwerte zum
  Nachjustieren.
- **FPS-Overlay erweitert:** zweite Zeile mit Draw-Calls + Objekten pro Frame
  (`RenderingServer.get_rendering_info`) — damit ist der Vorher/Nachher-
  Effekt und ein etwaiges verbleibendes GPU-Limit direkt ablesbar.

**Erwartete Ersparnis (GPU/Renderthread):** Schattenpass verliert die
Einheiten-Quads (skalierte exakt mit F9), ~1000+ potenzielle Ring-Instanzen
und den Kleinkram; halbe Kaskadenzahl × halbe Map-Auflösung × kürzere
Distanz. Beleg läuft über die Draw-Call-Anzeige im Nutzertest — headless ist
GPU-seitig nichts messbar.

**Nächster Hebel, falls weiter GPU-limitiert:** MultiMesh für Bäume
(2 MeshInstances je Baum, 120-480 Stück) und Gebäude-Mesh-Bündelung.

**Verifikation:** Testsuite grün (1499), `--headless --quit` und
`--headless --quit-after 600 -- lagtest` fehlerfrei (keine Property-
Warnungen — `shadow_opacity` existiert in 4.7). **Manuelle Prüfung durch
Nutzer ausstehend:** F9-Test mit FPS-/Draw-Call-Anzeige, Blob-Optik,
Helligkeit (Ambient/Opacity nach Geschmack nachjustieren).

### Nachbesserung Phase 8 — Kampf-Einbruch auf 2-3 FPS (Nutzerfeedback, 2026-07-07)

**Anlass:** Nach dem Schatten-Umbau besser, aber sobald echter Kampf + Bewegung
lief (Debugschlacht, ~2200 Einheiten), brach die FPS von ~30 auf 2-3 ein —
bei nur 600 Draw-Calls/210 Objekten, also klar CPU-seitig.

**Diagnose (gemessen):**
- **Physik-Aufholspirale** als Haupttäter des Klippeneffekts: Der Kampf-Tick
  lag bei Vollkampf am/über dem 33-ms-Budget (30 Hz). Godots Default
  `max_physics_steps_per_frame = 8` stapelt dann bis zu 8 Sim-Schritte pro
  Render-Frame → ~280-ms-Frames → 2-3 FPS, dauerhaft (die Sim kommt nie
  wieder vor die Uhr). Erklärt exakt „erste 5 s gut, dann Absturz".
- Sektions-Split des Attack-Ticks (temporäre Instrumentierung, 2000 Krieger,
  1859 im ATTACK-State): Verfolgung/`_approach` 13,1 ms, Kopf (Zielvalidierung
  + `request_melee_slot` pro Tick) 6,5 ms, Warten 0,7, Zuschlagen 0,8; dazu
  Basis-Tick-Overhead (Knockback/Regen/Brennen/Anim-Calls pro Einheit).
- **Sounds geprüft (Nutzerfrage): unkritisch.** `combat_audio.gd` ist gepoolt
  (12 Player) + global gedrosselt (min. 45 ms Abstand ≈ max. 22 Sounds/s);
  pro Treffer läuft nur ein µs-Handler. Bei ~1250 Treffern/s ≈ 1-2 ms/s.

**Fixes:**
- `project.godot`: **`max_physics_steps_per_frame = 2`** (statt 8) — Überlast
  wird zu leichter Zeitlupe bei spielbarer FPS statt zur 2-FPS-Spirale.
  `main.gd` setzt beim Matchstart auf 2 zurück; F10-Zeitraffer hebt weiter an
  (10x/100x brauchen viele Schritte/Frame), 1x geht zurück auf 2.
- Kampf-Hotpath (`unit.gd`):
  - `request_melee_slot`: Fast path zuerst (Slot-Halter überspringen den
    Prune-Scan; Prune nur noch bei Neuzugang).
  - `_approach`: quadrierte Distanzen statt `_flat_dist`-Aufrufe, Replan-
    Schwelle 1,0 → 1,5 m (Brawl-Ziele zittern durch Schubser/Separation —
    weniger A*-Läufe: 29,5k → 24,5k pro 300 Ticks).
  - Verfolger-Branch: redundantes `_face_point` entfernt (Facing kommt aus der
    Bewegung selbst).
  - `tick()`: Knockback-/Brennen-Aufrufe nur noch bei aktivem Effekt (2
    gesparte Calls pro Einheit pro Tick).
  - `_advance_path`/`_step_toward`: Steigungs-Speed + Boden-Snap inline (je
    ein Call pro bewegter Einheit pro Tick gespart).
- `stars_renderer.gd`: eine Uhr-Ablesung pro Frame statt pro Einheit
  (`has_stars()` inline).

**Messwerte (headless, Ø/Tick):** Bewegung 2000: 29,5 → **17,9 ms**; Kampf
2000: 28 → **22,7 ms** (Luft unterm 33-ms-Budget); Kampf ~4700: 76 → 52 ms;
Bewegung 6000: ~47 ms. Im Spiel fängt zusätzlich der 2er-Step-Cap jede
Restüberlast ab.

**Verifikation:** Suite grün, Ladecheck fehlerfrei (Stand nach Lauf s. u.).
**Manuelle Prüfung ausstehend:** Debugschlacht + Skirmish-F9 — FPS sollte im
Vollkampf nicht mehr unter ~15-20 fallen; bei Überlast läuft das Spiel
minimal langsamer statt einzufrieren.

### Rückabwicklung Phase 8 — Wegfindungs-Regression (Nutzerentscheid, 2026-07-12)

**Symptome (Langzeittest durch Nutzer):** Nach einer Weile Spielzeit ignorieren
Einheiten Befehle — Zielmarker werden angezeigt, Einheiten bewegen sich nicht
(beobachtet nahe Erdbeben-verformtem Terrain); KI-Einheiten verlassen die Basis
nicht mehr, zeigen aber **Laufanimation**.

**Täter-Hypothese (Startpunkt für den Neuanlauf in Phase 8.1):**
„Laufanimation ohne Bewegung" ist exakt der Zustand MOVE-State-wartet-auf-
Pfad-Queue (`_pending_target` gesetzt, `_tick_move` returned, `_anim_base()` =
walk). Das Phase-8-**Zeitbudget der Pfad-Queue** (`PATH_BUDGET_USEC = 4000`)
drückt den Queue-Durchsatz auf großen Karten mit teuren/fehlschlagenden
A*-Läufen (z. B. nach Erdbeben-Verformung) auf wenige Pfade pro Tick; die
GLOBALE Queue (alle Stämme teilen sie) staut sich dann unbegrenzt auf — alle
neuen Bewegungsbefehle warten Minuten. Passt auf beide Symptome (KI-Basen ohne
Terrain-Verformung sind über die geteilte Queue mitbetroffen). Zweiter
Kandidat: der Unreachable-Holz-Cache (30-s-Bann nach EINEM Pfad-Fehlschlag —
auch transiente Blockaden, z. B. Baustellen-Footprints, lösten ihn aus).

**Zurückgerollt auf den Stand vor Phase 8 (`16bc4be`):** alle Sim-/Wegfindungs-/
KI-Verhaltensänderungen aus `302ebad` („Phase 8: Performance") und `98de11f`
(Kampf-Hotpath): Pfad-Queue-Zeitbudget, Unreachable-Holz-Cache + Filter,
Worker-Retry-Backoffs, zweiphasige Safety-Scans, Hütten-/Wachturm-/Trainings-/
Werkstatt-/Förster-Drosselungen, Recruit-über-Stammesliste, KI-Plot-Cooldown/
Zell-Cap, 10-Hz-Tribe-Tick, `_ground_slope`-Bewegung (zurück zu `_slope_ahead`),
`_approach`-/`_tick_attack`-Umbauten, Melee-Slot-Fastpath, Tick-Guards,
allokationsfreie Scans (`nearest_enemy`/`has_enemy_in_radius`).
Komplett zurückgesetzte Dateien: brave.gd, hut.gd, watchtower.gd,
training_building.gd, workshop.gd, forester.gd, building_manager.gd,
ai_controller.gd, game_state.gd, unit_manager.gd; unit.gd zurückgesetzt und
building.gd bereinigt.

**Bewusst behalten:**
- Schatten-Umbau komplett (`7d7f6af`): Blob-Schatten, cast_shadow-OFF-Liste,
  2 PSSM-Splits/2048er-Map/70 m, Ambient 0,75 + shadow_opacity 0,8.
- Messwerkzeuge: FPS-/Draw-Call-Anzeige (GameSettings/FpsOverlay), lagtest-Flag,
  F9-Ausbau (2000/Druck, kartengrößen-Anker), Benchmarks
  (benchmark_earlygame/-mass/-units), Pfad-Telemetrie `Unit.dbg_plan_*`
  (in unit.gd re-eingepatcht), `_blob_hidden`-Feld (vom Blob-Renderer genutzt),
  StarsRenderer-Uhr-Optimierung, Renderer-Kapazität 8192.
- **Aufholspiralen-Cap `max_physics_steps_per_frame = 2`** (project.godot +
  main.gd) — verhindert weiterhin das 2-3-FPS-Standbild; Überlast wird Zeitlupe.

**Bekannte Kehrseite:** Früh-Lag (Bergpass) und Kampf-Tick-Kosten von vor
Phase 8 sind zurück (headless nach Rollback gemessen: Bewegung 2000 ≈ 31,5 ms,
Kampf 2000 ≈ 45,9 ms/Tick; Bewegung 6000 ≈ 79 ms, Kampf ~4700 ≈ 108 ms).

**Tests:** `test_perf.gd` um `test_unreachable_wood_is_cached` und
`test_early_economy_budget` gekürzt (wachten über zurückgerollte Fixes); die
zwei Massen-Budget-Wächter (move/combat 2000, Budgets 100/120 ms) bleiben.
Pfad-Queue-Test in test_unit_logic bleibt (kompatible „höchstens N pro
Tick"-Assertion).

**Nutzer-Vorgabe für alle künftigen Performance-Arbeiten:** KEINE Reduktion
der Simulationsfrequenz / keine Genauigkeits-Tricks („akkurate Berechnung") —
der 20-Hz-Plan (08a) ist verworfen. Performance-Neuanlauf (Phase 8.1 im
Overview): Optimierungen einzeln, mit Langzeit-Verifikation, wieder einführen.

**Nutzertest nach der Rückabwicklung (2026-07-12):** Wegpunkt-/Befehls-Bug
tritt nicht mehr auf (Rollback bestätigt wirksam); FPS erwartbar wieder
niedriger. Zwei neue Beobachtungen → als **Phase 8.2**
([08c_combat_groups_reachability.md](08c_combat_groups_reachability.md))
festgeschrieben, bewusst unabhängig von der Performance-Arbeit und vor 8.1:
(1) Bergpass-KI buggt sich fest (Krieger-Trauben am Bergsockel, Bauversuche
auf unerreichbaren Plateaus — Plot-Suche prüft keine Erreichbarkeit);
(2) Nahkampf in der Debugschlacht: Einheiten-Ball schiebt nach Norden, wenig
echte Kämpfe (Hypothese: Gegner-Scan-Cap zählt Freunde mit → Blob-Blindheit;
Bucket-Iteration NW→SO → Richtungs-Bias). Ziel-Design laut Nutzer wie im
Original: Kampfgruppen 3-gegen-1 + Wartende, Gruppen mit kleinem
Mindestabstand (> 0) statt Blob.

---

## Phase 8.1 — Parallelisierung, Stufe A: Pfad-Worker-Thread (2026-07-12)

**Ziel (aus 08b):** Wegfindung auf einen eigenen Thread verlagern — beseitigt
Spike-Frames (fehlschlagende A*-Läufe nach Erdbeben/Massenbefehl, 50–400 ms)
UND macht die Phase-8-Rückstau-Bug-Klasse strukturell unmöglich (kein
Pro-Tick-Durchsatzlimit mehr auf dem Main-Thread). Akkurate 30-Hz-Sim bleibt.

**Gebaut:**
- **`scripts/core/path_worker.gd` (neu, `class_name PathWorker`, RefCounted):**
  Ein langlebiger `Thread` + `Mutex` + `Semaphore`, EINE gemischte FIFO-Queue
  für Grid-Deltas UND Pfad-Anfragen (garantiert: ein Terrain-Delta wirkt auf
  alle danach gestellten Anfragen). Eigener `AStarGrid2D`-Klon des UNIT-Grids,
  im `_init` aus `NavGrid.solid_snapshot()` geseedet (`update()` einmal, dann
  Solid-Sync), danach nur noch vom Worker-Thread berührt (Deltas +
  `get_id_path`). Snap (`nearest_walkable_cell`) läuft im Worker auf dem Klon.
  Transport nur POD: Anfrage `{instance_id, request_id, from_cell, target_cell}`,
  Antwort `{instance_id, request_id, Zell-Pfad PackedVector2Array}`. Kein
  `randf()`, kein Node-/RefCounted-Sharing. API: `push_delta`,
  `submit_request`, `drain_results`, `stop` (idempotent, joined den Thread).
- **`NavGrid`:** Feld `path_worker`; `update_region` spiegelt jede
  Unit-Grid-Solidity-Änderung als kompaktes Delta an den Worker (nach dem
  lokalen Update, FIFO-korrekt vor Folge-Anfragen). Neu: `solid_snapshot()`
  (voller Byte-Snapshot zum Seeden). Vehicle-Grid bleibt Main-thread-only
  (Siege-Pfade sind synchron/selten — bewusst NICHT über den Worker in Stufe A,
  Abweichung vom Plan-Ausblick „Vehicle-Grid im Worker").
- **`Unit`:** `_path_request_id` (monoton, neuer Befehl bumpt → invalidiert
  in-flight-Antworten). `_submit_path_request(worker)` (reicht Ziel als POD an
  den Worker, lässt `_pending_target` gesetzt → Einheit wartet). 
  `_apply_worker_path(request_id, cells)` (Main-Thread: Stale-Guard über
  request_id, konsumiert `_pending_target` bei aktuellem Request IMMER — sonst
  könnte ein Rückkehr-in-MOVE auf eine nie kommende id warten; Welt/Y-Konversion
  + „letzter Punkt = exakter Klickpunkt"-Regel hier, da Heights nie über den
  Thread gehen; leerer Pfad → IDLE + Waypoint-Pop wie synchron). Synchroner
  Pfad (`_resolve_pending_path`/`_plan_path_to`/`find_path`) unverändert.
- **`UnitManager`:** Feld `path_worker`; `_drain_path_queue` verzweigt zu
  `_drain_path_queue_async` (Worker gesetzt) — submittet ALLE Queue-Einträge
  (kein Limit) und wendet ALLE fertigen Antworten an (`instance_from_id` +
  `is Unit` + `is_instance_valid`-Guard). Kein Zeitbudget/Cap → Rückstau
  strukturell unmöglich. `_exit_tree` joined den Worker sauber
  (Szenenwechsel/Quit).
- **`Main`:** Konstante `USE_PATH_WORKER` (A/B-Schalter + Notfall-Fallback);
  erzeugt den Worker (nur bei >1 Kern) aus `nav.solid_snapshot()` und verdrahtet
  ihn in NavGrid (Delta-Spiegel) und UnitManager (Async-Solve).
- **`path_service == null` / Worker nicht gesetzt = exakt das heutige synchrone
  Verhalten** (Tests, Headless-Suite, Fallback).

**Tests (`tests/test_path_worker.gd`, neu, 17 Checks, alle grün):**
async Pfad wird erzeugt + gelaufen; Grid-Delta vor Folge-Anfrage respektiert;
veralteter Request (zweiter Befehl) verworfen (Ziel B statt A); unerreichbar →
IDLE; Shutdown ohne Hänger (inert nach `stop`); **Regression-Wächter**
(200 Braves Massenbefehl + Terrain-Delta mid-flight → KEINE Einheit bleibt in
MOVE mit leerem Pfad + offener Anfrage). `benchmark_mass` um Worker-A/B ergänzt
(`_make_world(use_worker)`, `_teardown` joined den Thread).

**Verifikation:** `--headless --import` sauber (PathWorker registriert);
Suite **1509 passed, 0 failed** (Exit 0); `--headless --quit` fehlerfrei;
**lagtest-Smoke** (`--quit-after 600 -- lagtest`, Bergpass 3 KIs) fehlerfrei,
kein Leaked-Thread → In-Game-Shutdown korrekt.

**A/B-Messung (benchmark_mass, headless, 30 Hz):**

| Szenario | Ø Tick | schlimmster Tick | Pfade main-seitig |
|---|---|---|---|
| move 2000 sync | 30,6 ms | 47,5 ms | 2000 (0,28 ms) |
| move 2000 worker | 30,5 ms | 50,6 ms | **0** (0 ms) |
| move 6000 sync | 77,1 ms | 107 ms | 6002 (0,84 ms) |
| move 6000 worker | 78,7 ms | 166 ms | **0** (0 ms) |

**Ehrliche Einordnung:** Stufe A verschiebt die Pfadarbeit vollständig vom
Main-Thread (Spalte „Pfade main-seitig" = 0). In diesem Benchmark war
Wegfindung aber NIE der Engpass (0,3–0,8 ms/Tick, 0 Fehlschläge) — der
Steady-State bleibt daher gleich; der Tick ist vom seriellen Units-Loop
(17,8 ms @2000 / 54 ms @6000) und Separation (9–13 ms) dominiert (= Stufe C
bzw. B). Der schlimmste Worker-Tick ist hier Scheduling-Rauschen auf Frame 0,
kein Pfad-Kostenpunkt. Der eigentliche Gewinn von Stufe A — Spike-Glättung bei
fehlschlagenden A*-Läufen + strukturelles Aus für den Rückstau-Bug — ist durch
den Regression-Wächter und die manuelle Prüfung abgedeckt, nicht durch dieses
spike-arme Benchmark.

**Stufe B (Separation-Fan-out): noch offen.** Messung zeigt Separation
9–13 ms/Tick (> 4-ms-Go-Schwelle), also lohnenswert — aber laut Plan („erst
nach STABILER Stufe A", „Änderungen einzeln + Langzeittest") und der
Nutzer-Vorgabe bewusst als eigener, separat abgesicherter Schritt offen
gelassen, nicht in derselben Sitzung angehängt. Nächster isolierter Schritt.

**Verifikationsstand:** Headless vollständig grün + lagtest-Smoke sauber.
Manuelle In-Game-Prüfung (langes Bergpass-Skirmish, Massenbefehl-Spikes,
F10-Zeitraffer, Speichern/Beenden) durch den Nutzer noch ausstehend.

### Stufe B — Separation-Fan-out: gemessen und VERWORFEN (No-Go, 2026-07-12)

**Umsetzung (funktionsfähig, konserviert in der Git-History):** Commit
`305f73a` enthält die komplette zweiphasige Parallel-Separation
(POD-Snapshot + CSR-Bucket-Grid per Counting-Sort, `WorkerThreadPool.
add_group_task` in 256er-Chunks, serielles Anwenden mit unveränderten
Walkability-/Y-Snap-/Escape-Regeln, Flag `separation_parallel` + Main-Konstante
`USE_PARALLEL_SEPARATION`, 13 Funktionstests). Revert in `c24c775`.

**Messung (benchmark_mass, Ø sep-Phase pro Tick, sync → parallel):**

| Szenario | sync | parallel | Gewinn |
|---|---|---|---|
| move 2000 | 9,09 ms | 5,89 ms | 3,2 ms |
| move 6000 | 12,83 ms | 12,24 ms | **0,6 ms** |
| combat 2000 | 9,29 ms | 5,90 ms | 3,4 ms |
| combat 4740 | 12,11 ms | 8,97 ms | 3,1 ms |

**No-Go-Begründung (Plan-Kriterium: > ~4 ms/Tick bei 2000+):** Überall
verfehlt; bei 6000 praktisch kein Gewinn. Ursache: Der **O(n)-Snapshot**
(Positionen/Flags/Bucket-CSR über ALLE Einheiten, pro Tick, in GDScript
~0,9 µs je Array-Schreibzugriff) kostet bei 6000 Einheiten ~11 ms und frisst
den Parallelgewinn der eigentlichen Push-Berechnung (parallel nur ~1 ms) fast
vollständig auf — die Skalierung, für die Stufe B gedacht war, findet nicht
statt. Dazu kamen zwei nötige Verhaltens-Workarounds, die die Semantik vom
seriellen Pfad wegbewegen (Regressionsrisiko der Phase-8-Klasse):

1. **Push-Lockstep:** Aus EINEM Snapshot berechnete Pushes sind für gestapelte
   Einheiten identisch, wenn beide unter dem 20er-Checks-Cap dieselbe
   Nachbar-Teilmenge sehen (CSR-Reihenfolge) — Distanz bleibt exakt 0, für
   immer. Die serielle Variante entgeht dem nur durch ihre SOFORTIGEN
   Positions-Writes. Workarounds: paar-antisymmetrische
   Voll-Überlapp-Richtung + pro Einheit rotierter Bucket-Scan-Start.
2. **Escape-Churn:** `overlap_ticks` akkumulieren auch während überlapptem
   Marschieren; snapshot-basiert eskapieren gestapelte Einheiten von derselben
   Position zur SELBEN freien Zelle, kommen gestapelt an und eskapieren sofort
   wieder — Endlosschleife. Workaround: Tight-Buchführung nur im IDLE.

**Lehren für einen späteren Neuanlauf (Stufe C):** Der Snapshot ist das
strukturelle Limit jeder „Spiegeln-dann-parallel"-Stufe in GDScript. Erst wenn
Positionen/Kernzustände OHNEHIN in Packed-Arrays leben (data-oriented
Unit-Loop, Stufe C), entfällt das Spiegeln — dann ist der Fan-out
(inkl. der beiden dokumentierten Workarounds) direkt wiederverwendbar:
`git show 305f73a`.

**Damit Definition of Done Phase 8.1 erfüllt:** Stufe A umgesetzt und grün,
Stufe B „gemessen und dokumentiert verworfen" (Plan-Option 2). Suite nach
Revert erneut 1509 grün.

---

## Phase 8.2 — Kampfgruppen (1-gegen-N) & Erreichbarkeits-Fixes (2026-07-12)

**Plan:** [08c_combat_groups_reachability.md](08c_combat_groups_reachability.md).
Umfasst laut Nutzer-Vorgabe Kampfgruppen-Verhalten UND Kampf-Performance.

### Diagnose-Befunde (Schritt 1, Hypothesen bestätigt)

- **Debugschlacht headless** (2×800 W/FW, Diagnose-Skript
  `tests/diag_8_2.gd`, bleibt als Messwerkzeug im Repo): Massenschwerpunkt
  driftete **−35 m nach Norden in 30 s** (dx blieb ±1 m) und die
  Melee-Quote lag im Peak bei nur **~25 %** der ATTACK-Einheiten
  (254 kämpfen / 1298 in ATTACK) — Hunderte „ATTACK ohne Slot" (warten)
  oder nur verfolgend. Beide 08c-Hypothesen bestätigt: (1) der
  Kandidaten-Cap (`get_units_in_radius`, max 24) zählte **Freunde** mit →
  Blob-Blindheit; (2) die Bucket-Iteration min→max (NW zuerst) wählte
  Ziele systematisch im Norden/Westen → kollektiver Nord-Drift.
- **Bergpass (Code-Befund):** `_approach` fiel bei fehlgeschlagenem A* auf
  einen **blinden Direkt-Schritt** zurück → Verfolger liefen dauerhaft
  gegen die Riegelwand (Plateau-Gegner liegen in 8-m-FLACH-Distanz im
  Aggro-Radius). `AIController._find_supplied_plot` prüfte **keine
  Erreichbarkeit** → begehbare, aber isolierte Plateau-Plots wurden bebaut,
  Arbeiter kamen nie an, die tote Baustelle blockierte
  `MAX_PARALLEL_SITES`.

### Gebaut

- **`scripts/core/combat_group.gd` (neu, `class_name CombatGroup`,
  RefCounted):** genau EIN Verteidiger + 1–3 Angreifer + Warteliste
  (zweite Reihe, Aufrück-Reihenfolge = Ankunft), Anker (folgt dem
  Verteidiger träge). Einheit ↔ Gruppe über `Unit.combat_group`
  (höchstens EINE Gruppe pro Einheit — 2v2/2v4 strukturell unmöglich).
  `remove_member` füllt frei werdende Slots sofort aus der zweiten Reihe
  nach (Regel 5).
- **`unit.gd` — Paarungsregeln in `_bind_to_fight(enemy, allow_wait)`:**
  freier Gegner → neue 1v1-Gruppe; Gegner-Verteidiger mit freiem Slot →
  beitreten (bis 1v3); voll → zweite Reihe; Gegner kämpft anderswo als
  Angreifer → **Flip** (sein 1v1 wird 2v1 auf ihn) bzw. **Pull**
  (Nachzügler der unterlegenen Seite zieht ihn aus der vollen Gruppe:
  1v3 → 1v2 + frisches 1v1, der Gezogene retargetet den Zieher via
  `_switch_target_to`). Ein Verteidiger behält seinen Sitz, egal wen er
  schlägt (Vergeltung gegen Außenstehende löst die eigene Gruppe NICHT
  auf). `_end_attack` gibt nur Angreifer-/Wartesitze frei;
  `_dissolve_own_group` (Tod/Konversion/Weltaustritt/Garnison) retargetet
  alle Mitglieder. Alte Slot-API kompatibel gehalten:
  `request_melee_slot`/`release_melee_slot`/`active_melee_attacker_count`
  arbeiten auf der Gruppe, `melee_attackers` ist ein Read-only-Getter
  (Feld + `incoming_attackers` + `_prune_melee_attackers` entfernt).
- **Kampf-Tick:** gebundene Kämpfer scannen NICHT mehr (Gruppe = Bindung)
  und pollen keine Slots; nur die zweite Reihe sucht gedrosselt nach
  Kämpfen mit Platz. Wartende stehen am Ring um den GRUPPEN-Anker
  (`_wait_near`) mit Idle-Animation (`_combat_waiting`) statt
  Auf-der-Stelle-Laufens.
- **Scan-Fixes:** `UnitManager.get_enemy_candidates(pos, radius, tribe,
  max_count, max_examined)` — sammelt NUR Gegner (Freunde verbrauchen das
  24er-Budget nicht mehr), Buckets ring-weise von innen nach außen (kein
  NW-Bias), Examine-Cap (Default 300, greift mitten im Bucket) begrenzt
  Scans im Mega-Blob. `_scan_for_enemy` bewertet mit
  **Gruppen-Slot-Score** (`_melee_engage_cost`: frei 0 … volle Gruppe
  10+Warteliste) statt `incoming_attackers`; Prediger-Fokus
  (`_pick_convert_focus`) nutzt dieselbe Query. Brave-Wachscan im
  Regroup-Pass läuft mit kleinem Budget (32).
- **Gruppen-Mindestabstand:** UnitManager-Registry + `_apply_combat_groups`
  pro Tick: Prune, Anker-Follow (3 m/s), Verteidiger zu naher Gruppen
  (< 2,8 m Anker-Abstand) werden auseinandergeschoben (1,2 m/s) — der
  Kampf franst in Grüppchen aus. Skalierungs-Guards wie bei der
  Unit-Separation (Slices à 256 Gruppen, max 12 Nachbar-Checks,
  zentrumszentrierte + pro Verteidiger gespiegelte Bucket-Reihenfolge
  gegen einen eigenen Richtungs-Bias, s. Stolpersteine).
- **Erreichbarkeit (Bergpass):** `_approach` gibt bei fehlgeschlagenem A*
  `false` zurück (kein blinder Schritt mehr); `_tick_attack` merkt sich das
  Ziel als unerreichbar (`_unreach_targets`, 3 s Bann, max 8 Einträge —
  der teure Fehl-A* läuft nicht pro Scan erneut) und disengagiert.
  **Partial-Paths:** `NavGrid.find_path(…, allow_partial)` /
  `PathWorker.submit_request(…, allow_partial)` — Attack-Move-Routen
  (`move_aggressive`) laufen bis zum letzten erreichbaren Punkt Richtung
  Ziel statt leer→IDLE („Wellenziel"); Exakt-Klickpunkt-Regel nur, wenn
  die Zielzelle wirklich erreicht wurde. Passive Moves unverändert
  (leer = Befehl fallen lassen). **KI-Plots:**
  `AIController._plot_reachable` (A* Basis→Plot, Pfadende muss ≤ 3 m am
  Plot liegen — der Snap kann sonst „über die Klippe" zeigen) mit
  Session-Cache `_unreachable_plots`; unerreichbare Kandidaten zählen
  gegen `MAX_PLOT_CANDIDATES`.
- Signatur-Anpassungen: `Firewarrior._scan_for_enemy`,
  `SiegeEngine._plan_path_to` (Katapult bleibt via `_is_ranged` gruppenfrei);
  `benchmark_mass` tickt `_apply_combat_groups` mit.

### Wirkung (Debugschlacht-Diagnose vorher → nachher)

- Nord-Drift: **−35 m → max ~−4 m** (kehrt gegen 0 zurück; Rest =
  Zufalls-Random-Walk der Schubser/Rollen).
- Melee-Quote im Peak: **~25 % → ~50–66 %** der ATTACK-Einheiten; die
  Schlacht ist deutlich schneller entschieden (nach 900 Ticks 252 statt
  713 Überlebende — es wird gekämpft statt gestanden).

### Kampf-Performance (Deliverable 4; headless, DIESER Rechner ist
schneller als der PROGRESS-Referenzrechner — Vorher-Werte am selben Tag
gemessen)

| Szenario | vorher Ø | nachher Ø | units-Phase | A*-Läufe/300 Ticks |
|---|---|---|---|---|
| combat 2000 | 26,5 ms | **15,6 ms** | 19,5 → 9,6 ms | 29 955 → ~2 100 |
| combat 4740 | 59,8 ms | **37,3 ms** | 48,0 → 24,5 ms | 91 524 → ~4 700 |
| move 2000 | 18,8 ms | 16,3 ms | — | — |
| move 6000 | 47,2 ms | 42,4 ms | — | — |

Größter Hebel wie im Plan erwartet: **gebundene Kämpfer sind billig**
(kein Scan, kein Slot-Polling, kaum Replans); die sep-Phase liegt trotz
des neuen Gruppen-Passes unter der Baseline, weil die entzerrten Kämpfe
weniger Überlappungen erzeugen. Schlimmster Einzeltick im Kampf bleibt
hoch (~90/210 ms, Erstkontakt-/Massensterben-Frames) — im Spiel fängt der
2er-Step-Cap das ab.

### Stolpersteine / Erkenntnisse

- **Jeder gecappte Nachbar-Sweep ist ein Bias-Kandidat:** Der neue
  Gruppen-Push drückte mit fixer min→max-Bucket-Reihenfolge + Check-Cap
  alle Gruppen systematisch nach Süden (gleiche Fehlerklasse wie der
  Scan-Nord-Drift!) — der Symmetrie-Wächter hat es gefangen. Fix:
  zentrumszentrierte, pro Verteidiger gespiegelte Reihenfolge.
- **Examine-Caps müssen IN der Bucket-Schleife greifen** — ein Check nach
  dem Bucket iteriert im Blob trotzdem 100+ Einheiten pro Scan
  (Regroup-Phase 1,5 → 12 ms bei move 6000, nach dem Fix 0,5 ms).
- Ternary-Zuweisung an `Array[int]` wirft nur einen LAUFZEIT-Typfehler —
  die Funktion bricht still ab (Suite fing es über den Abstands-Test).
- Ein Verteidiger, der einen AUSSENSTEHENDEN schlägt (z. B. Vergeltung
  gegen Fernkämpfer), darf seine eigene Gruppe nicht verlassen/auflösen —
  sonst kollabiert der Melee-Ring um ihn (Reserve-Reihen-Test fing es).
- Godot-stdout wird auf diesem System vom PowerShell-Tool verschluckt —
  Godot-Läufe über Git-Bash ausführen.

### Tests

`tests/test_combat_groups.gd` (neu, 12 Tests): 6-auf-1 → 3 kämpfen +
3 warten + Nachrücken beim Tod; Warte-Ring-Positionen; 2v2 → zwei 1v1;
2v4 → 1v2 + 1v2; Nachzügler-Pull (1v3 → 1v2 + 1v1, Retarget);
Invarianten-Wächter (≤ 3 Angreifer, genau eine Rolle pro Einheit,
Rückverweise); Gruppen-Mindestabstand; Scan-findet-Gegner-im-Freundes-Blob;
**Symmetrie-Wächter** (gespiegelte Armeen: max. Schwerpunkt-Drift < 3 m —
alter Bias ~5+ m in diesem Setup, −35 m in der Vollschlacht — und
Melee-Quote ≥ 35 %); unerreichbares Kampfziel wird fallengelassen
(keine Klippen-Anläufe); Attack-Move nimmt Partial-Path (kommt bis zur
Wand, nie darüber; passiver Move bricht sauber ab); KI-Plot-Suche
verwirft Plateau-Plots (inkl. Cache) und wählt erreichbar. Bestehende
Slot-/Kampf-Tests laufen unverändert auf dem Gruppen-Modell (Semantik
1-gegen-N, N ≤ 3, erhalten).

### Verifikation

`--headless --import` sauber; Suite **1591 passed, 0 failed** (mehrfach
wiederholt — der Symmetrie-Wächter enthält Zufallsanteile);
`--headless --quit` fehlerfrei; **lagtest** (Bergpass, 3 KIs) 600 und
**2500 Frames** fehlerfrei. **Manuelle Prüfung (Nutzer) ausstehend:**
Debugschlacht-Optik (1-gegen-N-Grüppchen + zweite Reihe, kein Ball, kein
Nord-Schub, FPS vorher/nachher am Referenzrechner — Ist war 60 → 12 FPS),
langes Bergpass-Skirmish (keine Sockel-Trauben, KI baut kontinuierlich).

### Abweichungen vom Plan / Offenes

- „Neue Kämpfe nur mit Mindestabstand" ist als **weicher Push** umgesetzt
  (Kämpfe entstehen, wo Einheiten sich treffen, und werden binnen Sekunden
  auseinandergeschoben) statt als hartes Entstehungs-Verbot — robuster;
  der Test prüft den eingeschwungenen Abstand.
- KI-Wellen-Reissue brauchte kein eigenes Gate: Partial-Path +
  Unreachable-Drop entschärfen das „alle 4 s gegen die Wand"; das
  Wellenziel (nächstes Gegner-Gebäude) ist im Bergpass regulär über die
  Pässe erreichbar.
- `_unreachable_plots` wird bei Terraforming (Landbrücke!) nicht
  invalidiert (Plan: kleiner Session-Cache). Falls die KI später
  Landbrücken zur Expansion nutzt: Cache bei Terrain-Änderung leeren.

### Nutzertest + Nacharbeit (2026-07-12, zweite Runde)

**Nutzertest-Ergebnis:** Kampfablauf deutlich besser, Einheiten greifen
richtig an, **Nord-Bug bestätigt weg**. Zwei Punkte: (1) In-Game-Performance
„etwas schlechter" (trotz besserer Headless-Werte — Hauptverdächtiger unten
gefunden und behoben; erneuter FPS-Test durch Nutzer ausstehend);
(2) **Einheiten stacken stark** → offener Punkt, Kandidaten: Melee-Ring
(0,9 m) / Warte-Ring-Winkelverteilung / Separation im Kampf / Leichen unter
laufenden Kämpfen. Nicht in dieser Runde angefasst.

**Neue Schlacht-Benchmarks (Nutzerwunsch):** `benchmark_mass` hat zwei
zusätzliche Szenarien im Debugschlacht-Zuschnitt (zwei Armeen ±20 Zellen um
die Inselmitte, Attack-Move aufeinander, 450 Ticks, Ausgabe zusätzlich als
„Ø Kampf-Fenster" ab Tick 150): **schlacht krieger 2x1000** (reiner
Nahkampf: Gruppen/Slots/Schläge) und **schlacht feuerkrieger 2x1000**
(reiner Fernkampf: Zielsuche + Projektillast — von keinem bisherigen
Szenario abgedeckt).

**Fund durch das neue Szenario — Feuerkrieger-Hotspot:** Die reine
fw-Schlacht lief anfangs mit **Ø 264 ms/Tick (units-Phase 254 ms!)**.
Ursachen: `_melee_threat()` lief pro fw PRO TICK als ungecappte
`get_units_in_radius`-Query, und die Prediger-Priorität
(`_nearest_enemy_priest`, 13-m-Radius) sweepte ungecappt über das ganze
Schlachtfeld. Fixes (einzeln, konservativ):
- `Tribe.preachers` (neue Liste, gepflegt in add_unit/remove_unit —
  Konversionen laufen über dieselben Hooks): der Priest-Scan iteriert die
  wenigen Prediger der Gegnerstämme statt Tausender Umgebungseinheiten.
- `_melee_threat()` auf gecappte `get_enemy_candidates` (Radius 1,2 m,
  max 6 Kandidaten / 48 examined) umgestellt.
- Threat- UND Priest-Check hinter die vorhandene Scan-Drossel
  (`_due_to_scan`, 0,25 s) gelegt — gleiche Reaktions-Kadenz wie alle
  anderen Scans (vorher: Threat-Check pro Tick).
- Nebenbei: fw disengagiert jetzt wie der Nahkampf bei unerreichbarem Ziel
  (`_approach` false → `_mark_target_unreachable` + Retarget) statt
  eingefroren an der Wand zu stehen.

**Messwerte (headless, dieser Rechner):**

| Szenario | vor Fix | nach Fix |
|---|---|---|
| schlacht feuerkrieger 2x1000 | Ø 264,0 ms (units 254,4) | **Ø 28,2 ms** (units 20,9) |
| schlacht krieger 2x1000 | Ø 28,5 ms | Ø 21,5 ms |
| combat 2000 (Grid) | — | Ø 13,3 ms |
| combat 4740 (Grid) | — | Ø 31,8 ms |

Die Debugschlacht hat 30 % Feuerkrieger — der fw-Hotspot ist der
plausibelste Täter für das „etwas schlechter" des Nutzertests (die alten
Benchmarks enthielten schlicht keine Fernkämpfer). Verbleibende fw-Kosten:
~65k Chase-Replans/450 Ticks (~2,3 ms/Tick A*) — unter Budget belassen.

**Parallelisierungs-Einschätzung Kampflogik (Nutzerfrage „wie bei der
Bewegung"):** Vorerst NICHT umsetzen, Begründung:
- Der Pfad-Worker parallelisiert eine **reine Funktion** (Grid-Klon, POD
  rein/raus, keine Rückwirkung). Der Kampf-Tick ist das Gegenteil: fast
  jede Operation **mutiert geteilten Zustand** (take_damage auf beliebige
  Ziele, Gruppen-Membership/Flip/Pull, Retarget-Kaskaden bei Toden,
  Spatial-Hash) — in GDScript ohne thread-sichere Objekte nur über
  „Snapshot → parallel rechnen → seriell anwenden" machbar.
- Genau diese Snapshot-Architektur ist in **Stufe B gemessen gescheitert**
  (O(n)-Spiegeln in GDScript ≈ 11 ms bei 6000 — frisst den Gewinn); ein
  Kampf-Snapshot wäre GRÖSSER (HP, Ziele, Gruppen, Cooldowns) und das
  serielle Zurückschreiben (Schäden, Zustandswechsel) breiter.
- Der parallelisierbare (read-only) Anteil — Gegner-Scans/Zielsuche — ist
  nach 8.2 gerade KLEIN geworden: gebundene Kämpfer scannen nicht mehr;
  der Kampf-Tick besteht jetzt aus Verfolgen/Zuschlagen/Basisarbeit.
  Erwartbarer Gewinn liegt unter der 4-ms-Go-Schwelle aus 08b → gleiches
  No-Go-Verdikt wie Stufe B.
- **Voraussetzung für echten Kampf-Fan-out bleibt Stufe C**
  (data-oriented: Positionen/HP/Ziele in Packed-Arrays — dann entfällt das
  Spiegeln, und Separation + Scans sind natürliche Parallel-Kandidaten;
  Wiedereinstieg: `git show 305f73a` + PROGRESS „Stufe B").

**Verifikation:** Suite 1591 grün, Ladecheck sauber, lagtest-Smoke
(600 Frames) fehlerfrei. **Nutzer ausstehend:** FPS-Nachtest Debugschlacht
(fw-Fix!), Stacking-Beurteilung nach dem nächsten Balancing-Pass.

### Stresstest-Modus im Hauptmenü (Nutzerwunsch, 2026-07-13)

**Nutzertest fw-Fix bestätigt:** „keine großen Frameeinbrüche bei
Debugschlacht mehr."

**Neuer Sandbox-Modus `Stresstest`** (Hauptmenü-Button unter Debugschlacht;
headless/CLI: `godot … -- stresstest`), Spezifikation vom Nutzer:
- **4 Armeen** (Stamm 0 = Spieler, spielbar; Stämme 1–3 skriptgesteuert,
  KEIN AIController) auf den Kompasspunkten ±30 Zellen um die Inselmitte,
  je **1000 Fußeinheiten** (60 % Krieger vorn, 30 % Feuerkrieger, 10 %
  Prediger hinten) + **6 bemannte Katapulte** (je 3 Brave-Crew, spawnen
  direkt am Gerät und boarden sofort) + Schamanin im Rücken mit vollen
  Ladungen → **4100 Einheiten gesamt**.
- Nach **5 s Idle** ein einmaliger **Angriffsbefehl** (Attack-Move) aller
  vier Armeen auf die Inselmitte (Crew-Braves ausgenommen — ein Move-Befehl
  würde sie vom Katapult ziehen); ab Kontakt übernimmt das Kampfsystem.
- **Zauber-Dauerfeuer:** alle 5 s ein Cast pro Stamm, rotierend durch
  **Tornado / Erdbeben / Insektenschwarm / Feuerregen**; Ziel = nächster
  Gegner um die Schamanin (30 m, `get_enemy_candidates`), vor Kontakt die
  Inselmitte. Die Ladung wird vor jedem Cast aufgefüllt (Sandbox — Dauerlast
  ist der Zweck). Kein Win-Tracking, keine Basen (wie Debugschlacht).

**Umsetzung:** `MatchConfig.Mode.STRESS_TEST` + `stress_test()`
(`tribe_count()` = 4), Menü-Button + `stresstest`-CLI-Flag (main_menu.gd),
`main.gd`: `STRESS_MATCH_*`-Konstanten, `_setup_stress_match` /
`_spawn_stress_match_army` / `_spawn_stress_match_sieges` (nutzt
`_spawn_debug_shaman` wieder), Treiber `_tick_stress_match` in
`_physics_process`.

**Test-Härtung nebenbei:** Der Symmetrie-Drift-Wächter bekam `seed(1337)`
+ Toleranz 4,5 m (Random-Walk der Schubser/Rollen erreichte auf grünem Code
~3,7 m; der systematische Bias lag bei 5+ m klein / −35 m groß). Der
dadurch semi-deterministisch gewordene `test_attack_move_engages_enemies`
flatterte danach (Prüfung eines MOMENT-Zustands: Schubser-Mini-Roll genau
im Prüf-Tick) → auf Poll „engagiert innerhalb 4 s" umgestellt.

**Verifikation:** Ladecheck sauber; headless-Smoke `--quit-after 1200 --
stresstest`: 4100 Einheiten, Abmarsch feuert, keine Fehler; Suite **1591
grün, 6× wiederholt**. **Nutzer ausstehend:** manueller Stresstest-Lauf
(Optik/FPS der Zauber-Dauerlast).

### Bugfix-Runde nach Stresstest (Nutzerreport, 2026-07-13)

Nutzerfeedback: Stresstest läuft (langsam, „erstmal ok"). Drei gemeldete
Bugs, alle behoben:

**1. Stolpern vergisst den Auftrag.** Die Steilhang-Stolperrolle
(`_advance_path` → `start_roll`) räumte wie jede Kampfrolle ALLE Befehle ab
(`_on_combat_interrupt` + Waypoints). Fix: `start_roll(…, stumble)` — der
Stolper-Aufruf markiert die Rolle als harmlos; Befehle/Task-Felder bleiben
erhalten (`_stumble_resume` = vorheriger State) und `_end_roll` setzt über
`_resume_after_stumble` fort: MOVE plant frisch zum nächsten Wegpunkt,
ATTACK kämpft weiter (Gruppenbindung überlebt die Rolle ohnehin),
Arbeiter-/Gebets-/Trainings-/Crew-Sub-States laufen mit intakten Feldern
weiter. **Brave:** neuer Hook `_on_stumble` — lässt getragenes Holz als
Haufen fallen, behält aber Task/Claim; beim Fortsetzen findet die normale
Task-Wahl den Haufen vor den Füßen und hebt ihn wieder auf. Trifft eine
Kampf-/Zauberrolle die stolpernde Einheit mid-Roll, wird daraus eine echte
Kampfrolle (Befehle weg, Originalregeln). Panik wird durch Stolpern nicht
mehr abgebrochen, sondern pausiert (Test in test_spells angepasst: auf
`can_take_orders` warten statt `!= PANIC`).

**2. Unsterbliche Dauerrolle in der Erdbebensenke (Priester-Report).**
Root cause gefunden: `take_damage` schiebt den Tod im ROLL-Zustand auf
(`_end_roll` holt ihn nach) — aber in einer steilen Senke bleibt die
Fall-Linie dauerhaft über `ROLL_END_SLOPE`, die Rolle endet NIE → Einheit
unsterblich trotz negativer HP. Drei Sicherheitsnetze in `_tick_roll`:
(a) tödlicher Schaden wird nur bis zur Mindest-Rolldauer aufgeschoben,
nicht ewig; (b) Fortschritts-Sonde: < 1 m Netto-Bewegung in 2 s → Rolle
endet (Lebende stehen auf, Getötete sterben); (c) Hard-Cap
`ROLL_MAX_DURATION = 30 s` → Tod als Leiche. Analog für Würfe:
`THROWN_MAX_DURATION = 30 s` — ein nie landender Wurf/Carry endet als
Leiche am Boden („fällt aus dem Himmel").

**3. Katapulte stacken (inkl. Crew-Clipping).** Katapulte sind
`push_immune` und wurden von der Separation KOMPLETT übersprungen — auch
gegeneinander. Fix: neues Unit-Feld `vehicle_separation` (SiegeEngine:
**3,2 m**, deckt Rumpf + Crew-Seiten-/Rang-Slots ab); die Separation
verarbeitet Fahrzeuge jetzt MIT diesem Radius, aber nur gegen ANDERE
Fahrzeuge — Fußgänger können das Gerät weiterhin nicht wegschieben, und
geschützte Reserven (Turm-/Hütten-Crews, push_immune ohne Radius) bleiben
ausgenommen. Die Crews folgen ihren Slots → kein Clipping mehr.
Overlap-Escape bleibt Fußgänger-only. (Achtung Godot-Falle dabei: der
Override `SiegeEngine.start_roll` musste die neue Default-Signatur
spiegeln — Signatur-Mismatch ist ein Parse-Error, der die GANZE Klasse
aus dem Spiel nimmt.)

**Tests:** `tests/test_stumble_roll.gd` (neu, 7 Tests): Move-Resume nach
Stolperer (kommt trotzdem am Ziel an), Kampfrolle räumt weiter ab,
Kampftreffer mid-Stolperer räumt ab, Brave lässt Holz fallen + behält
Task/Claim, V-Rinnen-Terrain (Erdbebensenken-Form): tödlicher Schaden in
gefangener Rolle tötet binnen Sekunden, gesunde Einheit steht per
Fortschritts-Sonde wieder auf, Endlos-Wurf stirbt am 30-s-Cap und liegt am
Boden. `test_siege.gd`: +Fahrzeug-Separation (Geräte spreizen auf ≥ ~3 m,
Fußgänger schiebt Gerät nicht). Suite **1619 grün (3×)**; Ladecheck,
Stresstest-Smoke (1800 Frames) und lagtest-Smoke sauber.

## Asset-Migration: Pipeline für echte Assets (vor Balancing, 2026-07-13)

Umstieg von rein prozeduralen Inhalten auf nutzerlieferbare Assets — mit den
prozeduralen Platzhaltern als **permanentem, automatischem Fallback**: fehlt
eine Datei unter `assets\`, greift der bisherige Code; Assets können
stückweise geliefert werden. Konventions-Doku für den Asset-Ersteller:
**`assets\README.md`** (Ordnerbaum, Sheet-Layout, glb-Regeln, Audio-Formate,
Import-Pflicht).

**Zentrale Auflösung — `scripts/core/asset_library.gd`** (`AssetLibrary`,
statisch): `texture/image/model/instantiate_model/stream/json/
stream_variants/stream_folder` — alle liefern `null`/leer bei fehlender
Datei (→ Fallback im Aufrufer), cachen Ergebnisse und warnen einmalig, wenn
eine Datei auf der Platte liegt, aber nicht importiert ist (klassische
`--headless --import`-Falle, §9 CLAUDE.md).

**Audio (voller Umfang):**
- Neues Autoload **`AudioManager`** (`scripts/core/audio_manager.gd`, 3.
  Eintrag in project.godot): legt Busse **Music/Ambience/SFX/UI** idempotent
  per Code an, `play_sfx(name, pos)` (3D-Pool, 8) / `play_ui(name)` (2D-Pool),
  Musik-/Ambience-Playlists aus `assets/audio/music|ambience/` (leer =
  still), statische Bus-Lautstärke-Helper für die Options-UI.
- Neue Events-Signale: `building_completed`, `unit_trained`, `spell_cast`
  (Emits: `building.gd` finish_construction, `training_building.gd`
  _finish_one, `shaman.gd` beide Cast-Stellen via `_emit_spell_cast`; alle
  mit `is_inside_tree()`-Guard — headless-Tests instanziieren außerhalb des
  Trees). AudioManager hört darauf + `building_destroyed`; Selektions-Sounds
  direkt in `selection_manager.gd`, `build_place` in `building_manager.place`.
- `combat_audio.gd`: nutzt pro Kind `assets/audio/sfx/combat/<kind>_<n>.ogg`
  wenn vorhanden, sonst unverändert die Synthese (`generate_samples` bleibt
  statisch → test_combat grün); Pool-Player auf Bus SFX.

**Gebäude:** `building.gd` — neues virtuelles `asset_kind()` +
`_try_load_custom_model()` in `_create_visuals()` (lädt
`assets/models/buildings/<kind>.glb`, setzt `_has_custom_model`, färbt
`Flag`-MeshInstance3D im Modell bzw. hängt die Prozedural-Flagge an); alle
8 Subklassen: Early-Return nach `super._create_visuals()`. Bau-Wachstum,
Wobble, Versinken, Zerstörungslöcher (Stage-Hook) arbeiten modell-agnostisch
auf `_mesh_root` weiter — Stufen-glbs (`<kind>_stage<N>.glb`) sind als v2
vorgesehen, nicht umgesetzt.

**Terrain:** `shaders/terrain_triplanar.gdshader` (neu) — Sand/Gras
top-projiziert, Fels triplanar (5 statt 9 Fetches), Höhen-Blend spiegelt
`_color_for_height`, plus Slope-Term (Klippen = Fels), weiche Multiplikation
mit der Vertex-Farbe. `terrain.gd::_create_material()`: ShaderMaterial nur
wenn `assets/textures/terrain/{sand,grass,rock}.png` alle existieren, sonst
bisheriges Vertex-Farb-Material; Vertex-Farben werden IMMER erzeugt →
`_build_chunk_mesh`/`rebuild_chunks` unverändert (Verformung robust, keine
UVs). Wasser: optionale `water.png` als gekachelte Albedo.

**Einheiten (perf-kritisch):** `scripts/ui/unit_sprite_library.gd` (neu,
`UnitSpriteLibrary.build_atlas`) — identischer Contract wie
`PlaceholderSprites.build_atlas` (texture/uvs/frame_uv/table) **plus
`mask_texture`** (L8). Pro (kind, anim): Sheet
`assets/units/<kind>/<anim>.png` gemäß `manifest.json`
(frame_width/height Pflicht, fps optional) sliceb; 8 oder 5 Zeilen
(5 → linke Ansichten per flip_x gespiegelt wie `MIRRORED_VIEWS`); fehlendes
Sheet → `PlaceholderSprites._build_frames` nur für diese Anim. Eine
einheitliche Atlas-Zelle (Maximum aller Framegrößen, Platzhalter 16×24;
kleinere Frames nearest-hochskaliert) → `frame_uv` bleibt EIN Uniform.
`unit_renderer.gd`: Quadgröße jetzt `SPRITE_WORLD_W/H` (0.96/1.44 m,
ersetzt `W/H*PIXEL_SIZE`), Shader-Fragment `ALBEDO = tex.rgb *
mix(vec3(1), tint.rgb, mask)` — Maske weiß = exakt altes Voll-Multiply;
echte Art darf voll koloriert sein, Stammes-Bereiche via `<anim>_mask.png`.
MultiMesh/ein Draw Call/INSTANCE_CUSTOM/Dither-Fade unangetastet.
Kontrakt-Check headless: alte vs. neue Tabelle identisch (1288 Frames,
TABLE_MATCH yes); Atlas-Bau 17→33 ms (einmalig beim Start).

**Bäume/Katapult:** `tree_resource.gd` lädt `models/trees/tree.glb`
(Wachstum = Skalierung funktioniert weiter; Brand-Flackern nur prozedural,
glb schrumpft beim Brennen). `siege_engine.gd::_create_model()` lädt
`models/units/siege_engine.glb`; optionale Nodes `Arm` (Wurfarm-Pivot) und
`Flag` (Stammesfarbe); gemeinsamer Abschluss `_finish_model` (Shadow-Off +
Blob).

**Nicht umgesetzt (bewusst):** Zauber-Textur-Hooks (Phase 6 des Plans,
optional/niedrigste Priorität — Visuals bleiben prozedural; Zauber-SOUNDS
laufen bereits über `Events.spell_cast`), Gebäude-Stufen-glbs (v2),
Options-UI für die neuen Audio-Busse, Sidebar-Porträt weiter über
`PlaceholderSprites.make_frames`.

**Stolpersteine:**
- Neue `class_name`-Skripte → erst `--headless --import`, sonst
  „Identifier not declared" (bekannt, §9).
- `get_node_or_null("/root/…")` außerhalb des Scene-Trees ist ein ERROR —
  alle neuen Emits/Audio-Aufrufe brauchen `is_inside_tree()`-Guards
  (headless-Tests bauen Welten ohne Tree).
- `Image.blit_rect` verlangt gleiche Formate — Sheets/Masken werden nach
  RGBA8 konvertiert, Masken-Atlas ist L8.
- Sheet-Hard-Cap **64×96 px** (README): 128×192 sprengt das
  Atlas-Budget (~380 MB VRAM bzw. 16384-Limit).

**Verifikation:** Suite **1619 grün** (2 Flakies in Einzelläufen —
Zentroid-Drift 5,49 m > 4,5 und einmal test_perf — reproduzierten nicht;
parallel lief eine andere Session auf der Maschine), Ladecheck sauber,
Shader-Parse-Check ok, Stresstest-Smoke (4100 Einheiten, 45 s) und
Skirmish-Smoke (30 s) ohne Script-Fehler — alles mit leerem `assets\`
(= Fallback identisch zu vorher). **Nutzer ausstehend:** FPS-Vergleich
Stresstest gegen Baseline am echten Bildschirm; Test mit ersten echten
Asset-Dateien (dann `--headless --import` nicht vergessen).

### Zusätzliche Sound-Anker (Nutzerwunsch, 2026-07-13)

15 weitere Einhänge-Punkte, alle rein file-basiert (Fallback = stumm, außer
Katapult-Schuss). Vollständige Namens-Doku in `assets\README.md`.

- **Einheiten (`unit.gd`):** neuer gecachter Helper `_play_sfx(name,
  min_interval)` (Muster wie `_emit_combat_hit`). Hooks: `unit_panic`
  (start_panic, 150 ms global gedrosselt), `unit_injured` (take_damage —
  einmalig beim Unterschreiten von `BADLY_HURT_FRAC` = 25 %, nicht
  Schamanin), `shaman_hurt` (jeder Treffer, 800 ms), `unit_burning`
  (ignite, frisch). Tod zentral im AudioManager über `Events.unit_died`:
  `shaman_death` bzw. `unit_death` (200 ms gedrosselt).
- **Katapult:** `siege_fire` beim Schuss — NUR wenn die Datei existiert
  (`AudioManager.has_sfx`), sonst weiter das synthetische `throw`;
  `siege_impact` im `SiegeShot._impact`; `siege_burning` bei `ignite`.
- **Gebäude (`building.gd`):** eigener `_play_sfx`-Helper mit
  **Pro-Gebäude-Drossel** (`_sfx_last_ms`-Dict je Instanz).
  `building_attack_melee` im Raid-Tick (max. 1 Sound/Gebäude je 2,5 s,
  unabhängig von der Angreiferzahl — Nutzeranforderung),
  `building_attack_ranged` bei `take_damage(DMG_RANGED)` (1,5 s je Gebäude),
  `building_damaged` beim Überschreiten einer Zerstörungsstufe
  (Stage-Vergleich vor/nach dem Schaden). KEIN Gebäude-Brand-Sound —
  Gebäude haben keinen Brand-Zustand (nur Stufen); dem Nutzer so berichtet.
- **Umwelt:** `tree_burning` (TreeResource.ignite), `wood_chop` zentral in
  `TreeManager.harvest_tree` (deckt Job- UND Loose-Chop ab, 250 ms).
- **UI (`selection_manager.gd`):** Selektion spielt `select_shaman` wenn die
  Schamanin in der Auswahl ist, sonst `select_unit`; Move-Befehl analog
  `move_shaman`/`move_unit` (`_play_move_sound` nach beiden
  order_move-Zweigen in `_command_move`) — je Vorgang genau ein Sound.
- **AudioManager:** `play_sfx` kann jetzt pro Name global drosseln
  (`min_interval_ms`), neu `has_sfx(name)`; `unit_died`-Hook.

**Verifikation:** Suite 1619 grün, Ladecheck sauber, Stresstest-Smoke (40 s,
übt Panik/Tod/Katapult/Raid-Pfade) ohne Script-Fehler — ohne Sound-Dateien
ändert sich nur der Katapult-Schuss nicht (Fallback-Regel), alles andere
bleibt exakt wie vorher.

### Leichen-Versinken + zentrale Balance-Datei (Nutzerwunsch, 2026-07-13)

**Leichen versinken statt zu verblassen:** Der Dither-Alpha-Fade
(`corpse_alpha`, Shader-Farb-Updates im Renderer) ist ersetzt durch
`Unit.corpse_sink_depth()` — nach `CORPSE_DURATION` (5 s) sinkt das
Leichen-Sprite über `CORPSE_SINK_DURATION` linear um `CORPSE_SINK_DEPTH`
(1,6 m) in den Boden; der Transform-Pass des UnitRenderers zieht die Tiefe
einfach von pos.y ab (ein Draw Call unangetastet). Aufgeräumt: totes Feld
`_render_alpha` entfernt; `test_combat` auf Sink-Semantik umgestellt.
**Stolperstein:** Die Sink-Dauer verlängert die Lebenszeit der Leiche in der
Welt — der Zentroid-Drift-Wächter (test_combat_groups) zählt Leichen mit und
schlug bei 2 s Sink-Dauer DETERMINISTISCH fehl (5,03 m > 4,5, zweimal exakt
gleich). Sink-Dauer = 1,0 s hält die Gesamtdauer bei 6 s wie vorher → grün.
Wer den Wert in balance.gd erhöht, muss den Drift-Test im Blick haben
(Hinweis steht als Kommentar direkt an der Konstante).

**Zentrale Balance-Datei `scripts/core/balance.gd`** (`class_name Balance`,
nur Konstanten, deutsch kommentiert): Einheiten (HP/Tempo/Nahkampfstärke/
Schuss- und Aggro-Reichweiten/Cooldowns, Prediger-Bekehrzeit MIN/MAX,
Schamanin inkl. Respawn-Zeit + Kill-Bonus), Nahkampf allgemein
(Schlagschäden, Chancen, Regeneration), Leichen-Zeiten, Brand/Lava,
alle 10 Zauber (charge_cost/max_charges/cast_range + zentrale Effektwerte
wie Blitz-/Feuerball-/Erdbeben-Schaden, Tornado-Stufenintervall,
Feuerregen-Boltzahl), Katapult (Tempo/Reichweiten/Cooldowns/
Einschlag-Schaden/Gebäudestufen), Gebäude (Holzkosten/HP/Ausbildungszeiten/
Hütten-Spawn/Crew, Förster/Werkstatt/Wachturm-Werte, Stufen-Schadensanteil,
Raid-DPS), Wirtschaft (Mana-Raten, Einheiten-Hardcap, Baumwachstum/-Ertrag).

**Verkabelungs-Muster (bewusst):** Die Klassen behalten ihre lokalen
Konstantennamen und beziehen nur den WERT aus Balance
(`const MELEE_PUNCH: int = Balance.MELEE_PUNCH`) — dadurch bleiben alle
Test-Referenzen (`Unit.MELEE_PUNCH`, `Hut.CAPACITY`, `Watchtower.WOOD_COST`,
`ReincarnationSite.RESPAWN_TIME` … ~15 Testdateien) und Querverweise
(`RangeRenderer.range_for_kind`) unverändert gültig. Geändert: unit.gd,
brave/warrior/firewarrior/preacher/shaman/siege_engine/siege_shot,
building.gd + hut/warrior_camp/temple/firewarrior_camp/forester/workshop/
watchtower/reincarnation_site, tribe.gd, tree_resource.gd, alle 10 Spell-
Dateien + fireball_bolt/swarm_cloud/tornado_vortex/volcano_zone.
NICHT zentralisiert (bewusst, Verhalten/Physik statt Balance): Roll-/Wurf-/
Knockback-Physik, Scan-Intervalle/Budgets, Queue-/Slot-Layouts, Visuals.

**Verifikation:** Suite 1619 grün (alle Werte identisch übernommen —
verhaltensneutral), Ladecheck sauber, Stresstest-Smoke ohne Fehler.
Nachtrag: Gebäude-Footprints ebenfalls zentralisiert (8 FOOTPRINT-Shims).

### Status-Effekt-Overlays + Loop-Sounds (Nutzerwunsch, 2026-07-13)

Anhaltende Zustände bekommen eigene, unterscheidbare Optik (vorher gab es
nur die kurzen Schadens-Sterne) plus Dauerschleifen-Sounds:

- **`scripts/ui/status_fx_renderer.gd`** (neu, Muster = StarsRenderer): drei
  MultiMeshes (je 1 Draw Call, Cap 256 Instanzen) für **PANIC** (rotes
  Ausrufezeichen über dem Kopf), **BURNING** (Flackerflamme auf dem Körper,
  auch brennende Katapulte) und **INJURED** (< 25 % Leben =
  `Unit.BADLY_HURT_FRAC`, rote Tropfen; nur Sprite-Einheiten — die 1-HP-
  Konvention des Katapults zählt nicht als Verletzung). Icons prozedural
  (2–3 Frames, geteilter Material-Frame wie bei den Sternen), ersetzbar per
  `assets/textures/effects/<name>.png` (Einzelbild oder horizontaler
  Streifen quadratischer Frames). Positionierung entlang Kamera-Up wie die
  Sterne. Verkabelt in main.gd neben dem StarsRenderer.
- **Loop-Sounds im AudioManager:** neue API `start_loop(name, owner)` /
  `stop_loop(name, owner)` — positionaler Player folgt dem Owner
  (`_process`), Loop per finished→play (unabhängig vom Import-Loop-Flag),
  **Cap `LOOP_CAP_PER_NAME` = 4** gleichzeitige Emitter pro Name; weitere
  Owner warten und werden beim Freiwerden promotet. Owner weg (freed /
  nicht mehr im Tree) → Slot wird automatisch freigegeben.
  Dateien: `unit_panic_loop.ogg`, `unit_burning_loop.ogg`,
  `unit_injured_loop.ogg` (Fallback stumm).
- **Zustands-Tracking:** Bitmaske `_status_fx_mask` + Frame-Stempel
  `_status_fx_seen` auf der Unit; der Renderer difft die Maske pro Frame
  (Start/Stop der Loops exakt synchron zur Optik). Einheiten, die die Welt
  verlassen, aber am Leben bleiben (Training/Garnison — bleiben im Tree!),
  werden über den stale Frame-Stempel abgeräumt (`_cleanup_departed`),
  sonst liefe deren Loop weiter.

**Verifikation:** Suite 1619 grün, Ladecheck sauber, Stresstest-Smoke 45 s
(Zauber-Dauerfeuer erzeugt Panik/Brand/Verletzte in Masse) ohne Fehler.

### Bugfix-Runde Ebene-Klippen (Nutzerreport, 2026-07-13)

Report: Nach einem Ebene-Cast mit unerreichbarer Kante (1) fliegen
Feuerbälle durch die Geländekante, (2) massiver Lag, sobald Einheiten unten
an der Klippe feststecken und oben Gegner stehen.

**1. Feuerball-Terrainkollision:** `Fireball` kennt jetzt `terrain_data`
(an allen 3 Spawn-Stellen im Firewarrior gesetzt); im Flug prüft
`_hits_terrain()` pro Tick `position.y < get_height(x,z)` → der Ball
zerschellt wirkungslos an Klippenwand/Boden statt hindurchzufliegen. Flüge
nach oben/übers Gelände bleiben frei; Alt-Tests ohne Terrain (null) sind
unberührt.

**2. Klippen-Lag — zwei Ursachen, beide in unit.gd:**
- `_mark_target_unreachable` leerte bei vollem Cache (8) den KOMPLETTEN
  Cache — standen mehr als 8 unerreichbare Gegner im Aggro-Radius,
  vergaß die Einheit alles und lief den teuersten Pfad-Call überhaupt
  (fehlschlagendes A* = Flood-Fill der gesamten erreichbaren Fläche)
  endlos neu. Fix: abgelaufene Einträge räumen, sonst den am frühesten
  ablaufenden Eintrag verdrängen — nie pauschal leeren; Cap 8 → 32.
- Neuer **Combat-Path-Fail-Cooldown** (`COMBAT_PATH_FAIL_COOLDOWN_MS`
  = 800): nach einem fehlgeschlagenen Kampf-Pfadplan meldet `_approach`
  für 0,8 s sofort „unerreichbar" statt für jeden gescannten Gegner erneut
  zu fluten → Deckel ~1,25 fehlschlagende A*/s pro Einheit, egal wie viele
  Gegner oben stehen. Normale (erfolgreiche) Pfadplanung ist unberührt.

**Tests (test_combat.gd, +4):** Klippen-Welt-Helfer (`_make_cliff_world`,
Plateau 15 m ab x=40); Feuerball von unten auf Plateau-Ziel zerschellt ohne
Schaden; Flachboden-Schuss trifft weiterhin; gefangener Krieger mit 12
unerreichbaren Gegnern (> alter Cache-Cap!) produziert ≤ 8 fehlschlagende
Pläne in 5 s (alt: einer pro 0,25-s-Scan); Cache-Eviction statt Clear-all
(Größe bleibt gedeckelt, jüngstes Ziel bleibt gemerkt). Suite **1627 grün**,
Ladecheck + Skirmish-Smoke sauber. **Nutzer ausstehend:** Original-Szenario
(Ebene + KI-Feuerkrieger) im Spiel nachstellen.

### Holz-Bugs + UI-Features (Nutzerreport, 2026-07-13)

**NavGrid-Inseln (neu):** `same_island(a,b)`/`island_at(cell)` — Connected-
Component-Labels über das begehbare Grid (4er-Nachbarschaft = konsistent zu
DIAGONAL_ONLY_IF_NO_OBSTACLES), lazy nach Walkability-Änderungen neu
berechnet, gedrosselt auf max. 1x/s (`ISLAND_REFRESH_MS`; kurz veraltete
Labels heilen sich selbst). O(1)-Erreichbarkeits-Vorfilter.

**Bug „Bäume unterhalb der Klippe bevorzugt":** Alle Holz-Zielwahlen
rankten nach Luftlinie OHNE Erreichbarkeit. Insel-Filter ergänzt in:
`Brave._nearest_claimable_tree`, `Brave._best_safe_pile`,
`Brave._nearest_own_building` (+ delivery_point), `TreeManager._nearest`
(Loose-Chop-Kette). „Holz auf dem Luftweg" = Lieferziel unerreichbar nah.

**Bug „Sammler dreht auf der Stelle":** `_tick_loose_deliver` wählte
Gebäude+Stapel JEDEN Tick neu — bei nahezu gleich weiten Zielen flippte das
Ziel pro Tick (Replan + Facing-Flip, Null-Fortschritt). Jetzt: Ziel wird
einmal pro Lieferung gewählt (`_loose_deliver_goal`), Re-Check nur alle
1,5 s und Wechsel nur, wenn das neue Ziel >= 2 m näher ist (Hysterese).

**Feature Rechtsklick auf Holzstapel:** WoodPile hat jetzt einen ClickBody
(Layer 4, meta `wood_pile`); `_dispatch_context_command` → neues
`TribeCommands.order_pickup` → `Brave.order_pickup(pile)` (Task.PICKUP im
GATHER-State, neue Routing-Zeile in `_tick_state`); Lieferung läuft über die
bestehende Loose-Deliver-Pipeline (nächstes eigenes Gebäude). Shift-Queue
wie beim Baum-Befehl.

**Feature Cursor-Zähler:** `scripts/ui/cursor_count_label.gd` (neu,
`CursorCountLabel`), folgt der Maus, zeigt die Zahl selektierter lebender
Einheiten (Polling wie die Sidebar), in main.gd unter $UI verdrahtet.

**Feature Blink-Feedback:** `Building.flash_ring()` (Tween, 2x blinken,
stellt Selektionszustand wieder her) — ausgelöst in
`_apply_building_command` für alle „Reingehen"-Befehle (Förster/Werkstatt/
Wachturm/Hütte/Training), beim Katapult-Crew-Befehl
(`SiegeEngine.flash_ring()`, temporärer Ring — Einheitenringe sind zentral
im MultiMesh) und in `_set_rally`, wenn der Rally-Punkt per zweitem Raycast
(BUILDING_MASK) auf einem Gebäude landet.

**Tests:** test_nav_grid +1 (Inseln: getrennt über Wasser, Merge nach
Landbrücke — Drossel im Test via `_islands_computed_ms` umgangen),
test_economy +1 (order_pickup: Brave holt Stapel, liefert an den Drop-Spot
der Hütte). Suite **1634 grün**, Ladecheck sauber, Stresstest-Smoke (45 s,
Terrain-Verformungen erzwingen Insel-Rebuilds) ohne Fehler.
**Nutzer ausstehend:** Original-Szenario (Ebene + Holzwirtschaft) im Spiel.

### Zustandsanzeigen konsolidiert (Nutzerwunsch, 2026-07-13)

- **Sterne = NUR noch kritischer Schaden** (<= 25 % Leben, `has_stars()`
  umdefiniert): das ursprüngliche Phase-5d-Treffer-Feedback (>=12 Schaden
  in 1 s -> 1,5 s Sterne) ist ENTFERNT (stars_until_ms/_recent_damage/
  STARS_*-Konstanten/_register_damage_for_stars raus) — es lief parallel
  zu den neuen Zustands-Icons.
- **Brennen hat Anzeige-Priorität:** unterdrückt Panik-Icon UND Sterne
  (`has_stars()` prüft `not is_burning()`; StatusFxRenderer maskiert das
  visual_mask auf FX_BURNING). Brennende Einheiten sind ohnehin implizit
  in Panik (ignite -> start_panic).
- **Verletzt-Tropfen-Icon entfernt** — der INJURED-Zustand treibt im
  StatusFxRenderer nur noch seinen Loop-Sound; die Optik übernehmen die
  Sterne (StarsRenderer, jetzt via has_stars()).
- README: effects/ nur noch panic.png + burning.png; Sterne nicht ersetzbar.
- Test umgebaut: test_stars_show_critical_damage_and_fire_priority
  (leichter Schaden keine Sterne, krit -> Sterne, brennend+krit -> keine,
  Leiche -> keine). Suite **1637 grün**, Ladecheck sauber.

### Bugfix-Pass Katapult & Feuermechanik (Nutzerbericht, 2026-07-18)

Vier zusammenhängende Bugs (Details/Soll: `bugs_backlog.md` Bug 5, behoben):

- **Katapult-Treffer auf Gebäude spillt jetzt IMMER die Lavapfütze**
  (`SiegeShot._impact()`): Einheiten am Einschlag brennen auch bei
  Gebäudetreffern. Bei Gebäudetreffern läuft die Pfütze mit
  `damage_buildings = false` (kein Doppelschaden zum Stufen-Treffer).
- **Lava beschädigt Gebäude:** neues `Building.add_lava_contact(seconds)` —
  1 Zerstörungsstufe je volle 5 s Kontakt (`Balance.LAVA_BUILDING_STAGE_TIME`),
  Reset nach 1 s ohne Kontakt (`LAVA_BUILDING_CONTACT_GRACE`, Grace tickt in
  `Building.tick`; die 1 s überbrückt die ~0,9-s-Lücke zwischen
  Vulkan-Wellen). `LavaSurge._touch_buildings()` (Kreis vs. Footprint via
  neuem `Building.footprint_distance_to`) und `LavaFlow._touch_buildings()`
  (Segmente, pro Check-Tick dedupet) melden Kontakt im 0,2-s-Takt; beide
  bekamen `building_manager`-Setup-Param + `damage_buildings`-Flag
  (Aufrufer: VolcanoZone, SiegeShot, Earthquake-Verwerfungslava).
- **VolcanoZone: Pauschalschaden ERSETZT** — `_wreck_buildings()`/
  `_stage_timer`/`Balance.VOLCANO_ZONE_STAGE_INTERVAL` entfernt;
  Gebäudeschaden nur noch über echten Lavakontakt der Surges
  (Reichweite `LAVA_REACH` = 7,5 statt Zonen-Radius 5). Zusätzlich zündet
  die Zone während der Eruption selbst kontinuierlich alle 0,2 s alle
  Einheiten im Lavabereich (`_ignite_covered_units`) — vorher ließen die
  molten-Fenster der Einzelwellen (~3,7 s je 4,5 s) Brennlücken.
- **Anti-Raider-Beschuss:** eigenes Gebäude MIT Raidern ist gültiges
  Katapultziel. `Building.has_raiders()`/`blast_raiders(damage, attacker)`
  (Raider fliegen verletzt raus — `Balance.SIEGE_SHOT_RAIDER_DAMAGE` = 30 —
  mit Roll, nehmen den Sturm danach wieder auf oder greifen an);
  `SiegeShot._building_at_impact` matcht eigene Gebäude nur mit Raidern,
  das eigene Gebäude zahlt 1 Stufe pro Treffer. `SiegeEngine` überschreibt
  `_building_target_valid()` (Fokus fällt, sobald die Raider weg sind);
  `TribeCommands.order_attack_building` lässt Katapulte gegen eigene
  Raider-Gebäude durch; UI: `SelectionManager._dispatch_own_raided_building`
  (Katapulte bombardieren, Rest der Selektion stellt sich an den
  Gebäuderand). Eigene Gebäude OHNE Raider bleiben unantastbar.

**Tests:** test_siege +4 (nicht-wreckende Pfütze bei Gebäudetreffer,
Open-Ground-Pfütze wreckt, Raider-Blast, Order-/Routing-Regeln),
test_spells: Vulkan-Kadenz-Test auf Kontaktregel umgeschrieben, +3
(Grace-Reset, damage_buildings-Flag, kontinuierliches Zünden).
Suite **1677 grün**, Ladecheck sauber.
**Nutzer ausstehend:** Spieltest der drei Szenarien (Katapult neben
feindlichem Gebäude, Vulkan an Hütte, Raider im eigenen Gebäude).

## Bugfix Backlog #1 — UI-Skalierung / Auflösung (2026-07-18)

Behebung von [bugs_backlog.md](bugs_backlog.md) Bug 1: Bei 1080p war im
Werkstatt-Panel unten die Katapult-Anzahl abgeschnitten; Zielauflösungen sind
1920×1080 und 2560×1440.

**Ursache:** `project.godot` hatte Basis 1280×800 **ohne Stretch-Mode** — das
UI skalierte nicht mit dem Fenster (die alte Notiz „Fenstergröße 1280×800" aus
Phase 6 ist damit überholt). Zusätzlich stapelte die Sidebar-VBox Tab-Content
(min. 300 px) + Gebäudepanel über die Panelhöhe hinaus.

**Umsetzung:**
- `project.godot`: Basisauflösung **1920×1080**,
  `window/stretch/mode="canvas_items"` + `aspect="expand"` — bei 1080p rendert
  das UI 1:1, bei 1440p einheitlich ×1,33 skaliert. Die Screen-Space-Logik
  (Box-Select, BuildMenu, SpellTargeting, Cursor-Label) arbeitet komplett im
  Stretch-Basisraum und bleibt konsistent.
- `scripts/core/game_settings.gd`: Auflösung persistiert nach dem
  `show_fps`-Muster (`resolution_w`/`resolution_h`, Sektion `display`,
  `user://settings.cfg`). Neu: `resolution()`, `set_resolution()`,
  `apply_resolution()` (setzt + zentriert das Fenster; No-op headless und in
  Nicht-Windowed-Modi), Konstante `RESOLUTIONS` (1920×1080, 2560×1440).
- `scripts/ui/main_menu.gd`: Optionspunkt **„Auflösung"** (OptionButton) auf
  der Optionsseite; Auswahl wendet sofort an und speichert. In `_ready()` wird
  die gespeicherte Auflösung einmalig beim Start angewendet.
- `scripts/ui/sidebar.gd`: **Kompakt-Modus des Tab-Contents** — solange ein
  Gebäude-/Crew-Panel (Förster/Werkstatt/Katapult/Wachturm) sichtbar ist,
  schrumpft die Tab-Fläche von 300 auf 120 px (`_update_tab_content_height()`,
  im `_process`-Refresh), damit die untersten Panel-Zeilen (Katapult-Stepper)
  sicher im Sichtbereich bleiben. Damit dabei nichts unerreichbar wird,
  scrollen jetzt auch **Zauber- und Gefolgsleute-Tab** in ScrollContainern
  (wie der Gebäude-Tab); `clip_contents` auf der Tab-Fläche verhindert
  Überzeichnen des Panels darunter.

**Verifikation:** Ladecheck `--headless --quit` sauber; Headless-Skirmish
(`--quit-after 600 -- skirmish=1`) fehlerfrei. Manuelle Prüfung durch Nutzer
(1080p/1440p: Werkstatt-Panel vollständig, Klicks/Box-Select korrekt)
ausstehend.

---

## Bugfix-Pass 2 (Nutzertest, 2026-07-18) — Backlog #2/#4, Wachturm-Deadlock, KI-Wegfreimachung

**Bug 2 — Baustellen durch Einheiten zerstörbar (`building.gd`):**
- Baustellen-HP-Modell: `health` startet bei `SITE_MIN_HP` (1) und wächst mit
  dem angelieferten Holz (`_grow_site_hp()` in `_absorb_piles`), Deckel
  `SITE_HP_CAP_FRACTION` (3/4 der Voll-HP = 3 von 4 Stufen). Schaden bleibt
  beim Wachstum erhalten (nur Deckel-Delta wird addiert); bei
  `finish_construction()` Übernahme ins Voll-HP-Modell (`max_health` minus
  offenem Schaden, reparierbar). `tick()` ruft `_tick_raid()` jetzt auch
  während der Bauphase auf (vorher: Raider in Baustellen machten NIE Schaden).
- Neu: `tests/test_construction_assault.gd` (17 Checks).

**Bug 4 — Holzsuche Luftlinie (`tree_manager.gd`):**
- `_nearest()` bewertet jetzt Score = Flachdistanz + `HEIGHT_DETOUR_PENALTY`
  (6,0) × |Höhendifferenz| statt reiner XZ-Luftlinie. Plateau-Fall: Baum unter
  der Klippe ist per `same_island` erreichbar (Rampe), wurde aber trotz
  Riesenumweg bevorzugt. Bewusst O(1) je Baum, kein `find_path` im Scan
  (Perf-Vorgabe Phase 8). Gilt auch für die KI (`nearest_tree`).
- Neu: `tests/test_tree_priority.gd` (11 Checks, Plateau+Rampen-Terrain).

**Bug 6 — Angriff auf bemannten Wachturm lief nie los (`building.gd`):**
- `nearest_entrance_threat()` zählte die garnisonierte Turm-Crew (geschützte
  Reserve, bleibt in der Welt registriert) als Eingangs-Bedrohung;
  `_begin_attack()` weist nicht-zielbare Ziele ab → Deadlock (Lauf-Anim im
  Stand, kein Anmarsch). Fix: nicht-zielbare Einheiten überspringen — der
  Sturm wirft die Crew normal raus, dann wird gekämpft/abgerissen.
- `test_watchtower.gd` +3 Checks (ohne Fix: „moved 0.0 m").

**KI-Wegfreimachung (Landbrücke/Absinken, `ai_controller.gd`):**
- Neu `_tick_unblock_path(target)` im ATTACK-State: Liegt das Angriffsziel auf
  einer anderen Nav-Insel (z. B. Rampe zur Basis weggezaubert), läuft die
  Schamanin an die Inselkante Richtung Ziel (`_island_edge_toward`, Sampling
  der Sichtlinie über `island_at`) und wirkt **Landbrücke** über die Lücke
  (`_bridge_cast_point`: Punkt der Gegeninsel in Castreichweite, sonst
  maximale Reichweite = Teilbrücke; jeder Cast vergrößert die Insel, bis der
  Weg verbunden ist). **Absinken** als Fallback auf erhöhte Barrieren
  (`_wall_point_toward`), mit Flut-Guard `_sink_would_flood_caster()` (der
  Smoothstep-Falloff des Sinks würde auf Küstenniveau den eigenen Boden unter
  Wasser drücken). Armee marschiert währenddessen normal weiter (Attack-Move
  sammelt sie per Partial-Path an der Kante).
- Neu: `tests/test_ai_unblock.gd` (21 Checks inkl. Ende-zu-Ende: Inseln
  verbinden sich, Pfad existiert danach).

**Sonstiges:**
- Neu `tests/run_one.gd`: Einzeldatei-Testrunner
  (`-s res://tests/run_one.gd -- res://tests/test_x.gd [methode]`).
- `test_combat_groups.gd`: `test_adjacent_fights_keep_min_distance` seedet
  jetzt wie der Drift-Test (`seed(1337)`) — beide Metrik-Tests waren im
  Suite-Kontext einmalig grenzwertig geflaked (1,16 m / 4,83 m), isoliert und
  im Wiederholungslauf stabil grün. Rest-Flakiness (Echtzeit-Throttle der
  Insel-Labels) ist bekannt, aber selten.

**Verifikation:** Suite **1731 Tests grün**, Ladecheck `--headless --quit`
sauber. Manuelle Prüfung durch Nutzer (Startmission: bemannter Wachturm;
Plateau-Karte: Holzsuche + KI-Blockade) ausstehend.

### Bug 4 Nachbesserung: pfadverifizierte Holzsuche (2026-07-18, nach Nutzertest)

Der Höhen-Malus allein reichte nicht — die **Bau-Holzsuche** lief über einen
eigenen, ungefixten Luftlinien-Scan (`Brave._nearest_claimable_tree`). Neu:
**`TreeManager.best_tree(origin, walker, radius, claimable_only, filter)`** als
zentrale Auswahl für Chop-Kette, Bau-Suche und KI — Ranking per Luftlinie +
Höhen-Malus, dann Verifikation der Top-4 per echter `find_path`-Länge mit
Early-Accept (Pfad ≈ Luftlinie → sofort nehmen; Normalfall = EIN Pfadaufruf,
12–37 µs). Läufe > 1,5 × Suchradius werden abgelehnt (Site stallt statt
Klippenlauf); unbegrenzter Radius (KI-Anker) prüft keine Pfade. Gemessen mit
`tests/benchmark_pathcost.gd` (neu) und `benchmark_earlygame`: Pfadkosten je
Fenster 157→50 ms, Ø Unit-Tick 3,75→1,95 ms, schlimmster Frame 57→53 ms —
netto schneller, weil sinnlose Klippen-Märsche und deren Pfad-Fehlversuche
entfallen. `test_tree_priority.gd` auf 15 Checks erweitert (Site-Worker-Repro).
Suite: 1735 Tests grün.

### Nutzertest-Stand Bugfix-Pass 2 (2026-07-18, Abend)

- **Holzsuche (Bug 4): vom Nutzer bestätigt funktionierend** (Plateau-Karte,
  Hütte am Rand — Arbeiter bleiben oben).
- **KI-Wegfreimachung (Landbrücke/Absinken): klappt im echten Spiel noch
  nicht gut**, reicht laut Nutzer aber erstmal. Als **Bug 7** im
  `bugs_backlog.md` vermerkt (Nachbesserung, niedrige Prio) — bekannte
  Schwachstellen: Kanten-/Castpunktwahl nur entlang der Sichtlinie, greift
  nur im ATTACK-State, kein Fortschritts-Tracking bei wiederholt
  wirkungslosen Casts, Teilbrücken brauchen viele teure Ladungen.

### UI-Komfort: Steuerungsmenü, Gebäude-Hotkeys, Angriffs-Flash + Mechanik-Doku (2026-07-18)

**Steuerungsmenü (Rebinding):**
- Neu `scripts/core/input_settings.gd` (`InputSettings`, statisch nach
  `GameSettings`-Muster): rebindbare Actions mit deutschen Labels/Kategorien,
  Persistenz **nur der Overrides** (physical keycode) in `user://settings.cfg`
  Sektion `[input]`; Anwendung beim Start via `GameState._ready()` →
  `InputSettings.apply_overrides()` (InputMap `action_erase_events` +
  `action_add_event`). Nicht rebindbar (bewusst): Maus-Actions (Code fragt
  rohe `MOUSE_BUTTON_*` ab), `ui_cancel` (Esc), Debug-F1/F2 — deren Tasten
  sind zusätzlich als Konflikt gesperrt.
- `main_menu.gd`: neue Seite „Steuerung" (Index 3, Optionen → Steuerung):
  ScrollContainer-Liste (Label + Key-Button je Action, Kategorie-Header),
  Erfassungsmodus über `_input()` (Fokus-Falle: `release_focus()`, sonst
  bindet Space/Enter den Button statt der Taste), Esc bricht ab, Konflikte
  werden mit Meldung abgelehnt (kein Auto-Swap), „Auf Standard zurücksetzen".
  `key_display_name` mappt physical→Layout nur mit echtem DisplayServer
  (Headless-Guard, sonst ERROR-Spam im Ladecheck).

**Gebäude-Typ-Hotkeys (B/K/T/J) + Mehrfach-Gebäudeselektion „light":**
- 4 neue Actions in `project.godot`: `select_all_huts` (B),
  `select_all_warrior_camps` (K), `select_all_temples` (T),
  `select_all_firewarrior_camps` (J) — kartenweite Selektion aller eigenen,
  fertigen Gebäude des Typs (kein Treffer = Selektion bleibt).
- `selection_manager.gd`: neu `selected_buildings: Array[Building]`;
  `selected_building` bleibt Primärgebäude (Sidebar-Panels unverändert).
  `_select_buildings()`/`_prune_selected_buildings()`; Rechtsklick setzt den
  Rally-Point für **alle** selektierten Gebäude. `setup()` bekommt den
  `BuildingManager` als 5. Parameter (main.gd angepasst).

**Roter Angriffs-Flash:**
- `Building.flash_ring(color := RING_COLOR)` + `ATTACK_FLASH_COLOR`; laufender
  Flash-Tween wird vor Neuanlage gekillt (kein Gold/Rot-Flackern), Farbe wird
  am Ende zurückgesetzt. Bestandsaufrufer weiter gold.
- Neu `Unit.flash_target_ring()`: kurzlebiges rotes Torus-Mesh am Ziel (Muster
  `SiegeEngine.flash_ring`), als Kind der Unit (folgt dem Ziel), Tween am Ring
  (stirbt mit dem Ziel). Aufrufe im SelectionManager nach `order_attack`,
  `order_attack_building` und Anti-Raider-Beschuss.

**Doku:** Neu `docs/game_mechanics.md` — Spielmechanik-Handbuch (Wirtschaft,
Einheiten, Zustände, Gebäude, Zerstörungsstufen, Schadenssystem, Zauber,
Steuerung), Werte aus `balance.gd` mit Quellenhinweis.

**Verifikation:** `--headless --import` + `--headless --quit` sauber (keine
Parse-/Ladefehler). Manueller Funktionstest (Rebinding, Hotkeys, roter Flash)
ausstehend.

### Balance-Nachzug: Roll-Statuseffekt-Werte zentralisiert (2026-07-18)

Die Rollen-Werte waren als einzige Statuseffekt-Werte noch in `unit.gd`
hartkodiert (Panik/Brand/Lava lagen bereits in `balance.gd`). Neu in
`balance.gd`, Sektion „ROLLEN (Statuseffekt)": `ROLL_SPEED` (5,5),
`MINI_ROLL_DURATION` (0,35), `NEIGHBOR_ROLL_DURATION` (0,22), `ROLL_DPS` (5),
`SHOVE_ROLL_CHANCE` (0,2), `STEEP_ROLL_CHANCE_PER_SEC` (0,6) — `unit.gd`
referenziert sie nach dem üblichen Muster (lokale Konstantennamen bleiben,
externe Verweise wie `Unit.MINI_ROLL_DURATION` unverändert). Interne
Physik-/Sicherheitswerte (ROLL_END_SLOPE, ROLL_FRICTION, ROLL_MAX_DURATION,
Probe-Konstanten) bleiben bewusst lokal. Suite 1735 Tests grün, Ladecheck
sauber.

### Bugfix: Katapult löschte Gebäude-Insassen unsichtbar (2026-07-18, Nutzerreport)

**Repro (Startmission):** Katapult beschießt besetzte gegnerische Försterei —
niemand wird sichtbar rausgeworfen, das Gebäude stirbt "leer".
**Ursache:** `siege_shot.gd::_kill_building_occupants` hat Förster-Arbeiter und
Trainees **still gelöscht** (aus Stamm entfernt + `queue_free`, nie in die Welt
zurückgesetzt → keine Leiche, kein Effekt sichtbar). Hütte/Werkstatt/Wachturm
waren gar nicht abgedeckt (deren Insassen flogen über den GENERIC-Pfad lebend
raus — inkonsistent zur Fernkampf-Regel).
**Fix:** Der Treffer ruft jetzt einheitlich `building.eject_occupants(true)` —
dieselbe "Fernkampf tötet Insassen an der Tür"-Regel wie Feuerkrieger-Beschuss
(`DMG_RANGED`): Insassen werden in die Welt zurückgesetzt und sterben sichtbar
als Leiche am Eingang. Gilt jetzt für alle Gebäudetypen (auch Hütten-Besatzung,
Werkstatt-Arbeiter, Wachturm-Crew). `_kill_building_occupants`/`_free_unit`
entfernt.
**Doku-Korrektur:** `docs/game_mechanics.md` §5 behauptete das Gegenteil
("Fernkampf tötet Insassen nicht") — richtiggestellt.
**Tests:** `test_bombard_building_stage_and_occupant_kill` prüft jetzt die
sichtbare Leiche statt des stillen Löschens; neu
`test_bombard_forester_kills_workers_visibly` (Ende-zu-Ende: 2 eingelagerte
Arbeiter → Beschuss → Leichen in der Welt, Slots leer). Suite 1748 Tests grün.

### Nachschärfung: tödlicher Insassen-Eject als Roll-Tod (2026-07-18, Nutzerwunsch)

Insassen, die durch Fernkampf/Katapult aus einem Gebäude geworfen werden,
sterben nicht mehr schlagartig an der Tür, sondern **rollen vom Gebäude weg
und sterben beim Ausrollen** (nutzt den bestehenden aufgeschobenen Roll-Tod:
`start_roll` vor dem tödlichen `take_damage` → `_end_roll` vollendet).
Umsetzung zentral in `Building._eject_unit` (killed-Zweig: gleicher
Schubs+Roller wie der Lebend-Eject, danach tödlicher Schaden) — gilt damit
einheitlich für Kaserne/Tempel/Feuertempel-Trainee, Förster- und
Werkstatt-Arbeiter, Hütten-Besatzung und Wachturm-Crew, sowohl beim
Feuerkrieger-Pfad (`DMG_RANGED`-Stufe-1) als auch beim Katapult-Einschlag.
Tests angepasst (5 Checks: erst ROLL, nach Ausrollen DEAD + Population),
Doku §5 aktualisiert. Suite 1753 Tests grün.

### Nachschärfung 2: Fernkampf-Rauswurf verletzt statt tötet (2026-07-18, Nutzerwunsch)

Der tödliche Insassen-Eject war zu hart (Wachturm-Crew überlebte vorher
teilweise). Neue, kalkulierbare Regel: Fernkampf-Rauswurf (Feuerkrieger-
Stufe-1, Katapult-Treffer) verursacht **1 Brave-Leben Schaden**
(`Balance.BUILDING_EJECT_RANGED_DAMAGE` = 60, neu im Balance-Sheet) plus den
normalen Rollschaden des Rausrollens. Braves/Feuerkrieger (60 HP) sterben
beim Ausrollen (aufgeschobener Roll-Tod), Krieger/Prediger/Schamanin können
verletzt überleben. Zentral in `Building._eject_unit`; gilt einheitlich für
alle Gebäudetypen und beide Beschuss-Pfade.
Tests: Wachturm-Test differenziert jetzt (Feuerkrieger stirbt, Krieger
überlebt mit −60 HP, Population −1); Brave-Insassen-Tests unverändert gültig
(60 HP → Tod). Doku §5 aktualisiert. Suite 1754 Tests grün.

### Bugfix: Brennen ohne Panik + stumme Status-Loops (2026-07-18, Nutzerreport)

**Bug 1 — brennende Einheiten ohne Panik:** `Unit.ignite()` rief `start_panic`
nur einmal beim Kontakt; `start_panic` verweigert aber bei THROWN/ROLL. Eine
Einheit, die beim Entzünden gerade flog/rollte (Feuerball-Wurf in Lava,
Vulkan), brannte danach stehend weiter und konnte sogar kämpfen. Fix:
Invariante in `_tick_burning` — solange die Einheit brennt und weder
PANIC/THROWN/ROLL/DEAD noch panik-immun ist, wird `start_panic(position,
Restbrenndauer)` nachgezogen (nach dem Ausrollen geht es sofort in Panik
weiter; Schamanin brennt weiterhin bewusst stehend). Regressionstest neu:
`test_ignited_while_rolling_panics_after_the_tumble` (test_spells.gd).

**Bug 2 — Status-Sounds nur einmalig:** Das Loop-System existiert und ist
verdrahtet (StatusFxRenderer → `AudioManager.start_loop`, positional, folgt
der Einheit, Cap 4 Emitter je Effekt, sauberes Stop bei Zustandsende/
Weltaustritt) — es erwartet aber eigene Dateien `unit_panic_loop.ogg` /
`unit_burning_loop.ogg` / `unit_injured_loop.ogg`; fehlen die, war es stumm
und nur der One-Shot beim Eintritt war hörbar. Fix: `_activate_loop` fällt
bei fehlender `<name>_loop`-Datei auf die One-Shot-Streams des Basisnamens
zurück und wiederholt sie (finished→play). Damit laufen Brennen-, Panik- und
Kritisch-verwundet-Sound kontinuierlich, solange der Zustand anhält; eigene
Loop-Dateien haben weiterhin Vorrang. Suite 1758 Tests grün.

---

## Phase 8.3 — Seenland-Früh-Lag (2026-07-19, Nutzerreport)

**Anlass:** Skirmish mit 3 KIs auf Seenland bricht nach 1–2 min auf ~14 FPS
ein, obwohl kaum Einheiten existieren (Kampfbenchmark 1600 Einheiten läuft
mit 60 FPS). Plan: Ursachenanalyse + gezielte Fixes ohne die
Phase-8-Regressionsklasse (kein globales Pfad-Budget, keine
Sim-Frequenz-Tricks; Nutzer-Vorgabe PROGRESS.md „Rückabwicklung Phase 8").

**Diagnose (gemessen, `benchmark_earlygame -- map=seenland sim=300`):**
Ø-Unit-Tick ab t=90 s bei **61–102 ms/Frame** (Budget 33 ms); Treiber:
- **A*-Fehlschlag-Sturm:** ~13.500 fehlschlagende Pfad-Läufe pro
  30-s-Fenster (≈80 s CPU je Fenster!), dominiert von Bau-Arbeitern in
  FLATTEN/DELIVER. Seenland erzeugt See+Footprint-Taschen, deren Insassen
  jeden Pfad fehlschlagen; `_end_subtask` setzte den Retry auf 0 →
  Neuwahl im 30-Hz-Takt, jeder Fehlschlag exploriert die ganze ~50k-Zellen-
  Landmasse (~6,5 ms). Der Phase-8-Schutz war mit dem Rollback weg.
- **`best_tree`-See-Entartung:** Luftlinien-Ranking wählt Gegenufer-Bäume,
  `same_island` greift nicht (eine Landmasse), Early-Accept nie → bis 4
  teure Um-den-See-A* pro Suche, bis 2,8 s je Fenster.
- **KI-Bauplatzsuche:** Wasserzellen zählten nicht gegen den 40er-
  Kandidaten-Cap → Voll-Ringscan (~3480 Zellen) ×2 (Basis+Expansion) jede
  Sekunde pro KI sobald Holz knapp; je Kandidat 400-Baum-Linearscan +
  synchroner A*; alle 3 KIs im selben Frame (kein Stagger).
- Insel-Flood-Fill (65536 Zellen, ~40 ms) bis 47×/Fenster.

**Fixes (einzeln getestet):**
1. **Retry-Backoff nur im Fehlerpfad** (`brave.gd`): `_end_subtask(retry)`;
   `_on_seek_failed`/Invalid-Baum/Invalid-Pile übergeben `TASK_RETRY`
   (0,6 s), Erfolgspfade bleiben bei 0 (Responsivität). Dazu **eskalierender
   Backoff** (Verdopplung bis `TASK_RETRY_MAX` 4,8 s, `_seek_fail_streak`,
   Reset bei Erfolg) und **Job-Aufgabe nach 6 Fehlschlägen in Folge**
   (`SEEK_FAIL_QUIT_STREAK`; Worker geht IDLE, das periodische Recruiting
   holt ihn zurück, wenn die Baustelle wieder erreichbar ist). Rein pro
   Einheit — kein geteiltes Budget/keine Queue (Phase-8-sicher).
2. **Grid-versionierter Negativ-Cache in `best_tree`**
   (`tree_manager.gd`/`nav_grid.gd`): `NavGrid.change_version` (Inkrement in
   `update_region`); Verdikte TOO_FAR (TTL 5 s) und NO_PATH (TTL 1,5 s +
   Sofort-Invalidierung bei Grid-Änderung) je (Walker-8×8-Bucket, Baumzelle).
   Positive nie gecacht. Gecachte Negative kosten kein A* und **verbrauchen
   keinen der 4 Verifikations-Slots** mehr — tiefere Kandidaten rücken nach
   (vorher blockierten 4 Gegenufer-Bäume die Suche komplett → null trotz
   erreichbarer Bäume). Lazy-Prune (Clear) ab 4096 Einträgen.
3. **KI-Tick-Stagger** (`main.gd`/`ai_controller.gd`): `stagger_offset()`
   phasenverschiebt die 1-Hz-Ticks der KIs über die Sekunde (weiter exakt
   1 Hz je KI).
4. **Baum-Bucket-Index** (`tree_manager.gd`): `_pos_buckets` (8-m-Buckets,
   gepflegt in register/_remove_tree), `count_trees_near()` exakt äquivalent
   zum Linearscan (gleicher 3D-Distanz-Term, Äquivalenztest); Nutzer:
   `_trees_near_cell`, `_wood_thin_near_base`.
5. **KI-Plot-Suche gezähmt** (`ai_controller.gd`): Zell-Scan-Cap
   `MAX_PLOT_SCAN_CELLS` 800 (Kandidaten-Cap 40 bleibt; bewusst NICHT
   can_place_at-Fehlschläge in den 40er zählen — am Ufer bräche die Suche
   nach Radius ~3 ab); Fehlschlag-Cooldown `PLOT_FAIL_COOLDOWN_TICKS` 5;
   `_expansion_anchor`-Cache (TTL 10 Ticks, invalid wenn Baum weg);
   Erfolgs-Cache `_reachable_plots` (Wert = change_version, exakt-konservativ;
   der Session-Bann `_unreachable_plots` bleibt unverändert).
6. **Insel-Flood-Fill:** gemessen 4–5 Fills/Fenster ≈ 5–6 ms/s → unter der
   10-ms/s-Schwelle, Verlagerung auf den PathWorker bewusst NICHT umgesetzt.

**Messwerkzeuge (neu):** `benchmark_earlygame` per User-Args
parametrisierbar (`-- map=seenland sim=300`, Default bergpass); statische
Zähler `TreeManager.dbg_best_tree_calls/_paths/_us`,
`NavGrid.dbg_island_fills/_us`, `AIController.dbg_plot_scans/_cells/_us`
(Ausgabe je 30-s-Fenster).

**Ergebnis (Seenland 300 s, vorher → nachher):** Ø-Unit-Tick Spitze
102 → **4,0 ms**; Pfad-Fehlschläge je Fenster 13.738 → **~200–400**;
Pfad-CPU je Fenster 89 s → 0,8–2,0 s; schlimmster Frame 279 → **89 ms**
(Einzelspike; im Spiel zusätzlich durch Stagger entschärft — das Benchmark
tickt alle 4 KIs im selben Frame). **Bergpass-Gegenprobe: unverändert
gesund** (Ø 0,8–1,5 ms). Hinweis: Im echten Spiel laufen die Unit-Pfade über
den PathWorker-Thread; die Benchmark-Zahlen sind der konservative
Sync-Fall.

**Tests:** neu `test_failed_subtask_backs_off` (+Eskalation/Quit,
test_economy), `test_count_trees_near_matches_linear_scan` (test_economy),
`test_negative_verdicts_are_cached_and_budget_moves_on` +
`test_no_path_verdict_invalidated_by_grid_change` (test_tree_priority),
`test_ai_tick_stagger`, `test_plot_search_cooldown_after_failure`,
`test_plot_search_scan_cap`, `test_plot_reachable_success_cache`,
`test_expansion_anchor_cache` (test_ai),
`test_seenland_churn_budget_and_command_response` (test_perf —
Budget-Wächter UND Phase-8-Klasse-Wächter: Move-Befehle an 20 frische
Braves müssen während des Wirtschafts-Churns sofort reagieren).

**Manuelle Prüfung durch Nutzer ausstehend:** Langzeittest Seenland-Skirmish
mit 3 KIs (10+ min, FPS-Anzeige; Erdbeben/Terrain-Verformung; Truppbefehle
müssen jederzeit sofort greifen — Phase-8-Klasse).
