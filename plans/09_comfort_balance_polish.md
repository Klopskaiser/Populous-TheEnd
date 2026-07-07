# Phase 9 — Bedienkomfort, Balance & Feinschliff

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).
>
> Diese Phase bündelt die aus der alten Phase 8 herausgelösten NICHT-Performance-
> Punkte (Performance ist jetzt eigenständig Phase 8,
> [08_performance.md](08_performance.md)). Läuft **nach** dem Performance-Pass,
> damit Balance/Feinschliff gegen den optimierten Stand erfolgen.

## Ziel

Das Spiel ist komfortabel bedienbar (Kontrollgruppen, HUD-Ausbau), zentral
balancierbar, hat Feinschliff (Sound-Hooks, Treffer-/Todeseffekte) und ist
dokumentiert (README). Die Testsuite deckt die Kanten- und Fehlerfälle ab.

## Voraussetzungen

Phasen 1–8: vollständig spielbares, performantes Skirmish.

## Deliverables

| Bereich | Inhalt |
|---|---|
| `scripts/core/balance.gd` | `class_name Balance` — ALLE Balancing-Konstanten zentralisieren (bisher in den Klassen verstreut, inkl. der 7i-Werte): Kosten, HP, Schaden, Reichweiten, Geschwindigkeiten, Trainings-/Spawn-/Respawn-Zeiten, Mana-Raten, Zauber-Ladungskosten/-maxima/-radien, Hütten-Crew/Wachstum, Hardcap, KI-Schwellwerte. Alle Klassen umstellen; Tests referenzieren Balance statt Magic Numbers |
| Bedienkomfort | **Kontrollgruppen** Strg+1–9 (zuweisen) / 1–9 (auswählen; Konflikt mit Zauber-Hotkeys lösen, z. B. Zauber nur bei Schamanin-Selektion oder auf F1–F5). Doppelklick = alle Einheiten gleichen Typs im Sichtbereich. **Selektionsanzeige** (Typ + Anzahl + HP-Balken), „Zur Schamanin springen"-Hotkey, Feinschliff der bestehenden Anzeigen (Einheitenzähler, Schamanin-Porträt/Respawn-Countdown) |
| Balance | Balancing-Pass über ein volles Match: neue Zauber (inkl. der 7i-Kostenerhöhungen), Baumertrag/`SKIRMISH_BASE_TREES`, Belagerungswaffe, Hütten-Kosten/Kapazität/Crew-Rate/Wachstumsregler, Trainingsgebäude-Kosten (7i), Feuertempel/Tempel-Größen. Ziel: keine Dominanzstrategie, vertretbare Matchdauer |
| Feinschliff | Sound-Hooks: leere `AudioStreamPlayer3D`-Slots an Schlüsselstellen (Angriff, Zauber, Bau fertig, Einheit fertig). Einfache Todes-/Treffer-Effekte (kurzes Aufblitzen/Partikel). Wasser leicht animiert (Shader-Scroll), optional |
| Testsuite-Vervollständigung | Kanten-/Fehlerfälle: Einheit auf Landbridge während Verformung, Gebäudeplatzierung am Kartenrand, Konvertierung während PANIC/THROWN, Tod während Training, Rally Point im Wasser, Hütten-Crew-/Wachstums-Kanten, Karten-Startanker-Kanten |
| `README.md` | Projektbeschreibung, Steuerung (deutsch), Startbefehle, Teststrategie, Kartenübersicht, Verweis auf plans\ |

## Umsetzungsschritte

1. `balance.gd` extrahieren, alle Klassen + Tests umstellen (reine Refactor-Phase,
   Testsuite muss davor und danach grün sein).
2. Kontrollgruppen + Hotkey-Auflösung + HUD-Ausbau.
3. Feinschliff (Sound-Hooks, Effekte).
4. Testsuite-Lücken schließen; kompletter Suite-Lauf.
5. README schreiben; Balancing-Pass über ein volles Match.
6. Verifikation + manuelle Prüfung + Commit/Push.

## Tests

- Bestehende Suite bleibt nach Balance-Refactor vollständig grün (Regressionsschutz).
- Neue Kantenfall-Tests (siehe Tabelle) grün.
- Headless-KI-Simulationslauf: N Minuten simulierte Spielzeit ohne Skriptfehler,
  genau ein Sieger.

## Manuelle Prüfung

- Kontrollgruppen zuweisen/abrufen; Doppelklick-Selektion; HUD-Anzeigen korrekt.
- Ein komplettes Match auf Balance spielen: keine Dominanzstrategie, Matchdauer ok.

## Definition of Done

- [ ] Gesamte Testsuite grün, `--headless --quit` fehlerfrei
- [ ] Kontrollgruppen/HUD, `balance.gd`, Feinschliff, README vorhanden
- [ ] Match-Balance akzeptabel
- [ ] Checkbox Phase 9 in [00_overview.md](00_overview.md) abgehakt
- [ ] `git add -A && git commit -m "Phase 9: Bedienkomfort, Balance, Feinschliff" && git push`
