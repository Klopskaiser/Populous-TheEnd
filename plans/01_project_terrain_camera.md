# Phase 1 — Projektgerüst, verformbares Terrain, RTS-Kamera

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

Startbares Godot-Projekt mit prozedural generierter Insel (Heightmap-Terrain, zur Laufzeit
verformbar), Wasserebene und frei drehbarer RTS-Kamera. Fundament für alles Weitere:
`TerrainData` ist die Single Source of Truth für Höhen, Begehbarkeit und spätere
Verformung (Landbridge). Außerdem steht ab dieser Phase der Headless-Testrunner.

## Voraussetzungen

Keine (erste Phase). Projektverzeichnis enthält nur CLAUDE.md, plans\ und Git-Setup.

## Deliverables

| Datei | Inhalt |
|---|---|
| `project.godot` | Godot-4.7-Projekt. Hauptszene `res://scenes/main.tscn`. Autoloads: `GameState` (`res://scripts/core/game_state.gd`), `Events` (`res://scripts/core/events.gd`). Input-Map: `camera_forward/back/left/right` (WASD), `camera_rotate_left/right` (Q/E), `select` (LMB), `command` (RMB), `add_waypoint` (Shift+RMB als Modifier-Prüfung im Code) |
| `icon.svg` | Standard-Godot-Icon (von Godot beim Import erzeugt) oder simples eigenes SVG |
| `scripts/core/events.gd` | Signal-Bus (vorerst leer bis auf Signal-Deklarationen, wächst in späteren Phasen) |
| `scripts/core/game_state.gd` | Autoload-Gerüst (Tribes-Array kommt in Phase 3; hier nur Grundstruktur + Referenz auf TerrainData/NavGrid-Zugriffspunkte) |
| `scripts/core/terrain_data.gd` | `class_name TerrainData extends RefCounted`. `PackedFloat32Array heights` (129×129 Vertices, 128×128 Zellen, 1.0 m Raster), `sea_level`-Konstante. API: `get_height(world_x: float, world_z: float) -> float` (bilinear), `set_vertex_height(x: int, z: int, h: float)`, `raise_area(center: Vector2, radius: float, amount: float) -> Rect2i` (Smoothstep-Falloff), `is_walkable(cell: Vector2i) -> bool` (Höhe > sea_level, Hangneigung < Schwellwert), `generate_island(seed: int)` (FastNoiseLite + radialer Falloff → Insel mit Wasser außen) |
| `scripts/core/terrain.gd` + `scenes/terrain.tscn` | `class_name Terrain extends Node3D`. Baut aus TerrainData chunked ArrayMesh (16×16-Zellen-Chunks als MeshInstance3D-Kinder, Vertex-Farben nach Höhe: Sand/Gras/Fels), `StaticBody3D` + `HeightMapShape3D` (map_data aus heights, Body um `(size/2, 0, size/2)` versetzt — Shape ist origin-zentriert!), Wasserebene als `PlaneMesh` auf `sea_level` (halbtransparent blau). Methoden: `rebuild_chunks(rect: Rect2i)`, `update_collision()`, `apply_deformation(rect: Rect2i)` (ruft beide) |
| `scripts/core/camera_rig.gd` + Node-Setup in main.tscn | `class_name CameraRig extends Node3D`: Yaw-Node → Pitch-Node → Camera3D. WASD-Pan (kamerarelativ), Edge-Scroll, Mausrad-Zoom (Boom-Distanz geklemmt), Q/E-Rotation, Rig-Y an `TerrainData.get_height()` geklemmt |
| `scenes/main.tscn` + `scripts/core/main.gd` | Wurzelszene: Terrain, CameraRig, DirectionalLight3D, WorldEnvironment. `main.gd` erzeugt TerrainData (fester Seed), initialisiert Terrain. Muss **headless-robust** sein (kein Zugriff auf Viewport-Texturen in `_ready()`) |
| `tests/run_tests.gd` | Testrunner: `extends SceneTree`, lädt alle `res://tests/test_*.gd`, ruft `test_*`-Methoden per Reflection, Ausgabe pro Test, `quit(0)`/`quit(1)` (siehe Overview §Test-Strategie) |
| `tests/test_base.gd` | `class_name TestBase extends RefCounted` mit `check(cond: bool, msg: String)`, Fehlerliste, `passed/failed`-Zähler |
| `tests/test_terrain.gd` | siehe Tests unten |

## Umsetzungsschritte

1. `project.godot` + Ordnerstruktur (`scenes\`, `scripts\core\`, `tests\`, `assets\`) anlegen;
   einmal `--headless --import` laufen lassen (erzeugt `.godot\` und `.uid`-Dateien).
2. `terrain_data.gd` implementieren (reine Datenklasse, keine Node-Abhängigkeit — wichtig
   für Headless-Tests). Insel-Generierung: FastNoiseLite-Höhen × radialem Falloff, so dass
   der Rand sicher unter `sea_level` liegt.
3. Testrunner + `test_base.gd` + `test_terrain.gd` schreiben, Tests grün bekommen
   (Terrain-Mathe zuerst absichern, bevor Rendering dazukommt).
4. `terrain.gd`/`terrain.tscn`: Chunk-Meshes aus TerrainData bauen
   (`ArrayMesh.add_surface_from_arrays` mit VERTEX/NORMAL/COLOR/INDEX), HeightMapShape3D,
   Wasser-Plane.
5. `camera_rig.gd` + Input-Map; `main.tscn` zusammensetzen.
6. Verifikation (unten) + manuelle Prüfung + Commit/Push.

## Tests (`tests/test_terrain.gd`)

- `get_height()` liefert an Vertex-Positionen exakt den gesetzten Wert; zwischen Vertices
  korrekt bilinear interpoliert (bekannte Eckwerte → Mittelpunkt = Mittelwert).
- `raise_area()` hebt das Zentrum um ~`amount`, Randbereich weniger (Falloff monoton),
  außerhalb des Radius unverändert; zurückgegebenes `Rect2i` umschließt alle geänderten
  Zellen und nicht (wesentlich) mehr.
- `is_walkable()`: Zelle unter `sea_level` → false; nach `raise_area()` über `sea_level`
  → true (das ist der Landbridge-Kern!); steile Kante (großer Höhensprung) → false.
- `generate_island(seed)`: deterministisch bei gleichem Seed; Randzellen alle unter
  `sea_level`; es existiert eine zusammenhängend begehbare Landfläche (> N Zellen).

```powershell
$GODOT = 'C:\Users\johannes.wutzke\Downloads\Godot_v4.7-stable_win64.exe'
& $GODOT --path D:\game\Populous-TheEnd --headless --import
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/run_tests.gd   # Exit-Code 0
& $GODOT --path D:\game\Populous-TheEnd --headless --quit                        # keine Fehler im Output
```

## Manuelle Prüfung

`& $GODOT --path D:\game\Populous-TheEnd` starten:
- Insel mit Sand-/Gras-/Felsfärbung und Wasser rundherum sichtbar.
- WASD-Pan, Edge-Scroll, Q/E-Rotation, Mausrad-Zoom funktionieren; Kamera bleibt über dem Boden.
- HeightMapShape3D-Offset-Check: temporär bei Linksklick einen Marker (kleines SphereMesh)
  an der Raycast-Trefferposition spawnen — Marker muss exakt unter dem Cursor liegen
  (Risiko 1 aus Overview). Marker-Code danach wieder entfernen oder als Debug-Flag lassen.

## Definition of Done

- [ ] Testsuite grün (Exit-Code 0), `--headless --quit` fehlerfrei
- [ ] Manuelle Prüfung bestanden (inkl. Raycast-Offset-Check)
- [ ] Checkbox Phase 1 in [00_overview.md](00_overview.md) abgehakt
- [ ] `git add -A && git commit -m "Phase 1: Projektgerüst, Terrain, Kamera" && git push`
