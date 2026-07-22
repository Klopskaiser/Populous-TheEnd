# Phase 8.d — Kampf-Performance: Stufe C (data-oriented / SoA)

> Fortsetzung der Performance-Phase (siehe [08_performance.md](08_performance.md),
> [08b_parallelization.md](08b_parallelization.md),
> [08c_combat_groups_reachability.md](08c_combat_groups_reachability.md)).
> Verifikations-Befehle: [00_overview.md](00_overview.md). Ist-Stand & Messwerte:
> [PROGRESS.md](PROGRESS.md).

## Ziel

Große Schlachten flüssiger. Konkret: die **Debugschlacht** (~1800 Einheiten, 70 %
Krieger + Feuerkrieger/Prediger + Fahrzeuge) am Höhepunkt auf **≥ 30 FPS**
(Ist ~20; Referenzrechner 60 FPS vor Kontakt → ~12–20 FPS im Nah-+Fernkampf).
Kein hartes FPS-Cap nötig — eine deutliche, messbare Verbesserung (~+50 %).

## Ausgangslage (gemessen, nicht geraten)

Der Engpass ist die **CPU-units-Phase** pro 30-Hz-Sim-Tick, **nicht** Rendering
oder Terrain. Die Engine ist bereits stark optimiert: ein MultiMesh = ein
Draw-Call, keine Physik-Bodies, keine Schatten auf Einheiten, keine Partikel,
Spatial-Hash statt `Area3D`, gedrosselte Zielsuche, Combat-Group-Bindung,
off-thread Pfad-Worker (Stufe A), fixe 30 Hz mit 2-Step-Catch-up-Cap.

**Baseline (Zielmaschine, `benchmark_mass` headless, Budget ~33 ms/Tick, Kampf-Fenster):**

| Szenario | Ø Kampf-Fenster | schlimmster Tick | units | sep | hash |
|---|---|---|---|---|---|
| schlacht krieger 2×1000 | 24,6 ms | 47 ms | 17,2 | 7,2 | 1,6 |
| schlacht feuerkrieger 2×1000 | 28,7 ms | 41 ms | 19,8 | 5,6 | 1,6 |
| schlacht krieger+prediger 2×1000 | 30,0 ms | 49 ms | 21,5 | 7,8 | 1,6 |

**Granulare Zerlegung der units-Phase (Zeit pro State im Kampf-Fenster):**

| State | Anzahl | µs/Einheit | ms/Tick |
|---|---|---|---|
| **ATTACK** | ~1150 | ~10 | **11–13** (Löwenanteil) |
| **CAST** (Prediger-Konversion) | ~120 | ~36 | 4,5 (nur im Prediger-Mix) |
| MOVE | ~150 | ~12 | ~2 |
| DEAD (nach Leichen-Opt) | ~250–690 | ~0,6 | 0,2 |

**Kernbefund:** Die ~10 µs/Einheit im ATTACK-State sind **kein einzelner fetter
Hotspot**, sondern die diffusen GDScript-Kosten der Kampf-Choreografie
(Methoden-Dispatch über ~2000 Node3D-Objekte). Micro-Opts sind ausgereizt.

## Bisherige Erkenntnisse — was gemessen wurde (2026-07-20)

**UMGESETZT & behalten:**
- **Leichen-Early-out** (`unit.gd tick()`): tote Einheiten laufen pro Tick nur
  noch `_tick_dead` (Verwesungstimer); die Todes-Pose wird einmalig in `_die()`
  gesetzt. combat 2000/4000 units-Phase **−24/−25 %**, Schlacht-Fenster −1 bis
  −2 ms; skaliert mit Sterberate/Schlachtdauer. In-Game ~+2 FPS. Sicher, kein
  Balance-Effekt.

**GEMESSEN & VERWORFEN (nicht erneut versuchen):**
- **Chase-A\* auf den Pfad-Worker auslagern:** Die synchrone Verfolgungs-A\* ist
  nur ~1,5 ms/Tick (~7 % der units-Phase). Async-Auslagerung führt Pfad-
  Verspätung ein → langsamere Konvergenz → Einheiten länger im teuren
  Verfolgungs-Zustand → units-Phase **steigt** (fw-Fenster 29 → 32 ms). Netto
  negativ.
- **Sub-Tick-Guards** (regen/burning/knockback nur bei Bedarf aufrufen): kein
  messbarer Effekt — Kämpfer sind meist verletzt/geschubst, die Aufrufe laufen
  doch.
- **ATTACK-Neubewertungs-Drossel** (Ziel/Gruppe/Reichweite nur alle 0,15 s prüfen):
  im reinen Krieger-Szenario **kein Gewinn** (22,8 → 23,4 ms), weil die wenigsten
  ATTACK-Einheiten stabile Nahkampf-Schläger sind (die meisten warten/positionieren
  sich am Ring und laufen weiter voll) — plus Kampf-Feel-Risiko.
- **C0 „Render-Slicing" (`status_fx_renderer` pro Frame slicen):** verworfen. Der
  Loop-Sound-/Icon-Zustand hängt am Voll-Scan pro Frame (nicht sauber slicebar),
  und der Physik-Tick (~30 ms) ist der FPS-Begrenzer bei 30 Hz — ~1–2 ms Render-
  Ersparnis bewegen die Schlacht kaum.

**Bindende Lehre aus Stufe B** ([08b](08b_parallelization.md), PROGRESS „Stufe B"):
Jede „Objektfelder pro Tick in Arrays spiegeln"-Variante scheitert am
**O(n)-Snapshot** (~11 ms bei 6000 in GDScript, ~0,9 µs je Array-Schreibzugriff).
→ **Die Arrays müssen autoritativ sein — kein Per-Tick-Spiegeln.** Erst dann ist
der fertige Separation-Fan-out aus Commit `305f73a` sinnvoll wiederverwendbar.

**Schlussfolgerung:** Der zuverlässige +50 % kommt nur strukturell — Einheiten-
Hotdaten in Packed-Arrays, heiße Schleifen als flache Kernels statt Objekt-Tick.
Das ist die projekteigene „Stufe C".

## Designprinzipien (Stufe C)

1. **Arrays autoritativ für die heißen Schleifen.** `UnitManager` hält parallele
   `PackedFloat32Array`/`PackedInt32Array` für Position (`_px,_pz,_py`) und die in
   Schleifen gelesenen Flags. **Kein Per-Tick-Snapshot.**
2. **Doppelschreiben statt Spiegeln.** Positions-Schreiber schreiben BEIDES (Array
   + `Node3D.position`), nur dort wo ohnehin geschrieben wird (bewegte Einheiten)
   — kein O(n)-Lauf. So bleiben die ~404 kalten `.position`-Lesestellen und der
   Renderer unverändert gültig.
3. **Event-getriebene Flags brauchen keinen Tick-Sync.** `state`, `flies`,
   `push_immune`, `vehicle_separation`, `tribe_id` ändern sich nur bei Events →
   Array-Schreibung an der Event-Stelle (`_set_state` u. a.), nicht pro Tick.
4. **Index-Muster aus dem Renderer wiederverwenden.** `_idx` je Unit, append bei
   register, **swap-remove** bei unregister (bewährt in `unit_renderer.gd:192-229`).
   `_idx` (alle Einheiten) ≠ `_render_index` (nur Sprites).
5. **Eine Quelle pro Scan.** Ein Scan liest Position UND state/tribe **entweder**
   aus Arrays **oder** aus Objekten — nie gemischt (sonst Geister-Ziele).

## Etappen (jede einzeln messbar, grün, rückrollbar — Reihenfolge = De-Risking)

### C1 — Array-Fundament + Separation/Hash als Kernels
De-Risking-Sequenz (jeder Schritt gegen Benchmark + Suite verifizieren):
1. **Writer-Set vollständig sperren (KRITISCH, zuerst):** alle Unit-Positions-
   Schreiber auditieren — inkl. der externen in `watchtower.gd:214`,
   `airship.gd:325-337/509`, `crewed_vehicle.gd` `_tick_crew`,
   `tornado_vortex.gd:205`, `terrain_morph.gd:76`. Jeder betrifft Einheiten, die
   noch in `units` stehen (Turm-/Fahrzeug-Crew, Geworfene) und MUSS doppelschreiben
   — eine Lücke → Kampf zielt auf veraltete Positionen (Geister-Ziele).
2. **`_idx`-Verwaltung** (register/unregister/`remove_from_world`) nach dem
   Renderer-Muster; Debug-Assert der `_idx`-Integrität pro Tick. Dictionary-Hash
   vorerst behalten. **Beachten:** Einheiten, die leben aber NICHT in `units`
   sind (Hütten-/Förster-/Werkstatt-/Trainings-Reserve, Turm-Crew bleibt in
   `units`!) — Asymmetrie `enter_garrison` (bleibt) vs `enter_hut` (raus).
3. **Doppelschreiben** der Position an allen Sites aus (1); Flags an ihren
   Event-Stellen in Arrays. `_set_state` (`unit.gd:2880`) ist der einzige
   `state`-Schreiber → sauberer Mirror-Punkt.
4. **Hash → CSR-Bucket-Grid** (Counting-Sort aus `_px/_pz`, kosaken-Stil), ersetzt
   `Dictionary[_hash]` + `_move_hash_cell` + `_hash_cell`. `_apply_separation` +
   Scans (`get_enemy_candidates`, `get_units_in_radius`) auf Arrays umstellen
   (eine Quelle, Prinzip 5).
5. **Test-Harness mitziehen:** `benchmark_mass._simulate` ruft `_update_hash_cell`
   manuell (`tests/benchmark_mass.gd:185-201`) — bricht sonst; ebenso
   `diag_8_2.gd`, `test_combat_groups.gd` prüfen.
6. **Optional C1.5 — Separation parallelisieren:** der fertige Fan-out aus Commit
   `305f73a` ist mit autoritativen Arrays ohne Snapshot direkt wiederverwendbar
   (inkl. der Workarounds Push-Lockstep/Escape-Churn). Nur wenn der serielle
   Array-Pfad die Ziel-ms nicht bringt.

**Erwarteter Gewinn C1:** Separation + Hash von ~7–11 ms grob halbiert →
**~4–5 ms/Tick**. Risiko: mittel-hoch (Doppelschreib-Vollständigkeit;
Geister-Ziele bei Lücken). Berührt NICHT die 11–13 ms ATTACK.

### C2 — Kampf-Kernel data-oriented (die eigentliche Masse)
Die ATTACK-Bulk (11–13 ms) als flache Kernels über Arrays (`target_idx`,
`group_id`, `_attack_cooldown`, Position) statt `unit.tick()`-Dispatch.
**Nicht uniform** — mehrere Kernels: Basis-Melee, Feuerkrieger-Fernkampf,
Prediger-CAST (36 µs/U!), Schamane-CAST, Brave-Arbeiter, Fahrzeug. Sehr großer,
hochriskanter Umbau. **Wird erst nach C1-Messung als eigener Detailplan
ausgearbeitet** — falls C1 die 30 FPS nicht erreicht.

## Go/No-Go-Tore
- **Nach C1:** Benchmark + In-Game (FPS-Overlay Debugschlacht) messen. Bringt das
  Array-Fundament weniger als erwartet oder ist die Doppelschreib-Fläche zu
  fehleranfällig → stoppen/neu bewerten, **bevor** C2 (der teure Teil) beginnt.
- **In-Game maßgeblich:** headless misst kein Rendering; die FPS-Anzeige im echten
  Spiel entscheidet.

## Kritische Dateien
- `scripts/core/unit_manager.gd` — Arrays, `_idx`, CSR-Grid, Passes.
- `scripts/units/unit.gd` — `_idx`, `_set_state`-Flag-Write, Positions-
  Doppelschreiben, Scan-Quelle.
- Externe Positions-Schreiber: `scripts/buildings/watchtower.gd`,
  `scripts/units/airship.gd`, `scripts/units/crewed_vehicle.gd`,
  `scripts/spells/tornado_vortex.gd`, `scripts/spells/terrain_morph.gd`.
- `scripts/ui/unit_renderer.gd` (Index-Vorlage).
- `tests/benchmark_mass.gd` (+ `diag_8_2.gd`, `test_combat_groups.gd`) — Harness-Sync.

## Verifikation (nach JEDEM Schritt)
- Headless-Benchmark: `& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/benchmark_mass.gd`
  → Kampf-Fenster + schlimmster Tick gegen die Baseline oben.
  Zielwerte: Kampf-Fenster **< ~22 ms** (aktuell ~30), schlimmster Tick **< ~33 ms**.
- Regressionssuite `res://tests/run_tests.gd` **grün** halten (bes.
  `test_combat`, `test_combat_groups`, `test_nav_grid`, `test_path_worker`,
  `test_siege`, `test_conversion_targeting`, `test_watchtower`, `test_airship`).
  Achtung: `test_combat` enthält RNG-Anteile (Priester-Duell) — mehrfach laufen.
- Ladecheck `--headless --quit` sauber.
- **In-Game:** Debugschlacht, FPS-Overlay am Höhepunkt; zusätzlich Stacking,
  Konversion, Turm-/Fahrzeug-Crew und geworfene Einheiten visuell prüfen (die
  Doppelschreib-Risikostellen).
