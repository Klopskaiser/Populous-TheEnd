# Phase 7 — Hauptmenü, Multi-KI & Siegbedingungen

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).
>
> **Hinweis zur Aufteilung:** Die Steuerungs- und Einheitenverhalten-Punkte (Move/Attack-Split,
> Idle-Gruppen, Warteschlangen, Anti-Stacking, Doppelklick-Selektion) sind bewusst in die
> eigene [Phase 7b](07b_unit_control_behavior.md) ausgelagert — sie sind KI-unabhängig und
> würden diese Phase überladen.

## Ziel

Vollwertiges Skirmish-Match **mit bis zu 3 KIs (4 Spieler gesamt)**, erreichbar über ein
**echtes Vollbild-Hauptmenü** vor Spielstart. Jede KI baut, trainiert und greift an —
**ausschließlich über `TribeCommands`**, mit denselben Regeln und Kosten wie der Spieler
(kein Cheaten, architektonisch erzwungen). Siegbedingung und Endscreen
(„Sieg!"/„Niederlage") schließen die Spielschleife.

## Scope

- **Spieleranzahl:** 1 Mensch + **1–3 KIs** (insgesamt 2–4 Tribes). Die Tribe-Infrastruktur
  trägt bereits 4 Tribes (`Main.TRIBE_COUNT`, Tribes 0 = Spieler/Blau, 1–3 = KI); bisher
  bekommt nur eine KI (Sparring) eine Basis. Diese Phase spannt Basen + je einen
  `AIController` für **alle** aktiven KI-Tribes auf.
- **Karten:** vorerst **genau eine** Karte (aktuelle Insel, `ISLAND_SEED`). Die Kartenauswahl
  im Setup-Bildschirm ist bereits als Liste angelegt, enthält aber nur diesen einen Eintrag
  (Erweiterung später trivial).

## Voraussetzungen

Phasen 1–6: kompletter Gameplay-Stack (Wirtschaft, UI, Training, Kampf, Zauber mit
Ladungssystem, Respawn), TribeCommands als einzige Mutations-API. Die Startbasen-Logik in
`main.gd` (`_place_start_site`/`_setup_player_base`/`_setup_sparring`) und die
Debugschlacht (`GameState.debug_battle`) existieren bereits.

## Deliverables

### A. Hauptmenü & Spielstart-Flow

| Datei | Inhalt |
|---|---|
| `scenes/ui/main_menu.tscn` + `scripts/ui/main_menu.gd` | **Vollbild-Hauptmenü** (`Control` full rect, `process_mode = ALWAYS`), gleiche prozedurale Gold/Braun-Optik wie die Sidebar (`UiTheme` wiederverwenden). Wird die **neue Hauptszene** (`project.godot run/main_scene`). Buttons (deutsch): **„Neues Skirmish"** → Setup-Bildschirm, **„Startmission"** (= bisheriger Direktstart: Spieler + 1 Sparring-KI, wie heute), **„Debugschlacht"** (setzt `GameState.debug_battle`), **„Optionen"** → Optionen-Panel, **„Beenden"**. Ein zentraler Einstieg `MainMenu.start_match(config)` lädt `main.tscn` |
| Skirmish-Setup-Bildschirm (Teil von `main_menu.gd` oder eigenes Panel) | Auswahl **Anzahl KIs (1–3)** (SpinBox/Buttons) und **Karte** (OptionButton, aktuell nur „Insel"). „Starten" baut ein `MatchConfig` und ruft `start_match()`; „Zurück" führt zum Hauptmenü |
| Optionen-Panel | Erreichbar aus dem Hauptmenü **und** (bereits vorhanden) aus dem Pausemenü. Enthält mindestens die bestehende **Soundlautstärke** (Master-Bus, `Sidebar._on_volume_changed`-Logik wiederverwenden/teilen); gemeinsame Quelle, kein Duplikat |
| `scripts/core/match_config.gd` | `class_name MatchConfig extends RefCounted`: `ai_count: int` (1–3), `map_id: String` (`"island"`), `mode` (NORMAL / STARTMISSION / DEBUG_BATTLE). Von `GameState` gehalten (`GameState.match_config`), von `Main._ready()` konsumiert |
| `GameState` + `main.gd` (Umbau) | `Main._ready()` liest `GameState.match_config` statt hart 2 Tribes/1 Sparring: erzeugt **`1 + ai_count` Tribes**, spannt für **jeden KI-Tribe** eine Basis auf (Startsite, Schamanin, Starthütte, Start-Braves, Bäume) und hängt je einen `AIController` ein. Ohne Config (Direktstart des Projekts) Fallback = Startmission (heutiges Verhalten) — Ladecheck bleibt grün |

### B. Multi-KI & Siegbedingungen

| Datei | Inhalt |
|---|---|
| `scripts/ai/ai_controller.gd` | `class_name AIController extends Node` (Kind von Main, bekommt `tribe`-Referenz). Tickt **1×/s** (Akkumulator in `_process` → `tick_ai()`; `tick_ai()` direkt aufrufbar für Tests). Handelt NUR über TribeCommands. **Eine Instanz pro KI-Tribe** — die Instanzen sind unabhängig und teilen keinen State |
| `scripts/ai/ai_state.gd` | State-Machine (`enum AIState {BUILD, TRAIN, ATTACK}`) mit Schwellwert-Übergängen und Rückfall-Logik. Entscheidungslogik als reine Funktionen (Zustand + Tribe-Snapshot rein, Aktionsliste/Folgezustand raus) → headless testbar ohne Szenenbaum |
| KI-Verhalten pro State | **BUILD:** Hütten bauen bis Ziel-Bevölkerung (Bauplatz-Suche: begehbare freie Zellen nahe der Basis), Braves auf Bäume verteilen (`order_gather`), Trainingslager + Tempel errichten, Reinkarnationsplatz-Beter abstellen. → TRAIN, wenn Bevölkerung ≥ X und Gebäude stehen. **TRAIN:** Braves in Lager schicken (`order_train`), Armee-Mix (z. B. 50 % Krieger, 30 % Feuerkrieger, 20 % Prediger) bis Sollstärke Y; Wirtschaft läuft weiter. → ATTACK, wenn Armee ≥ Y und Schamanin lebt. **ATTACK:** Truppe + Schamanin am Sammelpunkt sammeln, dann Angriffsziel Spielerbasis (nächstes Spieler-Gebäude); Schamanin castet situativ, wenn eine Ladung verfügbar ist (Blast bei Einheitenklumpen in Reichweite, Lightning auf Spieler-Schamanin/stärkste Einheit — simple Heuristik reicht). **Rückfall:** Armee unter Z % dezimiert oder Schamanin tot → zurück zu BUILD/TRAIN |
| Siegbedingung in `game_state.gd` | Ein Tribe ist besiegt, wenn er **keine Einheiten UND keine nutzbaren spawnfähigen Gebäude** mehr hat (Hütte oder Reinkarnationsplatz; Trainingsgebäude zählen NICHT — sie brauchen einen lebenden Brave, sonst könnte ein einheitenloser Stamm nie besiegt werden). Prüfung über Events (`unit_died`, `building_destroyed`), Signal `tribe_defeated(tribe_id)`. **Bei N Tribes:** Match-Ende erst, wenn **nur noch ein Tribe** übrig ist. **Sieg** = übrig bleibt der Spieler-Tribe; **Niederlage** = der Spieler-Tribe wird besiegt (unabhängig davon, ob noch mehrere KIs leben). Besiegte KI-Tribes scheiden nur aus, das Match läuft für die Übrigen weiter (freie Bündnisse/Diplomatie sind **out of scope** — alle KIs sind Gegner von allen) |
| `scenes/ui/end_screen.tscn` + `scripts/ui/end_screen.gd` | Overlay „Sieg!" / „Niederlage" (deutsch) + Buttons „Zurück zum Menü" (lädt `main_menu.tscn`) und „Beenden"; Spiel pausiert (`get_tree().paused`, UI `process_mode = ALWAYS` — Muster + Optik vom Pausemenü aus Phase 4 wiederverwenden) |
| Map-Setup in `main.gd` | **Bis zu 4 Startbasen** möglichst gleichmäßig über die Insel verteilt (je: Reinkarnationsplatz, Schamanin, Starthütte, Start-Braves, Bäume in Reichweite). Basenpositionen aus einem festen Layout je Spielerzahl (z. B. 2 = gegenüber, 3 = Dreieck, 4 = Quadranten) auf begehbaren Zellen mit genug Abstand; fair genug für Skirmish, exakte Spiegelsymmetrie ist bei 3 Tribes ohnehin nicht möglich |
| `tests/test_ai.gd` | siehe Tests unten |

## Umsetzungsschritte

1. `MatchConfig` + `GameState.match_config`; `main.gd` auf konfigurierbare Tribe-/Basenzahl
   umbauen (N Basen, N−1 KI-Basen), Fallback = Startmission → Ladecheck grün.
2. Siegbedingung für N Tribes + Endscreen (unabhängig von KI testbar).
3. Hauptmenü (`main_menu.tscn`) als neue Hauptszene + Skirmish-Setup (KI-Anzahl, Karte) +
   Optionen (geteilte Lautstärke-Logik) + Debugschlacht + Startmission; `start_match()` lädt
   `main.tscn`.
4. `ai_state.gd`: Übergangs-/Entscheidungslogik als reine Funktionen + Tests grün.
5. `ai_controller.gd`: BUILD-Verhalten (Bauplatz-Suche, Braves verteilen) → im Spiel
   beobachten; dann TRAIN; dann ATTACK inkl. Zauber-Heuristik. Je KI-Tribe eine Instanz.
6. Balance-Grobjustierung der Schwellwerte (Match soll in ~10–20 min entscheidbar sein),
   inkl. Test eines 4-Spieler-Matches (Performance/Verhalten bei 3 KIs gleichzeitig).
7. Verifikation + manuelle Prüfung (komplettes Match, Menü-Flow) + Commit/Push.

## Tests (`tests/test_ai.gd`)

- **State-Übergänge** (mit künstlichen Tribe-Snapshots): wenig Bevölkerung → BUILD;
  Bevölkerung/Gebäude über Schwellwert → TRAIN; Armee ≥ Soll + Schamanin lebt → ATTACK;
  Armee dezimiert → Rückfall.
- **Symmetrie-Check (zentral!):** KI-Tribe ohne Holz → `place_building`-Aktion der KI
  schlägt fehl, kein Gebäude entsteht, Holz bleibt 0; KI ohne Zauber-Ladung →
  `cast_spell` schlägt fehl. (Beweist: KI kann nicht cheaten.)
- **BUILD-Tick:** KI-Tribe mit Startressourcen einige `tick_ai()` → mindestens eine
  Hütte via TribeCommands platziert, Holz entsprechend reduziert; Braves haben
  GATHER-Aufträge.
- **TRAIN-Tick:** KI mit Lager + Braves → `order_train`-Aufrufe, nach Trainingszeit
  existieren Kampfeinheiten des KI-Tribes.
- **Siegbedingung:** Tribe alle Einheiten + spawnfähigen Gebäude entziehen →
  `tribe_defeated` gefeuert; mit verbliebener Hütte ODER verbliebener Einheit → nicht
  besiegt.
- **N-Tribe-Siegbedingung:** bei 3 Tribes (Spieler + 2 KI) einen KI-Tribe besiegen →
  **kein** Match-Ende; danach den zweiten KI-Tribe besiegen → **Sieg** (nur Spieler übrig).
  Spieler-Tribe besiegen, während KIs leben → **Niederlage**.
- **MatchConfig → Tribe-Aufbau:** `MatchConfig(ai_count = 3)` → `main.gd` erzeugt 4 Tribes
  und 4 Basen (reine Aufbaulogik headless prüfbar: Anzahl Tribes, je eine Starthütte +
  Schamanin + Reinkarnationsplatz, KI-Tribes haben einen AIController).

```powershell
$GODOT = 'C:\Users\johannes.wutzke\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe'
& $GODOT --path D:\game\Populous-TheEnd --headless --import
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/run_tests.gd   # Exit-Code 0
& $GODOT --path D:\game\Populous-TheEnd --headless --quit
```

Zusätzlich sinnvoll: **Headless-Simulationslauf** — Testmodus, der **alle Tribes** (2–4)
von je einem AIController steuern lässt und N Minuten Spielzeit mit beschleunigten Ticks
simuliert; prüft, dass am Ende **genau ein** Tribe übrig ist (die anderen `tribe_defeated`)
und keine Skriptfehler fallen (KI-gegen-KI als Integrationstest, von Claude selbst
ausführbar). Einmal mit 4 Tribes laufen lassen (Multi-KI-Stresstest).

## Manuelle Prüfung

- **Menü-Flow:** Spielstart landet im Hauptmenü. „Neues Skirmish" → Setup, KI-Anzahl 1–3 +
  Karte wählen → „Starten" lädt das Match mit der gewählten Spielerzahl. „Startmission",
  „Debugschlacht", „Optionen" (Lautstärke), „Beenden" funktionieren; Endscreen-„Zurück zum
  Menü" führt zurück.
- Komplettes Match spielen: jede KI baut sichtbar Basis auf, sammelt Holz, bildet Armee aus,
  greift mit Schamanin + Truppen an und castet Zauber.
- **4-Spieler-Match (3 KIs):** läuft flüssig, KIs bekämpfen sich gegenseitig und den Spieler.
- Spieler gewinnen lassen (alle gegnerischen Basen vernichtet) → „Sieg!"-Screen.
- Zweites Match absichtlich verlieren (oder eigene Einheiten/Gebäude via Debug
  dezimieren) → „Niederlage"-Screen.
- Beobachten: KI baut nach verlorenem Angriff wieder auf (Rückfall-Übergang).

## Definition of Done

- [ ] Testsuite grün (inkl. Symmetrie-Check + N-Tribe-Sieg + MatchConfig-Aufbau),
      `--headless --quit` fehlerfrei
- [ ] Hauptmenü + Skirmish-Setup (1–3 KIs) manuell durchgespielt, 4-Spieler-Match lief
- [ ] Komplettes Match manuell gespielt, beide Endscreens gesehen
- [ ] Checkbox Phase 7 in [00_overview.md](00_overview.md) abgehakt
- [ ] `git add -A && git commit -m "Phase 7: Hauptmenü, Multi-KI & Siegbedingungen" && git push`
