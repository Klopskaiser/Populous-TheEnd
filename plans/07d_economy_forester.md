# Phase 7d — Wirtschaft: Förster-Gebäude & Baum-Ertrag 1/2/3/4

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

Zwei Wirtschaftsänderungen: (1) Die vier Baum-Wachstumsstufen liefern
**1/2/3/4 Holz** (bisher 1/1/2/3 — die Stufen ergeben damit spürbar mehr
Sinn), (2) ein neues Gebäude **Förster**, das im Umkreis aktiv Bäume
nachpflanzt — nachhaltige Holzversorgung ohne Expansion.

## Voraussetzungen

Phase 3b/3c-Wirtschaft: `TreeResource` (Stufen/`YIELDS`/`harvest_one`
-Herabstufung/Ernte-Slots), `TreeManager` (`spawn_tree`, `MIN_SPACING`,
Dichte-/Vermehrungslogik, `MAX_TREES 250`), Bau-Pipeline, Baumenü.

## Deliverables

| Datei | Inhalt |
|---|---|
| `scripts/core/tree_resource.gd` | `YIELDS` `[1,1,2,3]` → **`[1,2,3,4]`**. Folgeanpassungen: Ernte-Slots (`can_claim`: Slots = Restholz, damit max. **4** parallele Ernter am großen Baum), `chop_time`-Staffel prüfen (größte Stufe etwas länger), `harvest_one`-Herabstufung bleibt „eine Stufe pro Holz" — ein großer Baum braucht jetzt **4 Ernten** |
| `scripts/buildings/forester.gd` + `scenes/buildings/forester.tscn` | **Förster** (`display_name "Försterei"`): Holzkosten **10**, Footprint **3×3**, HP ~250. `_tick_active` (nur `is_usable()`): pflanzt alle **20 s** einen **kleinen Baum (Stufe 0)** auf einer freien begehbaren Zelle im Radius **10** um das Gebäude (Ringsuche, `TreeManager.MIN_SPACING` respektieren, nicht auf Bauplätzen/Stapeln). **Eigener Deckel statt globalem:** pflanzt nur, wenn im 10er-Radius **< 12 Bäume** stehen (lokale Dichte); der globale `MAX_TREES`-Deckel wird auf **400** angehoben, damit Förster mehrerer Stämme nicht verhungern (Vermehrungs-Stichprobe bleibt bei 250-Verhalten unauffällig — Deckel gilt weiter für die natürliche Vermehrung mit) |
| UI | Baumenü-Eintrag „Försterei (10 Holz)" in `Sidebar.default_build_entries()`, neues 24×24-Icon (`forester`, z. B. Setzling) in `ui_theme.gd` |
| KI | `AIController._next_building_scene`: nach dem Grundausbau eine **Försterei, wenn die Holzversorgung um die Basis dünn wird** (weniger als `MIN_TREES_NEAR_PLOT`-Niveau, z. B. < 6 Bäume im 22-m-Umkreis des Basis-Ankers) und noch keine (nutzbare/geplante) Försterei existiert — greift VOR der Expansion zum fernen Wald |
| Balance-Notiz | 4er-Bäume liefern ~⅓ mehr Holz: `Main.SKIRMISH_BASE_TREES` 16 → **12** als Startwert nachziehen (Feinbalance Phase 8) |
| Tests | `tests/test_economy.gd` erweitert (siehe unten) |

## Umsetzungsschritte

1. `YIELDS`-Umstellung + betroffene Bestands-Tests fixen (Ertrag, Slots,
   Herabstufungs-Ketten — mehrere Phase-3-Tests referenzieren 1/1/2/3).
2. Försterei (Gebäude + Pflanzlogik) + Tests.
3. UI-Eintrag + Icon.
4. KI-Regel + Test.
5. `SKIRMISH_BASE_TREES` anpassen; kurzer KI-Sim-Lauf (Basisaufbau darf nicht
   stallen — Erkenntnis aus Phase 7: zu wenig Holz stallte die Lager).
6. Verifikation, PROGRESS.md, Commit/Push.

## Tests (`tests/test_economy.gd`)

- **Ertrag:** Stufen liefern 1/2/3/4; großer Baum = 4 Einzel-Ernten mit
  Herabstufung 3→2→1→weg; 4 parallele Ernte-Slots am großen Baum.
- **Försterei:** platziert + `pre_built` → nach `tick`-Zeit ≥ 1 neuer Baum im
  Radius (Stufe 0); lokale Dichte ≥ 12 → pflanzt NICHT; beschädigt (Stufe ≥ 1)
  → pflanzt nicht; Mindestabstand zu Bestandsbäumen eingehalten.
- **KI:** Basis ohne Bäume im Umkreis + Grundausbau fertig →
  `_next_building_scene` liefert die Försterei (vor der Expansion).

## Manuelle Prüfung

- Großer Baum gibt sichtbar 4 Holz (4 Hack-Zyklen, Baum schrumpft je Stufe).
- Försterei bauen → im Umkreis sprießen nach und nach kleine Bäume; Arbeiter
  ernten sie normal.
- KI-Match: Die KI baut bei kahler Basis eine Försterei statt sofort weit zu
  expandieren; kein Bau-Stillstand durch Holzmangel.

## Definition of Done

- [ ] Testsuite grün, `--headless --quit` fehlerfrei
- [ ] Manuelle Prüfung bestanden
- [ ] PROGRESS.md ergänzt, Checkbox 7d in [00_overview.md](00_overview.md) abgehakt
- [ ] `git add -A && git commit -m "Phase 7d: Foersterei & Baum-Ertrag 1/2/3/4" && git push`
