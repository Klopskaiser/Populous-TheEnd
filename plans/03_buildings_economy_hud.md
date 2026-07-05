# Phase 3 — Gebäude, Wirtschaft (Holz, Hütten, Mana), HUD

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

Der Wirtschaftskreislauf läuft: Hütten platzieren (kostet Holz), Hütten spawnen Braves bis
zum Bevölkerungslimit, Braves sammeln Holz von wilden Bäumen und generieren durch Beten
Mana-Bonus, Mana skaliert mit der Bevölkerung. Dazu die tragenden Kernklassen `Tribe` und
`TribeCommands` (einzige Mutations-API — gilt ab jetzt strikt) sowie das deutsche HUD.

## Voraussetzungen

Phasen 1–2: TerrainData, NavGrid (`fill_solid_region`), Unit/Brave, UnitManager,
SelectionManager.

## Deliverables

| Datei | Inhalt |
|---|---|
| `scripts/core/tribe.gd` | `class_name Tribe extends RefCounted`. `id: int`, `color: Color`, `wood: int`, `mana: float`, `units: Array[Unit]`, `buildings: Array[Building]`, `shaman` (ab Phase 5). Abgeleitet: `population` (units.size()), `housing_capacity` (Summe Hütten-Kapazität), `praying_braves`. `tick(delta)`: `mana += (population * BASE_RATE + praying_braves * PRAY_BONUS) * delta` (Konstanten vorerst hier, ab Phase 7 in balance.gd). Signale via Events-Bus (`wood_changed`, `mana_changed`) |
| `scripts/core/tribe_commands.gd` | `class_name TribeCommands`. **Einzige Mutations-API** (statische Funktionen oder Node unter Main mit Referenzen auf NavGrid/UnitManager/BuildingManager): `place_building(tribe, building_scene, cell) -> Building` (prüft Holzkosten + Footprint-Walkability + frei; zieht Holz ab, reserviert NavGrid-Zellen), `order_move(units, target)`, `order_gather(units, tree)`, `order_train(...)` (Phase 4), `cast_spell(...)` (Phase 5). Ungültig → `null`/false, ohne Seiteneffekt |
| `scripts/core/game_state.gd` (erweitert) | Verwaltet `tribes: Array[Tribe]` (2 Stück: 0 = Spieler/Blau, 1 = KI/Rot), tickt Tribes in `_process` |
| `scripts/buildings/building.gd` | `class_name Building extends Node3D`. `tribe_id`, `max_health/health`, `wood_cost: int`, `footprint: Vector2i` (Zellen), `rally_point: Vector3`, Bauzustand (`under_construction`, `build_progress` — Braves im BUILD-State treiben ihn voran). Bei Platzierung: Y aus TerrainData, `nav_grid.fill_solid_region(footprint_rect, true)`; bei Zerstörung wieder freigeben + `Events.building_destroyed`. StaticBody3D + BoxShape für Klick-Selektion (eigener Layer). `tick(delta)` für Subklassen-Logik |
| `scripts/buildings/hut.gd` + `scenes/buildings/hut.tscn` | `class_name Hut extends Building`. `capacity := 100`. Spawn-Logik in `tick`: solange `tribe.population < tribe.housing_capacity`, Spawn-Timer runterzählen → Brave am Gebäuderand spawnen, `order_move` zum `rally_point` |
| `scripts/buildings/reincarnation_site.gd` + Szene | `class_name ReincarnationSite extends Building`. In dieser Phase: Platzierungsort + **Gebetsplatz** (Braves im PRAY-State in der Nähe zählen als `praying_braves`). Respawn-Logik folgt in Phase 5 |
| `scripts/core/tree_resource.gd` + `scenes/tree_resource.tscn` | `class_name TreeResource extends Node3D`. `wood_remaining: int`; `harvest(amount) -> int` liefert tatsächlich entnommenes Holz; leer → Baum verschwindet (Zelle im NavGrid wieder frei, falls blockiert). Main verteilt beim Start N Bäume auf begehbare Zellen (Seed-basiert). Registry im `BuildingManager` oder eigenem `TreeManager`-Node für `nearest_tree(pos)` |
| `scripts/units/brave.gd` (erweitert) | GATHER: nächsten Baum suchen → hinlaufen → hacken (Timer im `tick`) → Holz via TribeCommands/Tribe gutschreiben → nächster Baum. PRAY: zum Reinkarnationsplatz laufen, dort beten (zählt für Mana-Bonus). BUILD: zu Baustelle laufen, `build_progress` treiben. Kommandos über UI: selektierte Braves + Rechtsklick auf Baum → GATHER, auf Baustelle → BUILD, auf Reinkarnationsplatz → PRAY |
| `scripts/ui/build_menu.gd` + Ghost-Preview | Bau-UI (deutsch: „Hütte" — weitere Gebäude Phase 4): Button/Hotkey → Ghost-Mesh folgt Maus-Raycast, grün/rot je nach Gültigkeit (Walkability + frei + genug Holz), Linksklick platziert via `TribeCommands.place_building`, Esc bricht ab |
| `scenes/ui/hud.tscn` + `scripts/ui/hud.gd` | HUD (deutsch): „Holz: n", „Mana: n", „Bevölkerung: x/y". Aktualisierung über Events-Signale, kein Polling |
| `tests/test_economy.gd` | siehe Tests unten |

## Umsetzungsschritte

1. `tribe.gd` + `game_state.gd`-Erweiterung; Mana-Formel über `tick(delta)`.
2. `building.gd`-Basisklasse + `hut.tscn` (brauner PrismMesh + Stammfarben-Fahne);
   NavGrid-Footprint-Reservierung.
3. `tribe_commands.gd` mit `place_building` (Kosten-/Platzprüfung) — ab jetzt laufen
   **alle** Mutationen über diese Klasse (UI in Phase 3, KI in Phase 6).
4. Bäume + Brave-GATHER, dann PRAY (Reinkarnationsplatz), dann BUILD (Bauzustand).
5. Hütten-Spawn-Logik (Timer in `tick`, Kapazitätslimit).
6. Ghost-Preview-Platzierung + HUD.
7. Verifikation + manuelle Prüfung + Commit/Push.

## Tests (`tests/test_economy.gd`)

- **Mana-Formel:** Tribe mit p Einheiten, davon b betend: nach `tick(1.0)` ist
  `mana == p * BASE_RATE + b * PRAY_BONUS` (float-Toleranz); mehr Bevölkerung → mehr Mana.
- **Holzabbau:** `TreeResource.harvest()` reduziert `wood_remaining`, liefert nie mehr als
  vorhanden; Brave-GATHER-Zyklus (getickt) schreibt Holz dem Tribe gut; leerer Baum
  meldet sich ab.
- **Hütten-Spawn:** Hütte mit gemocktem Tribe ticken → nach Spawn-Intervall existiert ein
  Brave; bei `population >= housing_capacity` spawnt nichts mehr; neue Hütte erhöht
  Kapazität → Spawn geht weiter.
- **place_building:** genug Holz → Gebäude platziert, Holz um `wood_cost` reduziert,
  Footprint-Zellen im NavGrid solid; zu wenig Holz → `null`, Holz unverändert;
  Footprint auf Wasser/besetzter Zelle → `null`.
- **Baufortschritt:** Gebäude startet `under_construction`; Brave-BUILD-Ticks treiben
  `build_progress` auf 1.0 → Gebäude aktiv (Hütte spawnt erst danach).

```powershell
$GODOT = 'C:\Users\johannes.wutzke\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe'
& $GODOT --path D:\game\Populous-TheEnd --headless --import
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/run_tests.gd   # Exit-Code 0
& $GODOT --path D:\game\Populous-TheEnd --headless --quit
```

## Manuelle Prüfung

- HUD zeigt „Holz/Mana/Bevölkerung" und aktualisiert sich live.
- Hütte per Ghost-Preview platzieren (rot auf Wasser/zu wenig Holz, grün sonst);
  Braves bauen sie fertig; danach spawnen periodisch neue Braves.
- Selektierte Braves + Rechtsklick auf Baum: laufen hin, hacken, Holz steigt; Baum
  verschwindet irgendwann.
- Braves zum Reinkarnationsplatz schicken → Mana steigt schneller.
- Einheiten laufen um platzierte Gebäude herum (Footprint blockiert).

## Definition of Done

- [ ] Testsuite grün, `--headless --quit` fehlerfrei
- [ ] Manuelle Prüfung bestanden
- [ ] Checkbox Phase 3 in [00_overview.md](00_overview.md) abgehakt
- [ ] `git add -A && git commit -m "Phase 3: Gebäude, Wirtschaft, HUD" && git push`
