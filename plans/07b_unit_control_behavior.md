# Phase 7b — Steuerung & Einheitenverhalten

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

Steuerung und Einheiten-„Feel" auf Original-Niveau bringen: **zwei getrennte
Bewegungsbefehle** (Move ohne / Attack mit Aggro auf dem Weg), einfacheres Fliehen aus
Kämpfen, lebendigeres Idle-Verhalten (Brave-Mini-Aggro, selbstorganisierte 6er-Grüppchen),
geordnete **Warteschlangen** um Produktionsgebäude und **kein Flacker-Stacking** mehr.
Dazu **Doppelklick-Typselektion**.

Diese Phase ist **KI-unabhängig** und wurde aus [Phase 7](07_ai_win_conditions.md)
ausgegliedert. Sie baut auf dem bestehenden Attack-Move- und Aggro-System (Phase 5d/6-Nachtrag)
auf und verfeinert es.

## Voraussetzungen

- Phase 5: Kampf, Aggro (`Unit.AGGRO_RADIUS = 8`, `_engage_on_sight`, `_scan_for_enemy`),
  Retreat außerhalb des Aggro-Radius.
- Phase 6-Nachtrag: **Attack-Move ist aktuell Default** — Kampfeinheiten scannen bereits im
  MOVE-State und greifen Feinde im Aggro-Radius an; Braves sind passiv (nur Vergeltung);
  der Prediger konvertiert statt zu prügeln (`_engage_on_sight`-Override).
- Bewegung/Formation: `TribeCommands.order_move` (räumliche Sortierung, **6er-Gruppen**,
  `GROUP_SPACING`/`MEMBER_OFFSETS`), Pfad-Queue (`UnitManager.path_service`), weiche
  **Separation** (`SEPARATION_RADIUS = 0.44`, Budget/Slices in Phase 3e/3f).
- Selektion: `SelectionManager` (Klick/Box, screen-space `unproject_position`),
  `select_units()`.

## Ausgangslage → Zieländerung (Kurzüberblick)

| Punkt | Ist (heute) | Ziel (7b) |
|---|---|---|
| Bewegungsbefehl | **ein** Rechtsklick-Move; Kampfeinheiten haben Attack-Move immer an | **Move** (kein Angreifen unterwegs) **und Attack** (angreifen unterwegs) getrennt, je Hotkey |
| Fliehen | Retreat greift erst außerhalb 8 m, im Nahkampf zäh | Move-Befehl löst Kampf leichter; Nahkämpfer fallen aber **manchmal** zurück in den Kampf (Selbstverteidigung) |
| Brave Idle | passiv (nur Vergeltung) | zusätzlicher **Mini-Aggro-Radius 3 m** auch im Idle |
| Idle allgemein | Einheiten bleiben, wo sie stehen | nach kurzer Idle-Zeit **Zusammenfinden in 6er-Grüppchen**, nur Mini-Wege (~1 m) |
| Warteschlangen | chaotisch, sobald Gebäude einmal umrundet | geordnete **Schlange in zweiter/dritter Windung** um das Gebäude |
| Stacking | Separation vorhanden, kann noch flackern (Ineinanderstehen) | Ausweichen auf Platz, **kein Flackern** |
| Selektion | Klick / Box | zusätzlich **Doppelklick = alle Einheiten desselben Typs im Sichtfenster** |

## Deliverables

| Bereich | Datei(en) | Inhalt |
|---|---|---|
| **1. Move/Attack-Split** | `unit.gd`, `tribe_commands.gd`, `selection_manager.gd`, `project.godot` | Bewegungsaufträge tragen einen **Modus** `MoveMode { MOVE, ATTACK }` (Feld auf `Unit`, z. B. `move_aggressive: bool`). **MOVE** = kein `_engage_on_sight` im MOVE-State (Einheit läuft durch/an Feinden vorbei, nur Vergeltung bei direktem Angriff). **ATTACK** = heutiges Verhalten (Feinde im Aggro-Radius unterwegs angreifen). `TribeCommands.order_move(units, target, queue_up, aggressive)` setzt den Modus mit; Aggro-Auflösung nach Ankunft folgt dem Idle-Verhalten. **Tastenbelegung (mit Nutzer festgelegt):** **Rechtsklick = normaler Move (passiv)**; **Taste `A` schaltet den Attack-Move-Modus scharf, der folgende Rechtsklick löst den Attack-Move aus** (danach zurück zum normalen Move). Optischer Cursor-/Modushinweis, solange „A" aktiv ist; Esc bricht den Modus ab. Input-Action z. B. `attack_move_arm` (`A`) in `project.godot` |
| **2. Fliehen** | `unit.gd` | Ein **Move (passiv)-Befehl** bricht `ATTACK`/Kampf-State sofort ab und setzt MOVE. **Aber:** wird die Einheit noch im Nahkampf angegriffen (`last_attacker` in Reichweite), darf sie **mit Wahrscheinlichkeit / kurzer Sperre** wieder in den Kampf verfallen (Selbstverteidigung) — Flucht gelingt also nicht immer sofort. Klare, gedrosselte Regel statt Zufall-pro-Frame (deterministisch testbar) |
| **3. Brave Idle-Mini-Aggro** | `brave.gd` | Brave überschreibt `_engage_on_sight` (aktuell passiv) so, dass er im **Idle** Feinde nur bis `BRAVE_IDLE_AGGRO_RADIUS = 3.0 m` angreift (kein voller 8-m-Radius, kein Attack-Move auf dem Weg). Verhalten bei erteiltem Move/Attack bleibt regulär (Move passiv; Attack aggressiv). Schamanin/passive-Sonderfälle unberührt |
| **4. Idle-6er-Grüppchen** | `unit.gd`, `unit_manager.gd` | Nach `IDLE_REGROUP_DELAY` (kurze Idle-Zeit, z. B. 2–3 s) suchen freie Einheiten nahe Nachbarn desselben Tribes und rücken zu **losen 6er-Clustern** zusammen. **Nur Mini-Bewegung:** Zielversatz ≤ `IDLE_REGROUP_MAX_STEP ≈ 1 m`; wer schon nah genug an einer Gruppe steht, bleibt. Umsetzung im UnitManager über den vorhandenen **Spatial-Hash** (gedrosselt, Slices — nie O(n²), nie pro Frame; an Phase-3e-Budget halten). Kein A* für diese Mini-Wege (Direktschritt wie Separation). Deaktiviert für DEAD/THROWN/PANIC/CAST/arbeitende Braves |
| **5. Warteschlangen um Gebäude** | `building.gd` (+ Trainings-/Hütten-Subklassen), `unit.gd` | Wartende Braves (Ausbildung/Reparatur/Rally-Stau) stellen sich in einer **Schlange** um das Gebäude an: Warteplätze werden entlang eines Rings um den Footprint vergeben; ist die erste Windung (ein Mal umrundet) voll, geht es in der **zweiten/dritten Windung** (größerer Radius) weiter — wie eine sich um das Gebäude wickelnde Schlange. Deterministische Platzvergabe (`Building.queue_slot(index) -> Vector3`: Windung = `index / slots_per_ring`, Winkel = `index % slots_per_ring`), Slot-Reservierung wie die bestehenden Bau-Claims. Ersetzt das heutige „alle drängeln auf denselben Eingangspunkt" |
| **6. Anti-Stacking / kein Flackern** | `unit_manager.gd` (Separation), `unit.gd` | Separation so verschärfen, dass **echtes Ineinanderstehen** (Flicker) aufgelöst wird: steht eine Einheit dauerhaft unter Mindestabstand und die Separation kommt nicht frei (eingekeilt), sucht sie **aktiv eine freie Nachbarzelle** (Ring-Suche über begehbare, gering belegte Zellen — Belegung aus dem Spatial-Hash) und geht per Mini-Schritt dorthin. Grüppchenbildung (#4) entschärft das bereits; #6 ist der Fallback für Restfälle. Budget-/Slice-konform (Phase 3e) |
| **7. Doppelklick-Typselektion** | `selection_manager.gd`, `camera_rig.gd`/`camera` | Doppelklick auf eine Einheit → **alle eigenen Einheiten desselben `unit_kind()` im aktuellen Sichtfenster** selektieren. Zeitfenster über gedrosselten Klick-Timestamp (kein `Date.now()` in Kernlogik — in der Node-Input-Ebene ok, aber Auswahl-Filter als reine Funktion `units_of_kind_on_screen(units, kind, camera, viewport_rect)` testbar). Nutzt vorhandenes `unproject_position` + `is_position_behind`-Muster; Ergebnis über `select_units()` |
| **Tests** | `tests/test_unit_logic.gd` (+ ggf. `test_selection.gd`) | siehe unten |

## Umsetzungsschritte

1. **Move/Attack-Split** (#1): Modus-Feld + `order_move(..., aggressive)`; MOVE unterdrückt
   `_engage_on_sight` im MOVE-State. Rechtsklick = Move; `A` schärft Attack-Move, nächster
   Rechtsklick löst aus (Cursor-/Modushinweis, Esc bricht ab). Tests grün.
2. **Fliehen** (#2): Move-Befehl bricht Kampf ab; gedrosselte Rückfall-in-Kampf-Regel bei
   aktivem Nahkampf-Angreifer.
3. **Brave Idle-Mini-Aggro** (#3): 3-m-Radius-Override, Test.
4. **Idle-6er-Grüppchen** (#4) über Spatial-Hash, gedrosselt/Slices; im Spiel beobachten
   (bewegt sich nur minimal, kein Dauer-Gewusel).
5. **Warteschlangen** (#5): `queue_slot()`-Windungslogik + Slot-Reservierung; an Kaserne/
   Feuertempel/Tempel/Hütten-Rally beobachten.
6. **Anti-Stacking** (#6): Restflacker-Fallback; Benchmark prüfen (Budget nicht sprengen).
7. **Doppelklick-Typselektion** (#7).
8. Verifikation + manuelle Prüfung + Commit/Push.

## Tests (`tests/test_unit_logic.gd` u. a.)

- **Move-Modus unterdrückt Aggro:** Kampfeinheit im MOVE (passiv) mit Feind im 8-m-Radius →
  kein Wechsel in ATTACK, Ziel wird erreicht. Im ATTACK-Modus → greift an (bestehendes
  `test_marching_combatants_engage_on_contact` bleibt gültig, ggf. auf ATTACK-Modus stellen).
- **Fliehen:** Einheit im Kampf, `order_move(passiv)` → State MOVE; mit Angreifer in
  Nahkampfreichweite feuert die Rückfall-Regel deterministisch (gedrosselt) → verfällt
  wieder in Kampf; ohne Angreifer bleibt sie im MOVE.
- **Brave Idle-Aggro 3 m:** Feind bei 2,5 m → Brave greift an; Feind bei 5 m → Brave bleibt
  passiv (kein 8-m-Aggro).
- **Idle-Grüppchen:** mehrere IDLE-Einheiten nahe beieinander → nach `IDLE_REGROUP_DELAY`
  rücken sie zusammen, Einzelschritt ≤ `IDLE_REGROUP_MAX_STEP`; isolierte Einheit ohne
  Nachbarn bewegt sich **nicht**; arbeitende Braves/PANIC/THROWN werden nicht umgruppiert.
- **Warteschlangen-Slots:** `Building.queue_slot(index)` — Windung wächst mit dem Index
  (Slots 0..k−1 erste Windung, k..2k−1 zweite, größerer Radius), Positionen begehbar und
  nicht im Footprint; zwei Braves bekommen unterschiedliche Slots.
- **Anti-Stacking:** zwei exakt überlappende Einheiten, Separation blockiert → eine sucht
  eine freie Nachbarzelle (reine Ring-Suche testbar); Ergebnis begehbar, Abstand ≥
  `SEPARATION_RADIUS`.
- **Doppelklick-Typselektion:** `units_of_kind_on_screen(units, "warrior", cam, rect)`
  liefert nur eigene Krieger im Rechteck (Fremd-Tribe/andere Typen/außerhalb ausgeschlossen).

```powershell
$GODOT = 'C:\Users\johannes.wutzke\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe'
& $GODOT --path D:\game\Populous-TheEnd --headless --import
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/run_tests.gd   # Exit-Code 0
& $GODOT --path D:\game\Populous-TheEnd --headless --quit
```

## Manuelle Prüfung

- **Move (passiv):** selektierte Truppe per **Rechtsklick** an feindlicher Gruppe
  vorbeischicken → läuft durch, greift **nicht** an (nur Vergeltung bei direktem Beschuss).
  **Attack-Move:** **`A`** drücken, dann **Rechtsklick** aufs Ziel → greift Feinde auf dem
  Weg an; Cursor-/Modushinweis sichtbar, Esc bricht den scharfen Modus ab.
- **Fliehen:** Truppe aus einem Nahkampf per Move (passiv) abziehen → löst sich meist, aber
  einzelne im Handgemenge hängen kurz nach (verteidigen sich), lösen sich dann.
- **Brave Idle-Aggro:** einzelner Feind läuft dicht an untätige Braves → Braves schlagen im
  3-m-Umkreis zu, ignorieren Feinde weiter weg.
- **Idle-Grüppchen:** frisch gespawnte/untätige Einheiten ordnen sich nach kurzer Zeit zu
  6er-Grüppchen mit kleinen Schritten; kein dauerndes Umherlaufen.
- **Warteschlangen:** viele Braves zu einer Kaserne schicken → geordnete Schlange, die sich
  bei Andrang in einer zweiten/dritten Windung um das Gebäude legt (kein Klumpen am Eingang).
- **Kein Stacking-Flicker:** dichte Menge auf einen Punkt → keine ineinander flackernden
  Sprites; Einheiten schieben sich auf freien Platz.
- **Doppelklick:** Doppelklick auf einen Krieger wählt alle sichtbaren eigenen Krieger.

## Definition of Done

- [ ] Testsuite grün (neue Tests inkl. Move-Modus, Idle-Grüppchen, Warteschlangen-Slots,
      Doppelklick-Filter), `--headless --quit` fehlerfrei, Benchmark im Budget
- [ ] Manuelle Prüfung bestanden (alle Punkte oben)
- [ ] Tastenbelegung (Rechtsklick=Move, `A`+Rechtsklick=Attack-Move) in `project.godot`
- [ ] Checkbox Phase 7b in [00_overview.md](00_overview.md) abgehakt
- [ ] `git add -A && git commit -m "Phase 7b: Steuerung & Einheitenverhalten" && git push`
