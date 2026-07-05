# Phase 6 — Skirmish-KI & Siegbedingungen

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

Vollwertiges Skirmish-Match: Die KI baut, trainiert und greift an — **ausschließlich über
`TribeCommands`**, mit denselben Regeln und Kosten wie der Spieler (kein Cheaten,
architektonisch erzwungen). Siegbedingung und Endscreen („Sieg!"/„Niederlage") schließen
die Spielschleife.

## Voraussetzungen

Phasen 1–5: kompletter Gameplay-Stack (Wirtschaft, Training, Kampf, Zauber, Respawn),
TribeCommands als einzige Mutations-API.

## Deliverables

| Datei | Inhalt |
|---|---|
| `scripts/ai/ai_controller.gd` | `class_name AIController extends Node` (Kind von Main, bekommt `tribe`-Referenz). Tickt **1×/s** (Akkumulator in `_process` → `tick_ai()`; `tick_ai()` direkt aufrufbar für Tests). Handelt NUR über TribeCommands |
| `scripts/ai/ai_state.gd` | State-Machine (`enum AIState {BUILD, TRAIN, ATTACK}`) mit Schwellwert-Übergängen und Rückfall-Logik. Entscheidungslogik als reine Funktionen (Zustand + Tribe-Snapshot rein, Aktionsliste/Folgezustand raus) → headless testbar ohne Szenenbaum |
| KI-Verhalten pro State | **BUILD:** Hütten bauen bis Ziel-Bevölkerung (Bauplatz-Suche: begehbare freie Zellen nahe der Basis), Braves auf Bäume verteilen (`order_gather`), Trainingslager + Tempel errichten, Reinkarnationsplatz-Beter abstellen. → TRAIN, wenn Bevölkerung ≥ X und Gebäude stehen. **TRAIN:** Braves in Lager schicken (`order_train`), Armee-Mix (z. B. 50 % Krieger, 30 % Feuerkrieger, 20 % Prediger) bis Sollstärke Y; Wirtschaft läuft weiter. → ATTACK, wenn Armee ≥ Y und Schamanin lebt. **ATTACK:** Truppe + Schamanin am Sammelpunkt sammeln, dann Angriffsziel Spielerbasis (nächstes Spieler-Gebäude); Schamanin castet situativ (Blast bei Einheitenklumpen in Reichweite, Lightning auf Spieler-Schamanin/stärkste Einheit — simple Heuristik reicht). **Rückfall:** Armee unter Z % dezimiert oder Schamanin tot → zurück zu BUILD/TRAIN |
| Siegbedingung in `game_state.gd` | Ein Tribe ist besiegt, wenn er **keine Einheiten UND keine spawnfähigen Gebäude** (Hütten/Trainingsgebäude/Reinkarnationsplatz) mehr hat. Prüfung über Events (`unit_died`, `building_destroyed`), Signal `tribe_defeated(tribe_id)` → Match-Ende |
| `scenes/ui/end_screen.tscn` + `scripts/ui/end_screen.gd` | Overlay „Sieg!" / „Niederlage" (deutsch) + Button „Beenden"; Spiel pausiert (`get_tree().paused`, UI `process_mode = ALWAYS`) |
| Map-Setup in `main.gd` | Zwei **spiegelsymmetrische Startbasen** (je: Reinkarnationsplatz, Schamanin, Starthütte, Start-Braves, Bäume in Reichweite); Insel-Generierung ggf. symmetrisch spiegeln, damit fair |
| `tests/test_ai.gd` | siehe Tests unten |

## Umsetzungsschritte

1. Siegbedingung + Endscreen (unabhängig von KI testbar).
2. Symmetrisches Map-Setup beider Basen.
3. `ai_state.gd`: Übergangs-/Entscheidungslogik als reine Funktionen + Tests grün.
4. `ai_controller.gd`: BUILD-Verhalten (Bauplatz-Suche, Braves verteilen) → im Spiel
   beobachten; dann TRAIN; dann ATTACK inkl. Zauber-Heuristik.
5. Balance-Grobjustierung der Schwellwerte (Match soll in ~10–20 min entscheidbar sein).
6. Verifikation + manuelle Prüfung (komplettes Match) + Commit/Push.

## Tests (`tests/test_ai.gd`)

- **State-Übergänge** (mit künstlichen Tribe-Snapshots): wenig Bevölkerung → BUILD;
  Bevölkerung/Gebäude über Schwellwert → TRAIN; Armee ≥ Soll + Schamanin lebt → ATTACK;
  Armee dezimiert → Rückfall.
- **Symmetrie-Check (zentral!):** KI-Tribe ohne Holz → `place_building`-Aktion der KI
  schlägt fehl, kein Gebäude entsteht, Holz bleibt 0; KI ohne Mana → `cast_spell`
  schlägt fehl. (Beweist: KI kann nicht cheaten.)
- **BUILD-Tick:** KI-Tribe mit Startressourcen einige `tick_ai()` → mindestens eine
  Hütte via TribeCommands platziert, Holz entsprechend reduziert; Braves haben
  GATHER-Aufträge.
- **TRAIN-Tick:** KI mit Lager + Braves → `order_train`-Aufrufe, nach Trainingszeit
  existieren Kampfeinheiten des KI-Tribes.
- **Siegbedingung:** Tribe alle Einheiten + spawnfähigen Gebäude entziehen →
  `tribe_defeated` gefeuert; mit verbliebener Hütte ODER verbliebener Einheit → nicht
  besiegt.

```powershell
$GODOT = 'C:\Users\johannes.wutzke\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe'
& $GODOT --path D:\game\Populous-TheEnd --headless --import
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/run_tests.gd   # Exit-Code 0
& $GODOT --path D:\game\Populous-TheEnd --headless --quit
```

Zusätzlich sinnvoll: **Headless-Simulationslauf** — Testmodus, der beide Tribes von je
einem AIController steuern lässt und N Minuten Spielzeit mit beschleunigten Ticks
simuliert; prüft, dass genau ein `tribe_defeated` eintritt und keine Skriptfehler fallen
(KI-gegen-KI als Integrationstest, von Claude selbst ausführbar).

## Manuelle Prüfung

- Komplettes Match spielen: KI baut sichtbar Basis auf, sammelt Holz, bildet Armee aus,
  greift mit Schamanin + Truppen an und castet Zauber.
- Spieler gewinnen lassen (rote Basis vernichten) → „Sieg!"-Screen.
- Zweites Match absichtlich verlieren (oder eigene Einheiten/Gebäude via Debug
  dezimieren) → „Niederlage"-Screen.
- Beobachten: KI baut nach verlorenem Angriff wieder auf (Rückfall-Übergang).

## Definition of Done

- [ ] Testsuite grün (inkl. Symmetrie-Check), `--headless --quit` fehlerfrei
- [ ] Komplettes Match manuell gespielt, beide Endscreens gesehen
- [ ] Checkbox Phase 6 in [00_overview.md](00_overview.md) abgehakt
- [ ] `git add -A && git commit -m "Phase 6: Skirmish-KI & Siegbedingungen" && git push`
