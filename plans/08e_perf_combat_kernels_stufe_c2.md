# Phase 8.e — Kampf-Kernels data-oriented (Stufe C2)

> Fortsetzung von [08d_perf_soa_stufe_c.md](08d_perf_soa_stufe_c.md) (Stufe C1,
> umgesetzt 2026-07-22, Tag 0.9.5). Verifikations-Befehle: [00_overview.md](00_overview.md).
> Ist-Stand & Messwerte: [PROGRESS.md](PROGRESS.md).

## Ziel

**Stresstest (4 Armeen × ~1025 Einheiten + Zauber-Salve) auf ≥ 30 FPS** am
Höhepunkt (Ist auf dem Referenzrechner: ~10 FPS). Die Debugschlacht läuft nach
C1 bereits mit ~50 FPS — der Stresstest ist ~2,2× größer und 4-parteiig.

## Ausgangslage (gemessen 2026-07-22, `benchmark_stress` + `diag_stress_battle`)

**Der Sim-Tick am Stresstest-Höhepunkt kostet ~50–58 ms** (headless, ~2600–3500
lebend). In-game: > 33 ms/Tick → 2-Step-Catch-up → ~100 ms/Frame ≈ 10 FPS. ✓
Für 30 FPS muss der Peak-Tick auf **≤ ~28 ms** (1 Physik-Step + Rendering).

**Zerlegung des Peaks (t300–449, Ø 57 ms inkl. Mess-Overhead):**

| Block | ms/Tick | µs/Einheit × n |
|---|---|---|
| **warrior/ATTACK** | **20,6** | 12,9 × 1600 |
| **firewarrior/ATTACK** | **9,4** | 14,5 × 650 |
| MOVE (alle Typen) | ~6,0 | ~10 × 570 |
| preacher/CAST | 2,0 | 28,7 × 70 |
| Manager (grid+sep+groups+regroup) | ~9,1 | — |
| Rest (IDLE/ROLL/SIT/DEAD/…) | ~2,5 | — |

**Kernbefund unverändert zu 08d:** kein einzelner Hotspot, sondern der diffuse
GDScript-Objekt-Tick (~10–15 µs/Einheit: Methoden-Dispatch, Property-Roundtrips,
Validitäts-Ketten). Schon eine IDLE-Einheit kostet ~5 µs (2400 Krieger idle =
13 ms/Tick, gemessen `diag_stress_idle`). → Der Weg zu −50 % ist der im
08d-Plan skizzierte C2-Umbau: **flache Kernels über die C1-SoA-Arrays, Objekt-
Code nur noch an Event-Grenzen.**

**Bereits abgeräumt in der Stress-Vorrunde (2026-07-22, nach 0.9.5):**
- Zellen-Stammesmasken im CSR-Grid (Bits 0–7 Stämme, 8–15 Prediger je Stamm):
  Feind-Scans überspringen Zellen ohne Feindbit — Idle-/Anmarsch-Phase −19 %.
- `get_nearest_enemy_preacher` (grid-maskiert) ersetzt den Prediger-Listen-Loop
  der Feuerkrieger (war ~0,25 ms **pro Scan** bei 300 Feind-Predigern, > 30 ms/
  Tick im Stresstest — auch im Leerlauf). Globales Präsenzbit als Early-out für
  prediger-lose Schlachten.
- Schwellwert-Rebuild des Grids bei > 64 Neuregistrierungen: ein Massen-Spawn
  ließ sonst JEDEN Scan die lineare `_grid_extra`-Liste (4000 Einträge)
  durchlaufen — Spawn-Tick 640 ms → 318 ms (Rest = einmalige First-Tick-Kosten
  pro Instanz, nur beim Match-Start spürbar).

Damit bleibt der Peak bei ~50 ms: **ATTACK/MOVE-Bulk = 36 ms ist ohne C2 nicht
adressierbar** (Micro-Opts laut 08d ausgereizt; Sim-Frequenz-Reduktion ist per
Nutzer-Vorgabe tabu).

## Designproblem Nr. 1: Ziel-Referenzen in Arrays (Swap-Remove!)

Kernels brauchen `target`-Zugriff über Arrays (`soa_target[i]` = Index des
Ziels). Aber `unregister` macht **Swap-Remove**: der letzte Slot wandert auf
den freien Index — alle gespeicherten Indizes auf die verschobene Einheit
wären falsch (Geister-Ziel-Klasse!). Optionen, im Detail zu bewerten:

1. **Remap am Swap:** beim Verschieben von `last → index` alle Referenzen auf
   `last` umbiegen. Referenzhalter sind über die Combat-Groups auffindbar
   (Defender kennt Attacker/Waiter, Attacker kennen den Defender) — O(Gruppe).
   Präzise, aber jede neue soa_target-Quelle muss mitziehen (Auditpflicht wie
   C1-Writer-Set).
2. **Generation-Handles:** `soa_target` speichert (index, generation); jeder
   Slot bekommt einen Generationszähler, der bei Swap-Remove hochzählt.
   Validierung im Kernel = 1 Vergleich. Verschobene Einheit braucht trotzdem
   Remap ODER ihre Referenzen verfallen (Attacker verlieren 1 Tick).
3. **Kein soa_target:** Kernel prüft Validität weiter über das Objekt
   (`is_instance_valid` + Felder) — verschenkt den größten Teil des Gewinns.

Empfehlung: (1), da die Combat-Group-Invarianten (max 1 Gruppe pro Einheit)
die Halter-Menge klein und auffindbar machen. Detailschritt C2.1.

## Etappen (jede messbar gegen `benchmark_stress`, Suite grün, rückrollbar)

### C2.1 — soa_target + Swap-Remap (Fundament, kein Perf-Ziel)
`soa_target: PackedInt32Array` (−1 = kein Ziel), gepflegt in
`_begin_attack`/`_end_attack`/`_die`/Konversion; Remap-Hook in `unregister`.
Debug-Validierung (Suite): soa_target[i] zeigt immer auf `attack_target._idx`.

### C2.2 — Melee-Hold-Kernel (größter Einzelposten)
Die stabilste, häufigste ATTACK-Situation: Angreifer steht in Reichweite am
Slot, Cooldown läuft. Kernel über Arrays: Ziel-Validierung (state/tribe/
targetable via soa), Distanz, Cooldown-Dekrement; nur bei „Schlag fällig",
Slot-/Reichweitenverlust oder Zieltod → Objekt-Tick. Erwartung: großer Teil
der 12,9 µs → ~2–3 µs für haltende Kämpfer; Choreografie (Anmarsch, Slots,
Zweite Reihe) bleibt zunächst Objekt-Code.

### C2.3 — Fern-Feuer-Kernel (Feuerkrieger-Stand)
Analog für den stehenden Feuerkrieger (in FIRE_RANGE, Cooldown läuft): Ziel-
Validierung + Distanzband + Cooldown im Kernel, Schuss/Retarget als Event.

### C2.4 — MOVE-Kernel (optional, falls C2.2/2.3 nicht reichen)
`_advance_path`-Bulk (Wegpunkt-Interpolation + Snap + SoA-Write) als Kernel;
Wegpunktwechsel, Ankunft, Stolper-Roll als Objekt-Events.

### C2.5 — Prediger-CAST-Entlastung (klein)
28,7 µs/Einheit; erst nach C2.2/2.3 neu messen (profitiert von Masken bereits).

## Go/No-Go-Tore
- Nach C2.2: `benchmark_stress`-Peak-Block (t300–449) muss messbar fallen
  (Ziel ≥ −8 ms); sonst stoppen und Kernel-Zuschnitt neu bewerten.
- Nach jedem Schritt: Suite grün (3 Läufe, RNG), `benchmark_mass`
  Schlacht-Fenster ohne Regression, In-Game-Sichtprüfung Kampf-Feel
  (Slots, Zweite Reihe, Konversion, Fahrzeug-Crews).
- **In-Game maßgeblich:** FPS-Overlay im Stresstest auf dem Referenzrechner.

## Kritische Dateien
- `scripts/core/unit_manager.gd` — Kernels, soa_target, Remap.
- `scripts/units/unit.gd` — _tick_attack-Zerlegung (Hold-Pfad), Event-Hooks.
- `scripts/units/firewarrior.gd` — Fern-Feuer-Kernel-Anbindung.
- `tests/benchmark_stress.gd`, `tests/diag_stress_battle.gd`,
  `tests/diag_stress_idle.gd` — Mess-Harness (neu, 2026-07-22).

## Verifikation
- `& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/benchmark_stress.gd`
  → Peak-Block t300–449: Baseline **~58 ms** (Ziel ≤ ~28 ms), Blockprofil im Output.
- `res://tests/run_tests.gd` grün; `--headless --quit` sauber.
- In-Game Stresstest: FPS am Höhepunkt, Kampf-Feel-Sichtprüfung.
