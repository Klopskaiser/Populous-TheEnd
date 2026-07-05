# Phase 2 — Pathfinding, Unit-Basis, Selektion & Bewegung

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

Einheiten (vorerst nur Braves) können gespawnt, per Klick/Box-Select selektiert und per
Rechtsklick über die Insel bewegt werden. Wasser und steile Hänge blockieren. Wegpunkt-
Routen (einmalig und Patrouille) funktionieren. Grundlage: Grid-Pathfinding (`NavGrid`)
und die `Unit`-Basisklasse, auf der alle späteren Einheitentypen aufbauen.

## Voraussetzungen

Phase 1 abgeschlossen: `TerrainData` (`get_height`, `is_walkable`, `raise_area`),
`Terrain`-Szene, `CameraRig`, Testrunner.

## Deliverables

| Datei | Inhalt |
|---|---|
| `scripts/core/nav_grid.gd` | `class_name NavGrid extends RefCounted`. Kapselt `AStarGrid2D` (Größe = Terrain-Zellen, `DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES`). Init aus TerrainData (`set_point_solid` für nicht begehbare Zellen). API: `find_path(from: Vector3, to: Vector3) -> PackedVector3Array` (Y aus `TerrainData.get_height()`; Ziel unbegehbar → nächstgelegene begehbare Zelle), `update_region(rect: Rect2i)` (Walkability der Zellen neu aus TerrainData lesen), `fill_solid_region(rect: Rect2i, solid: bool)` (für Gebäude-Footprints ab Phase 3), `world_to_cell()`/`cell_to_world()` |
| `scripts/units/unit.gd` | `class_name Unit extends Node3D`. Properties: `tribe_id: int`, `max_health/health: int`, `speed: float`, `state: State` (`enum State {IDLE, MOVE, GATHER, PRAY, BUILD, ATTACK, TRAIN, PANIC, CAST, THROWN, DEAD}` — spätere Phasen füllen die Verhalten), `waypoint_queue: Array[Vector3]`, `patrol: bool`. Kernlogik in `tick(delta)` (von `_physics_process` aufgerufen — Testbarkeits-Regel!): Pfad abschreiten per `move_toward`, Y-Snapping via TerrainData, bei Pfadende nächsten Wegpunkt ziehen (Patrouille: Queue rotieren). API: `order_move(target: Vector3, queue_up: bool)`, `set_path(path: PackedVector3Array)`, `take_damage(amount: int)` (Gerüst), Signale `died(unit)`, `state_changed` |
| `scripts/units/brave.gd` + `scenes/units/brave.tscn` | `class_name Brave extends Unit` (Verhalten GATHER/PRAY/BUILD kommt in Phase 3 — hier nur Typ, Werte, Sprite) |
| `scripts/core/unit_manager.gd` | `class_name UnitManager extends Node` (Kind von Main). Registry aller Einheiten, **Spatial-Hash** (`Dictionary[Vector2i, Array]`, Zellgröße ~4 m, Update im `tick`), API: `register/unregister(unit)`, `get_units_in_radius(pos: Vector3, radius: float) -> Array[Unit]`, `get_units_of_tribe(tribe_id) -> Array[Unit]`, `spawn_unit(scene: PackedScene, tribe_id: int, pos: Vector3) -> Unit` |
| `scripts/ui/placeholder_sprites.gd` | `class_name PlaceholderSprites`. Statische Fabrik: `make_frames(unit_kind: StringName) -> SpriteFrames` — Animationen `idle/walk/attack/cast` aus `Image.create(16, 24, ...)` + `fill_rect`-Pixelmustern (Walk: Beine alternierend usw.). Aufruf NUR aus `_ready()` von Szenen (headless-Regel). Stammfarbe macht die Unit selbst via `modulate` |
| `scripts/ui/selection_manager.gd` (+ Control-Node in main.tscn) | Klick-Selektion (nächste eigene Einheit im Pixelradius via `camera.unproject_position`), Box-Select (Drag-Rect zeichnen in `Control._draw()`, Auswahl per `rect.has_point(unproject)` + `is_position_behind()`-Guard), Selektionsringe (flacher Torus/Quad unter der Einheit, `no_depth_test`), Rechtsklick → Terrain-Raycast → `order_move` an Selektion (vorerst direkt; ab Phase 3 via TribeCommands), Shift+Rechtsklick → Wegpunkt anhängen. Formation: Zielpunkte leicht streuen, damit Einheiten nicht stapeln |
| `scripts/core/main.gd` (erweitert) | Erzeugt NavGrid aus TerrainData, spawnt 10 Test-Braves (Tribe 0/Blau) auf begehbaren Zellen |
| `tests/test_nav_grid.gd`, `tests/test_unit_logic.gd` | siehe Tests unten |

## Umsetzungsschritte

1. `nav_grid.gd` implementieren + `test_nav_grid.gd` grün bekommen (reine Logik, kein Node).
2. `unit.gd` mit `tick(delta)`-Bewegung; `test_unit_logic.gd` grün bekommen (Unit lässt
   sich außerhalb des Szenenbaums instanziieren, TerrainData/Pfad injizieren).
3. `placeholder_sprites.gd` + `brave.tscn` (AnimatedSprite3D, `BILLBOARD_ENABLED`,
   `shaded=false`, `alpha_cut=ALPHA_CUT_DISCARD`); Walk-Animation an `state` koppeln.
4. `unit_manager.gd` (Spatial-Hash), Spawn der Test-Braves in `main.gd`.
5. `selection_manager.gd`: erst Einzelklick, dann Box-Select + Zeichnung, dann
   Rechtsklick-Bewegung + Shift-Wegpunkte + Patrouillen-Toggle (z. B. Taste P setzt
   `patrol` der Selektion).
6. Verifikation + manuelle Prüfung + Commit/Push.

## Tests

`tests/test_nav_grid.gd`:
- Pfad zwischen zwei Landzellen existiert und alle Pfadzellen sind begehbar.
- Ziel im Wasser → Pfad endet auf nächstgelegener begehbarer Zelle (kein leerer Pfad).
- Wasser trennt zwei Landmassen → kein direkter Pfad; nach
  `terrain_data.raise_area()` über die Wasserstraße + `nav_grid.update_region(rect)`
  existiert ein Pfad (Landbridge-Vorbereitung!).
- `fill_solid_region()` blockiert Zellen → Pfad umgeht sie; wieder freigeben → direkter Pfad.

`tests/test_unit_logic.gd`:
- Unit folgt gesetztem Pfad: nach genügend `tick(delta)`-Aufrufen ist `global_position`
  am Ziel (Toleranz), `state` wieder IDLE.
- Y-Snapping: Position.y entspricht `TerrainData.get_height()` an der XZ-Position.
- Wegpunkt-Queue: 3 Wegpunkte werden in Reihenfolge abgelaufen; `patrol = true` →
  nach dem letzten Wegpunkt geht es wieder zum ersten (Queue-Länge bleibt konstant).
- Spatial-Hash: `get_units_in_radius()` findet genau die Einheiten im Radius
  (Stichproben innerhalb/außerhalb).

```powershell
$GODOT = 'C:\Users\johannes.wutzke\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe'
& $GODOT --path D:\game\Populous-TheEnd --headless --import
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/run_tests.gd   # Exit-Code 0
& $GODOT --path D:\game\Populous-TheEnd --headless --quit
```

## Manuelle Prüfung

- 10 blaue Braves stehen auf der Insel, Billboard-Sprites drehen sich zur Kamera.
- Einzelklick selektiert eine Einheit (Ring sichtbar), Box-Select mehrere, Klick ins
  Leere deselektiert.
- Rechtsklick bewegt die Selektion (Walk-Animation läuft, Einheiten stapeln nicht exakt).
- Rechtsklick ins Wasser: Einheiten laufen bis an den Strand, nicht ins Wasser.
- Shift+Rechtsklick-Kette wird als Route abgelaufen; Patrouille wiederholt die Route.

## Definition of Done

- [ ] Testsuite grün, `--headless --quit` fehlerfrei
- [ ] Manuelle Prüfung bestanden
- [ ] Checkbox Phase 2 in [00_overview.md](00_overview.md) abgehakt
- [ ] `git add -A && git commit -m "Phase 2: Pathfinding, Units, Selektion & Bewegung" && git push`
