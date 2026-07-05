# Phase 7 — Performance, Balance & Feinschliff

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

Das fertige Spiel läuft mit 200+ Einheiten flüssig, ist komfortabel bedienbar
(Kontrollgruppen, HUD-Ausbau) und balancierbar (zentrale Konstanten). Testsuite wird
vervollständigt, README dokumentiert das Projekt.

## Voraussetzungen

Phasen 1–6: vollständig spielbares Skirmish-Match.

## Deliverables

| Bereich | Inhalt |
|---|---|
| `scripts/core/balance.gd` | `class_name Balance` — ALLE Balancing-Konstanten zentralisieren (bisher in den Klassen verstreut): Kosten, HP, Schaden, Reichweiten, Geschwindigkeiten, Trainings-/Spawn-/Respawn-Zeiten, Mana-Raten, Zauberkosten/-radien/-cooldowns, KI-Schwellwerte. Alle Klassen umstellen; Tests referenzieren Balance statt Magic Numbers |
| Performance | **Stresstest-Modus** (Kommandozeilen-Flag/Debug-Taste: 200+ Einheiten beider Tribes spawnen). Profiling mit Godot-Profiler im Editor. Bekannte Maßnahmen, falls nötig: gestaffelte `tick`-Raten (Zielsuche/KI seltener als Bewegung), Pfadberechnungs-Queue im NavGrid (Massenbefehle über mehrere Frames verteilen), **MultiMesh für Bäume** (statt N MeshInstance3D), Sichtbarkeits-Culling der Selektionsringe. Ziel: keine spürbaren Hitches bei 200 Einheiten + Landbridge-Cast |
| Bedienkomfort | **Kontrollgruppen** Strg+1–9 (zuweisen) / 1–9 (auswählen; Konflikt mit Zauber-Hotkeys lösen, z. B. Zauber nur bei Schamanin-Selektion oder auf F1–F5). Doppelklick = alle Einheiten gleichen Typs im Sichtbereich. HUD-Ausbau: Selektionsanzeige (Typ + Anzahl + HP-Balken), Einheitenzähler pro Typ, Schamanin-Respawn-Countdown, „Zur Schamanin springen"-Hotkey |
| Feinschliff | Sound-Hooks: leere `AudioStreamPlayer3D`-Slots an Schlüsselstellen (Angriff, Zauber, Bau fertig, Einheit fertig) — Assets optional später. Einfache Todes-/Treffer-Effekte (kurzes Aufblitzen/Partikel). Wasser leicht animiert (Shader-Scroll), optional |
| Testsuite-Vervollständigung | Lücken schließen: Kanten- und Fehlerfälle aus den Phasen 1–6 (z. B. Einheit auf Landbridge während Verformung, Gebäudeplatzierung am Kartenrand, Konvertierung während PANIC/THROWN, Tod während Training, Rally Point im Wasser). Headless-KI-Simulationslauf (aus Phase 6) als fester Bestandteil der Suite |
| `README.md` | Projektbeschreibung, Steuerung (deutsch), Startbefehle, Teststrategie, Verweis auf plans\ |

## Umsetzungsschritte

1. `balance.gd` extrahieren, alle Klassen + Tests umstellen (reine Refactor-Phase,
   Testsuite muss davor und danach grün sein).
2. Stresstest-Modus bauen; im Editor profilen; Engpässe gezielt beheben (Maßnahmenliste
   oben) — nicht auf Verdacht optimieren.
3. Kontrollgruppen + Hotkey-Auflösung + HUD-Ausbau.
4. Feinschliff (Sound-Hooks, Effekte).
5. Testsuite-Lücken schließen; kompletter Suite-Lauf.
6. README schreiben; Balancing-Pass über ein volles Match.
7. Verifikation + manuelle Prüfung + Commit/Push.

## Tests

- Bestehende Suite bleibt nach Balance-Refactor vollständig grün (Regressionsschutz).
- Neue Kantenfall-Tests (siehe Tabelle) grün.
- Headless-KI-Simulationslauf: N Minuten simulierte Spielzeit ohne Skriptfehler, genau
  ein Sieger.
- **Performance-Smoke headless:** Testfall, der 200 Units instanziiert und z. B. 600
  `tick`-Aufrufe (10 s Spielzeit) misst (`Time.get_ticks_usec()`); Budget-Check als
  grobe Regression (großzügige Schwelle, headless ≠ Release-Performance — nur
  Größenordnungs-Wächter gegen O(n²)-Rückfälle).

```powershell
$GODOT = 'C:\Users\johannes.wutzke\Downloads\Godot_v4.7-stable_win64.exe'
& $GODOT --path D:\game\Populous-TheEnd --headless --import
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/run_tests.gd   # Exit-Code 0
& $GODOT --path D:\game\Populous-TheEnd --headless --quit
```

## Manuelle Prüfung

- Stresstest-Modus: 200+ Einheiten bewegen/kämpfen lassen, dabei Landbridge casten —
  flüssig, keine Hitches (FPS-Anzeige/Profiler).
- Kontrollgruppen zuweisen/abrufen; Doppelklick-Selektion; HUD-Anzeigen korrekt.
- Ein komplettes Match auf Balance spielen: keine Dominanzstrategie, Matchdauer ok.

## Definition of Done

- [ ] Gesamte Testsuite grün, `--headless --quit` fehlerfrei
- [ ] Stresstest manuell bestanden, Match-Balance akzeptabel
- [ ] README vorhanden
- [ ] Checkbox Phase 7 in [00_overview.md](00_overview.md) abgehakt
- [ ] `git add -A && git commit -m "Phase 7: Performance, Balance, Feinschliff" && git push`
