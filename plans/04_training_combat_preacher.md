# Phase 4 — Training, Rally Points, Kampf, Prediger

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

Vollständige Einheitenpalette (außer Schamanin): Braves werden in Trainingsgebäuden zu
Kriegern, Feuerkriegern und Predigern ausgebildet und laufen danach zum Rally Point.
Kampfsystem (Nahkampf, Fernkampf mit Feuerball-Projektil, Auto-Aggro, Tod) und
Prediger-Konvertierung funktionieren gegen einen statisch vorplatzierten roten
Sparring-Stamm.

## Voraussetzungen

Phasen 1–3: Unit/Brave, UnitManager (Spatial-Hash), Building/Hut, Tribe, TribeCommands,
HUD, Bau-UI.

## Deliverables

| Datei | Inhalt |
|---|---|
| `scripts/buildings/training_building.gd` | `class_name TrainingBuilding extends Building`. `produces: PackedScene` (Zieleinheit), `training_time: float`, `queue: Array` (wartende/trainierende Braves). Ablauf in `tick`: Brave erreicht Gebäude (State TRAIN, Sprite versteckt, aus Spatial-Hash raus) → Timer → Brave wird entfernt, neue Kampfeinheit am Gebäuderand gespawnt (gleicher Tribe) → `order_move(rally_point)`. Befüllung via `TribeCommands.order_train(tribe, building, braves)` (selektierte Braves + Rechtsklick aufs Gebäude) |
| `scripts/buildings/warrior_camp.gd`, `firewarrior_camp.gd`, `temple.gd` + Szenen | Ableitungen mit jeweiliger Zieleinheit, Kosten, Trainingszeit; Placeholder-Meshes (graue Box, dunkelgraue Box mit orangem Detail, weißer Zylinder). In Bau-UI aufnehmen (deutsch: „Krieger-Trainingslager", „Feuerkrieger-Trainingslager", „Tempel") |
| `scripts/units/warrior.gd` + Szene | `class_name Warrior extends Unit`. Nahkampf: `attack_range` klein, `attack_damage`, `attack_cooldown`; ATTACK-State: Ziel verfolgen, in Reichweite zuschlagen (Attack-Animation) |
| `scripts/units/firewarrior.gd` + `scripts/units/fireball.gd` + Szenen | Fernkampf: größere Range, spawnt `Fireball` (`Node3D`, oranges SphereMesh unshaded, fliegt geradlinig/leichter Bogen zum Ziel, Treffer = Distanzcheck im `tick`, dann Schaden + Despawn) |
| `scripts/units/preacher.gd` + Szene | `class_name Preacher extends Unit`. Konvertierung statt Schaden: Ziel in Range halten (Cast-Animation), `conversion_progress` pro Ziel hochticken → bei 1.0 wechselt Ziel den Tribe (Tribe-Listen umhängen, `modulate`-Farbe wechseln, laufende Befehle abbrechen). Konvertiert keine Schamanin, keine anderen Prediger (Original-Regel, hält Balance einfach) |
| Kampfsystem in `unit.gd`/`unit_manager.gd` | Zielsuche via Spatial-Hash (`get_units_in_radius`), **per Timer alle 0.2–0.3 s mit Zufalls-Offset**, nie pro Frame. Auto-Aggro: Kampfeinheiten im IDLE greifen Feinde im Aggro-Radius an; Braves fliehen stattdessen Richtung eigener Basis. `take_damage()` → bei 0 HP State DEAD, `Events.unit_died`, Despawn + Deregistrierung (Tribe, UnitManager, Selektion) |
| Rally-Point-UI | Selektiertes Gebäude + Rechtsklick aufs Terrain → `rally_point` setzen (Basisklassen-Property, gilt für ALLE Gebäude inkl. Hütte); sichtbare Fahne (kleines Mesh) am Rally Point des selektierten Gebäudes |
| Sparring-Setup in `main.gd` | Roter Tribe (id 1) statisch vorplatziert: Hütte, Krieger-Lager, ein paar Krieger/Braves auf der anderen Inselseite — noch ohne KI-Controller (Phase 6) |
| `tests/test_training.gd`, `tests/test_combat.gd` | siehe Tests unten |

## Umsetzungsschritte

1. Kampf-Grundlagen in `unit.gd`: `take_damage`, Tod/Despawn, Zielsuche-Timer; dann
   `warrior.gd` (Nahkampf) — `test_combat.gd` (Nahkampfteil) grün.
2. `training_building.gd` + `order_train` in TribeCommands + Warrior-Camp;
   `test_training.gd` grün.
3. `firewarrior.gd` + `fireball.gd` (Projektil-Tick, Treffer, Schaden).
4. `preacher.gd` + Tempel (Konvertierungslogik inkl. Tribe-Wechsel).
5. Rally-Point-UI + Fahne; neue Einheiten laufen zum Rally Point.
6. Auto-Aggro + Brave-Flucht; Sparring-Basis in `main.gd`.
7. Verifikation + manuelle Prüfung + Commit/Push.

## Tests

`tests/test_training.gd`:
- `order_train` schickt Brave zum Gebäude; nach `training_time` Ticks existiert eine
  neue Kampfeinheit desselben Tribes, der Brave ist weg (Population konstant ±0,
  Einheitentyp gewechselt).
- Neue Einheit hat Bewegungsziel = `rally_point` des Gebäudes.
- Rally-Point-Änderung wirkt für danach fertige Einheiten.
- Training ohne wartende Braves produziert nichts; Queue arbeitet FIFO mehrere Braves ab.

`tests/test_combat.gd`:
- Schadensrechnung: `take_damage` reduziert HP; bei ≤0 → DEAD, `unit_died` gefeuert,
  Einheit aus Tribe-Liste und Spatial-Hash entfernt.
- Nahkampf-Tick: Warrior + Feind in Range → nach `attack_cooldown`-Ticks hat Feind
  Schaden; außer Range → Warrior bewegt sich zum Ziel.
- Fireball: fliegt getickt zum Ziel, wendet Schaden genau einmal an, despawnt.
- Auto-Aggro: Feind im Aggro-Radius → IDLE-Warrior wechselt in ATTACK; Brave wechselt
  nicht in ATTACK (flieht).
- Konvertierung: Preacher + Feind-Brave in Range ticken → `conversion_progress` steigt;
  bei 1.0 ist die Einheit in `tribes[0].units` statt `tribes[1].units`, `tribe_id`
  gewechselt; Prediger/Schamanin als Ziel → kein Fortschritt.

```powershell
$GODOT = 'C:\Users\johannes.wutzke\Downloads\Godot_v4.7-stable_win64.exe'
& $GODOT --path D:\game\Populous-TheEnd --headless --import
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/run_tests.gd   # Exit-Code 0
& $GODOT --path D:\game\Populous-TheEnd --headless --quit
```

## Manuelle Prüfung

- Krieger-Lager bauen, Braves reinschicken → Krieger kommen raus und laufen zur
  Rally-Fahne; Rally Point per Rechtsklick versetzen funktioniert (auch bei Hütten).
- Krieger zur roten Basis schicken: Nahkampf mit Attack-Animation, rote Einheiten sterben.
- Feuerkrieger: sichtbare Feuerbälle auf Distanz.
- Prediger: rote Einheit wird nach einigen Sekunden blau und ist selektierbar.
- Rote Krieger greifen von selbst an, wenn man in ihren Aggro-Radius läuft; eigene
  Braves fliehen vor Feinden.

## Definition of Done

- [ ] Testsuite grün, `--headless --quit` fehlerfrei
- [ ] Manuelle Prüfung bestanden
- [ ] Checkbox Phase 4 in [00_overview.md](00_overview.md) abgehakt
- [ ] `git add -A && git commit -m "Phase 4: Training, Kampf, Prediger, Rally Points" && git push`
