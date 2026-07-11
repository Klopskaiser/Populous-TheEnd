# Phase 8.1 — Performance-Neuanlauf: Parallelisierung (Multi-Core)

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).
> Neuanlauf nach der Phase-8-Rückabwicklung (siehe PROGRESS.md „Rückabwicklung");
> Machbarkeits-Recherche (Godot-4.7-Doku + GitHub-Issues) abgeschlossen —
> dieser Plan ist umsetzungsreif. Der alte 20-Hz-Plan
> [08a_sim_20hz_interpolation.md](08a_sim_20hz_interpolation.md) bleibt verworfen.

## Kontext / Ausgangslage

Nutzer-Idee: mehrere CPU-Kerne nutzen, insbesondere für die Wegfindung.
Einordnung an den Phase-8-Messungen (headless, 2000 Einheiten, 30 Hz):

| Kostenstelle | Ø pro Tick | Parallelisierbar? |
|---|---|---|
| Einheiten-Loop (Zielsuche, Slots, Bewegung, Worker-Logik) | ~34 ms (Kampf) | nur mit Daten-Umbau (Stufe C, Ausblick) |
| Separation | ~9 ms | zweiphasig (Stufe B) |
| Spatial-Hash-Refresh | ~2,5 ms | kaum lohnend |
| Wegfindung A* (Normalbetrieb) | ~0,3–2 ms | ja — im Schnitt klein |
| Wegfindung **Spikes** (Erdbeben, Massenbefehle, fehlschlagende Pfade) | 50–400 ms Einzel-Frames | **ja — Haupt-Gewinn Stufe A** |

**Erwartung (ehrlich):** Stufe A beseitigt die Spike-Frames und macht den
Phase-8-Rückstau-Bug (Einheiten „ignorieren Befehle", Laufanimation ohne
Bewegung) strukturell unmöglich — der Main-Thread rechnet keine Pfade mehr,
und es braucht kein Durchsatz-Limit pro Tick. Die Dauer-FPS im Vollkampf
steigt erst mit Stufe B moderat; der große Einheiten-Loop bleibt seriell
(echte Parallelisierung dafür = Stufe C, nur Ausblick).

**Verbindliche Nutzer-Vorgaben:** akkurate 30-Hz-Simulation (keine
Frequenz-/Genauigkeits-Tricks); Änderungen einzeln einführen und mit
Langzeittests absichern (Lehre aus der Wegfindungs-Regression).

## Dokumentierte Auslegungen (Recherche-Fakten, Godot 4.7)

- **GDScript-Threads laufen echt parallel** (kein GIL). Kanonisches Muster:
  `Thread` + `Mutex` + `Semaphore` (Producer/Consumer); `call_deferred` als
  Rückkanal in den Main-Thread.
  [Thread-safe APIs](https://docs.godotengine.org/en/4.4/tutorials/performance/thread_safe_apis.html)
- **AStarGrid2D ist NICHT thread-safe auf derselben Instanz** (Doku-Warnung an
  `get_point_path`; `get_id_path` läuft durch dieselbe `_solve()`-Routine —
  [Issue #19311](https://github.com/godotengine/godot/issues/19311)). Muster:
  **ein Grid-Klon pro Worker-Thread**. `AStarGrid2D.update()` nur einmal beim
  Aufbau (löscht ALLE Solidity-/Weight-Daten!), danach nur Deltas per
  `set_point_solid`.
- **Szenenbaum-/Node-Zugriff aus Worker-Threads ist nicht supported** — auch
  `Node3D.position` setzen nicht. Erlaubt ist paralleles Lesen/Schreiben von
  Elementen **vordimensionierter** Packed-Arrays an festen Indizes („anything
  that changes the container size requires locking a mutex"); Vorsicht
  COW-Kopien.
- **RefCounted-Objekte nicht zwischen Threads teilen/zuweisen**
  ([Issue #86194](https://github.com/godotengine/godot/issues/86194):
  Variant/Ref-Assignment ist nicht atomar) → über Threads nur POD-Daten und
  **instance_id** (int) transportieren.
- **WorkerThreadPool.add_group_task** skaliert für Massen-Updates; grobe
  Chunks wählen (Overhead pro Task), jede Group MUSS gewartet werden
  (`wait_for_group_task_completion`), nie aus einem Task heraus warten.
- **Globales `randf()` ist in Threads unsafe** (eine globale RandomPCG ohne
  Lock) — Worker-Code ohne RNG schreiben (oder eigene
  RandomNumberGenerator-Instanz pro Thread).
- **Verworfen:**
  - `rendering/driver/threads/thread_model = separate`: offiziell „several
    known bugs" in 4.x (schwarzer Bildschirm Vulkan Forward+
    [#98284](https://github.com/godotengine/godot/issues/98284), Glitches
    #87239, Leaks #87382, Crash #61650) — nicht als tragende Optimierung
    einplanen.
  - `physics/3d/run_on_separate_thread`: nutzlos für uns —
    `_physics_process`-Skripte laufen nachweislich weiter auf dem Main-Thread
    ([#104085](https://github.com/godotengine/godot/issues/104085)); das
    Setting verlagert nur die PhysicsServer-Simulation, die wir nicht nutzen.
  - 20-Hz-Sim: Nutzerentscheid (08a).

## Stufe A — Pfad-Worker-Thread (Kern-Deliverable)

Neues `scripts/core/path_worker.gd` (Node oder RefCounted, von Main erzeugt):

- **Ein langlebiger `Thread`**, `Mutex` + `Semaphore`, **EINE gemischte
  FIFO-Queue** für zwei Nachrichtenarten:
  1. **Grid-Delta-Kommandos** (Zellen + solid-Flags),
  2. **Pfad-Anfragen**.
  Die gemeinsame FIFO garantiert: Terrain-Änderungen wirken auf alle SPÄTER
  gestellten Anfragen (keine Pfade auf veraltetem Grid-Stand nach dem Delta).
- **Worker hält eigene AStarGrid2D-Klone** (Unit-Grid + Vehicle-Grid).
  Initialaufbau: `update()` einmal, dann kompletter Solid-Sync vom Main-Grid.
  Vehicle-Passierbarkeit leitet der Worker lokal aus seinem Unit-Klon ab
  (Logik aus `NavGrid._refresh_vehicle_region`/`_vehicle_passable`
  wiederverwenden) — spart Delta-Verkehr.
- **`NavGrid` bleibt Single Source of Truth im Main-Thread:**
  `update_region`/`fill_solid_region` berechnen die Solid-Flags wie heute auf
  dem Main-Grid (inkl. TerrainData-Zugriff) und schicken sie zusätzlich als
  kompakte Deltas (PackedInt32Array Zellindizes + PackedByteArray solid) an
  den Worker. **Der Worker liest NIE TerrainData** (heights mutieren im Main).
- **Anfrage/Antwort nur mit POD-Daten:** Anfrage = {instance_id, request_id,
  from-Zelle, Ziel-Welt-Punkt, vehicle-Flag}; Antwort = {instance_id,
  request_id, **Zell-Pfad** (PackedVector2Array)}. Die Welt-/Y-Konvertierung
  (`TerrainData.get_height`, „letzter Punkt = exakter Klickpunkt"-Regel aus
  `NavGrid.find_path`) macht der **Main-Thread beim Anwenden**. Snap-Logik
  (`nearest_walkable_cell`) läuft im Worker auf dessen Klon.
- **Integration an der bestehenden Naht:** `Unit._pending_target`/
  `_path_queued`/`_resolve_pending_path`-Mechanik bleibt konzeptionell;
  `UnitManager._drain_path_queue` reicht neue Anfragen an den Worker durch
  und wendet pro Tick **alle** fertigen Antworten an (Anwenden ist billig) —
  **kein Pro-Tick-Limit, kein Zeitbudget → Rückstau strukturell unmöglich.**
  Veraltete Antworten werden verworfen: pro Einheit laufender
  `request_id`-Zähler (neuer Befehl invalidiert), plus
  `instance_from_id` + `is_instance_valid` + State-Guard beim Anwenden
  (wie heute in `_resolve_pending_path`).
- **Headless/Tests unverändert:** ohne Worker (`path_service == null` bzw.
  Worker nicht gestartet) exakt das heutige synchrone Verhalten;
  `NavGrid.find_path` bleibt für alle synchronen Callsites
  (`_approach`, `_seek`, SiegeEngine-Vehicle-Pfade, Tests) unangetastet.
  In-Game-Schalter (z. B. Konstante/Setting) für A/B-Vergleich und als
  Notfall-Fallback.
- **Kein `randf()` im Worker-Code.** Sauberer Shutdown: Stop-Flag setzen,
  `Semaphore.post()`, `Thread.wait_to_finish()` in `_exit_tree`.

## Stufe B — Separation-Fan-out (messgesteuert, erst nach stabiler Stufe A)

- Zweiphasig: **parallel rechnen, seriell anwenden.**
  1. Main-Thread spiegelt vor dem Fan-out Positionen + Hash-Bucket-Inhalte in
     **vordimensionierte** Packed-Arrays (index-basiert, keine Objekt-Refs).
  2. `WorkerThreadPool.add_group_task` berechnet Push-Vektoren in groben
     Chunks (z. B. 250–500 Einheiten je Task); jeder Task schreibt NUR an
     seine festen Indizes eines vorab dimensionierten Ergebnis-Arrays.
  3. Main-Thread wendet seriell an (Walkability-Check + Y-Snap wie heute in
     `UnitManager._apply_separation`).
- Separation nutzt kein `randf()` (deterministische Richtung über
  instance_id) — thread-tauglich.
- **Go/No-Go:** nur übernehmen, wenn die Messung bei 2000+ Einheiten
  > ~4 ms/Tick Gewinn zeigt UND Suite + Langzeitlauf grün sind; sonst
  dokumentiert verwerfen (Aufwand/Nutzen).

## Stufe C — nur Ausblick (NICHT Teil dieser Phase)

Data-oriented Unit-Loop: Positionen/Kernzustände in Packed-Arrays, Node3D nur
noch Hülle, Entscheidungsphasen als WorkerThreadPool-Group-Tasks
(decide-parallel/apply-seriell). Einziger Weg, die ~34 ms Einheiten-Logik echt
über Kerne zu skalieren — großer Umbau, erst wenn A+B ausgereizt und stabil.

## Tests

- Bestehende Suite bleibt vollständig grün (synchroner Pfad unverändert).
- **Neue Funktionstests (Stufe A, mit laufendem Worker):**
  - Pfad-Anfrage wird asynchron beantwortet, Einheit läuft los;
  - Grid-Delta vor Folge-Anfrage: Pfad respektiert die Änderung
    (Landbridge-/Blockade-Fall);
  - veralteter Request (neuer Befehl vor Antwort) wird verworfen;
  - unerreichbares Ziel → Einheit wird IDLE (wie synchron);
  - Shutdown ohne Hänger/Leaks (Runner beendet sauber).
- **Langzeit-Wächter gegen die Regression-Klasse** (headless KI-Lauf, z. B.
  2500+ Frames bergpass wie in 7i): Assertion „keine lebende Einheit steht
  länger als X s (z. B. 10 s) in MOVE mit leerem Pfad und offener Anfrage";
  zusätzlich Erdbeben-/Massenbefehl-Szenario simulieren.
- benchmark_mass um Worker-A/B-Vergleich ergänzen (Spike-Kennzahl:
  schlimmster Tick mit/ohne Worker bei Massenbefehl auf 256er-Karte).

```powershell
$GODOT = 'C:\Users\johannes.wutzke\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe'
& $GODOT --path D:\game\Populous-TheEnd --headless --import
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/run_tests.gd   # Exit 0
& $GODOT --path D:\game\Populous-TheEnd --headless --quit
& $GODOT --path D:\game\Populous-TheEnd --headless --quit-after 600 -- lagtest
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/benchmark_mass.gd
```

## Manuelle Prüfung (Nutzer)

- Langes Skirmish (Bergpass, 3 KIs): Einheiten folgen Befehlen dauerhaft —
  auch nach Erdbeben/Terrain-Verformung; KI-Wellen verlassen die Basis.
- Massenbefehl an viele Einheiten auf der 256er-Karte: kein Spike-Frame
  (FPS-/Draw-Call-Anzeige beobachten).
- Debugschlacht: Frame-Zeiten gleichmäßiger; Dauer-FPS-Erwartung realistisch
  (Stufe A glättet, Stufe B bringt moderat mehr).
- F10-Zeitraffer und Speichern/Beenden (sauberer Thread-Shutdown) prüfen.

## Definition of Done

- [ ] Stufe A umgesetzt: PathWorker + NavGrid-Deltas + UnitManager-Integration,
      A/B-Schalter, sauberer Shutdown
- [ ] Neue Funktionstests + Langzeit-Wächter in der Suite, alles grün
- [ ] Ladecheck + lagtest-Smoke fehlerfrei
- [ ] benchmark_mass-A/B-Kennzahlen dokumentiert (v. a. Spike-Verhalten)
- [ ] Stufe B gemessen und übernommen ODER dokumentiert verworfen
- [ ] PROGRESS.md ergänzt, Checkbox Phase 8.1 in [00_overview.md](00_overview.md)
      abgehakt, Commit + Push
