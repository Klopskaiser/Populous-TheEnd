# Phase 7g — Gebäudezerstörung durch Einheiten (Sturmangriff)

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

Einheiten können gegnerische Gebäude zerstören — per **Rechtsklick-Befehl**,
im **Idle-Scan** und im **Attack-Move** (Gebäude dort immer als NIEDRIGSTE
Priorität). Zwei Angriffsarten: **Nahkampfsturm** (Angreifer dringen durch den
Eingang ein, werfen Insassen raus und demolieren von innen) und **Fernkampf**
(Feuerkrieger beschießen das Gebäude, halb so effektiv). Damit braucht das
Schleifen einer Basis keine Zauber mehr.

## Voraussetzungen

- Gebäude-Schadenssystem aus Phase 6 (`take_damage`/`destruction_stage`/
  `apply_destruction_stages`, Fragil-Regel für Baustellen, Trainee-Auswurf
  in `TrainingBuilding._on_disabled`).
- Trainee-Mechanik als „im Gebäude"-Vorlage (`UnitManager.remove_from_world`
  + `register`), `edge_spawn_position`, `entrance_world`.
- Kampfsystem (Melee-Slots MAX 3, `_scan_for_enemy` mit Kandidaten-Cap,
  Attack-Move), Feuerkrieger-Fernkampf (`fireball.gd`-Projektil).

## Kernregeln (vom Nutzer festgelegt)

- Rechtsklick auf Feindgebäude = Angriffsbefehl für die Selektion.
- Idle-Scan und Attack-Move zählen Gebäude als Ziele, aber **immer mit
  niedrigster Priorität** (erst wenn keine Feindeinheit in Reichweite ist).
- **Nahkampf** (alle außer Feuerkrieger): max. **15** Nahkämpfer pro Gebäude
  (Wachturm aus 7h: max. **5** — Konstante am Gebäude).
- **Sturm-Ablauf:** Angreifer laufen durch den **Eingang hinein**; alle
  **Insassen** (Trainees, später Turm-Besatzung) werden **nach draußen
  geschubst** und dort verprügelt (normale 3er-Melee-Slot-Regel); die übrigen
  Angreifer bleiben **drinnen und demolieren**. Während der Demolierung
  **wackelt das Gebäude in langsamen Schwingbewegungen**, das Schadenslevel
  steigt; **mehr Demolierer = schnellerer Abriss**.
- **Fernkampf** (Feuerkrieger): Feuerbälle aufs Gebäude, **halb so effektiv**
  wie Nahkampfschaden. Erreicht das Gebäude **durch Fernkampf allein**
  Schadensstufe 1, **fliegen die Insassen heraus und sterben sofort**; sind
  Nahkämpfer beteiligt, wurden die Insassen bereits beim Sturmbeginn (lebend)
  rausgeworfen.

## Dokumentierte Auslegungen (bei Bedarf beim Testen korrigieren)

- **Demolierer im Gebäude sind nicht angreifbar** (sie sind aus der Welt wie
  Trainees). Konter des Verteidigers: den Sturm VOR dem Eingang abfangen bzw.
  die draußen prügelnden Angreifer stellen. Kein „Gegensturm" in V1.
- **Braves** stürmen nur auf expliziten Befehl mit (Rechtsklick); ihre
  Idle-/Aggro-Passivität bleibt (3-m-Wache zählt Gebäude nicht).
- **Zauber-Schaden** wirft Insassen weiterhin LEBEND aus (bestehende
  Phase-6-Regel unverändert); nur der Fernkampf-Stufe-1-Auswurf tötet.
- Demolierte eigene Leute: Wird das Gebäude zerstört, treten die Demolierer
  am Rand wieder aus (lebend, IDLE) — sie reißen es kontrolliert ab.
- Selektion: Demolierer im Gebäude sind (wie Trainees) nicht selektierbar;
  sie kommen bei Zerstörung oder Gebäude-Stufenauswurf von selbst wieder raus.

## Deliverables

| Bereich | Datei(en) | Inhalt |
|---|---|---|
| **Gebäude-Ziel & Slots** | `building.gd` | `max_melee_raiders() -> int` (Basis 15, Turm überschreibt 5), Raider-Registry (`raiders: Array` = Einheiten drinnen, analog Trainee untypisiert), `raid_tick`-Schaden: `RAID_DPS_PER_RAIDER` (Startwert 6 HP/s, Balance Phase 8) × Demoliererzahl; **Wackel-Visual**: `_mesh_root` schwingt per Sinus (Rotation ±2°, ~0,8 Hz) solange `raiders > 0` (nur in-game, `_process`); Auswurf-Hooks: `eject_occupants(killed: bool)` — Stufe-1-durch-Fernkampf → `killed = true` (Insassen sterben am Auswurfpunkt), Sturmbeginn → `killed = false` (rausgeschubst + Mini-Roll) |
| **Einheiten-Angriff** | `unit.gd` | `attack_building`-Ziel (untypisiert) + `order_attack_building(b)` (alle Einheitentypen; `can_take_orders`-Guard). Neuer State-Zweig im ATTACK-Tick: Nahkämpfer laufen zum **Eingang**, treten ein (`Building.admit_raider` → `remove_from_world`, bis `max_melee_raiders`; Überzählige warten am Gebäude wie beim vollen Melee-Ring); Feuerkrieger stehen in `FIRE_RANGE` und feuern aufs Gebäude (Projektil-Gebäudetreffer: **halber Nahkampf-DPS-Gegenwert**, als HP-Schaden). **Scan-Fallback:** `_engage_on_sight`/Idle-Scan: erst Einheiten (bestehend), NUR wenn keine gefunden → gedrosselter Gebäudescan (`_scan_for_enemy_building`, Feindgebäude im Aggro-Radius, über `BuildingManager.buildings` mit Kandidaten-Cap — Hot-Path-Regel!) |
| **Sturm-Koordination** | `building.gd` / `tribe_commands.gd` | Sturmbeginn (erster Raider tritt ein): `eject_occupants(false)` — Trainees/Besatzung an `edge_spawn_position` + Schubs (`displace` + Mini-Roll); die wartenden Angreifer greifen die Rausgeworfenen automatisch an (normale Aggro/3er-Slots — kein Sondercode nötig, die stehen ja daneben). `TribeCommands.order_attack_building(units, building)`: verteilt Nahkämpfer (bis Limit) und Feuerkrieger (Fernkampf), Braves nur hier (expliziter Befehl) |
| **Rechtsklick** | `selection_manager.gd` | `_dispatch_context_command`: Rechtsklick auf **Feind**gebäude → `order_attack_building` (bisher wurden nur eigene Gebäude behandelt) |
| **Auswurf-Regeln** | `training_building.gd` (+ 7h-Turm) | Fernkampf-Stufe-1: Insassen sterben (`eject_occupants(true)` statt des lebenden `_on_disabled`-Auswurfs — nur wenn der Stufenwechsel durch Einheiten-Fernkampf kam: `last_damage_source`-Flag am Gebäude); Zauber behalten den lebenden Auswurf |
| **KI** | — | Keine Heuristik-Änderung nötig: der Attack-Move der Wellen findet Gebäude jetzt von selbst (niedrigste Priorität → erst Verteidiger, dann Basis schleifen). Sim-Lauf muss zeigen, dass Matches OHNE Zauber-Belagerung konvergieren |
| **Tests** | `tests/test_building_assault.gd` (neu) | siehe unten |

## Umsetzungsschritte

1. Gebäude-Raider-Registry + Demolier-Schaden + Auswurf-Hooks (Datenebene) + Tests.
2. `order_attack_building` + Nahkampf-Eintritt/Überzählige + Feuerkrieger-Fernkampf + Tests.
3. Scan-Fallback (Idle/Attack-Move, niedrigste Priorität, gedrosselt) + Tests.
4. Rechtsklick-Befehl + Sturm-Auswurf + Prügelei draußen (Integration).
5. Wackel-Visual (in-game).
6. KI-Sim-Lauf (Matches konvergieren über Einheiten-Belagerung), Verifikation,
   PROGRESS.md, Commit/Push.

## Tests (`tests/test_building_assault.gd`)

- **Slots:** 20 Krieger stürmen → genau 15 drinnen, 5 warten; Turm-Override 5
  (Stub/7h). Demolier-Schaden skaliert mit Raiderzahl (2× Raider ≈ 2× DPS).
- **Sturm:** Gebäude mit Trainee → erster Raider tritt ein → Trainee steht
  draußen (lebend, Registry), wird von wartenden Angreifern attackiert.
- **Demolierung bis Zerstörung:** Gebäude fällt, Raider treten lebend aus
  (wieder in Registry/Welt, IDLE), NavGrid-Footprint frei.
- **Fernkampf:** Feuerkrieger-Beschuss macht halben DPS-Gegenwert; Stufe 1
  durch Fernkampf → Insassen tot; mit beteiligten Nahkämpfern wurden sie
  vorher lebend ausgeworfen (kein Doppel-Auswurf).
- **Priorität:** Attack-Move mit Feindeinheit UND Gebäude in Reichweite →
  Einheit zuerst; nur Gebäude in Reichweite → Gebäude wird angegriffen; Brave
  im Idle ignoriert Gebäude.
- **Rechtsklick-Routing:** Feindgebäude → Angriff; eigenes Gebäude →
  weiterhin Reparatur/Training/Beten (bestehende Pfade unverändert).

## Manuelle Prüfung

- Trupp per Rechtsklick auf eine Feindhütte: Nahkämpfer verschwinden im
  Eingang, das Gebäude wackelt und nimmt sichtbar Stufen, Trainees purzeln
  raus und werden verprügelt; bei Zerstörung kommen die eigenen Leute raus.
- Feuerkrieger allein beschießen ein bemanntes Gebäude → bei Stufe 1 fliegen
  die Insassen tot heraus.
- Attack-Move durch eine Basis: erst fallen die Verteidiger, dann demolieren
  die Truppen die Gebäude (ohne weiteren Befehl).
- KI-Match: Die KI schleift die Spielerbasis jetzt auch ohne Zauber.

## Definition of Done

- [ ] Testsuite grün, `--headless --quit` fehlerfrei
- [ ] Manuelle Prüfung bestanden
- [ ] PROGRESS.md ergänzt, Checkbox 7g in [00_overview.md](00_overview.md) abgehakt
- [ ] `git add -A && git commit -m "Phase 7g: Gebaeudezerstoerung durch Einheiten" && git push`
