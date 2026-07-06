# Phase 7d — Wirtschaft: Förster-Gebäude, Baum-Ertrag 1/2/3/4, Setzlinge, Feuer & Tornado

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

Wirtschafts- und Umweltausbau:

1. **Baum-Ertrag** der vier Wachstumsstufen liefert **1/2/3/4 Holz** (bisher
   1/1/2/3 — die Stufen ergeben damit spürbar mehr Sinn).
2. Neues Gebäude **Försterei** mit **vier Arbeiterplätzen**, das aktiv
   **Setzlinge** in seinem Umkreis pflanzt — nachhaltige Holzversorgung ohne
   Expansion. Läuft auf **Mana-Upkeep**.
3. **Setzling-Stufe (Stufe 0)**: gepflanzte Bäume starten mit **0 Holz** und
   wachsen erst zu einem normalen Baum heran.
4. **Randomisiertes Baumwachstum**: Bäume wachsen in zufälligen Intervallen
   (gleicher Mittelwert wie bisher) statt streng getaktet.
5. **Bäume und Holzstapel können brennen**: Feuerzauber und Lava setzen sie in
   Brand (komplett zerstört, mit Brand-Animation).
6. **Tornado erfasst Bäume und Holzstapel**: Bäume werden zerstört, Holzstapel
   werden mit halbem Holz **ausgespuckt** (weggeschleudert).

## Voraussetzungen

Phase 3b/3c-Wirtschaft: `TreeResource` (Stufen/`YIELDS`/`harvest_one`
-Herabstufung/Ernte-Slots/`grow_tick`), `TreeManager` (`spawn_tree`,
`MIN_SPACING`, Dichte-/Vermehrungslogik, `MAX_TREES`, `_reproduce`,
`nearest`/`claim`-Queries), `WoodPile`/`WoodPileManager`, Bau-Pipeline,
Baumenü. Phase 7b/5-Training: `TrainingBuilding` (Warteschlange, „Brave betritt
Gebäude → aus Welt entfernt, lebt weiter, zählt zur Bevölkerung", Rally-Point).
Phase 7c-Feuer/Lava: `Unit.ignite()`/`is_burning()`/`_tick_burning`,
`FireballBolt`/`Firestorm`/`LavaFlow` (nutzen `get_units_in_radius` bzw.
`CONTACT_RADIUS`), `TornadoVortex` (`_wreck_buildings`, `_pick_up_units`),
`SpellContext` (führt bereits `tree_manager` und `wood_pile_manager`).

---

## Teil A — Baum-Ertrag & Setzling-Stufe (`scripts/core/tree_resource.gd`)

Die vier bisherigen Stufen bekommen die Erträge **1/2/3/4**, und **vor** ihnen
wird eine **Setzling-Stufe 0 mit 0 Holz** eingezogen. Damit hat der Baum **fünf
Stufen** (0 = Setzling, 1–4 = die bisherigen vier):

| Konstante | alt | neu |
|---|---|---|
| `MAX_STAGE` | 3 | **4** |
| `YIELDS` | `[1,1,2,3]` | **`[0, 1, 2, 3, 4]`** |
| `STAGE_SCALES` | `[0.35,0.55,0.8,1.0]` | **`[0.12, 0.35, 0.55, 0.8, 1.0]`** (Stufe 0 = winzig) |

**Folgeanpassungen:**

- **Setzling-Optik (Stufe 0):** kleiner **senkrechter Stock im Boden**, kein
  Kronen-Kegel — bei `set_stage(0)` nur den Stamm (dünner, niedriger Zylinder)
  zeigen, die Krone ausblenden. Ab Stufe 1 die bisherigen Visuals.
- **Kein Holz auf Stufe 0:** `wood_yield()` liefert `0`; `can_claim()` gibt
  `false` (Slots = Restholz = 0 → Setzlinge sind **nicht** erntbar). Ein Brave
  wählt einen Setzling nie als Ernteziel (`_nearest`/`claim_nearest_tree`
  filtern über `can_claim`/`wood_yield` bereits weg).
- **Ernte-Slots:** unverändert „Slots = Restholz" → am großen Baum (Stufe 4)
  jetzt **max. 4** parallele Ernter.
- **Herabstufung `harvest_one`:** logik bleibt („eine Stufe pro Holz"): großer
  Baum = **4 Ernten** (Stufe 4→3→2→1→gefällt). Stufe 0 wird durch Ernten nie
  erreicht (bei Restholz 1 wird gefällt).
- **`chop_time()`-Staffel** an fünf Stufen anpassen (größte Stufe etwas länger);
  Stufe 0 irrelevant (nicht erntbar).

### Randomisiertes Wachstum

`grow_tick` bleibt „bei Ablauf des Timers eine Stufe wachsen", aber der Timer
wird nach jedem Wachstum auf einen **zufälligen** Wert um den bisherigen
Mittelwert gesetzt statt exakt `GROWTH_TIME`:

- Neue Hilfe `_next_growth_time() -> float`: `GROWTH_TIME * randf_range(0.5, 1.5)`
  (Mittelwert = `GROWTH_TIME`, unverändert). Beim Reset in `grow_tick` und beim
  Init `growth_timer` damit belegen (eigener `RandomNumberGenerator` in der
  Ressource, damit Tests deterministisch seedbar bleiben).
- Gilt für **alle** Bäume (Setzling → Stufe 1 → … → Stufe 4), Verhalten ist nur
  weniger gleichgetaktet; der durchschnittliche Zuwachs bleibt gleich.

### Setzlinge vermehren sich nicht

Setzlinge (Stufe 0) dürfen **nicht** als Vermehrungs-Eltern dienen („in dieser
Wachstumsphase keine Vermehrung"). In `TreeManager._reproduce` Eltern mit
`stage == 0` überspringen. **Natürliche Vermehrung** sprießt weiterhin als
kleiner **Stufe-1**-Baum (nicht als Setzling): `_sprout_near` ruft
`spawn_tree(c, 1)` statt `spawn_tree(c, 0)` — die Wild-Wirtschaft bleibt damit
identisch zu vorher, die Setzling-Stufe ist der Försterei vorbehalten. Die
deterministische Startverteilung `spawn_trees` würfelt weiter Stufen
`1..MAX_STAGE` (nie 0).

---

## Teil B — Försterei mit Arbeiterplätzen

`scripts/buildings/forester.gd` + `scenes/buildings/forester.tscn`, `extends
Building` (**nicht** `TrainingBuilding` — kein Warteschlangen-/Graduierungs-
modell, aber dessen „Brave betritt Gebäude"-Muster wiederverwenden).

**Eckdaten:**

| Eigenschaft | Wert |
|---|---|
| `display_name` | „Försterei" |
| Holzkosten | **20** |
| Footprint | 3×3 |
| HP | ~250 |
| Arbeiterplätze | **4** |
| Reichweite (Pflanzgebiet) | **11×11 Felder** = Chebyshev-Radius **5** um das Gebäude |
| Pflanztempo (4 aktive Arbeiter) | **1 Setzling / 15 s** |
| Mana-Upkeep | **2 Mana/s je aktivem Arbeiter** |
| Max. Bäume im Gebiet | **30** (oder wenn kein Platz frei) |

### Arbeiterplätze & Zuweisung

- **Zuweisung:** Rechtsklick eines selektierten Braves auf die Försterei weist
  ihn einem **freien Platz** zu (analog zum Trainingsbefehl `Brave.order_train`
  → neue `Brave.order_forester(forester)` bzw. Erweiterung der Gebäude-
  Rechtsklick-Zielauflösung in `TribeCommands`/`Brave`). Der Brave läuft zum
  Gebäude und **geht hinein**: `unit_manager.remove_from_world(brave)`, bleibt am
  Leben und zählt zur Bevölkerung (wie der Trainee im `TrainingBuilding`). Ist
  kein Platz frei, wird der Befehl ignoriert (kein Einreihen).
- **Insassen-Anzeige:** Bei **Mouseover ODER Auswahl** der Försterei die vier
  Plätze anzeigen (belegt/frei), z. B. 4 Pips/Slot-Icons im
  Auswahl-/Info-Panel (`Sidebar`/Selektions-UI, siehe Teil D). Ein besetzter
  Platz zeigt an, dass ein Brave drinsteckt.
- **Rausschicken:** **Klick auf einen besetzten Platz** entlässt genau diesen
  Brave: `forester.eject_worker(slot_index)` → Brave wird an einer freien
  begehbaren Randzelle wieder in die Welt gesetzt (`unit_manager.register`,
  `brave.leave_forester()` analog `cancel_training`), Platz wird frei.

### Pflanzlogik (`_tick_active`, nur wenn `is_usable()`)

- **Aktive Arbeiter:** Ein besetzter Platz ist **aktiv**, solange der Stamm den
  Mana-Upkeep decken kann. Je Tick: benötigtes Mana = `2.0 * aktive_arbeiter *
  delta` von `tribe.mana` abziehen. Reicht das Mana nicht, werden Plätze
  (von hinten) **inaktiv** gesetzt — inaktive Arbeiter kosten kein Mana und
  tragen nicht zum Tempo bei (bleiben aber im Platz sitzen). Sobald wieder Mana
  da ist, werden sie reaktiviert. Mana-Abzug über einen kleinen Helfer an
  `Tribe` (`try_spend_mana(amount) -> bool` bzw. `mana`-Feld direkt, dann
  `_emit_mana()`), damit HUD/Ladungssystem konsistent bleiben.
- **Tempo:** Ziel „4 aktive Arbeiter → 1 Setzling / 15 s", linear skaliert:
  Pflanzintervall = `60.0 / max(aktive_arbeiter, 0)` s (1→60 s, 2→30 s, 3→20 s,
  4→15 s). Bei 0 aktiven Arbeitern: kein Pflanzen. Timer im `_tick_active`
  herunterzählen; bei Ablauf **einen** Pflanzvorgang auslösen.
- **Pflanzort:** freie, begehbare Zelle im **11×11-Feld** (Ringsuche um das
  Gebäude). Bedingungen: `nav_grid.is_cell_walkable`, nicht auf
  Bauplätzen/-Footprints, nicht auf Holzstapeln, und **Mindestabstand zu
  Bestandsbäumen kleiner als beim Wildwuchs** — die Pflanzung darf **dichter**
  stehen: eigener `PLANT_SPACING = 1` (statt `TreeManager.MIN_SPACING = 2`).
  Neue Query in `TreeManager`, z. B.
  `can_plant_at(cell, spacing) -> bool` und `trees_in_area(center, radius) ->
  int` (Chebyshev), damit die Försterei prüfen kann.
- **Gebiets-Deckel:** pflanzt nur, wenn im 11×11-Feld **< 30 Bäume** stehen
  **und** eine gültige Zelle frei ist; sonst pausiert die Pflanzung (kein
  Timer-Verbrauch). Kein globaler `MAX_TREES`-Konflikt: den globalen Deckel auf
  **400** anheben, damit Förster mehrerer Stämme sich nicht gegenseitig
  aushungern (natürliche Vermehrung bleibt unauffällig, nutzt denselben Deckel).
- **Setzling setzen:** `tree_manager.spawn_tree(cell, 0)` (Stufe 0, 0 Holz).

### Pflanz-Animation (Arbeiter tritt heraus)

Der Setzling wird **sichtbar von einem Arbeiter gepflanzt**:

- Beim ausgelösten Pflanzvorgang tritt **ein** aktiver Arbeiter kurz aus der
  Försterei heraus: `unit_manager.register(brave)` an einer Randzelle, Brave
  bekommt einen **Pflanz-Auftrag** zur Zielzelle (neuer Unit-State `PLANT` bzw.
  Wiederverwendung des Bewegungs-+Kurzaktions-Musters):
  1. läuft zur Zielzelle (Walk),
  2. **kurzes Hinknien** (Knie-Pose — als Platzhalter die vorhandene
     `Cast`/`Attack`-Animation kurz abspielen bzw. eine simple Crouch-Pose;
     Dauer ~0.8 s),
  3. Setzling erscheint (`spawn_tree(cell, 0)`),
  4. läuft zurück zur Försterei und **geht wieder hinein**
     (`remove_from_world`), Platz bleibt die ganze Zeit als besetzt gezählt.
- Solange der Arbeiter draußen pflanzt, zählt sein Platz weiter als besetzt/
  aktiv (Mana-Upkeep läuft weiter). Nur ein Arbeiter pflanzt gleichzeitig; die
  übrigen bleiben drin.
- **Robustheit:** Stirbt/entkommt der Arbeiter unterwegs (Tornado, Feuer,
  Rausschicken), wird der Platz frei und der Pflanzvorgang abgebrochen; kein
  „Geister-Setzling".

### Beschädigung / Zerstörung

- **Beschädigt (Stufe ≥ 1, `is_usable() == false`):** keine Pflanzung, kein
  Mana-Upkeep; Arbeiter bleiben drin (wie Trainee-Handling), Pflanzen ruht bis
  zur Reparatur.
- **Zerstört (`destroy`):** alle Insassen freigeben (an Randzellen zurück in die
  Welt, `super.destroy()` analog `TrainingBuilding.destroy`), ein evtl. gerade
  draußen pflanzender Arbeiter läuft nicht zurück, sondern bleibt in der Welt.

---

## Teil C — Bäume & Holzstapel brennen

### Bäume (`TreeResource`)

- Neue `ignite()` / `is_burning()` (Muster wie `Unit.ignite`): setzt den Baum in
  Brand → **kurze Brand-Animation** (prozedural: flackernd orange-emissive
  Krone, dann Schrumpfen/Verkohlen ~1.5–2 s), danach **komplett zerstört** —
  über den `felled`-Pfad des `TreeManager` deregistrieren und `queue_free`. Ein
  brennender Baum liefert **kein** Holz und ist nicht mehr erntbar
  (`can_claim` → false, laufende Ernte-Claims lösen sich, Ernter suchen neu).
- Brand-Tick über den `TreeManager.tick` mitlaufen lassen (kein eigener
  `_process` je Baum), analog `grow_tick`.

### Holzstapel (`WoodPile`)

- Neue `ignite()` / `is_burning()`: **Brand-Animation** (Sprite flackert/
  verkohlt ~1.5 s), danach Stapel entfernt (Holz verloren) — über den
  `WoodPileManager` deregistrieren (`_drain` bis 0 bzw. eigener `remove_pile`).
  `Events.stockpile_changed` emittieren.
- Brand-Tick über einen `WoodPileManager`-Tick (`_physics_process`/`tick`), da
  der Manager bisher keinen Tick hat → kleinen Tick ergänzen.

### Feuerquellen zünden Bäume/Stapel

Feuerzauber, Lava **und Blitz** zünden Bäume und Stapel im Wirkbereich, analog
zum bestehenden `Unit.ignite`:

- **`LavaFlow._ignite_touching_units`** erweitern → auch Bäume/Stapel im
  `CONTACT_RADIUS` der Segmente zünden. Braucht `tree_manager` +
  `wood_pile_manager` (werden schon in `SpellContext` geführt → beim Erzeugen
  der `LavaFlow` mitgeben).
- **`FireballBolt._explode`** (Einschlag, `SPLASH_RADIUS`) → Bäume/Stapel im
  Radius zünden.
- **`Firestorm`** (Feuerregen, Phase 7c): die einzelnen Bolts/Einschläge zünden
  im Einschlagradius ebenfalls.
- **`LightningSpell.execute`** (Blitz): am Einschlagpunkt (`target`) Bäume/Stapel
  in einem kleinen Zündradius (z. B. `TARGET_RADIUS`) entflammen. Der Blitz hat
  `ctx` direkt zur Hand → `ctx.tree_manager.ignite_in_radius(target, r)` /
  `ctx.wood_pile_manager.ignite_in_radius(target, r)` (Guards, wenn null). Zündet
  zusätzlich zum bisherigen Gebäude-/Einheiten-Effekt, unabhängig davon, ob am
  Zielpunkt ein Gebäude oder eine Einheit getroffen wurde.
- Neue Manager-Helfer:
  `TreeManager.ignite_in_radius(pos, radius)` und
  `WoodPileManager.ignite_in_radius(pos, radius)` (setzen alle betroffenen
  Objekte in Brand — Doppel-Zündung ist idempotent, `is_burning`-Guard).
- **`SpellContext`** und die Zauber-Ausführungen so anpassen, dass die
  Feuer-Entities `tree_manager`/`wood_pile_manager` erhalten (in den `setup`-
  Aufrufen mitreichen). In Headless-Tests dürfen beide `null` sein (Guards).

### Tornado (`TornadoVortex`)

- **Bäume:** im `_pick_up_units`-Radius (`RADIUS`) erfasste Bäume werden
  **zerstört** (kein Wegschleudern nötig) — neuer Aufruf
  `tree_manager.destroy_in_radius(position, RADIUS)` (deregistrieren +
  `queue_free`, ohne Holzausschüttung). `tree_manager` an den Tornado
  durchreichen (wie `building_manager`).
- **Holzstapel:** im Radius erfasste Stapel werden **herumgeschleudert, ohne
  Holz zu verlieren**: Stapel vom aktuellen Ort entfernen und an einer
  zufälligen begehbaren Zelle in der Nähe (Wurfweite) einen Stapel mit dem
  **vollen** Holz wieder ablegen (`wood_pile_manager.deposit(landing, amount)`
  nach Entfernen des Originals — `deposit` verteilt ggf. auf mehrere Stapel à
  max. 5, Gesamtmenge bleibt gleich). `wood_pile_manager` an den Tornado
  durchreichen. Kein Holzverlust; nur die Position ändert sich.

---

## Teil D — UI, KI, Balance

| Bereich | Inhalt |
|---|---|
| **Baumenü** | Eintrag „Försterei (20 Holz)" in `Sidebar.default_build_entries()`; neues 24×24-Icon (`forester`, z. B. Setzling) in `ui_theme.gd` |
| **Insassen-Panel** | Auswahl/Mouseover der Försterei zeigt die 4 Arbeiterplätze (belegt/frei); Klick auf besetzten Platz schickt den Brave raus (siehe Teil B). Anbindung an die bestehende Selektions-/Sidebar-UI |
| **KI** | `AIController._next_building_scene`: nach dem Grundausbau eine **Försterei, wenn die Holzversorgung um die Basis dünn wird** (z. B. < 6 Bäume im ~22-m-Umkreis des Basis-Ankers) und noch keine (nutzbare/geplante) Försterei existiert — greift VOR der Expansion zum fernen Wald. Danach Braves als Arbeiter zuweisen |
| **Balance** | 4er-Bäume liefern mehr Holz: `Main.SKIRMISH_BASE_TREES` 16 → **12** als Startwert (Feinbalance Phase 8) |

---

## Umsetzungsschritte

1. **Teil A:** `MAX_STAGE`/`YIELDS`/`STAGE_SCALES`, Setzling-Optik, `wood_yield`/
   `can_claim`/`chop_time`/`harvest_one` an 5 Stufen; randomisiertes Wachstum;
   `_reproduce`/`_sprout_near`/`spawn_trees` anpassen. Bestands-Tests fixen
   (mehrere Phase-3-Tests referenzieren 1/1/2/3 und `MAX_STAGE == 3`).
2. **Teil B:** Försterei-Gebäude + Szene, Arbeiterplatz-Modell, Mana-Upkeep,
   Pflanzlogik + `TreeManager`-Queries (`can_plant_at`/`trees_in_area`),
   Pflanz-Animation (Arbeiter tritt heraus), Rausschicken. `MAX_TREES` → 400.
3. **Teil C:** `TreeResource.ignite`/`WoodPile.ignite` + Brand-Ticks;
   `TreeManager`/`WoodPileManager` `ignite_in_radius`/`destroy_in_radius`;
   Feuerquellen (`LavaFlow`, `FireballBolt`, `Firestorm`) + Tornado anbinden;
   `SpellContext`-Durchreichung.
4. **Teil D:** UI-Eintrag + Icon, Insassen-Panel, KI-Regel, `SKIRMISH_BASE_TREES`.
5. Kurzer KI-Sim-Lauf (Basisaufbau darf nicht stallen — Erkenntnis aus Phase 7:
   zu wenig Holz stallte die Lager).
6. Verifikation, PROGRESS.md, Commit/Push.

## Tests (`tests/test_economy.gd`, ggf. neues `tests/test_forester.gd`)

- **Ertrag/Stufen:** Stufen liefern 0/1/2/3/4; Setzling (Stufe 0) hat 0 Holz und
  ist nicht claimbar; großer Baum (Stufe 4) = 4 Einzel-Ernten mit Herabstufung
  4→3→2→1→weg; 4 parallele Ernte-Slots am großen Baum.
- **Wachstum:** Setzling wächst nach Timer auf Stufe 1 (dann normale Regeln);
  randomisierter Timer liegt im Bereich `[0.5,1.5]·GROWTH_TIME`; Setzling
  vermehrt sich nicht (`_reproduce` überspringt Stufe-0-Eltern); natürliche
  Vermehrung sprießt als Stufe 1.
- **Försterei — Pflanzen:** platziert + `pre_built`, 1 Arbeiter zugewiesen →
  nach `60 s`-Tick ≥ 1 neuer Setzling (Stufe 0) im 11×11-Feld; 4 Arbeiter →
  ~4× so schnell; Gebiets-Deckel 30 erreicht → pflanzt NICHT; kein freier Platz
  im Feld → pflanzt NICHT; dichtere Pflanzung (`PLANT_SPACING 1`) erlaubt.
- **Försterei — Mana/Arbeiter:** Mana-Upkeep zieht `2·aktive_arbeiter`/s ab; bei
  leerem Mana werden Arbeiter inaktiv (kein Pflanzen, kein Abzug) und bei
  wieder vorhandenem Mana reaktiviert; beschädigt (Stufe ≥ 1) → pflanzt nicht,
  kein Upkeep; Rausschicken gibt Brave frei und leert den Platz; `destroy` gibt
  alle Insassen frei.
- **Feuer:** `TreeResource.ignite` → Baum brennt, liefert kein Holz, wird
  entfernt; `WoodPile.ignite` → Stapel brennt und verschwindet;
  `ignite_in_radius` zündet nur im Radius; `is_burning`-Guard verhindert
  Doppelzündung.
- **Tornado:** Baum im Radius → zerstört (aus Registry entfernt); Holzstapel im
  Radius → an eine andere Zelle versetzt, Gesamtholz bleibt unverändert (kein
  Verlust).
- **KI:** Basis ohne Bäume im Umkreis + Grundausbau fertig →
  `_next_building_scene` liefert die Försterei (vor der Expansion).

## Manuelle Prüfung

- Großer Baum gibt sichtbar 4 Holz (4 Hack-Zyklen, Baum schrumpft je Stufe).
- Försterei bauen, Braves per Rechtsklick zuweisen → Insassen-Pips zeigen die
  Plätze; ein Arbeiter tritt heraus, kniet, pflanzt einen Setzling (kleiner
  Stock), geht zurück; mit mehr Arbeitern wird spürbar schneller gepflanzt;
  Mana sinkt sichtbar (Upkeep). Klick auf besetzten Platz schickt den Brave
  raus. Setzlinge wachsen zu normalen Bäumen und werden dann geerntet.
- Feuerball/Feuerregen/Lava/Blitz auf einen Wald → Bäume fangen Feuer und
  verbrennen; ein Holzstapel im Feuer brennt ab.
- Tornado über Wald + Holzstapel → Bäume verschwinden, ein Stapel wird
  weggeschleudert (landet woanders), behält aber sein Holz.
- KI-Match: KI baut bei kahler Basis eine Försterei statt sofort weit zu
  expandieren; kein Bau-Stillstand durch Holzmangel.

## Definition of Done

- [x] Testsuite grün (1033), `--headless --quit` fehlerfrei
- [ ] Manuelle Prüfung bestanden *(ausstehend — durch Nutzer)*
- [x] PROGRESS.md ergänzt, Checkbox 7d in [00_overview.md](00_overview.md) abgehakt
- [x] `git add -A && git commit -m "Phase 7d: Foersterei, Setzlinge, Baumbrand & Tornado-Baumschaden" && git push`
