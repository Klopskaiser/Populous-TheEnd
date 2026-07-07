# Phase 8.1 — Massenschlacht-FPS: 20-Hz-Sim + Render-Interpolation + Hotpath Runde 2

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).
> Fortsetzung der Performance-Arbeit aus Phase 8 ([08_performance.md](08_performance.md))
> nach Nutzertests; **Design-Review abgeschlossen**, dieser Plan ist umsetzungsreif.

## Kontext / Ausgangslage (gemessen)

Nach Schatten-Umbau, Aufholspiralen-Cap (`max_physics_steps_per_frame = 2`) und
Hotpath-Runde 1 läuft die Massenschlacht (~2200 Einheiten, Debugschlacht) bei
**6-8 FPS**. Draw-Calls 600 / Objekte 210 → Rendering ist NICHT der Engpass; der
Frame besteht aus Render + 2 × Sim-Tick (in-game ~35-45 ms je Tick; headless
gemessen: Kampf 2000 ≈ 22,7 ms/Tick). Ziel: Sim-Last pro Sekunde so weit senken,
dass wieder 1 Physikschritt pro Frame reicht → erwartet **~15-25 FPS** im
Vollkampf, außerhalb des Kampfs flüssig.

**Kernidee:** Simulation von 30 auf **20 Hz** (−33 % Sim-Last/s für Einheiten,
Separation, Hash, Pfad-Queue, Gebäude, Bäume — alles ist delta-basiert, keine
Logikänderung) und die dadurch gröberen Bewegungsschritte (0,2 m bei Speed 4)
per **prev/curr-Interpolation im Renderer** glätten.

## Dokumentierte Auslegungen (aus dem Design-Review)

- **Godots `physics/common/physics_interpolation` bleibt bewusst AUS.**
  Gründe: MultiMesh-Instanz-Transforms werden seit 4.4 mit-interpoliert und
  kollidieren mit unserem manuellen `set_instance_transform`-Pfad (Bug erst in
  4.5 gefixt, Konzeptkonflikt bleibt); `_process`-bewegte Visuals (Kamera,
  sinkende Wracks, Raid-Wobble) würden auf Tick-Snapshots quantisiert → lange
  Opt-out-Liste; 3D hat KEINEN Auto-Reset bei Spawn/Teleport
  (`reset_physics_interpolation` überall nötig). Stattdessen manuell mit
  `Engine.get_physics_interpolation_fraction()` — funktioniert unabhängig von
  der Projekteinstellung, konstante Geschwindigkeit, halber Tick Latenz.
- **prev/curr-Lerp statt exponentiellem Glätten:** exaktes Nachzeichnen der
  Sim-Bewegung ohne Gummiband-Verzug (~70-80 ms) und ohne Tuning-Parameter.
- **Akzeptierte Nebenwirkung:** Katapulte (2 m/s → 0,1-m-Schritte) und
  Projektile (Feuerball 16 m/s → 0,8-m-Schritte, kurzlebig) steppen bei 20 Hz
  sichtbar minimal — akzeptiert und nur nachzubessern, falls es im Test
  auffällt (dann: gleiches prev/curr-Muster für diese Node3D-Visuals).
- **Alternierendes Halb-Ticking (15 Hz je Einheit bei 30 Hz global) verworfen:**
  gröbere Schritte als 20 Hz, Manager-Systeme blieben bei 30 Hz, Cross-Gruppen-
  Artefakte; 20 Hz global entlastet ALLES. Falls 20 Hz später nicht reicht, ist
  der nächste Hebel LOD-Ticking (kampffreie/offscreen Einheiten mit halber
  Rate) — orthogonal zu diesem Umbau.
- Eingabelatenz steigt auf max. 50 ms — für ein RTS unkritisch.

## Deliverables / Umsetzungsschritte

### 1. 20 Hz Simulation + mitskalierte Budgets

- `project.godot`: `physics/common/physics_ticks_per_second = 20`
  (Kommentar mitpflegen; `max_physics_steps_per_frame = 2` bleibt).
- `scripts/core/unit_manager.gd` — Konstanten skalieren (Durchsatz **pro
  Sekunde** erhalten, Tick-Budget ist jetzt 50 ms):
  - `PATHS_PER_TICK` 48 → 72, `PATH_BUDGET_USEC` 4000 → 6000,
  - `SEPARATION_UNITS_PER_TICK` 450 → 675,
  - `OVERLAP_ESCAPE_PASSES` 8 → 6 (zählt Pässe, nicht Sekunden),
  - `IDLE_REGROUP_SPREAD_TICKS` bleibt (delta-korrekt).

### 2. Render-Interpolation der Einheiten (prev/curr)

- `scripts/units/unit.gd`: neues Feld `_prev_pos: Vector3` (beim
  Render-Bookkeeping neben `_render_pos`).
- `scripts/core/unit_manager.gd`: in `_physics_process` vor `unit.tick(delta)`
  `unit._prev_pos = unit.position` (Separation/Knockback laufen danach →
  zählen zur curr-Position); in `register()` initialisieren.
- `scripts/ui/unit_renderer.gd` `_process`:
  - `var f := Engine.get_physics_interpolation_fraction()`,
  - Basis = `unit._prev_pos.lerp(unit.position, f)`; **Snap** bei
    prev→curr-Distanz² > 16 (Spawn/Teleport/Gebäude-Ein-/Austritt); beim
    Registrieren/Swap-Remove `_prev_pos` mit-snappen (der bestehende
    `_render_pos = INF`-Sentinel deckt die Slots ab),
  - Sprite = Basis (+ Hop-Offset), Blob = Basis + `BLOB_Y`; weiterhin nur bei
    Änderung schreiben (stehende Einheiten: prev == curr → Early-out bleibt).
- Overlays lesen dieselbe geglättete Position (`unit._render_pos` mit
  `!= Vector3.INF`-Guard, sonst `unit.position`) — sonst stottern sie in
  20-Hz-Stufen um glatt gleitende Sprites:
  - `scripts/ui/selection_ring_renderer.gd` (Ring-Transform),
  - `scripts/ui/stars_renderer.gd` (Sterne-Anker),
  - `scripts/ui/route_visualizer.gd` (Linien-Startpunkt).
  (UnitRenderer läuft in der Tree-Reihenfolge von main.tscn VOR diesen Nodes,
  StarsRenderer wird in main.gd danach angehängt — Reihenfolge passt.)

### 3. Hotpath Runde 2 (`scripts/units/unit.gd`)

- `_apply_animation(false)` nur noch jeden **2. Tick pro Einheit** (pro Einheit
  getoggeltes Bit, Phase aus `get_instance_id() & 1`) und für `State.DEAD`
  gar nicht mehr (Leichen-Anim ändert sich nach `_set_state(DEAD)` nie;
  Massenschlachten haben hunderte Leichen).
  **Sicher**, weil `_set_state()`, `_do_strike` und `Brave._set_working`
  Animationen bei echten Übergängen weiterhin SOFORT setzen — die
  Anim-Assertions in test_combat.gd hängen alle an diesen Sofort-Pfaden
  (geprüft). Latenz trifft nur statusinterne Flips (walk↔strike) ≤ 100 ms.

### 4. Diagnose

- `scripts/ui/fps_overlay.gd`: dritte Angabe **Sim-Zeit** in ms
  (`Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0`) —
  zeigt die Dauer des letzten Physik-Schritts (bei 2 Catch-up-Steps den
  einzelnen Schritt, nicht die Summe).

### 5. Benchmarks/Tests angleichen (Kosmetik)

- `tests/benchmark_mass.gd`, `tests/benchmark_earlygame.gd`,
  `tests/test_perf.gd`: `TICK` auf `1.0 / 20.0`; „Budget ~33 ms"-Texte auf
  „~50 ms". Die test_perf-Budgets bleiben unverändert (Hz-unabhängige
  Größenordnungs-Wächter); der Pfad-Queue-Test in test_unit_logic.gd skaliert
  über die Konstante mit.

## Nicht in dieser Phase

- Godot-`physics_interpolation` (s. Auslegungen), Multithreading der Unit-Sim
  (nicht thread-safe: Ziel-Claims, take_damage, Spatial-Hash), LOD-Ticking
  (nächster Hebel falls nötig), MultiMesh-Bäume (Rendering nicht der Engpass).

## Tests / Verifikation

```powershell
$GODOT = 'C:\Users\johannes.wutzke\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe'
& $GODOT --path D:\game\Populous-TheEnd --headless --import
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/run_tests.gd   # 1499+, Exit 0
& $GODOT --path D:\game\Populous-TheEnd --headless --quit
& $GODOT --path D:\game\Populous-TheEnd --headless --quit-after 600 -- lagtest
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/benchmark_mass.gd
```

- Suite muss grün bleiben (Tests ticken mit eigenen Deltas — von der Hz-
  Umstellung unberührt).
- benchmark_mass-Kennzahlen in PROGRESS.md dokumentieren (pro Tick ähnlich,
  aber nur noch 20 Ticks/s).

## Manuelle Prüfung (Nutzer)

- Debugschlacht: FPS deutlich über 15; Sim-Zeit-Anzeige ≤ ~45 ms.
- Bewegung der Einheiten glatt (Interpolation); Auswahlringe/Sterne kleben an
  den Sprites; kein Gummiband-Effekt.
- F10-Zeitraffer funktioniert (10x/100x).
- Katapult-Fahrt und Feuerbälle auf sichtbares Stottern prüfen (akzeptierte
  Nebenwirkung — nur notieren; Fix wäre dasselbe prev/curr-Muster für diese
  Node3D).
- Skirmish Bergpass + 3 KIs + F9 gegenprüfen.

## Definition of Done

- [ ] Testsuite grün, Ladecheck + lagtest-Smoke fehlerfrei
- [ ] 20 Hz + skalierte Budgets aktiv, Einheiten-Interpolation im Renderer
- [ ] Overlays nutzen die geglättete Position
- [ ] Anim-Staffelung + DEAD-Skip
- [ ] FPS-Overlay zeigt Sim-Zeit
- [ ] PROGRESS.md ergänzt, Checkbox in [00_overview.md](00_overview.md) abgehakt
- [ ] Commit + Push
