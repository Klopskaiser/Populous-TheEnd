# Phase 7e — 8 Sprite-Blickrichtungen

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

Einheiten-Sprites zeigen **8 Blickrichtungen** statt 4: zusätzlich zu
front/back/left/right die vier Diagonalen — weichere Übergänge beim Drehen
der Kamera und beim Richtungswechsel der Einheiten.

## Voraussetzungen

Phase 2/3f-Rendering: 4-Ansichten-System (`<anim>_<view>`), zentralisiert in
`Unit.view_index(facing, cam_forward, cam_right)` (unit.gd, 45°-Grenzen,
Rückgabe 0–3), `PlaceholderSprites.VIEWS` + Frame-Generierung,
`UnitRenderer`-Atlas (`build_atlas`: kind → anim → `views[view]` →
`[start, count, fps]`). Schamanin-Porträt nutzt separat
`make_frames`-Frontansicht (unberührt).

## Deliverables

| Bereich | Inhalt |
|---|---|
| `Unit.view_index` | 4 → **8 Sektoren** (22,5°-Grenzen), Rückgabe **0–7**; Zuordnung über Winkel aus `atan2(dot_right, dot_forward)` statt Schwellen-Kaskade — **reine Arithmetik, keine neuen Funktionsaufrufe** (Hot-Path-Regel aus Phase 7b: läuft pro Einheit pro Frame). Indizes: 0 = front, 1 = back, 2 = right, 3 = left (Kompatibilität), 4–7 = front_right, front_left, back_right, back_left. `view_suffix`-Wrapper folgt |
| `PlaceholderSprites` | `VIEWS` um die 4 Diagonalen erweitert; **Diagonal-Frames prozedural**: Mischung aus Seiten- und Front-/Rückansicht (z. B. front_right = 1 Auge versetzt + halber Haaransatz; gespiegelte Varianten für links). Sonder-Dekorationen (Schamanin-Haar/Kleid, Trage-/Jump-Posen) für die Diagonalen nachziehen oder auf die nächste Kardinale zurückfallen. **Fallback-Kette:** `<anim>_<diag>` → nächste Kardinale → `<anim>_front` → `idle_front` |
| `UnitRenderer` / `build_atlas` | `views`-Tabelle je Anim 4 → **8** Einträge; Atlas verdoppelt sich (~2×) — Texturgröße prüfen (Kapazität/`Image`-Limits, aktuell unkritisch bei 16×24-Frames). Zugriffscode `views[view]` bleibt unverändert; `Unit.view_index` liefert direkt den Tabellenindex |
| Tests | `tests/test_unit_logic.gd`: `view_index`-Sektoren (8 Richtungen inkl. Grenzwinkel, Kamera gedreht), Fallback-Kette; bestehende 4-Richtungs-Tests anpassen |

## Umsetzungsschritte

1. `view_index` auf 8 Sektoren + Tests (bestehende 4er-Tests migrieren).
2. `PlaceholderSprites`: Diagonal-Frames + `VIEWS` + Fallbacks.
3. Atlas-Erweiterung im `UnitRenderer` (+ `--headless --quit` lädt den
   größeren Atlas fehlerfrei).
4. Optische Prüfung im Spiel (alle Einheitentypen einmal umrunden).
5. PROGRESS.md, Commit/Push.

## Tests

- `view_index`: 8 Richtungen bei Standard-Kamera (N/S/O/W + Diagonalen),
  Grenzwinkel (22,5°-Kanten), gedrehte Kamera (45°/90°), Stillstand
  (`facing`-Länge 0 → front), Kompatibilität der Indizes 0–3.
- Atlas: Tabelle enthält je Anim 8 View-Einträge; Fallback für Anims ohne
  Diagonale (falls Sonderposen kardinal bleiben) liefert gültige Frames.

## Manuelle Prüfung

- Kamera per Q/E um stehende und laufende Einheiten drehen: 8 klar
  unterscheidbare Ansichten, kein Flackern an den Sektorgrenzen, kein
  Frame-Neustart beim Ansichtswechsel.
- Alle Typen prüfen (Brave, Krieger, Feuerkrieger, Prediger, Schamanin —
  inkl. Trage-/Hack-/Jump-Posen der Braves und Schamanin-Silhouette).
- Stresstest F9: Performance unverändert (Ansichtswahl kostet nicht mehr).

## Definition of Done

- [ ] Testsuite grün, `--headless --quit` fehlerfrei
- [ ] Manuelle Prüfung bestanden (8 Ansichten, keine Perf-Regression)
- [ ] PROGRESS.md ergänzt, Checkbox 7e in [00_overview.md](00_overview.md) abgehakt
- [ ] `git add -A && git commit -m "Phase 7e: 8 Sprite-Blickrichtungen" && git push`
