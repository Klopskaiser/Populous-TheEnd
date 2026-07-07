# Phase 7h — Wachturm

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

Neues Gebäude **Wachturm**: klein im Grundriss, hoch gebaut, **4 Holz**,
**2 Besatzungsplätze** für Kampfeinheiten und die Schamanin. Stationierte
**Fernwirker** erhalten **+3 m Reichweite** (Feuerkrieger-Beschuss,
Prediger-Bekehrung, Schamanin-Zauber). **Krieger erhalten KEINEN Bonus** —
sie sitzen als geschützte Reserve im Turm (siehe Auslegungen). Alle
Stationierten sind vor **Fernangriffen und Bekehrung geschützt**, bis der
Turm Schadensstufen erleidet oder ein Nahkampfsturm sie rauswirft. Im
Sturm-System aus 7g ist der Turm zäher zu stürmen (max. **5**
Nahkampf-Angreifer statt 15).

## Voraussetzungen

- Phase 7g: Insassen-/Auswurfmechanik (`eject_occupants`,
  `max_melee_raiders`-Override, Fernkampf-Stufe-1-Todesregel), Sturm-Slots.
- Trainee-Mechanik als „Einheit im Gebäude"-Vorlage (`remove_from_world`,
  `register`, Queue-Eintritt über den Eingang).
- Kampf-/Cast-Systeme: Feuerkrieger-`FIRE_RANGE`, Prediger-Konvertierung,
  `Spell.cast_range`, Krieger-Nahkampf.

## Dokumentierte Auslegungen

- **Besatzung:** Krieger, Feuerkrieger, Prediger und die Schamanin — **keine
  Braves** („bemannt von der Schamanin und allen Kriegern").
- **Krieger im Turm haben KEINEN Reichweiten- oder Kampfbonus** (Nutzer-
  Festlegung): Sie greifen NICHT aus dem Turm heraus an. Ihre Vorteile sind
  dieselben wie bei jeder Besatzung — geschützt vor Fernangriffen und
  Bekehrung, bis der Turm Schadensstufen erleidet oder ein Sturm sie
  rauswirft — plus der triviale Umstand, dass ein rausgeworfener Krieger die
  Sturmangreifer mit normalen Krieger-Werten besser abwehrt als z. B. ein
  Brave. Keine Sondermechanik.
- **Schutz der Besatzung:** Stationierte sind für Fernprojektile und
  Prediger-Konvertierung KEIN gültiges Ziel (sie sind aus der Welt, wie
  Trainees — ergibt sich aus der bestehenden Mechanik, wird aber explizit
  getestet).
- **Aussteigen:** Turm selektieren + Rechtsklick auf den Boden = Besatzung
  steigt aus und läuft dorthin (nutzt das Rally-Point-Muster); zusätzlich
  ein „Besatzung entlassen"-Weg über die Gebäude-Selektion.
- **Schamanin im Turm** castet weiterhin über die Zauberleiste/Hotkeys
  (`cast_range + 3`, Cast-Position = Turm); ein Move-/Cast-Ziel außerhalb
  der Reichweite lässt sie NICHT aussteigen — Zielmodus zeigt den Ring um
  den Turm (bewusst simpel; wer sie bewegen will, holt sie raus).

## Deliverables

| Bereich | Datei(en) | Inhalt |
|---|---|---|
| **Gebäude** | `scripts/buildings/watchtower.gd` + `scenes/buildings/watchtower.tscn` | „Wachturm": Kosten **4 Holz**, Footprint **2×2**, hohes schlankes Placeholder-Mesh (Turmschaft + Plattform + Fahne), HP ~200, `housing_capacity 0`, `max_melee_raiders() = 5`. **Besatzung:** `crew: Array` (max. **2**), `admit_crew(unit)` (nur Kampfeinheiten/Schamanin; via `remove_from_world`, Population bleibt gezählt), `eject_crew()`/`eject_occupants`-Anbindung an 7g (Sturm = lebend raus, Fernkampf-Stufe 1 = tot). Nur `is_usable()` hält Besatzung — Beschädigung (Stufe ≥ 1) wirft sie lebend aus (bestehende `_on_disabled`-Hook-Semantik) |
| **Reichweitenbonus (nur Fernwirker)** | `watchtower.gd` (+ kleine Hooks) | `TOWER_RANGE_BONUS = 3.0`. Der Turm **tickt seine Besatzung** in `_tick_active`: je FERNWIRKER ein gedrosselter Scan von der **Turmposition** aus mit `Basisreichweite + 3` — Feuerkrieger: Feuerball-Beschuss (bestehendes Projektil, Abschusspunkt Plattformhöhe), Prediger: Konvertierungs-Channel mit Radius + 3, Schamanin: `cast_range + 3` (Hook in `Shaman`/`TribeCommands.cast_spell`: Cast-Ursprung + Reichweite vom Turm, solange stationiert). **Krieger: KEINE Aktion aus dem Turm** — reine geschützte Reserve (kein Scan, kein Bonus). Einheiten in der Besatzung haben keinen eigenen Welt-Tick (sie sind draußen) — der Turm ist der Koordinator |
| **Einsteigen/Aussteigen** | `selection_manager.gd`, `tribe_commands.gd` | Rechtsklick mit selektierten Kampfeinheiten/Schamanin auf **eigenen** Wachturm → `order_garrison` (Einheiten laufen zum Eingang, treten ein bis 2 Plätze; Überzählige bleiben stehen). Turm selektiert + Rechtsklick auf Boden → Besatzung steigt aus und läuft zum Klickpunkt |
| **UI** | `sidebar.gd`, `ui_theme.gd`, `building.gd`-Overlay | Baumenü-Eintrag „Wachturm (4 Holz)" + Icon; Belegungsanzeige am Turm (Overlay „1/2" bzw. Besatzungs-Punkte); Schamanin-Porträt-Status „im Wachturm" |
| **KI** | `ai_controller.gd` | Nach dem Grundausbau **2 Wachtürme** Richtung Feindseite bauen (`_next_building_scene`); TRAIN-State bemannt leere Türme mit je 2 Feuerkriegern (`order_garrison`), sofern Armee-Soll nicht leidet |
| **Tests** | `tests/test_watchtower.gd` (neu) | siehe unten |

## Umsetzungsschritte

1. Turm-Gebäude + Besatzungs-Mechanik (ein-/aussteigen, Datenebene) + Tests.
2. Reichweitenbonus je Typ (Feuerkrieger → Krieger → Prediger → Schamanin) + Tests.
3. Sturm-/Auswurf-Anbindung an 7g (5er-Limit, tot/lebend) + Tests.
4. UI (Baumenü, Belegungsanzeige) + Rechtsklick-Flows.
5. KI-Turmbau/-Bemannung + Sim-Lauf.
6. Verifikation, PROGRESS.md, Commit/Push.

## Tests (`tests/test_watchtower.gd`)

- **Besatzung:** Krieger + Feuerkrieger steigen ein (2/2), dritter wird
  abgewiesen; Brave wird abgewiesen; Aussteigen setzt beide lebend an den
  Rand; Population konstant über ein-/aussteigen.
- **Reichweite:** Feuerkrieger im Turm trifft ein Ziel bei
  `FIRE_RANGE + 3 − ε`, nicht bei `+ 3 + ε`; Prediger konvertiert mit
  Radius + 3; Schamanin-Cast gelingt auf `cast_range + 3` ohne den Turm zu
  verlassen. **Krieger im Turm greift NIE an** (Feind direkt am Turmfuß →
  keine Aktion, kein Schaden).
- **Besatzungsschutz:** Stationierte Einheit ist kein Ziel für Feuerbälle
  (Projektil-Zielsuche findet sie nicht) und nicht konvertierbar; nach dem
  Auswurf (Sturm) ist sie wieder normal angreifbar/bekehrbar.
- **7g-Integration:** Sturm auf den Turm — max. 5 Angreifer drinnen,
  Besatzung wird lebend rausgeschubst und verprügelt; Fernkampf-Stufe 1 →
  Besatzung tot; beschädigter Turm (Stufe ≥ 1 durch Zauber) wirft lebend aus.
- **Kosten/Platzierung:** 4 Holz über die Bau-Pipeline, 2×2-Footprint
  blockt das NavGrid.

## Manuelle Prüfung

- Turm bauen (4 Holz), 2 Feuerkrieger per Rechtsklick einsteigen lassen →
  sie beschießen Feinde spürbar weiter als zu Fuß; Belegungsanzeige stimmt.
- Schamanin einsteigen lassen → Zauber-Reichweitenring wächst um 3 m.
- Krieger einsteigen lassen → er tut NICHTS (auch bei Feind am Turmfuß),
  ist aber nicht beschieß-/bekehrbar; beim Sturm purzelt er raus und
  kämpft mit normalen Krieger-Werten.
- Turm vom Feind stürmen lassen → nur wenige dringen ein, Besatzung purzelt
  raus; Fernbeschuss allein → Besatzung stirbt bei Stufe 1.
- Turm selektieren + Rechtsklick auf Boden → Besatzung steigt aus.
- KI baut und bemannt Türme; Angriffe auf die KI-Basis werden vom Turm aus
  beschossen.

## Definition of Done

- [x] Testsuite grün (1397 Tests), `--headless --quit` fehlerfrei
- [x] Manuelle Prüfung bestanden (2026-07-07)
- [x] PROGRESS.md ergänzt, Checkbox 7h in [00_overview.md](00_overview.md) abgehakt
- [x] `git add -A && git commit -m "Phase 7h: Wachturm" && git push`
