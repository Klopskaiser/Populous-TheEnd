# Phase 7f — Belagerungswaffe & Werkstatt

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

Eine neue Einheit **Belagerungswaffe** (Katapult): in einer neuen **Werkstatt**
aus Holz gefertigt und mit Braves bemannt, **langsam**, **große Reichweite**;
ihre Geschosse machen **Zerstörungsstufen an Gebäuden UND Flächenschaden an
Einheiten**. Damit können erstmals Einheiten (nicht nur Zauber) Gebäude
zerstören. Bewusst zuletzt in der 7c–7f-Reihe: profitiert von den
8-Richtungs-Sprites (7e) und dem Projektil-/AoE-Code (7c).

## Voraussetzungen

- `TrainingBuilding`-Maschinerie (Queue-Windungen, Slot-Anlauf,
  `_admit_front`/`_finish_one`-Trainee-Swap, Rally, Produktionsbalken).
- Holz-Absorb-Pipeline der Gebäude (`wants_more_wood`/`_absorb_piles` beim
  Bau, `repair_wood`-Puffer bei Reparatur — Muster für Produktions-Holz).
- `Firewarrior` als Fernkampf-Vorlage (`_tick_attack`-Override, Projektil via
  `UnitManager.register_projectile`), `fireball_bolt.gd` als Parabel-Vorlage.
- Gebäude-Schadenssystem (`apply_destruction_stages`, Fragil-Regel für
  Baustellen), KI-Wellen (`attack_wave_size`), 8-Richtungs-Atlas (7e).

## Deliverables

| Bereich | Datei(en) | Inhalt |
|---|---|---|
| **Werkstatt** | `scripts/buildings/workshop.gd` + `scenes/buildings/workshop.tscn` | „Werkstatt": Holzkosten **15**, Footprint **4×4**, HP ~350, `TrainingBuilding`-Subklasse mit zwei Erweiterungen: (1) **Crew = 2**: erst wenn ZWEI Braves nacheinander eingetreten sind (Queue-Mechanik unverändert, `_admit_front` sammelt bis `CREW_SIZE`), startet die Fertigung; (2) **Produktions-Holz = 8**: je Fertigung werden 8 Holz am Eingang absorbiert (Puffer-Muster der Reparatur) — ohne Holz wartet die Fertigung (`wood_stalled`-Recheck-Muster). `training_time 12 s`, `produces = SIEGE_SCENE`. Population: −2 Braves, +1 Katapult |
| **Einheit** | `scripts/units/siege_engine.gd` + `scenes/units/siege_engine.tscn` | `SiegeEngine` (`unit_kind &"siege"`): **Speed 1,5** (langsamste Einheit), **HP 300**, KEIN Nahkampf (`melee_strength 0`, wehrt sich nicht — braucht Eskorte), panikfähig, konvertierbar? **Nein** (Gerät, kein Gläubiger — `SIT`/Konvertierung immun, dokumentierte Auslegung). `_is_combatant() true` mit eigenem `_tick_attack`: Reichweite **15 m**, Schuss alle **4 s**, steht beim Schießen (Firewarrior-Muster). **Auto-Aggro-Priorität: Gebäude vor Einheiten** (scannt im Attack-Move/Idle zuerst Feindgebäude in Reichweite, dann Einheiten) |
| **Projektil** | `scripts/units/siege_shot.gd` | Steinbrocken in hoher Parabel (Vorlage `fireball_bolt`): am Einschlagpunkt **Gebäude im Trefferfeld +1 Zerstörungsstufe** (`apply_destruction_stages`, Footprint-+1-Suche wie der Blitz) UND **Flächenschaden an Einheiten** (Radius 2 m, ½ Brave-Leben, kleines Wegschleudern). Friendly Fire an Einheiten: JA im Radius (Steine kennen keine Freunde — Positionierung wird taktisch); eigene Gebäude werden NICHT beschädigt (Frustschutz) |
| **Gebäude-Targeting** | `unit.gd`, `tribe_commands.gd`, `selection_manager.gd` | NEU: Einheiten können Gebäude als Angriffsziel haben — minimal-invasiv: `attack_building`-Feld + `order_attack_building(b)` NUR auf `SiegeEngine` (Basisklasse lehnt ab); `TribeCommands.order_attack_building(units, building)` filtert auf SiegeEngines (Rest läuft hin wie bei order_repair-Movers); `SelectionManager._dispatch_context_command`: Rechtsklick auf FEINDGEBÄUDE mit selektierten SiegeEngines = Beschussbefehl (sonst wie bisher Move). `_tick_attack` der SiegeEngine priorisiert `attack_building`, sonst Einheitenziel |
| **Rendering** | `unit_renderer.gd`, `placeholder_sprites.gd` | Kind `&"siege"` in `KINDS` + Placeholder-Silhouette (breiter Holzrahmen + Wurfarm, 8 Richtungen aus 7e; Anims: idle/walk/attack — „attack" = Wurfarm schnellt hoch) |
| **KI** | `ai_controller.gd`, `ai_state.gd` | Werkstatt in `_next_building_scene` (nach dem Tempel, 1× im Grundausbau); Trainings-Mix um `siege` erweitert (Ziel ~10 % bzw. 1 Katapult je Welle ab Welle 2 — `training_kind_order` um vierten Eintrag; Werkstatt-Sonderfall: zieht 2 Braves je Fertigung); ATTACK: SiegeEngines marschieren mit der Welle, ihre Gebäude-Priorität erledigt die Belagerung automatisch |
| **UI** | `sidebar.gd`, `ui_theme.gd` | Baumenü-Eintrag „Werkstatt (15 Holz)" + Icon; Gefolgsleute-Tab-Zeile „Belagerungswaffe"; Doppelklick-Typselektion greift automatisch über `unit_kind` |
| **Tests** | `tests/test_siege.gd` (neu) | siehe unten |

## Umsetzungsschritte

1. `SiegeEngine` + `siege_shot` (Fernkampf auf Einheiten, AoE) headless + Tests.
2. Gebäude-Targeting (order/attack_building-Pfad + Auto-Priorität) + Tests.
3. Werkstatt (Crew 2 + Produktions-Holz) + Tests.
4. Rendering-Kind + UI (Baumenü, Tab).
5. Rechtsklick-Beschussbefehl im SelectionManager.
6. KI-Integration (+ Sim-Lauf: KI baut Werkstatt, Katapulte marschieren mit,
   Gebäude fallen ohne Zauber — Match muss weiter konvergieren).
7. Verifikation, PROGRESS.md, Commit/Push.

## Tests (`tests/test_siege.gd`)

- **Fertigung:** Werkstatt + 2 Braves + 8 Holz am Eingang → nach
  `training_time` existiert 1 SiegeEngine, beide Braves weg (Population −1
  netto); ohne Holz stallt die Fertigung und läuft nach Lieferung weiter;
  1 Brave allein startet nichts.
- **Beschuss:** SiegeEngine + Feindgebäude in 12 m → Schuss → Gebäude +1
  Stufe; Baustelle → sofort zerstört (Fragil-Regel); Einheiten im 2-m-Radius
  des Einschlags nehmen Schaden (auch eigene), eigenes Gebäude bleibt heil.
- **Verhalten:** kein Nahkampf (Feind in 1 m → kein Schlag, sie flieht nicht
  von selbst); Reichweiten-Grenze (16 m → rückt nach, dann schießt);
  Auto-Priorität Gebäude vor Einheit; `order_attack_building` auf Brave/Krieger
  wird abgelehnt.
- **KI:** Grundausbau enthält die Werkstatt; Wellen-Mix enthält `siege`.

## Manuelle Prüfung

- Werkstatt bauen, 2 Braves reinschicken, Holz liegt bereit → Katapult rollt
  raus (langsam, 8 Richtungen sichtbar), läuft zum Rally-Point.
- Rechtsklick auf Feindgebäude → Katapult stellt sich in Reichweite und
  zerlegt es Stufe für Stufe; Einschläge werfen umstehende Einheiten um.
- Katapult ohne Eskorte von Nahkämpfern überrennen lassen → wehrlos (stirbt).
- KI-Match: KI-Wellen bringen Katapulte mit; Spielerbasis verliert Gebäude
  auch ohne feindliche Zauber; Match konvergiert.

## Definition of Done

- [ ] Testsuite grün, `--headless --quit` fehlerfrei
- [ ] Manuelle Prüfung bestanden
- [ ] PROGRESS.md ergänzt, Checkbox 7f in [00_overview.md](00_overview.md) abgehakt
- [ ] `git add -A && git commit -m "Phase 7f: Belagerungswaffe & Werkstatt" && git push`
