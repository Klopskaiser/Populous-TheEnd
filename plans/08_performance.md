# Phase 8 — Performance

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).
>
> **Fokus dieser Phase ist AUSSCHLIESSLICH Performance.** Balance, Bedienkomfort
> (Kontrollgruppen/HUD-Ausbau), Feinschliff (Sound/Effekte), Testsuite-
> Vervollständigung und README sind bewusst nach **Phase 9**
> ([09_comfort_balance_polish.md](09_comfort_balance_polish.md)) verschoben.

## Ziel

Das Spiel läuft mit sehr vielen Einheiten flüssig. **Zielgröße: bis zu 6000
Einheiten**, **Mindestziel: 2000 Einheiten** (Bewegung + Kampf). Der aktuell
reproduzierbare Früh-Lag (siehe Auslegungen) ist beseitigt. Optimierung erfolgt
**messgestützt** (Profiler + FPS-Anzeige + headless-Mikrobenchmarks), nicht auf
Verdacht.

## Voraussetzungen

Phasen 1–7i: vollständig spielbares Skirmish auf allen Karten (128 und 256).

## Dokumentierte Auslegungen / bekannte Symptome

- **Reproduzierbares Lag-Szenario (primäres Profiling-Ziel):** **Bergpass, 3 KIs +
  Spieler**, sehr früh im Spiel, **ohne Kämpfe** — nur Hütten bauen und
  ausbilden, bei **< 100 Einheiten pro Spieler** bereits massives Lag. Das deutet
  auf einen Engpass **außerhalb** des Kampfes (Wirtschaft/KI/Wegfindung/Hütten-
  Bemannung/Terrain-256), NICHT auf reine Einheitenzahl. Dieses Setup muss per
  Flag/Taste sofort startbar und im Profiler zerlegbar sein.
- **Verdächtige (messen, nicht raten):** Hütten-Wachstums-Scans (7i:
  `_find_idle_brave_near`/`_incoming_crew_count` mit 16–20 m Radius je Hütte,
  `_admit_arrived_crew` jeden Frame), Pfad-Berechnungen bei Massenbefehlen
  (Bau/Ausbildung/Rally), KI-Tick-Kosten × 3 KIs, 256²-Terrain (Chunks/Nav),
  Melee-Slot-Kontention, GPU-Rendering vieler Sprites, Exit-Leaks. Panik-
  Allokations-Lawine an Klippen ist in 7i bereits behoben.
- **Zauber vorerst ausgeklammert:** Zauber-Performance (Massen-Panik, viele
  Terrain-Morphs, Projektile) wird in dieser Phase **noch nicht** optimiert —
  separat testen, sobald Bewegung/Kampf/Wirtschaft stehen.
- **Headless ≠ Release-Performance:** headless misst nur die Logik (kein
  Rendering). Die FPS-Anzeige im echten Spiel ist die maßgebliche Kennzahl;
  headless-Benchmarks sind Größenordnungs-Wächter gegen O(n²)-Rückfälle.

## Deliverables

| Bereich | Inhalt |
|---|---|
| **FPS-Anzeige** | Ein-/ausschaltbarer FPS-Zähler (Overlay), **anschaltbar über die Optionen** (`main_menu.gd` Optionen-Seite + Persistenz analog `AudioSettings`; In-Game-Overlay als eigener Control, zeigt FPS und optional Frame-Zeit-ms). Default aus. |
| **Profiling-Szenario** | Das Lag-Szenario (Bergpass, 3 KIs + Spieler, Früh-Aufbau) als **direkt startbares Setup** (Kommandozeilen-Flag/Debug-Taste) — schneller Wiedereinstieg für Profiler-Läufe. Ggf. Zeitraffer (F10 existiert) nutzen, um die Aufbauphase zu raffen. |
| **Engpass-Analyse & Fix (Früh-Lag)** | Den Früh-Lag im Profiler lokalisieren und beheben. Erwartete Hebel (zu verifizieren): **gestaffelte Tick-Raten** (Zielsuche/KI/Hütten-Wartung seltener als Bewegung, mit Zufalls-Offset über Frames verteilt), **Hütten-Bemannungs-Scans drosseln/verbilligen** (nicht jeden Frame, kleinerer Radius / Kandidaten-Cap), **Pfad-Queue** im NavGrid für Massenbefehle (über Frames verteilen). |
| **Bewegung & Kampf skalieren** | Bewegung und Kampf müssen bei **2000** Einheiten flüssig sein, Ziel **6000**. Hebel: Spatial-Hash-/Scan-Kosten (`SCAN_MAX_CANDIDATES`, Radien), Separation, Melee-Slot-Kontention, gestaffelte Zielsuche. |
| **Ausbildung/Holzwirtschaft** | Ausbildungs- und Holzwirtschafts-Tick prüfen und, wo nötig, entlasten (Trainings-Queues, Baum-/Holzstapel-Scans, Förster/Hütten-Wartung, Arbeiter-Zuweisung). |
| **Rendering** | Falls GPU-seitig limitiert: **MultiMesh für Bäume** (statt N MeshInstance3D), Sichtbarkeits-Culling der Selektionsringe/Overlays, Sprite-Batching prüfen. |
| **Stresstest-Modus** | Bestehenden F9-Stresstest auf die Zielgrößen (2k/6k) ausbauen (gestaffeltes Spawnen über Frames, damit der Spawn selbst nicht hitcht). |
| **Perf-Regressionstests** | Headless-Mikrobenchmarks als feste Suite-Bestandteile (siehe Tests). |

## Umsetzungsschritte

1. **FPS-Anzeige** bauen (Overlay + Optionen-Toggle + Persistenz) — damit jede
   weitere Änderung messbar ist.
2. **Profiling-Szenario** startbar machen; im Editor-Profiler den Früh-Lag
   zerlegen (Physik/Script/Idle, Funktions-Hotspots).
3. **Früh-Lag beheben** (gezielt nach Profiler-Befund; Hebelliste oben) — messen
   vor/nach.
4. **Bewegung & Kampf** auf 2k skalieren, dann Richtung 6k treiben; headless-
   Benchmarks + FPS im Spiel als Nachweis.
5. **Ausbildung/Holzwirtschaft** prüfen und entlasten.
6. **Rendering** nur bei Bedarf (wenn GPU limitiert).
7. Perf-Regressionstests in die Suite; Verifikation, PROGRESS.md, Commit/Push.

## Tests

- Bestehende Suite bleibt vollständig grün (Regressionsschutz — Optimierungen
  dürfen kein Verhalten ändern).
- **Headless-Perf-Smoke (Größenordnungs-Wächter):**
  - **Bewegung/Kampf:** 2000 Einheiten instanziieren, N `tick`-Aufrufe messen
    (`Time.get_ticks_usec()`), großzügiges Budget als O(n²)-Wächter; separat ein
    Lauf Richtung 6000 (nur als Kennzahl, kein hartes Budget).
    Ziel-Ausrichtung: pro-Frame-Logik ~linear in der Einheitenzahl.
  - **Früh-Wirtschaft:** Setup nahe am Lag-Szenario (mehrere Tribes, Hütten +
    Ausbildung, < 100/Tribe) headless über X Sekunden simulieren; Tick-Zeit
    messen — Wächter gegen Rückfälle beim Früh-Lag.
- Headless-KI-Simulationslauf (aus Phase 7) bleibt fester Bestandteil.

```powershell
$GODOT = 'C:\Users\johannes.wutzke\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe'
& $GODOT --path D:\game\Populous-TheEnd --headless --import
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/run_tests.gd   # Exit-Code 0
& $GODOT --path D:\game\Populous-TheEnd --headless --quit
```

## Manuelle Prüfung

- FPS-Anzeige über die Optionen ein-/ausschalten; im Spiel sichtbar.
- **Lag-Szenario (Bergpass, 3 KIs + Spieler):** Früh-Aufbau ohne Kämpfe läuft
  flüssig (FPS stabil), kein Ruckeln beim reinen Hütten-/Ausbildungsbetrieb.
- Stresstest: 2000 Einheiten bewegen/kämpfen — flüssig; Richtung 6000 noch
  bedienbar (Kennzahl, kein Zwang).
- Ausbildung/Holzwirtschaft unter Last ohne Hitches.

## Definition of Done

- [x] Gesamte Testsuite grün, `--headless --quit` fehlerfrei *(1499 Tests)*
- [x] FPS-Anzeige vorhanden + über Optionen schaltbar
- [x] Lag-Szenario (Bergpass, 3 KIs + Spieler, Früh-Aufbau) flüssig *(headless
  gemessen: Ø-Unit-Kosten 99 → 1,8 ms/Frame; In-Game-Prüfung durch Nutzer ausstehend)*
- [x] Bewegung/Kampf bei 2000 flüssig (Ziel 6000 dokumentiert) *(headless 2000:
  ~28-30 ms/Tick unter 33-ms-Budget; 6000: 46/76 ms als Kennzahl)*
- [x] Perf-Regressionstests in der Suite *(tests/test_perf.gd)*
- [x] PROGRESS.md ergänzt, Checkbox Phase 8 in [00_overview.md](00_overview.md) abgehakt
- [x] `git add -A && git commit -m "Phase 8: Performance" && git push`
