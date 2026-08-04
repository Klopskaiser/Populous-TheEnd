# Phase 10f — Hüttenüberarbeitung: kleinere Hütten, ausbaubar bis zum Wohnpalast

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

Die Hütte wird von „einem großen Wohnblock" zu einem **wachsenden Gebäude**:
billig und klein am Anfang, über vier Ausbaustufen zum **Wohnpalast**. Der
Bevölkerungsraum kommt nicht mehr aus der Hüttenzahl allein, sondern aus
Hüttenzahl **×** Ausbaustand.

| | vorher | Stufe 0 | Stufe 1 | Stufe 2 | Stufe 3 | Stufe 4 (Wohnpalast) |
|---|---|---|---|---|---|---|
| Holz (kumuliert) | 12 | **8** | 13 | 18 | 23 | **28** |
| Bevölkerungsplätze | 40 | **10** | 18 | 26 | 34 | **45** |
| Arbeiterplätze | 4 | **2** | 3 | 4 | 5 | **6** |

**Wirtschaftliche Folge — das ist die eigentliche Balance-Änderung:** ein Platz
kostete vorher 0,3 Holz (12/40), jetzt 0,8 Holz bei Stufe 0 (8/10) und 0,62 bei
Vollausbau (28/45). Wohnraum ist damit **rund doppelt so teuer**, und die
Bevölkerung wächst nur, wenn der Spieler (und die KI) in Ausbau investiert. Das
zieht sich durch die ganze KI-Bauordnung und ist der Grund für Teil 4.

## Nutzer-Festlegungen (2026-08-04)

- **Upgrade-Sperre stammweit**, als Schaltfläche beim vorhandenen
  Wachstumsregler. Keine Sperre pro Hütte.
- **Alle Arbeiter der Hütte** holen Holz und bauen aus → eine Hütte im Ausbau
  produziert **gar keine** Bevölkerung.
- **Bevölkerungsplätze:** Standardhütte **10**; die Stufen 1–3 bringen je **+8**,
  die letzte Stufe 4 bringt **+11** (also 10 / 18 / 26 / 34 / 45).
- **KI wird mitgezogen** (Teil 4).

## Bestandsaufnahme (am Code verifiziert)

- `scripts/buildings/hut.gd` (361 Z.): Besatzung („crew") ist **im Gebäude
  versteckt** (`unit_manager.remove_from_world`), zählt weiter zur Bevölkerung.
  `admit_crew`/`eject_crew`/`eject_occupants`/`_release_crew_member`,
  Wachstumspflege `_tick_growth` mit `manual_crew_override`, Produktion in
  `_tick_active` über `spawn_timer` und `_spawn_rate_factor()`.
- **Alle Kapazitäts- und Besatzungswerte sind heute `const`** (`CAPACITY`,
  `CREW_CAPACITY`, `SPAWN_INTERVAL`, `FULL_CREW_BONUS`) und werden an 8 Stellen
  gelesen — sie müssen sämtlich **stufenabhängige Methoden** werden.
- `housing_capacity()` (`hut.gd:52`) liefert `CAPACITY if is_usable() else 0`.
  **Diese Null ist eine Falle** (in Phase 10e bereits einmal aufgelaufen): sie
  gilt für Baustellen *und* beschädigte Hütten. Der Ausbau darf `is_usable()`
  **nicht** auf false ziehen, sonst bricht der Wohnraum des ganzen Stammes
  während jedes Ausbaus ein.
- **Der Reparatur-Pfad ist die exakte Vorlage für den Ausbau** — er ist bereits
  „Holz holen für ein FERTIGES Gebäude":
  `Building.wants_more_repair_wood()` (:514), `repair_wood_missing()` (:504),
  `Brave._choose_repair_task()` (:658), `Brave._tick_repair()` (:921),
  `Brave._job_wants_wood()` (:934), `_try_fetch_wood()`, und für „kein Holz
  erreichbar" schon `mark_wood_stalled()`. Der Ausbau wird als **dritte
  Job-Art** danebengelegt, nicht neu erfunden.
- `demolishing` aus 10d ist die Vorlage für den **Zustand**: ein Flag, das
  Nutzung/Produktion sperrt, ohne `under_construction` anzufassen.
- Modelle: `asset_kind()` (`hut.gd:323`) → `assets/models/buildings/<kind>.glb`
  über `_try_load_custom_model()` (`building.gd:1636`); ohne Datei greifen die
  prozeduralen Platzhalter in `_create_visuals()`. Die Zerstörungs-Texturen
  laufen über denselben `asset_kind()` (`building.gd:1799/1821`).
- Besatzungs-Pips: `crew_display_capacity()`/`crew_display_filled()`
  (`hut.gd:315`) — die Kapazität ist künftig **variabel**.
- Abriss-Erstattung: `demolish_refund_total()` rechnet mit `wood_cost`. Wird das
  Ausbauholz nicht mitgezählt, **verliert der Spieler beim Abriss einer
  ausgebauten Hütte 20 Holz**.
- Wachstumsregler-UI: `sidebar.gd:453-472` (`_growth_slider`, `_on_growth_changed`
  → `Tribe.set_growth_mode`). Genau dort kommt die neue Schaltfläche hin.

---

## Teil 1 — Werte und stufenabhängige Hütte

### Balance (`scripts/core/balance.gd`, Abschnitt `# --- Hütte ---`)

```gdscript
const HUT_WOOD_COST: int = 8                  # war 12
const HUT_HP: int = 300                       # Stufe 0 (siehe HUT_HP_PER_STAGE)
## Plätze/Arbeiter/Leben je Ausbaustufe (Index = Stufe 0..4). Stufe 4 bringt
## bewusst +11 statt +8 Plätze — der Wohnpalast ist der Lohn für den Vollausbau.
const HUT_CAPACITY_PER_STAGE: Array[int] = [10, 18, 26, 34, 45]
const HUT_CREW_PER_STAGE: Array[int]     = [2, 3, 4, 5, 6]
const HUT_HP_PER_STAGE: Array[int]       = [300, 340, 380, 420, 480]
const HUT_MAX_UPGRADE_STAGE: int = 4
## Sekunden je Brave und ARBEITER: die Rate ist linear in der Besatzung.
## 30 s → Stufe 0 (2 Arbeiter) 15 s/Brave, Stufe 4 (6 Arbeiter) 5 s/Brave.
## Bewusst langsamer als die alte Hütte (~9,1 s bei 4 Mann).
const HUT_SPAWN_SECONDS_PER_WORKER: float = 30.0
## Wartezeit nach Fertigstellung bzw. nach dem letzten Ausbau, bis das nächste
## Upgrade verfügbar wird.
const HUT_UPGRADE_DELAY: float = 90.0
const HUT_UPGRADE_WOOD_COST: int = 5
## Bauzeit-Faktor des Ausbaus auf Brave.BUILD_RATE.
const HUT_UPGRADE_RATE_FACTOR: float = 1.0
## Ein Ausbau STARTET nur, wenn in diesem Radius überhaupt Holz erreichbar ist
## (Bäume, Bodenstapel oder ein Holzlager mit Bestand) — sonst würde die Hütte
## ihre Besatzung in eine aussichtslose Holzsuche auswerfen.
const HUT_UPGRADE_WOOD_RADIUS: float = 40.0
```

**Entfällt:** `HUT_CAPACITY`, `HUT_CREW_CAPACITY`, `HUT_SPAWN_INTERVAL`,
`HUT_FULL_CREW_BONUS` — die Rate ist jetzt linear pro Arbeiter, der
Voll-Besatzungs-Bonus ist damit gegenstandslos.

### `scripts/buildings/hut.gd`

Konstanten → Methoden, alle über die Stufe indiziert:

```gdscript
var upgrade_stage: int = 0

func capacity() -> int          # HUT_CAPACITY_PER_STAGE[upgrade_stage]
func crew_capacity() -> int     # HUT_CREW_PER_STAGE[upgrade_stage]
func spawn_interval() -> float  # HUT_SPAWN_SECONDS_PER_WORKER (pro Arbeiter)
func display_name() -> String   # "Hütte" .. "Wohnpalast" je Stufe
```

Umzustellende Lesestellen (alle acht): `housing_capacity()`, `has_crew_room()`,
`admit_crew()`, `_crew_target()` (MAXIMUM → `crew_capacity()`),
`_admit_arrived_crew()`, `_spawn_rate_factor()`, `production_progress()`,
`growth_per_minute()`, `crew_display_capacity()`.

**Produktionsrate neu:** `spawn_timer` läuft mit
`crew.size() / HUT_SPAWN_SECONDS_PER_WORKER` pro Sekunde — linear in der
Besatzung, ohne Voll-Bonus. `production_progress()` normiert auf
`HUT_SPAWN_SECONDS_PER_WORKER`.

---

## Teil 2 — Ausbau-Mechanik

### Zustand (Muster: `demolishing` aus 10d)

```gdscript
var upgrade_stage: int = 0
## Zeit seit Fertigstellung bzw. seit dem letzten Ausbau.
var _upgrade_timer: float = 0.0
## Ausbau ist fällig (Timer voll) — bleibt bei „voll" stehen, solange die Sperre
## greift oder kein Holz erreichbar ist. DAS ist der 100-%-Halt aus der Vorgabe.
func upgrade_ready() -> bool
## Baumaßnahme läuft: Besatzung ist ausgeworfen, holt Holz und baut aus.
var upgrading: bool = false
var upgrade_wood: int = 0        # geliefert von HUT_UPGRADE_WOOD_COST
var upgrade_progress: float = 0.0
```

**`upgrading` zieht `is_usable()` NICHT auf false.** Die Hütte behält ihren
Wohnraum (`housing_capacity()` liefert weiter die Stufen-Kapazität) und verliert
nur die **Produktion** — genau wie eine Hütte ohne Besatzung. Damit bricht der
Bevölkerungsdeckel des Stammes während des Ausbaus nicht ein.

### Ablauf

1. `_tick_active`: `_upgrade_timer += delta`, gedeckelt auf `HUT_UPGRADE_DELAY`
   (der Fortschritt „bleibt bei 100 % stehen").
2. Startbedingungen für die Baumaßnahme — **alle** müssen gelten:
   `upgrade_stage < HUT_MAX_UPGRADE_STAGE`, `upgrade_ready()`, `is_usable()`
   (nicht beschädigt), nicht `demolishing`, `tribe.upgrades_allowed`,
   und `_upgrade_wood_reachable()`.
3. `begin_upgrade()`: `upgrading = true`, **alle** Besatzungsmitglieder werden
   lebend ausgeworfen (`eject_occupants(false)`-Muster) und per
   `commands.order_upgrade(crew, self)` auf den Ausbau gesetzt.
4. Braves: neue `Task.UPGRADE`, strukturgleich zu `Task.REPAIR` —
   `_choose_upgrade_task()` holt Holz solange `wants_upgrade_wood()`, sonst
   `Task.UPGRADE`; `_tick_upgrade()` arbeitet
   `add_upgrade_progress(BUILD_RATE * HUT_UPGRADE_RATE_FACTOR * delta)`.
   Kein Holz erreichbar → `mark_wood_stalled()` wie beim Reparieren.
5. `_finish_upgrade()`: `upgrade_stage += 1`, `max_health`/`health` auf die neue
   Stufe, `wood_cost += HUT_UPGRADE_WOOD_COST` (**Abriss-Erstattung!**),
   `_upgrade_timer = 0.0`, `upgrading = false`, Modell/Visual neu aufbauen, dann
   dürfen die Braves wieder als Besatzung einziehen (der Wachstumsregler holt
   sie automatisch zurück, weil `crew_capacity()` gestiegen ist).
6. Abbruch: Zerstörung, Abriss oder Schaden (Stufe ≥ 1) bricht den Ausbau ab;
   geliefertes Holz kommt als Bodenstapel zurück (`_refund_wood`-Muster aus 10d).

### `_upgrade_wood_reachable()`

`tree_manager.count_trees_near(center, HUT_UPGRADE_WOOD_RADIUS) > 0` **oder** ein
Bodenstapel/Holzlager mit Bestand in Reichweite. Ohne `tree_manager` (headless)
permissiv `true`, damit Tests stabil bleiben.

### Modell je Stufe

`asset_kind()` wird stufenabhängig: `&"hut"`, `&"hut1"` … `&"hut4"` (Stufe 4 =
Wohnpalast). Ohne `.glb` greifen die prozeduralen Platzhalter — die wachsen mit
der Stufe (höherer Körper, zweites Dachgeschoss, ab Stufe 3 ein Anbau), damit die
Stufen **ohne Assets** unterscheidbar sind. Die Zerstörungs-Texturpfade folgen
`asset_kind()` automatisch mit.

---

## Teil 3 — UI: Ausbau-Sperre (stammweit)

- `Tribe.upgrades_allowed: bool = true` + `TribeCommands.set_upgrades_allowed()`
  (Mutationen laufen ausschließlich über TribeCommands, siehe Overview §4).
- `sidebar.gd`: `CheckButton` „Ausbau erlauben" in einer Zeile unter dem
  Wachstumsregler (`:453-472`). Aus = fällige Ausbauten warten sichtbar.
- Anzeige an der Hütte: der vorhandene Produktionsbalken zeigt während
  `upgrading` den **Ausbaufortschritt** (Muster 10d: der Abriss nutzt denselben
  Balken in Rot) — kein neues Widget. Vorschlag: Ausbau = **blau**.
- Hütten-Panel: Stufe und Ausbaustatus im vorhandenen `info`-Text
  (`sidebar.gd:900`), z. B. „Wohnpalast (Stufe 4) — Besatzung 5/6".

---

## Teil 4 — KI mitziehen

Mit 10 statt 40 Plätzen je Stufe-0-Hütte kippen die 10e-Schwellwerte:
`TARGET_HUTS 4` bedeutet jetzt 40 statt 160 Plätze, und `AI_MAX_HUTS 30` deckelt
den Stamm bei 300 Plätzen, falls nicht ausgebaut wird.

| Konstante | jetzt | Vorschlag | Grund |
|---|---|---|---|
| `AIState.TARGET_HUTS` | 4 | **6** | Grundwohnraum 60 statt 40 Plätze |
| `Balance.AI_MAX_HUTS` | 30 | **60** | 60 × 45 = 2700 Plätze Vollausbau; ohne Ausbau 600 |
| `Balance.AI_MAX_HUT_SITES` | 2 | **3** | kleine Hütten müssen schneller nachwachsen |

Die KI braucht **keine** eigene Ausbau-Logik: `upgrades_allowed` ist per Default
`true` und der Ausbau läuft von selbst. Zu prüfen ist nur, dass der
Wohnraumdruck-Zweig aus 10e (`next_building_kind`) mit den kleineren Hütten nicht
dauerhaft feuert und die restliche Bauordnung aushungert — der
`AI_MAX_HUT_SITES`-Deckel ist genau dafür schon da.

---

## Umsetzungsschritte

1. Balance-Werte + `Hut`-Konstanten → stufenabhängige Methoden (Teil 1), alle
   acht Lesestellen umstellen. **Danach Suite:** hier brechen `test_hut_crew`,
   `test_economy` (Wohnraum/Spawnrate) und die KI-Wohnraumtests.
2. Ausbau-Zustand + `_tick_upgrade_timer` + Startbedingungen (Teil 2, Schritte
   1–2), ohne Baumaßnahme — rein datenseitig und headless testbar.
3. `Task.UPGRADE` im Brave + `wants_upgrade_wood`/`add_upgrade_progress` +
   `TribeCommands.order_upgrade` (Teil 2, Schritte 3–5), streng nach dem
   Reparatur-Muster.
4. Abbruch-/Erstattungspfade (Teil 2, Schritt 6) inkl. `wood_cost`-Akkumulation
   für die Abriss-Erstattung.
5. Visuals je Stufe + `asset_kind()`.
6. UI: `upgrades_allowed` + CheckButton + Balken/Infotext (Teil 3).
7. KI-Schwellwerte (Teil 4).
8. PROGRESS.md, Checkbox in `00_overview.md`, Commit/Push.

## Tests

**Neu `tests/test_hut_upgrades.gd`:**
`test_stage_zero_hut_has_the_new_small_values` (8 Holz, 10 Plätze, 2 Arbeiter),
`test_capacity_and_crew_grow_per_stage` (alle fünf Stufen gegen die
Balance-Arrays, inkl. +11 auf der letzten),
`test_spawn_rate_is_linear_in_the_crew`,
`test_upgrade_becomes_ready_after_the_delay`,
`test_upgrade_progress_stops_at_full_while_forbidden` (Kern der Vorgabe:
`upgrades_allowed = false` → `upgrade_ready()` bleibt wahr, `upgrading` bleibt
falsch; nach Freigabe startet die Baumaßnahme),
`test_upgrade_waits_for_reachable_wood` (ohne Bäume kein Start, mit Baum Start),
`test_upgrade_ejects_the_whole_crew`,
`test_hut_produces_nothing_while_upgrading` (Bevölkerung bleibt konstant),
`test_hut_keeps_its_housing_while_upgrading` (**Regressionswächter** für die
`is_usable()`-Falle),
`test_finished_upgrade_raises_stage_capacity_crew_and_hp`,
`test_upgrade_refund_counts_toward_the_demolition_payout` (Abriss einer Stufe-3-
Hütte erstattet 75 % von 23, nicht von 8),
`test_damage_cancels_a_running_upgrade_and_returns_the_wood`,
`test_max_stage_hut_never_upgrades_again`.

**Anzupassen:** `test_hut_crew` (Besatzung 4 → stufenabhängig),
`test_economy` (Wohnraum-/Spawnrechnung), `test_ai` (Wohnraumdruck und
`TARGET_HUTS`), `test_ui_logic` (Sidebar-Zeile), `test_demolition`
(Erstattung ausgebauter Hütten).

## Manuelle Prüfung

- Hütte bauen → nach `HUT_UPGRADE_DELAY` verlassen **beide** Arbeiter die Hütte,
  holen Holz, bauen aus; das Modell wächst sichtbar, danach ziehen sie wieder ein
  und die Hütte hat mehr Platz und einen Arbeiterplatz mehr.
- Während des Ausbaus: **keine** neuen Braves aus dieser Hütte, aber der
  Bevölkerungsdeckel des Stammes sinkt **nicht**.
- „Ausbau erlauben" aus → fällige Hütten warten; wieder an → sie legen los.
- Hütte ohne Holz in der Nähe → wartet, ohne die Besatzung auszuwerfen.
- Vollausbau bis Wohnpalast (Stufe 4), danach kein weiterer Ausbau.
- Ausgebaute Hütte mit `Entf` abreißen → Erstattung passt zum investierten Holz.
- Langes Skirmish: kommt die KI mit den kleinen Hütten noch über 300 Bevölkerung?

## Risiken

1. **`is_usable()`-Falle.** `housing_capacity()` liefert 0, sobald die Hütte
   nicht nutzbar ist. Zieht der Ausbau `is_usable()` auf false, bricht der
   Wohnraum des Stammes während **jedes** Ausbaus ein und die Bevölkerung
   stagniert. Deshalb ein eigenes `upgrading`-Flag (Wächter-Test oben).
2. **Abriss-Erstattung** muss das Ausbauholz mitzählen, sonst verliert der
   Spieler bis zu 20 Holz je Hütte.
3. **Wohnraum-Schock durch die Werteänderung**: bestehende Stände haben nach dem
   Umbau schlagartig ein Viertel des Wohnraums (40 → 10 pro Hütte) und damit
   `population > housing_capacity`. Die Produktion stoppt, bis Hütten gebaut oder
   ausgebaut sind. Das ist gewollt, muss aber im Spieltest bewusst beobachtet
   werden — es fühlt sich beim ersten Start nach einem Rückschritt an.
4. **Variable Besatzungskapazität** berührt Pips, Wachstumsregler (`MAXIMUM`),
   `manual_crew_override` (ein Override von 4 überlebt eine Stufensenkung nicht
   — clampen!) und die KI-Bemannung.
5. **Ausbau vs. Reparatur** konkurrieren um dieselben Braves und dasselbe Holz.
   Vorschlag: **Reparatur hat Vorrang**, Ausbau startet nur bei voller Gesundheit.
6. **Mehr Hütten = mehr Gebäude** → die Bauplatzsuche der KI (10e) läuft öfter.
   `dbg_plot_us` im Blick behalten; das gemeinsame Zellbudget aus 10e deckelt es.

## Definition of Done

- [ ] Alle fünf Stufen erreichbar, Werte exakt 10/18/26/34/45 und 2/3/4/5/6
- [ ] Ausbau-Sperre stammweit wirksam, Fortschritt hält bei 100 %
- [ ] Kein Ausbau ohne erreichbares Holz, ohne die Besatzung auszuwerfen
- [ ] Wohnraum bricht während des Ausbaus nicht ein (Wächter-Test)
- [ ] Abriss-Erstattung enthält das Ausbauholz
- [ ] Testsuite grün, `--headless --quit` fehlerfrei
- [ ] Manuelle Prüfung durch den Nutzer bestanden
- [ ] PROGRESS.md ergänzt, Checkbox in [00_overview.md](00_overview.md), Commit/Push
